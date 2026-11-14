-- Places: useful NPCs (flight masters, innkeepers, repair vendors, your class trainers) and
-- grinding camps. NPC lists come from Questie's own Townsfolk lists when available (fast),
-- otherwise from one scan of the NPC database. Positions come from QuestieDB spawns.
local ADDON, zyde = ...
-- Part of Zyde_Forever since 2026-11-14: LevelPlanner keeps its own private table (zyde.LP) so its
-- names never clash with Zyde's.
zyde.LP = zyde.LP or {}
local ns = zyde.LP

local PL = {}
ns.Places = PL

local cache = {}        -- [kind] = list of {id, name, point}
local hostileIndex      -- non-elite hostile NPCs with levels, for grinding
local grindCache        -- {level, inst, spots}

local function placeOf(npcId)
	local spawns = ns.QuestSource.Npc(npcId, "spawns")
	for areaId, pts in pairs(type(spawns) == "table" and spawns or {}) do
		for _, c in ipairs(pts) do
			local p = ns.Geo.Point(areaId, c[1], c[2])
			if p then return p end
		end
	end
	return nil
end

local function townsfolkIds(kind)
	local TF = ns.safe(QuestieLoader.ImportModule, QuestieLoader, "Townsfolk")
	if not TF then return nil end
	if kind == "Class Trainer" then
		local all = TF.GetClassTrainers and ns.safe(TF.GetClassTrainers)
		return all and all[UnitClassBase("player")]
	end
	return TF.townsfolk and TF.townsfolk[kind]
end

local FLAG_FOR = { ["Flight Master"] = "FLIGHT_MASTER", ["Innkeeper"] = "INNKEEPER", ["Repair"] = "REPAIR" }

-- kind: "Flight Master", "Innkeeper", "Repair" or "Class Trainer". Call inside a job.
function PL.List(kind)
	if cache[kind] then return cache[kind] end
	local QS = ns.QuestSource
	local ids = townsfolkIds(kind)
	if not ids or #ids == 0 then
		-- fallback: scan every NPC for the flag (class trainers have no flag of their own)
		ids = {}
		local LQDB = _G.LibQuestieDB
		local flag = FLAG_FOR[kind]
		local mask = flag and LQDB.Enum and LQDB.Enum.npcFlags and LQDB.Enum.npcFlags[flag]
		if mask then
			local all = ns.safe(LQDB.Npc.GetAllIds) or {}
			for i = 1, #all do
				if i % 100 == 0 then ns.Check() end
				local f = QS.Npc(all[i], "npcFlags")
				if f and bit.band(f, mask) == mask then ids[#ids + 1] = all[i] end
			end
		end
	end
	local list = {}
	for i, id in ipairs(ids) do
		if i % 25 == 0 then ns.Check() end
		if QS.IsFriendly(id) then
			local p = placeOf(id)
			if p then list[#list + 1] = { id = id, name = QS.Npc(id, "name") or kind, point = p } end
		end
	end
	cache[kind] = list
	return list
end

-- The places of a kind closest to the route: for each route point, the nearest one within `yards`.
-- Returns up to `max` distinct places.
function PL.NearRoute(kind, route, yards, max)
	local list = PL.List(kind)
	local picked, seen = {}, {}
	for _, e in ipairs(route) do
		ns.Check()
		local best, bestD
		for _, pl in ipairs(list) do
			local d = ns.Geo.Distance(pl.point, e.point)
			if d and d <= yards and (not bestD or d < bestD) then best, bestD = pl, d end
		end
		if best and not seen[best] then
			seen[best] = true
			picked[#picked + 1] = best
			if #picked >= (max or 8) then break end
		end
	end
	return picked
end

----------------------------------------------------------------------------------------
-- Grinding camps
----------------------------------------------------------------------------------------
local function buildHostileIndex()
	hostileIndex = {}
	local QS = ns.QuestSource
	local all = ns.safe(_G.LibQuestieDB.Npc.GetAllIds) or {}
	for i = 1, #all do
		if i % 100 == 0 then ns.Check() end
		local id = all[i]
		local lo = QS.Npc(id, "minLevel")
		if lo and lo > 0 and lo <= 63 and QS.Npc(id, "friendlyToFaction") == nil then
			local rank = QS.Npc(id, "rank")
			if not rank or rank == 0 then
				hostileIndex[#hostileIndex + 1] = { id = id, lo = lo, hi = QS.Npc(id, "maxLevel") or lo }
			end
		end
	end
end

-- Best grinding camps on your continent for your level: {npcId, name, point, count, level}.
-- Rebuilt when your level or continent changes. Call inside a job.
function PL.GrindSpots(here)
	local L = ns.playerLevel()
	local inst = here and here.inst
	if grindCache and grindCache.level == L and grindCache.inst == inst then return grindCache.spots end
	if not hostileIndex then buildHostileIndex() end
	local QS, cfg = ns.QuestSource, ns.cfg
	local r2 = (cfg.clusterRadius or 120) ^ 2
	local spots = {}
	for n, rec in ipairs(hostileIndex) do
		if n % 20 == 0 then ns.Check() end
		local lvl = (rec.lo + rec.hi) / 2
		if lvl >= L - 1 and lvl <= L + 2 then
			ns.Check() -- the camp search below can be heavy for common mobs
			local pts = {}
			local spawns = QS.Npc(rec.id, "spawns")
			for areaId, list in pairs(type(spawns) == "table" and spawns or {}) do
				for _, c in ipairs(list) do
					local p = ns.Geo.Point(areaId, c[1], c[2])
					if p and p.inst == inst then pts[#pts + 1] = p end
				end
			end
			if #pts > 120 then
				-- very common mobs: a sample is enough to find the densest camp
				local sample, step = {}, #pts / 120
				for k = 1, 120 do sample[k] = pts[math.floor((k - 1) * step) + 1] end
				pts = sample
			end
			if #pts >= (cfg.grindMinSpawns or 6) then
				-- densest spawn: most others within the cluster radius
				local best, bestCount = nil, 0
				for _, a in ipairs(pts) do
					local count = 0
					for _, b in ipairs(pts) do
						local dx, dy = a.wx - b.wx, a.wy - b.wy
						if dx * dx + dy * dy <= r2 then count = count + 1 end
					end
					if count > bestCount then best, bestCount = a, count end
				end
				if best and bestCount >= (cfg.grindMinSpawns or 6) then
					spots[#spots + 1] = { npcId = rec.id, name = QS.Npc(rec.id, "name") or "mobs",
						point = best, count = bestCount, level = lvl }
				end
			end
		end
	end
	grindCache = { level = L, inst = inst, spots = spots }
	return spots
end
