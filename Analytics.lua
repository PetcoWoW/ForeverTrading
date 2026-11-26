-- Wolf: indicators and signals.
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
-- per auction house (an item window may look at the other one for a moment)
local caches, cacheKey = {}, nil
local function UseCache()
    local key = FT.houseKey or "?"
    if key == cacheKey then return end
    if cacheKey then caches[cacheKey] = cache end
    cache = caches[key] or {}
    cacheKey = key
end
-- new prices: the items they are of are counted again (all of them after a whole market came in)
local function Forget()
    local set, _, all = FT.Hist.TakeChanged("stats")
    if all then
        wipe(cache)
        return
    end
    for id in pairs(set) do cache[id] = nil end
end
local STATS_FRESH = 600 -- seconds: counted again after this anyway (the fair price weighs prices by their age)
FT.On("FT_PRICES_CHANGED", Forget)
FT.On("FT_SCAN_DONE", Forget)
FT.On("FT_HOUSE_CHANGED", function()
    UseCache()
    wipe(cache)
end)
FT.On("FT_HOUSE_USE", UseCache)
FT.On("FT_LIVE_UPDATED", function(itemID) if itemID then cache[itemID] = nil end end)
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

-- the first close from day `from` to day `to`
local function FirstCloseIn(daily, from, to)
    for _, c in ipairs(daily) do
        if c.day >= from and c.day <= to then return c.c end
    end
    return nil
end

-- How long the market of this auction house has been watched (days with a whole-market scan, of the last `window`):
-- while it is little (a new auction house, Auctionator off: our own scans only) fewer days of prices are asked for.
local function Watched(window)
    return FT.Hist.WatchedDays(window)
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
local DROP = 0.10      -- a price this much lower than at the last check: risky
local FLOOD_MIN = 3    -- flooded: at least this many more listed than usual too (2 instead of 1 is no flood)
local CROWD_MIN = 2    -- more sellers: at least this many more than usual too
local SLOW_HOURS = 12  -- "hardly bought" needs at least this many hours watched

-- fair price, and what is usual (the same weights): how many listed, in how many auctions, by how many sellers
-- (nil: no prices from before the last hour; the usual auctions and sellers: nil while none were counted)
function An.FairNow(itemID)
    local now = time()
    local cutoff = now - SETTLED
    local obs = {}
    local function Add(p, q, t, span, n, sl)
        if p and p > 0 and t and t <= cutoff and now - t <= LOOK_BACK then
            obs[#obs + 1] = { p = p, q = q, t = t, span = span, n = n, sl = sl }
        end
    end
    local s = FT.Hist.Snaps(itemID)
    local firstSnap = s and s.t[1]
    -- the days before today: their closing price stood about half a day (where intraday prices don't cover it)
    local today = FT.Day()
    for _, c in ipairs(FT.Hist.Daily(itemID, 5)) do
        if c.day < today then
            local t = c.t + 43200
            if not firstSnap or t < firstSnap then Add(c.c, c.v, t, 12 * 3600, c.n, nil) end
        end
    end
    if s then
        for i = 1, #s.t do Add(s.p[i], s.q[i], s.t[i], nil, s.n[i], s.sl and s.sl[i]) end
    else
        -- not every price of it is kept (it doesn't matter to you): today's count too - its newest price and the one
        -- before it, once they are an hour old (not only the closes of the days before)
        local p, t, _, q, gone = FT.Price(itemID)
        if p and t and not gone and FT.Day(t) == today then Add(p, q, t, nil, nil, nil) end
        local prev = FT.Hist.Previous(itemID)
        if prev and prev.t ~= t and FT.Day(prev.t) == today then Add(prev.p, prev.q, prev.t, nil, prev.n, prev.sl) end
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
    local sumN, rN, sumS, rS = 0, 0, 0, 0
    for _, o in ipairs(obs) do
        local r = 0.5 ^ ((now - o.t) / HALF_LIFE) * o.span
        local q = (o.q and o.q > 0) and o.q or qMid
        o.w = q * r
        total = total + o.w
        sumQ, sumR = sumQ + q * r, sumR + r
        if o.n and o.n > 0 then sumN, rN = sumN + o.n * r, rN + r end
        if o.sl and o.sl > 0 then sumS, rS = sumS + o.sl * r, rS + r end
    end
    local typicalN = rN > 0 and sumN / rN or nil
    local typicalS = rS > 0 and sumS / rS or nil
    table.sort(obs, function(a, b) return a.p < b.p end)
    local acc, fair = 0, obs[#obs].p
    for _, o in ipairs(obs) do
        acc = acc + o.w
        if acc >= total / 2 then
            fair = o.p
            break
        end
    end
    return fair, sumR > 0 and sumQ / sumR or nil, typicalN, typicalS
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

---------------------------------------------------------------------------
-- How this item behaves, learned from its own daily closes (up to 60 days: the price feed, Auctionator's history,
-- your scans). Each answer counts real past cases, and stays quiet until there are enough of them.
--   highs, held: days 10%+ over the average of the 14 before, and how many still held 95% of it 5-9 days later
--   lows, back:  days 10%+ under it, and how many were back to 97% of that average 5-9 days later
--   stick, rebound: those rates, pulled toward a cautious guess while there are few cases (see PRIOR)
--   bestDay, bestUp, cheapDay, cheapDown: the weekday (0 Sunday) it usually closes highest / lowest, and by how much
-- One case per move: days right after a counted day (within 4) don't count again.
---------------------------------------------------------------------------
local PRIOR = { stick = 0.35, rebound = 0.5, weight = 2 }
local MIN_CASES = 3
local FLIP_BACK = 0.9   -- a flip worked when the price came back to 90% of its average (listed there: it sells)
local KIND_FLIPS = 20   -- a kind's flip record counts from this many cases
An.MIN_CASES = MIN_CASES

local function Weekday(day)
    return tonumber(date("%w", FT.DayStart(day) + 43200))
end
An.Weekday = Weekday

-- its kind (item class:subclass: herbs, ore, cloth, potions...): GetItemInfoInstant needs no server answer
local function KindOf(itemID)
    if not itemID then return nil end
    local _, _, subType, _, _, classID, subID = FT.GetItemInfoInstant(itemID)
    if not classID then return nil end
    return classID .. ":" .. (subID or 0), subType
end
An.KindOf = KindOf

-- what its kind did (An.LearnKinds), for this auction house: { highs, held, lows, back, name } or nil
local KIND_MIN = 30 -- a kind's record counts from this many cases
local function KindRecord(itemID)
    local l = FT.db.learned and FT.db.learned[FT.houseKey or "?"]
    local k = l and l.kinds and KindOf(itemID)
    return k and l.kinds[k] or nil
end

function An.Behavior(daily, itemID)
    local b = { highs = 0, held = 0, lows = 0, back = 0, flips = 0, flipped = 0 }
    local close = {}
    for _, c in ipairs(daily or {}) do close[c.day] = c.c end
    local lastHigh, lastLow, lastFlip = -99, -99, -99
    -- a flip, replayed: a day its cheapest was a deal (FLIP_BELOW under the average of the 14 days before) - did
    -- the price come back to FLIP_BACK of that average within 3 days, so the cheap ones bought could be sold again?
    local flipBelow = (FT.S and FT.S.dealBelow or 30) / 100
    local wkSum, wkN = {}, {}
    for _, c in ipairs(daily or {}) do
        local d = c.day
        local sum, n = 0, 0
        for k = 1, 14 do
            local v = close[d - k]
            if v then sum, n = sum + v, n + 1 end
        end
        if n >= 5 then
            local avg = sum / n
            local low = c.l or c.c
            if low <= avg * (1 - flipBelow) and d - lastFlip > 4 then
                local known, back = false, false
                for k = 1, 3 do
                    local v = close[d + k]
                    if v then known = true; if v >= avg * FLIP_BACK then back = true end end
                end
                if known then
                    lastFlip = d
                    b.flips = b.flips + 1
                    if back then b.flipped = b.flipped + 1 end
                end
            end
            local later
            for k = 5, 9 do
                if close[d + k] then later = close[d + k]; break end
            end
            if later then
                if c.c >= avg * 1.10 and d - lastHigh > 4 then
                    lastHigh = d
                    b.highs = b.highs + 1
                    if later >= c.c * 0.95 then b.held = b.held + 1 end
                elseif c.c <= avg * 0.90 and d - lastLow > 4 then
                    lastLow = d
                    b.lows = b.lows + 1
                    if later >= avg * 0.97 then b.back = b.back + 1 end
                end
            end
        end
        -- the weekday pattern: the close against the week around it (3 days each side, 5 of them known)
        local wSum, wN = 0, 0
        for k = -3, 3 do
            local v = close[d + k]
            if v then wSum, wN = wSum + v, wN + 1 end
        end
        if wN >= 5 and wSum > 0 then
            local wd = Weekday(d)
            wkSum[wd] = (wkSum[wd] or 0) + c.c / (wSum / wN)
            wkN[wd] = (wkN[wd] or 0) + 1
        end
    end
    -- few cases of its own: lean on what its kind did (all herbs, all ore...) instead of a fixed guess
    local kind = itemID and KindRecord(itemID)
    local pStick, pRebound, wStick, wRebound = PRIOR.stick, PRIOR.rebound, PRIOR.weight, PRIOR.weight
    if kind and kind.highs >= KIND_MIN then pStick, wStick, b.kindHighs, b.kindHeld = kind.held / kind.highs, 3, kind.highs, kind.held end
    if kind and kind.lows >= KIND_MIN then pRebound, wRebound, b.kindLows, b.kindBack = kind.back / kind.lows, 3, kind.lows, kind.back end
    if kind and (kind.flips or 0) >= KIND_FLIPS then b.kindFlips, b.kindFlipped = kind.flips, kind.flipped end
    b.kindName = kind and kind.name
    b.stick = (b.held + pStick * wStick) / (b.highs + wStick)
    b.rebound = (b.back + pRebound * wRebound) / (b.lows + wRebound)
    -- enough to act on: its own cases, or its kind's (then said so)
    b.knowsHighs = b.highs >= MIN_CASES or b.kindHighs ~= nil
    b.knowsLows = b.lows >= MIN_CASES or b.kindLows ~= nil
    local days = 0
    for wd, n in pairs(wkN) do
        if n >= 2 then
            days = days + 1
            local r = wkSum[wd] / n
            if not b.bestUp or r - 1 > b.bestUp then b.bestDay, b.bestUp = wd, r - 1 end
            if not b.cheapDown or r - 1 < b.cheapDown then b.cheapDay, b.cheapDown = wd, r - 1 end
        end
    end
    if days < 5 then b.bestDay, b.bestUp, b.cheapDay, b.cheapDown = nil, nil, nil, nil end
    return b
end

-- "its jumps held a week 4 of 5 times" / "Herb jumps held a week 210 of 340 times"
function An.HighRecord(b)
    if b.highs >= MIN_CASES then return string.format(L["its jumps held a week %d of %d times"], b.held, b.highs) end
    if b.kindHighs then
        return string.format(L["%s jumps held a week %d%% of the time"], b.kindName or L["its kind's"],
            math.floor(b.kindHeld / b.kindHighs * 100 + 0.5))
    end
end
function An.LowRecord(b)
    if b.lows >= MIN_CASES then return string.format(L["its dips came back %d of %d times"], b.back, b.lows) end
    if b.kindLows then
        return string.format(L["%s dips came back %d%% of the time"], b.kindName or L["its kind's"],
            math.floor(b.kindBack / b.kindLows * 100 + 0.5))
    end
end

-- How flipping it went before, replayed on its history: worked, cases, its own (true) or its kind's; nil: no cases
function An.FlipRecord(b)
    if not b then return nil end
    if (b.flips or 0) >= MIN_CASES then return b.flipped, b.flips, true end
    if b.kindFlips then return b.kindFlipped, b.kindFlips, false end
    return nil
end

-- "flips worked 9 of 11 times" / "Ore flips worked 72% of the time"
function An.FlipText(b)
    local ok, n, own = An.FlipRecord(b)
    if not ok then return nil end
    if own then return string.format(L["flips worked %d of %d times"], ok, n) end
    return string.format(L["%s flips worked %d%% of the time"], b.kindName or L["its kind's"], math.floor(ok / n * 100 + 0.5))
end

-- Once a day, in the background: every item's cases added up by kind, for this auction house (again at once when
-- what is learned changes: LEARN_V)
local LEARN_V = 3 -- 2: flips, 3: snipe targets
function An.LearnKinds(force)
    local key = FT.houseKey or "?"
    FT.db.learned = FT.db.learned or {}
    local l = FT.db.learned[key]
    if l and l.day == FT.Day() and l.v == LEARN_V and not force then return end
    local ids, seen = {}, {}
    local function Add(id)
        id = tonumber(id)
        if id and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
    end
    FT.Hist.EachItem(Add)
    local fh = FT.Feed and FT.Feed.House and FT.Feed.House()
    if fh then for id in pairs(fh.raw or fh.items) do Add(id) end end
    local kinds = {}
    local often = {} -- snipe targets: deep dips that came back most times, on a market that sells (FT.Snipe)
    FT.Job("learn", #ids, function(k)
        local id = ids[k]
        local kind, name = KindOf(id)
        if not kind then return end
        local b = An.Behavior(FT.Hist.Daily(id, 60))
        if b.highs + b.lows + b.flips == 0 then return end
        local r = kinds[kind]
        if not r then
            r = { highs = 0, held = 0, lows = 0, back = 0, flips = 0, flipped = 0, name = name }
            kinds[kind] = r
        end
        r.highs, r.held, r.lows, r.back = r.highs + b.highs, r.held + b.held, r.lows + b.lows, r.back + b.back
        r.flips, r.flipped = r.flips + b.flips, r.flipped + b.flipped
        if b.flips >= 3 and b.flipped / b.flips >= 0.6 then
            local rate = FT.Feed and FT.Feed.Rate and FT.Feed.Rate(id)
            if rate and rate.perDay >= 1 then often[#often + 1] = { id = id, ok = b.flipped, n = b.flips } end
        end
        -- the week: the day this item usually sells highest, for the kind's calendar - real markets only (3+ sold
        -- a day), and no one item's odd week counted as more than +30%
        local rate = b.bestDay and FT.Sales.Rate(id)
        if b.bestDay and (b.bestUp or 0) >= 0.03 and rate and (rate.sold or 0) >= 5 and (rate.perDay or 0) >= 3 then
            r.wd = r.wd or {}
            local d = r.wd[b.bestDay] or { n = 0, up = 0 }
            r.wd[b.bestDay] = d
            d.n, d.up = d.n + 1, d.up + math.min(b.bestUp, 0.3)
        end
    end, function()
        -- this week's calendar: kinds whose items mostly peak on the same day (5+ items), the clearest first
        local week = {}
        for _, k in pairs(kinds) do
            local best
            for wd, d in pairs(k.wd or {}) do
                if d.n >= 8 and (not best or d.n > best.n) then best = { wd = wd, n = d.n, up = d.up / d.n } end
            end
            if best and best.up >= 0.05 then week[#week + 1] = { name = k.name, wd = best.wd, up = best.up, n = best.n } end
            k.wd = nil
        end
        table.sort(week, function(a, b) return a.n * a.up > b.n * b.up end)
        for i = #week, 4, -1 do week[i] = nil end
        table.sort(often, function(a, b)
            if a.ok ~= b.ok then return a.ok > b.ok end
            return a.ok / a.n > b.ok / b.n
        end)
        for i = #often, (FT.Snipe and FT.Snipe.MAX_OFTEN or 40) + 1, -1 do often[i] = nil end
        FT.db.learned[key] = { day = FT.Day(), v = LEARN_V, kinds = kinds, week = week, often = often }
        pcall(An.SeedScore, kinds)
        wipe(cache)
        FT.Fire("FT_LEARNED")
    end)
end
FT.On("FT_READY", function()
    local function Go()
        if InCombatLockdown and InCombatLockdown() then C_Timer.After(30, Go) return end
        An.LearnKinds()
    end
    C_Timer.After(120, Go)
end)

local WEEKDAYS = { [0] = "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
function An.DayName(wd) return wd and L[WEEKDAYS[wd]] or "" end

-- { price, t, source, listed, ch1, ch7, ch30, avg, dev, rsi, hi7, lo7, hi30, lo30, vol, days, auctions,
--   sellers, closes, daily, fair, typicalQ, spike, sale (the price to count on when selling),
--   auctionsNow, sellersNow (of the newest measurement), typicalN, typicalS (usual auctions, sellers),
--   prev (the check half an hour or more before: t, p, q, n, sl), sinceP (price change since, a fraction),
--   sinceQ, sinceN, sinceS (listed, auctions, sellers: more (+) or fewer (-) since), flood, crowd, dropped }
function An.Stats(itemID)
    local s = cache[itemID]
    if s and GetTime() - s.countedAt < STATS_FRESH then return s end
    s = { countedAt = GetTime(), id = itemID }
    s.price, s.t, s.source, s.listed = FT.Price(itemID)
    local daily = FT.Hist.Daily(itemID, 60)
    s.daily = daily
    local today = FT.Day()
    local closes = {}
    for _, c in ipairs(daily) do closes[#closes + 1] = c.c end
    s.closes = closes
    -- No day as old as that known (a new auction house or item, Auctionator off): the change since the first day of
    -- that span known - or since today's first price, when it moved today at all (seen more than once).
    local last = daily[#daily]
    local dayOpen = last and last.day == today and last.o and last.h ~= last.l and last.o or nil
    s.ch1 = Change(s.price, CloseAtOrBefore(daily, today - 1) or dayOpen)
    s.ch7 = Change(s.price, CloseAtOrBefore(daily, today - 7) or FirstCloseIn(daily, today - 6, today - 1) or dayOpen)
    s.ch30 = Change(s.price, CloseAtOrBefore(daily, today - 30) or FirstCloseIn(daily, today - 29, today - 1) or dayOpen)

    -- the average of the last N days, today left out (that's what we compare today with)
    local avgDays = FT.S.avgDays
    local sum, n, days14 = 0, 0, 0
    local hi7, lo7, hi30, lo30
    local wSum, wN, pSum, pN, loOld = 0, 0, 0, 0, nil -- this week, the two weeks before it, the low before this week
    for _, c in ipairs(daily) do
        local age = today - c.day
        if age >= 1 and age <= avgDays then
            sum, n = sum + c.c, n + 1
        end
        if age >= 1 and age <= 7 then wSum, wN = wSum + c.c, wN + 1 end
        if age >= 8 and age <= 21 then pSum, pN = pSum + c.c, pN + 1 end
        if age >= 8 and age <= 29 then loOld = math.min(loOld or c.l, c.l) end
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
    -- Climbing for weeks, not a jump: this week's average 5%+ over the two weeks before, up 15%+ in 30 days,
    -- and this week's low above the lows before it (higher lows: buyers keep paying more). Needs 3 weeks.
    s.avgWeek = wN > 0 and wSum / wN or nil
    s.avgBefore = pN > 0 and pSum / pN or nil
    s.rising = (wN >= 4 and pN >= 7 and s.avgWeek >= s.avgBefore * 1.05 and (s.ch30 or 0) >= 0.15
        and lo7 ~= nil and loOld ~= nil and lo7 > loOld) and true or false
    s.hi7, s.lo7, s.hi30, s.lo30 = hi7, lo7, hi30, lo30
    s.behavior = An.Behavior(daily, itemID)
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
    -- the market right now: auctions and sellers of the newest measurement (an older order book doesn't count)
    local l = FT.Hist.Latest(itemID)
    if l and s.t and l.t == s.t and not l.gone then
        s.auctionsNow, s.sellersNow = l.n, l.sl
    end
    if book and s.t and book.t and book.t >= s.t - 600 and book.source ~= "mastercraft" then
        s.auctionsNow = s.auctionsNow or ((book.auctions or 0) > 0 and book.auctions or nil)
        s.sellersNow = s.sellersNow or ((book.sellers or 0) > 0 and book.sellers or nil)
    end
    s.fair, s.typicalQ, s.typicalN, s.typicalS = An.FairNow(itemID)
    -- the first day the market is watched (no day before today): the fair price of the hours seen is the average
    if not s.avg and s.fair and Watched(avgDays) <= 1 then s.avg, s.avgN, s.avgFair = s.fair, 0, true end
    s.dev = Change(s.price, s.avg)
    s.spike = Spike(s)
    s.falling = Falling(s)
    s.sale = s.spike and s.fair or s.price

    -- what changed since the last check (the scan, or the live update, of half an hour or more ago)
    local prev = FT.Hist.Previous(itemID)
    if prev and s.price and prev.p and prev.p > 0 then
        s.prev = prev
        s.sinceP = s.price / prev.p - 1
        s.sinceQ = (s.listed and prev.q) and (s.listed - prev.q) or nil
        s.sinceN = (s.auctionsNow and prev.n) and (s.auctionsNow - prev.n) or nil
        s.sinceS = (s.sellersNow and prev.sl) and (s.sellersNow - prev.sl) or nil
    end
    local more = 1 + (FT.S.floodAbove or 50) / 100
    -- far more listed than usual: the market is flooded - a price that holds now may not hold long
    s.flood = (s.listed and s.typicalQ and s.typicalQ > 0 and s.listed >= s.typicalQ * more
        and s.listed - s.typicalQ >= FLOOD_MIN) and true or false
    -- far more sellers than usual: competitors have come
    s.crowd = (s.sellersNow and s.typicalS and s.typicalS > 0 and s.sellersNow >= s.typicalS * more
        and s.sellersNow - s.typicalS >= CROWD_MIN) and true or false
    -- what really sells (FT.Sales: told from the listings seen go): slow when a day sells under 5% of what is
    -- usually listed (and under one) - the listed take weeks to clear
    s.sales = FT.Sales.Rate(itemID)
    local usual = s.typicalQ or s.listed or 0
    s.slow = (s.sales and s.sales.hours >= SLOW_HOURS and s.sales.perDay < math.max(1, usual * 0.05)) and true or false
    -- the price fell since the last check (one of the last day)
    s.dropped = (s.sinceP and s.sinceP <= -DROP and time() - s.prev.t <= 86400) and true or false
    -- Pushed up: a jump (or a price far over its usual) while what's listed thinned out - someone bought the
    -- cheap ones to sell them again higher (a reset). The price may not hold; don't buy into it.
    local thinned = s.listed and s.typicalQ and s.typicalQ > 0 and s.listed <= s.typicalQ * 0.6
    s.pumped = (s.spike or ((s.dev or 0) >= 0.3 and ((s.ch1 or 0) >= 0.2 or thinned))) and true or false
    -- Dumped: far more listed than usual (or a lot more since the last check) and the price going down with it -
    -- a falling knife: wait for it to settle
    local piled = s.flood or (s.sinceQ and s.typicalQ and s.typicalQ > 0 and s.sinceQ >= s.typicalQ * 0.5)
    s.dumping = (piled and (s.falling or s.dropped or (s.ch1 or 0) <= -0.08)) and true or false
    -- The price to list yours at: the real wall of supply, not bait. A lone lot or two far under the next price
    -- up (with a fresh order book) is someone fishing for undercuts - list a copper under the next one instead.
    s.listAt = s.sale
    if book and book.levels and #book.levels >= 2 and s.t and (book.t or 0) >= s.t - 600 and book.source ~= "mastercraft" then
        local first, second = book.levels[1], book.levels[2]
        local few = math.max(2, (s.listed or book.qty or 0) * 0.05)
        if first[2] <= few and second[1] >= first[1] * 1.15 then
            s.bait = true
            s.listAt = math.max(s.listAt or 0, second[1] - 1)
            if s.fair then s.listAt = math.min(s.listAt, math.max(s.fair, first[1])) end
        end
    end
    cache[itemID] = s
    return s
end

-- Why selling it (or crafting it to sell) is risky right now: reasons, the strongest first.
-- liquidity: An.Liquidity of the same stats (given when known)
function An.Risks(s, liquidity)
    local out = {}
    if not (s and s.price) then return out end
    if s.falling and s.fair then
        out[#out + 1] = string.format(L["Price falling fast: %s vs its fair price"], FT.Pct(s.price / s.fair - 1, true))
    end
    if s.dropped then
        out[#out + 1] = string.format(L["%s since the check %s"], FT.Pct(s.sinceP, true), FT.Ago(s.prev.t))
    end
    if s.flood then
        out[#out + 1] = string.format(L["Flooded: %s listed, usually ~%s"], FT.Num(s.listed), FT.Num(math.floor(s.typicalQ + 0.5)))
    end
    if s.crowd then
        out[#out + 1] = string.format(L["More sellers: %d, usually ~%d"], s.sellersNow, math.floor(s.typicalS + 0.5))
    end
    if s.slow then
        out[#out + 1] = string.format(L["Hardly bought: %s with ~%s usually listed"], FT.Sales.PerDayText(s.sales),
            FT.Num(math.floor((s.typicalQ or s.listed or 0) + 0.5)))
    end
    if liquidity == "low" then out[#out + 1] = L["Rarely listed: it may not sell"] end
    if s.ch7 and s.ch7 <= -0.10 then
        out[#out + 1] = string.format(L["Price falling: %s in 7 days"], FT.Pct(s.ch7, true))
    end
    return out
end

-- the same, short, for the line under an item's name (falling fast and a jump are said there already)
function An.RiskNotes(s)
    local out = {}
    if not (s and s.price) then return out end
    if s.dropped then
        out[#out + 1] = string.format(L["%s since the check %s"], FT.Pct(s.sinceP, true), FT.Ago(s.prev.t))
    end
    if s.flood then
        out[#out + 1] = string.format(L["flooded: %s listed (usually ~%s)"], FT.Num(s.listed), FT.Num(math.floor(s.typicalQ + 0.5)))
    end
    if s.crowd then
        out[#out + 1] = string.format(L["%d sellers (usually ~%d)"], s.sellersNow, math.floor(s.typicalS + 0.5))
    end
    return out
end

-- day by day: how far the price stood above (+) or below (-) its average of the days before it
-- (Settings: average over N days), as a fraction - the "is it a good moment to sell" line
function An.DevSeries(itemID, days)
    local daily = FT.Hist.Daily(itemID, (days or 30) + FT.S.avgDays)
    local out = {}
    -- days in an average: 3, fewer while the market has been watched fewer days
    local need = math.max(1, math.min(3, Watched(FT.S.avgDays) - 1))
    local from = FT.Day() - (days or 30) + 1
    for i, c in ipairs(daily) do
        if c.day >= from then
            local sum, n = 0, 0
            for k = i - 1, 1, -1 do
                local prev = daily[k]
                if c.day - prev.day > FT.S.avgDays then break end
                sum, n = sum + prev.c, n + 1
            end
            if n >= need and sum > 0 then
                -- in money: what selling one now brings above (or below) the average price
                local avg = sum / n
                out[#out + 1] = { t = c.t, value = c.c - avg, pct = c.c / avg - 1 }
            end
        end
    end
    return out
end

-- how easy it is to sell: "high" / "medium" / "low" (by how many of the last 14 days it was listed)
-- "unknown" while the item has less than 5 days of history (fewer while the market itself has been watched fewer
-- days, at least 2): too early to tell. On the market's first day: "medium" when many auctions of it are up now.
function An.Liquidity(s)
    if not s or not s.days or not s.span then return "unknown" end
    local watched = Watched(14)
    if s.span >= math.max(2, math.min(5, watched)) then
        -- the share of the days we know of on which it was listed
        local cover = s.days / math.min(14, s.span)
        if cover >= 0.6 and (s.auctions == nil or s.auctions >= 4) then return "high" end
        if cover >= 0.3 then return "medium" end
        return "low"
    end
    if watched <= 1 then
        local auctions = s.auctionsNow or s.auctions
        if (auctions and auctions >= 4) or (not auctions and (s.listed or 0) >= 10) then return "medium" end
    end
    return "unknown"
end

---------------------------------------------------------------------------
-- The item page in three answers: is the market healthy, where is the price going, and what to do
---------------------------------------------------------------------------
-- The market's health: key, label, colour, and a line of why
--   new (too little history), pumped, dumping, flooded, stagnant (hardly sells), thin (little trade), healthy
function An.Health(s)
    if not (s and s.price) then return "new", L["No price yet"], "dim", "" end
    local sales = s.sales
    local perDay = sales and sales.hours >= 12 and sales.perDay or nil
    local listed = s.listed
    local clear = (perDay and perDay > 0 and listed) and listed / perDay or nil
    local why = {}
    if perDay then why[#why + 1] = string.format(L["sells %s a day"], perDay >= 10 and FT.Num(math.floor(perDay + 0.5)) or string.format("%.1f", perDay)) end
    if listed then why[#why + 1] = string.format(L["%s listed"], FT.Num(listed)) end
    if clear then why[#why + 1] = clear < 1 and L["gone in a day"] or string.format(L["%s days to sell out"], FT.Num(math.floor(clear + 0.5))) end
    local line = table.concat(why, ", ")
    if s.pumped then return "pumped", L["Being pushed up"], "down", L["Someone bought the cheap ones to sell them higher: the price may not hold."] end
    if s.dumping then return "dumping", L["Being dumped"], "down", L["A lot more listed and the price dropping: wait for it to settle."] end
    if (s.span or 0) < 3 and not perDay then return "new", L["Too new to tell"], "dim", line end
    if s.flood then return "flooded", L["Flooded"], "accent", line end
    if s.slow or (perDay and perDay < 1) then return "stagnant", L["Stagnant"], "accent", line end
    local liq = An.Liquidity(s)
    if liq == "low" or (perDay and perDay < 3) or (clear and clear > 14) then return "thin", L["Thin market"], "accent", line end
    if not perDay and liq == "unknown" then return "new", L["Too new to tell"], "dim", line end
    return "healthy", L["Healthy"], "up", line
end

-- where the price is going: a word and its colour
function An.TrendWord(s)
    if not (s and s.price) then return L["No price yet"], "dim" end
    if s.pumped or (s.ch1 or 0) >= 0.2 then return L["Spiking"], "accent" end
    if (s.ch1 or 0) <= -0.2 or s.falling then return L["Crashing"], "down" end
    if s.rising then return L["Climbing for weeks"], "up" end
    if (s.ch7 or 0) >= 0.05 then return L["Rising"], "up" end
    if (s.ch7 or 0) <= -0.05 then return L["Falling"], "down" end
    if not s.ch7 then return L["Too new to tell"], "dim" end
    return L["Steady"], "muted"
end

-- The engine's call, for this item and you: what to do (a signal kind and strength), the reason, and a second line
-- (the other side: if you have it, buying more; if not, nothing). Health comes first: a market being pushed up,
-- dumped or that hardly sells is no place to buy, whatever the price says.
function An.Call(s, own)
    local health = An.Health(s)
    local sell, sStr, sWhy, sDetail = An.SellSignal(s)
    local sConf, sRule = s.conf, s.rule
    local buy, bStr, bWhy, bDetail = An.BuySignal(s)
    local bConf, bRule = s.conf, s.rule
    local guard
    if health == "pumped" then guard = L["Don't buy: the price is being pushed up and may not hold."]
    elseif health == "dumping" then guard = L["Don't buy yet: it's being dumped, wait for it to settle."]
    elseif health == "stagnant" then guard = L["Don't buy to resell: it hardly sells."] end
    local call = {}
    if own and own > 0 then
        call.kind, call.strength, call.text, call.detail, call.conf, call.rule = sell, sStr, sWhy, sDetail, sConf, sRule
        call.other = guard or ((buy == "BUY") and (L["Buying more"] .. ": " .. bWhy) or nil)
    elseif guard then
        call.kind, call.strength, call.text, call.conf = "AVOID", 2, guard, "likely"
    else
        call.kind, call.strength, call.text, call.detail, call.conf, call.rule = buy, bStr, bWhy, bDetail, bConf, bRule
    end
    call.record = call.rule and An.RecordText(call.rule) or nil
    return call
end

---------------------------------------------------------------------------
-- Signals: kind, strength (1-3), reason
---------------------------------------------------------------------------
-- an average of 3 days or more (fewer while the market has been watched fewer days; its first day: the fair price
-- of the hours seen)
local function Enough(s)
    if not (s and s.price and s.avg) then return false end
    return (s.avgN or 0) >= math.min(3, math.max(0, Watched(FT.S.avgDays) - 1))
end

-- what the average is of, in the reasons: "the 14-day average" (as many days as the setting while there are 3 or
-- more of them, otherwise as many as there are), or the price of the last hours
-- "+20%" (whole percents: a reason is read at a glance)
local function Pc(v) return string.format("%+d%%", math.floor(v * 100 + (v >= 0 and 0.5 or -0.5))) end
An.Pc = Pc
local function AboveText(s, dev) return string.format(L["Higher than usual (%s)"], Pc(dev)) end
local function BelowText(s, dev) return string.format(L["Cheaper than usual (%s)"], Pc(dev)) end

---------------------------------------------------------------------------
-- The scorecard: the engine grading its own calls. Every day it writes down what it said about the items that
-- matter (yours, your watchlist, the busiest markets) and at what price; 5-9 days later it looks at what the price
-- did and marks each call right or wrong. A rule's record (all items together) then decides how sure its calls
-- are, and a rule that keeps being wrong (under 35% over 10+ calls) is switched off until it does better. Before
-- there are graded calls, the market's own history stands in (what jumps and dips did, all items together).
---------------------------------------------------------------------------
local Allowed, RuleConf
local OPTIONAL = { stick = true, rising = true, week = true, comeback = true, nowait = true, buyback = true }

local function Score()
    FT.db.score = FT.db.score or { rules = {}, pending = {} }
    return FT.db.score
end

-- right, out of: what the rule's calls did (seeded from history until real calls come in)
function An.RuleRecord(rule)
    local sc = FT.db and FT.db.score
    local r = rule and sc and sc.rules[rule]
    if not r then return 0, 0 end
    return (r.r or 0) + (r.sr or 0), (r.n or 0) + (r.sn or 0), r.r or 0, r.n or 0
end

-- a rule that keeps being wrong is left out (its branch isn't taken)
Allowed = function(rule)
    if not OPTIONAL[rule] then return true end
    local right, n = An.RuleRecord(rule)
    return not (n >= 10 and right / n < 0.35)
end

-- how sure, from the rule's own record (nil: too few calls graded)
RuleConf = function(rule)
    local right, n = An.RuleRecord(rule)
    if n < 10 then return nil end
    local rate = right / n
    return (rate >= 0.65 and "sure") or (rate >= 0.45 and "likely") or "guess"
end

-- "right 7 of 10" (its real calls; nil while there are fewer than 5)
function An.RecordText(rule)
    local _, _, r, n = An.RuleRecord(rule)
    if not n or n < 5 then return nil end
    return string.format(L["right %d of %d"], r, n)
end

-- was a call right? p: the price called at, later: the close 5-9 days on
local SELL_RULES = { spike = true, crack = true, fade = true, high = true, hype = true }
local HOLD_UP = { rising = true, stick = true, week = true }
local function Right(rule, p, later)
    if SELL_RULES[rule] then return later <= p end
    if rule == "trim" then return later <= p * 1.05 end
    if HOLD_UP[rule] then return later >= p end
    if rule == "comeback" or rule == "waitdip" then return later >= p * 1.05 end
    if rule == "nowait" then return later <= p * 1.02 end
    if rule == "buy" or rule == "buyback" then return later >= p * 1.03 end
    -- waiting was right when buying then wouldn't have paid (it didn't come back 3%)
    if rule == "buyfalls" or rule == "buyslide" then return later < p * 1.03 end
    return nil
end
An.Right = Right

local function Tally(rule, ok)
    local sc = Score()
    local r = sc.rules[rule] or {}
    sc.rules[rule] = r
    r.n = (r.n or 0) + 1
    if ok then r.r = (r.r or 0) + 1 end
end

local MAX_LOGGED = 400
-- once a day: today's calls written down, the calls 5+ days old graded
function An.ScoreDay()
    local key = FT.houseKey
    if not key then return end
    local sc = Score()
    local pend = sc.pending[key] or {}
    sc.pending[key] = pend
    local today = FT.Day()
    -- grade
    local graded = 0
    for k, v in pairs(pend) do
        local id, day = k:match("^(%d+):(%d+)b?$")
        id, day = tonumber(id), tonumber(day)
        local rule, p = v:match("^(%a+),(%d+)$")
        p = tonumber(p)
        if not (id and day and rule and p) then
            pend[k] = nil
        elseif today - day >= 5 then
            local later
            for _, c in ipairs(FT.Hist.Daily(id, 20) or {}) do
                if c.day >= day + 5 and c.day <= day + 9 then later = c.c; break end
            end
            if later then
                local ok = Right(rule, p, later)
                if ok ~= nil then Tally(rule, ok); graded = graded + 1 end
                pend[k] = nil
            elseif today - day > 12 then
                pend[k] = nil
            end
        end
    end
    -- write down today's (once a day)
    if sc.loggedDay and sc.loggedDay[key] == today then return graded end
    sc.loggedDay = sc.loggedDay or {}
    sc.loggedDay[key] = today
    local ids, seen = {}, {}
    local function Add(id) if id and not seen[id] and #ids < MAX_LOGGED then seen[id] = true; ids[#ids + 1] = id end end
    for _, h in ipairs((FT.Port.Rows())) do Add(h.id) end
    for id in pairs(FT.db.watch or {}) do Add(id) end
    -- the busiest markets: the most gold listed (cheap to sort; no sales lookups for 7,000 items)
    local busy = {}
    for _, r in ipairs(FT.Market.Rows() or {}) do
        if r.price and (r.qty or 0) >= 5 then busy[#busy + 1] = r end
    end
    table.sort(busy, function(a, b) return a.price * a.qty > b.price * b.qty end)
    for _, r in ipairs(busy) do
        if #ids >= MAX_LOGGED then break end
        Add(r.id)
    end
    -- the calls themselves, a little each frame
    FT.Job("score", #ids, function(k)
        local id = ids[k]
        local st = An.Stats(id)
        if st.price and st.price > 0 then
            An.SellSignal(st)
            if st.rule then pend[id .. ":" .. today] = st.rule .. "," .. math.floor(st.price) end
            An.BuySignal(st)
            if st.rule and st.rule:find("^buy") then pend[id .. ":" .. today .. "b"] = st.rule .. "," .. math.floor(st.price) end
        end
    end)
    return graded
end
FT.On("FT_MARKET_READY", function() FT.Debounce("scoreDay", 20, function() pcall(An.ScoreDay) end) end)

-- the market's own history as a starting record (all items' jumps and dips, from An.LearnKinds), weighed as up
-- to 10 calls: real graded calls soon outweigh it
function An.SeedScore(kinds)
    local H, Hd, Lo, Bk = 0, 0, 0, 0
    for _, k in pairs(kinds or {}) do H, Hd, Lo, Bk = H + k.highs, Hd + k.held, Lo + k.lows, Bk + k.back end
    local sc = Score()
    local function Seed(rule, rate, n)
        if n < 30 then return end
        local r = sc.rules[rule] or {}
        sc.rules[rule] = r
        r.sn, r.sr = 10, rate * 10
    end
    if H > 0 then Seed("high", (H - Hd) / H, H) end
    if Lo > 0 then
        Seed("waitdip", Bk / Lo, Lo)
        Seed("buy", Bk / Lo, Lo)
        Seed("nowait", (Lo - Bk) / Lo, Lo)
    end
end

-- "Herb peaks Tuesday (+8%) · Potion peaks Monday (+11%)" (nil: no clear pattern yet)
function An.WeekText()
    local l = FT.db.learned and FT.db.learned[FT.houseKey or "?"]
    local week = l and l.week
    if not (week and week[1]) then return nil end
    local parts = {}
    for _, w in ipairs(week) do
        parts[#parts + 1] = string.format(L["%s peaks %s (%s)"], w.name or "?", An.DayName(w.wd), Pc(w.up))
    end
    return table.concat(parts, "  ·  ")
end

-- all graded calls together: right, out of
function An.Scorecard()
    local right, n = 0, 0
    for _, r in pairs((FT.db.score or { rules = {} }).rules) do right, n = right + (r.r or 0), n + (r.n or 0) end
    return right, n
end

-- How sure a signal is: Sure (this item's own past cases), Likely (its kind's, or a long history), Guess (little to go by)
local function Conf(s, own, kind)
    if own then return "sure" end
    if kind or (s.days or 0) >= 10 then return "likely" end
    return "guess"
end
local CONF_TEXT = { sure = "Sure", likely = "Likely", guess = "Guess" }
function An.ConfText(c) return c and L[CONF_TEXT[c]] or "" end

-- For something you have or make: sell now? Returns kind, strength (1-3), a short reason anyone gets, and the
-- numbers behind it (for a hover). How sure it is goes in s.conf.
function An.SellSignal(s)
    s.conf, s.rule = nil, nil
    -- a buyout: worth selling a little under it now - it won't last
    if s.spike then
        s.conf, s.rule = "likely", "spike"
        return "SELL", 2, string.format(L["Someone bought out the cheap ones: sell a little under ~%s now, it won't last"], FT.Money(s.fair, "short")),
            string.format(L["%s over its fair price"], Pc(s.price / s.fair - 1))
    end
    if not Enough(s) then return "NODATA", 0, L["Not enough price history yet"] end
    local th = FT.S.sellAbove / 100
    local dev = s.dev or 0
    local hot = s.rsi and s.rsi >= 70
    local b = s.behavior or {}
    local learn = FT.S.holdTrends ~= false
    local sticky = learn and b.knowsHighs and b.stick >= 0.6
    local fades = learn and b.knowsHighs and b.stick <= 0.3
    local record = b.knowsHighs and An.HighRecord(b) or nil
    local ownHighs, kindHighs = (b.highs or 0) >= MIN_CASES, b.kindHighs ~= nil
    local ownLows, kindLows = (b.lows or 0) >= MIN_CASES, b.kindLows ~= nil
    -- yours to hold: you marked it (a raid or phase coming that the numbers can't see)
    if FT.db.longHold and s.id and FT.db.longHold[s.id] then
        s.conf = "sure"
        return "HOLD", 3, L["Your long hold: HODL until you unmark it"], (dev >= th) and AboveText(s, dev) or nil
    end
    if (dev >= th or hot) and learn and ((s.rising and Allowed("rising")) or (sticky and Allowed("stick"))) then
        local up = s.rising and string.format(L["%s this month"], Pc(s.ch30 or 0)) or nil
        s.conf = Conf(s, ownHighs or s.rising, kindHighs)
        -- the climb cracking: fell since the last check, under its fair price, more listed or sellers than usual,
        -- or not selling - take the gains while they're there
        local why
        if s.dropped then why = L["it just fell"]
        elseif s.falling then why = L["it's under its price of the last hours"]
        elseif s.flood then why = L["far more listed than usual"]
        elseif s.crowd then why = L["more sellers than usual"]
        elseif s.slow then why = L["it's hardly selling"] end
        if why then
            s.rule = "crack"
            return "SELL", 3, string.format(L["Was climbing, now slipping (%s): sell"], why), up or record
        end
        -- climbing, but stretched far above its average: bank half, let the rest ride
        if dev >= th * 3 or (s.rsi and s.rsi >= 80) then
            s.rule = "trim"
            return "TRIM", 2, string.format(L["Way up (%s): sell half, keep half"], up or Pc(dev)), record
        end
        if s.rising and Allowed("rising") then
            s.rule = "rising"
            s.conf = RuleConf("rising") or s.conf
            return "HOLD", 3, string.format(L["Climbing for weeks (%s): let it ride"], up), record
        end
        s.rule = "stick"
        s.conf = RuleConf("stick") or s.conf
        return "HOLD", 3, L["Higher than usual, and jumps like this tend to stick: let it ride"], record
    end
    if dev >= th or hot then
        local strength = (dev >= th and hot) and 3 or ((dev >= th * 2) and 3 or 2)
        local detail = dev >= th and AboveText(s, dev) or string.format(L["Hype %d"], math.floor(s.rsi + 0.5))
        -- the week's rhythm: its best day is close and pays clearly more - list it then
        if learn and b.bestDay and (b.bestUp or 0) >= 0.05 and not s.dropped and not s.flood and Allowed("week") then
            local today = Weekday(FT.Day())
            local wait = (b.bestDay - today) % 7
            if wait >= 1 and wait <= 3 then
                s.conf, s.rule = RuleConf("week") or "likely", "week"
                local day = An.DayName(b.bestDay)
                return "HOLD", 2, string.format(L["Higher than usual, and %ss pay %s more: list it %s"], day, Pc(b.bestUp), day), detail
            end
        end
        if fades then
            s.conf, s.rule = RuleConf("fade") or Conf(s, ownHighs, kindHighs), "fade"
            return "SELL", 3, L["Higher than usual, and jumps like this fade fast: sell now"], detail .. "; " .. record
        end
        if dev >= th then
            s.conf, s.rule = RuleConf("high") or Conf(s, false, false), "high"
            return "SELL", strength, string.format(L["Higher than usual (%s): good time to sell"], Pc(dev)), nil
        end
        s.conf, s.rule = RuleConf("hype") or Conf(s, false, false), "hype"
        return "SELL", strength, L["Hyped up right now: good time to sell"], detail
    end
    if dev <= -th then
        if learn and b.knowsLows and b.rebound <= 0.3 and Allowed("nowait") then
            s.conf, s.rule = RuleConf("nowait") or Conf(s, ownLows, kindLows), "nowait"
            return "FAIR", 1, L["Cheaper than usual, and dips here don't come back: no point waiting"], BelowText(s, dev) .. "; " .. An.LowRecord(b)
        end
        if learn and b.knowsLows and b.rebound >= 0.6 and Allowed("comeback") then
            s.conf, s.rule = RuleConf("comeback") or Conf(s, ownLows, kindLows), "comeback"
            return "HOLD", 3, L["Cheaper than usual, but dips like this come back: wait"], BelowText(s, dev) .. "; " .. An.LowRecord(b)
        end
        s.conf, s.rule = RuleConf("waitdip") or Conf(s, false, false), "waitdip"
        return "HOLD", 2, string.format(L["Cheaper than usual (%s): wait for it to come back"], Pc(dev)), nil
    end
    s.conf = Conf(s, false, false)
    return "FAIR", 1, L["About its usual price"]
end

-- for a material you need: buy now?
function An.BuySignal(s)
    s.conf, s.rule = nil, nil
    if not Enough(s) then return "NODATA", 0, L["Not enough price history yet"] end
    local th = FT.S.buyBelow / 100
    local dev = s.dev or 0
    local cold = s.rsi and s.rsi <= 30
    local b = s.behavior or {}
    if dev <= -th or cold then
        local strength = (dev <= -th and cold) and 3 or 2
        local detail = dev <= -th and BelowText(s, dev) or string.format(L["Hype %d"], math.floor(s.rsi + 0.5))
        if FT.S.holdTrends ~= false and b.knowsLows then
            s.conf = Conf(s, (b.lows or 0) >= MIN_CASES, b.kindLows ~= nil)
            if b.rebound >= 0.6 and Allowed("buyback") then
                s.conf, s.rule = RuleConf("buyback") or s.conf, "buyback"
                return "BUY", 3, string.format(L["Cheaper than usual (%s), and dips like this come back: good buy"], Pc(dev)), An.LowRecord(b)
            elseif b.rebound <= 0.3 then
                -- most dips like this kept falling: cheap isn't a buy here (the market's own record says so)
                s.rule = "buyfalls"
                return "WATCH", 1, string.format(L["Cheaper than usual (%s), but dips like this kept falling: wait"], Pc(dev)), An.LowRecord(b)
            end
        end
        -- still sliding for a week, with no record that dips come back: a falling knife - wait for it to settle
        if (s.ch7 or 0) <= -0.10 and not (b.knowsLows and b.rebound >= 0.6) then
            s.conf, s.rule = Conf(s, false, false), "buyslide"
            return "WATCH", 1, string.format(L["Cheaper than usual, but still falling (%s this week): wait for it to settle"], Pc(s.ch7)), nil
        end
        s.conf, s.rule = RuleConf("buy") or Conf(s, false, false), "buy"
        if dev <= -th then
            return "BUY", strength, string.format(L["Cheaper than usual (%s): good time to buy"], Pc(dev)), nil
        end
        return "BUY", strength, L["Nobody's buying right now: cheap"], detail
    end
    if dev >= th then
        s.conf = Conf(s, false, false)
        return "EXPENSIVE", 2, string.format(L["Pricier than usual (%s): wait"], Pc(dev)), nil
    end
    s.conf = Conf(s, false, false)
    return "FAIR", 1, L["About its usual price"]
end

-- trend over a week
function An.Trend(s)
    if not s or not s.ch7 then return "flat" end
    if s.ch7 >= 0.05 then return "up" end
    if s.ch7 <= -0.05 then return "down" end
    return "flat"
end

FT.SIGNAL_COLORS = {
    SELL = "up", BUY = "up", CRAFT = "up", TRIM = "up",
    HOLD = "accent", WATCH = "accent", EXPENSIVE = "accent", RISKY = "accent",
    AVOID = "down", LOSS = "down",
    FAIR = "muted", NODATA = "dim",
    VENDOR = "up", RESELL = "blue", UNDERCUT = "down", HOUSES = "accent", DE = "blue",
}

function FT.SignalText(kind)
    local names = {
        SELL = L["SELL"], TRIM = L["TRIM"], BUY = L["BUY"], CRAFT = L["CRAFT"], HOLD = L["HOLD"], WATCH = L["WATCH"],
        EXPENSIVE = L["PRICEY"], RISKY = L["RISKY"], AVOID = L["AVOID"], LOSS = L["LOSS"], FAIR = L["FAIR"],
        NODATA = L["NO DATA"], VENDOR = L["TO VENDOR"], RESELL = L["RESELL"], UNDERCUT = L["UNDERCUT"],
        HOUSES = L["CARRY OVER"],
    }
    return names[kind] or kind
end
