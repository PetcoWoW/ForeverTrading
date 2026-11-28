-- Wolf: Calculator (v0.51), its own page next to You. An item or none, how many, buying or selling, a price each:
-- the sum as you type (buying an item walks up its listings; selling takes home what's left after the auction
-- house's real cut). Beside it the cheat sheet: your last sums, kept between sessions, with their running totals -
-- for big buys and keeping track without alt-tabbing. Click a line to load it again; Wipe clears it.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local T = {}
FT.Tabs.calc = T

local state = { mode = "buy", id = nil }
local built, p0
local SHEET_MAX = 60

local function Sheet()
    FT.db.calcSheet = FT.db.calcSheet or {}
    return FT.db.calcSheet
end

-- the item a name points at: its exact name, else the busiest item on the market whose name has every word
local function FindItem(text)
    local q = FT.Fold(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if q == "" then return nil end
    local idx = FT.NameIndex()
    for name, id in pairs(idx) do
        if FT.Fold(name) == q then return id end
    end
    local match = FT.NameMatcher(text)
    if not match then return nil end
    local best, bestV
    for _, r in ipairs(FT.Market.Rows() or {}) do
        if r.id and match(r.id) then
            local v = (r.qty or 0) + 1
            if not best or v > bestV then best, bestV = r.id, v end
        end
    end
    return best
end
T.FindItem = FindItem

-- (v0.54) what the item box suggests as you type: up to 8 items on the market with every word of it in their name,
-- those whose name starts with it first, then the busiest
-- (v0.61) every market item's folded name, kept per market build (folding 7,000 names a keystroke was ~50 ms)
local names, namesFor = nil, nil
local function Names()
    local rows = FT.Market.Rows() or {}
    if namesFor ~= rows or not names then
        names, namesFor = {}, rows
        for _, r in ipairs(rows) do
            local n = r.id and FT.Name(r.id)
            if n then names[#names + 1] = { id = r.id, name = FT.Fold(n), v = r.qty or 0 } end
        end
    end
    return names
end

-- built in the background a few hundred names a frame after new prices, so a keystroke never waits for it
local function Warm()
    local rows = FT.Market.Rows() or {}
    local fresh = {}
    FT.Job("searchNames", #rows, function(k)
        local r = rows[k]
        local n = r and r.id and FT.Name(r.id)
        if n then fresh[#fresh + 1] = { id = r.id, name = FT.Fold(n), v = r.qty or 0 } end
    end, function() names, namesFor = fresh, rows end)
end
FT.On("FT_MARKET_READY", function() FT.Debounce("searchNames", 3, Warm) end)
FT.On("FT_ITEMS_LOADED", function() FT.Debounce("searchNames", 3, Warm) end)

local function Suggest(text)
    local q = FT.Fold(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if #q < 2 then return {} end
    local words = {}
    for w in q:gsub('"', ""):gmatch("%S+") do words[#words + 1] = w end
    if #words == 0 then return {} end
    -- the best 8 kept while looking (those starting with it first, then the busiest): no sort of every match
    local best = {}
    local function Better(a, b)
        if a.starts ~= b.starts then return a.starts end
        if a.v ~= b.v then return a.v > b.v end
        return a.name < b.name
    end
    local w1, nw = words[1], #words
    for _, x in ipairs(Names()) do
        local name = x.name
        if name:find(w1, 1, true) then
            local ok = true
            for k = 2, nw do if not name:find(words[k], 1, true) then ok = false break end end
            if ok then
                local starts = name:find(q, 1, true) == 1
                local last = best[8]
                -- (a table only for one that gets in)
                if not last or (starts and not last.starts) or (starts == last.starts and (x.v > last.v or (x.v == last.v and name < last.name))) then
                    local c = { id = x.id, starts = starts, v = x.v, name = name }
                    local i = math.min(#best + 1, 8)
                    while i > 1 and Better(c, best[i - 1]) do best[i] = best[i - 1]; i = i - 1 end
                    best[i] = c
                end
            end
        end
    end
    local out = {}
    for i = 1, math.min(8, #best) do out[i] = best[i].id end
    return out
end
T.Suggest = Suggest

-- the sum now: { lines, total, take, unit, qty } (take: what selling brings home)
function T.Sum()
    local qty = math.max(1, math.floor(tonumber(T.qty:GetText()) or 1))
    local each = FT.Calc.ParseMoney(T.each:GetText())
    local id = state.id
    local out = { qty = qty, id = id, mode = state.mode }
    if state.mode == "sell" then
        if id then
            local x = FT.Calc.Sell(id, qty, each, 24)
            out.lines = FT.Calc.SellLines(x)
            if x then out.total, out.take, out.unit = x.gross, x.take, x.unit end
        elseif each then
            local gross = each * qty
            local cut = math.floor(gross * FT.Cut() + 0.5)
            out.total, out.take, out.unit = gross, gross - cut, each
            out.lines = { string.format(L["You take home %s"], FT.C("up", FT.Money(gross - cut))) .. FT.C("dim", "  ·  " .. string.format(L["%s at %s each"], FT.Num(qty), FT.Money(each, "short"))),
                string.format(L["The cut: %s (%s%%)"], FT.Money(cut, "short"), string.format("%g", math.floor(FT.Cut() * 1000 + 0.5) / 10)) }
        end
    else
        if id and not each then
            local b = FT.Calc.Buy(id, qty)
            out.lines = FT.Calc.BuyLines(b)
            if b then out.total, out.unit = b.total, b.avg end
        elseif each then
            out.total, out.unit = each * qty, each
            out.lines = { string.format(L["%s for %s"], FT.Money(each * qty), FT.Num(qty)) .. FT.C("dim", "  ·  " .. string.format(L["%s each"], FT.Money(each, "short"))) }
            if id then
                local v = FT.VendorBuy(id)
                if v and v < each then out.lines[2] = FT.C("accent", string.format(L["A vendor sells it for %s  ·  never pay over that"], FT.Money(v, "short"))) end
            end
        end
    end
    out.lines = out.lines or { FT.C("dim", L["Pick an item, or type a price each."]) }
    return out
end

-- the suggestions: ids (nil or empty: closed)
function T.ShowSuggest(ids)
    local sg = T.sugg
    if not sg then return end
    -- nothing to suggest, or the one typed exactly
    if not ids or #ids == 0 or (#ids == 1 and ids[1] == state.id and FT.Fold(FT.Name(ids[1]) or "") == FT.Fold(T.item:GetText() or "")) then
        sg.ids = nil
        sg:Hide()
        return
    end
    sg.ids = ids
    for i, r in ipairs(sg.rows) do
        local id = ids[i]
        r.id = id
        r:SetShown(id ~= nil)
        if id then
            r.icon:SetItem(id)
            UI.FitBits(r.name, FT.ItemText(id, 40))
            local price = FT.Price(id)
            r.price:SetText(price and FT.Money(price, "short") or "")
        end
    end
    sg:SetHeight(#ids * UI.RowH(22) + 4)
    sg:Show()
end

-- a suggestion chosen: its name in the box, the sums on it
function T.PickItem(id)
    state.id = id
    T.item:SetValue(FT.Name(id) or "")
    T.ShowSuggest(nil)
    T.Update()
end

local function Show(sum)
    for i, t in ipairs(T.lines) do
        t.fitText = nil
        UI.FitBits(t, sum.lines[i] or "")
    end
end

function T.Update()
    if not built then return end
    T.pick:SetText(state.id and FT.ItemText(state.id, 40) or FT.C("dim", L["no item: plain sums"]))
    T.icon:SetShown(state.id ~= nil)
    if state.id then T.icon:SetItem(state.id) end
    Show(T.Sum())
end

-- onto the cheat sheet (Enter in a box, or Add)
function T.Log()
    local s = T.Sum()
    if not s.total then return end
    local sheet = Sheet()
    table.insert(sheet, 1, { t = time(), id = s.id, mode = s.mode, qty = s.qty, unit = s.unit and math.floor(s.unit + 0.5),
        total = math.floor(s.total + 0.5), take = s.take and math.floor(s.take + 0.5), each = T.each:GetText() ~= "" and T.each:GetText() or nil })
    while #sheet > SHEET_MAX do table.remove(sheet) end
    T.RefreshSheet()
end

function T.RefreshSheet()
    if not built then return end
    local sheet = Sheet()
    T.sheet:SetItems(sheet, true)
    local buy, take = 0, 0
    for _, x in ipairs(sheet) do
        if x.mode == "sell" then take = take + (x.take or x.total or 0) else buy = buy + (x.total or 0) end
    end
    UI.FitBits(T.totals, #sheet == 0 and FT.C("dim", L["Empty: your sums land here."]) or
        (L["Buying"] .. " " .. FT.C("down", FT.Money(buy, "short")) .. FT.C("dim", "  ·  ") .. L["Selling"] .. " " .. FT.C("up", FT.Money(take, "short"))
            .. FT.C("dim", "  ·  ") .. L["Net"] .. " " .. FT.C((take - buy) >= 0 and "up" or "down", ((take - buy) >= 0 and "+" or "-") .. FT.Money(math.abs(take - buy), "short"))))
end

local function SetMode(m)
    state.mode = m
    T.seg:SetValue(m)
    T.Update()
end

function T.Build(p)
    p0 = p
    local left = UI.Panel(p, "bg1", "line")
    left:SetPoint("TOPLEFT", 8, -8)
    left:SetPoint("BOTTOMLEFT", 8, 8)
    T.left = left
    local right = UI.Panel(p, "bg1", "line")
    right:SetPoint("TOPRIGHT", -8, -8)
    right:SetPoint("BOTTOMRIGHT", -8, 8)
    right:SetPoint("LEFT", left, "RIGHT", 8, 0)
    UI.OnSize(p, function(self, w) left:SetWidth(math.floor((w - 24) * 0.55)) end)

    local title = UI.Text(left, 13, "muted")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText(L["Calculator"])
    T.seg = UI.Segmented(left, { { "buy", L["Buying"] }, { "sell", L["Selling"] } }, function(v) SetMode(v) end, 22)
    T.seg:SetPoint("TOPRIGHT", -12, -8)
    T.seg:SetValue(state.mode)

    -- the item
    local lab1 = UI.Text(left, 11, "muted")
    lab1:SetPoint("TOPLEFT", 14, -48)
    lab1:SetText(L["Item"])
    T.item = UI.Input(left, 220, 24, L["Type an item, or leave it empty"], function(text)
        FT.Debounce("calcItem", 0.2, function()
            state.id = FindItem(text)
            T.Update()
            T.ShowSuggest(Suggest(text))
        end)
    end, function()
        -- Enter: the first suggestion when the list is open, else onto the sheet
        local first = T.sugg and T.sugg:IsShown() and T.sugg.ids and T.sugg.ids[1]
        if first then T.PickItem(first) else T.Log() end
    end)
    T.item:SetPoint("TOPLEFT", lab1, "BOTTOMLEFT", 0, -4)
    T.item:SetPoint("RIGHT", left, "RIGHT", -14, 0)
    UI.ClearButton(T.item, function() state.id = nil; T.ShowSuggest(nil); T.Update() end)
    -- the suggestions under the box, over the page; a click picks one
    local sg = CreateFrame("Frame", nil, left)
    sg:SetPoint("TOPLEFT", T.item, "BOTTOMLEFT", 0, -2)
    sg:SetPoint("TOPRIGHT", T.item, "BOTTOMRIGHT", 0, -2)
    sg:SetFrameLevel(left:GetFrameLevel() + 20)
    UI.Skin(sg, "popup", "bg2")
    sg:EnableMouse(true)
    sg.rows = {}
    for i = 1, 8 do
        local r = CreateFrame("Button", nil, sg)
        r:SetHeight(UI.RowH(22))
        r:SetPoint("TOPLEFT", 1, -2 - (i - 1) * UI.RowH(22))
        r:SetPoint("TOPRIGHT", -1, -2 - (i - 1) * UI.RowH(22))
        r.hl = UI.RoundTex(r, "BACKGROUND", "hl", 1)
        r.hl:SetAllPoints()
        r.hl:Hide()
        r.icon = UI.Icon(r, 16)
        r.icon:SetPoint("LEFT", 6, 0)
        r.price = UI.Text(r, 11, "muted", "RIGHT")
        r.price:SetPoint("RIGHT", -8, 0)
        r.name = UI.Text(r, 12, "text")
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
        r.name:SetPoint("RIGHT", r.price, "LEFT", -6, 0)
        if r.name.SetWordWrap then r.name:SetWordWrap(false) end
        r:SetScript("OnEnter", function(self) self.hl:Show() end)
        r:SetScript("OnLeave", function(self) self.hl:Hide() end)
        r:SetScript("OnClick", function(self) if self.id then T.PickItem(self.id) end end)
        sg.rows[i] = r
    end
    sg:Hide()
    T.sugg = sg
    -- leaving the box closes it (a moment later, so a click on it still lands)
    T.item:HookScript("OnEditFocusLost", function() C_Timer.After(0.2, function() if T.sugg and not T.sugg:IsMouseOver() then T.ShowSuggest(nil) end end) end)
    T.icon = UI.Icon(left, 18)
    T.icon:SetPoint("TOPLEFT", T.item, "BOTTOMLEFT", 0, -6)
    T.pick = UI.Text(left, 12, "text")
    T.pick:SetPoint("LEFT", T.icon, "RIGHT", 6, 0)
    T.pick:SetPoint("RIGHT", left, "RIGHT", -14, 0)
    if T.pick.SetWordWrap then T.pick:SetWordWrap(false) end

    -- how many, a price each
    local lab2 = UI.Text(left, 11, "muted")
    lab2:SetPoint("TOPLEFT", T.item, "BOTTOMLEFT", 0, -34)
    lab2:SetText(L["How many"])
    T.qty = UI.Input(left, 90, 24, "1", function() T.Update() end, function() T.Log() end)
    T.qty:SetPoint("TOPLEFT", lab2, "BOTTOMLEFT", 0, -4)
    if T.qty.SetNumeric then T.qty:SetNumeric(true) end
    local lab3 = UI.Text(left, 11, "muted")
    lab3:SetPoint("LEFT", lab2, "LEFT", 110, 0)
    lab3:SetText(L["Each"])
    T.each = UI.Input(left, 130, 24, L["auto"], function() T.Update() end, function() T.Log() end)
    T.each:SetPoint("TOPLEFT", lab3, "BOTTOMLEFT", 0, -4)
    T.add = UI.Button(left, L["Add to the sheet"], 10, 24, "primary", function() T.Log() end)
    T.add:FitText(22)
    T.add:SetPoint("LEFT", T.each, "RIGHT", 10, 0)

    T.lines = {}
    for i = 1, 5 do
        local t = UI.Text(left, i == 1 and 14 or 12, i == 1 and "text" or "muted")
        t:SetPoint("TOPLEFT", T.qty, "BOTTOMLEFT", 0, -22 - (i == 1 and 0 or (8 + (i - 1) * UI.RowH(20))))
        t:SetPoint("RIGHT", left, "RIGHT", -14, 0)
        if t.SetWordWrap then t:SetWordWrap(false) end
        T.lines[i] = t
    end
    local foot = UI.Text(left, 10, "dim")
    foot:SetPoint("BOTTOMLEFT", 14, 12)
    foot:SetPoint("RIGHT", left, "RIGHT", -14, 0)
    if foot.SetWordWrap then foot:SetWordWrap(false) end
    UI.FitBits(foot, L["Each: gold (12.5) or 12g 50s  ·  empty: the listings (buying) or a copper under the cheapest (selling)  ·  Enter adds it to the sheet"])

    -- the cheat sheet
    local st = UI.Text(right, 13, "muted")
    st:SetPoint("TOPLEFT", 14, -12)
    st:SetText(L["Cheat sheet"])
    T.wipe = UI.Button(right, L["Wipe"], 10, 20, "default", function(self)
        -- twice to wipe (no pop-up): the first click asks on the button itself
        if self.armed and GetTime() - self.armed < 4 then
            self.armed = nil
            wipe(Sheet())
            self:SetLabel(L["Wipe"])
            self:FitText(16)
            T.RefreshSheet()
        else
            self.armed = GetTime()
            self:SetLabel(L["Sure? Click again"])
            self:FitText(16)
            C_Timer.After(4, function() if self.armed and GetTime() - self.armed >= 4 then self.armed = nil; self:SetLabel(L["Wipe"]); self:FitText(16) end end)
        end
    end)
    T.wipe:FitText(16)
    T.wipe:SetPoint("TOPRIGHT", -10, -8)
    T.totals = UI.Text(right, 11, "text")
    T.totals:SetPoint("TOPLEFT", 14, -34)
    T.totals:SetPoint("RIGHT", right, "RIGHT", -14, 0)
    T.sheet = UI.List(right, {
        rowHeight = UI.RowH(40),
        setup = function(row)
            row.badge = UI.Badge(row, 52, 18)
            row.badge:SetPoint("TOPLEFT", 6, -4)
            row.total = UI.Text(row, 12, "text", "RIGHT")
            row.total:SetPoint("TOPRIGHT", -24, -5)
            row.what = UI.Text(row, 12, "text")
            row.what:SetPoint("LEFT", row.badge, "RIGHT", 8, 0)
            row.what:SetPoint("RIGHT", row.total, "LEFT", -8, 0)
            if row.what.SetWordWrap then row.what:SetWordWrap(false) end
            row.sub = UI.Text(row, 10, "dim")
            row.sub:SetPoint("TOPLEFT", row.badge, "BOTTOMLEFT", 2, -4)
            row.sub:SetPoint("RIGHT", -24, 0)
            if row.sub.SetWordWrap then row.sub:SetWordWrap(false) end
            row.x = UI.Button(row, "x", 16, 16, "default", function(self)
                local sheet = Sheet()
                for i, e in ipairs(sheet) do if e == self.entry then table.remove(sheet, i) break end end
                T.RefreshSheet()
            end)
            row.x:SetPoint("RIGHT", -4, 0)
        end,
        update = function(row, x)
            row.x.entry = x
            row.badge:Set(x.mode == "sell" and "SELL" or "BUY")
            UI.FitBits(row.what, FT.Num(x.qty) .. " x " .. (x.id and FT.ItemText(x.id, 30) or L["(no item)"]))
            row.total:SetText(x.mode == "sell" and FT.C("up", FT.Money(x.take or x.total or 0, "short")) or FT.Money(x.total or 0, "short"))
            UI.FitBits(row.sub, (x.unit and (FT.Money(x.unit, "short") .. " " .. L["each"]) or "") .. "  ·  " .. date("%b %d %H:%M", x.t))
        end,
        onClick = function(x)
            -- load it back
            state.id = x.id
            T.item:SetValue(x.id and (FT.Name(x.id) or "") or "")
            T.qty:SetValue(tostring(x.qty or 1))
            T.each:SetValue(x.each or "")
            SetMode(x.mode or "buy")
        end,
        onEnter = function(row, x)
            if x.id then UI.TipItem(row, x.id) else GameTooltip:SetOwner(row, "ANCHOR_RIGHT") end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Click: back into the calculator  ·  x: off the sheet"], 0.6, 0.64, 0.7, true)
            GameTooltip:Show()
        end,
    })
    T.sheet:SetPoint("TOPLEFT", 6, -56)
    T.sheet:SetPoint("BOTTOMRIGHT", -4, 6)
    T.sheet:SetEmptyText(L["Your sums land here: press Enter or Add to the sheet."])
    built = true
end

function T.Refresh()
    if not built then return end
    T.Update()
    T.RefreshSheet()
end
T.OnShow = T.Refresh

-- (v0.51) an item page's Calculator button: this page, on that item
function FT.ShowCalc(itemID, mode)
    FT.SelectTab("calc")
    if not built then return end
    state.id = itemID
    T.item:SetValue(itemID and (FT.Name(itemID) or "") or "")
    if mode then SetMode(mode) else T.Update() end
end

-- new prices: the sum follows
FT.On("FT_SCAN_DONE", function() if built and T.left:IsVisible() then T.Update() end end)
FT.On("FT_LIVE_UPDATED", function() if built and T.left:IsVisible() then T.Update() end end)
