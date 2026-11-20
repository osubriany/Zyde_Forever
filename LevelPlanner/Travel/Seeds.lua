-- Seeds: hand-written starting data for the travel graph. Written for LevelPlanner from general game
-- knowledge (not copied from any addon). Coordinates are APPROXIMATE map percentages (0-100) on the
-- given uiMapID. LevelPlanner also learns real zone crossings as you walk, and those win over these.
--
-- Zones whose map was redrawn on Forever (Mulgore, Redridge, Stormwind, Eastern Plaguelands) are
-- avoided: crossings into them are written on the neighbouring zone's map instead.
local ADDON, zyde = ...
-- Part of Zyde_Forever since 2026-11-14: LevelPlanner keeps its own private table (zyde.LP) so its
-- names never clash with Zyde's.
zyde.LP = zyde.LP or {}
local ns = zyde.LP

local Seeds = {}
ns.TravelSeeds = Seeds

-- uiMapIDs (Forever / Classic)
local DUROTAR, BARRENS = 1411, 1413
local ARATHI, BADLANDS, BLASTED, TIRISFAL, SILVERPINE, WPL, EPL, HILLSBRAD, HINTERLANDS =
	1417, 1418, 1419, 1420, 1421, 1422, 1423, 1424, 1425
local DUNMOROGH, BURNING, ELWYNN, DEADWIND, DUSKWOOD, LOCH, REDRIDGE, STV, SWAMP, WESTFALL, WETLANDS =
	1426, 1428, 1429, 1430, 1431, 1432, 1433, 1434, 1435, 1436, 1437
local TELDRASSIL, DARKSHORE, ASHENVALE, NEEDLES, STONETALON, DESOLACE, FERALAS, DUSTWALLOW, AZSHARA, FELWOOD =
	1438, 1439, 1440, 1441, 1442, 1443, 1444, 1445, 1447, 1448
local MULGORE, ALTERAC = 1412, 1416

-- Zone crossings: the point is on `map`; the crossing joins `map` and `other`.
-- pass = true shows the crossing as its own step ("Go through Thandol Span").
Seeds.crossings = {
	-- Eastern Kingdoms
	-- passes with "exit": two ends, so the arrow leads to the entrance on your side first
	{ name = "Thandol Span", map = WETLANDS, x = 51.0, y = 9.0, other = ARATHI, pass = true,
		exit = { map = ARATHI, x = 43.5, y = 91.5 } },
	{ name = "Dun Algaz", map = WETLANDS, x = 53.0, y = 70.5, other = LOCH, pass = true,
		exit = { map = LOCH, x = 20.0, y = 17.0 } },
	{ name = "Dun Morogh / Loch Modan pass", map = DUNMOROGH, x = 84.0, y = 50.5, other = LOCH },
	{ name = "Elwynn / Westfall bridge", map = ELWYNN, x = 21.0, y = 80.5, other = WESTFALL },
	{ name = "Three Corners", map = ELWYNN, x = 92.0, y = 72.0, other = REDRIDGE },
	{ name = "Elwynn / Duskwood road", map = ELWYNN, x = 74.0, y = 93.5, other = DUSKWOOD },
	{ name = "Westfall / Duskwood road", map = DUSKWOOD, x = 8.0, y = 64.0, other = WESTFALL },
	{ name = "Duskwood / Stranglethorn road", map = STV, x = 38.0, y = 3.5, other = DUSKWOOD },
	{ name = "Redridge / Burning Steppes", map = BURNING, x = 80.0, y = 68.0, other = REDRIDGE },
	{ name = "Duskwood / Deadwind Pass", map = DUSKWOOD, x = 88.0, y = 42.0, other = DEADWIND },
	{ name = "Deadwind Pass / Swamp of Sorrows", map = SWAMP, x = 3.5, y = 62.0, other = DEADWIND },
	{ name = "Swamp of Sorrows / Blasted Lands", map = BLASTED, x = 64.0, y = 12.0, other = SWAMP },
	{ name = "Loch Modan / Badlands", map = LOCH, x = 46.5, y = 77.0, other = BADLANDS },
	{ name = "Tirisfal / Silverpine road", map = TIRISFAL, x = 50.0, y = 72.0, other = SILVERPINE },
	{ name = "Silverpine / Hillsbrad road", map = HILLSBRAD, x = 13.5, y = 46.0, other = SILVERPINE },
	{ name = "Hillsbrad / Alterac road", map = HILLSBRAD, x = 59.0, y = 22.0, other = ALTERAC },
	{ name = "Thoradin's Wall", map = ARATHI, x = 18.5, y = 31.0, other = HILLSBRAD },
	{ name = "Arathi / Hinterlands", map = HINTERLANDS, x = 9.5, y = 59.0, other = ARATHI },
	{ name = "Hillsbrad / Hinterlands", map = HINTERLANDS, x = 3.5, y = 47.5, other = HILLSBRAD },
	{ name = "The Bulwark", map = TIRISFAL, x = 83.5, y = 69.0, other = WPL },
	{ name = "Western / Eastern Plaguelands", map = WPL, x = 69.0, y = 50.0, other = EPL },
	-- Kalimdor
	{ name = "Durotar / Barrens bridge", map = DUROTAR, x = 34.5, y = 42.5, other = BARRENS },
	{ name = "Barrens / Mulgore road", map = BARRENS, x = 34.0, y = 62.0, other = MULGORE },
	{ name = "Mor'shan Rampart", map = BARRENS, x = 48.5, y = 5.5, other = ASHENVALE },
	{ name = "Barrens / Stonetalon road", map = BARRENS, x = 34.0, y = 27.0, other = STONETALON },
	{ name = "Barrens / Dustwallow road", map = DUSTWALLOW, x = 29.5, y = 47.5, other = BARRENS },
	{ name = "The Great Lift", map = BARRENS, x = 44.5, y = 91.0, other = NEEDLES, pass = true,
		exit = { map = NEEDLES, x = 32.0, y = 22.0 } },
	{ name = "Darkshore / Ashenvale road", map = DARKSHORE, x = 43.5, y = 93.0, other = ASHENVALE },
	{ name = "Talondeep Path", map = ASHENVALE, x = 42.0, y = 71.5, other = STONETALON, pass = true,
		exit = { map = STONETALON, x = 78.0, y = 42.5 } },
	{ name = "Ashenvale / Felwood road", map = ASHENVALE, x = 56.0, y = 29.0, other = FELWOOD },
	{ name = "Ashenvale / Azshara road", map = ASHENVALE, x = 93.5, y = 37.0, other = AZSHARA },
	{ name = "Stonetalon / Desolace road", map = DESOLACE, x = 55.0, y = 6.0, other = STONETALON },
	{ name = "Desolace / Feralas road", map = DESOLACE, x = 43.0, y = 96.0, other = FERALAS },
	{ name = "Feralas / Thousand Needles", map = FERALAS, x = 90.0, y = 45.0, other = NEEDLES },
}

-- Boats, zeppelins, tram. Each end is either a spawn of a known NPC (preferred: exact position from
-- Questie, checked by name) or the fallback coordinates. faction nil = everyone.
Seeds.transports = {
	{ kind = "boat", faction = "Alliance", a = { name = "Menethil Harbor", map = WETLANDS, x = 5.0, y = 63.5 },
		b = { name = "Theramore", map = DUSTWALLOW, x = 71.6, y = 56.4 } },
	{ kind = "boat", faction = "Alliance", a = { name = "Menethil Harbor", map = WETLANDS, x = 4.6, y = 57.1 },
		b = { name = "Auberdine", map = DARKSHORE, x = 32.4, y = 43.8 } },
	{ kind = "boat", faction = "Alliance", a = { name = "Auberdine", map = DARKSHORE, x = 33.2, y = 40.2 },
		b = { name = "Rut'theran Village", map = TELDRASSIL, x = 54.9, y = 96.8 } },
	{ kind = "boat", faction = nil, a = { name = "Booty Bay", map = STV, x = 25.8, y = 73.1 },
		b = { name = "Ratchet", map = BARRENS, x = 63.7, y = 38.6 } },
	-- Forever: the goblin ferry between Powderfuse Port (Riverglades) and Steamwheedle Port (Tanaris).
	-- Both ends approximate (Riverglades guides; one Tanaris source).
	{ kind = "boat", faction = nil, a = { name = "Powderfuse Port", map = 2548, x = 80.6, y = 54.6 },
		b = { name = "Steamwheedle Port", map = 1446, x = 68.6, y = 23.0 } },
	-- Forever: the Old Dinghy by Menethil Harbor's fishing trainer to Newman's Landing (Dun Morogh's
	-- west coast). Menethil end approximate: next to Harold Riggs.
	{ kind = "boat", faction = nil, a = { name = "Menethil Old Dinghy", map = WETLANDS, x = 8.0, y = 58.4 },
		b = { name = "Newman's Landing", map = DUNMOROGH, x = 18.0, y = 74.5 } },
	{ kind = "zeppelin", faction = "Horde",
		a = { name = "Orgrimmar zeppelins", map = DUROTAR, x = 50.9, y = 13.8, npc = 9564, npcName = "Zapetta" },
		b = { name = "Undercity zeppelins", map = TIRISFAL, x = 60.7, y = 58.8, npc = 9566, npcName = "Frezza" } },
	{ kind = "zeppelin", faction = "Horde",
		a = { name = "Orgrimmar zeppelins", map = DUROTAR, x = 50.6, y = 12.6, npc = 3149, npcName = "Nez'raz" },
		b = { name = "Grom'gol", map = STV, x = 31.6, y = 29.1, npc = 12136, npcName = "Snurk Bucksquick" } },
	{ kind = "zeppelin", faction = "Horde",
		a = { name = "Undercity zeppelins", map = TIRISFAL, x = 61.9, y = 59.1, npc = 3150, npcName = "Hin Denburg" },
		b = { name = "Grom'gol", map = STV, x = 31.6, y = 29.1, npc = 12136, npcName = "Snurk Bucksquick" } },
	-- The Deeprun Tram ends come from Questie's dungeon entrances at run time (see Graph.lua).
}

Seeds.DEEPRUN_TRAM_AREA = 2257
