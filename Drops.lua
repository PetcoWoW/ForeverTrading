local _, FT = ...
local L = FT.L

-- Drops, Dungeons and the farm logic (v0.55, the rules from the farm study in v0.56), for Make gold > Farm it
-- and the Where to farm window.
-- What a kill is worth: a mob's coin and vendor loot (its floor) plus what it drops that trades, at today's prices.
-- Steady: the floor and anything that comes 5%+ of kills or is worth under 2g; jackpot: the rarer valuable drops,
-- always shown apart, never inside the steady number. A pace: ~90 kills an hour (30 for elites), capped by the
-- spawns and their respawn.
-- Drops lists targeted farms only: no world drops (a pool any mob of the level rolls), no summoned or event mobs,
-- nothing above level 60 (61 for elites); rare spawns say so.
local D = {}
FT.Drops = D

local MIN_PRICE = 10000                       -- worth farming for: a gold or more
local MAX_ROWS = 120
local GROUP = 5
local RUNS_AN_HOUR = 5                        -- a dungeon resets five times an hour
local JACKPOT, JACKPOT_P = 20000, 0.05        -- 2g+ and under 5% of kills: a jackpot
local PACE, PACE_ELITE = 90, 30               -- kills an hour, at your level
-- the raids and battlegrounds: not a farm
local NOT_A_FARM = {
    ["Molten Core"] = true, ["Blackwing Lair"] = true, ["Onyxia's Lair"] = true, ["Zul'Gurub"] = true,
    ["Ruins of Ahn'Qiraj"] = true, ["Temple of Ahn'Qiraj"] = true, ["Naxxramas"] = true,
    ["Alterac Valley"] = true, ["Warsong Gulch"] = true, ["Arathi Basin"] = true,
}
-- the gathered staples (cloth, leather, ore and stone, herbs): Materials has them
local STAPLE = { [5] = true, [6] = true, [7] = true, [9] = true }

local dungeonNames, dungeonMobs
local function Dungeons()
    if not dungeonNames then
        dungeonNames, dungeonMobs = {}, {}
        for _, d in ipairs(FT.DNG or {}) do
            dungeonNames[d.b or d.n] = true
            local set = {}
            for n in (d.m or ""):gmatch("%d+") do set[tonumber(n)] = true end
            dungeonMobs[d.n] = set
        end
    end
    return dungeonNames, dungeonMobs
end
local function DungeonOf(zones)
    local names = Dungeons()
    for z in (zones or ""):gmatch("[^,]+") do
        if names[z] then return z end
    end
    return nil
end
D.DungeonOf = DungeonOf

local function LowLevel(lv) return tonumber((lv or ""):match("^(%d+)")) end
local function HighLevel(lv) return tonumber((lv or ""):match("(%d+)$")) end
D.LowLevel = LowLevel

-- a mob you can go and kill: not a world boss, not summoned or event-only, not in a raid or a battleground, not
-- above level 60 (61 for elites)
local function Elite(who) return who ~= nil and (who.rank == "1" or who.rank == "2") end
D.Elite = Elite
local function Killable(who)
    if not who or not who.name then return false end
    if who.rank == "3" or who.spawns == 0 then return false end
    local hi = HighLevel(who.lv)
    if hi and hi > (Elite(who) and 61 or 60) then return false end
    for z in (who.zones or ""):gmatch("[^,]+") do
        if NOT_A_FARM[z] then return false end
    end
    return true
end
D.Killable = Killable
local function Rare(who) return who ~= nil and (who.rank == "2" or who.rank == "4") end
D.Rare = Rare

-- what one is worth to you: on the auction house after its cut, or what a vendor pays
local function Worth(id)
    local p, via = FT.Session.UnitValue(id)
    if not p then return 0 end
    return via == "ah" and p * (1 - FT.Cut()) or p
end
D.Worth = Worth

-- kills an hour at a mob: the pace, or what its spawns give (a rare spawn: its few)
function D.KillsAnHour(who)
    local pace = Elite(who) and PACE_ELITE or PACE
    if who and who.spawns and who.spawns > 0 and who.respawn and who.respawn > 0 then
        return math.min(pace, who.spawns * 3600 / math.max(who.respawn, 60))
    end
    return pace
end

-- a kill: steady copper, jackpot copper (nil: no farm facts for this mob)
local killCache, killFor = {}, nil
function D.KillValue(who)
    if not (who and who.floor) then return nil end
    local rows = FT.Market.Rows()
    if killFor ~= rows then killCache, killFor = {}, rows end
    local c = killCache[who.id]
    if c then return c[1], c[2] end
    local steady, jackpot = who.floor, 0
    for id, e in (who.trades or ""):gmatch("(%d+)%*(%d+)") do
        local p = tonumber(e) / 10000
        local w = Worth(tonumber(id))
        if p < JACKPOT_P and w >= JACKPOT then jackpot = jackpot + w * p else steady = steady + w * p end
    end
    killCache[who.id] = { steady, jackpot }
    return steady, jackpot
end

-- an hour at a mob: steady, jackpot, kills
function D.MobHour(who)
    local s, j = D.KillValue(who)
    if not s then return nil end
    local k = D.KillsAnHour(who)
    return s * k, j * k, k
end

-- your level's best open-world farm: { who, steady, jackpot } (solo: no elites, rares or dungeons), cached
local bestCache, bestFor, bestLevel
function D.BestSpot(level)
    level = level or (FT.Me and FT.Me.Level()) or 60
    local rows = FT.Market.Rows()
    if bestFor == rows and bestLevel == level then return bestCache end
    local best
    for n in pairs(FT.SRC_N or {}) do
        local who = FT.Where.Npc(n)
        if who and who.floor and who.spawns and who.spawns >= 6 and not Elite(who) and not Rare(who) and Killable(who)
            and not DungeonOf(who.zones) then
            local lo, hi = LowLevel(who.lv), HighLevel(who.lv)
            if lo and lo <= level + 2 and (hi or lo) >= level - 8 then
                local s, j = D.MobHour(who)
                if s and (not best or s > best.steady) then best = { who = who, steady = s, jackpot = j } end
            end
        end
    end
    bestCache, bestFor, bestLevel = best, rows, level
    return best
end

-- a world drop: lowest level, about 1 in how many kills (nil: not one)
function D.World(id)
    local s = FT.SRC_WORLD and FT.SRC_WORLD[id]
    if not s then return nil end
    local lv, one = s:match("^(%d+):(%d+)$")
    return tonumber(lv), tonumber(one)
end

-- one item's Drops entry (nil: not a targeted drop worth listing)
local function Entry(r)
    if not (r.id and r.price and r.price >= MIN_PRICE) or r.gone then return nil end
    if r.cls == 7 and STAPLE[r.sub] then return nil end
    local g = FT.Where.Get(r.id)
    if not g or #g.drops == 0 then return nil end
    local best
    for _, x in ipairs(g.drops) do
        if Killable(x.who) and (not best or x.chance > best.chance) then best = x end
    end
    if not best then return nil end
    -- a world drop is no farm, unless one mob gives it far more often (2%+)
    if D.World(r.id) and best.chance < 200 then return nil end
    local who = best.who
    local dng = DungeonOf(who.zones)
    local net = r.price * (1 - FT.Cut())
    local each = best.chance > 0 and net * best.chance / 10000 or nil
    return {
        id = r.id, price = r.price, ch7 = r.ch7, who = who, chance = best.chance, dungeon = dng, rare = Rare(who),
        group = dng ~= nil or who.rank == "1",
        lv = LowLevel(who.lv),
        perKill = each, perHour = each and each * D.KillsAnHour(who) or nil,
        others = #g.drops - 1,
    }
end

-- the list, worked out in the background a few ms a frame; nil while it's being made (onReady when it's done)
local cache, cacheFor, job
local waiting = {}
function D.List(onReady)
    local rows = FT.Market.Rows()
    if cache and cacheFor == rows then return cache end
    if onReady then waiting[#waiting + 1] = onReady end
    if job then return cache end                  -- the last list while the new one is made
    if not rows then return nil end
    local out = {}
    job = FT.Job("drops", #rows, function(k)
        if FT.Market.Rows() ~= rows then job = nil return false end   -- new prices: the next ask starts again
        local e = Entry(rows[k])
        if e then out[#out + 1] = e end
    end, function()
        job = nil
        if FT.Market.Rows() ~= rows then return end
        table.sort(out, function(a, b) return a.price > b.price end)
        while #out > MAX_ROWS * 3 do table.remove(out) end
        cache, cacheFor = out, rows
        local w = waiting
        waiting = {}
        for _, f in ipairs(w) do pcall(f) end
        FT.Fire("FT_DROPS_READY")
    end, 3)
    return cache
end

-- the list as shown: sort "price" (priciest) or "hour" (this drop's gold an hour; unknown rates after), one
-- dungeon run only (its mobs), mobs far above you sink
function D.Shown(list, sort, dungeon, matches)
    local me = FT.Me and FT.Me.Level() or 60
    local _, mobsOf = Dungeons()
    local only = dungeon and mobsOf[dungeon]
    local out = {}
    for _, e in ipairs(list or {}) do
        if (not dungeon or (only and only[e.who.id]) or e.dungeon == dungeon) and (not matches or matches(e.id)) then out[#out + 1] = e end
    end
    local function key(e)
        local v = (sort == "hour" or sort == "kill") and (e.perHour and (1e9 + e.perHour) or e.price / 1e6) or e.price
        if e.lv and e.lv > me + 3 then v = v / 1e3 end
        return v
    end
    table.sort(out, function(a, b) return key(a) > key(b) end)
    while #out > MAX_ROWS do table.remove(out) end
    return out
end

-- a drop chance as people say it: "1 in 60", "35%"
function D.Odds(chance)
    if not chance or chance <= 0 then return nil end
    if chance >= 1000 then return string.format("%d%%", math.floor(chance / 100 + 0.5)) end
    return string.format(L["1 in %s"], FT.Num(math.floor(10000 / chance + 0.5)))
end

---------------------------------------------------------------------------
-- Dungeons
---------------------------------------------------------------------------
local function Parse(s)
    local out = {}
    for id, e, j in (s or ""):gmatch("(%d+):(%d+)(:?j?)") do out[#out + 1] = { tonumber(id), tonumber(e) / 1000, j == ":j" } end
    return out
end
local parsed = {}

-- { name, base, door, lv, min, mobs, bosses, coin, steady (a run), jackpot (a run), each (steady, a person), hour
-- (steady each, guessed), jackpotEach, measured (your own gold an hour there), top = { {id, n, worth, jackpot} } }
-- best first
function D.Dungeons(trashOnly)
    local me = FT.Me and FT.Me.Level() or 60
    local out = {}
    for _, d in ipairs(FT.DNG or {}) do
        local key = d.n .. (trashOnly and "|t" or "")
        parsed[key] = parsed[key] or Parse(trashOnly and d.trash or d.items)
        local coin = trashOnly and d.coinT or d.coin
        local steady, jackpot, top = coin, 0, {}
        for _, x in ipairs(parsed[key]) do
            local unit = Worth(x[1])
            local w = unit * x[2]
            if w > 0 then
                local jp = x[3] and unit >= JACKPOT
                if jp then jackpot = jackpot + w else steady = steady + w end
                top[#top + 1] = { id = x[1], n = x[2], worth = w, jackpot = jp }
            end
        end
        table.sort(top, function(a, b)
            if a.jackpot ~= b.jackpot then return not a.jackpot end
            return a.worth > b.worth
        end)
        while #top > 8 do table.remove(top) end
        local each = steady / GROUP
        local runs = math.min(60 / math.max(d.min or 60, 1), RUNS_AN_HOUR)
        local measured = FT.Farm and FT.Farm.ZoneGoldHour and FT.Farm.ZoneGoldHour(d.b or d.n)
        local low = LowLevel(d.lv)
        out[#out + 1] = {
            name = d.n, base = d.b or d.n, door = d.door, lv = d.lv, min = d.min, mobs = d.mobs, bosses = d.bosses,
            coin = coin, steady = steady, jackpot = jackpot, value = steady, each = each, hour = each * runs,
            jackpotEach = jackpot / GROUP, measured = measured, top = top,
            unknown = d.u ~= "" and d.u or nil, high = low and low > me + 3,
        }
    end
    table.sort(out, function(a, b)
        if a.high ~= b.high then return not a.high end
        return a.each > b.each
    end)
    return out
end
