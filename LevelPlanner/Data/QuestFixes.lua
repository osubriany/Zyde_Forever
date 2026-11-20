-- QuestFixes: quest details Questie is missing on Forever, filled in by hand.
-- The planner uses an entry only where Questie has nothing: a quest giver, a turn-in, or the
-- objectives (where to kill, collect or go). Anything Questie does know is left as it is.
--
-- Sources: Wowhead's WoW Forever database (giver / turn-in / mob spawn points) and, for objectives
-- Wowhead can't map, written walkthroughs. Coordinates are zone map percent (0-100), keyed by zone
-- (area) ID like Questie's own data: [area] = { {x, y}, ... }. Mob spawns are listed as found;
-- the planner picks the densest cluster itself.
--
-- Each entry:
--   name        quest name (for reading this file; the game's own name is used in game)
--   start       { name = "NPC", spawns = { [area] = { {x, y} } } }      -- who gives it
--               or { drop = true, name = "Mob", ids = { ... }, spawns = ... }  -- starts from an item these drop
--   finish      { name = "NPC", spawns = { ... } }                       -- who takes it back
--   objectives  list of
--     { kind = "kill", name = "Mob", count = n, ids = { npcId, ... }, spawns = { ... } }
--         kill these (count: how many; omitted = read from the quest text, else a default)
--     { kind = "loot", name = "Mob", ids = { ... }, spawns = { ... } }
--         kill these for a quest item
--     { kind = "spot", name = "What to do there", seconds = n, spawns = { [area] = { {x, y} } } }
--         go to this spot (place / use / fight something there); one entry per spot
--     { kind = "objects", name = "Thing", count = n, spawns = { ... } }
--         click / loot things lying around (herbs, crates)
--   replace     true: use `objectives` even though Questie has its own (one item that takes several steps)
--   items       { [itemId] = one of the objectives above, or { kind = "have" } }
--         where a quest item comes from, when Questie lists the item but not its source
--         ("have": you're given it with the quest, nothing to fetch)
-- Added 2026-11-19. To add one: look the quest up, add an entry, /reload.
local ADDON, zyde = ...
zyde.LP = zyde.LP or {}
local ns = zyde.LP

ns.QuestFixes = {
	-- Valuable Vantages (Horde, Hillsbrad): place the three Apothecary Vials on peaks.
	-- Spots from Sportskeeda's walkthrough.
	[98095] = {
		name = "Valuable Vantages",
		objectives = {
			{ kind = "spot", name = "Place a vial: hills behind Dun Garok", spawns = { [267] = { { 74.2, 73.5 } } } },
			{ kind = "spot", name = "Place a vial: plateau NE of Durnholde Keep", spawns = { [267] = { { 71.6, 30.0 } } } },
			{ kind = "spot", name = "Place a vial: top of The Headland", spawns = { [267] = { { 38.6, 94.1 } } } },
		},
	},

	-- Blood of My Blood (Swamp of Sorrows): slay 10 Lost Ones in the Fallow Sanctuary.
	[93429] = {
		name = "Blood of My Blood",
		start = { name = "Karana", spawns = { [8] = { { 24.8, 32.4 }, { 26.2, 32.4 }, { 26.8, 33.0 } } } },
		finish = { name = "Karana", spawns = { [8] = { { 24.8, 32.4 }, { 26.2, 32.4 }, { 26.8, 33.0 } } } },
		objectives = {
			{ kind = "kill", name = "Lost Ones", count = 10, ids = { 759, 760, 761, 762 }, spawns = { [8] = {
				-- Lost One Hunter
				{ 54.4, 30.2 }, { 55.4, 28.8 }, { 56.4, 25.2 }, { 57.2, 24.4 }, { 57.6, 23.4 }, { 58.2, 26.6 },
				{ 61.4, 22.4 }, { 61.8, 22.6 }, { 62.4, 23.8 }, { 62.6, 23.4 }, { 64.4, 23.4 }, { 64.8, 20.8 },
				{ 64.8, 22.0 }, { 65.6, 21.4 },
				-- Lost One Muckdweller
				{ 55.2, 28.1 }, { 56.2, 31.6 }, { 57.5, 29.8 }, { 58.2, 23.6 }, { 59.0, 24.4 }, { 60.2, 26.4 },
				{ 61.2, 25.2 }, { 61.6, 20.4 }, { 62.4, 18.8 }, { 63.4, 21.0 }, { 64.0, 17.2 }, { 64.4, 20.4 },
				{ 64.6, 25.0 }, { 66.4, 17.6 },
				-- Lost One Seer and Riftseeker
				{ 59.4, 21.4 }, { 60.0, 22.4 }, { 60.6, 20.6 }, { 61.0, 24.4 }, { 61.6, 22.8 }, { 64.4, 19.8 },
				{ 64.6, 22.6 }, { 65.2, 19.2 }, { 60.8, 23.2 }, { 61.8, 20.8 }, { 64.2, 23.6 }, { 65.0, 20.6 },
			} } },
		},
	},

	-- Reclaiming Ravencrest (Azshara): Spitelash Battlemasters and Enchantresses.
	[88812] = {
		name = "Reclaiming Ravencrest",
		objectives = {
			{ kind = "kill", name = "Spitelash Battlemaster and Enchantress", ids = { 7885, 7886 }, spawns = { [16] = {
				{ 65.4, 76.8 }, { 66.0, 77.8 }, { 66.4, 82.8 }, { 67.0, 82.6 }, { 67.8, 83.4 }, { 68.4, 82.4 },
				{ 69.0, 82.2 }, { 69.2, 83.4 }, { 69.6, 82.6 }, { 69.8, 84.4 }, { 70.4, 81.4 }, { 70.4, 85.4 },
				{ 70.6, 85.4 }, { 71.2, 85.8 }, { 71.6, 85.6 }, { 72.6, 85.0 }, { 73.4, 86.4 }, { 70.4, 87.4 },
				{ 65.4, 91.4 }, { 66.0, 91.2 }, { 66.4, 89.4 }, { 67.0, 90.4 }, { 67.8, 91.2 }, { 69.2, 91.2 },
				{ 69.4, 90.4 }, { 69.6, 90.6 }, { 70.4, 89.4 }, { 70.8, 90.4 }, { 71.2, 89.4 }, { 72.4, 89.4 },
			} } },
		},
	},

	-- The Broken Hammer (Desolace): its item drops from Burning Blade casters.
	[79939] = {
		name = "The Broken Hammer",
		objectives = {
			{ kind = "loot", name = "Burning Blade Summoners and Invokers", ids = { 4668, 4705 }, spawns = { [405] = {
				{ 50.2, 72.1 }, { 50.4, 76.8 }, { 50.5, 82.5 }, { 50.9, 84.2 }, { 51.2, 81.7 }, { 51.8, 83.2 },
				{ 52.4, 81.7 }, { 52.6, 80.8 }, { 52.8, 80.0 }, { 53.0, 83.3 }, { 53.1, 84.7 }, { 53.4, 78.1 },
				{ 53.9, 77.0 }, { 54.9, 77.3 },
				{ 79.4, 77.2 }, { 79.4, 78.6 }, { 79.4, 81.0 }, { 79.8, 78.0 }, { 80.2, 77.0 }, { 80.8, 76.4 },
				{ 81.8, 80.4 }, { 82.0, 80.6 }, { 82.6, 81.0 },
			} } },
		},
	},

	-- Rapid Escape (Eastern Plaguelands): hand it to an Argent Medic.
	[8152] = {
		name = "Rapid Escape",
		finish = { name = "Argent Medic", spawns = { [139] = { { 46.8, 43.4 }, { 70.8, 48.2 }, { 80.4, 57.8 } } } },
	},

	-- The Ritual (Felwood): Aeonas the Vindicated gives and takes it.
	[81885] = {
		name = "The Ritual",
		start = { name = "Aeonas the Vindicated", spawns = { [361] = { { 45.0, 52.0 } } } },
		finish = { name = "Aeonas the Vindicated", spawns = { [361] = { { 45.0, 52.0 } } } },
	},

	-- The Price of Hope: from Aeonas in Felwood to Katherine the Pure in Stormwind.
	[82135] = {
		name = "The Price of Hope",
		start = { name = "Aeonas the Vindicated", spawns = { [361] = { { 45.0, 52.0 } } } },
		finish = { name = "Katherine the Pure", spawns = { [1519] = { { 48.4, 49.2 }, { 48.8, 49.6 } } } },
	},

	-- Red Bag Blues: from Nami in Winterspring to the Red Bag in Burning Steppes.
	[84146] = {
		name = "Red Bag Blues",
		finish = { name = "Red Bag", spawns = { [46] = { { 53.0, 24.4 } } } },
	},

	-- Poacher's Den: from the Red Bag in Burning Steppes back to Nami in Winterspring; the item
	-- drops from the poachers and smugglers around the den.
	[84211] = {
		name = "Poacher's Den",
		start = { name = "Red Bag", spawns = { [46] = { { 53.0, 24.4 } } } },
		finish = { name = "Nami", spawns = { [618] = { { 61.2, 37.0 } } } },
		objectives = {
			{ kind = "loot", name = "Poachers and smugglers", ids = { 228230, 228231, 228232, 228233, 228609, 228610 },
				spawns = { [46] = {
					{ 46.4, 35.4 }, { 46.8, 34.0 }, { 47.4, 35.6 }, { 48.2, 36.6 }, { 48.4, 34.8 }, { 49.4, 38.2 },
					{ 49.8, 33.4 }, { 50.0, 35.2 }, { 50.4, 27.4 }, { 50.8, 27.4 }, { 50.8, 30.2 }, { 51.0, 26.4 },
					{ 51.2, 25.2 }, { 52.0, 26.6 }, { 52.8, 25.2 }, { 53.4, 24.0 }, { 54.0, 23.4 }, { 51.2, 37.0 },
					{ 44.9, 26.2 }, { 46.4, 21.4 }, { 47.2, 23.3 }, { 47.4, 29.0 }, { 48.1, 29.6 }, { 50.5, 27.2 },
				} } },
		},
	},

	------------------------------------------------------------------------------------
	-- Batch 2 (2026-11-19), from Wowhead WoW Forever pages.
	-- Areas: 16651 = Shen'dralas (Forever's Valley of Bones, Desolace), 616 = Mount Hyjal.
	------------------------------------------------------------------------------------

	-- Praise (two versions): use the Embroidered Scabbard to meet the Veteran at Mourning's Rest.
	[92102] = {
		name = "Praise",
		objectives = {
			{ kind = "spot", name = "Meet the Veteran of the Third War (broken cannon, Mourning's Rest)", spawns = { [616] = { { 27.4, 51.0 } } } },
		},
	},
	[93551] = {
		name = "Praise",
		objectives = {
			{ kind = "spot", name = "Meet the Veteran of the Third War (broken cannon, Mourning's Rest)", spawns = { [616] = { { 27.4, 51.0 } } } },
		},
	},

	-- Pay Dirt! (two versions, Azshara): starts from an item the Cliff Breakers and Thunderers drop.
	[90813] = {
		name = "Pay Dirt!",
		start = { drop = true, name = "Cliff Breakers and Thunderers", ids = { 6146, 6147 }, spawns = { [16] = {
			{ 43.4, 72.0 }, { 44.2, 71.2 }, { 45.4, 69.4 }, { 45.4, 74.2 }, { 45.8, 71.4 }, { 45.8, 75.0 },
			{ 46.6, 76.4 }, { 47.2, 73.4 }, { 47.6, 73.6 }, { 48.2, 71.0 }, { 48.4, 75.2 }, { 48.8, 70.6 },
			{ 45.8, 79.8 }, { 47.4, 81.4 }, { 48.4, 83.4 }, { 46.2, 83.2 }, { 45.0, 85.8 }, { 47.8, 86.0 },
			{ 41.4, 71.8 }, { 42.2, 72.0 }, { 44.4, 73.4 }, { 45.6, 69.6 }, { 46.0, 75.2 }, { 47.4, 77.6 },
		} } },
	},
	[91607] = {
		name = "Pay Dirt!",
		start = { drop = true, name = "Cliff Breakers and Thunderers", ids = { 6146, 6147 }, spawns = { [16] = {
			{ 43.4, 72.0 }, { 44.2, 71.2 }, { 45.4, 69.4 }, { 45.4, 74.2 }, { 45.8, 71.4 }, { 45.8, 75.0 },
			{ 46.6, 76.4 }, { 47.2, 73.4 }, { 47.6, 73.6 }, { 48.2, 71.0 }, { 48.4, 75.2 }, { 48.8, 70.6 },
			{ 45.8, 79.8 }, { 47.4, 81.4 }, { 48.4, 83.4 }, { 46.2, 83.2 }, { 45.0, 85.8 }, { 47.8, 86.0 },
			{ 41.4, 71.8 }, { 42.2, 72.0 }, { 44.4, 73.4 }, { 45.6, 69.6 }, { 46.0, 75.2 }, { 47.4, 77.6 },
		} } },
	},

	-- A New Need for Shadow Protection (Desolace): bring the potions back to Mirda in Magram Village.
	[92754] = {
		name = "A New Need for Shadow Protection",
		finish = { name = "Mirda", spawns = { [405] = { { 70.4, 70.4 }, { 70.6, 70.6 } } } },
	},

	-- The Giant in the Den (Arathi): starts from the Goliath's Wristguards, dropped by the Witherbark Goliath.
	[92707] = {
		name = "The Giant in the Den",
		start = { drop = true, kills = 1, name = "the Witherbark Goliath", ids = { 218032 }, spawns = { [45] = {
			{ 68.3, 80.7 }, { 68.4, 80.2 }, { 68.4, 82.2 }, { 69.2, 81.2 }, { 69.4, 81.6 }, { 69.6, 81.6 },
		} } },
	},

	-- Outcast Necromancers (Valley of Bones): slay Outcast Necromancers.
	[92846] = {
		name = "Outcast Necromancers",
		objectives = {
			{ kind = "kill", name = "Outcast Necromancers", ids = { 11559 }, spawns = {
				[16651] = {
					{ 22.6, 27.2 }, { 24.3, 25.3 }, { 25.0, 25.9 }, { 25.9, 23.1 }, { 26.3, 24.6 }, { 27.4, 25.3 },
					{ 28.2, 26.3 }, { 29.0, 27.6 }, { 29.9, 27.7 }, { 30.4, 26.7 }, { 30.7, 30.0 }, { 31.4, 29.3 },
					{ 31.5, 25.2 }, { 31.9, 31.9 }, { 32.1, 27.1 }, { 32.6, 18.8 }, { 33.9, 20.1 }, { 34.9, 20.2 },
				},
				[405] = {
					{ 59.2, 89.4 }, { 60.0, 90.0 }, { 61.0, 90.6 }, { 62.4, 91.2 }, { 63.4, 89.4 }, { 63.8, 90.4 },
					{ 64.4, 92.0 }, { 64.8, 84.2 }, { 64.8, 87.1 }, { 64.8, 89.4 }, { 65.0, 85.4 }, { 65.2, 86.0 },
				},
			} },
		},
	},

	-- Khan Jehn (Desolace): slay Khan Jehn at Magram Village, then report to Uthek the Wise.
	[93128] = {
		name = "Khan Jehn",
		objectives = {
			{ kind = "kill", name = "Khan Jehn", count = 1, ids = { 5601 }, spawns = { [405] = {
				{ 65.5, 78.9 }, { 66.0, 80.4 }, { 66.0, 80.6 }, { 66.6, 79.8 }, { 66.8, 79.4 },
			} } },
		},
	},

	-- No Mercy for the Weak (Valley of Bones): slay 5 Gelkis Captives.
	[92893] = {
		name = "No Mercy for the Weak",
		objectives = {
			{ kind = "kill", name = "Gelkis Captives", count = 5, ids = { 253431 }, spawns = { [16651] = {
				{ 45.4, 31.0 }, { 45.6, 30.4 }, { 46.8, 27.8 }, { 47.4, 26.4 }, { 49.2, 28.4 }, { 49.2, 33.6 },
				{ 49.6, 33.8 }, { 49.8, 25.4 }, { 51.2, 25.4 }, { 51.8, 24.6 },
			} } },
		},
	},

	-- Bone Raising (Valley of Bones): raise (or slay) 10 Haggard Bones with the Enhanced Necromancy Staff.
	[92894] = {
		name = "Bone Raising",
		objectives = {
			{ kind = "kill", name = "Haggard Bones (raise or slay)", count = 10, ids = { 253446 }, spawns = { [16651] = {
				{ 35.8, 29.6 }, { 38.0, 30.6 }, { 38.4, 29.0 }, { 39.0, 29.4 }, { 40.4, 30.4 }, { 41.8, 30.0 },
				{ 42.4, 29.4 }, { 43.0, 30.2 }, { 43.6, 30.8 }, { 44.2, 31.8 }, { 45.4, 32.2 }, { 46.0, 37.6 },
				{ 46.4, 32.8 }, { 46.8, 36.8 }, { 47.0, 31.6 }, { 47.2, 34.4 }, { 47.6, 32.4 }, { 48.0, 30.4 },
				{ 48.4, 28.2 }, { 48.4, 32.6 }, { 48.8, 26.4 }, { 49.2, 24.2 },
			} } },
		},
	},

	-- Ravaging Ravagers (Valley of Bones): slay 6 Undead Ravagers.
	[93035] = {
		name = "Ravaging Ravagers",
		objectives = {
			{ kind = "kill", name = "Undead Ravagers", count = 6, ids = { 11561 }, spawns = {
				[16651] = {
					{ 20.0, 28.4 }, { 23.0, 27.5 }, { 26.0, 27.2 }, { 27.3, 28.3 }, { 28.7, 27.6 }, { 30.4, 27.0 },
					{ 31.4, 27.1 }, { 32.3, 22.3 }, { 32.8, 19.0 }, { 33.4, 14.0 }, { 33.7, 23.3 }, { 34.3, 27.9 },
					{ 34.7, 13.3 }, { 35.7, 26.0 },
				},
				[405] = {
					{ 58.2, 89.4 }, { 59.6, 89.0 }, { 60.6, 90.4 }, { 62.8, 90.2 }, { 63.4, 89.4 }, { 64.0, 89.0 },
					{ 64.2, 84.8 }, { 64.4, 90.0 }, { 64.8, 83.4 }, { 65.2, 85.8 },
				},
			} },
		},
	},

	-- Bristleback Retreat (Valley of Bones): slay quilboar, then report to Hagiak at the Magram Front.
	[93066] = {
		name = "Bristleback Retreat",
		objectives = {
			{ kind = "kill", name = "Bristleback quilboar", ids = { 253524, 253525, 253526 }, spawns = { [16651] = {
				{ 60.4, 18.4 }, { 63.9, 22.5 }, { 66.4, 22.8 }, { 67.8, 23.4 }, { 68.4, 37.4 }, { 68.9, 31.3 },
				{ 69.3, 35.7 }, { 69.7, 30.6 }, { 70.3, 27.3 }, { 71.2, 23.0 }, { 72.3, 20.1 }, { 73.4, 32.0 },
				{ 65.8, 25.4 }, { 66.2, 28.8 }, { 67.2, 29.2 }, { 68.1, 35.8 }, { 71.1, 30.0 }, { 71.5, 40.7 },
				{ 72.1, 28.1 }, { 62.1, 23.7 }, { 63.6, 37.5 }, { 65.5, 38.5 }, { 67.4, 23.3 }, { 70.7, 26.4 },
			} } },
		},
	},

	-- Bait the Beast (Mount Hyjal): kill a Nightsaber Guardian for its haunch, then bait and kill
	-- Ghansurok on the northern ridge of the summit.
	[93444] = {
		name = "Bait the Beast",
		objectives = {
			{ kind = "loot", name = "a Nightsaber Guardian (haunch)", count = 1, ids = { 249493 }, spawns = { [616] = {
				{ 68.2, 23.0 }, { 69.6, 26.0 }, { 70.4, 35.6 }, { 71.0, 30.6 }, { 71.6, 33.6 }, { 72.0, 23.0 },
				{ 72.2, 41.2 }, { 72.6, 40.2 }, { 73.2, 43.2 }, { 74.0, 26.0 }, { 74.6, 43.0 }, { 75.2, 28.4 },
				{ 76.2, 28.6 }, { 76.6, 32.2 }, { 77.2, 37.2 }, { 78.0, 41.2 }, { 78.8, 42.2 },
			} } },
			{ kind = "kill", name = "Ghansurok (bait it with the haunch)", count = 1, ids = { 264867 }, spawns = { [616] = {
				{ 68.4, 22.2 }, { 68.6, 23.6 }, { 69.2, 21.4 }, { 69.2, 21.8 }, { 69.2, 23.0 },
			} } },
		},
	},

	-- Partially Digested Collar (Shen'dralas): starts from an item the Prowlers drop.
	[93568] = {
		name = "Partially Digested Collar",
		start = { drop = true, name = "Prowlers", ids = { 255207 }, spawns = { [16651] = {
			{ 44.2, 48.3 }, { 44.7, 50.5 }, { 45.1, 50.2 }, { 46.4, 50.8 }, { 46.8, 47.1 }, { 46.8, 53.2 },
			{ 47.0, 48.8 }, { 48.4, 62.5 }, { 50.2, 54.8 }, { 51.9, 59.0 }, { 53.5, 59.6 }, { 55.3, 54.6 },
			{ 57.4, 54.1 },
		} } },
	},

	-- Corpsefeeder's Carapace (Shen'dralas): starts from an item the Corpsefeeders drop.
	[93574] = {
		name = "Corpsefeeder's Carapace",
		start = { drop = true, name = "Corpsefeeders", ids = { 253394 }, spawns = { [16651] = {
			{ 39.7, 31.0 }, { 46.0, 33.8 }, { 46.8, 30.4 }, { 53.7, 53.4 }, { 55.1, 23.5 }, { 57.9, 23.8 },
			{ 58.3, 24.8 }, { 59.5, 25.3 }, { 61.2, 41.1 }, { 63.6, 20.3 }, { 64.1, 39.4 }, { 65.4, 37.6 },
			{ 66.0, 23.1 }, { 67.4, 35.4 },
		} } },
	},

	------------------------------------------------------------------------------------
	-- Batch 3 (2026-11-19), from Wowhead WoW Forever pages, filled in with a web research pass
	-- (forever-xp.com, wow4ever.quest, foreverchanges.pro). Where they disagree, Wowhead's map wins.
	-- Areas: 16591 = Riverglades, 616 = Mount Hyjal, 16651 = Shen'dralas.
	------------------------------------------------------------------------------------

	-- Herbs of the Hollow (Mount Hyjal): 10 Dried Hanging Herbs around Barkskin Burrow.
	[93828] = {
		name = "Herbs of the Hollow",
		objectives = {
			{ kind = "objects", name = "Dried Hanging Herbs", count = 10, spawns = { [616] = {
				{ 20.3, 78.3 }, { 20.3, 78.5 }, { 20.7, 79.2 }, { 21.6, 78.9 }, { 21.7, 79.7 },
			} } },
		},
	},

	-- Bloodmaster's Ring (Riverglades): one fight each in the ring, run by Jezap Jinglesprocket.
	[94670] = { name = "Bloodmaster's Ring", objectives = { { kind = "spot", seconds = 90, name = "Defeat Buzzbeak in the Bloodmaster's Ring", spawns = { [16591] = { { 65.6, 21.4 } } } } } },
	[94739] = { name = "Bloodmaster's Ring", objectives = { { kind = "spot", seconds = 90, name = "Defeat Kronk in the Bloodmaster's Ring", spawns = { [16591] = { { 65.6, 21.4 } } } } } },
	[94962] = { name = "Bloodmaster's Ring", objectives = { { kind = "spot", seconds = 90, name = "Defeat Bonegnaw in the Bloodmaster's Ring", spawns = { [16591] = { { 65.6, 21.4 } } } } } },
	[94964] = { name = "Bloodmaster's Ring", objectives = { { kind = "spot", seconds = 90, name = "Defeat Mog'thar in the Bloodmaster's Ring", spawns = { [16591] = { { 65.6, 21.4 } } } } } },
	[94965] = { name = "Bloodmaster's Ring", objectives = { { kind = "spot", seconds = 90, name = "Defeat Snufflesnout in the Bloodmaster's Ring", spawns = { [16591] = { { 65.6, 21.4 } } } } } },
	[95063] = {
		name = "Bloodmaster's Ring",
		objectives = { { kind = "spot", seconds = 120, name = "Defeat Chub'chob in the Bloodmaster's Ring", spawns = { [16591] = { { 65.6, 21.4 } } } } },
		finish = { name = "Clugfist", spawns = { [16591] = { { 64.4, 14.8 } } } },
	},

	-- Divine Grace (priests): from Priestess Alathea in Darnassus to High Priestess Laurena in Stormwind.
	[94779] = {
		name = "Divine Grace",
		start = { name = "Priestess Alathea", spawns = { [1657] = { { 39.5, 81.2 } } } },
		finish = { name = "High Priestess Laurena", spawns = { [1519] = { { 49.4, 44.8 } } } },
	},

	-- Confounding Flash (priests, two versions): to High Priestess Mims in Ironforge (Mystic Ward).
	[94823] = {
		name = "Confounding Flash",
		start = { name = "Laurna Morninglight", spawns = { [141] = { { 55.4, 56.8 } } } },
		finish = { name = "High Priestess Mims", spawns = { [1537] = { { 24.8, 9.4 }, { 25.6, 10.4 } } } },
	},
	[94826] = {
		name = "Confounding Flash",
		start = { name = "Priestess Alathea", spawns = { [1657] = { { 39.5, 81.2 } } } },
		finish = { name = "High Priestess Mims", spawns = { [1537] = { { 24.8, 9.4 }, { 25.6, 10.4 } } } },
	},

	-- What We Lost (Riverglades): 5 Farmers' Mementos from Twilight Raiders, buried at the graves.
	[94829] = {
		name = "What We Lost",
		objectives = {
			{ kind = "loot", name = "Twilight Raiders (Farmers' Mementos)", count = 5, ids = { 256952 }, spawns = { [16591] = {
				{ 42.6, 45.4 }, { 44.4, 51.8 }, { 45.2, 46.1 }, { 45.6, 45.9 }, { 46.2, 50.6 }, { 47.3, 45.2 },
				{ 47.9, 49.9 }, { 48.6, 50.7 }, { 49.5, 48.8 }, { 50.1, 48.0 }, { 51.4, 45.0 }, { 53.1, 44.4 },
			} } },
			{ kind = "spot", seconds = 40, name = "Bury the mementos at the graves west of Elbrim's Farm", spawns = { [16591] = {
				{ 47.2, 44.9 }, { 48.4, 43.2 }, { 48.4, 44.8 }, { 48.6, 43.8 },
			} } },
		},
	},

	-- Tattered Journal (Shen'dralas): starts from an item Outcast and Magram Necromancers drop.
	[93644] = {
		name = "Tattered Journal",
		start = { drop = true, name = "Outcast and Magram Necromancers", ids = { 11559, 253272 }, spawns = { [16651] = {
			{ 22.6, 27.2 }, { 24.4, 26.0 }, { 25.9, 23.1 }, { 26.5, 26.9 }, { 28.2, 26.3 }, { 29.0, 28.8 },
			{ 30.0, 29.6 }, { 31.0, 30.5 }, { 31.5, 25.2 }, { 32.1, 27.1 }, { 33.9, 20.5 },
			{ 30.0, 28.0 }, { 32.6, 28.9 }, { 35.3, 18.3 }, { 36.0, 25.8 }, { 40.9, 31.5 }, { 47.1, 30.4 },
		} } },
	},

	-- Moonglade (druids, two versions): teleport to Moonglade and talk to Dendrite Starblaze. The
	-- turn-in is the whole quest: nothing to do on the way.
	[94913] = { name = "Moonglade" },
	[94914] = { name = "Moonglade" },

	-- Drop the Hammer (Riverglades): starts from Komuk's Warmaul, dropped by the ogre Komuk.
	[94926] = {
		name = "Drop the Hammer",
		start = { drop = true, kills = 1, name = "Komuk", ids = { 259056 }, spawns = { [16591] = {
			{ 66.4, 34.0 }, { 66.4, 38.3 }, { 66.5, 37.0 }, { 69.2, 32.0 }, { 70.6, 32.6 }, { 71.0, 32.4 },
		} } },
	},

	-- Mystic Mix (Mount Hyjal): 2 Deadwood Death Mystics and 2 cauldrons in Deadwood Den.
	[95108] = {
		name = "Mystic Mix",
		objectives = {
			{ kind = "kill", name = "Deadwood Death Mystics", count = 2, ids = { 259876 }, spawns = { [616] = {
				{ 26.3, 59.7 }, { 27.5, 59.0 }, { 28.5, 60.0 }, { 29.4, 58.0 }, { 30.2, 57.4 }, { 30.8, 59.8 }, { 31.4, 60.9 },
			} } },
			{ kind = "spot", seconds = 40, name = "Destroy two Deadwood Cauldrons (Deadwood Den)", spawns = { [616] = { { 28.5, 59.0 } } } },
		},
	},

	-- Kum'isha's Endeavors (Blasted Lands): a Flawless Draenethyst Sphere from the cultists and felbeasts.
	[93686] = {
		name = "Kum'isha's Endeavors",
		start = { name = "Kum'isha the Collector", spawns = { [4] = { { 52.0, 35.6 } } } },
		finish = { name = "Kum'isha the Collector", spawns = { [4] = { { 52.0, 35.6 } } } },
		objectives = {
			{ kind = "loot", name = "Shadowsworn Cultists and Felbeasts (Draenethyst Sphere)", count = 1, ids = { 6004, 8675 }, spawns = { [4] = {
				{ 59.3, 22.6 }, { 61.2, 26.6 }, { 62.8, 39.0 }, { 63.6, 32.0 }, { 64.3, 27.3 }, { 64.5, 31.3 },
				{ 65.6, 32.2 }, { 66.8, 31.2 }, { 44.3, 35.1 }, { 45.9, 40.4 }, { 49.2, 35.8 }, { 50.3, 38.1 },
				{ 51.6, 39.7 }, { 52.9, 37.5 }, { 53.8, 38.2 }, { 55.6, 42.0 }, { 58.2, 42.8 }, { 59.2, 35.6 },
			} } },
		},
	},

	-- To Serve The Draenei (Blasted Lands): follows Kum'isha's Endeavors; protect the refugees going
	-- through Kum'isha's rift. Giver and turn-in not recorded anywhere: Kum'isha, from the quest text.
	[93572] = {
		name = "To Serve The Draenei",
		start = { name = "Kum'isha the Collector", spawns = { [4] = { { 52.0, 35.6 } } } },
		finish = { name = "Kum'isha the Collector", spawns = { [4] = { { 52.0, 35.6 } } } },
		objectives = {
			{ kind = "spot", seconds = 180, name = "Protect the draenei refugees at Kum'isha's rift", spawns = { [4] = { { 52.0, 35.6 } } } },
		},
	},

	-- Itching for a Fixing: hand in to Hnaz Blunderflame in Mount Hyjal (web research only).
	[91564] = {
		name = "Itching for a Fixing",
		finish = { name = "Hnaz Blunderflame", spawns = { [616] = { { 15.6, 50.0 } } } },
	},

	------------------------------------------------------------------------------------
	-- Batch 4 (2026-11-19), from Wowhead WoW Forever pages.
	------------------------------------------------------------------------------------

	-- Call of Fire (shamans): from Narm Skychaser (Mulgore) or Kardris Dreamseeker (Orgrimmar).
	[98517] = {
		name = "Call of Fire",
		start = { name = "Narm Skychaser / Kardris Dreamseeker", spawns = { [215] = { { 47.4, 62.6 } }, [1637] = { { 38.4, 37.2 } } } },
	},

	-- Hail the Dragonslayer (two versions, Riverglades): starts from the Head of Scaldaron.
	[95935] = {
		name = "Hail the Dragonslayer",
		start = { drop = true, kills = 1, name = "Scaldaron", ids = { 263141 }, spawns = { [16591] = { { 30.4, 72.2 }, { 31.2, 72.9 }, { 31.6, 73.2 } } } },
	},
	[95936] = {
		name = "Hail the Dragonslayer",
		start = { drop = true, kills = 1, name = "Scaldaron", ids = { 263141 }, spawns = { [16591] = { { 30.4, 72.2 }, { 31.2, 72.9 }, { 31.6, 73.2 } } } },
	},

	-- Partial Mystical Notes (Stranglethorn): starts from an item the Skullsplitter Mystics drop.
	[95384] = {
		name = "Partial Mystical Notes",
		start = { drop = true, name = "Skullsplitter Mystics", ids = { 780 }, spawns = { [33] = {
			{ 42.0, 36.2 }, { 42.8, 34.0 }, { 43.4, 37.8 }, { 44.0, 35.4 }, { 45.0, 32.6 }, { 45.6, 41.2 },
			{ 46.4, 30.0 }, { 47.0, 32.4 }, { 47.2, 39.8 }, { 47.9, 38.3 },
		} } },
	},

	-- Torn Mystical Scroll (Stranglethorn): starts from an item the Bloodsail Warlocks drop.
	[95385] = {
		name = "Torn Mystical Scroll",
		start = { drop = true, name = "Bloodsail Warlocks", ids = { 1564 }, spawns = { [33] = {
			{ 22.8, 53.4 }, { 24.0, 56.0 }, { 26.4, 83.4 }, { 27.0, 82.8 }, { 28.2, 82.4 }, { 29.4, 87.4 },
			{ 29.6, 81.6 }, { 30.2, 87.4 }, { 32.0, 79.6 }, { 33.4, 86.6 },
		} } },
	},

	-- Mirage Mirror (Badlands): starts from an item the Malevolent Mirages drop.
	[97821] = {
		name = "Mirage Mirror",
		start = { drop = true, name = "Malevolent Mirages", ids = { 269756 }, spawns = { [3] = {
			{ 15.2, 74.0 }, { 15.4, 75.4 }, { 15.6, 74.8 }, { 17.6, 77.2 }, { 30.2, 74.6 }, { 31.4, 75.8 },
			{ 32.4, 72.4 }, { 37.4, 44.4 }, { 38.0, 45.4 },
		} } },
	},

	-- Soldier's Solace (Mount Hyjal): put the spirits to rest (Spectral Frostwyrm) at the Battle Cache.
	[96558] = {
		name = "Soldier's Solace",
		objectives = {
			{ kind = "spot", seconds = 90, name = "Put the spirits to rest at the Battle Cache (Spectral Frostwyrm)", spawns = { [616] = { { 28.9, 52.9 } } } },
		},
	},

	-- Supplies and Studies (Badlands): Mus'hale's Stolen Supplies from Dustbowl ogres, then rubbings of
	-- the small and large etched stones.
	[97663] = {
		name = "Supplies and Studies",
		objectives = {
			{ kind = "loot", name = "Dustbelcher ogres (Mus'hale's Stolen Supplies)", count = 1, ids = { 2701, 2715 }, spawns = { [3] = {
				{ 25.4, 62.0 }, { 26.3, 58.7 }, { 27.2, 58.3 }, { 27.6, 60.8 }, { 28.3, 52.5 }, { 28.5, 64.9 },
				{ 29.1, 60.8 }, { 29.6, 59.4 }, { 30.4, 55.4 }, { 30.8, 60.7 }, { 26.0, 57.1 }, { 27.0, 59.7 },
			} } },
			{ kind = "spot", name = "Rub the small etched stone", spawns = { [3] = { { 31.5, 61.0 } } } },
			{ kind = "spot", name = "Rub the large etched stone", spawns = { [3] = { { 28.4, 60.7 } } } },
		},
	},

	-- Aeonas's Secret Refuge (Wetlands): ride the Old Dinghy at Menethil Harbor (by Harold Riggs).
	[96449] = {
		name = "Aeonas's Secret Refuge",
		objectives = {
			{ kind = "spot", seconds = 120, name = "Ride the Old Dinghy at Menethil Harbor", spawns = { [11] = { { 8.0, 58.4 } } } },
		},
	},

	-- From the Ashes (Wetlands): destroy the 4 attack plans in the Angerfang Encampment.
	[98221] = {
		name = "From the Ashes",
		objectives = {
			{ kind = "spot", name = "Destroy the attack plan: Menethil Harbor", spawns = { [11] = { { 45.4, 42.6 } } } },
			{ kind = "spot", name = "Destroy the attack plan: Southshore", spawns = { [11] = { { 45.4, 45.4 } } } },
			{ kind = "spot", name = "Destroy the attack plan: Thelsamar", spawns = { [11] = { { 49.4, 46.7 } } } },
			{ kind = "spot", name = "Destroy the attack plan: Ironforge", spawns = { [11] = { { 38.6, 46.2 } } } },
		},
	},

	------------------------------------------------------------------------------------
	-- Batch 5 (2026-11-19): quest items Questie lists without a source.
	------------------------------------------------------------------------------------

	-- Not on Squealing Terms (Shen'dralas): the Benevolent Bouquet's flowers come from the
	-- Rowdy Roses, Terrible Tulips and Vibrant Flowers in the Forlorn Gardens.
	[93606] = {
		name = "Not on Squealing Terms",
		items = {
			[260244] = { kind = "loot", count = 5, name = "Rowdy Roses and Terrible Tulips (Forlorn Gardens)", ids = { 254566, 254567 }, spawns = { [16651] = {
				{ 61.9, 72.7 }, { 63.3, 73.4 }, { 64.0, 73.4 }, { 65.0, 76.5 }, { 65.5, 74.1 }, { 66.3, 72.9 },
				{ 66.6, 75.5 }, { 67.5, 72.7 }, { 68.9, 77.1 }, { 63.6, 74.3 }, { 64.6, 73.2 }, { 66.3, 72.1 },
				{ 67.0, 73.4 }, { 63.0, 73.5 }, { 63.3, 74.8 }, { 64.3, 74.5 }, { 68.3, 72.6 }, { 70.7, 72.5 },
			} } },
		},
	},

	-- Shipping Label (two versions): the label is what you hand in; you already have it.
	[98247] = { name = "Shipping Label", items = { [280179] = { kind = "have" } } },
	[98248] = { name = "Shipping Label", items = { [280180] = { kind = "have" } } },

	-- Stalk With The Earthmother (Fish Chunks): buy or catch a Raw Brilliant Smallfish, then fillet it
	-- with the Knife Set in front of Boarton Shadetotem (Thunder Bluff).
	[76240] = {
		name = "Stalk With The Earthmother",
		items = {
			[206345] = { kind = "spot", seconds = 60, name = "Get a Raw Brilliant Smallfish and fillet it by Boarton Shadetotem", spawns = { [1638] = { { 39.5, 65.0 } } } },
		},
	},

	-- Call of Water (brown): fill the waterskin in the pool at the base of the falls below Hervdana's cave.
	[94497] = {
		name = "Call of Water",
		items = {
			[265734] = { kind = "spot", name = "Fill the Brown Waterskin at the waterfall below Hervdana's cave", spawns = { [11] = { { 65.7, 76.4 } } } }, -- (Wowhead comments)
		},
	},

	------------------------------------------------------------------------------------
	-- Batch 6 (2026-11-19): web research pass (warcraftmaps.com, bindonforever.com,
	-- warcraft.wiki.gg). Spots marked "centre" are the middle of the densest spawn cluster.
	------------------------------------------------------------------------------------

	-- The Dying Ancients (Mount Hyjal): kill Sunderbark (elite), then plant the seed in his remains.
	[92959] = {
		name = "The Dying Ancients",
		objectives = {
			{ kind = "kill", name = "Sunderbark", count = 1, ids = { 248709 }, spawns = { [616] = { { 62.4, 76.6 } } } }, -- centre
			{ kind = "spot", name = "Plant the Seed of the Ancients in Sunderbark's remains", spawns = { [616] = { { 62.4, 76.6 } } } },
		},
	},

	-- Farholde Scouting Report (Riverglades): starts from the report Cavalry Scout Alturin (elite,
	-- patrols) drops.
	[93971] = {
		name = "Farholde Scouting Report",
		start = { drop = true, kills = 1, name = "Cavalry Scout Alturin (patrols)", ids = { 257079 }, spawns = { [16591] = { { 52.5, 56.9 } } } }, -- centre
	},

	-- Memories of Rockard (Blasted Lands): starts from the Carved Stone Trinket Dreadmaul ogres drop.
	[87451] = {
		name = "Memories of Rockard",
		start = { drop = true, name = "Dreadmaul ogres", spawns = { [4] = { { 46.4, 44.2 } } } },
	},

	-- Microcrystal Contamination (Un'Goro): starts from the Crystal Infused Scale ravasaurs drop.
	[87494] = {
		name = "Microcrystal Contamination",
		start = { drop = true, name = "ravasaurs", spawns = { [490] = { { 59.9, 75.9 } } } },
	},

	-- Fetch 'n' Fletch (Riverglades): Wood Bundles from the Peasant Woodpiles in Turner's Logging
	-- Camp, fletched into 20 spears.
	[95951] = {
		name = "Fetch 'n' Fletch",
		items = {
			[271630] = { kind = "objects", name = "Wood Bundles from Peasant Woodpiles (fletch into spears)", spawns = { [16591] = { { 39.0, 61.3 } } } },
		},
	},

	-- The Morrow Stone (Feralas): use the Stave of Equinex at the Equinex Monolith.
	[2942] = {
		name = "The Morrow Stone",
		items = {
			[9307] = { kind = "spot", name = "Use the Stave of Equinex at the Equinex Monolith (Ruins of Ravenwind)", spawns = { [357] = { { 38.9, 13.2 } } } }, -- (Wowhead)
		},
	},

	-- Samophlange Manual (Barrens): the pages and cover drop from the Venture Co. Enforcers and
	-- Overseers and Boss Copperplug at Boulder Lode Mine (Wowhead).
	[3924] = {
		name = "Samophlange Manual",
		items = {
			[11149] = { kind = "loot", count = 1, name = "Venture Co. at Boulder Lode Mine (pages and cover)", ids = { 3283, 3286, 9336 }, spawns = { [17] = {
				{ 60.0, 3.2 }, { 60.4, 3.8 }, { 61.2, 5.4 }, { 61.4, 5.6 }, { 61.6, 4.8 }, { 61.7, 3.3 },
				{ 61.8, 3.8 }, { 62.0, 4.8 }, { 59.8, 3.4 }, { 60.0, 4.0 },
			} } },
		},
	},

	-- Two Halves Become One (Western Plaguelands): the other half of the charm drops from the
	-- Jabbering Ghoul in Felstone Field (Wowhead).
	[5051] = {
		name = "Two Halves Become One",
		items = {
			[12723] = { kind = "loot", count = 1, name = "the Jabbering Ghoul (Felstone Field)", ids = { 10801 }, spawns = { [28] = {
				{ 36.0, 56.9 }, { 36.0, 58.6 }, { 36.8, 58.6 }, { 37.4, 55.8 }, { 37.8, 57.6 }, { 38.0, 56.6 },
				{ 38.6, 55.2 }, { 38.6, 56.6 },
			} } },
		},
	},

	-- Marauders of Darrowshire (Eastern Plaguelands): Fetid Skulls from Scourge Champions, tested with
	-- the Mystic Crystal until they resonate (Wowhead; method from the web research pass).
	[5206] = {
		name = "Marauders of Darrowshire",
		items = {
			[13155] = { kind = "loot", name = "Scourge Champions (Fetid Skulls, test with the Mystic Crystal)", ids = { 8529 }, spawns = { [139] = {
				{ 76.4, 49.4 }, { 77.4, 54.8 }, { 79.4, 44.4 }, { 81.8, 40.4 }, { 84.4, 40.6 }, { 85.0, 41.6 },
				{ 66.8, 43.1 }, { 32.6, 65.4 }, { 36.0, 57.2 }, { 37.6, 57.4 },
			} } },
		},
	},

	------------------------------------------------------------------------------------
	-- Batch 7 (2026-11-19): spots checked in game.
	------------------------------------------------------------------------------------

	-- Paying Back the Pact (Mount Hyjal): use the Staff of the Mountain on 10 Blackthorne Pact
	-- members to remove their wards, then kill them.
	[92169] = {
		name = "Paying Back the Pact",
		objectives = {
			{ kind = "kill", count = 10, name = "Blackthorne Pact members (Staff of the Mountain first)", spawns = { [616] = { { 74.4, 30.0 } } } },
		},
	},

	-- The Experimental Method (Mount Hyjal): throw the Slimy Pinecones at the 4 Ashen Reign workstations.
	[95316] = {
		name = "The Experimental Method",
		objectives = {
			{ kind = "spot", name = "Pinecone the Vessel Workstation", spawns = { [616] = { { 49.6, 69.7 } } } },
			{ kind = "spot", name = "Pinecone the Disease Workstation", spawns = { [616] = { { 46.4, 67.7 } } } },
			{ kind = "spot", name = "Pinecone the Alchemy Workstation", spawns = { [616] = { { 44.4, 68.5 } } } },
			{ kind = "spot", name = "Pinecone the Slime Workstation", spawns = { [616] = { { 42.8, 72.0 } } } },
		},
	},

	-- Powering the Pylons (Shen'dralas): the Mana Sieve (temple, top floor) first, collect Ancient Mana
	-- Crystals with it, then power the western and eastern pylons.
	[96018] = {
		name = "Powering the Pylons",
		objectives = {
			{ kind = "spot", seconds = 90, name = "Get the Mana Sieve (temple, top floor) and collect Ancient Mana Crystals", spawns = { [16651] = { { 46.2, 78.0 } } } },
			{ kind = "spot", name = "Power the western pylon", spawns = { [16651] = { { 43.6, 34.8 } } } },
			{ kind = "spot", name = "Power the eastern pylon", spawns = { [16651] = { { 73.5, 23.0 } } } },
		},
	},

	-- Phantasmal Problems (Shen'dralas): the Phantasmal Blade is made at Vindael, the quest giver.
	[93450] = {
		name = "Phantasmal Problems",
		items = { [258735] = { kind = "spot", seconds = 60, name = "Make the Phantasmal Blade at Vindael", spawns = { [16651] = { { 42.1, 78.6 } } } } },
	},

	-- Lost in Transit (Swamp of Sorrows): loot the Courier's Shipment from the Mangled Corpse by the water.
	[93663] = {
		name = "Lost in Transit",
		items = { [260452] = { kind = "spot", name = "Loot the Courier's Shipment from the Mangled Corpse", spawns = { [8] = { { 30.0, 54.3 } } } } },
	},

	-- Call of Water (red, Redridge): fill it at the Stonewatch Falls waterfall.
	[94499] = {
		name = "Call of Water",
		items = { [265748] = { kind = "spot", name = "Fill the Red Waterskin at the Stonewatch Falls waterfall", spawns = { [44] = { { 68.0, 61.0 } } } } },
	},

	-- Call of Water (blue, Ashenvale): fill it in the lake by Astranaar.
	[94500] = {
		name = "Call of Water",
		items = { [265773] = { kind = "spot", name = "Fill the Blue Waterskin in the lake by Astranaar", spawns = { [331] = { { 34.9, 47.6 } } } } },
	},

	-- Something's in the Water (Riverglades): the freshwater spout in the big pond north of the broken watchtower.
	[96084] = {
		name = "Something's in the Water",
		items = { [281228] = { kind = "spot", name = "Fill the phial at the freshwater spout", spawns = { [16591] = { { 62.0, 56.2 } } } } },
	},

	-- Snowbound (Loch Modan): fill the Ceramic Jar with snow at South Gate Pass.
	[86667] = {
		name = "Snowbound",
		items = { [279379] = { kind = "spot", name = "Fill the Ceramic Jar with snow at South Gate Pass", spawns = { [38] = { { 19.0, 66.0 } } } } },
	},

	-- Stalk With The Earthmother (Pine Salve, Mulgore): 8 Windfury Cones north of Thunder Bluff, ground
	-- with the Mortar and Pestle.
	[76160] = {
		name = "Stalk With The Earthmother",
		items = { [206175] = { kind = "spot", seconds = 120, name = "Gather 8 Windfury Cones and grind them with the Mortar and Pestle", spawns = { [215] = { { 30.9, 22.9 } } } } },
	},

	-- The Bloody Missive: starts from the missive Elrick drops, in the inn on Theramore Isle
	-- (warcraft.wiki.gg). Spot is the Theramore inn.
	[81766] = {
		name = "The Bloody Missive",
		start = { drop = true, kills = 1, name = "Elrick (Theramore inn)", spawns = { [15] = { { 66.6, 45.2 } } } },
	},

	-- Pamela's Doll (Eastern Plaguelands): the head, left side and right side lie in the Darrowshire
	-- houses south of Pamela (spots move between the houses; classicdb / Wowhead comments).
	[5149] = {
		name = "Pamela's Doll",
		items = {
			[12885] = { kind = "objects", count = 3, name = "doll parts in the Darrowshire houses (head, left, right)", spawns = { [139] = {
				{ 38.0, 92.0 }, { 39.0, 90.0 }, { 40.0, 90.0 },
			} } },
		},
	},

	------------------------------------------------------------------------------------
	-- Batch 8 (2026-11-19): Google AI answers (Wowhead, classicdb, warcraft.wiki.gg cited).
	------------------------------------------------------------------------------------

	-- The Old Key (Feralas): loot the key from the Old Crate next to the tent; the chest is underwater
	-- at 79.2, 49.4 (that part Questie knows).
	[95599] = {
		name = "The Old Key",
		start = { name = "the Old Crate next to the tent (loot the Old Key)", spawns = { [357] = { { 76.6, 48.0 } } } },
	},

	-- Terror of the Desert Skies (Badlands): the Primitive Drawing drops from Stonevault troggs and
	-- Dustbelcher ogres.
	[78823] = {
		name = "Terror of the Desert Skies",
		start = { drop = true, name = "Stonevault troggs and Dustbelcher ogres", spawns = { [3] = { { 52.0, 65.0 } } } },
	},

	-- Orders from the Grand Crusader (paladins): take the dinghy south of the Menethil docks to Newman's
	-- Landing, inspect the fallen Scarlet Crusader, and kill the elite Assassin who ambushes you.
	[79945] = {
		name = "Orders from the Grand Crusader",
		start = { drop = true, kills = 1, name = "the Scarlet Crusader Assassin at Newman's Landing (dinghy from Menethil)", spawns = { [1] = { { 18.0, 74.5 } } } },
	},

	-- Cyclonian (Arathi, then Alterac): 8 of each charm from the three binding circles, combined at
	-- Bath'rah the Windwatcher's cauldron into the Essence of the Exile.
	[1712] = {
		name = "Cyclonian",
		replace = true,
		objectives = {
			{ kind = "loot", count = 8, name = "Burning Exiles (Burning Charms, Circle of West Binding)", spawns = { [45] = { { 26.0, 26.0 } } } },
			{ kind = "loot", count = 8, name = "Thundering Exiles (Thundering Charms, Circle of Outer Binding)", spawns = { [45] = { { 50.0, 53.0 } } } },
			{ kind = "loot", count = 8, name = "Cresting Exiles (Cresting Charms, Circle of East Binding)", spawns = { [45] = { { 67.0, 30.0 } } } },
			{ kind = "spot", name = "Combine the charms at Bath'rah the Windwatcher's cauldron", spawns = { [36] = { { 80.5, 66.9 } } } },
		},
	},

	-- To Kill With Purpose (Eastern Plaguelands): 7 Living Rot from the Scourge at Corin's Crossing (loot
	-- them all at once: each expires 10 minutes after looting), ground into Coagulated Rot.
	[6022] = {
		name = "To Kill With Purpose",
		items = { [15448] = { kind = "spot", seconds = 300, name = "Kill 7 Scourge at Corin's Crossing, loot the Living Rot together, grind it", spawns = { [139] = { { 59.0, 69.0 } } } } },
	},

	-- The Lost Pages (Ashenvale): the 12 Shredder Operating Manual pages drop across the zone; densest
	-- humanoids/demons are the Dark Strand at Ordil'Aran and the satyrs at Xavian.
	[6504] = {
		name = "The Lost Pages",
		items = {
			[16642] = { kind = "spot", seconds = 600, name = "Farm Manual pages 1-4 (Ordil'Aran / Xavian)", spawns = { [331] = { { 31.0, 30.0 }, { 78.0, 46.0 } } } },
			[16643] = { kind = "spot", seconds = 600, name = "Farm Manual pages 5-8 (Ordil'Aran / Xavian)", spawns = { [331] = { { 31.0, 30.0 }, { 78.0, 46.0 } } } },
			[16644] = { kind = "spot", seconds = 600, name = "Farm Manual pages 9-12 (Ordil'Aran / Xavian)", spawns = { [331] = { { 31.0, 30.0 }, { 78.0, 46.0 } } } },
		},
	},

	-- Tanaris Field Sampling: scorpid and hyena samples just outside Gadgetzan, basilisk samples south of
	-- the Noxious Lair; test each with the Field Testing Kit (2-hour timer).
	[654] = {
		name = "Tanaris Field Sampling",
		items = {
			[9438] = { kind = "loot", name = "scorpids outside Gadgetzan (test the samples)", spawns = { [440] = { { 51.2, 34.5 } } } },
			[9441] = { kind = "loot", name = "Starving Blisterpaws outside Gadgetzan (test the samples)", spawns = { [440] = { { 51.2, 34.5 } } } },
			[9440] = { kind = "loot", name = "Glasshide Basilisks south of the Noxious Lair (test the samples)", spawns = { [440] = { { 34.2, 26.8 } } } },
		},
	},

	-- The Green Hills of Stranglethorn: the pages drop from humanoids zone-wide; Kurzen's Compound has the
	-- most per hour at 30-40 (Google AI, citing Wowhead / Reddit).
	[338] = {
		name = "The Green Hills of Stranglethorn",
		items = {
			[2756] = { kind = "spot", seconds = 600, name = "Farm Green Hills pages at Kurzen's Compound (Chapter I)", spawns = { [33] = { { 44.0, 10.0 } } } },
			[2757] = { kind = "spot", seconds = 600, name = "Farm Green Hills pages at Kurzen's Compound (Chapter II)", spawns = { [33] = { { 44.0, 10.0 } } } },
			[2758] = { kind = "spot", seconds = 600, name = "Farm Green Hills pages at Kurzen's Compound (Chapter III)", spawns = { [33] = { { 44.0, 10.0 } } } },
			[2759] = { kind = "spot", seconds = 600, name = "Farm Green Hills pages at Kurzen's Compound (Chapter IV)", spawns = { [33] = { { 44.0, 10.0 } } } },
		},
	},

	-- Quest items you get from the quest before in the chain: nothing to fetch.
	[3374] = { name = "The Essence of Eranikus", items = { [10455] = { kind = "have" } } },
	[4121] = { name = "Precarious Predicament", items = { [11286] = { kind = "have" } } },
}

----------------------------------------------------------------------------------------
-- Quests confirmed live on Forever that Questie's trace data hasn't seen yet (race/class versions,
-- dungeon versions). Never skipped as "not seen on Forever". Source: Wowhead Forever, via Google AI.
----------------------------------------------------------------------------------------
ns.LiveQuests = {
	[94817] = true, [94825] = true, -- Confounding Flash (gnome priests)
	[94773] = true, [94778] = true, -- Divine Grace (human priests)
	[94818] = true,                 -- Contingency Plan (gnome priests)
	[98166] = true,                 -- Your First Horse (humans, Theramore)
	[98287] = true,                 -- Camping 101: Engineering (Alliance engineers)
	[92753] = true,                 -- Destruction in Deadmines (Alliance)
	[92415] = true,                 -- Remember That I Love You (Alliance)
	[78699] = true,                 -- The Eye of Bhossca (rogues)
	[78307] = true,                 -- The Horn of Xelthos (rogues)
	[97288] = true,                 -- Unending Torment (Horde)
}

----------------------------------------------------------------------------------------
-- Forever drop rates for quest items, in % (used instead of Questie's Classic-era rates).
--   [itemId] = 19.3                       -- every mob that drops it
--   [itemId] = { [npcId] = 19.3, all = 5 } -- per mob ("all": the rest)
-- Wowhead counts every kill, also by players not on the quest, so for quest-only drops its
-- number is the low end of the real rate.
----------------------------------------------------------------------------------------
ns.QuestDropRates = {
	[5481] = 19.3, -- Satyr Horns (Xavian satyrs, Ashenvale): Wowhead Forever 581/3013. Questie: 50%
	[7128] = 0.6,  -- Uncloven Satyr Hoof (Xavian satyrs): Wowhead Forever 17/3013, not quest-only. Questie: 80%
}
