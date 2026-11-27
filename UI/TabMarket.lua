-- Wolf: Market page - every item with its price and moves, the chart of one item, and three answers
-- under it: the market's health, the price's trend, the call. With no item chosen: the market overview.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local T = {}
FT.Tabs.market = T

-- open: under "My recipes", the item whose materials are shown under it
-- the height of a move card: two lines of its sentence, at the chosen text size
local function MOVE_H() return 60 + 9 * (tonumber(FT.S and FT.S.textSize) or 0) end
local state = { filter = "all", cls = "all", sub = "all", sort = "cap", desc = true, search = "", selected = nil, open = nil,
    home = true } -- home: the market overview on the right (v0.43: Market opens on it; "< Market" on an item goes back)
-- the auction house's own filters: required level, usable, not collected, quality
local QUALITIES = { 0, 1, 2, 3, 4, 5 }
local filt = { min = nil, max = nil, usable = false, uncollected = false, quality = {} }
for _, q in ipairs(QUALITIES) do filt.quality[q] = true end

local function FiltersOn()
    if filt.min or filt.max or filt.usable or filt.uncollected then return true end
    for _, q in ipairs(QUALITIES) do
        if not filt.quality[q] then return true end
    end
    return false
end

-- the game's own "can this character use it" (armor and weapon skills, class); without it only the level counts
local CanUse = C_PlayerInfo and C_PlayerInfo.CanUseItem
local Transmog = C_TransmogCollection
local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

-- collected: true / false; nil when it isn't something to collect (an appearance, a toy)
local function Collected(id)
    if PlayerHasToy and C_ToyBox and C_ToyBox.GetToyInfo and C_ToyBox.GetToyInfo(id) then return PlayerHasToy(id) end
    if Transmog and Transmog.PlayerHasTransmog then
        local equip = GetInstant and select(4, GetInstant(id))
        if equip and equip ~= "" and equip ~= "INVTYPE_NON_EQUIP_IGNORE" and equip ~= "INVTYPE_BAG" then
            local ok, has = pcall(Transmog.PlayerHasTransmog, id)
            if ok then return has and true or false end
        end
    end
    return nil
end

-- the "not collected" filter only where the game keeps collections
local function CanCollect()
    return (Transmog and Transmog.PlayerHasTransmog) ~= nil or PlayerHasToy ~= nil
end

-- an item passes the filters (what the game hasn't loaded yet passes the level and usable ones)
local function PassFilters(id)
    local q, lvl = FT.ItemFacts(id)
    if q and filt.quality[q] == false then return false end
    if lvl then
        if filt.min and lvl < filt.min then return false end
        if filt.max and lvl > filt.max then return false end
    end
    if filt.usable then
        if lvl and lvl > (UnitLevel("player") or 0) then return false end
        if CanUse and FT.ItemCached(id) then
            local ok, usable = pcall(CanUse, id)
            if ok and usable == false then return false end
        end
    end
    if filt.uncollected and Collected(id) ~= false then return false end
    return true
end
local page, list, countText, overview, itemView, center, mats
local LEFT_W = 372
-- the right side (craft breakdown): a little wider with the larger text sizes, so names fit
local function RIGHT_W() return 280 + 10 * (tonumber(FT.S and FT.S.textSize) or 0) end
local CARDS_H = 132 -- the market, price and call cards under the charts (124 high, 8 above them)

local GetClassInfo = (C_Item and C_Item.GetItemClassInfo) or GetItemClassInfo
local GetSubClassInfo = (C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo
local CLASSES = { 7, 0, 9, 5, 4, 2, 15, 1 }
local CLASS_FALLBACK = { [7] = "Trade goods", [0] = "Consumables", [9] = "Recipes", [5] = "Reagents", [4] = "Armor",
    [2] = "Weapons", [15] = "Miscellaneous", [1] = "Containers" }
local KNOWN = {}
for _, c in ipairs(CLASSES) do KNOWN[c] = true end

local function ClassName(id)
    local name = GetClassInfo and GetClassInfo(id)
    return (name and name ~= "") and name or L[CLASS_FALLBACK[id] or "Other"]
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------
-- what your recipes make (their materials show under an item when you open it)
local function RecipeOutputs()
    local set = {}
    for _, r in ipairs(FT.Craft.List()) do set[r.output] = true end
    return set
end

local SOURCE_TAG = { ah = "AH", vendor = "vendor", ["vendor~"] = "vendor~", craft = "craft" }

-- the materials of one craft of the item, as rows under it: each at its cheapest (auction house, vendor,
-- your own craft), with the market's moves when it has them
local function MaterialRows(id)
    local r = FT.Craft.Best(id)
    if not r then return {} end
    local kids = {}
    for _, part in ipairs(FT.Craft.Eval(r).parts or {}) do
        if part.itemID then
            local m = FT.Market.Row(part.itemID)
            kids[#kids + 1] = {
                id = part.itemID, child = true, parent = id, qty = part.qty, unit = part.unit, source = part.source,
                price = part.unit or (m and m.price), ch1 = m and m.ch1, ch7 = m and m.ch7, spark = m and m.spark or {},
            }
        end
    end
    return kids
end

local SORTS = {
    cap = function(r) return r.price * (r.qty or 0) end,
    price = function(r) return r.price end,
    ch1 = function(r) return r.ch1 end,
    ch7 = function(r) return r.ch7 end,
    qty = function(r) return r.qty end,
}

-- The sorted list kept for the next draw, until the market, your items, names or the list's choices change
local baseKey, baseRows
local listVersion = 0
local function ListChanged() listVersion = listVersion + 1 end
for _, ev in ipairs({ "FT_MARKET_READY", "FT_LIVE_UPDATED", "FT_WATCH_CHANGED", "FT_OWNED_CHANGED", "FT_INVENTORY_CHANGED",
    "FT_ITEMS_LOADED", "FT_RECIPES_CHANGED", "FT_SETTINGS_CHANGED", "FT_HOUSE_CHANGED", "FT_SCAN_DONE", "FT_PRICES_CHANGED",
    "FT_ITEMS_DROPPED", "FT_DATA_CLEARED" }) do
    FT.On(ev, ListChanged)
end
T.ListChanged = ListChanged
local function BaseKey(rows)
    local q = {}
    for _, k in ipairs(QUALITIES) do q[#q + 1] = filt.quality[k] == false and "0" or "1" end
    return table.concat({ tostring(rows), listVersion, state.filter, tostring(state.cls), tostring(state.sub), state.search or "",
        tostring(state.sort), tostring(state.desc), tostring(filt.min), tostring(filt.max), tostring(filt.usable),
        tostring(filt.uncollected), table.concat(q), tostring(UnitLevel and UnitLevel("player")) }, "|")
end

local function Filtered()
    local rows = FT.Market.Rows()
    if not rows then return nil end
    -- one item opened (its name in the search box, nothing else changed): just its row, no look through them all
    if state.only and state.search == state.onlySearch and state.filter == "all" and state.cls == "all" and state.sub == "all" and not FiltersOn() then
        local r = FT.Market.Row(state.only)
        if r then return { r }, 1 end
    end
    state.only = nil
    -- the same list as last time (nothing in it or about it changed): no look through them all, no sort
    local cacheKey = BaseKey(rows)
    local mine = state.filter == "mine" and RecipeOutputs() or nil
    local out
    if baseKey == cacheKey and baseRows then
        out = {}
        for i, r in ipairs(baseRows) do out[i] = r end
    else
        out = {}
        -- "name" in quotes: that name exactly (not the recipes for it and such); otherwise a part of the name
        local matches = FT.NameMatcher(state.search)
        local filtersOn = FiltersOn()
        local holdings = state.filter == "bags" and FT.Port.Holdings() or nil
        for _, r in ipairs(rows) do
            local ok = true
            local f = state.filter
            if f == "fav" then
                ok = FT.db.watch[r.id] ~= nil
            elseif f == "mine" then
                ok = mine[r.id] == true
            elseif f == "bags" then
                ok = holdings[r.id] ~= nil
            elseif f == "up" then
                ok = r.ch1 ~= nil and r.ch1 > 0.001
            elseif f == "down" then
                ok = r.ch1 ~= nil and r.ch1 < -0.001
            end
            if ok and state.cls ~= "all" then
                if state.cls == "other" then ok = not KNOWN[r.cls] else ok = r.cls == state.cls end
            end
            if ok and state.sub ~= "all" then ok = r.sub == state.sub end
            if ok and filtersOn then ok = PassFilters(r.id) end
            if ok and matches then ok = matches(r.id) end
            -- grey items and white gear: left out of the lists unless you search them by name (or watch / own them)
            if ok and not matches and (f == "all" or f == "up" or f == "down") and FT.Market.Junk(r) then ok = false end
            if ok then out[#out + 1] = r end
        end
        local key, desc = state.sort, state.desc
        if key == "name" then
            local names = {}
            for _, r in ipairs(out) do names[r.id] = FT.Fold(FT.Name(r.id) or "~") end
            table.sort(out, function(a, b)
                if names[a.id] ~= names[b.id] then
                    if desc then return names[a.id] > names[b.id] end
                    return names[a.id] < names[b.id]
                end
                return a.id < b.id
            end)
        else
            local get = SORTS[key] or SORTS.cap
            local missing = desc and -math.huge or math.huge
            -- each row's value worked out once (not twice per comparison: ~13 times each for 7,000 rows)
            local val = {}
            for _, r in ipairs(out) do val[r] = get(r) or missing end
            if desc then
                table.sort(out, function(a, b)
                    local va, vb = val[a], val[b]
                    if va ~= vb then return va > vb end
                    return a.id < b.id
                end)
            else
                table.sort(out, function(a, b)
                    local va, vb = val[a], val[b]
                    if va ~= vb then return va < vb end
                    return a.id < b.id
                end)
            end
        end
        baseKey, baseRows = cacheKey, {}
        for i, r in ipairs(out) do baseRows[i] = r end
    end
    -- My recipes: the open item's materials under it
    local count = #out
    -- the watchlist: by group (yours first, in your order; then by kind), each under a header that folds it
    if state.filter == "fav" then
        local byGroup, order = {}, {}
        for _, r in ipairs(out) do
            local g, own = FT.Market.GroupOf(r.id)
            if not byGroup[g] then
                byGroup[g] = { rows = {}, own = own, value = 0 }
                order[#order + 1] = g
            end
            table.insert(byGroup[g].rows, r)
            byGroup[g].value = byGroup[g].value + (r.price or 0) * FT.Port.Count(r.id)
        end
        local rank = {}
        for i, g in ipairs(FT.Market.WatchGroups()) do rank[g] = i end
        table.sort(order, function(a, b)
            local ra, rb = rank[a] or 1000, rank[b] or 1000
            if ra ~= rb then return ra < rb end
            return a < b
        end)
        state.closed = state.closed or {}
        local grouped = {}
        for _, g in ipairs(order) do
            local x = byGroup[g]
            grouped[#grouped + 1] = { header = true, id = "group:" .. g, group = g, own = x.own, n = #x.rows, value = x.value }
            if not state.closed[g] then
                for _, r in ipairs(x.rows) do grouped[#grouped + 1] = r end
            end
        end
        return grouped, count
    end
    if mine and state.open then
        for i, r in ipairs(out) do
            if r.id == state.open then
                for k, kid in ipairs(MaterialRows(r.id)) do table.insert(out, i + k, kid) end
                break
            end
        end
    end
    return out, count
end

-- Names the game hasn't loaded yet: a search can only find a name it knows. While you search, 80 every quarter
-- second; in the background after login (background), 20 a second until every item on the market has its name -
-- they're kept between sessions, so a search finds "thor" the first time after that.
local loader, loaderQuiet
function T.LoadMissingNames(background)
    if loader then
        -- a search while the quiet one runs: faster from now on
        if not background and loaderQuiet then loader:Cancel(); loader = nil else return end
    end
    if not background then FT.LoudItems() end
    local missing = {}
    for _, r in ipairs(FT.Market.Rows() or {}) do
        if not FT.Name(r.id) then missing[#missing + 1] = r.id end
    end
    if #missing == 0 then return end
    local i = 1
    local per, every = background and 10 or 80, background and 0.5 or 0.25
    loaderQuiet = background
    loader = C_Timer.NewTicker(every, function()
        local stop = i > #missing or (not background and state.search == "" and not FiltersOn())
        if stop then
            loader:Cancel()
            loader = nil
            -- a search stopped early: the rest quietly
            if i <= #missing and not background then C_Timer.After(5, function() T.LoadMissingNames(true) end) end
            return
        end
        if background and InCombatLockdown and InCombatLockdown() then return end
        for k = i, math.min(i + per - 1, #missing) do FT.RequestItem(missing[k], background) end
        i = i + per
    end)
end
-- once the market is known after login, the names it lacks, quietly
local namesAsked = false
FT.On("FT_MARKET_READY", function()
    if namesAsked then return end
    namesAsked = true
    C_Timer.After(90, function() T.LoadMissingNames(true) end)
end)

-- names arrived: the rows on screen show them; a search takes the new matches in now and then
function T.OnItems()
    ListChanged() -- names came in: a search or the name sort can differ
    -- an item opened from elsewhere before the game had its name: now it goes in the search box
    local id = state.focusFor
    local name = id and state.search == "" and FT.Name(id)
    if name then
        state.focusFor = nil
        state.search = '"' .. name .. '"'
        if T.searchBox then T.searchBox:SetValue(state.search) end
        T.RefreshList()
        return
    end
    if list then list:Refresh() end
    if state.search ~= "" or FiltersOn() then
        FT.Debounce("marketSearchMore", 1.5, function() T.RefreshList(true) end)
    end
end

-- the subcategories of the chosen category that are on the market, with how many items each
local function UpdateSubs()
    local dd = T.subDD
    if not dd then return end
    local opts = { { "all", L["All subcategories"] } }
    local real = state.cls ~= "all" and state.cls ~= "other"
    if real then
        local counts = {}
        for _, r in ipairs(FT.Market.Rows() or {}) do
            if r.cls == state.cls and r.sub then counts[r.sub] = (counts[r.sub] or 0) + 1 end
        end
        local subs = {}
        for sub, n in pairs(counts) do
            local name = GetSubClassInfo and GetSubClassInfo(state.cls, sub)
            subs[#subs + 1] = { sub, (name and name ~= "") and name or ("#" .. sub), n }
        end
        table.sort(subs, function(a, b) return a[2] < b[2] end)
        for _, s in ipairs(subs) do opts[#opts + 1] = { s[1], s[2] .. FT.C("dim", "  " .. FT.Num(s[3])) } end
    end
    dd:SetOptions(opts)
    local found = false
    for _, o in ipairs(opts) do
        if o[1] == state.sub then found = true end
    end
    if not found then state.sub = "all" end
    dd:SetValue(state.sub)
    UI.SetTextColor(dd.label, real and "text" or "dim")
end

-- the chips of what the Filter popup has set: the category (or its subcategory) and "Filters" (level, usable,
-- quality); each × clears its part. The Filter button counts them.
local activeChips = {}
local function UpdateActive()
    local row = T.activeRow
    if not row then return end
    local parts = {}
    if state.cls ~= "all" then
        local name = state.cls == "other" and L["Other"] or ClassName(state.cls)
        if state.sub ~= "all" and GetSubClassInfo then
            local sn = GetSubClassInfo(state.cls, state.sub)
            if sn and sn ~= "" then name = sn end
        end
        parts[#parts + 1] = { name, function()
            state.cls, state.sub = "all", "all"
            if T.clsDD then T.clsDD:SetValue("all") end
            T.RefreshList()
        end }
    end
    if FiltersOn() then
        parts[#parts + 1] = { L["Filters"], function()
            T.ResetFilters()
            T.SyncFilters()
        end }
    end
    local x = 0
    for i, part in ipairs(parts) do
        local c = activeChips[i]
        if not c then
            c = UI.Button(row, "", 10, row:GetHeight(), "ghost", function(self) if self.clear then self.clear() end end)
            c:SetTip(L["Clear"], L["Shows everything of this kind again."])
            activeChips[i] = c
        end
        c.clear = part[2]
        c:SetLabel(FT.C("accent", part[1]) .. FT.C("dim", "  ×"))
        c:FitText(14)
        c:ClearAllPoints()
        c:SetPoint("LEFT", x, 0)
        c:Show()
        x = x + c:GetWidth() + 4
    end
    for i = #parts + 1, #activeChips do activeChips[i]:Hide() end
    if T.filterBtn then T.filterBtn:SetLabel(#parts > 0 and (L["Filter"] .. " (" .. #parts .. ")") or L["Filter"]) end
end

function T.RefreshList(keepOffset)
    if not list then return end
    UpdateSubs()
    UpdateActive()
    local items, count = Filtered()
    if not items then
        list:SetEmptyText(FT.Market.Building() and L["Reading the market..."] or
            L["No market data yet: open the auction house and press Full scan."])
        list:SetItems({}, keepOffset)
        countText:SetText("")
        return
    end
    list:SetEmptyText(L["Nothing matches"])
    list:SetItems(items, keepOffset)
    countText:SetText(string.format(L["%s items"], FT.Num(count)))
end

-- My recipes: open an item's materials under it (again: close them)
local function ToggleOpen(id)
    state.open = state.open ~= id and id or nil
    T.RefreshList(true)
    if not (state.open and list) then return end
    for i, x in ipairs(list.items) do
        if x.id == id and not x.child then
            -- its materials in sight, the item too
            local last = i
            while list.items[last + 1] and list.items[last + 1].child do last = last + 1 end
            list:ScrollTo(last)
            list:ScrollTo(i)
            break
        end
    end
end

local function NameCell(row)
    local f = CreateFrame("Frame", nil, row)
    f:SetHeight(24)
    -- My recipes: an arrow to open the materials
    f.chev = UI.Chevron(f, 8, "muted")
    f.chev:SetPoint("LEFT", 2, 0)
    f.chev:Hide()
    f.icon = UI.Icon(f, 18)
    f.icon:SetPoint("LEFT", 0, 0)
    f.star = UI.Text(f, 11, "accent")
    f.star:SetPoint("LEFT", f.icon, "RIGHT", 5, 0)
    f.text = UI.Text(f, 12, "text")
    f.text:SetPoint("LEFT", f.icon, "RIGHT", 6, 0)
    f.text:SetPoint("RIGHT", 0, 0)
    return f
end

local function SparkCell(row)
    local s = UI.Sparkline(row, 40, 16)
    return s
end

local function BuildList(parent)
    local panel = UI.Panel(parent, "bg1", "line")
    T.listPanel = panel
    panel:SetPoint("TOPLEFT", 8, -8)
    panel:SetPoint("BOTTOMLEFT", 8, 8)
    panel:SetWidth(LEFT_W)

    -- the filters: a grid of four columns, rows of one height, one gap between them all
    local IW, GAP, RH = LEFT_W - 20, 6, 20
    local CW = math.floor((IW - 3 * GAP) / 4)
    local function Cell(col, span) return 10 + (col - 1) * (CW + GAP), span * CW + (span - 1) * GAP end
    local search = UI.Input(panel, IW - 84, 24, L["Search item..."], function(text)
        state.search = text or ""
        state.focusFor = nil
        FT.Debounce("marketSearch", 0.25, function()
            T.RefreshList()
            if state.search ~= "" then T.LoadMissingNames() end
        end)
    end)
    search:SetPoint("TOPLEFT", 10, -10)
    T.searchBox = search
    T.filterBtn = UI.Button(panel, L["Filter"], 78, 24, "default", function(self) T.ToggleFilters(self) end)
    T.filterBtn:SetPoint("LEFT", search, "RIGHT", 6, 0)
    T.filterBtn:SetTip(L["Filter"], L["Required level, usable, not collected, quality - as on the auction house."])
    panel:HookScript("OnHide", function() if T.filterPanel then T.filterPanel:Hide() end end)
    -- × : the whole list again, the item you have open still in sight
    UI.ClearButton(search, function()
        state.search, state.focusFor = "", nil
        T.RefreshList()
        T.ShowSelectedInList()
    end)

    local chips = {}
    local function Chip(key, label)
        local c = UI.Chip(panel, label, function()
            state.filter = key
            for _, ch in ipairs(chips) do ch:SetOn(ch.key == key) end
            T.RefreshList()
        end)
        c.key = key
        chips[#chips + 1] = c
        return c
    end
    local row1 = { Chip("all", L["All"]), Chip("fav", L["Watchlist"]), Chip("mine", L["My recipes"]),
        Chip("bags", L["Owned"]) }
    -- another page asks for a list: the Watchlist, say
    function T.SetFilter(key)
        state.filter = key
        for _, ch in ipairs(chips) do ch:SetOn(ch.key == key) end
        T.RefreshList()
    end
    local row2 = { Chip("up", L["Rising"]), Chip("down", L["Falling"]) }
    local Y1, Y2 = -42, -42 - RH - GAP
    for i, c in ipairs(row1) do
        local x, w = Cell(i, 1)
        c:SetSize(w, RH)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", x, Y1)
    end
    for i, c in ipairs(row2) do
        local x, w = Cell(i, 1)
        c:SetSize(w, RH)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", x, Y2)
    end
    for _, c in ipairs(chips) do c:SetOn(c.key == state.filter) end
    T.chips = chips

    -- what's chosen in the Filter popup (category, subcategory, a filter on): chips under the Rising / Falling
    -- ones, each × clears it
    T.activeRow = CreateFrame("Frame", nil, panel)
    T.activeRow:SetPoint("TOPLEFT", select(1, Cell(3, 1)), Y2)
    T.activeRow:SetSize(select(2, Cell(3, 2)), RH)
    countText = UI.Text(panel, 11, "dim", "RIGHT")
    countText:SetPoint("BOTTOMRIGHT", -12, 6)

    local cols = {
        { key = "name", title = L["Item"], width = "fill", sort = "name", make = NameCell, cellHeight = 24 },
        { key = "price", title = L["Price"], width = 82, justify = "RIGHT", sort = "price" },
        { key = "ch1", title = L["24h"], width = 60, justify = "RIGHT", sort = "ch1" },
        { key = "spark", title = L["7d"], width = 40, justify = "RIGHT", sort = "ch7", make = SparkCell, cellHeight = 16 },
    }
    T.header = UI.Header(panel, cols, function(key)
        if state.sort == key then
            state.desc = not state.desc
        else
            state.sort, state.desc = key, key ~= "name"
        end
        T.header:SetSort(state.sort, state.desc)
        if T.sortDD then T.sortDD:SetValue(state.sort) end
        T.RefreshList()
    end)
    T.header:SetPoint("TOPLEFT", 1, Y2 - RH - 8)
    T.header:SetPoint("TOPRIGHT", -1, Y2 - RH - 8)
    T.header:SetSort(state.sort, state.desc)

    list = UI.List(panel, {
        rowHeight = 26,
        cols = cols,
        liveID = function(r) return not r.header and r.id or nil end,
        update = function(row, r)
            local cell = row.cells.name
            if r.header then
                -- a watchlist group: its name, how many, what you hold of it; folds on a click
                cell.chev:Show()
                local closed = state.closed and state.closed[r.group]
                cell.chev:SetDir(closed and "right" or "down", "accent")
                cell.icon:Hide()
                cell.star:SetText("")
                cell.text:ClearAllPoints()
                cell.text:SetPoint("LEFT", cell, "LEFT", 16, 0)
                cell.text:SetPoint("RIGHT", cell, "RIGHT", 0, 0)
                cell.text:SetText(FT.C(r.own and "accent" or "text", r.group) .. FT.C("dim", "  " .. r.n))
                row.cells.price:SetText(r.value > 0 and FT.C("dim", FT.Money(math.floor(r.value), "short")) or "")
                row.cells.ch1:SetText("")
                row.cells.spark:SetValues({}, "muted")
                return
            end
            cell.icon:Show()
            -- My recipes: the items with an arrow, their materials indented under them
            local indent = 0
            if state.filter == "mine" then
                if r.child then
                    indent = 30
                    cell.chev:Hide()
                else
                    indent = 14
                    local open = state.open == r.id
                    cell.chev:Show()
                    cell.chev:SetDir(open and "down" or "right", open and "accent" or "muted")
                end
            else
                cell.chev:Hide()
            end
            cell.icon:ClearAllPoints()
            cell.icon:SetPoint("LEFT", indent, 0)
            cell.icon:SetItem(r.id)
            local watched = FT.db.watch[r.id] ~= nil
            cell.star:SetText(watched and "*" or "")
            cell.text:ClearAllPoints()
            cell.text:SetPoint("LEFT", cell.icon, "RIGHT", watched and 14 or 6, 0)
            cell.text:SetPoint("RIGHT", cell, "RIGHT", 0, 0)
            if r.child then
                cell.text:SetText(FT.ItemText(r.id) .. FT.C("dim", " x" .. r.qty))
            else
                cell.text:SetText(FT.ItemText(r.id))
            end
            row.cells.price:SetText(FT.Money(r.price, "short"))
            row.cells.ch1:SetText(FT.Pct(r.ch1))
            local color = (r.ch7 and r.ch7 < 0) and "down" or ((r.ch7 and r.ch7 > 0) and "up" or "muted")
            row.cells.spark:SetValues(r.spark, color)
        end,
        isSelected = function(r) return r.id == state.selected end,
        onClick = function(r, button)
            if r.header then
                if button == "RightButton" and r.own then UI.WatchGroupMenu(r.group) return end
                state.closed = state.closed or {}
                state.closed[r.group] = not state.closed[r.group] or nil
                T.RefreshList(true)
                return
            end
            if UI.ItemClick(r.id) then return end
            if button == "RightButton" then
                -- the watchlist: a click right on it straight away (Settings), or its menu
                if FT.S.rightClickWatch then FT.Market.ToggleWatch(r.id) else UI.WatchMenu(r.id) end
                return
            end
            T.Select(r.id)
            if state.filter == "mine" and not r.child then ToggleOpen(r.id) end
        end,
        onEnter = function(row, r)
            if r.header then
                GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                GameTooltip:AddLine(r.group, 1, 0.82, 0)
                GameTooltip:AddLine(r.own and L["Your group. Click: fold it || Right-click: rename or remove it"]
                    or L["Grouped by kind. Click: fold it"], 0.52, 0.56, 0.61, true)
                GameTooltip:Show()
                return
            end
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            if GameTooltip.SetItemByID then GameTooltip:SetItemByID(r.id) end
            GameTooltip:AddLine(" ")
            if r.child then
                -- a material: how many one craft takes and where it is cheapest
                GameTooltip:AddLine(string.format(L["%s per craft of %s"], "x" .. r.qty, FT.ItemText(r.parent)), 0.85, 0.87, 0.9)
                if r.unit then
                    local tag = r.source and L[SOURCE_TAG[r.source] or r.source] or ""
                    GameTooltip:AddLine(FT.Money(r.unit) .. "  " .. FT.C("dim", tag) .. "  =  " .. FT.Money(r.unit * r.qty), 0.85, 0.87, 0.9)
                end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine((FT.S.rightClickWatch and L["Click: chart || Right-click: watchlist || Shift-click: link"] or L["Click: chart || Right-click: watchlist menu || Shift-click: link"]), 0.52, 0.56, 0.61)
            elseif state.filter == "mine" then
                GameTooltip:AddLine((FT.S.rightClickWatch and L["Click: chart and materials || Right-click: watchlist || Shift-click: link"] or L["Click: chart and materials || Right-click: watchlist menu || Shift-click: link"]), 0.52, 0.56, 0.61)
            else
                GameTooltip:AddLine((FT.S.rightClickWatch and L["Click: chart || Right-click: watchlist || Shift-click: link"] or L["Click: chart || Right-click: watchlist menu || Shift-click: link"]), 0.52, 0.56, 0.61)
            end
            GameTooltip:Show()
        end,
    })
    list:SetPoint("TOPLEFT", T.header, "BOTTOMLEFT", 0, -2)
    list:SetPoint("BOTTOMRIGHT", -1, 22)
    return panel
end

---------------------------------------------------------------------------
-- Overview (no item chosen)
---------------------------------------------------------------------------
-- one unit only: "12g", "35s", "80c" (a narrow column)
function T.ShortMoney(c)
    if not c then return "" end
    local G, S, C = FT.COIN and FT.COIN.gold or "g", FT.COIN and FT.COIN.silver or "s", FT.COIN and FT.COIN.copper or "c"
    if c >= 10000 then return FT.Thousands(math.floor(c / 10000 + 0.5)) .. G end
    if c >= 100 then return math.floor(c / 100 + 0.5) .. S end
    return math.floor(c) .. C
end

local function MoverList(parent, title)
    local box = UI.Panel(parent, "bg1", "line")
    box.title = UI.Text(box, 12, "text")
    box.title:SetPoint("TOPLEFT", 12, -10)
    box.title:SetText(title)
    local bump = (UI.Size(12) - 12) * 5
    local cols = {
        { key = "name", title = "", width = "fill", make = NameCell, cellHeight = 24 },
        { key = "spark", title = "", width = 40, justify = "RIGHT", make = SparkCell, cellHeight = 16 },
        { key = "price", title = "", width = 46 + bump, justify = "RIGHT" },
        { key = "ch", title = "", width = 46 + bump, justify = "RIGHT" },
    }
    box.list = UI.List(box, {
        rowHeight = 24, cols = cols,
        update = function(row, r)
            local cell = row.cells.name
            cell.icon:SetItem(r.id)
            cell.star:SetText("")
            cell.text:SetText(FT.ItemText(r.id) .. (r.pushed and FT.C("accent", "  " .. L["pushed up?"]) or ""))
            -- its last week, colored by the week's move (today's move is the number beside it)
            local wk = r.ch7 or r.ch1 or 0
            row.cells.spark:SetValues(r.spark, wk > 0 and "up" or (wk < 0 and "down" or "muted"))
            row.cells.price:SetText(T.ShortMoney(r.price))
            row.cells.ch:SetText(FT.C(r.ch1 >= 0 and "up" or "down", FT.An.Pc(r.ch1)))
        end,
        onClick = function(r) if not UI.ItemClick(r.id) then T.Select(r.id) end end,
        onEnter = function(row, r) UI.TipItem(row, r.id) end,
    })
    box.list:SetPoint("TOPLEFT", 1, -32)
    box.list:SetPoint("BOTTOMRIGHT", -1, 4)
    return box
end

-- Market Makers: the sellers with the most gold listed, from your last Full scan
function T.MakersList(parent)
    local box = UI.Panel(parent, "bg1", "line")
    box.title = UI.Text(box, 12, "text")
    box.title:SetPoint("TOPLEFT", 12, -10)
    box.title:SetText(L["Market Makers"])
    box.when = UI.Text(box, 10, "dim", "RIGHT")
    box.when:SetPoint("TOPRIGHT", -12, -11)
    local cols = {
        { key = "name", title = "", width = "fill" },
        { key = "value", title = "", width = 52 + (UI.Size(12) - 12) * 5, justify = "RIGHT" },
        { key = "items", title = "", width = 54 + (UI.Size(12) - 12) * 5, justify = "RIGHT" },
    }
    box.list = UI.List(box, {
        rowHeight = 24, cols = cols,
        update = function(row, x)
            row.cells.name:SetText(x.n .. (x.you and FT.C("dim", " " .. L["(you)"]) or ""))
            row.cells.value:SetText(T.ShortMoney(x.value))
            row.cells.items:SetText(FT.C("dim", string.format(L["%d items"], x.items)))
        end,
        onClick = function(x) if x.top then T.Select(x.top) end end,
        onEnter = function(row, x)
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:AddLine(x.n, 1, 1, 1)
            GameTooltip:AddLine(string.format(L["%s listed across %d items"], FT.Money(x.value), x.items), nil, nil, nil, true)
            if x.top then GameTooltip:AddLine(L["Biggest: "] .. FT.ItemText(x.top) .. "  " .. FT.C("dim", L["(click to open)"]), nil, nil, nil, true) end
            GameTooltip:Show()
        end,
    })
    box.list:SetPoint("TOPLEFT", 1, -32)
    box.list:SetPoint("BOTTOMRIGHT", -1, 4)
    box.list:SetEmptyText(L["Do a Full Scan in Auctionator: it names the sellers."])
    return box
end

local function BuildOverview(parent)
    local v = CreateFrame("Frame", nil, parent)
    v:SetAllPoints()
    v.title = UI.Text(v, 18, "text")
    v.title:SetPoint("TOPLEFT", 4, -6)
    v.title:SetText(L["Market overview"])
    v.hint = UI.Text(v, 11, "dim")
    v.hint:SetPoint("LEFT", v.title, "RIGHT", 12, -1)
    v.hint:SetPoint("RIGHT", v, "RIGHT", -4, 0)
    v.hint:SetText(L["Pick an item on the left to see its chart"])

    v.cards = {}
    local titles = { L["Items on the market"], L["Listed value"], L["Market mood"], L["Your portfolio"] }
    for i, t in ipairs(titles) do
        local c = UI.Stat(v, t)
        c:SetHeight(UI.RowH(70))
        v.cards[i] = c
    end
    v.moodBar = CreateFrame("Frame", nil, v.cards[3])
    v.moodBar:SetHeight(3)
    v.moodBar:SetPoint("BOTTOMLEFT", 10, 6)
    v.moodBar:SetPoint("BOTTOMRIGHT", -10, 6)
    UI.Fill(v.moodBar, "bg3", nil, "none")
    v.moodFill = UI.Tex(v.moodBar, "ARTWORK", "up", 1)
    v.moodFill:SetPoint("TOPLEFT")
    v.moodFill:SetPoint("BOTTOMLEFT")

    -- Today's 3 moves: the best carry, flip and farm right now, with the gold each should make
    v.movesTitle = UI.Text(v, 12, "text")
    v.movesTitle:SetText(L["Today's 3 moves"])
    -- what the wolf sees of you, on the title's line (FT.Eye)
    v.sees = UI.Text(v, 11, "muted", "RIGHT")
    if v.sees.SetWordWrap then v.sees:SetWordWrap(false) end
    v.moves = {}
    for i = 1, 3 do
        local c = CreateFrame("Button", nil, v)
        c:SetHeight(MOVE_H())
        UI.Fill(c, "bg1")
        UI.Border(c, "line")
        c.icon = UI.Icon(c, 30)
        c.icon:SetPoint("LEFT", 10, 0)
        c.gold = UI.Text(c, 12, "up", "RIGHT")
        c.gold:SetPoint("TOPRIGHT", -10, -9)
        -- the label stops short of the gold (a long one used to run into it)
        c.kind = UI.Text(c, 10, "accent")
        c.kind:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 8, 1)
        c.kind:SetPoint("RIGHT", c.gold, "LEFT", -6, 0)
        if c.kind.SetWordWrap then c.kind:SetWordWrap(false) end
        c.what = UI.Text(c, 11, "text")
        c.what:SetPoint("TOPLEFT", c.kind, "BOTTOMLEFT", 0, -3)
        c.what:SetPoint("RIGHT", c, "RIGHT", -10, 0)
        c.what:SetPoint("BOTTOM", c, "BOTTOM", 0, 5)
        c.what:SetJustifyV("TOP")
        if c.what.SetWordWrap then c.what:SetWordWrap(true) end
        if c.what.SetMaxLines then c.what:SetMaxLines(2) end
        c:SetScript("OnClick", function(self)
            if not self.itemID then return end
            -- a farm card: where to farm it; the others: the item
            if self.farm then FT.ShowFarm(self.itemID) else FT.OpenItem(self.itemID) end
        end)
        c:SetScript("OnEnter", function(self)
            if not self.itemID then return end
            UI.TipItem(self, self.itemID)
            if self.tip then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(self.tip, 0.85, 0.87, 0.9, true)
                GameTooltip:Show()
            end
        end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
        v.moves[i] = c
    end

    v.chartTitle = UI.Text(v, 12, "text")
    v.chartTitle:SetText(L["Value listed on the auction house, by scan"])
    v.chart = UI.Chart(v)
    local meme = FT.S.meme ~= false
    v.gainers = MoverList(v, meme and L["TO THE MOON (24h)"] or L["Top gainers 24h"])
    v.losers = MoverList(v, meme and L["RUG PULLS (24h)"] or L["Top losers 24h"])
    -- Market Makers (the sellers with the most gold listed): in the hover of the Listed value card
    v.cards[2]:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["Market Makers"], 1, 1, 1)
        local makers, t = FT.Whales.Makers()
        if #makers == 0 then
            GameTooltip:AddLine(L["The sellers with the most gold listed show here after a Full Scan in Auctionator (it names every seller)."], 0.6, 0.64, 0.7, true)
        else
            GameTooltip:AddLine(string.format(L["The sellers with the most gold listed (scan of %s)"], FT.Ago(t)), 0.6, 0.64, 0.7, true)
            for i = 1, math.min(8, #makers) do
                local x = makers[i]
                GameTooltip:AddDoubleLine(x.n .. (x.you and (" " .. L["(you)"]) or ""), FT.Money(x.value, "short") .. "  " .. string.format(L["%d items"], x.items), 0.85, 0.87, 0.9, 1, 1, 1)
            end
        end
        GameTooltip:Show()
    end)
    v.cards[2]:SetScript("OnLeave", function() GameTooltip:Hide() end)

    UI.OnSize(v, function(self, w, h)
        local cw = (w - 3 * 8) / 4
        for i, c in ipairs(self.cards) do
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", (i - 1) * (cw + 8), -34)
            c:SetWidth(cw)
        end
        self.movesTitle:ClearAllPoints()
        local movesY = 34 + UI.RowH(70) + 28
        self.movesTitle:SetPoint("TOPLEFT", 4, -(movesY - 18))
        self.sees:ClearAllPoints()
        self.sees:SetPoint("LEFT", self.movesTitle, "RIGHT", 16, 0)
        self.sees:SetPoint("RIGHT", self, "RIGHT", -4, 0)
        local mw = (w - 2 * 8) / 3
        for i, c in ipairs(self.moves) do
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", (i - 1) * (mw + 8), -movesY)
            c:SetWidth(mw)
        end
        -- (v0.43: Your top 3 is Today's; the market's home skips it and the chart takes the room)
        self.movesTitle:Hide()
        self.sees:Hide()
        for _, c in ipairs(self.moves) do c:Hide() end
        self.chartTitle:ClearAllPoints()
        local below = movesY - 18
        self.chartTitle:SetPoint("TOPLEFT", 4, -below)
        self.chart:ClearAllPoints()
        self.chart:SetPoint("TOPLEFT", 0, -below - 18)
        self.chart:SetPoint("TOPRIGHT", 0, -below - 18)
        local listsH = math.max(180, math.floor(h * 0.36))
        self.chart:SetPoint("BOTTOM", 0, listsH + 8)
        local half = (w - 8) / 2
        self.gainers:ClearAllPoints()
        self.gainers:SetPoint("BOTTOMLEFT", 0, 0)
        self.gainers:SetSize(half, listsH)
        self.losers:ClearAllPoints()
        self.losers:SetPoint("BOTTOMRIGHT", 0, 0)
        self.losers:SetSize(half, listsH)
    end)
    return v
end

function T.ShowOverview()
    if not overview then return end
    itemView:Hide()
    overview:Show()
    T.LayoutRight()
    local rows = FT.Market.Rows()
    overview.cards[1]:Set(rows and FT.Num(#rows) or "—", rows and L["seen in scans"] or L["no data"])
    local scans = FT.R().scans
    local lastScan = scans[#scans]
    if lastScan then
        local prev = scans[#scans - 1]
        local ch = prev and prev.value and prev.value > 0 and (lastScan.value / prev.value - 1) or nil
        overview.cards[2]:Set(FT.Money(lastScan.value, "short"), string.format(L["%s auctions"], FT.Num(lastScan.auctions))
            .. "  " .. FT.Pct(ch))
    else
        overview.cards[2]:Set("—", L["after a full scan"])
    end
    local mood, counted = FT.Market.Mood()
    local moodText, moodColor = FT.Market.MoodText(mood)
    overview.cards[3]:Set(mood and (FT.C(moodColor, mood) .. "  " .. FT.C(moodColor, moodText)) or "—",
        mood and string.format(L["%d%% of %s liquid items up (7d)"], mood, FT.Num(counted)) or L["needs a few days of prices"])
    if mood then
        overview.moodFill:Show()
        overview.moodFill:SetWidth(math.max(1, overview.moodBar:GetWidth() * mood / 100))
        UI.SetTexColor(overview.moodFill, moodColor, 1)
    else
        overview.moodFill:Hide()
    end
    local last = FT.Hist.LastScan()
    -- your portfolio today
    local prows, ptotal = FT.Port.Rows()
    local pvalue1 = 0
    for _, h in ipairs(prows or {}) do
        local r = FT.Market.Row(h.id)
        if r and r.ch1 and r.ch1 > -1 then pvalue1 = pvalue1 + h.value / (1 + r.ch1) else pvalue1 = pvalue1 + h.value end
    end
    local pch = pvalue1 > 0 and (ptotal / pvalue1 - 1) or nil
    overview.cards[4]:Set(FT.Money(math.floor((ptotal or 0) + FT.Port.Gold()), "short"),
        (pch and (FT.Pct(pch) .. FT.C("dim", " " .. L["today"])) or L["items and gold"]))
    local week = FT.An.WeekText and FT.An.WeekText()
    UI.FitBits(overview.hint, week and (FT.C("accent", L["This week"]) .. ":  " .. week) or L["Pick an item on the left to see its chart"])

    local points = {}
    for _, s in ipairs(scans) do
        if s.value and s.value > 0 then points[#points + 1] = { t = s.t, value = s.value } end
    end
    overview.chart:SetData({
        candles = UI.LineCandles(points), mode = "line", hourly = true, lineColor = "accent", tagColor = "accent",
        fmt = function(v) return FT.Thousands(v / 10000) .. FT.COIN.gold end,
        emptyTitle = L["No full scans yet"],
        emptyBody = L["Each full scan (yours or Auctionator's) adds a point: the total buyout of everything listed."],
    })
    overview.gainers.list:SetItems(FT.Market.Movers(20, "ch1", true))
    overview.losers.list:SetItems(FT.Market.Movers(20, "ch1", false))
end

-- Your top 3: the wolf's moves for you (what you hold, watch, can craft or gather - FT.Eye); short of three,
-- today's market moves fill in: the best carry and flip, the best thing to farm (else a craft or vendor deal)
-- (the old overview's moves: the same as Today's, FT.TopMoves - no more AH TO AH, Blackwater isn't followed)
function T.FillMoves()
    -- (v0.43: the market's home has no moves row - Today's Your top 3 is the one)
    if not overview or not overview.moves[1]:IsShown() then return end
    local cards, personal = FT.TopMoves()
    overview.movesTitle:SetText(personal and L["Your top 3"] or L["Today's 3 moves"])
    local okSees, sees = pcall(FT.Eye.ProfileText)
    UI.FitBits(overview.sees, okSees and sees or "")
    for i, c in ipairs(overview.moves) do
        local m = cards[i]
        c.itemID = m and m.id
        c.tip = m and m.tip
        c.icon:SetShown(m ~= nil)
        if m then c.icon:SetItem(m.id) end
        c.kind:SetText(m and FT.VerdictLabel(m.label or m.kind) or "")
        c.gold:SetText(m and m.gold or "")
        c.what:SetText(m and m.what or FT.C("dim", L["Nothing right now: new prices come every hour."]))
    end
end
FT.On("FT_DEALS_READY", function() if overview and overview:IsVisible() then T.FillMoves() end end) -- (never: no overview)
FT.On("FT_CRAFTS_READY", function() if overview and overview:IsVisible() then T.FillMoves() end end)

---------------------------------------------------------------------------
-- One item
---------------------------------------------------------------------------
local function StatPair(parent, label)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(100, 34)
    f.label = UI.Text(f, 10, "dim")
    f.label:SetPoint("TOPLEFT", 0, -2)
    f.label:SetText(label)
    f.value = UI.Text(f, 12, "text")
    f.value:SetPoint("TOPLEFT", 0, -17)
    return f
end

local function Card(parent, title)
    local c = UI.Panel(parent, "bg1", "line")
    c.title = UI.Text(c, 11, "muted")
    c.title:SetPoint("TOPLEFT", 10, -8)
    c.title:SetText(title)
    return c
end

---------------------------------------------------------------------------
-- The item page (v0.42): it reads top to bottom. The head (icon, name, price, its move), the verdict with its
-- reason (the call), Watch / Wowhead / Share; then the one clean chart (7D / 30D / 90D) and beside it the sections
-- that fit the item, sharing the column's height: When it sells, Market, Price history, then Best crafts (it's made
-- into things), Craft it (it's made) and Where to farm (it's gathered). One text size per section.
---------------------------------------------------------------------------
local function SEC_W() return (FT.Compact() and 270 or 310) + 14 * (tonumber(FT.S and FT.S.textSize) or 0) end
local SEC_TITLE = { when = L["When it sells"], market = L["Market"], history = L["Price history"], crafts = L["Best crafts"],
    make = L["Craft it"], farm = L["Where to get it"] }
-- the sections that are lists: every line one size
local LIST_SECTION = { crafts = true, make = true, farm = true }

local function SectionKeys(id)
    local keys = { "when", "market", "history" }
    if FT.Craft.UsedIn(id) then keys[#keys + 1] = "crafts" end
    -- a recipe of yours, else the game's (v0.43: the materials show for anything craftable, known or not)
    if UI.RecipeOf and UI.RecipeOf(id) then keys[#keys + 1] = "make" end
    -- where it comes from: anything farmed, and anything not crafted that has a source (a vendor, a drop, a quest)
    if FT.Farm.IsRaw(id) or (keys[#keys] ~= "make" and FT.Where and #FT.Where.Lines(id, 1) > 0) then keys[#keys + 1] = "farm" end
    return keys
end

local function Signed(c)
    if not c then return FT.C("dim", "—") end
    return c >= 0 and FT.C("up", "+" .. FT.Money(c, "short")) or FT.C("down", FT.Money(c, "short"))
end

-- a section's answer, its extra lines, and a button { label, fn }
local function SectionTexts(key, id, s)
    if key == "when" then
        local w = FT.WhenSummary and FT.WhenSummary(id)
        if not w then
            return FT.C("dim", L["Not enough sales seen yet"]), { L["The price robot needs 10 or more sold in four weeks."] },
                { L["Hour by hour"], function() FT.ShowWhenSells(id) end }
        end
        local sum
        if w.timed then
            sum = string.format(L["Sell %s · buy %s"], w.sell, w.buy)
        else
            sum = w.busy and string.format(L["Sells most %s"], w.busy) or L["Sells through the day"]
        end
        local more = {}
        if w.day then more[#more + 1] = string.format(L["Busiest day: %s"], w.day) end
        if w.timed and w.busy then more[#more + 1] = string.format(L["Sells most %s"], w.busy) end
        more[#more + 1] = L["Times on your clock."]
        return sum, more, { L["Hour by hour"], function() FT.ShowWhenSells(id) end }
    elseif key == "market" then
        local _, healthLabel, healthColor, healthWhy = FT.An.Health(s)
        local perDay = s.sales and s.sales.hours >= 12 and s.sales.perDay
        local sum = FT.C(healthColor, healthLabel)
        if perDay then sum = sum .. FT.C("text", "  ·  " .. string.format(L["sells ~%s a day"], perDay >= 10 and FT.Num(math.floor(perDay + 0.5)) or string.format("%.1f", perDay))) end
        local more = {}
        if s.listed then
            local line = string.format(L["%s listed"], FT.Num(s.listed))
            if perDay and perDay > 0 then
                local clear = s.listed / perDay
                line = line .. "  ·  " .. (clear < 1 and L["gone in a day"] or string.format(L["%s days to sell out"], FT.Num(math.floor(clear + 0.5))))
            end
            more[#more + 1] = line
        end
        -- (v0.50) the warnings first: a vendor sells it for less, the price looks propped up
        local floor, how = FT.VendorFloor(id, s.price)
        if floor then
            more[#more + 1] = FT.C("accent", string.format(L["A vendor sells it for %s: never pay over that"], FT.Money(floor, "short") .. (how == "estimate" and "~" or "")))
        end
        local propped = FT.An.Propped and FT.An.Propped(s)
        if propped then more[#more + 1] = FT.C("down", propped) end
        if s.fair then more[#more + 1] = string.format(L["Normal price %s"], FT.Money(s.fair, "short")) end
        local key2 = FT.An.Health(s)
        if (key2 == "pumped" or key2 == "dumping") and healthWhy and not propped then more[#more + 1] = healthWhy end
        if s.bait then more[#more + 1] = L["The cheapest one looks like bait: don't price off it."] end
        if FT.PvPTag and FT.PvPTag(id) then more[#more + 1] = FT.C("blue", FT.PvPTag(id)) end
        local sold = FT.Net and FT.Net.SoldText and FT.Net.SoldText(id)
        if sold then more[#more + 1] = sold end
        return sum, more, { L["Buy/sell"], function() FT.ShowCalc(id) end }
    elseif key == "history" then
        local bits = {}
        if s.ch7 then bits[#bits + 1] = L["7d"] .. " " .. FT.Pct(s.ch7) end
        if s.ch30 then bits[#bits + 1] = L["30d"] .. " " .. FT.Pct(s.ch30) end
        local word, wordColor = FT.An.TrendWord(s)
        local more = { FT.C(wordColor, word) .. (s.dev and FT.C("muted", "  ·  " .. L["vs usual"] .. " ") .. FT.Pct(s.dev) or "") }
        local b = s.behavior or {}
        local rec
        if (s.dev or 0) >= 0 and b.knowsHighs then rec = FT.An.HighRecord(b)
        elseif b.knowsLows then rec = FT.An.LowRecord(b)
        elseif b.knowsHighs then rec = FT.An.HighRecord(b) end
        if rec then more[#more + 1] = rec:sub(1, 1):upper() .. rec:sub(2) .. "." end
        return #bits > 0 and table.concat(bits, "  ·  ") or FT.C("dim", L["A few days of prices first"]), more
    elseif key == "crafts" then
        local uses, raw = FT.Craft.BestUse(id)
        local out = {}
        for _, x in ipairs(uses or {}) do
            if x.each then
                local gain = raw and (x.each - raw) or nil
                out[#out + 1] = FT.ItemText(x.recipe.output, 26) .. ": " .. FT.Money(math.floor(x.each), "short") .. FT.C("dim", " " .. L["a use"])
                    .. (gain and ("  " .. Signed(math.floor(gain))) or "")
            end
            if #out >= 4 then break end
        end
        if #out == 0 then
            return FT.C("dim", L["Nothing made from it has a price yet"]), {}, { L["All"], function() FT.ShowBestUse(id) end }
        end
        local first = table.remove(out, 1)
        return first, out, { L["All"], function() FT.ShowBestUse(id) end }
    elseif key == "make" then
        local rs = FT.Craft.ByOutput(id)
        local r = FT.Craft.Best and FT.Craft.Best(id) or (rs and rs[1])
        if r and r.recipe then r = r.recipe end
        r = r or (rs and rs[1])
        local known = r ~= nil
        if not r and UI.RecipeOf then r = UI.RecipeOf(id); known = r ~= nil and next(r.knownBy or {}) ~= nil end
        local e = r and FT.Craft.Eval(r)
        if not e then return FT.C("dim", L["No price for its materials yet"]), {} end
        local sum
        if e.complete and e.revenue then
            sum = string.format(L["Costs ~%s, sells %s"], FT.Money(math.floor(e.cost), "short"), FT.Money(math.floor(e.revenue), "short")) .. "  " .. Signed(math.floor(e.profit or 0))
        else
            sum = FT.C("dim", e.reason or L["No price for its materials yet"])
        end
        local more = {}
        -- a timer bites where it is: on the craft itself, or on a material it needs (Cured Rugged Hide: the salt)
        local days, how = FT.Craft.TimerOf(id)
        local function Every(n) return n == 1 and L["once a day"] or string.format(L["every %d days"], n) end
        if days then more[#more + 1] = FT.C("accent", L["Timer"] .. ": " .. Every(days)) .. FT.C("dim", how and ("  ·  " .. L[how]) or "") end
        for _, part in ipairs(e.parts or {}) do
            local pd, ph = FT.Craft.TimerOf(part.itemID)
            if pd and #more < 4 then
                more[#more + 1] = FT.C("accent", string.format(L["needs %s"], FT.ItemText(part.itemID, 22)) .. ": " .. Every(pd)) .. FT.C("dim", ph and ("  ·  " .. L[ph]) or "")
            end
        end
        for _, part in ipairs(e.parts or {}) do
            more[#more + 1] = part.qty .. " " .. FT.ItemText(part.itemID, 24) .. FT.C("dim", "  " .. (part.total and FT.Money(math.floor(part.total), "short") or "—"))
            if #more >= 5 then break end
        end
        if not known then more[#more + 1] = FT.C("dim", L["None of your characters knows it  ·  Breakdown: where the recipe is"]) end
        return sum, more, { L["Breakdown"], function() FT.ShowCraft(r) end }
    else -- farm: where it comes from
        local spots = FT.Farm.Spots(id)
        local out = {}
        for _, sp in ipairs(spots or {}) do
            -- (parts apart with " · ": a line too long for the section drops its last part, never cut mid-word)
            out[#out + 1] = FT.C("text", sp.zone) .. FT.C("dim", string.format("  ·  %d-%d", sp.lo, sp.hi) .. (sp.what and ("  ·  " .. sp.what) or ""))
            if #out >= 2 then break end
        end
        -- your loot, Wolf users' loot, Wolf's note, then ForeverDB: nodes, skinning, drops, vendors, quests
        for _, line in ipairs(FT.Where and FT.Where.Lines(id, 6) or {}) do
            if #out >= 6 then break end
            out[#out + 1] = line
        end
        local button = FT.Farm.IsRaw(id) and { L["Open"], function() FT.ShowFarm(id) end } or nil
        if #out == 0 then return FT.C("dim", L["Not in Wolf's sources yet: the loot log fills it in when a Wolf user loots one."]), {}, button end
        local first = table.remove(out, 1)
        return first, out, button
    end
end

local function BuildSections(parent)
    local box = UI.Panel(parent, "bg1", "line")
    box.secs = {}
    for i = 1, 6 do
        local f = CreateFrame("Frame", nil, box)
        f.title = UI.Text(f, 12, "muted")
        f.title:SetPoint("TOPLEFT", 12, -9)
        f.sum = UI.Text(f, 13, "text")
        f.sum:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -5)
        f.sum:SetPoint("RIGHT", -12, 0)
        f.more = {}
        for k = 1, 4 do
            local t = UI.Text(f, 11, "muted")
            t:SetPoint("TOPLEFT", f.sum, "BOTTOMLEFT", 0, -5 - (k - 1) * UI.RowH(16))
            t:SetPoint("RIGHT", -12, 0)
            f.more[k] = t
        end
        f.btn = UI.Button(f, "", 10, 18, "default", function(self) if self.fn then self.fn() end end)
        f.btn:SetPoint("TOPRIGHT", -8, -5)
        f.title:SetPoint("RIGHT", f.btn, "LEFT", -8, 0)
        f.line = UI.HLine(f, "line", 0.5)
        f.line:SetPoint("BOTTOMLEFT", 8, 0)
        f.line:SetPoint("BOTTOMRIGHT", -8, 0)
        box.secs[i] = f
    end
    function box:Lay(id, s)
        if not id then return end
        local keys = SectionKeys(id)
        local n = #keys
        local H = (self:GetHeight() or 400) - 8
        local each = math.floor(H / math.max(1, n))
        for i, f in ipairs(self.secs) do
            local key = keys[i]
            f:SetShown(key ~= nil)
            if key then
                local ok, sum, more, btn = pcall(SectionTexts, key, id, s)
                if not ok then sum, more, btn = FT.C("dim", "—"), {}, nil end
                f.title:SetText(SEC_TITLE[key])
                f.btn:SetShown(btn ~= nil)
                if btn then f.btn:SetLabel(btn[1]); f.btn.fn = btn[2]; f.btn:FitText(16) end
                -- as many extra lines as its share of the height holds
                local room = math.max(0, math.floor((each - UI.RowH(44)) / UI.RowH(16)))
                local shown = {}
                -- (a line fitted before remembers its text and fits it again on a resize: not an old item's)
                f.sum.fitText = nil
                for k, t in ipairs(f.more) do
                    t.fitText = nil
                    local line = (k <= room) and more and more[k] or nil
                    t:SetShown(line ~= nil)
                    if line then t:SetText(line); shown[#shown + 1] = t end
                end
                f.sum:SetText(sum or "")
                -- one size per section: a list has every line the same size; whatever must shrink to fit shrinks
                -- the whole section by the same step
                local list = LIST_SECTION[key]
                local sumSize, moreSize = list and 12 or 13, list and 12 or 11
                local fits
                for k = 0, 3 do
                    f.sum:SetFont(UI.FONT, UI.Size(sumSize) - k, "")
                    fits = (f.sum:GetStringWidth() or 0) <= (f.sum:GetWidth() or 0) + 0.5
                    for _, t in ipairs(shown) do
                        t:SetFont(UI.FONT, UI.Size(moreSize) - k, "")
                        if (t:GetStringWidth() or 0) > (t:GetWidth() or 0) + 0.5 then fits = false end
                    end
                    if fits then break end
                end
                -- still too long at the smallest step: the long lines drop their last parts (after " · ")
                if not fits then
                    UI.FitBits(f.sum, f.sum:GetText() or "")
                    for _, t in ipairs(shown) do UI.FitBits(t, t:GetText() or "") end
                end
                f.line:SetShown(i < n)
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", 4, -4 - (i - 1) * each)
                f:SetPoint("RIGHT", -4, 0)
                f:SetHeight(each)
            end
        end
    end
    box:HookScript("OnSizeChanged", function(self) if state.selected then self:Lay(state.selected, FT.An.Stats(state.selected)) end end)
    return box
end

local function BuildItemView(parent)
    local v = CreateFrame("Frame", nil, parent)
    v:SetAllPoints()

    -- head: back to the market's home, icon, name, the line under it; price, its move, how old
    v.back = UI.Button(v, "< " .. L["Market"], 10, 22, "default", function() T.Home() end)
    v.back:FitText(18)
    v.back:SetPoint("TOPLEFT", 0, -12)
    v.back:SetTip(L["Market"], L["Back to the market's home: its mood, the value listed, the week, what's moving."])
    v.icon = UI.Icon(v, 38)
    v.icon:SetPoint("TOPLEFT", v.back, "TOPRIGHT", 10, 8)
    v.icon:EnableMouse(true)
    v.icon:SetScript("OnEnter", function(self) UI.TipItem(self, state.selected) end)
    v.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    v.name = UI.Text(v, 16, "text")
    v.name:SetPoint("TOPLEFT", v.icon, "TOPRIGHT", 10, -1)
    v.sub = UI.Text(v, 11, "dim")
    v.sub:SetPoint("TOPLEFT", v.name, "BOTTOMLEFT", 0, -5)
    v.change = UI.Text(v, 14, "text", "RIGHT")
    v.change:SetPoint("TOPRIGHT", -2, -6)
    v.price = UI.Text(v, 22, "text", "RIGHT")
    v.price:SetPoint("RIGHT", v.change, "LEFT", -12, -1)
    v.priceAge = UI.Text(v, 10, "dim", "RIGHT")
    v.priceAge:SetPoint("TOPRIGHT", -2, -32)
    v.ring = UI.LiveRingFor(v, 9, function() return state.selected end)
    v.ring:SetPoint("RIGHT", v.priceAge, "LEFT", -5, 0)

    -- the verdict first, then Watch / Wowhead / Share
    v.share = UI.Button(v, L["Share"], 10, 24, "default", function() if state.selected then FT.ShareTip(state.selected) end end)
    v.share:FitText(22)
    v.share:SetPoint("TOPRIGHT", 0, -52)
    v.share:SetTip(L["Share"], L["A line about this item for guild chat: its price today against usual. You send it yourself (Enter)."])
    v.wowhead = UI.Button(v, L["Wowhead"], 10, 24, "default", function() if state.selected then FT.Farm.Wowhead(state.selected) end end)
    v.wowhead:FitText(22)
    v.wowhead:SetPoint("RIGHT", v.share, "LEFT", -6, 0)
    v.wowhead:SetTip(L["Wowhead"], L["Its page on Wowhead (WoW Forever): a link to copy into your browser."])
    v.watch = UI.Button(v, L["Watch"], 10, 24, "default", function(self) if state.selected then UI.WatchMenu(state.selected, self) end end)
    v.watch:SetPoint("RIGHT", v.wowhead, "LEFT", -6, 0)

    v.call = UI.Panel(v, "bg2", "accent")
    v.call:SetPoint("TOPLEFT", 0, -48)
    v.call:SetPoint("RIGHT", v.watch, "LEFT", -10, 0)
    v.call:SetHeight(UI.RowH(34))
    v.call:EnableMouse(true)
    v.callBadge = UI.Badge(v.call, 84, 22)
    v.callBadge:SetPoint("LEFT", 10, 0)
    v.callSure = UI.Text(v.call, 11, "dim", "RIGHT")
    v.callSure:SetPoint("RIGHT", -10, 0)
    v.callText = UI.Text(v.call, 13, "text")
    v.callText:SetPoint("LEFT", v.callBadge, "RIGHT", 12, 0)
    v.callText:SetPoint("RIGHT", v.callSure, "LEFT", -10, 0)
    if v.callText.SetWordWrap then v.callText:SetWordWrap(true) end
    if v.callText.SetMaxLines then v.callText:SetMaxLines(2) end
    v.call:SetScript("OnEnter", function(self)
        if not v.callWhy then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["The call"], 1, 1, 1)
        GameTooltip:AddLine(v.callWhy, 0.85, 0.87, 0.9, true)
        if v.callOther then GameTooltip:AddLine(v.callOther, 0.6, 0.64, 0.7, true) end
        GameTooltip:AddLine(L["Sure: this item did it before. Likely: items like it did. Guess: little to go by yet."], 0.6, 0.64, 0.7, true)
        GameTooltip:Show()
    end)
    v.call:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- the sections on the right, the chart on the left
    v.secs = BuildSections(v)
    -- below the verdict (it can take two lines), level with the chart's range buttons
    v.secs:SetPoint("TOPRIGHT", v, "TOPRIGHT", 0, -(48 + UI.RowH(34) + 10))
    v.secs:SetPoint("BOTTOMRIGHT", 0, 0)
    v.secs:SetWidth(SEC_W())
    v.range = UI.Segmented(v, UI.RANGES, function(r)
        FT.S.chartRange = r
        T.DrawChart()
    end, 20)
    v.range:SetPoint("TOPLEFT", v.call, "BOTTOMLEFT", 0, -10)
    v.chart = UI.Chart(v)
    v.chart:SetPoint("TOPLEFT", v.range, "BOTTOMLEFT", 0, -6)
    v.chart:SetPoint("BOTTOMRIGHT", v.secs, "BOTTOMLEFT", -10, 0)
    UI.Border(v.chart, "line")
    -- (kept for the code that asks after them: there is no second chart, no Pro chart, no stats strip any more)
    v.pchart = CreateFrame("Frame", nil, v)
    v.pchart:Hide()
    return v
end

-- the name and the line under it stop before the price, its change and its age (cut with "...")
function T.FitHeader()
    local v = itemView
    local w = v and v:GetWidth()
    if not w or w <= 0 then return end
    local left = (v.back:GetWidth() or 0) + 10 + 38 + 10
    local top = 2 + v.change:GetStringWidth() + 12 + v.price:GetStringWidth() + 14
    local bottom = 2 + v.priceAge:GetStringWidth() + 5 + 9 + 14
    v.name:SetWidth(math.max(60, w - left - top))
    v.sub:SetWidth(math.max(60, w - left - bottom))
end

function T.FitBestUse() end

function T.UpdateWatchButton()
    local v = itemView
    if not (v and state.selected) then return end
    local on = FT.Market.IsWatched(state.selected)
    local hold = FT.db.longHold and FT.db.longHold[state.selected]
    v.watch:SetLabel((on and L["In watchlist"] or L["Watch"]) .. (hold and FT.C("accent", " *") or ""))
    v.watch:SetActive(on)
    v.watch:FitText(20)
end

function T.ApplyChartStyle()
    local v = itemView
    if not v then return end
    v.range:SetValue(FT.S.chartRange or "30D")
end

function T.DrawChart(keepView)
    local v = itemView
    local id = state.selected
    if not (v and id) then return end
    v.range:SetValue(FT.S.chartRange or "30D")
    v.chart:SetData(UI.PriceChartData(id, FT.S.chartTF, false), keepView)
end

function T.ShowItem(id, keepView)
    if not itemView then return end
    overview:Hide()
    itemView:Show()
    local v = itemView
    local _, _, icon = FT.Item(id)
    v.icon:SetIcon(icon)
    v.name:SetText(FT.ItemText(id, 40))
    local cls, sub = FT.ItemClass(id)
    local parts = {}
    if cls then
        parts[#parts + 1] = ClassName(cls)
        local subName = GetSubClassInfo and sub and GetSubClassInfo(cls, sub)
        if subName and subName ~= "" and subName ~= parts[1] then parts[#parts + 1] = subName end
    end
    local own = FT.Port.Count(id)
    if own > 0 then parts[#parts + 1] = FT.C("text", string.format(L["you have %s"], FT.Num(own))) end
    local s = FT.An.Stats(id)
    local head = UI.RiskHead(s)
    for i = #head, 1, -1 do table.insert(parts, 1, head[i]) end
    UI.FitBits(v.sub, table.concat(parts, FT.C("dim", "  ||  ")))
    v.price:SetText(s.price and FT.Money(s.price, "short") or "—")
    v.change:SetText(FT.Pct(s.ch1) .. FT.C("dim", " " .. L["24h"]))
    v.priceAge:SetText(UI.PriceAgeText(id, s))

    -- the call: for you - selling if you have it, else buying - with how sure it is and its record
    local call = FT.An.Call(s, own)
    v.callBadge:Set(call.kind, nil, call.strength)
    local sure = call.conf and FT.An.ConfText(call.conf) or ""
    if call.record then sure = sure .. (sure ~= "" and ", " or "") .. call.record end
    v.callSure:SetText(sure)
    v.callText:SetText(call.text or "")
    -- a long reason takes a second line: the panel grows, the chart and the sections move down
    local two = (v.callText:GetStringWidth() or 0) > ((v.callText:GetWidth() or 400) + 0.5)
    v.call:SetHeight(UI.RowH(two and 46 or 34))
    v.secs:SetPoint("TOPRIGHT", v, "TOPRIGHT", 0, -(48 + UI.RowH(two and 46 or 34) + 10))
    v.callWhy = call.detail
    v.callOther = call.other

    T.ApplyChartStyle()
    T.DrawChart(keepView)
    v.secs:SetWidth(SEC_W())
    v.secs:Lay(id, s)
    T.UpdateWatchButton()
    T.LayoutRight()
    T.FitHeader()
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
function T.Build(p)
    page = p
    BuildList(p)
    center = CreateFrame("Frame", nil, p)
    overview = BuildOverview(center)
    overview:Hide()
    itemView = BuildItemView(center)
    itemView:Hide()
    -- (the craft breakdown is the Craft it section now; the old panel stays built, out of sight)
    mats = UI.Materials(p, function(id) T.Select(id) end)
    mats:Hide()
    T.OnLayout()
end

function T.LayoutRight()
    if not center then return end
    center:ClearAllPoints()
    center:SetPoint("TOPLEFT", LEFT_W + 18, -8)
    center:SetPoint("BOTTOMRIGHT", -8, 8)
    if mats then mats:Hide() end
end

function T.SizeCharts() end

function T.OnLayout()
    if not page then return end
    itemView.compact = FT.Compact()
    if itemView.secs then itemView.secs:SetWidth(SEC_W()) end
    T.LayoutRight()
end

-- the list scrolled to the item you have open
function T.ShowSelectedInList()
    if not (list and state.selected) then return end
    for i, x in ipairs(list.items) do
        if x.id == state.selected and not x.child then
            list:ScrollTo(i)
            return
        end
    end
end

---------------------------------------------------------------------------
-- The filters panel (the button next to the search box)
---------------------------------------------------------------------------
local function FiltersChanged()
    if T.filterBtn then T.filterBtn:SetActive(FiltersOn()) end
    FT.Debounce("marketFilters", 0.2, function()
        T.RefreshList()
        if FiltersOn() then T.LoadMissingNames() end
    end)
end

local function QualityName(q)
    local name = _G["ITEM_QUALITY" .. q .. "_DESC"]
    return "|c" .. FT.QualityHex(q) .. (name or tostring(q)) .. "|r"
end

local function BuildFilters()
    local p = CreateFrame("Frame", nil, UIParent)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:SetFrameLevel(60)
    p:SetClampedToScreen(true)
    p:EnableMouse(true)
    p:SetWidth(220)
    UI.Skin(p, "popup", "bg1")
    -- a click anywhere else closes it
    local blocker = CreateFrame("Button", nil, UIParent)
    blocker:SetAllPoints(UIParent)
    blocker:SetFrameStrata("FULLSCREEN_DIALOG")
    blocker:SetFrameLevel(50)
    blocker:SetScript("OnClick", function() p:Hide() end)
    blocker:Hide()
    p:SetScript("OnShow", function() blocker:Show() end)
    p:SetScript("OnHide", function() blocker:Hide() end)

    local y = -12
    local function Title(text)
        local t = UI.Text(p, 12, "accent")
        t:SetPoint("TOPLEFT", 14, y)
        t:SetText(text)
        y = y - 22
    end

    Title(L["Levels"])
    local function LevelBox(onSet)
        local e = UI.Input(p, 48, 22, "", function(text)
            onSet(tonumber(text))
            FiltersChanged()
        end)
        e:SetNumeric(true)
        e:SetMaxLetters(3)
        e:SetJustifyH("CENTER")
        return e
    end
    p.min = LevelBox(function(v) filt.min = v end)
    p.min:SetPoint("TOPLEFT", 14, y)
    local dash = UI.Text(p, 12, "muted")
    dash:SetPoint("LEFT", p.min, "RIGHT", 6, 0)
    dash:SetText("-")
    p.max = LevelBox(function(v) filt.max = v end)
    p.max:SetPoint("LEFT", dash, "RIGHT", 6, 0)
    y = y - 34

    p.usable = UI.Check(p, L["Usable only"], function(on)
        filt.usable = on
        FiltersChanged()
    end)
    p.usable:SetPoint("TOPLEFT", 14, y)
    y = y - 24
    if CanCollect() then
        p.uncollected = UI.Check(p, L["Not collected only"], function(on)
            filt.uncollected = on
            FiltersChanged()
        end)
        p.uncollected:SetPoint("TOPLEFT", 14, y)
        y = y - 24
    end
    y = y - 6

    Title(L["Quality"])
    p.quality = {}
    for _, q in ipairs(QUALITIES) do
        local c = UI.Check(p, QualityName(q), function(on)
            filt.quality[q] = on
            FiltersChanged()
        end)
        c:SetPoint("TOPLEFT", 14, y)
        p.quality[q] = c
        y = y - 22
    end
    y = y - 8

    -- what kind: the category, then its subcategory (armor: cloth, leather...; trade goods: cloth, metal...)
    Title(L["Category"])
    local clsOptions = { { "all", L["All categories"] } }
    for _, c in ipairs(CLASSES) do clsOptions[#clsOptions + 1] = { c, ClassName(c) } end
    clsOptions[#clsOptions + 1] = { "other", L["Other"] }
    local cls = UI.Dropdown(p, 192, clsOptions, function(v)
        state.cls, state.sub = v, "all"
        T.RefreshList()
    end)
    cls:SetHeight(22)
    cls:SetPoint("TOPLEFT", 14, y)
    cls:SetValue(state.cls)
    T.clsDD = cls
    y = y - 28
    local subDD = UI.Dropdown(p, 192, { { "all", L["All subcategories"] } }, function(v)
        state.sub = v
        T.RefreshList()
    end)
    subDD:SetHeight(22)
    subDD:SetPoint("TOPLEFT", 14, y)
    subDD:SetValue(state.sub)
    T.subDD = subDD
    y = y - 34

    -- the order (clicking a column title in the list sorts too)
    Title(L["Sort"])
    local sortOptions = {
        { "cap", L["Market value"] }, { "ch1", L["24h change"] }, { "ch7", L["7d change"] },
        { "price", L["Price"] }, { "qty", L["Listed"] }, { "name", L["Name"] },
    }
    local sortDD = UI.Dropdown(p, 192, sortOptions, function(v)
        state.sort = v
        state.desc = v ~= "name"
        T.header:SetSort(v, state.desc)
        T.RefreshList()
    end)
    sortDD:SetHeight(22)
    sortDD:SetPoint("TOPLEFT", 14, y)
    sortDD:SetValue(state.sort)
    T.sortDD = sortDD
    y = y - 34

    p.reset = UI.Button(p, L["Reset"], 10, 22, "default", function()
        T.ResetFilters()
        state.cls, state.sub = "all", "all"
        T.clsDD:SetValue("all")
        T.SyncFilters()
        T.RefreshList()
    end)
    p.reset:FitText(24)
    p.reset:SetPoint("TOPLEFT", 14, y)
    y = y - 22 - 12
    p:SetHeight(-y)
    p:Hide()
    T.filterPanel = p
    return p
end

-- the panel shows what is set
function T.SyncFilters()
    local p = T.filterPanel
    if not p then return end
    p.min:SetValue(filt.min and tostring(filt.min) or "")
    p.max:SetValue(filt.max and tostring(filt.max) or "")
    p.usable:SetChecked(filt.usable)
    if p.uncollected then p.uncollected:SetChecked(filt.uncollected) end
    for q, c in pairs(p.quality) do c:SetChecked(filt.quality[q]) end
    if T.clsDD then T.clsDD:SetValue(state.cls) end
    if T.sortDD then T.sortDD:SetValue(state.sort) end
end

function T.ResetFilters()
    filt.min, filt.max, filt.usable, filt.uncollected = nil, nil, false, false
    for _, q in ipairs(QUALITIES) do filt.quality[q] = true end
    FiltersChanged()
end

function T.ToggleFilters(button)
    local p = T.filterPanel or BuildFilters()
    if p:IsShown() then
        p:Hide()
        return
    end
    p:SetScale(button:GetEffectiveScale() / UIParent:GetEffectiveScale())
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
    T.SyncFilters()
    p:Show()
end

-- An item opened from elsewhere (Craft, Signals, Portfolio, the ticker, the item window): the list shows just
-- it - its exact name in quotes in the search box, the filters back to all. × brings the whole list back.
-- (Picking an item in the list itself leaves the list as it is.)
function T.Focus(id)
    if not id then return end
    if not page then FT.Show("market") end
    state.filter, state.cls, state.sub = "all", "all", "all"
    if FiltersOn() then
        T.ResetFilters()
        T.SyncFilters()
    end
    if T.chips then
        for _, c in ipairs(T.chips) do c:SetOn(c.key == "all") end
    end
    if T.clsDD then T.clsDD:SetValue("all") end
    local name = FT.Name(id) or FT.Item(id)
    -- no name yet: the search box gets it when it arrives
    state.focusFor = not name and id or nil
    state.search = name and ('"' .. name .. '"') or ""
    state.only, state.onlySearch = name and id or nil, state.search
    if T.searchBox then T.searchBox:SetValue(state.search) end
    T.RefreshList()
    T.Select(id)
end

-- typing began in the search box at the top of the window (another page): the list searches it, from all items,
-- and the typing goes on in Market's own box
function T.TypeIn(text)
    state.filter, state.cls, state.sub = "all", "all", "all"
    if FiltersOn() then
        T.ResetFilters()
        T.SyncFilters()
    end
    if T.chips then
        for _, c in ipairs(T.chips) do c:SetOn(c.key == "all") end
    end
    if T.clsDD then T.clsDD:SetValue("all") end
    state.search, state.focusFor, state.only = text or "", nil, nil
    if T.searchBox then
        T.searchBox:SetValue(state.search)
        T.searchBox:SetFocus()
        if T.searchBox.SetCursorPosition then T.searchBox:SetCursorPosition(#state.search) end
    end
    T.RefreshList()
    if state.search ~= "" then T.LoadMissingNames() end
end

function T.Select(id)
    if not id then return end
    if not page then FT.Show("market") end
    state.selected, state.home = id, false
    FT.db.ui = FT.db.ui or {}
    FT.db.ui.lastItem = id
    FT.Hist.Viewed(id)
    if list then list:Refresh() end
    T.ShowItem(id)
    FT.Scanner.LiveNow(id)
end

-- the item kept live at the auction house: the one open here
function T.LiveItem()
    return itemView and itemView:IsVisible() and state.selected or nil
end

-- and the materials of one craft of it (when they show): its cost and profit follow the market too
function T.LiveItems()
    local id = T.LiveItem()
    if not id then return nil end
    local out = { id }
    if mats and mats:IsVisible() and mats.r then
        for _, m in ipairs(FT.Craft.MarketMaterials(mats.r)) do out[#out + 1] = m end
    end
    return out
end

-- a live price came in (id), or the auction house opened or closed (nil)
function T.OnLive(_, id)
    if list then list:Refresh() end
    local ours = id == nil or id == state.selected or (mats and mats:IsShown() and mats:Has(id))
    if state.selected and itemView and itemView:IsShown() and ours then
        T.ShowItem(state.selected, true)
    end
end

function T.OnShow()
    FT.Market.EnsureFresh()
    -- an item about to open: it draws the list once itself (not twice)
    if T.opening then return end
    T.Refresh()
end

function T.Refresh()
    T.RefreshList(true)
    T.RefreshRight()
end

function T.RefreshRight()
    if state.home and not state.selected then return T.ShowOverview() end
    if not state.selected then
        -- v0.42: no overview (Today has it): the item you opened last, else the first in the list
        local last = FT.db.ui and FT.db.ui.lastItem
        local first = list and list.items and list.items[1]
        state.selected = (last and FT.Market.Row and FT.Market.Row(last) and last) or (first and first.id) or last
        if list then list:Refresh() end
    end
    if state.selected then
        T.ShowItem(state.selected, true)
    else
        T.ShowOverview()
    end
end

-- new data while you look (not a click): the list this frame, the overview or the item the next - two short
-- frames, not one long one
function T.RefreshSoft()
    T.RefreshList(true)
    C_Timer.After(0, function() if page and page:IsVisible() then T.RefreshRight() end end)
end

-- Escape-like: back to the overview
-- the item open (nil: the overview)
function T.Selected()
    return state.selected
end

-- (for the tests) the market's home and the item page
function T.Views() return overview, itemView end

function T.ClearSelection()
    T.Home()
end

-- back to the market's home: the overview (mood, listed value, the week, what's moving)
function T.Home()
    state.selected, state.home = nil, true
    if list then list:Refresh() end
    if page and page:IsVisible() then T.ShowOverview() end
end

-- the watchlist changed (a menu, another page): the Watch button and the list follow
FT.On("FT_WATCH_CHANGED", function()
    if not FT.IsShown() then return end
    T.UpdateWatchButton()
    T.RefreshList(true)
end)
