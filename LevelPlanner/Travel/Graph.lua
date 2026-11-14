-- Travel graph: zone crossings, passes, boats, zeppelins, the Deeprun Tram and your known flight paths,
-- joined by walking. Shortest times between all graph nodes are worked out once (Floyd-Warshall,
-- spread over frames); any two map points are then joined through their nearby nodes.
local ADDON, zyde = ...
-- Part of Zyde_Forever since 2026-11-14: LevelPlanner keeps its own private table (zyde.LP) so its
-- names never clash with Zyde's.
zyde.LP = zyde.LP or {}
local ns = zyde.LP

local T = {}
ns.Travel = T

local INF = math.huge
local version = 1      -- bumped whenever learned data changes
local graph            -- built graph
local buildId = 0
local HEARTHSTONE_ITEM = 6948

function T.Invalidate() version = version + 1 end

----------------------------------------------------------------------------------------
-- Walking between two points (or nodes)
----------------------------------------------------------------------------------------
local function shares(a, b)
	if a.maps then
		if b.maps then
			for m in pairs(a.maps) do if b.maps[m] then return true end end
			return false
		end
		return a.maps[b.map] or false
	end
	if b.maps then return b.maps[a.map] or false end
	return a.map ~= nil and a.map == b.map
end

local function walkSeconds(a, b, speed)
	local d = ns.Geo.Distance(a, b)
	if not d then return INF end
	local cfg = ns.cfg
	local t = d * ns.TravelLearn.DetourBetween(a, b) / speed -- learned per zone (Travel/Learn.lua)
	if not shares(a, b) then
		t = t * (cfg.crossZoneWalkFactor or 1.6) + (cfg.zoneChangeSeconds or 30)
	end
	return t
end
T.WalkSeconds = walkSeconds

----------------------------------------------------------------------------------------
-- Building the graph
----------------------------------------------------------------------------------------
local function setOf(...)
	local s = {}
	for i = 1, select("#", ...) do
		local m = select(i, ...)
		if m then s[m] = true end
	end
	return s
end

local function npcPoint(npcId, expectedName)
	local QS = ns.QuestSource
	local name = QS.Npc(npcId, "name")
	if expectedName and name ~= expectedName then return nil end
	local spawns = QS.Npc(npcId, "spawns")
	if type(spawns) ~= "table" then return nil end
	for areaId, list in pairs(spawns) do
		for _, c in ipairs(list) do
			local p = ns.Geo.Point(areaId, c[1], c[2])
			if p then return p end
		end
	end
	return nil
end

local function build(speed)
	local cfg = ns.cfg
	local faction = UnitFactionGroup("player")
	local Seeds, Learn = ns.TravelSeeds, ns.TravelLearn
	local nodes, edges = {}, {}

	local function addNode(p, name, kind, maps)
		if not p then return nil end
		local n = { name = name, kind = kind, maps = maps or setOf(p.map),
			map = p.map, x = p.x, y = p.y, wx = p.wx, wy = p.wy, inst = p.inst }
		nodes[#nodes + 1] = n
		n.i = #nodes
		return n
	end
	local function addEdge(a, b, seconds, kind, both)
		if not (a and b) then return end
		edges[#edges + 1] = { a = a.i, b = b.i, s = seconds, kind = kind }
		if both then edges[#edges + 1] = { a = b.i, b = a.i, s = seconds, kind = kind } end
	end

	-- zone crossings: seeds, then learned ones
	for _, c in ipairs(Seeds.crossings) do
		if c.exit then
			-- a pass with two ends: one node on each side, joined by the pass itself
			local a = addNode(ns.Geo.PointOnMap(c.map, c.x, c.y), c.name, "pass", setOf(c.map))
			local b = addNode(ns.Geo.PointOnMap(c.exit.map, c.exit.x, c.exit.y), c.name, "pass", setOf(c.exit.map))
			if a and b then
				local d = ns.Geo.Distance(a, b)
				if d then addEdge(a, b, d * 1.1 / speed, "walk", true) end
			end
		else
			addNode(ns.Geo.PointOnMap(c.map, c.x, c.y), c.name, c.pass and "pass" or "border", setOf(c.map, c.other))
		end
	end
	for _, b in ipairs(Learn.Borders()) do
		addNode(ns.Geo.PointOnMap(b.map, b.x, b.y), "zone crossing", "border", setOf(b.mapA, b.mapB))
	end
	ns.Check()

	-- boats and zeppelins
	local ts = cfg.transportSeconds or {}
	for _, tr in ipairs(Seeds.transports) do
		if not tr.faction or tr.faction == faction then
			local function endNode(e)
				local p = (e.npc and npcPoint(e.npc, e.npcName)) or ns.Geo.PointOnMap(e.map, e.x, e.y)
				return addNode(p, e.name, "dock")
			end
			local a, b = endNode(tr.a), endNode(tr.b)
			addEdge(a, b, ts[tr.kind] or 240, tr.kind, true)
		end
	end

	-- Deeprun Tram, from Questie's dungeon entrances
	if faction == "Alliance" and ns.Q.ZoneDB and ns.Q.ZoneDB.GetDungeons then
		local dungeons = ns.safe(ns.Q.ZoneDB.GetDungeons, ns.Q.ZoneDB)
		local tram = dungeons and dungeons[Seeds.DEEPRUN_TRAM_AREA]
		local ends = tram and tram[4]
		if type(ends) == "table" and #ends >= 2 then
			local a = addNode(ns.Geo.Point(ends[1][1], ends[1][2], ends[1][3]), "Deeprun Tram (Stormwind)", "dock")
			local b = addNode(ns.Geo.Point(ends[2][1], ends[2][2], ends[2][3]), "Deeprun Tram (Ironforge)", "dock")
			addEdge(a, b, ts.tram or 150, "tram", true)
		end
	end

	-- your flight paths
	local money = GetMoney and GetMoney() or 0
	-- one network: a flight path learned both at a flight master and from the map is one node
	local taxiNodes, taxiSeen = {}, {}
	for contMap, list in pairs(Learn.KnownTaxi()) do
		for name, pos in pairs(list) do
			local p = not taxiSeen[name] and ns.Geo.PointOnMap(contMap, pos.x * 100, pos.y * 100)
			if p then taxiSeen[name] = true end
			if p then
				-- keep the point on its zone map, so waypoints land in the right place
				local zone = ns.Geo.ZoneAt(contMap, pos.x, pos.y)
				local zx, zy = ns.Geo.ZoneCoords(p, zone)
				if zx then p.map, p.x, p.y = zone, zx, zy end
				taxiNodes[#taxiNodes + 1] = addNode(p, name, "taxi", setOf(zone))
			end
		end
		ns.Check()
	end
	do
		for _, a in ipairs(taxiNodes) do
			for _, b in ipairs(taxiNodes) do
				if a ~= b and a.inst == b.inst then
					local d = ns.Geo.Distance(a, b) or 0
					local secs = Learn.FlightTime(a.name, b.name)
						or d * (cfg.flightRouteFactor or 1.25) / (cfg.flightSpeed or 30)
					local cost = Learn.FlightCost(a.name, b.name) or d * (cfg.flightCopperPerYard or 0.6)
					if cost <= money then
						secs = secs + (cfg.flightOverheadSeconds or 20) + cost / 10000 * (cfg.flightSecondsPerGold or 60)
						addEdge(a, b, secs, "fly", false)
					end
				end
			end
		end
		ns.Check()
	end

	-- distance matrix: walking between every pair, then the special edges
	local N = #nodes
	local D, nxt, kind = {}, {}, {}
	for i = 1, N do
		local Di, ni, ki = {}, {}, {}
		for j = 1, N do
			if i == j then
				Di[j] = 0
			else
				Di[j] = walkSeconds(nodes[i], nodes[j], speed)
			end
			ni[j] = j
			ki[j] = "walk"
		end
		D[i], nxt[i], kind[i] = Di, ni, ki
		ns.Check()
	end
	for _, e in ipairs(edges) do
		if e.s < D[e.a][e.b] then
			D[e.a][e.b] = e.s
			kind[e.a][e.b] = e.kind
		end
	end

	-- all-pairs shortest times
	for k = 1, N do
		local Dk = D[k]
		for i = 1, N do
			local Di = D[i]
			local dik = Di[k]
			if dik < INF then
				local ni = nxt[i]
				for j = 1, N do
					local alt = dik + Dk[j]
					if alt < Di[j] then
						Di[j] = alt
						ni[j] = ni[k]
					end
				end
			end
		end
		ns.Check()
	end

	buildId = buildId + 1
	return { id = buildId, version = version, speed = speed, faction = faction,
		nodes = nodes, D = D, nxt = nxt, kind = kind, N = N }
end

-- Rebuilds the graph when learned data, speed or faction changed. Call inside a job.
function T.Prepare()
	local speed = ns.Geo.Speed()
	if graph and graph.version == version and graph.speed == speed then return end
	graph = build(speed)
	ns.dprint(string.format("travel graph: %d nodes", graph.N))
end

----------------------------------------------------------------------------------------
-- Points to the graph
----------------------------------------------------------------------------------------

-- Nodes reachable on foot from a point without guessing: same zone, else the 3 nearest.
local function access(p)
	if p._accId == graph.id then return p._acc end
	local acc, nodes, speed = {}, graph.nodes, graph.speed
	for _, n in ipairs(nodes) do
		if n.inst == p.inst and shares(p, n) then
			acc[#acc + 1] = { i = n.i, w = walkSeconds(p, n, speed) }
		end
	end
	if #acc == 0 then
		local near = {}
		for _, n in ipairs(nodes) do
			if n.inst == p.inst then near[#near + 1] = { i = n.i, w = walkSeconds(p, n, speed) } end
		end
		table.sort(near, function(a, b) return a.w < b.w end)
		for k = 1, math.min(3, #near) do acc[k] = near[k] end
	end
	p._acc, p._accId = acc, graph.id
	return acc
end

-- Best time from a point to every node, and the first node used.
local function reach(p)
	if p._reachId == graph.id then return p._reach, p._via end
	local r, via = {}, {}
	for j = 1, graph.N do r[j] = INF end
	for _, e in ipairs(access(p)) do
		local Du = graph.D[e.i]
		for j = 1, graph.N do
			local t = e.w + Du[j]
			if t < r[j] then r[j], via[j] = t, e.i end
		end
	end
	p._reach, p._via, p._reachId = r, via, graph.id
	return r, via
end

-- Seconds from a to b by the fastest known way (without the hearthstone).
function T.Seconds(a, b)
	if not a or not b then return 0 end
	if not graph then return ns.Geo.TravelSeconds(a, b) end
	local best = walkSeconds(a, b, graph.speed)
	if graph.N > 0 then
		local r = reach(a)
		for _, e in ipairs(access(b)) do
			local t = r[e.i] + e.w
			if t < best then best = t end
		end
	end
	if best == INF then best = ns.cfg.continentChangeSeconds or 900 end
	return best
end

local LABEL = {
	fly = "Fly to %s",
	boat = "Take the boat to %s",
	zeppelin = "Take the zeppelin to %s",
	tram = "Take the tram to %s",
	portal = "Take the portal to %s",
}

-- The steps worth showing on the way from a to b: flights, boats, zeppelins, tram and named passes.
-- Each step: {mode, label, point (where to go for it), seconds}.
function T.Legs(a, b)
	local legs = {}
	if not (graph and a and b and graph.N > 0) then return legs end
	local direct = walkSeconds(a, b, graph.speed)
	local r, via = reach(a)
	local bestT, bestV = direct, nil
	for _, e in ipairs(access(b)) do
		local t = r[e.i] + e.w
		if t < bestT then bestT, bestV = t, e.i end
	end
	if not bestV then return legs end

	local nodes, nxt, kind, D = graph.nodes, graph.nxt, graph.kind, graph.D
	local i = via[bestV]
	local prevMap, lastPass = a.map, nil
	local guard = 0
	while i and guard < 200 do
		guard = guard + 1
		local n = nodes[i]
		if n.kind == "pass" then
			-- the second end of a two-ended pass is its exit
			local exit = lastPass == n.name
			legs[#legs + 1] = { mode = "pass", point = n, seconds = 0,
				label = exit and (n.name .. " exit") or ("Go through " .. n.name) }
			lastPass = n.name
			prevMap = n.map or prevMap
		elseif n.kind == "border" then
			-- a zone crossing: the step names the zone you're heading into
			local into
			for m in pairs(n.maps or {}) do
				if m ~= prevMap then into = m end
			end
			local info = into and C_Map.GetMapInfo(into)
			legs[#legs + 1] = { mode = "border", point = n, seconds = 0,
				label = "Into " .. (info and info.name or "the next zone") .. " (zone border)" }
			prevMap = into or prevMap
			lastPass = nil
		else
			lastPass = nil
		end
		if i == bestV then break end
		local j = nxt[i][bestV]
		local k = kind[i][j]
		if k ~= "walk" then
			legs[#legs + 1] = { mode = k, label = string.format(LABEL[k] or "Travel to %s", nodes[j].name),
				point = n, seconds = D[i][j] }
		end
		i = j
	end
	return legs
end

-- Is there a flight path you already know within `yards` of this point?
function T.KnownTaxiNear(p, yards)
	if not graph or not p then return false end
	for _, n in ipairs(graph.nodes) do
		if n.kind == "taxi" and n.inst == p.inst then
			local d = ns.Geo.Distance(n, p)
			if d and d <= yards then return true end
		end
	end
	return false
end

function T.PrintInfo()
	local Learn = ns.TravelLearn
	local taxis = 0
	for _, list in pairs(Learn.KnownTaxi()) do for _ in pairs(list) do taxis = taxis + 1 end end
	ns.print(string.format("travel: %d graph nodes, %d known flight paths, %d learned zone crossings",
		graph and graph.N or 0, taxis, #Learn.Borders()))
	local bind = Learn.Bind()
	local h = T.Hearth()
	if h then
		ns.print(string.format("hearthstone: %s, %s", h.name, h.readyIn > 0 and ("ready in " .. ns.minutes(h.readyIn)) or "ready"))
	elseif bind then
		ns.print("hearthstone: not planned (no hearthstone in bags, or it is now set somewhere new - use it once so LevelPlanner learns where)")
	else
		ns.print("hearthstone: location not learned yet - use it once, or set it at an innkeeper")
	end
end

----------------------------------------------------------------------------------------
-- Hearthstone
----------------------------------------------------------------------------------------

-- Returns {point, readyIn (seconds), name} when the hearthstone can be planned, else nil.
function T.Hearth()
	local cfg = ns.cfg
	if cfg.useHearth == false then return nil end
	local bind = ns.TravelLearn.Bind()
	if not bind or not GetBindLocation or bind.name ~= GetBindLocation() then return nil end
	local count = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(HEARTHSTONE_ITEM))
		or (GetItemCount and GetItemCount(HEARTHSTONE_ITEM)) or 0
	if count < 1 then return nil end
	local getCd = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
	local start, dur = 0, 0
	if getCd then start, dur = getCd(HEARTHSTONE_ITEM) end
	local readyIn = 0
	if start and dur and start > 0 and dur > 0 then readyIn = math.max(0, start + dur - GetTime()) end
	local p = ns.Geo.PointOnMap(bind.map, bind.x, bind.y)
	if not p then return nil end
	return { point = p, readyIn = readyIn, name = bind.name }
end
