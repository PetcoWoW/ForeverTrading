-- Wolf of Booty Bay: the Futures page (the tab key stays "radar") - what raiders will need before the raids and how
-- you make gold from it (FT.Futures). Two sections: Consumables (ranked by how many raiders burn how much, with the
-- key materials beside them) and Gear (the crafted pre-raid pieces). Every row has the move that's yours.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local T = {}
FT.Tabs.radar = T

local state = { section = "consumables" }
local list, matList, head, sub, seg, box, matBox, matTitle

-- each move's colour, and its word on the chip
local MOVES = {
    CRAFT = { "CRAFT IT", "up" }, HOLD = { "HOLD", "accent" }, SELL = { "SELL", "up" }, BUY = { "BUY NOW", "blue" },
    DIP = { "BUY THE DIP", "blue" }, STOCK = { "STOCK UP", "blue" }, GATHER = { "GATHER", "accent" },
    LATE = { "CLIMBING", "down" }, NORECIPE = { "NO RECIPE", "muted" }, NONE = { "NONE LISTED", "muted" },
    STEADY = { "STEADY", "muted" },
}
local CONF_WORD = { confirmed = "confirmed", likely = "likely", unknown = "unknown" }

local function Chip(parent)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(74, 16)
    c.bg = UI.RoundTex(c, "BACKGROUND", "muted", 0.2)
    c.bg:SetAllPoints()
    c.text = UI.Text(c, 10, "muted", "CENTER")
    c.text:SetPoint("CENTER")
    function c:SetMove(move)
        local m = MOVES[move] or MOVES.STEADY
        UI.SetTexColor(self.bg, m[2], 0.22)
        UI.SetTextColor(self.text, m[2])
        self.text:SetText(L[m[1]])
    end
    return c
end

local function Change(v)
    if not v then return FT.C("dim", "—") end
    return FT.Pct(v) .. FT.C("dim", " " .. L["7d"])
end

local function RowSetup(row)
    row.rank = UI.Text(row, 13, "accent", "RIGHT")
    row.rank:SetPoint("LEFT", 4, 0)
    row.rank:SetWidth(28)
    row.icon = UI.Icon(row, 28)
    row.icon:SetPoint("LEFT", 38, 0)
    row.name = UI.Text(row, 12, "text")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 1)
    row.name:SetPoint("RIGHT", row, "RIGHT", -190, 0)
    row.line = UI.Text(row, 11, "muted")
    row.line:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, -1)
    row.line:SetPoint("RIGHT", row, "RIGHT", -190, 0)
    for _, t in ipairs({ row.name, row.line }) do if t.SetWordWrap then t:SetWordWrap(false) end end
    row.price = UI.Text(row, 12, "text", "RIGHT")
    row.price:SetPoint("TOPRIGHT", row, "TOPRIGHT", -96, -7)
    row.ch = UI.Text(row, 11, "muted", "RIGHT")
    row.ch:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -96, 7)
    row.chip = Chip(row)
    row.chip:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    row.sep = UI.HLine(row, "line", 0.5)
    row.sep:SetPoint("BOTTOMLEFT", 10, 0)
    row.sep:SetPoint("BOTTOMRIGHT", -10, 0)
end

local function MatSetup(row)
    row.icon = UI.Icon(row, 24)
    row.icon:SetPoint("LEFT", 10, 0)
    row.name = UI.Text(row, 12, "text")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 1)
    row.name:SetPoint("RIGHT", row, "RIGHT", -150, 0)
    row.line = UI.Text(row, 10, "dim")
    row.line:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, -1)
    row.line:SetPoint("RIGHT", row, "RIGHT", -86, 0)
    for _, t in ipairs({ row.name, row.line }) do if t.SetWordWrap then t:SetWordWrap(false) end end
    row.price = UI.Text(row, 11, "text", "RIGHT")
    row.price:SetPoint("TOPRIGHT", row, "TOPRIGHT", -88, -6)
    row.ch = UI.Text(row, 10, "muted", "RIGHT")
    row.ch:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -88, 6)
    row.chip = Chip(row)
    row.chip:SetSize(70, 16)
    row.chip:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    row.sep = UI.HLine(row, "line", 0.5)
    row.sep:SetPoint("BOTTOMLEFT", 8, 0)
    row.sep:SetPoint("BOTTOMRIGHT", -8, 0)
end

-- what a recipe needs, one line per material with its price (tooltips)
local function AddMaterials(r)
    if not r then return end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Made of"] .. FT.C("dim", "  (" .. L[r.prof or "?"] .. ")"), 1, 0.82, 0)
    for _, rg in ipairs(r.reagents or {}) do
        local price = FT.Price(rg.itemID)
        GameTooltip:AddDoubleLine(FT.ItemText(rg.itemID, 30) .. FT.C("dim", " x" .. rg.qty),
            price and FT.Money(price * rg.qty, "short") or FT.C("dim", "—"), 0.85, 0.87, 0.9, 1, 1, 1)
    end
end

-- the header's own caution tape: gold with black words, striped edges, beside the title (still being built)
local SIGN_H = 0
local function Tape(parent)
    local t = CreateFrame("Frame", nil, parent)
    t:SetSize(150, 16)
    local bg = t:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 0.78, 0.05, 1)
    local top = UI.HazardTape(t, 3)
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    local bottom = UI.HazardTape(t, 3)
    bottom:SetPoint("BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT")
    local text = UI.Text(t, 9, "black", "CENTER")
    text:SetShadowOffset(0, 0)
    text:SetPoint("CENTER", 0, 0)
    text:SetText(L["UNDER CONSTRUCTION"])
    t:SetWidth(math.ceil(text:GetStringWidth()) + 18)
    t:EnableMouse(true)
    t:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["Futures is still being built"], 1, 0.82, 0)
        GameTooltip:AddLine(L["Built from the pre-raid study and today's market; the raids will teach it more."], 0.85, 0.87, 0.9, true)
        GameTooltip:Show()
    end)
    t:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return t
end

function T.Build(p)
    head = UI.Text(p, 16, "text")
    head:SetPoint("TOPLEFT", 12, -10 - SIGN_H)
    head:SetText(L["Futures"])
    T.sign = Tape(p)
    T.sign:SetPoint("LEFT", head, "RIGHT", 10, 0)
    sub = UI.Text(p, 11, "dim")
    sub:SetPoint("LEFT", T.sign, "RIGHT", 12, -1)
    sub:SetPoint("RIGHT", p, "RIGHT", -230, 0)
    if sub.SetWordWrap then sub:SetWordWrap(false) end
    seg = UI.Segmented(p, { { "consumables", L["Consumables"] }, { "gear", L["Gear"] } }, function(v)
        state.section = v
        T.Layout()
        T.Refresh()
    end, 22)
    seg:SetPoint("TOPRIGHT", -8, -8 - SIGN_H)
    seg:SetValue(state.section)

    box = UI.Panel(p, "bg1", "line")
    list = UI.List(box, {
        rowHeight = 46, setup = RowSetup,
        update = function(row, x)
            row.icon:SetItem(x.id)
            local m = x.market
            if x.c then
                row.rank:SetText("#" .. x.rank)
                row.name:SetText(FT.ItemText(x.id, 34) .. FT.C("dim", "  " .. x.c.roles))
            else
                row.rank:SetText(tostring(x.g.specs))
                row.name:SetText(FT.ItemText(x.id, 34) .. FT.C("dim", "  " .. L[x.g.slot] .. ": " .. x.g.who))
            end
            row.line:SetText(x.moveText or "")
            UI.SetTextColor(row.line, (MOVES[x.move] or MOVES.STEADY)[2])
            row.price:SetText(m.price and FT.Money(m.price, "short") or FT.C("dim", L["none listed"]))
            row.ch:SetText(Change(m.ch7))
            row.chip:SetMove(x.move)
        end,
        onClick = function(x) if not UI.ItemClick(x.id) then FT.OpenItem(x.id) end end,
        onEnter = function(row, x)
            UI.TipItem(row, x.id)
            GameTooltip:AddLine(" ")
            local m = x.market
            if x.c then
                GameTooltip:AddLine(string.format(L["#%d for raids: %s"], x.rank, x.c.roles), 1, 0.82, 0)
                GameTooltip:AddLine(x.c.note, 0.85, 0.87, 0.9, true)
                GameTooltip:AddDoubleLine(L["How sure"], L[CONF_WORD[x.c.conf] or "?"] .. (x.c.raids and ("  ·  " .. x.c.raids) or ""), 0.6, 0.64, 0.7, 1, 1, 1)
            else
                GameTooltip:AddLine(string.format(L["Pre-raid BiS for %d specs: %s"], x.g.specs, x.g.who), 1, 0.82, 0, true)
            end
            GameTooltip:AddDoubleLine(L["Listed / sold a day"], FT.Num(m.listed or 0) .. " / " .. FT.Num(math.floor((m.perDay or 0) + 0.5)), 0.6, 0.64, 0.7, 1, 1, 1)
            if m.ch30 then GameTooltip:AddDoubleLine(L["Since its first weeks"], FT.Pct(m.ch30), 0.6, 0.64, 0.7, 1, 1, 1) end
            AddMaterials(x.recipe)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(x.moveText or "", 0.4, 0.9, 0.4, true)
            GameTooltip:Show()
        end,
    })
    list:SetPoint("TOPLEFT", 1, -1)
    list:SetPoint("BOTTOMRIGHT", -1, 4)

    -- the key materials: what most of the list is made of
    matBox = UI.Panel(p, "bg1", "line")
    matBox:SetPoint("TOPRIGHT", -8, -40 - SIGN_H)
    matBox:SetPoint("BOTTOMRIGHT", -8, 8)
    matBox:SetWidth(330)
    matTitle = UI.Text(matBox, 12, "accent")
    matTitle:SetPoint("TOPLEFT", 10, -8)
    matTitle:SetText(L["Key materials"])
    local matSub = UI.Text(matBox, 10, "dim")
    matSub:SetPoint("TOPLEFT", matTitle, "BOTTOMLEFT", 0, -2)
    matSub:SetPoint("RIGHT", matBox, "RIGHT", -10, 0)
    matSub:SetText(L["What most of the raid consumables are made of"])
    matList = UI.List(matBox, {
        rowHeight = 40, setup = MatSetup,
        update = function(row, x)
            row.icon:SetItem(x.id)
            row.name:SetText(FT.ItemText(x.id, 26))
            local bits = { string.format(L["in %d of the list"], #x.into) }
            if x.held > 0 then bits[#bits + 1] = string.format(L["you hold %s"], FT.Num(x.held)) end
            if (x.gathered or 0) > 0 then bits[#bits + 1] = string.format(L["gathered %s"], FT.Num(x.gathered)) end
            row.line:SetText(table.concat(bits, "  ·  "))
            row.price:SetText(x.market.price and FT.Money(x.market.price, "short") or FT.C("dim", "—"))
            row.ch:SetText(Change(x.market.ch7))
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
    T.Layout()
end

-- Consumables: the list and the key materials beside it; Gear: the list, wide
function T.Layout()
    if not box then return end
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", 8, -40 - SIGN_H)
    box:SetPoint("BOTTOMLEFT", 8, 8)
    if state.section == "consumables" then
        matBox:Show()
        box:SetPoint("RIGHT", matBox, "LEFT", -8, 0)
    else
        matBox:Hide()
        box:SetPoint("RIGHT", -8, 0)
    end
end

function T.Refresh()
    if not list then return end
    sub:SetText(FT.Futures.Headline())
    if state.section == "consumables" then
        local items = FT.Futures.Consumables()
        list:SetEmptyText(L["The study's list is empty."])
        list:SetItems(items, true)
        matList:SetEmptyText(L["Working out the materials..."])
        matList:SetItems(FT.Futures.Materials(10), true)
    else
        list:SetEmptyText(L["The study's list is empty."])
        list:SetItems(FT.Futures.Gear(), true)
    end
end

T.OnShow = T.Refresh
FT.On("FT_INVENTORY_CHANGED", function() if list and list:IsVisible() then FT.Debounce("futures", 1, T.Refresh) end end)
FT.On("FT_MARKET_READY", function() if list and list:IsVisible() then FT.Debounce("futures", 1, T.Refresh) end end)
