-- GearAdvisor config: the one file you edit.
--
-- Every number here is PROVISIONAL. No Forever sims exist for this addon yet, so these are
-- starting guesses. Change them freely; /reload picks up changes (no client restart needed
-- for edits to an existing file).
--
-- UNITS: weights are "AP-equivalents": how much one point of a stat is worth compared with
-- 1 Attack Power (Arms) or 1 Ranged Attack Power (Beast Mastery). So Strength = 2 means
-- "1 Strength is worth 2 Attack Power".
-- Percent stats (hit, crit) are weighted per 1%, NOT per rating point. The addon turns rating
-- into percent for you, at your current level (see `ratings` below).

local _, zyde = ...
zyde.GA = zyde.GA or {}
local ns = zyde.GA
local C = {}
ns.Config = C

---------------------------------------------------------------------------------------------
-- Rating conversions
---------------------------------------------------------------------------------------------
-- Rating needed for +1%. The addon asks the game first (GetCombatRatingBonusForCombatRatingValue),
-- which already accounts for your level. These numbers are only used when the game won't say.
C.ratings = {
	hit = 10,   -- 10 hit rating = 1% hit (reported by SimGearForever, checked in game at level 22)
	crit = 14,  -- 14 crit rating = 1% crit (same source)
}
-- Only used with the fallback numbers above. true = TBC-style: fewer rating per 1% at low
-- levels (rating x (level - 8) / 52). false = the same at every level (what was seen at 22).
C.ratingScalesWithLevel = false

---------------------------------------------------------------------------------------------
-- Hit cap
---------------------------------------------------------------------------------------------
-- Hit % that removes all misses, by how many levels the target is above you.
-- Classic rules with full weapon skill: 5% vs same level, 5.5% vs +1, 6% vs +2, and about 9% vs +3
-- (a raid boss: 8% base miss plus a 1% penalty for the skill gap). Unconfirmed on Forever.
C.hitCap = { [0] = 5, [1] = 5.5, [2] = 6, [3] = 9 }

-- Which target to cap against. "auto" = a dungeon boss (+2) below level 60, a raid boss (+3) at 60.
-- Others: "same" (0), "dungeon" (+2), "raid" (+3). Change it in game with /ga target.
C.defaultTarget = "auto"

-- Where your current hit % comes from.
--   The addon reads the hit you get from rating (GetCombatRatingBonus) if the game offers it,
--   otherwise it adds up the hit on your equipped gear.
-- includeHitModifier: also add GetHitModifier(). Turn on ONLY if /ga probe shows it holds talent hit
--   and NOT gear hit (otherwise hit is counted twice).
C.includeHitModifier = false
-- Hit % from talents or anything else not on gear (e.g. Hunter "Surefooted" 3/3 = 3).
C.extraHitPercent = 0

---------------------------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------------------------
-- Changes smaller than this (in %) count as "about the same", not an upgrade or downgrade.
C.minUpgradePct = 0.5

-- Items you can't use yet (level too low, or an armour type you haven't learned):
-- if you can use it within this many levels it shows as a "future upgrade"; further off it's
-- just "can't use yet", because you'll have outlevelled it by then.
C.futureUpgradeLevels = 3

---------------------------------------------------------------------------------------------
-- Profiles: which weight set each class and spec uses
---------------------------------------------------------------------------------------------
-- Spec names come from the talent tree with the most points. Specs without their own profile
-- yet use the class's main one (you'll see a note in /ga score).
C.specProfiles = {
	WARRIOR = { ARMS = "WARRIOR_ARMS", FURY = "WARRIOR_ARMS", PROTECTION = "WARRIOR_ARMS", default = "WARRIOR_ARMS" },
	HUNTER = { BEAST_MASTERY = "HUNTER_BM", MARKSMANSHIP = "HUNTER_BM", SURVIVAL = "HUNTER_BM", default = "HUNTER_BM" },
}

-- Weight keys (anything missing counts as 0):
--   Strength, Agility, Stamina, Intellect, Spirit, AttackPower, RangedAttackPower, Armor
--   HitPercent          per 1% hit, until the hit cap
--   HitPercentPastCap   per 1% hit beyond the cap (small: only helps vs higher-level targets)
--   CritPercent         per 1% crit
--   ExpertiseRating     per point of expertise RATING. Forever's new stat; what it does is unknown.
--   WeaponSkill         per point of "+X weapon skill" on gear (heavily reduced on Forever).
--                       Not checked against your weapon type yet, so keep it small.
--   TwoHandDPS, MainHandDPS, OffHandDPS, RangedDPS   per 1 weapon DPS in that slot
--   TwoHandSpeed, MainHandSpeed, RangedSpeed   per 1 second of weapon speed ABOVE the
--                       reference speed in `speedRef` (negative below it). Rewards slow weapons.
--   Defense, Dodge, Parry, Block, BlockValue    tank stats (0 for these specs)
--
-- Each profile lists weights at a few levels; the addon blends between them for your level.
C.profiles = {}

-- ARMS WARRIOR, in Attack Power equivalents.
-- Mortal Strike, Overpower and Slam add weapon damage, so weapon DPS and slow speed matter a lot.
C.profiles.WARRIOR_ARMS = {
	label = "Arms Warrior",
	hitKind = "melee",   -- which hit rating counts toward the cap: "melee" or "ranged"
	speedRef = { TwoHandSpeed = 3.3, MainHandSpeed = 2.6 },
	brackets = {
		{ level = 10, weights = {
			Strength = 2,          -- 1 Str = 2 AP for warriors
			Agility = 0.6,         -- mostly crit; little crit per Agility at low level
			AttackPower = 1,
			Stamina = 0.5,         -- levelling survival, not damage
			Spirit = 0.1,          -- a little out-of-combat regen
			Armor = 0.02,
			HitPercent = 7,
			HitPercentPastCap = 0.5,
			CritPercent = 6,
			ExpertiseRating = 0,   -- UNKNOWN: set once we know what expertise does
			WeaponSkill = 0,       -- UNKNOWN on Forever
			TwoHandDPS = 14,       -- 14 AP = 1 DPS on white hits, plus the weapon-damage specials
			MainHandDPS = 10,
			OffHandDPS = 2,
			TwoHandSpeed = 5,
			MainHandSpeed = 3,
		} },
		{ level = 30, weights = {
			Strength = 2, Agility = 0.8, AttackPower = 1, Stamina = 0.3, Spirit = 0.05, Armor = 0.01,
			HitPercent = 15, HitPercentPastCap = 0.5, CritPercent = 13,
			ExpertiseRating = 0, WeaponSkill = 0,
			TwoHandDPS = 15, MainHandDPS = 11, OffHandDPS = 3,
			TwoHandSpeed = 15, MainHandSpeed = 8,
		} },
		{ level = 60, weights = {
			Strength = 2, Agility = 1.0, AttackPower = 1, Stamina = 0.1, Spirit = 0, Armor = 0.005,
			HitPercent = 25, HitPercentPastCap = 1, CritPercent = 22,
			ExpertiseRating = 0, WeaponSkill = 0,
			TwoHandDPS = 16, MainHandDPS = 12, OffHandDPS = 4,
			TwoHandSpeed = 30, MainHandSpeed = 15,
		} },
	},
}

-- BEAST MASTERY HUNTER, in Ranged Attack Power equivalents.
-- The ranged weapon carries the damage; melee weapons are mostly stat sticks.
C.profiles.HUNTER_BM = {
	label = "Beast Mastery Hunter",
	hitKind = "ranged",
	speedRef = { RangedSpeed = 2.8 },
	brackets = {
		{ level = 10, weights = {
			Agility = 2.1,         -- 1 Agi = 2 RAP for hunters, plus a little crit
			RangedAttackPower = 1,
			AttackPower = 1,       -- on Forever plain "+Attack Power" reportedly raises ranged AP too.
			                       -- If it turns out to be melee only, set this to 0.1.
			Strength = 0.1,        -- melee only
			Stamina = 0.5,
			Intellect = 0.2,       -- mana for shots and Mend Pet
			Spirit = 0.1,
			Armor = 0.02,
			HitPercent = 7,
			HitPercentPastCap = 0.3,
			CritPercent = 6,
			ExpertiseRating = 0,   -- UNKNOWN; probably melee only, so likely ~0 for BM
			WeaponSkill = 0,
			RangedDPS = 14,
			TwoHandDPS = 1,
			MainHandDPS = 0.7,
			OffHandDPS = 0.3,
			RangedSpeed = 2,       -- Aimed Shot and Multi-Shot add weapon damage: slower is a bit better
		} },
		{ level = 30, weights = {
			Agility = 2.3, RangedAttackPower = 1, AttackPower = 1, Strength = 0.1, Stamina = 0.3,
			Intellect = 0.3, Spirit = 0.05, Armor = 0.01,
			HitPercent = 14, HitPercentPastCap = 0.3, CritPercent = 12,
			ExpertiseRating = 0, WeaponSkill = 0,
			RangedDPS = 16, TwoHandDPS = 1, MainHandDPS = 0.7, OffHandDPS = 0.3, RangedSpeed = 5,
		} },
		{ level = 60, weights = {
			Agility = 2.6, RangedAttackPower = 1, AttackPower = 1, Strength = 0.05, Stamina = 0.15,
			Intellect = 0.3, Spirit = 0, Armor = 0.005,
			HitPercent = 24, HitPercentPastCap = 0.5, CritPercent = 20,
			ExpertiseRating = 0, WeaponSkill = 0,
			RangedDPS = 18, TwoHandDPS = 1, MainHandDPS = 0.7, OffHandDPS = 0.3, RangedSpeed = 8,
		} },
	},
}

---------------------------------------------------------------------------------------------
-- What each class can wear and wield
---------------------------------------------------------------------------------------------
-- Weapon types (item subclass IDs): 0 one-hand axe, 1 two-hand axe, 2 bow, 3 gun, 4 one-hand mace,
-- 5 two-hand mace, 6 polearm, 7 one-hand sword, 8 two-hand sword, 10 staff, 13 fist weapon,
-- 15 dagger, 16 thrown, 18 crossbow, 19 wand.
-- Armour types: 0 misc (rings, necks, trinkets), 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield.
-- armorSpells: the skill spell that lets you wear an armour type (Mail 8737, Plate Mail 750). The
--   addon asks the game whether you know it, so this stays right whatever level Forever teaches it.
-- armorFromLevel: the level you learn it, only used for the "from level N" message.
--   Hunter mail at 40 and warrior plate at 40, as in Classic (user, 2026-11-09).
C.classGear = {
	WARRIOR = {
		weapons = { [0]=true, [1]=true, [2]=true, [3]=true, [4]=true, [5]=true, [6]=true, [7]=true, [8]=true, [10]=true, [13]=true, [15]=true, [16]=true, [18]=true },
		armor = { [0]=true, [1]=true, [2]=true, [3]=true, [4]=true, [6]=true },
		armorSpells = { [3] = 8737, [4] = 750 },
		armorFromLevel = { [4] = 40 },
	},
	HUNTER = {
		weapons = { [0]=true, [1]=true, [2]=true, [3]=true, [6]=true, [7]=true, [8]=true, [10]=true, [13]=true, [15]=true, [16]=true, [18]=true },
		armor = { [0]=true, [1]=true, [2]=true, [3]=true },
		armorSpells = { [3] = 8737 },
		armorFromLevel = { [3] = 40 },
	},
}

---------------------------------------------------------------------------------------------
-- Special items: procs, on-use effects and anything the stat list misses
---------------------------------------------------------------------------------------------
-- Keyed by item ID (from Wowhead's Forever pages, or /ga score which prints it).
-- Each entry gives extra value per profile key, or `all` for every profile:
--   value = N            a flat N AP-equivalents
--   any weight key = N   extra stat, e.g. AttackPower = 30, CritPercent = 1, HitPercent = 1
-- `note` is shown in /ga score. Don't copy Classic numbers: Forever changed many items.
C.special = {
	-- [12345] = { note = "Chance on hit: +100 AP for 10s, ~ +20 AP average", all = { AttackPower = 20 } },
	-- [23456] = { note = "Use: +200 AP for 20s every 2 min", WARRIOR_ARMS = { value = 35 }, HUNTER_BM = { value = 40 } },
}

---------------------------------------------------------------------------------------------
-- Item set bonuses
---------------------------------------------------------------------------------------------
-- Each set: its item IDs, and the bonus per number of pieces (same keys as weights, or value = N).
-- A bonus counts in full when you'd have enough pieces, and at `setNearlyFactor` when you'd be
-- one piece short (so collecting the set shows as progress).
-- Hit and crit in set bonuses are counted at their plain weight, ignoring the hit cap.
C.setNearlyFactor = 0.5
C.sets = {
	-- ["Example Set"] = {
	-- 	items = { 11111, 11112, 11113 },
	-- 	bonuses = { [2] = { AttackPower = 20 }, [3] = { CritPercent = 1 } },
	-- },
}
