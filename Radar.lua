-- Wolf of Booty Bay: Radar - demand forming, spotted from the market itself (nobody's list of what to hold).
--  * Demand rising: sales speeding up (the last 3 days against the week before, from the price robot's daily
--    sales) while the price holds or climbs and what's listed doesn't pile up - real buying, not a pump (a pump
--    is a price jump without the sales). Early while the price has hardly moved yet, late once it has.
--  * Chain: a crafted item whose demand rises pulls on what it's made of (Data/Recipes.lua) - its materials are
--    flagged while their own price hasn't moved yet: they tend to follow days later.
--  * Cooling: what sold well slowing down (for what you hold).
--  * The calendar: dates Blizzard has announced (raid openings): consumables tend to climb before them.
-- It grades itself: an Early call is written down with its price and checked 5-9 days later (up 5%+ = right).
local ADDON, FT = ...
local L = FT.L

local R = {}
FT.Radar = R

local MIN_RECENT = 3    -- sold a day lately, at least (smaller markets move on noise)
local SPEED_UP = 2      -- the last 3 days sell this many times the week before
local SLOW_DOWN = 0.5
local MAX_ROWS = 40

-- Dates Blizzard has announced (Forever's roadmap). kinds: item classes:subclasses that tend to climb before it
-- (0:1 potions, 0:2 elixirs, 0:3 flasks, 0:5 food); ids: items its fights are known to need.
local CALENDAR = {
    { t = time({ year = 2026, month = 12, day = 9, hour = 12 }), name = "Raids open: Barrow Deeps, Hyjal Summit, Onyxia's Lair",
      kinds = { ["0:1"] = true, ["0:2"] = true, ["0:3"] = true, ["0:5"] = true },
      ids = { [13457] = "Onyxia breathes fire", [6049] = "Onyxia breathes fire", [13461] = "fire resistance" } },
}
R.CALENDAR = CALENDAR

-- the next event within 4 weeks: { t, name, days }, or nil
function R.Next()
    local now = time()
    for _, e in ipairs(CALENDAR) do
        if e.t > now and e.t - now <= 28 * 86400 then
            return { t = e.t, name = e.name, days = math.ceil((e.t - now) / 86400), kinds = e.kinds, ids = e.ids }
        end
    end
    return nil
end

-- an event's pull on an item: a few words, or nil
local function EventPull(id, ev)
    if not ev then return nil end
    if ev.ids and ev.ids[id] then return ev.ids[id] end
    local kind = FT.An.KindOf(id)
    if kind and ev.kinds and ev.kinds[kind] then return L["raid consumable"] end
    return nil
end

-- recent (last 3 days with sales seen) and before (the 7 days before them) - a day's worth each, averaged
local function Speeds(days, today)
    local rSum, rN, bSum, bN = 0, 0, 0, 0
    for d = today - 2, today do if days[d] then rSum, rN = rSum + days[d], rN + 1 end end
    for d = today - 9, today - 3 do if days[d] then bSum, bN = bSum + days[d], bN + 1 end end
    if rN < 2 or bN < 3 then return nil end
    return rSum / rN, bSum / bN
end

local list, builtAt, building

function R.List() return list or {}, builtAt, building end

-- the self-check: Early calls written down, graded 5-9 days later
local function Log()
    FT.db.radar = FT.db.radar or { calls = {}, ok = 0, n = 0 }
    return FT.db.radar
end
local function Grade()
    local lg = Log()
    local today = FT.Day()
    for id, c in pairs(lg.calls) do
        local age = today - c.day
        if age >= 5 then
            local p = FT.Price(id)
            if p and age <= 9 then
                lg.n = lg.n + 1
                if p >= c.p * 1.05 then lg.ok = lg.ok + 1 end
            end
            if age >= 5 then lg.calls[id] = nil end
        end
    end
end

-- its record: "right 6 of 9" (nil before 5 graded calls)
function R.Record()
    local lg = FT.db and FT.db.radar
    if not lg or (lg.n or 0) < 5 then return nil end
    return string.format(L["right %d of %d"], lg.ok, lg.n)
end

function R.Build()
    if building or not (FT.Feed and FT.Feed.House) then return end
    local h = FT.Feed.House()
    if not (h and h.soldRaw) then
        list, builtAt = {}, time()
        FT.Fire("FT_RADAR_READY")
        return
    end
    building = true
    pcall(Grade)
    local ids = {}
    for id in pairs(h.soldRaw) do ids[#ids + 1] = id end
    -- the robot's days are UTC days
    local today = math.floor((FT.Feed.Time() or time()) / 86400)
    local ev = R.Next()
    local out, rising = {}, {}
    FT.Job("radar", #ids, function(k)
        local id = ids[k]
        local days = FT.Feed.SoldDays(id)
        if not days then return end
        local recent, before = Speeds(days, today)
        if not recent then return end
        local up = before > 0.3 and recent / before or (recent >= MIN_RECENT and 9 or 1)
        local pull = EventPull(id, ev)
        if not ((up >= SPEED_UP and recent >= MIN_RECENT) or (up <= SLOW_DOWN and before >= MIN_RECENT) or (pull and up >= 1.3)) then return end
        local s = FT.An.Stats(id)
        if not s.price or s.pumped then return end
        local x = { id = id, recent = recent, before = before, up = up, price = s.price, ch7 = s.ch7 or 0, pull = pull,
            supply = (s.listed and s.typicalQ and s.typicalQ > 0) and s.listed / s.typicalQ or nil }
        if up <= SLOW_DOWN then
            x.kind = "cooling"
        else
            x.kind = "rising"
            -- piling up while selling faster: sellers keep up - not a squeeze
            if x.supply and x.supply >= 1.5 then return end
            x.stage = (x.ch7 < 0.10 and "early") or (x.ch7 < 0.40 and "moving") or "late"
            rising[#rising + 1] = x
        end
        out[#out + 1] = x
    end, function()
        -- the chains: what the rising crafts are made of (every recipe of the game, not only yours), while those
        -- materials' own price hasn't moved
        local made = {}
        for _, r in ipairs(FT.Craft.AllRecipes() or {}) do
            if r.output then made[r.output] = made[r.output] or {}; table.insert(made[r.output], r) end
        end
        local seen = {}
        for _, x in ipairs(out) do seen[x.id] = true end
        for _, x in ipairs(rising) do
            for _, r in ipairs(made[x.id] or {}) do
                for _, part in ipairs(r.reagents or {}) do
                    local mid = part.itemID
                    if mid and not seen[mid] then
                        local s = FT.An.Stats(mid)
                        if s.price and (s.ch7 or 0) < 0.05 and not s.dumping then
                            seen[mid] = true
                            out[#out + 1] = { id = mid, kind = "chain", via = x.id, viaUp = x.up, price = s.price, ch7 = s.ch7 or 0,
                                stage = "early" }
                        end
                    end
                end
            end
        end
        -- early first (the most to gain), then the chains, moving, late, cooling; within each the strongest
        local rank = { early = 1, chain = 2, moving = 3, late = 4, cooling = 5 }
        local function Rank(x) return x.kind == "chain" and rank.chain or (x.kind == "cooling" and rank.cooling) or rank[x.stage] end
        table.sort(out, function(a, b)
            if Rank(a) ~= Rank(b) then return Rank(a) < Rank(b) end
            return (a.up or a.viaUp or 0) > (b.up or b.viaUp or 0)
        end)
        for i = #out, MAX_ROWS + 1, -1 do out[i] = nil end
        -- write down today's early calls (once an item), for the record
        local lg = Log()
        for _, x in ipairs(out) do
            if (x.stage == "early") and not lg.calls[x.id] then lg.calls[x.id] = { day = FT.Day(), p = x.price } end
        end
        list, builtAt, building = out, time(), false
        FT.Fire("FT_RADAR_READY")
    end, 2)
end

-- one line anyone gets, for a row
function R.Text(x)
    local function Speed(v) return v >= 10 and FT.Num(math.floor(v + 0.5)) or string.format("%.1f", v) end
    if x.kind == "chain" then
        return string.format(L["What's made from it (%s) sells %s faster this week; its own price hasn't moved yet."],
            FT.ItemText(x.via, 26), string.format("%.1fx", x.viaUp or 0))
    end
    if x.kind == "cooling" then
        return string.format(L["Selling slower: %s a day, was %s."], Speed(x.recent), Speed(x.before))
    end
    local bits = { string.format(L["Selling %s faster: %s a day, was %s"], string.format("%.1fx", x.up), Speed(x.recent), Speed(x.before)) }
    if x.supply and x.supply < 0.1 then bits[#bits + 1] = L["nearly sold out"]
    elseif x.supply and x.supply < 0.8 then bits[#bits + 1] = string.format(L["supply %s"], FT.An.Pc(x.supply - 1)) end
    if x.stage == "early" then bits[#bits + 1] = L["price hasn't moved yet"]
    else bits[#bits + 1] = string.format(L["price %s this week"], FT.An.Pc(x.ch7)) end
    if x.pull then bits[#bits + 1] = x.pull end
    return table.concat(bits, ", ") .. "."
end

-- after new prices from the robot (once at login, then with each feed taken)
FT.On("FT_SCAN_DONE", function(kind) if kind == "feed" then C_Timer.After(5, R.Build) end end)
