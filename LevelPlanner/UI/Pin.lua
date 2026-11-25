-- Pin: the step list's "..." menu finds the nearest innkeeper, ammo vendor, class trainer, repair or auctioneer
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
	{ key = "auction", label = "Auctioneer", place = "Auctioneer", icon = "Interface\\Minimap\\Tracking\\Auctioneer" },
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
	-- (anywhere: travel steps from "..." > Travel may sit above it)
	for i = #plan.stops, 1, -1 do
		if plan.stops[i].kind == "pin" then table.remove(plan.stops, i) end
	end
	local p = current()
	if not p then return end
	local point = ns.Geo.PointOnMap(p.map, p.x, p.y)
	if not point then return end
	-- (a ghost's run back to the corpse stays first)
	local at = (plan.stops[1] and plan.stops[1].mode == "corpse") and 2 or 1
	table.insert(plan.stops, at, {
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
		-- Travel > Dungeons / Zones (UI/TravelTo.lua): route to a dungeon entrance or a zone, first
		local tsep = menu:CreateTexture(nil, "ARTWORK")
		tsep:SetColorTexture(1, 1, 1, 0.12)
		tsep:SetHeight(1)
		tsep:SetPoint("TOPLEFT", 8, y - 3)
		tsep:SetPoint("TOPRIGHT", -8, y - 3)
		y = y - 7
		local tr = CreateFrame("Button", nil, menu)
		tr:SetSize(150, 20)
		tr:SetPoint("TOPLEFT", 4, y)
		tr.hl = tr:CreateTexture(nil, "HIGHLIGHT")
		tr.hl:SetAllPoints()
		tr.hl:SetColorTexture(1, 1, 1, 0.1)
		tr.icon = tr:CreateTexture(nil, "ARTWORK")
		tr.icon:SetSize(16, 16)
		tr.icon:SetPoint("LEFT", 4, 0)
		tr.icon:SetTexture("Interface\\Icons\\INV_Misc_Map02")
		tr.text = tr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		tr.text:SetPoint("LEFT", tr.icon, "RIGHT", 6, 0)
		tr.text:SetText("Travel")
		tr.arrow = tr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		tr.arrow:SetPoint("RIGHT", -6, 0)
		tr.arrow:SetText("<")
		tr:SetScript("OnClick", function(self)
			if ns.Skip then ns.Skip.HideList() end
			if ns.TravelTo then ns.TravelTo.ToggleSide(self) end
		end)
		tr:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:AddLine("Travel")
			GameTooltip:AddLine("Pick a dungeon, a city or a zone: the steps route you there first (hearthstone, flights, boats, passes) until you arrive. Right-click a travel step to stop.", 1, 1, 1, true)
			GameTooltip:Show()
		end)
		tr:SetScript("OnLeave", function() GameTooltip:Hide() end)
		y = y - 20
		-- Skipped quests (UI/Skip.lua): the quests you right-clicked away; click one to bring it back
		local sk = CreateFrame("Button", nil, menu)
		sk:SetSize(150, 20)
		sk:SetPoint("TOPLEFT", 4, y)
		sk.hl = sk:CreateTexture(nil, "HIGHLIGHT")
		sk.hl:SetAllPoints()
		sk.hl:SetColorTexture(1, 1, 1, 0.1)
		sk.icon = sk:CreateTexture(nil, "ARTWORK")
		sk.icon:SetSize(16, 16)
		sk.icon:SetPoint("LEFT", 4, 0)
		sk.icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
		sk.text = sk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		sk.text:SetPoint("LEFT", sk.icon, "RIGHT", 6, 0)
		sk.arrow = sk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		sk.arrow:SetPoint("RIGHT", -6, 0)
		sk.arrow:SetText("<")
		menu.skipRefresh = function()
			local n = 0
			for _ in pairs(ns.skipped) do n = n + 1 end
			sk.text:SetText(n > 0 and string.format("Skipped quests |cff999999(%d)|r", n) or "Skipped quests")
		end
		sk:SetScript("OnClick", function(self)
			local side = _G.LevelPlannerTravelMenu
			if side then side:Hide() end
			if ns.Skip then ns.Skip.ToggleList(self) end
		end)
		sk:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:AddLine("Skipped quests")
			GameTooltip:AddLine("Quests and dungeon runs the planner leaves out. Right-click a step to skip it; click one here to put it back. Saved for this character.", 1, 1, 1, true)
			GameTooltip:Show()
		end)
		sk:SetScript("OnLeave", function() GameTooltip:Hide() end)
		y = y - 20
		-- planner setting: elite quests (auto -> on -> off; same as /lp elites)
		local sep = menu:CreateTexture(nil, "ARTWORK")
		sep:SetColorTexture(1, 1, 1, 0.12)
		sep:SetHeight(1)
		sep:SetPoint("TOPLEFT", 8, y - 3)
		sep:SetPoint("TOPRIGHT", -8, y - 3)
		y = y - 7
		local e = CreateFrame("Button", nil, menu)
		e:SetSize(150, 20)
		e:SetPoint("TOPLEFT", 4, y)
		e.hl = e:CreateTexture(nil, "HIGHLIGHT")
		e.hl:SetAllPoints()
		e.hl:SetColorTexture(1, 1, 1, 0.1)
		e.icon = e:CreateTexture(nil, "ARTWORK")
		e.icon:SetSize(16, 16)
		e.icon:SetPoint("LEFT", 4, 0)
		e.icon:SetTexture("Interface\\Icons\\INV_Misc_Head_Dragon_01")
		e.text = e:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		e.text:SetPoint("LEFT", e.icon, "RIGHT", 6, 0)
		local NEXT = { auto = "on", on = "off", off = "auto" }
		local WORD = { auto = "|cffbbbbbbauto|r", on = "|cff66ff66on|r", off = "|cffff6666off|r" }
		menu.eliteRefresh = function() e.text:SetText("Elite quests: " .. WORD[ns.EliteMode()]) end
		e:SetScript("OnClick", function() ns.SetEliteMode(NEXT[ns.EliteMode()]) menu.eliteRefresh() end)
		e:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:AddLine("Elite quests in the plan")
			GameTooltip:AddLine("Click to switch: auto (when grouped, or a hunter solo once they're yellow), on (always), off (only when grouped).", 1, 1, 1, true)
			GameTooltip:Show()
		end)
		e:SetScript("OnLeave", function() GameTooltip:Hide() end)
		y = y - 20
		-- planner setting: pick-ups (tight <-> loose; same as /lp pickup)
		local p = CreateFrame("Button", nil, menu)
		p:SetSize(150, 20)
		p:SetPoint("TOPLEFT", 4, y)
		p.hl = p:CreateTexture(nil, "HIGHLIGHT")
		p.hl:SetAllPoints()
		p.hl:SetColorTexture(1, 1, 1, 0.1)
		p.icon = p:CreateTexture(nil, "ARTWORK")
		p.icon:SetSize(16, 16)
		p.icon:SetPoint("LEFT", 4, 0)
		p.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
		p.text = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		p.text:SetPoint("LEFT", p.icon, "RIGHT", 6, 0)
		local PWORD = { tight = "|cffbbbbbbtight|r", loose = "|cff66ff66loose|r" }
		menu.pickupRefresh = function() p.text:SetText("Pick-ups: " .. PWORD[ns.PickupMode()]) end
		p:SetScript("OnClick", function()
			ns.SetPickupMode(ns.PickupMode() == "tight" and "loose" or "tight")
			menu.pickupRefresh()
		end)
		p:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:AddLine("Which quests the plan takes")
			GameTooltip:AddLine("Tight: only quests that make the route faster. Loose: also quests on the way (up to ~8 minutes each) that earn at least 35% of the route's XP per minute - closer to guides that take everything.", 1, 1, 1, true)
			GameTooltip:Show()
		end)
		p:SetScript("OnLeave", function() GameTooltip:Hide() end)
		y = y - 20
		-- action: abandon the grey quests the plan doesn't use (asks first; same as /lp cleanup grey)
		local c = CreateFrame("Button", nil, menu)
		c:SetSize(150, 20)
		c:SetPoint("TOPLEFT", 4, y)
		c.hl = c:CreateTexture(nil, "HIGHLIGHT")
		c.hl:SetAllPoints()
		c.hl:SetColorTexture(1, 1, 1, 0.1)
		c.icon = c:CreateTexture(nil, "ARTWORK")
		c.icon:SetSize(16, 16)
		c.icon:SetPoint("LEFT", 4, 0)
		c.icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
		c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		c.text:SetPoint("LEFT", c.icon, "RIGHT", 6, 0)
		c.text:SetText("Cleanup quests")
		c:SetScript("OnClick", function()
			menu:Hide()
			ns.ConfirmGreyCleanup()
		end)
		c:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:AddLine("Cleanup quests")
			local n = ns.GreyCleanupList and #ns.GreyCleanupList() or 0
			GameTooltip:AddLine("Abandons the grey quests in your log that the plan doesn't use - they only get greyer as you level. Keeps grey quests ready to turn in and class quests. Lists them and asks first.", 1, 1, 1, true)
			GameTooltip:AddLine(n > 0 and string.format("%d grey quest(s) to clean up now.", n) or "Nothing to clean up right now.", 0.6, 0.8, 1)
			GameTooltip:Show()
		end)
		c:SetScript("OnLeave", function() GameTooltip:Hide() end)
		y = y - 20
		menu:SetSize(158, -y + 6)
		tinsert(UISpecialFrames, "LevelPlannerPinMenu") -- Escape closes it
	end
	menu.eliteRefresh()
	menu.pickupRefresh()
	menu.skipRefresh()
	if ns.Skip then ns.Skip.HideList() end
	menu:ClearAllPoints()
	menu:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
	menu:Show()
end
