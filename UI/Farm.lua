local _, FT = ...
local L = FT.L
local UI = FT.UI

---------------------------------------------------------------------------
-- Where to farm a raw material: its price and how it sells, Wowhead, the spots for your level (Classic's, with
-- your own numbers there) and the mobs you looted it from. Opened from the Farm Board, the item's chart, the
-- right-click menu and the farm tip in chat.
---------------------------------------------------------------------------
local win
local SPOT_ROWS, MOB_ROWS = 6, 5

local function Win()
    if win then return win end
    UI.ResolveFont()
    local ts = tonumber(FT.S and FT.S.textSize) or 0
    local spotH, mobH = UI.RowH(32), UI.RowH(24)
    local d = CreateFrame("Frame", "WolfOfBootyBayFarm", UIParent)
    d:SetSize(640 + 20 * ts, 150 + SPOT_ROWS * spotH + MOB_ROWS * mobH + 30 * ts)
    d:SetPoint("CENTER", 0, 40)
    d:SetFrameStrata("DIALOG")
    d:SetToplevel(true)
    d:EnableMouse(true)
    d:SetMovable(true)
    d:SetClampedToScreen(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)
    UI.Skin(d, "window", "bg1")
    if d.bg then d.bg:SetAlpha(0.92) end

    d.icon = UI.Icon(d, 30)
    d.icon:SetPoint("TOPLEFT", 16, -14)
    d.icon:EnableMouse(true)
    d.icon:SetScript("OnEnter", function(self) if d.itemID then UI.TipItem(self, d.itemID) end end)
    d.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    d.close = UI.Button(d, L["Close"], 10, 22, "default", function() d:Hide() end)
    d.close:FitText(24)
    d.close:SetPoint("TOPRIGHT", -12, -12)
    d.wowhead = UI.Button(d, L["Wowhead"], 10, 22, "default", function() FT.Farm.Wowhead(d.itemID) end)
    d.wowhead:FitText(20)
    d.wowhead:SetPoint("RIGHT", d.close, "LEFT", -6, 0)
    d.wowhead:SetTip(L["Wowhead"], L["Its page on Wowhead (WoW Forever): every mob that drops it, with drop chances and a map."])
    d.title = UI.Text(d, 14, "text")
    d.title:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 10, -1)
    d.title:SetPoint("RIGHT", d.wowhead, "LEFT", -10, 0)
    d.sum = UI.Text(d, 11, "muted")
    d.sum:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -4)
    d.sum:SetPoint("RIGHT", d, "RIGHT", -16, 0)

    local function Section(anchor, y, title)
        local t = UI.Text(d, 12, "text")
        t:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", anchor == d and 16 or 0, y)
        t:SetText(title)
        local sub = UI.Text(d, 10, "dim")
        sub:SetPoint("LEFT", t, "RIGHT", 10, 0)
        sub:SetPoint("RIGHT", d, "RIGHT", -16, 0)
        return t, sub
    end

    -- the spots for your level
    d.t1, d.s1 = Section(d.icon, -16, "")
    d.t1:ClearAllPoints()
    d.t1:SetPoint("TOPLEFT", 16, -60)
    d.spots = UI.List(d, {
        rowHeight = spotH,
        cols = {
            { key = "where", width = "fill", make = function(row)
                local c = CreateFrame("Frame", nil, row)
                c.zone = UI.Text(c, 12, "text")
                c.zone:SetPoint("TOPLEFT", 0, -3)
                c.zone:SetPoint("RIGHT")
                c.what = UI.Text(c, 10, "dim")
                c.what:SetPoint("TOPLEFT", c.zone, "BOTTOMLEFT", 0, -3)
                c.what:SetPoint("RIGHT")
                return c
            end, cellHeight = spotH },
            { key = "lv", width = 70 + 6 * ts, justify = "RIGHT", size = 11 },
            { key = "you", width = 170 + 14 * ts, justify = "RIGHT", size = 11 },
        },
        update = function(row, x)
            local c = row.cells.where
            c.zone:SetText(x.zone .. (x.fit == 0 and ("  " .. FT.C("up", L["your level"])) or ""))
            UI.FitBits(c.what, x.what or (x.skill and string.format(L["needs %s %d"], x.skillName, x.skill)) or "")
            row.cells.lv:SetText(x.own and "" or FT.C(x.fit == 0 and "text" or "dim", string.format(L["level %d-%d"], x.lo, x.hi)))
            local y = x.yours
            row.cells.you:SetText(y and (FT.C("accent", string.format(L["you: %s an hour"], FT.Num(math.floor(y.perHour + 0.5))))
                .. (y.goldHour and FT.C("dim", " · " .. FT.Money(math.floor(y.goldHour), "short") .. L["/h"]) or "")) or "")
        end,
        onClick = function(x) FT.Farm.WowheadSearch(x.zone) end,
        onEnter = function(row, x)
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:AddLine(x.zone, 1, 1, 1)
            if x.what then GameTooltip:AddLine(x.what, 0.85, 0.87, 0.9, true) end
            if not x.own then GameTooltip:AddLine(string.format(L["level %d-%d"], x.lo, x.hi), 0.6, 0.64, 0.7) end
            if x.yours then
                GameTooltip:AddLine(string.format(L["You looted %s here in %d minutes of looting."], FT.Num(x.yours.n), x.yours.mins), 0.95, 0.75, 0.3, true)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Click: the zone on Wowhead (a link to copy)."], 0.6, 0.64, 0.7)
            GameTooltip:Show()
        end,
    })
    d.spots:SetPoint("TOPLEFT", d.t1, "BOTTOMLEFT", -4, -6)
    d.spots:SetPoint("RIGHT", d, "RIGHT", -12, 0)
    d.spots:SetHeight(SPOT_ROWS * spotH)
    d.spots:SetEmptyText(L["No spots written for it: its Wowhead page has every mob that drops it."])

    -- the mobs you looted it from
    d.t2, d.s2 = Section(d, 0, L["From your loot"])
    d.t2:ClearAllPoints()
    d.t2:SetPoint("TOPLEFT", d.spots, "BOTTOMLEFT", 4, -14)
    d.s2:SetText(L["what Wolf saw you loot (5 corpses or more of a mob)"])
    d.mobs = UI.List(d, {
        rowHeight = mobH,
        cols = {
            { key = "mob", width = "fill" },
            { key = "zone", width = 150 + 10 * ts, size = 11, color = "muted" },
            { key = "per", width = 150 + 12 * ts, justify = "RIGHT", size = 11 },
        },
        update = function(row, m)
            row.cells.mob:SetText((m.name or FT.C("dim", L["a mob"])) .. (m.lv and FT.C("dim", " (" .. m.lv .. ")") or ""))
            row.cells.zone:SetText(m.zone or "")
            local pct = m.per < 1 and (math.floor(m.per * 100 + 0.5) .. "%") or string.format(L["%.1f each"], m.per)
            row.cells.per:SetText(FT.C("accent", pct) .. FT.C("dim", " " .. string.format(L["of %d"], m.corpses)))
        end,
        onClick = function(m)
            if m.npc then
                FT.ShowLink(m.name or L["a mob"], L["Wowhead: copy the link (Ctrl+C) and paste it in your browser."], FT.Farm.WowheadURL("npc", m.npc))
            end
        end,
    })
    d.mobs:SetPoint("TOPLEFT", d.t2, "BOTTOMLEFT", -4, -6)
    d.mobs:SetPoint("RIGHT", d, "RIGHT", -12, 0)
    d.mobs:SetHeight(MOB_ROWS * mobH)
    d.mobs:SetEmptyText(L["Nothing yet: loot it and Wolf counts every corpse and where you were."])

    d.note = UI.Text(d, 10, "dim")
    d.note:SetPoint("BOTTOMLEFT", 16, 12)
    d.note:SetPoint("RIGHT", d, "RIGHT", -16, 0)
    d.note:SetText(L["Spots: how Classic hands it out (Forever may differ). Your numbers: only what you looted."])

    tinsert(UISpecialFrames, "WolfOfBootyBayFarm")
    d:Hide()
    win = d
    return d
end

local SKILL = { herb = "Herbalism", ore = "Mining" }

function FT.ShowFarm(itemID)
    if not itemID then return end
    local d = Win()
    d.itemID = itemID
    d.icon:SetItem(itemID)
    d.title:SetText(L["Where to farm"] .. ": " .. FT.ItemText(itemID, 40))
    -- how it sells
    local r = FT.Market.Row(itemID)
    local rate = FT.Sales.Rate(itemID)
    local bits = {}
    if r and r.price then bits[#bits + 1] = FT.C("text", FT.Money(r.price, "short")) .. FT.C("dim", " " .. L["each"]) end
    if rate then bits[#bits + 1] = FT.Sales.PerDayText(rate) end
    if r and r.ch7 then bits[#bits + 1] = FT.Pct(r.ch7) .. " " .. L["this week"] end
    local level = (UnitLevel and UnitLevel("player")) or 60
    local spots, data = FT.Farm.Spots(itemID, level)
    if data and data.skill then bits[#bits + 1] = string.format(L["needs %s %d"], L[SKILL[data.kind]], data.skill) end
    UI.FitBits(d.sum, table.concat(bits, FT.C("dim", "  ·  ")))
    -- the spots, yours first
    d.t1:SetText(string.format(L["For you (level %d)"], level))
    d.s1:SetText(data and (data.kind == "cloth" and L["cloth: any humanoid of the level; these camps have many"]
        or data.kind == "leather" and L["leather: skin the beasts of the level"]
        or (data.kind == "herb" or data.kind == "ore") and L["the zones it grows in, by level"]
        or "") or "")
    for _, sp in ipairs(spots) do
        if not sp.what and data and data.skill then sp.skill, sp.skillName = data.skill, L[SKILL[data.kind]] end
    end
    -- zones you looted it in that aren't on the list
    local listed = {}
    for _, sp in ipairs(spots) do listed[sp.zone] = true end
    for _, y in ipairs(FT.Farm.YourZones(itemID, 3)) do
        if not listed[y.zone] then
            table.insert(spots, 1, { zone = y.zone, lo = level, hi = level, fit = 0, own = true, what = L["where you looted it"], yours = y })
        end
    end
    d.spots:SetItems(spots)
    d.mobs:SetItems(FT.Farm.Mobs(itemID, 10))
    d:Show()
    d:Raise()
end

FT.On("FT_FARM_LOGGED", function()
    if win and win:IsShown() and win.itemID then FT.Debounce("farmWin", 1, function() FT.ShowFarm(win.itemID) end) end
end)
