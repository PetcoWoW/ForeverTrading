-- ForeverTrading: "What's new" - once a version, the first time the window opens after an update: a few lines on
-- what came, each with a button to where it is. On a first install the tour is offered instead (UI/Tour.lua).
-- Again any time: Settings > About, /ft news.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local N = {}
FT.News = N

-- per version: { title, text, where it is (a function, or nil) } - made when shown: the language is applied at
-- start, after the files are read (a table made with them would keep the English)
local function News()
    return {
        ["v1.1.3"] = {
            { L["Hotfix"], L["The ForeverTrading tab on the auction house window works without Auctionator too."],
                nil },
        },
        ["v1.1.2"] = {
            { L["Blackwater apart"], L["The neutral auction house keeps its own prices, history, deals and your auctions: a scan there doesn't touch your faction's. Talking to an auctioneer picks its house; the chip next to the auction house status switches whose prices you see, the pencil on it puts a wrong auction house right."],
                nil },
            { L["Between the auction houses"], L["Signals > Deals > Between houses: cheaper at one auction house than the other sells it for - buy, carry it over, list it there; each house's cut counted, no more than sells there in two days."],
                function() FT.Show("signals"); FT.Tabs.signals.SetView("deals"); FT.Tabs.signals.SetDealKind("HOUSES") end },
            { L["Item windows"], L["More opens up to four item windows at once - two items side by side. Each has a compact mode (the charts alone) and its own auction house."],
                nil },
            { L["A faster exchange"], L["Prices go three times as fast between two players with 1.1.2 (three lanes at once). Exchange pressed again stops it; what has come stays."],
                nil },
            { L["Deals on any computer"], L["Signals > Deals asks the game for what vendors pay (a new computer or game knows hardly any), and says why there are none: old prices, too little history, the minimum profit."],
                function() FT.Show("signals"); FT.Tabs.signals.SetView("deals") end },
            { L["A tidier look"], L["Choices are one framed switch, tinted buttons have an edge, corners are slightly rounded, rows and filters line up; the light style shows hovered and chosen rows."],
                nil },
            { L["Fixes"], L["The deals journal counts what was sold (Forever's letters say 0) and keeps up with Collect all; no exchange during your own scan; the Settings columns stay; the ticker shows the market's most valuable listings while there are no moves yet."],
                nil },
        },
        ["v1.1.1"] = {
            { L["Good deals"], L["Signals > Deals: what to buy right now for a profit - under what a vendor pays, or far under the fair price on a steady market."],
                function() FT.Show("signals"); FT.Tabs.signals.SetView("deals") end },
            { L["What really sells"], L["How much really sells a day, on the Craft page, the Market and the item window (told from the listings); and risks: a flooded market, more sellers, hardly bought."],
                function() FT.Show("market") end },
            { L["Undercut"], L["A line in chat when an auction of yours is undercut; Sell > My auctions tells whether to wait or post it again."],
                function() FT.Show("sell"); FT.Tabs.sell.SetView("owned") end },
            { L["Deals journal"], L["Portfolio > Deals journal: what you really earned - from the auction house's letters."],
                function() FT.Show("portfolio"); FT.Tabs.portfolio.SetView("journal") end },
            { L["The craft queue"], L["Craft > Queue: the materials to buy for several crafts at once, at their cheapest, and how long it all takes to sell."],
                function() FT.Show("craft"); FT.Tabs.craft.SetView("queue") end },
            { L["Fixes"], L["The price exchange works (it didn't know your name), poisons are back on the Craft page, vendor prices of materials count, searching finds Russian names in any case."],
                nil },
        },
    }
end

-- a hotfix: what's new is that of the version it fixes, then its own lines (seen already with that version: not shown
-- again by itself)
local HOTFIX_OF = { ["v1.1.3"] = "v1.1.2" }
local function ListFor(v)
    local all, list = News(), {}
    local base = HOTFIX_OF[v]
    for _, it in ipairs(base and all[base] or {}) do list[#list + 1] = it end
    for _, it in ipairs(all[v] or {}) do list[#list + 1] = it end
    return #list > 0 and list or nil
end

local win

local function Build()
    win = CreateFrame("Frame", "ForeverTradingNews", UIParent, UI.EdgeTemplate())
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:SetScale(FT.S.scale or 1)
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    UI.Fill(win, "bg0")
    if not UI.ClassicEdge(win, "line", { edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 } }) then
        UI.Border(win, "line")
    end
    table.insert(UISpecialFrames, "ForeverTradingNews")
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) self:StartMoving() end)
    win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    -- seen: not again for this version
    win:SetScript("OnHide", function()
        if FT.db then FT.db.newsSeen = FT.VERSION_TEXT end
    end)

    win.title = UI.Text(win, 16, "text")
    win.title:SetPoint("TOPLEFT", 20, -18)
    local close = UI.Button(win, "×", 26, 26, "ghost", function() win:Hide() end)
    close.label:SetFont(UI.FONT, 18, "")
    close:SetPoint("TOPRIGHT", -10, -10)
    win.sub = UI.Text(win, 11, "dim")
    win.sub:SetPoint("TOPLEFT", win.title, "BOTTOMLEFT", 0, -4)
    win.sub:SetText(L["Press Show to go there."])

    win.rows = {}
    win.tour = UI.Button(win, L["Take the tour"], 10, 26, "default", function()
        win:Hide()
        FT.Tour.Start()
    end)
    win.tour:FitText(28)
    win.tour:SetPoint("BOTTOMLEFT", 20, 16)
    win.ok = UI.Button(win, L["Got it"], 10, 26, "primary", function() win:Hide() end)
    win.ok:FitText(36)
    win.ok:SetPoint("BOTTOMRIGHT", -20, 16)
end

local function Row(i)
    local r = win.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, win)
    r.title = UI.Text(r, 13, "accent")
    r.title:SetPoint("TOPLEFT", 0, 0)
    r.text = UI.Text(r, 11, "muted")
    r.text:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -3)
    r.text:SetPoint("RIGHT", r, "RIGHT", -96, 0)
    if r.text.SetWordWrap then r.text:SetWordWrap(true) end
    r.text:SetJustifyH("LEFT")
    r.go = UI.Button(r, L["Show"], 10, 22, "default", function()
        if r.goFn then
            win:Hide()
            r.goFn()
        end
    end)
    r.go:FitText(20)
    r.go:SetPoint("TOPRIGHT", 0, -2)
    win.rows[i] = r
    return r
end

function N.Hide()
    if win then win:Hide() end
end

-- the window for this version (nothing new for it: nothing shown)
function N.Show()
    local list = ListFor(FT.VERSION_TEXT)
    if not list then
        FT.Print(string.format(L["Nothing new written for %s."], FT.VERSION_TEXT))
        return
    end
    if not win then Build() end
    local width = 560
    win:SetWidth(width)
    win.title:SetText(string.format(L["What's new in ForeverTrading %s"], FT.VERSION_TEXT))
    local y = -64
    for i, item in ipairs(list) do
        local r = Row(i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 20, y)
        r:SetPoint("RIGHT", win, "RIGHT", -20, 0)
        r.title:SetText(item[1])
        r.text:SetText(item[2])
        r.goFn = item[3]
        r.go:SetShown(item[3] ~= nil)
        local h = 18 + math.max(14, math.ceil(r.text:GetStringHeight()))
        r:SetHeight(h)
        r:Show()
        y = y - h - 12
    end
    for i = #list + 1, #win.rows do win.rows[i]:Hide() end
    win:SetHeight(-y + 56)
    win:Show()
    win:Raise()
end

-- The main window opened: once a session, what's new for a version not seen yet - or, on a first install,
-- the tour offered
function N.OnWindow()
    if N.checked or not FT.db then return end
    N.checked = true
    if FT.freshInstall and not FT.db.tourOffered then
        FT.db.tourOffered = true
        FT.db.newsSeen = FT.VERSION_TEXT
        UI.Confirm({
            owner = "tourOffer",
            title = L["Welcome to ForeverTrading"],
            text = L["A short tour: where everything is and how to use it (a couple of minutes). It can be taken again any time: Settings > About, /ft tour."],
            ok = L["Take the tour"],
            cancel = L["Later"],
            onOK = function() FT.Tour.Start() end,
        })
        return
    end
    if FT.db.newsSeen ~= FT.VERSION_TEXT then
        if ListFor(FT.VERSION_TEXT) and FT.db.newsSeen ~= HOTFIX_OF[FT.VERSION_TEXT] then
            N.Show()
        else
            FT.db.newsSeen = FT.VERSION_TEXT
        end
    end
end

