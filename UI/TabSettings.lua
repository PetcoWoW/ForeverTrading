-- ForeverTrading: Settings page.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local T = {}
FT.Tabs.settings = T

local controls = {}
local ROW = 30

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
    StaticPopup_Show("FOREVERTRADING_RELOAD", text or L["This change shows after the interface reloads. Reload now?"])
end

StaticPopupDialogs["FOREVERTRADING_RELOAD"] = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["FOREVERTRADING_CLEAR"] = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        FT.Hist.ClearAll()
        FT.Print(L["Price history cleared."])
        T.Refresh()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function T.Build(p)
    local scroll, content = UI.ScrollArea(p)
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -8, 8)

    local left = CreateFrame("Frame", nil, content)
    local right = CreateFrame("Frame", nil, content)

    -- general
    local g = Section(left, L["General"], 8)
    Choice(g, "lang", L["Language"], { { "auto", L["Game language"] }, { "ru", "Русский" }, { "en", "English" } },
        L["Takes effect after /reload."], function()
            FT.AskReload(L["The new language shows after the interface reloads. Reload now?"])
        end)
    Choice(g, "theme", L["Style"], { { "dark", L["Dark"] }, { "light", L["Light"] }, { "classic", L["Classic"] } },
        L["Dark: an exchange terminal at night. Light: the same by day. Classic: the game's own look. Takes effect after a reload."],
        function() FT.AskReload(L["The new style shows after the interface reloads. Reload now?"]) end)
    Choice(g, "scale", L["Window scale"], { { 0.8, "80%" }, { 0.9, "90%" }, { 1.0, "100%" }, { 1.1, "110%" }, { 1.2, "120%" } },
        nil, function(v)
            local w = FT.Window()
            if w then
                w:SetScale(v)
                FT.ResetWindow()
            end
        end)
    Check(g, "ticker", L["Ticker tape under the header"], L["Your watchlist and the day's biggest movers, scrolling. Takes effect after /reload."],
        function() FT.AskReload() end)
    Check(g, "minimap", L["Minimap button"], nil, function() if FT.UpdateMinimap then FT.UpdateMinimap() end end)
    Check(g, "ahButton", L["Button on the auction house"], L["Opens ForeverTrading next to the auction house window."])
    Check(g, "tooltip", L["Lines in item tooltips"], L["Price change, RSI, the signal and the craft profit of the item."])
    Check(g, "versionCheck", L["Tell me about new versions"],
        L["ForeverTrading users in your guild and group tell each other which version they have (a hidden addon message): a newer one shows in chat and in the status bar."])

    -- scanning
    local sc = Section(left, L["Scanning"], 4)
    Check(sc, "autoMine", L["Scan My items when the auction house opens"],
        L["When they haven't been seen for 30 minutes. It pauses while you search yourself."])
    Check(sc, "autoFull", L["Full scan when the auction house opens"], L["At most once an hour."])
    Check(sc, "deepFull", L["Deep full scan (every auction)"],
        L["Reads every single auction (the game allows it once every 15 minutes): order books and auction counts of every item, not only the lowest price. The game freezes for a few seconds while it is read. In between, the quick full scan runs."])
    Choice(sc, "scanPages", L["My items: pages per item"], { { 1, "1 (50)" }, { 2, "2 (100)" }, { 5, "5 (250)" }, { 10, "10 (500)" } },
        L["Auctions read per item, cheapest first (50 a page). More pages: a deeper order book, a slower scan."])

    -- sources
    local so = Section(left, L["Sources"], 2)
    Check(so, "useAuctionator", "Auctionator",
        L["Its full scans and searches go into ForeverTrading's history, and the days you haven't scanned yourself come from its price database."],
        function() FT.Fire("FT_SOURCES_CHANGED") end)
    Check(so, "useMastercraft", "Mastercraft",
        L["Its price scans go into ForeverTrading's history; the recipes and holdings of alts you haven't logged in with ForeverTrading come from it."],
        function() FT.Fire("FT_SOURCES_CHANGED"); FT.Fire("FT_RECIPES_CHANGED"); FT.Fire("FT_INVENTORY_CHANGED") end)

    -- prices
    local pr = Section(left, L["Prices"], 2)
    Check(pr, "ahCut", L["Take the 5% auction house cut off profits"])
    Check(pr, "cheapestWay", L["Count materials you can craft cheaper at their craft cost"],
        L["Bars from ore, cloth bolts from cloth...: when one of your characters knows the recipe and it costs less than buying."])

    -- alerts
    local al = Section(left, L["Alerts"], 2)
    Check(al, "alertSound", L["Sound on a price alert"])
    Check(al, "alertChat", L["Message in chat on a price alert"])

    -- signals
    local sg = Section(right, L["Signals"], 5)
    MoneyField(sg, "minProfit", L["Craft: minimum profit"], L["A recipe with less profit gets WATCH instead of CRAFT."])
    Number(sg, "minMargin", L["Craft: minimum margin"], "%", nil, false, 0, 500)
    Number(sg, "sellAbove", L["Sell when the price is above average by"], "%", nil, false, 1, 500)
    Number(sg, "buyBelow", L["Buy when the price is below average by"], "%", nil, false, 1, 95)
    Choice(sg, "avgDays", L["Average over"], { { 7, L["7 days"] }, { 14, L["14 days"] }, { 30, L["30 days"] } })

    -- data
    local dt = Section(right, L["Data"], 5)
    Choice(dt, "keepDaily", L["Keep day candles for"], { { 30, L["30 days"] }, { 60, L["60 days"] }, { 90, L["90 days"] }, { 180, L["180 days"] } },
        L["Every item seen on the auction house keeps one candle a day."])
    Check(dt, "trackAll", L["Intraday history for every item"],
        L["Normally only the items that matter to you get intraday candles (your recipes and materials, watchlist, what you own, what you open). For every item the saved file grows a lot."],
        function() FT.Fire("FT_WATCH_CHANGED") end)
    Choice(dt, "keepDays", L["Keep intraday history for"], { { 14, L["14 days"] }, { 30, L["30 days"] }, { 45, L["45 days"] }, { 90, L["90 days"] } })
    T.footprint = UI.Text(dt, 11, "dim")
    T.footprint:SetPoint("TOPLEFT", 14, dt.y - 6)
    local clear = UI.Button(dt, L["Clear history"], 10, 24, "down", function()
        StaticPopup_Show("FOREVERTRADING_CLEAR", L["Clear ForeverTrading's price history (day candles, intraday, order books) of this server? Auctionator's and Mastercraft's own data stay."])
    end)
    clear:FitText(24)
    clear:SetPoint("TOPRIGHT", -14, dt.y)
    Next(dt)
    local reload = UI.Button(dt, L["Reload UI"], 10, 24, "default", function() ReloadUI() end)
    reload:FitText(24)
    reload:SetPoint("TOPRIGHT", -14, dt.y)
    local rl = UI.Text(dt, 11, "dim")
    rl:SetPoint("TOPLEFT", 14, dt.y - 6)
    rl:SetText(L["Language and ticker changes need a reload."])
    Next(dt)

    -- about
    local ab = Section(right, L["About"], 5)
    T.about = UI.Text(ab, 11, "muted")
    T.about:SetPoint("TOPLEFT", 14, -40)
    T.about:SetPoint("RIGHT", ab, "RIGHT", -14, 0)
    if T.about.SetWordWrap then T.about:SetWordWrap(true) end
    T.about:SetJustifyV("TOP")
    T.about:SetHeight(4 * ROW)
    local support = UI.Button(ab, L["Support on Boosty"], 10, 24, "primary", function() FT.ShowSupport() end)
    support:FitText(28)
    support:SetPoint("BOTTOMLEFT", 14, 12)
    local gh = UI.Button(ab, "GitHub", 10, 24, "default", function() FT.ShowGitHub() end)
    gh:FitText(28)
    gh:SetPoint("LEFT", support, "RIGHT", 8, 0)

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
    UI.OnSize(content, function(self, w)
        local cw = math.floor((w - 10) / 2)
        left:ClearAllPoints()
        left:SetPoint("TOPLEFT", 0, 0)
        left:SetWidth(cw)
        right:ClearAllPoints()
        right:SetPoint("TOPLEFT", cw + 10, 0)
        right:SetWidth(cw)
        local h1 = Stack(left, { g, sc, so, pr, al })
        local h2 = Stack(right, { sg, dt, ab })
        left:SetHeight(h1)
        right:SetHeight(h2)
        self:SetHeight(math.max(h1, h2))
    end)
end

function T.Refresh()
    for _, fn in ipairs(controls) do fn() end
    local items, size = FT.Hist.Footprint()
    T.footprint:SetText(string.format(L["%d items, about %s KB saved"], items, FT.Num(math.ceil(size / 1024))))
    local lines = {
        "ForeverTrading " .. FT.VERSION_TEXT,
        "Auctionator: " .. (FT.Atr.Loaded() and FT.C("up", L["connected"]) or FT.C("down", L["not loaded"])) ..
            "    Mastercraft: " .. (FT.MC.Loaded() and FT.C("up", L["connected"]) or FT.C("down", L["not loaded"])),
        L["Prices come from ForeverTrading's own scans (and Auctionator's and Mastercraft's when they are on); recipes from your profession windows and Mastercraft."],
        "/ft  ||  /ft scan  ||  /ft scan mine  ||  /ft stop  ||  /ft reset",
    }
    T.about:SetText(table.concat(lines, "\n"))
end

T.OnShow = T.Refresh
