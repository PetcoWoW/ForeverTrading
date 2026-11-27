-- Wolf: Today, the first page (v0.42). What everything you own is worth and what the last price update did to it;
-- then two rows on the same three columns: Your top 3, and under them In your bags, Going down today and Going up
-- today (each scrolls). Tried first in Wolf Lab.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local T = {}
FT.Tabs.today = T

local PAD, GAP = 12, 10
local built

---------------------------------------------------------------------------
-- Your top 3: the wolf's moves for you (FT.Eye); short of three, today's market fills in (a flip, the best thing to
-- farm, a craft, a disenchant, a vendor deal). Also what the Market page's old overview showed.
---------------------------------------------------------------------------
function FT.TopMoves()
    local cards, shown = {}, {}
    local okEye, moves = pcall(FT.Eye.Moves, 3)
    if okEye then
        for _, m in ipairs(moves or {}) do
            cards[#cards + 1] = { id = m.id, kind = m.kind, label = m.label, gold = m.value or "", what = m.text, tip = m.why }
            shown[m.id] = true
        end
    end
    local personal = #cards
    local best = {}
    for _, d in ipairs(FT.Deals.List() or {}) do
        if not best[d.kind] or d.profit > best[d.kind].profit then best[d.kind] = d end
    end
    local flip = best.RESELL
    if #cards < 3 and flip and not shown[flip.id] then
        cards[#cards + 1] = { id = flip.id, kind = "RESELL", label = "FLIP IT", gold = "+" .. FT.Money(math.floor(flip.profit), "gold"),
            what = string.format(L["%s: under its usual price, sells every day"], FT.ItemText(flip.id, 24)) }
        shown[flip.id] = true
    end
    local farm = FT.Tabs.signals and FT.Tabs.signals.FarmRows and FT.Tabs.signals.FarmRows()
    local f1 = farm and farm[1]
    if #cards < 3 and f1 and not shown[f1.id] then
        cards[#cards + 1] = { id = f1.id, kind = "FARM", label = "FARM IT", gold = FT.Money(f1.price or 0, "short") .. FT.C("dim", " " .. L["each"]),
            what = string.format(L["%s: sells ~%s a day"], FT.ItemText(f1.id, 24), FT.Num(math.floor((f1.perDay or 0) + 0.5))),
            tip = string.format(L["One farmer selling a share of each day's sales makes about %s a day from it."], FT.Money(math.floor(f1.yours or 0), "gold")) }
        shown[f1.id] = true
    end
    if #cards < 3 then
        local crafts = FT.Craft.ProfitCrafts and FT.Craft.ProfitCrafts()
        local c = crafts and crafts[1]
        if c and not shown[c.id] then
            cards[#cards + 1] = { id = c.id, kind = "CRAFT", label = c.mode == "de" and "CRAFT + DE" or "CRAFT IT",
                gold = "+" .. FT.Money(math.floor(c.profit), "gold"), what = string.format(L["%s: %s"], FT.ItemText(c.id, 24), L[c.recipe.prof or "?"]) }
            shown[c.id] = true
        end
    end
    if #cards < 3 then
        local de = FT.Enchant and FT.Enchant.Deals()
        local d = de and de[1]
        if d and not shown[d.id] then
            cards[#cards + 1] = { id = d.id, kind = "DE", label = "DE IT", gold = "+" .. FT.Money(math.floor(d.profit), "gold"),
                what = string.format(L["%s: buy it, disenchant it"], FT.ItemText(d.id, 24)) }
            shown[d.id] = true
        end
    end
    if #cards < 3 and best.VENDOR and not shown[best.VENDOR.id] then
        cards[#cards + 1] = { id = best.VENDOR.id, kind = "VENDOR", label = "VENDOR IT", gold = "+" .. FT.Money(math.floor(best.VENDOR.profit), "gold"),
            what = string.format(L["%s: a vendor pays more than it costs"], FT.ItemText(best.VENDOR.id, 24)) }
    end
    return cards, personal > 0
end

local function Card(parent)
    local c = UI.Panel(parent, "bg1", "line")
    c:EnableMouse(true)
    c.badge = UI.Badge(c, 70, 20)
    c.badge:SetPoint("TOPLEFT", 12, -12)
    c.gold = UI.Text(c, 15, "text", "RIGHT")
    c.gold:SetPoint("TOPRIGHT", -12, -13)
    c.gold:SetPoint("LEFT", c.badge, "RIGHT", 8, 0)
    c.icon = UI.Icon(c, 20)
    c.icon:SetPoint("TOPLEFT", c.badge, "BOTTOMLEFT", 0, -10)
    c.what = UI.Text(c, 13, "text")
    c.what:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 8, -1)
    c.what:SetPoint("RIGHT", -12, 0)
    c.what:SetJustifyV("TOP")
    if c.what.SetWordWrap then c.what:SetWordWrap(true) end
    if c.what.SetMaxLines then c.what:SetMaxLines(3) end
    c.what:SetHeight(UI.RowH(48))
    c:SetScript("OnEnter", function(self)
        if not self.id then return end
        UI.TipItem(self, self.id)
        if self.tip then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(self.tip, 0.85, 0.87, 0.9, true)
        end
        GameTooltip:AddLine(L["Click: its page"], 0.58, 0.55, 0.5)
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    c:SetScript("OnMouseUp", function(self) if self.id and not UI.ItemClick(self.id) then FT.OpenItem(self.id) end end)
    function c:Set(m)
        self.id, self.tip = m and m.id, m and m.tip
        self.badge:SetShown(m ~= nil)
        self.icon:SetShown(m ~= nil)
        if not m then
            self.gold:SetText("")
            self.what:SetText(FT.C("dim", L["Nothing right now: new prices come every hour."]))
            return
        end
        self.badge:Set(m.kind, m.label)
        self.icon:SetItem(m.id)
        self.gold:SetText(m.gold or "")
        self.what:SetText(m.what or "")
    end
    return c
end

local function Box(parent, title)
    local b = UI.Panel(parent, "bg1", "line")
    b.title = UI.Text(b, 13, "muted")
    b.title:SetPoint("TOPLEFT", 12, -10)
    b.title:SetText(title)
    return b
end

-- a scrolling list of items: name, price, today's move (or, for your bags, the verdict and worth)
local function ItemList(box, bags)
    local list = UI.List(box, {
        rowHeight = UI.RowH(bags and 28 or 24),
        setup = function(row)
            row.right = UI.Text(row, 13, "text", "RIGHT")
            row.right:SetPoint("RIGHT", -4, 0)
            row.right:SetWidth(UI.RowH(bags and 72 or 52) + 4 * (tonumber(FT.S.textSize) or 0))
            row.mid = UI.Text(row, 12, "muted", "RIGHT")
            row.mid:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
            row.mid:SetWidth(UI.RowH(70) + 4 * (tonumber(FT.S.textSize) or 0))
            if bags then
                row.badge = UI.Badge(row, 60, 18)
                row.badge:SetPoint("LEFT", 4, 0)
                row.mid:Hide()
            end
            row.name = UI.Text(row, 13, "text")
            row.name:SetPoint("LEFT", bags and row.badge or row, bags and "RIGHT" or "LEFT", bags and 8 or 6, 0)
            row.name:SetPoint("RIGHT", bags and row.right or row.mid, "LEFT", -6, 0)
        end,
        update = function(row, x)
            if bags then
                row.badge:Set(x.signal or "NODATA", nil, x.strength)
                UI.FitSize(row.name, FT.ItemText(x.id) .. FT.C("dim", " ×" .. FT.Num(x.qty)), 13, 3)
                row.right:SetText(FT.Money(x.value, "gold"))
            else
                UI.FitSize(row.name, FT.ItemText(x.id), 13, 3)
                row.mid:SetText(FT.Money(x.price, "short"))
                row.right:SetText(FT.C((x.ch1 or 0) >= 0 and "up" or "down", FT.An.Pc(x.ch1 or 0)))
            end
        end,
        onClick = function(x) if not UI.ItemClick(x.id) then FT.OpenItem(x.id) end end,
        onEnter = function(row, x)
            UI.TipItem(row, x.id)
            if x.reason then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(x.reason, 0.85, 0.87, 0.9, true)
                GameTooltip:Show()
            end
        end,
    })
    list:SetPoint("TOPLEFT", 6, -34)
    list:SetPoint("BOTTOMRIGHT", -4, 6)
    return list
end

-- three equal columns of a row
local function Thirds(row, frames)
    UI.OnSize(row, function(self, w, h)
        local cw = math.floor((w - GAP * 2) / 3)
        for i, f in ipairs(frames) do
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", self, "TOPLEFT", (i - 1) * (cw + GAP), 0)
            f:SetSize(cw, h)
        end
    end)
end

function T.Build(p)
    -- everything you own: worth, the last update's move, since yesterday, a line of the last 24 updates
    local own = UI.Panel(p, "bg1", "line")
    own:SetPoint("TOPLEFT", PAD, -PAD)
    own:SetPoint("TOPRIGHT", -PAD, -PAD)
    own:SetHeight(UI.RowH(58))
    own:EnableMouse(true)
    local label = UI.Text(own, 13, "muted")
    label:SetPoint("LEFT", 14, 0)
    label:SetText(L["Everything you own"])
    T.worth = UI.Text(own, 22, "text")
    T.worth:SetPoint("LEFT", label, "RIGHT", 16, 0)
    T.update = UI.Text(own, 13, "up")
    T.update:SetPoint("BOTTOMLEFT", T.worth, "RIGHT", 14, 1)
    T.since = UI.Text(own, 11, "muted")
    T.since:SetPoint("TOPLEFT", T.worth, "RIGHT", 14, -2)
    local span = UI.Text(own, 10, "dim", "RIGHT")
    span:SetPoint("RIGHT", -14, 0)
    span:SetText(L["last 24 updates"])
    T.spark = UI.Sparkline(own, 240, 32)
    T.spark:SetPoint("RIGHT", span, "LEFT", -10, 0)
    T.update:SetPoint("RIGHT", T.spark, "LEFT", -12, 0)
    T.since:SetPoint("RIGHT", T.spark, "LEFT", -12, 0)
    own:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["Everything you own"], 1, 1, 1)
        GameTooltip:AddLine(L["Bags, banks, mail and the auction house of your characters on this server, at the latest prices, plus their gold."], 0.75, 0.78, 0.82, true)
        local list = FT.Port.Snaps()
        if #list >= 2 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["What each price update did to it"], 1, 0.82, 0)
            for i = #list, math.max(2, #list - 5), -1 do
                local d = list[i].v - list[i - 1].v
                GameTooltip:AddDoubleLine(FT.TimeOfDay(list[i].t) .. FT.C("dim", "   " .. FT.Money(list[i].v, "gold")),
                    d >= 0 and FT.C("up", "+" .. FT.Money(d, "gold")) or FT.C("down", FT.Money(d, "gold")), 0.85, 0.87, 0.9, 1, 1, 1)
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Click: where it all is (You)."], 0.58, 0.55, 0.5)
        GameTooltip:Show()
    end)
    own:SetScript("OnLeave", function() GameTooltip:Hide() end)
    own:SetScript("OnMouseUp", function() FT.ShowSub("you", "portfolio") end)

    T.title = UI.Text(p, 15, "accent")
    T.title:SetPoint("TOPLEFT", own, "BOTTOMLEFT", 2, -14)
    T.title:SetText(L["Your top 3"])
    local hint = UI.Text(p, 11, "dim")
    hint:SetPoint("LEFT", T.title, "RIGHT", 12, -1)
    hint:SetText(L["what to do with your stuff right now · hover for why"])

    local top = CreateFrame("Frame", nil, p)
    top:SetPoint("TOPLEFT", T.title, "BOTTOMLEFT", -2, -8)
    top:SetPoint("RIGHT", -PAD, 0)
    top:SetHeight(UI.RowH(104))
    T.cards = { Card(top), Card(top), Card(top) }
    Thirds(top, T.cards)

    local bottom = CreateFrame("Frame", nil, p)
    bottom:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -GAP)
    bottom:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    T.bags = Box(bottom, L["In your bags"])
    T.bagsTotal = UI.Text(T.bags, 13, "text", "RIGHT")
    T.bagsTotal:SetPoint("TOPRIGHT", -12, -10)
    T.bags.list = ItemList(T.bags, true)
    T.bags.list:SetEmptyText(L["Nothing priced in your bags."])
    T.down = Box(bottom, L["Going down today"])
    T.down.list = ItemList(T.down)
    T.down.list:SetEmptyText(L["Nothing has dropped much today."])
    T.up = Box(bottom, L["Going up today"])
    T.up.list = ItemList(T.up)
    T.up.list:SetEmptyText(L["Nothing has climbed much today."])
    Thirds(bottom, { T.bags, T.down, T.up })
    built = true
end

-- what this character carries, priced, the most valuable first, with what to do with each
local function BagRows()
    local out, total = {}, 0
    local inv = FT.charKey and FT.db.inv and FT.db.inv[FT.charKey]
    for id, n in pairs(inv and inv.bags or {}) do
        if type(id) == "number" and type(n) == "number" and n > 0 then
            local s = FT.An.Stats(id)
            if s.price then
                local signal, strength, reason = FT.An.SellSignal(s)
                local v = s.price * n
                out[#out + 1] = { id = id, qty = n, value = v, signal = signal, strength = strength, reason = reason }
                total = total + v
            end
        end
    end
    table.sort(out, function(a, b) return a.value > b.value end)
    return out, total
end

function T.FillWorth()
    if not built then return end
    T.worth:SetText(FT.Money(FT.Port.Worth(), "gold"))
    local lastMove, dayMove, now = FT.Port.WorthMoves()
    if lastMove then
        T.update:SetText((lastMove >= 0 and FT.C("up", "+" .. FT.Money(lastMove, "gold")) or FT.C("down", FT.Money(lastMove, "gold")))
            .. FT.C("muted", " " .. string.format(L["with the last prices (%s)"], FT.TimeOfDay(now.t))))
    else
        T.update:SetText(FT.C("dim", L["its move shows from the next prices"]))
    end
    T.since:SetText(dayMove and ((dayMove >= 0 and ("+" .. FT.Money(dayMove, "gold")) or FT.Money(dayMove, "gold")) .. " " .. L["since yesterday"]) or "")
    local vals = {}
    local list = FT.Port.Snaps()
    for i = math.max(1, #list - 23), #list do vals[#vals + 1] = list[i].v end
    T.spark:SetValues(vals, (lastMove or 0) >= 0 and "up" or "down")
end

function T.Refresh()
    if not built then return end
    T.FillWorth()
    local cards, personal = FT.TopMoves()
    T.title:SetText(personal and L["Your top 3"] or L["Today's 3 moves"])
    for i, c in ipairs(T.cards) do c:Set(cards[i]) end
    local bags, total = BagRows()
    T.bags.list:SetItems(bags, true)
    T.bagsTotal:SetText(total > 0 and FT.Money(total, "gold") or "")
    T.down.list:SetItems(FT.Market.Movers(200, "ch1", false), true)
    T.up.list:SetItems(FT.Market.Movers(200, "ch1", true), true)
end

T.OnShow = T.Refresh

function T.OnItems()
    if not built then return end
    for _, l in ipairs({ T.bags.list, T.down.list, T.up.list }) do l:Refresh() end
end

local function IfShown() if built and T.cards[1]:IsVisible() then T.Refresh() end end
FT.On("FT_WORTH_CHANGED", function() if built and T.cards[1]:IsVisible() then T.FillWorth() end end)
FT.On("FT_DEALS_READY", IfShown)
FT.On("FT_CRAFTS_READY", IfShown)
FT.On("FT_MOVERS_READY", IfShown)
FT.On("FT_INVENTORY_CHANGED", function() FT.Debounce("todayBags", 1, IfShown) end)
