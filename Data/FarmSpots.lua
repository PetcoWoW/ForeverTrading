local _, FT = ...

-- Where to farm raw materials: Wolf's own list, from how Classic hands them out (cloth from humanoids by their
-- level, leather from skinning beasts by theirs, herbs and ore from the zones of their skill) and the best-known
-- spots. Classic's: WoW Forever may differ - what you loot yourself (FT.Farm's log) shows next to it and counts
-- more. Written for Wolf; no other addon's data.
--
-- [itemID] = { kind, skill (herbs, ore: the skill to gather it), spots = { { zone, lo, hi, what }, ... } }
-- lo-hi: the level of what you kill there (or the zone's, for gathering).

local S = {}
FT.FarmSpots = S

local function Add(ids, kind, skill, spots)
    for _, id in ipairs(ids) do S[id] = { kind = kind, skill = skill, spots = spots } end
end

-- cloth: any humanoid of the level drops it (the camps below are the thick ones)
Add({ 2589 }, "cloth", nil, {
    { "Westfall", 10, 18, "Defias at the farms and Moonbrook" },
    { "The Barrens", 10, 20, "Kolkar centaurs and Razormane quilboar" },
    { "Tirisfal Glades", 5, 12, "Scarlet Crusade at Solliden Farmstead and the Monastery road" },
    { "Loch Modan", 10, 18, "Stonesplinter troggs" },
    { "Silverpine Forest", 10, 20, "Moonrage gnolls and Dalaran wizards" },
    { "Darkshore", 11, 20, "Blackwood furbolgs" },
})
Add({ 2592 }, "cloth", nil, {
    { "Redridge Mountains", 16, 25, "Blackrock orcs and Redridge gnolls" },
    { "Wetlands", 20, 28, "Dragonmaw orcs and Mosshide gnolls" },
    { "Hillsbrad Foothills", 20, 30, "Hillsbrad farmers and Syndicate" },
    { "Ashenvale", 18, 28, "Foulweald furbolgs and Dark Strand cultists" },
    { "Stonetalon Mountains", 18, 26, "Venture Co. at Windshear Crag" },
    { "The Barrens", 20, 26, "Bael'dun dwarves and Razorfen quilboar" },
    { "Duskwood", 20, 30, "Nightbane worgen and Defias" },
})
Add({ 4306 }, "cloth", nil, {
    { "Alterac Mountains", 30, 38, "Syndicate and Crushridge ogres" },
    { "Arathi Highlands", 28, 36, "Syndicate at Northfold Manor and Boulderfist ogres" },
    { "Stranglethorn Vale", 30, 36, "Kurzen camps in the north" },
    { "Thousand Needles", 26, 34, "Galak centaurs and Grimtotem" },
    { "Desolace", 30, 37, "Magram and Gelkis centaurs" },
    { "Scarlet Monastery", 30, 40, "the Monastery's wings (dungeon)" },
})
Add({ 4338 }, "cloth", nil, {
    { "Stranglethorn Vale", 38, 45, "Bloodsail pirates, Venture Co. and Skullsplitter trolls" },
    { "Badlands", 37, 44, "Dark Iron and Shadowforge dwarves" },
    { "Tanaris", 41, 46, "Wastewander bandits and Southsea pirates" },
    { "Feralas", 41, 46, "Gordunni ogres and Woodpaw gnolls" },
    { "The Hinterlands", 42, 50, "Witherbark and Vilebranch trolls" },
    { "Dustwallow Marsh", 36, 42, "Theramore deserters and Grimtotem" },
    { "Arathi Highlands", 36, 40, "Syndicate at Stromgarde" },
    { "Zul'Farrak", 44, 54, "the trolls (dungeon)" },
})
Add({ 14047 }, "cloth", nil, {
    { "Felwood", 47, 54, "Deadwood furbolgs" },
    { "Winterspring", 53, 57, "Winterfall furbolgs" },
    { "Eastern Plaguelands", 53, 60, "Scourge and the Scarlet Crusade" },
    { "Western Plaguelands", 51, 58, "Scarlet Crusade at Hearthglen and the Scourge" },
    { "Burning Steppes", 50, 58, "Blackrock orcs" },
    { "Silithus", 55, 60, "Twilight's Hammer camps" },
    { "Stratholme", 58, 60, "the undead side (dungeon)" },
})
Add({ 14256 }, "cloth", nil, {
    { "Felwood", 49, 56, "Jadefire satyrs and Jaedenar's Shadow Council" },
    { "Azshara", 53, 58, "Haldarr and Legashi satyrs" },
    { "Dire Maul", 55, 60, "the satyrs of the east wing (dungeon)" },
})

-- leather and hides: skinning beasts of the level (any you can skin)
local LIGHT = {
    { "The Barrens", 10, 20, "zhevras, plainstriders and kodo calves" },
    { "Westfall", 10, 18, "coyotes and boars" },
    { "Darkshore", 11, 20, "bears, nightsabers and thistle boars" },
    { "Loch Modan", 10, 18, "bears and boars" },
    { "Silverpine Forest", 10, 20, "wolves and bears" },
}
local MEDIUM = {
    { "The Barrens", 18, 25, "kodos and hyenas in the south" },
    { "Wetlands", 20, 28, "crocolisks and raptors" },
    { "Hillsbrad Foothills", 20, 30, "bears and mountain lions" },
    { "Stonetalon Mountains", 18, 27, "pumas and wolves" },
    { "Ashenvale", 18, 30, "bears, wolves and nightsabers" },
}
local HEAVY = {
    { "Arathi Highlands", 30, 38, "raptors and highland striders" },
    { "Stranglethorn Vale", 30, 40, "panthers, tigers and raptors" },
    { "Desolace", 30, 38, "kodos, hyenas and thunder lizards" },
    { "Thousand Needles", 25, 35, "cougars and pterrordaxes" },
    { "Dustwallow Marsh", 35, 42, "crocolisks and raptors" },
}
local THICK = {
    { "Stranglethorn Vale", 40, 45, "raptors and tigers in the south" },
    { "Feralas", 40, 48, "yetis, hippogryphs and gorillas" },
    { "Tanaris", 40, 48, "hyenas and basilisks" },
    { "The Hinterlands", 42, 50, "owlbeasts, wolves and silvermane stalkers" },
    { "Un'Goro Crater", 48, 52, "the raptors at the edges" },
}
local RUGGED = {
    { "Un'Goro Crater", 48, 55, "raptors, stegodons and devilsaurs" },
    { "Winterspring", 53, 60, "frostsabers, bears and chimaeras" },
    { "Felwood", 48, 55, "bears and wolves" },
    { "Eastern Plaguelands", 53, 60, "plaguehounds and bats" },
    { "Burning Steppes", 50, 58, "worgs and black dragonkin-hounds" },
}
Add({ 2318, 783, 2934 }, "leather", nil, LIGHT)
Add({ 2319, 4232 }, "leather", nil, MEDIUM)
Add({ 4234, 4235 }, "leather", nil, HEAVY)
Add({ 4304, 8169 }, "leather", nil, THICK)
Add({ 8170, 8171 }, "leather", nil, RUGGED)
Add({ 15417 }, "leather", nil, {
    { "Un'Goro Crater", 52, 55, "devilsaurs (they wander: elite)" },
})

-- herbs: the zones they grow in, and the Herbalism they need
local function Herb(id, skill, zones)
    local spots = {}
    for _, z in ipairs(zones) do spots[#spots + 1] = { z[1], z[2], z[3], nil } end
    Add({ id }, "herb", skill, spots)
end
local Z = {
    start = { { "Elwynn Forest", 1, 10 }, { "Durotar", 1, 10 }, { "Teldrassil", 1, 10 }, { "Tirisfal Glades", 1, 10 }, { "Dun Morogh", 1, 10 }, { "Mulgore", 1, 10 } },
    low = { { "The Barrens", 10, 25 }, { "Westfall", 10, 20 }, { "Darkshore", 10, 20 }, { "Silverpine Forest", 10, 20 }, { "Loch Modan", 10, 20 } },
}
Herb(2447, 1, Z.start)
Herb(765, 1, Z.start)
Herb(2449, 15, Z.start)
Herb(785, 50, Z.low)
Herb(2450, 70, Z.low)
Herb(2453, 100, { { "The Barrens", 15, 25 }, { "Wetlands", 20, 30 }, { "Redridge Mountains", 15, 25 }, { "Ashenvale", 18, 30 }, { "Stonetalon Mountains", 15, 27 }, { "Hillsbrad Foothills", 20, 30 } })
Herb(3820, 85, { { "Wetlands", 20, 30 }, { "Westfall", 10, 20 }, { "Darkshore", 10, 20 }, { "Stranglethorn Vale", 30, 45 } })
Herb(3355, 115, { { "Wetlands", 20, 30 }, { "Arathi Highlands", 30, 40 }, { "Stonetalon Mountains", 15, 27 }, { "Hillsbrad Foothills", 20, 30 }, { "Thousand Needles", 25, 35 } })
Herb(3369, 120, { { "Duskwood", 18, 30 }, { "The Barrens", 20, 25 }, { "Wetlands", 20, 30 }, { "Desolace", 30, 40 } })
Herb(3356, 125, { { "Wetlands", 20, 30 }, { "Hillsbrad Foothills", 20, 30 }, { "Ashenvale", 18, 30 }, { "Duskwood", 18, 30 }, { "Arathi Highlands", 30, 40 }, { "Stranglethorn Vale", 30, 45 } })
Herb(3357, 150, { { "Wetlands", 20, 30 }, { "Arathi Highlands", 30, 40 }, { "Hillsbrad Foothills", 20, 30 }, { "Stranglethorn Vale", 30, 45 }, { "Swamp of Sorrows", 35, 45 } })
Herb(3818, 160, { { "Arathi Highlands", 30, 40 }, { "Stranglethorn Vale", 30, 45 }, { "Swamp of Sorrows", 35, 45 }, { "Dustwallow Marsh", 35, 45 }, { "Alterac Mountains", 30, 40 } })
Herb(3821, 170, { { "Arathi Highlands", 30, 40 }, { "Stranglethorn Vale", 30, 45 }, { "The Hinterlands", 40, 50 }, { "Feralas", 40, 50 }, { "Dustwallow Marsh", 35, 45 } })
Herb(3358, 185, { { "Arathi Highlands", 30, 40 }, { "Stranglethorn Vale", 30, 45 }, { "The Hinterlands", 40, 50 }, { "Feralas", 40, 50 }, { "Alterac Mountains", 30, 40 } })
Herb(3819, 195, { { "Alterac Mountains", 30, 40 } })
Herb(4625, 205, { { "Searing Gorge", 43, 50 }, { "Badlands", 35, 45 }, { "Tanaris", 40, 50 }, { "Blasted Lands", 45, 55 } })
Herb(8831, 210, { { "Tanaris", 40, 50 }, { "Feralas", 40, 50 }, { "The Hinterlands", 40, 50 }, { "Azshara", 45, 55 }, { "Stranglethorn Vale", 30, 45 } })
Herb(8836, 220, { { "Felwood", 48, 55 }, { "Western Plaguelands", 51, 58 }, { "Eastern Plaguelands", 53, 60 } })
Herb(8838, 230, { { "The Hinterlands", 40, 50 }, { "Feralas", 40, 50 }, { "Felwood", 48, 55 }, { "Un'Goro Crater", 48, 55 }, { "Azshara", 45, 55 } })
Herb(8839, 235, { { "Swamp of Sorrows", 35, 45 }, { "Un'Goro Crater", 48, 55 } })
Herb(8845, 245, { { "The Hinterlands", 40, 50 }, { "Un'Goro Crater", 48, 55 }, { "Desolace", 30, 40 } })
Herb(8846, 250, { { "Felwood", 48, 55 }, { "Desolace", 30, 40 }, { "Ashenvale", 18, 30 }, { "Blasted Lands", 45, 55 } })
Herb(13464, 260, { { "Un'Goro Crater", 48, 55 }, { "Felwood", 48, 55 }, { "Azshara", 45, 55 }, { "Silithus", 55, 60 }, { "Burning Steppes", 50, 58 } })
Herb(13463, 270, { { "Un'Goro Crater", 48, 55 }, { "Felwood", 48, 55 }, { "Azshara", 45, 55 }, { "Silithus", 55, 60 }, { "Winterspring", 53, 60 } })
Herb(13465, 280, { { "Winterspring", 53, 60 }, { "Un'Goro Crater", 48, 55 }, { "Azshara", 45, 55 }, { "Burning Steppes", 50, 58 }, { "Silithus", 55, 60 } })
Herb(13466, 285, { { "Eastern Plaguelands", 53, 60 }, { "Western Plaguelands", 51, 58 }, { "Felwood", 48, 55 } })
Herb(13467, 290, { { "Winterspring", 53, 60 } })
Herb(13468, 300, { { "Burning Steppes", 50, 58 }, { "Winterspring", 53, 60 }, { "Eastern Plaguelands", 53, 60 }, { "Silithus", 55, 60 } })

-- ore and stone: the zones of the veins, and the Mining they need (a stone comes from its ore's veins)
local function Ore(ids, skill, zones)
    local spots = {}
    for _, z in ipairs(zones) do spots[#spots + 1] = { z[1], z[2], z[3], nil } end
    Add(ids, "ore", skill, spots)
end
Ore({ 2770, 2835 }, 1, { { "Elwynn Forest", 1, 10 }, { "Durotar", 1, 10 }, { "Westfall", 10, 20 }, { "The Barrens", 10, 25 }, { "Loch Modan", 10, 20 }, { "Darkshore", 10, 20 } })
Ore({ 2771, 2836 }, 65, { { "Wetlands", 20, 30 }, { "Redridge Mountains", 15, 25 }, { "Ashenvale", 18, 30 }, { "Stonetalon Mountains", 15, 27 }, { "Hillsbrad Foothills", 20, 30 }, { "Duskwood", 18, 30 } })
Ore({ 2775 }, 75, { { "Wetlands", 20, 30 }, { "Redridge Mountains", 15, 25 }, { "Stonetalon Mountains", 15, 27 }, { "Hillsbrad Foothills", 20, 30 } })
Ore({ 2772, 2838 }, 125, { { "Arathi Highlands", 30, 40 }, { "Alterac Mountains", 30, 40 }, { "Desolace", 30, 40 }, { "Thousand Needles", 25, 35 }, { "Stranglethorn Vale", 30, 45 }, { "Badlands", 35, 45 } })
Ore({ 2776 }, 155, { { "Arathi Highlands", 30, 40 }, { "Stranglethorn Vale", 30, 45 }, { "Badlands", 35, 45 }, { "Desolace", 30, 40 } })
Ore({ 3858, 7912 }, 175, { { "Badlands", 35, 45 }, { "Searing Gorge", 43, 50 }, { "The Hinterlands", 40, 50 }, { "Tanaris", 40, 50 }, { "Felwood", 48, 55 }, { "Azshara", 45, 55 }, { "Un'Goro Crater", 48, 55 } })
Ore({ 7911 }, 230, { { "Searing Gorge", 43, 50 }, { "Badlands", 35, 45 }, { "Tanaris", 40, 50 }, { "Un'Goro Crater", 48, 55 }, { "Felwood", 48, 55 } })
Ore({ 10620, 12365 }, 245, { { "Un'Goro Crater", 48, 55 }, { "Winterspring", 53, 60 }, { "Burning Steppes", 50, 58 }, { "Eastern Plaguelands", 53, 60 }, { "Silithus", 55, 60 }, { "Azshara", 45, 55 } })
-- Arcane Crystal: a rare find in thorium veins (the more you mine, the more you see)
Ore({ 12363 }, 245, { { "Un'Goro Crater", 48, 55 }, { "Winterspring", 53, 60 }, { "Burning Steppes", 50, 58 }, { "Eastern Plaguelands", 53, 60 }, { "Silithus", 55, 60 } })
Ore({ 11370 }, 230, { { "Blackrock Depths", 52, 60 }, { "Burning Steppes", 50, 58 } })

-- elementals: kill them
Add({ 7068, 7077, 7078 }, "elemental", nil, {
    { "Searing Gorge", 43, 50, "fire elementals" },
    { "Burning Steppes", 50, 58, "fire elementals and blazing elementals" },
})
Add({ 7067 }, "elemental", nil, {
    { "Badlands", 37, 45, "rock elementals" },
})
