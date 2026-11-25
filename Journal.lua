-- Wolf of Booty Bay: the deals journal - what you really bought and sold at the auction house, and what it brought.
-- The auction house's mail says it exactly (its invoice: the price, the cut, the deposit back, how many, who),
-- read when you open your mailbox; the deposits of what you post here are written when you post. Kept per server
-- and side (all your characters, both auction houses), 90 days. The cut is learned per house (by the letter's
-- sender: Blackwater signs with its name).
--   S sold: v = the price, f = the cut          B bought: v = the price paid
--   D deposit paid: v                            R deposit back (with a sale): v
--   X expired, C cancelled (came back by mail): how many
local ADDON, FT = ...
local L = FT.L

local J = {}
FT.Journal = J

local KEEP = 90 * 86400
local MAX_EVENTS = 4000

local events      -- parsed: { { t, k, id, q, v, f }, ... } oldest first
local Enc, Dec = FT.Hist.Enc, FT.Hist.Dec

local function R()
    local r = FT.Side()
    r.journal = r.journal or ""
    r.journalSeen = r.journalSeen or {}
    return r
end

local function Load()
    if events then return events end
    events = {}
    for rec in R().journal:gmatch("([^;]+);") do
        local t, k, id, q, v, f = rec:match("^(%w+),(%a),(%w*),(%w*),(%w*),(%w*)$")
        if t then
            local e = { t = Dec(t), k = k, id = Dec(id), q = Dec(q) or 0, v = Dec(v) or 0, f = Dec(f) or 0 }
            -- a sale or a purchase written with no count (Forever's letters say 0): one
            if (k == "S" or k == "B") and e.q <= 0 then e.q = 1 end
            events[#events + 1] = e
        end
    end
    return events
end

local function Save()
    local cutoff = time() - KEEP
    local first = 1
    while events[first] and (events[first].t < cutoff or #events - first + 1 > MAX_EVENTS) do first = first + 1 end
    local kept, parts = {}, {}
    for i = first, #events do
        local e = events[i]
        kept[#kept + 1] = e
        parts[#parts + 1] = Enc(e.t) .. "," .. e.k .. "," .. (e.id and Enc(e.id) or "") .. "," .. Enc(e.q) .. ","
            .. Enc(e.v) .. "," .. Enc(e.f) .. ";"
    end
    events = kept
    R().journal = table.concat(parts)
end

-- one event (kind as above); said to the pages
function J.Add(k, itemID, qty, value, fee, t)
    Load()
    local e = { t = t or time(), k = k, id = itemID, q = math.floor((qty or 0) + 0.5), v = math.floor((value or 0) + 0.5),
        f = math.floor((fee or 0) + 0.5) }
    -- in time order (a mail read late is of its own time)
    local i = #events
    while i > 0 and events[i].t > e.t do i = i - 1 end
    table.insert(events, i + 1, e)
    Save()
    FT.Debounce("journalChanged", 0.5, function() FT.Fire("FT_JOURNAL_CHANGED") end)
end

---------------------------------------------------------------------------
-- The auction house's mail
---------------------------------------------------------------------------
-- "Auction successful: %s" and the others, as patterns (the game's own words, in its language)
local function Pattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local p = fmt:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    return "^" .. p:gsub("%%%%s", "(.+)") .. "$"
end
local SUBJECTS = {
    { "sold", Pattern(AUCTION_SOLD_MAIL_SUBJECT) }, { "won", Pattern(AUCTION_WON_MAIL_SUBJECT) },
    { "expired", Pattern(AUCTION_EXPIRED_MAIL_SUBJECT) }, { "cancelled", Pattern(AUCTION_REMOVED_MAIL_SUBJECT) },
}

local function Classify(subject)
    if type(subject) ~= "string" then return nil end
    for _, s in ipairs(SUBJECTS) do
        if s[2] then
            local name = subject:match(s[2])
            if name then return s[1], name end
        end
    end
    return nil
end

-- a mail read before (the same letter: its kind, item, buyer, price, count and the time it runs out - this last
-- within a few minutes, as the client counts it)
local function Seen(key, expires)
    local n = 0
    for _, e in ipairs(R().journalSeen[key] or {}) do
        if math.abs(e - expires) < 300 then n = n + 1 end
    end
    return n
end

local function MarkSeen(key, expires)
    local seen = R().journalSeen
    seen[key] = seen[key] or {}
    table.insert(seen[key], expires)
end

-- letters run out within 30 days: what they were known by goes after that
local function PruneSeen()
    local seen, now = R().journalSeen, time()
    for key, list in pairs(seen) do
        for i = #list, 1, -1 do
            if list[i] < now - 86400 then table.remove(list, i) end
        end
        if #list == 0 then seen[key] = nil end
    end
end

-- the item of a letter: its attachment, else the item of the name in the subject
local function ItemOf(i, name)
    -- the link says the item for sure; the count is the 4th answer of newer clients (name, itemID, texture,
    -- count), told by their 2nd being the same item
    local link = GetInboxItemLink and GetInboxItemLink(i, 1)
    local id = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
    if GetInboxItem then
        local a, b, _, d = GetInboxItem(i, 1)
        if id then return id, (b == id and type(d) == "number") and d or nil end
        if type(a) == "string" then name = a end
    end
    return id or (name and FT.NameIndex()[name]) or nil, nil
end

local function ReadMail()
    if not (GetInboxNumItems and GetInboxHeaderInfo and FT.db) then return end
    local now, n, added = time(), GetInboxNumItems() or 0, 0
    local index
    local twins = {} -- letters alike in this read (two auctions of one item ending together): each counts
    for i = 1, n do
        local _, _, sender, subject, money, _, daysLeft = GetInboxHeaderInfo(i)
        local kind, name = Classify(subject)
        if kind and type(daysLeft) == "number" then
            local expires = now + math.floor(daysLeft * 86400)
            -- the letter came about when it would run out less the time letters keep (30 days)
            local at = math.min(now, expires - 30 * 86400)
            local invType, invItem, buyer, bid, _, deposit, cut, _, _, count
            if GetInboxInvoiceInfo then invType, invItem, buyer, bid, _, deposit, cut, _, _, count = GetInboxInvoiceInfo(i) end
            name = invItem or name
            index = index or FT.NameIndex()
            local id = name and index[name]
            local key = table.concat({ kind, tostring(name), tostring(buyer), tostring(bid or money), tostring(count) }, "|")
            local twin = key .. "|" .. math.floor(expires / 300)
            twins[twin] = (twins[twin] or 0) + 1
            if twins[twin] > Seen(key, expires) then
                MarkSeen(key, expires)
                if kind == "sold" then
                    -- the cut this auction house takes: learned from the sale (a price large enough to tell it)
                    local field = (FT.House.OfSender(sender) == "neutral") and "cutSeenNeutral" or "cutSeen"
                    local seenCut = FT.db[field]
                    if bid and type(cut) == "number" and bid >= 1000 and not (seenCut and (seenCut.at or 0) > at) then
                        FT.db[field] = { rate = cut / bid, at = at }
                    end
                    if invType and bid then
                        -- how many: the letter's count when it says one (Forever's say 0 for an item sold whole)
                        J.Add("S", id, (type(count) == "number" and count > 0) and count or 1, bid, cut, at)
                        if deposit and deposit > 0 then J.Add("R", id, 0, deposit, 0, at) end
                    elseif type(money) == "number" and money > 0 then
                        -- no invoice to read: the gold that came (the price less the cut, with the deposit back)
                        J.Add("S", id, 1, money, 0, at)
                    end
                    added = added + 1
                elseif kind == "won" then
                    local itemID, qty = ItemOf(i, name)
                    if invType and bid then
                        J.Add("B", itemID or id, (type(count) == "number" and count > 0) and count or qty or 1, bid, 0, at)
                        added = added + 1
                    end
                else
                    local itemID, qty = ItemOf(i, name)
                    J.Add(kind == "expired" and "X" or "C", itemID or id, qty or 1, 0, 0, at)
                    added = added + 1
                end
            end
        end
    end
    if added > 0 then FT.Debug("journal:", added, "letters of the auction house written") end
    PruneSeen()
end

-- Read at once whenever the inbox changes, and the moment a letter is taken or deleted - before it goes ("Open all"
-- and mail addons' "Collect all" take letters faster than any wait); a letter read before isn't written twice.
FT.On("MAIL_INBOX_UPDATE", function() ReadMail() end)
FT.On("MAIL_SHOW", function()
    ReadMail()
    C_Timer.After(1, ReadMail)
end)
local hooked = false
FT.On("FT_READY", function()
    if hooked then return end
    hooked = true
    for _, name in ipairs({ "TakeInboxMoney", "TakeInboxItem", "AutoLootMailItem", "DeleteInboxItem" }) do
        if type(_G[name]) == "function" then
            hooksecurefunc(name, function() pcall(ReadMail) end)
        end
    end
end)

-- what you post here: its deposit
function J.Posted(itemID, qty, deposit)
    if deposit and deposit > 0 then J.Add("D", itemID, qty, deposit, 0) end
end

---------------------------------------------------------------------------
-- What it brought
---------------------------------------------------------------------------
-- Since `from` (time): totals { income (sold, the cut taken off), cut, spent (bought), deposits (paid), back
-- (deposits back), result, sold, bought, expired, cancelled } and per item rows { id, sold, income, bought, spent,
-- expired, cancelled, result, avgBuy, avgSell }
function J.Summary(from)
    local tot = { income = 0, cut = 0, spent = 0, deposits = 0, back = 0, sold = 0, bought = 0, expired = 0, cancelled = 0 }
    local byID, rows = {}, {}
    local function Row(id)
        local key = id or 0
        local r = byID[key]
        if not r then
            r = { id = id, sold = 0, income = 0, bought = 0, spent = 0, expired = 0, cancelled = 0, deposits = 0 }
            byID[key] = r
            rows[#rows + 1] = r
        end
        return r
    end
    for _, e in ipairs(Load()) do
        if e.t >= from then
            local r = Row(e.id)
            if e.k == "S" then
                local net = e.v - e.f
                r.sold, r.income = r.sold + e.q, r.income + net
                tot.sold, tot.income, tot.cut = tot.sold + e.q, tot.income + net, tot.cut + e.f
            elseif e.k == "B" then
                r.bought, r.spent = r.bought + e.q, r.spent + e.v
                tot.bought, tot.spent = tot.bought + e.q, tot.spent + e.v
            elseif e.k == "D" then
                r.deposits = r.deposits + e.v
                tot.deposits = tot.deposits + e.v
            elseif e.k == "R" then
                r.deposits = r.deposits - e.v
                tot.back = tot.back + e.v
            elseif e.k == "X" then
                r.expired, tot.expired = r.expired + e.q, tot.expired + e.q
            elseif e.k == "C" then
                r.cancelled, tot.cancelled = r.cancelled + e.q, tot.cancelled + e.q
            end
        end
    end
    for _, r in ipairs(rows) do
        r.result = r.income - r.spent - math.max(0, r.deposits)
        r.avgBuy = r.bought > 0 and r.spent / r.bought or nil
        r.avgSell = r.sold > 0 and r.income / r.sold or nil
    end
    -- deposits: what was paid and not given back (one posted in the game's window was never seen paid: its
    -- deposit back is no income)
    tot.lost = math.max(0, tot.deposits - tot.back)
    tot.result = tot.income - tot.spent - tot.lost
    return tot, rows
end

-- any event at all (the page says how to start when there are none)
function J.Empty()
    return #Load() == 0
end

FT.On("FT_DATA_CLEARED", function() events = nil end)
FT.On("FT_LOGIN", function() events = nil end)
