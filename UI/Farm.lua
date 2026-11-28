local _, FT = ...
local L = FT.L
local UI = FT.UI

---------------------------------------------------------------------------
-- Where to farm it (v0.56, redesigned from the farm study): one answer first - the best way for you to get it -
-- then a few other spots with their odds and gold an hour, your own loot in a line, and nothing empty: the window
-- is as tall as what it says. World drops say so honestly (any mob of the level; your level's best farm instead).
-- Opened from Farm it, Drops, the item page, the right-click menu and the farm tip in chat.
---------------------------------------------------------------------------
local win
local MAX_ROWS = 5
local W_BASE = 470
local PAD = 12

local ICONS = {
    mob = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
    skin = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
    node = "Interface\\Icons\\INV_Ore_Copper_01",
    herb = "Interface\\Icons\\INV_Misc_Herb_07",
    vendor = "Interface\\Icons\\INV_Misc_Coin_01",
    quest = "Interface\\GossipFrame\\AvailableQuestIcon",
    zone = "Interface\\Icons\\INV_Misc_Map_01",
    box = "Interface\\Icons\\INV_Box_01",
    favor = "Interface\\Icons\\INV_Letter_15",
}

local function Money(c) return FT.Money(math.floor((c or 0) + 0.5), "short") end

---------------------------------------------------------------------------
-- What the window says: { card = { k, big, where, meta, chips = { {text, tone} } }, others = { rows }, mine, note }
---------------------------------------------------------------------------
local function LowLevel(lv) return tonumber((lv or ""):match("^(%d+)")) end

local function Model(id)
    local Dr, Wh = FT.Drops, FT.Where
    local level = FT.Me and FT.Me.Level() or 60
    local g = Wh.Get(id)
    local unit = Dr.Worth(id)
    local cands = {}
    -- mobs that drop it: how many of it an hour for you, and the mob's steady gold an hour
    for _, x in ipairs(g.drops) do
        local w = x.who
        if w and Dr.Killable(w) then
            local steady, jackpot, kph = Dr.MobHour(w)
            kph = kph or Dr.KillsAnHour(w)
            local lo = LowLevel(w.lv)
            local perHour = x.chance > 0 and kph * x.chance / 10000 or nil
            local dng = Dr.DungeonOf(w.zones)
            cands[#cands + 1] = {
                kind = "mob", who = w, name = w.name, where = dng or (w.zones and w.zones:match("^[^,]+")), lv = w.lv,
                chance = x.chance, perHour = perHour, steady = steady, jackpot = jackpot, kph = kph,
                elite = Dr.Elite(w), rare = Dr.Rare(w), dungeon = dng,
                high = lo and lo > level + 3,
                score = (perHour and perHour * unit or 0) + (steady or 0) * 0.25 - ((lo and lo > level + 3) and 1e9 or 0),
            }
        end
    end
    -- (v0.61) skinning and gathering, in the same terms as drops: how many an hour and gold an hour - skinning a
    -- mob also gives its own loot; a node about 40 an hour in a good zone, ~2 a node. Only the professions one of your
    -- characters has can be the answer; the others show as other spots, with what they need
    local has = FT.Me and FT.Me.Has or function() return true end
    local NODES_AN_HOUR, PER_NODE, PER_SKIN = 40, 2, 1.4
    for _, x in ipairs(g.skin) do
        local w = x.who
        if w then
            local kph = Dr.KillsAnHour(w)
            local perHour = (x.chance or 0) > 0 and kph * x.chance / 10000 * PER_SKIN or nil
            local steady = Dr.MobHour(w)
            local lo = LowLevel(w.lv)
            local can = has("Skinning")
            cands[#cands + 1] = { kind = "skin", who = w, name = w.name, where = w.zones and w.zones:match("^[^,]+"), lv = w.lv, chance = x.chance,
                needs = "Skinning", can = can, perHour = perHour, steady = steady, kph = kph, high = lo and lo > level + 3,
                score = (can and 0 or -1e8) + (perHour and perHour * unit or 0) + (steady or 0) * 0.25 - ((lo and lo > level + 3) and 1e9 or 0) }
        end
    end
    for _, x in ipairs(g.nodes) do
        local o = x.who
        if o and not o.chest then
            local herb = FT.Farm.KindOf(id) == "herb"
            local prof = herb and "Herbalism" or "Mining"
            local can = has(prof)
            local perHour = (x.chance or 0) > 0 and NODES_AN_HOUR * x.chance / 10000 * PER_NODE or nil
            cands[#cands + 1] = { kind = herb and "herb" or "node", name = o.name, needs = prof, can = can,
                where = o.zones and o.zones:match("^[^,]+"), chance = x.chance, perHour = perHour,
                score = (can and 0 or -1e8) + (perHour and perHour * unit or 0) }
        end
    end
    local vendor
    for _, v in ipairs(g.vendors) do
        if v.zones and (not v.fac or v.fac == "" or v.fac == "AH" or v.fac == (UnitFactionGroup and (UnitFactionGroup("player") == "Alliance" and "A" or "H"))) then
            vendor = vendor or v
            cands[#cands + 1] = { kind = "vendor", name = v.name, where = v.zones and v.zones:match("^[^,]+"), score = -3 }
        end
    end
    for _, q in ipairs(g.quests) do
        cands[#cands + 1] = { kind = "quest", name = q.name, lv = q.lv and tostring(q.lv), score = -4 }
    end
    for _, b in ipairs(g.boxes) do
        cands[#cands + 1] = { kind = "box", name = FT.Name(b.itemID) or L["a container"], chance = b.chance, score = -6 }
    end
    -- the spots written for raw materials (zones by level)
    local spots, data = FT.Farm.Spots(id, level)
    for _, sp in ipairs(spots or {}) do
        cands[#cands + 1] = { kind = "zone", name = sp.zone, lv = sp.lo .. "-" .. sp.hi, what = sp.what, fit = sp.fit, yours = sp.yours,
            score = (sp.fit == 0 and 1e6 or 0) - sp.fit, skill = data and data.skill, gather = data and data.kind }
    end
    table.sort(cands, function(a, b) return a.score > b.score end)

    local card, chips = { chips = {} }, nil
    chips = card.chips
    local worldLv, worldOne = Dr.World(id)
    local bestMob
    for _, c in ipairs(cands) do if c.kind == "mob" and not c.high then bestMob = c break end end
    local gathered = FT.Farm.IsRaw and FT.Farm.IsRaw(id)
    local answer
    if worldLv and not (bestMob and bestMob.chance >= 200) and not vendor and #g.nodes == 0 and #g.skin == 0 then
        -- a world drop: no spot is better than another
        card.k = L["WORLD DROP · NOT A FARM"]
        card.big = string.format(L["Any mob level %d and up"], worldLv)
        card.meta = string.format(L["About 1 in %s kills, from any mob of that level: no spot is better than another. Farm what pays anyway, and this is a bonus."], FT.Num(worldOne))
        local best = Dr.BestSpot(level)
        if best then
            chips[#chips + 1] = { string.format(L["your level's best farm: %s, %s · ~%s an hour"], best.who.name,
                best.who.zones and best.who.zones:match("^[^,]+") or "?", FT.Money(math.floor(best.steady), "gold")) }
        end
    elseif vendor and not gathered then
        answer = nil
        card.k = L["BUY IT"]
        card.big = string.format(L["Sold by %s"], vendor.name)
        card.where = vendor.zones and vendor.zones:match("^[^,]+")
        card.meta = L["A vendor sells it: no farming needed."]
    else
        answer = cands[1]
        if answer and answer.kind == "mob" then
            local solo = not answer.elite and not answer.dungeon
            card.k = solo and string.format(L["BEST SOLO FOR YOU (LEVEL %d)"], level) or L["BEST WAY TO GET IT"]
            card.big, card.where = answer.name, answer.where
            local meta = {}
            if answer.lv then meta[#meta + 1] = string.format(L["Level %s"], answer.lv) .. (answer.elite and (" " .. L["elite"]) or "") end
            meta[#meta + 1] = Dr.Odds(answer.chance) or L["the odds aren't known yet (new Forever loot)"]
            if answer.steady then meta[#meta + 1] = FT.C("up", "~" .. FT.Money(math.floor(answer.steady), "gold") .. " " .. L["an hour"]) .. " " .. L["steady, all its loot counted"] end
            card.meta = table.concat(meta, "  ·  ")
            chips[#chips + 1] = answer.rare and { L["RARE SPAWN · up now and then"], "warn" } or (solo and { L["SOLO"], "solo" } or { L["GROUP"] .. (answer.elite and (" · " .. L["elite"]) or ""), "group" })
            if answer.who.spawns and answer.who.spawns > 0 then
                chips[#chips + 1] = { string.format(L["%d spawns · respawn %d min"], answer.who.spawns, math.floor((answer.who.respawn or 300) / 60 + 0.5)) }
            end
            if answer.perHour and answer.perHour >= 0.05 then
                chips[#chips + 1] = { string.format(L["~%s of it an hour"], answer.perHour >= 1 and FT.Num(math.floor(answer.perHour + 0.5)) or string.format("%.1f", answer.perHour)) }
            end
            for _, z in ipairs(cands) do
                if z.kind == "zone" and z.skill then
                    chips[#chips + 1] = { string.format(L["or gather it: %s · %s %d"], z.name, L[z.gather == "herb" and "Herbalism" or "Mining"] or "", z.skill) }
                    break
                end
            end
            if answer.jackpot and answer.jackpot >= 10000 then
                chips[#chips + 1] = { "+ " .. string.format(L["rare drops ~%s an hour"], FT.Money(math.floor(answer.jackpot), "gold")) }
            end
        elseif answer and (answer.kind == "skin" or answer.kind == "node" or answer.kind == "herb") and answer.can then
            card.k = string.format(L["BEST FOR YOU (LEVEL %d)"], level)
            card.big, card.where = answer.name, answer.where
            local meta = {}
            meta[#meta + 1] = L[answer.needs]
            if answer.lv then meta[#meta + 1] = string.format(L["Level %s"], answer.lv) end
            if answer.perHour then meta[#meta + 1] = string.format(L["~%s of it an hour"], answer.perHour >= 1 and FT.Num(math.floor(answer.perHour + 0.5)) or string.format("%.1f", answer.perHour)) end
            local gph = (answer.perHour or 0) * unit + (answer.steady or 0)
            if gph > 0 then meta[#meta + 1] = FT.C("up", "~" .. FT.Money(math.floor(gph), "gold") .. " " .. L["an hour"]) end
            card.meta = table.concat(meta, "  ·  ")
            chips[#chips + 1] = { string.format(L["needs %s"], L[answer.needs]), "solo" }
        elseif answer and answer.kind == "zone" then
            card.k = string.format(L["BEST FOR YOU (LEVEL %d)"], level)
            card.big = answer.name
            card.meta = (answer.what or "") .. (answer.lv and ("  ·  " .. string.format(L["level %s"], answer.lv)) or "")
            if answer.skill then chips[#chips + 1] = { string.format(L["needs %s %d"], L[answer.gather == "herb" and "Herbalism" or "Mining"] or "", answer.skill) } end
        elseif answer then
            card.k = L["WHERE IT COMES FROM"]
            card.big, card.where = answer.name, answer.where
            card.meta = (answer.kind == "skin" and (L["Skinning"] .. "  ·  ") or "") .. (Dr.Odds(answer.chance) or "")
                .. (answer.lv and ("  ·  " .. string.format(L["level %s"], answer.lv)) or "")
        else
            card.k = L["WHERE IT COMES FROM"]
            card.big = L["Not in Wolf's sources yet"]
            card.meta = L["Loot one and Wolf counts it: where you were and from what."]
        end
    end
    local r = FT.Market.Row(id)
    if r and (r.ch7 or 0) <= -0.15 and (answer and answer.kind == "mob") then chips[#chips + 1] = { L["price falling: others found it"], "warn" } end

    -- the other spots: the next best, a few
    local others = {}
    for _, c in ipairs(cands) do
        if c ~= answer and #others < MAX_ROWS and not (c.kind == "vendor" and card.k == L["BUY IT"]) then
            local odds, gph
            if c.kind == "mob" then
                odds = Dr.Odds(c.chance) or L["odds unknown"]
                gph = c.steady and (FT.Money(math.floor(c.steady), "gold") .. L["/h"]) or nil
            elseif c.kind == "skin" or c.kind == "node" or c.kind == "herb" then
                local g2 = (c.perHour or 0) * unit + (c.steady or 0)
                odds = c.can and L[c.needs] or FT.C("dim", string.format(L["needs %s"], L[c.needs]))
                gph = g2 > 0 and (FT.Money(math.floor(g2), "gold") .. L["/h"]) or nil
            elseif c.kind == "zone" then
                odds = c.lv and string.format(L["level %s"], c.lv) or ""
            else
                odds = Dr.Odds(c.chance) or (c.kind == "vendor" and L["sells it"]) or (c.kind == "quest" and L["a reward"]) or ""
            end
            local where = {}
            if c.where then where[#where + 1] = L[c.where] or c.where end
            if c.kind == "mob" and c.lv then where[#where + 1] = c.lv .. (c.elite and (" " .. L["elite"]) or "") end
            if c.rare then where[#where + 1] = L["rare spawn"] end
            others[#others + 1] = { kind = c.kind, name = c.name, where = table.concat(where, " · "),
                odds = odds .. (gph and (" · " .. gph) or ""), ratio = c.chance and c.chance > 0 and c.chance or (c.steady and 1) or 0, steady = c.steady }
        end
    end
    -- the bars: the odds against the best of them
    local top = 0
    for _, o in ipairs(others) do top = math.max(top, o.ratio or 0) end
    for _, o in ipairs(others) do o.bar = top > 0 and (o.ratio or 0) / top or 0 end

    -- your own loot, one line
    local mine
    local m = FT.Farm.Mobs(id, 1)[1]
    if m then
        local gh = m.zone and FT.Farm.ZoneGoldHour(m.zone)
        mine = string.format(L["Your loot: %s from %s %s (%s)"], FT.Num(m.n), FT.Num(m.corpses), m.name or L["mobs"],
            FT.Drops.Odds(math.floor(m.per * 10000 + 0.5)) or "")
            .. (gh and ("  ·  " .. string.format(L["%s an hour there"], FT.Money(math.floor(gh), "gold"))) or "")
    elseif not worldLv and card.k ~= L["BUY IT"] then
        mine = L["Your loot: none yet. Farm it and Wolf counts your own odds."]
    end
    local note = worldLv and L["World drops aren't in Drops: no mob is a real farm for them."]
        or L["Odds: ForeverDB and player counts; yours once you've looted 5+."]
    return { card = card, others = others, mine = mine, mineEmpty = not m, note = note, world = worldLv ~= nil }
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local function Chip(parent)
    local c = UI.Panel(parent, "bg2", "line")
    c.text = UI.Text(c, 10, "muted")
    c.text:SetPoint("CENTER", 0, 0)
    return c
end

local function Row(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(UI.RowH(22))
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(14, 14)
    r.icon:SetPoint("LEFT", 8, 0)
    r.bar = CreateFrame("Frame", nil, r)
    r.bar:SetSize(56, 5)
    r.bar:SetPoint("RIGHT", -8, 0)
    r.bar.bg = UI.Tex(r.bar, "BACKGROUND", "line", 0.6)
    r.bar.bg:SetAllPoints()
    r.bar.fill = UI.Tex(r.bar, "ARTWORK", "accent", 1)
    r.bar.fill:SetPoint("TOPLEFT")
    r.bar.fill:SetPoint("BOTTOMLEFT")
    r.odds = UI.Text(r, 11, "text", "RIGHT")
    r.odds:SetPoint("RIGHT", r.bar, "LEFT", -8, 0)
    r.name = UI.Text(r, 12, "text")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.name:SetPoint("RIGHT", r.odds, "LEFT", -8, 0)
    r.line = UI.Tex(r, "BACKGROUND", "line", 0.35)
    r.line:SetHeight(1)
    r.line:SetPoint("TOPLEFT", 4, 0)
    r.line:SetPoint("TOPRIGHT", -4, 0)
    return r
end

local function Win()
    if win then return win end
    UI.ResolveFont()
    local ts = tonumber(FT.S and FT.S.textSize) or 0
    local d = CreateFrame("Frame", "WolfOfBootyBayFarm", UIParent)
    d:SetWidth(W_BASE + 30 * ts)
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
    if d.bg then d.bg:SetAlpha(0.94) end

    -- the head: the item, how it sells, Best crafts, Wowhead, close
    d.icon = UI.Icon(d, 34)
    d.icon:SetPoint("TOPLEFT", PAD + 2, -PAD)
    d.icon:EnableMouse(true)
    d.icon:SetScript("OnEnter", function(self) if d.itemID then UI.TipItem(self, d.itemID) end end)
    d.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    d.close = UI.CloseButton(d, function() d:Hide() end, 26)
    d.close:SetPoint("TOPRIGHT", -6, -6)
    d.wowhead = UI.Button(d, L["Wowhead"], 10, 20, "default", function() FT.Farm.Wowhead(d.itemID) end)
    d.wowhead:FitText(16)
    d.wowhead:SetPoint("RIGHT", d.close, "LEFT", -4, 0)
    d.wowhead:SetTip(L["Wowhead"], L["Its page on Wowhead (WoW Forever): every mob that drops it, with drop chances and a map."])
    d.crafts = UI.Button(d, L["Best crafts"], 10, 20, "default", function() FT.ShowBestUse(d.itemID) end)
    d.crafts:FitText(16)
    d.crafts:SetPoint("RIGHT", d.wowhead, "LEFT", -4, 0)
    d.crafts:SetTip(L["Best crafts"], L["The finished products made from it, the best sellers first."])
    d.title = UI.Text(d, 14, "text")
    d.title:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 10, -1)
    d.title:SetPoint("RIGHT", d.crafts, "LEFT", -8, 0)
    d.sum = UI.Text(d, 11, "muted")
    d.sum:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -5)
    d.sum:SetPoint("RIGHT", d, "RIGHT", -PAD, 0)
    d.headLine = UI.Tex(d, "ARTWORK", "line", 0.6)
    d.headLine:SetHeight(1)
    d.headLine:SetPoint("TOPLEFT", 4, -(PAD + 34 + 9))
    d.headLine:SetPoint("TOPRIGHT", -4, -(PAD + 34 + 9))

    -- the answer
    d.card = UI.Panel(d, "bg2", "accent")
    d.card:SetPoint("TOPLEFT", PAD, -(PAD + 34 + 18))
    d.card:SetPoint("RIGHT", d, "RIGHT", -PAD, 0)
    d.card.k = UI.Text(d.card, 10, "accent")
    d.card.k:SetPoint("TOPLEFT", 11, -9)
    d.card.big = UI.Text(d.card, 14, "text")
    d.card.big:SetPoint("TOPLEFT", d.card.k, "BOTTOMLEFT", 0, -5)
    d.card.big:SetPoint("RIGHT", d.card, "RIGHT", -11, 0)
    d.card.meta = UI.Text(d.card, 11, "muted")
    d.card.meta:SetPoint("TOPLEFT", d.card.big, "BOTTOMLEFT", 0, -4)
    d.card.meta:SetPoint("RIGHT", d.card, "RIGHT", -11, 0)
    if d.card.meta.SetWordWrap then d.card.meta:SetWordWrap(true) end
    d.chips = {}

    -- the other spots
    d.otherHead = UI.Text(d, 12, "accent")
    d.otherSub = UI.Text(d, 10, "dim", "RIGHT")
    d.list = UI.Panel(d, "bg1", "line")
    d.rows = {}
    for i = 1, MAX_ROWS do
        local r = Row(d.list)
        r:SetPoint("TOPLEFT", 1, -2 - (i - 1) * UI.RowH(22))
        r:SetPoint("RIGHT", d.list, "RIGHT", -1, 0)
        if i == 1 then r.line:Hide() end
        d.rows[i] = r
    end

    -- your loot, and the small print
    d.mine = UI.Panel(d, "bg1", "line")
    d.mine.text = UI.Text(d.mine, 11, "muted")
    d.mine.text:SetPoint("LEFT", 10, 0)
    d.mine.text:SetPoint("RIGHT", -10, 0)
    d.note = UI.Text(d, 10, "dim")

    tinsert(UISpecialFrames, "WolfOfBootyBayFarm")
    d:Hide()
    win = d
    return d
end

local TONES = { solo = "up", group = "accent", warn = "down" }

-- lay the window out for a model: top to bottom, as tall as what it holds
local function Layout(d, mdl)
    local width = d:GetWidth()
    local inner = width - 2 * PAD
    local c = d.card
    c.k:SetText(mdl.card.k or "")
    c.big:SetText((mdl.card.big or "") .. (mdl.card.where and FT.C("dim", "  ·  " .. (L[mdl.card.where] or mdl.card.where)) or ""))
    c.meta:SetWidth(inner - 22)
    c.meta:SetText(mdl.card.meta or "")
    local metaH = 0
    if mdl.card.meta and mdl.card.meta ~= "" then
        local lines = math.max(1, math.ceil((c.meta:GetStringWidth() or 0) / math.max(1, inner - 22)))
        metaH = math.ceil(math.max(c.meta:GetStringHeight() or 0, lines * (UI.Size(11) + 3)))
    end
    c.meta:SetHeight(math.max(1, metaH))
    local chipTop = 9 + UI.Size(10) + 5 + UI.Size(14) + 4 + metaH + 6
    -- the chips, left to right, wrapping
    for _, ch in ipairs(d.chips) do ch:Hide() end
    local x, y, chipH = 11, 0, UI.Size(10) + 8
    local nChips = #(mdl.card.chips or {})
    for i, ch in ipairs(mdl.card.chips or {}) do
        local cp = d.chips[i] or Chip(c)
        d.chips[i] = cp
        cp.text:SetText(ch[1])
        UI.SetTextColor(cp.text, TONES[ch[2]] or "muted")
        local w = math.min((cp.text:GetStringWidth() or 40) + 14, inner - 22)
        if x + w > inner - 11 and x > 11 then x, y = 11, y + chipH + 4 end
        cp:SetSize(w, chipH)
        cp:ClearAllPoints()
        cp:SetPoint("TOPLEFT", c, "TOPLEFT", x, -chipTop - y)
        cp:Show()
        x = x + w + 4
    end
    local chipsH = nChips > 0 and (y + chipH + 8) or 0
    local cardH = 9 + UI.Size(10) + 5 + UI.Size(14) + 4 + metaH + chipsH + 10
    c:SetHeight(cardH)
    local top = PAD + 34 + 18 + cardH + 10
    -- the other spots
    local n = #mdl.others
    if n > 0 then
        d.otherHead:ClearAllPoints()
        d.otherHead:SetPoint("TOPLEFT", PAD + 2, -top)
        d.otherHead:SetText(mdl.world and L["Where it has dropped"] or L["Other spots"])
        d.otherSub:ClearAllPoints()
        d.otherSub:SetPoint("TOPRIGHT", -PAD - 2, -top - 1)
        d.otherSub:SetText(L["odds · steady gold an hour"])
        top = top + UI.Size(12) + 6
        d.list:ClearAllPoints()
        d.list:SetPoint("TOPLEFT", PAD, -top)
        d.list:SetPoint("RIGHT", d, "RIGHT", -PAD, 0)
        local rh = UI.RowH(22)
        d.list:SetHeight(n * rh + 4)
        for i, r in ipairs(d.rows) do
            local o = mdl.others[i]
            r:SetShown(o ~= nil)
            if o then
                r.icon:SetTexture(ICONS[o.kind] or ICONS.mob)
                r.icon:SetTexCoord(o.kind == "mob" and 0 or 0.08, o.kind == "mob" and 1 or 0.92, o.kind == "mob" and 0 or 0.08, o.kind == "mob" and 1 or 0.92)
                UI.FitBits(r.name, FT.C("text", o.name or "?") .. (o.where ~= "" and FT.C("dim", "  ·  " .. o.where) or ""))
                r.odds:SetText(o.odds or "")
                r.bar.fill:SetWidth(math.max(1, 56 * (o.bar or 0)))
                r.bar.fill:SetShown((o.bar or 0) > 0)
            end
        end
        d.otherHead:Show(); d.otherSub:Show(); d.list:Show()
        top = top + n * rh + 4 + 10
    else
        d.otherHead:Hide(); d.otherSub:Hide(); d.list:Hide()
    end
    -- your loot
    if mdl.mine then
        d.mine:ClearAllPoints()
        d.mine:SetPoint("TOPLEFT", PAD, -top)
        d.mine:SetPoint("RIGHT", d, "RIGHT", -PAD, 0)
        local mh = UI.Size(11) + 14
        d.mine:SetHeight(mh)
        UI.SetTextColor(d.mine.text, mdl.mineEmpty and "dim" or "text")
        UI.FitBits(d.mine.text, mdl.mine)
        d.mine:Show()
        top = top + mh + 8
    else
        d.mine:Hide()
    end
    d.note:ClearAllPoints()
    d.note:SetPoint("TOPLEFT", PAD + 2, -top)
    d.note:SetPoint("RIGHT", d, "RIGHT", -PAD, 0)
    UI.FitBits(d.note, mdl.note or "")
    top = top + UI.Size(10) + PAD
    d:SetHeight(top)
end

function FT.ShowFarm(itemID)
    if not itemID then return end
    local d = Win()
    d.itemID = itemID
    d.icon:SetItem(itemID)
    d.title:SetText(FT.ItemText(itemID, 40))
    d.crafts:SetShown(FT.Craft.UsedIn(itemID) ~= nil)
    -- how it sells
    local r = FT.Market.Row(itemID)
    local rate = FT.Sales.Rate(itemID)
    local bits = {}
    if r and r.price then
        -- (v0.62) what it sells for, when that's well under its listing
        local note = FT.WorthNote(itemID)
        bits[#bits + 1] = note and FT.C("orange", note) or (FT.C("text", FT.Money(r.price, "short")) .. FT.C("dim", " " .. L["each"]))
    end
    if rate then bits[#bits + 1] = FT.Sales.PerDayText(rate) end
    if r and r.ch7 then bits[#bits + 1] = FT.C(r.ch7 >= 0 and "up" or "down", FT.Pct(r.ch7) .. " " .. L["this week"]) end
    UI.FitBits(d.sum, table.concat(bits, FT.C("dim", "  ·  ")))
    d.model = Model(itemID)
    Layout(d, d.model)
    d:Show()
    d:Raise()
end
FT.FarmModel = Model

FT.On("FT_FARM_LOGGED", function()
    if win and win:IsShown() and win.itemID then FT.Debounce("farmWin", 1, function() FT.ShowFarm(win.itemID) end) end
end)

---------------------------------------------------------------------------
-- (v0.61) A dungeon's card: a click on one in Farm it > Dungeons. The answer first - gold each a run (or yours
-- alone, solo) and an hour - then what a run is made of in one bar (coin, what vendors pay, what sells, rare drops
-- apart), its best loot, your own runs there, and for solo the caveat. Its whole drop list is a button away.
---------------------------------------------------------------------------
local dwin
local PARTS = { { "coin", "Coin", "accent" }, { "vendor", "To a vendor", "muted" }, { "trade", "Sells on the AH", "up" }, { "jackpot", "Rare drops", "purple" } }

local function DWin()
    if dwin then return dwin end
    UI.ResolveFont()
    local ts = tonumber(FT.S and FT.S.textSize) or 0
    local d = CreateFrame("Frame", "WolfOfBootyBayDungeon", UIParent)
    d:SetWidth(W_BASE + 30 * ts)
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
    d.icon = UI.Icon(d, 34)
    d.icon:SetPoint("TOPLEFT", PAD + 2, -PAD)
    d.icon:SetIcon("Interface\\Icons\\INV_Misc_Key_13")
    d.close = UI.CloseButton(d, function() d:Hide() end, 26)
    d.close:SetPoint("TOPRIGHT", -6, -6)
    d.all = UI.Button(d, L["All its drops"], 10, 20, "default", function()
        d:Hide()
        if d.info and FT.Tabs.signals.ShowDungeonDrops then FT.Tabs.signals.ShowDungeonDrops(d.info.name) end
    end)
    d.all:FitText(16)
    d.all:SetPoint("RIGHT", d.close, "LEFT", -4, 0)
    d.title = UI.Text(d, 15, "text")
    d.title:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 10, -1)
    d.title:SetPoint("RIGHT", d.all, "LEFT", -8, 0)
    d.sum = UI.Text(d, 11, "muted")
    d.sum:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -5)
    d.sum:SetPoint("RIGHT", d, "RIGHT", -PAD, 0)
    d.card = UI.Panel(d, "bg2", "accent")
    d.card.k = UI.Text(d.card, 10, "accent")
    d.card.k:SetPoint("TOPLEFT", 11, -9)
    d.card.big = UI.Text(d.card, 20, "text")
    d.card.big:SetPoint("TOPLEFT", d.card.k, "BOTTOMLEFT", 0, -6)
    d.card.meta = UI.Text(d.card, 12, "muted")
    d.card.meta:SetPoint("TOPLEFT", d.card.big, "BOTTOMLEFT", 0, -5)
    d.card.meta:SetPoint("RIGHT", d.card, "RIGHT", -11, 0)
    d.card.note = UI.Text(d.card, 11, "orange")
    d.card.note:SetPoint("TOPLEFT", d.card.meta, "BOTTOMLEFT", 0, -6)
    d.card.note:SetPoint("RIGHT", d.card, "RIGHT", -11, 0)
    if d.card.note.SetWordWrap then d.card.note:SetWordWrap(true) end
    -- what a run is made of
    d.madeHead = UI.Text(d, 12, "accent")
    d.bar = CreateFrame("Frame", nil, d)
    d.bar:SetHeight(10)
    d.bar.seg = {}
    d.legend = {}
    for i, pt in ipairs(PARTS) do
        d.bar.seg[i] = UI.Tex(d.bar, "ARTWORK", pt[3], 1)
        d.legend[i] = UI.Text(d, 11, "text")
    end
    d.lootHead = UI.Text(d, 12, "accent")
    d.list = UI.Panel(d, "bg1", "line")
    d.rows = {}
    for i = 1, 6 do
        local r = CreateFrame("Frame", nil, d.list)
        r:SetHeight(UI.RowH(22))
        r:SetPoint("TOPLEFT", 1, -2 - (i - 1) * UI.RowH(22))
        r:SetPoint("RIGHT", d.list, "RIGHT", -1, 0)
        r.icon = UI.Icon(r, 16)
        r.icon:SetPoint("LEFT", 8, 0)
        r.val = UI.Text(r, 12, "text", "RIGHT")
        r.val:SetPoint("RIGHT", -10, 0)
        r.name = UI.Text(r, 12, "text")
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
        r.name:SetPoint("RIGHT", r.val, "LEFT", -8, 0)
        r:EnableMouse(true)
        r:SetScript("OnEnter", function(self) if self.id then UI.TipItem(self, self.id) end end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        d.rows[i] = r
    end
    d.mine = UI.Text(d, 11, "muted")
    d.note = UI.Text(d, 10, "dim")
    tinsert(UISpecialFrames, "WolfOfBootyBayDungeon")
    d:Hide()
    dwin = d
    return d
end

-- d: a dungeon from FT.Drops.Dungeons(mode); mode: "full", "trash" or "solo"
function FT.ShowDungeon(info, mode)
    if not info then return end
    local d = DWin()
    d.info = info
    local width = d:GetWidth()
    local inner = width - 2 * PAD
    local solo = info.solo
    d.title:SetText(info.name)
    UI.FitBits(d.sum, string.format(L["Level %s"], info.lv) .. FT.C("dim", "  ·  ") .. string.format(L["the door is in %s"], L[info.door] or info.door)
        .. FT.C("dim", "  ·  ") .. string.format(L["~%d min a run"], info.min))
    local top = PAD + 34 + 14
    -- the answer
    local c = d.card
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", PAD, -top)
    c:SetPoint("RIGHT", d, "RIGHT", -PAD, 0)
    c.k:SetText((solo and L["ON YOUR OWN"]) or (mode == "trash" and L["A GROUP OF 5, THE TRASH ONLY"]) or L["A GROUP OF 5, A FULL CLEAR"])
    c.big:SetText(string.format(solo and L["~%s a run"] or L["~%s each a run"], FT.Money(math.floor(info.each), "gold")))
    local runs = math.floor(60 / math.max(info.min, 1) + 0.5)
    c.meta:SetText(string.format(solo and L["~%s an hour"] or L["~%s an hour each"], FT.Money(math.floor(info.hour), "gold"))
        .. FT.C("dim", "  ·  " .. (runs >= 1 and string.format(L["%d runs an hour"], math.min(runs, 5)) or string.format(L["one run in %d min"], info.min))))
    local note = nil
    if solo then
        note = info.hardSolo and L["Hard solo: under 8 levels below you, its elites hit back. Smaller pulls, and slower."]
            or L["Solo: for a geared class that holds big pulls (warrior, paladin, druid, warlock, mage)."]
    end
    c.note:SetShown(note ~= nil)
    c.note:SetWidth(inner - 22)
    c.note:SetText(note or "")
    local noteH = note and math.max(UI.Size(11) + 2, math.ceil((c.note:GetStringWidth() or 0) / math.max(1, inner - 22)) * (UI.Size(11) + 3)) or 0
    local cardH = 9 + UI.Size(10) + 6 + UI.Size(20) + 5 + UI.Size(12) + (note and (6 + noteH) or 0) + 12
    c:SetHeight(cardH)
    top = top + cardH + 14
    -- what a run is made of: one bar, then its parts in words
    local split = solo and 1 or 5
    local vals = { info.coin / split, (info.vendor or 0) / split, (info.trade or 0) / split, (info.jackpot or 0) / split }
    local total = 0
    for _, v in ipairs(vals) do total = total + math.max(0, v) end
    d.madeHead:ClearAllPoints()
    d.madeHead:SetPoint("TOPLEFT", PAD + 2, -top)
    d.madeHead:SetText(solo and L["What a run is made of"] or L["What your share of a run is made of"])
    top = top + UI.Size(12) + 8
    d.bar:ClearAllPoints()
    d.bar:SetPoint("TOPLEFT", PAD, -top)
    d.bar:SetPoint("RIGHT", d, "RIGHT", -PAD, 0)
    local x = 0
    for i, seg in ipairs(d.bar.seg) do
        local w = total > 0 and inner * math.max(0, vals[i]) / total or 0
        seg:ClearAllPoints()
        seg:SetPoint("TOPLEFT", d.bar, "TOPLEFT", x, 0)
        seg:SetSize(math.max(0.01, w), 10)
        seg:SetShown(w >= 1)
        x = x + w
    end
    top = top + 10 + 8
    -- the parts, two to a line
    local col = inner / 2
    local n = 0
    for i, pt in ipairs(PARTS) do
        local t = d.legend[i]
        local show = vals[i] >= 1
        t:SetShown(show)
        if show then
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", PAD + 2 + (n % 2) * col, -(top + math.floor(n / 2) * (UI.Size(11) + 8)))
            t:SetWidth(col - 8)
            t:SetText(FT.C(pt[3], L[pt[2]]) .. "  " .. FT.C("text", FT.Money(math.floor(vals[i]), "gold"))
                .. (pt[1] == "jackpot" and FT.C("dim", " " .. L["on average"]) or ""))
            n = n + 1
        end
    end
    top = top + math.ceil(n / 2) * (UI.Size(11) + 8) + 8
    -- the best loot
    local items = {}
    for _, t in ipairs(info.top or {}) do if #items < 6 and t.worth >= 100 then items[#items + 1] = t end end
    d.lootHead:SetShown(#items > 0)
    d.list:SetShown(#items > 0)
    if #items > 0 then
        d.lootHead:ClearAllPoints()
        d.lootHead:SetPoint("TOPLEFT", PAD + 2, -top)
        d.lootHead:SetText(L["Its best loot, a run"])
        top = top + UI.Size(12) + 6
        d.list:ClearAllPoints()
        d.list:SetPoint("TOPLEFT", PAD, -top)
        d.list:SetPoint("RIGHT", d, "RIGHT", -PAD, 0)
        local rh = UI.RowH(22)
        d.list:SetHeight(#items * rh + 4)
        for i, r in ipairs(d.rows) do
            local t = items[i]
            r:SetShown(t ~= nil)
            if t then
                r.id = t.id
                r.icon:SetItem(t.id)
                local cnt = t.n >= 10 and FT.Num(math.floor(t.n + 0.5)) or string.format("%.1f", t.n)
                UI.FitBits(r.name, FT.ItemText(t.id, 32) .. FT.C("dim", "  x" .. cnt .. (t.jackpot and ("  ·  " .. L["rare"]) or "")))
                r.val:SetText(FT.Money(math.floor(t.worth / split), "short") .. (split > 1 and FT.C("dim", " " .. L["each"]) or ""))
            end
        end
        top = top + #items * rh + 4 + 10
    end
    -- your own runs, and the small print
    d.mine:ClearAllPoints()
    d.mine:SetPoint("TOPLEFT", PAD + 2, -top)
    d.mine:SetPoint("RIGHT", d, "RIGHT", -PAD, 0)
    UI.FitBits(d.mine, info.measured and FT.C("up", string.format(L["Your own runs here: %s an hour"], FT.Money(math.floor(info.measured), "gold")))
        or L["Run it once: the farming tracker measures your own gold an hour here."])
    top = top + UI.Size(11) + 8
    d.note:ClearAllPoints()
    d.note:SetPoint("TOPLEFT", PAD + 2, -top)
    d.note:SetPoint("RIGHT", d, "RIGHT", -PAD, 0)
    UI.FitBits(d.note, L["Averages of its loot tables at today's prices: a lucky drop beats it, a dry run doesn't."])
    top = top + UI.Size(10) + PAD
    d:SetHeight(top)
    d:Show()
    d:Raise()
end
