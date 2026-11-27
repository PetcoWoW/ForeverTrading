-- Wolf: your auction house visits, like a farming session but for the auction house. From the moment you open it
-- to the moment you walk away: what you bought (how many, what each cost, against its usual price), what you
-- posted (at what price), what you took off; what you spent, the value you put up, your gold before and after.
-- Purchases and postings are seen whatever window made them (Wolf's, the game's, Auctionator's). Kept: the last
-- 30 visits. One line in chat when you walk away (Settings: the wolf's notes).
--
-- And the watchlist, live: while the auction house is open, the items you watch take turns in the live searches;
-- one listed well under its usual price (15%+) says so in chat - how many, under what - with [Buy them].
local ADDON, FT = ...
local L = FT.L

local V = {}
FT.AHVisit = V

local KEEP = 30
local WATCH_UNDER = 0.15   -- a watched item listed this far under its usual price: said in chat
local AH = C_AuctionHouse

local visit           -- the visit under way: { start, gold0, events = { { t, k, id, q, u, usual } } }

local function Usual(id)
    local s = FT.An and FT.An.Stats(id)
    if not s then return nil end
    return (s.avg and s.fair and math.min(s.avg, s.fair)) or s.fair or s.avg
end

local function Log(kind, id, qty, unit)
    if not (visit and id and qty and qty > 0) then return end
    table.insert(visit.events, { t = time(), k = kind, id = id, q = qty, u = unit and math.floor(unit) or nil, usual = Usual(id) })
    FT.Fire("FT_AH_VISIT")
end
V.Log = Log

function V.Current() return visit end

function V.Past()
    FT.db.ahVisits = FT.db.ahVisits or {}
    return FT.db.ahVisits
end

-- a visit's numbers: spent, bought (lots, against usual), posted value, taken off
function V.Sum(v)
    local s = { spent = 0, bought = 0, boughtUsual = 0, boughtQty = 0, posted = 0, postedQty = 0, cancelled = 0, items = {} }
    for _, e in ipairs(v and v.events or {}) do
        local value = (e.u or 0) * e.q
        if e.k == "B" then
            s.spent, s.bought, s.boughtQty = s.spent + value, s.bought + 1, s.boughtQty + e.q
            if e.usual then s.boughtUsual = s.boughtUsual + e.usual * e.q end
        elseif e.k == "P" then
            s.posted, s.postedQty = s.posted + value, s.postedQty + e.q
        elseif e.k == "C" then
            s.cancelled = s.cancelled + 1
        end
        s.items[e.id] = true
    end
    -- what you bought against its usual price: under it is good
    s.vsUsual = s.boughtUsual > 0 and (s.spent / s.boughtUsual - 1) or nil
    return s
end

FT.On("AUCTION_HOUSE_SHOW", function()
    visit = { start = time(), gold0 = GetMoney(), events = {} }
    FT.Fire("FT_AH_VISIT")
end)

FT.On("AUCTION_HOUSE_CLOSED", function()
    local v = visit
    visit = nil
    if not v then return end
    v.stop, v.gold1 = time(), GetMoney()
    if #v.events == 0 then return end
    local past = V.Past()
    table.insert(past, 1, v)
    for i = #past, KEEP + 1, -1 do past[i] = nil end
    FT.Fire("FT_AH_VISIT")
    if FT.S.eyeChat == false then return end
    local s = V.Sum(v)
    local bits = {}
    if s.bought > 0 then
        bits[#bits + 1] = string.format(L["bought %d (%s)"], s.bought, FT.Money(math.floor(s.spent), "short"))
            .. (s.vsUsual and (" " .. FT.C(s.vsUsual <= 0 and "up" or "down", FT.Pct(s.vsUsual, true)) .. FT.C("dim", " " .. L["vs usual"])) or "")
    end
    if s.postedQty > 0 then
        bits[#bits + 1] = string.format(L["posted %s (%s)"], FT.Num(s.postedQty), FT.Money(math.floor(s.posted), "short"))
    end
    if s.cancelled > 0 then bits[#bits + 1] = string.format(L["took off %d"], s.cancelled) end
    local net = v.gold1 - v.gold0
    FT.Print(FT.C("accent", L["AH visit"]) .. "  " .. table.concat(bits, FT.C("dim", "  ·  "))
        .. FT.C("dim", "  ·  " .. L["gold"] .. " ") .. FT.C(net >= 0 and "up" or "down", FT.SignedMoney(net)))
end)

---------------------------------------------------------------------------
-- What you bought and posted, whatever window: the auction house's own functions, read as they're called
---------------------------------------------------------------------------
local quote          -- the last price the server quoted for stackable goods: { unit, total }
local buyingOther    -- a purchase made outside Wolf: { id, qty } (stackable) / { auctionID, amount, id } (gear)
local postingOther   -- a posting made outside Wolf: { id, qty, unit }
local itemResults = {} -- the last gear search results: auctionID -> itemID

FT.On("COMMODITY_PRICE_UPDATED", function(unit, total) quote = { unit = unit, total = total } end)
FT.On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
    if not (AH and itemKey and AH.GetNumItemSearchResults) then return end
    for i = 1, AH.GetNumItemSearchResults(itemKey) or 0 do
        local info = AH.GetItemSearchResultInfo(itemKey, i)
        if info and info.auctionID then itemResults[info.auctionID] = itemKey.itemID end
    end
end)

local function ItemIDAt(loc)
    if not (loc and C_Item and C_Item.GetItemID) then return nil end
    local ok, id = pcall(C_Item.GetItemID, loc)
    return ok and id or nil
end

if AH and hooksecurefunc then
    pcall(hooksecurefunc, AH, "ConfirmCommoditiesPurchase", function(itemID, qty)
        if FT.Buy and FT.Buy.Busy() then return end -- Wolf's own: said by Buy
        buyingOther = { id = itemID, qty = qty }
    end)
    pcall(hooksecurefunc, AH, "PlaceBid", function(auctionID, amount)
        if FT.Buy and FT.Buy.Busy() then return end
        buyingOther = { auctionID = auctionID, amount = amount, id = itemResults[auctionID] }
    end)
    pcall(hooksecurefunc, AH, "PostCommodity", function(loc, _, qty, unit)
        if FT.Sell and FT.Sell.Busy() then return end
        postingOther = { id = ItemIDAt(loc), qty = qty, unit = unit }
    end)
    pcall(hooksecurefunc, AH, "PostItem", function(loc, _, qty, _, buyout)
        if FT.Sell and FT.Sell.Busy() then return end
        postingOther = { id = ItemIDAt(loc), qty = qty or 1, unit = buyout and buyout / math.max(1, qty or 1) or nil }
    end)
end

FT.On("COMMODITY_PURCHASE_SUCCEEDED", function()
    local b = buyingOther
    buyingOther = nil
    if b and b.id and b.qty then Log("B", b.id, b.qty, quote and quote.total and quote.total / b.qty or (quote and quote.unit)) end
end)
FT.On("AUCTION_HOUSE_PURCHASE_COMPLETED", function(auctionID)
    local b = buyingOther
    if not (b and b.auctionID and (not auctionID or auctionID == b.auctionID)) then return end
    buyingOther = nil
    if b.id then Log("B", b.id, 1, b.amount) end
end)
FT.On("AUCTION_HOUSE_AUCTION_CREATED", function()
    local p = postingOther
    postingOther = nil
    if p and p.id then Log("P", p.id, p.qty, p.unit) end
end)
-- Wolf's own buying and posting
FT.On("FT_AH_BOUGHT", function(id, qty, total) Log("B", id, qty, total and qty and total / qty) end)
FT.On("FT_AH_POSTED", function(id, qty, unit) Log("P", id, qty, unit) end)
FT.On("FT_AH_CANCELLED", function(id, qty, unit) Log("C", id, qty or 1, unit) end)

---------------------------------------------------------------------------
-- The watchlist, live: what's listed well under its usual price, said once per item and price
---------------------------------------------------------------------------
local told = {}

-- listed under a price now (the order book of the last search): how many, their cost
function V.Under(id, price)
    local book = FT.Hist.Book(id)
    local n, cost, low = 0, 0, nil
    for _, lv in ipairs(book and book.levels or {}) do
        if lv[1] < price then
            n, cost = n + lv[2], cost + lv[1] * lv[2]
            low = low or lv[1]
        end
    end
    return n, cost, low
end

-- a watched item's deal now: { id, n, cost, low, usual, under }, or nil
function V.WatchDeal(id)
    local usual = Usual(id)
    if not (usual and usual > 0) then return nil end
    local under = math.floor(usual * (1 - WATCH_UNDER))
    local n, cost, low = V.Under(id, under)
    if n == 0 then return nil end
    return { id = id, n = n, cost = cost, low = low, usual = usual, under = under }
end

-- buy what a deal is (stackable: all of them at once; gear: the cheapest)
function V.BuyDeal(id)
    local d = V.WatchDeal(id)
    if not d then
        FT.Print(L["Nothing of it is listed under that price any more."])
        return
    end
    local commodity = FT.Buy.IsCommodity(id)
    FT.Buy.Start(id, commodity and d.n or 1, commodity and d.cost / d.n or d.low)
end

FT.On("FT_LIVE_UPDATED", function(id)
    if not (id and FT.db.watch[id] and FT.ahOpen) or FT.S.watchLive == false then return end
    local d = V.WatchDeal(id)
    if not d or told[id] == d.low then return end
    told[id] = d.low
    local link = FT.ChatLink and FT.ChatLink("buy", L["Buy them"], "", id) or ""
    FT.Print(FT.C("accent", L["Watchlist"]) .. "  " .. string.format(L["%s: %s listed under %s, from %s (%s vs usual)"],
        FT.ItemText(id), FT.Num(d.n), FT.Money(d.under, "short"), FT.Money(d.low, "short"), FT.Pct(d.low / d.usual - 1))
        .. (link ~= "" and ("  " .. link) or ""))
    -- the Wolf network: one line for the guild's and group's Wolf users too
    if FT.Net then FT.Net.Deal(id, d.low, d.low / d.usual - 1) end
end)
FT.On("AUCTION_HOUSE_CLOSED", function() wipe(told) end)

if FT.ChatAction then FT.ChatAction("buy", function(arg) V.BuyDeal(tonumber(arg)) end) end

-- the watched items for the live searches (after what's on screen), the auction house open
function V.LiveWatch(max)
    if FT.S.watchLive == false then return {} end
    local out = {}
    for id in pairs(FT.db.watch or {}) do
        out[#out + 1] = id
        if #out >= (max or 12) then break end
    end
    table.sort(out)
    return out
end
