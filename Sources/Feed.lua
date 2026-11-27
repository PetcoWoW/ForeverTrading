-- Wolf: the price feed. Every release carries Data/Feed.lua, built hourly outside the game from
-- Blizzard's own auction data for every WoW Forever auction house (tools/feed/build.mjs): the lowest price of each
-- item, how many are listed and in how many auctions, what sold over the last 7 days and the daily lows of the
-- last 30 days (FT.FEED.days). So prices are there before your first scan, and for the house you aren't standing at.
--
-- How it is used:
--  * at login (and when the house you look at changes) the feed's prices go into the history as a scan of the
--    whole market - unless a scan of your own (or one received from another player) is newer;
--  * the days you didn't scan get the feed's daily lows on the charts (History.lua, like Auctionator's days);
--  * "sells ~N a day" uses the feed's 7 days of sales when they cover more hours than what you watched yourself
--    (Sales.lua).
-- Settings > Sources turns it off.
local ADDON, FT = ...
local L = FT.L

local F = {}
FT.Feed = F

-- Blizzard's auction houses by ruleset and side (the same ids in every region)
local HOUSE_IDS = {
    pvp = { Alliance = 110, Horde = 113, Neutral = 116 },
    normal = { Alliance = 111, Horde = 114, Neutral = 117 },
    roleplay = { Alliance = 119, Horde = 120, Neutral = 121 },
    ["roleplay-pvp"] = { Alliance = 123, Horde = 124, Neutral = 125 },
}
-- The realm's ruleset when its name doesn't tell it: by realm id (the id the game gives, modulo 16384)
local REALM_RULESET = {
    -- US and TW
    [366] = "pvp", [369] = "pvp", [372] = "pvp", [623] = "normal", [626] = "normal", [629] = "normal",
    [887] = "roleplay", [888] = "roleplay", [889] = "roleplay",
    [3963] = "roleplay-pvp", [3964] = "roleplay-pvp", [3965] = "roleplay-pvp",
    -- EU and KR
    [8558] = "pvp", [8561] = "pvp", [8564] = "pvp", [8815] = "normal", [8818] = "normal", [8821] = "normal",
    [9079] = "roleplay", [9080] = "roleplay", [9081] = "roleplay",
    [12155] = "roleplay-pvp", [12156] = "roleplay-pvp", [12157] = "roleplay-pvp",
}

local parsed = {} -- house id -> { t, items = { [itemID] = entry } }
local reading = {} -- house id -> a read under way in the background (F.Warm)
local region     -- the feed's data of this client's region

local function Dec(s)
    if s == nil or s == "" then return nil end
    return tonumber(s, 36)
end

function F.Loaded()
    return type(FT.FEED) == "table" and type(FT.FEED.regions) == "table"
end

-- loaded and allowed in Settings
function F.On()
    return F.Loaded() and not (FT.S and FT.S.useFeed == false)
end

local function Region()
    if region ~= nil then return region or nil end
    region = false
    if not F.Loaded() then return nil end
    local id = GetCurrentRegion and GetCurrentRegion()
    region = (id and FT.FEED.regions[id]) or false
    if not region then
        -- the game's region id isn't one the feed knows (WoW Forever may give its own): the only region in the
        -- feed, when it carries one
        local only, count = nil, 0
        for _, r in pairs(FT.FEED.regions) do only, count = r, count + 1 end
        if count == 1 then region = only end
    end
    return region or nil
end

-- "PvP", "us-pvp", "RP-PvP Alliance"... -> a ruleset (nil: no clue in it)
local function KindIn(text)
    if type(text) ~= "string" then return nil end
    local t = text:lower()
    if t:find("rp%-?pvp") or t:find("roleplay%-?pvp") then return "roleplay-pvp" end
    if t:find("pvp") then return "pvp" end
    if t:find("%f[%a]rp%f[%A]") or t:find("roleplay") then return "roleplay" end
    if t:find("normal") or t:find("pve") then return "normal" end
    return nil
end

-- this realm's ruleset: "pvp", "normal", "roleplay" or "roleplay-pvp" (nil: not told), and how it was told.
-- In order: your choice (Settings > Basics > Realm type), the realm's name, its id, Auctionator's name for its
-- price list ("PvP Alliance"), and last: the one ruleset the feed carries a house of your side for.
function F.Ruleset()
    local pick = FT.S and FT.S.realmType
    if pick and pick ~= "auto" and HOUSE_IDS[pick] then return pick, "setting" end
    local name = GetRealmName and GetRealmName() or ""
    local server = FT.ServerOf(name)
    local kind = server and server:match("^%a%a%-(.+)$")
    if kind and HOUSE_IDS[kind] then return kind, "name" end
    local id = GetRealmID and GetRealmID()
    if not id then
        local guid = UnitGUID and UnitGUID("player")
        id = guid and tonumber(guid:match("^Player%-(%d+)"))
    end
    if id and REALM_RULESET[id % 16384] then return REALM_RULESET[id % 16384], "id" end
    kind = KindIn(name)
    if kind then return kind, "name" end
    if type(AUCTIONATOR_PRICE_DATABASE) == "table" then
        local side = UnitFactionGroup and UnitFactionGroup("player") or ""
        for key in pairs(AUCTIONATOR_PRICE_DATABASE) do
            if type(key) == "string" and key:find(side, 1, true) then
                kind = KindIn(key)
                if kind then return kind, "auctionator" end
            end
        end
    end
    -- the feed carries one house of your side: that one
    local r = Region()
    if r and r.houses then
        local side = UnitFactionGroup and UnitFactionGroup("player") or ""
        local found
        for rs, ids in pairs(HOUSE_IDS) do
            if r.houses[ids[side]] then
                if found then found = nil; break end
                found = rs
            end
        end
        if found then return found, "only" end
    end
    return nil, nil
end
F.HOUSE_IDS = HOUSE_IDS

-- why the feed isn't on, in a sentence (nil: it is)
function F.WhyOff()
    if not F.Loaded() then return L["This copy has no Blizzard prices in it: update the addon, or get the prices companion (Settings > About)."] end
    if FT.S and FT.S.useFeed == false then return L["Turned off: Settings > Show all settings > Sources."] end
    if not Region() then return L["The prices in this copy are for another region."] end
    if not F.Ruleset() then
        return string.format(L["Couldn't tell your realm type (realm \"%s\", id %s). Pick it: Settings > Basics > Realm type."],
            GetRealmName and GetRealmName() or "?", tostring(GetRealmID and GetRealmID() or "?"))
    end
    if not F.House() then return L["No Blizzard prices for your auction house in this copy."] end
    return nil
end

-- Blizzard's id of one of our two auction houses ("faction" or "neutral")
function F.HouseID(house)
    local rs = F.Ruleset()
    local ids = rs and HOUSE_IDS[rs]
    if not ids then return nil end
    if house == "neutral" then return ids.Neutral end
    return ids[UnitFactionGroup and UnitFactionGroup("player") or ""]
end

-- "7911=p,q,n,sold,value,hours,expired,low0,...,low29;" - read lazily: one quick pass keeps each item's text
-- (h.raw), an item is decoded the first time it's asked for (h.items[id]) and forgotten again when nothing holds
-- it; its daily lows only when they're asked for (F.Daily). Decoding all 7,000+ items at once took ~100 ms in one
-- frame (a stutter at login) and ~4 MB.
local function Decode(rest)
    local p, q, n, sold, value, hours, expired, lows = rest:match("^([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),?(.*)$")
    if not p then return nil end
    return {
        p = Dec(p), q = Dec(q), n = Dec(n), sold = Dec(sold) or 0, value = Dec(value) or 0, hours = Dec(hours) or 0,
        expired = Dec(expired) or 0, lowsRaw = lows or "",
    }
end
F.Decode = Decode

-- Reading a house's feed: one pass over its text keeps each item's part (h.raw). That pass is ~15 ms for 7,000+
-- items - done in the background a little each frame right after login (Warm), so nothing waits for it in one
-- frame; whatever asks before it's done finishes the rest at once.
local FIELDS = { "data", "sold", "hourly" }
local function NewRead(h)
    return { h = h, field = 1, pos = 1, n = 0, raw = {}, sold = {}, hourly = {} }
end

-- read on until done (true) or the clock passes stopAt (false)
local function ReadOn(st, stopAt)
    local clock = FT.Clock
    while st.field <= #FIELDS do
        local key = FIELDS[st.field]
        local text = st.h[key]
        local into = key == "data" and st.raw or st[key]
        if type(text) == "string" then
            local pos, k = st.pos, 0
            while true do
                local _, b, id, rest = text:find("(%d+)=([^;]*);", pos)
                if not b then break end
                into[tonumber(id)] = rest
                if key == "data" then st.n = st.n + 1 end
                pos = b + 1
                k = k + 1
                if stopAt and k % 250 == 0 and clock() >= stopAt then
                    st.pos = pos
                    return false
                end
            end
        end
        st.field, st.pos = st.field + 1, 1
    end
    return true
end

local function Finish(st)
    local h, raw = st.h, st.raw
    local items = setmetatable({}, {
        __mode = "v",
        __index = function(t, id)
            local rest = raw[id]
            if not rest then return nil end
            local e = Decode(rest)
            rawset(t, id, e)
            return e
        end,
    })
    -- the UTC days the house was really downloaded on (older feeds don't say: none counted)
    local seen = {}
    for d in (type(h.seen) == "string" and h.seen or ""):gmatch("(%d+)") do seen[#seen + 1] = tonumber(d) end
    -- what sold each day (the Radar) and hour by hour (the item page's timeline): kept as text, an item read
    -- when asked for (F.SoldDays, F.Hourly)
    return { t = h.t, firstDay = h.firstDay, items = items, raw = raw, count = st.n, seen = seen,
        soldRaw = st.sold, soldFirst = h.soldFirst, hourRaw = st.hourly, hourFirst = h.hourFirst }
end

local function Parse(h, st)
    st = st or NewRead(h)
    ReadOn(st)
    return Finish(st)
end
F.Parse = Parse

-- your clock against UTC, in whole hours (Pacific: -8)
function F.UTCOffsetHours()
    local now = time()
    return math.floor((now - time(date("!*t", now))) / 3600 + 0.5)
end

-- An item's sales hour by hour: { hours = { { t = start of the hour (unix), n = sold or nil when not watched }
-- x48, oldest first }, tod = { [0..23] = sold an hour at that hour of YOUR day, nil: not watched enough } };
-- nil when the feed has none (older feeds, too few sales)
function F.Hourly(itemID, house)
    local h = F.House(house)
    local rest = h and h.hourRaw and h.hourRaw[itemID]
    if not (rest and h.hourFirst) then return nil end
    local last, tod = rest:match("^([^/]*)/(.*)$")
    if not last then return nil end
    local out = { hours = {}, tod = {} }
    local k = 0
    for v in (last .. ","):gmatch("([^,]*),") do
        out.hours[#out.hours + 1] = { t = (h.hourFirst + k) * 3600, n = Dec(v) }
        k = k + 1
    end
    local off = F.UTCOffsetHours()
    local u = 0
    for v in (tod .. ","):gmatch("([^,]*),") do
        local x = Dec(v)
        if u <= 23 then out.tod[(u + off) % 24] = x and x / 10 or nil end
        u = u + 1
    end
    return out
end

-- An item's sales day by day, as a day's worth each (the robot's watched hours scaled to 24): { [utcDay] = n }
-- for the last two weeks, days watched too little left out; nil when the feed has none (older feeds, no sales)
function F.SoldDays(itemID, house)
    local h = F.House(house)
    local rest = h and h.soldRaw and h.soldRaw[itemID]
    if not (rest and h.soldFirst) then return nil end
    local out, k = {}, 0
    for v in (rest .. ","):gmatch("([^,]*),") do
        local x = Dec(v)
        if x then out[h.soldFirst + k] = x / 10 end
        k = k + 1
    end
    return out
end

-- the feed's data of one of our auction houses (default: the one you look at)
function F.House(house)
    if not F.On() then return nil end
    local r = Region()
    local hid = F.HouseID(house or FT.house)
    if not (r and hid) then return nil end
    local p = parsed[hid]
    if p == nil then
        local h = r.houses and r.houses[hid]
        local st = reading[hid]
        if st and st.h ~= h then st = nil end
        reading[hid] = nil
        p = (type(h) == "table" and type(h.data) == "string") and Parse(h, st) or false
        parsed[hid] = p
    end
    return p or nil
end

-- the houses you'll look at, read in the background (a few ms a frame) before anything asks
function F.Warm()
    if not F.On() then return end
    local r = Region()
    if not r then return end
    for _, side in ipairs({ FT.house, "neutral" }) do
        local hid = F.HouseID(side)
        local h = hid and r.houses and r.houses[hid]
        if hid and parsed[hid] == nil and not reading[hid] and type(h) == "table" and type(h.data) == "string" then
            local st = NewRead(h)
            reading[hid] = st
            local ticker
            local spent, frames, worst, began = 0, 0, 0, GetTime()
            ticker = C_Timer.NewTicker(0, function()
                -- asked for meanwhile (F.House finished it), or the sources changed: nothing left to do
                if reading[hid] ~= st then ticker:Cancel() return end
                local t0 = FT.Clock()
                local done = ReadOn(st, t0 + 3)
                if done then
                    ticker:Cancel()
                    reading[hid] = nil
                    if parsed[hid] == nil then parsed[hid] = Finish(st) end
                end
                local d = FT.Clock() - t0
                spent, frames, worst = spent + d, frames + 1, math.max(worst, d)
                if done then FT.PerfNote("feed:warm", st.n, spent, frames, worst, GetTime() - began) end
            end)
        end
    end
end

-- when the feed's prices of a house were taken (nil: no feed for it)
function F.Time(house)
    local h = F.House(house)
    return h and h.t or nil
end

-- the feed's daily lows of an item from `fromDay` on (our days, FT.Day): day -> { low }
function F.Daily(itemID, fromDay, house)
    local h = F.House(house)
    local e = h and h.items[itemID]
    if not e then return nil end
    local out, any, k = {}, false, 0
    for v in (e.lowsRaw .. ","):gmatch("([^,]*),") do
        k = k + 1
        local low = Dec(v)
        if low then
            -- the feed's days are UTC days: each counts for the day its middle falls on here
            local d = FT.Day((h.firstDay + k - 1) * 86400 + 43200)
            if not fromDay or d >= fromDay then
                out[d] = { low = low }
                any = true
            end
        end
    end
    return any and out or nil
end

-- the days the feed really saw the whole market (our days), for "how long it has been watched"
function F.Days(house)
    local h = F.House(house)
    if not h then return nil end
    local out = {}
    for _, d in ipairs(h.seen) do out[#out + 1] = FT.Day(d * 86400 + 43200) end
    return out
end

-- What sold over the feed's 7 days, in the shape FT.Sales.Rate gives (nil: watched under an hour)
function F.Rate(itemID, house)
    local h = F.House(house)
    local e = h and h.items[itemID]
    if not e or (e.hours or 0) < 1 then return nil end
    return {
        perDay = e.sold / (e.hours / 24), sold = e.sold, avgPrice = e.sold > 0 and e.value / e.sold or nil,
        hours = e.hours, relisted = 0, expired = e.expired, added = 0, feed = true,
    }
end

---------------------------------------------------------------------------
-- Into the history: the feed as a scan of the whole market
---------------------------------------------------------------------------
local taking = false

function F.Take()
    if taking or not F.On() then return end
    if FT.Scanner and FT.Scanner.mode then return end -- a scan of our own is running: it wins anyway
    local h = F.House()
    if not (h and h.t and h.count > 0) then return end
    local own = FT.Hist.MarketTime()
    if own and own >= h.t then return end           -- our own (or a received) scan is newer
    if FT.Hist.HasScan(h.t) then return end         -- taken before
    taking = true
    local sum = FT.Scanner.NewSummary()
    local ids = {}
    for id in pairs(h.raw) do ids[#ids + 1] = id end
    -- a little each frame (only the price and how many are listed are read)
    FT.Job("feed:read", #ids, function(k)
        local id = ids[k]
        local p, q = h.raw[id]:match("^([^,]*),([^,]*),")
        p, q = Dec(p), Dec(q)
        if p and p > 0 and q and q > 0 then
            sum.items[id] = { p = p, q = q }
            sum.count = sum.count + 1
        end
    end, function()
        FT.Scanner.SaveSummary(sum, h.t, "feed", function(items)
            taking = false
            FT.Debug("feed: taken", items, "items of", FT.Ago(h.t))
            FT.Fire("FT_SCAN_DONE", "feed")
        end)
    end)
end

FT.On("FT_READY", function() C_Timer.After(2, F.Take) end)
FT.On("FT_HOUSE_CHANGED", function() C_Timer.After(0.5, F.Take) end)
FT.On("FT_SOURCES_CHANGED", function() wipe(parsed); wipe(reading); region = nil end)
FT.On("FT_SETTINGS_CHANGED", function() wipe(parsed); wipe(reading); region = nil end)
FT.On("FT_READY", function() F.Warm() end)
-- not on: said once a login, with what to do
FT.On("FT_READY", function()
    C_Timer.After(6, function()
        local why = F.WhyOff()
        if why and F.Loaded() and not (FT.S and FT.S.useFeed == false) then
            FT.Print(FT.C("accent", L["Blizzard's prices aren't loading"]) .. ": " .. why)
        end
    end)
end)

---------------------------------------------------------------------------
-- What the login or /reload brought: new prices, or the same ones
---------------------------------------------------------------------------
-- The game reads the price file only at login or /reload, and the addon can't see the disk in between: it can't
-- know when newer prices have been downloaded (by the companion app or an addon update), so it doesn't guess. It says, once
-- after loading, whether these are newer than the ones it had last time - and remembers them (the saved data is
-- written at every reload: the companion app reads it to tell what the game has).
local OLD = 2 * 3600

-- the prices are over two hours old (Blizzard's own time): shown in yellow
function F.Stale()
    local t = F.On() and F.Time()
    return t ~= nil and time() - t > OLD
end

local function Report()
    if not F.On() or not FT.db then return end
    local h = F.House()
    if not h or not h.t then return end
    local key = tostring(F.HouseID(FT.house) or "?")
    local seen = FT.db.feedLoaded
    if type(seen) ~= "table" then seen = {}; FT.db.feedLoaded = seen end
    local last = tonumber(seen[key])
    seen[key] = h.t
    FT.db.feedBuilt = FT.FEED.built
    if last and h.t > last then
        FT.Print(string.format(L["New prices loaded: Blizzard, %s (%s items)."], FT.TimeOfDay(h.t), FT.Num(h.count)))
    elseif last and h.t == last and time() - h.t > 75 * 60 then
        -- only when newer ones could exist: a reload for anything else says nothing
        FT.Print(FT.C("dim", string.format(L["Same prices as last time (%s): nothing newer had downloaded yet."], FT.TimeOfDay(h.t))))
    end
end

FT.On("FT_READY", function() C_Timer.After(4, Report) end)

-- for the status bar and /wolf debug
function F.Describe()
    if not F.Loaded() then return L["no price feed in this version"] end
    local r = Region()
    if not r then return L["the price feed has no prices for your region"] end
    local hid = F.HouseID(FT.house)
    if not hid then return L["the price feed doesn't know your realm's auction house"] end
    local h = F.House()
    if not h then return L["the price feed has no prices for this auction house"] end
    return string.format(L["price feed: %s items, %s"], FT.Num(h.count), FT.Ago(h.t))
end
