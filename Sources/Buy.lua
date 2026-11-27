-- Wolf: buying from the order book, at the auction house.
--  * Stackable goods: the server is asked what that many of the cheapest cost right now; you see its exact
--    price (and a warning when it is dearer than the book showed, or changed meanwhile) and confirm.
--  * Gear: the cheapest auction of exactly that version with a buyout (not yours) is found; you confirm it.
-- Nothing is bought without your click on the question that shows the server's price. One purchase at a time;
-- a purchase made in the game's own window (or by another addon) meanwhile makes ours step aside; a purchase
-- the server doesn't answer is dropped after a while.
local ADDON, FT = ...
local L = FT.L

local B = {}
FT.Buy = B

local AH = C_AuctionHouse
-- the game's own functions as they are when we load, called straight (never through a hook: the game allows
-- them only right in your click, and a wrapper around them loses that)
local Game = {}
for _, name in ipairs({ "StartCommoditiesPurchase", "ConfirmCommoditiesPurchase", "CancelCommoditiesPurchase", "PlaceBid" }) do
    Game[name] = AH and AH[name]
end
local WAIT = 15          -- seconds the server has to answer (a quote, a search, a purchase)
local pending            -- the purchase: { kind = "commodity" | "item", itemID, qty, expected, key, ... }
local ourCallAt          -- GetTime() of our own call to the auction house (to tell it from others')

local function Name(id)
    return FT.ItemText(id, 40)
end

local function PriceSort()
    local order = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0
    return { { sortOrder = order, reverseSort = false } }
end

-- Stackable goods are bought by quantity (the cheapest first), gear one auction at a time.
-- nil: not known yet (the game is loading the item) - it is asked for.
function B.IsCommodity(itemID)
    if AH and AH.MakeItemKey and AH.GetItemKeyInfo then
        local ok, info = pcall(AH.GetItemKeyInfo, AH.MakeItemKey(itemID))
        if ok and type(info) == "table" and info.isCommodity ~= nil then return info.isCommodity end
    end
    local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local stack = select(8, GetInfo(itemID))
    if stack then return stack > 1 end
    FT.RequestItem(itemID)
    return nil
end

function B.Possible()
    return FT.ahOpen and AH ~= nil and AH.StartCommoditiesPurchase ~= nil
end

function B.Busy()
    return pending ~= nil
end

local function Done(refresh)
    local p = pending
    pending = nil
    if refresh and p and FT.ahOpen then FT.Scanner.LiveNow(p.itemID) end
end

-- the server has WAIT seconds to answer, or the purchase is dropped (not while the question waits for you)
local function Arm(p)
    p.deadline = GetTime() + WAIT
    C_Timer.After(WAIT + 0.1, function()
        if pending ~= p or p.asking or GetTime() < p.deadline then return end
        if p.confirmed then FT.Print(L["No answer from the server about the purchase: check your bags and mailbox."]) end
        Done(true)
    end)
end

-- the question for this purchase; OK held back a moment when the price just changed
local function Ask(p, text, hold)
    p.asking = true
    FT.UI.Confirm({
        owner = p,
        title = L["Buy"],
        text = text,
        ok = L["Buy"],
        okDelay = hold and 1.2 or nil,
        onOK = function()
            if pending ~= p then return end
            p.asking, p.confirmed = false, true
            -- the first call of your click, nothing around it (the game wants it so)
            if p.kind == "commodity" then
                Game.ConfirmCommoditiesPurchase(p.itemID, p.qty)
            else
                Game.PlaceBid(p.auctionID, p.price)
            end
            Arm(p)
        end,
        onCancel = function()
            if pending ~= p then return end
            p.asking = false
            if p.kind == "commodity" and Game.CancelCommoditiesPurchase then
                pcall(Game.CancelCommoditiesPurchase)
            end
            pending = nil
        end,
    })
end

local function Dearer(p, unit)
    if p.expected and p.expected > 0 and unit and unit > p.expected * 1.05 then
        return "\n\n" .. FT.C("down", string.format(L["Dearer than the order book showed (%s each): some lots were bought meanwhile."],
            FT.Money(p.expected)))
    end
    return ""
end

-- Buy: qty of itemID (gear: one auction); expectedUnit: what the book showed, to warn when it went up
function B.Start(itemID, qty, expectedUnit)
    if not B.Possible() then
        FT.Print(FT.House.Why(L["Talk to an auctioneer to buy."]))
        return false
    end
    if pending then
        FT.Print(pending.asking and L["Answer the question about the purchase first."] or L["A purchase is waiting for the server."])
        return false
    end
    if (FT.Sell and FT.Sell.Busy()) or (FT.Owned and FT.Owned.Busy()) then
        FT.Print(L["Finish the purchase or posting under way first."])
        return false
    end
    if FT.Scanner.AHBusy() then
        FT.Print(L["The game's auction house window is busy buying or selling: finish there first."])
        return false
    end
    local commodity = B.IsCommodity(itemID)
    if commodity == nil then
        FT.Print(L["The item is still loading: try again in a moment."])
        return false
    end
    qty = math.floor(qty or 1)
    if not itemID or qty < 1 then return false end
    -- live searches wait while we talk to the server
    FT.Scanner.otherAt = GetTime()
    local p
    if commodity then
        p = { kind = "commodity", itemID = itemID, qty = qty, expected = expectedUnit }
        pending = p
        Arm(p)
        ourCallAt = GetTime()
        if not pcall(Game.StartCommoditiesPurchase, itemID, qty) then
            pending = nil
            FT.Print(L["The purchase didn't go through."])
            return false
        end
    else
        local S = FT.Scanner
        local key = S.KeyFor(itemID)
        p = { kind = "item", itemID = itemID, qty = 1, expected = expectedUnit, key = key }
        pending = p
        Arm(p)
        S.sending = true
        local ok = pcall(AH.SendSearchQuery, key, PriceSort(), false)
        S.sending = false
        if not ok then
            pending = nil
            FT.Print(L["The purchase didn't go through."])
            return false
        end
    end
    return true
end

---------------------------------------------------------------------------
-- Stackable goods: the server's price, then the purchase
---------------------------------------------------------------------------
FT.On("COMMODITY_PRICE_UPDATED", function(unit, total)
    local p = pending
    if not (p and p.kind == "commodity") or type(total) ~= "number" then return end
    local before = p.total
    -- the same price again after you confirmed: nothing to ask (the purchase goes on)
    if p.confirmed and before == total then return end
    p.unit, p.total = unit, total
    -- a new price after you confirmed: the server asks again
    p.confirmed = false
    if GetMoney() < total then
        FT.Print(string.format(L["Not enough gold: %s needed."], FT.Money(total)))
        pending = nil
        FT.UI.CloseConfirm(p)
        if Game.CancelCommoditiesPurchase then pcall(Game.CancelCommoditiesPurchase) end
        return
    end
    local text = string.format(L["Buy %s x %s for %s?"], FT.Num(p.qty), Name(p.itemID), FT.Money(total)) .. "\n"
        .. string.format(L["%s each - the server's price right now."], FT.Money(unit or total / p.qty))
    local changed = before ~= nil and before ~= total
    if changed then
        text = text .. "\n\n" .. FT.C("down", string.format(L["The price changed: it was %s, now %s."], FT.Money(before), FT.Money(total)))
    else
        text = text .. Dearer(p, unit)
    end
    Ask(p, text, changed)
    -- the server's price holds for a while: when it runs out, the question goes
    if AH.GetQuoteDurationRemaining then
        local ok, left = pcall(AH.GetQuoteDurationRemaining)
        if ok and type(left) == "number" and left > 0 then
            p.quote = (p.quote or 0) + 1
            local quote = p.quote
            C_Timer.After(left, function()
                if pending == p and p.asking and p.quote == quote then
                    FT.Print(L["The server's price ran out: press Buy again."])
                    FT.UI.CloseConfirm(p)
                end
            end)
        end
    end
end)

FT.On("COMMODITY_PRICE_UNAVAILABLE", function()
    local p = pending
    if not (p and p.kind == "commodity") then return end
    pending = nil
    FT.UI.CloseConfirm(p)
    FT.Print(L["The price isn't available any more: the lots changed. Try again."])
    if FT.ahOpen then FT.Scanner.LiveNow(p.itemID) end
end)

FT.On("COMMODITY_PURCHASE_SUCCEEDED", function()
    local p = pending
    if not (p and p.kind == "commodity" and p.confirmed) then return end
    FT.Print(string.format(L["Bought: %s x %s for %s."], FT.Num(p.qty), Name(p.itemID), FT.Money(p.total)))
    FT.Fire("FT_AH_BOUGHT", p.itemID, p.qty, p.total)
    Done(true)
end)

FT.On("COMMODITY_PURCHASE_FAILED", function()
    local p = pending
    if not (p and p.kind == "commodity" and p.confirmed) then return end
    FT.Print(L["The purchase didn't go through."])
    Done(true)
end)

---------------------------------------------------------------------------
-- Gear: the cheapest auction of exactly that version, then the buyout
---------------------------------------------------------------------------
local function SameKey(a, b)
    return type(a) == "table" and type(b) == "table" and a.itemID == b.itemID and (a.itemLevel or 0) == (b.itemLevel or 0)
        and (a.itemSuffix or 0) == (b.itemSuffix or 0) and (a.battlePetSpeciesID or 0) == (b.battlePetSpeciesID or 0)
end

local function OnItemResults(itemKey)
    local p = pending
    if not (p and p.kind == "item" and not p.asking and not p.confirmed) or not SameKey(itemKey, p.key) then return end
    local n = AH.GetNumItemSearchResults and AH.GetNumItemSearchResults(itemKey) or 0
    local best
    for i = 1, n do
        local info = AH.GetItemSearchResultInfo(itemKey, i)
        -- one item with a buyout, not yours: buyoutAmount is its whole price
        if info and info.auctionID and info.buyoutAmount and info.buyoutAmount > 0 and (info.quantity or 1) == 1
            and not info.containsOwnerItem and not info.containsAccountItem
            and (not best or info.buyoutAmount < best.buyoutAmount) then
            best = info
        end
    end
    local full = not AH.HasFullItemSearchResults or AH.HasFullItemSearchResults(itemKey)
    if not best then
        if full then
            FT.Print(L["No auction of it to buy out right now."])
            pending = nil
        end
        return -- more results may come
    end
    p.auctionID, p.price = best.auctionID, best.buyoutAmount
    if GetMoney() < p.price then
        FT.Print(string.format(L["Not enough gold: %s needed."], FT.Money(p.price)))
        pending = nil
        return
    end
    local what = best.itemLink or Name(p.itemID)
    local text = string.format(L["Buy out %s for %s?"], what, FT.Money(p.price)) .. "\n"
        .. L["Its cheapest auction with a buyout right now."] .. Dearer(p, p.price)
    Ask(p, text, false)
end

FT.On("ITEM_SEARCH_RESULTS_UPDATED", OnItemResults)
FT.On("ITEM_SEARCH_RESULTS_ADDED", OnItemResults)

FT.On("AUCTION_HOUSE_PURCHASE_COMPLETED", function(auctionID)
    local p = pending
    if not (p and p.kind == "item" and p.confirmed) then return end
    if auctionID and auctionID ~= p.auctionID then return end
    FT.Print(string.format(L["Bought out: %s for %s."], Name(p.itemID), FT.Money(p.price)))
    FT.Fire("FT_AH_BOUGHT", p.itemID, 1, p.price)
    Done(true)
end)

FT.On("AUCTION_HOUSE_SHOW_ERROR", function()
    local p = pending
    if not (p and p.kind == "item" and p.confirmed) then return end
    FT.Print(L["The purchase didn't go through."])
    Done(true)
end)

---------------------------------------------------------------------------
-- The server too busy for our question; walking away
---------------------------------------------------------------------------
-- the game blocked our purchase: the game's window it is
FT.On("FT_BLOCKED", function(func)
    if not (type(func) == "string" and (func:find("Purchase", 1, true) or func:find("PlaceBid", 1, true))) then return end
    FT.ShowGameAH()
    FT.Print(L["WoW Forever lets only its own auction house window buy: buy there (the order book here shows what it costs)."])
    pending = nil
end)

FT.On("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", function()
    local p = pending
    if not p or p.asking or p.confirmed then return end
    FT.Print(L["The auction house is busy: try again in a few seconds."])
    pending = nil
end)

FT.On("AUCTION_HOUSE_CLOSED", function()
    local p = pending
    if p then
        pending = nil
        FT.UI.CloseConfirm(p)
    end
end)
