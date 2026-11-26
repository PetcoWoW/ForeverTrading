-- Wolf of Booty Bay: the Snipe panel - the auction house tab. Right after a scan: what's listed under its snipe
-- price (with how sure, and a Buy button: the server's price, your click), and the items worth searching again
-- and again. Re-check searches the hit list without a new full scan.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local P = {}
FT.SnipePanel = P

local panel
local MAX_RECHECK = 30

local function Chip(parent)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(58, 16)
    c.bg = UI.RoundTex(c, "BACKGROUND", "muted", 0.2)
    c.bg:SetAllPoints()
    c.text = UI.Text(c, 10, "muted", "CENTER")
    c.text:SetPoint("CENTER")
    function c:Set(conf)
        local col = FT.Snipe.CONF_COLORS[conf] or "muted"
        UI.SetTexColor(self.bg, col, 0.22)
        UI.SetTextColor(self.text, col)
        self.text:SetText(L[FT.Snipe.CONF_TEXT[conf] or "?"])
    end
    return c
end

-- a row: icon, name over a line of numbers, on the right a chip and a button
local function RowSetup(row)
    row.icon = UI.Icon(row, 26)
    row.icon:SetPoint("LEFT", 8, 0)
    row.name = UI.Text(row, 12, "text")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 1)
    row.name:SetPoint("RIGHT", row, "RIGHT", -140, 0)
    row.line = UI.Text(row, 11, "dim")
    row.line:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, -1)
    row.line:SetPoint("RIGHT", row, "RIGHT", -140, 0)
    row.chip = Chip(row)
    row.chip:SetPoint("RIGHT", row, "RIGHT", -64, 0)
    row.buy = UI.Button(row, L["Buy"], 50, 20, "primary", function() end)
    row.buy:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.sep = UI.HLine(row, "line", 0.5)
    row.sep:SetPoint("BOTTOMLEFT", 8, 0)
    row.sep:SetPoint("BOTTOMRIGHT", -8, 0)
end

local function Box(parent, title)
    local b = UI.Panel(parent, "bg1", "line")
    b.title = UI.Text(b, 13, "text")
    b.title:SetPoint("TOPLEFT", 10, -8)
    b.title:SetText(title)
    b.count = UI.Text(b, 11, "dim", "RIGHT")
    b.count:SetPoint("TOPRIGHT", -10, -9)
    return b
end

local function Build(parent)
    local f = CreateFrame("Frame", "WolfOfBootyBaySnipe", parent)
    UI.ResolveFont()
    -- over the auction house's own page: dark and solid (the classic look: with the tooltip's gold edge)
    if UI.Classic() then UI.Skin(f, "popup", "bg0", 0.97) else UI.Fill(f, "bg0", 0.97) end
    f.head = UI.Text(f, 15, "accent")
    f.head:SetPoint("TOPLEFT", 12, -10)
    f.head:SetText(L["Snipe"])
    f.sub = UI.Text(f, 11, "dim")
    f.sub:SetPoint("LEFT", f.head, "RIGHT", 12, -1)
    f.sub:SetPoint("RIGHT", f, "RIGHT", -330, 0)
    f.open = UI.Button(f, L["Open Wolf of Booty Bay"], 10, 22, "default", function() FT.Show("market") end)
    f.open:FitText(20)
    f.open:SetPoint("TOPRIGHT", -10, -8)
    f.toAtr = UI.Button(f, L["To Auctionator"], 10, 22, "default", function()
        local ids = {}
        for _, x in ipairs((FT.Snipe.Now())) do ids[#ids + 1] = x.id end
        for _, x in ipairs(FT.Snipe.Often()) do ids[#ids + 1] = x.id end
        FT.ToAuctionator(L["Wolf: Snipe"], ids)
    end)
    f.toAtr:FitText(20)
    f.toAtr:SetPoint("RIGHT", f.open, "LEFT", -6, 0)
    f.toAtr:SetTip(L["To Auctionator"], L["Both lists as an Auctionator shopping list."])
    f.recheck = UI.Button(f, L["Re-check"], 10, 22, "primary", function() P.Recheck() end)
    f.recheck:FitText(20)
    f.recheck:SetPoint("RIGHT", f.toAtr, "LEFT", -6, 0)
    f.recheck:SetTip(L["Re-check"], L["Searches just the items in both lists again (no full scan): what's cheap right now."])

    f.now = Box(f, L["Underpriced now"])
    f.often = Box(f, L["Often underpriced"])
    f.now.list = UI.List(f.now, {
        rowHeight = 40, setup = RowSetup,
        update = function(row, x)
            row.icon:SetItem(x.id)
            row.name:SetText(FT.ItemText(x.id, 40))
            row.line:SetText(FT.C("up", FT.Money(x.price, "short")) .. FT.C("dim", "  ·  " .. L["normally"] .. " ")
                .. FT.Money(math.floor(x.fair), "short") .. FT.C("dim", "  ·  ") .. FT.Pct(x.off)
                .. (x.listed and FT.C("dim", "  ·  " .. string.format(L["%s listed"], FT.Num(x.listed))) or ""))
            row.chip:Set(x.conf)
            row.buy:Show()
            row.buy:SetLabel((x.qty or 1) > 1 and string.format(L["Buy %s"], FT.Num(x.qty)) or L["Buy"])
            row.buy:FitText(14)
            row.buy.onClick = function() FT.Buy.Start(x.id, x.qty or 1, x.price) end
        end,
        onClick = function(x) if not UI.ItemClick(x.id) then FT.OpenItem(x.id) end end,
        onEnter = function(row, x)
            UI.TipItem(row, x.id)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(string.format(L["Buy at or under %s (its real price %s, less %d%%)."], FT.Money(x.under), FT.Money(math.floor(x.fair)),
                FT.S.dealBelow or 30), 0.85, 0.87, 0.9, true)
            GameTooltip:AddLine(L[FT.Snipe.CONF_TEXT[x.conf]] .. ": " .. x.why, 0.85, 0.87, 0.9, true)
            GameTooltip:AddLine(string.format(L["Sold again at its real price: about %s each after the cut."], FT.Money(math.floor(x.gain))), 0.4, 0.85, 0.5, true)
            GameTooltip:AddLine(L["Buy: the server's exact price first, then your OK. Click: the item's page."], 0.6, 0.64, 0.7, true)
            GameTooltip:Show()
        end,
    })
    f.often.list = UI.List(f.often, {
        rowHeight = 40, setup = RowSetup,
        update = function(row, x)
            row.icon:SetItem(x.id)
            row.name:SetText(FT.ItemText(x.id, 30))
            row.line:SetText(x.under and (L["under"] .. " " .. FT.Money(x.under, "short") .. FT.C("dim", "  ·  "
                .. string.format(L["came back %d/%d"], x.ok, x.n))) or string.format(L["came back %d/%d"], x.ok, x.n))
            row.chip:Set(x.hit and "safe" or "good")
            row.chip.text:SetText(x.hit and L["CHEAP NOW"] or (x.price and FT.Money(x.price, "short") or "—"))
            row.buy:SetShown(x.hit and true or false)
            row.buy:SetLabel(L["Buy"])
            row.buy:FitText(14)
            row.buy.onClick = function() FT.Buy.Start(x.id, 1, x.price) end
        end,
        onClick = function(x) if not UI.ItemClick(x.id) then FT.OpenItem(x.id) end end,
        onEnter = function(row, x)
            UI.TipItem(row, x.id)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(string.format(L["Dipped 30%%+ under its usual price %d times; came back within 3 days %d times. Worth searching often."], x.n, x.ok), 0.85, 0.87, 0.9, true)
            GameTooltip:Show()
        end,
    })
    f.now.list:SetEmptyText(L["Scan first (Auctionator's Full Scan or ours): what's listed under its price shows here."])
    f.often.list:SetEmptyText(L["Fills after a day: the items whose deep dips came back most times."])

    UI.OnSize(f, function(self, w, h)
        local lw = math.floor((w - 30) * 0.58)
        self.now:ClearAllPoints()
        self.now:SetPoint("TOPLEFT", 10, -40)
        self.now:SetPoint("BOTTOMLEFT", 10, 10)
        self.now:SetWidth(lw)
        self.often:ClearAllPoints()
        self.often:SetPoint("TOPLEFT", self.now, "TOPRIGHT", 10, 0)
        self.often:SetPoint("BOTTOMRIGHT", -10, 10)
    end)
    for _, b in ipairs({ f.now, f.often }) do
        b.list:SetPoint("TOPLEFT", 1, -30)
        b.list:SetPoint("BOTTOMRIGHT", -1, 4)
    end
    f:SetScript("OnShow", function() P.Refresh() end)
    return f
end

-- the panel inside the auction house (parent: the tab's frame), or beside it
function P.Get(parent)
    if not panel then panel = Build(parent or UIParent) end
    return panel
end

function P.Refresh()
    if not (panel and panel:IsShown()) then return end
    local list, at, busy = FT.Snipe.Now()
    local scan = FT.ScanTime and FT.ScanTime()
    panel.sub:SetText(busy and L["Looking..."] or (scan and string.format(L["From your scan %s: buy what's under its price, the surest first."], FT.Ago(scan))
        or L["Scan the auction house first."]))
    panel.now.list:SetItems(list, true)
    panel.now.count:SetText(#list > 0 and tostring(#list) or "")
    local often = FT.Snipe.Often()
    panel.often.list:SetItems(often, true)
    local hits = 0
    for _, x in ipairs(often) do if x.hit then hits = hits + 1 end end
    panel.often.count:SetText(hits > 0 and string.format(L["%d cheap now"], hits) or "")
end

-- both lists searched again, no full scan
function P.Recheck()
    if not FT.ahOpen then
        FT.Print(FT.House.Why(L["Talk to an auctioneer to check the order books."]))
        return
    end
    local ids, seen = {}, {}
    for _, x in ipairs((FT.Snipe.Now())) do if not seen[x.id] then seen[x.id] = true; ids[#ids + 1] = x.id end end
    for _, x in ipairs(FT.Snipe.Often()) do if not seen[x.id] then seen[x.id] = true; ids[#ids + 1] = x.id end end
    while #ids > MAX_RECHECK do table.remove(ids) end
    if #ids == 0 then return end
    FT.Scanner.StartMine(false, ids)
end

-- the panel if it was made (nil: never opened)
function P.Panel() return panel end

-- how many are underpriced now (the tab's label)
function P.Count()
    return #(FT.Snipe.Now())
end

FT.On("FT_SNIPE_READY", function() P.Refresh() end)
FT.On("FT_SCAN_DONE", function(kind) if kind == "mine" then FT.Snipe.Build() end end)
FT.On("FT_LEARNED", function() P.Refresh() end)
