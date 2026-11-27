-- Zyde_Forever: ability highlight. A blue glow on the action button that does the most damage
-- right now (option "Ability highlight").
--
-- What it weighs, each tenth of a second while you have an enemy targeted:
--   * what's on your bars (the rank you put there), what each does: damage, damage over time and
--     its length, cooldown, cast time, cost - read from the spells' own tooltips out of combat
--   * how long the fight has left: your target's health, falling at the rate you've been
--     taking it down (or, while the game hides health in a fight, a guess from the mob's type
--     and how long you've been at it, shortened by the people helping you)
--   * how many enemies are fighting you (nameplates in combat with you): area spells count once
--     per target, up to their cap, and only from their minimum number of targets
--   * what's ready: your own cooldowns (counted from your casts) and the game's when it says;
--     damage over time already ticking on this target; reach; mana, rage or energy when shown;
--     combo points for finishers; reactive moves (Overpower, Revenge...) only when usable
-- Score = damage it will really do (a damage-over-time spell only for the time the fight has
-- left; area spells x targets) / time it takes (global cooldown or cast). Highest wins.
--
-- Health-gated moves (Execute under 20%, Drain Soul for a shard near the end, a finisher on a
-- nearly dead target) can't be decided in Lua while the game hides health in a fight. Their glow
-- and the normal pick's glow both sit inside "gates": hidden status bars fed the target's real
-- (hidden) health, whose fill edge clips each glow - so the game itself shows the right one.
--
-- The glow is its own frame drawn over the button: the action buttons themselves are never touched.

local ADDON, ns = ...
local isSecret, safe = ns.isSecret, ns.safe
local function plain(v) if isSecret(v) then return nil end return v end
local function on() return ns.F("rotation") end

local _, playerClass = UnitClass("player")
local FLAT = "Interface\\Buttons\\WHITE8X8"
local GLOW = "Interface\\Buttons\\UI-ActionButton-Border"
local BLUE = { 0.25, 0.6, 1 }
local K = 200 -- gate bars are this many times wider than what they gate

---------------------------------------------------------------------------
-- What each class presses. name = the spell's name (any rank on your bars).
--   kind: "filler", "direct", "dot", "builder", "finisher", "reactive", "execute"
--   aoe = {min, max}: hits up to max enemies, only worth it from min
--   threshold: target health share at or under which it's used (execute kind)
--   form: only in this shapeshift form id (druid: 1 cat, 5 bear)
--   gcd: its global cooldown when not 1.5
--   needUsable: only when the game says it's usable right now (reactive moves)
-- The order is the fallback when a tooltip gives no numbers (earlier = better).
---------------------------------------------------------------------------
local CLASSES = {
	WARLOCK = {
		{ name = "Drain Soul", kind = "execute", threshold = 0.25, shardCap = 3 },
		{ name = "Shadowburn", kind = "execute", threshold = 0.25 },
		{ name = "Corruption", kind = "dot" },
		{ name = "Curse of Agony", kind = "dot" },
		{ name = "Immolate", kind = "dot" },
		{ name = "Siphon Life", kind = "dot" },
		{ name = "Death Coil", kind = "direct" },
		{ name = "Conflagrate", kind = "direct", needUsable = true },
		{ name = "Hellfire", kind = "direct", aoe = { 3, 10 } },
		{ name = "Rain of Fire", kind = "direct", aoe = { 3, 10 } },
		{ name = "Searing Pain", kind = "filler" },
		{ name = "Shadow Bolt", kind = "filler" },
	},
	WARRIOR = {
		{ name = "Execute", kind = "execute", threshold = 0.2 },
		{ name = "Victory Rush", kind = "reactive", needUsable = true },
		{ name = "Overpower", kind = "reactive", needUsable = true },
		{ name = "Revenge", kind = "reactive", needUsable = true },
		{ name = "Mortal Strike", kind = "direct" },
		{ name = "Bloodthirst", kind = "direct" },
		{ name = "Shield Slam", kind = "direct" },
		{ name = "Whirlwind", kind = "direct", aoe = { 2, 4 } },
		{ name = "Thunder Clap", kind = "direct", aoe = { 2, 4 } },
		{ name = "Cleave", kind = "direct", aoe = { 2, 2 } },
		{ name = "Rend", kind = "dot" },
		{ name = "Slam", kind = "filler" },
		{ name = "Heroic Strike", kind = "filler" },
	},
	ROGUE = {
		{ name = "Riposte", kind = "reactive", needUsable = true },
		{ name = "Eviscerate", kind = "finisher" },
		{ name = "Rupture", kind = "finisher", dotFinisher = true },
		{ name = "Blade Flurry", kind = "direct", aoe = { 2, 2 } },
		{ name = "Ghostly Strike", kind = "builder" },
		{ name = "Hemorrhage", kind = "builder" },
		{ name = "Backstab", kind = "builder", needUsable = true },
		{ name = "Sinister Strike", kind = "builder" },
	},
	HUNTER = {
		{ name = "Mongoose Bite", kind = "reactive", needUsable = true, melee = true },
		{ name = "Multi-Shot", kind = "direct", aoe = { 1, 3 }, rangedWeapon = true }, -- (worth it on one target too)
		{ name = "Volley", kind = "direct", aoe = { 3, 10 } },
		{ name = "Serpent Sting", kind = "dot" },
		{ name = "Aimed Shot", kind = "direct", rangedWeapon = true },
		{ name = "Arcane Shot", kind = "direct" },
		{ name = "Raptor Strike", kind = "filler", melee = true, meleeWeapon = true },
	},
	PALADIN = {
		-- Seals and Judgement are chosen by paladinPick (below), ahead of the scored list.
		{ name = "Seal of Righteousness", kind = "seal" },
		{ name = "Seal of Command", kind = "seal" },
		{ name = "Seal of the Crusader", kind = "seal" },
		{ name = "Judgement", kind = "judgement" },
		{ name = "Hammer of Wrath", kind = "execute", threshold = 0.2 },
		{ name = "Holy Strike", kind = "direct" },
		{ name = "Crusader Strike", kind = "direct" },
		{ name = "Exorcism", kind = "direct", needUsable = true },
		{ name = "Holy Shock", kind = "direct" },
		{ name = "Consecration", kind = "direct", aoe = { 2, 10 } },
	},
	MAGE = {
		{ name = "Fire Blast", kind = "direct" },
		{ name = "Arcane Explosion", kind = "direct", aoe = { 3, 10 } },
		{ name = "Cone of Cold", kind = "direct", aoe = { 2, 10 } },
		{ name = "Blizzard", kind = "direct", aoe = { 3, 10 } },
		{ name = "Flamestrike", kind = "direct", aoe = { 3, 10 } },
		{ name = "Arcane Missiles", kind = "filler" },
		{ name = "Pyroblast", kind = "filler" },
		{ name = "Fireball", kind = "filler" },
		{ name = "Frostbolt", kind = "filler" },
		{ name = "Scorch", kind = "filler" },
	},
	PRIEST = {
		{ name = "Shadow Word: Pain", kind = "dot" },
		{ name = "Holy Fire", kind = "dot" },
		{ name = "Mind Blast", kind = "direct" },
		{ name = "Holy Nova", kind = "direct", aoe = { 3, 10 } },
		{ name = "Mind Flay", kind = "filler" },
		{ name = "Smite", kind = "filler" },
	},
	SHAMAN = {
		{ name = "Stormstrike", kind = "direct" },
		{ name = "Flame Shock", kind = "dot" },
		{ name = "Earth Shock", kind = "direct" },
		{ name = "Chain Lightning", kind = "direct", aoe = { 2, 3 } },
		{ name = "Lightning Bolt", kind = "filler" },
	},
	DRUID = {
		{ name = "Ferocious Bite", kind = "finisher", form = 1 },
		{ name = "Rip", kind = "finisher", dotFinisher = true, form = 1 },
		{ name = "Rake", kind = "dot", form = 1, gcd = 1 },
		{ name = "Shred", kind = "builder", form = 1, needUsable = true },
		{ name = "Claw", kind = "builder", form = 1 },
		{ name = "Swipe", kind = "direct", aoe = { 2, 3 }, form = 5 },
		{ name = "Maul", kind = "filler", form = 5 },
		{ name = "Moonfire", kind = "dot", form = 0 },
		{ name = "Insect Swarm", kind = "dot", form = 0 },
		{ name = "Starfire", kind = "filler", form = 0 },
		{ name = "Wrath", kind = "filler", form = 0 },
	},
}
local LIST = CLASSES[playerClass]
local ENERGY_GCD = { ROGUE = 1 } -- (rogues and cat druids run on a 1-second global cooldown)
local SOUL_SHARD = 6265

---------------------------------------------------------------------------
-- 1. Your action buttons, by the spell on them: byName[name] = { button, spellID }
---------------------------------------------------------------------------
local BAR_PREFIXES = {
	"ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
	"MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button", "MultiBar8Button",
	"AbilityBarButton", "AbilityButton",
}
local byName = {}

local function spellName(id)
	local n = C_Spell and C_Spell.GetSpellName and safe(C_Spell.GetSpellName, id)
	if not n and GetSpellInfo then n = safe(GetSpellInfo, id) end
	return plain(n)
end

local function actionOf(b)
	local a = b.action
	if not a and b.CalculateAction then a = safe(b.CalculateAction, b) end
	if not a and b.GetAttribute then a = b:GetAttribute("action") end
	return plain(a)
end

local function scanBars()
	wipe(byName)
	for _, prefix in ipairs(BAR_PREFIXES) do
		for i = 1, 12 do
			local b = _G[prefix .. i]
			if b and b:IsVisible() then
				local a = actionOf(b)
				local kind, id = nil, nil
				if a then kind, id = safe(GetActionInfo, a) end
				kind, id = plain(kind), plain(id)
				if kind == "macro" and GetMacroSpell then id = plain(safe(GetMacroSpell, id)) kind = id and "spell" end
				local name = kind == "spell" and type(id) == "number" and spellName(id)
				if name and not byName[name] then byName[name] = { button = b, id = id } end
			end
		end
	end
end

---------------------------------------------------------------------------
-- 2. What a spell does, from its tooltip (read out of combat, kept by spell id)
---------------------------------------------------------------------------
local facts = {}
local function num(s) local v = (s or ""):gsub(",", "") return tonumber(v) end -- (gsub's count must not reach tonumber as a base)

local function parseFacts(id)
	local f = { direct = 0, dot = 0, dotDur = 0, cd = 0, cast = 0, cost = 0, finisher = {} }
	local data = C_TooltipInfo and C_TooltipInfo.GetSpellByID and safe(C_TooltipInfo.GetSpellByID, id)
	if type(data) ~= "table" then return nil end
	local body = {}
	for _, line in ipairs(data.lines or {}) do
		for _, t in ipairs({ plain(line.leftText), plain(line.rightText) }) do
			if type(t) == "string" then
				body[#body + 1] = t
				local c, cdm = t:match("([%d%.]+) sec cooldown"), t:match("([%d%.]+) min cooldown")
				if c then f.cd = num(c) or 0 elseif cdm then f.cd = (num(cdm) or 0) * 60 end
				local cast = t:match("([%d%.]+) sec cast")
				if cast then f.cast = num(cast) or 0 end
				local cost = t:match("^(%d+) [MRE]%a+$") -- "120 Mana", "15 Rage", "40 Energy"
				if cost then f.cost = num(cost) or 0 end
			end
		end
	end
	local text = table.concat(body, "\n")
	-- Finishers: "1 point: 10-15 damage" lines.
	for p, lo, hi in text:gmatch("(%d) points?: (%d+)%-(%d+)") do f.finisher[tonumber(p)] = (num(lo) + num(hi)) / 2 end
	for p, v in text:gmatch("(%d) points?: (%d+) damage") do f.finisher[tonumber(p)] = num(v) end
	-- Damage over time: "... 120 Shadow damage over 18 sec" / "... over 12 sec ... 90 damage".
	local dotDmg, dotDur = text:match("(%d+) %a* ?damage over (%d+) sec")
	if not dotDmg then dotDur, dotDmg = text:match("over (%d+) sec[^%d]-(%d+) damage") end
	if dotDmg then f.dot, f.dotDur = num(dotDmg) or 0, num(dotDur) or 0 end
	-- Direct: "10 to 15" first, else the first "N damage" / "N Fire damage" that isn't the
	-- damage over time (Immolate: "8 Fire damage and then an additional 20 Fire damage over 15
	-- sec" - the school name between the number and "damage" used to hide the 8), else "an additional 40".
	local lo, hi = text:match("(%d+) to (%d+)")
	if lo then f.direct = (num(lo) + num(hi)) / 2
	else
		for d, rest in text:gmatch("(%d+) %a* ?damage( ?o?v?e?r?)") do
			if rest ~= " over" then f.direct = num(d) or 0 break end
		end
		if f.direct == 0 then
			-- "an additional 120", "increases ranged damage by 70" (Aimed Shot), "damage by 45"
			local d = text:match("additional (%d+)") or text:match("damage by (%d+)")
			if d and not (dotDmg and num(d) == f.dot) then f.direct = num(d) or 0 end
		end
	end
	-- Weapon strikes ("weapon damage plus 40"): add your average swing.
	if text:find("weapon damage", 1, true) then
		f.weapon = true
		local mn, mx = UnitDamage("player")
		mn, mx = plain(mn), plain(mx)
		if mn and mx then f.direct = f.direct + (mn + mx) / 2 end
	end
	return f
end

local function factsOf(id)
	local f = facts[id]
	if f == nil and not InCombatLockdown() then
		f = parseFacts(id) or false
		facts[id] = f
	end
	return f or nil
end

---------------------------------------------------------------------------
-- 3. The fight
---------------------------------------------------------------------------
local lastCast = {} -- [spell name] = GetTime() of your last cast
local lastManaCast = 0 -- your last spell that cost mana (mana comes back 5 seconds after it)
local dots = {}     -- [target GUID] = { [spell name] = time it runs out }
local samples = {}    -- your target's health over time (when the game shows it)
local engagedAt = {}  -- [mob GUID] = when you started fighting it
-- Your kill times: ZydeForeverDB.killTimes[character][kind] = { n, mean seconds }.
local function killStats()
	ZydeForeverDB = ZydeForeverDB or {}
	ZydeForeverDB.killTimes = ZydeForeverDB.killTimes or {}
	local me = (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "")
	ZydeForeverDB.killTimes[me] = ZydeForeverDB.killTimes[me] or {}
	return ZydeForeverDB.killTimes[me]
end

local function cooldownLeft(name, f)
	local entry = byName[name]
	if entry and C_Spell and C_Spell.GetSpellCooldown then
		local cd = safe(C_Spell.GetSpellCooldown, entry.id)
		if type(cd) == "table" then
			local s, d = plain(cd.startTime), plain(cd.duration)
			if s and d then
				if s == 0 or d <= 1.5 then return 0 end
				return math.max(0, s + d - GetTime())
			end
		end
	end
	local last = lastCast[name]
	if last and f and f.cd > 0 then return math.max(0, last + f.cd - GetTime()) end
	return 0
end

-- Enemies fighting you: nameplates of attackable units in combat that are on you (threat or target).
local function enemyCount()
	local n = 0
	for _, unit in ipairs(ns.Plates and ns.Plates.units() or {}) do
		local attack = plain(UnitCanAttack("player", unit))
		local fighting = plain(UnitAffectingCombat(unit))
		if attack and fighting then
			local threat = UnitThreatSituation and plain(UnitThreatSituation("player", unit))
			local onMe = plain(UnitIsUnit(unit .. "target", "player"))
			-- (and mobs only your pet is fighting: they were left out, so Multi-Shot looked worse)
			local petThreat = UnitThreatSituation and plain(UnitThreatSituation("pet", unit))
			local onPet = plain(UnitIsUnit(unit .. "target", "pet"))
			if (threat and threat > 0) or onMe or threat == nil or petThreat ~= nil or onPet then n = n + 1 end
		end
	end
	return math.max(1, n)
end

local function targetShare()
	local h, m = plain(UnitHealth("target")), plain(UnitHealthMax("target"))
	if not h or not m or m <= 0 then return nil end
	return h / m
end

-- Seconds the fight has left on your target.
local function timeToKill()
	local share = targetShare()
	local now = GetTime()
	if share then
		samples[#samples + 1] = { now, share }
		while #samples > 2 and now - samples[1][1] > 10 do table.remove(samples, 1) end
		local first = samples[1]
		local rate = (first[2] - share) / math.max(0.1, now - first[1])
		if rate > 0.001 then return share / rate end
	end
	-- Hidden, or too early to tell: how long your kills of this kind of mob take (learned, below;
	-- a guess until you've made a few), less the time already spent on THIS mob. (It used to count
	-- from when you entered combat, so a fresh mob pulled mid-fight looked nearly dead: 3 s left,
	-- and Serpent Sting wasn't worth casting.)
	local class = plain(UnitClassification("target"))
	local kind = (class == "elite" or class == "rareelite") and "elite" or (class == "worldboss" and "boss" or "normal")
	local learned = killStats()[kind]
	local base = (learned and learned.n >= 3) and learned.mean
		or (kind == "elite" and 45 or (kind == "boss" and 120 or 14))
	local helpers = plain(GetNumGroupMembers and GetNumGroupMembers()) or 0
	if helpers > 1 and not (learned and learned.n >= 3) then base = base / math.min(helpers, 5) * 1.5 end
	local guid = plain(UnitGUID("target"))
	local started = guid and engagedAt[guid]
	local spent = started and (now - started) or 0
	return math.max(3, base - spent)
end

-- Note when you start on a mob (it's fighting), and how long it took when it dies: a running
-- mean per kind of mob (normal / elite / boss), kept per character.
local recorded = {}
local function watchTarget()
	local guid = plain(UnitGUID("target"))
	if not guid then return end
	local now = GetTime()
	local fightingNow = plain(UnitAffectingCombat("target"))
	if not engagedAt[guid] and fightingNow then engagedAt[guid] = now end
	local started = engagedAt[guid]
	local dead = plain(UnitIsDead("target"))
	-- A live mob out of combat has reset (it ran home, healed): it's a fresh fight next time.
	if started and fightingNow == false and dead == false then
		engagedAt[guid], dots[guid] = nil, nil
		return
	end
	if started and not recorded[guid] and dead == true then
		recorded[guid] = true
		local took = now - started
		if took >= 2 and took <= 300 then
			local class = plain(UnitClassification("target"))
			local kind = (class == "elite" or class == "rareelite") and "elite" or (class == "worldboss" and "boss" or "normal")
			local stats = killStats()
			local s = stats[kind] or { n = 0, mean = took }
			s.n = math.min(s.n + 1, 10) -- (the last ten or so: you get stronger as you level)
			s.mean = s.mean + (took - s.mean) / s.n
			stats[kind] = s
		end
	end
end

local function power()
	local p = plain(UnitPower("player"))
	return p
end

local function comboPoints()
	local c = GetComboPoints and plain(GetComboPoints("player", "target"))
	if c == nil and UnitPower then c = plain(UnitPower("player", 4)) end
	return c
end

local function formId()
	local id = GetShapeshiftFormID and plain(GetShapeshiftFormID())
	return id or 0
end

local function shards()
	local f = (C_Item and C_Item.GetItemCount) or GetItemCount
	return f and plain(safe(f, SOUL_SHARD)) or 0
end

local function usable(entry)
	local u = C_Spell and C_Spell.IsSpellUsable and C_Spell.IsSpellUsable(entry.id)
	if u == nil and IsUsableSpell then u = IsUsableSpell(entry.id) end
	return plain(u)
end

-- In reach of your target? Asks the action button first (the game answers that for melee
-- moves too), then the spell. A spell marked melee = true (a hunter's Raptor Strike) that
-- nobody answers for is only in reach within about 10 yards. Unknown otherwise: allowed.
-- (Before: a hidden or missing answer counted as in range, so Raptor Strike glowed at 30 yards.)
local function verdict(r)
	r = plain(r)
	if r == false or r == 0 then return false end
	if r == true or r == 1 then return true end
	return nil
end
local SHOTS = { "Auto Shot", "Arcane Shot", "Serpent Sting", "Concussive Shot", "Multi-Shot", "Aimed Shot" }
local rangeOf -- (below: the plain range answer, used for the shots here)

-- A hunter's shots don't work inside about 8 yards: when one of them says the target is in
-- reach, you're not in melee.
local function shotInReach()
	for _, name in ipairs(SHOTS) do
		local e = byName[name]
		if e and rangeOf(e) == true then return true end
	end
	return false
end

local function inRange(entry, spell)
	if spell and spell.melee and playerClass == "HUNTER" and shotInReach() then return false end
	local v = rangeOf(entry)
	if v ~= nil then return v end
	if spell and spell.melee then
		local near = verdict(safe(CheckInteractDistance, "target", 3))
		return near == true
	end
	return true
end

-- The game's own range answer for this button / spell: true, false or nil (it won't say).
function rangeOf(entry)
	local v
	local a = entry.button and actionOf(entry.button)
	if a and IsActionInRange then v = verdict(safe(IsActionInRange, a)) end
	if v == nil and C_Spell and C_Spell.IsSpellInRange then v = verdict(safe(C_Spell.IsSpellInRange, entry.id, "target")) end
	if v == nil and IsSpellInRange then v = verdict(safe(IsSpellInRange, spellName(entry.id) or "", "target")) end
	return v
end

---------------------------------------------------------------------------
-- 4. Scoring: damage it will really do / the time it takes
---------------------------------------------------------------------------
local function score(spell, entry, f, ctx, index)
	if spell.form and spell.form ~= ctx.form then return nil end
	if cooldownLeft(spell.name, f) > 0.3 then return nil end
	if not inRange(entry, spell) then return nil end
	local u = usable(entry)
	if u == false then return nil end
	if spell.needUsable and u ~= true then return nil end
	if f and f.cost > 0 and ctx.power and f.cost > ctx.power then return nil end
	-- (hunters, below: the pet's head start - only a sting until it has the mob's attention;
	-- low on mana - nothing that costs it but a melee strike, Mend Pet's mana is kept)
	if ctx.headStart and spell.kind ~= "dot" and not spell.melee then return nil end
	if ctx.noDots and spell.kind == "dot" then return nil end
	if ctx.noAoe and spell.aoe then return nil end
	if ctx.mode == "dry" and f and f.cost > 0 and not spell.melee then return nil end

	local gcd = spell.gcd or ctx.gcd
	local time = math.max(gcd, f and f.cast or 0)
	local fallback = (40 - index) -- (no numbers in the tooltip: keep the class order)
	local dmg = 0
	if f then
		dmg = f.direct
		if spell.kind == "dot" or (f.dot > 0) then
			local running = ctx.dots and ctx.dots[spell.name]
			if running and running - GetTime() > 1.5 then
				if spell.kind == "dot" then return nil end -- already ticking on this target
			elseif f.dotDur > 0 then
				dmg = dmg + f.dot * math.min(1, ctx.ttk / f.dotDur)
			end
		end
		if spell.kind == "finisher" then
			local cp = ctx.cp
			if not cp or cp < 1 then return nil end
			-- (a full bar, or the fight ends before you'd fill it)
			if cp < 5 and ctx.ttk > 4 then return nil end
			local v = f.finisher[cp] or f.direct
			if spell.dotFinisher then
				if ctx.ttk < 8 then return nil end
				v = (f.finisher[cp] or f.dot) * math.min(1, ctx.ttk / math.max(f.dotDur, 8))
			end
			dmg = v
		end
	end
	-- Shots that fire your bow or gun (Multi-Shot, Aimed Shot): their bonus plus an average shot.
	if spell.rangedWeapon and UnitRangedDamage then
		local _, lo, hi = UnitRangedDamage("player")
		lo, hi = plain(lo), plain(hi)
		if lo and hi then dmg = dmg + (lo + hi) / 2 end
	end
	-- ...and a melee strike's (Raptor Strike: "increases melee damage by 45"), unless the
	-- tooltip's "weapon damage" already added it
	if spell.meleeWeapon and f and not f.weapon then
		local lo, hi = UnitDamage("player")
		lo, hi = plain(lo), plain(hi)
		if lo and hi then dmg = dmg + (lo + hi) / 2 end
	end
	if dmg <= 0 then dmg = fallback end
	if spell.aoe then
		if ctx.enemies < spell.aoe[1] then return nil end
		dmg = dmg * math.min(ctx.enemies, spell.aoe[2])
	end
	if spell.kind == "reactive" then dmg = dmg * 1.5 end -- (a window that closes: use it)
	return dmg / time, dmg, f and f.cost or 0
end

---------------------------------------------------------------------------
-- Paladins: keep the right seal up and judge it.
-- On Forever a seal lasts 30 seconds and Judgement does NOT use it up (the seal reminder relies
-- on the same), so the weave is:
--   * long fight (an elite, or a mob that will last over 20 s) and Seal of the Crusader known:
--     open with Seal of the Crusader, judge it (the target takes more Holy damage), then put
--     your damage seal on for the rest of the fight
--   * otherwise straight to the damage seal: Seal of Command with a slow weapon (3.3 s swing
--     or slower) when you have it, else Seal of Righteousness
--   * refresh the seal when it's missing, or in a fight with under 3 seconds left
--   * Judgement whenever it's ready, in reach, and a seal is up
-- Your buffs can be hidden in a fight, so your own seal casts are tracked too.
---------------------------------------------------------------------------
local SEAL_TIME, CRUSADER = 30, "Seal of the Crusader"
local sealName, sealUntil = nil, 0
local crusaderOn = {} -- [target GUID] = when your Judgement of the Crusader on it runs out

-- Your seal now and the seconds it has left (nil when there's none).
-- (Reads your buffs through the shared ns.PlayerBuffs, as the seal reminder does. A seal buff with
-- no expiry time given counts as up with its time unknown - it used to fall back to an old cast
-- time, which had run out, so the seal glowed blue all fight while it was on.)
local function currentSeal()
	local now = GetTime()
	local buffs = ns.PlayerBuffs and ns.PlayerBuffs()
	if buffs then
		for _, a in ipairs(buffs.list or {}) do
			local name = a.name
			if type(name) == "string" and name:find("^Seal of") then
				local exp = a.expirationTime
				if type(exp) == "number" and exp > now then
					sealName, sealUntil = name, exp
					return name, exp - now
				end
				-- time not given: your own cast of this seal, if it's still within 30 s
				if sealName == name and sealUntil > now then return name, sealUntil - now end
				return name, nil
			end
		end
		if not buffs.hidden then sealName, sealUntil = nil, 0 return nil end
	end
	-- Buffs hidden: go by your own seal casts.
	if sealName and sealUntil > now then return sealName, sealUntil - now end
	return nil
end

local function mainSeal()
	local speed = plain(UnitAttackSpeed and UnitAttackSpeed("player"))
	if byName["Seal of Command"] and speed and speed >= 3.3 then return "Seal of Command" end
	if byName["Seal of Righteousness"] then return "Seal of Righteousness" end
	return byName["Seal of Command"] and "Seal of Command" or nil
end

local function ready(name)
	local e = byName[name]
	if not e then return false end
	if cooldownLeft(name, facts[e.id]) > 0.3 then return false end
	return usable(e) ~= false
end

local function paladinPick(ctx, tg)
	local seal, left = currentSeal()
	local main = mainSeal()
	local now = GetTime()
	local judged = tg and crusaderOn[tg] and crusaderOn[tg] > now
	local class = plain(UnitClassification("target"))
	local long = ctx.ttk > 20 or class == "elite" or class == "rareelite" or class == "worldboss"
	local wantCrusader = byName[CRUSADER] and long and not judged
	local judgeReady = ready("Judgement") and inRange(byName["Judgement"])

	if seal == CRUSADER then
		if judgeReady and not judged then return "Judgement" end
		if (judged or not wantCrusader) and main and ready(main) then return main end
	end
	local fighting = InCombatLockdown()
	if not seal or (fighting and left and left < 3) then
		if wantCrusader and ready(CRUSADER) then return CRUSADER end
		if main and ready(main) then return main end
	end
	if seal and judgeReady then return "Judgement" end
	return nil
end

-- The best pick, and the health-gated one (execute kind) if any: pick, gatedPick, threshold.
-- opts (hunters): mode = "free" / "thrifty" (damage per mana counts too) / "dry" (no mana spent),
-- headStart = true while the pet takes the mob's attention.
local function choose(opts)
	if not LIST then return nil end
	local tg = plain(UnitGUID("target"))
	local ctx = {
		enemies = enemyCount(), ttk = timeToKill(), power = power(), cp = comboPoints(), form = formId(),
		gcd = ENERGY_GCD[playerClass] or ((playerClass == "DRUID" and formId() == 1) and 1 or 1.5),
		dots = tg and dots[tg],
		mode = opts and opts.mode, headStart = opts and opts.headStart, noDots = opts and opts.noDots,
		noAoe = opts and opts.noAoe,
	}
	if playerClass == "PALADIN" then
		local p = paladinPick(ctx, tg)
		if p then return p end
	end
	local share = targetShare()
	local best, bestScore, gated, gatedScore, threshold
	local cands = {}
	for index, spell in ipairs(LIST) do
		local entry = byName[spell.name]
		if entry and spell.kind ~= "seal" and spell.kind ~= "judgement" then
			local f = factsOf(entry.id)
			if spell.kind == "execute" then
				if not (spell.shardCap and shards() >= spell.shardCap) then
					local s = score(spell, entry, f, ctx, index)
					if s then
						if share then
							if share <= spell.threshold and (not bestScore or s * 2 > bestScore) then best, bestScore = spell.name, s * 2 end
						elseif not gatedScore or s > gatedScore then
							gated, gatedScore, threshold = spell.name, s, spell.threshold
						end
					end
				end
			else
				local s, dmg, cost = score(spell, entry, f, ctx, index)
				if s then cands[#cands + 1] = { name = spell.name, s = s, dmg = dmg, cost = cost } end
			end
		end
	end
	-- Thrifty: a spell's score shrinks with how much less damage per mana it does than the
	-- thriftiest one (free ones keep theirs).
	if ctx.mode == "thrifty" then
		local bestEff = 0
		for _, c in ipairs(cands) do
			if c.cost > 0 then bestEff = math.max(bestEff, c.dmg / c.cost) end
		end
		for _, c in ipairs(cands) do
			if c.cost > 0 and bestEff > 0 then c.s = c.s * (c.dmg / c.cost) / bestEff end
		end
	end
	for _, c in ipairs(cands) do
		if not bestScore or c.s > bestScore then best, bestScore = c.name, c.s end
	end
	return best, gated, threshold
end

---------------------------------------------------------------------------
-- 5. The glow. Two of them: the pick, and the health-gated pick. With a gated
-- pick, the gates (fed the target's hidden health) show one or the other.
---------------------------------------------------------------------------
local root = CreateFrame("Frame", "ZydeForeverRotation", UIParent)
root:SetFrameStrata("HIGH")
root:SetAllPoints()
root:EnableMouse(false)

local function makeGlow(parent, color)
	color = color or BLUE
	local g = CreateFrame("Frame", nil, parent)
	g:EnableMouse(false)
	g.tex = g:CreateTexture(nil, "OVERLAY")
	g.tex:SetTexture(GLOW)
	g.tex:SetBlendMode("ADD")
	g.tex:SetVertexColor(color[1], color[2], color[3])
	g.tex:SetPoint("CENTER")
	g.fill = g:CreateTexture(nil, "ARTWORK")
	g.fill:SetColorTexture(color[1], color[2], color[3], 0.22)
	g.fill:SetBlendMode("ADD")
	local pulse = g:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local a = pulse:CreateAnimation("Alpha")
	a:SetFromAlpha(0.55)
	a:SetToAlpha(1)
	a:SetDuration(0.45)
	g.pulse = pulse
	g:Hide()
	return g
end

local function placeGlow(g, button)
	if not button then g:Hide() g.pulse:Stop() return end
	g:ClearAllPoints()
	g:SetAllPoints(button)
	local w = button:GetWidth()
	if isSecret(w) or type(w) ~= "number" then w = 36 end
	g.tex:SetSize(w * 1.9, w * 1.9)
	g.fill:SetAllPoints(button)
	g:SetFrameLevel((button:GetFrameLevel() or 1) + 10)
	g:Show()
	if not g.pulse:IsPlaying() then g.pulse:Play() end
end

-- A gate: a frame that shows its children only while the target's health share is above (or not
-- above) `share`. Its clip edge is the fill edge of a hidden status bar fed the real health.
local gateBars = {}
local gateArea = CreateFrame("Frame", nil, root)
gateArea:SetSize(200, 200)
gateArea:SetPoint("CENTER")
local function gate(above)
	local bar = CreateFrame("StatusBar", nil, gateArea)
	bar:SetStatusBarTexture(FLAT)
	bar:SetStatusBarColor(0, 0, 0, 0)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	gateBars[#gateBars + 1] = bar
	local fill = bar:GetStatusBarTexture()
	local clip = CreateFrame("Frame", nil, root)
	clip:SetClipsChildren(true)
	if above then
		clip:SetPoint("TOPLEFT", bar, "TOPLEFT")
		clip:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
	else
		clip:SetPoint("TOPLEFT", fill, "TOPRIGHT")
		clip:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
	end
	bar.above = above
	return clip, bar
end
local aboveClip, aboveBar = gate(true)   -- the normal pick: health above the threshold
local belowClip, belowBar = gate(false)  -- the execute pick: health at or under it

local plainGlow = makeGlow(root)
local aboveGlow = makeGlow(aboveClip)
local belowGlow = makeGlow(belowClip)

-- Put the gate's switch-over at `share` of the way across the area that holds the glow.
local function aimGate(bar, area, share)
	local w, h = area:GetWidth(), area:GetHeight()
	if isSecret(w) or type(w) ~= "number" or w <= 0 then return end
	bar:ClearAllPoints()
	bar:SetSize(w * K, h * 3)
	bar:SetPoint("LEFT", area, "LEFT", -share * w * K, 0)
end

local function feedGates()
	local h, m = UnitHealth("target"), UnitHealthMax("target")
	for _, bar in ipairs(gateBars) do
		pcall(bar.SetMinMaxValues, bar, 0, m)
		pcall(bar.SetValue, bar, h)
	end
end

local hunterUpdate, hunterHide, hunterDebug -- (section 6, hunters)

local function hideAll()
	for _, g in ipairs({ plainGlow, aboveGlow, belowGlow }) do g:Hide() g.pulse:Stop() end
	if hunterHide then hunterHide() end
end

local function update()
	if not on() or not LIST then hideAll() return end
	local hostile = plain(UnitExists("target")) and plain(UnitCanAttack("player", "target"))
		and not plain(UnitIsDeadOrGhost("target"))
	if playerClass == "HUNTER" and hunterUpdate then
		for _, g in ipairs({ plainGlow, aboveGlow, belowGlow }) do g:Hide() g.pulse:Stop() end
		hunterUpdate(hostile and true or false)
		return
	end
	if not hostile then hideAll() return end
	local pick, gatedPick, threshold = choose()
	local pickBtn = pick and byName[pick] and byName[pick].button
	local gatedBtn = gatedPick and byName[gatedPick] and byName[gatedPick].button
	if gatedBtn then
		-- Both glows, each inside its gate; the gate areas sit over each glow's button.
		plainGlow:Hide() plainGlow.pulse:Stop()
		placeGlow(aboveGlow, pickBtn)
		placeGlow(belowGlow, gatedBtn)
		-- (each gate's bar spans its own button's area, so each switches at the threshold)
		aimGate(aboveBar, pickBtn or gatedBtn, threshold)
		aimGate(belowBar, gatedBtn, threshold)
		feedGates()
	else
		aboveGlow:Hide() aboveGlow.pulse:Stop()
		belowGlow:Hide() belowGlow.pulse:Stop()
		placeGlow(plainGlow, pickBtn)
	end
end

---------------------------------------------------------------------------
-- 6. Hunters: playing on your own means chain pulls, so the glows weigh more than damage.
--   * Mana for the next pull: above 55% anything goes; 25-55% damage per mana counts too
--     ("thrifty"); under 25% nothing that costs mana but a melee strike, keeping it for Mend
--     Pet. (In a group: 30% and 10%.)
--   * The pet first: its Attack button glows until it's on your target. On your own, nothing
--     glows until the mob is fighting, then 2 seconds of stings only, so the pet has its
--     attention before your big shots.
--   * Threat: no glow while you're above the tank on the mob (ease off). The tank is your pet
--     on your own (or with Growl on in a group), else your group's tank. Feign Death glows
--     amber when the mob turns on you; your shots wait meanwhile.
--   * Multi-Shot: only while you're safely under the tank on every other mob fighting (up to 3)
--     and no mob that isn't fighting stands by your target (it could pull it; judged from the
--     nameplates); else a one-target shot.
--   * Mend Pet glows green when your pet is under 40% in a fight (70% between fights: top it
--     up for the next pull), unless the mob is nearly dead. Your shots wait meanwhile.
--   * Danger: Bestial Wrath, Rapid Fire, Intimidation and your race's burst glow red when
--     more than one mob is on you and your pet (3 in a group), an elite while on your own, a
--     mob 3+ levels above you or a boss, your pet under 30% or you under 40%. Deterrence glows
--     red when you're under 50% and the mob is on you.
-- The game hides your mana and health (and maybe your pet's) from addons, so those checks are
-- the game's own: a curve turns the hidden percent into how see-through a glow is
-- (UnitHealthPercent / UnitPowerPercent with a step curve: 1 on one side of the line, 0 on the
-- other). Where that gives nothing, a hidden status bar fed the number clips the glow instead,
-- as the execute gates above do. Each glow sits in a stack of holders, one per condition, so
-- it shows only when they're all on. /zyde rotationdebug says which way each check went.
---------------------------------------------------------------------------
do
	local GREEN, RED, AMBER = { 0.3, 1, 0.35 }, { 1, 0.2, 0.15 }, { 1, 0.7, 0.1 }
	local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
	local DEPTH = 8 -- (mana 2, Mend Pet, threat, sting or 3 other mobs for Multi-Shot)
	local BIG = { "Bestial Wrath", "Rapid Fire", "Intimidation", "Blood Fury", "Berserking" }
	local NEEDS_PET = { ["Bestial Wrath"] = true, ["Intimidation"] = true }
	-- A sting only on a mob above this much health (the game's hidden number, through a curve):
	-- under it, the next best shot instead. (After Feign Death a nearly dead mob looked fresh.)
	local DOT_CUT = 0.3
	local isDot, isAoe = {}, {}
	for _, spell in ipairs(LIST or {}) do
		if spell.kind == "dot" then isDot[spell.name] = true end
		if spell.aoe and spell.aoe[2] > 1 then isAoe[spell.name] = true end
	end

	-- Your pet's Growl on autocast: true / false, nil when it isn't on the pet bar. Off (or no pet
	-- tanking) in a group means your group's tank holds the mobs.
	local GROWL_IDS = { [2649] = true, [14916] = true, [14917] = true, [14918] = true,
		[14919] = true, [14920] = true, [14921] = true }
	local function growlOn()
		local growl = spellName(2649)
		for i = 1, (NUM_PET_ACTION_SLOTS or 10) do
			local r = { safe(GetPetActionInfo, i) }
			local name = plain(r[1])
			-- (newer clients: ..., autoCastEnabled (6), spellID (7); older: one more field before)
			local spellID, auto
			if type(r[7]) == "number" then spellID, auto = r[7], r[6] else auto = r[7] end
			if (spellID and GROWL_IDS[spellID]) or (name and growl and name == growl) then
				return plain(auto) and true or false
			end
		end
		return nil
	end

	-- (/zyde rotationdebug curves off: status-bar gates only, to compare)
	local function useCurves()
		return not (ZydeForeverDB and ZydeForeverDB.rotationCurves == false)
	end

	-- Step curves, made once. points = { {x, y}, ... }. Each y is given at both ends of its stretch,
	-- so it reads the same whether the game holds the last point or takes the nearest one.
	local curves = {}
	local function curve(key, points)
		local c = curves[key]
		if c ~= nil then return c or nil end
		c = false
		local step = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step
		if step and C_CurveUtil and C_CurveUtil.CreateCurve then
			local ok, made = pcall(function()
				local k = C_CurveUtil.CreateCurve()
				k:SetType(step)
				for _, p in ipairs(points) do k:AddPoint(p[1], p[2]) end
				return k
			end)
			if ok and made then c = made end
		end
		curves[key] = c
		return c or nil
	end
	-- 1 under `cut` (below = true) or at/over it (below = false), else 0. Input is 0-1.
	local function cutCurve(cut, below)
		local a, b = below and 1 or 0, below and 0 or 1
		return curve(("cut%.3f%s"):format(cut, below and "b" or "a"),
			{ { 0, a }, { cut - 0.001, a }, { cut, b }, { 1, b } })
	end

	-- The holders. slots[id] = { wraps = { {a = alpha frame, c = clip frame, bar}, ... }, glow }
	local slots, used = {}, {}
	local hows = {} -- [check] = "plain" / "curve" / "gate" / "unknown" (for the debug)

	local function slot(id, color)
		local s = slots[id]
		if s then return s end
		s = { wraps = {} }
		local parent = root
		for i = 1, DEPTH do
			local a = CreateFrame("Frame", nil, parent)
			a:SetAllPoints(root)
			local c = CreateFrame("Frame", nil, a)
			c:SetAllPoints(root)
			local bar = CreateFrame("StatusBar", nil, gateArea)
			bar:SetStatusBarTexture(FLAT)
			bar:SetStatusBarColor(0, 0, 0, 0)
			bar:SetMinMaxValues(0, 1)
			bar:SetValue(1)
			s.wraps[i] = { a = a, c = c, bar = bar }
			parent = c
		end
		s.glow = makeGlow(parent, color)
		slots[id] = s
		return s
	end

	local function unclip(w)
		if not w.clipped then return end
		w.clipped = false
		w.c:SetClipsChildren(false)
		w.c:ClearAllPoints()
		w.c:SetAllPoints(root)
	end

	-- Clip to the part of the bar under (below) or over the fill edge, as gate() does.
	local function clipTo(w, below)
		local fill = w.bar:GetStatusBarTexture()
		w.c:ClearAllPoints()
		if below then
			w.c:SetPoint("TOPLEFT", fill, "TOPRIGHT")
			w.c:SetPoint("BOTTOMRIGHT", w.bar, "BOTTOMRIGHT")
		else
			w.c:SetPoint("TOPLEFT", w.bar, "TOPLEFT")
			w.c:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
		end
		w.c:SetClipsChildren(true)
		w.clipped = true
	end

	-- A unit's health (or power of `ptype`) share when the game shows it, and the raw numbers.
	local function readShare(unit, ptype)
		local cur, mx
		if ptype then cur, mx = safe(UnitPower, unit, ptype), safe(UnitPowerMax, unit, ptype)
		else cur, mx = safe(UnitHealth, unit), safe(UnitHealthMax, unit) end
		local pc, pm = plain(cur), plain(mx)
		if pc and pm and pm > 0 then return pc / pm, cur, mx end
		return nil, cur, mx
	end

	-- Set one holder for a condition:
	--   { kind = "share", unit, power = power type or nil, cut, below }  health / power under or over cut
	--   { kind = "bool", v = a yes/no (maybe hidden), yes = alpha, no = alpha }
	--   { kind = "threat", key, points = alpha for threat 0, 1, 2, 3 }  your threat on the target
	-- fallback: the alpha when it can't be told. label: the check's name in the debug.
	local function apply(w, cond, button)
		unclip(w)
		w.a:SetAlpha(1)
		if not cond then return end
		local how
		if cond.kind == "share" then
			local share, cur, mx = readShare(cond.unit, cond.power)
			if share then
				w.a:SetAlpha(((share < cond.cut) == cond.below) and 1 or 0)
				how = "plain"
			else
				local k = useCurves() and cutCurve(cond.cut, cond.below)
				local fn = cond.power and UnitPowerPercent or UnitHealthPercent
				if k and fn then
					local ok, v
					if cond.power then ok, v = pcall(fn, cond.unit, cond.power, false, k)
					else ok, v = pcall(fn, cond.unit, false, k) end
					if ok and v ~= nil and pcall(w.a.SetAlpha, w.a, v) then how = "curve" end
				end
				if not how and cur ~= nil and mx ~= nil then
					w.a:SetAlpha(1)
					local okM = pcall(w.bar.SetMinMaxValues, w.bar, 0, mx)
					local okV = pcall(w.bar.SetValue, w.bar, cur)
					if okM and okV then
						aimGate(w.bar, button, cond.cut)
						clipTo(w, cond.below)
						how = "gate"
					end
				end
				if not how then w.a:SetAlpha(cond.fallback or 0) how = "unknown" end
			end
		elseif cond.kind == "bool" then
			local v = cond.v
			if not isSecret(v) then
				w.a:SetAlpha(v and cond.yes or cond.no)
				how = "plain"
			elseif useCurves() and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
				local ok, a = pcall(C_CurveUtil.EvaluateColorValueFromBoolean, v, cond.yes, cond.no)
				if ok and a ~= nil and pcall(w.a.SetAlpha, w.a, a) then how = "curve" end
			end
			if not how then w.a:SetAlpha(cond.fallback or 0) how = "unknown" end
		elseif cond.kind == "threat" then
			local pts = cond.points
			local st = UnitThreatSituation and safe(UnitThreatSituation, "player", cond.unit or "target")
			if not isSecret(st) then
				w.a:SetAlpha(pts[(type(st) == "number" and st or 0) + 1] or pts[1]) -- (not on its list: as 0)
				how = st and "plain" or "plain (not on its list)"
			else
				local k = useCurves() and curve("threat" .. cond.key,
					{ { 0, pts[1] }, { 1, pts[2] }, { 2, pts[3] }, { 3, pts[4] } })
				if k then
					local ok, v = pcall(k.Evaluate, k, st)
					if ok and v ~= nil and pcall(w.a.SetAlpha, w.a, v) then how = "curve" end
				end
				if not how then w.a:SetAlpha(cond.fallback or 1) how = "unknown" end
			end
		end
		if cond.label then hows[cond.label] = how end
	end

	local function show(id, color, button, conds)
		if not button then return end
		local s = slot(id, color)
		for i = 1, DEPTH do apply(s.wraps[i], conds and conds[i], button) end
		placeGlow(s.glow, button)
		used[id] = true
	end

	hunterHide = function()
		for _, s in pairs(slots) do s.glow:Hide() s.glow.pulse:Stop() end
	end

	local function hideUnused()
		for id, s in pairs(slots) do
			if not used[id] then s.glow:Hide() s.glow.pulse:Stop() end
		end
	end

	-- The pet bar's Attack button.
	local function petAttackButton()
		for i = 1, (NUM_PET_ACTION_SLOTS or 10) do
			local name = plain(safe(GetPetActionInfo, i))
			if name == "PET_ACTION_ATTACK" then
				local b = _G["PetActionButton" .. i]
				if b and b:IsVisible() then return b end
			end
		end
		return nil
	end

	-- Mobs fighting you or your pet (nameplates).
	local function foesOnUs()
		local n = 0
		for _, unit in ipairs(ns.Plates and ns.Plates.units() or {}) do
			if plain(UnitCanAttack("player", unit)) and plain(UnitAffectingCombat(unit)) then
				local mine = UnitThreatSituation and safe(UnitThreatSituation, "player", unit)
				local pets = UnitThreatSituation and safe(UnitThreatSituation, "pet", unit)
				local onMe = plain(UnitIsUnit(unit .. "target", "player"))
				local onPet = plain(UnitIsUnit(unit .. "target", "pet"))
				local hidden = isSecret(mine) or isSecret(pets)
				if hidden or plain(mine) ~= nil or plain(pets) ~= nil or onMe or onPet then n = n + 1 end
			end
		end
		return math.max(1, n)
	end

	-- Danger the addon can see for itself: adds, an elite on your own, a much higher level, a boss.
	local function plainDanger(foes, solo)
		local why = {}
		local class = plain(UnitClassification("target"))
		local mine, theirs = plain(UnitLevel("player")), plain(UnitLevel("target"))
		if foes >= (solo and 2 or 3) then why[#why + 1] = foes .. " mobs on you" end
		if solo and (class == "elite" or class == "rareelite") then why[#why + 1] = "elite" end
		if class == "worldboss" or theirs == -1 then why[#why + 1] = "boss"
		elseif mine and theirs and theirs >= mine + 3 then why[#why + 1] = "level " .. theirs end
		return #why > 0, why
	end

	-- Mobs Multi-Shot could hit besides your target: up to 3 fighting nameplates (on your own,
	-- only ones fighting you or your pet; in a group, any in a fight).
	local function otherFoes(solo)
		local out = {}
		for _, unit in ipairs(ns.Plates and ns.Plates.units() or {}) do
			if #out >= 3 then break end
			if plain(UnitCanAttack("player", unit)) and plain(UnitAffectingCombat(unit))
				and plain(UnitIsDead(unit)) ~= true and plain(UnitIsUnit(unit, "target")) ~= true then
				local ours = not solo
				if solo then
					local mine = UnitThreatSituation and safe(UnitThreatSituation, "player", unit)
					local pets = UnitThreatSituation and safe(UnitThreatSituation, "pet", unit)
					ours = isSecret(mine) or isSecret(pets) or plain(mine) ~= nil or plain(pets) ~= nil
						or plain(UnitIsUnit(unit .. "target", "player")) or plain(UnitIsUnit(unit .. "target", "pet"))
				end
				if ours then out[#out + 1] = unit end
			end
		end
		return out
	end

	-- A mob not fighting yet standing by your target (not a critter): Multi-Shot could hit it and
	-- pull it. The game gives no mob positions, so "by your target" is read from the nameplates:
	-- its plate within about 1.5 plate widths of your target's plate on screen (and in reach of
	-- your shots). It used to be any such mob within 35 yards of you - nearly always one out in
	-- the world, so Multi-Shot hardly ever glowed. No target plate to compare with: not blocked.
	local NEAR_PLATES = 1.5
	local function plateSpot(unit)
		local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and safe(C_NamePlate.GetNamePlateForUnit, unit)
		if not plate or isSecret(plate) then return nil end
		local x, y = safe(plate.GetCenter, plate)
		local sc, w = safe(plate.GetEffectiveScale, plate), safe(plate.GetWidth, plate)
		x, y, sc, w = plain(x), plain(y), plain(sc), plain(w)
		if not (x and y and sc and w) then return nil end
		return x * sc, y * sc, w * sc
	end
	local function unpulledByTarget()
		local tx, ty, tw = plateSpot("target")
		if not tx then return nil, "no target plate (not checked)" end
		local e = byName["Multi-Shot"] or byName["Arcane Shot"]
		for _, unit in ipairs(ns.Plates and ns.Plates.units() or {}) do
			if plain(UnitCanAttack("player", unit)) and plain(UnitAffectingCombat(unit)) == false
				and plain(UnitIsDead(unit)) ~= true and plain(UnitCreatureType(unit)) ~= "Critter"
				and plain(UnitIsUnit(unit, "target")) ~= true then
				local x, y = plateSpot(unit)
				local close = x and math.sqrt((x - tx) ^ 2 + (y - ty) ^ 2) <= tw * NEAR_PLATES
				local reach = true
				if close and e and C_Spell and C_Spell.IsSpellInRange then
					reach = verdict(safe(C_Spell.IsSpellInRange, e.id, unit)) ~= false
				end
				if close and reach then return plain(UnitName(unit)) or "a mob", "nameplates" end
			end
		end
		return nil, "nameplates"
	end

	local info = {}
	local function share(unit, cut, below, label, ptype)
		return { kind = "share", unit = unit, power = ptype, cut = cut, below = below, label = label }
	end

	hunterUpdate = function(hostile)
		wipe(used)
		wipe(info)
		local now = GetTime()
		local solo = not plain(IsInGroup and IsInGroup())
		local petUp = plain(UnitExists("pet")) and plain(UnitIsDeadOrGhost("pet")) == false or false
		local fighting = InCombatLockdown()
		local ttk = hostile and timeToKill() or 0
		info.solo, info.petUp, info.ttk = solo, petUp, ttk

		-- Mend Pet (green): in a fight or between them.
		local mend = byName["Mend Pet"]
		local channel = UnitChannelInfo and plain(UnitChannelInfo("player"))
		local mendCut = fighting and 0.4 or 0.7
		local mendOn = petUp and mend and not channel and ready("Mend Pet")
			and not (fighting and hostile and ttk < 5) and true or false
		if mendOn then show("mend", GREEN, mend.button, { share("pet", mendCut, true, "pet health") }) end
		info.mend = mendOn and ("when your pet is under " .. mendCut * 100 .. "%")
			or (not mend and "not on your bars" or "not now")
		if not hostile then hideUnused() return end

		-- The pet first: its Attack button until it's on your target.
		local attack = petUp and petAttackButton()
		if attack then
			show("petattack", BLUE, attack, { { kind = "bool", v = UnitIsUnit("pettarget", "target"), yes = 0, no = 1,
				fallback = 0, label = "pet on your target" } })
		end

		-- Who holds the mobs: your pet (on your own, or Growl on in a group) or your group's tank
		-- (in a group with Growl off, or no pet). Threat is weighed against whoever it is.
		local growl = petUp and growlOn()
		local petTanks = petUp and (solo or growl == true) or false
		local groupTank = not solo and not petTanks
		local tanked = petTanks or groupTank
		info.tank = petTanks and "your pet" or (groupTank and "your group's tank" .. (petUp and " (Growl off)" or "") or "nobody (no pet)")

		-- With a tank: wait until the mob fights, then 2 seconds of stings only.
		local guid = plain(UnitGUID("target"))
		local eng = guid and engagedAt[guid]
		local waiting = tanked and plain(UnitAffectingCombat("target")) == false
		local headStart = tanked and eng and now - eng < 2 or false
		info.waiting, info.headStart = waiting, headStart

		local fd = byName["Feign Death"]
		local fdReady = tanked and fd and ready("Feign Death") and true or false

		-- Damage (blue): one pick per mana band, each shown only in its band.
		if not waiting then
			-- On your own and safe (your pet holds it, nothing dangerous), mana is for the next
			-- pull too: thrifty from 70%, dry under 35%. And once your mana is coming back (no
			-- mana spent for 5 seconds), under 70% nothing that costs mana unless the fight has
			-- over 12 seconds left: your pet and Auto Shot finish it, and the next drink is shorter.
			local safeSolo = solo and petTanks and not plainDanger(foesOnUs(), solo)
			local regen = now - lastManaCast >= 5
			local hold = safeSolo and regen and fighting and ttk < 12
			local hi, lo
			if solo then hi, lo = safeSolo and 0.7 or 0.55, safeSolo and 0.35 or 0.25 else hi, lo = 0.3, 0.1 end
			info.safeSolo, info.regen, info.hold = safeSolo, regen, hold
			local free = choose({ mode = "free", headStart = headStart })
			local thrifty = choose({ mode = hold and "dry" or "thrifty", headStart = headStart })
			local dry = choose({ mode = "dry", headStart = headStart })
			info.picks = { free = free, thrifty = thrifty, dry = dry, hi = hi, lo = lo }
			local extra = {}
			-- (Mend Pet's turn: the shots wait)
			if mendOn and fighting then extra[#extra + 1] = share("pet", mendCut, false, "pet health") end
			-- (threat 1 = you're above the tank but it hasn't turned yet: ease off. 2-3 = it's on you:
			-- Feign Death's turn when it's ready, else keep shooting.)
			if tanked then
				extra[#extra + 1] = { kind = "threat", key = fdReady and "easeFD" or "ease",
					points = { 1, 0, fdReady and 0 or 1, fdReady and 0 or 1 }, fallback = 1, label = "threat" }
			end
			local function joined(conds, last)
				local all = {}
				for _, c in ipairs(conds) do all[#all + 1] = c end
				for _, c in ipairs(extra) do all[#all + 1] = c end
				if last then all[#all + 1] = last end
				return all
			end
			local others = otherFoes(solo)
			local unpulled, plateCheck = unpulledByTarget()
			info.plateCheck = plateCheck
			info.others, info.unpulled = #others, unpulled
			local function place(id, pick, conds, mode, noAoe)
				if not pick or not byName[pick] then return end
				if not isDot[pick] then show(id, BLUE, byName[pick].button, joined(conds)) return end
				-- a sting: only while the mob has some life in it; else the best without one
				show(id, BLUE, byName[pick].button, joined(conds, share("target", DOT_CUT, false, "target health")))
				local alt = choose({ mode = mode, headStart = headStart, noDots = true, noAoe = noAoe })
				info.noSting = alt
				if alt and byName[alt] then
					show(id .. "low", BLUE, byName[alt].button, joined(conds, share("target", DOT_CUT, true, "target health")))
				end
			end
			local function band(id, pick, conds, mode)
				if not pick or not byName[pick] then return end
				if not isAoe[pick] then place(id, pick, conds, mode) return end
				-- Multi-Shot hits the mobs around your target. Not with a mob that isn't fighting in
				-- reach (it could pull it); with others fighting, only while you're safely under
				-- the tank on every one of them (threat 0, read by the game) - else the best shot
				-- that hits one mob.
				local alt = choose({ mode = mode, headStart = headStart, noAoe = true })
				info.noMulti = alt
				if unpulled then place(id, alt, conds, mode, true) return end
				if #others == 0 or not tanked then place(id, pick, conds, mode) return end
				local held = {}
				for _, c in ipairs(conds) do held[#held + 1] = c end
				for _, unit in ipairs(others) do
					held[#held + 1] = { kind = "threat", unit = unit, key = "held", points = { 1, 0, 0, 0 }, fallback = 0,
						label = "threat on the other mobs" }
				end
				place(id, pick, held, mode)
				-- (any one not held: the single-target shot, one overlay per mob)
				for i, unit in ipairs(others) do
					local c2 = {}
					for _, c in ipairs(conds) do c2[#c2 + 1] = c end
					c2[#c2 + 1] = { kind = "threat", unit = unit, key = "loose", points = { 0, 1, 1, 1 }, fallback = 1,
						label = "threat on the other mobs" }
					place(id .. "loose" .. i, alt, c2, mode, true)
				end
			end
			if free == thrifty and thrifty == dry then
				band("dmg", free, {}, "free")
			elseif free == thrifty then
				band("dmg1", free, { share("player", lo, false, "mana", MANA) }, "free")
				band("dmg3", dry, { share("player", lo, true, "mana", MANA) }, "dry")
			else
				band("dmg1", free, { share("player", hi, false, "mana", MANA) }, "free")
				band("dmg2", thrifty, { share("player", lo, false, "mana", MANA), share("player", hi, true, "mana", MANA) }, hold and "dry" or "thrifty")
				band("dmg3", dry, { share("player", lo, true, "mana", MANA) }, "dry")
			end
		end

		-- Feign Death (amber) when the mob turns on you.
		if fdReady and fighting then
			show("fd", AMBER, fd.button, { { kind = "threat", key = "onMe", points = { 0, 0, 1, 1 }, fallback = 0,
				label = "threat" } })
		end

		-- Danger (red): the big cooldowns.
		if fighting and ttk >= 4 then
			local danger, why = plainDanger(foesOnUs(), solo)
			info.danger = danger and table.concat(why, ", ") or "none seen (your pet's and your health still decide)"
			for _, name in ipairs(BIG) do
				local e = byName[name]
				if e and ready(name) and (petUp or not NEEDS_PET[name]) then
					if danger then
						show("big:" .. name, RED, e.button, {})
					else
						if petUp then show("bigPet:" .. name, RED, e.button, { share("pet", 0.3, true, "pet health") }) end
						show("bigMe:" .. name, RED, e.button, { share("player", 0.4, true, "your health") })
					end
				end
			end
			local det = byName["Deterrence"]
			if det and ready("Deterrence") then
				show("det", RED, det.button, { share("player", 0.5, true, "your health"),
					{ kind = "bool", v = UnitIsUnit("targettarget", "player"), yes = 1, no = 0, fallback = 0, label = "mob on you" } })
			end
		end
		hideUnused()
	end

	-- What the hunter part sees, for /zyde rotationdebug.
	hunterDebug = function(P)
		local p = info.picks
		print(P .. ("hunter: %s, pet %s, tank: %s, fight left ~%.0fs, curves %s"):format(info.solo and "on your own" or "in a group",
			info.petUp and "up" or "not up", tostring(info.tank or "-"), info.ttk or 0, useCurves() and "on" or "off (gates only)"))
		if info.waiting then
			print(P .. "  waiting for the mob to fight your pet (no damage glow yet)")
		elseif p then
			print(P .. ("  mana: %s, %s%s"):format(info.safeSolo and "on your own and safe (careful bands)" or "normal bands",
				info.regen and ("coming back (nothing cast for " .. math.floor(GetTime() - lastManaCast) .. "s)") or "not coming back yet (cast in the last 5s)",
				info.hold and " - holding it: under 70% only free hits while the fight has under 12s left" or ""))
			print(P .. ("  damage: %s above %d%% mana, %s %d-%d%%, %s under %d%%%s"):format(tostring(p.free), p.hi * 100,
				tostring(p.thrifty), p.lo * 100, p.hi * 100, tostring(p.dry), p.lo * 100,
				info.headStart and "   (pet's head start: stings only)" or ""))
			if info.noSting then print(P .. "  under " .. DOT_CUT * 100 .. "% target health, instead of the sting: " .. info.noSting) end
			if info.noMulti then
				print(P .. ("  Multi-Shot: %d other mob(s) fighting%s; when one isn't safely held: %s"):format(info.others or 0,
					info.unpulled and (", but " .. info.unpulled .. " isn't fighting and stands by your target (no Multi-Shot)")
						or (" (mobs by your target: " .. tostring(info.plateCheck) .. ")"),
					tostring(info.noMulti)))
			end
		end
		local guid = plain(UnitGUID("target"))
		local list = guid and dots[guid]
		if list then
			local parts = {}
			for name, ends in pairs(list) do parts[#parts + 1] = ("%s %.0fs"):format(name, math.max(0, ends - GetTime())) end
			print(P .. "  ticking on your target: " .. (#parts > 0 and table.concat(parts, ", ") or "-"))
		end
		print(P .. "  Mend Pet: " .. tostring(info.mend) .. "   danger: " .. tostring(info.danger or "not in a fight"))
		local parts = {}
		for label, how in pairs(hows) do parts[#parts + 1] = label .. " " .. tostring(how) end
		table.sort(parts)
		print(P .. "  checks read by: " .. (#parts > 0 and table.concat(parts, ", ") or "-"))
		print(P .. ("  game has: CreateCurve %s, step curves %s, UnitHealthPercent %s, UnitPowerPercent %s, bool->value %s"):format(
			tostring(C_CurveUtil and C_CurveUtil.CreateCurve ~= nil), tostring(Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step ~= nil),
			tostring(UnitHealthPercent ~= nil), tostring(UnitPowerPercent ~= nil),
			tostring(C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean ~= nil)))
		-- The raw answers (hidden ones may not print).
		for _, q in ipairs({
			{ "pet health %", function() return UnitHealthPercent("pet") end },
			{ "your health %", function() return UnitHealthPercent("player") end },
			{ "your mana %", function() return UnitPowerPercent("player", MANA) end },
			{ "pet under 40% (curve)", function() return UnitHealthPercent("pet", false, cutCurve(0.4, true)) end },
			{ "threat", function() return UnitThreatSituation("player", "target") end },
		}) do
			local ok, v = pcall(q[2])
			local shown = ok and pcall(print, P .. "  " .. q[1] .. ":", v)
			if not shown then print(P .. "  " .. q[1] .. ": " .. (ok and "hidden" or "not available")) end
		end
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
	"SPELLS_CHANGED", "PLAYER_ENTERING_WORLD", "UPDATE_SHAPESHIFT_FORM", "PLAYER_REGEN_DISABLED",
	"PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED", "PLAYER_EQUIPMENT_CHANGED" }) do
	pcall(ev.RegisterEvent, ev, e)
end
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SUCCEEDED", "player")
pcall(ev.RegisterUnitEvent, ev, "UNIT_HEALTH", "target")
local rescanQueued = false
ev:SetScript("OnEvent", function(_, event, unit, _, spellID)
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		local name = spellName(plain(spellID) or 0)
		if name then
			local now = GetTime()
			lastCast[name] = now
			local tg = plain(UnitGUID("target"))
			if name:find("^Seal of") then sealName, sealUntil = name, now + SEAL_TIME end
			if name == "Judgement" and tg and sealName == CRUSADER and sealUntil > now then crusaderOn[tg] = now + 10 end
			local entry = byName[name]
			local f = entry and facts[entry.id]
			if f and f.cost and f.cost > 0 then lastManaCast = now end
			if tg and f and f.dotDur and f.dotDur > 0 then
				dots[tg] = dots[tg] or {}
				dots[tg][name] = now + f.dotDur
			end
		end
		return
	end
	if event == "UNIT_HEALTH" then feedGates() watchTarget() return end
	if event == "PLAYER_REGEN_DISABLED" then return end
	if event == "PLAYER_REGEN_ENABLED" then
		watchTarget() -- (the last kill)
		wipe(samples)
		-- Leaving combat doesn't end the fight with a mob: Feign Death drops you out while it keeps
		-- fighting your pet. Wiping the notes here made it look fresh, with no sting on it. So only
		-- the run-out ones go: stings that have ended, mobs from over 5 minutes ago.
		local now = GetTime()
		for guid, list in pairs(dots) do
			for name, ends in pairs(list) do
				if ends <= now then list[name] = nil end
			end
			if next(list) == nil then dots[guid] = nil end
		end
		for guid, at in pairs(engagedAt) do
			if now - at > 300 then engagedAt[guid] = nil end
		end
		for guid in pairs(recorded) do
			if not engagedAt[guid] then recorded[guid] = nil end
		end
	end
	if event == "PLAYER_TARGET_CHANGED" then wipe(samples) feedGates() return end
	if event == "SPELLS_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED" then wipe(facts) end
	if rescanQueued then return end
	rescanQueued = true
	C_Timer.After(0.2, function()
		rescanQueued = false
		scanBars()
		-- read the tooltips while it's allowed
		if not InCombatLockdown() then
			for _, e in pairs(byName) do factsOf(e.id) end
		end
	end)
end)

local wait = 0
root:SetScript("OnUpdate", function(_, dt)
	wait = wait + dt
	if wait < 0.1 then return end
	wait = 0
	if on() then watchTarget() end
	update()
end)

ns.OnFeatureChanged(function(key) if key == "rotation" then update() end end)

-- /zyde rotationdebug: what it sees and why it picked what it did.
function ns.RotationDebug()
	local P = "|cff66ccffZyde_Forever|r: "
	if not LIST then print(P .. "no ability list for your class yet") return end
	local pick, gatedPick, threshold = choose()
	print(P .. ("pick: %s%s   enemies: %d   time left: %.0fs   target health: %s   power: %s   combo: %s"):format(
		tostring(pick), gatedPick and (" / under " .. math.floor(threshold * 100) .. "%: " .. gatedPick) or "",
		enemyCount(), timeToKill(), targetShare() and (math.floor(targetShare() * 100) .. "%") or "hidden",
		tostring(power()), tostring(comboPoints())))
	if playerClass == "HUNTER" and hunterDebug then hunterDebug(P) end
	local ks, parts = killStats(), {}
	for _, kind in ipairs({ "normal", "elite", "boss" }) do
		local s = ks[kind]
		parts[#parts + 1] = kind .. " " .. (s and ("%.0fs (%d kills)"):format(s.mean, s.n) or "not learned yet")
	end
	local guid = plain(UnitGUID("target"))
	print(P .. "your kill times: " .. table.concat(parts, ", ") .. ("   on this mob for %s"):format(
		guid and engagedAt[guid] and ("%.0fs"):format(GetTime() - engagedAt[guid]) or "-"))
	if playerClass == "PALADIN" then
		local seal, left = currentSeal()
		local tg = plain(UnitGUID("target"))
		print(P .. ("seal: %s%s   damage seal: %s   Crusader judged on target: %s"):format(tostring(seal),
			left and (" (%.0fs left)"):format(left) or "", tostring(mainSeal()),
			tostring(tg and crusaderOn[tg] and crusaderOn[tg] > GetTime() or false)))
	end
	for _, spell in ipairs(LIST) do
		local e = byName[spell.name]
		if e then
			local f = facts[e.id]
			print(("  %s: %s; range: game says %s, counted %s"):format(spell.name,
				f and ("hit %.0f, dot %.0f/%ss, cd %ss, cast %ss, cost %s"):format(
				f.direct, f.dot, f.dotDur, f.cd, f.cast, f.cost) or "no tooltip numbers",
				tostring(rangeOf(e)), inRange(e, spell) and "in reach" or "OUT of reach"))
		end
	end
end
