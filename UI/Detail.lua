-- Wolf: the item charts' data and the small texts the Market page shares (price line, profit line, how old a
-- price is, auctions, sales, risks, the Wowhead button). (v0.52: the item's own window is gone.)
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local D = {}
FT.Detail = D

local W, H = 1000, 620


---------------------------------------------------------------------------
-- Chart data, shared with the Market page
---------------------------------------------------------------------------
local function MoneyAxis(v) return FT.Money(v, "short") end

-- the price line of an item: tf "1H" / "4H" / "1D" / "1W", moving averages when ma is on
-- the price chart's style (Settings and the chart's "Pro chart" box): "simple", one line green when it went up
-- over the period and red when down, nothing else; "pro", candles and the averages
function UI.ProChart()
    -- v0.42: no Pro chart (Simple Wolf): always the one clean line
    do return false end
    return FT.S.chartStyle == "pro"
end

-- the simple chart's range: 7D (points every 4 hours), 30D or 90D (a point a day)
UI.RANGES = { { "7D", L["7D"] }, { "30D", L["30D"] }, { "90D", L["90D"] } }
local RANGE_DAYS = { ["7D"] = 7, ["30D"] = 30, ["90D"] = 90 }

function UI.PriceChartData(id, tf, ma)
    local pro = UI.ProChart()
    if not pro then
        -- the simple line: the range picked, a point a day (every 4 hours over a week, when tracked hourly)
        local range = RANGE_DAYS[FT.S.chartRange or "30D"] and FT.S.chartRange or "30D"
        local days = RANGE_DAYS[range]
        local candles, hourly = nil, false
        if days == 7 then
            candles = FT.Hist.Series(id, "4H")
            hourly = #candles >= 6
        end
        if not hourly then candles = FT.Hist.Series(id, "1D") end
        local keep = hourly and (days * 6) or days
        local from = math.max(1, #candles - keep + 1)
        local shown = {}
        for i = from, #candles do shown[#shown + 1] = candles[i] end
        -- (v0.61) your own buys and sales of it on the line (the deals journal: the auction house's mail)
        local trades = {}
        if FT.Journal and shown[1] then
            for _, e in ipairs(FT.Journal.Events() or {}) do
                if e.id == id and (e.k == "B" or e.k == "S") and e.t >= shown[1].t - 86400 and (e.q or 0) > 0 then
                    trades[#trades + 1] = { t = e.t, unit = e.v / e.q, q = e.q, buy = e.k == "B" }
                end
            end
        end
        return {
            candles = shown, mode = "line", fmt = MoneyAxis, title = L["Price"], overlays = {}, hourly = hourly, trades = trades,
            defaultCount = #shown, emptyTitle = L["No price history"],
            emptyBody = L["No prices for it yet: scan My items or run a full scan at the auction house."],
        }
    end
    local candles = FT.Hist.Series(id, tf)
    local overlays = {}
    ma = ma and pro
    -- the averages show from 3 points on (until there are 7 / 25, of the points there are); MA25 once there
    -- are more than 7, else it would be the same line
    if ma and #candles >= 3 then
        local closes = {}
        for i, c in ipairs(candles) do closes[i] = c.c end
        overlays[#overlays + 1] = { values = FT.An.SMA(closes, 7, true), color = "blue", label = L["MA7"] }
        if #candles > 7 then
            overlays[#overlays + 1] = { values = FT.An.SMA(closes, 25, true), color = "purple", label = L["MA25"] }
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
        candles = candles, mode = pro and "candles" or "line", fmt = MoneyAxis,
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
-- on a chart's top bar, at the right: the item's Wowhead page (was More: the item window, which showed nothing new)
function UI.MoreButton(chart, getID)
    local b = UI.Button(chart, L["Wowhead"], 10, 18, "default", function()
        local id = getID()
        if id then FT.Farm.Wowhead(id) end
    end)
    b.label:SetFont(UI.FONT, UI.Size(11), "")
    b:FitText(14)
    b:SetPoint("TOPRIGHT", -3, -2)
    b:SetFrameLevel(chart:GetFrameLevel() + 14)
    b:SetTip(L["Wowhead"], L["Its page on Wowhead (WoW Forever): a link to copy into your browser."])
    return b
end
UI.WowheadButton = UI.MoreButton

---------------------------------------------------------------------------
-- An item, opened: on the Market page. (v0.52: the item's own window - nothing opened it since v0.42 - is gone,
-- with its order book.)
---------------------------------------------------------------------------
function FT.ShowDetail(id)
    if id then FT.OpenItem(id) end
end
FT.ShowItemWindow = FT.ShowDetail
function D.Items() return nil end
function D.Item() return nil end
function D.Refresh() end
function D.Rescale() end
