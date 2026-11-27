local _, FT = ...
local L = FT.L

-- Farming: where a raw material comes from (Data/FarmSpots.lua), what YOU looted where (the farm log, kept from
-- every loot window: the zone, and which mob or node it came from), Wowhead links, and the farm tip in chat
local F = {}
FT.Farm = F

---------------------------------------------------------------------------
-- Wowhead (WoW Forever's pages): a link to copy - an addon can't open the browser
---------------------------------------------------------------------------
local WOWHEAD = "https://www.wowhead.com/forever/"

function F.WowheadURL(kind, id)
    if kind == "search" then
        return WOWHEAD .. "search?q=" .. tostring(id):gsub("[^%w]", function(c) return string.format("%%%02X", c:byte()) end)
    end
    return WOWHEAD .. kind .. "=" .. tostring(id)
end

function F.Wowhead(itemID)
    if not itemID then return end
    FT.ShowLink(FT.ItemText(itemID, 40), L["Wowhead: copy the link (Ctrl+C) and paste it in your browser."], F.WowheadURL("item", itemID))
end

function F.WowheadSearch(text)
    if not text or text == "" then return end
    FT.ShowLink(text, L["Wowhead: copy the link (Ctrl+C) and paste it in your browser."], F.WowheadURL("search", text))
end

---------------------------------------------------------------------------
-- What kind of raw material an item is (Trade Goods: 5 cloth, 6 leather, 7 metal & stone, 9 herb, 10 elemental)
---------------------------------------------------------------------------
local CLASS = { ore = { 7, 7 }, herb = { 7, 9 }, leather = { 7, 6 }, cloth = { 7, 5 }, elemental = { 7, 10 }, gem = { 3 } }
F.CLASS = CLASS

function F.KindOfRow(r)
    if not r then return nil end
    for k, c in pairs(CLASS) do
        if r.cls == c[1] and (c[2] == nil or r.sub == c[2]) then return k end
    end
    return nil
end

function F.KindOf(id)
    local s = FT.FarmSpots and FT.FarmSpots[id]
    if s then return s.kind end
    return F.KindOfRow(FT.Market.Row(id))
end

-- a raw material: something you farm (the Where to farm button shows for it)
function F.IsRaw(id)
    return id ~= nil and F.KindOf(id) ~= nil
end

---------------------------------------------------------------------------
-- Where to farm it for your level: Classic's spots, nearest your level first
---------------------------------------------------------------------------
local function Level() return (UnitLevel and UnitLevel("player")) or 60 end

-- { { zone, lo, hi, what, fit (0: your level is in it), yours = the log's numbers there or nil } }
function F.Spots(id, level)
    level = level or Level()
    local s = FT.FarmSpots and FT.FarmSpots[id]
    local out = {}
    for i, sp in ipairs(s and s.spots or {}) do
        local lo, hi = sp[2], sp[3]
        local fit = (level < lo and lo - level) or (level > hi and level - hi) or 0
        out[#out + 1] = { zone = sp[1], lo = lo, hi = hi, what = sp[4], fit = fit, order = i, yours = F.ZoneFor(sp[1], id) }
    end
    table.sort(out, function(a, b)
        -- too low for you counts less against it than too high (you can farm lower mobs, not higher ones)
        local fa = a.lo > level and a.fit * 2 or a.fit
        local fb = b.lo > level and b.fit * 2 or b.fit
        if fa ~= fb then return fa < fb end
        return a.order < b.order
    end)
    return out, s
end

-- the spots of it that suit your level (within a few levels): their zone names, best first
function F.ForYou(id, level, n)
    level = level or Level()
    local names = {}
    for _, sp in ipairs((F.Spots(id, level))) do
        if level >= sp.lo - 3 and level <= sp.hi + 8 then names[#names + 1] = sp.zone end
        if #names >= (n or 3) then break end
    end
    return names
end

---------------------------------------------------------------------------
-- The farm log: every loot window - the zone, what was looted, and the mob (or node) it came from. Your time
-- in a zone counts while you loot (the gap between two loots, up to 3 minutes; the first one, 30 seconds).
---------------------------------------------------------------------------
local GAP_MAX, FIRST = 180, 30
local MAX_MOBS = 600

local function DB()
    FT.db.farm = FT.db.farm or { zones = {}, mobs = {} }
    return FT.db.farm
end

local function ZoneName()
    return (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or "?"
end

local function ZoneRec(name)
    local d = DB()
    local z = d.zones[name]
    if not z then
        z = { secs = 0, money = 0, items = {}, corpses = 0, nodes = 0 }
        d.zones[name] = z
    end
    return z
end

local function Tick(z)
    local now = time()
    local gap = z.last and (now - z.last) or nil
    z.secs = z.secs + ((gap and gap <= GAP_MAX) and gap or FIRST)
    z.last = now
end

local function NpcFromGUID(guid)
    if type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    return kind, tonumber(id)
end

-- the name and level of the mob a corpse is (your target or what's under the mouse, when it's that one)
local function WhoIs(guid)
    for _, u in ipairs({ "target", "mouseover", "softenemy" }) do
        if UnitGUID and UnitGUID(u) == guid then return UnitName(u), UnitLevel(u) end
    end
    return nil, nil
end

local opened = {}   -- corpses looted this login (a second loot of the same one - skinning - is no new corpse)
local openedN = 0

local function Prune(d)
    local n, list = 0, {}
    for id, m in pairs(d.mobs) do n = n + 1; list[#list + 1] = { id, m.c or 0 } end
    if n <= MAX_MOBS then return end
    table.sort(list, function(a, b) return a[2] < b[2] end)
    for i = 1, n - MAX_MOBS do d.mobs[list[i][1]] = nil end
end

function F.OnLoot()
    if not (GetNumLootItems and GetLootSlotLink) then return end
    local d = DB()
    -- one loot window counted once (the game tells LOOT_READY and LOOT_OPENED for it): until it closes
    if d.open then return end
    d.open = true
    local zname = ZoneName()
    local z = ZoneRec(zname)
    Tick(z)
    local fishing = IsFishingLoot and IsFishingLoot()
    local newMobs = false
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id then
            local qty = (GetLootSlotInfo and select(3, GetLootSlotInfo(slot))) or 1
            qty = tonumber(qty) or 1
            z.items[id] = (z.items[id] or 0) + qty
            -- where it came from (a corpse, a vein or a herb; AoE looting: several)
            if not fishing and GetLootSourceInfo then
                local src = { GetLootSourceInfo(slot) }
                for k = 1, #src, 2 do
                    local guid, n = src[k], tonumber(src[k + 1]) or qty
                    local kind, npc = NpcFromGUID(guid)
                    if kind == "Creature" and npc then
                        local m = d.mobs[npc]
                        if not m then
                            m = { c = 0, items = {}, z = zname }
                            d.mobs[npc] = m
                            newMobs = true
                        end
                        if not opened[guid] then
                            opened[guid] = true
                            openedN = openedN + 1
                            m.c = m.c + 1
                            z.corpses = z.corpses + 1
                        end
                        if not m.n then
                            local name, lv = WhoIs(guid)
                            if name then m.n, m.lv = name, lv end
                        end
                        m.items[id] = (m.items[id] or 0) + n
                    elseif kind == "GameObject" and not opened[guid] then
                        opened[guid] = true
                        openedN = openedN + 1
                        z.nodes = z.nodes + 1
                    end
                end
            end
        end
    end
    if openedN > 5000 then opened, openedN = {}, 0 end
    if newMobs then Prune(d) end
    FT.Fire("FT_FARM_LOGGED")
end

FT.On("LOOT_READY", function() pcall(F.OnLoot) end)
FT.On("LOOT_OPENED", function() pcall(F.OnLoot) end)
FT.On("LOOT_CLOSED", function() if FT.db and FT.db.farm then FT.db.farm.open = nil end end)
FT.On("FT_DB_READY", function() if FT.db and FT.db.farm then FT.db.farm.open = nil end end)
FT.On("CHAT_MSG_MONEY", function(msg)
    local c = FT.Session and FT.Session.ParseMoney and FT.Session.ParseMoney(msg) or 0
    if c > 0 then ZoneRec(ZoneName()).money = ZoneRec(ZoneName()).money + c end
end)

-- your numbers of an item in a zone: { perHour (how many an hour), goldHour (all you looted there, at today's
-- prices, an hour), mins } - nil until you've looted there for 5 minutes and it dropped
function F.ZoneFor(zone, id)
    local z = FT.db and FT.db.farm and FT.db.farm.zones[zone]
    if not z or (z.secs or 0) < 300 then return nil end
    local n = z.items[id] or 0
    if n == 0 then return nil end
    return { perHour = n / z.secs * 3600, goldHour = F.ZoneGoldHour(zone), mins = math.floor(z.secs / 60), n = n }
end

-- all you looted in a zone, at today's prices (or a vendor's), and money, an hour
function F.ZoneGoldHour(zone)
    local z = FT.db and FT.db.farm and FT.db.farm.zones[zone]
    if not z or (z.secs or 0) < 300 then return nil end
    local worth = z.money or 0
    local Unit = FT.Session and FT.Session.UnitValue
    for id, n in pairs(z.items) do worth = worth + ((Unit and Unit(id)) or FT.Price(id) or 0) * n end
    return worth / z.secs * 3600
end

-- the mobs YOU looted it from: { { npc, name, lv, zone, corpses, n, per (a corpse) } }, most per corpse first
-- (5 corpses or more, so one lucky drop doesn't top it)
function F.Mobs(id, n)
    local out = {}
    for npc, m in pairs(FT.db and FT.db.farm and FT.db.farm.mobs or {}) do
        local got = m.items[id]
        if got and (m.c or 0) >= 5 then
            out[#out + 1] = { npc = npc, name = m.n, lv = m.lv, zone = m.z, corpses = m.c, n = got, per = got / m.c }
        end
    end
    table.sort(out, function(a, b)
        if a.per ~= b.per then return a.per > b.per end
        return a.corpses > b.corpses
    end)
    while #out > (n or 6) do table.remove(out) end
    return out
end

-- your zones with it: { { zone, perHour, goldHour, mins } }, most an hour first
function F.YourZones(id, n)
    local out = {}
    for zone in pairs(FT.db and FT.db.farm and FT.db.farm.zones or {}) do
        local y = F.ZoneFor(zone, id)
        if y then y.zone = zone; out[#out + 1] = y end
    end
    table.sort(out, function(a, b) return a.perHour > b.perHour end)
    while #out > (n or 4) do table.remove(out) end
    return out
end

---------------------------------------------------------------------------
-- The farm tip, in chat (never on screen): a raw material for your level (and professions) selling well - up this
-- week (15%+) and selling every day (20+) - with where to get it and [Where to farm]. Once at login and after
-- fresh prices, one tip in two hours at most, the same item not again for a day; never inside a dungeon.
---------------------------------------------------------------------------
local TIP_EVERY, SAME_AGAIN = 2 * 3600, 24 * 3600
local UP, PER_DAY = 0.15, 20

-- can this character get it: cloth and elementals anyone; herbs and ore need the profession at its skill,
-- leather needs Skinning (professions are read from the skill list at login: none seen yet, no gathering tips)
local NEEDS = { herb = "Herbalism", ore = "Mining", leather = "Skinning" }
function F.CanGet(id)
    local s = FT.FarmSpots and FT.FarmSpots[id]
    if not s then return false end
    local prof = NEEDS[s.kind]
    if not prof then return true end
    local c = FT.charKey and FT.db.chars and FT.db.chars[FT.charKey]
    local rank = c and type(c.profs) == "table" and c.profs[prof]
    if not rank then return false end
    return rank >= (s.skill or 1)
end

function F.BestTip(level)
    level = level or Level()
    local best, bestV
    for id in pairs(FT.FarmSpots or {}) do
        local r = FT.Market.Row(id)
        if r and r.price and (r.ch7 or 0) >= UP and r.ch7 <= 3 and F.CanGet(id) and #F.ForYou(id, level, 1) > 0 then
            local rate = FT.Sales.Rate(id)
            local perDay = rate and rate.perDay or 0
            if perDay >= PER_DAY then
                local v = r.price * math.min(perDay * 0.2, 40)
                if not bestV or v > bestV then best, bestV = { id = id, row = r, perDay = perDay }, v end
            end
        end
    end
    return best
end

function F.TipText(t, level)
    level = level or Level()
    local zones = F.ForYou(t.id, level, 2)
    return string.format(L["Farm tip: %s %s each, %s this week, ~%s sell a day. At %d: %s."], FT.ItemText(t.id),
        FT.Money(t.row.price, "short"), FT.C("up", FT.Pct(t.row.ch7)), FT.Num(math.floor(t.perDay + 0.5)), level,
        table.concat(zones, ", "))
end

function F.MaybeTip()
    if not (FT.S and FT.S.farmTips) then return end
    if IsInInstance and IsInInstance() then return end
    FT.db.farmTip = FT.db.farmTip or { said = {} }
    local ft = FT.db.farmTip
    if ft.at and time() - ft.at < TIP_EVERY then return end
    local t = F.BestTip()
    if not t then return end
    if ft.said[t.id] and time() - ft.said[t.id] < SAME_AGAIN then return end
    ft.at, ft.said[t.id] = time(), time()
    FT.Print(F.TipText(t) .. " " .. FT.ChatLink("farm", L["Where to farm"], "", t.id))
    return t
end

FT.ChatAction("farm", function(arg)
    local id = tonumber(arg)
    if id and FT.ShowFarm then FT.ShowFarm(id) end
end)

local tipped = false
FT.On("FT_MARKET_READY", function()
    if tipped then return end
    tipped = true
    C_Timer.After(30, function() pcall(F.MaybeTip) end)
end)
FT.On("FT_SCAN_DONE", function() FT.Debounce("farmTip", 25, function() pcall(F.MaybeTip) end) end)
