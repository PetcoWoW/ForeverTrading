-- Wolf of Booty Bay (built on ForeverTrading): what your characters own (bags, bank, mail) and what it is worth at market prices.
local ADDON, FT = ...

local P = {}
FT.Port = P

local holdings = nil
FT.On("FT_INVENTORY_CHANGED", function() holdings = nil end)
FT.On("FT_SOURCES_CHANGED", function() holdings = nil end)

-- itemID -> { id, total, chars = { [name] = { bags, bank, mail } } }
function P.Holdings()
    if holdings then return holdings end
    local out = {}
    local function Add(name, id, n, where)
        if type(id) ~= "number" or type(n) ~= "number" or n <= 0 then return end
        local h = out[id]
        if not h then
            h = { id = id, total = 0, chars = {} }
            out[id] = h
        end
        h.total = h.total + n
        local c = h.chars[name]
        if not c then
            c = { bags = 0, bank = 0, mail = 0 }
            h.chars[name] = c
        end
        c[where] = c[where] + n
    end
    local seen, mailSeen = {}, {}
    -- our own reading (soulbound items left out)
    for guid, inv in pairs(FT.db.inv) do
        local c = FT.db.chars[guid]
        if c and c.side == FT.sideKey and type(inv) == "table" then
            seen[guid] = true
            for id, n in pairs(inv.bags or {}) do Add(c.name or "?", id, n, "bags") end
            for id, n in pairs(inv.bank or {}) do Add(c.name or "?", id, n, "bank") end
            if inv.mailT then
                mailSeen[guid] = true
                for id, n in pairs(inv.mail or {}) do Add(c.name or "?", id, n, "mail") end
            end
        end
    end
    holdings = out
    return out
end

function P.EachHolding(fn)
    for id in pairs(P.Holdings()) do fn(id) end
end

function P.Count(itemID)
    local h = P.Holdings()[itemID]
    return h and h.total or 0
end

-- gold of this side's characters
function P.Gold()
    local total, seen = 0, {}
    if FT.charKey then
        total = GetMoney()
        seen[FT.charKey] = true
    end
    for guid, c in pairs(FT.db.chars) do
        if not seen[guid] and c.side == FT.sideKey and type(c.money) == "number" then
            total = total + c.money
            seen[guid] = true
        end
    end
    return total
end

-- priced holdings, the most valuable first: { id, qty, price, value, ch7, stats, signal, reason, chars }
function P.Rows()
    local out, total, total7 = {}, 0, 0
    for id, h in pairs(P.Holdings()) do
        local s = FT.An.Stats(id)
        if s.price then
            local value = s.price * h.total
            local signal, strength, reason = FT.An.SellSignal(s)
            out[#out + 1] = { id = id, qty = h.total, price = s.price, value = value, ch7 = s.ch7, stats = s,
                signal = signal, strength = strength, reason = reason, chars = h.chars }
            total = total + value
            total7 = total7 + (s.ch7 and value / (1 + s.ch7) or value)
        end
    end
    table.sort(out, function(a, b) return a.value > b.value end)
    return out, total, total7
end

-- worth of today's holdings on each of the last `days` days: { { t, value } }
function P.History(days)
    days = days or 14
    local today = FT.Day()
    local sums = {}
    for id, h in pairs(P.Holdings()) do
        local daily = FT.Hist.Daily(id, days + 3)
        if #daily > 0 then
            -- before its first known day an item counts at its first price (no false jump in the chart)
            local k, last = 1, daily[1].c
            for day = today - days + 1, today do
                while daily[k] and daily[k].day <= day do
                    last = daily[k].c
                    k = k + 1
                end
                if last then sums[day] = (sums[day] or 0) + last * h.total end
            end
        end
    end
    local out = {}
    for day = today - days + 1, today do
        if sums[day] then out[#out + 1] = { t = FT.DayStart(day), value = sums[day] } end
    end
    return out
end
