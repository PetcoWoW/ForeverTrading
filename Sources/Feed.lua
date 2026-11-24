-- Wolf of Booty Bay: the price feed. Every release carries Data/Feed.lua, built hourly outside the game from
-- Blizzard's own auction data for every WoW Forever auction house (tools/feed/build.mjs): the lowest price of each
-- item, how many are listed and in how many auctions, what sold over the last 7 days and the daily lows of the
-- last 14 days (FT.FEED.days). So prices are there before your first scan, and for the house you aren't standing at.
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
        -- no region from the game: the only one in the feed, if it carries one
        local only, count = nil, 0
        for _, r in pairs(FT.FEED.regions) do only, count = r, count + 1 end
        if count == 1 and not id then region = only end
    end
    return region or nil
end

-- this realm's ruleset: "pvp", "normal", "roleplay" or "roleplay-pvp" (nil: not told)
function F.Ruleset()
    local server = FT.ServerOf(GetRealmName and GetRealmName() or "")
    local kind = server and server:match("^%a%a%-(.+)$")
    if kind and HOUSE_IDS[kind] then return kind end
    local id = GetRealmID and GetRealmID()
    if not id then
        local guid = UnitGUID and UnitGUID("player")
        id = guid and tonumber(guid:match("^Player%-(%d+)"))
    end
    return id and REALM_RULESET[id % 16384] or nil
end

-- Blizzard's id of one of our two auction houses ("faction" or "neutral")
function F.HouseID(house)
    local rs = F.Ruleset()
    local ids = rs and HOUSE_IDS[rs]
    if not ids then return nil end
    if house == "neutral" then return ids.Neutral end
    return ids[UnitFactionGroup and UnitFactionGroup("player") or ""]
end

-- "7911=p,q,n,sold,value,hours,expired,low0,...,low6;" -> entries, read once per house
local function Parse(h)
    local items, n = {}, 0
    for id, rest in h.data:gmatch("(%d+)=([^;]*);") do
        local f, i = {}, 0
        for v in (rest .. ","):gmatch("([^,]*),") do
            i = i + 1
            f[i] = v
        end
        local lows = {}
        for k = 8, i do lows[k - 7] = Dec(f[k]) end
        items[tonumber(id)] = {
            p = Dec(f[1]), q = Dec(f[2]), n = Dec(f[3]),
            sold = Dec(f[4]) or 0, value = Dec(f[5]) or 0, hours = Dec(f[6]) or 0, expired = Dec(f[7]) or 0,
            lows = lows,
        }
        n = n + 1
    end
    return { t = h.t, firstDay = h.firstDay, items = items, count = n }
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
        p = (type(h) == "table" and type(h.data) == "string") and Parse(h) or false
        parsed[hid] = p
    end
    return p or nil
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
    local out, any = {}, false
    for k, low in pairs(e.lows) do
        -- the feed's days are UTC days: each counts for the day its middle falls on here
        local d = FT.Day((h.firstDay + k - 1) * 86400 + 43200)
        if low and (not fromDay or d >= fromDay) then
            out[d] = { low = low }
            any = true
        end
    end
    return any and out or nil
end

-- the days the feed saw the whole market (our days), for "how long it has been watched"
function F.Days(house)
    local h = F.House(house)
    if not h then return nil end
    local out = {}
    local days = FT.FEED.days or 7
    for k = 1, days do
        out[#out + 1] = FT.Day((h.firstDay + k - 1) * 86400 + 43200)
    end
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
    for id, e in pairs(h.items) do
        if e.p and e.p > 0 and e.q and e.q > 0 then
            sum.items[id] = { p = e.p, q = e.q }
            sum.count = sum.count + 1
        end
    end
    FT.Scanner.SaveSummary(sum, h.t, "feed", function(items)
        taking = false
        FT.Debug("feed: taken", items, "items of", FT.Ago(h.t))
        FT.Fire("FT_SCAN_DONE", "feed")
    end)
end

FT.On("FT_READY", function() C_Timer.After(2, F.Take) end)
FT.On("FT_HOUSE_CHANGED", function() C_Timer.After(0.5, F.Take) end)
FT.On("FT_SOURCES_CHANGED", function() wipe(parsed); region = nil end)

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
