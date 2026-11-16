-- ForeverTrading: Portfolio page - what your characters on this server own, valued at market prices.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local T = {}
FT.Tabs.portfolio = T

local state = { sort = "value", desc = true, days = 30 }
local cards, chart, list, rangeSeg

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
    list:SetEmptyText(L["Nothing priced yet. Open your bags and bank once per character; Mastercraft's records of your alts are used too."])

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

function T.Refresh()
    local rows, total, total7 = FT.Port.Rows()
    T.rows, T.total = rows, total
    local gold = FT.Port.Gold()
    local ch = total7 > 0 and (total / total7 - 1) or nil
    cards[1]:Set(FT.Money(total + gold, "short"), L["items and gold"])
    cards[2]:Set(FT.Money(total, "short"), FT.Pct(ch) .. FT.C("dim", " " .. L["in 7 days"]))
    cards[3]:Set(FT.Money(gold, "short"), L["all characters on this server"])
    local toSell = 0
    for _, x in ipairs(rows) do
        if x.signal == "SELL" then toSell = toSell + 1 end
    end
    cards[4]:Set(FT.Num(#rows), toSell > 0 and FT.C("up", string.format(L["%d worth selling now"], toSell)) or L["priced items"])
    T.DrawChart()
    T.RefreshList()
end

T.OnShow = T.Refresh
