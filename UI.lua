--[[----------------------------------------------------------------------------
    GetInfoScan - UI.lua

    The window is built with AceGUI-3.0 (vendored under Libs). AceGUI arranges
    the controls, supplies the frame art and remembers the window geometry, so
    no coordinate in this file is guessed.

    AceGUI has no widget for a scrollable list of clickable hyperlinks with real
    item/quest tooltips, so "InfoScanList" below registers a custom AceGUI widget
    for exactly that. It recycles a pool of row frames, which keeps a result set
    of thousands of entries cheap.
----------------------------------------------------------------------------]]--

local _, addon = ...
local L = addon.L

local ROW_HEIGHT   = 21    -- fallback only; the pool measures the real pitch
local ROW_POOL_MIN = 22

-- The window widget is held on the addon table only. Keeping a second local
-- copy here was a bug: BuildWindow assigned the local while the rest of the
-- file read the addon field, so they could disagree about which widget was live.
addon.window = nil

local AceGUI = LibStub("AceGUI-3.0")

-- ============================================================================
-- Repaint throttling
-- ============================================================================
local repaintPending = false

local function Repaint()
    repaintPending = false
    local win = addon.window
    if win and win:IsShown() and addon.RefreshList then
        addon:RefreshList()
    end
end

function addon:RequestRepaint(immediate)
    if immediate then
        Repaint()
        return
    end
    if repaintPending then return end
    repaintPending = true
    C_Timer.After(0.1, Repaint)
end

-- ============================================================================
-- Custom AceGUI widget: scrollable list of link rows
-- ============================================================================
do
    local Type = "InfoScanList"

    local function Constructor()
        local count = AceGUI:GetNextWidgetNum(Type)
        local frame = CreateFrame("Frame", "GetInfoScanList" .. count, UIParent)
        frame:Hide()

        local scroll = CreateFrame("ScrollFrame", "$parentScrollFrame", frame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 0)
        if scroll.SetClipsChildren then pcall(scroll.SetClipsChildren, scroll, true) end

        local content = CreateFrame("Frame", "$parentContent", scroll)
        content:SetSize(100, ROW_HEIGHT)
        if type(scroll.SetScrollChild) == "function" then
            pcall(scroll.SetScrollChild, scroll, content)
        end

        local widget = {
            type    = Type,
            frame   = frame,
            scroll  = scroll,
            content = content,
            rows    = {},
            entries = {},
            store   = {},
        }

        -- Kept as a closure local on purpose: reading it back off the widget
        -- table would resolve through AceGUI's method table and pick up a
        -- function instead of the number.
        local rowHeight = ROW_HEIGHT
        local rowHeightMeasured = false

        local methods = {}

        function methods:OnAcquire()
            self:SetHeight(220)
            self:SetWidth(500)
            self.scroll:SetVerticalScroll(0)
            self:Fill()
        end

        function methods:OnRelease()
            self.entries, self.store = {}, {}
            for i = 1, #self.rows do
                local row = self.rows[i]
                if row then
                    row.entry = nil
                    row:Hide()
                end
            end
            self.scroll:SetVerticalScroll(0)
            self.frame:Hide()
        end

        function methods:SetData(order, store)
            self.entries = order or {}
            self.store = store or {}
            local maxScroll = self:MaxScroll()
            if (self.scroll:GetVerticalScroll() or 0) > maxScroll then
                self.scroll:SetVerticalScroll(maxScroll)
            end
            self:Fill()
        end

        function methods:ViewHeight()
            -- Usable height of the viewport, from the most trustworthy source
            -- available. GetHeight() alone is not enough: on the live client it
            -- reported about two rows' worth for a 260-unit list, so only two
            -- rows were ever painted, and a hidden or not-yet-laid-out frame
            -- reports 0. A value that cannot hold a few rows is rejected.
            local h = self.scroll.GetHeight and self.scroll:GetHeight() or nil
            if type(h) ~= "number" then h = nil end

            if not h or h < rowHeight * 3 then
                local getTop, getBottom = self.scroll.GetTop, self.scroll.GetBottom
                if type(getTop) == "function" and type(getBottom) == "function" then
                    local top, bottom = getTop(self.scroll), getBottom(self.scroll)
                    if type(top) == "number" and type(bottom) == "number"
                        and (top - bottom) > (h or 0) then
                        h = top - bottom
                    end
                end
            end

            if not h or h < rowHeight * 3 then
                local getHeight = self.frame.GetHeight
                if type(getHeight) == "function" then
                    local fh = getHeight(self.frame)
                    if type(fh) == "number" and fh > (h or 0) then h = fh end
                end
            end

            if not h or h < rowHeight * 3 then
                h = rowHeight * ROW_POOL_MIN
            end

            return h
        end

        function methods:ContentHeight()
            local total = #self.entries
            return math.max(self:ViewHeight(), math.max(1, total) * rowHeight)
        end

        function methods:MaxScroll()
            return math.max(0, self:ContentHeight() - self:ViewHeight())
        end

        function methods:SetScroll(value)
            local v = value or 0
            if v < 0 then v = 0 end
            if v > self:MaxScroll() then v = self:MaxScroll() end
            self.scroll:SetVerticalScroll(v)
            self:Fill()
        end

        function methods:GetScroll()
            return self.scroll:GetVerticalScroll() or 0
        end

        --- Measures the real line height of the row font.
        --- The font's line spacing is larger than its nominal size; assuming a
        --- constant is exactly what broke the list before.
        --- Measured once and cached: Fill() runs on every scroll step and on
        --- every live refresh, and creating a font string each time leaked one
        --- per call.
        function methods:MeasureRowHeight()
            if rowHeightMeasured then return rowHeight end
            local fs = self.content:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
            if not fs then return ROW_HEIGHT end
            fs:SetText("Ag")
            fs:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, 0)

            local h = 0
            if type(fs.GetLineHeight) == "function" then
                local ok, v = pcall(fs.GetLineHeight, fs)
                if ok then h = tonumber(v) or 0 end
            end
            if h <= 0 and type(fs.GetStringHeight) == "function" then
                local ok, v = pcall(fs.GetStringHeight, fs)
                if ok then h = tonumber(v) or 0 end
            end
            fs:Hide()
            -- Do not cache a reading that is obviously not a line height; the
            -- next call retries.
            if h < 8 then return ROW_HEIGHT end
            rowHeight = math.floor(h + 0.5)
            rowHeightMeasured = true
            return rowHeight
        end

        --- Creates one row, or returns the pooled one.
        function methods:CreateRow(index)
            local row = self.rows[index]
            if row then return row end

            row = CreateFrame("Button", nil, self.content)
            if row.RegisterForClicks then row:RegisterForClicks("anyUp") end

            local highlight = row:CreateTexture(nil, "HIGHLIGHT")
            if highlight then
                highlight:SetAllPoints(row)
                highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                if highlight.SetBlendMode then pcall(highlight.SetBlendMode, highlight, "ADD") end
                if highlight.SetAlpha then pcall(highlight.SetAlpha, highlight, 0.4) end
            end

            local idText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            idText:SetPoint("LEFT", row, "LEFT", 2, 0)
            idText:SetWidth(52)
            idText:SetJustifyH("RIGHT")
            row.idText = idText

            local linkText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            linkText:SetPoint("LEFT", idText, "RIGHT", 6, 0)
            linkText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            linkText:SetJustifyH("LEFT")
            linkText:SetWordWrap(false)
            row.linkText = linkText

            row:SetScript("OnEnter", function(self)
                if not self.entry then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.entry.link)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row:SetScript("OnClick", function(self, button)
                if not self.entry then return end
                local link = self.entry.link
                if button ~= "RightButton" and HandleModifiedItemClick
                    and HandleModifiedItemClick(link) then
                    return
                end
                local editBox = ChatFrame1EditBox
                if editBox then
                    editBox:Show()
                    editBox:SetText(link)
                    editBox:HighlightText()
                    if editBox.SetFocus then editBox:SetFocus() end
                end
            end)

            self.rows[index] = row
            return row
        end

        local function PlaceRow(row, content, index, rowHeight)
            row:SetHeight(rowHeight)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * rowHeight)
            row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(index - 1) * rowHeight)
        end

        --- Paints the rows for the current scroll offset.
        ---
        --- Indexing rule, which the first version got wrong: rows are pooled by
        --- screen slot (1..visible+1), but slot i shows entries[offset + i].
        --- The row must therefore be placed at the CONTENT position of
        --- entries[offset + i] -- that is, at slot "offset + i" -- because the
        --- ScrollFrame already shifts the whole content by the scroll offset.
        --- Placing slot i at content position i applied the offset twice: after
        --- scrolling past one screen every painted row sat outside the viewport
        --- and the list went blank, and rows in between showed entries whose
        --- position did not match their own.
        function methods:Fill()
            -- Setting the content height changes the scroll range, which can
            -- clamp the offset and fire OnVerticalScroll, which calls Fill
            -- again. Repainting is idempotent, so a second entry is stopped.
            if self.filling then return end
            if not self.frame:IsShown() then return end
            self.filling = true

            rowHeight = self:MeasureRowHeight() or ROW_HEIGHT

            local visible = math.max(1, math.floor(self:ViewHeight() / rowHeight))
            local needed = visible + 1
            for i = #self.rows + 1, needed do
                self:CreateRow(i)
            end

            local offset = math.floor(self:GetScroll() / rowHeight + 0.5)
            local total = #self.entries
            local maxOffset = math.max(0, total - visible)
            if offset > maxOffset then offset = maxOffset end
            if offset < 0 then offset = 0 end

            for i = 1, #self.rows do
                local row = self.rows[i]
                if row then
                    PlaceRow(row, self.content, offset + i, rowHeight)
                    local id = self.entries[offset + i]
                    local entry = id and self.store[id]
                    if i <= visible and entry and row.idText and row.linkText then
                        row.entry = entry
                        row.idText:SetText(tostring(entry.id))
                        row.linkText:SetText(entry.link)
                        local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[entry.quality or 1]
                        if color then
                            row.idText:SetTextColor(color.r or 1, color.g or 1, color.b or 1)
                        else
                            row.idText:SetTextColor(1, 1, 1)
                        end
                        row:Show()
                    else
                        row.entry = nil
                        row:Hide()
                    end
                end
            end

            self.content:SetHeight(self:ContentHeight())
            if type(self.scroll.UpdateScrollChildRect) == "function" then
                pcall(self.scroll.UpdateScrollChildRect, self.scroll)
            end

            self.filling = nil
        end

        function methods:OnWidthSet(width)
            if width then self.content:SetWidth(math.max(100, width - 28)) end
        end

        function methods:OnHeightSet()
            self:Fill()
        end

        function methods:OnMouseWheel(delta)
            -- Deliberately does NOT move the scroll offset. The scroll frame has
            -- the client's own mouse wheel enabled, so it scrolls natively;
            -- moving it here as well would scroll two steps per notch. All this
            -- has to do is make sure the rows follow, which OnVerticalScroll
            -- also does.
            self:Fill()
            return false
        end

        function methods:EnableMouseWheel(state)
            if self.scroll.EnableMouseWheel then
                pcall(self.scroll.EnableMouseWheel, self.scroll, state ~= false)
            end
        end

        function methods:SetDisabled(state)
            if self.frame.EnableMouse then
                pcall(self.frame.EnableMouse, self.frame, not state)
            end
        end

        function methods:IsDisabled()
            return false
        end

        for name, fn in pairs(methods) do
            widget[name] = fn
        end

        -- Repaint on every scroll change, whatever moved it.
        --
        -- This is the fix for rows that stayed put while the viewport scrolled.
        -- The scroll frame can be moved by paths that never call SetScroll on
        -- this widget: the scrollbar of UIPanelScrollFrameTemplate drives it
        -- directly, and EnableMouseWheel lets the client scroll it natively.
        -- Without this hook the offset moved and the rows did not, so scrolling
        -- down lost the later entries and scrolling up lost the earlier ones.
        -- A periodic repaint during a scan masked the whole problem, which is
        -- why it only appeared once the scan had finished.
        --
        -- HookScript rather than SetScript, so the template's own handler (it
        -- keeps the scrollbar thumb in step) is preserved.
        local function OnScrollChanged()
            widget:Fill()
        end

        local hooked = pcall(function()
            scroll:HookScript("OnVerticalScroll", OnScrollChanged)
        end)
        if not hooked then
            local previous = scroll.GetScript and scroll:GetScript("OnVerticalScroll")
            scroll:SetScript("OnVerticalScroll", function(self, offset)
                if previous then pcall(previous, self, offset) end
                OnScrollChanged()
            end)
        end

        AceGUI:RegisterAsWidget(widget)
        return widget
    end

    AceGUI:RegisterWidgetType(Type, Constructor, 1)
end

-- ============================================================================
-- Progress bar
--
-- A plain StatusBar is used rather than an AceGUI slider: a slider would let the
-- user drag the progress indicator, which is meaningless.
--
-- The bar is anchored LEFT and RIGHT to its holder rather than given a fixed
-- width, so it follows the window when it is resized. The holder is full width,
-- so both anchors resolve from the window itself and no recalculation is needed.
-- A pinned 560 stayed 560 while the window grew.
-- ============================================================================
local function CreateProgressBar(parent, height)
    local bar = CreateFrame("StatusBar", nil, parent)
    if not bar then return nil end
    bar:SetHeight(height or 16)
    bar:SetPoint("LEFT", parent, "LEFT", 0, 0)
    bar:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
    if type(bar.SetStatusBarTexture) == "function" then
        pcall(bar.SetStatusBarTexture, bar, "Interface\\TargetingFrame\\UI-StatusBar")
    end
    if type(bar.SetStatusBarColor) == "function" then
        pcall(bar.SetStatusBarColor, bar, 0.25, 0.75, 0.35)
    end
    if type(bar.SetMinMaxValues) == "function" then
        pcall(bar.SetMinMaxValues, bar, 0, 100)
    end
    if type(bar.SetValue) == "function" then
        pcall(bar.SetValue, bar, 0)
    end

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    if bg then
        bg:SetAllPoints(bar)
        bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
        if bg.SetVertexColor then pcall(bg.SetVertexColor, bg, 0.15, 0.15, 0.15, 0.9) end
    end

    return bar
end

-- ============================================================================
-- Build instrumentation
--
-- A window built as one unguarded block fails as a whole. That is exactly what
-- happened: AceGUI's Frame:SetStatusTable asserts when handed a non-table, the
-- assert removed every control built after it, and the frame stayed on screen
-- showing only its title. pcall swallowed the reason, so the window looked
-- half-drawn for no visible cause.
--
-- Every band now goes through Step(), which names the failure, reports it, and
-- keeps building. A partial window is still usable and the cause is readable.
-- ============================================================================
addon.buildLog = addon.buildLog or {}
-- Repairs such as recreating a missing SavedVariables table are notes, not
-- failures. Keeping them apart means the error count only ever reports real
-- step failures.
addon.buildNotes = addon.buildNotes or {}

local function Step(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if ok then return true end
    local entry = ("%s: %s"):format(label, tostring(err))
    local log = addon.buildLog
    log[#log + 1] = entry
    addon:Print(L.BUILD_STEP_FAILED:format(entry))
    return false
end

--- Recursively counts the widgets in an AceGUI container tree.
local function CountWidgets(widget)
    local n = 0
    local children = widget and widget.children
    if type(children) == "table" then
        for i = 1, #children do
            n = n + 1 + CountWidgets(children[i])
        end
    end
    return n
end

--- Reports what the window is actually made of. A window that built only
--- partly is this addon's recurring failure, so it is stated explicitly rather
--- than left for the user to infer from a blank panel.
function addon:PrintBuildReport()
    local win = self.window
    if not win then
        self:Print(L.BUILD_NONE)
        return
    end

    self:Print((L.BUILD_OK):format(#(win.children or {}), CountWidgets(win)))

    local wanted = {
        "fromBox", "toBox", "delayBox", "scanBtn", "stopBtn",
        "progressBar", "progressText",
        "headerText", "list", "copyBox", "tabs",
        "copyBtn", "exportBtn", "clearBtn",
    }
    local missing = {}
    for i = 1, #wanted do
        if win[wanted[i]] == nil then
            missing[#missing + 1] = wanted[i]
        end
    end
    if #missing > 0 then
        self:Print((L.BUILD_MISSING):format(table.concat(missing, ", ")))
    end

    -- Whether Escape really reaches this window. It is the one piece of window
    -- behaviour that depends on a client global, so it is stated rather than
    -- assumed: the name has to resolve through _G to the live frame.
    local escName = self.escFrameName
    local escLive = type(escName) == "string" and _G[escName] == win.frame
    self:Print((L.BUILD_ESC):format(tostring(escName or "-"),
        escLive and L.ESC_STATE_OK or (self.escError or L.ESC_STATE_BAD)))

    local notes = self.buildNotes or {}
    if #notes > 0 then
        self:Print((L.BUILD_NOTES):format(#notes))
        for i = 1, #notes do
            self:Print("  " .. notes[i])
        end
    end

    local log = self.buildLog or {}
    if #log == 0 then
        self:Print(L.BUILD_NO_ERRORS)
    else
        self:Print((L.BUILD_ERRORS):format(#log))
        for i = 1, #log do
            self:Print("  " .. log[i])
        end
    end
end

-- ============================================================================
-- Window chrome
--
-- This client accepts SetBackdrop on a BackdropTemplate frame but paints no
-- backdrop, and the dialog art AceGUI asks for (UI-DialogBox-Background /
-- -Border and the header banner) does not show. GetInfoLink -- an addon that
-- demonstrably works on this same client -- never calls SetBackdrop at all and
-- paints its panel from texture 136548 instead.
--
-- The body is therefore drawn here from plain textures, which needs no template
-- and no dialog art. AceGUI's own (inert) backdrop attempt is left alone; it
-- simply does nothing.
-- ============================================================================
local PANEL_TEXTURE = 136548  -- UI-Character-CharacterTab-L1, as used by GetInfoLink

--- Paints a texture with the art path proven to render on this client.
local function PaintArt(texture, r, g, b, a)
    if not texture then return false end
    local ok = pcall(texture.SetTexture, texture, PANEL_TEXTURE)
    if not ok then
        -- last resort: the old SetTexture(r, g, b[, a]) form
        ok = pcall(texture.SetTexture, texture, r, g, b, a)
    end
    if not ok then return false end
    pcall(texture.SetTexCoord, texture, 0.255, 1, 0.29, 1)
    if texture.SetVertexColor then pcall(texture.SetVertexColor, texture, r, g, b) end
    if texture.SetAlpha then pcall(texture.SetAlpha, texture, a) end
    return true
end

--- Paints a texture with a flat colour, which needs no art file at all.
local function PaintColor(texture, r, g, b, a)
    if not texture then return false end
    if type(texture.SetColorTexture) == "function" then
        if pcall(texture.SetColorTexture, texture, r, g, b, a) then return true end
    end
    return (pcall(texture.SetTexture, texture, r, g, b, a))
end

--- One 1px border segment between two corners of the frame.
local function Edge(frame, p1, x1, y1, p2, x2, y2, axis)
    local t = frame:CreateTexture(nil, "BORDER")
    if not t then return nil end
    t:SetPoint(p1, frame, p1, x1, y1)
    t:SetPoint(p2, frame, p2, x2, y2)
    if axis == "h" then
        t:SetHeight(1)
    else
        t:SetWidth(1)
    end
    PaintColor(t, 0.55, 0.48, 0.34, 0.9)
    return t
end

--- Draws the window body inside an AceGUI frame.
--- Returns true when a panel texture was created.
local function DrawWindowChrome(widget)
    local frame = widget.frame
    if not frame then return false end

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    if not bg then return false end
    bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -6)
    bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
    PaintArt(bg, 1, 1, 1, 0.98)

    Edge(frame, "TOPLEFT",     5, -5, "TOPRIGHT",    -5, -5, "h")
    Edge(frame, "BOTTOMLEFT",  5,  5, "BOTTOMRIGHT", -5,  5, "h")
    Edge(frame, "TOPLEFT",     5, -5, "BOTTOMLEFT",   5,  5, "v")
    Edge(frame, "TOPRIGHT",   -5, -5, "BOTTOMRIGHT", -5,  5, "v")

    return true
end

-- ============================================================================
-- Type tabs
--
-- All four tabs used to look identical, so which type was selected could only be
-- discovered by clicking one and reading the status line. The active tab now gets
-- a tinted plate plus a coloured label.
--
-- The label text is the same glyphs either way -- only colour codes are added --
-- so the Flow row does not reflow when the selection moves. The tint sits on the
-- BORDER layer: above the button's own art, below the label, so the text stays
-- readable.
-- ============================================================================
local TAB_ACTIVE = { 0.15, 0.85, 0.45, 0.40 }

--- The label for one tab, marked when it is the active one.
local function TabLabel(index, active)
    local def = addon.SCAN_TYPES[index]
    local text = (def and L["TAB_" .. def.key:upper()]) or "?"
    if active then
        return "|cff33ff99" .. text .. "|r"
    end
    return text
end

--- Paints the tabs so the selected one can be told apart at a glance.
function addon:RefreshTabs()
    local win = self.window
    if not win or type(win.tabs) ~= "table" then return end

    local types = self.SCAN_TYPES or {}
    for i = 1, #win.tabs do
        local tab = win.tabs[i]
        local def = types[i]
        local active = (def ~= nil and def.key == self.scan.typeKey)

        if type(tab) == "table" and tab.frame then
            if not tab.tabTint then
                local tint = tab.frame:CreateTexture(nil, "BORDER")
                if tint then
                    tint:SetAllPoints(tab.frame)
                    tab.tabTint = tint
                end
            end

            local tint = tab.tabTint
            if tint then
                if active and PaintColor(tint, TAB_ACTIVE[1], TAB_ACTIVE[2], TAB_ACTIVE[3], TAB_ACTIVE[4]) then
                    tint:SetAlpha(1)
                else
                    tint:SetAlpha(0)
                end
            end

            tab:SetText(TabLabel(i, active))
        end
    end
end

-- ============================================================================
-- Sizing the list to the window
--
-- AceGUI's "List" layout gives every child the height it was told and has no
-- concept of a child that fills the space left over -- only "Flow" understands
-- SetFullHeight, and there a fill-height child has to come last, which does not
-- fit a list with a copy box underneath it. A list pinned to 260 therefore
-- stayed 260 while the window grew, which is what made the window look
-- hardcoded. The list is instead given whatever the fixed rows leave behind.
-- ============================================================================
local lastListHeight = nil

local function FitListToWindow()
    local win = addon.window
    if not win or not win.list or not win.content then return end

    local available
    if type(win.content.GetHeight) == "function" then
        local ok, value = pcall(win.content.GetHeight, win.content)
        if ok and type(value) == "number" then available = value end
    end
    if not available or available <= 0 then return end

    local children = win.children
    if type(children) ~= "table" then return end

    -- Everything except the list has a fixed height, so the remainder is its.
    local used = 0
    for i = 1, #children do
        local child = children[i]
        if child ~= win.list and type(child) == "table" then
            local frame = child.frame
            local h = frame and frame.height
            if type(h) ~= "number" and frame and type(frame.GetHeight) == "function" then
                local ok, value = pcall(frame.GetHeight, frame)
                if ok then h = value end
            end
            if type(h) == "number" and h > 0 then used = used + h end
        end
    end

    local want = available - used
    if want < 80 then want = 80 end
    -- Same value again means no resize event, which is also what stops the
    -- layout that follows from looping.
    if lastListHeight and math.abs(lastListHeight - want) <= 0.5 then return end
    lastListHeight = want

    win.list:SetHeight(want)

    -- The copy box sits below the list and has to move to its new place.
    if type(win.DoLayout) == "function" then
        pcall(win.DoLayout, win)
    end
end

-- ============================================================================
-- Remembering the typed range
--
-- The start ID, end ID and speed are the user's own input, so they are stored
-- verbatim and restored when the window is built. Text is stored rather than
-- numbers so that whatever was typed comes back exactly as typed; validation
-- happens when a scan starts, as before.
-- ============================================================================
local function SavedRange()
    local range = type(GetInfoScanDB) == "table" and GetInfoScanDB.range
    if type(range) ~= "table" then
        range = { from = "1", to = "5000", delay = "0.08" }
        if type(GetInfoScanDB) == "table" then
            GetInfoScanDB.range = range
        end
    end
    return range
end

--- Stores the three boxes into the saved range. Reading uses GetText, which
--- AceGUI's EditBox forwards to the underlying frame.
function addon:SaveRange()
    local win = self.window
    if not win then return end
    local range = SavedRange()

    local function take(key, box)
        if box and type(box.GetText) == "function" then
            local ok, value = pcall(box.GetText, box)
            if ok and type(value) == "string" then
                range[key] = value
            end
        end
    end

    take("from", win.fromBox)
    take("to", win.toBox)
    take("delay", win.delayBox)
end

--- Saves on every keystroke, so the values survive even if no scan is started.
--- AceGUI's EditBox does not fire OnTextChanged for programmatic SetText, so
--- restoring the values does not loop back into another save.
local function Remember(box)
    if box and type(box.SetCallback) == "function" then
        box:SetCallback("OnTextChanged", function() addon:SaveRange() end)
    end
    return box
end

-- ============================================================================
-- Escape key
--
-- Escape is handled by the client itself: pressing it runs CloseSpecialWindows,
-- which walks UISpecialFrames, resolves every entry through _G and hides what it
-- finds. That is the list every other addon on this client registers with, and
-- it takes names, not frames -- which matters here because AceGUI builds its
-- frame anonymously (CreateFrame("Frame", nil, UIParent)), so GetName() returns
-- nil and cannot be used the way a hand-made named frame can. Publishing the
-- frame under a fixed name makes the lookup succeed.
-- ============================================================================
local ESC_FRAME_NAME = "GetInfoScanMainFrame"

--- Publishes the window so the client's own Escape handling closes it.
--- Re-published on every build, so a rebuild points the name at the new frame
--- instead of leaving it on the widget that was just released back into the
--- AceGUI pool.
function addon:RegisterEscClose(frame)
    frame = frame or (self.window and self.window.frame)
    self.escFrameName = ESC_FRAME_NAME

    if type(frame) ~= "table" then
        self.escError = L.ESC_NO_FRAME
        return false
    end
    if type(UISpecialFrames) ~= "table" then
        self.escError = L.ESC_NO_LIST
        return false
    end

    _G[ESC_FRAME_NAME] = frame

    local listed = false
    for i = 1, #UISpecialFrames do
        if UISpecialFrames[i] == ESC_FRAME_NAME then
            listed = true
            break
        end
    end
    if not listed then
        UISpecialFrames[#UISpecialFrames + 1] = ESC_FRAME_NAME
    end

    self.escError = nil
    return true
end

-- ============================================================================
-- Window construction
-- ============================================================================
--- A labelled edit box, stacked vertically inside its own group.
local function LabeledBox(container, label, width, value)
    local holder = AceGUI:Create("SimpleGroup")
    holder:SetWidth(width)
    holder:SetHeight(48)
    holder:SetLayout("List")

    local lbl = AceGUI:Create("Label")
    lbl:SetText(label)
    lbl:SetFullWidth(true)
    lbl:SetHeight(18)
    holder:AddChild(lbl)

    local box = AceGUI:Create("EditBox")
    box:SetFullWidth(true)
    box:SetHeight(22)
    box:DisableButton(true)
    if value then box:SetText(value) end
    box:SetCallback("OnEnterPressed", function() addon:OnScanClicked() end)
    holder:AddChild(box)

    container:AddChild(holder)
    return box
end

--- A horizontal strip of controls.
--- Its height is deliberately NOT set. AceGUI's Flow layout measures its rows and
--- reports the total back through LayoutFinished, so the strip re-measures and
--- re-wraps whenever the window is resized. Pinning a height here is part of what
--- made the window look hardcoded.
local function Row(container)
    local row = AceGUI:Create("SimpleGroup")
    row:SetFullWidth(true)
    row:SetLayout("Flow")
    container:AddChild(row)
    return row
end

function addon:BuildWindow()
    if type(self.window) == "table" and self.window.type == "Frame" then
        return self.window
    end

    self.buildLog = {}
    self.buildNotes = {}
    local notes = self.buildNotes

    -- Frame:SetStatusTable asserts on anything that is not a table, and that
    -- bare assert used to destroy the whole window. The geometry table is
    -- therefore validated and repaired here rather than trusted to have been
    -- created by Core.lua in an earlier file.
    local status = type(GetInfoScanDB) == "table" and GetInfoScanDB.window
    if type(status) ~= "table" then
        status = { width = 660, height = 620 }
        if type(GetInfoScanDB) == "table" then
            GetInfoScanDB.window = status
        end
        notes[#notes + 1] = "geometry table was missing; a default was created"
    end

    -- The options table used to be validated here because two check boxes were
    -- built from it. Both are gone: they wrote their state into SavedVariables
    -- but nothing ever read it, so ticking them changed nothing at all.

    local f
    if not Step("create frame", function()
        f = AceGUI:Create("Frame")
        if not f then error("AceGUI:Create('Frame') returned nil") end
    end) then
        return nil
    end

    -- Publish the handle immediately. No later step may be able to leave
    -- addon.window nil, or the window is on screen while /gis denies it exists.
    self.window = f

    Step("title",    function() f:SetTitle(L.WINDOW_TITLE) end)
    Step("geometry", function()
        f:SetWidth(status.width or 660)
        f:SetHeight(status.height or 620)
    end)
    Step("resize",   function() f:EnableResize(true) end)
    Step("layout",   function() f:SetLayout("List") end)
    Step("status",   function() f:SetStatusTable(status) end)
    Step("chrome",   function()
        if not DrawWindowChrome(f) then
            error("no panel texture could be created")
        end
    end)

    -- No OnClose handler is registered on purpose. AceGUI fires OnClose from the
    -- frame's OnHide script, so the usual
    --   f:SetCallback("OnClose", function(w) AceGUI:Release(w) end)
    -- releases the widget on every hide -- after which addon.window is nil and
    -- the window can never be reopened. Releasing is done only in RebuildWindow.

    -- Escape closes the window. A client without UISpecialFrames is not a broken
    -- window, so the failure is a note rather than a build error; the close
    -- button keeps working either way.
    Step("escape key", function()
        if not self:RegisterEscClose(f.frame) then
            notes[#notes + 1] = "escape key: " .. tostring(self.escError)
        end
    end)

    -- ------------------------------------------------------- range / speed
    Step("range row", function()
        local row1 = Row(f)
        -- Restore what was typed last time rather than the defaults.
        local range = SavedRange()
        f.fromBox  = Remember(LabeledBox(row1, L.LABEL_START, 110, range.from))
        f.toBox    = Remember(LabeledBox(row1, L.LABEL_END,   110, range.to))
        f.delayBox = Remember(LabeledBox(row1, L.LABEL_DELAY,  90, range.delay))
    end)

    -- ------------------------------------------------- scan / action controls
    -- Everything that acts on the scan lives on this one row: start and stop,
    -- the four type tabs, and the three result actions (copy / export / clear).
    --
    -- The actions used to share a second row with two check boxes, and neither
    -- of those did anything -- their state was written to SavedVariables and
    -- never read, so ticking them changed nothing. Removing them freed the row,
    -- and the actions were moved up onto the scan row to give the list back the
    -- height the second row was eating.
    Step("scan buttons", function()
        local row2 = Row(f)

        -- SetAutoWidth, never SetWidth: AceGUI's Button measures its own label
        -- (width = text + 30), but OnAcquire switches auto-width off, so an
        -- explicit width clips whatever does not fit. That is exactly why the
        -- Chinese label rendered as "复制...". It also lets the label change
        -- (Start Scan / Pause / Continue) without ever being cut off.
        local function MakeButton(text, handler, name)
            local btn = AceGUI:Create("Button")
            btn:SetAutoWidth(true)
            btn:SetText(text)
            if handler then btn:SetCallback("OnClick", handler) end
            row2:AddChild(btn)
            -- Kept on the window so the build report can name the ones that
            -- failed; the tabs keep their own list instead.
            if name then f[name] = btn end
            return btn
        end

        f.scanBtn = MakeButton(L.BTN_SCAN, function() addon:OnScanClicked() end)
        f.stopBtn = MakeButton(L.BTN_STOP, function() addon:StopScan() end)
        f.stopBtn:SetDisabled(true)

        f.tabs = {}
        for i = 1, #self.SCAN_TYPES do
            local def = self.SCAN_TYPES[i]
            local tab = MakeButton(L["TAB_" .. def.key:upper()],
                function() addon:SelectType(def.key) end)
            tab:SetCallback("OnEnter", function(widget)
                if not def.apiCheck() then
                    GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
                    GameTooltip:AddLine((L.ERR_NO_API):format(addon:TypeLabel(def.key)),
                        1, 0.3, 0.3, true)
                    GameTooltip:Show()
                end
            end)
            tab:SetCallback("OnLeave", function() GameTooltip:Hide() end)
            f.tabs[i] = tab
        end

        self:RefreshTabs()

        -- Auto-width for the same reason as the scan buttons: the Chinese
        -- labels are long, and a fixed width clipped them to "复制...".
        MakeButton(L.BTN_COPY,   function() addon:CopyLinks() end,    "copyBtn")
        MakeButton(L.BTN_EXPORT, function() addon:Export() end,       "exportBtn")
        MakeButton(L.BTN_CLEAR,  function() addon:ClearResults() end, "clearBtn")
    end)

    -- ------------------------------------------------------------- progress
    -- The bar is a fixed-height spacer inside a List layout, so it does not
    -- fight AceGUI's flow for space.
    Step("progress band", function()
        local barRow = AceGUI:Create("SimpleGroup")
        barRow:SetFullWidth(true)
        barRow:SetHeight(24)
        barRow:SetLayout("None")
        f:AddChild(barRow)
        f.progressBar = CreateProgressBar(barRow.frame, 16)
        if f.progressBar then
            f.progressBar:SetValue(0)
        end

        f.progressText = AceGUI:Create("Label")
        f.progressText:SetFullWidth(true)
        f.progressText:SetHeight(20)
        f.progressText:SetText(L.PROGRESS_IDLE)
        f:AddChild(f.progressText)
    end)

    Step("result heading", function()
        f.headerText = AceGUI:Create("Heading")
        f.headerText:SetFullWidth(true)
        f.headerText:SetText(L.HDR_RESULTS .. ": 0")
        f:AddChild(f.headerText)
    end)

    -- ----------------------------------------------------------------- list
    Step("result list", function()
        f.list = AceGUI:Create("InfoScanList")
        f.list:SetFullWidth(true)
        f.list:SetHeight(260)
        f:AddChild(f.list)
    end)

    -- ------------------------------------------------------ copy helper box
    -- A plain EditBox rather than AceGUI's MultiLineEditBox: the latter depends
    -- on named child frames inside a Blizzard template, which is exactly the
    -- kind of client-specific assumption this addon avoids.
    Step("copy box", function()
        f.copyBox = AceGUI:Create("EditBox")
        f.copyBox:SetFullWidth(true)
        f.copyBox:SetHeight(24)
        f.copyBox:DisableButton(true)
        f.copyBox:SetText("")
        f:AddChild(f.copyBox)
    end)

    Step("status text", function()
        -- The selected type is prepended by SelectType; on its own this is the
        -- client's own answer, with no inferred label in front of it.
        f:SetStatusText(addon:ClientLine())
    end)

    -- Give the list the leftover height, and keep giving it on every resize.
    -- OnHeightSet is the hook AceGUI itself uses for this: it runs both from
    -- SetHeight and from the frame's OnSizeChanged, so dragging the resize grip
    -- keeps the list in step with the window.
    Step("list fills the window", function()
        lastListHeight = nil
        local baseOnHeightSet = f.OnHeightSet
        f.OnHeightSet = function(widget, height)
            if baseOnHeightSet then baseOnHeightSet(widget, height) end
            FitListToWindow()
        end
        FitListToWindow()
    end)

    Step("initial state", function()
        addon:SelectType("item", true)
        addon:RefreshProgress()
        addon:RefreshButtons()
        -- The boxes already hold the remembered range. Writing "1" / "5000"
        -- here is what reset the user's input on every single reload.
    end)

    -- Built hidden: a login screen is not the place to force a window open.
    -- AceGUI shows a frame as part of Create, so it is hidden again here.
    pcall(f.Hide, f)

    return f
end

--- Throws the current window away and builds a fresh one. Releasing is only
--- done here, never from OnClose, because AceGUI fires OnClose from OnHide.
function addon:RebuildWindow()
    local old = self.window
    self.window = nil
    if type(old) == "table" and old.type == "Frame" and old.frame then
        -- The published Escape name must not keep pointing at a widget that is
        -- about to go back into the AceGUI pool -- another addon could acquire
        -- it, and Escape would then close that addon's window. The build below
        -- publishes the new frame under the same name.
        if _G[ESC_FRAME_NAME] == old.frame then
            _G[ESC_FRAME_NAME] = nil
        end
    end
    if type(old) == "table" and old.type == "Frame" then
        pcall(AceGUI.Release, AceGUI, old)
    end

    local win = self:EnsureWindow()
    if win then
        self:ShowWindow()
        self:Print(L.BUILD_REBUILT)
    end
    self:PrintBuildReport()
    return win
end

-- ============================================================================
-- Type selection
-- ============================================================================
function addon:SelectType(key, silent)
    local def = self:GetScanTypeDef(key)
    if not def then return end

    self.scan.typeKey = key

    local win = self.window
    if win then
        if not silent then
            local from = self:ReadNumber(win.fromBox)
            local to = self:ReadNumber(win.toBox)
            if not from and win.fromBox then win.fromBox:SetText(tostring(def.defaultFrom)) end
            if not to and win.toBox then win.toBox:SetText(tostring(def.defaultTo)) end
        end

        if win.SetStatusText then
            -- "type  |  <what the client says>". ClientLine reads GetBuildInfo /
            -- GetLocale / WOW_PROJECT_ID -- it never invents a version line, so
            -- what is on screen here can be quoted in a bug report as-is.
            win:SetStatusText(("%s  |  %s"):format(
                self:TypeLabel(def.key), self:ClientLine()))
        end
    end

    -- The tab marker is part of the selection, so it moves with it.
    self:RefreshTabs()
end

-- ShowTypeHelp(key) used to live here. It printed "<type> - API ready/missing"
-- but nothing ever called it, so /gis status is the only report of API
-- availability now -- and that one covers every type at once.

-- ============================================================================
-- Refresh
-- ============================================================================
-- Namespace rule, which the first AceGUI version got wrong:
--   addon.window   = the AceGUI frame handle (show/hide/SetStatusText)
--   addon.<control>= the controls it contains (list, progressBar, scanBtn, ...)
-- Reading a control off the frame handle always yields nil, because an AceGUI
-- widget resolves unknown keys to the library's method table.
function addon:RefreshList()
    local win = self.window
    if not win or not win.list then return end
    local order, results = self:GetResults()
    win.list:SetData(order, results)
    -- The heading was set once at build time and never updated, so it always
    -- read "Results: 0" no matter how many links were found.
    if win.headerText then
        win.headerText:SetText(("%s: %d"):format(L.HDR_RESULTS, #order))
    end
end

function addon:RefreshProgress()
    local state = self.scan
    local win = self.window
    if not win then return end
    local bar, text = win.progressBar, win.progressText
    if not bar or not text then return end

    if state.active then
        local percent = 0
        if state.total > 0 then
            percent = (state.scanned / state.total) * 100
        end
        if percent > 100 then percent = 100 end
        bar:SetValue(percent)

        if state.paused then
            text:SetText(L.PROGRESS_PAUSED)
        else
            local def = self:GetScanTypeDef(state.typeKey)
            text:SetText((L.PROGRESS_SCANNING):format(
                self:TypeLabel(def and def.key), percent))
        end
    elseif state.scanned > 0 then
        bar:SetValue(100)
        text:SetText((L.PROGRESS_STOPPED):format(state.scanned, #state.order,
            state.missing or 0))
    else
        bar:SetValue(0)
        text:SetText(L.PROGRESS_IDLE)
    end
end

function addon:RefreshButtons()
    local win = self.window
    if not win then return end
    local state = self.scan

    if win.scanBtn then
        if state.active then
            win.scanBtn:SetText(state.paused and L.BTN_RESUME or L.BTN_PAUSE)
        else
            win.scanBtn:SetText(L.BTN_SCAN)
        end
    end

    if win.stopBtn then
        win.stopBtn:SetText(L.BTN_STOP)
        win.stopBtn:SetDisabled(not state.active)
    end
end

--- Repaints progress, buttons and list together.
function addon:RefreshLive()
    local win = self.window
    if not win or not win:IsShown() then return end
    addon:RefreshProgress()
    addon:RefreshButtons()
    self:RefreshList()
end

-- ============================================================================
-- Window control
--
-- ToggleWindow lives in Core.lua so it stays reachable even when construction
-- fails; it calls back into ShowWindow/HideWindow.
-- ============================================================================
function addon:ShowWindow()
    local win = self.window
    -- Self-healing: if the widget is not a live AceGUI frame, rebuild it rather
    -- than silently refusing to open. A released widget used to leave the
    -- minimap button and /gis looking dead.
    if type(win) ~= "table" or win.type ~= "Frame" then
        win = self:EnsureWindow()
    end
    if not win then return end
    win:Show()
    self:RefreshList()
    addon:RefreshProgress()
    addon:RefreshButtons()
end

function addon:HideWindow()
    local win = self.window
    if not win then return end
    win:Hide()
end

function addon:ToggleOptions()
    self:ToggleWindow()
end

-- ============================================================================
-- Scan button
-- ============================================================================
function addon:OnScanClicked()
    local state = self.scan

    if state.active then
        self:TogglePause()
        return
    end

    if not self.window then return end

    local win = self.window
    local from = self:ReadNumber(win.fromBox)
    local to = self:ReadNumber(win.toBox)
    local delay = self:ReadNumber(win.delayBox)
    if not delay or delay <= 0 then delay = 0.08 end

    if not from or not to then
        self:Print(L.ERR_RANGE)
        return
    end

    if to < from then
        from, to = to, from
        win.fromBox:SetText(tostring(from))
        win.toBox:SetText(tostring(to))
    end

    -- Keep what was actually used, including a swap.
    self:SaveRange()

    self:StartScan(state.typeKey, from, to, delay)
end
