-- Wolf: the Money page - ways to make gold from the market right now:
--  Make gold (one ranked list: carry it between the houses, flip it, vendor it) and the Farm Board (raw materials by
--  the gold the market pays for them a day). What to do with what you own is Portfolio > Sell yours.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local T = {}
FT.Tabs.signals = T

-- a row of a list: icon, name over a reason, the value top right, a badge under it
local function RowSetup(row)
    row.icon = UI.Icon(row, 26)
    row.icon:SetPoint("LEFT", 10, 0)
    row.name = UI.Text(row, 12, "text")
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 44, -6)
    row.name:SetPoint("RIGHT", row, "RIGHT", -100, 0)
    row.reason = UI.Text(row, 11, "dim")
    row.reason:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 44, 6)
    row.reason:SetPoint("RIGHT", row, "RIGHT", -100, 0)
    row.value = UI.Text(row, 12, "text", "RIGHT")
    row.value:SetPoint("TOPRIGHT", -10, -6)
    row.badge = UI.Badge(row, 84, 16)
    row.badge:SetPoint("BOTTOMRIGHT", -10, 5)
    row.line = UI.HLine(row, "line", 0.6)
    row.line:SetPoint("BOTTOMLEFT", 10, 0)
    row.line:SetPoint("BOTTOMRIGHT", -10, 0)
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

-- how long what you'd buy takes to sell where you'd sell it (nil: not known)
local function SellsIn(d)
    local perDay = d.sales and d.sales.perDay
    if not (perDay and perDay > 0) then return nil end
    local days = (d.qty or 1) / perDay
    if days < 1 then return FT.C("up", L["sells within a day"]) end
    if days <= 3 then return string.format(L["sells in ~%d days"], math.ceil(days)) end
    return FT.C("down", string.format(L["slow: ~%d days to sell"], math.ceil(days)))
end
T.SellsIn = SellsIn

-- what it costs against the gold on this character: fine, a big part of it, or more than you have
local function Budget(d)
    local cost = d.cost or (d.unit and d.unit * (d.qty or 1))
    local money = GetMoney and GetMoney() or 0
    if not cost or money <= 0 then return nil, false end
    if cost > money then return FT.C("down", string.format(L["costs %s: more than you have"], Money(cost))), true end
    if cost > money / 3 then return FT.C("accent", string.format(L["costs %s: over a third of your gold"], Money(cost))), false end
    return FT.C("dim", string.format(L["costs %s"], Money(cost))), false
end
T.Budget = Budget

-- what you'd lose at worst (it doesn't sell and goes at its 30-day low, or to a vendor): "no risk" / "risk 12g"
local function Risk(d)
    if not d.worst then return nil end
    if d.worst <= 0 then return FT.C("up", L["no risk"]) end
    return FT.C(d.worst > (d.profit or 0) and "accent" or "dim", string.format(L["risk %s"], Money(d.worst)))
end

-- one line anyone gets: what to do, the gold, how fast it sells, what it costs you
local function DealText(d)
    local H = FT.House
    local text
    if d.kind == "HOUSES" then
        if d.carried then
            return string.format(L["In your carry list: sell at %s for ~%s"], H.Name(d.sellHouse), Money(d.target))
                .. FT.C("dim", "  ·  " .. string.format(L["since %s"], FT.Ago(d.t)))
        end
        text = string.format(L["Buy at %s for %s, sell at %s for ~%s"], H.Name(d.buyHouse), Money(d.unit), H.Name(d.sellHouse), Money(d.target))
    elseif d.kind == "VENDOR" then
        text = string.format(L["Buy for %s, a vendor pays %s"], Money(d.unit), Money(d.target))
    elseif d.kind == "DE" then
        text = string.format(L["Buy for %s and disenchant it: worth ~%s in its materials"], Money(d.unit), Money(d.target))
    else
        text = string.format(L["Buy for %s (usually ~%s), list at %s"], Money(d.unit), Money(d.fair), Money(d.target))
    end
    local bits = { text, FT.C("up", "+" .. Money(d.perUnit) .. " " .. L["each"]) }
    -- the risk: what you'd lose at worst, and how flipping it went before
    local risk = Risk(d)
    if risk then bits[#bits + 1] = risk end
    if d.record then
        local ok, n = d.record[1], d.record[2]
        bits[#bits + 1] = FT.C(ok / n >= 0.8 and "up" or "accent", d.record[3] and string.format(L["worked %d/%d"], ok, n)
            or string.format(L["%d%% worked"], math.floor(ok / n * 100 + 0.5)))
    end
    local qty = d.noBook and L["the cheapest one"] or string.format(L["%s of them"], FT.Num(d.qty))
    bits[#bits + 1] = FT.C("dim", qty)
    local sells = d.kind ~= "VENDOR" and d.kind ~= "DE" and SellsIn(d)
    if sells then bits[#bits + 1] = sells end
    local budget = Budget(d)
    if budget then bits[#bits + 1] = budget end
    return table.concat(bits, FT.C("dim", "  ·  "))
end

-- the worst case and the replayed record, in a deal's hover
local function DealRiskLines(d)
    if d.worst then
        if d.worst <= 0 then
            GameTooltip:AddLine(L["Worst case: none - a vendor (or its lowest price in a month) still pays what you paid."], 0.4, 0.85, 0.5, true)
        else
            GameTooltip:AddLine(string.format(L["Worst case: if it doesn't sell and you let it go at its lowest price of the last weeks, you lose %s."],
                Money(d.worst)), 0.95, 0.75, 0.3, true)
        end
    end
    if d.record then
        local ok, n, own = d.record[1], d.record[2], d.record[3]
        GameTooltip:AddLine(own and string.format(L["Replayed on its price history: a dip this deep came back within 3 days %d of %d times."], ok, n)
            or string.format(L["Replayed on items like it: dips this deep came back within 3 days %d%% of the time (%d cases)."],
                math.floor(ok / n * 100 + 0.5), n), 0.85, 0.87, 0.9, true)
    elseif d.kind == "RESELL" then
        GameTooltip:AddLine(L["No dip this deep in its history yet to replay: a newer market, so a bit riskier."], 0.95, 0.75, 0.3, true)
    end
end

local function DealTip(row, d)
    UI.TipItem(row, d.id)
    local qty = d.noBook and L["the cheapest lot"] or string.format(L["%s pcs"], FT.Num(d.qty))
    GameTooltip:AddLine(" ")
    if d.kind == "DE" then
        GameTooltip:AddLine(L["Disenchanted, it usually gives:"], 0.85, 0.87, 0.9)
        for _, o in ipairs(FT.Enchant.Outcome(d.id) or {}) do
            GameTooltip:AddDoubleLine(string.format("%d%%  %s x%s", math.floor(o[2] * 100 + 0.5), FT.ItemText(o[1]), o[3] == math.floor(o[3]) and tostring(o[3]) or string.format("%.1f", o[3])),
                FT.Price(o[1]) and FT.Money(FT.Price(o[1]), "short") or L["no price"], 0.8, 0.82, 0.86, 1, 1, 1)
        end
        GameTooltip:AddLine(L["Classic's odds: WoW Forever's may differ."], 0.6, 0.64, 0.7, true)
        GameTooltip:Show()
        return
    end
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
        DealRiskLines(d)
        if d.noBook then
            GameTooltip:AddLine(L["Only the cheapest lot is sure: open the item (or Check order books) for its whole order book."], 0.6, 0.62, 0.66, true)
        end
        GameTooltip:AddLine(L["Click: the item with its order book - buy there."], 0.6, 0.62, 0.66, true)
        if FT.Carry.Get(d.id) then
            GameTooltip:AddLine(L["Right click: out of your carry list."], 0.6, 0.62, 0.66, true)
        else
            GameTooltip:AddLine(string.format(L["Right click: into your carry list - at %s the Sell page shows what you brought and what it cost."],
                H.Name(d.sellHouse)), 0.6, 0.62, 0.66, true)
        end
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
    DealRiskLines(d)
    if d.cheap and d.cap and d.cheap > d.qty then
        GameTooltip:AddLine(string.format(L["%s pcs are this cheap: buy no more than %s - more doesn't sell in two days."],
            FT.Num(d.cheap), FT.Num(d.qty)), 0.95, 0.75, 0.3, true)
    end
    if d.noBook then
        GameTooltip:AddLine(L["Only the cheapest lot is sure: open the item (or Check order books) for its whole order book."], 0.6, 0.62, 0.66, true)
    end
    GameTooltip:AddLine(L["Click: the item with its order book - buy there."], 0.6, 0.62, 0.66, true)
    GameTooltip:Show()
end

local ShownDeals -- below (the To Auctionator button needs it first)

local function BuildDeals(p)
    local f = CreateFrame("Frame", nil, p)
    f:SetPoint("TOPLEFT", 8, -56)
    f:SetPoint("BOTTOMRIGHT", -8, 8)
    f:Hide()
    -- (no "Between houses" since v0.28: only your faction's house is followed)
    if dstate.kind == "HOUSES" then dstate.kind = "all" end
    f.kind = UI.Segmented(f, { { "all", L["All"] }, { "VENDOR", L["To a vendor"] }, { "RESELL", L["Resell"] } }, function(v)
        dstate.kind = v
        T.RefreshDeals()
    end, 22)
    f.kind:SetPoint("TOPLEFT", 0, -1)
    f.kind:SetValue(dstate.kind)
    T.dealsKind = f.kind -- the tour points at it
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
    -- the deals on the page as an Auctionator shopping list
    f.toAtr = UI.Button(f, L["To Auctionator"], 10, 24, "default", function()
        local ids = {}
        for i, d in ipairs((ShownDeals())) do
            if i > 30 then break end
            if d.kind ~= "HOUSES" or d.buyHouse == FT.house then ids[#ids + 1] = d.id end
        end
        FT.ToAuctionator(L["Wolf: Make gold"], ids)
    end)
    f.toAtr:FitText(24)
    f.toAtr:SetPoint("RIGHT", f.check, "LEFT", -6, 0)
    f.toAtr:SetTip(L["To Auctionator"], L["The deals here (bought at this auction house) as an Auctionator shopping list: buy them from its Shopping tab."])
    f.count = UI.Text(f, 11, "dim", "RIGHT")
    f.count:SetPoint("RIGHT", f.toAtr, "LEFT", -12, 0)
    f.hint = UI.Text(f, 11, "dim")
    f.hint:SetPoint("TOPLEFT", 0, -32)
    f.hint:SetPoint("RIGHT", 0, 0)
    if f.hint.SetWordWrap then f.hint:SetWordWrap(false) end
    DEALS_HINT = L["Buy it, then: FLIP IT (list it again near its normal price) or VENDOR IT. Best first."]
    f.hint:SetText(DEALS_HINT)
    local box = UI.Panel(f, "bg1", "line")
    box:SetPoint("TOPLEFT", 0, -50)
    box:SetPoint("BOTTOMRIGHT", 0, 0)
    f.list = UI.List(box, {
        rowHeight = UI.RowH(46),
        setup = RowSetup,
        update = function(row, d)
            row.icon:SetItem(d.id)
            local listed = d.kind == "HOUSES" and FT.Carry.Get(d.id)
            row.name:SetText(FT.ItemText(d.id, 40) .. (listed and FT.C("accent", "  [" .. L["in your list"] .. "]") or ""))
            row.reason:SetText(DealText(d))
            row.value:SetText(FT.C("up", "+" .. Money(d.profit)))
            local label = (d.kind == "RESELL" and L["FLIP IT"]) or (d.kind == "VENDOR" and L["VENDOR IT"])
                or (d.kind == "DE" and L["DE IT"]) or nil
            row.badge:Set(d.kind, label, d.noBook and 1 or 3)
        end,
        onClick = function(d, button)
            -- between the houses: a right click takes it on (or lets it go)
            if button == "RightButton" and d.kind == "HOUSES" then
                local on = FT.Carry.Toggle(d)
                local H = FT.House
                if on then
                    FT.Print(string.format(L["Carry list: %s - buy at %s for up to %s each, list at %s for ~%s."],
                        FT.ItemText(d.id), H.Name(d.buyHouse), Money(d.unit), H.Name(d.sellHouse), Money(d.target)))
                else
                    FT.Print(string.format(L["Carry list: %s is out of it."], FT.ItemText(d.id)))
                end
                T.RefreshDeals()
                return
            end
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
function ShownDeals()
    local list, _, building = FT.Deals.List()
    -- buy it to disenchant (your best enchanter's skill): with the rest, by profit
    local de = FT.Enchant and FT.Enchant.Deals() or {}
    if #de > 0 then
        local merged = {}
        for _, d in ipairs(list or {}) do merged[#merged + 1] = d end
        for i = 1, math.min(#de, 40) do merged[#merged + 1] = de[i] end
        table.sort(merged, function(a, b) return (a.profit or 0) > (b.profit or 0) end)
        list = merged
    end
    local matches = FT.NameMatcher(T.search)
    local since = time() - dstate.age
    local out, noBook, total, older = {}, {}, 0, 0
    local have = {}
    for _, d in ipairs(list) do
        if (dstate.kind == "all" or d.kind == dstate.kind) and (not matches or matches(d.id)) then
            if d.t >= since or (d.kind == "HOUSES" and FT.Carry.Get(d.id)) then
                out[#out + 1] = d
                total = total + d.profit
                if d.kind == "HOUSES" then have[d.id] = true end
                -- only the house open here can be searched (between the houses: the one it is bought at)
                if d.noBook and (d.kind ~= "HOUSES" or d.buyHouse == FT.house) then noBook[#noBook + 1] = d.id end
            else
                older = older + 1
            end
        end
    end
    -- the carry list: what you took on stays on the page (whatever the prices' age), first
    if dstate.kind == "all" or dstate.kind == "HOUSES" then
        for _, d in ipairs(FT.Carry.Rows(have)) do
            if not matches or matches(d.id) then out[#out + 1] = d end
        end
        local function Listed(d) return d.kind == "HOUSES" and FT.Carry.Get(d.id) ~= nil end
        local keyed = {}
        for i, d in ipairs(out) do keyed[d] = i end
        table.sort(out, function(a, b)
            local la, lb = Listed(a), Listed(b)
            if la ~= lb then return la end
            return keyed[a] < keyed[b]
        end)
    end
    -- what you can't pay for goes last (the carry list stays first)
    local keyed2 = {}
    for i, d in ipairs(out) do keyed2[d] = i end
    local function Over(d) local _, over = Budget(d) return over end
    local function Listed(d) return d.kind == "HOUSES" and FT.Carry.Get(d.id) ~= nil end
    table.sort(out, function(a, b)
        local la, lb = Listed(a), Listed(b)
        if la ~= lb then return la end
        local oa, ob = Over(a), Over(b)
        if oa ~= ob then return ob end
        return keyed2[a] < keyed2[b]
    end)
    return out, total, noBook, building, older
end

-- no deals on the page: why (no prices yet, old prices, vendor prices still coming, too little history, the
-- minimum profit)
local function WhyNoDeals(older)
    if T.search ~= "" then return L["Nothing matches"] end
    local info = FT.Deals.Info()
    if info and info.items == 0 then
        return L["No prices yet. They come with the next update (Blizzard's hourly prices), or scan in Auctionator at the auction house."]
    end
    local why = { L["No good deals right now."] }
    if older > 0 then
        why[#why + 1] = string.format(L["%d more with older prices: choose 24 h, or scan in Auctionator."], older)
    elseif info and info.newest and info.newest < time() - dstate.age then
        why[#why + 1] = string.format(L["Newest prices: %s. Scan in Auctionator, or /reload for Blizzard's newest."], FT.Ago(info.newest))
    end
    if FT.Deals.Loading() > 0 then
        why[#why + 1] = L["Vendor prices are still loading: deals to a vendor follow."]
    end
    if info and info.history == 0 and (dstate.kind == "all" or dstate.kind == "RESELL") then
        why[#why + 1] = L["Flipping needs at least 3 days of prices."]
    end
    if false and (dstate.kind == "all" or dstate.kind == "HOUSES") then
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
        return L["No good deals right now. New prices come every hour: check back after the next update."]
    end
    return table.concat(why, "\n\n")
end

function T.RefreshDeals()
    local f = dealsView
    if not (f and f:IsShown()) then return end
    local shown, total, noBook, building, older = ShownDeals()
    -- still looking: how far (the page updates itself until done)
    local pct = FT.Deals.Progress and FT.Deals.Progress()
    local looking = pct and string.format(L["Finding deals... %d%%"], math.floor(pct * 100)) or L["Looking for deals..."]
    -- while looking: only the percentage again every half second (the whole list took ~25 ms a time); the list
    -- itself when the deals are ready (FT_DEALS_READY)
    if building then
        local function Tick()
            if not (dealsView and dealsView:IsVisible()) then return end
            local _, _, still = FT.Deals.List()
            if not still then return end
            local q = FT.Deals.Progress and FT.Deals.Progress()
            local text = q and string.format(L["Finding deals... %d%%"], math.floor(q * 100)) or L["Looking for deals..."]
            dealsView.count:SetText(text)
            if dealsView.list.items == nil or #dealsView.list.items == 0 then
                dealsView.list:SetEmptyText(text)
                dealsView.list:Refresh()
            end
            C_Timer.After(0.5, Tick)
        end
        if not T.progressTicking then
            T.progressTicking = true
            C_Timer.After(0.5, function() T.progressTicking = false; Tick() end)
        end
    end
    f.list:SetEmptyText((building and #shown == 0) and looking or WhyNoDeals(older))
    -- vendor prices still coming: said in place of the hint
    local left = FT.Deals.Loading()
    f.hint:SetText(left > 0 and string.format(L["Loading vendor prices: %s items left - deals to a vendor follow as they come."],
        FT.Num(left)) or DEALS_HINT)
    f.list:SetItems(shown, true)
    if #shown > 0 then
        f.count:SetText(string.format(L["%d deals, +%s in all"], #shown, Money(total)))
    else
        f.count:SetText(building and looking or "")
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
    if kind == "all" then kind = "HOUSES" end
    T.SetView(kind)
end

local DEAL_VIEWS = { make = true }

local sellView, farmView, craftView -- the Sell yours, Farm Board and Craft for profit views (built in T.Build)

function T.SetView(view)
    -- the old names (the tour, What's new, other pages): one Make gold list now; Sell yours is in Portfolio
    if view == "sell" then
        FT.SelectTab("portfolio")
        FT.Tabs.portfolio.SetView("sell")
        return
    end
    if view == "deals" or view == "HOUSES" or view == "RESELL" or view == "VENDOR" or view == "signals" then view = "make" end
    T.view = view
    if T.viewSeg then T.viewSeg:SetValue(view) end
    if FT.GroupShows and (view == "make" or view == "craft" or view == "farm") then FT.GroupShows("make", view) end
    local deals = DEAL_VIEWS[view]
    if deals then dstate.kind = "all" end
    if dealsView then
        dealsView:SetShown(deals or false)
        dealsView.kind:Hide()
        dealsView.ageLabel:ClearAllPoints()
        dealsView.ageLabel:SetPoint("TOPLEFT", 0, -6)
    end
    if sellView then sellView:SetShown(view == "sell") end
    if farmView then farmView:SetShown(view == "farm") end
    if craftView then craftView:SetShown(view == "craft") end
    T.Refresh()
end

---------------------------------------------------------------------------
-- A plain list view (Sell yours, the Farm Board): a bar on top, one list
---------------------------------------------------------------------------
local function ListView(p, onClick, onEnter)
    local f = CreateFrame("Frame", nil, p)
    f:SetPoint("TOPLEFT", 8, -56)
    f:SetPoint("BOTTOMRIGHT", -8, 8)
    f:Hide()
    f.hint = UI.Text(f, 11, "dim")
    f.hint:SetPoint("TOPLEFT", 0, -32)
    f.hint:SetPoint("RIGHT", 0, 0)
    if f.hint.SetWordWrap then f.hint:SetWordWrap(false) end
    f.count = UI.Text(f, 11, "dim", "RIGHT")
    f.count:SetPoint("TOPRIGHT", 0, -6)
    local box = UI.Panel(f, "bg1", "line")
    box:SetPoint("TOPLEFT", 0, -50)
    box:SetPoint("BOTTOMRIGHT", 0, 0)
    f.list = UI.List(box, {
        rowHeight = UI.RowH(46),
        setup = RowSetup,
        update = function(row, x)
            row.icon:SetItem(x.id)
            row.name:SetText(FT.ItemText(x.id, 40) .. (x.qty and FT.C("dim", "  x" .. FT.Num(x.qty)) or ""))
            row.reason:SetText(x.reason or "")
            row.value:SetText(x.value or "")
            row.badge:Set(x.signal, x.label, x.strength or 2)
        end,
        onClick = onClick,
        onEnter = onEnter,
    })
    f.list:SetPoint("TOPLEFT", 1, -2)
    f.list:SetPoint("BOTTOMRIGHT", -1, 2)
    if f.list.empty then f.list.empty:SetWidth(460) end
    return f
end


-- Sell yours: each thing you own (every character) and the best way to turn it into gold - the vendor, this
-- auction house, or the other one when it pays clearly more after its cut; how many to list at once
local function SellYours()
    local out = {}
    local here = FT.house
    local other = (here == "neutral") and "faction" or "neutral"
    local H = FT.House
    for _, h in ipairs((FT.Port.Rows())) do
        local id = h.id
        -- the price to list at here: not under a bait lot, not at a spike that won't last (FT.An.Stats listAt)
        local st = h.stats
        local listAt = (st and st.listAt) or h.price
        local netHere = listAt * (1 - FT.Cut(here))
        local vendor = FT.SellPriceKnown(id) or 0
        -- only this house since v0.28 (no "sell it at the other house")
        local pOther = nil
        local netOther = pOther and pOther * (1 - FT.Cut(other)) or 0
        local x = { id = id, qty = h.qty }
        local unit, house
        if vendor > 0 and vendor >= netHere and vendor >= netOther then
            x.signal, unit = "VENDOR", vendor
            x.reason = L["A vendor pays more than the auction house"]
        elseif netOther > netHere * 1.1 then
            x.signal, x.label, unit, house = "HOUSES", L["AH TO AH"], netOther, other
            x.reason = string.format(L["%s pays %s (here %s)"], H.Name(other), FT.Money(pOther, "short"),
                FT.Money(h.price, "short"))
        else
            unit, house = netHere, here
            local own = h.signal == "SELL" or h.signal == "HOLD" or h.signal == "TRIM"
            x.signal = own and h.signal or "SELL"
            x.label = (not own) and L["SELL"] or nil
            x.reason = h.reason or string.format(L["%s each here"], FT.Money(listAt, "short"))
            if st and st.bait then
                x.reason = x.reason .. FT.C("dim", "  ·  ") .. FT.C("accent", string.format(L["list at ~%s: the cheapest one looks like bait"], FT.Money(listAt, "short")))
            end
        end
        -- how many at once: what sells there in two days
        local rate = house and FT.Sales.RateIn(house, id)
        if rate and rate.perDay and rate.perDay > 0 then
            local cap = math.max(1, math.floor(rate.perDay * 2 + 0.5))
            if cap < h.qty then x.reason = x.reason .. FT.C("dim", "  ·  ") .. string.format(L["list %s at a time"], FT.Num(cap)) end
        elseif house and rate and rate.hours and rate.hours >= 12 then
            x.reason = x.reason .. FT.C("dim", "  ·  ") .. FT.C("down", L["hardly sells"])
        end
        x.sortV = unit * h.qty
        x.value = FT.C("up", FT.Money(math.floor(x.sortV), "short"))
        out[#out + 1] = x
    end
    table.sort(out, function(a, b) return a.sortV > b.sortV end)
    return out
end

-- The Farm Board: raw materials ranked by the gold the market pays for them a day (price x how many sell a
-- day), with the week's move. Where to farm them is up to you: right-click gives a Wowhead link.
local FARM_KINDS = {
    { "all", "All" }, { "ore", "Ore & stone" }, { "herb", "Herbs" }, { "leather", "Leather" }, { "cloth", "Cloth" },
    { "elemental", "Elemental" }, { "gem", "Gems" },
}
local FARM_CLASS = FT.Farm.CLASS -- the item classes and subclasses of each (FT.Farm)
local farmKind = "all"

local function FarmKindOf(r)
    for k, c in pairs(FARM_CLASS) do
        if r.cls == c[1] and (c[2] == nil or r.sub == c[2]) then return k end
    end
    return nil
end

-- What one farmer could make of it a day: you sell a share of what sells (a fifth), and no more than you'd
-- gather in an hour or so (40). The whole market's trade (price x everyone's sales: "12,821g a day") told a new
-- player nothing about what they would make.
-- Something that sells under 20 a day is rare (a gem, a rare drop): no one farms three of those a day, so it
-- ranks after the ones you can go and gather.
local FARM_SHARE, FARM_MAX, FARM_COMMON = 0.2, 40, 20
local function FarmYours(price, perDay)
    return price * math.min((perDay or 0) * FARM_SHARE, FARM_MAX)
end
local function FarmRank(price, perDay)
    local v = FarmYours(price, perDay)
    if (perDay or 0) < FARM_COMMON then return v / 1000 end
    return v
end
T.FarmYours = FarmYours

-- One item's line on the farm list (nil: not something you farm, or not the kind chosen)
local function FarmEntry(r)
    local kind = r.price and FarmKindOf(r)
    if not (kind and (farmKind == "all" or farmKind == kind) and not r.gone) then return nil end
    local rate = FT.Sales.Rate(r.id)
    local perDay = rate and rate.perDay or 0
    local yours = FarmYours(r.price, perDay)
    local bits = {}
    if rate then bits[#bits + 1] = FT.Sales.PerDayText(rate) else bits[#bits + 1] = L["sales not seen yet"] end
    if r.ch7 then bits[#bits + 1] = FT.Pct(r.ch7) .. " " .. L["this week"] end
    if yours > 0 then bits[#bits + 1] = string.format(L["you could sell ~%s a day"], FT.Money(math.floor(yours), "short")) end
    return {
        id = r.id, reason = table.concat(bits, FT.C("dim", "  ·  ")), sortV = FarmRank(r.price, perDay), yours = yours,
        price = r.price, perDay = perDay,
        value = FT.C("up", FT.Money(r.price, "short")) .. FT.C("dim", " " .. L["each"]),
        signal = (r.ch7 or 0) >= 0.1 and "SELL" or ((r.ch7 or 0) <= -0.1 and "BUY" or "HOLD"),
        label = ((r.ch7 or 0) >= 0.1 and L["HOT"]) or ((r.ch7 or 0) <= -0.1 and L["COOLING"]) or L["STEADY"],
    }
end

local function FarmSort(out)
    table.sort(out, function(a, b) return a.sortV > b.sortV end)
    while #out > 80 do table.remove(out) end
    return out
end

-- Made once per market list and farm choice (the overview asks every time it draws). New prices: the last list
-- stays until the new one is worked out in the background, a few ms a frame - not all of it in one frame.
local farmCache, farmFor, farmKindFor, farmJob, farmStale
local function FarmLater()
    local rows = FT.Market.Rows()
    if not rows or not farmCache then farmCache, farmStale = nil, false return end
    if farmJob then farmJob.Cancel() end
    local kindNow, out = farmKind, {}
    farmJob = FT.Job("farm", #rows, function(k)
        if FT.Market.Rows() ~= rows then return false end
        local e = FarmEntry(rows[k])
        if e then out[#out + 1] = e end
    end, function()
        farmJob, farmStale = nil, false
        if farmKind ~= kindNow then return end
        farmCache, farmFor, farmKindFor = FarmSort(out), rows, kindNow
        if T.RefreshFarm then T.RefreshFarm() end
    end, 3)
end
local function Stale() farmStale = farmCache ~= nil; FT.Debounce("farmList", 0.5, FarmLater) end
FT.On("FT_MARKET_READY", Stale)
FT.On("FT_SCAN_DONE", Stale)
local function FarmRows()
    local rowsNow = FT.Market.Rows()
    -- the same list, or the last one while the new one is worked out
    if farmCache and farmKindFor == farmKind and (farmFor == rowsNow or farmJob or farmStale) then return farmCache end
    local out = {}
    for _, r in ipairs(rowsNow or {}) do
        local e = FarmEntry(r)
        if e then out[#out + 1] = e end
    end
    farmCache, farmFor, farmKindFor = FarmSort(out), rowsNow, farmKind
    return farmCache
end

local function WowheadLink(id) FT.Farm.Wowhead(id) end

T.ListView, T.SellYours = ListView, SellYours

-- Craft for profit: every recipe of WoW Forever whose product sells every day, by the gold it should make a day
local function BuildCraftView(p)
    local f = ListView(p, function(x)
        if UI.ItemClick(x.id) then return end
        FT.ShowCraft(x.recipe)
    end, function(row, x)
        UI.TipItem(row, x.id)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Click: every material, what it costs, and crafting vs buying it ready."], 0.6, 0.64, 0.7, true)
        GameTooltip:Show()
    end)
    -- every profession by default; one profession, and only what your characters know, on a choice
    local profs = { { "all", L["All professions"] } }
    for _, p in ipairs({ "Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering", "First Aid", "Leatherworking", "Mining", "Tailoring" }) do
        profs[#profs + 1] = { p, L[p] }
    end
    f.prof = UI.Dropdown(f, 150, profs, function(v)
        T.craftProf = v
        T.RefreshCraft()
    end)
    f.prof:SetPoint("TOPLEFT", 0, 0)
    T.craftProf = T.craftProf or "all"
    f.prof:SetValue(T.craftProf)
    f.known = UI.Segmented(f, { { "all", L["Every recipe"] }, { "known", L["Ones you know"] } }, function(v)
        T.craftFilter = v
        T.RefreshCraft()
    end, 22)
    f.known:SetPoint("LEFT", f.prof, "RIGHT", 8, 0)
    T.craftFilter = T.craftFilter or "all"
    f.known:SetValue(T.craftFilter)
    f.hint:SetText(L["Every profession's crafts worth making: sell what it makes, or disenchant it. The ones you know say so in green."])
    f.list:SetEmptyText(L["Working out every recipe..."])
    return f
end

function T.RefreshCraft()
    if not (craftView and craftView:IsShown()) then return end
    local list = FT.Craft.ProfitCrafts(function() T.RefreshCraft() end)
    if not list then
        craftView.list:SetEmptyText(L["Working out every recipe..."])
        craftView.list:SetItems({}, true)
        return
    end
    local matches = FT.NameMatcher(T.search)
    local out = {}
    local ench = FT.Enchant and FT.Enchant.Skill()
    for _, c in ipairs(list) do
        if (T.craftFilter ~= "known" or c.known) and (T.craftProf == "all" or c.prof == T.craftProf) and (not matches or matches(c.id)) then
            local e = c.eval
            local qty = c.recipe.outputQty or 1
            local how
            if c.mode == "de" then
                how = string.format(L["Costs %s to make, disenchants for ~%s"], FT.Money(math.floor(e.cost), "short"), FT.Money(math.floor(c.deValue or 0), "short"))
                if not ench or (c.deSkill and ench < c.deSkill) then how = how .. FT.C("accent", "  ·  " .. string.format(L["needs an enchanter (%d)"], c.deSkill or 1)) end
            else
                how = string.format(L["Costs %s to make, sells for %s"], FT.Money(math.floor(e.cost), "short"), FT.Money(math.floor(e.revenue), "short"))
                how = how .. FT.C("dim", "  ·  " .. (c.perDay and string.format(L["sells %s a day"], FT.Num(math.floor(c.perDay + 0.5))) or L["sales not seen yet"]))
            end
            out[#out + 1] = {
                id = c.id, recipe = c.recipe, qty = qty > 1 and qty or nil,
                signal = c.mode == "de" and "DE" or "CRAFT",
                label = c.mode == "de" and L["CRAFT + DE"] or L["CRAFT IT"], strength = c.known and 3 or 1,
                reason = how .. FT.C("dim", "  ·  " .. L[c.recipe.prof or "?"])
                    .. (c.cooldown and FT.C("accent", "  ·  " .. string.format(L["once every %d days (cooldown)"], c.cooldown)) or "")
                    .. (c.known and FT.C("up", "  ·  " .. L["you know it"]) or ""),
                value = FT.C("up", "+" .. FT.Money(math.floor(c.profit), "short")) .. FT.C("dim", " " .. L["each craft"]),
            }
        end
    end
    -- your crafters, on the line under the choices
    local crafters = FT.Craft.CraftersText and FT.Craft.CraftersText()
    craftView.hint:SetText(crafters and (FT.C("accent", L["Your crafters"]) .. ":  " .. crafters)
        or L["Every profession's crafts worth making: sell what it makes, or disenchant it. Log in each crafter once so their professions show here."])
    craftView.list:SetEmptyText(T.craftFilter == "known" and L["None of the recipes you know makes a profit right now. Open your profession windows once so they're known."]
        or L["No craft makes a profit on a product that sells every day right now."])
    craftView.count:SetText(#out > 0 and string.format(L["%d crafts"], #out) or "")
    craftView.list:SetItems(out, true)
end
FT.On("FT_CRAFTS_READY", function() T.RefreshCraft() end)
T.FarmRows = function() return FarmRows() end

local function BuildSellView(p)
    local f = ListView(p, function(x)
        if UI.ItemClick(x.id) then return end
        FT.OpenItem(x.id)
    end, function(row, x) UI.TipItem(row, x.id) end)
    f.hint:SetText(L["Everything your characters own, and the best way to turn each into gold. Characters count once they log in and open their bank and mailbox."])
    f.list:SetEmptyText(L["Nothing priced yet. Open your bags and bank once per character."])
    return f
end

local function BuildFarmView(p)
    local f = ListView(p, function(x, button)
        if button == "RightButton" then UI.WatchMenu(x.id) return end
        if UI.ItemClick(x.id) then return end
        FT.ShowFarm(x.id)
    end, function(row, x)
        UI.TipItem(row, x.id)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Click: where to farm it || Right-click: watchlist"], 0.6, 0.64, 0.7)
        GameTooltip:Show()
    end)
    local items = {}
    for _, k in ipairs(FARM_KINDS) do items[#items + 1] = { k[1], L[k[2]] } end
    f.kind = UI.Segmented(f, items, function(v)
        farmKind = v
        T.RefreshFarm()
    end, 22)
    f.kind:SetPoint("TOPLEFT", 0, -1)
    f.kind:SetValue(farmKind)
    f.hint:SetText(L["Raw materials by what one farmer could sell of them a day, best first. Click one: where to farm it for your level."])
    f.list:SetEmptyText(L["No sales seen yet: the price feed fills this over a few hours."])
    return f
end

function T.RefreshSell()
    if not (sellView and sellView:IsShown()) then return end
    local list = SellYours()
    local matches = FT.NameMatcher(T.search)
    if matches then
        local kept = {}
        for _, x in ipairs(list) do if matches(x.id) then kept[#kept + 1] = x end end
        list = kept
    end
    local total = 0
    for _, x in ipairs(list) do total = total + x.sortV end
    sellView.count:SetText(#list > 0 and string.format(L["%d items, worth %s"], #list, FT.Money(math.floor(total), "short")) or "")
    sellView.list:SetItems(list, true)
end

function T.RefreshFarm()
    if not (farmView and farmView:IsShown()) then return end
    local list = FarmRows()
    local matches = FT.NameMatcher(T.search)
    if matches then
        local kept = {}
        for _, x in ipairs(list) do if matches(x.id) then kept[#kept + 1] = x end end
        list = kept
    end
    farmView.list:SetItems(list, true)
end

-- the best deal there is right now, for the line under the title
local function BestMove()
    local list = FT.Deals.List()
    local best
    for _, d in ipairs(list or {}) do
        if not best or (d.perUnit or 0) * math.min(d.qty or 1, 20) > (best.perUnit or 0) * math.min(best.qty or 1, 20) then best = d end
    end
    if not best then return nil end
    local H = FT.House
    local what = (best.kind == "HOUSES" and string.format(L["carry %s to %s"], FT.ItemText(best.id), H.Name(best.sellHouse)))
        or (best.kind == "VENDOR" and string.format(L["vendor %s"], FT.ItemText(best.id)))
        or string.format(L["flip %s"], FT.ItemText(best.id))
    return L["Best move right now"] .. ": " .. what .. "  " .. FT.C("up", "+" .. Money(best.perUnit or 0) .. " " .. L["each"])
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
    T.title:SetText(L["Money"])
    T.rules = UI.Text(head, 11, "dim")
    T.rules:SetPoint("TOPLEFT", 4, -24)
    T.rules:SetPoint("RIGHT", head, "RIGHT", -150, 0)

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
    -- one way to make gold per view; Signals: the four columns
    T.view = T.view or "make"
    T.viewSeg = UI.GroupBar(head, "make")
    T.viewSeg:SetPoint("LEFT", T.searchBox, "RIGHT", 12, 0)
    T.viewSeg:SetValue(T.view)
    dealsView = BuildDeals(p)
    farmView = BuildFarmView(p)
    craftView = BuildCraftView(p)
    -- the deals are looked for again on new prices only while they are on the screen (Sell yours and the
    -- line under the title use them too)
    FT.Deals.watching = function() return dealsView:IsVisible() or (T.title and T.title:IsVisible()) end
end

function T.Refresh()
    FT.Deals.Ensure()
    local best = BestMove()
    if DEAL_VIEWS[T.view] or T.view == "sell" or T.view == "farm" or T.view == "craft" then
        T.rules:SetText(best or FT.C("dim", L["No deal right now: the list fills as prices come in."]))
        if DEAL_VIEWS[T.view] then T.RefreshDeals() end
        if T.view == "sell" then T.RefreshSell() end
        if T.view == "farm" then T.RefreshFarm() end
        if T.view == "craft" then T.RefreshCraft() end
        return
    end
end

T.OnShow = T.Refresh

-- item names and colours arrived: the rows on screen show them (and a search may find more now)
function T.OnItems()
    if T.search and T.search ~= "" then
        FT.Debounce("signalsSearch", 0.5, T.Refresh)
        return
    end
    if dealsView and dealsView:IsShown() then
        dealsView.list:Refresh()
        FT.Debounce("dealsHint", 1, T.RefreshDeals)
    end
end

-- the deals were looked for again; the auction house opened or closed (Check order books needs it)
FT.On("FT_DEALS_READY", function()
    T.RefreshDeals()
    if T.title and T.title:IsVisible() and T.view ~= "signals" then
        local best = BestMove()
        if best then T.rules:SetText(best) end
    end
end)
FT.On("FT_CARRY_CHANGED", function() T.RefreshDeals() end)
FT.On("AUCTION_HOUSE_SHOW", function() C_Timer.After(0.5, T.RefreshDeals) end)
FT.On("AUCTION_HOUSE_CLOSED", function() C_Timer.After(0.5, T.RefreshDeals) end)
FT.On("FT_AH_CHANGED", function() C_Timer.After(0.1, T.RefreshDeals) end)
