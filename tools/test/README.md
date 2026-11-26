# Checks outside the game

- `node tools/test/audit.js .` (needs `luaparse`): FT./UI. functions called but never defined, globals written,
  every global read. It fails (exit 1) on a name read as a global that the same file declares as a local (used above its
  declaration: nil there), on lowercase globals, and on any global written other than the saved data and slash commands.
- `python3 tools/test/loadtest.py . [path/to/Data/Feed.lua]` (needs `lupa`): loads every file in TOC order in a
  fake WoW (`wowmock.lua`), logs in, opens every tab and view, runs scans (ours and Auctionator's), learns, logs
  out, does it all again after a /reload, and prints every error. Pass a release's `Data/Feed.lua` for real prices.
