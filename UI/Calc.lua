-- Wolf: the buy/sell calculator window (v0.50) - from the item page's Market section. How many, and (selling) at
-- what price; the answer under it as you type. FT.Calc does the sums.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local win
local W, H = 500, 236

local function Window()
    if win then return win end
    UI.ResolveFont()
    local d = CreateFrame("Frame", "WolfOfBootyBayCalc", UIParent)
    d:SetSize(W, H)
    d:SetPoint("CENTER", 0, 60)
    d:SetFrameStrata("DIALOG")
    d:SetToplevel(true)
    d:EnableMouse(true)
    d:SetMovable(true)
    d:SetClampedToScreen(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)
    UI.Skin(d, "window", "bg1")
    if d.bg then d.bg:SetAlpha(0.95) end
    table.insert(UISpecialFrames, "WolfOfBootyBayCalc")
    d.icon = UI.Icon(d, 26)
    d.icon:SetPoint("TOPLEFT", 14, -12)
    d.close = UI.Button(d, L["Close"], 10, 22, "default", function() d:Hide() end)
    d.close:FitText(24)
    d.close:SetPoint("TOPRIGHT", -12, -12)
    d.title = UI.Text(d, 14, "text")
    d.title:SetPoint("LEFT", d.icon, "RIGHT", 10, 0)
    d.title:SetPoint("RIGHT", d.close, "LEFT", -10, 0)
    if d.title.SetWordWrap then d.title:SetWordWrap(false) end

    d.mode = "buy"
    d.seg = UI.Segmented(d, { { "buy", L["Buying"] }, { "sell", L["Selling"] } }, function(v)
        d.mode = v
        FT.CalcUpdate()
    end, 22)
    d.seg:SetPoint("TOPLEFT", 14, -48)
    d.seg:SetValue("buy")

    d.qtyLabel = UI.Text(d, 11, "muted")
    d.qtyLabel:SetPoint("LEFT", d.seg, "RIGHT", 14, 0)
    d.qtyLabel:SetText(L["How many"])
    d.qty = UI.Input(d, 64, 22, "1", function() FT.CalcUpdate() end, function() FT.CalcUpdate() end)
    d.qty:SetPoint("LEFT", d.qtyLabel, "RIGHT", 6, 0)
    if d.qty.SetNumeric then d.qty:SetNumeric(true) end
    d.stack = UI.Button(d, L["A stack"], 10, 20, "default", function()
        local _, _, _, _, _, _, _, stack = FT.GetItemInfo and FT.GetItemInfo(d.itemID)
        d.qty:SetValue(tostring(tonumber(stack) and stack > 1 and stack or 20))
        FT.CalcUpdate()
    end)
    d.stack:FitText(14)
    d.stack:SetPoint("LEFT", d.qty, "RIGHT", 6, 0)
    d.priceLabel = UI.Text(d, 11, "muted")
    d.priceLabel:SetPoint("LEFT", d.stack, "RIGHT", 14, 0)
    d.priceLabel:SetText(L["Each"])
    d.price = UI.Input(d, 96, 22, L["under the cheapest"], function() FT.CalcUpdate() end, function() FT.CalcUpdate() end)
    d.price:SetPoint("LEFT", d.priceLabel, "RIGHT", 6, 0)
    d.price:SetPoint("RIGHT", d, "RIGHT", -14, 0)

    d.lines = {}
    for i = 1, 5 do
        local t = UI.Text(d, i == 1 and 13 or 11, i == 1 and "text" or "muted")
        t:SetPoint("TOPLEFT", 16, -86 - (i == 1 and 0 or (8 + (i - 1) * UI.RowH(20))))
        t:SetPoint("RIGHT", d, "RIGHT", -16, 0)
        if t.SetWordWrap then t:SetWordWrap(false) end
        d.lines[i] = t
    end
    d.foot = UI.Text(d, 10, "dim")
    d.foot:SetPoint("BOTTOMLEFT", 16, 12)
    d.foot:SetPoint("RIGHT", d, "RIGHT", -16, 0)
    if d.foot.SetWordWrap then d.foot:SetWordWrap(false) end
    win = d
    return d
end

function FT.CalcUpdate()
    local d = win
    if not (d and d.itemID) then return end
    local qty = tonumber(d.qty:GetText()) or 1
    local selling = d.mode == "sell"
    d.priceLabel:SetShown(selling)
    d.price:SetShown(selling)
    local lines
    if selling then
        lines = FT.Calc.SellLines(FT.Calc.Sell(d.itemID, qty, FT.Calc.ParseMoney(d.price:GetText()), 24))
        d.foot:SetText(L["Price: gold (12.5) or 12g 50s. Empty: a copper under the cheapest. For a 24 hour posting."])
    else
        lines = FT.Calc.BuyLines(FT.Calc.Buy(d.itemID, qty))
        d.foot:SetText(L["Walks up the listings from your last scan: the cheapest first."])
    end
    for i, t in ipairs(d.lines) do
        t.fitText = nil
        UI.FitBits(t, lines[i] or "")
    end
end

-- open it for an item (mode "buy" / "sell"; nil: as it was)
function FT.ShowCalc(itemID, mode)
    if not itemID then return end
    local d = Window()
    if d.itemID ~= itemID then
        d.qty:SetValue("")
        d.price:SetValue("")
    end
    d.itemID = itemID
    if mode then d.mode = mode; d.seg:SetValue(mode) end
    d.icon:SetItem(itemID)
    d.title:SetText(L["Buy or sell"] .. ": " .. FT.ItemText(itemID, 40))
    d:Show()
    d:Raise()
    FT.CalcUpdate()
end

-- new prices while it's open: the sums follow
FT.On("FT_SCAN_DONE", function() if win and win:IsShown() then FT.CalcUpdate() end end)
FT.On("FT_LIVE_UPDATED", function() if win and win:IsShown() then FT.CalcUpdate() end end)
