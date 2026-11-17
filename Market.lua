-- ForeverTrading: the whole market at a glance - every item seen on the auction house (by our scans, and
-- by Auctionator and Mastercraft when they are on), its price, how it moved in a day and a week, top movers,
-- the market mood, the watchlist and its price alerts.
local ADDON, FT = ...
local L = FT.L

local M = {}
FT.Market = M

local rows, byID = nil, {}
local building = false
local builtAt = 0
local CHUNK = 500
local SPARK_DAYS = 14

-- a row: { id, price, ch1, ch7, qty, spark = { prices }, days, lastDay, cls, sub, gone }

-- from our own day candles
local function RowFromOwn(id, today)
    local rec = FT.Hist.Recent(id, SPARK_DAYS + 1)
    if #rec == 0 then return nil end
    local price, _, _, listed, gone = FT.Price(id)
    if not price then return nil end
    local spark, ref1, ref7, days = {}, nil, nil, 0
    for _, r in ipairs(rec) do
        if r.day >= today - SPARK_DAYS then
            spark[#spark + 1] = r.c
            days = days + 1
        end
        if r.day <= today - 1 then ref1 = r.c end
        if r.day <= today - 7 then ref7 = r.c end
    end
    local lastDay = rec[#rec].day
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

function M.Rebuild()
    if building then
        M.again = true
        return
    end
    -- which source each item is read from: ours first, then Auctionator's, then Mastercraft's
    local jobs, seen = {}, {}
    FT.Hist.EachItem(function(id)
        if not seen[id] then
            seen[id] = true
            jobs[#jobs + 1] = { id, "own" }
        end
    end)
    local db = FT.Atr.DB()
    if db then
        for k, e in pairs(db) do
            local id = tonumber(k)
            if id and not seen[id] and type(e) == "table" then
                seen[id] = true
                jobs[#jobs + 1] = { id, "atr" }
            end
        end
    end
    if FT.MC.Loaded() then
        local book = FT.MC.Book()
        for id in pairs(book and type(book.items) == "table" and book.items or {}) do
            if type(id) == "number" and not seen[id] then
                seen[id] = true
                jobs[#jobs + 1] = { id, "mc" }
            end
        end
    end
    building = true
    local today = FT.Day()
    local dayKeys = {}
    for i = 0, SPARK_DAYS do dayKeys[i] = tostring(today - SPARK_DAYS + i) end
    local newRows, newByID = {}, {}
    local i = 1
    local ticker
    ticker = C_Timer.NewTicker(0, function()
        local last = math.min(i + CHUNK - 1, #jobs)
        for k = i, last do
            local id, src = jobs[k][1], jobs[k][2]
            local row
            if src == "own" then
                row = RowFromOwn(id, today)
            elseif src == "atr" then
                local e = db[tostring(id)]
                if type(e) == "table" then row = RowFromAuctionator(id, e, today, dayKeys) end
            else
                row = RowFromMastercraft(id)
            end
            if row then
                newRows[#newRows + 1] = row
                newByID[id] = row
            end
        end
        i = last + 1
        if i > #jobs then
            ticker:Cancel()
            rows, byID = newRows, newByID
            building = false
            builtAt = time()
            FT.Fire("FT_MARKET_READY")
            if M.again then
                M.again = false
                C_Timer.After(1, M.Rebuild)
            end
        end
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
    local row = byID[id]
    if not row or building then return end
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
FT.On("FT_SCAN_DONE", function() FT.Debounce("marketRebuild", 1, M.Rebuild) end)
FT.On("FT_PRICES_CHANGED", function() FT.Debounce("marketRebuild", 4, M.Rebuild) end)

-- items worth showing in movers: listed on several days, not dirt cheap
local function Liquid(r)
    return r.days >= 3 and r.price >= 100 and (r.qty == nil or r.qty >= 3)
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

function M.Movers(n, field, descending)
    local list = {}
    for _, r in ipairs(rows or {}) do
        if r[field] and Liquid(r) and Plausible(r[field]) then list[#list + 1] = r end
    end
    table.sort(list, function(a, b)
        if descending then return a[field] > b[field] end
        return a[field] < b[field]
    end)
    local out = {}
    for i = 1, math.min(n, #list) do out[i] = list[i] end
    return out
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
