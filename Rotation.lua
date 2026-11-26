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
		{ name = "Mongoose Bite", kind = "reactive", needUsable = true },
		{ name = "Multi-Shot", kind = "direct", aoe = { 2, 3 } },
		{ name = "Volley", kind = "direct", aoe = { 3, 10 } },
		{ name = "Serpent Sting", kind = "dot" },
		{ name = "Aimed Shot", kind = "direct" },
		{ name = "Arcane Shot", kind = "direct" },
		{ name = "Raptor Strike", kind = "filler" },
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
			local d = text:match("additional (%d+)")
			if d and not (dotDmg and num(d) == f.dot) then f.direct = num(d) or 0 end
		end
	end
	-- Weapon strikes ("weapon damage plus 40"): add your average swing.
	if text:find("weapon damage", 1, true) then
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
local dots = {}     -- [target GUID] = { [spell name] = time it runs out }
local fightStart, samples = nil, {} -- your target's health over time (when the game shows it)

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
			if (threat and threat > 0) or onMe or threat == nil then n = n + 1 end
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
	-- Hidden, or too early to tell: a guess from the mob's type, less the time already spent.
	local class = plain(UnitClassification("target"))
	local base = (class == "elite" or class == "rareelite") and 45 or (class == "worldboss" and 120 or 14)
	local helpers = plain(GetNumGroupMembers and GetNumGroupMembers()) or 0
	if helpers > 1 then base = base / math.min(helpers, 5) * 1.5 end
	local spent = fightStart and (now - fightStart) or 0
	return math.max(3, base - spent)
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

local function inRange(entry)
	local r = C_Spell and C_Spell.IsSpellInRange and safe(C_Spell.IsSpellInRange, entry.id, "target")
	if r == nil and IsSpellInRange then r = safe(IsSpellInRange, spellName(entry.id) or "", "target") end
	r = plain(r)
	if r == false or r == 0 then return false end
	return true
end

---------------------------------------------------------------------------
-- 4. Scoring: damage it will really do / the time it takes
---------------------------------------------------------------------------
local function score(spell, entry, f, ctx, index)
	if spell.form and spell.form ~= ctx.form then return nil end
	if cooldownLeft(spell.name, f) > 0.3 then return nil end
	if not inRange(entry) then return nil end
	local u = usable(entry)
	if u == false then return nil end
	if spell.needUsable and u ~= true then return nil end
	if f and f.cost > 0 and ctx.power and f.cost > ctx.power then return nil end

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
	if dmg <= 0 then dmg = fallback end
	if spell.aoe then
		if ctx.enemies < spell.aoe[1] then return nil end
		dmg = dmg * math.min(ctx.enemies, spell.aoe[2])
	end
	if spell.kind == "reactive" then dmg = dmg * 1.5 end -- (a window that closes: use it)
	return dmg / time
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
local function choose()
	if not LIST then return nil end
	local tg = plain(UnitGUID("target"))
	local ctx = {
		enemies = enemyCount(), ttk = timeToKill(), power = power(), cp = comboPoints(), form = formId(),
		gcd = ENERGY_GCD[playerClass] or ((playerClass == "DRUID" and formId() == 1) and 1 or 1.5),
		dots = tg and dots[tg],
	}
	if playerClass == "PALADIN" then
		local p = paladinPick(ctx, tg)
		if p then return p end
	end
	local share = targetShare()
	local best, bestScore, gated, gatedScore, threshold
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
				local s = score(spell, entry, f, ctx, index)
				if s and (not bestScore or s > bestScore) then best, bestScore = spell.name, s end
			end
		end
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

local function makeGlow(parent)
	local g = CreateFrame("Frame", nil, parent)
	g:EnableMouse(false)
	g.tex = g:CreateTexture(nil, "OVERLAY")
	g.tex:SetTexture(GLOW)
	g.tex:SetBlendMode("ADD")
	g.tex:SetVertexColor(BLUE[1], BLUE[2], BLUE[3])
	g.tex:SetPoint("CENTER")
	g.fill = g:CreateTexture(nil, "ARTWORK")
	g.fill:SetColorTexture(BLUE[1], BLUE[2], BLUE[3], 0.22)
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

local shown = {}
local function hideAll()
	for _, g in ipairs({ plainGlow, aboveGlow, belowGlow }) do g:Hide() g.pulse:Stop() end
end

local function update()
	if not on() or not LIST then hideAll() return end
	local hostile = plain(UnitExists("target")) and plain(UnitCanAttack("player", "target"))
		and not plain(UnitIsDeadOrGhost("target"))
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
			if tg and f and f.dotDur and f.dotDur > 0 then
				dots[tg] = dots[tg] or {}
				dots[tg][name] = now + f.dotDur
			end
		end
		return
	end
	if event == "UNIT_HEALTH" then feedGates() return end
	if event == "PLAYER_REGEN_DISABLED" then fightStart = GetTime() return end
	if event == "PLAYER_REGEN_ENABLED" then
		fightStart = nil
		wipe(dots)
		wipe(samples)
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
			print(("  %s: %s"):format(spell.name, f and ("hit %.0f, dot %.0f/%ss, cd %ss, cast %ss, cost %s"):format(
				f.direct, f.dot, f.dotDur, f.cd, f.cast, f.cost) or "no tooltip numbers"))
		end
	end
end
