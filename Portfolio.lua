-- Wolf: what your characters own (bags, bank, mail) and what it is worth at market prices.
local ADDON, FT = ...

local L = FT.L
local P = {}
FT.Port = P

local holdings = nil
FT.On("FT_INVENTORY_CHANGED", function() holdings = nil end)
FT.On("FT_SOURCES_CHANGED", function() holdings = nil end)

-- itemID -> { id, total, chars = { [name] = { bags, bank, mail } } }
function P.Holdings()
    if holdings then return holdings end
    local out = {}
    local function Add(name, id, n, where)
        if type(id) ~= "number" or type(n) ~= "number" or n <= 0 then return end
        local h = out[id]
        if not h then
            h = { id = id, total = 0, chars = {} }
            out[id] = h
        end
        h.total = h.total + n
        local c = h.chars[name]
        if not c then
            c = { bags = 0, bank = 0, mail = 0, post = 0 }
            h.chars[name] = c
        end
        c[where] = c[where] + n
    end
    local seen, mailSeen = {}, {}
    -- our own reading (soulbound items left out)
    for guid, inv in pairs(FT.db.inv) do
        local c = FT.db.chars[guid]
        if c and c.side == FT.sideKey and type(inv) == "table" then
            seen[guid] = true
            for id, n in pairs(inv.bags or {}) do Add(c.name or "?", id, n, "bags") end
            for id, n in pairs(inv.bank or {}) do Add(c.name or "?", id, n, "bank") end
            if inv.mailT then
                mailSeen[guid] = true
                for id, n in pairs(inv.mail or {}) do Add(c.name or "?", id, n, "mail") end
            end
        end
    end
    -- sent to one of your characters and not in its mailbox reading yet: still yours
    for _, x in ipairs(FT.db.transit or {}) do
        if x.side == FT.sideKey then
            for id, n in pairs(x.items or {}) do Add(x.toName or "?", id, n, "post") end
        end
    end
    holdings = out
    return out
end

-- gold in a character's mailbox (its last reading) and on its way there from your other characters
function P.MailGold(guid)
    local inv = FT.db.inv[guid]
    local g = inv and inv.mailT and inv.mailGold or 0
    for _, x in ipairs(FT.db.transit or {}) do
        if x.to == guid then g = g + (x.gold or 0) end
    end
    return g
end

function P.EachHolding(fn)
    for id in pairs(P.Holdings()) do fn(id) end
end

function P.Count(itemID)
    local h = P.Holdings()[itemID]
    return h and h.total or 0
end

-- gold of this side's characters
function P.Gold()
    local total, seen = 0, {}
    if FT.charKey then
        total = GetMoney()
        seen[FT.charKey] = true
    end
    for guid, c in pairs(FT.db.chars) do
        if not seen[guid] and c.side == FT.sideKey and type(c.money) == "number" then
            total = total + c.money
            seen[guid] = true
        end
    end
    -- in mailboxes and on the way between your characters (a bank alt's gold before it opens the mailbox)
    for guid, c in pairs(FT.db.chars) do
        if c.side == FT.sideKey then total = total + P.MailGold(guid) end
    end
    return total
end

-- priced holdings, the most valuable first: { id, qty, price, value, ch7, stats, signal, reason, chars }
function P.Rows()
    local out, total, total7 = {}, 0, 0
    for id, h in pairs(P.Holdings()) do
        local s = FT.An.Stats(id)
        if s.price then
            local value = s.price * h.total
            local signal, strength, reason = FT.An.SellSignal(s)
            out[#out + 1] = { id = id, qty = h.total, price = s.price, value = value, ch7 = s.ch7, stats = s,
                signal = signal, strength = strength, reason = reason, chars = h.chars }
            total = total + value
            total7 = total7 + (s.ch7 and value / (1 + s.ch7) or value)
        end
    end
    table.sort(out, function(a, b) return a.value > b.value end)
    return out, total, total7
end

---------------------------------------------------------------------------
-- What you own, at every price update (v0.42): a snapshot each time new prices come in (Blizzard's with a reload,
-- your scans, a guild member's scan). { t = the prices' time, v = items + listings + gold, at = when it was taken,
-- move = what those prices did }, the last 48 per side. Today shows what the last one did to your worth.
---------------------------------------------------------------------------
local SNAPS = 48

local function PricesTime()
    local scanT = FT.ScanTime and FT.ScanTime() or nil
    local apiT = FT.Feed and FT.Feed.On() and FT.Feed.Time() or nil
    local t = math.max(scanT or 0, apiT or 0)
    return t > 0 and t or nil
end

-- your listings on the auction house at market price (not sold yet): posting moves an item there, it stays yours
function P.ListedWorth()
    local total = 0
    if not (FT.Owned and FT.Owned.List) then return 0 end
    for _, b in ipairs((FT.Owned.List())) do
        if b.itemID and not b.sold then
            local s = FT.An.Stats(b.itemID)
            if s and s.price then total = total + s.price * (b.qty or 1) end
        end
    end
    return total
end

-- items (bags, bank, mail, on the way), listings and gold: what Today's "Everything you own" says
function P.Worth()
    local total = 0
    for id, h in pairs(P.Holdings()) do
        local s = FT.An.Stats(id)
        if s and s.price then total = total + s.price * h.total end
    end
    return total + P.ListedWorth() + P.Gold()
end

function P.Snaps()
    if not FT.db then return {} end
    FT.db.worthLog = FT.db.worthLog or {}
    local key = FT.sideKey or "?"
    FT.db.worthLog[key] = FT.db.worthLog[key] or {}
    return FT.db.worthLog[key]
end

-- What you did today, at the prices of the moment: loot, gold, buys, crafts, sales (a price update is not in it).
-- { day, v } per side; a new day starts again from 0.
function P.Played()
    if not (FT.db and FT.sideKey) then return 0 end
    FT.db.worthPlay = FT.db.worthPlay or {}
    local x = FT.db.worthPlay[FT.sideKey]
    if not x or x.day ~= FT.Day() then return 0 end
    return x.v or 0
end

local function AddPlayed(d)
    FT.db.worthPlay = FT.db.worthPlay or {}
    local x = FT.db.worthPlay[FT.sideKey]
    if not x or x.day ~= FT.Day() then
        x = { day = FT.Day(), v = 0 }
        FT.db.worthPlay[FT.sideKey] = x
    end
    x.v = x.v + d
end

-- which readings the worth is made of: a character, bank or mailbox read for the first time adds what was already
-- there, which is not something you picked up
local function Readings()
    local k = 0
    for guid, inv in pairs(FT.db.inv or {}) do
        local c = FT.db.chars[guid]
        if c and c.side == FT.sideKey and type(inv) == "table" then
            k = k + 1 + (inv.bankT and 1000 or 0) + (inv.mailT and 1000000 or 0)
        end
    end
    return k
end

-- What you hold, counted (items with listings, and gold): what changed since the last count, at the prices of now,
-- is what you picked up or spent. Kept in memory only: the first count after a login is the starting point.
local basket
local function Count()
    local items = {}
    for id, h in pairs(P.Holdings()) do items[id] = h.total end
    if FT.Owned and FT.Owned.List then
        for _, b in ipairs((FT.Owned.List())) do
            if b.itemID and not b.sold then items[b.itemID] = (items[b.itemID] or 0) + (b.qty or 1) end
        end
    end
    return { items = items, gold = P.Gold(), k = Readings() }
end

local function TrackPlay()
    local now = Count()
    local before = basket
    basket = now
    if not before or before.k ~= now.k then return end
    local d = now.gold - before.gold
    for id, n in pairs(now.items) do
        local was = before.items[id] or 0
        if n ~= was then
            local s = FT.An.Stats(id)
            if s and s.price then d = d + (n - was) * s.price end
        end
    end
    for id, was in pairs(before.items) do
        if not now.items[id] then
            local s = FT.An.Stats(id)
            if s and s.price then d = d - was * s.price end
        end
    end
    d = math.floor(d)
    if d ~= 0 then AddPlayed(d) end
end
P.TrackPlay = TrackPlay

-- A snapshot is taken when new prices come in; its `move` is what those prices did (the worth just before them
-- is kept up to date as your bags and gold change, so what you picked up meanwhile is not counted as a move).
function P.Snapshot()
    if not (FT.db and FT.sideKey) then return end
    TrackPlay()
    local t = PricesTime()
    if not t then return end
    local list = P.Snaps()
    local last = list[#list]
    local v = math.floor(P.Worth())
    if v <= 0 then return end
    local k = basket and basket.k
    if last and last.t == t then
        -- the same prices: your things changed (counted above), not the prices
        last.v, last.at, last.k = v, time(), k
    elseif last and last.t > t then
        return -- older prices than the last snapshot's (a reload before the newest arrived): nothing to say
    else
        list[#list + 1] = { t = t, v = v, at = time(), k = k, move = (last and last.k == k) and (v - last.v) or nil }
        while #list > SNAPS do table.remove(list, 1) end
    end
    FT.Fire("FT_WORTH_CHANGED")
end

-- the last update's move, the move since about a day ago (nil when there's nothing to compare) and the newest snapshot
function P.WorthMoves()
    local list = P.Snaps()
    local n = #list
    if n == 0 then return nil end
    local now = list[n]
    local lastMove = now.move
    if lastMove == nil and n >= 2 and not now.k then lastMove = now.v - list[n - 1].v end -- a v0.42 snapshot
    local dayAgo
    for i = n - 1, 1, -1 do
        dayAgo = list[i]
        if now.t - list[i].t >= 20 * 3600 then break end
    end
    return lastMove, dayAgo and (now.v - dayAgo.v) or nil, now
end

FT.On("FT_MARKET_READY", function() FT.Debounce("worthSnap", 3, P.Snapshot) end)
FT.On("FT_SCAN_DONE", function() FT.Debounce("worthSnap", 3, P.Snapshot) end)
-- your things change (loot, mail, a buy, a craft, a listing, gold): the worth follows, and Today and You with it
local function Track() FT.Debounce("worthSnap", 2, P.Snapshot) end
FT.On("FT_INVENTORY_CHANGED", Track)
FT.On("FT_OWNED_CHANGED", Track)
FT.On("PLAYER_MONEY", Track)

-- worth of today's holdings on each of the last `days` days: { { t, value } }
function P.History(days)
    days = days or 14
    local today = FT.Day()
    local sums = {}
    for id, h in pairs(P.Holdings()) do
        local daily = FT.Hist.Daily(id, days + 3)
        if #daily > 0 then
            -- before its first known day an item counts at its first price (no false jump in the chart)
            local k, last = 1, daily[1].c
            for day = today - days + 1, today do
                while daily[k] and daily[k].day <= day do
                    last = daily[k].c
                    k = k + 1
                end
                if last then sums[day] = (sums[day] or 0) + last * h.total end
            end
        end
    end
    local out = {}
    for day = today - days + 1, today do
        if sums[day] then out[#out + 1] = { t = FT.DayStart(day), value = sums[day] } end
    end
    return out
end

-- The group a holding goes in, for the Portfolio list: "gear" (armor and weapons that bind when equipped: can be
-- sold), "mat" (trade goods, reagents, gems, anything a recipe uses), "crafted" (what professions make, potions and
-- other consumables) or "other"
local groupOf = {}
function P.Group(id)
    local g = groupOf[id]
    if g then return g end
    local _, _, _, equipLoc, _, classID = FT.GetItemInfoInstant(id)
    local bind = select(14, FT.GetItemInfo(id))
    if (classID == 2 or classID == 4) and equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" then
        g = (bind == 2 or bind == nil) and "gear" or "other"
        if bind == nil then return g end -- not loaded yet: asked again next time
    elseif classID == 7 or classID == 5 or classID == 3 or (FT.Craft and FT.Craft.UsedIn and FT.Craft.UsedIn(id)) then
        g = "mat"
    elseif classID == 0 or (FT.Craft and FT.Craft.ByOutput and FT.Craft.ByOutput(id)) then
        g = "crafted"
    else
        g = "other"
    end
    if classID then groupOf[id] = g end
    return g
end

-- Every character of this side (your bank alt too): gold, what its bags, bank and mail are worth, and when each
-- was last seen - a character counts only from its own logins, so an old "last seen" means old numbers.
-- { guid, name, classFile, current, gold, worth, seenT, bankT, mailT, moneyT }, the richest first
function P.Characters()
    local worth = {}
    for _, h in ipairs((P.Rows())) do
        for name, c in pairs(h.chars or {}) do
            worth[name] = (worth[name] or 0) + h.price * (c.bags + c.bank + c.mail + (c.post or 0))
        end
    end
    local out = {}
    for guid, c in pairs(FT.db.chars) do
        if c.side == FT.sideKey then
            local inv = FT.db.inv[guid] or {}
            local current = guid == FT.charKey
            local gold = (current and GetMoney() or (type(c.money) == "number" and c.money or 0)) + P.MailGold(guid)
            out[#out + 1] = {
                guid = guid, name = c.name or "?", classFile = c.classFile, current = current,
                gold = gold, worth = worth[c.name or "?"] or 0, seenT = current and time() or c.seenT,
                bankT = inv.bankT, mailT = inv.mailT, moneyT = c.moneyT,
            }
        end
    end
    for _, x in ipairs(out) do x.total = x.gold + x.worth end
    table.sort(out, function(a, b) return a.total > b.total end)
    return out
end

-- when each character was here last: at login and at logout
FT.On("FT_LOGIN", function()
    local c = FT.charKey and FT.db.chars[FT.charKey]
    if c then c.seenT = time() end
end)
FT.On("PLAYER_LOGOUT", function()
    local c = FT.charKey and FT.db.chars[FT.charKey]
    if c then c.seenT = time() end
end)

---------------------------------------------------------------------------
-- Sessions: a farming run (mining, herbs, a dungeon...) - everything you loot, what it's worth now, gold an hour.
-- Counted from the game's own loot lines (yours only: "You receive loot", items pushed into your bags, gold you
-- loot), so mail, auction buys, trades and crafts never get in. Survives a /reload or a relog. AFK pauses it.
---------------------------------------------------------------------------
local Ses = {}
FT.Session = Ses

-- 3725 -> "1 h 2 min"
function FT.Duration(secs)
    secs = math.floor(secs or 0)
    local h, m = math.floor(secs / 3600), math.floor((secs % 3600) / 60)
    if h > 0 then return string.format(L["%d h %d min"], h, m) end
    return string.format(L["%d min"], m)
end
local MAX_SAVED = 50
local RATE_AFTER = 600 -- gold an hour shows from this many seconds into a session

-- the game's loot lines as patterns, from its own strings (any language): %s the item, %d how many
local function Pattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    return "^" .. p .. "$"
end
local lootPatterns
local function LootPatterns()
    if lootPatterns then return lootPatterns end
    lootPatterns = {}
    -- the "x5" ones first: the plain ones would match them too
    for _, key in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF" }) do
        local p = Pattern(_G[key])
        if p then lootPatterns[#lootPatterns + 1] = p end
    end
    if #lootPatterns == 0 then
        lootPatterns = { "^You receive loot: (.+)x(%d+)%.$", "^You receive item: (.+)x(%d+)%.$", "^You receive loot: (.+)%.$", "^You receive item: (.+)%.$" }
    end
    return lootPatterns
end

-- "You receive loot: [Thorium Ore]x3." -> itemID, 3
function Ses.ParseLoot(msg)
    if type(msg) ~= "string" then return nil end
    for _, p in ipairs(LootPatterns()) do
        local link, n = msg:match(p)
        if link then
            local id = FT.ItemIDFromLink(link) or tonumber(link:match("item:(%d+)"))
            if id then return id, tonumber(n) or 1 end
        end
    end
    return nil
end

-- "You loot 1 Gold, 20 Silver, 5 Copper" (and your share of a group's) -> copper
local moneyPatterns
function Ses.ParseMoney(msg)
    if type(msg) ~= "string" then return 0 end
    if not moneyPatterns then
        moneyPatterns = {}
        for key, mult in pairs({ GOLD_AMOUNT = 10000, SILVER_AMOUNT = 100, COPPER_AMOUNT = 1 }) do
            local f = _G[key] or (key == "GOLD_AMOUNT" and "%d Gold") or (key == "SILVER_AMOUNT" and "%d Silver") or "%d Copper"
            moneyPatterns[#moneyPatterns + 1] = { f:gsub("%%d", "(%%d+)"), mult }
        end
    end
    local total = 0
    for _, p in ipairs(moneyPatterns) do
        local n = msg:match(p[1])
        if n then total = total + tonumber(n) * p[2] end
    end
    return total
end

-- what one is worth now: its market price - the same number as its tooltip and the Portfolio (FT.Price, the newest
-- of your scans, the Blizzard API and Auctionator) - else what a vendor pays when the auction house has none;
-- nil: no price anywhere yet (shown as such, never counted as 0 without saying so)
function Ses.UnitValue(itemID)
    local p = FT.Price(itemID)
    if p and p > 0 then return p, "ah" end
    local vendor = FT.VendorSell(itemID)
    if vendor and vendor > 0 then return vendor, "vendor" end
    return nil, nil
end

function Ses.Current() return FT.db.session end
function Ses.Running() local s = FT.db.session return s ~= nil and not s.paused end

local function Zone()
    return (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or "?"
end

-- seconds it has run (pauses left out)
function Ses.Elapsed(s)
    s = s or FT.db.session
    if not s then return 0 end
    return (s.secs or 0) + ((not s.paused and s.since) and (time() - s.since) or 0)
end

-- { worth, perHour, items = { { id, qty, value, via } } (most valuable first), money }
function Ses.Summary(s)
    s = s or FT.db.session
    if not s then return nil end
    local items, worth, unpriced = {}, s.money or 0, 0
    for id, qty in pairs(s.items or {}) do
        local unit, via = Ses.UnitValue(id)
        local v = (unit or 0) * qty
        worth = worth + v
        if not unit then unpriced = unpriced + 1 end
        items[#items + 1] = { id = id, qty = qty, value = v, unit = unit, via = via,
            thenUnit = s.found and s.found[id] and qty > 0 and s.found[id] / qty or nil, last = s.lastLoot == id }
    end
    table.sort(items, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.id < b.id
    end)
    local secs = Ses.Elapsed(s)
    -- gold an hour only from 10 minutes on (a lucky first minute made it look huge), and without the single most
    -- valuable find too (one rare drop shouldn't set your rate)
    local best = items[1] and items[1].value or 0
    local ok = secs >= RATE_AFTER
    return { worth = worth, perHour = ok and worth / secs * 3600 or nil,
        perHourNoBest = ok and #items > 1 and (worth - best) / secs * 3600 or nil, bestItem = items[1],
        items = items, money = s.money or 0, secs = secs, unpriced = unpriced, rateIn = math.max(0, RATE_AFTER - secs) }
end

function Ses.Start()
    if FT.db.session then return end
    FT.db.session = { start = time(), since = time(), secs = 0, items = {}, money = 0, zone = Zone() }
    FT.Print(L["Session started: everything you loot counts. Stop it with a right-click on the minimap button, or /wolf farm."])
    FT.Fire("FT_SESSION_CHANGED")
end

function Ses.Pause(on)
    local s = FT.db.session
    if not s then return end
    if on == nil then on = not s.paused end
    if on and not s.paused then
        s.secs = Ses.Elapsed(s)
        s.since, s.paused = nil, true
    elseif not on and s.paused then
        s.since, s.paused, s.afk = time(), nil, nil
    end
    FT.Fire("FT_SESSION_CHANGED")
end

function Ses.Stop()
    local s = FT.db.session
    if not s then return end
    local sum = Ses.Summary(s)
    s.secs = Ses.Elapsed(s)
    s.stop = time()
    s.worth = math.floor(sum.worth)
    s.name = s.name or string.format("%s, %d min", s.zone or "?", math.floor(s.secs / 60 + 0.5))
    FT.db.sessions = FT.db.sessions or {}
    table.insert(FT.db.sessions, 1, s)
    for i = #FT.db.sessions, MAX_SAVED + 1, -1 do FT.db.sessions[i] = nil end
    FT.db.session = nil
    FT.Print(string.format(L["Session done: %s in %s, %s an hour."], FT.Money(s.worth, "short"),
        FT.Duration and FT.Duration(s.secs) or (math.floor(s.secs / 60) .. " min"),
        sum.perHour and FT.Money(math.floor(sum.perHour), "short") or "?"))
    FT.Fire("FT_SESSION_CHANGED")
end

function Ses.List() return FT.db.sessions or {} end

-- a saved session renamed (empty: its zone and length again), or deleted
function Ses.Rename(s, name)
    name = name and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
    s.name = name ~= "" and name or string.format("%s, %d min", s.zone or "?", math.floor((s.secs or 0) / 60 + 0.5))
    FT.Fire("FT_SESSION_CHANGED")
end
function Ses.Delete(s)
    for i, x in ipairs(FT.db.sessions or {}) do
        if x == s then table.remove(FT.db.sessions, i) break end
    end
    FT.Fire("FT_SESSION_CHANGED")
end

-- your gold an hour over your saved sessions (nil: none of an hour or more in all)
function Ses.UsualPerHour()
    local worth, secs = 0, 0
    for _, s in ipairs(Ses.List()) do worth, secs = worth + (s.worth or 0), secs + (s.secs or 0) end
    return secs >= 3600 and worth / secs * 3600 or nil
end

FT.On("CHAT_MSG_LOOT", function(msg)
    local s = FT.db.session
    if not s or s.paused then return end
    local id, n = Ses.ParseLoot(msg)
    if id then
        s.items[id] = (s.items[id] or 0) + n
        -- what it was worth when found (the session's page shows then against now)
        s.found = s.found or {}
        s.found[id] = (s.found[id] or 0) + math.floor((Ses.UnitValue(id) or 0) * n)
        s.lastLoot, s.lastN, s.lastT = id, n, time()
        FT.Fire("FT_SESSION_LOOT", id, n)
    end
end)
FT.On("CHAT_MSG_MONEY", function(msg)
    local s = FT.db.session
    if not s or s.paused then return end
    local c = Ses.ParseMoney(msg)
    if c > 0 then
        s.money = (s.money or 0) + c
        FT.Fire("FT_SESSION_LOOT")
    end
end)
-- away from the keyboard: paused, and on again when you're back (only if AFK paused it)
FT.On("PLAYER_FLAGS_CHANGED", function(unit)
    if unit ~= "player" or not FT.db.session then return end
    local afk = UnitIsAFK and UnitIsAFK("player")
    local s = FT.db.session
    if afk and not s.paused then
        Ses.Pause(true)
        s.afk = true
    elseif not afk and s.paused and s.afk then
        Ses.Pause(false)
    end
end)
-- logged out mid-session: the time away doesn't count
FT.On("PLAYER_LOGOUT", function()
    local s = FT.db.session
    if s and not s.paused then
        s.secs = Ses.Elapsed(s)
        s.since = nil
        s.resume = true
    end
end)
FT.On("FT_READY", function()
    local s = FT.db.session
    if s and s.resume then
        s.since, s.resume = time(), nil
        FT.Print(L["Your session goes on (the time logged out doesn't count)."])
        FT.Fire("FT_SESSION_CHANGED")
    end
end)

---------------------------------------------------------------------------
-- The market recap at login (one line, like a stock app's morning summary) and sell-day pings: something you own
-- on a good day to sell - once a day each, a few at most, in one line
---------------------------------------------------------------------------
local loginAt
FT.On("FT_READY", function() loginAt = time() end)

local function BestMove()
    local best
    for _, d in ipairs(FT.Deals.List() or {}) do
        if not best or (d.profit or 0) > (best.profit or 0) then best = d end
    end
    if not best then return nil end
    local H = FT.House
    local what = FT.ItemText(best.id)
    local how = (best.kind == "HOUSES" and string.format(L["carry %s to %s"], what, H.Name(best.sellHouse)))
        or (best.kind == "VENDOR" and string.format(L["vendor %s"], what)) or string.format(L["flip %s"], what)
    return how .. " " .. FT.C("up", "(+" .. FT.Money(math.floor(best.profit), "short") .. ")")
end

function P.Recap()
    local rows, total = P.Rows()
    local worth = (total or 0) + P.Gold()
    local r = FT.db.recap or {}
    FT.db.recap = r
    local bits = { string.format(L["Portfolio %s"], FT.Money(math.floor(worth), "short")) }
    if r.worth and r.worth > 0 then
        bits[1] = bits[1] .. " " .. FT.Pct(worth / r.worth - 1) .. FT.C("dim", " " .. L["since last time"])
    end
    local toSell = 0
    for _, h in ipairs(rows) do if h.signal == "SELL" or h.signal == "TRIM" then toSell = toSell + 1 end end
    if toSell > 0 then bits[#bits + 1] = string.format(L["%d worth selling (Portfolio > Sell yours)"], toSell) end
    local move = BestMove()
    if move then bits[#bits + 1] = L["best move"] .. ": " .. move end
    local right, n = FT.An.Scorecard()
    if n >= 10 then bits[#bits + 1] = FT.C("dim", string.format(L["its calls: %d%% right"], math.floor(right / n * 100 + 0.5))) end
    FT.Print(FT.C("accent", L["Market recap"]) .. "  " .. table.concat(bits, FT.C("dim", "  ·  ")))
    r.worth, r.t = worth, time()
end

-- (v0.25: the Eye says this at login, with your moves - P.Recap stays for /wolf recap)

function P.SellPings()
    if FT.S.sellPing == false then return end
    if loginAt and time() - loginAt < 90 then return end -- the recap just said it
    local today = FT.Day()
    local pinged = FT.db.pinged
    if not pinged or pinged.day ~= today then pinged = { day = today }; FT.db.pinged = pinged end
    local lines = {}
    for _, h in ipairs((P.Rows())) do
        if #lines >= 3 then break end
        if not pinged[h.id] and (h.signal == "SELL" or h.signal == "TRIM") and (h.strength or 0) >= 2 then
            local s = FT.An.Stats(h.id)
            pinged[h.id] = true
            local _, _, _, _, link = FT.Item(h.id)
            lines[#lines + 1] = (link or FT.ItemText(h.id)) .. " x" .. FT.Num(h.qty)
                .. (s.dev and (" " .. FT.Pct(s.dev)) or "")
        end
    end
    if #lines > 0 then
        FT.Print(FT.C("up", L["Good day to sell"]) .. "  " .. table.concat(lines, FT.C("dim", "  ·  ")))
    end
end
-- (v0.25: what to sell is the Eye's, once it knows enough - FT.Eye)

---------------------------------------------------------------------------
-- Auctionator shopping lists: a list of ours (deals to buy, a craft's materials) as one of Auctionator's, so
-- buying is a click away in its Shopping tab (Auctionator.API.v1; without it: the names in chat)
---------------------------------------------------------------------------
function FT.ToAuctionator(listName, ids)
    local names, seen = {}, {}
    for _, id in ipairs(ids or {}) do
        local name = FT.Item(id)
        if name and not seen[name] then seen[name] = true; names[#names + 1] = name end
    end
    if #names == 0 then
        FT.Print(L["Nothing to put in a list yet."])
        return false
    end
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    local caller = "WolfOfBootyBay"
    if api and api.CreateShoppingList then
        local terms = {}
        for _, name in ipairs(names) do
            local ok, term = false, nil
            if api.ConvertToSearchString then ok, term = pcall(api.ConvertToSearchString, caller, { searchString = name, isExact = true }) end
            terms[#terms + 1] = (ok and type(term) == "string") and term or ('"' .. name .. '"')
        end
        if api.DeleteShoppingList then pcall(api.DeleteShoppingList, caller, listName) end
        local ok = pcall(api.CreateShoppingList, caller, listName, terms)
        if ok then
            FT.Print(string.format(L["Auctionator shopping list \"%s\": %d items. Open Auctionator's Shopping tab at the auction house."], listName, #names))
            return true
        end
    end
    FT.Print(string.format(L["Search these in Auctionator: %s"], table.concat(names, ", ")))
    return false
end
