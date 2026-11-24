# The Wolf of Booty Bay

The WoW Forever auction house as a stock market: tickers, gainers and losers, charts, plain-English
"what to do" signals, deals and your net worth across every character.

Built on [ForeverTrading](https://github.com/thewoolfi/ForeverTrading) by thewoolfi (Apache License 2.0).
His scanner, price history, price exchange and trading tools are the engine; this addon reworks the look
and the words and adds its own features. See `NOTICE`.

## Install

Get the newest release from this repository's **Releases** page (or add the repository to WowUp as a GitHub
source, so it updates itself) and put the `WolfOfBootyBay` folder into
`World of Warcraft/<your Forever client>/Interface/AddOns/`. Restart the game fully the first time (new
addon files load at launch, not on `/reload`), then type `/wolf`.

## The price feed

Every release carries the prices of every WoW Forever auction house, built hourly from Blizzard's own auction
data (`tools/feed/`): the lowest price, how many are listed, what sold over the last 7 days and the daily lows.
So the addon has prices before your first scan, charts for the days you didn't scan, and "sells ~N a day" from
a whole week of watching. Your own scans and prices from other players still win when they are newer. Fresh
feed: update the addon (WowUp does it by itself) and `/reload`. Settings > Sources turns it off.

Don't run ForeverTrading at the same time: two scanners do the same work twice.

## Settings that matter (Settings > General)

- **Words**: Plain English (default) swaps trader terms for plain ones - "Hype meter" instead of RSI,
  "How fast it sells" instead of liquidity, CASH OUT / BUY DIP / HODL instead of SELL / BUY / HOLD.
  Trader terms brings the originals back.
- **Font**: the game's own wide font (default) or the narrow condensed one.
- **Text size** and **Window scale** (up to 150%).

## Commands

`/wolf` window · `/wolf scan` full scan · `/wolf scan mine` your items · `/wolf stop` ·
`/wolf share` ask guild and group for prices · `/wolf words plain | trader` · `/wolf reset` · `/wolf credits`

## Prices from other players

The price exchange speaks ForeverTrading's protocol, so you swap prices with ForeverTrading users in your
guild or group as well as with other Wolf of Booty Bay users.
