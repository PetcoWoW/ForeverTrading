# The price feed

`build.mjs` downloads every WoW Forever auction house from Blizzard's Game Data API and writes
`Data/Feed.lua`, which the addon reads at login (`Sources/Feed.lua`). The workflow
`.github/workflows/feed.yml` runs it every hour at :17 and publishes the addon with the fresh file as a new
GitHub release.

## What it ships, per auction house and item

- the lowest price now, how many are listed, in how many auctions;
- what sold over the last 7 days, what it sold for, and how many expired;
- the lowest price of each of the last 14 days (UTC days).

## How sales are counted

Blizzard doesn't publish sales, so each run compares the listings with the previous run's, an hour earlier:

- a listing gone with more than 2 hours left was bought (or taken off by its seller - from outside the two look
  the same);
- a listing gone with under 30 minutes left ran out;
- 30 minutes to 2 hours left: can't tell, not counted;
- a stack of goods that got smaller: the difference was bought.

Runs more than 3 hours apart count no sales between them.

## Endpoints

```
POST https://oauth.battle.net/token                                     (client credentials)
GET  https://{region}.api.blizzard.com/data/wow/ruleset/2/auctions/{house}?namespace=dynamic-forever-{region}
GET  .../auctions/{house}/commodities?namespace=dynamic-forever-{region}
```

Houses: PvP 110 / 113 / 116, Normal 111 / 114 / 117, Roleplay 119 / 120 / 121, Roleplay PvP 123 / 124 / 125
(Alliance / Horde / Neutral). Thanks to the
[Oribos Exchange Forever research notes](https://github.com/ZiiMs/OribosExchange-Forever/blob/main/docs/research/forever-auction-api.md)
for documenting them.

## Set it up

1. Create a client at <https://develop.battle.net/access/clients>.
2. In the GitHub repository: Settings > Secrets and variables > Actions, add `BLIZZARD_CLIENT_ID` and
   `BLIZZARD_CLIENT_SECRET`. Optional variables: `FEED_REGIONS` (e.g. `us,eu`; default `us`) and
   `FEED_HOUSES` (default `110,116`, PvP Alliance and PvP Blackwater; the house ids are below).
3. Actions > Price feed > Run workflow, once. After that it runs hourly.

The first run has prices and no sales yet; sales and daily lows fill in over the next days.

## Run it locally

```
BLIZZARD_CLIENT_ID=... BLIZZARD_CLIENT_SECRET=... node tools/feed/build.mjs
```

`FEED_FIXTURE=<folder>` builds from saved API answers instead (`<region>-<house>.json` with `auctions`,
`commodities` and `modified`), for testing.
