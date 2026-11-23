-- Planner (phase 3): builds about an hour of stops for the most XP per minute.
--   1. Greedy: repeatedly add the quest whose stops fit into the route for the most XP per extra minute.
--   2. Local improvement: move whole quests, move single stops, swap a quest for an unused one.
--   3. Stability: keep the current route unless the new one is better by Config.switchThreshold.
-- Rules everywhere: pick-up -> objectives -> turn-in order, follow-ups after the quests that open
-- them, at most 20 quests in the log (bag room never holds a quest back).
-- Travel times come from the travel graph (phase 2). Everything runs inside a frame-spread job.
local ADDON, zyde = ...
-- Part of Zyde_Forever since 2026-11-14: LevelPlanner keeps its own private table (zyde.LP) so its
-- names never clash with Zyde's.
zyde.LP = zyde.LP or {}
local ns = zyde.LP

local P = {}
ns.Planner = P

-- (the quest log's size comes from the game: ctx.logCap, see QuestSource.LogCap)

-- Travel times are looked up hundreds of thousands of times while searching, mostly for the same
-- pairs of points: each plan keeps them (P.Plan starts a fresh table, so nothing goes stale).
local tcache = setmetatable({}, { __mode = "k" })
local function travel(a, b)
	if not a or not b then return 0 end
	local row = tcache[a]
	if not row then row = setmetatable({}, { __mode = "k" }) tcache[a] = row end
	local t = row[b]
	if not t then t = ns.Travel.Seconds(a, b) row[b] = t end
	return t
end

-- XP a stop earns (its kills, plus the quest XP at a turn-in): used to see where the route levels you up.
-- pool = rested XP left before this stop (kills give double while it lasts). Returns the XP and the
-- pool left after the stop.
local function stopXp(s, pool)
	local m = s.mobXp or 0
	local b = 0
	if pool and pool > 0 and m > 0 then b, pool = ns.Estimate.RestedBonus(pool, m) end
	return m + b + (s.kind == "turnin" and (s.xp or 0) or 0), pool
end

-- The stop after which the route's XP takes you up n levels (default 1; nil: it doesn't get there).
-- ctx.toDing = XP still needed for the next level (nil when unknown or at the cap); ctx.dingNeeds[n]
-- = XP needed for n levels up.
local function dingIndex(route, ctx, n)
	local need = ctx.dingNeeds and ctx.dingNeeds[n or 1] or (not n or n == 1) and ctx.toDing
	if not need then return nil end
	local xp, pool = 0, ctx.rested
	for i, e in ipairs(route) do
		local g
		g, pool = stopXp(e.stop, pool)
		xp = xp + g
		if xp >= need then return i end
	end
	return nil
end

-- A quest offered only now and then (Stops.TimedWindow): at its pick-up, arriving at t seconds into
-- the route, how long you wait for the giver, and whether you're too late. MISSED is added to the
-- route's time when you are, so no route keeps a pick-up it can't make.
local MISSED = 1e6
local function timedWait(s, t, ctx)
	local q = s.quest
	if s.kind ~= "pickup" or not q.timedFrom or not ctx.now then return 0 end
	local from, to = q.timedFrom - ctx.now, q.timedTo - ctx.now
	if t > to then return MISSED end
	if t < from then return from - t end
	return 0
end

-- Kill XP in a quest (or grind / dungeon), for the rested bonus.
local function mobOf(q)
	if q.mobXp then return q.mobXp end
	if q._mobXp == nil then
		local m = 0
		for _, s in ipairs(q.stops or {}) do m = m + (s.mobXp or 0) end
		q._mobXp = m
	end
	return q._mobXp
end

-- The rested bonus a route earns: kills worth mobXp in all, the pool used up by them in route order.
-- The total doesn't depend on the order (min(pool, kill XP)), so it's kept as a running sum
-- (state.mobXp) and costs nothing while searching.
local function restedWorth(mobXp, ctx)
	local pool = ctx.rested or 0
	if pool <= 0 then return 0 end
	return math.min(pool, mobXp or 0) * (ns.cfg.mobXpWeight or 1)
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

-- Along the way. A kill / gather step whose mobs or pick-ups lie among the steps of other quests
-- (stop.wayNb, worked out once per plan by P.WayNeighbours) is partly done in passing: on the way to
-- those steps and while doing them you meet its mobs anyway. Each such quest that's in the route
-- takes Config.wayPerNeighbour off its work, up to wayMaxShare - or wayMaxShareRoam for mobs that roam
-- the whole zone (Duskbats). Quests that need the same mobs are left to the overlap rule (addedWork).
function P.WayShare(stop, inRoute)
	local nb = inRoute and stop.wayNb
	if not nb then return 0 end
	local n = 0
	for q in pairs(nb) do
		if inRoute[q] then n = n + 1 end
	end
	if n == 0 then return 0 end
	local cfg = ns.cfg
	local max = stop.roam and (cfg.wayMaxShareRoam or 0.5) or (cfg.wayMaxShare or 0.3)
	return math.min(max, n * (cfg.wayPerNeighbour or 0.1))
end

-- Sets stop.wayNb on every kill / gather step of the pool: the other quests with a step within
-- Config.wayYards of its mobs or pick-ups (Stops.lua stop.spread). A grid keeps it quick.
function P.WayNeighbours(pool)
	local cfg = ns.cfg
	local yards = cfg.wayYards or 150
	local grid = {}
	local function key(p, dx, dy)
		return tostring(p.inst) .. ":" .. (math.floor(p.wx / yards) + dx) .. ":" .. (math.floor(p.wy / yards) + dy)
	end
	for _, q in ipairs(pool) do
		for _, s in ipairs(q.stops) do
			for _, p in ipairs(s.points or {}) do
				if p.wx and p.wy then
					local k = key(p, 0, 0)
					local cell = grid[k]
					if not cell then cell = {} grid[k] = cell end
					cell[#cell + 1] = { p = p, q = q, s = s }
				end
			end
		end
	end
	local any = false
	for _, q in ipairs(pool) do
		ns.Check()
		for _, s in ipairs(q.stops) do
			s.wayNb = nil
			if s.spread then
				local nb, n = {}, 0
				for _, p in ipairs(s.spread) do
					if p.wx and p.wy then
						for dx = -1, 1 do
							for dy = -1, 1 do
								for _, c in ipairs(grid[key(p, dx, dy)] or {}) do
									if c.q ~= q and not nb[c.q] and not sharesMobs(s, c.s) then
										local d = ns.Geo.Distance(p, c.p)
										if d and d <= yards then nb[c.q], n = true, n + 1 end
									end
								end
							end
						end
					end
				end
				if n > 0 then s.wayNb, any = nb, true end
			end
		end
	end
	return any
end

-- Work time a stop adds after the previous one. Two objectives right next to each other that need
-- the same mobs are done together: the kills count for both, so only the longer one's time counts.
-- run = the longest work time in the current "together" group.
-- rate (search only, XP per second): those shared kills give their XP once, not to both quests, so
-- the XP counted twice is charged back as the time it would take to earn at this rate.
local function addedWork(prevEntry, e, run, start, rate, inRoute)
	-- (an area of higher-level mobs takes longer: point.workFactor, Stops.lua)
	local w = (e.stop.work or 0) * (e.point.workFactor or 1)
	-- along the way: other quests of the route have steps among its mobs / pick-ups, so part of it is
	-- done in passing, on the way to and while doing those (wayNeighbours, P.Plan)
	w = w * (1 - P.WayShare(e.stop, inRoute))
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
			local charge = 0
			local mx = (e.stop.mobXp or 0) * (e.point.xpFactor or 1)
			-- (no route rate known yet: this stop's own kill rate, i.e. the shared kills save nothing)
			if rate and mx > 0 and w > 0 then
				local r = rate > 0 and rate or mx / w
				charge = mx * math.min(1, run / w) / r
			end
			return math.max(0, w - run) + charge, math.max(run, w)
		end
		-- another objective in the same camp: you're already there, so "finding the spot"
		-- (objectiveOverheadSeconds) is counted once, not again for each objective
		if d and d <= (ns.cfg.sameCampYards or 200)
			and prevEntry.stop.kind == "objective" and e.stop.kind == "objective" then
			w = math.max(0, w - (ns.cfg.objectiveOverheadSeconds or 45))
			-- picking things off the ground among mobs you're killing: you walk the area anyway, so
			-- part of the shorter one's time is shared (Doom Weed among the Graverobbers)
			local a, b = prevEntry.stop, e.stop
			if (a.gather and b.mobs) or (b.gather and a.mobs) then
				local pw = (a.work or 0) * (prevEntry.point.workFactor or 1)
				w = math.max(0, w - math.min(w, pw) * (ns.cfg.gatherAmongKillsShare or 0.5))
			end
		end
	end
	return w, w
end

-- Total time of a route (list of {stop, point}) from ctx.start. Counts the shortcuts you'll really use:
--  * the hearthstone, once (it's an hour's cooldown and a route is about an hour): on the leg where
--    "cast, land at the inn, walk on" beats the normal way by the most, once it's off cooldown
--    (ctx.hearth; finalize places the actual step, see there)
--  * riding instead of running after a level-up on the way that reaches your mount level
--    (ctx.mountSpeed). Flights, boats and zeppelins you know are in travel() already.
local function routeSeconds(route, ctx)
	local t, prev, prevEntry, run = 0, ctx.start, nil, 0
	local inRoute
	if ctx.wayOn then
		inRoute = {}
		for _, e in ipairs(route) do inRoute[e.stop.quest] = true end
	end
	local h, hs, save = ctx.hearth, ctx.hearthSecs or 45, 0
	local need, xp, speed, pool = ctx.mountSpeed and ctx.toDing, 0, nil, ctx.rested
	for _, e in ipairs(route) do
		local w
		w, run = addedWork(prevEntry, e, run, ctx.start, ctx.xpRate or 0, inRoute)
		local leg = speed and prev and ns.Travel.Seconds(prev, e.point, speed) or travel(prev, e.point)
		if h and leg > hs and t >= h.readyIn then
			local s = leg - hs - travel(h.point, e.point)
			if s > save then save = s end
		end
		t = t + leg
		if e.stop.quest.timedFrom then t = t + timedWait(e.stop, t, ctx) end
		t = t + w
		prev, prevEntry = e.point, e
		if need and not speed then
			local g
			g, pool = stopXp(e.stop, pool)
			xp = xp + g
			if xp >= need then speed = ctx.mountSpeed end
		end
	end
	return t - save
end

-- What a quest is worth when choosing: its XP plus part of what it opens later (chain value).
local function value(q) return q.value or q.xp or 0 end

-- What a route is worth: its quests plus the rested bonus on its kills.
local function worth(state, ctx)
	return (state.value or 0) + restedWorth(state.mobXp, ctx)
end

-- Order, follow-up, quest-log and bag rules.
-- A quest that opens at your next level (q.unlockLevel) can only start after the stop where the
-- route's XP gets you there.
local failWhy -- why the last insertQuest / feasible check said no (for /lp why, P.Diagnose)
local function feasible(route, ctx)
	local n, bag = ctx.logCount, 0
	local turnedIn, lastOrder = {}, {}
	local xp, need, level, pool = 0, ctx.toDing, ctx.level or 0, ctx.rested
	local prevStop
	for _, e in ipairs(route) do
		local s = e.stop
		local q = s.quest
		local first = lastOrder[q] == nil
		-- an escort starts the moment you take it: its objective comes right after its pick-up
		if q.escort and s.kind == "objective" and lastOrder[q] and not (prevStop and prevStop.quest == q) then
			failWhy = "escort order"
			return false
		end
		prevStop = s
		-- equal order is allowed: a dungeon's pick-ups (and its turn-ins) can come in any order
		if s.order < (lastOrder[q] or 0) then failWhy = "step order" return false end
		lastOrder[q] = s.order
		if first and q.unlockLevel and q.unlockLevel > level then
			local n = q.unlockLevel - level
			local needN = ctx.dingNeeds and ctx.dingNeeds[n] or (n == 1 and need)
			if not needN or xp < needN then failWhy = "opens at a level the route doesn't reach" return false end
		end
		local g
		g, pool = stopXp(s, pool)
		xp = xp + g
		if s.kind == "pickup" and q.requires then
			for _, req in ipairs(q.requires) do
				if not turnedIn[req] then failWhy = "needs quest " .. tostring(req) .. " turned in first" return false end
			end
		elseif s.kind == "turnin" then
			turnedIn[q.id] = true
		end
		n = n + (s.logDelta or 0)
		bag = bag + (s.bagDelta or 0)
		-- (only a step that adds a quest can break the log limit: with a full log, turn-ins, kills and
		-- grinding are still plannable. Bag room never holds a quest back - you can always make room;
		-- a vendor stop is suggested when the route fills your bags, Extras.lua)
		if (s.logDelta or 0) > 0 and n > ctx.logCap then
			failWhy = string.format("quest log full at %s (%d/%d)", s.label or s.key, n, ctx.logCap)
			return false
		end
	end
	return true
end

-- Cheapest insertion of all of a quest's stops, in order (and after the quests it needs, and after
-- the level-up when it opens at your next level).
-- Returns the new route, its time and where the first stop went; nil when it can't fit.
-- skipFirst: keep the first stop out of that position (the second-best place, for regret insertion).
local function insertQuest(route, quest, ctx, skipFirst)
	local r = copy(route)
	local minPos = 1
	if quest.unlockLevel and quest.unlockLevel > (ctx.level or 0) then
		local d = dingIndex(r, ctx, quest.unlockLevel - (ctx.level or 0))
		if not d then failWhy = string.format("opens at level %d, which the route doesn't reach", quest.unlockLevel) return nil end
		minPos = d + 1
	end
	if quest.requires then
		for _, req in ipairs(quest.requires) do
			local found
			for i, e in ipairs(r) do
				if e.stop.kind == "turnin" and e.stop.quest.id == req then found = i end
			end
			if not found then failWhy = "needs quest " .. tostring(req) .. " turned in first" return nil end
			minPos = math.max(minPos, found + 1)
		end
	end
	local firstPos
	for k, stop in ipairs(quest.stops) do
		local bestPos, bestPoint, bestDelta
		-- an escort's objective goes right after its pick-up (it starts when you take it)
		local maxPos = #r + 1
		if quest.escort and stop.kind == "objective" and k > 1 and quest.stops[k - 1].kind == "pickup" then maxPos = minPos end
		for pos = minPos, maxPos do
			if not (k == 1 and pos == skipFirst) then
				local prev = (pos == 1) and ctx.start or r[pos - 1].point
				local nxt = r[pos] and r[pos].point
				local base = nxt and travel(prev, nxt) or 0
				for _, p in ipairs(stop.points) do
					-- travel there, plus how much longer (or shorter) the work takes in that area
					local d = travel(prev, p) + (nxt and travel(p, nxt) or 0) - base
						+ (stop.work or 0) * ((p.workFactor or 1) - 1)
					if not bestDelta or d < bestDelta then bestPos, bestPoint, bestDelta = pos, p, d end
				end
			end
		end
		if not bestPos then failWhy = "no place for " .. tostring(stop.label or stop.key) .. " (no location?)" return nil end
		table.insert(r, bestPos, { stop = stop, point = bestPoint })
		minPos = bestPos + 1
		firstPos = firstPos or bestPos
	end
	if not feasible(r, ctx) then return nil end
	local t = routeSeconds(r, ctx)
	if t >= MISSED then failWhy = "its giver won't be there in time" return nil end -- (a now-and-then quest's giver would be gone)
	return r, t, firstPos
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
-- Plain: always the quest with the most value per added minute. opts (other starting routes for the
-- search, see P.Plan):
--   topK + rand: pick at random among the best few (GRASP), so each start explores a different route
--   regret: favour quests that only fit well in one place (their second-best place costs much more):
--           put off, they get expensive; the easy-to-place ones can still go in later
local function greedyFill(state, pool, ctx, opts)
	local topK = opts and opts.topK or 1
	local rand = opts and opts.rand
	local regret = opts and opts.regret
	local regretWeight = ns.cfg.regretWeight or 0.5
	while state.total < ctx.horizon do
		local top = {} -- best first, at most topK (equal ones keep pool order: plain = the old greedy)
		for _, q in ipairs(pool) do
			ns.Check()
			if not state.used[q] then
				local r, t, pos = insertQuest(state.route, q, ctx)
				if r then
					local added = math.max(1, t - state.total)
					-- (its kills while rested count double: what that adds to the route's rested bonus)
					local gain = restedWorth((state.mobXp or 0) + mobOf(q), ctx) - restedWorth(state.mobXp, ctx)
					local rate = (value(q) + gain) / added
					if regret then
						local _, t2 = insertQuest(state.route, q, ctx, pos)
						local extra = t2 and (t2 - t) / added or 1
						rate = rate * (1 + regretWeight * math.min(1, math.max(0, extra)))
					end
					local k = #top + 1
					while k > 1 and rate > top[k - 1].rate do k = k - 1 end
					if k <= topK then
						table.insert(top, k, { q = q, r = r, t = t, rate = rate })
						top[topK + 1] = nil
					end
				end
			end
		end
		if #top == 0 then break end
		local c = top[(rand and #top > 1) and rand(#top) or 1]
		-- filling the hour is no reason to take something far worse than the route: a long trip for a
		-- few quests (Durotar from Deathknell) would sink its XP per minute. Leave the time to grinding
		-- nearby (fillWithGrind) and the next re-plan instead. (Config.fillMinShare of the route's rate)
		-- (once the route has some length: a 40-second turn-in alone says little about a route's rate)
		if state.total >= ctx.horizon * 0.25 then
			local routeRate = (state.value or 0) / math.max(60, state.total)
			if c.rate < routeRate * (ns.cfg.fillMinShare or 0.2) then break end
		end
		state.used[c.q] = true
		state.route, state.total, state.xp = c.r, c.t, state.xp + c.q.xp
		state.value = (state.value or 0) + value(c.q)
		state.mobXp = (state.mobXp or 0) + mobOf(c.q)
	end
	return state
end

-- A full route (it covers the horizon) still takes any quest that raises its XP per minute: a
-- turn-in you're standing on, a quest you just picked up next to the route. greedyFill stops at the
-- horizon, so without this a kept route never takes them (and the 10% switch rule keeps it).
-- At most Config.overHorizonSeconds extra per quest; best value per added second first.
-- "Loose" pick-ups (ctx.loose, /lp pickup loose): also a quick quest on the way that earns at least
-- Config.looseMinShare of the route's rate and adds at most Config.looseMaxSeconds - you're there
-- anyway, and skipping it may cost a trip back later (as guides that take everything do).
local function topUp(state, pool, ctx)
	local cfg = ns.cfg
	local maxExtra = cfg.overHorizonSeconds or 300
	local looseMax, looseShare = cfg.looseMaxSeconds or 180, cfg.looseMinShare or 0.4
	local rate0 = worth(state, ctx) / math.max(60, state.total) -- (loose bar: the route as it was)
	local looseLeft = cfg.looseMaxTotalSeconds or 600            -- (and loose picks add this much at most)
	local looseDetour = cfg.looseDetourSeconds or 60
	-- the route's kill stops near you (the quest you're standing in): a quest in your log whose
	-- ground pick-ups are among them is "here" too, like a giver you're standing at
	local killsHere = {}
	local camp = cfg.sameCampYards or 200
	if ctx.start then
		for _, e in ipairs(state.route) do
			local d = e.stop.mobs and ns.Geo.Distance(ctx.start, e.point)
			if d and d <= camp then killsHere[#killsHere + 1] = e.point end
		end
	end
	local function gatherHere(q)
		if q.stops[1] and q.stops[1].kind == "pickup" then return false end
		for _, s in ipairs(q.stops) do
			-- (mobs that roam the zone, among several of the route's quests: killed on the way to them)
			if s.roam and s.wayNb then
				local n = 0
				for nq in pairs(s.wayNb) do if routeSet[nq] then n = n + 1 end end
				if n >= (cfg.roamHereNeighbours or 3) then return true end
			end
			if s.gather and #killsHere > 0 then
				for _, p in ipairs(s.points or {}) do
					for _, k in ipairs(killsHere) do
						local d = ns.Geo.Distance(k, p)
						if d and d <= camp then return true end
					end
				end
			end
		end
		return false
	end
	local routeSet
	local changed = true
	while changed do
		changed = false
		routeSet = {}
		for _, e in ipairs(state.route) do routeSet[e.stop.quest] = true end
		local best, bestR, bestT, bestRate, bestLoose
		local rate = worth(state, ctx) / math.max(60, state.total)
		for _, q in ipairs(pool) do
			ns.Check()
			if not state.used[q] then
				local r, t, firstPos = insertQuest(state.route, q, ctx)
				local added = r and t - state.total
				-- a quest whose giver you're standing at gets the loose rule in tight mode too: taking
				-- it now costs nothing, coming back for it later costs a trip (Scavenging Deathknell)
				local atGiver = false
				local first = q.stops[1]
				if first and first.kind == "pickup" and ctx.start then
					for _, p in ipairs(first.points or {}) do
						local d = ns.Geo.Distance(ctx.start, p)
						if d and d <= (cfg.hereTurninAtYards or 40) then atGiver = true break end
					end
				end
				-- (or a quest in your log whose ground pick-ups are among the mobs you're killing here)
				if not atGiver and r and gatherHere(q) then atGiver = true end
				local looseHere = ctx.loose or atGiver
				-- (at the giver: up to Config.overHorizonSeconds, like a quest that speeds the route up)
				local looseCap = atGiver and math.max(looseMax, maxExtra) or looseMax
				if r and added <= math.max(maxExtra, looseHere and looseCap or 0) then
					local qWork = 0
					for _, s in ipairs(q.stops) do qWork = qWork + (s.work or 0) end
					local m = (state.mobXp or 0) + mobOf(q)
					local gain = value(q) + restedWorth(m, ctx) - restedWorth(state.mobXp, ctx)
					local newRate = ((state.value or 0) + value(q) + restedWorth(m, ctx)) / math.max(60, t)
					local ok = added <= maxExtra and newRate > rate * 1.001
					local loose = false
					-- (on the way: little walking beyond the quest's own work, and inside the route - one
					-- tacked on after its end only makes the route longer)
					-- (at the giver, walking out to its objective is part of the quest: Config.giverDetourSeconds)
					local detourCap = atGiver and math.max(looseDetour, cfg.giverDetourSeconds or 120) or looseDetour
					if not ok and looseHere and added <= math.min(looseCap, looseLeft) and added - qWork <= detourCap
						and (atGiver or (firstPos and firstPos <= #state.route)) then
						ok = gain / math.max(1, added) >= rate0 * (atGiver and (cfg.giverMinShare or 0.3) or looseShare)
						loose = ok
					end
					if ok and (not bestRate or newRate > bestRate) then
						best, bestR, bestT, bestRate, bestLoose = q, r, t, newRate, loose
					end
				end
			end
		end
		if best then
			if bestLoose then looseLeft = looseLeft - (bestT - state.total) end
			state.used[best] = true
			state.route, state.total, state.xp = bestR, bestT, state.xp + best.xp
			state.value = (state.value or 0) + value(best)
			state.mobXp = (state.mobXp or 0) + mobOf(best)
			changed = true
		end
	end
	return state
end

-- Reverse route[i..j] in place (2-opt; call again to undo).
local function reverse(r, i, j)
	while i < j do r[i], r[j] = r[j], r[i] i, j = i + 1, j - 1 end
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

		if ns.cfg.segmentMoves ~= false then
			-- 2b. move a run of 2-3 stops in a row to its best place (or-opt): a camp and the turn-in
			--     next to it travel together, which single-stop moves can't do
			for len = 2, 3 do
				i = 1
				while i + len - 1 <= #state.route do
					ns.Check()
					local r0 = copy(state.route)
					local seg = {}
					for k = 1, len do seg[k] = table.remove(r0, i) end
					local bestPos, bestT = nil, state.total - 0.5
					for pos = 1, #r0 + 1 do
						if pos ~= i then
							ns.Check()
							for k = 1, len do table.insert(r0, pos + k - 1, seg[k]) end
							if feasible(r0, ctx) then
								local t = routeSeconds(r0, ctx)
								if t < bestT then bestPos, bestT = pos, t end
							end
							for _ = 1, len do table.remove(r0, pos) end
						end
					end
					if bestPos then
						for k = 1, len do table.insert(r0, bestPos + k - 1, seg[k]) end
						state.route, state.total, better = r0, bestT, true
					end
					i = i + 1
				end
			end

			-- 2c. walk a stretch of the route the other way round (2-opt): undoes zig-zags
			local span = ns.cfg.twoOptMaxSpan or 10
			local r = state.route
			for a = 1, #r - 1 do
				for b = a + 1, math.min(#r, a + span - 1) do
					ns.Check()
					reverse(r, a, b)
					local t = feasible(r, ctx) and routeSeconds(r, ctx)
					if t and t < state.total - 0.5 then
						state.total, better = t, true -- keep it
					else
						reverse(r, a, b)
					end
				end
			end
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

		local rate = worth(state, ctx) / math.max(1, state.total)
		for _, q in ipairs(questsIn(state.route)) do
			if state.used[q] and not hasDependents(state.route, q) then
				local r0 = removeQuest(state.route, q)
				local bestR, bestT, bestC, bestRate = nil, nil, nil, rate * 1.001
				for _, c in ipairs(unused) do
					ns.Check()
					if not state.used[c] then
						local r, t = insertQuest(r0, c, ctx)
						if r and t <= ctx.horizon * 1.25 then
							local m = (state.mobXp or 0) - mobOf(q) + mobOf(c)
							local newRate = ((state.value or 0) - value(q) + value(c) + restedWorth(m, ctx)) / math.max(1, t)
							if newRate > bestRate then bestR, bestT, bestC, bestRate = r, t, c, newRate end
						end
					end
				end
				if bestR then
					state.used[q], state.used[bestC] = nil, true
					state.route, state.total = bestR, bestT
					state.xp = state.xp - q.xp + bestC.xp
					state.value = (state.value or 0) - value(q) + value(bestC)
					state.mobXp = (state.mobXp or 0) - mobOf(q) + mobOf(bestC)
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
			-- (mid-fight with its mob, or standing among its mobs - Config.amongYards: finishing here
			-- comes first whatever the sums say)
			if fighting or bestD <= (ns.cfg.amongYards or 80) or t <= state.total + slack then
				state.route, state.total = r, t
			end
		end
	end
	-- the other objectives in this same camp (Rattlecage Skeletons among the scavengers and bats you're
	-- killing): right after it, nearest first - you're among their mobs now, later means coming back
	if campStop and state.route[1] and state.route[1].stop == campStop then
		local others = {}
		for i, e in ipairs(state.route) do
			if i > 1 and e.stop.kind == "objective" then
				local bestP2, bestD2
				for _, p in ipairs(e.stop.points) do
					local d = ns.Geo.Distance(ctx.start, p)
					if d and d <= near and (not bestD2 or d < bestD2) then bestP2, bestD2 = p, d end
				end
				if bestP2 then others[#others + 1] = { e = e, p = bestP2, d = bestD2 } end
			end
		end
		table.sort(others, function(a, b) return a.d < b.d end)
		-- (standing among its mobs - Config.amongYards: it comes next whatever the sums say; the
		-- route's own order put Rattlecage Skeletons you stood in at minute 27, next to the Scarlet camp)
		local among = ns.cfg.amongYards or 80
		local pos, budget = 2, state.total + slack
		for _, o in ipairs(others) do
			local r = copy(state.route)
			local from
			for i, x in ipairs(r) do if x == o.e then from = i break end end
			if from and from > pos then
				table.remove(r, from)
				table.insert(r, pos, { stop = o.e.stop, point = o.p })
				if feasible(r, ctx) then
					local t = routeSeconds(r, ctx)
					if o.d <= among then
						budget = budget + math.max(0, t - state.total) -- (its cost doesn't count against the others)
						state.route, state.total, pos = r, t, pos + 1
					elseif t <= budget then
						state.route, state.total, pos = r, t, pos + 1
					end
				end
			elseif from == pos then
				pos = pos + 1
			end
		end
	end

	-- Turn-ins close by (the town you're standing in) go first too, nearest first: putting them off
	-- "until you're back" looks free on paper, but the XP and follow-ups are wanted now.
	local turnNear = ns.cfg.hereTurninYards or 400
	-- ...but not when a camp of the route is nearer than they are: you're at the mobs, so farm first
	-- and hand in on the way (camp spawns spread wide; its map point can be out past sameCampYards
	-- while you're already among them)
	local campD
	for _, e in ipairs(state.route) do
		-- (a camp of mobs to kill - not NPCs you visit, like Discipline's Deathguards around Brill's inn)
		if e.stop.kind == "objective" and (e.stop.mobXp or 0) > 0 then
			for _, p in ipairs(e.stop.points) do
				local d = ns.Geo.Distance(ctx.start, p)
				if d and (not campD or d < campD) then campD = d end
			end
		end
	end
	-- (standing at the NPC: hand it in now, before anything - Config.hereTurninAtYards)
	local atYards = ns.cfg.hereTurninAtYards or 40
	local list = {}
	for i, e in ipairs(state.route) do
		if e.stop.kind == "turnin" then
			local d = ns.Geo.Distance(ctx.start, e.point)
			if d and (d <= atYards or (d <= turnNear and not (campD and campD < d))) then
				list[#list + 1] = { stop = e.stop, d = d, at = d <= atYards }
			end
		end
	end
	table.sort(list, function(a, b) return a.d < b.d end)
	-- the camp you're standing in stays first: finish the kills here, then walk to the turn-ins
	local campFirst = campStop ~= nil and state.route[1] ~= nil and state.route[1].stop == campStop
	local pos = campFirst and 2 or 1
	local atPos = 1
	for _, c in ipairs(list) do
		local r = copy(state.route)
		local from
		for i, e in ipairs(r) do if e.stop == c.stop then from = i break end end
		if c.at then
			-- right here: to the very front (after any other one you're standing at)
			if from and from > atPos then
				local e = table.remove(r, from)
				table.insert(r, atPos, e)
				if feasible(r, ctx) then
					state.route, state.total = r, routeSeconds(r, ctx)
					atPos = atPos + 1
				end
			elseif from == atPos then
				atPos = atPos + 1
			end
			-- (the rest go after these - and after the camp you're in, which moved back by one)
			pos = atPos + (campFirst and 1 or 0)
		elseif from and from > pos then
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
	state.mobXp = 0
	for _, q in ipairs(questsIn(whole)) do
		state.used[q] = true
		state.xp = state.xp + (q.xp or 0)
		state.value = state.value + value(q)
		state.mobXp = state.mobXp + mobOf(q)
	end
	return topUp(greedyFill(state, pool, ctx), pool, ctx)
end

----------------------------------------------------------------------------------------
-- Optional stops (trainer, vendor/repair, hearthstone at the hub, flight paths): each is added
-- where it fits best, only when the detour is short and XP per minute - counting what the stop
-- saves or gains later - goes up.
----------------------------------------------------------------------------------------
local standingAt, addExtrasInner -- (below)
local function addExtras(state, ctx)
	return standingAt(addExtrasInner(state, ctx), ctx)
end

-- A turn-in or extra stop (set your hearthstone, vendor, trainer) whose NPC you're standing at
-- (Config.hereTurninAtYards) goes first: you're there now, later means coming back.
standingAt = function(state, ctx)
	if not ctx.start or #state.route < 2 then return state end
	local atYards = ns.cfg.hereTurninAtYards or 40
	-- (/lp debug: how far the set-hearthstone step is, and whether it moved)
	for _, e in ipairs(state.route) do
		if e.stop.quest.id == "bind" and ns.Extras then
			local d = ns.Geo.Distance(ctx.start, e.point)
			ns.Extras.bindAt = d and string.format("%d yd from you", math.floor(d)) or "distance unknown (another map?)"
		end
	end
	-- the stops you're standing at, in route order; each moves to the front unless the rules forbid
	-- it there (a trainer visit that waits for your level-up stays put - the others still move)
	local at = {}
	for _, e in ipairs(state.route) do
		if e.stop.kind == "turnin" or e.stop.kind == "pickup" or e.stop.quest.isExtra then
			local d = ns.Geo.Distance(ctx.start, e.point)
			if d and d <= atYards then at[#at + 1] = e end
		end
	end
	local pos = 1
	for _, e in ipairs(at) do
		local from
		for i, x in ipairs(state.route) do if x == e then from = i break end end
		if from and from > pos then
			local r = copy(state.route)
			table.remove(r, from)
			table.insert(r, pos, e)
			failWhy = nil
			if feasible(r, ctx) then
				state.route, state.total = r, routeSeconds(r, ctx)
				pos = pos + 1
			elseif e.stop.quest.id == "bind" and ns.Extras then
				ns.Extras.bindAt = (ns.Extras.bindAt or "") .. ", not moved first: " .. (failWhy or "?")
			end
		elseif from == pos then
			pos = pos + 1
		end
	end
	return state
end

function addExtrasInner(state, ctx)
	if not ctx.start or #state.route == 0 then return state end
	-- a level-up on the way: a trainer visit that falls due then can go right after it (Extras.lua)
	ctx.dingLevel = dingIndex(state.route, ctx) and (ctx.level or 0) + 1 or nil
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
			elseif q.id == "bind" and ns.Extras then
				-- (/lp debug says why the suggested inn didn't make it)
				ns.Extras.bindWhy = (ns.Extras.bindWhy or "") .. (r and string.format(" - but left out: +%ds detour", math.floor(t - state.total))
					or (" - but left out: " .. (failWhy or "no place in the route")))
			end
		end
	end
	return state
end

----------------------------------------------------------------------------------------
-- Where the route ends: a small bonus when it ends near good quests it didn't take (a hub you
-- carry on from), scaled down when the quest log is too full to take them. Capped at
-- Config.endBonusMaxShare of the route's own value, so it only settles near-ties.
----------------------------------------------------------------------------------------
local function endBonus(route, ctx, routeValue)
	local cfg = ns.cfg
	local cap = (cfg.endBonusMaxShare or 0.03) * (routeValue or 0)
	if cap <= 0 or #route == 0 or not ctx.pool then return 0 end
	local last = route[#route].point
	local radius = cfg.endHubYards or 300
	local inRoute, logEnd = {}, ctx.logCount or 0
	for _, e in ipairs(route) do
		inRoute[e.stop.quest] = true
		logEnd = logEnd + (e.stop.logDelta or 0)
	end
	local near = 0
	for _, q in ipairs(ctx.pool) do
		ns.Check()
		local s = not inRoute[q] and q.stops and q.stops[1]
		if s and s.points then
			for _, p in ipairs(s.points) do
				local d = ns.Geo.Distance(last, p)
				if d and d <= radius then near = near + value(q) break end
			end
		end
	end
	local room = math.max(0, math.min(1, ((ctx.logCap or 20) - logEnd) / (cfg.endLogRoom or 4)))
	return math.min(cap, near * (cfg.endHubValueShare or 0.1) * room)
end

-- What routes are compared on before the step list exists (value per second, end bonus included).
local function rateOf(state, ctx)
	local w = worth(state, ctx)
	return (w + endBonus(state.route, ctx, w)) / math.max(60, state.total)
end

-- Deterministic random numbers (same situation, same plan: re-plans don't flicker). rand(n) = 1..n
local function rng(seed)
	local s = math.floor(seed) % 2147483646 + 1
	return function(n)
		s = (s * 16807) % 2147483647
		return 1 + s % n
	end
end

----------------------------------------------------------------------------------------
-- Final step list: travel legs (hearth, flights, boats, passes) before each stop
----------------------------------------------------------------------------------------
local function finalize(state, ctx)
	local cfg = ns.cfg
	local route, start = state.route, ctx.start
	local wayIn -- (the along-the-way share, as routeSeconds counts it)
	if ctx.wayOn then
		wayIn = {}
		for _, e in ipairs(route) do wayIn[e.stop.quest] = true end
	end
	local hearthSecs = cfg.hearthSeconds or 45
	-- level-up on the way: legs after it are ridden when it reaches your mount level (as in routeSeconds)
	local ding = dingIndex(route, ctx)
	local dingsAt = {} -- [stop index] = the level it takes you to, for the 2nd, 3rd... level-up
	for k = 2, #(ctx.dingNeeds or {}) do
		local d = dingIndex(route, ctx, k)
		if d then dingsAt[d] = (ctx.level or 0) + k end
	end
	local function legSeconds(idx, a, b)
		if ding and idx > ding and ctx.mountSpeed and a then return ns.Travel.Seconds(a, b, ctx.mountSpeed) end
		return travel(a, b)
	end

	-- hearthstone: used on the legs where it saves the most time, once per cooldown. A saving later in
	-- the route counts for less (the route is re-planned as you go, so a later leg may never happen):
	-- a sure saving now beats a slightly bigger one in 40 minutes.
	local hearth = ns.Travel.Hearth()
	local hearthLegs = {}
	if hearth then
		local cands = {}
		local t, prev = ctx.corpseSecs or 0, start
		local later = cfg.hearthLaterDiscount or 0.5
		for idx, e in ipairs(route) do
			local normal = legSeconds(idx, prev, e.point)
			if t >= hearth.readyIn then
				local save = normal - (hearthSecs + travel(hearth.point, e.point))
				if save > 0 then
					cands[#cands + 1] = { idx = idx, t = t, score = save * (1 - later * math.min(1, t / ctx.horizon)) }
				end
			end
			t = t + normal + (e.stop.work or 0) * (e.point.workFactor or 1)
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
	local xpAdj = 0
	local arrived = (cfg.arrivedYards or 15) * 2
	local t, prev, prevEntry, run = 0, start, nil, 0
	-- a ghost runs back to the corpse first; the route itself starts there (ctx.start = the corpse)
	if ctx.corpseSecs then
		steps[1] = { kind = "travel", mode = "corpse", label = "Run back to your corpse", point = start,
			work = ctx.corpseSecs, arrive = ctx.corpseSecs, mobXp = 0 }
		t = ctx.corpseSecs
	end
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
		t = t + legSeconds(idx, from, e.point)
		-- the giver of a now-and-then quest isn't there yet: wait for him
		local wait = e.stop.quest.timedFrom and timedWait(e.stop, t, ctx) or 0
		if wait > 0 and wait < MISSED then
			steps[#steps + 1] = { kind = "travel", mode = "wait", point = e.point, work = wait, arrive = t, mobXp = 0,
				label = string.format("Wait for %s (~%d min)", (ns.TimedQuests and ns.TimedQuests[e.stop.quest.id]
					and ns.TimedQuests[e.stop.quest.id].npcName) or "the quest giver", math.ceil(wait / 60)) }
			t = t + wait
		end
		e.arrive = t
		-- a per-plan view of the stop (the stop itself is shared between the plans being compared)
		local view = setmetatable({ point = e.point, arrive = t }, { __index = e.stop })
		steps[#steps + 1] = view
		-- kills in this area: its own mobs' level (Stops.lua: point.xpFactor, point.level)
		local mx = e.stop.mobXp or 0
		if mx > 0 and e.point.xpFactor then
			view.mobXp = mx * e.point.xpFactor
			xpAdj = xpAdj + view.mobXp - mx
			mx = view.mobXp
		end
		local mobLevel = e.point.level or e.stop.mobLevel
		if ding and idx > ding and mx > 0 and mobLevel and ns.Estimate then
			-- after the level-up the same kills give a little less (or nothing, once grey)
			local E = ns.Estimate
			local now = E.MobXP(mobLevel, e.stop.mobRank)
			if now > 0 then
				view.mobXp = mx * E.MobXP(mobLevel, e.stop.mobRank, nil, (ctx.level or 0) + 1) / now
				xpAdj = xpAdj + view.mobXp - mx
			end
		end
		if idx == ding then view.dingTo = (ctx.level or 0) + 1 end
		if dingsAt[idx] then view.dingTo = dingsAt[idx] end
		keys[#keys + 1] = { key = e.stop.key, wx = e.point.wx, wy = e.point.wy, inst = e.point.inst }
		local w
		w, run = addedWork(prevEntry, e, run, start, nil, wayIn)
		t = t + w
		prev, prevEntry = e.point, e
	end

	local xp = state.xp + xpAdj
	-- rested bonus on the route's kills (after the level-up re-pricing): counted in the score; the
	-- step list adds it to what it shows from the live pool (Estimate.RestedBonus, same rule)
	local kills = 0
	for _, s in ipairs(steps) do kills = kills + (s.mobXp or 0) end
	local rested = restedWorth(kills, ctx)
	local w = (state.value or state.xp) + xpAdj * (cfg.mobXpWeight or 1) + rested
	local bonus = endBonus(route, ctx, w)
	return {
		stops = steps,
		keys = keys,
		route = route,
		xp = xp,                                              -- real XP, shown in the list (rested not included)
		seconds = t,
		rate = t > 0 and xp / (t / 60) or 0,                  -- real XP per minute, shown
		score = t > 0 and (w + bonus) / (t / 60) or 0,        -- what routes are compared on
		endBonus = bonus,
		restedPool = ctx.rested or 0,                         -- (Core re-plans when it runs out)
		restedBonus = rested,
		corpseRun = ctx.corpseSecs ~= nil,
		dingAt = ding,
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
	tcache = setmetatable({}, { __mode = "k" }) -- (fresh travel times: you've moved, flights learned...)
	-- opts.quick: the plain search only (the job runner asks for it when a full search took too long)
	local quick = opts and opts.quick
	local ctx = {
		start = ns.Geo.PlayerPoint(),
		targetNpc = (function() local ok, id = pcall(P.TargetNpc) return ok and id or nil end)(), -- (the mob you're fighting: its objective goes first, see hereFirst)
		horizon = (cfg.horizonMinutes or 60) * 60,
		logCount = ns.QuestSource.LogCount(),
		logCap = ns.QuestSource.LogCap and ns.QuestSource.LogCap() or 20,
		bagFree = ns.QuestSource.FreeBagSlots() - (cfg.bagReserveSlots or 2),
		level = ns.playerLevel and ns.playerLevel() or 1,
		hearthSecs = cfg.hearthSeconds or 45,
		loose = ns.PickupMode and ns.PickupMode() == "loose", -- (quick quests on the way too: topUp)
		-- the current plan's XP per second: what XP counted twice is worth in time (addedWork)
		xpRate = (ns.plan and (ns.plan.rate or 0) > 0) and ns.plan.rate / 60 or 0,
		now = GetServerTime and GetServerTime() or nil, -- (for quests offered only now and then)
		-- rested XP: kills give double until it's used up (counted in route value and level-ups)
		rested = (cfg.plannerRested ~= false and ns.Estimate and ns.Estimate.RestedPool) and ns.Estimate.RestedPool() or 0,
	}
	-- XP still needed for the next level: the route levels you up when its XP gets there (then quests
	-- of the next level open, kills give a bit less, the trainer may be due, and you may ride)
	if cfg.planLevelUps ~= false and UnitXP and UnitXPMax then
		local cur, max = UnitXP("player"), UnitXPMax("player")
		local secret = ns.isSecret and (ns.isSecret(cur) or ns.isSecret(max))
		local cap = GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
		if not secret and type(cur) == "number" and type(max) == "number" and max > 0 and ctx.level < cap then
			ctx.toDing = math.max(1, max - cur)
			-- and the levels after it (several level-ups in one route at low levels)
			ctx.dingNeeds = { ctx.toDing }
			for k = 2, 4 do
				local per = ns.Estimate and ns.Estimate.XpToNext and ns.Estimate.XpToNext(ctx.level + k - 1)
				if not per or ctx.level + k > cap then break end
				ctx.dingNeeds[k] = ctx.dingNeeds[k - 1] + per
			end
		end
	end
	-- the level-up reaches your mount level: legs after it are ridden
	if ctx.toDing and cfg.mountLevel and ctx.level < cfg.mountLevel and ctx.level + 1 >= cfg.mountLevel then
		ctx.mountSpeed = cfg.mountSpeed or 11.2
	end
	-- dead and released: the run back to the corpse comes first, and the route is planned from the
	-- corpse (that's where you'll be once you're alive again)
	if UnitIsGhost and UnitIsGhost("player") and ns.Waypoint and ns.Waypoint.CorpsePoint then
		local ok, corpse = pcall(ns.Waypoint.CorpsePoint)
		if ok and corpse and ctx.start then
			local secs = ns.Travel.WalkSeconds and ns.Travel.WalkSeconds(ctx.start, corpse, cfg.runSpeed or 7)
			if not secs or secs == math.huge then secs = ns.Travel.Seconds(ctx.start, corpse) end
			ctx.corpseSecs = math.max(1, secs)
			ctx.start, ctx.targetNpc = corpse, nil
		end
	end
	-- the hearthstone counts in every route's time, not only in the final step list
	if cfg.hearthInRoute ~= false then
		local ok, h = pcall(ns.Travel.Hearth)
		if ok and h and h.point then ctx.hearth = h end
	end

	local pool = {}
	for _, list in ipairs({ candidates and candidates.log or {}, candidates and candidates.available or {},
			candidates and candidates.locked or {}, candidates and candidates.upcoming or {} }) do
		for _, q in ipairs(list) do
			if not ns.skipped[q.id] then pool[#pool + 1] = q end
		end
	end
	ctx.pool = pool -- (escortFirst looks here for an escort you have started)
	-- which kill / gather steps lie among other quests' steps (along the way: P.WayShare)
	ctx.wayOn = cfg.alongTheWay ~= false and P.WayNeighbours(pool) or nil

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

	-- The search: the plain greedy route, then other starting routes (regret insertion, and a few
	-- randomized greedy ones), each polished by improve(). A start replaces the plain one only when
	-- it ends up clearly better.
	local function empty() return { route = {}, total = 0, xp = 0, value = 0, used = {} } end
	local function search(list)
		local best = topUp(improve(greedyFill(empty(), list, ctx), list, ctx), list, ctx)
		local bestRate = rateOf(best, ctx)
		local starts = {}
		if quick then return best end
		if cfg.regretStart ~= false then starts[#starts + 1] = { regret = true } end
		for k = 1, (cfg.graspStarts or 2) do
			starts[#starts + 1] = { topK = cfg.graspTopK or 3, rand = rng(#list * 7919 + k * 104729) }
		end
		for _, o in ipairs(starts) do
			local s = topUp(improve(greedyFill(empty(), list, ctx, o), list, ctx), list, ctx)
			local r = rateOf(s, ctx)
			if r > bestRate * 1.001 then best, bestRate = s, r end
		end
		return best
	end

	local fresh = addExtras(hereFirst(fillWithGrind(search(pool)), ctx), ctx)
	local plan = finalize(fresh, ctx)
	local chosen = fresh -- (the route behind the plan, for P.Diagnose)

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
		if altPlan.score > plan.score or (grouped and altPlan.score > plan.score * 0.9) then plan, chosen = altPlan, alt end
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
			plan, chosen = keep, carried
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
	P.last = { state = chosen, ctx = ctx, pool = pool }
	return plan
end

-- /lp why, for a planned quest that isn't first: how far its first objective is from you, and what
-- moving it to the front of the route would cost (or the rule that stops it). Returns lines.
function P.WhyNotFirst(questId)
	local last = P.last
	if not last then return nil end
	local state, ctx = last.state, last.ctx
	local fromI, e
	for i, x in ipairs(state.route) do
		if x.stop.quest.id == questId and x.stop.kind == "objective" then fromI, e = i, x break end
	end
	if not e then return nil end
	local bestP, bestD
	for _, p in ipairs(e.stop.points) do
		local d = ctx.start and ns.Geo.Distance(ctx.start, p)
		if d and (not bestD or d < bestD) then bestP, bestD = p, d end
	end
	local out = {}
	out[#out + 1] = bestD and string.format("  Its objective (%s): nearest of %d area(s) is %d yd from you; the route uses one %d yd away.",
		e.stop.label or "?", #e.stop.points, math.floor(bestD), math.floor(ns.Geo.Distance(ctx.start, e.point) or -1))
		or "  Its objective's areas aren't on your map."
	if fromI > 1 and bestP then
		local r = copy(state.route)
		table.remove(r, fromI)
		table.insert(r, 1, { stop = e.stop, point = bestP })
		failWhy = nil
		if not feasible(r, ctx) then
			out[#out + 1] = "  It can't go first: " .. (failWhy or "?") .. "."
		else
			out[#out + 1] = string.format("  Doing it first would make the route %+ds (%s).", math.floor(routeSeconds(r, ctx) - state.total),
				bestD <= (ns.cfg.amongYards or 80) and "you're among its mobs, so it should be first"
				or bestD <= (ns.cfg.sameCampYards or 200) and "in your camp: first if that costs under 90 s"
				or "too far to count as your camp")
		end
	end
	return out
end

-- /lp why: what the planner makes of a quest it didn't plan - the rule that keeps it out, or what
-- it would add to the current route against the route's own XP per minute. Returns lines.
function P.Diagnose(questId)
	local last = P.last
	if not last then return nil end
	local q
	for _, c in ipairs(last.pool) do if c.id == questId then q = c break end end
	if not q then return { "  The planner didn't get it as a candidate (/lp debug lists why quests drop out)." } end
	local state, ctx = last.state, last.ctx
	if state.used[q] then return { "  It's in the route." } end
	local out = {}
	local inRoute = {}
	for _, e in ipairs(state.route) do inRoute[e.stop.quest] = true end
	for _, s in ipairs(q.stops) do
		-- (along the way: how many quests of the route have steps among its mobs, and the time that saves)
		local way = ""
		if s.wayNb then
			local n, total = 0, 0
			for nq in pairs(s.wayNb) do
				total = total + 1
				if inRoute[nq] then n = n + 1 end
			end
			way = string.format(", along the way: %d of %d nearby quests in the route, -%d%%%s", n, total,
				math.floor(P.WayShare(s, inRoute) * 100), s.roam and " (roams the zone)" or "")
		end
		out[#out + 1] = string.format("  step: %s - %ds work, %d place(s)%s%s", s.label or s.key, math.floor(s.work or 0),
			#(s.points or {}), (s.bagDelta or 0) ~= 0 and string.format(", bags %+d", s.bagDelta) or "", way)
	end
	failWhy = nil
	local r, t = insertQuest(state.route, q, ctx)
	if not r then
		out[#out + 1] = "  Can't fit in the route: " .. (failWhy or "unknown reason") .. "."
		return out
	end
	local added = math.max(1, t - state.total)
	local qRate = value(q) / added * 60
	-- (the planner's figures count follow-ups a quest opens: say how much of the route that is)
	local chain = 0
	for _, c in ipairs(questsIn(state.route)) do chain = chain + (c.chainValue or 0) end
	if chain > 0 then
		out[#out + 1] = string.format("  The route's value includes %s for follow-ups its quests open (%s XP itself).",
			ns.short(chain), ns.short(state.xp or 0))
	end
	local planRate = worth(state, ctx) / math.max(60, state.total) * 60
	out[#out + 1] = string.format("  Adding it: +%s for %s XP (~%d XP/min); the route makes ~%d XP/min over %s.",
		ns.minutes(added), ns.short(value(q)), math.floor(qRate), math.floor(planRate), ns.minutes(state.total))
	-- the "you're at its giver" rule (topUp): what it sees
	local first = q.stops[1]
	if first and first.kind == "pickup" then
		local gd
		for _, p in ipairs(first.points or {}) do
			local d = ctx.start and ns.Geo.Distance(ctx.start, p)
			if d and (not gd or d < gd) then gd = d end
		end
		local qWork = 0
		for _, s in ipairs(q.stops) do qWork = qWork + (s.work or 0) end
		local cfg = ns.cfg
		out[#out + 1] = string.format("  At-the-giver rule: giver %s from you (needs %d); adds %ds (max %d), %ds beyond its own work (max %d); %d%% of the route's rate (needs %d%%).",
			gd and (math.floor(gd) .. " yd") or "not on your map", cfg.hereTurninAtYards or 40,
			math.floor(added), math.max(cfg.looseMaxSeconds or 180, cfg.overHorizonSeconds or 300),
			math.floor(added - qWork), math.max(cfg.looseDetourSeconds or 60, cfg.giverDetourSeconds or 120),
			math.floor(qRate / math.max(1, planRate) * 100), math.floor((cfg.giverMinShare or 0.3) * 100))
	elseif first then
		-- a quest in your log with ground pick-ups: are they among the route's kills where you are?
		local camp, gd = ns.cfg.sameCampYards or 200, nil
		for _, e in ipairs(state.route) do
			local here = e.stop.mobs and ctx.start and ns.Geo.Distance(ctx.start, e.point)
			if here and here <= camp then
				for _, s in ipairs(q.stops) do
					for _, p in ipairs(s.gather and s.points or {}) do
						local d = ns.Geo.Distance(e.point, p)
						if d and (not gd or d < gd) then gd = d end
					end
				end
			end
		end
		if gd then
			out[#out + 1] = string.format("  Gather-here rule: its pick-ups are %d yd from a kill step near you (needs %d); then it's taken like a quest at its giver.",
				math.floor(gd), camp)
		end
	end
	return out
end
