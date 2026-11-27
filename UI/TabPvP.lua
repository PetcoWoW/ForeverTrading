-- Wolf: Make gold > PvP (v0.51) - what battlegrounds burn through and how you make gold from it, studied like the
-- raids (the PvP study: Forever's own sources first, Classic guides after; each item says how sure). Forever's
-- battleground holiday weeks on top: stock up the week before, sell into the week. The materials beside it.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local T = {}
FT.Tabs.pvp = T

local list, matList, sub, box, matBox, built
local CONF = { confirmed = "confirmed", likely = "likely" }

function T.Build(p)
    local R = FT.Tabs.radar
    T.bar = UI.GroupBar(p, "make")
    T.bar:SetPoint("TOPLEFT", 12, -8)
    sub = UI.Text(p, 11, "dim")
    sub:SetPoint("LEFT", T.bar, "RIGHT", 14, 0)
    sub:SetPoint("RIGHT", p, "RIGHT", -12, 0)
    if sub.SetWordWrap then sub:SetWordWrap(false) end

    matBox = UI.Panel(p, "bg1", "line")
    matBox:SetPoint("TOPRIGHT", -8, -40)
    matBox:SetPoint("BOTTOMRIGHT", -8, 8)
    matBox:SetWidth(360)
    local matTitle = UI.Text(matBox, 12, "accent")
    matTitle:SetPoint("TOPLEFT", 10, -8)
    matTitle:SetText(L["Key materials"])
    local matSub = UI.Text(matBox, 10, "dim")
    matSub:SetPoint("TOPLEFT", matTitle, "BOTTOMLEFT", 0, -2)
    matSub:SetPoint("RIGHT", matBox, "RIGHT", -10, 0)
    matSub:SetText(L["What most of the PvP kit is made of"])

    box = UI.Panel(p, "bg1", "line")
    box:SetPoint("TOPLEFT", 8, -40)
    box:SetPoint("BOTTOMLEFT", 8, 8)
    box:SetPoint("RIGHT", matBox, "LEFT", -8, 0)
    list = UI.List(box, {
        rowHeight = UI.RowH(48), setup = R.RowSetup,
        update = function(row, x)
            row.icon:SetItem(x.id)
            row.rank:SetText("#" .. x.rank)
            UI.FitBits(row.name, FT.ItemText(x.id, 34) .. FT.C("dim", "  ·  " .. x.roles))
            local c = FT.Ahead and FT.Ahead.Call(x.id)
            local call = (c and c.sure >= 40) and (FT.C("dim", "  ·  ") .. FT.C(c.move >= 0 and "up" or "down", (c.move >= 0 and "+" or "") .. FT.An.Pc(c.move))
                .. FT.C("dim", " " .. L["next week"] .. ", " .. c.sure .. "% " .. L["sure"])) or ""
            UI.FitBits(row.line, (x.moveText or "") .. call)
            UI.SetTextColor(row.line, (R.MOVES[x.move] or R.MOVES.STEADY)[2])
            local m = x.market
            row.price:SetText(m.price and FT.Money(m.price, "short") or FT.C("dim", L["none listed"]))
            row.ch:SetText(R.Change(m.ch7))
            row.chip:SetMove(x.move)
        end,
        onClick = function(x) if not UI.ItemClick(x.id) then FT.OpenItem(x.id) end end,
        onEnter = function(row, x)
            UI.TipItem(row, x.id)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(string.format(L["#%d for battlegrounds: %s"], x.rank, x.roles), 1, 0.82, 0)
            GameTooltip:AddLine(x.note, 0.85, 0.87, 0.9, true)
            GameTooltip:AddDoubleLine(L["How sure"], L[CONF[x.conf] or "?"], 0.6, 0.64, 0.7, 1, 1, 1)
            local m = x.market
            GameTooltip:AddDoubleLine(L["Listed / sold a day"], FT.Num(m.listed or 0) .. " / " .. FT.Num(math.floor((m.perDay or 0) + 0.5)), 0.6, 0.64, 0.7, 1, 1, 1)
            local c = FT.Ahead and FT.Ahead.Call(x.id)
            if c and c.sure >= 40 then
                GameTooltip:AddLine(string.format(L["How sure: %d%% (right %d of %d weeks on its last 30 days)"], c.sure, c.hits, c.weeks), 0.85, 0.87, 0.9, true)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(x.moveText or "", 0.4, 0.9, 0.4, true)
            GameTooltip:Show()
        end,
    })
    list:SetPoint("TOPLEFT", 1, -1)
    list:SetPoint("BOTTOMRIGHT", -1, 4)
    list:SetEmptyText(L["The study's list is empty."])

    matList = UI.List(matBox, {
        rowHeight = UI.RowH(46), setup = R.MatSetup,
        update = function(row, x)
            row.icon:SetItem(x.id)
            row.name:SetText(FT.ItemText(x.id, 26))
            local bits = { string.format(L["in %d of the kit"], #x.into) }
            if x.held > 0 then bits[#bits + 1] = string.format(L["you hold %s"], FT.Num(x.held)) end
            row.line:SetText(table.concat(bits, " · "))
            row.price:SetText(x.market.price and FT.Money(x.market.price, "short") or FT.C("dim", "—"))
            row.ch:SetText(R.Change(x.market.ch7))
            row.chip:SetMove(x.move)
        end,
        onClick = function(x) if not UI.ItemClick(x.id) then FT.OpenItem(x.id) end end,
        onEnter = function(row, x)
            UI.TipItem(row, x.id)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(x.moveText or "", 0.4, 0.9, 0.4, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Goes into"], 1, 0.82, 0)
            for i, id in ipairs(x.into) do
                if i > 8 then break end
                GameTooltip:AddLine(FT.ItemText(id, 34), 0.85, 0.87, 0.9)
            end
            GameTooltip:Show()
        end,
    })
    matList:SetPoint("TOPLEFT", 1, -40)
    matList:SetPoint("BOTTOMRIGHT", -1, 4)
    matList:SetEmptyText(L["Working out the materials..."])
    built = true
end

function T.Refresh()
    if not built then return end
    UI.FitBits(sub, FT.Futures.PvPHeadline())
    list:SetItems(FT.Futures.PvP(), true)
    matList:SetItems(FT.Futures.PvPMaterials(10), true)
end
T.OnShow = T.Refresh

FT.On("FT_INVENTORY_CHANGED", function() if list and list:IsVisible() then FT.Debounce("pvpPage", 1, T.Refresh) end end)
FT.On("FT_MARKET_READY", function() if list and list:IsVisible() then FT.Debounce("pvpPage", 1, T.Refresh) end end)
