-- ForeverTrading: good deals - what to buy at the auction house right now for a profit.
--  * to a vendor: listed under what a vendor pays for it - buy it and sell it to the vendor: a sure profit
--    (no cut, no waiting);
--  * to resell: listed far under its fair price on a steady market (listed most days, not flooded, no crowd
--    of new sellers, the cheap lots only a small part of all that is listed) - buy the cheap lots and list
--    them again at the fair price, or just under the next lot up, the auction house's cut counted (FT.Cut).
-- With a fresh order book a deal counts every cheap lot (your own left out); without one only the cheapest
-- lot is sure - "Check order books" at the auction house searches those items.
-- Looked for a little each frame among every item with a price, again when prices change and the page is on.
local ADDON, FT = ...

local D = {}
FT.Deals = D

local CHUNK = 200
local BOOK_SLACK = 600 -- an order book this much older than the price is still the price's

local deals = {}
local builtAt
local building, again, dirty = false, false, true

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
    local d = { id = id, kind = "VENDOR", unit = p, target = v, t = t, perUnit = v - p }
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

-- a quick look before the whole stats: is the price far under the closes of the last days?
local function LooksCheap(id, p, below)
    local row = FT.Market.Row(id)
    local spark = row and row.spark
    if not (spark and #spark >= 3) then return false end
    local closes = {}
    for i = 1, #spark - 1 do closes[#closes + 1] = spark[i] end -- the last one may be today's: left out
    table.sort(closes)
    local mid = closes[math.ceil(#closes / 2)]
    return mid ~= nil and p <= mid * (1 - below * 0.6)
end

-- buy the cheap lots, list them again near the fair price
local function ToResell(id, p, t, mine, below)
    local s = FT.An.Stats(id)
    local fair = s.fair
    if not (fair and fair > 0 and p <= fair * (1 - below)) then return nil end
    local liq = FT.An.Liquidity(s)
    if liq ~= "high" and liq ~= "medium" then return nil end
    -- flooded, more sellers, or hardly bought (seen from the listings): listed again, it may not sell
    if s.flood or s.crowd or s.slow then return nil end
    local d = { id = id, kind = "RESELL", unit = p, t = t, fair = fair, liquidity = liq, sales = s.sales }
    local book = FreshBook(id, t)
    if book then
        local qty, cost, above = LotsUnder(book, math.floor(fair * (1 - below)) + 1, mine)
        if qty <= 0 then return nil end
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
    return d
end

local function Judge(id, mine, below)
    local p, t, _, _, gone = FT.Price(id)
    if not (p and t) or gone then return nil end
    local v = ToVendor(id, p, t, mine[id])
    local r = LooksCheap(id, p, below) and ToResell(id, p, t, mine[id], below) or nil
    -- both: the sure one, unless reselling brings far more
    if v and r then return (r.profit > v.profit * 1.5) and r or v end
    return v or r
end

function D.Build()
    if building then
        again = true
        return
    end
    if not FT.db then return end
    building, dirty = true, false
    local ids = {}
    FT.Hist.EachItem(function(id) ids[#ids + 1] = id end)
    local mine = OwnedMap()
    local below = (FT.S.dealBelow or 30) / 100
    local minProfit = FT.S.dealMin or 0
    local out = {}
    local i = 1
    local ticker
    ticker = C_Timer.NewTicker(0, function()
        local last = math.min(i + CHUNK - 1, #ids)
        for k = i, last do
            local ok, d = pcall(Judge, ids[k], mine, below)
            if ok and d and d.profit >= minProfit then out[#out + 1] = d end
        end
        i = last + 1
        if i > #ids then
            ticker:Cancel()
            table.sort(out, function(a, b) return a.profit > b.profit end)
            deals, builtAt, building = out, time(), false
            FT.Fire("FT_DEALS_READY")
            if again then
                again = false
                C_Timer.After(1, D.Build)
            end
        end
    end)
end

-- the deals (best first), when they were looked for, still looking
function D.List()
    return deals, builtAt, building
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
    local ok, d = pcall(Judge, id, OwnedMap(), (FT.S.dealBelow or 30) / 100)
    local had = false
    for i = #deals, 1, -1 do
        if deals[i].id == id then
            table.remove(deals, i)
            had = true
        end
    end
    if ok and d and d.profit >= (FT.S.dealMin or 0) then
        deals[#deals + 1] = d
        table.sort(deals, function(a, b) return a.profit > b.profit end)
    elseif not had then
        return
    end
    FT.Fire("FT_DEALS_READY")
end

FT.On("FT_MARKET_READY", D.Changed)
FT.On("FT_SCAN_DONE", D.Changed)
FT.On("FT_OWNED_CHANGED", D.Changed)
FT.On("FT_SETTINGS_CHANGED", D.Changed)
FT.On("FT_LIVE_UPDATED", function(id) D.Update(id) end)
