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
	f.icon:SetPoint("TOPLEFT", 12, -12)

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
	f.equip:SetPoint("TOPLEFT", f.detail, "BOTTOMLEFT", 0, -6) -- below the text, however many lines it takes
	f.equip:SetScript("OnClick", function() Toast.equip() end)

	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:SetPoint("TOPRIGHT", 2, 2)
	f.close:SetScript("OnClick", function() Toast.decline() end) -- (not offered again, even after a log-in)

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

-- Upgrades found together wait their turn: after one is equipped or closed, the next best
-- one still in your bags (and still an upgrade, now that your gear changed) shows.
local waiting = {} -- link -> true
local showNextSoon -- (below)

local offered = {} -- link -> true: already shown this session (equipped, closed or still up)

-- Upgrades you closed with the X are remembered (per character, in GearAdvisorDB.toastDeclined) and
-- never offered again, across log-ins. Keyed by item ID and random suffix: a link changes as you level.
-- /ga toast reset forgets them.
local function itemKey(link)
	local id, suffix = tostring(link):match("item:(%d+):[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:([^:|]*)")
	return id and (id .. ":" .. (suffix ~= "" and suffix or "0")) or tostring(link)
end
local function declined()
	if not ns.db then return {} end
	ns.db.toastDeclined = ns.db.toastDeclined or {}
	local who = (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "")
	ns.db.toastDeclined[who] = ns.db.toastDeclined[who] or {}
	return ns.db.toastDeclined[who]
end
function Toast.decline()
	if current then declined()[itemKey(current.link)] = true end
	Toast.hide()
end
function Toast.resetDeclined()
	local d = declined()
	local n = 0
	for k in pairs(d) do d[k] = nil n = n + 1 end
	wipe(offered)
	return n
end

function Toast.hide()
	if current then waiting[current.link] = nil end
	current, pendingEquip = nil, nil
	if frame then frame:Hide() end
	if showNextSoon then showNextSoon() end
end

function Toast.show(link, r)
	frame = frame or build()
	current = { link = link, slot = r.slot }
	offered[link] = true
	pendingEquip = nil
	local texture = ns.safe(C_Item and C_Item.GetItemIconByID or GetItemIcon, r.info.itemID)
	frame.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
	local gain = (r.pct < 0.05 and (r.armorGain or 0) > 0) and ("+" .. r.armorGain .. " armour") or ("+%.1f%%"):format(r.pct)
	frame.title:SetText(("|cff1aff1aUpgrade %s|r  %s"):format(gain, link))
	local over = (r.vs and r.vs[1]) and ("over " .. table.concat(r.vs, " + ")) or "(empty slot)"
	local notes = (r.notes and #r.notes > 0) and (" – " .. table.concat(r.notes, ", ")) or ""
	frame.detail:SetText(over .. notes)
	-- grow to fit a long item name or note that wraps onto more lines
	local textH = (frame.title:GetStringHeight() or 12) + 3 + (frame.detail:GetStringHeight() or 10) + 6 + 20
	frame:SetHeight(math.max(74, textH + 24)) -- 12 above, 12 below
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
-- Spotting upgrades: any gear in your bags that is an upgrade you can wear now gets a popup, once
-- per session. That covers new loot and also gear that turns into an upgrade later (you levelled
-- up and can now wear it, or it came in during a loading screen).
---------------------------------------------------------------------------------------------
local quietUntil = 0   -- no popups before this time (bags fill in for a few seconds after login)
local function scan()
	if GetTime() < quietUntil or not enabled() then return end
	local found, retry = false, false
	for _, info in ipairs(zyde.Bags.items()) do   -- Zyde's shared bag list (Bags.lua)
		local link = info.hyperlink
		if link and not offered[link] and not waiting[link] and not declined()[itemKey(link)] and ns.Stats.isGear(link) then
			local ok, r = pcall(ns.Score.compare, link)
			if ok and r and r.kind == "upgrade" then waiting[link] = true found = true end
			if ok and r and r.kind == "loading" then retry = true end -- data not in yet: look again
		end
	end
	if retry then C_Timer.After(1, function() if Toast.scanSoon then Toast.scanSoon() end end) end
	if found and not current then Toast.showNext() end
end

-- The best upgrade still waiting, or nothing (and the list is cleared of the rest).
function Toast.showNext()
	if current or not enabled() or inCombat() then return end
	local inBags = {}
	for _, info in ipairs(zyde.Bags.items()) do
		if info.hyperlink then inBags[info.hyperlink] = true end
	end
	local best, bestR
	for link in pairs(waiting) do
		local ok, r = false, nil
		if inBags[link] then ok, r = pcall(ns.Score.compare, link) end -- ("x and f()" would keep only ok)
		if ok and r and r.kind == "upgrade" then
			if not bestR or r.pct > bestR.pct then best, bestR = link, r end
		elseif not (ok and r and r.kind == "loading") then
			waiting[link] = nil -- gone, or no longer an upgrade
		end
	end
	if best then Toast.show(best, bestR) end
end

-- (a moment after a change, so the new gear is worn when the rest are scored again)
local nextQueued = false
function showNextSoon()
	if nextQueued then return end
	nextQueued = true
	C_Timer.After(1, function()
		nextQueued = false
		pcall(Toast.showNext)
	end)
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
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP" }) do
	pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_ENTERING_WORLD" then
		quietUntil = GetTime() + 5
		C_Timer.After(5.5, scanSoon) -- then offer what's already waiting in your bags
	end
	if event == "PLAYER_LEVEL_UP" then
		-- the new level counts a moment later; gear you couldn't wear may be an upgrade now
		C_Timer.After(2, scanSoon)
		return
	end
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
			if not current then showNextSoon() end -- (upgrades still waiting from before the fight)
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
