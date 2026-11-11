-- Player: who you are (class, spec, level), which weights apply, what you're wearing, and your
-- current hit. Built once and cached until equipment, level, talents or settings change.
local _, zyde = ...
zyde.GA = zyde.GA or {}
local ns = zyde.GA

local Player = {}
ns.Player = Player

local C = ns.Config
local ctx

function Player.invalidate() ctx = nil end

-- Talent trees left to right, as spec names.
Player.TREES = {
	WARRIOR = { "ARMS", "FURY", "PROTECTION" },
	HUNTER = { "BEAST_MASTERY", "MARKSMANSHIP", "SURVIVAL" },
}

-- Points spent in talent tree i, whatever shape this client's GetTalentTabInfo returns:
-- modern Classic (id, name, description, icon, pointsSpent, ...) or old (name, icon, pointsSpent, ...).
function Player.talentTab(i)
	local r = ns.pack(ns.safe(GetTalentTabInfo, i))
	if r.n == 0 then return nil end
	if type(r[1]) == "number" then return r[2], r[5] end
	return r[1], r[3]
end

-- The spec name and how it was found ("GetSpecialization", "talents", or nil + reason).
function Player.detectSpec(class)
	local trees = Player.TREES[class]
	if not trees then return nil, "class not supported" end
	-- Talent points first: Classic-style talents are the real source of truth.
	local best, bestPoints = nil, 0
	local n = ns.safe(GetNumTalentTabs) or 0
	for i = 1, n do
		local _, points = Player.talentTab(i)
		if type(points) == "number" and points > bestPoints then best, bestPoints = i, points end
	end
	if best and trees[best] then return trees[best], "talents" end
	if GetSpecialization then
		local i = ns.safe(GetSpecialization)
		if type(i) == "number" and trees[i] then return trees[i], "GetSpecialization" end
	end
	return nil, "no talent points yet"
end

-- Weights for your level: blended between the profile's two nearest level brackets.
function Player.blend(brackets, level)
	local list = {}
	for _, b in ipairs(brackets) do list[#list + 1] = b end
	table.sort(list, function(a, b) return a.level < b.level end)
	local function copy(w) local t = {} for k, v in pairs(w) do t[k] = v end return t end
	if #list == 0 then return {} end
	if level <= list[1].level then return copy(list[1].weights) end
	if level >= list[#list].level then return copy(list[#list].weights) end
	for i = 1, #list - 1 do
		local a, b = list[i], list[i + 1]
		if level >= a.level and level <= b.level then
			local t = (level - a.level) / (b.level - a.level)
			local out = {}
			for k, v in pairs(a.weights) do out[k] = v end
			for k, v in pairs(b.weights) do
				local from = a.weights[k] or 0
				out[k] = from + (v - from) * t
			end
			for k, v in pairs(a.weights) do
				if b.weights[k] == nil then out[k] = v * (1 - t) end
			end
			return out
		end
	end
	return copy(list[#list].weights)
end

-- Rating per 1% at your level. Asks the game first; falls back to Config.ratings.
function Player.ratingPerPercent(crName, fallback, level)
	local cr = _G[crName]
	if type(cr) == "number" and GetCombatRatingBonusForCombatRatingValue then
		local bonus = ns.safe(GetCombatRatingBonusForCombatRatingValue, cr, 100)
		if type(bonus) == "number" and bonus > 0 then return 100 / bonus, "game" end
	end
	local per = fallback
	if C.ratingScalesWithLevel then per = per * math.max(2, level - 8) / 52 end
	return per, "config"
end

-- Target level gap for the hit cap.
local TARGETS = { same = 0, dungeon = 2, raid = 3 }
Player.TARGETS = TARGETS
function Player.targetGap(level)
	local t = (ns.db and ns.db.target) or C.defaultTarget or "auto"
	if TARGETS[t] then return TARGETS[t], t end
	return (level >= 60) and 3 or 2, "auto"
end

-- Equipment slots we read (4 shirt and 19 tabard are skipped).
Player.SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

-- The scoring context: everything Score needs about you. Returns ctx (ctx.profile is nil when
-- your class has no profile; ctx.reason says why).
function Player.context()
	if ctx then return ctx end
	local c = {}
	c.class = select(2, UnitClass("player"))
	c.level = ns.safe(UnitLevel, "player") or 1

	-- Profile: a manual choice (/ga spec) wins, else the detected spec's profile.
	c.spec, c.specSource = Player.detectSpec(c.class)
	local map = C.specProfiles[c.class]
	local override = ns.db and ns.db.specOverride
	if override and C.profiles[override] then
		c.profileKey, c.profileSource = override, "set by /ga spec"
	elseif map then
		c.profileKey = (c.spec and map[c.spec]) or map.default
		c.profileSource = c.spec and ("detected " .. c.spec .. " from " .. c.specSource)
			or ("no spec found (" .. tostring(c.specSource) .. "), using the default")
	end
	c.profile = c.profileKey and C.profiles[c.profileKey]
	if not c.profile then
		c.reason = "no GearAdvisor profile for " .. tostring(c.class) .. " yet"
		return c   -- not cached: nothing to cache
	end
	c.weights = Player.blend(c.profile.brackets, c.level)

	-- Rating conversions at this level, for the profile's kind of hit and crit.
	local ranged = c.profile.hitKind == "ranged"
	c.hitCR = ranged and "CR_HIT_RANGED" or "CR_HIT_MELEE"
	c.critCR = ranged and "CR_CRIT_RANGED" or "CR_CRIT_MELEE"
	c.hitSplitKey = ranged and "HitRangedRating" or "HitMeleeRating"
	c.critSplitKey = ranged and "CritRangedRating" or "CritMeleeRating"
	c.hitPer, c.hitPerSource = Player.ratingPerPercent(c.hitCR, C.ratings.hit, c.level)
	c.critPer, c.critPerSource = Player.ratingPerPercent(c.critCR, C.ratings.crit, c.level)

	-- Hit cap.
	c.targetGap, c.targetSetting = Player.targetGap(c.level)
	c.hitCap = C.hitCap[c.targetGap] or 6

	-- What you're wearing.
	c.equipped, c.equippedIDs = {}, {}
	local loading = false
	for _, slot in ipairs(Player.SLOTS) do
		local link = ns.safe(GetInventoryItemLink, "player", slot)
		if link then
			local info, why = ns.Stats.read(link)
			if info then
				c.equipped[slot] = info
				c.equippedIDs[info.itemID] = true
			elseif why == "loading" then
				loading = true
			end
		end
	end

	-- Your hit: rating hit from the game if it will say, else the hit on your gear.
	local gearHit = 0
	for slot, info in pairs(c.equipped) do
		local _, _, hit = ns.Score.parts(info, slot, c)
		gearHit = gearHit + hit
	end
	c.gearHit = gearHit
	local cr = _G[c.hitCR]
	local ratingHit = (type(cr) == "number") and ns.safe(GetCombatRatingBonus, cr) or nil
	if type(ratingHit) == "number" then
		c.hitHave, c.hitSource = ratingHit, "game (rating)"
	else
		c.hitHave, c.hitSource = gearHit, "gear"
	end
	if C.includeHitModifier then
		local mod = ns.safe(GetHitModifier)
		if type(mod) == "number" then c.hitHave = c.hitHave + mod end
	end
	c.hitHave = c.hitHave + (C.extraHitPercent or 0)
	-- Hit that isn't from gear (talents etc.): kept when gear is swapped.
	c.hitOther = c.hitHave - gearHit

	-- Whole-kit score: the base for "+N%".
	c.kitScore = ns.Score.kitScore(c)

	if not loading then ctx = c end
	c.loading = loading
	return c
end
