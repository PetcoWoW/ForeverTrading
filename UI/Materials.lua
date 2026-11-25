-- Wolf of Booty Bay: the materials of one craft of an item (its most profitable recipe) - each at its cheapest
-- (auction house, vendor or your own craft) with its 24h move - and what one craft costs, brings in and leaves.
-- Under the order book on the Market page and in the item window.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local SOURCE_TAG = { ah = "AH", vendor = "vendor", ["vendor~"] = "vendor~", craft = "craft" }
local ROW_H = 22
local MAX_ROWS = 6
local TOP, BOTTOM = 32, 66

-- onPick(itemID): a material clicked
function UI.Materials(parent, onPick)
    local f = UI.Panel(parent, "bg1", "line")
    f.title = UI.Text(f, 13, "text")
    f.title:SetPoint("TOPLEFT", 12, -10)
    f.title:SetText(L["Materials per craft"])
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
        { key = "unit", title = "", width = 60, justify = "RIGHT", size = 11 },
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
            row.cells.unit:SetText(part.unit and FT.Money(part.unit, "short") or FT.C("down", L["no price"]))
            local m = FT.Market.Row(part.itemID)
            row.cells.ch:SetText(FT.Pct(m and m.ch1))
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
                GameTooltip:AddLine(FT.Money(part.unit) .. "  " .. FT.C("dim", tag) .. "   x" .. part.qty .. "  =  "
                    .. FT.Money(part.total or part.unit * part.qty), 0.85, 0.87, 0.9)
            else
                GameTooltip:AddLine(L["no price"], 0.96, 0.27, 0.36)
            end
            if part.via then
                GameTooltip:AddLine(string.format(L["Cheaper to craft yourself (%s)"], part.via.name or ""), 0.05, 0.8, 0.5)
            end
            GameTooltip:Show()
        end,
    })
    f.list:SetPoint("TOPLEFT", 1, -TOP)
    f.list:SetPoint("BOTTOMRIGHT", -1, BOTTOM)

    -- one craft: cost, what it brings in, profit
    f.sep = UI.HLine(f, "line")
    f.sep:SetPoint("BOTTOMLEFT", 1, BOTTOM - 4)
    f.sep:SetPoint("BOTTOMRIGHT", -1, BOTTOM - 4)
    local function Line(y, label)
        local l = UI.Text(f, 11, "muted")
        l:SetPoint("BOTTOMLEFT", 12, y)
        l:SetText(label)
        local v = UI.Text(f, 12, "text", "RIGHT")
        v:SetPoint("BOTTOMRIGHT", -12, y)
        return v
    end
    f.cost = Line(42, L["Cost per craft"])
    f.revenue = Line(25, L["Brings in"])
    f.profit = Line(8, L["Profit"])

    -- the item's recipe: true and the height the panel wants when there is one (nil: nothing to show)
    function f:SetItem(id)
        local r = id and FT.Craft.Best(id)
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
        self.cost:SetText(e.complete and FT.Money(e.cost, "short") or FT.C("dim", L["incomplete"]))
        local rev = e.revenue and FT.Money(e.revenue, "short") or FT.C("dim", "—")
        if e.via == "vendor" then rev = rev .. FT.C("dim", " (" .. L["vendor"] .. ")") end
        self.revenue:SetText(rev)
        if e.profit then
            self.profit:SetText(FT.C(e.profit >= 0 and "up" or "down", FT.SignedMoney(e.profit))
                .. FT.C("dim", string.format("  %d%%", math.floor((e.margin or 0) * 100 + 0.5))))
        else
            self.profit:SetText(FT.C("dim", "—"))
        end
        local n = math.min(MAX_ROWS, math.max(1, #(e.parts or {})))
        return true, TOP + n * ROW_H + 6 + BOTTOM
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
