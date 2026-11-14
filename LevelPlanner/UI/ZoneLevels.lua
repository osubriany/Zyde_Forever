-- ZoneLevels: on the world map, hovering a zone shows its level range under the zone's name,
-- coloured for you: grey (too low), green, yellow (right for you), orange, red (too high).
-- Level ranges come from the game (C_Map.GetMapLevels) when it has them, else from the classic
-- ranges below. Only reads the map and draws its own text: it never changes Blizzard's map frames
-- (on Forever, touching them breaks things).
local ADDON, zyde = ...
-- Part of Zyde_Forever since 2026-11-14: LevelPlanner keeps its own private table (zyde.LP) so its
-- names never clash with Zyde's.
zyde.LP = zyde.LP or {}
local ns = zyde.LP

local ZL = {}
ns.ZoneLevels = ZL

-- Classic level ranges by uiMapID (used when the game has none).
local RANGES = {
	-- Kalimdor
	[1411] = { 1, 10 },   -- Durotar
	[1412] = { 1, 10 },   -- Mulgore
	[1438] = { 1, 10 },   -- Teldrassil
	[1439] = { 10, 20 },  -- Darkshore
	[1413] = { 10, 25 },  -- The Barrens
	[1442] = { 15, 27 },  -- Stonetalon Mountains
	[1440] = { 18, 30 },  -- Ashenvale
	[1441] = { 25, 35 },  -- Thousand Needles
	[1443] = { 30, 40 },  -- Desolace
	[1445] = { 35, 45 },  -- Dustwallow Marsh
	[1444] = { 40, 50 },  -- Feralas
	[1446] = { 40, 50 },  -- Tanaris
	[1447] = { 45, 55 },  -- Azshara
	[1448] = { 48, 55 },  -- Felwood
	[1449] = { 48, 55 },  -- Un'Goro Crater
	[1451] = { 55, 60 },  -- Silithus
	[1452] = { 55, 60 },  -- Winterspring
	-- Eastern Kingdoms
	[1429] = { 1, 10 },   -- Elwynn Forest
	[1426] = { 1, 10 },   -- Dun Morogh
	[1420] = { 1, 10 },   -- Tirisfal Glades
	[1436] = { 10, 20 },  -- Westfall
	[1432] = { 10, 20 },  -- Loch Modan
	[1421] = { 10, 20 },  -- Silverpine Forest
	[1433] = { 15, 25 },  -- Redridge Mountains
	[1431] = { 18, 30 },  -- Duskwood
	[1437] = { 20, 30 },  -- Wetlands
	[1424] = { 20, 30 },  -- Hillsbrad Foothills
	[1416] = { 30, 40 },  -- Alterac Mountains
	[1417] = { 30, 40 },  -- Arathi Highlands
	[1434] = { 30, 45 },  -- Stranglethorn Vale
	[1418] = { 35, 45 },  -- Badlands
	[1435] = { 35, 45 },  -- Swamp of Sorrows
	[1425] = { 40, 50 },  -- The Hinterlands
	[1427] = { 43, 50 },  -- Searing Gorge
	[1419] = { 45, 55 },  -- Blasted Lands
	[1428] = { 50, 58 },  -- Burning Steppes
	[1422] = { 51, 58 },  -- Western Plaguelands
	[1423] = { 53, 60 },  -- Eastern Plaguelands
	[1430] = { 55, 60 },  -- Deadwind Pass
}

local function levelsOf(mapID)
	if C_Map.GetMapLevels then
		local lo, hi = ns.safe(C_Map.GetMapLevels, mapID)
		if lo and hi and lo > 0 and hi > 0 and not ns.isSecret(lo) then return lo, hi end
	end
	local r = RANGES[mapID]
	if r then return r[1], r[2] end
	return nil
end

-- Colour for a range against your level: the same idea as quest colours.
local function colourFor(lo, hi)
	local L = ns.playerLevel()
	local green = (C_QuestLog and C_QuestLog.GetTrivialRange and ns.safe(C_QuestLog.GetTrivialRange))
		or (GetQuestGreenRange and ns.safe(GetQuestGreenRange)) or 8
	if hi < L - green then return 0.62, 0.62, 0.62, "grey" end       -- everything grey
	if lo > L + 4 then return 1, 0.15, 0.15, "red" end
	if lo > L + 2 then return 1, 0.5, 0.25, "orange" end
	if L >= lo and L <= hi then return 1, 0.82, 0, "yellow" end       -- right for you
	if hi < L then return 0.25, 0.75, 0.25, "green" end
	return 1, 0.82, 0, "yellow"
end

local label, lastZone
local elapsed = 0

local function update()
	if not WorldMapFrame:IsShown() then label:Hide() return end
	local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
	local sc = WorldMapFrame.ScrollContainer
	if not (mapID and sc and sc.GetNormalizedCursorPosition and sc:IsMouseOver()) then label:Hide() lastZone = nil return end
	local x, y = sc:GetNormalizedCursorPosition()
	if not x then label:Hide() return end
	-- the zone under the cursor (on a continent map), or the zone being shown itself
	local zone = mapID
	local info = C_Map.GetMapInfo(mapID)
	if info and Enum and Enum.UIMapType and info.mapType ~= Enum.UIMapType.Zone then
		local under = ns.safe(C_Map.GetMapInfoAtPosition, mapID, x, y)
		zone = under and under.mapID ~= mapID and under.mapID or nil
	end
	local lo, hi
	if zone then lo, hi = levelsOf(zone) end
	if not lo then label:Hide() lastZone = nil return end
	if zone ~= lastZone then
		lastZone = zone
		local r, g, b = colourFor(lo, hi)
		label:SetText(lo == hi and ("Level " .. lo) or ("Level " .. lo .. "-" .. hi))
		label:SetTextColor(r, g, b)
	end
	label:Show()
end

function ZL.Init()
	if ns.cfg.zoneLevels == false or label or not (WorldMapFrame and WorldMapFrame.ScrollContainer) then return end
	local holder = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer)
	holder:SetAllPoints(WorldMapFrame.ScrollContainer)
	holder:SetFrameLevel(WorldMapFrame.ScrollContainer:GetFrameLevel() + 3000)
	label = holder:CreateFontString(nil, "OVERLAY")
	label:SetFont(STANDARD_TEXT_FONT, 15, "OUTLINE")
	-- just under the game's own zone name at the top of the map
	label:SetPoint("TOP", holder, "TOP", 0, -46)
	label:Hide()
	holder:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < 0.05 then return end
		elapsed = 0
		update()
	end)
end
