-- Wolf of Booty Bay (built on ForeverTrading): order book - what is listed at each price, with the depth behind it, and what
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
    f.best:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    f.listed = UI.Text(f, 11, "muted")
    f.listed:SetPoint("BOTTOMLEFT", 12, 106)
    f.listed:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    f.updated = UI.Text(f, 11, "dim")
    f.updated:SetPoint("BOTTOMLEFT", 12, 89)
    f.updated:SetPoint("RIGHT", f, "RIGHT", -12, 0)

    -- buying: its title, then the field and the button side by side (half the width each), then what it costs -
    -- each on its own line (the panel is narrow: a title and a field on one line ran into each other)
    f.calcTitle = UI.Text(f, 11, "muted")
    f.calcTitle:SetPoint("BOTTOMLEFT", 12, 68)
    f.calcTitle:SetPoint("RIGHT", -12, 0)
    f.calcTitle:SetText(L["Cost to buy"])
    f.calcRow = CreateFrame("Frame", nil, f)
    f.calcRow:SetHeight(22)
    f.calcRow:SetPoint("BOTTOMLEFT", 12, 40)
    f.calcRow:SetPoint("BOTTOMRIGHT", -12, 40)
    f.calc = UI.Input(f.calcRow, 70, 22, L["qty"], function() f:UpdateCalc() end)
    f.calc:SetPoint("LEFT", 0, 0)
    f.calc:SetPoint("RIGHT", f.calcRow, "CENTER", -4, 0)
    f.calc:SetNumeric(true)
    -- at the auction house: buy what the box says
    f.buy = UI.Button(f.calcRow, L["Buy"], 70, 22, "primary", function() f:Buy() end)
    f.buy:SetPoint("LEFT", f.calcRow, "CENTER", 4, 0)
    f.buy:SetPoint("RIGHT", 0, 0)
    f.calcResult = UI.Text(f, 12, "text")
    f.calcResult:SetPoint("BOTTOMLEFT", 12, 22)
    f.calcResult:SetPoint("RIGHT", -12, 0)
    f.calcAvg = UI.Text(f, 11, "dim")
    f.calcAvg:SetPoint("BOTTOMLEFT", 12, 6)
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
        r.hl = UI.RoundTex(r, "BACKGROUND", "hl", 1, -1)
        r.hl:SetAllPoints()
        r.hl:Hide()
        r:SetScript("OnEnter", function(self)
            self.hl:Show()
            if self.cumQty then
                UI.TipText(self, string.format(L["Buy up to %s"], FT.Money(self.unit)),
                    string.format(L["%d pcs for %s (avg %s)"], self.cumQty, FT.Money(self.cumCost),
                        FT.Money(self.cumCost / math.max(1, self.cumQty))) .. "\n\n" .. L["Click: that many in the buy box below."])
            end
        end)
        -- a level clicked: buy everything up to its price
        r:SetScript("OnMouseUp", function(self)
            if not self.cumQty then return end
            f.calc:SetText(tostring(self.cumQty))
            f.calc:ClearFocus()
            f:UpdateCalc()
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
        -- another item: the quantity typed for the last one doesn't carry over
        if itemID ~= self.itemID then self.calc:SetText("") end
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
            -- two short lines that fit the narrow panel: how many / in how many auctions, then sellers / when
            local parts = { string.format(L["%s pcs listed"], qtyText) }
            if book.auctions and book.auctions > 0 then parts[#parts + 1] = UI.AuctionsText(self.itemID, book.auctions) end
            self.listed:SetText(table.concat(parts, "  ||  "))
            local when = string.format(L["Updated %s"], FT.Ago(book.t))
            if book.sellers and book.sellers > 0 then
                when = string.format(L["%d sellers"], book.sellers) .. "  ||  " .. when
            end
            self.updated:SetText(when)
        else
            self.best:SetText("")
            self.listed:SetText("")
            self.updated:SetText("")
        end
        self:UpdateCalc()
    end

    -- the Buy button: at the auction house, with a quantity (gear: its cheapest auction)
    function f:UpdateBuy()
        local id = self.itemID
        local qty = tonumber(self.calc:GetText())
        local commodity = id and FT.Buy.IsCommodity(id)
        local gear = commodity == false
        local can = id and FT.Buy.Possible() and commodity ~= nil and (gear or (qty and qty > 0))
        self.buy:SetUsable(can and true or false)
        if not FT.Buy.Possible() then
            self.buy:SetTip(L["Buy"], FT.House.Why(L["Talk to an auctioneer to buy."]))
        elseif commodity == nil then
            -- the game is loading the item: asked again in a moment
            self.buy:SetTip(L["Buy"], L["The item is still loading: try again in a moment."])
            if id and not self.recheck then
                self.recheck = true
                C_Timer.After(1, function()
                    self.recheck = false
                    if self.itemID == id then self:UpdateBuy() end
                end)
            end
        elseif gear then
            self.buy:SetTip(L["Buy"], L["Gear is bought one auction at a time: its cheapest with a buyout. You confirm its price first."])
        elseif not (qty and qty > 0) then
            self.buy:SetTip(L["Buy"], L["Type a quantity or click a price in the order book."])
        else
            self.buy:SetTip(L["Buy"], L["The cheapest that many: the server tells their exact price first, you confirm."])
        end
    end

    function f:Buy()
        local id = self.itemID
        if not id then return end
        local qty = tonumber(self.calc:GetText())
        local commodity = FT.Buy.IsCommodity(id)
        if commodity == nil then return end
        if not commodity then qty = 1 end
        if not (qty and qty > 0) then return end
        local cost, _, avg = FT.Hist.CostToBuy(id, qty)
        FT.Buy.Start(id, qty, avg or (cost and cost / qty) or FT.Price(id))
    end

    function f:UpdateCalc()
        self:UpdateBuy()
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

    -- the house its numbers are of: an item window's own (nil: the one on)
    for _, name in ipairs({ "SetItem", "Refresh", "UpdateBuy", "UpdateCalc", "Buy" }) do
        local fn = f[name]
        if fn then f[name] = function(self, ...) return FT.House.With(self.house, fn, self, ...) end end
    end
    f:HookScript("OnSizeChanged", function(self) self:Refresh() end)
    return f
end
