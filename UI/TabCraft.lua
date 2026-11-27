-- Wolf: Craft page - every recipe your characters know: what it costs, what it brings in,
-- the profit and a signal; one recipe in detail with its margin over time and its materials.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local T = {}
FT.Tabs.craft = T

local state = { prof = "all", char = "all", profitable = false, search = "", sort = "profit", desc = true, selected = nil,
    view = "recipes" }
local queueView -- the craft queue (FT.Queue): what is queued, and what to buy for it
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
    local search = state.search ~= "" and FT.Fold(state.search) or nil
    for _, r in ipairs(FT.Craft.List()) do
        local ok = (state.prof == "all" or r.prof == state.prof) and (state.char == "all" or r.knownBy[state.char])
        local e
        if ok then
            e = FT.Craft.Eval(r)
            if state.profitable and not (e.profit and e.profit > 0) then ok = false end
        end
        if ok and search then
            local name = FT.Fold(FT.Name(r.output) or r.name or "")
            ok = name:find(search, 1, true) ~= nil or FT.Fold(r.name or ""):find(search, 1, true) ~= nil
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
            local na = FT.Fold(FT.Name(a.r.output) or a.r.name or "")
            local nb = FT.Fold(FT.Name(b.r.output) or b.r.name or "")
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
    UI.FitBits(summary, table.concat(parts, FT.C("dim", "   ||   ")))
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
    UI.ClearButton(T.search, function()
        state.search = ""
        T.RefreshList()
    end)

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

    -- the recipes, or the craft queue
    T.viewSeg = UI.Segmented(bar2, { { "recipes", L["Recipes"] }, { "queue", L["Craft queue"] }, { "level", L["Level it up"] },
        { "learn", L["Worth learning"] } }, function(v) T.SetView(v) end, 22)
    T.viewSeg:SetPoint("LEFT", 0, 0)
    T.viewSeg:SetValue(state.view)
    T.bar2Filters = { charDD, T.profitable, T.search }

    summary = UI.Text(bar2, 11, "muted")
    summary:SetPoint("LEFT", T.viewSeg, "RIGHT", 14, 0)
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
                if state.view == "level" or state.view == "learn" then T.RefreshPlan() else T.RefreshList() end
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
    T.tablePanel = panel
    panel:SetPoint("TOPLEFT", 8, -70)
    panel:SetPoint("BOTTOMRIGHT", -(DETAIL_W + 16), 8)
    local cols = {
        { key = "name", title = L["Recipe"], width = "fill", sort = "name", make = NameCell, cellHeight = 26 },
        { key = "cost", title = L["Cost"], width = 80, justify = "RIGHT", sort = "cost",
            tip = L["What one craft costs: each material at the cheapest of auction house, vendor or crafting it yourself."] },
        { key = "revenue", title = L["Sells for"], width = 80, justify = "RIGHT", sort = "revenue",
            tip = L["What one craft brings in at the auction house after its cut (or at a vendor, when that pays more)."] },
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
        liveID = function(x) return x.r.output end,
        update = function(row, x)
            local r, e = x.r, x.e
            local c = row.cells.name
            c.icon:SetItem(r.output)
            local qty = r.outputQty > 1 and FT.C("dim", string.format(" x%g", r.outputQty)) or ""
            c.text:SetText(FT.ItemText(r.output, 34) .. qty)
            row.cells.cost:SetText(e.complete and FT.Money(e.cost, "short") or FT.C("dim", "?"))
            row.cells.revenue:SetText(e.revenue and (FT.Money(e.revenue, "short") .. (e.via == "vendor" and FT.C("dim", " v") or "")
                .. (e.spike and FT.C("accent", " !") or "")) or FT.C("dim", "?"))
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
            GameTooltip:AddLine(L["Click: details || Right-click: price chart"], 0.52, 0.56, 0.61)
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
        list:SetEmptyText(L["No recipes yet. Open each profession window once and they show up here."])
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
    -- into the craft queue (click: one craft more, Shift: five)
    d.btnQueue = UI.Button(d, L["Queue it"], 10, 22, "default", function()
        if d.r then FT.Queue.Add(d.r.key, IsShiftKeyDown() and 5 or 1) end
    end)
    d.btnQueue:FitText(18)
    d.btnQueue:SetPoint("TOPRIGHT", -12, -12)
    d.btnQueue:SetTip(L["Queue it"], L["Click: one craft more in the craft queue, Shift-click: five. The queue (Craft queue, above) adds up the materials to buy for all of it."])
    d.name = UI.Text(d, 14, "text")
    d.name:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 10, -1)
    d.name:SetPoint("RIGHT", d.btnQueue, "LEFT", -8, 0)
    d.sub = UI.Text(d, 11, "dim")
    d.sub:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -5)
    d.sub:SetPoint("RIGHT", d, "RIGHT", -12, 0)

    d.badge = UI.Badge(d, 84, 20)
    d.badge:SetPoint("TOPLEFT", 12, -58)
    d.reason = UI.Text(d, 12, "text")
    d.reason:SetPoint("LEFT", d.badge, "RIGHT", 10, 0)
    d.reason:SetPoint("RIGHT", d, "RIGHT", -12, 0)
    -- worth crafting: the recipe in the game's profession window
    d.btnOpen = UI.Button(d, L["Open recipe"], 10, 22, "default", function()
        if d.r then FT.OpenRecipeInGame(d.r) end
    end)
    d.btnOpen:FitText(20)
    d.btnOpen:SetPoint("TOPRIGHT", -12, -57)
    d.btnOpen:Hide()

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
    d.more = UI.MoreButton(d.chart, function() return d.r and d.r.output end)
    d.pchart = UI.Chart(d)
    d.pchart:SetPoint("TOPLEFT", d.chart, "BOTTOMLEFT", 0, -4)
    d.pchart:SetPoint("TOPRIGHT", d.chart, "BOTTOMRIGHT", 0, -4)
    d.pchart:SetHeight(120)
    -- the materials under the charts (the compact window has no room for them: the charts take it, "More" and
    -- the Market show them)
    d.matsArea = CreateFrame("Frame", nil, d)
    d.matsArea:SetAllPoints(d)
    UI.OnSize(d, function(self, w, h)
        local compact = FT.Compact()
        self.matsArea:SetShown(not compact)
        -- the charts give way so at least four materials stay visible
        local free = compact and (h - 192 - 4 - 44 - 8) or (h - 192 - 4 - 44 - 22 - 4 * 22)
        local each = math.max(80, math.min(compact and 300 or 150, math.floor(free / 2)))
        self.chart:SetHeight(each)
        self.pchart:SetHeight(each)
    end)

    d.matsTitle = UI.Text(d.matsArea, 11, "muted")
    d.matsTitle:SetPoint("TOPLEFT", d.pchart, "BOTTOMLEFT", 11, -8)
    d.matsTitle:SetText(L["Materials"])
    d.liveText = UI.Text(d.matsArea, 11, "dim", "RIGHT")
    d.liveText:SetPoint("TOPRIGHT", d.pchart, "BOTTOMRIGHT", -11, -8)
    -- the countdown to the next live search of what the recipe makes
    d.ring = UI.LiveRingFor(d.matsArea, 9, function() return d.r and d:IsVisible() and d.r.output or nil end)
    d.ring:SetPoint("RIGHT", d.liveText, "LEFT", -5, 0)
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
    d.mats = UI.List(d.matsArea, {
        rowHeight = 22, cols = cols,
        liveID = function(part) return part.itemID end,
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
    d.btnSearch:SetTip(L["Search on AH"], L["Searches the item and all its materials: in Auctionator's Shopping tab when it is installed, otherwise with Wolf's scanner. The auction house must be open; fresh prices and order books follow."])
    d.btnSearch:Hide() -- v0.42: one way to each thing
    d.btnChart = UI.Button(d, L["Price chart"], 10, 24, "default", function()
        if d.r then FT.OpenItem(d.r.output) end
    end)
    d.btnChart:FitText(20)
    d.btnChart:SetPoint("BOTTOMLEFT", 12, 10)
    d.btnChart:Hide() -- v0.42: the recipe's name opens its page
    d.btnWatch = UI.Button(d, L["Watch"], 10, 24, "default", function()
        if d.r then
            FT.Market.ToggleWatch(d.r.output)
            T.ShowDetail()
        end
    end)
    d.btnWatch:SetPoint("BOTTOMLEFT", 12, 10)

    d.empty = UI.EmptyState(d, L["Pick a recipe"], L["Its costs, profit and materials show here."])
    d.empty:SetPoint("CENTER")
end

-- item names and colours arrived: the rows on screen show them
function T.OnItems()
    if list then list:Refresh() end
    if detail and detail.mats then detail.mats:Refresh() end
    if detail and detail.r then
        detail.name:SetText(FT.ItemText(detail.r.output, 36) .. (detail.r.outputQty > 1 and FT.C("dim", string.format(" x%g", detail.r.outputQty)) or ""))
    end
end

-- the materials of the chosen recipe bought at the auction house (or with no price yet)
local function LiveMaterials(r)
    return FT.Craft.MarketMaterials(r)
end

-- keepView: the charts keep their zoom (a live price came in)
function T.ShowDetail(keepView)
    local d = detail
    if not d then return end
    local r = state.selected and FT.Craft.Find(state.selected)
    d.r = r
    local show = r ~= nil
    for _, region in ipairs({ d.icon, d.name, d.sub, d.badge, d.reason, d.chart, d.pchart, d.matsTitle, d.liveText, d.mats,
        d.btnSearch, d.btnChart, d.btnWatch, d.btnQueue }) do
        region:SetShown(show)
    end
    for _, v in pairs(d.cells) do v:SetShown(show) end
    d.empty:SetShown(not show)
    if not r then
        d.btnOpen:Hide()
        return
    end
    local e = FT.Craft.Eval(r)
    d.icon:SetItem(r.output)
    d.name:SetText(FT.ItemText(r.output, 36) .. (r.outputQty > 1 and FT.C("dim", string.format(" x%g", r.outputQty)) or ""))
    d.sub:SetText(ProfName(r.prof) .. FT.C("dim", "  ||  ") .. FT.Craft.KnownByText(r))
    d.badge:Set(e.signal, nil, e.strength)
    d.reason:SetText(e.reason or "")
    -- worth crafting: open it in the profession window (this character must know it)
    local craft = e.signal == "CRAFT"
    d.btnOpen:SetShown(craft)
    d.reason:ClearAllPoints()
    d.reason:SetPoint("LEFT", d.badge, "RIGHT", 10, 0)
    if craft then
        d.reason:SetPoint("RIGHT", d.btnOpen, "LEFT", -8, 0)
        local mine = r.knownBy[UnitName("player")]
        d.btnOpen:SetUsable(mine == true)
        if mine then
            d.btnOpen:SetTip(L["Open recipe"], L["Opens this recipe in the game's profession window."])
        else
            d.btnOpen:SetTip(L["Open recipe"], string.format(L["Known by %s: log in with them to craft it."], FT.Craft.KnownByText(r)))
        end
    else
        d.reason:SetPoint("RIGHT", d, "RIGHT", -12, 0)
    end

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
    d.cells.price:SetText((e.sellUnit and FT.Money(e.sellUnit, "short") or "—") .. "  " .. FT.Pct(e.stats.ch7) .. FT.C("dim", " 7d")
        .. (e.spike and FT.C("accent", " !") or ""))
    -- live: the item and its materials searched in turn at the open auction house
    local on = FT.Scanner.LiveOn(r.output)
    for _, id in ipairs(LiveMaterials(r)) do on = on or FT.Scanner.LiveOn(id) end
    d.liveText:SetText(on and (FT.C("up", L["live"]) .. FT.C("dim", " || " .. L["the item and its materials"])) or "")
    local liqNames = { high = L["liq:high"], medium = L["liq:medium"], low = L["liq:low"], unknown = L["no data"] }
    -- how much really sells (seen from the listings) when known, else how often it is listed
    local sales = e.stats.sales and FT.Sales.PerDayText(e.stats.sales)
    d.cells.sell:SetText(FT.C(FT.SIGNAL_COLORS[e.sell] or "muted", FT.SignalText(e.sell)) .. FT.C("dim", "  ||  ")
        .. (sales and (FT.C(e.stats.slow and "down" or "text", L["sells"] .. " " .. sales))
            or FT.C("dim", L["liquidity"] .. " " .. liqNames[e.liquidity])))

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
    }, keepView)
    d.pchart:SetData({
        candles = UI.LineCandles(FT.Craft.History(r, 30), "profit"),
        mode = "line",
        centerZero = true,
        title = L["Profit per craft"],
        fmt = FT.SignedMoney,
        defaultCount = 30,
        emptyTitle = L["No history yet"],
        emptyBody = L["Needs a few days of prices for the item and its materials."],
    }, keepView)
    d.mats:SetItems(e.parts)
    local watched = FT.Market.IsWatched(r.output)
    d.btnWatch:SetLabel(watched and L["In watchlist"] or L["Watch"])
    d.btnWatch:SetActive(watched)
    d.btnWatch:FitText(20)
    T.UpdateQueueButton()
end

---------------------------------------------------------------------------
-- The craft queue
---------------------------------------------------------------------------
function T.UpdateQueueButton()
    local d = detail
    if not (d and d.r) then return end
    local n = FT.Queue.Count(d.r.key)
    d.btnQueue:SetLabel(n > 0 and string.format(L["Queued: %d"], n) or L["Queue it"])
    d.btnQueue:SetActive(n > 0)
    d.btnQueue:FitText(18)
end

local SOURCE_NAMES = { ah = "auction house", vendor = "vendor", ["vendor~"] = "vendor~", craft = "craft it" }

-- how many crafts: - n +  (Shift: five)
local function CraftsCell(row)
    local f = CreateFrame("Frame", nil, row)
    f:SetSize(104, 22)
    f.minus = UI.Button(f, "-", 22, 20, "default", function()
        if f.x then FT.Queue.Add(f.x.r.key, IsShiftKeyDown() and -5 or -1) end
    end)
    f.minus:SetPoint("LEFT", 0, 0)
    f.text = UI.Text(f, 12, "text", "CENTER")
    f.text:SetPoint("LEFT", f.minus, "RIGHT", 2, 0)
    f.text:SetWidth(52)
    f.plus = UI.Button(f, "+", 22, 20, "default", function()
        if f.x then FT.Queue.Add(f.x.r.key, IsShiftKeyDown() and 5 or 1) end
    end)
    f.plus:SetPoint("LEFT", f.text, "RIGHT", 2, 0)
    return f
end

local function DaysText(days)
    if not days then return FT.C("dim", "—") end
    local color = (days > 3 and "down") or (days > 1 and "accent") or "up"
    local n = days < 1 and string.format("%.1f", days) or FT.Num(math.floor(days + 0.5))
    return FT.C(color, string.format(L["~%s d"], n))
end

local function BuildQueue(p)
    local f = CreateFrame("Frame", nil, p)
    f:SetPoint("TOPLEFT", 8, -70)
    f:SetPoint("BOTTOMRIGHT", -8, 8)
    f:Hide()
    queueView = f

    -- the queued recipes
    f.left = UI.Panel(f, "bg1", "line")
    local cols = {
        { key = "name", title = L["Recipe"], width = "fill", make = NameCell, cellHeight = 26 },
        { key = "crafts", title = L["Crafts"], width = 104, justify = "CENTER", make = CraftsCell, cellHeight = 22 },
        { key = "makes", title = L["Makes"], width = 56, justify = "RIGHT" },
        { key = "profit", title = L["Profit"], width = 86, justify = "RIGHT" },
        { key = "days", title = L["To sell"], width = 64, justify = "RIGHT",
            tip = L["How long what the crafts make takes to sell at what really sells a day (seen from the listings)."] },
    }
    f.lhead = UI.Header(f.left, cols)
    f.lhead:SetPoint("TOPLEFT", 1, -1)
    f.lhead:SetPoint("TOPRIGHT", -1, -1)
    f.list = UI.List(f.left, {
        rowHeight = 28, cols = cols,
        update = function(row, x)
            local c = row.cells.name
            c.icon:SetItem(x.r.output)
            c.text:SetText(FT.ItemText(x.r.output, 32))
            row.cells.crafts.x = x
            row.cells.crafts.text:SetText(FT.Num(x.crafts))
            row.cells.makes:SetText(FT.Num(x.makes))
            local pr = x.profit
            row.cells.profit:SetText(pr and FT.C(pr >= 0 and "up" or "down", (pr >= 0 and "+" or "-") .. FT.Money(math.abs(pr), "short"))
                or FT.C("dim", "—"))
            row.cells.days:SetText(DaysText(x.days))
        end,
        onClick = function(x)
            if UI.ItemClick(x.r.output) then return end
            T.SetView("recipes")
            T.Select(x.r.key)
        end,
        onEnter = function(row, x)
            UI.TipItem(row, x.r.output)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(x.e.reason or "", 0.85, 0.87, 0.9, true)
            local sales = x.e.stats and x.e.stats.sales
            if sales then
                GameTooltip:AddLine(string.format(L["Sells %s: the %s it makes take about %s."], FT.Sales.PerDayText(sales),
                    FT.Num(x.makes), x.days and DaysText(x.days) or "—"), 0.85, 0.87, 0.9, true)
            end
            GameTooltip:AddLine(L["Click: the recipe. -/+ : one craft (Shift: five)."], 0.6, 0.62, 0.66, true)
            GameTooltip:Show()
        end,
    })
    f.list:SetPoint("TOPLEFT", f.lhead, "BOTTOMLEFT", 0, -2)
    f.list:SetPoint("BOTTOMRIGHT", -1, 4)
    f.list:SetEmptyText(L["The queue is empty: pick a recipe and press Queue it."])

    -- what to buy for all of it
    f.right = UI.Panel(f, "bg1", "line")
    local mcols = {
        { key = "name", title = L["Material"], width = "fill", make = NameCell, cellHeight = 26 },
        { key = "need", title = L["Need"], width = 50, justify = "RIGHT" },
        { key = "have", title = L["Have"], width = 50, justify = "RIGHT" },
        { key = "buy", title = L["Buy"], width = 50, justify = "RIGHT" },
        { key = "cost", title = L["Costs"], width = 90, justify = "RIGHT" },
    }
    f.rhead = UI.Header(f.right, mcols)
    f.rhead:SetPoint("TOPLEFT", 1, -1)
    f.rhead:SetPoint("TOPRIGHT", -1, -1)
    f.mats = UI.List(f.right, {
        rowHeight = 28, cols = mcols,
        update = function(row, m)
            local c = row.cells.name
            c.icon:SetItem(m.id)
            local src = m.source and FT.C("dim", " " .. L[SOURCE_NAMES[m.source] or m.source]) or ""
            c.text:SetText(FT.ItemText(m.id, 26) .. src)
            row.cells.need:SetText(FT.Num(m.need))
            row.cells.have:SetText(m.have > 0 and FT.C(m.have >= m.need and "up" or "text", FT.Num(m.have)) or FT.C("dim", "0"))
            row.cells.buy:SetText(m.buy > 0 and FT.C("accent", FT.Num(m.buy)) or FT.C("up", L["enough"]))
            row.cells.cost:SetText(m.buy == 0 and FT.C("dim", "—") or (m.cost and FT.Money(m.cost, "short")) or FT.C("down", L["no price"]))
        end,
        onClick = function(m)
            if UI.ItemClick(m.id) then return end
            FT.ShowDetail(m.id)
        end,
        onEnter = function(row, m)
            UI.TipItem(row, m.id)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(string.format(L["Need %s, have %s (bags and bank of this character): buy %s."], FT.Num(m.need), FT.Num(m.have),
                FT.Num(m.buy)), 0.85, 0.87, 0.9, true)
            if m.unit then
                GameTooltip:AddLine(string.format(L["At %s each: %s"], FT.Money(m.unit, "short"), L[SOURCE_NAMES[m.source] or m.source or ""] or ""), 0.85, 0.87, 0.9, true)
            end
            if m.via then
                GameTooltip:AddLine(string.format(L["Cheaper to craft yourself (%s)"], m.via.name or ""), 0.05, 0.8, 0.5, true)
            end
            GameTooltip:AddLine(L["Click: its order book - buy there."], 0.6, 0.62, 0.66, true)
            GameTooltip:Show()
        end,
    })
    f.mats:SetPoint("TOPLEFT", f.rhead, "BOTTOMLEFT", 0, -2)
    f.mats:SetPoint("BOTTOMRIGHT", -1, 4)
    f.mats:SetEmptyText(L["Nothing to buy."])

    -- totals, and the buttons
    f.total = UI.Text(f, 12, "text")
    f.search = UI.Button(f, L["Search materials on AH"], 10, 24, "primary", function()
        local _, mats = FT.Queue.Plan()
        local ids = {}
        for _, m in ipairs(mats) do
            if m.buy > 0 and m.source == "ah" then ids[#ids + 1] = m.id end
        end
        if #ids > 0 then FT.SearchItems(ids) end
    end)
    f.search:FitText(24)
    f.search:SetTip(L["Search materials on AH"], L["Searches what is left to buy: fresh prices and order books, so the costs above are of now. The auction house must be open."])
    f.clear = UI.Button(f, L["Clear the queue"], 10, 24, "default", function()
        UI.Confirm({ owner = "queueClear", title = L["Clear the queue"], text = L["Take every recipe out of the craft queue?"],
            ok = L["Clear the queue"], cancel = L["Cancel"], onOK = function() FT.Queue.Clear() end })
    end)
    f.clear:FitText(24)

    UI.OnSize(f, function(self, w, h)
        local lw = math.floor((w - 8) * 0.55)
        self.left:ClearAllPoints()
        self.left:SetPoint("TOPLEFT", 0, 0)
        self.left:SetPoint("BOTTOMLEFT", 0, 40)
        self.left:SetWidth(lw)
        self.right:ClearAllPoints()
        self.right:SetPoint("TOPLEFT", self.left, "TOPRIGHT", 8, 0)
        self.right:SetPoint("BOTTOMRIGHT", 0, 40)
        self.clear:ClearAllPoints()
        self.clear:SetPoint("BOTTOMRIGHT", 0, 6)
        self.search:ClearAllPoints()
        self.search:SetPoint("RIGHT", self.clear, "LEFT", -8, 0)
        self.total:ClearAllPoints()
        self.total:SetPoint("LEFT", self, "BOTTOMLEFT", 4, 18)
        self.total:SetPoint("RIGHT", self.search, "LEFT", -12, 0)
    end)
end

function T.RefreshQueue()
    local f = queueView
    if not (f and f:IsShown()) then return end
    local rows, mats, tot = FT.Queue.Plan()
    f.list:SetItems(rows, true)
    f.mats:SetItems(mats, true)
    local parts = {}
    if #rows > 0 then
        parts[#parts + 1] = string.format(L["%d crafts"], tot.crafts)
        parts[#parts + 1] = L["to buy"] .. " " .. FT.C("accent", FT.Money(tot.buy, "short"))
            .. (tot.missing > 0 and FT.C("down", " " .. string.format(L["(%d without a price)"], tot.missing)) or "")
        parts[#parts + 1] = L["brings"] .. " " .. FT.Money(tot.revenue, "short")
        parts[#parts + 1] = L["profit"] .. " " .. FT.C(tot.profit >= 0 and "up" or "down",
            (tot.profit >= 0 and "+" or "-") .. FT.Money(math.abs(tot.profit), "short"))
    end
    f.total:SetText(table.concat(parts, FT.C("dim", "   ||   ")))
    summary.fitText = nil
    summary:SetText(#rows > 0 and string.format(L["%d recipes in the queue"], #rows) or "")
end


---------------------------------------------------------------------------
-- Level it up and Worth learning (v0.50): two lists in the recipes' place; the profession chips filter them
---------------------------------------------------------------------------
local planViews = {}
local DIFF_COLOR = { optimal = { "ff8040", "Orange" }, medium = { "ffff00", "Yellow" }, easy = { "40c040", "Green" } }

local function PlanView(p, key, cols, update, onEnter, empty)
    local f = UI.Panel(p, "bg1", "line")
    f:SetPoint("TOPLEFT", 8, -70)
    f:SetPoint("BOTTOMRIGHT", -8, 34)
    f:Hide()
    f.head = UI.Header(f, cols)
    f.head:SetPoint("TOPLEFT", 1, -1)
    f.head:SetPoint("TOPRIGHT", -1, -1)
    f.list = UI.List(f, {
        rowHeight = 28, cols = cols, update = update,
        onClick = function(x)
            if UI.ItemClick(x.r.output) then return end
            if key == "level" then
                T.SetView("recipes")
                T.Select(x.r.key)
            else
                FT.OpenItem(x.r.output)
            end
        end,
        onEnter = onEnter,
    })
    f.list:SetPoint("TOPLEFT", f.head, "BOTTOMLEFT", 0, -2)
    f.list:SetPoint("BOTTOMRIGHT", -1, 4)
    f.list:SetEmptyText(empty)
    f.foot = UI.Text(p, 11, "dim")
    f.foot:SetPoint("BOTTOMLEFT", 12, 12)
    f.foot:SetPoint("BOTTOMRIGHT", -12, 12)
    if f.foot.SetWordWrap then f.foot:SetWordWrap(false) end
    f.foot:Hide()
    planViews[key] = f
    return f
end

local function Net(c)
    if not c then return FT.C("dim", "—") end
    -- a craft that pays for itself: a gain
    if c <= 0 then return FT.C("up", "+" .. FT.Money(-c, "short")) end
    return FT.C("down", "-" .. FT.Money(c, "short"))
end

local function BuildPlans(p)
    PlanView(p, "level", {
        { key = "name", title = L["Recipe"], width = "fill", make = NameCell, cellHeight = 26 },
        { key = "color", title = L["Colour"], width = 70 },
        { key = "rank", title = L["Skill"], width = 56, justify = "RIGHT" },
        { key = "net", title = L["A craft"], width = 90, justify = "RIGHT",
            tip = L["What one craft costs you once what it makes is sold (green: it pays for itself)."] },
        { key = "point", title = L["A point"], width = 90, justify = "RIGHT",
            tip = L["What a skill point costs: a craft over the chance it gives one (orange always, yellow ~3 in 4, green ~1 in 4)."] },
    }, function(row, x)
        local c = row.cells.name
        c.icon:SetItem(x.r.output)
        c.text:SetText(FT.ItemText(x.r.output, 32) .. FT.C("dim", "  " .. ProfName(x.prof)))
        local dc = DIFF_COLOR[x.diff]
        row.cells.color:SetText(dc and ("|cff" .. dc[1] .. L[dc[2]] .. "|r") or "")
        row.cells.rank:SetText(x.rank and FT.Num(x.rank) or FT.C("dim", "—"))
        row.cells.net:SetText(Net(x.net))
        row.cells.point:SetText(Net(x.perPoint))
    end, function(row, x)
        UI.TipItem(row, x.r.output)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format(L["Materials ~%s, what it makes sells for %s"], FT.Money(math.floor(x.e.cost), "short"),
            FT.Money(math.floor(x.e.revenue or 0), "short")), 0.85, 0.87, 0.9, true)
        GameTooltip:AddLine(L["The colour is as of when you last opened the profession window: open it again as you level."], 0.6, 0.62, 0.66, true)
        GameTooltip:AddLine(L["Click: the recipe."], 0.6, 0.62, 0.66, true)
        GameTooltip:Show()
    end, L["Open your profession window once: Wolf reads there which recipes still give a point."])

    PlanView(p, "learn", {
        { key = "name", title = L["Recipe"], width = "fill", make = NameCell, cellHeight = 26 },
        { key = "profit", title = L["Profit"], width = 86, justify = "RIGHT" },
        { key = "sells", title = L["Sells"], width = 70, justify = "RIGHT" },
        { key = "how", title = L["Where to get it"], width = 250 + 20 * (tonumber(FT.S and FT.S.textSize) or 0) },
        { key = "back", title = L["Pays back"], width = 76, justify = "RIGHT",
            tip = L["How many crafts pay for the recipe at its auction house price."] },
    }, function(row, x)
        local c = row.cells.name
        c.icon:SetItem(x.r.output)
        c.text:SetText(FT.ItemText(x.r.output, 30) .. FT.C("dim", "  " .. ProfName(x.r.prof)))
        row.cells.profit:SetText(FT.C("up", "+" .. FT.Money(math.floor(x.e.profit), "short")))
        row.cells.sells:SetText(string.format(L["~%s/d"], x.perDay >= 10 and FT.Num(math.floor(x.perDay + 0.5)) or string.format("%.1f", x.perDay)))
        UI.FitBits(row.cells.how, FT.Craft.LearnText(x))
        row.cells.back:SetText(x.payback and string.format(L["%d crafts"], x.payback) or FT.C("dim", "—"))
    end, function(row, x)
        UI.TipItem(row, x.r.output)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format(L["Costs ~%s to make, sells for %s after the cut"], FT.Money(math.floor(x.e.cost), "short"),
            FT.Money(math.floor(x.e.revenue), "short")), 0.85, 0.87, 0.9, true)
        GameTooltip:AddLine(FT.Craft.LearnText(x), 0.85, 0.87, 0.9, true)
        GameTooltip:AddLine(L["Click: its page."], 0.6, 0.62, 0.66, true)
        GameTooltip:Show()
    end, L["Nothing worth learning for your professions right now (or Wolf hasn't seen them yet: open a profession window once)."])
end

function T.RefreshPlan()
    local v = state.view
    local f = planViews[v]
    if not (f and f:IsShown()) then return end
    if v == "level" then
        local rows = FT.Craft.LevelUp(state.prof)
        f.list:SetItems(rows or {}, true)
        local bits = {}
        for k, n in pairs(FT.Me and FT.Me.MyProfs() or {}) do bits[#bits + 1] = ProfName(k) .. " " .. n end
        table.sort(bits)
        UI.FitBits(summary, #bits > 0 and table.concat(bits, "  ·  ") or "")
        f.foot:SetText(L["The cheapest point first. Orange: always a point · yellow: ~3 in 4 · green: ~1 in 4."])
    else
        local rows = FT.Craft.WorthLearning(state.prof)
        f.list:SetItems(rows, true)
        UI.FitBits(summary, string.format(L["%d recipes worth learning"], #rows))
        f.foot:SetText(L["Recipes none of your characters know, for professions they have, that make a profit and sell a day or more."])
    end
    f.foot:Show()
end

function T.SetView(view)
    state.view = view
    if T.viewSeg then T.viewSeg:SetValue(view) end
    local q = view == "queue"
    local plan = view == "level" or view == "learn"
    if T.tablePanel then T.tablePanel:SetShown(view == "recipes") end
    if detail then detail:SetShown(view == "recipes") end
    if queueView then queueView:SetShown(q) end
    for k, f in pairs(planViews) do
        f:SetShown(k == view)
        f.foot:SetShown(k == view)
    end
    if T.bar then T.bar:SetShown(not q) end
    for _, x in ipairs(T.bar2Filters or {}) do x:SetShown(view == "recipes") end
    if q then T.RefreshQueue() elseif plan then UpdateFilters(); T.RefreshPlan() else T.Refresh() end
end

FT.On("FT_QUEUE_CHANGED", function()
    T.UpdateQueueButton()
    T.RefreshQueue()
end)
-- the bags changed (bought, crafted): what is left to buy follows
FT.On("BAG_UPDATE_DELAYED", function() FT.Debounce("queueBags", 1, T.RefreshQueue) end)

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
function T.Build(p)
    page = p
    BuildToolbar(p)
    BuildTable(p)
    BuildDetail(p)
    BuildQueue(p)
    BuildPlans(p)
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
    -- with the auction house open what it makes is searched now
    if detail and detail.r then FT.Scanner.LiveNow(detail.r.output) end
end

function T.Refresh()
    if state.view == "queue" then return T.RefreshQueue() end
    if state.view == "level" or state.view == "learn" then UpdateFilters(); return T.RefreshPlan() end
    UpdateFilters()
    T.RefreshList(true)
end

-- kept live at the auction house: what the chosen recipe makes, then its materials in turn - its cost and
-- profit follow the market too
function T.LiveItems()
    local r = detail and detail:IsVisible() and detail.r
    if not r then return nil end
    local list = { r.output }
    for _, id in ipairs(LiveMaterials(r)) do list[#list + 1] = id end
    return list
end

-- a live price came in (id), or the auction house opened or closed (nil)
function T.OnLive(_, id)
    local r = detail and detail.r
    if not r then return end
    local mine = id == nil or id == r.output
    if not mine then
        for _, rg in ipairs(r.reagents) do
            if rg.itemID == id then mine = true end
        end
    end
    if mine then
        T.ShowDetail(true)
        if list then
            -- its row in the table shows the new cost and profit too
            for _, x in ipairs(list.items) do
                if x.r == r then x.e = FT.Craft.Eval(r) end
            end
            list:Refresh()
        end
    end
end

T.OnShow = T.Refresh
