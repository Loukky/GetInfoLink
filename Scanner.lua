--[[----------------------------------------------------------------------------
    GetInfoScan - Scanner.lua
    Asynchronous batch scan engine.

    Works in chunks so the client stays responsive:
      * fast path  - item definitions already in the local cache are resolved
                     synchronously, hundreds per tick;
      * slow path  - uncached ids are pushed through a hidden scanning tooltip
                     and re-checked a tick later, which makes the client
                     request the definition from the server.
----------------------------------------------------------------------------]]--

local _, addon = ...
local L = addon.L
local api = addon.api

-- Tunables -------------------------------------------------------------------
local CHUNK_CACHE    = 200   -- ids checked per tick against the local cache
local CHUNK_VERIFY   = 24    -- uncached ids pushed per verification round
local MAX_RESULTS    = 5000  -- hard cap on collected links
local MAX_RETRY      = 1     -- extra verification rounds per id
local DEFAULT_TICK   = 0.1   -- seconds between batches
local REQUEST_BUDGET = 40    -- item definitions the client may be asked for per second

-- Fast path: the engine only resolves item ids that are already cached.
local scanTooltip = CreateFrame("GameTooltip", "GetInfoScanTooltip", nil, "GameTooltipTemplate")
if scanTooltip then
    pcall(scanTooltip.SetOwner, scanTooltip, WorldFrame or UIParent, "ANCHOR_NONE")
    pcall(scanTooltip.Hide, scanTooltip)
end

-- Slow path: ask the client to fetch an item definition.
--
-- On modern clients the tooltip route is gone or restricted, so the Item mixin
-- is preferred and the tooltip is only a last resort. Addons never call the
-- on-demand path directly, so no scan path may raise when it is missing.
local itemFactories = {}
do
    local seen = {}
    local function AddFactory(factory)
        if factory and type(factory.CreateFromItemID) == "function" and not seen[factory] then
            seen[factory] = true
            itemFactories[#itemFactories + 1] = factory
        end
    end
    AddFactory(C_Item and C_Item.Item)
    AddFactory(Item)
end

local function CanContinue(item)
    return item ~= nil and type(item.ContinueOnItemLoad) == "function"
end

-- The callback name moved across client versions, so accept both spellings.
local function ItemContinueMethod(item)
    if type(item.ContinueOnItemLoad) == "function" then return "ContinueOnItemLoad" end
    if type(item.ContinueOnItemLoadForCallback) == "function" then return "ContinueOnItemLoadForCallback" end
    return nil
end

local preloadPath, preloadFactory, preloadMethod
do
    for i = 1, #itemFactories do
        local factory = itemFactories[i]
        local ok, probe = pcall(factory.CreateFromItemID, factory, 1)
        if ok then
            local method = ItemContinueMethod(probe)
            if method then
                preloadPath = "ItemMixin"
                preloadFactory = factory
                preloadMethod = method
                break
            end
        end
    end

    if not preloadPath and scanTooltip and type(scanTooltip.SetItemByID) == "function" then
        preloadPath = "Tooltip"
    end
end

-- ============================================================================
-- State
-- ============================================================================
local state = {
    active    = false,
    paused    = false,
    typeKey   = "item",
    from      = 0,
    to        = 0,
    total     = 0,
    pos       = 0,        -- next id to push through the fast path
    scanned   = 0,        -- ids that reached a verdict
    missing   = 0,        -- ids that reached a "no such entry" verdict
    settled   = {},       -- id -> true, guards against double counting
    slots     = {},       -- id -> 0 unknown / 1 not cached / 2 cached / 3 missing
    pending   = {},       -- ids awaiting a cache check
    retries   = {},       -- retry counter per id
    budget    = REQUEST_BUDGET, -- item load requests still allowed this second
    lastTick  = 0,
    results   = {},       -- { id = , link = , quality = , level = }
    order     = {},       -- result order = ascending id
    dirty     = false,    -- UI needs a repaint
    tick      = DEFAULT_TICK,
    startedAt = 0,
    elapsed   = 0,
    truncated = false,
}

addon.scan = state

-- ============================================================================
-- Forward declarations
-- ============================================================================
local Schedule, Tick
local RecordResult, Settle, Finish

-- ============================================================================
-- Record a hit
-- ============================================================================
RecordResult = function(id, link, quality, level)
    if state.results[id] then return end

    if #state.order >= MAX_RESULTS then
        if not state.truncated then
            state.truncated = true
            addon:Print(("|cffff5555[GetInfoScan]|r result limit reached (%d), further links are dropped."):format(MAX_RESULTS))
        end
        return
    end

    state.results[id] = { id = id, link = link, quality = quality or 1, level = level or 0 }
    state.order[#state.order + 1] = id
    state.dirty = true

    -- No chat line per hit here. The "announce hits in chat" box that used to
    -- guard this read addon.DB.options, which nothing ever assigned, so the
    -- condition could never be true however the box was set.
end

-- ============================================================================
-- Scheduling
-- ============================================================================
Schedule = function()
    if state.active and not state.paused then
        C_Timer.After(state.tick, Tick)
    end
end

-- ============================================================================
-- Counting / verdict helpers
-- ============================================================================
--- Marks an id as fully processed. Returns true the first time only.
Settle = function(id)
    if state.settled[id] then return false end
    state.settled[id] = true
    state.scanned = state.scanned + 1
    return true
end

local function Verdict(id)
    local typeDef = addon:GetScanTypeDef(state.typeKey)
    if not typeDef then return false end

    local rId, link, quality, level = typeDef.resolver(id)
    if rId and link then
        RecordResult(id, link, quality, level)
        return true
    end
    return false
end

--- Classifies an item id, cheapest check first.
--  The result is memoized so the full, comparatively costly lookup runs at
--  most once per id.
--  @return 2 cached, 1 not cached yet, 3 does not exist, 0 not a cached item
local function ItemClass(id)
    local slot = state.slots[id]
    if slot then return slot end

    if api.GetItemInfo then
        local ok, name = pcall(api.GetItemInfo, id)
        if ok and name ~= nil then
            state.slots[id] = 2
            return 2
        end
    end

    if api.DoesItemExistByID then
        local ok, exists = pcall(api.DoesItemExistByID, id)
        if ok and exists == false then
            state.slots[id] = 3
            return 3
        end
    end

    -- Temporary state: it may still turn into a hit once the client caches it.
    return 1
end

--- Rate limiter for item-definition requests.
--  Returns false when the per-second request budget is exhausted, which lets
--  the engine hold expensive ids back instead of flooding the server.
local function TakeBudget(count)
    local now = GetTime()
    local elapsed = now - (state.lastTick or now)
    if elapsed > 0 then
        state.budget = math.min(REQUEST_BUDGET, (state.budget or 0) + elapsed * REQUEST_BUDGET)
        state.lastTick = now
    end
    if (state.budget or 0) < count then return false end
    state.budget = state.budget - count
    return true
end

--- Asks the client to fetch one item definition.
--  Returns true when a request was actually handed to the client, so the engine
--  only waits for ids that have a chance of arriving.
local function PreloadItem(id)
    if preloadPath == "ItemMixin" and preloadFactory then
        local ok, item = pcall(preloadFactory.CreateFromItemID, preloadFactory, id)
        if ok and item and preloadMethod then
            return pcall(item[preloadMethod], item, function() end)
        end
        return false
    end

    if preloadPath == "Tooltip" then
        local ok = pcall(scanTooltip.SetItemByID, scanTooltip, id)
        return ok
    end

    return false
end

-- ============================================================================
-- Verification round: give the client a moment to cache the requested items
-- ============================================================================
local function VerifyPending()
    local pending = state.pending
    if #pending == 0 then return end

    local stillPending = {}
    for i = 1, #pending do
        local id = pending[i]
        local slot = ItemClass(id)

        if slot == 2 then
            if not Verdict(id) then
                state.missing = state.missing + 1
            end
            Settle(id)
        elseif slot == 3 then
            state.missing = state.missing + 1
            Settle(id)
        else
            local tries = (state.retries[id] or 0) + 1
            if tries <= MAX_RETRY then
                state.retries[id] = tries
                stillPending[#stillPending + 1] = id
            else
                -- The client never produced a definition for this id, so it has
                -- no data on this client: report it as missing.
                if not Verdict(id) then
                    state.missing = state.missing + 1
                end
                Settle(id)
            end
        end
    end

    state.pending = stillPending
end

-- ============================================================================
-- Live UI refresh
--
-- The scan engine runs in short ticks, so the progress bar and the result list
-- are repainted on their own cadence while a scan is running. Without this the
-- numbers only changed once, when the scan ended.
-- ============================================================================
local REFRESH_INTERVAL = 0.15
local lastRefresh = 0
local refreshScheduled = false

local function ScheduleRefresh()
    if refreshScheduled then return end
    refreshScheduled = true
    C_Timer.After(REFRESH_INTERVAL, function()
        refreshScheduled = false
        if not state.active then return end
        if addon.RefreshLive then addon:RefreshLive() end
        ScheduleRefresh()
    end)
end

local function StopRefresh()
    refreshScheduled = false
end

-- ============================================================================
-- One engine tick
-- ============================================================================
Tick = function()
    if not state.active or state.paused then return end

    -- Keep the visible numbers moving while the scan is in progress.
    local now = GetTime()
    if now - lastRefresh >= REFRESH_INTERVAL then
        lastRefresh = now
        if addon.RefreshLive then addon:RefreshLive() end
    end

    -- 1) An outstanding verification batch always has priority so the
    --    tooltip queue cannot grow without bound.
    if #state.pending > 0 then
        VerifyPending()
        state.dirty = true
        if state.pos >= state.total and #state.pending == 0 then
            Finish(false)
            return
        end
        Schedule()
        return
    end

    -- 2) Fast path: walk the requested range.
    local typeDef = addon:GetScanTypeDef(state.typeKey)
    local isItem = (state.typeKey == "item")
    local budget = CHUNK_CACHE
    local requestQueue

    while budget > 0 and state.pos < state.total do
        local id = state.from + state.pos
        state.pos = state.pos + 1
        budget = budget - 1

        if isItem then
            local slot = ItemClass(id)
            if slot == 2 then
                if not Verdict(id) then
                    state.missing = state.missing + 1
                end
                Settle(id)
            elseif slot == 3 then
                -- The client already knows this id does not exist: no request.
                state.missing = state.missing + 1
                Settle(id)
            else
                -- Unknown to the client: needs a definition request, which is
                -- the only operation here that costs server round trips.
                requestQueue = requestQueue or {}
                requestQueue[#requestQueue + 1] = id
            end
        else
            if not Verdict(id) then
                state.missing = state.missing + 1
            end
            Settle(id)
        end
    end

    -- 3) Hand the uncached items to the client, rate limited so a cold cache
    --    cannot flood it with item requests.
    if requestQueue then
        local asked = 0
        for i = 1, #requestQueue do
            if TakeBudget(1) then
                local id = requestQueue[i]
                PreloadItem(id)
                state.pending[#state.pending + 1] = id
                asked = asked + 1
            else
                -- Budget spent: these ids stay unknown and are revisited on a
                -- later tick, when the fast path walks them again.
                state.pos = state.pos - (#requestQueue - i + 1)
                break
            end
        end
        if asked > 0 then
            api.RequestItem(state.pending[1])
        end

        -- Keep verification batches bounded; the rest waits for later ticks.
        if #state.pending > CHUNK_VERIFY then
            local overflow = {}
            for i = CHUNK_VERIFY + 1, #state.pending do
                overflow[#overflow + 1] = state.pending[i]
            end
            state.pending = overflow
        end
    end

    state.dirty = true

    if state.pos >= state.total and #state.pending == 0 then
        Finish(false)
        return
    end

    Schedule()
end

-- ============================================================================
-- Lifecycle
-- ============================================================================
Finish = function(stopped)
    state.active = false
    state.paused = false
    state.elapsed = GetTime() - state.startedAt
    StopRefresh()

    if addon.RefreshProgress then addon:RefreshProgress() end
    if addon.RequestRepaint then addon:RequestRepaint(true) end
    if addon.RefreshButtons then addon:RefreshButtons() end

    if stopped then
        addon:Print(L.MSG_CANCELLED)
    else
        addon:Print((L.PROGRESS_DONE):format(state.scanned, #state.order,
            state.missing, state.elapsed))
    end
end

function addon:InitScanner()
    self.preloadPath = preloadPath or "none"
end

--- One-line summary of what the scanner can actually do on this client.
function addon:DescribeScanner()
    local parts = {
        "preload=" .. (preloadPath or "none"),
        "itemInfo=" .. (api.GetItemInfo and "yes" or "no"),
        "itemExists=" .. (api.DoesItemExistByID and "yes" or "no"),
        "quest=" .. (api.questUsable and "yes" or "no"),
        "spell=" .. (api.spellUsable and "yes" or "no"),
        "achv=" .. (api.GetAchievementLink and "yes" or "no"),
    }
    return table.concat(parts, " ")
end

--- Starts a scan. Returns true when a scan was actually started.
function addon:StartScan(typeKey, from, to, delay)
    if state.active then
        self:Print(L.ERR_BUSY)
        return false
    end

    local typeDef = self:GetScanTypeDef(typeKey)
    if not typeDef then return false end

    if not typeDef.apiCheck() then
        self:Print((L.ERR_NO_API):format(self:TypeLabel(typeDef.key)))
        return false
    end

    if not from or not to or from < 0 or to < from then
        self:Print(L.ERR_RANGE)
        return false
    end

    local maxIDs = 100000
    if (to - from + 1) > maxIDs then
        self:Print((L.ERR_TOO_LARGE):format(to - from + 1, maxIDs))
        return false
    end

    state.active    = true
    state.paused    = false
    state.typeKey   = typeKey
    state.from      = from
    state.to        = to
    state.total     = to - from + 1
    state.pos       = 0
    state.scanned   = 0
    state.missing   = 0
    state.settled   = {}
    state.slots     = {}
    state.pending   = {}
    state.retries   = {}
    state.budget    = REQUEST_BUDGET
    state.lastTick  = GetTime()
    state.results   = {}
    state.order     = {}
    state.dirty     = true
    state.truncated = false
    state.startedAt = GetTime()
    state.elapsed   = 0
    state.tick      = tonumber(delay) or DEFAULT_TICK
    if state.tick < 0.01 then state.tick = 0.01 end

    if self.RequestRepaint then self:RequestRepaint(true) end
    if self.RefreshProgress then self:RefreshProgress() end
    if self.RefreshButtons then self:RefreshButtons() end

    lastRefresh = GetTime()
    ScheduleRefresh()

    Tick()
    return true
end

function addon:StopScan()
    if not state.active and #state.order == 0 then return end
    if state.active then
        Finish(true)
    end
end

function addon:TogglePause()
    if not state.active then return end
    state.paused = not state.paused
    if self.RefreshLive then self:RefreshLive() end
    if not state.paused then
        lastRefresh = GetTime()
        ScheduleRefresh()
        Schedule()
    end
end

function addon:ResumeScan()
    if not state.active then return false end
    if not state.paused then return true end
    state.paused = false
    if self.RefreshLive then self:RefreshLive() end
    lastRefresh = GetTime()
    ScheduleRefresh()
    Schedule()
    return true
end

-- ============================================================================
-- Result access
-- ============================================================================
function addon:GetResults()
    return state.order, state.results
end

function addon:GetScanState()
    return state
end

function addon:ClearResults()
    state.results = {}
    state.order = {}
    state.scanned = 0
    state.truncated = false
    if self.RequestRepaint then self:RequestRepaint(true) end
    self:Print(L.MSG_CLEARED)
end

-- ============================================================================
-- Export
--
-- One line per hit: the numeric id, a tab, then the link. Nothing else.
--
-- The name needs no column of its own because it is the link's visible text:
-- a quest row reads
--     2<TAB>|cffffff00|Hquest:2|h[沙普塔隆的爪子]|h|r
-- so id and name are both in it, and the row stays sortable by id and diffable.
--
-- Quest descriptions and objective lists used to be appended as indented
-- continuation lines. They are gone on purpose, not for lack of trying: this
-- client has no per-id quest text getter at all, and the one call that does hand
-- out a quest's short sentence (GetQuestLogQuestText) describes whichever entry
-- the player has SELECTED -- so over an id range it would attribute one quest's
-- words to another, which is worse than exporting none. The reasoning is kept
-- here so the same road is not walked twice.
-- ============================================================================
function addon:Export()
    if #state.order == 0 then
        self:Print(L.ERR_NO_RESULTS)
        return
    end

    local lines = {}
    lines[1] = ("-- %s  %s"):format(L.EXPORT_HEADER, date("%Y-%m-%d %H:%M:%S"))
    lines[2] = ("-- type=%s  range=%d-%d  found=%d"):format(
        state.typeKey, state.from, state.to, #state.order)

    for i = 1, #state.order do
        local entry = state.results[state.order[i]]
        if entry then
            lines[#lines + 1] = ("%d\t%s"):format(entry.id, entry.link)
        end
    end

    GetInfoScanDB.export[state.typeKey] = {
        time = date("%Y-%m-%d %H:%M:%S"),
        from = state.from,
        to = state.to,
        count = #state.order,
        text = table.concat(lines, "\n"),
    }

    self:Print((L.MSG_EXPORTED):format(#state.order))
end

function addon:CopyLinks()
    if #state.order == 0 then
        self:Print(L.ERR_NO_RESULTS_COPY)
        return
    end

    -- Copied as "id link" per entry. The id is what makes the result usable
    -- outside the game (a bare hyperlink cannot be sorted, diffed or looked up),
    -- and it applies to every scan type: item, quest, spell and achievement.
    local parts = {}
    for i = 1, #state.order do
        local entry = state.results[state.order[i]]
        if entry and entry.link then
            parts[#parts + 1] = ("%s %s"):format(tostring(entry.id), entry.link)
        end
    end
    if #parts == 0 then
        self:Print(L.ERR_NO_RESULTS_COPY)
        return
    end

    local text = table.concat(parts, " ")
    local box = self.window and self.window.copyBox

    -- AceGUI's EditBox is a WIDGET, not a frame: it has no Show/Hide. What it
    -- does expose is SetMaxLetters, SetText, SetFocus and HighlightText, and its
    -- frame is already visible because the widget is a child of the window.
    --
    -- The previous version called box:Show(), which raised
    -- "attempt to call a nil value" before any of the real work ran. Copy Links
    -- then reported success while putting nothing anywhere.
    if box then
        if box.SetMaxLetters then box:SetMaxLetters(0) end
        if box.SetText then box:SetText(text) end
        if box.SetFocus then box:SetFocus() end
        if box.HighlightText then box:HighlightText() end
    end

    self:Print((L.MSG_COPIED):format(#parts))

    -- World of Warcraft has no clipboard API: the text is placed in an edit box
    -- and selected so Ctrl+C can copy it. If the client's edit box silently
    -- truncates the text, say so rather than implying the whole set is there.
    if box and box.GetText then
        local stored = box:GetText()
        if type(stored) == "string" and #stored < #text then
            self:Print((L.MSG_COPY_TRUNCATED):format(#stored, #text))
        end
    end
end
