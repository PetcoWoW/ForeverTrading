-- ForeverTrading: your auctions. Read from the server at the auction house (when it opens, after you post or
-- cancel, and when you ask), kept for this character so they show away from it too; cancelling one asks first
-- (the item comes back by mail, the deposit is gone). Whether someone undercut you is told by the market's
-- lowest price of the item against yours.
local ADDON, FT = ...
local L = FT.L

local O = {}
FT.Owned = O

local AH = C_AuctionHouse
-- the game's own functions as they are when we load, called straight (never through a hook: the game allows
-- them only right in your click, and a wrapper around them loses that)
local Game = {}
for _, name in ipairs({ "CancelAuction" }) do
    Game[name] = AH and AH[name]
end
local list, readAt   -- this visit's list: { auctionID, itemID, link, qty, unit, bid, timeLeft, seconds, sold }
local cancelling     -- { auctionID, itemID, link, qty, sent, sentAt, said }
local ourCallAt

-- why the auction house said no, in its own words when it gave them (for the chat line)
local function ErrorName(code)
    local E = Enum and Enum.AuctionHouseError
    if type(E) == "table" then
        for name, v in pairs(E) do
            if v == code then return name end
        end
    end
    return code ~= nil and tostring(code) or nil
end

local function Failed(p, why)
    local text = L["The auction wasn't cancelled."]
    local bits = {}
    if p and p.said then bits[#bits + 1] = p.said end
    if why then bits[#bits + 1] = why end
    if #bits > 0 then text = text .. " (" .. table.concat(bits, "; ") .. ")" end
    FT.Print(text)
end

local function Saved()
    FT.db.owned = FT.db.owned or {}
    return FT.db.owned
end

-- your auctions are kept per character and auction house (your faction's under the character, as always)
local function KeyOf(house)
    if not FT.charKey then return nil end
    return (house == "neutral") and (FT.charKey .. "@neutral") or FT.charKey
end
local function MyKey()
    return KeyOf(FT.house)
end

function O.Possible()
    return FT.ahOpen and AH ~= nil and AH.QueryOwnedAuctions ~= nil
end

function O.Busy()
    return cancelling ~= nil
end

-- the list and when it was read (from the last visit when away from the auction house)
function O.List()
    if list and FT.ahOpen then return list, readAt, true end
    local s = MyKey() and Saved()[MyKey()]
    if s then return s.list or {}, s.t, false end
    return {}, nil, false
end

-- At once, before the server's list comes: an auction cancelled goes, one posted comes (the list read after
-- puts it all right).
function O.Remove(auctionID)
    if not (list and auctionID) then return end
    for i = #list, 1, -1 do
        if list[i].auctionID == auctionID then table.remove(list, i) end
    end
    FT.Fire("FT_OWNED_CHANGED")
end

-- a = { auctionID, itemID, link, qty, unit, seconds }: counted from now
function O.Add(a)
    a.at = time()
    list = list or {}
    readAt = readAt or a.at
    table.insert(list, 1, a)
    FT.Fire("FT_OWNED_CHANGED")
end

-- your own lots of an item: unit price -> how many
local function MineOf(itemID)
    local mine = {}
    for _, b in ipairs((O.List())) do
        if b.itemID == itemID and b.unit and not b.sold then
            local u = math.ceil(b.unit)
            mine[u] = (mine[u] or 0) + (b.qty or 1)
        end
    end
    return mine
end

-- How your auction stands against the others' (your own lots left out): { low = the others' lowest, ahead = how
-- many of theirs are cheaper than yours (nil: unknown), sure = from an order book as new as the price } - nil
-- when no price is known
function O.Competition(a)
    if a.sold or not a.unit then return nil end
    local p, t, _, _, gone = FT.Price(a.itemID)
    local mine = MineOf(a.itemID)
    local book = FT.Hist.Book(a.itemID)
    if book and book.levels and #book.levels > 0 and book.source ~= "mastercraft" and (book.t or 0) >= (t or 0) - 600 then
        local ours, low, ahead = math.ceil(a.unit), nil, 0
        for _, lv in ipairs(book.levels) do
            local q = lv[2] - (mine[lv[1]] or 0)
            if q > 0 then
                low = low or lv[1]
                if lv[1] < ours then ahead = ahead + q end
            end
        end
        return { low = low, ahead = ahead, sure = true, t = book.t }
    end
    if p and not gone then
        -- the lowest price may be one of yours: then nobody else is known to be under you
        if mine[math.ceil(p)] then return { low = nil, sure = false, t = t } end
        return { low = p, sure = false, t = t }
    end
    return nil
end

-- the others' lowest price under yours: someone undercut you (nil: you are the cheapest, or no price known);
-- and the competition as above
function O.Undercut(a)
    local c = O.Competition(a)
    if c and c.low and a.unit and c.low < math.ceil(a.unit) then return c.low, c end
    return nil
end

-- seconds an auction has left (the band's least when only that is known), nil when unknown
local BAND_LEAST = { [0] = 0, [1] = 1800, [2] = 7200, [3] = 28800 }
function O.SecondsLeft(a)
    if a.sold then return 0 end
    if a.seconds and a.seconds > 0 then
        local _, readAt = O.List()
        local from = a.at or readAt
        return math.max(0, a.seconds - (from and (time() - from) or 0))
    end
    return a.timeLeft ~= nil and BAND_LEAST[a.timeLeft] or nil
end

local function Hours(sec)
    if sec >= 3600 then return string.format(L["%d h"], math.floor(sec / 3600 + 0.5)) end
    return string.format(L["%d min"], math.max(1, math.floor(sec / 60)))
end

-- Undercut: wait, or take it off and post it again? { kind = "wait" / "repost" / "low" / "check", target (the price
-- to post again at), text }. It weighs what is listed under yours against what sells in the time yours has left
-- (FT.Sales), and a price posted again far under the fair or the vendor's price.
function O.Advice(a)
    local low, c = O.Undercut(a)
    if not low then return nil end
    local target = low - 1
    local s = FT.An.Stats(a.itemID)
    local vendor = FT.SellPriceKnown(a.itemID)
    if (vendor and target * (1 - FT.Cut()) < vendor) or (s.fair and target < s.fair * 0.8) then
        return { kind = "low", target = target, text = string.format(L["Under the lowest would be %s: far under its fair price (or the vendor's). Rather wait for the cheap lots to go, or let yours run out."], FT.Money(target, "short")) }
    end
    local r, left = s.sales, O.SecondsLeft(a)
    if c.sure and r and r.hours >= 3 and left then
        local willSell = r.perDay * left / 86400
        local ahead = string.format(L["%s cheaper than yours"], FT.Num(c.ahead))
        if willSell >= c.ahead + a.qty then
            return { kind = "wait", target = target, text = string.format(L["%s; at %s, about %s sell in the %s yours has left - yours too, likely. Waiting costs nothing; posting again costs a deposit."],
                ahead, FT.Sales.PerDayText(r), FT.Num(math.floor(willSell)), Hours(left)) }
        end
        return { kind = "repost", target = target, text = string.format(L["%s; at %s, only about %s sell in the %s yours has left - yours likely won't. Take it off and post it again at %s (the deposit is lost, a new one is paid)."],
            ahead, FT.Sales.PerDayText(r), FT.Num(math.floor(willSell)), Hours(left), FT.Money(target, "short")) }
    end
    if c.sure then
        return { kind = "check", target = target, text = string.format(L["%s cheaper than yours. To sell first: take it off and post it again at %s (the deposit is lost) - or wait if they are few and go fast."],
            FT.Num(c.ahead), FT.Money(target, "short")) }
    end
    return { kind = "check", target = target, text = L["Check the prices first: how many are listed under yours, now."] }
end

---------------------------------------------------------------------------
-- Taken off to post again: when the item is back in the bags, the Sell page has it first
---------------------------------------------------------------------------
O.repost = {} -- itemID -> { at, target }

local GetCount = (C_Item and C_Item.GetItemCount) or GetItemCount

function O.CancelToRepost(a)
    local advice = O.Advice(a)
    local ok = O.Cancel(a)
    if ok then
        O.repost[a.itemID] = { at = time(), target = advice and advice.target, pending = a.auctionID,
            count = GetCount and GetCount(a.itemID) or 0 }
    end
    return ok
end

-- the auction taken off: the item is on its way by mail
local function TakenOff(itemID)
    local w = itemID and O.repost[itemID]
    if not (w and w.pending) then return end
    w.pending = nil
    FT.Print(L["Take it from your mailbox: back in your bags, the Sell page has it first, at a copper under the lowest."])
end

-- posted again (or given up after a while): no longer waited for
function O.Reposted(itemID)
    if itemID and O.repost[itemID] then
        O.repost[itemID] = nil
        FT.Fire("FT_OWNED_CHANGED")
    end
end

function O.Waiting(itemID)
    local w = itemID and O.repost[itemID]
    if w and time() - w.at > 6 * 3600 then
        O.repost[itemID] = nil
        return nil
    end
    return w
end

-- the item came back from the mail: said once
FT.On("BAG_UPDATE_DELAYED", function()
    for itemID, w in pairs(O.repost) do
        if not w.pending and not w.back and GetCount and GetCount(itemID) > (w.count or 0) then
            w.back = true
            FT.Print(string.format(L["%s is back in your bags: the Sell page has it first, at a copper under the lowest."],
                FT.ItemText(itemID, 40)))
            FT.Fire("FT_OWNED_CHANGED")
        end
    end
end)

---------------------------------------------------------------------------
-- Undercut: said in chat when it is seen (once per auction and price), at the auction house
---------------------------------------------------------------------------
local told = {} -- auctionID -> the lowest price it was told for

local function TellUndercuts()
    if FT.S.undercutAlert == false or not list then return end
    local news = {}
    for _, a in ipairs(list) do
        local low = (not a.sold) and O.Undercut(a)
        if low and a.auctionID and told[a.auctionID] ~= low then
            told[a.auctionID] = low
            news[#news + 1] = a
        end
    end
    if #news == 0 then return end
    for i = 1, math.min(#news, 4) do
        local a = news[i]
        local low = O.Undercut(a)
        FT.Print(string.format(L["Undercut: %s - yours %s, now %s."], a.link or FT.ItemText(a.itemID, 40),
            FT.Money(math.ceil(a.unit), "short"), FT.Money(low, "short")))
    end
    if #news > 4 then FT.Print(string.format(L["...and %d more: Sell > My auctions."], #news - 4)) end
end

local function SoonTell() FT.Debounce("undercuts", 2, TellUndercuts) end
FT.On("FT_OWNED_CHANGED", SoonTell)
FT.On("FT_SCAN_DONE", SoonTell)
FT.On("FT_LIVE_UPDATED", function(itemID)
    if not list then return end
    for _, a in ipairs(list) do
        if a.itemID == itemID then return SoonTell() end
    end
end)

local function Sorts()
    local order = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Name or 1
    return { { sortOrder = order, reverseSort = false } }
end

-- read them from the server (at the auction house)
-- read them from the server (at the auction house); tried again a few times when the server is busy
local tries = 0
function O.Query(again)
    if not O.Possible() then return false end
    if not again then tries = 0 end
    tries = tries + 1
    local ready = not AH.IsThrottledMessageSystemReady or AH.IsThrottledMessageSystemReady()
    local ok = ready and pcall(AH.QueryOwnedAuctions, Sorts())
    FT.Debug("owned: asked the server, ready", ready, "ok", ok, "try", tries)
    local asked = GetTime()
    O.askedAt = asked
    if tries < 4 then
        C_Timer.After(ready and 4 or 1, function()
            -- no answer to this ask yet: once more
            if O.askedAt == asked and (not readAt or readAt < time() - 5) and FT.ahOpen then O.Query(true) end
        end)
    end
    return ok and true or false
end

local function IsCommodity(itemKey)
    if not (AH.GetItemKeyInfo and itemKey) then return false end
    local ok, info = pcall(AH.GetItemKeyInfo, itemKey)
    return ok and type(info) == "table" and info.isCommodity == true
end

FT.On("OWNED_AUCTIONS_UPDATED", function()
    -- read by the game's own window while the other house's prices are on: not ours to keep
    if not FT.ahOpen then return end
    if not (AH and AH.GetNumOwnedAuctions and AH.GetOwnedAuctionInfo) then return end
    local out = {}
    local sold = Enum and Enum.AuctionStatus and Enum.AuctionStatus.Sold or 1
    for i = 1, AH.GetNumOwnedAuctions() or 0 do
        local a = AH.GetOwnedAuctionInfo(i)
        if a and a.itemKey and a.itemKey.itemID then
            local qty = a.quantity or 1
            -- a stackable good's buyout is per unit; anything else's is for the auction
            local unit = a.buyoutAmount
            if unit and not IsCommodity(a.itemKey) and qty > 1 then unit = unit / qty end
            out[#out + 1] = {
                auctionID = a.auctionID, itemID = a.itemKey.itemID, link = a.itemLink, qty = qty, unit = unit,
                bid = a.bidAmount, timeLeft = a.timeLeft, seconds = a.timeLeftSeconds, sold = a.status == sold,
            }
        end
    end
    list, readAt = out, time()
    FT.Debug("owned: the server sent", #out, "auctions")
    if MyKey() then Saved()[MyKey()] = { t = readAt, list = out } end
    FT.Fire("FT_OWNED_CHANGED")
    -- the auction you wanted to cancel while the list was being read: its question now
    local w = O.wanted
    O.wanted = nil
    if w and GetTime() - w.at < 15 then
        for _, a in ipairs(out) do
            if a.auctionID == w.auctionID then
                O.Cancel(a)
                return
            end
        end
        FT.Print(L["That auction isn't up any more (sold or ended)."])
    end
end)

-- fresh after posting, and a few seconds after going online at the auction house (it opened, or its own prices
-- are on again); offline: the list of the house whose prices are on, as last read
FT.On("AUCTION_HOUSE_AUCTION_CREATED", function() C_Timer.After(0.5, function() if FT.ahOpen then O.Query() end end) end)
FT.On("FT_AH_CHANGED", function()
    if FT.ahOpen then
        C_Timer.After(3, function() if FT.ahOpen then O.Query() end end)
    elseif list then
        list, readAt = nil, nil
        FT.Fire("FT_OWNED_CHANGED")
    end
end)
FT.On("AUCTION_HOUSE_CLOSED", function()
    list = nil
    FT.Fire("FT_OWNED_CHANGED")
end)

-- the other house's prices on: its list as last read (read again when online there)
FT.On("FT_HOUSE_CHANGED", function()
    list, readAt = nil, nil
    FT.Fire("FT_OWNED_CHANGED")
end)

-- the auction house here was taken for `wrong` (put right on the chip): the list read here goes from there
function O.Misfiled(wrong)
    local key = KeyOf(wrong)
    local s = key and Saved()[key]
    if s and readAt and s.t == readAt then Saved()[key] = nil end
end

---------------------------------------------------------------------------
-- Cancelling
---------------------------------------------------------------------------
-- the game lets only its own window cancel (it blocked ours): there it is, with where to click
local function InTheGamesWindow()
    FT.ShowGameAH()
    FT.Print(L["WoW Forever lets only its own auction house window cancel auctions: open its Auctions tab and cancel there."])
end

function O.Blocked()
    return O.gameOnly == true
end

function O.Cancel(a)
    if O.gameOnly then
        InTheGamesWindow()
        return false
    end
    if not O.Possible() or not Game.CancelAuction then
        FT.Print(FT.House.Why(L["Talk to an auctioneer to cancel."]))
        return false
    end
    if cancelling or (FT.Buy and FT.Buy.Busy()) or (FT.Sell and FT.Sell.Busy()) then
        FT.Print(L["Finish the purchase or posting under way first."])
        return false
    end
    if a.sold then return false end
    -- the list must be the server's of this visit (the one kept from last time may be out of date): it is
    -- read, and the question comes by itself when it is here
    local _, _, live = O.List()
    -- (one just posted shows before the server numbers it: its number comes with the list)
    if not live or not a.auctionID then
        O.wanted = a.auctionID and { auctionID = a.auctionID, at = GetTime() } or nil
        O.Query()
        FT.Print(L["Reading your auctions from the auction house: the question comes in a moment."])
        return false
    end
    local p = { auctionID = a.auctionID, itemID = a.itemID, link = a.link, qty = a.qty }
    local text = string.format(L["Take %s x %s off the auction house?"], FT.Num(a.qty), a.link or FT.ItemText(a.itemID, 40)) .. "\n"
        .. L["It comes back by mail; the deposit isn't returned."]
    if AH.GetCancelCost then
        local ok, cost = pcall(AH.GetCancelCost, a.auctionID)
        if ok and type(cost) == "number" and cost > 0 then
            text = text .. "\n" .. string.format(L["Cancelling costs %s."], FT.Money(cost))
            if GetMoney() < cost then
                FT.Print(string.format(L["Not enough gold: %s needed."], FT.Money(cost)))
                return false
            end
        end
    end
    cancelling = p
    FT.UI.Confirm({
        owner = p,
        title = L["Cancel the auction"],
        text = text,
        ok = L["Cancel the auction"],
        cancel = L["Keep it"],
        okStyle = "down",
        onOK = function()
            if cancelling ~= p then return end
            p.sent, p.sentAt = true, GetTime()
            -- the very first thing in your click, nothing around it (the game wants it so)
            Game.CancelAuction(p.auctionID)
            FT.Debug("owned: CancelAuction called, auction", p.auctionID)
            -- no word in a while: the list is read again anyway
            C_Timer.After(10, function()
                if cancelling == p then
                    cancelling = nil
                    O.Query()
                end
            end)
        end,
        onCancel = function()
            if cancelling == p and not p.sent then cancelling = nil end
            -- not taken off: not waited for to post again
            local w = O.repost[p.itemID]
            if w and w.pending == p.auctionID and not p.sent then O.repost[p.itemID] = nil end
        end,
    })
    return true
end

-- the game blocked our cancel: from now on (this session) the game's window does it
FT.On("FT_BLOCKED", function(func)
    if not (type(func) == "string" and func:find("CancelAuction", 1, true)) then return end
    O.gameOnly = true
    if cancelling then
        cancelling = nil
        InTheGamesWindow()
    end
    FT.Fire("FT_OWNED_CHANGED")
end)

FT.On("AUCTION_CANCELED", function(auctionID)
    FT.Debug("owned: event AUCTION_CANCELED", tostring(auctionID))
    local p = cancelling
    if p and p.sent and (auctionID == nil or auctionID == p.auctionID) then
        FT.Print(string.format(L["Taken off: %s x %s (it comes by mail)."], FT.Num(p.qty), p.link or FT.ItemText(p.itemID, 40)))
        cancelling = nil
        O.Remove(p.auctionID)
        TakenOff(p.itemID)
    elseif auctionID then
        O.Remove(auctionID)
    end
    C_Timer.After(0.5, O.Query)
end)

FT.On("AUCTION_HOUSE_SHOW_ERROR", function(code)
    local p = cancelling
    if not (p and p.sent) then return end
    cancelling = nil
    -- the game's own red message usually comes in the same moment: said with it
    C_Timer.After(0.3, function() Failed(p, ErrorName(code)) end)
    C_Timer.After(0.5, O.Query)
end)

-- the game's own line in chat: "Auction cancelled." - when the event above doesn't come
FT.On("CHAT_MSG_SYSTEM", function(message)
    local p = cancelling
    if type(message) ~= "string" or not (p and p.sent) then return end
    FT.Debug("owned: system line", message)
    if ERR_AUCTION_REMOVED and message == ERR_AUCTION_REMOVED then
        FT.Print(string.format(L["Taken off: %s x %s (it comes by mail)."], FT.Num(p.qty), p.link or FT.ItemText(p.itemID, 40)))
        cancelling = nil
        O.Remove(p.auctionID)
        TakenOff(p.itemID)
        C_Timer.After(0.5, O.Query)
    end
end)

-- the game's red message right after our cancel (its reason)
FT.On("UI_ERROR_MESSAGE", function(_, message)
    local p = cancelling
    if p and p.sent and p.sentAt and GetTime() - p.sentAt < 3 and type(message) == "string" then p.said = message end
end)

FT.On("AUCTION_HOUSE_CLOSED", function()
    local p = cancelling
    if p then
        cancelling = nil
        FT.UI.CloseConfirm(p)
    end
end)
