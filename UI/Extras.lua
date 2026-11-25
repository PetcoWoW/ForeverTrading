-- Wolf of Booty Bay: minimap button, the button on the auction house, item tooltip lines, alert toasts.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local ICON = "Interface\\Icons\\Ability_Hunter_Pet_Wolf"

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
    GameTooltip:AddLine("|cfff0b90bWolf of Booty Bay|r")
    local last = FT.Hist.LastScan()
    GameTooltip:AddLine(L["Scan"] .. ": " .. (last and FT.Ago(last) or L["never"]), 0.6, 0.64, 0.7)
    GameTooltip:AddLine(" ")
    local s = FT.Session.Current()
    if s then
        local sum = FT.Session.Summary(s)
        GameTooltip:AddLine(string.format(L["Session: %s, %s an hour"], FT.Money(math.floor(sum.worth), "short"),
            sum.perHour and FT.Money(math.floor(sum.perHour), "short") or "..."), 0.05, 0.8, 0.5)
    end
    GameTooltip:AddLine(L["Click: open / close the window"], 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L["Right-click: session tracker (start, pause, stop)"], 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L["Drag: move"], 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

-- the right-click menu: the session, the pages
local menu, menuBlock
local function MenuItems()
    local S = FT.Session
    local s = S.Current()
    local items = {}
    if not s then
        items[#items + 1] = { L["Start a session"], function() S.Start() end, "up" }
    else
        local sum = S.Summary(s)
        items[#items + 1] = { FT.C("dim", string.format(L["Running: %s, %s an hour"], FT.Money(math.floor(sum.worth), "short"),
            sum.perHour and FT.Money(math.floor(sum.perHour), "short") or "...")), nil }
        items[#items + 1] = { s.paused and L["Resume the session"] or L["Pause the session"], function() S.Pause() end }
        items[#items + 1] = { L["Stop the session"], function() S.Stop() end, "down" }
    end
    items[#items + 1] = { "-" }
    items[#items + 1] = { (FT.IsShown() and L["Close Wolf of Booty Bay"]) or L["Open Wolf of Booty Bay"], function() FT.Toggle() end }
    items[#items + 1] = { L["Sessions"], function() FT.Show("sessions") end }
    items[#items + 1] = { L["Money"], function() FT.Show("signals") end }
    items[#items + 1] = { L["Portfolio"], function() FT.Show("portfolio") end }
    items[#items + 1] = { L["Settings"], function() FT.Show("settings") end }
    return items
end

function FT.ShowMenu(anchor)
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
        UI.Fill(menu, "bg2")
        UI.Border(menu, "line")
        menu.rows = {}
        tinsert(UISpecialFrames, "WolfOfBootyBayMenu")
    end
    local items = MenuItems()
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
    icon:SetSize(18, 18)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetPoint("CENTER")
    local border = mb:CreateTexture(nil, "OVERLAY")
    border:SetSize(52, 52)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")
    -- a click: the window; right-click: the session menu (start, pause, stop, its worth so far)
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
    ldb:NewDataObject("Wolf of Booty Bay", {
        type = "launcher", label = "Wolf of Booty Bay", text = "Wolf of Booty Bay", icon = ICON,
        OnClick = function(self, button)
            if button == "RightButton" then FT.ShowMenu(self) else FT.Toggle() end
        end,
        OnTooltipShow = function(tt)
            if not (tt and tt.AddLine) then return end
            tt:AddLine("Wolf of Booty Bay")
            local last = FT.Hist.LastScan()
            tt:AddLine(L["Scan"] .. ": " .. (last and FT.Ago(last) or L["never"]), 0.6, 0.64, 0.7)
        end,
    })
end

---------------------------------------------------------------------------
-- Auction house: a button that opens Wolf of Booty Bay right next to it
---------------------------------------------------------------------------
local ahButton
local docked = false

local function AHFrame()
    return AuctionFrame or AuctionHouseFrame
end

local function Dock()
    if FT.WindowMaximized() then return end
    local win = FT.Window()
    local ah = AHFrame()
    if not (win and ah and ah:IsShown()) then return end
    local scale = win:GetEffectiveScale()
    local right = (ah:GetRight() or 0) * ah:GetEffectiveScale()
    local room = GetScreenWidth() * UIParent:GetEffectiveScale() - right
    if room >= win:GetWidth() * scale then
        win:ClearAllPoints()
        win:SetPoint("TOPLEFT", ah, "TOPRIGHT", 6, -2)
        docked = true
    end
end

local function ToggleFromAH()
    if FT.IsShown() then
        FT.Window():Hide()
    else
        FT.Show("market")
        if FT.S.dockAH then Dock() end
    end
end

local function TipAH(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("|cfff0b90bWolf of Booty Bay|r")
    GameTooltip:AddLine(L["Charts, order books, craft profit and signals"], 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end

-- the text of the button (with how far a scan got)
local function AHLabel()
    local frac = FT.Scanner.Running() and FT.Scanner.Progress()
    return frac and string.format("Wolf of Booty Bay  %d%%", math.floor(frac * 100)) or "Wolf of Booty Bay"
end

-- The modern auction house: a tab in the row of its tabs, the game's own look. With Auctionator its tab
-- library places it after Auctionator's tabs; without it we put it after the game's last tab.
local function BuildAHTab(ah)
    local tab
    local lib = LibStub and LibStub("LibAHTab-1-0", true)
    if lib and lib.CreateTab then
        local ok = pcall(function()
            if not lib:DoesIDExist("Wolf of Booty Bay") then
                local holder = CreateFrame("Frame", nil, ah)
                lib:CreateTab("Wolf of Booty Bay", holder, "Wolf of Booty Bay")
            end
            tab = lib:GetButton("Wolf of Booty Bay")
        end)
        if not ok then tab = nil end
    end
    if not tab then
        local ok, made = pcall(CreateFrame, "Button", "WolfOfBootyBayAHTab", ah, "AuctionHouseFrameDisplayModeTabTemplate")
        if not ok or not made then return nil end
        tab = made
        tab:SetText("Wolf of Booty Bay")
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
    -- it opens our window; it never becomes the auction house's chosen tab
    tab:SetScript("OnClick", function(self)
        ToggleFromAH()
        if PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(self) end
    end)
    tab:HookScript("OnEnter", TipAH)
    tab:HookScript("OnLeave", function() GameTooltip:Hide() end)
    if PanelTemplates_TabResize then PanelTemplates_TabResize(tab, 20, nil, 70) end
    if PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(tab) end
    tab.SetLabel = function(self, text)
        self:SetText(text)
        if PanelTemplates_TabResize then PanelTemplates_TabResize(self, 20, nil, 70) end
    end
    tab.GetLabel = function(self) return self:GetText() end
    return tab
end

-- The classic auction house (or no tab template): our own button
local function BuildAHPlainButton(ah)
    local b = UI.Button(ah, "Wolf of Booty Bay", 10, 22, "default", ToggleFromAH)
    b.style = { bg = "bg0", bgA = 0.92, hover = "bg2", hoverA = 1, text = "accent", border = "line" }
    b:SetActive(false)
    b:FitText(24)
    b:SetFrameStrata("HIGH")
    if ah == AuctionFrame then
        b:SetPoint("TOPRIGHT", ah, "TOPRIGHT", -40, -13)
    else
        b:SetPoint("TOPRIGHT", ah, "BOTTOMRIGHT", -4, -2)
    end
    b:SetTip("Wolf of Booty Bay", L["Charts, order books, craft profit and signals"])
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
    -- while Wolf of Booty Bay scans, the button shows how far it got
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

FT.On("AUCTION_HOUSE_CLOSED", function()
    if docked then
        docked = false
        local win = FT.Window()
        if win and win:IsShown() then
            win:Hide()
            FT.ResetWindow()
        end
    end
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

-- "Best use: Thorium Bar, 2.6g each (+24%)" for a material, or nil - kept 2 minutes (a material in 100+
-- recipes takes a moment to price)
local bestCache = {}
FT.On("FT_SCAN_DONE", function() wipe(bestCache) end)
local function BestUseLine(itemID)
    local c = bestCache[itemID]
    if c and GetTime() - c.t < 120 then return c.text end
    local text = nil
    local list, raw = FT.Craft.BestUse(itemID)
    local x = list[1]
    if x and x.each and x.each > 0 and x.sells then
        text = string.format(L["Best use: %s, %s each"], FT.ItemText(x.recipe.output, 26), FT.Money(math.floor(x.each), "short"))
        if raw and raw > 0 then text = text .. " " .. FT.Pct(x.each / raw - 1) end
    end
    bestCache[itemID] = { t = GetTime(), text = text }
    return text
end

local function TipLines(itemID, detail)
    local s = FT.An.Stats(itemID)
    local rs = FT.Craft.ByOutput(itemID)
    local uses = FT.S.tooltipBestUse ~= false and FT.Craft.UsedIn(itemID)
    local de = FT.Enchant and FT.Enchant.Value and FT.Enchant.Value(itemID)
    if not s.price and not rs and not uses and not de then return false end
    local out = {}
    -- 1: what to do with it, and its price
    local sig, _, reason = FT.An.SellSignal(s)
    local sym = FT.Symbol(itemID)
    local left = "|cfff0b90bWolf|r" .. (sym ~= "" and ("  |cfff0b90b$" .. sym .. "|r") or "")
    if sig ~= "NODATA" and sig ~= "FAIR" then
        left = left .. "  " .. FT.C(FT.SIGNAL_COLORS[sig] or "muted", FT.SignalText(sig))
    end
    local right = s.price and (FT.Money(s.price, "short") .. (s.ch1 and ("  " .. FT.Pct(s.ch1) .. FT.C("dim", " " .. L["today"])) or "")) or ""
    out[#out + 1] = { left, right }
    -- 2: the one fact worth most: a craft's profit, a material's best use, what it disenchants for
    local second
    if rs and rs[1] then
        local e = FT.Craft.Eval(rs[1])
        if e.profit then
            second = string.format(L["Craft it: profit %s"], FT.C(e.profit >= 0 and "up" or "down", FT.Money(e.profit, "short")))
        end
    end
    if not second and uses then second = BestUseLine(itemID) end
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
    elseif FT.S.tooltipHint ~= false then
        -- (the hint fits on line 2 when there's room)
    end
    return out
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
    for _, l in ipairs(c.lines) do
        if l[2] then tt:AddDoubleLine(l[1], l[2], 0.8, 0.82, 0.86, 1, 1, 1)
        else tt:AddLine(l[1], 0.8, 0.82, 0.86) end
    end
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
    UI.Fill(t, "bg1")
    UI.Border(t, "line")
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
    -- recipes by profession: how many the Craft page has, how many Wolf of Booty Bay read itself (Mastercraft: the rest)
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
    UI.Fill(d, "bg1")
    UI.Border(d, "line")
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
-- Best use: every recipe a material goes into, ranked by what one of it brings (FT.Craft.BestUse)
---------------------------------------------------------------------------
local bestUse

local function BestUseWindow()
    if bestUse then return bestUse end
    UI.ResolveFont()
    local d = CreateFrame("Frame", "WolfOfBootyBayBestUse", UIParent)
    d:SetSize(640, 440)
    d:SetPoint("CENTER", 0, 60)
    d:SetFrameStrata("DIALOG")
    d:SetToplevel(true)
    d:EnableMouse(true)
    d:SetMovable(true)
    d:SetClampedToScreen(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)
    UI.Fill(d, "bg1")
    UI.Border(d, "line")
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
    local panel = UI.Panel(d, "bg0", "line")
    panel:SetPoint("TOPLEFT", 12, -60)
    panel:SetPoint("BOTTOMRIGHT", -12, 30)
    local cols = {
        { key = "name", title = L["Makes"], width = "fill" },
        { key = "prof", title = L["Profession"], width = 110 },
        { key = "need", title = L["Uses"], width = 44, justify = "RIGHT" },
        { key = "each", title = L["Worth each"], width = 96, justify = "RIGHT" },
        { key = "vs", title = L["vs selling it"], width = 90, justify = "RIGHT" },
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
    d.foot:SetText(L["Worth each: what the product sells for, minus the other materials, per one of this. Before your time and the recipe."])
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
    d.title:SetText(L["Best use of"] .. " " .. FT.ItemText(itemID, 40))
    local list, raw, via = FT.Craft.BestUse(itemID)
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
    UI.Fill(d, "bg1")
    UI.Border(d, "line")
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
    local panel = UI.Panel(d, "bg0", "line")
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
    for i = 1, 4 do
        local l = UI.Text(d, 12, "muted")
        l:SetPoint("BOTTOMLEFT", 18, 76 - i * 18)
        local r = UI.Text(d, 12, "text", "RIGHT")
        r:SetPoint("BOTTOMRIGHT", -18, 76 - i * 18)
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
    local sym = FT.SymbolText(r.output)
    d.title:SetText((sym ~= "" and (sym .. "  ") or "") .. FT.ItemText(r.output, 34) .. ((r.outputQty or 1) > 1 and FT.C("dim", "  x" .. r.outputQty) or ""))
    local known = next(r.knownBy or {}) ~= nil
    local who = {}
    for name in pairs(r.knownBy or {}) do who[#who + 1] = name end
    d.sub:SetText(L[r.prof or "?"] .. "  ·  " .. (known and FT.C("up", L["Known by"] .. " " .. table.concat(who, ", "))
        or FT.C("accent", L["Recipe needed"])))
    d.parts = e.parts
    d.list:SetItems(e.parts or {})
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
            and FT.C("up", string.format(L["crafting saves %s vs buying it"], FT.Money(math.floor(diff), "short")))
            or FT.C("accent", string.format(L["buying it ready is %s cheaper"], FT.Money(math.floor(-diff), "short"))) }
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
local HUD_ROWS = 4

local function BuildHUD()
    UI.ResolveFont()
    local h = CreateFrame("Frame", "WolfOfBootyBaySession", UIParent)
    h:SetSize(250, 74 + HUD_ROWS * 16)
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
    UI.Fill(h, "bg1", 0.92)
    UI.Border(h, "line")
    local bar = UI.RoundTex(h, "ARTWORK", "up", 1, nil, "top", UI.RADIUS - 1)
    bar:SetHeight(2)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    h.bar = bar
    h.title = UI.Text(h, 11, "accent")
    h.title:SetPoint("TOPLEFT", 10, -8)
    h.time = UI.Text(h, 11, "muted", "RIGHT")
    h.time:SetPoint("TOPRIGHT", -10, -8)
    h.worth = UI.Text(h, 15, "text")
    h.worth:SetPoint("TOPLEFT", 10, -24)
    h.rate = UI.Text(h, 12, "up", "RIGHT")
    h.rate:SetPoint("TOPRIGHT", -10, -27)
    h.rows = {}
    for i = 1, HUD_ROWS do
        local l = UI.Text(h, 11, "muted")
        l:SetPoint("TOPLEFT", 10, -46 - (i - 1) * 16)
        l:SetPoint("RIGHT", h, "RIGHT", -70, 0)
        if l.SetWordWrap then l:SetWordWrap(false) end
        local r = UI.Text(h, 11, "text", "RIGHT")
        r:SetPoint("TOPRIGHT", -10, -46 - (i - 1) * 16)
        h.rows[i] = { l, r }
    end
    h.pause = UI.Button(h, L["Pause"], 10, 20, "default", function() FT.Session.Pause() end)
    h.pause:FitText(16)
    h.pause:SetPoint("BOTTOMLEFT", 8, 6)
    h.stop = UI.Button(h, L["Stop"], 10, 20, "down", function() FT.Session.Stop() end)
    h.stop:FitText(16)
    h.stop:SetPoint("LEFT", h.pause, "RIGHT", 6, 0)
    h.open = UI.Button(h, L["Details"], 10, 20, "default", function() FT.Show("sessions") end)
    h.open:FitText(16)
    h.open:SetPoint("BOTTOMRIGHT", -8, 6)
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
    if not s or FT.S.sessionPanel == false then
        if hud then hud:Hide() end
        return
    end
    local h = hud or BuildHUD()
    h:Show()
    local sum = S.Summary(s)
    h.title:SetText(s.paused and (L["Session"] .. "  " .. FT.C("accent", s.afk and L["paused (AFK)"] or L["paused"])) or (L["Session"] .. "  ·  " .. (s.zone or "")))
    UI.SetTexColor(h.bar, s.paused and "accent" or "up", 1)
    local secs = math.floor(sum.secs)
    h.time:SetText(string.format("%d:%02d:%02d", math.floor(secs / 3600), math.floor(secs % 3600 / 60), secs % 60))
    h.worth:SetText(FT.Money(math.floor(sum.worth), "short"))
    h.rate:SetText(sum.perHour and (FT.Money(math.floor(sum.perHour), "short") .. FT.C("dim", " " .. L["/ hour"])) or FT.C("dim", L["counting..."]))
    local lines = {}
    if (sum.money or 0) > 0 then lines[#lines + 1] = { L["Gold looted"], FT.Money(sum.money, "short") } end
    for _, it in ipairs(sum.items) do
        if #lines >= HUD_ROWS then break end
        lines[#lines + 1] = { FT.ItemText(it.id, 22) .. FT.C("dim", " x" .. FT.Num(it.qty)), FT.Money(math.floor(it.value), "short") }
    end
    if #lines == 0 then lines[1] = { FT.C("dim", L["Loot something: it shows here."]), "" } end
    for i, r in ipairs(h.rows) do
        r[1]:SetText(lines[i] and lines[i][1] or "")
        r[2]:SetText(lines[i] and lines[i][2] or "")
    end
    h.pause:SetLabel(s.paused and L["Resume"] or L["Pause"])
    h.pause:FitText(16)
end
FT.On("FT_SESSION_CHANGED", function() FT.UpdateHUD() end)
FT.On("FT_SESSION_LOOT", function() FT.Debounce("hud", 0.3, FT.UpdateHUD) end)
FT.On("FT_READY", function() C_Timer.After(2, FT.UpdateHUD) end)

-- /wolf credits: where the code began (the license's notice; NOTICE and LICENSE ship in the addon's folder)
function FT.ShowSupport()
    FT.ShowLink(L["Credits"], L["The Wolf of Booty Bay is a modified version of an addon by thewoolfi, under the Apache License 2.0 (see NOTICE in the addon's folder). The original:"],
        FT.URL_SUPPORT)
end

function FT.ShowGitHub()
    FT.ShowLink(L["Wolf of Booty Bay on GitHub"], L["Source code, releases and bug reports. Copy the link and open it in your browser:"],
        FT.URL_GITHUB)
end

-- A tip for guild chat, in the chat box for you to send: "[Thorium Bar] $THOR is cheap today: 2.1g (usually 2.6g)"
function FT.ShareTip(itemID)
    local s = FT.An.Stats(itemID)
    if not s.price then return end
    local _, _, _, _, link = FT.Item(itemID)
    local sym = FT.Symbol(itemID)
    local name = (link or FT.ItemText(itemID)) .. (sym ~= "" and (" $" .. sym) or "")
    local function G(c) return FT.MoneyPlain(math.floor(c)) end
    local text
    if s.avg and s.dev and s.dev <= -0.1 then
        text = string.format(L["%s is cheap today: %s (usually %s)"], name, G(s.price), G(s.avg))
    elseif s.avg and s.dev and s.dev >= 0.1 then
        text = string.format(L["%s is high today: %s (usually %s), good time to sell"], name, G(s.price), G(s.avg))
    else
        text = string.format(L["%s is at its usual price: %s"], name, G(s.price))
    end
    text = text .. " - Wolf of Booty Bay"
    local prefix = (IsInGuild and IsInGuild()) and "/g " or ""
    if ChatFrame_OpenChat then ChatFrame_OpenChat(prefix .. text) else FT.Print(text) end
end
