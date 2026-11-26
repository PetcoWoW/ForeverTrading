# The Wolf of Booty Bay

The WoW Forever auction house as a stock market: a ticker tape, 7-day trend lines, gainers and losers, charts, plain-English
"what to do" signals, deals and your net worth across every character.

Built on [ForeverTrading](https://github.com/thewoolfi/ForeverTrading) by thewoolfi (Apache License 2.0).
His scanner, price history, price exchange and trading tools are the engine; this addon reworks the look
and the words and adds its own features. See `NOTICE`.

## Install

1. **The addon:** search "Wolf of Booty Bay" in the CurseForge app (or on curseforge.com) and install it. New
   versions arrive through CurseForge. Or take the newest zip from this repository's **Releases** page and put the
   `WolfOfBootyBay` folder into `World of Warcraft/<your Forever client>/Interface/AddOns/`.
2. **Hourly prices (Windows):** [WolfPricesSetup.exe](https://github.com/sain221b-sketch/ForeverTrading/releases/download/companion/WolfPricesSetup.exe), the Wolf prices companion. Run it, click Install.
   In game: Settings > About > Prices companion.

Restart the game fully the first time (new addon files load at launch, not on `/reload`), then type `/wolf`.

## The Wolf prices companion (Windows)

A small program by the clock that keeps the prices fresh: every 15 minutes it asks the price robot (this
repository's releases) whether there are newer prices, and if so puts them in the addon folder. It never shows a
notification, a window or a sound on its own - safe on stream. In game, when you open the auction house and newer
prices are waiting, chat says so with a **[Load them]** link (the game reads files only at login or `/reload`).

- **Download:** [WolfPricesSetup.exe](https://github.com/sain221b-sketch/ForeverTrading/releases/download/companion/WolfPricesSetup.exe). Setup finds World of Warcraft and the addon, installs for your
  Windows user only (no admin rights) and starts with Windows if you leave that ticked.
- **What it touches:** the addon's price file (`Interface/AddOns/WolfOfBootyBay/Data/Feed.lua`), a one-line note
  beside it (`Data/Companion.lua`: when it last checked), its settings and log in `%APPDATA%\WolfPrices`, and
  itself in `%LOCALAPPDATA%\Programs\WolfPrices`. Nothing else: no accounts, no game memory, no data sent anywhere.
- **Updates itself** quietly from its own release, only when the download matches its published SHA-256.
- **Remove it:** Windows Settings > Apps > Wolf prices > Uninstall.
- **Source:** [`companion/`](companion/) (C#, .NET Framework 4.8, part of Windows). It's built from that source by
  [`.github/workflows/companion.yml`](.github/workflows/companion.yml) on GitHub's own Windows machines, which
  also test it against a pretend game folder.
- Windows shows "Windows protected your PC" the first time for programs it hasn't seen much yet: More info >
  Run anyway.

## The price feed

Every release carries the prices of every WoW Forever auction house, built hourly from Blizzard's own auction
data (`tools/feed/`): the lowest price, how many are listed, what sold over the last 7 days and the daily lows.
So the addon has prices before your first scan, charts for the days you didn't scan, and "sells ~N a day" from
a whole week of watching. Your own scans and prices from other players still win when they are newer. Fresh
feed: the prices companion fetches it, then `/reload`. Settings > Sources turns it off.

Don't run ForeverTrading at the same time: two scanners do the same work twice.

## Recipes (Best use)

`Data/Recipes.lua` holds every crafting recipe of WoW Forever (about 2,300), read from the Blizzard API by
`tools/recipes/build.mjs`. The `recipes` workflow refreshes it every Monday and commits it when something changed.
It's what **Best use** ranks: every recipe a material goes into, and what one of it brings in each. You'll find it
on the Farm Board (click), the item's Best use button on the Terminal, and a line in the material's tooltip.

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
