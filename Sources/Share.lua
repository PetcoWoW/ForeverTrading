-- Wolf: price exchange between Wolf users of a guild or a group.
-- When your prices of the whole market are more than an hour old (or you press Exchange), the guild (then the
-- group) is asked who has fresher ones. Those who have offer them; the freshest is picked and sends its last
-- full scan in the background: hidden addon messages, paused in a fight. The game lets each prefix send about
-- one message a second (LayerSwap's measurements on Forever), so a transfer goes on up to three prefixes at once
-- ("lanes": three messages a second, some 750 bytes - within the 800 a second addon libraries hold safe from the
-- server's flood limit) when both sides know them; 1.1.1 knows only the first. Everyone listening whose prices
-- are older takes them in too, and can pass them on later.
-- The live Forever realms restrict what an addon may send (C_ChatInfo.AreOutgoingAddonChatMessagesRestricted:
-- LayerSwap's author found its messages in a chat channel refused there; a hidden whisper is the one message
-- they surely carry). So when the guild and the group bring nothing, the same question goes as hidden whispers:
-- to the group, to Wolf users met before who are online in the guild and, when you pressed
-- Exchange, to the rest of the guild online. The answer and the transfer then go by whisper too.
--   Q  ask:    "Q", proto, side, the time of our newest market prices, "m" when you pressed Exchange, lanes
--   O  offer:  "O", proto, side, the time of theirs, how many items
--   N  no:     "N", proto, side, the asker, why, the time of theirs: said only to a pressed Exchange, so that
--              it can tell who is there and why nothing came ("old", "same", "off", "busy")
--   P  pick:   "P", proto, the name picked, its time, the lanes the asker takes
--   B  begin:  "B", proto, side, time, items, lanes   D  data: "D", n, "item,price,listed,age;..." (on any lane)
--   C  begin, compact: as B, its data in   Z  data: "Z", n, numbers in printable characters (on any lane)
--              when the asker's pick says it reads them (format "2", since 1.1.4: about half the messages)
--   E  end:    "E", messages, items                K  still here (the sender is in a fight)
--   T  test:   "T", proto, a token, the compact characters: /wolf share test sends it to itself every way it can and
--              sees which come back (and whether every character comes back as it was)
-- A channel here is "GUILD", "PARTY", "RAID" or "W:<name>": a hidden whisper to that player.
-- Times go over the wire as server time: players' clocks differ.
local ADDON, FT = ...
local L = FT.L

local X = {}
FT.Share = X

local PREFIX = "WOLFBBD"
-- the lanes of a transfer: their prefixes (the first is PREFIX: everything else goes on it); how many are used
-- at most - the one number to turn down should the server ever take it for flooding
local LANE_PREFIX = { PREFIX, "WOLFBBD2", "WOLFBBD3" }
local LANES = 3
local LANE_OF = {}
for i, p in ipairs(LANE_PREFIX) do LANE_OF[p] = i end
local PROTO = "1"
local AUTO_EVERY = 3600       -- ask by itself when the prices are older than this, at most this often
local NEWER_BY = 1200         -- an offer counts when it is at least 20 minutes newer than ours
local MAX_AGE = 3 * 86400     -- older scans aren't offered or taken (a day was too little: one who scans
                              -- every other day had nothing to give to one who has no prices at all)
local WINDOW = 3 * 3600       -- what is sent: the prices seen in the 3 hours up to the scan, and since
local OFFER_WAIT = 4          -- seconds the asker listens for offers
local PICK_WAIT = 12          -- seconds the one picked has to begin
local SEND_EVERY = 1.0        -- one message a second
local IDLE_TIMEOUT = 90       -- a transfer silent this long is over
local STREAM_GAP = 300        -- we send to the same channel at most once in 5 minutes
local MAX_ITEMS = 8000
local MSG_MAX = 245           -- an addon message holds 255 characters
local MAX_PRICE = 1e10        -- a million gold
local WHISPER_BURST = 8       -- the game lets about 10 messages of an addon out at once, then about one a second
local WHISPER_GAP = 1.1
local WHISPER_MAX = 25        -- players whispered when you press Exchange
local WHISPER_AUTO = 6        -- by itself: only the group and Wolf users met before
local PEER_DAYS = 60          -- a Wolf user not heard from for this long is forgotten

local ask        -- { channels, i, channel, offers, picked, manual, round, replies, sentAny, heardBroadcast }
local offer      -- { channel, t, count, beaten }: our offer, said after a short random wait
local out        -- what we send: { channel, t, list, i, seq, fails, ticker }
local streams = {} -- sender -> { t, count, got, taken, value, lastAt, from, manual }
local lastAuto = 0
local round = 0       -- each ask of a channel gets its own number: old timers can't touch a newer ask
local lastStream = {} -- channel -> time we last sent our scan to it
local test            -- /wolf share test running: { token, sent = { keys }, heard = { key = true } }

local function Enc(n) return FT.Hist.Enc(n) end
local function Dec(s) return FT.Hist.Dec(s) end

---------------------------------------------------------------------------
-- The compact data (format "2"): numbers in printable characters with no separators. Of the 92 printable ones
-- (no tab - it parts the fields - no "|" nor "\") half end a number and the other half come before its last digit:
-- under 46 a number takes one character, under 2116 two, under 97 336 three, under 4.5 million four.
-- An item: its id (in a message the items go by id: after the first only the step up from the one before), its
-- price, listed x 2 (+1: an age follows), the age (minutes before the scan).
---------------------------------------------------------------------------
local FORMAT = "2"
local Z_BASE = 46
local Z_MORE, Z_LAST = {}, {}   -- digit -> character
local MORE_OF, LAST_OF = {}, {} -- byte -> digit
local Z_ALL                     -- every character, in order (the test sends them)
do
    local chars = {}
    for b = 33, 126 do
        if b ~= 124 and b ~= 92 then chars[#chars + 1] = string.char(b) end
    end
    for i = 0, Z_BASE - 1 do
        Z_MORE[i], Z_LAST[i] = chars[i + 1], chars[Z_BASE + i + 1]
        MORE_OF[chars[i + 1]:byte()] = i
        LAST_OF[chars[Z_BASE + i + 1]:byte()] = i
    end
    Z_ALL = table.concat(chars)
end

local function ZPut(parts, v)
    v = math.max(0, math.floor(v))
    local low = v % Z_BASE
    v = math.floor(v / Z_BASE)
    local digits = {}
    while v > 0 do
        digits[#digits + 1] = v % Z_BASE
        v = math.floor(v / Z_BASE)
    end
    for i = #digits, 1, -1 do parts[#parts + 1] = Z_MORE[digits[i]] end
    parts[#parts + 1] = Z_LAST[low]
end

-- items list[from .. from + k - 1] ({ id, price, listed, age }) as one message's data
local function ZText(list, from, k)
    local items = {}
    for i = from, from + k - 1 do items[#items + 1] = list[i] end
    table.sort(items, function(a, b) return a[1] < b[1] end)
    local parts, prev = {}, 0
    for _, e in ipairs(items) do
        ZPut(parts, e[1] - prev)
        prev = e[1]
        ZPut(parts, e[2])
        local age = e[4] or 0
        ZPut(parts, (e[3] or 0) * 2 + (age > 0 and 1 or 0))
        if age > 0 then ZPut(parts, age) end
    end
    return table.concat(parts)
end

-- the numbers of a message's data (nil: a character that isn't ours - not this format)
local function ZNumbers(text)
    local out_, acc = {}, 0
    for i = 1, #text do
        local b = text:byte(i)
        local d = MORE_OF[b]
        if d then
            acc = acc * Z_BASE + d
        else
            d = LAST_OF[b]
            if not d then return nil end
            out_[#out_ + 1] = acc * Z_BASE + d
            acc = 0
        end
    end
    return out_
end

-- our clock vs the server's
local function Skew()
    return GetServerTime and (GetServerTime() - time()) or 0
end
local function Wire(t) return t + Skew() end
local function Local(w) return w - Skew() end

-- Names. On Forever a character is "First Surname" and its realms are one world: chat writes a sender as
-- "First Surname-Realm", and a whisper wants "First Surname" (it reads whatever follows a "-" as the surname).
local function Short(name)
    return type(name) == "string" and (name:gsub("%-.*$", "")) or ""
end

local function NameSep()
    local c = Constants and Constants.CharacterNameSeparatorConsts
    local sep = c and c.CHARACTERNAME_SURNAME_SEPARATOR
    return (type(sep) == "string" and sep ~= "") and sep or " "
end

-- a unit's name as chat writes it: UnitName gives the player's two parts at once, anyone else's apart
local function UnitFull(unit)
    local ok, name = pcall(function()
        local first, second = UnitName(unit)
        if type(first) ~= "string" or first == "" then return nil end
        if type(second) == "string" and second ~= "" then return first .. NameSep() .. second end
        return first
    end)
    return ok and name or nil
end

local me -- our own name as chat writes it
local function FindMe()
    me = UnitFull("player")
    -- the guild roster writes it the way chat does (should UnitName leave the surname out)
    if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo and UnitGUID then
        local guid = UnitGUID("player")
        for i = 1, GetNumGuildMembers() do
            local row = { GetGuildRosterInfo(i) }
            if row[1] and row[17] == guid then
                me = Short(row[1])
                break
            end
        end
    end
end

local function MyName()
    if not me then FindMe() end
    return me or UnitName("player")
end

local function IsMe(name)
    local s = Short(name)
    return s ~= "" and (s == MyName() or s == UnitName("player"))
end

local function Fighting()
    return InCombatLockdown and InCombatLockdown()
end

local function GroupChannel()
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return nil
end

local function Channels()
    local out_ = {}
    if IsInGuild and IsInGuild() then out_[#out_ + 1] = "GUILD" end
    local g = GroupChannel()
    if g then out_[#out_ + 1] = g end
    return out_
end

local function IsWhisper(channel)
    return type(channel) == "string" and channel:sub(1, 2) == "W:"
end

local whispered = {} -- name -> GetTime(): our hidden whispers (the game's "no such player" for them is ours)

-- sent or not, and the game's answer when not
local function SendOn(lane, channel, ...)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false, "no API" end
    local kind, target = channel, nil
    if IsWhisper(channel) then
        kind, target = "WHISPER", channel:sub(3)
        whispered[target] = GetTime()
    end
    local prefix = LANE_PREFIX[lane] or PREFIX
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, prefix, table.concat({ ... }, "\t"), kind, target)
    if not ok or res == false then return false, res end
    -- newer clients answer with a result code: Success (0) is "sent"
    local success = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success or 0
    if type(res) == "number" and res ~= success then return false, res end
    return true
end

local function Send(channel, ...)
    return SendOn(1, channel, ...)
end

-- after a short random wait (so that a guild's answers don't all come at once)
local function Soon(fn)
    C_Timer.After(0.3 + math.random() * 1.7, fn)
end

local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- the transfer coming in (one is enough to know one is)
function X.Receiving()
    local _, st = next(streams)
    return st
end

-- what the exchange is doing for the header: "ask" / "receive" / "send", how far (0-1), with whom
function X.Status()
    local st = X.Receiving()
    if st then return "receive", st.count > 0 and math.min(1, st.got / st.count) or 0, st.from end
    if out then return "send", #out.list > 0 and math.min(1, (out.i - 1) / #out.list) or 0 end
    if ask then return "ask", 0 end
    return nil
end

---------------------------------------------------------------------------
-- Who can be whispered
---------------------------------------------------------------------------
-- Wolf users heard before (this server and side): short name -> { n = full name, t = when }
local function Peers()
    local r = FT.Side()
    r.peers = r.peers or {}
    return r.peers
end

-- a Wolf user heard (anything of ours, or its version)
function X.Met(sender)
    local key = Short(sender)
    if not FT.db or key == "" or IsMe(sender) then return end
    local p = Peers()[key]
    if p then
        p.n, p.t = key, time()
    else
        Peers()[key] = { n = key, t = time() }
    end
end

local function AskRoster()
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        pcall(C_GuildInfo.GuildRoster)
    elseif GuildRoster then
        pcall(GuildRoster)
    end
end

-- the group, then Wolf users met before who are online in the guild, then (asked by hand)
-- the rest of the guild online
local function WhisperTargets(manual)
    local list, seen = {}, {}
    local function Add(full)
        if type(full) ~= "string" or full == "" then return end
        local key = Short(full)
        if seen[key] or IsMe(full) then return end
        seen[key] = true
        list[#list + 1] = full
    end
    local raid = IsInRaid and IsInRaid()
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    for i = 1, n do
        local unit = (raid and "raid" or "party") .. i
        if UnitExists(unit) and UnitIsConnected(unit) then Add(UnitFull(unit)) end
    end
    local online = {}
    if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
        for i = 1, GetNumGuildMembers() do
            local name, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
            if name and isOnline then online[#online + 1] = Short(name) end
        end
    end
    local peers = Peers()
    for _, name in ipairs(online) do
        if peers[Short(name)] then Add(name) end
    end
    if manual then
        for _, name in ipairs(online) do Add(name) end
    end
    local cap = manual and WHISPER_MAX or WHISPER_AUTO
    while #list > cap do table.remove(list) end
    return list
end

---------------------------------------------------------------------------
-- Asking
---------------------------------------------------------------------------
local NextChannel

-- an answer that belongs to the ask going on (a whisper ask hears each player on its own whisper)
local function Asking(channel)
    if not (ask and channel) then return false end
    if ask.channel == channel then return true end
    return ask.channel == "W" and IsWhisper(channel)
end

-- a pressed Exchange that brought nothing: who answered and why they had nothing to give
local function Report(a)
    local names = {}
    for name in pairs(a.replies) do names[#names + 1] = name end
    table.sort(names)
    if #names == 0 then
        if not a.sentAny then
            FT.Print(L["The game didn't let the question out (it holds addon messages back for a while): try again in a minute."])
        else
            FT.Print(L["No Wolf user in your guild or group answered: they have to be in the game right now, in your guild or group, on your server and side. (An older Wolf stays silent when it has nothing to give: ask them to update it.)"])
        end
        return
    end
    FT.Print(L["Nobody in your guild or group has fresher prices right now."])
    for i = 1, math.min(#names, 6) do
        local name, r = names[i], a.replies[names[i]]
        local text
        if r.why == "old" and (r.t or 0) <= 0 then
            text = L["hasn't scanned the whole auction house yet"]
        elseif r.why == "old" then
            text = string.format(L["their last scan is too old to pass on (%s, older than 3 days)"], FT.Ago(r.t))
        elseif r.why == "same" then
            text = string.format(L["their scan (%s) isn't fresher than your prices"], FT.Ago(r.t))
        elseif r.why == "off" then
            text = L["has Share my scans turned off"]
        elseif r.why == "nostart" then
            text = L["offered its prices but didn't begin sending: try again in a few minutes"]
        else
            text = L["busy (sending prices or in a fight): try again in a few minutes"]
        end
        FT.Print("  " .. name .. ": " .. text)
    end
end

local function Pick(r)
    if not ask or ask.round ~= r or ask.picked then return end
    local best
    for _, o in pairs(ask.offers) do
        if not best or o.t > best.t or (o.t == best.t and (o.count > best.count or (o.count == best.count and o.name < best.name))) then
            best = o
        end
    end
    FT.Debug("share: offers on", ask.channel, "-", Count(ask.offers), best and ("picked " .. best.name) or "none")
    if not best then return NextChannel() end
    ask.picked = best.name
    -- the lanes we take and the data format we read (1.1.3 and older send the old one: they don't know it)
    Send(best.channel, "P", PROTO, best.name, Enc(best.wire), tostring(LANES), FT.db.shareOldFormat and "1" or FORMAT)
    -- they don't begin: the next channel
    C_Timer.After(PICK_WAIT, function()
        if ask and ask.round == r and ask.picked then
            FT.Debug("share:", ask.picked, "didn't begin")
            ask.replies[Short(ask.picked)] = { why = "nostart" }
            NextChannel()
        end
    end)
end

-- the question itself (the same on every way)
local function Question(channel)
    local have = FT.Hist.MarketTime()
    local ok, code = Send(channel, "Q", PROTO, FT.houseKey or "", Enc(have > 0 and Wire(have) or 0), ask.manual and "m" or "-",
        tostring(LANES))
    if ok then ask.sentAny = true end
    return ok, code, have
end

-- the question as hidden whispers: a burst, then one a second. The answers of the first burst are looked at
-- once they are in (those asked first are the likeliest to have the addon), everyone's after the last.
local function WhisperRound()
    local targets = WhisperTargets(ask.manual)
    FT.Debug("share: asking by whisper:", #targets > 0 and table.concat(targets, ", ") or "nobody to whisper")
    if #targets == 0 then return NextChannel() end
    local r = ask.round
    for i, name in ipairs(targets) do
        local delay = i <= WHISPER_BURST and 0 or (i - WHISPER_BURST) * WHISPER_GAP
        C_Timer.After(delay, function()
            if not (ask and ask.round == r and not ask.picked) then return end
            local ok, code = Question("W:" .. name)
            if not ok then FT.Debug("share: whisper to", name, "not sent:", tostring(code)) end
        end)
    end
    C_Timer.After(OFFER_WAIT, function()
        if ask and ask.round == r and next(ask.offers) then Pick(r) end
    end)
    C_Timer.After(math.max(0, #targets - WHISPER_BURST) * WHISPER_GAP + OFFER_WAIT, function() Pick(r) end)
end

NextChannel = function()
    if not ask then return end
    ask.i = ask.i + 1
    round = round + 1
    ask.round = round
    local ch = ask.channels[ask.i]
    if not ch then
        if ask.manual then Report(ask) end
        ask = nil
        return
    end
    -- someone answered in the guild or the group: those ways work here, and everyone there has heard us
    if ch == "W" and ask.heardBroadcast then return NextChannel() end
    ask.channel, ask.offers, ask.picked = ch, {}, nil
    if ch == "W" then return WhisperRound() end
    local ok, code, have = Question(ch)
    FT.Debug("share: asking on", ch, "- ours:", FT.Ago(have), ok and "- sent" or ("- not sent: " .. tostring(code)))
    if not ok then return NextChannel() end
    local r = ask.round
    C_Timer.After(OFFER_WAIT, function() Pick(r) end)
end

-- ask guild, then group, then by whisper; manual: said in chat how it went
function X.Ask(manual)
    if ask or out or X.Receiving() then
        if manual then FT.Print(L["The price exchange is already running."]) end
        return false
    end
    local channels = Channels()
    if #channels == 0 then
        if manual then FT.Print(L["The price exchange needs a guild or a group with other Wolf users."]) end
        return false
    end
    AskRoster()
    if manual then FT.Print(L["Asking Wolf users in your guild and group for fresher prices..."]) end
    channels[#channels + 1] = "W"
    ask = { channels = channels, i = 0, manual = manual, replies = {} }
    NextChannel()
    return true
end

---------------------------------------------------------------------------
-- Answering and sending
---------------------------------------------------------------------------
local function Fresh(t)
    return t and t > 0 and time() - t <= MAX_AGE
end

local function OnAsk(channel, sender, side, haveWire, flags)
    if side ~= FT.houseKey then
        FT.Debug("share:", Short(sender), "asks for another server or side:", side, "(ours:", tostring(FT.houseKey) .. ")")
        return
    end
    local mine = FT.Hist.MarketTime()
    -- nothing to give: said in debug, and to the asker when they pressed Exchange
    local function No(why)
        FT.Debug("share:", Short(sender), "asks on", channel, "- ours:", FT.Ago(mine), "- not offered:", why)
        if flags ~= "m" then return end
        Soon(function()
            Send(channel, "N", PROTO, FT.houseKey, sender, why, mine > 0 and Enc(Wire(mine)) or "0")
        end)
    end
    if not FT.S.shareSend then return No("off") end
    if out or offer or Fighting() or (lastStream[channel] and time() - lastStream[channel] < STREAM_GAP) then
        return No("busy")
    end
    if not Fresh(mine) then return No("old") end
    local have = Local(Dec(haveWire) or 0)
    if mine < have + NEWER_BY then return No("same") end
    local n = 0
    FT.Hist.EachSince(mine - WINDOW, function() n = n + 1 end)
    if n == 0 then return No("old") end
    FT.Debug("share:", Short(sender), "asks on", channel, "- offering", n, "prices of", FT.Ago(mine))
    offer = { channel = channel, t = mine, count = math.min(n, MAX_ITEMS) }
    -- a short random wait: someone with fresher prices may speak first
    Soon(function()
        local o = offer
        offer = nil
        if o and not o.beaten and not out then
            local ok, code = Send(o.channel, "O", PROTO, FT.houseKey, Enc(Wire(o.t)), Enc(o.count))
            if not ok then FT.Debug("share: offer not sent:", tostring(code)) end
        end
    end)
end

local function OnOffer(channel, sender, side, tWire, countText)
    if side ~= FT.houseKey then return end
    local w = Dec(tWire)
    if not w then return end
    local t = Local(w)
    FT.Debug("share: offer from", Short(sender), "on", channel, "-", FT.Ago(t), Dec(countText) or 0, "prices")
    -- someone offers the same or fresher: ours isn't needed
    if offer and offer.channel == channel and t >= offer.t - 60 then offer.beaten = true end
    if Asking(channel) and not IsWhisper(channel) then ask.heardBroadcast = true end
    if Asking(channel) and not ask.picked and Fresh(t) then
        ask.offers[sender] = { name = sender, t = t, wire = w, count = Dec(countText) or 0, channel = channel }
    end
end

-- someone has nothing to give us (we pressed Exchange): why, for the report
local function OnNo(channel, sender, side, target, why, tWire)
    if not (ask and ask.manual) or side ~= FT.houseKey or not IsMe(target) then return end
    local w = Dec(tWire) or 0
    FT.Debug("share:", Short(sender), "has nothing to give:", why)
    if not IsWhisper(channel) then ask.heardBroadcast = true end
    ask.replies[Short(sender)] = { why = why, t = w > 0 and Local(w) or 0 }
end

local function ItemText(e)
    local s = Enc(e[1]) .. "," .. Enc(e[2]) .. "," .. (e[3] > 0 and Enc(e[3]) or "")
    if e[4] > 0 then s = s .. "," .. Enc(e[4]) end
    return s
end

local function StopSending()
    if out and out.ticker then out.ticker:Cancel() end
    out = nil
end

-- the next message's data, from item o.i on: its text, and the item after its last
local function NextData(o)
    local head = 2 + #Enc(o.seq + 1) + 1
    if o.dense then
        -- as many items as fit (one more never makes the text shorter)
        local lo, hi, best, text = 1, math.min(#o.list - o.i + 1, 120), 0, nil
        while lo <= hi do
            local mid = math.floor((lo + hi) / 2)
            local t = ZText(o.list, o.i, mid)
            if head + #t <= MSG_MAX then
                best, text, lo = mid, t, mid + 1
            else
                hi = mid - 1
            end
        end
        if best == 0 then best, text = 1, ZText(o.list, o.i, 1) end
        return text, o.i + best
    end
    local parts, len, k = {}, head, o.i
    while k <= #o.list do
        local s = ItemText(o.list[k])
        if len + #s + 1 > MSG_MAX then break end
        parts[#parts + 1] = s
        len = len + #s + 1
        k = k + 1
    end
    return table.concat(parts, ";"), k
end

local function SendStep()
    local o = out
    if not o then return end
    if Fighting() then
        -- paused: the listeners hear we are still here now and then
        if GetTime() - (o.keptAt or 0) > 30 then
            o.keptAt = GetTime()
            Send(o.channel, "K")
        end
        return
    end
    -- all sent (the last ones a second ago, on every lane): the end, on the first
    if o.i > #o.list then
        Send(o.channel, "E", Enc(o.seq), Enc(#o.list))
        return StopSending()
    end
    for lane = 1, o.lanes or 1 do
        if o.i > #o.list then break end
        local text, k = NextData(o)
        if SendOn(lane, o.channel, o.dense and "Z" or "D", Enc(o.seq + 1), text) then
            o.seq, o.i, o.fails = o.seq + 1, k, 0
        else
            -- left the guild or the group, or the game holds messages back: try again, give up after a while
            o.fails = o.fails + 1
            if o.fails >= 20 then StopSending() end
            return
        end
    end
end

-- dense: the compact data (the asker reads it)
local function StartSending(channel, lanes, dense)
    lanes = math.max(1, math.min(LANES, lanes or 1))
    local mine = FT.Hist.MarketTime()
    if not Fresh(mine) then return end
    local list = {}
    FT.Hist.EachSince(mine - WINDOW, function(id, p, q, t)
        if p and p > 0 and p < MAX_PRICE then
            list[#list + 1] = { id, math.floor(p + 0.5), math.floor(q or 0), math.max(0, math.floor((mine - t) / 60)) }
        end
    end)
    if #list == 0 then return end
    -- the most valuable listings first: a transfer cut short still has what matters most
    table.sort(list, function(a, b) return a[2] * math.max(1, a[3]) > b[2] * math.max(1, b[3]) end)
    while #list > MAX_ITEMS do table.remove(list) end
    lastStream[channel] = time()
    local ok, code = Send(channel, dense and "C" or "B", PROTO, FT.houseKey, Enc(Wire(mine)), Enc(#list), tostring(lanes))
    FT.Debug("share: sending", #list, "prices on", channel, "-", lanes, "lanes", dense and "compact" or "",
        ok and "" or ("- not sent: " .. tostring(code)))
    if not ok then return end
    out = { channel = channel, t = mine, list = list, i = 1, seq = 0, fails = 0, lanes = lanes, dense = dense }
    out.ticker = C_Timer.NewTicker(SEND_EVERY, SendStep)
end

-- picked: as many lanes as the asker takes (none said: 1.1.1, one), compact when it reads that (since 1.1.4)
local function OnPick(channel, target, lanesText, formatText)
    if not IsMe(target) then return end
    if out or not FT.S.shareSend then return end
    if lastStream[channel] and time() - lastStream[channel] < STREAM_GAP then
        FT.Debug("share: picked on", channel, "- sent there less than 5 minutes ago")
        return
    end
    StartSending(channel, tonumber(lanesText) or 1, formatText == FORMAT)
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
-- a price far away from what we know is a mistake (or a joke): left out
local function Plausible(id, p)
    local own, _, source = FT.Price(id)
    if not own or own <= 0 or source == "peer" then return true end
    return p < own * 50 and p > own / 50
end

-- a scan of our own running: the freshest prices are on their way here
local function Scanning()
    return FT.scanning or FT.atrScanning or (FT.Scanner and FT.Scanner.mode ~= nil)
end

-- dense: its data comes compact ("C" began it)
local function OnBegin(channel, sender, side, tWire, countText, dense)
    if side ~= FT.houseKey or streams[sender] then return end
    if Scanning() then
        FT.Debug("share:", Short(sender), "begins - not taken: our own scan runs")
        return
    end
    local w, count = Dec(tWire), Dec(countText) or 0
    if not w or count <= 0 or count > MAX_ITEMS then return end
    local t = math.min(Local(w), time())
    if not Fresh(t) then return end
    -- the one we picked begins: asking is over
    local manual = false
    if Asking(channel) and Short(ask.picked) == Short(sender) then
        manual = ask.manual
        ask = nil
    end
    -- not fresher than ours: nothing to take
    if t < FT.Hist.MarketTime() + NEWER_BY or Count(streams) >= 2 then
        if manual then FT.Print(L["Nobody in your guild or group has fresher prices right now."]) end
        return
    end
    FT.Debug("share: receiving", count, "prices from", Short(sender), "-", FT.Ago(t))
    streams[sender] = { t = t, count = count, got = 0, taken = 0, value = 0, lastAt = GetTime(), shownAt = GetTime(),
        from = Short(sender), dense = dense }
    if manual then FT.Print(string.format(L["Receiving prices from %s (their scan: %s)..."], Short(sender), FT.Ago(t))) end
end

-- one price of a transfer: item, price, listed (nil: not known), age (minutes before their scan)
local function Take(st, id, p, q, age)
    if not (id and p and id > 0 and id < 10000000 and p > 0 and p < MAX_PRICE) then return end
    st.got = st.got + 1
    if q and (q <= 0 or q > 1000000) then q = nil end
    local t = st.t - math.min(age or 0, WINDOW / 60) * 60
    if Plausible(id, p) then
        FT.Hist.Observe(id, p, q, nil, t, "peer")
        st.taken = st.taken + 1
        st.value = st.value + p * (q or 0)
    end
end

-- a long transfer: the pages catch up once a minute (not on every message)
local function Shown(st)
    if GetTime() - st.shownAt > 60 then
        st.shownAt = GetTime()
        FT.Fire("FT_PRICES_CHANGED", "peer")
    end
end

local function OnData(sender, payload)
    local st = streams[sender]
    if not st or st.dense or type(payload) ~= "string" then return end
    st.lastAt = GetTime()
    for rec in payload:gmatch("[^;]+") do
        if st.got >= st.count then break end
        local a, b, c, d = rec:match("^(%w+),(%w+),(%w*),?(%w*)$")
        Take(st, Dec(a), Dec(b), Dec(c), Dec(d))
    end
    Shown(st)
end

-- the compact data: item (the step up from the one before), price, listed x 2 (+1: an age follows), age
local function OnDense(sender, payload)
    local st = streams[sender]
    if not (st and st.dense) or type(payload) ~= "string" then return end
    st.lastAt = GetTime()
    local v = ZNumbers(payload)
    if not v then
        -- the way changes characters: this transfer brings nothing - from now on the old data is asked for
        streams[sender] = nil
        FT.db.shareOldFormat = true
        FT.Print(L["The exchange: the compact data came changed on the way. From now on the old format is asked for - press Exchange again."])
        return
    end
    local k, prev = 1, 0
    while v[k + 2] and st.got < st.count do
        local id, p, x = prev + v[k], v[k + 1], v[k + 2]
        k = k + 3
        local age = 0
        if x % 2 == 1 then
            age = v[k] or 0
            k = k + 1
        end
        prev = id
        Take(st, id, p, math.floor(x / 2), age)
    end
    Shown(st)
end

local function Finish(sender, complete)
    local st = streams[sender]
    if not st then return end
    streams[sender] = nil
    if st.taken == 0 then return end
    -- the whole scan came: it counts as one of the market's (the next hourly ask waits for it)
    if complete or st.got >= st.count * 0.9 then
        FT.Hist.MarkScan("peer", st.t)
        local meta = FT.R().meta
        meta.lastPeerFrom = st.from
        if not FT.Hist.HasScan(st.t) then
            FT.Hist.LogScan({ t = st.t, items = st.got, value = st.value, source = "peer", summary = true })
        end
    end
    FT.Print(string.format(L["Received %s prices from %s (their scan: %s)."], FT.Num(st.taken), st.from, FT.Ago(st.t)))
    FT.Fire("FT_SCAN_DONE", "peer")
end

-- Exchange pressed while it runs: it stops. Asking ends; what was received stays (it is in the history already),
-- the rest of that transfer is let go; sending ends (those receiving keep what came - a part, never taken for a
-- whole scan - once they hear nothing more). Said in chat.
function X.Stop()
    local said
    for sender, st in pairs(streams) do
        streams[sender] = nil
        if st.taken > 0 then
            FT.Fire("FT_SCAN_DONE", "peer")
            said = string.format(L["Exchange stopped: %s prices from %s kept."], FT.Num(st.taken), st.from)
        end
    end
    if out then
        if out.ticker then out.ticker:Cancel() end
        out = nil
        said = said or L["Exchange stopped: no more of your prices are sent."]
    end
    if ask or offer then
        ask, offer = nil, nil
        round = round + 1
    end
    FT.Print(said or L["Exchange stopped."])
end

-- the other auction house: asking, offering, sending and receiving of the last one end (an exchange is of one
-- house: its key goes with every message; 1.1.1 knows only the faction's)
FT.On("FT_HOUSE_CHANGED", function()
    if out and out.ticker then out.ticker:Cancel() end
    out, offer, ask = nil, nil, nil
    wipe(streams)
end)

FT.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    local lane = LANE_OF[prefix]
    if not lane or type(text) ~= "string" or not sender then return end
    local kind, a, b, c, d, e = strsplit("\t", text)
    if lane > 1 and kind ~= "D" and kind ~= "Z" then return end
    if IsMe(sender) then
        -- our own test message came back: that way works (and the compact characters came as they went, or not)
        if kind == "T" and test and b == test.token then
            local key = channel == "WHISPER" and "W" or channel
            test.heard[key] = true
            test.chars[key] = (c == Z_ALL)
        end
        return
    end
    if kind == "T" then return end
    X.Met(sender)
    if channel == "WHISPER" then channel = "W:" .. Short(sender) end
    if kind ~= "D" and kind ~= "Z" and kind ~= "K" then FT.Debug("share: heard", kind, "from", Short(sender), "on", channel) end
    if kind == "D" then
        OnData(sender, b)
    elseif kind == "Z" then
        OnDense(sender, b)
    elseif kind == "K" then
        if streams[sender] then streams[sender].lastAt = GetTime() end
    elseif kind == "E" then
        Finish(sender, true)
    elseif a ~= PROTO then
        return -- a newer exchange than ours
    elseif kind == "Q" then
        OnAsk(channel, sender, b, c, d)
    elseif kind == "O" then
        OnOffer(channel, sender, b, c, d)
    elseif kind == "N" then
        OnNo(channel, sender, b, c, d, e)
    elseif kind == "P" then
        OnPick(channel, b, d, e)
    elseif kind == "B" or kind == "C" then
        OnBegin(channel, sender, b, c, d, kind == "C")
    end
end)

---------------------------------------------------------------------------
-- /wolf share test: which ways the game carries our hidden messages here
---------------------------------------------------------------------------
local function WayName(key)
    if key == "GUILD" then return L["guild"] end
    if key == "PARTY" or key == "RAID" then return L["group"] end
    return L["whisper"]
end

function X.Test()
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    local restricted = L["unknown"]
    local f = C_ChatInfo.AreOutgoingAddonChatMessagesRestricted
    if type(f) == "function" then
        -- the answer may be a value an addon can't compare (then it stays "unknown")
        local ok, v = pcall(function()
            local r = f()
            if r == true then return "yes" elseif r == false then return "no" end
        end)
        if ok and v == "yes" then
            restricted = L["yes"]
        elseif ok and v == "no" then
            restricted = L["no"]
        end
    end
    FT.Print(string.format(L["Exchange test: which ways the game carries Wolf's hidden messages (the realm restricts addon messages: %s)..."], restricted))
    FindMe()
    local t = { token = tostring(math.random(100000, 999999)), sent = {}, heard = {}, chars = {}, self = MyName() }
    test = t
    local ways = Channels()
    ways[#ways + 1] = "W:" .. t.self
    for _, ch in ipairs(ways) do
        local key = IsWhisper(ch) and "W" or ch
        local ok, code = Send(ch, "T", PROTO, t.token, Z_ALL)
        if ok then
            t.sent[#t.sent + 1] = key
        else
            FT.Print("  " .. WayName(key) .. ": " .. string.format(L["the game refused to send it (code %s)"], tostring(code)))
        end
    end
    C_Timer.After(3, function()
        if test ~= t then return end
        test = nil
        for _, key in ipairs(t.sent) do
            local text
            if t.heard[key] and t.chars[key] then
                text = L["works"]
                -- the compact data comes through: asked for again (should it have been given up)
                FT.db.shareOldFormat = nil
            elseif t.heard[key] then
                -- the compact data wouldn't come through this way as it went: an exchange with 1.1.4 would bring nothing
                text = L["works, but some characters come changed: the compact exchange can't go this way"]
            elseif key == "W" and t.notFound then
                text = string.format(L["the game found no player named %s"], t.self)
            else
                text = L["sent, but it didn't come back: this way seems not to work here"]
            end
            FT.Print("  " .. WayName(key) .. (key == "W" and (" (" .. t.self .. ")") or "") .. ": " .. text)
        end
    end)
end

-- The game answers a whisper to nobody with "No player named X": for our hidden whispers that goes to debug,
-- not to your chat.
local notFound
if type(ERR_CHAT_PLAYER_NOT_FOUND_S) == "string" then
    local p = ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    notFound = "^" .. p:gsub("%%%%s", "(.+)") .. "$"
end

local function NotFoundFilter(_, _, msg)
    if not notFound or type(msg) ~= "string" then return false end
    local name = msg:match(notFound)
    local at = name and whispered[name]
    if not at or GetTime() - at > 10 then return false end
    if test and test.self == name then test.notFound = true end
    FT.Debug("share: whisper to", name, "- the game says there is no such player")
    return true
end

---------------------------------------------------------------------------
-- By itself: prices older than an hour, at most once an hour
---------------------------------------------------------------------------
local function AutoCheck()
    if not FT.S.shareAuto or ask or out or X.Receiving() or Fighting() or Scanning() then return end
    local now = time()
    if now - FT.Hist.MarketTime() < AUTO_EVERY or now - lastAuto < AUTO_EVERY then return end
    if #Channels() == 0 then return end
    lastAuto = now
    X.Ask(false)
end

-- our own scan of the whole market done: what is coming from others that isn't fresher than it stops (and asking
-- by itself ends) - the prices just read are the freshest there are
FT.On("FT_SCAN_DONE", function(kind)
    if kind == "peer" then return end
    local mine = FT.Hist.MarketTime()
    for sender, st in pairs(streams) do
        if st.t < mine + NEWER_BY then
            streams[sender] = nil
            FT.Debug("share: receiving from", st.from, "ended - our own scan is fresher")
            if st.taken > 0 then FT.Fire("FT_PRICES_CHANGED", "peer") end
        end
    end
    if ask and not ask.manual then
        ask = nil
        round = round + 1
    end
end)

local function Timeouts()
    for sender, st in pairs(streams) do
        if GetTime() - st.lastAt > IDLE_TIMEOUT then Finish(sender, false) end
    end
end

FT.On("FT_LOGIN", function()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        for _, p in ipairs(LANE_PREFIX) do pcall(C_ChatInfo.RegisterAddonMessagePrefix, p) end
    end
end)

-- the guild roster came: our own name as chat writes it is read again
FT.On("GUILD_ROSTER_UPDATE", function() FT.Debounce("shareMe", 2, FindMe) end)

FT.On("FT_READY", function()
    -- users not heard from for a long time are forgotten
    local peers, old = Peers(), time() - PEER_DAYS * 86400
    for key, p in pairs(peers) do
        if type(p) ~= "table" or (p.t or 0) < old then peers[key] = nil end
    end
    AskRoster()
    local filter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
    if filter then pcall(filter, "CHAT_MSG_SYSTEM", NotFoundFilter) end
    C_Timer.After(40, AutoCheck)
    C_Timer.NewTicker(60, AutoCheck)
    C_Timer.NewTicker(5, Timeouts)
end)
