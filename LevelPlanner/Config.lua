-- LevelPlanner settings. Edit the numbers below, save, then /reload in game.
-- Times are in seconds, speeds in yards per second, XP in experience points.

LevelPlannerConfig = {
	-- Planning ---------------------------------------------------------------
	horizonMinutes = 60,        -- how far ahead the route is planned
	maxCandidates = 60,         -- how many available quests the planner looks at in detail
	stepsShown = 6,             -- lines in the step list
	frameBudgetMs = 4,          -- planning work allowed per frame (lower = smoother, slower)
	replanDelay = 1.0,          -- wait this long after an event before re-planning (events come in bursts)
	offTrailCheckSeconds = 5,   -- how often to check whether you've left the planned path
	offTrailYards = 100,        -- moved this far from where the plan was made, not toward the next step = off the trail
	offTrailSwitchThreshold = 0.02, -- off the trail, a new route only needs to be this much better (2%)
	refreshSeconds = 90,        -- on the trail, re-time the route from where you are this often (if you moved)

	-- Level filter -----------------------------------------------------------
	-- quest colours: yellow = up to 2 levels above you, orange = 3-4 above, red = 5+ above
	maxLevelsAbove = 2,         -- solo: quests up to this many levels above you (2 = yellow; orange and red wait)
	includeEliteQuests = false, -- always include elite quests, even solo (normally only when grouped)
	hunterSoloElites = true,    -- hunters solo: elite quests and mobs when yellow or easier (the pet tanks)
	hunterEliteLevelsAbove = 2, -- ... at most this many levels above you (yellow)
	includeDungeonQuests = false, -- dungeon quests (phase 4 adds dungeons)

	-- Grey quests: little quest XP and no XP from their mobs, but quick ones can still pay off
	greyQuests = true,          -- consider grey quests you haven't picked up (grey ones in your log are always weighed)
	greyMaxLevelsBelow = 8,     -- not more than this many levels below you
	greySearchYards = 1500,     -- quest giver within this distance of you
	greyMinRateShare = 0.8,     -- keep one only if its XP per minute is at least 80% of your plan's
	greyCandidates = 8,         -- at most this many offered to the planner

	-- Group (/lp group on|off) ---------------------------------------------------------
	autoDetectGroup = true,     -- being in a party also counts as grouped
	groupMaxLevelsAbove = 6,    -- grouped: orange and red quests allowed up to this many levels above you
	eliteKillFactorSolo = 3,    -- an elite takes this many times longer to kill alone
	eliteKillFactorGrouped = 1.2,
	groupMobXpShare = 0.6,      -- share of each kill's XP you get in a group

	-- Planner (phase 3) ------------------------------------------------------------------
	improvementPasses = 3,      -- local-improvement rounds after the first greedy route
	swapCandidates = 15,        -- unused quests tried as swaps in each round (more = better plans, slower)
	regretStart = true,         -- also try a route built quests-that-fit-in-one-place-first (regret insertion)
	regretWeight = 0.5,         -- how much "only fits well in one place" counts in that build
	graspStarts = 1,            -- extra routes built picking at random among the best few (0 = off; more = slower)
	graspTopK = 3,              -- ...among this many of the best
	segmentMoves = true,        -- improvement also moves runs of 2-3 stops and reverses stretches of the route
	twoOptMaxSpan = 10,         -- longest stretch (stops) tried reversed
	endBonusMaxShare = 0.03,    -- ending near good quests not taken (a hub) adds at most this share of the route's value
	endHubYards = 300,          -- "near" the route's last stop
	endHubValueShare = 0.1,     -- share of those quests' value counted (before the cap)
	endLogRoom = 4,             -- free quest-log slots at the end for the full bonus (fewer: less)
	planLevelUps = true,        -- see where the route levels you up: next-level quests, kill XP, trainer, mount
	levelUpCandidates = 15,     -- next-level quests offered to the planner (the most promising)
	hearthInRoute = true,       -- count the hearthstone in every route's time while choosing (not just the step list)
	switchThreshold = 0.10,     -- only switch to a new route if it is at least 10% better (XP per minute)
	chainLookahead = true,      -- plan follow-up quests unlocked by quests in the route
	bagReserveSlots = 2,        -- keep this many bag slots free for loot
	chainDepth = 2,             -- plan follow-ups this many steps down a chain
	chainValueFactor = 0.5,     -- a quest that opens later quests is worth this share of their XP (squared for the next step)
	sameCampYards = 200,        -- objectives this close count as one camp: "finding the spot" is counted once
	hereFirst = true,           -- an objective in the camp you stand in goes first when it costs little
	hereFirstSlackSeconds = 90, -- ... at most this many seconds more on the route
	hereTurninYards = 400,      -- turn-ins this close to you (the town you're in) go first, same rule
	escortFirst = true,         -- an escort you have started goes first in the route (leave it and it fails)
	escortMinutes = 30,         -- ... counted as started for this long after you accept it
	overlapYards = 60,          -- two objectives this close that need the same mobs are done together (kills count once)

	-- Flight paths you haven't learned ------------------------------------------------------
	learnFlightPaths = true,
	flightPathValueMinutes = 8,  -- a new flight path is assumed to save this many minutes of levelling later
	flightPathMaxDetourMinutes = 4, -- never go further out of the way than this to learn one

	-- Travel (phase 1 uses straight lines; phase 2 adds roads, flights and boats) ---
	runSpeed = 7.0,             -- yards per second on foot
	mountLevel = 40,            -- from this level the planner assumes you ride
	mountSpeed = 11.2,          -- yards per second mounted (60% mount)
	detourFactor = 1.3,         -- straight lines are shorter than real paths; multiply by this.
	                            -- LevelPlanner learns each zone's real factor from your walks (/lp learned)
	detourMinYards = 200,       -- only walks covering at least this much ground (straight line) are measured
	detourMaxSample = 3,        -- a walk more than 3x longer than the straight line is wandering, not counted
	zoneChangeSeconds = 30,     -- extra time when the next stop is in another zone
	continentChangeSeconds = 900, -- used only when no boat or zeppelin route is known

	-- Travel graph (phase 2) ---------------------------------------------------------
	crossZoneWalkFactor = 1.6,  -- walking into another zone without a known border crossing costs this much more
	flightSpeed = 30,           -- yards per second on a flight path (until real times are learned)
	flightRouteFactor = 1.25,   -- flight routes bend; straight distance x this
	flightOverheadSeconds = 20, -- talking to the flight master, take-off and landing
	flightCopperPerYard = 0.6,  -- cost estimate until real prices are seen at a flight master
	flightSecondsPerGold = 60,  -- how much one gold of flight cost is "worth" in time (0 = ignore cost)
	hearthSeconds = 45,         -- casting the hearthstone plus the loading screen
	hearthCooldownSeconds = 3600, -- the hearthstone's cooldown: it can be planned again after this
	hearthLaterDiscount = 0.5,  -- a saving at the end of the plan counts this much less than one now
	useHearth = true,
	-- boats, zeppelins and the tram: average wait plus the ride, in seconds
	transportSeconds = { boat = 240, zeppelin = 240, tram = 150, portal = 15 },

	-- Work at a stop -------------------------------------------------------------
	npcTalkSeconds = 10,        -- picking up or turning in one quest
	objectiveOverheadSeconds = 45, -- finding the spot / walking around inside an objective area
	killSeconds = 22,           -- one kill of an equal-level mob, including looting and rest
	killSecondsPerLevelAbove = 3, -- extra seconds per mob level above you
	killShareLessPerLevelBelow = 0.07, -- each level a mob is below you makes it this much quicker (7%)
	killFloorShare = 0.35,      -- ...but a kill never takes less than this share of the normal time
	objectSeconds = 12,         -- using / looting one object
	eventSeconds = 20,          -- explore / reach-a-place objectives once you are there
	defaultDropRate = 0.5,      -- chance a quest item drops when Questie has no rate (0-1)
	-- Quest items no mob drops (crafted, sold): buy them. A vendor Questie knows sells it comes
	-- first; else the auction house, when AHledger has seen it listed. The gold counts as time
	-- (flightSecondsPerGold), so a buy is planned only when it's worth the trip and the price.
	buyQuestItems = true,       -- plan buy steps at all
	buyInsteadOfFarming = true, -- also buy items you could farm, when buying is quicker (kill XP counted)
	buySeconds = 30,            -- buying from a vendor
	autoBuy = true,             -- open that vendor and the plan's items are bought for you (hold the
	                            -- autoQuestSkipKey to skip; never more than ahBuyMaxGold in one visit)
	shoppingList = true,        -- the list beside the auction house (UI/Shopping.lua)
	ahBuy = true,               -- also buy at the auction house (needs AHledger prices)
	ahBuyMaxGold = 5,           -- ... at most this many gold for the whole stack
	ahBuySeconds = 60,          -- ... finding it and buying it
	-- What one gold is worth in time when buying: how long it takes to earn it at your level.
	-- nil = from goldPerHourByLevel below (about 15 min per gold at level 33); a number = fixed.
	-- (Gold comes slowly on Forever: the curve is set for that.)
	buySecondsPerGold = nil,
	goldPerHourByLevel = { [10] = 0.5, [20] = 1.5, [30] = 3, [40] = 6, [50] = 10, [60] = 18 },
	defaultKillCount = 8,       -- when the quest text gives no count
	defaultItemCount = 6,
	defaultObjectCount = 4,

	-- Value ------------------------------------------------------------------------
	questXpWeight = 1.0,
	mobXpWeight = 1.0,
	unknownXpPerQuestLevel = 85, -- XP estimate per quest level when Questie has no XP for a quest

	-- Areas --------------------------------------------------------------------------
	clusterRadius = 120,        -- yards: spawns this close count as one objective area
	maxAreasPerObjective = 3,

	-- Dungeons (phase 4) ---------------------------------------------------------------
	-- A dungeon is planned only when its XP per minute beats questing, or when you are grouped.
	dungeons = true,
	groupFindMinutes = 20,      -- finding a group when solo
	groupFindMinutesGrouped = 5, -- when already grouped (/lp group on or in a party)
	dungeonMobXpShare = 0.28,   -- your share of each kill's XP in a 5-player group
	dungeonLevelSlack = 2,      -- plan a dungeon from this many levels below its range to this many above
	-- [Questie dungeon area ID] = { name, lowest level, highest level, average mob level,
	--                               kills in a normal run, minutes for a normal run }
	-- Rough figures for a typical group; edit them to match your runs.
	dungeonData = {
		[2437] = { "Ragefire Chasm", 13, 18, 15, 60, 30 },
		[718]  = { "Wailing Caverns", 17, 24, 20, 110, 60 },
		[1581] = { "The Deadmines", 17, 26, 19, 100, 55 },
		[209]  = { "Shadowfang Keep", 22, 30, 24, 90, 50 },
		[719]  = { "Blackfathom Deeps", 24, 32, 26, 100, 60 },
		[717]  = { "The Stockade", 24, 32, 26, 60, 30 },
		[721]  = { "Gnomeregan", 29, 38, 31, 140, 80 },
		[491]  = { "Razorfen Kraul", 29, 38, 31, 110, 60 },
		[796]  = { "Scarlet Monastery (one wing)", 30, 45, 36, 80, 45 },
		[722]  = { "Razorfen Downs", 37, 46, 39, 100, 60 },
		[1337] = { "Uldaman", 41, 51, 43, 130, 80 },
		[1176] = { "Zul'Farrak", 44, 54, 46, 140, 70 },
		[2100] = { "Maraudon", 46, 55, 48, 150, 90 },
		[1477] = { "The Temple of Atal'Hakkar", 50, 60, 52, 130, 80 },
		[1584] = { "Blackrock Depths", 52, 60, 55, 200, 120 },
		[1583] = { "Lower Blackrock Spire", 55, 60, 58, 150, 90 },
		[2557] = { "Dire Maul", 55, 60, 58, 100, 60 },
		[2057] = { "Scholomance", 58, 60, 59, 150, 90 },
		[2017] = { "Stratholme", 58, 60, 59, 150, 90 },
		-- Forever's own dungeons Questie's dungeon list doesn't have yet: entrance = { area, x, y },
		-- quests = the dungeon quests (Questie doesn't tie them to the dungeon).
		[17780] = { "Krol'dok Stronghold", 40, 45, 42, 110, 60, entrance = { 16591, 37.5, 37.5 },
			-- A Token of Vengeance, Tome of Twilight, Krol'dok Moulding (Tunk drops it in the run)
			quests = { 94975, 94972, 94973 } },
	},

	-- Learning from your play (phase 5) ---------------------------------------------------
	-- Real kill, objective and dungeon times are recorded per character and blended with the
	-- defaults above: after a few samples your own pace counts for more than the defaults.
	useLearned = true,
	learnPriorWeight = 5,       -- the default counts as this many samples
	learnMaxSamples = 30,       -- newer samples keep mattering: older ones fade after this many
	learnMaxGapSeconds = 240,   -- a longer pause between two kills or two objective ticks is a break, not counted

	-- Extra stops on the way (each is added only if the detour is short and it pays off) ----------
	-- "Worth" is in minutes of your current XP rate: what the stop saves or gains you later.
	trainerVisits = true,
	trainerEveryLevels = 2,        -- visit your class trainer after gaining this many levels
	trainerValueMinutes = 15,
	trainerMaxDetourMinutes = 6,
	vendorVisits = true,
	vendorWhenFreeSlots = 3,       -- suggest selling junk when this few bag slots are free...
	repairBelowPercent = 30,       -- ...or when an item's durability drops below this
	vendorValueMinutes = 10,       -- (tripled when gear is about to break)
	vendorMaxDetourMinutes = 5,
	hearthSuggestions = true,
	hubMinStops = 3,               -- this many pick-ups / turn-ins near one inn makes it a hub
	hubRadiusYards = 250,
	hubBetterBy = 1.5,             -- suggest a new inn only if its upcoming quests outweigh your current one's by this much
	bindValueMinutes = 6,
	bindMaxDetourMinutes = 2,

	-- Grinding as filler ---------------------------------------------------------------
	grinding = true,
	grindMinutes = 15,             -- length of one grinding block
	grindMinSpawns = 6,            -- a camp needs at least this many spawns close together
	grindCandidates = 5,           -- best camps offered to the planner
	grindValueFactor = 0.7,        -- grinding counts less than questing (its estimate is less certain)
	grindWhenPlanBelow = 0.75,     -- only grind when quests fill less than this share of the planned hour

	-- Quest log clean-up ---------------------------------------------------------------------
	cleanupAtLogCount = nil,       -- suggest quests to abandon when the log holds this many (nil: 2 under its size, 38 on Forever)

	-- Map ---------------------------------------------------------------------------------
	zoneLevels = true,             -- world map: hovered zone's level range under its name, coloured for you
	mapPins = true,
	mapPinSteps = 5,               -- numbered pins for this many next steps, with a dotted trail
	minimapPins = true,

	-- Waypoints and arrow ---------------------------------------------------------
	useGameWaypoint = true,     -- set the game's own map pin
	followQuestInTracker = true, -- the step's quest (if in your log) is followed like clicking it in the quest tracker
	useTomTom = true,           -- use TomTom's arrow when TomTom is installed
	arrivedYards = 15,          -- the arrow shows "here" inside this distance
	stepSound = true,           -- a quiet sound when a step is finished

	-- Quest NPCs ---------------------------------------------------------------------------
	autoQuests = true,          -- first-run default only. The Auto complete quests checkbox in /zyde is the saved switch.
	autoQuestSkipKey = "SHIFT", -- hold this ("SHIFT", "CTRL" or "ALT") while talking to an NPC to do it yourself
	npcStars = true,            -- the "Target next step's NPC" key also puts the star marker on it
	                            -- (bind it in Key Bindings > AddOns > LevelPlanner)
	itemButton = true,          -- button for your current quest's usable item (bind a key in Key Bindings > AddOns)
}
