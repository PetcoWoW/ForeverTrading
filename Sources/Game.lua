-- ForeverTrading: what we read from the game ourselves, so it also works without Mastercraft:
-- the recipes of your profession windows, your bags and bank, and what merchants charge.
local ADDON, FT = ...

local G = {}
FT.Game = G

---------------------------------------------------------------------------
-- Professions (English key <- the game's name), to merge Mastercraft's names with ours
---------------------------------------------------------------------------
local PROF_EN = {
    ["Alchemy"] = "Alchemy", ["Алхимия"] = "Alchemy", ["Alchimie"] = "Alchemy", ["Alquimia"] = "Alchemy",
    ["Blacksmithing"] = "Blacksmithing", ["Кузнечное дело"] = "Blacksmithing", ["Schmiedekunst"] = "Blacksmithing",
    ["Enchanting"] = "Enchanting", ["Наложение чар"] = "Enchanting", ["Verzauberkunst"] = "Enchanting",
    ["Engineering"] = "Engineering", ["Инженерное дело"] = "Engineering", ["Ingenieurskunst"] = "Engineering",
    ["Leatherworking"] = "Leatherworking", ["Кожевничество"] = "Leatherworking", ["Lederverarbeitung"] = "Leatherworking",
    ["Tailoring"] = "Tailoring", ["Портняжное дело"] = "Tailoring", ["Schneiderei"] = "Tailoring",
    ["Cooking"] = "Cooking", ["Кулинария"] = "Cooking", ["Kochkunst"] = "Cooking",
    ["First Aid"] = "First Aid", ["Первая помощь"] = "First Aid", ["Erste Hilfe"] = "First Aid",
    ["Mining"] = "Mining", ["Горное дело"] = "Mining", ["Bergbau"] = "Mining",
    ["Smelting"] = "Mining", ["Выплавка металлов"] = "Mining", ["Verhüttung"] = "Mining",
    ["Jewelcrafting"] = "Jewelcrafting", ["Ювелирное дело"] = "Jewelcrafting",
    ["Poisons"] = "Poisons", ["Яды"] = "Poisons",
}
function FT.ProfKey(name)
    return name and (PROF_EN[name] or name) or "?"
end

local function ItemID(link)
    return link and tonumber(link:match("item:(%d+)"))
end

-- the player really has this profession (a linked window of another player must not be saved as ours)
local function HasSkill(name)
    if not (name and GetNumSkillLines and GetSkillLineInfo) then return true end
    local collapsed = false
    for i = 1, GetNumSkillLines() do
        local skillName, isHeader, isExpanded = GetSkillLineInfo(i)
        if isHeader and not isExpanded then collapsed = true end
        if not isHeader and skillName == name then return true end
    end
    -- a collapsed header (Skills tab) hides its lines from the game's list: then we can't tell
    return collapsed
end

local function Store(prof, list)
    if not (FT.charKey and prof and list and #list > 0) then return end
    FT.db.recipes[FT.charKey] = FT.db.recipes[FT.charKey] or {}
    FT.db.recipes[FT.charKey][FT.ProfKey(prof)] = { scanned = time(), list = list, name = prof }
    FT.Debounce("recipesChanged", 0.5, function() FT.Fire("FT_RECIPES_CHANGED") end)
end

local function ScanTradeClassic()
    if not (GetTradeSkillLine and GetNumTradeSkills) then return end
    if IsTradeSkillLinked and IsTradeSkillLinked() then return end
    local prof = GetTradeSkillLine()
    if not prof or prof == "UNKNOWN" or not HasSkill(prof) then return end
    local list = {}
    for i = 1, GetNumTradeSkills() do
        local name, kind = GetTradeSkillInfo(i)
        if name and kind ~= "header" and kind ~= "subheader" then
            local r = { name = name, icon = GetTradeSkillIcon and GetTradeSkillIcon(i), reagents = {},
                output = ItemID(GetTradeSkillItemLink(i)), outputQty = 1, diff = kind }
            if GetTradeSkillNumMade then
                local lo, hi = GetTradeSkillNumMade(i)
                r.outputQty = math.max(1, ((lo or 1) + (hi or lo or 1)) / 2)
            end
            if GetTradeSkillCooldown then r.cooldown = GetTradeSkillCooldown(i) end
            for j = 1, GetTradeSkillNumReagents(i) do
                local _, _, qty = GetTradeSkillReagentInfo(i, j)
                local id = ItemID(GetTradeSkillReagentItemLink(i, j))
                if id then
                    r.reagents[#r.reagents + 1] = { itemID = id, qty = qty or 1 }
                else
                    r.incomplete = true -- not loaded yet: read the window again in a moment
                    G.retry = true
                end
            end
            list[#list + 1] = r
        end
    end
    Store(prof, list)
end

local function ScanCraftClassic()
    if not (GetCraftDisplaySkillLine and GetNumCrafts) then return end
    local prof = GetCraftDisplaySkillLine()
    if not prof or not HasSkill(prof) then return end
    local list = {}
    for i = 1, GetNumCrafts() do
        local name, _, kind = GetCraftInfo(i)
        if name and kind ~= "header" then
            local link = GetCraftItemLink and GetCraftItemLink(i)
            local r = { name = name, icon = GetCraftIcon and GetCraftIcon(i), reagents = {}, output = ItemID(link),
                outputQty = 1, diff = kind }
            for j = 1, GetCraftNumReagents(i) do
                local _, _, qty = GetCraftReagentInfo(i, j)
                local id = ItemID(GetCraftReagentItemLink(i, j))
                if id then
                    r.reagents[#r.reagents + 1] = { itemID = id, qty = qty or 1 }
                else
                    r.incomplete = true
                    G.retry = true
                end
            end
            list[#list + 1] = r
        end
    end
    Store(prof, list)
end

local function ScanTradeModern()
    local T = C_TradeSkillUI
    if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo) then return false end
    if (T.IsTradeSkillLinked and T.IsTradeSkillLinked()) or (T.IsTradeSkillGuild and T.IsTradeSkillGuild()) then return true end
    local base = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
    local prof = base and base.professionName
    if not prof or prof == "" then return false end -- not this client's window: the classic API reads it
    local list = {}
    for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
        local info = T.GetRecipeInfo(id)
        if info and info.learned then
            local r = { id = id, name = info.name, icon = info.icon, reagents = {}, outputQty = 1 }
            local s = T.GetRecipeSchematic and T.GetRecipeSchematic(id, false)
            if s then
                r.output = s.outputItemID
                if s.quantityMin and s.quantityMin > 0 then
                    r.outputQty = ((s.quantityMin or 1) + (s.quantityMax or s.quantityMin or 1)) / 2
                end
                for _, slot in ipairs(s.reagentSlotSchematics or {}) do
                    local reagent = slot.reagents and slot.reagents[1]
                    if reagent and reagent.itemID then
                        r.reagents[#r.reagents + 1] = { itemID = reagent.itemID, qty = slot.quantityRequired or 1 }
                    end
                end
            end
            list[#list + 1] = r
        end
    end
    if #list == 0 then return false end
    Store(prof, list)
    return true
end

local function ScanTrade()
    G.retry = false
    local ok, handled = pcall(ScanTradeModern)
    if not (ok and handled) then pcall(ScanTradeClassic) end
    if G.retry then FT.Debounce("tradeRetry", 2, ScanTrade) end
end

local function ScanCraft()
    G.retry = false
    pcall(ScanCraftClassic)
    if G.retry then FT.Debounce("craftRetry", 2, ScanCraft) end
end

FT.On("TRADE_SKILL_SHOW", function() C_Timer.After(0.5, ScanTrade) end)
FT.On("TRADE_SKILL_UPDATE", function() FT.Debounce("tradeScan", 0.6, ScanTrade) end)
FT.On("TRADE_SKILL_LIST_UPDATE", function() FT.Debounce("tradeScan", 0.6, ScanTrade) end)
FT.On("CRAFT_SHOW", function() C_Timer.After(0.5, ScanCraft) end)
FT.On("CRAFT_UPDATE", function() FT.Debounce("craftScan", 0.6, ScanCraft) end)

---------------------------------------------------------------------------
-- Bags and bank
---------------------------------------------------------------------------
local Container = C_Container
local NumSlots = (Container and Container.GetContainerNumSlots) or GetContainerNumSlots

local function SlotInfo(bag, slot)
    if Container and Container.GetContainerItemInfo then
        local info = Container.GetContainerItemInfo(bag, slot)
        if info then return info.itemID, info.stackCount or 1, info.isBound end
        return nil
    end
    if GetContainerItemInfo then
        local _, count, _, _, _, _, link, _, _, itemID = GetContainerItemInfo(bag, slot)
        return itemID or ItemID(link), count or 1, nil
    end
end

local function IsBound(bag, slot, known)
    if known ~= nil then return known end
    if C_Item and C_Item.IsBound and ItemLocation and ItemLocation.CreateFromBagAndSlot then
        local ok, bound = pcall(function() return C_Item.IsBound(ItemLocation:CreateFromBagAndSlot(bag, slot)) end)
        if ok then return bound end
    end
    return false
end

local function ReadBags(bags)
    local counts, bound = {}, {}
    for _, bag in ipairs(bags) do
        for slot = 1, (NumSlots and NumSlots(bag) or 0) do
            local id, count, isBound = SlotInfo(bag, slot)
            if id then
                if IsBound(bag, slot, isBound) then
                    bound[id] = true
                else
                    counts[id] = (counts[id] or 0) + count
                end
            end
        end
    end
    return counts, bound
end

local function MyInv()
    local inv = FT.db.inv[FT.charKey] or {}
    FT.db.inv[FT.charKey] = inv
    return inv
end

local function BagList()
    local out = {}
    for b = 0, (NUM_BAG_SLOTS or 4) do out[#out + 1] = b end
    return out
end

local function BankList()
    local out = { BANK_CONTAINER or -1 }
    local first = (NUM_BAG_SLOTS or 4) + 1
    for b = first, first + (NUM_BANKBAGSLOTS or 6) - 1 do out[#out + 1] = b end
    return out
end

local bankOpen = false
function G.ScanBags()
    if not FT.charKey then return end
    local inv = MyInv()
    inv.bags, inv.bagsBound = ReadBags(BagList())
    inv.t = time()
    FT.Debounce("invChanged", 1, function() FT.Fire("FT_INVENTORY_CHANGED") end)
end

function G.ScanBank()
    if not (FT.charKey and bankOpen) then return end
    local inv = MyInv()
    inv.bank, inv.bankBound = ReadBags(BankList())
    inv.bankT = time()
    FT.Debounce("invChanged", 1, function() FT.Fire("FT_INVENTORY_CHANGED") end)
end

FT.On("PLAYER_ENTERING_WORLD", function() C_Timer.After(3, G.ScanBags) end)
FT.On("BAG_UPDATE_DELAYED", function() FT.Debounce("bagScan", 0.5, function() G.ScanBags(); G.ScanBank() end) end)
FT.On("BANKFRAME_OPENED", function()
    bankOpen = true
    C_Timer.After(0.3, G.ScanBank)
end)
FT.On("BANKFRAME_CLOSED", function() bankOpen = false end)
FT.On("PLAYERBANKSLOTS_CHANGED", function() FT.Debounce("bankScan", 0.5, G.ScanBank) end)

---------------------------------------------------------------------------
-- Mailbox (what you bought waits there) and gold
---------------------------------------------------------------------------
local mailOpen = false
function G.ScanMail()
    if not (FT.charKey and mailOpen and GetInboxNumItems and GetInboxItem) then return end
    local counts = {}
    local slots = ATTACHMENTS_MAX_RECEIVE or 12
    for i = 1, GetInboxNumItems() do
        for j = 1, slots do
            local _, itemID, _, count = GetInboxItem(i, j)
            if not itemID and GetInboxItemLink then itemID = ItemID(GetInboxItemLink(i, j)) end
            if type(itemID) == "number" and count and count > 0 then
                counts[itemID] = (counts[itemID] or 0) + count
            end
        end
    end
    local inv = MyInv()
    inv.mail, inv.mailT = counts, time()
    FT.Debounce("invChanged", 1, function() FT.Fire("FT_INVENTORY_CHANGED") end)
end

FT.On("MAIL_SHOW", function() mailOpen = true end)
FT.On("MAIL_CLOSED", function() mailOpen = false end)
FT.On("MAIL_INBOX_UPDATE", function() FT.Debounce("mailScan", 0.5, G.ScanMail) end)

local function SaveMoney()
    local c = FT.charKey and FT.db.chars[FT.charKey]
    if c then
        c.money = GetMoney()
        c.moneyT = time()
    end
end
FT.On("PLAYER_MONEY", SaveMoney)
FT.On("FT_LOGIN", SaveMoney)

---------------------------------------------------------------------------
-- Merchants: what a vendor really charges for a material
---------------------------------------------------------------------------
local function ScanMerchant()
    if not (GetMerchantNumItems and GetMerchantItemInfo) then return end
    for i = 1, GetMerchantNumItems() do
        local _, _, price, stack, _, _, _, extendedCost = GetMerchantItemInfo(i)
        local id = (GetMerchantItemID and GetMerchantItemID(i)) or ItemID(GetMerchantItemLink and GetMerchantItemLink(i))
        if id and price and price > 0 and not extendedCost then
            FT.db.vendor[id] = math.floor(price / math.max(1, stack or 1) + 0.5)
        end
    end
end
FT.On("MERCHANT_SHOW", function() C_Timer.After(0.3, ScanMerchant) end)
FT.On("MERCHANT_UPDATE", function() FT.Debounce("merchant", 0.5, ScanMerchant) end)
