# The Wolf of Booty Bay

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
