-- Wolf of Booty Bay: which auction house. Your faction's (Alliance or Horde) and Blackwater - the neutral one, shared by
-- both factions - have lots and prices of their own: each keeps its own history, order books, sales, deals, your
-- auctions there and its cut. Two things are told apart:
--  * the house you stand at (FT.atHouse, while FT.ahHere): talking to an auctioneer tells it (an auctioneer of
--    neither faction: the neutral one); a wrong guess is put right with the pencil on the chip in the header -
--    remembered for that auctioneer and the other auctioneers of that place;
--  * the house whose prices you see (FT.house, FT.houseKey: the data read and written) - the chip switches it,
--    anywhere. Standing at one house and looking at the other's prices, Wolf of Booty Bay is offline here (FT.ahOpen
--    false: nothing is read from this auction house, nothing bought or posted) until you switch back.
-- The Black Market is another window: not counted here.
-- Auctionator and Mastercraft know one house per faction: their prices count for your faction's house only, and
-- Mastercraft's scans made while you were at Blackwater are left out (told by their time).
-- What is yours whichever the house (the deals journal, the craft queue, Wolf of Booty Bay users met) is kept per server
-- and side (FT.Side).
local ADDON, FT = ...
local L = FT.L

local Ho = {}
FT.House = Ho

local KEEP_VISITS = 60 * 86400
local MAX_VISITS = 300
local neutralSince -- at Blackwater now: since when
local npcID        -- the auctioneer talked to (a correction is remembered for it)
local mapID        -- and where (for the other auctioneers there)

-- the neutral house's letters are signed with its name (the faction's: with the faction's name)
local NEUTRAL_SENDERS = { "Blackwater", "Черновод" }

function Ho.IsNeutral()
    return FT.house == "neutral"
end

-- the house's name: your faction's (in the game's language), or Blackwater
function Ho.Name(house)
    house = house or FT.house
    if house == "neutral" then return L["Blackwater"] end
    local _, name = UnitFactionGroup("player")
    return name or L["Your faction"]
end

-- "Alliance" / "Horde" / "Neutral": the colour of the chip
function Ho.Faction(house)
    house = house or FT.house
    if house == "neutral" then return "Neutral" end
    return UnitFactionGroup("player") or "Neutral"
end

-- the house of an auction house letter, by its sender (nil: not told)
function Ho.OfSender(sender)
    if type(sender) ~= "string" or sender == "" then return nil end
    for _, word in ipairs(NEUTRAL_SENDERS) do
        if sender:find(word, 1, true) then return "neutral" end
    end
    return "faction"
end

---------------------------------------------------------------------------
-- Visits to Blackwater (Mastercraft's scans made then were of its lots)
---------------------------------------------------------------------------
local function Visits()
    FT.db.neutralVisits = FT.db.neutralVisits or {}
    return FT.db.neutralVisits
end

local function BeginVisit()
    neutralSince = neutralSince or time()
end

local function EndVisit()
    if not neutralSince then return end
    local v = Visits()
    v[#v + 1] = { neutralSince, time() }
    neutralSince = nil
    local cutoff = time() - KEEP_VISITS
    while v[1] and (v[1][2] < cutoff or #v > MAX_VISITS) do table.remove(v, 1) end
end

-- were we at Blackwater at `t`?
function Ho.WasNeutral(t)
    if type(t) ~= "number" or not FT.db then return false end
    if neutralSince and t >= neutralSince - 60 then return true end
    for _, v in ipairs(Visits()) do
        if t >= v[1] - 60 and t <= v[2] + 60 then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Switching
---------------------------------------------------------------------------
local function Busy()
    return FT.scanning or FT.atrScanning or (FT.Scanner and FT.Scanner.mode ~= nil)
end

local function Other(house)
    return (house == "neutral") and "faction" or "neutral"
end

-- the auction house you stand at is the one whose prices are on: Wolf of Booty Bay is online there
function Ho.Online()
    return FT.ahHere == true and FT.atHouse == FT.house
end

-- why nothing can be done at the auction house now: standing at it with the other house's prices on says so;
-- else `text` (talk to an auctioneer...)
function Ho.Why(text)
    if FT.ahHere and not FT.ahOpen and FT.atHouse ~= FT.house then
        return string.format(L["You stand at %s, which isn't tracked: Wolf of Booty Bay follows your faction's auction house."],
            Ho.Name(FT.atHouse))
    end
    return text
end

-- online or offline at the auction house you stand at, as the houses are now (away from it: nothing to do)
local opening = false -- the auction house is opening: the scanner goes online itself, a moment later
local function Sync()
    if FT.ahHere and not opening and FT.Scanner and FT.Scanner.SetOnline then FT.Scanner.SetOnline(Ho.Online()) end
end

-- whose data is read and written from now on; told in chat when `say`. False when it can't now (a scan runs) -
-- unless `force` (an auctioneer just talked to: nothing can be scanning yet, whatever a flag left from before says)
function Ho.Set(house, say, force)
    -- one house's prices only: your faction's (Blackwater isn't followed since v0.28)
    house = "faction"
    if house == FT.house then return true end
    if not force and Busy() then
        FT.Print(L["Not while scanning: the prices being read belong to the auction house they come from."])
        return false
    end
    -- nothing more is read from the auction house here into the prices being left
    if FT.ahOpen and FT.Scanner and FT.Scanner.SetOnline then FT.Scanner.SetOnline(false) end
    FT.house = house
    FT.houseKey = FT.HouseKey(house)
    local c = FT.charKey and FT.db.chars[FT.charKey]
    if c then c.house = (house == "neutral") and "neutral" or nil end
    FT.Debug("house:", house, FT.houseKey, "at", tostring(FT.atHouse))
    FT.Fire("FT_HOUSE_CHANGED", house)
    Sync()
    if say then
        if house == "neutral" then
            FT.Print(L["Blackwater auction house: its prices, history and your auctions there are kept apart from your faction's."])
        else
            FT.Print(string.format(L["Auction house: %s."], Ho.Name(house)))
        end
    end
    return true
end

-- An item window of its own house: fn runs with that house's data on (and offline - nothing of it is live or
-- bought there), then everything is as it was. The modules keep their caches per house (FT_HOUSE_USE).
local function Pack(...) return { n = select("#", ...), ... } end
function Ho.With(house, fn, ...)
    if not house or house == FT.house then return fn(...) end
    local keepHouse, keepKey, keepOpen = FT.house, FT.houseKey, FT.ahOpen
    FT.house, FT.houseKey, FT.ahOpen = house, FT.HouseKey(house), false
    FT.Fire("FT_HOUSE_USE")
    local res = Pack(pcall(fn, ...))
    FT.house, FT.houseKey, FT.ahOpen = keepHouse, keepKey, keepOpen
    FT.Fire("FT_HOUSE_USE")
    if not res[1] then
        geterrorhandler()(res[2])
        return nil
    end
    return unpack(res, 2, res.n)
end

local function MapHere()
    return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
end

local function Known(book, key)
    local v = key and FT.db[book] and FT.db[book][key]
    return (v == "faction" or v == "neutral") and v or nil
end

-- the auctioneer talked to: its house (a correction remembered for it or for its place, else by its faction:
-- none - the neutral house), nil when it can't be told; and the auctioneer
local function Detect()
    local known = Known("houseByMap", mapID)
    local unit
    for _, u in ipairs({ "npc", "target" }) do
        if UnitExists(u) and not UnitIsPlayer(u) then
            unit = u
            break
        end
    end
    if not unit then return known, nil end
    local guid = UnitGUID(unit)
    local kind, id
    if type(guid) == "string" then
        local parts = { strsplit("-", guid) }
        kind, id = parts[1], tonumber(parts[6])
    end
    if kind ~= "Creature" then id = nil end
    known = Known("houseByNpc", id) or known
    if known then return known, id end
    local group = UnitFactionGroup(unit)
    return (group == "Alliance" or group == "Horde") and "faction" or "neutral", id
end

-- the chip in the header: whose prices you see (at an auctioneer too: the other house is offline here)
function Ho.Toggle()
    -- nothing to switch to: your faction's house is the only one followed
    FT.Print(L["Wolf of Booty Bay follows your faction's auction house. Blackwater, the neutral one, isn't tracked: its prices come too late to act on."])
end

-- the pencil on the chip, at an auctioneer: this auction house is the other one (asked first; remembered for the
-- auctioneers here); its prices are on from now on
function Ho.Fix()
    if not FT.ahHere then return end
    local to = Other(FT.atHouse)
    FT.UI.Confirm({
        owner = "houseFix",
        title = string.format(L["This is %s?"], Ho.Name(to)),
        text = string.format(L["The prices seen at this auctioneer go to %s from now on, and Wolf of Booty Bay remembers it for the auctioneers here."], Ho.Name(to)),
        ok = Ho.Name(to),
        cancel = L["Cancel"],
        onOK = function()
            if not FT.ahHere then return end
            if Busy() then
                FT.Print(L["Not while scanning: the prices being read belong to the auction house they come from."])
                return
            end
            -- your auctions read here a moment ago were kept under the wrong house
            if FT.Owned and FT.Owned.Misfiled then FT.Owned.Misfiled(FT.atHouse) end
            if FT.Scanner and FT.Scanner.SetOnline then FT.Scanner.SetOnline(false) end
            FT.atHouse = to
            if to == "neutral" then BeginVisit() else EndVisit() end
            if npcID then
                FT.db.houseByNpc = FT.db.houseByNpc or {}
                FT.db.houseByNpc[npcID] = to
            end
            if mapID then
                FT.db.houseByMap = FT.db.houseByMap or {}
                FT.db.houseByMap[mapID] = to
            end
            Ho.Set(to, true)
            Sync()
            FT.Fire("FT_AH_CHANGED")
        end,
    })
end

-- before anything else reads the auction house (this file is read before the scanner and the others): the house
-- you stand at, and its prices on
FT.On("AUCTION_HOUSE_SHOW", function()
    if not FT.db then return end
    mapID = MapHere()
    local house, id = Detect()
    npcID = id
    if not house then
        FT.Debug("house: the auctioneer can't be told - your faction's house")
        house = "faction"
    end
    FT.ahHere, FT.atHouse = true, house
    if house == "neutral" then
        BeginVisit()
        -- offline here (its prices aren't ours): said once a session
        if not Ho.toldNeutral then
            Ho.toldNeutral = true
            FT.Print(L["Blackwater, the neutral auction house, isn't tracked: Wolf of Booty Bay stays offline here and follows your faction's."])
        end
    end
    opening = true
    Ho.Set(house, true, true)
    opening = false
end)

FT.On("AUCTION_HOUSE_CLOSED", function()
    EndVisit()
    FT.ahHere, FT.atHouse = false, nil
    npcID, mapID = nil, nil
end)
