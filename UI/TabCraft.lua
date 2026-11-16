-- ForeverTrading: Craft page - every recipe your characters know: what it costs, what it brings in,
-- the profit and a signal; one recipe in detail with its margin over time and its materials.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local T = {}
FT.Tabs.craft = T

local state = { prof = "all", char = "all", profitable = false, search = "", sort = "profit", desc = true, selected = nil }
local page, list, summary, detail, profChips, charDD
local DETAIL_W = 350

local SIGNAL_RANK = { CRAFT = 5, RISKY = 4, WATCH = 3, NODATA = 1, AVOID = 0 }

local function ProfName(key)
    return L[key] or key
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function Rows()
    local out = {}
    local search = state.search ~= "" and state.search:lower() or nil
    for _, r in ipairs(FT.Craft.List()) do
        local ok = (state.prof == "all" or r.prof == state.prof) and (state.char == "all" or r.knownBy[state.char])
        local e
        if ok then
            e = FT.Craft.Eval(r)
            if state.profitable and not (e.profit and e.profit > 0) then ok = false end
        end
        if ok and search then
            local name = (FT.Item(r.output) or r.name or ""):lower()
            ok = name:find(search, 1, true) ~= nil or (r.name or ""):lower():find(search, 1, true) ~= nil
        end
        if ok then out[#out + 1] = { r = r, e = e } end
    end
    local key, desc = state.sort, state.desc
    local function Get(x)
        local e = x.e
        if key == "cost" then return e.complete and e.cost or nil end
        if key == "revenue" then return e.revenue end
        if key == "margin" then return e.margin end
        if key == "ch7" then return e.stats.ch7 end
        if key == "signal" then return (SIGNAL_RANK[e.signal] or 0) * 1e12 + (e.profit or -1e11) end
        if key == "name" then return nil end
        return e.profit
    end
    if key == "name" then
        table.sort(out, function(a, b)
            local na = (FT.Item(a.r.output) or a.r.name or ""):lower()
            local nb = (FT.Item(b.r.output) or b.r.name or ""):lower()
            if na ~= nb then
                if desc then return na > nb end
                return na < nb
            end
            return a.r.key < b.r.key
        end)
    else
        local missing = desc and -math.huge or math.huge
        table.sort(out, function(a, b)
            local va, vb = Get(a) or missing, Get(b) or missing
            if va ~= vb then
                if desc then return va > vb end
                return va < vb
            end
            return a.r.key < b.r.key
        end)
    end
    return out
end

local function UpdateSummary(rows)
    local profitable, best, sum = 0, nil, 0
    for _, x in ipairs(rows) do
        if x.e.profit and x.e.profit > 0 then
            profitable = profitable + 1
            sum = sum + x.e.profit
            if not best or x.e.profit > best.e.profit then best = x end
        end
    end
    local parts = {
        string.format(L["Recipes: %d"], #rows),
        string.format(L["Profitable: %s"], FT.C("up", profitable)),
    }
    if best then
        parts[#parts + 1] = L["Best"] .. ": " .. FT.ItemText(best.r.output, 32) .. " " .. FT.C("up", "+" .. FT.Money(best.e.profit, "short"))
    end
    summary:SetText(table.concat(parts, FT.C("dim", "   ·   ")))
end

---------------------------------------------------------------------------
-- Toolbar
---------------------------------------------------------------------------
local function BuildToolbar(p)
    local bar = CreateFrame("Frame", nil, p)
    bar:SetPoint("TOPLEFT", 8, -8)
    bar:SetPoint("TOPRIGHT", -8, -8)
    bar:SetHeight(24)
    T.bar = bar
    profChips = {}

    -- second row: summary on the left, filters on the right
    local bar2 = CreateFrame("Frame", nil, p)
    bar2:SetPoint("TOPLEFT", 8, -38)
    bar2:SetPoint("TOPRIGHT", -8, -38)
    bar2:SetHeight(24)

    T.search = UI.Input(bar2, 200, 24, L["Search recipe..."], function(text)
        state.search = text or ""
        FT.Debounce("craftSearch", 0.25, function() T.RefreshList() end)
    end)
    T.search:SetPoint("RIGHT", 0, 0)

    T.profitable = UI.Check(bar2, L["Profitable only"], function(on)
        state.profitable = on
        T.RefreshList()
    end)
    T.profitable:SetPoint("RIGHT", T.search, "LEFT", -16, 0)

    charDD = UI.Dropdown(bar2, 150, { { "all", L["All characters"] } }, function(v)
        state.char = v
        T.RefreshList()
    end)
    charDD:SetPoint("RIGHT", T.profitable, "LEFT", -16, 0)
    charDD:SetValue("all")

    summary = UI.Text(bar2, 11, "muted")
    summary:SetPoint("LEFT", 2, 0)
    summary:SetPoint("RIGHT", charDD, "LEFT", -16, 0)
end

-- profession chips and the character list follow the recipes we know
local function UpdateFilters()
    for _, c in ipairs(profChips) do c:Hide() end
    local items = {}
    local function Chip(i, key, label)
        local c = profChips[i]
        if not c then
            c = UI.Chip(T.bar, label, function(self)
                state.prof = self.key
                for _, ch in ipairs(profChips) do ch:SetOn(ch.key == state.prof) end
                T.RefreshList()
            end)
            profChips[i] = c
        end
        c.key = key
        c:SetLabel(label)
        c:SetOn(key == state.prof)
        c:Show()
        items[#items + 1] = c
    end
    Chip(1, "all", L["All"])
    local found = false
    for i, prof in ipairs(FT.Craft.Professions()) do
        Chip(i + 1, prof, ProfName(prof))
        if prof == state.prof then found = true end
    end
    if not found and state.prof ~= "all" then
        state.prof = "all"
        profChips[1]:SetOn(true)
    end
    UI.RowLayout(T.bar, items, 0, -2, 6)

    local names, seen = {}, {}
    for _, r in ipairs(FT.Craft.List()) do
        for name in pairs(r.knownBy) do
            if not seen[name] then
                seen[name] = true
                names[#names + 1] = name
            end
        end
    end
    table.sort(names)
    local opts = { { "all", L["All characters"] } }
    for _, n in ipairs(names) do opts[#opts + 1] = { n, n } end
    charDD:SetOptions(opts)
    if state.char ~= "all" and not seen[state.char] then state.char = "all" end
    charDD:SetValue(state.char)
end

---------------------------------------------------------------------------
-- Table
---------------------------------------------------------------------------
local function NameCell(row)
    local f = CreateFrame("Frame", nil, row)
    f:SetHeight(26)
    f.icon = UI.Icon(f, 20)
    f.icon:SetPoint("LEFT", 0, 0)
    f.text = UI.Text(f, 12, "text")
    f.text:SetPoint("LEFT", f.icon, "RIGHT", 8, 0)
    f.text:SetPoint("RIGHT", 0, 0)
    return f
end

local function BadgeCell(row)
    local b = UI.Badge(row, 78, 18)
    return b
end

local function BuildTable(p)
    local panel = UI.Panel(p, "bg1", "line")
    panel:SetPoint("TOPLEFT", 8, -70)
    panel:SetPoint("BOTTOMRIGHT", -(DETAIL_W + 16), 8)
    local cols = {
        { key = "name", title = L["Recipe"], width = "fill", sort = "name", make = NameCell, cellHeight = 26 },
        { key = "cost", title = L["Cost"], width = 80, justify = "RIGHT", sort = "cost",
            tip = L["What one craft costs: each material at the cheapest of auction house, vendor or crafting it yourself."] },
        { key = "revenue", title = L["Sells for"], width = 80, justify = "RIGHT", sort = "revenue",
            tip = L["What one craft brings in at the auction house after its 5% cut (or at a vendor, when that pays more)."] },
        { key = "profit", title = L["Profit"], width = 80, justify = "RIGHT", sort = "profit" },
        { key = "margin", title = L["Margin"], width = 56, justify = "RIGHT", sort = "margin" },
        { key = "ch7", title = L["7d"], width = 56, justify = "RIGHT", sort = "ch7",
            tip = L["How the crafted item's price moved in 7 days."] },
        { key = "signal", title = L["Signal"], width = 80, justify = "CENTER", sort = "signal", make = BadgeCell, cellHeight = 18 },
    }
    T.header = UI.Header(panel, cols, function(key)
        if state.sort == key then
            state.desc = not state.desc
        else
            state.sort, state.desc = key, key ~= "name"
        end
        T.header:SetSort(state.sort, state.desc)
        T.RefreshList(true)
    end)
    T.header:SetPoint("TOPLEFT", 1, -1)
    T.header:SetPoint("TOPRIGHT", -1, -1)
    T.header:SetSort(state.sort, state.desc)

    list = UI.List(panel, {
        rowHeight = 28,
        cols = cols,
        update = function(row, x)
            local r, e = x.r, x.e
            local c = row.cells.name
            c.icon:SetItem(r.output)
            local qty = r.outputQty > 1 and FT.C("dim", string.format(" x%g", r.outputQty)) or ""
            c.text:SetText(FT.ItemText(r.output, 34) .. qty)
            row.cells.cost:SetText(e.complete and FT.Money(e.cost, "short") or FT.C("dim", "?"))
            row.cells.revenue:SetText(e.revenue and (FT.Money(e.revenue, "short") .. (e.via == "vendor" and FT.C("dim", " v") or "")) or FT.C("dim", "?"))
            if e.profit then
                row.cells.profit:SetText(FT.C(e.profit >= 0 and "up" or "down", FT.Money(e.profit, "short")))
                row.cells.margin:SetText(FT.C(e.profit >= 0 and "up" or "down", string.format("%d%%", math.floor((e.margin or 0) * 100 + 0.5))))
            else
                row.cells.profit:SetText(FT.C("dim", "—"))
                row.cells.margin:SetText(FT.C("dim", "—"))
            end
            row.cells.ch7:SetText(FT.Pct(e.stats.ch7))
            row.cells.signal:Set(e.signal, nil, e.strength)
        end,
        isSelected = function(x) return x.r.key == state.selected end,
        onClick = function(x, button)
            if UI.ItemClick(x.r.output) then return end
            if button == "RightButton" then
                FT.OpenItem(x.r.output)
                return
            end
            T.Select(x.r.key)
        end,
        onEnter = function(row, x)
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:AddLine(FT.ItemText(x.r.output))
            GameTooltip:AddLine(x.e.reason or "", 0.85, 0.87, 0.9, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Click: details · Right-click: price chart"], 0.52, 0.56, 0.61)
            GameTooltip:Show()
        end,
    })
    list:SetPoint("TOPLEFT", T.header, "BOTTOMLEFT", 0, -2)
    list:SetPoint("BOTTOMRIGHT", -1, 4)
end

function T.RefreshList(keepOffset)
    if not list then return end
    local rows = Rows()
    if #FT.Craft.List() == 0 then
        list:SetEmptyText(L["No recipes yet. Open each profession window once (or let Mastercraft learn them) and they show up here."])
    else
        list:SetEmptyText(L["Nothing matches"])
    end
    list:SetItems(rows, keepOffset)
    UpdateSummary(rows)
    if not state.selected and rows[1] then
        state.selected = rows[1].r.key
        list:Refresh()
    end
    T.ShowDetail()
end

---------------------------------------------------------------------------
-- Detail
---------------------------------------------------------------------------
local SOURCE_TAG = { ah = "AH", vendor = "vendor", ["vendor~"] = "vendor~", craft = "craft" }

local function BuildDetail(p)
    local d = UI.Panel(p, "bg1", "line")
    d:SetPoint("TOPRIGHT", -8, -70)
    d:SetPoint("BOTTOMRIGHT", -8, 8)
    d:SetWidth(DETAIL_W)
    detail = d

    d.icon = UI.Icon(d, 34)
    d.icon:SetPoint("TOPLEFT", 12, -12)
    d.icon:EnableMouse(true)
    d.icon:SetScript("OnEnter", function(self) if d.r then UI.TipItem(self, d.r.output) end end)
    d.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    d.name = UI.Text(d, 14, "text")
    d.name:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 10, -1)
    d.name:SetPoint("RIGHT", d, "RIGHT", -12, 0)
    d.sub = UI.Text(d, 11, "dim")
    d.sub:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -5)
    d.sub:SetPoint("RIGHT", d, "RIGHT", -12, 0)

    d.badge = UI.Badge(d, 84, 20)
    d.badge:SetPoint("TOPLEFT", 12, -58)
    d.reason = UI.Text(d, 12, "text")
    d.reason:SetPoint("LEFT", d.badge, "RIGHT", 10, 0)
    d.reason:SetPoint("RIGHT", d, "RIGHT", -12, 0)

    -- numbers
    local defs = {
        { "cost", L["Cost per craft"] }, { "revenue", L["Brings in"] },
        { "profit", L["Profit"] }, { "margin", L["Margin / ROI"] },
        { "price", L["Item price"] }, { "sell", L["Sell now?"] },
    }
    d.cells = {}
    for i, def in ipairs(defs) do
        local col = (i - 1) % 2
        local rowI = math.floor((i - 1) / 2)
        local l = UI.Text(d, 10, "dim")
        l:SetPoint("TOPLEFT", 12 + col * (DETAIL_W / 2), -88 - rowI * 34)
        l:SetText(def[2])
        local v = UI.Text(d, 13, "text")
        v:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -3)
        v:SetWidth(DETAIL_W / 2 - 20)
        d.cells[def[1]] = v
    end

    -- two charts: the item's price, and the profit of one craft (zero in the middle)
    d.chart = UI.Chart(d)
    d.chart:SetPoint("TOPLEFT", 1, -192)
    d.chart:SetPoint("TOPRIGHT", -1, -192)
    d.chart:SetHeight(120)
    d.pchart = UI.Chart(d)
    d.pchart:SetPoint("TOPLEFT", d.chart, "BOTTOMLEFT", 0, -4)
    d.pchart:SetPoint("TOPRIGHT", d.chart, "BOTTOMRIGHT", 0, -4)
    d.pchart:SetHeight(120)
    UI.OnSize(d, function(self, w, h)
        -- the charts give way so at least four materials stay visible
        local free = h - 192 - 4 - 44 - 22 - 4 * 22
        local each = math.max(80, math.min(150, math.floor(free / 2)))
        self.chart:SetHeight(each)
        self.pchart:SetHeight(each)
    end)

    d.matsTitle = UI.Text(d, 11, "muted")
    d.matsTitle:SetPoint("TOPLEFT", d.pchart, "BOTTOMLEFT", 11, -8)
    d.matsTitle:SetText(L["Materials"])
    local cols = {
        { key = "name", title = "", width = "fill", make = function(row)
            local f = CreateFrame("Frame", nil, row)
            f:SetHeight(22)
            f.icon = UI.Icon(f, 16)
            f.icon:SetPoint("LEFT")
            f.text = UI.Text(f, 11, "text")
            f.text:SetPoint("LEFT", f.icon, "RIGHT", 6, 0)
            f.text:SetPoint("RIGHT")
            return f
        end, cellHeight = 22 },
        { key = "unit", title = "", width = 92, justify = "RIGHT", size = 11 },
        { key = "total", title = "", width = 66, justify = "RIGHT", size = 11 },
    }
    d.mats = UI.List(d, {
        rowHeight = 22, cols = cols,
        update = function(row, part)
            local c = row.cells.name
            c.icon:SetItem(part.itemID)
            local buy = ""
            if part.source == "ah" then
                local sig = FT.An.BuySignal(FT.An.Stats(part.itemID))
                if sig == "BUY" then buy = " " .. FT.C("up", L["dip"]) end
            end
            c.text:SetText(FT.ItemText(part.itemID, 24) .. FT.C("dim", " x" .. part.qty) .. buy)
            local tag = part.source and FT.C("dim", " " .. L[SOURCE_TAG[part.source] or part.source]) or ""
            row.cells.unit:SetText(part.unit and (FT.Money(part.unit, "short") .. tag) or FT.C("down", L["no price"]))
            row.cells.total:SetText(part.total and FT.Money(part.total, "short") or "")
        end,
        onClick = function(part, button)
            if UI.ItemClick(part.itemID) then return end
            FT.OpenItem(part.itemID)
        end,
        onEnter = function(row, part)
            UI.TipItem(row, part.itemID)
            if part.via then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(string.format(L["Cheaper to craft yourself (%s)"], part.via.name or ""), 0.05, 0.8, 0.5)
                GameTooltip:Show()
            end
        end,
    })
    d.mats:SetPoint("TOPLEFT", d.pchart, "BOTTOMLEFT", 0, -24)
    d.mats:SetPoint("BOTTOMRIGHT", -1, 44)

    d.btnSearch = UI.Button(d, L["Search on AH"], 10, 24, "primary", function()
        if not d.r then return end
        local ids = { d.r.output }
        for _, rg in ipairs(d.r.reagents) do ids[#ids + 1] = rg.itemID end
        FT.SearchItems(ids)
    end)
    d.btnSearch:FitText(24)
    d.btnSearch:SetPoint("BOTTOMLEFT", 12, 10)
    d.btnSearch:SetTip(L["Search on AH"], L["Searches the item and all its materials: in Auctionator's Shopping tab when it is installed, otherwise with ForeverTrading's scanner. The auction house must be open; fresh prices and order books follow."])
    d.btnChart = UI.Button(d, L["Price chart"], 10, 24, "default", function()
        if d.r then FT.OpenItem(d.r.output) end
    end)
    d.btnChart:FitText(20)
    d.btnChart:SetPoint("LEFT", d.btnSearch, "RIGHT", 8, 0)
    d.btnWatch = UI.Button(d, L["Watch"], 10, 24, "default", function()
        if d.r then
            FT.Market.ToggleWatch(d.r.output)
            T.ShowDetail()
        end
    end)
    d.btnWatch:SetPoint("LEFT", d.btnChart, "RIGHT", 8, 0)

    d.empty = UI.EmptyState(d, L["Pick a recipe"], L["Its costs, profit and materials show here."])
    d.empty:SetPoint("CENTER")
end

function T.ShowDetail()
    local d = detail
    if not d then return end
    local r = state.selected and FT.Craft.Find(state.selected)
    d.r = r
    local show = r ~= nil
    for _, region in ipairs({ d.icon, d.name, d.sub, d.badge, d.reason, d.chart, d.pchart, d.matsTitle, d.mats,
        d.btnSearch, d.btnChart, d.btnWatch }) do
        region:SetShown(show)
    end
    for _, v in pairs(d.cells) do v:SetShown(show) end
    d.empty:SetShown(not show)
    if not r then return end
    local e = FT.Craft.Eval(r)
    d.icon:SetItem(r.output)
    d.name:SetText(FT.ItemText(r.output, 36) .. (r.outputQty > 1 and FT.C("dim", string.format(" x%g", r.outputQty)) or ""))
    d.sub:SetText(ProfName(r.prof) .. FT.C("dim", "  ·  ") .. FT.Craft.KnownByText(r))
    d.badge:Set(e.signal, nil, e.strength)
    d.reason:SetText(e.reason or "")

    d.cells.cost:SetText(e.complete and FT.Money(e.cost) or FT.C("dim", L["incomplete"]))
    local rev = e.revenue and FT.Money(e.revenue) or FT.C("dim", "—")
    if e.via == "vendor" then rev = rev .. FT.C("dim", " (" .. L["vendor"] .. ")") end
    d.cells.revenue:SetText(rev)
    if e.profit then
        d.cells.profit:SetText(FT.C(e.profit >= 0 and "up" or "down", FT.Money(e.profit)))
        d.cells.margin:SetText(string.format("%d%%  /  %d%%", math.floor((e.margin or 0) * 100 + 0.5), math.floor((e.roi or 0) * 100 + 0.5)))
    else
        d.cells.profit:SetText(FT.C("dim", "—"))
        d.cells.margin:SetText(FT.C("dim", "—"))
    end
    d.cells.price:SetText((e.sellUnit and FT.Money(e.sellUnit, "short") or "—") .. "  " .. FT.Pct(e.stats.ch7) .. FT.C("dim", " 7d"))
    local liqNames = { high = L["high"], medium = L["medium"], low = L["low"] }
    d.cells.sell:SetText(FT.C(FT.SIGNAL_COLORS[e.sell] or "muted", FT.SignalText(e.sell)) .. FT.C("dim", "  ·  " .. L["liquidity"] .. " " .. liqNames[e.liquidity]))

    d.chart:SetData({
        candles = FT.Hist.Daily(r.output, 30),
        mode = "line",
        lineColor = "accent",
        tagColor = "accent",
        title = L["Price"],
        fmt = function(v) return FT.Money(v, "short") end,
        defaultCount = 30,
        emptyTitle = L["No price history"],
        emptyBody = L["No prices for it yet: scan My items or run a full scan at the auction house."],
    })
    d.pchart:SetData({
        candles = UI.LineCandles(FT.Craft.History(r, 30), "profit"),
        mode = "line",
        centerZero = true,
        title = L["Profit per craft"],
        fmt = FT.SignedMoney,
        defaultCount = 30,
        emptyTitle = L["No history yet"],
        emptyBody = L["Needs a few days of prices for the item and its materials."],
    })
    d.mats:SetItems(e.parts)
    local watched = FT.Market.IsWatched(r.output)
    d.btnWatch:SetLabel(watched and L["In watchlist"] or L["Watch"])
    d.btnWatch:SetActive(watched)
    d.btnWatch:FitText(20)
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
function T.Build(p)
    page = p
    BuildToolbar(p)
    BuildTable(p)
    BuildDetail(p)
end

function T.Select(key)
    state.selected = key
    if list then
        list:Refresh()
        for i, x in ipairs(list.items) do
            if x.r.key == key then
                list:ScrollTo(i)
                break
            end
        end
    end
    T.ShowDetail()
end

function T.Refresh()
    UpdateFilters()
    T.RefreshList(true)
end

T.OnShow = T.Refresh
