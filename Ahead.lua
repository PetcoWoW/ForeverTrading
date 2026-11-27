local _, FT = ...
local L = FT.L

-- Coming up (v0.50): a calendar of gold chances and next week's calls, each with how sure Wolf is.
--   Events: Forever's own calendar (Data/Sources.lua: the Darkmoon Faire, battleground holiday weeks, Winter Veil
--   and the other holidays) and the raids (Data/Futures.lua).
--   Calls: where an item's price should be in a week. One plain rule - a price far off its two-week average comes
--   back part way, a week's trend carries on a little - and an event ahead adds its pull. The rule is checked
--   against every week of the item's own last 30 days: how sure Wolf is = how often it was right there (pulled
--   toward a coin flip when there are few weeks). Calls under 40% sure aren't shown.
local A = {}
FT.Ahead = A

local DAY = 86400
local HIDE_UNDER = 40

---------------------------------------------------------------------------
-- The calendar
---------------------------------------------------------------------------
local SHORT = { faire = "Faire", bg = "BG week", veil = "Winter Veil", lunar = "Lunar", love = "Love", noble = "Noblegarden",
    midsummer = "Midsummer", hallow = "Hallow's End", harvest = "Harvest", children = "Children's Week", raid = "Raids" }

-- events that touch the next `days` days: { t, ends, kind, name, where, short }, soonest first; the raids' opening
-- (Raid prep's study) is one of them
function A.Events(days, now)
    now = now or time()
    local upto = now + (days or 7) * DAY
    local out = {}
    for _, e in ipairs(FT.SRC_EVENTS or {}) do
        local t, hours, kind, name, where = e[1], e[2], e[3], e[4], e[5]
        local ends = t + hours * 3600
        if ends > now and t < upto then
            local short = SHORT[kind] or name
            if kind == "bg" then short = (name:match(": (.+)$") or name):gsub("Darkspear Islands", "Darkspear"):gsub("Arathi Basin", "AB"):gsub("Warsong Gulch", "WSG") .. " week" end
            out[#out + 1] = { t = t, ends = ends, kind = kind, name = name, where = where ~= "" and where or nil, short = short }
        end
    end
    local _, ev = FT.Futures and FT.Futures.Days and FT.Futures.Days()
    if ev and ev.t and ev.t < upto and ev.t + DAY > now then
        out[#out + 1] = { t = ev.t, ends = ev.t + DAY, kind = "raid", name = ev.name or L["The raids open"], short = L["Raids"] }
    end
    table.sort(out, function(a, b) return a.t < b.t end)
    return out
end

-- the items an event pulls on: the Faire's turn-ins, the PvP kit in a battleground's holiday week, the raids' list
function A.EventItems(kind)
    if kind == "faire" then return FT.SRC_LIST_FAIRE or {} end
    if kind == "bg" then return FT.SRC_LIST_PVP or {} end
    if kind == "raid" then
        local out = {}
        for _, x in ipairs(FT.FUTURES and FT.FUTURES.consumables or {}) do out[#out + 1] = x.id end
        return out
    end
    return {}
end

local pullOf -- item -> { kind, ev } of the soonest event pulling on it in the next 10 days
local function Pulls()
    if pullOf then return pullOf end
    pullOf = {}
    for _, ev in ipairs(A.Events(10)) do
        for _, id in ipairs(A.EventItems(ev.kind)) do
            if not pullOf[id] then pullOf[id] = ev end
        end
    end
    return pullOf
end

---------------------------------------------------------------------------
-- The calls
---------------------------------------------------------------------------
local PULL = { faire = 0.06, bg = 0.04, raid = 0.08 } -- what an event ahead adds (a week before it)

local function Rule(c, k)
    -- the rule at day k of closes c: back part way to the two-week average, plus a little of the week's trend
    local from = math.max(1, k - 13)
    local sum, n = 0, 0
    for i = from, k do sum, n = sum + c[i], n + 1 end
    local avg = sum / n
    local dev = c[k] / avg - 1
    local trend = k > 7 and (c[k] / c[k - 7] - 1) or 0
    return -0.5 * dev + 0.25 * trend
end

-- { move = expected change in a week (0.08: +8%), sure = 0-100, hits, weeks, why } or nil (too little data)
function A.Call(id)
    local daily = FT.Hist and FT.Hist.Daily and FT.Hist.Daily(id, 30)
    if not daily or #daily < 10 then return nil end
    local c = {}
    for _, d in ipairs(daily) do if d.c and d.c > 0 then c[#c + 1] = d.c end end
    if #c < 10 then return nil end
    -- the rule against every past week of this item
    local hits, weeks = 0, 0
    for k = 8, #c - 7 do
        local p = Rule(c, k)
        local a = c[k + 7] / c[k] - 1
        local right
        if math.abs(p) < 0.03 then right = math.abs(a) < 0.07 else right = (p > 0) == (a > 0) end
        weeks = weeks + 1
        if right then hits = hits + 1 end
    end
    local move = Rule(c, #c)
    local why
    local ev = Pulls()[id]
    if ev and PULL[ev.kind] then
        move = move + PULL[ev.kind]
        why = ev.kind == "raid" and string.format(L["the raids open %s"], date("%b %d", ev.t))
            or ev.kind == "faire" and string.format(L["Darkmoon Faire %s: a turn-in"], date("%b %d", ev.t))
            or string.format(L["%s: more battlegrounds"], ev.name)
    end
    if not why then
        local dev = c[#c] / ((c[math.max(1, #c - 13)] + c[#c]) / 2) - 1
        why = move > 0.03 and (dev < -0.05 and L["back up from a dip"] or L["climbing"]) or move < -0.03 and L["coming down from a high"] or L["steady"]
    end
    -- how sure: its record, pulled toward a coin flip by few weeks (4 weeks' worth of 50%)
    local sure = math.floor((hits + 2) / (weeks + 4) * 100 + 0.5)
    if ev then sure = math.min(95, sure + 10) end -- an event on the calendar is a known pull
    return { move = move, sure = sure, hits = hits, weeks = weeks, why = why, event = ev }
end

-- the colour of how sure: bright from 75, the accent from 55, dimmer under (calls under 40 never show)
function A.SureColor(sure)
    if sure >= 75 then return "up" end
    if sure >= 55 then return "accent" end
    return "muted"
end
function A.SureText(sure)
    return FT.C(A.SureColor(sure), sure .. "%") .. FT.C("dim", " " .. (sure >= 75 and L["High"] or sure >= 55 and L["Medium"] or L["Low"]))
end

---------------------------------------------------------------------------
-- Coming up's lists: the best farms next week, the raids, the PvP kit in a holiday week. Worked out in the
-- background, kept until new prices come.
---------------------------------------------------------------------------
local list, busy, waiting = nil, false, {}
FT.On("FT_SCAN_DONE", function() list, pullOf = nil, nil end)
FT.On("FT_MARKET_READY", function() list, pullOf = nil, nil end)

local function Row(id, kind, c, extra)
    local s = FT.An.Stats(id)
    if not (s and s.price) then return nil end
    local rate = FT.Sales.Rate(id)
    local r = { id = id, kind = kind, call = c, price = s.price, ahead = s.price * (1 + c.move), perDay = rate and rate.perDay or 0 }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end

-- { farms = { rows }, raids = { rows }, pvp = { rows } } (nil while it's worked out; done(list) after)
function A.Lists(done)
    if list then return list end
    if done then waiting[#waiting + 1] = done end
    if busy then return nil end
    busy = true
    local rows = FT.Market.Rows() or {}
    local farms = {}
    FT.Job("comingUp", #rows, function(k)
        local r = rows[k]
        if not (r and r.price and (r.cls == 7 or r.cls == 5 or r.cls == 15) and FT.Where and FT.Where.Farmable(r.id)) then return end
        local id = r.id
        local c = A.Call(id)
        if not (c and c.sure >= HIDE_UNDER and c.move > -0.02) then return end
        local row = Row(id, "FARM", c)
        if not row or row.perDay < 10 then return end
        -- what you'd make: your own rate an hour when you've farmed it, else a farmer's share of a day's sales
        local yours = FT.Farm.YourZones(id, 1)[1]
        if yours then
            row.hour = yours.perHour * row.ahead
            row.where = yours.zone
        end
        row.score = (row.hour or row.ahead * math.min(row.perDay * 0.2, 40)) * (c.sure / 100)
        farms[#farms + 1] = row
    end, function()
        table.sort(farms, function(a, b) return a.score > b.score end)
        while #farms > 12 do table.remove(farms) end
        local raids, pvp = {}, {}
        for _, id in ipairs(A.EventItems("raid")) do
            local c = A.Call(id)
            if c and c.sure >= HIDE_UNDER then
                local row = Row(id, c.move >= 0.03 and "HOLD" or (c.move <= -0.03 and "SELL" or "HOLD"), c)
                if row then raids[#raids + 1] = row end
            end
        end
        table.sort(raids, function(a, b) return a.call.sure * math.abs(a.call.move) > b.call.sure * math.abs(b.call.move) end)
        while #raids > 6 do table.remove(raids) end
        for _, id in ipairs(FT.SRC_LIST_PVP or {}) do
            local c = A.Call(id)
            if c and c.sure >= HIDE_UNDER then
                local row = Row(id, c.move >= 0.03 and "BUY" or "HOLD", c)
                if row and row.perDay >= 1 then pvp[#pvp + 1] = row end
            end
        end
        table.sort(pvp, function(a, b) return a.perDay * a.price > b.perDay * b.price end)
        while #pvp > 6 do table.remove(pvp) end
        list = { farms = farms, raids = raids, pvp = pvp }
        busy = false
        local w = waiting
        waiting = {}
        for _, fn in ipairs(w) do pcall(fn, list) end
        FT.Fire("FT_COMING_UP")
    end)
    return nil
end

---------------------------------------------------------------------------
-- The reminder: one chat line the day before an event (once per event)
---------------------------------------------------------------------------
function A.Remind(now)
    now = now or time()
    if not (FT.db and FT.S) or FT.S.comingRemind == false then return end
    FT.db.reminded = FT.db.reminded or {}
    for _, ev in ipairs(A.Events(2, now)) do
        local key = ev.kind .. ":" .. ev.t
        local soon = ev.t - now
        if soon > 0 and soon <= DAY + 6 * 3600 and not FT.db.reminded[key] then
            FT.db.reminded[key] = now
            local items = A.EventItems(ev.kind)
            local names = {}
            for i = 1, math.min(3, #items) do names[#names + 1] = FT.ItemText(items[i], 22) end
            local what = #names > 0 and string.format(L[" - %s climb, stock up today."], table.concat(names, ", ")) or ""
            FT.Print(string.format(L["Coming up tomorrow: %s%s"], ev.name .. (ev.where and (" (" .. ev.where .. ")") or ""), what))
        end
    end
    -- forget reminders older than a month
    for k, t in pairs(FT.db.reminded) do if now - t > 30 * DAY then FT.db.reminded[k] = nil end end
end
FT.On("FT_READY", function() C_Timer.After(40, function() pcall(A.Remind) end) end)
