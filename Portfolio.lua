-- Wolf of Booty Bay: what your characters own (bags, bank, mail) and what it is worth at market prices.
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
            c = { bags = 0, bank = 0, mail = 0 }
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
    holdings = out
    return out
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
            worth[name] = (worth[name] or 0) + h.price * (c.bags + c.bank + c.mail)
        end
    end
    local out = {}
    for guid, c in pairs(FT.db.chars) do
        if c.side == FT.sideKey then
            local inv = FT.db.inv[guid] or {}
            local current = guid == FT.charKey
            local gold = current and GetMoney() or (type(c.money) == "number" and c.money or 0)
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

-- what one is worth now: the auction house after its cut, else what a vendor pays; and where from
function Ses.UnitValue(itemID)
    local p = FT.Price(itemID)
    local ah = p and p * (1 - FT.Cut()) or nil
    local vendor = FT.VendorSell(itemID)
    if ah and (not vendor or ah >= vendor) then return ah, "ah" end
    if vendor and vendor > 0 then return vendor, "vendor" end
    return 0, nil
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
    local items, worth = {}, s.money or 0
    for id, qty in pairs(s.items or {}) do
        local unit, via = Ses.UnitValue(id)
        local v = unit * qty
        worth = worth + v
        items[#items + 1] = { id = id, qty = qty, value = v, via = via }
    end
    table.sort(items, function(a, b) return a.value > b.value end)
    local secs = Ses.Elapsed(s)
    return { worth = worth, perHour = secs >= 60 and worth / secs * 3600 or nil, items = items, money = s.money or 0, secs = secs }
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
        s.found[id] = (s.found[id] or 0) + math.floor(Ses.UnitValue(id) * n)
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

local recapDone = false
FT.On("FT_MARKET_READY", function()
    if recapDone or FT.S.recap == false then return end
    recapDone = true
    -- a moment for the deals and the portfolio to be worked out
    C_Timer.After(12, function() pcall(P.Recap) end)
end)

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
FT.On("FT_MARKET_READY", function() FT.Debounce("sellPing", 30, function() pcall(P.SellPings) end) end)

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
