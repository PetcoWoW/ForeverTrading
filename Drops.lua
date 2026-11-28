local _, FT = ...
local L = FT.L

-- Drops and Dungeons (v0.55), for Make gold > Farm it.
-- Drops: what mobs drop that sells for real money - patterns, gear, rare reagents - with the mob that drops it
-- (ForeverDB's sources: Data/Sources.lua), its zone, level and chance; the chance unknown for much of Forever's new
-- loot, which still shows (that's where being early pays). No world bosses (rank 3) and no raids.
-- Dungeons: what a full clear of each 5-man dungeon drops on average (Data/Dungeons.lua, built from every mob in
-- it), priced with today's market - or what a vendor pays for loot that can't be traded - and split five ways.
local D = {}
FT.Drops = D

local MIN_PRICE = 10000                       -- worth farming for: a gold or more
local MAX_ROWS = 120
local GROUP = 5
local RUNS_AN_HOUR = 5                        -- the game's cap on new dungeons an hour
-- the raids and battlegrounds: not a farm
local NOT_A_FARM = {
    ["Molten Core"] = true, ["Blackwing Lair"] = true, ["Onyxia's Lair"] = true, ["Zul'Gurub"] = true,
    ["Ruins of Ahn'Qiraj"] = true, ["Temple of Ahn'Qiraj"] = true, ["Naxxramas"] = true,
    ["Alterac Valley"] = true, ["Warsong Gulch"] = true, ["Arathi Basin"] = true,
}
-- the gathered staples (cloth, leather, ore and stone, herbs): Materials has them
local STAPLE = { [5] = true, [6] = true, [7] = true, [9] = true }

local dungeonNames
local function DungeonOf(zones)
    if not dungeonNames then
        dungeonNames = {}
        for _, d in ipairs(FT.DNG or {}) do dungeonNames[d.n] = true end
    end
    for z in (zones or ""):gmatch("[^,]+") do
        if dungeonNames[z] then return z end
    end
    return nil
end
D.DungeonOf = DungeonOf

-- a mob you can go and kill: not a world boss or a city's leader, not in a raid or a battleground
local function Killable(who)
    if not who or not who.name then return false end
    if who.rank == "3" then return false end
    for z in (who.zones or ""):gmatch("[^,]+") do
        if NOT_A_FARM[z] then return false end
    end
    return true
end
D.Killable = Killable

local function LowLevel(lv) return tonumber((lv or ""):match("^(%d+)")) end

-- what one is worth to you: on the auction house after its cut, or what a vendor pays
local function Worth(id)
    local p, via = FT.Session.UnitValue(id)
    if not p then return 0 end
    return via == "ah" and p * (1 - FT.Cut()) or p
end
D.Worth = Worth

-- one item's Drops entry (nil: not a drop worth listing)
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
    local who = best.who
    local dng = DungeonOf(who.zones)
    local net = r.price * (1 - FT.Cut())
    return {
        id = r.id, price = r.price, ch7 = r.ch7, who = who, chance = best.chance, dungeon = dng,
        group = dng ~= nil or who.rank == "1" or who.rank == "2",
        lv = LowLevel(who.lv),
        perKill = best.chance > 0 and net * best.chance / 10000 or nil,
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

-- the list as shown: sort "price" (priciest) or "kill" (gold a kill; unknown rates after), a dungeon only,
-- mobs far above you sink
function D.Shown(list, sort, dungeon, matches)
    local me = FT.Me and FT.Me.Level() or 60
    local out = {}
    for _, e in ipairs(list or {}) do
        if (not dungeon or e.dungeon == dungeon) and (not matches or matches(e.id)) then out[#out + 1] = e end
    end
    local function key(e)
        local v = sort == "kill" and (e.perKill and (1e9 + e.perKill) or e.price / 1e6) or e.price
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
    for id, e in (s or ""):gmatch("(%d+):(%d+)") do out[#out + 1] = { tonumber(id), tonumber(e) / 1000 } end
    return out
end
local parsed = {}

-- { name, door, lv, min, mobs, bosses, value (a clear, everything), coin, each, hour (each, guessed), measured
-- (your own gold an hour there, each), top = { {id, n, worth} } } best first; trashOnly: the bosses left out
function D.Dungeons(trashOnly)
    local me = FT.Me and FT.Me.Level() or 60
    local out = {}
    for _, d in ipairs(FT.DNG or {}) do
        local key = d.n .. (trashOnly and "|t" or "")
        parsed[key] = parsed[key] or Parse(trashOnly and d.trash or d.items)
        local coin = trashOnly and d.coinT or d.coin
        local value, top = coin, {}
        for _, x in ipairs(parsed[key]) do
            local w = Worth(x[1]) * x[2]
            if w > 0 then
                value = value + w
                top[#top + 1] = { id = x[1], n = x[2], worth = w }
            end
        end
        table.sort(top, function(a, b) return a.worth > b.worth end)
        while #top > 8 do table.remove(top) end
        local each = value / GROUP
        local runs = math.min(60 / math.max(d.min or 60, 1), RUNS_AN_HOUR)
        local measured = FT.Farm and FT.Farm.ZoneGoldHour and FT.Farm.ZoneGoldHour(d.n)
        local low = LowLevel(d.lv)
        out[#out + 1] = {
            name = d.n, door = d.door, lv = d.lv, min = d.min, mobs = d.mobs, bosses = d.bosses, coin = coin,
            value = value, each = each, hour = each * runs, measured = measured, top = top,
            unknown = d.u ~= "" and d.u or nil, high = low and low > me + 3,
        }
    end
    table.sort(out, function(a, b)
        if a.high ~= b.high then return not a.high end
        return a.each > b.each
    end)
    return out
end
