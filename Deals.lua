-- ForeverTrading: good deals - what to buy at the auction house right now for a profit.
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

local CHUNK = 200
local BOOK_SLACK = 600 -- an order book this much older than the price is still the price's
local THERE_AGE = 3 * 86400 -- between the houses: the price where it is sold, not older than this
local THERE_DAYS = 2        -- buy no more than sells there in this many days

local deals = {}
local builtAt
local building, again, dirty = false, false, true
-- the last look, for the page to say why it found nothing (and /ft debug): items with a price, the newest
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
    -- watched there half a day and more, and nothing was bought: it wouldn't sell
    if rate and rate.hours >= 12 and rate.sold == 0 then return nil end
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
        if row and row.spark and #row.spark >= 3 then look.history = look.history + 1 end
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
            D.Changed()
        end
    end)
end

function D.Build()
    if building then
        again = true
        return
    end
    if not FT.db then return end
    building, dirty = true, false
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
    local look = { items = 0, history = 0, small = 0, errors = 0, unknown = {} }
    local out = {}
    local i = 1
    local ticker
    ticker = C_Timer.NewTicker(0, function()
        local last = math.min(i + CHUNK - 1, #ids)
        for k = i, last do
            local fine, d, x = pcall(Judge, ids[k], mine, below, look)
            if not fine then
                look.errors = look.errors + 1
                look.firstError = look.firstError or tostring(d)
            else
                for _, deal in ipairs({ d or false, x or false }) do
                    if deal then
                        if deal.profit >= minProfit then
                            out[#out + 1] = deal
                        else
                            look.small = look.small + 1
                        end
                    end
                end
            end
        end
        i = last + 1
        if i > #ids then
            ticker:Cancel()
            table.sort(out, function(a, b) return a.profit > b.profit end)
            deals, builtAt, building, info = out, time(), false, look
            LoadVendorPrices(look.unknown)
            look.unknown = nil
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
FT.On("FT_OWNED_CHANGED", D.Changed)
FT.On("FT_SETTINGS_CHANGED", D.Changed)
-- the other auction house: its own deals (vendor prices are the same everywhere)
FT.On("FT_HOUSE_CHANGED", function()
    deals, builtAt, info = {}, nil, nil
    D.Changed()
    FT.Fire("FT_DEALS_READY")
end)
FT.On("FT_LIVE_UPDATED", function(id) D.Update(id) end)
