-- Wolf of Booty Bay: good deals - what to buy at the auction house right now for a profit.
--  * to a vendor: listed under what a vendor pays for it - buy it and sell it to the vendor: a sure profit
--    (no cut, no waiting);
--  * to resell: listed far under its fair price on a steady market (listed most days, not flooded, no crowd
--    of new sellers, the cheap lots only a small part of all that is listed) - buy the cheap lots and list
--    them again at the fair price, or just under the next lot up, the auction house's cut counted (FT.Cut);
--  * between the auction houses: cheaper at one (your faction's or Blackwater, open to both factions) than the other
--    sells it for - buy, carry it over, list it there a copper under its lowest (or at its usual price when that
--    is lower now), its own cut counted; no more than sells there in two days (or half of what is listed there).
-- With a fresh order book a deal counts every cheap lot (your own left out); without one only the cheapest
-- lot is sure - "Check order books" at the auction house searches those items.
-- Looked for a little each frame among every item with a price, again when prices change and the page is on.
-- What a vendor pays is known only for items the game has loaded: the others are asked for quietly (a new game or
-- computer has seen hardly any), and the deals are looked for again as they come.
local ADDON, FT = ...

local D = {}
FT.Deals = D

local FULL_EVERY = 600  -- every item again at least this often (prices age); otherwise only the changed ones
local BOOK_SLACK = 600 -- an order book this much older than the price is still the price's
local THERE_AGE = 3 * 86400 -- between the houses: the price where it is sold, not older than this
local THERE_DAYS = 2        -- buy no more than sells there in this many days

local deals = {}
local builtAt
local building, again, dirty = false, false, true
local fullAt, builtDay, fullNext = nil, nil, false
-- what each item counted in the last look (the counts below go on item by item): 1 has a price, 2 has days of
-- history, 4 an error, 8 a deal under the minimum profit (16: two)
local counted = {}
-- the last look, for the page to say why it found nothing (and /wolf debug): items with a price, the newest
-- price, items with 3+ days of prices, deals under the minimum profit, errors
local info

-- vendor prices not loaded yet: asked for the cheapest items first, a few at a time, once a session
local LOAD_BATCH, LOAD_EVERY, LOAD_REBUILD = 40, 0.5, 15
local asked = {}
local loadQueue, loadAt, loader = {}, 1, nil

-- our own auctions: item -> unit price -> how many (we can't buy those)
local function OwnedMap()
    local map = {}
    if FT.Owned and FT.Owned.List then
        for _, a in ipairs(FT.Owned.List() or {}) do
            if a.itemID and a.unit and not a.sold then
                local u = math.ceil(a.unit)
                map[a.itemID] = map[a.itemID] or {}
                map[a.itemID][u] = (map[a.itemID][u] or 0) + (a.qty or 1)
            end
        end
    end
    return map
end

-- the order book of an item when it is as new as its price
local function FreshBook(id, t)
    local book = FT.Hist.Book(id)
    if not (book and book.levels and #book.levels > 0) or book.source == "mastercraft" then return nil end
    if (book.t or 0) < (t or 0) - BOOK_SLACK then return nil end
    return book
end

-- the lots under `limit` each: how many, what they cost (ours left out), the first price at or above it
local function LotsUnder(book, limit, mine)
    local qty, cost, above = 0, 0, nil
    for _, lv in ipairs(book.levels) do
        if lv[1] < limit then
            local q = lv[2] - (mine and mine[lv[1]] or 0)
            if q > 0 then qty, cost = qty + q, cost + q * lv[1] end
        else
            above = lv[1]
            break
        end
    end
    return qty, cost, above
end

-- buy at the auction house, sell to a vendor
local function ToVendor(id, p, t, mine)
    local v = FT.SellPriceKnown(id)
    if not (v and v > p) then return nil end
    local d = { id = id, kind = "VENDOR", unit = p, target = v, t = t, perUnit = v - p, worst = 0 }
    local book = FreshBook(id, t)
    if book then
        local qty, cost = LotsUnder(book, v, mine)
        if qty <= 0 then return nil end
        d.qty, d.cost, d.profit = qty, cost, v * qty - cost
    else
        -- the cheapest one is most likely ours
        if mine and mine[math.ceil(p)] then return nil end
        d.qty, d.cost, d.profit, d.noBook = 1, p, v - p, true
    end
    return d
end

-- closes of the days before reselling needs: 2, fewer while the market has been watched fewer days (its first day:
-- none - the fair price of the hours seen decides, in the whole stats)
local function NeedCloses()
    return math.min(2, math.max(0, FT.Hist.WatchedDays(14) - 1))
end

-- a quick look before the whole stats: is the price far under the closes of the last days?
local function LooksCheap(id, p, below)
    local row = FT.Market.Row(id)
    local spark = row and row.spark
    local need = NeedCloses()
    if not (spark and #spark >= need + 1) then return false end
    if need == 0 and #spark < 2 then return true end
    local closes = {}
    for i = 1, #spark - 1 do closes[#closes + 1] = spark[i] end -- the last one may be today's: left out
    table.sort(closes)
    local mid = closes[math.ceil(#closes / 2)]
    return mid ~= nil and p <= mid * (1 - below * 0.6)
end

-- The broker's checks before a flip is shown (a new player may buy on its word):
--  * it really sells: seen for a day or more, 2+ a day - a cheap price nobody pays is no deal;
--  * the price to sell at is its real one: the lower of its fair price and its average of the last days (a spike
--    doesn't count), and the cheap ones are well under it after the cut;
--  * the market isn't being pushed up, dumped, flooded or crowded with new sellers;
--  * flipping it worked before, replayed on its price history (its own, else its kind's): not shown when it
--    mostly didn't;
--  * no more than sells in RESELL_DAYS days, and what you'd get back if it doesn't sell (the worst case) is shown.
local RESELL_DAYS = 2
local MIN_PER_DAY = 2
local OWN_FLIP_MIN, KIND_FLIP_MIN = 0.6, 0.5 -- the share of replayed flips that must have worked

-- what's left if it doesn't sell: what a vendor pays, or the 30-day low after the cut (whichever is more)
local function Floor(id, s, cut)
    local v = FT.SellPriceKnown(id) or 0
    local lo = s and s.lo30 and s.lo30 * (1 - cut) or 0
    return math.max(v, lo)
end

-- buy the cheap lots, list them again near the fair price
local function ToResell(id, p, t, mine, below)
    local s = FT.An.Stats(id)
    local fair = s.fair
    if fair and s.avg and s.avg > 0 and s.avg < fair then fair = s.avg end
    if not (fair and fair > 0 and p <= fair * (1 - below)) then return nil end
    local liq = FT.An.Liquidity(s)
    if liq ~= "high" and liq ~= "medium" then return nil end
    -- flooded, more sellers, hardly bought, pushed up or dumped: listed again, it may not sell
    if s.flood or s.crowd or s.slow or s.pumped or s.dumping then return nil end
    local sales = s.sales
    if not (sales and sales.hours >= 24 and sales.perDay >= MIN_PER_DAY) then return nil end
    local ok, n, own = FT.An.FlipRecord(s.behavior)
    if ok and ok / n < (own and OWN_FLIP_MIN or KIND_FLIP_MIN) then return nil end
    local cap = math.max(1, math.floor(sales.perDay * RESELL_DAYS + 0.5))
    local d = { id = id, kind = "RESELL", unit = p, t = t, fair = fair, liquidity = liq, sales = sales, cap = cap,
        record = ok and { ok, n, own } or nil }
    local book = FreshBook(id, t)
    if book then
        local qty, cost, above = 0, 0, nil
        local limit = math.floor(fair * (1 - below)) + 1
        local cheap = 0
        for _, lv in ipairs(book.levels) do
            if lv[1] >= limit then above = lv[1]; break end
            local q = lv[2] - (mine and mine[lv[1]] or 0)
            if q > 0 then
                cheap = cheap + q
                local take = math.min(q, cap - qty)
                if take > 0 then qty, cost = qty + take, cost + take * lv[1] end
            end
        end
        if qty <= 0 then return nil end
        d.cheap = cheap
        -- most of what is listed is down there: the market itself is lower now - no bargain
        local listed = s.listed or book.qty
        if listed and listed > 0 and qty > listed * 0.5 then return nil end
        -- listed again at the fair price, or just under the next lot up when that is lower
        local resale = fair
        if above and above - 1 < resale then resale = above - 1 end
        d.target, d.qty, d.cost = resale, qty, cost
        d.profit = resale * (1 - FT.Cut()) * qty - cost
    else
        if mine and mine[math.ceil(p)] then return nil end
        d.target, d.qty, d.cost, d.noBook = fair, 1, p, true
        d.profit = fair * (1 - FT.Cut()) - p
    end
    d.perUnit = d.target * (1 - FT.Cut()) - p
    if d.profit <= 0 then return nil end
    d.worst = math.max(0, d.cost - Floor(id, s, FT.Cut()) * d.qty)
    return d
end

-- the middle one
local function Median(list)
    if #list == 0 then return nil end
    local s = {}
    for i, v in ipairs(list) do s[i] = v end
    table.sort(s)
    return s[math.ceil(#s / 2)]
end

-- buy at one auction house, carry it to the other, sell it there
local function Between(id, mine)
    local here = FT.house
    local other = (here == "neutral") and "faction" or "neutral"
    local pHere, tHere, qHere = FT.Hist.PriceIn(here, id)
    if not pHere then return nil end
    local pOther, tOther, qOther = FT.Hist.PriceIn(other, id)
    if not pOther or pOther == pHere then return nil end
    -- the cheaper one is bought, the other sold at
    local buyH, sellH, pb, tb, ps, ts, qs
    if pHere < pOther then
        buyH, sellH, pb, tb, ps, ts, qs = here, other, pHere, tHere, pOther, tOther, qOther
    else
        buyH, sellH, pb, tb, ps, ts, qs = other, here, pOther, tOther, pHere, tHere, qHere
    end
    if not (tb and ts) or time() - ts > THERE_AGE then return nil end
    local cut = FT.Cut(sellH)
    if (ps - 1) * (1 - cut) <= pb then return nil end
    -- a copper under the lowest there, or its usual price when that is lower now (a spike doesn't last)
    local closes = FT.Hist.ClosesIn(sellH, id, 7)
    local usual = #closes >= 3 and Median(closes) or nil
    local sell = ps - 1
    if usual and usual < sell then sell = usual end
    local net = sell * (1 - cut)
    if net <= pb then return nil end
    local rate = FT.Sales.RateIn(sellH, id)
    -- it must be seen selling there (half a day and more, one a day or more): carried over, it has to sell
    if not (rate and rate.hours >= 12 and rate.perDay >= 1) then return nil end
    local cap = rate and math.max(1, math.floor(rate.perDay * THERE_DAYS + 0.5))
        or math.max(1, math.floor((qs or 2) / 2))
    local d = { id = id, kind = "HOUSES", buyHouse = buyH, sellHouse = sellH, unit = pb, target = sell, t = tb,
        sellT = ts, usual = usual, there = qs, sales = rate, cut = cut, thin = #closes < 3, cap = cap }
    local mineHere = (buyH == here) and mine or nil
    local book = FT.Hist.BookIn(buyH, id)
    if book and book.levels and #book.levels > 0 and book.source ~= "mastercraft" and (book.t or 0) >= tb - BOOK_SLACK then
        -- the lots that bring more there than they cost, up to what sells there
        local qty, cost, cheap = 0, 0, 0
        for _, lv in ipairs(book.levels) do
            if lv[1] >= net then break end
            local q = lv[2] - (mineHere and mineHere[lv[1]] or 0)
            if q > 0 then
                cheap = cheap + q
                local take = math.min(q, cap - qty)
                if take > 0 then qty, cost = qty + take, cost + take * lv[1] end
            end
        end
        if qty <= 0 then return nil end
        d.qty, d.cost, d.cheap = qty, cost, cheap
    else
        -- the cheapest one is most likely ours
        if mineHere and mineHere[math.ceil(pb)] then return nil end
        d.qty, d.cost, d.noBook = 1, pb, true
    end
    d.perUnit = net - pb
    d.profit = net * d.qty - d.cost
    if d.profit <= 0 then return nil end
    -- what's left if it doesn't sell there: its lowest of the last week there after the cut, or a vendor
    local lowThere = #closes > 0 and math.min(unpack(closes)) or pb
    d.worst = math.max(0, d.cost - math.max(FT.SellPriceKnown(id) or 0, lowThere * (1 - cut)) * d.qty)
    return d
end

-- an item's deal here (to a vendor, or to resell) and its deal between the auction houses
local function Judge(id, mine, below, look)
    local p, t, _, _, gone = FT.Price(id)
    if not (p and t) or gone then return nil end
    if look then
        look.items = look.items + 1
        if not look.newest or t > look.newest then look.newest = t end
        if not asked[id] and FT.SellPriceKnown(id) == nil and not FT.ItemCached(id) then
            look.unknown[#look.unknown + 1] = { id, p }
        end
        local row = FT.Market.Row(id)
        if row and row.spark and #row.spark >= NeedCloses() + 1 then look.history = look.history + 1 end
    end
    local v = ToVendor(id, p, t, mine[id])
    local r = LooksCheap(id, p, below) and ToResell(id, p, t, mine[id], below) or nil
    local x = Between(id, mine[id])
    -- both: the sure one, unless reselling brings far more
    if v and r then return (r.profit > v.profit * 1.5) and r or v, x end
    return v or r, x
end

-- the vendor prices the last look didn't know: asked for, the cheapest items first; the deals follow now and
-- then while they come, and once more at the end
local function LoadVendorPrices(list)
    if loader or #list == 0 then return end
    table.sort(list, function(a, b) return a[2] < b[2] end)
    loadQueue, loadAt = list, 1
    local lastLook = GetTime()
    loader = C_Timer.NewTicker(LOAD_EVERY, function()
        local last = math.min(loadAt + LOAD_BATCH - 1, #loadQueue)
        for k = loadAt, last do
            local id = loadQueue[k][1]
            asked[id] = true
            FT.RequestItem(id)
        end
        loadAt = last + 1
        local done = loadAt > #loadQueue
        if done then
            loader:Cancel()
            loader, loadQueue = nil, {}
        end
        if done or GetTime() - lastLook >= LOAD_REBUILD then
            lastLook = GetTime()
            -- any item may have its vendor price now: every item again
            fullNext = true
            D.Changed()
        end
    end)
end

local function Count(look, code, sign)
    look.items = look.items + sign * (code % 2)
    look.history = look.history + sign * (math.floor(code / 2) % 2)
    look.errors = look.errors + sign * (math.floor(code / 4) % 2)
    look.small = look.small + sign * math.floor(code / 8)
end

-- one item looked at: its deals into `out`, what it counts into `look`, vendor prices to ask for into `unknown`
local one = {} -- what Judge counts for one item (the same table each time)
local function Look(id, mine, below, minProfit, look, out, unknown)
    one.items, one.history, one.newest, one.unknown = 0, 0, nil, unknown
    local fine, d, x = pcall(Judge, id, mine, below, one)
    local code
    if not fine then
        code = 4
        look.firstError = look.firstError or tostring(d)
    else
        code = one.items + 2 * one.history
        if one.newest and (not look.newest or one.newest > look.newest) then look.newest = one.newest end
        if d then
            if d.profit >= minProfit then out[#out + 1] = d else code = code + 8 end
        end
        if x then
            if x.profit >= minProfit then out[#out + 1] = x else code = code + 8 end
        end
    end
    local old = counted[id]
    if old then Count(look, old, -1) end
    counted[id] = code ~= 0 and code or nil
    Count(look, code, 1)
end

local function ByProfit(a, b) return a.profit > b.profit end

local function Finished(out, unknown)
    table.sort(out, ByProfit)
    deals, builtAt, building = out, time(), false
    LoadVendorPrices(unknown)
    FT.Fire("FT_DEALS_READY")
    if again then
        again = false
        C_Timer.After(1, D.Build)
    end
end

-- every item
local function BuildAll()
    building, dirty = true, false
    FT.Hist.TakeChanged("deals") -- every item is looked at: what changed so far is in it
    -- an error here must not leave the page "looking" for ever
    local ok, ids, mine = pcall(function()
        local list = {}
        FT.Hist.EachItem(function(id) list[#list + 1] = id end)
        return list, OwnedMap()
    end)
    if not ok then
        building = false
        geterrorhandler()(ids)
        return
    end
    local below = (FT.S.dealBelow or 30) / 100
    local minProfit = FT.S.dealMin or 0
    local look = { items = 0, history = 0, small = 0, errors = 0 }
    local out, unknown = {}, {}
    local today = FT.Day()
    counted = {}
    D.job = FT.Job("deals", #ids, function(k) Look(ids[k], mine, below, minProfit, look, out, unknown) end, function()
        info, fullAt, builtDay = look, time(), today
        D.job = nil
        Finished(out, unknown)
    end)
end

-- while looking through every item: how far, 0-1 (nil: not looking)
function D.Progress()
    if not (building and D.job and D.job.Progress) then return nil end
    local done, n = D.job.Progress()
    return n > 0 and done / n or nil
end

-- Ready before the Money page is opened: looked for once a minute after login (never in a fight), and the disenchant
-- deals with them; after that, only what changed when the page is opened
FT.On("FT_READY", function()
    local function Go()
        if InCombatLockdown and InCombatLockdown() then C_Timer.After(30, Go) return end
        if not builtAt and not building then D.Build() end
        if FT.Enchant and FT.Enchant.Deals then FT.Enchant.Deals() end
    end
    C_Timer.After(60, Go)
end)

-- only the items whose prices changed (or your auctions of them): the rest stay as they were
local function BuildChanged(set)
    building, dirty = true, false
    local ids = {}
    for id in pairs(set) do ids[#ids + 1] = id end
    local mine = OwnedMap()
    local below = (FT.S.dealBelow or 30) / 100
    local minProfit = FT.S.dealMin or 0
    local out, unknown = {}, {}
    for _, d in ipairs(deals) do
        if not set[d.id] then out[#out + 1] = d end
    end
    local look = info -- the counts go on from the last look
    FT.Job("deals+", #ids, function(k) Look(ids[k], mine, below, minProfit, look, out, unknown) end, function()
        Finished(out, unknown)
    end)
end

function D.Build()
    if building then
        again = true
        return
    end
    if not FT.db then return end
    if fullNext or not (builtAt and info) or builtDay ~= FT.Day() or time() - (fullAt or 0) > FULL_EVERY then
        fullNext = false
        return BuildAll()
    end
    local set, n, all = FT.Hist.TakeChanged("deals")
    if all then return BuildAll() end
    dirty = false
    if n > 0 then BuildChanged(set) end
end

-- the deals (best first), when they were looked for, still looking
function D.List()
    return deals, builtAt, building
end

-- the last look: { items, newest, history, small, errors, firstError } (nil before the first)
function D.Info()
    return info
end

-- how many vendor prices are still to be asked for
function D.Loading()
    return loader and math.max(0, #loadQueue - loadAt + 1) or 0
end

-- looked for again when the page wants them and something changed (or never yet)
function D.Ensure()
    if dirty or not builtAt then D.Build() end
end

-- the page showing the deals follows new prices
function D.Changed()
    dirty = true
    if D.watching and D.watching() then FT.Debounce("dealsBuild", 3, D.Build) end
end

-- one item again (a live update at the auction house): its deal changes in place, nothing else is looked at
function D.Update(id)
    if not (id and builtAt) or building then return end
    local ok, d, x = pcall(Judge, id, OwnedMap(), (FT.S.dealBelow or 30) / 100)
    local had, added = false, false
    for i = #deals, 1, -1 do
        if deals[i].id == id then
            table.remove(deals, i)
            had = true
        end
    end
    if ok then
        for _, deal in ipairs({ d or false, x or false }) do
            if deal and deal.profit >= (FT.S.dealMin or 0) then
                deals[#deals + 1] = deal
                added = true
            end
        end
    end
    if added then
        table.sort(deals, function(a, b) return a.profit > b.profit end)
    elseif not had then
        return
    end
    FT.Fire("FT_DEALS_READY")
end

FT.On("FT_MARKET_READY", D.Changed)
FT.On("FT_SCAN_DONE", D.Changed)
-- your auctions changed: the items they are of (and were of) again
local ownedBefore = {}
FT.On("FT_OWNED_CHANGED", function()
    local now = OwnedMap()
    for id in pairs(now) do FT.Hist.MarkChanged("deals", id) end
    for id in pairs(ownedBefore) do FT.Hist.MarkChanged("deals", id) end
    ownedBefore = now
    D.Changed()
end)
FT.On("FT_SETTINGS_CHANGED", function()
    fullNext = true
    D.Changed()
end)
-- the other auction house: its own deals (vendor prices are the same everywhere)
FT.On("FT_HOUSE_CHANGED", function()
    deals, builtAt, info, counted = {}, nil, nil, {}
    D.Changed()
    FT.Fire("FT_DEALS_READY")
end)
FT.On("FT_LIVE_UPDATED", function(id) D.Update(id) end)

---------------------------------------------------------------------------
-- The carry list: the deals between the auction houses you take on (a right click on one). At the one house it
-- says what to buy - it stays when the deal is gone (you bought the cheap lots); at the other the Sell page says
-- what you brought and what it was bought for. It goes when you have listed what you brought there (out of your
-- bags at that house), on another right click, or after two weeks.
---------------------------------------------------------------------------
local C = {}
FT.Carry = C
local CARRY_DAYS = 14

-- itemID -> { buy, sell (houses), unit (bought for), target (to list at), qty, cut (there), at (taken on), had }
local function Store()
    local r = FT.Side()
    r.carry = r.carry or {}
    return r.carry
end

function C.Get(id)
    return id and Store()[id] or nil
end

function C.Count()
    local n = 0
    for _ in pairs(Store()) do n = n + 1 end
    return n
end

-- a deal between the houses into the list, or out of it (`d`: a deal, or a row of the list); true: in it now
function C.Toggle(d)
    local s = Store()
    if s[d.id] then
        s[d.id] = nil
        FT.Fire("FT_CARRY_CHANGED")
        return false
    end
    s[d.id] = { buy = d.buyHouse, sell = d.sellHouse, unit = d.unit, target = d.target, qty = d.qty or 1, cut = d.cut,
        at = time() }
    FT.Fire("FT_CARRY_CHANGED")
    return true
end

-- the list as rows of the deals page - those not among the deals found now (`have`: itemID -> true)
function C.Rows(have)
    local out = {}
    for id, e in pairs(Store()) do
        if not (have and have[id]) and e.unit and e.target then
            local qty = e.qty or 1
            local net = e.target * (1 - (e.cut or FT.Cut(e.sell)))
            out[#out + 1] = { id = id, kind = "HOUSES", carried = true, buyHouse = e.buy, sellHouse = e.sell,
                unit = e.unit, target = e.target, qty = qty, cut = e.cut, perUnit = net - e.unit,
                profit = (net - e.unit) * qty, cost = e.unit * qty, t = e.at, sellT = e.at }
        end
    end
    return out
end

-- what you brought is out of your bags at the house it sells at (listed, or sold to a vendor there), or the
-- entry is old: out of the list
local function Tidy()
    if not FT.db then return end
    local s, now, changed = Store(), time(), false
    for id, e in pairs(s) do
        local count = GetItemCount and GetItemCount(id) or 0
        if count > 0 then
            e.had = true
        elseif e.had and FT.ahHere and FT.atHouse == e.sell then
            s[id], changed = nil, true
        end
        if s[id] and now - (e.at or 0) > CARRY_DAYS * 86400 then s[id], changed = nil, true end
    end
    if changed then FT.Fire("FT_CARRY_CHANGED") end
end
FT.On("FT_INVENTORY_CHANGED", Tidy)
FT.On("FT_READY", Tidy)
