-- Geo: map percentages to world yards, distances and straight-line travel times.
-- Uses the game's own map functions (C_Map, UnitPosition). Questie 12.9 made its copy of
-- HereBeDragons private, so LevelPlanner no longer borrows it.
--
-- World coordinates follow the same convention HereBeDragons uses, so learned data stays valid:
--   wx = the game's world Y (positive = west), wy = the game's world X (positive = north).
local ADDON, zyde = ...
-- Part of Zyde_Forever since 2026-11-14: LevelPlanner keeps its own private table (zyde.LP) so its
-- names never clash with Zyde's.
zyde.LP = zyde.LP or {}
local ns = zyde.LP

local Geo = {}
ns.Geo = Geo

local uiMapCache = {}   -- [areaId] = uiMapId or false
local vec = CreateVector2D

function Geo.Init()
	if not (C_Map and C_Map.GetWorldPosFromMapPos and vec) then
		ns.print("this client has no map position functions; distances will be rough.")
	end
	return true
end

-- World yards for a map position (fx, fy in 0-1).
local function toWorld(map, fx, fy)
	if not (map and fx and fy and C_Map and C_Map.GetWorldPosFromMapPos and vec) then return nil end
	local ok, inst, pos = pcall(C_Map.GetWorldPosFromMapPos, map, vec(fx, fy))
	if not ok or not pos then return nil end
	local north, west = pos:GetXY()
	if not north or ns.isSecret(north) then return nil end
	return west, north, inst
end

-- Questie keys spawns by areaId; the game's map functions want a uiMapId.
function Geo.UiMapForArea(areaId)
	local cached = uiMapCache[areaId]
	if cached ~= nil then return cached or nil end
	local ZoneDB = ns.Q and ns.Q.ZoneDB
	local id = ZoneDB and ns.safe(ZoneDB.GetUiMapIdByAreaId, ZoneDB, areaId)
	uiMapCache[areaId] = id or false
	return id
end

-- Builds a point from a Questie spawn (areaId, x and y in 0-100). Returns nil when it can't be placed
-- on an outdoor map (instance spawns, unknown zones).
function Geo.Point(areaId, x, y)
	if not x or not y or x < 0 or y < 0 then return nil end
	local map = Geo.UiMapForArea(areaId)
	if not map then return nil end
	local wx, wy, inst = toWorld(map, x / 100, y / 100)
	if not wx then return nil end
	return { map = map, area = areaId, x = x, y = y, wx = wx, wy = wy, inst = inst }
end

-- Same, but from a uiMapID (x and y in 0-100).
function Geo.PointOnMap(map, x, y)
	local wx, wy, inst = toWorld(map, x and x / 100, y and y / 100)
	if not wx then return nil end
	return { map = map, x = x, y = y, wx = wx, wy = wy, inst = inst }
end

-- A point's position on another map, in 0-100 (nil when it isn't on that map).
function Geo.ZoneCoords(p, map)
	if not (p and map and C_Map and C_Map.GetMapPosFromWorldPos and vec) then return nil end
	local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, p.inst, vec(p.wy, p.wx), map)
	if not ok or not pos then return nil end
	local x, y = pos:GetXY()
	if not x or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
	return x * 100, y * 100
end

-- The continent map (e.g. Kalimdor, Eastern Kingdoms) that contains a map.
function Geo.ContinentOf(map)
	local guard = 0
	while map and guard < 10 do
		local info = C_Map.GetMapInfo(map)
		if not info then return nil end
		if Enum and Enum.UIMapType and info.mapType == Enum.UIMapType.Continent then return map end
		if info.mapType == 2 then return map end
		map = info.parentMapID
		guard = guard + 1
	end
	return nil
end

-- The zone (uiMapID) under a point of a continent map (x and y in 0-1).
function Geo.ZoneAt(continentMap, x, y)
	if not (C_Map and C_Map.GetMapInfoAtPosition) then return nil end
	local info = ns.safe(C_Map.GetMapInfoAtPosition, continentMap, x, y)
	return info and info.mapID or nil
end

-- Your position in world yards.
local function playerWorld()
	local north, west, _, inst = UnitPosition("player")
	if not west or ns.isSecret(west) then return nil end
	return west, north, inst
end

function Geo.PlayerPoint()
	local wx, wy, inst = playerWorld()
	if not wx then return nil end
	local map = C_Map.GetBestMapForUnit("player")
	local x, y
	local pos = map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
	if pos then x, y = pos:GetXY() end
	if x and ns.isSecret(x) then x, y = nil, nil end
	return { map = map, x = x and x * 100, y = y and y * 100, wx = wx, wy = wy, inst = inst }
end

-- Straight-line distance in yards, or nil when the points are on different continents.
function Geo.Distance(a, b)
	if not a or not b or a.inst ~= b.inst then return nil end
	local dx, dy = b.wx - a.wx, b.wy - a.wy
	return math.sqrt(dx * dx + dy * dy)
end

-- Class speed while travelling: Aspect of the Cheetah (+30%), Ghost Wolf (+40%), Travel Form (+40%),
-- once you know the spell (any rank). Walking legs are timed at that speed (Config.classSpeed).
local CLASS_SPEED = {
	HUNTER = { ids = { 5118 }, mult = 1.3 },  -- Aspect of the Cheetah
	SHAMAN = { ids = { 2645 }, mult = 1.4 },  -- Ghost Wolf
	DRUID = { ids = { 783 }, mult = 1.4 },    -- Travel Form
}
function Geo.ClassSpeedMult()
	if ns.cfg.classSpeed == false then return 1 end
	local _, class = UnitClass("player")
	local c = class and not ns.isSecret(class) and CLASS_SPEED[class]
	if not c then return 1 end
	for _, id in ipairs(c.ids) do
		local known = IsPlayerSpell and ns.safe(IsPlayerSpell, id)
		if known and not ns.isSecret(known) then return c.mult end
	end
	return 1
end

-- Your riding: the best "... Riding" skill (Wolf Riding, Horse Riding...): 150 = 100% mount, 75 = 60%,
-- 0 = none. nil when it can't tell (no skill API, or a collapsed skill header might hide it).
-- Read at most every 10 s.
local ridingAt, ridingRank = -100, nil
function Geo.RidingRank()
	if GetTime() - ridingAt < 10 then return ridingRank end
	ridingAt = GetTime()
	if not (GetNumSkillLines and GetSkillLineInfo) then ridingRank = nil return nil end
	local best, collapsed = 0, false
	for i = 1, ns.safe(GetNumSkillLines) or 0 do
		local name, isHeader, isExpanded, rank = GetSkillLineInfo(i)
		if isHeader and not isExpanded then collapsed = true end
		if not isHeader and type(name) == "string" and not ns.isSecret(name) and name:lower():find("riding")
			and type(rank) == "number" and rank > best then
			best = rank
		end
	end
	ridingRank = (best > 0 or not collapsed) and best or nil
	return ridingRank
end

function Geo.Speed()
	local cfg = ns.cfg
	local base = cfg.runSpeed or 7
	local run = base * Geo.ClassSpeedMult()
	-- your real riding skill when the game says (Config.mountSpeed / mountFastSpeed); else the
	-- old guess: a 60% mount from Config.mountLevel
	local rank = cfg.useRidingSkill ~= false and Geo.RidingRank() or nil
	if rank then
		if rank >= 150 then return math.max(cfg.mountFastSpeed or 14, run) end
		if rank >= 75 then return math.max(cfg.mountSpeed or 11.2, run) end
		return run
	end
	if ns.playerLevel() >= (cfg.mountLevel or 40) then return math.max(cfg.mountSpeed or 11.2, run) end
	return run
end

-- Phase 1 travel estimate: straight line x detour factor, plus a fixed cost for changing zone or continent.
function Geo.TravelSeconds(a, b, speed)
	if not a or not b then return 0 end
	local cfg = ns.cfg
	local d = Geo.Distance(a, b)
	if not d then return cfg.continentChangeSeconds or 900 end
	local detour = ns.TravelLearn and ns.TravelLearn.DetourBetween(a, b) or (cfg.detourFactor or 1.3)
	local t = d * detour / (speed or Geo.Speed())
	if a.map and b.map and a.map ~= b.map then t = t + (cfg.zoneChangeSeconds or 30) end
	return t
end

-- Angle (radians, counter-clockwise from north, as GetPlayerFacing uses) and distance to a point.
function Geo.VectorTo(p)
	if not p then return nil end
	local px, py, inst = playerWorld()
	if not px or inst ~= p.inst then return nil end
	local dx, dy = p.wx - px, p.wy - py      -- dx: west, dy: north
	local dist = math.sqrt(dx * dx + dy * dy)
	local angle = math.atan2(dx, dy)          -- 0 = north, pi/2 = west
	if angle < 0 then angle = angle + 2 * math.pi end
	return angle, dist
end
