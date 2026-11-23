-- Zyde_Forever: a tidier quest tracker (replaces the game's objective tracker).
--   Ready to turn in  - finished quests, by level
--   This zone         - quests with an objective here, by level
--   Other zones       - everything else, folded away (click the heading)
-- The mark on a heading cycles that list: nearest, highest level, lowest level.
-- Finished objective lines are hidden; only what's left to do shows.
-- Each quest has a level badge in its difficulty color.
-- Dims in combat.
-- "Nearest" uses Questie's locations of the mobs, objects and turn-in NPCs
-- (falls back to the quest log's zone headings without Questie).
-- Click a quest to follow it (like the game's own "..." button: map
-- highlight); right-click opens it in the quest log. Shift-click pastes
-- the quest into chat. Shift-drag the title to move.

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
	local w, h -- the map's size in yards (nil if the game doesn't say)
	if C_Map.GetMapWorldSize then w, h = safe(C_Map.GetMapWorldSize, map) end
	if not (type(w) == "number" and w > 0 and type(h) == "number" and h > 0) then w, h = nil, nil end
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

-- An elite (group) quest: the game's quest tag, its "suggested group" size, or Questie's data.
local QuestieDB
local function isElite(questID, info, tag)
	if type(tag) == "string" and tag ~= "" then return true end -- classic log: "Elite", "Group", "Dungeon"...
	if info and (plain(info.suggestedGroup) or 0) > 1 then return true end
	if C_QuestLog.GetQuestTagInfo then
		local t = safe(C_QuestLog.GetQuestTagInfo, questID)
		if t and (plain(t.isElite) or plain(t.tagID) == 1 or plain(t.tagName) == (ELITE or "Elite")) then return true end
	end
	if QuestieDB == nil then
		QuestieDB = QuestieLoader and QuestieLoader.ImportModule and safe(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB") or false
	end
	if QuestieDB and QuestieDB.IsGroupQuest and safe(QuestieDB.IsGroupQuest, questID) then return true end
	return false
end

local function readLog()
	local quests = {}
	local area, px, py, map, w, h = playerZone()
	local zoneName = GetRealZoneText and GetRealZoneText()
	local header
	local n = C_QuestLog.GetNumQuestLogEntries and (safe(C_QuestLog.GetNumQuestLogEntries) or 0) or (safe(GetNumQuestLogEntries) or 0)
	for i = 1, n do
		local title, level, isHeader, completeFlag, questID, info, tag
		if C_QuestLog.GetInfo then
			info = safe(C_QuestLog.GetInfo, i)
			if info then
				title, level, isHeader, questID = info.title, info.level, info.isHeader, info.questID
				if info.isHidden then title = nil end
			end
		else
			local t, l, tg, h2, _, c, _, id = GetQuestLogTitle(i)
			title, level, isHeader, completeFlag, questID, tag = t, l, h2, c, id, tg
			-- (third value: the tag, or the suggested group size on some clients)
			if type(tag) == "number" then info, tag = { suggestedGroup = tag }, nil end
		end
		if isHeader then
			header = title
		elseif title and questID then
			local objectives = objectivesOf(questID, i)
			local ready = isComplete(questID, completeFlag, objectives)
			local dist, pt = questDistance(questID, ready, area, px, py, w, h)
			-- The log writes an elite as "29+". The number is the level; the + is only the badge.
			local elite = isElite(questID, info, tag)
			if not isSecret(level) and type(level) == "string" then
				if level:find("+", 1, true) then elite = true end
				local digits = level:match("^(%d+)")
				level = digits and tonumber(digits) or level
			end
			quests[#quests + 1] = {
				index = i, questID = questID, title = title, level = level, ready = ready,
				elite = elite,
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
	return groups, #quests
end

-- Level first. Same level: the closer quest stays above. A secret level
-- cannot be compared, so it sorts after a plain one.
local function questLevel(q)
	local n = q.level
	if isSecret(n) or type(n) ~= "number" then return nil end
	return n
end

local function byLevel(highFirst)
	return function(a, b)
		local al, bl = questLevel(a), questLevel(b)
		if al ~= nil and bl ~= nil and al ~= bl then
			if highFirst then return al > bl end
			return al < bl
		end
		-- Only when one quest has a level and the other does not. Saying
		-- "this one wins" for two equal levels makes the sort abort.
		if (al ~= nil) ~= (bl ~= nil) then return al ~= nil end
		if a.dist and b.dist then return a.dist < b.dist end
		if a.dist or b.dist then return a.dist ~= nil end
		if type(a.title) == "string" and type(b.title) == "string" then return a.title < b.title end
		return false
	end
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
-- The game's own tracker fonts, by size.
local FONTS = {
	[14] = "GameFontNormalLarge", [13] = "GameFontHighlight", [12] = "GameFontNormal",
	[11] = "GameFontHighlightSmall", [10] = "GameFontHighlightSmall",
}
-- Text size (the slider in /zyde): the tracker's own copies of those fonts, scaled
-- from 13 (the quest titles' size); spacing and width scale with them.
local BASE_FONT = 13
local fontObjs = {}
local function fontSize() return tonumber(db().questTrackerFont) or BASE_FONT end
local scale = 1 -- (set by applyFonts)
local function Q(n) return math.floor(n * scale + 0.5) end
local function font(fs, size)
	local fo = fontObjs[size]
	if not fo then
		fo = CreateFont("ZydeForeverQuestFont" .. size)
		fo:CopyFontObject(FONTS[size] or "GameFontHighlight")
		fontObjs[size] = fo
	end
	fs:SetFontObject(fo)
	return fs
end
local GOLD = { 1, 0.82, 0 }

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
title.text = font(title:CreateFontString(nil, "OVERLAY"), 14)
title.text:SetPoint("LEFT", 6, 0)
title.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
title.count = font(title:CreateFontString(nil, "OVERLAY"), 11)
title.count:SetPoint("LEFT", title.text, "RIGHT", 6, 0)
title.count:SetTextColor(0.6, 0.6, 0.65)
title.line = title:CreateTexture(nil, "ARTWORK")
title.line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35)
title.line:SetHeight(1)
title.line:SetPoint("BOTTOMLEFT", 6, 0)
title.line:SetPoint("BOTTOMRIGHT", -6, 0)
title.text:SetText("Quests")
title:RegisterForDrag("LeftButton")
title:SetScript("OnDragStart", function() if IsShiftKeyDown() then frame:StartMoving() end end)
-- Always held by its top-right corner. (After a drag the game may anchor it by its bottom or centre;
-- then each refresh grew it upward, which made room for more, and it kept growing on every click.)
local function anchorTop(save)
	local right, top = frame:GetRight(), frame:GetTop()
	if not (right and top) then return end
	frame:ClearAllPoints()
	frame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right, top)
	if save then db().questTrackerPos = { point = "TOPRIGHT", rel = "BOTTOMLEFT", x = right, y = top } end
end
title:SetScript("OnDragStop", function()
	frame:StopMovingOrSizing()
	anchorTop(true)
end)
title:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("Quests")
	GameTooltip:AddLine("Click a quest to follow it, right-click to open it. Click a group heading to fold it.", 1, 1, 1, true)
	GameTooltip:AddLine("Shift-drag here to move the tracker.", 0.7, 0.7, 0.7, true)
	GameTooltip:AddLine("Mouse wheel over the list scrolls it when it's too long for the screen.", 0.7, 0.7, 0.7, true)
	GameTooltip:Show()
end)
title:SetScript("OnLeave", function() GameTooltip:Hide() end)

---------------------------------------------------------------------------
-- The list scrolls: the tracker grows with its quests until it would run off
-- the bottom of the screen, then the mouse wheel scrolls it (a thin bar on
-- the right shows where you are). It stops at two-thirds of the screen by default;
-- /zyde questheight <pixels> sets another cap (0 = down to the bottom of the screen).
---------------------------------------------------------------------------
local TOP_GAP, BOTTOM_MARGIN, MIN_VIEW = 24, 40, 120
local scroll = CreateFrame("ScrollFrame", nil, frame)
scroll:SetPoint("TOPLEFT", 0, -TOP_GAP)
scroll:SetPoint("TOPRIGHT", 0, -TOP_GAP)
scroll:SetHeight(1)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(WIDTH, 1)
scroll:SetScrollChild(content)

local bar = scroll:CreateTexture(nil, "OVERLAY")
bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.45)
bar:SetWidth(2)
bar:Hide()

local function maxScroll() return math.max(0, content:GetHeight() - scroll:GetHeight()) end
local function updateBar()
	local view, total = scroll:GetHeight(), content:GetHeight()
	if total <= view + 1 then bar:Hide() return end
	local h = math.max(16, view * view / total)
	local pos = (view - h) * (scroll:GetVerticalScroll() / maxScroll())
	bar:ClearAllPoints()
	bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -1, -pos)
	bar:SetHeight(h)
	bar:Show()
end
local function scrollTo(v)
	scroll:SetVerticalScroll(math.max(0, math.min(maxScroll(), v)))
	updateBar()
end
scroll:EnableMouseWheel(true)
scroll:SetScript("OnMouseWheel", function(_, delta) scrollTo(scroll:GetVerticalScroll() - delta * 40) end)

-- How tall the list may be: down to near the bottom of the screen, or less.
local function viewLimit()
	local top = frame:GetTop()
	local room = top and (top - TOP_GAP - BOTTOM_MARGIN) or 500
	-- questTrackerMaxHeight: pixels; -1 = down to the bottom of the screen; unset = two-thirds of it
	local cap = tonumber(db().questTrackerMaxHeight)
	if not cap or cap == 0 then cap = math.floor((UIParent:GetHeight() or 900) * 2 / 3) end
	if cap > 0 then room = math.min(room, cap) end
	return math.max(MIN_VIEW, room)
end

local function place()
	local p = db().questTrackerPos
	frame:ClearAllPoints()
	if p then
		frame:SetPoint(p.point, UIParent, p.rel or p.point, p.x, p.y)
		-- a position saved by an older version (bottom/centre anchor): hold it by its top from now on
		if not (p.point == "TOPRIGHT" and p.rel == "BOTTOMLEFT") then anchorTop(true) end
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

-- Each heading cycles nearest, then highest level, then lowest level.
local SORT_NEXT = { low = "dist", dist = "high", high = "low" }
-- (small game icons, not "•" "↓" "↑": the game's font has none of those and draws an empty box)
local SORT_MARK = {
	dist = "|TInterface\\COMMON\\Indicator-Gray:12:12|t",
	high = "|TInterface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up:14:14|t",
	low = "|TInterface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up:14:14|t",
}
local SORT_TIP = { dist = "Nearest first", high = "Highest level first", low = "Lowest level first" }
local SORT_NEXT_TIP = { dist = "Click for highest level", high = "Click for lowest level", low = "Click for nearest" }
local function sortMode(key)
	local v = (db().questLevelSort or {})[key]
	if v == "high" or v == "dist" then return v end
	return "low"
end
local function setSortMode(key, mode)
	db().questLevelSort = db().questLevelSort or {}
	db().questLevelSort[key] = mode
end

local refresh -- forward

local function headRow(i)
	local h = heads[i]
	if h then return h end
	h = CreateFrame("Button", nil, content)
	h.sort = CreateFrame("Button", nil, h)
	h.sort:SetSize(16, 16)
	h.sort:SetPoint("RIGHT", -2, 0)
	h.sort:RegisterForClicks("LeftButtonUp")
	h.sort.label = font(h.sort:CreateFontString(nil, "OVERLAY"), 12)
	h.sort.label:SetPoint("CENTER")
	h.sort.label:SetTextColor(1, 0.9, 0.55)
	h.sort:SetScript("OnClick", function(self)
		local key = self:GetParent().key
		setSortMode(key, SORT_NEXT[sortMode(key)])
		refresh()
	end)
	h.sort:SetScript("OnEnter", function(self)
		local mode = sortMode(self:GetParent().key)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(SORT_TIP[mode], 1, 0.9, 0.55)
		GameTooltip:AddLine(SORT_NEXT_TIP[mode], 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	h.sort:SetScript("OnLeave", function() GameTooltip:Hide() end)
	h.text = font(h:CreateFontString(nil, "OVERLAY"), 12)
	h.text:SetPoint("LEFT", 6, 0)
	h.text:SetPoint("RIGHT", h.sort, "LEFT", -2, 0)
	h.text:SetJustifyH("LEFT")
	h.text:SetWordWrap(false)
	h:SetScript("OnClick", function(self) setFold(self.key, not folded(self.key)) refresh() end)
	heads[i] = h
	return h
end

---------------------------------------------------------------------------
-- Clicking a quest does what the game's own "..." quest button does: it
-- makes that quest the one the game follows (highlighted on the map, and
-- shown by the game's navigation). Clicking it again lets go.
-- Right-click opens it in the quest log.
---------------------------------------------------------------------------
local function trackedQuest()
	local id = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and safe(C_SuperTrack.GetSuperTrackedQuestID)
	return plain(id)
end

local function toggleTrack(q)
	if not (C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID) then return end
	if trackedQuest() == q.questID then
		pcall(C_SuperTrack.SetSuperTrackedQuestID, 0)
	else
		if C_QuestLog.SetSelectedQuest then pcall(C_QuestLog.SetSelectedQuest, q.questID) end
		pcall(C_SuperTrack.SetSuperTrackedQuestID, q.questID)
	end
	if PlaySound and SOUNDKIT and SOUNDKIT.UI_MAP_WAYPOINT_SUPER_TRACK_ON then
		PlaySound(SOUNDKIT.UI_MAP_WAYPOINT_SUPER_TRACK_ON)
	end
	refresh()
end

-- The same link the quest log copies. Prefer the game's own link, and build
-- one only if that call doesn't know this client.
local function questLink(q)
	local id = plain(q.questID)
	if type(id) ~= "number" then return end
	local index = plain(q.index)
	if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
		local got = plain(safe(C_QuestLog.GetLogIndexForQuestID, id))
		if type(got) == "number" then index = got end
	end
	local function matches(link)
		return type(link) == "string" and link:find("|Hquest:" .. id .. ":", 1, true) ~= nil
	end
	if GetQuestLink then
		local byID = plain(safe(GetQuestLink, id))
		if matches(byID) then return byID end
		if type(index) == "number" then
			local byIndex = plain(safe(GetQuestLink, index))
			if matches(byIndex) then return byIndex end
		end
	end
	local title = plain(q.title)
	if type(title) ~= "string" or title == "" then return end
	local level = plain(q.level)
	if type(level) ~= "number" then level = 0 end
	local hex = "ffffff00"
	if level > 0 and GetQuestDifficultyColor then
		local c = safe(GetQuestDifficultyColor, level)
		local r = type(c) == "table" and plain(c.r)
		local g = type(c) == "table" and plain(c.g)
		local b = type(c) == "table" and plain(c.b)
		if type(r) == "number" and type(g) == "number" and type(b) == "number" then
			hex = format("ff%02x%02x%02x", r * 255, g * 255, b * 255)
		end
	end
	return format("|c%s|Hquest:%d:%d|h[%s]|h|r", hex, id, level, title)
end

local function linkQuest(q)
	local link = questLink(q)
	if not link then return end
	if ChatEdit_InsertLink and plain(safe(ChatEdit_InsertLink, link)) then return end
	if ChatFrame_OpenChat then ChatFrame_OpenChat(link) end
end

local function openInLog(q)
	-- Several ways, as clients differ; stop at the first that opens the log.
	local function logOpen()
		local f = _G.QuestLogFrame or _G.QuestLogExFrame
		if f and f:IsShown() then return true end
		local w = _G.WorldMapFrame
		return w and w:IsShown() and _G.QuestMapFrame and _G.QuestMapFrame:IsShown() or false
	end
	-- The quest's place in the log now (it moves as quests come and go).
	local index = q.index
	if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
		index = ns.safe(C_QuestLog.GetLogIndexForQuestID, q.questID) or index
	end
	-- Classic-style quest log: select the quest, then show the log.
	local f = _G.QuestLogFrame
	if f and SelectQuestLogEntry then
		pcall(SelectQuestLogEntry, index)
		if not f:IsShown() then
			if ShowUIPanel then pcall(ShowUIPanel, f) end
			if not f:IsShown() and ToggleQuestLog then pcall(ToggleQuestLog) end
		end
		if _G.QuestLog_SetSelection then pcall(_G.QuestLog_SetSelection, index) end
		if _G.QuestLog_Update then pcall(_G.QuestLog_Update) end
		if logOpen() then return end
	end
	if _G.QuestLog_OpenToQuest then
		pcall(_G.QuestLog_OpenToQuest, index)
		if logOpen() then return end
		pcall(_G.QuestLog_OpenToQuest, q.questID)
		if logOpen() then return end
	end
	-- Newer quest log on the map.
	if _G.QuestMapFrame_OpenToQuestDetails then
		pcall(_G.QuestMapFrame_OpenToQuestDetails, q.questID)
		if logOpen() then return end
	end
	if _G.OpenQuestLog then pcall(_G.OpenQuestLog, q.questID) end
end

local function questRow(i)
	local r = rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, content)
	r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	-- Soft gold band behind the quest the game is following.
	r.sel = r:CreateTexture(nil, "BACKGROUND")
	r.sel:SetPoint("TOPLEFT", 2, 1)
	r.sel:SetPoint("BOTTOMRIGHT", -2, 1)
	r.sel:SetColorTexture(1, 0.82, 0, 0.14)
	r.sel:Hide()
	r.selBar = r:CreateTexture(nil, "ARTWORK")
	r.selBar:SetPoint("TOPLEFT", 2, 1)
	r.selBar:SetPoint("BOTTOMLEFT", 2, 1)
	r.selBar:SetWidth(2)
	r.selBar:SetColorTexture(1, 0.82, 0, 0.9)
	r.selBar:Hide()
	-- Level badge: a small box in the difficulty color with the level in it.
	r.badge = r:CreateTexture(nil, "ARTWORK")
	r.badge:SetSize(20, 13)
	r.badge:SetPoint("TOPLEFT", 10, 0)
	r.badgeText = font(r:CreateFontString(nil, "OVERLAY"), 10)
	r.badgeText:SetPoint("CENTER", r.badge, "CENTER", 0, 0)
	r.badgeText:SetTextColor(1, 1, 1)
	r.title = font(r:CreateFontString(nil, "OVERLAY"), 13)
	r.title:SetPoint("TOPLEFT", r.badge, "TOPRIGHT", 5, 0)
	r.title:SetPoint("RIGHT", -6, 0)
	r.title:SetJustifyH("LEFT")
	r.title:SetWordWrap(false)
	r.title:SetTextColor(1, 1, 1)
	r.lines = {}
	r:SetScript("OnClick", function(self, button)
		local q = self.quest
		if not q then return end
		if button == "RightButton" then openInLog(q)
		elseif IsShiftKeyDown() then linkQuest(q)
		else toggleTrack(q) end
	end)
	r:SetScript("OnEnter", function(self)
		self.title:SetAlpha(0.75)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(self.quest and self.quest.title or "Quest")
		if self.quest and self.quest.elite then GameTooltip:AddLine("Elite quest: a group is suggested", 1, 0.82, 0) end
		GameTooltip:AddLine("Click: follow this quest (map highlight). Click again to stop.", 1, 1, 1, true)
		GameTooltip:AddLine("Shift-click: paste it into chat.", 1, 1, 1, true)
		GameTooltip:AddLine("Right-click: open it in the quest log.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	r:SetScript("OnLeave", function(self) self.title:SetAlpha(1) GameTooltip:Hide() end)
	rows[i] = r
	return r
end

local function lineOf(r, j)
	local fs = r.lines[j]
	if fs then return fs end
	fs = font(r:CreateFontString(nil, "OVERLAY"), 11)
	fs:SetJustifyH("LEFT")
	fs:SetTextColor(0.8, 0.8, 0.8)
	r.lines[j] = fs
	return fs
end

local function levelColor(level)
	local c = level and GetQuestDifficultyColor and GetQuestDifficultyColor(level)
	if c then return c.r, c.g, c.b end
	return 1, 0.82, 0
end

local GROUPS = {
	{ key = "ready", label = "Ready to turn in", color = { 0.4, 1, 0.4 } },
	{ key = "here", label = "This zone", color = { 1, 0.82, 0 } },
	{ key = "other", label = "Other zones", color = { 0.7, 0.7, 0.7 }, foldByDefault = true },
}

refresh = function()
	if not on() then frame:Hide() return end
	local groups, total = readLog()
	for _, g in ipairs(GROUPS) do
		local mode = sortMode(g.key)
		if mode == "dist" then
			table.sort(groups[g.key], function(a, b)
				if a.dist and b.dist then return a.dist < b.dist end
				if a.dist or b.dist then return a.dist ~= nil end
				local al, bl = questLevel(a), questLevel(b)
				if al and bl and al ~= bl then return al < bl end
				if type(a.title) == "string" and type(b.title) == "string" then return a.title < b.title end
				return false
			end)
		else
			table.sort(groups[g.key], byLevel(mode == "high"))
		end
	end
	local tracked = trackedQuest() -- the quest the game is following
	title.count:SetFormattedText("%d/%d", total, MAX_QUESTLOG_QUESTS or 20)
	local y = 0 -- (from the top of the scrolling list)
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
			local mode = sortMode(g.key)
			h.sort:SetSize(Q(16), Q(16))
			h.sort.label:SetText(SORT_MARK[mode])
			h.sort:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:AddLine(SORT_TIP[mode], 1, 0.9, 0.55)
				GameTooltip:AddLine(SORT_NEXT_TIP[mode], 0.8, 0.8, 0.8)
				GameTooltip:Show()
			end)
			h:SetHeight(Q(18))
			h:ClearAllPoints()
			h:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
			h:SetPoint("RIGHT", content, "RIGHT")
			h:SetScript("OnClick", function()
				local cur = folded(g.key)
				if cur == nil then cur = g.foldByDefault or false end
				setFold(g.key, not cur)
				refresh()
			end)
			h:Show()
			y = y - Q(18)
			if not isFolded then
				for _, q in ipairs(list) do
					ri = ri + 1
					local r = questRow(ri)
					r.quest = q
					local isTracked = tracked == q.questID
					r.sel:SetShown(isTracked)
					r.selBar:SetShown(isTracked)
					local lr, lg, lb = levelColor(q.level)
					r.badge:SetColorTexture(lr * 0.75, lg * 0.75, lb * 0.75, 0.9)
					-- elite (group) quests: "30+", as the game writes it
					r.badgeText:SetText((q.level and tostring(q.level) or "?") .. (q.elite and "+" or ""))
					r.title:SetText(q.title)
					r.badge:SetSize(Q(q.elite and 25 or 20), Q(13))
					local ly, shown, lineH = -Q(15), 0, Q(12)
					-- A fixed width, so a long objective wraps and its real height is known.
					local lineW = Q(WIDTH) - 4 - (Q(20) + 16) - 4
					for _, o in ipairs(q.objectives) do
						if not o.done and not q.ready then
							shown = shown + 1
							local fs = lineOf(r, shown)
							fs:ClearAllPoints()
							fs:SetPoint("TOPLEFT", r, "TOPLEFT", Q(20) + 16, ly)
							fs:SetWidth(lineW)
							fs:SetText("- " .. o.text)
							fs:Show()
							ly = ly - math.max(lineH, math.ceil(fs:GetStringHeight()) + 1)
						end
					end
					for j = shown + 1, #r.lines do r.lines[j]:Hide() end
					local height = -ly + 4
					r:SetHeight(height)
					r:ClearAllPoints()
					r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
					r:SetPoint("RIGHT", content, "RIGHT", -4, 0) -- (room for the scroll bar)
					r:Show()
					y = y - height
				end
			end
			y = y - 4
		end
	end
	for i = hi + 1, #heads do heads[i]:Hide() end
	for i = ri + 1, #rows do rows[i]:Hide() end
	local listH = math.max(1, -y)
	content:SetHeight(listH)
	local view = math.min(listH, viewLimit())
	scroll:SetHeight(view)
	frame:SetHeight(TOP_GAP + view + 4)
	scrollTo(scroll:GetVerticalScroll()) -- (keep the place, within the new length)
	frame:SetShown(total > 0)
end

---------------------------------------------------------------------------
-- Text size: the fonts, then everything sized from them.
local function applyFonts()
	scale = fontSize() / BASE_FONT
	for size, fo in pairs(fontObjs) do
		local src = _G[FONTS[size] or "GameFontHighlight"]
		local path, _, flags = src and src:GetFont()
		if path then fo:SetFont(path, Q(size), flags or "") end
	end
	title:SetHeight(Q(20))
	TOP_GAP = Q(20) + 4
	scroll:SetPoint("TOPLEFT", 0, -TOP_GAP)
	scroll:SetPoint("TOPRIGHT", 0, -TOP_GAP)
	frame:SetWidth(Q(WIDTH))
	content:SetWidth(Q(WIDTH))
end

---------------------------------------------------------------------------
-- In combat the tracker dims to 30% (mouse over it to read it), and comes
-- back 3 seconds after the fight.
---------------------------------------------------------------------------
-- Moved: the room below it changed, so fit the list again.
title:HookScript("OnDragStop", function() refresh() end)

local FIGHT_ALPHA, AFTER = 0.3, 3
local lastFight, alpha = 0, 1
frame:SetScript("OnUpdate", function(self, elapsed)
	if UnitAffectingCombat("player") then lastFight = GetTime() end
	local goal = (GetTime() - lastFight < AFTER and not self:IsMouseOver()) and FIGHT_ALPHA or 1
	if alpha == goal then return end
	-- Dim gently, come back quickly.
	local step = elapsed * (goal > alpha and 5 or 2)
	alpha = goal > alpha and math.min(goal, alpha + step) or math.max(goal, alpha - step)
	self:SetAlpha(alpha)
end)

---------------------------------------------------------------------------
-- The game's own tracker steps aside while this one is on
---------------------------------------------------------------------------
local hideBlizzard
local hooked = {}
-- The game can put its tracker back after we hid it (its UI loads late, or gets moved back to the
-- screen on a /reload): hide it again whenever it's moved back or shown.
local function watch(f)
	if hooked[f] then return end
	hooked[f] = true
	local function again() C_Timer.After(0, hideBlizzard) end
	if f.SetParent then hooksecurefunc(f, "SetParent", function(_, parent)
		if parent ~= _G.ZydeForeverHidden then again() end
	end) end
	if f.HookScript then f:HookScript("OnShow", function(self)
		if self:GetParent() ~= _G.ZydeForeverHidden then again() end
	end) end
end

hideBlizzard = function()
	if InCombatLockdown() or not on() then return end
	for _, f in ipairs({ _G.ObjectiveTrackerFrame, _G.QuestWatchFrame, _G.WatchFrame }) do
		if f then
			ns.stash(f)
			watch(f)
		end
	end
end

local pending = false
local function refreshSoon()
	if pending then return end
	pending = true
	C_Timer.After(0.2, function() pending = false refresh() end)
end

-- Questie's own tracker: off while this one is on (Questie's "Enable Tracker"
-- setting). Turned back on only if Zyde was the one that turned it off.
local function setQuestieTracker(wantOff)
	local Q = rawget(_G, "Questie")
	local p = type(Q) == "table" and Q.db and Q.db.profile
	if type(p) ~= "table" then return end
	if wantOff then
		if p.trackerEnabled then
			p.trackerEnabled = false
			db().questieTrackerOff = true
		end
		-- (already built this session: its next update hides it; hide it now too)
		local ok, T = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieTracker")
		if ok and type(T) == "table" and T.started and T.Update then pcall(T.Update, T) end
		local base = rawget(_G, "Questie_BaseFrame")
		if base and base:IsShown() and not InCombatLockdown() then base:Hide() end
	elseif db().questieTrackerOff then
		p.trackerEnabled = true
		db().questieTrackerOff = nil
		print(P .. "Questie's quest tracker comes back after a /reload")
	end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" then
		-- the game's tracker loading after login: hide it as it arrives
		if type(name) == "string" and name:find("^Blizzard_") and (name:find("Tracker") or name:find("Watch")) then
			C_Timer.After(0, hideBlizzard)
		end
		return
	end
	if event == "PLAYER_LOGIN" then
		if QuestieLoader then
			-- before Questie starts its tracker (it does so after login)
			pcall(setQuestieTracker, on())
		end
		if QuestieLoader and QuestieLoader.ImportModule then
			DB = select(2, pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB"))
			ZDB = select(2, pcall(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB"))
			if type(DB) ~= "table" then DB = nil end
			if type(ZDB) ~= "table" then ZDB = nil end
		end
		applyFonts()
		if not on() then return end
		place()
		for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "UNIT_QUEST_LOG_CHANGED", "ZONE_CHANGED_NEW_AREA",
			"ZONE_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_LEVEL_UP", "SUPER_TRACKING_CHANGED" }) do
			pcall(ev.RegisterEvent, ev, e)
		end
		-- Re-sort as you move, so two quests of the same level stay nearest-first.
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
	if QuestieLoader then pcall(setQuestieTracker, on()) end
end)

ns.QuestTracker = {
	-- The /zyde window's text size slider.
	GetFontSize = fontSize,
	SetFontSize = function(size)
		db().questTrackerFont = (size ~= BASE_FONT) and size or nil
		applyFonts()
		if on() then refresh() end
	end,
	-- /zyde questheight <pixels>: the tallest the list gets before it scrolls (0 = down to the screen's bottom).
	SetMaxHeight = function(px)
		if not px then
			local cap = tonumber(db().questTrackerMaxHeight)
			print(P .. "quest list height: " .. ((cap and cap > 0) and (cap .. " pixels")
				or (cap and cap < 0) and "down to the bottom of the screen" or "two-thirds of the screen (default)")
				.. ". /zyde questheight <pixels> to change it (0 = to the bottom of the screen)")
			return
		end
		db().questTrackerMaxHeight = px > 0 and px or -1
		refresh()
		print(P .. "quest list " .. (px > 0 and ("now scrolls past " .. px .. " pixels") or "now runs to the bottom of the screen"))
	end,
	ResetPosition = function()
		db().questTrackerPos = nil
		place()
		refresh()
		print(P .. "quest tracker moved back to its default spot")
	end,
}
