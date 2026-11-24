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

