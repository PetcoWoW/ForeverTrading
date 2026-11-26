-- Wolf: what we read from the game ourselves, so it also works without Mastercraft:
-- the recipes of your profession windows, your bags and bank, and what merchants charge.
local ADDON, FT = ...
local L = FT.L

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
    ["Inscription"] = "Inscription", ["Начертание"] = "Inscription", ["Inschriftenkunde"] = "Inscription",
    ["Fishing"] = "Fishing", ["Рыбная ловля"] = "Fishing", ["Angeln"] = "Fishing",
    ["Skinning"] = "Skinning", ["Снятие шкур"] = "Skinning", ["Kürschnerei"] = "Skinning",
    ["Herbalism"] = "Herbalism", ["Травничество"] = "Herbalism", ["Kräuterkunde"] = "Herbalism",
    ["Lockpicking"] = "Lockpicking", ["Взлом замков"] = "Lockpicking", ["Вскрытие замков"] = "Lockpicking",
    ["Schlossknacken"] = "Lockpicking",
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

-- complete: the list is every recipe learned (the newer API gives them all, whatever the window shows).
-- The older one reads what the window shows: with a search or "have materials" on that is a part, so the
-- recipes read before stay (a recipe once learned isn't lost) - the poisons vanished that way.
-- what a recipe list is, for telling whether a scan changed anything: every craft makes the game send its
-- "recipes updated" (the counts you can make changed), and re-working every craft profit each time was the lag
-- while crafting. Cooldowns and the counts don't count; a new recipe, a reagent or a colour (skill-ups) does.
local function Signature(list)
    local parts = {}
    for _, r in ipairs(list or {}) do
        if type(r) == "table" then
            local rs = {}
            for _, g in ipairs(r.reagents or {}) do rs[#rs + 1] = tostring(g.itemID) .. "x" .. tostring(g.qty) end
            parts[#parts + 1] = table.concat({ tostring(r.output), tostring(r.name), tostring(r.outputQty),
                tostring(r.diff), table.concat(rs, ",") }, ":")
        end
    end
    table.sort(parts)
    return table.concat(parts, ";")
end

local function Store(prof, list, complete)
    if not (FT.charKey and prof and list and #list > 0) then return end
    FT.db.recipes[FT.charKey] = FT.db.recipes[FT.charKey] or {}
    local key = FT.ProfKey(prof)
    local old = FT.db.recipes[FT.charKey][key]
    local kept = 0
    if not complete and type(old) == "table" and type(old.list) == "table" then
        local seen = {}
        for _, r in ipairs(list) do seen[tostring(r.output) .. ":" .. tostring(r.name)] = true end
        for _, r in ipairs(old.list) do
            if type(r) == "table" and not seen[tostring(r.output) .. ":" .. tostring(r.name)] then
                list[#list + 1] = r
                kept = kept + 1
            end
        end
    end
    local same = type(old) == "table" and Signature(old.list) == Signature(list)
    FT.db.recipes[FT.charKey][key] = { scanned = time(), list = list, name = prof }
    FT.Debug("recipes:", prof, #list - kept, "read,", kept, "kept from before", same and "(unchanged)" or "")
    if not same then FT.Debounce("recipesChanged", 0.5, function() FT.Fire("FT_RECIPES_CHANGED") end) end
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
    local ids = T.GetAllRecipeIDs() or {}
    -- Switching windows, the game names the new profession while it still lists the previous one's recipes
    -- for a moment (Mastercraft's author saw it too): saved under the new name, they overwrote its recipes and
    -- the previous profession's were lost on the next read (poisons, 18 Nov 2026). Read again in a moment.
    if T.GetProfessionInfoByRecipeID and ids[1] then
        local ok, pinfo = pcall(T.GetProfessionInfoByRecipeID, ids[1])
        if ok and type(pinfo) == "table" then
            local known, match = false, false
            for _, n in ipairs({ pinfo.professionName or "", pinfo.parentProfessionName or "" }) do
                if type(n) == "string" and n ~= "" then
                    known = true
                    if n == prof or n:find(prof, 1, true) or prof:find(n, 1, true) then match = true end
                end
            end
            if known and not match then
                G.mismatch = (G.mismatch or 0) + 1
                FT.Debug("recipes: the window is", prof, "but its recipes are still", tostring(pinfo.professionName),
                    "- read again", G.mismatch <= 5 and "in a moment" or "no more")
                if G.mismatch <= 5 then G.retry = true end
                return true
            end
        end
    end
    G.mismatch = 0
    local list = {}
    for _, id in ipairs(ids) do
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
    FT.Debug("recipes: window", prof, "-", #ids, "recipes listed,", #list, "learned")
    if #list == 0 then return false end
    Store(prof, list, true)
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

---------------------------------------------------------------------------
-- Open a recipe in the game's profession window
---------------------------------------------------------------------------
local pending -- { name, at }: chosen as soon as the classic profession window opens

-- the classic windows (trade skills, enchanting): choose the recipe in the open one and scroll to it
local function SelectIn(count, info, setSelection, select, scroll, shown, height, update, expand)
    if expand then pcall(expand, 0) end
    local n = count()
    for i = 1, n do
        local name, kind = info(i)
        if name == pending.name and kind ~= "header" and kind ~= "subheader" then
            if setSelection then pcall(setSelection, i) elseif select then pcall(select, i) end
            if scroll and FauxScrollFrame_SetOffset then
                local offset = math.max(0, math.min(i - 1, n - (shown or 8)))
                pcall(FauxScrollFrame_SetOffset, scroll, offset)
                local bar = scroll.ScrollBar or _G[(scroll:GetName() or "") .. "ScrollBar"]
                if bar and bar.SetValue then pcall(bar.SetValue, bar, offset * (height or 16)) end
            end
            if update then pcall(update) end
            return true
        end
    end
    return false
end

local function SelectPending()
    if not pending or GetTime() - pending.at > 120 then return false end
    if TradeSkillFrame and TradeSkillFrame:IsShown() and GetNumTradeSkills and GetTradeSkillInfo then
        if SelectIn(GetNumTradeSkills, GetTradeSkillInfo, TradeSkillFrame_SetSelection, SelectTradeSkill,
            TradeSkillListScrollFrame, TRADE_SKILLS_DISPLAYED, TRADE_SKILL_HEIGHT, TradeSkillFrame_Update,
            ExpandTradeSkillSubClass) then
            pending = nil
            return true
        end
    end
    if CraftFrame and CraftFrame:IsShown() and GetNumCrafts and GetCraftInfo then
        local function Info(i)
            local name, _, kind = GetCraftInfo(i)
            return name, kind
        end
        if SelectIn(GetNumCrafts, Info, CraftFrame_SetSelection, SelectCraft, CraftListScrollFrame, CRAFTS_DISPLAYED,
            CRAFT_SKILL_HEIGHT, CraftFrame_Update, ExpandCraftSkillLine) then
            pending = nil
            return true
        end
    end
    return false
end

-- r: a recipe of FT.Craft. The modern profession window opens right at it; the classic one has it chosen
-- when it is open or as soon as you open it (the game lets only you open a profession)
function FT.OpenRecipeInGame(r)
    if not r then return false end
    if InCombatLockdown and InCombatLockdown() then
        FT.Print(L["Not during a fight."])
        return false
    end
    local T = C_TradeSkillUI
    if r.id and T and T.OpenRecipe and pcall(T.OpenRecipe, r.id) then return true end
    pending = { name = r.name, at = GetTime() }
    if SelectPending() then return true end
    FT.Print(string.format(L["Open the %s window: the recipe is chosen there by itself."], L[r.prof] or r.prof))
    return false
end

FT.On("TRADE_SKILL_SHOW", function() C_Timer.After(0.3, SelectPending) end)
FT.On("CRAFT_SHOW", function() C_Timer.After(0.3, SelectPending) end)

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

-- itemID, count, bound (nil: ask the item), link
local function SlotInfo(bag, slot)
    if Container and Container.GetContainerItemInfo then
        local info = Container.GetContainerItemInfo(bag, slot)
        if info then return info.itemID, info.stackCount or 1, info.isBound, info.hyperlink end
        return nil
    end
    if GetContainerItemInfo then
        local _, count, _, _, _, _, link, _, _, itemID = GetContainerItemInfo(bag, slot)
        return itemID or ItemID(link), count or 1, nil, link
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

-- What this character carries that the auction house could take (not bound): stackable goods one entry per
-- item (all its stacks together), everything else one entry per bag slot.
-- { id, count, gear, bag, slot (the first), link, slots = { { bag, slot, count }, ... } }
local GetItem = (C_Item and C_Item.GetItemInfo) or GetItemInfo
function FT.BagItems()
    local byID, out = {}, {}
    for _, bag in ipairs(BagList()) do
        for slot = 1, (NumSlots and NumSlots(bag) or 0) do
            local id, count, isBound, link = SlotInfo(bag, slot)
            if id and not IsBound(bag, slot, isBound) then
                local stack = select(8, GetItem(id))
                if stack == 1 then
                    -- this very item (another copy of it, another version, has its own)
                    local guid
                    if C_Item and C_Item.GetItemGUID and ItemLocation and ItemLocation.CreateFromBagAndSlot then
                        local ok, g = pcall(C_Item.GetItemGUID, ItemLocation:CreateFromBagAndSlot(bag, slot))
                        if ok then guid = g end
                    end
                    out[#out + 1] = { id = id, count = 1, gear = true, bag = bag, slot = slot, link = link, guid = guid,
                        slots = { { bag, slot, 1 } } }
                else
                    local e = byID[id]
                    if not e then
                        e = { id = id, count = 0, bag = bag, slot = slot, link = link, slots = {} }
                        byID[id] = e
                        out[#out + 1] = e
                    end
                    e.count = e.count + count
                    e.slots[#e.slots + 1] = { bag, slot, count }
                end
            end
        end
    end
    return out
end

-- bags change with every craft: while a profession window is open, what's held is worked out again only once
-- crafting stops for a few seconds (each craft used to rebuild deals, holdings and the open page)
local function InvChanged()
    local crafting = (TradeSkillFrame and TradeSkillFrame:IsShown()) or (CraftFrame and CraftFrame:IsShown())
        or (ProfessionsFrame and ProfessionsFrame:IsShown())
    FT.Debounce("invChanged", crafting and 5 or 1, function() FT.Fire("FT_INVENTORY_CHANGED") end)
end
G.InvChanged = InvChanged

local bankOpen = false
function G.ScanBags()
    if not FT.charKey then return end
    local inv = MyInv()
    inv.bags, inv.bagsBound = ReadBags(BagList())
    inv.t = time()
    InvChanged()
end

function G.ScanBank()
    if not (FT.charKey and bankOpen) then return end
    local inv = MyInv()
    inv.bank, inv.bankBound = ReadBags(BankList())
    inv.bankT = time()
    InvChanged()
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
    local counts, gold, from = {}, 0, {}
    local slots = ATTACHMENTS_MAX_RECEIVE or 12
    for i = 1, GetInboxNumItems() do
        if GetInboxHeaderInfo then
            local _, _, sender, _, money, cod = GetInboxHeaderInfo(i)
            if sender then from[sender:gsub("%-.*$", "")] = true end
            if type(money) == "number" and money > 0 and not (cod and cod > 0) then gold = gold + money end
        end
        for j = 1, slots do
            local _, itemID, _, count = GetInboxItem(i, j)
            if not itemID and GetInboxItemLink then itemID = ItemID(GetInboxItemLink(i, j)) end
            if type(itemID) == "number" and count and count > 0 then
                counts[itemID] = (counts[itemID] or 0) + count
            end
        end
    end
    local inv = MyInv()
    inv.mail, inv.mailT, inv.mailGold = counts, time(), gold
    G.Arrived(from)
    InvChanged()
end

-- Mail you send to one of your own characters (a bank alt) stays yours on the way: it counts in that character's
-- mail until it opens its mailbox and the letter is there - from then its own reading has it. Mail with items can
-- take up to an hour, so a mailbox opened before that keeps it on the way; after 30 days (it would have come back)
-- it's dropped. Mail to anyone else leaves what you own, as before. FT.db.transit = { { to, toName, from, fromName,
-- side, items = { [itemID] = n }, gold, t } }
local function OwnChar(name)
    if not name or name == "" then return nil end
    local short = name:gsub("%-.*$", ""):lower()
    for guid, c in pairs(FT.db.chars) do
        if guid ~= FT.charKey and c.side == FT.sideKey and c.name and c.name:lower() == short then return guid, c end
    end
end
G.OwnChar = OwnChar

local sending
local function ReadSend(to)
    sending = nil
    local guid, c = OwnChar(to)
    if not guid then return end
    if GetSendMailCOD and (GetSendMailCOD() or 0) > 0 then return end -- cash on delivery: a sale, not a move
    local items, any = {}, false
    for i = 1, (ATTACHMENTS_MAX_SEND or 12) do
        local id, count
        if GetSendMailItem then
            local _, itemID, _, n = GetSendMailItem(i)
            id, count = itemID, n
        end
        if not id and GetSendMailItemLink then id = ItemID(GetSendMailItemLink(i)) end
        if type(id) == "number" and type(count) == "number" and count > 0 then
            items[id] = (items[id] or 0) + count
            any = true
        end
    end
    local gold = GetSendMailMoney and GetSendMailMoney() or 0
    if not any and gold <= 0 then return end
    local me = FT.db.chars[FT.charKey] or {}
    sending = { to = guid, toName = c.name, from = FT.charKey, fromName = me.name, side = FT.sideKey,
        items = items, gold = gold, t = time() }
end
if hooksecurefunc then pcall(hooksecurefunc, "SendMail", function(to) pcall(ReadSend, to) end) end
FT.On("MAIL_SEND_SUCCESS", function()
    if not sending then return end
    FT.db.transit = FT.db.transit or {}
    local last = FT.db.transit[#FT.db.transit]
    if not (last and last.t == sending.t and last.to == sending.to and last.from == sending.from) then -- one letter once
        table.insert(FT.db.transit, sending)
    end
    sending = nil
    InvChanged()
end)
FT.On("MAIL_FAILED", function() sending = nil end)

-- this character's mailbox was just read: letters from your characters that are there now are counted by it
function G.Arrived(from)
    local list, now = FT.db.transit, time()
    if not list then return end
    for i = #list, 1, -1 do
        local x = list[i]
        if now - (x.t or 0) > 30 * 86400
            or (x.to == FT.charKey and ((x.fromName and from[x.fromName]) or now - (x.t or 0) > 3700)) then
            table.remove(list, i)
        end
    end
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
-- price, stack size, paid in something other than money: the newer clients (Forever among them) answer with
-- C_MerchantFrame.GetItemInfo, the older ones with GetMerchantItemInfo
local function MerchantItem(i)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local ok, info = pcall(C_MerchantFrame.GetItemInfo, i)
        if ok and type(info) == "table" then return info.price, info.stackCount, info.hasExtendedCost end
        return nil
    end
    if GetMerchantItemInfo then
        local _, _, price, stack, _, _, _, extendedCost = GetMerchantItemInfo(i)
        return price, stack, extendedCost
    end
end

local function ScanMerchant()
    if not GetMerchantNumItems then return end
    local n = 0
    for i = 1, GetMerchantNumItems() do
        local price, stack, extendedCost = MerchantItem(i)
        local id = (GetMerchantItemID and GetMerchantItemID(i)) or ItemID(GetMerchantItemLink and GetMerchantItemLink(i))
        if id and price and price > 0 and not extendedCost then
            local unit = math.floor(price / math.max(1, stack or 1) + 0.5)
            if FT.db.vendor[id] ~= unit then n = n + 1 end
            FT.db.vendor[id] = unit
        end
    end
    -- new vendor prices: craft costs count them
    if n > 0 then
        FT.Debug("merchant:", n, "prices recorded")
        FT.Fire("FT_PRICES_CHANGED", "vendor")
    end
end
FT.On("MERCHANT_SHOW", function() C_Timer.After(0.3, ScanMerchant) end)
FT.On("MERCHANT_UPDATE", function() FT.Debounce("merchant", 0.5, ScanMerchant) end)
