-- GearAdvisor config: the one file you edit.
--
-- Arms and BM were hand-tuned first; every other class comes from MythicSim's Forever sims plus
-- estimates (see "EVERY OTHER CLASS AND SPEC"). All of it is a starting point. Change them freely; /reload picks up changes (no client restart needed
-- for edits to an existing file).
--
-- UNITS: each profile has its own: Arms in Attack Power, BM in Ranged Attack Power, the rest in
-- the unit their sim used (Strength, Agility, spell damage, healing...). So Strength = 2 in Arms
-- means "1 Strength is worth 2 Attack Power". Only the ratios inside one profile matter.
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
-- Spells: 4% miss vs same level, 5% vs +1, 6% vs +2, 17% vs +3, and never under 1%, so the gear
-- you need is 3 / 4 / 5 / 16%. MythicSim's Forever engine uses 16% vs a raid boss.
C.spellHitCap = { [0] = 3, [1] = 4, [2] = 5, [3] = 16 }

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
-- Spec names come from the talent tree with the most points; `default` is used before you have
-- any. /ga spec <name> picks one by hand (e.g. /ga spec bear, /ga spec fury).
C.specProfiles = {
	WARRIOR = { ARMS = "WARRIOR_ARMS", FURY = "WARRIOR_FURY", PROTECTION = "WARRIOR_PROT", default = "WARRIOR_ARMS" },
	HUNTER = { BEAST_MASTERY = "HUNTER_BM", MARKSMANSHIP = "HUNTER_MM", SURVIVAL = "HUNTER_SV", default = "HUNTER_BM" },
	ROGUE = { ASSASSINATION = "ROGUE_ASSASSINATION", COMBAT = "ROGUE_COMBAT", SUBTLETY = "ROGUE_SUBTLETY", default = "ROGUE_COMBAT" },
	PALADIN = { HOLY = "PALADIN_HOLY", PROTECTION = "PALADIN_PROT", RETRIBUTION = "PALADIN_RET", default = "PALADIN_RET" },
	SHAMAN = { ELEMENTAL = "SHAMAN_ELE", ENHANCEMENT = "SHAMAN_ENH", RESTORATION = "SHAMAN_RESTO", default = "SHAMAN_ENH" },
	MAGE = { ARCANE = "MAGE_ARCANE", FIRE = "MAGE_FIRE", FROST = "MAGE_FROST", default = "MAGE_FROST" },
	WARLOCK = { AFFLICTION = "WARLOCK_AFF", DEMONOLOGY = "WARLOCK_DEMO", DESTRUCTION = "WARLOCK_DESTRO", default = "WARLOCK_AFF" },
	PRIEST = { DISCIPLINE = "PRIEST_HEAL", HOLY = "PRIEST_HEAL", SHADOW = "PRIEST_SHADOW", default = "PRIEST_SHADOW" },
	-- Talents can't tell cat from bear: feral uses cat; /ga spec bear switches.
	DRUID = { BALANCE = "DRUID_BALANCE", FERAL = "DRUID_CAT", BEAR = "DRUID_BEAR", RESTORATION = "DRUID_RESTO", default = "DRUID_CAT" },
}

-- Weight keys (anything missing counts as 0):
--   Strength, Agility, Stamina, Intellect, Spirit, AttackPower, RangedAttackPower, Armor
--   HitPercent          per 1% hit, until the hit cap
--   HitPercentPastCap   per 1% hit beyond the cap (small: only helps vs higher-level targets)
--   CritPercent         per 1% crit
--   ExpertiseRating     per point of expertise RATING (10 rating = 1% less dodge and parry)
--   HasteRating, ArmorPen   per rating point
--   SpellPower          per point of "damage and healing done by spells"
--   HealingPower        per point of healing only
--   HolyPower, ShadowPower, FirePower, FrostPower, ArcanePower, NaturePower   one school's damage
--   ManaRegen           per 1 mana per 5 seconds
--   FeralAttackPower    attack power in cat and bear form
--   SpellPen            spell penetration (0 everywhere for now)
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
			ExpertiseRating = 0.7, -- 1 rating = -0.1% dodge (MythicSim: 1.04 Str = 2.3 AP at 60)
			HasteRating = 0.5,     -- MythicSim: 0.83 Str = 1.8 AP at 60
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
			ExpertiseRating = 1.4, HasteRating = 1.1, ArmorPen = 0.27, WeaponSkill = 0,
			TwoHandDPS = 15, MainHandDPS = 11, OffHandDPS = 3,
			TwoHandSpeed = 15, MainHandSpeed = 8,
		} },
		{ level = 60, weights = {
			Strength = 2, Agility = 1.0, AttackPower = 1, Stamina = 0.1, Spirit = 0, Armor = 0.005,
			HitPercent = 25, HitPercentPastCap = 1, CritPercent = 22,
			ExpertiseRating = 2.3, HasteRating = 1.8, ArmorPen = 0.45, WeaponSkill = 0,
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

-- EVERY OTHER CLASS AND SPEC (added 2026-11-22).
-- Level-60 numbers are from MythicSim's Forever sims (mythicsim.com/wow-forever/stat-priority, engine
-- a667dce84, client 1.60.1.70707): damage per point against a level 63 boss, as EP. Each profile
-- uses that sim's own unit (named on its `unit` line) instead of Attack Power. That's fine: upgrades
-- are a % of your whole gear's score, so the unit cancels out.
-- Converted for this file: hit and crit are per 1% (sim EP per rating x 10 for hit, x 14 for crit);
-- haste, expertise and armour penetration stay per rating point. Weapon DPS = the sim's "weapon
-- damage" EP x a typical weapon speed. Forever's single hit rating counts for melee and spells,
-- so hybrids (Enhancement, Retribution) add both.
-- NOT from sims (my estimates, marked "est."): healer weights (no healer sims exist yet), tank
-- survival weights (the sims measure damage only), levelling weights, and wand DPS.
-- Spell penetration is left at 0: it only matters against raid bosses with resistances.
--
-- levelled() builds the level 10 and 30 brackets from the level-60 set: percent and rating stats
-- are worth 30% (level 10) and 60% (level 30) as much, as with Arms and BM above, and `early`
-- weights (Stamina for levelling, mana for casters, wands) are added in full at 10, half at 30.
local RAMP = { HitPercent = true, HitPercentPastCap = true, CritPercent = true, HasteRating = true,
	ExpertiseRating = true, ArmorPen = true }
local function levelled(w60, early)
	local brackets = {}
	for _, step in ipairs({ { level = 10, f = 0.3, e = 1 }, { level = 30, f = 0.6, e = 0.5 } }) do
		local w = {}
		for k, v in pairs(w60) do w[k] = RAMP[k] and v * step.f or v end
		for k, v in pairs(early or {}) do w[k] = (w[k] or 0) + v * step.e end
		brackets[#brackets + 1] = { level = step.level, weights = w }
	end
	brackets[#brackets + 1] = { level = 60, weights = w60 }
	return brackets
end

-- Survival weights for tanks (est.), in Strength or Agility units, added to the threat weights.
local TANK = { Stamina = 1.5, Armor = 0.1, Defense = 1.5, Dodge = 1.2, Parry = 1.0, Block = 0.6, BlockValue = 0.3 }
local function plus(a, b)
	local t = {}
	for k, v in pairs(a) do t[k] = v end
	for k, v in pairs(b) do t[k] = (t[k] or 0) + v end
	return t
end

-- Healers (est.; no Forever healer sims yet). Unit: 1 +healing. Order from the Forever guides:
-- healing > Intellect > Spirit / mana per 5 > crit. Hit is worthless.
local function healer(label, w)
	return { label = label, unit = "healing", hitKind = "spell",
		brackets = levelled(plus({ HealingPower = 1, SpellPower = 1, HitPercent = 0, Stamina = 0.1, HasteRating = 0.6 }, w),
			{ Stamina = 0.3, SpellPower = 0.3, RangedDPS = 3 }) }   -- levelling: you also deal damage
end

---------------------------------------------------------------------------------------------
-- Warrior
C.profiles.WARRIOR_FURY = {   -- sim: Fury 17/32/2
	label = "Fury Warrior", unit = "Strength", hitKind = "melee",
	brackets = levelled({
		Strength = 1, Agility = 0.80, AttackPower = 0.45, Stamina = 0.05, Armor = 0.002,
		HitPercent = 13.3, HitPercentPastCap = 5,   -- dual-wield white swings keep gaining hit (est.)
		CritPercent = 14.3, HasteRating = 0.87, ExpertiseRating = 1.53, ArmorPen = 0.19,
		MainHandDPS = 5.4, OffHandDPS = 3.6, TwoHandDPS = 6.3,   -- est. from 1 Str = 2.2 AP
	}, { Stamina = 0.25, Armor = 0.008 }),
}
C.profiles.WARRIOR_PROT = {   -- sim: Protection 0/20/31 (threat); survival est.
	label = "Protection Warrior", unit = "Strength", hitKind = "melee",
	brackets = levelled(plus({
		Strength = 1, Agility = 0.56, AttackPower = 0.43, CritPercent = 11.9, HasteRating = 0.71,
		ExpertiseRating = 4.14, ArmorPen = 0.21, BlockValue = 0.78,
		HitPercent = 8,   -- the sim's build was hit-capped (measured 0); est. below the cap
		MainHandDPS = 4.5, TwoHandDPS = 1,
	}, TANK)),
}

-- Hunter (Beast Mastery is above)
C.profiles.HUNTER_MM = {   -- sim: Marksmanship 5/31/15
	label = "Marksmanship Hunter", unit = "Agility", hitKind = "ranged", speedRef = { RangedSpeed = 2.8 },
	brackets = levelled({
		Agility = 1, RangedAttackPower = 0.30, AttackPower = 0.10, Strength = 0.11, Intellect = 0.58,
		ManaRegen = 0.21, Stamina = 0.05, Armor = 0.002,
		HitPercent = 11.1, HitPercentPastCap = 0.2, CritPercent = 11.8, HasteRating = 0.38, ArmorPen = 0.13,
		ExpertiseRating = 0.15,   -- sim 0.31 with melee weaving; halved
		RangedDPS = 4.2, RangedSpeed = 1.5, TwoHandDPS = 0.3, MainHandDPS = 0.2, OffHandDPS = 0.1,
	}, { Stamina = 0.2, Armor = 0.008 }),
}
C.profiles.HUNTER_SV = {   -- sim: Survival 0/20/31
	label = "Survival Hunter", unit = "Agility", hitKind = "ranged", speedRef = { RangedSpeed = 2.8 },
	brackets = levelled({
		Agility = 1, RangedAttackPower = 0.20, AttackPower = 0.16, Strength = 0.17, Intellect = 0.67,
		ManaRegen = 0.39, Stamina = 0.05, Armor = 0.002,
		HitPercent = 9,   -- the sim's build was hit-capped (measured 0); est.
		HitPercentPastCap = 0.2, CritPercent = 10.8, HasteRating = 0.41, ArmorPen = 0.13,
		ExpertiseRating = 0.3,   -- sim 0.62 with light weaving; halved
		RangedDPS = 3.75, RangedSpeed = 1, TwoHandDPS = 0.3, MainHandDPS = 0.2, OffHandDPS = 0.1,
	}, { Stamina = 0.2, Armor = 0.008 }),
}

-- Rogue
local function rogue(label, w)
	return { label = label, unit = "Attack Power", hitKind = "melee",
		brackets = levelled(plus({ Strength = 1.10, AttackPower = 1, Stamina = 0.1, Armor = 0.005,
			HitPercentPastCap = 6, RangedDPS = 0.5 }, w), { Stamina = 0.4, Armor = 0.015 }) }
end
C.profiles.ROGUE_ASSASSINATION = rogue("Assassination Rogue", {   -- sim: Mutilate 31/20/0
	Agility = 2.05, HitPercent = 19, CritPercent = 25.6, HasteRating = 1.36, ExpertiseRating = 2.99, ArmorPen = 0.42,
	MainHandDPS = 11, OffHandDPS = 5,   -- weapon damage 8.92 x 1.8 (daggers)
})
C.profiles.ROGUE_COMBAT = rogue("Combat Rogue", {   -- sim: Combat Maces 21/30/0
	Agility = 1.81, HitPercent = 22.8, CritPercent = 18.8, HasteRating = 1.60, ExpertiseRating = 2.80, ArmorPen = 0.35,
	MainHandDPS = 13, OffHandDPS = 6.5,   -- weapon damage 7.48 x 2.6
})
C.profiles.ROGUE_SUBTLETY = rogue("Subtlety Rogue", {   -- sim: Hemorrhage 12/8/31
	Agility = 1.93, HitPercent = 21.5, CritPercent = 21.7, HasteRating = 1.54, ExpertiseRating = 2.56, ArmorPen = 0.26,
	MainHandDPS = 9, OffHandDPS = 4,   -- weapon damage 5.89 x 2.2
})

-- Paladin
C.profiles.PALADIN_RET = {   -- sim: Retribution 12/8/31
	label = "Retribution Paladin", unit = "Strength", hitKind = "melee",
	brackets = levelled({
		Strength = 1, Agility = 1.36, AttackPower = 0.41, Intellect = 1.60, SpellPower = 2.11,
		HolyPower = 1.9,   -- est.: seals and Exorcism are Holy
		ManaRegen = 1.0,   -- est.
		Stamina = 0.05, Armor = 0.002,
		HitPercent = 10,   -- the sim's build was hit-capped (measured 0); est.
		CritPercent = 24.2, HasteRating = 1.48, ExpertiseRating = 2.86, ArmorPen = 0.10,
		TwoHandDPS = 6.6, MainHandDPS = 4.5,   -- est. from 1 Str = 2.4 AP
	}, { Stamina = 0.25, Armor = 0.008 }),
}
C.profiles.PALADIN_PROT = {   -- sim: Protection 10/31/10 (threat); survival est.
	label = "Protection Paladin", unit = "Strength", hitKind = "melee",
	brackets = levelled(plus({
		Strength = 1, Agility = 0.90, AttackPower = 0.42, SpellPower = 1.56, HolyPower = 1.4,
		Intellect = 0.3,   -- sim 0.05; mana keeps you tanking (est.)
		CritPercent = 17.8, HasteRating = 0.94, ExpertiseRating = 4.46, ArmorPen = 0.11, Block = 1.72,
		HitPercent = 8.7,   -- the sim's spell hit (its melee hit was capped)
		MainHandDPS = 4.5,
	}, TANK)),
}
C.profiles.PALADIN_HOLY = healer("Holy Paladin", {
	Intellect = 0.8, Spirit = 0.1, ManaRegen = 2.0,
	CritPercent = 8,   -- Illumination refunds mana on crits
})

-- Shaman
C.profiles.SHAMAN_ELE = {   -- sim: Elemental 31/11/9
	label = "Elemental Shaman", unit = "spell damage", hitKind = "spell",
	brackets = levelled({
		SpellPower = 1, NaturePower = 0.88, FirePower = 0.1, FrostPower = 0.05, Intellect = 0.19,
		Stamina = 0.05, HitPercent = 13.2, HitPercentPastCap = 0, CritPercent = 9.7, HasteRating = 0.96,
	}, { Stamina = 0.3, Intellect = 0.3, Spirit = 0.1, ManaRegen = 1 }),
}
C.profiles.SHAMAN_ENH = {   -- sim: Enhancement 17/31/3
	label = "Enhancement Shaman", unit = "Attack Power", hitKind = "melee",
	brackets = levelled({
		Strength = 2.20, Agility = 1.43, AttackPower = 1, Intellect = 1.96, SpellPower = 1.37, NaturePower = 0.63,
		Stamina = 0.1, Armor = 0.004,
		-- One hit rating: melee (capped in the sim, est. 1.4/rating below it) plus spell hit 2.08.
		HitPercent = 35, HitPercentPastCap = 20.8,
		CritPercent = 37,   -- crit 1.84 + spell crit 0.82 per rating, x 14
		HasteRating = 2.15, ExpertiseRating = 4.06, ArmorPen = 0.35,
		TwoHandDPS = 18, MainHandDPS = 14, OffHandDPS = 6,   -- est.: Windfury adds weapon damage
	}, { Stamina = 0.5, Armor = 0.015, ManaRegen = 1 }),
}
C.profiles.SHAMAN_RESTO = healer("Restoration Shaman", {
	Intellect = 0.6, Spirit = 0.15, ManaRegen = 2.5, CritPercent = 6,
})

-- Mage
local function caster(label, w, early)
	return { label = label, unit = "spell damage", hitKind = "spell",
		brackets = levelled(plus({ SpellPower = 1, Stamina = 0.05, HitPercentPastCap = 0 }, w),
			plus({ Stamina = 0.3, Intellect = 0.3, Spirit = 0.2, RangedDPS = 3 }, early or {})) }   -- RangedDPS = wands
end
C.profiles.MAGE_ARCANE = caster("Arcane Mage", {   -- sim: Arc Fire 32/16/3
	ArcanePower = 0.56, FirePower = 0.44, Intellect = 0.99, Spirit = 0.27, ManaRegen = 0.43,
	HitPercent = 17.9, CritPercent = 11.2, HasteRating = 0.66,
})
C.profiles.MAGE_FIRE = caster("Fire Mage", {   -- sim: Fire Arcane Blast 16/32/3
	FirePower = 0.88, ArcanePower = 0.12, Intellect = 0.47, Spirit = 0.11, ManaRegen = 0.25,
	HitPercent = 15.3, CritPercent = 10.6, HasteRating = 0,   -- the sim measured haste at about 0
})
C.profiles.MAGE_FROST = caster("Frost Mage", {   -- sim: Missile Barrage 14/5/32
	FrostPower = 0.85, ArcanePower = 0.15, Intellect = 0.18, ManaRegen = 0.02,
	HitPercent = 16.4, CritPercent = 9.1, HasteRating = 1.09,
})

-- Warlock
C.profiles.WARLOCK_AFF = caster("Affliction Warlock", {   -- sim: Affliction 35/11/5
	ShadowPower = 1.0, Intellect = 0.17, HitPercent = 5.2, CritPercent = 9.7, HasteRating = 0.22,
})
C.profiles.WARLOCK_DEMO = caster("Demonology Warlock", {   -- sim: Demonic Pact 2/31/18
	ShadowPower = 0.79, FirePower = 0.18, Intellect = 0.45, ManaRegen = 0.28,
	HitPercent = 12.9, CritPercent = 10.8, HasteRating = 0.87,
})
C.profiles.WARLOCK_DESTRO = caster("Destruction Warlock", {   -- sim: Shadow Bolt 20/0/31
	ShadowPower = 0.77, FirePower = 0.21, Intellect = 0.50, ManaRegen = 0.30,
	HitPercent = 11.4, CritPercent = 11.8, HasteRating = 0.79,
})

-- Priest
C.profiles.PRIEST_SHADOW = caster("Shadow Priest", {   -- sim: Shadow 17/0/34
	ShadowPower = 1.0, Intellect = 0.26, HitPercent = 11.9, CritPercent = 12.7, HasteRating = 0.65,
}, { Spirit = 0.2 })   -- levelling: Spirit Tap
C.profiles.PRIEST_HEAL = healer("Healing Priest", {
	Intellect = 0.6, Spirit = 0.5, ManaRegen = 2.0, CritPercent = 5,
})

-- Druid
C.profiles.DRUID_BALANCE = caster("Balance Druid", {   -- sim: Moonkin 41/0/10
	ArcanePower = 0.64, NaturePower = 0.36, Intellect = 0.28, ManaRegen = 0.14,
	HitPercent = 11.2, CritPercent = 9.4, HasteRating = 0.84,
})
C.profiles.DRUID_CAT = {   -- sim: Feral 9/32/10. Weapon damage doesn't matter in forms.
	label = "Feral Druid (cat)", unit = "Agility", hitKind = "melee",
	brackets = levelled({
		Agility = 1, Strength = 0.89, AttackPower = 0.36, FeralAttackPower = 0.36, Stamina = 0.05, Armor = 0.003,
		HitPercent = 6.9, CritPercent = 10.9, HasteRating = 0.55, ExpertiseRating = 0.67, ArmorPen = 0.12,
	}, { Stamina = 0.25, Armor = 0.01, Intellect = 0.1 }),
}
C.profiles.DRUID_BEAR = {   -- sim: Bear Tank 0/41/10 (threat); survival est. Use /ga spec bear.
	label = "Feral Druid (bear)", unit = "Agility", hitKind = "melee",
	brackets = levelled(plus({
		Agility = 1, Strength = 1.62, AttackPower = 0.74, FeralAttackPower = 0.74,
		HitPercent = 28.9, CritPercent = 18.2, HasteRating = 0.93, ExpertiseRating = 5.76, ArmorPen = 0.30,
	}, { Stamina = 1.5, Armor = 0.12, Defense = 1.2, Dodge = 1.2 })),
}
C.profiles.DRUID_RESTO = healer("Restoration Druid", {
	Intellect = 0.6, Spirit = 0.45, ManaRegen = 2.0, CritPercent = 4,
})

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
	ROGUE = {   -- daggers, one-hand swords, maces and fist weapons; bows, guns, crossbows, thrown
		weapons = { [2]=true, [3]=true, [4]=true, [7]=true, [13]=true, [15]=true, [16]=true, [18]=true },
		armor = { [0]=true, [1]=true, [2]=true },
	},
	-- Paladin and shaman mail at 40, paladin plate at 40, as in Classic (unconfirmed on Forever;
	-- the addon asks the game whether you know the skill anyway).
	PALADIN = {   -- axes, maces, swords (one- and two-hand), polearms; shields
		weapons = { [0]=true, [1]=true, [4]=true, [5]=true, [6]=true, [7]=true, [8]=true },
		armor = { [0]=true, [1]=true, [2]=true, [3]=true, [4]=true, [6]=true },
		armorSpells = { [3] = 8737, [4] = 750 },
		armorFromLevel = { [3] = 40, [4] = 40 },
	},
	SHAMAN = {   -- axes, maces (one- and two-hand), staves, daggers, fist weapons; shields
		weapons = { [0]=true, [1]=true, [4]=true, [5]=true, [10]=true, [13]=true, [15]=true },
		armor = { [0]=true, [1]=true, [2]=true, [3]=true, [6]=true },
		armorSpells = { [3] = 8737 },
		armorFromLevel = { [3] = 40 },
	},
	DRUID = {   -- maces (one- and two-hand), staves, daggers, fist weapons
		weapons = { [4]=true, [5]=true, [10]=true, [13]=true, [15]=true },
		armor = { [0]=true, [1]=true, [2]=true },
	},
	PRIEST = {   -- one-hand maces, staves, daggers, wands
		weapons = { [4]=true, [10]=true, [15]=true, [19]=true },
		armor = { [0]=true, [1]=true },
	},
	MAGE = {   -- one-hand swords, staves, daggers, wands
		weapons = { [7]=true, [10]=true, [15]=true, [19]=true },
		armor = { [0]=true, [1]=true },
	},
	WARLOCK = {   -- one-hand swords, staves, daggers, wands
		weapons = { [7]=true, [10]=true, [15]=true, [19]=true },
		armor = { [0]=true, [1]=true },
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
