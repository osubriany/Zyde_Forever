-- Learn (travel): remembers what the game shows you, so travel estimates get better as you play.
--   * flight paths you know, read at every flight master (per character)
--   * real flight times and prices (per faction, shared by your characters)
--   * your hearthstone location (per character)
--   * zone crossings you actually walk through (shared)
local ADDON, zyde = ...
-- Part of Zyde_Forever since 2026-11-14: LevelPlanner keeps its own private table (zyde.LP) so its
-- names never clash with Zyde's.
zyde.LP = zyde.LP or {}
local ns = zyde.LP

local L = {}
ns.TravelLearn = L

local HEARTHSTONE_SPELL = 8690
local TELEPORT_YARDS = 150  -- further than this in one second (on foot or mounted) means a teleport
local faction
local currentTaxi        -- name of the flight master you are standing at
local pendingFlight      -- {from, to, t}
local hearthCastAt
local lastPos            -- last player position on foot, for learning zone crossings
local prevMapPos, prevMapAt -- last position in the previous map, when the sampler saw a map change

local function db()
	local d = ns.db
	d.flightTimes = d.flightTimes or {}
	d.flightCosts = d.flightCosts or {}
	d.borders = d.borders or {}
	d.detour = d.detour or {}   -- [uiMapID] = {n, mean}: real walking path / straight line, per zone
	faction = faction or UnitFactionGroup("player") or "Neutral"
	d.flightTimes[faction] = d.flightTimes[faction] or {}
	d.flightCosts[faction] = d.flightCosts[faction] or {}
	return d
end

local function char()
	ns.char.taxi = ns.char.taxi or {}
	return ns.char
end

function L.FlightKey(from, to) return tostring(from) .. ">" .. tostring(to) end
function L.FlightTime(from, to) return db().flightTimes[faction][L.FlightKey(from, to)] end
function L.FlightCost(from, to) return db().flightCosts[faction][L.FlightKey(from, to)] end
function L.KnownTaxi() return char().taxi end      -- [continentMap] = {[name] = {x, y}}
function L.Borders() return db().borders end

----------------------------------------------------------------------------------------
-- Walking detour per zone: how much longer your real walks are than a straight line.
-- Learned from your own movement (out of combat, on foot or mounted, not flying), so mountain
-- zones like Stonetalon end up with a bigger factor than open ones like the Barrens.
----------------------------------------------------------------------------------------
local function detourOf(map)
	local cfg = ns.cfg
	local prior = cfg.detourFactor or 1.3
	local rec = map and db().detour[map]
	if cfg.useLearned == false or not rec or rec.n == 0 then return prior end
	local k = cfg.learnPriorWeight or 5
	local w = rec.n / (rec.n + k)
	return prior * (1 - w) + rec.mean * w
end
L.Detour = detourOf

-- Detour for a walk between two points (the average of their zones).
function L.DetourBetween(a, b)
	local da, db_ = detourOf(a and a.map), detourOf(b and b.map)
	return (da + db_) / 2
end

local seg   -- the walk being measured: {start, last, len, map, idle}

local function endWalk()
	local s = seg
	seg = nil
	if not s then return end
	local cfg = ns.cfg
	local straight = ns.Geo.Distance(s.start, s.last)
	if not straight or straight < (cfg.detourMinYards or 200) or s.len < straight then return end
	local ratio = s.len / straight
	if ratio > (cfg.detourMaxSample or 3) then return end -- wandering about, not getting somewhere
	local before = detourOf(s.map)
	local rec = db().detour[s.map] or { n = 0, mean = 0 }
	rec.n = rec.n + 1
	rec.mean = rec.mean + (ratio - rec.mean) / math.min(rec.n, cfg.learnMaxSamples or 30)
	db().detour[s.map] = rec
	ns.dprint(string.format("walk measured: %d yd for %d yd straight (x%.2f)", math.floor(s.len + 0.5),
		math.floor(straight + 0.5), ratio))
	-- rebuild the travel graph when this zone's factor moved noticeably
	if math.abs(detourOf(s.map) - before) >= 0.05 then ns.Travel.Invalidate() end
end

-- Called once a second with your position.
local function sampleWalk(p)
	local speed = GetUnitSpeed and GetUnitSpeed("player") or 0
	if ns.isSecret(speed) then speed = 0 end
	if not p or not p.map or UnitOnTaxi("player") or UnitIsDeadOrGhost("player") or InCombatLockdown()
		or (IsFlying and IsFlying()) then
		endWalk()
		return
	end
	if seg and (p.inst ~= seg.start.inst or p.map ~= seg.map) then endWalk() end -- new zone: new walk
	if speed > 0 then
		if not seg then
			seg = { start = p, last = p, len = 0, map = p.map, idle = 0 }
		else
			local step = ns.Geo.Distance(seg.last, p)
			if not step or step > 60 then
				endWalk() -- teleport or loading screen
			else
				seg.len = seg.len + step
				seg.last = p
				seg.idle = 0
			end
		end
	elseif seg then
		seg.idle = seg.idle + 1
		if seg.idle >= 3 then endWalk() end -- stopped: the walk is over
	end
end
function L.Bind() return ns.char.bind end

----------------------------------------------------------------------------------------
-- Flight masters
----------------------------------------------------------------------------------------
local FS = Enum and Enum.FlightPathState
local STATE_UNREACHABLE = FS and FS.Unreachable or 2
local STATE_CURRENT = FS and FS.Current or 0

local function readTaxiMap()
	local taxiMap = (GetTaxiMapID and ns.safe(GetTaxiMapID)) or ns.Geo.ContinentOf(C_Map.GetBestMapForUnit("player"))
	if not taxiMap then return end
	local known = char().taxi
	known[taxiMap] = known[taxiMap] or {}
	local list = known[taxiMap]
	local costs = db().flightCosts[faction]
	currentTaxi = nil

	local nodes = C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and ns.safe(C_TaxiMap.GetAllTaxiNodes, taxiMap)
	local seen = {}
	if type(nodes) == "table" and #nodes > 0 then
		for _, n in ipairs(nodes) do
			if n.name and n.position and n.state ~= STATE_UNREACHABLE then
				list[n.name] = { x = n.position.x, y = n.position.y }
				seen[#seen + 1] = n
				if n.state == STATE_CURRENT then currentTaxi = n.name end
			end
		end
		if currentTaxi then
			for _, n in ipairs(seen) do
				if n.name ~= currentTaxi and n.slotIndex and TaxiNodeCost then
					local c = ns.safe(TaxiNodeCost, n.slotIndex)
					if c and c > 0 then costs[L.FlightKey(currentTaxi, n.name)] = c end
				end
			end
		end
	elseif NumTaxiNodes then
		-- older interface
		for i = 1, (NumTaxiNodes() or 0) do
			local kind = TaxiNodeGetType(i)
			if kind == "CURRENT" or kind == "REACHABLE" then
				local name = TaxiNodeName(i)
				local x, y = TaxiNodePosition(i)
				if name and x then
					list[name] = { x = x, y = y }
					if kind == "CURRENT" then currentTaxi = name end
				end
			end
		end
		if currentTaxi then
			for i = 1, (NumTaxiNodes() or 0) do
				if TaxiNodeGetType(i) == "REACHABLE" then
					local c = TaxiNodeCost(i)
					if c and c > 0 then costs[L.FlightKey(currentTaxi, TaxiNodeName(i))] = c end
				end
			end
		end
	end
	ns.Travel.Invalidate()
	ns.dprint("flight master read:", currentTaxi or "?")
	ns.RequestReplan(false) -- a "learn this flight path" step is now done
end

-- Your discovered flight paths on this continent, from the map's flight-node list. Works anywhere,
-- not only at a flight master, so a path you learned while LevelPlanner wasn't looking still counts.
-- Only used when the client says which nodes are undiscovered (never guess "known").
function L.RefreshKnownFromMap()
	if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then return end
	local here = C_Map.GetBestMapForUnit("player")
	local cont = here and ns.Geo.ContinentOf(here)
	if not cont then return end
	local nodes = ns.safe(C_TaxiMap.GetTaxiNodesForMap, cont)
	if type(nodes) ~= "table" or #nodes == 0 then return end
	local reported = false
	for _, n in ipairs(nodes) do
		if n.isUndiscovered ~= nil then reported = true break end
	end
	if not reported then return end
	local FPF = Enum and Enum.FlightPathFaction
	local mine = UnitFactionGroup("player")
	local enemy = FPF and ((mine == "Horde" and FPF.Alliance) or (mine == "Alliance" and FPF.Horde)) or nil
	local known = char().taxi
	local have = {}
	for _, list in pairs(known) do
		for name in pairs(list) do have[name] = true end
	end
	known[cont] = known[cont] or {}
	local added = 0
	for _, n in ipairs(nodes) do
		if n.name and n.position and n.isUndiscovered == false and not have[n.name]
			and (enemy == nil or n.faction ~= enemy) then
			known[cont][n.name] = { x = n.position.x, y = n.position.y }
			added = added + 1
		end
	end
	if added > 0 then
		ns.dprint(added .. " known flight path(s) read from the map")
		ns.Travel.Invalidate()
		ns.RequestReplan(false)
	end
end

local function onTakeTaxi(slot)
	local to = TaxiNodeName and ns.safe(TaxiNodeName, slot)
	if currentTaxi and to then
		pendingFlight = { from = currentTaxi, to = to, t = GetTime() }
	end
end

local function onLanded()
	if not pendingFlight or UnitOnTaxi("player") then return end
	local dur = GetTime() - pendingFlight.t
	if dur > 10 and dur < 1800 then
		local times = db().flightTimes[faction]
		local key = L.FlightKey(pendingFlight.from, pendingFlight.to)
		times[key] = times[key] and (times[key] * 0.5 + dur * 0.5) or dur
		ns.dprint(string.format("flight %s took %ds", key, dur))
		ns.Travel.Invalidate()
	end
	pendingFlight = nil
end

----------------------------------------------------------------------------------------
-- Hearthstone location
----------------------------------------------------------------------------------------
local function recordBind(reason)
	local p = ns.Geo.PlayerPoint()
	local name = GetBindLocation and GetBindLocation()
	if not p or not p.map or not name then return end
	ns.char.bind = { name = name, map = p.map, x = p.x, y = p.y }
	ns.dprint("hearthstone location learned (" .. reason .. "): " .. name)
	ns.Travel.Invalidate()
	ns.RequestReplan(false) -- a "set your hearthstone here" step is now done
end

----------------------------------------------------------------------------------------
-- Zone crossings
----------------------------------------------------------------------------------------
local function recordCrossing()
	local now = ns.Geo.PlayerPoint()
	local before = lastPos
	-- the 1-second sampler may already have stepped over the border
	if before and now and before.map == now.map and prevMapPos and prevMapAt and GetTime() - prevMapAt < 3 then
		before = prevMapPos
	end
	lastPos, prevMapPos, prevMapAt = now, nil, nil
	if not (now and before and now.map and before.map) or now.map == before.map then return end
	if now.inst ~= before.inst or UnitOnTaxi("player") then return end
	local d = ns.Geo.Distance(now, before)
	if not d or d > 60 then return end -- teleport or loading screen, not a walk
	local borders = db().borders
	for _, b in ipairs(borders) do
		local same = (b.mapA == before.map and b.mapB == now.map) or (b.mapA == now.map and b.mapB == before.map)
		if same then
			local bp = ns.Geo.PointOnMap(b.map, b.x, b.y)
			local dd = bp and ns.Geo.Distance(bp, now)
			if dd and dd < 150 then return end -- already known
		end
	end
	borders[#borders + 1] = { mapA = before.map, mapB = now.map, map = now.map, x = now.x, y = now.y }
	ns.dprint("learned a zone crossing")
	ns.Travel.Invalidate()
end

----------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------
function L.Init()
	db()
	char()
	local f = CreateFrame("Frame")
	f:RegisterEvent("TAXIMAP_OPENED")
	f:RegisterEvent("UI_INFO_MESSAGE")
	f:RegisterEvent("PLAYER_CONTROL_GAINED")
	f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	f:RegisterEvent("PLAYER_ENTERING_WORLD")
	f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	f:SetScript("OnEvent", function(_, event, a1, a2, a3)
		if event == "TAXIMAP_OPENED" then
			readTaxiMap()
		elseif event == "UI_INFO_MESSAGE" then
			-- "New flight path discovered!"
			if a2 == ERR_NEWTAXIPATH then C_Timer.After(1, L.RefreshKnownFromMap) end
		elseif event == "PLAYER_CONTROL_GAINED" then
			-- also fires after stuns and fears; only a finished flight matters
			if pendingFlight and not UnitOnTaxi("player") then
				onLanded()
				ns.RequestReplan(true)
			end
		elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
			if a1 == "player" and a3 == HEARTHSTONE_SPELL then hearthCastAt = GetTime() end
		elseif event == "PLAYER_ENTERING_WORLD" then
			lastPos = nil
			if hearthCastAt and GetTime() - hearthCastAt < 60 then
				hearthCastAt = nil
				C_Timer.After(2, function() recordBind("arrived by hearthstone") end)
			end
		elseif event == "ZONE_CHANGED_NEW_AREA" then
			recordCrossing()
			C_Timer.After(2, L.RefreshKnownFromMap) -- maybe a new continent
		end
	end)
	if TakeTaxiNode then hooksecurefunc("TakeTaxiNode", onTakeTaxi) end
	-- flight paths you know but LevelPlanner never saw on a flight map
	C_Timer.After(3, L.RefreshKnownFromMap)
	if ConfirmBinder then hooksecurefunc("ConfirmBinder", function() C_Timer.After(1, function() recordBind("set at innkeeper") end) end) end
	-- a hearthstone that lands without a loading screen
	C_Timer.NewTicker(1, function()
		sampleWalk(ns.Geo.PlayerPoint())
		if hearthCastAt and GetTime() - hearthCastAt > 3 and GetTime() - hearthCastAt < 60 then
			local p = ns.Geo.PlayerPoint()
			if p then hearthCastAt = nil recordBind("arrived by hearthstone") end
		end
		if not UnitOnTaxi("player") and not UnitIsDeadOrGhost("player") then
			local p = ns.Geo.PlayerPoint()
			if p then
				local jump = lastPos and (p.inst ~= lastPos.inst or (ns.Geo.Distance(p, lastPos) or 0) > TELEPORT_YARDS)
				if jump then
					-- hearthstone, portal, summon or graveyard: the old route started somewhere else
					prevMapPos, prevMapAt = nil, nil
					ns.dprint("you moved a long way at once - planning afresh from here")
					ns.forceFresh = true
					ns.RequestReplan(true)
				elseif lastPos and p.map ~= lastPos.map then
					prevMapPos, prevMapAt = lastPos, GetTime()
				end
				lastPos = p
			end
		end
	end)
end
