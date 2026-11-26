Wolf prices - the companion of Wolf
=====================================================

Download WolfPricesSetup.exe from the "companion" release and run it. It finds World of Warcraft and the addon,
installs for your Windows user only (no admin rights), and sits by the clock.

Every 15 minutes it fetches Blizzard's newest prices into the addon folder. No notifications, no sounds, no
windows. In game, chat tells you at the auction house when newer prices are waiting ([Load them] reloads).

This folder is its source (C#, .NET Framework 4.8). .github/workflows/companion.yml builds it on Windows, tests it
against a pretend game folder, and publishes it. Settings and log: %APPDATA%\WolfPrices.
