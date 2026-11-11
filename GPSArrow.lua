-- Zyde_Forever: our own direction arrow and notes for AzerothGPS routes ("gpsArrow").
-- AzerothGPS works out the route along the roads; this draws it car-GPS style:
--
--      ▲      Turn left in 40 yd
--    509 yd   Collect Echeyakee's Hide
--    1m 12s   Then: straight 300 yd
--
-- AzerothGPS's own two windows (AzerothGPSArrow, AzerothGPSDirections) keep
-- running, faded out, and Zyde reads them: the arrow's turn and color every
-- frame, and its direction lines, which are rewritten here (the stop's name,
-- distance and ETA pulled apart, "Continue straight, then" and "Zygor:" dropped,
-- marker icons removed). AzerothGPS has no published call for this, so if an
-- update changes its windows and they can't be read, its own windows show again.
-- A hearthstone or teleport as the next step: AzerothGPS's window shows (its
-- button is the one you click), and this one steps aside.
--
-- Shift-drag the window to move it (/zyde gpsreset puts it back).

local ADDON, ns = ...

---------------------------------------------------------------------------
-- The look: change these to taste, then /reload.
---------------------------------------------------------------------------
local LOOK = {
	scale = 1,
	-- the arrow
	arrowSize = 52,               -- the arrow as you see it, in pixels
	arrowArtScale = 1.4,          -- the art has empty space round it: drawn this much bigger to fill arrowSize
	arrowAtlas = "ui-hud-minimap-arrow-questtracking-2x",
	arrowFile = "Interface\\Minimap\\MinimapArrow", -- used when the atlas is missing
	arrowShadow = 0.7,            -- the dark shadow under the arrow (0 = none)
	colors = {                    -- by what AzerothGPS says (it colors its own arrow the same way)
		ahead = { 0.3, 1, 0.35 },   -- on course
		turn = { 1, 0.82, 0.1 },    -- a turn
		behind = { 1, 0.25, 0.2 },  -- it's behind you
		-- (a ledge to jump down: orange, and flying: light blue, as AzerothGPS has them)
	},
	pulseWithin = 30,             -- the arrow pulses when a turn is this many yards away or less (0 = never)
	-- the text
	font = nil,                   -- nil: the game's font; or a path like "Fonts\\FRIZQT__.TTF"
	outline = "",                 -- "" (soft shadow), "OUTLINE" or "THICKOUTLINE"
	distSize = 16,                -- "509 yd" under the arrow
	etaSize = 11,                 -- "1m 12s" under that
	moveSize = 14,                -- "Turn left in 40 yd"
	stopSize = 12,                -- the step: "Collect Echeyakee's Hide"
	thenSize = 10,                -- "Then: ..." and quest objectives
	moveColor = { 1, 1, 1 },
	stopColor = { 1, 0.82, 0 },
	distColor = { 1, 1, 1 },
	etaColor = { 1, 0.82, 0 },
	thenColor = { 0.65, 0.65, 0.65 },
	leftWidth = 78,               -- the arrow / distance / ETA column
	textWidth = 230,              -- the notes column (a long step name ends in "...")
	gap = 6,                      -- between the two columns
	showThenWithin = 80,          -- the "Then: ..." line only when the next move is this close in yards (0 = always)
	maxObjectives = 2,            -- in a quest's area: its objective lines shown
	-- the backing plate
	plate = 0,                    -- its darkness, 0 = none (try 0.45 for a soft dark backing)
	plateFade = 28,               -- its soft left and right edges, in pixels
	platePad = 8,
	fadeInCombat = 0.35,          -- opacity in combat (1 = no change)
}

local function on() return ns.F("gpsArrow") end
local function db() ZydeForeverDB = ZydeForeverDB or {} return ZydeForeverDB end
local isSecret = ns.isSecret

---------------------------------------------------------------------------
-- Reading AzerothGPS's windows
---------------------------------------------------------------------------
local src -- { panel, dir, arrow, useIcon, bang, lines = { 4 font strings } }

local function find()
	local panel, dir = rawget(_G, "AzerothGPSArrow"), rawget(_G, "AzerothGPSDirections")
	if not (panel and dir and panel.GetRegions and dir.GetRegions) then return nil end
	-- the arrow's own textures, in the order AzerothGPS makes them: ARTWORK ones are
	-- the arrow, then the hearthstone icon, then the quest "!"
	local art = {}
	for _, r in ipairs({ panel:GetRegions() }) do
		if r.GetObjectType and r:GetObjectType() == "Texture" and r:GetDrawLayer() == "ARTWORK" then art[#art + 1] = r end
	end
	local arrow = art[1]
	if not (arrow and arrow.GetRotation) then return nil end
	local lines = {}
	for _, r in ipairs({ dir:GetRegions() }) do
		if r.GetObjectType and r:GetObjectType() == "FontString" then
			lines[#lines + 1] = r
			if #lines == 4 then break end
		end
	end
	if #lines < 4 then return nil end
	return { panel = panel, dir = dir, arrow = arrow, useIcon = art[2], bang = art[3], lines = lines }
end

local function textOf(fs)
	local t = fs and fs:GetText()
	if type(t) ~= "string" or isSecret(t) then return "" end
	return t
end

-- No icons or color codes, single spaces.
local function clean(s)
	s = s:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	s = s:gsub("%s+", " ")
	return strtrim(s)
end

local function cap(s) return (s:gsub("^%l", string.upper)) end

-- The stop line: "<icon> Zygor: Name  |cffffffff509 yd|r  |cffffd1001m 12s|r  (1/3)".
local function parseStop(raw)
	local dist = raw:match("|cffffffff([^|]+)|r")
	local eta = raw:match("|cffffd100([^|]+)|r")
	if not (dist and eta) then return nil end
	local name = raw:match("^(.-)%s*|cffffffff") or ""
	name = clean(name):gsub("^%d+%.%s*", ""):gsub("^Zygor:%s*", "")
	return { name = name, dist = clean(dist), eta = clean(eta) }
end

-- "Continue straight, then turn left in 40 yd" -> "Turn left in 40 yd"; an arrival -> "".
local function parseMove(raw)
	local m = clean(raw)
	m = m:gsub("^Continue straight, then ", ""):gsub("^Straight, then ", "")
	if m:lower():find("^arrive") then return "" end
	return cap(m)
end

-- Yards to the move ("in 40 yd"), 0 for "... now", nil when unknown.
local function moveYards(move)
	if move:find(" now$") then return 0 end
	local n = move:match(" in ([%d%.,]+)%s*yd$")
	return n and tonumber((n:gsub(",", ""))) or nil
end

---------------------------------------------------------------------------
-- Fading AzerothGPS's windows out (they set their own opacity a few times a
-- second; the hook puts it back to 0 and remembers what they wanted)
---------------------------------------------------------------------------
local wantAlpha = {}
local hiding = false
local busy = false

local function hookFade(f)
	if f.zydeFadeHooked then return end
	f.zydeFadeHooked = true
	wantAlpha[f] = f:GetAlpha()
	hooksecurefunc(f, "SetAlpha", function(self, a)
		if busy then return end
		wantAlpha[self] = a
		if hiding then busy = true; self:SetAlpha(0); busy = false end
	end)
	hooksecurefunc(f, "EnableMouse", function(self, m)
		if busy or not (hiding and m) then return end
		busy = true; pcall(self.EnableMouse, self, false); busy = false
	end)
end

local function setHiding(h)
	if not src or h == hiding then return end
	hiding = h
	busy = true
	for _, f in ipairs({ src.panel, src.dir }) do
		if h then
			f:SetAlpha(0)
			pcall(f.EnableMouse, f, false)
		else
			f:SetAlpha(wantAlpha[f] or 1) -- (its mouse comes back on its next update)
		end
	end
	busy = false
end

---------------------------------------------------------------------------
-- Our window
---------------------------------------------------------------------------
local win, art, shadow, distFS, etaFS, moveFS, stopFS, thenFS
local objFS = {}
local plate = {}

local function fontFile() return LOOK.font or (GameFontNormal and GameFontNormal:GetFont()) or "Fonts\\FRIZQT__.TTF" end

local function makeFS(size, color, justify, width)
	local fs = win:CreateFontString(nil, "OVERLAY")
	fs:SetFont(fontFile(), size, LOOK.outline or "")
	fs:SetShadowOffset(1, -1)
	fs:SetShadowColor(0, 0, 0, 0.9)
	fs:SetTextColor(color[1], color[2], color[3])
	fs:SetJustifyH(justify)
	fs:SetWordWrap(false)
	fs:SetWidth(width)
	return fs
end

local function setArt(tex)
	local ok = LOOK.arrowAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(LOOK.arrowAtlas)
	if ok then tex:SetAtlas(LOOK.arrowAtlas) else tex:SetTexture(LOOK.arrowFile) end
	local s = LOOK.arrowSize * LOOK.arrowArtScale
	tex:SetSize(s, s)
end

local function savePos()
	local p, _, rp, x, y = win:GetPoint(1)
	db().gpsArrowPos = { p, rp, x, y }
end

local function place()
	win:ClearAllPoints()
	local pos = db().gpsArrowPos
	if type(pos) == "table" and pos[1] then
		win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		win:SetPoint("TOP", UIParent, "TOP", 0, -140)
	end
end

-- A soft dark plate: solid in the middle, fading out at the left and right.
local function buildPlate()
	local a, fade, pad = LOOK.plate, LOOK.plateFade, LOOK.platePad
	if a <= 0 then return end
	local mid = win:CreateTexture(nil, "BACKGROUND")
	mid:SetColorTexture(0, 0, 0, a)
	mid:SetPoint("TOPLEFT", win, "TOPLEFT", -pad + fade, pad)
	mid:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", pad - fade, -pad)
	local function edge(left)
		local t = win:CreateTexture(nil, "BACKGROUND")
		t:SetColorTexture(1, 1, 1, 1)
		t:SetWidth(fade)
		t:SetPoint("TOP", mid, "TOP")
		t:SetPoint("BOTTOM", mid, "BOTTOM")
		t:SetPoint(left and "RIGHT" or "LEFT", mid, left and "LEFT" or "RIGHT")
		local clear, solid = CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, a)
		if t.SetGradient and CreateColor then
			if left then t:SetGradient("HORIZONTAL", clear, solid) else t:SetGradient("HORIZONTAL", solid, clear) end
		else
			t:SetColorTexture(0, 0, 0, a / 2)
		end
		return t
	end
	plate = { mid, edge(true), edge(false) }
end

local function build()
	if win then return end
	win = CreateFrame("Frame", "ZydeForeverGPSArrow", UIParent)
	win:SetScale(LOOK.scale)
	win:SetSize(LOOK.leftWidth + LOOK.gap + LOOK.textWidth, LOOK.arrowSize + 40)
	win:SetClampedToScreen(true)
	win:SetMovable(true)
	win:EnableMouse(false) -- (only while Shift is held: see update)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
	win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos() end)
	win:Hide()
	pcall(buildPlate)

	-- the arrow, with its shadow a little down and right
	local cx, cy = LOOK.leftWidth / 2, -LOOK.arrowSize / 2
	if LOOK.arrowShadow > 0 then
		shadow = win:CreateTexture(nil, "BORDER")
		setArt(shadow)
		shadow:SetPoint("CENTER", win, "TOPLEFT", cx + 2, cy - 2)
		shadow:SetVertexColor(0, 0, 0, LOOK.arrowShadow)
	end
	art = win:CreateTexture(nil, "ARTWORK")
	setArt(art)
	art:SetPoint("CENTER", win, "TOPLEFT", cx, cy)

	distFS = makeFS(LOOK.distSize, LOOK.distColor, "CENTER", LOOK.leftWidth)
	distFS:SetPoint("TOP", win, "TOPLEFT", cx, -LOOK.arrowSize - 1)
	etaFS = makeFS(LOOK.etaSize, LOOK.etaColor, "CENTER", LOOK.leftWidth)
	etaFS:SetPoint("TOP", distFS, "BOTTOM", 0, -1)

	moveFS = makeFS(LOOK.moveSize, LOOK.moveColor, "LEFT", LOOK.textWidth)
	stopFS = makeFS(LOOK.stopSize, LOOK.stopColor, "LEFT", LOOK.textWidth)
	thenFS = makeFS(LOOK.thenSize, LOOK.thenColor, "LEFT", LOOK.textWidth)
	for i = 1, LOOK.maxObjectives do objFS[i] = makeFS(LOOK.thenSize, LOOK.thenColor, "LEFT", LOOK.textWidth) end
	place()
end

-- The left column's height, then the notes stacked and centered beside it.
local function layout()
	local leftH = LOOK.arrowSize + 2 + (distFS:IsShown() and distFS:GetStringHeight() or 0)
		+ (etaFS:IsShown() and etaFS:GetStringHeight() + 1 or 0)
	local list = { moveFS, stopFS }
	for _, fs in ipairs(objFS) do list[#list + 1] = fs end
	list[#list + 1] = thenFS
	local shown, h = {}, 0
	for _, fs in ipairs(list) do
		if fs:IsShown() then shown[#shown + 1] = fs; h = h + fs:GetStringHeight() + 3 end
	end
	local total = math.max(leftH, h)
	win:SetHeight(total)
	local y = -(total - h) / 2
	for _, fs in ipairs(shown) do
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", win, "TOPLEFT", LOOK.leftWidth + LOOK.gap, y)
		y = y - fs:GetStringHeight() - 3
	end
end

local function setLine(fs, text)
	if not text or text == "" then fs:Hide() else fs:SetText(text); fs:Show() end
end

local moveYd -- yards to the next move (for the pulse), or nil
local lastText = ""
local function copyText()
	local stop, thenLine, others = nil, nil, {}
	for _, fs in ipairs(src.lines) do
		local raw = textOf(fs)
		if raw ~= "" then
			local s = not stop and parseStop(raw)
			if s then stop = s
			elseif raw:find("^Then: ") or raw:find("^|c%x+Then: ") then thenLine = clean(raw)
			else others[#others + 1] = raw end
		end
	end
	-- the move: the first line, or in a quest's area the last (its objectives come first)
	local inQuestArea = src.bang and src.bang:IsShown()
	local moveRaw = inQuestArea and table.remove(others) or table.remove(others, 1)
	local move = moveRaw and parseMove(moveRaw) or ""
	if move:find("^Toward ") then move = "" end -- (the "toward Razor Hill" line alone)
	moveYd = moveYards(move)
	local objectives = {}
	if inQuestArea then
		for i = 1, math.min(#others, LOOK.maxObjectives) do objectives[i] = clean(others[i]) end
	end
	if thenLine and LOOK.showThenWithin > 0 and not (moveYd and moveYd <= LOOK.showThenWithin) then thenLine = nil end
	if move == "" then thenLine = nil end

	local key = table.concat({ move, stop and stop.name or "", stop and stop.dist or "", stop and stop.eta or "",
		thenLine or "", table.concat(objectives, "\1") }, "\2")
	if key == lastText then return end
	lastText = key
	setLine(moveFS, move)
	setLine(stopFS, stop and stop.name)
	setLine(distFS, stop and stop.dist)
	setLine(etaFS, stop and stop.eta ~= "--" and stop.eta or nil)
	for i, fs in ipairs(objFS) do setLine(fs, objectives[i]) end
	setLine(thenFS, thenLine)
	layout()
end

-- AzerothGPS's arrow colors -> ours.
local function arrowColor(r, g, b)
	local C = LOOK.colors
	if r > 0.9 and g > 0.9 and b > 0.9 then return C.turn end
	if g > 0.9 and r < 0.6 then return C.ahead end
	if r > 0.9 and g < 0.5 and b > 0.25 then return C.behind end
	return { r, g, b } -- (jump down, flying, no route: as AzerothGPS has it)
end

---------------------------------------------------------------------------
-- Short Zygor hops: Zygor's own straight arrow is enough. A route to a Zygor
-- stop (ZygorRoute.lua) uses the GPS arrow only when AzerothGPS's ETA is at
-- least gpsMinSeconds (40 by default; /zyde gpsmin), and drops back to Zygor's
-- under SLACK seconds less, so it doesn't flip at the line.
---------------------------------------------------------------------------
local SLACK = 5
local function minSeconds()
	local v = tonumber(db().gpsMinSeconds)
	return v and v >= 0 and v or 40
end

-- "2m 39s", "45s", "1h 02m 03s" -> seconds; nil for "--" or anything else.
local function seconds(t)
	if type(t) ~= "string" then return nil end
	local h, m, s = t:match("^(%d+)h (%d+)m (%d+)s$")
	if h then return h * 3600 + m * 60 + s end
	m, s = t:match("^(%d+)m (%d+)s$")
	if m then return m * 60 + s end
	s = t:match("^(%d+)s$")
	return s and tonumber(s) or nil
end

-- The Zygor stop's ETA from AzerothGPS's lines: isZygor, seconds (nil when unknown).
local function zygorEta()
	for _, fs in ipairs(src.lines) do
		local t = textOf(fs)
		if t:find("Zygor: ", 1, true) then
			return true, seconds(t:match("|cffffd100([^|]+)|r"))
		end
	end
	return false, nil
end

local useGPS = true
local function decide(active)
	if not (active and ns.F("zygorRoute")) then useGPS = true return end
	local zyg, eta = zygorEta()
	if not zyg then useGPS = true return end -- a trip you planned yourself
	if not eta then return end -- (keep what it was)
	local min = minSeconds()
	if useGPS and eta < min - SLACK then useGPS = false
	elseif not useGPS and eta >= min then useGPS = true end
end

-- ZygorRoute.lua asks: is Zygor's own arrow the one to show right now?
ns.GPSShortHop = function() return not useGPS end

---------------------------------------------------------------------------
-- Each frame
---------------------------------------------------------------------------
local textWait = 0
local warned = false

local function routeActive()
	if not (src.panel:IsShown() and (wantAlpha[src.panel] or 0) > 0) then return false end
	return not textOf(src.lines[1]):find("No route", 1, true)
end

local function update(_, dt)
	if not (on() or ns.F("zygorRoute")) then useGPS = true; setHiding(false); win:Hide(); return end
	if not src then
		src = find()
		if not src then
			if not warned and rawget(_G, "AzerothGPSArrow") then
				warned = true
				print("|cff66ccffZyde_Forever|r: can't read AzerothGPS's arrow (an update changed it?) - its own arrow stays")
			end
			return
		end
		hookFade(src.panel)
		hookFade(src.dir)
	end

	-- hearthstone / teleport next: AzerothGPS's own window, with its button
	local using = src.useIcon and src.useIcon:IsShown()
	local active = routeActive()
	decide(active)
	-- AzerothGPS's windows: out of the way for our arrow, or for Zygor's on a short hop
	setHiding(active and not using and (on() or not useGPS))
	if not active or using or not on() or not useGPS then
		if win:IsShown() then win:Hide() end
		return
	end
	if not win:IsShown() then lastText = ""; textWait = 0; win:Show() end

	textWait = textWait - (dt or 0)
	if textWait <= 0 then
		textWait = 0.2
		copyText()
	end

	-- the arrow: every frame, as AzerothGPS turns it
	if src.arrow:IsShown() then
		art:Show()
		local rot = src.arrow:GetRotation()
		if type(rot) == "number" and not isSecret(rot) then
			art:SetRotation(rot)
			if shadow then shadow:SetRotation(rot) end
		end
		local r, g, b = src.arrow:GetVertexColor()
		if r and not isSecret(r) then
			local c = arrowColor(r, g, b)
			art:SetVertexColor(c[1], c[2], c[3])
		end
		-- a turn coming up: a gentle pulse
		local pulse = LOOK.pulseWithin > 0 and moveYd and moveYd <= LOOK.pulseWithin
		art:SetAlpha(pulse and (0.7 + 0.3 * math.sin(GetTime() * 7)) or 1)
		if shadow then shadow:Show() end
	else
		art:Hide()
		if shadow then shadow:Hide() end
	end
	win:SetAlpha(InCombatLockdown() and LOOK.fadeInCombat or 1)
	-- clicks pass through it, except with Shift held (Shift-drag moves it)
	local grab = IsShiftKeyDown() and not InCombatLockdown()
	if grab ~= win:IsMouseEnabled() then win:EnableMouse(grab) end
end

local driver = CreateFrame("Frame")
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
	if not ns.addonOn("AzerothGPS") then return end
	build()
	driver:SetScript("OnUpdate", function(self, dt)
		local ok, err = pcall(update, self, dt)
		if not ok then
			driver:SetScript("OnUpdate", nil)
			pcall(setHiding, false)
			if win then win:Hide() end
			print("|cff66ccffZyde_Forever|r: GPS arrow stopped (" .. tostring(err) .. ") - AzerothGPS's own arrow is back")
		end
	end)
end)

ns.OnFeatureChanged(function(key)
	if key == "gpsArrow" and not on() then
		pcall(setHiding, false)
		if win then win:Hide() end
	end
end)

ns.GPSArrow = {
	-- /zyde gpsmin <seconds>: the shortest trip that gets the GPS arrow (0 = always).
	SetMinSeconds = function(v)
		v = tonumber(v)
		if not v or v < 0 then
			print(("|cff66ccffZyde_Forever|r: Zygor's arrow for trips under %ds, the GPS arrow past that. /zyde gpsmin <seconds> (0 = always GPS)"):format(minSeconds()))
			return
		end
		db().gpsMinSeconds = math.floor(v)
		print(("|cff66ccffZyde_Forever|r: the GPS arrow now takes over for trips of %ds or more"):format(minSeconds()))
	end,
	ResetPosition = function()
		db().gpsArrowPos = nil
		if win then place() end
	end,
}
