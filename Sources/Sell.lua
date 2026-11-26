-- Wolf: posting auctions from your bags, at the auction house. The Selling page works out the price,
-- the deposit and the cut; here the posting itself: one question with everything (and the warnings), then the
-- post - stackable goods by quantity (all your stacks together), anything else one item at a time. When the
-- server warns about the price it asks once more. Nothing is posted without your click; the item must still be
-- the same one in the same place when you click; one posting (or purchase) at a time; a posting made in the
-- game's own window meanwhile makes ours step aside.
local ADDON, FT = ...
local L = FT.L

local Sell = {}
FT.Sell = Sell

local AH = C_AuctionHouse
-- the game's own functions as they are when we load, called straight (never through a hook: the game allows
-- them only right in your click, and a wrapper around them loses that)
local Game = {}
for _, name in ipairs({ "PostCommodity", "PostItem", "ConfirmPostCommodity", "ConfirmPostItem", "CancelSell" }) do
    Game[name] = AH and AH[name]
end
local WAIT = 15
local pending   -- { kind, itemID, loc, guid, qty, unit, duration, deposit, link, warnings, severe, posted, asking }
local ourCallAt -- GetTime() of our own call (to tell it from others')

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
local ItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount

local function Changed()
    FT.Fire("FT_SELL_STATE")
end

function Sell.Possible()
    return FT.ahOpen and AH ~= nil and AH.PostCommodity ~= nil and AH.PostItem ~= nil
end

function Sell.Busy()
    return pending ~= nil
end

-- a price in whole copper (at least 1)
function Sell.Price(c)
    if not c then return nil end
    return math.max(1, math.floor(c))
end

-- the bag slot as the game wants it (nil: nothing there)
function Sell.Location(bag, slot)
    if not (ItemLocation and ItemLocation.CreateFromBagAndSlot and bag and slot) then return nil end
    local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
    if C_Item and C_Item.DoesItemExist and not C_Item.DoesItemExist(loc) then return nil end
    return loc
end

-- "commodity" (sold by quantity, all stacks together) / "item" (one auction per item) / nil (the auction house
-- won't take it, or the game can't tell yet)
function Sell.Kind(loc)
    if not (AH and AH.GetItemCommodityStatus and loc) then return nil end
    local ok, status = pcall(AH.GetItemCommodityStatus, loc)
    if not ok or not status then return nil end
    local E = Enum and Enum.ItemCommodityStatus
    local item, commodity = E and E.Item or 1, E and E.Commodity or 2
    if status == commodity then return "commodity" end
    if status == item then return "item" end
    return nil
end

function Sell.Valid(loc)
    if not (AH and AH.IsSellItemValid and loc) then return false end
    local ok, valid = pcall(AH.IsSellItemValid, loc, false)
    return ok and valid and true or false
end

-- the deposit the auction house keeps (and gives back when it sells)
function Sell.Deposit(kind, itemID, loc, duration, qty)
    if not AH then return nil end
    local ok, d
    if kind == "commodity" and AH.CalculateCommodityDeposit then
        ok, d = pcall(AH.CalculateCommodityDeposit, itemID, duration, qty)
    elseif AH.CalculateItemDeposit and loc then
        ok, d = pcall(AH.CalculateItemDeposit, loc, duration, qty)
    end
    return ok and type(d) == "number" and d or nil
end

-- How long an auction runs: short, medium, long (the game's 1, 2, 3). WoW Forever: 2, 8 and 24 hours -
-- Auctionator, when it is there, knows this server's own.
local HOURS = { 2, 8, 24 }
function Sell.Hours(i)
    local d = Auctionator and Auctionator.Constants and Auctionator.Constants.Durations
    if type(d) == "table" then
        local v = (i == 1 and d.Short) or (i == 2 and d.Medium) or (i == 3 and d.Long)
        if type(v) == "number" then return v end
    end
    return HOURS[i] or HOURS[2]
end

-- the whole posting in words (for the question), with its warnings
function Sell.Text(p)
    local total = p.unit * p.qty
    local cut = math.floor(total * FT.Cut())
    local what = p.link or FT.ItemText(p.itemID, 40)
    local lines = {
        string.format(L["Post %s x %s at %s each?"], FT.Num(p.qty), what, FT.Money(p.unit)),
        string.format(L["For all: %s. For %d hours."], FT.Money(total), Sell.Hours(p.duration)),
        string.format(L["Deposit %s (back when it sells), the auction house's cut: %s."], p.deposit and FT.Money(p.deposit) or "—",
            FT.Money(cut)),
        string.format(L["You get %s when it all sells."], FT.Money(total - cut)),
    }
    if p.warnings and #p.warnings > 0 then
        lines[#lines + 1] = ""
        for _, w in ipairs(p.warnings) do lines[#lines + 1] = w end
    end
    return table.concat(lines, "\n")
end

-- the item is still the same one in the same place (bags can change while the question waits)
local function Still(p)
    local loc = p.loc
    if not (loc and C_Item and C_Item.DoesItemExist and C_Item.DoesItemExist(loc)) then return false end
    if C_Item.GetItemID and C_Item.GetItemID(loc) ~= p.itemID then return false end
    -- plain calls (the item is there): nothing wrapped in your click before the posting itself
    if p.guid and C_Item.GetItemGUID and C_Item.GetItemGUID(loc) ~= p.guid then return false end
    if p.kind == "commodity" and ItemCount then
        local n = ItemCount(p.itemID, false)
        if n and n < p.qty then return false end
    end
    return true
end

local function Done(refresh)
    local p = pending
    pending = nil
    Changed()
    if refresh and p and FT.ahOpen then FT.Scanner.LiveNow(p.itemID) end
end

-- the server has WAIT seconds to answer the posting, or it is dropped (not while a question waits for you)
local function Arm(p)
    p.deadline = GetTime() + WAIT
    C_Timer.After(WAIT + 0.1, function()
        if pending ~= p or p.asking or GetTime() < p.deadline then return end
        if p.posted then FT.Print(L["No answer from the server about the posting: look in the auction house window."]) end
        Done(true)
    end)
end

-- true when the auction house wants the posting confirmed (a second word) before it is made
local function Call(p, confirm)
    ourCallAt = GetTime()
    -- one item per auction is posted at its own price (only commodities go by quantity)
    if p.kind == "commodity" then
        if confirm then return Game.ConfirmPostCommodity(p.loc, p.duration, p.qty, p.unit) end
        return Game.PostCommodity(p.loc, p.duration, p.qty, p.unit)
    end
    if confirm then return Game.ConfirmPostItem(p.loc, p.duration, 1, nil, p.unit) end
    return Game.PostItem(p.loc, p.duration, 1, nil, p.unit)
end

local function Ask(p, text, okLabel, warn)
    p.asking = true
    FT.UI.Confirm({
        owner = p,
        title = L["Post an auction"],
        text = text,
        ok = okLabel,
        okStyle = warn and "down" or "primary",
        okDelay = (warn or p.severe) and 1.2 or nil,
        onOK = function()
            if pending ~= p then return end
            p.asking = false
            if not Still(p) then
                FT.Print(L["Your bags changed: the posting is cancelled. Check it and press Post again."])
                Done(false)
                return
            end
            p.posted, p.sentAt = true, GetTime()
            -- the first call of your click, nothing around it (the game wants it so)
            local second = Call(p, warn)
            FT.Debug("sell: called", warn and "Confirm" or "Post", p.kind, p.duration, p.qty, p.unit, "- the game answered", tostring(second))
            FT.Scanner.otherAt = GetTime() -- live searches wait
            Arm(p)
            if second and not warn then
                -- the auction house asks to confirm the posting: once more, then it is made
                p.posted, p.warned = false, true
                Ask(p, FT.C("accent", L["The auction house asks to confirm the posting."]) .. "\n\n" .. Sell.Text(p), L["Post"], true)
            end
        end,
        onCancel = function()
            if pending ~= p or p.posted then return end
            -- the server holds a warned posting: it lets go of it
            if p.warned and Game.CancelSell then pcall(Game.CancelSell) end
            pending = nil
            Changed()
        end,
    })
end

-- p = { kind, itemID, loc, guid, qty, unit, duration, deposit, link, warnings, severe }: asks, then posts
function Sell.Post(p)
    if not Sell.Possible() then
        FT.Print(FT.House.Why(L["Talk to an auctioneer to sell."]))
        return false
    end
    if pending or (FT.Buy and FT.Buy.Busy()) or (FT.Owned and FT.Owned.Busy()) then
        FT.Print(L["Finish the purchase or posting under way first."])
        return false
    end
    if FT.Scanner.AHBusy() then
        FT.Print(L["The game's auction house window is busy buying or selling: finish there first."])
        return false
    end
    if not (p.loc and p.kind and p.qty and p.qty > 0 and p.unit and p.unit > 0) then return false end
    if p.kind ~= "commodity" then p.qty = 1 end
    p.unit = Sell.Price(p.unit)
    if p.deposit and GetMoney() < p.deposit then
        FT.Print(string.format(L["Not enough gold for the deposit: %s needed."], FT.Money(p.deposit)))
        return false
    end
    local text = Sell.Text(p)
    pending = p
    Changed()
    Ask(p, text, L["Post"], false)
    FT.Debug("sell: question shown")
    return true
end

---------------------------------------------------------------------------
-- The server's answers
---------------------------------------------------------------------------
-- a price far from the usual one: the server asks for a second word
FT.On("AUCTION_HOUSE_POST_WARNING", function()
    FT.Debug("sell: event POST_WARNING")
    local p = pending
    if not (p and p.posted and not p.warned) then return end
    p.warned, p.posted = true, false
    Ask(p, FT.C("down", L["The auction house warns: this price is far from the usual one. Post anyway?"]) .. "\n\n" .. Sell.Text(p),
        L["Post anyway"], true)
end)

-- posted: said in chat, and in My auctions at once (the server's list follows)
local function Posted(p, auctionID)
    FT.Print(string.format(L["Posted: %s x %s at %s each."], FT.Num(p.qty), p.link or FT.ItemText(p.itemID, 40), FT.Money(p.unit)))
    if FT.Owned then
        FT.Owned.Add({ auctionID = auctionID, itemID = p.itemID, link = p.link, qty = p.qty, unit = p.unit,
            seconds = Sell.Hours(p.duration) * 3600 })
        -- taken off to post again: posted again
        FT.Owned.Reposted(p.itemID)
    end
    -- the deposit, for the deals journal
    if FT.Journal then FT.Journal.Posted(p.itemID, p.qty, p.deposit) end
    Done(true)
end

FT.On("AUCTION_HOUSE_AUCTION_CREATED", function(auctionID)
    FT.Debug("sell: event AUCTION_CREATED")
    local p = pending
    if not (p and p.posted) then return end
    Posted(p, auctionID)
end)

FT.On("AUCTION_HOUSE_SHOW_ERROR", function(code)
    FT.Debug("ah: event SHOW_ERROR", tostring(code), ErrorName(code))
    local p = pending
    if not (p and p.posted) then return end
    Done(true)
    -- the game's own red message usually comes in the same moment: said with it
    C_Timer.After(0.3, function()
        local bits = {}
        if p.said then bits[#bits + 1] = p.said end
        local name = ErrorName(code)
        if name then bits[#bits + 1] = name end
        FT.Print(L["The posting didn't go through: check the auction house window."]
            .. (#bits > 0 and (" (" .. table.concat(bits, "; ") .. ")") or ""))
    end)
end)

-- the game's own line in chat: "Auction created." - when the event above doesn't come
FT.On("CHAT_MSG_SYSTEM", function(message)
    local p = pending
    if type(message) ~= "string" or not (p and p.posted) then return end
    FT.Debug("sell: system line", message)
    if ERR_AUCTION_STARTED and message == ERR_AUCTION_STARTED then Posted(p, nil) end
end)

-- the game's red message right after our posting (its reason)
FT.On("UI_ERROR_MESSAGE", function(_, message)
    FT.Debug("ah: red message", tostring(message))
    local p = pending
    if p and p.posted and p.sentAt and GetTime() - p.sentAt < 3 and type(message) == "string" then p.said = message end
end)

-- the game blocked our posting: the game's window it is
FT.On("FT_BLOCKED", function(func)
    if not (type(func) == "string" and (func:find("Post", 1, true))) then return end
    Sell.gameOnly = true
    FT.ShowGameAH()
    FT.Print(L["WoW Forever lets only its own auction house window post auctions: use its Sell tab (the prices and warnings here still help)."])
    if pending then Done(false) end
end)

-- bags changed while the question waits: if it isn't the same item any more, the question goes
FT.On("BAG_UPDATE_DELAYED", function()
    local p = pending
    if p and p.asking and not Still(p) then
        FT.Print(L["Your bags changed: the posting is cancelled. Check it and press Post again."])
        FT.UI.CloseConfirm(p)
    end
end)

FT.On("AUCTION_HOUSE_CLOSED", function()
    local p = pending
    if p then
        pending = nil
        FT.UI.CloseConfirm(p)
        Changed()
    end
end)
