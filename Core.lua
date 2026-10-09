--[[----------------------------------------------------------------------------
    GetInfoScan - Core.lua
    Namespace, client detection, multi-version API compatibility layer,
    minimap launcher button and slash commands.
----------------------------------------------------------------------------]]--

local addonName, addon = ...

addon.name = addonName or "GetInfoScan"
addon.L = addon.L or setmetatable({}, { __index = function(_, k) return tostring(k) end })
local L = addon.L

-- ============================================================================
-- Saved variables
-- ============================================================================
GetInfoScanDB = GetInfoScanDB or {}
local DB = GetInfoScanDB
DB.minimap = DB.minimap or { hide = false, angle = 220 }
DB.export = DB.export or {}
-- AceGUI stores the window geometry here, so size and position survive /reload.
DB.window = DB.window or { width = 660, height = 620 }
-- The start ID, end ID and speed the user typed. Refilling these with defaults
-- on every login would throw away work the user just did, so they are kept
-- verbatim as text and restored when the window is built.
DB.range = DB.range or { from = "1", to = "5000", delay = "0.08" }

-- ============================================================================
-- Client / build detection
--
-- Everything the window and /gis status report about the client is READ from the
-- client: GetBuildInfo() is the authority for version, build, date and the
-- interface (toc) number, GetLocale() for the language, and WOW_PROJECT_ID for
-- which content line the client says it is.
--
-- The flags below (isMainline / isForever / isClassicLine) are an INTERPRETATION
-- used only to pick behaviour, such as which link format to write. They are not
-- shown to the player as if they were the client's own name: an earlier version
-- printed a made-up label like "Classic" in the status bar and it read as fact.
-- ============================================================================
local buildVersion, buildNumber, buildDate, interfaceVersion = GetBuildInfo()
local projectID = WOW_PROJECT_ID
local locale = GetLocale and GetLocale() or nil

-- "Forever" (Titan / Camelot) reports the retail project id but uses the
-- Classic content line and interface version 16xxx.
local isForever = type(interfaceVersion) == "number"
    and interfaceVersion >= 16000 and interfaceVersion < 17000

local isMainline = (not isForever) and (
    projectID == WOW_PROJECT_MAINLINE
    or (projectID == nil and type(interfaceVersion) == "number" and interfaceVersion >= 100000)
)

-- Everything below is the Classic content line (Era, Titan/Forever, TBC, Wrath, Cata, MoP).
local isClassicLine = not isMainline

--- Which WOW_PROJECT_* constant the client's own WOW_PROJECT_ID equals.
---
--- This is reading, not guessing: the names are searched in the client's own
--- globals, so a match means the client itself named its content line. Scanning
--- _G rather than a hardcoded list means a content line this addon has never
--- heard of is still named correctly if the client defines a constant for it.
--- A client that defines no such constant (or whose value matches none) gets no
--- name here rather than a label this addon invented.
---
--- WOW_PROJECT_ID itself is skipped. It also starts with "WOW_PROJECT_" and its
--- value IS the id, so it matches whenever the id matches -- and it is the id
--- holder, not a content line. Picking it printed "ID" in the status bar, which
--- is what a viewer of the target client saw: with id 1 the holder sorted after
--- WOW_PROJECT_CLASSIC and the bug stayed hidden, with id 11 it sorted first.
local function ProjectName(id)
    if type(id) ~= "number" then return nil end

    local matches = {}
    local ok = pcall(function()
        for key, value in pairs(_G) do
            -- Content lines never end in _ID; only the holder does.
            if type(key) == "string" and type(value) == "number" and value == id
                and key:sub(1, 12) == "WOW_PROJECT_" and key:sub(-3) ~= "_ID" then
                matches[#matches + 1] = key
            end
        end
    end)
    if not ok or #matches == 0 then return nil end

    -- Deterministic when several constants share the value: "CLASSIC" beats
    -- "SOMETHING_ELSE_CLASSIC", which is what a plain sort gives.
    table.sort(matches)
    return matches[1]
end

addon.client = {
    version = (type(buildVersion) == "string" and buildVersion ~= "")
        and buildVersion or nil,
    build = (buildNumber ~= nil and tostring(buildNumber) ~= "")
        and tostring(buildNumber) or nil,
    date = (type(buildDate) == "string" and buildDate ~= "") and buildDate or nil,
    interface = tonumber(interfaceVersion) or nil,
    locale = locale,
    projectID = projectID,
    projectName = ProjectName(projectID),
    isMainline = isMainline,
    isForever = isForever,
    isClassicLine = isClassicLine,
}

-- Kept for callers that want one short identifier. It reports only what the
-- client said: its project constant, its raw project id, or "unknown" when the
-- client exposes neither. No inferred label is ever returned.
function addon:ClientTag()
    if self.client.projectName then return self.client.projectName end
    if type(self.client.projectID) == "number" then
        return "project " .. self.client.projectID
    end
    return "unknown"
end

--- The status bar line: what the client reports, in its own words.
--- Built from GetBuildInfo / GetLocale / WOW_PROJECT_ID only, and every field is
--- optional: a client that answers nothing gets an empty part rather than a
--- placeholder that looks like data.
function addon:ClientLine()
    local c = self.client
    local parts = {}

    if c.version then
        local text = c.version
        -- Only worth showing when it is not just the interface number again.
        if c.build and c.build ~= tostring(c.interface) then
            text = text .. " (build " .. c.build .. ")"
        end
        parts[#parts + 1] = text
    end

    if c.interface then
        parts[#parts + 1] = "Interface " .. c.interface
    end

    if c.projectName then
        -- The constant name is long and every one of them shares the prefix.
        parts[#parts + 1] = (c.projectName:gsub("^WOW_PROJECT_", ""))
    elseif type(c.projectID) == "number" then
        parts[#parts + 1] = "project " .. c.projectID
    end

    if c.locale then parts[#parts + 1] = c.locale end

    if #parts == 0 then return "?" end
    return table.concat(parts, "  |  ")
end

-- ============================================================================
-- API compatibility
--
-- Every lookup is probed once with pcall so a missing global or a changed
-- signature can never raise a Lua error later from inside the scan loop.
-- ============================================================================
local api = {}
addon.api = api

local function safeCall(fn, ...)
    if not fn then return nil end
    local ok, a, b, c, d, e, f = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c, d, e, f
end

api.GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
api.GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
api.IsItemDataCachedByID = C_Item and C_Item.IsItemDataCachedByID
api.DoesItemExistByID = C_Item and C_Item.DoesItemExistByID
api.RequestLoadItemDataByID = C_Item and C_Item.RequestLoadItemDataByID

api.GetSpellInfo = (C_Spell and C_Spell.GetSpellInfo) or GetSpellInfo
api.GetSpellLink = (C_Spell and C_Spell.GetSpellLink) or GetSpellLink
api.GetSpellTexture = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture

api.GetTitleForQuestID = C_QuestLog and C_QuestLog.GetTitleForQuestID
api.GetQuestInfo = C_QuestLog and C_QuestLog.GetQuestInfo
api.GetQuestLink = GetQuestLink

api.GetAchievementLink = GetAchievementLink
api.GetAchievementInfo = GetAchievementInfo
api.GetAchievementNumRows = GetAchievementNumRows

-- probe the spell API once: some clients guard it and raise on invalid ids
local spellApiUsable = false
do
    if api.GetSpellInfo then
        local ok = pcall(api.GetSpellInfo, 1)
        spellApiUsable = ok
    end
end
api.spellUsable = spellApiUsable and api.GetSpellInfo ~= nil

-- probe the quest API once
local questApiUsable = false
do
    local fn = api.GetQuestInfo or api.GetTitleForQuestID
    if fn then
        local ok = pcall(fn, 1)
        questApiUsable = ok
    end
end
api.questUsable = questApiUsable

--[[----------------------------------------------------------------------------
    Item helpers
----------------------------------------------------------------------------]]--

--- Returns the cached item data.
--  Normalises both the 15-value legacy tuple and the table form
--  (retail / Forever) into 4 return values.
--  @return name, link, quality, itemLevel  (all nil when not cached)
function api.ItemLookup(itemID)
    if not api.GetItemInfo then return nil end

    local ok, a, b, c, d = pcall(api.GetItemInfo, itemID)
    if not ok or a == nil then return nil end

    if type(a) == "table" then
        return a.itemName, a.itemLink, a.quality, a.itemLevel
    end

    -- Legacy tuple: name, link, quality, iLevel, reqLevel, class, subclass, ...
    -- Some Classic-line builds return a shifted tuple that carries the icon
    -- texture as the second value, in which case every field moves by one.
    if type(b) == "number" then
        local _, _, q2, l2, _, lvl2 = pcall(api.GetItemInfo, itemID)
        return a, q2, l2, lvl2
    end

    return a, b, c, d
end

--- True when the item definition is loaded into the local cache.
function api.IsItemCached(itemID)
    -- 1) Best case: the client answers directly.
    if api.IsItemDataCachedByID then
        local ok, cached = pcall(api.IsItemDataCachedByID, itemID)
        if ok then return cached and true or false end
    end

    -- 2) The instant lookup. On some Classic-line builds it already answers for
    --    uncached ids, so require the fields that are only filled from cache.
    if api.GetItemInfoInstant then
        local ok, id, _, _, _, icon, _, name = pcall(api.GetItemInfoInstant, itemID)
        if ok and id then
            if icon ~= nil or (name ~= nil and name ~= "") then
                return true
            end
        end
    end

    -- 3) Full lookup: it only returns a name once the definition is known.
    if api.GetItemInfo then
        local ok, name = pcall(api.GetItemInfo, itemID)
        if ok and name ~= nil then return true end
    end

    return false
end

--- True when the id does not resolve to any item at all.
--  Only trusted when the client can answer authoritatively, otherwise the
--  caller has to treat "unknown" and "missing" the same way.
function api.IsItemMissing(itemID)
    if api.DoesItemExistByID then
        local ok, exists = pcall(api.DoesItemExistByID, itemID)
        if ok then return not exists end
    end
    return nil -- unknown
end

--- Asks the client to load an item definition (best effort, may be a no-op).
function api.RequestItem(itemID)
    local fn = api.RequestLoadItemDataByID
    if fn and not pcall(fn, itemID) and api.RequestLoadItemData then
        pcall(api.RequestLoadItemData, itemID)
    elseif api.RequestLoadItemData then
        pcall(api.RequestLoadItemData, itemID)
    end
end

--- Resolves an item id into #id, display link, quality, level.
function api.ResolveItem(itemID)
    local name, link, quality, itemLevel = api.ItemLookup(itemID)
    if name == nil or name == "" then return nil end

    if not link or link == "" then
        link = ("|c%02x%02x%02x|Hitem:%d|h[%s]|h|r"):format(
            255, 255, 255, itemID, name)
    end

    return tostring(itemID), link, tonumber(quality) or 1, tonumber(itemLevel) or 0
end

--[[----------------------------------------------------------------------------
    Quest helpers
----------------------------------------------------------------------------]]--

function api.ResolveQuest(questID)
    local name = safeCall(api.GetTitleForQuestID, questID)
    if (name == nil or name == "") and api.GetQuestInfo then
        name = safeCall(api.GetQuestInfo, questID)
    end

    -- Last resort: some clients fill their quest cache as a side effect of the
    -- localized link request and will then answer the name lookup.
    if name == nil or name == "" then
        local link = safeCall(api.GetQuestLink, questID)
        if type(link) == "string" and link ~= "" then
            name = link:match("%[(.-)%]")
        end
    end

    if name == nil or name == "" then return nil end

    -- Both the modern and the classic client accept the name-carrying form on
    -- the Classic content line, which is what this scanner targets.
    local link = ("|cffffff00|Hquest:%d|h[%s]|h|r"):format(questID, name)

    return tostring(questID), link, 1, 0
end

--[[----------------------------------------------------------------------------
    Spell helpers
----------------------------------------------------------------------------]]--

function api.ResolveSpell(spellID)
    if not api.GetSpellInfo then return nil end

    local a, b = safeCall(api.GetSpellInfo, spellID)

    local name, subText
    if type(a) == "table" then
        name = a.name
        subText = a.subText
    else
        name, subText = a, b
    end

    if name == nil or name == "" then return nil end
    if subText and subText ~= "" then
        name = name .. " (" .. subText .. ")"
    end

    local link = safeCall(api.GetSpellLink, spellID)
    if type(link) ~= "string" or link == "" then
        link = ("|cff71d5ff|Hspell:%d|h[%s]|h|r"):format(spellID, name)
    end

    return tostring(spellID), link, 1, 0
end

--[[----------------------------------------------------------------------------
    Achievement helpers
----------------------------------------------------------------------------]]--

function api.ResolveAchievement(achievementID)
    local link = safeCall(api.GetAchievementLink, achievementID)
    if type(link) ~= "string" or link == "" then return nil end

    -- Strip the colour codes when the name is only needed for logging.
    return tostring(achievementID), link, 1, 0
end

-- ============================================================================
-- Shared helpers
-- ============================================================================
function addon:Print(msg)
    local frame = DEFAULT_CHAT_FRAME or ChatFrame1
    if frame then
        frame:AddMessage(tostring(msg))
    end
end

function addon:Colorize(text, quality)
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
    if color and color.hex then
        return color.hex .. tostring(text) .. "|r"
    end
    return tostring(text)
end

--- Numeric text of an edit box, or nil when it is not a plain integer.
function addon:ReadNumber(editBox)
    if not editBox then return nil end
    local text = editBox:GetText() or ""
    text = text:gsub("%s", "")
    if text == "" then return nil end
    return tonumber(text)
end

-- ============================================================================
-- Scan types
--
-- Every entry resolves an id into: id, link, quality, level.
-- A nil first return value means "no such entry".
-- ============================================================================
local function ResolveItem(id) return api.ResolveItem(id) end
local function ResolveQuest(id) return api.ResolveQuest(id) end
local function ResolveSpell(id) return api.ResolveSpell(id) end
local function ResolveAchievement(id) return api.ResolveAchievement(id) end

addon.SCAN_TYPES = {
    { key = "item",        resolver = ResolveItem,
      apiName = "item",        defaultFrom = 1,     defaultTo = 5000 },
    { key = "quest",       resolver = ResolveQuest,
      apiName = "quest",       defaultFrom = 1,     defaultTo = 5000 },
    { key = "spell",       resolver = ResolveSpell,
      apiName = "spell",       defaultFrom = 1,     defaultTo = 5000 },
    { key = "achievement", resolver = ResolveAchievement,
      apiName = "achievement", defaultFrom = 1,     defaultTo = 5000 },
}

-- Availability check per type, evaluated lazily so the probes above are final.
local apiCheckers = {
    item        = function() return api.GetItemInfo ~= nil and api.IsItemCached ~= nil end,
    quest       = function() return api.questUsable end,
    spell       = function() return api.spellUsable end,
    achievement = function() return api.GetAchievementLink ~= nil end,
}

for i = 1, #addon.SCAN_TYPES do
    local def = addon.SCAN_TYPES[i]
    def.apiCheck = apiCheckers[def.key]
end

function addon:GetScanTypeDef(key)
    for i = 1, #self.SCAN_TYPES do
        if self.SCAN_TYPES[i].key == key then
            return self.SCAN_TYPES[i], i
        end
    end
end

--- Localized display name of a scan type: "物品", "Items", ...
---
--- def.apiName deliberately stays the raw key. It is what /gis status prints next
--- to the API probes ("quest=yes"), where a stable identifier is what you want.
--- Everything the player actually reads goes through here instead -- otherwise a
--- Chinese client reports "扫描 item 中" and "当前客户端不提供「spell」资料".
function addon:TypeLabel(key)
    local label = L["TAB_" .. tostring(key or ""):upper()]
    if type(label) ~= "string" or label == "" then return tostring(key or "?") end
    return label
end

-- ============================================================================
-- Minimap launcher button (self contained, no external library required)
-- ============================================================================
local function CreateMinimapButton()
    local button = CreateFrame("Button", "GetInfoScanMinimapButton", Minimap)
    button:SetFrameStrata("MEDIUM")
    button:SetFixedFrameStrata(true)
    button:SetFrameLevel(8)
    button:SetFixedFrameLevel(true)
    button:SetSize(31, 31)
    button:RegisterForClicks("anyUp")
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)

    -- File paths are used instead of the numeric file ids so the button keeps
    -- its artwork on every client branch; every call is best effort.
    local function TryTexture(region, paths)
        for i = 1, #paths do
            local ok = pcall(region.SetTexture, region, paths[i])
            if ok then return end
        end
    end

    pcall(button.SetHighlightTexture, button,
        "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local overlay = button:CreateTexture(nil, "OVERLAY")
    TryTexture(overlay, {
        "Interface\\Minimap\\MiniMap-TrackingBorder",
        "Interface\\Minimap\\UI-Minimap-Border",
    })

    local background = button:CreateTexture(nil, "BACKGROUND")
    TryTexture(background, {
        "Interface\\Minimap\\UI-Minimap-Background",
    })

    local icon = button:CreateTexture(nil, "ARTWORK")
    TryTexture(icon, {
        "Interface\\AddOns\\GetInfoScan\\icon",
    })
    icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    button.icon = icon

    if isMainline then
        overlay:SetSize(50, 50)
        overlay:SetPoint("TOPLEFT", button, "TOPLEFT")
        background:SetSize(24, 24)
        background:SetPoint("CENTER", button, "CENTER")
        icon:SetSize(18, 18)
        icon:SetPoint("CENTER", button, "CENTER")
    else
        overlay:SetSize(53, 53)
        overlay:SetPoint("TOPLEFT")
        background:SetSize(20, 20)
        background:SetPoint("TOPLEFT", 7, -5)
        icon:SetSize(17, 17)
        icon:SetPoint("TOPLEFT", 7, -6)
    end

    -- Drag handling: keep the button on the minimap ring.
    -- Lua 5.1 exposes math.atan2 while newer Lua folded it into math.atan(y, x);
    -- older 5.1 builds only take one argument, so both are probed and a full
    -- fallback is used when neither two-argument form exists.
    local atan2
    do
        if type(math.atan2) == "function" then
            atan2 = math.atan2
        else
            local ok = pcall(function() return math.atan(1, 1) end)
            if ok then
                atan2 = function(y, x) return math.atan(y, x) end
            else
                atan2 = function(y, x)
                    if x == 0 and y == 0 then return 0 end
                    local a = math.atan(math.abs(y / x))
                    if x >= 0 and y >= 0 then return a end
                    if x < 0 and y >= 0 then return math.pi - a end
                    if x < 0 then return a - math.pi end
                    return -a
                end
            end
        end
    end

    local function UpdatePosition(angle)
        local radius = 80
        local x = math.cos(math.rad(angle)) * radius
        local y = math.sin(math.rad(angle)) * radius
        button:ClearAllPoints()
        button:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            local angle = math.deg(atan2(cy - my, cx - mx))
            DB.minimap.angle = angle
            UpdatePosition(angle)
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(L.TIP_MINIMAP)
        GameTooltip:AddLine(L.TIP_MINIMAP_CLICK, 1, 1, 1, true)
        GameTooltip:AddLine(L.TIP_MINIMAP_DRAG, 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    button:SetScript("OnClick", function()
        addon:ToggleWindow()
    end)

    UpdatePosition(DB.minimap.angle or 220)
    button:SetShown(not DB.minimap.hide)
    return button
end

-- ============================================================================
-- Late UI helpers
--
-- These live in Core because the window itself is created in UI.lua. The
-- indirection also means a slash command typed before PLAYER_LOGIN still works.
-- ============================================================================
function addon:IsWindowBuilt()
    return self.window ~= nil
end

function addon:EnsureWindow()
    if self.window then return self.window end
    if not self.BuildWindow then
        self:Print(L.BUILD_NO_BUILDER)
        return nil
    end

    local ok, err = pcall(self.BuildWindow, self)
    if not ok then
        -- BuildWindow guards every band, so arriving here means the frame object
        -- itself could not be made. Report the actual error instead of a generic
        -- one: a previous version printed "could not be created" while the real
        -- cause -- an assert inside AceGUI -- stayed hidden.
        self.lastBuildError = tostring(err)
        self:Print(L.BUILD_STEP_FAILED:format(tostring(err)))
        if type(debug) == "table" and type(debug.traceback) == "function" then
            local tb = (debug.traceback("", 2) or ""):gsub("%s+", " ")
            self:Print("|cffff5555[GetInfoScan]|r " .. tb)
        end
        return nil
    end
    if not self.window then
        self:Print(L.BUILD_NONE)
    end
    return self.window
end

--- Shows what the client reports about itself plus the scan API surface, which
--- is the first thing to check when the client treats the addon as out of date.
---
--- Every value here is read from the client, never inferred: version, build and
--- interface number come from GetBuildInfo, the project name is whichever of the
--- client's own WOW_PROJECT_* constants WOW_PROJECT_ID equals, and "unknown"
--- means exactly that -- the client did not say.
function addon:PrintStatus()
    self:Print((L.STATUS_LINE):format(
        tostring(self.client.version or "?"),
        tostring(self.client.interface or "?"),
        self:ClientTag(),
        self:IsWindowBuilt() and "yes" or "no"))

    -- The raw numbers behind that line, for a bug report: the build number and
    -- date are not shown anywhere else.
    self:Print((L.STATUS_BUILD):format(
        tostring(self.client.build or "?"),
        tostring(self.client.date or "?"),
        tostring(self.client.locale or "?"),
        tostring(self.client.projectID)))

    if self.DescribeScanner then
        self:Print((L.STATUS_APIS):format(self:DescribeScanner()))
    end

    -- Which controls actually exist. A window that builds only partly is the
    -- failure mode this addon kept hitting, so the report is explicit about it.
    if self.PrintBuildReport then
        self:PrintBuildReport()
    end

    self:Print((L.STATUS_CMDS))
end

-- ============================================================================
-- Slash commands
-- ============================================================================
local function HandleSlash(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

    if msg == "" or msg == "show" or msg == "toggle" or msg == "open" then
        addon:ToggleWindow()
    elseif msg == "hide" or msg == "close" then
        addon:HideWindow()
    elseif msg == "clear" then
        addon:ClearResults()
    elseif msg == "export" then
        addon:Export()
    elseif msg == "copy" then
        addon:CopyLinks()
    elseif msg == "status" or msg == "debug" then
        addon:PrintStatus()
    elseif msg == "build" then
        if addon.RebuildWindow then
            addon:RebuildWindow()
        else
            addon:EnsureWindow()
            addon:PrintStatus()
        end
    elseif msg == "reset" then
        DB.export = {}
        addon:Print("|cff33ff99[GetInfoScan]|r saved export cleared.")
    elseif msg == "minimap" then
        DB.minimap.hide = not DB.minimap.hide
        if addon.MinimapButton then addon.MinimapButton:SetShown(not DB.minimap.hide) end
        addon:Print(("|cff33ff99[GetInfoScan]|r minimap button %s.")
            :format(DB.minimap.hide and "hidden" or "shown"))
    else
        addon:Print("|cff33ff99[GetInfoScan]|r /gis  |  /gis status  |  /gis clear  |  "
            .. "/gis copy  |  /gis export  |  /gis minimap  |  /gis reset")
    end
end

-- Register the command immediately at load time so it exists even before the
-- player physically logs in, and accept a couple of alternate spellings.
pcall(function()
    SLASH_GETINFOSCAN1 = "/gis"
    SLASH_GETINFOSCAN2 = "/getinfoscan"
    SLASH_GETINFOSCAN3 = "/infoscan"
    SlashCmdList.GETINFOSCAN = HandleSlash
end)

-- ============================================================================
-- Bootstrap
-- ============================================================================
--- Runs the one-time construction, and never more than once.
function addon:InitRuntime()
    if self.runtimeReady then return end

    if not self.MinimapButton then
        local ok, button = pcall(CreateMinimapButton)
        if ok then
            self.MinimapButton = button
        else
            self:Print("|cffff5555[GetInfoScan]|r minimap button failed: " .. tostring(button))
        end
    end

    self:EnsureWindow()

    if self.InitScanner then
        pcall(self.InitScanner, self)
    end

    self.runtimeReady = true
end

function addon:ToggleWindow()
    self:InitRuntime()
    if not self.window then
        -- The real reason was already reported by EnsureWindow; this only
        -- repeats the state so a bare /gis is never silent.
        if self.PrintBuildReport then self:PrintBuildReport() end
        return
    end

    if self.window:IsShown() then
        self.window:Hide()
    else
        self:ShowWindow()
    end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
    boot:UnregisterEvent("PLAYER_LOGIN")
    addon:InitRuntime()
    addon:PrintStatus()
end)

addon.boot = boot
