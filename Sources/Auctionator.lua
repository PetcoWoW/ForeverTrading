-- Wolf of Booty Bay (built on ForeverTrading): Auctionator link (Settings > Sources can turn it off).
-- What Auctionator scans goes into ForeverTrading's own history, as if we had scanned it ourselves:
-- its full scan (every auction: order books, day candles), its searches, and every price it saves.
-- Days ForeverTrading has no candle for are filled from Auctionator's own price database.
local ADDON, FT = ...
local L = FT.L

local A = {}
FT.Atr = A

local CALLER = "WolfOfBootyBay"

function A.Loaded()
    return Auctionator ~= nil and Auctionator.Database ~= nil and type(Auctionator.Database.db) == "table"
end

-- loaded and allowed in Settings
function A.On()
    return FT.S ~= nil and FT.S.useAuctionator ~= false and A.Loaded()
end

-- its price history (one per faction: of your faction's auction house, not Blackwater's)
function A.DB()
    if FT.house == "neutral" then return nil end
    return A.On() and Auctionator.Database.db or nil
end

-- Auctionator's record of an item: { m = last lowest price, h/l = { [day] = highest/lowest low }, a = { [day] = qty } }
function A.Entry(itemID)
    local db = A.DB()
    local e = db and db[tostring(itemID)]
    if type(e) == "table" then return e end
    return nil
end

-- the newest day this item was seen
function A.LastDay(e)
    local newest
    for dk in pairs(e.h or {}) do
        local d = tonumber(dk)
        if d and (not newest or d > newest) then newest = d end
    end
    return newest
end

-- current price (copper), age in days
function A.Current(itemID)
    local e = A.Entry(itemID)
    if not e or type(e.m) ~= "number" or e.m <= 0 then return nil end
    local last = A.LastDay(e)
    return e.m, last and (FT.Day() - last) or nil
end

-- day -> { low, high, qty } from `fromDay` on
function A.Daily(itemID, fromDay)
    local e = A.Entry(itemID)
    if not e or type(e.h) ~= "table" then return nil end
    local out = {}
    for dk, high in pairs(e.h) do
        local d = tonumber(dk)
        if d and (not fromDay or d >= fromDay) and type(high) == "number" then
            local low = e.l and e.l[dk] or high
            out[d] = { low = low, high = high, qty = e.a and e.a[dk] }
        end
    end
    return out
end

-- The days Auctionator scanned the whole market: days on which at least SCAN_DAY_ITEMS items got a price (a
-- search saves a few; a full scan thousands). Worked out at most every 5 minutes, and after each of its scans.
local SCAN_DAY_ITEMS = 150
local scanDays, scanDaysAt
function A.ScanDays()
    local db = A.DB()
    if not db then return {} end
    if scanDays and scanDaysAt and GetTime() - scanDaysAt < 300 then return scanDays end
    local count = {}
    for _, e in pairs(db) do
        if type(e) == "table" and type(e.h) == "table" then
            for dk in pairs(e.h) do
                local d = tonumber(dk)
                if d then count[d] = (count[d] or 0) + 1 end
            end
        end
    end
    scanDays = {}
    for d, n in pairs(count) do
        if n >= SCAN_DAY_ITEMS then scanDays[#scanDays + 1] = d end
    end
    table.sort(scanDays)
    scanDaysAt = GetTime()
    return scanDays
end
FT.On("FT_SCAN_DONE", function(src) if src == "auctionator" then scanDaysAt = nil end end)
FT.On("FT_HOUSE_CHANGED", function() scanDaysAt = nil end)

-- How many days of history Auctionator keeps (its setting)
function A.HistoryDays()
    if not (Auctionator and Auctionator.Config and Auctionator.Config.Get and Auctionator.Config.Options) then return nil end
    local ok, days = pcall(Auctionator.Config.Get, Auctionator.Config.Options.PRICE_HISTORY_DAYS)
    return ok and days or nil
end

-- One scan for both addons: our Scan button starts Auctionator's own scan when it is there, and its results come
-- to us through the hooks below. Auctionator has no public call for this, so its scan frames are tried by name;
-- should none start a scan within 1.5 seconds (an Auctionator version that names them otherwise), `fallback`
-- (our own scan) runs instead. Returns false when Auctionator isn't there at all (run your own scan then).
function A.StartScan(fallback)
    if not (A.On() and FT.ahOpen and FT.S.scanWithAuctionator ~= false) then return false end
    local st = Auctionator.State
    local started = false
    -- the summary scan first (a few seconds, any time), then the full one (every auction, once every 15 minutes)
    for _, key in ipairs({ "IncrementalScanFrameRef", "FullScanFrameRef" }) do
        local ref = type(st) == "table" and st[key]
        if not started and type(ref) == "table" and type(ref.InitiateScan) == "function" then
            started = pcall(ref.InitiateScan, ref)
        end
    end
    if not started then return false end
    C_Timer.After(1.5, function()
        if not FT.atrScanning and not FT.scanning and fallback then
            FT.Debug("Auctionator's scan didn't start: ours instead")
            fallback()
        end
    end)
    return true
end

-- Searches the auction house in Auctionator's Shopping tab (the auction house must be open)
function A.Search(terms)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not (api and api.MultiSearch) then return false end
    local ok = pcall(api.MultiSearch, CALLER, terms)
    return ok
end

---------------------------------------------------------------------------
-- Its scans -> our history
---------------------------------------------------------------------------
-- full scan entries are { replicateInfo = { C_AuctionHouse.GetReplicateItemInfo() }, itemLink } (the classic
-- auction house: auctionInfo), search results { info = {...}, itemLink }
local function Info(entry)
    local info = entry and (entry.replicateInfo or entry.auctionInfo or entry.info)
    if not info then return nil end
    return info[3], info[10], info[14], info[17] or FT.ItemIDFromLink(entry.itemLink)
end

function A.OnFullScan(raw)
    FT.atrScanning = false
    if not (A.On() and FT.ahOpen and type(raw) == "table") then
        FT.Fire("FT_SCAN_DONE", "auctionator")
        return
    end
    local t = time()
    FT.Scanner.ReadList(raw, Info, function(acc)
        FT.Scanner.SaveFull(acc, t, "auctionator", function()
            FT.Print(L["Took Auctionator's full scan: no need to scan again."])
            FT.Fire("FT_SCAN_DONE", "auctionator")
        end)
    end)
end

-- its summary scan (the default "full scan" on the modern auction house): the browse list of every item
function A.OnSummaryScan(results)
    FT.atrScanning = false
    if not (A.On() and FT.ahOpen and type(results) == "table" and #results > 0) then
        FT.Fire("FT_SCAN_DONE", "auctionator")
        return
    end
    local sum = FT.Scanner.NewSummary()
    FT.Scanner.AddBrowse(sum, results)
    FT.Scanner.SaveSummary(sum, time(), "auctionator", function()
        -- Auctionator counts every version of an item (each item level, each "of the Bear"); we count items
        FT.Print(string.format(L["Took Auctionator's scan: %s items (%s with every gear version), no need to scan again."],
            FT.Num(sum.count), FT.Num(#results)))
        FT.Fire("FT_SCAN_DONE", "auctionator")
    end)
end

function A.OnSearchResults(results)
    if not (A.On() and FT.ahOpen and type(results) == "table" and #results > 0) then return end
    local t = time()
    FT.Scanner.ReadList(results, Info, function(acc)
        FT.Scanner.Ingest(acc, t, "auctionator")
    end)
end

---------------------------------------------------------------------------
-- Hooks (installed once; Settings decide whether they do anything)
---------------------------------------------------------------------------
local hooked = false
local listener = {}

function listener:ReceiveEvent(eventName, ...)
    local fs = Auctionator.FullScan and Auctionator.FullScan.Events or {}
    local is = Auctionator.IncrementalScan and Auctionator.IncrementalScan.Events or {}
    if eventName == fs.ScanStart or eventName == is.ScanStart then
        FT.atrScanning = true
        FT.Fire("FT_SCAN_START", "auctionator")
    elseif eventName == fs.ScanComplete then
        A.OnFullScan(...)
    elseif eventName == is.ScanComplete then
        A.OnSummaryScan(...)
    elseif eventName == fs.ScanFailed or eventName == is.ScanFailed then
        FT.atrScanning = false
        FT.Fire("FT_SCAN_FAILED", "auctionator")
    end
end

local function TryHook()
    if hooked then return true end
    if not A.Loaded() then return false end
    hooked = true
    -- a price it saves outside a full scan (its shopping and selling tabs); the full scan itself is read whole
    hooksecurefunc(Auctionator.Database, "SetPrice", function(_, dbKey, price, available)
        if A.On() and FT.ahOpen and not FT.atrScanning then
            FT.Hist.Observe(dbKey, price, available, nil, time(), "auctionator")
        end
    end)
    local bus = Auctionator.EventBus
    if bus and bus.Register then
        local names = {}
        for _, events in ipairs({ Auctionator.FullScan and Auctionator.FullScan.Events,
            Auctionator.IncrementalScan and Auctionator.IncrementalScan.Events }) do
            for _, key in ipairs({ "ScanStart", "ScanComplete", "ScanFailed" }) do
                if type(events) == "table" and events[key] then names[#names + 1] = events[key] end
            end
        end
        if #names > 0 then pcall(bus.Register, bus, listener, names) end
    end
    if Auctionator.Search and type(Auctionator.Search.GroupResultsForDB) == "function" then
        hooksecurefunc(Auctionator.Search, "GroupResultsForDB", function(results) A.OnSearchResults(results) end)
    end
    FT.Debug("Auctionator hooked")
    FT.Fire("FT_SOURCES_CHANGED")
    return true
end
A.TryHook = TryHook

FT.On("FT_READY", function()
    if TryHook() then return end
    local tries = 0
    local ticker
    ticker = C_Timer.NewTicker(1, function()
        tries = tries + 1
        if TryHook() or tries >= 30 then ticker:Cancel() end
    end)
end)

FT.On("AUCTION_HOUSE_SHOW", function() TryHook() end)
FT.On("AUCTION_HOUSE_CLOSED", function() FT.atrScanning = false end)
