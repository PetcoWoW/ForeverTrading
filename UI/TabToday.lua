-- Wolf: Today, the first page (v0.42). What everything you own is worth and what the last price update did to it;
-- then two rows on the same three columns: Your top 3, and under them In your bags, Going down today and Going up
-- today (each scrolls). Tried first in Wolf Lab.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local T = {}
FT.Tabs.today = T

local PAD, GAP = 12, 10
local built

---------------------------------------------------------------------------
-- Your top 3: the wolf's moves for you (FT.Eye); short of three, today's market fills in (a flip, the best thing to
-- farm, a craft, a disenchant, a vendor deal). Also what the Market page's old overview showed.
---------------------------------------------------------------------------
function FT.TopMoves(n)
    n = n or 3
    local cards, shown = {}, {}
    local okEye, moves = pcall(FT.Eye.Moves, n)
    if okEye then
        for _, m in ipairs(moves or {}) do
            cards[#cards + 1] = { id = m.id, kind = m.kind, label = m.label, gold = m.value or "", what = m.text, tip = m.why }
            shown[m.id] = true
        end
    end
    local personal = #cards
    local best = {}
    for _, d in ipairs(FT.Deals.List() or {}) do
        if not best[d.kind] or d.profit > best[d.kind].profit then best[d.kind] = d end
    end
    local flip = best.RESELL
    if #cards < n and flip and not shown[flip.id] then
        cards[#cards + 1] = { id = flip.id, kind = "RESELL", label = "FLIP IT", gold = "+" .. FT.Money(math.floor(flip.profit), "gold"),
            what = string.format(L["%s: under its usual price, sells every day"], FT.ItemText(flip.id, 24)) }
        shown[flip.id] = true
    end
    local farm = FT.Tabs.signals and FT.Tabs.signals.FarmRows and FT.Tabs.signals.FarmRows()
    local f1 = farm and farm[1]
    if #cards < n and f1 and not shown[f1.id] then
        cards[#cards + 1] = { id = f1.id, kind = "FARM", label = "FARM IT", gold = FT.Money(f1.price or 0, "short") .. FT.C("dim", " " .. L["each"]),
            what = string.format(L["%s: sells ~%s a day"], FT.ItemText(f1.id, 24), FT.Num(math.floor((f1.perDay or 0) + 0.5))),
            tip = string.format(L["One farmer selling a share of each day's sales makes about %s a day from it."], FT.Money(math.floor(f1.yours or 0), "gold")) }
        shown[f1.id] = true
    end
    if #cards < n then
        local crafts = FT.Craft.ProfitCrafts and FT.Craft.ProfitCrafts()
        local c = crafts and crafts[1]
        if c and not shown[c.id] then
            cards[#cards + 1] = { id = c.id, kind = "CRAFT", label = c.mode == "de" and "CRAFT + DE" or "CRAFT IT",
                gold = "+" .. FT.Money(math.floor(c.profit), "gold"), what = string.format(L["%s: %s"], FT.ItemText(c.id, 24), L[c.recipe.prof or "?"]) }
            shown[c.id] = true
        end
    end
    if #cards < n then
        local de = FT.Enchant and FT.Enchant.Deals()
        local d = de and de[1]
        if d and not shown[d.id] then
            cards[#cards + 1] = { id = d.id, kind = "DE", label = "DE IT", gold = "+" .. FT.Money(math.floor(d.profit), "gold"),
                what = string.format(L["%s: buy it, disenchant it"], FT.ItemText(d.id, 24)) }
            shown[d.id] = true
        end
    end
    if #cards < n and best.VENDOR and not shown[best.VENDOR.id] then
        cards[#cards + 1] = { id = best.VENDOR.id, kind = "VENDOR", label = "VENDOR IT", gold = "+" .. FT.Money(math.floor(best.VENDOR.profit), "gold"),
            what = string.format(L["%s: a vendor pays more than it costs"], FT.ItemText(best.VENDOR.id, 24)) }
    end
    return cards, personal > 0
end

local function Box(parent, title)
    local b = UI.Panel(parent, "bg1", "line")
    b.title = UI.Text(b, 13, "muted")
    b.title:SetPoint("TOPLEFT", 12, -10)
    b.title:SetText(title)
    return b
end

-- a scrolling list of items: name, price, today's move (or, for your bags, the verdict and worth)
local function ItemList(box, bags)
    local list = UI.List(box, {
        rowHeight = UI.RowH(bags and 28 or 24),
        setup = function(row)
            row.right = UI.Text(row, 13, "text", "RIGHT")
            row.right:SetPoint("RIGHT", -4, 0)
            row.right:SetWidth(UI.RowH(bags and 72 or 52) + 4 * (tonumber(FT.S.textSize) or 0))
            row.mid = UI.Text(row, 12, "muted", "RIGHT")
            row.mid:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
            row.mid:SetWidth(UI.RowH(70) + 4 * (tonumber(FT.S.textSize) or 0))
            if bags then
                row.badge = UI.Badge(row, 60, 18)
                row.badge:SetPoint("LEFT", 4, 0)
                row.mid:Hide()
            end
            row.name = UI.Text(row, 13, "text")
            row.name:SetPoint("LEFT", bags and row.badge or row, bags and "RIGHT" or "LEFT", bags and 8 or 6, 0)
            row.name:SetPoint("RIGHT", bags and row.right or row.mid, "LEFT", -6, 0)
        end,
        update = function(row, x)
            if bags then
                row.badge:Set(x.signal or "NODATA", nil, x.strength)
                UI.FitSize(row.name, FT.ItemText(x.id) .. FT.C("dim", " ×" .. FT.Num(x.qty)), 13, 3)
                row.right:SetText(FT.Money(x.value, "gold"))
            else
                UI.FitSize(row.name, FT.ItemText(x.id), 13, 3)
                row.mid:SetText(FT.Money(x.price, "short"))
                row.right:SetText(FT.C((x.ch1 or 0) >= 0 and "up" or "down", FT.An.Pc(x.ch1 or 0)))
            end
        end,
        onClick = function(x) if not UI.ItemClick(x.id) then FT.OpenItem(x.id) end end,
        onEnter = function(row, x)
            UI.TipItem(row, x.id)
            if x.reason then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(x.reason, 0.85, 0.87, 0.9, true)
                GameTooltip:Show()
            end
        end,
    })
    list:SetPoint("TOPLEFT", 6, -34)
    list:SetPoint("BOTTOMRIGHT", -4, 6)
    return list
end


---------------------------------------------------------------------------
-- Coming up (v0.50): the next seven days, each with its events (the Darkmoon Faire, a battleground's holiday week,
-- the raids, a holiday); click a day for what it pulls on. Under the days: next week's calls, how sure Wolf is.
---------------------------------------------------------------------------
local DAY = 86400
local function DayStart(t)
    local d = date("*t", t)
    d.hour, d.min, d.sec = 0, 0, 0
    return time(d)
end

-- (v0.51) where an event's tag leads: a battleground week to PvP, the raids to Raids; the Faire and the holidays
-- open their day here (what they pull on)
local function Jump(c, d)
    local e = d.events and d.events[1]
    if not e then return end
    if e.kind == "bg" then return FT.ShowSub("make", "pvp") end
    if e.kind == "raid" then return FT.ShowSub("make", "raid") end
    c.weeks = 1
    c.from = d.t
    c.picked = d.t
    T.FillComing()
end

local function DayCell(c, parent)
    local d = CreateFrame("Button", nil, parent)
    d.bg = d:CreateTexture(nil, "BACKGROUND")
    d.bg:SetAllPoints()
    d.bg:SetColorTexture(1, 1, 1, 0.04)
    d.day = UI.Text(d, 11, "dim")
    d.day:SetPoint("TOPLEFT", 6, -4)
    d.num = UI.Text(d, 13, "text")
    d.num:SetPoint("TOPRIGHT", -6, -3)
    d.ev = UI.Text(d, 10, "accent")
    d.ev:SetPoint("TOPLEFT", 6, -22)
    d.ev:SetPoint("BOTTOMRIGHT", -4, 2)
    d.ev:SetJustifyV("TOP")
    if d.ev.SetWordWrap then d.ev:SetWordWrap(true) end
    if d.ev.SetMaxLines then d.ev:SetMaxLines(2) end
    -- the tag: a link to its section
    d.evBtn = CreateFrame("Button", nil, d)
    d.evBtn:SetAllPoints(d.ev)
    d.evBtn:SetScript("OnClick", function() Jump(c, d) end)
    d.evBtn:SetScript("OnEnter", function() d:GetScript("OnEnter")(d) end)
    d.evBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    d:SetScript("OnClick", function(self)
        if c.weeks > 1 then return Jump(c, self) end
        if c.picked == self.t then c.picked = nil else c.picked = self.t end
        T.FillComing()
    end)
    d:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(date("%A %b %d", self.t), 1, 0.82, 0)
        for _, e in ipairs(self.events or {}) do GameTooltip:AddLine(e.name .. (e.where and (" (" .. e.where .. ")") or ""), 0.85, 0.87, 0.9) end
        if not self.events or #self.events == 0 then GameTooltip:AddLine(L["Nothing on the calendar"], 0.6, 0.6, 0.6) end
        local e = self.events and self.events[1]
        if e and (e.kind == "bg" or e.kind == "raid") then
            GameTooltip:AddLine(e.kind == "bg" and L["Click the event: PvP"] or L["Click the event: Raids"], 0.58, 0.55, 0.5)
        end
        if c.weeks == 1 then GameTooltip:AddLine(L["Click the day: what it pulls on"], 0.58, 0.55, 0.5) end
        GameTooltip:Show()
    end)
    d:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return d
end

local function BuildComing(parent)
    local c = UI.Panel(parent, "bg1", "line")
    c.weeks = 1
    c.title = UI.Text(c, 13, "muted")
    c.title:SetPoint("TOPLEFT", 12, -10)
    c.title:SetText(L["Coming up"])
    -- (v0.51) "All of it": four weeks right here; again, back to this week
    c.all = UI.Button(c, L["All of it"], 10, 18, "default", function()
        c.weeks = (c.weeks == 1) and 4 or 1
        c.from, c.picked = nil, nil
        T.FillComing()
    end)
    c.all:FitText(16)
    c.all:SetPoint("TOPRIGHT", -8, -6)
    c.hint = UI.Text(c, 11, "dim")
    c.hint:SetPoint("LEFT", c.title, "RIGHT", 10, 0)
    c.hint:SetPoint("RIGHT", c.all, "LEFT", -8, 0)
    if c.hint.SetWordWrap then c.hint:SetWordWrap(false) end
    c.days = {}
    local strip = CreateFrame("Frame", nil, c)
    strip:SetPoint("TOPLEFT", 8, -32)
    strip:SetPoint("RIGHT", -8, 0)
    strip:SetHeight(UI.RowH(58))
    c.strip = strip
    for i = 1, 28 do c.days[i] = DayCell(c, strip) end
    function c:LayDays()
        local w, h = strip:GetWidth() or 0, strip:GetHeight() or 0
        local rows = self.weeks
        local cw = (w - 6 * 4) / 7
        local ch = (h - (rows - 1) * 4) / rows
        for i, d in ipairs(self.days) do
            local on = i <= rows * 7
            d:SetShown(on)
            if on then
                local r, k = math.floor((i - 1) / 7), (i - 1) % 7
                d:ClearAllPoints()
                d:SetPoint("TOPLEFT", strip, "TOPLEFT", k * (cw + 4), -r * (ch + 4))
                d:SetSize(cw, ch)
                -- small cells: the day and one tag
                if d.ev.SetMaxLines then d.ev:SetMaxLines(rows > 1 and 1 or 2) end
                d.ev:ClearAllPoints()
                d.ev:SetPoint("TOPLEFT", 6, rows > 1 and -18 or -22)
                d.ev:SetPoint("BOTTOMRIGHT", -4, 2)
            end
        end
    end
    UI.OnSize(strip, function() c:LayDays() end)
    c.list = UI.List(c, {
        rowHeight = UI.RowH(24),
        setup = function(row)
            row.right = UI.Text(row, 12, "text", "RIGHT")
            row.right:SetPoint("RIGHT", -4, 0)
            row.right:SetWidth(UI.RowH(96) + 4 * (tonumber(FT.S.textSize) or 0))
            row.name = UI.Text(row, 12, "text")
            row.name:SetPoint("LEFT", 6, 0)
            row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
            if row.name.SetWordWrap then row.name:SetWordWrap(false) end
        end,
        update = function(row, x)
            local c2 = x.call
            if not c2 then
                UI.FitBits(row.name, FT.ItemText(x.id))
                row.right:SetText(FT.C("dim", L["no call yet"]))
                return
            end
            local mv = (c2.move >= 0 and FT.C("up", "+" .. FT.An.Pc(c2.move)) or FT.C("down", FT.An.Pc(c2.move)))
            UI.FitBits(row.name, FT.ItemText(x.id) .. FT.C("dim", "  ·  ") .. mv .. FT.C("dim", "  ·  " .. (c2.why or "")))
            row.right:SetText(FT.Ahead.SureText(c2.sure))
        end,
        onClick = function(x) if not UI.ItemClick(x.id) then FT.OpenItem(x.id) end end,
        onEnter = function(row, x)
            UI.TipItem(row, x.id)
            if x.call then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(string.format(L["How sure: %d%% (right %d of %d weeks on its last 30 days)"], x.call.sure, x.call.hits, x.call.weeks), 0.85, 0.87, 0.9, true)
            end
            GameTooltip:Show()
        end,
    })
    c.list:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", -2, -6)
    c.list:SetPoint("BOTTOMRIGHT", -4, 6)
    c.list:SetEmptyText(L["Working out next week's calls..."])
    return c
end

function T.FillComing()
    local c = T.coming
    if not c then return end
    local now = time()
    local four = c.weeks > 1
    -- four weeks: the days fill the card; this week: seven days and their list under them
    c.strip:SetHeight(four and math.max(UI.RowH(58), (c:GetHeight() or 196) - 40) or UI.RowH(58))
    c.list:SetShown(not four)
    c:LayDays()
    c.all:SetLabel(four and L["This week"] or L["All of it"])
    c.all:FitText(16)
    local first = DayStart(c.from or now)
    local events = FT.Ahead.Events(c.weeks * 7 + 1, first)
    for i, d in ipairs(c.days) do
        if i > c.weeks * 7 then break end
        local t = DayStart(first + (i - 1) * DAY + 3600) -- (an hour in: a clock change doesn't slip a day)
        d.t = t
        d.day:SetText((t == DayStart(now)) and L["Today"] or date(four and "%b" or "%a", t))
        d.num:SetText(date("%d", t))
        d.events = {}
        local tags = {}
        for _, e in ipairs(events) do
            if e.t < t + DAY and e.ends > t then
                d.events[#d.events + 1] = e
                if #tags < 2 then tags[#tags + 1] = e.short end
            end
        end
        d.ev:SetText(table.concat(tags, "\n"))
        d.evBtn:SetShown(#d.events > 0)
        d.bg:SetColorTexture(1, 1, 1, (c.picked == t) and 0.14 or (#d.events > 0 and 0.07 or 0.03))
    end
    if four then
        c.hint:SetText(L["four weeks · click an event for its page"])
        return
    end
    -- the list: the picked day's event items, else next week's best farms
    local rows = {}
    if c.picked then
        local seen = {}
        for _, d in ipairs(c.days) do
            if d.t == c.picked then
                for _, e in ipairs(d.events) do
                    for _, id in ipairs(FT.Ahead.EventItems(e.kind)) do
                        if not seen[id] then
                            seen[id] = true
                            local call = FT.Ahead.Call(id)
                            if not call or call.sure >= 40 then rows[#rows + 1] = { id = id, call = call } end
                        end
                    end
                end
            end
        end
        c.hint:SetText(date("%a %b %d", c.picked) .. FT.C("dim", "  ·  " .. L["what it pulls on"]))
        c.list:SetEmptyText(L["Nothing on the calendar that day."])
    else
        local l = FT.Ahead.Lists(function() if T.coming and T.coming:IsVisible() then T.FillComing() end end)
        for _, r in ipairs(l and l.farms or {}) do rows[#rows + 1] = r end
        c.hint:SetText(L["best farms next week · click a day for its events"])
        c.list:SetEmptyText(l and L["No call sure enough yet: new prices come every hour."] or L["Working out next week's calls..."])
    end
    c.list:SetItems(rows)
end

---------------------------------------------------------------------------
-- Your best moves (v0.50): one card, it scrolls - your best asset first, then the wolf's moves for you and today's
-- market (a flip, a farm, a craft, a disenchant, a vendor deal)
---------------------------------------------------------------------------
local function BuildMoves(parent)
    local c = UI.Panel(parent, "bg1", "line")
    c:EnableMouse(true)
    c.title = UI.Text(c, 13, "muted")
    c.title:SetPoint("TOPLEFT", 12, -10)
    c.title:SetText(L["Your best moves"])
    c.list = UI.List(c, {
        rowHeight = UI.RowH(62),
        setup = function(row)
            row.badge = UI.Badge(row, 64 + 6 * (tonumber(FT.S.textSize) or 0), 18)
            row.badge:SetPoint("TOPLEFT", 4, -4)
            row.gold = UI.Text(row, 13, "text", "RIGHT")
            row.gold:SetPoint("TOPRIGHT", -4, -4)
            row.gold:SetPoint("LEFT", row.badge, "RIGHT", 6, 0)
            row.what = UI.Text(row, 12, "muted")
            row.what:SetPoint("TOPLEFT", row.badge, "BOTTOMLEFT", 2, -4)
            row.what:SetPoint("RIGHT", -4, 0)
            row.what:SetPoint("BOTTOM", row, "BOTTOM", 0, 3)
            row.what:SetJustifyV("TOP")
            if row.what.SetWordWrap then row.what:SetWordWrap(true) end
            if row.what.SetMaxLines then row.what:SetMaxLines(2) end
        end,
        update = function(row, m)
            row.badge:Set(m.kind, m.label)
            row.gold:SetText(m.gold or "")
            row.what:SetFont(UI.FONT, UI.Size(11), "")
            row.what:SetText(m.what or FT.ItemText(m.id))
        end,
        onClick = function(m) if m.id and not UI.ItemClick(m.id) then FT.OpenItem(m.id) end end,
        onEnter = function(row, m)
            if not m.id then return end
            UI.TipItem(row, m.id)
            if m.tip then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(m.tip, 0.85, 0.87, 0.9, true)
            end
            GameTooltip:AddLine(L["Click: its page"], 0.58, 0.55, 0.5)
            GameTooltip:Show()
        end,
    })
    c.list:SetPoint("TOPLEFT", 6, -32)
    c.list:SetPoint("BOTTOMRIGHT", -4, 6)
    c.list:SetEmptyText(L["Nothing right now: new prices come every hour."])
    return c
end

-- your best asset: the most valuable thing you hold, and its week
local function BestAsset()
    local rows = FT.Port and FT.Port.Rows and FT.Port.Rows() or {}
    local best
    for _, r in ipairs(rows) do
        if r.value and (not best or r.value > best.value) then best = r end
    end
    if not best then return nil end
    local s = FT.An.Stats(best.id)
    local wk = s and s.ch7
    return { id = best.id, kind = "HOLD", label = L["BEST ASSET"], gold = FT.Money(math.floor(best.value), "gold"),
        what = FT.ItemText(best.id, 26) .. FT.C("dim", " ×" .. FT.Num(best.total or best.qty or 0))
            .. (wk and ("  ·  " .. FT.C(wk >= 0 and "up" or "down", FT.An.Pc(wk)) .. FT.C("dim", " " .. L["this week"])) or ""),
        tip = L["The most valuable thing you hold, across your characters."] }
end

-- (v0.51) the undercut check: your listings someone listed under, from your auctions (kept away from the auction
-- house) and the newest prices - one row, the biggest gap first
local function Undercuts()
    local O = FT.Owned
    if not (O and O.List and O.Undercut) then return nil end
    local n, worst, gap = 0, nil, 0
    for _, a in ipairs((O.List()) or {}) do
        if a.itemID and not a.sold then
            local low = O.Undercut(a)
            if low then
                n = n + 1
                local g = (a.unit - low) * (a.qty or 1)
                if g > gap then worst, gap = a, a.unit - low end
            end
        end
    end
    if n == 0 then return nil end
    return { id = worst.itemID, kind = "SELL", label = L["UNDERCUT"], gold = "-" .. FT.Money(math.floor(gap), "short"),
        what = (n == 1 and string.format(L["%s: someone listed under yours"], FT.ItemText(worst.itemID, 24))
            or string.format(L["%d of your listings undercut: %s the most"], n, FT.ItemText(worst.itemID, 22))),
        tip = L["Your auctions against the newest prices. At the auction house, Wolf says which to repost."] }
end

-- (v0.51) what to post tonight: what you hold that sells best in the next few hours (its price by the hour)
local function PostTonight()
    local now = tonumber(date("%H")) or 0
    local best
    for _, r in ipairs(FT.Port and FT.Port.Rows and (FT.Port.Rows()) or {}) do
        if r.value and r.value >= 10000 and r.signal ~= "HOLD" then
            local w = FT.WhenSummary and FT.WhenSummary(r.id)
            local at = w and (w.timed and w.sellAt or w.busyAt)
            if at then
                local wait = (at - now) % 24
                if wait >= 1 and wait <= 6 and (not best or r.value > best.r.value) then best = { r = r, w = w, at = at } end
            end
        end
    end
    if not best then return nil end
    local w = best.w
    return { id = best.r.id, kind = "SELL", label = L["POST"], gold = FT.Money(math.floor(best.r.value), "gold"),
        what = string.format(L["%s: post before %s, it sells best %s"], FT.ItemText(best.r.id, 22), date("%I%p", time() + ((best.at - now) % 24) * 3600):gsub("^0", ""):lower(),
            w.timed and w.sell or w.busy),
        tip = L["From its price by the hour: post a little before its best hours."] }
end

T.Undercuts, T.PostTonight = Undercuts, PostTonight

function T.FillMoves()
    if not T.moves then return end
    local cards = FT.TopMoves(8)
    -- your best asset first; then your listings undercut, and what to post tonight (one row each)
    local extras = {}
    for _, x in ipairs({ BestAsset() or false, Undercuts() or false, PostTonight() or false }) do
        if x then extras[#extras + 1] = x end
    end
    for _, x in ipairs(extras) do
        for i = #cards, 1, -1 do if cards[i].id == x.id then table.remove(cards, i) end end
    end
    for i = #extras, 1, -1 do table.insert(cards, 1, extras[i]) end
    T.moves.list:SetItems(cards)
end

-- three equal columns of a row
local function Thirds(row, frames)
    UI.OnSize(row, function(self, w, h)
        local cw = math.floor((w - GAP * 2) / 3)
        for i, f in ipairs(frames) do
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", self, "TOPLEFT", (i - 1) * (cw + GAP), 0)
            f:SetSize(cw, h)
        end
    end)
end

local function Signed(v)
    local m = FT.Money(math.abs(v), "gold")
    return v >= 0 and FT.C("up", "+" .. m) or FT.C("down", "-" .. m)
end

function T.Build(p)
    -- everything you own: worth, the last update's move, since yesterday, a line of the last 24 updates
    local own = UI.Panel(p, "bg1", "line")
    own:SetPoint("TOPLEFT", PAD, -PAD)
    own:SetPoint("TOPRIGHT", -PAD, -PAD)
    own:SetHeight(UI.RowH(58))
    own:EnableMouse(true)
    local label = UI.Text(own, 13, "muted")
    label:SetPoint("LEFT", 14, 0)
    label:SetText(L["Everything you own"])
    T.worth = UI.Text(own, 22, "text")
    T.worth:SetPoint("LEFT", label, "RIGHT", 16, 0)
    T.update = UI.Text(own, 13, "up")
    T.update:SetPoint("BOTTOMLEFT", T.worth, "RIGHT", 14, 1)
    T.since = UI.Text(own, 11, "muted")
    T.since:SetPoint("TOPLEFT", T.worth, "RIGHT", 14, -2)
    local span = UI.Text(own, 10, "dim", "RIGHT")
    span:SetPoint("RIGHT", -14, 0)
    span:SetText(L["last 24 updates"])
    T.span = span
    T.spark = UI.Sparkline(own, 240, 32)
    T.spark:SetPoint("RIGHT", span, "LEFT", -10, 0)
    T.update:SetPoint("RIGHT", T.spark, "LEFT", -12, 0)
    T.since:SetPoint("RIGHT", T.spark, "LEFT", -12, 0)
    own:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["Everything you own"], 1, 1, 1)
        GameTooltip:AddLine(L["Bags, banks, mail and the auction house of your characters on this server, at the latest prices, plus their gold."], 0.75, 0.78, 0.82, true)
        local played = FT.Port.Played()
        if played ~= 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine(played > 0 and L["Picked up today"] or L["Spent today"], Signed(played), 1, 0.82, 0)
            GameTooltip:AddLine(L["Loot, gold, buys, crafts and sales today, at the prices of the moment. Price updates aren't in it. A sale counts once its gold is read from the mailbox."], 0.58, 0.55, 0.5, true)
        end
        local list = FT.Port.Snaps()
        local shown = 0
        for i = #list, 2, -1 do
            local d = list[i].move
            if d == nil and not list[i].k then d = list[i].v - list[i - 1].v end
            if d then
                if shown == 0 then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(L["What each price update did to it"], 1, 0.82, 0)
                end
                GameTooltip:AddDoubleLine(FT.TimeOfDay(list[i].t) .. FT.C("dim", "   " .. FT.Money(list[i].v, "gold")), Signed(d), 0.85, 0.87, 0.9, 1, 1, 1)
                shown = shown + 1
                if shown >= 6 then break end
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Click: where it all is (You)."], 0.58, 0.55, 0.5)
        GameTooltip:Show()
    end)
    own:SetScript("OnLeave", function() GameTooltip:Hide() end)
    own:SetScript("OnMouseUp", function() FT.ShowSub("you", "portfolio") end)

    -- v0.50: Coming up on the left (a calendar of gold chances: the days ahead and their events, the calls under
    -- them), your best moves on the right (one card, it scrolls) - in place of the three top-3 cards
    local top = CreateFrame("Frame", nil, p)
    top:SetPoint("TOPLEFT", own, "BOTTOMLEFT", 0, -GAP)
    top:SetPoint("RIGHT", -PAD, 0)
    top:SetHeight(UI.RowH(196))
    T.coming = BuildComing(top)
    T.moves = BuildMoves(top)
    T.cards = { T.moves }
    UI.OnSize(top, function(self, w, h)
        local cw = math.floor((w - GAP * 2) / 3)
        T.coming:ClearAllPoints()
        T.coming:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
        T.coming:SetSize(cw * 2 + GAP, h)
        T.moves:ClearAllPoints()
        T.moves:SetPoint("TOPLEFT", self, "TOPLEFT", (cw + GAP) * 2, 0)
        T.moves:SetSize(cw, h)
    end)

    local bottom = CreateFrame("Frame", nil, p)
    bottom:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -GAP)
    bottom:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    T.bags = Box(bottom, L["In your bags"])
    T.bagsTotal = UI.Text(T.bags, 13, "text", "RIGHT")
    T.bagsTotal:SetPoint("TOPRIGHT", -12, -10)
    T.bags.list = ItemList(T.bags, true)
    T.bags.list:SetEmptyText(L["Nothing priced in your bags."])
    T.down = Box(bottom, L["Going down today"])
    T.down.list = ItemList(T.down)
    T.down.list:SetEmptyText(L["Nothing has dropped much today."])
    T.up = Box(bottom, L["Going up today"])
    T.up.list = ItemList(T.up)
    T.up.list:SetEmptyText(L["Nothing has climbed much today."])
    Thirds(bottom, { T.bags, T.down, T.up })
    built = true
end

-- what this character carries, priced, the most valuable first, with what to do with each
local function BagRows()
    local out, total = {}, 0
    local inv = FT.charKey and FT.db.inv and FT.db.inv[FT.charKey]
    for id, n in pairs(inv and inv.bags or {}) do
        if type(id) == "number" and type(n) == "number" and n > 0 then
            local s = FT.An.Stats(id)
            if s.price then
                local signal, strength, reason = FT.An.SellSignal(s)
                local v = s.price * n
                out[#out + 1] = { id = id, qty = n, value = v, signal = signal, strength = strength, reason = reason }
                total = total + v
            end
        end
    end
    table.sort(out, function(a, b) return a.value > b.value end)
    return out, total
end

-- the line: the worth at each of the last 24 updates; the first days (fewer than 6 of them), what you hold now was
-- worth on each of the last 14 days
local function WorthLine()
    local list = FT.Port.Snaps()
    local vals = {}
    if #list >= 6 then
        for i = math.max(1, #list - 23), #list do vals[#vals + 1] = list[i].v end
        return vals, L["last 24 updates"], nil
    end
    local hist = FT.Port.History(14)
    for _, h in ipairs(hist) do vals[#vals + 1] = h.value end
    if #vals < 2 then
        vals = {}
        for _, x in ipairs(list) do vals[#vals + 1] = x.v end
        return vals, L["last 24 updates"], nil
    end
    return vals, L["14 days"], vals[#vals] - vals[#vals - 1]
end

function T.FillWorth()
    if not built then return end
    T.worth:SetText(FT.Money(FT.Port.Worth(), "gold"))
    local lastMove, dayMove, now = FT.Port.WorthMoves()
    local vals, span, histDay = WorthLine()
    dayMove = dayMove or histDay
    T.span:SetText(span)
    if lastMove == 0 then
        T.update:SetText(FT.C("muted", string.format(L["no change with the last prices (%s)"], FT.TimeOfDay(now.t))))
    elseif lastMove then
        T.update:SetText(Signed(lastMove) .. FT.C("muted", " " .. string.format(L["with the last prices (%s)"], FT.TimeOfDay(now.t))))
    elseif dayMove and dayMove ~= 0 then
        T.update:SetText(Signed(dayMove) .. FT.C("muted", " " .. L["since yesterday"]))
        dayMove = nil -- said above
    else
        T.update:SetText(FT.C("dim", L["its move shows from the next prices"]))
    end
    local parts = {}
    local played = FT.Port.Played()
    if played > 0 then
        parts[#parts + 1] = Signed(played) .. " " .. L["picked up today"]
    elseif played < 0 then
        parts[#parts + 1] = Signed(played) .. " " .. L["spent today"]
    end
    if dayMove and dayMove ~= 0 then parts[#parts + 1] = Signed(dayMove) .. " " .. L["since yesterday"] end
    UI.FitBits(T.since, table.concat(parts, FT.C("dim", "  ·  ")))
    T.spark:SetValues(vals, (#vals < 2 or vals[#vals] >= vals[1]) and "up" or "down")
end

function T.Refresh()
    if not built then return end
    T.FillWorth()
    T.FillComing()
    T.FillMoves()
    local bags, total = BagRows()
    T.bags.list:SetItems(bags, true)
    T.bagsTotal:SetText(total > 0 and FT.Money(total, "gold") or "")
    T.down.list:SetItems(FT.Market.Movers(200, "ch1", false), true)
    T.up.list:SetItems(FT.Market.Movers(200, "ch1", true), true)
end

T.OnShow = T.Refresh

function T.OnItems()
    if not built then return end
    for _, l in ipairs({ T.bags.list, T.down.list, T.up.list, T.moves.list, T.coming.list }) do l:Refresh() end
end

local function IfShown() if built and T.cards[1]:IsVisible() then T.Refresh() end end
FT.On("FT_COMING_UP", function() if built and T.cards[1]:IsVisible() then T.FillComing() end end)
FT.On("FT_WORTH_CHANGED", function() if built and T.cards[1]:IsVisible() then T.FillWorth() end end)
FT.On("FT_DEALS_READY", IfShown)
FT.On("FT_CRAFTS_READY", IfShown)
FT.On("FT_MOVERS_READY", IfShown)
FT.On("FT_INVENTORY_CHANGED", function() FT.Debounce("todayBags", 1, IfShown) end)
FT.On("PLAYER_MONEY", function() if built and T.cards[1]:IsVisible() then FT.Debounce("todayWorth", 1, T.FillWorth) end end)
