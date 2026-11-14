-- ItemButton: a button for the usable quest item of your current quest (the "use this on ..." kind).
-- Click it, or bind a key in Key Bindings > AddOns > LevelPlanner. Alt+drag to move it.
-- It's a protected (secure) button so it may use items; the game only lets it change outside
-- combat, so a change during a fight waits until the fight ends.
local ADDON, zyde = ...
-- Part of Zyde_Forever since 2026-11-14: LevelPlanner keeps its own private table (zyde.LP) so its
-- names never clash with Zyde's.
zyde.LP = zyde.LP or {}
local ns = zyde.LP

local IB = {}
ns.ItemButton = IB

local BINDING = "CLICK LevelPlannerItemButton:LeftButton"
_G.BINDING_HEADER_LEVELPLANNER = "LevelPlanner"
_G["BINDING_NAME_" .. BINDING] = "Use quest item"

local btn
local currentItem
local pending = false

local function itemSpell(itemId)
	if C_Item and C_Item.GetItemSpell then return C_Item.GetItemSpell(itemId) end
	return GetItemSpell and GetItemSpell(itemId)
end

local function count(itemId)
	if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(itemId) end
	return GetItemCount and GetItemCount(itemId) or 0
end

-- Usable items in your bags that belong to a quest: [questId] = itemId
local function questItemsInBags()
	local out = {}
	local C = C_Container
	if not (C and C.GetContainerNumSlots and C.GetContainerItemID) then return out end
	for bag = 0, 4 do
		for slot = 1, (C.GetContainerNumSlots(bag) or 0) do
			local itemId = C.GetContainerItemID(bag, slot)
			if itemId and itemSpell(itemId) then
				local info = C.GetContainerItemQuestInfo and C.GetContainerItemQuestInfo(bag, slot)
				local qid = info and info.questID
				if qid and qid > 0 then out[qid] = out[qid] or itemId end
			end
		end
	end
	return out
end

-- Items Questie links to a quest (given at pick-up, needed to start, used for an objective).
local function questieItems(questId)
	local qo = ns.QuestSource.GetQuest(questId)
	if not qo then return {} end
	local list = {}
	if qo.sourceItemId then list[#list + 1] = qo.sourceItemId end
	if qo.SpellItemId then list[#list + 1] = qo.SpellItemId end
	for _, id in ipairs(qo.requiredSourceItems or {}) do list[#list + 1] = id end
	return list
end

-- The usable item for the first planned quests that need one (looks at the next few steps).
local function pickItem()
	if not ns.plan then return nil end
	local inBags = questItemsInBags()
	local seen, checked = {}, 0
	for _, s in ipairs(ns.plan.stops) do
		local qid = s.questId
		if type(qid) == "number" and not seen[qid] then
			seen[qid] = true
			checked = checked + 1
			if inBags[qid] then return inBags[qid] end
			for _, itemId in ipairs(questieItems(qid)) do
				if count(itemId) > 0 and itemSpell(itemId) then return itemId end
			end
			if checked >= 3 then break end
		end
	end
	return nil
end

local function savePos()
	local point, _, rel, x, y = btn:GetPoint()
	ns.char.itemButtonPos = { point, rel, x, y }
end

local function hotkeyText()
	local key = GetBindingKey and GetBindingKey(BINDING)
	btn.hotkey:SetText(key and GetBindingText and GetBindingText(key, "KEY_", true) or "")
end

function IB.Refresh()
	if not btn then return end
	if InCombatLockdown() then pending = true return end
	pending = false
	local itemId = (ns.cfg.itemButton ~= false) and pickItem() or nil
	if itemId ~= currentItem then
		currentItem = itemId
		if itemId then
			btn:SetAttribute("type", "item")
			btn:SetAttribute("item", "item:" .. itemId)
			btn.icon:SetTexture((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemId))
				or (GetItemIcon and GetItemIcon(itemId)) or "Interface\\Icons\\INV_Misc_QuestionMark")
		else
			btn:SetAttribute("type", nil)
			btn:SetAttribute("item", nil)
		end
	end
	btn:SetShown(itemId ~= nil)
	if itemId then
		local n = count(itemId)
		btn.count:SetText(n > 1 and n or "")
		hotkeyText()
	end
end

function IB.Init()
	btn = CreateFrame("Button", "LevelPlannerItemButton", UIParent, "SecureActionButtonTemplate")
	btn:SetSize(40, 40)
	local pos = ns.char and ns.char.itemButtonPos
	if pos then
		btn:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		btn:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
	end
	local down = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
	btn:RegisterForClicks(down and "AnyDown" or "AnyUp")
	btn:SetMovable(true)
	btn:RegisterForDrag("LeftButton")
	btn:SetScript("OnDragStart", function(self) if IsAltKeyDown() and not InCombatLockdown() then self:StartMoving() end end)
	btn:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() savePos() end)
	btn:SetClampedToScreen(true)

	btn.icon = btn:CreateTexture(nil, "ARTWORK")
	btn.icon:SetAllPoints()
	btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	local border = btn:CreateTexture(nil, "OVERLAY")
	border:SetPoint("TOPLEFT", -1, 1)
	border:SetPoint("BOTTOMRIGHT", 1, -1)
	border:SetColorTexture(0.35, 1, 0.55, 0.35)
	border:SetDrawLayer("BACKGROUND")
	btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	btn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

	btn.cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
	btn.cooldown:SetAllPoints()
	btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	btn.count:SetPoint("BOTTOMRIGHT", -2, 2)
	btn.hotkey = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
	btn.hotkey:SetPoint("TOPRIGHT", -2, -2)

	btn:SetScript("OnEnter", function(self)
		if not currentItem then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(currentItem)
		GameTooltip:AddLine("LevelPlanner: quest item for your current step. Alt+drag to move.", 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	btn:Hide()

	local f = CreateFrame("Frame")
	f:RegisterEvent("BAG_UPDATE_DELAYED")
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	f:RegisterEvent("BAG_UPDATE_COOLDOWN")
	f:RegisterEvent("UPDATE_BINDINGS")
	f:SetScript("OnEvent", function(_, event)
		if event == "BAG_UPDATE_COOLDOWN" then
			if currentItem then
				local getCd = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
				local start, dur, enable = getCd(currentItem)
				if start and dur then btn.cooldown:SetCooldown(start, dur) end
			end
		elseif event == "UPDATE_BINDINGS" then
			if currentItem then hotkeyText() end
		elseif event == "PLAYER_REGEN_ENABLED" then
			if pending then IB.Refresh() end
		else
			IB.Refresh()
		end
	end)
end
