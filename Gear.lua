-- Zyde_Forever: character screen gear (rarity borders, item levels, upgrade flags).
-- Moved out of Zyde_Forever.lua (that file was at Lua's 200-local limit).
-- Loads right after Zyde_Forever.lua: other files use ns.newEdges / ns.placeEdges as they load.

local ADDON, ns = ...
local isSecret, safe, F, fade = ns.isSecret, ns.safe, ns.F, ns.fade

---------------------------------------------------------------------------
-- Character screen: rarity-colored borders on equipped gear.
-- Crisp 2px colored edge, a 1px dark outline outside it, and a soft inner
-- glow fading toward the icon centre. Replaces Blizzard's own quality border.
---------------------------------------------------------------------------
local GEAR_SLOTS = {
	"Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist",
	"Hands", "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1",
	"MainHand", "SecondaryHand", "Ranged", "Ammo",
}

local BORDER_PX = 2   -- colored edge thickness (screen pixels)
local GLOW_PX   = 6   -- inner glow depth
local GLOW_A    = 0.30

local function qualityColor(q)
	if C_Item and C_Item.GetItemQualityColor then
		local r, g, b = safe(C_Item.GetItemQualityColor, q)
		if r then return r, g, b end
	end
	if GetItemQualityColor then
		local r, g, b = safe(GetItemQualityColor, q)
		if r then return r, g, b end
	end
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

local function newEdges(f, layer, sub)
	local t = {}
	for i = 1, 4 do
		t[i] = f:CreateTexture(nil, layer, nil, sub)
		t[i]:SetColorTexture(1, 1, 1, 1)
	end
	return t
end

-- Four strips forming a box: inset > 0 is inside the frame, < 0 outside.
local function placeEdges(t, f, inset, thick)
	local top, bottom, left, right = t[1], t[2], t[3], t[4]
	top:ClearAllPoints()
	top:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset)
	top:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inset, -inset)
	top:SetHeight(thick)
	bottom:ClearAllPoints()
	bottom:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inset, inset)
	bottom:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
	bottom:SetHeight(thick)
	left:ClearAllPoints()
	left:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset - thick)
	left:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inset, inset + thick)
	left:SetWidth(thick)
	right:ClearAllPoints()
	right:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inset, -inset - thick)
	right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset + thick)
	right:SetWidth(thick)
end

local function setGlow(t, r, g, b)
	if not CreateColor then
		for _, tex in ipairs(t) do tex:SetColorTexture(r, g, b, GLOW_A * 0.5) end
		return
	end
	local solid, clear = CreateColor(r, g, b, GLOW_A), CreateColor(r, g, b, 0)
	-- SetGradient(orientation, minColor, maxColor): min = bottom/left.
	t[1]:SetGradient("VERTICAL", clear, solid)   -- top: strong at the edge
	t[2]:SetGradient("VERTICAL", solid, clear)   -- bottom
	t[3]:SetGradient("HORIZONTAL", solid, clear) -- left
	t[4]:SetGradient("HORIZONTAL", clear, solid) -- right
end

local function getBorder(button)
	if button.zydeBorder then return button.zydeBorder end
	local f = CreateFrame("Frame", nil, button)
	f:SetAllPoints(button)
	f:SetFrameLevel(button:GetFrameLevel() + 3)
	f:EnableMouse(false)

	-- Snap thickness to whole screen pixels so edges stay razor sharp.
	local px = 1
	if PixelUtil and PixelUtil.GetNearestPixelSize then
		px = PixelUtil.GetNearestPixelSize(1, button:GetEffectiveScale(), 1)
	end

	f.outline = newEdges(f, "OVERLAY", 1)
	placeEdges(f.outline, f, -px, px)
	for _, tex in ipairs(f.outline) do tex:SetColorTexture(0, 0, 0, 0.9) end

	f.edge = newEdges(f, "OVERLAY", 2)
	placeEdges(f.edge, f, 0, BORDER_PX * px)

	f.glow = newEdges(f, "OVERLAY", 0)
	placeEdges(f.glow, f, BORDER_PX * px, GLOW_PX * px)

	-- Item level, bottom-centre, small with a clean outline.
	f.ilvl = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	f.ilvl:SetPoint("BOTTOM", f, "BOTTOM", 0, 3)
	local font, size = f.ilvl:GetFont()
	if font then f.ilvl:SetFont(font, (size or 11), "OUTLINE") end
	f.ilvl:SetShadowOffset(0, 0)

	-- Upgrade flag: a "!" in the top-right corner (see gearFlag below).
	f.flag = f:CreateFontString(nil, "OVERLAY")
	f.flag:SetFont(STANDARD_TEXT_FONT, 16, "THICKOUTLINE")
	f.flag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
	f.flag:SetText("!")
	f.flag:Hide()

	-- Upgrade waiting in your bags: a green arrow in the top-left corner.
	f.arrow = f:CreateTexture(nil, "OVERLAY", nil, 3)
	f.arrow:SetSize(14, 14)
	f.arrow:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
	f.arrow:SetTexture("Interface\\Buttons\\UI-MicroStream-Green")
	f.arrow:Hide()

	-- Hide Blizzard's quality border on this slot so only ours shows.
	if button.IconBorder then fade(button.IconBorder) end

	-- Add the flag's reason and any bag upgrade to the slot's tooltip.
	button:HookScript("OnEnter", function()
		if not GameTooltip:IsOwned(button) then return end
		local added = false
		if f.flagText and f.flag:IsShown() then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(f.flagText, f.flagR, f.flagG, f.flagB, true)
			added = true
		end
		if f.upgradeText and f.arrow:IsShown() then
			if not added then GameTooltip:AddLine(" ") end
			GameTooltip:AddLine(f.upgradeText, 0.35, 1, 0.35, true)
			added = true
		end
		if added then GameTooltip:Show() end
	end)

	button.zydeBorder = f
	return f
end

-- Upgrade flags: gear well behind your level, and empty slots.
-- Typical gear for your level is about item level = your level + 3 (quest
-- greens). 6-9 behind that: orange "!" (getting old). 10+ behind: red "!".
local GEAR_EXPECT_OVER_LEVEL = 3
local GEAR_AGING, GEAR_WEAK = 6, 10
-- Slots worth filling (not shirt 4, tabard 19, ammo 0).
local FLAG_EMPTY = { [1] = true, [2] = true, [3] = true, [5] = true, [6] = true, [7] = true,
	[8] = true, [9] = true, [10] = true, [11] = true, [12] = true, [13] = true, [14] = true,
	[15] = true, [16] = true, [17] = true, [18] = true }

-- Returns r, g, b, reason for a flag, or nil.
local function gearFlag(slot, lvl, twoHanded)
	local level = UnitLevel("player")
	if not level or isSecret(level) then return nil end
	if not lvl then
		if not FLAG_EMPTY[slot] then return nil end
		if slot == 17 and twoHanded then return nil end -- off hand is empty for a 2-hander
		return 1, 0.2, 0.2, "Empty slot - anything you can put here is an upgrade."
	end
	local behind = level + GEAR_EXPECT_OVER_LEVEL - lvl
	if behind >= GEAR_WEAK then
		return 1, 0.2, 0.2, ("Upgrade this: about %d item levels behind typical gear for level %d."):format(behind, level)
	elseif behind >= GEAR_AGING then
		return 1, 0.6, 0.15, ("Getting old: about %d item levels behind typical gear for level %d."):format(behind, level)
	end
	return nil
end

local function mainHandIsTwoHanded()
	local link = GetInventoryItemLink("player", 16)
	if not link or isSecret(link) then return false end
	local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local equipLoc = select(9, getInfo(link))
	return equipLoc == "INVTYPE_2HWEAPON"
end

-- Shirt, tabard and ammo: item level means nothing there.
local NO_ILVL_SLOTS = { [0] = true, [4] = true, [19] = true }

local function slotItemLevel(slot)
	local lvl
	if C_Item and C_Item.GetCurrentItemLevel and ItemLocation and ItemLocation.CreateFromEquipmentSlot then
		local loc = safe(ItemLocation.CreateFromEquipmentSlot, ItemLocation, slot)
		if loc and safe(loc.IsValid, loc) then lvl = safe(C_Item.GetCurrentItemLevel, loc) end
	end
	if not lvl then
		local link = GetInventoryItemLink("player", slot)
		if link and not isSecret(link) then
			local getLevel = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
			lvl = safe(getLevel, link)
		end
	end
	if lvl and not isSecret(lvl) then return lvl end
	return nil
end

local function showFlag(f, fr, fg, fb, reason)
	if fr then
		f.flag:SetTextColor(fr, fg, fb)
		f.flag:Show()
		f.flagText, f.flagR, f.flagG, f.flagB = reason, fr, fg, fb
	else
		f.flag:Hide()
		f.flagText = nil
	end
end

---------------------------------------------------------------------------
-- Upgrades waiting in your bags, per character slot. Scored by GearAdvisor
-- when it's loaded (its "upgrade" verdict and % gain); otherwise any item you
-- can wear now with a higher item level than what's in the slot.
---------------------------------------------------------------------------
local EQUIP_SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
	INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
	INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
	INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
	INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
	INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
	INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
local bagUpgrades = {} -- slot -> { link, pct (GearAdvisor) or gain (item levels) }

-- Red text in the item's tooltip (level, armor type, class...) = can't wear it now.
local function wearableNow(bag, slot)
	local data = C_TooltipInfo and C_TooltipInfo.GetBagItem and safe(C_TooltipInfo.GetBagItem, bag, slot)
	for _, line in ipairs(data and data.lines or {}) do
		for _, side in ipairs({ { line.leftText, line.leftColor }, { line.rightText, line.rightColor } }) do
			local text, c = side[1], side[2]
			if c and type(text) == "string" and not isSecret(text) and c.r and c.r > 0.95 and c.g < 0.2 and c.b < 0.2 then
				return false
			end
		end
	end
	return true
end

local function scanBagUpgrades()
	wipe(bagUpgrades)
	local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local getLevel = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
	local GA = GearAdvisorAPI
	local function record(slot, link, pct, gain)
		local cur = bagUpgrades[slot]
		local score = pct or gain or 0
		if not cur or score > (cur.pct or cur.gain or 0) then bagUpgrades[slot] = { link = link, pct = pct, gain = gain } end
	end
	for _, info in ipairs(ns.Bags.items()) do -- shared bag list (Bags.lua)
		local bag, bslot = info.bag, info.slot
		local link = info and info.hyperlink
		local equipLoc = link and select(9, getInfo(link))
		local slots = equipLoc and EQUIP_SLOTS[equipLoc]
		if slots then
			if GA and GA.Compare then
				local r = GA.Compare(link)
				if r and r.kind == "upgrade" and r.slot then record(r.slot, link, r.pct) end
			elseif wearableNow(bag, bslot) then
				local lvl = safe(getLevel, link)
				if type(lvl) == "number" and not isSecret(lvl) then
					for _, s in ipairs(slots) do
						local cur = slotItemLevel(s) or 0
						if lvl > cur then record(s, link, nil, lvl - cur) end
					end
				end
			end
		end
	end
end

local function upgradeLine(u)
	if u.pct then return ("Upgrade in your bags: %s (%+.0f%%)"):format(u.link, u.pct) end
	if u.gain then return ("Upgrade in your bags: %s (+%d item levels)"):format(u.link, u.gain) end
	return "Upgrade in your bags: " .. u.link
end

local function updateSlotBorder(button)
	if not button or not button.GetID then return end
	local slot = button:GetID()
	if not slot then return end
	if not F("gear") then
		if button.zydeBorder then button.zydeBorder:Hide() end
		return -- Blizzard's own border comes back after a /reload
	end
	local q = GetInventoryItemQuality("player", slot)
	if isSecret(q) then return end
	local up = bagUpgrades[slot]
	if not q then
		-- Empty slot: quiet gray, unless your bags hold something for it -
		-- then a red "!" (you can fix this right now).
		if not FLAG_EMPTY[slot] or (slot == 17 and mainHandIsTwoHanded()) then
			if button.zydeBorder then button.zydeBorder:Hide() end
			return
		end
		local f = getBorder(button)
		f.ilvl:Hide()
		f.arrow:Hide()
		if up then
			for _, tex in ipairs(f.edge) do tex:SetColorTexture(1, 0.2, 0.2, 0.6) end
			setGlow(f.glow, 1, 0.2, 0.2)
			showFlag(f, 1, 0.2, 0.2, "Empty - you have something for this slot in your bags: " .. up.link)
		else
			for _, tex in ipairs(f.edge) do tex:SetColorTexture(0.35, 0.35, 0.38, 0.5) end
			for _, tex in ipairs(f.glow) do tex:SetColorTexture(0, 0, 0, 0) end
			showFlag(f, nil)
		end
		f:Show()
		return
	end
	local f = getBorder(button)
	local r, g, b = qualityColor(q)
	for _, tex in ipairs(f.edge) do tex:SetColorTexture(r, g, b, 1) end
	setGlow(f.glow, r, g, b)
	f.arrow:SetShown(up ~= nil)
	f.upgradeText = up and upgradeLine(up) or nil

	local lvl = (not NO_ILVL_SLOTS[slot]) and slotItemLevel(slot)
	if lvl and lvl > 1 then
		f.ilvl:SetText(lvl)
		f.ilvl:SetTextColor(r, g, b)
		f.ilvl:Show()
		showFlag(f, gearFlag(slot, lvl))
	else
		f.ilvl:Hide()
		showFlag(f, nil)
	end
	f:Show()
end

-- Average item level of what you wear, in the header: "Level 17 Hunter · item level 16.8".
local function averageItemLevel()
	if GetAverageItemLevel then
		local _, equipped = safe(GetAverageItemLevel)
		if type(equipped) == "number" and not isSecret(equipped) and equipped > 0 then return equipped end
	end
	-- Our own count: the 16 slots that matter (a two-hander counts for both hands).
	local total, count = 0, 0
	for _, s in ipairs({ 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }) do
		if s ~= 18 or UnitClass and select(2, UnitClass("player")) == "HUNTER" then
			local lvl = slotItemLevel(s)
			if s == 17 and not lvl and mainHandIsTwoHanded() then lvl = slotItemLevel(16) end
			total, count = total + (lvl or 0), count + 1
		end
	end
	return count > 0 and total / count or nil
end

local ILVL_SUFFIX = "  ·  item level "
local function updateLevelText()
	if not (F("gear") and CharacterLevelText) then return end
	local text = CharacterLevelText:GetText()
	if type(text) ~= "string" or isSecret(text) then return end
	-- Take off our old number (the game doesn't always redraw the line), add the new one.
	local cut = text:find(ILVL_SUFFIX, 1, true)
	if cut then text = text:sub(1, cut - 1) end
	local avg = averageItemLevel()
	if avg then CharacterLevelText:SetText(("%s%s%.1f"):format(text, ILVL_SUFFIX, avg)) end
end
if PaperDollFrame_SetLevel then hooksecurefunc("PaperDollFrame_SetLevel", updateLevelText) end

local function updateAllGearBorders()
	if F("gear") then pcall(scanBagUpgrades) end
	for _, name in ipairs(GEAR_SLOTS) do
		updateSlotBorder(_G["Character" .. name .. "Slot"])
	end
	updateLevelText()
	-- The game's average can lag a moment behind a gear change: look again.
	C_Timer.After(0.5, updateLevelText)
end

if PaperDollItemSlotButton_Update then
	hooksecurefunc("PaperDollItemSlotButton_Update", updateSlotBorder)
end
ns.OnFeatureChanged(function(key) if key == "gear" then updateAllGearBorders() end end)

local gearEvents = CreateFrame("Frame")
gearEvents:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
gearEvents:RegisterEvent("GET_ITEM_INFO_RECEIVED")
gearEvents:RegisterEvent("PLAYER_LEVEL_UP")
gearEvents:RegisterEvent("PLAYER_LOGIN")
gearEvents:RegisterEvent("BAG_UPDATE_DELAYED")
gearEvents:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" and CharacterFrame then
		CharacterFrame:HookScript("OnShow", updateAllGearBorders)
	end
	-- Item info and bag changes only matter while the character window is open.
	if (event == "GET_ITEM_INFO_RECEIVED" or event == "BAG_UPDATE_DELAYED")
		and not (CharacterFrame and CharacterFrame:IsShown()) then return end
	-- Item info arrives in bursts (one event per item): redraw once, a moment after.
	if event == "GET_ITEM_INFO_RECEIVED" then
		if gearEvents.pending then return end
		gearEvents.pending = true
		C_Timer.After(0.2, function() gearEvents.pending = nil updateAllGearBorders() end)
		return
	end
	updateAllGearBorders()
end)

ns.newEdges, ns.placeEdges = newEdges, placeEdges
