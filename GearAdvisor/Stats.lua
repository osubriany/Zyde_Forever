-- Stats: reads an item link into a plain stat table. Everything is read live from the game
-- (never from Classic data): C_Item.GetItemStats for the stat list, and the item's tooltip text
-- for weapon speed and anything the stat list leaves out.
local _, zyde = ...
zyde.GA = zyde.GA or {}
local ns = zyde.GA

local Stats = {}
ns.Stats = Stats

local GetItemStatsFn = (C_Item and C_Item.GetItemStats) or GetItemStats
local GetItemInfoFn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstantFn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

-- Game stat key -> our stat name. Keys marked "confirmed" were seen in game on Forever (by
-- SimGearForever's author, 2026-10); the others are the standard modern-client names, included
-- in case Forever uses them. /ga probe and /ga score list any key we don't know.
Stats.KEY_MAP = {
	ITEM_MOD_STRENGTH_SHORT = "Strength",             -- confirmed
	ITEM_MOD_AGILITY_SHORT = "Agility",               -- confirmed
	ITEM_MOD_STAMINA_SHORT = "Stamina",               -- confirmed
	ITEM_MOD_INTELLECT_SHORT = "Intellect",           -- confirmed
	ITEM_MOD_SPIRIT_SHORT = "Spirit",                 -- confirmed
	ITEM_MOD_ATTACK_POWER_SHORT = "AttackPower",      -- confirmed
	ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "RangedAttackPower", -- confirmed
	ITEM_MOD_HIT_RATING_SHORT = "HitRating",          -- confirmed: one rating for melee, ranged, spells
	ITEM_MOD_CRIT_RATING_SHORT = "CritRating",        -- confirmed: same
	ITEM_MOD_HIT_MELEE_RATING_SHORT = "HitMeleeRating",
	ITEM_MOD_HIT_RANGED_RATING_SHORT = "HitRangedRating",
	ITEM_MOD_CRIT_MELEE_RATING_SHORT = "CritMeleeRating",
	ITEM_MOD_CRIT_RANGED_RATING_SHORT = "CritRangedRating",
	ITEM_MOD_EXPERTISE_RATING_SHORT = "ExpertiseRating", -- not seen yet
	ITEM_MOD_WEAPON_SKILL_RATING_SHORT = "WeaponSkill",  -- not seen yet
	ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "DPS",         -- confirmed
	RESISTANCE0_NAME = "Armor",                       -- confirmed (school 0 = armour)
	ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "Defense",  -- confirmed
	ITEM_MOD_DODGE_RATING_SHORT = "Dodge",            -- confirmed
	ITEM_MOD_PARRY_RATING_SHORT = "Parry",            -- confirmed
	ITEM_MOD_BLOCK_RATING_SHORT = "Block",            -- confirmed
	ITEM_MOD_BLOCK_VALUE_SHORT = "BlockValue",        -- confirmed
	-- Known, but worth nothing to Arms or BM: kept so they don't show as "unknown".
	ITEM_MOD_SPELL_POWER_SHORT = "SpellPower",
	ITEM_MOD_SPELL_POWER = "SpellPower",
	ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "SpellPower",
	ITEM_MOD_SPELL_HEALING_DONE_SHORT = "HealingPower",
	ITEM_MOD_HOLY_DAMAGE_DONE_SHORT = "SchoolPower",
	ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT = "SchoolPower",
	ITEM_MOD_FIRE_DAMAGE_DONE_SHORT = "SchoolPower",
	ITEM_MOD_FROST_DAMAGE_DONE_SHORT = "SchoolPower",
	ITEM_MOD_ARCANE_DAMAGE_DONE_SHORT = "SchoolPower",
	ITEM_MOD_NATURE_DAMAGE_DONE_SHORT = "SchoolPower",
	ITEM_MOD_MANA_REGENERATION_SHORT = "ManaRegen",
	ITEM_MOD_HEALTH_REGEN_SHORT = "HealthRegen",
	RESISTANCE1_NAME = "Resistance", RESISTANCE2_NAME = "Resistance", RESISTANCE3_NAME = "Resistance",
	RESISTANCE4_NAME = "Resistance", RESISTANCE5_NAME = "Resistance", RESISTANCE6_NAME = "Resistance",
}

-- Some keys are two names for the same stat; count it once.
local SAME_AS = { ITEM_MOD_SPELL_POWER = "ITEM_MOD_SPELL_POWER_SHORT" }

-- Every unknown stat key seen this session (for /ga probe).
Stats.unknownSeen = {}

local cache = {}

local function escapePattern(s)
	return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

local function number(s)
	if not s then return nil end
	return tonumber((s:gsub(",", ".")))
end

-- The item's tooltip as a list of { left, right } strings (secret text left out).
function Stats.tooltipLines(link)
	local out = {}
	if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return out end
	local data = ns.safe(C_TooltipInfo.GetHyperlink, link)
	if type(data) ~= "table" or type(data.lines) ~= "table" then return out end
	for _, line in ipairs(data.lines) do
		if line.leftText == nil and line.args and TooltipUtil and TooltipUtil.SurfaceArgs then
			pcall(TooltipUtil.SurfaceArgs, line)
		end
		local l, r = line.leftText, line.rightText
		if ns.isSecret(l) or type(l) ~= "string" then l = nil end
		if ns.isSecret(r) or type(r) ~= "string" then r = nil end
		out[#out + 1] = { left = l, right = r }
	end
	return out
end

-- True if "Increased <name> +N" names a weapon skill (not Defense, Fishing and so on).
local WEAPON_WORDS = { "axe", "sword", "mace", "dagger", "bow", "gun", "crossbow", "polearm", "staves", "staff", "fist", "thrown", "unarmed", "weapon" }
function Stats.isWeaponSkillName(name)
	if type(name) ~= "string" then return false end
	name = name:lower()
	for _, w in ipairs(WEAPON_WORDS) do
		if name:find(w, 1, true) then return true end
	end
	return false
end

-- Reads extras from tooltip text into info: speed, DPS fallback, and "Equip:" lines that
-- GetItemStats may not list (old-style "+1% hit", expertise, weapon skill).
local function readTooltip(info, lines)
	local s = info.stats
	local speedLabel = escapePattern(type(SPEED) == "string" and SPEED or "Speed")
	local equipPrefix = type(ITEM_SPELL_TRIGGER_ONEQUIP) == "string" and ITEM_SPELL_TRIGGER_ONEQUIP or "Equip:"
	local hadExpertise, hadSkill = s.ExpertiseRating ~= nil, s.WeaponSkill ~= nil
	for _, line in ipairs(lines) do
		local l, r = line.left, line.right
		if r and not info.speed then
			local v = number(r:match("^%s*" .. speedLabel .. "%s+([%d%.,]+)%s*$"))
			if v and v > 0 and v < 10 then info.speed = v end
		end
		if l then
			if not s.DPS then
				local v = number(l:match("%(([%d%.,]+) damage per second%)"))
				if v then s.DPS = v end
			end
			if l:sub(1, #equipPrefix) == equipPrefix then
				local text = l:sub(#equipPrefix + 1)
				info.equipLines = info.equipLines or {}
				info.equipLines[#info.equipLines + 1] = text
				local hit = tonumber(text:match("Improves your chance to hit by (%d+)%%"))
				if hit then s.HitPercent = (s.HitPercent or 0) + hit end
				local crit = tonumber(text:match("Improves your chance to get a critical strike by (%d+)%%"))
				if crit then s.CritPercent = (s.CritPercent or 0) + crit end
				if not hadExpertise then
					local e = tonumber(text:match("[Ee]xpertise.-(%d+)"))
					if e then s.ExpertiseRating = (s.ExpertiseRating or 0) + e end
				end
				if not hadSkill then
					local kind, amount = text:match("Increased%s+(.-)%s+%+(%d+)")
					if amount and Stats.isWeaponSkillName(kind) then
						s.WeaponSkill = (s.WeaponSkill or 0) + tonumber(amount)
						info.weaponSkillType = kind
					end
				end
			end
		end
	end
end

-- Reads an item. Returns info, or nil plus "loading" (ask again shortly) or "not an item".
-- info = { link, itemID, name, quality, itemLevel, reqLevel, equipLoc, classID, subclassID,
--          stats = { name -> amount }, unknown = { game keys we don't know }, speed, equipLines }
function Stats.read(link)
	if type(link) ~= "string" or ns.isSecret(link) then return nil, "not an item" end
	local cached = cache[link]
	if cached then return cached end

	local itemID = ns.safe(GetItemInfoInstantFn, link)
	if not itemID then return nil, "not an item" end
	local name, _, quality, itemLevel, reqLevel, _, _, _, equipLoc, _, _, classID, subclassID = ns.safe(GetItemInfoFn, link)
	if not name then
		if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
		return nil, "loading"
	end

	local info = {
		link = link, itemID = itemID, name = name, quality = quality, itemLevel = itemLevel,
		reqLevel = reqLevel or 0, equipLoc = equipLoc, classID = classID, subclassID = subclassID,
		stats = {}, unknown = {},
	}
	local raw = ns.safe(GetItemStatsFn, link)
	if type(raw) == "table" then
		for key, amount in pairs(raw) do
			if not ns.isSecret(key) and not ns.isSecret(amount) then
				local mapped = Stats.KEY_MAP[key]
				local twin = SAME_AS[key]
				if twin and raw[twin] ~= nil then
					-- counted under its other name
				elseif mapped and type(amount) == "number" then
					info.stats[mapped] = (info.stats[mapped] or 0) + amount
				else
					info.unknown[#info.unknown + 1] = tostring(key)
					Stats.unknownSeen[tostring(key)] = (Stats.unknownSeen[tostring(key)] or 0) + 1
				end
			end
		end
	end
	table.sort(info.unknown)
	readTooltip(info, Stats.tooltipLines(link))
	cache[link] = info
	return info
end

-- Equip locations that count as gear we score.
Stats.GEAR_LOCS = {
	INVTYPE_HEAD = true, INVTYPE_NECK = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true,
	INVTYPE_ROBE = true, INVTYPE_WAIST = true, INVTYPE_LEGS = true, INVTYPE_FEET = true,
	INVTYPE_WRIST = true, INVTYPE_HAND = true, INVTYPE_FINGER = true, INVTYPE_TRINKET = true,
	INVTYPE_CLOAK = true, INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true,
	INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_RANGED = true,
	INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true,
}

-- Cheap check (no item data needed): is this link a piece of gear we'd score?
function Stats.isGear(link)
	if type(link) ~= "string" or ns.isSecret(link) then return false end
	local _, _, _, equipLoc = ns.safe(GetItemInfoInstantFn, link)
	return Stats.GEAR_LOCS[equipLoc] == true
end
