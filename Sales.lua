-- Wolf of Booty Bay (built on ForeverTrading): how much really sells. The game tells no one's sales, so they are told from the listings:
-- two looks at the same item (a few seconds to a few hours apart), seller by seller and price by price:
--  * fewer at the same price by the same seller: bought (an auction is cancelled whole, a stack is bought in part);
--  * a seller's listing gone and the same seller listing anew (another price): cancelled and listed again - no sale;
--  * gone with less time left than went by: expired - no sale;
--  * gone otherwise: bought (or cancelled for good: the estimate counts that as a sale);
--  * what was listed anew: more supply.
-- Kept day by day per item: sold, what they sold for, how long the item was watched; the rate per day is what
-- was seen sold over the hours watched. The looks come from the searches of an item (live prices, My items,
-- what you open or search) and, for the items that matter to you, the deep full scan.
local ADDON, FT = ...

local Sa = {}
FT.Sales = Sa

local MAX_GAP = 6 * 3600 -- looks further apart than this aren't compared (too much can happen between them)
local KEEP_DAYS = 14
local MIN_WATCH = 3600   -- a rate needs at least an hour watched
local BAND_MAX = { [0] = 1800, [1] = 7200, [2] = 43200, [3] = 172800 } -- time-left bands: the most each can be

local last = {}  -- itemID -> the previous look this session: { t, kind, groups, partial, maxP }
local cache = {} -- itemID -> parsed days: { [day] = { sold, value, watched, relisted, expired, added } }

local Enc, Dec = FT.Hist.Enc, FT.Hist.Dec

-- the sellers of a listing as one key (names sorted; the game may name only some of many: "+N" for the rest)
function Sa.OwnersKey(owners, total)
    local names = {}
    if type(owners) == "table" then
        for _, o in ipairs(owners) do
            if type(o) == "string" and o ~= "" then names[#names + 1] = o end
        end
    elseif type(owners) == "string" and owners ~= "" then
        names[1] = owners
    end
    table.sort(names)
    local key = table.concat(names, ",")
    if type(total) == "number" and total > #names then key = key .. "+" .. (total - #names) end
    return key
end

-- the most time a listing has left (seconds, or by its band), nil when unknown
function Sa.TimeLeft(info)
    if type(info) ~= "table" then return nil end
    if type(info.timeLeftSeconds) == "number" then return info.timeLeftSeconds end
    return info.timeLeft ~= nil and BAND_MAX[info.timeLeft] or nil
end

---------------------------------------------------------------------------
-- Day by day: r.sales[id] = "day,sold,value,watched,relisted,expired,added;..."
---------------------------------------------------------------------------
local function Store()
    local r = FT.R()
    r.sales = r.sales or {}
    return r.sales
end

local function Parse(str)
    local d = {}
    if type(str) == "string" then
        for rec in str:gmatch("([^;]+);") do
            local a, b, c, e, f, g, h = rec:match("^(%w+),(%w*),(%w*),(%w*),(%w*),(%w*),(%w*)$")
            if a then
                d[Dec(a)] = { sold = Dec(b) or 0, value = Dec(c) or 0, watched = Dec(e) or 0, relisted = Dec(f) or 0,
                    expired = Dec(g) or 0, added = Dec(h) or 0 }
            end
        end
    end
    return d
end

local function Days(itemID)
    local d = cache[itemID]
    if d then return d end
    d = Parse(Store()[itemID])
    cache[itemID] = d
    return d
end

local function Save(itemID, d)
    local from = FT.Day() - KEEP_DAYS + 1
    local keys = {}
    for day in pairs(d) do
        if day >= from then keys[#keys + 1] = day else d[day] = nil end
    end
    table.sort(keys)
    local parts = {}
    for _, day in ipairs(keys) do
        local x = d[day]
        parts[#parts + 1] = Enc(day) .. "," .. Enc(x.sold) .. "," .. Enc(x.value) .. "," .. Enc(x.watched) .. ","
            .. Enc(x.relisted) .. "," .. Enc(x.expired) .. "," .. Enc(x.added) .. ";"
    end
    Store()[itemID] = #parts > 0 and table.concat(parts) or nil
end

---------------------------------------------------------------------------
-- Comparing two looks
---------------------------------------------------------------------------
-- the names in a sellers key (the "+N" the game didn't name left out)
local function Names(key, into)
    if type(key) == "string" and key ~= "" then
        for n in key:gsub("%+%d+$", ""):gmatch("[^,]+") do into[n] = true end
    end
    return into
end

-- rows ({ p, q, o, tl }) -> price -> { q, names (set), tl (the longest time left there; nil: unknown) }.
-- By price, not by seller: stackable goods come one row per price, several sellers in it.
local function Groups(rows)
    local g = {}
    for _, r in ipairs(rows) do
        if r.p and r.q and r.q > 0 then
            local x = g[r.p]
            if not x then
                x = { q = 0, names = {}, tl = r.tl }
                g[r.p] = x
            elseif x.tl and r.tl then
                x.tl = math.max(x.tl, r.tl)
            else
                x.tl = nil
            end
            x.q = x.q + r.q
            Names(r.o, x.names)
        end
    end
    return g
end

-- What happened between look a and look b, `gap` seconds apart: sold, their value, relisted, expired, added.
-- Price by price: what was listed anew is put to its sellers (the ones new at that price, else all of it);
-- fewer at a price: expired when the time ran out, moved as far as its sellers listed anew elsewhere, the rest
-- bought. (Checked against the usual cases: a stack bought in part, an undercut, a seller joining or leaving a
-- price, part moved cheaper, all bought.)
local function Compare(a, b, gap)
    -- a look cut short (more listings than its pages) is compared only up to its dearest price
    local cut = math.huge
    if a.partial then cut = math.min(cut, a.maxP) end
    if b.partial then cut = math.min(cut, b.maxP) end
    -- listed anew, seller by seller
    local fresh, newQ = {}, 0
    for p, x in pairs(b.groups) do
        if p <= cut then
            local old = a.groups[p]
            local more = x.q - (old and old.q or 0)
            if more > 0 then
                newQ = newQ + more
                local who = {}
                for n in pairs(x.names) do
                    if not (old and old.names[n]) then who[#who + 1] = n end
                end
                if #who == 0 then
                    for n in pairs(x.names) do who[#who + 1] = n end
                end
                for _, n in ipairs(who) do fresh[n] = (fresh[n] or 0) + more / #who end
            end
        end
    end
    local sold, value, relisted, expired = 0, 0, 0, 0
    for p, x in pairs(a.groups) do
        if p <= cut then
            local now = b.groups[p]
            local less = x.q - (now and now.q or 0)
            if less > 0 then
                if not now and x.tl and x.tl <= gap + 60 then
                    expired = expired + less
                elseif next(x.names) then
                    -- what its sellers listed anew elsewhere was moved, not bought
                    local moved = 0
                    for n in pairs(x.names) do
                        local f = fresh[n]
                        if f and f > 0 and moved < less then
                            local take = math.min(f, less - moved)
                            fresh[n] = f - take
                            moved = moved + take
                        end
                    end
                    relisted = relisted + moved
                    sold, value = sold + (less - moved), value + (less - moved) * p
                end
                -- (no seller named: nobody to tell by - left out)
            end
        end
    end
    local added = math.max(0, newQ - relisted)
    return math.floor(sold + 0.5), value, math.floor(relisted + 0.5), expired, math.floor(added + 0.5)
end

-- One look at an item's listings: rows = { { p = unit price, q = how many, o = OwnersKey, tl = time left }, ... }
-- (empty: none listed). kind: "search" or "full" - only looks of one kind are compared (a full scan lists
-- auction by auction, a search of stackable goods by price). partial: more listings than were read.
function Sa.Observe(itemID, rows, t, partial, kind)
    if not (itemID and type(rows) == "table" and FT.db) then return end
    t = t or time()
    local prev = last[itemID]
    if prev and t <= prev.t then return end -- older than what we have
    local maxP = 0
    for _, r in ipairs(rows) do
        if r.p and r.p > maxP then maxP = r.p end
    end
    local cur = { t = t, kind = kind or "search", groups = Groups(rows), partial = partial and true or false, maxP = maxP }
    last[itemID] = cur
    if not prev or prev.kind ~= cur.kind then return end
    local gap = t - prev.t
    if gap > MAX_GAP then return end
    local sold, value, relisted, expired, added = Compare(prev, cur, gap)
    local d = Days(itemID)
    local day = FT.Day(t)
    local x = d[day]
    if not x then
        x = { sold = 0, value = 0, watched = 0, relisted = 0, expired = 0, added = 0 }
        d[day] = x
    end
    x.sold, x.value, x.watched = x.sold + sold, x.value + math.floor(value + 0.5), x.watched + gap
    x.relisted, x.expired, x.added = x.relisted + relisted, x.expired + expired, x.added + added
    Save(itemID, d)
    if sold > 0 or relisted > 0 then
        FT.Debug("sales:", FT.Name(itemID) or itemID, "sold", sold, "relisted", relisted, "expired", expired, "new", added,
            "in", gap, "s")
    end
end

---------------------------------------------------------------------------
-- What sells
---------------------------------------------------------------------------
-- Over the last `days` (7): { perDay, sold, avgPrice (what they sold for), hours (watched), relisted, expired,
-- added }; nil while the item was watched less than an hour
local function RateOf(d, days)
    local from = FT.Day() - (days or 7) + 1
    local s = { sold = 0, value = 0, watched = 0, relisted = 0, expired = 0, added = 0 }
    for day, x in pairs(d) do
        if day >= from then
            for k in pairs(s) do s[k] = s[k] + (x[k] or 0) end
        end
    end
    if s.watched < MIN_WATCH then return nil end
    return {
        perDay = s.sold / (s.watched / 86400), sold = s.sold, avgPrice = s.sold > 0 and s.value / s.sold or nil,
        hours = s.watched / 3600, relisted = s.relisted, expired = s.expired, added = s.added,
    }
end

-- the feed's sales (Sources/Feed.lua) when they cover more hours than ours
local function Better(own, feed)
    if not feed then return own end
    if not own or (feed.hours or 0) > (own.hours or 0) then return feed end
    return own
end

function Sa.Rate(itemID, days)
    if not (itemID and FT.db) then return nil end
    return Better(RateOf(Days(itemID), days), FT.Feed and FT.Feed.Rate(itemID))
end

-- what sells at either auction house (House.lua): the other one's as it was saved
function Sa.RateIn(house, itemID, days)
    if house == FT.house then return Sa.Rate(itemID, days) end
    if not (itemID and FT.db) then return nil end
    local feed = FT.Feed and FT.Feed.Rate(itemID, house)
    local r = FT.db.realms[FT.HouseKey(house)]
    local str = r and r.sales and r.sales[itemID]
    if not str then return feed end
    return Better(RateOf(Parse(str), days), feed)
end

-- "~12 a day" (with a decimal under 10), for the pages
function Sa.PerDayText(rate)
    if not rate then return nil end
    local v = rate.perDay
    local n = v >= 10 and FT.Num(math.floor(v + 0.5)) or string.format("%.1f", v)
    return string.format(FT.L["~%s a day"], n)
end

FT.On("FT_DATA_CLEARED", function()
    wipe(last)
    wipe(cache)
end)
-- items long gone from the auction house left the history (FT.Hist.DropUnseen)
FT.On("FT_ITEMS_DROPPED", function(ids)
    for id in pairs(ids or {}) do
        last[id], cache[id] = nil, nil
    end
end)
-- per auction house (an item window may look at the other one for a moment)
local saved, savedKey = {}, nil
local function UseHouse()
    local key = FT.houseKey or "?"
    if key == savedKey then return end
    if savedKey then saved[savedKey] = { last = last, cache = cache } end
    local s = saved[key]
    last, cache = s and s.last or {}, s and s.cache or {}
    savedKey = key
end
FT.On("FT_HOUSE_CHANGED", UseHouse)
FT.On("FT_HOUSE_USE", UseHouse)
