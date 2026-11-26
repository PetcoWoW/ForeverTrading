-- Wolf of Booty Bay: "What's new" - once a version, the first time the window opens after an update: a few lines on
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
        ["v0.26"] = {
            { L["Futures: what raiders will need"], L["The Radar became Futures: the consumables every class will burn, ranked, with the herbs behind them and your move on each."], function() FT.Show("radar") end },
        },
        ["v0.25"] = {
            { L["The wolf knows what you've got"], L["Your top 3 on the Terminal now come from what you hold, watch, can craft and gather. Hover one for why."], function() FT.Show("market") end },
            { L["Quiet, and only in chat"], L["A few lines after login and after the auction house, each once a day. No pop-ups."], nil },
        },
        ["v0.24"] = {
            { L["Smarter search"], L["Type parts of words in any order: \"thor ore\" finds Thorium Ore."], function() FT.Show("market") end },
            { L["Tidier Terminal"], L["Category, subcategory and sort live in the Filter popup now; what's set shows as chips you can clear."], function() FT.Show("market") end },
            { L["Smoother"], L["No lag while crafting; the ticker keeps its place and stops under the mouse."], nil },
        },
        ["v0.23"] = {
            { L["The classic auction house look"], L["The game's own style everywhere: stone-and-gold edges, red buttons, gold labels, the game's tabs. Prefer the dark terminal? Settings > Look."],
                function() FT.Show("settings") end },
        },
        ["v0.22"] = {
            { L["Radar"], L["A new page: what's starting to sell faster before its price moves, what a rising craft is made of, what's cooling off, and the next raid opening. It grades its own calls."],
                function() FT.Show("radar") end },
            { L["Snipe at the auction house"], L["The Wolf tab at the auction house is Snipe now: after a scan, what's listed under its price with how sure (Safe, Good, Gamble) and Buy, plus the items worth searching again and again."] },
            { L["A cleaner chart"], L["One smooth line with its high and low, 7D / 30D / 90D, dates as 11/25. Pro chart keeps the candles."],
                function() FT.Show("market") end },
        },
        ["v0.21"] = {
            { L["Fresh prices, by the clock"], L["The Wolf prices companion (Windows): every 15 minutes it puts the newest prices in your addon folder and tells you to /reload. Settings > About > Prices companion."],
                function() FT.Show("settings") end },
            { L["Sessions you can tidy"], L["Right-click a session to rename or delete it. Opened, each find shows its price then and now, and what the stack gained or lost since."],
                function() FT.Show("sessions") end },
        },
        ["v0.20"] = {
            { L["One price everywhere"], L["The session panel, sessions, tooltips and the Portfolio now all use the same market price (it was after the 5% cut on the panel). Always the newest of your scan, the Blizzard API and Auctionator; Shift on a tooltip says which and when."] },
            { L["A bigger session panel"], L["Scroll it with the mouse wheel, drag its corner for more rows, hover a row for what it was worth when you found it and now. What you just looted shows on top for a moment."] },
        },
        ["v0.19"] = {
            { L["A pickier engine"], L["Deals are checked like a broker would: it really sells, the price is its real one, no one is pushing or dumping it, and flipping it worked before on its own history. Each deal shows its risk and record. A cheap price on a falling market now says WAIT, not BUY."],
                function() FT.Show("signals"); FT.Tabs.signals.SetView("make") end },
            { L["Item page in three answers"], L["Market (healthy, thin, stagnant, being pushed up or dumped), Price (where it's going) and The call (what to do, how sure, its record). No more price alerts or order book."],
                function() FT.Show("market") end },
            { L["Portfolio groups and session details"], L["Holdings in Materials, Crafted, BoE gear and Other. Click a past session to see what you found, worth then and now."],
                function() FT.Show("portfolio") end },
        },
        ["v0.18"] = {
            { L["Fresher Blizzard prices"], L["New prices go out within about 15 minutes of Blizzard's own update, instead of up to a few hours later. No more \"likely out, /reload\" guesses: after a login or /reload, one line says whether you got new prices. The API chip says when yours are from."] },
        },
        ["v0.17"] = {
            { L["Smoother"], L["Loading in no longer stutters: the price data is read item by item as it's needed, the heavy work at login is spread thinner and later, and nothing heavy runs in a fight. About 15% less memory."] },
        },
        ["v0.16"] = {
            { L["Blizzard prices fixed"], L["They load now whatever the game calls your realm. The API chip and the status bar say how old they are; if they ever can't load, the chip says why (Settings > Basics > Realm type)."] },
            { L["Craft for profit, every profession"], L["Every profession's crafts, whoever knows them: sell what it makes or disenchant it, whichever pays. Pick one profession, or only what you know; your crafters' skills are on top."],
                function() FT.Show("signals"); FT.Tabs.signals.SetView("craft") end },
        },
        ["v0.15"] = {
            { L["Sessions"], L["Right-click the minimap button: Start a session. Everything you loot counts, valued at today's prices, with gold an hour on a small panel. Portfolio > Sessions keeps your runs."],
                function() FT.Show("sessions") end },
            { L["It checks itself"], L["Every day it writes down its calls and a week later grades them. Each signal shows its record (right 7 of 10); a rule that keeps being wrong switches itself off."],
                function() FT.Show("market") end },
            { L["Recap, pings, sharing"], L["A market recap at login, a line when something you own has a good day to sell, Share on any item for guild chat, To Auctionator for shopping lists, and This week on the Terminal."] },
        },
        ["v0.14"] = {
            { L["Disenchanting"], L["Gear tooltips say whether to disenchant it or sell it. Money > Make gold lists gear worth buying to disenchant, for your best enchanter's skill. Classic's odds: Forever's may differ."],
                function() FT.Show("signals"); FT.Tabs.signals.SetView("make") end },
        },
        ["v0.13"] = {
            { L["Craft for profit"], L["Money > Craft for profit: every recipe in WoW Forever whose product sells every day, by the gold it should make a day. Click one: every material, what it costs, and crafting vs buying it ready."],
                function() FT.Show("signals"); FT.Tabs.signals.SetView("craft") end },
            { L["Before you buy"], L["Make gold now says how fast it sells and what it costs you, and warns when it's more than a third of your gold. What you can't afford goes last."],
                function() FT.Show("signals"); FT.Tabs.signals.SetView("make") end },
        },
        ["v0.12"] = {
            { L["Tickers"], L["Every item has a ticker now: $THOR, $ACRY, $RUGG. The tape shows your watchlist, then what you own, then the day's movers."],
                function() FT.Show("market") end },
            { L["Today's 3 moves"], L["On the Terminal: the best thing to carry, to flip and to farm right now, with the gold each should make."],
                function() FT.Show("market"); FT.Tabs.market.ShowOverview() end },
        },
        ["v0.11"] = {
            { L["Where the prices come from"], L["Top left: AH (your last scan, Auctionator's too) and API (Blizzard's hourly prices). The lit one is what you see. Auctionator's last scan is taken at login by itself."] },
            { L["Fewer pages"], L["Terminal, Money (Make gold, Farm) and Portfolio (Holdings, Sell yours, Characters, Journal). Scanning, posting and undercuts: Auctionator does those."],
                function() FT.Show("signals"); FT.Tabs.signals.SetView("make") end },
            { L["Plain reasons"], L["Every signal says why in plain words, and how sure it is: Sure, Likely or Guess. Hover the badge for the numbers."],
                function() FT.Show("market") end },
            { L["Lighter tooltips"], L["Two lines on every item, Shift for more. Worked out once, never in combat: no slowdown in your bags."] },
        },
        ["v0.10"] = {
            { L["Bug pass"], L["Money > Sell yours and Farm Board switch properly now; the biggest movers and banners skip tiny markets and one-off prices."],
                function() FT.Show("signals"); FT.Tabs.signals.SetView("farm") end },
        },
        ["v0.9"] = {
            { L["Quiet alerts"], L["Alerts are one line in chat now, nothing to click away. Want pop-ups back? Settings > Alerts > Pop-up alerts."],
                function() FT.Show("settings") end },
        },
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
            { L["Where your prices come from"], L["The status bar shows Blizzard's time and your scan's: the newer one in green. Yellow means they are over two hours old."],
                nil },
            { L["One scan for both"], L["Full scan runs Auctionator's scan when it's installed, and its scans come into this addon too: no need to scan twice."],
                function() FT.Show("settings") end },
            { L["Your history counts"], L["Signals now count the days Auctionator scanned, so your old Auctionator history works from day one."],
                nil },
        },
        ["v0.1"] = {
            { L["Welcome to the Wolf of Booty Bay"], L["The auction house as a stock market: tickers, moves, what to buy and sell, and your portfolio."],
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
    UI.Skin(win, "window", "bg0")
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
    local close = UI.CloseButton(win, function() win:Hide() end, 26)
    close:SetPoint("TOPRIGHT", UI.Classic() and -6 or -10, UI.Classic() and -6 or -10)
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

