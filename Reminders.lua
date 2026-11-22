-- Zyde_Forever: more reminder icons in the column beside your character
-- (all under the "Reminder icons" toggle).
--   Warrior: Execute ready, Revenge ready, Victory Rush ready, Thunder Clap
--            missing on your target, wrong stance (out of combat),
--            Sunder Armor stacks while tanking, target too far for melee.
--   Hunter:  Cheetah / Pack on in combat (flashing), Hunter's Mark missing on
--            an elite / rare / player target (solo only), target too far or
--            too close to shoot, Mongoose Bite ready, Mend Pet when your pet is low.
--   Shaman:  weapon imbue missing or running out, Lightning Shield missing or
--            on its last charge, Earth Shock to interrupt a cast, a totem out
--            of range (its buff gone), no Ankh for Reincarnation.
--   Rogue:   Eviscerate when your combo points will (nearly) kill, or you're at max.
--   Paladin: Seal of Righteousness missing or running out, no aura, no blessing on you, Judgement ready.
--   Everyone: gear badly damaged, running low on food (and water for hunters).
-- Battle Shout running out (under 10 seconds) blinks in Zyde_Forever.lua.

local ADDON, ns = ...

local safe, isSecret, knownRank = ns.safe, ns.isSecret, ns.knownRank
local _, playerClass = UnitClass("player")
local WARRIOR, HUNTER, SHAMAN = playerClass == "WARRIOR", playerClass == "HUNTER", playerClass == "SHAMAN"
local GCD = 1.5

local function plain(v) if isSecret(v) then return nil end return v end
local function on() return ns.F("reminders") end
local function inCombat() return UnitAffectingCombat("player") end
local function hostileTarget()
	return UnitExists("target") and plain(UnitCanAttack("player", "target")) and not plain(UnitIsDeadOrGhost("target"))
end
local function icon(ids, fallback)
	return ns.spellTexture(ids[1], "Interface\\Icons\\" .. fallback)
end
local function blink(frame, fast)
	frame:SetAlpha(0.35 + 0.65 * math.abs(math.sin(GetTime() * (fast and 7 or 4))))
end

-- A spell you know that the game says you can use now, and whose own
-- cooldown isn't running (the global cooldown doesn't count).
local function ready(ids)
	local id = knownRank(ids)
	if not id then return false end
	local usable
	if C_Spell and C_Spell.IsSpellUsable then usable = safe(C_Spell.IsSpellUsable, id)
	elseif IsUsableSpell then usable = safe(IsUsableSpell, id) end
	if not plain(usable) then return false end
	local start, duration
	if C_Spell and C_Spell.GetSpellCooldown then
		local cd = safe(C_Spell.GetSpellCooldown, id)
		if type(cd) == "table" then start, duration = cd.startTime, cd.duration end
	elseif GetSpellCooldown then
		start, duration = safe(GetSpellCooldown, id)
	end
	start, duration = plain(start), plain(duration)
	if start and duration and duration > GCD and start + duration - GetTime() > 0 then return false end
	return true
end

-- The spells' names, for matching auras by name: on Forever a debuff can carry
-- a different spell ID than the spell that put it there (Sunder Armor's debuff
-- is 58567 whatever rank you cast). Looked up on first use, kept per ID set.
local namesOf = setmetatable({}, { __mode = "k" })
local function spellNames(idSet)
	local names = namesOf[idSet]
	if names then return names end
	names = {}
	for id in pairs(idSet) do
		local n = (C_Spell and C_Spell.GetSpellName and safe(C_Spell.GetSpellName, id))
			or (GetSpellInfo and safe(GetSpellInfo, id))
		n = plain(n)
		if type(n) == "string" and n ~= "" then names[n] = true end
	end
	if next(names) then namesOf[idSet] = names end -- (spell data can be late: try again next time)
	return names
end

-- Your auras / debuffs on a unit, by spell ID set (or those spells' names).
-- Returns found, unknown (unknown = the game hid the details, so we can't tell).
local function hasAura(unit, filter, idSet)
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return false, true end
	local names = spellNames(idSet)
	-- Your own buffs: the list every tile shares (Zyde_Forever.lua).
	if unit == "player" and filter == "HELPFUL" and ns.PlayerBuffs then
		local buffs = ns.PlayerBuffs()
		if not buffs then return false, true end
		for _, a in ipairs(buffs.list) do
			if (a.spellId and idSet[a.spellId]) or (a.name and names[a.name]) then return true, false, a end
		end
		return false, buffs.hidden
	end
	local hidden = false
	for i = 1, 40 do
		local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
		-- In combat Forever refuses to show addons your target's auras at all
		-- ("Auras cannot be accessed when secret"): that's "can't tell", not "none".
		if not ok then return false, true end
		if not a then break end
		local id, name = plain(a.spellId), plain(a.name)
		if (id and idSet[id]) or (name and names[name]) then return true, false, a end
		if id == nil and name == nil then hidden = true end
	end
	return false, hidden
end

local function set(ids) local s = {} for _, id in ipairs(ids) do s[id] = true end return s end

-- Spell `id` can reach your target: true / false, or nil when the game won't say.
local function inRange(id)
	local r
	if C_Spell and C_Spell.IsSpellInRange then r = safe(C_Spell.IsSpellInRange, id, "target")
	elseif IsSpellInRange then
		local name = GetSpellInfo and GetSpellInfo(id)
		r = name and safe(IsSpellInRange, name, "target")
	end
	r = plain(r)
	if r == nil then return nil end
	return r == true or r == 1
end

local function inDungeon()
	local _, kind = IsInInstance()
	return kind == "party" or kind == "raid"
end

---------------------------------------------------------------------------
-- Warrior
---------------------------------------------------------------------------
local EXECUTE = { 5308, 20658, 20660, 20661, 20662 }
local REVENGE = { 6572, 6574, 7379, 11600, 11601, 25288 }
local SUNDER  = { 7386, 7405, 8380, 11596, 11597 }
local SUNDER_SET = set(SUNDER)
SUNDER_SET[58567] = true -- (the Sunder Armor debuff itself on newer clients)
local BATTLE_STANCE, DEFENSIVE_STANCE = 2457, 71
local BATTLE_STANCE_IDS, DEFENSIVE_STANCE_IDS = { BATTLE_STANCE }, { DEFENSIVE_STANCE } -- (knownRank caches by table)
local VICTORY_RUSH = { 34428 }
local THUNDER_CLAP = { 6343, 8198, 8204, 8205, 11580, 11581, 25264 }
local THUNDER_SET = set(THUNDER_CLAP)
local REND = { 772, 6546, 6547, 6548, 11572, 11573, 11574, 25208 } -- (an instant melee attack: its range is melee reach)

if WARRIOR then
	ns.AddReminder("execute", "ZydeForeverExecute", icon(EXECUTE, "INV_Sword_48"), function(preview)
		if preview then return true end
		return on() and inCombat() and hostileTarget() and ready(EXECUTE)
	end)

	ns.AddReminder("revenge", "ZydeForeverRevenge", icon(REVENGE, "Ability_Warrior_Revenge"), function(preview)
		if preview then return true end
		return on() and inCombat() and hostileTarget() and ready(REVENGE)
	end)

	-- 1 Battle, 2 Defensive, 3 Berserker (the stance bar's order).
	local function stance()
		local f = plain(GetShapeshiftForm and GetShapeshiftForm())
		return f
	end
	local function hasShield()
		return IsEquippedItemType and IsEquippedItemType("Shields") or false
	end

	-- Out of combat only: Defensive while questing alone, or Battle while
	-- you're the shield-wearer in a dungeon group.
	local stanceTile
	stanceTile = ns.AddReminder("stance", "ZydeForeverStance", "Interface\\Icons\\Ability_Warrior_OffensiveStance", function(preview)
		if preview then return true, "Battle Stance?" end
		if not on() or InCombatLockdown() or UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then return false end
		local s = stance()
		if s == 2 and not IsInGroup() and not inDungeon() and knownRank(BATTLE_STANCE_IDS) then
			stanceTile.tex:SetTexture(ns.spellTexture(BATTLE_STANCE, "Interface\\Icons\\Ability_Warrior_OffensiveStance"))
			return true, "Battle Stance?"
		end
		if s == 1 and inDungeon() and IsInGroup() and hasShield() and knownRank(DEFENSIVE_STANCE_IDS) then
			stanceTile.tex:SetTexture(ns.spellTexture(DEFENSIVE_STANCE, "Interface\\Icons\\Ability_Warrior_DefensiveStance"))
			return true, "Defensive Stance?"
		end
		return false
	end)

	-- Tanking (Defensive Stance, in a group): your target has fewer than 5 Sunders.
	ns.AddReminder("sunder", "ZydeForeverSunder", icon(SUNDER, "Ability_Warrior_Sunder"), function(preview)
		if preview then return true, "Sunder 2/5" end
		if not on() or not inCombat() or not hostileTarget() or not IsInGroup() or stance() ~= 2 then return false end
		if not knownRank(SUNDER) then return false end
		local found, hidden, a = hasAura("target", "HARMFUL", SUNDER_SET)
		if hidden and not found then return false end -- can't tell: stay quiet
		-- (one Sunder can read as 0 applications: stacks only count from 2)
		local stacks = found and math.max(1, plain(a.applications) or 1) or 0
		if stacks >= 5 then return false end
		return true, ("Sunder %d/5"):format(stacks)
	end)

	-- Too far: in a fight, your target is out of melee reach. Asked of instant
	-- melee abilities (Rend, Hamstring, Sunder Armor): their range is your real
	-- reach. Not Heroic Strike: a "next swing" ability, which can say "in range"
	-- from anywhere. If none will say, the game's ~10 yd distance check.
	local HAMSTRING = { 1715, 7372, 7373, 25212 }
	local REACH = { REND, HAMSTRING, SUNDER }
	local function inReach()
		for _, ids in ipairs(REACH) do
			local id = knownRank(ids)
			local r = id and inRange(id)
			if r ~= nil then return r end
		end
		local near = CheckInteractDistance and plain(safe(CheckInteractDistance, "target", 3))
		if near ~= nil then return near == true end
		return nil
	end
	-- /zyde rangedebug for warriors: what each check says right now.
	ns.RangeDebug = function()
		local p = "|cff66ccffZyde_Forever|r range: "
		print(p .. "target " .. tostring(plain(UnitName("target"))) .. ", " .. (InCombatLockdown() and "IN COMBAT" or "out of combat"))
		for _, s in ipairs({ { "Rend", REND }, { "Hamstring", HAMSTRING }, { "Sunder Armor", SUNDER } }) do
			local id = knownRank(s[2])
			print(p .. s[1] .. (id and (" (" .. id .. ") in range " .. tostring(inRange(id))) or " not known"))
		end
		local raw = CheckInteractDistance and safe(CheckInteractDistance, "target", 3)
		print(p .. "~10 yd distance check: " .. (isSecret(raw) and "hidden" or tostring(raw)))
		print(p .. "in reach verdict " .. tostring(inReach()))
	end
	local meleeTile = ns.AddReminder("meleeRange", "ZydeForeverMeleeRange", "Interface\\Icons\\Ability_Warrior_Charge", function(preview)
		if preview then return true, "|cffff4444TOO FAR|r" end
		if not on() or not inCombat() or not hostileTarget() or UnitOnTaxi("player") then return false end
		if inReach() ~= false then return false end -- (in reach, or can't tell: quiet)
		return true, "|cffff4444TOO FAR|r"
	end)
	meleeTile.prominent = true

	-- Victory Rush: usable for a short while after a kill that gives XP.
	ns.AddReminder("victoryRush", "ZydeForeverVictoryRush", icon(VICTORY_RUSH, "Ability_Warrior_Devastate"), function(preview)
		if preview then return true end
		if not on() or UnitIsDeadOrGhost("player") then return false end
		return ready(VICTORY_RUSH)
	end)

	-- Thunder Clap's slow lasts 30 seconds. In a fight the game often hides the
	-- debuff, so a cast you just made keeps the icon down until that time is up.
	local thunderExpires, THUNDER_TIME = 0, 30
	local thunderEv = CreateFrame("Frame")
	thunderEv:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	thunderEv:SetScript("OnEvent", function(_, _, _, _, spellID)
		spellID = plain(spellID)
		if spellID and THUNDER_SET[spellID] then thunderExpires = GetTime() + THUNDER_TIME end
	end)
	-- Missing on a target you're in melee with (from anyone: it's the same slow),
	-- when you could cast it now.
	local thunderTile = ns.AddReminder("thunderClap", "ZydeForeverThunderClap", icon(THUNDER_CLAP, "Spell_Nature_ThunderClap"), function(preview)
		if preview then return true, "Thunder" end
		if not on() or not inCombat() or not hostileTarget() or not ready(THUNDER_CLAP) then return false end
		local rend = knownRank(REND)
		if rend and inRange(rend) == false then return false end -- (out of reach: it wouldn't land)
		local found, hidden, a = hasAura("target", "HARMFUL", THUNDER_SET)
		if found then
			local dur, exp = a and plain(a.duration), a and plain(a.expirationTime)
			if dur and dur > 0 then THUNDER_TIME = dur end
			if exp and exp > 0 then thunderExpires = exp end
			return false
		end
		if hidden and GetTime() < thunderExpires then return false end
		return true, "Thunder"
	end)
	thunderTile.prominent = true
end

---------------------------------------------------------------------------
-- Hunter
---------------------------------------------------------------------------
local CHEETAH, PACK = 5118, 13159
local AUTO_SHOT = 75
local RAPTOR = { 2973, 14260, 14261, 14262, 14263, 14264, 14265, 14266 }
local WING_CLIP = { 2974, 14267, 14268 }
local MARK = { 1130, 14323, 14324, 14325 }
local MARK_SET = set(MARK)
local MONGOOSE = { 1495, 14269, 14270, 14271 }
local MEND_PET = { 136, 3111, 3661, 3662, 13542, 13543, 13544 }
local MEND_SET = set(MEND_PET)

if HUNTER then
	-- The last aspect you cast, for when the game hides your buffs in combat.
	local lastAspect
	local ASPECT_SET = set({ 13165, 14318, 14319, 14320, 14321, 14322, 25296, 13163, CHEETAH, PACK, 13161, 20043, 20190 })
	local ev = CreateFrame("Frame")
	ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	ev:SetScript("OnEvent", function(_, _, _, _, spellID)
		spellID = plain(spellID)
		if spellID and ASPECT_SET[spellID] then lastAspect = spellID end
	end)

	local FAST_SET = set({ CHEETAH, PACK })
	local cheetahTile
	cheetahTile = ns.AddReminder("cheetah", "ZydeForeverCheetah", ns.spellTexture(CHEETAH, "Interface\\Icons\\Ability_Mount_JungleTiger"), function(preview)
		if preview then return true, "Cheetah on!" end
		if not on() or not inCombat() then return false end
		local found, hidden, a = hasAura("player", "HELPFUL", FAST_SET)
		local which = found and plain(a.spellId)
		if not found and hidden then which = (lastAspect == CHEETAH or lastAspect == PACK) and lastAspect or nil end
		if not which then return false end
		cheetahTile.tex:SetTexture(ns.spellTexture(which, cheetahTile.fallback))
		blink(cheetahTile, true)
		return true, (which == PACK and "Pack on!" or "Cheetah on!")
	end)

	-- Hunter's Mark missing, solo only (in a group someone else may mark, or it
	-- isn't worth it): elites, rares, bosses and players.
	local function worthMarking()
		local c = plain(UnitClassification("target"))
		return plain(UnitIsPlayer("target")) or (c and c ~= "normal" and c ~= "trivial" and c ~= "minus")
	end
	ns.AddReminder("huntersMark", "ZydeForeverHuntersMark", icon(MARK, "Ability_Hunter_SniperShot"), function(preview)
		if preview then return true end
		if not on() or IsInGroup() or not inCombat() or not hostileTarget() or not knownRank(MARK) or not worthMarking() then return false end
		local found, hidden = hasAura("target", "HARMFUL", MARK_SET)
		return not found and not hidden
	end)

	-- Your target can't be shot from here: too far for Auto Shot, or so close
	-- you're in melee (the dead zone, where Auto Shot won't fire). Auto Shot's
	-- own range check, so range talents count; Wing Clip's for melee.
	local rangeTile
	-- In melee reach: the game's ~10 yd distance check, which Forever answers in
	-- combat too (seen 2026-11-11: false at range, true in melee). Only if it
	-- won't say, Wing Clip's range. Never Raptor Strike's: a "next swing"
	-- ability, it reports in range from any distance on Forever.
	local function meleeRange()
		local near = CheckInteractDistance and plain(safe(CheckInteractDistance, "target", 3))
		if near ~= nil then return near == true end
		local id = knownRank(WING_CLIP)
		return id ~= nil and inRange(id) == true
	end
	ns.RangeDebug = function()
		local p = "|cff66ccffZyde_Forever|r range: "
		print(p .. "target " .. tostring(UnitName("target")) .. ", hostile " .. tostring(hostileTarget() and true or false))
		print(p .. (InCombatLockdown() and "IN COMBAT" or "out of combat") .. ", Auto Shot in range " .. tostring(inRange(AUTO_SHOT)))
		for _, s in ipairs({ { "Wing Clip", WING_CLIP }, { "Raptor Strike", RAPTOR }, { "Mongoose Bite", MONGOOSE } }) do
			local id = knownRank(s[2])
			print(p .. s[1] .. (id and (" (" .. id .. ") in range " .. tostring(inRange(id))) or " not known"))
		end
		-- The game's distance checks (1 = ~28 yd inspect, 2 = ~11 yd trade, 3 = ~10 yd duel, 4 = ~28 yd follow).
		for i = 1, 4 do
			local raw = CheckInteractDistance and safe(CheckInteractDistance, "target", i)
			print(p .. "distance check " .. i .. ": " .. (isSecret(raw) and "hidden" or tostring(raw)))
		end
		print(p .. "melee verdict " .. tostring(meleeRange()))
	end

	rangeTile = ns.AddReminder("shotRange", "ZydeForeverShotRange", ns.spellTexture(AUTO_SHOT, "Interface\\Icons\\Ability_Whirlwind"), function(preview)
		if preview then return true, "Too far" end
		if not on() or not hostileTarget() or UnitOnTaxi("player") then return false end
		local shot = inRange(AUTO_SHOT)
		if shot == nil or shot then return false end -- (no ranged weapon, or can't tell: quiet)
		if meleeRange() then
			rangeTile.tex:SetTexture(ns.spellTexture(WING_CLIP[1], "Interface\\Icons\\Ability_Rogue_Trip"))
			return true, "|cffff9933Too close|r"
		end
		rangeTile.tex:SetTexture(ns.spellTexture(AUTO_SHOT, rangeTile.fallback))
		return true, "|cffff4444Too far|r"
	end)

	ns.AddReminder("mongoose", "ZydeForeverMongoose", icon(MONGOOSE, "Ability_Hunter_SwiftStrike"), function(preview)
		if preview then return true end
		return on() and inCombat() and hostileTarget() and ready(MONGOOSE)
	end)

	ns.AddReminder("mendPet", "ZydeForeverMendPet", icon(MEND_PET, "Ability_Hunter_MendPet"), function(preview)
		if preview then return true end
		if not on() or not inCombat() or not UnitExists("pet") or plain(UnitIsDead("pet")) ~= false then return false end
		if not knownRank(MEND_PET) then return false end
		local hp, max = plain(UnitHealth("pet")), plain(UnitHealthMax("pet"))
		if not (hp and max and max > 0) or hp / max >= 0.35 then return false end
		local mending = hasAura("pet", "HELPFUL", MEND_SET)
		return not mending
	end)
end

---------------------------------------------------------------------------
-- Shaman
---------------------------------------------------------------------------
local IMBUES = {
	rockbiter = { 8017, 8018, 8019, 10399, 16314, 16315, 16316 },
	flametongue = { 8024, 8027, 8030, 16339, 16341, 16342 },
	frostbrand = { 8033, 8038, 10456, 16355, 16356 },
	windfury = { 8232, 8235, 10486, 16362 },
}
local LIGHTNING_SHIELD = { 324, 325, 905, 945, 8134, 10431, 10432 }
local SHIELD_SET = set(LIGHTNING_SHIELD)
local EARTH_SHOCK = { 8042, 8044, 8045, 8046, 10412, 10413, 10414 }
local REINCARNATION_IDS, ANKH = { 20608 }, 17030
local IMBUE_WARN = 60 -- seconds left on an imbue before the tile shows

-- Totems whose buff you get while you're near them (name without " Totem" and rank).
local TOTEM_BUFFS = {
	["Strength of Earth"] = true, ["Stoneskin"] = true, ["Grace of Air"] = true, ["Mana Spring"] = true,
	["Healing Stream"] = true, ["Fire Resistance"] = true, ["Frost Resistance"] = true,
	["Nature Resistance"] = true, ["Tranquil Air"] = true, ["Windwall"] = true,
}
local TOTEM_GRACE = 3 -- seconds after dropping a totem before its buff is expected

if SHAMAN then
	-- The imbue you used last (its icon on the tile), else the best one you know.
	local lastImbue
	local IMBUE_SET = {}
	for _, ids in pairs(IMBUES) do for _, id in ipairs(ids) do IMBUE_SET[id] = true end end
	local ev = CreateFrame("Frame")
	ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	ev:SetScript("OnEvent", function(_, _, _, _, spellID)
		spellID = plain(spellID)
		if spellID and IMBUE_SET[spellID] then lastImbue = spellID end
	end)
	local function imbueToShow()
		if lastImbue then return lastImbue end
		for _, key in ipairs({ "windfury", "flametongue", "frostbrand", "rockbiter" }) do
			local id = knownRank(IMBUES[key])
			if id then return id end
		end
	end

	-- 1. Weapon imbue missing, or under a minute left.
	local imbueTile
	imbueTile = ns.AddReminder("imbue", "ZydeForeverImbue", icon(IMBUES.rockbiter, "Spell_Nature_RockBiter"), function(preview)
		if preview then return true, "Imbue weapon" end
		if not on() or UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then return false end
		local spell = imbueToShow()
		if not spell or not GetInventoryItemID("player", 16) or not GetWeaponEnchantInfo then return false end
		local has, msLeft = GetWeaponEnchantInfo()
		has, msLeft = plain(has), plain(msLeft)
		if has == nil then return false end -- (hidden: stay quiet)
		imbueTile.tex:SetTexture(ns.spellTexture(spell, imbueTile.fallback))
		if not has then return true, "Imbue weapon" end
		local secs = msLeft and msLeft / 1000
		if secs and secs < IMBUE_WARN then return true, ("Imbue %ds"):format(math.floor(secs)) end
		return false
	end)

	-- 2. Lightning Shield missing or down to its last charge: in combat, or
	-- out of combat with an enemy targeted (about to pull).
	ns.AddReminder("lightningShield", "ZydeForeverLightningShield", icon(LIGHTNING_SHIELD, "Spell_Nature_LightningShield"), function(preview)
		if preview then return true, "Shield 1" end
		if not on() or not knownRank(LIGHTNING_SHIELD) or UnitIsDeadOrGhost("player") then return false end
		if not (inCombat() or hostileTarget()) then return false end
		local found, hidden, a = hasAura("player", "HELPFUL", SHIELD_SET)
		if not found then
			if hidden then return false end
			return true, "Lightning Shield"
		end
		local charges = plain(a.applications)
		if charges and charges == 1 then return true, "Shield 1" end
		return false
	end)

	-- 3. Your target is casting something you can stop, and Earth Shock is ready.
	local shockTile
	shockTile = ns.AddReminder("earthShock", "ZydeForeverEarthShock", icon(EARTH_SHOCK, "Spell_Nature_EarthShock"), function(preview)
		if preview then return true, "Interrupt!" end
		if not on() or not hostileTarget() then return false end
		local casting, _, _, _, _, _, _, castLocked = UnitCastingInfo("target")
		local channel, _, _, _, _, _, chanLocked = UnitChannelInfo("target")
		local spell = plain(casting) or plain(channel)
		if not spell then return false end
		if plain(casting) and plain(castLocked) == true then return false end
		if not plain(casting) and plain(chanLocked) == true then return false end
		if not ready(EARTH_SHOCK) then return false end
		local id = knownRank(EARTH_SHOCK)
		if id and inRange(id) == false then return false end
		blink(shockTile, true)
		return true, "Interrupt!"
	end)

	-- 4. A totem is down but you don't have its buff: you've walked out of its range.
	local dropped = {} -- slot -> when that totem went down
	local totemTile
	totemTile = ns.AddReminder("totemRange", "ZydeForeverTotemRange", "Interface\\Icons\\Spell_Nature_EarthBindTotem", function(preview)
		if preview then return true, "Totem out of range" end
		if not on() or not GetTotemInfo or UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then return false end
		-- your buffs by name (nil: the game hid them, so we can't tell)
		local buffs = ns.PlayerBuffs()
		if not buffs then return false end
		local names, hidden = {}, buffs.hidden
		for _, aura in ipairs(buffs.list) do
			if aura.name then names[aura.name] = true else hidden = true end
		end
		local now = GetTime()
		for slot = 1, 4 do
			local have, name, start, duration, tex = GetTotemInfo(slot)
			have, name, start, duration = plain(have), plain(name), plain(start), plain(duration)
			if have and type(name) == "string" and name ~= "" and start and duration then
				local buff = name:gsub("%s+Totem.*$", "")
				if TOTEM_BUFFS[buff] and start + duration > now and now - start > TOTEM_GRACE
					and not names[buff] and not hidden then
					totemTile.tex:SetTexture(plain(tex) or totemTile.fallback)
					return true, buff .. " out of range"
				end
			end
		end
		return false
	end)

	-- 6. You can Reincarnate but carry no Ankh.
	ns.AddReminder("ankh", "ZydeForeverAnkh", "Interface\\Icons\\INV_Jewelry_Talisman_06", function(preview)
		if preview then return true, "No Ankh" end
		if not on() or InCombatLockdown() or UnitIsDeadOrGhost("player") or not knownRank(REINCARNATION_IDS) then return false end
		local count = (C_Item and C_Item.GetItemCount and safe(C_Item.GetItemCount, ANKH)) or (GetItemCount and safe(GetItemCount, ANKH))
		count = plain(count)
		return count ~= nil and count == 0, "No Ankh"
	end)
end

---------------------------------------------------------------------------
-- Rogue: Eviscerate when it's worth it
--   * "Kill": your combo points now will kill your target, or leave so little
--     that a couple of seconds of white swings finish it (your combo points die with the
--   * "Max": you're at the most combo points you can hold and they won't kill
--     it (more points would only be wasted)
--     mob, and energy refills while you loot: ending the fight sooner wins)
-- Damage: Eviscerate's own tooltip (your rank's range per point), the low end,
-- less the target's armor (estimated from its level). (Forever blocks addons from
-- the combat log, so it can't learn from your real hits.)
---------------------------------------------------------------------------
if playerClass == "ROGUE" then
	local EVISCERATE = { 2098, 6760, 6761, 6762, 8623, 8624, 11299, 11300, 31016 }
	local CP = Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4
	-- If the tooltip can't be read: Classic ranks, damage = a + b * (points - 1) .. that + spread.
	local RANKS = {
		[2098] = { 6, 6, 4 }, [6760] = { 14, 11, 8 }, [6761] = { 25, 18, 12 }, [6762] = { 41, 31, 20 },
		[8623] = { 60, 44, 28 }, [8624] = { 93, 69, 44 }, [11299] = { 144, 108, 68 },
		[11300] = { 199, 147, 96 }, [31016] = { 224, 170, 108 },
	}

	-- { [points] = { low, high } } for a rank, from its tooltip ("3 points: 61-73 damage").
	local rangeCache = {}
	local function ranges(id)
		local r = rangeCache[id]
		if r then return r end
		r = {}
		local desc = (C_Spell and C_Spell.GetSpellDescription and safe(C_Spell.GetSpellDescription, id))
			or (GetSpellDescription and safe(GetSpellDescription, id))
		desc = plain(desc)
		if type(desc) == "string" then
			for n, lo, hi in desc:gmatch("(%d+)%s*points?%s*:%s*(%d+)%s*%-%s*(%d+)") do
				r[tonumber(n)] = { tonumber(lo), tonumber(hi) }
			end
		end
		if not r[1] and RANKS[id] then
			local a, b, s = RANKS[id][1], RANKS[id][2], RANKS[id][3]
			for n = 1, 5 do r[n] = { a + b * (n - 1), a + b * (n - 1) + s } end
		end
		if r[1] then rangeCache[id] = r end -- (spell data can be late: read again next time)
		return r
	end

	local function points()
		local n = plain(UnitPower("player", CP))
		if n == nil and GetComboPoints then n = plain(GetComboPoints("player", "target")) end
		return n or 0
	end
	local function maxPoints()
		local n = plain(UnitPowerMax("player", CP))
		return (type(n) == "number" and n > 0) and n or 5
	end

	-- Share of physical damage left after the target's armor. Addons can't read a mob's
	-- armor: estimated from its level (about Classic's mob armor), then the usual formula.
	local function armorLeft(unit)
		local lvl = plain(UnitLevel(unit))
		local me = plain(UnitLevel("player")) or 1
		if type(lvl) ~= "number" or lvl <= 0 then lvl = me + 3 end -- (skull level)
		if plain(UnitIsPlayer(unit)) then return 0.75 end
		local armor = 15 * lvl + 0.8 * lvl * lvl
		return 1 - armor / (armor + 400 + 85 * me)
	end

	-- Eviscerate with n points on `unit`: three quarters up its range (an unlucky roll
	-- leaves a sliver, which the white swing counted below finishes).
	local function evisLow(n, unit)
		local id = knownRank(EVISCERATE)
		local r = id and ranges(id)[n]
		if not r then return nil end
		return (r[1] + (r[2] - r[1]) * 0.75) * armorLeft(unit)
	end

	-- A weapon's damage and speed from its tooltip ("11 - 21 Damage", "Speed 1.80"):
	-- Forever hides UnitDamage / UnitAttackSpeed from addons. Read again when you change gear.
	local weapons = {}
	local function weapon(slot)
		local w = weapons[slot]
		if w ~= nil then return w end
		w = false
		local info = C_TooltipInfo and C_TooltipInfo.GetInventoryItem and safe(C_TooltipInfo.GetInventoryItem, "player", slot)
		if type(info) == "table" and type(info.lines) == "table" then
			local lo, hi, speed
			for _, line in ipairs(info.lines) do
				for _, t in ipairs({ plain(line.leftText), plain(line.rightText) }) do
					if type(t) == "string" then
						local a, b = t:match("^(%d+)%s*%-%s*(%d+)%s+[Dd]amage")
						if a and not lo then lo, hi = tonumber(a), tonumber(b) end
						local s = t:match("^[Ss]peed%s+([%d%.]+)")
						if s then speed = tonumber(s) end
					end
				end
			end
			if lo and speed and speed > 0 then w = { lo = lo, hi = hi, speed = speed } end
		end
		weapons[slot] = w
		return w
	end
	do
		local gearEv = CreateFrame("Frame")
		gearEv:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
		gearEv:SetScript("OnEvent", function() wipe(weapons) end)
	end

	-- Your attack power: the game's number if it shows it, else Classic's rogue formula
	-- (level x 2 + Strength + Agility - 20), else a guess from your level.
	local function attackPower()
		local base, pos, neg = UnitAttackPower("player")
		base, pos, neg = plain(base), plain(pos), plain(neg)
		if type(base) == "number" then return base + (pos or 0) + (neg or 0) end
		local lvl = plain(UnitLevel("player")) or 1
		local str, agi = plain(select(2, UnitStat("player", 1))), plain(select(2, UnitStat("player", 2)))
		if type(str) == "number" and type(agi) == "number" then return lvl * 2 + str + agi - 20 end
		return lvl * 4
	end

	-- After Eviscerate your energy restarts near empty and comes back at 10 a second, so
	-- until you can afford a Sinister Strike (45) only your white swings add damage: that's
	-- the time a "nearly dead" target has to be finished in. From your energy now, if the
	-- game shows it (5 seconds if not), plus a second of slack.
	local SS_COST, EVIS_COST, REGEN = 45, 35, 10
	local function swingTime()
		local e = plain(UnitPower("player", Enum and Enum.PowerType and Enum.PowerType.Energy or 3))
		if type(e) ~= "number" then return 5 end
		local after = math.max(0, e - EVIS_COST)
		return math.max(2.5, math.min(5.5, (SS_COST - after) / REGEN + 1)) -- (+1 s: a swing or two of slack)
	end

	-- What your white swings will still do: at least one main-hand swing, or swingTime()
	-- seconds of both hands (off-hand at half damage), whichever is more. Average hits.
	local function whiteLow(unit)
		local ap = attackPower()
		local mh, oh = weapon(16), weapon(17)
		if not mh then
			local lo = plain(UnitDamage and UnitDamage("player"))
			return type(lo) == "number" and lo * armorLeft(unit) or 0
		end
		local mhHit = (mh.lo + mh.hi) / 2 + ap / 14 * mh.speed
		local dps = mhHit / mh.speed
		if oh then dps = dps + ((oh.lo + oh.hi) / 2 + ap / 14 * oh.speed) * 0.5 / oh.speed end
		return math.max(mhHit, dps * swingTime()) * armorLeft(unit)
	end

	-- Forever hides your target's health from addons (in and out of combat), so the "Kill"
	-- test can't be done in Lua. The game will still fill a status bar from the hidden
	-- number, so the tile is cut out by a mask tied to an invisible bar over it: the bar runs
	-- from (kill damage - 1) to (kill damage) and is filled by the target's health. Health
	-- at or above the kill damage fills it and the mask (the unfilled part) shrinks to
	-- nothing: tile hidden. Below it the bar is empty, the mask covers the whole tile: shown.
	local evisTile, gate
	local function gateOpen() -- tile fully visible (Max, preview)
		if gate then gate:SetMinMaxValues(0, 1) gate:SetValue(0) end
	end

	local function evisCheck(preview)
		if preview then gateOpen() evisTile.tex:SetDesaturated(false) return true, "Kill" end
		if not on() or not inCombat() or not hostileTarget() then return false end
		local n = points()
		if n <= 0 or not knownRank(EVISCERATE) then return false end
		-- Shown even before you have the energy: grayed out until you can cast it.
		evisTile.tex:SetDesaturated(not ready(EVISCERATE))
		if n >= maxPoints() then gateOpen() return true, "Max" end
		local dmg = evisLow(n, "target")
		if not dmg then return false end
		local kill = dmg + whiteLow("target")
		local hp = UnitHealth("target")
		if not isSecret(hp) then
			gateOpen()
			if type(hp) == "number" and hp <= kill then return true, "|cffff5555Kill|r" end
			return false
		end
		if not gate then return false end
		gate:SetMinMaxValues(kill - 1, kill)
		if not pcall(gate.SetValue, gate, hp) then return false end
		return true, "" -- (shown only where the game says health < kill; no label: text can't be masked)
	end
	evisTile = ns.AddReminder("eviscerate", "ZydeForeverEviscerate", icon(EVISCERATE, "Ability_Rogue_Eviscerate"), evisCheck)
	evisTile.prominent = true
	do
		local ok = pcall(function()
			local g = CreateFrame("StatusBar", nil, evisTile)
			g:SetPoint("TOPLEFT", evisTile, "TOPLEFT", -2, 2)
			g:SetPoint("BOTTOMRIGHT", evisTile, "BOTTOMRIGHT", 2, -2)
			g:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
			g:SetStatusBarColor(0, 0, 0, 0) -- (never drawn: only its fill's edge is used)
			g:SetMinMaxValues(0, 1)
			g:SetValue(0)
			local m = evisTile:CreateMaskTexture()
			m:SetTexture("Interface\\Buttons\\WHITE8X8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			m:SetPoint("TOPLEFT", g:GetStatusBarTexture(), "TOPRIGHT")
			m:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT")
			evisTile.tex:AddMaskTexture(m)
			evisTile.border:AddMaskTexture(m)
			gate = g
		end)
		if not ok then gate = nil end
	end

	-- /zyde evisdebug: the numbers behind the Eviscerate tile for your target.
	ns.EvisDebug = function()
		local p = "|cff66ccffZyde_Forever|r eviscerate: "
		local id = knownRank(EVISCERATE)
		print(p .. "rank " .. tostring(id) .. ", points " .. points() .. "/" .. maxPoints()
			.. (", armor left %.0f%%"):format(armorLeft("target") * 100))
		local r = id and ranges(id) or {}
		for n = 1, maxPoints() do
			if r[n] then print(p .. ("  %d: %d-%d, counted as %.0f"):format(n, r[n][1], r[n][2], evisLow(n, "target") or 0)) end
		end
		local rawHp = UnitHealth("target")
		print(p .. ("target health %s, white damage counted %.0f (AP %.0f, %.1f s of swings)"):format(isSecret(rawHp) and "HIDDEN by the game" or tostring(rawHp), whiteLow("target"), attackPower(), swingTime()))
		-- Each gate the tile goes through, and what the tile decides right now.
		local usable
		if id and C_Spell and C_Spell.IsSpellUsable then usable = safe(C_Spell.IsSpellUsable, id)
		elseif id and IsUsableSpell then usable = safe(IsUsableSpell, id) end
		print(p .. ("reminders on %s, in combat %s, enemy target %s, usable %s, ready %s"):format(
			tostring(on()), tostring(inCombat()), tostring(hostileTarget()),
			isSecret(usable) and "hidden" or tostring(usable), tostring(ready(EVISCERATE))))
		local ok, show, label = pcall(evisCheck, false)
		print(p .. "tile: " .. (ok and (tostring(show) .. " " .. tostring(label or "")) or ("ERROR " .. tostring(show)))
			.. (gate and "" or " (no health gate: hidden health can't be checked)"))
		if ok and show and label == "" then
			print(p .. ("  shown only while the target's health is under %.0f (the game decides)"):format((evisLow(points(), "target") or 0) + whiteLow("target")))
		end
	end
end

---------------------------------------------------------------------------
-- Paladin: Seal of Righteousness missing (in a fight, or with an enemy targeted),
-- or under 3 seconds left in a fight. Quiet while any other seal is up (you chose it).
-- A seal lasts 30 seconds (on Forever, Judgement does not use it up). Forever can hide
-- your buffs in a fight, so your own casts are tracked too: a seal cast starts the 30 seconds.
---------------------------------------------------------------------------
if playerClass == "PALADIN" then
	-- (Rank 1 is 20154 on Classic clients, 21084 on some others: both listed)
	local SOR = { 20154, 21084, 20287, 20288, 20289, 20290, 20291, 20292, 20293 }
	local JUDGEMENT = 20271
	local SEAL_TIME, WARN = 30, 3
	local sealExpires, sealIsSoR = 0, false

	local function spellName(id)
		local n = (C_Spell and C_Spell.GetSpellName and safe(C_Spell.GetSpellName, id)) or (GetSpellInfo and safe(GetSpellInfo, id))
		return plain(n)
	end
	local function isSeal(name) return type(name) == "string" and name:find("^Seal of") ~= nil end
	local sorName
	local function isSoR(name)
		sorName = sorName or spellName(SOR[1])
		return type(name) == "string" and name == (sorName or "Seal of Righteousness")
	end

	local ev = CreateFrame("Frame")
	ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	ev:SetScript("OnEvent", function(_, _, _, _, spellID)
		spellID = plain(spellID)
		if not spellID then return end
		local name = spellName(spellID)
		if isSeal(name) then
			sealExpires = GetTime() + SEAL_TIME
			sealIsSoR = isSoR(name)
		end
	end)

	-- Your seal from your buffs: "sor" / "other" / nil (none), seconds left; unknown = hidden.
	local function sealBuff()
		local buffs = ns.PlayerBuffs()
		if not buffs then return nil, nil, true end
		for _, a in ipairs(buffs.list) do
			local name = a.name
			if isSeal(name) then
				local exp = a.expirationTime
				local left = (exp and exp > 0) and (exp - GetTime()) or nil
				if left then sealExpires = exp end
				return isSoR(name) and "sor" or "other", left, false
			end
		end
		return nil, nil, buffs.hidden
	end

	-- Your Seal of Righteousness: by the ID list, else by name from your spellbook
	-- (in case Forever uses IDs not in the list). Kept as a one-ID list for ready().
	local sorIds
	local function mySoR()
		if knownRank(SOR) then return SOR end
		if sorIds then return sorIds end
		local info = C_Spell and C_Spell.GetSpellInfo and safe(C_Spell.GetSpellInfo, "Seal of Righteousness")
		local id = type(info) == "table" and plain(info.spellID)
		if id then sorIds = { id } return sorIds end
		return nil
	end

	local function sealCheck(preview, why)
		why = why or function() end
		if preview then return true, "Seal" end
		if not on() or UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then return why("reminders off, dead or flying") end
		local ids = mySoR()
		if not ids then return why("Seal of Righteousness not found in your spells") end
		if not ready(ids) then return why("can't cast it right now (mana?)") end
		local fighting = inCombat()
		if not (fighting or hostileTarget()) then return why("not in a fight and no enemy targeted") end
		local kind, left, hidden = sealBuff()
		if hidden and not kind then
			-- Buffs hidden: go by your own casts.
			left = sealExpires - GetTime()
			if left > 0 then kind = sealIsSoR and "sor" or "other" else kind, left = nil, nil end
			why("your buffs are hidden: going by your casts")
		end
		if kind == "other" then return why("another seal is up") end
		if not kind then return true, "Seal" end
		if fighting and left and left < WARN then return true, "Seal" end
		return why(("Seal of Righteousness up, %s left"):format(left and ("%.0f s"):format(left) or "unknown time"))
	end
	local sealTile = ns.AddReminder("sealRighteousness", "ZydeForeverSealRighteousness", icon(SOR, "Ability_ThunderBolt"), function(preview)
		return sealCheck(preview)
	end)
	sealTile.prominent = true

	-- /zyde sealdebug: why the Seal of Righteousness tile is or isn't showing.
	ns.SealDebug = function()
		local p = "|cff66ccffZyde_Forever|r seal: "
		local ids = mySoR()
		print(p .. "spell " .. (ids and tostring(ids[1]) .. (ids == SOR and (" (rank " .. tostring(knownRank(SOR)) .. ")") or " (found by name)") or "not found"))
		local kind, left, hidden = sealBuff()
		print(p .. ("buff: %s, %s left, buffs hidden %s; last seal cast %.0f s left"):format(
			tostring(kind), left and ("%.0f s"):format(left) or "?", tostring(hidden), math.max(0, sealExpires - GetTime())))
		local ok, show, label = pcall(sealCheck, false, function(msg) print(p .. "  " .. msg) end)
		print(p .. "tile: " .. (ok and (tostring(show) .. " " .. tostring(label or "")) or ("ERROR " .. tostring(show))))
	end

	-- No aura on you (any paladin aura, yours or another paladin's). Auras last until you
	-- change them or die. When Forever hides your buffs: an aura cast since you last died counts.
	local AURAS = {
		["Devotion Aura"] = true, ["Retribution Aura"] = true, ["Concentration Aura"] = true,
		["Shadow Resistance Aura"] = true, ["Frost Resistance Aura"] = true,
		["Fire Resistance Aura"] = true, ["Sanctity Aura"] = true, ["Crusader Aura"] = true,
	}
	local DEVOTION = { 465, 10290, 643, 10291, 1032, 10292, 10293 }
	local auraCastId -- your last aura cast (its icon on the tile), nil after you die
	local auraEv = CreateFrame("Frame")
	auraEv:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	auraEv:RegisterEvent("PLAYER_DEAD")
	auraEv:SetScript("OnEvent", function(_, event, _, _, spellID)
		if event == "PLAYER_DEAD" then auraCastId = nil return end
		spellID = plain(spellID)
		if spellID and AURAS[spellName(spellID) or ""] then auraCastId = spellID end
	end)

	-- true (an aura is on you), false (none), nil (buffs hidden)
	local function hasPaladinAura()
		local buffs = ns.PlayerBuffs()
		if not buffs then return nil end
		for _, a in ipairs(buffs.list) do
			if a.name and AURAS[a.name] then
				auraCastId = a.spellId or auraCastId -- (remembered for when buffs are hidden)
				return true
			end
		end
		if buffs.hidden then return nil end
		return false
	end

	local auraTile
	auraTile = ns.AddReminder("paladinAura", "ZydeForeverPaladinAura", icon(DEVOTION, "Spell_Holy_DevotionAura"), function(preview)
		if preview then return true, "No aura" end
		if not on() or UnitIsDeadOrGhost("player") or UnitOnTaxi("player") or not knownRank(DEVOTION) then return false end
		local has = hasPaladinAura()
		if has == nil then has = auraCastId ~= nil end
		if has then return false end
		auraTile.tex:SetTexture(ns.spellTexture(auraCastId or knownRank(DEVOTION), auraTile.fallback))
		return true, "No aura"
	end)

	-- No blessing on you (Might, Wisdom, Kings, Salvation, Light, Sanctuary, or a Greater
	-- one; from you or another paladin). Not the short ones (Protection, Freedom,
	-- Sacrifice). When Forever hides your buffs: a blessing you cast on yourself counts for
	-- its 5 minutes (15 for a Greater one), until you die.
	local MIGHT = { 19740, 19834, 19835, 19836, 19837, 19838, 25291 }
	local LONG = { Might = true, Wisdom = true, Kings = true, Salvation = true, Light = true, Sanctuary = true }
	local function isBlessing(name)
		if type(name) ~= "string" then return false end
		local kind = name:match("^Greater Blessing of (%a+)") or name:match("^Blessing of (%a+)")
		return kind ~= nil and LONG[kind] == true, name:find("^Greater") ~= nil
	end
	local blessId, blessExpires = nil, 0
	local pendingSelf = {} -- cast GUID -> true when the cast went at you
	local blessEv = CreateFrame("Frame")
	blessEv:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
	blessEv:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	blessEv:RegisterEvent("PLAYER_DEAD")
	blessEv:SetScript("OnEvent", function(_, event, _, a2, a3, a4)
		if event == "PLAYER_DEAD" then blessExpires = 0 return end
		if event == "UNIT_SPELLCAST_SENT" then
			-- (unit, target name, cast GUID, spell ID): no target name = yourself
			local target, guid = plain(a2), plain(a3)
			if guid and (target == nil or target == "" or target == plain(UnitName("player"))) then pendingSelf[guid] = true end
			return
		end
		-- UNIT_SPELLCAST_SUCCEEDED (unit, cast GUID, spell ID)
		local guid, spellID = plain(a2), plain(a3)
		local onMe = guid and pendingSelf[guid]
		if guid then pendingSelf[guid] = nil end
		if not spellID then return end
		local ok, greater = isBlessing(spellName(spellID))
		if not ok then return end
		blessId = spellID
		-- (a Greater blessing covers your whole class, you included)
		if onMe or greater then blessExpires = GetTime() + (greater and 900 or 300) end
	end)

	-- true (a blessing is on you), false (none), nil (buffs hidden)
	local function hasBlessing()
		local buffs = ns.PlayerBuffs()
		if not buffs then return nil end
		for _, a in ipairs(buffs.list) do
			if isBlessing(a.name) then
				local exp = a.expirationTime
				if exp and exp > 0 then blessExpires = exp end
				return true
			end
		end
		if buffs.hidden then return nil end
		return false
	end

	local blessTile
	blessTile = ns.AddReminder("paladinBlessing", "ZydeForeverPaladinBlessing", icon(MIGHT, "Spell_Holy_FistOfJustice"), function(preview)
		if preview then return true, "No blessing" end
		if not on() or UnitIsDeadOrGhost("player") or UnitOnTaxi("player") or not knownRank(MIGHT) then return false end
		local has = hasBlessing()
		if has == nil then has = blessExpires > GetTime() end
		if has then return false end
		blessTile.tex:SetTexture(ns.spellTexture(blessId or knownRank(MIGHT), blessTile.fallback))
		return true, "No blessing"
	end)

	-- Judgement ready: in a fight with an enemy targeted, off cooldown, castable (the game
	-- says it isn't without a seal up or the mana), and your target within its reach.
	-- Forever can hide spell cooldowns from addons in a fight, so your own Judgement casts
	-- are tracked too: the tile stays down for the cooldown after each one (the game's base
	-- cooldown if it says, else 10 seconds).
	local JUDGEMENT_IDS = { JUDGEMENT }
	local judgedAt, judgeName = -math.huge, nil
	local function judgeCooldown()
		local ms = GetSpellBaseCooldown and plain(safe(GetSpellBaseCooldown, JUDGEMENT))
		return (type(ms) == "number" and ms > 0) and ms / 1000 or 10
	end
	local judgeEv = CreateFrame("Frame")
	judgeEv:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	judgeEv:SetScript("OnEvent", function(_, _, _, _, spellID)
		spellID = plain(spellID)
		if not spellID then return end
		judgeName = judgeName or spellName(JUDGEMENT) or "Judgement"
		if spellID == JUDGEMENT or spellName(spellID) == judgeName then judgedAt = GetTime() end
	end)
	ns.AddReminder("judgement", "ZydeForeverJudgement", icon(JUDGEMENT_IDS, "Spell_Holy_RighteousFury"), function(preview)
		if preview then return true, "Judgement" end
		if not on() or not inCombat() or not hostileTarget() then return false end
		if GetTime() - judgedAt < judgeCooldown() then return false end
		if not ready(JUDGEMENT_IDS) then return false end
		if inRange(JUDGEMENT) == false then return false end -- (out of reach; can't tell: still show)
		return true, "Judgement"
	end)
end

---------------------------------------------------------------------------
-- Both: damaged gear, low food / water (checked when bags or gear change)
---------------------------------------------------------------------------
local REPAIR_AT = 0.20
local FOOD_LOW = 5
local worstDurability, food, drink = 1, 0, 0

local function scanDurability()
	worstDurability = 1
	for slot = 1, 18 do
		local cur, max = GetInventoryItemDurability(slot)
		cur, max = plain(cur), plain(max)
		if cur and max and max > 0 then worstDurability = math.min(worstDurability, cur / max) end
	end
end

-- Food and drink: items whose "use" is a Food / Drink / Refreshment spell. Names are matched
-- loosely ("Drink", "Food & Drink", "Refreshment"...). A freshly bought item often has no spell
-- loaded yet; the game is asked to load it, and the scan runs again when it arrives.
local requested = {}
local function scanFood()
	food, drink = 0, 0
	local getSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
	local load = C_Item and C_Item.RequestLoadItemDataByID
	for _, info in ipairs(ns.Bags.items()) do
		local spell = plain(safe(getSpell, info.itemID))
		if type(spell) == "string" then
			local n = tonumber(info.stackCount) or 1
			local s = spell:lower()
			local refresh = s:find("refresh", 1, true) ~= nil
			if refresh or s:find("food", 1, true) then food = food + n end
			if refresh or s:find("drink", 1, true) then drink = drink + n end
		elseif load and info.itemID and not requested[info.itemID] then
			requested[info.itemID] = true
			safe(load, info.itemID)
		end
	end
end

local scanEv = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT" }) do
	pcall(scanEv.RegisterEvent, scanEv, e)
end
local scanPending = false
scanEv:SetScript("OnEvent", function()
	if scanPending then return end
	scanPending = true
	C_Timer.After(0.5, function()
		scanPending = false
		scanDurability()
		scanFood()
	end)
end)

local function quietTime()
	return not InCombatLockdown() and not UnitIsDeadOrGhost("player") and not UnitOnTaxi("player")
end

ns.AddReminder("repair", "ZydeForeverRepair", "Interface\\Icons\\Trade_BlackSmithing", function(preview)
	if preview then return true, "Repair 15%" end
	if not on() or not quietTime() or worstDurability >= REPAIR_AT then return false end
	return true, ("Repair %d%%"):format(math.floor(worstDurability * 100))
end)

local foodTile
foodTile = ns.AddReminder("food", "ZydeForeverFood", "Interface\\Icons\\INV_Misc_Food_14", function(preview)
	if preview then return true, "Food 3" end
	if not on() or not quietTime() or UnitLevel("player") < 5 then return false end
	local lowFood = food < FOOD_LOW
	local lowDrink = HUNTER and drink < FOOD_LOW -- warriors don't need water
	if not (lowFood or lowDrink) then return false end
	foodTile.tex:SetTexture(lowFood and "Interface\\Icons\\INV_Misc_Food_14" or "Interface\\Icons\\INV_Drink_07")
	local parts = {}
	if lowFood then parts[#parts + 1] = "Food " .. food end
	if lowDrink then parts[#parts + 1] = "Water " .. drink end
	return true, table.concat(parts, ", ")
end)

-- /zyde auradebug: what the game says about your target's debuffs (name, spell ID,
-- stacks, yours or not), to check the Sunder and Thunder Clap tiles against.
ns.AuraDebug = function()
	local P = "|cff66ccffZyde_Forever|r: "
	if not UnitExists("target") then print(P .. "target something first") return end
	local function show(v) if isSecret(v) then return "hidden" end return tostring(v) end
	print(P .. "target debuffs, " .. (InCombatLockdown() and "IN COMBAT" or "out of combat")
		.. ", unit frame icons " .. (ns.F("unitAuras") and "on" or "OFF in /zyde")
		.. ", nameplates " .. (ns.F("plates") and "on" or "off"))
	-- 1) What Zyde uses: C_UnitAuras.GetAuraDataByIndex.
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		for _, filter in ipairs({ "HARMFUL", "HARMFUL|PLAYER" }) do
			local n, first = 0, nil
			for i = 1, 40 do
				local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "target", i, filter)
				if not ok then print(P .. "  by index (" .. filter .. "): error " .. tostring(a)) break end
				if not a then break end
				n = n + 1
				if n <= 6 then
					print(("%s  %d. %s  id %s  stacks %s  yours %s  ends %s"):format(P, i, show(a.name), show(a.spellId),
						show(a.applications), show(a.isFromPlayerOrPlayerPet), show(a.expirationTime)))
				end
			end
			print(P .. "  by index (" .. filter .. "): " .. n .. " found")
		end
	else
		print(P .. "  no C_UnitAuras.GetAuraDataByIndex on this client")
	end
	-- 2) Other ways the game offers, to see which one Forever answers.
	if C_UnitAuras and C_UnitAuras.GetAuraSlots then
		local ok, r = pcall(function() return select("#", C_UnitAuras.GetAuraSlots("target", "HARMFUL")) - 1 end)
		print(P .. "  aura slots: " .. (ok and tostring(r) or ("error " .. tostring(r))))
	end
	if C_UnitAuras and C_UnitAuras.GetUnitAuras then
		local ok, list = pcall(C_UnitAuras.GetUnitAuras, "target", "HARMFUL")
		print(P .. "  GetUnitAuras: " .. (ok and (type(list) == "table" and (#list .. " found") or tostring(list)) or ("error " .. tostring(list))))
	end
	local legacy = _G.UnitDebuff or _G.UnitAura
	if legacy then
		local n = 0
		for i = 1, 40 do
			local ok, name = pcall(legacy, "target", i, _G.UnitDebuff and nil or "HARMFUL")
			if not ok or name == nil then break end
			n = n + 1
			if n <= 3 then print(P .. "  legacy " .. i .. ": " .. show(name)) end
		end
		print(P .. "  legacy UnitDebuff: " .. n .. " found")
	end
	-- 3) The game's own icons, which Zyde shows when addons can't read auras.
	local UFm = ns.UnitFrames
	if UFm and UFm.gameAuraContainer then
		local c = UFm.gameAuraContainer()
		local kids = c and select("#", c:GetChildren()) or 0
		print(P .. "  game's target aura container: " .. (c and ("found, " .. (c:IsVisible() and "visible" or "not visible") .. ", " .. kids .. " children, under " .. tostring(c:GetParent() and c:GetParent():GetName())) or "none"))
	end
	if UFm and UFm.blizzTargetButtons then
		local buffs, debuffs, total = UFm.blizzTargetButtons()
		if buffs then
			print(P .. ("  game's target frame icons: %d buffs, %d debuffs showing (%d icon frames found)"):format(#buffs, #debuffs, total or 0))
		else
			print(P .. "  game's target frame icons: none found (TargetFrame " .. (TargetFrame and "exists" or "missing") .. ")")
		end
	end
	if TargetFrame then
		-- Where does the game's target frame keep its aura icons? (Everything
		-- on it named like an aura, its aura-like children, and a few globals.)
		local ok, err = pcall(function()
			local tf = TargetFrame
			local parent = tf:GetParent()
			print(P .. ("  TargetFrame: shown %s, visible %s, parent %s, UpdateAuras %s, TargetFrame_UpdateAuras %s")
				:format(tostring(tf:IsShown()), tostring(tf:IsVisible()), tostring(parent and parent:GetName() or "unnamed"),
				type(tf.UpdateAuras), type(_G.TargetFrame_UpdateAuras)))
			local keys = {}
			for k, v in pairs(tf) do
				if type(k) == "string" and (k:lower():find("aura") or k:lower():find("buff")) then
					keys[#keys + 1] = k .. "=" .. type(v)
				end
			end
			table.sort(keys)
			print(P .. "  TargetFrame fields: " .. (#keys > 0 and table.concat(keys, ", ") or "none named like auras"))
			local kids = {}
			for _, c in ipairs({ tf:GetChildren() }) do
				local n = c:GetName() or c:GetDebugName() or "?"
				if n:lower():find("aura") or n:lower():find("buff") then kids[#kids + 1] = n end
			end
			print(P .. "  aura-like children: " .. (#kids > 0 and table.concat(kids, ", ", 1, math.min(#kids, 6)) or "none"))
			local globals = {}
			for _, g in ipairs({ "TargetFrameBuff1", "TargetFrameDebuff1", "TargetFrameAura1", "TargetFrameBuffs", "TargetFrameDebuffs" }) do
				if _G[g] then globals[#globals + 1] = g .. (_G[g]:IsShown() and " (shown)" or "") end
			end
			print(P .. "  aura globals: " .. (#globals > 0 and table.concat(globals, ", ") or "none"))
		end)
		if not ok then print(P .. "  TargetFrame check failed: " .. tostring(err)) end
	end
	-- 4) A full dump of the game's target frame for Zyde's author: saved in
	-- ZydeForeverDB.debugDump (written to disk at the next /reload).
	if TargetFrame then
		local lines = {}
		local function flags(f)
			local t = {}
			for _, k in ipairs({ "Icon", "icon", "Cooldown", "cooldown", "Count", "count", "Border", "Stealable", "auraInstanceID", "isDebuff", "unit" }) do
				local ok, v = pcall(function() return f[k] end)
				if ok and v ~= nil then t[#t + 1] = k end
			end
			return table.concat(t, " ")
		end
		local function walk(f, depth, path)
			if depth > 5 or #lines > 400 then return end
			for i, c in ipairs({ f:GetChildren() }) do
				local ok, name = pcall(c.GetName, c)
				local okT, kind = pcall(c.GetObjectType, c)
				local shown = c.IsShown and c:IsShown()
				local p = path .. "/" .. ((ok and name) or ("#" .. i))
				lines[#lines + 1] = ("%s [%s] %s %s"):format(p, okT and kind or "?", shown and "shown" or "hidden", flags(c))
				walk(c, depth + 1, p)
			end
		end
		for k, v in pairs(TargetFrame) do
			if type(k) == "string" then
				local extra = ""
				if type(v) == "table" and v.EnumerateActive then
					local n = 0
					pcall(function() for _ in v:EnumerateActive() do n = n + 1 end end)
					extra = " (pool, " .. n .. " active)"
				end
				lines[#lines + 1] = "field " .. k .. " = " .. type(v) .. extra
			end
		end
		table.sort(lines)
		walk(TargetFrame, 1, "TargetFrame")
		-- The aura container (moved under Zyde's frame), with its cooldowns' number setting.
		local c = ns.UnitFrames and ns.UnitFrames.gameAuraContainer and ns.UnitFrames.gameAuraContainer()
		if c then
			local function walkC(f, depth, path)
				if depth > 6 or #lines > 600 then return end
				for i, ch in ipairs({ f:GetChildren() }) do
					local okT, kind = pcall(ch.GetObjectType, ch)
					local extra = ""
					if okT and kind == "Cooldown" then
						local okH, hide = pcall(function() return ch.GetHideCountdownNumbers and ch:GetHideCountdownNumbers() end)
						extra = " hideNumbers=" .. (okH and (isSecret(hide) and "secret" or tostring(hide)) or "error")
					end
					local keys = {}
					for k in pairs(ch) do if type(k) == "string" and #keys < 12 then keys[#keys + 1] = k end end
					local p = path .. "/" .. (ch:GetName() or ("#" .. i))
					lines[#lines + 1] = ("%s [%s] %s%s keys: %s"):format(p, okT and kind or "?", ch:IsShown() and "shown" or "hidden", extra, table.concat(keys, " "))
					walkC(ch, depth + 1, p)
				end
			end
			local keys = {}
			for k, v in pairs(c) do if type(k) == "string" then keys[#keys + 1] = k .. (type(v) == "function" and "()" or "") end end
			table.sort(keys)
			lines[#lines + 1] = "CONTAINER type " .. tostring(select(2, pcall(c.GetObjectType, c))) .. ", fields: " .. table.concat(keys, " ")
			local mt = getmetatable(c)
			local idx = mt and type(mt.__index) == "table" and mt.__index
			if idx then
				local m = {}
				for k in pairs(idx) do
					if type(k) == "string" and (k:find("Aura") or k:find("Count") or k:find("Cooldown") or k:find("Duration") or k:find("Timer") or k:find("Text")) then m[#m + 1] = k end
				end
				table.sort(m)
				lines[#lines + 1] = "CONTAINER methods: " .. table.concat(m, " ")
			end
			lines[#lines + 1] = "CONTAINER templates: buff " .. tostring(select(2, pcall(c.GetBuffTemplate, c))) .. ", debuff " .. tostring(select(2, pcall(c.GetDebuffTemplate, c)))
			-- Its icons aren't its children: find frames anchored to it.
			local found = 0
			local f = EnumerateFrames()
			while f and found < 20 do
				local ok, _, rel = pcall(f.GetPoint, f, 1)
				if ok and rel == c then
					found = found + 1
					local keys = {}
					for k in pairs(f) do if type(k) == "string" and #keys < 15 then keys[#keys + 1] = k end end
					local cd = f.Cooldown or f.cooldown
					local hide = cd and select(2, pcall(function() return cd.GetHideCountdownNumbers and cd:GetHideCountdownNumbers() end))
					local par = f:GetParent()
					lines[#lines + 1] = ("ANCHORED %s parent %s shown %s cooldown %s hideNumbers %s keys: %s"):format(tostring(select(2, pcall(f.GetObjectType, f))),
						tostring(par and (par:GetName() or (par == c and "CONTAINER") or "unnamed")), tostring(f:IsShown()), tostring(cd ~= nil),
						isSecret(hide) and "secret" or tostring(hide), table.concat(keys, " "))
				end
				f = EnumerateFrames(f)
			end
			lines[#lines + 1] = "ANCHORED total " .. found
			local regions = {}
			for _, r in ipairs({ c:GetRegions() }) do regions[#regions + 1] = tostring(select(2, pcall(r.GetObjectType, r))) end
			lines[#lines + 1] = "CONTAINER regions: " .. table.concat(regions, " ")
			walkC(c, 1, "CONTAINER")
		end
		ZydeForeverDB = ZydeForeverDB or {}
		ZydeForeverDB.debugDump = lines
		print(P .. ("  saved a dump of the game's target frame (%d lines): /reload so Zyde's author can read it"):format(#lines))
	end
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit("target")
	if plate and ns.PlateAuraFrame then
		local c = ns.PlateAuraFrame(plate)
		local shownIcons = 0
		if c then for _, child in ipairs({ c:GetChildren() }) do if child:IsShown() then shownIcons = shownIcons + 1 end end end
		print(P .. "  game's nameplate debuff row: " .. (c and (("found (%s), %d shown parts"):format(c:GetName() or "unnamed", shownIcons)) or "none on this plate"))
	else
		print(P .. "  target has no nameplate in view")
	end
end
