-- Toast (phase d): when an upgrade lands in your bags (looted, quest reward, bought, mailed), a small
-- popup shows it with an Equip button. Gear can't be changed in combat, so in combat the button
-- waits and equips the moment combat ends. Drag the popup to move it; /ga toast turns it off.
local _, zyde = ...
zyde.GA = zyde.GA or {}
local ns = zyde.GA

local Toast = {}
ns.Toast = Toast

local equipByName = (C_Item and C_Item.EquipItemByName) or EquipItemByName

local function inCombat() return InCombatLockdown and InCombatLockdown() end
local function enabled() return ns.db and ns.db.toast end

---------------------------------------------------------------------------------------------
-- The popup
---------------------------------------------------------------------------------------------
local frame, current, pendingEquip

local function build()
	local f = CreateFrame("Frame", "GearAdvisorToast", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	f:SetSize(320, 74)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	if f.SetBackdrop then
		f:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		f:SetBackdropColor(0, 0, 0, 0.85)
		f:SetBackdropBorderColor(0.1, 1, 0.1)
	end
	local pos = ns.db and ns.db.toastPos
	if pos then f:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else f:SetPoint("TOP", UIParent, "TOP", 0, -140) end
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, _, x, y = self:GetPoint()
		ns.db.toastPos = { point, x, y }
	end)

	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetSize(40, 40)
	f.icon:SetPoint("LEFT", 12, 0)

	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 8, 0)
	f.title:SetPoint("RIGHT", -28, 0)
	f.title:SetJustifyH("LEFT")

	f.detail = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.detail:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
	f.detail:SetPoint("RIGHT", -12, 0)
	f.detail:SetJustifyH("LEFT")

	f.equip = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.equip:SetSize(120, 20)
	f.equip:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", 8, -4)
	f.equip:SetScript("OnClick", function() Toast.equip() end)

	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:SetPoint("TOPRIGHT", 2, 2)
	f.close:SetScript("OnClick", function() Toast.hide() end)

	-- Hover the icon for the item's tooltip (with GearAdvisor's breakdown).
	local hit = CreateFrame("Frame", nil, f)
	hit:SetAllPoints(f.icon)
	hit:EnableMouse(true)
	hit:SetScript("OnEnter", function(self)
		if current then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(current.link)
			GameTooltip:Show()
		end
	end)
	hit:SetScript("OnLeave", function() GameTooltip:Hide() end)

	f:Hide()
	return f
end

local function setButton()
	if not frame then return end
	if pendingEquip then
		frame.equip:SetText("Equips after combat")
		frame.equip:Disable()
	elseif inCombat() then
		frame.equip:SetText("Equip after combat")
		frame.equip:Enable()
	else
		frame.equip:SetText("Equip")
		frame.equip:Enable()
	end
end

function Toast.hide()
	current, pendingEquip = nil, nil
	if frame then frame:Hide() end
end

function Toast.show(link, r)
	frame = frame or build()
	current = { link = link, slot = r.slot }
	pendingEquip = nil
	local texture = ns.safe(C_Item and C_Item.GetItemIconByID or GetItemIcon, r.info.itemID)
	frame.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
	frame.title:SetText(("|cff1aff1aUpgrade +%.1f%%|r  %s"):format(r.pct, link))
	local over = (r.vs and r.vs[1]) and ("over " .. table.concat(r.vs, " + ")) or "(empty slot)"
	local notes = (r.notes and #r.notes > 0) and (" – " .. table.concat(r.notes, ", ")) or ""
	frame.detail:SetText(over .. notes)
	setButton()
	frame:Show()
	if PlaySound and SOUNDKIT and SOUNDKIT.UI_EPICLOOT_TOAST then pcall(PlaySound, SOUNDKIT.UI_EPICLOOT_TOAST) end
end

local function doEquip()
	if not current then return end
	-- EquipItemByName with the slot the score picked (the right ring or trinket slot).
	local ok = pcall(equipByName, current.link, current.slot)
	if not ok then pcall(equipByName, current.link) end
	Toast.hide()
end

function Toast.equip()
	if not current then return end
	if inCombat() then
		pendingEquip = true
		setButton()
		return
	end
	doEquip()
end

---------------------------------------------------------------------------------------------
-- Spotting new upgrades: compare the bags' items with the last look; new gear that's an upgrade
-- gets a popup. The first look after login only remembers what's there.
---------------------------------------------------------------------------------------------
local known        -- link -> count, from the last scan; nil until the first scan
local quietUntil = 0   -- no popups before this time (bags fill in for a few seconds after login)
local silentNext = false  -- next scan only remembers (you swapped gear: the old piece went to your bags)
local function scan()
	local now = {}
	for _, info in ipairs(zyde.Bags.items()) do   -- Zyde's shared bag list (Bags.lua)
		local link = info.hyperlink
		if link then now[link] = (now[link] or 0) + 1 end
	end
	local first = known == nil
	local before = known or {}
	known = now
	local silent = silentNext or GetTime() < quietUntil
	silentNext = false
	if first or silent or not enabled() then return end
	local best, bestR
	for link, n in pairs(now) do
		if n > (before[link] or 0) and ns.Stats.isGear(link) then
			local ok, r = pcall(ns.Score.compare, link)
			if ok and r and r.kind == "upgrade" and (not bestR or r.pct > bestR.pct) then best, bestR = link, r end
			if ok and r and r.kind == "loading" then
				-- Data not in yet: forget it, so the next scan sees it as new again.
				now[link] = (now[link] or 1) - 1
				C_Timer.After(1, function() if Toast.scanSoon then Toast.scanSoon() end end)
			end
		end
	end
	if best then Toast.show(best, bestR) end
end

local queued = false
local function scanSoon()
	if queued then return end
	queued = true
	C_Timer.After(0.3, function()
		queued = false
		if inCombat() then return end   -- links can be secret in combat; we look again after
		pcall(scan)
	end)
end
Toast.scanSoon = scanSoon

local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_EQUIPMENT_CHANGED" }) do
	pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_ENTERING_WORLD" then quietUntil = GetTime() + 5 end
	if event == "PLAYER_EQUIPMENT_CHANGED" then silentNext = true end
	if event == "PLAYER_REGEN_DISABLED" then
		setButton()
		return
	end
	if event == "PLAYER_REGEN_ENABLED" then
		if pendingEquip then
			pendingEquip = nil
			doEquip()
		else
			setButton()
		end
	end
	if event == "PLAYER_EQUIPMENT_CHANGED" and current then
		-- You equipped it some other way: the popup has done its job.
		local still = false
		for _, info in ipairs(zyde.Bags.items()) do
			if info.hyperlink == current.link then still = true break end
		end
		if not still then Toast.hide() end
	end
	scanSoon()
end)
