-- Zyde_Forever: target marks and world markers.
--   Target markers: hold the marker key and two rows of four icons appear
--     above your target's name. Top: skull, X, square, moon. Bottom:
--     triangle, diamond, circle, star. The red button removes the mark on
--     your target. The gold ALL button removes every mark, even on something
--     whose nameplate is gone. Clicking the icon already on your target
--     removes that mark too.
--   World markers: press the key to show a small grid of squares, click one,
--     then click the ground. Press the key again to put the grid away. Drag
--     its title bar to move it. The last square clears every world marker.
-- Set the keys in Options > Keybindings > AddOns > Zyde Forever.
--
-- Marking is protected on Forever, so each icon is a secure button running
-- /tm or /worldmarker. Only a real click can run it.

local ADDON, ns = ...

local P = "|cff66ccffZyde_Forever|r: "
local RAID_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"

local function on() return ns.F("markerWheel") end

local debugOn = false
-- Called by each marker's own macro line: shows (in /zyde wheeldebug) that it ran.
function ZydeForever_WheelRan(what)
	if debugOn then print(P .. ("wheel ran: %s at %.2f"):format(tostring(what), GetTime())) end
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
	-- Same kind of frame as the target wheel. A normal frame here blocks the
	-- marker, and a script on the button does too.
	local panel = CreateFrame("Frame", cfg.name .. "Palette", UIParent, "SecureHandlerBaseTemplate")
	panel:SetSize(PAD * 2 + cols * CELL + (cols - 1) * GAP, PAD + HEADER + 4 + rows * CELL + (rows - 1) * GAP + PAD)
	panel:SetFrameStrata("HIGH")
	panel:SetClampedToScreen(true)
	panel:EnableMouse(false)
	panel:SetPoint("RIGHT", UIParent, "RIGHT", -24, 0)
	panel:Hide()

	panel.bg = panel:CreateTexture(nil, "BACKGROUND")
	panel.bg:SetAllPoints()
	panel.bg:SetColorTexture(0.07, 0.07, 0.07, 0.94)
	panel.edges = ns.newEdges(panel, "OVERLAY", 1)
	ns.placeEdges(panel.edges, panel, -1, 1)
	for _, t in ipairs(panel.edges) do t:SetColorTexture(0, 0, 0, 0.95) end

	local squares = {}
	local function square(it, index)
		local col = (index - 1) % cols
		local row = math.floor((index - 1) / cols)
		-- Owned by UIParent, not the panel. A click on a child of the panel never
		-- reaches the placement on this client. Same kind of button Leatrix uses.
		local b = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
		b:SetFrameStrata("DIALOG")
		b:SetSize(CELL, CELL)
		b:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + col * (CELL + GAP), -(PAD + HEADER + 4 + row * (CELL + GAP)))
		b:RegisterForClicks("AnyUp", "AnyDown")
		if b.SetMouseClickEnabled then b:SetMouseClickEnabled(true) end
		-- Run on the mouse-up. A press would eat the click that has to land on the ground.
		b:SetAttribute("pressAndHoldAction", true)
		b:SetAttribute("typerelease", "worldmarker")
		b:SetAttribute("typerelease1", "worldmarker")
		if it.clear then
			b:SetAttribute("action", "clear")
			b:SetAttribute("action1", "clear")
		else
			b:SetAttribute("marker", it.marker)
			b:SetAttribute("marker1", it.marker)
			b:SetAttribute("action", "set")
			b:SetAttribute("action1", "set")
		end
		b:Hide()
		squares[index] = b
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
		return b
	end

	for i, it in ipairs(cfg.items) do square(it, i) end
	if cfg.center then square(cfg.center, #cfg.items + 1) end
	panel.squares = squares

	_G["BINDING_NAME_CLICK " .. cfg.name .. "Key:LeftButton"] = cfg.bind
	local key = CreateFrame("Button", cfg.name .. "Key", UIParent, "SecureActionButtonTemplate, SecureHandlerBaseTemplate")
	key:SetSize(1, 1)
	key:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
	key:SetAlpha(0)
	key:RegisterForClicks("AnyDown", "AnyUp")
	key:SetFrameRef("panel", panel)
	for i, b in ipairs(squares) do key:SetFrameRef("sq" .. i, b) end
	key:SetAttribute("on", true)
	key:SetAttribute("nsq", #squares)
	-- Header is the panel, same as the target wheel. The key cannot run this itself.
	SecureHandlerWrapScript(key, "OnClick", panel, [[
		if not down then return end
		if not self:GetAttribute("on") then return end
		local panel = self:GetFrameRef("panel")
		local show = not panel:IsShown()
		if show then panel:Show() else panel:Hide() end
		local n = self:GetAttribute("nsq")
		for i = 1, n do
			local b = self:GetFrameRef("sq" .. i)
			if show then b:Show() else b:Hide() end
		end
	]])
	key:HookScript("OnClick", function(_, _, down)
		if debugOn and down then print(P .. cfg.bind .. ": toggled") end
	end)

	-- Drag handle sits beside the secure frame, not inside it. Moving a secure
	-- frame from one of its own scripts blocks later marker clicks.
	local drag = CreateFrame("Frame", nil, UIParent)
	drag:SetFrameStrata("HIGH")
	drag:SetHeight(HEADER)
	drag:SetClampedToScreen(true)
	drag:EnableMouse(true)
	drag:RegisterForDrag("LeftButton")
	drag:Hide()
	drag.bg = drag:CreateTexture(nil, "BACKGROUND")
	drag.bg:SetAllPoints()
	drag.bg:SetColorTexture(0.14, 0.14, 0.16, 1)
	drag.title = drag:CreateFontString(nil, "OVERLAY")
	if not drag.title:SetFont("Fonts\\ARIALN.TTF", 13, "OUTLINE") then drag.title:SetFontObject("GameFontNormal") end
	drag.title:SetPoint("CENTER")
	drag.title:SetText(cfg.title or "Markers")
	drag.title:SetTextColor(1, 0.84, 0.35)
	local function parkDrag()
		if not panel:IsShown() or InCombatLockdown() then drag:Hide() return end
		drag:ClearAllPoints()
		drag:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -1)
		drag:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -1)
		drag:Show()
	end
	-- Move by setting the panel's point. StartMoving on the secure frame would block the markers.
	drag:SetScript("OnDragStart", function(self)
		if InCombatLockdown() then return end
		local left, top = panel:GetLeft(), panel:GetTop()
		if not left or not top then return end
		local scale = UIParent:GetEffectiveScale()
		local x, y = GetCursorPosition()
		self.ox, self.oy = x / scale - left, y / scale - top
		self.dragging = true
	end)
	drag:SetScript("OnDragStop", function(self)
		self.dragging = false
		if InCombatLockdown() then return end
		local point, _, _, x, y = panel:GetPoint()
		ZydeForeverDB = ZydeForeverDB or {}
		ZydeForeverDB.worldMarkerPos = { point = point, x = x, y = y }
		parkDrag()
	end)
	drag:SetScript("OnUpdate", function(self)
		if not self.dragging then return end
		if InCombatLockdown() then self.dragging = false return end
		local scale = UIParent:GetEffectiveScale()
		local x, y = GetCursorPosition()
		panel:ClearAllPoints()
		panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale - self.ox, y / scale - self.oy)
	end)
	key:HookScript("OnClick", function(_, _, down)
		if down then C_Timer.After(0, parkDrag) end
	end)

	return key, panel
end

---------------------------------------------------------------------------
-- Target markers
---------------------------------------------------------------------------
local TARGET_ITEMS = {}
for _, m in ipairs({
	{ 8, "Skull", { 1, 1, 1 } }, { 7, "X", { 1, 0.2, 0.2 } }, { 6, "Square", { 0.2, 0.55, 1 } },
	{ 5, "Moon", { 0.75, 0.85, 1 } }, { 4, "Triangle", { 0.2, 1, 0.2 } }, { 3, "Diamond", { 0.8, 0.2, 1 } },
	{ 2, "Circle", { 1, 0.5, 0 } }, { 1, "Star", { 1, 0.92, 0 } },
}) do
	TARGET_ITEMS[#TARGET_ITEMS + 1] = { index = m[1], name = m[2], color = m[3], icon = RAID_ICON .. m[1], macro = "/tm " .. m[1] }
end

-- The mark on your target, when the client lets us read it. Nil when there
-- is none, or when the number is secret (a fight can hide it).
local function targetMarker()
	if not UnitExists("target") then return end
	local idx = ns.safe(GetRaidTargetIndex, "target")
	if ns.isSecret(idx) then return end
	if type(idx) ~= "number" or idx < 1 or idx > 8 then return end
	return idx
end

---------------------------------------------------------------------------
-- World markers, same order as the target wheel: skull, X, square, moon,
-- triangle, diamond, circle, star. marker is the ground-marker number.
---------------------------------------------------------------------------
local WORLD_ITEMS = {}
for _, m in ipairs({
	{ 8, 8, "Skull", { 1, 1, 1 } }, { 4, 7, "X", { 1, 0.2, 0.2 } },
	{ 1, 6, "Square", { 0.2, 0.55, 1 } }, { 7, 5, "Moon", { 0.75, 0.85, 1 } },
	{ 2, 4, "Triangle", { 0.2, 1, 0.2 } }, { 3, 3, "Diamond", { 0.8, 0.2, 1 } },
	{ 6, 2, "Circle", { 1, 0.5, 0 } }, { 5, 1, "Star", { 1, 0.92, 0 } },
}) do
	-- m = { world marker number, raid icon, name, color }
	WORLD_ITEMS[#WORLD_ITEMS + 1] = { marker = m[1], name = m[3], color = m[4], icon = RAID_ICON .. m[2] }
end

-- 25% smaller than the 30px row. Four icons on each row. Two tall buttons
-- on the end: red removes your target's mark, gold removes every mark.
local ROW_ICON, ROW_GAP, ROW_PAD, ROW_SPLIT, ROW_COLS = 22, 2, 2, 4, 4
local CLEAR_W, ALL_W = 22, 32
local placeTargetRow, paintTargetRow

-- Each icon can sit on only one unit. Putting 8 through 1 on you pulls every
-- icon off whoever has it, nameplate or not. 0 then takes the last one off you.
local CLEAR_ALL = "/tm [@player] 8\n/tm [@player] 7\n/tm [@player] 6\n/tm [@player] 5\n/tm [@player] 4\n/tm [@player] 3\n/tm [@player] 2\n/tm [@player] 1\n/tm [@player] 0"

local function makeTargetRow()
	local handler = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
	handler:Hide()
	local gridW = ROW_COLS * ROW_ICON + (ROW_COLS - 1) * ROW_GAP
	local gridH = ROW_ICON * 2 + ROW_GAP
	local row = CreateFrame("Frame", "ZydeForeverTargetMarks", UIParent)
	row:SetSize(ROW_PAD * 2 + gridW + ROW_SPLIT + CLEAR_W + ROW_GAP + ALL_W, ROW_PAD * 2 + gridH)
	row:SetFrameStrata("HIGH")
	row:EnableMouse(false)
	row:Hide()
	row.held = false
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(0.07, 0.07, 0.07, 0.88)
	row.edges = ns.newEdges(row, "OVERLAY", 1)
	ns.placeEdges(row.edges, row, -1, 1)
	for _, t in ipairs(row.edges) do t:SetColorTexture(0, 0, 0, 0.95) end

	local function button(macro, tag, markIndex)
		local b = CreateFrame("Button", nil, row, "SecureActionButtonTemplate")
		b:SetSize(ROW_ICON, ROW_ICON)
		b:RegisterForClicks("AnyDown", "AnyUp")
		if b.SetMouseClickEnabled then b:SetMouseClickEnabled(true) end
		b:SetAttribute("type", "macro")
		b:SetAttribute("macrotext", macro .. "\n/run ZydeForever_WheelRan(\"" .. tag .. "\")")
		b:SetAttribute("ran", tag)
		if markIndex then
			-- The secure click cannot ask which icon is on the target. The row
			-- holds that number, and this click clears only when it matches.
			b:SetAttribute("mark", markIndex)
			SecureHandlerWrapScript(b, "PreClick", handler, [[
				local mark = self:GetAttribute("mark")
				if not mark then return end
				local cur = self:GetParent():GetAttribute("cur")
				local cmd = "/tm " .. mark
				if cur == mark then cmd = "/tm 0" end
				local ran = self:GetAttribute("ran")
				if ran then cmd = cmd .. "\n/run ZydeForever_WheelRan(\"" .. ran .. "\")" end
				self:SetAttribute("macrotext", cmd)
			]])
		end
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetPoint("CENTER")
		b.icon:SetSize(ROW_ICON - 4, ROW_ICON - 4)
		b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		b.edges = ns.newEdges(b, "OVERLAY", 2)
		ns.placeEdges(b.edges, b, 0, 1)
		return b
	end

	row.slots = {}
	for i, it in ipairs(TARGET_ITEMS) do
		local b = button(it.macro, it.name, it.index)
		local col = (i - 1) % ROW_COLS
		local line = math.floor((i - 1) / ROW_COLS)
		b:SetPoint("TOPLEFT", row, "TOPLEFT", ROW_PAD + col * (ROW_ICON + ROW_GAP), -(ROW_PAD + line * (ROW_ICON + ROW_GAP)))
		b.icon:SetTexture(it.icon)
		b.item = it
		for _, t in ipairs(b.edges) do t:SetColorTexture(it.color[1], it.color[2], it.color[3], 1) end
		row.slots[i] = b
	end
	local clear = button("/tm 0", "Remove mark")
	clear:SetSize(CLEAR_W, gridH)
	clear:SetPoint("TOPLEFT", row, "TOPLEFT", ROW_PAD + gridW + ROW_SPLIT, -ROW_PAD)
	clear.icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
	for _, t in ipairs(clear.edges) do t:SetColorTexture(1, 0.35, 0.3, 1) end
	row.clear = clear

	local all = CreateFrame("Button", nil, row, "SecureActionButtonTemplate")
	all:SetSize(ALL_W, gridH)
	all:SetPoint("TOPLEFT", row, "TOPLEFT", ROW_PAD + gridW + ROW_SPLIT + CLEAR_W + ROW_GAP, -ROW_PAD)
	all:RegisterForClicks("AnyDown", "AnyUp")
	if all.SetMouseClickEnabled then all:SetMouseClickEnabled(true) end
	all:SetAttribute("type", "macro")
	all:SetAttribute("macrotext", CLEAR_ALL .. "\n/run ZydeForever_WheelRan(\"Clear all\")")
	all.bg = all:CreateTexture(nil, "BACKGROUND")
	all.bg:SetPoint("TOPLEFT", 1, -1)
	all.bg:SetPoint("BOTTOMRIGHT", -1, 1)
	all.bg:SetColorTexture(0.55, 0.38, 0.05, 0.95)
	all.label = all:CreateFontString(nil, "OVERLAY")
	if not all.label:SetFont("Fonts\\ARIALN.TTF", 12, "OUTLINE") then all.label:SetFontObject("GameFontNormal") end
	all.label:SetPoint("CENTER")
	all.label:SetText("ALL")
	all.label:SetTextColor(1, 0.9, 0.45)
	all.edges = ns.newEdges(all, "OVERLAY", 2)
	ns.placeEdges(all.edges, all, 0, 1)
	for _, t in ipairs(all.edges) do t:SetColorTexture(1, 0.82, 0.2, 1) end
	row.clearAll = all

	-- Same click binding as the old hold wheel, so the key you already set still works.
	_G["BINDING_NAME_CLICK ZydeForeverMarkerKey:LeftButton"] = "Marker wheel (hold)"
	local key = CreateFrame("Button", "ZydeForeverMarkerKey", UIParent, "SecureActionButtonTemplate, SecureHandlerBaseTemplate")
	key:SetSize(1, 1)
	key:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
	key:SetAlpha(0)
	key:RegisterForClicks("AnyDown", "AnyUp")
	key:SetFrameRef("row", row)
	key:SetAttribute("on", true)
	SecureHandlerWrapScript(key, "OnClick", handler, [[
		if not self:GetAttribute("on") then return end
		local row = self:GetFrameRef("row")
		if down then row:Show() else row:Hide() end
	]])
	key:HookScript("OnClick", function(_, _, down)
		row.held = down and true or false
		if row.held then placeTargetRow() paintTargetRow() else row:Hide() end
		if debugOn then print(P .. "target markers: " .. (down and "pressed" or "released")) end
	end)
	return row, key
end

local targetRow, markKey = makeTargetRow()

function placeTargetRow()
	local row = targetRow
	if not row then return end
	if not on() or not row.held then row:Hide() return end
	local exists = ns.safe(UnitExists, "target")
	if not ns.isSecret(exists) and not exists then row:Hide() return end
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and ns.safe(C_NamePlate.GetNamePlateForUnit, "target")
	if not plate or (plate.IsForbidden and plate:IsForbidden()) then row:Hide() row.anchor = nil return end
	local name = ns.TargetPlateName and ns.TargetPlateName()
	if row.anchor == (name or plate) and row:IsShown() then return end
	row.anchor = name or plate
	row:ClearAllPoints()
	local ok = name and pcall(row.SetPoint, row, "BOTTOM", name, "TOP", 0, 3)
	if not ok then ok = pcall(row.SetPoint, row, "BOTTOM", plate, "TOP", 0, 4) end
	if ok then row:Show() else row:Hide() end
end

function paintTargetRow()
	local cur = targetMarker()
	-- Plain frame, so this can be written during a fight. 0 means "no mark we can see".
	targetRow:SetAttribute("cur", cur or 0)
	for _, b in ipairs(targetRow.slots) do
		local onMark = cur ~= nil and cur == b.item.index
		local c = onMark and { 1, 0.92, 0.4 } or b.item.color
		for _, t in ipairs(b.edges) do t:SetColorTexture(c[1], c[2], c[3], 1) end
		b.icon:SetAlpha(onMark and 1 or 0.85)
	end
end

local worldKey, worldPanel
local keys
keys = { markKey }
worldKey, worldPanel = makePalette({
	name = "ZydeForeverWorldMarker", bind = "World markers", title = "Markers",
	items = WORLD_ITEMS,
	center = {
		clear = true, name = "Clear all", color = { 1, 0.35, 0.3 },
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
	if worldPanel and not on() then
		worldPanel:Hide()
		if worldPanel.squares then
			for _, b in ipairs(worldPanel.squares) do b:Hide() end
		end
	end
	if not on() then targetRow.held = false targetRow:Hide() end
end
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("NAME_PLATE_UNIT_ADDED")
ev:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then placeWorld() end
	syncOn()
	placeTargetRow()
	if targetRow:IsShown() then paintTargetRow() end
end)
local wait = 0
ev:SetScript("OnUpdate", function(_, dt)
	wait = wait + dt
	if wait < 0.2 then return end
	wait = 0
	placeTargetRow()
	if targetRow:IsShown() then paintTargetRow() end
end)
ns.OnFeatureChanged(function(k) if k == "markerWheel" then syncOn() end end)

ns.MarkerWheel = {
	ToggleDebug = function()
		debugOn = not debugOn
		print(P .. "marker debug " .. (debugOn and "on - click a target mark or a world marker square and read chat" or "off"))
	end,
}
