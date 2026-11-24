-- Extras: things besides quests that speed up levelling.
--   * optional stops added to a finished route when the detour pays off: class trainer, vendor /
--     repair, setting your hearthstone at the hub ahead, learning flight paths
--   * grinding camps as filler "quests"
--   * quest-log clean-up advice when the log is nearly full
local ADDON, zyde = ...
-- Part of Zyde_Forever since 2026-11-14: LevelPlanner keeps its own private table (zyde.LP) so its
-- names never clash with Zyde's.
zyde.LP = zyde.LP or {}
local ns = zyde.LP

local X = {}
ns.Extras = X

----------------------------------------------------------------------------------------
-- Your state
----------------------------------------------------------------------------------------

-- Bag slots holding grey (junk) items.
function X.JunkSlots()
	local C = C_Container
	if not (C and C.GetContainerNumSlots and C.GetContainerItemInfo) then return 0 end
	local n = 0
	for bag = 0, 4 do
		for slot = 1, (C.GetContainerNumSlots(bag) or 0) do
			local info = C.GetContainerItemInfo(bag, slot)
			if info and info.quality == 0 and not info.hasNoValue then n = n + 1 end
		end
	end
	return n
end

-- Lowest durability of your equipped items, in percent (100 when nothing can break).
function X.MinDurability()
	local low = 100
	for slot = 1, 18 do
		local cur, max = GetInventoryItemDurability(slot)
		if cur and max and max > 0 then low = math.min(low, cur / max * 100) end
	end
	return low
end

-- Does a vendor visit make sense now? Returns needed, urgent, reason.
function X.VendorNeed()
	local cfg = ns.cfg
	if cfg.vendorVisits == false then return false end
	local dur = X.MinDurability()
	if dur <= 10 then return true, true, string.format("gear at %d%%", dur) end
	if dur <= (cfg.repairBelowPercent or 30) then return true, false, string.format("gear at %d%%", dur) end
	local free = ns.QuestSource.FreeBagSlots()
	if free <= (cfg.vendorWhenFreeSlots or 3) and X.JunkSlots() > 0 then
		return true, false, string.format("%d bag slot%s free", free, free == 1 and "" or "s")
	end
	return false
end

-- Has a class trainer visit come due? (atLevel: would it be at that level - a predicted level-up)
function X.TrainerDue(atLevel)
	local cfg = ns.cfg
	if cfg.trainerVisits == false then return false end
	local L = atLevel or ns.playerLevel()
	ns.char.trainedLevel = ns.char.trainedLevel or L -- first time seen: assume you're trained up
	return L >= ns.char.trainedLevel + (cfg.trainerEveryLevels or 2)
end

----------------------------------------------------------------------------------------
-- Optional stops
----------------------------------------------------------------------------------------
local function oneStopQuest(id, kind, name, label, points, work, extra)
	local q = { id = id, name = name, xp = 0, isExtra = true, stops = {} }
	local s = { kind = kind, questId = id, questName = name, key = id, points = points, work = work or 20,
		mobXp = 0, logDelta = 0, bagDelta = 0, order = 1, quest = q, label = label }
	for k, v in pairs(extra or {}) do s[k] = v end
	q.stops[1] = s
	return q
end

local function zoneName(p)
	local info = p and p.map and C_Map.GetMapInfo(p.map)
	return info and info.name or "?"
end

-- The inn at the heart of the quests coming up over the next few hours (a hub), when it beats
-- where your hearthstone is set now. "Coming up" = every quest the planner has to choose from
-- (in your log, available, follow-ups), not just this hour's route; each pick-up / turn-in counts
-- with its quest's XP, so a hub of big quests wins over a few small ones.
local function questStops()
	local out = {}
	local c = ns.candidates
	for _, list in ipairs({ c and c.log or {}, c and c.available or {}, c and c.locked or {} }) do
		for _, q in ipairs(list) do
			for _, st in ipairs(q.stops or {}) do
				if (st.kind == "pickup" or st.kind == "turnin") and st.points and st.points[1] then
					out[#out + 1] = { point = st.points[1], weight = math.max(0.25, (q.xp or 0) / 1000) }
				end
			end
		end
	end
	return out
end

local function hubScore(point, stops, radius)
	local score, count = 0, 0
	for _, st in ipairs(stops) do
		local d = ns.Geo.Distance(point, st.point)
		if d and d <= radius then score, count = score + st.weight, count + 1 end
	end
	return score, count
end

-- Pick-ups and turn-ins in the route ahead - where you'll really be (all known quests reach as far as
-- Mulgore's: Bloodhoof Village won the hub for a character in Brill).
local function routeStops(route)
	local out = {}
	for _, e in ipairs(route or {}) do
		local s = e.stop
		if (s.kind == "pickup" or s.kind == "turnin") and e.point and not s.quest.isExtra then
			out[#out + 1] = { point = e.point, weight = math.max(0.25, (s.quest.xp or 0) / 1000) }
		end
	end
	return out
end

local function hubInn(route)
	local cfg = ns.cfg
	local radius = cfg.hubRadiusYards or 250
	local stops = routeStops(route)
	if #stops < (cfg.hubMinStops or 3) then stops = questStops() end
	if #stops == 0 then X.bindWhy = "no quest stops ahead" return nil end
	-- inns near any upcoming pick-up or turn-in (same lookup the route uses)
	local inns = ns.Places.NearRoute("Innkeeper", stops, radius, 12)
	local best, bestScore, bestCount = nil, 0, 0
	for _, inn in ipairs(inns) do
		ns.Check()
		local score, count = hubScore(inn.point, stops, radius)
		if score > bestScore then best, bestScore, bestCount = inn, score, count end
	end
	if not best then X.bindWhy = string.format("no innkeeper known near the quests ahead (%d inns found)", #inns) return nil end
	if bestCount < (cfg.hubMinStops or 3) then
		X.bindWhy = string.format("%s has only %d quest stops nearby", best.name or "the nearest inn", bestCount)
		return nil
	end
	local bind = ns.TravelLearn.Bind()
	local bp = bind and ns.Geo.PointOnMap(bind.map, bind.x, bind.y)
	if bp then
		local d = ns.Geo.Distance(bp, best.point)
		if d and d < 400 then X.bindWhy = "already set at " .. (bind.name or "that inn") return nil end
		-- only worth a stop when the new hub clearly beats where you're bound
		local here = hubScore(bp, stops, radius)
		if bestScore < here * (cfg.hubBetterBy or 1.5) then
			X.bindWhy = string.format("%s isn't clearly better than %s", best.name or "the hub inn", bind.name or "your home")
			return nil
		end
	end
	X.bindWhy = string.format("suggested: %s (%d quest stops nearby)", best.name or "inn", bestCount)
	return best, bestCount
end

-- Optional stops worth considering for this route: list of {quest, worthMinutes, maxDetourMinutes}.
-- Call inside a job.
function X.OptionalStops(route, ctx)
	local cfg = ns.cfg
	local out = {}
	if #route == 0 or not ctx.start then return out end

	-- class trainer: due now, or due once the level-up the route reaches (ctx.dingLevel) happens; then
	-- the visit has to come after the ding (q.unlockLevel keeps it behind it, see Planner.lua)
	local dueNow = X.TrainerDue()
	if dueNow or (ctx.dingLevel and X.TrainerDue(ctx.dingLevel)) then
		local places = ns.Places.NearRoute("Class Trainer", route, 3000, 6)
		if #places > 0 then
			local pts, ids = {}, {}
			for _, pl in ipairs(places) do pts[#pts + 1] = pl.point ids[#ids + 1] = pl.id end
			local label = string.format("Train new spells (%s, %s)", places[1].name, zoneName(places[1].point))
			if not dueNow then label = label .. string.format(" - you'll be level %d", ctx.dingLevel) end
			local q = oneStopQuest("trainer", "trainer", "Class trainer", label, pts, 60, { npcIds = ids })
			if not dueNow then q.unlockLevel = ctx.dingLevel end
			out[#out + 1] = { quest = q, worth = cfg.trainerValueMinutes or 15, maxDetour = cfg.trainerMaxDetourMinutes or 6 }
		end
	end

	-- vendor / repair
	local need, urgent, why = X.VendorNeed()
	local bagsOnly = false
	if not need and ctx.bagFree then
		-- the route's quest items would fill your bags (it's planned anyway - you can make room): a
		-- quick stop to sell junk, only when a vendor is close to the route (short detour)
		local bag, peak = 0, 0
		for _, e in ipairs(route) do
			bag = bag + (e.stop.bagDelta or 0)
			if bag > peak then peak = bag end
		end
		if peak > ctx.bagFree and X.JunkSlots() > 0 then
			need, bagsOnly, why = true, true, "bags fill up on the way"
		end
	end
	if need then
		local places = ns.Places.NearRoute("Repair", route, 3000, 8)
		if #places > 0 then
			local pts, ids = {}, {}
			for _, pl in ipairs(places) do pts[#pts + 1] = pl.point ids[#ids + 1] = pl.id end
			local q = oneStopQuest("vendor", "vendor", "Vendor",
				string.format(bagsOnly and "Sell junk to make bag room (%s)" or "Sell junk and repair (%s)", why), pts, 60,
				{ bagDelta = -X.JunkSlots(), npcIds = ids })
			local worth = (cfg.vendorValueMinutes or 10) * (urgent and 3 or 1)
			local detour = bagsOnly and (cfg.vendorBagDetourMinutes or 2) or (cfg.vendorMaxDetourMinutes or 5) * (urgent and 2 or 1)
			out[#out + 1] = { quest = q, worth = worth, maxDetour = detour }
		end
	end

	-- hearthstone at the hub ahead
	if cfg.hearthSuggestions ~= false then
		local inn, count = hubInn(route)
		if inn then
			local q = oneStopQuest("bind", "bind", "Hearthstone",
				string.format("Set your hearthstone with %s (%s) - %d upcoming quest stops nearby", inn.name, zoneName(inn.point), count),
				{ inn.point }, 20, { npcIds = { inn.id } })
			out[#out + 1] = { quest = q, worth = cfg.bindValueMinutes or 6, maxDetour = cfg.bindMaxDetourMinutes or 2 }
		end
	end

	-- flight paths you haven't learned
	if cfg.learnFlightPaths ~= false then
		for _, fm in ipairs(ns.QuestSource.FlightMasters()) do
			ns.Check()
			local id = "fp:" .. fm.id
			if fm.point.inst == ctx.start.inst and not ns.Travel.KnownTaxiNear(fm.point, 150) then
				local q = oneStopQuest(id, "flightpath", "Flight path (" .. fm.name .. ")",
					string.format("Learn the flight path at %s (%s)", zoneName(fm.point), fm.name), { fm.point }, 20, { npcIds = { fm.id } })
				out[#out + 1] = { quest = q, worth = cfg.flightPathValueMinutes or 8, maxDetour = cfg.flightPathMaxDetourMinutes or 4 }
			end
		end
	end
	return out
end

----------------------------------------------------------------------------------------
-- Grinding
----------------------------------------------------------------------------------------
function X.GrindCandidates(here)
	local cfg, E = ns.cfg, ns.Estimate
	if not here then return {} end
	local spots = ns.Places.GrindSpots(here)
	local minutes = cfg.grindMinutes or 15
	local out = {}
	for _, spot in ipairs(spots) do
		local id = "grind:" .. spot.npcId
		if not ns.skipped[id] then
			-- fewer spawns close together means more walking between kills
			local sparse = math.min(2, math.max(1, 12 / spot.count))
			local killSec = E.KillSeconds(spot.level, 0, spot.name) * sparse
			local kills = math.floor(minutes * 60 / killSec)
			local xp = kills * E.MobXP(spot.level, 0)
			if xp > 0 then
				local q = oneStopQuest(id, "grind", "Grind " .. spot.name,
					string.format("Grind %s for %d min (~%d kills, ~%s XP)", spot.name, minutes, kills, ns.fmt(xp)),
					{ spot.point }, minutes * 60, { mobXp = xp, mobLevel = spot.level, mobRank = 0, mobs = { [spot.npcId] = true } })
				q.xp = xp
				q.value = xp * (cfg.grindValueFactor or 0.85)
				q.workSeconds = minutes * 60
				q.isGrind = true
				local travel = ns.Travel.Seconds(here, spot.point)
				q.roughRate = q.value / (travel + minutes * 60)
				out[#out + 1] = q
			end
		end
	end
	table.sort(out, function(a, b) return a.roughRate > b.roughRate end)
	for i = #out, (cfg.grindCandidates or 5) + 1, -1 do out[i] = nil end
	return out
end

----------------------------------------------------------------------------------------
-- Quest log clean-up
----------------------------------------------------------------------------------------

-- Quests in your log that the plan doesn't use, worst first: {name, reason}. Only when the log is
-- nearly full.
-- (the log count at which this starts: Config.cleanupAtLogCount, else 2 under the log's size)
function X.CleanupAt(cap)
	return ns.cfg.cleanupAtLogCount or ((cap or 20) - 2)
end
function X.CleanupAdvice(plan, candidates, ctx, force)
	local cfg = ns.cfg
	if not force and ctx.logCount < X.CleanupAt(ctx.logCap) then return nil end
	local inPlan = {}
	for _, e in ipairs(plan.route or {}) do
		local q = e.stop.quest
		inPlan[q.id] = true
		for _, part in ipairs(q.parts or {}) do inPlan[part.id] = true end
	end
	local planned = {}
	for _, q in ipairs(candidates and candidates.log or {}) do planned[q.id] = q end
	for _, d in ipairs(candidates and candidates.dungeons or {}) do
		for _, part in ipairs(d.parts or {}) do planned[part.id] = part end
	end

	local list = {}
	for questId, entry in pairs(ns.QuestSource.LogEntries()) do
		if not inPlan[questId] then
			local q = planned[questId]
			local name = (q and q.name) or entry.title or ("Quest " .. questId)
			local lvl = ns.QuestSource.Levels(questId)
			local grey = ns.Q.QuestieDB.IsTrivial and ns.safe(ns.Q.QuestieDB.IsTrivial, lvl)
			local reason, rank
			if grey then
				reason, rank = "grey: little XP", 1
			elseif ns.QuestSource.TooHigh(questId, entry) then
				reason, rank = "too high for now - keep it, planned later", 5
			elseif not q then
				reason, rank = "LevelPlanner can't plan it (location unknown or blocked)", 2
			else
				local far = true
				for _, s in ipairs(q.stops) do
					for _, p in ipairs(s.points or {}) do
						if ctx.start and p.inst == ctx.start.inst then far = false end
					end
				end
				if far then
					reason, rank = "on another continent", 3
				else
					local first = q.stops[1] and q.stops[1].points[1]
					local travel = first and ctx.start and ns.Travel.Seconds(ctx.start, first) or 0
					q.cleanupRate = (q.xp or 0) / math.max(60, travel + (q.workSeconds or 0)) * 60
					reason, rank = string.format("slow: ~%s XP/min", ns.fmt(q.cleanupRate)), 4
				end
			end
			list[#list + 1] = { name = name, reason = reason, rank = rank, rate = q and q.cleanupRate or 0,
				id = questId, grey = grey and true or false, complete = entry.isComplete == 1,
				classQuest = ns.QuestSource.IsClassQuest and ns.QuestSource.IsClassQuest(questId) or false }
		end
	end
	table.sort(list, function(a, b)
		if a.rank ~= b.rank then return a.rank < b.rank end
		return a.rate < b.rate
	end)
	return list
end
