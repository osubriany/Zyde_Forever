-- Zyde_Forever: our own direction arrow and notes for AzerothGPS routes ("gpsArrow").
-- AzerothGPS works out the route along the roads; this draws its arrow and
-- directions Zyde's way. AzerothGPS's own two windows (AzerothGPSArrow,
-- AzerothGPSDirections) keep running, faded out, and Zyde copies from them:
--   * the arrow's turn (its rotation) and color, every frame
--   * the text lines: what to do now, the stop with distance and ETA, "Then: ..."
-- AzerothGPS has no published call for this, so if an update changes its
-- windows and they can't be read, its own windows simply show again.
-- A hearthstone or teleport as the next step: AzerothGPS's window shows (its
-- button is the one you click), and this one steps aside.
--
-- Shift-drag the window to move it (/zyde gpsreset puts it back).

local ADDON, ns = ...

---------------------------------------------------------------------------
-- The look: change these to taste, then /reload.
---------------------------------------------------------------------------
local LOOK = {
	arrowSize = 44,               -- the arrow, in pixels
	arrowAtlas = "ui-hud-minimap-arrow-questtracking-2x",
	arrowFile = "Interface\\Minimap\\MinimapArrow", -- used when the atlas is missing
	copyArrowColor = true,        -- green ahead, white for a turn, red behind (AzerothGPS's colors)
	arrowColor = { 1, 0.82, 0 },  -- used when copyArrowColor is false
	textWidth = 240,              -- the notes column
	gap = 6,                      -- between the arrow and the notes
	font = nil,                   -- nil: the game's font; or a path like "Fonts\\FRIZQT__.TTF"
	nowSize = 13,                 -- "Continue straight, then join the road in 9 yd"
	stopSize = 11,                -- the stop, its distance and ETA
	thenSize = 10,                -- "Then: slight right in 92 yd"
	outline = "OUTLINE",          -- "", "OUTLINE" or "THICKOUTLINE"
	showToward = false,           -- the "toward Razor Hill" line
	showThen = true,              -- the "Then: ..." line
	dropZygorPrefix = true,       -- "Zygor: Turn in ..." -> "Turn in ..."
	background = 0,               -- 0 = none, up to 1 = solid black behind it all
	fadeInCombat = 0.35,          -- opacity in combat (1 = no change)
	scale = 1,
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
local win, arrowTex, nowFS, towardFS, stopFS, thenFS, bg

local function fontFile() return LOOK.font or (GameFontNormal and GameFontNormal:GetFont()) or "Fonts\\FRIZQT__.TTF" end

local function makeFS(size, r, g, b)
	local fs = win:CreateFontString(nil, "OVERLAY")
	fs:SetFont(fontFile(), size, LOOK.outline or "")
	fs:SetTextColor(r, g, b)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(false)
	fs:SetWidth(LOOK.textWidth)
	return fs
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

local function build()
	if win then return end
	win = CreateFrame("Frame", "ZydeForeverGPSArrow", UIParent)
	win:SetScale(LOOK.scale)
	win:SetSize(LOOK.arrowSize + LOOK.gap + LOOK.textWidth, LOOK.arrowSize)
	win:SetClampedToScreen(true)
	win:SetMovable(true)
	win:EnableMouse(false) -- (only while Shift is held: see update)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
	win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos() end)
	win:Hide()

	bg = win:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("TOPLEFT", -6, 6)
	bg:SetPoint("BOTTOMRIGHT", 6, -6)
	bg:SetColorTexture(0, 0, 0, LOOK.background)

	arrowTex = win:CreateTexture(nil, "ARTWORK")
	arrowTex:SetSize(LOOK.arrowSize, LOOK.arrowSize)
	arrowTex:SetPoint("LEFT")
	local okAtlas = LOOK.arrowAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(LOOK.arrowAtlas)
	if okAtlas then arrowTex:SetAtlas(LOOK.arrowAtlas) else arrowTex:SetTexture(LOOK.arrowFile) end
	if not LOOK.copyArrowColor then arrowTex:SetVertexColor(unpack(LOOK.arrowColor)) end

	nowFS = makeFS(LOOK.nowSize, 1, 0.82, 0)
	towardFS = makeFS(LOOK.thenSize, 0.8, 0.8, 0.8)
	stopFS = makeFS(LOOK.stopSize, 1, 1, 1)
	thenFS = makeFS(LOOK.thenSize, 0.62, 0.62, 0.62)
	place()
end

-- Stack the lines that have text beside the arrow, centered on it.
local function layout(list)
	local shown, h = {}, 0
	for _, fs in ipairs(list) do
		if fs:IsShown() then shown[#shown + 1] = fs; h = h + fs:GetStringHeight() + 2 end
	end
	local y = h / 2
	for _, fs in ipairs(shown) do
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", win, "LEFT", LOOK.arrowSize + LOOK.gap, y)
		y = y - fs:GetStringHeight() - 2
	end
	win:SetHeight(math.max(LOOK.arrowSize, h))
end

local function textOf(fs)
	local t = fs and fs:GetText()
	if type(t) ~= "string" or isSecret(t) then return "" end
	return t
end

local function setLine(fs, text)
	if text == "" then fs:Hide() else fs:SetText(text); fs:Show() end
end

local lastText = ""
local function copyText()
	local L = src.lines
	local now, toward, stop, nxt = textOf(L[1]), textOf(L[2]), textOf(L[3]), textOf(L[4])
	if LOOK.dropZygorPrefix then stop = stop:gsub("Zygor: ", "", 1) end
	local inQuestArea = src.bang and src.bang:IsShown()
	if not (LOOK.showToward or inQuestArea) then toward = "" end
	if not LOOK.showThen and not inQuestArea then nxt = "" end
	local key = now .. "\1" .. toward .. "\1" .. stop .. "\1" .. nxt
	if key == lastText then return end
	lastText = key
	setLine(nowFS, now)
	setLine(towardFS, toward)
	setLine(stopFS, stop)
	setLine(thenFS, nxt)
	layout({ nowFS, towardFS, stopFS, thenFS })
end

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
	if not on() then setHiding(false); win:Hide(); return end
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
	setHiding(active and not using)
	if not active or using then
		if win:IsShown() then win:Hide() end
		return
	end
	if not win:IsShown() then lastText = ""; win:Show() end

	-- the arrow: every frame, as AzerothGPS turns it
	if src.arrow:IsShown() then
		arrowTex:Show()
		local rot = src.arrow:GetRotation()
		if type(rot) == "number" and not isSecret(rot) then arrowTex:SetRotation(rot) end
		if LOOK.copyArrowColor then
			local r, g, b = src.arrow:GetVertexColor()
			if r and not isSecret(r) then arrowTex:SetVertexColor(r, g, b) end
		end
	else
		arrowTex:Hide()
	end
	win:SetAlpha(InCombatLockdown() and LOOK.fadeInCombat or 1)
	-- clicks pass through it, except with Shift held (Shift-drag moves it)
	local grab = IsShiftKeyDown() and not InCombatLockdown()
	if grab ~= win:IsMouseEnabled() then win:EnableMouse(grab) end

	textWait = textWait - (dt or 0)
	if textWait <= 0 then
		textWait = 0.2
		copyText()
	end
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
	ResetPosition = function()
		db().gpsArrowPos = nil
		if win then place() end
	end,
}
