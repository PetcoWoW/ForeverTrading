-- Wolf of Booty Bay (built on ForeverTrading): Settings page.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local T = {}
FT.Tabs.settings = T

local controls = {}
local ROW = 30
local UNSEEN_DAYS = 30 -- Data > Remove: items not seen on the auction house this long

local function Changed()
    FT.Fire("FT_SETTINGS_CHANGED")
end

local function Section(parent, title, rows)
    local s = UI.Panel(parent, "bg1", "line")
    s.title = UI.Text(s, 13, "text")
    s.title:SetPoint("TOPLEFT", 14, -12)
    s.title:SetText(title)
    s:SetHeight(44 + rows * ROW)
    s.y = -40
    return s
end

local function Label(s, text, tip)
    local l = UI.Text(s, 12, "muted")
    l:SetPoint("TOPLEFT", 14, s.y - 6)
    l:SetText(text)
    if tip then
        local hit = CreateFrame("Frame", nil, s)
        hit:SetAllPoints(l)
        hit:EnableMouse(true)
        hit:SetScript("OnEnter", function(self) UI.TipText(self, text, tip) end)
        hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return l
end

local function Next(s)
    s.y = s.y - ROW
end

local function Check(s, key, text, tip, after)
    local c = UI.Check(s, text, function(on)
        FT.S[key] = on
        if after then after(on) end
        Changed()
    end)
    c:SetPoint("TOPLEFT", 14, s.y - 4)
    if tip then c:SetTip(text, tip) end
    controls[#controls + 1] = function() c:SetChecked(FT.S[key]) end
    Next(s)
    return c
end

local function Choice(s, key, text, options, tip, after)
    Label(s, text, tip)
    local dd = UI.Dropdown(s, 170, options, function(v)
        FT.S[key] = v
        if after then after(v) end
        Changed()
    end)
    dd:SetPoint("TOPRIGHT", -14, s.y)
    controls[#controls + 1] = function() dd:SetValue(FT.S[key]) end
    Next(s)
    return dd
end

-- number field; money = true takes "12g 50s"; min / max clamp
-- an amount of money: gold, silver and copper boxes
local function MoneyField(s, key, text, tip)
    Label(s, text, tip)
    local m
    m = UI.MoneyInput(s, function(v)
        v = v or 0
        if v ~= FT.S[key] then
            FT.S[key] = v
            Changed()
        end
        m:SetValue(FT.S[key])
    end)
    m:SetPoint("TOPRIGHT", -14, s.y)
    controls[#controls + 1] = function() if not m:HasFocus() then m:SetValue(FT.S[key]) end end
    Next(s)
    return m
end

local function Number(s, key, text, suffix, tip, money, min, max)
    Label(s, text, tip)
    local e
    local function Show()
        e:SetValue(money and FT.MoneyPlain(FT.S[key]) or tostring(FT.S[key]))
    end
    local function Apply()
        local v
        if money then v = FT.ParseMoney(e:GetText()) else v = tonumber(e:GetText()) end
        if v then
            if min then v = math.max(min, v) end
            if max then v = math.min(max, v) end
            if v ~= FT.S[key] then
                FT.S[key] = v
                Changed()
            end
        end
        Show()
    end
    e = UI.Input(s, 90, 24, "", nil, Apply)
    e:SetPoint("TOPRIGHT", -14 - (suffix and 34 or 0), s.y)
    e:HookScript("OnEditFocusLost", Apply)
    if suffix then
        local u = UI.Text(s, 12, "dim")
        u:SetPoint("LEFT", e, "RIGHT", 8, 0)
        u:SetText(suffix)
    end
    -- a refresh never overwrites what you are typing
    controls[#controls + 1] = function() if not e:HasFocus() then Show() end end
    Next(s)
    return e
end

-- "reload now?" after a change that only shows after a reload (language, style, ticker tape)
function FT.AskReload(text)
    UI.Confirm({
        title = L["Reload UI"],
        text = text or L["This change shows after the interface reloads. Reload now?"],
        ok = L["Reload UI"],
        cancel = L["Later"],
        onOK = function() ReloadUI() end,
    })
end

function T.Build(p)
    local scroll, content = UI.ScrollArea(p)
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -8, 8)

    local left = CreateFrame("Frame", nil, content)
    local right = CreateFrame("Frame", nil, content)

    -- general
    local g = Section(left, L["General"], 12)
    Choice(g, "words", L["Words"], { { "plain", L["Plain English"] }, { "trader", L["Trader terms"] } },
        L["Plain English swaps the trader terms (RSI, liquidity, volatility...) for plain words. Takes effect after a reload."],
        function() FT.AskReload(L["The new words show after the interface reloads. Reload now?"]) end)
    Choice(g, "font", L["Font"], { { "game", L["Game font (wide)"] }, { "condensed", L["Condensed (narrow)"] } },
        L["The game's own font reads easiest; the condensed one fits more in a row. Takes effect after a reload."],
        function() FT.AskReload(L["The new font shows after the interface reloads. Reload now?"]) end)
    Choice(g, "textSize", L["Text size"], { { 0, L["Normal"] }, { 1, L["Large"] }, { 2, L["Larger"] } },
        L["Makes every text bigger without making the window bigger. Takes effect after a reload."],
        function() FT.AskReload(L["The new text size shows after the interface reloads. Reload now?"]) end)
    Choice(g, "scale", L["Window scale"], { { 0.9, "90%" }, { 1.0, "100%" }, { 1.1, "110%" }, { 1.2, "120%" }, { 1.3, "130%" }, { 1.4, "140%" }, { 1.5, "150%" } },
        nil, function(v)
            local w = FT.Window()
            if w then
                w:SetScale(v)
                FT.ResetWindow()
            end
            FT.Detail.Rescale(v)
        end)
    Check(g, "simple", L["Simple view"],
        L["The numbers that matter at a glance: four key numbers per item, what to do in one card, one clean chart. Off: every number and indicator. Takes effect after a reload."],
        function() FT.AskReload() end)
    Check(g, "showCraft", L["Craft tab"],
        L["Recipes your characters know, with their profit. Takes effect after a reload."],
        function() FT.AskReload() end)
    Check(g, "ticker", L["Ticker tape under the header"], L["Your watchlist and the day's biggest movers, scrolling. Takes effect after /reload."],
        function() FT.AskReload() end)
    Check(g, "minimap", L["Minimap button"], nil, function() if FT.UpdateMinimap then FT.UpdateMinimap() end end)
    Check(g, "ahButton", L["Button on the auction house"], L["Opens Wolf of Booty Bay next to the auction house window."])
    Check(g, "replaceAH", L["Open Wolf of Booty Bay instead of the auction house window"],
        L["Talking to an auctioneer opens Wolf of Booty Bay; the game's window stays open behind it, unseen. The \"AH: online\" pill in the header brings it back for buying and selling (and Auctionator). Walking away: the terminal goes offline with the last known prices."])
    Check(g, "tooltip", L["Lines in item tooltips"], L["Price change, RSI, the signal and the craft profit of the item, and a material's best use."])
    Check(g, "versionCheck", L["Tell me about new versions"],
        L["Wolf of Booty Bay users in your guild and group tell each other which version they have (a hidden addon message): a newer one shows in chat and in the status bar."])

    -- scanning
    local sc = Section(left, L["Scanning"], 4)
    Check(sc, "liveRefresh", L["Live price of the open item"],
        L["While the auction house is open, the item you have open (on the Market or in its own window) is searched again every 8 seconds: its price and order book stay fresh. On the Craft page the recipe's item and its materials take turns, so its cost and profit stay fresh too. It pauses while you search, buy or sell yourself, and slows down when the server is busy."])
    Check(sc, "autoFull", L["Full scan when the auction house opens"], L["At most once an hour."])
    Check(sc, "deepFull", L["Deep full scan (every auction)"],
        L["Reads every single auction (the game allows it once every 15 minutes): order books and auction counts of every item, not only the lowest price. The game freezes for a few seconds while it is read. In between, the quick full scan runs."])
    Choice(sc, "scanPages", L["My items: pages per item"], { { 1, "1 (50)" }, { 2, "2 (100)" }, { 5, "5 (250)" }, { 10, "10 (500)" } },
        L["Auctions read per item, cheapest first (50 a page). More pages: a deeper order book, a slower scan."])

    -- sources
    local so = Section(left, L["Sources"], 4)
    Check(so, "useFeed", L["Price feed"],
        L["Prices of every auction house, built hourly from Blizzard's own auction data and shipped with each update: prices before your first scan, and charts for the days you didn't scan. Update the addon (WowUp) and /reload for fresh ones."],
        function() FT.Fire("FT_SOURCES_CHANGED"); if FT.Feed then FT.Feed.Take() end end)
    Check(so, "reloadReminder", L["Reload reminder"],
        L["A line in chat, at most once an hour and never in combat, when newer feed prices are likely out: /reload loads them."])
    Check(so, "scanWithAuctionator", L["One scan for both"],
        L["Full scan runs Auctionator's scan when Auctionator is installed: one scan, and both addons get the prices."])
    Check(so, "useAuctionator", "Auctionator",
        L["Its full scans and searches go into Wolf of Booty Bay's history, and the days you haven't scanned yourself come from its price database."],
        function() FT.Fire("FT_SOURCES_CHANGED") end)

    -- prices
    local pr = Section(left, L["Prices"], 2)
    Check(pr, "ahCut", L["Take the auction house cut off profits"],
        L["The cut is learned from the auction house's letters about your sales (it isn't the same everywhere); 5% until one is read."])
    Check(pr, "cheapestWay", L["Count materials you can craft cheaper at their craft cost"],
        L["Bars from ore, cloth bolts from cloth...: when one of your characters knows the recipe and it costs less than buying."])

    -- alerts
    local al = Section(left, L["Alerts"], 4)
    Check(al, "meme", L["Meme mode"],
        L["TO THE MOON and RUG PULL banners for what you own or watch, WHALE ALERT when one seller holds most of an item, APE IN on the strongest buys."])
    Check(al, "alertSound", L["Sound on a price alert"])
    Check(al, "alertChat", L["Message in chat on a price alert"])
    Check(al, "undercutAlert", L["Say in chat when you are undercut"],
        L["At the auction house: when an auction of yours is no longer the cheapest (your own other lots aside) - once per auction and price. Sell > My auctions tells whether to wait or post it again."])

    -- signals
    local sg = Section(right, L["Signals"], 12)
    MoneyField(sg, "minProfit", L["Craft: minimum profit"], L["A recipe with less profit gets WATCH instead of CRAFT."])
    Number(sg, "minMargin", L["Craft: minimum margin"], "%", nil, false, 0, 500)
    Number(sg, "sellAbove", L["Sell when the price is above average by"], "%", nil, false, 1, 500)
    Number(sg, "buyBelow", L["Buy when the price is below average by"], "%", nil, false, 1, 95)
    Choice(sg, "avgDays", L["Average over"], { { 7, L["7 days"] }, { 14, L["14 days"] }, { 30, L["30 days"] } })
    Check(sg, "holdTrends", L["Hold what's climbing"],
        L["High because it's been climbing for weeks (up 15%+ in 30 days, higher lows, still selling): HODL instead of cash out. Far above its average: sell half. The climb cracking (price falling, flooded, more sellers, not selling): cash out. Needs 3 weeks of prices."])
    Check(sg, "spikeGuard", L["Don't trust buyouts"],
        L["Someone bought out the cheap lots and listed them far higher: the lowest price then says little. The fair price is the median of the prices of the last days up to an hour ago, each weighted by how many were listed at it and how recent it is. When the price is far above it, profits and signals count the fair price."])
    Choice(sg, "spikeAbove", L["Jump: above the fair price by"], { { 30, "30%" }, { 50, "50%" }, { 100, "100%" }, { 200, "200%" } })
    Choice(sg, "fallBelow", L["Falling fast: below the fair price by"], { { 10, "10%" }, { 20, "20%" }, { 30, "30%" }, { 50, "50%" } },
        L["Other crafters undercut: a craft of an item falling this fast gets RISKY - by the time yours is listed the price may be lower still."])
    Choice(sg, "floodAbove", L["Flooded: more than usual by"], { { 30, "30%" }, { 50, "50%" }, { 100, "100%" }, { 200, "200%" } },
        L["More listed than usual, or more sellers than usual, by this much: competitors have come, and a price that holds now may not hold long. A craft of it gets RISKY and the Sell page warns. Usual: the average of the last days up to an hour ago (sellers are counted from the searches of an item: My items, live prices, the items you open). A price 10% lower than at the last check half an hour or more ago is RISKY too."])
    Choice(sg, "dealBelow", L["Deals: resale under the fair price by"], { { 20, "20%" }, { 30, "30%" }, { 40, "40%" }, { 50, "50%" } },
        L["Signals > Good deals: a lot this far under its fair price, on a market that sells most days and isn't flooded, is worth buying to list again."])
    MoneyField(sg, "dealMin", L["Deals: minimum profit"], L["Deals that bring less are not shown (a vendor deal too)."])

    -- exchange
    local ex = Section(right, L["Exchange"], 3)
    Check(ex, "shareAuto", L["Ask guild and group for fresh prices"],
        L["When your prices of the whole market are more than an hour old, Wolf of Booty Bay asks its users in your guild (then your group) who has fresher ones; the freshest sends its last full scan in the background. At most once an hour."])
    Check(ex, "shareSend", L["Share my scans"],
        L["When someone in your guild or group asks, your full scan (less than 3 days old and fresher than theirs) goes to them in the background: hidden addon messages, one a second, paused in a fight."])
    T.shareText = UI.Text(ex, 11, "dim")
    T.shareText:SetPoint("TOPLEFT", 14, ex.y - 6)
    local askNow = UI.Button(ex, L["Ask now"], 10, 24, "default", function() FT.Share.Ask(true) end)
    askNow:FitText(24)
    askNow:SetPoint("TOPRIGHT", -14, ex.y)
    T.shareText:SetPoint("RIGHT", askNow, "LEFT", -10, 0)
    Next(ex)

    -- data
    local dt = Section(right, L["Data"], 6)
    Choice(dt, "keepDaily", L["Keep day candles for"], { { 30, L["30 days"] }, { 60, L["60 days"] }, { 90, L["90 days"] }, { 180, L["180 days"] } },
        L["Every item seen on the auction house keeps one candle a day."])
    Check(dt, "trackAll", L["Intraday history for every item"],
        L["Normally only the items that matter to you get intraday candles (your recipes and materials, watchlist, what you own, what you open). For every item the saved file grows a lot."],
        function() FT.Fire("FT_WATCH_CHANGED") end)
    Choice(dt, "keepDays", L["Keep intraday history for"], { { 14, L["14 days"] }, { 30, L["30 days"] }, { 45, L["45 days"] }, { 90, L["90 days"] } })
    T.footprint = UI.Text(dt, 11, "dim")
    T.footprint:SetPoint("TOPLEFT", 14, dt.y - 6)
    local clear = UI.Button(dt, L["Clear history"], 10, 24, "down", function()
        UI.Confirm({
            title = L["Clear history"],
            text = string.format(L["Clear Wolf of Booty Bay's price history (day candles, intraday, order books) of this server's auction house: %s? The other auction house's, Auctionator's and Mastercraft's data stay."],
                FT.House.Name()),
            ok = L["Clear history"],
            okStyle = "down",
            onOK = function()
                FT.Hist.ClearAll()
                FT.Print(L["Price history cleared."])
                T.Refresh()
            end,
        })
    end)
    clear:FitText(24)
    clear:SetPoint("TOPRIGHT", -14, dt.y)
    Next(dt)
    -- items long gone from the auction house: their history out (a smaller saved file, a quicker login)
    T.unseen = UI.Text(dt, 11, "dim")
    T.unseen:SetPoint("TOPLEFT", 14, dt.y - 6)
    local drop = UI.Button(dt, L["Remove"], 10, 24, "default", function()
        local items, chars = FT.Hist.DropUnseen(UNSEEN_DAYS, false)
        if items == 0 then
            FT.Print(string.format(L["Nothing to remove: every item was seen in the last %d days (or matters to you)."], UNSEEN_DAYS))
            return
        end
        UI.Confirm({
            title = L["Remove items long gone"],
            text = string.format(L["Remove the history of %s items not seen on the auction house for %d days or more (both auction houses, about %s KB)? Those that matter to you stay: your recipes and their materials, watchlist, what you own."],
                FT.Num(items), UNSEEN_DAYS, FT.Num(math.ceil(chars / 1024))),
            ok = L["Remove"],
            okStyle = "down",
            onOK = function()
                local n, c = FT.Hist.DropUnseen(UNSEEN_DAYS, true)
                FT.Print(string.format(L["Removed the history of %s items not seen for %d days (about %s KB): the saved file is smaller from the next logout or /reload."],
                    FT.Num(n), UNSEEN_DAYS, FT.Num(math.ceil(c / 1024))))
                T.unseenAt = nil
                T.Refresh()
            end,
        })
    end)
    drop:FitText(24)
    drop:SetPoint("TOPRIGHT", -14, dt.y)
    T.unseen:SetPoint("RIGHT", drop, "LEFT", -10, 0)
    Next(dt)
    local reload = UI.Button(dt, L["Reload UI"], 10, 24, "default", function() ReloadUI() end)
    reload:FitText(24)
    reload:SetPoint("TOPRIGHT", -14, dt.y)
    local rl = UI.Text(dt, 11, "dim")
    rl:SetPoint("TOPLEFT", 14, dt.y - 6)
    rl:SetText(L["Language and ticker changes need a reload."])
    Next(dt)

    -- about
    local ab = Section(right, L["About"], 6)
    T.about = UI.Text(ab, 11, "muted")
    T.about:SetPoint("TOPLEFT", 14, -40)
    T.about:SetPoint("RIGHT", ab, "RIGHT", -14, 0)
    if T.about.SetWordWrap then T.about:SetWordWrap(true) end
    T.about:SetJustifyV("TOP")
    T.about:SetHeight(4 * ROW)
    local support = UI.Button(ab, L["Credits: ForeverTrading"], 10, 24, "primary", function() FT.ShowSupport() end)
    support:FitText(28)
    support:SetPoint("BOTTOMLEFT", 14, 12)
    local gh = UI.Button(ab, "GitHub", 10, 24, "default", function() FT.ShowGitHub() end)
    gh:FitText(28)
    gh:SetPoint("LEFT", support, "RIGHT", 8, 0)
    local news = UI.Button(ab, L["What's new"], 10, 24, "default", function() FT.News.Show() end)
    news:FitText(28)
    news:SetPoint("BOTTOMLEFT", support, "TOPLEFT", 0, 8)
    local tour = UI.Button(ab, L["Take the tour again"], 10, 24, "default", function() FT.Tour.Start() end)
    tour:FitText(28)
    tour:SetPoint("LEFT", news, "RIGHT", 8, 0)

    local function Stack(col, sections)
        local y = 0
        for _, s in ipairs(sections) do
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", col, "TOPLEFT", 0, y)
            s:SetPoint("TOPRIGHT", col, "TOPRIGHT", 0, y)
            y = y - s:GetHeight() - 10
        end
        return -y
    end
    -- two columns as wide as the page is now. A window changing size passes through sizes on the way (down to
    -- nothing): those are let go, and it is laid out again once the window has settled. The scroll stays inside
    -- the page (never sideways, never past the end).
    local function Layout()
        local w = scroll:GetWidth()
        if not w or w < 200 then return end
        local cw = math.floor((w - 10) / 2)
        content:SetWidth(w)
        left:ClearAllPoints()
        left:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        left:SetWidth(cw)
        right:ClearAllPoints()
        right:SetPoint("TOPLEFT", content, "TOPLEFT", cw + 10, 0)
        right:SetWidth(cw)
        local h1 = Stack(left, { g, sc, so, pr, al })
        local h2 = Stack(right, { sg, ex, dt, ab })
        left:SetHeight(h1)
        right:SetHeight(h2)
        content:SetHeight(math.max(h1, h2))
        if scroll.SetHorizontalScroll then scroll:SetHorizontalScroll(0) end
        local maxS = math.max(0, content:GetHeight() - scroll:GetHeight())
        if scroll:GetVerticalScroll() > maxS then scroll:SetVerticalScroll(maxS) end
        if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
    end
    local function Settled()
        Layout()
        C_Timer.After(0, Layout)
        C_Timer.After(0.2, Layout)
    end
    scroll:HookScript("OnSizeChanged", Settled)
    p:HookScript("OnShow", Settled)
    -- the window's size mode changed (compact, standard, full screen)
    T.OnLayout = Settled
    Layout()
end

function T.Refresh()
    for _, fn in ipairs(controls) do fn() end
    local items, size = FT.Hist.Footprint()
    T.footprint:SetText(string.format(L["%d items, about %s KB saved"], items, FT.Num(math.ceil(size / 1024))))
    -- counted at most once a minute (it reads both auction houses' data)
    if not T.unseenAt or GetTime() - T.unseenAt > 60 then
        T.unseenAt = GetTime()
        local n = FT.Hist.DropUnseen(UNSEEN_DAYS, false)
        T.unseen:SetText(string.format(L["Not seen for %d+ days: %s items"], UNSEEN_DAYS, FT.Num(n)))
    end
    local meta = FT.R().meta
    if meta.lastPeer then
        T.shareText:SetText(string.format(L["Last received: %s from %s"], FT.Ago(meta.lastPeer), meta.lastPeerFrom or "?"))
    else
        T.shareText:SetText(L["Nothing received yet"])
    end
    local lines = {
        "Wolf of Booty Bay  ||  " .. string.format(L["version %s"], FT.C("text", FT.VERSION_TEXT)),
        "Auctionator: " .. (FT.Atr.Loaded() and FT.C("up", L["connected"]) or FT.C("down", L["not loaded"])),
        L["Prices come from Wolf of Booty Bay's own scans (and Auctionator's when it is on); recipes from your profession windows."],
        "/wolf  ||  /wolf scan  ||  /wolf scan mine  ||  /wolf stop  ||  /wolf reset",
    }
    T.about:SetText(table.concat(lines, "\n"))
end

T.OnShow = T.Refresh
