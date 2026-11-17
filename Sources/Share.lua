-- ForeverTrading: price exchange between ForeverTrading users of a guild or a group.
-- When your prices of the whole market are more than an hour old (or you press Exchange), the guild (then the
-- group) is asked who has fresher ones. Those who have offer them; the freshest is picked and sends its last
-- full scan in the background: hidden addon messages, one a second (far below what the game allows), paused
-- in a fight. Everyone listening whose prices are older takes them in too, and can pass them on later.
--   Q  ask:    "Q", proto, side, the time of our newest market prices
--   O  offer:  "O", proto, side, the time of theirs, how many items
--   P  pick:   "P", proto, the name picked, its time
--   B  begin:  "B", proto, side, time, items          D  data: "D", n, "item,price,listed,age;..."
--   E  end:    "E", messages, items                K  still here (the sender is in a fight)
-- Times go over the wire as server time: players' clocks differ.
local ADDON, FT = ...
local L = FT.L

local X = {}
FT.Share = X

local PREFIX = "FTDATA"
local PROTO = "1"
local AUTO_EVERY = 3600       -- ask by itself when the prices are older than this, at most this often
local NEWER_BY = 1200         -- an offer counts when it is at least 20 minutes newer than ours
local MAX_AGE = 24 * 3600     -- older scans aren't offered or taken
local WINDOW = 3 * 3600       -- what is sent: the prices seen in the 3 hours up to the scan, and since
local OFFER_WAIT = 4          -- seconds the asker listens for offers
local PICK_WAIT = 12          -- seconds the one picked has to begin
local SEND_EVERY = 1.0        -- one message a second
local IDLE_TIMEOUT = 90       -- a transfer silent this long is over
local STREAM_GAP = 300        -- we send to the same channel at most once in 5 minutes
local MAX_ITEMS = 8000
local MSG_MAX = 245           -- an addon message holds 255 characters
local MAX_PRICE = 1e10        -- a million gold

local ask        -- { channels, i, channel, offers, picked, manual, round }
local offer      -- { channel, t, count, beaten }: our offer, said after a short random wait
local out        -- what we send: { channel, t, list, i, seq, fails, ticker }
local streams = {} -- sender -> { t, count, got, taken, value, lastAt, from, manual }
local lastAuto = 0
local round = 0       -- each ask of a channel gets its own number: old timers can't touch a newer ask
local lastStream = {} -- channel -> time we last sent our scan to it

local function Enc(n) return FT.Hist.Enc(n) end
local function Dec(s) return FT.Hist.Dec(s) end

-- our clock vs the server's
local function Skew()
    return GetServerTime and (GetServerTime() - time()) or 0
end
local function Wire(t) return t + Skew() end
local function Local(w) return w - Skew() end

local function Short(name)
    return type(name) == "string" and (name:gsub("%-.*$", "")) or ""
end

local function IsMe(name)
    return Short(name) == UnitName("player")
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

local function Send(channel, ...)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false end
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, table.concat({ ... }, "\t"), channel)
    if not ok or res == false then return false end
    -- newer clients answer with a result code: 0 is "sent"
    if type(res) == "number" and res ~= 0 then return false end
    return true
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
-- Asking
---------------------------------------------------------------------------
local NextChannel

local function Pick(round)
    if not ask or ask.round ~= round or ask.picked then return end
    local best
    for _, o in pairs(ask.offers) do
        if not best or o.t > best.t or (o.t == best.t and (o.count > best.count or (o.count == best.count and o.name < best.name))) then
            best = o
        end
    end
    if not best then return NextChannel() end
    ask.picked = best.name
    Send(ask.channel, "P", PROTO, best.name, Enc(best.wire))
    -- they don't begin: the next channel
    C_Timer.After(PICK_WAIT, function()
        if ask and ask.round == round and ask.picked then NextChannel() end
    end)
end

NextChannel = function()
    if not ask then return end
    ask.i = ask.i + 1
    round = round + 1
    ask.round = round
    local ch = ask.channels[ask.i]
    if not ch then
        if ask.manual then FT.Print(L["Nobody in your guild or group has fresher prices right now."]) end
        ask = nil
        return
    end
    ask.channel, ask.offers, ask.picked = ch, {}, nil
    if not Send(ch, "Q", PROTO, FT.sideKey or "", Enc(Wire(FT.Hist.MarketTime()))) then return NextChannel() end
    local round = ask.round
    C_Timer.After(OFFER_WAIT, function() Pick(round) end)
end

-- ask guild, then group; manual: said in chat how it went
function X.Ask(manual)
    if ask or out or X.Receiving() then
        if manual then FT.Print(L["The price exchange is already running."]) end
        return false
    end
    local channels = Channels()
    if #channels == 0 then
        if manual then FT.Print(L["The price exchange needs a guild or a group with other ForeverTrading users."]) end
        return false
    end
    if manual then FT.Print(L["Asking ForeverTrading users in your guild and group for fresher prices..."]) end
    ask = { channels = channels, i = 0, manual = manual }
    NextChannel()
    return true
end

---------------------------------------------------------------------------
-- Answering and sending
---------------------------------------------------------------------------
local function Fresh(t)
    return t and t > 0 and time() - t <= MAX_AGE
end

local function OnAsk(channel, side, haveWire)
    if not FT.S.shareSend or out or offer or side ~= FT.sideKey or Fighting() then return end
    if lastStream[channel] and time() - lastStream[channel] < STREAM_GAP then return end
    local mine = FT.Hist.MarketTime()
    if not Fresh(mine) then return end
    local have = Local(Dec(haveWire) or 0)
    if mine < have + NEWER_BY then return end
    local n = 0
    FT.Hist.EachSince(mine - WINDOW, function() n = n + 1 end)
    if n == 0 then return end
    offer = { channel = channel, t = mine, count = math.min(n, MAX_ITEMS) }
    -- a short random wait: someone with fresher prices may speak first
    C_Timer.After(0.3 + math.random() * 1.7, function()
        local o = offer
        offer = nil
        if o and not o.beaten and not out then
            Send(o.channel, "O", PROTO, FT.sideKey, Enc(Wire(o.t)), Enc(o.count))
        end
    end)
end

local function OnOffer(channel, sender, side, tWire, countText)
    if side ~= FT.sideKey then return end
    local w = Dec(tWire)
    if not w then return end
    local t = Local(w)
    -- someone offers the same or fresher: ours isn't needed
    if offer and offer.channel == channel and t >= offer.t - 60 then offer.beaten = true end
    if ask and ask.channel == channel and not ask.picked and Fresh(t) then
        ask.offers[sender] = { name = sender, t = t, wire = w, count = Dec(countText) or 0 }
    end
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
    if o.i > #o.list then
        Send(o.channel, "E", Enc(o.seq), Enc(#o.list))
        return StopSending()
    end
    local head = 2 + #Enc(o.seq + 1) + 1
    local parts, len, k = {}, head, o.i
    while k <= #o.list do
        local s = ItemText(o.list[k])
        if len + #s + 1 > MSG_MAX then break end
        parts[#parts + 1] = s
        len = len + #s + 1
        k = k + 1
    end
    if Send(o.channel, "D", Enc(o.seq + 1), table.concat(parts, ";")) then
        o.seq, o.i, o.fails = o.seq + 1, k, 0
    else
        -- left the guild or the group, or the game holds messages back: try again, give up after a while
        o.fails = o.fails + 1
        if o.fails >= 20 then StopSending() end
    end
end

local function StartSending(channel)
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
    if not Send(channel, "B", PROTO, FT.sideKey, Enc(Wire(mine)), Enc(#list)) then return end
    out = { channel = channel, t = mine, list = list, i = 1, seq = 0, fails = 0 }
    out.ticker = C_Timer.NewTicker(SEND_EVERY, SendStep)
end

local function OnPick(channel, target)
    if out or not FT.S.shareSend or not IsMe(target) then return end
    if lastStream[channel] and time() - lastStream[channel] < STREAM_GAP then return end
    StartSending(channel)
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

local function OnBegin(channel, sender, side, tWire, countText)
    if side ~= FT.sideKey or streams[sender] then return end
    local w, count = Dec(tWire), Dec(countText) or 0
    if not w or count <= 0 or count > MAX_ITEMS then return end
    local t = math.min(Local(w), time())
    if not Fresh(t) then return end
    -- the one we picked begins: asking is over
    local manual = false
    if ask and ask.channel == channel and Short(ask.picked) == Short(sender) then
        manual = ask.manual
        ask = nil
    end
    -- not fresher than ours: nothing to take
    if t < FT.Hist.MarketTime() + NEWER_BY or Count(streams) >= 2 then return end
    streams[sender] = { t = t, count = count, got = 0, taken = 0, value = 0, lastAt = GetTime(), shownAt = GetTime(),
        from = Short(sender) }
    if manual then FT.Print(string.format(L["Receiving prices from %s (their scan: %s)..."], Short(sender), FT.Ago(t))) end
end

local function OnData(sender, payload)
    local st = streams[sender]
    if not st or type(payload) ~= "string" then return end
    st.lastAt = GetTime()
    for rec in payload:gmatch("[^;]+") do
        if st.got >= st.count then break end
        local a, b, c, d = rec:match("^(%w+),(%w+),(%w*),?(%w*)$")
        local id, p = Dec(a), Dec(b)
        if id and p and id < 10000000 and p > 0 and p < MAX_PRICE then
            st.got = st.got + 1
            local q = Dec(c)
            if q and q > 1000000 then q = nil end
            local t = st.t - math.min(Dec(d) or 0, WINDOW / 60) * 60
            if Plausible(id, p) then
                FT.Hist.Observe(id, p, q, nil, t, "peer")
                st.taken = st.taken + 1
                st.value = st.value + p * (q or 0)
            end
        end
    end
    -- a long transfer: the pages catch up once a minute (not on every message)
    if GetTime() - st.shownAt > 60 then
        st.shownAt = GetTime()
        FT.Fire("FT_PRICES_CHANGED", "peer")
    end
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

FT.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    if prefix ~= PREFIX or type(text) ~= "string" or not sender or IsMe(sender) then return end
    local kind, a, b, c, d = strsplit("\t", text)
    if kind == "D" then
        OnData(sender, b)
    elseif kind == "K" then
        if streams[sender] then streams[sender].lastAt = GetTime() end
    elseif kind == "E" then
        Finish(sender, true)
    elseif a ~= PROTO then
        return -- a newer exchange than ours
    elseif kind == "Q" then
        OnAsk(channel, b, c)
    elseif kind == "O" then
        OnOffer(channel, sender, b, c, d)
    elseif kind == "P" then
        OnPick(channel, b)
    elseif kind == "B" then
        OnBegin(channel, sender, b, c, d)
    end
end)

---------------------------------------------------------------------------
-- By itself: prices older than an hour, at most once an hour
---------------------------------------------------------------------------
local function AutoCheck()
    if not FT.S.shareAuto or ask or out or X.Receiving() or Fighting() then return end
    local now = time()
    if now - FT.Hist.MarketTime() < AUTO_EVERY or now - lastAuto < AUTO_EVERY then return end
    if #Channels() == 0 then return end
    lastAuto = now
    X.Ask(false)
end

local function Timeouts()
    for sender, st in pairs(streams) do
        if GetTime() - st.lastAt > IDLE_TIMEOUT then Finish(sender, false) end
    end
end

FT.On("FT_LOGIN", function()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    end
end)

FT.On("FT_READY", function()
    C_Timer.After(40, AutoCheck)
    C_Timer.NewTicker(60, AutoCheck)
    C_Timer.NewTicker(5, Timeouts)
end)
