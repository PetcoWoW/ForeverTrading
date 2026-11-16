-- ForeverTrading: order book - what is listed at each price, with the depth behind it, and what
-- buying a quantity really costs.
local ADDON, FT = ...
local UI = FT.UI
local C = UI.C
local L = FT.L

local ROW_H = 18


function UI.OrderBook(parent)
    local f = UI.Panel(parent, "bg1", "line")

    f.title = UI.Text(f, 13, "text")
    f.title:SetPoint("TOPLEFT", 12, -10)
    f.title:SetText(L["Order book"])
    f.sub = UI.Text(f, 11, "dim", "RIGHT")
    f.sub:SetPoint("TOPRIGHT", -12, -12)
    f.sub:SetText(L["asks"])

    local cols = {
        { key = "price", title = L["Price"], width = "fill", justify = "LEFT" },
        { key = "qty", title = L["Qty"], width = 52, justify = "RIGHT" },
        { key = "cum", title = L["Total"], width = 58, justify = "RIGHT" },
    }
    f.header = UI.Header(f, cols)
    f.header:SetPoint("TOPLEFT", 1, -32)
    f.header:SetPoint("TOPRIGHT", -1, -32)

    f.rowsArea = CreateFrame("Frame", nil, f)
    f.rowsArea:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 0, -2)
    f.rowsArea:SetPoint("BOTTOMRIGHT", -1, 150)
    f.rows = {}

    -- summary
    f.sep = UI.HLine(f, "line")
    f.sep:SetPoint("BOTTOMLEFT", 1, 148)
    f.sep:SetPoint("BOTTOMRIGHT", -1, 148)
    f.best = UI.Text(f, 12, "muted")
    f.best:SetPoint("BOTTOMLEFT", 12, 124)
    f.listed = UI.Text(f, 11, "muted")
    f.listed:SetPoint("BOTTOMLEFT", 12, 106)
    f.updated = UI.Text(f, 11, "dim")
    f.updated:SetPoint("BOTTOMLEFT", 12, 89)

    f.calcTitle = UI.Text(f, 11, "muted")
    f.calcTitle:SetPoint("BOTTOMLEFT", 12, 62)
    f.calcTitle:SetText(L["Cost to buy"])
    f.calc = UI.Input(f, 70, 22, L["qty"], function() f:UpdateCalc() end)
    f.calc:SetPoint("BOTTOMRIGHT", -12, 56)
    f.calc:SetNumeric(true)
    f.calcResult = UI.Text(f, 12, "text")
    f.calcResult:SetPoint("BOTTOMLEFT", 12, 34)
    f.calcResult:SetPoint("RIGHT", -12, 0)
    f.calcAvg = UI.Text(f, 11, "dim")
    f.calcAvg:SetPoint("BOTTOMLEFT", 12, 16)
    f.calcAvg:SetPoint("RIGHT", -12, 0)

    f.empty = UI.Text(f, 12, "dim", "CENTER")
    f.empty:SetPoint("CENTER", f.rowsArea, "CENTER", 0, 0)
    f.empty:SetWidth(200)
    if f.empty.SetWordWrap then f.empty:SetWordWrap(true) end

    local function Row(i)
        local r = f.rows[i]
        if r then return r end
        r = CreateFrame("Frame", nil, f.rowsArea)
        r:SetHeight(ROW_H)
        r:EnableMouse(true)
        r.depth = UI.Tex(r, "BACKGROUND", "down", 0.12)
        r.depth:SetPoint("TOPRIGHT")
        r.depth:SetPoint("BOTTOMRIGHT")
        r.price = UI.Text(r, 12, "down", "LEFT")
        r.qty = UI.Text(r, 12, "text", "RIGHT")
        r.cum = UI.Text(r, 12, "muted", "RIGHT")
        r.hl = UI.Tex(r, "BACKGROUND", "bg2", 1, -1)
        r.hl:SetAllPoints()
        r.hl:Hide()
        r:SetScript("OnEnter", function(self)
            self.hl:Show()
            if self.cumQty then
                UI.TipText(self, string.format(L["Buy up to %s"], FT.Money(self.unit)),
                    string.format(L["%d pcs for %s (avg %s)"], self.cumQty, FT.Money(self.cumCost),
                        FT.Money(self.cumCost / math.max(1, self.cumQty))))
            end
        end)
        r:SetScript("OnLeave", function(self)
            self.hl:Hide()
            GameTooltip:Hide()
        end)
        f.rows[i] = r
        return r
    end

    function f:Layout()
        UI.LayoutColumns(cols, self.rowsArea:GetWidth() - 10)
        for i, r in ipairs(self.rows) do
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
            r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
            for _, c in ipairs(cols) do
                local cell = r[c.key]
                cell:ClearAllPoints()
                cell:SetPoint("LEFT", r, "LEFT", c._x, 0)
                cell:SetWidth(c._w)
            end
        end
    end

    function f:SetItem(itemID)
        self.itemID = itemID
        self:Refresh()
    end

    function f:Refresh()
        local book = self.itemID and FT.Hist.Book(self.itemID)
        local maxRows = math.max(1, math.floor(self.rowsArea:GetHeight() / ROW_H))
        for i = #self.rows + 1, maxRows do Row(i) end
        self:Layout()
        local levels = book and book.levels or {}
        local total = 0
        for _, lv in ipairs(levels) do total = total + lv[2] end
        local cum, cost = 0, 0
        for i, r in ipairs(self.rows) do
            local lv = levels[i]
            if lv and i <= maxRows then
                cum = cum + lv[2]
                cost = cost + lv[1] * lv[2]
                r.price:SetText(FT.Money(lv[1], "short"))
                r.qty:SetText(FT.Num(lv[2]))
                r.cum:SetText(FT.Num(cum))
                r.depth:SetWidth(math.max(1, (r:GetWidth() or 200) * (total > 0 and cum / total or 0)))
                r.unit, r.cumQty, r.cumCost = lv[1], cum, cost
                r:Show()
            else
                r.cumQty = nil
                r:Hide()
            end
        end
        if #levels == 0 then
            self.empty:SetText(self.itemID and L["No listings known yet. Search this item on the auction house or run a full scan."] or "")
            self.empty:Show()
        else
            self.empty:Hide()
        end
        if book and levels[1] then
            self.best:SetText(L["Best price"] .. ":  " .. FT.Money(levels[1][1]))
            -- partial: more auctions than the pages read (the cheapest were read): at least this many
            local qtyText = FT.Num(book.qty or total) .. (book.partial and "+" or "")
            local parts = { string.format(L["%s pcs listed"], qtyText) }
            if book.auctions and book.auctions > 0 then parts[#parts + 1] = string.format(L["%d auctions"], book.auctions) end
            if book.sellers and book.sellers > 0 then parts[#parts + 1] = string.format(L["%d sellers"], book.sellers) end
            self.listed:SetText(table.concat(parts, "  ·  "))
            self.updated:SetText(string.format(L["Updated %s"], FT.Ago(book.t)) .. "  ·  " .. FT.SourceName(book.source))
        else
            self.best:SetText("")
            self.listed:SetText("")
            self.updated:SetText("")
        end
        self:UpdateCalc()
    end

    function f:UpdateCalc()
        local qty = tonumber(self.calc:GetText())
        if not (self.itemID and qty and qty > 0) then
            self.calcResult:SetText(FT.C("dim", L["Type a quantity"]))
            self.calcAvg:SetText("")
            return
        end
        local cost, enough, avg = FT.Hist.CostToBuy(self.itemID, qty)
        if not cost then
            local p = FT.Price(self.itemID)
            if p then
                self.calcResult:SetText("~ " .. FT.Money(p * qty))
                self.calcAvg:SetText(L["by the lowest price (no listings known)"])
            else
                self.calcResult:SetText(FT.C("dim", L["No price"]))
                self.calcAvg:SetText("")
            end
            return
        end
        self.calcResult:SetText(FT.Money(cost))
        local text = string.format(L["avg %s each"], FT.Money(avg, "short"))
        if not enough then text = text .. "  " .. FT.C("down", L["not that many listed"]) end
        self.calcAvg:SetText(text)
    end

    f:SetScript("OnSizeChanged", function(self) self:Refresh() end)
    return f
end
