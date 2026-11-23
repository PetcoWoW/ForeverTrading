-- ForeverTrading: Selling page. On the left what you carry that the auction house takes, at market prices with
-- a signal; in the middle one item to post: the market (the cheapest listing, the fair price, the vendor's, the
-- signal), the quantity, the price per unit (a copper under the cheapest to begin with), how long, and what it
-- comes to - deposit, the auction house's cut, what you get - with warnings (under the vendor price, far under the fair one,
-- above the cheapest, a price jump or a fast fall). Post asks once more with everything. Its order book on the
-- right, live at the auction house.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local T = {}
FT.Tabs.sell = T

local LEFT_W, RIGHT_W = 400, 232
local page, list, form, book, center, totalText
-- My auctions: their list, its header, the detail of one, the buttons under the list
local olist, oform, viewSeg, bagsHeader, ownHeader, ownButtons
-- view: "bags" (post from your bags) or "owned" (your auctions); okey: the auction chosen
local state = { key = nil, search = "", auto = true, view = "bags", okey = nil }
local entries = {}

-- goods by item; gear by the very item (its GUID), not by the bag slot it happens to be in
local function KeyOf(e)
    if e.gear then return e.guid or ((e.link or e.id) .. "@" .. e.bag .. ":" .. e.slot) end
    return e.id
end

local function Current()
    for _, e in ipairs(entries) do
        if KeyOf(e) == state.key then return e end
    end
    return nil
end

---------------------------------------------------------------------------
-- The bags
---------------------------------------------------------------------------
local function Rows()
    entries = FT.BagItems()
    local out, sum = {}, 0
    local search = state.search ~= "" and FT.Fold(state.search) or nil
    for _, e in ipairs(entries) do
        local price, _, _, _, gone = FT.Price(e.id)
        e.price = price
        e.value = price and price * e.count or nil
        e.signal, e.strength = FT.An.SellSignal(FT.An.Stats(e.id))
        if gone then e.signal = "NODATA" end
        if e.value then sum = sum + e.value end
        local name = FT.Name(e.id)
        if not search or (name and FT.Fold(name):find(search, 1, true)) then out[#out + 1] = e end
    end
    -- taken off to post again and back from the mail: first; then what you brought from the other auction house
    -- (the carry list) to sell here
    for _, e in ipairs(out) do
        e.repost = FT.Owned.Waiting(e.id) ~= nil
        local c = FT.Carry.Get(e.id)
        e.carry = (c and c.sell == FT.house) and c or nil
    end
    table.sort(out, function(a, b)
        if a.repost ~= b.repost then return a.repost end
        if (a.carry ~= nil) ~= (b.carry ~= nil) then return a.carry ~= nil end
        local va, vb = a.value or -1, b.value or -1
        if va ~= vb then return va > vb end
        return a.id < b.id
    end)
    return out, sum
end

local function NameCell(row)
    local f = CreateFrame("Frame", nil, row)
    f:SetHeight(24)
    f.icon = UI.Icon(f, 18)
    f.icon:SetPoint("LEFT", 0, 0)
    f.text = UI.Text(f, 12, "text")
    f.text:SetPoint("LEFT", f.icon, "RIGHT", 6, 0)
    f.text:SetPoint("RIGHT", 0, 0)
    return f
end

local function BuildList(p)
    local panel = UI.Panel(p, "bg1", "line")
    panel:SetPoint("TOPLEFT", 8, -8)
    panel:SetPoint("BOTTOMLEFT", 8, 8)
    panel:SetWidth(LEFT_W)
    -- your bags or your auctions
    viewSeg = UI.Segmented(panel, { { "bags", L["Your bags"] }, { "owned", L["My auctions"] } }, function(v) T.SetView(v) end, 24)
    T.viewSeg = viewSeg
    viewSeg:SetPoint("TOPLEFT", 8, -7)
    viewSeg:SetValue(state.view)
    totalText = UI.Text(panel, 11, "dim", "RIGHT")
    totalText:SetPoint("TOPRIGHT", -12, -13)

    local search = UI.Input(panel, LEFT_W - 20, 26, L["Search item..."], function(text)
        state.search = text or ""
        FT.Debounce("sellSearch", 0.25, function() T.RefreshList() end)
    end)
    search:SetPoint("TOPLEFT", 10, -36)
    UI.ClearButton(search, function()
        state.search = ""
        T.RefreshList()
    end)

    local cols = {
        { key = "name", title = L["Item"], width = "fill", make = NameCell, cellHeight = 24 },
        { key = "count", title = L["Qty"], width = 42, justify = "RIGHT" },
        { key = "price", title = L["Price"], width = 70, justify = "RIGHT" },
        { key = "signal", title = L["Signal"], width = 80, justify = "CENTER", make = function(row) return UI.Badge(row, 78, 18) end,
            cellHeight = 18 },
    }
    local header = UI.Header(panel, cols)
    header:SetPoint("TOPLEFT", 1, -70)
    header:SetPoint("TOPRIGHT", -1, -70)
    bagsHeader = header

    list = UI.List(panel, {
        rowHeight = 26,
        cols = cols,
        liveID = function(e) return e.id end,
        update = function(row, e)
            local c = row.cells.name
            c.icon:SetItem(e.id)
            c.text:SetText(FT.ItemText(e.id) .. (e.repost and FT.C("accent", " " .. L["post again"]) or "")
                .. (e.carry and FT.C("accent", " " .. L["brought"]) or ""))
            row.cells.count:SetText(FT.Num(e.count))
            row.cells.price:SetText(e.price and FT.Money(e.price, "short") or FT.C("dim", "—"))
            row.cells.signal:Set(e.signal, nil, e.strength)
        end,
        isSelected = function(e) return KeyOf(e) == state.key end,
        onClick = function(e)
            if UI.ItemClick(e.id) then return end
            T.Select(KeyOf(e))
        end,
        onEnter = function(row, e)
            UI.TipItem(row, e.id)
            if e.value then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(string.format(L["You have %s: worth %s"], FT.Num(e.count), FT.Money(e.value)), 0.85, 0.87, 0.9)
                GameTooltip:Show()
            end
        end,
    })
    list:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    list:SetPoint("BOTTOMRIGHT", -1, 4)
    T.BuildOwnedList(panel)
end

function T.RefreshList()
    if not list then return end
    if state.view == "owned" then return T.RefreshOwned() end
    local rows, sum = Rows()
    list:SetEmptyText(state.search ~= "" and L["Nothing matches"] or L["Nothing in your bags the auction house would take."])
    list:SetItems(rows, true)
    totalText:SetText(sum > 0 and string.format(L["worth %s"], FT.Money(sum, "short")) or "")
end

---------------------------------------------------------------------------
-- The posting form
---------------------------------------------------------------------------
local function Label(f, text, x, y)
    local l = UI.Text(f, 11, "muted")
    l:SetPoint("TOPLEFT", x, y)
    l:SetText(text)
    return l
end

-- a market fact: its name, the value, a small line under it (how many, how old...)
local function Fact(f, label)
    local c = CreateFrame("Frame", nil, f)
    c:SetSize(120, 46)
    c.label = UI.Text(c, 10, "dim")
    c.label:SetPoint("TOPLEFT", 0, 0)
    c.label:SetText(label)
    c.value = UI.Text(c, 13, "text")
    c.value:SetPoint("TOPLEFT", 0, -15)
    c.sub = UI.Text(c, 10, "dim")
    c.sub:SetPoint("TOPLEFT", 0, -32)
    function c:Fit(w)
        self:SetWidth(w)
        self.label:SetWidth(w)
        self.value:SetWidth(w)
        self.sub:SetWidth(w)
    end
    return c
end

local function SumLine(f, label, y, big)
    local l = UI.Text(f, 12, big and "text" or "muted")
    l:SetPoint("TOPLEFT", 16, y)
    l:SetText(label)
    local v = UI.Text(f, big and 15 or 13, "text", "RIGHT")
    v:SetPoint("TOPRIGHT", -16, y + (big and 1 or 0))
    return v
end

local function BuildForm(p)
    local f = UI.Panel(p, "bg1", "line")
    form = f
    f.icon = UI.Icon(f, 40)
    f.icon:SetPoint("TOPLEFT", 16, -14)
    f.icon:EnableMouse(true)
    f.icon:SetScript("OnEnter", function(self)
        local e = Current()
        if e then UI.TipItem(self, e.id) end
    end)
    f.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.name = UI.Text(f, 16, "text")
    f.name:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 10, -2)
    f.name:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    f.sub = UI.Text(f, 11, "dim")
    f.sub:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -6)
    f.sub:SetPoint("RIGHT", f, "RIGHT", -16, 0)

    -- the market
    f.marketTitle = UI.Text(f, 12, "accent")
    f.marketTitle:SetPoint("TOPLEFT", 16, -70)
    f.marketTitle:SetText(L["Market"])
    f.best = Fact(f, L["Cheapest listed"])
    f.fair = Fact(f, L["Fair price"])
    f.vendor = Fact(f, L["Vendor pays"])
    f.badge = UI.Badge(f, 84, 18)
    f.badge:SetPoint("TOPLEFT", 16, -144)
    f.reason = UI.Text(f, 11, "muted")
    f.reason:SetPoint("LEFT", f.badge, "RIGHT", 10, 0)
    f.reason:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    local sep1 = UI.HLine(f, "line")
    sep1:SetPoint("TOPLEFT", 1, -172)
    sep1:SetPoint("TOPRIGHT", -1, -172)

    -- quantity
    Label(f, L["Quantity"], 16, -190)
    f.qty = UI.Input(f, 70, 24, "", function()
        T.UpdateSummary()
    end)
    f.qty:SetNumeric(true)
    f.qty:SetPoint("TOPLEFT", 170, -185)
    f.qtyOf = UI.Text(f, 11, "dim")
    f.qtyOf:SetPoint("LEFT", f.qty, "RIGHT", 8, 0)
    f.max = UI.Button(f, L["Max"], 10, 22, "default", function()
        local e = Current()
        if e then
            f.qty:SetValue(tostring(T.MaxQty(e)))
            T.UpdateSummary()
        end
    end)
    f.max:FitText(20)
    f.max:SetPoint("LEFT", f.qtyOf, "RIGHT", 10, 0)

    -- price per unit
    Label(f, L["Price per unit"], 16, -226)
    f.price = UI.MoneyInput(f, function() T.UpdateSummary() end)
    f.price:SetPoint("TOPLEFT", 170, -221)
    for _, box in ipairs(f.price.boxes) do
        box:HookScript("OnTextChanged", function(_, user)
            if user then state.auto = false end
            T.UpdateSummary()
        end)
    end
    -- the price in one click: a copper under the cheapest, the same as the cheapest, the fair price
    f.under = UI.Button(f, string.format(L["1%s under"], FT.COIN.copper), 10, 22, "default", function() T.SetPrice("under") end)
    f.under:FitText(20)
    f.under:SetPoint("TOPLEFT", 170, -252)
    f.under:SetTip(L["A copper under the cheapest"], L["Yours becomes the cheapest listing: it sells first."])
    f.same = UI.Button(f, L["At the cheapest"], 10, 22, "default", function() T.SetPrice("same") end)
    f.same:FitText(20)
    f.same:SetPoint("LEFT", f.under, "RIGHT", 6, 0)
    f.same:SetTip(L["At the cheapest"], L["The same price as the cheapest listing now."])
    f.fairBtn = UI.Button(f, L["Fair price"], 10, 22, "default", function() T.SetPrice("fair") end)
    f.fairBtn:FitText(20)
    f.fairBtn:SetPoint("LEFT", f.same, "RIGHT", 6, 0)
    f.fairBtn:SetTip(L["Fair price"], L["The median of the last days' prices, weighted by how many were listed and how recent."])

    -- how long
    Label(f, L["Duration"], 16, -292)
    local lengths = {}
    for i = 1, 3 do lengths[i] = { i, string.format(L["%dh"], FT.Sell.Hours(i)) } end
    f.dur = UI.Segmented(f, lengths, function(v)
        FT.S.sellDuration = v
        T.UpdateSummary()
    end)
    f.dur:SetPoint("TOPLEFT", 170, -288)
    local sep2 = UI.HLine(f, "line")
    sep2:SetPoint("TOPLEFT", 1, -320)
    sep2:SetPoint("TOPRIGHT", -1, -320)

    -- what it comes to
    f.total = SumLine(f, L["For all"], -334)
    f.deposit = SumLine(f, L["Deposit (back when it sells)"], -354)
    f.cut = SumLine(f, L["Auction house cut"], -374)
    f.net = SumLine(f, L["You get"], -398, true)

    f.warn = UI.Text(f, 11, "accent")
    f.warn:SetPoint("TOPLEFT", 16, -428)
    f.warn:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    if f.warn.SetWordWrap then f.warn:SetWordWrap(true) end
    f.warn:SetJustifyV("TOP")

    f.post = UI.Button(f, L["Post"], 10, 30, "primary", function() T.Post() end)
    f.post.label:SetFont(UI.FONT, 13, "")
    f.post:FitText(40)
    f.post:SetPoint("BOTTOMRIGHT", -16, 16)
    f.hint = UI.Text(f, 10, "dim")
    f.hint:SetPoint("BOTTOMLEFT", 16, 24)
    f.hint:SetPoint("RIGHT", f.post, "LEFT", -12, 0)
    f.hint:SetText(L["Post asks once more with everything before anything happens."])
    -- the warnings take the room down to the button
    f.warn:SetPoint("BOTTOM", f.post, "TOP", 0, 10)

    UI.OnSize(f, function(self, w)
        local cw = math.floor((w - 32) / 3)
        for i, c in ipairs({ self.best, self.fair, self.vendor }) do
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", 16 + (i - 1) * cw, -92)
            c:Fit(cw - 8)
        end
    end)

    f.empty = UI.EmptyState(f, L["Pick an item"], L["What you carry is on the left: pick one to post it."])
    f.empty:SetPoint("CENTER")
end

-- the most that can go in one posting: stackable goods all your stacks; anything else one item per auction
function T.MaxQty(e)
    if e.gear then return 1 end
    local loc = FT.Sell.Location(e.bag, e.slot)
    if FT.Sell.Kind(loc) == "item" then return 1 end
    return e.count
end

-- a copper under the cheapest listing, or the fair price
local function Suggestion(e, how)
    local p, _, _, _, gone = FT.Price(e.id)
    local s = FT.An.Stats(e.id)
    if how == "fair" then return FT.Sell.Price(s.fair or p) end
    if how == "same" and p and not gone then return FT.Sell.Price(p) end
    if p and not gone then return FT.Sell.Price(p - 1) end
    return FT.Sell.Price(s.fair or p)
end

-- what to watch out for at this price; severe: a reason to slow the click down
local function Warnings(e, unit)
    local warns, severe = {}, false
    if not (unit and unit > 0) then return warns, severe end
    local p, t, _, _, gone = FT.Price(e.id)
    local s = FT.An.Stats(e.id)
    local vendor = FT.VendorSell(e.id)
    if vendor and vendor > 0 and unit * (1 - FT.Cut()) < vendor then
        warns[#warns + 1] = FT.C("down", string.format(L["Less than a vendor pays (%s each, no cut, no waiting)."], FT.Money(vendor, "short")))
        severe = true
    end
    if s.fair and unit < s.fair * 0.8 then
        warns[#warns + 1] = FT.C("down", string.format(L["%s under the fair price (%s)."], FT.Pct(1 - unit / s.fair, true), FT.Money(s.fair, "short")))
        severe = true
    end
    if p and not gone and unit > p then
        warns[#warns + 1] = FT.C("accent", string.format(L["Dearer than the cheapest listing (%s): yours sells after it."], FT.Money(p, "short")))
    end
    if s.spike then
        warns[#warns + 1] = FT.C("accent", string.format(L["A price jump right now (buyout?): the fair price is ~%s - it may not last."], FT.Money(s.fair, "short")))
    elseif s.falling then
        warns[#warns + 1] = FT.C("down", string.format(L["The price is falling fast: %s vs its fair price."], FT.Pct(s.price / s.fair - 1, true)))
        severe = true
    end
    -- the competition: since the last check, and against what is usual
    if s.dropped and not s.falling then
        warns[#warns + 1] = FT.C("accent", string.format(L["The price went %s since the check %s: others undercut."], FT.Pct(s.sinceP, true), FT.Ago(s.prev.t)))
    end
    if s.flood then
        warns[#warns + 1] = FT.C("accent", string.format(L["Flooded: %s listed, usually ~%s - it may sell slowly, and undercuts come."],
            FT.Num(s.listed), FT.Num(math.floor(s.typicalQ + 0.5))))
    end
    if s.crowd then
        warns[#warns + 1] = FT.C("accent", string.format(L["More sellers than usual: %d, usually ~%d - expect undercuts."],
            s.sellersNow, math.floor(s.typicalS + 0.5)))
    end
    -- the market as last seen, not right now
    if t and time() - t > 1800 then
        warns[#warns + 1] = FT.C("accent", string.format(L["The market prices are from %s: wait for the live update at the auction house."], FT.Ago(t)))
    end
    if e.gear then
        warns[#warns + 1] = FT.C("dim", L["Gear: the prices are of its cheapest version listed - check yours (item level, \"of the ...\")."])
    end
    return warns, severe
end

function T.SetPrice(how)
    local e = Current()
    if not e then return end
    if how then state.auto = false end
    local price = Suggestion(e, how or "under")
    form.price:SetValue(price)
    T.UpdateSummary()
end

local function Shown(show)
    local f = form
    for _, r in ipairs({ f.icon, f.name, f.sub, f.marketTitle, f.best, f.fair, f.vendor, f.badge, f.reason, f.qty, f.qtyOf,
        f.max, f.price, f.under, f.same, f.fairBtn, f.dur, f.total, f.deposit, f.cut, f.net, f.warn, f.post, f.hint }) do
        r:SetShown(show)
    end
    f.empty:SetShown(not show)
end

-- the market facts of the item (live: they follow the auction house)
local function Facts(e)
    local f = form
    local p, t, _, listed, gone = FT.Price(e.id)
    local s = FT.An.Stats(e.id)
    if p and not gone then
        f.best.value:SetText(FT.Money(p, "short"))
        local parts = {}
        if listed then parts[#parts + 1] = FT.Num(listed) .. " " .. L["pcs"] end
        if t then parts[#parts + 1] = FT.Ago(t) end
        f.best.sub:SetText(table.concat(parts, "  ||  "))
    else
        f.best.value:SetText(FT.C("dim", L["none listed"]))
        f.best.sub:SetText("")
    end
    f.fair.value:SetText(s.fair and FT.Money(s.fair, "short") or FT.C("dim", "—"))
    f.fair.sub:SetText(s.fair and L["of the last days"] or "")
    local vendor = FT.VendorSell(e.id)
    f.vendor.value:SetText(vendor and vendor > 0 and FT.Money(vendor, "short") or FT.C("dim", "—"))
    f.vendor.sub:SetText(vendor and vendor > 0 and L["no cut, no waiting"] or "")
    local sig, strength, reason = FT.An.SellSignal(s)
    f.badge:Set(sig, nil, strength)
    f.reason:SetText(reason or "")
end

-- keep: the same item again (a refresh) - what you typed stays
function T.ShowForm(keep)
    if not form then return end
    if oform then oform:SetShown(state.view == "owned") end
    form:SetShown(state.view ~= "owned")
    if state.view == "owned" then return T.ShowOwned() end
    local e = Current()
    if not e then
        Shown(false)
        book:SetItem(nil)
        return
    end
    Shown(true)
    local f = form
    f.icon:SetItem(e.id)
    f.name:SetText(e.gear and e.link or FT.ItemText(e.id, 40))
    local kind = FT.Sell.Kind(FT.Sell.Location(e.bag, e.slot))
    local parts = { string.format(L["in your bags: %s"], FT.Num(e.count)) }
    if e.gear or kind == "item" then
        parts[#parts + 1] = L["posted one at a time"]
    else
        parts[#parts + 1] = L["all your stacks in one posting"]
    end
    -- brought from the other auction house (the carry list): what it cost there, what the deal counted on here
    local carry = FT.Carry.Get(e.id)
    if carry and carry.sell == FT.house and carry.unit and carry.target then
        parts[#parts + 1] = FT.C("accent", string.format(L["bought at %s for %s each: list at ~%s"], FT.House.Name(carry.buy),
            FT.Money(math.floor(carry.unit + 0.5), "short"), FT.Money(math.floor(carry.target + 0.5), "short")))
    end
    f.sub:SetText(table.concat(parts, FT.C("dim", "  ||  ")))
    Facts(e)
    local max = T.MaxQty(e)
    f.qtyOf:SetText(string.format(L["of %s"], FT.Num(max)))
    if f.qty.SetEnabled then f.qty:SetEnabled(not e.gear) end
    f.max:SetShown(not e.gear)
    if not keep then
        state.auto = true
        f.qty:SetValue("1")
        f.dur:SetValue(FT.S.sellDuration or 2)
        T.SetPrice(nil)
    else
        local qty = tonumber(f.qty:GetText()) or 0
        if qty > max then f.qty:SetValue(tostring(max)) end
        -- the price follows the market until you change it
        if state.auto then T.SetPrice(nil) end
    end
    book:SetItem(e.id)
    T.UpdateSummary()
end

-- what the posting comes to, and what to watch out for
function T.UpdateSummary()
    local f = form
    local e = Current()
    if not (f and e) then return end
    local max = T.MaxQty(e)
    local typed = tonumber(f.qty:GetText()) or 0
    -- more than there is: the box shows the most (not while you type)
    if typed > max and not f.qty:HasFocus() then f.qty:SetValue(tostring(max)) end
    local qty = math.min(typed, max)
    local unit = f.price:GetValue()
    local dur = f.dur.value or FT.S.sellDuration or 2
    local loc = FT.Sell.Location(e.bag, e.slot)
    local kind = FT.Sell.Kind(loc) or (e.gear and "item" or "commodity")
    local total = unit and unit * qty or nil
    local cut = total and math.floor(total * FT.Cut())
    local deposit = qty > 0 and FT.Sell.Deposit(kind, e.id, loc, dur, qty) or nil
    f.total:SetText(total and FT.Money(total) or FT.C("dim", "—"))
    f.deposit:SetText(deposit and FT.Money(deposit) or FT.C("dim", "—"))
    f.cut:SetText(cut and FT.Money(cut) or FT.C("dim", "—"))
    f.net:SetText(total and FT.C("up", FT.Money(total - cut)) or FT.C("dim", "—"))

    f.warn:SetText(table.concat((Warnings(e, unit)), "\n"))

    local can = FT.Sell.Possible() and unit and unit > 0 and qty > 0 and not FT.Sell.Busy() and not FT.Buy.Busy()
    f.post:SetUsable(can and true or false)
    if not FT.Sell.Possible() then
        f.post:SetTip(L["Post"], FT.House.Why(L["Talk to an auctioneer to sell."]))
    else
        f.post:SetTip(L["Post"], L["Post asks once more with everything before anything happens."])
    end
end

-- the bag slot of the entry as it is now (things move in bags): the same item - for gear the very same one
local function FindLocation(e)
    for _, s in ipairs(e.slots) do
        local l = FT.Sell.Location(s[1], s[2])
        if l and (not (C_Item and C_Item.GetItemID) or C_Item.GetItemID(l) == e.id) then
            if not (e.gear and e.guid and C_Item.GetItemGUID) then return l end
            local ok, guid = pcall(C_Item.GetItemGUID, l)
            if ok and guid == e.guid then return l end
        end
    end
    return nil
end

function T.Post()
    local e = Current()
    FT.Debug("sell: Post pressed, entry", e and e.id, e and e.count)
    if not e then return end
    local loc = FindLocation(e)
    if not loc then
        FT.Print(L["The item isn't in that bag slot any more."])
        T.Refresh()
        return
    end
    local kind = FT.Sell.Kind(loc)
    FT.Debug("sell: kind", kind, "valid", FT.Sell.Valid(loc))
    if not kind or not FT.Sell.Valid(loc) then
        FT.Print(L["The auction house doesn't take this item."])
        return
    end
    local qty = kind == "commodity" and math.min(tonumber(form.qty:GetText()) or 0, T.MaxQty(e)) or 1
    local unit = FT.Sell.Price(form.price:GetValue())
    local dur = form.dur.value or FT.S.sellDuration or 2
    FT.Debug("sell: qty", qty, "unit", unit, "duration", dur)
    if not (unit and unit > 0 and qty > 0) then return end
    -- what the question shows comes from the slot itself (its link, its GUID)
    local link = C_Item and C_Item.GetItemLink and C_Item.GetItemLink(loc) or e.link
    local guid
    if kind ~= "commodity" and C_Item and C_Item.GetItemGUID then
        local ok, g = pcall(C_Item.GetItemGUID, loc)
        if ok then guid = g end
    end
    local warnings, severe = Warnings(e, unit)
    FT.Sell.Post({
        kind = kind, itemID = e.id, loc = loc, guid = guid, qty = qty, unit = unit, duration = dur, link = link,
        deposit = FT.Sell.Deposit(kind, e.id, loc, dur, qty), warnings = warnings, severe = severe,
    })
end

-- a posting started, done or cancelled: the Post button follows
FT.On("FT_SELL_STATE", function() if form and form:IsVisible() then T.UpdateSummary() end end)
-- the carry list changed: what you brought shows
FT.On("FT_CARRY_CHANGED", function()
    if page and page:IsVisible() and state.view ~= "owned" then
        T.RefreshList()
        T.ShowForm(true)
    end
end)

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
function T.Build(p)
    page = p
    BuildList(p)
    center = CreateFrame("Frame", nil, p)
    BuildForm(center)
    form:SetAllPoints(center)
    T.BuildOwnedForm(center)
    oform:SetAllPoints(center)
    oform:Hide()
    book = UI.OrderBook(p)
    book:SetPoint("TOPRIGHT", -8, -8)
    book:SetPoint("BOTTOMRIGHT", -8, 8)
    book:SetWidth(RIGHT_W)
    T.OnLayout()
end

-- the compact window: no order book on the side
function T.OnLayout()
    if not page then return end
    local compact = FT.Compact()
    book:SetShown(not compact)
    center:ClearAllPoints()
    center:SetPoint("TOPLEFT", LEFT_W + 18, -8)
    center:SetPoint("BOTTOMRIGHT", compact and -8 or -(RIGHT_W + 18), 8)
end

function T.Select(key)
    state.key = key
    if list then list:Refresh() end
    T.ShowForm(false)
    local e = Current()
    if e then
        FT.Hist.Viewed(e.id)
        FT.Scanner.LiveNow(e.id)
    end
end

function T.Refresh()
    T.RefreshList()
    if state.key and not Current() then state.key = nil end
    T.ShowForm(true)
end

T.OnShow = T.Refresh

-- open an item to sell (from elsewhere): the Selling page with it chosen
function FT.OpenSell(itemID)
    FT.Show("sell")
    for _, e in ipairs(entries) do
        if e.id == itemID then
            T.Select(KeyOf(e))
            return
        end
    end
end

-- kept live at the auction house: the item you are posting (or the auction you look at)
function T.LiveItem()
    if state.view == "owned" then
        local a = oform and oform:IsVisible() and T.CurrentOwned()
        return a and a.itemID or nil
    end
    local e = form and form:IsVisible() and Current()
    return e and e.id or nil
end

-- a live price (id), or the auction house opened or closed (nil)
function T.OnLive(_, id)
    if state.view == "owned" then
        if olist then olist:Refresh() end
        local a = T.CurrentOwned()
        if a and (id == nil or id == a.itemID) then T.ShowOwned() end
        return
    end
    local e = Current()
    if list then list:Refresh() end
    if e and (id == nil or id == e.id) then
        Facts(e)
        if state.auto then T.SetPrice(nil) end
        book:SetItem(e.id)
        T.UpdateSummary()
    end
end

function T.OnItems()
    if list then list:Refresh() end
    if olist then olist:Refresh() end
end

---------------------------------------------------------------------------
-- My auctions
---------------------------------------------------------------------------
local BANDS = { [0] = "under 30 min", [1] = "30 min - 2 h", [2] = "2 - 8 h", [3] = "8 - 24 h" }

-- how long it has left: the seconds when the server tells them (counted on from when it was read), else a band
local function TimeLeft(a, readAt)
    if a.sold then return FT.C("up", L["sold"]) end
    if a.seconds and a.seconds > 0 then
        -- counted from when it was read (or posted, for one added at once)
        local from = a.at or readAt
        local left = a.seconds - (from and (time() - from) or 0)
        if left <= 0 then return FT.C("dim", L["ended?"]) end
        local h, m = math.floor(left / 3600), math.floor(left % 3600 / 60)
        if h > 0 then return string.format(L["%dh %dm"], h, m) end
        return string.format(L["%dm"], m)
    end
    local band = a.timeLeft and BANDS[a.timeLeft]
    return band and L[band] or FT.C("dim", "—")
end

function T.CurrentOwned()
    local items = FT.Owned.List()
    for _, a in ipairs(items) do
        if a.auctionID == state.okey then return a end
    end
    return nil
end

local function OwnedRows()
    local items, readAt = FT.Owned.List()
    local out, value, under = {}, 0, 0
    local search = state.search ~= "" and FT.Fold(state.search) or nil
    for _, a in ipairs(items) do
        a.low = FT.Owned.Undercut(a)
        if a.low then under = under + 1 end
        if a.unit and not a.sold then value = value + a.unit * a.qty end
        local name = FT.Name(a.itemID)
        if not search or (name and FT.Fold(name):find(search, 1, true)) then out[#out + 1] = a end
    end
    -- undercut first, then the most valuable
    table.sort(out, function(x, y)
        if (x.low ~= nil) ~= (y.low ~= nil) then return x.low ~= nil end
        local vx, vy = (x.unit or 0) * x.qty, (y.unit or 0) * y.qty
        if vx ~= vy then return vx > vy end
        return (x.auctionID or 0) < (y.auctionID or 0)
    end)
    return out, value, under, readAt
end

function T.BuildOwnedList(panel)
    local cols = {
        { key = "name", title = L["Item"], width = "fill", make = NameCell, cellHeight = 24 },
        { key = "price", title = L["Yours"], width = 66, justify = "RIGHT" },
        { key = "low", title = L["Lowest"], width = 66, justify = "RIGHT" },
        { key = "time", title = L["Left"], width = 62, justify = "RIGHT", size = 11 },
    }
    ownHeader = UI.Header(panel, cols)
    ownHeader:SetPoint("TOPLEFT", 1, -70)
    ownHeader:SetPoint("TOPRIGHT", -1, -70)
    olist = UI.List(panel, {
        rowHeight = 26,
        cols = cols,
        liveID = function(a) return a.itemID end,
        update = function(row, a)
            local c = row.cells.name
            c.icon:SetItem(a.itemID)
            c.text:SetText(FT.ItemText(a.itemID) .. (a.qty > 1 and FT.C("dim", " x" .. FT.Num(a.qty)) or ""))
            row.cells.price:SetText(a.unit and FT.Money(a.unit, "short") or FT.C("dim", "—"))
            if a.sold then
                row.cells.low:SetText("")
            elseif a.low then
                row.cells.low:SetText(FT.C("down", FT.Money(a.low, "short")))
            else
                local p, _, _, _, gone = FT.Price(a.itemID)
                row.cells.low:SetText(p and not gone and FT.C("up", FT.Money(p, "short")) or FT.C("dim", "—"))
            end
            local _, readAt = FT.Owned.List()
            row.cells.time:SetText(TimeLeft(a, readAt))
        end,
        isSelected = function(a) return a.auctionID == state.okey end,
        onClick = function(a)
            if UI.ItemClick(a.itemID) then return end
            T.SelectOwned(a.auctionID)
        end,
        onEnter = function(row, a)
            UI.TipItem(row, a.itemID)
            GameTooltip:AddLine(" ")
            if a.low then
                GameTooltip:AddLine(string.format(L["Undercut: the lowest is %s, yours %s."], FT.Money(a.low), FT.Money(a.unit)), 0.96, 0.27, 0.36)
                local advice = FT.Owned.Advice(a)
                if advice then GameTooltip:AddLine(advice.text, 0.85, 0.87, 0.9, true) end
            elseif not a.sold then
                GameTooltip:AddLine(L["Yours is the cheapest (as far as is known)."], 0.05, 0.8, 0.5)
            end
            GameTooltip:Show()
        end,
    })
    olist:SetPoint("TOPLEFT", ownHeader, "BOTTOMLEFT", 0, -2)
    olist:SetPoint("BOTTOMRIGHT", -1, 40)

    -- read them again; look at the order books of all of them
    ownButtons = CreateFrame("Frame", nil, panel)
    ownButtons:SetPoint("BOTTOMLEFT", 10, 8)
    ownButtons:SetPoint("BOTTOMRIGHT", -10, 8)
    ownButtons:SetHeight(24)
    ownButtons.refresh = UI.Button(ownButtons, L["Refresh"], 10, 24, "default", function()
        if not FT.Owned.Query() then FT.Print(FT.House.Why(L["Talk to an auctioneer to see your auctions as they are now."])) end
    end)
    ownButtons.refresh:FitText(24)
    ownButtons.refresh:SetPoint("LEFT", 0, 0)
    ownButtons.check = UI.Button(ownButtons, L["Check the prices"], 10, 24, "default", function()
        local ids, seen = {}, {}
        for _, a in ipairs((FT.Owned.List())) do
            if not a.sold and not seen[a.itemID] then
                seen[a.itemID] = true
                ids[#ids + 1] = a.itemID
            end
        end
        if #ids > 0 then FT.Scanner.StartMine(false, ids) end
    end)
    ownButtons.check:FitText(24)
    ownButtons.check:SetPoint("LEFT", ownButtons.refresh, "RIGHT", 6, 0)
    ownButtons.check:SetTip(L["Check the prices"], L["Reads the order book of every item you have up: who undercut you, now. One search each."])

    ownHeader:Hide()
    olist:Hide()
    ownButtons:Hide()
end

function T.RefreshOwned()
    local rows, value, under, readAt = OwnedRows()
    olist:SetEmptyText(state.search ~= "" and L["Nothing matches"] or L["No auctions of yours known. Post something, or open the auction house."])
    olist:SetItems(rows, true)
    local parts = {}
    if #rows > 0 then parts[#parts + 1] = string.format(L["%d up, worth %s"], #rows, FT.Money(value, "short")) end
    if under > 0 then parts[#parts + 1] = FT.C("down", string.format(L["%d undercut"], under)) end
    if readAt and not FT.ahOpen then parts[#parts + 1] = string.format(L["as of %s"], FT.Ago(readAt)) end
    totalText:SetText(table.concat(parts, "  ||  "))
    if state.okey and not T.CurrentOwned() then state.okey = nil end
end

-- the view on the left (and the form in the middle that goes with it)
function T.SetView(view)
    state.view = view
    viewSeg:SetValue(view)
    local owned = view == "owned"
    bagsHeader:SetShown(not owned)
    list:SetShown(not owned)
    ownHeader:SetShown(owned)
    olist:SetShown(owned)
    ownButtons:SetShown(owned)
    if owned then FT.Owned.Query() end
    T.RefreshList()
    T.ShowForm(true)
end

function T.SelectOwned(auctionID)
    state.okey = auctionID
    if olist then olist:Refresh() end
    T.ShowOwned()
    local a = T.CurrentOwned()
    if a then
        FT.Hist.Viewed(a.itemID)
        FT.Scanner.LiveNow(a.itemID)
    end
end

function T.BuildOwnedForm(p)
    local f = UI.Panel(p, "bg1", "line")
    oform = f
    f.icon = UI.Icon(f, 40)
    f.icon:SetPoint("TOPLEFT", 16, -14)
    f.icon:EnableMouse(true)
    f.icon:SetScript("OnEnter", function(self)
        local a = T.CurrentOwned()
        if a then UI.TipItem(self, a.itemID) end
    end)
    f.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.name = UI.Text(f, 16, "text")
    f.name:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 10, -2)
    f.name:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    f.sub = UI.Text(f, 11, "dim")
    f.sub:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -6)
    f.sub:SetPoint("RIGHT", f, "RIGHT", -16, 0)

    f.yours = Fact(f, L["Your price"])
    f.low = Fact(f, L["Cheapest listed"])
    f.fair = Fact(f, L["Fair price"])
    f.verdict = UI.Text(f, 13, "text")
    f.verdict:SetPoint("TOPLEFT", 16, -150)
    f.verdict:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    f.advice = UI.Text(f, 11, "muted")
    f.advice:SetPoint("TOPLEFT", f.verdict, "BOTTOMLEFT", 0, -8)
    f.advice:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    if f.advice.SetWordWrap then f.advice:SetWordWrap(true) end
    f.advice:SetJustifyV("TOP")
    f.advice:SetHeight(48)

    f.cancel = UI.Button(f, L["Cancel the auction"], 10, 30, "down", function()
        local a = T.CurrentOwned()
        if a then FT.Owned.Cancel(a) end
    end)
    f.cancel.label:SetFont(UI.FONT, 13, "")
    f.cancel:FitText(36)
    f.cancel:SetPoint("BOTTOMRIGHT", -16, 16)
    -- undercut: take it off to post it again under the lowest (back from the mail, the Sell page has it first)
    f.repost = UI.Button(f, L["Take off to post cheaper"], 10, 30, "primary", function()
        local a = T.CurrentOwned()
        if a then FT.Owned.CancelToRepost(a) end
    end)
    f.repost.label:SetFont(UI.FONT, 13, "")
    f.repost:FitText(36)
    f.repost:SetPoint("BOTTOMRIGHT", f.cancel, "TOPRIGHT", 0, 8)
    f.repost:SetTip(L["Take off to post cheaper"], L["The auction is taken off (the deposit is lost) and the item comes back by mail; back in your bags, the Sell page has it first, at a copper under the lowest. Posting again needs your click there."])
    f.hint = UI.Text(f, 10, "dim")
    f.hint:SetPoint("BOTTOMLEFT", 16, 24)
    f.hint:SetPoint("RIGHT", f.cancel, "LEFT", -12, 0)
    f.hint:SetText(L["It comes back by mail; the deposit isn't returned."])

    UI.OnSize(f, function(self, w)
        local cw = math.floor((w - 32) / 3)
        for i, c in ipairs({ self.yours, self.low, self.fair }) do
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", 16 + (i - 1) * cw, -80)
            c:Fit(cw - 8)
        end
    end)
    f.empty = UI.EmptyState(f, L["Pick an auction"], L["Your auctions are on the left: undercut ones first."])
    f.empty:SetPoint("CENTER")
end

-- the auction chosen: your price against the market, and what to do
function T.ShowOwned()
    local f = oform
    if not f then return end
    local a = T.CurrentOwned()
    local show = a ~= nil
    for _, r in ipairs({ f.icon, f.name, f.sub, f.yours, f.low, f.fair, f.verdict, f.advice, f.cancel, f.hint }) do r:SetShown(show) end
    f.repost:Hide()
    f.empty:SetShown(not show)
    if not a then
        book:SetItem(nil)
        return
    end
    local _, readAt, live = FT.Owned.List()
    f.icon:SetItem(a.itemID)
    f.name:SetText((a.link or FT.ItemText(a.itemID, 40)) .. (a.qty > 1 and FT.C("dim", " x" .. FT.Num(a.qty)) or ""))
    local parts = { a.sold and FT.C("up", L["sold: the gold comes by mail"]) or (L["left"] .. ": " .. TimeLeft(a, readAt)) }
    if not live and readAt then parts[#parts + 1] = string.format(L["as of %s"], FT.Ago(readAt)) end
    f.sub:SetText(table.concat(parts, FT.C("dim", "  ||  ")))

    f.yours.value:SetText(a.unit and FT.Money(a.unit, "short") or "—")
    f.yours.sub:SetText(a.unit and a.qty > 1 and string.format(L["all: %s"], FT.Money(a.unit * a.qty, "short")) or "")
    local p, t, _, listed, gone = FT.Price(a.itemID)
    if p and not gone then
        f.low.value:SetText(a.low and FT.C("down", FT.Money(p, "short")) or FT.Money(p, "short"))
        local bits = {}
        if listed then bits[#bits + 1] = FT.Num(listed) .. " " .. L["pcs"] end
        if t then bits[#bits + 1] = FT.Ago(t) end
        f.low.sub:SetText(table.concat(bits, "  ||  "))
    else
        f.low.value:SetText(FT.C("dim", "—"))
        f.low.sub:SetText("")
    end
    local s = FT.An.Stats(a.itemID)
    f.fair.value:SetText(s.fair and FT.Money(s.fair, "short") or FT.C("dim", "—"))
    f.fair.sub:SetText(s.fair and L["of the last days"] or "")

    -- what it means
    if a.sold then
        f.verdict:SetText(FT.C("up", L["Sold."]))
        f.advice:SetText("")
    elseif a.low then
        f.verdict:SetText(FT.C("down", string.format(L["Undercut by %s (%s)."], FT.Money(a.unit - a.low, "short"), FT.Pct(a.low / a.unit - 1, true))))
        -- wait or post again: what is under yours against what sells in the time yours has left
        local advice = FT.Owned.Advice(a)
        local color = advice and ((advice.kind == "repost" and "down") or (advice.kind == "wait" and "up") or "muted") or "muted"
        f.advice:SetText(advice and FT.C(color, advice.text) or "")
        f.repost:SetShown(advice ~= nil and advice.kind ~= "low")
        f.repost:SetUsable(FT.Owned.Possible() and not FT.Owned.Blocked())
    elseif p and not gone then
        f.verdict:SetText(FT.C("up", L["Yours is the cheapest."]))
        f.advice:SetText(t and time() - t > 1800 and string.format(L["As of %s: Check the prices for now."], FT.Ago(t)) or "")
    else
        f.verdict:SetText(FT.C("dim", L["No market price known."]))
        f.advice:SetText(L["Check the prices: one search for each of your items."])
    end
    f.cancel:SetUsable(FT.Owned.Possible() and not a.sold)
    f.cancel:SetLabel(FT.Owned.Blocked() and L["Cancel in the game's window"] or L["Cancel the auction"])
    f.cancel:FitText(36)
    if not FT.Owned.Possible() then
        f.cancel:SetTip(L["Cancel the auction"], FT.House.Why(L["Talk to an auctioneer to cancel."]))
    elseif FT.Owned.Blocked() then
        f.cancel:SetTip(L["Cancel in the game's window"], L["WoW Forever lets only its own auction house window cancel auctions: open its Auctions tab and cancel there."])
    else
        f.cancel:SetTip(nil)
    end
    book:SetItem(a.itemID)
end

-- the bags changed (posted, bought, looted): the page follows at once
FT.On("BAG_UPDATE_DELAYED", function()
    if page and page:IsVisible() and state.view ~= "owned" then
        T.RefreshList()
        if state.key and not Current() then state.key = nil end
        T.ShowForm(true)
    end
end)

-- your auctions read again: the view follows
FT.On("FT_OWNED_CHANGED", function()
    if page and page:IsVisible() and state.view == "owned" then
        T.RefreshOwned()
        T.ShowOwned()
    elseif page and page:IsVisible() then
        -- an item taken off to post again: its mark in the bags follows
        T.RefreshList()
    end
end)

-- an auction of yours from elsewhere (the Signals page): My auctions with it chosen
function T.OpenOwned(auctionID)
    if state.view ~= "owned" then T.SetView("owned") end
    T.SelectOwned(auctionID)
end
