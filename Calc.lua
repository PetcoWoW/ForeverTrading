local _, FT = ...
local L = FT.L

-- The buy/sell calculator (v0.50), on the item page.
--   Buying N: what it costs walking up the listings (the cheapest first), the average, the dearest one you'd pay,
--     and the vendor's price when a vendor sells it for less (never pay over that).
--   Selling N at a price: what you take home after the auction house's cut (the real cut, read from your own sale
--     letters; else 5%, Blackwater 15%), the deposit (back when it sells), how many sit cheaper than yours, how long
--     yours take to sell at what sells a day, and what your N do to the price while they sit.
local C = {}
FT.Calc = C

-- buying qty: { total, avg, top, enough, levels (how many prices you walk through), vendor, vendorHow, cheaper } -
-- nil with nothing listed
-- (v0.54) the listings to walk: your last scan's, but at today's price when a newer price came since (the hourly
-- prices, the Wolf network): its depth shifted so its cheapest is the newest lowest price. { levels, t, shifted }
local function Levels(id)
    local book = FT.Hist.Book(id)
    local p, pt = FT.Price(id)
    if not (book and book.levels and #book.levels > 0) then return nil, p, pt end
    local low = book.levels[1][1]
    if p and pt and book.t and pt > book.t + 1800 and low and low > 0 and math.abs(p - low) / low > 0.01 then
        local k, levels = p / low, {}
        for i, lv in ipairs(book.levels) do levels[i] = { math.max(1, math.floor(lv[1] * k + 0.5)), lv[2] } end
        return { levels = levels, t = pt, qty = book.qty, shifted = true }, p, pt
    end
    return book, p, pt
end
C.Levels = Levels

function C.Buy(id, qty)
    qty = math.max(1, math.floor(tonumber(qty) or 1))
    local book, p = Levels(id)
    local out = { qty = qty }
    if book then
        out.shifted = book.shifted
        local left, cost, n, top = qty, 0, 0, nil
        for _, lv in ipairs(book.levels) do
            if left <= 0 then break end
            local take = math.min(left, lv[2])
            cost = cost + take * lv[1]
            left = left - take
            n, top = n + 1, lv[1]
        end
        out.enough = left <= 0
        out.got = qty - math.max(0, left)
        out.total = cost
        out.avg = out.got > 0 and cost / out.got or nil
        out.top, out.levels = top, n
        out.listed = book.qty
        out.t = book.t
    else
        if not p then return nil end
        out.total, out.avg, out.top, out.enough, out.got, out.levels, out.guess = p * qty, p, p, nil, qty, 1, true
    end
    local v, how = FT.VendorBuy(id)
    if v then
        out.vendor, out.vendorHow = v, how
        if out.avg and v < out.avg then out.cheaper = (out.avg - v) * out.got end
    end
    return out
end

-- the deposit of posting qty for `hours`: the game's when the auction house is open and it's in your bags, else
-- an estimate from the vendor price (Forever charges about 15% of it for a day)
local function Deposit(id, qty, hours)
    local _, _, _, sellPrice = FT.Item(id)
    if not sellPrice or sellPrice <= 0 then return 0, true end
    return math.floor(sellPrice * qty * 0.15 * (hours or 24) / 24 + 0.5), true
end

-- selling qty at unit (nil: just under the cheapest): { unit, gross, cut, cutRate, cutSeen, deposit, take, ahead,
-- perDay, days, share, slip }
function C.Sell(id, qty, unit, hours)
    qty = math.max(1, math.floor(tonumber(qty) or 1))
    local s = FT.An.Stats(id) or {}
    local book, p = Levels(id)
    local cheapest = (book and book.levels[1] and book.levels[1][1]) or p or s.price
    if not unit then
        -- under the cheapest by a copper - unless the cheapest is bait: then the normal price
        unit = (s.bait and s.fair) or (cheapest and math.max(1, cheapest - 1)) or s.fair
    end
    if not unit then return nil end
    local out = { qty = qty, unit = unit }
    out.gross = unit * qty
    out.cutRate = FT.Cut()
    local field = (FT.house == "neutral") and "cutSeenNeutral" or "cutSeen"
    out.cutSeen = type(FT.db and FT.db[field]) == "table"
    out.cut = math.floor(out.gross * out.cutRate + 0.5)
    out.deposit, out.depositGuess = Deposit(id, qty, hours)
    out.take = out.gross - out.cut
    -- how many sit cheaper than yours, and all that's listed
    local ahead, listed = 0, 0
    for _, lv in ipairs(book and book.levels or {}) do
        listed = listed + lv[2]
        if lv[1] < unit then ahead = ahead + lv[2] end
    end
    if listed == 0 then listed = s.listed or 0 end
    out.ahead, out.listed = ahead, listed
    local sales = s.sales
    local perDay = sales and (sales.hours or 0) >= 12 and sales.perDay or nil
    out.perDay = perDay
    if perDay and perDay > 0 then out.days = (ahead + qty) / perDay end
    -- what yours do to the price: their share of what's listed. A big share holds the price down while it sits -
    -- the others undercut it - so the more days of sales you post at once, the further it slips.
    out.share = listed > 0 and qty / (listed + qty) or 1
    if out.days then
        out.slip = math.min(0.4, 0.03 * math.max(0, out.days - 1) + 0.25 * math.max(0, out.share - 0.2))
    end
    if s.fair and unit > s.fair * 1.5 then out.high = s.fair end
    return out
end

-- the words of a buy, one line each
function C.BuyLines(b)
    if not b then return { FT.C("dim", L["Nothing listed to buy yet: a scan or a reload brings the listings."]) } end
    local lines = {}
    lines[1] = string.format(L["%s for %s"], FT.Money(math.floor(b.total)), FT.Num(b.got))
        .. FT.C("dim", "  ·  " .. string.format(L["%s each on average"], FT.Money(math.floor(b.avg or 0), "short")))
    if b.guess then
        lines[#lines + 1] = FT.C("dim", L["At the lowest price: the listings come with a scan."])
    elseif b.shifted and b.enough ~= false then
        lines[#lines + 1] = string.format(L["The dearest you'd pay: %s  ·  %d prices up the listings"], FT.Money(b.top, "short"), b.levels)
            .. FT.C("dim", "  ·  " .. L["your last scan's listings at today's price"])
    elseif b.enough == false then
        lines[#lines + 1] = FT.C("down", string.format(L["Only %s listed: you'd buy them all"], FT.Num(b.got)))
    else
        lines[#lines + 1] = string.format(L["The dearest you'd pay: %s  ·  %d prices up the listings"], FT.Money(b.top, "short"), b.levels)
    end
    if b.cheaper and b.cheaper > 0 then
        lines[#lines + 1] = FT.C("accent", string.format(L["A vendor sells it for %s  ·  never pay over that  ·  %s saved"],
            FT.Money(b.vendor, "short") .. (b.vendorHow == "estimate" and "~" or ""), FT.Money(math.floor(b.cheaper), "short")))
    elseif b.vendor then
        lines[#lines + 1] = FT.C("dim", string.format(L["A vendor sells it for %s"], FT.Money(b.vendor, "short") .. (b.vendorHow == "estimate" and "~" or "")))
    end
    return lines
end

-- the words of a sale, one line each
function C.SellLines(x)
    if not x then return { FT.C("dim", L["No price for it yet."]) } end
    local lines = {}
    lines[1] = string.format(L["You take home %s"], FT.C("up", FT.Money(math.floor(x.take))))
        .. FT.C("dim", "  ·  " .. string.format(L["%s at %s each"], FT.Num(x.qty), FT.Money(x.unit, "short")))
    lines[#lines + 1] = string.format(L["The cut: %s (%s%%%s)"], FT.Money(x.cut, "short"),
        string.format("%g", math.floor(x.cutRate * 1000 + 0.5) / 10),
        x.cutSeen and (", " .. L["from your sale letters"]) or "")
        .. FT.C("dim", "  ·  " .. string.format(L["deposit ~%s, back when it sells"], FT.Money(x.deposit, "short")))
    if x.days then
        local d = x.days < 1 and L["within a day"] or string.format(L["~%s days"], FT.Num(math.floor(x.days + 0.5)))
        lines[#lines + 1] = string.format(L["%s cheaper than yours  ·  sells ~%s a day: yours go %s"], FT.Num(x.ahead),
            x.perDay >= 10 and FT.Num(math.floor(x.perDay + 0.5)) or string.format("%.1f", x.perDay), d)
    else
        lines[#lines + 1] = string.format(L["%s cheaper than yours  ·  not enough sales seen to say how fast"], FT.Num(x.ahead))
    end
    if x.slip and x.slip >= 0.03 then
        lines[#lines + 1] = FT.C("accent", string.format(L["Yours are %d%% of what's listed  ·  expect the price to slip ~%d%% while they sit  ·  post fewer at a time"],
            math.floor(x.share * 100 + 0.5), math.floor(x.slip * 100 + 0.5)))
    elseif x.share then
        lines[#lines + 1] = FT.C("dim", string.format(L["Yours are %d%% of what's listed  ·  the price holds"], math.floor(x.share * 100 + 0.5)))
    end
    if x.high then lines[#lines + 1] = FT.C("down", string.format(L["Over its normal price (%s)  ·  it may sit"], FT.Money(x.high, "short"))) end
    return lines
end

-- "12" / "12.5" (gold), "12g 50s", "75s", "30c" -> copper (nil: not a price)
function C.ParseMoney(text)
    text = tostring(text or ""):lower():gsub("%s+", "")
    if text == "" then return nil end
    local n = tonumber(text)
    if n then return n > 0 and math.floor(n * 10000 + 0.5) or nil end
    local total, any = 0, false
    for v, u in text:gmatch("([%d%.]+)([gsc])") do
        local x = tonumber(v)
        if x then
            any = true
            total = total + x * (u == "g" and 10000 or u == "s" and 100 or 1)
        end
    end
    return any and total > 0 and math.floor(total + 0.5) or nil
end
