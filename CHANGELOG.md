# The Wolf of Booty Bay

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
