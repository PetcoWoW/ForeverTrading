# The Wolf of Booty Bay

## v0.11 - simpler: an extension of Auctionator

- Header: AH and API chips (your last scan, Auctionator's included; Blizzard's hourly prices) in place of
  "AH: offline"; the one in use lit, old ones yellow. AH click: take Auctionator's last scan again; right-click:
  the game's AH window (when it's hidden). API click when newer prices are out: /reload.
- Auctionator's last scan (AUCTIONATOR_SAVEDVARS.TimeOfLastBrowseScan + its price database) is taken at login when
  it's newer than what we have.
- Cut what Auctionator does: the Sell tab (posting, My auctions), Full scan, My items, Exchange (off by default).
- Money: Make gold (carry, flip, vendor in one ranked list) and Farm. Portfolio: Holdings, Sell yours, Characters,
  Journal. The old links (What's new, the tour) lead to the new places.
- Signals in plain words ("Higher than usual (+20%), and jumps like this fade fast: sell now") with Sure / Likely /
  Guess; the numbers behind them on a hover of the badge.
- Tooltips: two lines (signal and price; craft profit, best use or disenchant value), Shift for more. Cached
  10 seconds per item, nothing worked out in combat, no redraw of the tooltip: bag addons aren't slowed.
- Best use counts only products that really sell (3+ sales seen, one a day or more) first; others are marked.
- Settings: Basics first, the rest behind Show all settings. The last page you used opens next time.
- A shorter tour.

## v0.10 - bug pass

- Fixed: Money > Sell yours and Farm Board weren't shown or hidden by the view switch (their frames were looked up
  before they were declared, so the switch never found them).
- Biggest movers (Terminal lists, banners) count only real markets: 3+ sold a day from 5+ known sales, 1g+ a day
  changing hands, 5+ listed, and yesterday's price in line with the week before (no "down 85%" from one
  overpriced day, no "up 300%" on a 4-silver item).
- A note in chat when the original ForeverTrading is also turned on (both would scan and fill tooltips).
- tools/test: a static audit and a load test that runs the whole addon in a fake WoW.

## v0.9 - quiet alerts

- No pop-ups by default: price alerts, TO THE MOON / RUG PULL and WHALE ALERT go to chat, the banners of one
  scan grouped into one line per kind. Settings > Alerts > Pop-up alerts brings the pop-ups (and their sound) back.

## v0.8 - signals that learn

- Each item's own record, from up to 60 days of daily prices: after a jump (10%+ over its 14-day average), did it
  still hold 95% of it 5-9 days later; after a dip, was it back within 3% of the average; which weekday closes
  highest. Shrunk toward a cautious guess while cases are few.
- Its kind's record (item class and subclass: herbs, ore, cloth, potions...), worked out once a day in the
  background over every item, stands in until the item has 3 cases of its own (30+ cases for the kind).
- Sell: jumps that hold -> HODL; jumps that fade -> CASH OUT; its best weekday 1-3 days away and 5%+ higher ->
  HOLD till then. Low: dips that come back -> wait; dips that don't -> no point waiting. Buy: dips that come back
  -> APE IN, dips that don't -> careful.
- Long hold: mark an item on its chart; it says HODL until you unmark it.
- The item's glance line shows what it learned (jumps held, best day).

## v0.7 - hold what's climbing

- The sell signal tells a jump from a climb. Climbing for weeks (this week's average 5%+ over the two weeks
  before, up 15%+ in 30 days, higher lows) and still selling: HODL (DIAMOND HANDS in meme mode). Stretched far
  above its average (3x the sell threshold, or RSI 80+): SELL HALF. The climb cracking (fell since the last
  check, under its fair price, flooded, more sellers, hardly selling): CASH OUT.
- Settings > Signals > Hold what's climbing turns it off (back to selling anything above average).

## v0.6 - Best use of a material

- Every crafting recipe of WoW Forever (2,302, from the Blizzard API's `static-forever-us` professions) ships in
  `Data/Recipes.lua`; a weekly workflow keeps it current.
- Best use: every recipe a material goes into, ranked by what one of it brings (the product's price minus the
  other materials, per one), against selling it as it is; recipes your characters know are marked.
- Opens from a Farm Board row (click), the Best use button on an item's chart, and a line in a material's tooltip.

## v0.5 - batch 4: the meme layer

- TO THE MOON / RUG PULL banners: something you own or watch up or down 30%+ in a day, plus the market's single
  biggest move each way; once a day per item.
- Market Makers on the Terminal: the 20 sellers with the most gold listed, from your last Full scan (the Blizzard
  feed has no seller names). Click one to open their biggest item.
- WHALE ALERT: one seller holding half or more of an item you own or watch (50g+ of it); the item's glance line
  names the whale.
- APE IN on the strongest buys. Settings > Alerts > Meme mode turns it all off.

## v0.4 - batch 3: money and portfolio

- The Money tab: Carry it (between your faction's auction house and Blackwater, the other house's prices from the
  price feed when you haven't been there), Flip it, Vendor it, Sell yours (each thing you own: vendor, this house or
  the other, how many at a time), the Farm Board, and Signals. The best move right now sits under the title.
- Farm Board: ore, herbs, leather, cloth, elemental and gems ranked by price x how many sell a day, with the week's
  move; right-click for a Wowhead link.
- Portfolio > Characters: gold, items, total and when the bank and mailbox were last seen, for every character;
  out-of-date ones named at the top.

## v0.3 - batch 2: slim and readable

- Four tabs: Terminal, Money, Portfolio, Sell. The Craft tab is off by default (Settings > General > Craft tab).
- Simple view (on by default): each item shows Normal price, 7-day low, Listed and Sells a day; what to do gets
  the big card with hype, how fast it sells and vs normal price in one line; no indicators card.
- Simple chart: one line, green when it went up over the period, red when down, with the room of both charts.
  "Pro chart" brings back candles, the averages and the second chart.
- Shorter texts in the tour and on the Money page; the header says Wolf of Booty Bay.

## v0.2 - batch 1: data and freshness

- Signals count only the days the market was really seen: the feed's real days plus the days Auctionator scanned
  (your old Auctionator history counts from the start).
- The feed keeps 90 days and ships 30; its record is saved in the repository's feed-history branch every run.
- Status bar: Blizzard vs Your scan, the newer one in green, Blizzard in yellow once newer prices are likely out.
- A chat reminder, at most hourly and never in combat, when newer prices are likely out: /reload.
- A note in chat when Auctionator's scan was taken: no need to scan twice.
- Full scan runs Auctionator's scan when it is installed, so one scan feeds both (Settings > Sources).
- A merged change is released at once, not at the next hourly run.

## v0.1 - the price feed

- Every release now carries the prices of every WoW Forever auction house, built hourly from Blizzard's own
  auction data: lowest price, listed, sold over the last 7 days, daily lows. Prices before your first scan,
  charts for the days you didn't scan, and "sells ~N a day" from a whole week of watching. Settings > Sources.
- Releases are published hourly (version 0.1.<date and time>), so WowUp keeps the prices fresh.

## v0.1.0

First version, built on ForeverTrading 1.1.4 by thewoolfi.

- New name, its own saved data and the `/wolf` commands. ForeverTrading's data isn't carried over: run a
  full scan, and Auctionator's history fills the charts.
- Easier to read: the game's own wide font by default, a Text size setting, window scale up to 150%.
- Plain English: trader terms (RSI, liquidity, volatility, moving averages, fair price) swapped for plain
  words, and the signals read CASH OUT / BUY DIP / HODL / FLIP IT. Settings > General > Words switches back.
- Removed: the Russian translation, the light and classic styles, the Mastercraft link.
- The price exchange still works with ForeverTrading users.
