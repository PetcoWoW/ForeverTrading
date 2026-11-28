# Wolf

## v0.61 - getting around, honest dungeons, your auctions in place

- **Back and Forward** by the search box, like a browser (the mouse's side buttons too): every page, section,
  Farm it mode and item you open is a step; their hover says where they go.
- **The search box doesn't jump:** what you type shows the items it finds right under it, with price and verdict;
  only picking one opens it.
- **Right-click the wolf by the minimap:** a session running (yours or one tracking itself) shows its card - where
  and what, the gold, gold an hour, its best loot - with Show on screen and Stop and save. Nothing running: Start a
  session.
- **Farm it:** the sections on one row, the mode's own choice on its own row below ("How you run it: Full clear ·
  Trash only · Solo"). A click on a dungeon opens its card: gold each a run and an hour, what a run is made of
  (coin, vendor loot, what sells, rare drops), its best loot, your own runs there.
- **Dungeon gold checked:** world greens no longer count (Maraudon had ~80g a run of them: 54 Brutish Gauntlets),
  loot from cMaNGOS's full tables, clear times at least a minute for every 5 mobs, and stacks past what the auction
  house buys count at a vendor. Maraudon: ~43g a run, ~8.6g each in a group (the guides: ~8g).
- **Skinning and gathering** in Where to farm it: items and gold an hour like drops, with what they need; only a
  profession one of your characters has can be the answer.
- **Your auctions where you look:** an item's page says "your 5 listed at 12g, undercut by 40s since 2 pm" (or the
  cheapest); Holdings has an "undercut" badge to My auctions; after a login, one line for listings undercut since
  the last prices.
- **Your buys and sales on the chart:** a green dot where you bought, gold where you sold, and under the mouse how
  many at what (from the auction house's mail).
- **Two lanes:** every build reaches the prices companion's friends at once; CurseForge gets a version when it's
  released there. Wolf no longer points to the companion, and a CurseForge user isn't told about a friend's newer
  build. The companion updates only when Wolf's own files change.
- Make gold's list box says "Filter this list...", apart from the search at the top.

## v0.60 - a test update (not on CurseForge)

- Only for testing the prices companion's updates: a new version number and a line in a spare file
  (Extra\Logic1.lua) that /wolf build shows. Nothing else changed; it came to companion users only.

## v0.59 - room to grow without a restart

- **Spare files:** six empty code files (Extra\Logic1-4, Extra\UI1-2) and two data files (Data\Extra1-2) in the
  TOC. The game reads its list of files only at launch, so new code goes into a spare one and the prices
  companion's update still comes in with a /reload. (This version adds them: it's the one that waits for a restart.)
- **/wolf build:** which build runs, and what the prices companion last put in (or what waits for a restart).
- **Prices companion 1.1.1:** setup run while it's by the clock closes the running one first (an older one that
  doesn't answer is closed for it) instead of failing; it waits for a restart only when Wolf's files or saved data
  change, not its description.

## v0.58 - Wolf updates itself

- **The prices companion (1.1) keeps Wolf up to date:** a new Wolf - a version or a fix - is swapped in while you
  play, checked against its fingerprint; the next /reload (the same one that loads new prices) loads it. Your prices
  and settings stay. A version with new files waits until the game is closed (the game reads its file list only at
  launch), and chat says so. Off in the companion's tray menu: "Keep Wolf updated".
- In game: "Wolf v0.59 is ready (the prices companion brought it): [Reload]", the minimap dot's menu loads it, and
  once it's in, one line with what's new.
- Release builds carry their commit (the TOC's X-Commit) and their version in the code, so a reload-loaded Wolf
  knows which it is.

## v0.57 - worth at a glance, solo dungeons, quiet alerts, farming tracked by itself

- **You > Holdings:** no ring to read. The total, then each part biggest first - its gold, its share (a bar of it
  behind the row) and its top items. **What it is** (herbs, ore, cloth, leather, enchanting, consumables, gear,
  recipes) is the new default; Where it is and How liquid stay. Click a part: just that in the table.
- **Dungeons > Solo:** the whole run's loot is yours, at a slower clear (smaller pulls), only dungeons well under
  your level; 3 to 7 levels under is marked HARD SOLO. The caveat says it plainly: for a geared class that holds big
  pulls (warrior, paladin, druid, warlock, mage).
- **Quiet alerts:** a small dot on the minimap button - green when newer prices are waiting, gold when a newer Wolf
  is out - and both in its right-click menu ([Load the fresh prices], [Get v...]). The chat line comes at a natural
  pause (opening the auction house or a mailbox), once an hour at most. A newer Wolf is said at login once, and once
  more three days on if you're still on the old one. Settings > Alerts: load fresh prices by itself when the
  auction house opens (off by default).
- **Farming tracked by itself:** your first gather or loot out of town starts a session quietly (nothing on screen);
  5 minutes without loot pauses it and those minutes don't count; 30 ends it. Saved in You > Sessions as where and
  what ("Felwood · herbs, 42 min") with one chat line; tiny ones aren't kept; your own session takes over. Settings >
  Alerts.

## v0.56 - honest drops, a cozier farm window

- **Drops lists real farms only.** World drops (epics any mob of a level can give, 1 in thousands) are gone from it:
  1,118 of its 1,706 entries were those. What's left is loot a mob is worth killing for.
- **Ranked by steady gold an hour:** each mob's coin, vendor loot and common trade drops, at how many you can kill an
  hour (its spawns and respawn, elites slower). Rare drops are counted apart ("+12g in rare drops"), never mixed in.
  Priciest or Per hour; rare spawns say so.
- **Dungeons per wing** (Dire Maul East/West/North, Stratholme Live/Undead, Lower/Upper Blackrock Spire, the four
  Scarlet Monastery wings): the steady gold of a run split five ways, rare drops apart.
- **Where to farm it, redesigned:** one answer first - the best way for you to get it, at your level - with its odds,
  gold an hour, spawns, solo or group; then a few other spots with odds bars; your own loot in one line. As tall as
  what it says. A world drop says so: any mob of the level, about 1 in N, and your level's best farm instead.
- The daily sources build reads cMaNGOS classic-db (GPL-3) too: spawns, respawns, coin and full loot tables.

## v0.55 - Drops and Dungeons

- **Farm it > Drops:** what mobs drop that sells for a gold or more - patterns, gear, rare reagents (the gathered
  staples stay in Materials) - each with the mob that drops it best, its zone, level and odds ("1 in 60"), and
  **rate unknown** for new Forever loot no one has counted yet (it still shows: being early is where it pays).
  Priciest first, or gold a kill. Tagged SOLO or GROUP (a dungeon or an elite). No world bosses, raids or
  battlegrounds; mobs well above your level sink. A price down 15% in a week says so: others found it.
- **Farm it > Dungeons:** every 5-man dungeon's average full clear (or the trash only) - its every mob, their loot
  tables and coin, from ForeverDB - priced with today's market (loot that can't be traded at what a vendor pays) and
  split five ways. The tooltip has what pays in it, the coin and a rough hour; run it with the session tracker on
  and your own gold an hour there replaces the guess. Click a dungeon: Drops, that dungeon only.
- Farm it's bar: Materials (their kind in a dropdown), Drops, Dungeons, Next week.
- The daily sources build (tools/sources/build.py) also writes Data/Dungeons.lua, and creatures carry their rank.

## v0.54 - small fixes

- **Calculator:** the item box suggests items as you type (the busiest first; Enter takes the top one). Buying and
  selling use today's price: when a newer price came since your last scan (the hourly prices, the Wolf network),
  your scan's listings are shifted to it before Wolf walks up them, and selling starts a copper under today's
  cheapest.
- **You:** the donut is a solid ring (no stripes or gaps), of your items only - where they are or how fast they
  sell. Your coins sit in the middle under the total of everything you own. Hover a slice: its gold and share show
  in the middle (no tooltip).
- **The folded tracker:** fold, pause and stop are one size and one look.
- **The logo:** the black wolf, brightened and its dark border trimmed, so it reads on the minimap.

## v0.53 - a new face

- **The logo is the game's own black wolf** (the Black Wolf mount icon), on the minimap button, in the window's
  header and in the addon list. Wolf ships no logo file of its own any more.
- **No banner over the window:** the header with the logo is the top of the window (it still drags it).

## v0.52 - Today about you, a cozier, lighter Wolf

- **Today is about you:** **Your movers** (what you own that moved with the last prices, and what it did in gold)
  and **While you were away** (what sold, what came back, what you bought since you last played, with the total
  sold) in place of Going up / Going down today. The market's gainers and losers stay on Market. The calendar shows
  the top three farms for next week (all of them in Farm it).
- **Market's home:** the value chart, and under it two lists, each on a switch: Top gainers / Top losers, and
  **Most traded** (where the most gold changes hands a day) / **Market Makers** (who lists the most).
- **Compact by default:** Wolf opens compact; Standard and Full screen are in Settings > Window size (the three
  buttons in the header are gone). Every page was checked at all three sizes and both text sizes: no text ends in
  "..." any more - long lines wrap, long verdicts take a third line.
- **The folded session tracker:** three short rows, about 160 wide; bigger pause and stop.
- **Lighter:** the old Sell page and the item window (unreachable since v0.42) and the hidden Radar list (worked out
  every hour, shown nowhere) are gone; the Wolf network's loot keeps 60 days and is looked up from an index; your
  node and chest log keeps the 300 you loot most; next week's calls are kept half an hour instead of worked out
  again on every price.

## v0.51 - the Calculator page, Raids and PvP, truer sources

- **Calculator**, its own page next to You: an item or none, how many, buying or selling, a price each. Buying an
  item walks up its listings; selling takes home what's left after the real cut. Beside it a **cheat sheet** of your
  last sums with running totals (buying, selling, net), kept between sessions: click a line to load it again, x to
  drop it, Wipe (click twice) to clear it. Item pages have a Calculator button.
- **Make gold is Flip it, Craft it, Farm it, Raids, PvP.** The Coming up page came apart: next week's best farms
  are Farm it's **Next week**; the raids' calls (how sure) are on **Raids**; **PvP** is new - the PvP kit studied
  like the raids (Forever's own sources first, each item says how sure), what to do around the battleground weeks
  (stock up the week before, sell into it) and the materials behind it. Today's calendar stays.
- **Today's calendar:** click an event for its page (a battleground week opens PvP, raid night Raids, the Faire
  its turn-ins); All of it shows four weeks.
- **Your best moves** add two rows: your listings someone undercut, and what to post tonight (what you hold that
  sells best in the next few hours).
- **How to learn it:** every craftable item's Craft it section says where its recipe is (a trainer, a vendor and
  where, a drop, Merchant's Favor) and its price on the auction house - or who of yours knows it.
- **Truer, shorter sources:** no chests or containers unless nothing else gives it; no vendors that aren't in the
  world; bosses and instance vendors say their instance; BoE gear says "World drop" first with Wowhead for the best
  rates; made items show only drops worth farming. Long lines wrap; hover a section for every line.
- **The session tracker, folded,** is small: the zone, the timer, the gold and gold an hour, with pause and stop
  on it. No "Session".
- **Fixed:** the craft window's last row ("Need it yourself?") sat lower than its label.

## v0.50 - Coming up, where everything comes from, the buy/sell calculator

- **Coming up** (Make gold, in place of Raid prep): this week's events (the Darkmoon Faire, a battleground's holiday
  week, the raids, the holidays), next week's best farms, what to hold or sell for the raids, the PvP kit in a
  battleground week, and Forever's content phases. Every call says how sure Wolf is - High from 75%, Medium from
  55%, Low below, the colour fading as it drops - from how often the same call was right on that item over its
  last 30 days (the hover shows the record). Calls under 40% aren't shown.
- **Today, redone:** a seven-day calendar on the left (click a day for what it pulls on; again for next week's
  farms) and one scrolling card on the right - your best asset first, then your best moves - in place of the three
  top cards. One chat line the day before an event.
- **Where everything comes from:** an item's page says where it's from - your loot, Wolf users' loot, mobs with
  their drop chance, nodes, skinning, vendors (your side), Merchant's Favor (Three Corners, the Crossroads),
  containers, quests, world drops - from ForeverDB and Wolf's own notes on Forever's new items. Every item that
  trades has a source. Crafted materials (Cured Rugged Hide, bars, bolts) say Craft it, with their timers: "needs
  Refined Deeprock Salt: every 3 days". The loot log now counts nodes and chests too, pooled over the Wolf network.
- **Buy/sell calculator** (the Market section's button): buying N walks up the listings - the total, the average,
  the dearest you'd pay; selling N takes home what's left after the auction house's real cut (read from your own
  sale letters) with the deposit, how fast yours sell, and what your N do to the price while they sit.
- **Smarter:** the vendor price floor ("a vendor sells it for 2s: never pay over that"), a propped-up price warning
  (a few listings by one seller holding it far over its usual), a PvP tag on what battlegrounds burn through, and
  farms that fit you (no skinning farm without a skinner, no mobs far over your level).
- **Craft it: Level it up** (the cheapest skill point first, from each recipe's colour) **and Worth learning**
  (recipes none of your characters know, for your professions, that profit and sell - with where to get each and
  how many crafts pay it back). Season of Discovery leftovers are gone from the recipes.
- **The bar:** Make gold and You keep their section bar in the same spot top left on every page.
- **A newer Wolf:** one chat line per new version, then quiet. Every Wolf network message carries its version, so
  the news gets round the guild.
- **Licence:** Wolf is now GPL v3, to carry ForeverDB's data. Credits in NOTICE and /wolf credits.

## v0.43 - search from anywhere, what you own live, where recipes come from

- **Search from any page:** a search box at the top of the window. The first letter takes you to Market and the
  typing goes on there. Wolf now always opens on Today.
- **What you own, live:** loot, mail, AH buys, crafts and gold show on Today and You (Holdings, the donut) as they
  happen. Listings on the auction house count in "Everything you own".
- **Picked up vs prices:** Today's "+12g with the last prices" is what the prices did, only; a second line says what
  you picked up (or spent) today. The first days, before a few updates are in, the line shows 14 days of what you
  hold and since yesterday comes from it.
- **Where a recipe comes from:** a craft's window says if the recipe is from a trainer, a merchant (name and zone,
  seen by you or a Wolf user in your guild or group) or a drop or quest, and whether it's on the auction house now and
  at what price. Click it for the recipe's Market page.
- **Market has its home back:** the Market tab opens on the overview (market mood, value listed, the week, top
  gainers and losers), and "< Market" on an item page goes back to it. The "I own" filter is "Owned".
- **Fixed:** a two-line verdict on an item page ran under When it sells. An item's Craft it section (its materials)
  shows again for anything craftable, not only recipes your characters know.

## v0.42 - Simple Wolf and the Wolf network

Wolf slimmed down for first-timers, tried out first in Wolf Lab.

- **Four tabs:** Today, Market, Make gold (Flip it, Craft it, Farm it, Raid prep) and You (Holdings, Sessions,
  Characters, Journal). Settings is behind the gear.
- **Today:** what everything you own is worth and what the last price update did to it ("+12g with the last
  prices"), since yesterday, a line of the last 24 updates; Your top 3; then In your bags, Going down today and
  Going up today, each scrolling.
- **Six verdicts everywhere:** BUY, SELL, HOLD, WAIT, CRAFT, FARM, one colour each. CASH OUT, HODL, APE IN and the
  rest only with Settings > Meme mode (now off to start).
- **Item pages read top to bottom:** the verdict and its reason first, one clean chart (7D / 30D / 90D), and beside
  it sections that fit the item - When it sells, Market, Price history, then Best crafts (it's made into things),
  Craft it (it's made: materials, cost, profit) and Where to farm (it's gathered). Watch, Wowhead and Share.
- **When it sells at a glance:** when to sell, when to buy, the busiest day and a 24-hour strip; the charts on
  request.
- **One freshness light:** "Prices 20 min old"; your scan and Blizzard's prices in its hover.
- **Where your gold sits:** a donut on You > Holdings - where it is, or how liquid. Click a slice for just that.
- **Session panel folds** to the gold and gold an hour.
- **A reminder** in chat when a newer Wolf or prices companion is out.
- **Gone:** the Pro chart, candles and averages, Market Makers, the stat cards, Search on AH, the second Wowhead and
  Where to farm entries in menus, Chart buttons in popups, the old item window. Long hold is in the Watch menu.
- **The Wolf network:** Wolf users in your guild and group share the prices that changed after a scan (taken at
  once, no /reload), what sold ("Wolf users sold 5 this week at ~20s" on the item page), farm rates per mob ("Wolf
  users: 0.33 a corpse") and watchlist deals (one chat line). A price far from what's known waits until a second
  user agrees. Settings > Exchange.

## v0.41 - when it sells: its price by the hour

- **Price by hour of the day** in When it sells: each hour's price against the item's usual, your clock, the
  priciest three hours in gold and the cheapest in blue, the hour it is now marked.
- **When to buy and post**, on its own line: "Cheapest 7p-10p (-4%): buy then · priciest 10a-1p (+5%): post just
  before 10a" - or that its price hardly moves through the day. The line above: when it sells most, the best day,
  the quietest hours.
- The price robot now keeps each item's price by the hour: the last 48 hours, and a running profile of every hour
  of the day (about two weeks each). It needs five looks at an hour before it shows it, so the price section fills
  in over the next few days.

## v0.40 - smarter sell or hold, Best crafts, Wowhead on the chart

- **Sell or hold reads history now.** In a weeks-old economy a steady climber always looked "higher than usual",
  so Wolf said sell. Now:
  - **Its climb:** a line through its daily prices. A new high where the line says it should be: HOLD ("On its
    climb, +15% a week for 20 days: let it ride"). Above even its climb: TRIM, sell a third, keep the rest. A climb
    that cracks (it fell, floods, stops selling): sell, as before.
  - **The raids ahead:** what the pre-raid list needs, what it's made of and what that's made of (Arcane Crystal ->
    Arcanite Bar -> the crafted raid gear). High before the raids: HOLD, sell into the run-up (Dec 5-8); in raid
    week: SELL into the demand.
  - **Endgame or leveling material:** in a young economy endgame materials (thorium, arcane crystals, runecloth,
    the high herbs) climb as more players reach 60 - sell a third, hold the rest; leveling materials fall as
    everyone levels past them - sell.
  - Each new rule is graded like the others (the price 5-9 days later) and switches itself off if it's wrong more
    often than right.
- **Best crafts** (was Best use): every finished product a material goes into, by what one of it brings or by the
  **best sellers** (what it's worth through the product times how many sell a day), with a Sold a day column.
  From an item's chart (Crafts when the row is tight) and from Where to farm.
- **Wowhead on the chart** where More was. The item popup showed nothing the Market page doesn't, so every item
  now opens on the Market page.

## v0.39 - where to farm

- **Raw mats** (Money page, was Farm): raw materials by what one farmer could sell of them a day. Click one for
  **Where to farm**: its price and how it sells, the spots for your level first (cloth from humanoids of the
  level with the thick camps named, leather from skinning beasts of the level, herbs and ore by zone with the
  skill they need, fire and earth elementals), your own numbers in each spot, the mobs you looted it from (per
  corpse, 5 corpses or more), and a Wowhead button. Click a spot or a mob for its Wowhead page.
- **Wolf learns your farming.** Every loot window is noted: the zone, what dropped, and the mob or node it came
  from (a skinned corpse isn't counted twice). Your time in a zone counts while you loot. Where to farm shows
  how many an hour you got there and your gold an hour, at today's prices.
- **Farm tips in chat** (Settings > Alerts, on): when a raw material for your level sells well (up 15%+ this
  week, 20+ sold a day) and you can get it (herbs, ore and leather only with the profession at its skill): one
  line with the zones and [Where to farm]. One tip in two hours at most, never in a dungeon, the same item not
  again for a day.
- **Wowhead links** to WoW Forever's pages (they were Classic's, which miss Forever's own items): a Wowhead button
  on the item window, Wowhead link in the right-click menu, Where to farm on a raw material's chart and on the
  overview's FARM IT card.
- The spots are how Classic hands materials out; Forever may differ, so what you loot yourself shows beside them.

## v0.38 - smarter lists, sharper charts, faster

- **Junk stays out.** Grey items, and white weapons, armor and odds and ends, no longer show in the Market list
  (All, Rising, Falling), the busiest list, the market mood or the most valuable listings. Search one by name, or
  watch or own it, and it's there.
- **TO THE MOON / RUG PULL need real sales.** A move counts only when the item sells: gear (the green items people
  list at random prices to test) needs 3+ listed, 4+ sales seen, about one sold every two days, and no more than
  double in a day; goods need 5+ listed and 3+ sold a day.
- **Charts:** crisp price labels that never run past the chart's edge or onto each other (at every text size), the
  high and low on small plates, no "-0".
- **Nothing cut short.** Long lines (the Market header, an item's tags, its sales line, the AH visit, When it
  sells) drop whole parts that don't fit instead of ending in "...". At the larger text sizes the side panel is a
  little wider and a material's name shrinks a point or two before it's ever cut. Tested at every size and look.
- **Faster.** Opening an item went from ~0.5 s to under 10 ms (the list no longer looks through all 7,000 items
  for the one you clicked, and draws once, not twice); the Market page ~1 s to ~10 ms; the watchlist ~0.3 s to a
  few ms. The sorted list, the market mood, your top 3 and the farm list are kept until something they're made of
  changes; new prices are read in the background a few ms a frame, and the list and overview redraw in separate
  frames. A millisecond test now times every page and job and fails anything over its budget.

## v0.37 - fix

- The "When it sells" button stayed on the screen after closing Wolf: it now belongs to the item's chart. The
  tests now look for any button left loose on the screen.

## v0.36 - watchlist groups, the AH visit, when it sells

- **Watchlist groups.** Watched items are grouped on the Market list's Watchlist: your own groups first (make,
  rename, remove them), the rest by kind (herbs, ore, consumables...). Click a group to fold it.
- **Watch materials.** An item's Watch button opens a menu: watch it, watch it with its materials (a group named
  after it), put it in a group, move it, remove it. The craft breakdown has a star on each material and Watch all.
- **Right-click** on the Market list opens that menu now; Settings > General can make it add/remove straight away
  again (off by default).
- **The Wolf tab at the auction house** (was Snipe): This visit - what you bought, posted and took off, each
  against its usual price, and the totals; Watchlist - your watched items as the live searches see them, with Buy
  on a deal; Deals - the snipe lists; Past visits - your last 30. One chat line when you walk away.
- **Watchlist deals, live.** While the auction house is open your watched items take turns in the live searches;
  one listed 15% or more under its usual price is said in chat with how many and [Buy them] (Settings > Alerts).
- **Buy under your price.** Posting: when some are listed under the price you're about to post at, a button buys
  them out first (stackable goods all at once; gear the cheapest, a click each).
- **When it sells.** On an item's chart: the last 48 hours hour by hour, the time of day it sells most (your clock)
  and the best day of the week, from the price robot's hourly looks. The hourly picture fills up over the next days.

## v0.35 - the breakdown beside the chart

- The craft breakdown shows on the item's page in every window size: beside the chart, or under it in the
  smallest window (where it used to take a click on More).
- The More window: solid, so the window under it no longer shows through its text; the breakdown gets the room
  it needs under the order book (or drops its last tips when there isn't any); wider, so material names fit;
  the line under the price is shorter and fits.

## v0.34 - the craft breakdown

- An item's page (click it in Futures, Market or anywhere) now has a **Craft breakdown** beside the chart for
  anything that's crafted - also when none of your characters knows the recipe (Flask of the Titans): each
  material with what it adds to one craft and its move this week; what one craft costs, what it sells for after
  the auction house's cut, the profit. Then what to do: worth crafting or not, which of your materials to hold
  (rising) or sell (falling), dips to buy, how many crafts your materials make, and the raid timing for raid
  consumables.

## v0.33 - the notes follow what's yours

- At login and /reload, chat starts with your portfolio and its change since last time (no more "The wolf"
  in front), then what moved in what you hold most and what you watch since you were last told: "Dreamfoil
  +12% · you hold 400 (+1,020g)", "Black Lotus -9% · on your watchlist, now 48g". Then the moves. Five lines at
  most. Nothing moved: your three biggest positions, steady, on the same line.
- After a scan of yours: "Fresh AH prices", what moved in yours - only if something did.
- A position is followed when it's one of your 8 biggest (50g or more); it's said when it moves 5% and 20g or
  more. Watched items: 8% or more.
- Futures > Key materials, Money lists, Snipe: the two lines of each row have more room (and grow with bigger
  text); stat cards stack their lines; the item page's price age sits clear of the price.

## v0.32 - tidy-up

- Futures > Key materials: "you hold" no longer runs into the 7-day change; the rows give bigger text room.
- Your top 3: each card's sentence gets two lines instead of being cut off.
- Charts: the axis numbers stay clear of the last-price tag, and the H / L marks of the dates.
- Market list: wider price and 24h columns (big prices and big moves fit).
- Shorter wording where it was cut off (market mood, "no one knows its recipe yet").
- /wolf curseforge: the link to the newest version.
- Behind the scenes: the tests now lay out every page, in both looks, at the smallest window and the largest text,
  and flag any text that runs into another or gets cut.

## v0.31 - Wolf, with a new face

- The addon is now just **Wolf**, with its own logo: in the header, the minimap button, the addon list and the
  prices companion. Nothing to redo: your settings, history and portfolio carry over (the folder is still
  WolfOfBootyBay), and /wolf works as before.

## v0.30 - mail to your bank alt, and the new prices companion

- Portfolio: what you mail to one of your own characters (a bank alt) stays in your net worth on the way, counted
  in that character's mail until it opens its mailbox. Gold in mailboxes and on the way counts too. Mail to anyone
  else leaves, as before.
- The prices companion is now a real Windows app: WolfPricesSetup.exe, a setup window, installs without admin
  rights, starts with Windows, uninstalls from Settings > Apps, updates itself. It never shows a notification
  (safe on stream). Installing it stops and removes the old script version.
- In game: when you open the auction house and the companion has newer prices waiting, chat says so with a
  [Load them] link. The API chip reads "API: new" then (click: load them). No companion yet: one line, once, on
  where to get it.

## v0.29 - on CurseForge

- The addon is on CurseForge: search "Wolf of Booty Bay" in the CurseForge app. Each new version goes there by
  itself; CurseForge checks every file before it shows up.
- Hourly prices come from the prices companion (Settings > About > Prices companion), whatever installed the
  addon. The hints no longer send you to WowUp.

## v0.28 - your faction's auction house only

- Blackwater, the neutral auction house, isn't followed any more: its prices arrive too late to act on (whoever is
  standing there snipes first). No switching to it, no AH TO AH deals, no "sell it at the other house", and the
  price robot no longer fetches it. At a neutral auctioneer Wolf of Booty Bay stays offline and says so once.
- Buying to hold for a rise (Futures, buy the dip) is unchanged: it's about your own house.

## v0.27 - clearer words, buy the dip

- Terminal cards: the label no longer runs into the gold; the gold is just the number.
- SLIDING is now DROPPING, CARRY IT is now AH TO AH (buy at one auction house, sell at the other).
- The wolf always says what it sees: no more "Still getting to know you" - its best guess from whatever is there
  (gatherer, crafter, trader, collector, saver), worked out in the background after login, plus what you're into.
- Futures: the construction tape sits on the title now, not across the page. WAIT is gone: moves read STEADY,
  NO RECIPE, NONE LISTED - and BUY THE DIP when something on the raid list (or a key material in several of its
  consumables) fell this week with the raids still ahead. HOLD (HODL) stays for what you hold.

## v0.26 - Futures: what raiders will need

- The Radar becomes Futures (still under construction): the pre-raid study as a ranked list of what raiders across
  every class are expected to use before the 9 December raids, against today's market.
- Consumables: 34 items ranked by how many raiders use how much (Major Mana first, Greater Fire Protection for
  Onyxia, the role elixirs, the new Natural flasks...), each with who uses it, how sure the study is, price and
  7-day change, what it's made of, and your move: craft it (a character of yours knows it), hold what you have
  for raid week, buy it while it's cheap, or watch it (no one makes the Natural flasks yet).
- Key materials beside it: what most of the list is made of (Dreamfoil goes into 12), with your move - hold what
  you gathered, sell in raid week, stock up if you craft with it, gather it if your profession picks it.
- Gear: the crafted pre-raid BiS pieces by how many specs want them (Dawn Armor: 8), and whether you can make them.
- The wolf's top 3 always keeps one raid move before the raids: hold your herbs, or the best raid craft you know.

## v0.25 - the Eye: the wolf knows what you've got

- The wolf works out what kind of player you are, with no questions: every character's professions and skill,
  what you hold everywhere, what you gather (all the time now, not only in sessions), what you bought and sold at
  the auction house, your watchlist. "The wolf sees" on the Terminal says it in one line.
- Your top 3 on the Terminal: moves about you, each with its reason in the hover - sell what's high (how many, at
  what), what's sliding, a big move on something you hold, a watched item under its usual price, what your own
  characters can craft from what you hold (a miner's ore into bars too), the best thing to gather for your
  professions, a flip your gold covers if you trade. Nothing you can't do: no craft no character of yours knows.
  Short of three, today's market moves fill in.
- In chat, rarely: once after login (when prices, bags and crafts are known) and after a real auction house visit,
  up to three moves, each once a day. Replaces the old recap, sell pings and market banners.
- No more pop-up alerts on screen, ever (the setting is gone).

## v0.24 - smoother, cleaner Terminal

- Search: every word you type is matched as a part of the name, in any order ("thor ore" finds Thorium Ore).
  Item names load quietly in the background after login and are kept, so a search finds them the first time.
- The Terminal list: category, subcategory and sort moved into the Filter popup; what's set shows as chips
  under the list's top row (× clears it), and the Filter button counts them. Column titles still sort.
- Ticker: no longer jumps back to the start when prices refresh; it stops under the mouse so an item is easy to
  click (Settings: "Keep the ticker moving under the mouse").
- Crafting no longer lags the window: a craft used to re-read every recipe and rebuild every profit; now only a
  real recipe change does, and bag changes wait until you stop crafting.
- To the moon / Rug pulls never come up empty: checked again once sales are known, and the looser list shows
  meanwhile.
- Farm it: what each sells for and how many sell a day, ranked by what one farmer could make (not the whole
  market's trade).
- Radar moved to the last tab, marked work in progress, with a construction sign.
- Classic look: the title banner's text sits in the middle of the banner.

## v0.23 - the classic auction house look

- New look, the default: the game's own auction house style everywhere. Windows and dialogs get the game's
  stone-and-gold dialog edge and its title banner, panels the gold tooltip edge, buttons are the game's red ones
  (gold label, white under the mouse), the pages are the game's tabs, inputs and check boxes the game's own, labels
  gold, the wolf in a round portrait, the red X to close. Square corners, the game's green and red.
- The dark terminal stays: Settings > General (and Basics) > Look > Dark terminal, after a reload.
- Each piece falls back to the dark look's own if this client lacks the game's version of it.

## v0.22 - Radar, Snipe, a cleaner chart

- Radar (new page, between Money and Portfolio): demand forming, from the market itself. Sales speeding up (the
  last 3 days against the week before) while the price holds and supply doesn't pile up - Early before the price
  moves, Moving, Late; Chains: what a rising craft is made of (every recipe of the game) while its own price
  hasn't moved; Cooling: what's slowing down. The next announced event on top (raids open 12/9: consumables
  usually climb before). Early calls are written down and graded 5-9 days later (its record in the header).
  The price robot now ships what sold each day for the last two weeks (a day's worth each, days watched under
  6 hours left out) - the Radar needs a few days of them.
- Snipe: the auction house tab is Snipe now (inside the auction house with Auctionator's tab library, beside it
  without). After a scan: Underpriced now (fresh prices under their real price less the deal margin, not being
  dumped or pushed up, gear and what hardly sells left out unless a vendor pays more; over 80% off says "check the
  listing"), each Safe / Good / Gamble with why, and Buy (the cheap ones of a fresh order book, up to two days of
  sales; the server's price, your click). Often underpriced: items whose deep dips came back most times (from the
  daily learning). Re-check searches both lists again without a full scan; To Auctionator.
- Chart (simple): 7D / 30D / 90D, one smooth line with a soft glow and finer fill, its high and low marked, a dot
  following the mouse, no vertical lines or dashed last-price line. Pro chart unchanged.
- Dates the American way everywhere: 11/25/26, 11/25 3 pm.
- Price card: 7 days, 30 days and vs usual on their own lines (no more "..."), one record under them.
- Money and Craft for profit: the lists made ahead (Craft for profit now too) take half the frame time (2 ms);
  only a page waiting for its list gets the full share.
- Session gold an hour: from 10 minutes in (a lucky first minute made it huge); its hover shows the rate without
  your single best find.

## v0.21.1 - tooltip under Auctionator's

- Our tooltip lines sit right under Auctionator's (Vendor / Auction / Disenchant), above other addons' lines (bag
  counts, drop sources): "Wolf API  8g 05s  1h", then what to do (CASH OUT, HODL...) with today's move, then a
  craft's profit or what it disenchants for. Moved only when it's safe (Auctionator's lines found, no icons in the
  lines that move down); otherwise at the bottom as before.
- No more "Best use" line in tooltips (the Best use button on an item's page stays).

## v0.21 - the prices companion, tidier sessions

- Wolf prices companion (companion/, Windows): a tray app. Every 15 minutes it reads a small note of when the
  newest prices are from (releases/latest/download/latest.json) and, when they're newer than the addon's, downloads
  the price file into the addon folder and says so ("/reload to load them"); its hover shows what the game has
  loaded (from the addon's saved data) and what's ready. Finds World of Warcraft by itself (else asks once),
  offers to start with Windows, one copy at a time, a log in %APPDATA%\WolfPrices. Every release now carries
  Feed.lua, latest.json and WolfPrices.zip. Settings > About > Prices companion links it.
- Tooltips say where our price is from and how old: "8g · API 1h", "· your scan 12m", "· Auctionator 2d" - so it
  can't be taken for Auctionator's own line. A saved Blizzard price read back after a /reload still says API.
- TO THE MOON: a jump with what's listed thinned out (the cheap ones bought to be relisted) is tagged "pushed up?",
  and its banner says it may not hold.
- Money: deals are worked out in the background a minute after login (never in a fight), disenchant deals too, so
  the page isn't blank when opened; while looking it says "Finding deals... 40%".
- Sessions: an opened session shows Qty, Then, Now and Change (what the stack gained or lost since it was found);
  right-click a session to rename or delete it (asked first). Questions can take a typed answer (UI.Confirm input).

## v0.20.1 - fixes from the first in-game pass

- Portfolio: clicking a group's header didn't close it (the click called a function defined further down the
  file: an error, quietly). Fixed; the load test clicks a header.
- The right-click menu's two frames had lost their `local` in v0.17.4 and were globals named `menu` and
  `menuBlock` (a name another addon could use). Local again. The static audit now fails on a name read as a
  global that its own file declares as a local, and on any global written but the saved data and slash commands.
- The ticker tape keeps moving under the mouse.

## v0.20 - one price everywhere

- The session panel valued loot after the auction house's 5% cut (or at a vendor's price when that was higher),
  while tooltips and the Portfolio show the market price: the same item read two ways. Now every place uses the
  market price; a vendor's only when the auction house has none, and an item with no price anywhere says so
  ("2 items have no price yet") instead of counting as nothing.
- The price is the newest one known: your scans and the Blizzard API, and now Auctionator's too when its day is
  newer than ours (it used to count only when we had nothing).
- Where a price is from, in the same words everywhere: Shift on a tooltip and a hover on a session row say
  "Blizzard API, 3:05 pm (1h ago)", "your AH scan", "Auctionator scan" or "saved prices".
- Session panel: scroll with the mouse wheel (a thin bar shows there's more), drag the corner for 3 to 14 rows
  (remembered), hover a row for worth each when found and now, click it for the item; the newest loot shows
  as "+3 Thorium Ore" for a few seconds and lights up in the list.
- Settings > Chat commands: every /wolf command and what it does (the rare way: all have a button somewhere).
  /wolf help prints the same list.

## v0.19 - a pickier engine, a calmer item page

Engine (the broker's checks):
- Every flip is replayed on the item's price history (its own, else its kind's): did a dip this deep come back
  within 3 days? Across the market only 30% did (3,146 of 10,450), so flips of kinds where it mostly didn't are
  no longer shown. Flips also need 2+ sales a day seen for a day or more, sell at the lower of the fair price and
  the recent average, and no more than two days of sales are suggested.
- New checks: pushed up (a jump with the cheap ones bought out: a reset) and dumped (a pile of new listings with
  the price falling). Neither is shown as a deal or a buy.
- Carries need sales seen at the other house; disenchant deals value the materials at their average when that's
  lower (a spike doesn't count), skip materials that hardly sell and need 20% over the price.
- Every deal shows its worst case (what you'd lose if it doesn't sell and goes at its 30-day low, or to a vendor)
  and its record ("worked 9/11").
- Buying: a cheap price on an item whose dips kept falling, or that is still sliding, says WAIT (was BUY): on the
  test prices, 1,726 of 3,000 buy calls became 47.
- Sell yours: a lone lot or two far under the next price is treated as bait: list at the real wall instead.

Screens:
- Item page: under the chart, Market (healthy / thin / stagnant / flooded / pushed up / dumped, sales a day, days
  to sell out), Price (where it's going, 7 and 30 days, its record) and The call (what to do, how sure, its
  record), with Long hold, Share and Recipe on it. Price alerts and the order book are gone; the materials of a
  craft stay on the right.
- Portfolio: holdings in groups (Materials, Crafted, BoE gear, Other) with count, worth and share; click to open
  or close (remembered).
- Sessions: click a past session for what you found: how many, worth each then and now, gold looted. Prices when
  found are kept from this update on.
- Money: the empty Cash out now / Worth crafting columns (left over from an old view) are gone.
- Craft for profit: no "recipe needed" on every line; the ones you know say so.
- Signal badges shrink their text to fit (DIAMOND HANDS no longer spills out).

## v0.18 - fresher Blizzard prices, honest messages

- The price robot kept the newest 12 releases by a date that is the same for every hourly build, so it deleted
  new releases at random, often the one it had just made: WowUp never saw those prices. Fixed (by publish time).
- The robot looks at Blizzard every 15 minutes and publishes only when Blizzard has refreshed its data (about
  hourly). GitHub often ran the hourly check 1-2 hours late; now a late run costs minutes.
- No more reload reminder: the addon can't see what's been downloaded until a reload, so it was guessing.
  After a login or /reload, one chat line: "New prices loaded: Blizzard, 3:05 pm", or, when newer ones could
  exist, "Same prices as last time". The API chip shows the time of your prices (yellow past two hours).
- The prices last loaded are kept in the saved data (for the coming companion app).

## v0.17.4 - right-click menu

- Right-clicking the minimap button only offers Start a session, or Stop the session while one runs. The page
  links are gone (a left-click opens the window); pause is on the session panel and /wolf farm pause.

## v0.17.3 - names, not tickers

- Items go by their names again everywhere: the TO THE MOON / RUG PULLS lists, the market list, the item page,
  the tooltip, the craft window, shared tips, the login recap and sell pings. The $THOR-style tickers stay on the
  scrolling tape at the top, as decoration.
- A small 7-day trend line beside each item in the two mover lists and in Portfolio holdings, green or red by
  the week's move.

## v0.17.2 - minimap button

- Click: open / close the window. Right-click: the session tracker menu (start, pause, stop, its worth so far).
  The same on broker bars.

## v0.17.1 - Terminal fixes

- Today's 3 moves: the texts were drawn under the card's own background (only the icon showed); empty slots
  showed a red "?" icon. The card is its own background now, an empty slot has no icon, and a slot without a
  carry, flip or farm move takes the best craft, buy-to-disenchant or vendor deal.
- Market Makers: no list of its own; the top sellers by gold listed are in the hover of the Listed value card.
  The two mover lists get the room back and show the ticker and the name again.

## v0.17 - performance pass

Measured in the fake WoW with real prices (tools/test), longest single frame of each piece of work at login:
- TO THE MOON / RUG PULL check: 192 ms -> 3.5 ms. The biggest movers are worked out once per market build, in
  the background (M.PrepareMovers: cheap tests first, the costly real-market check only until 40 are found each
  way), not on every redraw of the Terminal and the tape.
- Blizzard prices: read lazily. One quick pass keeps each item's text; an item is decoded when asked for and
  forgotten when nothing holds it; daily lows only when a chart asks. Was ~100 ms in one frame and ~7 MB parsed;
  the take into history reads them a little each frame.
- Background work gets 4 ms of each frame (2 in a fight), down from 8: loading in stays smooth. Market build's
  worst frame 23 -> 9.5 ms.
- The scorecard's daily calls are written down a little each frame; the "its kind" learning starts 2 minutes
  after login and never in a fight.
- Disenchant values: weapon/armor told without asking the server; only items the game already has are looked
  at (no flood of item requests when Make gold opens).
- Delayed tasks report what they cost in /wolf perf.
- Memory after login: 26.9 MB -> 23.7 MB (and far less garbage while loading in).

## v0.16.2 - Sessions on its own

- Sessions is a tab of its own (Terminal, Money, Portfolio, Sessions); Portfolio's Sessions view is gone.
- The minimap button: a click opens the menu (start, pause or stop a session - with its worth so far - open or
  close the window, the pages); a right-click opens or closes the window right away. The same for broker bars.
- /wolf sessions opens it; /wolf farm still starts and stops one.

## v0.16.1 - fixes from the game

- Fixed: Craft for profit and disenchant values threw errors ("Craft.lua:545: attempt to call a nil value"):
  WoW Forever has no global GetItemInfo / GetItemInfoInstant, only C_Item's. Every call goes through
  FT.GetItemInfo / FT.GetItemInfoInstant now. The same fix makes the "its kind" learning (herbs, ore...) work in
  game: it quietly never did. The fake WoW the tests run in has only the C_Item ones too now.
- Terminal lists (TO THE MOON / RUG PULLS / Market Makers): the ticker in place of the name (the name is in the
  hover), one-unit prices ("20s"), whole-number changes, columns that grow with the text size; nothing past the
  box's edge.
- A list's "nothing here" text stays inside a narrow list (wrapped).

## v0.16 - Blizzard prices fixed, Craft for profit for every profession

- Fixed: Blizzard's prices didn't load when the game's region id or realm wasn't one the feed knew. The house is
  now found by: Settings > Basics > Realm type (new, Auto by default), the realm's name, its id, Auctionator's
  name for its price list ("PvP Alliance"), and last the one house of your side the feed carries. A region id the
  feed doesn't know falls back to the only region in it.
- When they still can't load: the API chip says why (and opens Settings), and one chat line at login.
- API chip: how old the prices are and when they were taken, how old this copy is; the status bar shows both
  ages (Blizzard API, your AH scan), the one in use green.
- Craft for profit: every profession's recipes whoever knows them, the best of selling the product or
  disenchanting it (CRAFT + DE, with the enchanting skill it needs); products whose sales aren't watched yet count
  at half, tagged. A profession picker and Every recipe / Ones you know. Your crafters' professions and skills on
  the line above (read at each character's login).

## v0.15.1 - our own branding

- A wolf for the minimap button, the header, item windows and the AddOns list (was the original's gold coin).
- Every on-screen trace of ForeverTrading gone (the Credits button and link, the welcome note, the AddOns-list
  notes and author); the original's credit stays in NOTICE and LICENSE in the addon's folder, and /wolf credits.
- Guild price sharing and version news on our own addon channels (the old ones were the original addon's).

## v0.15 - sessions and a scorecard

- Sessions: start from the minimap button's right-click menu (or Portfolio > Sessions, /wolf farm). Counts your
  own loot lines (loot, items pushed into your bags, gold looted; not mail, trades, auction buys or crafts), valued
  at today's prices (AH after its cut, else a vendor). A small movable panel: time, worth, gold an hour, the best
  loot; pause, stop. AFK pauses it; a /reload or relog keeps it (time logged out doesn't count). Portfolio >
  Sessions lists your runs by gold an hour, the loot on hover.
- Minimap (and broker) right-click: a menu - start/pause/stop a session, the pages, settings.
- Scorecard: every day the calls on what you own, your watchlist and the busiest 400 markets are written down
  with their price, and graded 5-9 days later (sold before a drop, held through a rise, waited for a dip that came
  back...). A rule's record sets how sure its calls are and shows on the item ("Likely, right 7 of 10"); an
  optional rule under 35% over 10+ calls switches off. Market history seeds the first records.
- Market recap at login; Good day to sell pings (once a day per item, 3 at most); Share (a line for guild chat,
  sent by you); To Auctionator (Make gold deals, a craft's materials) as an Auctionator shopping list; This week on
  the Terminal (kinds whose items peak on the same weekday).

## v0.14 - disenchanting

- Classic's disenchant odds (greens by item level: dust, essence, a shard; blues: a shard, Nexus Crystal at
  56+; purples: Nexus Crystal), weapons giving more essence than armor. Forever's may differ.
- Value of disenchanting an item: its materials at auction house prices after the cut, when the likely ones are
  priced.
- Gear tooltips: "Disenchant it: ~1.2g (sells for 40s)" or "Sell it: 2.1g beats disenchanting (~1.2g)".
- Make gold: DE IT deals, gear listed under what it breaks into (15%+ profit), for the best enchanting skill
  among your characters (read at login); the odds on hover.

## v0.13 - Craft for profit

- Money > Craft for profit: every recipe (known and not) whose product sells every day (3+ sales seen, 1+ a day),
  by profit x crafts a day (up to 20; cooldown crafts like Mooncloth and transmutes once every few days). Worked
  out in the background, kept until new prices. "Ones you know" filter; recipes you don't know say so.
- Craft window: every material (AH, vendor or crafted yourself), cost, sells for, profit, and crafting vs buying
  it ready-made.
- Make gold rows in plain words: buy for X, sell for Y, +Z each, how many, how fast it sells ("sells in ~2 days",
  "slow: ~9 days"), what it costs against your gold (over a third: yellow; more than you have: red, and last).
- The audit fails on lowercase globals (a local used before it's declared).

## v0.12 - tickers

- Ticker symbols for every item ($THOR, $ACRY, $RUGG...), made from the name; on the tape, the Terminal's lists, the
  item's title and its tooltip.
- The tape: your watchlist, then what you own (most valuable first), then the day's movers.
- Terminal overview: Today's 3 moves (best carry, flip and farm, with the gold each should make) and Your
  portfolio (worth and today's change) in place of Last scan.

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
