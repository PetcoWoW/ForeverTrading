-- Wolf: the auction house tab. Four views:
--  * This visit: what you bought, posted and took off since you opened the auction house - each with its price
--    and how it compares with usual - and the totals (FT.AHVisit).
--  * Watchlist: your watched items as the live searches see them - price now, usual, how many under it - and Buy.
--  * Deals: right after a scan, what's listed under its snipe price (with how sure, and Buy), and the items worth
--    searching again and again. Re-check searches them again without a new full scan.
--  * Past visits: the last 30, each with what it came to.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local P = {}
FT.SnipePanel = P

local panel
local MAX_RECHECK = 30

local function Chip(parent)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(58, 16)
    c.bg = UI.RoundTex(c, "BACKGROUND", "muted", 0.2)
    c.bg:SetAllPoints()
    c.text = UI.Text(c, 10, "muted", "CENTER")
    c.text:SetPoint("CENTER")
    function c:Set(conf)
        local col = FT.Snipe.CONF_COLORS[conf] or "muted"
        UI.SetTexColor(self.bg, col, 0.22)
        UI.SetTextColor(self.text, col)
        self.text:SetText(L[FT.Snipe.CONF_TEXT[conf] or "?"])
    end
    return c
end

-- a row: icon, name over a line of numbers, on the right a chip and a button
local function RowSetup(row)
    row.icon = UI.Icon(row, 26)
    row.icon:SetPoint("LEFT", 8, 0)
    row.name = UI.Text(row, 12, "text")
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 42, -6)
    row.name:SetPoint("RIGHT", row, "RIGHT", -140, 0)
    row.line = UI.Text(row, 11, "dim")
    row.line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 42, 6)
    row.line:SetPoint("RIGHT", row, "RIGHT", -140, 0)
    row.chip = Chip(row)
    row.chip:SetPoint("RIGHT", row, "RIGHT", -64, 0)
    row.buy = UI.Button(row, L["Buy"], 50, 20, "primary", function() end)
    row.buy:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.sep = UI.HLine(row, "line", 0.5)
    row.sep:SetPoint("BOTTOMLEFT", 8, 0)
    row.sep:SetPoint("BOTTOMRIGHT", -8, 0)
end

local function Box(parent, title)
    local b = UI.Panel(parent, "bg1", "line")
    b.title = UI.Text(b, 13, "text")
    b.title:SetPoint("TOPLEFT", 10, -8)
    b.title:SetText(title)
    b.count = UI.Text(b, 11, "dim", "RIGHT")
    b.count:SetPoint("TOPRIGHT", -10, -9)
    return b
end

local VIEWS = { { "visit", L["This visit"] }, { "watch", L["Watchlist"] }, { "deals", L["Deals"] }, { "past", L["Past visits"] } }

local function Build(parent)
    local f = CreateFrame("Frame", "WolfOfBootyBaySnipe", parent)
    UI.ResolveFont()
    -- over the auction house's own page: dark and solid (the classic look: with the tooltip's gold edge)
    if UI.Classic() then UI.Skin(f, "popup", "bg0", 0.97) else UI.Fill(f, "bg0", 0.97) end
    f.head = UI.Text(f, 15, "accent")
    f.head:SetPoint("TOPLEFT", 12, -10)
    f.head:SetText(L["Wolf"])
    f.seg = UI.Segmented(f, VIEWS, function(v) P.SetView(v) end, 22)
    f.seg:SetPoint("LEFT", f.head, "RIGHT", 14, 0)
    f.sub = UI.Text(f, 11, "dim")
    f.sub:SetPoint("TOPLEFT", 12, -38)
    f.open = UI.Button(f, L["Open Wolf"], 10, 22, "default", function() FT.Show("market") end)
    f.open:FitText(20)
    f.open:SetPoint("TOPRIGHT", -10, -32)
    f.toAtr = UI.Button(f, L["To Auctionator"], 10, 22, "default", function()
        local ids = {}
        if P.view == "watch" then
            for id in pairs(FT.db.watch or {}) do ids[#ids + 1] = id end
            FT.ToAuctionator(L["Wolf: Watchlist"], ids)
            return
        end
        for _, x in ipairs((FT.Snipe.Now())) do ids[#ids + 1] = x.id end
        for _, x in ipairs(FT.Snipe.Often()) do ids[#ids + 1] = x.id end
        FT.ToAuctionator(L["Wolf: Snipe"], ids)
    end)
    f.toAtr:FitText(20)
    f.toAtr:SetPoint("RIGHT", f.open, "LEFT", -6, 0)
    f.toAtr:SetTip(L["To Auctionator"], L["The list on screen as an Auctionator shopping list."])
    f.recheck = UI.Button(f, L["Re-check"], 10, 22, "primary", function() P.Recheck() end)
    f.views = {}
    f.recheck:FitText(20)
    f.recheck:SetPoint("RIGHT", f.toAtr, "LEFT", -6, 0)
    f.recheck:SetTip(L["Re-check"], L["Searches just the items in both lists again (no full scan): what's cheap right now."])
    f.sub:SetPoint("RIGHT", f.recheck, "LEFT", -12, 0)

    -- Deals
    local deals = CreateFrame("Frame", nil, f)
    f.views.deals = deals
    f.now = Box(deals, L["Underpriced now"])
    f.often = Box(deals, L["Often underpriced"])
    f.now.list = UI.List(f.now, {
        rowHeight = UI.RowH(44), setup = RowSetup,
        update = function(row, x)
            row.icon:SetItem(x.id)
            row.name:SetText(FT.ItemText(x.id, 40))
            row.line:SetText(FT.C("up", FT.Money(x.price, "short")) .. FT.C("dim", "  ·  " .. L["normally"] .. " ")
                .. FT.Money(math.floor(x.fair), "short") .. FT.C("dim", "  ·  ") .. FT.Pct(x.off)
                .. (x.listed and FT.C("dim", "  ·  " .. string.format(L["%s listed"], FT.Num(x.listed))) or ""))
            row.chip:Set(x.conf)
            row.buy:Show()
            row.buy:SetLabel((x.qty or 1) > 1 and string.format(L["Buy %s"], FT.Num(x.qty)) or L["Buy"])
            row.buy:FitText(14)
            row.buy.onClick = function() FT.Buy.Start(x.id, x.qty or 1, x.price) end
        end,
        onClick = function(x) if not UI.ItemClick(x.id) then FT.OpenItem(x.id) end end,
        onEnter = function(row, x)
            UI.TipItem(row, x.id)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(string.format(L["Buy at or under %s (its real price %s, less %d%%)."], FT.Money(x.under), FT.Money(math.floor(x.fair)),
                FT.S.dealBelow or 30), 0.85, 0.87, 0.9, true)
            GameTooltip:AddLine(L[FT.Snipe.CONF_TEXT[x.conf]] .. ": " .. x.why, 0.85, 0.87, 0.9, true)
            GameTooltip:AddLine(string.format(L["Sold again at its real price: about %s each after the cut."], FT.Money(math.floor(x.gain))), 0.4, 0.85, 0.5, true)
            GameTooltip:AddLine(L["Buy: the server's exact price first, then your OK. Click: the item's page."], 0.6, 0.64, 0.7, true)
            GameTooltip:Show()
        end,
    })
    f.often.list = UI.List(f.often, {
        rowHeight = UI.RowH(44), setup = RowSetup,
        update = function(row, x)
            row.icon:SetItem(x.id)
            row.name:SetText(FT.ItemText(x.id, 30))
            row.line:SetText(x.under and (L["under"] .. " " .. FT.Money(x.under, "short") .. FT.C("dim", "  ·  "
                .. string.format(L["back %d/%d"], x.ok, x.n))) or string.format(L["back %d/%d"], x.ok, x.n))
            row.chip:Set(x.hit and "safe" or "good")
            row.chip.text:SetText(x.hit and L["CHEAP NOW"] or (x.price and FT.Money(x.price, "short") or "—"))
            row.buy:SetShown(x.hit and true or false)
            row.buy:SetLabel(L["Buy"])
            row.buy:FitText(14)
            row.buy.onClick = function() FT.Buy.Start(x.id, 1, x.price) end
        end,
        onClick = function(x) if not UI.ItemClick(x.id) then FT.OpenItem(x.id) end end,
        onEnter = function(row, x)
            UI.TipItem(row, x.id)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(string.format(L["Dipped 30%%+ under its usual price %d times; came back within 3 days %d times. Worth searching often."], x.n, x.ok), 0.85, 0.87, 0.9, true)
            GameTooltip:Show()
        end,
    })
    f.now.list:SetEmptyText(L["Scan first (Auctionator's Full Scan or ours): what's listed under its price shows here."])
    f.often.list:SetEmptyText(L["Fills after a day: the items whose deep dips came back most times."])

    UI.OnSize(deals, function(self, w, h)
        local lw = math.floor((w - 10) * 0.5)
        f.now:ClearAllPoints()
        f.now:SetPoint("TOPLEFT", 0, 0)
        f.now:SetPoint("BOTTOMLEFT", 0, 0)
        f.now:SetWidth(lw)
        f.often:ClearAllPoints()
        f.often:SetPoint("TOPLEFT", f.now, "TOPRIGHT", 10, 0)
        f.often:SetPoint("BOTTOMRIGHT", 0, 0)
    end)

    P.BuildVisit(f)
    P.BuildWatch(f)
    P.BuildPast(f)
    for _, v in pairs(f.views) do
        v:SetPoint("TOPLEFT", 10, -62)
        v:SetPoint("BOTTOMRIGHT", -10, 10)
        v:Hide()
    end
    for _, b in ipairs({ f.now, f.often }) do
        b.list:SetPoint("TOPLEFT", 1, -30)
        b.list:SetPoint("BOTTOMRIGHT", -1, 4)
    end
    f:SetScript("OnShow", function() P.Refresh() end)
    return f
end

---------------------------------------------------------------------------
-- This visit: a log, newest first, and its totals
---------------------------------------------------------------------------
local KIND = { B = { "BOUGHT", "up" }, P = { "POSTED", "accent" }, C = { "TOOK OFF", "muted" } }

local function NameCell(row)
    local c = CreateFrame("Frame", nil, row)
    c:SetHeight(24)
    c.icon = UI.Icon(c, 18)
    c.icon:SetPoint("LEFT")
    c.text = UI.Text(c, 12, "text")
    c.text:SetPoint("LEFT", c.icon, "RIGHT", 6, 0)
    c.text:SetPoint("RIGHT")
    return c
end

local function EventList(parent)
    local cols = {
        { key = "t", title = L["Time"], width = 64, size = 11 },
        { key = "k", title = "", width = 76, size = 11 },
        { key = "name", title = L["Item"], width = "fill", make = NameCell, cellHeight = 24 },
        { key = "q", title = L["Qty"], width = 54, justify = "RIGHT", size = 11 },
        { key = "u", title = L["Each"], width = 90, justify = "RIGHT", size = 11 },
        { key = "vs", title = L["vs usual"], width = 70, justify = "RIGHT", size = 11 },
    }
    local header = UI.Header(parent, cols)
    local list = UI.List(parent, {
        rowHeight = 26, cols = cols,
        update = function(row, e)
            row.cells.t:SetText(FT.C("dim", date("%H:%M", e.t)))
            local k = KIND[e.k] or { e.k, "muted" }
            row.cells.k:SetText(FT.C(k[2], L[k[1]]))
            row.cells.name.icon:SetItem(e.id)
            row.cells.name.text:SetText(FT.ItemText(e.id))
            row.cells.q:SetText(FT.Num(e.q))
            row.cells.u:SetText(e.u and FT.Money(e.u, "short") or FT.C("dim", "—"))
            -- against usual: under it is green when you bought, over it is green when you posted
            local vs = (e.u and e.usual and e.usual > 0) and (e.u / e.usual - 1) or nil
            if vs then
                local good = (e.k == "B") and vs <= 0 or (e.k ~= "B" and vs >= 0)
                row.cells.vs:SetText(FT.C(good and "up" or "down", FT.Pct(vs, true)))
            else
                row.cells.vs:SetText(FT.C("dim", "—"))
            end
        end,
        onClick = function(e) if not UI.ItemClick(e.id) then FT.OpenItem(e.id) end end,
        onEnter = function(row, e) UI.TipItem(row, e.id) end,
    })
    return header, list
end

function P.BuildVisit(f)
    local v = CreateFrame("Frame", nil, f)
    f.views.visit = v
    v.header, v.list = EventList(v)
    v.header:SetPoint("TOPLEFT", 0, 0)
    v.header:SetPoint("TOPRIGHT", 0, 0)
    v.list:SetPoint("TOPLEFT", v.header, "BOTTOMLEFT", 0, -2)
    v.list:SetPoint("BOTTOMRIGHT", 0, 0)
    v.list:SetEmptyText(L["Buy, post or take something off: it shows here with its price against usual (whatever window you use)."])
end

local function SumText(s, v)
    local bits = {}
    bits[#bits + 1] = s.bought > 0 and (string.format(L["bought %d (%s)"], s.bought, FT.Money(math.floor(s.spent), "short"))
        .. (s.vsUsual and (" " .. FT.C(s.vsUsual <= 0 and "up" or "down", FT.Pct(s.vsUsual, true)) .. FT.C("dim", " " .. L["vs usual"])) or "")) or FT.C("dim", L["nothing bought"])
    bits[#bits + 1] = s.postedQty > 0 and string.format(L["posted %s (%s)"], FT.Num(s.postedQty), FT.Money(math.floor(s.posted), "short"))
        or FT.C("dim", L["nothing posted"])
    if s.cancelled > 0 then bits[#bits + 1] = string.format(L["took off %d"], s.cancelled) end
    if v and v.gold0 then
        local net = (v.gold1 or GetMoney()) - v.gold0
        bits[#bits + 1] = L["gold"] .. " " .. FT.C(net >= 0 and "up" or "down", FT.SignedMoney(net))
    end
    return table.concat(bits, FT.C("dim", "  ·  "))
end
P.SumText = SumText

---------------------------------------------------------------------------
-- Watchlist, live
---------------------------------------------------------------------------
function P.BuildWatch(f)
    local v = CreateFrame("Frame", nil, f)
    f.views.watch = v
    v.list = UI.List(v, {
        rowHeight = UI.RowH(44), setup = RowSetup,
        update = function(row, x)
            row.icon:SetItem(x.id)
            row.name:SetText(FT.ItemText(x.id, 40) .. FT.C("dim", "  " .. x.group))
            local bits = {}
            bits[#bits + 1] = x.price and (L["now"] .. " " .. FT.Money(x.price, "short")) or FT.C("dim", L["no price yet"])
            if x.usual then bits[#bits + 1] = L["usual"] .. " " .. FT.Money(math.floor(x.usual), "short") end
            if x.deal then bits[#bits + 1] = FT.C("up", string.format(L["%s under %s"], FT.Num(x.deal.n), FT.Money(x.deal.under, "short"))) end
            if FT.Scanner.LiveOn(x.id) then bits[#bits + 1] = FT.C("up", L["live"]) end
            row.line:SetText(table.concat(bits, FT.C("dim", "  ·  ")))
            if x.deal then
                row.chip:Set("safe")
                row.chip.text:SetText(L["DEAL"])
            else
                row.chip:Set("good")
                row.chip.text:SetText(x.vs and (x.vs >= 0 and "+" or "") .. math.floor(x.vs * 100 + 0.5) .. "%" or "—")
            end
            row.buy:SetShown(x.deal ~= nil)
            row.buy:SetLabel(x.deal and FT.Buy.IsCommodity(x.id) and string.format(L["Buy %s"], FT.Num(x.deal.n)) or L["Buy"])
            row.buy:FitText(14)
            row.buy.onClick = function() FT.AHVisit.BuyDeal(x.id) end
        end,
        onClick = function(x) if not UI.ItemClick(x.id) then FT.OpenItem(x.id) end end,
        onEnter = function(row, x)
            UI.TipItem(row, x.id)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["At the auction house your watched items take turns in the live searches: one listed 15% or more under its usual price is a deal (and said in chat)."], 0.85, 0.87, 0.9, true)
            GameTooltip:Show()
        end,
    })
    v.list:SetAllPoints()
    v.list:SetEmptyText(L["Nothing on your watchlist: watch items from their page (Watch) or a craft's materials (Watch all)."])
end

function P.WatchRows()
    local out = {}
    for id in pairs(FT.db.watch or {}) do
        local s = FT.An.Stats(id)
        local usual = s and ((s.avg and s.fair and math.min(s.avg, s.fair)) or s.fair or s.avg)
        out[#out + 1] = { id = id, price = s and s.price, usual = usual, deal = FT.AHVisit.WatchDeal(id),
            vs = (s and s.price and usual and usual > 0) and (s.price / usual - 1) or nil, group = (FT.Market.GroupOf(id)) }
    end
    table.sort(out, function(a, b)
        if (a.deal ~= nil) ~= (b.deal ~= nil) then return a.deal ~= nil end
        if a.group ~= b.group then return a.group < b.group end
        return a.id < b.id
    end)
    return out
end

---------------------------------------------------------------------------
-- Past visits
---------------------------------------------------------------------------
function P.BuildPast(f)
    local v = CreateFrame("Frame", nil, f)
    f.views.past = v
    v.list = UI.List(v, {
        rowHeight = UI.RowH(44), setup = RowSetup,
        update = function(row, x)
            row.icon:SetItem(x.events[1] and x.events[1].id)
            local mins = math.max(1, math.floor(((x.stop or time()) - x.start) / 60 + 0.5))
            row.name:SetText(date("%a %m/%d  %H:%M", x.start) .. FT.C("dim", "  " .. string.format(L["%d min"], mins)))
            row.line:SetText(SumText(FT.AHVisit.Sum(x), x))
            row.chip:Hide()
            row.buy:Hide()
        end,
        onClick = function(x) P.ShowVisit(x) end,
        onEnter = function(row, x)
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["Click: what you did on that visit"], 1, 1, 1)
            GameTooltip:Show()
        end,
    })
    v.list:SetAllPoints()
    v.list:SetEmptyText(L["Your last 30 auction house visits show here: what you bought and posted, and your gold."])
end

-- a past visit in the This visit view (its log), until you pick This visit again
function P.ShowVisit(x)
    P.shownVisit = x
    P.SetView("visit")
end

-- the panel inside the auction house (parent: the tab's frame), or beside it
function P.Get(parent)
    if not panel then panel = Build(parent or UIParent) end
    return panel
end

function P.SetView(view)
    P.view = view
    if not panel then return end
    if view ~= "visit" then P.shownVisit = nil end
    panel.seg:SetValue(view)
    for k, v in pairs(panel.views) do v:SetShown(k == view) end
    local deals = view == "deals"
    panel.recheck:SetShown(deals)
    panel.toAtr:SetShown(deals or view == "watch")
    P.Refresh()
end

function P.Refresh()
    if not (panel and panel:IsShown()) then return end
    if not P.view then
        -- at the auction house: this visit once something happened, else your watchlist (deals first)
        P.view = (FT.AHVisit.Current() and #FT.AHVisit.Current().events > 0) and "visit" or (next(FT.db.watch or {}) and "watch" or "deals")
        return P.SetView(P.view)
    end
    if P.view == "visit" then
        local v = P.shownVisit or FT.AHVisit.Current()
        local events = {}
        for i = #(v and v.events or {}), 1, -1 do events[#events + 1] = v.events[i] end
        panel.views.visit.list:SetItems(events, true)
        if not v then
            UI.FitBits(panel.sub, L["Open the auction house: this visit starts then."])
        else
            local when = P.shownVisit and date("%a %m/%d %H:%M", v.start) or string.format(L["Since %s"], date("%H:%M", v.start))
            UI.FitBits(panel.sub, when .. FT.C("dim", ":  ") .. SumText(FT.AHVisit.Sum(v), v))
        end
        return
    elseif P.view == "watch" then
        local rows = P.WatchRows()
        panel.views.watch.list:SetItems(rows, true)
        local deals = 0
        for _, x in ipairs(rows) do if x.deal then deals = deals + 1 end end
        UI.FitBits(panel.sub, FT.ahOpen and (deals > 0 and string.format(L["%d of your watched items listed well under usual: Buy."], deals)
            or L["Your watched items, searched live while you're here. A deal is said in chat."]) or L["Open the auction house to search them live."])
        return
    elseif P.view == "past" then
        panel.views.past.list:SetItems(FT.AHVisit.Past(), true)
        UI.FitBits(panel.sub, L["Your last auction house visits: click one for what you did."])
        return
    end
    local list, at, busy = FT.Snipe.Now()
    local scan = FT.ScanTime and FT.ScanTime()
    UI.FitBits(panel.sub, busy and L["Looking..."] or (scan and string.format(L["From your scan %s: buy what's under its price, the surest first."], FT.Ago(scan))
        or L["Scan the auction house first."]))
    panel.now.list:SetItems(list, true)
    panel.now.count:SetText(#list > 0 and tostring(#list) or "")
    local often = FT.Snipe.Often()
    panel.often.list:SetItems(often, true)
    local hits = 0
    for _, x in ipairs(often) do if x.hit then hits = hits + 1 end end
    panel.often.count:SetText(hits > 0 and string.format(L["%d cheap now"], hits) or "")
end

-- both lists searched again, no full scan
function P.Recheck()
    if not FT.ahOpen then
        FT.Print(FT.House.Why(L["Talk to an auctioneer to check the order books."]))
        return
    end
    local ids, seen = {}, {}
    for _, x in ipairs((FT.Snipe.Now())) do if not seen[x.id] then seen[x.id] = true; ids[#ids + 1] = x.id end end
    for _, x in ipairs(FT.Snipe.Often()) do if not seen[x.id] then seen[x.id] = true; ids[#ids + 1] = x.id end end
    while #ids > MAX_RECHECK do table.remove(ids) end
    if #ids == 0 then return end
    FT.Scanner.StartMine(false, ids)
end

-- the panel if it was made (nil: never opened)
function P.Panel() return panel end

-- how many are underpriced now (the tab's label)
function P.Count()
    return #(FT.Snipe.Now())
end

FT.On("FT_SNIPE_READY", function() P.Refresh() end)
FT.On("FT_AH_VISIT", function() P.Refresh() end)
FT.On("FT_WATCH_CHANGED", function() P.Refresh() end)
FT.On("FT_LIVE_UPDATED", function(id) if P.view == "watch" and FT.db.watch[id] then FT.Debounce("ahWatch", 0.5, P.Refresh) end end)
FT.On("FT_SCAN_DONE", function(kind) if kind == "mine" then FT.Snipe.Build() end end)
FT.On("FT_LEARNED", function() P.Refresh() end)
