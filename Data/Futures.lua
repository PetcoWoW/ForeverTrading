-- Wolf of Booty Bay: the pre-raid study as data (the Futures page). What raiders across every class are expected to
-- use before the first raids (9 December 2026), from the guide sites that check against the Forever database
-- (RankedBoost, Method, the Warcraft wiki, Icy Veins) and the crafted pre-raid lists (Frostyboost), cross-checked:
-- one site alone is a guess. The study: "WoW Forever pre-raid study - what raiders will need" (26 Nov 2026).
-- Prices, trends and materials are never written here: they come live from the market and the recipe data.
--   rank: 1 = what the most raiders burn the most of   roles: who uses it   uses: how many a raider goes through
--   on a raid night   conf: confirmed (several sources) / likely (one strong source) / unknown (recipe or numbers
--   not published)   raids: where it matters most, when only some   note: one line on why
local ADDON, FT = ...

FT.FUTURES = {
    studied = "2026-11-26",
    consumables = {
        { id = 13444, rank = 1, roles = "casters, healers, hunters", uses = 4, conf = "confirmed", note = "Every raid, several a night" },
        { id = 13457, rank = 2, roles = "everyone", uses = 2, conf = "confirmed", raids = "Onyxia", note = "The only prep Blizzard confirmed: fire resistance for Onyxia" },
        { id = 13454, rank = 3, roles = "casters", uses = 2, conf = "confirmed", note = "Every caster's spell damage elixir; stacks with a flask" },
        { id = 13452, rank = 4, roles = "agility melee, hunters", uses = 2, conf = "confirmed", note = "Rogues, ferals and hunters, every night" },
        { id = 250351, rank = 5, roles = "strength melee", uses = 2, conf = "confirmed", note = "New: replaces Greater Strength; Honored with Merchant's Favor to make" },
        { id = 250333, rank = 6, roles = "healers", uses = 2, conf = "confirmed", note = "New: +40 healing; Friendly with Merchant's Favor to make" },
        { id = 274274, rank = 7, roles = "melee, hunters, casters, healers", uses = 1, conf = "unknown", raids = "Hyjal, Barrow Deeps", note = "New: crit, only in the Hyjal raids; recipe source unknown, no one makes it yet" },
        { id = 274275, rank = 8, roles = "melee, tanks", uses = 1, conf = "unknown", raids = "Hyjal, Barrow Deeps", note = "New: less dodged and parried in the Hyjal raids; Method's pick for Fury" },
        { id = 274273, rank = 9, roles = "melee, hunters, casters", uses = 1, conf = "unknown", raids = "Hyjal, Barrow Deeps", note = "New: hit in the Hyjal raids; Method's pick for Combat rogues" },
        { id = 274276, rank = 10, roles = "melee, hunters, casters, healers", uses = 1, conf = "unknown", raids = "Hyjal, Barrow Deeps", note = "New: haste in the Hyjal raids; recipe source unknown" },
        { id = 13512, rank = 11, roles = "casters", uses = 1, conf = "confirmed", note = "The caster flask (Black Lotus)" },
        { id = 13510, rank = 12, roles = "tanks, melee", uses = 1, conf = "confirmed", note = "The tank and melee flask (Black Lotus)" },
        { id = 13511, rank = 13, roles = "healers", uses = 1, conf = "confirmed", note = "The healer flask (Black Lotus)" },
        { id = 250943, rank = 14, roles = "melee, hunters", uses = 2, conf = "confirmed", note = "New: +80 attack power for 30 sec; Method lists it for rogues" },
        { id = 250937, rank = 15, roles = "casters", uses = 2, conf = "confirmed", note = "New: +47 spell damage for 30 sec" },
        { id = 13446, rank = 16, roles = "everyone", uses = 2, conf = "confirmed", note = "Now made with First Aid, not Alchemy" },
        { id = 9264, rank = 17, roles = "shadow casters", uses = 2, conf = "confirmed", note = "Warlocks and shadow priests; a guide suggests it for Barrow Deeps" },
        { id = 250341, rank = 18, roles = "healers", uses = 1, conf = "confirmed", note = "New: 20 mana every 5 sec" },
        { id = 250337, rank = 19, roles = "casters, healers", uses = 2, conf = "confirmed", note = "New: +25 intellect, +2% crit" },
        { id = 250329, rank = 20, roles = "tanks", uses = 1, conf = "confirmed", note = "New: +400 health, +500 armor" },
        { id = 13458, rank = 21, roles = "everyone", uses = 1, conf = "likely", raids = "Barrow Deeps", note = "Nature threats per one guide; not confirmed" },
        { id = 13459, rank = 22, roles = "everyone", uses = 1, conf = "likely", raids = "Barrow Deeps", note = "Shadow threats per one guide; not confirmed" },
        { id = 250949, rank = 23, roles = "healers", uses = 2, conf = "confirmed", note = "New: +88 healing for 30 sec; few on the market" },
        { id = 13442, rank = 24, roles = "warriors", uses = 2, conf = "confirmed", note = "Rage and strength in one" },
        { id = 250350, rank = 25, roles = "rogues, ferals", uses = 1, conf = "confirmed", note = "Strength and agility; not with Mongoose" },
        { id = 246948, rank = 26, roles = "melee", uses = 1, conf = "confirmed", note = "New: +35 attack power" },
        { id = 13455, rank = 27, roles = "tanks", uses = 1, conf = "confirmed", note = "+2,000 armor for 2 min" },
        { id = 249870, rank = 28, roles = "healers", uses = 2, conf = "confirmed", note = "Food: +44 healing" },
        { id = 20452, rank = 29, roles = "strength melee", uses = 2, conf = "confirmed", note = "Food: +20 strength" },
        { id = 250072, rank = 30, roles = "agility melee, hunters", uses = 2, conf = "confirmed", note = "Food: +20 agility" },
        { id = 13933, rank = 31, roles = "casters", uses = 2, conf = "confirmed", note = "Food: spell damage" },
        { id = 250068, rank = 32, roles = "tanks", uses = 2, conf = "confirmed", note = "Food: +20 stamina" },
        { id = 12643, rank = 33, roles = "melee (blunt)", uses = 2, conf = "confirmed", note = "Weapon buff; the sharpening stones and oils of Classic aren't on the market yet" },
        { id = 250328, rank = 34, roles = "hunters", uses = 1, conf = "confirmed", note = "Agility and intellect; one or Mongoose" },
    },
    -- the crafted pre-raid BiS pieces: how many specs' lists name each (one source so far: Frostyboost)
    gear = {
        { id = 252483, specs = 8, who = "Fury, all Hunters, all Rogues, Shockadin", slot = "Chest" },
        { id = 19169, specs = 4, who = "Arms, Ret, Enhancement, Survival", slot = "Two-hand" },
        { id = 18510, specs = 4, who = "Holy Paladin, Disc and Holy Priest, Resto Shaman", slot = "Back" },
        { id = 252605, specs = 4, who = "all Hunters, Enhancement", slot = "Head" },
        { id = 12640, specs = 3, who = "Fury, Arms, Ret", slot = "Head" },
        { id = 252484, specs = 3, who = "Arms, Ret, Enhancement", slot = "Chest" },
        { id = 279263, specs = 3, who = "Prot Warrior, Prot and Shockadin Paladin", slot = "Feet" },
        { id = 18282, specs = 3, who = "all Hunters", slot = "Ranged" },
        { id = 14146, specs = 3, who = "Arcane, Fire, Shadow Priest", slot = "Hands" },
        { id = 22384, specs = 2, who = "Fury, Combat", slot = "One-hand" },
        { id = 14152, specs = 2, who = "Arcane, Fire", slot = "Chest" },
        { id = 250619, specs = 2, who = "BM and MM Hunter", slot = "Two-hand" },
        { id = 14140, specs = 2, who = "Disc and Holy Priest", slot = "Head" },
        { id = 14154, specs = 2, who = "Disc and Holy Priest", slot = "Chest" },
        { id = 19047, specs = 2, who = "Disc and Holy Priest", slot = "Waist" },
    },
}
