-- Wolf: Radar - the raids' calendar (FT.Radar.Next, .Pull): what Raids and the calls read. Once also:
--  * Demand rising: sales speeding up (the last 3 days against the week before, from the price robot's daily
--    sales) while the price holds or climbs and what's listed doesn't pile up - real buying, not a pump (a pump
--    is a price jump without the sales). Early while the price has hardly moved yet, late once it has.
--  * Chain: a crafted item whose demand rises pulls on what it's made of (Data/Recipes.lua) - its materials are
--    flagged while their own price hasn't moved yet: they tend to follow days later.
--  * Cooling: what sold well slowing down (for what you hold).
--  * The calendar: dates Blizzard has announced (raid openings): consumables tend to climb before them.
-- It grades itself: an Early call is written down with its price and checked 5-9 days later (up 5%+ = right).
local ADDON, FT = ...
local L = FT.L

local R = {}
FT.Radar = R

local MIN_RECENT = 3    -- sold a day lately, at least (smaller markets move on noise)
local SPEED_UP = 2      -- the last 3 days sell this many times the week before
local SLOW_DOWN = 0.5
local MAX_ROWS = 40

-- Dates Blizzard has announced (Forever's roadmap). kinds: item classes:subclasses that tend to climb before it
-- (0:1 potions, 0:2 elixirs, 0:3 flasks, 0:5 food); ids: items its fights are known to need.
local CALENDAR = {
    { t = time({ year = 2026, month = 12, day = 9, hour = 12 }), name = "Raids open: Barrow Deeps, Hyjal Summit, Onyxia's Lair",
      kinds = { ["0:1"] = true, ["0:2"] = true, ["0:3"] = true, ["0:5"] = true },
      ids = { [13457] = "Onyxia breathes fire", [6049] = "Onyxia breathes fire", [13461] = "fire resistance" } },
}
R.CALENDAR = CALENDAR

-- the next event within 4 weeks: { t, name, days }, or nil
function R.Next()
    local now = time()
    for _, e in ipairs(CALENDAR) do
        if e.t > now and e.t - now <= 28 * 86400 then
            return { t = e.t, name = e.name, days = math.ceil((e.t - now) / 86400), kinds = e.kinds, ids = e.ids }
        end
    end
    return nil
end

-- an event's pull on an item: a few words, or nil
local function EventPull(id, ev)
    if not ev then return nil end
    if ev.ids and ev.ids[id] then return ev.ids[id] end
    local kind = FT.An.KindOf(id)
    if kind and ev.kinds and ev.kinds[kind] then return L["raid consumable"] end
    return nil
end
R.Pull = EventPull

-- (v0.51: the rest of the old Radar - its own list of rising demand, worked out after every price file and shown
-- nowhere since v0.42 - is gone. Its calendar stays: Raids and the calls read it.)
