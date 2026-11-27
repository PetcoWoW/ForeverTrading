-- Wolf: the Wolf network (v0.42). Wolf users in your guild and group share, in small hidden addon messages, beside
-- the full-scan exchange (Share.lua):
--   L  live prices: after your own scan, the prices that changed (not the whole scan) - others take them at once,
--      no /reload
--   F  farm rates: what your farm log saw per mob (corpses, items) - pooled into Forever's real drops
--   S  sale prices: what sold of yours (the auction house mail) - "Wolf users sold N lately at ~X"
--   G  deal calls: a watchlist deal you found at the auction house - one chat line for the others
--   V  recipe merchants (v0.43): a vendor selling a recipe, where it stands - the craft window says it
--   O  nodes and chests (v0.50): which one gave what - with F, Wolf's own Forever loot table
-- The junk guard: a price far from what we know (3x or more either way) is held until a second user agrees (within
-- 10%, inside two hours); anything 50x off is dropped. Only guild and group: Forever refuses addon messages in chat
-- channels. Nothing is sent in a fight; at most a message a second, queued.
local ADDON, FT = ...
local L = FT.L

local N = {}
FT.Net = N

local PREFIX = "WOLFNET1"
local PROTO = "1"
local SEND_EVERY = 1.2
local MSG_MAX = 236          -- (and the version, a few more)
local MAX_LIVE = 400          -- prices in one round of live updates
local CHANGED = 0.03          -- a price counts as changed from 3% on
local OUTLIER = 3             -- 3x either way of what we know: held until a second user agrees
local DROP = 50               -- 50x: dropped
local AGREE = 0.10
local AGREE_WITHIN = 2 * 3600
local FARM_EVERY = 30 * 60
local DEAL_GAP = 30 * 60      -- the same item's deal said again at most this often
local DEALS_AN_HOUR = 6

local queue = {}
local pending = {} -- id -> { p, from, t } a price waiting for a second user
local heardDeal, dealsHour, dealsHourAt = {}, 0, 0

local function On() return FT.S and FT.S.net ~= false end
local function Enc(n) return FT.Hist.Enc(math.floor(n + 0.5)) end
local function Dec(s) return FT.Hist.Dec(s) end
-- times go over the wire as server time: clocks differ
local function Skew() return (GetServerTime and GetServerTime() or time()) - time() end
local function Wire(t) return t + Skew() end
local function Local(w) return w - Skew() end
local function Short(name) return name and (name:gsub("%-.*$", "")) or "?" end
local function IsMe(sender)
    local me = UnitName and UnitName("player")
    return me and Short(sender) == me
end
local function Fighting() return InCombatLockdown and InCombatLockdown() end

local function Channels()
    local out = {}
    if IsInGuild and IsInGuild() then out[#out + 1] = "GUILD" end
    if IsInRaid and IsInRaid() then out[#out + 1] = "RAID" elseif IsInGroup and IsInGroup() then out[#out + 1] = "PARTY" end
    return out
end

-- v0.50: every message ends with the sender's Wolf version ("v0.50"): a newer one heard means one chat line
-- (FT.Ver.Heard). Older Wolfs read the fields they know and leave the rest.
local function VerTag()
    local a, b = tostring(FT.VERSION or ""):match("^v?(%d+)%.(%d+)")
    return a and ("v" .. a .. "." .. b) or nil
end
N.VerTag = VerTag

local function Push(...)
    if not On() then return end
    local parts = { ... }
    local tag = VerTag()
    if tag then parts[#parts + 1] = tag end
    local text = table.concat(parts, "\t")
    if #text > 250 then return end
    for _, ch in ipairs(Channels()) do queue[#queue + 1] = { ch, text } end
end

local function Pump()
    if #queue == 0 or Fighting() or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    local m = table.remove(queue, 1)
    pcall(C_ChatInfo.SendAddonMessage, PREFIX, m[2], m[1])
end

-- what's in the queue (for the Settings line and the tests)
function N.Queued() return #queue end

---------------------------------------------------------------------------
-- The junk guard
---------------------------------------------------------------------------
-- "take": use it now; "hold": far off, waiting for a second user; "drop"
local function Guard(id, p, from, t)
    local own = FT.Price(id)
    local s = FT.An and FT.An.Stats(id)
    local known = (s and (s.fair or s.avg)) or own
    if not known or known <= 0 then return "take" end
    local r = p / known
    if r > DROP or r < 1 / DROP then return "drop" end
    if r < OUTLIER and r > 1 / OUTLIER then return "take" end
    local w = pending[id]
    if w and Short(w.from) ~= Short(from) and math.abs(w.p - p) <= AGREE * math.max(w.p, p) and math.abs(w.t - t) <= AGREE_WITHIN then
        pending[id] = nil
        return "take", (w.p + p) / 2
    end
    pending[id] = { p = p, from = from, t = t }
    return "hold"
end
N.Guard = Guard

---------------------------------------------------------------------------
-- L: live prices
---------------------------------------------------------------------------
local function SentDB()
    FT.db.netSent = FT.db.netSent or {}
    local k = FT.houseKey or "?"
    FT.db.netSent[k] = FT.db.netSent[k] or {}
    return FT.db.netSent[k]
end

-- the prices of our scan that changed since we last said them: the busiest first, MAX_LIVE at most
function N.Changed()
    local rows = FT.Market.Rows() or {}
    local sent = SentDB()
    local out = {}
    for _, r in ipairs(rows) do
        if r.id and r.price and r.price > 0 then
            local was = sent[r.id]
            if not was or math.abs(r.price - was) > was * CHANGED then out[#out + 1] = r end
        end
    end
    table.sort(out, function(a, b) return (a.price * (a.qty or 1)) > (b.price * (b.qty or 1)) end)
    while #out > MAX_LIVE do table.remove(out) end
    return out
end

function N.SendLive(t)
    if not On() or #Channels() == 0 then return 0 end
    local list = N.Changed()
    if #list == 0 then return 0 end
    local sent = SentDB()
    local head = { "L", PROTO, FT.houseKey or "?", Enc(Wire(t or time())) }
    local parts, len, n = {}, 0, 0
    local function Flush()
        if #parts == 0 then return end
        local h = table.concat(head, "\t")
        Push(h, table.concat(parts, ";"))
        parts, len = {}, 0
    end
    local base = #table.concat(head, "\t") + 1
    for _, r in ipairs(list) do
        local rec = Enc(r.id) .. "," .. Enc(r.price)
        if base + len + #rec + 1 > MSG_MAX then Flush() end
        parts[#parts + 1] = rec
        len = len + #rec + 1
        sent[r.id] = r.price
        n = n + 1
    end
    Flush()
    return n
end

local function OnLive(sender, side, tWire, payload)
    if side ~= FT.houseKey or type(payload) ~= "string" then return end
    local t = math.min(Local(Dec(tWire) or 0), time())
    if time() - t > 3 * 3600 then return end
    local took = 0
    for rec in payload:gmatch("[^;]+") do
        local a, b = rec:match("^(%w+),(%w+)$")
        local id, p = Dec(a), Dec(b)
        if id and p and id > 0 and p > 0 and p < 1e10 then
            local verdict, agreed = Guard(id, p, sender, t)
            if verdict == "take" then
                FT.Hist.Observe(id, agreed or p, nil, nil, t, "peer")
                took = took + 1
            end
        end
    end
    if took > 0 then
        N.lastLive = { from = Short(sender), n = took, t = t }
        FT.Debounce("netLive", 2, function() FT.Fire("FT_PRICES_CHANGED", "peer") end)
    end
end

-- our own scan done: say what changed (a few seconds after, the market list first)
FT.On("FT_SCAN_DONE", function(kind)
    if kind == "peer" or not On() then return end
    C_Timer.After(5, function() N.SendLive(time()) end)
end)

---------------------------------------------------------------------------
-- F: farm rates - per mob, what our farm log saw
---------------------------------------------------------------------------
function N.SendFarm(force)
    if not On() or #Channels() == 0 then return 0 end
    local mobs = FT.db.farm and FT.db.farm.mobs or {}
    FT.db.netFarmSent = FT.db.netFarmSent or {}
    local n = 0
    for npc, m in pairs(mobs) do
        if (m.c or 0) >= 5 and (force or FT.db.netFarmSent[npc] ~= m.c) then
            local items = {}
            for id, got in pairs(m.items or {}) do
                items[#items + 1] = Enc(id) .. ":" .. Enc(got)
                if #items >= 12 then break end
            end
            if #items > 0 then
                local name = (m.n or "?"):gsub("[\t;:,]", " "):sub(1, 30)
                Push("F", PROTO, Enc(tonumber(npc) or 0), name, Enc(m.c), table.concat(items, ","))
                FT.db.netFarmSent[npc] = m.c
                n = n + 1
                if n >= 20 then break end
            end
        end
    end
    return n
end

-- O (v0.50): the same for nodes and chests - which one gave what, so Forever's new things find their source
function N.SendObjects(force)
    if not On() or #Channels() == 0 then return 0 end
    local objs = FT.db.farm and FT.db.farm.objs or {}
    FT.db.netObjSent = FT.db.netObjSent or {}
    local n = 0
    for obj, o in pairs(objs) do
        if (o.c or 0) >= 3 and (force or FT.db.netObjSent[obj] ~= o.c) then
            local items = {}
            for id, got in pairs(o.items or {}) do
                items[#items + 1] = Enc(id) .. ":" .. Enc(got)
                if #items >= 12 then break end
            end
            if #items > 0 then
                local zone = (o.z or "?"):gsub("[\t;:,]", " "):sub(1, 30)
                Push("O", PROTO, Enc(tonumber(obj) or 0), zone, Enc(o.c), table.concat(items, ","))
                FT.db.netObjSent[obj] = o.c
                n = n + 1
                if n >= 20 then break end
            end
        end
    end
    return n
end

local function OnObjects(sender, objText, zone, cText, itemsText)
    local obj, c = Dec(objText), Dec(cText)
    if not (obj and c and c > 0 and c < 1e6 and type(itemsText) == "string") then return end
    FT.db.netObj = FT.db.netObj or {}
    local o = FT.db.netObj[obj] or { by = {} }
    o.z = zone
    local items = {}
    for a, b in itemsText:gmatch("(%w+):(%w+)") do
        local id, got = Dec(a), Dec(b)
        if id and got and got >= 0 and got <= c * 20 then items[id] = got end
    end
    o.by[Short(sender)] = { c = c, items = items, t = time() }
    FT.db.netObj[obj] = o
end

-- the best node or chest for an item, pooled: "Wolf users: <node> 0.12 a node (340 nodes) · <zone>"
function N.LootText(id)
    local best, bestPer, bestC, bestObj
    for obj, o in pairs(FT.db and FT.db.netObj or {}) do
        local c, got = 0, 0
        for _, b in pairs(o.by or {}) do
            if b.items and b.items[id] then c, got = c + b.c, got + b.items[id] end
        end
        if c >= 10 and got > 0 and (not bestPer or got / c > bestPer) then best, bestPer, bestC, bestObj = o, got / c, c, obj end
    end
    if not best then return nil end
    local name = FT.SRC_O and FT.SRC_O[bestObj] and FT.SRC_O[bestObj]:match("^([^|]*)") or L["a node"]
    return FT.C("text", name) .. FT.C("dim", "  ·  " .. string.format(L["Wolf users: %s a node (%s nodes)"], string.format("%.2f", bestPer), FT.Num(bestC))
        .. (best.z and ("  ·  " .. best.z) or ""))
end

local function OnFarm(sender, npcText, name, cText, itemsText)
    local npc, c = Dec(npcText), Dec(cText)
    if not (npc and c and c > 0 and c < 1e6 and type(itemsText) == "string") then return end
    FT.db.netFarm = FT.db.netFarm or {}
    local m = FT.db.netFarm[npc] or { by = {} }
    m.n = name
    local items = {}
    for a, b in itemsText:gmatch("(%w+):(%w+)") do
        local id, got = Dec(a), Dec(b)
        -- a drop rate over 20 a corpse is a mistake
        if id and got and got >= 0 and got <= c * 20 then items[id] = got end
    end
    m.by[Short(sender)] = { c = c, items = items, t = time() }
    FT.db.netFarm[npc] = m
end

-- the best mob for an item, pooled over every Wolf user heard: "Wolf users: <mob> 0.35 a corpse (120 corpses)"
function N.FarmText(id)
    local best, bestPer, bestC
    for _, m in pairs(FT.db and FT.db.netFarm or {}) do
        local c, got = 0, 0
        for _, b in pairs(m.by or {}) do
            if b.items and b.items[id] then c, got = c + b.c, got + b.items[id] end
        end
        if c >= 10 and got > 0 and (not bestPer or got / c > bestPer) then best, bestPer, bestC = m, got / c, c end
    end
    if not best then return nil end
    return FT.C("text", best.n or "?") .. FT.C("dim", "  ·  " .. string.format(L["Wolf users: %s a corpse (%s corpses)"], string.format("%.2f", bestPer), FT.Num(bestC)))
end

---------------------------------------------------------------------------
-- S: sale prices
---------------------------------------------------------------------------
function N.Sold(id, unit, qty, t)
    if not (id and unit and unit > 0) then return end
    Push("S", PROTO, FT.houseKey or "?", Enc(id), Enc(unit), Enc(qty or 1), Enc(Wire(t or time())))
end

local function OnSold(sender, side, a, b, c, d)
    if side ~= FT.houseKey then return end
    local id, unit, qty, w = Dec(a), Dec(b), Dec(c), Dec(d)
    if not (id and unit and unit > 0 and qty and qty > 0 and w) then return end
    if Guard(id, unit, sender, Local(w)) == "drop" then return end
    FT.db.netSales = FT.db.netSales or {}
    local list = FT.db.netSales[id] or {}
    list[#list + 1] = { u = unit, q = qty, t = Local(w), by = Short(sender) }
    while #list > 20 do table.remove(list, 1) end
    FT.db.netSales[id] = list
end

-- "Wolf users sold 12 in the last week at ~38g" (nil: none heard)
function N.SoldText(id)
    local list = FT.db and FT.db.netSales and FT.db.netSales[id]
    if not list then return nil end
    local q, v, from = 0, 0, time() - 7 * 86400
    for _, x in ipairs(list) do
        if x.t >= from then q, v = q + x.q, v + x.u * x.q end
    end
    if q == 0 then return nil end
    return string.format(L["Wolf users sold %s this week at ~%s"], FT.Num(q), FT.Money(math.floor(v / q), "short"))
end

-- our sales, from the journal (the auction house mail)
if FT.Journal and FT.Journal.Add then
    local realAdd = FT.Journal.Add
    FT.Journal.Add = function(k, itemID, qty, value, fee, t)
        realAdd(k, itemID, qty, value, fee, t)
        if k == "S" and itemID and (qty or 0) > 0 and (value or 0) > 0 then N.Sold(itemID, value / qty, qty, t) end
    end
end

---------------------------------------------------------------------------
-- G: deal calls
---------------------------------------------------------------------------
function N.Deal(id, price, under)
    if not (id and price) then return end
    Push("G", PROTO, FT.houseKey or "?", Enc(id), Enc(price), Enc(math.floor(math.abs(under or 0) * 100)))
end

local function OnDeal(sender, side, a, b, c)
    if side ~= FT.houseKey or FT.S.netDeals == false then return end
    local id, price, pct = Dec(a), Dec(b), Dec(c)
    if not (id and price and pct) or pct < 10 or pct > 95 then return end
    if heardDeal[id] and time() - heardDeal[id] < DEAL_GAP then return end
    if time() - dealsHourAt > 3600 then dealsHour, dealsHourAt = 0, time() end
    if dealsHour >= DEALS_AN_HOUR then return end
    heardDeal[id] = time()
    dealsHour = dealsHour + 1
    FT.Print(FT.C("accent", string.format(L["Wolf · %s"], Short(sender))) .. "  " .. string.format(L["%s listed at %s, %d%% under usual"],
        FT.ItemText(id), FT.Money(price, "short"), pct))
end

---------------------------------------------------------------------------
-- V: a merchant that sells a recipe (v0.43)
---------------------------------------------------------------------------
local function Clean(t) return (tostring(t or ""):gsub("[\t|]", " "):sub(1, 40)) end
function N.RecipeVendor(id, npc, zone, price, limited)
    if not (id and npc) then return end
    Push("V", PROTO, FT.houseKey or "?", Enc(id), Clean(npc), Clean(zone), Enc(price or 0), limited and "1" or "0")
end

local function OnVendor(sender, side, a, npc, zone, b, lim)
    local id = Dec(a)
    if not (id and npc and npc ~= "") then return end
    local _, _, _, _, _, classID = FT.GetItemInfoInstant(id)
    if classID and classID ~= 9 then return end
    FT.db.recipeVendors = FT.db.recipeVendors or {}
    if FT.db.recipeVendors[id] then return end -- your own sighting (or the first one heard) stays
    local price = Dec(b)
    FT.db.recipeVendors[id] = { n = Clean(npc), z = Clean(zone), p = (price and price > 0) and price or nil, l = lim == "1" or nil,
        t = time(), by = Short(sender) }
end

---------------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------------
FT.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    if prefix ~= PREFIX or type(text) ~= "string" or not sender or IsMe(sender) or not On() then return end
    if channel ~= "GUILD" and channel ~= "PARTY" and channel ~= "RAID" then return end
    local kind, proto, a, b, c, d, e = strsplit("\t", text)
    if proto ~= PROTO then return end
    if FT.Share and FT.Share.Met then FT.Share.Met(sender) end
    local ver = text:match("\t(v%d+%.%d+)$")
    if ver and FT.Ver and FT.Ver.Heard then FT.Ver.Heard(ver) end
    if kind == "L" then OnLive(sender, a, b, c)
    elseif kind == "F" then OnFarm(sender, a, b, c, d)
    elseif kind == "O" then OnObjects(sender, a, b, c, d)
    elseif kind == "S" then OnSold(sender, a, b, c, d, e)
    elseif kind == "G" then OnDeal(sender, a, b, c, d)
    elseif kind == "V" then OnVendor(sender, a, b, c, d, e, select(8, strsplit("\t", text)))
    end
end)

FT.On("FT_LOGIN", function()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
end)

FT.On("FT_READY", function()
    C_Timer.NewTicker(SEND_EVERY, Pump)
    C_Timer.After(90, function() N.SendFarm(false); N.SendObjects(false) end)
    C_Timer.NewTicker(FARM_EVERY, function() N.SendFarm(false); N.SendObjects(false) end)
end)
