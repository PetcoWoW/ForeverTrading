-- Wolf: a spare file (v0.59). Holds (v0.61): getting around like a browser, and the search box that doesn't jump.
-- Back and Forward: every page, section, Farm it mode and item you open is a step (FT.Place, UI\Main.lua); the
-- buttons sit left of the search box, their hover says where they go, and the mouse's side buttons work on the
-- window. The search box: what you type shows the items it finds right under it - icon, price, verdict - and
-- only picking one (a click, or Enter for the first) opens it; Back returns you to where you were.
local _, FT = ...
local L = FT.L
local UI = FT.UI

---------------------------------------------------------------------------
-- History
---------------------------------------------------------------------------
local MAX = 40
local steps, at = {}, 0
local restoring = false
local back, fwd

local function Key(p)
    if not p then return "" end
    return table.concat({ p.tab or "", p.group or "", p.sub or "", p.farm or "", tostring(p.item or "") }, "|")
end

local function Paint()
    if not back then return end
    back:SetUsable(at > 1)
    fwd:SetUsable(at < #steps)
end

-- where you are now, after any move: a new step (the forward ones are dropped, like a browser)
local pending = false
local function Record()
    pending = false
    if restoring then return end
    local p = FT.Place()
    if not p then return end
    if steps[at] and Key(steps[at]) == Key(p) then return end
    for i = #steps, at + 1, -1 do steps[i] = nil end
    steps[#steps + 1] = p
    while #steps > MAX do table.remove(steps, 1) end
    at = #steps
    Paint()
end
function FT.NavNote()
    if pending then return end
    pending = true
    C_Timer.After(0, Record)
end

local function Go(p)
    if not p then return end
    restoring = true
    local ok, err = pcall(function()
        if p.item then
            FT.OpenItem(p.item)
        elseif p.group then
            FT.ShowSub(p.group, p.sub)
            if p.sub == "make" then
                local want = p.farm == "mats" and "mats" or "deals"
                if FT.Tabs.signals.flipMode ~= want then FT.Tabs.signals.SetFlipMode(want) end
            elseif p.farm and FT.Tabs.signals.SetFarmMode and FT.Tabs.signals.FarmMode() ~= p.farm then FT.Tabs.signals.SetFarmMode(p.farm) end
        else
            FT.SelectTab(p.tab)
            if p.tab == "market" and FT.Tabs.market.Home then FT.Tabs.market.Home() end
        end
    end)
    restoring = false
    if not ok then geterrorhandler()(err) end
    Paint()
end

function FT.NavBack()
    if at <= 1 then return end
    at = at - 1
    Go(steps[at])
end
function FT.NavForward()
    if at >= #steps then return end
    at = at + 1
    Go(steps[at])
end
function FT.NavSteps() return steps, at end

-- every way of moving notes the place it lands on
local function After(tbl, name)
    local fn = tbl and tbl[name]
    if type(fn) ~= "function" then return end
    tbl[name] = function(...)
        local a, b, c = fn(...)
        FT.NavNote()
        return a, b, c
    end
end
After(FT, "SelectTab")
After(FT, "OpenItem")
After(FT.Tabs.market, "Select")
After(FT.Tabs.market, "Home")

local function Tip(self, label, p)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(label, 1, 1, 1)
    if p then GameTooltip:AddLine(FT.PlaceName(p), 0.87, 0.75, 0.42) end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- The search box's results
---------------------------------------------------------------------------
local drop
local ROWS = 8

local function Pick(id)
    if drop then drop:Hide() end
    local box = FT.MainRefs and FT.MainRefs.search
    if box then box:SetValue(""); box:ClearFocus() end
    if id then FT.OpenItem(id) end
end

local function BuildDrop(box)
    local d = CreateFrame("Frame", nil, box)
    d:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -2)
    d:SetWidth(330 + 20 * (tonumber(FT.S and FT.S.textSize) or 0))
    d:SetFrameStrata("DIALOG")
    UI.Skin(d, "popup", "bg2")
    d:EnableMouse(true)
    d.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, d)
        r:SetHeight(UI.RowH(26))
        r:SetPoint("TOPLEFT", 3, -3 - (i - 1) * UI.RowH(26))
        r:SetPoint("RIGHT", d, "RIGHT", -3, 0)
        r.hl = UI.Tex(r, "BACKGROUND", "hl", 1)
        r.hl:SetAllPoints()
        r.hl:Hide()
        r.icon = UI.Icon(r, 20)
        r.icon:SetPoint("LEFT", 5, 0)
        r.verdict = UI.Text(r, 10, "muted", "RIGHT")
        r.verdict:SetPoint("RIGHT", -6, 0)
        r.verdict:SetWidth(56)
        r.price = UI.Text(r, 12, "text", "RIGHT")
        r.price:SetPoint("RIGHT", r.verdict, "LEFT", -8, 0)
        r.name = UI.Text(r, 12, "text")
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
        r.name:SetPoint("RIGHT", r.price, "LEFT", -8, 0)
        r:SetScript("OnEnter", function(self) self.hl:Show() end)
        r:SetScript("OnLeave", function(self) self.hl:Hide() end)
        r:SetScript("OnClick", function(self) Pick(self.id) end)
        d.rows[i] = r
    end
    d.none = UI.Text(d, 11, "dim")
    d.none:SetPoint("TOPLEFT", 10, -10)
    d:Hide()
    drop = d
    return d
end

local function Verdict(id)
    local ok, call = pcall(function() return FT.An.Call(FT.An.Stats(id)) end)
    if not ok or not call or not call.kind then return "" end
    return FT.C(FT.SIGNAL_COLORS[call.kind] or "muted", FT.SignalText(call.kind))
end

function FT.QuickSearchTyped(box, text)
    FT.Debounce("quickSearch", 0.15, function()
        local d = drop or BuildDrop(box)
        local q = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if #q < 2 or not box:HasFocus() then d:Hide() return end
        local ids = FT.Tabs.calc and FT.Tabs.calc.Suggest and FT.Tabs.calc.Suggest(q) or {}
        d.ids = ids
        for i, r in ipairs(d.rows) do
            local id = ids[i]
            r.id = id
            r:SetShown(id ~= nil)
            if id then
                r.icon:SetItem(id)
                UI.FitBits(r.name, FT.ItemText(id, 40))
                local price = FT.Price(id)
                r.price:SetText(price and FT.Money(price, "short") or FT.C("dim", "—"))
                r.verdict:SetText(Verdict(id))
            end
        end
        d.none:SetShown(#ids == 0)
        d.none:SetText(L["No item by that name on the market yet."])
        d:SetHeight(#ids > 0 and (#ids * UI.RowH(26) + 6) or (UI.Size(11) + 20))
        d:Show()
        d:Raise()
    end)
end

function FT.QuickSearchDrop() return drop end

function FT.QuickSearchEnter(box)
    local first = drop and drop:IsShown() and drop.ids and drop.ids[1]
    if first then Pick(first) else box:ClearFocus() end
end

---------------------------------------------------------------------------
-- The buttons, once the window is made (UI\Main.lua calls this)
---------------------------------------------------------------------------
function FT.BuildNav(header, search, win)
    back = UI.Button(header, "<", 24, 24, "default", FT.NavBack)
    fwd = UI.Button(header, ">", 24, 24, "default", FT.NavForward)
    fwd:SetPoint("RIGHT", search, "LEFT", -8, 0)
    back:SetPoint("RIGHT", fwd, "LEFT", -3, 0)
    back:HookScript("OnEnter", function(self) Tip(self, L["Back"], steps[at - 1]) end)
    fwd:HookScript("OnEnter", function(self) Tip(self, L["Forward"], steps[at + 1]) end)
    back:HookScript("OnLeave", function() GameTooltip:Hide() end)
    fwd:HookScript("OnLeave", function() GameTooltip:Hide() end)
    -- the mouse's side buttons, on the window
    win:HookScript("OnMouseUp", function(_, button)
        if button == "Button4" then FT.NavBack() elseif button == "Button5" then FT.NavForward() end
    end)
    -- the results close when the box lets go (a moment later, so a click on one still lands)
    search:HookScript("OnEditFocusLost", function() C_Timer.After(0.2, function() if drop and not search:HasFocus() then drop:Hide() end end) end)
    search:HookScript("OnHide", function() if drop then drop:Hide() end end)
    Paint()
end
