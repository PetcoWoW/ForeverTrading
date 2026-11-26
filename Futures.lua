-- Wolf of Booty Bay: Futures - what raiders will need, and how you make gold from it. The pre-raid study's list
-- (Data/Futures.lua: what each class is expected to use, ranked) meets the live market (price, its trend, how fast
-- it sells) and the recipe data (what it's made of), and then you: through the Eye it knows if you gather, craft or
-- trade, and gives each item and each key material the move that's yours - craft it (a character of yours knows
-- it), hold your herbs (you gather them, the raids are ahead), sell into raid week, stock up while it's cheap.
local ADDON, FT = ...
local L = FT.L

local F = {}
FT.Futures = F

local CONF = { confirmed = 1.5, likely = 1, unknown = 0.7 }
local RAID_WEEK = 3 -- days before the raids open: sell what you held
local DIP = -0.1    -- down this much this week, with raid demand ahead: a dip worth buying

-- the recipe that makes an item: one of yours if a character knows it, else the game's
local byOutput
FT.On("FT_RECIPES_CHANGED", function() byOutput = nil end)
local function Recipe(id)
    if not byOutput then
        byOutput = {}
        for _, r in ipairs(FT.Craft.AllRecipes() or {}) do
            local cur = byOutput[r.output]
            if not cur or (next(r.knownBy or {}) and not next(cur.knownBy or {})) then byOutput[r.output] = r end
        end
    end
    return byOutput[id]
end
F.Recipe = Recipe

local function Known(r) return r and next(r.knownBy or {}) ~= nil end

-- days until the raids open (nil: open already, or nothing announced)
function F.Days()
    local ev = FT.Radar and FT.Radar.Next and FT.Radar.Next()
    return ev and ev.days or nil, ev
end

-- an item's market: price, listed, sold a day, 7- and 30-day change
local function Market(id)
    local s = FT.An.Stats(id)
    local rate = FT.Sales.Rate(id)
    return { price = s.price, listed = s.listed, perDay = rate and rate.perDay or nil, ch7 = s.ch7, ch30 = s.ch30, stats = s }
end
F.Market = Market

-- what an item's demand weighs: how many use it, how much of it they go through, how sure the study is
local function Weight(c)
    return (c.uses or 1) * (CONF[c.conf] or 1) * math.max(0.2, 1 - ((c.rank or 1) - 1) / 40)
end

---------------------------------------------------------------------------
-- Your move on one item, from what the wolf sees of you
---------------------------------------------------------------------------
local function ItemMove(c, m, r, p, days)
    local held = FT.Port.Count(c.id)
    local e = r and FT.Craft.Eval(r)
    local raidWeek = days and days <= RAID_WEEK
    -- no one has listed or sold it: the recipe isn't found yet
    if not m.price and (m.perDay or 0) == 0 then
        if Known(r) then
            return "CRAFT", string.format(L["You know it and no one sells it: the market is yours (materials ~%s)"],
                FT.Money(math.floor(e and e.cost or 0), "short"))
        end
        return "NORECIPE", L["No one makes it yet: where its recipe drops isn't known. Its materials are the play."]
    end
    if Known(r) and e and e.cost and e.revenue then
        local margin = e.revenue > 0 and (e.revenue - e.cost) / e.revenue or 0
        local who = FT.Craft.KnownByText(r)
        if margin > 0.02 then
            return "CRAFT", string.format(L["%s can craft it: ~%s in materials, sells ~%s (+%d%%)"], who,
                FT.Money(math.floor(e.cost), "short"), FT.Money(math.floor(e.revenue), "short"), math.floor(margin * 100 + 0.5))
        end
        return "CRAFT", string.format(L["%s can craft it, but it sells at its materials' cost now: craft it closer to the raids"], who)
    end
    if held > 0 then
        if raidWeek then
            return "SELL", string.format(L["You hold %s: raid week, sell them now"], FT.Num(held))
        end
        return "HOLD", string.format(L["You hold %s: keep them for raid week"], FT.Num(held))
    end
    if m.ch7 and m.ch7 >= 0.3 then
        return "LATE", string.format(L["Already climbing: %s this week, late to buy"], FT.Pct(m.ch7))
    end
    -- a dip with raid demand ahead: on the list, sure enough, and the raids not here yet
    if m.ch7 and m.ch7 <= DIP and not raidWeek and (c.conf ~= "unknown") and (c.rank or 99) <= 24 then
        return "DIP", string.format(L["Down %d%% this week with the raids ahead: buy the dip"], math.floor(-m.ch7 * 100 + 0.5))
    end
    if m.ch30 and m.ch30 <= -0.3 and not raidWeek then
        return "BUY", string.format(L["%d%% cheaper than in its first weeks: buy before the raids"], math.floor(-m.ch30 * 100 + 0.5))
    end
    return "STEADY", L["About its usual price"]
end

-- the consumables, best first: { c, id, rank, market, recipe, move, moveText }
function F.Consumables()
    local p = FT.Eye and FT.Eye.Profile() or {}
    local days = F.Days()
    local out = {}
    for _, c in ipairs(FT.FUTURES and FT.FUTURES.consumables or {}) do
        local m = Market(c.id)
        local r = Recipe(c.id)
        local move, text = ItemMove(c, m, r, p, days)
        out[#out + 1] = { c = c, id = c.id, rank = c.rank, market = m, recipe = r, move = move, moveText = text }
    end
    table.sort(out, function(a, b) return a.rank < b.rank end)
    return out
end

-- the crafted pre-raid pieces, by how many specs want each
function F.Gear()
    local out = {}
    for _, g in ipairs(FT.FUTURES and FT.FUTURES.gear or {}) do
        local m = Market(g.id)
        local r = Recipe(g.id)
        local e = r and FT.Craft.Eval(r)
        local move, text
        if Known(r) and e and e.cost then
            move = "CRAFT"
            text = string.format(L["%s can make it: ~%s in materials%s"], FT.Craft.KnownByText(r), FT.Money(math.floor(e.cost), "short"),
                m.price and string.format(L[", sells ~%s"], FT.Money(m.price, "short")) or L[", none listed: name your price"])
        elseif not m.price then
            move, text = "NONE", e and e.complete and string.format(L["None listed. Materials ~%s"], FT.Money(math.floor(e.cost), "short"))
                or L["None listed, and some of its materials aren't on the market"]
        else
            move, text = "STEADY", string.format(L["%s listed, ~%s sold a day"], FT.Num(m.listed or 0), FT.Num(math.floor((m.perDay or 0) + 0.5)))
        end
        out[#out + 1] = { g = g, id = g.id, market = m, recipe = r, cost = e and e.cost, move = move, moveText = text,
            prof = r and r.prof }
    end
    table.sort(out, function(a, b)
        if a.g.specs ~= b.g.specs then return a.g.specs > b.g.specs end
        return a.id < b.id
    end)
    return out
end

---------------------------------------------------------------------------
-- The key materials: what most of the list is made of, and your move on each
---------------------------------------------------------------------------
function F.Materials(n)
    local p = FT.Eye and FT.Eye.Profile() or {}
    local days = F.Days()
    local raidWeek = days and days <= RAID_WEEK
    local mats = {}
    for _, c in ipairs(FT.FUTURES and FT.FUTURES.consumables or {}) do
        local r = Recipe(c.id)
        if r then
            local w = Weight(c)
            local q = math.max(r.outputQty or 1, 1)
            for _, rg in ipairs(r.reagents or {}) do
                local id = rg.itemID
                if id and not (FT.VENDOR_REAGENTS and FT.VENDOR_REAGENTS[id]) then
                    local x = mats[id]
                    if not x then
                        x = { id = id, score = 0, into = {}, known = false }
                        mats[id] = x
                    end
                    x.score = x.score + w * (rg.qty or 1) / q
                    x.into[#x.into + 1] = c.id
                    if Known(r) then x.known = true end
                end
            end
        end
    end
    local list = {}
    for _, x in pairs(mats) do
        if #x.into >= 2 or x.score >= 6 then list[#list + 1] = x end
    end
    table.sort(list, function(a, b) return a.score > b.score end)
    local looted = FT.Eye and FT.Eye.Looted and FT.Eye.Looted(14) or {}
    local out = {}
    for i = 1, math.min(n or 10, #list) do
        local x = list[i]
        x.market = Market(x.id)
        x.held = FT.Port.Count(x.id)
        x.gathered = looted[x.id]
        local kind = FT.Eye and FT.Eye.KindOf and FT.Eye.KindOf(x.id)
        x.yours = kind and p.kinds and p.kinds[kind] or false -- one of your gathering professions picks it
        local ch7 = x.market.ch7 or 0
        if x.held > 0 and (x.yours or p.isGatherer or not x.known) then
            if raidWeek then
                x.move, x.moveText = "SELL", string.format(L["You hold %s: raid week, sell into it"], FT.Num(x.held))
            else
                x.move, x.moveText = "HOLD", string.format(L["You hold %s: hold it, the raids open in %s days"], FT.Num(x.held), days and tostring(days) or "?")
            end
        elseif x.known then
            if not raidWeek and ch7 <= DIP then
                x.move, x.moveText = "DIP", string.format(L["You craft with it and it's down %d%% this week: buy the dip"], math.floor(-ch7 * 100 + 0.5))
            elseif not raidWeek and ch7 < 0.5 then
                x.move, x.moveText = "STOCK", L["You craft with it: stock up while it's cheap"]
            else
                x.move, x.moveText = "BUY", L["You craft with it: buy what you need, it's moving"]
            end
        elseif x.yours then
            x.move, x.moveText = "GATHER", L["Your profession picks it: worth gathering now"]
        elseif not raidWeek and ch7 <= DIP and #x.into >= 2 then
            -- in several raid consumables and cheaper than last week, the raids still ahead: worth buying
            x.move, x.moveText = "DIP", string.format(L["Down %d%% this week, in %d raid consumables: buy the dip before raid week"],
                math.floor(-ch7 * 100 + 0.5), #x.into)
        elseif ch7 >= 0.2 then
            x.move, x.moveText = "LATE", string.format(L["Up %d%% this week: late to buy, good to sell"], math.floor(ch7 * 100 + 0.5))
        else
            x.move, x.moveText = "STEADY", L["About its usual price"]
        end
        out[#out + 1] = x
    end
    return out
end

-- one line for the page: the raids, and what it sees of you
function F.Headline()
    local days, ev = F.Days()
    if days then
        return string.format(L["The raids open in %d days (%s): consumables usually climb toward raid night"], days, date("%m/%d", ev.t))
    end
    return L["The raids are open: consumables sell best before each raid night"]
end
