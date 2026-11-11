-- Zyde_Forever: hunter pet care.
--   * "Feed pet" key: casts Feed Pet on the best food in your bags for your
--     pet - food it eats, not too low level, cheapest first.
--   * Reminder icon (out of combat) when your pet is only content or unhappy.
--   * "Call or revive pet" key: Revive Pet if it died, Call Pet if it's away,
--     nothing if it's already out. Reminder icon when you have no pet out.
--   * Growl warning: on autocast inside a dungeon it pulls mobs off your
--     tank; off autocast outside one you're missing your pet's taunt.
-- Set the keys in Options > Keybindings > AddOns > Zyde Forever.
--
-- Which food your pet eats: the game only tells us its diet ("Meat",
-- "Fish"...), not which diet each item is. So we use a list of common foods,
-- then words in the item's name, and we learn from the game's answer each
-- time you feed ("doesn't like that food" / "food level too low").

local ADDON, ns = ...

local _, playerClass = UnitClass("player")
local IS_HUNTER = playerClass == "HUNTER"

local FEED_PET, CALL_PET, REVIVE_PET, GROWL = 6991, 883, 982, 2649
local FEED_EFFECT = 1539 -- the "eating" buff on your pet
local GROWL_IDS = { [2649] = true, [14916] = true, [14917] = true, [14918] = true,
	[14919] = true, [14920] = true, [14921] = true }
local P = "|cff66ccffZyde_Forever|r: "

local function db() ZydeForeverDB = ZydeForeverDB or {} return ZydeForeverDB end
local function on() return IS_HUNTER and ns.F("petCare") end
local safe, isSecret = ns.safe, ns.isSecret
local function plain(v) if isSecret(v) then return nil end return v end

local function spellName(id)
	local n = (C_Spell and C_Spell.GetSpellName and safe(C_Spell.GetSpellName, id))
		or (GetSpellInfo and safe(GetSpellInfo, id))
	return plain(n)
end
local function spellIcon(id)
	return (C_Spell and C_Spell.GetSpellTexture and safe(C_Spell.GetSpellTexture, id))
		or (GetSpellTexture and safe(GetSpellTexture, id))
end
local function knowsSpell(id)
	if IsPlayerSpell and safe(IsPlayerSpell, id) then return true end
	return IsSpellKnown and safe(IsSpellKnown, id) or false
end
local function itemInfo(x)
	local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	return f(x)
end

local function petAlive() return UnitExists("pet") and not UnitIsDead("pet") end

-- "[F]" for a binding, or "" when none is set.
local function keyText(binding)
	local key = GetBindingKey(binding)
	if not key then return "" end
	return " [" .. (GetBindingText and GetBindingText(key, "KEY_") or key) .. "]"
end

---------------------------------------------------------------------------
-- Food: what diet an item belongs to
---------------------------------------------------------------------------
-- Common vendor foods, by diet.
local KNOWN = {}
for diet, ids in pairs({
	meat   = { 117, 2287, 3770, 3771, 4599, 8952 },
	bread  = { 4540, 4541, 4542, 4544, 4601, 8950 },
	fish   = { 787, 4592, 4593, 4594, 21552, 8957 },
	fruit  = { 4536, 4537, 4538, 4539, 4602, 8953 },
	fungus = { 4604, 4605, 4606, 4607, 4608, 8948 },
	cheese = { 2070, 414, 422, 1707, 3927, 8932 },
}) do
	for _, id in ipairs(ids) do KNOWN[id] = diet end
end

-- Name words, for food not in the list (raw meat, cooked dishes...).
local WORDS = {
	{ "meat", { "meat", "haunch", "jerky", "steak", "chop", "flank", "ribs", "shank", "sausage", "bacon", "venison", "kabob", "chili" } },
	{ "fish", { "fish", "snapper", "catfish", "cod", "mackerel", "yellowtail", "salmon", "eel", "trout", "squid", "lobster", "clam", "crab", "mightfish", "loach", "grouper", "smallfish" } },
	{ "bread", { "bread", "cornbread", "muffin", "biscuit", "pie", "cake", "cookie" } },
	{ "cheese", { "cheese", "brie", "cheddar", "swiss", "bleu", "dalaran sharp", "dwarven mild", "gouda" } },
	{ "fruit", { "apple", "banana", "snapdragon", "pumpkin", "plantain", "melon", "grape", "berry", "berries", "peach" } },
	{ "fungus", { "mushroom", "morel", "mold", "truffle", "bolete" } },
}

-- Drinks, potions and scrolls that a name word could be mistaken for food.
-- (Whole words where a short one would hide inside a food name: "tea" in "steak".)
local NOT_FOOD = { "juice", "water", "milk", "wine", " ale", "grog", "brew", "potion",
	"elixir", "scroll", "flask", "recipe", "spice", "egg" }

local function guessDiet(id, name, classID)
	if KNOWN[id] then return KNOWN[id] end
	if classID ~= 0 and classID ~= 7 then return nil end -- consumables and trade goods only
	local lower = name:lower()
	for _, w in ipairs(NOT_FOOD) do
		if lower:find(w, 1, true) then return nil end
	end
	for _, entry in ipairs(WORDS) do
		for _, w in ipairs(entry[2]) do
			if lower:find(w, 1, true) then return entry[1] end
		end
	end
	return nil
end

-- What we've learned from feeding: ZydeForeverDB.petFood
--   good["Wolf/2672"] = true   eaten by this kind of pet
--   bad["Wolf/4540"]  = true   "doesn't like that food"
--   low[4540] = 22             too low level for a pet of level 22 or higher
local function learned()
	local d = db()
	d.petFood = d.petFood or { good = {}, bad = {}, low = {} }
	return d.petFood
end

local function petFamily() return plain(UnitCreatureFamily("pet")) or "?" end

local function dietSet()
	local set, any = {}, false
	local fn = ns.PetInfoFn and ns.PetInfoFn("GetPetFoodTypes") or GetPetFoodTypes
	local types = fn and { safe(fn) } or {}
	if type(types[1]) == "table" then types = types[1] end -- returned as one list
	for _, t in ipairs(types) do
		if type(t) == "string" and not isSecret(t) then set[t:lower()] = true any = true end
	end
	return any and set or nil
end

---------------------------------------------------------------------------
-- Food: pick the best stack in your bags
---------------------------------------------------------------------------
-- How much a food helps a pet of this level (approximate Classic rules):
-- 3 = full, 2 = less, 1 = little, nil = too low to bother.
local function foodTier(itemLevel, petLevel)
	local diff = petLevel - (itemLevel or 0)
	if diff <= 5 then return 3 end
	if diff <= 10 then return 2 end
	if diff <= 15 then return 1 end
	return nil
end

local food -- { bag, slot, id, link, count } or nil

local function pickFood()
	food = nil
	if not on() or not UnitExists("pet") then return end
	-- No diet from the game (Forever has no GetPetFoodTypes): try any food
	-- and let the game's "doesn't like that" answers teach us.
	local diets = dietSet()
	local family, L = petFamily(), learned()
	local petLevel = plain(UnitLevel("pet")) or UnitLevel("player")
	local best, bestScore
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local id = info and info.itemID
			if id then
				local key = family .. "/" .. id
				local name, _, _, itemLevel, _, _, _, _, _, _, sellPrice, classID = itemInfo(info.hyperlink or id)
				local quest = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
				local isQuest = quest and (quest.isQuestItem or quest.questID)
				if name and not isQuest and not L.bad[key] and not (L.low[id] and petLevel >= L.low[id]) then
					local diet = guessDiet(id, name, classID)
					if L.good[key] or (diet and (not diets or diets[diet])) then
						local tier = foodTier(itemLevel, petLevel)
						if tier then
							local count = tonumber(info.stackCount) or 1
							-- Best help first, then the cheapest, then the smallest stack.
							-- Food it ate before beats a guess.
							local score = tier * 1e9 + (L.good[key] and 5e8 or 0) - (sellPrice or 0) * 1000 - math.min(count, 999)
							if not bestScore or score > bestScore then
								best, bestScore = { bag = bag, slot = slot, id = id, link = info.hyperlink, count = count }, score
							end
						end
					end
				end
			end
		end
	end
	food = best
end

---------------------------------------------------------------------------
-- Secure buttons (keybinds)
---------------------------------------------------------------------------
local FEED_BIND = "CLICK ZydeForeverFeedPet:LeftButton"
local CALL_BIND = "CLICK ZydeForeverCallPet:LeftButton"
_G["BINDING_NAME_" .. FEED_BIND] = "Feed pet (best food in bags)"
_G["BINDING_NAME_" .. CALL_BIND] = "Call or revive pet"

local function secureButton(name)
	local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
	b:SetSize(1, 1)
	b:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
	b:SetAlpha(0)
	b:SetAttribute("type", "macro")
	b:SetAttribute("macrotext", "")
	return b
end

local feedButton = secureButton("ZydeForeverFeedPet")
local callButton = secureButton("ZydeForeverCallPet")

local petDied = false -- saw the pet dead and it hasn't come back yet
local lastFeed, lastCall
local tried -- { key, id, at } the food the last key press fed

local function updateButtons()
	if InCombatLockdown() then return end -- they can't change in combat
	local down = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
	feedButton:RegisterForClicks(down and "AnyDown" or "AnyUp")
	callButton:RegisterForClicks(down and "AnyDown" or "AnyUp")

	local feedText = ""
	if on() then
		local feed = spellName(FEED_PET)
		if not UnitExists("pet") then
			feedText = "/run print(\"Zyde_Forever: no pet to feed\")"
		elseif not food then
			feedText = "/run print(\"Zyde_Forever: no food in your bags that your pet will eat\")"
		elseif feed then
			feedText = ("/cast %s\n/use %d %d"):format(feed, food.bag, food.slot)
		end
	end
	if feedText ~= lastFeed then feedButton:SetAttribute("macrotext", feedText) lastFeed = feedText end

	local callText = ""
	if on() then
		local call, revive = spellName(CALL_PET), spellName(REVIVE_PET)
		if petDied and not UnitExists("pet") and revive then
			callText = "/cast " .. revive
		elseif call and revive then
			callText = ("/cast [@pet,dead] %s; [nopet] %s"):format(revive, call)
		end
	end
	if callText ~= lastCall then callButton:SetAttribute("macrotext", callText) lastCall = callText end
end

feedButton:HookScript("PreClick", function()
	if food then tried = { key = petFamily() .. "/" .. food.id, id = food.id, at = GetTime() } end
end)

local function refresh()
	if UnitExists("pet") then
		if UnitIsDead("pet") then petDied = true else petDied = false end
	end
	pickFood()
	updateButtons()
end

local pending = false
local function refreshSoon()
	if pending then return end
	pending = true
	C_Timer.After(0.3, function() pending = false refresh() end)
end

---------------------------------------------------------------------------
-- Reminders in the icon column beside your character
---------------------------------------------------------------------------
local function eating()
	local name = spellName(FEED_EFFECT)
	if not (name and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then return false end
	return safe(C_UnitAuras.GetAuraDataBySpellName, "pet", name, "HELPFUL") ~= nil
end

local function quietTime()
	return not InCombatLockdown() and not UnitIsDeadOrGhost("player") and not UnitOnTaxi("player")
end

ns.AddReminder("petFeed", "ZydeForeverPetFeed", spellIcon(FEED_PET) or "Interface\\Icons\\Ability_Hunter_BeastTraining",
	function(preview)
		if preview then return IS_HUNTER, "Feed pet" end
		if not on() or not quietTime() or not petAlive() then return false end
		local happy = ns.PetHappiness and ns.PetHappiness()
		if not happy or happy >= 3 or eating() then return false end
		if not food then return true, "Feed pet - no food it eats!" end
		return true, (happy == 1 and "Pet is unhappy - feed it" or "Feed pet") .. keyText(FEED_BIND)
	end)

ns.AddReminder("petCall", "ZydeForeverPetCall", spellIcon(CALL_PET) or "Interface\\Icons\\Ability_Hunter_BeastCall",
	function(preview)
		if preview then return IS_HUNTER, "Call pet" end
		if not on() or not quietTime() or not knowsSpell(CALL_PET) then return false end
		if IsMounted() or IsResting() or petAlive() then return false end
		if petDied or UnitExists("pet") then return true, "Pet is dead - revive it" .. keyText(CALL_BIND) end
		return true, "No pet out - call it" .. keyText(CALL_BIND)
	end)

-- Growl on the pet action bar: its slot and whether autocast is on.
local growlState, growlAt = nil, 0
local function readGrowl()
	local growl = spellName(GROWL)
	for i = 1, (NUM_PET_ACTION_SLOTS or 10) do
		local r = { safe(GetPetActionInfo, i) }
		local name = plain(r[1])
		-- Newer clients: ..., autoCastEnabled (6), spellID (7). Older: one more field before.
		local spellID, auto
		if type(r[7]) == "number" then spellID, auto = r[7], r[6] else auto = r[7] end
		if (spellID and GROWL_IDS[spellID]) or (name and growl and name == growl) then
			return plain(auto) and true or false
		end
	end
	return nil -- no Growl on the bar
end
-- The reminder column asks 10 times a second; reading the pet bar once a second is plenty.
local function growlAutocast()
	if GetTime() - growlAt >= 1 then growlState, growlAt = readGrowl(), GetTime() end
	return growlState
end

ns.AddReminder("petGrowl", "ZydeForeverPetGrowl", spellIcon(GROWL) or "Interface\\Icons\\Ability_Physical_Taunt",
	function(preview)
		if preview then return IS_HUNTER, "Growl is on in a dungeon" end
		if not on() or not petAlive() then return false end
		local auto = growlAutocast()
		if auto == nil then return false end
		local _, instance = IsInInstance()
		local dungeon = instance == "party" or instance == "raid"
		if dungeon and auto then
			return true, "Growl is on - right-click it on the pet bar so your pet doesn't steal the tank's mobs"
		end
		if not dungeon and not auto and not InCombatLockdown() then
			return true, "Growl autocast is off - right-click it on the pet bar"
		end
		return false
	end)

---------------------------------------------------------------------------
-- Loud warning when your pet's mood drops (any time, combat included):
-- content -> chat line and a sound; unhappy -> raid warning, sound, and
-- again every minute until it's fed. Unhappy pets lose loyalty and run away.
---------------------------------------------------------------------------
local lastHappy, unhappyNagAt = nil, 0

local function alert(msg, loud)
	if loud and RaidNotice_AddMessage and RaidWarningFrame then
		RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.3, b = 0.2 })
	end
	PlaySound((SOUNDKIT and (loud and SOUNDKIT.RAID_WARNING or SOUNDKIT.TELL_MESSAGE)) or 8959, "Master")
	print(P .. msg)
end

C_Timer.NewTicker(1, function()
	if not on() or not petAlive() then lastHappy = nil return end
	local happy, _, loyaltyRate = ns.PetHappiness()
	if not happy then return end
	local name = plain(UnitName("pet")) or "Your pet"
	if lastHappy and happy < lastHappy then
		if happy == 2 then
			alert(name .. " is only content - feed it soon" .. keyText(FEED_BIND), false)
		elseif happy == 1 then
			alert(name .. " is UNHAPPY - feed it or it will run away" .. keyText(FEED_BIND), true)
			unhappyNagAt = GetTime()
		end
	elseif happy == 1 and GetTime() - unhappyNagAt >= 60 then
		alert(name .. " is still unhappy" .. ((type(loyaltyRate) == "number" and loyaltyRate < 0) and " and losing loyalty" or "")
			.. " - feed it" .. keyText(FEED_BIND), true)
		unhappyNagAt = GetTime()
	end
	lastHappy = happy
end)

---------------------------------------------------------------------------
-- Learning which food works
---------------------------------------------------------------------------
local function feedResult(ok, low)
	if not tried or GetTime() - tried.at > 5 then return end
	local L = learned()
	if ok then
		L.good[tried.key] = true
	elseif low then
		L.low[tried.id] = plain(UnitLevel("pet")) or UnitLevel("player")
		print(P .. "that food is too low level for your pet now - picking another next time")
	else
		L.bad[tried.key] = true
		print(P .. "your pet won't eat that - picking another next time")
	end
	tried = nil
	refreshSoon()
end

local function matches(msg, global, fallback)
	if type(msg) ~= "string" or isSecret(msg) then return false end
	if global and msg == global then return true end
	return msg:lower():find(fallback, 1, true) ~= nil
end

---------------------------------------------------------------------------
-- Pet log: game messages about your pet, kept in ZydeForeverDB.petLog
-- (last 30), so after "my pet left" we can see what the game said.
---------------------------------------------------------------------------
local lastPetName, lastPetAlive
local PET_WORDS = { "pet", "happy", "loyal", "run away", "ran away", "abandon", "leaves", "left you", "hungry", "feed" }

local function logPet(text)
	local d = db()
	d.petLog = d.petLog or {}
	table.insert(d.petLog, (date and date("%m-%d %H:%M") or "?") .. "  " .. text)
	while #d.petLog > 30 do table.remove(d.petLog, 1) end
end

local function petMessage(event, msg)
	if type(msg) ~= "string" or isSecret(msg) then return end
	local lower = msg:lower()
	local hit = lastPetName and lower:find(lastPetName:lower(), 1, true)
	if not hit then
		for _, w in ipairs(PET_WORDS) do
			if lower:find(w, 1, true) then hit = true break end
		end
	end
	if hit then logPet(event .. ": " .. msg) end
end

local function watchPetChange()
	local exists = UnitExists("pet")
	local name = exists and plain(UnitName("pet")) or nil
	if lastPetName and not exists then
		logPet(("pet gone: %s (it was %s)"):format(lastPetName, lastPetAlive and "alive" or "dead"))
	elseif name and name ~= lastPetName then
		logPet("pet out: " .. name)
	end
	if exists then lastPetName, lastPetAlive = name or lastPetName, not UnitIsDead("pet")
	else lastPetName, lastPetAlive = nil, nil end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, a1, a2, a3)
	if event == "PLAYER_LOGIN" then
		if not IS_HUNTER then return end
		for _, e in ipairs({ "BAG_UPDATE_DELAYED", "UNIT_PET", "UNIT_HEALTH", "UNIT_LEVEL", "UNIT_HAPPINESS",
			"PET_UI_UPDATE", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "UPDATE_BINDINGS",
			"UI_ERROR_MESSAGE", "GET_ITEM_INFO_RECEIVED",
			"CHAT_MSG_SYSTEM", "CHAT_MSG_PET_INFO", "CHAT_MSG_MONSTER_EMOTE", "UI_INFO_MESSAGE" }) do
			pcall(ev.RegisterEvent, ev, e)
		end
		pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SUCCEEDED", "player")
		watchPetChange()
		refreshSoon()
		return
	end
	if event == "CHAT_MSG_SYSTEM" or event == "CHAT_MSG_PET_INFO" or event == "CHAT_MSG_MONSTER_EMOTE" then
		petMessage(event, a1)
		return
	end
	if event == "UI_INFO_MESSAGE" then petMessage(event, a2) return end
	if event == "UNIT_PET" and a1 == "player" then watchPetChange() end
	if event == "UNIT_HEALTH" and a1 == "pet" and UnitExists("pet") then lastPetAlive = not UnitIsDead("pet") end
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		if plain(a3) == FEED_PET then feedResult(true) end
		return
	end
	if event == "UI_ERROR_MESSAGE" then
		local msg = a2
		petMessage(event, msg)
		if matches(msg, _G.SPELL_FAILED_FOOD_LOWLEVEL, "level is not high enough") then feedResult(false, true)
		elseif matches(msg, _G.SPELL_FAILED_WRONG_PET_FOOD, "doesn't like") then feedResult(false, false) end
		return
	end
	if event == "UNIT_HEALTH" then
		if a1 ~= "pet" then return end
		if UnitIsDead("pet") and not petDied then petDied = true refreshSoon() end
		return
	end
	if (event == "UNIT_LEVEL" or event == "UNIT_HAPPINESS") and a1 ~= "pet" then return end
	if event == "GET_ITEM_INFO_RECEIVED" and food then return end
	refreshSoon()
end)

ns.OnFeatureChanged(function(key) if key == "petCare" then refresh() end end)

---------------------------------------------------------------------------
-- /zyde petdebug: what the game tells us about your pet
---------------------------------------------------------------------------
local function show(v)
	if isSecret(v) then return "<hidden>" end
	return tostring(v)
end

local function debug()
	print(P .. "pet debug")
	print(("  hunter=%s  feature on=%s"):format(tostring(IS_HUNTER), tostring(on())))
	print(("  pet exists=%s  dead=%s  name=%s  family=%s  level=%s"):format(
		show(UnitExists("pet")), show(UnitIsDead("pet")), show(UnitName("pet")), show(UnitCreatureFamily("pet")), show(UnitLevel("pet"))))
	if GetPetHappiness then
		local r = { pcall(GetPetHappiness) }
		print(("  GetPetHappiness: ok=%s  happiness=%s  damage%%=%s  loyaltyRate=%s"):format(
			tostring(r[1]), show(r[2]), show(r[3]), show(r[4])))
	else
		print("  GetPetHappiness: does not exist on this client")
	end
	-- Forever's C_PetInfo versions, raw (tables listed field by field).
	local function raw(name)
		local fn = C_PetInfo and C_PetInfo[name]
		if not fn then return "missing" end
		local r = { pcall(fn) }
		if not r[1] then return "error: " .. show(r[2]) end
		local out = {}
		for j = 2, math.max(2, #r) do
			local v = r[j]
			if type(v) == "table" and not isSecret(v) then
				local f = {}
				for k, x in pairs(v) do f[#f + 1] = tostring(k) .. "=" .. show(x) end
				out[#out + 1] = "{" .. table.concat(f, ", ") .. "}"
			else
				out[#out + 1] = show(v)
			end
		end
		return table.concat(out, ", ")
	end
	print("  C_PetInfo.GetPetHappiness: " .. raw("GetPetHappiness"))
	print("  C_PetInfo.GetPetLoyalty: " .. raw("GetPetLoyalty"))
	print("  C_PetInfo.GetPetFoodTypes: " .. raw("GetPetFoodTypes"))
	local happy, _, _, source = ns.PetHappiness()
	print(("  mood we use: %s (from %s)"):format(tostring(happy), tostring(source or "nothing")))
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
			for i = 1, 40 do
				local a = safe(C_UnitAuras.GetAuraDataByIndex, "pet", i, filter)
				if not a then break end
				print(("  pet %s %d: %s (spell %s)"):format(filter == "HARMFUL" and "debuff" or "buff", i, show(a.name), show(a.spellId)))
			end
		end
	end
	local diets = {}
	for d in pairs(dietSet() or {}) do diets[#diets + 1] = d end
	print("  eats: " .. (#diets > 0 and table.concat(diets, ", ") or "unknown"))
	print("  food picked: " .. (food and ((food.link or food.id) .. (" (bag %d slot %d)"):format(food.bag, food.slot)) or "none"))
	print(("  feed key:%s  call key:%s"):format(keyText(FEED_BIND) ~= "" and keyText(FEED_BIND) or " none",
		keyText(CALL_BIND) ~= "" and keyText(CALL_BIND) or " none"))
	print("  Growl autocast: " .. tostring(readGrowl()))

	-- What this client has at all.
	local have = {}
	for _, n in ipairs({ "GetPetFoodTypes", "GetPetLoyalty", "GetPetExperience", "GetPetTrainingPoints",
		"HasPetUI", "PetFrameHappiness", "PetPaperDollFrame", "C_PetInfo" }) do
		have[#have + 1] = n .. (_G[n] ~= nil and "=yes" or "=no")
	end
	print("  client has: " .. table.concat(have, "  "))
	if HasPetUI then
		local a, b = safe(HasPetUI)
		print(("  HasPetUI: %s, hunter pet=%s"):format(show(a), show(b)))
	end
	local spells = {}
	for _, s in ipairs({ { "Feed Pet", FEED_PET }, { "Call Pet", CALL_PET }, { "Revive Pet", REVIVE_PET },
		{ "Tame Beast", 1515 }, { "Dismiss Pet", 2641 }, { "Mend Pet", 136 } }) do
		spells[#spells + 1] = ("%s=%s"):format(s[1], knowsSpell(s[2]) and "known" or (spellName(s[2]) and "not known" or "missing"))
	end
	print("  spells: " .. table.concat(spells, "  "))
	for i = 1, (NUM_PET_ACTION_SLOTS or 10) do
		local r = { safe(GetPetActionInfo, i) }
		if r[1] then
			local parts = {}
			for j = 1, 8 do parts[j] = show(r[j]) end
			print(("  pet bar %d: %s"):format(i, table.concat(parts, ", ")))
		end
	end
	-- Blizzard's happiness face, and anything happiness-like in this client.
	local face = _G.PetFrameHappiness
	if face then
		local tex = _G.PetFrameHappinessTexture or face.texture
		local coords = tex and tex.GetTexCoord and { safe(tex.GetTexCoord, tex) } or {}
		local c = {}
		for j = 1, 8 do
			local v = coords[j]
			c[j] = (v == nil and "-") or (isSecret(v) and "?") or ("%.3f"):format(tonumber(v) or -1)
		end
		print(("  PetFrameHappiness: shown=%s  texture=%s  coords=%s  tooltip=%s"):format(
			tostring(face:IsShown()), show(tex and tex.GetTexture and tex:GetTexture()),
			table.concat(c, ","), show(face.tooltip)))
	end
	if C_PetInfo then
		local keys = {}
		for k in pairs(C_PetInfo) do keys[#keys + 1] = tostring(k) end
		table.sort(keys)
		print("  C_PetInfo: " .. table.concat(keys, ", "))
	end
	local found = {}
	for k, v in pairs(_G) do
		if type(k) == "string" then
			local l = k:lower()
			if (l:find("happi") or l:find("loyal") or l:find("petfood") or l:find("diet"))
				and (type(v) == "function" or type(v) == "table") and not l:find("^zyde") then
				found[#found + 1] = k .. "(" .. type(v) .. ")"
			end
		end
	end
	table.sort(found)
	print("  happiness-like names: " .. (#found > 0 and table.concat(found, ", ") or "none"))

	local log = db().petLog
	if log and #log > 0 then
		print("  recent pet messages:")
		for i = math.max(1, #log - 9), #log do print("    " .. log[i]) end
	else
		print("  recent pet messages: none yet")
	end
end

ns.PetCare = { Debug = debug }
