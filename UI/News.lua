-- Wolf of Booty Bay (built on ForeverTrading): "What's new" - once a version, the first time the window opens after an update: a few lines on
-- what came, each with a button to where it is. On a first install the tour is offered instead (UI/Tour.lua).
-- Again any time: Settings > About, /wolf news.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local N = {}
FT.News = N

-- per version: { title, text, where it is (a function, or nil) } - made when shown: the language is applied at
-- start, after the files are read (a table made with them would keep the English)
local function News()
    return {
        ["v0.8"] = {
            { L["Signals that learn"], L["Each signal now checks what really happened before: did this item's jumps hold a week later, did its dips come back, which day it sells highest. Until an item has enough cases, it goes by its kind (all herbs, all ore...)."],
                function() FT.Show("market") end },
            { L["Long hold"], L["A button on any item's chart: you know it'll be worth more later. It says HODL until you unmark it."],
                function() FT.Show("market") end },
        },
        ["v0.7"] = {
            { L["HODL what's climbing"], L["A price that's high because it's climbed for weeks now says HODL, or SELL HALF when it's stretched. A sudden jump, or a climb that cracks, still says CASH OUT."],
                function() FT.Show("signals") end },
        },
        ["v0.6"] = {
            { L["Best use"], L["Every recipe a material goes into, all 2,300 of WoW Forever's, ranked by what one of it brings. Click a Farm Board row, or Best use on an item's chart."],
                function() FT.Show("signals"); FT.Tabs.signals.SetView("farm") end },
            { L["In the tooltip too"], L["A material's tooltip names its best use and how it compares to selling it as it is."] },
        },
        ["v0.5"] = {
            { L["TO THE MOON / RUG PULL"], L["A banner when something you own or watch jumps or crashes 30% in a day, and one for the market's biggest move."],
                function() FT.Show("market") end },
            { L["Whales and Market Makers"], L["After a Full scan: the sellers with the most gold listed (Terminal), WHALE ALERT when one seller holds most of an item you care about."],
                function() FT.Show("market") end },
            { L["APE IN"], L["The strongest buy signals now say APE IN. Turn the whole meme layer off in Settings > Alerts > Meme mode."],
                function() FT.Show("settings") end },
        },
        ["v0.4"] = {
            { L["The Money tab"], L["Carry it, Flip it, Vendor it, Sell yours, the Farm Board: one list for each way to make gold, the best move right now on top."],
                function() FT.Show("signals") end },
            { L["Farm Board"], L["Raw materials by the gold the market pays for them a day. Right-click one for a Wowhead link."],
                function() FT.Show("signals"); FT.Tabs.signals.SetView("farm") end },
            { L["Characters"], L["Portfolio > Characters: every character's gold and holdings, and when its bank was last seen. Log your bank alt in once to count it."],
                function() FT.Show("portfolio"); FT.Tabs.portfolio.SetView("chars") end },
        },
        ["v0.3"] = {
            { L["Four tabs"], L["Terminal, Money, Portfolio, Sell. Craft is off until you turn it on: Settings > General."],
                nil },
            { L["Simple view"], L["Each item shows the four numbers that matter, what to do, and one clean chart: green when it went up, red when down. Pro chart: candles and averages."],
                function() FT.Show("market") end },
        },
        ["v0.2"] = {
            { L["Where your prices come from"], L["The status bar shows Blizzard's time and your scan's: the newer one in green. Yellow means newer prices are likely out: /reload."],
                nil },
            { L["One scan for both"], L["Full scan runs Auctionator's scan when it's installed, and its scans come into this addon too: no need to scan twice."],
                function() FT.Show("settings") end },
            { L["Your history counts"], L["Signals now count the days Auctionator scanned, so your old Auctionator history works from day one."],
                nil },
        },
        ["v0.1"] = {
            { L["Welcome to the Wolf of Booty Bay"], L["The auction house as a stock market. Built on ForeverTrading by thewoolfi - his scanner, history and price exchange, with our own look on top."],
                nil },
            { L["Easier to read"], L["The game's own wide font, bigger text and window sizes up to 150%: Settings > General."],
                function() FT.Show("settings") end },
            { L["The price feed"], L["Prices of every auction house come with each update, built hourly from Blizzard's own auction data: prices before your first scan, charts for the days you didn't scan, and what really sells over a whole week."],
                function() FT.Show("market") end },
            { L["Plain English"], L["Trader terms like RSI and liquidity are swapped for plain words. Prefer the trader terms? Settings > General > Words."],
                function() FT.Show("settings") end },
        },
    }
end

-- a hotfix: what's new is that of the version it fixes, then its own lines (seen already with that version: not shown
-- again by itself)
local HOTFIX_OF = {}

-- what's new is written per minor version ("v0.1"): the hourly price-feed releases only change the last number
local function NewsKey()
    return (FT.VERSION_TEXT or ""):match("^(v%d+%.%d+)") or FT.VERSION_TEXT
end
local function ListFor(v)
    local all, list = News(), {}
    local base = HOTFIX_OF[v]
    for _, it in ipairs(base and all[base] or {}) do list[#list + 1] = it end
    for _, it in ipairs(all[v] or {}) do list[#list + 1] = it end
    return #list > 0 and list or nil
end

local win

local function Build()
    win = CreateFrame("Frame", "WolfOfBootyBayNews", UIParent, UI.EdgeTemplate())
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
    table.insert(UISpecialFrames, "WolfOfBootyBayNews")
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) self:StartMoving() end)
    win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    -- seen: not again for this version
    win:SetScript("OnHide", function()
        if FT.db then FT.db.newsSeen = NewsKey() end
    end)

    win.title = UI.Text(win, 16, "text")
    win.title:SetPoint("TOPLEFT", 20, -18)
    local close = UI.Button(win, "×", 26, 26, "ghost", function() win:Hide() end)
    close.label:SetFont(UI.FONT, UI.Size(18), "")
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
    local list = ListFor(NewsKey())
    if not list then
        FT.Print(string.format(L["Nothing new written for %s."], FT.VERSION_TEXT))
        return
    end
    if not win then Build() end
    local width = 560
    win:SetWidth(width)
    win.title:SetText(string.format(L["What's new in Wolf of Booty Bay %s"], FT.VERSION_TEXT))
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
        FT.db.newsSeen = NewsKey()
        UI.Confirm({
            owner = "tourOffer",
            title = L["Welcome to Wolf of Booty Bay"],
            text = L["A short tour: where everything is and how to use it (a couple of minutes). It can be taken again any time: Settings > About, /wolf tour."],
            ok = L["Take the tour"],
            cancel = L["Later"],
            onOK = function() FT.Tour.Start() end,
        })
        return
    end
    if FT.db.newsSeen ~= NewsKey() then
        if ListFor(NewsKey()) and FT.db.newsSeen ~= HOTFIX_OF[NewsKey()] then
            N.Show()
        else
            FT.db.newsSeen = NewsKey()
        end
    end
end

