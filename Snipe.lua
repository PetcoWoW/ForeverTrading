-- Wolf: Snipe - what to buy at the auction house right after a scan, and what to keep an eye on.
--  * Underpriced now: items whose price from a fresh scan (two hours or newer) is under their snipe price - their
--    real price (the lower of the fair price and the recent average) less the deal margin (Settings: 30%) -
--    on a market that isn't being dumped or pushed up. Each with how sure (FT.Snipe.Confidence).
--  * Often underpriced: items whose deep dips came back most times, replayed on their price history (FT.An.Behavior's
--    flips, gathered by FT.An.LearnKinds once a day): the ones worth searching again and again.
-- Nothing is bought here: each Buy goes through FT.Buy (the server's price, your click).
local ADDON, FT = ...
local L = FT.L

local S = {}
FT.Snipe = S

local FRESH = 2 * 3600 -- a price this new is "right now" (a scan's)
local MAX_NOW = 60
local MAX_OFTEN = 40

local nowList, nowAt, building

-- the price to snipe under: its real price less the margin; nil without a real price
function S.Below(s)
    local fair = s and s.fair
    if fair and s.avg and s.avg > 0 and s.avg < fair then fair = s.avg end
    if not (fair and fair > 0) then return nil end
    return math.floor(fair * (1 - (FT.S.dealBelow or 30) / 100)), fair
end

-- how sure a snipe at `price` is: "safe" / "good" / "gamble", and why (a few words)
function S.Confidence(id, s, price)
    local vendor = FT.SellPriceKnown(id) or 0
    if vendor > 0 and vendor >= price then return "safe", L["a vendor pays more"] end
    local perDay = (s.sales and s.sales.hours >= 12) and s.sales.perDay or 0
    local ok, n, own = FT.An.FlipRecord(s.behavior)
    local rate = ok and n > 0 and ok / n or nil
    local sells = perDay >= 1 and string.format(L["sells %s a day"], perDay >= 10 and FT.Num(math.floor(perDay + 0.5)) or string.format("%.1f", perDay)) or L["hardly sells"]
    local record = rate and (own and string.format(L["came back %d of %d times"], ok, n) or string.format(L["items like it came back %d%%"], math.floor(rate * 100 + 0.5)))
    if perDay >= 5 and rate and rate >= 0.7 then return "safe", sells .. ", " .. record end
    if perDay >= 2 and (not rate or rate >= 0.5) then return "good", sells .. (record and (", " .. record) or "") end
    return "gamble", sells .. (record and (", " .. record) or "")
end

S.CONF_COLORS = { safe = "up", good = "accent", gamble = "down" }
S.CONF_TEXT = { safe = "SAFE", good = "GOOD", gamble = "GAMBLE" }

-- a quick look before the whole stats: far under the middle of its last days?
local function LooksCheap(r, below)
    local spark = r.spark
    if not (r.price and spark and #spark >= 3) then return false end
    local days = {}
    for i = 1, #spark - 1 do days[#days + 1] = spark[i] end
    table.sort(days)
    local mid = days[math.ceil(#days / 2)]
    return mid and r.price <= mid * (1 - below * 0.6)
end

-- worked out a little each frame after a scan (FT_SNIPE_READY when done); the list there meanwhile
function S.Now()
    return nowList or {}, nowAt, building
end

function S.Build()
    if building then return end
    local rows = FT.Market.Rows()
    if not rows then return end
    building = true
    local below = (FT.S.dealBelow or 30) / 100
    local out = {}
    local now = time()
    FT.Job("snipe", #rows, function(k)
        local r = rows[k]
        if r.gone or not LooksCheap(r, below) then return end
        local p, t = FT.Price(r.id)
        if not (p and t and now - t <= FRESH) then return end
        local s = FT.An.Stats(r.id)
        if s.pumped or s.dumping then return end
        local under, fair = S.Below(s)
        if not (under and p <= under) then return end
        local conf, why = S.Confidence(r.id, s, p)
        -- not a vendor sure thing: gear's cheapest is often a poor version (its price mixes them all) - left out;
        -- so is what hardly sells (bought, it couldn't be sold again)
        if (FT.SellPriceKnown(r.id) or 0) < p then
            local _, _, _, _, _, classID = FT.GetItemInfoInstant(r.id)
            if classID == 2 or classID == 4 then return end
            local perDay = (s.sales and s.sales.hours >= 12) and s.sales.perDay or 0
            if perDay < 0.5 then return end
        end
        -- far too good to be true: a wrong price, bait, or a version mix-up - a gamble, said so
        if p < fair * 0.2 and conf ~= "safe" then conf, why = "gamble", L["over 80% off: check the listing first"] end
        -- how many to buy: the cheap ones of a fresh order book (else one), no more than sells in two days
        local qty = 1
        local book = FT.Hist.Book(r.id)
        if book and book.levels and (book.t or 0) >= t - 600 and book.source ~= "mastercraft" then
            local n = 0
            for _, lv in ipairs(book.levels) do
                if lv[1] > under then break end
                n = n + lv[2]
            end
            local perDay = s.sales and s.sales.perDay or 0
            qty = math.max(1, math.min(n, math.max(1, math.floor(perDay * 2 + 0.5))))
        end
        out[#out + 1] = { id = r.id, price = p, under = under, fair = fair, off = p / fair - 1, conf = conf, why = why,
            listed = s.listed, t = t, gain = (fair * (1 - FT.Cut()) - p), qty = qty }
    end, function()
        -- the surest first, then the most gold each
        local rank = { safe = 1, good = 2, gamble = 3 }
        table.sort(out, function(a, b)
            if rank[a.conf] ~= rank[b.conf] then return rank[a.conf] < rank[b.conf] end
            return a.gain > b.gain
        end)
        for i = #out, MAX_NOW + 1, -1 do out[i] = nil end
        nowList, nowAt, building = out, time(), false
        FT.Fire("FT_SNIPE_READY")
    end, 3)
end

-- after a scan of the whole market (yours, Auctionator's, or one shared with you): the list again
FT.On("FT_SCAN_DONE", function(kind)
    if kind == "full" or kind == "auctionator" or kind == "peer" or kind == "feed" then
        C_Timer.After(2, S.Build)
    end
end)

-- Often underpriced: { { id, ok, n, price, under, fair } }, the most comebacks first (from the daily learning)
function S.Often()
    local l = FT.db and FT.db.learned and FT.db.learned[FT.houseKey or "?"]
    local out = {}
    for _, x in ipairs(l and l.often or {}) do
        local s = FT.An.Stats(x.id)
        local under, fair = S.Below(s)
        out[#out + 1] = { id = x.id, ok = x.ok, n = x.n, price = s.price, under = under, fair = fair,
            hit = s.price and under and s.price <= under }
    end
    return out
end
S.MAX_OFTEN = MAX_OFTEN
