-- Planner (phase 3): builds about an hour of stops for the most XP per minute.
--   1. Greedy: repeatedly add the quest whose stops fit into the route for the most XP per extra minute.
--   2. Local improvement: move whole quests, move single stops, swap a quest for an unused one.
--   3. Stability: keep the current route unless the new one is better by Config.switchThreshold.
-- Rules everywhere: pick-up -> objectives -> turn-in order, follow-ups after the quests that open
-- them, at most 20 quests in the log, and enough free bag slots for quest items.
-- Travel times come from the travel graph (phase 2). Everything runs inside a frame-spread job.
local ADDON, zyde = ...
-- Part of Zyde_Forever since 2026-11-14: LevelPlanner keeps its own private table (zyde.LP) so its
-- names never clash with Zyde's.
zyde.LP = zyde.LP or {}
local ns = zyde.LP

local P = {}
ns.Planner = P

-- (the quest log's size comes from the game: ctx.logCap, see QuestSource.LogCap)

local function travel(a, b)
	if not a or not b then return 0 end
	return ns.Travel.Seconds(a, b)
end

local function copy(route)
	local r = {}
	for i = 1, #route do r[i] = route[i] end
	return r
end

local function sharesMobs(a, b)
	if not (a and b and a.mobs and b.mobs) then return false end
	for id in pairs(a.mobs) do
		if b.mobs[id] then return true end
	end
	return false
end

-- Work time a stop adds after the previous one. Two objectives right next to each other that need
-- the same mobs are done together: the kills count for both, so only the longer one's time counts.
-- run = the longest work time in the current "together" group.
local function addedWork(prevEntry, e, run, start)
	local w = e.stop.work or 0
	if not prevEntry then
		-- the first stop is an objective in the camp you're standing in: you've already found it
		local d = start and e.stop.kind == "objective" and ns.Geo.Distance(start, e.point)
		if d and d <= (ns.cfg.sameCampYards or 200) then
			w = math.max(0, w - (ns.cfg.objectiveOverheadSeconds or 45))
		end
		return w, w
	end
	if prevEntry then
		local d = ns.Geo.Distance(prevEntry.point, e.point)
		if d and d <= (ns.cfg.overlapYards or 60) and sharesMobs(prevEntry.stop, e.stop) then
			return math.max(0, w - run), math.max(run, w)
		end
		-- another objective in the same camp: you're already there, so "finding the spot"
		-- (objectiveOverheadSeconds) is counted once, not again for each objective
		if d and d <= (ns.cfg.sameCampYards or 200)
			and prevEntry.stop.kind == "objective" and e.stop.kind == "objective" then
			w = math.max(0, w - (ns.cfg.objectiveOverheadSeconds or 45))
		end
	end
	return w, w
end

-- Total time of a route (list of {stop, point}) from ctx.start.
local function routeSeconds(route, ctx)
	local t, prev, prevEntry, run = 0, ctx.start, nil, 0
	for _, e in ipairs(route) do
		local w
		w, run = addedWork(prevEntry, e, run, ctx.start)
		t = t + travel(prev, e.point) + w
		prev, prevEntry = e.point, e
	end
	return t
end

-- What a quest is worth when choosing: its XP plus part of what it opens later (chain value).
local function value(q) return q.value or q.xp or 0 end

-- Order, follow-up, quest-log and bag rules.
local function feasible(route, ctx)
	local n, bag = ctx.logCount, 0
	local turnedIn, lastOrder = {}, {}
	for _, e in ipairs(route) do
		local s = e.stop
		local q = s.quest
		-- equal order is allowed: a dungeon's pick-ups (and its turn-ins) can come in any order
		if s.order < (lastOrder[q] or 0) then return false end
		lastOrder[q] = s.order
		if s.kind == "pickup" and q.requires then
			for _, req in ipairs(q.requires) do
				if not turnedIn[req] then return false end
			end
		elseif s.kind == "turnin" then
			turnedIn[q.id] = true
		end
		n = n + (s.logDelta or 0)
		bag = bag + (s.bagDelta or 0)
		if n > ctx.logCap or bag > ctx.bagFree then return false end
	end
	return true
end

-- Cheapest insertion of all of a quest's stops, in order (and after the quests it needs).
-- Returns the new route and its time, or nil when it can't fit.
local function insertQuest(route, quest, ctx)
	local r = copy(route)
	local minPos = 1
	if quest.requires then
		for _, req in ipairs(quest.requires) do
			local found
			for i, e in ipairs(r) do
				if e.stop.kind == "turnin" and e.stop.quest.id == req then found = i end
			end
			if not found then return nil end
			minPos = math.max(minPos, found + 1)
		end
	end
	for _, stop in ipairs(quest.stops) do
		local bestPos, bestPoint, bestDelta
		for pos = minPos, #r + 1 do
			local prev = (pos == 1) and ctx.start or r[pos - 1].point
			local nxt = r[pos] and r[pos].point
			local base = nxt and travel(prev, nxt) or 0
			for _, p in ipairs(stop.points) do
				local d = travel(prev, p) + (nxt and travel(p, nxt) or 0) - base
				if not bestDelta or d < bestDelta then bestPos, bestPoint, bestDelta = pos, p, d end
			end
		end
		if not bestPos then return nil end
		table.insert(r, bestPos, { stop = stop, point = bestPoint })
		minPos = bestPos + 1
	end
	if not feasible(r, ctx) then return nil end
	return r, routeSeconds(r, ctx)
end

local function removeQuest(route, quest)
	local r = {}
	for _, e in ipairs(route) do
		if e.stop.quest ~= quest then r[#r + 1] = e end
	end
	return r
end

local function questsIn(route)
	local list, seen = {}, {}
	for _, e in ipairs(route) do
		local q = e.stop.quest
		if not seen[q] then seen[q] = true list[#list + 1] = q end
	end
	return list
end

-- Does any other quest in the route need this one turned in first?
local function hasDependents(route, quest)
	for _, e in ipairs(route) do
		local req = e.stop.quest.requires
		if req then
			for _, id in ipairs(req) do
				if id == quest.id then return true end
			end
		end
	end
	return false
end

----------------------------------------------------------------------------------------
-- Building
----------------------------------------------------------------------------------------

-- Adds quests until the route covers the horizon. state = {route, total, xp, used}
local function greedyFill(state, pool, ctx)
	while state.total < ctx.horizon do
		local bestQ, bestRoute, bestTime, bestRate
		for _, q in ipairs(pool) do
			ns.Check()
			if not state.used[q] then
				local r, t = insertQuest(state.route, q, ctx)
				if r then
					local rate = value(q) / math.max(1, t - state.total)
					if not bestRate or rate > bestRate then
						bestQ, bestRoute, bestTime, bestRate = q, r, t, rate
					end
				end
			end
		end
		if not bestQ then break end
		state.used[bestQ] = true
		state.route, state.total, state.xp = bestRoute, bestTime, state.xp + bestQ.xp
		state.value = (state.value or 0) + value(bestQ)
	end
	return state
end

-- Local-improvement passes. Each pass tries three kinds of move and keeps any that helps.
local function improve(state, pool, ctx)
	for _ = 1, (ns.cfg.improvementPasses or 3) do
		local better = false

		-- 1. take a whole quest out and put it back in its cheapest place
		for _, q in ipairs(questsIn(state.route)) do
			ns.Check()
			if not hasDependents(state.route, q) then
				local r, t = insertQuest(removeQuest(state.route, q), q, ctx)
				if r and t < state.total - 0.5 then
					state.route, state.total, better = r, t, true
				end
			end
		end

		-- 2. move one stop to its best place (any of its areas)
		local i = 1
		while i <= #state.route do
			ns.Check()
			local e = state.route[i]
			local r0 = copy(state.route)
			table.remove(r0, i)
			local bestPos, bestP, bestT = nil, nil, state.total - 0.5
			for pos = 1, #r0 + 1 do
				ns.Check()
				for _, p in ipairs(e.stop.points) do
					-- try in place, then undo (avoids copying the route for every try)
					table.insert(r0, pos, { stop = e.stop, point = p })
					if feasible(r0, ctx) then
						local t = routeSeconds(r0, ctx)
						if t < bestT then bestPos, bestP, bestT = pos, p, t end
					end
					table.remove(r0, pos)
				end
			end
			if bestPos then
				table.insert(r0, bestPos, { stop = e.stop, point = bestP })
				state.route, state.total, better = r0, bestT, true
			end
			i = i + 1
		end

		-- 3. swap a planned quest for an unused one when that raises XP per minute
		--    (only the most promising unused quests are tried, to keep re-planning quick)
		local unused = {}
		for _, c in ipairs(pool) do
			if not state.used[c] then unused[#unused + 1] = c end
		end
		table.sort(unused, function(a, b)
			return value(a) / math.max(60, a.workSeconds or 60) > value(b) / math.max(60, b.workSeconds or 60)
		end)
		for k = #unused, (ns.cfg.swapCandidates or 15) + 1, -1 do unused[k] = nil end

		local rate = (state.value or 0) / math.max(1, state.total)
		for _, q in ipairs(questsIn(state.route)) do
			if state.used[q] and not hasDependents(state.route, q) then
				local r0 = removeQuest(state.route, q)
				local bestR, bestT, bestC, bestRate = nil, nil, nil, rate * 1.001
				for _, c in ipairs(unused) do
					ns.Check()
					if not state.used[c] then
						local r, t = insertQuest(r0, c, ctx)
						if r and t <= ctx.horizon * 1.25 then
							local newRate = ((state.value or 0) - value(q) + value(c)) / math.max(1, t)
							if newRate > bestRate then bestR, bestT, bestC, bestRate = r, t, c, newRate end
						end
					end
				end
				if bestR then
					state.used[q], state.used[bestC] = nil, true
					state.route, state.total = bestR, bestT
					state.xp = state.xp - q.xp + bestC.xp
					state.value = (state.value or 0) - value(q) + value(bestC)
					rate = bestRate
					better = true
				end
			end
		end

		-- time freed up by the moves above can take more quests
		if state.total < ctx.horizon then greedyFill(state, pool, ctx) end
		if not better then break end
	end
	return state
end

-- Finish what's here first: an objective whose camp you're standing in moves to the front when that
-- costs at most Config.hereFirstSlackSeconds. Leaving and coming back later risks the camp being
-- cleared or forgotten, and a near tie in the estimate shouldn't send you away from mobs you're
-- already killing. Works on the kept route too (which is re-read in its old order).
-- An escort you've started goes first, whatever it costs: wander off and it fails. "Started" = an
-- escort quest accepted in the last Config.escortMinutes that isn't finished (a failed one has
-- already left the pool). Its objective leads the route; its turn-in is added if it wasn't planned.
local function escortActive(q)
	if not q.escort then return false end
	local t = ns.char and ns.char.acceptedAt and ns.char.acceptedAt[q.id]
	return t ~= nil and GetTime() - t < (ns.cfg.escortMinutes or 30) * 60
end

local function escortFirst(state, ctx)
	if ns.cfg.escortFirst == false or not ctx.pool then return state end
	for _, q in ipairs(ctx.pool) do
		if escortActive(q) then
			local r, lead, planned = copy(state.route), {}, false
			for i = #r, 1, -1 do
				local s = r[i].stop
				if s.quest == q then
					planned = true
					if s.kind == "objective" then table.insert(lead, 1, table.remove(r, i)) end
				end
			end
			if not planned then
				for _, s in ipairs(q.stops) do
					local e = { stop = s, point = ns.Stops.NearestPoint(s, ctx.start) }
					if s.kind == "objective" then lead[#lead + 1] = e elseif s.kind == "turnin" then r[#r + 1] = e end
				end
				state.xp = (state.xp or 0) + (q.questXp or 0)
			end
			for k = #lead, 1, -1 do table.insert(r, 1, lead[k]) end
			if #lead > 0 and feasible(r, ctx) then
				state.route, state.total = r, routeSeconds(r, ctx)
			end
			return state
		end
	end
	return state
end

-- The NPC ID of your target when it's a live enemy (nil otherwise, or when the game hides it).
function P.TargetNpc()
	if not UnitExists("target") or UnitIsDead("target") or not UnitCanAttack("player", "target") then return nil end
	local guid = UnitGUID("target")
	if ns.isSecret(guid) or type(guid) ~= "string" then return nil end
	local kind, _, _, _, _, id = strsplit("-", guid)
	if kind ~= "Creature" then return nil end
	return tonumber(id)
end

local hereFirstInner -- (below: then the escort, if one is running, goes in front of everything)
local function hereFirst(state, ctx)
	return escortFirst(hereFirstInner(state, ctx), ctx)
end

function hereFirstInner(state, ctx)
	if not ctx.start or #state.route < 2 or ns.cfg.hereFirst == false then return state end
	local near = ns.cfg.sameCampYards or 200
	local bestI, bestP, bestD
	local fighting = false
	for i, e in ipairs(state.route) do
		if e.stop.kind == "objective" then
			-- the mob you're attacking counts for it: you're in this camp, wherever its map point sits
			if ctx.targetNpc and e.stop.mobs and e.stop.mobs[ctx.targetNpc] then
				bestI, bestP, bestD = i, ns.Stops.NearestPoint(e.stop, ctx.start), 0
				fighting = true
				break
			end
			for _, p in ipairs(e.stop.points) do
				local d = ns.Geo.Distance(ctx.start, p)
				if d and d <= near and (not bestD or d < bestD) then bestI, bestP, bestD = i, p, d end
			end
		end
	end
	local slack = ns.cfg.hereFirstSlackSeconds or 90
	local campStop = bestI and state.route[bestI].stop
	if bestI and bestI > 1 then
		local r = copy(state.route)
		local e = table.remove(r, bestI)
		table.insert(r, 1, { stop = e.stop, point = bestP })
		if feasible(r, ctx) then
			local t = routeSeconds(r, ctx)
			-- (mid-fight with its mob, finishing here comes first whatever the sums say)
			if fighting or t <= state.total + slack then state.route, state.total = r, t end
		end
	end

	-- Turn-ins close by (the town you're standing in) go first too, nearest first: putting them off
	-- "until you're back" looks free on paper, but the XP and follow-ups are wanted now.
	local turnNear = ns.cfg.hereTurninYards or 400
	local list = {}
	for i, e in ipairs(state.route) do
		if e.stop.kind == "turnin" then
			local d = ns.Geo.Distance(ctx.start, e.point)
			if d and d <= turnNear then list[#list + 1] = { stop = e.stop, d = d } end
		end
	end
	table.sort(list, function(a, b) return a.d < b.d end)
	-- the camp you're standing in stays first: finish the kills here, then walk to the turn-ins
	local campFirst = campStop ~= nil and state.route[1] ~= nil and state.route[1].stop == campStop
	local pos = campFirst and 2 or 1
	for _, c in ipairs(list) do
		local r = copy(state.route)
		local from
		for i, e in ipairs(r) do if e.stop == c.stop then from = i break end end
		if from and from > pos then
			local e = table.remove(r, from)
			table.insert(r, pos, e)
			if feasible(r, ctx) then
				local t = routeSeconds(r, ctx)
				if t <= state.total + slack then
					state.route, state.total = r, t
					pos = pos + 1
				end
			end
		elseif from == pos then
			pos = pos + 1
		end
	end
	return state
end

-- The previous route, re-read against current quest data (finished stops drop out), then topped up.
local function carryOver(previous, pool, ctx)
	if not (previous and previous.keys and #previous.keys > 0) then return nil end
	local byKey = {}
	for _, q in ipairs(pool) do
		for _, s in ipairs(q.stops) do byKey[s.key] = s end
	end
	local r, count = {}, {}
	for _, k in ipairs(previous.keys) do
		local s = byKey[k.key]
		if s then
			-- the area closest to the one used before
			local best, bestD
			for _, p in ipairs(s.points) do
				local d = ns.Geo.Distance(p, k)
				if d and (not bestD or d < bestD) then best, bestD = p, d end
			end
			r[#r + 1] = { stop = s, point = best or s.points[1] }
			count[s.quest] = (count[s.quest] or 0) + 1
		end
	end
	-- only whole quests can stay
	local whole = {}
	for _, e in ipairs(r) do
		if count[e.stop.quest] == #e.stop.quest.stops then whole[#whole + 1] = e end
	end
	if #whole == 0 or not feasible(whole, ctx) then return nil end
	local state = { route = whole, total = routeSeconds(whole, ctx), xp = 0, value = 0, used = {} }
	for _, q in ipairs(questsIn(whole)) do
		state.used[q] = true
		state.xp = state.xp + (q.xp or 0)
		state.value = state.value + value(q)
	end
	return greedyFill(state, pool, ctx)
end

----------------------------------------------------------------------------------------
-- Optional stops (trainer, vendor/repair, hearthstone at the hub, flight paths): each is added
-- where it fits best, only when the detour is short and XP per minute - counting what the stop
-- saves or gains later - goes up.
----------------------------------------------------------------------------------------
local function addExtras(state, ctx)
	if not ctx.start or #state.route == 0 then return state end
	local perSecond = (state.value or 0) / math.max(60, state.total)
	if perSecond <= 0 then return state end
	for _, opt in ipairs(ns.Extras.OptionalStops(state.route, ctx)) do
		ns.Check()
		local q = opt.quest
		if not ns.skipped[q.id] then
			local worth = opt.worth * 60 * perSecond
			q.value = worth
			local r, t = insertQuest(state.route, q, ctx)
			if r and t - state.total <= opt.maxDetour * 60
				and (state.value + worth) / t > state.value / math.max(1, state.total) then
				state.route, state.total, state.value = r, t, state.value + worth
			end
		end
	end
	return state
end

----------------------------------------------------------------------------------------
-- Final step list: travel legs (hearth, flights, boats, passes) before each stop
----------------------------------------------------------------------------------------
local function finalize(state, ctx)
	local cfg = ns.cfg
	local route, start = state.route, ctx.start
	local hearthSecs = cfg.hearthSeconds or 45

	-- hearthstone: used on the legs where it saves the most time, once per cooldown. A saving later in
	-- the route counts for less (the route is re-planned as you go, so a later leg may never happen):
	-- a sure saving now beats a slightly bigger one in 40 minutes.
	local hearth = ns.Travel.Hearth()
	local hearthLegs = {}
	if hearth then
		local cands = {}
		local t, prev = 0, start
		local later = cfg.hearthLaterDiscount or 0.5
		for idx, e in ipairs(route) do
			local normal = travel(prev, e.point)
			if t >= hearth.readyIn then
				local save = normal - (hearthSecs + travel(hearth.point, e.point))
				if save > 0 then
					cands[#cands + 1] = { idx = idx, t = t, score = save * (1 - later * math.min(1, t / ctx.horizon)) }
				end
			end
			t = t + normal + (e.stop.work or 0)
			prev = e.point
		end
		table.sort(cands, function(a, b) return a.score > b.score end)
		local cd, chosen = cfg.hearthCooldownSeconds or 3600, {}
		for _, c in ipairs(cands) do
			local free = true
			for _, o in ipairs(chosen) do
				if math.abs(c.t - o.t) < cd then free = false break end
			end
			if free then chosen[#chosen + 1] = c hearthLegs[c.idx] = true end
		end
	end

	local steps, keys = {}, {}
	local arrived = (cfg.arrivedYards or 15) * 2
	local t, prev, prevEntry, run = 0, start, nil, 0
	for idx, e in ipairs(route) do
		local from = prev
		if hearthLegs[idx] then
			steps[#steps + 1] = { kind = "travel", mode = "hearth", label = "Use your hearthstone (" .. hearth.name .. ")",
				point = prev, work = hearthSecs, arrive = t, mobXp = 0 }
			t = t + hearthSecs
			from = hearth.point
		end
		for _, leg in ipairs(ns.Travel.Legs(from, e.point)) do
			local d = ns.Geo.Distance(leg.point, from)
			-- a crossing you're already standing at is no step
			if not ((leg.mode == "pass" or leg.mode == "border") and d and d <= arrived) then
				steps[#steps + 1] = { kind = "travel", mode = leg.mode, label = leg.label, point = leg.point,
					work = leg.seconds, mobXp = 0, to = leg.to }
			end
		end
		t = t + travel(from, e.point)
		e.arrive = t
		-- a per-plan view of the stop (the stop itself is shared between the plans being compared)
		steps[#steps + 1] = setmetatable({ point = e.point, arrive = t }, { __index = e.stop })
		keys[#keys + 1] = { key = e.stop.key, wx = e.point.wx, wy = e.point.wy, inst = e.point.inst }
		local w
		w, run = addedWork(prevEntry, e, run, start)
		t = t + w
		prev, prevEntry = e.point, e
	end

	return {
		stops = steps,
		keys = keys,
		route = route,
		xp = state.xp,                                        -- real XP, shown in the list
		seconds = t,
		rate = t > 0 and state.xp / (t / 60) or 0,            -- real XP per minute, shown
		score = t > 0 and (state.value or state.xp) / (t / 60) or 0, -- what routes are compared on
		hearthPlanned = next(hearthLegs) ~= nil,
	}
end

----------------------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------------------

-- candidates: {log, available, locked} from QuestSource. previous: the plan currently shown (or nil).
-- opts.threshold: switch threshold for this plan (lower when you've left the planned path).
function P.Plan(candidates, previous, opts)
	local cfg = ns.cfg
	local ctx = {
		start = ns.Geo.PlayerPoint(),
		targetNpc = (function() local ok, id = pcall(P.TargetNpc) return ok and id or nil end)(), -- (the mob you're fighting: its objective goes first, see hereFirst)
		horizon = (cfg.horizonMinutes or 60) * 60,
		logCount = ns.QuestSource.LogCount(),
		logCap = ns.QuestSource.LogCap and ns.QuestSource.LogCap() or 20,
		bagFree = ns.QuestSource.FreeBagSlots() - (cfg.bagReserveSlots or 2),
	}

	local pool = {}
	for _, list in ipairs({ candidates and candidates.log or {}, candidates and candidates.available or {},
			candidates and candidates.locked or {} }) do
		for _, q in ipairs(list) do
			if not ns.skipped[q.id] then pool[#pool + 1] = q end
		end
	end
	ctx.pool = pool -- (escortFirst looks here for an escort you have started)

	-- grinding is filler only: it can take time the quests leave empty, never replace them
	local grind = {}
	for _, g in ipairs(candidates and candidates.grind or {}) do
		if not ns.skipped[g.id] then grind[#grind + 1] = g end
	end
	local function fillWithGrind(state)
		if #grind > 0 and state.total < ctx.horizon * (cfg.grindWhenPlanBelow or 0.75) then
			greedyFill(state, grind, ctx)
		end
		return state
	end

	local fresh = greedyFill({ route = {}, total = 0, xp = 0, value = 0, used = {} }, pool, ctx)
	fresh = addExtras(hereFirst(fillWithGrind(improve(fresh, pool, ctx)), ctx), ctx)
	local plan = finalize(fresh, ctx)

	-- dungeons: considered only when a run beats questing XP per minute, or when you're grouped
	local grouped = ns.IsGrouped()
	local dungeonInfo, eligible = {}, {}
	for _, d in ipairs(candidates and candidates.dungeons or {}) do
		ns.Check()
		if not ns.skipped[d.id] then
			local r, t = insertQuest({}, d, ctx)
			local rate = r and value(d) / math.max(1, t / 60) or 0
			local ok = r ~= nil and (grouped or rate > plan.score)
			dungeonInfo[#dungeonInfo + 1] = { name = d.name, rate = rate, ok = ok, quests = #d.parts }
			if ok then eligible[#eligible + 1] = d end
		end
	end
	if #eligible > 0 then
		local withDungeons = {}
		for _, q in ipairs(pool) do withDungeons[#withDungeons + 1] = q end
		for _, d in ipairs(eligible) do withDungeons[#withDungeons + 1] = d end
		local alt = improve(greedyFill({ route = {}, total = 0, xp = 0, value = 0, used = {} }, withDungeons, ctx), withDungeons, ctx)
		local altPlan = finalize(addExtras(hereFirst(fillWithGrind(alt), ctx), ctx), ctx)
		-- when grouped a run is wanted even if questing is slightly faster
		if altPlan.score > plan.score or (grouped and altPlan.score > plan.score * 0.9) then plan = altPlan end
		pool = withDungeons
		ctx.pool = pool
	end

	local carried = carryOver(previous, pool, ctx)
	if carried then hereFirst(fillWithGrind(carried), ctx) end
	if carried and #carried.route > 0 then
		local keep = finalize(addExtras(carried, ctx), ctx)
		local threshold = (opts and opts.threshold) or cfg.switchThreshold or 0.10
		if keep.score > 0 and plan.score < keep.score * (1 + threshold) then
			keep.note = string.format("kept the current route (new route only %+.0f%% better)",
				(plan.score / keep.score - 1) * 100)
			plan = keep
		else
			plan.switchGain = keep.score > 0 and (plan.score / keep.score - 1) * 100 or 100
			plan.note = string.format("switched route (%+.0f%% better)", plan.switchGain)
			plan.switched = true
		end
	end

	plan.candidateCount = #pool
	plan.dungeonInfo = dungeonInfo
	plan.cleanup = ns.Extras.CleanupAdvice(plan, candidates, ctx, true)
	plan.cleanupDue = ctx.logCount >= ns.Extras.CleanupAt(ctx.logCap)
	plan.bagFree = ctx.bagFree
	plan.logCount = ctx.logCount
	plan.logCap = ctx.logCap
	return plan
end
