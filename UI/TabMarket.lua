-- ForeverTrading: Market page - every item with its price and moves, the chart of one item, its order
-- book, indicators, signals and price alerts. With no item chosen: the market overview.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local T = {}
FT.Tabs.market = T

local state = { filter = "all", cls = "all", sort = "cap", desc = true, search = "", selected = nil }
local page, list, countText, overview, itemView, book
local LEFT_W, RIGHT_W = 372, 232

local GetClassInfo = (C_Item and C_Item.GetItemClassInfo) or GetItemClassInfo
local GetSubClassInfo = (C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo
local CLASSES = { 7, 0, 9, 5, 4, 2, 15, 1 }
local CLASS_FALLBACK = { [7] = "Trade goods", [0] = "Consumables", [9] = "Recipes", [5] = "Reagents", [4] = "Armor",
    [2] = "Weapons", [15] = "Miscellaneous", [1] = "Containers" }
local KNOWN = {}
for _, c in ipairs(CLASSES) do KNOWN[c] = true end

local function ClassName(id)
    local name = GetClassInfo and GetClassInfo(id)
    return (name and name ~= "") and name or L[CLASS_FALLBACK[id] or "Other"]
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------
local function RecipeItems()
    local set = {}
    FT.Craft.EachItem(function(id) set[id] = true end)
    return set
end

local SORTS = {
    cap = function(r) return r.price * (r.qty or 0) end,
    price = function(r) return r.price end,
    ch1 = function(r) return r.ch1 end,
    ch7 = function(r) return r.ch7 end,
    qty = function(r) return r.qty end,
}

local function Filtered()
    local rows = FT.Market.Rows()
    if not rows then return nil end
    local out = {}
    local search = state.search ~= "" and state.search:lower() or nil
    local mine = state.filter == "mine" and RecipeItems() or nil
    local holdings = state.filter == "bags" and FT.Port.Holdings() or nil
    for _, r in ipairs(rows) do
        local ok = true
        local f = state.filter
        if f == "fav" then
            ok = FT.db.watch[r.id] ~= nil
        elseif f == "mine" then
            ok = mine[r.id] == true
        elseif f == "bags" then
            ok = holdings[r.id] ~= nil
        elseif f == "up" then
            ok = r.ch1 ~= nil and r.ch1 > 0.001
        elseif f == "down" then
            ok = r.ch1 ~= nil and r.ch1 < -0.001
        end
        if ok and state.cls ~= "all" then
            if state.cls == "other" then ok = not KNOWN[r.cls] else ok = r.cls == state.cls end
        end
        if ok and search then
            local name = FT.Name(r.id)
            ok = name ~= nil and name:lower():find(search, 1, true) ~= nil
        end
        if ok then out[#out + 1] = r end
    end
    local key, desc = state.sort, state.desc
    if key == "name" then
        local names = {}
        for _, r in ipairs(out) do names[r.id] = (FT.Name(r.id) or "~"):lower() end
        table.sort(out, function(a, b)
            if names[a.id] ~= names[b.id] then
                if desc then return names[a.id] > names[b.id] end
                return names[a.id] < names[b.id]
            end
            return a.id < b.id
        end)
    else
        local get = SORTS[key] or SORTS.cap
        local missing = desc and -math.huge or math.huge
        table.sort(out, function(a, b)
            local va, vb = get(a) or missing, get(b) or missing
            if va ~= vb then
                if desc then return va > vb end
                return va < vb
            end
            return a.id < b.id
        end)
    end
    return out
end

-- names the game hasn't loaded yet, asked for a few at a time while you search (no flood of requests)
local loader
function T.LoadMissingNames()
    if loader then return end
    local missing = {}
    for _, r in ipairs(FT.Market.Rows() or {}) do
        if not FT.Name(r.id) then missing[#missing + 1] = r.id end
    end
    if #missing == 0 then return end
    local i = 1
    loader = C_Timer.NewTicker(0.5, function()
        if state.search == "" or i > #missing then
            loader:Cancel()
            loader = nil
            return
        end
        for k = i, math.min(i + 39, #missing) do FT.RequestItem(missing[k]) end
        i = i + 40
    end)
end

-- names arrived: the rows on screen show them; a search takes the new matches in now and then
function T.OnItems()
    if list then list:Refresh() end
    if state.search ~= "" then
        FT.Debounce("marketSearchMore", 1.5, function() T.RefreshList(true) end)
    end
end

function T.RefreshList(keepOffset)
    if not list then return end
    local items = Filtered()
    if not items then
        list:SetEmptyText(FT.Market.Building() and L["Reading the market..."] or
            L["No market data yet: open the auction house and press Full scan."])
        list:SetItems({}, keepOffset)
        countText:SetText("")
        return
    end
    list:SetEmptyText(L["Nothing matches"])
    list:SetItems(items, keepOffset)
    countText:SetText(string.format(L["%s items"], FT.Num(#items)))
end

local function NameCell(row)
    local f = CreateFrame("Frame", nil, row)
    f:SetHeight(24)
    f.icon = UI.Icon(f, 18)
    f.icon:SetPoint("LEFT", 0, 0)
    f.star = UI.Text(f, 11, "accent")
    f.star:SetPoint("LEFT", f.icon, "RIGHT", 5, 0)
    f.text = UI.Text(f, 12, "text")
    f.text:SetPoint("LEFT", f.icon, "RIGHT", 6, 0)
    f.text:SetPoint("RIGHT", 0, 0)
    return f
end

local function SparkCell(row)
    local s = UI.Sparkline(row, 40, 16)
    return s
end

local function BuildList(parent)
    local panel = UI.Panel(parent, "bg1", "line")
    panel:SetPoint("TOPLEFT", 8, -8)
    panel:SetPoint("BOTTOMLEFT", 8, 8)
    panel:SetWidth(LEFT_W)

    local search = UI.Input(panel, LEFT_W - 20, 26, L["Search item..."], function(text)
        state.search = text or ""
        FT.Debounce("marketSearch", 0.25, function()
            T.RefreshList()
            if state.search ~= "" then T.LoadMissingNames() end
        end)
    end)
    search:SetPoint("TOPLEFT", 10, -10)

    local chips = {}
    local function Chip(key, label)
        local c = UI.Chip(panel, label, function()
            state.filter = key
            for _, ch in ipairs(chips) do ch:SetOn(ch.key == key) end
            T.RefreshList()
        end)
        c.key = key
        chips[#chips + 1] = c
        return c
    end
    local row1 = { Chip("all", L["All"]), Chip("fav", L["Watchlist"]), Chip("mine", L["My recipes"]),
        Chip("bags", L["I own"]) }
    local row2 = { Chip("up", L["Rising"]), Chip("down", L["Falling"]) }
    UI.RowLayout(panel, row1, 10, -44, 6)
    local x = UI.RowLayout(panel, row2, 10, -70, 6)
    for _, c in ipairs(chips) do c:SetOn(c.key == state.filter) end

    local clsOptions = { { "all", L["All categories"] } }
    for _, c in ipairs(CLASSES) do clsOptions[#clsOptions + 1] = { c, ClassName(c) } end
    clsOptions[#clsOptions + 1] = { "other", L["Other"] }
    local cls = UI.Dropdown(panel, LEFT_W - x - 10, clsOptions, function(v)
        state.cls = v
        T.RefreshList()
    end)
    cls:SetHeight(20)
    cls:SetPoint("TOPLEFT", x, -70)
    cls:SetValue("all")

    local sortOptions = {
        { "cap", L["Sort: market value"] }, { "ch1", L["Sort: 24h change"] }, { "ch7", L["Sort: 7d change"] },
        { "price", L["Sort: price"] }, { "qty", L["Sort: listed"] }, { "name", L["Sort: name"] },
    }
    local sortDD = UI.Dropdown(panel, 170, sortOptions, function(v)
        state.sort = v
        state.desc = v ~= "name"
        T.header:SetSort(v, state.desc)
        T.RefreshList()
    end)
    sortDD:SetHeight(20)
    sortDD:SetPoint("TOPLEFT", 10, -96)
    sortDD:SetValue(state.sort)
    T.sortDD = sortDD
    countText = UI.Text(panel, 11, "dim", "RIGHT")
    countText:SetPoint("TOPRIGHT", -12, -100)

    local cols = {
        { key = "name", title = L["Item"], width = "fill", sort = "name", make = NameCell, cellHeight = 24 },
        { key = "price", title = L["Price"], width = 70, justify = "RIGHT", sort = "price" },
        { key = "ch1", title = L["24h"], width = 52, justify = "RIGHT", sort = "ch1" },
        { key = "spark", title = L["7d"], width = 40, justify = "RIGHT", sort = "ch7", make = SparkCell, cellHeight = 16 },
    }
    T.header = UI.Header(panel, cols, function(key)
        if state.sort == key then
            state.desc = not state.desc
        else
            state.sort, state.desc = key, key ~= "name"
        end
        T.header:SetSort(state.sort, state.desc)
        T.sortDD:SetValue(state.sort)
        T.RefreshList()
    end)
    T.header:SetPoint("TOPLEFT", 1, -124)
    T.header:SetPoint("TOPRIGHT", -1, -124)
    T.header:SetSort(state.sort, state.desc)

    list = UI.List(panel, {
        rowHeight = 26,
        cols = cols,
        update = function(row, r)
            local cell = row.cells.name
            cell.icon:SetItem(r.id)
            local watched = FT.db.watch[r.id] ~= nil
            cell.star:SetText(watched and "*" or "")
            cell.text:ClearAllPoints()
            cell.text:SetPoint("LEFT", cell.icon, "RIGHT", watched and 14 or 6, 0)
            cell.text:SetPoint("RIGHT", cell, "RIGHT", 0, 0)
            cell.text:SetText(FT.ItemText(r.id))
            row.cells.price:SetText(FT.Money(r.price, "short"))
            row.cells.ch1:SetText(FT.Pct(r.ch1))
            local color = (r.ch7 and r.ch7 < 0) and "down" or ((r.ch7 and r.ch7 > 0) and "up" or "muted")
            row.cells.spark:SetValues(r.spark, color)
        end,
        isSelected = function(r) return r.id == state.selected end,
        onClick = function(r, button)
            if UI.ItemClick(r.id) then return end
            if button == "RightButton" then
                FT.Market.ToggleWatch(r.id)
                return
            end
            T.Select(r.id)
        end,
        onEnter = function(row, r)
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            if GameTooltip.SetItemByID then GameTooltip:SetItemByID(r.id) end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Click: chart || Right-click: watchlist || Shift-click: link"], 0.52, 0.56, 0.61)
            GameTooltip:Show()
        end,
    })
    list:SetPoint("TOPLEFT", T.header, "BOTTOMLEFT", 0, -2)
    list:SetPoint("BOTTOMRIGHT", -1, 4)
    return panel
end

---------------------------------------------------------------------------
-- Overview (no item chosen)
---------------------------------------------------------------------------
local function MoverList(parent, title)
    local box = UI.Panel(parent, "bg1", "line")
    box.title = UI.Text(box, 12, "text")
    box.title:SetPoint("TOPLEFT", 12, -10)
    box.title:SetText(title)
    local cols = {
        { key = "name", title = "", width = "fill", make = NameCell, cellHeight = 24 },
        { key = "price", title = "", width = 74, justify = "RIGHT" },
        { key = "ch", title = "", width = 60, justify = "RIGHT" },
    }
    box.list = UI.List(box, {
        rowHeight = 24, cols = cols,
        update = function(row, r)
            local cell = row.cells.name
            cell.icon:SetItem(r.id)
            cell.star:SetText("")
            cell.text:SetText(FT.ItemText(r.id))
            row.cells.price:SetText(FT.Money(r.price, "short"))
            row.cells.ch:SetText(FT.Pct(r.ch1))
        end,
        onClick = function(r) if not UI.ItemClick(r.id) then T.Select(r.id) end end,
        onEnter = function(row, r) UI.TipItem(row, r.id) end,
    })
    box.list:SetPoint("TOPLEFT", 1, -32)
    box.list:SetPoint("BOTTOMRIGHT", -1, 4)
    return box
end

local function BuildOverview(parent)
    local v = CreateFrame("Frame", nil, parent)
    v:SetAllPoints()
    v.title = UI.Text(v, 18, "text")
    v.title:SetPoint("TOPLEFT", 4, -6)
    v.title:SetText(L["Market overview"])
    v.hint = UI.Text(v, 11, "dim")
    v.hint:SetPoint("LEFT", v.title, "RIGHT", 12, -1)
    v.hint:SetText(L["Pick an item on the left to see its chart"])

    v.cards = {}
    local titles = { L["Items on the market"], L["Listed value"], L["Market mood"], L["Last scan"] }
    for i, t in ipairs(titles) do
        local c = UI.Stat(v, t)
        c:SetHeight(64)
        v.cards[i] = c
    end
    v.moodBar = CreateFrame("Frame", nil, v.cards[3])
    v.moodBar:SetHeight(3)
    v.moodBar:SetPoint("BOTTOMLEFT", 10, 6)
    v.moodBar:SetPoint("BOTTOMRIGHT", -10, 6)
    UI.Fill(v.moodBar, "bg3")
    v.moodFill = UI.Tex(v.moodBar, "ARTWORK", "up", 1)
    v.moodFill:SetPoint("TOPLEFT")
    v.moodFill:SetPoint("BOTTOMLEFT")

    v.chartTitle = UI.Text(v, 12, "text")
    v.chartTitle:SetText(L["Value listed on the auction house, by scan"])
    v.chart = UI.Chart(v)
    v.gainers = MoverList(v, L["Top gainers 24h"])
    v.losers = MoverList(v, L["Top losers 24h"])

    UI.OnSize(v, function(self, w, h)
        local cw = (w - 3 * 8) / 4
        for i, c in ipairs(self.cards) do
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", (i - 1) * (cw + 8), -34)
            c:SetWidth(cw)
        end
        self.chartTitle:ClearAllPoints()
        self.chartTitle:SetPoint("TOPLEFT", 4, -110)
        self.chart:ClearAllPoints()
        self.chart:SetPoint("TOPLEFT", 0, -128)
        self.chart:SetPoint("TOPRIGHT", 0, -128)
        local listsH = math.max(180, math.floor(h * 0.36))
        self.chart:SetPoint("BOTTOM", 0, listsH + 8)
        local half = (w - 8) / 2
        self.gainers:ClearAllPoints()
        self.gainers:SetPoint("BOTTOMLEFT", 0, 0)
        self.gainers:SetSize(half, listsH)
        self.losers:ClearAllPoints()
        self.losers:SetPoint("BOTTOMRIGHT", 0, 0)
        self.losers:SetSize(half, listsH)
    end)
    return v
end

function T.ShowOverview()
    if not overview then return end
    itemView:Hide()
    overview:Show()
    book:SetItem(nil)
    local rows = FT.Market.Rows()
    overview.cards[1]:Set(rows and FT.Num(#rows) or "—", rows and L["seen in scans"] or L["no data"])
    local scans = FT.R().scans
    local lastScan = scans[#scans]
    if lastScan then
        local prev = scans[#scans - 1]
        local ch = prev and prev.value and prev.value > 0 and (lastScan.value / prev.value - 1) or nil
        overview.cards[2]:Set(FT.Money(lastScan.value, "short"), string.format(L["%s auctions"], FT.Num(lastScan.auctions))
            .. "  " .. FT.Pct(ch))
    else
        overview.cards[2]:Set("—", L["after a full scan"])
    end
    local mood, counted = FT.Market.Mood()
    local moodText, moodColor = FT.Market.MoodText(mood)
    overview.cards[3]:Set(mood and (FT.C(moodColor, mood) .. "  " .. FT.C(moodColor, moodText)) or "—",
        mood and string.format(L["%d%% of %d liquid items rose this week"], mood, counted) or L["needs a few days of prices"])
    if mood then
        overview.moodFill:Show()
        overview.moodFill:SetWidth(math.max(1, overview.moodBar:GetWidth() * mood / 100))
        UI.SetTexColor(overview.moodFill, moodColor, 1)
    else
        overview.moodFill:Hide()
    end
    local last = FT.Hist.LastScan()
    overview.cards[4]:Set(last and FT.Ago(last) or "—", last and date("%d.%m %H:%M", last) or L["press Full scan at the auction house"])

    local points = {}
    for _, s in ipairs(scans) do
        if s.value and s.value > 0 then points[#points + 1] = { t = s.t, value = s.value } end
    end
    overview.chart:SetData({
        candles = UI.LineCandles(points), mode = "line", hourly = true, lineColor = "accent", tagColor = "accent",
        fmt = function(v) return FT.Thousands(v / 10000) .. FT.COIN.gold end,
        emptyTitle = L["No full scans yet"],
        emptyBody = L["Each full scan (yours or Auctionator's) adds a point: the total buyout of everything listed."],
    })
    overview.gainers.list:SetItems(FT.Market.Movers(20, "ch1", true))
    overview.losers.list:SetItems(FT.Market.Movers(20, "ch1", false))
end

---------------------------------------------------------------------------
-- One item
---------------------------------------------------------------------------
local function StatPair(parent, label)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(100, 34)
    f.label = UI.Text(f, 10, "dim")
    f.label:SetPoint("TOPLEFT", 0, -2)
    f.label:SetText(label)
    f.value = UI.Text(f, 12, "text")
    f.value:SetPoint("TOPLEFT", 0, -17)
    return f
end

local function Card(parent, title)
    local c = UI.Panel(parent, "bg1", "line")
    c.title = UI.Text(c, 11, "muted")
    c.title:SetPoint("TOPLEFT", 10, -8)
    c.title:SetText(title)
    return c
end

local function BuildItemView(parent)
    local v = CreateFrame("Frame", nil, parent)
    v:SetAllPoints()

    -- head: icon, name, price, change
    v.icon = UI.Icon(v, 38)
    v.icon:SetPoint("TOPLEFT", 2, -4)
    v.icon:EnableMouse(true)
    v.icon:SetScript("OnEnter", function(self) UI.TipItem(self, state.selected) end)
    v.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    v.name = UI.Text(v, 16, "text")
    v.name:SetPoint("TOPLEFT", v.icon, "TOPRIGHT", 10, -1)
    v.sub = UI.Text(v, 11, "dim")
    v.sub:SetPoint("TOPLEFT", v.name, "BOTTOMLEFT", 0, -5)
    v.back = UI.Button(v, "×", 24, 24, "ghost", function() T.ClearSelection() end)
    v.back.label:SetFont(UI.FONT, 16, "")
    v.back:SetPoint("TOPRIGHT", 0, -2)
    v.back:SetTip(L["Back to the market overview"])
    v.change = UI.Text(v, 14, "text", "RIGHT")
    v.change:SetPoint("TOPRIGHT", -30, -6)
    v.price = UI.Text(v, 22, "text", "RIGHT")
    v.price:SetPoint("RIGHT", v.change, "LEFT", -12, -1)
    v.priceAge = UI.Text(v, 10, "dim", "RIGHT")
    v.priceAge:SetPoint("TOPRIGHT", -30, -28)

    -- stats strip
    v.strip = UI.Panel(v, "bg1", "line")
    v.strip:SetPoint("TOPLEFT", 0, -50)
    v.strip:SetPoint("TOPRIGHT", 0, -50)
    v.strip:SetHeight(42)
    local pairsDef = {
        { "hi7", L["7d high"] }, { "lo7", L["7d low"] }, { "avg", L["Average"] }, { "hi30", L["30d high"] },
        { "lo30", L["30d low"] }, { "listed", L["Listed"] }, { "auctions", L["Auctions"] }, { "sellers", L["Sellers"] },
    }
    v.pairs = {}
    for i, d in ipairs(pairsDef) do
        local p = StatPair(v.strip, d[2])
        p.key = d[1]
        v.pairs[i] = p
    end
    UI.OnSize(v.strip, function(self, w)
        local cw = (w - 20) / #v.pairs
        for i, p in ipairs(v.pairs) do
            p:ClearAllPoints()
            p:SetPoint("LEFT", 10 + (i - 1) * cw, 0)
            p:SetWidth(cw - 6)
        end
    end)

    -- toolbar
    v.tf = UI.Segmented(v, { { "1H", L["1H"] }, { "4H", L["4H"] }, { "1D", L["1D"] }, { "1W", L["1W"] } }, function(tf)
        FT.S.chartTF = tf
        T.DrawChart()
    end)
    v.tf:SetPoint("TOPLEFT", 0, -100)
    v.ma = UI.Check(v, "MA", function(on)
        FT.S.showMA = on
        T.DrawChart(true)
    end)
    v.ma:SetPoint("LEFT", v.tf, "RIGHT", 16, 0)
    v.ma:SetTip(L["Moving averages"], L["MA7 and MA25: the average close of the last 7 and 25 candles."])

    v.search = UI.Button(v, L["Search on AH"], 10, 22, "default", function()
        if state.selected then FT.SearchItems({ state.selected }) end
    end)
    v.search:FitText(20)
    v.search:SetPoint("TOPRIGHT", 0, -100)
    v.watch = UI.Button(v, "", 10, 22, "default", function()
        FT.Market.ToggleWatch(state.selected)
        T.UpdateWatchButton()
    end)
    v.watch:SetPoint("RIGHT", v.search, "LEFT", -6, 0)

    -- charts: the price on top, the profitability under it (zero in the middle)
    v.chart = UI.Chart(v)
    v.chart:SetPoint("TOPLEFT", 0, -128)
    v.chart:SetPoint("TOPRIGHT", 0, -128)
    UI.Border(v.chart, "line")
    v.pchart = UI.Chart(v)
    v.pchart:SetPoint("TOPLEFT", v.chart, "BOTTOMLEFT", 0, -6)
    v.pchart:SetPoint("BOTTOMRIGHT", 0, 118)
    UI.Border(v.pchart, "line")

    -- bottom cards
    v.ind = Card(v, L["Indicators"])
    v.sig = Card(v, L["Signal"])
    v.alert = Card(v, L["Price alert"])
    for _, c in ipairs({ v.ind, v.sig, v.alert }) do c:SetHeight(110) end
    UI.OnSize(v, function(self, w, h)
        self.chart:SetHeight(math.max(80, math.floor((h - 128 - 118 - 6) * 0.56)))
        local cw = (w - 16) / 3
        self.ind:ClearAllPoints()
        self.ind:SetPoint("BOTTOMLEFT", 0, 0)
        self.ind:SetWidth(cw)
        self.sig:ClearAllPoints()
        self.sig:SetPoint("BOTTOMLEFT", cw + 8, 0)
        self.sig:SetWidth(cw)
        self.alert:ClearAllPoints()
        self.alert:SetPoint("BOTTOMLEFT", 2 * (cw + 8), 0)
        self.alert:SetWidth(cw)
    end)

    -- indicators
    local function IndLine(y, label)
        local l = UI.Text(v.ind, 11, "muted")
        l:SetPoint("TOPLEFT", 10, y)
        l:SetText(label)
        local r = UI.Text(v.ind, 12, "text", "RIGHT")
        r:SetPoint("TOPRIGHT", -10, y)
        return r
    end
    v.rsi = IndLine(-28, "RSI (14)")
    v.rsiBar = CreateFrame("Frame", nil, v.ind)
    v.rsiBar:SetHeight(3)
    v.rsiBar:SetPoint("TOPLEFT", 10, -44)
    v.rsiBar:SetPoint("TOPRIGHT", -10, -44)
    UI.Fill(v.rsiBar, "bg3")
    v.rsiZoneL = UI.Tex(v.rsiBar, "ARTWORK", "up", 0.35)
    v.rsiZoneL:SetPoint("TOPLEFT")
    v.rsiZoneL:SetPoint("BOTTOMLEFT")
    v.rsiZoneH = UI.Tex(v.rsiBar, "ARTWORK", "down", 0.35)
    v.rsiZoneH:SetPoint("TOPRIGHT")
    v.rsiZoneH:SetPoint("BOTTOMRIGHT")
    v.rsiMark = UI.Tex(v.rsiBar, "OVERLAY", "text", 1)
    v.rsiMark:SetSize(3, 9)
    v.dev = IndLine(-54, L["vs average"])
    v.vol = IndLine(-72, L["Daily volatility"])
    v.liq = IndLine(-90, L["Liquidity"])

    -- signal: what to do with it if you sell, if you buy
    local function SigRow(y, label)
        local l = UI.Text(v.sig, 11, "muted")
        l:SetPoint("TOPLEFT", 10, y)
        l:SetText(label)
        local b = UI.Badge(v.sig, 84, 17)
        b:SetPoint("TOPRIGHT", -10, y + 2)
        local r = UI.Text(v.sig, 11, "dim")
        r:SetPoint("TOPLEFT", 10, y - 17)
        r:SetPoint("RIGHT", v.sig, "RIGHT", -10, 0)
        return b, r
    end
    v.sellBadge, v.sellText = SigRow(-28, L["If you sell"])
    v.buyBadge, v.buyText = SigRow(-64, L["If you buy"])
    v.craft = UI.Button(v.sig, L["Recipe"], 10, 18, "ghost", function()
        local rs = FT.Craft.ByOutput(state.selected)
        if rs and rs[1] then FT.OpenRecipe(rs[1].key) end
    end)
    v.craft.label:SetFont(UI.FONT, 11, "")
    v.craft:FitText(16)
    v.craft:SetPoint("TOPRIGHT", -6, -4)

    -- alert
    v.below = UI.Input(v.alert, 80, 22, L["below, e.g. 12g"])
    v.below:SetPoint("TOPLEFT", 10, -28)
    v.above = UI.Input(v.alert, 80, 22, L["above, e.g. 15g50s"])
    v.above:SetPoint("TOPRIGHT", -10, -28)
    v.save = UI.Button(v.alert, L["Save"], 10, 22, "primary", function()
        local id = state.selected
        if not id then return end
        FT.Market.SetAlert(id, "below", FT.ParseMoney(v.below:GetText()))
        FT.Market.SetAlert(id, "above", FT.ParseMoney(v.above:GetText()))
        v.below:ClearFocus()
        v.above:ClearFocus()
        T.UpdateAlert()
        FT.Market.CheckAlerts()
    end)
    v.save:FitText(24)
    v.save:SetPoint("TOPLEFT", 10, -56)
    v.alertText = UI.Text(v.alert, 11, "muted")
    v.alertText:SetPoint("LEFT", v.save, "RIGHT", 10, 0)
    v.alertText:SetPoint("RIGHT", v.alert, "RIGHT", -10, 0)
    v.alertHint = UI.Text(v.alert, 10, "dim")
    v.alertHint:SetPoint("BOTTOMLEFT", 10, 8)
    v.alertHint:SetPoint("RIGHT", v.alert, "RIGHT", -10, 0)
    v.alertHint:SetText(L["Checked after every scan. Empty = no alert."])
    UI.OnSize(v.alert, function(self, w)
        local iw = math.floor((w - 26) / 2)
        v.below:SetWidth(iw)
        v.above:SetWidth(iw)
    end)
    return v
end

function T.UpdateWatchButton()
    local v = itemView
    if not (v and state.selected) then return end
    local on = FT.Market.IsWatched(state.selected)
    v.watch:SetLabel(on and L["In watchlist"] or L["Watch"])
    v.watch:SetActive(on)
    v.watch:FitText(20)
end

function T.UpdateAlert()
    local v = itemView
    local w = FT.db.watch[state.selected]
    local parts = {}
    if w and w.below then parts[#parts + 1] = L["below"] .. " " .. FT.Money(w.below) end
    if w and w.above then parts[#parts + 1] = L["above"] .. " " .. FT.Money(w.above) end
    v.alertText:SetText(#parts > 0 and (L["Alert when"] .. ": " .. table.concat(parts, ", ")) or FT.C("dim", L["No alert set"]))
end

-- money on chart axes: "12s 50c"; profit with its sign: "+1g 20s" / "-35s"
local function MoneyAxis(v) return FT.Money(v, "short") end
local SignedMoney = FT.SignedMoney
local function SignedPct(v) return string.format("%+.0f%%", v * 100) end

-- the profitability line: the profit of one craft (your recipe), else selling now vs the average price
function T.DrawProfit(keepView)
    local v = itemView
    local id = state.selected
    if not (v and id) then return end
    local best, bestProfit
    for _, r in ipairs(FT.Craft.ByOutput(id) or {}) do
        local e = FT.Craft.Eval(r)
        local p = e.profit or -math.huge
        if not best or p > bestProfit then best, bestProfit = r, p end
    end
    if best then
        v.pchart:SetData({
            candles = UI.LineCandles(FT.Craft.History(best, 30), "profit"),
            mode = "line", centerZero = true, fmt = SignedMoney, defaultCount = 30,
            title = L["Profit per craft"],
            emptyTitle = L["No history yet"],
            emptyBody = L["Needs a few days of prices for the item and its materials."],
        }, keepView)
    else
        v.pchart:SetData({
            candles = UI.LineCandles(FT.An.DevSeries(id, 30)),
            mode = "line", centerZero = true, fmt = SignedPct, defaultCount = 30,
            title = string.format(L["Selling now: price vs its %d-day average"], FT.S.avgDays),
            emptyTitle = L["Not enough price history yet"],
            emptyBody = L["Shows once there are a few days of prices."],
        }, keepView)
    end
end

-- draw the charts of the chosen item; keepView: same zoom
function T.DrawChart(keepView)
    local v = itemView
    local id = state.selected
    if not (v and id) then return end
    local tf = FT.S.chartTF
    local candles = FT.Hist.Series(id, tf)
    local overlays = {}
    if FT.S.showMA and #candles >= 7 then
        local closes = {}
        for i, c in ipairs(candles) do closes[i] = c.c end
        overlays[#overlays + 1] = { values = FT.An.SMA(closes, 7), color = "blue", label = "MA7" }
        if #candles >= 25 then
            overlays[#overlays + 1] = { values = FT.An.SMA(closes, 25), color = "purple", label = "MA25" }
        end
    end
    local intraday = (tf == "1H" or tf == "4H")
    local emptyBody
    if intraday then
        emptyBody = L["Hourly prices are recorded for the items you track (recipes, watchlist, what you own, what you open). This item is tracked now: its hourly line starts with the next scan."]
    else
        emptyBody = L["No prices for it yet: scan My items or run a full scan at the auction house."]
    end
    v.chart:SetData({
        candles = candles,
        mode = "line",
        lineColor = "accent",
        tagColor = "accent",
        fmt = MoneyAxis,
        title = L["Price"],
        overlays = overlays,
        hourly = intraday,
        defaultCount = intraday and 72 or 60,
        emptyTitle = L["No price history"],
        emptyBody = emptyBody,
    }, keepView)
    T.DrawProfit(keepView)
end

function T.ShowItem(id, keepView)
    if not itemView then return end
    overview:Hide()
    itemView:Show()
    local v = itemView
    local _, _, icon = FT.Item(id)
    v.icon:SetIcon(icon)
    v.name:SetText(FT.ItemText(id, 40))
    local cls, sub = FT.ItemClass(id)
    local parts = {}
    if cls then
        parts[#parts + 1] = ClassName(cls)
        local subName = GetSubClassInfo and sub and GetSubClassInfo(cls, sub)
        if subName and subName ~= "" and subName ~= parts[1] then parts[#parts + 1] = subName end
    end
    if FT.Hist.Tracked(id) then parts[#parts + 1] = FT.C("accent", L["tracked intraday"]) end
    local rs = FT.Craft.ByOutput(id)
    if rs and rs[1] then parts[#parts + 1] = FT.C("up", L["you can craft it"]) end
    local own = FT.Port.Count(id)
    if own > 0 then parts[#parts + 1] = FT.C("text", string.format(L["you have %s"], FT.Num(own))) end
    v.sub:SetText(table.concat(parts, FT.C("dim", "  ||  ")))
    v.craft:SetShown(rs ~= nil and rs[1] ~= nil)

    local s = FT.An.Stats(id)
    v.price:SetText(s.price and FT.Money(s.price) or "—")
    v.change:SetText(FT.Pct(s.ch1) .. FT.C("dim", " " .. L["24h"]))
    local src = FT.SourceName(s.source)
    v.priceAge:SetText(s.t and (src .. " || " .. FT.Ago(s.t)) or "")

    for _, p in ipairs(v.pairs) do
        local val = s[p.key]
        if p.key == "listed" or p.key == "auctions" or p.key == "sellers" then
            p.value:SetText(val and FT.Num(val) or "—")
        else
            p.value:SetText(val and FT.Money(val, "short") or "—")
        end
    end

    v.tf:SetValue(FT.S.chartTF)
    v.ma:SetChecked(FT.S.showMA)
    T.DrawChart(keepView)

    -- indicators
    if s.rsi then
        local color = (s.rsi >= 70 and "down") or (s.rsi <= 30 and "up") or "text"
        v.rsi:SetText(FT.C(color, string.format("%.0f", s.rsi)))
        local w = v.rsiBar:GetWidth()
        v.rsiZoneL:SetWidth(w * 0.3)
        v.rsiZoneH:SetWidth(w * 0.3)
        v.rsiMark:ClearAllPoints()
        v.rsiMark:SetPoint("CENTER", v.rsiBar, "LEFT", w * s.rsi / 100, 0)
        v.rsiMark:Show()
    else
        v.rsi:SetText(FT.C("dim", "—"))
        v.rsiMark:Hide()
    end
    v.dev:SetText(FT.Pct(s.dev))
    v.vol:SetText(s.vol and string.format("%.1f%%", s.vol * 100) or FT.C("dim", "—"))
    local liq = FT.An.Liquidity(s)
    local liqNames = { high = L["high"], medium = L["medium"], low = L["low"], unknown = L["no data"] }
    local liqColors = { high = "up", medium = "accent", low = "down", unknown = "dim" }
    v.liq:SetText(FT.C(liqColors[liq], liqNames[liq]))

    -- signals
    local sell, sellStrength, sellReason = FT.An.SellSignal(s)
    v.sellBadge:Set(sell, nil, sellStrength)
    v.sellText:SetText(sellReason or "")
    local buy, buyStrength, buyReason = FT.An.BuySignal(s)
    v.buyBadge:Set(buy, nil, buyStrength)
    v.buyText:SetText(buyReason or "")

    -- alert: the boxes are filled when another item is opened, never while you type in them
    if v.alertFor ~= id then
        v.alertFor = id
        local w = FT.db.watch[id]
        v.below:SetValue(w and w.below and FT.MoneyPlain(w.below) or "")
        v.above:SetValue(w and w.above and FT.MoneyPlain(w.above) or "")
    end
    T.UpdateAlert()
    T.UpdateWatchButton()
    book:SetItem(id)
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
function T.Build(p)
    page = p
    BuildList(p)
    local center = CreateFrame("Frame", nil, p)
    center:SetPoint("TOPLEFT", LEFT_W + 18, -8)
    center:SetPoint("BOTTOMRIGHT", -(RIGHT_W + 18), 8)
    overview = BuildOverview(center)
    itemView = BuildItemView(center)
    itemView:Hide()
    book = UI.OrderBook(p)
    book:SetPoint("TOPRIGHT", -8, -8)
    book:SetPoint("BOTTOMRIGHT", -8, 8)
    book:SetWidth(RIGHT_W)
end

function T.Select(id)
    if not id then return end
    if not page then FT.Show("market") end
    state.selected = id
    FT.Hist.Viewed(id)
    if list then list:Refresh() end
    T.ShowItem(id)
end

function T.OnShow()
    FT.Market.EnsureFresh()
    T.Refresh()
end

function T.Refresh()
    T.RefreshList(true)
    if state.selected then
        T.ShowItem(state.selected, true)
    else
        T.ShowOverview()
    end
end

-- Escape-like: back to the overview
function T.ClearSelection()
    state.selected = nil
    if list then list:Refresh() end
    T.ShowOverview()
end
