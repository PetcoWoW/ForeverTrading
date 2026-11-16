-- ForeverTrading: the main window - header with navigation, the ticker tape, pages, status bar.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

FT.Tabs = {}

local TAB_ORDER = { "market", "craft", "signals", "portfolio", "settings" }
local TAB_LABELS = { market = "Market", craft = "Craft", signals = "Signals", portfolio = "Portfolio", settings = "Settings" }

local win, nav, content, ticker, statusLeft, statusRight, scanDot, scanText, sizeBox
local pages = {}

-- three sizes instead of dragging a corner: compact, standard, the whole screen
local SIZES = { min = { 1100, 640 }, std = { 1240, 740 } }
local SIZE_ORDER = { "min", "std", "max" }

local function SizeMode()
    local m = FT.db.frame.size
    return (m == "min" or m == "max") and m or "std"
end

---------------------------------------------------------------------------
-- Position
---------------------------------------------------------------------------
local function SavePos()
    if not win or SizeMode() == "max" then return end
    local p = FT.db.frame
    local point, _, relPoint, x, y = win:GetPoint(1)
    p.point, p.relPoint, p.x, p.y = point, relPoint, x, y
end

local function UpdateSizeButtons()
    if not sizeBox then return end
    local mode = SizeMode()
    for _, b in ipairs(sizeBox.buttons) do
        local on = b.mode == mode
        b.box:SetBorderColor(on and "accent" or "muted", on and 1 or 0.9)
        b.fill:SetShown(on)
    end
end

local function PlaceWindow()
    local p = FT.db.frame
    local mode = SizeMode()
    win:ClearAllPoints()
    if mode == "max" then
        -- the whole screen, whatever the window's scale (Settings)
        local scale = win:GetScale()
        win:SetSize(UIParent:GetWidth() / scale, UIParent:GetHeight() / scale)
        win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    else
        local size = SIZES[mode]
        win:SetSize(size[1], size[2])
        if p.point then
            win:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
        else
            win:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
        end
    end
    UpdateSizeButtons()
end

function FT.ResetWindow()
    if win then PlaceWindow() end
end

function FT.SetWindowSize(mode)
    FT.db.frame.size = mode
    if win then PlaceWindow() end
end

function FT.WindowMaximized()
    return SizeMode() == "max"
end

-- three small buttons, each a frame of its size
local function BuildSizeButtons(header, anchor)
    local f = CreateFrame("Frame", nil, header)
    f:SetSize(3 * 24 + 4, 24)
    f:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
    f.buttons = {}
    local frames = { min = { 9, 7 }, std = { 12, 9 }, max = { 16, 12 } }
    local tips = { min = L["Compact"], std = L["Standard"], max = L["Full screen"] }
    for i, mode in ipairs(SIZE_ORDER) do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(24, 24)
        b:SetPoint("LEFT", (i - 1) * 26, 0)
        b.mode = mode
        b.hover = UI.Tex(b, "BACKGROUND", "bg2", 1)
        b.hover:SetAllPoints()
        b.hover:Hide()
        b.box = CreateFrame("Frame", nil, b)
        b.box:SetSize(frames[mode][1], frames[mode][2])
        b.box:SetPoint("CENTER")
        UI.Border(b.box, "muted")
        b.fill = UI.Tex(b.box, "ARTWORK", "accent", 0.25)
        b.fill:SetAllPoints()
        b:SetScript("OnEnter", function(self)
            self.hover:Show()
            UI.TipText(self, tips[mode])
        end)
        b:SetScript("OnLeave", function(self)
            self.hover:Hide()
            GameTooltip:Hide()
        end)
        b:SetScript("OnClick", function() FT.SetWindowSize(mode) end)
        f.buttons[i] = b
    end
    sizeBox = f
    UpdateSizeButtons()
    return f
end

---------------------------------------------------------------------------
-- Ticker tape: watchlist first, then the day's biggest movers
---------------------------------------------------------------------------
local function BuildTicker(parent)
    local t = CreateFrame("Frame", nil, parent)
    t:SetHeight(26)
    UI.Fill(t, "bg1")
    if t.SetClipsChildren then pcall(t.SetClipsChildren, t, true) end
    t.entries = {}
    t.speed = 28
    local fadeL = UI.Tex(t, "OVERLAY", "bg1", 1, 7)
    fadeL:SetPoint("TOPLEFT")
    fadeL:SetPoint("BOTTOMLEFT")
    fadeL:SetWidth(30)
    UI.Gradient(fadeL, "HORIZONTAL", "bg1", 1, 0)
    local fadeR = UI.Tex(t, "OVERLAY", "bg1", 1, 7)
    fadeR:SetPoint("TOPRIGHT")
    fadeR:SetPoint("BOTTOMRIGHT")
    fadeR:SetWidth(30)
    UI.Gradient(fadeR, "HORIZONTAL", "bg1", 0, 1)

    local function Entry(i)
        local e = t.entries[i]
        if e then return e end
        e = CreateFrame("Button", nil, t)
        e:SetHeight(26)
        e.text = UI.Text(e, 11, "text")
        e.text:SetPoint("LEFT", 0, 0)
        e:SetScript("OnClick", function(self)
            if self.itemID then FT.OpenItem(self.itemID) end
        end)
        e:SetScript("OnEnter", function(self)
            t.paused = true
            if self.itemID then UI.TipItem(self, self.itemID, "ANCHOR_BOTTOM") end
        end)
        e:SetScript("OnLeave", function()
            t.paused = false
            GameTooltip:Hide()
        end)
        t.entries[i] = e
        return e
    end

    function t:SetEntries(list)
        self.list = list
        local x = 12
        for i, item in ipairs(list) do
            local e = Entry(i)
            e.itemID = item.id
            e.text:SetText(item.text)
            e:SetWidth(math.ceil(e.text:GetStringWidth()) + 4)
            e.x = x
            x = x + e:GetWidth() + 34
            e:ClearAllPoints()
            e:SetPoint("LEFT", self, "LEFT", e.x, 0)
            e:Show()
        end
        for i = #list + 1, #self.entries do self.entries[i]:Hide() end
        self.total = x
    end

    t:SetScript("OnUpdate", function(self, elapsed)
        if self.paused or not self.list or #self.list == 0 then return end
        local W = self:GetWidth()
        if (self.total or 0) <= W then
            -- everything fits: no need to move
            return
        end
        local dx = self.speed * math.min(elapsed, 0.1)
        local maxRight = 0
        for i = 1, #self.list do
            local e = self.entries[i]
            local right = e.x + e:GetWidth()
            if right > maxRight then maxRight = right end
        end
        for i = 1, #self.list do
            local e = self.entries[i]
            e.x = e.x - dx
            if e.x + e:GetWidth() < 0 then
                e.x = math.max(maxRight + 34, W)
                maxRight = e.x + e:GetWidth()
            end
            e:ClearAllPoints()
            e:SetPoint("LEFT", self, "LEFT", e.x, 0)
            if not self.clips then e:SetShown(e.x >= 0 and e.x + e:GetWidth() <= W) end
        end
    end)
    t.clips = t.SetClipsChildren ~= nil
    t:SetScript("OnEnter", function(self) self.paused = true end)
    t:SetScript("OnLeave", function(self) self.paused = false end)
    return t
end

local function TickerText(id, price, ch)
    local name = FT.Trunc(FT.Item(id) or ("#" .. id), 26)
    return FT.C("muted", name) .. "  " .. FT.Money(price, "short") .. "  " .. FT.Pct(ch)
end

function FT.UpdateTicker()
    if not ticker or not FT.S.ticker then return end
    local list, seen = {}, {}
    for id in pairs(FT.db.watch) do
        local r = FT.Market.Row(id)
        local price = r and r.price or FT.Price(id)
        if price then
            list[#list + 1] = { id = id, text = "|cfff0b90b*|r " .. TickerText(id, price, r and r.ch1) }
            seen[id] = true
        end
    end
    for _, r in ipairs(FT.Market.Movers(8, "ch1", true)) do
        if not seen[r.id] and r.ch1 > 0 then
            list[#list + 1] = { id = r.id, text = TickerText(r.id, r.price, r.ch1) }
            seen[r.id] = true
        end
    end
    for _, r in ipairs(FT.Market.Movers(8, "ch1", false)) do
        if not seen[r.id] and r.ch1 < 0 then
            list[#list + 1] = { id = r.id, text = TickerText(r.id, r.price, r.ch1) }
            seen[r.id] = true
        end
    end
    if #list == 0 then
        -- no moves known yet (the first days): the most valuable listings
        for _, r in ipairs(FT.Market.TopByValue(14)) do
            list[#list + 1] = { id = r.id, text = TickerText(r.id, r.price, r.ch1) }
        end
    end
    if #list == 0 then
        list[1] = { text = FT.C("dim", L["No market data yet: open the auction house and press Full scan."]) }
    end
    ticker:SetEntries(list)
end

---------------------------------------------------------------------------
-- Status (header dot + bottom bar)
---------------------------------------------------------------------------
function FT.UpdateStatus()
    if not win then return end
    local last = FT.Hist.LastScan()
    local color, text
    if FT.scanning or FT.atrScanning then
        color, text = "accent", L["Scanning..."]
    elseif not last then
        color, text = "dim", L["No scan yet"]
    else
        local age = time() - last
        color = (age < 3600 and "up") or (age < 12 * 3600 and "accent") or "down"
        text = L["Scan"] .. ": " .. FT.Ago(last)
    end
    UI.SetTexColor(scanDot, color, 1)
    scanText:SetText(text)

    local parts = {}
    local full = FT.Hist.LastScan("full")
    parts[#parts + 1] = L["Full scan"] .. ": " .. (full and FT.Ago(full) or L["never"])
    local function Source(name, on)
        return on and (FT.C("up", name) .. " " .. FT.C("up", L["on"])) or FT.C("dim", name .. " " .. L["off"])
    end
    parts[#parts + 1] = Source("Auctionator", FT.Atr.On())
    parts[#parts + 1] = Source("Mastercraft", FT.MC.Loaded())
    parts[#parts + 1] = string.format(L["Recipes: %d"], #FT.Craft.List())
    parts[#parts + 1] = string.format(L["Tracked: %d"], FT.S.trackAll and #(FT.Market.Rows() or {}) or FT.Hist.UniverseSize())
    local rows = FT.Market.Rows()
    if rows then parts[#parts + 1] = string.format(L["Market: %s items"], FT.Num(#rows)) end
    statusLeft:SetText(table.concat(parts, FT.C("dim", "   ·   ")))
end

---------------------------------------------------------------------------
-- Scan buttons and progress (header)
---------------------------------------------------------------------------
local scanBox

local function BuildScanBox(header, anchor, closeButton)
    local f = CreateFrame("Frame", nil, header)
    f:SetSize(280, 40)
    f.anchor, f.closeButton = anchor, closeButton
    f:SetPoint("RIGHT", anchor, "LEFT", -18, 0)
    f.mine = UI.Button(f, L["My items"], 10, 24, "default", function() FT.Scanner.StartMine() end)
    f.mine:FitText(24)
    f.mine:SetPoint("RIGHT", 0, 0)
    f.full = UI.Button(f, L["Full scan"], 10, 24, "primary", function() FT.Scanner.StartFull() end)
    f.full:FitText(24)
    f.full:SetPoint("RIGHT", f.mine, "LEFT", -6, 0)
    f.stop = UI.Button(f, L["Stop"], 10, 22, "down", function() FT.Scanner.Stop("user") end)
    f.stop:FitText(20)
    f.stop:SetPoint("RIGHT", 0, 0)
    f.bar = CreateFrame("Frame", nil, f)
    f.bar:SetSize(160, 4)
    f.bar:SetPoint("BOTTOMRIGHT", f.stop, "BOTTOMLEFT", -10, 3)
    UI.Fill(f.bar, "bg3")
    f.fill = UI.Tex(f.bar, "ARTWORK", "accent", 1)
    f.fill:SetPoint("TOPLEFT")
    f.fill:SetPoint("BOTTOMLEFT")
    f.text = UI.Text(f, 10, "muted", "RIGHT")
    f.text:SetPoint("BOTTOMRIGHT", f.bar, "TOPRIGHT", 0, 4)
    f.text:SetWidth(160)
    f.elapsed = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed >= 0.2 then
            self.elapsed = 0
            FT.UpdateScanBox()
        end
    end)
    scanBox = f
    return f
end

function FT.UpdateScanBox()
    local f = scanBox
    if not f then return end
    local S = FT.Scanner
    local mode = S.mode
    local running = mode ~= nil
    -- Full scan is always there (during My items it takes over); My items while nothing runs
    f.full:SetShown(mode ~= "full")
    f.mine:SetShown(not running)
    f.stop:SetShown(running)
    f.bar:SetShown(running)
    f.text:SetShown(running)
    -- the scan status next to it makes room for the progress
    scanText:SetShown(not running)
    scanDot:SetShown(not running)
    f:ClearAllPoints()
    if running then
        f:SetPoint("RIGHT", f.closeButton, "LEFT", -12, 0)
    else
        f:SetPoint("RIGHT", f.anchor, "LEFT", -18, 0)
    end
    f.full:ClearAllPoints()
    if running then
        local frac, text = S.Progress()
        f.fill:SetWidth(math.max(1, f.bar:GetWidth() * math.max(0, math.min(1, frac or 0))))
        f.text:SetText(text or "")
        f.full:SetPoint("RIGHT", f.bar, "LEFT", -12, 3)
    else
        f.full:SetPoint("RIGHT", f.mine, "LEFT", -6, 0)
    end
    local ah = FT.ahOpen and S.Supported()
    f.full:SetUsable(ah)
    f.mine:SetUsable(ah)
    if not ah then
        f.full:SetTip(L["Full scan"], L["Open the auction house first."])
        f.mine:SetTip(L["My items"], L["Open the auction house first."])
    else
        f.full:SetTip(L["Full scan"], L["The whole auction house in a few seconds: the lowest price and how many are listed of every item. Any time. (Settings > Scanning: a deep scan reads every auction and order book, once every 15 minutes.)"])
        f.mine:SetTip(L["My items"], L["Only what matters to you: what your recipes make and use, your watchlist and what you own - one search each, cheapest first. Any time; it pauses while you search yourself."])
    end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function Build()
    UI.ResolveFont()
    win = CreateFrame("Frame", "ForeverTradingFrame", UIParent)
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:SetScale(FT.S.scale or 1)
    PlaceWindow()
    UI.Fill(win, "bg0")
    UI.Border(win, "line")
    table.insert(UISpecialFrames, "ForeverTradingFrame")

    -- header
    local header = CreateFrame("Frame", nil, win)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(44)
    UI.Fill(header, "bg0")
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        -- the full-screen window stays where it is
        if SizeMode() ~= "max" then win:StartMoving() end
    end)
    header:SetScript("OnDragStop", function()
        win:StopMovingOrSizing()
        SavePos()
    end)
    local hl = UI.HLine(header, "line")
    hl:SetPoint("BOTTOMLEFT")
    hl:SetPoint("BOTTOMRIGHT")

    local logo = UI.Icon(header, 24)
    logo:SetIcon("Interface\\Icons\\INV_Misc_Coin_02")
    logo:SetPoint("LEFT", 14, 0)
    local brand1 = UI.Text(header, 15, "accent")
    brand1:SetPoint("LEFT", logo, "RIGHT", 10, 0)
    brand1:SetText("FOREVER")
    local brand2 = UI.Text(header, 15, "text")
    brand2:SetPoint("LEFT", brand1, "RIGHT", 1, 0)
    brand2:SetText("TRADING")

    local items = {}
    for _, key in ipairs(TAB_ORDER) do items[#items + 1] = { key, L[TAB_LABELS[key]] } end
    nav = UI.NavTabs(header, items, function(key) FT.SelectTab(key) end)
    nav:SetPoint("LEFT", brand2, "RIGHT", 28, 0)

    local close = UI.Button(header, "×", 30, 30, "ghost", function() win:Hide() end)
    close.label:SetFont(UI.FONT, 18, "")
    close:SetPoint("RIGHT", -8, 0)

    local sizes = BuildSizeButtons(header, close)

    scanText = UI.Text(header, 11, "muted", "RIGHT")
    scanText:SetPoint("RIGHT", sizes, "LEFT", -14, 0)
    scanDot = UI.Tex(header, "OVERLAY", "dim", 1)
    scanDot:SetSize(7, 7)
    scanDot:SetPoint("RIGHT", scanText, "LEFT", -7, 0)
    BuildScanBox(header, scanDot, sizes)
    FT.UpdateScanBox()

    -- ticker tape
    ticker = BuildTicker(win)
    ticker:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    ticker:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
    if not FT.S.ticker then ticker:SetHeight(1) ticker:Hide() end
    local tl = UI.HLine(win, "line")
    tl:SetPoint("TOPLEFT", ticker, "BOTTOMLEFT")
    tl:SetPoint("TOPRIGHT", ticker, "BOTTOMRIGHT")

    -- status bar
    local status = CreateFrame("Frame", nil, win)
    status:SetPoint("BOTTOMLEFT", 1, 1)
    status:SetPoint("BOTTOMRIGHT", -1, 1)
    status:SetHeight(22)
    UI.Fill(status, "bg1")
    local sl = UI.HLine(status, "line")
    sl:SetPoint("TOPLEFT")
    sl:SetPoint("TOPRIGHT")
    statusLeft = UI.Text(status, 10, "muted")
    statusLeft:SetPoint("LEFT", 12, 0)
    statusRight = UI.Text(status, 10, "dim", "RIGHT")
    statusRight:SetPoint("RIGHT", -12, 0)
    statusRight:SetText("v" .. FT.VERSION .. "   /ft")


    -- pages
    content = CreateFrame("Frame", nil, win)
    content:SetPoint("TOPLEFT", ticker, "BOTTOMLEFT", 0, -1)
    content:SetPoint("BOTTOMRIGHT", status, "TOPRIGHT", 0, 0)

    win:SetScript("OnShow", function()
        FT.UpdateStatus()
        FT.UpdateTicker()
        FT.Market.EnsureFresh()
    end)
    win:SetScript("OnHide", function()
        UI.CloseMenu()
        win:StopMovingOrSizing()
    end)
    win:Hide()
end

local function Page(name)
    local p = pages[name]
    if p then return p end
    p = CreateFrame("Frame", nil, content)
    p:SetAllPoints()
    pages[name] = p
    local tab = FT.Tabs[name]
    if tab and tab.Build then
        local ok, err = pcall(tab.Build, p)
        if not ok then geterrorhandler()(err) end
    end
    p.built = true
    return p
end

function FT.SelectTab(name)
    if not FT.Tabs[name] then name = "market" end
    FT.currentTab = name
    nav:SetValue(name)
    local page = Page(name)
    for n, p in pairs(pages) do p:SetShown(n == name) end
    local tab = FT.Tabs[name]
    local fn = tab.OnShow or tab.Refresh
    if fn then
        local ok, err = pcall(fn, page)
        if not ok then geterrorhandler()(err) end
    end
end

function FT.Show(tab)
    if not win then Build() end
    win:Show()
    win:Raise()
    FT.SelectTab(tab or FT.currentTab or "market")
end

function FT.Toggle()
    if win and win:IsShown() then
        win:Hide()
    else
        FT.Show()
    end
end

function FT.Window()
    return win
end

function FT.IsShown()
    return win ~= nil and win:IsShown()
end

-- open an item on the Market page
function FT.OpenItem(itemID)
    FT.Show("market")
    if FT.Tabs.market.Select then FT.Tabs.market.Select(itemID) end
end

-- open a recipe on the Craft page
function FT.OpenRecipe(key)
    FT.Show("craft")
    if FT.Tabs.craft.Select then FT.Tabs.craft.Select(key) end
end

-- the page on screen follows new data (once things have settled)
local function RefreshVisible()
    if not FT.IsShown() then return end
    FT.UpdateStatus()
    local tab = FT.Tabs[FT.currentTab]
    local page = pages[FT.currentTab]
    if tab and tab.Refresh and page then
        local ok, err = pcall(tab.Refresh, page)
        if not ok then geterrorhandler()(err) end
    end
end

local function Later() FT.Debounce("uiRefresh", 0.6, RefreshVisible) end
FT.On("FT_SCAN_DONE", Later)
FT.On("FT_PRICES_CHANGED", Later)
FT.On("FT_RECIPES_CHANGED", Later)
FT.On("FT_INVENTORY_CHANGED", Later)
FT.On("FT_WATCH_CHANGED", function()
    Later()
    if FT.IsShown() then FT.UpdateTicker() end
end)
FT.On("FT_ITEMS_LOADED", Later)
FT.On("FT_SCAN_START", function()
    if FT.IsShown() then
        FT.UpdateStatus()
        FT.UpdateScanBox()
    end
end)
FT.On("FT_SCAN_FAILED", function() if FT.IsShown() then FT.UpdateStatus() end end)
FT.On("FT_AH_CHANGED", function() if FT.IsShown() then FT.UpdateScanBox() end end)
FT.On("FT_MARKET_READY", function()
    if FT.IsShown() then
        FT.UpdateTicker()
        Later()
    end
end)

-- status line ages ("5m ago") even when nothing else happens
C_Timer.NewTicker(30, function() if FT.IsShown() then FT.UpdateStatus() end end)

FT.On("DISPLAY_SIZE_CHANGED", function() if win and SizeMode() == "max" then PlaceWindow() end end)
FT.On("UI_SCALE_CHANGED", function() if win and SizeMode() == "max" then PlaceWindow() end end)
