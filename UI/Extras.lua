-- Wolf: minimap button, the button on the auction house, item tooltip lines, alert toasts.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local ICON = FT.LOGO

---------------------------------------------------------------------------
-- Minimap button (and a launcher for broker bars when one is loaded)
---------------------------------------------------------------------------
local mb

local function PlaceMinimap()
    local a = math.rad(FT.S.minimapAngle or 205)
    local r = (Minimap:GetWidth() or 140) / 2 + 8
    mb:ClearAllPoints()
    mb:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function MinimapTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cfff0b90bWolf|r")
    local last = FT.Hist.LastScan()
    GameTooltip:AddLine(L["Scan"] .. ": " .. (last and FT.Ago(last) or L["never"]), 0.6, 0.64, 0.7)
    GameTooltip:AddLine(" ")
    local s = FT.Session.Current()
    if s then
        local sum = FT.Session.Summary(s)
        GameTooltip:AddLine(string.format(s.auto and L["Farming (by itself): %s, %s an hour"] or L["Session: %s, %s an hour"], FT.Money(math.floor(sum.worth), "short"),
            sum.perHour and FT.Money(math.floor(sum.perHour), "short") or "..."), 0.05, 0.8, 0.5)
    end
    local fresh, newer = FT.Alerts()
    if fresh then GameTooltip:AddLine(L["Newer prices are waiting: right-click to load them."], 0.12, 1, 0.12, true) end
    if newer then
        local C = FT.Companion
        GameTooltip:AddLine(string.format((C and C.Updates()) and (C.Pending() and L["Wolf v%s is ready: it goes in when you restart the game."] or L["Wolf v%s is ready: right-click to load it."])
            or L["Wolf v%s is out: update it in the CurseForge app or WowUp."], newer), 1, 0.82, 0, true)
    end
    if fresh or newer then GameTooltip:AddLine(" ") end
    GameTooltip:AddLine(L["Click: open / close the window"], 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L["Right-click: sessions, and what's waiting"], 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L["Drag: move"], 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

local menu, menuBlock -- the right-click menu and the click-anywhere-to-close layer under it

-- the right-click menu: start or stop a session, nothing else (the rest is a left-click away; pause is on the panel)
local function MenuItems()
    local S = FT.Session
    local items = {}
    local fresh, newer = FT.Alerts()
    if fresh then items[#items + 1] = { L["Load the fresh prices"], function() ReloadUI() end, "up" } end
    if newer then
        local C = FT.Companion
        if C and C.Updates() and C.Pending() then
            items[#items + 1] = { string.format(L["v%s goes in when the game restarts"], newer), nil, "muted" }
        elseif C and C.Updates() then
            items[#items + 1] = { string.format(L["Load Wolf v%s (reload)"], newer), function() ReloadUI() end, "accent" }
        else
            items[#items + 1] = { string.format(L["Get v%s (CurseForge)"], newer), function() FT.ShowCurseForge() end, "accent" }
        end
    end
    if #items > 0 then items[#items + 1] = { "-" } end
    if S.Current() then
        items[#items + 1] = { S.Current().auto and L["Stop the farming session"] or L["Stop the session"], function() S.Stop() end, "down" }
    else
        items[#items + 1] = { L["Start a session"], function() S.Start() end, "up" }
    end
    return items
end

-- (v0.57) what's waiting, quietly: newer prices on disk (green dot), a newer Wolf (gold dot); nothing else
function FT.Alerts()
    local fresh = FT.Companion and FT.Companion.FreshReady() or false
    local newer = FT.Ver and FT.Ver.Outdated and FT.Ver.Outdated() or nil
    return fresh, newer
end
function FT.UpdateMinimapDot()
    if not (mb and mb.dot) then return end
    local fresh, newer = FT.Alerts()
    mb.dot:SetShown(fresh or newer ~= nil)
    UI.SetTexColor(mb.dot, fresh and "up" or "accent", 1)
end

-- items: { { label, fn, color } or { "-" } } (none: the session menu of the minimap button)
function FT.ShowMenu(anchor, given)
    UI.ResolveFont()
    if not menuBlock then
        menuBlock = CreateFrame("Button", nil, UIParent)
        menuBlock:SetAllPoints(UIParent)
        menuBlock:SetFrameStrata("FULLSCREEN_DIALOG")
        menuBlock:RegisterForClicks("AnyUp")
        menuBlock:SetScript("OnClick", function() menu:Hide(); menuBlock:Hide() end)
        menu = CreateFrame("Frame", nil, UIParent)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(menuBlock:GetFrameLevel() + 5)
        menu:SetClampedToScreen(true)
        UI.Skin(menu, "popup", "bg2")
        menu.rows = {}
        tinsert(UISpecialFrames, "WolfOfBootyBayMenu")
    end
    local items = given or MenuItems()
    local y, w = -6, 170
    for i, it in ipairs(items) do
        local row = menu.rows[i]
        if not row then
            row = CreateFrame("Button", nil, menu)
            row.hl = UI.RoundTex(row, "BACKGROUND", "hl", 1)
            row.hl:SetAllPoints()
            row.hl:Hide()
            row.text = UI.Text(row, 12, "text")
            row.text:SetPoint("LEFT", 10, 0)
            row.line = UI.HLine(row, "line")
            row.line:SetPoint("LEFT", 8, 0)
            row.line:SetPoint("RIGHT", -8, 0)
            row:SetScript("OnEnter", function(self) if self.fn then self.hl:Show() end end)
            row:SetScript("OnLeave", function(self) self.hl:Hide() end)
            row:SetScript("OnClick", function(self)
                menu:Hide()
                menuBlock:Hide()
                if self.fn then self.fn() end
            end)
            menu.rows[i] = row
        end
        local sep = it[1] == "-"
        row:SetHeight(sep and 9 or 22)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 4, y)
        row:SetPoint("RIGHT", menu, "RIGHT", -4, 0)
        row.fn = not sep and it[2] or nil
        row:EnableMouse(row.fn ~= nil)
        row.text:SetShown(not sep)
        row.line:SetShown(sep)
        if not sep then
            row.text:SetText(it[1])
            UI.SetTextColor(row.text, it[3] or "text")
            w = math.max(w, math.ceil(row.text:GetStringWidth()) + 30)
        end
        row:Show()
        y = y - row:GetHeight()
    end
    for i = #items + 1, #menu.rows do menu.rows[i]:Hide() end
    menu:SetSize(w, -y + 6)
    menu:ClearAllPoints()
    local x, cy = GetCursorPosition()
    local sc = UIParent:GetEffectiveScale()
    menu:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", x / sc, cy / sc)
    menuBlock:Show()
    menu:Show()
end

local function BuildMinimap()
    mb = CreateFrame("Button", "WolfOfBootyBayMinimapButton", Minimap)
    mb:SetSize(31, 31)
    mb:SetFrameStrata("MEDIUM")
    mb:SetFrameLevel(8)
    mb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mb:RegisterForDrag("LeftButton")
    mb:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local bg = mb:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(22, 22)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("CENTER")
    local icon = mb:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetTexture(ICON)
    if icon.SetMask then icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask") end
    icon:SetPoint("CENTER")
    local border = mb:CreateTexture(nil, "OVERLAY")
    border:SetSize(52, 52)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")
    mb.dot = UI.Dot(mb, 9, "up", 1, "OVERLAY")
    mb.dot:SetPoint("TOPRIGHT", -3, -3)
    mb.dot:Hide()
    C_Timer.NewTicker(60, FT.UpdateMinimapDot)
    FT.On("FT_NEWER_VERSION", FT.UpdateMinimapDot)
    C_Timer.After(5, FT.UpdateMinimapDot)
    -- a click: the window; right-click: sessions, and what's waiting
    mb:SetScript("OnClick", function(self, button)
        if button == "RightButton" then FT.ShowMenu(self) else FT.Toggle() end
    end)
    mb:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            FT.S.minimapAngle = math.deg(math.atan2(py / s - my, px / s - mx))
            PlaceMinimap()
        end)
    end)
    mb:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    mb:SetScript("OnEnter", MinimapTooltip)
    mb:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function FT.UpdateMinimap()
    if not FT.S.minimap then
        if mb then mb:Hide() end
        return
    end
    if not mb then BuildMinimap() end
    PlaceMinimap()
    mb:Show()
end

local function MakeBroker()
    local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
    if not (ldb and ldb.NewDataObject) then return end
    ldb:NewDataObject("Wolf", {
        type = "launcher", label = "Wolf", text = "Wolf", icon = ICON,
        OnClick = function(self, button)
            if button == "RightButton" then FT.ShowMenu(self) else FT.Toggle() end
        end,
        OnTooltipShow = function(tt)
            if not (tt and tt.AddLine) then return end
            tt:AddLine("Wolf")
            local last = FT.Hist.LastScan()
            tt:AddLine(L["Scan"] .. ": " .. (last and FT.Ago(last) or L["never"]), 0.6, 0.64, 0.7)
        end,
    })
end

---------------------------------------------------------------------------
-- Auction house: a button that opens Wolf right next to it
---------------------------------------------------------------------------
local ahButton

local function AHFrame()
    return AuctionFrame or AuctionHouseFrame
end

-- the auction house's Wolf tab is Snipe now: without a tab library, the panel docks beside the auction house
local function ToggleFromAH()
    local ah = AHFrame()
    local p = FT.SnipePanel.Get(UIParent)
    if p:IsShown() then p:Hide() return end
    p:SetParent(UIParent)
    p:ClearAllPoints()
    if ah then p:SetPoint("TOPLEFT", ah, "TOPRIGHT", 6, 0) else p:SetPoint("CENTER") end
    p:SetSize(660, 440)
    p:SetFrameStrata("HIGH")
    p:Show()
end

local function TipAH(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("|cfff0b90bWolf|r")
    GameTooltip:AddLine(L["This visit (what you bought and posted, against usual), your watchlist live, deals after a scan, past visits."], 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end

-- the text of the tab: Snipe, how far a scan got, how many are underpriced now
local function AHLabel()
    local frac = FT.Scanner.Running() and FT.Scanner.Progress()
    if frac then return string.format("%s  %d%%", L["Wolf"], math.floor(frac * 100)) end
    local n = FT.SnipePanel and FT.SnipePanel.Count() or 0
    return n > 0 and string.format("%s (%d)", L["Wolf"], n) or L["Wolf"]
end

-- The modern auction house: a tab in the row of its tabs, the game's own look. With Auctionator its tab
-- library places it after Auctionator's tabs; without it we put it after the game's last tab.
local function BuildAHTab(ah)
    local tab, libTab
    local lib = LibStub and LibStub("LibAHTab-1-0", true)
    if lib and lib.CreateTab then
        local ok = pcall(function()
            if not lib:DoesIDExist("Wolf") then
                -- the Snipe panel, shown inside the auction house when its tab is picked (like Auctionator's)
                local holder = CreateFrame("Frame", nil, ah)
                holder:SetPoint("TOPLEFT", ah, "TOPLEFT", 4, -60)
                holder:SetPoint("BOTTOMRIGHT", ah, "BOTTOMRIGHT", -4, 28)
                local p = FT.SnipePanel.Get(holder)
                p:SetParent(holder)
                p:SetAllPoints(holder)
                p:Show()
                lib:CreateTab("Wolf", holder, L["Wolf"])
            end
            tab = lib:GetButton("Wolf")
        end)
        if not ok then tab = nil end
        if tab then libTab = true end
    end
    if not tab then
        local ok, made = pcall(CreateFrame, "Button", "WolfOfBootyBayAHTab", ah, "AuctionHouseFrameDisplayModeTabTemplate")
        if not ok or not made then return nil end
        tab = made
        tab:SetText("Wolf")
        -- after the game's last tab (the template may have put ours in that list already: not after itself)
        local last
        for i = #(ah.Tabs or {}), 1, -1 do
            local t = ah.Tabs[i]
            if t and t ~= tab and t.IsShown and t:IsShown() then
                last = t
                break
            end
        end
        tab:ClearAllPoints()
        if not (last and pcall(tab.SetPoint, tab, "TOPLEFT", last, "TOPRIGHT", 3, 0)) then
            tab:SetPoint("TOPRIGHT", ah, "BOTTOMRIGHT", -4, 2)
        end
    end
    -- with the tab library it shows the Snipe panel inside the auction house; without it, the panel beside it
    if not libTab then
        tab:SetScript("OnClick", function(self)
            ToggleFromAH()
            if PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(self) end
        end)
    end
    tab:HookScript("OnEnter", TipAH)
    tab:HookScript("OnLeave", function() GameTooltip:Hide() end)
    if PanelTemplates_TabResize then PanelTemplates_TabResize(tab, 20, nil, 70) end
    if PanelTemplates_DeselectTab and not libTab then PanelTemplates_DeselectTab(tab) end
    tab.SetLabel = function(self, text)
        self:SetText(text)
        if PanelTemplates_TabResize then PanelTemplates_TabResize(self, 20, nil, 70) end
    end
    tab.GetLabel = function(self) return self:GetText() end
    return tab
end

-- The classic auction house (or no tab template): our own button
local function BuildAHPlainButton(ah)
    local b = UI.Button(ah, L["Wolf"], 10, 22, "default", ToggleFromAH)
    b.style = { bg = "bg0", bgA = 0.92, hover = "bg2", hoverA = 1, text = "accent", border = "line" }
    b:SetActive(false)
    b:FitText(24)
    b:SetFrameStrata("HIGH")
    if ah == AuctionFrame then
        b:SetPoint("TOPRIGHT", ah, "TOPRIGHT", -40, -13)
    else
        b:SetPoint("TOPRIGHT", ah, "BOTTOMRIGHT", -4, -2)
    end
    b:SetTip("Wolf", L["This visit (what you bought and posted, against usual), your watchlist live, deals after a scan, past visits."])
    local set = b.SetLabel
    b.SetLabel = function(self, text)
        set(self, text)
        self:FitText(24)
    end
    b.GetLabel = function(self) return self.label:GetText() end
    return b
end

local function BuildAHButton()
    local ah = AHFrame()
    if not ah or ahButton then return end
    if ah == AuctionHouseFrame then ahButton = BuildAHTab(ah) end
    ahButton = ahButton or BuildAHPlainButton(ah)
    -- while Wolf scans, the button shows how far it got
    ahButton.ftElapsed = 0
    ahButton:HookScript("OnUpdate", function(self, elapsed)
        self.ftElapsed = self.ftElapsed + elapsed
        if self.ftElapsed < 0.3 then return end
        self.ftElapsed = 0
        local label = AHLabel()
        if self:GetLabel() ~= label then self:SetLabel(label) end
    end)
end

FT.On("AUCTION_HOUSE_SHOW", function()
    -- a moment later: Auctionator adds its tabs first, ours goes after them
    C_Timer.After(0.4, function()
        if not FT.S.ahButton then
            if ahButton then ahButton:Hide() end
            return
        end
        BuildAHButton()
        if ahButton then ahButton:Show() end
    end)
end)

-- the Snipe panel beside the auction house goes with it
FT.On("AUCTION_HOUSE_CLOSED", function()
    local p = FT.SnipePanel and FT.SnipePanel.Panel()
    if p and p:GetParent() == UIParent then p:Hide() end
end)

---------------------------------------------------------------------------
-- Item tooltips
---------------------------------------------------------------------------
-- Two lines on an item's tooltip (bags, Bagnon, chat links...):
--   Wolf  HODL                               2.1g  +4% today
--   Best use: Thorium Bar, 2.6g each (+24%)   - or: Craft profit, or what it disenchants for
-- Shift: the reason in plain words, how much sells a day, the week's move.
-- The game refreshes a bag item's tooltip many times a second while you hover it: the lines are worked out once
-- and kept (10 seconds, or until new prices come), and in combat only kept lines are shown - nothing is worked
-- out there. Nothing of the bag addon is touched: lines are added after the game (or the bag addon) has set the
-- tooltip, and the tooltip isn't redrawn by us.
local tipCache = {}
local TIP_FRESH = 10
FT.On("FT_PRICES_CHANGED", function() wipe(tipCache) end)
FT.On("FT_SCAN_DONE", function() wipe(tipCache) end)
FT.On("FT_LEARNED", function() wipe(tipCache) end)

local function TipLines(itemID, detail)
    local s = FT.An.Stats(itemID)
    local rs = FT.Craft.ByOutput(itemID)
    local de = FT.Enchant and FT.Enchant.Value and FT.Enchant.Value(itemID)
    if not s.price and not rs and not de then return false end
    local out = {}
    -- 1: our price, like Auctionator's line it sits under: "Wolf API      8g 05s  1h"
    local sig, _, reason = FT.An.SellSignal(s)
    if s.price then
        local _, name, age = FT.PriceTag(s.source, s.t)
        out[#out + 1] = { "|cfff0b90bWolf|r " .. name, FT.Money(s.price, "short") .. (age and FT.C("dim", "  " .. age) or "") }
        -- 2: what to do with it (CASH OUT, HODL...), today's move beside it
        if sig ~= "NODATA" then
            out[#out + 1] = { FT.C(FT.SIGNAL_COLORS[sig] or "muted", FT.SignalText(sig)),
                s.ch1 and (FT.Pct(s.ch1) .. FT.C("dim", " " .. L["today"])) or "" }
        end
    end
    -- 3: a craft's profit, or what it disenchants for
    local second
    if rs and rs[1] then
        local e = FT.Craft.Eval(rs[1])
        if e.profit then
            second = string.format(L["Craft it: profit %s"], FT.C(e.profit >= 0 and "up" or "down", FT.Money(e.profit, "short")))
        end
    end
    if not second and de then
        -- worth disenchanting, or worth more sold as it is (auction house after its cut, or a vendor)?
        local asIs = math.max(s.price and s.price * (1 - FT.Cut()) or 0, FT.VendorSell(itemID) or 0)
        if asIs > 0 and asIs >= de then
            second = string.format(L["Sell it: %s beats disenchanting (~%s)"], FT.Money(math.floor(asIs), "short"), FT.Money(math.floor(de), "short"))
        else
            second = string.format(L["Disenchant it: ~%s"], FT.Money(math.floor(de), "short"))
                .. (asIs > 0 and FT.C("dim", " " .. string.format(L["(sells for %s)"], FT.Money(math.floor(asIs), "short"))) or "")
        end
    end
    if second then out[#out + 1] = { second } end
    -- Shift: the reason, how much sells, the week
    if detail then
        if reason and sig ~= "NODATA" then out[#out + 1] = { FT.C("muted", reason) } end
        local bits = {}
        if s.sales and s.sales.perDay then bits[#bits + 1] = FT.Sales.PerDayText(s.sales) end
        if s.ch7 then bits[#bits + 1] = L["7d"] .. " " .. FT.Pct(s.ch7) end
        if s.rsi then bits[#bits + 1] = L["Hype"] .. " " .. string.format("%.0f", s.rsi) end
        if #bits > 0 then out[#out + 1] = { FT.C("dim", table.concat(bits, "  ·  ")) } end
        out[#out + 1] = { FT.C("dim", L["Price from"] .. ": " .. FT.PriceFrom(itemID)) }
    elseif FT.S.tooltipHint ~= false then
        -- (the hint fits on line 2 when there's room)
    end
    return out
end

-- Our lines go right under Auctionator's (Vendor / Auction / Disenchant), not after every other addon's (bag counts,
-- drop sources): the lines between move down. Only when it's safe: Auctionator's lines are found, and no line in
-- that stretch carries an icon (an icon belongs to its line and wouldn't move with the text).
local ATR_LABELS = { "^Auction", "^Vendor", "^Disenchant" }
local function Plain(t) return (t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
local function UnderAuctionator(tt, first, last)
    local name = tt.GetName and tt:GetName()
    if not name or first <= 2 then return end
    local after
    for i = first - 1, 2, -1 do
        local fs = _G[name .. "TextLeft" .. i]
        local t = fs and Plain(fs:GetText())
        for _, pat in ipairs(ATR_LABELS) do
            if t and t:find(pat) then after = i break end
        end
        if after then break end
    end
    if not after or after == first - 1 then return end
    for i = 1, 30 do
        local tex = _G[name .. "Texture" .. i]
        if tex and tex.IsShown and tex:IsShown() then return end
    end
    -- read every line from under Auctionator's to the end, then write them back: ours first
    local lines = {}
    for i = after + 1, last do
        local l, r = _G[name .. "TextLeft" .. i], _G[name .. "TextRight" .. i]
        if not l then return end
        local lr, lg, lb = l:GetTextColor()
        local rr, rg, rb = 1, 1, 1
        if r then rr, rg, rb = r:GetTextColor() end
        lines[#lines + 1] = { l:GetText(), { lr, lg, lb }, r and r:IsShown() and r:GetText() or nil, { rr, rg, rb } }
    end
    local n = last - first + 1
    local order = {}
    for k = #lines - n + 1, #lines do order[#order + 1] = lines[k] end
    for k = 1, #lines - n do order[#order + 1] = lines[k] end
    for k, x in ipairs(order) do
        local i = after + k
        local l, r = _G[name .. "TextLeft" .. i], _G[name .. "TextRight" .. i]
        l:SetText(x[1] or "")
        l:SetTextColor(x[2][1], x[2][2], x[2][3])
        if r then
            if x[3] then
                r:SetText(x[3])
                r:SetTextColor(x[4][1], x[4][2], x[4][3])
                r:Show()
            else
                r:SetText("")
                r:Hide()
            end
        end
    end
    tt:Show() -- the size again
end

local function AddLines(tt, itemID)
    if not (FT.S and FT.S.tooltip and itemID) then return end
    if tt.IsForbidden and tt:IsForbidden() then return end
    local detail = IsShiftKeyDown and IsShiftKeyDown() or false
    local key = itemID .. (detail and "+" or "")
    local c = tipCache[key]
    local now = GetTime()
    if not (c and (now - c.t < TIP_FRESH or InCombatLockdown())) then
        if InCombatLockdown() then return end -- nothing is worked out in a fight
        local ok, lines = pcall(TipLines, itemID, detail)
        if not ok then FT.Debug(lines) lines = false end
        c = { t = now, lines = lines }
        tipCache[key] = c
    end
    if not c.lines then return end
    local first = tt:NumLines() + 1
    for _, l in ipairs(c.lines) do
        if l[2] then tt:AddDoubleLine(l[1], l[2], 0.8, 0.82, 0.86, 1, 1, 1)
        else tt:AddLine(l[1], 0.8, 0.82, 0.86) end
    end
    if #c.lines > 0 then UnderAuctionator(tt, first, tt:NumLines()) end
end

local function HookTooltips()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
            if (tt == GameTooltip or tt == ItemRefTooltip) and data and data.id then AddLines(tt, data.id) end
        end)
        return
    end
    local function OnSet(tt)
        local _, link = tt:GetItem()
        local id = FT.ItemIDFromLink(link)
        if id then AddLines(tt, id) end
    end
    GameTooltip:HookScript("OnTooltipSetItem", OnSet)
    if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipSetItem", OnSet) end
end

---------------------------------------------------------------------------
-- Alert toasts
---------------------------------------------------------------------------
local toasts = {}

local function Restack()
    local y = -120
    for _, t in ipairs(toasts) do
        if t:IsShown() then
            t:ClearAllPoints()
            t:SetPoint("TOP", UIParent, "TOP", 0, y)
            y = y - t:GetHeight() - 6
        end
    end
end

local function NewToast()
    local t = CreateFrame("Button", nil, UIParent)
    t:SetSize(360, 56)
    t:SetFrameStrata("FULLSCREEN_DIALOG")
    UI.Skin(t, "popup", "bg1")
    local bar = UI.RoundTex(t, "ARTWORK", "accent", 1, nil, "left", UI.RADIUS - 1)
    t.bar = bar
    bar:SetWidth(3)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMLEFT", 1, 1)
    t.icon = UI.Icon(t, 34)
    t.icon:SetPoint("LEFT", 14, 0)
    t.title = UI.Text(t, 11, "accent")
    t.title:SetPoint("TOPLEFT", t.icon, "TOPRIGHT", 10, 0)
    t.title:SetText(L["Price alert"])
    t.text = UI.Text(t, 12, "text")
    t.text:SetPoint("TOPLEFT", t.title, "BOTTOMLEFT", 0, -4)
    t.text:SetPoint("RIGHT", t, "RIGHT", -12, 0)
    t:SetScript("OnClick", function(self)
        if self.itemID then FT.OpenItem(self.itemID) end
        self:Hide()
        Restack()
    end)
    t:SetScript("OnUpdate", function(self, elapsed)
        self.age = (self.age or 0) + elapsed
        if self:IsMouseOver() then
            self.age = math.min(self.age, 6)
            self:SetAlpha(1)
            return
        end
        if self.age > 7 then
            self:SetAlpha(math.max(0, 1 - (self.age - 7)))
            if self.age > 8 then
                self:Hide()
                Restack()
            end
        end
    end)
    return t
end

-- title and color: a banner of its own (the meme layer); nil = a price alert
function FT.Toast(itemID, text, title, color)
    UI.ResolveFont()
    local t
    for _, x in ipairs(toasts) do
        if not x:IsShown() then
            t = x
            break
        end
    end
    if not t then
        if #toasts >= 4 then
            t = toasts[1]
            table.remove(toasts, 1)
        else
            t = NewToast()
        end
        toasts[#toasts + 1] = t
    end
    t.itemID = itemID
    color = color or "accent"
    t.title:SetText(title or L["Price alert"])
    UI.SetTextColor(t.title, color)
    UI.SetTexColor(t.bar, color, 1)
    t.icon:SetItem(itemID)
    t.text:SetText(FT.ItemText(itemID, 30) .. " " .. text)
    t.age = 0
    t:SetAlpha(1)
    t:Show()
    Restack()
end

---------------------------------------------------------------------------
-- Start and /wolf debug
---------------------------------------------------------------------------
FT.On("FT_READY", function()
    UI.ResolveFont()
    FT.UpdateMinimap()
    pcall(MakeBroker)
    pcall(HookTooltips)
end)

function FT.DebugReport()
    FT.Print("side " .. tostring(FT.sideKey) .. ", house " .. tostring(FT.house) .. " (" .. tostring(FT.houseKey)
        .. "), cut " .. string.format("%.1f%%", FT.Cut() * 100) .. ", char " .. tostring(FT.charKey))
    FT.Print("Auctionator " .. tostring(FT.Atr.Loaded()) .. ", days " .. tostring(FT.Atr.HistoryDays()))
    FT.Print("feed: " .. FT.Feed.Describe() .. " (ruleset " .. tostring(FT.Feed.Ruleset()) .. ", house "
        .. tostring(FT.Feed.HouseID(FT.house)) .. ")")
    FT.Print("recipes " .. #FT.Craft.List() .. ", tracked " .. FT.Hist.UniverseSize())
    -- recipes by profession: how many the Craft page has, how many Wolf read itself (Mastercraft: the rest)
    local all, own = {}, {}
    for _, r in ipairs(FT.Craft.List()) do all[r.prof] = (all[r.prof] or 0) + 1 end
    for _, profs in pairs(FT.db.recipes or {}) do
        for prof, data in pairs(type(profs) == "table" and profs or {}) do
            local n = type(data) == "table" and type(data.list) == "table" and #data.list or 0
            own[prof] = (own[prof] or 0) + n
            all[prof] = all[prof] or 0
        end
    end
    local parts = {}
    for prof, n in pairs(all) do parts[#parts + 1] = string.format("%s %d (own %d)", L[prof] or prof, n, own[prof] or 0) end
    table.sort(parts)
    FT.Print("by profession: " .. table.concat(parts, ", "))
    local items, size = FT.Hist.Footprint()
    FT.Print("history items " .. items .. ", saved " .. size .. " chars, font " .. tostring(UI.FONT))
    local rows = FT.Market.Rows()
    FT.Print("market rows " .. tostring(rows and #rows) .. (FT.Market.Building() and ", building" or "")
        .. ((FT.Market.errors or 0) > 0 and (", errors " .. FT.Market.errors .. " (" .. tostring(FT.Market.firstError) .. ")") or ""))
    -- the good deals: what the last look saw
    local list, at, building = FT.Deals.List()
    local info = FT.Deals.Info()
    local kinds = {}
    for _, d in ipairs(list) do kinds[d.kind] = (kinds[d.kind] or 0) + 1 end
    FT.Print(string.format("deals %d (vendor %d, resell %d, between houses %d), looked %s%s", #list, kinds.VENDOR or 0,
        kinds.RESELL or 0, kinds.HOUSES or 0, at and FT.Ago(at) or "never", building and ", looking now" or ""))
    if info then
        FT.Print(string.format("deals: items %d, newest price %s, 3+ days %d, under the minimum %d, vendor prices to load %d, errors %d%s",
            info.items, FT.Ago(info.newest), info.history, info.small, FT.Deals.Loading(), info.errors,
            info.firstError and (" (" .. info.firstError .. ")") or ""))
    end
    FT.Print(FT.Scanner.LiveState())
end

---------------------------------------------------------------------------
-- A link to copy (the game can't open a browser): support the author, the project on GitHub
---------------------------------------------------------------------------
local linkDialog

local function LinkDialog()
    if linkDialog then return linkDialog end
    UI.ResolveFont()
    local d = CreateFrame("Frame", "WolfOfBootyBayLinkDialog", UIParent)
    d:SetSize(440, 150)
    d:SetPoint("CENTER", 0, 120)
    d:SetFrameStrata("FULLSCREEN_DIALOG")
    d:SetToplevel(true)
    d:EnableMouse(true)
    d:SetMovable(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)
    UI.Skin(d, "window", "bg1")
    local bar = UI.RoundTex(d, "ARTWORK", "accent", 1, nil, "top", UI.RADIUS - 1)
    bar:SetHeight(2)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    d.title = UI.Text(d, 14, "text")
    d.title:SetPoint("TOPLEFT", 16, -16)
    d.body = UI.Text(d, 11, "muted")
    d.body:SetPoint("TOPLEFT", 16, -40)
    d.body:SetPoint("RIGHT", d, "RIGHT", -16, 0)
    d.input = UI.Input(d, 408, 26, "")
    d.input:SetPoint("TOPLEFT", 16, -64)
    -- read only: whatever is typed, the link comes back, selected
    d.input:SetScript("OnTextChanged", function(self, user)
        if user then
            self:SetText(d.url or "")
            self:HighlightText()
        end
    end)
    d.input:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    d.input:SetScript("OnEscapePressed", function() d:Hide() end)
    d.input:SetScript("OnEnterPressed", function() d:Hide() end)
    d.hint = UI.Text(d, 11, "dim")
    d.hint:SetPoint("TOPLEFT", 16, -100)
    d.hint:SetText(L["Ctrl+C to copy"])
    d.close = UI.Button(d, L["Close"], 10, 24, "default", function() d:Hide() end)
    d.close:FitText(28)
    d.close:SetPoint("BOTTOMRIGHT", -16, 14)
    tinsert(UISpecialFrames, "WolfOfBootyBayLinkDialog")
    d:Hide()
    linkDialog = d
    return d
end

function FT.ShowLink(title, body, url)
    local d = LinkDialog()
    d.url = url
    d.title:SetText(title)
    d.body:SetText(body)
    d.input:SetText(url)
    d:Show()
    d:Raise()
    d.input:SetFocus()
    d.input:HighlightText()
end

---------------------------------------------------------------------------
-- A name to type (a new watchlist group, a rename): the link dialog's look, with an OK
---------------------------------------------------------------------------
local askDialog

function FT.AskText(title, body, default, onOK)
    if not askDialog then
        UI.ResolveFont()
        local d = CreateFrame("Frame", "WolfOfBootyBayAskText", UIParent)
        d:SetSize(400, 150)
        d:SetPoint("CENTER", 0, 120)
        d:SetFrameStrata("FULLSCREEN_DIALOG")
        d:SetToplevel(true)
        d:EnableMouse(true)
        UI.Skin(d, "window", "bg1")
        d.title = UI.Text(d, 14, "text")
        d.title:SetPoint("TOPLEFT", 16, -16)
        d.body = UI.Text(d, 11, "muted")
        d.body:SetPoint("TOPLEFT", 16, -40)
        d.body:SetPoint("RIGHT", d, "RIGHT", -16, 0)
        d.input = UI.Input(d, 368, 26, "")
        d.input:SetPoint("TOPLEFT", 16, -64)
        local function OK()
            local text = d.input:GetText()
            d:Hide()
            if d.onOK and text and text:match("%S") then d.onOK(text) end
        end
        d.input:SetScript("OnEnterPressed", OK)
        d.input:SetScript("OnEscapePressed", function() d:Hide() end)
        d.ok = UI.Button(d, L["OK"], 10, 24, "primary", OK)
        d.ok:FitText(28)
        d.ok:SetPoint("BOTTOMRIGHT", -16, 14)
        d.cancel = UI.Button(d, L["Cancel"], 10, 24, "default", function() d:Hide() end)
        d.cancel:FitText(28)
        d.cancel:SetPoint("RIGHT", d.ok, "LEFT", -8, 0)
        tinsert(UISpecialFrames, "WolfOfBootyBayAskText")
        d:Hide()
        askDialog = d
    end
    local d = askDialog
    d.onOK = onOK
    d.title:SetText(title)
    d.body:SetText(body or "")
    d.input:SetText(default or "")
    d:Show()
    d:Raise()
    d.input:SetFocus()
    d.input:HighlightText()
end

---------------------------------------------------------------------------
-- The watchlist menu of one item: watch it (alone, with its materials, in a group of yours), move it, remove it
---------------------------------------------------------------------------
function UI.WatchMenu(id, anchor)
    local M = FT.Market
    local items = {}
    local function NewGroupThen(fn)
        FT.AskText(L["New watchlist group"], L["A name for it (Flask mats, Flips, Raid night...)"], "", function(name)
            local g = M.NewGroup(name)
            if g then fn(g) end
        end)
    end
    if not M.IsWatched(id) then
        items[#items + 1] = { L["Watch it"], function() M.Watch(id) end }
        if UI.RecipeOf and UI.RecipeOf(id) then
            items[#items + 1] = { L["Watch it and its materials"], function()
                local g, n = M.WatchWithMaterials(id)
                FT.Print(string.format(L["Watching %s and its %d materials, in the group %s."], FT.ItemText(id), n, g))
            end }
        end
        items[#items + 1] = { "-" }
        for _, g in ipairs(M.WatchGroups()) do
            items[#items + 1] = { string.format(L["Watch it in: %s"], g), function() M.Watch(id, g) end }
        end
        items[#items + 1] = { L["Watch it in a new group..."], function() NewGroupThen(function(g) M.Watch(id, g) end) end }
    else
        local cur, own = M.GroupOf(id)
        items[#items + 1] = { FT.C("dim", string.format(L["In the group: %s"], cur)) }
        for _, g in ipairs(M.WatchGroups()) do
            if g ~= cur then items[#items + 1] = { string.format(L["Move to: %s"], g), function() M.Watch(id, g) end } end
        end
        items[#items + 1] = { L["Move to a new group..."], function() NewGroupThen(function(g) M.Watch(id, g) end) end }
        if own then
            items[#items + 1] = { string.format(L["Back to: %s"], M.AutoGroup(id)), function() M.Watch(id, false) end }
        end
        items[#items + 1] = { "-" }
        items[#items + 1] = { L["Remove from the watchlist"], function() M.Unwatch(id) end, "down" }
    end
    items[#items + 1] = { "-" }
    -- a long hold: you know it'll be worth more later (a raid or phase coming) - it never says SELL until unmarked
    local hold = FT.db.longHold and FT.db.longHold[id]
    items[#items + 1] = { hold and L["Long hold: on (click to stop)"] or L["Long hold (never say SELL)"], function()
        FT.db.longHold = FT.db.longHold or {}
        FT.db.longHold[id] = (not FT.db.longHold[id]) or nil
        FT.Fire("FT_SETTINGS_CHANGED")
        FT.Fire("FT_WATCH_CHANGED", id)
    end }
    FT.ShowMenu(anchor, items)
end

-- a group of yours: rename it, or let it go (its items stay watched)
function UI.WatchGroupMenu(name, anchor)
    local M = FT.Market
    FT.ShowMenu(anchor, {
        { L["Rename the group..."], function()
            FT.AskText(L["Rename the group"], name, name, function(new) M.RenameGroup(name, new) end)
        end },
        { L["Remove the group (its items stay watched)"], function() M.DeleteGroup(name) end, "down" },
    })
end

---------------------------------------------------------------------------
-- Best use: every recipe a material goes into, ranked by what one of it brings (FT.Craft.BestUse)
---------------------------------------------------------------------------
local bestUse

local function BestUseWindow()
    if bestUse then return bestUse end
    UI.ResolveFont()
    local d = CreateFrame("Frame", "WolfOfBootyBayBestUse", UIParent)
    local ts = tonumber(FT.S and FT.S.textSize) or 0
    d:SetSize(720 + 30 * ts, 460)
    d:SetPoint("CENTER", 0, 60)
    d:SetFrameStrata("DIALOG")
    d:SetToplevel(true)
    d:EnableMouse(true)
    d:SetMovable(true)
    d:SetClampedToScreen(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)
    UI.Skin(d, "window", "bg1")
    local bar = UI.RoundTex(d, "ARTWORK", "accent", 1, nil, "top", UI.RADIUS - 1)
    bar:SetHeight(2)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    d.icon = UI.Icon(d, 30)
    d.icon:SetPoint("TOPLEFT", 16, -14)
    d.title = UI.Text(d, 14, "text")
    d.title:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 10, -1)
    d.title:SetPoint("RIGHT", d, "RIGHT", -110, 0)
    d.raw = UI.Text(d, 11, "muted")
    d.raw:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -4)
    d.raw:SetPoint("RIGHT", d, "RIGHT", -16, 0)
    d.close = UI.Button(d, L["Close"], 10, 22, "default", function() d:Hide() end)
    d.close:FitText(24)
    d.close:SetPoint("TOPRIGHT", -14, -14)
    d.chart = UI.Button(d, L["Chart"], 10, 22, "default", function()
        if d.itemID then FT.OpenItem(d.itemID) end
    end)
    d.chart:FitText(24)
    d.chart:SetPoint("RIGHT", d.close, "LEFT", -6, 0)
    d.chart:Hide() -- v0.42: one way to each thing (the item's name opens its page)
    -- the order: the most each one of it brings, or what sells most (the gold a day it moves through that product)
    d.sort = UI.Segmented(d, { { "each", L["Most per one"] }, { "sells", L["Best sellers"] } }, function(v)
        d.sortBy = v
        if d.itemID then FT.ShowBestUse(d.itemID) end
    end, 22)
    d.sort:SetPoint("TOPLEFT", 16, -62)
    d.sortBy = "each"
    d.sort:SetValue("each")
    local panel = UI.Panel(d, "bg0", "line")
    panel:SetPoint("TOPLEFT", 12, -92)
    panel:SetPoint("BOTTOMRIGHT", -12, 30)
    local cols = {
        { key = "name", title = L["Makes"], width = "fill" },
        { key = "prof", title = L["Profession"], width = 104 + 8 * ts },
        { key = "need", title = L["Uses"], width = 40 + 4 * ts, justify = "RIGHT" },
        { key = "each", title = L["Worth each"], width = 90 + 8 * ts, justify = "RIGHT" },
        { key = "sold", title = L["Sold a day"], width = 76 + 8 * ts, justify = "RIGHT" },
        { key = "vs", title = L["vs selling it"], width = 84 + 8 * ts, justify = "RIGHT" },
    }
    d.header = UI.Header(panel, cols, function() end)
    d.header:SetPoint("TOPLEFT", 1, -1)
    d.header:SetPoint("TOPRIGHT", -1, -1)
    d.list = UI.List(panel, {
        rowHeight = 24, cols = cols,
        update = function(row, x)
            local r = x.recipe
            row.cells.name:SetText(FT.ItemText(r.output, 34) .. (x.known and FT.C("up", "  " .. L["known"]) or "")
                .. ((not x.sells and x.each) and FT.C("down", "  " .. L["hardly sells"]) or ""))
            row.cells.prof:SetText(FT.C("dim", L[r.prof or "?"]))
            row.cells.need:SetText(FT.Num(x.need))
            row.cells.sold:SetText(x.perDay and FT.Num(math.floor(x.perDay + 0.5)) or FT.C("dim", "-"))
            if x.each then
                row.cells.each:SetText(FT.C(x.each > 0 and "text" or "down", FT.Money(math.floor(x.each), "short")))
                row.cells.vs:SetText(d.raw_ and d.raw_ > 0 and FT.Pct(x.each / d.raw_ - 1) or "")
            else
                row.cells.each:SetText(FT.C("dim", L["no price"]))
                row.cells.vs:SetText("")
            end
        end,
        onClick = function(x) if not UI.ItemClick(x.recipe.output) then FT.OpenItem(x.recipe.output) end end,
        onEnter = function(row, x)
            local r, e = x.recipe, x.eval
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:AddLine(r.name or FT.ItemText(r.output), 1, 1, 1)
            for _, part in ipairs(e.parts or {}) do
                GameTooltip:AddDoubleLine(part.qty .. " x " .. FT.ItemText(part.itemID),
                    part.total and FT.Money(part.total, "short") or L["no price"], 0.8, 0.82, 0.86, 0.8, 0.82, 0.86)
            end
            if e.revenue then
                GameTooltip:AddDoubleLine(L["Sells for"] .. (e.via == "vendor" and (" (" .. L["vendor"] .. ")") or ""),
                    FT.Money(math.floor(e.revenue), "short"), 0.6, 0.64, 0.7, 1, 1, 1)
            end
            if x.known then
                local who = {}
                for name in pairs(r.knownBy) do who[#who + 1] = name end
                GameTooltip:AddLine(L["Known by"] .. " " .. table.concat(who, ", "), 0.3, 0.8, 0.4, true)
            end
            GameTooltip:AddLine(L["Click: its chart"], 0.6, 0.64, 0.7)
            GameTooltip:Show()
        end,
    })
    d.list:SetPoint("TOPLEFT", d.header, "BOTTOMLEFT", 0, -2)
    d.list:SetPoint("BOTTOMRIGHT", -1, 2)
    d.list:SetEmptyText(L["Not a material of any recipe."])
    d.foot = UI.Text(d, 10, "dim")
    d.foot:SetPoint("BOTTOMLEFT", 16, 10)
    d.foot:SetPoint("RIGHT", d, "RIGHT", -16, 0)
    d.foot:SetText(L["Worth each: what the product sells for, minus the other materials, per one of this. Best sellers: that times how many sell a day."])
    tinsert(UISpecialFrames, "WolfOfBootyBayBestUse")
    d:Hide()
    bestUse = d
    return d
end

function FT.ShowBestUse(itemID)
    if not itemID then return end
    local d = BestUseWindow()
    d.itemID = itemID
    d.icon:SetItem(itemID)
    d.title:SetText(L["Best crafts from"] .. " " .. FT.ItemText(itemID, 40))
    local list, raw, via = FT.Craft.BestUse(itemID)
    if d.sortBy == "sells" then
        -- best sellers: what this material is worth through each product, times how many of it sell a day
        list = { unpack(list) }
        local function V(x) return (x.each and x.perDay) and x.each * x.need * x.perDay or -1 end
        table.sort(list, function(a, b)
            local va, vb = V(a), V(b)
            if va ~= vb then return va > vb end
            return (a.recipe.name or "") < (b.recipe.name or "")
        end)
    end
    d.raw_ = raw
    local best = list[1] and list[1].sells and list[1].each
    local line
    if raw then
        line = string.format(L["Sold as it is: %s each%s."], FT.Money(math.floor(raw), "short"),
            via == "vendor" and (" (" .. L["vendor"] .. ")") or "")
    else
        line = L["No price for it as it is yet."]
    end
    if best and raw and best > raw then
        line = line .. "  " .. FT.C("up", string.format(L["Best: make %s, %s more each."], FT.ItemText(list[1].recipe.output, 24), FT.Pct(best / raw - 1, true)))
    elseif best and raw then
        line = line .. "  " .. FT.C("accent", L["Selling it as it is beats every recipe."])
    end
    d.raw:SetText(line .. "  " .. FT.C("dim", string.format(L["%d recipes"], #list)))
    d.list:SetItems(list)
    d:Show()
    d:Raise()
end

---------------------------------------------------------------------------
-- When it sells: the last 48 hours hour by hour, the time of day it sells most (your clock, four weeks) and the
-- day of the week (two weeks) - from the price robot's hourly looks at the whole auction house (FT.Feed.Hourly)
---------------------------------------------------------------------------
local whenWin
local WHEN_H, WHEN_H_SHORT = 790, 240 -- with the charts / the answers only

-- a row of bars: values (nil: not watched, drawn faint), a label under some of them, the best ones in gold
local function Bars(parent, n)
    local f = CreateFrame("Frame", nil, parent)
    f.bars, f.labels = {}, {}
    for i = 1, n do
        local b = UI.Tex(f, "ARTWORK", "accent", 1)
        f.bars[i] = b
        local l = UI.Text(f, 10, "dim", "CENTER")
        f.labels[i] = l
    end
    f.max = UI.Text(f, 10, "dim", "RIGHT")
    f.max:SetPoint("TOPRIGHT", f, "TOPLEFT", -4, 2)
    f.base = UI.HLine(f, "line")
    f.base:SetPoint("BOTTOMLEFT", 0, 14)
    f.base:SetPoint("BOTTOMRIGHT", 0, 14)
    -- the hour it is now: a faint line behind its bar
    f.now = UI.Tex(f, "BACKGROUND", "text", 0.12)
    f.now:Hide()
    -- values, labels (by index), best: indexes in gold; fmt: the top value's text; opts: { low = indexes in blue,
    -- floor = the value at the bottom (differences of a few percent show), now = an index to mark }
    f:SetScript("OnSizeChanged", function(self) if self.args then self:Set(unpack(self.args)) end end)
    function f:Set(values, labels, best, fmt, opts)
        self.args = { values, labels, best, fmt, opts }
        local w, h = self:GetWidth(), self:GetHeight() - 16
        if not w or w <= 0 then return end
        opts = opts or {}
        local floor = opts.floor or 0
        local top = floor
        for i = 1, n do if values[i] and values[i] > top then top = values[i] end end
        local bw = w / n
        for i = 1, n do
            local b, v = self.bars[i], values[i]
            b:ClearAllPoints()
            local bh = (v and top > floor) and math.max(1, math.floor(h * (v - floor) / (top - floor) + 0.5)) or 2
            b:SetPoint("BOTTOMLEFT", (i - 1) * bw + 1, 15)
            b:SetSize(math.max(1, bw - 2), bh)
            if v == nil then UI.SetTexColor(b, "line", 0.6)
            elseif best and best[i] then UI.SetTexColor(b, "accent", 1)
            elseif opts.low and opts.low[i] then UI.SetTexColor(b, "blue", 1)
            else UI.SetTexColor(b, "muted", 0.55) end
            local l = self.labels[i]
            l:ClearAllPoints()
            l:SetPoint("TOP", self, "BOTTOMLEFT", (i - 0.5) * bw, 13)
            l:SetText(labels[i] or "")
        end
        self.now:ClearAllPoints()
        if opts.now then
            self.now:SetPoint("BOTTOMLEFT", (opts.now - 1) * bw, 15)
            self.now:SetSize(bw, h)
            self.now:Show()
        else
            self.now:Hide()
        end
        self.max:SetText(top > floor and (fmt and fmt(top) or FT.Num(top)) or "")
    end
    return f
end

local function HourLabel(h)
    h = h % 24
    if h == 0 then return "12a" elseif h == 12 then return "12p" end
    return h < 12 and (h .. "a") or ((h - 12) .. "p")
end

-- the 3 hours in a row (around the day) that sell the most, and the 3 that sell the least
local function Window(tod)
    local best, bestAt, low, lowAt
    for start = 0, 23 do
        local sum, ok = 0, true
        for k = 0, 2 do
            local v = tod[(start + k) % 24]
            if v == nil then ok = false break end
            sum = sum + v
        end
        if ok then
            if not best or sum > best then best, bestAt = sum, start end
            if not low or sum < low then low, lowAt = sum, start end
        end
    end
    return bestAt, lowAt
end

-- the answer of When it sells, for the item page and the window (v0.42): nil while there are too few sales seen.
-- { sell = "7p-10p" (priciest: post just before), buy = cheapest hours, busy = the hours it sells most, day = its
--   busiest day, timed = the price moves enough through the day to time it, sellAt / buyAt / busyAt (hours), hr }
local DAY_NAMES = { [0] = "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
function FT.WhenSummary(itemID)
    local hr = FT.Feed and FT.Feed.Hourly and FT.Feed.Hourly(itemID)
    if not hr then return nil end
    local out = { hr = hr }
    local bestAt = Window(hr.tod)
    if bestAt then out.busyAt, out.busy = bestAt, HourLabel(bestAt) .. "-" .. HourLabel(bestAt + 3) end
    if hr.todPrice then
        local dearAt, cheapAt = Window(hr.todPrice)
        local function Avg(at)
            if not at then return nil end
            local sum = 0
            for k = 0, 2 do sum = sum + hr.todPrice[(at + k) % 24] end
            return sum / 3 - 1
        end
        local dp, cp = Avg(dearAt), Avg(cheapAt)
        out.timed = dp and cp and (dp - cp) >= 0.02 or false
        out.sellAt, out.buyAt, out.sellPct, out.buyPct = dearAt, cheapAt, dp, cp
        if dearAt then out.sell = HourLabel(dearAt) .. "-" .. HourLabel(dearAt + 3) end
        if cheapAt then out.buy = HourLabel(cheapAt) .. "-" .. HourLabel(cheapAt + 3) end
    end
    local days = FT.Feed.SoldDays and FT.Feed.SoldDays(itemID) or {}
    local sum, cnt = {}, {}
    for day, n in pairs(days) do
        local wd = tonumber(date("!%w", day * 86400))
        sum[wd] = (sum[wd] or 0) + n
        cnt[wd] = (cnt[wd] or 0) + 1
    end
    local bestV
    for wd = 0, 6 do
        local v = cnt[wd] and sum[wd] / cnt[wd]
        if v and (not bestV or v > bestV) then bestV, out.dayAt = v, wd end
    end
    if out.dayAt then out.day = L[DAY_NAMES[out.dayAt]] end
    return out
end

local function WhenWindow()
    if whenWin then return whenWin end
    UI.ResolveFont()
    local d = CreateFrame("Frame", "WolfOfBootyBayWhenSells", UIParent)
    d:SetSize(660, WHEN_H)
    d:SetPoint("CENTER", 0, 40)
    d:SetFrameStrata("DIALOG")
    d:SetToplevel(true)
    d:EnableMouse(true)
    d:SetMovable(true)
    d:SetClampedToScreen(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)
    UI.Skin(d, "window", "bg1")
    if d.bg then d.bg:SetAlpha(0.92) end
    d.icon = UI.Icon(d, 30)
    d.icon:SetPoint("TOPLEFT", 16, -14)
    d.title = UI.Text(d, 14, "text")
    d.title:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 10, -1)
    d.title:SetPoint("RIGHT", d, "RIGHT", -110, 0)
    d.sum = UI.Text(d, 11, "muted")
    d.sum:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -4)
    d.sum:SetPoint("RIGHT", d, "RIGHT", -16, 0)
    -- when to buy and to post, from its price by the hour
    d.advice = UI.Text(d, 11, "text")
    d.advice:SetPoint("TOPLEFT", d.sum, "BOTTOMLEFT", 0, -4)
    d.advice:SetPoint("RIGHT", d, "RIGHT", -16, 0)
    d.close = UI.Button(d, L["Close"], 10, 22, "default", function() d:Hide() end)
    d.close:FitText(24)
    d.close:SetPoint("TOPRIGHT", -12, -12)
    local function Section(y, title)
        local t = UI.Text(d, 12, "text")
        t:SetPoint("TOPLEFT", 16, y)
        t:SetText(title)
        local sub = UI.Text(d, 10, "dim")
        sub:SetPoint("LEFT", t, "RIGHT", 10, 0)
        sub:SetPoint("RIGHT", d, "RIGHT", -16, 0)
        return t, sub
    end
    d.t1, d.s1 = Section(-234, L["The last 48 hours"])
    d.hours = Bars(d, 48)
    d.hours:SetPoint("TOPLEFT", 64, -254)
    d.hours:SetPoint("RIGHT", d, "RIGHT", -16, 0)
    d.hours:SetHeight(96)
    d.t2, d.s2 = Section(-368, L["By hour of the day"])
    d.tod = Bars(d, 24)
    d.tod:SetPoint("TOPLEFT", 64, -388)
    d.tod:SetPoint("RIGHT", d, "RIGHT", -16, 0)
    d.tod:SetHeight(96)
    d.t4, d.s4 = Section(-502, L["Price by hour of the day"])
    d.price = Bars(d, 24)
    d.price:SetPoint("TOPLEFT", 64, -522)
    d.price:SetPoint("RIGHT", d, "RIGHT", -16, 0)
    d.price:SetHeight(96)
    d.priceNone = UI.Text(d, 11, "dim", "CENTER")
    d.priceNone:SetPoint("TOPLEFT", 64, -548)
    d.priceNone:SetPoint("RIGHT", d, "RIGHT", -16, 0)
    if d.priceNone.SetWordWrap then d.priceNone:SetWordWrap(true) end
    d.priceNone:SetText(L["Its price by the hour comes with the next days of the price robot: it needs five looks at every hour of the day."])
    d.t3, d.s3 = Section(-636, L["By day of the week"])
    d.days = Bars(d, 7)
    d.days:SetPoint("TOPLEFT", 64, -656)
    d.days:SetPoint("RIGHT", d, "RIGHT", -280, 0)
    d.days:SetHeight(80)
    -- v0.42, at a glance: when to sell, when to buy, the busiest day; one strip of the day's hours (blue cheaper,
    -- gold pricier, now marked); the charts below only on "Show the charts"
    d.answers = {}
    for i = 1, 3 do
        local r = UI.Panel(d, "bg2", "line")
        r:SetPoint("TOPLEFT", 16, -60 - (i - 1) * 32)
        r:SetPoint("RIGHT", d, "RIGHT", -16, 0)
        r:SetHeight(28)
        r.badge = UI.Badge(r, 58, 18)
        r.badge:SetPoint("LEFT", 8, 0)
        r.text = UI.Text(r, 13, "text")
        r.text:SetPoint("LEFT", r.badge, "RIGHT", 10, 0)
        r.text:SetPoint("RIGHT", -8, 0)
        d.answers[i] = r
    end
    d.strip = CreateFrame("Frame", nil, d)
    d.strip:SetPoint("TOPLEFT", 16, -162)
    d.strip:SetPoint("RIGHT", d, "RIGHT", -16, 0)
    d.strip:SetHeight(22)
    d.cells = {}
    for h = 1, 24 do d.cells[h] = d.strip:CreateTexture(nil, "ARTWORK") end
    d.nowMark = UI.Tex(d.strip, "OVERLAY", "text", 0.9)
    d.stripLabels = {}
    for k = 1, 4 do d.stripLabels[k] = UI.Text(d, 10, "dim") end
    d.toggle = UI.Button(d, L["Show the charts"], 10, 22, "default", function()
        FT.db.ui = FT.db.ui or {}
        FT.db.ui.whenCharts = not FT.db.ui.whenCharts or nil
        if d.itemID then FT.ShowWhenSells(d.itemID) end
    end)
    d.toggle:FitText(24)
    d.toggle:SetPoint("TOPLEFT", 16, -204)
    -- the old summary lines: the three answers say it now
    d.sum:Hide()
    d.advice:Hide()
    d.empty = UI.Text(d, 12, "muted", "CENTER")
    d.empty:SetPoint("CENTER", 0, -20)
    d.empty:SetWidth(520)
    if d.empty.SetWordWrap then d.empty:SetWordWrap(true) end
    tinsert(UISpecialFrames, "WolfOfBootyBayWhenSells")
    d:Hide()
    whenWin = d
    return d
end

function FT.ShowWhenSells(itemID)
    if not itemID then return end
    local d = WhenWindow()
    d.itemID = itemID
    d.icon:SetItem(itemID)
    d.title:SetText(L["When it sells"] .. ": " .. FT.ItemText(itemID, 40))
    d:Show()
    d:Raise()
    local hr = FT.Feed and FT.Feed.Hourly and FT.Feed.Hourly(itemID)
    local any = hr ~= nil
    local charts = any and FT.db.ui and FT.db.ui.whenCharts and true or false
    for _, x in ipairs({ d.t1, d.s1, d.hours, d.t2, d.s2, d.tod, d.t3, d.s3, d.days, d.t4, d.s4 }) do x:SetShown(charts) end
    d.price:SetShown(charts and hr.todPrice ~= nil)
    d.priceNone:SetShown(charts and hr.todPrice == nil)
    for _, r in ipairs(d.answers) do r:SetShown(any) end
    d.strip:SetShown(any)
    for _, l in ipairs(d.stripLabels) do l:SetShown(any) end
    d.toggle:SetShown(any)
    d:SetHeight(charts and WHEN_H or WHEN_H_SHORT)
    if any then
        local w = FT.WhenSummary(itemID)
        local a1, a2, a3 = d.answers[1], d.answers[2], d.answers[3]
        a1.badge:Set("SELL")
        a1.text:SetText(w.sell and (FT.C("text", w.sell) .. FT.C("muted", "  ·  " .. (w.sellPct and string.format(L["priciest (%s): post just before"], FT.Pct(w.sellPct)) or L["priciest: post just before"])))
            or (w.busy and (FT.C("text", w.busy) .. FT.C("muted", "  ·  " .. L["sells most: post a little before"])) or FT.C("dim", L["its price by the hour comes in a few days"])))
        a2.badge:Set("BUY")
        a2.text:SetText(w.buy and (FT.C("text", w.buy) .. FT.C("muted", "  ·  " .. (w.buyPct and string.format(L["cheapest (%s)"], FT.Pct(w.buyPct)) or L["cheapest"])))
            or FT.C("dim", L["its price by the hour comes in a few days"]))
        a3.badge:Set("WAIT", L["DAY"])
        a3.text:SetText(w.day and (FT.C("text", w.day) .. FT.C("muted", "  ·  " .. L["busiest day of the week"])) or FT.C("dim", L["two weeks of sales first"]))
        -- the strip: its price by the hour when known (blue cheaper, gold pricier), else how much it sells
        local vals = hr.todPrice or hr.tod
        local lo, hi
        for h = 0, 23 do local x = vals[h]; if x then lo, hi = math.min(lo or x, x), math.max(hi or x, x) end end
        local sw = d.strip:GetWidth()
        if not sw or sw <= 0 then sw = 628 end
        local cw = (sw - 23 * 2) / 24
        local blue, mid, gold = { UI.RGB("blue") }, { UI.RGB("bg3") }, { UI.RGB("accent") }
        for h = 0, 23 do
            local c = d.cells[h + 1]
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", d.strip, "TOPLEFT", h * (cw + 2), 0)
            c:SetSize(cw, 22)
            local x = vals[h]
            local t = (x and hi and hi > lo) and (x - lo) / (hi - lo) or nil
            if not t then c:SetColorTexture(0.2, 0.2, 0.2, 0.6)
            elseif t < 0.45 then
                local k = t / 0.45
                c:SetColorTexture(blue[1] + (mid[1] - blue[1]) * k, blue[2] + (mid[2] - blue[2]) * k, blue[3] + (mid[3] - blue[3]) * k, 1)
            else
                local k = (t - 0.45) / 0.55
                c:SetColorTexture(mid[1] + (gold[1] - mid[1]) * k, mid[2] + (gold[2] - mid[2]) * k, mid[3] + (gold[3] - mid[3]) * k, 1)
            end
        end
        local nowH = tonumber(date("%H")) or 0
        d.nowMark:ClearAllPoints()
        d.nowMark:SetPoint("TOPLEFT", d.strip, "BOTTOMLEFT", nowH * (cw + 2), -1)
        d.nowMark:SetSize(cw, 2)
        for k, h in ipairs({ 0, 6, 12, 18 }) do
            local l = d.stripLabels[k]
            l:ClearAllPoints()
            l:SetPoint("TOPLEFT", d.strip, "BOTTOMLEFT", h * (cw + 2), -4)
            l:SetText(HourLabel(h))
        end
        d.toggle:SetLabel(charts and L["Hide the charts"] or L["Show the charts"])
        d.toggle:FitText(24)
    end
    if not hr then
        UI.FitBits(d.sum, "")
        UI.FitBits(d.advice, "")
        d.empty:SetText(L["Not enough sales seen yet for an hour-by-hour picture: the price robot needs 10 or more sold in four weeks. It looks at the whole auction house every hour."])
        d.empty:Show()
        return
    end
    d.empty:Hide()
    -- the last 48 hours, your clock under every 6th
    local vals, labels, total, watched = {}, {}, 0, 0
    for i, x in ipairs(hr.hours) do
        vals[i] = x.n
        if x.n then total, watched = total + x.n, watched + 1 end
        local hh = tonumber(date("%H", x.t))
        if hh % 6 == 0 then labels[i] = HourLabel(hh) end
    end
    d.hours:Set(vals, labels, nil)
    d.s1:SetText(string.format(L["%s sold in the %d hours watched; each bar an hour (faint: not watched)"], FT.Num(total), watched))
    -- the time of day, your clock
    local tv, tl = {}, {}
    for h = 0, 23 do
        tv[h + 1] = hr.tod[h]
        if h % 3 == 0 then tl[h + 1] = HourLabel(h) end
    end
    local bestAt, lowAt = Window(hr.tod)
    local best = {}
    if bestAt then for k = 0, 2 do best[(bestAt + k) % 24 + 1] = true end end
    local nowH = tonumber(date("%H")) + 1
    d.tod:Set(tv, tl, best, function(v) return string.format(L["%s/h"], FT.Num(math.floor(v + 0.5))) end, { now = nowH })
    d.s2:SetText(L["your clock, the last four weeks: sold an hour, on average"])
    -- its price by the hour: when it's cheapest (buy then) and priciest (post then)
    local dearAt, cheapAt, dearPct, cheapPct
    if hr.todPrice then
        local pv, lo, hi = {}, nil, nil
        for h = 0, 23 do
            local x = hr.todPrice[h]
            pv[h + 1] = x
            if x then lo, hi = math.min(lo or x, x), math.max(hi or x, x) end
        end
        dearAt, cheapAt = Window(hr.todPrice)
        local function Avg(at)
            if not at then return nil end
            local s = 0
            for k = 0, 2 do s = s + hr.todPrice[(at + k) % 24] end
            return s / 3 - 1
        end
        dearPct, cheapPct = Avg(dearAt), Avg(cheapAt)
        local dear, cheap = {}, {}
        if dearAt then for k = 0, 2 do dear[(dearAt + k) % 24 + 1] = true end end
        if cheapAt then for k = 0, 2 do cheap[(cheapAt + k) % 24 + 1] = true end end
        local span = (hi or 1) - (lo or 1)
        d.price:Set(pv, tl, dear, function(v) return FT.Pct(v - 1) end,
            { low = cheap, floor = (lo or 1) - math.max(span * 0.3, 0.005), now = nowH })
        UI.FitBits(d.s4, table.concat({ L["against its usual, your clock, two weeks"], FT.C("accent", L["gold: priciest"]),
            FT.C("blue", L["blue: cheapest"]) }, FT.C("dim", "  ·  ")))
    else
        UI.FitBits(d.s4, "")
    end
    -- the days of the week, from the two weeks of daily sales
    local days = FT.Feed.SoldDays and FT.Feed.SoldDays(itemID) or {}
    local sum, cnt = {}, {}
    for day, n in pairs(days) do
        local wd = tonumber(date("!%w", day * 86400)) -- 0 = Sunday (UTC days)
        sum[wd] = (sum[wd] or 0) + n
        cnt[wd] = (cnt[wd] or 0) + 1
    end
    local dv, dl, order = {}, {}, { 1, 2, 3, 4, 5, 6, 0 }
    local NAMES = { [0] = L["Sun"], L["Mon"], L["Tue"], L["Wed"], L["Thu"], L["Fri"], L["Sat"] }
    local bestDay, bestDayV
    for i, wd in ipairs(order) do
        dv[i] = cnt[wd] and sum[wd] / cnt[wd] or nil
        dl[i] = NAMES[wd]
        if dv[i] and (not bestDayV or dv[i] > bestDayV) then bestDay, bestDayV = i, dv[i] end
    end
    d.days:Set(dv, dl, bestDay and { [bestDay] = true } or nil)
    d.s3:SetText(L["the last two weeks, sold a day"])
    -- the summary, what to do first (a long line drops its last parts): when it sells, when to buy and to post
    local bits = {}
    local timed = cheapPct and dearPct and (dearPct - cheapPct) >= 0.02 -- a dip worth timing: 2%+ through the day
    if bestAt then
        bits[#bits + 1] = FT.C("accent", string.format(L["Sells most %s-%s"], HourLabel(bestAt), HourLabel(bestAt + 3)))
            .. FT.C("dim", " " .. L["your time"])
    end
    if bestDay then bits[#bits + 1] = string.format(L["best day: %s"], dl[bestDay]) end
    if lowAt then bits[#bits + 1] = string.format(L["quietest %s-%s"], HourLabel(lowAt), HourLabel(lowAt + 3)) end
    -- the line under it: when to buy and when to post
    local adv = {}
    if timed then
        adv[#adv + 1] = FT.C("blue", string.format(L["Cheapest %s-%s (%s): buy then"], HourLabel(cheapAt), HourLabel(cheapAt + 3), FT.Pct(cheapPct)))
        adv[#adv + 1] = FT.C("accent", string.format(L["priciest %s-%s (%s): post just before %s"], HourLabel(dearAt), HourLabel(dearAt + 3), FT.Pct(dearPct), HourLabel(dearAt)))
    elseif hr.todPrice then
        adv[#adv + 1] = L["Its price hardly moves through the day: post when it sells most"]
    else
        adv[#adv + 1] = FT.C("dim", L["Post a little before the busy hours (its price by the hour comes in a few days)"])
    end
    -- (the old summary lines stay hidden: the three answers say it)
end

---------------------------------------------------------------------------
-- A craft, laid out: every material and what it costs (bought, from a vendor, or crafted yourself), what the
-- product sells for, the profit - and against buying the product ready-made
---------------------------------------------------------------------------
local craftWin

local function CraftWindow()
    if craftWin then return craftWin end
    UI.ResolveFont()
    local d = CreateFrame("Frame", "WolfOfBootyBayCraft", UIParent)
    d:SetSize(520, 400)
    d:SetPoint("CENTER", 40, 40)
    d:SetFrameStrata("DIALOG")
    d:SetToplevel(true)
    d:EnableMouse(true)
    d:SetMovable(true)
    d:SetClampedToScreen(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)
    UI.Skin(d, "window", "bg1")
    d.icon = UI.Icon(d, 30)
    d.icon:SetPoint("TOPLEFT", 16, -14)
    d.title = UI.Text(d, 14, "text")
    d.title:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 10, -1)
    d.title:SetPoint("RIGHT", d, "RIGHT", -110, 0)
    d.sub = UI.Text(d, 11, "muted")
    d.sub:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -4)
    d.sub:SetPoint("RIGHT", d, "RIGHT", -16, 0)
    d.close = UI.Button(d, L["Close"], 10, 22, "default", function() d:Hide() end)
    d.close:FitText(24)
    d.close:SetPoint("TOPRIGHT", -14, -14)
    d.chart = UI.Button(d, L["Chart"], 10, 22, "default", function() if d.itemID then FT.OpenItem(d.itemID) end end)
    d.chart.Show = d.chart.Hide -- v0.42: no Chart button in popups
    d.chart:Hide()
    d.chart:FitText(24)
    d.chart:SetPoint("RIGHT", d.close, "LEFT", -6, 0)
    d.shop = UI.Button(d, L["Shopping list"], 10, 22, "default", function()
        local ids = {}
        for _, p in ipairs(d.parts or {}) do if p.source ~= "vendor" then ids[#ids + 1] = p.itemID end end
        FT.ToAuctionator(L["Wolf: "] .. (FT.Item(d.itemID) or "craft"), ids)
    end)
    d.shop:FitText(24)
    d.shop:SetPoint("RIGHT", d.chart, "LEFT", -6, 0)
    d.shop:SetTip(L["Shopping list"], L["The materials to buy (not the vendor ones) as an Auctionator shopping list."])
    -- v0.43: where the recipe comes from, and whether it's on the auction house (click: the recipe in Market)
    d.recipe = CreateFrame("Button", nil, d)
    d.recipe:SetPoint("TOPLEFT", 16, -56)
    d.recipe:SetPoint("RIGHT", d, "RIGHT", -16, 0)
    d.recipe:SetHeight(20)
    d.recipe.icon = UI.Icon(d.recipe, 16)
    d.recipe.icon:SetPoint("LEFT", 0, 0)
    d.recipe.text = UI.Text(d.recipe, 12, "text")
    d.recipe.text:SetPoint("LEFT", d.recipe.icon, "RIGHT", 8, 0)
    d.recipe.text:SetPoint("RIGHT", 0, 0)
    d.recipe:SetScript("OnClick", function(self)
        if self.itemID and not UI.ItemClick(self.itemID) then FT.OpenItem(self.itemID) end
    end)
    d.recipe:SetScript("OnEnter", function(self)
        local src = self.src
        if not src then return end
        if self.itemID then UI.TipItem(self, self.itemID) else GameTooltip:SetOwner(self, "ANCHOR_RIGHT") end
        GameTooltip:AddLine(" ")
        if src.trainer then
            GameTooltip:AddLine(L["No recipe item teaches it: a profession trainer does."], 0.75, 0.78, 0.82, true)
        else
            local v = src.vendor
            if v then
                GameTooltip:AddLine(string.format(L["Sold by %s in %s"], v.n or "?", v.z or "?"), 1, 0.82, 0, true)
                if v.p then GameTooltip:AddLine(string.format(L["for %s"], FT.Money(v.p, "short")) .. (v.l and ("  ·  " .. L["limited stock: it comes back over time"]) or ""), 0.75, 0.78, 0.82, true) end
                GameTooltip:AddLine(v.by and string.format(L["Seen by %s (Wolf network)"], v.by) or L["Seen by you"], 0.58, 0.55, 0.5)
            end
            if src.line then GameTooltip:AddLine(src.line, 0.75, 0.78, 0.82, true) end
            local lines = FT.Where and src.items[1] and FT.Where.Lines(src.items[1], 5) or {}
            for i = 2, #lines do GameTooltip:AddLine(lines[i], 0.75, 0.78, 0.82, true) end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Click: the recipe on the Market page."], 0.58, 0.55, 0.5)
        end
        GameTooltip:Show()
    end)
    d.recipe:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local panel = UI.Panel(d, "bg0", "line")
    d.panel = panel
    panel:SetPoint("TOPLEFT", 12, -60)
    panel:SetPoint("BOTTOMRIGHT", -12, 92)
    local cols = {
        { key = "name", title = L["Material"], width = "fill" },
        { key = "qty", title = L["Qty"], width = 40, justify = "RIGHT" },
        { key = "unit", title = L["Each"], width = 80, justify = "RIGHT" },
        { key = "total", title = L["Total"], width = 80, justify = "RIGHT" },
        { key = "from", title = L["From"], width = 70, justify = "RIGHT" },
    }
    d.header = UI.Header(panel, cols, function() end)
    d.header:SetPoint("TOPLEFT", 1, -1)
    d.header:SetPoint("TOPRIGHT", -1, -1)
    local FROM = { ah = "AH", vendor = "Vendor", craft = "Craft it" }
    d.list = UI.List(panel, {
        rowHeight = 24, cols = cols,
        update = function(row, p)
            row.cells.name:SetText(FT.ItemText(p.itemID, 30))
            row.cells.qty:SetText(FT.Num(p.qty))
            row.cells.unit:SetText(p.unit and FT.Money(math.floor(p.unit), "short") or FT.C("dim", L["no price"]))
            row.cells.total:SetText(p.total and FT.Money(math.floor(p.total), "short") or "")
            row.cells.from:SetText(FT.C("dim", FROM[p.source or ""] and L[FROM[p.source]] or ""))
        end,
        onClick = function(p) if not UI.ItemClick(p.itemID) then FT.OpenItem(p.itemID) end end,
        onEnter = function(row, p) UI.TipItem(row, p.itemID) end,
    })
    d.list:SetPoint("TOPLEFT", d.header, "BOTTOMLEFT", 0, -2)
    d.list:SetPoint("BOTTOMRIGHT", -1, 2)
    d.sum = {}
    -- (v0.51) each row one line, label and answer on its middle (money icons made the answer sit lower), clear of
    -- the window's bottom edge
    for i = 1, 4 do
        local row = CreateFrame("Frame", nil, d)
        row:SetPoint("BOTTOMLEFT", 18, 86 - i * 18)
        row:SetPoint("RIGHT", d, "RIGHT", -18, 0)
        row:SetHeight(18)
        local l = UI.Text(row, 12, "muted")
        l:SetPoint("LEFT", 0, 0)
        local r = UI.Text(row, 12, "text", "RIGHT")
        r:SetPoint("RIGHT", 0, 0)
        r:SetPoint("LEFT", l, "RIGHT", 12, 0)
        if r.SetWordWrap then r:SetWordWrap(false) end
        d.sum[i] = { l, r }
    end
    tinsert(UISpecialFrames, "WolfOfBootyBayCraft")
    d:Hide()
    craftWin = d
    return d
end

function FT.ShowCraft(r)
    if not r then return end
    local d = CraftWindow()
    local e = FT.Craft.Eval(r)
    d.itemID = r.output
    d.icon:SetItem(r.output)
    d.title:SetText(FT.ItemText(r.output, 34) .. ((r.outputQty or 1) > 1 and FT.C("dim", "  x" .. r.outputQty) or ""))
    local known = next(r.knownBy or {}) ~= nil
    local who = {}
    for name in pairs(r.knownBy or {}) do who[#who + 1] = name end
    d.sub:SetText(L[r.prof or "?"] .. (known and ("  ·  " .. FT.C("up", L["Known by"] .. " " .. table.concat(who, ", "))) or ""))
    d.parts = e.parts
    d.list:SetItems(e.parts or {})
    -- the recipe: a trainer, a merchant, a drop - and on the auction house or not
    local src = FT.Craft.RecipeSource and FT.Craft.RecipeSource(r)
    d.recipe.src = src
    d.recipe:SetShown(src ~= nil)
    d.panel:SetPoint("TOPLEFT", 12, src and -82 or -60)
    d:SetHeight(src and 422 or 400)
    if src then
        local ah = src.ah
        d.recipe.itemID = ah and ah.id or src.items[1]
        d.recipe.icon:SetShown(d.recipe.itemID ~= nil)
        if d.recipe.itemID then d.recipe.icon:SetItem(d.recipe.itemID) end
        local parts = {}
        local from
        if src.trainer then
            from = L["a trainer"]
        elseif src.line and src.how ~= "drop" and src.how ~= "world" and src.how ~= "box" then
            from = src.line -- Merchant's Favor, a vendor, a quest, Wolf's note: what the sources say
        elseif src.vendor then
            from = string.format(L["%s (vendor), %s"], src.vendor.n or "?", src.vendor.z or "?")
        elseif src.line then
            from = src.line
        else
            from = L["not in Wolf's sources yet"]
        end
        parts[1] = FT.C("accent", L["Recipe:"]) .. " " .. from
        if not src.trainer then
            if ah and ah.listed > 0 then
                parts[2] = FT.C("up", string.format(L["on the AH %s"], FT.Money(ah.price, "short"))) .. FT.C("dim", ", " .. string.format(L["%s listed"], FT.Num(ah.listed)))
            elseif ah then
                parts[2] = FT.C("dim", string.format(L["not on the AH (last %s)"], FT.Money(ah.price, "short")))
            else
                parts[2] = FT.C("dim", L["never seen on the AH"])
            end
        end
        UI.FitBits(d.recipe.text, table.concat(parts, FT.C("dim", "  ·  ")))
    end
    local qty = r.outputQty or 1
    local buyReady = FT.Price(r.output)
    local rows = {
        { L["Materials cost"], e.cost and FT.Money(math.floor(e.cost), "short") or FT.C("dim", L["no price"]) },
        { L["Sells for"] .. (e.via == "vendor" and (" (" .. L["vendor"] .. ")") or ""), e.revenue and FT.Money(math.floor(e.revenue), "short") or FT.C("dim", L["no price"]) },
        { L["Profit"], e.profit and FT.C(e.profit >= 0 and "up" or "down", FT.Money(math.floor(e.profit), "short")) or "" },
    }
    if buyReady and e.cost then
        local ready = buyReady * qty
        local diff = ready - e.cost
        rows[#rows + 1] = { L["Need it yourself?"], diff > 0
            and FT.C("up", string.format(L["craft it: saves %s"], FT.Money(math.floor(diff), "short")))
            or FT.C("accent", string.format(L["buy it: %s cheaper"], FT.Money(math.floor(-diff), "short"))) }
    end
    for i, s in ipairs(d.sum) do
        local row = rows[i]
        s[1]:SetText(row and row[1] or "")
        s[2]:SetText(row and row[2] or "")
    end
    d:Show()
    d:Raise()
end

---------------------------------------------------------------------------
-- The session panel: small, movable, on screen only while a session runs
---------------------------------------------------------------------------
local hud
-- The session panel: worth, gold an hour, what you just looted, and everything found - scroll it with the mouse
-- wheel, drag its bottom-right corner for more or fewer rows (remembered), hover a row for then and now.
local HUD_MIN, HUD_MAX, HUD_DEFAULT, ROW_H = 3, 14, 6, 16
local JUST_LOOTED = 6 -- seconds the "+3 Thorium Ore" line stays

local function HudRows()
    local n = FT.db.ui and FT.db.ui.hudRows
    return math.max(HUD_MIN, math.min(HUD_MAX, tonumber(n) or HUD_DEFAULT))
end

-- folded (v0.42): the title line and the gold with gold an hour, nothing else
local HUD_FOLDED_H = 68
local function HudFolded() return FT.db and FT.db.ui and FT.db.ui.hudFolded and true or false end
local function HudHeight(rows)
    if HudFolded() then return HUD_FOLDED_H end
    return 92 + rows * ROW_H
end

local function HudRowTip(self)
    local it = self.item
    if not it then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    if GameTooltip.SetItemByID then GameTooltip:SetItemByID(it.id) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(L["Found"], "x" .. FT.Num(it.qty), 0.8, 0.82, 0.86, 1, 1, 1)
    if it.thenUnit then
        GameTooltip:AddDoubleLine(L["Worth each when found"], FT.Money(math.floor(it.thenUnit), "short"), 0.8, 0.82, 0.86, 1, 1, 1)
    end
    if it.unit then
        local ch = it.thenUnit and it.thenUnit > 0 and (it.unit / it.thenUnit - 1) or nil
        GameTooltip:AddDoubleLine(L["Worth each now"], FT.Money(math.floor(it.unit), "short") .. (ch and ("  " .. FT.Pct(ch)) or ""), 0.8, 0.82, 0.86, 1, 1, 1)
        GameTooltip:AddDoubleLine(L["All of them"], FT.Money(math.floor(it.value), "short"), 0.8, 0.82, 0.86, 1, 1, 1)
    end
    GameTooltip:AddLine(L["Price from"] .. ": " .. FT.PriceFrom(it.id), 0.6, 0.64, 0.7, true)
    GameTooltip:Show()
end

local function BuildHUD()
    UI.ResolveFont()
    local h = CreateFrame("Frame", "WolfOfBootyBaySession", UIParent)
    h:SetSize(260, HudHeight(HudRows()))
    h:SetFrameStrata("MEDIUM")
    h:SetClampedToScreen(true)
    h:EnableMouse(true)
    h:SetMovable(true)
    h:RegisterForDrag("LeftButton")
    h:SetScript("OnDragStart", h.StartMoving)
    h:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        FT.db.ui = FT.db.ui or {}
        FT.db.ui.hud = { p, rp, x, y }
    end)
    local pos = FT.db.ui and FT.db.ui.hud
    if pos then h:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else h:SetPoint("RIGHT", UIParent, "RIGHT", -60, 80) end
    UI.Skin(h, "popup", "bg1", 0.92)
    local bar = UI.RoundTex(h, "ARTWORK", "up", 1, nil, "top", UI.RADIUS - 1)
    bar:SetHeight(2)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    h.bar = bar
    h.title = UI.Text(h, 11, "accent")
    h.title:SetPoint("TOPLEFT", 10, -8)
    -- the fold: - leaves the gold and gold an hour, + brings the items back (kept after /reload)
    -- (v0.54) the fold, pause and stop: one size, one look (the game's button in the classic look), our glyphs
    local function Square(glyph, onClick)
        local b = UI.Button(h, "", 20, 20, "default", onClick)
        b.tex = b:CreateTexture(nil, "OVERLAY")
        b.tex:SetSize(11, 11)
        b.tex:SetPoint("CENTER", 0, b.game and 1 or 0)
        b.tex:SetTexture(FT.MEDIA .. glyph)
        b.tex:SetVertexColor(UI.RGB(b.game and "accent" or "text"))
        return b
    end
    h.fold = UI.Button(h, "-", 20, 20, "default", function()
        FT.db.ui = FT.db.ui or {}
        FT.db.ui.hudFolded = not FT.db.ui.hudFolded or nil
        FT.UpdateHUD()
    end)
    h.fold:SetPoint("TOPRIGHT", -6, -4)
    -- folded: pause and stop on it
    h.miniStop = Square("stop", function() FT.Session.Stop() end)
    h.miniStop:SetTip(L["Stop the session"])
    h.miniStop:SetPoint("BOTTOMRIGHT", -6, 5)
    h.miniPause = Square("pause", function() FT.Session.Pause() end)
    h.miniPause:SetTip(L["Pause"])
    h.miniPause:SetPoint("RIGHT", h.miniStop, "LEFT", -4, 0)
    h.time = UI.Text(h, 11, "muted", "RIGHT")
    h.time:SetPoint("TOPRIGHT", -30, -8)
    h.worth = UI.Text(h, 15, "text")
    h.worth:SetPoint("TOPLEFT", 10, -24)
    h.rate = UI.Text(h, 12, "up", "RIGHT")
    h.rate:SetPoint("TOPRIGHT", -10, -27)
    -- its hover: the rate without your best find, and why it waits 10 minutes
    h.rateHit = CreateFrame("Frame", nil, h)
    h.rateHit:SetAllPoints(h.rate)
    h.rateHit:EnableMouse(true)
    h.rateHit:SetScript("OnEnter", function(self)
        local sm = h.sum
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(L["Gold an hour"], 1, 1, 1)
        if sm and sm.perHour then
            GameTooltip:AddDoubleLine(L["Everything you found"], FT.Money(math.floor(sm.perHour), "short"), 0.8, 0.82, 0.86, 1, 1, 1)
            if sm.perHourNoBest and sm.bestItem then
                GameTooltip:AddDoubleLine(string.format(L["Without your best find (%s)"], FT.ItemText(sm.bestItem.id, 20)),
                    FT.Money(math.floor(sm.perHourNoBest), "short"), 0.8, 0.82, 0.86, 1, 1, 1)
            end
        end
        GameTooltip:AddLine(L["At market prices. Shown from 10 minutes in: a lucky first minute would make it look far bigger than it is."], 0.6, 0.64, 0.7, true)
        GameTooltip:Show()
    end)
    h.rateHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- what you just looted (a few seconds), or how many have no price yet
    h.just = UI.Text(h, 11, "up")
    h.just:SetPoint("TOPLEFT", 10, -44)
    h.just:SetPoint("RIGHT", h, "RIGHT", -10, 0)
    -- the rows: a frame each, so a hover shows the item, then and now
    h.rows = {}
    for i = 1, HUD_MAX do
        local r = CreateFrame("Button", nil, h)
        r:SetHeight(ROW_H)
        r:SetPoint("TOPLEFT", 6, -60 - (i - 1) * ROW_H)
        r:SetPoint("RIGHT", h, "RIGHT", -12, 0)
        r.hl = UI.Tex(r, "BACKGROUND", "text", 0.06)
        r.hl:SetAllPoints()
        r.hl:Hide()
        r.l = UI.Text(r, 11, "muted")
        r.l:SetPoint("LEFT", 4, 0)
        r.l:SetPoint("RIGHT", r, "RIGHT", -64, 0)
        r.r = UI.Text(r, 11, "text", "RIGHT")
        r.r:SetPoint("RIGHT", -2, 0)
        r:SetScript("OnEnter", function(self) self.hl:Show(); HudRowTip(self) end)
        r:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
        r:SetScript("OnClick", function(self) if self.item and not UI.ItemClick(self.item.id) then FT.OpenItem(self.item.id) end end)
        r:SetScript("OnMouseWheel", function(_, d) h:GetScript("OnMouseWheel")(h, d) end)
        h.rows[i] = r
    end
    -- the scrollbar: a thin track and a thumb, only when there is more than fits
    h.track = UI.Tex(h, "ARTWORK", "line", 0.8)
    h.track:SetWidth(2)
    h.track:SetPoint("TOPRIGHT", -5, -60)
    h.thumb = UI.Tex(h, "OVERLAY", "muted", 0.9)
    h.thumb:SetWidth(2)
    h.offset = 0
    h:EnableMouseWheel(true)
    h:SetScript("OnMouseWheel", function(self, d)
        self.offset = math.max(0, math.min((self.total or 0) - HudRows(), self.offset - d))
        FT.UpdateHUD()
    end)
    h.pause = UI.Button(h, L["Pause"], 10, 20, "default", function() FT.Session.Pause() end)
    h.pause:FitText(16)
    h.pause:SetPoint("BOTTOMLEFT", 8, 6)
    h.stop = UI.Button(h, L["Stop"], 10, 20, "down", function() FT.Session.Stop() end)
    h.stop:FitText(16)
    h.stop:SetPoint("LEFT", h.pause, "RIGHT", 6, 0)
    h.open = UI.Button(h, L["Details"], 10, 20, "default", function() FT.Show("sessions") end)
    h.open:FitText(16)
    h.open:SetPoint("BOTTOMRIGHT", -18, 6)
    -- the corner to drag: more or fewer rows
    h.grip = CreateFrame("Button", nil, h)
    h.grip:SetSize(12, 12)
    h.grip:SetPoint("BOTTOMRIGHT", -2, 2)
    h.grip.tex = h.grip:CreateTexture(nil, "OVERLAY")
    h.grip.tex:SetAllPoints()
    h.grip.tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    h.grip:SetScript("OnEnter", function(self) UI.TipText(self, L["More rows"], L["Drag down for more rows, up for fewer."]) end)
    h.grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    h.grip:SetScript("OnMouseDown", function(self)
        local _, y = GetCursorPosition()
        self.startY, self.startRows = y / UIParent:GetEffectiveScale(), HudRows()
    end)
    h.grip:SetScript("OnMouseUp", function(self) self.startY = nil end)
    h.grip:SetScript("OnUpdate", function(self)
        if not self.startY then return end
        local _, y = GetCursorPosition()
        y = y / UIParent:GetEffectiveScale()
        local rows = math.max(HUD_MIN, math.min(HUD_MAX, self.startRows + math.floor((self.startY - y) / ROW_H + 0.5)))
        if rows ~= HudRows() then
            FT.db.ui = FT.db.ui or {}
            FT.db.ui.hudRows = rows
            h:SetHeight(HudHeight(rows))
            FT.UpdateHUD()
        end
    end)
    h.elapsed = 0
    h:SetScript("OnUpdate", function(self, e)
        self.elapsed = self.elapsed + e
        if self.elapsed >= 1 then
            self.elapsed = 0
            FT.UpdateHUD()
        end
    end)
    hud = h
    return h
end

function FT.UpdateHUD()
    local S = FT.Session
    local s = S.Current()
    -- (v0.57) a farming session (it ran by itself) shows nothing on screen
    if not s or s.auto or FT.S.sessionPanel == false then
        if hud then hud:Hide() end
        return
    end
    local h = hud or BuildHUD()
    h:Show()
    local sum = S.Summary(s)
    -- (v0.51) no "Session": the zone, or that it's paused
    h.title:SetText(s.paused and FT.C("accent", s.afk and L["paused (AFK)"] or L["paused"]) or (s.zone or ""))
    UI.SetTexColor(h.bar, s.paused and "accent" or "up", 1)
    local secs = math.floor(sum.secs)
    h.time:SetText(string.format("%d:%02d:%02d", math.floor(secs / 3600), math.floor(secs % 3600 / 60), secs % 60))
    h.worth:SetText(FT.Money(math.floor(sum.worth), "short"))
    h.rate:SetText(sum.perHour and (FT.Money(math.floor(sum.perHour), "short") .. FT.C("dim", " " .. L["/ hour"]))
        or FT.C("dim", string.format(L["/ hour in %d min"], math.ceil((sum.rateIn or 0) / 60))))
    h.sum = sum
    if s.lastT and time() - s.lastT <= JUST_LOOTED and s.lastLoot then
        h.just:SetText("+" .. FT.Num(s.lastN or 1) .. " " .. FT.ItemText(s.lastLoot, 26))
    elseif (sum.unpriced or 0) > 0 then
        h.just:SetText(FT.C("dim", string.format(sum.unpriced == 1 and L["%d item has no price yet"] or L["%d items have no price yet"], sum.unpriced)))
    else
        h.just:SetText("")
    end
    local lines = {}
    if (sum.money or 0) > 0 then lines[#lines + 1] = { text = L["Gold looted"], value = FT.Money(sum.money, "short") } end
    for _, it in ipairs(sum.items) do
        lines[#lines + 1] = { item = it, text = FT.ItemText(it.id, 22) .. FT.C("dim", " x" .. FT.Num(it.qty)),
            value = it.unit and FT.Money(math.floor(it.value), "short") or FT.C("dim", L["no price"]) }
    end
    if #lines == 0 then lines[1] = { text = FT.C("dim", L["Loot something: it shows here."]), value = "" } end
    local rows = HudRows()
    if math.floor(h:GetHeight() + 0.5) ~= HudHeight(rows) then h:SetHeight(HudHeight(rows)) end
    local folded = HudFolded()
    h.fold:SetLabel(folded and "+" or "-")
    h.fold:SetTip(folded and L["Show the items"] or L["Fold it"], folded and L["Brings back what you've found."] or L["Just the gold and gold an hour: takes less room."])
    for _, x in ipairs({ h.just, h.pause, h.stop, h.open, h.grip }) do x:SetShown(not folded) end
    h.miniPause:SetShown(folded)
    h.miniStop:SetShown(folded)
    h.time:ClearAllPoints()
    h.rate:ClearAllPoints()
    if folded then
        -- (v0.51) three short rows, narrow: the zone and the fold; the gold and the timer; gold an hour, pause, stop
        h.miniPause.tex:SetTexture(FT.MEDIA .. (s.paused and "play" or "pause"))
        h.miniPause:SetTip(s.paused and L["Resume"] or L["Pause"])
        h.time:SetPoint("TOPRIGHT", -10, -28)
        h.rate:SetPoint("BOTTOMLEFT", 10, 9)
        h.rate:SetJustifyH("LEFT")
        h.rate:SetText(sum.perHour and (FT.Money(math.floor(sum.perHour), "gold") .. FT.C("dim", " " .. L["/ hour"]))
            or FT.C("dim", string.format(L["/ hour in %dm"], math.ceil((sum.rateIn or 0) / 60))))
        for _, r in ipairs(h.rows) do r:Hide() end
        h.track:Hide()
        h.thumb:Hide()
        -- as wide as what's in it
        local row1 = (h.title:GetStringWidth() or 0) + 8 + 20
        local row2 = (h.worth:GetStringWidth() or 0) + 12 + (h.time:GetStringWidth() or 0)
        local row3 = (h.rate:GetStringWidth() or 0) + 10 + 50
        local w = math.floor(math.max(140, 16 + math.max(row1, row2, row3)) + 0.5)
        if math.abs((h:GetWidth() or 0) - w) > 1 then h:SetWidth(w) end
        return
    end
    h.time:SetPoint("TOPRIGHT", -30, -8)
    h.rate:SetPoint("TOPRIGHT", -10, -27)
    h.rate:SetJustifyH("RIGHT")
    if math.abs((h:GetWidth() or 0) - 260) > 1 then h:SetWidth(260) end
    h.total = #lines
    h.offset = math.max(0, math.min(h.offset or 0, #lines - rows))
    for i, r in ipairs(h.rows) do
        local x = i <= rows and lines[i + h.offset] or nil
        r:SetShown(i <= rows)
        r.item = x and x.item or nil
        -- the newest loot lights up for a few seconds
        local fresh = x and x.item and x.item.last and s.lastT and time() - s.lastT <= JUST_LOOTED
        r.l:SetText(x and (fresh and FT.C("up", x.text) or x.text) or "")
        r.r:SetText(x and x.value or "")
    end
    local more = #lines > rows
    h.track:SetShown(more)
    h.thumb:SetShown(more)
    if more then
        local trackH = rows * ROW_H
        h.track:SetHeight(trackH)
        local thumbH = math.max(8, trackH * rows / #lines)
        h.thumb:SetHeight(thumbH)
        h.thumb:ClearAllPoints()
        h.thumb:SetPoint("TOPRIGHT", -5, -60 - (trackH - thumbH) * (h.offset / math.max(1, #lines - rows)))
    end
    h.pause:SetLabel(s.paused and L["Resume"] or L["Pause"])
    h.pause:FitText(16)
end
FT.On("FT_SESSION_CHANGED", function() FT.UpdateHUD() end)
FT.On("FT_SESSION_LOOT", function() FT.Debounce("hud", 0.3, FT.UpdateHUD) end)
FT.On("FT_READY", function() C_Timer.After(2, FT.UpdateHUD) end)

-- /wolf credits: where the code began and where its data comes from (NOTICE and the licenses ship in its folder)
function FT.ShowSupport()
    FT.ShowLink(L["Credits"], L["Wolf is free software under the GNU GPL v3, built on ForeverTrading by thewoolfi (Apache 2.0). Where items come from: ForeverDB, with QuestieDB, VMaNGOS, cMaNGOS, AllTheThings, pfQuest and the Drop Tables contributors (CC BY-SA 4.0). All in NOTICE, in Wolf's folder. The original addon:"],
        FT.URL_SUPPORT)
end

function FT.ShowCurseForge()
    FT.ShowLink(L["Wolf on CurseForge"], L["The newest version, for the CurseForge app. Copy the link and open it in your browser:"],
        FT.URL_CURSEFORGE)
end

function FT.ShowGitHub()
    FT.ShowLink(L["Wolf on GitHub"], L["Source code, releases and bug reports. Copy the link and open it in your browser:"],
        FT.URL_GITHUB)
end

-- A tip for guild chat, in the chat box for you to send: "[Thorium Bar] is cheap today: 2.1g (usually 2.6g)"
function FT.ShareTip(itemID)
    local s = FT.An.Stats(itemID)
    if not s.price then return end
    local _, _, _, _, link = FT.Item(itemID)
    local name = link or FT.ItemText(itemID)
    local function G(c) return FT.MoneyPlain(math.floor(c)) end
    local text
    if s.avg and s.dev and s.dev <= -0.1 then
        text = string.format(L["%s is cheap today: %s (usually %s)"], name, G(s.price), G(s.avg))
    elseif s.avg and s.dev and s.dev >= 0.1 then
        text = string.format(L["%s is high today: %s (usually %s), good time to sell"], name, G(s.price), G(s.avg))
    else
        text = string.format(L["%s is at its usual price: %s"], name, G(s.price))
    end
    text = text .. " - Wolf"
    local prefix = (IsInGuild and IsInGuild()) and "/g " or ""
    if ChatFrame_OpenChat then ChatFrame_OpenChat(prefix .. text) else FT.Print(text) end
end
