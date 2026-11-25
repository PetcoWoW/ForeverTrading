-- Wolf of Booty Bay (built on ForeverTrading): what your recipes cost and bring in.
-- Recipes come from Mastercraft (every character it knows) and from your own profession windows.
local ADDON, FT = ...
local L = FT.L

local C = {}
FT.Craft = C

local recipes = nil   -- list of recipes (one per output item and name)
local byOutput = nil  -- itemID -> recipes that make it
local evalCache = {}

local function Invalidate()
    recipes, byOutput = nil, nil
    wipe(evalCache)
end
FT.On("FT_RECIPES_CHANGED", Invalidate)
FT.On("FT_SOURCES_CHANGED", Invalidate)
FT.On("FT_PRICES_CHANGED", function() wipe(evalCache) end)
-- per auction house (an item window may look at the other one for a moment)
local evalCaches, evalKey = {}, nil
local function UseEvalCache()
    local key = FT.houseKey or "?"
    if key == evalKey then return end
    if evalKey then evalCaches[evalKey] = evalCache end
    evalCache = evalCaches[key] or {}
    evalKey = key
end
FT.On("FT_HOUSE_CHANGED", UseEvalCache)
FT.On("FT_HOUSE_USE", UseEvalCache)
FT.On("FT_LIVE_UPDATED", function() wipe(evalCache) end)
FT.On("FT_SCAN_DONE", function() wipe(evalCache) end)
FT.On("FT_SETTINGS_CHANGED", function() wipe(evalCache) end)

local function Build()
    local byKey = {}
    recipes, byOutput = {}, {}
    local nameIndex
    local function Add(prof, r, charName)
        if type(r) ~= "table" or type(r.reagents) ~= "table" or #r.reagents == 0 then return end
        -- The classic "craft" window (poisons) doesn't always say the item a recipe makes - Mastercraft reads it
        -- without one: then the item of the recipe's own name ("Deadly Poison" makes Deadly Poison).
        -- Enchantments make no item and stay out.
        local output = r.output
        if not output and type(r.name) == "string" then
            nameIndex = nameIndex or FT.NameIndex()
            output = nameIndex[r.name]
        end
        if type(output) ~= "number" then return end
        local key = output .. ":" .. tostring(r.name)
        local e = byKey[key]
        if not e then
            e = {
                key = key, name = r.name, icon = r.icon, prof = FT.ProfKey(prof), output = output,
                outputQty = (type(r.outputQty) == "number" and r.outputQty > 0) and r.outputQty or 1,
                reagents = r.reagents, incomplete = r.incomplete, knownBy = {},
            }
            byKey[key] = e
            recipes[#recipes + 1] = e
            byOutput[output] = byOutput[output] or {}
            table.insert(byOutput[output], e)
        elseif e.incomplete and not r.incomplete then
            e.reagents, e.incomplete = r.reagents, nil
        end
        -- the game's id of the recipe: it opens in the profession window by it
        local id = r.id or r.recipeID or r.spellID
        if type(id) == "number" and not e.id then e.id = id end
        if charName then e.knownBy[charName] = true end
    end
    for guid, profs in pairs(FT.db.recipes) do
        local c = FT.db.chars[guid]
        if c and c.side == FT.sideKey and type(profs) == "table" then
            for prof, data in pairs(profs) do
                for _, r in ipairs(type(data) == "table" and data.list or {}) do Add(prof, r, c.name) end
            end
        end
    end
end

function C.List()
    if not recipes then Build() end
    return recipes
end

function C.ByOutput(itemID)
    if not recipes then Build() end
    return byOutput[itemID]
end

-- every item your recipes make or use
function C.EachItem(fn)
    for _, r in ipairs(C.List()) do
        fn(r.output)
        for _, rg in ipairs(r.reagents) do
            if rg.itemID then fn(rg.itemID) end
        end
    end
end

-- of the recipes that make an item (several characters, ranks), the one that brings the most
function C.Best(itemID)
    local best, bestProfit
    for _, r in ipairs(C.ByOutput(itemID) or {}) do
        local p = C.Eval(r).profit or -math.huge
        if not best or p > bestProfit then best, bestProfit = r, p end
    end
    return best
end

-- the materials of a recipe bought at the auction house (or with no price yet): what live searches follow
function C.MarketMaterials(r)
    local out = {}
    for _, part in ipairs(C.Eval(r).parts or {}) do
        local id = part.itemID
        if id and id ~= r.output and (part.source == "ah" or not part.unit) and not FT.VENDOR_REAGENTS[id] then
            out[#out + 1] = id
        end
    end
    return out
end

-- professions present, sorted
function C.Professions()
    local seen, out = {}, {}
    for _, r in ipairs(C.List()) do
        if not seen[r.prof] then
            seen[r.prof] = true
            out[#out + 1] = r.prof
        end
    end
    table.sort(out)
    return out
end

---------------------------------------------------------------------------
-- Cost
---------------------------------------------------------------------------
local RecipeCost

-- the auction house price of `qty`: walked up the order book when the book is as fresh as the price (a few
-- cheap lots aren't the price of all you need), else the lowest price
local function AHUnit(itemID, qty)
    local p, t = FT.Price(itemID)
    if not p then return nil end
    if qty and qty > 1 then
        local book = FT.Hist.Book(itemID)
        if book and book.source ~= "mastercraft" and book.levels and #book.levels > 0 and (book.t or 0) >= (t or 0) - 600 then
            local cost = FT.Hist.CostToBuy(itemID, qty)
            if cost then return cost / qty end
        end
    end
    return p
end

-- the cheapest way to get `qty` (one by default): auction house, vendor or crafting it yourself
-- returns unit cost, source ("ah", "vendor", "vendor~", "craft"), the recipe when crafted
local function UnitCost(itemID, depth, visiting, qty)
    local best, src, via
    local p = AHUnit(itemID, qty)
    if p then best, src = p, "ah" end
    local v, how = FT.VendorBuy(itemID)
    if v and (not best or v < best) then best, src = v, (how == "estimate") and "vendor~" or "vendor" end
    if FT.S.cheapestWay and depth < 2 then
        for _, r in ipairs(byOutput[itemID] or {}) do
            if not visiting[r.key] then
                visiting[r.key] = true
                local cost, complete = RecipeCost(r, depth + 1, visiting)
                visiting[r.key] = nil
                if complete and cost then
                    local unit = cost / r.outputQty
                    if not best or unit < best then best, src, via = unit, "craft", r end
                end
            end
        end
    end
    return best, src, via
end

-- total cost of one craft, complete (every material has a price), parts, the first missing material
RecipeCost = function(r, depth, visiting)
    local total, complete, parts, missing = 0, not r.incomplete, {}, nil
    for _, rg in ipairs(r.reagents) do
        local qty = rg.qty or 1
        local unit, src, via = UnitCost(rg.itemID, depth, visiting, qty)
        parts[#parts + 1] = { itemID = rg.itemID, qty = qty, unit = unit, source = src, via = via,
            total = unit and unit * qty or nil }
        if unit then
            total = total + unit * qty
        else
            complete = false
            missing = missing or rg.itemID
        end
    end
    return total, complete, parts, missing
end

function C.UnitCost(itemID)
    if not recipes then Build() end
    return UnitCost(itemID, 0, {})
end

local function Cut()
    return FT.S.ahCut and (1 - FT.Cut()) or 1
end

---------------------------------------------------------------------------
-- One recipe, everything about it
---------------------------------------------------------------------------
-- { cost, complete, parts, missing, sellUnit, revenue, via ("ah"/"vendor"), profit, margin, roi, stats,
--   liquidity, signal, strength, reason, sell (signal for the product), sellReason }
function C.Eval(r)
    local e = evalCache[r.key]
    if e then return e end
    if not recipes then Build() end
    e = {}
    local visiting = { [r.key] = true }
    e.cost, e.complete, e.parts, e.missing = RecipeCost(r, 0, visiting)
    e.stats = FT.An.Stats(r.output)
    -- a price blown up by a buyout isn't counted on: the fair price is
    e.sellUnit = e.stats.sale or e.stats.price
    e.rawUnit, e.spike = e.stats.price, e.stats.spike
    local qty = r.outputQty
    local ahRevenue = e.sellUnit and e.sellUnit * qty * Cut() or nil
    local vendorUnit = FT.VendorSell(r.output)
    local vendorRevenue = vendorUnit and vendorUnit * qty or nil
    if ahRevenue and (not vendorRevenue or ahRevenue >= vendorRevenue) then
        e.revenue, e.via = ahRevenue, "ah"
    elseif vendorRevenue then
        e.revenue, e.via = vendorRevenue, "vendor"
    end
    e.vendorRevenue = vendorRevenue
    if e.complete and e.revenue then
        e.profit = e.revenue - e.cost
        e.margin = e.revenue > 0 and e.profit / e.revenue or nil
        e.roi = e.cost > 0 and e.profit / e.cost or nil
    end
    e.liquidity = FT.An.Liquidity(e.stats)
    e.risks = FT.An.Risks(e.stats, e.liquidity)

    if not e.complete then
        e.signal, e.strength = "NODATA", 0
        local name = e.missing and FT.Item(e.missing)
        e.reason = string.format(L["No price for %s"], name or L["a material"])
    elseif not e.revenue then
        e.signal, e.strength, e.reason = "NODATA", 0, L["No price for the crafted item"]
    elseif e.profit <= 0 then
        e.signal, e.strength = "AVOID", 3
        e.reason = string.format(L["Loses %s per craft"], FT.Money(-e.profit, "short"))
    elseif e.profit < FT.S.minProfit or (e.margin or 0) * 100 < FT.S.minMargin then
        e.signal, e.strength = "WATCH", 1
        e.reason = string.format(L["Small profit: %s (%d%%)"], FT.Money(e.profit, "short"), math.floor((e.margin or 0) * 100 + 0.5))
    elseif e.via == "ah" and #e.risks > 0 then
        -- falling fast, fallen since the last check, flooded, more sellers, rarely listed, falling for a week:
        -- by the time yours is listed the price may be lower still, or it may not sell
        e.signal, e.strength = "RISKY", 2
        e.reason = table.concat(e.risks, "; ")
    else
        e.signal = "CRAFT"
        e.strength = ((e.margin or 0) >= 0.3) and 3 or 2
        e.reason = string.format(L["Profit %s (%d%%)"], FT.Money(e.profit, "short"), math.floor((e.margin or 0) * 100 + 0.5))
    end
    if e.spike and e.reason then
        e.reason = e.reason .. "  ||  " .. FT.C("accent", string.format(L["buyout? counted at %s"], FT.Money(e.sellUnit, "short")))
    end
    e.sell, e.sellStrength, e.sellReason = FT.An.SellSignal(e.stats)
    evalCache[r.key] = e
    return e
end

function C.Find(key)
    for _, r in ipairs(C.List()) do
        if r.key == key then return r end
    end
end

function C.KnownByText(r)
    local names = {}
    for name in pairs(r.knownBy) do names[#names + 1] = name end
    table.sort(names)
    return table.concat(names, ", ")
end

---------------------------------------------------------------------------
-- Margin history: what one craft cost and brought in, day by day
---------------------------------------------------------------------------
local function DayMap(itemID, days)
    local map = {}
    for _, c in ipairs(FT.Hist.Daily(itemID, days)) do map[c.day] = c.c end
    return map
end

-- price on `day`, or the last one up to 3 days before
local function At(map, day)
    for d = day, day - 3, -1 do
        if map[d] then return map[d] end
    end
end

-- list of { t, day, revenue, cost, profit } (oldest first)
function C.History(r, days)
    days = days or 30
    local today = FT.Day()
    local productMap = DayMap(r.output, days + 3)
    local reagentMaps, fixed = {}, {}
    local now = C.Eval(r)
    for i, rg in ipairs(r.reagents) do
        reagentMaps[i] = DayMap(rg.itemID, days + 3)
        local part = now.parts[i]
        -- vendor and craft-it-yourself costs don't move with the auction house
        if part and part.source and part.source ~= "ah" then fixed[i] = part.unit end
    end
    local out = {}
    for day = today - days + 1, today do
        local p = At(productMap, day)
        if day == today and now.sellUnit then p = now.sellUnit end
        if p then
            local cost, ok = 0, true
            for i, rg in ipairs(r.reagents) do
                local unit = fixed[i] or At(reagentMaps[i], day)
                if day == today and now.parts[i] and now.parts[i].unit then unit = now.parts[i].unit end
                if not unit then
                    ok = false
                    break
                end
                cost = cost + unit * (rg.qty or 1)
            end
            if ok then
                local revenue = p * r.outputQty * Cut()
                out[#out + 1] = { t = FT.DayStart(day), day = day, revenue = revenue, cost = cost, profit = revenue - cost }
            end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Best use of a material: every recipe it goes into (all of WoW Forever's, Data/Recipes.lua from the Blizzard
-- API, and the ones your characters know), and what one of it brings made into each
---------------------------------------------------------------------------
local PROF_NAMES = {
    [129] = "First Aid", [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy", [185] = "Cooking",
    [186] = "Mining", [197] = "Tailoring", [202] = "Engineering", [333] = "Enchanting",
}
C.PROF_NAMES = PROF_NAMES

local byReagent -- [materialID] = { recipe, ... } (recipes shaped like C.List()'s)

local function BuildUses()
    byReagent = {}
    local outputs = {} -- output:name of the known ones, so a recipe in both lists counts once (the known one)
    local function Index(r)
        local seen = {}
        for _, rg in ipairs(r.reagents) do
            if rg.itemID and not seen[rg.itemID] then
                seen[rg.itemID] = true
                byReagent[rg.itemID] = byReagent[rg.itemID] or {}
                table.insert(byReagent[rg.itemID], r)
            end
        end
    end
    for _, r in ipairs(C.List()) do
        outputs[r.output .. ":" .. tostring(r.name)] = true
        Index(r)
    end
    for id, d in pairs(FT.RECIPE_DB or {}) do
        local prof, output, qty, name = d[1], d[2], d[3], d[4]
        if not outputs[output .. ":" .. tostring(name)] then
            local reagents = {}
            for k = 5, #d - 1, 2 do reagents[#reagents + 1] = { itemID = d[k], qty = d[k + 1] } end
            Index({ key = "db:" .. id, id = id, name = name, prof = PROF_NAMES[prof] or "?", output = output,
                outputQty = qty > 0 and qty or 1, reagents = reagents, knownBy = {} })
        end
    end
end
FT.On("FT_RECIPES_CHANGED", function() byReagent = nil end)

-- the recipes a material goes into (nil: none)
function C.UsedIn(itemID)
    if not byReagent then BuildUses() end
    return byReagent[itemID]
end

-- what one of it brings sold as it is: the auction house after the cut, or a merchant
function C.RawValue(itemID)
    local s = FT.An.Stats(itemID)
    local ah = (s.sale or s.price) and (s.sale or s.price) * Cut() or nil
    local vendor = FT.VendorSell(itemID)
    if ah and (not vendor or ah >= vendor) then return ah, "ah" end
    return vendor, vendor and "vendor" or nil
end

-- { { recipe, eval, need = how many of it, each = what one of it brings that way (the product's price minus
--   the other materials, per one), known = someone of yours knows it }, ... }, the best first; raw, rawVia
function C.BestUse(itemID)
    local out = {}
    for _, r in ipairs(C.UsedIn(itemID) or {}) do
        local e = C.Eval(r)
        local need, mine = 0, 0
        for _, part in ipairs(e.parts or {}) do
            if part.itemID == itemID then
                need = need + part.qty
                mine = mine + (part.total or 0)
            end
        end
        local x = { recipe = r, eval = e, need = need, known = next(r.knownBy or {}) ~= nil }
        -- the other materials must have a price: else what's left for this one isn't known
        local othersPriced = true
        for _, part in ipairs(e.parts or {}) do
            if part.itemID ~= itemID and not part.unit then othersPriced = false end
        end
        if need > 0 and e.revenue and othersPriced then
            x.each = (e.revenue - (e.cost - mine)) / need
        end
        -- a product that really sells (3+ sales seen, one a day or more): its price can be counted on; one odd
        -- listing of a rare item isn't a market
        local rate = FT.Sales.Rate(r.output)
        x.perDay = rate and (rate.sold or 0) >= 3 and rate.perDay or nil
        x.sells = (x.perDay and x.perDay >= 1) or (e.via == "vendor") or false
        out[#out + 1] = x
    end
    table.sort(out, function(a, b)
        if (a.each ~= nil) ~= (b.each ~= nil) then return a.each ~= nil end
        if a.sells ~= b.sells then return a.sells end
        if a.each and a.each ~= b.each then return a.each > b.each end
        return (a.recipe.name or "") < (b.recipe.name or "")
    end)
    local raw, via = C.RawValue(itemID)
    return out, raw, via
end
