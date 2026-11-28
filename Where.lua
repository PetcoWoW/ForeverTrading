local _, FT = ...
local L = FT.L

-- Where an item comes from (v0.50): ForeverDB's sources (Data/Sources.lua: drops, skinning, nodes, containers,
-- vendors, Merchant's Favor, quests, world drops), Wolf's own Forever notes, Wolf's recipes, your loot log and the
-- Wolf network's (other users' loot, pooled). One answer for the item page, the farm window, the craft window's
-- recipe line and the Farm it board - and whether it's farmed at all (crafted materials aren't).
local W = {}
FT.Where = W

local cache = setmetatable({}, { __mode = "v" })

local function Split(s, sep)
    local out = {}
    for part in (s .. sep):gmatch("(.-)" .. sep) do out[#out + 1] = part end
    return out
end

local function Npc(id)
    local s = FT.SRC_N and FT.SRC_N[id]
    if not s then return nil end
    local p = Split(s, "|")
    local n = { id = id, name = p[1], zones = p[2] ~= "" and p[2] or nil, lv = p[3] ~= "" and p[3] or nil, fac = p[4] ~= "" and p[4] or nil,
        rank = p[5] ~= "" and p[5] or nil } -- rank (v0.55): 1 elite, 2 rare elite, 3 boss, 4 rare
    -- (v0.56) its farm facts: spawns and respawn (0: summoned or event-only), coin and vendor loot a kill, what it
    -- drops that trades (expected a kill), priced in game
    if p[6] and p[6] ~= "" then
        local sp, resp = p[6]:match("^(%d+):(%d+)$")
        n.spawns, n.respawn = tonumber(sp), tonumber(resp)
        n.floor = tonumber(p[7]) or 0
        n.trades = p[8] ~= "" and p[8] or nil
    end
    return n
end
W.Npc = Npc

local function Obj(id)
    local s = FT.SRC_O and FT.SRC_O[id]
    if not s then return nil end
    local p = Split(s, "|")
    return { id = id, name = p[1], zones = p[2] ~= "" and p[2] or nil, chest = p[3] == "c" }
end

local function Quest(id)
    local s = FT.SRC_Q and FT.SRC_Q[id]
    if not s then return nil end
    local p = Split(s, "|")
    return { id = id, name = p[1], lv = tonumber(p[2]) }
end

-- your side: "A" or "H" (nil: not known yet - everything shows)
local function Side()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return f == "Alliance" and "A" or (f == "Horde" and "H" or nil)
end
local function ForYou(fac)
    local me = Side()
    return not (me and fac and fac ~= "AH" and fac ~= "" and fac ~= me)
end

-- the parsed sources of an item: { drops, skin, nodes = { {who, chance} }, boxes = { {itemID, chance} },
-- vendors, favor = { npc }, quests, world = min level, note = text } (chance per 10000; 0 = known, rate unknown)
function W.Get(id)
    if not id then return nil end
    local c = cache[id]
    if c then return c end
    local out = { drops = {}, skin = {}, nodes = {}, boxes = {}, vendors = {}, favor = {}, quests = {} }
    local s = FT.SRC and FT.SRC[id]
    if s then
        for _, seg in ipairs(Split(s, ";")) do
            local k, v = seg:match("^(%a)=(.*)$")
            if k and v then
                for _, e in ipairs(Split(v, ",")) do
                    local a, b = e:match("^(%d+):?(%d*)$")
                    a, b = tonumber(a), tonumber(b)
                    if k == "d" then out.drops[#out.drops + 1] = { who = Npc(a), chance = b or 0 }
                    elseif k == "s" then out.skin[#out.skin + 1] = { who = Npc(a), chance = b or 0 }
                    elseif k == "o" then out.nodes[#out.nodes + 1] = { who = Obj(a), chance = b or 0 }
                    elseif k == "i" then out.boxes[#out.boxes + 1] = { itemID = a, chance = b or 0 }
                    elseif k == "v" then local n = Npc(a); if n then out.vendors[#out.vendors + 1] = n end
                    elseif k == "f" then local n = Npc(a); if n then n.camp = FT.SRC_MF and FT.SRC_MF[a]; out.favor[#out.favor + 1] = n end
                    elseif k == "q" then local q = Quest(a); if q then out.quests[#out.quests + 1] = q end
                    elseif k == "w" then out.world = a
                    end
                end
            end
        end
    end
    out.note = FT.SRC_H and FT.SRC_H[id]
    cache[id] = out
    return out
end

-- recipes that can't be made in Forever (an item they make or use isn't in the game): every list leaves them out
function W.Dead(recipeID)
    return FT.SRC_DEAD and recipeID and FT.SRC_DEAD[recipeID] or false
end

local function Pct(chance)
    if not chance or chance <= 0 then return nil end
    local p = chance / 100
    if p >= 10 then return string.format("%d%%", math.floor(p + 0.5)) end
    if p >= 1 then return string.format("%.1f%%", p) end
    return string.format("%.2f%%", p)
end

local GATHERED = { [5] = true, [6] = true, [7] = true, [9] = true, [10] = true } -- cloth, leather, ore, herbs, elementals

-- something you go out and farm: gathered (a node, skinning, Wolf's farm spots or notes), or a material mobs drop
-- often enough. A crafted material (bars, bolts, cured hides, Mooncloth, transmutes) isn't, unless it's also
-- gathered (Heavy Leather: skinned and made).
function W.Farmable(id)
    if not id then return false end
    if FT.FarmSpots and FT.FarmSpots[id] then return true end
    local g = W.Get(id)
    local crafted = FT.Craft and FT.Craft.ByOutputAll and FT.Craft.ByOutputAll(id)
    local best = 0
    for _, x in ipairs(g.nodes) do
        if not (x.who and x.who.chest) then best = math.max(best, x.chance > 0 and x.chance or 1000) end
    end
    for _, x in ipairs(g.skin) do best = math.max(best, x.chance > 0 and x.chance or 1000) end
    for _, x in ipairs(g.drops) do best = math.max(best, x.chance) end
    if crafted then return best >= 500 end -- made, and also found often enough (5% a corpse or node)
    if best > 0 or (g.note and g.note:find("Scarce", 1, true)) then
        local row = FT.Market and FT.Market.Row and FT.Market.Row(id)
        if row and row.cls ~= 7 and row.cls ~= 5 then return best >= 1000 end -- gear and the like: only a real farm
        return true
    end
    -- nothing in the sources: Trade Goods of a gathered kind that no recipe makes
    local row = FT.Market and FT.Market.Row and FT.Market.Row(id)
    return row and row.cls == 7 and GATHERED[row.sub] or false
end

-- a vendor of your side sells it (v0.50: the vendor price floor)
function W.VendorSold(id)
    if not id then return false end
    for _, n in ipairs(W.Get(id).vendors) do
        if ForYou(n.fac) then return true end
    end
    return false
end

-- the gathering profession it needs, when that's the only way to get it (v0.50: Wolf knows you): "Skinning",
-- "Mining", "Herbalism" - nil when mobs drop it, a vendor sells it, or it isn't gathered
function W.Needs(id)
    if not id then return nil end
    local g = W.Get(id)
    local dropped = false
    for _, x in ipairs(g.drops) do if x.chance >= 300 then dropped = true end end
    if dropped or #g.vendors > 0 or #g.favor > 0 or (FT.FarmSpots and FT.FarmSpots[id]) then return nil end
    if #g.skin > 0 then return "Skinning" end
    local gathered = false
    for _, x in ipairs(g.nodes) do if not (x.who and x.who.chest) then gathered = true end end
    if gathered then
        local row = FT.Market and FT.Market.Row and FT.Market.Row(id)
        if row and row.cls == 7 and row.sub == 7 then return "Mining" end
        if row and row.cls == 7 and row.sub == 9 then return "Herbalism" end
    end
    return nil
end

-- the lowest level of the mobs that drop it (nil: no drop of known level)
function W.DropLevel(id)
    local lo
    for _, x in ipairs(W.Get(id).drops) do
        local lv = x.who and x.who.lv and tonumber(tostring(x.who.lv):match("^(%d+)"))
        if lv and x.chance >= 100 then lo = math.min(lo or lv, lv) end
    end
    return lo
end

-- the lines that say where it comes from, best first (each one string, parts apart with " · " so a narrow line
-- drops its last part): your loot, Wolf users' loot, Wolf's note, nodes, skinning, drops, vendors, Merchant's
-- Favor, containers, quests, world drop
function W.Lines(id, max)
    max = max or 6
    local out, spare = {}, {}
    local function Add(text) if #out < max then out[#out + 1] = text end end
    local function Spare(text) spare[#spare + 1] = text end
    local g = W.Get(id)
    -- (v0.51) crafted: its drops only when worth farming (5%+); gear: the world drop first, then only real farms
    local crafted = FT.Craft and FT.Craft.ByOutputAll and FT.Craft.ByOutputAll(id)
    local _, _, _, _, _, classID = FT.GetItemInfoInstant(id)
    if not classID then
        local row = FT.Market and FT.Market.Row and FT.Market.Row(id)
        classID = row and row.cls
    end
    local gear = classID == 2 or classID == 4
    local dropMin = crafted and 500 or (gear and 200 or 0)
    local mob = FT.Farm and FT.Farm.Mobs and FT.Farm.Mobs(id, 1)[1]
    if mob then
        Add(FT.C("text", mob.name or "?") .. FT.C("dim", "  ·  " .. string.format(L["%s a corpse (your loot)"], string.format("%.2f", mob.per))
            .. (mob.zone and ("  ·  " .. mob.zone) or "")))
    end
    local node = FT.Farm and FT.Farm.Objects and FT.Farm.Objects(id, 1)[1]
    if node then
        Add(FT.C("text", node.name or L["a node"]) .. FT.C("dim", "  ·  " .. string.format(L["%s a node (your loot)"], string.format("%.2f", node.per))
            .. (node.zone and ("  ·  " .. node.zone) or "")))
    end
    local pooled = FT.Net and FT.Net.FarmText and FT.Net.FarmText(id)
    if pooled then Add(pooled) end
    pooled = FT.Net and FT.Net.LootText and FT.Net.LootText(id)
    if pooled then Add(pooled) end
    if g.note then Add(FT.C("text", g.note)) end
    if gear and g.world then
        Add(FT.C("text", L["World drop"]) .. FT.C("dim", "  ·  " .. string.format(L["level %d and up"], g.world) .. "  ·  " .. L["Wowhead has where it drops most"]))
    end
    -- a vendor: first for what isn't gathered; after the nodes and skinning for what is (a Faire vendor's few)
    local function Vendors()
        local n = 0
        for _, v in ipairs(g.vendors) do
            if ForYou(v.fac) and v.zones and n < 2 then
                n = n + 1
                Add(FT.C("text", L["Vendor"] .. ": " .. v.name) .. FT.C("dim", "  ·  " .. v.zones))
            end
        end
    end
    local gathered = #g.skin > 0
    for _, x in ipairs(g.nodes) do if x.who and not x.who.chest then gathered = true end end
    if not gathered then Vendors() end
    for _, v in ipairs(g.favor) do
        if ForYou(v.camp) then
            Add(FT.C("accent", L["Merchant's Favor"]) .. FT.C("dim", "  ·  " .. v.name .. "  ·  "
                .. (v.camp == "H" and L["west of the Crossroads, the Barrens"] or L["Three Corners, Redridge"])))
        end
    end
    local n = 0
    for _, x in ipairs(g.nodes) do
        if x.who then
            local line = FT.C("text", x.who.name) .. FT.C("dim", (Pct(x.chance) and ("  ·  " .. Pct(x.chance)) or "") .. (x.who.zones and ("  ·  " .. x.who.zones) or ""))
            if x.who.chest then Spare(line) elseif n < 2 then n = n + 1; Add(line) end
        end
    end
    n = 0
    for _, x in ipairs(g.skin) do
        if x.who and n < 2 then
            n = n + 1
            Add(FT.C("text", L["Skinning"] .. ": " .. x.who.name) .. FT.C("dim", (Pct(x.chance) and ("  ·  " .. Pct(x.chance)) or "")
                .. (x.who.zones and ("  ·  " .. x.who.zones) or "") .. (x.who.lv and ("  ·  " .. x.who.lv) or "")))
        end
    end
    if gathered then Vendors() end
    n = 0
    for _, x in ipairs(g.drops) do
        if x.who and n < 2 and x.chance >= dropMin then
            n = n + 1
            Add(FT.C("text", x.who.name) .. FT.C("dim", (Pct(x.chance) and ("  ·  " .. Pct(x.chance)) or "")
                .. (x.who.zones and ("  ·  " .. x.who.zones) or "") .. (x.who.lv and ("  ·  " .. x.who.lv) or "")))
        end
    end
    for _, x in ipairs(g.boxes) do
        Spare(FT.C("text", FT.ItemText(x.itemID, 26)) .. FT.C("dim", Pct(x.chance) and ("  ·  " .. Pct(x.chance)) or ""))
    end
    if g.quests[1] then
        local q = g.quests[1]
        Add(FT.C("text", L["Quest"] .. ": " .. q.name) .. FT.C("dim", q.lv and ("  ·  " .. q.lv) or ""))
    end
    if g.world and not gear then Add(FT.C("text", L["World drop"]) .. FT.C("dim", "  ·  " .. string.format(L["creatures of level %d and up"], g.world))) end
    -- chests, boxes and containers: only when nothing else gives it
    if #out == 0 then
        for _, line in ipairs(spare) do Add(line) end
    end
    return out
end

-- one short line on how you get a recipe item: Merchant's Favor (your camp), a vendor (name, zone), a drop
-- (the best mob, zone), a quest, a world drop; nil when nothing's known
function W.RecipeLine(itemID)
    local g = W.Get(itemID)
    for _, n in ipairs(g.favor) do
        if ForYou(n.camp) then
            return string.format(L["Merchant's Favor  ·  %s  ·  %s"], n.name, n.camp == "H" and L["the Crossroads"] or L["Three Corners"]), "favor"
        end
    end
    for _, n in ipairs(g.vendors) do
        if ForYou(n.fac) then
            return n.zones and string.format(L["%s (vendor)  ·  %s"], n.name, n.zones) or string.format(L["%s (vendor)"], n.name), "vendor"
        end
    end
    if g.note then return g.note, "note" end
    local d = g.drops[1]
    if d and d.who then
        return (d.who.zones and string.format(L["drops from %s  ·  %s"], d.who.name, d.who.zones) or string.format(L["drops from %s"], d.who.name))
            .. (Pct(d.chance) and (" " .. Pct(d.chance)) or ""), "drop"
    end
    local q = g.quests[1]
    if q then return string.format(L["quest: %s"], q.name), "quest" end
    if g.world then return string.format(L["a world drop (level %d+)"], g.world), "world" end
    local b = g.boxes[1]
    if b then return string.format(L["in %s"], FT.ItemText(b.itemID, 24)), "box" end
    return nil
end
