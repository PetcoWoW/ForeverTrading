-- Wolf of Booty Bay (built on ForeverTrading): Portfolio page - what your characters on this server own, valued at market prices.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local T = {}
FT.Tabs.portfolio = T

local state = { sort = "value", desc = true, days = 30, view = "portfolio", period = 7 }
local cards, chart, list, rangeSeg
local portfolioParts = {} -- what the Portfolio view shows (hidden in the Journal view)
local journal             -- the Journal view
local charsView           -- the Characters view
local sellView            -- the Sell yours view (what to do with each thing you own)
local sessView            -- the Sessions view (your farming runs)
local STALE_DAYS = 7      -- a character's bank or mailbox not seen for this long: its numbers are old

local function NameCell(row)
    local f = CreateFrame("Frame", nil, row)
    f:SetHeight(26)
    f.icon = UI.Icon(f, 20)
    f.icon:SetPoint("LEFT")
    f.text = UI.Text(f, 12, "text")
    f.text:SetPoint("LEFT", f.icon, "RIGHT", 8, 0)
    f.text:SetPoint("RIGHT")
    return f
end

local SORT_GET = {
    value = function(x) return x.value end,
    qty = function(x) return x.qty end,
    price = function(x) return x.price end,
    ch7 = function(x) return x.ch7 end,
    share = function(x) return x.value end,
}

function T.Build(p)
    local head = UI.Text(p, 16, "text")
    head:SetPoint("TOPLEFT", 12, -10)
    head:SetText(L["Portfolio"])
    local sub = UI.Text(p, 11, "dim")
    sub:SetPoint("LEFT", head, "RIGHT", 12, -1)
    sub:SetText(L["Bags, banks and mailboxes of your characters on this server, at auction house prices"])

    -- what you own, or what your trading brought (the deals journal)
    T.viewSeg = UI.Segmented(p, { { "portfolio", L["Holdings"] }, { "sell", L["Sell yours"] }, { "chars", L["Characters"] }, { "sessions", L["Sessions"] }, { "journal", L["Journal"] } }, function(v) T.SetView(v) end, 22)
    T.viewSeg:SetPoint("TOPRIGHT", -8, -8)
    T.viewSeg:SetValue(state.view)
    T.head, T.sub = head, sub

    cards = {}
    local titles = { L["Total worth"], L["Items"], L["Gold"], L["Positions"] }
    for i, t in ipairs(titles) do
        cards[i] = UI.Stat(p, t)
        cards[i]:SetHeight(64)
    end

    local chartTitle = UI.Text(p, 12, "text")
    chartTitle:SetText(L["Worth of what you own today, day by day"])
    rangeSeg = UI.Segmented(p, { { 14, L["14d"] }, { 30, L["30d"] }, { 60, L["60d"] } }, function(v)
        state.days = v
        T.DrawChart()
    end)
    rangeSeg:SetValue(state.days)
    chart = UI.Chart(p)
    UI.Border(chart, "line")

    local panel = UI.Panel(p, "bg1", "line")
    local cols = {
        { key = "name", title = L["Item"], width = "fill", make = NameCell, cellHeight = 26 },
        { key = "qty", title = L["Qty"], width = 64, justify = "RIGHT", sort = "qty" },
        { key = "price", title = L["Price"], width = 86, justify = "RIGHT", sort = "price" },
        { key = "value", title = L["Value"], width = 96, justify = "RIGHT", sort = "value" },
        { key = "ch7", title = L["7d"], width = 60, justify = "RIGHT", sort = "ch7" },
        { key = "share", title = L["Share"], width = 56, justify = "RIGHT", sort = "share" },
        { key = "signal", title = L["Signal"], width = 84, justify = "CENTER", make = function(row) return UI.Badge(row, 82, 18) end, cellHeight = 18 },
    }
    T.header = UI.Header(panel, cols, function(key)
        if state.sort == key then state.desc = not state.desc else state.sort, state.desc = key, true end
        T.header:SetSort(state.sort, state.desc)
        T.RefreshList()
    end)
    T.header:SetPoint("TOPLEFT", 1, -1)
    T.header:SetPoint("TOPRIGHT", -1, -1)
    T.header:SetSort(state.sort, state.desc)
    list = UI.List(panel, {
        rowHeight = 28, cols = cols,
        update = function(row, x)
            row.cells.name.icon:SetItem(x.id)
            row.cells.name.text:SetText(FT.ItemText(x.id, 40))
            row.cells.qty:SetText(FT.Num(x.qty))
            row.cells.price:SetText(FT.Money(x.price, "short"))
            row.cells.value:SetText(FT.Money(x.value, "short"))
            row.cells.ch7:SetText(FT.Pct(x.ch7))
            row.cells.share:SetText(T.total and T.total > 0 and string.format("%.1f%%", x.value / T.total * 100) or "")
            row.cells.signal:Set(x.signal, nil, x.strength)
        end,
        onClick = function(x)
            if not UI.ItemClick(x.id) then FT.OpenItem(x.id) end
        end,
        onEnter = function(row, x)
            UI.TipItem(row, x.id)
            GameTooltip:AddLine(" ")
            local names = {}
            for name in pairs(x.chars) do names[#names + 1] = name end
            table.sort(names)
            for _, name in ipairs(names) do
                local c = x.chars[name]
                local where = {}
                if c.bags > 0 then where[#where + 1] = L["bags"] .. " " .. c.bags end
                if c.bank > 0 then where[#where + 1] = L["bank"] .. " " .. c.bank end
                if c.mail > 0 then where[#where + 1] = L["mail"] .. " " .. c.mail end
                GameTooltip:AddDoubleLine(name, table.concat(where, ", "), 0.9, 0.9, 0.9, 0.6, 0.65, 0.7)
            end
            if x.reason then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(x.reason, 0.85, 0.87, 0.9, true)
            end
            GameTooltip:Show()
        end,
    })
    list:SetPoint("TOPLEFT", T.header, "BOTTOMLEFT", 0, -2)
    list:SetPoint("BOTTOMRIGHT", -1, 4)
    list:SetEmptyText(L["Nothing priced yet. Open your bags and bank once per character."])
    for _, c in ipairs(cards) do portfolioParts[#portfolioParts + 1] = c end
    for _, x in ipairs({ chartTitle, rangeSeg, chart, panel }) do portfolioParts[#portfolioParts + 1] = x end
    T.BuildJournal(p)
    T.BuildChars(p)
    T.BuildSell(p)
    T.BuildSessions(p)

    UI.OnSize(p, function(self, w, h)
        local cw = (w - 16 - 3 * 8) / 4
        for i, c in ipairs(cards) do
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", 8 + (i - 1) * (cw + 8), -38)
            c:SetWidth(cw)
        end
        chartTitle:ClearAllPoints()
        chartTitle:SetPoint("TOPLEFT", 12, -114)
        rangeSeg:ClearAllPoints()
        rangeSeg:SetPoint("TOPRIGHT", -8, -110)
        local chartH = math.max(140, math.floor((h - 140) * 0.38))
        chart:ClearAllPoints()
        chart:SetPoint("TOPLEFT", 8, -136)
        chart:SetPoint("TOPRIGHT", -8, -136)
        chart:SetHeight(chartH)
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", 8, -136 - chartH - 8)
        panel:SetPoint("BOTTOMRIGHT", -8, 8)
    end)
end

---------------------------------------------------------------------------
-- The deals journal (FT.Journal): what was bought and sold, and what it brought
---------------------------------------------------------------------------
local JSORT = {
    result = function(x) return x.result end, sold = function(x) return x.income end,
    bought = function(x) return x.spent end, expired = function(x) return x.expired + x.cancelled end,
}

function T.BuildJournal(p)
    local f = CreateFrame("Frame", nil, p)
    f:SetPoint("TOPLEFT", 0, -30)
    f:SetPoint("BOTTOMRIGHT", 0, 0)
    f:Hide()
    journal = f
    f.sort, f.desc = "result", true
    f.cards = {}
    for i, t in ipairs({ L["Sold"], L["Bought"], L["Deposits lost"], L["Result"] }) do
        f.cards[i] = UI.Stat(f, t)
        f.cards[i]:SetHeight(64)
    end
    f.period = UI.Segmented(f, { { 1, L["Today"] }, { 7, L["7d"] }, { 30, L["30d"] }, { 90, L["90d"] } }, function(v)
        state.period = v
        T.RefreshJournal()
    end, 22)
    f.period:SetValue(state.period)
    f.note = UI.Text(f, 11, "dim")
    if f.note.SetWordWrap then f.note:SetWordWrap(false) end
    f.note:SetText(L["From the auction house's letters, read when you open your mailbox; deposits of what you post here. The cut is taken off what sold."])
    local panel = UI.Panel(f, "bg1", "line")
    f.panel = panel
    local cols = {
        { key = "name", title = L["Item"], width = "fill", make = NameCell, cellHeight = 26 },
        { key = "bought", title = L["Bought"], width = 130, justify = "RIGHT", sort = "bought" },
        { key = "sold", title = L["Sold"], width = 130, justify = "RIGHT", sort = "sold" },
        { key = "avg", title = L["Bought / sold at"], width = 150, justify = "RIGHT" },
        { key = "result", title = L["Result"], width = 96, justify = "RIGHT", sort = "result" },
        { key = "expired", title = L["Back unsold"], width = 92, justify = "RIGHT", sort = "expired" },
    }
    f.header = UI.Header(panel, cols, function(key)
        if f.sort == key then f.desc = not f.desc else f.sort, f.desc = key, true end
        f.header:SetSort(f.sort, f.desc)
        T.RefreshJournal()
    end)
    f.header:SetPoint("TOPLEFT", 1, -1)
    f.header:SetPoint("TOPRIGHT", -1, -1)
    f.header:SetSort(f.sort, f.desc)
    local function QtyMoney(q, v)
        if q <= 0 and v <= 0 then return FT.C("dim", "—") end
        return FT.Num(q) .. FT.C("dim", " " .. L["pcs"] .. "  ") .. FT.Money(v, "short")
    end
    f.list = UI.List(panel, {
        rowHeight = 28, cols = cols,
        update = function(row, x)
            row.cells.name.icon:SetItem(x.id)
            row.cells.name.text:SetText(x.id and FT.ItemText(x.id, 40) or FT.C("dim", L["an item not known by name"]))
            row.cells.bought:SetText(QtyMoney(x.bought, x.spent))
            row.cells.sold:SetText(QtyMoney(x.sold, x.income))
            local buy = x.avgBuy and FT.Money(x.avgBuy, "short") or "—"
            local sell = x.avgSell and FT.Money(x.avgSell, "short") or "—"
            row.cells.avg:SetText((x.avgBuy or x.avgSell) and (buy .. FT.C("dim", " / ") .. sell) or FT.C("dim", "—"))
            local r = x.result
            row.cells.result:SetText(r == 0 and FT.C("dim", "0")
                or FT.C(r > 0 and "up" or "down", (r > 0 and "+" or "-") .. FT.Money(math.abs(r), "short")))
            local back = x.expired + x.cancelled
            row.cells.expired:SetText(back > 0 and FT.C("accent", FT.Num(back)) or FT.C("dim", "—"))
        end,
        onClick = function(x)
            if x.id and not UI.ItemClick(x.id) then FT.OpenItem(x.id) end
        end,
        onEnter = function(row, x)
            if x.id then UI.TipItem(row, x.id) else GameTooltip:SetOwner(row, "ANCHOR_RIGHT") end
            GameTooltip:AddLine(" ")
            if x.sold > 0 and x.bought == 0 then
                GameTooltip:AddLine(L["Sold, not bought at the auction house (crafted, farmed): its result is what it brought."], 0.85, 0.87, 0.9, true)
            end
            if x.deposits > 0 then
                GameTooltip:AddLine(string.format(L["Deposits lost: %s"], FT.Money(x.deposits)), 0.96, 0.6, 0.3, true)
            end
            if x.expired + x.cancelled > 0 then
                GameTooltip:AddLine(string.format(L["Came back unsold: %s expired, %s taken off"], FT.Num(x.expired), FT.Num(x.cancelled)),
                    0.85, 0.87, 0.9, true)
            end
            GameTooltip:Show()
        end,
    })
    f.list:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 0, -2)
    f.list:SetPoint("BOTTOMRIGHT", -1, 4)
    UI.OnSize(f, function(self, w)
        local cw = (w - 16 - 3 * 8) / 4
        for i, c in ipairs(self.cards) do
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", 8 + (i - 1) * (cw + 8), -8)
            c:SetWidth(cw)
        end
        self.period:ClearAllPoints()
        self.period:SetPoint("TOPRIGHT", -8, -82)
        self.note:ClearAllPoints()
        self.note:SetPoint("LEFT", self, "TOPLEFT", 12, -93)
        self.note:SetPoint("RIGHT", self.period, "LEFT", -12, 0)
        self.panel:ClearAllPoints()
        self.panel:SetPoint("TOPLEFT", 8, -110)
        self.panel:SetPoint("BOTTOMRIGHT", -8, 8)
    end)
end

function T.RefreshJournal()
    local f = journal
    if not (f and f:IsShown()) then return end
    local from = state.period == 1 and FT.DayStart(FT.Day()) or (time() - state.period * 86400)
    local tot, rows = FT.Journal.Summary(from)
    f.cards[1]:Set(FT.Money(tot.income, "short"), string.format(L["%s pcs, the cut %s"], FT.Num(tot.sold), FT.Money(tot.cut, "short")))
    f.cards[2]:Set(FT.Money(tot.spent, "short"), string.format(L["%s pcs"], FT.Num(tot.bought)))
    f.cards[3]:Set(FT.Money(tot.lost, "short"), string.format(L["paid %s, back %s"], FT.Money(tot.deposits, "short"), FT.Money(tot.back, "short")))
    local r = tot.result
    f.cards[4]:Set(FT.C(r >= 0 and "up" or "down", (r >= 0 and "+" or "-") .. FT.Money(math.abs(r), "short")),
        string.format(L["back unsold: %s expired, %s taken off"], FT.Num(tot.expired), FT.Num(tot.cancelled)))
    local get = JSORT[f.sort] or JSORT.result
    local missing = f.desc and -math.huge or math.huge
    table.sort(rows, function(a, b)
        local va, vb = get(a) or missing, get(b) or missing
        if va ~= vb then
            if f.desc then return va > vb end
            return va < vb
        end
        return (a.id or 0) < (b.id or 0)
    end)
    f.list:SetEmptyText(FT.Journal.Empty() and L["The journal fills from the auction house's letters: open your mailbox. What you post here writes its deposit."]
        or L["Nothing in this period."])
    f.list:SetItems(rows, true)
end

function T.SetView(view)
    state.view = view
    if T.viewSeg then T.viewSeg:SetValue(view) end
    local j, ch, sl, se = view == "journal", view == "chars", view == "sell", view == "sessions"
    for _, x in ipairs(portfolioParts) do x:SetShown(not j and not ch and not sl and not se) end
    if sessView then sessView:SetShown(se) end
    if journal then journal:SetShown(j) end
    if charsView then charsView:SetShown(ch) end
    if sellView then sellView:SetShown(sl) end
    T.head:SetText((j and L["Journal"]) or (ch and L["Characters"]) or (sl and L["Sell yours"]) or (se and L["Sessions"]) or L["Portfolio"])
    T.sub:SetText((j and L["What you bought and sold at the auction house, and what it brought"])
        or (ch and L["Every character on this server: gold, what it holds, when it was last seen"])
        or (sl and L["Everything you own and the best way to turn each into gold"])
        or (se and L["Your farming runs: what you looted, what it's worth now, gold an hour"])
        or L["Bags, banks and mailboxes of your characters on this server, at auction house prices"])
    T.Refresh()
end

---------------------------------------------------------------------------
-- Characters (FT.Port.Characters): your bank alt and every other character, with how fresh its numbers are
---------------------------------------------------------------------------
local function AgeText(t)
    if not t then return FT.C("down", L["never"]) end
    local days = (time() - t) / 86400
    local text = FT.Ago(t)
    return days >= STALE_DAYS and FT.C("accent", text) or text
end

function T.BuildChars(p)
    local f = CreateFrame("Frame", nil, p)
    f:SetPoint("TOPLEFT", 0, -30)
    f:SetPoint("BOTTOMRIGHT", 0, 0)
    f:Hide()
    charsView = f
    f.note = UI.Text(f, 11, "dim")
    f.note:SetPoint("TOPLEFT", 12, -12)
    f.note:SetPoint("RIGHT", -12, 0)
    if f.note.SetWordWrap then f.note:SetWordWrap(false) end
    local panel = UI.Panel(f, "bg1", "line")
    panel:SetPoint("TOPLEFT", 8, -34)
    panel:SetPoint("BOTTOMRIGHT", -8, 8)
    local cols = {
        { key = "name", title = L["Character"], width = "fill" },
        { key = "gold", title = L["Gold"], width = 110, justify = "RIGHT" },
        { key = "worth", title = L["Items"], width = 110, justify = "RIGHT" },
        { key = "total", title = L["Total"], width = 110, justify = "RIGHT" },
        { key = "bank", title = L["Bank seen"], width = 110, justify = "RIGHT" },
        { key = "mail", title = L["Mail seen"], width = 110, justify = "RIGHT" },
    }
    f.header = UI.Header(panel, cols, function() end)
    f.header:SetPoint("TOPLEFT", 1, -1)
    f.header:SetPoint("TOPRIGHT", -1, -1)
    f.list = UI.List(panel, {
        rowHeight = 28, cols = cols,
        update = function(row, x)
            local color = x.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[x.classFile]
            local name = color and ("|c" .. color.colorStr .. x.name .. "|r") or x.name
            row.cells.name:SetText(name .. (x.current and FT.C("dim", "  " .. L["(this one)"]) or ""))
            row.cells.gold:SetText(FT.Money(x.gold, "short"))
            row.cells.worth:SetText(FT.Money(math.floor(x.worth), "short"))
            row.cells.total:SetText(FT.Money(math.floor(x.total), "short"))
            row.cells.bank:SetText(AgeText(x.bankT))
            row.cells.mail:SetText(AgeText(x.mailT))
        end,
    })
    f.list:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 0, -2)
    f.list:SetPoint("BOTTOMRIGHT", -1, 4)
    f.list:SetEmptyText(L["No characters yet."])
end

function T.RefreshChars()
    if not charsView then return end
    local list = FT.Port.Characters()
    local old = {}
    for _, x in ipairs(list) do
        if not x.current and (not x.bankT or time() - x.bankT >= STALE_DAYS * 86400) then old[#old + 1] = x.name end
    end
    if #old > 0 then
        charsView.note:SetText(FT.C("accent", string.format(L["Out of date: %s. Log in and open the bank and mailbox to count what they hold."], table.concat(old, ", "))))
    else
        charsView.note:SetText(L["A character counts from its own logins: open its bank and mailbox now and then."])
    end
    charsView.list:SetItems(list, true)
end

FT.On("FT_JOURNAL_CHANGED", function() T.RefreshJournal() end)

function T.DrawChart()
    local points = FT.Port.History(state.days)
    chart:SetData({
        candles = UI.LineCandles(points),
        mode = "line",
        lineColor = "accent",
        tagColor = "accent",
        defaultCount = state.days,
        fmt = function(v) return FT.Thousands(v / 10000) .. FT.COIN.gold end,
        emptyTitle = L["No price history yet"],
        emptyBody = L["Shows once there are a few days of prices for what you own."],
    })
end

function T.RefreshList()
    local rows = T.rows or {}
    local get = SORT_GET[state.sort] or SORT_GET.value
    local missing = state.desc and -math.huge or math.huge
    table.sort(rows, function(a, b)
        local va, vb = get(a) or missing, get(b) or missing
        if va ~= vb then
            if state.desc then return va > vb end
            return va < vb
        end
        return a.id < b.id
    end)
    list:SetItems(rows, true)
end

---------------------------------------------------------------------------
-- Sell yours (FT.Tabs.signals.SellYours): each thing you own and what to do with it - vendor it, sell it here,
-- carry it to the other house or HODL; how many to list at once
---------------------------------------------------------------------------
function T.BuildSell(p)
    local M = FT.Tabs.signals
    local f = M.ListView(p, function(x)
        if UI.ItemClick(x.id) then return end
        FT.OpenItem(x.id)
    end, function(row, x)
        UI.TipItem(row, x.id)
        if x.why then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(x.why, 0.85, 0.87, 0.9, true)
            GameTooltip:Show()
        end
    end)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", 8, -36)
    f:SetPoint("BOTTOMRIGHT", -8, 8)
    f.hint:SetText(L["Sell it in Auctionator: this tells you where, at what and how many. A character counts once it has logged in and opened its bank and mailbox."])
    f.list:SetEmptyText(L["Nothing priced yet. Log in each character once and open its bags, bank and mailbox."])
    sellView = f
end

function T.RefreshSell()
    if not (sellView and sellView:IsShown()) then return end
    local list = FT.Tabs.signals.SellYours()
    local total = 0
    for _, x in ipairs(list) do total = total + x.sortV end
    sellView.count:SetText(#list > 0 and string.format(L["%d items, worth %s"], #list, FT.Money(math.floor(total), "short")) or "")
    sellView.list:SetItems(list, true)
end

---------------------------------------------------------------------------
-- Sessions (FT.Session): your farming runs, the best gold an hour first
---------------------------------------------------------------------------
function T.BuildSessions(p)
    local f = CreateFrame("Frame", nil, p)
    f:SetPoint("TOPLEFT", 0, -30)
    f:SetPoint("BOTTOMRIGHT", 0, 0)
    f:Hide()
    sessView = f
    f.toggle = UI.Button(f, L["Start a session"], 10, 24, "primary", function()
        if FT.Session.Current() then FT.Session.Stop() else FT.Session.Start() end
    end)
    f.toggle:FitText(24)
    f.toggle:SetPoint("TOPLEFT", 10, -8)
    f.note = UI.Text(f, 11, "dim")
    f.note:SetPoint("LEFT", f.toggle, "RIGHT", 12, 0)
    f.note:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    if f.note.SetWordWrap then f.note:SetWordWrap(false) end
    local panel = UI.Panel(f, "bg1", "line")
    panel:SetPoint("TOPLEFT", 8, -40)
    panel:SetPoint("BOTTOMRIGHT", -8, 8)
    local cols = {
        { key = "name", title = L["Session"], width = "fill" },
        { key = "when", title = L["When"], width = 100, justify = "RIGHT" },
        { key = "time", title = L["Time"], width = 90, justify = "RIGHT" },
        { key = "worth", title = L["Worth"], width = 100, justify = "RIGHT" },
        { key = "rate", title = L["Per hour"], width = 100, justify = "RIGHT" },
    }
    f.header = UI.Header(panel, cols, function() end)
    f.header:SetPoint("TOPLEFT", 1, -1)
    f.header:SetPoint("TOPRIGHT", -1, -1)
    f.list = UI.List(panel, {
        rowHeight = 28, cols = cols,
        update = function(row, s)
            local rate = (s.secs or 0) >= 60 and (s.worth or 0) / s.secs * 3600 or nil
            row.cells.name:SetText(s.name or s.zone or "?")
            row.cells.when:SetText(FT.C("dim", s.stop and FT.Ago(s.stop) or ""))
            row.cells.time:SetText(FT.Duration(s.secs))
            row.cells.worth:SetText(FT.Money(s.worth or 0, "short"))
            row.cells.rate:SetText(rate and FT.C("up", FT.Money(math.floor(rate), "short")) or "")
        end,
        onEnter = function(row, s)
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:AddLine(s.name or s.zone or "?", 1, 1, 1)
            local sum = FT.Session.Summary(s)
            GameTooltip:AddLine(string.format(L["Worth now: %s (then: %s)"], FT.Money(math.floor(sum.worth), "short"), FT.Money(s.worth or 0, "short")), 0.8, 0.82, 0.86)
            if (s.money or 0) > 0 then GameTooltip:AddDoubleLine(L["Gold looted"], FT.Money(s.money, "short"), 0.8, 0.82, 0.86, 1, 1, 1) end
            for i, it in ipairs(sum.items) do
                if i > 12 then break end
                GameTooltip:AddDoubleLine(FT.ItemText(it.id, 30) .. " x" .. FT.Num(it.qty), FT.Money(math.floor(it.value), "short"), 0.8, 0.82, 0.86, 1, 1, 1)
            end
            GameTooltip:Show()
        end,
    })
    f.list:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 0, -2)
    f.list:SetPoint("BOTTOMRIGHT", -1, 4)
    f.list:SetEmptyText(L["No sessions yet. Start one before a farming run (here, or right-click the minimap button): everything you loot counts."])
end

function T.RefreshSessions()
    if not sessView then return end
    local cur = FT.Session.Current()
    sessView.toggle:SetLabel(cur and L["Stop the session"] or L["Start a session"])
    sessView.toggle:FitText(24)
    local usual = FT.Session.UsualPerHour()
    if cur then
        local sum = FT.Session.Summary(cur)
        sessView.note:SetText(string.format(L["Running: %s so far, %s an hour."], FT.Money(math.floor(sum.worth), "short"),
            sum.perHour and FT.Money(math.floor(sum.perHour), "short") or "..."))
    else
        sessView.note:SetText(usual and string.format(L["Your usual: %s an hour."], FT.Money(math.floor(usual), "short")) or "")
    end
    local list = {}
    for _, s in ipairs(FT.Session.List()) do list[#list + 1] = s end
    sessView.list:SetItems(list, true)
end
FT.On("FT_SESSION_CHANGED", function() if sessView and sessView:IsShown() then T.RefreshSessions() end end)

function T.Refresh()
    if state.view == "journal" then return T.RefreshJournal() end
    if state.view == "sessions" then return T.RefreshSessions() end
    if state.view == "chars" then return T.RefreshChars() end
    if state.view == "sell" then return T.RefreshSell() end
    local rows, total, total7 = FT.Port.Rows()
    T.rows, T.total = rows, total
    local gold = FT.Port.Gold()
    local ch = total7 > 0 and (total / total7 - 1) or nil
    cards[1]:Set(FT.Money(total + gold, "short"), L["items and gold"])
    cards[2]:Set(FT.Money(total, "short"), FT.Pct(ch) .. FT.C("dim", " " .. L["in 7 days"]))
    cards[3]:Set(FT.Money(gold, "short"), L["all characters on this server"])
    local toSell = 0
    for _, x in ipairs(rows) do
        if x.signal == "SELL" or x.signal == "TRIM" then toSell = toSell + 1 end
    end
    cards[4]:Set(FT.Num(#rows), toSell > 0 and FT.C("up", string.format(L["%d worth selling now"], toSell)) or L["priced items"])
    T.DrawChart()
    T.RefreshList()
end

T.OnShow = T.Refresh

-- item names and colours arrived: the rows on screen show them
function T.OnItems()
    if list then list:Refresh() end
    if journal and journal:IsShown() then journal.list:Refresh() end
end
