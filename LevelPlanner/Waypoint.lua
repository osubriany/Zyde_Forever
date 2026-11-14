-- Waypoint: points the game's map pin, TomTom (if installed) or the built-in arrow at the next stop.
local ADDON, zyde = ...
-- Part of Zyde_Forever since 2026-11-14: LevelPlanner keeps its own private table (zyde.LP) so its
-- names never clash with Zyde's.
zyde.LP = zyde.LP or {}
local ns = zyde.LP

local W = {}
ns.Waypoint = W

local lastKey, tomtomUid, weSetPin

local function useTomTom()
	return ns.cfg.useTomTom ~= false and TomTom and TomTom.AddWaypoint and true or false
end
W.UsingTomTom = useTomTom

local function clear()
	if tomtomUid and TomTom and TomTom.RemoveWaypoint then ns.safe(TomTom.RemoveWaypoint, TomTom, tomtomUid) end
	tomtomUid = nil
	if weSetPin and C_Map and C_Map.ClearUserWaypoint then ns.safe(C_Map.ClearUserWaypoint) end
	weSetPin = false
	if ns.Arrow then ns.Arrow.SetTarget(nil) end
	lastKey = nil
end

-- Reaching a pass doesn't fire a game event, so check once a second and plan again when you're there.
local passDone
C_Timer.NewTicker(1, function()
	local stop = ns.plan and ns.plan.stops and ns.plan.stops[1]
	if not (stop and stop.kind == "travel" and (stop.mode == "pass" or stop.mode == "border") and stop.point) then return end
	local _, dist = ns.Geo.VectorTo(stop.point)
	if dist and dist <= (ns.cfg.arrivedYards or 15) * 2 and passDone ~= stop.label then
		passDone = stop.label
		ns.RequestReplan(false)
	end
end)

-- Points the map pin, TomTom or the built-in arrow at a point.
-- The quest LevelPlanner last had the game follow (so a quest you pick yourself in the tracker
-- stays followed until the step changes).
local followedQuest

-- A quest in your log for this step? Then the game follows that quest, like clicking it in the
-- quest tracker: it's highlighted there and on the map, and the game draws its own waypoint.
-- Returns true when it did that.
local function followQuest(questId)
	if ns.cfg.followQuestInTracker == false or type(questId) ~= "number" then return false end
	if not (C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID) then return false end
	local inLog = ns.Q.QuestLogCache and ns.safe(ns.Q.QuestLogCache.TryGetQuest, questId)
	if not inLog then return false end
	if followedQuest ~= questId then
		followedQuest = questId
		if C_QuestLog and C_QuestLog.SetSelectedQuest then ns.safe(C_QuestLog.SetSelectedQuest, questId) end
		ns.safe(C_SuperTrack.SetSuperTrackedQuestID, questId)
	end
	return true
end

local function setTarget(p, title, questId)
	local key = string.format("%d:%.2f:%.2f:%s", p.map, p.x, p.y, title)
	if key == lastKey then return end
	lastKey = key

	local following = followQuest(questId)
	if not following then followedQuest = nil end
	if ns.cfg.useGameWaypoint ~= false and C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
		local can = not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(p.map)
		if can then
			ns.safe(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(p.map, p.x / 100, p.y / 100))
			-- the game follows one thing: the step's quest when there is one, else this pin
			if not following and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
				ns.safe(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
			end
			weSetPin = true
		end
	end

	if useTomTom() then
		if tomtomUid and TomTom.RemoveWaypoint then ns.safe(TomTom.RemoveWaypoint, TomTom, tomtomUid) end
		tomtomUid = ns.safe(TomTom.AddWaypoint, TomTom, p.map, p.x / 100, p.y / 100, {
			title = title, persistent = false, minimap = true, world = true, crazy = true, from = "LevelPlanner",
		})
		if ns.Arrow then ns.Arrow.SetTarget(nil) end
	elseif ns.Arrow then
		ns.Arrow.SetTarget(p, title)
	end
end

----------------------------------------------------------------------------------------
-- Your corpse: while you are a ghost, everything points there instead of the plan.
----------------------------------------------------------------------------------------
local function corpsePoint()
	if not (C_DeathInfo and C_DeathInfo.GetCorpseMapPosition) then return nil end
	local map = C_Map.GetBestMapForUnit("player")
	-- the corpse may be in the zone you are in, or (after a far graveyard) further up the map tree
	local guard = 0
	while map and guard < 4 do
		local pos = ns.safe(C_DeathInfo.GetCorpseMapPosition, map)
		if pos and pos.x and pos.x > 0 then
			local x, y = pos.x, pos.y
			-- prefer the zone map the corpse lies on, so the pin and arrow are exact
			local p = ns.Geo.PointOnMap(map, x * 100, y * 100)
			local info = C_Map.GetMapInfoAtPosition and ns.safe(C_Map.GetMapInfoAtPosition, map, x, y)
			if p and info and info.mapID and info.mapID ~= map then
				local zx, zy = ns.Geo.ZoneCoords(p, info.mapID)
				if zx then p = ns.Geo.PointOnMap(info.mapID, zx, zy) or p end
			end
			return p
		end
		local mi = C_Map.GetMapInfo(map)
		map = mi and mi.parentMapID
		guard = guard + 1
	end
	return nil
end

local function isGhost()
	return UnitIsGhost and UnitIsGhost("player")
end

function W.ShowCorpse()
	local p = corpsePoint()
	if p then setTarget(p, "Your corpse") end
	return p ~= nil
end
W.CorpsePoint = corpsePoint -- the step list adds the run back to it to the level-up time

local deathFrame = CreateFrame("Frame")
deathFrame:RegisterEvent("PLAYER_DEAD")
deathFrame:RegisterEvent("PLAYER_ALIVE")
deathFrame:RegisterEvent("PLAYER_UNGHOST")
deathFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
deathFrame:SetScript("OnEvent", function(_, event)
	if not ns.active then return end -- "Level planner" is off in /zyde
	if isGhost() then
		W.ShowCorpse()
	elseif event == "PLAYER_UNGHOST" or event == "PLAYER_ALIVE" then
		lastKey = nil
		W.Update(ns.plan)
	end
end)
-- the corpse position can arrive a moment after you release; keep trying while you are a ghost
C_Timer.NewTicker(2, function()
	if ns.active and isGhost() and not (lastKey or ""):find("Your corpse$") then W.ShowCorpse() end
	-- keep the level-up time current (it includes the run back) while you're a ghost
	if ns.active and isGhost() and ns.StepList and ns.StepList.Refresh then ns.safe(ns.StepList.Refresh) end
end)

function W.Update(plan)
	if isGhost() and W.ShowCorpse() then return end -- the corpse comes first
	local stop = plan and plan.stops and plan.stops[1]
	local p = stop and stop.point
	if not p or not p.map or not p.x or not p.y then clear() return end
	setTarget(p, stop.label or stop.questName or "LevelPlanner", stop.questId)
end
