-- Wolf: what your recipes cost and bring in.
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

-- Where a recipe comes from (v0.43): { items = { recipe itemIDs }, trainer = true (no recipe item: a trainer),
-- vendor = { n = merchant, z = zone, p = price, l = limited, by = who saw it }, ah = { id, price, listed } (the
-- cheapest one listed now, else the last price seen, listed = 0) }; nil when the recipe data doesn't say
function C.RecipeSource(r)
    if not (r and type(r.name) == "string" and FT.RECIPE_ITEMS) then return nil end
    local ids = FT.RECIPE_ITEMS[r.name:lower()]
    if not ids or #ids == 0 then return { items = {}, trainer = true } end
    local out = { items = ids }
    local vendors = FT.db and FT.db.recipeVendors
    for _, id in ipairs(ids) do
        if vendors and vendors[id] and not out.vendor then out.vendor = vendors[id] end
        local st = FT.An and FT.An.Stats(id)
        if st and st.price then
            local listed = st.listed or 0
            local a = out.ah
            if not a or (listed > 0 and (a.listed == 0 or st.price < a.price)) then
                out.ah = { id = id, price = st.price, listed = listed }
            end
        end
    end
    return out
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
local allRecipes -- every recipe once: the ones your characters know, then the rest of WoW Forever's

local function BuildUses()
    byReagent = {}
    allRecipes = {}
    local outputs = {} -- output:name of the known ones, so a recipe in both lists counts once (the known one)
    local function Index(r)
        local seen = {}
        allRecipes[#allRecipes + 1] = r
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
FT.On("FT_RECIPES_CHANGED", function() byReagent = nil; allRecipes = nil end)

function C.AllRecipes()
    if not allRecipes then BuildUses() end
    return allRecipes
end

---------------------------------------------------------------------------
-- Craft for profit: every recipe of WoW Forever whose product really sells, by the gold it should make a day
-- (profit per craft x how many of it sell a day, up to 20). Worked out in the background (2,300 recipes), kept
-- until new prices come.
---------------------------------------------------------------------------
local profitList, profitBusy, profitAt

-- crafts with a cooldown (Classic's; Blizzard's recipe data doesn't say): days between two crafts
local COOLDOWN_ITEMS = { [14342] = 4, [12360] = 2, [15409] = 3 } -- Mooncloth, Arcanite Bar, Refined Deeprock Salt
function C.CooldownDays(r)
    if COOLDOWN_ITEMS[r.output] then return COOLDOWN_ITEMS[r.output] end
    if type(r.name) == "string" and r.name:find("^Transmute") then return 1 end
    return nil
end
FT.On("FT_SCAN_DONE", function() profitList = nil end)
FT.On("FT_PRICES_CHANGED", function(source) if source ~= "live" then profitList = nil end end)

-- the list (nil while it's being worked out) - done(list) once ready
function C.ProfitCrafts(done)
    if profitList then return profitList end
    if profitBusy then return nil end
    profitBusy = true
    local all = C.AllRecipes()
    local out = {}
    -- every profession's recipes, whoever knows them: the best of selling what it makes and disenchanting it
    FT.Job("craftProfit", #all, function(k)
        local r = all[k]
        local e = C.Eval(r)
        if not (e.complete and e.cost and e.cost > 0) then return end
        local qty = r.outputQty or 1
        local rate = FT.Sales.Rate(r.output)
        local perDay = rate and (rate.sold or 0) >= 3 and rate.perDay or nil
        local unseen = not rate or (rate.hours or 0) < 6 -- no sales watched yet: not "doesn't sell"
        -- 1) sell it: the product's market must really move (or not be watched yet, and be listed)
        local sell
        if e.revenue and e.via == "ah" and e.revenue > e.cost then
            local listed = select(2, FT.Price(r.output))
            if perDay and perDay >= 1 then sell = { profit = e.revenue - e.cost, crafts = math.min(perDay / qty, 20) }
            elseif unseen and (listed or 0) >= 5 then sell = { profit = e.revenue - e.cost, crafts = 0.5, unseen = true } end
        end
        -- 2) disenchant it: its dust and essences sell whatever the product does
        local de
        local v, skill = FT.Enchant and FT.Enchant.Value(r.output)
        if v and v * qty > e.cost then de = { profit = v * qty - e.cost, crafts = 5, skill = skill } end
        local best = sell
        if sell then sell.mode = "sell" end
        if de and (not sell or de.profit > sell.profit) then
            best = de
            best.mode = "de"
        end
        if not best then return end
        local cd = C.CooldownDays(r)
        -- a cooldown caps it: one craft every few days, however much sells
        local crafts = cd and (1 / cd) or best.crafts
        out[#out + 1] = {
            id = r.output, recipe = r, eval = e, perDay = perDay, cooldown = cd, mode = best.mode,
            profit = best.profit, unseen = best.unseen, deSkill = best.skill, deValue = v and v * qty,
            known = next(r.knownBy or {}) ~= nil, prof = r.prof,
            daily = best.profit * crafts * (best.unseen and 0.5 or 1),
        }
    end, function()
        table.sort(out, function(a, b) return a.daily > b.daily end)
        profitList, profitBusy, profitAt = out, false, time()
        FT.Fire("FT_CRAFTS_READY")
        if done then done(out) end
    end, done == nil and 2 or nil) -- made ahead (no one waiting): lighter on the frame rate
    return nil
end

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

---------------------------------------------------------------------------
-- Disenchanting (Classic's odds - nobody has published WoW Forever's yet; they may differ): what a green, blue or
-- purple weapon or armor piece breaks into, what that's worth sold at the auction house, and buy-to-disenchant
-- deals for the skill of your best enchanter.
---------------------------------------------------------------------------
local E = {}
FT.Enchant = E

local DUST = { strange = 10940, soul = 11083, vision = 11137, dream = 11176, illusion = 16204 }
local ESS = { lmagic = 10938, gmagic = 10939, lastral = 10998, gastral = 11082, lmystic = 11134, gmystic = 11135,
    lnether = 11174, gnether = 11175, leternal = 16202, geternal = 16203 }
local SHARD = { sglim = 10978, lglim = 11084, sglow = 11138, lglow = 11139, srad = 11177, lrad = 11178,
    sbril = 14343, lbril = 14344 }
local NEXUS = 20725

-- greens by item level: { up to ilvl, skill, dust {id, min, max}, essence {id, min, max}, shard id }
local GREEN = {
    { 15, 1, { DUST.strange, 1, 2 }, { ESS.lmagic, 1, 2 }, nil },
    { 20, 1, { DUST.strange, 2, 3 }, { ESS.gmagic, 1, 2 }, SHARD.sglim },
    { 25, 25, { DUST.strange, 4, 6 }, { ESS.lastral, 1, 2 }, SHARD.sglim },
    { 30, 50, { DUST.soul, 1, 2 }, { ESS.gastral, 1, 2 }, SHARD.lglim },
    { 35, 75, { DUST.soul, 2, 5 }, { ESS.lmystic, 1, 2 }, SHARD.sglow },
    { 40, 100, { DUST.vision, 1, 2 }, { ESS.gmystic, 1, 2 }, SHARD.lglow },
    { 45, 125, { DUST.vision, 2, 5 }, { ESS.lnether, 1, 2 }, SHARD.srad },
    { 50, 150, { DUST.dream, 1, 2 }, { ESS.gnether, 1, 2 }, SHARD.lrad },
    { 55, 175, { DUST.dream, 2, 5 }, { ESS.leternal, 1, 2 }, SHARD.sbril },
    { 60, 200, { DUST.illusion, 1, 2 }, { ESS.geternal, 1, 2 }, SHARD.lbril },
    { 65, 225, { DUST.illusion, 2, 5 }, { ESS.geternal, 2, 3 }, SHARD.lbril },
}
-- blues: { up to ilvl, skill, shard }
local BLUE = {
    { 25, 1, SHARD.sglim }, { 30, 50, SHARD.lglim }, { 35, 75, SHARD.sglow }, { 40, 100, SHARD.lglow },
    { 45, 125, SHARD.srad }, { 50, 150, SHARD.lrad }, { 55, 175, SHARD.sbril }, { 70, 200, SHARD.lbril },
}

-- what it breaks into: { { itemID, chance, average count }, ... } and the skill it needs; nil if it doesn't
function E.Outcome(itemID)
    -- weapons and armor only - told without asking the server (GetItemInfoInstant)
    local _, _, _, _, _, classID = FT.GetItemInfoInstant(itemID)
    if classID ~= 2 and classID ~= 4 then return nil end
    -- quality and item level need the full info: only for items the game already has (asking the server for
    -- thousands of items at once floods it and stutters the game)
    if C_Item and C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(itemID) then return nil end
    local _, _, quality, ilvl = FT.GetItemInfo(itemID)
    if not (quality and ilvl) then return nil end
    if quality == 2 then
        for _, b in ipairs(GREEN) do
            if ilvl <= b[1] then
                local weapon = classID == 2
                -- weapons give more essence, armor more dust (Classic: 75/20/5 flipped to 20/75/5)
                local pd, pe = weapon and 0.20 or 0.75, weapon and 0.75 or 0.20
                if not b[5] then pd, pe = weapon and 0.20 or 0.80, weapon and 0.80 or 0.20 end
                local out = {
                    { b[3][1], pd, (b[3][2] + b[3][3]) / 2 },
                    { b[4][1], pe, (b[4][2] + b[4][3]) / 2 },
                }
                if b[5] then out[3] = { b[5], 0.05, 1 } end
                return out, b[2]
            end
        end
    elseif quality == 3 then
        for _, b in ipairs(BLUE) do
            if ilvl <= b[1] then
                if b[3] == SHARD.lbril and ilvl >= 56 then return { { b[3], 0.995, 1 }, { NEXUS, 0.005, 1 } }, b[2] end
                return { { b[3], 1, 1 } }, b[2]
            end
        end
    elseif quality == 4 and ilvl >= 56 then
        return { { NEXUS, 1, ilvl <= 60 and 1 or 1.5 } }, ilvl <= 60 and 225 or 300
    end
    return nil
end

-- what disenchanting one is worth, its materials sold at the auction house after the cut, and the skill it needs
-- (nil: can't be disenchanted, or its likely materials have no price)
local valueCache, matCache = {}, {}
FT.On("FT_SCAN_DONE", function() wipe(valueCache); wipe(matCache) end)

-- a material's price to count on: today's, or its average when that is lower (a spike doesn't last), and its
-- 30-day low (the worst case); nil when it hardly sells (seen a day: under one a day) - it can't be counted on
local function MatPrice(id)
    local c = matCache[id]
    if c == nil then
        c = false
        -- the light numbers (the market row's last days, the sale rate), not the whole stats: a Best use can value
        -- a hundred crafts at once
        local p = FT.Price(id)
        local row = FT.Market.Row(id)
        local spark = row and row.spark
        local lo = p
        if p and spark and #spark >= 3 then
            local days = {}
            for i = 1, #spark - 1 do days[#days + 1] = spark[i] end -- the last one may be today's
            table.sort(days)
            p = math.min(p, days[math.ceil(#days / 2)])
            lo = math.min(p, days[1])
        end
        -- the price feed's sale rate (quick; the full one reads your scans' history and is slow the first time)
        local sales = FT.Feed and FT.Feed.Rate and FT.Feed.Rate(id)
        if p and not (sales and sales.hours >= 24 and sales.perDay < 1) then c = { p = p, lo = lo or p } end
        matCache[id] = c
    end
    if not c then return nil end
    return c.p, c.lo
end

function E.Value(itemID)
    local c = valueCache[itemID]
    if c == nil then
        c = false
        local out, skill = E.Outcome(itemID)
        if out then
            local total, low, known = 0, 0, 0
            for _, o in ipairs(out) do
                local p, lo = MatPrice(o[1])
                if p then
                    total = total + p * (1 - FT.Cut()) * o[2] * o[3]
                    low = low + lo * (1 - FT.Cut()) * o[2] * o[3]
                    known = known + o[2]
                end
            end
            if known >= 0.9 then c = { v = total, low = low, skill = skill } end
        end
        -- an item the game hasn't loaded yet isn't remembered as "can't"
        local cached = not (C_Item and C_Item.IsItemDataCachedByID) or C_Item.IsItemDataCachedByID(itemID)
        if c or cached then valueCache[itemID] = c end
    end
    if not c then return nil end
    return c.v, c.skill, c.low
end

-- the best enchanting skill among your characters on this side (seen when each logs in), nil: no enchanter
function E.Skill()
    local best
    for _, c in pairs(FT.db.chars or {}) do
        if c.side == FT.sideKey and type(c.enchanting) == "number" then best = math.max(best or 0, c.enchanting) end
    end
    return best
end

-- this character's professions and their skill, read from the skill list (enchanting for disenchanting)
local PROF_SET = { Alchemy = true, Blacksmithing = true, Enchanting = true, Engineering = true, Leatherworking = true,
    Tailoring = true, Cooking = true, ["First Aid"] = true, Mining = true, Herbalism = true, Skinning = true, Fishing = true,
    Jewelcrafting = true, Inscription = true }
local function ReadSkill()
    local c = FT.charKey and FT.db.chars[FT.charKey]
    if not (c and GetNumSkillLines and GetSkillLineInfo) then return end
    local profs = {}
    for i = 1, GetNumSkillLines() do
        local name, isHeader, _, rank = GetSkillLineInfo(i)
        local key = not isHeader and FT.ProfKey(name)
        if key and PROF_SET[key] and type(rank) == "number" then
            profs[key] = rank
            if key == "Enchanting" then c.enchanting = rank end
        end
    end
    if next(profs) then c.profs = profs end
end

-- "Jay: Mining 300, Engineering 285 · Bankalt: Enchanting 300" (nil: none seen yet)
function C.CraftersText()
    local parts = {}
    for _, c in pairs(FT.db.chars or {}) do
        if c.side == FT.sideKey and type(c.profs) == "table" then
            local list = {}
            for p, rank in pairs(c.profs) do list[#list + 1] = { p, rank } end
            table.sort(list, function(a, b) return a[2] > b[2] end)
            local bits = {}
            for _, x in ipairs(list) do bits[#bits + 1] = L[x[1]] .. " " .. x[2] end
            if #bits > 0 then parts[#parts + 1] = (c.name or "?") .. ": " .. table.concat(bits, ", ") end
        end
    end
    if #parts == 0 then return nil end
    table.sort(parts)
    return table.concat(parts, "  ·  ")
end
FT.On("FT_READY", function() C_Timer.After(3, ReadSkill) end)
FT.On("SKILL_LINES_CHANGED", function() FT.Debounce("enchSkill", 2, ReadSkill) end)

-- Buy it to disenchant: armor and weapons listed under what they break into, for your enchanter's skill.
-- Shaped like FT.Deals' entries (kind "DE") so Make gold lists them with the rest.
-- Worked out a little each frame (thousands of items), kept a minute: the list there is returned meanwhile (empty
-- the first time), and FT_DEALS_READY says when the new one is done.
local dealsCache, dealsAt, dealsJob
FT.On("FT_SCAN_DONE", function() dealsAt = nil end)
function E.Deals()
    if dealsCache and dealsAt and GetTime() - dealsAt < 60 then return dealsCache end
    if dealsJob then return dealsCache or {} end
    local skill = E.Skill()
    if not skill then return {} end
    local out = {}
    local minProfit = FT.S.dealMin or 0
    local rows = FT.Market.Rows() or {}
    dealsJob = FT.Job("de-deals", #rows, function(k)
        local r = rows[k]
        local v, need, low = E.Value(r.id)
        if v and need and need <= skill and r.price and r.price > 0 and not r.gone then
            local profit = v - r.price
            -- a fifth over what it costs at the materials' prices to count on: the odds are Classic's, and a
            -- disenchant can roll low
            if profit > math.max(minProfit, r.price * 0.2) then
                out[#out + 1] = { id = r.id, kind = "DE", unit = r.price, target = math.floor(v), perUnit = profit,
                    qty = 1, cost = r.price, profit = profit, t = r.t or time(), noBook = true,
                    worst = math.max(0, math.floor(r.price - (low or 0))) }
            end
        end
    end, function()
        table.sort(out, function(a, b) return a.profit > b.profit end)
        dealsCache, dealsAt, dealsJob = out, GetTime(), nil
        FT.Fire("FT_DEALS_READY")
    end, 2)
    return dealsCache or {}
end
