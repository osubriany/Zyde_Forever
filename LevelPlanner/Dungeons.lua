-- Dungeons (phase 4): each dungeon becomes one planned "quest" made of
--   pre-quests (whole, in order) -> pick up every dungeon quest -> run the dungeon -> turn them all in.
-- Value: the quests' XP plus kills in the run. Cost: travel, finding a group, and the run itself.
-- Levels, kills and run times come from Config.dungeonData; names and entrances from Questie.
local ADDON, zyde = ...
-- Part of Zyde_Forever since 2026-11-14: LevelPlanner keeps its own private table (zyde.LP) so its
-- names never clash with Zyde's.
zyde.LP = zyde.LP or {}
local ns = zyde.LP

local D = {}
ns.Dungeons = D

local areaToDungeon   -- [any dungeon areaId, including Questie's alternative IDs] = main areaId

local function index()
	if areaToDungeon then return areaToDungeon end
	areaToDungeon = {}
	local ZoneDB = ns.Q.ZoneDB
	local all = ZoneDB and ZoneDB.GetDungeons and ns.safe(ZoneDB.GetDungeons, ZoneDB) or {}
	for area, entry in pairs(all) do
		if (ns.cfg.dungeonData or {})[area] then
			areaToDungeon[area] = area
			for _, alt in ipairs(type(entry[2]) == "table" and entry[2] or {}) do areaToDungeon[alt] = area end
		end
	end
	return areaToDungeon
end

-- The planned dungeon a quest belongs to (by its zone), or nil.
function D.Of(questId)
	if ns.cfg.dungeons == false then return nil end
	local zone = ns.QuestSource.Quest(questId, "zoneOrSort")
	if not zone or zone <= 0 then return nil end
	return index()[zone]
end

-- Is the player's level right for this dungeon?
local function levelOk(data)
	local L = ns.playerLevel()
	local slack = ns.cfg.dungeonLevelSlack or 2
	return L >= data[2] - slack and L <= data[3] + slack
end

local function entrancePoints(area)
	local pts = {}
	local ZoneDB = ns.Q.ZoneDB
	local locs = ZoneDB and ZoneDB.GetDungeonLocation and ns.safe(ZoneDB.GetDungeonLocation, ZoneDB, area)
	for _, loc in ipairs(type(locs) == "table" and locs or {}) do
		local p = ns.Geo.Point(loc[1], loc[2], loc[3])
		if p then pts[#pts + 1] = p end
	end
	return pts
end

-- Every-pre-quest helper for QuestSource.ChainRequires: "any quest may be in the route".
local ANY = setmetatable({}, { __index = function() return true end })

-- found[area] = { log = {[id] = entry}, avail = {ids}, blocked = {ids} }
-- poolIds: quests planned on their own (in log or available). Returns a list of dungeon "quests".
function D.BuildAll(found, poolIds, complete, log)
	local out = {}
	local cfg = ns.cfg
	for area, f in pairs(found) do
		ns.Check()
		local data = cfg.dungeonData and cfg.dungeonData[area]
		if data and levelOk(data) then
			local d = D.Build(area, data, f, poolIds, complete, log)
			if d then out[#out + 1] = d end
		end
	end
	return out
end

function D.Build(area, data, f, poolIds, complete, log)
	local cfg, QS, S = ns.cfg, ns.QuestSource, ns.Stops
	local entrances = entrancePoints(area)
	if #entrances == 0 then return nil end

	local pre, preSeen, parts, requires, reqSeen = {}, {}, {}, {}, {}
	local function needs(id)
		if not reqSeen[id] then reqSeen[id] = true requires[#requires + 1] = id end
	end

	for id, entry in pairs(f.log or {}) do
		local q = S.BuildQuest(id, entry, { dungeon = true })
		if q then parts[#parts + 1] = q end
	end
	for _, id in ipairs(f.avail or {}) do
		local q = S.BuildQuest(id, nil, { dungeon = true })
		if q then parts[#parts + 1] = q end
	end
	-- dungeon quests still waiting for a pre-quest: bring the pre-quest along (one step deep)
	for _, id in ipairs(f.blocked or {}) do
		local reqs = QS.ChainRequires(id, ANY, complete, log)
		local ok = reqs ~= nil
		local newPre = {}
		for _, p in ipairs(reqs or {}) do
			if poolIds[p] then
				-- planned on its own; it must be turned in before this dungeon's pick-ups
			elseif preSeen[p] then
				-- already coming along
			elseif ns.safe(ns.Q.QuestieDB.IsDoable, p) then
				local pq = S.BuildQuest(p, nil)
				if pq then newPre[#newPre + 1] = pq else ok = false end
			else
				ok = false
			end
		end
		if ok then
			local q = S.BuildQuest(id, nil, { dungeon = true })
			if q then
				for _, p in ipairs(reqs) do if poolIds[p] then needs(p) end end
				for _, pq in ipairs(newPre) do preSeen[pq.id] = true pre[#pre + 1] = pq end
				parts[#parts + 1] = q
			end
		end
	end
	if #parts == 0 then return nil end

	-- the dungeon stop
	local share = cfg.dungeonMobXpShare or 0.28
	local kills = data[5] or 100
	local mobXp = kills * ns.Estimate.MobXP(data[4], 1, true) * share
	local findMin = ns.IsGrouped() and (cfg.groupFindMinutesGrouped or 5) or (cfg.groupFindMinutes or 20)
	local runMin = math.floor(ns.Learn.DungeonMinutes(area, data[6] or 60) + 0.5) -- your real run times, once known
	local name = data[1] or (ns.Q.ZoneDB.GetLocalizedDungeonName and ns.safe(ns.Q.ZoneDB.GetLocalizedDungeonName, ns.Q.ZoneDB, area)) or "dungeon"
	local id = "d:" .. area

	local questXp, items = 0, 0
	for _, q in ipairs(parts) do
		questXp = questXp + (q.questXp or 0)
		if not q.inLog then items = items + (q.bagHold or 0) - (q.sourceItemId and 1 or 0) end
	end
	local dstop = {
		kind = "dungeon", questId = id, questName = name, key = id, points = entrances,
		work = (findMin + runMin) * 60, mobXp = mobXp, logDelta = 0, bagDelta = math.max(0, items),
		label = string.format("Run %s with %d quest%s (~%s mob XP; %d min to find a group, %d min run)",
			name, #parts, #parts == 1 and "" or "s", ns.fmt(mobXp), findMin, runMin),
	}

	-- one "quest" for the planner: pre-quests, pick-ups, the run, turn-ins
	local comp = { id = id, name = name, isDungeon = true, area = area, stops = {},
		requires = #requires > 0 and requires or nil, parts = parts }
	local order = 0
	local function add(s, sameOrder)
		if not sameOrder then order = order + 1 end
		s.quest, s.order = comp, order
		comp.stops[#comp.stops + 1] = s
	end
	for _, pq in ipairs(pre) do
		for _, s in ipairs(pq.stops) do add(s) end
	end
	local first = true
	for _, q in ipairs(parts) do
		for _, s in ipairs(q.stops) do
			if s.kind == "pickup" then add(s, not first) first = false end
		end
	end
	add(dstop)
	first = true
	for _, q in ipairs(parts) do
		for _, s in ipairs(q.stops) do
			if s.kind == "turnin" then add(s, not first) first = false end
		end
	end

	local xp, work = mobXp * (cfg.mobXpWeight or 1) + questXp * (cfg.questXpWeight or 1), 0
	for _, pq in ipairs(pre) do xp = xp + pq.xp end
	for _, s in ipairs(comp.stops) do work = work + (s.work or 0) end
	comp.xp, comp.workSeconds, comp.questXp, comp.mobXp = xp, work, questXp, mobXp
	if xp <= 0 then return nil end
	return comp
end
