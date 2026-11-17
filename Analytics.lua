-- ForeverTrading: indicators and signals.
local ADDON, FT = ...
local L = FT.L

local An = {}
FT.An = An

---------------------------------------------------------------------------
-- Indicators over a list of numbers (oldest first)
---------------------------------------------------------------------------
-- partial: the first values (fewer than n so far) get the average of what there is
function An.SMA(values, n, partial)
    local out, sum = {}, 0
    for i = 1, #values do
        sum = sum + values[i]
        if i > n then sum = sum - values[i - n] end
        if i >= n then
            out[i] = sum / n
        elseif partial then
            out[i] = sum / i
        end
    end
    return out
end

function An.EMA(values, n)
    local out, k, prev = {}, 2 / (n + 1), nil
    for i = 1, #values do
        if prev == nil then
            prev = values[i]
        else
            prev = values[i] * k + prev * (1 - k)
        end
        if i >= math.min(n, #values) then out[i] = prev end
    end
    return out
end

-- Wilder's RSI of the last value (nil with too little data)
function An.RSI(values, n)
    n = n or 14
    if #values < 3 then return nil end
    n = math.min(n, #values - 1)
    local gain, loss = 0, 0
    for i = 2, n + 1 do
        local d = values[i] - values[i - 1]
        if d > 0 then gain = gain + d else loss = loss - d end
    end
    gain, loss = gain / n, loss / n
    for i = n + 2, #values do
        local d = values[i] - values[i - 1]
        gain = (gain * (n - 1) + math.max(d, 0)) / n
        loss = (loss * (n - 1) + math.max(-d, 0)) / n
    end
    if loss == 0 then return gain == 0 and 50 or 100 end
    local rs = gain / loss
    return 100 - 100 / (1 + rs)
end

function An.Mean(values, from, to)
    from, to = from or 1, to or #values
    local sum, n = 0, 0
    for i = math.max(1, from), math.min(#values, to) do
        sum, n = sum + values[i], n + 1
    end
    return n > 0 and sum / n or nil
end

-- standard deviation of day-to-day changes
function An.Volatility(values)
    if #values < 3 then return nil end
    local r = {}
    for i = 2, #values do
        if values[i - 1] > 0 then r[#r + 1] = values[i] / values[i - 1] - 1 end
    end
    local m = An.Mean(r)
    if not m then return nil end
    local s = 0
    for _, x in ipairs(r) do s = s + (x - m) ^ 2 end
    return math.sqrt(s / #r)
end

---------------------------------------------------------------------------
-- Everything about one item, cached until prices change
---------------------------------------------------------------------------
local cache = {}
FT.On("FT_PRICES_CHANGED", function() wipe(cache) end)
FT.On("FT_LIVE_UPDATED", function(itemID) if itemID then cache[itemID] = nil end end)
FT.On("FT_SCAN_DONE", function() wipe(cache) end)
FT.On("FT_SETTINGS_CHANGED", function() wipe(cache) end)

local function CloseAtOrBefore(daily, day)
    for i = #daily, 1, -1 do
        if daily[i].day <= day then return daily[i].c end
    end
    return nil
end

local function Change(now, ref)
    if not now or not ref or ref <= 0 then return nil end
    return now / ref - 1
end

---------------------------------------------------------------------------
-- The fair price right now: what the market stood at lately, so a sudden jump (someone bought out the cheap
-- lots and listed them three times higher) or a sudden fall (other crafters undercutting) shows against it.
-- The median of the prices of the last days up to an hour ago, each weighted by how many were listed at it,
-- how long it stood (not how often it was looked at) and how recent it is (half the weight a day): the hour
-- that just went by doesn't move it, a new level the market keeps for hours does.
---------------------------------------------------------------------------
local HALF_LIFE = 24 * 3600
local LOOK_BACK = 4 * 86400
local SETTLED = 3600
local MAX_SPAN = 3 * 3600

-- fair price, the number usually listed (nil: no prices from before the last hour)
function An.FairNow(itemID)
    local now = time()
    local cutoff = now - SETTLED
    local obs = {}
    local function Add(p, q, t, span)
        if p and p > 0 and t and t <= cutoff and now - t <= LOOK_BACK then
            obs[#obs + 1] = { p = p, q = q, t = t, span = span }
        end
    end
    local s = FT.Hist.Snaps(itemID)
    local firstSnap = s and s.t[1]
    -- the days before today: their closing price stood about half a day (where intraday prices don't cover it)
    local today = FT.Day()
    for _, c in ipairs(FT.Hist.Daily(itemID, 5)) do
        if c.day < today then
            local t = c.t + 43200
            if not firstSnap or t < firstSnap then Add(c.c, c.v, t, 12 * 3600) end
        end
    end
    if s then
        for i = 1, #s.t do Add(s.p[i], s.q[i], s.t[i], nil) end
    end
    if #obs == 0 then return nil end
    table.sort(obs, function(a, b) return a.t < b.t end)
    -- an intraday price stood until the next one (at most 3 hours: a long silence says nothing)
    for i, o in ipairs(obs) do
        if not o.span then
            local nextT = obs[i + 1] and obs[i + 1].t or cutoff
            o.span = math.max(600, math.min(nextT - o.t, MAX_SPAN))
        end
    end
    local qs = {}
    for _, o in ipairs(obs) do
        if o.q and o.q > 0 then qs[#qs + 1] = o.q end
    end
    table.sort(qs)
    local qMid = #qs > 0 and qs[math.ceil(#qs / 2)] or 1
    local total, sumQ, sumR = 0, 0, 0
    for _, o in ipairs(obs) do
        local r = 0.5 ^ ((now - o.t) / HALF_LIFE) * o.span
        local q = (o.q and o.q > 0) and o.q or qMid
        o.w = q * r
        total = total + o.w
        sumQ, sumR = sumQ + q * r, sumR + r
    end
    table.sort(obs, function(a, b) return a.p < b.p end)
    local acc, fair = 0, obs[#obs].p
    for _, o in ipairs(obs) do
        acc = acc + o.w
        if acc >= total / 2 then
            fair = o.p
            break
        end
    end
    return fair, sumR > 0 and sumQ / sumR or nil
end

-- far above the fair price: a buyout (or a shortage) - not to be counted on for long (Settings: by how much)
local function Spike(s)
    if FT.S.spikeGuard == false or not (s.price and s.fair) then return false end
    return s.price > s.fair * (1 + (FT.S.spikeAbove or 50) / 100)
end

-- far below the fair price: falling fast - others undercut (Settings: by how much)
local function Falling(s)
    if not (s.price and s.fair) then return false end
    return s.price < s.fair * (1 - (FT.S.fallBelow or 20) / 100)
end

-- { price, t, source, listed, ch1, ch7, ch30, avg, dev, rsi, hi7, lo7, hi30, lo30, vol, days, auctions,
--   sellers, closes, daily, fair, typicalQ, spike, sale (the price to count on when selling) }
function An.Stats(itemID)
    local s = cache[itemID]
    if s then return s end
    s = {}
    s.price, s.t, s.source, s.listed = FT.Price(itemID)
    local daily = FT.Hist.Daily(itemID, 60)
    s.daily = daily
    local today = FT.Day()
    local closes = {}
    for _, c in ipairs(daily) do closes[#closes + 1] = c.c end
    s.closes = closes
    s.ch1 = Change(s.price, CloseAtOrBefore(daily, today - 1))
    s.ch7 = Change(s.price, CloseAtOrBefore(daily, today - 7))
    s.ch30 = Change(s.price, CloseAtOrBefore(daily, today - 30))

    -- the average of the last N days, today left out (that's what we compare today with)
    local avgDays = FT.S.avgDays
    local sum, n, days14 = 0, 0, 0
    local hi7, lo7, hi30, lo30
    for _, c in ipairs(daily) do
        local age = today - c.day
        if age >= 1 and age <= avgDays then
            sum, n = sum + c.c, n + 1
        end
        if age <= 13 then days14 = days14 + 1 end
        if age <= 6 then
            hi7 = math.max(hi7 or c.h, c.h)
            lo7 = math.min(lo7 or c.l, c.l)
        end
        if age <= 29 then
            hi30 = math.max(hi30 or c.h, c.h)
            lo30 = math.min(lo30 or c.l, c.l)
        end
    end
    s.avgN = n
    s.avg = n > 0 and sum / n or nil
    s.dev = Change(s.price, s.avg)
    s.hi7, s.lo7, s.hi30, s.lo30 = hi7, lo7, hi30, lo30
    s.days = days14
    -- how many days this item has history at all (liquidity can't be judged on a day or two)
    s.span = #daily > 0 and (today - daily[1].day + 1) or 0
    local forRsi = {}
    for i = math.max(1, #closes - 29), #closes do forRsi[#forRsi + 1] = closes[i] end
    if s.price and #forRsi > 0 and daily[#daily].day ~= today then forRsi[#forRsi + 1] = s.price end
    s.rsi = An.RSI(forRsi, 14)
    s.vol = An.Volatility(forRsi)

    local book = FT.Hist.Book(itemID)
    if book then
        s.auctions, s.sellers = book.auctions, book.sellers
        s.listed = s.listed or book.qty
        s.bookT = book.t
    end
    s.fair, s.typicalQ = An.FairNow(itemID)
    s.spike = Spike(s)
    s.falling = Falling(s)
    -- more listed than usual: competitors are selling
    s.moreListed = s.listed and s.typicalQ and s.typicalQ > 0 and s.listed > s.typicalQ * 1.3 and (s.listed / s.typicalQ - 1) or nil
    s.sale = s.spike and s.fair or s.price
    cache[itemID] = s
    return s
end

-- day by day: how far the price stood above (+) or below (-) its average of the days before it
-- (Settings: average over N days), as a fraction - the "is it a good moment to sell" line
function An.DevSeries(itemID, days)
    local daily = FT.Hist.Daily(itemID, (days or 30) + FT.S.avgDays)
    local out = {}
    local from = FT.Day() - (days or 30) + 1
    for i, c in ipairs(daily) do
        if c.day >= from then
            local sum, n = 0, 0
            for k = i - 1, 1, -1 do
                local prev = daily[k]
                if c.day - prev.day > FT.S.avgDays then break end
                sum, n = sum + prev.c, n + 1
            end
            if n >= 3 and sum > 0 then
                -- in money: what selling one now brings above (or below) the average price
                local avg = sum / n
                out[#out + 1] = { t = c.t, value = c.c - avg, pct = c.c / avg - 1 }
            end
        end
    end
    return out
end

-- how easy it is to sell: "high" / "medium" / "low" (by how many of the last 14 days it was listed)
-- "unknown" while the item has less than 5 days of history: too early to tell
function An.Liquidity(s)
    if not s or not s.days or not s.span or s.span < 5 then return "unknown" end
    -- the share of the days we know of on which it was listed
    local cover = s.days / math.min(14, s.span)
    if cover >= 0.6 and (s.auctions == nil or s.auctions >= 4) then return "high" end
    if cover >= 0.3 then return "medium" end
    return "low"
end

---------------------------------------------------------------------------
-- Signals: kind, strength (1-3), reason
---------------------------------------------------------------------------
local function Enough(s)
    return s and s.price and s.avg and (s.avgN or 0) >= 3
end

-- for something you have or make: sell now?
function An.SellSignal(s)
    -- a buyout: worth selling a little under it now - it won't last
    if s.spike then
        return "SELL", 2, string.format(L["Price jump (buyout?): %s above its fair price ~%s - sell a little under it now, it won't last"],
            FT.Pct(s.price / s.fair - 1, true), FT.Money(s.fair, "short"))
    end
    if not Enough(s) then return "NODATA", 0, L["Not enough price history yet"] end
    local th = FT.S.sellAbove / 100
    local dev = s.dev or 0
    local hot = s.rsi and s.rsi >= 70
    if dev >= th or hot then
        local strength = (dev >= th and hot) and 3 or ((dev >= th * 2) and 3 or 2)
        local reason
        if dev >= th then
            reason = string.format(L["%s above the %d-day average"], FT.Pct(dev, true), FT.S.avgDays)
        else
            reason = string.format(L["RSI %d: overbought"], math.floor(s.rsi + 0.5))
        end
        return "SELL", strength, reason
    end
    if dev <= -th then
        return "HOLD", 2, string.format(L["%s below the %d-day average: wait"], FT.Pct(dev, true), FT.S.avgDays)
    end
    return "FAIR", 1, L["Price near its average"]
end

-- for a material you need: buy now?
function An.BuySignal(s)
    if not Enough(s) then return "NODATA", 0, L["Not enough price history yet"] end
    local th = FT.S.buyBelow / 100
    local dev = s.dev or 0
    local cold = s.rsi and s.rsi <= 30
    if dev <= -th or cold then
        local strength = (dev <= -th and cold) and 3 or 2
        local reason
        if dev <= -th then
            reason = string.format(L["%s below the %d-day average"], FT.Pct(dev, true), FT.S.avgDays)
        else
            reason = string.format(L["RSI %d: oversold"], math.floor(s.rsi + 0.5))
        end
        return "BUY", strength, reason
    end
    if dev >= th then
        return "EXPENSIVE", 2, string.format(L["%s above the %d-day average"], FT.Pct(dev, true), FT.S.avgDays)
    end
    return "FAIR", 1, L["Price near its average"]
end

-- trend over a week
function An.Trend(s)
    if not s or not s.ch7 then return "flat" end
    if s.ch7 >= 0.05 then return "up" end
    if s.ch7 <= -0.05 then return "down" end
    return "flat"
end

FT.SIGNAL_COLORS = {
    SELL = "up", BUY = "up", CRAFT = "up",
    HOLD = "accent", WATCH = "accent", EXPENSIVE = "accent", RISKY = "accent",
    AVOID = "down", LOSS = "down",
    FAIR = "muted", NODATA = "dim",
}

function FT.SignalText(kind)
    local names = {
        SELL = L["SELL"], BUY = L["BUY"], CRAFT = L["CRAFT"], HOLD = L["HOLD"], WATCH = L["WATCH"],
        EXPENSIVE = L["PRICEY"], RISKY = L["RISKY"], AVOID = L["AVOID"], LOSS = L["LOSS"], FAIR = L["FAIR"],
        NODATA = L["NO DATA"],
    }
    return names[kind] or kind
end
