-- The price feed: replaced in every release by tools/feed/build.mjs (hourly, .github/workflows/feed.yml) with the
-- prices of every WoW Forever auction house. Empty in the source code: the addon then goes by its own scans.
local ADDON, FT = ...
FT.FEED = FT.FEED or nil
