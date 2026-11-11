-- Score: the engine. Values an item for your spec and level, and compares it with what you wear
-- in the same slot. Hit is valued against your current hit and the cap; everything else is
-- weight x amount. All values are in AP-equivalents (see Config.lua).
local _, zyde = ...
zyde.GA = zyde.GA or {}
local ns = zyde.GA

local Score = {}
ns.Score = Score

local C = ns.Config

-- Equip location -> the slot(s) it can go in. Rings and trinkets have two.
Score.SLOTS_BY_LOC = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
	INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
	INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
	INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
	INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
}

Score.SLOT_NAMES = {
	[1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist", [7] = "Legs",
	[8] = "Feet", [9] = "Wrist", [10] = "Hands", [11] = "Ring 1", [12] = "Ring 2",
	[13] = "Trinket 1", [14] = "Trinket 2", [15] = "Back", [16] = "Main hand", [17] = "Off hand",
	[18] = "Ranged",
}

-- Which weapon weight an item uses, from where it's worn.
function Score.dpsKey(info, slot)
	local loc = info.equipLoc
	if loc == "INVTYPE_2HWEAPON" then return "TwoHandDPS" end
	if loc == "INVTYPE_RANGED" or loc == "INVTYPE_RANGEDRIGHT" or loc == "INVTYPE_THROWN" then return "RangedDPS" end
	if slot == 17 or loc == "INVTYPE_WEAPONOFFHAND" then return "OffHandDPS" end
	if loc == "INVTYPE_WEAPON" or loc == "INVTYPE_WEAPONMAINHAND" then return "MainHandDPS" end
end

local SPEED_KEY = { TwoHandDPS = "TwoHandSpeed", MainHandDPS = "MainHandSpeed", RangedDPS = "RangedSpeed" }

-- Stats weighted directly (one point x weight).
local PLAIN = { "Strength", "Agility", "Stamina", "Intellect", "Spirit", "AttackPower", "RangedAttackPower",
	"Armor", "ExpertiseRating", "WeaponSkill", "Defense", "Dodge", "Parry", "Block", "BlockValue" }

-- The special-items entry for this item and profile, or nil.
local function specialFor(itemID, ctx)
	local sp = C.special and C.special[itemID]
	if type(sp) ~= "table" then return nil end
	return sp[ctx.profileKey] or sp.all, sp.note
end

-- Breaks an item into value parts, NOT counting hit (hit depends on the cap; see Score.hitValue).
-- Returns parts (list of { label, amount, value }), their total, and the item's hit in %.
function Score.parts(info, slot, ctx)
	local w, s = ctx.weights, info.stats
	local parts, total = {}, 0
	local function add(label, amount, weight)
		if amount and amount ~= 0 and weight and weight ~= 0 then
			local v = amount * weight
			parts[#parts + 1] = { label = label, amount = amount, value = v }
			total = total + v
		end
	end
	for _, k in ipairs(PLAIN) do add(k, s[k], w[k]) end

	local critPct = ((s.CritRating or 0) + (s[ctx.critSplitKey] or 0)) / ctx.critPer + (s.CritPercent or 0)
	add("Crit %", critPct, w.CritPercent)
	local hitPct = ((s.HitRating or 0) + (s[ctx.hitSplitKey] or 0)) / ctx.hitPer + (s.HitPercent or 0)

	local dpsKey = Score.dpsKey(info, slot)
	if dpsKey then
		add(dpsKey, s.DPS, w[dpsKey])
		local speedKey = SPEED_KEY[dpsKey]
		local ref = speedKey and ctx.profile.speedRef and ctx.profile.speedRef[speedKey]
		if ref and info.speed and (w[dpsKey] or 0) ~= 0 then
			add(("Speed %.2f vs %.1f"):format(info.speed, ref), info.speed - ref, w[speedKey])
		end
	end

	local sp, note = specialFor(info.itemID, ctx)
	if sp then
		for k, amount in pairs(sp) do
			if k == "value" then
				add(note or "special effect", 1, amount)
			elseif k == "HitPercent" then
				hitPct = hitPct + amount
			else
				add((note and (k .. " (" .. note .. ")")) or k, amount, w[k])
			end
		end
	end
	return parts, total, hitPct
end

local function overlap(a, b, lo, hi)
	return math.max(0, math.min(b, hi) - math.max(a, lo))
end

-- Value of going from `from`% to `to`% hit: full weight up to the cap, the past-cap weight after.
function Score.hitValue(from, to, ctx)
	if to < from then return -Score.hitValue(to, from, ctx) end
	local w, past, cap = ctx.weights.HitPercent or 0, ctx.weights.HitPercentPastCap or 0, ctx.hitCap
	return w * overlap(from, to, -math.huge, cap) + past * overlap(from, to, cap, math.huge)
end

-- Value of one set bonus table.
local function bonusValue(bonus, ctx)
	local v = 0
	for k, amount in pairs(bonus) do
		if k == "value" then v = v + amount else v = v + amount * (ctx.weights[k] or 0) end
	end
	return v
end

-- Total set-bonus value for a set of equipped item IDs ({ [id] = true }).
function Score.setValue(ids, ctx)
	local total = 0
	for _, set in pairs(C.sets or {}) do
		local have = 0
		for _, id in ipairs(set.items or {}) do
			if ids[id] then have = have + 1 end
		end
		if have > 0 then
			for pieces, bonus in pairs(set.bonuses or {}) do
				if have >= pieces then
					total = total + bonusValue(bonus, ctx)
				elseif have == pieces - 1 then
					total = total + bonusValue(bonus, ctx) * (C.setNearlyFactor or 0)
				end
			end
		end
	end
	return total
end

-- Score of everything you wear: the base that "+N%" is measured against.
function Score.kitScore(ctx)
	local total = 0
	for slot, info in pairs(ctx.equipped) do
		local _, lin = Score.parts(info, slot, ctx)
		total = total + lin
	end
	total = total + Score.hitValue(ctx.hitOther, ctx.hitHave, ctx) + Score.setValue(ctx.equippedIDs, ctx)
	return total
end

-- true/false if you know a spell, nil if the game won't say.
function Score.knowsSpell(id)
	for _, fn in ipairs({ IsPlayerSpell, IsSpellKnown, C_SpellBook and C_SpellBook.IsSpellKnown }) do
		if type(fn) == "function" then
			local known = ns.safe(fn, id)
			if known ~= nil then return known and true or false end
		end
	end
	return nil
end

local ARMOR_NAMES = { [1] = "cloth", [2] = "leather", [3] = "mail", [4] = "plate", [6] = "shields" }

-- Can your class use it? Returns "yes", "no" + reason, or "later" + level + reason.
function Score.usable(info, ctx)
	local gear = C.classGear[ctx.class]
	local need, why = 0, nil
	if gear and info.classID == 2 then
		if not gear.weapons[info.subclassID] then return "no", "your class can't use this weapon type" end
	elseif gear and info.classID == 4 then
		local sub = info.subclassID
		if sub and sub ~= 0 and not gear.armor[sub] then
			return "no", "your class can't wear this armour type"
		end
		local spell = gear.armorSpells and gear.armorSpells[sub]
		local from = gear.armorFromLevel and gear.armorFromLevel[sub]
		local known = spell and Score.knowsSpell(spell)
		local name = ARMOR_NAMES[sub] or "this armour"
		if known == false then
			if from and from > ctx.level then
				need, why = from, ("you can wear %s from level %d"):format(name, from)
			else
				need, why = ctx.level, ("train %s at your class trainer first"):format(name)
			end
		elseif known == nil and from and ctx.level < from then
			need, why = from, ("you can wear %s from level %d"):format(name, from)
		end
	end
	if (info.reqLevel or 0) > ctx.level and info.reqLevel > need then
		need, why = info.reqLevel, ("requires level %d"):format(info.reqLevel)
	end
	if why then return "later", need, why end
	return "yes"
end

-- Puts `info` in `slot` and returns the result of that swap.
local function swap(info, slot, ctx)
	local eq = ctx.equipped
	local removed = { [slot] = true }
	local notes = {}
	if info.equipLoc == "INVTYPE_2HWEAPON" then
		removed[17] = true
	elseif slot == 16 and eq[16] and eq[16].equipLoc == "INVTYPE_2HWEAPON" then
		notes[#notes + 1] = "needs an off-hand too"
	elseif slot == 17 and eq[16] and eq[16].equipLoc == "INVTYPE_2HWEAPON" then
		return { kind = "n/a", slot = slot, delta = -math.huge, notes = { "you use a two-hander" } }
	end

	local oldLinear, oldHit, vs = 0, 0, {}
	local idsAfter = {}
	for id in pairs(ctx.equippedIDs) do idsAfter[id] = true end
	for s in pairs(removed) do
		local e = eq[s]
		if e then
			local _, lin, hit = Score.parts(e, s, ctx)
			oldLinear, oldHit = oldLinear + lin, oldHit + hit
			vs[#vs + 1] = e.link
			idsAfter[e.itemID] = nil
		end
	end
	idsAfter[info.itemID] = true

	local parts, newLinear, newHit = Score.parts(info, slot, ctx)
	local base = ctx.hitHave - oldHit
	local hitDelta = Score.hitValue(base + oldHit, base + newHit, ctx)
	local setDelta = Score.setValue(idsAfter, ctx) - Score.setValue(ctx.equippedIDs, ctx)
	local delta = (newLinear - oldLinear) + hitDelta + setDelta

	local before, after, cap = ctx.hitHave, base + newHit, ctx.hitCap
	if before < cap - 0.01 and after >= cap - 0.01 then
		notes[#notes + 1] = "reaches hit cap"
	elseif before >= cap - 0.01 and after < cap - 0.01 then
		notes[#notes + 1] = ("drops below hit cap (%.1f%% of %.1f%%)"):format(after, cap)
	elseif newHit > 0 and after > cap + 0.05 then
		notes[#notes + 1] = ("%.1f%% hit over cap"):format(after - cap)
	end
	if setDelta > 0.01 then notes[#notes + 1] = "set bonus" end

	return {
		slot = slot, vs = vs, delta = delta, parts = parts,
		newLinear = newLinear, oldLinear = oldLinear, hitDelta = hitDelta, setDelta = setDelta,
		newHit = newHit, oldHit = oldHit, hitBefore = before, hitAfter = after, hitCap = cap,
		notes = notes,
	}
end

-- Compares an item with what you wear. Returns a result table:
--   kind  "upgrade", "downgrade", "same", "future" (upgrade you can wear within a few levels),
--         "too early" (can't wear it for a while: no upgrade claim), "equipped", "unusable", "n/a",
--         "not gear", "loading" or "unsupported"
--   pct   change in your whole-kit score, in %      delta  the same in AP-equivalents
--   slot, vs (list of replaced item links), notes (list of short strings), info, parts, ...
--   later the level you can use it from (nil if usable now)
function Score.compare(link, ctx)
	ctx = ctx or ns.Player.context()
	if not ctx.profile then return { kind = "unsupported", notes = { ctx.reason } } end
	local info, why = ns.Stats.read(link)
	if not info then return { kind = (why == "loading") and "loading" or "not gear", notes = {} } end
	local slots = Score.SLOTS_BY_LOC[info.equipLoc]
	if not slots then return { kind = "not gear", info = info, notes = {} } end

	for _, slot in ipairs(slots) do
		local e = ctx.equipped[slot]
		if e and e.link == info.link then return { kind = "equipped", info = info, slot = slot, notes = {} } end
	end

	local ok, extra, laterWhy = Score.usable(info, ctx)
	if ok == "no" then return { kind = "unusable", info = info, notes = { extra } } end

	local best
	for _, slot in ipairs(slots) do
		local r = swap(info, slot, ctx)
		if not best or r.delta > best.delta then best = r end
	end
	best.info = info
	if best.kind ~= "n/a" then
		best.pct = best.delta / math.max(ctx.kitScore or 0, 1) * 100
		local min = C.minUpgradePct or 0
		if best.pct > min then best.kind = "upgrade"
		elseif best.pct < -min then best.kind = "downgrade"
		else best.kind = "same" end
	end
	if ok == "later" then
		-- Not wearable yet: a "future upgrade" only if it's close; otherwise you'll have outlevelled
		-- it by the time you can wear it, so make no upgrade claim at all.
		best.later = extra
		table.insert(best.notes, 1, laterWhy)
		if extra - ctx.level > (C.futureUpgradeLevels or 0) then
			best.kind = "too early"
		elseif best.kind == "upgrade" then
			best.kind = "future"
		end
	end
	if info.unknown and #info.unknown > 0 then
		best.notes[#best.notes + 1] = "unknown stats: " .. table.concat(info.unknown, ", ")
	end
	if ctx.loading then best.notes[#best.notes + 1] = "some equipped items still loading" end
	return best
end
