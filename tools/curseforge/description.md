# Wolf: the WoW Forever auction house as a stock market

Wolf watches every price on the WoW Forever auction house and tells you, in plain English, how to make gold: what to buy, what to sell, what to craft, what to farm, and what's coming up next week.

---

## Install (two steps)

**1. The addon.** Install Wolf with the CurseForge app (or WowUp). Updates arrive on their own.

**2. Hourly prices (Windows, recommended).** Get the Wolf prices companion: [WolfPricesSetup.exe](https://github.com/PetcoWoW/ForeverTrading/releases/download/companion/WolfPricesSetup.exe). Run it and click **Install**. It keeps Wolf's prices fresh every hour, even for items you never scanned.

- Windows may say "Windows protected your PC" the first time: click **More info**, then **Run anyway**.
- It installs for your Windows user only (no admin rights) and starts with Windows if you leave that ticked.
- Not on Windows? Wolf still works: your own scans and other Wolf users in your guild keep the prices fresh.

Restart the game fully the first time (new addons load at launch, not on `/reload`), then type `/wolf`.

---

## What's inside

**Today**: what everything you own is worth and what the last prices did to it, a calendar of what's coming (the Darkmoon Faire, battleground weeks, the raids), your best moves (including listings someone undercut and what to post tonight), what you own that moved, and what sold while you were away.

**Market**: the market's mood, its value over time, the top gainers and losers, the most traded items and the biggest sellers. Search any item: the verdict comes first, then one clean chart, when it sells best, where it comes from (mobs, nodes, vendors, Merchant's Favor, quests), and what it costs to craft and where to learn the recipe.

**Make gold**

- **Flip it**: deals worth buying and relisting.
- **Craft it**: what your recipes make in profit, a craft queue with the shopping list, the cheapest way to level a profession, and recipes worth learning (with where to get them).
- **Farm it**: the best things to farm for your level and professions, and where; Next week shows the best farms ahead.
- **Raids**: what raiders will burn through, ranked, with your move on each and how sure Wolf is (High, Medium, Low) from its own track record.
- **PvP**: the battleground kit (potions, bombs anyone can throw, their materials), and when to stock up before a battleground week.

**You**: Holdings across all your characters (bags, bank, mail, listings, gold), Sessions (gold an hour), Characters and a Journal of everything you bought and sold.

**Calculator**: what buying or selling any amount comes to (it walks up the listings and takes off the auction house's cut), with a cheat sheet that keeps your last sums.

Every call is one of six verdicts, one colour each: **BUY**, **SELL**, **HOLD**, **WAIT**, **CRAFT**, **FARM**.

---

## The Wolf network

Wolf users in the same guild or group share, in hidden addon messages:

- prices that changed after a scan (no `/reload` needed)
- what sold, and at what price
- farm rates and loot (which mob, node or chest gave what)
- watchlist deals (one chat line)

A price far from what's known waits until a second user agrees, so one bad scan can't fool everyone. Turn it off in Settings > Exchange.

---

## Safe on stream

No pop-ups, no sounds. Wolf only ever speaks in a chat line: a deal from your guild, a reminder the day before an event, a newer version (once). The session tracker folds down to one small bar.

---

## Good to know

- `/wolf` opens the window (compact; Standard and Full screen are in Settings). `/wolf news` shows what's new.
- Don't run ForeverTrading at the same time: two scanners do the same work twice.
- The prices companion only touches Wolf's own price file. No accounts, no game memory, nothing sent anywhere. Remove it in Windows Settings > Apps > Wolf prices.

---

## Credits

Wolf is free software under the GNU GPL v3.

- Built on [ForeverTrading](https://github.com/thewoolfi/ForeverTrading) by thewoolfi (Apache License 2.0).
- Where items come from: [ForeverDB](https://github.com/foreverfraddons/forever-db), with data from QuestieDB, VMaNGOS, cMaNGOS, AllTheThings, pfQuest and the [Drop Tables](https://github.com/valcheffnet/DropTables) contributors (CC BY-SA 4.0).
- Full credits in the addon (`/wolf credits`) and in NOTICE.

Source code, the price robot and every release: [github.com/PetcoWoW/ForeverTrading](https://github.com/PetcoWoW/ForeverTrading)
