-- ForeverTrading: Signals page - what to do now, in four columns: sell, craft, buy, hold / avoid.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local T = {}
FT.Tabs.signals = T

local cols = {}

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
    c.accent = UI.Tex(c, "ARTWORK", "accent", 1)
    c.accent:SetHeight(2)
    c.accent:SetPoint("TOPLEFT", 1, -1)
    c.accent:SetPoint("TOPRIGHT", -1, -1)
    c.list = UI.List(c, {
        rowHeight = 42,
        setup = function(row)
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
        end,
        update = function(row, x)
            row.icon:SetItem(x.id)
            row.name:SetText(FT.ItemText(x.id, 30))
            row.reason:SetText(x.reason or "")
            row.value:SetText(x.value or "")
            row.badge:Set(x.signal, nil, x.strength)
        end,
        onClick = function(x)
            if UI.ItemClick(x.id) then return end
            if x.recipe then FT.OpenRecipe(x.recipe) else FT.OpenItem(x.id) end
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

    -- what you own
    local rows = FT.Port.Rows()
    for _, h in ipairs(rows) do
        if h.signal == "SELL" then
            sell[#sell + 1] = { id = h.id, signal = "SELL", strength = h.strength, reason = h.reason,
                value = FT.Num(h.qty) .. FT.C("dim", " x ") .. FT.Money(h.price, "short"), sortV = h.value * h.strength,
                tip = string.format(L["You have %s: worth %s"], FT.Num(h.qty), FT.Money(h.value)) }
        elseif h.signal == "HOLD" then
            hold[#hold + 1] = { id = h.id, signal = "HOLD", strength = h.strength, reason = h.reason,
                value = FT.Num(h.qty) .. FT.C("dim", " x ") .. FT.Money(h.price, "short"), sortV = h.value }
        end
    end

    -- your recipes
    local materials = {}
    for _, r in ipairs(FT.Craft.List()) do
        local e = FT.Craft.Eval(r)
        if e.signal == "CRAFT" then
            local reason = e.reason
            if e.sell == "SELL" then reason = reason .. "  ·  " .. FT.C("up", L["price is high now"]) end
            craft[#craft + 1] = { id = r.output, recipe = r.key, signal = "CRAFT", strength = e.strength, reason = reason,
                value = FT.C("up", "+" .. FT.Money(e.profit, "short")), sortV = e.profit * (e.sell == "SELL" and 1.5 or 1),
                tip = FT.Craft.KnownByText(r) }
        elseif e.signal == "AVOID" then
            hold[#hold + 1] = { id = r.output, recipe = r.key, signal = "AVOID", strength = e.strength, reason = e.reason,
                value = FT.C("down", FT.Money(e.profit, "short")), sortV = -e.profit * 0.5 }
        end
        for _, rg in ipairs(r.reagents) do materials[rg.itemID] = true end
    end

    -- materials of your recipes and your watchlist on a dip
    for id in pairs(FT.db.watch) do materials[id] = true end
    for id in pairs(materials) do
        local s = FT.An.Stats(id)
        local signal, strength, reason = FT.An.BuySignal(s)
        if signal == "BUY" then
            buy[#buy + 1] = { id = id, signal = "BUY", strength = strength, reason = reason,
                value = FT.Money(s.price, "short"), sortV = -(s.dev or 0) * 100 + (strength or 0) }
        end
    end

    local function Sort(t) table.sort(t, function(a, b) return (a.sortV or 0) > (b.sortV or 0) end) end
    Sort(sell); Sort(craft); Sort(buy); Sort(hold)
    return sell, craft, buy, hold
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

    cols[1] = Column(p, L["Sell now"], L["What you own, priced above its average"])
    cols[2] = Column(p, L["Worth crafting"], L["Your recipes with a good profit"])
    cols[3] = Column(p, L["Worth buying"], L["Your materials and watchlist on a dip"])
    cols[4] = Column(p, L["Hold / avoid"], L["Below average - wait; recipes at a loss"])
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
    T.rules:SetText(string.format(L["Sell: %d%% above the %d-day average or RSI 70+.  Buy: %d%% below or RSI 30-.  Craft: profit from %s and margin from %d%%."],
        FT.S.sellAbove, FT.S.avgDays, FT.S.buyBelow, FT.Money(FT.S.minProfit, "short"), FT.S.minMargin))
    local sell, craft, buy, hold = Collect()
    local lists = { sell, craft, buy, hold }
    for i, c in ipairs(cols) do
        c.list:SetItems(lists[i], true)
        c.count:SetText(#lists[i] > 0 and tostring(#lists[i]) or "")
    end
end

T.OnShow = T.Refresh
