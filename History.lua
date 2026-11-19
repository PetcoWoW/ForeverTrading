-- ForeverTrading: price history, kept by ForeverTrading itself.
--  * every item seen on the auction house gets a day candle (open, high, low, close of its lowest price,
--    the most listed and the most auctions that day) - for as long as Settings > Data says;
--  * the items that matter to you (your recipes and their materials, your watchlist, what you own, what you
--    opened) also get every single observation, for intraday candles;
--  * the last order book of every item seen this session (saved for the items that matter to you).
-- Everything is saved as short base-36 strings so the saved file stays small.
local ADDON, FT = ...

local H = {}
FT.Hist = H

local EPOCH = 1704067200 -- 2024-01-01: times inside the strings are minutes since then
local MERGE_WINDOW = 600 -- intraday: one record per 10 minutes of the clock (the newest look of them wins)
local PREV_GAP = 1800    -- "since the last check": the newest measurement at least half an hour older than now

---------------------------------------------------------------------------
-- base 36
---------------------------------------------------------------------------
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function Enc(n)
    n = math.floor((n or 0) + 0.5)
    if n <= 0 then return "0" end
    local s = ""
    while n > 0 do
        local d = n % 36
        s = DIGITS:sub(d + 1, d + 1) .. s
        n = math.floor(n / 36)
    end
    return s
end
local function Dec(s)
    if not s or s == "" then return nil end
    return tonumber(s, 36)
end
local function Opt(n)
    return n and Enc(n) or ""
end
local function Minutes(t)
    return math.floor((t - EPOCH) / 60)
end
H.Enc, H.Dec = Enc, Dec

---------------------------------------------------------------------------
-- Items we keep every observation of
---------------------------------------------------------------------------
local universe = nil

function H.RebuildUniverse()
    local set = {}
    if FT.Craft and FT.Craft.EachItem then
        FT.Craft.EachItem(function(itemID) set[itemID] = true end)
    end
    for itemID in pairs(FT.db.watch) do set[itemID] = true end
    for _, itemID in ipairs(FT.db.viewed) do set[itemID] = true end
    if FT.Port and FT.Port.EachHolding then
        FT.Port.EachHolding(function(itemID) set[itemID] = true end)
    end
    universe = set
    local n = 0
    for _ in pairs(set) do n = n + 1 end
    H.universeSize = n
end

function H.UniverseSize()
    if not universe then H.RebuildUniverse() end
    return H.universeSize or 0
end

function H.Tracked(itemID)
    if FT.S.trackAll then return true end
    if not universe then H.RebuildUniverse() end
    return universe[itemID] == true
end

function H.EachTracked(fn)
    if not universe then H.RebuildUniverse() end
    for itemID in pairs(universe) do fn(itemID) end
end

-- remember an item the user opened (it gets intraday history from now on)
function H.Viewed(itemID)
    local list = FT.db.viewed
    for i = #list, 1, -1 do
        if list[i] == itemID then table.remove(list, i) end
    end
    table.insert(list, 1, itemID)
    while #list > 40 do table.remove(list) end
    if universe then universe[itemID] = true end
end

FT.On("FT_RECIPES_CHANGED", function() universe = nil end)
FT.On("FT_INVENTORY_CHANGED", function() universe = nil end)
FT.On("FT_WATCH_CHANGED", function() universe = nil end)
FT.On("FT_SOURCES_CHANGED", function() universe = nil end)

---------------------------------------------------------------------------
-- Day candles: r.days[id] = finished days "d,o,h,l,c,q,n;...", r.today[id] = the newest day "d,o,h,l,c,q,n,m"
---------------------------------------------------------------------------
local todayCache = {} -- itemID -> { d, o, h, l, c, q, n, m }
local daysCache = {}  -- itemID -> parsed finished days

local function ParseToday(str)
    if type(str) ~= "string" then return nil end
    local d, o, h, l, c, q, n, m = str:match("^(%w+),(%w+),(%w+),(%w+),(%w+),(%w*),(%w*),(%w*)$")
    if not d then return nil end
    return { d = Dec(d), o = Dec(o), h = Dec(h), l = Dec(l), c = Dec(c), q = Dec(q), n = Dec(n), m = Dec(m) or 0 }
end

local function DayRecord(t)
    return Enc(t.d) .. "," .. Enc(t.o) .. "," .. Enc(t.h) .. "," .. Enc(t.l) .. "," .. Enc(t.c) .. "," .. Opt(t.q) .. ","
        .. Opt(t.n)
end

local function ParseDays(str, out)
    out = out or {}
    if type(str) ~= "string" then return out end
    for rec in str:gmatch("([^;]+);") do
        local d, o, h, l, c, q, n = rec:match("^(%w+),(%w+),(%w+),(%w+),(%w+),(%w*),(%w*)$")
        if d then
            out[#out + 1] = { day = Dec(d), o = Dec(o), h = Dec(h), l = Dec(l), c = Dec(c), q = Dec(q), n = Dec(n) }
        end
    end
    return out
end

local function Today(itemID)
    local t = todayCache[itemID]
    if t then return t end
    t = ParseToday(FT.R().today[itemID])
    if t then todayCache[itemID] = t end
    return t
end

local function Days(itemID)
    local p = daysCache[itemID]
    if p then return p end
    p = ParseDays(FT.R().days[itemID])
    daysCache[itemID] = p
    return p
end

-- the last few finished days without reading the whole string
local function RecentDays(itemID, n)
    local str = FT.R().days[itemID]
    if not str then return {} end
    if daysCache[itemID] then
        local all, out = daysCache[itemID], {}
        for i = math.max(1, #all - n + 1), #all do out[#out + 1] = all[i] end
        return out
    end
    local tail = str
    if #str > n * 44 then
        tail = str:sub(-n * 44)
        local cut = tail:find(";", 1, true)
        tail = cut and tail:sub(cut + 1) or ""
    end
    local out = ParseDays(tail)
    while #out > n do table.remove(out, 1) end
    return out
end

local function PruneDays(itemID)
    local keepFrom = FT.Day() - (FT.S.keepDaily or 90)
    local all = Days(itemID)
    local first = 1
    while all[first] and all[first].day < keepFrom do first = first + 1 end
    if first == 1 then return end
    local parts, kept = {}, {}
    for i = first, #all do
        local r = all[i]
        kept[#kept + 1] = r
        parts[#parts + 1] = DayRecord({ d = r.day, o = r.o, h = r.h, l = r.l, c = r.c, q = r.q, n = r.n }) .. ";"
    end
    daysCache[itemID] = kept
    FT.R().days[itemID] = #parts > 0 and table.concat(parts) or nil
end

-- one price seen for one item: the day candle moves
local function ObserveDay(itemID, p, q, n, t)
    local r = FT.R()
    local d = FT.Day(t)
    local m = Minutes(t)
    local tr = Today(itemID)
    if tr and tr.d > d then return end -- an observation of a day already closed: leave the candles alone
    if tr and tr.d == d then
        if m >= tr.m then
            tr.c = p
            tr.m = m
        end
        if p > tr.h then tr.h = p end
        if p < tr.l then tr.l = p end
        if q and q > (tr.q or 0) then tr.q = q end
        if n and n > (tr.n or 0) then tr.n = n end
    else
        if tr then
            -- the old day is finished: it joins the history
            r.days[itemID] = (r.days[itemID] or "") .. DayRecord(tr) .. ";"
            local cached = daysCache[itemID]
            if cached then
                cached[#cached + 1] = { day = tr.d, o = tr.o, h = tr.h, l = tr.l, c = tr.c, q = tr.q, n = tr.n }
            end
            if #r.days[itemID] > ((FT.S.keepDaily or 90) + 10) * 30 then PruneDays(itemID) end
        end
        tr = { d = d, o = p, h = p, l = p, c = p, q = q, n = n, m = m }
        todayCache[itemID] = tr
    end
    r.today[itemID] = DayRecord(tr) .. "," .. Enc(tr.m)
end

---------------------------------------------------------------------------
-- Intraday observations (the items that matter to you): r.snaps[id] = "t,p,q,n;..."
---------------------------------------------------------------------------
local cache = {}  -- itemID -> parsed { t = {}, p = {}, q = {}, n = {} }
local latest = {} -- itemID -> { p, q, n, sl, t, source, gone } this session, every item
local before = {} -- itemID -> the latest entry before the newest measurement (this session, every item)

-- s = { t, p, q (listed), n (auctions), sl (sellers) }: "t,p,q,n,sl;" (sellers since 1.1.1, may be missing)
local function ParseSnaps(str)
    local s = { t = {}, p = {}, q = {}, n = {}, sl = {} }
    if type(str) ~= "string" then return s end
    for rec in str:gmatch("([^;]+);") do
        local a, b, c, d, e = rec:match("^(%w+),(%w+),(%w*),?(%w*),?(%w*)$")
        if a then
            local i = #s.t + 1
            s.t[i] = Dec(a) * 60 + EPOCH
            s.p[i] = Dec(b)
            s.q[i] = Dec(c)
            s.n[i] = Dec(d)
            s.sl[i] = Dec(e)
        end
    end
    return s
end

local function SnapRecord(t, p, q, n, sl)
    local rec = Enc(Minutes(t)) .. "," .. Enc(p) .. "," .. Opt(q) .. "," .. Opt(n)
    if sl then rec = rec .. "," .. Enc(sl) end
    return rec .. ";"
end

local function SerializeSnaps(s)
    local parts = {}
    for i = 1, #s.t do parts[#parts + 1] = SnapRecord(s.t[i], s.p[i], s.q[i], s.n[i], s.sl[i]) end
    return table.concat(parts)
end

function H.Snaps(itemID)
    local s = cache[itemID]
    if s then return s end
    local str = FT.R().snaps[itemID]
    if not str then return nil end
    s = ParseSnaps(str)
    cache[itemID] = s
    return s
end

local function PruneSnaps(itemID, s)
    local keep = FT.S.keepDays * 86400
    local maxN = FT.S.maxSnaps
    local now = time()
    local first = 1
    while first <= #s.t and (now - s.t[first] > keep or (#s.t - first + 1) > maxN) do
        first = first + 1
    end
    if first > 1 then
        local n = { t = {}, p = {}, q = {}, n = {}, sl = {} }
        for i = first, #s.t do
            local k = #n.t + 1
            n.t[k], n.p[k], n.q[k], n.n[k], n.sl[k] = s.t[i], s.p[i], s.q[i], s.n[i], s.sl[i]
        end
        cache[itemID] = n
        FT.R().snaps[itemID] = #n.t > 0 and SerializeSnaps(n) or nil
        return n
    end
    return s
end

local function ObserveIntraday(itemID, p, q, n, t, sl)
    local snaps = FT.R().snaps
    local s = H.Snaps(itemID)
    if not s then
        s = { t = {}, p = {}, q = {}, n = {}, sl = {} }
        cache[itemID] = s
    end
    local last = #s.t
    if last > 0 and t < s.t[last] then return end -- older than what we have
    -- one record per 10 minutes of the clock (a window that moved with every look would make the live updates
    -- of an hour one record, and nothing to compare with)
    if last > 0 and math.floor(t / MERGE_WINDOW) == math.floor(s.t[last] / MERGE_WINDOW) then
        -- the same moment of the market: the newest value wins
        s.t[last], s.p[last] = t, p
        if q then s.q[last] = q end
        if n then s.n[last] = n end
        if sl then s.sl[last] = sl end
        local str = snaps[itemID] or ""
        local prefix = str:match("^(.*;)[^;]*;$") or ""
        snaps[itemID] = prefix .. SnapRecord(s.t[last], s.p[last], s.q[last], s.n[last], s.sl[last])
    else
        last = last + 1
        s.t[last], s.p[last], s.q[last], s.n[last], s.sl[last] = t, p, q, n, sl
        snaps[itemID] = (snaps[itemID] or "") .. SnapRecord(t, p, q, n, sl)
        if last > FT.S.maxSnaps then PruneSnaps(itemID, s) end
    end
end

-- Sources that tell the pages themselves when they are done (one item every few seconds, or a transfer
-- of thousands): no "prices changed" storm for each price
local QUIET = { live = true, peer = true }

-- The one way prices come in: the lowest unit buyout `p` of an item, how many are listed `q`, in how many
-- auctions `n` by how many sellers `sl` (q, n and sl may be unknown), seen at time `t`, by `source`
-- ("full", "mine", "live", "auctionator"...)
function H.Observe(itemID, p, q, n, t, source, sl)
    itemID = type(itemID) == "number" and itemID or tonumber(itemID)
    if not itemID or type(p) ~= "number" or p <= 0 then return end
    t = t or time()
    local cur = latest[itemID]
    if not cur or t >= cur.t then
        -- the measurement before this one stays at hand (what changed since)
        if cur and not cur.gone and t - cur.t >= PREV_GAP then before[itemID] = cur end
        latest[itemID] = { p = p, q = q, n = n, sl = sl, t = t, source = source }
    end
    ObserveDay(itemID, p, q, n, t)
    if H.Tracked(itemID) then ObserveIntraday(itemID, p, q, n, t, sl) end
    if not QUIET[source] then
        FT.Debounce("pricesChanged", 1.0, function() FT.Fire("FT_PRICES_CHANGED", source) end)
    end
end

-- the prices seen since `since` (the newest of each item): fn(itemID, price, listed, t)
function H.EachSince(since, fn)
    local m0 = Minutes(since)
    for itemID in pairs(FT.R().today) do
        local l = latest[itemID]
        if l and l.p and l.t >= since then
            if not l.gone then fn(itemID, l.p, l.q, l.t) end
        else
            local tr = Today(itemID)
            if tr and tr.m >= m0 and not (l and l.gone and l.t >= tr.m * 60 + EPOCH) then
                fn(itemID, tr.c, tr.q, tr.m * 60 + EPOCH)
            end
        end
    end
end

-- a full scan didn't find it: none listed right now (its last price stays)
function H.Gone(itemID, t, source)
    local cur = latest[itemID]
    local p = cur and cur.p
    if not p then
        local tr = Today(itemID)
        p = tr and tr.c
    end
    latest[itemID] = { p = p, q = 0, n = 0, t = t or time(), source = source or "full", gone = true }
end

function H.Latest(itemID)
    return latest[itemID]
end

-- The measurement before the newest one, at least half an hour older: { t, p, q, n, sl } (nil: none known).
-- An item that matters to you has every measurement (the last scan, or the live update of half an hour ago);
-- any other one the one before the newest of this session.
function H.Previous(itemID)
    local cur = latest[itemID]
    local s = H.Snaps(itemID)
    local curT = (cur and cur.t) or (s and s.t[#s.t])
    if s and curT then
        for i = #s.t, 1, -1 do
            if s.t[i] <= curT - PREV_GAP then
                return { t = s.t[i], p = s.p[i], q = s.q[i], n = s.n[i], sl = s.sl[i] }
            end
        end
    end
    local b = before[itemID]
    if b and curT and b.t <= curT - PREV_GAP then return { t = b.t, p = b.p, q = b.q, n = b.n, sl = b.sl } end
    return nil
end

-- every item we have a day candle of
function H.EachItem(fn)
    local r = FT.R()
    local seen = {}
    for itemID in pairs(r.today) do
        seen[itemID] = true
        fn(itemID)
    end
    for itemID in pairs(r.days) do
        if not seen[itemID] then fn(itemID) end
    end
end

-- the last `n` day candles of an item (cheap: reads only the end of its history) and today's
function H.Recent(itemID, n)
    local out = RecentDays(itemID, n)
    local tr = Today(itemID)
    if tr then
        out[#out + 1] = { day = tr.d, o = tr.o, h = tr.h, l = tr.l, c = tr.c, q = tr.q, n = tr.n }
    end
    -- the days only Auctionator has (from before you scanned yourself): closing at their lowest price,
    -- the same as the day charts do
    if FT.Atr.On() then
        local atr = FT.Atr.Daily(itemID, FT.Day() - n + 1)
        if atr then
            local have, added = {}, false
            for _, r in ipairs(out) do have[r.day] = true end
            for d, row in pairs(atr) do
                if not have[d] then
                    out[#out + 1] = { day = d, o = row.low, h = row.high, l = row.low, c = row.low, q = row.qty }
                    added = true
                end
            end
            if added then table.sort(out, function(a, b) return a.day < b.day end) end
        end
    end
    return out
end

-- prune everything once after login (and an auction house's data the first time it is switched to), a little
-- each frame
local pruned = {}
local function PruneAll()
    local key = FT.houseKey
    if not key or pruned[key] then return end
    pruned[key] = true
    local r = FT.R()
    local ids = {}
    for itemID in pairs(r.snaps) do ids[#ids + 1] = { "s", itemID } end
    for itemID in pairs(r.days) do ids[#ids + 1] = { "d", itemID } end
    local i = 1
    local ticker
    ticker = C_Timer.NewTicker(0.05, function()
        for _ = 1, 60 do
            local job = ids[i]
            -- done, or the other house is on now (its own pruning follows)
            if not job or FT.houseKey ~= key then
                if job then pruned[key] = nil end
                ticker:Cancel()
                return
            end
            if job[1] == "s" then
                local s = H.Snaps(job[2])
                if s then PruneSnaps(job[2], s) end
                cache[job[2]] = nil
            else
                PruneDays(job[2])
                daysCache[job[2]] = nil
            end
            i = i + 1
        end
    end)
end
FT.On("FT_READY", PruneAll)

---------------------------------------------------------------------------
-- Order books (the listings of an item at each price)
---------------------------------------------------------------------------
local books = {} -- this session, every item
local MAX_LEVELS = 30

-- book = { t, levels = { {price, qty, auctions}, ... } cheapest first, auctions, qty, sellers, source, partial }
function H.SetBook(itemID, book)
    books[itemID] = book
    if not H.Tracked(itemID) then return end
    local parts = { Enc(Minutes(book.t)) .. "," .. Enc(book.auctions or 0) .. "," .. Enc(book.qty or 0) .. ","
        .. Enc(book.sellers or 0) .. "," .. (book.source or "") .. ";" }
    for i = 1, math.min(#book.levels, MAX_LEVELS) do
        local lv = book.levels[i]
        parts[#parts + 1] = Enc(lv[1]) .. "," .. Enc(lv[2]) .. "," .. Enc(lv[3] or 0) .. ";"
    end
    FT.R().books[itemID] = table.concat(parts)
end

local function ParseBook(str)
    local book
    for rec in str:gmatch("([^;]+);") do
        if not book then
            local t, a, q, s, src = rec:match("^(%w+),(%w+),(%w+),(%w+),(%w*)$")
            if not t then return nil end
            book = { t = Dec(t) * 60 + EPOCH, auctions = Dec(a), qty = Dec(q), sellers = Dec(s), source = src, levels = {} }
        else
            local p, q, n = rec:match("^(%w+),(%w+),(%w+)$")
            if p then book.levels[#book.levels + 1] = { Dec(p), Dec(q), Dec(n) } end
        end
    end
    return book
end

function H.Book(itemID)
    local b = books[itemID]
    if b then return b end
    local str = FT.R().books[itemID]
    if str then
        b = ParseBook(str)
        if b then
            books[itemID] = b
            return b
        end
    end
    -- Mastercraft's scan knows the price steps of the items on its shopping lists
    if FT.MC and FT.MC.Loaded() then
        local p, t, listed, tiers = FT.MC.Price(itemID)
        if p and type(tiers) == "table" and #tiers > 0 then
            local levels = {}
            for _, tier in ipairs(tiers) do levels[#levels + 1] = { tier[1], tier[2], 0 } end
            return { t = t, levels = levels, qty = listed, source = "mastercraft" }
        end
    end
    return nil
end

-- what buying `qty` costs walking up the book: total, enough, average
function H.CostToBuy(itemID, qty)
    local book = H.Book(itemID)
    if not book or #book.levels == 0 then return nil end
    local left, cost = qty, 0
    for _, lv in ipairs(book.levels) do
        local take = math.min(left, lv[2])
        cost = cost + take * lv[1]
        left = left - take
        if left <= 0 then break end
    end
    if left > 0 then
        cost = cost + left * book.levels[#book.levels][1]
        return cost, false, cost / qty
    end
    return cost, true, cost / qty
end

-- Each auction house's session caches apart: those of the house on are in use (the other house's prices on, or an
-- item window looking at the other house for a moment - FT.House.With - switches them there and back)
local sets, setKey = {}, nil
local function UseSet()
    local key = FT.houseKey or "?"
    if key == setKey then return end
    if setKey then
        sets[setKey] = { cache = cache, latest = latest, before = before, books = books, today = todayCache, days = daysCache }
    end
    local s = sets[key]
    if s then
        cache, latest, before, books, todayCache, daysCache = s.cache, s.latest, s.before, s.books, s.today, s.days
    else
        cache, latest, before, books, todayCache, daysCache = {}, {}, {}, {}, {}, {}
    end
    setKey = key
end
-- what was read before is of the house on at login
FT.On("FT_LOGIN", function() setKey = FT.houseKey end)
FT.On("FT_HOUSE_USE", UseSet)
FT.On("FT_HOUSE_CHANGED", function()
    UseSet()
    C_Timer.After(5, PruneAll)
end)

-- forget all of our history of this server (of the auction house on)
function H.ClearAll()
    local r = FT.R()
    r.snaps, r.books, r.scans, r.days, r.today, r.listed, r.sales = {}, {}, {}, {}, {}, nil, nil
    r.meta.listedAt = nil
    wipe(cache)
    wipe(latest)
    wipe(before)
    wipe(books)
    wipe(todayCache)
    wipe(daysCache)
    FT.Fire("FT_DATA_CLEARED")
    FT.Fire("FT_PRICES_CHANGED", "clear")
end

-- items with history, and the size of what is saved (characters)
function H.Footprint()
    local r = FT.R()
    local items, size, seen = 0, 0, {}
    for id, str in pairs(r.today) do
        seen[id] = true
        items = items + 1
        size = size + #str
    end
    for id, str in pairs(r.days) do
        if not seen[id] then items = items + 1 end
        size = size + #str
    end
    for _, str in pairs(r.snaps) do size = size + #str end
    for _, str in pairs(r.books) do size = size + #str end
    return items, size
end

---------------------------------------------------------------------------
-- Scan log (the whole market after each full scan) and scan times
---------------------------------------------------------------------------
-- in time order (a scan received from someone else may be older than our last one)
function H.LogScan(entry)
    local scans = FT.R().scans
    local i = #scans + 1
    while i > 1 and (scans[i - 1].t or 0) > (entry.t or 0) do i = i - 1 end
    table.insert(scans, i, entry)
    while #scans > 300 do table.remove(scans, 1) end
end

-- a logged scan within a minute of `t` (the same scan heard twice)
function H.HasScan(t)
    for _, s in ipairs(FT.R().scans) do
        if s.t and math.abs(s.t - t) < 60 then return true end
    end
    return false
end

-- kind: "full", "mine" or "peer" (a whole-market scan received from another ForeverTrading user)
function H.MarkScan(kind, t)
    local meta = FT.R().meta
    t = t or time()
    meta.lastScan = math.max(meta.lastScan or 0, t)
    if kind == "full" then meta.lastFull = t end
    if kind == "mine" then meta.lastMine = t end
    if kind == "peer" then meta.lastPeer = math.max(meta.lastPeer or 0, t) end
end

function H.LastScan(kind)
    local meta = FT.R().meta
    if kind == "full" then return meta.lastFull end
    if kind == "mine" then return meta.lastMine end
    if kind == "peer" then return meta.lastPeer end
    return meta.lastScan
end

-- the time of the newest prices of the whole market we have: our full scan or one received
function H.MarketTime()
    local meta = FT.R().meta
    return math.max(meta.lastFull or 0, meta.lastPeer or 0)
end

---------------------------------------------------------------------------
-- The price now: price, time it was seen, source, listed now, gone
---------------------------------------------------------------------------
function FT.Price(itemID)
    if not itemID then return nil end
    local l = latest[itemID]
    if l and l.p then return l.p, l.t, l.source, l.q, l.gone end
    local tr = Today(itemID)
    if tr then return tr.c, tr.m * 60 + EPOCH, "history", tr.q end
    local recent = RecentDays(itemID, 1)
    local last = recent[#recent]
    if last then return last.c, FT.DayStart(last.day) + 43200, "history", last.q end
    if FT.S.useAuctionator and FT.Atr.Loaded() then
        local e = FT.Atr.Entry(itemID)
        if e and type(e.m) == "number" and e.m > 0 then
            local lastDay = FT.Atr.LastDay(e)
            local t = lastDay and math.min(time(), FT.DayStart(lastDay) + 43200) or nil
            return e.m, t, "auctionator", e.a and lastDay and e.a[tostring(lastDay)]
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Either auction house (House.lua): the one on as this session saw it, the other as it was saved (nothing of
-- it is in this session's caches) - for the deals between the two
---------------------------------------------------------------------------
local function TailDays(str, n)
    if type(str) ~= "string" then return {} end
    local tail = str
    if #str > n * 44 then
        tail = str:sub(-n * 44)
        local cut = tail:find(";", 1, true)
        tail = cut and tail:sub(cut + 1) or ""
    end
    local out = ParseDays(tail)
    while #out > n do table.remove(out, 1) end
    return out
end

-- its data (nil: never scanned there)
local function RealmIn(house)
    if house == FT.house then return FT.R() end
    return FT.db.realms[FT.HouseKey(house)]
end

-- the lowest price there, when it was seen, how many were listed (nil: not seen there, or none left)
function H.PriceIn(house, itemID)
    if house == FT.house then
        local l = latest[itemID]
        if l and l.p then
            if l.gone then return nil end
            return l.p, l.t, l.q
        end
    end
    local r = RealmIn(house)
    if not r then return nil end
    local tr = r.today and ParseToday(r.today[itemID])
    if tr then return tr.c, tr.m * 60 + EPOCH, tr.q end
    local last = TailDays(r.days and r.days[itemID], 1)[1]
    if last then return last.c, FT.DayStart(last.day) + 43200, last.q end
    return nil
end

-- the closes of its last `n` days there (today's the last), oldest first
function H.ClosesIn(house, itemID, n)
    local r = RealmIn(house)
    if not r then return {} end
    local out = {}
    for _, d in ipairs(TailDays(r.days and r.days[itemID], n)) do out[#out + 1] = d.c end
    local tr = r.today and ParseToday(r.today[itemID])
    if tr then out[#out + 1] = tr.c end
    while #out > n do table.remove(out, 1) end
    return out
end

-- its order book there (saved for the items that matter to you; of the house on, this session's too)
function H.BookIn(house, itemID)
    if house == FT.house then return H.Book(itemID) end
    local r = RealmIn(house)
    local str = r and r.books and r.books[itemID]
    return str and ParseBook(str) or nil
end

-- when the whole market there was last seen (a full scan, or one received), nil: never
function H.MarketTimeIn(house)
    local r = RealmIn(house)
    local meta = r and r.meta
    if not meta then return nil end
    local t = math.max(meta.lastFull or 0, meta.lastPeer or 0, meta.lastScan or 0)
    return t > 0 and t or nil
end

---------------------------------------------------------------------------
-- Candles
---------------------------------------------------------------------------
-- day candles for the last `days` days: { t, day, o, h, l, c, v, n, own }
-- Ours are complete; a day only Auctionator has (before you scanned yourself) gets its low and high,
-- closes at its low (what you could buy for) and opens at the close before it.
function H.Daily(itemID, days)
    local today = FT.Day()
    local from = today - (days or 60) + 1
    local map = {}
    for _, r in ipairs(Days(itemID)) do
        if r.day >= from then
            map[r.day] = { day = r.day, o = r.o, h = r.h, l = r.l, c = r.c, v = r.q, n = r.n, own = true }
        end
    end
    local tr = Today(itemID)
    if tr and tr.d >= from then
        map[tr.d] = { day = tr.d, o = tr.o, h = tr.h, l = tr.l, c = tr.c, v = tr.q, n = tr.n, own = true }
    end
    if FT.S.useAuctionator and FT.Atr.Loaded() then
        local atr = FT.Atr.Daily(itemID, from)
        if atr then
            for d, row in pairs(atr) do
                if not map[d] then map[d] = { day = d, h = row.high, l = row.low, v = row.qty } end
            end
        end
    end
    local keys = {}
    for d in pairs(map) do keys[#keys + 1] = d end
    table.sort(keys)
    local out, prevC = {}, nil
    for _, d in ipairs(keys) do
        local c = map[d]
        if not c.c then c.c = c.l end
        if not c.o then c.o = prevC or c.h end
        c.h = math.max(c.h or c.c, c.o, c.c)
        c.l = math.min(c.l or c.c, c.o, c.c)
        c.t = FT.DayStart(d)
        prevC = c.c
        out[#out + 1] = c
    end
    -- the newest price of today closes today's candle
    local last = out[#out]
    local l = latest[itemID]
    if last and last.day == today and l and l.p and not l.gone then
        last.c = l.p
        last.h = math.max(last.h, l.p)
        last.l = math.min(last.l, l.p)
    end
    return out
end

-- candles of `bucket` seconds from the intraday observations
function H.Intraday(itemID, bucket, maxCount)
    local s = H.Snaps(itemID)
    local out = {}
    if not s or #s.t == 0 then return out end
    local cur
    for i = 1, #s.t do
        local b = math.floor(s.t[i] / bucket) * bucket
        local p = s.p[i]
        if not cur or cur.t ~= b then
            cur = { t = b, o = p, h = p, l = p, c = p, v = s.q[i], n = s.n[i], own = true }
            out[#out + 1] = cur
        else
            cur.c = p
            if p > cur.h then cur.h = p end
            if p < cur.l then cur.l = p end
            if s.q[i] then cur.v = math.max(cur.v or 0, s.q[i]) end
            if s.n[i] then cur.n = s.n[i] end
        end
    end
    if maxCount and #out > maxCount then
        local trimmed = {}
        for i = #out - maxCount + 1, #out do trimmed[#trimmed + 1] = out[i] end
        out = trimmed
    end
    return out
end

-- week candles from day candles
local function Weekly(daily)
    local out, cur = {}, nil
    for _, d in ipairs(daily) do
        local w = math.floor((d.day + 2) / 7) -- weeks start on Monday (day 0 = Wed 2020-01-01, day 5 = Monday)
        if not cur or cur.week ~= w then
            cur = { week = w, t = d.t, o = d.o, h = d.h, l = d.l, c = d.c, v = d.v }
            out[#out + 1] = cur
        else
            cur.c = d.c
            cur.h = math.max(cur.h, d.h)
            cur.l = math.min(cur.l, d.l)
            if d.v then cur.v = math.max(cur.v or 0, d.v) end
        end
    end
    return out
end

-- candles for a chart: tf = "1H", "4H", "1D", "1W"
function H.Series(itemID, tf)
    if tf == "1H" then return H.Intraday(itemID, 3600, 240) end
    if tf == "4H" then return H.Intraday(itemID, 14400, 240) end
    if tf == "1W" then return Weekly(H.Daily(itemID, 365)) end
    return H.Daily(itemID, 120)
end
