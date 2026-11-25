-- Wolf of Booty Bay: is there a newer version? An addon can't go online, so guild and group members who use
-- Wolf of Booty Bay tell each other which version they have (a hidden addon message): at login and when you join
-- a group - at most once a minute per channel, never in a fight. A newer one than yours: one line in chat a
-- session and a link in the status bar. Someone with an older version hears yours back, so the news gets round.
local ADDON, FT = ...
local L = FT.L

local V = {}
FT.Ver = V

local PREFIX = "WOLFBBV"
local lastSaid = {}   -- channel -> time we last told it
local answered = {}   -- player -> true: told our version back this session

-- "v1.2.10" -> { 1, 2, 10 }; nil for "dev" and anything that isn't a version
local function Parts(v)
    if type(v) ~= "string" then return nil end
    local a, b, c = v:match("^v?(%d+)%.(%d+)%.?(%d*)")
    if not a then return nil end
    return { tonumber(a), tonumber(b), tonumber(c) or 0 }
end

-- true when version a is newer than b
function V.Newer(a, b)
    local x, y = Parts(a), Parts(b)
    if not (x and y) then return false end
    for i = 1, 3 do
        if x[i] ~= y[i] then return x[i] > y[i] end
    end
    return false
end

local function On()
    return FT.S and FT.S.versionCheck ~= false and C_ChatInfo and C_ChatInfo.SendAddonMessage
        and Parts(FT.VERSION) ~= nil
end

local function Say(channel, target)
    if not (channel and On()) then return end
    local key = target or channel
    if lastSaid[key] and time() - lastSaid[key] < 60 then return end
    if InCombatLockdown and InCombatLockdown() then
        FT.Debounce("verAfterFight" .. key, 5, function() Say(channel, target) end)
        return
    end
    lastSaid[key] = time()
    pcall(C_ChatInfo.SendAddonMessage, PREFIX, "V\t" .. FT.VERSION, channel, target)
end

local function GroupChannel()
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return nil
end

local function SayAll()
    if IsInGuild and IsInGuild() then Say("GUILD") end
    Say(GroupChannel())
end

-- the newest version heard this session (nil: none newer than ours)
function V.Newest()
    return V.newest
end

FT.On("FT_LOGIN", function()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    end
end)
FT.On("FT_READY", function() C_Timer.After(10, SayAll) end)
FT.On("GROUP_ROSTER_UPDATE", function() FT.Debounce("verGroup", 5, function() Say(GroupChannel()) end) end)

FT.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    if prefix ~= PREFIX or type(text) ~= "string" then return end
    -- whoever says its version uses Wolf of Booty Bay: the price exchange can whisper them later
    if sender and FT.Share and text:find("^V\t") then FT.Share.Met(sender) end
    if not On() then return end
    local theirs = text:match("^V\t(.+)$")
    if not theirs then return end
    if V.Newer(theirs, FT.VERSION) then
        if not V.newest or V.Newer(theirs, V.newest) then
            V.newest = theirs
            FT.Print(string.format(L["A newer Wolf of Booty Bay is out: %s (you have %s). Get it on CurseForge or GitHub (/wolf github)."],
                theirs, FT.VERSION))
            FT.Fire("FT_NEWER_VERSION", theirs)
        end
    elseif V.Newer(FT.VERSION, theirs) and sender and not answered[sender] then
        -- they are behind: tell them ours, once
        answered[sender] = true
        -- a whisper wants the name without "-Realm" (on Forever what follows a "-" is read as the surname)
        Say("WHISPER", (sender:gsub("%-.*$", "")))
    end
end)
