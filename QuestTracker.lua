-- Zyde_Forever: a tidier quest tracker (replaces the game's objective tracker).
--   Ready to turn in  - finished quests, nearest turn-in first
--   This zone         - quests with an objective here, nearest first
--   Other zones       - everything else, folded away (click the heading)
-- Finished objective lines are hidden; only what's left to do shows.
-- "Nearest" uses Questie's locations of the mobs, objects and turn-in NPCs
-- (falls back to the quest log's zone headings without Questie).
-- Click a quest to open it in the quest log. Shift-drag the title to move.

local ADDON, ns = ...

local WIDTH = 250
local P = "|cff66ccffZyde_Forever|r: "

local function on() return ns.F("questTracker") end
local function db() ZydeForeverDB = ZydeForeverDB or {} return ZydeForeverDB end
local safe, isSecret = ns.safe, ns.isSecret
local function plain(v) if isSecret(v) then return nil end return v end

local DB, ZDB -- QuestieDB, ZoneDB

---------------------------------------------------------------------------
-- Where you are: Questie's area ID, the map, and your position (0-100)
---------------------------------------------------------------------------
local function playerZone()
	local map = safe(C_Map.GetBestMapForUnit, "player")
	for _ = 1, 3 do -- caves and city districts: step up to their zone
		local info = map and safe(C_Map.GetMapInfo, map)
		if not info or not Enum or not Enum.UIMapType or (info.mapType or 0) <= Enum.UIMapType.Zone then break end
		if not info.parentMapID or info.parentMapID == 0 then break end
		map = info.parentMapID
	end
	if not map then return nil end
	local area = ZDB and ZDB.GetAreaIdByUiMapId and safe(ZDB.GetAreaIdByUiMapId, ZDB, map)
	local px, py
	local pos = safe(C_Map.GetPlayerMapPosition, map, "player")
	if pos and pos.GetXY then
		local x, y = pos:GetXY()
		if type(x) == "number" and not isSecret(x) and not isSecret(y) then px, py = x * 100, y * 100 end
	end
	local w, h
	if C_Map.GetMapWorldSize then w, h = safe(C_Map.GetMapWorldSize, map) end
	return area, px, py, map, w, h
end

-- Distance in yards (or map units if the map size is unknown) to the
-- nearest of `points` ({ {x, y}, ... } in 0-100).
local function nearest(points, px, py, w, h)
	local best, bestPt
	for _, pt in ipairs(points) do
		local x, y = pt[1], pt[2]
		if type(x) == "number" and type(y) == "number" and x > 0 then
			local dx, dy = (x - px) / 100 * (w or 100), (y - py) / 100 * (h or 100)
			local d = dx * dx + dy * dy
			if not best or d < best then best, bestPt = d, pt end
		end
	end
	return best and math.sqrt(best) or nil, bestPt
end

-- Spawn points of an NPC (or object) in an area, from Questie.
local function spawnsOf(kind, id, area)
	if not (DB and id) then return nil end
	local q = kind == "object" and DB.QueryObjectSingle or DB.QueryNPCSingle
	local spawns = q and safe(q, id, "spawns")
	return type(spawns) == "table" and spawns[area] or nil
end

---------------------------------------------------------------------------
-- The quest log, sorted into groups
---------------------------------------------------------------------------
local function objectivesOf(questID, logIndex)
	local out = {}
	local list = C_QuestLog.GetQuestObjectives and safe(C_QuestLog.GetQuestObjectives, questID)
	if type(list) == "table" then
		for _, o in ipairs(list) do
			if type(o.text) == "string" and not isSecret(o.text) then
				out[#out + 1] = { text = o.text, done = o.finished and true or false }
			end
		end
	elseif GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
		for i = 1, (safe(GetNumQuestLeaderBoards, logIndex) or 0) do
			local text, _, finished = GetQuestLogLeaderBoard(i, logIndex)
			if type(text) == "string" then out[#out + 1] = { text = text, done = finished and true or false } end
		end
	end
	return out
end

local function isComplete(questID, completeFlag, objectives)
	if completeFlag == 1 or completeFlag == true then return true end
	if C_QuestLog.IsComplete and safe(C_QuestLog.IsComplete, questID) == true then return true end
	if C_QuestLog.ReadyForTurnIn and safe(C_QuestLog.ReadyForTurnIn, questID) == true then return true end
	return false
end

-- Distance to what's left: the turn-in NPC when ready, otherwise the
-- nearest spawn of any unfinished objective. nil = nothing in this zone.
local function questDistance(questID, ready, area, px, py, w, h)
	if not (DB and area and px) then return nil end
	local quest = safe(DB.GetQuest, questID)
	if type(quest) ~= "table" then return nil end
	local best, bestPt
	local function consider(points)
		if not points then return end
		local d, pt = nearest(points, px, py, w, h)
		if d and (not best or d < best) then best, bestPt = d, pt end
	end
	if ready then
		local f = quest.Finisher or {}
		if type(f.NPC) == "table" then for _, id in ipairs(f.NPC) do consider(spawnsOf("npc", id, area)) end end
		if type(f.GameObject) == "table" then for _, id in ipairs(f.GameObject) do consider(spawnsOf("object", id, area)) end end
		return best, bestPt
	end
	for _, list in ipairs({ quest.Objectives or {}, quest.SpecialObjectives or {} }) do
		for _, obj in pairs(list) do
			if not obj.Completed and type(obj.spawnList) == "table" then
				for _, spawnData in pairs(obj.spawnList) do
					consider(type(spawnData.Spawns) == "table" and spawnData.Spawns[area] or nil)
				end
			end
		end
	end
	return best, bestPt
end

local function readLog()
	local quests = {}
	local area, px, py, map, w, h = playerZone()
	local zoneName = GetRealZoneText and GetRealZoneText()
	local header
	local n = C_QuestLog.GetNumQuestLogEntries and (safe(C_QuestLog.GetNumQuestLogEntries) or 0) or (safe(GetNumQuestLogEntries) or 0)
	for i = 1, n do
		local title, level, isHeader, completeFlag, questID
		if C_QuestLog.GetInfo then
			local info = safe(C_QuestLog.GetInfo, i)
			if info then
				title, level, isHeader, questID = info.title, info.level, info.isHeader, info.questID
				if info.isHidden then title = nil end
			end
		else
			local t, l, _, h2, _, c, _, id = GetQuestLogTitle(i)
			title, level, isHeader, completeFlag, questID = t, l, h2, c, id
		end
		if isHeader then
			header = title
		elseif title and questID then
			local objectives = objectivesOf(questID, i)
			local ready = isComplete(questID, completeFlag, objectives)
			local dist, pt = questDistance(questID, ready, area, px, py, w, h)
			quests[#quests + 1] = {
				index = i, questID = questID, title = title, level = level, ready = ready,
				objectives = objectives, dist = dist, map = pt and map, x = pt and pt[1], y = pt and pt[2],
				here = dist ~= nil or (header ~= nil and header == zoneName),
			}
		end
	end
	local groups = { ready = {}, here = {}, other = {} }
	for _, q in ipairs(quests) do
		local g = q.ready and groups.ready or (q.here and groups.here or groups.other)
		g[#g + 1] = q
	end
	-- Nearest first; quests with no known distance after, by level.
	local function byDistance(a, b)
		if a.dist and b.dist then return a.dist < b.dist end
		if a.dist or b.dist then return a.dist ~= nil end
		return (a.level or 0) < (b.level or 0)
	end
	table.sort(groups.ready, byDistance)
	table.sort(groups.here, byDistance)
	table.sort(groups.other, function(a, b) return (a.level or 0) < (b.level or 0) end)
	return groups, #quests
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local frame = CreateFrame("Frame", "ZydeForeverQuestTracker", UIParent)
frame:SetSize(WIDTH, 40)
frame:SetFrameStrata("LOW")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:Hide()

local title = CreateFrame("Button", nil, frame)
title:SetPoint("TOPLEFT")
title:SetPoint("TOPRIGHT")
title:SetHeight(20)
title.text = title:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title.text:SetPoint("LEFT", 4, 0)
title.count = title:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
title.count:SetPoint("LEFT", title.text, "RIGHT", 6, -1)
title.line = title:CreateTexture(nil, "ARTWORK")
title.line:SetColorTexture(1, 0.82, 0, 0.35)
title.line:SetHeight(1)
title.line:SetPoint("BOTTOMLEFT", 4, 0)
title.line:SetPoint("BOTTOMRIGHT", -4, 0)
title.text:SetText("Quests")
title:RegisterForDrag("LeftButton")
title:SetScript("OnDragStart", function() if IsShiftKeyDown() then frame:StartMoving() end end)
title:SetScript("OnDragStop", function()
	frame:StopMovingOrSizing()
	local point, _, rel, x, y = frame:GetPoint()
	db().questTrackerPos = { point = point, rel = rel, x = x, y = y }
end)
title:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("Quests")
	GameTooltip:AddLine("Click a quest to open it. Click a group heading to fold it.", 1, 1, 1, true)
	GameTooltip:AddLine("Shift-drag here to move the tracker.", 0.7, 0.7, 0.7, true)
	GameTooltip:Show()
end)
title:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function place()
	local p = db().questTrackerPos
	frame:ClearAllPoints()
	if p then
		frame:SetPoint(p.point, UIParent, p.rel or p.point, p.x, p.y)
	else
		frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -40, -300)
	end
end

-- Row pools: group headings and quest rows (title + objective lines).
local heads, rows = {}, {}

local function folded(key) return (db().questFold or {})[key] end
local function setFold(key, v)
	db().questFold = db().questFold or {}
	db().questFold[key] = v and true or false
end

local refresh -- forward

local function headRow(i)
	local h = heads[i]
	if h then return h end
	h = CreateFrame("Button", nil, frame)
	h:SetHeight(18)
	h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	h.text:SetPoint("LEFT", 4, 0)
	h:SetScript("OnClick", function(self) setFold(self.key, not folded(self.key)) refresh() end)
	heads[i] = h
	return h
end

---------------------------------------------------------------------------
-- Focusing a quest (the circle left of each title): a map waypoint to the
-- nearest place you still need to go - an unfinished objective, or the
-- turn-in once it's done - kept up to date as you move. Click again to stop.
---------------------------------------------------------------------------
local focused, focusedAt -- questID, and the "map:x:y" the waypoint points at

local function clearFocus()
	focused, focusedAt = nil, nil
	if C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
	if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then pcall(C_SuperTrack.SetSuperTrackedQuestID, 0) end
end

-- Point the waypoint at the quest's nearest spot (if it moved).
local function aimFocus(q)
	if q.map and q.x then
		local key = q.map .. ":" .. q.x .. ":" .. q.y
		if key == focusedAt then return end
		focusedAt = key
		local set = false
		if UiMapPoint and C_Map.CanSetUserWaypointOnMap and safe(C_Map.CanSetUserWaypointOnMap, q.map) then
			set = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(q.map, q.x / 100, q.y / 100))
			if set and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
				pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
			end
		end
		if TomTom and TomTom.AddWaypoint then
			pcall(TomTom.AddWaypoint, TomTom, q.map, q.x / 100, q.y / 100, { title = q.title, from = "Zyde_Forever" })
		end
	elseif focusedAt ~= "quest" then
		-- Nothing known in this zone: let the game focus the quest itself.
		focusedAt = "quest"
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then pcall(C_SuperTrack.SetSuperTrackedQuestID, q.questID) end
	end
end

local function toggleFocus(q)
	if focused == q.questID then
		clearFocus()
		print(P .. "stopped focusing " .. q.title)
	else
		focused, focusedAt = q.questID, nil
		aimFocus(q)
		print(P .. "focusing " .. q.title .. (q.x and (" - waypoint set (%.1f, %.1f)"):format(q.x, q.y) or " (no location known in this zone)"))
	end
	refresh()
end

local function circleTexture(parent, layer, size, r, g, b, a)
	local t = parent:CreateTexture(nil, layer)
	t:SetSize(size, size)
	t:SetPoint("CENTER")
	t:SetColorTexture(r, g, b, a)
	local m = parent:CreateMaskTexture()
	m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	m:SetAllPoints(t)
	t:AddMaskTexture(m)
	return t
end

local function questRow(i)
	local r = rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, frame)
	-- The circle: "..." while in progress, "?" when ready; lit when focused.
	local c = CreateFrame("Button", nil, r)
	c:SetSize(18, 18)
	c:SetPoint("TOPLEFT", 4, 2)
	c.ring = circleTexture(c, "BACKGROUND", 18, 0.85, 0.65, 0.15, 1)
	c.inner = circleTexture(c, "ARTWORK", 14, 0.12, 0.09, 0.05, 1)
	c.mark = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	c.mark:SetPoint("CENTER", 0, 0)
	c:SetScript("OnClick", function() if r.quest then toggleFocus(r.quest) end end)
	c:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		local q = r.quest
		GameTooltip:AddLine(q and q.title or "Quest")
		GameTooltip:AddLine(focused == (q and q.questID) and "Click to stop focusing this quest"
			or "Click to focus: waypoint to the nearest place you still need to go", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	c:SetScript("OnLeave", function() GameTooltip:Hide() end)
	r.circle = c
	r.title = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	r.title:SetPoint("TOPLEFT", 26, 0)
	r.title:SetPoint("RIGHT", -4, 0)
	r.title:SetJustifyH("LEFT")
	r.title:SetWordWrap(false)
	r.lines = {}
	r:SetScript("OnClick", function(self)
		local q = self.quest
		if not q then return end
		if QuestLog_OpenToQuest then
			pcall(QuestLog_OpenToQuest, q.questID)
		elseif QuestLogFrame and SelectQuestLogEntry then
			SelectQuestLogEntry(q.index)
			ShowUIPanel(QuestLogFrame)
			if QuestLog_Update then pcall(QuestLog_Update) end
		end
	end)
	r:SetScript("OnEnter", function(self) self.title:SetAlpha(0.75) end)
	r:SetScript("OnLeave", function(self) self.title:SetAlpha(1) end)
	rows[i] = r
	return r
end

local function lineOf(r, j)
	local fs = r.lines[j]
	if fs then return fs end
	fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetJustifyH("LEFT")
	fs:SetTextColor(0.8, 0.8, 0.8)
	r.lines[j] = fs
	return fs
end

local function levelColor(level)
	local c = level and GetQuestDifficultyColor and GetQuestDifficultyColor(level)
	if c then return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) end
	return "|cffffd200"
end

local GROUPS = {
	{ key = "ready", label = "Ready to turn in", color = { 0.4, 1, 0.4 } },
	{ key = "here", label = "This zone", color = { 1, 0.82, 0 } },
	{ key = "other", label = "Other zones", color = { 0.7, 0.7, 0.7 }, foldByDefault = true },
}

refresh = function()
	if not on() then frame:Hide() return end
	local groups, total = readLog()
	-- Keep the focused quest's waypoint on its nearest spot; drop it once the quest is gone.
	if focused then
		local found
		for _, list in pairs(groups) do
			for _, q in ipairs(list) do if q.questID == focused then found = q end end
		end
		if found then aimFocus(found) else clearFocus() end
	end
	title.count:SetFormattedText("%d/%d", total, MAX_QUESTLOG_QUESTS or 20)
	local y = -24
	local hi, ri = 0, 0
	for _, g in ipairs(GROUPS) do
		local list = groups[g.key]
		if #list > 0 then
			hi = hi + 1
			local h = headRow(hi)
			h.key = g.key
			local isFolded = folded(g.key)
			if isFolded == nil then isFolded = g.foldByDefault or false end
			h.text:SetFormattedText("%s %s (%d)", isFolded and "+" or "-", g.label, #list)
			h.text:SetTextColor(g.color[1], g.color[2], g.color[3])
			h:ClearAllPoints()
			h:SetPoint("TOPLEFT", 0, y)
			h:SetPoint("RIGHT", frame, "RIGHT")
			h:SetScript("OnClick", function()
				local cur = folded(g.key)
				if cur == nil then cur = g.foldByDefault or false end
				setFold(g.key, not cur)
				refresh()
			end)
			h:Show()
			y = y - 18
			if not isFolded then
				for _, q in ipairs(list) do
					ri = ri + 1
					local r = questRow(ri)
					r.quest = q
					local isFocus = focused == q.questID
					r.circle.mark:SetText(q.ready and "?" or "...")
					r.circle.ring:SetColorTexture(isFocus and 1 or 0.85, isFocus and 0.9 or 0.65, isFocus and 0.3 or 0.15, 1)
					r.circle.inner:SetColorTexture(isFocus and 0.45 or 0.12, isFocus and 0.32 or 0.09, isFocus and 0.05 or 0.05, 1)
					r.title:SetText(("%s[%s]|r %s"):format(levelColor(q.level), tostring(q.level or "?"), q.title))
					local ly, shown = -14, 0
					for _, o in ipairs(q.objectives) do
						if not o.done and not q.ready then
							shown = shown + 1
							local fs = lineOf(r, shown)
							fs:ClearAllPoints()
							fs:SetPoint("TOPLEFT", r, "TOPLEFT", 36, ly)
							fs:SetPoint("RIGHT", r, "RIGHT", -4, 0)
							fs:SetText("- " .. o.text)
							fs:Show()
							ly = ly - 12
						end
					end
					for j = shown + 1, #r.lines do r.lines[j]:Hide() end
					local height = 14 + shown * 12 + 4
					r:SetHeight(height)
					r:ClearAllPoints()
					r:SetPoint("TOPLEFT", 0, y)
					r:SetPoint("RIGHT", frame, "RIGHT")
					r:Show()
					y = y - height
				end
			end
			y = y - 4
		end
	end
	for i = hi + 1, #heads do heads[i]:Hide() end
	for i = ri + 1, #rows do rows[i]:Hide() end
	frame:SetHeight(-y + 4)
	frame:SetShown(total > 0)
end

---------------------------------------------------------------------------
-- The game's own tracker steps aside while this one is on
---------------------------------------------------------------------------
local function hideBlizzard()
	if InCombatLockdown() or not on() then return end
	for _, f in ipairs({ _G.ObjectiveTrackerFrame, _G.QuestWatchFrame, _G.WatchFrame }) do
		if f then ns.stash(f) end
	end
end

local pending = false
local function refreshSoon()
	if pending then return end
	pending = true
	C_Timer.After(0.2, function() pending = false refresh() end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		if QuestieLoader and QuestieLoader.ImportModule then
			DB = select(2, pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB"))
			ZDB = select(2, pcall(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB"))
			if type(DB) ~= "table" then DB = nil end
			if type(ZDB) ~= "table" then ZDB = nil end
		end
		if not on() then return end
		place()
		for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "UNIT_QUEST_LOG_CHANGED", "ZONE_CHANGED_NEW_AREA",
			"ZONE_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_LEVEL_UP" }) do
			pcall(ev.RegisterEvent, ev, e)
		end
		-- Re-sort as you move (nearest first).
		C_Timer.NewTicker(3, function() if on() then refresh() end end)
		hideBlizzard()
		refreshSoon()
		return
	end
	if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then hideBlizzard() end
	refreshSoon()
end)

ns.OnFeatureChanged(function(key)
	if key ~= "questTracker" then return end
	if on() then place() hideBlizzard() refresh() else frame:Hide() end
end)

ns.QuestTracker = {
	ResetPosition = function()
		db().questTrackerPos = nil
		place()
		print(P .. "quest tracker moved back to its default spot")
	end,
}
