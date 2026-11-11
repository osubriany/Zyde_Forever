-- Zyde_Forever: more reminder icons in the column beside your character
-- (all under the "Reminder icons" toggle).
--   Warrior: Execute ready, Revenge ready, wrong stance (out of combat),
--            Sunder Armor stacks while tanking.
--   Hunter:  Cheetah / Pack on in combat (flashing), Hunter's Mark missing
--            on an elite / rare / player / dungeon target, Mongoose Bite
--            ready, Mend Pet when your pet is low.
--   Both:    gear badly damaged, running low on food (and water for hunters).
-- Battle Shout running out (under 10 seconds) blinks in Zyde_Forever.lua.

local ADDON, ns = ...

local safe, isSecret, knownRank = ns.safe, ns.isSecret, ns.knownRank
local _, playerClass = UnitClass("player")
local WARRIOR, HUNTER = playerClass == "WARRIOR", playerClass == "HUNTER"
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

-- Your auras / your debuffs on a unit, by spell ID set. Returns found, unknown
-- (unknown = the game hid the details, so we can't tell).
local function hasAura(unit, filter, idSet)
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return false, true end
	local hidden = false
	for i = 1, 40 do
		local a = safe(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
		if not a then break end
		local id = plain(a.spellId)
		if id == nil then hidden = true elseif idSet[id] then return true, false, a end
	end
	return false, hidden
end

local function set(ids) local s = {} for _, id in ipairs(ids) do s[id] = true end return s end

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
local BATTLE_STANCE, DEFENSIVE_STANCE = 2457, 71

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
		if s == 2 and not IsInGroup() and not inDungeon() and knownRank({ BATTLE_STANCE }) then
			stanceTile.tex:SetTexture(ns.spellTexture(BATTLE_STANCE, "Interface\\Icons\\Ability_Warrior_OffensiveStance"))
			return true, "Battle Stance?"
		end
		if s == 1 and inDungeon() and IsInGroup() and hasShield() and knownRank({ DEFENSIVE_STANCE }) then
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
		local stacks = found and (plain(a.applications) or 1) or 0
		if stacks >= 5 then return false end
		return true, ("Sunder %d/5"):format(stacks)
	end)
end

---------------------------------------------------------------------------
-- Hunter
---------------------------------------------------------------------------
local CHEETAH, PACK = 5118, 13159
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

	local cheetahTile
	cheetahTile = ns.AddReminder("cheetah", "ZydeForeverCheetah", ns.spellTexture(CHEETAH, "Interface\\Icons\\Ability_Mount_JungleTiger"), function(preview)
		if preview then return true, "Cheetah on!" end
		if not on() or not inCombat() then return false end
		local found, hidden, a = hasAura("player", "HELPFUL", set({ CHEETAH, PACK }))
		local which = found and plain(a.spellId)
		if not found and hidden then which = (lastAspect == CHEETAH or lastAspect == PACK) and lastAspect or nil end
		if not which then return false end
		cheetahTile.tex:SetTexture(ns.spellTexture(which, cheetahTile.fallback))
		blink(cheetahTile, true)
		return true, (which == PACK and "Pack on!" or "Cheetah on!")
	end)

	-- Worth marking: elites, rares, bosses, players - and anything in a dungeon.
	local function worthMarking()
		local c = plain(UnitClassification("target"))
		return inDungeon() or plain(UnitIsPlayer("target")) or (c and c ~= "normal" and c ~= "trivial" and c ~= "minus")
	end
	ns.AddReminder("huntersMark", "ZydeForeverHuntersMark", icon(MARK, "Ability_Hunter_SniperShot"), function(preview)
		if preview then return true end
		if not on() or not inCombat() or not hostileTarget() or not knownRank(MARK) or not worthMarking() then return false end
		local found, hidden = hasAura("target", "HARMFUL", MARK_SET)
		return not found and not hidden
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
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID then
				local spell = plain(safe(getSpell, info.itemID))
				if type(spell) == "string" then
					local n = tonumber(info.stackCount) or 1
					if spell == "Food" or spell == "Refreshment" or spell == "Food & Drink" then food = food + n end
					if spell == "Drink" or spell == "Refreshment" or spell == "Food & Drink" then drink = drink + n end
				end
			end
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
