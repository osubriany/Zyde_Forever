-- Zyde_Forever: a few looks for the minimap. The zone name and your local
-- time (your clock, not the server's) sit under it. Round and Gilded are circles; Square is a square.
-- Off while SexyMap is loaded.

local _, ns = ...
local isSecret = ns.isSecret

local LOOKS = {
	{ key = "round", label = "Round", desc = "A circle with a thin ring. The zone name and your local time sit under the map." },
	{ key = "gilded", label = "Gilded", desc = "A circle with a gold ring. The zone name and your local time sit under the map." },
	{ key = "square", label = "Square", desc = "A square with a thin edge. Drag the map to move it. The zone name and your local time sit under it." },
}
local BY_KEY = {}
for _, look in ipairs(LOOKS) do BY_KEY[look.key] = look end

local CIRCLE = "Interface\\Masks\\CircleMaskScalable"
local CIRCLE_FALLBACK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local SQUARE = "Interface\\Buttons\\WHITE8X8"
local RING = "Interface\\Minimap\\MiniMap-TrackingBorder"

local function db() ZydeForeverDB = ZydeForeverDB or {} return ZydeForeverDB end
local function on() return ns.F("minimap") end

local function font(fs, size)
	if not fs:SetFont("Fonts\\FRIZQT__.TTF", size, "OUTLINE") then fs:SetFontObject("GameFontHighlight") end
end

local function lookKey()
	local k = db().minimapLook
	if BY_KEY[k] then return k end
	return "round"
end

local host = CreateFrame("Frame", nil, Minimap:GetParent() or UIParent)
host:SetFrameStrata(Minimap:GetFrameStrata() or "LOW")
host:SetFrameLevel(math.max(0, (Minimap:GetFrameLevel() or 1) - 1))
host:EnableMouse(false)
host:Hide()

local ring = host:CreateTexture(nil, "ARTWORK")
ring:SetTexture(RING)
ring:Hide()

local edges = {}
for i = 1, 4 do
	local t = host:CreateTexture(nil, "ARTWORK")
	t:SetColorTexture(1, 1, 1, 1)
	t:Hide()
	edges[i] = t
end

local panel = CreateFrame("Frame", nil, UIParent)
panel:SetHeight(40)
panel:SetFrameStrata("MEDIUM")
panel:EnableMouse(true)
panel:SetMovable(true)
panel:RegisterForDrag("LeftButton")
panel:Hide()
local zone = panel:CreateFontString(nil, "OVERLAY")
font(zone, 13)
zone:SetPoint("TOP", panel, "TOP", 0, 0)
zone:SetJustifyH("CENTER")
zone:SetWordWrap(false)
local localTime = panel:CreateFontString(nil, "OVERLAY")
font(localTime, 11)
-- Just your own clock, centered under the zone (no server time).
localTime:SetPoint("TOP", panel, "TOP", 0, -18)
localTime:SetJustifyH("CENTER")
localTime:SetWordWrap(false)

local concealed = {}
local function conceal(f)
	if not f or concealed[f] then return end
	concealed[f] = true
	if not f.zydeMinimapHook then
		f.zydeMinimapHook = true
		pcall(hooksecurefunc, f, "Show", function(self)
			if on() and concealed[self] then self:Hide() end
		end)
	end
	pcall(f.Hide, f)
end

-- The game clock (the bare "6:03" above the map). Our own times sit under the map.
local function hideClock()
	if not on() then return end
	local clock = TimeManagerClockButton
	if clock and not clock.zydeClockHook then
		clock.zydeClockHook = true
		clock:HookScript("OnShow", function(self)
			if on() then self:Hide() end
		end)
		if hooksecurefunc and clock.SetPoint then
			hooksecurefunc(clock, "SetPoint", function()
				if on() then clock:Hide() end
			end)
		end
	end
	if clock then clock:Hide() end
	if TimeManagerClockTicker and TimeManagerClockTicker.Hide then TimeManagerClockTicker:Hide() end
end

local function revealAll()
	for f in pairs(concealed) do
		concealed[f] = nil
		f:Show()
	end
end

local function blizzBits()
	-- The round frame and the game's own zone line. Ours is the one under the map.
	for _, f in ipairs({
		MinimapBackdrop, MinimapBorder, MinimapBorderTop, MinimapCompassTexture,
		MinimapZoneText, MinimapZoneTextButton, TimeManagerClockButton,
	}) do
		conceal(f)
	end
	local cluster = MinimapCluster
	if cluster then
		conceal(cluster.BorderTop)
		conceal(cluster.ZoneTextButton)
		conceal(cluster.ZoneText)
	end
	hideClock()
	local box = MinimapCluster and MinimapCluster.MinimapContainer
	if box and box.PlayerCoords then conceal(box.PlayerCoords) end
	-- The + and - that fade in while the cursor is over the map.
	conceal(Minimap.ZoomIn)
	conceal(Minimap.ZoomOut)
	conceal(MinimapZoomIn)
	conceal(MinimapZoomOut)
end

local SQUARE_MASKS = {
	SQUARE,
	"Interface\\BUTTONS\\WHITE8X8",
	"Interface\\Tooltips\\UI-Tooltip-Background",
}
local function mask(kind)
	if not Minimap.SetMaskTexture then return end
	if kind == "square" then
		for _, path in ipairs(SQUARE_MASKS) do
			if pcall(Minimap.SetMaskTexture, Minimap, path) then return end
		end
		return
	end
	if not pcall(Minimap.SetMaskTexture, Minimap, CIRCLE) then
		pcall(Minimap.SetMaskTexture, Minimap, CIRCLE_FALLBACK)
	end
end

local function restoreMask()
	if not Minimap.SetMaskTexture then return end
	if not pcall(Minimap.SetMaskTexture, Minimap, CIRCLE) then
		pcall(Minimap.SetMaskTexture, Minimap, CIRCLE_FALLBACK)
	end
end

local function placeBorder(key)
	local square = key == "square"
	ring:ClearAllPoints()
	if square then
		ring:Hide()
		host:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 3)
		host:ClearAllPoints()
		host:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -1, 1)
		host:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 1, -1)
		local r, g, b = 0.75, 0.75, 0.78
		for _, t in ipairs(edges) do t:SetVertexColor(r, g, b, 1) t:Show() end
		edges[1]:ClearAllPoints()
		edges[1]:SetPoint("TOPLEFT")
		edges[1]:SetPoint("TOPRIGHT")
		edges[1]:SetHeight(2)
		edges[2]:ClearAllPoints()
		edges[2]:SetPoint("BOTTOMLEFT")
		edges[2]:SetPoint("BOTTOMRIGHT")
		edges[2]:SetHeight(2)
		edges[3]:ClearAllPoints()
		edges[3]:SetPoint("TOPLEFT")
		edges[3]:SetPoint("BOTTOMLEFT")
		edges[3]:SetWidth(2)
		edges[4]:ClearAllPoints()
		edges[4]:SetPoint("TOPRIGHT")
		edges[4]:SetPoint("BOTTOMRIGHT")
		edges[4]:SetWidth(2)
	else
		-- A disc a few pixels larger than the map, drawn behind it. The map
		-- covers the middle, so what shows is a ring the size of the circle.
		for _, t in ipairs(edges) do t:Hide() end
		local w = Minimap:GetWidth()
		if isSecret(w) or type(w) ~= "number" or w < 40 then w = 140 end
		local thick = 3
		host:SetFrameLevel(math.max(0, (Minimap:GetFrameLevel() or 1) - 1))
		host:ClearAllPoints()
		host:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
		host:SetSize(w + thick * 2, w + thick * 2)
		ring:SetAllPoints()
		if not ring:SetTexture(CIRCLE) then ring:SetTexture(CIRCLE_FALLBACK) end
		local r, g, b = 0.55, 0.55, 0.58
		if key == "gilded" then r, g, b = 1, 0.78, 0.25 end
		ring:SetVertexColor(r, g, b, 1)
		ring:Show()
	end
end

local function zoneColor()
	local pvp = GetZonePVPInfo and GetZonePVPInfo()
	if isSecret(pvp) then return 1, 0.82, 0 end
	if pvp == "sanctuary" then return 0.41, 0.8, 0.94 end
	if pvp == "friendly" then return 0.1, 0.9, 0.1 end
	if pvp == "hostile" then return 1, 0.15, 0.15 end
	if pvp == "contested" then return 1, 0.7, 0 end
	return 1, 0.82, 0
end

local function paintZone()
	local text
	if GetMinimapZoneText then text = GetMinimapZoneText() end
	if (not text or text == "") and GetSubZoneText then text = GetSubZoneText() end
	if (not text or text == "") and GetZoneText then text = GetZoneText() end
	if isSecret(text) then
		zone:SetText(text)
		zone:SetTextColor(1, 0.82, 0)
		return
	end
	zone:SetText(type(text) == "string" and text or "")
	zone:SetTextColor(zoneColor())
end

local function hour12(h, m)
	if type(h) ~= "number" or type(m) ~= "number" then return nil end
	local ap = h >= 12 and "PM" or "AM"
	h = h % 12
	if h == 0 then h = 12 end
	return string.format("%d:%02d %s", h, m, ap)
end

-- Where you are on this zone's map, "44.2, 40.8". nil inside a dungeon or when hidden.
local function coordsText()
	if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
	local map = ns.safe(C_Map.GetBestMapForUnit, "player")
	if isSecret(map) or type(map) ~= "number" then return nil end
	local pos = ns.safe(C_Map.GetPlayerMapPosition, map, "player")
	if type(pos) ~= "table" or not pos.GetXY then return nil end
	local x, y = pos:GetXY()
	if isSecret(x) or isSecret(y) or type(x) ~= "number" or type(y) ~= "number" then return nil end
	if x == 0 and y == 0 then return nil end
	return string.format("%.1f, %.1f", x * 100, y * 100)
end

-- The second line: "44.2, 40.8  ·  6:40 AM" (coordinates in gray, time in white).
local function paintTimes()
	local stamp = date("*t")
	local clock = stamp and hour12(stamp.hour, stamp.min)
	local where = coordsText()
	if where and clock then
		localTime:SetText("|cff9a9aa2" .. where .. "|r  |cff555560·|r  " .. clock)
	elseif clock then
		localTime:SetText(clock)
	end
end

-- The square used to fill the whole minimap, so its corner covered the ZF button.
local nativeW, nativeH
local fitting = false
local SQUARE_INSET = 8

local function rememberNative()
	if nativeW then return end
	local w, h = Minimap:GetWidth(), Minimap:GetHeight()
	if isSecret(w) or isSecret(h) or type(w) ~= "number" or type(h) ~= "number" then return end
	if w < 40 or h < 40 then return end
	nativeW, nativeH = w, h
end
rememberNative()

local function fitSquare(square)
	rememberNative()
	if not nativeW or fitting or InCombatLockdown() then return end
	fitting = true
	local w = square and math.max(40, nativeW - SQUARE_INSET * 2) or nativeW
	local h = square and math.max(40, nativeH - SQUARE_INSET * 2) or nativeH
	pcall(Minimap.SetSize, Minimap, w, h)
	fitting = false
end

-- Blizzard (and Leatrix) draw the player coordinates just under the map.
local function playerCoords()
	local box = MinimapCluster and MinimapCluster.MinimapContainer
	local coords = box and box.PlayerCoords
	if coords and coords.IsShown and coords:IsShown() then return coords end
end

-- Tracking, mail, the calendar, and the addon compartment sit on the top edge
-- in one row. Their old spots were for the round header.
local headerSaved = {}

local function rememberHeader(f)
	if not f or headerSaved[f] then return end
	local n = f.GetNumPoints and f:GetNumPoints() or 0
	local pts = {}
	for i = 1, n do
		local a, b, c, d, e = f:GetPoint(i)
		if isSecret(a) or isSecret(d) or isSecret(e) then return end
		if a then pts[#pts + 1] = { a, b, c, d, e } end
	end
	local scale = f.GetScale and f:GetScale()
	if isSecret(scale) or type(scale) ~= "number" then scale = nil end
	headerSaved[f] = { pts = pts, scale = scale }
end

local function restoreHeader()
	if InCombatLockdown() then return end
	for f, saved in pairs(headerSaved) do
		if not (f.IsProtected and f:IsProtected()) then
			f:ClearAllPoints()
			for _, p in ipairs(saved.pts) do
				f:SetPoint(p[1], p[2], p[3], p[4], p[5])
			end
			if saved.scale then f:SetScale(saved.scale) end
		end
	end
end

local function addShown(side, f)
	if not f or not f.IsShown or not f:IsShown() then return end
	if f.IsForbidden and f:IsForbidden() then return end
	side[#side + 1] = f
end

local function headerSides()
	local cluster = MinimapCluster
	local right = {}
	if cluster then
		addShown(right, cluster.InstanceDifficulty)
	end
	-- Anything still along the top. The filter, mail, and calendar are placed on their own.
	addShown(right, AddonCompartmentFrame)
	addShown(right, QueueStatusMinimapButton)
	return right
end

local function span(f)
	local w = f:GetWidth()
	if isSecret(w) or type(w) ~= "number" or w < 8 or w > 160 then w = 26 end
	local s = f.GetScale and f:GetScale()
	if isSecret(s) or type(s) ~= "number" or s <= 0 then s = 1 end
	return w * s
end

local function placeHeader(list, fromRight, startX)
	local x = startX or 3
	local level = (Minimap:GetFrameLevel() or 1) + 12
	for _, f in ipairs(list) do
		if not (f.IsProtected and f:IsProtected()) then
			rememberHeader(f)
			f:SetFrameLevel(level)
			f:ClearAllPoints()
			if fromRight then
				f:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", -x, 3)
			else
				f:SetPoint("TOPLEFT", Minimap, "TOPLEFT", x, 3)
			end
			x = x + span(f) + 3
		end
	end
end

-- Filter on the top-left corner, mail centered on the bottom-left corner,
-- calendar on the bottom-right corner, and the day/night sun centered on the
-- top-right corner.
local placingSun = false
local placingHeader = false

local function canMove(f)
	return f and f.IsShown and f:IsShown() and not (f.IsProtected and f:IsProtected()) and not (f.IsForbidden and f:IsForbidden())
end

local function placeAt(f, dx, dy)
	if not canMove(f) then return end
	rememberHeader(f)
	f:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 14)
	f:ClearAllPoints()
	local half = Minimap:GetWidth()
	if isSecret(half) or type(half) ~= "number" or half < 40 then half = 140 end
	half = half / 2
	-- Square: the corner of the box. Circle: the same compass point on the rim.
	local reach = lookKey() == "square" and half or half * 0.70710678
	f:SetPoint("CENTER", Minimap, "CENTER", dx * reach, dy * reach)
end

local function placeTracking()
	placeAt((MinimapCluster and MinimapCluster.Tracking) or MiniMapTracking, -1, 1)
end

local function mailFrame()
	local cluster = MinimapCluster
	local indicator = cluster and cluster.IndicatorFrame
	local candidates = {
		indicator and indicator.MailFrame,
		cluster and cluster.MailFrame,
		MiniMapMailFrame,
	}
	for _, f in ipairs(candidates) do
		if canMove(f) then return f end
	end
end

local function placeMail()
	local mail = mailFrame()
	if not mail then return end
	rememberHeader(mail)
	mail:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 14)
	mail:ClearAllPoints()
	placeAt(mail, -1, -1)
end

-- The day/night sun. Its center is the top-right point of the map.
local function placeDay()
	local sun = MinimapCluster and MinimapCluster.DielFrame
	if not canMove(sun) then return end
	rememberHeader(sun)
	sun:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 14)
	sun:ClearAllPoints()
	placeAt(sun, 1, 1)
end

local function placeSun()
	local sun = GameTimeFrame
	if not canMove(sun) then return end
	rememberHeader(sun)
	sun:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 14)
	placingSun = true
	placeAt(sun, 1, -1)
	placingSun = false
end

local function layoutHeader()
	if InCombatLockdown() then return end
	hideClock()
	placingHeader = true
	placeSun()
	placeDay()
	placeTracking()
	placeMail()
	placeHeader(headerSides(), true, 3)
	placingHeader = false
end

local mover = MinimapCluster or Minimap
local layoutText

-- Where the map is kept: the top-right corner of the map itself (not the
-- cluster around it, which keeps empty room above the map for the game's
-- header), in screen pixels. Nothing saved: the top-right of the screen.
-- (minimapPos, the old cluster spot, left a gap above the map and is dropped.)
local CORNER = 16 -- room for the ring and the icons on its rim

local function edgePx(frame)
	local r, t, s = frame:GetRight(), frame:GetTop(), frame:GetEffectiveScale()
	for _, v in ipairs({ r, t, s }) do
		if isSecret(v) or type(v) ~= "number" then return nil end
	end
	return r * s, t * s
end

local function savePos()
	local r, t = edgePx(Minimap)
	if not r then return end
	db().minimapSpot = { right = r, top = t }
	db().minimapPos = nil
end

local placingMap = false
local function applyPos()
	if InCombatLockdown() or placingMap then return end
	db().minimapPos = nil
	local spot = db().minimapSpot
	local wantR, wantT
	if type(spot) == "table" and type(spot.right) == "number" and type(spot.top) == "number" then
		wantR, wantT = spot.right, spot.top
	else
		local uiR, uiT = edgePx(UIParent)
		if not uiR then return end
		local px = CORNER * UIParent:GetEffectiveScale()
		wantR, wantT = uiR - px, uiT - px
	end
	local mapR, mapT = edgePx(Minimap)
	local boxR, boxT = edgePx(mover)
	if not (mapR and boxR) then return end
	-- Move the cluster by however far the map is from where it should be.
	local s = mover:GetEffectiveScale()
	local x, y = (boxR + wantR - mapR) / s, (boxT + wantT - mapT) / s
	placingMap = true
	mover:ClearAllPoints()
	mover:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", x, y)
	placingMap = false
end

-- The game lays the minimap out again on its own (its layout and edit-mode
-- passes) and puts the cluster back where it was. Whenever anything else
-- moves it, put it back in our spot on the next frame.
do
	local queued = false
	local function again()
		if queued or placingMap or not on() then return end
		queued = true
		C_Timer.After(0, function()
			queued = false
			if on() and not InCombatLockdown() then applyPos() end
		end)
	end
	if hooksecurefunc and mover.SetPoint then hooksecurefunc(mover, "SetPoint", again) end
	if hooksecurefunc and mover.ApplySystemAnchor then hooksecurefunc(mover, "ApplySystemAnchor", again) end
	if hooksecurefunc and type(UIParent_ManageFramePositions) == "function" then
		hooksecurefunc("UIParent_ManageFramePositions", again)
	end
end

-- /zyde minimapdebug: where the map and its cluster are, and what's saved.
function ns.MinimapDebug()
	local P = "|cff66ccffZyde_Forever|r: "
	local function show(v) if isSecret(v) then return "hidden" end return v and string.format("%.0f", v) or "nil" end
	local mR, mT = edgePx(Minimap)
	local cR, cT = edgePx(mover)
	local uR, uT = edgePx(UIParent)
	print(P .. ("minimap look %s, mover %s"):format(on() and "on" or "off", mover:GetName() or "?"))
	print(("  map top-right %s, %s   cluster top-right %s, %s   screen %s, %s (pixels)"):format(
		show(mR), show(mT), show(cR), show(cT), show(uR), show(uT)))
	for i = 1, mover:GetNumPoints() do
		local a, rel, b, x, y = mover:GetPoint(i)
		print(("  cluster point %d: %s to %s %s %s, %s"):format(i, tostring(a),
			rel and rel.GetName and (rel:GetName() or "?") or tostring(rel), tostring(b), show(x), show(y)))
	end
	local spot = db().minimapSpot
	print("  saved spot: " .. (type(spot) == "table" and (show(spot.right) .. ", " .. show(spot.top)) or "none (top-right corner)")
		.. (db().minimapPos and "  (old minimapPos still saved)" or ""))
end


local function startDrag()
	if InCombatLockdown() or not on() then return end
	mover:SetMovable(true)
	mover:StartMoving()
end

local function stopDrag()
	if mover.StopMovingOrSizing then mover:StopMovingOrSizing() end
	savePos()
	layoutText()
end

layoutText = function()
	local w = Minimap:GetWidth()
	if isSecret(w) or type(w) ~= "number" or w < 40 then w = 180 end
	panel:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 20)
	panel:ClearAllPoints()
	-- The zone sits under the coordinate line. Anchoring to the map bottom
	-- draws the name straight through those numbers.
	local coords = playerCoords()
	if coords then
		panel:SetPoint("TOP", coords, "BOTTOM", 0, -3)
	else
		panel:SetPoint("TOP", Minimap, "BOTTOM", 0, -10)
	end
	panel:SetWidth(math.max(w, 240))
end

local function apply()
	if not on() then
		host:Hide()
		panel:Hide()
		revealAll()
		restoreMask()
		fitSquare(false)
		restoreHeader()
		if ns.PlaceMinimapBag then ns.PlaceMinimapBag() end
		return
	end
	if InCombatLockdown() then return end
	local key = lookKey()
	local square = key == "square"
	blizzBits()
	fitSquare(square)
	mask(square and "square" or "circle")
	placeBorder(key)
	applyPos()
	layoutHeader()
	layoutText()
	if ns.PlaceMinimapBag then ns.PlaceMinimapBag() end
	paintZone()
	paintTimes()
	host:Show()
	panel:Show()
end

local elapsed = 0
panel:SetScript("OnUpdate", function(_, dt)
	elapsed = elapsed + dt
	if elapsed < 0.25 then return end
	elapsed = 0
	paintTimes()
	hideClock()
end)

local ev = CreateFrame("Frame")
for _, e in ipairs({
	"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
	"ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_ENABLED", "ADDON_LOADED",
}) do
	pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_LOGIN" or event == "ADDON_LOADED" then
		apply()
		return
	end
	if on() then paintZone() end
end)

if Minimap.HookScript then
	Minimap:HookScript("OnEnter", function()
		if not on() then return end
		conceal(Minimap.ZoomIn)
		conceal(Minimap.ZoomOut)
		conceal(MinimapZoomIn)
		conceal(MinimapZoomOut)
	end)
	Minimap:HookScript("OnSizeChanged", function()
		if not on() or fitting then return end
		placeBorder(lookKey())
		layoutHeader()
		layoutText()
	end)
	Minimap:RegisterForDrag("LeftButton")
	Minimap:HookScript("OnDragStart", startDrag)
	Minimap:HookScript("OnDragStop", stopDrag)
end
panel:SetScript("OnDragStart", startDrag)
panel:SetScript("OnDragStop", stopDrag)

-- The game puts the round mask back whenever it lays the minimap out again.
local function settle()
	if not on() or InCombatLockdown() then return end
	applyPos()
	local key = lookKey()
	mask(key == "square" and "square" or "circle")
	fitSquare(key == "square")
	placeBorder(key)
	layoutHeader()
	layoutText()
	if ns.PlaceMinimapBag then ns.PlaceMinimapBag() end
end

if MinimapCluster and MinimapCluster.UpdateMinimapConfig and hooksecurefunc then
	hooksecurefunc(MinimapCluster, "UpdateMinimapConfig", settle)
end

-- Leatrix lays the header out on its own hooks. Run again after those.
local headerQueued = false
local function queueHeader()
	if headerQueued or not C_Timer or not C_Timer.After then return end
	if not on() then return end
	headerQueued = true
	C_Timer.After(0, function()
		headerQueued = false
		settle()
	end)
end

if hooksecurefunc then
	if MinimapCluster and MinimapCluster.SetHeaderUnderneath then
		hooksecurefunc(MinimapCluster, "SetHeaderUnderneath", queueHeader)
	end
	if MiniMapIndicatorFrame_UpdatePosition then
		hooksecurefunc("MiniMapIndicatorFrame_UpdatePosition", queueHeader)
	end
	-- Leatrix anchors the calendar with the old header. Put it back on the corner.
	if GameTimeFrame and GameTimeFrame.SetPoint then
		hooksecurefunc(GameTimeFrame, "SetPoint", function()
			if placingSun or placingHeader or not on() then return end
			queueHeader()
		end)
	end
	local function hookMove(frame)
		if frame and frame.SetPoint then
			hooksecurefunc(frame, "SetPoint", function()
				if placingHeader or not on() then return end
				queueHeader()
			end)
		end
	end
	hookMove(MinimapCluster and MinimapCluster.Tracking)
	hookMove(MiniMapTracking)
	hookMove(MinimapCluster and MinimapCluster.DielFrame)
	hookMove(MinimapCluster and MinimapCluster.IndicatorFrame and MinimapCluster.IndicatorFrame.MailFrame)
	hookMove(MinimapCluster and MinimapCluster.MailFrame)
	hookMove(MiniMapMailFrame)
	if TimeManagerClockButton and TimeManagerClockButton.SetPoint then
		hooksecurefunc(TimeManagerClockButton, "SetPoint", function()
			if on() then hideClock() end
		end)
	end
end

if C_Timer and C_Timer.After then
	C_Timer.After(1, function()
		if on() then apply() end
	end)
end

ns.OnFeatureChanged(function(key)
	if key == "minimap" then apply() end
end)

ns.MinimapLook = {
	LOOKS = LOOKS,
	Get = lookKey,
	Set = function(key)
		if not BY_KEY[key] then return end
		db().minimapLook = key
		apply()
	end,
}
