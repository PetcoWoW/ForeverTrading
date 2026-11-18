-- ForeverTrading: one item in its own window ("More" on the charts): large price and profit charts, the
-- numbers that matter, its order book and what buying costs. With the auction house open its price and order
-- book stay live (searched again every few seconds).
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local D = {}
FT.Detail = D

local W, H = 1000, 620
local BOOK_W = 250
local win
local state = { id = nil }

local GetClassInfo = (C_Item and C_Item.GetItemClassInfo) or GetItemClassInfo
local GetSubClassInfo = (C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo

---------------------------------------------------------------------------
-- Chart data, shared with the Market page
---------------------------------------------------------------------------
local function MoneyAxis(v) return FT.Money(v, "short") end

-- the price line of an item: tf "1H" / "4H" / "1D" / "1W", moving averages when ma is on
function UI.PriceChartData(id, tf, ma)
    local candles = FT.Hist.Series(id, tf)
    local overlays = {}
    -- the averages show from 3 points on (until there are 7 / 25, of the points there are); MA25 once there
    -- are more than 7, else it would be the same line
    if ma and #candles >= 3 then
        local closes = {}
        for i, c in ipairs(candles) do closes[i] = c.c end
        overlays[#overlays + 1] = { values = FT.An.SMA(closes, 7, true), color = "blue", label = "MA7" }
        if #candles > 7 then
            overlays[#overlays + 1] = { values = FT.An.SMA(closes, 25, true), color = "purple", label = "MA25" }
        end
    end
    local intraday = (tf == "1H" or tf == "4H")
    local emptyBody
    if intraday then
        emptyBody = L["Hourly prices are recorded for the items you track (recipes, watchlist, what you own, what you open). This item is tracked now: its hourly line starts with the next scan."]
    else
        emptyBody = L["No prices for it yet: scan My items or run a full scan at the auction house."]
    end
    return {
        candles = candles, mode = "line", lineColor = "accent", tagColor = "accent", fmt = MoneyAxis,
        title = L["Price"], overlays = overlays, hourly = intraday, defaultCount = intraday and 72 or 60,
        emptyTitle = L["No price history"], emptyBody = emptyBody,
    }
end

-- the profitability line, in money: the profit of one craft (your recipe), else what selling one now brings
-- above or below its average price
function UI.ProfitChartData(id)
    local best = FT.Craft.Best(id)
    if best then
        return {
            candles = UI.LineCandles(FT.Craft.History(best, 30), "profit"),
            mode = "line", centerZero = true, fmt = FT.SignedMoney, defaultCount = 30,
            title = L["Profit per craft"],
            emptyTitle = L["No history yet"],
            emptyBody = L["Needs a few days of prices for the item and its materials."],
        }
    end
    return {
        candles = UI.LineCandles(FT.An.DevSeries(id, 30)),
        mode = "line", centerZero = true, fmt = FT.SignedMoney, defaultCount = 30,
        title = string.format(L["Selling now: price vs its %d-day average"], FT.S.avgDays),
        emptyTitle = L["Not enough price history yet"],
        emptyBody = L["Shows once there are a few days of prices."],
    }
end

-- where the price comes from and how old it is; "live" while the auction house keeps it fresh
function UI.PriceAgeText(id, s)
    if not (s and s.t) then return "" end
    if FT.Scanner.LiveOn(id) then
        return FT.C("up", L["live"]) .. " || " .. FT.Ago(s.t)
    end
    return FT.SourceName(s.source) .. " || " .. FT.Ago(s.t)
end

-- Stackable goods come from the auction house as one row per price, not per auction: "auctions" of them are
-- the prices the order book has. Gear comes auction by auction.
function UI.AuctionsLabel(id)
    return (id and FT.Buy.IsCommodity(id)) and L["Price levels"] or L["Auctions"]
end
function UI.AuctionsText(id, n)
    return string.format((id and FT.Buy.IsCommodity(id)) and L["%d price levels"] or L["%d auctions"], n)
end

-- how much really sells, as estimated from the listings seen go (FT.Sales): "Sells ~4.2 a day (14 h watched)"
function UI.SalesText(s)
    local r = s and s.sales
    if not r then return L["Sells"] .. " " .. FT.C("dim", L["not seen yet"]) end
    return L["Sells"] .. " " .. FT.C(s.slow and "down" or "text", FT.Sales.PerDayText(r))
        .. FT.C("dim", " " .. string.format(L["(%d h watched)"], math.max(1, math.floor(r.hours + 0.5))))
end

-- listed / auctions / sellers of the newest measurement, and how many more (+, red: competition) or fewer
-- (-, green) than at the last check half an hour or more ago
function UI.CountText(s, key)
    local val, d
    if key == "listed" then
        val, d = s.listed, s.sinceQ
    elseif key == "auctions" then
        val, d = s.auctionsNow or s.auctions, s.auctionsNow and s.sinceN
    else
        val, d = s.sellersNow or s.sellers, s.sellersNow and s.sinceS
    end
    if not val then return "—" end
    local text = FT.Num(val)
    if d and d ~= 0 then
        text = text .. " " .. FT.C(d > 0 and "down" or "up", (d > 0 and "+" or "-") .. FT.Num(math.abs(d)))
    end
    return text
end

-- what to know first, before the item's name line: a price jump or a fast fall, a fall since the last check,
-- a flooded market, more sellers than usual
function UI.RiskHead(s)
    local head = {}
    if s.spike then
        head[#head + 1] = FT.C("accent", string.format(L["price jump (buyout?): fair ~%s"], FT.Money(s.fair, "short")))
    elseif s.falling then
        head[#head + 1] = FT.C("down", string.format(L["falling fast: %s, fair ~%s"], FT.Pct(s.price / s.fair - 1, true), FT.Money(s.fair, "short")))
    end
    for _, note in ipairs(FT.An.RiskNotes(s)) do head[#head + 1] = FT.C("down", note) end
    return head
end

-- "More" in the corner of a chart: the item in its own window
function UI.MoreButton(chart, getID)
    local b = UI.Button(chart, L["More"], 10, 18, "default", function()
        local id = getID()
        if id then FT.ShowDetail(id) end
    end)
    b.label:SetFont(UI.FONT, 11, "")
    b:FitText(14)
    b:SetPoint("TOPRIGHT", -3, -2)
    b:SetFrameLevel(chart:GetFrameLevel() + 14)
    b:SetTip(L["More"], L["The item in its own window: large charts and its order book. With the auction house open they stay live."])
    return b
end

---------------------------------------------------------------------------
-- The window
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

local function SavePos()
    local point, _, relPoint, x, y = win:GetPoint(1)
    FT.db.detailFrame = { point = point, relPoint = relPoint, x = x, y = y }
end

local function Build()
    win = CreateFrame("Frame", "ForeverTradingDetail", UIParent, UI.EdgeTemplate())
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:SetScale(FT.S.scale or 1)
    win:SetSize(W, H)
    local p = FT.db.detailFrame
    if p and p.point then
        win:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
    else
        win:SetPoint("CENTER", UIParent, "CENTER", 30, -20)
    end
    UI.Fill(win, "bg0")
    if not UI.ClassicEdge(win, "line", { edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 } }) then
        UI.Border(win, "line")
    end
    table.insert(UISpecialFrames, "ForeverTradingDetail")

    -- header: the item, its price, buttons; dragging it moves the window
    local header = CreateFrame("Frame", nil, win)
    header:SetPoint("TOPLEFT", UI.INSET, -UI.INSET)
    header:SetPoint("TOPRIGHT", -UI.INSET, -UI.INSET)
    header:SetHeight(58)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() win:StartMoving() end)
    header:SetScript("OnDragStop", function()
        win:StopMovingOrSizing()
        SavePos()
    end)
    local hl = UI.HLine(header, "line")
    hl:SetPoint("BOTTOMLEFT")
    hl:SetPoint("BOTTOMRIGHT")

    win.icon = UI.Icon(header, 38)
    win.icon:SetPoint("LEFT", 12, 0)
    win.icon:EnableMouse(true)
    win.icon:SetScript("OnEnter", function(self) if state.id then UI.TipItem(self, state.id) end end)
    win.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    win.name = UI.Text(header, 16, "text")
    win.name:SetPoint("TOPLEFT", win.icon, "TOPRIGHT", 10, -1)
    win.sub = UI.Text(header, 11, "dim")
    win.sub:SetPoint("TOPLEFT", win.name, "BOTTOMLEFT", 0, -6)

    local close = UI.Button(header, "×", 30, 30, "ghost", function() win:Hide() end)
    close.label:SetFont(UI.FONT, 18, "")
    close:SetPoint("RIGHT", -8, 0)
    win.market = UI.Button(header, L["Open in Market"], 10, 24, "default", function()
        if state.id then FT.OpenItem(state.id) end
    end)
    win.market:FitText(20)
    win.market:SetPoint("RIGHT", close, "LEFT", -10, 0)
    win.watch = UI.Button(header, L["Watch"], 10, 24, "default", function()
        if state.id then
            FT.Market.ToggleWatch(state.id)
            D.UpdateWatch()
        end
    end)
    win.watch:SetPoint("RIGHT", win.market, "LEFT", -6, 0)
    win.search = UI.Button(header, L["Search on AH"], 10, 24, "primary", function()
        if state.id then FT.SearchItems({ state.id }) end
    end)
    win.search:FitText(20)
    win.search:SetPoint("RIGHT", win.watch, "LEFT", -6, 0)

    win.change = UI.Text(header, 14, "text", "RIGHT")
    win.change:SetPoint("RIGHT", win.search, "LEFT", -20, 8)
    win.price = UI.Text(header, 22, "text", "RIGHT")
    win.price:SetPoint("RIGHT", win.change, "LEFT", -12, -1)
    win.priceAge = UI.Text(header, 10, "dim", "RIGHT")
    win.priceAge:SetPoint("TOPRIGHT", win.change, "BOTTOMRIGHT", 0, -7)
    -- the countdown to its next live search
    win.ring = UI.LiveRingFor(header, 9, function() return state.id end)
    win.ring:SetPoint("RIGHT", win.priceAge, "LEFT", -5, 0)

    -- body: charts on the left, the order book on the right
    local body = CreateFrame("Frame", nil, win)
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 8, -8)
    body:SetPoint("BOTTOMRIGHT", -UI.INSET - 8, UI.INSET + 8)

    win.book = UI.OrderBook(body)
    win.book:SetPoint("TOPRIGHT", 0, 0)
    win.book:SetPoint("BOTTOMRIGHT", 0, 0)
    win.book:SetWidth(BOOK_W)
    -- under it the materials of one craft (a material clicked opens in this window)
    win.mats = UI.Materials(body, function(id) FT.ShowDetail(id) end)
    win.mats:SetPoint("BOTTOMRIGHT", 0, 0)
    win.mats:SetWidth(BOOK_W)
    win.mats:Hide()

    local left = CreateFrame("Frame", nil, body)
    left:SetPoint("TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMRIGHT", -(BOOK_W + 10), 0)

    win.strip = UI.Panel(left, "bg1", "line")
    win.strip:SetPoint("TOPLEFT", 0, 0)
    win.strip:SetPoint("TOPRIGHT", 0, 0)
    win.strip:SetHeight(42)
    local defs = {
        { "hi7", L["7d high"] }, { "lo7", L["7d low"] }, { "avg", L["Average"] }, { "hi30", L["30d high"] },
        { "lo30", L["30d low"] }, { "listed", L["Listed"] }, { "auctions", L["Auctions"] }, { "sellers", L["Sellers"] },
    }
    win.pairs = {}
    for i, d in ipairs(defs) do
        local pr = StatPair(win.strip, d[2])
        pr.key = d[1]
        win.pairs[i] = pr
    end
    UI.OnSize(win.strip, function(self, w)
        local cw = (w - 20) / #win.pairs
        for i, pr in ipairs(win.pairs) do
            pr:ClearAllPoints()
            pr:SetPoint("LEFT", 10 + (i - 1) * cw, 0)
            pr:SetWidth(cw - 6)
        end
    end)

    win.tf = UI.Segmented(left, { { "1H", L["1H"] }, { "4H", L["4H"] }, { "1D", L["1D"] }, { "1W", L["1W"] } }, function(tf)
        FT.S.chartTF = tf
        D.Draw()
    end)
    win.tf:SetPoint("TOPLEFT", 0, -50)
    win.ma = UI.Check(left, L["Averages"], function(on)
        FT.S.showMA = on
        D.Draw(true)
    end)
    win.ma:SetPoint("LEFT", win.tf, "RIGHT", 16, 0)
    win.ma:SetTip(L["Moving averages"], L["Two smoothed lines on the price chart: MA7 and MA25, the average price of the last 7 and 25 points (days on 1D). Until there are that many, of the points there are; MA25 shows once there are more than 7."])
    -- indicators in one line on the right of the toolbar
    win.ind = UI.Text(left, 11, "muted", "RIGHT")
    win.ind:SetPoint("RIGHT", left, "TOPRIGHT", -2, -61)
    win.ind:SetPoint("LEFT", win.ma, "RIGHT", 60, 0)

    win.chart = UI.Chart(left)
    win.chart:SetPoint("TOPLEFT", 0, -78)
    win.chart:SetPoint("TOPRIGHT", 0, -78)
    UI.Border(win.chart, "line")
    win.pchart = UI.Chart(left)
    win.pchart:SetPoint("TOPLEFT", win.chart, "BOTTOMLEFT", 0, -6)
    win.pchart:SetPoint("BOTTOMRIGHT", 0, 0)
    UI.Border(win.pchart, "line")
    UI.OnSize(left, function(self, w, h)
        win.chart:SetHeight(math.max(120, math.floor((h - 78 - 6) * 0.6)))
    end)

    win:SetScript("OnHide", function() win:StopMovingOrSizing() end)
    win:Hide()
end

function D.Item()
    return win and win:IsShown() and state.id or nil
end

function D.UpdateWatch()
    if not (win and state.id) then return end
    local on = FT.Market.IsWatched(state.id)
    win.watch:SetLabel(on and L["In watchlist"] or L["Watch"])
    win.watch:SetActive(on)
    win.watch:FitText(20)
    D.FitHeader()
end

-- the name and the line under it stop before the price block and the buttons (cut with "...")
function D.FitHeader()
    local hw = win.name:GetParent():GetWidth()
    if not hw or hw <= 0 then return end
    local changeRight = hw - 48 - win.market:GetWidth() - 6 - win.watch:GetWidth() - 6 - win.search:GetWidth() - 20
    local left = 12 + 38 + 10
    win.name:SetWidth(math.max(60, changeRight - win.change:GetStringWidth() - 12 - win.price:GetStringWidth() - 14 - left))
    win.sub:SetWidth(math.max(60, changeRight - win.priceAge:GetStringWidth() - 5 - 9 - 14 - left))
end

function D.Draw(keepView)
    if not (win and state.id) then return end
    win.chart:SetData(UI.PriceChartData(state.id, FT.S.chartTF, FT.S.showMA), keepView)
    win.pchart:SetData(UI.ProfitChartData(state.id), keepView)
end

local LIQ_NAMES = { high = "high", medium = "medium", low = "low", unknown = "no data" }
local LIQ_COLORS = { high = "up", medium = "accent", low = "down", unknown = "dim" }

function D.Refresh(keepView)
    if not D.Item() then return end
    local id = state.id
    win.icon:SetItem(id)
    win.name:SetText(FT.ItemText(id, 34))
    local parts = {}
    local cls, sub = FT.ItemClass(id)
    if cls then
        local name = GetClassInfo and GetClassInfo(cls)
        if name and name ~= "" then parts[#parts + 1] = name end
        local subName = GetSubClassInfo and sub and GetSubClassInfo(cls, sub)
        if subName and subName ~= "" and subName ~= name then parts[#parts + 1] = subName end
    end
    local rs = FT.Craft.ByOutput(id)
    if rs and rs[1] then parts[#parts + 1] = FT.C("up", L["you can craft it"]) end
    local own = FT.Port.Count(id)
    if own > 0 then parts[#parts + 1] = FT.C("text", string.format(L["you have %s"], FT.Num(own))) end
    local s = FT.An.Stats(id)
    local head = UI.RiskHead(s)
    for i = #head, 1, -1 do table.insert(parts, 1, head[i]) end
    win.sub:SetText(table.concat(parts, FT.C("dim", "  ||  ")))

    win.price:SetText(s.price and FT.Money(s.price) or "—")
    win.change:SetText(FT.Pct(s.ch1) .. FT.C("dim", " " .. L["24h"]))
    win.priceAge:SetText(UI.PriceAgeText(id, s))
    for _, pr in ipairs(win.pairs) do
        local val = s[pr.key]
        if pr.key == "listed" or pr.key == "auctions" or pr.key == "sellers" then
            pr.value:SetText(UI.CountText(s, pr.key))
            if pr.key == "auctions" then pr.label:SetText(UI.AuctionsLabel(id)) end
        else
            pr.value:SetText(val and FT.Money(val, "short") or "—")
        end
    end

    local ind = {}
    if s.rsi then
        local color = (s.rsi >= 70 and "down") or (s.rsi <= 30 and "up") or "text"
        ind[#ind + 1] = "RSI " .. FT.C(color, string.format("%.0f", s.rsi))
    end
    if s.dev then ind[#ind + 1] = L["vs average"] .. " " .. FT.Pct(s.dev) end
    if s.vol then ind[#ind + 1] = L["Daily volatility"] .. " " .. FT.C("text", string.format("%.1f%%", s.vol * 100)) end
    local liq = FT.An.Liquidity(s)
    ind[#ind + 1] = L["Liquidity"] .. " " .. FT.C(LIQ_COLORS[liq], L[LIQ_NAMES[liq]])
    ind[#ind + 1] = UI.SalesText(s)
    win.ind:SetText(table.concat(ind, FT.C("dim", "   ||   ")))

    win.tf:SetValue(FT.S.chartTF)
    win.ma:SetChecked(FT.S.showMA)
    D.Draw(keepView)
    win.book:SetItem(id)
    local show, h = win.mats:SetItem(id)
    win.mats:SetShown(show)
    win.book:ClearAllPoints()
    win.book:SetPoint("TOPRIGHT", 0, 0)
    win.book:SetWidth(BOOK_W)
    if show then
        win.mats:SetHeight(h)
        win.book:SetPoint("BOTTOMRIGHT", win.mats, "TOPRIGHT", 0, 8)
    else
        win.book:SetPoint("BOTTOMRIGHT", 0, 0)
    end
    D.UpdateWatch()
end

-- kept live: the item, and the materials of one craft of it
function D.Items()
    local id = D.Item()
    if not id then return nil end
    local out = { id }
    if win.mats:IsShown() and win.mats.r then
        for _, m in ipairs(FT.Craft.MarketMaterials(win.mats.r)) do out[#out + 1] = m end
    end
    return out
end

-- open an item in its own window
function FT.ShowDetail(id)
    if not id then return end
    if not win then Build() end
    local same = state.id == id and win:IsShown()
    state.id = id
    FT.Hist.Viewed(id)
    win:Show()
    win:Raise()
    D.Refresh(same)
    -- with the auction house open its search goes out now
    FT.Scanner.LiveNow(id)
end

-- Settings: the window scale changed
function D.Rescale(scale)
    if win then win:SetScale(scale or 1) end
end

FT.On("FT_LIVE_UPDATED", function(id)
    if id and D.Item() and (id == state.id or (win.mats:IsShown() and win.mats:Has(id))) then D.Refresh(true) end
end)
FT.On("FT_AH_CHANGED", function() if D.Item() then D.Refresh(true) end end)
local function Later()
    if D.Item() then FT.Debounce("detailRefresh", 0.8, function() D.Refresh(true) end) end
end
FT.On("FT_PRICES_CHANGED", Later)
FT.On("FT_SCAN_DONE", Later)
FT.On("FT_ITEMS_LOADED", Later)
FT.On("FT_WATCH_CHANGED", function() if D.Item() then D.UpdateWatch() end end)
