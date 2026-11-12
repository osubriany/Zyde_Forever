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
	local hidden = false
	for i = 1, 40 do
		local a = safe(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
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
	ns.AddReminder("meleeRange", "ZydeForeverMeleeRange", "Interface\\Icons\\Ability_Warrior_Charge", function(preview)
		if preview then return true, "|cffff4444Too far|r" end
		if not on() or not inCombat() or not hostileTarget() or UnitOnTaxi("player") then return false end
		if inReach() ~= false then return false end -- (in reach, or can't tell: quiet)
		return true, "|cffff4444Too far|r"
	end)

	-- Victory Rush: usable for a short while after a kill that gives XP.
	ns.AddReminder("victoryRush", "ZydeForeverVictoryRush", icon(VICTORY_RUSH, "Ability_Warrior_Devastate"), function(preview)
		if preview then return true end
		if not on() or UnitIsDeadOrGhost("player") then return false end
		return ready(VICTORY_RUSH)
	end)

	-- Thunder Clap missing on a target you're in melee with (from anyone: it's the
	-- same slow), when you could cast it now.
	ns.AddReminder("thunderClap", "ZydeForeverThunderClap", icon(THUNDER_CLAP, "Spell_Nature_ThunderClap"), function(preview)
		if preview then return true end
		if not on() or not inCombat() or not hostileTarget() or not ready(THUNDER_CLAP) then return false end
		local rend = knownRank(REND)
		if rend and inRange(rend) == false then return false end -- (out of reach: it wouldn't land)
		local found, hidden = hasAura("target", "HARMFUL", THUNDER_SET)
		return not found and not hidden
	end)
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
		local names, hidden = {}, false
		if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return false end
		for i = 1, 40 do
			local aura = safe(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
			if not aura then break end
			local n = plain(aura.name)
			if n then names[n] = true else hidden = true end
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

-- Food and drink: items whose "use" is the Food / Drink / Refreshment spell.
local function scanFood()
	food, drink = 0, 0
	local getSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
	for _, info in ipairs(ns.Bags.items()) do
		local spell = plain(safe(getSpell, info.itemID))
		if type(spell) == "string" then
			local n = tonumber(info.stackCount) or 1
			if spell == "Food" or spell == "Refreshment" or spell == "Food & Drink" then food = food + n end
			if spell == "Drink" or spell == "Refreshment" or spell == "Food & Drink" then drink = drink + n end
		end
	end
end

local scanEv = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED" }) do
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
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then print(P .. "this client has no aura data") return end
	local n = 0
	for i = 1, 40 do
		local a = safe(C_UnitAuras.GetAuraDataByIndex, "target", i, "HARMFUL")
		if not a then break end
		n = n + 1
		local function show(v) if isSecret(v) then return "hidden" end return tostring(v) end
		print(("%s%d. %s  id %s  stacks %s  yours %s"):format(P, i, show(a.name), show(a.spellId),
			show(a.applications), show(a.isFromPlayerOrPlayerPet)))
	end
	if n == 0 then print(P .. "no debuffs on your target") end
end
