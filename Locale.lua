-- Wolf: texts. English is the key. With "Plain English" on (Settings >
-- General, the default) the trader terms are swapped for plain words: the table below, applied once at start.
-- Every other text shows as written in the code.
local ADDON, FT = ...

local L = setmetatable({}, { __index = function(_, k) return k end })
FT.L = L

-- original text -> what Plain English shows instead
local plain = {}
FT.PLAIN = plain

-- keys that aren't English text themselves: what they show with the trader terms
local base = { ["liq:high"] = "high", ["liq:medium"] = "medium", ["liq:low"] = "low" }

function FT.ApplyLocale(words)
    for k, v in pairs(base) do rawset(L, k, v) end
    if words ~= "trader" then
        for k, v in pairs(plain) do rawset(L, k, v) end
    end
end

-- what to do: the signal badges (short: they sit in narrow columns)
plain["SELL"] = "CASH OUT"
plain["BUY"] = "BUY DIP"
plain["HOLD"] = "HODL"
plain["TRIM"] = "SELL HALF"
plain["PRICEY"] = "OVERPRICED"
plain["AVOID"] = "STAY AWAY"
plain["LOSS"] = "LOSES GOLD"
plain["FAIR"] = "NORMAL"
plain["WATCH"] = "WAIT"
plain["RESELL"] = "FLIP IT"
plain["Resell"] = "Flip"
plain["Sell now"] = "Cash out now"
plain["Hold / avoid"] = "HODL / stay away"

-- hype (RSI): 0-100, how much of the recent moves were up
plain["RSI"] = "Hype"
plain["RSI (14)"] = "Hype meter"
plain["RSI %d: overbought"] = "Overhyped (%d/100): lots of people already piled in"
plain["RSI %d: oversold"] = "Beaten down (%d/100): could bounce back"
plain["Price change, RSI, the signal and the craft profit of the item."] =
    "Price change, hype, what to do and the craft profit of the item."
plain["Sell: %d%% above the %d-day average or RSI 70+.  Buy: %d%% below or RSI 30-.  Craft: profit from %s and margin from %d%%."] =
    "Cash out: %d%% over normal (%d days) or overhyped  ·  Buy the dip: %d%% under or beaten down  ·  Craft: %s+ and %d%%+ profit"

-- the other numbers
plain["Indicators"] = "The numbers"
plain["vs average"] = "vs normal"
plain["Daily volatility"] = "Daily swing"
plain["Liquidity"] = "How fast it sells"
plain["liquidity"] = "how fast it sells"
plain["liq:high"] = "fast"
plain["liq:medium"] = "steady"
plain["liq:low"] = "slow"
plain["%d%% of %s liquid items up (7d)"] = "%d%% of %s up (7d)"
plain["Moving averages"] = "Average lines"
plain["MA7"] = "7-day avg"
plain["MA25"] = "25-day avg"
plain["Two smoothed lines on the price chart: MA7 and MA25, the average price of the last 7 and 25 points (days on 1D). Until there are that many, of the points there are; MA25 shows once there are more than 7."] =
    "Two smooth lines on the chart: the average price of the last 7 and the last 25 points (days, on 1D). They show the trend without the day-to-day noise."
plain["Margin"] = "Profit %"
plain["Margin / ROI"] = "Profit %"
plain["Craft: minimum margin"] = "Craft: minimum profit %"
plain["Order book"] = "Listings by price"
plain["The order book"] = "Listings by price"
plain["Check order books"] = "Check listings"
plain["Check order books (%d)"] = "Check listings (%d)"

-- the normal price (the "fair price": a median that ignores spikes)
plain["Fair price"] = "Normal price"
plain["The median of the last days' prices, weighted by how many were listed and how recent."] =
    "What it normally goes for: the middle of the last days' prices, counting busier and newer ones more."
plain["%s under the fair price (%s)."] = "%s under the normal price (%s)."
plain["%s each, fair ~%s: list at %s, +%s each after the cut"] = "%s each, normally ~%s: list at %s, +%s each after the cut"
plain["falling fast: %s, fair ~%s"] = "crashing: %s, normally ~%s"
plain["price jump (buyout?): fair ~%s"] = "price spike (cheap ones bought out?): normally ~%s"
plain["A price jump right now (buyout?): the fair price is ~%s - it may not last."] =
    "Price spike right now (someone bought the cheap ones?): normally ~%s - it may not last."
plain["Price jump (buyout?): %s above its fair price ~%s - sell a little under it now, it won't last"] =
    "Price spike: %s above its normal ~%s - sell a little under it now, it won't last"
plain["Price falling fast: %s vs its fair price"] = "Crashing: %s vs its normal price"
plain["The price is falling fast: %s vs its fair price."] = "Crashing: %s vs its normal price."
plain["Jump: above the fair price by"] = "Spike: above the normal price by"
plain["Falling fast: below the fair price by"] = "Crashing: below the normal price by"
plain["Sell when the price is above average by"] = "Cash out when it's above normal by"
plain["Buy when the price is below average by"] = "Buy the dip when it's below normal by"
plain["Selling now: price vs its %d-day average"] = "Selling now: price vs its normal %d-day price"
plain["Deals: resale under the fair price by"] = "Deals: flip when under the normal price by"
plain["Deals: resale %d%% or more under the fair price, from %s profit (Settings > Signals)."] =
    "Deals: flips %d%% or more under the normal price, from %s profit (Settings > Signals)."
plain["Signals > Good deals: a lot this far under its fair price, on a market that sells most days and isn't flooded, is worth buying to list again."] =
    "Signals > Good deals: this far under its normal price, on an item that sells most days and isn't flooded, it's worth buying to flip."
plain["To a vendor: a sure profit. Resell: the cheap lots of a steady market, listed again near the fair price. Between houses: cheaper at one auction house than the other sells it for."] =
    "To a vendor: a sure profit. Flip: the cheap ones of a steady item, listed again near the normal price. Between houses: cheaper at one auction house than the other sells it for."
plain["Under the lowest would be %s: far under its fair price (or the vendor's). Rather wait for the cheap lots to go, or let yours run out."] =
    "Under the lowest would be %s: far under its normal price (or the vendor's). Better to wait for the cheap ones to go, or let yours run out."

-- shorter where it shows all the time
plain["From the auction house's letters, read when you open your mailbox; deposits of what you post here. The cut is taken off what sold."] =
    "From your auction house mail. The cut is already taken off."
plain["Average"] = "Average price"
plain["TO VENDOR"] = "VENDOR IT"
plain["CARRY OVER"] = "AH TO AH"
