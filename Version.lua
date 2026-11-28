-- Wolf: is there a newer version? An addon can't go online, so guild and group members who use
-- Wolf tell each other which version they have (a hidden addon message): at login and when you join
-- a group - at most once a minute per channel, never in a fight. A newer one than yours: one line in chat a
-- line in chat once per new version (v0.50) and a link in the status bar. Someone with an older version hears yours back, so the news gets round.
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

-- v0.50: told once per new version, then quiet - however it was heard (a guild member, the Wolf network, the price
-- file). FT.db.told.version: the newest version the chat line was said for.
local function MM(v)
    local a, b = tostring(v or ""):match("^v?(%d+)%.(%d+)")
    if not a then return nil end
    return tonumber(a) * 1000 + tonumber(b)
end
function V.Tell(theirs)
    if not (FT.db and theirs) then return false end
    FT.db.told = FT.db.told or {}
    local n, mine = MM(theirs), MM(FT.VERSION)
    if not (n and mine) or n <= mine then return false end
    local was = MM(FT.db.told.version)
    if was and was >= n then return false end
    FT.db.told.version = string.format("%d.%d", math.floor(n / 1000), n % 1000)
    FT.db.told.versionAt = time()
    FT.Print(V.HowToGet(FT.db.told.version))
    return true
end

-- (v0.58) the line for a newer Wolf: the prices companion brings it (a /reload, or a game restart when it has new
-- files), or the CurseForge app / WowUp
function V.HowToGet(v)
    local C = FT.Companion
    if C and C.Updates() then
        if C.Pending() then
            return string.format(L["Wolf v%s is ready: it has new files, so it goes in when you restart the game (the prices companion brings it)."], v)
        end
        return string.format(L["Wolf v%s is ready (the prices companion brought it): %s"], v,
            FT.ChatLink and FT.ChatLink("reload", L["Reload"], "/reload") or "/reload")
    end
    return string.format(L["A newer Wolf is out: v%s (you have %s). Update it in the CurseForge app or WowUp."], v, FT.VERSION_TEXT or FT.VERSION)
end

-- a newer version heard from another Wolf user (this file's version message, or any Wolf network message)
function V.Heard(theirs)
    if not (theirs and V.Newer(theirs, FT.VERSION)) then return end
    if not V.newest or V.Newer(theirs, V.newest) then
        V.newest = theirs
        FT.Fire("FT_NEWER_VERSION", theirs)
    end
    V.Tell(theirs)
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
    -- whoever says its version uses Wolf: the price exchange can whisper them later
    if sender and FT.Share and text:find("^V\t") then FT.Share.Met(sender) end
    if not On() then return end
    local theirs = text:match("^V\t(.+)$")
    if not theirs then return end
    if V.Newer(theirs, FT.VERSION) then
        V.Heard(theirs)
    elseif V.Newer(FT.VERSION, theirs) and sender and not answered[sender] then
        -- they are behind: tell them ours, once
        answered[sender] = true
        -- a whisper wants the name without "-Realm" (on Forever what follows a "-" is read as the surname)
        Say("WHISPER", (sender:gsub("%-.*$", "")))
    end
end)

---------------------------------------------------------------------------
-- The outdated reminder (v0.42): one chat line at login when a newer Wolf is out, or the prices companion is behind -
-- from the price file the companion brings every hour (FT.FEED.release / .companion, written by the release robot).
-- Once per version (v0.50; it was once a day); never a pop-up.
---------------------------------------------------------------------------
local function MajMin(v)
    local a, b = tostring(v or ""):match("^v?(%d+)%.(%d+)")
    return tonumber(a), tonumber(b)
end

-- true when release (MAJ.MIN) is newer than what's installed
function V.ReleaseNewer(release, mine)
    local a1, b1 = MajMin(release)
    local a2, b2 = MajMin(mine)
    if not (a1 and a2) then return false end
    return a1 > a2 or (a1 == a2 and b1 > b2)
end

function V.Remind()
    if not (FT.db and FT.FEED) then return end
    FT.db.told = FT.db.told or {}
    local today = date("%Y%m%d")
    local rel = FT.FEED.release
    if rel and V.ReleaseNewer(rel, FT.VERSION) then V.Tell(rel) end
    local want, have = FT.FEED.companion, FT.COMPANION and FT.COMPANION.version
    if want and have and V.Newer(want, have) and FT.db.told.companion ~= want .. today then
        FT.db.told.companion = want .. today
        FT.Print(string.format(L["The prices companion is behind: %s (you have %s). It updates itself when it starts; or get it again: %s"], want, have,
            FT.ChatLink and FT.ChatLink("get", L["Get it"], "/wolf companion") or "/wolf companion"))
    end
end

-- (v0.57) still on the old one three days after the line: said once more at login, then only the minimap dot
function V.RemindAgain()
    local t = FT.db and FT.db.told
    if not (t and t.version and t.versionAt) then return end
    if not (V.Newest() or (FT.FEED and FT.FEED.release and V.ReleaseNewer(FT.FEED.release, FT.VERSION))) then return end
    if (MM(t.version) or 0) <= (MM(FT.VERSION) or 0) or t.again == t.version or time() - t.versionAt < 3 * 86400 then return end
    t.again = t.version
    if FT.Companion and FT.Companion.Updates() then FT.Print(V.HowToGet(t.version)) return end
    FT.Print(string.format(L["Still on %s: v%s is out. Update it in the CurseForge app or WowUp (Wolf's prices and pages are made for the newest)."],
        FT.VERSION_TEXT or FT.VERSION, t.version))
end

-- (v0.58) the prices companion put this version in: one line, once a version
function V.SelfUpdated()
    local n = FT.Companion and FT.Companion.Note()
    if not (FT.db and n and n.updated) then return end
    local mine = MM(FT.VERSION)
    if not mine or MM(n.updated) ~= mine then return end
    FT.db.told = FT.db.told or {}
    if FT.db.told.self == mine then return end
    FT.db.told.self = mine
    FT.Print(string.format(L["Wolf %s is in: the prices companion updated it. What's new: %s"], FT.VERSION_TEXT or FT.VERSION,
        FT.ChatLink and FT.ChatLink("news", L["See it"], "/wolf news") or "/wolf news"))
end

-- the newest version known (heard, or the price file's), when newer than ours
function V.Outdated()
    local n = V.Newest()
    local rel = FT.FEED and FT.FEED.release
    if rel and V.ReleaseNewer(rel, FT.VERSION) and not (n and V.Newer(n, rel)) then n = rel end
    return n
end

FT.On("FT_READY", function() C_Timer.After(25, V.Remind); C_Timer.After(40, V.RemindAgain); C_Timer.After(8, V.SelfUpdated) end)
