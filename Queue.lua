-- ForeverTrading: the craft queue - recipes and how many crafts of each, and what to buy for them: every material
-- of the queue together, less what this character has in its bags and bank, each at its cheapest (the auction
-- house walked up its order book for the whole amount, a vendor, or crafting it yourself), with what the crafts
-- bring and how long they take to sell (FT.Sales). Kept per server and side.
local ADDON, FT = ...

local Q = {}
FT.Queue = Q

local GetCount = (C_Item and C_Item.GetItemCount) or GetItemCount

local function Store()
    local r = FT.Side()
    r.queue = r.queue or {}
    return r.queue
end

local function Changed()
    FT.Debounce("queueChanged", 0.1, function() FT.Fire("FT_QUEUE_CHANGED") end)
end

-- how many crafts of a recipe are queued (0: none)
function Q.Count(key)
    return key and Store()[key] or 0
end

function Q.Set(key, crafts)
    if not key then return end
    crafts = math.floor(crafts or 0)
    Store()[key] = crafts > 0 and math.min(crafts, 9999) or nil
    Changed()
end

function Q.Add(key, crafts)
    Q.Set(key, Q.Count(key) + (crafts or 1))
end

function Q.Clear()
    wipe(Store())
    Changed()
end

-- how many recipes are queued
function Q.Size()
    local n = 0
    for _ in pairs(Store()) do n = n + 1 end
    return n
end

-- What the queue takes and brings:
--   rows   { r, e, crafts, makes, profit, revenue, days (to sell what it makes, when sales are known) }
--   mats   { id, need, have, buy, unit, source, via, cost (nil: no price) } - most costly first
--   totals { buy (the materials to buy), revenue, profit, crafts, missing (materials with no price) }
function Q.Plan()
    local rows, byMat, mats = {}, {}, {}
    local totals = { buy = 0, revenue = 0, profit = 0, crafts = 0, missing = 0 }
    for key, crafts in pairs(Store()) do
        local r = FT.Craft.Find(key)
        if r then
            local e = FT.Craft.Eval(r)
            local makes = crafts * r.outputQty
            local row = { r = r, e = e, crafts = crafts, makes = makes, profit = e.profit and e.profit * crafts or nil,
                revenue = e.revenue and e.revenue * crafts or nil }
            local sales = e.stats and e.stats.sales
            if sales and sales.perDay > 0 then row.days = makes / sales.perDay end
            rows[#rows + 1] = row
            totals.crafts = totals.crafts + crafts
            totals.revenue = totals.revenue + (row.revenue or 0)
            totals.profit = totals.profit + (row.profit or 0)
            for _, part in ipairs(e.parts or {}) do
                local m = byMat[part.itemID]
                if not m then
                    m = { id = part.itemID, need = 0, source = part.source, via = part.via, unit = part.unit }
                    byMat[part.itemID] = m
                    mats[#mats + 1] = m
                end
                m.need = m.need + (part.qty or 1) * crafts
            end
        end
    end
    for _, m in ipairs(mats) do
        m.have = GetCount and GetCount(m.id, true) or 0
        m.buy = math.max(0, m.need - m.have)
        if m.buy > 0 and m.unit then
            -- at the auction house the whole amount walks up the order book (a few cheap lots aren't the price of all)
            local cost = (m.source == "ah") and FT.Hist.CostToBuy(m.id, m.buy) or nil
            m.cost = cost or m.unit * m.buy
        elseif m.buy == 0 then
            m.cost = 0
        end
        if m.cost then totals.buy = totals.buy + m.cost elseif m.buy > 0 then totals.missing = totals.missing + 1 end
    end
    table.sort(rows, function(a, b) return (a.profit or -math.huge) > (b.profit or -math.huge) end)
    table.sort(mats, function(a, b)
        if (a.buy > 0) ~= (b.buy > 0) then return a.buy > 0 end
        return (a.cost or 0) > (b.cost or 0)
    end)
    return rows, mats, totals
end

-- a recipe gone (Mastercraft forgot it, a character dropped the profession): out of the queue
FT.On("FT_RECIPES_CHANGED", function()
    C_Timer.After(1, function()
        if not FT.db then return end
        local gone = false
        for key in pairs(Store()) do
            if not FT.Craft.Find(key) then
                Store()[key] = nil
                gone = true
            end
        end
        if gone then Changed() end
    end)
end)
