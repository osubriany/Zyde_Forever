-- Zyde_Forever: marker wheels (like the ping wheel).
--   Target markers: hold the key, click skull / cross / moon... to put it on
--     your target. With no target, pressing the key targets what's under
--     your mouse first.
--   World markers: press the key to show a small grid of squares, click one,
--     then click the ground. Press the key again to put the grid away. Drag
--     its title bar to move it. The last square clears every world marker.
-- Letting go of the target-marker key (or clicking nothing) just closes that wheel.
-- Set the keys in Options > Keybindings > AddOns > Zyde Forever.
--
-- Marking is protected on Forever, so each wheel is a secure frame and each
-- marker a secure button running /tm or /wm. (Letting go of the key can't run
-- a secure action on Forever - only key presses and clicks can - so you click.)

local ADDON, ns = ...

local RADIUS = 92      -- icon ring
local DISC = 132       -- background disc radius
local ICON = 40
local HIT = 66         -- the area around each icon that counts as "on it"
local CENTER = 26      -- the middle button
local TIMEOUT = 15     -- close by itself (out of combat) if the key-up never arrives
local P = "|cff66ccffZyde_Forever|r: "
local RAID_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"

local function on() return ns.F("markerWheel") end

local debugOn = false
-- Called by each marker's own macro line: shows (in /zyde wheeldebug) that it ran.
function ZydeForever_WheelRan(what)
	if debugOn then print(P .. ("wheel ran: %s at %.2f"):format(tostring(what), GetTime())) end
end

local function circleMask(frame, region, inset)
	local m = frame:CreateMaskTexture()
	m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	m:SetPoint("TOPLEFT", region or frame, "TOPLEFT", -inset, inset)
	m:SetPoint("BOTTOMRIGHT", region or frame, "BOTTOMRIGHT", inset, -inset)
	return m
end

---------------------------------------------------------------------------
-- Building a wheel
--   cfg.name     frame name prefix
--   cfg.bind     keybinding label
--   cfg.items    { {macro=, icon=, name=, color={r,g,b}, index=}, ... } clockwise from the top
--   cfg.center   optional { macro=, icon=, name= }: a clickable middle button
--   cfg.target   true: target what's under the mouse when opened without a target
--   cfg.hint     text under the wheel when nothing is hovered
--   cfg.checked  optional function() -> index of the item to tick
---------------------------------------------------------------------------
local function makeWheel(cfg)
	local wheel = CreateFrame("Frame", cfg.name .. "Wheel", UIParent, "SecureHandlerBaseTemplate")
	wheel:SetSize(DISC * 2, DISC * 2)
	wheel:SetPoint("CENTER")
	wheel:SetFrameStrata("FULLSCREEN_DIALOG")
	wheel:Hide()

	local edge = wheel:CreateTexture(nil, "BACKGROUND", nil, -1)
	edge:SetPoint("TOPLEFT", -2, 2)
	edge:SetPoint("BOTTOMRIGHT", 2, -2)
	edge:SetColorTexture(0, 0, 0, 0.45)
	edge:AddMaskTexture(circleMask(wheel, nil, 2))

	local disc = wheel:CreateTexture(nil, "BACKGROUND")
	disc:SetAllPoints()
	disc:SetColorTexture(0.04, 0.04, 0.05, 0.20)
	disc:AddMaskTexture(circleMask(wheel, nil, 0))

	local label = wheel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	label:SetPoint("TOP", wheel, "BOTTOM", 0, -6)

	-- A secure button that runs a macro and closes the wheel after the click
	-- (on the mouse-up, after the action went through - also in combat).
	local function actionButton(size, macro, tag)
		local b = CreateFrame("Button", nil, wheel, "SecureActionButtonTemplate")
		b:SetSize(size, size)
		b:RegisterForClicks("AnyDown", "AnyUp") -- the game acts on just one of them
		b:SetAttribute("type", "macro")
		b:SetAttribute("macrotext", macro .. "\n/run ZydeForever_WheelRan(\"" .. tag .. "\")")
		SecureHandlerWrapScript(b, "OnClick", wheel, [[ return nil, down ]], [[
			if not message then self:GetParent():Hide() end
		]])
		return b
	end

	-- Middle: a clickable button (world markers: clear all) or a plain X.
	local mid
	if cfg.center then
		mid = actionButton(CENTER * 2, cfg.center.macro, cfg.center.name)
		mid:SetPoint("CENTER")
	else
		mid = CreateFrame("Frame", nil, wheel)
		mid:SetSize(CENTER * 2, CENTER * 2)
		mid:SetPoint("CENTER")
	end
	mid.bg = mid:CreateTexture(nil, "ARTWORK")
	mid.bg:SetAllPoints()
	mid.bg:SetColorTexture(0.2, 0.2, 0.22, 0.9)
	mid.bg:AddMaskTexture(circleMask(mid, nil, 0))
	mid.icon = mid:CreateTexture(nil, "OVERLAY")
	mid.icon:SetSize(24, 24)
	mid.icon:SetPoint("CENTER")
	mid.icon:SetTexture(cfg.center and cfg.center.icon or "Interface\\Buttons\\UI-GroupLoot-Pass-Up")

	-- The 8 markers, clockwise from the top.
	local slots = {}
	for i, it in ipairs(cfg.items) do
		local angle = math.rad(90 - (i - 1) * 45)
		local s = actionButton(HIT, it.macro, it.name)
		s:SetPoint("CENTER", wheel, "CENTER", math.cos(angle) * RADIUS, math.sin(angle) * RADIUS)
		s.glow = s:CreateTexture(nil, "BACKGROUND")
		s.glow:SetPoint("CENTER")
		s.glow:SetSize(ICON * 1.9, ICON * 1.9)
		s.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
		s.glow:SetBlendMode("ADD")
		s.glow:SetVertexColor(it.color[1], it.color[2], it.color[3], 1)
		s.glow:Hide()
		s.icon = s:CreateTexture(nil, "ARTWORK")
		s.icon:SetPoint("CENTER")
		s.icon:SetSize(ICON, ICON)
		s.icon:SetTexture(it.icon)
		s.check = s:CreateTexture(nil, "OVERLAY")
		s.check:SetSize(16, 16)
		s.check:SetPoint("BOTTOMRIGHT", s.icon, "BOTTOMRIGHT", 4, -4)
		s.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
		s.check:Hide()
		s.item = it
		slots[i] = s
	end

	-- The key: pressing opens the wheel at the mouse; letting go closes it.
	_G["BINDING_NAME_CLICK " .. cfg.name .. "Key:LeftButton"] = cfg.bind
	local key = CreateFrame("Button", cfg.name .. "Key", UIParent, "SecureActionButtonTemplate, SecureHandlerBaseTemplate")
	key:SetSize(1, 1)
	key:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
	key:SetAlpha(0)
	key:RegisterForClicks("AnyDown", "AnyUp")
	key:SetFrameRef("wheel", wheel)
	key:SetAttribute("on", true)
	key:SetAttribute("targetFirst", cfg.target and true or false)
	SecureHandlerWrapScript(key, "OnClick", wheel, [[
		self:SetAttribute("type", nil)
		local wheel = self:GetFrameRef("wheel")
		if not down then wheel:Hide() return end
		if not self:GetAttribute("on") then return end
		if self:GetAttribute("targetFirst") and not UnitExists("target") and UnitExists("mouseover") then
			self:SetAttribute("type", "target")
			self:SetAttribute("unit", "mouseover")
		end
		wheel:Show()
		wheel:ClearAllPoints()
		wheel:SetPoint("CENTER", "$cursor")
	]])

	-- Highlight and name (normal addon code).
	local openedAt, choice = 0, nil
	wheel:HookScript("OnShow", function()
		openedAt, choice = GetTime(), -1 -- -1: force the first highlight update
		local ticked = cfg.checked and cfg.checked()
		for _, s in ipairs(slots) do s.check:SetShown(ticked ~= nil and ticked == s.item.index) end
		-- Out of combat, also place it at the mouse ourselves (in case the
		-- game's secure "at the cursor" placement isn't available).
		if not InCombatLockdown() then
			local x, y = GetCursorPosition()
			local sc = UIParent:GetEffectiveScale()
			wheel:ClearAllPoints()
			wheel:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / sc, y / sc)
		end
	end)

	wheel:HookScript("OnUpdate", function(self)
		if GetTime() - openedAt > TIMEOUT and not InCombatLockdown() then self:Hide() return end
		local i
		for j, s in ipairs(slots) do
			if s:IsMouseOver() then i = j break end
		end
		local onMid = not i and cfg.center and mid:IsMouseOver()
		local now = i or (onMid and 0) or nil
		if now == choice then return end
		choice = now
		for j, s in ipairs(slots) do
			local hot = j == i
			s.glow:SetShown(hot)
			local size = hot and ICON * 1.25 or ICON
			s.icon:SetSize(size, size)
			s.icon:SetAlpha((i == nil or hot) and 1 or 0.55)
		end
		mid.bg:SetColorTexture(onMid and 0.45 or 0.2, 0.2, 0.22, 0.9)
		if i then
			local it = slots[i].item
			label:SetText(it.name)
			label:SetTextColor(it.color[1], it.color[2], it.color[3])
		elseif onMid then
			label:SetText(cfg.center.name)
			label:SetTextColor(1, 0.82, 0)
		else
			label:SetText(cfg.hint)
			label:SetTextColor(0.8, 0.8, 0.8)
		end
	end)

	key:HookScript("OnClick", function(_, _, down)
		if debugOn then print(P .. cfg.bind .. (down and ": pressed" or ": released")) end
		if down and on() and cfg.target and not UnitExists("target") and not UnitExists("mouseover") then
			UIErrorsFrame:AddMessage("Target something (or point at it) to mark it", 1, 0.3, 0.2)
		end
	end)

	return key
end

---------------------------------------------------------------------------
-- A small grid that stays where you put it. Press the key to show it, press
-- again to hide it. Each square is its own click (world markers still need a
-- second click on the ground; that part is the game).
---------------------------------------------------------------------------
local CELL, GAP, PAD, HEADER = 52, 5, 6, 22

local function makePalette(cfg)
	local n = #cfg.items + (cfg.center and 1 or 0)
	local cols = 3
	local rows = math.ceil(n / cols)
	local panel = CreateFrame("Frame", cfg.name .. "Palette", UIParent)
	panel:SetSize(PAD * 2 + cols * CELL + (cols - 1) * GAP, PAD + HEADER + 4 + rows * CELL + (rows - 1) * GAP + PAD)
	panel:SetFrameStrata("HIGH")
	panel:SetClampedToScreen(true)
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:Hide()

	panel.bg = panel:CreateTexture(nil, "BACKGROUND")
	panel.bg:SetAllPoints()
	panel.bg:SetColorTexture(0.07, 0.07, 0.07, 0.94)
	panel.edges = ns.newEdges(panel, "OVERLAY", 1)
	ns.placeEdges(panel.edges, panel, -1, 1)
	for _, t in ipairs(panel.edges) do t:SetColorTexture(0, 0, 0, 0.95) end

	local header = CreateFrame("Frame", nil, panel)
	header:SetPoint("TOPLEFT", 1, -1)
	header:SetPoint("TOPRIGHT", -1, -1)
	header:SetHeight(HEADER)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header.bg = header:CreateTexture(nil, "BACKGROUND")
	header.bg:SetAllPoints()
	header.bg:SetColorTexture(0.14, 0.14, 0.16, 1)
	header.title = header:CreateFontString(nil, "OVERLAY")
	if not header.title:SetFont("Fonts\\ARIALN.TTF", 13, "OUTLINE") then header.title:SetFontObject("GameFontNormal") end
	header.title:SetPoint("CENTER")
	header.title:SetText(cfg.title or "Markers")
	header.title:SetTextColor(1, 0.84, 0.35)
	header:SetScript("OnDragStart", function()
		if InCombatLockdown() then return end
		panel:StartMoving()
	end)
	header:SetScript("OnDragStop", function()
		panel:StopMovingOrSizing()
		local point, _, _, x, y = panel:GetPoint()
		ZydeForeverDB = ZydeForeverDB or {}
		ZydeForeverDB.worldMarkerPos = { point = point, x = x, y = y }
	end)

	local function square(it, index)
		local col = (index - 1) % cols
		local row = math.floor((index - 1) / cols)
		local b = CreateFrame("Button", nil, panel, "SecureActionButtonTemplate")
		b:SetSize(CELL, CELL)
		b:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + col * (CELL + GAP), -(PAD + HEADER + 4 + row * (CELL + GAP)))
		b:RegisterForClicks("AnyUp")
		b:SetAttribute("type", "macro")
		b:SetAttribute("macrotext", it.macro .. "\n/run ZydeForever_WheelRan(\"" .. it.name .. "\")")
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints()
		b.bg:SetColorTexture(0.12, 0.12, 0.13, 1)
		b.edges = ns.newEdges(b, "OVERLAY", 2)
		ns.placeEdges(b.edges, b, 0, 2)
		for _, t in ipairs(b.edges) do t:SetColorTexture(it.color[1], it.color[2], it.color[3], 1) end
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetPoint("CENTER")
		b.icon:SetSize(CELL - 16, CELL - 16)
		b.icon:SetTexture(it.icon)
		b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		b:SetScript("OnEnter", function(self)
			self.bg:SetColorTexture(0.24, 0.24, 0.26, 1)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(it.name, it.color[1], it.color[2], it.color[3])
			if it.hint then GameTooltip:AddLine(it.hint, 0.85, 0.85, 0.85, true) end
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function(self)
			self.bg:SetColorTexture(0.12, 0.12, 0.13, 1)
			GameTooltip:Hide()
		end)
		return b
	end

	for i, it in ipairs(cfg.items) do square(it, i) end
	if cfg.center then square(cfg.center, #cfg.items + 1) end

	_G["BINDING_NAME_CLICK " .. cfg.name .. "Key:LeftButton"] = cfg.bind
	local key = CreateFrame("Button", cfg.name .. "Key", UIParent, "SecureActionButtonTemplate, SecureHandlerBaseTemplate")
	key:SetSize(1, 1)
	key:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
	key:SetAlpha(0)
	key:RegisterForClicks("AnyDown", "AnyUp")
	key:SetFrameRef("panel", panel)
	key:SetAttribute("on", true)
	SecureHandlerWrapScript(key, "OnClick", key, [[
		if not down then return end
		if not self:GetAttribute("on") then return end
		local panel = self:GetFrameRef("panel")
		if panel:IsShown() then panel:Hide() else panel:Show() end
	]])
	key:HookScript("OnClick", function(_, _, down)
		if debugOn and down then print(P .. cfg.bind .. ": toggled") end
	end)
	return key, panel
end

---------------------------------------------------------------------------
-- Target markers
---------------------------------------------------------------------------
local TARGET_ITEMS = {}
for _, m in ipairs({
	{ 8, "Skull", { 1, 1, 1 } }, { 7, "Cross", { 1, 0.2, 0.2 } }, { 6, "Square", { 0.2, 0.55, 1 } },
	{ 5, "Moon", { 0.75, 0.85, 1 } }, { 4, "Triangle", { 0.2, 1, 0.2 } }, { 3, "Diamond", { 0.8, 0.2, 1 } },
	{ 2, "Circle", { 1, 0.5, 0 } }, { 1, "Star", { 1, 0.92, 0 } },
}) do
	TARGET_ITEMS[#TARGET_ITEMS + 1] = { index = m[1], name = m[2], color = m[3], icon = RAID_ICON .. m[1], macro = "/tm " .. m[1] }
end

local function targetMarker()
	for _, u in ipairs({ "target", "mouseover" }) do
		local idx = UnitExists(u) and GetRaidTargetIndex(u)
		if idx and not ns.isSecret(idx) then return idx end
	end
end

---------------------------------------------------------------------------
-- World markers (/wm 1-8 in the game's order: blue square, green triangle,
-- purple diamond, red cross, yellow star, orange circle, silver moon, white skull)
---------------------------------------------------------------------------
local WORLD_ITEMS = {}
for _, m in ipairs({
	{ 8, 8, "White Skull", { 1, 1, 1 } }, { 4, 7, "Red Cross", { 1, 0.2, 0.2 } },
	{ 1, 6, "Blue Square", { 0.2, 0.55, 1 } }, { 7, 5, "Silver Moon", { 0.75, 0.85, 1 } },
	{ 2, 4, "Green Triangle", { 0.2, 1, 0.2 } }, { 3, 3, "Purple Diamond", { 0.8, 0.2, 1 } },
	{ 6, 2, "Orange Circle", { 1, 0.5, 0 } }, { 5, 1, "Yellow Star", { 1, 0.92, 0 } },
}) do
	-- m = { world marker number, matching raid icon, name, color }
	WORLD_ITEMS[#WORLD_ITEMS + 1] = { index = m[1], name = m[3], color = m[4], icon = RAID_ICON .. m[2], macro = "/wm " .. m[1] }
end

local worldKey, worldPanel
local keys
keys = {
	makeWheel({ name = "ZydeForeverMarker", bind = "Marker wheel (hold)", items = TARGET_ITEMS,
		target = true, hint = "Click a marker", checked = targetMarker }),
}
worldKey, worldPanel = makePalette({
	name = "ZydeForeverWorldMarker", bind = "World markers", title = "Markers",
	items = WORLD_ITEMS,
	center = {
		macro = "/cwm all", name = "Clear all", color = { 1, 0.35, 0.3 },
		icon = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
		hint = "Removes every world marker",
	},
})
for _, it in ipairs(WORLD_ITEMS) do it.hint = "Then click the ground" end
keys[#keys + 1] = worldKey

local function placeWorld()
	if not worldPanel or InCombatLockdown() then return end
	worldPanel:ClearAllPoints()
	local p = ZydeForeverDB and ZydeForeverDB.worldMarkerPos
	if type(p) == "table" and p.point then
		worldPanel:SetPoint(p.point, UIParent, p.point, p.x or 0, p.y or 0)
	else
		worldPanel:SetPoint("RIGHT", UIParent, "RIGHT", -24, 0)
	end
end

local function syncOn()
	if InCombatLockdown() then return end
	for _, k in ipairs(keys) do k:SetAttribute("on", on() and true or false) end
	if worldPanel and not on() then worldPanel:Hide() end
end
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then placeWorld() end
	syncOn()
end)
ns.OnFeatureChanged(function(k) if k == "markerWheel" then syncOn() end end)

ns.MarkerWheel = {
	ToggleDebug = function()
		debugOn = not debugOn
		print(P .. "marker wheel debug " .. (debugOn and "on - use a wheel and read chat" or "off"))
	end,
}
