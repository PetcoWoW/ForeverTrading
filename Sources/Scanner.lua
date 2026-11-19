-- ForeverTrading: our own auction house scanner (WoW Forever has the modern auction house, C_AuctionHouse).
--  * Full scan: the whole auction house as the game's browse list - the lowest price and how many are listed
--    of every item, in a few seconds, any time. Optionally "deep" (Settings): every single auction
--    (ReplicateItems) - order books of everything - once every 15 minutes.
--  * My items: what your recipes make and use, your watchlist and what you own - one search each, cheapest
--    first: its order book and price.
--  * And everything you look at yourself on the auction house is kept too.
--  * Live: the item you have open (Market, Craft, its own window) is searched again every few seconds.
-- When you (or another addon) search, "my items" and live pause and go on by themselves.
local ADDON, FT = ...
local L = FT.L

local S = {}
FT.Scanner = S

local AH = C_AuctionHouse
local READ_CHUNK = 1500
local SAVE_CHUNK = 300
local ANSWER_TIMEOUT = 3
local LISTED_FRESH = 2 * 3600 -- what a full scan found stays good enough for "my items" this long
local REPLICATE_COOLDOWN = 15 * 60

local frame = CreateFrame("Frame")

local function Modern()
    return AH ~= nil and AH.SendSearchQuery ~= nil and AH.SendBrowseQuery ~= nil
end
S.Supported = Modern

local function Ready()
    return not AH.IsThrottledMessageSystemReady or AH.IsThrottledMessageSystemReady()
end

local function PriceSort()
    local order = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0
    return { { sortOrder = order, reverseSort = false } }
end

---------------------------------------------------------------------------
-- Auctions -> items
---------------------------------------------------------------------------
function S.NewAcc()
    return { items = {}, auctions = 0, value = 0 }
end

-- `count` items at `unit` copper each in `auctions` auctions (several sellers: `owners` = list of names,
-- `ownerCount` = how many the game counts there: its list of names may be shorter)
function S.AddLevel(acc, itemID, unit, count, auctions, owners, ownerCount)
    if not (itemID and itemID > 0 and unit and unit > 0 and count and count > 0) then return end
    unit = math.ceil(unit)
    auctions = auctions or 1
    local it = acc.items[itemID]
    if not it then
        it = { levels = {}, auctions = 0, qty = 0, sellers = {}, sellerCount = 0 }
        acc.items[itemID] = it
    end
    local lv = it.levels[unit]
    if not lv then
        lv = { unit, 0, 0 }
        it.levels[unit] = lv
    end
    lv[2] = lv[2] + count
    lv[3] = lv[3] + auctions
    it.auctions = it.auctions + auctions
    it.qty = it.qty + count
    if type(owners) == "string" then owners = { owners } end
    if type(owners) == "table" then
        for _, owner in ipairs(owners) do
            if type(owner) == "string" and owner ~= "" and not it.sellers[owner] then
                it.sellers[owner] = true
                it.sellerCount = it.sellerCount + 1
            end
        end
    end
    -- a price step with more sellers than its names: at least that many sell the item
    if type(ownerCount) == "number" and ownerCount > it.sellerCount then it.sellerCount = ownerCount end
    acc.auctions = acc.auctions + auctions
    acc.value = acc.value + unit * count
end

-- one auction: `count` items for `buyout` copper in all (0 = bid only, left out)
function S.Add(acc, itemID, count, buyout, owner)
    if not (count and count > 0 and buyout and buyout > 0) then return end
    S.AddLevel(acc, itemID, buyout / count, count, 1, owner)
    -- auction by auction, for the items that matter to you: what sells (FT.Sales)
    if FT.Hist.Tracked(itemID) then
        local it = acc.items[itemID]
        if it then
            it.rows = it.rows or {}
            it.rows[#it.rows + 1] = { p = math.ceil(buyout / count), q = count, o = FT.Sales.OwnersKey(owner) }
        end
    end
end

local function Ladder(it)
    local ladder = {}
    for _, lv in pairs(it.levels) do ladder[#ladder + 1] = lv end
    table.sort(ladder, function(a, b) return a[1] < b[1] end)
    return ladder
end

-- order books and price observations for every item of `acc`, a little each frame; done(items)
function S.Ingest(acc, t, source, done)
    local ids = {}
    for itemID in pairs(acc.items) do ids[#ids + 1] = itemID end
    local i = 1
    local ticker
    ticker = C_Timer.NewTicker(0, function()
        local last = math.min(i + SAVE_CHUNK - 1, #ids)
        for k = i, last do
            local itemID = ids[k]
            local it = acc.items[itemID]
            local ladder = Ladder(it)
            FT.Hist.SetBook(itemID, { t = t, levels = ladder, auctions = it.auctions, qty = it.qty,
                sellers = it.sellerCount, source = source, partial = it.partial })
            FT.Hist.Observe(itemID, ladder[1][1], it.qty, it.auctions, t, source,
                (not it.partial and it.sellerCount > 0) and it.sellerCount or nil)
            if it.rows then FT.Sales.Observe(itemID, it.rows, t, it.partial, "full") end
        end
        i = last + 1
        if i > #ids then
            ticker:Cancel()
            if done then done(#ids) end
        end
    end)
end

-- a full scan: everything we know that wasn't listed is gone for now
local function MarkGone(seen, t)
    FT.Hist.EachItem(function(itemID)
        if not seen[itemID] then FT.Hist.Gone(itemID, t) end
    end)
end

-- read a list another addon handed over (`info(entry)` -> count, buyout, owner, itemID)
function S.ReadList(list, info, done)
    local acc = S.NewAcc()
    local i, n = 1, #list
    local ticker
    ticker = C_Timer.NewTicker(0, function()
        local last = math.min(i + READ_CHUNK - 1, n)
        for k = i, last do
            local count, buyout, owner, itemID = info(list[k])
            S.Add(acc, itemID, count, buyout, owner)
        end
        i = last + 1
        if i > n then
            ticker:Cancel()
            done(acc)
        end
    end)
end

-- every auction of the auction house (ours or Auctionator's): books, observations, gone, the scan log
function S.SaveFull(acc, t, source, done)
    if S.mode == "full" then S.phase = "save" end
    S.Ingest(acc, t, source, function(items)
        MarkGone(acc.items, t)
        FT.Hist.LogScan({ t = t, items = items, auctions = acc.auctions, value = acc.value, source = source })
        FT.Hist.MarkScan("full", t)
        if done then done(items) end
    end)
end

-- What the last full scan found listed, and under which key (gear: its item level and version), is kept in
-- the saved data for your items: after a /reload or the next login "my items" goes on from there instead of
-- reading the whole auction house again.
local function KeyText(key)
    if type(key) == "table" then return (key.itemLevel or 0) .. ":" .. (key.itemSuffix or 0) end
    return "0:0"
end

function S.SaveListed(t)
    local saved = {}
    for id, key in pairs(S.listed or {}) do
        if FT.Hist.Tracked(id) then saved[id] = KeyText(key) end
    end
    local r = FT.R()
    r.listed, r.meta.listedAt = saved, t
end

function S.LoadListed()
    if S.listed then return end
    local r = FT.R()
    if type(r.listed) ~= "table" or not r.meta.listedAt then return end
    local listed = {}
    for id, text in pairs(r.listed) do
        local lvl, suffix = tostring(text):match("^(%d+):(%d+)$")
        lvl, suffix = tonumber(lvl) or 0, tonumber(suffix) or 0
        if lvl ~= 0 or suffix ~= 0 then
            listed[id] = { itemID = id, itemLevel = lvl, itemSuffix = suffix, battlePetSpeciesID = 0 }
        else
            listed[id] = true
        end
    end
    S.listed, S.listedAt = listed, r.meta.listedAt
end

-- the browse list: per item the lowest price and how many are listed (gear versions merged)
function S.NewSummary()
    return { items = {}, count = 0 }
end

function S.AddBrowse(sum, results)
    for _, r in ipairs(results or {}) do
        local id = r.itemKey and r.itemKey.itemID
        local p, q = r.minPrice, r.totalQuantity
        if id and p and p > 0 and q and q > 0 then
            local e = sum.items[id]
            if not e then
                sum.items[id] = { p = p, q = q, key = r.itemKey }
                sum.count = sum.count + 1
            else
                if p < e.p then
                    e.p = p
                    e.key = r.itemKey
                end
                e.q = e.q + q
            end
        end
    end
end

-- a whole browse list (ours or Auctionator's): observations, gone, the scan log; done(items)
function S.SaveSummary(sum, t, source, done)
    if S.mode == "full" then S.phase = "save" end
    local ids = {}
    for id in pairs(sum.items) do ids[#ids + 1] = id end
    local i, value = 1, 0
    local ticker
    ticker = C_Timer.NewTicker(0, function()
        local last = math.min(i + SAVE_CHUNK - 1, #ids)
        for k = i, last do
            local id = ids[k]
            local e = sum.items[id]
            FT.Hist.Observe(id, e.p, e.q, nil, t, source)
            value = value + e.p * e.q
        end
        i = last + 1
        if i > #ids then
            ticker:Cancel()
            MarkGone(sum.items, t)
            S.listed, S.listedAt = {}, t
            for id, e in pairs(sum.items) do S.listed[id] = e.key or true end
            S.SaveListed(t)
            FT.Hist.LogScan({ t = t, items = #ids, value = value, source = source, summary = true })
            FT.Hist.MarkScan("full", t)
            if done then done(#ids) end
        end
    end)
end

---------------------------------------------------------------------------
-- Reading the game's answers
---------------------------------------------------------------------------
local function MaxRows()
    return (FT.S.scanPages or 5) * 50
end

-- a commodity's listings (stackable goods): acc item, rows the game has, complete
local function ReadCommodity(itemID)
    local acc = S.NewAcc()
    local n = AH.GetNumCommoditySearchResults and AH.GetNumCommoditySearchResults(itemID) or 0
    local rows = {}
    for i = 1, math.min(n, MaxRows()) do
        local info = AH.GetCommoditySearchResultInfo(itemID, i)
        if info then
            S.AddLevel(acc, itemID, info.unitPrice, info.quantity, 1, info.owners, info.totalNumberOfOwners)
            if info.unitPrice and info.quantity then
                rows[#rows + 1] = { p = math.ceil(info.unitPrice), q = info.quantity,
                    o = FT.Sales.OwnersKey(info.owners, info.totalNumberOfOwners), tl = FT.Sales.TimeLeft(info) }
            end
        end
    end
    local full = not AH.HasFullCommoditySearchResults or AH.HasFullCommoditySearchResults(itemID)
    if acc.items[itemID] then acc.items[itemID].rows = rows end
    return acc.items[itemID], n, full
end

-- the listings of an item that isn't stackable (gear, bags...)
local function ReadItemKey(itemKey)
    local acc = S.NewAcc()
    local itemID = itemKey.itemID
    local n = AH.GetNumItemSearchResults and AH.GetNumItemSearchResults(itemKey) or 0
    local rows = {}
    for i = 1, math.min(n, MaxRows()) do
        local info = AH.GetItemSearchResultInfo(itemKey, i)
        -- buyoutAmount is the price of one; quantity is how many are listed at it (no buyout: bid only)
        if info and info.buyoutAmount and info.buyoutAmount > 0 then
            S.AddLevel(acc, itemID, info.buyoutAmount, info.quantity or 1, 1, info.owners, info.totalNumberOfOwners)
            rows[#rows + 1] = { p = math.ceil(info.buyoutAmount), q = info.quantity or 1,
                o = FT.Sales.OwnersKey(info.owners, info.totalNumberOfOwners), tl = FT.Sales.TimeLeft(info) }
        end
    end
    local full = not AH.HasFullItemSearchResults or AH.HasFullItemSearchResults(itemKey)
    if acc.items[itemID] then acc.items[itemID].rows = rows end
    return acc.items[itemID], n, full
end

-- book and price of one item from a search
local function SaveItem(itemID, it, n, full, source)
    if not (it and next(it.levels)) then return false end
    local t = time()
    it.partial = (not full or n > MaxRows()) or nil
    local ladder = Ladder(it)
    FT.Hist.SetBook(itemID, { t = t, levels = ladder, auctions = it.auctions, qty = it.qty, sellers = it.sellerCount,
        source = source, partial = it.partial })
    FT.Hist.Observe(itemID, ladder[1][1], it.qty, (not it.partial) and it.auctions or nil, t, source,
        (not it.partial and it.sellerCount > 0) and it.sellerCount or nil)
    if it.rows then FT.Sales.Observe(itemID, it.rows, t, it.partial, "search") end
    return true
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
S.mode = nil -- nil, "full", "mine"

local function Clean()
    if S.ticker then
        S.ticker:Cancel()
        S.ticker = nil
    end
    if S.timeoutTimer then
        S.timeoutTimer:Cancel()
        S.timeoutTimer = nil
    end
    S.mode, S.phase, S.waiting, S.current, S.wantMore, S.asked = nil, nil, false, nil, false, false
    S.sum, S.deep = nil, false
    FT.scanning = false
end

local STOP_TEXT = {
    closed = "Scan stopped: the auction house closed.",
    other = "Full scan stopped: another search was made in the auction house before it finished. Press Full scan again.",
    timeout = "Full scan stopped: the server didn't answer.",
    user = "Scan stopped.",
}

function S.Stop(why, quiet)
    S.chainMine = false
    if not S.mode then return end
    local mode = S.mode
    Clean()
    if not quiet then FT.Print(L[STOP_TEXT[why] or STOP_TEXT.user]) end
    FT.Fire("FT_SCAN_FAILED", mode)
    if mode == "mine" then FT.Fire("FT_SCAN_DONE", "mine") end
end

function S.Running()
    return S.mode ~= nil
end

local function Finish(mode, text)
    Clean()
    if text then FT.Print(text) end
    FT.Fire("FT_SCAN_DONE", mode)
    -- "my items" asked for a full scan first: now it goes on with the keys that scan found
    if mode == "full" and S.chainMine then
        S.chainMine = false
        C_Timer.After(0.5, function() S.StartMine(true) end)
    end
end

local function Clock(sec)
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end
S.Clock = Clock

-- seconds until a deep full scan is allowed again (0 = now)
function S.DeepWait()
    local last = FT.db.lastReplicate
    if not last then return 0 end
    return math.max(0, REPLICATE_COOLDOWN - (time() - last))
end

-- for the progress bar: fraction 0-1, text
function S.Progress()
    if S.mode == "full" then
        if S.phase == "wait" then return 0.03, L["Full scan: waiting for the server..."] end
        if S.phase == "browse" then
            local n = S.sum and S.sum.count or 0
            return math.min(0.9, 0.05 + n / (n + 3000) * 0.85), string.format(L["Full scan: %s items"], FT.Num(n))
        end
        if S.phase == "read" then
            local f = (S.total or 0) > 0 and S.done / S.total or 0
            return 0.05 + f * 0.85, string.format(L["Full scan: %s / %s auctions"], FT.Num(S.done or 0), FT.Num(S.total or 0))
        end
        return 0.95, L["Full scan: saving..."]
    elseif S.mode == "mine" then
        local n = S.queue and #S.queue or 0
        local f = n > 0 and (S.idx - 1) / n or 0
        local text = string.format(L["My items: %d / %d"], math.min(S.idx, n), n)
        if S.pausedUntil and GetTime() < S.pausedUntil then
            text = text .. "  " .. L["(paused: you are searching)"]
        elseif S.current then
            text = text .. "  " .. (FT.Item(S.current) or "")
        end
        return f, text
    end
    return nil
end

local function NeedAH(quiet)
    if not Modern() then
        if not quiet then FT.Print(L["This client's auction house can't be scanned by ForeverTrading."]) end
        return false
    end
    if not FT.ahOpen then
        if not quiet then FT.Print(FT.House.Why(L["Open the auction house first."])) end
        return false
    end
    return true
end

---------------------------------------------------------------------------
-- Full scan: the browse list (any time), or every auction (deep, every 15 minutes)
---------------------------------------------------------------------------
local function SendBrowseAll()
    S.sending = true
    local ok = pcall(AH.SendBrowseQuery, { searchString = "", sorts = {}, filters = {}, itemClassFilters = {} })
    S.sending = false
    return ok
end

local function StartDeep()
    if not AH.ReplicateItems then return false end
    S.sending = true
    local ok = pcall(AH.ReplicateItems)
    S.sending = false
    if not ok then return false end
    FT.db.lastReplicate = time()
    return true
end

-- the browse list is complete (or as complete as it gets): save it
local function BrowseFinished()
    if S.ticker then
        S.ticker:Cancel()
        S.ticker = nil
    end
    local sum = S.sum
    S.SaveSummary(sum, time(), "full", function(items)
        Finish("full", string.format(L["Full scan done: %s items."], FT.Num(items)))
    end)
end

local function BrowseStep()
    if S.mode ~= "full" then return end
    if S.phase == "wait" and not S.asked then
        if Ready() then
            S.asked = SendBrowseAll()
            if not S.asked then return S.Stop("timeout") end
            S.waitFrom = GetTime()
        end
    elseif S.phase == "browse" and S.wantMore and Ready() then
        S.wantMore = false
        S.sending = true
        pcall(AH.RequestMoreBrowseResults)
        S.sending = false
        S.waitFrom = GetTime()
    end
    if GetTime() - (S.waitFrom or GetTime()) > 20 then
        -- no next page for a long time: keep what came
        if S.phase == "browse" and S.sum and S.sum.count > 0 then return BrowseFinished() end
        S.Stop("timeout")
    end
end

function S.StartFull(quiet)
    if not NeedAH(quiet) then return false end
    if S.mode == "full" then
        if not quiet then FT.Print(L["A scan is already running."]) end
        return false
    end
    -- the full scan takes over from "my items" (what it read is kept)
    if S.mode == "mine" then S.Stop("user", true) end
    S.mode, S.phase, S.done, S.total = "full", "wait", 0, 0
    S.fullTried = time()
    FT.scanning = true
    if FT.S.deepFull and S.DeepWait() == 0 and StartDeep() then
        S.deep = true
        S.timeoutTimer = C_Timer.NewTimer(120, function()
            S.timeoutTimer = nil
            if S.mode == "full" and S.phase == "wait" then S.Stop("timeout") end
        end)
    else
        if FT.S.deepFull and not quiet then
            FT.Print(string.format(L["A deep scan is allowed once every 15 minutes (next in %s): reading the browse list instead."], Clock(S.DeepWait())))
        end
        S.deep, S.asked, S.sum, S.waitFrom = false, false, S.NewSummary(), GetTime()
        S.ticker = C_Timer.NewTicker(0.2, BrowseStep)
    end
    FT.Fire("FT_SCAN_START", "full")
    return true
end

-- the browse list changed while our full scan runs: true when it was ours
local function OnBrowseFull(added)
    if S.mode ~= "full" or S.deep then return false end
    if S.phase ~= "wait" and S.phase ~= "browse" then return true end
    if S.phase == "wait" and not S.asked then return false end
    if added then
        S.AddBrowse(S.sum, added)
    else
        -- the whole list (again): start over with it
        S.sum = S.NewSummary()
        S.AddBrowse(S.sum, AH.GetBrowseResults())
    end
    S.phase = "browse"
    S.waitFrom = GetTime()
    if AH.HasFullBrowseResults and not AH.HasFullBrowseResults() then
        S.wantMore = true
    else
        S.phase = "save"
        BrowseFinished()
    end
    return true
end

local function ReadDeep()
    if S.timeoutTimer then
        S.timeoutTimer:Cancel()
        S.timeoutTimer = nil
    end
    S.phase = "read"
    local n = AH.GetNumReplicateItems() or 0
    S.total, S.done = n, 0
    local acc = S.NewAcc()
    local t = time()
    local i = 0
    S.ticker = C_Timer.NewTicker(0, function()
        if S.mode ~= "full" then return end
        local last = math.min(i + READ_CHUNK - 1, n - 1)
        for k = i, last do
            local _, _, count, _, _, _, _, _, _, buyout, _, _, _, owner, _, _, itemID = AH.GetReplicateItemInfo(k)
            S.Add(acc, itemID, count, buyout, owner)
        end
        i = last + 1
        S.done = math.min(n, i)
        if i >= n then
            S.ticker:Cancel()
            S.ticker = nil
            S.SaveFull(acc, t, "full", function(items)
                Finish("full", string.format(L["Full scan done: %s items, %s auctions."], FT.Num(items), FT.Num(acc.auctions)))
            end)
        end
    end)
end

---------------------------------------------------------------------------
-- My items
---------------------------------------------------------------------------
-- what "my items" looks up, the longest unseen first
function S.MineList()
    local set = {}
    FT.Craft.EachItem(function(id) set[id] = true end)
    for id in pairs(FT.db.watch) do set[id] = "watch" end
    if FT.Port and FT.Port.Holdings then
        for id in pairs(FT.Port.Holdings()) do
            -- what you own counts once it has been seen on the auction house (soulbound and quest items never are)
            if not set[id] and FT.Price(id) then set[id] = true end
        end
    end
    local now = time()
    local listed = S.listedAt and now - S.listedAt < LISTED_FRESH and S.listed or nil
    local list, age = {}, {}
    for id, why in pairs(set) do
        -- vendor goods are bought from a vendor; skip them unless you watch them.
        -- After a recent full scan: what it didn't find has no listings to read.
        if (why == "watch" or not FT.VENDOR_REAGENTS[id]) and (not listed or listed[id]) then
            local book = FT.Hist.Book(id)
            local seen = book and book.source ~= "mastercraft" and book.t or 0
            if now - seen > 600 then
                list[#list + 1] = id
                age[id] = seen
            end
        end
    end
    table.sort(list, function(a, b)
        if age[a] ~= age[b] then return age[a] < age[b] end
        return a < b
    end)
    return list
end

-- stage: "key" (search by the bare item), "name" (the browse list by its name), "exact" (the key found by name)
local function ResetItem()
    S.current, S.stage, S.exactKey, S.waiting, S.retries, S.wantMore = nil, "key", nil, false, 0, false
end

local function NextItem()
    S.idx = S.idx + 1
    ResetItem()
    local id = S.queue and S.queue[S.idx]
    local key = id and S.listed and type(S.listed[id]) == "table" and S.listed[id]
    if key then S.stage, S.exactKey = "exact", key end
end

-- found = false: none listed (confirmed)
local function ItemDone(found)
    if found == false and S.current then
        FT.Hist.Gone(S.current, time())
        FT.Hist.SetBook(S.current, { t = time(), levels = {}, auctions = 0, qty = 0, sellers = 0, source = "mine" })
        FT.Sales.Observe(S.current, {}, time(), false, "search")
    end
    NextItem()
end

-- no listings under the bare item: gear is listed under a key with its item level - look it up by name
local function TryByName()
    S.stage, S.waiting, S.retries = "name", false, 0
end

local function Send()
    local id = S.queue[S.idx]
    if not Ready() then return end
    S.current = id
    local query
    if S.stage == "name" then
        local name = FT.Item(id)
        if not name then
            -- no name to search with yet: tried again at the end, once
            if not S.deferred[id] then
                S.deferred[id] = true
                S.queue[#S.queue + 1] = id
            end
            return NextItem()
        end
        query = function() AH.SendBrowseQuery({ searchString = name, sorts = PriceSort(), filters = {}, itemClassFilters = {} }) end
    elseif S.stage == "exact" then
        local key = S.exactKey
        query = function() AH.SendSearchQuery(key, PriceSort(), false) end
    else
        query = function() AH.SendSearchQuery(AH.MakeItemKey(id), PriceSort(), false) end
    end
    S.sending = true
    local ok = pcall(query)
    S.sending = false
    if not ok then return NextItem() end
    S.waiting, S.sentAt = true, GetTime()
end

local function Step()
    if S.mode ~= "mine" then return end
    if not FT.ahOpen then return S.Stop("closed") end
    if S.pausedUntil and GetTime() < S.pausedUntil then return end
    if S.waiting then
        if GetTime() - S.sentAt > ANSWER_TIMEOUT then
            S.waiting = false
            if S.stage == "key" then
                TryByName()
            else
                S.retries = S.retries + 1
                if S.retries >= 2 then NextItem() end -- no answer: we know nothing new, go on
            end
        end
        return
    end
    if S.wantMore then
        -- the next rows of a long list
        if Ready() then
            S.wantMore = false
            S.sending = true
            if S.moreKind == "commodity" then
                pcall(AH.RequestMoreCommoditySearchResults, S.current)
            else
                pcall(AH.RequestMoreItemSearchResults, S.moreKey)
            end
            S.sending = false
            S.waiting, S.sentAt = true, GetTime()
        end
        return
    end
    if not S.queue[S.idx] then
        return Finish("mine", string.format(L["My items scanned: %d."], #S.queue))
    end
    Send()
end

-- The My items button: it reads the order book of every item of yours, one search each - that takes minutes,
-- so it asks first
function S.AskMine()
    if not NeedAH(false) then return false end
    if S.mode then
        FT.Print(L["A scan is already running."])
        return false
    end
    S.LoadListed()
    local n = #S.MineList()
    -- nothing to read: StartMine says why
    if n == 0 then return S.StartMine() end
    FT.UI.Confirm({
        title = L["My items"],
        text = string.format(L["My items: the order book of every item your recipes make and use, your watchlist and what you own - one search each, %s items now. It can take a few minutes. Your own searches at the auction house pause it, and live prices wait for it."], FT.Num(n)),
        ok = L["Continue"],
        onOK = function() S.StartMine() end,
    })
    return true
end

-- ids: just these items (no full scan first, however recently they were seen)
function S.StartMine(quiet, ids)
    if not NeedAH(quiet) then return false end
    if S.mode then
        if not quiet then FT.Print(L["A scan is already running."]) end
        return false
    end
    -- without a recent full scan: one first (a few seconds) - it tells which items are listed at all and
    -- under which key, so "my items" asks only for those, once each (also one from before a /reload)
    S.LoadListed()
    local now = time()
    local fresh = S.listedAt and now - S.listedAt < LISTED_FRESH
    if not ids and not fresh and not (S.fullTried and now - S.fullTried < 120) then
        if S.StartFull(quiet) then
            S.chainMine = true
            return true
        end
    end
    local queue = ids or S.MineList()
    if #queue == 0 then
        if not quiet then FT.Print(L["Nothing to scan: your items were all seen in the last 10 minutes (or no recipes are known yet)."]) end
        return false
    end
    for _, id in ipairs(queue) do FT.RequestItem(id) end
    S.mode, S.queue, S.idx, S.deferred = "mine", queue, 0, {}
    NextItem()
    S.pausedUntil = nil
    FT.scanning = true
    S.ticker = C_Timer.NewTicker(0.1, Step)
    FT.Fire("FT_SCAN_START", "mine")
    return true
end

---------------------------------------------------------------------------
-- Live: the item you have open, searched again every few seconds while the auction house is open (on the
-- Craft page the recipe's item and its materials take turns). One search at a time, only when nothing else
-- runs, never right after a search of yours, slower when the server says it is busy.
---------------------------------------------------------------------------
local LIVE_EVERY = 8  -- one item: searched every 8 seconds
local LIVE_TURN = 4   -- several (an item and its materials): one of them every 4 seconds
local LIVE_SLOW = 30
-- head: the item opened (the first of the list); turn: whose turn it was; answered: itemID -> when prices came
local live = { id = nil, head = nil, turn = 0, sentAt = 0, slowUntil = 0, rest = {}, answered = {}, named = {} }
local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- The key an item is searched by. Stackable goods: the item itself. Gear is listed under a key with its item
-- level (and version, "of the Bear"): the one the last full scan (or a search by name) found, else one made
-- with the item's own level. how: "known" / "level" / "bare"
function S.KeyFor(id)
    S.LoadListed()
    local known = S.listed and S.listed[id]
    if type(known) == "table" then return known, "known" end
    if FT.Buy and FT.Buy.IsCommodity(id) == false then
        local level = select(4, GetInfo(id))
        if level and level > 0 then
            local ok, key = pcall(AH.MakeItemKey, id, level)
            if ok and type(key) == "table" then return key, "level" end
        end
    end
    return AH.MakeItemKey(id), "bare"
end

-- a key found for an item (by a search by name): used from now on and kept for the next time
local function Learn(id, key)
    S.LoadListed()
    S.listed = S.listed or {}
    S.listed[id] = key
    local r = FT.R()
    r.listed = r.listed or {}
    r.listed[id] = KeyText(key)
end

-- the game's auction house window on screen: its browse list is yours (not replaced by our searches by name)
local function WindowOnScreen()
    local f = AuctionHouseFrame
    return f ~= nil and f:IsVisible() and f:GetAlpha() > 0.05
end

-- gear not found under its key: its versions looked up by name, once (the cheapest one is searched next)
local function FindByName(id)
    if live.named[id] or WindowOnScreen() then return false end
    local name = FT.Name(id)
    if not name then return false end
    live.named[id] = true
    S.sending = true
    local ok = pcall(AH.SendBrowseQuery, { searchString = name, sorts = PriceSort(), filters = {}, itemClassFilters = {} })
    S.sending = false
    if ok then live.browseFor, live.browseAt = id, GetTime() end
    return ok
end
S.otherAt = 0

-- the items on screen, all taking turns: the item window's, the open page's item (on the Craft page its
-- materials too)
local function LiveTargets()
    if not FT.S.liveRefresh then return nil end
    local list, seen = {}, {}
    local function Add(id)
        if id and not seen[id] then
            seen[id] = true
            list[#list + 1] = id
        end
    end
    if FT.Detail and FT.Detail.Items then
        for _, id in ipairs(FT.Detail.Items() or {}) do Add(id) end
    end
    if FT.IsShown and FT.IsShown() then
        local tab = FT.Tabs and FT.Tabs[FT.currentTab]
        if tab and tab.LiveItems then
            for _, id in ipairs(tab.LiveItems() or {}) do Add(id) end
        elseif tab and tab.LiveItem then
            Add(tab.LiveItem())
        end
    end
    return list[1] and list or nil
end

-- the auction house window is busy with an item of its own (buying, selling): it goes first
local function AHBusy()
    local f = AuctionHouseFrame
    if f and not f:IsVisible() then return false end
    if not f then return false end
    for _, k in ipairs({ "CommoditiesBuyFrame", "ItemBuyFrame" }) do
        local sub = f[k]
        if type(sub) == "table" and sub.IsVisible and sub:IsVisible() then return true end
    end
    -- its Sell tab only with an item placed in it
    for _, k in ipairs({ "CommoditiesSellFrame", "ItemSellFrame" }) do
        local sub = f[k]
        if type(sub) == "table" and sub.IsVisible and sub:IsVisible() then
            local ok, item = pcall(function() return sub.GetItem and sub:GetItem() end)
            if not ok or item then return true end
        end
    end
    return false
end

S.AHBusy = AHBusy

local function LiveStep()
    if not (FT.ahOpen and Modern()) then
        live.list = nil
        return
    end
    local list = LiveTargets()
    live.list = list
    if not (list and list[1]) then
        live.head = nil
        return
    end
    -- a scan goes first (ours or Auctionator's): the items wait for it, their circles pale
    live.blocked = S.mode ~= nil or FT.atrScanning
    if live.blocked then return end
    local now = GetTime()
    -- another item opened: it goes first, now
    if list[1] ~= live.head then
        live.head, live.turn, live.sentAt = list[1], 0, 0
    end
    local every = now < live.slowUntil and LIVE_SLOW or (#list > 1 and LIVE_TURN or LIVE_EVERY)
    live.every = every
    -- an item just opened goes before the others
    local turn
    if live.now then
        for k, id in ipairs(list) do
            if id == live.now and not (live.rest[id] and now < live.rest[id]) then turn = k end
        end
        if not turn then live.now = nil end
    end
    if not turn then
        if now - live.sentAt < every then return end
        -- whose turn: the next one, passing over the items resting (gear with nothing under its key)
        local passed = 0
        turn = live.turn % #list + 1
        while live.rest[list[turn]] and now < live.rest[list[turn]] do
            passed = passed + 1
            if passed >= #list then return end
            turn = turn % #list + 1
        end
    end
    if now - (S.otherAt or 0) < 4 or AHBusy() or not Ready() then return end
    -- a search by name of ours under way: its answer first
    if live.browseFor and now - live.browseAt < 10 then return end
    local id = list[turn]
    local key = S.KeyFor(id)
    S.sending = true
    local ok = pcall(AH.SendSearchQuery, key, PriceSort(), false)
    S.sending = false
    live.id, live.turn, live.sentAt, live.waiting = id, turn, now, ok
    if id == live.now then live.now = nil end
end

-- the item is being kept live (its prices came in the last half minute)
function S.LiveOn(id)
    local at = id and live.answered[id]
    return FT.ahOpen and at ~= nil and GetTime() - at < 30
end

-- The countdown of an item kept live (the green circle in the lists): when its round began and how long a
-- round takes - it is searched again at the end. 0, 0: kept live but waiting for its first search (a scan or
-- a search of yours goes first). nil: not kept live.
function S.LiveTick(id)
    local list = live.list
    if not (id and list and FT.ahOpen) then return nil end
    local n = #list
    for k = 1, n do
        if list[k] == id then
            if live.blocked or live.sentAt == 0 or not live.every or list[1] ~= live.head then return 0, 0 end
            -- turns until it is searched again (n for the one just searched)
            local steps = (k - live.turn - 1) % n + 1
            local round = live.every * n
            return live.sentAt + live.every * steps - round, round
        end
    end
    return nil
end

-- open an item: its search goes out at once instead of waiting for its turn
function S.LiveNow(id)
    live.now = id
    if not id then live.sentAt = 0 end
    LiveStep()
end

-- for /ft debug
function S.LiveState()
    local ids = {}
    for _, id in ipairs(live.list or {}) do ids[#ids + 1] = tostring(id) end
    return string.format("live: on %s, ah %s, items [%s], blocked %s, last search %s s ago, every %s s",
        tostring(FT.S.liveRefresh), tostring(FT.ahOpen), table.concat(ids, ","), tostring(live.blocked),
        live.sentAt > 0 and string.format("%.1f", GetTime() - live.sentAt) or "-", tostring(live.every))
end

-- the answer to our live search; true when it was one. commodity: stackable goods have one key, so
-- nothing under it means none listed; gear is listed under a key per version (item level, "of the Bear"...)
local function LiveAnswer(itemID, it, n, full, commodity)
    if not (live.waiting and live.id == itemID) then return false end
    live.waiting = false
    if n > 0 then
        SaveItem(itemID, it, n, full, "live")
    elseif full and commodity then
        -- none listed any more
        FT.Hist.Gone(itemID, time(), "live")
        FT.Hist.SetBook(itemID, { t = time(), levels = {}, auctions = 0, qty = 0, sellers = 0, source = "live" })
        FT.Sales.Observe(itemID, {}, time(), false, "search")
    else
        -- gear with nothing under this key (that version sold, or it is listed under a key we don't know):
        -- what we know stays; its versions are looked up by name once, else it rests for two minutes
        if S.listed and type(S.listed[itemID]) == "table" then S.listed[itemID] = true end
        if not FindByName(itemID) then live.rest[itemID] = GetTime() + 120 end
        return true
    end
    live.answered[itemID] = GetTime()
    FT.Market.Touch(itemID)
    FT.Fire("FT_LIVE_UPDATED", itemID)
    return true
end

-- an answer about one item: ours (my items, live) or anything you looked at yourself
local function OnCommodity(itemID)
    if not itemID then return end
    local it, n, full = ReadCommodity(itemID)
    if S.mode == "mine" and S.current == itemID and S.waiting then
        S.waiting = false
        if not full and n < MaxRows() then
            S.wantMore, S.moreKind = true, "commodity" -- more rows to come
            return
        end
        if n == 0 then return ItemDone(false) end
        SaveItem(itemID, it, n, full, "mine")
        return ItemDone(true)
    end
    if LiveAnswer(itemID, it, n, full, true) then return end
    if n > 0 then SaveItem(itemID, it, n, full, "search") end
end

local function OnItemKey(itemKey)
    if type(itemKey) ~= "table" or not itemKey.itemID then return end
    local itemID = itemKey.itemID
    local it, n, full = ReadItemKey(itemKey)
    if S.mode == "mine" and S.current == itemID and S.waiting then
        S.waiting = false
        if not full and n < MaxRows() then
            S.wantMore, S.moreKind, S.moreKey = true, "item", itemKey
            return
        end
        if n == 0 then
            -- nothing under the bare key: gear has its own keys - find them by name
            if S.stage == "key" then return TryByName() end
            return ItemDone(false)
        end
        SaveItem(itemID, it, n, full, "mine")
        return ItemDone(true)
    end
    if LiveAnswer(itemID, it, n, full, false) then return end
    if n > 0 then SaveItem(itemID, it, n, full, "search") end
end

-- the browse list changed: our full scan, our search by name, or your own search
local function OnBrowse(added)
    if OnBrowseFull(added) then return end
    local results = added or (AH.GetBrowseResults and AH.GetBrowseResults()) or {}
    -- live: the versions of a gear item looked up by name - its cheapest key is searched next
    local want = live.browseFor
    if want and GetTime() - live.browseAt < 10 then
        local best
        for _, r in ipairs(results) do
            local k = r.itemKey
            if k and k.itemID == want and r.minPrice and r.minPrice > 0 and (not best or r.minPrice < best.minPrice) then
                best = r
            end
        end
        if best or not AH.HasFullBrowseResults or AH.HasFullBrowseResults() then
            live.browseFor = nil
            if best then
                Learn(want, best.itemKey)
                live.rest[want] = nil
                live.now, live.sentAt = want, 0
            else
                live.rest[want] = GetTime() + 120
            end
        end
    end
    if S.mode == "mine" and S.stage == "name" and S.waiting then
        -- our search by name: the cheapest key of our item, searched next for its listings
        local best
        for _, r in ipairs(results) do
            local k = r.itemKey
            if k and k.itemID == S.current and r.minPrice and r.minPrice > 0 and (not best or r.minPrice < best.minPrice) then
                best = r
            end
        end
        if best then
            S.stage, S.exactKey, S.waiting = "exact", best.itemKey, false
        elseif not AH.HasFullBrowseResults or AH.HasFullBrowseResults() then
            S.waiting = false
            ItemDone(false)
        end
        return
    end
    -- what you searched yourself: the lowest price of every item in the list
    local sum = S.NewSummary()
    S.AddBrowse(sum, results)
    local t = time()
    for id, e in pairs(sum.items) do FT.Hist.Observe(id, e.p, e.q, nil, t, "search") end
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED" then
        OnCommodity(...)
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED" then
        OnItemKey(...)
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
        OnBrowse(nil)
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
        OnBrowse(...)
    elseif event == "AUCTION_HOUSE_BROWSE_FAILURE" then
        if S.mode == "full" and not S.deep then S.Stop("timeout") end
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        if S.mode == "full" and S.deep and S.phase == "wait" then ReadDeep() end
    elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
        -- the server is busy: live searches slow down for two minutes
        live.slowUntil = GetTime() + 120
        live.waiting = false
    end
end)

local EVENTS = {
    "COMMODITY_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_ADDED", "ITEM_SEARCH_RESULTS_UPDATED",
    "ITEM_SEARCH_RESULTS_ADDED", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
    "AUCTION_HOUSE_BROWSE_FAILURE", "REPLICATE_ITEM_LIST_UPDATE", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
}

---------------------------------------------------------------------------
-- Searches that aren't ours
---------------------------------------------------------------------------
local hooked = false
local function HookSearches()
    if hooked or not Modern() then return end
    hooked = true
    local function Other(name)
        if S.sending then return end
        S.otherAt = GetTime()
        if S.mode == "mine" then
            -- yours (or another addon's) first: ours goes on a few seconds after the last one
            S.pausedUntil = GetTime() + 4
            S.waiting, S.wantMore = false, false
        elseif S.mode == "full" and not S.deep and (name == "SendBrowseQuery" or name == "ReplicateItems") then
            -- the browse list we read is replaced
            S.Stop("other")
        end
    end
    for _, name in ipairs({ "SendBrowseQuery", "SendSearchQuery", "SendSellSearchQuery", "SearchForFavorites",
        "SearchForItemKeys", "ReplicateItems", "RequestMoreBrowseResults", "RequestMoreCommoditySearchResults",
        "RequestMoreItemSearchResults" }) do
        if type(AH[name]) == "function" then
            hooksecurefunc(AH, name, function() Other(name) end)
        end
    end
end

---------------------------------------------------------------------------
-- Auction house open / closed, scanning by itself
---------------------------------------------------------------------------
local liveTicker

-- Online: at the auction house, and it is the one whose prices are on (House.lua) - its lists are read, the open
-- item searched again, scans run, you buy and post. Offline: away, or looking at the other house's prices while
-- standing at this one (nothing of this one may go into them).
function S.SetOnline(on)
    on = on and true or false
    if on == (FT.ahOpen == true) then return end
    if on then
        FT.ahOpen = true
        if not Modern() then return end
        HookSearches()
        for _, e in ipairs(EVENTS) do pcall(frame.RegisterEvent, frame, e) end
        if not liveTicker then liveTicker = C_Timer.NewTicker(1, LiveStep) end
    else
        FT.ahOpen = false
        if liveTicker then
            liveTicker:Cancel()
            liveTicker = nil
        end
        live.id, live.head, live.list, live.waiting, live.rest, live.answered = nil, nil, nil, false, {}, {}
        live.named, live.browseFor = {}, nil
        if S.mode then S.Stop("closed") end
        frame:UnregisterAllEvents()
    end
    FT.Fire("FT_AH_CHANGED")
end

FT.On("AUCTION_HOUSE_SHOW", function()
    S.SetOnline(not FT.House or FT.House.Online())
    C_Timer.After(2.5, function()
        if not FT.ahOpen or S.mode then return end
        local now = time()
        if FT.S.autoFull and now - (FT.Hist.LastScan("full") or 0) > 3600 then
            S.StartFull(true)
        end
    end)
end)

-- the other auction house: its own keys of the listings (read from its data when needed)
FT.On("FT_HOUSE_CHANGED", function()
    S.listed, S.listedAt = nil, nil
    live.answered = {}
end)

FT.On("AUCTION_HOUSE_CLOSED", function()
    S.SetOnline(false)
end)

---------------------------------------------------------------------------
-- "Search on AH" buttons
---------------------------------------------------------------------------
-- Auctionator's Shopping tab when it is installed; without it the game's own search (one item) or
-- ForeverTrading's scanner for a list (an item and its materials): fresh prices and order books either way
function FT.SearchItems(ids)
    local names = {}
    for _, id in ipairs(ids) do
        local name = FT.Item(id)
        if name then names[#names + 1] = name end
    end
    if FT.Atr.Loaded() and #names > 0 and FT.Atr.Search(names) then return true end
    if not NeedAH(false) then return false end
    if #ids == 1 then
        if not names[1] then return false end
        pcall(AH.SendBrowseQuery, { searchString = names[1], sorts = PriceSort(), filters = {}, itemClassFilters = {} })
        return true
    end
    return S.StartMine(false, ids)
end
