-- Wolf: Portfolio page - what your characters on this server own, valued at market prices.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local T = {}
FT.Tabs.portfolio = T
local DONUT_W -- (below: the donut's width)

local state = { sort = "value", desc = true, days = 30, view = "portfolio", period = 7 }
local cards, chart, list, rangeSeg
local portfolioParts = {} -- what the Portfolio view shows (hidden in the Journal view)
local journal             -- the Journal view
local charsView           -- the Characters view
local sellView            -- the Sell yours view (what to do with each thing you own)
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

-- the groups of the list, the most valuable first; a closed one shows its header only (remembered)
local GROUPS = { mat = "Materials", crafted = "Crafted", gear = "BoE gear", other = "Other" }
local function Closed()
    FT.db.portClosed = FT.db.portClosed or { other = true }
    return FT.db.portClosed
end

local SORT_GET = {
    value = function(x) return x.value end,
    qty = function(x) return x.qty end,
    price = function(x) return x.price end,
    ch7 = function(x) return x.ch7 end,
    share = function(x) return x.value end,
}

function T.Build(p)
    -- v0.50: the section bar top left, as on every Make gold and You page; the page's line beside it
    T.viewSeg = UI.GroupBar(p, "you")
    T.viewSeg:SetPoint("TOPLEFT", 12, -8)
    local head = UI.Text(p, 16, "text")
    head:SetText(L["Portfolio"])
    head:Hide()
    local sub = UI.Text(p, 11, "dim")
    sub:SetPoint("LEFT", T.viewSeg, "RIGHT", 14, 0)
    sub:SetPoint("RIGHT", p, "RIGHT", -12, 0)
    if sub.SetWordWrap then sub:SetWordWrap(false) end
    sub:SetText(L["Bags, banks and mailboxes of your characters on this server, at auction house prices"])
    T.viewSeg:SetValue(state.view)
    T.head, T.sub = head, sub

    cards = {}
    local titles = { L["Total worth"], L["Items"], L["Gold"], L["Positions"] }
    for i, t in ipairs(titles) do
        cards[i] = UI.Stat(p, t)
        cards[i]:SetHeight(UI.RowH(64))
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
            local c = row.cells
            if not row.groupBg then
                row.groupBg = UI.Tex(row, "BACKGROUND", "bg2", 1)
                row.groupBg:SetAllPoints()
            end
            row.groupBg:SetShown(x.header == true)
            c.name.icon:ClearAllPoints()
            if x.header then
                -- a group: open or closed, how many, what they're worth, how many to sell
                c.name.icon:SetPoint("LEFT", 0, 0)
                c.name.icon:SetIcon(x.closed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
                c.name.text:SetText(x.name .. FT.C("dim", "  ·  " .. string.format(x.n == 1 and L["%d item"] or L["%d items"], x.n)))
                c.qty:SetText("")
                c.price:SetText("")
                c.value:SetText(FT.Money(x.value, "gold"))
                c.ch7:SetText("")
                -- (no trend and share columns since v0.42)
                c.signal:SetShown(x.toSell > 0)
                if x.toSell > 0 then c.signal:Set("SELL", string.format(L["%d to sell"], x.toSell)) end
                return
            end
            c.signal:Show()
            c.name.icon:SetPoint("LEFT", 14, 0)
            row.cells.name.icon:SetItem(x.id)
            row.cells.name.text:SetText(FT.ItemText(x.id, 40))
            row.cells.qty:SetText(FT.Num(x.qty))
            row.cells.price:SetText(FT.Money(x.price, "short"))
            row.cells.value:SetText(FT.Money(x.value, "gold"))
            row.cells.ch7:SetText(FT.Pct(x.ch7))
            local m = FT.Market.Row(x.id)
            local wk = x.ch7 or 0
            row.cells.signal:Set(x.signal, nil, x.strength)
        end,
        onClick = function(x)
            if x.header then
                local closed = Closed()
                closed[x.key] = (not closed[x.key]) or nil
                T.RefreshList()
                return
            end
            if not UI.ItemClick(x.id) then FT.OpenItem(x.id) end
        end,
        onEnter = function(row, x)
            if x.header then
                GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                GameTooltip:AddLine(x.name, 1, 1, 1)
                GameTooltip:AddLine(string.format(L["%s items worth %s"], FT.Num(x.n), FT.Money(x.value)), 0.85, 0.87, 0.9)
                GameTooltip:AddLine(x.closed and L["Click: open"] or L["Click: close"], 0.6, 0.64, 0.7)
                GameTooltip:Show()
                return
            end
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
                if (c.post or 0) > 0 then where[#where + 1] = L["mailed, on the way"] .. " " .. c.post end
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
    -- v0.42: the donut of where your gold sits takes the place of the four cards and the worth chart (Today shows
    -- the worth and its moves); the table beside it shows what the chosen slice holds
    for _, x in ipairs(cards) do x:Hide() end
    for _, x in ipairs({ chartTitle, rangeSeg, chart }) do x:Hide() end
    T.BuildDonut(p)
    for _, x in ipairs({ T.donutBox, T.filter, T.showAll, panel }) do portfolioParts[#portfolioParts + 1] = x end
    T.BuildJournal(p)
    T.BuildChars(p)
    T.BuildSell(p)

    UI.OnSize(p, function(self, w, h)
        T.donutBox:ClearAllPoints()
        T.donutBox:SetPoint("TOPLEFT", 8, -38)
        T.donutBox:SetPoint("BOTTOMLEFT", 8, 8)
        T.donutBox:SetWidth(DONUT_W())
        if T.worth and T.rows then FT.Debounce("worthFit", 0.1, T.FillDonut) end
        T.filter:ClearAllPoints()
        T.filter:SetPoint("TOPLEFT", T.donutBox, "TOPRIGHT", 12, -6)
        T.filter:SetPoint("RIGHT", T.showAll, "LEFT", -10, 0)
        T.showAll:ClearAllPoints()
        T.showAll:SetPoint("TOPRIGHT", -8, -38)
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", T.donutBox, "TOPRIGHT", 10, -30)
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

---------------------------------------------------------------------------
-- Where your worth is (v0.57; a donut from v0.42 to v0.56): no ring to read - the total, then a row for each part,
-- biggest first: its gold and share, a bar of it behind the row, and its top items. What it is (herbs, ore, cloth,
-- leather, enchanting, consumables, gear, recipes), where it is (bags, bank, mail, on the AH) or how liquid it is
-- (sells today, this week, slow to sell - a fifth of a day's sales is what one seller can move - listed). A click
-- shows just that part in the table; again: everything.
---------------------------------------------------------------------------
DONUT_W = function() return (FT.Compact() and 320 or 360) + 16 * (tonumber(FT.S and FT.S.textSize) or 0) end
local WHAT = { { "herb", "Herbs", "up" }, { "ore", "Ore and stone", "orange" }, { "cloth", "Cloth", "purple" },
    { "leather", "Leather", "accent" }, { "enchant", "Enchanting", "blue" }, { "mats", "Other materials", "muted" },
    { "consum", "Consumables", "down" }, { "gear", "Gear", "text" }, { "recipe", "Recipes", "purple" }, { "other", "Other", "dim" } }
local WHERE = { { "bags", "Bags", "blue" }, { "bank", "Bank", "up" }, { "mail", "Mail", "purple" }, { "ah", "On the AH", "accent" } }
local LIQUID = { { "today", "Sells today", "up" }, { "week", "Sells this week", "blue" },
    { "slow", "Slow to sell", "orange" }, { "ah", "Listed on the AH", "accent" } }
local VIEWS = { what = WHAT, where = WHERE, liquid = LIQUID }
local MAX_PARTS = 7
local donutView, donutPick = "what", nil

local function Liquidity(id, qty)
    local rate = FT.Sales.Rate(id)
    local perDay = rate and rate.perDay or 0
    local days = qty / math.max(0.2, perDay * 0.2)
    if days <= 1 then return "today" elseif days <= 7 then return "week" end
    return "slow"
end

-- what an item is: by its class and subclass (the market's row, else the game's instant info)
local TRADE = { [9] = "herb", [7] = "ore", [5] = "cloth", [6] = "leather", [12] = "enchant" }
local kindCache = {}
local function WhatOf(id)
    if not id then return "other" end
    local k = kindCache[id]
    if k then return k end
    local r = FT.Market.Row(id)
    local cls, sub = r and r.cls, r and r.sub
    if not cls then
        local _, _, _, _, _, c, sc = FT.GetItemInfoInstant(id)
        cls, sub = c, sc
    end
    if cls == 7 then k = TRADE[sub] or "mats"
    elseif cls == 0 then k = "consum"
    elseif cls == 2 or cls == 4 then k = "gear"
    elseif cls == 9 then k = "recipe"
    elseif cls == 5 or cls == 3 then k = "mats"
    else k = "other" end
    if cls then kindCache[id] = k end
    return k
end

-- every row of the table split by where it is (a part of an item in each place), and your listed auctions
local function Pieces(rows)
    local out = {}
    for _, x in ipairs(rows) do
        local per = { bags = 0, bank = 0, mail = 0 }
        for _, c in pairs(x.chars or {}) do
            per.bags = per.bags + (c.bags or 0)
            per.bank = per.bank + (c.bank or 0)
            per.mail = per.mail + (c.mail or 0) + (c.post or 0)
        end
        for loc, n in pairs(per) do
            if n > 0 then out[#out + 1] = { row = x, loc = loc, qty = n, value = x.price * n } end
        end
    end
    for _, b in ipairs((FT.Owned.List())) do
        if b.itemID and not b.sold then
            local s = FT.An.Stats(b.itemID)
            if s.price then
                out[#out + 1] = { id = b.itemID, loc = "ah", qty = b.qty or 1, value = s.price * (b.qty or 1), stats = s }
            end
        end
    end
    return out
end

local function SliceOf(piece)
    if donutView == "where" then return piece.loc end
    if donutView == "what" then return WhatOf(piece.row and piece.row.id or piece.id) end
    if piece.loc == "ah" then return "ah" end
    return Liquidity(piece.row.id, piece.row.qty)
end

-- the parts as numbers: { key, label, color, value, share, top = { names } }, biggest first (the small ones in
-- "Other" when there are too many)
function T.WorthParts()
    local defs = VIEWS[donutView]
    local sums, items = {}, {}
    for _, piece in ipairs(Pieces(T.rows or {})) do
        local k = SliceOf(piece)
        sums[k] = (sums[k] or 0) + piece.value
        local id = piece.row and piece.row.id or piece.id
        items[k] = items[k] or {}
        items[k][id] = (items[k][id] or 0) + piece.value
    end
    local parts, total = {}, 0
    for _, d in ipairs(defs) do
        local v = sums[d[1]] or 0
        if v > 0 then
            local top = {}
            for id, iv in pairs(items[d[1]]) do top[#top + 1] = { id, iv } end
            table.sort(top, function(x, y) if x[2] ~= y[2] then return x[2] > y[2] end return x[1] < y[1] end)
            local names = {}
            for i = 1, math.min(3, #top) do names[i] = FT.Name(top[i][1]) or "?" end
            parts[#parts + 1] = { key = d[1], label = L[d[2]], color = d[3], value = v, top = names, n = #top }
            total = total + v
        end
    end
    table.sort(parts, function(x, y) return x.value > y.value end)
    for _, pt in ipairs(parts) do pt.share = total > 0 and pt.value / total or 0 end
    return parts, total
end

local function PartRow(box)
    local r = CreateFrame("Button", nil, box)
    r:SetHeight(UI.RowH(36))
    r.fill = UI.Tex(r, "BACKGROUND", "accent", 0.16)
    r.fill:SetPoint("TOPLEFT", 0, -1)
    r.fill:SetPoint("BOTTOMLEFT", 0, 1)
    r.hover = UI.Tex(r, "BORDER", "hl", 0.7)
    r.hover:SetAllPoints()
    r.hover:Hide()
    r.sw = UI.Tex(r, "ARTWORK", "accent", 1)
    r.sw:SetSize(4, UI.RowH(36) - 8)
    r.sw:SetPoint("LEFT", 2, 0)
    r.pct = UI.Text(r, 12, "muted", "RIGHT")
    r.pct:SetPoint("TOPRIGHT", -8, -5)
    r.pct:SetWidth(40)
    r.val = UI.Text(r, 13, "text", "RIGHT")
    r.val:SetPoint("RIGHT", r.pct, "LEFT", -6, 0)
    r.val:SetWidth(UI.RowH(78) + 8 * (tonumber(FT.S.textSize) or 0))
    r.label = UI.Text(r, 13, "text")
    r.label:SetPoint("TOPLEFT", 12, -5)
    r.label:SetPoint("RIGHT", r.val, "LEFT", -6, 0)
    r.top = UI.Text(r, 10, "dim")
    r.top:SetPoint("BOTTOMLEFT", 12, 5)
    r.top:SetPoint("RIGHT", -8, 0)
    r:SetScript("OnEnter", function(self) self.hover:Show() end)
    r:SetScript("OnLeave", function(self) self.hover:Hide() end)
    r:SetScript("OnClick", function(self) if self.key then T.worth:Pick(self.key) end end)
    return r
end

function T.BuildDonut(p)
    local box = UI.Panel(p, "bg1", "line")
    T.donutBox = box
    box.seg = UI.Segmented(box, { { "what", L["What it is"] }, { "where", L["Where it is"] }, { "liquid", L["How liquid"] } }, function(v)
        donutView, donutPick = v, nil
        T.FillDonut()
        T.RefreshList()
    end, 22)
    box.seg:SetPoint("TOPLEFT", 8, -8)
    box.seg:SetPoint("TOPRIGHT", -8, -8)
    box.seg:SetValue(donutView)
    box.total = UI.Text(box, 20, "text")
    box.total:SetPoint("TOPLEFT", 10, -40)
    box.sub = UI.Text(box, 11, "muted")
    box.sub:SetPoint("TOPLEFT", box.total, "BOTTOMLEFT", 1, -3)
    box.sub:SetPoint("RIGHT", box, "RIGHT", -10, 0)
    -- (v0.61) your listings someone undercut: a badge by the total, to Sell > My auctions
    box.undercut = UI.Button(box, "", 10, 20, "default", function() FT.Show("sell") end)
    box.undercut:SetPoint("TOPRIGHT", -10, -42)
    box.undercut:SetTip(L["Undercut"], L["Your listings someone listed cheaper since: My auctions has each one, and whether to wait or post it again."])
    box.parts = {}
    for i = 1, MAX_PARTS do
        local r = PartRow(box)
        r:SetPoint("TOPLEFT", 6, -40 - UI.Size(20) - UI.Size(11) - 16 - (i - 1) * (UI.RowH(36) + 3))
        r:SetPoint("RIGHT", box, "RIGHT", -6, 0)
        box.parts[i] = r
    end
    -- what the rows answer to (the old donut's Pick, for the table and the tests)
    T.worth = { picked = nil, byKey = {} }
    function T.worth:Pick(key)
        self.picked = (key and self.picked ~= key) and key or nil
        donutPick = self.picked
        T.FillDonut()
        T.RefreshList()
    end
    T.filter = UI.Text(p, 12, "text")
    T.showAll = UI.Button(p, L["Show everything"], 10, 22, "default", function() T.worth:Pick(nil) end)
    T.showAll:FitText(22)
end

function T.FillDonut()
    if not T.worth then return end
    local box = T.donutBox
    local gold = FT.Port.Gold() or 0
    local parts, total = T.WorthParts()
    -- the small ones together, past what fits in the box's height
    local top0 = 40 + UI.Size(20) + UI.Size(11) + 16
    local fit = MAX_PARTS
    local h = box:GetHeight()
    if h and h > top0 + 40 then fit = math.max(2, math.min(MAX_PARTS, math.floor((h - top0 - 4) / (UI.RowH(36) + 3)))) end
    if #parts > fit then
        local rest = { key = "rest", label = L["The rest"], color = "dim", value = 0, share = 0, top = {}, n = 0 }
        for i = fit, #parts do
            rest.value, rest.share = rest.value + parts[i].value, rest.share + parts[i].share
            rest.top[#rest.top + 1] = parts[i].label
            parts[i] = nil
        end
        parts[fit] = rest
    end
    T.worth.byKey, T.worth.parts = {}, parts
    for _, pt in ipairs(parts) do T.worth.byKey[pt.key] = pt end
    if donutPick and not T.worth.byKey[donutPick] then donutPick = nil end
    T.worth.picked = donutPick
    box.total:SetText(FT.Money(total + gold, "gold"))
    local under = 0
    if FT.Owned and FT.Owned.List then
        for _, a in ipairs((FT.Owned.List()) or {}) do if not a.sold and FT.Owned.Undercut(a) then under = under + 1 end end
    end
    box.undercut:SetShown(under > 0)
    if under > 0 then
        box.undercut:SetLabel(FT.C("down", string.format(under == 1 and L["%d undercut"] or L["%d undercut"], under)))
        box.undercut:FitText(16)
    end
    UI.FitBits(box.sub, L["all you own"] .. FT.C("dim", "  ·  ") .. (gold > 0 and (FT.Money(gold, "gold") .. " " .. L["in coins"]) or L["no coins on you"]))
    for i, r in ipairs(box.parts) do
        local pt = parts[i]
        r:SetShown(pt ~= nil)
        if pt then
            r.key = pt.key ~= "rest" and pt.key or nil
            local c = UI.C[pt.color] or UI.C.text
            r.sw:SetColorTexture(c[1], c[2], c[3], 1)
            r.fill:SetColorTexture(c[1], c[2], c[3], donutPick == pt.key and 0.32 or 0.16)
            r.fill:SetWidth(math.max(2, (DONUT_W() - 28) * pt.share))
            r.label:SetText(pt.label)
            UI.SetTextColor(r.label, donutPick == pt.key and "accent" or "text")
            r.val:SetText(FT.Money(pt.value, "gold"))
            r.pct:SetText(string.format("%d%%", math.floor(pt.share * 100 + 0.5)))
            UI.FitBits(r.top, table.concat(pt.top, " · ") .. ((pt.n or 0) > 3 and (" · " .. string.format(L["+%d more"], pt.n - 3)) or ""))
        end
    end
    local sl = donutPick and T.worth.byKey[donutPick]
    T.showAll:SetShown(sl ~= nil)
    if sl then
        T.filter:SetText(FT.C("accent", sl.label) .. "  " .. FT.Money(sl.value, "gold") .. FT.C("dim", string.format("  ·  %d%%", math.floor(sl.share * 100 + 0.5))))
    else
        T.filter:SetText(L["Everything"] .. FT.C("dim", "  ·  " .. L["click a part to see just that"]))
    end
end

-- the table's rows for the chosen slice: the part of each item that's there (nil: every row whole)
function T.SliceRows(rows)
    if not donutPick then return rows end
    local out, byId = {}, {}
    for _, piece in ipairs(Pieces(rows)) do
        if SliceOf(piece) == donutPick then
            local base = piece.row
            if not base then
                local s = piece.stats
                local signal, strength, reason = FT.An.SellSignal(s)
                base = { id = piece.id, price = s.price, ch7 = s.ch7, stats = s, signal = signal, strength = strength, reason = reason, chars = {} }
            end
            local key = base.id
            local x = byId[key]
            if not x then
                x = {}
                for k, v in pairs(base) do x[k] = v end
                x.qty, x.value = 0, 0
                byId[key] = x
                out[#out + 1] = x
            end
            x.qty = x.qty + piece.qty
            x.value = x.value + piece.value
        end
    end
    return out
end

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
        f.cards[i]:SetHeight(UI.RowH(64))
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
    if view == "sessions" then
        FT.ShowSub("you", "sessions")
        return
    end
    if FT.GroupShows and view ~= "sell" then FT.GroupShows("you", view) end
    local j, ch, sl = view == "journal", view == "chars", view == "sell"
    for _, x in ipairs(portfolioParts) do x:SetShown(not j and not ch and not sl) end
    if journal then journal:SetShown(j) end
    if charsView then charsView:SetShown(ch) end
    if sellView then sellView:SetShown(sl) end
    T.head:SetText((j and L["Journal"]) or (ch and L["Characters"]) or (sl and L["Sell yours"]) or L["Portfolio"])
    UI.FitSize(T.sub, (j and L["What you bought and sold at the auction house, and what it brought"])
        or (ch and L["Every character on this server: gold, what it holds, when it was last seen"])
        or (sl and L["Everything you own and the best way to turn each into gold"])
        or L["Bags, banks and mailboxes of your characters on this server, at auction house prices"], 11, 2)
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
    local rows = T.SliceRows and T.SliceRows(T.rows or {}) or (T.rows or {})
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
    local byGroup, heads = {}, {}
    for _, x in ipairs(rows) do
        local g = FT.Port.Group(x.id)
        local h = byGroup[g]
        if not h then
            h = { header = true, key = g, name = L[GROUPS[g]], n = 0, value = 0, toSell = 0, items = {} }
            byGroup[g] = h
            heads[#heads + 1] = h
        end
        h.n, h.value = h.n + 1, h.value + (x.value or 0)
        if x.signal == "SELL" or x.signal == "TRIM" then h.toSell = h.toSell + 1 end
        h.items[#h.items + 1] = x
    end
    table.sort(heads, function(a, b) return a.value > b.value end)
    local out, closed = {}, Closed()
    for _, h in ipairs(heads) do
        h.closed = closed[h.key] and true or false
        out[#out + 1] = h
        if not h.closed then
            for _, x in ipairs(h.items) do out[#out + 1] = x end
        end
    end
    list:SetItems(out, true)
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

function T.Refresh()
    if state.view == "journal" then return T.RefreshJournal() end
    if state.view == "chars" then return T.RefreshChars() end
    if state.view == "sell" then return T.RefreshSell() end
    local rows, total, total7 = FT.Port.Rows()
    T.rows, T.total = rows, total
    local gold = FT.Port.Gold()
    local ch = total7 > 0 and (total / total7 - 1) or nil
    cards[1]:Set(FT.Money(FT.Port.Worth(), "short"), L["items, listings and gold"])
    cards[2]:Set(FT.Money(total, "short"), FT.Pct(ch) .. FT.C("dim", " " .. L["in 7 days"]))
    cards[3]:Set(FT.Money(gold, "short"), L["all characters on this server"])
    local toSell = 0
    for _, x in ipairs(rows) do
        if x.signal == "SELL" or x.signal == "TRIM" then toSell = toSell + 1 end
    end
    cards[4]:Set(FT.Num(#rows), toSell > 0 and FT.C("up", string.format(L["%d worth selling now"], toSell)) or L["priced items"])
    T.FillDonut()
    T.RefreshList()
end

T.OnShow = T.Refresh

-- loot, mail, a buy, a listing, gold: Holdings follows while it's open (once things settle: crafting holds it off)
local function Follow()
    if list and list:IsVisible() and state.view == "portfolio" then FT.Debounce("youFollow", 1, T.Refresh) end
end
FT.On("FT_INVENTORY_CHANGED", Follow)
FT.On("FT_OWNED_CHANGED", Follow)
FT.On("PLAYER_MONEY", Follow)

-- item names and colours arrived: the rows on screen show them
function T.OnItems()
    if list then list:Refresh() end
    if journal and journal:IsShown() then journal.list:Refresh() end
end

---------------------------------------------------------------------------
-- The Sessions page (FT.Session): start and stop a session, your runs by gold an hour
---------------------------------------------------------------------------
local ST = {}
local openSess = {} -- the sessions opened, by their start time
FT.Tabs.sessions = ST
local sessView

function ST.Build(p)
    -- v0.50: the section bar top left, as on every Make gold and You page
    ST.bar = UI.GroupBar(p, "you")
    ST.bar:SetPoint("TOPLEFT", 12, -8)
    local sub = UI.Text(p, 11, "dim")
    sub:SetPoint("LEFT", ST.bar, "RIGHT", 14, 0)
    sub:SetPoint("RIGHT", p, "RIGHT", -12, 0)
    if sub.SetWordWrap then sub:SetWordWrap(false) end
    sub:SetText(L["Your farming runs: what you looted, what it's worth now, gold an hour"])
    local f = CreateFrame("Frame", nil, p)
    f:SetPoint("TOPLEFT", 0, -30)
    f:SetPoint("BOTTOMRIGHT", 0, 0)
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
        rowHeight = 24, cols = cols,
        update = function(row, x)
            local c = row.cells
            if not row.openBg then
                row.openBg = UI.Tex(row, "BACKGROUND", "bg2", 1)
                row.openBg:SetAllPoints()
            end
            row.openBg:SetShown(x.session ~= nil and openSess[x.session.start] == true)
            if x.session then
                local s = x.session
                local rate = (s.secs or 0) >= 600 and (s.worth or 0) / s.secs * 3600 or nil
                local mark = openSess[s.start] and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up"
                c.name:SetText("|T" .. mark .. ":14|t  " .. (s.name or s.zone or "?"))
                c.when:SetText(FT.C("dim", FT.TimeOfDay(s.start or s.stop)))
                c.time:SetText(FT.Duration(s.secs))
                c.worth:SetText(FT.Money(s.worth or 0, "gold"))
                c.rate:SetText(rate and FT.C("up", FT.Money(math.floor(rate), "short")) or "")
            elseif x.head then
                -- the columns of what was found
                c.name:SetText(FT.C("dim", "      " .. L["Found"]))
                c.when:SetText(FT.C("dim", L["Qty"]))
                c.time:SetText(FT.C("dim", L["Then"]))
                c.worth:SetText(FT.C("dim", L["Now"]))
                c.rate:SetText(FT.C("dim", L["Change"]))
            elseif x.id then
                local _, _, icon = FT.Item(x.id)
                c.name:SetText("      |T" .. (icon or 134400) .. ":14|t " .. FT.ItemText(x.id, 30))
                c.when:SetText(FT.Num(x.qty))
                c.time:SetText(x.thenUnit and FT.Money(math.floor(x.thenUnit), "short") or FT.C("dim", "—"))
                local ch = (x.thenUnit and x.thenUnit > 0) and (x.nowUnit / x.thenUnit - 1) or nil
                c.worth:SetText(FT.Money(math.floor(x.nowUnit), "short") .. (ch and ("  " .. FT.Pct(ch)) or ""))
                -- what the stack gained or lost since it was found (no price then: nothing to compare)
                if x.thenTotal then
                    local diff = math.floor(x.nowUnit * x.qty - x.thenTotal)
                    c.rate:SetText(diff == 0 and FT.C("dim", "0") or FT.C(diff > 0 and "up" or "down", (diff > 0 and "+" or "-") .. FT.Money(math.abs(diff), "short")))
                else
                    c.rate:SetText(FT.C("dim", "—"))
                end
            else
                -- a line of text: gold looted, more items, its worth today
                c.name:SetText(FT.C("dim", "      " .. (x.text or "")))
                c.when:SetText("")
                c.time:SetText("")
                c.worth:SetText("")
                c.rate:SetText(x.value and FT.Money(x.value, "short") or "")
            end
        end,
        onClick = function(x, button)
            if x.session and button == "RightButton" then
                ST.Menu(x.session)
            elseif x.session then
                ST.Toggle(x.session)
            elseif x.id and not UI.ItemClick(x.id) then
                FT.OpenItem(x.id)
            end
        end,
        onEnter = function(row, x)
            if x.id then UI.TipItem(row, x.id) return end
            if not x.session then return end
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:AddLine(x.session.name or x.session.zone or "?", 1, 1, 1)
            GameTooltip:AddLine((openSess[x.session.start] and L["Click: close"] or L["Click: what you found"]) .. "  ·  " .. L["Right-click: rename or delete"], 0.6, 0.64, 0.7)
            GameTooltip:Show()
        end,
    })
    f.list:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 0, -2)
    f.list:SetPoint("BOTTOMRIGHT", -1, 4)
    f.list:SetEmptyText(L["No sessions yet. Start one before a farming run (here, or right-click the minimap button): everything you loot counts."])
end

-- right-click on a session: rename it, or delete it (asked first)
function ST.Menu(s)
    FT.ShowMenu(nil, {
        { s.name or s.zone or "?", nil, "dim" },
        { L["Rename"], function()
            UI.Confirm({ title = L["Rename the session"], text = L["Its new name (empty: its zone and length):"], input = s.name or "",
                ok = L["Rename"], onOK = function(name) FT.Session.Rename(s, name) end })
        end },
        { L["Delete"], function()
            UI.Confirm({ title = L["Delete this session?"], text = string.format(L["%s, %s. It can't be brought back."], s.name or s.zone or "?",
                FT.Money(s.worth or 0, "short")), ok = L["Delete"], okStyle = "down", onOK = function() FT.Session.Delete(s) end })
        end, "down" },
    })
end

-- a session opened or closed: what was found in it under its row
function ST.Toggle(s)
    openSess[s.start] = (not openSess[s.start]) or nil
    ST.Refresh()
end

function ST.Refresh()
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
    for _, s in ipairs(FT.Session.List()) do
        list[#list + 1] = { session = s }
        if openSess[s.start] then
            -- what was found: how many, worth each then (new sessions) and now, the most valuable first
            local found = {}
            for id, qty in pairs(s.items or {}) do
                local nowUnit = FT.Session.UnitValue(id) or 0
                local thenTotal = s.found and s.found[id]
                found[#found + 1] = { id = id, qty = qty, nowUnit = nowUnit, thenTotal = thenTotal,
                    thenUnit = thenTotal and qty > 0 and thenTotal / qty or nil, sortV = thenTotal or nowUnit * qty }
            end
            table.sort(found, function(a, b) return a.sortV > b.sortV end)
            if #found > 0 then list[#list + 1] = { head = true } end
            for i, it in ipairs(found) do
                if i > 15 then
                    list[#list + 1] = { text = string.format(L["%d more"], #found - 15) }
                    break
                end
                list[#list + 1] = it
            end
            if (s.money or 0) > 0 then list[#list + 1] = { text = L["Gold looted"], value = s.money } end
            local sum = FT.Session.Summary(s)
            list[#list + 1] = { text = string.format(L["Worth %s at today's prices"], FT.Money(math.floor(sum.worth), "short"))
                .. ((s.found == nil) and ("  ·  " .. L["prices when found are kept from this update on"]) or "") }
        end
    end
    sessView.list:SetItems(list, true)
end
FT.On("FT_SESSION_CHANGED", function() if sessView and sessView:IsVisible() then ST.Refresh() end end)
ST.OnShow = ST.Refresh

