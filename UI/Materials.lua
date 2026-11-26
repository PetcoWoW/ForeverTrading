-- Wolf: the craft breakdown of an item. Its recipe (one of your characters' if one knows it, else the game's), each
-- material at its cheapest (auction house, vendor or your own craft) with what it adds to one craft and its move
-- this week; then the sum: what one craft costs, what it sells for after the auction house's cut, the profit, how
-- many you could make from what you hold - and what to do: craft it or not, which materials to hold, sell or buy.
-- Beside the chart on the Market page and in the item window.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local SOURCE_TAG = { ah = "AH", vendor = "vendor", ["vendor~"] = "vendor~", craft = "craft" }
local ROW_H = 22
local MAX_ROWS = 6
local TOP = 46
local LINE_H = 17
local RISING, FALLING = 0.10, -0.10

-- the recipe of an item: the best of your characters' (most profit), else the game's
local function RecipeOf(id)
    local r = FT.Craft.Best(id)
    if r then return r, true end
    r = FT.Futures and FT.Futures.Recipe and FT.Futures.Recipe(id)
    return r, r ~= nil and next(r.knownBy or {}) ~= nil
end
UI.RecipeOf = RecipeOf

local function Ch7(id)
    local s = FT.An.Stats(id)
    return s and s.ch7
end

-- what to do, a few short lines: craft it or not, then the materials worth holding, selling or buying
local function Advice(id, r, e, known)
    local out = {}
    local parts = e.parts or {}
    -- how many crafts the materials you hold make
    local canMake
    for _, part in ipairs(parts) do
        if part.itemID and part.source ~= "vendor" then
            local n = math.floor(FT.Port.Count(part.itemID) / math.max(1, part.qty or 1))
            canMake = canMake and math.min(canMake, n) or n
        end
    end
    local who = known and FT.Craft.KnownByText(r) or nil
    if e.profit and e.complete then
        local pct = math.floor((e.margin or 0) * 100 + 0.5)
        if (e.margin or 0) >= 0.02 then
            local s = FT.C("up", L["Worth crafting"]) .. ": " .. string.format(L["+%s a craft (%d%%)"], FT.Money(math.floor(e.profit), "short"), pct)
            if not known then s = s .. FT.C("dim", " - " .. L["none of your characters knows it"]) end
            out[#out + 1] = s
        elseif e.profit >= 0 then
            out[#out + 1] = FT.C("muted", L["Break-even"]) .. ": " .. L["it sells for about what its materials cost"]
        else
            out[#out + 1] = FT.C("down", L["Not worth crafting now"]) .. ": " .. string.format(L["the materials cost %s more than it sells for"],
                FT.Money(math.floor(-e.profit), "short"))
        end
    elseif not e.sellUnit then
        out[#out + 1] = FT.C("muted", L["No price yet"]) .. ": " .. L["no one sells it, so there's nothing to compare the materials with"]
    else
        out[#out + 1] = FT.C("muted", L["Some materials have no price"]) .. ": " .. L["the sum isn't complete"]
    end

    -- the materials: what you hold that's moving, then dips worth buying when crafting pays
    local notes = {}
    for _, part in ipairs(parts) do
        local mid = part.itemID
        local ch = mid and part.source ~= "vendor" and Ch7(mid)
        if ch then
            local held = FT.Port.Count(mid)
            local value = held * (part.unit or 0)
            if held > 0 and ch >= RISING then
                notes[#notes + 1] = { w = value * ch, text = FT.C("accent", L["Hold"]) .. " " .. string.format(L["your %s %s: %s this week"],
                    FT.Num(held), FT.ItemText(mid), FT.Pct(ch)) }
            elseif held > 0 and ch <= FALLING then
                notes[#notes + 1] = { w = value * -ch, text = FT.C("down", L["Sell"]) .. " " .. string.format(L["your %s %s if you won't craft: %s this week"],
                    FT.Num(held), FT.ItemText(mid), FT.Pct(ch)) }
            elseif held == 0 and ch <= FALLING and (e.margin or 0) >= 0.02 then
                notes[#notes + 1] = { w = (part.total or 0) * -ch, text = FT.C("up", L["Buy the dip"]) .. " " .. string.format(L["on %s: %s this week"],
                    FT.ItemText(mid), FT.Pct(ch)) }
            end
        end
    end
    table.sort(notes, function(a, b) return a.w > b.w end)
    for i = 1, math.min(2, #notes) do out[#out + 1] = notes[i].text end

    if canMake and canMake > 0 then
        out[#out + 1] = FT.C("dim", string.format(L["Your materials make %s"], FT.Num(canMake)))
    end
    -- a raid consumable: the timing
    local days = FT.Futures and FT.Futures.Days and FT.Futures.Days()
    if days then
        for _, c in ipairs(FT.FUTURES and FT.FUTURES.consumables or {}) do
            if c.id == id then
                out[#out + 1] = FT.C("dim", string.format(L["Raids open in %d days: it usually climbs toward raid night"], days))
                break
            end
        end
    end
    return out
end

-- onPick(itemID): a material clicked
function UI.Materials(parent, onPick)
    local f = UI.Panel(parent, "bg1", "line")
    f.title = UI.Text(f, 13, "text")
    f.title:SetPoint("TOPLEFT", 12, -10)
    f.title:SetText(L["Craft breakdown"])
    f.who = UI.Text(f, 10, "dim")
    f.who:SetPoint("TOPLEFT", 12, -28)
    f.who:SetPoint("RIGHT", -10, 0)
    f.recipe = UI.Button(f, L["Recipe"], 10, 18, "default", function()
        if f.r then FT.OpenRecipe(f.r.key) end
    end)
    f.recipe.label:SetFont(UI.FONT, UI.Size(11), "")
    f.recipe:FitText(16)
    f.recipe:SetPoint("TOPRIGHT", -6, -7)
    f.recipe:SetTip(L["Recipe"], L["Open it on the Craft page"])

    local cols = {
        { key = "name", title = "", width = "fill", make = function(row)
            local c = CreateFrame("Frame", nil, row)
            c:SetHeight(ROW_H)
            c.icon = UI.Icon(c, 16)
            c.icon:SetPoint("LEFT")
            c.text = UI.Text(c, 11, "text")
            c.text:SetPoint("LEFT", c.icon, "RIGHT", 6, 0)
            c.text:SetPoint("RIGHT")
            return c
        end, cellHeight = ROW_H },
        { key = "total", title = "", width = 64, justify = "RIGHT", size = 11 },
        { key = "ch", title = "", width = 44, justify = "RIGHT", size = 11 },
    }
    f.list = UI.List(f, {
        rowHeight = ROW_H, cols = cols,
        liveID = function(part) return part.itemID end,
        update = function(row, part)
            local c = row.cells.name
            c.icon:SetItem(part.itemID)
            -- how many first: the name may be cut short in the narrow column
            c.text:SetText(FT.C("dim", part.qty .. "x ") .. FT.ItemText(part.itemID))
            local total = part.total or (part.unit and part.unit * part.qty)
            row.cells.total:SetText(total and FT.Money(math.floor(total), "short") or FT.C("down", L["no price"]))
            row.cells.ch:SetText(part.source == "vendor" and FT.C("dim", L["vendor"]) or FT.Pct(Ch7(part.itemID)))
        end,
        onClick = function(part)
            if UI.ItemClick(part.itemID) then return end
            if onPick then onPick(part.itemID) end
        end,
        onEnter = function(row, part)
            UI.TipItem(row, part.itemID)
            GameTooltip:AddLine(" ")
            if part.unit then
                local tag = part.source and L[SOURCE_TAG[part.source] or part.source] or ""
                GameTooltip:AddLine(FT.Money(part.unit) .. " " .. L["each"] .. "  " .. FT.C("dim", tag) .. "   x" .. part.qty .. "  =  "
                    .. FT.Money(math.floor(part.total or part.unit * part.qty)), 0.85, 0.87, 0.9)
            else
                GameTooltip:AddLine(L["no price"], 0.96, 0.27, 0.36)
            end
            local ch = Ch7(part.itemID)
            if ch then GameTooltip:AddLine(L["This week"] .. ": " .. FT.Pct(ch), 0.85, 0.87, 0.9) end
            local held = FT.Port.Count(part.itemID)
            if held > 0 then GameTooltip:AddLine(string.format(L["You hold %s"], FT.Num(held)), 0.85, 0.87, 0.9) end
            if part.via then
                GameTooltip:AddLine(string.format(L["Cheaper to craft yourself (%s)"], part.via.name or ""), 0.05, 0.8, 0.5)
            end
            GameTooltip:Show()
        end,
    })

    -- the sum of one craft
    f.sep = UI.HLine(f, "line")
    local function Line(label)
        local l = UI.Text(f, 11, "muted")
        l:SetText(label)
        local v = UI.Text(f, 12, "text", "RIGHT")
        return { label = l, value = v }
    end
    f.sum = { Line(L["Materials"]), Line(L["Sells for"]), Line(L["Profit a craft"]) }
    f.advice = UI.Text(f, 11, "text")
    f.advice:SetJustifyV("TOP")
    if f.advice.SetWordWrap then f.advice:SetWordWrap(true) end
    if f.advice.SetSpacing then f.advice:SetSpacing(3) end

    -- lays it out from the top: the list's rows, the sum, the advice; returns the height
    local function Place(n, adviceText)
        local w = f:GetWidth()
        if not w or w <= 0 then w = 280 end
        local y = TOP
        f.list:ClearAllPoints()
        f.list:SetPoint("TOPLEFT", 1, -y)
        f.list:SetPoint("RIGHT", -1, 0)
        f.list:SetHeight(n * ROW_H)
        y = y + n * ROW_H + 6
        f.sep:ClearAllPoints()
        f.sep:SetPoint("TOPLEFT", 1, -y)
        f.sep:SetPoint("TOPRIGHT", -1, -y)
        y = y + 6
        for _, s in ipairs(f.sum) do
            s.label:ClearAllPoints()
            s.label:SetPoint("TOPLEFT", 12, -y)
            s.value:ClearAllPoints()
            s.value:SetPoint("TOPRIGHT", -12, -y)
            y = y + LINE_H
        end
        y = y + 6
        f.advice:ClearAllPoints()
        f.advice:SetPoint("TOPLEFT", 12, -y)
        f.advice:SetWidth(w - 24)
        f.advice:SetText(adviceText)
        -- its height: the game's measure of the wrapped text, or a count of its lines
        local lines = 0
        for line in (adviceText .. "\n"):gmatch("(.-)\n") do
            local plain = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            lines = lines + math.max(1, math.ceil(#plain * UI.Size(11) * 0.52 / math.max(60, w - 24)))
        end
        local h = math.max(f.advice.GetStringHeight and f.advice:GetStringHeight() or 0, lines * (UI.Size(11) + 4))
        f.advice:SetHeight(h)
        return y + h + 10
    end

    -- the item's recipe: true and the height the panel wants when there is one (nil: nothing to show)
    function f:SetItem(id)
        local r, known = nil, false
        if id then r, known = RecipeOf(id) end
        self.r = r
        if not r then
            self.e, self.itemID = nil, nil
            self.list:SetItems({})
            return false, 0
        end
        local e = FT.Craft.Eval(r)
        self.e = e
        self.list:SetItems(e.parts or {}, self.itemID == id)
        self.itemID = id
        -- the Recipe button: only a recipe one of yours knows opens on the Craft page
        self.recipe:SetShown(known and FT.Craft.Best(id) ~= nil)
        self.who:SetText(known and string.format(L["%s knows it"], FT.Craft.KnownByText(r))
            or L["No character of yours knows it"])
        local qty = math.max(1, r.outputQty or 1)
        self.sum[1].value:SetText(e.complete and FT.Money(math.floor(e.cost), "short") or FT.C("dim", L["incomplete"]))
        local rev = e.revenue and FT.Money(math.floor(e.revenue), "short") or FT.C("dim", "—")
        if e.via == "vendor" then rev = rev .. FT.C("dim", " (" .. L["vendor"] .. ")") end
        if qty > 1 and e.revenue then rev = FT.C("dim", qty .. "x  ") .. rev end
        self.sum[2].value:SetText(rev)
        if e.profit and e.complete then
            self.sum[3].value:SetText(FT.C(e.profit >= 0 and "up" or "down", FT.SignedMoney(math.floor(e.profit)))
                .. FT.C("dim", string.format("  %d%%", math.floor((e.margin or 0) * 100 + 0.5))))
        else
            self.sum[3].value:SetText(FT.C("dim", "—"))
        end
        local n = math.min(MAX_ROWS, math.max(1, #(e.parts or {})))
        return true, Place(n, table.concat(Advice(id, r, e, known), "\n"))
    end
    -- the house its prices are of: an item window's own (nil: the one on)
    local setItem = f.SetItem
    function f:SetItem(id) return FT.House.With(self.house, setItem, self, id) end

    -- one of its materials
    function f:Has(id)
        for _, part in ipairs(self.e and self.e.parts or {}) do
            if part.itemID == id then return true end
        end
        return false
    end

    return f
end
