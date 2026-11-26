-- Wolf of Booty Bay: the Eye - what the addon sees of you, and what it says because of it.
-- It reads everything it already keeps: every character's professions and skill, every bag, bank and mailbox, your
-- gold, what you loot (all the time, not only in a session), what you bought and sold at the auction house (its
-- letters), your watchlist. From that, with no question asked, it works out what kind of player you are (gatherer,
-- crafter, trader, or a mix) and turns the market into a few moves that are yours: about what you hold, what you
-- watch, what your own characters can make or gather. Each says why. Nothing is suggested you can't do: no craft
-- no character of yours knows, no flip bigger than your gold, no farming for a profession you haven't got.
-- It speaks in chat only, and rarely: once after login (when the prices, your bags and the crafts are all known)
-- and after you leave the auction house, at most three moves, never the same thing twice a day.
local ADDON, FT = ...
local L = FT.L

local E = {}
FT.Eye = E

local GATHER = { Herbalism = "herb", Mining = "ore", Skinning = "leather", Fishing = "fish" }
local CRAFT = { Alchemy = true, Blacksmithing = true, Enchanting = true, Engineering = true, Leatherworking = true,
    Tailoring = true, Jewelcrafting = true, Inscription = true, Cooking = true }
-- the kinds of what you gather, by the game's own item classes (Trade Goods 7: 9 herb, 7 metal & stone,
-- 6 leather, 5 cloth, 10 elemental; Gems 3)
local function KindOf(id, cls, sub)
    if not cls then cls, sub = FT.ItemClass(id) end
    if cls == 7 then
        if sub == 9 then return "herb" elseif sub == 7 then return "ore" elseif sub == 6 then return "leather"
        elseif sub == 5 then return "cloth" elseif sub == 10 then return "elemental" end
    elseif cls == 3 then
        return "gem"
    end
    return nil
end
E.KindOf = KindOf
local KIND_WORD = { herb = "herbs", ore = "ore", leather = "leather", cloth = "cloth", elemental = "elementals",
    gem = "gems", fish = "fish" }

---------------------------------------------------------------------------
-- What you loot, every day (two weeks kept): the gathering half of the picture
---------------------------------------------------------------------------
local LOOT_DAYS = 14
local function LootLog()
    local log = FT.db.lootLog
    if type(log) ~= "table" then
        log = {}
        FT.db.lootLog = log
    end
    return log
end

FT.On("CHAT_MSG_LOOT", function(msg)
    if not (FT.db and FT.Session and FT.Session.ParseLoot) then return end
    local id, n = FT.Session.ParseLoot(msg)
    if not id then return end
    local log, today = LootLog(), FT.Day()
    local key = tostring(today)
    log[key] = log[key] or {}
    log[key][id] = (log[key][id] or 0) + (n or 1)
    for day in pairs(log) do
        if tonumber(day) and tonumber(day) < today - LOOT_DAYS then log[day] = nil end
    end
end)

-- what you looted in the last `days` days: { [itemID] = n }
function E.Looted(days)
    local out, today = {}, FT.Day()
    for day, items in pairs(LootLog()) do
        local d = tonumber(day)
        if d and d > today - (days or 7) and type(items) == "table" then
            for id, n in pairs(items) do out[id] = (out[id] or 0) + n end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- The profile: worked out from what's seen, kept a minute (or until what you hold or know changes)
---------------------------------------------------------------------------
local profile, profileAt
local function Forget() profile = nil end
FT.On("FT_INVENTORY_CHANGED", Forget)
FT.On("FT_RECIPES_CHANGED", Forget)
FT.On("FT_JOURNAL_CHANGED", Forget)
FT.On("FT_WATCH_CHANGED", Forget)
FT.On("SKILL_LINES_CHANGED", Forget)

local function Thousand(n) return FT.Num(math.floor(n + 0.5)) end

function E.Profile()
    if profile and GetTime() - profileAt < 60 then return profile end
    local p = { gather = {}, craft = {}, kinds = {}, chars = 0 }
    -- professions, every character of this side: the best rank of each, and who has it
    for _, c in pairs(FT.db.chars or {}) do
        if c.side == FT.sideKey then
            p.chars = p.chars + 1
            for prof, rank in pairs(type(c.profs) == "table" and c.profs or {}) do
                local into = GATHER[prof] and p.gather or (CRAFT[prof] and p.craft) or nil
                if into and (not into[prof] or rank > into[prof].rank) then
                    into[prof] = { rank = rank, who = c.name or "?" }
                end
            end
        end
    end
    for prof in pairs(p.gather) do p.kinds[GATHER[prof]] = true end
    -- crafts known (the recipes your profession windows showed)
    local known = 0
    for _, r in ipairs(FT.Craft.List() or {}) do
        if next(r.knownBy or {}) then known = known + 1 end
    end
    p.recipes = known
    -- what you gathered this week, by kind, and what it's worth
    p.looted, p.lootedValue = {}, 0
    for id, n in pairs(E.Looted(7)) do
        local k = KindOf(id)
        if k then
            p.looted[k] = (p.looted[k] or 0) + n
            p.lootedValue = p.lootedValue + (FT.Price(id) or 0) * n
        end
    end
    -- the auction house, two weeks of its letters: bought, sold, and what you bought and then sold (flips)
    local since = time() - 14 * 86400
    local bought, sold, boughtIds = 0, 0, {}
    p.boughtValue, p.soldValue, p.flips = 0, 0, 0
    for _, e in ipairs(FT.Journal and FT.Journal.Events() or {}) do
        if e.t >= since and e.id then
            if e.k == "B" then
                bought = bought + 1
                p.boughtValue = p.boughtValue + e.v
                boughtIds[e.id] = true
            elseif e.k == "S" then
                sold = sold + 1
                p.soldValue = p.soldValue + e.v
                if boughtIds[e.id] then p.flips = p.flips + 1 end
            end
        end
    end
    p.bought, p.sold = bought, sold
    -- what you hold: worth by group (materials, crafted, gear)
    p.held = { mat = 0, crafted = 0, gear = 0, other = 0 }
    p.worth = 0
    local rows = FT.Port.Rows()
    for _, h in ipairs(rows) do
        local g = FT.Port.Group(h.id) or "other"
        p.held[g] = (p.held[g] or 0) + h.value
        p.worth = p.worth + h.value
    end
    p.gold = FT.Port.Gold()
    p.watching = 0
    for _ in pairs(FT.db.watch or {}) do p.watching = p.watching + 1 end

    -- the roles, each from its own evidence (a profession counts more the higher it is; what you do counts most)
    local gatherScore, craftScore, tradeScore = 0, 0, 0
    for _, g in pairs(p.gather) do gatherScore = gatherScore + math.min(g.rank, 300) / 100 end
    local lootedN = 0
    for _, n in pairs(p.looted) do lootedN = lootedN + n end
    p.lootedN = lootedN
    gatherScore = gatherScore + math.min(lootedN / 200, 4)
    for prof, c in pairs(p.craft) do
        -- cooking and a low profession count little: most players have one
        craftScore = craftScore + math.min(c.rank, 300) / (prof == "Cooking" and 300 or 100)
    end
    craftScore = craftScore + math.min(known / 40, 2)
    tradeScore = math.min(p.flips / 3, 4) + math.min(bought / 15, 2)
    p.scores = { gatherer = gatherScore, crafter = craftScore, trader = tradeScore }
    local roles = {}
    for role, v in pairs(p.scores) do
        if v >= 1.5 then roles[#roles + 1] = role end
    end
    table.sort(roles, function(a, b) return p.scores[a] > p.scores[b] end)
    -- no clear role yet: the best guess from what's there - the strongest evidence, else what you hold
    if #roles == 0 then
        local top, best = nil, 0
        for role, v in pairs(p.scores) do if v > best then top, best = role, v end end
        if top then
            roles = { top }
        elseif (p.held.mat or 0) > (p.held.gear or 0) and (p.held.mat or 0) > 0 then
            roles = { "collector" }
        elseif p.worth > 0 or p.gold > 0 then
            roles = { "saver" }
        else
            roles = { "newcomer" }
        end
    end
    p.roles = roles
    -- what you're into: the kind (herbs, ore, leather...) most of what you hold and watch is
    local kinds = {}
    for _, h in ipairs(rows) do
        local k = KindOf(h.id)
        if k then kinds[k] = (kinds[k] or 0) + h.value end
    end
    for id in pairs(FT.db.watch or {}) do
        local k = KindOf(id)
        if k then kinds[k] = (kinds[k] or 0) + (FT.Price(id) or 0) * 20 end
    end
    local into, intoV = nil, 0
    for k, v in pairs(kinds) do if v > intoV then into, intoV = k, v end end
    p.into = into
    p.isGatherer = p.scores.gatherer >= 1.5
    p.isCrafter = p.scores.crafter >= 1.5 and known > 0
    p.isTrader = p.scores.trader >= 1.5
    -- the best guess counts too: some evidence of one thing, and nothing of the others
    if roles[1] == "gatherer" then p.isGatherer = true end
    if roles[1] == "crafter" and known > 0 then p.isCrafter = true end
    if roles[1] == "trader" then p.isTrader = true end
    profile, profileAt = p, GetTime()
    return p
end

local ROLE_WORD = { gatherer = "Gatherer", crafter = "Crafter", trader = "Trader", collector = "Collector",
    saver = "Saver", newcomer = "New to the market" }

-- "Gatherer: Herbalism 300, Mining 285 (Raja) · 1,240 herbs and ore this week · no crafters · 3,200g in materials ·
-- watching 6" - what it sees, in one line
function E.ProfileText()
    local p = E.Profile()
    local bits = {}
    local names = {}
    for i = 1, math.min(2, #p.roles) do names[i] = L[ROLE_WORD[p.roles[i]] or p.roles[i]] end
    local who = table.concat(names, " & ")
    local profs = {}
    local function AddProfs(set)
        for prof, x in pairs(set) do
            if not (prof == "Cooking" and x.rank < 150) and prof ~= "Fishing" then
                profs[#profs + 1] = { L[prof] .. " " .. x.rank, x.rank }
            end
        end
    end
    AddProfs(p.gather)
    AddProfs(p.craft)
    table.sort(profs, function(a, b) return a[2] > b[2] end)
    local list = {}
    for i = 1, math.min(3, #profs) do list[i] = profs[i][1] end
    bits[#bits + 1] = FT.C("accent", who) .. (#list > 0 and (": " .. table.concat(list, ", ")) or "")
    if p.lootedN >= 20 then
        local kinds = {}
        for k, n in pairs(p.looted) do kinds[#kinds + 1] = { k, n } end
        table.sort(kinds, function(a, b) return a[2] > b[2] end)
        local words = {}
        for i = 1, math.min(2, #kinds) do words[i] = L[KIND_WORD[kinds[i][1]] or kinds[i][1]] end
        bits[#bits + 1] = string.format(L["%s %s gathered this week"], Thousand(p.lootedN), table.concat(words, L[" and "]))
    end
    if not next(p.craft) then
        bits[#bits + 1] = L["no crafters"]
    elseif p.recipes == 0 then
        -- a profession, but its recipes never seen: they're read when its window opens
        bits[#bits + 1] = L["open your profession window once so it knows your recipes"]
    end
    if p.flips >= 2 then bits[#bits + 1] = string.format(L["%d flips in two weeks"], p.flips) end
    if (p.held.mat or 0) >= 10000 then
        bits[#bits + 1] = string.format(L["%s in materials"], FT.Money(math.floor(p.held.mat), "short"))
    end
    if p.into and not (p.lootedN >= 20) then bits[#bits + 1] = string.format(L["into %s"], L[KIND_WORD[p.into] or p.into]) end
    if p.watching > 0 then bits[#bits + 1] = string.format(L["watching %d"], p.watching) end
    return table.concat(bits, FT.C("dim", "  ·  "))
end

---------------------------------------------------------------------------
-- Your moves: each one { id, kind, label, gold (what it's worth to you), text, why }
---------------------------------------------------------------------------
local MIN_GOLD = 50000        -- 5g: smaller isn't worth a card
local CHAT_GOLD = 200000      -- 20g: smaller isn't worth a line in chat
local FLIP_MIN = 100000       -- a flip worth 10g at least

local function Link(id)
    local _, _, _, _, link = FT.Item(id)
    return link or FT.ItemText(id)
end

-- how many you could sell in a couple of days without crashing it: what sells, a fair share
local function Sellable(id, have)
    local rate = FT.Sales.Rate(id)
    local perDay = rate and rate.perDay
    if not perDay or perDay <= 0 then return have end
    return math.max(1, math.min(have, math.ceil(perDay * 2 * 0.5)))
end

-- what you hold: sell high, sliding, a big move today
local function FromHoldings(out, p)
    for _, h in ipairs(FT.Port.Rows()) do
        local s, qty = h.stats, h.qty
        local avg = s.avg
        if h.value >= MIN_GOLD then
            if (h.signal == "SELL" or h.signal == "TRIM") and (h.strength or 0) >= 2 then
                local n = h.signal == "TRIM" and math.max(1, math.floor(qty / 2)) or Sellable(h.id, qty)
                local gain = avg and avg > 0 and (s.price - avg) * n or h.value * (s.dev or 0.1)
                out[#out + 1] = {
                    id = h.id, kind = "SELL", label = L["SELL NOW"], gold = math.max(gain, 0),
                    text = string.format(L["Sell %s of your %s %s at ~%s"], Thousand(n), Thousand(qty), Link(h.id),
                        FT.Money(s.sale or s.price, "short")),
                    why = h.reason,
                    value = "+" .. FT.Money(math.floor(math.max(gain, 0)), "short"),
                }
            elseif s.ch7 and s.ch7 <= -0.15 and (s.falling or (s.ch1 or 0) < 0) then
                local loss = h.value * math.min(-s.ch7, 0.3)
                out[#out + 1] = {
                    id = h.id, kind = "SLIDING", label = L["DROPPING"], gold = loss * 0.6,
                    text = string.format(L["Your %s %s is down %s this week and still falling"], Thousand(qty), Link(h.id),
                        FT.Pct(s.ch7)),
                    why = L["Selling now keeps what it's worth today; another week like this one costs about"] .. " "
                        .. FT.Money(math.floor(loss), "short") .. ".",
                    value = FT.Money(math.floor(h.value), "short"),
                }
            elseif s.ch1 and math.abs(s.ch1) >= 0.15 and h.value * math.abs(s.ch1) >= CHAT_GOLD then
                local moved = h.value - h.value / (1 + s.ch1)
                local up = s.ch1 > 0
                out[#out + 1] = {
                    id = h.id, kind = up and "UP" or "DOWN", label = up and L["UP TODAY"] or L["DOWN TODAY"],
                    gold = math.abs(moved) * 0.4,
                    text = string.format(up and L["Your %s %s jumped %s today"] or L["Your %s %s fell %s today"],
                        Thousand(qty), Link(h.id), FT.Pct(s.ch1)),
                    why = (h.reason and h.reason ~= "") and (L["The call"] .. ": " .. h.reason) or nil,
                    value = (up and "+" or "-") .. FT.Money(math.floor(math.abs(moved)), "short"),
                }
            end
        end
    end
end

-- your watchlist: a buy window
local function FromWatch(out)
    for id in pairs(FT.db.watch or {}) do
        local s = FT.An.Stats(id)
        if s.price and s.avg and s.avg > 0 and s.price <= s.avg * 0.85 and FT.An.Health(s) ~= "dumping" then
            local rate = FT.Sales.Rate(id)
            if rate and (rate.perDay or 0) >= 1 then
                local n = math.min(math.ceil(rate.perDay), 20)
                out[#out + 1] = {
                    id = id, kind = "WATCH", label = L["BUY WINDOW"], gold = (s.avg - s.price) * n,
                    text = string.format(L["%s, on your watchlist, is %s under usual"], Link(id), FT.Pct(s.price / s.avg - 1)),
                    why = string.format(L["~%s now against ~%s usually; it sells about %s a day."],
                        FT.Money(s.price, "short"), FT.Money(math.floor(s.avg), "short"), Thousand(rate.perDay)),
                    value = FT.Money(s.price, "short"),
                }
            end
        end
    end
end

-- what your own characters can make from what you hold (crafters, and miners smelting their own ore)
local function FromCrafts(out, p)
    local list = FT.Craft.ProfitCrafts and FT.Craft.ProfitCrafts()
    if not list then return end
    local held = FT.Port.Holdings()
    for _, c in ipairs(list) do
        if c.known and c.mode == "sell" and (c.perDay or 0) >= 1 then
            local r = c.recipe
            -- crafts your materials cover: every material that isn't sold by vendors, from what you hold
            local can, mine = math.huge, nil
            for _, rg in ipairs(r.reagents or {}) do
                if rg.itemID and not FT.VENDOR_REAGENTS[rg.itemID] then
                    local have = held[rg.itemID] and held[rg.itemID].total or 0
                    can = math.min(can, math.floor(have / math.max(rg.qty or 1, 1)))
                    if have > 0 and (not mine or have > mine.n) then mine = { id = rg.itemID, n = have } end
                end
            end
            if can ~= math.huge and can >= 1 and mine then
                local n = math.min(can, math.max(1, math.floor((c.perDay or 1) * 2 / (r.outputQty or 1))))
                local gain = c.profit * n
                local who = FT.Craft.KnownByText(r)
                if who == "" then who = L["One of your characters"] end
                out[#out + 1] = {
                    id = c.id, kind = "CRAFT", label = L["CRAFT IT"], gold = gain, from = mine.id,
                    text = string.format(L["Your %s make %s %s: +%s over selling them"], Link(mine.id), Thousand(n * (r.outputQty or 1)),
                        Link(c.id), FT.Money(math.floor(gain), "short")),
                    why = string.format(L["%s knows it. Profit %s a craft; it sells about %s a day."], who,
                        FT.Money(math.floor(c.profit), "short"), Thousand(c.perDay)),
                    value = "+" .. FT.Money(math.floor(gain), "short"),
                }
            end
        end
    end
end

-- gatherers: the best thing to gather for the professions you have (and that you already gather, first)
local function FromGathering(out, p)
    if not p.isGatherer then return end
    local yours = FT.Tabs and FT.Tabs.signals and FT.Tabs.signals.FarmYours
    if not yours then return end
    local looted = E.Looted(14)
    local best
    for _, r in ipairs(FT.Market.Rows() or {}) do
        -- the market row knows its class already (no lookup for 7,000 items)
        local k = r.price and not r.gone and KindOf(r.id, r.cls, r.sub)
        if k and p.kinds[k] then
            local rate = FT.Sales.Rate(r.id)
            local perDay = rate and rate.perDay or 0
            if perDay >= 20 then
                local v = yours(r.price, perDay) * (looted[r.id] and 1.5 or 1)
                if not best or v > best.v then best = { r = r, v = v, perDay = perDay, k = k, did = looted[r.id] } end
            end
        end
    end
    if best then
        out[#out + 1] = {
            id = best.r.id, kind = "FARM", label = L["GATHER"], gold = best.v * 0.5,
            text = string.format(L["Best %s to gather now: %s, ~%s each, ~%s sell a day"], L[KIND_WORD[best.k] or best.k],
                Link(best.r.id), FT.Money(best.r.price, "short"), Thousand(best.perDay)),
            why = (best.did and string.format(L["You gathered %s of it in two weeks. "], Thousand(best.did)) or "")
                .. string.format(L["Selling a share of each day's sales, about %s a day."], FT.Money(math.floor(best.v / (best.did and 1.5 or 1)), "short")),
            value = FT.Money(best.r.price, "short"),
        }
    end
end

-- traders: the best flip your gold covers
local function FromDeals(out, p)
    if not p.isTrader then return end
    local best
    for _, d in ipairs(FT.Deals.List() or {}) do
        if d.kind == "RESELL" and (d.profit or 0) >= FLIP_MIN and (d.cost or 0) <= p.gold then
            if not best or d.profit > best.profit then best = d end
        end
    end
    if best then
        out[#out + 1] = {
            id = best.id, kind = "FLIP", label = best.kind == "HOUSES" and L["AH TO AH"] or L["FLIP IT"], gold = best.profit,
            text = string.format(L["Buy %s %s for %s, sell for +%s"], Thousand(best.qty or 1), Link(best.id),
                FT.Money(math.floor(best.cost or 0), "short"), FT.Money(math.floor(best.profit), "short")),
            why = string.format(L["Your gold covers it. You flipped %d items in two weeks."], p.flips),
            value = "+" .. FT.Money(math.floor(best.profit), "short"),
        }
    end
end

-- the raids ahead (FT.Futures): a gatherer holding a key material - hold it, or sell it in raid week; a crafter
-- who knows a recipe on the raid list - the best of those to craft
local function FromFutures(out, p)
    local Fu = FT.Futures
    if not (Fu and FT.FUTURES) then return end
    local days = Fu.Days()
    if p.isGatherer then
        local best
        for _, x in ipairs(Fu.Materials(10)) do
            local price = x.market.price
            if x.held >= 20 and price and (x.move == "HOLD" or x.move == "SELL") then
                local value = price * x.held
                if not best or value > best.value then best = { x = x, value = value } end
            end
        end
        if best then
            local x = best.x
            local sell = x.move == "SELL"
            out[#out + 1] = {
                id = x.id, kind = sell and "RAIDSELL" or "RAIDHOLD", label = sell and L["SELL FOR RAID"] or L["HOLD FOR RAID"],
                gold = best.value * (sell and 0.3 or 0.15),
                text = sell and string.format(L["Raid week: sell your %s %s, it goes into %d raid consumables"], Thousand(x.held), Link(x.id), #x.into)
                    or string.format(L["Hold your %s %s: it goes into %d raid consumables, the raids open in %s days"], Thousand(x.held),
                        Link(x.id), #x.into, days and tostring(days) or "?"),
                why = string.format(L["%s this week. Consumables and their herbs usually climb toward raid night."], FT.Pct(x.market.ch7 or 0)),
                value = FT.Money(math.floor(best.value), "short"),
            }
        end
    end
    local bestCraft
    for _, c in ipairs(Fu.Consumables()) do
        if c.move == "CRAFT" and c.recipe and next(c.recipe.knownBy or {}) then
            local e = FT.Craft.Eval(c.recipe)
            local profit = e and e.revenue and e.cost and (e.revenue - e.cost) or 0
            local n = math.min((c.market.perDay or 0) * 0.2, 20)
            if profit > 0 and n >= 1 and (not bestCraft or profit * n > bestCraft.gain) then
                bestCraft = { c = c, gain = profit * n, profit = profit }
            end
        end
    end
    if bestCraft then
        local c = bestCraft.c
        out[#out + 1] = {
            id = c.id, kind = "RAIDCRAFT", label = L["CRAFT FOR RAID"], gold = bestCraft.gain,
            text = string.format(L["#%d on the raid list: craft %s, +%s a craft"], c.rank, Link(c.id), FT.Money(math.floor(bestCraft.profit), "short")),
            why = string.format(L["%s knows it. Used by %s; it sells about %s a day."], FT.Craft.KnownByText(c.recipe), c.c.roles,
                Thousand(c.market.perDay or 0)),
            value = "+" .. FT.Money(math.floor(bestCraft.gain), "short"),
        }
    end
end

-- the moves, the most gold to you first, one per item
function E.Moves(n)
    local p = E.Profile()
    local out = {}
    for _, f in ipairs({ FromHoldings, FromWatch, FromCrafts, FromGathering, FromDeals, FromFutures }) do
        local ok, err = pcall(f, out, p)
        if not ok then FT.Debug("eye:", err) end
    end
    table.sort(out, function(a, b) return a.gold > b.gold end)
    -- the raids ahead: one raid move always makes the top three (holding herbs is worth less gold today than a
    -- sale, but it's the move that matters before raid week)
    local raid
    for _, m in ipairs(out) do
        if m.kind:find("^RAID") and m.gold >= MIN_GOLD then raid = m break end
    end
    local kept, seen = {}, {}
    for _, m in ipairs(out) do
        local key = m.from or m.id
        if m.gold >= MIN_GOLD and not seen[key] and not seen[m.id] then
            seen[key], seen[m.id] = true, true
            kept[#kept + 1] = m
            if n and #kept >= n then break end
        end
    end
    if raid and n and n >= 3 then
        local has = false
        for _, m in ipairs(kept) do if m == raid then has = true end end
        if not has then
            -- in the last place (another move for the same item goes)
            for i = #kept, 1, -1 do
                if kept[i].id == raid.id or (kept[i].from and kept[i].from == raid.id) then table.remove(kept, i) end
            end
            if #kept >= n then kept[n] = raid else kept[#kept + 1] = raid end
        end
    end
    return kept
end

---------------------------------------------------------------------------
-- Chat: rarely, and only once it knows enough
---------------------------------------------------------------------------
local function Said()
    local today = FT.Day()
    local s = FT.db.eyeSaid
    if type(s) ~= "table" or s.day ~= today then
        s = { day = today }
        FT.db.eyeSaid = s
    end
    return s
end

-- the moves not said today (or said, and worth half as much again since)
local function Fresh(moves)
    local said, out = Said(), {}
    for _, m in ipairs(moves) do
        local key = m.kind .. ":" .. m.id
        if m.gold >= CHAT_GOLD and (not said[key] or m.gold >= said[key] * 1.5) then out[#out + 1] = m end
    end
    return out
end

local function Tell(moves, intro)
    local said = Said()
    if intro then FT.Print(intro) end
    for i, m in ipairs(moves) do
        if i > 3 then break end
        said[m.kind .. ":" .. m.id] = m.gold
        FT.Print("  " .. FT.C("accent", m.label) .. "  " .. m.text)
    end
end

-- after login: the portfolio since last time, what it sees of you (once a day), and up to three moves
function E.LoginNote()
    if FT.S.eyeChat == false then return end
    local p = E.Profile()
    local r = FT.db.recap or {}
    FT.db.recap = r
    local worth = p.worth + p.gold
    local head = FT.C("accent", L["The wolf"]) .. "  " .. string.format(L["Portfolio %s"], FT.Money(math.floor(worth), "short"))
    if r.worth and r.worth > 0 and math.abs(worth / r.worth - 1) >= 0.001 then
        head = head .. " " .. FT.Pct(worth / r.worth - 1) .. FT.C("dim", " " .. L["since last time"])
    end
    r.worth, r.t = worth, time()
    local said = Said()
    if not said.profile then
        said.profile = true
        head = head .. FT.C("dim", "  ·  ") .. E.ProfileText()
    end
    local moves = Fresh(E.Moves(6))
    if #moves == 0 then
        FT.Print(head .. FT.C("dim", "  ·  " .. L["nothing needs you right now"]))
        return
    end
    Tell(moves, head)
end

-- after the auction house: only what's new since
function E.AfterAH()
    if FT.S.eyeChat == false then return end
    local moves = Fresh(E.Moves(6))
    if #moves == 0 then return end
    Tell(moves, FT.C("accent", L["The wolf"]) .. "  " .. L["after that visit:"])
end

-- it waits for what it needs: the prices (the market built), your bags read, the crafts worked out - or a
-- minute and a half, whichever first - and a little more, so the login spam of other addons is past
local loginDone, marketReady, craftsReady, loginAt
FT.On("FT_READY", function() loginAt = GetTime() end)
local function MaybeLogin()
    if loginDone or not (marketReady and loginAt) then return end
    local waited = GetTime() - loginAt
    if not craftsReady and waited < 90 then return end
    loginDone = true
    C_Timer.After(math.max(0, 20 - waited), function() pcall(E.LoginNote) end)
end
FT.On("FT_MARKET_READY", function()
    marketReady = true
    -- what it sees of you, worked out in the background once the prices are known (before anything asks)
    C_Timer.After(2, function() pcall(E.Profile) end)
    -- the crafts list: asked for now (it's worked out in the background)
    if FT.Craft.ProfitCrafts then FT.Craft.ProfitCrafts() end
    MaybeLogin()
    C_Timer.After(91, MaybeLogin)
end)
FT.On("FT_CRAFTS_READY", function()
    craftsReady = true
    MaybeLogin()
end)

local ahOpenedAt
FT.On("AUCTION_HOUSE_SHOW", function() ahOpenedAt = GetTime() end)
FT.On("AUCTION_HOUSE_CLOSED", function()
    -- a real visit (a minute or a scan), then a moment for the prices it brought to be counted
    if not ahOpenedAt or GetTime() - ahOpenedAt < 45 then return end
    ahOpenedAt = nil
    C_Timer.After(8, function() pcall(E.AfterAH) end)
end)
