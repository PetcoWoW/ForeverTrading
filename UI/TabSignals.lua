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
    -- (v0.62) Flip it's two rows: Deals now / Materials, then the mode's own choice
    f.mode = UI.Segmented(f, { { "deals", L["Deals now"] }, { "mats", L["Materials"] } }, function(v) T.SetFlipMode(v) end, 22)
    f.mode:SetPoint("TOPLEFT", 0, -1)
    f.mode:SetValue("deals")
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
    f.box = box
    f.list = UI.List(box, {
        rowHeight = UI.RowH(46),
        setup = RowSetup,
        update = function(row, d)
            row.icon:SetItem(d.id)
            local listed = d.kind == "HOUSES" and FT.Carry.Get(d.id)
            row.name:SetText(FT.ItemText(d.id, 40) .. (listed and FT.C("accent", "  [" .. L["in your list"] .. "]") or ""))
            -- (a long line drops its last parts, never cut mid-word)
            UI.FitBits(row.reason, DealText(d))
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

---------------------------------------------------------------------------
-- (v0.62) Flip it > Materials: the raw materials people trade (herbs, ore, cloth, leather, enchanting, elemental),
-- each with today's lowest, a "buy below" line (its usual less your Buy-below setting, Settings > Signals) and a
-- verdict: BUY NOW under it, WAIT over its usual (or while it's still sliding), FAIR between. Yours first (what
-- your characters' professions use), and what you paid when Wolf knows (your auction house mail, or Set what I
-- paid on the item's page).
---------------------------------------------------------------------------
T.flipMode = "deals"
local matsShow = "yours"
local MAT_SUBS = { [9] = true, [7] = true, [5] = true, [6] = true, [12] = true, [10] = true }

local function YourProfs()
    local out = {}
    for name, lv in pairs(FT.Me and FT.Me.Profs() or {}) do if (lv or 0) > 0 then out[FT.ProfKey(name)] = true end end
    return out
end

local function MatRows()
    local profs = YourProfs()
    local th = (FT.S.buyBelow or 15) / 100
    local match = FT.NameMatcher(T.search)
    local out = {}
    for _, r in ipairs(FT.Market.Rows() or {}) do
        if r.cls == 7 and MAT_SUBS[r.sub] and r.price and (not match or match(r.id)) then
            local rate = FT.Sales.Rate(r.id)
            local perDay = rate and rate.perDay or 0
            local yours = false
            for _, rc in ipairs(FT.Craft.UsedIn(r.id) or {}) do if profs[rc.prof] then yours = true break end end
            if perDay >= 3 and (matsShow == "all" or yours) then
                local s = FT.An.Stats(r.id)
                local sig, _, why = FT.An.BuySignal(s)
                local below = s.avg and s.avg * (1 - th) or nil
                local label, signal, strength
                if sig == "BUY" then label, signal, strength = L["BUY NOW"], "BUY", 3
                elseif sig == "EXPENSIVE" or sig == "WATCH" then label, signal, strength = L["WAIT"], "WAIT", 2
                elseif sig == "FAIR" then label, signal, strength = L["FAIR"], "HOLD", 1
                else label, signal, strength = nil, "NODATA", 0 end
                local bits = {}
                if below then bits[#bits + 1] = string.format(L["buy below %s"], FT.Money(math.floor(below), "short")) end
                if sig == "WATCH" or sig == "EXPENSIVE" then bits[#bits + 1] = FT.C("dim", why) end
                local paid = FT.PaidText(r.id)
                if paid then bits[#bits + 1] = paid end
                bits[#bits + 1] = FT.C("dim", FT.Sales.PerDayText(rate))
                out[#out + 1] = {
                    id = r.id, fit = true, reason = table.concat(bits, FT.C("dim", "  ·  ")),
                    value = FT.C(sig == "BUY" and "up" or "text", FT.Money(r.price, "short")) .. FT.C("dim", " " .. L["now"]),
                    signal = signal, label = label, strength = strength,
                    rank = (sig == "BUY" and 0 or (sig == "FAIR" and 1 or 2)), dev = s.dev or 0, vol = perDay * r.price,
                }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        if a.rank == 0 and a.dev ~= b.dev then return a.dev < b.dev end
        return a.vol > b.vol
    end)
    return out
end
T.MatRows = MatRows

function T.SetFlipMode(v)
    T.flipMode = v
    if dealsView and dealsView.mode then dealsView.mode:SetValue(v) end
    if T.matsView and T.matsView.mode then T.matsView.mode:SetValue(v) end
    T.SetView("make")
    if v == "mats" then T.RefreshMats() else T.RefreshDeals() end
    if FT.NavNote then FT.NavNote() end
end

function T.RefreshMats()
    local f = T.matsView
    if not (f and f:IsShown()) then return end
    local rows = MatRows()
    f.list:SetEmptyText(matsShow == "yours" and L["None your professions use that trade enough yet. Show: All."] or L["No materials with prices yet."])
    f.list:SetItems(rows, true)
    local now = 0
    for _, x in ipairs(rows) do if x.rank == 0 then now = now + 1 end end
    f.count:SetText(now > 0 and FT.C("up", string.format(L["%d under their buy-below now"], now)) or "")
end

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
        dealsView:SetShown((deals and T.flipMode ~= "mats") or false)
        dealsView.kind:Hide()
        -- (v0.62) the age choice on the second row, under Deals now / Materials
        dealsView.ageLabel:ClearAllPoints()
        dealsView.ageLabel:SetPoint("TOPLEFT", 2, -40)
        dealsView.hint:ClearAllPoints()
        dealsView.hint:SetPoint("TOPLEFT", 0, -66)
        dealsView.hint:SetPoint("RIGHT", 0, 0)
        dealsView.box:ClearAllPoints()
        dealsView.box:SetPoint("TOPLEFT", 0, -84)
        dealsView.box:SetPoint("BOTTOMRIGHT", 0, 0)
    end
    if T.matsView then T.matsView:SetShown((deals and T.flipMode == "mats") or false) end
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
    f.box = box
    f.list = UI.List(box, {
        rowHeight = UI.RowH(46),
        setup = RowSetup,
        update = function(row, x)
            row.icon:SetItem(x.id)
            row.name:SetText(x.title or (FT.ItemText(x.id, 40) .. (x.qty and FT.C("dim", "  x" .. FT.Num(x.qty)) or "")))
            row.reason.fitText = nil -- (not a deal line fitted before)
            if x.fit then UI.FitBits(row.reason, x.reason or "") else row.reason:SetText(x.reason or "") end
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
    { "all", "All materials" }, { "ore", "Ore & stone" }, { "herb", "Herbs" }, { "leather", "Leather" }, { "cloth", "Cloth" },
    { "elemental", "Elemental" }, { "gem", "Gems" },
}
-- (v0.55) what Farm it shows: materials (their kind in a dropdown), Drops, Dungeons, Next week
local FARM_MODES = { { "all", "Materials" }, { "drops", "Drops" }, { "dungeons", "Dungeons" }, { "next", "Next week" } }
local farmMode = "all"
local dropSort, dropDungeon, dungeonMode = "price", nil, "full"
local FARM_CLASS = FT.Farm.CLASS -- the item classes and subclasses of each (FT.Farm)
local farmKind = "all"

local function FarmKindOf(r)
    -- (v0.50: crafted materials - bars, bolts, cured hides, transmutes - aren't farmed)
    if FT.Where and r.id and not FT.Where.Farmable(r.id) then return nil end
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

-- (v0.55) a dungeon's tooltip: what pays in it, the coin, the time
local function DungeonTip(row, x)
    local d = x.dungeonInfo
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(d.name, 1, 0.82, 0)
    GameTooltip:AddLine(string.format(L["Level %s  ·  the door is in %s"], d.lv, L[d.door] or d.door), 0.85, 0.87, 0.9)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine((dungeonMode == "trash" and L["The trash, steady"] or L["A run, steady"]), FT.Money(math.floor(d.steady), "gold"), 0.85, 0.87, 0.9, 1, 1, 1)
    if not d.solo then
        GameTooltip:AddDoubleLine(string.format(L["Each, in a group of %d"], 5), FT.Money(math.floor(d.each), "gold"), 0.85, 0.87, 0.9, 0.12, 1, 0.12)
    end
    GameTooltip:AddDoubleLine(L["Of it, coin"], FT.Money(math.floor(d.coin), "gold"), 0.6, 0.64, 0.7, 0.6, 0.64, 0.7)
    if d.jackpot > 0 then
        GameTooltip:AddDoubleLine(L["Rare drops, on average (not counted above)"], "+" .. FT.Money(math.floor(d.jackpot), "gold"), 0.95, 0.75, 0.3, 0.95, 0.75, 0.3)
    end
    for _, t in ipairs(d.top) do
        local n = t.n >= 10 and FT.Num(math.floor(t.n + 0.5)) or string.format("%.1f", t.n)
        GameTooltip:AddDoubleLine(FT.ItemText(t.id, 32) .. FT.C("dim", "  x" .. n .. (t.jackpot and ("  " .. L["rare"]) or "")),
            FT.Money(math.floor(t.worth), "short"), 1, 1, 1, t.jackpot and 0.95 or 0.85, t.jackpot and 0.75 or 0.87, t.jackpot and 0.3 or 0.9)
    end
    GameTooltip:AddLine(" ")
    if d.measured then
        GameTooltip:AddLine(string.format(L["Your own runs here: %s an hour"], FT.Money(math.floor(d.measured), "gold")), 0.12, 1, 0.12, true)
    else
        GameTooltip:AddLine(string.format(d.solo and L["About %d min a clear on your own: ~%s an hour. Run it with the session tracker on and Wolf measures it."]
            or L["About %d min a full clear of every wing: ~%s an hour each. Run it with the session tracker on and Wolf measures it."],
            d.min, FT.Money(math.floor(d.hour), "gold")), 0.6, 0.64, 0.7, true)
    end
    if d.hardSolo then
        GameTooltip:AddLine(L["Hard solo: under 8 levels below you, its elites hit back. Smaller pulls, and slower."], 1, 0.6, 0.18, true)
    end
    GameTooltip:AddLine(L["The average of its loot tables: a lucky epic beats it, a dry run doesn't."], 0.6, 0.64, 0.7, true)
    GameTooltip:AddLine(L["Click: its card - what a run is made of, its best loot"], 0.6, 0.64, 0.7)
    GameTooltip:Show()
end

local function BuildFarmView(p)
    local f = ListView(p, function(x, button)
        if x.dungeonInfo then
            -- (v0.61) a dungeon: its card (its whole drop list is a button there)
            FT.ShowDungeon(x.dungeonInfo, dungeonMode)
            return
        end
        if button == "RightButton" then UI.WatchMenu(x.id) return end
        if UI.ItemClick(x.id) then return end
        FT.ShowFarm(x.id)
    end, function(row, x)
        if x.dungeonInfo then DungeonTip(row, x) return end
        UI.TipItem(row, x.id)
        GameTooltip:AddLine(" ")
        if x.call then
            GameTooltip:AddLine(string.format(L["How sure: %d%% (right %d of %d weeks on its last 30 days)"], x.call.sure, x.call.hits, x.call.weeks), 0.85, 0.87, 0.9, true)
            if x.call.event then GameTooltip:AddLine(string.format(L["%s is on the calendar: a known pull."], x.call.event.name), 0.75, 0.78, 0.82, true) end
        end
        if x.drop and x.drop.others > 0 then
            GameTooltip:AddLine(string.format(L["%d more mobs drop it: its page lists them."], x.drop.others), 0.75, 0.78, 0.82, true)
        end
        GameTooltip:AddLine(L["Click: where to farm it || Right-click: watchlist"], 0.6, 0.64, 0.7)
        GameTooltip:Show()
    end)
    local modes = {}
    for _, k in ipairs(FARM_MODES) do modes[#modes + 1] = { k[1], L[k[2]] } end
    f.kind = UI.Segmented(f, modes, function(v)
        farmMode = v
        if v ~= "drops" then dropDungeon = nil end
        T.RefreshFarm()
        if FT.NavNote then FT.NavNote() end
    end, 22)
    f.kind:SetPoint("TOPLEFT", 0, -1)
    f.kind:SetValue(farmMode)
    T.farmKindBar = f.kind
    -- (v0.61) a dungeon's drops (its card's All its drops)
    function T.ShowDungeonDrops(name)
        dropDungeon, farmMode = name, "drops"
        f.kind:SetValue("drops")
        T.RefreshFarm()
        if FT.NavNote then FT.NavNote() end
    end
    -- (v0.61) Farm it's mode, for Back and Forward
    function T.FarmMode() return farmMode end
    function T.SetFarmMode(v) farmMode = v; if v ~= "drops" then dropDungeon = nil end; f.kind:SetValue(v); T.RefreshFarm(); if FT.NavNote then FT.NavNote() end end
    function T.FarmModeName(v) for _, k in ipairs(FARM_MODES) do if k[1] == v then return L[k[2]] end end return v end
    -- next to it, the choice of the mode: the kind of material / how drops sort / full clears or the trash
    local mats = {}
    for _, k in ipairs(FARM_KINDS) do mats[#mats + 1] = { k[1], L[k[2]] } end
    f.mat = UI.Dropdown(f, 130, mats, function(v)
        farmKind = v
        T.RefreshFarm()
    end)
    -- (v0.61) the mode's own choice on a second row, with its label: the sections stay alone on the first
    f.row2 = UI.Text(f, 12, "muted")
    f.row2:SetPoint("TOPLEFT", 2, -36)
    f.mat:SetPoint("LEFT", f.row2, "RIGHT", 10, 0)
    f.mat:SetValue(farmKind)
    f.sort = UI.Segmented(f, { { "price", L["Priciest"] }, { "hour", L["Per hour"] } }, function(v)
        dropSort = v
        T.RefreshFarm()
    end, 22)
    f.sort:SetPoint("LEFT", f.row2, "RIGHT", 10, 0)
    f.sort:SetValue(dropSort)
    f.trash = UI.Segmented(f, { { "full", L["Full clear"] }, { "trash", L["Trash only"] }, { "solo", L["Solo"] } }, function(v)
        dungeonMode = v
        T.RefreshFarm()
    end, 22)
    f.trash:SetPoint("LEFT", f.row2, "RIGHT", 10, 0)
    f.trash:SetValue("full")
    f.allDrops = UI.Button(f, L["All drops"], 80, 22, "default", function()
        dropDungeon = nil
        T.RefreshFarm()
    end)
    f.allDrops:FitText(16)
    f.allDrops:SetPoint("LEFT", f.sort, "RIGHT", 12, 0)
    f.hint:SetText(L["Raw materials by what one farmer could sell of them a day, best first. Click one: where to farm it for your level."])
    f.list:SetEmptyText(L["No sales seen yet: the price feed fills this over a few hours."])
    return f
end

-- (v0.55) Drops: mob drops that sell, with the mob, its zone and level, and the odds
local function DropRows()
    local list = FT.Drops.List(function() if farmView and farmView:IsShown() and farmMode == "drops" then T.RefreshFarm() end end)
    if not list then return nil end
    local out = {}
    for _, e in ipairs(FT.Drops.Shown(list, dropSort, dropDungeon, FT.NameMatcher(T.search))) do
        local w = e.who
        local bits = { w.name }
        local where = e.dungeon or (w.zones and w.zones:match("^[^,]+"))
        if where then bits[#bits + 1] = L[where] or where end
        if w.lv then bits[#bits + 1] = string.format(L["level %s"], w.lv) .. (FT.Drops.Elite(w) and (" " .. L["elite"]) or "") end
        bits[#bits + 1] = FT.Drops.Odds(e.chance) or FT.C("accent", L["rate unknown"])
        if e.rare then bits[#bits + 1] = FT.C("accent", L["a rare spawn: up now and then"]) end
        if (e.ch7 or 0) <= -0.15 then bits[#bits + 1] = FT.C("down", FT.Pct(e.ch7) .. " " .. L["this week"]) end
        if e.note then bits[#bits + 1] = FT.C("orange", e.note) end
        local value
        if dropSort == "hour" then
            value = e.perHour and (FT.C("up", "~" .. FT.Money(math.floor(e.perHour + 0.5), "short")) .. FT.C("dim", " " .. L["an hour"]))
                or FT.C("dim", FT.Money(e.price, "short") .. " " .. L["each"])
        else
            value = FT.C("up", FT.Money(e.price, "short")) .. FT.C("dim", " " .. L["each"])
        end
        out[#out + 1] = {
            id = e.id, drop = e, fit = true, reason = table.concat(bits, FT.C("dim", "  ·  ")), value = value,
            signal = "FARM", label = e.rare and L["RARE SPAWN"] or (e.group and L["GROUP"] or L["SOLO"]), strength = e.chance > 0 and 2 or 1,
        }
    end
    return out
end

-- (v0.55) Dungeons: each one's average clear at today's prices, split five ways
local function DungeonRows()
    local q = (T.search or ""):lower()
    local out = {}
    for _, d in ipairs(FT.Drops.Dungeons(dungeonMode)) do
        if q == "" or d.name:lower():find(q, 1, true) then
            local names = {}
            for i = 1, math.min(3, #d.top) do names[#names + 1] = FT.Name(d.top[i].id) or "?" end
            local bits = { string.format(L["level %s"], d.lv), L[d.door] or d.door }
            if d.jackpotEach >= 10000 then bits[#bits + 1] = FT.C("accent", "+" .. FT.Money(math.floor(d.jackpotEach), "gold") .. " " .. L["in rare drops"]) end
            if #names > 0 then bits[#bits + 1] = table.concat(names, ", ") end
            out[#out + 1] = {
                id = d.top[1] and d.top[1].id, title = FT.C("text", d.name), dungeonInfo = d, fit = true,
                reason = table.concat(bits, FT.C("dim", "  ·  ")),
                value = FT.C("up", "~" .. FT.Money(math.floor(d.each), "gold")) .. FT.C("dim", " " .. (d.solo and L["a run"] or L["each"])),
                signal = "FARM", label = d.hardSolo and L["HARD SOLO"] or string.format(L["~%d MIN"], d.min), strength = d.high and 1 or 2,
            }
        end
    end
    return out
end
T.DropRows, T.DungeonRows = DropRows, DungeonRows

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

-- (v0.51) Next week: the best farms for next week, each with how sure Wolf is (from Coming up, which came apart)
local function NextWeekRows()
    local l = FT.Ahead.Lists(function() if farmView and farmView:IsShown() and farmMode == "next" then T.RefreshFarm() end end)
    if not l then return nil end
    local out = {}
    for _, r in ipairs(l.farms) do
        local c = r.call
        local bits = {}
        if r.hour then bits[#bits + 1] = "~" .. FT.Money(math.floor(r.hour), "gold") .. " " .. L["an hour"] .. (r.where and (" " .. string.format(L["in %s"], r.where)) or "") end
        bits[#bits + 1] = FT.C(c.move >= 0 and "up" or "down", (c.move >= 0 and "+" or "") .. FT.An.Pc(c.move)) .. FT.C("dim", " " .. L["next week"])
        if c.why then bits[#bits + 1] = c.why end
        out[#out + 1] = { id = r.id, reason = table.concat(bits, FT.C("dim", "  ·  ")), call = c,
            value = FT.Ahead.SureText(c.sure), signal = "FARM", label = L["FARM"], strength = 2 }
    end
    return out
end

function T.RefreshFarm()
    if not (farmView and farmView:IsShown()) then return end
    local f = farmView
    f.mat:SetShown(farmMode == "all")
    f.sort:SetShown(farmMode == "drops")
    f.trash:SetShown(farmMode == "dungeons")
    f.allDrops:SetShown(farmMode == "drops" and dropDungeon ~= nil)
    -- (v0.61) two rows: the sections, then this mode's own choice (Next week has none: the list moves up)
    local two = farmMode ~= "next"
    f.row2:SetShown(two)
    f.row2:SetText((farmMode == "all" and L["What you gather"]) or (farmMode == "drops" and L["Sort by"]) or L["How you run it"])
    local top = two and 34 or 0
    f.hint:ClearAllPoints()
    f.hint:SetPoint("TOPLEFT", 0, -32 - top)
    f.hint:SetPoint("RIGHT", 0, 0)
    f.box:ClearAllPoints()
    f.box:SetPoint("TOPLEFT", 0, -50 - top)
    f.box:SetPoint("BOTTOMRIGHT", 0, 0)
    f.count:SetText("")
    if farmMode == "next" then
        local rows = NextWeekRows()
        f.hint:SetText(L["Next week's best farms, and how sure Wolf is: its record on each item's last 30 days. Under 40% isn't shown."])
        f.list:SetEmptyText(rows and L["No call sure enough yet: new prices come every hour."] or L["Working out next week's calls..."])
        f.list:SetItems(rows or {}, true)
        return
    end
    if farmMode == "drops" then
        local rows = DropRows()
        f.hint:SetText(dropDungeon and string.format(L["What drops in %s and sells, best first."], dropDungeon)
            or L["Drops you can farm, and the mob. No world drops: any mob can give those."])
        f.list:SetEmptyText(rows and L["No drop sells for a gold or more yet: the price feed fills this over a few hours."] or L["Working out the drops..."])
        f.count:SetText(rows and #rows > 0 and string.format(L["%d drops"], #rows) or "")
        f.list:SetItems(rows or {}, true)
        return
    end
    if farmMode == "dungeons" then
        local rows = DungeonRows()
        local hint
        if dungeonMode == "solo" then
            local _, class = UnitClass and UnitClass("player")
            local cls = class and FT.Drops.SOLO_CLASSES[class]
            hint = L["Solo: all the loot is yours, but it's hard - for a geared class that holds big pulls (warrior, paladin, druid, warlock, mage)."]
                .. (class and not cls and (" " .. L["Your class will find it slow."]) or "")
        elseif dungeonMode == "trash" then
            hint = L["The trash only (no bosses): the steady gold of a run, split five ways."]
        else
            hint = L["Each run's steady gold at today's prices, split five ways; rare drops apart. Click one: its card."]
        end
        f.hint:SetText(hint)
        f.list:SetEmptyText(dungeonMode == "solo" and L["No dungeon is far enough under your level to solo yet."] or L["No dungeon found."])
        f.count:SetText(string.format(L["%d dungeons"], #rows))
        f.list:SetItems(rows, true)
        return
    end
    f.hint:SetText(L["Raw materials by what one farmer could sell of them a day, best first. Click one: where to farm it for your level."])
    f.list:SetEmptyText(L["No sales seen yet: the price feed fills this over a few hours."])
    local list = FarmRows()
    local matches = FT.NameMatcher(T.search)
    if matches then
        local kept = {}
        for _, x in ipairs(list) do if matches(x.id) then kept[#kept + 1] = x end end
        list = kept
    end
    f.list:SetItems(list, true)
end
FT.On("FT_DROPS_READY", function() if farmMode == "drops" then T.RefreshFarm() end end)

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
    -- v0.50: the section bar in the same spot on every Make gold and You page (top left); the line under it
    T.title = UI.Text(head, 16, "text")
    T.title:SetText(L["Money"])
    T.title:Hide()
    T.rules = UI.Text(head, 11, "dim")
    T.rules:SetPoint("TOPLEFT", 4, -28)
    T.rules:SetPoint("RIGHT", head, "RIGHT", -8, 0)

    -- the search, next to the title: every column keeps only what matches ("name" in quotes: that name exactly)
    T.search = ""
    T.searchBox = UI.Input(head, 220, 22, L["Filter this list..."], function(text)
        T.search = text or ""
        FT.Debounce("signalsSearch", 0.25, T.Refresh)
    end)
    T.searchBox:SetPoint("TOPRIGHT", head, "TOPRIGHT", -4, 0)
    UI.ClearButton(T.searchBox, function()
        T.search = ""
        T.Refresh()
    end)
    -- one way to make gold per view; Signals: the four columns
    T.view = T.view or "make"
    T.viewSeg = UI.GroupBar(head, "make")
    T.viewSeg:SetPoint("TOPLEFT", head, "TOPLEFT", 4, 0)
    T.viewSeg:SetValue(T.view)
    dealsView = BuildDeals(p)
    farmView = BuildFarmView(p)
    -- (v0.62) Flip it > Materials
    do
        local f = ListView(p, function(x) if x.id then FT.OpenItem(x.id) end end, function(row, x)
            if x and x.id then UI.TipItem(row, x.id) end
        end)
        f:Hide()
        if f.kind then f.kind:Hide() end
        f.mode = UI.Segmented(f, { { "deals", L["Deals now"] }, { "mats", L["Materials"] } }, function(v) T.SetFlipMode(v) end, 22)
        f.mode:SetPoint("TOPLEFT", 0, -1)
        f.mode:SetValue("mats")
        f.row2 = UI.Text(f, 12, "muted")
        f.row2:SetPoint("TOPLEFT", 2, -40)
        f.row2:SetText(L["Show"])
        f.show = UI.Segmented(f, { { "yours", L["What your professions use"] }, { "all", L["All"] } }, function(v)
            matsShow = v
            T.RefreshMats()
        end, 22)
        f.show:SetPoint("LEFT", f.row2, "RIGHT", 10, 0)
        f.show:SetValue(matsShow)
        f.hint:ClearAllPoints()
        f.hint:SetPoint("TOPLEFT", 0, -66)
        f.hint:SetPoint("RIGHT", 0, 0)
        f.hint:SetText(L["Buy below its line and it's cheap for that item: under its usual by your Buy-below setting. Click one: its page."])
        f.box:ClearAllPoints()
        f.box:SetPoint("TOPLEFT", 0, -84)
        f.box:SetPoint("BOTTOMRIGHT", 0, 0)
        T.matsView = f
        f:HookScript("OnShow", function() T.RefreshMats() end)
    end
    craftView = BuildCraftView(p)
    -- the deals are looked for again on new prices only while they are on the screen (Sell yours and the
    -- line under the title use them too)
    FT.Deals.watching = function() return dealsView:IsVisible() or (T.rules and T.rules:IsVisible()) end
end

function T.Refresh()
    FT.Deals.Ensure()
    local best = BestMove()
    if DEAL_VIEWS[T.view] or T.view == "sell" or T.view == "farm" or T.view == "craft" then
        T.rules:SetText(best or FT.C("dim", L["No deal right now: the list fills as prices come in."]))
        if DEAL_VIEWS[T.view] then if T.flipMode == "mats" then T.RefreshMats() else T.RefreshDeals() end end
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
