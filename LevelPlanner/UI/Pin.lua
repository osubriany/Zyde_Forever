-- Pin: the step list's "..." menu finds the nearest innkeeper, ammo vendor, class trainer or repair
-- vendor and puts it at the top of the steps (arrow, map pins and all). It stays until you
-- right-click that step. Kept per character, so it survives a /reload.
local ADDON, zyde = ...
zyde.LP = zyde.LP or {}
local ns = zyde.LP

local Pin = {}
ns.Pin = Pin

-- What the menu offers. place: a Places.lua kind; ammo: Zyde's ammo vendor finder.
Pin.KINDS = {
	{ key = "inn", label = "Innkeeper", place = "Innkeeper", icon = "Interface\\Minimap\\Tracking\\Innkeeper" },
	{ key = "ammo", label = "Ammo vendor", ammo = true, icon = "Interface\\Icons\\INV_Ammo_Arrow_02" },
	{ key = "trainer", label = "Class trainer", place = "Class Trainer", icon = "Interface\\Minimap\\Tracking\\Class" },
	{ key = "repair", label = "Repair", place = "Repair", icon = "Interface\\Minimap\\Tracking\\Repair" },
}

local function current() return ns.char and ns.char.pin end

-- The nearest NPC of a kind: { name, map, x, y (0-100) } or nil, plus a reason.
local function nearest(kind)
	local here = ns.Geo.PlayerPoint()
	if not here then return nil, "your position isn't known" end
	if kind.ammo then
		local Ammo = zyde.Ammo
		if not (Ammo and Ammo.Nearest) then return nil, "the ammo vendor finder isn't loaded" end
		local ok, v, what = pcall(Ammo.Nearest)
		if not ok or not v then return nil, "no ammo vendor known on this continent" end
		return { name = v.name or "Ammo vendor", map = v.map, x = v.x * 100, y = v.y * 100, what = what }
	end
	local ok, list = pcall(ns.Places.List, kind.place)
	if not ok or type(list) ~= "table" then return nil, "Questie's NPC data isn't ready" end
	local best, bestD
	for _, pl in ipairs(list) do
		local d = ns.Geo.Distance(here, pl.point)
		if d and (not bestD or d < bestD) then best, bestD = pl, d end
	end
	if not best then return nil, "none known on this continent" end
	return { name = best.name, map = best.point.map, x = best.point.x, y = best.point.y }
end

-- The pinned step, added at the top of the plan's steps (call before the plan is shown).
function Pin.Apply(plan)
	if not plan or not plan.stops then return end
	if plan.stops[1] and plan.stops[1].kind == "pin" then table.remove(plan.stops, 1) end
	local p = current()
	if not p then return end
	local point = ns.Geo.PointOnMap(p.map, p.x, p.y)
	if not point then return end
	table.insert(plan.stops, 1, {
		kind = "pin", label = "Go to " .. p.name, point = point, work = 0, mobXp = 0, xp = 0,
		npcName = p.name, pinLabel = p.label, icon = p.icon,
	})
end

local function refresh()
	if ns.plan and ns.OnPlanReady then ns.OnPlanReady(ns.plan) end
end

function Pin.Set(kind)
	local found, why = nearest(kind)
	if not found then
		ns.print(kind.label .. ": " .. (why or "not found"))
		return
	end
	ns.char.pin = { key = kind.key, label = kind.label, icon = kind.icon, name = found.name,
		map = found.map, x = found.x, y = found.y }
	local mapInfo = C_Map.GetMapInfo(found.map)
	ns.print(string.format("%s: %s, %s - added at the top (right-click it to remove)", kind.label, found.name,
		mapInfo and mapInfo.name or "?"))
	refresh()
end

function Pin.Clear()
	if not current() then return end
	ns.char.pin = nil
	refresh()
end

----------------------------------------------------------------------------------------
-- The menu: a small list under the "..." button
----------------------------------------------------------------------------------------
local menu
function Pin.ToggleMenu(anchor)
	if menu and menu:IsShown() then menu:Hide() return end
	if not menu then
		menu = CreateFrame("Frame", "LevelPlannerPinMenu", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
		menu:SetFrameStrata("DIALOG")
		menu:SetClampedToScreen(true)
		if menu.SetBackdrop then
			menu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
			menu:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
			menu:SetBackdropBorderColor(1, 1, 1, 0.2)
		end
		local head = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		head:SetPoint("TOPLEFT", 8, -6)
		head:SetText("Find the nearest")
		local y = -22
		for _, kind in ipairs(Pin.KINDS) do
			local b = CreateFrame("Button", nil, menu)
			b:SetSize(150, 20)
			b:SetPoint("TOPLEFT", 4, y)
			b.hl = b:CreateTexture(nil, "HIGHLIGHT")
			b.hl:SetAllPoints()
			b.hl:SetColorTexture(1, 1, 1, 0.1)
			b.icon = b:CreateTexture(nil, "ARTWORK")
			b.icon:SetSize(16, 16)
			b.icon:SetPoint("LEFT", 4, 0)
			b.icon:SetTexture(kind.icon)
			b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
			b.text:SetText(kind.label)
			b:SetScript("OnClick", function() menu:Hide() Pin.Set(kind) end)
			y = y - 20
		end
		menu:SetSize(158, -y + 6)
		tinsert(UISpecialFrames, "LevelPlannerPinMenu") -- Escape closes it
	end
	menu:ClearAllPoints()
	menu:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
	menu:Show()
end
