-- Wolf: a spare file (v0.59). Holds (v0.61): the session card - a right-click on the minimap button while a session
-- runs (one of yours, or a farming one that started by itself). What it is and how it's going in big plain numbers,
-- its best loot, and two buttons: Show on screen (the small session window, pinned or unpinned) and Stop and save.
-- Fresh prices or a newer Wolf waiting sit on top. Nothing running: the right-click is the menu (Start a session).
local _, FT = ...
local L = FT.L
local UI = FT.UI

local card
local W = 300
local PAD = 12

local function Build()
    UI.ResolveFont()
    local d = CreateFrame("Frame", "WolfOfBootyBaySessionCard", UIParent)
    d:SetFrameStrata("DIALOG")
    d:SetToplevel(true)
    d:EnableMouse(true)
    d:SetClampedToScreen(true)
    d:SetWidth(W + 20 * (tonumber(FT.S and FT.S.textSize) or 0))
    UI.Skin(d, "window", "bg1")
    d.close = UI.CloseButton(d, function() d:Hide() end, 22)
    d.close:SetPoint("TOPRIGHT", -4, -4)
    -- what's waiting (fresh prices, a newer Wolf): a line with its button
    d.alert = CreateFrame("Frame", nil, d)
    d.alert:SetPoint("TOPLEFT", PAD, -PAD)
    d.alert:SetPoint("RIGHT", d, "RIGHT", -34, 0)
    d.alert.text = UI.Text(d.alert, 11, "up")
    d.alert.text:SetPoint("LEFT", 0, 0)
    d.alert.btn = UI.Button(d.alert, "", 10, 20, "default", function() if d.alert.fn then d.alert.fn() end end)
    d.alert.btn:SetPoint("RIGHT", 0, 0)
    d.alert.text:SetPoint("RIGHT", d.alert.btn, "LEFT", -6, 0)
    -- the session
    d.kind = UI.Text(d, 10, "accent")
    d.name = UI.Text(d, 15, "text")
    d.worth = UI.Text(d, 22, "text")
    d.rate = UI.Text(d, 12, "up")
    d.time = UI.Text(d, 11, "muted")
    d.best = {}
    for i = 1, 3 do
        local r = CreateFrame("Frame", nil, d)
        r:SetHeight(UI.RowH(20))
        r.icon = UI.Icon(r, 16)
        r.icon:SetPoint("LEFT", 0, 0)
        r.val = UI.Text(r, 11, "muted", "RIGHT")
        r.val:SetPoint("RIGHT", 0, 0)
        r.name = UI.Text(r, 11, "text")
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
        r.name:SetPoint("RIGHT", r.val, "LEFT", -6, 0)
        d.best[i] = r
    end
    d.show = UI.Button(d, "", 10, 26, "default", function()
        FT.Session.SetOnScreen(not FT.Session.OnScreen())
        FT.ShowSessionCard()
    end)
    d.stop = UI.Button(d, L["Stop and save"], 10, 26, "default", function()
        d:Hide()
        FT.Session.Stop()
    end)
    d.elapsed = 0
    d:SetScript("OnUpdate", function(self, e)
        self.elapsed = self.elapsed + e
        if self.elapsed >= 1 then self.elapsed = 0; FT.ShowSessionCard(true) end
    end)
    tinsert(UISpecialFrames, "WolfOfBootyBaySessionCard")
    d:Hide()
    card = d
    return d
end

-- the card for the session running (again: refreshed in place); nil anchor keeps where it is
function FT.ShowSessionCard(refresh, anchor)
    local S = FT.Session
    local s = S.Current()
    if not s then
        if card then card:Hide() end
        return
    end
    local d = card or Build()
    if refresh and not d:IsShown() then return end
    local y = -PAD
    -- what's waiting
    local fresh, newer = FT.Alerts()
    d.alert.fn = nil
    if fresh then
        d.alert.text:SetText(L["Newer prices are waiting."])
        d.alert.btn:SetLabel(L["Load them"]); d.alert.fn = ReloadUI
    elseif newer and FT.Companion and FT.Companion.Updates() and not FT.Companion.Pending() then
        d.alert.text:SetText(string.format(L["Wolf v%s is ready."], newer))
        d.alert.btn:SetLabel(L["Reload"]); d.alert.fn = ReloadUI
    end
    d.alert:SetShown(d.alert.fn ~= nil)
    if d.alert.fn then
        d.alert.btn:FitText(14)
        d.alert:SetHeight(22)
        y = y - 30
    end
    local sum = S.Summary(s)
    d.kind:ClearAllPoints(); d.kind:SetPoint("TOPLEFT", PAD, y)
    d.kind:SetText(s.paused and (s.idle and L["PAUSED: NO LOOT FOR 5 MINUTES"] or (s.afk and L["PAUSED (AFK)"] or L["PAUSED"]))
        or (s.auto and L["FARMING, TRACKED BY ITSELF"] or L["YOUR SESSION"]))
    UI.SetTextColor(d.kind, s.paused and "muted" or "accent")
    y = y - UI.Size(10) - 4
    d.name:ClearAllPoints(); d.name:SetPoint("TOPLEFT", PAD, y); d.name:SetPoint("RIGHT", d, "RIGHT", -PAD, 0)
    UI.FitBits(d.name, S.Label(s) or "")
    y = y - UI.Size(15) - 8
    d.worth:ClearAllPoints(); d.worth:SetPoint("TOPLEFT", PAD, y)
    d.worth:SetText(FT.Money(math.floor(sum.worth), "gold"))
    d.rate:ClearAllPoints(); d.rate:SetPoint("BOTTOMLEFT", d.worth, "BOTTOMRIGHT", 10, 2)
    d.rate:SetText(sum.perHour and string.format(L["%s an hour"], FT.Money(math.floor(sum.perHour), "gold"))
        or FT.C("dim", string.format(L["an hour from %d min"], math.ceil(sum.rateIn / 60))))
    y = y - math.ceil(UI.Size(22) * 1.4) - 4
    d.time:ClearAllPoints(); d.time:SetPoint("TOPLEFT", PAD, y)
    d.time:SetText(string.format(L["%s of farming"], FT.Duration(sum.secs)) .. ((sum.money or 0) > 0 and (FT.C("dim", "  ·  ") .. string.format(L["%s of it coin"], FT.Money(sum.money, "gold"))) or ""))
    y = y - UI.Size(11) - 10
    -- the best loot
    for i, r in ipairs(d.best) do
        local it = sum.items[i]
        r:SetShown(it ~= nil and (it.value or 0) > 0)
        if r:IsShown() then
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", PAD, y)
            r:SetPoint("RIGHT", d, "RIGHT", -PAD, 0)
            r.icon:SetItem(it.id)
            UI.FitBits(r.name, FT.ItemText(it.id, 30) .. FT.C("dim", "  x" .. FT.Num(it.qty)))
            r.val:SetText(FT.Money(math.floor(it.value), "short"))
            y = y - UI.RowH(20)
        end
    end
    y = y - 8
    -- the buttons, side by side
    d.show:SetLabel(S.OnScreen(s) and L["Take off screen"] or L["Show on screen"])
    local bw = math.floor((d:GetWidth() - 2 * PAD - 8) / 2)
    d.show:SetWidth(bw); d.stop:SetWidth(bw)
    d.show:ClearAllPoints(); d.show:SetPoint("TOPLEFT", PAD, y)
    d.stop:ClearAllPoints(); d.stop:SetPoint("TOPRIGHT", -PAD, y)
    y = y - 26 - PAD
    d:SetHeight(-y)
    if anchor then
        d:ClearAllPoints()
        local x, cy = anchor:GetCenter()
        local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
        local right = x and x > sw / 2
        local top = cy and cy > sh / 2
        d:SetPoint((top and "TOP" or "BOTTOM") .. (right and "RIGHT" or "LEFT"), anchor, (top and "BOTTOM" or "TOP") .. (right and "LEFT" or "RIGHT"), 0, 0)
    end
    if not refresh then d:Show(); d:Raise() end
end

FT.On("FT_SESSION_CHANGED", function() if card and card:IsShown() then FT.ShowSessionCard(true) end end)
