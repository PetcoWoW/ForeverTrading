-- Wolf of Booty Bay: the prices companion, from the game's side. The companion (a small Windows app by the clock,
-- silent) checks for new prices every 15 minutes and saves them into the addon folder; it also leaves a note,
-- Data\Companion.lua, of when it last checked. The game reads files only at login or /reload, so the addon can't
-- see a download - but with the note it knows the companion is running, and the price robot publishes hourly: an
-- hour and a quarter after the prices it loaded were published, newer ones are on disk. Then, and only then:
-- one chat line when you open the auction house ("[Load them]" reloads), and the API chip says so.
-- With no companion: once ever, after a real auction house visit, one line on where to get it.
local ADDON, FT = ...
local L = FT.L

local C = {}
FT.Companion = C

C.URL = "https://github.com/PetcoWoW/ForeverTrading/releases/download/companion/WolfPricesSetup.exe"
local CHECK = 15 * 60       -- the companion's check
local HOURLY = 60 * 60      -- the price robot
local loadedAt = time()

function C.Note()
    local n = FT.COMPANION
    if type(n) == "table" and tonumber(n.checked) then return n end
end

-- it had checked within 40 minutes of this login or reload: it's running
function C.Running()
    local n = C.Note()
    return n ~= nil and loadedAt - n.checked < 40 * 60
end

-- newer prices should be waiting on disk: the companion runs, the robot has published since the loaded prices (an
-- hour after them, plus the companion's quarter hour to fetch them), and there was a check after this load
function C.FreshReady()
    if not (C.Running() and FT.Feed and FT.Feed.On()) then return false end
    local built = FT.FEED and tonumber(FT.FEED.built)
    local t = FT.Feed.Time()
    if not (built and t) then return false end
    local now = time()
    return now - built > HOURLY + CHECK + 3 * 60 and now - t > HOURLY and now - loadedAt > CHECK + 60
end

---------------------------------------------------------------------------
-- A chat link of ours: [Load them] / [Get it]. The game's own "addon" link type: a click on it is handed to the
-- addon by EventRegistry's "SetItemRef" (nothing of the game's is replaced). A client without it gets the words.
---------------------------------------------------------------------------
local actions = {}
local registered = false
local function Link(action, label, words)
    if not (EventRegistry and EventRegistry.RegisterCallback) then return words end
    if not registered then
        registered = true
        EventRegistry:RegisterCallback("SetItemRef", function(_, link)
            local a = type(link) == "string" and link:match("^addon:WolfOfBootyBay:(%w+)")
            if a and actions[a] then actions[a]() end
        end, C)
    end
    return "|cffffd100|Haddon:WolfOfBootyBay:" .. action .. "|h[" .. label .. "]|h|r"
end

actions.reload = function() ReloadUI() end
actions.get = function()
    FT.ShowLink(L["Wolf prices companion (Windows)"], C.Pitch(), C.URL)
end

function C.Pitch()
    return L["A small app by the clock. Every 15 minutes it puts the newest prices in your addon folder, without a sound or a pop-up; the addon tells you in chat when there are newer ones to load. Download, run it, done:"]
end

local function Quiet()
    if InCombatLockdown and InCombatLockdown() then return true end
    if IsInInstance then
        local inside = IsInInstance()
        if inside then return true end
    end
    return false
end

-- at the auction house: newer prices are waiting (at most once a visit, and 20 minutes apart)
local saidAt = 0
FT.On("AUCTION_HOUSE_SHOW", function()
    C_Timer.After(2, function()
        if not C.FreshReady() or Quiet() or GetTime() - saidAt < 20 * 60 then return end
        saidAt = GetTime()
        FT.Print(string.format(L["Newer prices should be waiting (yours are from %s). %s"],
            FT.TimeOfDay(FT.Feed.Time()), Link("reload", L["Load them"], L["/reload loads them."])))
    end)
end)

-- no companion: once ever, after a real visit
local openedAt
FT.On("AUCTION_HOUSE_SHOW", function() openedAt = GetTime() end)
FT.On("AUCTION_HOUSE_CLOSED", function()
    if not FT.db or not openedAt or GetTime() - openedAt < 45 then return end
    openedAt = nil
    if C.Note() then FT.db.companionSeen = true end
    if FT.db.companionSeen or FT.db.companionHint or not (FT.Feed and FT.Feed.On()) then return end
    FT.db.companionHint = true
    C_Timer.After(10, function()
        FT.Print(string.format(L["Fresh prices every hour, without updating anything: the Wolf prices companion (Windows). %s"],
            Link("get", L["Get it"], L["Settings > About > Prices companion."])))
    end)
end)
FT.On("FT_LOGIN", function() if C.Note() and FT.db then FT.db.companionSeen = true end end)
