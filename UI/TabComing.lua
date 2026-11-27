-- Wolf: Make gold > Coming up (v0.50, in place of Raid prep). What should pay next week and when: this week's
-- events (the Darkmoon Faire, a battleground's holiday week, the raids, Winter Veil), next week's best farms, what
-- to hold or sell for the raids, the PvP kit when the battlegrounds are busy. Every call says how sure Wolf is
-- (its record on that item over the last 30 days); under 40% it isn't shown. Tried first in Wolf Lab.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local T = {}
FT.Tabs.coming = T

local PAD = 12
local built, list, lead

local function Head(text) return { head = text } end

local function Rows()
    local out = {}
    local ev = FT.Ahead.Events(7)
    if #ev > 0 then
        out[#out + 1] = Head(L["This week"])
        for _, e in ipairs(ev) do out[#out + 1] = { event = e } end
    end
    local l = FT.Ahead.Lists(function() if built and list:IsVisible() then T.Refresh() end end)
    if not l then
        out[#out + 1] = Head(L["Working out next week's calls..."])
        return out
    end
    if #l.farms > 0 then
        out[#out + 1] = Head(L["Best farms next week"])
        for i = 1, math.min(6, #l.farms) do out[#out + 1] = l.farms[i] end
    end
    if #l.raids > 0 then
        out[#out + 1] = Head(L["The raids"])
        for _, r in ipairs(l.raids) do out[#out + 1] = r end
    end
    -- the PvP kit: when a battleground's holiday week is on or coming
    local bgWeek
    for _, e in ipairs(ev) do if e.kind == "bg" then bgWeek = e end end
    if bgWeek and #l.pvp > 0 then
        out[#out + 1] = Head(string.format(L["PvP: %s"], bgWeek.name))
        for i = 1, math.min(4, #l.pvp) do out[#out + 1] = l.pvp[i] end
    end
    -- (v0.50, partial) Forever's content phases: what's known of them
    out[#out + 1] = Head(L["Content phases"])
    for _, ph in ipairs(FT.Ahead.Phases()) do out[#out + 1] = { phase = ph } end
    return out
end

local function When(t)
    local d = math.floor((t - time()) / 86400 + 0.999)
    if t <= time() then return L["on now"] end
    if d <= 1 then return L["tomorrow"] end
    return date("%a %b %d", t)
end

function T.Build(p)
    -- the section bar top left, as on every Make gold and You page; the line beside it
    local bar = UI.GroupBar(p, "make")
    bar:SetPoint("TOPLEFT", PAD, -8)
    bar:SetValue("coming")
    lead = UI.Text(p, 11, "dim")
    lead:SetPoint("LEFT", bar, "RIGHT", 14, 0)
    lead:SetPoint("RIGHT", p, "RIGHT", -PAD, 0)
    if lead.SetWordWrap then lead:SetWordWrap(false) end
    T.lead = lead

    local box = UI.Panel(p, "bg1", "line")
    box:SetPoint("TOPLEFT", PAD, -40)
    box:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    list = UI.List(box, {
        rowHeight = UI.RowH(44),
        setup = function(row)
            row.badge = UI.Badge(row, 64, 20)
            row.badge:SetPoint("LEFT", 10, 0)
            row.right = UI.Text(row, 13, "text", "RIGHT")
            row.right:SetPoint("RIGHT", -14, 0)
            row.right:SetWidth(UI.RowH(130) + 6 * (tonumber(FT.S.textSize) or 0))
            row.name = UI.Text(row, 14, "text")
            row.name:SetPoint("TOPLEFT", row.badge, "TOPRIGHT", 14, 6)
            row.name:SetPoint("RIGHT", row.right, "LEFT", -12, 0)
            if row.name.SetWordWrap then row.name:SetWordWrap(false) end
            row.text = UI.Text(row, 12, "muted")
            row.text:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -4)
            row.text:SetPoint("RIGHT", row.right, "LEFT", -12, 0)
            if row.text.SetWordWrap then row.text:SetWordWrap(false) end
            row.head = UI.Text(row, 13, "accent")
            row.head:SetPoint("LEFT", 12, -4)
        end,
        update = function(row, x)
            local isHead = x.head ~= nil
            row.head:SetShown(isHead)
            row.badge:SetShown(not isHead)
            row.name:SetShown(not isHead)
            row.text:SetShown(not isHead)
            row.right:SetShown(not isHead)
            if isHead then row.head:SetText(x.head) return end
            if x.phase then
                local ph = x.phase
                row.badge:Set("WAIT", L["PHASE"])
                row.name:SetText(ph.name)
                UI.FitBits(row.text, ph.note or (ph.t and L["from the raids' study: what to stock is under The raids"]) or L["No date yet"])
                row.right:SetText(ph.t and FT.C("accent", When(ph.t)) or FT.C("dim", L["not dated"]))
                return
            end
            if x.event then
                local e = x.event
                row.badge:Set(e.kind == "bg" and "BUY" or (e.kind == "raid" and "HOLD" or "WAIT"), e.kind == "raid" and L["RAIDS"] or L["EVENT"])
                row.name:SetText(e.name .. (e.where and FT.C("dim", "  ·  " .. e.where) or ""))
                local items = FT.Ahead.EventItems(e.kind)
                local names = {}
                for i = 1, math.min(3, #items) do names[#names + 1] = FT.ItemText(items[i], 20) end
                UI.FitBits(row.text, #names > 0 and (L["it pulls on"] .. " " .. table.concat(names, "  ·  ")) or L["a holiday: its own quests and treats"])
                row.right:SetText(FT.C("accent", When(e.t)))
                return
            end
            local c = x.call
            row.badge:Set(x.kind)
            row.name:SetText(FT.ItemText(x.id))
            local parts = {}
            if x.hour then parts[#parts + 1] = FT.C("text", "~" .. FT.Money(math.floor(x.hour), "gold") .. " " .. L["an hour"]) end
            parts[#parts + 1] = (c.move >= 0 and FT.C("up", "+") or FT.C("down", "")) .. FT.C(c.move >= 0 and "up" or "down", FT.An.Pc(c.move)) .. FT.C("dim", " " .. L["next week"])
            parts[#parts + 1] = c.why
            if x.where then parts[#parts + 1] = x.where end
            UI.FitBits(row.text, table.concat(parts, FT.C("dim", "  ·  ")))
            row.right:SetText(FT.Ahead.SureText(c.sure))
        end,
        onClick = function(x) if x.id and not UI.ItemClick(x.id) then FT.OpenItem(x.id) end end,
        onEnter = function(row, x)
            if x.event then
                GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                GameTooltip:AddLine(x.event.name, 1, 0.82, 0)
                GameTooltip:AddLine(date("%a %b %d, %H:%M", x.event.t) .. " - " .. date("%a %b %d", x.event.ends), 0.85, 0.87, 0.9)
                for _, id in ipairs(FT.Ahead.EventItems(x.event.kind)) do
                    GameTooltip:AddLine(FT.ItemText(id, 34), 0.75, 0.78, 0.82)
                end
                GameTooltip:Show()
                return
            end
            if not x.id or not x.call then return end
            UI.TipItem(row, x.id)
            local c = x.call
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine(L["How sure"], c.sure .. "%", 1, 0.82, 0, 1, 1, 1)
            GameTooltip:AddLine(string.format(L["The same call was right %d of %d weeks on this item's last 30 days."], c.hits, c.weeks), 0.75, 0.78, 0.82, true)
            if c.event then GameTooltip:AddLine(string.format(L["%s is on the calendar: a known pull."], c.event.name), 0.75, 0.78, 0.82, true) end
            GameTooltip:AddLine(L["Click: its page"], 0.58, 0.55, 0.5)
            GameTooltip:Show()
        end,
    })
    list:SetPoint("TOPLEFT", 6, -6)
    list:SetPoint("BOTTOMRIGHT", -6, 6)
    list:SetEmptyText(L["Nothing on the calendar this week, and no call sure enough yet: new prices come every hour."])
    built = true
end

function T.Refresh()
    if not built then return end
    -- (Wolf knows you: the farms fit your professions and level)
    local me = FT.Me and FT.Me.Text()
    UI.FitSize(lead, L["What should pay next week, and how sure Wolf is: every call checked against the item's last 30 days."]
        .. (me and FT.C("dim", "  ·  " .. L["fits you"] .. ": " .. me) or ""), 11, 2)
    list:SetItems(Rows())
end
T.OnShow = T.Refresh

FT.On("FT_COMING_UP", function() if built and list:IsVisible() then T.Refresh() end end)
