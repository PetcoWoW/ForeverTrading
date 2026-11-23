-- ForeverTrading: the whole market at a glance - every item seen on the auction house (by our scans, and
-- by Auctionator and Mastercraft when they are on), its price, how it moved in a day and a week, top movers,
-- the market mood, the watchlist and its price alerts.
local ADDON, FT = ...
local L = FT.L

local M = {}
FT.Market = M

local rows, byID = nil, {}
local building = false
local builtAt, builtDay = 0, nil
local SPARK_DAYS = 14
local FULL_EVERY = 600 -- every item again at least this often (prices age, Auctionator's days move on)
-- days of prices an item needs to be a mover: 3, fewer while the auction house itself was scanned on fewer days
-- (a new market, or Auctionator off: only our own scans count) - set at each build
local needDays = 3
local marketDay = nil -- the day the whole market was seen last (set at each build)

-- a row: { id, price, ch1, ch7, qty, spark = { prices }, days, lastDay, cls, sub, gone }

-- from our own day candles
local function RowFromOwn(id, today)
    local rec = FT.Hist.Recent(id, SPARK_DAYS + 1)
    if #rec == 0 then return nil end
    local price, _, _, listed, gone = FT.Price(id)
    if not price then return nil end
    local last = rec[#rec]
    local lastDay = last.day
    -- the day its changes are counted to: today - or, before the market is scanned today, the last day it was
    -- (the moves of that day, not its price against itself)
    local base = today
    if lastDay < today and lastDay == marketDay then base = lastDay end
    local spark, ref1, ref7, days = {}, nil, nil, 0
    local weekFirst -- the first close of that week before that day
    for _, r in ipairs(rec) do
        if r.day >= today - SPARK_DAYS then
            spark[#spark + 1] = r.c
            days = days + 1
        end
        if r.day <= base - 1 then ref1 = r.c end
        if r.day <= base - 7 then ref7 = r.c end
        if not weekFirst and r.day > base - 7 and r.day <= base - 1 then weekFirst = r.c end
    end
    -- No day before it known (a new market or a new item, Auctionator off: nothing older than our own scans):
    -- the change since that day's first price - when it moved that day at all (seen more than once).
    local dayOpen = lastDay == base and last.o and last.h ~= last.l and last.o or nil
    ref1 = ref1 or dayOpen
    -- no close a week old: the change since the first day of that week known (or that day's first price)
    ref7 = ref7 or weekFirst or dayOpen
    if #spark > 0 and lastDay == today then spark[#spark] = price end
    local cls, sub = FT.ItemClass(id)
    return {
        id = id, price = price, ch1 = ref1 and (price / ref1 - 1) or nil, ch7 = ref7 and (price / ref7 - 1) or nil,
        qty = listed, spark = spark, days = days, lastDay = lastDay, cls = cls, sub = sub, gone = gone,
    }
end

-- an item only Auctionator has seen (from before you scanned with ForeverTrading)
local function RowFromAuctionator(id, e, today, dayKeys)
    local m = type(e.m) == "number" and e.m > 0 and e.m or nil
    if not m then return nil end
    local h, l, a = e.h or {}, e.l or {}, e.a
    local spark, lastDay, ref1, ref7, days = {}, nil, nil, nil, 0
    for i = 0, SPARK_DAYS do
        local d = today - SPARK_DAYS + i
        local dk = dayKeys[i]
        local v = l[dk] or h[dk]
        if v then
            spark[#spark + 1] = v
            lastDay = d
            days = days + 1
            if d <= today - 1 then ref1 = v end
            if d <= today - 7 then ref7 = v end
        end
    end
    if not lastDay then lastDay = FT.Atr.LastDay(e) end
    local price = m
    local own = FT.Hist.Latest(id)
    local atrT = lastDay and math.min(time(), FT.DayStart(lastDay) + 43200) or 0
    if own and own.p and (own.t or 0) >= atrT then price = own.p end
    if #spark > 0 and lastDay == today then spark[#spark] = price end
    local cls, sub = FT.ItemClass(id)
    return {
        id = id, price = price, ch1 = ref1 and (price / ref1 - 1) or nil, ch7 = ref7 and (price / ref7 - 1) or nil,
        qty = a and lastDay and a[tostring(lastDay)] or nil, spark = spark, days = days, lastDay = lastDay,
        cls = cls, sub = sub,
    }
end

-- an item only Mastercraft's scan has
local function RowFromMastercraft(id)
    local p, t, listed = FT.MC.Price(id)
    if not p then return nil end
    local cls, sub = FT.ItemClass(id)
    return { id = id, price = p, qty = listed, spark = {}, days = 0, lastDay = t and FT.Day(t), cls = cls, sub = sub }
end

local function BuildRow(id, src, today, dayKeys, db)
    if src == "own" then return RowFromOwn(id, today) end
    if src == "atr" then
        local e = db[tostring(id)]
        return type(e) == "table" and RowFromAuctionator(id, e, today, dayKeys) or nil
    end
    return RowFromMastercraft(id)
end

local function SetNeedDays()
    -- the days of the last two weeks the whole market was seen on
    needDays = math.max(1, math.min(3, FT.Hist.WatchedDays(SPARK_DAYS)))
    local t = FT.Hist.MarketTime()
    marketDay = (t and t > 0) and FT.Day(t) or nil
end

-- asked for again while it was building: after it ("all": every item, otherwise the changed ones)
local function Again()
    local what = M.again
    if not what then return end
    M.again = nil
    C_Timer.After(1, what == "all" and M.Rebuild or M.Refresh)
end

function M.Rebuild()
    if building then
        M.again = "all"
        return
    end
    -- every item is read again: what changed so far is in it
    FT.Hist.TakeChanged("market")
    -- which source each item is read from: ours first, then Auctionator's, then Mastercraft's
    local ids, srcs, seen = {}, {}, {}
    local function Add(id, src)
        seen[id] = true
        ids[#ids + 1], srcs[#srcs + 1] = id, src
    end
    FT.Hist.EachItem(function(id)
        if not seen[id] then Add(id, "own") end
    end)
    local db = FT.Atr.DB()
    if db then
        for k, e in pairs(db) do
            local id = tonumber(k)
            if id and not seen[id] and type(e) == "table" then Add(id, "atr") end
        end
    end
    if FT.MC.Loaded() then
        local book = FT.MC.Book()
        for id in pairs(book and type(book.items) == "table" and book.items or {}) do
            if type(id) == "number" and not seen[id] then Add(id, "mc") end
        end
    end
    building = true
    M.errors, M.firstError = 0, nil
    local today = FT.Day()
    SetNeedDays()
    local dayKeys = {}
    for i = 0, SPARK_DAYS do dayKeys[i] = tostring(today - SPARK_DAYS + i) end
    local newRows, newByID = {}, {}
    FT.Job("market", #ids, function(k)
        local id = ids[k]
        -- one item that fails must not stop the market (it would stay unbuilt)
        local ok, row = pcall(BuildRow, id, srcs[k], today, dayKeys, db)
        if not ok then
            M.errors = M.errors + 1
            M.firstError = M.firstError or tostring(row)
            row = nil
        end
        if row then
            newRows[#newRows + 1] = row
            newByID[id] = row
        end
    end, function()
        rows, byID = newRows, newByID
        building = false
        builtAt, builtDay = time(), today
        FT.Fire("FT_MARKET_READY")
        Again()
    end)
end

-- after new prices: only the items whose prices came in (every item when most did, on a new day, now and then)
function M.Refresh()
    if building then
        M.again = M.again or "changed"
        return
    end
    if not rows or builtDay ~= FT.Day() or time() - builtAt > FULL_EVERY then return M.Rebuild() end
    local set, n, all = FT.Hist.TakeChanged("market")
    if all or n > #rows / 2 then return M.Rebuild() end
    if n == 0 then return end
    local ids = {}
    for id in pairs(set) do ids[#ids + 1] = id end
    building = true
    local today = FT.Day()
    SetNeedDays()
    FT.Job("market+", #ids, function(k)
        local id = ids[k]
        local ok, fresh = pcall(RowFromOwn, id, today)
        if not ok then
            M.errors = (M.errors or 0) + 1
            M.firstError = M.firstError or tostring(fresh)
            return
        end
        if not fresh then return end
        local row = byID[id]
        if row then
            -- in place: the lists on screen keep it
            for key in pairs(row) do row[key] = nil end
            for key, v in pairs(fresh) do row[key] = v end
        else
            rows[#rows + 1] = fresh
            byID[id] = fresh
        end
    end, function()
        building = false
        FT.Fire("FT_MARKET_READY")
        Again()
    end)
end

function M.Rows()
    return rows
end

function M.Row(id)
    return byID[id]
end

-- one item's row again (its live price): the list keeps its place
function M.Touch(id)
    if building then
        -- the rows are being made: this one again after them
        FT.Hist.MarkChanged("market", id)
        M.again = M.again or "changed"
        return
    end
    local row = byID[id]
    if not row then return end
    local fresh = RowFromOwn(id, FT.Day())
    if fresh then
        for k in pairs(row) do row[k] = nil end
        for k, v in pairs(fresh) do row[k] = v end
    end
end

function M.Building()
    return building
end

function M.EnsureFresh()
    if not rows or (time() - builtAt > 600) then M.Rebuild() end
end

FT.On("FT_READY", function() C_Timer.After(3, M.Rebuild) end)
-- the changed items (everything when it's a whole market or another auction house: FT.Hist.TakeChanged says)
FT.On("FT_SCAN_DONE", function() FT.Debounce("marketRebuild", 1, M.Refresh) end)
FT.On("FT_PRICES_CHANGED", function() FT.Debounce("marketRebuild", 4, M.Refresh) end)
FT.On("FT_SOURCES_CHANGED", function() FT.Debounce("marketRebuild", 1, M.Refresh) end)
FT.On("FT_HOUSE_CHANGED", function() FT.Debounce("marketRebuild", 0.1, M.Refresh) end)

-- items worth showing in movers: listed on several days (as many as the market was seen on, up to 3), not dirt cheap
local function Liquid(r)
    return r.days >= needDays and r.price >= 100 and (r.qty == nil or r.qty >= 3)
end

-- the most valuable listings (price x quantity), for when there are no moves yet
function M.TopByValue(n)
    local list = {}
    for _, r in ipairs(rows or {}) do
        if r.qty and r.price >= 100 then list[#list + 1] = r end
    end
    table.sort(list, function(a, b)
        local va, vb = a.price * a.qty, b.price * b.qty
        if va ~= vb then return va > vb end
        return a.id < b.id
    end)
    local out = {}
    for i = 1, math.min(n, #list) do out[i] = list[i] end
    return out
end

-- a move this big is a mispriced listing (1c instead of 1g), not the market moving
local function Plausible(ch)
    return ch >= -0.9 and ch <= 3
end

-- the biggest moves: up (descending) - only what rose - or down - only what fell
function M.Movers(n, field, descending)
    local list = {}
    for _, r in ipairs(rows or {}) do
        local v = r[field]
        if v and ((descending and v > 0) or (not descending and v < 0)) and Liquid(r) and Plausible(v) then
            list[#list + 1] = r
        end
    end
    table.sort(list, function(a, b)
        if descending then return a[field] > b[field] end
        return a[field] < b[field]
    end)
    local out = {}
    for i = 1, math.min(n, #list) do out[i] = list[i] end
    return out
end

-- how far back the prices go: items, items with prices on 3+ days of the last two weeks, items that can be movers
function M.Depth()
    local deep, movers = 0, 0
    for _, r in ipairs(rows or {}) do
        if r.days >= 3 then deep = deep + 1 end
        if r.ch1 and r.ch1 ~= 0 and Liquid(r) and Plausible(r.ch1) then movers = movers + 1 end
    end
    return rows and #rows or 0, deep, movers
end

-- the market's mood: share of liquid items that went up this week (0-100), and how many were counted
function M.Mood()
    local up, total = 0, 0
    for _, r in ipairs(rows or {}) do
        if r.ch7 and Liquid(r) then
            total = total + 1
            if r.ch7 > 0 then up = up + 1 end
        end
    end
    if total < 10 then return nil, total end
    return math.floor(up / total * 100 + 0.5), total
end

function M.MoodText(v)
    if not v then return L["no data"], "muted" end
    if v >= 75 then return L["Extreme greed"], "up" end
    if v >= 55 then return L["Greed"], "up" end
    if v > 45 then return L["Neutral"], "muted" end
    if v > 25 then return L["Fear"], "down" end
    return L["Extreme fear"], "down"
end

---------------------------------------------------------------------------
-- Watchlist and price alerts
---------------------------------------------------------------------------
function M.IsWatched(id)
    return FT.db.watch[id] ~= nil
end

function M.ToggleWatch(id)
    if FT.db.watch[id] then
        FT.db.watch[id] = nil
    else
        FT.db.watch[id] = { added = time() }
    end
    FT.Fire("FT_WATCH_CHANGED", id)
end

-- kind: "above" / "below"; value in copper or nil to clear
function M.SetAlert(id, kind, value)
    local w = FT.db.watch[id]
    if not w then
        w = { added = time() }
        FT.db.watch[id] = w
    end
    w[kind] = value
    w.state = nil
    FT.Fire("FT_WATCH_CHANGED", id)
end

local function Alert(id, text)
    if FT.Toast then FT.Toast(id, text) end
    if FT.S.alertChat then
        local _, _, _, _, link = FT.Item(id)
        FT.Print((link or FT.ItemText(id)) .. " " .. text)
    end
    if FT.S.alertSound then
        pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959)
    end
end

function M.CheckAlerts()
    for id, w in pairs(FT.db.watch) do
        if w.above or w.below then
            local price = FT.Price(id)
            if price then
                local state
                if w.below and price <= w.below then
                    state = "below"
                elseif w.above and price >= w.above then
                    state = "above"
                end
                if state and state ~= w.state then
                    if state == "below" then
                        Alert(id, string.format(L["fell to %s (alert: %s or less)"], FT.Money(price), FT.Money(w.below)))
                    else
                        Alert(id, string.format(L["rose to %s (alert: %s or more)"], FT.Money(price), FT.Money(w.above)))
                    end
                end
                w.state = state
            end
        end
    end
end

FT.On("FT_SCAN_DONE", function() FT.Debounce("alerts", 2, M.CheckAlerts) end)
FT.On("FT_PRICES_CHANGED", function() FT.Debounce("alerts", 2, M.CheckAlerts) end)
FT.On("FT_LIVE_UPDATED", function() FT.Debounce("alerts", 2, M.CheckAlerts) end)
