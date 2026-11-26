-- Wolf of Booty Bay: the Radar page - demand forming, from the market itself (FT.Radar): what's starting to sell
-- faster before its price moves, what a rising craft pulls on, what's cooling off, and the next announced event.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local T = {}
FT.Tabs.radar = T

local state = { filter = "all" }
local list, head, sub, cal, filterSeg

local STAGES = {
    early = { "EARLY", "up" }, moving = { "MOVING", "accent" }, late = { "LATE", "down" },
    chain = { "CHAIN", "blue" }, cooling = { "COOLING", "muted" },
}

local function Chip(parent)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(66, 16)
    c.bg = UI.RoundTex(c, "BACKGROUND", "muted", 0.2)
    c.bg:SetAllPoints()
    c.text = UI.Text(c, 10, "muted", "CENTER")
    c.text:SetPoint("CENTER")
    return c
end

local function RowSetup(row)
    row.icon = UI.Icon(row, 26)
    row.icon:SetPoint("LEFT", 10, 0)
    row.name = UI.Text(row, 12, "text")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 1)
    row.name:SetPoint("RIGHT", row, "RIGHT", -170, 0)
    row.line = UI.Text(row, 11, "dim")
    row.line:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, -1)
    row.line:SetPoint("RIGHT", row, "RIGHT", -170, 0)
    row.price = UI.Text(row, 12, "text", "RIGHT")
    row.price:SetPoint("RIGHT", row, "RIGHT", -86, 0)
    row.chip = Chip(row)
    row.chip:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    row.sep = UI.HLine(row, "line", 0.5)
    row.sep:SetPoint("BOTTOMLEFT", 10, 0)
    row.sep:SetPoint("BOTTOMRIGHT", -10, 0)
end

-- the sign over the page: the Radar is still being built (what it sees already shows under it)
local SIGN_H = 78
local function BuildSign(p)
    local s = UI.Panel(p, "bg1", "accent")
    s:SetPoint("TOPLEFT", 8, -8)
    s:SetPoint("TOPRIGHT", -8, -8)
    s:SetHeight(SIGN_H - 10)
    local top = UI.HazardTape(s, 7)
    top:SetPoint("TOPLEFT", 3, -3)
    top:SetPoint("TOPRIGHT", -3, -3)
    local bottom = UI.HazardTape(s, 7)
    bottom:SetPoint("BOTTOMLEFT", 3, 3)
    bottom:SetPoint("BOTTOMRIGHT", -3, 3)
    local wolf = UI.Portrait(s, 30, "Interface\\Icons\\Ability_Hunter_Pet_Wolf")
    wolf:SetPoint("LEFT", 18, 0)
    local title = UI.Text(s, 14, "accent")
    title:SetPoint("TOPLEFT", wolf, "TOPRIGHT", 22, 3)
    title:SetText(L["UNDER CONSTRUCTION"])
    local body = UI.Text(s, 11, "muted")
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    body:SetPoint("RIGHT", s, "RIGHT", -16, 0)
    body:SetText(L["The wolves are still digging. Soon the Radar will guess what raiders will need before the prices move. What it already sees is below."])
    return s
end

function T.Build(p)
    T.sign = BuildSign(p)
    head = UI.Text(p, 16, "text")
    head:SetPoint("TOPLEFT", 12, -10 - SIGN_H)
    head:SetText(L["Radar"])
    sub = UI.Text(p, 11, "dim")
    sub:SetPoint("LEFT", head, "RIGHT", 12, -1)
    sub:SetPoint("RIGHT", p, "RIGHT", -320, 0)
    filterSeg = UI.Segmented(p, { { "all", L["All"] }, { "early", L["Early"] }, { "chain", L["Chains"] }, { "cooling", L["Cooling"] } },
        function(v)
            state.filter = v
            T.Refresh()
        end, 22)
    filterSeg:SetPoint("TOPRIGHT", -8, -8 - SIGN_H)
    filterSeg:SetValue(state.filter)

    -- the next announced event, when one is close
    cal = UI.Panel(p, "bg1", "line")
    cal:SetPoint("TOPLEFT", 8, -40 - SIGN_H)
    cal:SetPoint("TOPRIGHT", -8, -40 - SIGN_H)
    cal:SetHeight(34)
    cal.bar = UI.Tex(cal, "ARTWORK", "accent", 1)
    cal.bar:SetWidth(3)
    cal.bar:SetPoint("TOPLEFT", 1, -1)
    cal.bar:SetPoint("BOTTOMLEFT", 1, 1)
    cal.text = UI.Text(cal, 12, "text")
    cal.text:SetPoint("LEFT", 14, 0)
    cal.text:SetPoint("RIGHT", -12, 0)

    local box = UI.Panel(p, "bg1", "line")
    box:SetPoint("TOPLEFT", cal, "BOTTOMLEFT", 0, -8)
    box:SetPoint("BOTTOMRIGHT", -8, 8)
    T.box = box
    list = UI.List(box, {
        rowHeight = 42, setup = RowSetup,
        update = function(row, x)
            row.icon:SetItem(x.id)
            row.name:SetText(FT.ItemText(x.id, 40))
            row.line:SetText(FT.Radar.Text(x))
            row.price:SetText(FT.Money(x.price, "short"))
            local key = x.kind == "chain" and "chain" or (x.kind == "cooling" and "cooling") or x.stage
            local st = STAGES[key] or STAGES.moving
            UI.SetTexColor(row.chip.bg, st[2], 0.22)
            UI.SetTextColor(row.chip.text, st[2])
            row.chip.text:SetText(L[st[1]])
        end,
        onClick = function(x) if not UI.ItemClick(x.id) then FT.OpenItem(x.id) end end,
        onEnter = function(row, x)
            UI.TipItem(row, x.id)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(FT.Radar.Text(x), 0.85, 0.87, 0.9, true)
            local what = {
                early = L["Early: buying has picked up but the price hasn't followed yet. The most to gain, and the least proven."],
                moving = L["Moving: the price is following the buying. Still room, less than early."],
                late = L["Late: the price already jumped. Selling into it beats buying it now."],
                chain = L["Chain: a material of something that's selling faster. Materials tend to follow the product by days."],
                cooling = L["Cooling: it sold well and is slowing down. If you hold some, a good time to list them."],
            }
            local key = x.kind == "chain" and "chain" or (x.kind == "cooling" and "cooling") or x.stage
            GameTooltip:AddLine(what[key] or "", 0.6, 0.64, 0.7, true)
            GameTooltip:Show()
        end,
    })
    list:SetPoint("TOPLEFT", 1, -1)
    list:SetPoint("BOTTOMRIGHT", -1, 4)
end

function T.Refresh()
    if not list then return end
    local all, at, busy = FT.Radar.List()
    if not at and not busy then FT.Radar.Build() end
    local rec = FT.Radar.Record()
    sub:SetText(L["Demand forming, from the market itself: buying that speeds up before the price moves"]
        .. (rec and FT.C("accent", "  ·  " .. string.format(L["its record: %s"], rec)) or ""))
    local ev = FT.Radar.Next()
    if ev then
        cal:Show()
        cal.text:SetText(string.format(L["%s in %d days (%s): potions, elixirs, flasks and food usually climb before."],
            ev.name, ev.days, date("%m/%d", ev.t)))
        T.box:SetPoint("TOPLEFT", cal, "BOTTOMLEFT", 0, -8)
    else
        cal:Hide()
        T.box:SetPoint("TOPLEFT", cal, "TOPLEFT", 0, 0)
    end
    local shown = {}
    for _, x in ipairs(all) do
        local key = x.kind == "chain" and "chain" or (x.kind == "cooling" and "cooling") or x.stage
        if state.filter == "all" or state.filter == key then shown[#shown + 1] = x end
    end
    local h = FT.Feed and FT.Feed.House and FT.Feed.House()
    local noDaily = not (h and h.soldRaw and next(h.soldRaw))
    list:SetEmptyText(busy and L["Looking..."]
        or (noDaily and L["The Radar reads the price robot's daily sales: they arrive with your next price update, and it needs a few days of them."]
        or L["Nothing forming right now: no item is selling clearly faster than the week before."]))
    list:SetItems(shown, true)
end

T.OnShow = T.Refresh
FT.On("FT_RADAR_READY", function() if list and list:IsVisible() then T.Refresh() end end)
