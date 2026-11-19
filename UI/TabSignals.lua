-- ForeverTrading: Signals page - what to do now, in four columns: sell, craft, buy, hold / avoid.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local T = {}
FT.Tabs.signals = T

local cols = {}

-- a row of a list: icon, name over a reason, the value top right, a badge under it
local function RowSetup(row)
    row.icon = UI.Icon(row, 26)
    row.icon:SetPoint("LEFT", 10, 0)
    row.name = UI.Text(row, 12, "text")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 1)
    row.name:SetPoint("RIGHT", row, "RIGHT", -100, 0)
    row.reason = UI.Text(row, 11, "dim")
    row.reason:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, -1)
    row.reason:SetPoint("RIGHT", row, "RIGHT", -100, 0)
    row.value = UI.Text(row, 12, "text", "RIGHT")
    row.value:SetPoint("TOPRIGHT", -10, -6)
    row.badge = UI.Badge(row, 84, 16)
    row.badge:SetPoint("BOTTOMRIGHT", -10, 5)
    row.line = UI.HLine(row, "line", 0.6)
    row.line:SetPoint("BOTTOMLEFT", 10, 0)
    row.line:SetPoint("BOTTOMRIGHT", -10, 0)
end

local function Column(parent, title, sub)
    local c = UI.Panel(parent, "bg1", "line")
    c.title = UI.Text(c, 13, "text")
    c.title:SetPoint("TOPLEFT", 12, -10)
    c.title:SetText(title)
    c.count = UI.Text(c, 11, "dim", "RIGHT")
    c.count:SetPoint("TOPRIGHT", -12, -12)
    c.sub = UI.Text(c, 11, "dim")
    c.sub:SetPoint("TOPLEFT", 12, -28)
    c.sub:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    c.sub:SetText(sub)
    c.accent = UI.RoundTex(c, "ARTWORK", "accent", 1, nil, "top", UI.RADIUS - 1)
    c.accent:SetHeight(2)
    c.accent:SetPoint("TOPLEFT", 1, -1)
    c.accent:SetPoint("TOPRIGHT", -1, -1)
    c.list = UI.List(c, {
        rowHeight = 42,
        setup = RowSetup,
        update = function(row, x)
            row.icon:SetItem(x.id)
            row.name:SetText(FT.ItemText(x.id, 30))
            row.reason:SetText(x.reason or "")
            row.value:SetText(x.value or "")
            row.badge:Set(x.signal, nil, x.strength)
        end,
        onClick = function(x)
            if UI.ItemClick(x.id) then return end
            if x.auction then
                -- your auction someone undercut: My auctions with it chosen
                FT.Show("sell")
                FT.Tabs.sell.OpenOwned(x.auction)
            elseif x.recipe then
                FT.OpenRecipe(x.recipe)
            else
                FT.OpenItem(x.id)
            end
        end,
        onEnter = function(row, x)
            UI.TipItem(row, x.id)
            if x.tip then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(x.tip, 0.85, 0.87, 0.9, true)
                GameTooltip:Show()
            end
        end,
    })
    c.list:SetPoint("TOPLEFT", 1, -48)
    c.list:SetPoint("BOTTOMRIGHT", -1, 4)
    return c
end

---------------------------------------------------------------------------
-- What goes in each column
---------------------------------------------------------------------------
local function Collect()
    local sell, craft, buy, hold = {}, {}, {}, {}
    local judged, early = 0, 0 -- items with a sell / buy signal, and those without enough history for one

    -- what you own
    local rows = FT.Port.Rows()
    for _, h in ipairs(rows) do
        judged = judged + 1
        if h.signal == "NODATA" then early = early + 1 end
        if h.signal == "SELL" then
            sell[#sell + 1] = { id = h.id, signal = "SELL", strength = h.strength, reason = h.reason,
                value = FT.Num(h.qty) .. FT.C("dim", " x ") .. FT.Money(h.price, "short"), sortV = h.value * h.strength,
                tip = string.format(L["You have %s: worth %s"], FT.Num(h.qty), FT.Money(h.value)) }
        elseif h.signal == "HOLD" then
            hold[#hold + 1] = { id = h.id, signal = "HOLD", strength = h.strength, reason = h.reason,
                value = FT.Num(h.qty) .. FT.C("dim", " x ") .. FT.Money(h.price, "short"), sortV = h.value }
        end
    end

    -- your auctions someone undercut (this visit's list, or the last one read), with what to do: on top
    local ADVICE = { repost = L["post again"], wait = L["wait"], low = L["not worth following"], check = L["check the prices"] }
    for _, a in ipairs((FT.Owned.List())) do
        local low = (not a.sold) and FT.Owned.Undercut(a)
        if low then
            local advice = FT.Owned.Advice(a)
            local yours = math.ceil(a.unit)
            sell[#sell + 1] = { id = a.itemID, auction = a.auctionID, signal = "UNDERCUT",
                strength = (advice and advice.kind == "repost") and 3 or 2,
                reason = string.format(L["yours %s, now %s"], FT.Money(yours, "short"), FT.Money(low, "short"))
                    .. (advice and ("  ||  " .. FT.C(advice.kind == "repost" and "down" or "text", ADVICE[advice.kind])) or ""),
                value = FT.C("down", "-" .. FT.Money(yours - low, "short")), sortV = 1e15 + yours * a.qty,
                tip = advice and advice.text }
        end
    end

    -- your recipes
    local materials = {}
    for _, r in ipairs(FT.Craft.List()) do
        local e = FT.Craft.Eval(r)
        if e.signal == "CRAFT" then
            local reason = e.reason
            if e.sell == "SELL" then reason = reason .. "  ||  " .. FT.C("up", L["price is high now"]) end
            craft[#craft + 1] = { id = r.output, recipe = r.key, signal = "CRAFT", strength = e.strength, reason = reason,
                value = FT.C("up", "+" .. FT.Money(e.profit, "short")), sortV = e.profit * (e.sell == "SELL" and 1.5 or 1),
                tip = FT.Craft.KnownByText(r) }
        elseif e.signal == "AVOID" then
            hold[#hold + 1] = { id = r.output, recipe = r.key, signal = "AVOID", strength = e.strength, reason = e.reason,
                value = FT.C("down", FT.Money(e.profit, "short")), sortV = -e.profit * 0.5 }
        elseif e.signal == "RISKY" then
            -- a profit on paper the market may not keep: falling, flooded, more sellers, rarely bought
            local known = FT.Craft.KnownByText(r)
            hold[#hold + 1] = { id = r.output, recipe = r.key, signal = "RISKY", strength = e.strength, reason = e.reason,
                value = FT.C("accent", "+" .. FT.Money(e.profit, "short")), sortV = e.profit,
                tip = e.reason .. (known ~= "" and ("\n" .. known) or "") }
        end
        for _, rg in ipairs(r.reagents) do materials[rg.itemID] = true end
    end

    -- materials of your recipes and your watchlist on a dip
    for id in pairs(FT.db.watch) do materials[id] = true end
    for id in pairs(materials) do
        local s = FT.An.Stats(id)
        local signal, strength, reason = FT.An.BuySignal(s)
        judged = judged + 1
        if signal == "NODATA" then early = early + 1 end
        if signal == "BUY" then
            buy[#buy + 1] = { id = id, signal = "BUY", strength = strength, reason = reason,
                value = FT.Money(s.price, "short"), sortV = -(s.dev or 0) * 100 + (strength or 0) }
        end
    end

    local function Sort(t) table.sort(t, function(a, b) return (a.sortV or 0) > (b.sortV or 0) end) end
    Sort(sell); Sort(craft); Sort(buy); Sort(hold)
    return sell, craft, buy, hold, judged > 0 and early >= judged * 0.8
end

---------------------------------------------------------------------------
-- Good deals (FT.Deals): what to buy right now for a profit
---------------------------------------------------------------------------
local dealsView
local dstate = { kind = "all", age = 21600 }
local DEALS_HINT
local MAX_CHECK = 60 -- items "Check order books" searches at most

local function Money(v)
    return FT.Money(math.floor(v + 0.5), "short")
end

local function DealText(d)
    local text
    if d.kind == "HOUSES" then
        local H = FT.House
        text = string.format(L["%s each at %s, %s at %s: +%s each after its cut"], Money(d.unit), H.Name(d.buyHouse),
            Money(d.target), H.Name(d.sellHouse), Money(d.perUnit))
        local qty = d.noBook and L["the cheapest lot"] or string.format(L["%s pcs"], FT.Num(d.qty))
        local sells = d.sales and ("  ||  " .. L["sells there"] .. " " .. FT.Sales.PerDayText(d.sales)) or ""
        local ages = string.format(L["here %s, there %s"], FT.Ago(d.buyHouse == FT.house and d.t or d.sellT),
            FT.Ago(d.buyHouse == FT.house and d.sellT or d.t))
        return text .. FT.C("dim", "  ||  " .. qty .. sells .. "  ||  " .. ages)
    elseif d.kind == "VENDOR" then
        text = string.format(L["%s each, a vendor pays %s: +%s each"], Money(d.unit), Money(d.target), Money(d.perUnit))
    else
        text = string.format(L["%s each, fair ~%s: list at %s, +%s each after the cut"], Money(d.unit), Money(d.fair),
            Money(d.target), Money(d.perUnit))
    end
    local qty = d.noBook and L["the cheapest lot"] or string.format(L["%s pcs"], FT.Num(d.qty))
    -- reselling: how much really sells, when seen
    local sells = d.sales and ("  ||  " .. L["sells"] .. " " .. FT.Sales.PerDayText(d.sales)) or ""
    return text .. FT.C("dim", "  ||  " .. qty .. sells .. "  ||  " .. FT.Ago(d.t))
end

local function DealTip(row, d)
    UI.TipItem(row, d.id)
    local qty = d.noBook and L["the cheapest lot"] or string.format(L["%s pcs"], FT.Num(d.qty))
    GameTooltip:AddLine(" ")
    if d.kind == "HOUSES" then
        local H = FT.House
        GameTooltip:AddLine(string.format(L["Buy at %s: %s for %s (price of %s)"], H.Name(d.buyHouse), qty, Money(d.cost),
            FT.Ago(d.t)), 0.85, 0.87, 0.9, true)
        GameTooltip:AddLine(string.format(L["Carry it to %s and list it at %s each: its cut there is %s (the deposit comes back when it sells; unsold, it is lost)."],
            H.Name(d.sellHouse), Money(d.target), string.format("%.0f%%", (d.cut or 0) * 100)), 0.85, 0.87, 0.9, true)
        local there = {}
        if d.there then there[#there + 1] = string.format(L["listed there: %s"], FT.Num(d.there)) end
        if d.usual then there[#there + 1] = string.format(L["usual there: %s"], Money(d.usual)) end
        if d.sales then there[#there + 1] = L["sells there"] .. " " .. FT.Sales.PerDayText(d.sales) end
        there[#there + 1] = string.format(L["price there: %s"], FT.Ago(d.sellT))
        GameTooltip:AddLine(table.concat(there, ", "), 0.6, 0.62, 0.66, true)
        if d.cheap and d.cheap > d.qty then
            GameTooltip:AddLine(string.format(L["%s pcs are this cheap: no more than %s - more doesn't sell there in two days."],
                FT.Num(d.cheap), FT.Num(d.qty)), 0.95, 0.75, 0.3, true)
        end
        if d.thin then
            GameTooltip:AddLine(L["Fewer than 3 days of prices there: look at its order book before buying much."], 0.95, 0.75, 0.3, true)
        end
        GameTooltip:AddLine(string.format(L["Profit: %s"], Money(d.profit)), 0.4, 0.85, 0.5, true)
        if d.noBook then
            GameTooltip:AddLine(L["Only the cheapest lot is sure: open the item (or Check order books) for its whole order book."], 0.6, 0.62, 0.66, true)
        end
        GameTooltip:AddLine(L["Click: the item with its order book - buy there."], 0.6, 0.62, 0.66, true)
        GameTooltip:Show()
        return
    end
    GameTooltip:AddLine(string.format(L["Buy: %s for %s"], qty, Money(d.cost)), 0.85, 0.87, 0.9, true)
    if d.kind == "VENDOR" then
        GameTooltip:AddLine(string.format(L["Sell them to a vendor for %s each: no cut, no waiting."], Money(d.target)), 0.85, 0.87, 0.9, true)
    else
        GameTooltip:AddLine(string.format(L["List them again at %s each (the auction house's cut is counted; the deposit comes back when they sell)."],
            Money(d.target)), 0.85, 0.87, 0.9, true)
    end
    GameTooltip:AddLine(string.format(L["Profit: %s"], Money(d.profit)), 0.4, 0.85, 0.5, true)
    if d.noBook then
        GameTooltip:AddLine(L["Only the cheapest lot is sure: open the item (or Check order books) for its whole order book."], 0.6, 0.62, 0.66, true)
    end
    GameTooltip:AddLine(L["Click: the item with its order book - buy there."], 0.6, 0.62, 0.66, true)
    GameTooltip:Show()
end

local function BuildDeals(p)
    local f = CreateFrame("Frame", nil, p)
    f:SetPoint("TOPLEFT", 8, -56)
    f:SetPoint("BOTTOMRIGHT", -8, 8)
    f:Hide()
    f.kind = UI.Segmented(f, { { "all", L["All"] }, { "VENDOR", L["To a vendor"] }, { "RESELL", L["Resell"] },
        { "HOUSES", L["Between houses"] } }, function(v)
        dstate.kind = v
        T.RefreshDeals()
    end, 22)
    f.kind:SetPoint("TOPLEFT", 0, -1)
    f.kind:SetValue(dstate.kind)
    f.ageLabel = UI.Text(f, 11, "dim")
    f.ageLabel:SetPoint("LEFT", f.kind, "RIGHT", 18, 0)
    f.ageLabel:SetText(L["Prices not older than"])
    f.age = UI.Segmented(f, { { 3600, L["1 h"] }, { 21600, L["6 h"] }, { 86400, L["24 h"] } }, function(v)
        dstate.age = v
        T.RefreshDeals()
    end, 22)
    f.age:SetPoint("LEFT", f.ageLabel, "RIGHT", 6, 0)
    f.age:SetValue(dstate.age)
    f.check = UI.Button(f, L["Check order books"], 10, 24, "default", function() T.CheckBooks() end)
    f.check:FitText(24)
    f.check:SetPoint("TOPRIGHT", 0, 0)
    f.check:SetTip(L["Check order books"], L["Searches the auction house for the deals seen without an order book: how many cheap lots there really are (one search each, like My items)."])
    f.count = UI.Text(f, 11, "dim", "RIGHT")
    f.count:SetPoint("RIGHT", f.check, "LEFT", -12, 0)
    f.hint = UI.Text(f, 11, "dim")
    f.hint:SetPoint("TOPLEFT", 0, -32)
    f.hint:SetPoint("RIGHT", 0, 0)
    if f.hint.SetWordWrap then f.hint:SetWordWrap(false) end
    DEALS_HINT = L["To a vendor: a sure profit. Resell: the cheap lots of a steady market, listed again near the fair price. Between houses: cheaper at one auction house than the other sells it for."]
    f.hint:SetText(DEALS_HINT)
    local box = UI.Panel(f, "bg1", "line")
    box:SetPoint("TOPLEFT", 0, -50)
    box:SetPoint("BOTTOMRIGHT", 0, 0)
    f.list = UI.List(box, {
        rowHeight = 42,
        setup = RowSetup,
        update = function(row, d)
            row.icon:SetItem(d.id)
            row.name:SetText(FT.ItemText(d.id, 40))
            row.reason:SetText(DealText(d))
            row.value:SetText(FT.C("up", "+" .. Money(d.profit)))
            row.badge:Set(d.kind, nil, d.noBook and 1 or 3)
        end,
        onClick = function(d)
            if UI.ItemClick(d.id) then return end
            FT.ShowDetail(d.id)
        end,
        onEnter = DealTip,
    })
    f.list:SetPoint("TOPLEFT", 1, -2)
    f.list:SetPoint("BOTTOMRIGHT", -1, 2)
    if f.list.empty then f.list.empty:SetWidth(460) end
    return f
end

-- the deals that pass the view's choices and the search (and how many only their prices' age hides)
local function ShownDeals()
    local list, _, building = FT.Deals.List()
    local matches = FT.NameMatcher(T.search)
    local since = time() - dstate.age
    local out, noBook, total, older = {}, {}, 0, 0
    for _, d in ipairs(list) do
        if (dstate.kind == "all" or d.kind == dstate.kind) and (not matches or matches(d.id)) then
            if d.t >= since then
                out[#out + 1] = d
                total = total + d.profit
                -- only the house open here can be searched (between the houses: the one it is bought at)
                if d.noBook and (d.kind ~= "HOUSES" or d.buyHouse == FT.house) then noBook[#noBook + 1] = d.id end
            else
                older = older + 1
            end
        end
    end
    return out, total, noBook, building, older
end

-- no deals on the page: why (no prices yet, old prices, vendor prices still coming, too little history, the
-- minimum profit)
local function WhyNoDeals(older)
    if T.search ~= "" then return L["Nothing matches"] end
    local info = FT.Deals.Info()
    if info and info.items == 0 then
        return L["No prices yet: deals are looked for in the auction house's prices - scan it at the auction house."]
    end
    local why = { L["No good deals right now."] }
    if older > 0 then
        why[#why + 1] = string.format(L["%d more with older prices: choose 24 h, or scan the auction house again."], older)
    elseif info and info.newest and info.newest < time() - dstate.age then
        why[#why + 1] = string.format(L["Newest prices: %s - scan the auction house again."], FT.Ago(info.newest))
    end
    if FT.Deals.Loading() > 0 then
        why[#why + 1] = L["Vendor prices are still loading: deals to a vendor follow."]
    end
    if info and info.history == 0 and (dstate.kind == "all" or dstate.kind == "RESELL") then
        why[#why + 1] = L["Reselling needs at least 3 days of prices: a full scan every day."]
    end
    if dstate.kind == "all" or dstate.kind == "HOUSES" then
        local other = FT.House.IsNeutral() and "faction" or "neutral"
        local seen = FT.Hist.MarketTimeIn(other)
        if not seen then
            why[#why + 1] = string.format(L["No prices of %s yet: scan there once - deals between the houses compare both."], FT.House.Name(other))
        elseif time() - seen > 3 * 86400 then
            why[#why + 1] = string.format(L["The prices of %s are from %s: deals between the houses take them up to 3 days old."],
                FT.House.Name(other), FT.Ago(seen))
        end
    end
    if info and info.small > 0 and (FT.S.dealMin or 0) > 0 then
        why[#why + 1] = string.format(L["%d smaller ones (under %s profit) are hidden: Settings > Signals."], info.small,
            Money(FT.S.dealMin))
    end
    if #why == 1 then
        return L["No good deals right now. They are looked for in the latest prices: scan the auction house, or open items while it is open."]
    end
    return table.concat(why, "\n\n")
end

function T.RefreshDeals()
    local f = dealsView
    if not (f and f:IsShown()) then return end
    local shown, total, noBook, building, older = ShownDeals()
    f.list:SetEmptyText((building and #shown == 0) and L["Looking for deals..."] or WhyNoDeals(older))
    -- vendor prices still coming: said in place of the hint
    local left = FT.Deals.Loading()
    f.hint:SetText(left > 0 and string.format(L["Loading vendor prices: %s items left - deals to a vendor follow as they come."],
        FT.Num(left)) or DEALS_HINT)
    f.list:SetItems(shown, true)
    if #shown > 0 then
        f.count:SetText(string.format(L["%d deals, +%s in all"], #shown, Money(total)))
    else
        f.count:SetText(building and L["Looking for deals..."] or "")
    end
    f.check:SetUsable(#noBook > 0 and FT.ahOpen == true)
    f.check:SetLabel(#noBook > 0 and string.format(L["Check order books (%d)"], math.min(#noBook, MAX_CHECK)) or L["Check order books"])
    f.check:FitText(24)
end

-- the deals seen without an order book: searched one by one (best first), the deals follow
function T.CheckBooks()
    local _, _, noBook = ShownDeals()
    if #noBook == 0 then return end
    if not FT.ahOpen then
        FT.Print(FT.House.Why(L["Talk to an auctioneer to check the order books."]))
        return
    end
    while #noBook > MAX_CHECK do table.remove(noBook) end
    FT.Scanner.StartMine(false, noBook)
end

-- one kind of deals on the page (What's new opens it)
function T.SetDealKind(kind)
    dstate.kind = kind
    if dealsView then dealsView.kind:SetValue(kind) end
    T.RefreshDeals()
end

function T.SetView(view)
    T.view = view
    if T.viewSeg then T.viewSeg:SetValue(view) end
    local deals = view == "deals"
    for _, c in ipairs(cols) do c:SetShown(not deals) end
    if dealsView then dealsView:SetShown(deals) end
    T.Refresh()
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
function T.Build(p)
    local head = CreateFrame("Frame", nil, p)
    head:SetPoint("TOPLEFT", 8, -8)
    head:SetPoint("TOPRIGHT", -8, -8)
    head:SetHeight(40)
    T.title = UI.Text(head, 16, "text")
    T.title:SetPoint("TOPLEFT", 4, -2)
    T.title:SetText(L["Signals"])
    T.rules = UI.Text(head, 11, "dim")
    T.rules:SetPoint("TOPLEFT", 4, -24)
    T.rules:SetPoint("RIGHT", head, "RIGHT", -150, 0)
    local tune = UI.Button(head, L["Thresholds"], 10, 24, "default", function() FT.SelectTab("settings") end)
    tune:FitText(24)
    tune:SetPoint("RIGHT", 0, 0)
    -- the search, next to the title: every column keeps only what matches ("name" in quotes: that name exactly)
    T.search = ""
    T.searchBox = UI.Input(head, 220, 22, L["Search item..."], function(text)
        T.search = text or ""
        FT.Debounce("signalsSearch", 0.25, T.Refresh)
    end)
    T.searchBox:SetPoint("LEFT", T.title, "RIGHT", 16, 0)
    UI.ClearButton(T.searchBox, function()
        T.search = ""
        T.Refresh()
    end)
    -- the four columns of signals, or the good deals
    T.view = T.view or "signals"
    T.viewSeg = UI.Segmented(head, { { "signals", L["Signals"] }, { "deals", L["Good deals"] } }, function(v) T.SetView(v) end, 22)
    T.viewSeg:SetPoint("LEFT", T.searchBox, "RIGHT", 12, 0)
    T.viewSeg:SetValue(T.view)
    dealsView = BuildDeals(p)
    -- the deals are looked for again on new prices only while they are on the screen
    FT.Deals.watching = function() return dealsView:IsVisible() end

    cols[1] = Column(p, L["Sell now"], L["What you own, priced above its average; your auctions undercut"])
    cols[2] = Column(p, L["Worth crafting"], L["Your recipes with a good profit"])
    cols[3] = Column(p, L["Worth buying"], L["Your materials and watchlist on a dip"])
    cols[4] = Column(p, L["Hold / avoid"], L["Below average - wait; recipes at a loss or at risk"])
    UI.SetTexColor(cols[1].accent, "up")
    UI.SetTexColor(cols[2].accent, "accent")
    UI.SetTexColor(cols[3].accent, "blue")
    UI.SetTexColor(cols[4].accent, "down")
    cols[1].list:SetEmptyText(L["Nothing you own is priced high right now."])
    cols[2].list:SetEmptyText(L["No recipe clears your profit and margin thresholds right now."])
    cols[3].list:SetEmptyText(L["None of your materials is on a dip."])
    cols[4].list:SetEmptyText(L["Nothing to worry about."])

    UI.OnSize(p, function(self, w)
        local cw = (w - 16 - 3 * 8) / 4
        for i, c in ipairs(cols) do
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", 8 + (i - 1) * (cw + 8), -56)
            c:SetPoint("BOTTOM", 0, 8)
            c:SetWidth(cw)
        end
    end)
end

function T.Refresh()
    if T.view == "deals" then
        T.rules:SetText(string.format(L["Deals: resale %d%% or more under the fair price, from %s profit (Settings > Signals)."],
            FT.S.dealBelow or 30, FT.Money(FT.S.dealMin or 0, "short")))
        FT.Deals.Ensure()
        T.RefreshDeals()
        return
    end
    T.rules:SetText(string.format(L["Sell: %d%% above the %d-day average or RSI 70+.  Buy: %d%% below or RSI 30-.  Craft: profit from %s and margin from %d%%."],
        FT.S.sellAbove, FT.S.avgDays, FT.S.buyBelow, FT.Money(FT.S.minProfit, "short"), FT.S.minMargin))
    local sell, craft, buy, hold, tooEarly = Collect()
    -- selling and buying compare today with the days before: without them, say so
    local early = L["Too little price history yet: sell and buy signals need at least 3 days of prices before today. A full scan every day fills it."]
    local empty = {
        tooEarly and early or L["Nothing you own is priced high right now."],
        L["No recipe clears your profit and margin thresholds right now."],
        tooEarly and early or L["None of your materials is on a dip."],
        L["Nothing to worry about."],
    }
    local lists = { sell, craft, buy, hold }
    -- a search: only what matches, in every column
    local matches = FT.NameMatcher(T.search)
    if matches then
        for i, list in ipairs(lists) do
            local kept = {}
            for _, x in ipairs(list) do
                if matches(x.id) then kept[#kept + 1] = x end
            end
            lists[i] = kept
        end
    end
    for i, c in ipairs(cols) do
        c.list:SetEmptyText(matches and L["Nothing matches"] or empty[i])
        c.list:SetItems(lists[i], true)
        c.count:SetText(#lists[i] > 0 and tostring(#lists[i]) or "")
    end
end

T.OnShow = T.Refresh

-- item names and colours arrived: the rows on screen show them (and a search may find more now)
function T.OnItems()
    if T.search and T.search ~= "" then
        FT.Debounce("signalsSearch", 0.5, T.Refresh)
        return
    end
    for _, c in ipairs(cols) do c.list:Refresh() end
    if dealsView and dealsView:IsShown() then
        dealsView.list:Refresh()
        FT.Debounce("dealsHint", 1, T.RefreshDeals)
    end
end

-- the deals were looked for again; the auction house opened or closed (Check order books needs it)
FT.On("FT_DEALS_READY", function() T.RefreshDeals() end)
FT.On("AUCTION_HOUSE_SHOW", function() C_Timer.After(0.5, T.RefreshDeals) end)
FT.On("AUCTION_HOUSE_CLOSED", function() C_Timer.After(0.5, T.RefreshDeals) end)
FT.On("FT_AH_CHANGED", function() C_Timer.After(0.1, T.RefreshDeals) end)
