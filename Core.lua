-- ForeverTrading: core (saved data, events, formatting helpers, slash commands)
local ADDON, FT = ...
local L = FT.L

local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
FT.VERSION = (GetMeta and GetMeta(ADDON, "Version")) or "dev"
-- a copy straight from the repository (not packaged): the packager hasn't put the version in yet
if FT.VERSION:find("@", 1, true) then FT.VERSION = "dev" end
FT.VERSION_TEXT = FT.VERSION:match("^%d") and ("v" .. FT.VERSION) or FT.VERSION
FT.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\media\\"
FT.URL_SUPPORT = "https://boosty.to/andrewwoolfi"
FT.URL_GITHUB = "https://github.com/thewoolfi/ForeverTrading"

---------------------------------------------------------------------------
-- Events: game events and our own ("FT_*") share one dispatcher
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

function FT.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        if not event:find("^FT_") then
            -- an event this client doesn't know must not break the addon
            pcall(eventFrame.RegisterEvent, eventFrame, event)
        end
    end
    table.insert(handlers[event], fn)
end

function FT.Fire(event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then
            geterrorhandler()(err)
        end
    end
end

eventFrame:SetScript("OnEvent", function(_, event, ...) FT.Fire(event, ...) end)

-- Run fn once, `delay` seconds after the last call with the same key. One timer per key, however
-- often it is called (a full scan saves thousands of prices in a few frames).
local pending = {}
function FT.Debounce(key, delay, fn)
    local due = GetTime() + delay
    local p = pending[key]
    if p then
        p.due, p.fn = due, fn
        return
    end
    p = { due = due, fn = fn }
    pending[key] = p
    local function Check()
        local left = p.due - GetTime()
        if left > 0.01 then
            C_Timer.After(left, Check)
            return
        end
        pending[key] = nil
        local ok, err = pcall(p.fn)
        if not ok then geterrorhandler()(err) end
    end
    C_Timer.After(delay, Check)
end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
FT.DEFAULTS = {
    lang = "auto",          -- auto / ru / en
    theme = "dark",         -- dark / light / classic (after a reload)
    useAuctionator = true,  -- its scans and searches go into our history; days we don't have come from it
    useMastercraft = true,  -- recipes and holdings of alts ForeverTrading hasn't seen yet
    autoMine = true,        -- scan "my items" when the auction house opens and they are old
    autoFull = false,       -- full scan when the auction house opens (at most once an hour)
    deepFull = false,       -- full scan reads every auction (ReplicateItems, once every 15 minutes)
    scanPages = 2,          -- pages (50 auctions each, cheapest first) read per item in "my items"
    keepDaily = 90,         -- days of day candles kept
    ahCut = true,           -- 5% auction house cut in profits
    cheapestWay = true,     -- a material you can craft cheaper counts at its craft cost
    minProfit = 2000,       -- copper: below this a craft is not a "CRAFT" signal
    minMargin = 10,         -- percent
    sellAbove = 10,         -- percent above the average price -> SELL
    buyBelow = 15,          -- percent below the average price -> BUY
    avgDays = 14,           -- days in the average price
    tooltip = true,
    versionCheck = true,    -- tell guild and group which version we have, hear about newer ones
    minimap = true,
    minimapAngle = 205,
    alertSound = true,
    alertChat = true,
    trackAll = false,       -- intraday history for every item (more memory)
    keepDays = 45,
    maxSnaps = 240,
    scale = 1.0,
    ticker = true,
    ahButton = true,
    dockAH = true,
    chartTF = "1D",
    showMA = false,
}

local function Fill(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then
            t[k] = v
        end
    end
end

-- One server of WoW Forever has numbered realms that are layers of it ("CAMWOW EU5 Realm 8 PvP"):
-- they share the auction house, so their data is kept together under "eu-pvp" (the same key
-- Mastercraft uses for its price book).
local SERVER_KINDS = {
    [""] = "normal", pve = "normal", normal = "normal", pvp = "pvp", rp = "roleplay", roleplay = "roleplay",
    ["rp-pvp"] = "roleplay-pvp", rppvp = "roleplay-pvp", ["roleplay-pvp"] = "roleplay-pvp",
    hc = "hardcore", hardcore = "hardcore",
}
local SERVER_REGIONS = { EU = "eu", US = "us", NA = "us", KR = "kr", TW = "tw", CN = "cn" }
function FT.ServerOf(realm)
    if type(realm) ~= "string" or realm == "" then return "?" end
    local init = 1
    while true do
        local s, _, region, kind = realm:find("%f[%a](%a%a)%d*%s+[Rr]ealm%s+%d+%s*(.-)%s*$", init)
        if not s then return realm end
        local r = SERVER_REGIONS[region:upper()]
        if r then
            kind = kind:lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
            kind = SERVER_KINDS[kind] or kind
            return r .. "-" .. kind
        end
        init = s + 1
    end
end

function FT.SideKey()
    local realm = GetRealmName and GetRealmName() or "?"
    local faction = UnitFactionGroup and UnitFactionGroup("player") or "?"
    return FT.ServerOf(realm) .. "-" .. tostring(faction)
end

-- Data of this server and faction (snapshots, order books, scan log)
function FT.R()
    local key = FT.sideKey or FT.SideKey()
    local realms = FT.db.realms
    local r = realms[key]
    if not r then
        r = {}
        realms[key] = r
    end
    r.snaps = r.snaps or {}
    r.books = r.books or {}
    r.scans = r.scans or {}
    r.days = r.days or {}
    r.today = r.today or {}
    r.meta = r.meta or {}
    return r
end

local function InitDB()
    ForeverTradingDB = ForeverTradingDB or {}
    local db = ForeverTradingDB
    db.settings = db.settings or {}
    Fill(db.settings, FT.DEFAULTS)
    db.realms = db.realms or {}
    db.watch = db.watch or {}
    db.viewed = db.viewed or {}
    db.recipes = db.recipes or {}
    db.chars = db.chars or {}
    db.inv = db.inv or {}
    db.vendor = db.vendor or {}
    db.frame = db.frame or {}
    -- 1.1: price charts are one line; the moving averages start switched off
    if (db.version or 1) < 2 then
        db.settings.showMA = false
        db.settings.chartType = nil
    end
    -- 1.2: "my items" reads the cheapest 100 auctions per item (was 250): a faster scan
    if (db.version or 1) < 3 and db.settings.scanPages == 5 then db.settings.scanPages = 2 end
    db.version = 3
    FT.db = db
    FT.S = db.settings
end

function FT.Lang()
    local lang = FT.S and FT.S.lang or "auto"
    if lang == "auto" then
        return (GetLocale() == "ruRU") and "ru" or "en"
    end
    return lang
end

---------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------
FT.HEX = {
    text = "eaecef", muted = "848e9c", dim = "5e6673", up = "0ecb81", down = "f6465d",
    accent = "f0b90b", blue = "3b82f6", purple = "a78bfa", gold = "e8b923", silver = "c0c6cc", copper = "d9894a",
}

function FT.C(hex, s)
    return "|cff" .. (FT.HEX[hex] or hex) .. tostring(s) .. "|r"
end

-- the game's own coin icons, as tall as the text around them
local function Coin(kind)
    return "|TInterface\\MoneyFrame\\UI-" .. kind .. "Icon:0:0:1:0|t"
end
FT.COIN = { gold = Coin("Gold"), silver = Coin("Silver"), copper = Coin("Copper") }
local G_SUFFIX = FT.COIN.gold
local S_SUFFIX = FT.COIN.silver
local C_SUFFIX = FT.COIN.copper

-- where a price came from, for people
function FT.SourceName(source)
    local names = { full = L["full scan"], mine = L["My items"], auctionator = "Auctionator", mastercraft = "Mastercraft",
        history = L["history"] }
    return names[source] or L["scan"]
end

function FT.Thousands(n)
    local s = tostring(math.floor(n))
    local out, k = s, 0
    repeat
        out, k = out:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    until k == 0
    return out
end

-- copper -> "42g 12s 30c"; mode "short": at most two units ("42g 12s", "1,204g")
function FT.Money(c, mode)
    if c == nil then return "|cff5e6673—|r" end
    local neg = c < 0
    c = math.floor(math.abs(c) + 0.5)
    local g = math.floor(c / 10000)
    local s = math.floor((c % 10000) / 100)
    local cp = c % 100
    local out
    if mode == "short" then
        if g >= 1000 then
            out = FT.Thousands(g) .. G_SUFFIX
        elseif g >= 1 then
            out = g .. G_SUFFIX .. (s > 0 and (" " .. s .. S_SUFFIX) or "")
        elseif s >= 1 then
            out = s .. S_SUFFIX .. (cp > 0 and (" " .. cp .. C_SUFFIX) or "")
        else
            out = cp .. C_SUFFIX
        end
    else
        local parts = {}
        if g > 0 then parts[#parts + 1] = FT.Thousands(g) .. G_SUFFIX end
        if s > 0 or (g > 0 and cp > 0) then parts[#parts + 1] = s .. S_SUFFIX end
        if cp > 0 or #parts == 0 then parts[#parts + 1] = cp .. C_SUFFIX end
        out = table.concat(parts, " ")
    end
    return (neg and "-" or "") .. out
end

-- copper -> "1500g50s25c" for input boxes: exact, no colours, read back by FT.ParseMoney
function FT.MoneyPlain(c)
    if not c then return "" end
    c = math.floor(c + 0.5)
    local g, s, cp = math.floor(c / 10000), math.floor((c % 10000) / 100), c % 100
    local out = ""
    if g > 0 then out = out .. g .. "g" end
    if s > 0 then out = out .. s .. "s" end
    if cp > 0 or out == "" then out = out .. cp .. "c" end
    return out
end

-- a profit with its sign: "+1g 20s" / "-35s"
function FT.SignedMoney(c)
    if c and c > 0 then return "+" .. FT.Money(c, "short") end
    return FT.Money(c, "short")
end

-- Plain number in gold for chart axes: 42.12 / 0.35
function FT.GoldNumber(c)
    if not c then return "" end
    local g = c / 10000
    if math.abs(g) >= 1000 then return FT.Thousands(g) end
    if math.abs(g) >= 100 then return string.format("%.1f", g) end
    if math.abs(g) >= 1 then return string.format("%.2f", g) end
    return string.format("%.4f", g)
end

-- fraction -> "+5.3%" in green / red
function FT.Pct(v, plain)
    if v == nil or v ~= v then return "|cff5e6673—|r" end
    local p = v * 100
    local s
    if math.abs(p) >= 1000 then
        s = string.format("%+.0f%%", p)
    else
        s = string.format("%+.1f%%", p)
    end
    if plain then return s end
    if p > 0.05 then return FT.C("up", s) end
    if p < -0.05 then return FT.C("down", s) end
    return FT.C("muted", s)
end

function FT.Num(n)
    if not n then return "—" end
    return FT.Thousands(n)
end

function FT.Ago(t)
    if not t or t <= 0 then return L["never"] end
    local d = time() - t
    if d < 60 then return L["just now"] end
    if d < 3600 then return string.format(L["%dm ago"], math.floor(d / 60)) end
    if d < 86400 then return string.format(L["%dh ago"], math.floor(d / 3600)) end
    return string.format(L["%dd ago"], math.floor(d / 86400))
end

---------------------------------------------------------------------------
-- Days, as Auctionator counts them (its price history is kept per day)
---------------------------------------------------------------------------
local DAY0 = time({ year = 2020, month = 1, day = 1, hour = 0 })
function FT.Day0()
    return (Auctionator and Auctionator.Constants and Auctionator.Constants.SCAN_DAY_0) or DAY0
end
function FT.Day(t)
    return math.floor(((t or time()) - FT.Day0()) / 86400)
end
function FT.DayStart(day)
    return day * 86400 + FT.Day0()
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------
local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

-- Item names we have seen, saved per game language: searching thousands of items needs their names
-- without asking the server for each one
local nameBook
local function NameBook()
    if not nameBook then
        FT.db.names = FT.db.names or {}
        local lang = GetLocale()
        FT.db.names[lang] = FT.db.names[lang] or {}
        nameBook = FT.db.names[lang]
    end
    return nameBook
end

function FT.RememberName(itemID, name)
    if itemID and type(name) == "string" and name ~= "" and FT.db then NameBook()[itemID] = name end
end

-- the name of an item without asking the server (nil when the game hasn't loaded it and we never saw it).
-- GetItemInfo itself asks the server for an item it doesn't have: only called for items the game has.
local IsCached = C_Item and C_Item.IsItemDataCachedByID
function FT.Name(itemID)
    if not itemID then return nil end
    if IsCached and not IsCached(itemID) then return NameBook()[itemID] end
    local name = GetInfo(itemID)
    if name then
        local book = NameBook()
        if book[itemID] ~= name then book[itemID] = name end
        return name
    end
    return NameBook()[itemID]
end

-- name, quality, icon, sellPrice, link (name from our book while the game hasn't loaded the item yet)
function FT.Item(itemID)
    if not itemID then return nil end
    local name, link, quality, _, _, _, _, _, _, icon, sellPrice = GetInfo(itemID)
    if not icon and GetInstant then
        icon = select(5, GetInstant(itemID))
    end
    if name then
        local book = NameBook()
        if book[itemID] ~= name then book[itemID] = name end
    else
        FT.RequestItem(itemID)
        name = NameBook()[itemID]
    end
    return name, quality, icon, sellPrice, link
end

-- classID, subClassID, icon without waiting for the item to load
function FT.ItemClass(itemID)
    if not (GetInstant and itemID) then return nil end
    local _, _, _, equipLoc, icon, classID, subClassID = GetInstant(itemID)
    return classID, subClassID, icon, equipLoc
end

local requested = {}
function FT.RequestItem(itemID)
    if requested[itemID] then return end
    requested[itemID] = true
    if C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
end

FT.On("GET_ITEM_INFO_RECEIVED", function()
    FT.Debounce("itemsLoaded", 0.4, function() FT.Fire("FT_ITEMS_LOADED") end)
end)

function FT.QualityHex(q)
    if FT.UI and FT.UI.theme == "light" then
        if not q or q <= 1 then return "ff" .. FT.HEX.text end
        if q == 2 then return "ff1a9e00" end -- a darker green than the game's, for white
    end
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c and c.hex then return c.hex:gsub("^|c", "") end
    return "ffeaecef"
end

-- the first n characters of a UTF-8 text (Russian letters are two bytes each: never cut one in half)
function FT.Trunc(s, n)
    if not s or not n then return s end
    local chars, i, len = 0, 1, #s
    while i <= len do
        chars = chars + 1
        if chars > n then
            -- cut before this character, leaving room for the ellipsis
            local cut, k, c = 1, 1, 0
            while k <= len and c < n - 1 do
                local b = s:byte(k)
                local size = (b >= 240 and 4) or (b >= 224 and 3) or (b >= 192 and 2) or 1
                k = k + size
                c = c + 1
                cut = k
            end
            return s:sub(1, cut - 1) .. "…"
        end
        local b = s:byte(i)
        i = i + ((b >= 240 and 4) or (b >= 224 and 3) or (b >= 192 and 2) or 1)
    end
    return s
end

function FT.ItemText(itemID, maxLen)
    local name, quality = FT.Item(itemID)
    if not name then return "|cff5e6673" .. L["Loading..."] .. " #" .. tostring(itemID) .. "|r" end
    if maxLen then name = FT.Trunc(name, maxLen) end
    return "|c" .. FT.QualityHex(quality) .. name .. "|r"
end

function FT.ItemIDFromLink(link)
    if type(link) == "number" then return link end
    return link and tonumber(link:match("item:(%d+)"))
end

---------------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------------
function FT.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cfff0b90bForever|r|cffeaecefTrading|r: " .. tostring(msg))
end

function FT.Debug(...)
    if FT.debug then
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        FT.Print("|cff848e9c[debug]|r " .. table.concat(parts, " "))
    end
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
FT.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    InitDB()
    FT.ApplyLocale(FT.Lang())
    FT.Fire("FT_DB_READY")
end)

FT.On("PLAYER_LOGIN", function()
    FT.charKey = UnitGUID("player")
    FT.sideKey = FT.SideKey()
    local c = FT.db.chars[FT.charKey] or {}
    FT.db.chars[FT.charKey] = c
    c.name = UnitName("player")
    c.realm = GetRealmName()
    c.server = FT.ServerOf(c.realm)
    c.faction = UnitFactionGroup("player")
    c.classFile = select(2, UnitClass("player"))
    c.side = FT.sideKey
    FT.Fire("FT_LOGIN")
    -- the other addons finish their own start on PLAYER_LOGIN: hook them a moment later
    C_Timer.After(0.5, function() FT.Fire("FT_READY") end)
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_FOREVERTRADING1 = "/ft"
SLASH_FOREVERTRADING2 = "/forevertrading"
SLASH_FOREVERTRADING3 = "/ftrade"
SlashCmdList.FOREVERTRADING = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    if cmd == "" then
        FT.Toggle()
    elseif cmd == "market" or cmd == "craft" or cmd == "signals" or cmd == "portfolio" or cmd == "settings" then
        FT.Show(cmd)
    elseif cmd == "lang" and (rest == "ru" or rest == "en" or rest == "auto") then
        FT.S.lang = rest
        if FT.AskReload then
            FT.AskReload(L["The new language shows after the interface reloads. Reload now?"])
        else
            FT.Print(L["Language changed. Type /reload to apply."])
        end
    elseif cmd == "reset" then
        FT.db.frame = {}
        if FT.ResetWindow then FT.ResetWindow() end
        FT.Print(L["Window position reset."])
    elseif cmd == "debug" then
        FT.debug = not FT.debug
        FT.Print("debug " .. tostring(FT.debug))
        if FT.debug and FT.DebugReport then FT.DebugReport() end
    elseif cmd == "scan" then
        if rest == "mine" or rest == "my" then
            FT.Scanner.StartMine()
        else
            FT.Scanner.StartFull()
        end
    elseif cmd == "support" or cmd == "donate" then
        FT.ShowSupport()
    elseif cmd == "github" or cmd == "git" then
        FT.ShowGitHub()
    elseif cmd == "stop" then
        FT.Scanner.Stop("user")
    else
        FT.Print("/ft — " .. L["open / close"])
        FT.Print("/ft market | craft | signals | portfolio | settings")
        FT.Print("/ft scan — " .. L["full scan"] .. ",  /ft scan mine — " .. L["My items"] .. ",  /ft stop")
        FT.Print("/ft lang ru | en | auto,  /ft reset,  /ft github,  /ft support")
    end
end
