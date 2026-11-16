-- MapPins: numbered pins for the next few steps on the world map and minimap, joined by a dotted
-- trail on the world map.
-- LevelPlanner draws these itself. (Questie 12.9 made its pin library private; pins placed in it
-- made Questie's map tooltip print "handleMapIcon ... Aborting!" for every LevelPlanner pin.)
-- World map: our own layer on the map's canvas, so pins move and zoom with the map.
-- Minimap: our own layer on the minimap, placed from your position and the minimap's view radius.
local ADDON, zyde = ...
-- Part of Zyde_Forever since 2026-11-14: LevelPlanner keeps its own private table (zyde.LP) so its
-- names never clash with Zyde's.
zyde.LP = zyde.LP or {}
local ns = zyde.LP

local M = {}
ns.MapPins = M

local PIN = "Interface\\AddOns\\Zyde_Forever\\LevelPlanner\\Media\\Pin"
local DOT = "Interface\\AddOns\\Zyde_Forever\\LevelPlanner\\Media\\Dot"
local RING_NOW = { 0.35, 1, 0.55 }   -- next step: green
local RING_LATER = { 1, 0.82, 0.25 } -- later steps: gold
local DOT_STEP = 0.015   -- one trail dot per 1.5% of the map
local MAX_DOTS = 40       -- per leg

local places = {}         -- the next steps with a place: {point, label}
local worldLayer, miniLayer
local worldPins, miniPins, dots = {}, {}, {}
local vec = CreateVector2D

----------------------------------------------------------------------------------------
-- Pins
----------------------------------------------------------------------------------------

-- Dark disc with a coloured ring and a white, outlined number: readable on light and dark maps.
local function numberPin(pool, parent, i, size)
	local f = pool[i]
	if not f then
		f = CreateFrame("Frame", nil, parent)
		f:SetSize(size, size)
		local tex = f:CreateTexture(nil, "ARTWORK")
		tex:SetAllPoints()
		tex:SetTexture(PIN)
		f.tex = tex
		local fs = f:CreateFontString(nil, "OVERLAY")
		fs:SetFont(STANDARD_TEXT_FONT, math.floor(size * 0.55), "OUTLINE")
		fs:SetPoint("CENTER", 0, 0)
		fs:SetTextColor(1, 1, 1)
		f.text = fs
		f:EnableMouse(true)
		f:SetScript("OnEnter", function(self)
			if not self.label then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine("LevelPlanner - step " .. (self.index or "?"))
			GameTooltip:AddLine(self.label, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		f:SetScript("OnLeave", function() GameTooltip:Hide() end)
		pool[i] = f
	end
	return f
end

-- A trail dot from a pool (world map or minimap), in the given colour.
local function poolDot(pool, parent, i, size, colour)
	local f = pool[i]
	if not f then
		f = CreateFrame("Frame", nil, parent)
		f:SetSize(size, size)
		f.tex = f:CreateTexture(nil, "ARTWORK")
		f.tex:SetAllPoints()
		f.tex:SetTexture(DOT)
		f.tex:SetAlpha(0.9)
		pool[i] = f
	end
	f.tex:SetVertexColor(colour[1], colour[2], colour[3])
	return f
end
local function dot(i, colour) return poolDot(dots, worldLayer, i, 9, colour or RING_LATER) end

-- The next steps with a place, one per location (several turn-ins at one NPC = one pin).
local function placesOf(plan, max)
	local out = {}
	for _, s in ipairs(plan and plan.stops or {}) do
		local p = s.point
		if p and p.wx then
			local last = out[#out]
			local d = last and ns.Geo.Distance(last.point, p)
			if last and d and d < 40 then
				last.label = last.label .. "\n" .. (s.label or "")
			else
				out[#out + 1] = { point = p, label = s.label or s.questName or "" }
				if #out >= max then break end
			end
		end
	end
	return out
end

----------------------------------------------------------------------------------------
-- World map
----------------------------------------------------------------------------------------

-- Where a point is on the map being shown (0-1), or nil when it isn't on it.
local function onMap(p, mapID)
	if p.map == mapID and p.x and p.y then return p.x / 100, p.y / 100 end
	if not (C_Map.GetMapPosFromWorldPos and vec and p.inst) then return nil end
	local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, p.inst, vec(p.wy, p.wx), mapID)
	if not ok or not pos then return nil end
	local x, y = pos:GetXY()
	if not x or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
	return x, y
end

-- Hidden along with the step list (/lp).
local function listHidden() return ns.char and ns.char.listHidden end

local function drawWorld()
	if not worldLayer then return end
	for _, f in ipairs(worldPins) do f:Hide() end
	for _, f in ipairs(dots) do f:Hide() end
	if ns.cfg.mapPins == false or listHidden() or not WorldMapFrame:IsShown() then return end
	local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
	if not mapID then return end
	local w, h = worldLayer:GetWidth(), worldLayer:GetHeight()
	if not w or w <= 0 then return end
	-- keep pins the same size on screen however far the map is zoomed
	local zoom = WorldMapFrame.ScrollContainer.GetCanvasScale and WorldMapFrame.ScrollContainer:GetCanvasScale() or 1
	local scale = 1 / math.max(zoom, 0.01)
	local nDots, prev = 0, nil
	-- the trail starts at you: a green line from your position to the next stop
	local here = ns.Geo.PlayerPoint()
	if here then
		local px, py = onMap(here, mapID)
		if px then prev = { px, py, fromYou = true } end
	end
	for i, pl in ipairs(places) do
		local x, y = onMap(pl.point, mapID)
		if x then
			local f = numberPin(worldPins, worldLayer, i, 24)
			f.index, f.label = i, pl.label
			f.text:SetText(i)
			local ring = (i == 1) and RING_NOW or RING_LATER
			f.tex:SetVertexColor(ring[1], ring[2], ring[3])
			f:SetScale(scale)
			f:ClearAllPoints()
			f:SetPoint("CENTER", worldLayer, "TOPLEFT", x * w / scale, -y * h / scale)
			f:SetFrameLevel(worldLayer:GetFrameLevel() + 10)
			f:Show()
			-- trail from the previous pin; a gap is left next to each pin so dots never cover numbers
			if prev then
				local len = math.sqrt((x - prev[1]) ^ 2 + (y - prev[2]) ^ 2)
				local count = math.min(MAX_DOTS, math.floor(len / DOT_STEP))
				for k = 2, count - 2 do
					local t = k / count
					nDots = nDots + 1
					local d = dot(nDots, prev.fromYou and RING_NOW or RING_LATER)
					d:SetScale(scale)
					d:ClearAllPoints()
					d:SetPoint("CENTER", worldLayer, "TOPLEFT",
						(prev[1] + (x - prev[1]) * t) * w / scale, -(prev[2] + (y - prev[2]) * t) * h / scale)
					d:SetFrameLevel(worldLayer:GetFrameLevel() + 5)
					d:Show()
				end
			end
			prev = { x, y }
		else
			prev = nil
		end
	end
end

local function setupWorld()
	if worldLayer or not (WorldMapFrame and WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child) then return end
	local canvas = WorldMapFrame.ScrollContainer.Child
	worldLayer = CreateFrame("Frame", nil, canvas)
	worldLayer:SetAllPoints(canvas)
	worldLayer:SetFrameLevel(canvas:GetFrameLevel() + 2000)
	-- only listen; never hand the map our functions or call its own methods (Forever taint lesson)
	WorldMapFrame:HookScript("OnShow", drawWorld)
	if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", drawWorld) end
	local lastZoom, since = nil, 0
	worldLayer:SetScript("OnUpdate", function(_, dt)
		local z = WorldMapFrame.ScrollContainer.GetCanvasScale and WorldMapFrame.ScrollContainer:GetCanvasScale()
		since = since + dt
		-- redraw on zoom, and twice a second so the line from you follows you
		if z ~= lastZoom or since >= 0.5 then lastZoom, since = z, 0 drawWorld() end
	end)
end

----------------------------------------------------------------------------------------
-- Minimap
----------------------------------------------------------------------------------------
-- Minimap view diameter in yards by zoom level, for clients without C_Minimap.GetViewRadius.
local VIEW = {
	indoor = { [0] = 300, 240, 180, 120, 80, 50 },
	outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
}

local function minimapRadius()
	if C_Minimap and C_Minimap.GetViewRadius then
		local r = ns.safe(C_Minimap.GetViewRadius)
		if r and r > 0 then return r end
	end
	local zoom = Minimap:GetZoom()
	local list = (IsIndoors and IsIndoors()) and VIEW.indoor or VIEW.outdoor
	return (list[zoom] or 466) / 2
end

local miniElapsed = 0
local miniDots = {}
local function drawMini()
	for _, f in ipairs(miniPins) do f:Hide() end
	for _, f in ipairs(miniDots) do f:Hide() end
	if ns.cfg.minimapPins == false or listHidden() or #places == 0 then return end
	local here = ns.Geo.PlayerPoint()
	if not here then return end
	local radius = minimapRadius()
	local half = Minimap:GetWidth() / 2
	local rotate = GetCVar and GetCVar("rotateMinimap") == "1"
	local facing = rotate and GetPlayerFacing and GetPlayerFacing() or 0
	if ns.isSecret(facing) then facing = 0 end
	for i, pl in ipairs(places) do
		local p = pl.point
		if p.inst == here.inst then
			-- world: wx grows west, wy grows north; minimap: x east, y north
			local east, north = here.wx - p.wx, p.wy - here.wy
			if rotate then
				-- the minimap turns with you: rotate by -facing (facing grows counter-clockwise)
				local c, s = math.cos(facing), math.sin(facing)
				east, north = east * c + north * s, -east * s + north * c
			end
			local dist = math.sqrt(east * east + north * north)
			local edge = dist > radius
			-- only the next step stays on the minimap's edge when it's out of range
			if not edge or i == 1 then
				if edge then east, north = east / dist * radius, north / dist * radius end
				local sx, sy = east / radius * half * 0.92, north / radius * half * 0.92
				-- green dots from you (the minimap's centre) toward the next stop
				if i == 1 then
					local len = math.sqrt(sx * sx + sy * sy)
					local count = math.floor(len / 10)
					for k = 2, count - 1 do
						local t = k / count
						local d = poolDot(miniDots, miniLayer, k, 6, RING_NOW)
						d:ClearAllPoints()
						d:SetPoint("CENTER", miniLayer, "CENTER", sx * t, sy * t)
						d:Show()
					end
				end
				local f = numberPin(miniPins, miniLayer, i, i == 1 and 20 or 16)
				f.index, f.label = i, pl.label
				f.text:SetText(i)
				local ring = (i == 1) and RING_NOW or RING_LATER
				f.tex:SetVertexColor(ring[1], ring[2], ring[3])
				f:ClearAllPoints()
				f:SetPoint("CENTER", miniLayer, "CENTER", east / radius * half * 0.92, north / radius * half * 0.92)
				f:Show()
			end
		end
	end
end

local function setupMini()
	if miniLayer or not Minimap then return end
	miniLayer = CreateFrame("Frame", nil, Minimap)
	miniLayer:SetAllPoints(Minimap)
	miniLayer:SetFrameLevel(Minimap:GetFrameLevel() + 5)
	miniLayer:SetScript("OnUpdate", function(_, dt)
		miniElapsed = miniElapsed + dt
		if miniElapsed < 0.1 then return end
		miniElapsed = 0
		drawMini()
	end)
end

----------------------------------------------------------------------------------------
function M.Clear()
	wipe(places)
	drawWorld()
	for _, f in ipairs(miniPins) do f:Hide() end
end

-- Draw again as things are (after /lp showed or hid the step list).
function M.Redraw()
	drawWorld()
	drawMini()
end

function M.Update(plan)
	setupWorld()
	setupMini()
	places = (ns.cfg.mapPins ~= false or ns.cfg.minimapPins ~= false)
		and placesOf(plan, ns.cfg.mapPinSteps or 5) or {}
	drawWorld()
	drawMini()
end
