-- Wolf of Booty Bay: the whole market at a glance - every item seen on the auction house (by our scans, and
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

-- an item only Auctionator has seen (from before you scanned with this addon)
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

local function BuildRow(id, src, today, dayKeys, db)
    if src == "own" then return RowFromOwn(id, today) end
    if src == "atr" then
        local e = db[tostring(id)]
        return type(e) == "table" and RowFromAuctionator(id, e, today, dayKeys) or nil
    end
    return nil
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
    -- which source each item is read from: ours first, then Auctionator's
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
        if M.ForgetMovers then M.ForgetMovers() end -- some rows changed in place: the movers again
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

-- A real market, for the biggest moves and the banners: it sells 3+ a day, 1g+ a day changes hands and 5+ are
-- up. A 4-silver item with one sale a day "up 300%" (1c to 4c), or a 5g item "down 90%" after one 50g listing,
-- is noise. Known sales come from the price feed and your scans; with none known, a market isn't counted solid.
local function Solid(r)
    if not Liquid(r) or (r.qty or 0) < 5 then return false end
    if r.perDay == nil then
        local s = FT.Sales.Rate(r.id)
        r.perDay = (s and (s.sold or 0) >= 5) and s.perDay or false
    end
    if not (r.perDay and r.perDay >= 3 and r.price * r.perDay >= 10000) then return false end
    -- yesterday's close must look like the days before it (within 50% of their median): a move "down 85%" from
    -- one overpriced day is no move
    if r.sane == nil then
        local s = FT.An.Stats(r.id)
        local today, before, yest = FT.Day(), {}, nil
        for _, c in ipairs(s.daily or {}) do
            if c.day == today - 1 then yest = c.c
            elseif c.day < today - 1 and c.day >= today - 8 then before[#before + 1] = c.c end
        end
        if yest and #before >= 3 then
            table.sort(before)
            local med = before[math.floor((#before + 1) / 2)]
            r.sane = med > 0 and yest >= med * 0.5 and yest <= med * 1.5
        else
            r.sane = yest ~= nil
        end
    end
    return r.sane
end
M.Solid = Solid

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
-- The biggest moves. The cheap tests first, the biggest first, and the costly one (Solid: sales, the week before)
-- only until n are found - not on all 7,000 items (that was a long frame every time the Terminal showed).
-- Worked out once per market build, in the background (M.PrepareMovers): the top 40 each way, each a real
-- market (Solid reads sales and the week before - too much for one frame across thousands of items). Until it's
-- ready, the cheap tests alone.
local moversCache = setmetatable({}, { __mode = "k" })
local MOVERS_KEPT = 40
function M.ForgetMovers() if rows then moversCache[rows] = nil end end

local function Candidates(field, descending)
    local list = {}
    for _, r in ipairs(rows or {}) do
        local v = r[field]
        if v and ((descending and v > 0) or (not descending and v < 0)) and Plausible(v) and Liquid(r) and (r.qty or 0) >= 5 then
            list[#list + 1] = r
        end
    end
    table.sort(list, function(a, b)
        if descending then return a[field] > b[field] end
        return a[field] < b[field]
    end)
    return list
end

local preparing
function M.PrepareMovers()
    if not rows or preparing then return end
    local forRows = rows
    local sets = {}
    for _, spec in ipairs({ { "ch1", true }, { "ch1", false }, { "ch7", true }, { "ch7", false } }) do
        sets[#sets + 1] = { key = spec[1] .. (spec[2] and "+" or "-"), list = Candidates(spec[1], spec[2]), top = {}, i = 1 }
    end
    preparing = true
    -- one item's check per step, across the four lists, until each has its 40 (or runs out)
    local total = 0
    for _, set in ipairs(sets) do total = total + #set.list end
    local si = 1
    FT.Job("movers", total, function()
        local tries = 0
        while tries < #sets do
            local set = sets[si]
            si = si % #sets + 1
            if #set.top < MOVERS_KEPT and set.i <= #set.list then
                local r = set.list[set.i]
                set.i = set.i + 1
                if Solid(r) then set.top[#set.top + 1] = r end
                return
            end
            tries = tries + 1
        end
        return false -- every list is full or done
    end, nil)
    -- the job stops itself with false: finish when it's done
    local function Finish()
        for _, set in ipairs(sets) do
            if #set.top < MOVERS_KEPT and set.i <= #set.list then return C_Timer.After(0.2, Finish) end
        end
        preparing = false
        if rows ~= forRows then return end
        local byRows = {}
        for _, set in ipairs(sets) do byRows[set.key] = set.top end
        moversCache[forRows] = byRows
        FT.Fire("FT_MOVERS_READY")
    end
    C_Timer.After(0.2, Finish)
end
FT.On("FT_MARKET_READY", function() M.ForgetMovers(); C_Timer.After(0.5, M.PrepareMovers) end)

function M.Movers(n, field, descending)
    local byRows = rows and moversCache[rows]
    local top = byRows and byRows[field .. (descending and "+" or "-")]
    local out = {}
    if top then
        for i = 1, math.min(n, #top) do out[i] = top[i] end
        return out
    end
    -- not worked out yet: the cheap tests only (a moment after login)
    for _, r in ipairs(Candidates(field, descending)) do
        if #out >= n then break end
        out[#out + 1] = r
    end
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
    if FT.S.alertPopup and FT.Toast then FT.Toast(id, text) end
    if FT.S.alertChat then
        local _, _, _, _, link = FT.Item(id)
        FT.Print((link or FT.ItemText(id)) .. " " .. text)
    end
    if FT.S.alertSound and FT.S.alertPopup then
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

---------------------------------------------------------------------------
-- The meme layer: TO THE MOON / RUG PULL banners, whales and Market Makers
---------------------------------------------------------------------------
local MOON, RUG = 0.30, -0.30      -- a day's move this big gets a banner
local WHALE_SHARE = 0.5            -- one seller with this share of what's listed is a whale
local WHALE_MIN_VALUE = 500000     -- ... and at least 50g of it up
local MAX_BANNERS = 3              -- per market build

-- 0.42 -> "42%" (no sign: a size, not a move)
local function Whole(v) return string.format("%d%%", math.floor(math.abs(v) * 100 + 0.5)) end

-- what you own or watch: banners are about your stuff (and the market's single biggest move of the day)
local function Cares(id)
    return FT.db.watch[id] ~= nil or (FT.Port and FT.Port.Count(id) > 0)
end

-- Banners wait a moment and go out together: one chat line per kind (TO THE MOON: a +40%, b +35%), no pop-up
-- or sound unless Settings > Alerts > Pop-up alerts is on
local pending = {}
local function Flush()
    local byTitle, order = {}, {}
    for _, b in ipairs(pending) do
        if not byTitle[b.title] then
            byTitle[b.title] = { color = b.color }
            order[#order + 1] = b.title
        end
        local _, _, _, _, link = FT.Item(b.id)
        table.insert(byTitle[b.title], (link or FT.ItemText(b.id)) .. " " .. b.text)
        if FT.S.alertPopup and FT.Toast then FT.Toast(b.id, b.text, b.title, b.color) end
    end
    if FT.S.alertChat then
        for _, title in ipairs(order) do
            local g = byTitle[title]
            FT.Print(FT.C(g.color, title) .. "  " .. table.concat(g, FT.C("dim", "  ·  ")))
        end
    end
    if #pending > 0 and FT.S.alertPopup and FT.S.alertSound then
        pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959)
    end
    wipe(pending)
end
local function Banner(id, text, title, color)
    pending[#pending + 1] = { id = id, text = text, title = title, color = color }
    FT.Debounce("memeFlush", 1, Flush)
end

-- once a day per item and kind
local function Seen(id, kind)
    local day = FT.Day()
    local s = FT.db.memeSeen
    if not s or s.day ~= day then
        s = { day = day }
        FT.db.memeSeen = s
    end
    local key = kind .. id
    if s[key] then return true end
    s[key] = true
    return false
end

function M.CheckBanners()
    if FT.S.meme == false or not rows then return end
    local shown = 0
    -- the market's biggest each way: the cheap way (M.Movers tests only the top few fully)
    local topUp = M.Movers(1, "ch1", true)[1]
    local topDown = M.Movers(1, "ch1", false)[1]
    if topUp and topUp.ch1 < MOON then topUp = nil end
    if topDown and topDown.ch1 > RUG then topDown = nil end
    for _, r in ipairs(rows) do
        local ch = r.ch1
        -- a big move first (cheap), then yours, then a real market (costly) - in that order
        if ch and (ch >= MOON or ch <= RUG) and Plausible(ch) and Cares(r.id) and Solid(r) then
            if shown < MAX_BANNERS then
                if ch >= MOON and not Seen(r.id, "moon") then
                    Banner(r.id, string.format(L["up %s today"], Whole(ch)), L["TO THE MOON"], "up")
                    shown = shown + 1
                elseif ch <= RUG and not Seen(r.id, "rug") then
                    Banner(r.id, string.format(L["down %s today"], Whole(ch)), L["RUG PULL"], "down")
                    shown = shown + 1
                end
            end
        end
    end
    -- the market's biggest of the day, owned or not
    if shown < MAX_BANNERS and topUp and not Seen(0, "moon") and not Seen(topUp.id, "moon") then
        Banner(topUp.id, string.format(L["up %s today: the market's biggest"], Whole(topUp.ch1)), L["TO THE MOON"], "up")
        shown = shown + 1
    end
    if shown < MAX_BANNERS and topDown and not Seen(0, "rug") and not Seen(topDown.id, "rug") then
        Banner(topDown.id, string.format(L["down %s today: the market's biggest"], Whole(topDown.ch1)), L["RUG PULL"], "down")
    end
end

FT.On("FT_MOVERS_READY", function() FT.Debounce("meme", 1, M.CheckBanners) end)

-- Whales and Market Makers, from your own deep scans (Full scan): the Blizzard feed has no seller names.
-- R().whales = { t, items = { [itemID] = { n = seller, s = share, q = how many } } }
-- R().makers = { t, list = { { n, value, items, top = itemID } } }, the 20 with the most gold listed
local W = {}
FT.Whales = W
W.Whole = Whole

function W.FromScan(acc, t)
    local mine = {}
    for _, c in pairs(FT.db.chars) do if c.name then mine[c.name] = true end end
    local whales, byOwner = {}, {}
    for itemID, it in pairs(acc.items) do
        if it.byOwner and (it.qty or 0) > 0 then
            local price = FT.Price(itemID)
            if price and price > 0 then
                local topName, topQ = nil, 0
                for name, q in pairs(it.byOwner) do
                    if q > topQ then topName, topQ = name, q end
                    local o = byOwner[name]
                    if not o then
                        o = { n = name, value = 0, items = 0, topV = 0 }
                        byOwner[name] = o
                    end
                    local v = price * q
                    o.value, o.items = o.value + v, o.items + 1
                    if v > o.topV then o.top, o.topV = itemID, v end
                end
                local share = topQ / it.qty
                if topName and share >= WHALE_SHARE and price * topQ >= WHALE_MIN_VALUE and it.qty >= 5 then
                    whales[itemID] = { n = topName, s = math.floor(share * 100 + 0.5) / 100, q = topQ }
                end
            end
        end
    end
    local list = {}
    for _, o in pairs(byOwner) do
        list[#list + 1] = { n = o.n, value = math.floor(o.value), items = o.items, top = o.top, you = mine[o.n] or nil }
    end
    if #list == 0 then return end -- the scan gave no seller names: keep what we had
    table.sort(list, function(a, b) return a.value > b.value end)
    for i = #list, 21, -1 do list[i] = nil end
    local r = FT.R()
    local before = r.whales and r.whales.items or {}
    r.whales = { t = t, items = whales }
    r.makers = { t = t, list = list }
    -- WHALE ALERT: a new whale in something you own or watch
    if FT.S.meme ~= false then
        local shown = 0
        for itemID, w in pairs(whales) do
            local old = before[itemID]
            if shown < MAX_BANNERS and Cares(itemID) and not mine[w.n] and not (old and old.n == w.n) then
                Banner(itemID, string.format(L["%s holds %s of what's listed"], w.n, Whole(w.s)), L["WHALE ALERT"], "accent")
                shown = shown + 1
            end
        end
    end
    FT.Fire("FT_WHALES_READY")
end

-- the whale of one item from the last deep scan, or nil
function W.Of(itemID)
    local w = FT.R().whales
    return w and w.items and w.items[itemID], w and w.t
end

function W.Makers()
    local m = FT.R().makers
    return m and m.list or {}, m and m.t
end

---------------------------------------------------------------------------
-- Ticker symbols, for the scrolling tape only (names everywhere else): $THOR (Thorium Bar), $ACRY (Arcane Crystal), $RUGG (Rugged
-- Leather). Made from the name: the first word's first letters when the rest says only what kind of thing it is
-- (Bar, Cloth, Ore...), else its initials and the last word. Two items with the same: the second gets a number.
---------------------------------------------------------------------------
local KIND_WORDS = { bar = true, cloth = true, leather = true, ore = true, hide = true, scale = true, scales = true,
    dust = true, essence = true, shard = true, potion = true, elixir = true, flask = true, oil = true, stone = true,
    powder = true, thread = true, dye = true, bolt = true, meat = true, steak = true, fillet = true, leaf = true,
    bloom = true, root = true, gem = true, crystal = false }
local SKIP_WORDS = { ["of"] = true, ["the"] = true, ["a"] = true, ["an"] = true, ["and"] = true }
local symbolOf, idOf = {}, {}

local function MakeSymbol(name)
    local words = {}
    for w in name:gmatch("[%a']+") do
        w = w:gsub("'", "")
        if w ~= "" and not SKIP_WORDS[w:lower()] then words[#words + 1] = w end
    end
    if #words == 0 then return nil end
    local first = words[1]:upper()
    if #words == 1 then return first:sub(1, 4) end
    local last = words[#words]
    if KIND_WORDS[last:lower()] then return first:sub(1, 4) end
    local initials = ""
    for i = 1, math.min(#words - 1, 2) do initials = initials .. words[i]:sub(1, 1):upper() end
    return (initials .. last:upper()):sub(1, 4)
end

function FT.Symbol(itemID)
    if not itemID then return "" end
    local s = symbolOf[itemID]
    if s then return s end
    local name = FT.Item(itemID)
    if not name then return "" end -- not loaded yet: asked again later
    local base = MakeSymbol(name) or tostring(itemID)
    s = base
    -- taken (Thorium Bar has THOR): the last word's first letter instead (Thorium Ore: THOO), then a number
    local lastWord = name:match("([%a]+)%s*$")
    if idOf[s] and idOf[s] ~= itemID and lastWord then s = (base:sub(1, 3) .. lastWord:sub(1, 1)):upper() end
    local n = 1
    while idOf[s] and idOf[s] ~= itemID do
        n = n + 1
        s = base:sub(1, 3) .. n
    end
    symbolOf[itemID], idOf[s] = s, itemID
    return s
end

