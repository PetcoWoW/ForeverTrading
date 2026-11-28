-- Wolf: the main window - header with navigation, the ticker tape, pages, status bar.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

FT.Tabs = {}

-- v0.42: four tabs - Today, Market, Make gold, You (Settings behind the gear). Make gold and You are groups of
-- pages, switched by one row of buttons on each of them (UI.GroupBar): Flip it / Craft it / Farm it / Raids / PvP, and
-- Holdings / Sessions / Characters / Journal.
local TAB_ORDER = { "today", "market", "craft", "make", "you", "calc", "settings" }
local TAB_LABELS = { today = "Today", market = "Market", craft = "Craft", make = "Make gold", you = "You", signals = "Make gold",
    calc = "Calculator", radar = "Raids", pvp = "PvP", portfolio = "You", sell = "Sell", sessions = "Sessions", settings = "Settings" }

-- the groups: their sections in order { key, label, page, view (the page's own view, if it has views) }
FT.GROUPS = {
    make = { { "make", "Flip it", "signals", "make" }, { "craft", "Craft it", "signals", "craft" }, { "farm", "Farm it", "signals", "farm" },
        { "raid", "Raids", "radar" }, { "pvp", "PvP", "pvp" } },
    you = { { "portfolio", "Holdings", "portfolio", "portfolio" }, { "sessions", "Sessions", "sessions" },
        { "chars", "Characters", "portfolio", "chars" }, { "journal", "Journal", "portfolio", "journal" } },
}
-- the group a page belongs to (the tab that lights up for it)
local GROUP_OF = { signals = "make", radar = "make", pvp = "make", portfolio = "you", sessions = "you", sell = "you" }
local groupBars = { make = {}, you = {} }
local groupLast = { make = "make", you = "portfolio" }

local win, nav, content, ticker, statusLeft, statusRight, scanDot, scanText, sizeBox, gearBtn, brand
local lastPage = "today"
local quickSearch
local pages = {}

-- three sizes instead of dragging a corner: compact, standard, the whole screen
local SIZES = { min = { 1100, 640 }, std = { 1240, 740 } }
local SIZE_ORDER = { "min", "std", "max" }

-- (v0.52) compact unless Settings says otherwise (the three buttons in the header went to Settings)
local function SizeMode()
    local m = FT.S and FT.S.windowSize
    return (m == "std" or m == "max") and m or "min"
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

-- the pages lay themselves out for the size (compact: charts only)
local function LayoutPages()
    for name, p in pairs(pages) do
        local tab = FT.Tabs[name]
        if tab and tab.OnLayout and p.built then
            local ok, err = pcall(tab.OnLayout, p)
            if not ok then geterrorhandler()(err) end
        end
    end
end

-- the brand: its name only in the full-screen window, else the coin (the pages' names need the room); in the
-- compact window the auction house pill is its light alone
function FT.LayoutBrand()
    if not brand then return end
    local roomy = FT.WindowMaximized()
    -- the classic look's banner carries the name, but it's off the screen when the window fills it
    if win and win.banner then win.banner:SetShown(not roomy) end
    for _, w in ipairs(brand.words) do w:SetShown(roomy) end
    FT.UpdateAHPill()
    brand.pill:ClearAllPoints()
    if not roomy then
        -- the classic portrait's gold ring reaches past the picture
        brand.pill:SetPoint("LEFT", brand.logo, "RIGHT", UI.Classic() and 18 or 10, 0)
    else
        brand.pill:SetPoint("LEFT", brand.words[2], "RIGHT", 16, 0)
    end
end

function FT.SetWindowSize(mode)
    FT.S.windowSize = mode
    if win then
        PlaceWindow()
        LayoutPages()
        FT.LayoutBrand()
        FT.UpdateScanBox()
    end
end

function FT.WindowMaximized()
    return SizeMode() == "max"
end

-- the compact window: the order book and the cards under the charts make way
function FT.Compact()
    return FT.db ~= nil and SizeMode() == "min"
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
        b.hover = UI.RoundTex(b, "BACKGROUND", "bg2", 1)
        b.hover:SetAllPoints()
        b.hover:Hide()
        b.box = CreateFrame("Frame", nil, b)
        b.box:SetSize(frames[mode][1], frames[mode][2])
        b.box:SetPoint("CENTER")
        UI.Border(b.box, "muted", nil, "none")
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
    -- solid in both looks: the fades at its ends are the same colour
    if UI.Classic() then
        t.bg = UI.Tex(t, "BACKGROUND", "bg1", 1, -8)
        t.bg:SetAllPoints()
    else
        UI.Fill(t, "bg1", nil, "none")
    end
    if t.SetClipsChildren then pcall(t.SetClipsChildren, t, true) end
    t.entries = {}
    t.speed = 18 -- v0.42: slower (was 28)
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
        -- the tape stops under the mouse, so the item is easy to click (Settings: keep it moving)
        e:SetScript("OnEnter", function(self)
            if not FT.S.tickerMove then t.paused = true end
            if self.itemID then UI.TipItem(self, self.itemID, "ANCHOR_BOTTOM") end
        end)
        e:SetScript("OnLeave", function()
            t.paused = false
            GameTooltip:Hide()
        end)
        t.entries[i] = e
        return e
    end

    -- the entries hang on one strip that moves: one anchor a frame (an entry is placed again only when it goes
    -- round from the left edge to the end)
    t.strip = CreateFrame("Frame", nil, t)
    t.strip:SetSize(1, 26)
    t.offset = 0
    local function PlaceStrip(self)
        self.strip:ClearAllPoints()
        self.strip:SetPoint("LEFT", self, "LEFT", self.offset, 0)
    end
    local function PlaceEntry(self, e)
        e:ClearAllPoints()
        e:SetPoint("LEFT", self.strip, "LEFT", e.x, 0)
    end

    -- New entries keep the tape where it is: they start where the leftmost one on screen stands, from that same
    -- item when it's still in the list (a refresh used to send the tape back to the start)
    function t:SetEntries(list)
        local x = 12
        local old = self.list
        if old and #old > 0 and #list > 0 then
            local leftX, leftID
            for i = 1, #old do
                local e = self.entries[i]
                if e and e.x and e.w and e.x + e.w + self.offset >= 0 and (not leftX or e.x < leftX) then
                    leftX, leftID = e.x, e.itemID
                end
            end
            if leftX then
                x = leftX
                for k, item in ipairs(list) do
                    if item.id == leftID and k > 1 then
                        local turned = {}
                        for i = k, #list do turned[#turned + 1] = list[i] end
                        for i = 1, k - 1 do turned[#turned + 1] = list[i] end
                        list = turned
                        break
                    end
                end
            else
                self.offset = 0
            end
        else
            self.offset = 0
        end
        self.list = list
        PlaceStrip(self)
        local start = x
        for i, item in ipairs(list) do
            local e = Entry(i)
            e.itemID = item.id
            e.text:SetText(item.text)
            e:SetWidth(math.ceil(e.text:GetStringWidth()) + 4)
            e.x, e.w = x, e:GetWidth()
            x = x + e.w + 34
            PlaceEntry(self, e)
            e:Show()
        end
        for i = #list + 1, #self.entries do self.entries[i]:Hide() end
        self.total = x - start + 12 -- how long the whole tape is (all of it fits: it stands still)
        self.right = x - 34 -- the right edge of the last entry, on the strip
    end

    t:SetScript("OnUpdate", function(self, elapsed)
        if self.paused or not self.list or #self.list == 0 then return end
        local W = self:GetWidth()
        if (self.total or 0) <= W then
            -- everything fits: no need to move
            return
        end
        local n = #self.list
        self.offset = self.offset - self.speed * math.min(elapsed, 0.1)
        if self.offset < -10000 then
            -- far along: the strip back to the start, the entries with it
            for i = 1, n do
                local e = self.entries[i]
                e.x = e.x + self.offset
                PlaceEntry(self, e)
            end
            self.right = self.right + self.offset
            self.offset = 0
        end
        PlaceStrip(self)
        for i = 1, n do
            local e = self.entries[i]
            if e.x + e.w + self.offset < 0 then
                -- gone past the left edge: after the last one
                e.x = math.max(self.right + 34, W - self.offset)
                self.right = e.x + e.w
                PlaceEntry(self, e)
            end
            if not self.clips then
                local sx = e.x + self.offset
                e:SetShown(sx >= 0 and sx + e.w <= W)
            end
        end
    end)
    t.clips = t.SetClipsChildren ~= nil
    return t
end

local function TickerText(id, price, ch)
    local sym = FT.Symbol(id)
    local name = sym ~= "" and FT.C("accent", "$" .. sym) or FT.C("muted", FT.Trunc(FT.Item(id) or ("#" .. id), 20))
    return name .. "  " .. FT.Money(price, "short") .. "  " .. FT.Pct(ch)
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
    -- what you own, the most valuable first
    local owned = 0
    for _, h in ipairs((FT.Port.Rows())) do
        if owned >= 8 then break end
        if not seen[h.id] then
            local r = FT.Market.Row(h.id)
            list[#list + 1] = { id = h.id, text = "|cff0ecb81•|r " .. TickerText(h.id, h.price, r and r.ch1) }
            seen[h.id] = true
            owned = owned + 1
        end
    end
    local movers = 0
    for _, r in ipairs(FT.Market.Movers(8, "ch1", true)) do
        if not seen[r.id] and r.ch1 > 0 then
            list[#list + 1] = { id = r.id, text = TickerText(r.id, r.price, r.ch1) }
            seen[r.id] = true
            movers = movers + 1
        end
    end
    for _, r in ipairs(FT.Market.Movers(8, "ch1", false)) do
        if not seen[r.id] and r.ch1 < 0 then
            list[#list + 1] = { id = r.id, text = TickerText(r.id, r.price, r.ch1) }
            seen[r.id] = true
            movers = movers + 1
        end
    end
    if movers == 0 then
        -- no moves known yet (the first days of prices - of this auction house too): the most valuable listings,
        -- after the watchlist
        for _, r in ipairs(FT.Market.TopByValue(14)) do
            if not seen[r.id] then
                list[#list + 1] = { id = r.id, text = TickerText(r.id, r.price, r.ch1) }
                seen[r.id] = true
            end
        end
    end
    if #list == 0 then
        list[1] = { text = FT.C("dim", L["No market data yet: it comes with the next update, or scan in Auctionator."]) }
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

    -- where the prices come from: Blizzard's (the price feed), your own scan (Auctionator's count), the exchange;
    -- the newest one in green, the feed in yellow once it's over two hours old
    local parts = {}
    local feedT = FT.Feed.On() and FT.Feed.Time() or nil
    local own = FT.ScanTime()
    local newest = math.max(feedT or 0, own or 0)
    local function Age(label, t, used)
        if not t then return FT.C("dim", label .. ": " .. L["none"]) end
        return FT.C(used and "up" or "muted", label) .. " " .. FT.C(used and "text" or "muted", FT.Ago(t))
    end
    parts[#parts + 1] = Age(L["Blizzard API"], feedT, feedT and feedT >= (own or 0))
    parts[#parts + 1] = Age(L["Your AH scan"], own, own and own > (feedT or 0))
    local rows = FT.Market.Rows()
    if rows then parts[#parts + 1] = string.format(L["Market: %s items"], FT.Num(#rows)) end
    statusLeft:SetText(table.concat(parts, FT.C("dim", "   ||   ")))
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
    f.stop = UI.Button(f, L["Stop"], 10, 22, "down", function() FT.Scanner.Stop("user") end)
    f.stop:FitText(20)
    f.stop:SetPoint("RIGHT", 0, 0)
    f.bar = CreateFrame("Frame", nil, f)
    f.bar:SetSize(160, 4)
    f.bar:SetPoint("BOTTOMRIGHT", f.stop, "BOTTOMLEFT", -10, 3)
    UI.Fill(f.bar, "bg3", nil, "none")
    f.fill = UI.Tex(f.bar, "ARTWORK", "accent", 1)
    f.fill:SetPoint("TOPLEFT")
    f.fill:SetPoint("BOTTOMLEFT")
    f.text = UI.Text(f, 10, "muted", "RIGHT")
    f.text:SetPoint("BOTTOMRIGHT", f.bar, "TOPRIGHT", 0, 4)
    f.text:SetWidth(160)
    f.elapsed = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed < 0.2 then return end
        self.elapsed = 0
        -- only while a scan or the exchange runs (and once when it ends): the rest comes with the events
        local busy = FT.Scanner.mode ~= nil
        if busy or self.busy then
            self.busy = busy
            FT.UpdateScanBox()
        end
    end)
    scanBox = f
    return f
end

function FT.UpdateQuickSearch()
    if not quickSearch then return end
    local show = FT.currentTab ~= "market" and not (FT.Scanner and FT.Scanner.mode ~= nil)
    if not show and quickSearch:HasFocus() then quickSearch:ClearFocus() end
    quickSearch:SetShown(show)
end

function FT.UpdateScanBox()
    local f = scanBox
    if not f then return end
    local S = FT.Scanner
    local running = S.mode ~= nil
    FT.UpdateQuickSearch()
    f:SetShown(running)
    f.stop:SetShown(running)
    f.bar:SetShown(running)
    f.text:SetShown(running)
    f:ClearAllPoints()
    f:SetPoint("RIGHT", f.closeButton, "LEFT", -12, 0)
    if running then
        local frac, text = S.Progress()
        f.fill:SetWidth(math.max(1, f.bar:GetWidth() * math.max(0, math.min(1, frac or 0))))
        f.text:SetText(text or "")
    end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function Build()
    UI.ResolveFont()
    win = CreateFrame("Frame", "WolfOfBootyBayFrame", UIParent, UI.EdgeTemplate())
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:SetScale(FT.S.scale or 1)
    PlaceWindow()
    UI.Skin(win, "window", "bg0")
    -- (v0.53: no title banner over the top edge - the header has the logo (the game's black wolf icon), and drags the window)
    table.insert(UISpecialFrames, "WolfOfBootyBayFrame")

    -- header
    local header = CreateFrame("Frame", nil, win)
    header:SetPoint("TOPLEFT", UI.INSET, -UI.INSET)
    header:SetPoint("TOPRIGHT", -UI.INSET, -UI.INSET)
    header:SetHeight(44)
    UI.Fill(header, "bg0", nil, "top", UI.RADIUS - UI.INSET)
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

    -- the classic look: a round portrait with the gold ring
    local logo = UI.Classic() and UI.Portrait(header, 22, FT.LOGO) or UI.Icon(header, 24)
    logo:SetIcon(FT.LOGO)
    logo:SetPoint("LEFT", UI.Classic() and 10 or 14, 0)
    local brand1 = UI.Text(header, 15, "accent")
    brand1:SetPoint("LEFT", logo, "RIGHT", UI.Classic() and 18 or 10, 0)
    brand1:SetText("WOLF")
    local brand2 = UI.Text(header, 15, "text")
    brand2:SetPoint("LEFT", brand1, "RIGHT", 1, 0)
    brand2:SetText("")

    -- the pages; Settings is the gear on the right
    local items = {}
    for _, key in ipairs(TAB_ORDER) do
        -- the Craft tab only when it's on (Settings > General)
        if key ~= "settings" and (key ~= "craft" or FT.S.showCraft) then
            items[#items + 1] = { key, L[TAB_LABELS[key]] }
        end
    end
    local pill = FT.BuildAHPill(header)
    brand = { logo = logo, words = { brand1, brand2 }, pill = pill }
    FT.LayoutBrand()
    -- v0.42: no house chip in the header (the light's hover names the auction house)
    local houseChip = FT.BuildHouseChip(header)
    houseChip:SetPoint("LEFT", pill, "RIGHT", 6, 0)
    houseChip:Hide()
    nav = UI.NavTabs(header, items, function(key)
        -- Market from the tabs: its home, the overview (an item opened from elsewhere goes straight to the item)
        if key == "market" and FT.Tabs.market and FT.Tabs.market.Home then FT.Tabs.market.Home() end
        FT.SelectTab(key)
    end)
    nav:SetPoint("LEFT", pill, "RIGHT", 14, 0)

    local close = UI.CloseButton(header, function() win:Hide() end)
    close:SetPoint("RIGHT", UI.Classic() and -4 or -8, 0)

    -- (v0.52) the window's size is in Settings: the header keeps the gear and the close button
    local sizes = close

    -- Settings: a gear (again: back to the page you were on)
    gearBtn = CreateFrame("Button", nil, header)
    gearBtn:SetSize(28, 28)
    gearBtn:SetPoint("RIGHT", sizes, "LEFT", -6, 0)
    gearBtn.hover = UI.RoundTex(gearBtn, "BACKGROUND", "bg2", 1)
    gearBtn.hover:SetAllPoints()
    gearBtn.hover:Hide()
    gearBtn.gear = UI.Gear(gearBtn, 18, "muted")
    gearBtn.gear:SetPoint("CENTER")
    function gearBtn:Update()
        local on = FT.currentTab == "settings"
        self.gear:SetColor(on and "accent" or (self:IsMouseOver() and "text" or "muted"))
    end
    gearBtn:SetScript("OnEnter", function(self)
        self.hover:Show()
        self:Update()
        UI.TipText(self, L["Settings"])
    end)
    gearBtn:SetScript("OnLeave", function(self)
        self.hover:Hide()
        self:Update()
        GameTooltip:Hide()
    end)
    gearBtn:SetScript("OnClick", function()
        if FT.currentTab == "settings" then FT.SelectTab(lastPage) else FT.SelectTab("settings") end
    end)

    -- v0.43: search from any page. The first letter typed takes you to Market, the rest goes on in its own search
    -- box (hidden on Market itself, which has that box, and while a scan shows its progress here)
    -- (v0.61) no jump: what you type shows the items it finds under the box (Extra\UI2.lua), and only picking one
    -- opens it - Back returns you to where you were
    quickSearch = UI.Input(header, 210, 24, L["Search any item..."], function(text)
        if FT.QuickSearchTyped then FT.QuickSearchTyped(quickSearch, text) end
    end, function()
        if FT.QuickSearchEnter then FT.QuickSearchEnter(quickSearch) end
    end)
    quickSearch:SetPoint("RIGHT", gearBtn, "LEFT", -12, 0)

    scanText = UI.Text(header, 11, "muted", "RIGHT")
    scanText:SetPoint("RIGHT", gearBtn, "LEFT", -14, 0)
    scanText:Hide()
    scanDot = UI.Dot(header, 7, "dim", 1, "OVERLAY")
    scanDot:SetPoint("RIGHT", scanText, "LEFT", -7, 0)
    scanDot:Hide()
    BuildScanBox(header, scanDot, gearBtn)
    FT.UpdateScanBox()
    -- what the tour points at
    FT.MainRefs = { nav = nav, pill = pill, house = houseChip, gear = gearBtn, scan = scanBox, search = quickSearch }
    if FT.BuildNav then FT.BuildNav(header, quickSearch, win) end

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
    status:SetPoint("BOTTOMLEFT", UI.INSET, UI.INSET)
    status:SetPoint("BOTTOMRIGHT", -UI.INSET, UI.INSET)
    status:SetHeight(22)
    UI.Fill(status, "bg1", nil, "bottom", UI.RADIUS - UI.INSET)
    local sl = UI.HLine(status, "line")
    sl:SetPoint("TOPLEFT")
    sl:SetPoint("TOPRIGHT")
    statusLeft = UI.Text(status, 10, "muted")
    statusLeft:SetPoint("LEFT", 12, 0)
    statusRight = UI.Text(status, 10, "dim", "RIGHT")
    statusRight:SetPoint("RIGHT", -12, 0)
    statusRight:SetText(FT.VERSION_TEXT .. "   /wolf")
    -- links: support the author, the project on GitHub
    local function StatusLink(text, color, onClick)
        local b = CreateFrame("Button", nil, status)
        b.text = UI.Text(b, 10, color)
        b.text:SetPoint("CENTER")
        b.text:SetText(text)
        b:SetSize(math.ceil(b.text:GetStringWidth()) + 12, 20)
        b:SetScript("OnEnter", function(self) UI.SetTextColor(self.text, "text") end)
        b:SetScript("OnLeave", function(self) UI.SetTextColor(self.text, color) end)
        b:SetScript("OnClick", onClick)
        return b
    end
    local gh = StatusLink("GitHub", "muted", function() FT.ShowGitHub() end)
    gh:SetPoint("RIGHT", statusRight, "LEFT", -12, 0)
    -- a newer version was heard of: where to get it
    local newer = StatusLink("", "up", function() FT.ShowGitHub() end)
    newer:SetPoint("RIGHT", gh, "LEFT", -8, 0)
    local function ShowNewer()
        local v = FT.Ver.Newest()
        newer:SetShown(v ~= nil)
        if v then
            newer.text:SetText(string.format(L["Update available: %s"], v))
            newer:SetWidth(math.ceil(newer.text:GetStringWidth()) + 12)
        end
    end
    ShowNewer()
    FT.On("FT_NEWER_VERSION", ShowNewer)


    -- pages
    content = CreateFrame("Frame", nil, win)
    content:SetPoint("TOPLEFT", ticker, "BOTTOMLEFT", 0, -1)
    content:SetPoint("BOTTOMRIGHT", status, "TOPRIGHT", 0, 0)

    win:SetScript("OnShow", function()
        FT.UpdateStatus()
        FT.UpdateScanBox()
        FT.UpdateTicker()
        FT.Market.EnsureFresh()
    end)
    win:SetScript("OnHide", function()
        UI.CloseMenu()
        win:StopMovingOrSizing()
        -- closing the terminal with the game's window hidden behind it: the visit is over
        -- (not the hiding right after the window is made)
        if win.ready then FT.LeaveAH() end
    end)
    win:Hide()
    win.ready = true
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

-- a section of a group: its page, then its view; every bar of the group shows it
function FT.ShowSub(group, key)
    for _, e in ipairs(FT.GROUPS[group] or {}) do
        if e[1] == key then
            groupLast[group] = key
            if FT.db then FT.db.ui = FT.db.ui or {}; FT.db.ui.groupLast = groupLast end
            FT.SelectTab(e[3])
            local tab = FT.Tabs[e[3]]
            if e[4] and tab and tab.SetView then tab.SetView(e[4]) end
            for _, b in ipairs(groupBars[group]) do b:SetValue(key) end
            return
        end
    end
end

-- the row of section buttons of a group, for a page of it (its value follows whichever section shows)
function UI.GroupBar(parent, group)
    local opts = {}
    for _, e in ipairs(FT.GROUPS[group]) do opts[#opts + 1] = { e[1], L[e[2]] } end
    local bar = UI.Segmented(parent, opts, function(v) FT.ShowSub(group, v) end, 22)
    bar:SetValue(groupLast[group])
    table.insert(groupBars[group], bar)
    return bar
end

-- (for the tests) the section bars of a group
function FT.GroupBarsOf(group) return groupBars[group] end

-- (v0.61) where you are, for Back and Forward (Extra\UI2.lua): the page, its section, the item open on Market,
-- Farm it's mode; nil while the window is closed
function FT.Place()
    if not (win and win:IsShown() and FT.currentTab) then return nil end
    local tab = FT.currentTab
    local p = { tab = tab }
    local g = GROUP_OF[tab]
    if g then p.group, p.sub = g, groupLast[g] end
    if tab == "market" and FT.Tabs.market and FT.Tabs.market.CurrentItem then p.item = FT.Tabs.market.CurrentItem() end
    if tab == "signals" and p.sub == "farm" and FT.Tabs.signals.FarmMode then p.farm = FT.Tabs.signals.FarmMode() end
    return p
end

-- a place in words: "Make gold › Farm it › Dungeons", "Market › Arcanite Bar"
function FT.PlaceName(p)
    if not p then return "" end
    local bits = { L[TAB_LABELS[p.group or p.tab] or p.tab] or p.tab }
    if p.group then
        for _, e in ipairs(FT.GROUPS[p.group] or {}) do if e[1] == p.sub then bits[#bits + 1] = L[e[2]] end end
    end
    if p.farm and FT.Tabs.signals.FarmModeName then bits[#bits + 1] = FT.Tabs.signals.FarmModeName(p.farm) end
    if p.item then bits[#bits + 1] = FT.Name(p.item) or "?" end
    return table.concat(bits, " › ")
end

-- a page's own view changed (from inside it): the group's bars follow
function FT.GroupShows(group, key)
    if not FT.GROUPS[group] then return end
    groupLast[group] = key
    for _, b in ipairs(groupBars[group]) do b:SetValue(key) end
end

function FT.SelectTab(name)
    -- a group's tab: the section shown there last
    if FT.GROUPS[name] then
        local saved = FT.db and FT.db.ui and FT.db.ui.groupLast
        -- (v0.51: Coming up came apart - its farms are Farm it's Next week, its raids Raids)
        if saved then for g, k in pairs(saved) do groupLast[g] = (k == "coming") and "raid" or k end end
        return FT.ShowSub(name, groupLast[name])
    end
    if not FT.Tabs[name] then name = "today" end
    FT.currentTab = name
    if name ~= "settings" then
        lastPage = name
        if FT.db then FT.db.ui = FT.db.ui or {}; FT.db.ui.lastTab = name end
    end
    nav:SetValue(GROUP_OF[name] or name)
    if gearBtn then gearBtn:Update() end
    FT.UpdateQuickSearch()
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
    local open = win:IsShown()
    win:Show()
    win:Raise()
    if tab == "sell" then
        FT.SelectTab("portfolio")
        if FT.Tabs.portfolio and FT.Tabs.portfolio.SetView then FT.Tabs.portfolio.SetView("sell") end
        tab = nil
    else
        -- opened: Today, every time (v0.43); already open: the page you're on
        FT.SelectTab(tab or (open and FT.currentTab) or "today")
    end
    -- once a version: what's new (or, on a first install, the tour)
    if FT.News then C_Timer.After(0.4, FT.News.OnWindow) end
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

-- open an item on the Market page: its list shows just that item (× in the search box: all again)
function FT.OpenItem(itemID)
    local T = FT.Tabs.market
    T.opening = T.Focus ~= nil
    local ok, err = pcall(FT.Show, "market")
    T.opening = nil
    if not ok then geterrorhandler()(err) end
    if T.Focus then T.Focus(itemID) elseif T.Select then T.Select(itemID) end
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
        local ok, err = pcall(tab.RefreshSoft or tab.Refresh, page)
        if not ok then geterrorhandler()(err) end
    end
end

local function Later() FT.Debounce("uiRefresh", 0.6, RefreshVisible) end
FT.On("FT_SCAN_DONE", Later)
FT.On("FT_SCAN_DONE", function() FT.UpdateAHPill() end)
FT.On("FT_PRICES_CHANGED", Later)
FT.On("FT_RECIPES_CHANGED", Later)
FT.On("FT_LEARNED", Later)
FT.On("FT_INVENTORY_CHANGED", Later)
FT.On("FT_WHALES_READY", Later)
FT.On("FT_WATCH_CHANGED", function()
    Later()
    if FT.IsShown() then FT.UpdateTicker() end
end)
FT.On("FT_ITEMS_LOADED", function()
    if not FT.IsShown() then return end
    local tab, page = FT.Tabs[FT.currentTab], pages[FT.currentTab]
    if tab and tab.OnItems and page then
        local ok, err = pcall(tab.OnItems, page)
        if not ok then geterrorhandler()(err) end
    else
        FT.Debounce("uiRefresh", 1.5, RefreshVisible)
    end
end)
FT.On("FT_SCAN_START", function()
    if FT.IsShown() then
        FT.UpdateStatus()
        FT.UpdateScanBox()
    end
end)
FT.On("FT_SCAN_FAILED", function() if FT.IsShown() then FT.UpdateStatus() end end)

-- a live price (id), or the auction house opened or closed (nil): the open page's item follows
local function Live(id)
    if not FT.IsShown() then return end
    local tab, page = FT.Tabs[FT.currentTab], pages[FT.currentTab]
    if tab and tab.OnLive and page then
        local ok, err = pcall(tab.OnLive, page, id)
        if not ok then geterrorhandler()(err) end
    end
end
FT.On("FT_LIVE_UPDATED", Live)
FT.On("FT_AH_CHANGED", function()
    if not FT.IsShown() then return end
    FT.UpdateScanBox()
    FT.UpdateAHPill()
    Live(nil)
end)

---------------------------------------------------------------------------
-- In place of the auction house window (Settings): talking to an auctioneer opens Wolf. The game's
-- window stays open behind it, unseen (closing it would end the visit): see-through and off the screen. The
-- pill in the header shows whether you are at the auction house and brings the game's window back for buying
-- and selling (and Auctionator). Walking away ends the visit: the terminal goes "offline".
---------------------------------------------------------------------------
local ahHidden, ahPoints, ahClamped, pill

local function AHFrame()
    return AuctionHouseFrame or AuctionFrame
end

local function OffScreen(f)
    f:SetAlpha(0)
    f:ClearAllPoints()
    f:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", -50, -50)
end

local function HideAHWindow()
    local f = AHFrame()
    if not f or ahHidden then return end
    ahPoints = {}
    for i = 1, f:GetNumPoints() do ahPoints[i] = { f:GetPoint(i) } end
    ahClamped = f.IsClampedToScreen and f:IsClampedToScreen()
    ahHidden = true
    if f.SetClampedToScreen then f:SetClampedToScreen(false) end
    OffScreen(f)
end

local function ShowAHWindow()
    local f = AHFrame()
    if not f or not ahHidden then return end
    ahHidden = false
    f:SetAlpha(1)
    if f.SetClampedToScreen and ahClamped ~= nil then f:SetClampedToScreen(ahClamped) end
    f:ClearAllPoints()
    for _, p in ipairs(ahPoints or {}) do f:SetPoint(unpack(p)) end
    if not (ahPoints and ahPoints[1]) then f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116) end
end

-- the game puts its windows back in place now and then: ours stays out of sight
local hookedPanels = false
local function HookPanels()
    if hookedPanels or not UpdateUIPanelPositions then return end
    hookedPanels = true
    hooksecurefunc("UpdateUIPanelPositions", function()
        local f = AHFrame()
        if ahHidden and f then OffScreen(f) end
    end)
end

-- Where the prices come from, in two chips: AH (your last auction house scan: Auctionator's or this addon's) and
-- API (Blizzard's hourly prices, shipped with every update). The one the pages go by is lit; an old one is yellow.
local function ShortAgo(t)
    if not t then return "--" end
    local s = math.max(0, time() - t)
    if s < 3600 then return math.max(1, math.floor(s / 60)) .. "m" end
    if s < 86400 then return math.floor(s / 3600) .. "h" end
    return math.floor(s / 86400) .. "d"
end

-- the newest scan of yours: this addon's own record, or Auctionator's last scan time
function FT.ScanTime()
    local own = FT.Hist.LastScan("full")
    local atr = FT.Atr and FT.Atr.LastScanTime and FT.Atr.LastScanTime()
    local t = math.max(own or 0, atr or 0)
    return t > 0 and t or nil, (atr and atr >= (own or 0)) and "auctionator" or "own"
end

local function PaintChip(c, label, t, lit, old)
    UI.SetTexColor(c.dot, (not t and "dim") or (old and "accent") or (lit and "up" or "muted"), 1)
    UI.SetTextColor(c.text, lit and "text" or "muted")
    c.text:SetText(FT.Compact() and label or (label .. " " .. FT.C(old and "accent" or (lit and "text" or "dim"), ShortAgo(t))))
    c:SetWidth(math.ceil(c.text:GetStringWidth()) + 28)
end

-- v0.42: one freshness light. "Prices 20 min old" for the newer of your scan and Blizzard's prices; its dot green
-- under an hour, yellow under four, red older; "New prices: click" when the companion has newer ones waiting.
-- The split (your scan / Blizzard's) is in its hover.
function FT.UpdateAHPill()
    if not pill then return end
    local scanT = FT.ScanTime()
    local apiT = FT.Feed.On() and FT.Feed.Time() or nil
    local t = math.max(scanT or 0, apiT or 0)
    if t == 0 then t = nil end
    local fresh = FT.Companion and FT.Companion.FreshReady()
    local c = pill.ah
    local age = t and math.max(0, time() - t) or nil
    local color = (not t and "dim") or (age < 3600 and "up") or (age < 4 * 3600 and "accent") or "down"
    UI.SetTexColor(c.dot, fresh and "accent" or color, 1)
    UI.SetTextColor(c.text, "text")
    local text
    if fresh then
        text = L["New prices: click"]
    elseif not t then
        text = L["No prices yet"]
    elseif FT.Compact() then
        text = ShortAgo(t)
    else
        text = string.format(L["Prices %s old"], age < 3600 and string.format(L["%d min"], math.max(1, math.floor(age / 60))) or ShortAgo(t))
    end
    c.text:SetText(text)
    c:SetWidth(math.ceil(c.text:GetStringWidth()) + 28)
    pill.api:Hide()
    pill:SetWidth(c:GetWidth())
end

local function SourceChip(parent)
    local c = CreateFrame("Button", nil, parent)
    c:SetHeight(22)
    c.bg = UI.RoundTex(c, "BACKGROUND", "bg2", 1)
    c.bg:SetAllPoints()
    UI.Border(c, "line")
    c.dot = UI.Dot(c, 7, "dim", 1)
    c.dot:SetPoint("LEFT", 8, 0)
    c.text = UI.Text(c, 11, "muted")
    c.text:SetPoint("LEFT", c.dot, "RIGHT", 6, 0)
    c:SetScript("OnLeave", function(self)
        UI.SetTexColor(self.bg, "bg2", 1)
        GameTooltip:Hide()
    end)
    return c
end

function FT.BuildAHPill(header)
    pill = CreateFrame("Frame", nil, header)
    pill:SetHeight(22)
    pill.ah = SourceChip(pill)
    pill.ah:SetPoint("LEFT", 0, 0)
    pill.api = SourceChip(pill)
    pill.api:SetPoint("LEFT", pill.ah, "RIGHT", 4, 0)
    pill.ah:SetScript("OnEnter", function(self)
        UI.SetTexColor(self.bg, "bg3", 1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["How fresh the prices are"], 1, 1, 1)
        local scanT, who = FT.ScanTime()
        local apiT = FT.Feed.On() and FT.Feed.Time() or nil
        GameTooltip:AddDoubleLine(who == "auctionator" and L["Your AH scan (Auctionator)"] or L["Your AH scan"],
            scanT and FT.Ago(scanT) or L["none yet"], 0.87, 0.75, 0.42, 1, 1, 1)
        GameTooltip:AddDoubleLine(L["Blizzard's prices"], apiT and (FT.TimeOfDay(apiT) .. " (" .. FT.Ago(apiT) .. ")") or (FT.Feed.WhyOff() or L["not loaded"]),
            0.87, 0.75, 0.42, 1, 1, 1)
        GameTooltip:AddLine(string.format(L["Auction house: %s"], FT.House.Name(FT.house)), 0.6, 0.64, 0.7)
        GameTooltip:AddLine(" ")
        if FT.Companion.FreshReady() then
            GameTooltip:AddLine(L["Newer prices are in your addon folder (the prices companion fetched them). Click: load them (reloads the interface)."], 1, 0.82, 0, true)
        elseif FT.Companion.Running() then
            GameTooltip:AddLine(L["New prices come about every hour; the prices companion fetches them and chat says when they're ready."], 0.6, 0.64, 0.7, true)
        else
            GameTooltip:AddLine(L["Blizzard's prices come with each Wolf update; your own scans and Auctionator's keep them fresh in between."], 0.6, 0.64, 0.7, true)
        end
        if FT.Atr and FT.Atr.On() then GameTooltip:AddLine(L["Click: take Auctionator's last scan again."], 0.58, 0.55, 0.5) end
        if FT.ahOpen and ahHidden then GameTooltip:AddLine(L["Right-click: show the game's auction house window."], 0.58, 0.55, 0.5) end
        GameTooltip:Show()
    end)
    pill.ah:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pill.ah:SetScript("OnClick", function(_, button)
        if button == "RightButton" then FT.ToggleAHWindow() return end
        if FT.Companion.FreshReady() then ReloadUI() return end
        if not (FT.Feed.On() and FT.Feed.Time()) and not FT.ScanTime() then FT.Show("settings") return end
        if FT.Atr and FT.Atr.TakeLatest then
            local n = FT.Atr.TakeLatest(true)
            if not n then FT.Print(L["Nothing newer from Auctionator: scan in Auctionator at the auction house."]) end
        end
    end)
    pill.api:SetScript("OnEnter", function(self)
        UI.SetTexColor(self.bg, "bg3", 1)
        local t = FT.Feed.On() and FT.Feed.Time() or nil
        local text
        if not t then
            text = FT.C("accent", FT.Feed.WhyOff() or L["Not loaded."]) .. "\n\n" .. L["Click: Settings."]
        else
            text = string.format(L["Blizzard's prices of every item.\n\nThese: %s (%s)."], FT.C(FT.Feed.Stale() and "accent" or "text", FT.TimeOfDay(t)), FT.Ago(t))
            if FT.Companion.FreshReady() then
                text = text .. "\n\n" .. FT.C("accent", L["Newer ones should be in your addon folder by now (the prices companion fetched them). Click: load them (reloads the interface)."])
            elseif FT.Companion.Running() then
                text = text .. "\n\n" .. FT.C("dim", L["New ones come about every hour; the prices companion fetches them, and chat says when there are newer ones to load."])
            else
                text = text .. "\n\n" .. FT.C("dim", L["New ones come with each Wolf update; your own scans and Auctionator's keep them fresh in between."])
            end
        end
        UI.TipText(self, L["API: Blizzard's hourly prices"], text)
    end)
    pill.api:SetScript("OnClick", function()
        if not (FT.Feed.On() and FT.Feed.Time()) then FT.Show("settings")
        elseif FT.Companion.FreshReady() then ReloadUI() end
    end)
    FT.UpdateAHPill()
    C_Timer.NewTicker(30, function() if pill:IsVisible() then FT.UpdateAHPill() end end)
    return pill
end

-- Which auction house (House.lua): your faction's or Blackwater - whose prices the pages show. Coloured by it. One
-- in the header, one in every item window: they all follow.
local chips = {}
local HOUSE_COLORS = { Alliance = "blue", Horde = "down", Neutral = "accent" }

local function UpdateChip(c)
    local house = c.get and c.get() or FT.house
    local color = HOUSE_COLORS[FT.House.Faction(house)] or "accent"
    UI.SetTexColor(c.dot, color, 1)
    c.text:SetText(FT.House.Name(house))
    -- the pencil: the header's only (the auction house you stand at is the whole addon's)
    local fix = FT.ahHere == true and not c.own
    c.fix:SetShown(fix)
    c.sep:SetShown(fix)
    c:SetWidth(math.ceil(c.text:GetStringWidth()) + 30 + (fix and 22 or 0))
end

function FT.UpdateHouseChip()
    for _, c in ipairs(chips) do UpdateChip(c) end
end

-- a small pencil drawn with lines
local function Pencil(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f.lines = { UI.NewLine(f, "OVERLAY"), UI.NewLine(f, "OVERLAY"), UI.NewLine(f, "OVERLAY") }
    function f:SetColor(c)
        local sz = self:GetWidth()
        UI.PlaceLine(self.lines[1], sz * 0.30, sz * 0.30, sz * 0.72, sz * 0.72, sz * 0.22, c) -- the body
        UI.PlaceLine(self.lines[2], sz * 0.12, sz * 0.12, sz * 0.27, sz * 0.27, sz * 0.10, c) -- the tip
        UI.PlaceLine(self.lines[3], sz * 0.78, sz * 0.78, sz * 0.90, sz * 0.90, sz * 0.22, c) -- the end
    end
    f:SetColor("muted")
    return f
end

-- opts (an item window's own house): get() - its house, toggle() - to the other; no pencil
function UI.HouseChip(parent, opts)
    local c = CreateFrame("Button", nil, parent)
    opts = opts or {}
    c.get, c.toggle, c.own = opts.get, opts.toggle, opts.get ~= nil
    function c:Update() UpdateChip(self) end
    c:SetHeight(22)
    c.bg = UI.RoundTex(c, "BACKGROUND", "bg2", 1)
    c.bg:SetAllPoints()
    UI.Border(c, "line")
    c.dot = UI.Dot(c, 7, "accent", 1)
    c.dot:SetPoint("LEFT", 9, 0)
    c.text = UI.Text(c, 11, "muted")
    c.text:SetPoint("LEFT", c.dot, "RIGHT", 6, 0)
    c:SetScript("OnClick", function(self)
        if self.toggle then self.toggle() else FT.House.Toggle() end
    end)
    c:SetScript("OnEnter", function(self)
        UI.SetTexColor(self.bg, "bg3", 1)
        local H = FT.House
        local house = self.get and self.get() or FT.house
        local text = L["The auction house Wolf follows: your faction's. Blackwater, the neutral one, isn't tracked: its prices come too late to act on."]
        if FT.ahHere and FT.atHouse ~= house then
            text = text .. "\n\n" .. string.format(L["You stand at %s: offline here."], H.Name(FT.atHouse))
        end
        UI.TipText(self, string.format(L["Auction house: %s"], H.Name(house)), text)
    end)
    c:SetScript("OnLeave", function(self)
        UI.SetTexColor(self.bg, "bg2", 1)
        GameTooltip:Hide()
    end)
    -- at an auctioneer: the pencil - this auction house is the other one
    c.sep = UI.VLine(c, "line")
    c.sep:SetPoint("TOPRIGHT", -22, -4)
    c.sep:SetPoint("BOTTOMRIGHT", -22, 4)
    c.fix = CreateFrame("Button", nil, c)
    c.fix:SetSize(20, 20)
    c.fix:SetPoint("RIGHT", -1, 0)
    c.fix.icon = Pencil(c.fix, 12)
    c.fix.icon:SetPoint("CENTER")
    c.fix:SetScript("OnClick", function() FT.House.Fix() end)
    c.fix:SetScript("OnEnter", function(self)
        self.icon:SetColor("text")
        local H = FT.House
        local here = FT.atHouse or "faction"
        UI.TipText(self, L["Wrong auction house?"], string.format(L["Click if this auctioneer is of %s, not %s: Wolf puts it right and remembers it for the auctioneers here."],
            H.Name(here == "neutral" and "faction" or "neutral"), H.Name(here)))
    end)
    c.fix:SetScript("OnLeave", function(self)
        self.icon:SetColor("muted")
        GameTooltip:Hide()
    end)
    chips[#chips + 1] = c
    UpdateChip(c)
    return c
end

function FT.BuildHouseChip(header)
    return UI.HouseChip(header)
end

FT.On("FT_LOGIN", function() FT.UpdateHouseChip() end)
-- at an auctioneer or not (the pencil), online or not (the pill)
FT.On("FT_AH_CHANGED", function()
    FT.UpdateHouseChip()
    FT.UpdateAHPill()
end)
FT.On("FT_HOUSE_CHANGED", function()
    FT.UpdateHouseChip()
    FT.UpdateAHPill()
    if pill and GameTooltip:IsOwned(pill) then pill:GetScript("OnEnter")(pill) end
    for _, c in ipairs(chips) do
        if GameTooltip:IsOwned(c) then c:GetScript("OnEnter")(c) end
    end
    if FT.IsShown() then
        FT.UpdateScanBox()
        Later()
    end
end)

-- the game's window or ours in front, while you are at the auction house
function FT.ToggleAHWindow()
    if not FT.ahHere then return end
    if ahHidden then
        ShowAHWindow()
    else
        FT.Show()
        HookPanels()
        HideAHWindow()
    end
    if GameTooltip:IsOwned(pill) and pill:GetScript("OnEnter") then pill:GetScript("OnEnter")(pill) end
end

-- the game's window on the screen (when it was hidden behind Wolf)
function FT.ShowGameAH()
    if FT.ahHere and ahHidden then ShowAHWindow() end
end

-- the terminal closed with the game's window hidden: the visit ends (no unseen auction house left open)
function FT.LeaveAH()
    if not (ahHidden and FT.ahHere) then return end
    local f = AHFrame()
    ShowAHWindow()
    if f and HideUIPanel then
        pcall(HideUIPanel, f)
    elseif C_AuctionHouse and C_AuctionHouse.CloseAuctionHouse then
        pcall(C_AuctionHouse.CloseAuctionHouse)
    end
end

-- in place of the game's window: hidden, ours shown
local function Replace()
    if not (FT.ahHere and FT.S.replaceAH) then return end
    -- ours first (made now the first time), then the game's hidden
    FT.Show()
    HookPanels()
    HideAHWindow()
    FT.UpdateAHPill()
end

-- The game (and other addons: Auctionator's tabs...) may put its window back on the screen in the first moments
-- after it opens - the very first time above all, when the game loads it: looked at again for two seconds.
local function KeepReplaced()
    for _, delay in ipairs({ 0.15, 0.4, 0.8, 1.3, 2 }) do
        C_Timer.After(delay, function()
            local f = AHFrame()
            if not (ahHidden and f and FT.ahHere) then return end
            local left = f:GetLeft()
            if f:GetAlpha() > 0.05 or (left and left > -10) then OffScreen(f) end
        end)
    end
end

-- the moment the game shows its window (hooked as soon as the game has loaded it)
local hookedShow = false
local function HookAHShow()
    local f = AHFrame()
    if hookedShow or not f then return end
    hookedShow = true
    f:HookScript("OnShow", function()
        if FT.S.replaceAH then C_Timer.After(0, Replace) end
    end)
end
FT.On("ADDON_LOADED", function(name)
    if name == "Blizzard_AuctionHouseUI" or name == "Blizzard_AuctionUI" then HookAHShow() end
end)
FT.On("FT_READY", HookAHShow)

FT.On("AUCTION_HOUSE_SHOW", function()
    FT.UpdateAHPill()
    HookAHShow()
    if not FT.S.replaceAH then return end
    -- the game shows its window in the same moment: hidden right after, and kept so
    C_Timer.After(0, function()
        Replace()
        KeepReplaced()
    end)
end)

FT.On("AUCTION_HOUSE_CLOSED", function()
    -- the game closed its window: back in place for the next time
    ShowAHWindow()
    FT.UpdateAHPill()
    FT.UpdateHouseChip()
end)
FT.On("FT_MOVERS_READY", function()
    if FT.IsShown() then
        FT.UpdateTicker()
        Later()
    end
end)
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
