-- ItemButton: one button (and one key) for the quest item you need right now.
--   Use    - an item with a "Use:" (the "use this on ..." kind)
--   Equip  - an item a quest wants you to wear (Goggles of Gem Hunting for Sunken Treasure):
--            one press puts it on; Zyde remembers what was in that slot
--   Wear   - that quest is done (or you've left the area): one press puts your own gear back
-- Which item: your gear to put back first; then the next planned steps' items (as before);
-- then any quest in your log whose objectives aren't done, when you're near them (its planned
-- spots within about 250 yards, or its zone when the planner doesn't have it).
-- Click it, or bind a key in Key Bindings > Zyde Forever. Alt+drag to move it.
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
_G["BINDING_NAME_" .. BINDING] = "Use quest item"

local NEAR_YARDS = 250   -- an unplanned quest's item shows within this of its planned spots
local LEAVE_YARDS = 400  -- wearing a quest item this far from its quest's spots: time to put your gear back

local btn
local current -- { item = id, mode = "use" | "equip" | "wear", questId = id }
local pending = false

local function plain(v) if ns.isSecret(v) then return nil end return v end

local function itemSpell(itemId)
	if C_Item and C_Item.GetItemSpell then return plain(C_Item.GetItemSpell(itemId)) end
	return GetItemSpell and plain(GetItemSpell(itemId))
end

local function count(itemId)
	if C_Item and C_Item.GetItemCount then return plain(C_Item.GetItemCount(itemId)) or 0 end
	return GetItemCount and plain(GetItemCount(itemId)) or 0
end

local function equipLoc(itemId)
	local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	local _, _, _, loc = ns.safe(f, itemId)
	loc = plain(loc)
	return type(loc) == "string" and loc ~= "" and loc ~= "INVTYPE_NON_EQUIP_IGNORE" and loc or nil
end

local function worn(itemId)
	local f = (C_Item and C_Item.IsEquippedItem) or IsEquippedItem
	return f and plain(ns.safe(f, itemId)) == true
end

-- The inventory slot an item went into (after it's worn): 1-19, or nil.
local function slotOf(itemId)
	for slot = 1, 19 do
		if plain(GetInventoryItemID("player", slot)) == itemId then return slot end
	end
end

-- Quest items in your bags (the game marks them): [questId] = itemId
local function questItemsInBags()
	local out = {}
	local C = C_Container
	if not (C and C.GetContainerNumSlots and C.GetContainerItemID) then return out end
	for bag = 0, 4 do
		for slot = 1, (C.GetContainerNumSlots(bag) or 0) do
			local itemId = plain(C.GetContainerItemID(bag, slot))
			if itemId and (itemSpell(itemId) or equipLoc(itemId)) then
				local info = C.GetContainerItemQuestInfo and C.GetContainerItemQuestInfo(bag, slot)
				local qid = info and plain(info.questID)
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

-- The item a quest wants used or worn, and how: "use" or "equip". nil when you have none (or
-- you're already wearing it).
local function questItem(questId, inBags)
	local candidates = {}
	if inBags[questId] then candidates[1] = inBags[questId] end
	for _, id in ipairs(questieItems(questId)) do candidates[#candidates + 1] = id end
	for _, id in ipairs(candidates) do
		if count(id) > 0 then
			if itemSpell(id) then return id, "use" end
			if equipLoc(id) and not worn(id) then return id, "equip" end
		end
	end
end

-- Where a quest's objectives are, from the plan (objective stops' spots): a list of points.
local function questSpots(questId)
	local out = {}
	local plan = ns.plan
	for _, list in ipairs({ plan and plan.stops or {}, plan and plan.onWay or {} }) do
		for _, s in ipairs(list) do
			if s.questId == questId and s.kind == "objective" then
				for _, p in ipairs(s.points or {}) do out[#out + 1] = p end
			end
		end
	end
	return out
end

-- Yards from you to a quest's nearest planned spot; nil when the plan has none.
local function yardsTo(questId, here)
	local best
	for _, p in ipairs(questSpots(questId)) do
		local d = ns.Geo.Distance(here, p)
		if d and (not best or d < best) then best = d end
	end
	return best
end

-- Is the quest's zone the one you're in? (for quests the plan doesn't have)
local function inQuestZone(questId)
	local qo = ns.QuestSource.GetQuest(questId)
	local area = qo and qo.zoneOrSort
	if type(area) ~= "number" or area <= 0 then return false end
	local map = ns.Geo.UiMapForArea(area)
	local mine = C_Map.GetBestMapForUnit("player")
	return map ~= nil and mine == map
end

local function objectivesDone(entry)
	if not entry then return true end
	if entry.isComplete == 1 or entry.isComplete == true then return true end
	local objs = entry.objectives or {}
	if #objs == 0 then return false end
	for _, o in ipairs(objs) do
		if not o.finished then return false end
	end
	return true
end

----------------------------------------------------------------------------------------
-- Wearing a quest item: what it replaced, saved per character, so the button can put it back.
--   ns.char.questSwap = { item = questItem, slot = slot, prev = yourItemOrNil, questId = id }
----------------------------------------------------------------------------------------
local lastWorn = {} -- [slot] = itemId, from the last look (so we know what a swap replaced)
local function snapshotWorn()
	for slot = 1, 19 do lastWorn[slot] = plain(GetInventoryItemID("player", slot)) end
end

local equipFor -- questId of the item the button last offered to equip, with that item
local function noticeEquip()
	local swap = ns.char and ns.char.questSwap
	if swap then
		-- put back (or swapped some other way): done
		local nowIn = plain(GetInventoryItemID("player", swap.slot))
		if nowIn ~= swap.item then ns.char.questSwap = nil end
	elseif equipFor and worn(equipFor.item) then
		local slot = slotOf(equipFor.item)
		if slot then
			local prev = lastWorn[slot]
			if prev == equipFor.item then prev = nil end
			ns.char.questSwap = { item = equipFor.item, slot = slot, prev = prev, questId = equipFor.questId }
		end
	end
	snapshotWorn()
end

-- Your gear to put back, when the quest that wanted the swap no longer needs it.
local function wearBack(log, here)
	local swap = ns.char and ns.char.questSwap
	if not swap or not swap.prev then return nil end
	if not worn(swap.item) then return nil end
	if count(swap.prev) <= 0 then return nil end -- (sold, banked: nothing to put back)
	local entry = log[swap.questId]
	local done = not entry or objectivesDone(entry)
	if not done then
		local d = here and yardsTo(swap.questId, here)
		if not (d and d > LEAVE_YARDS) then return nil end -- still there, still needed
	end
	return swap.prev
end

----------------------------------------------------------------------------------------
-- What the button offers now
----------------------------------------------------------------------------------------
local function pick()
	if not ns.QuestSource then return nil end
	local log = ns.QuestSource.LogEntries() or {}
	local here = ns.Geo.PlayerPoint()
	local back = wearBack(log, here)
	if back then return { item = back, mode = "wear", questId = ns.char.questSwap.questId } end
	local inBags = questItemsInBags()

	-- 1. the next planned steps (as before)
	local seen, checked = {}, 0
	for _, s in ipairs(ns.plan and ns.plan.stops or {}) do
		local qid = s.questId
		if type(qid) == "number" and not seen[qid] then
			seen[qid] = true
			checked = checked + 1
			local id, mode = questItem(qid, inBags)
			-- (a quest not in your log yet - one an item starts - still gets its item)
			if id and not (log[qid] and objectivesDone(log[qid])) then return { item = id, mode = mode, questId = qid } end
			if checked >= 3 then break end
		end
	end

	-- 2. any quest in your log that still needs its item, when you're near it (nearest first)
	local best, bestD
	for qid, entry in pairs(log) do
		if not seen[qid] and not objectivesDone(entry) then
			local id, mode = questItem(qid, inBags)
			if id then
				local d = here and yardsTo(qid, here)
				local near = (d and d <= NEAR_YARDS) or (d == nil and inQuestZone(qid))
				if near then
					local rank = d or (NEAR_YARDS + 1)
					if not bestD or rank < bestD then best, bestD = { item = id, mode = mode, questId = qid }, rank end
				end
			end
		end
	end
	return best
end

local function itemName(itemId)
	local f = (C_Item and C_Item.GetItemNameByID) or (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local n = f and plain(ns.safe(f, itemId))
	return type(n) == "string" and n or nil
end

local MODE_LABEL = { use = "", equip = "Equip", wear = "Wear" }

local function savePos()
	local point, _, rel, x, y = btn:GetPoint()
	ns.char.itemButtonPos = { point, rel, x, y }
end

local function hotkeyText()
	local key = GetBindingKey and GetBindingKey(BINDING)
	btn.hotkey:SetText(key and GetBindingText and GetBindingText(key, "KEY_", true) or "")
end

local function same(a, b)
	if not a or not b then return a == b end
	return a.item == b.item and a.mode == b.mode
end

function IB.Refresh()
	if not btn then return end
	if InCombatLockdown() then pending = true return end
	pending = false
	local want = (ns.cfg.itemButton ~= false) and pick() or nil
	if not same(want, current) then
		current = want
		equipFor = (want and want.mode == "equip") and want or nil
		if not want then
			btn:SetAttribute("type", nil)
			btn:SetAttribute("item", nil)
			btn:SetAttribute("macrotext", nil)
		elseif want.mode == "use" then
			btn:SetAttribute("macrotext", nil)
			btn:SetAttribute("type", "item")
			btn:SetAttribute("item", "item:" .. want.item)
		else
			-- Wearing is /equip (one press, out of combat). The name works best; the id when the
			-- name isn't loaded yet.
			btn:SetAttribute("item", nil)
			btn:SetAttribute("type", "macro")
			btn:SetAttribute("macrotext", "/equip " .. (itemName(want.item) or ("item:" .. want.item)))
		end
		if want then
			btn.icon:SetTexture((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(want.item))
				or (GetItemIcon and GetItemIcon(want.item)) or "Interface\\Icons\\INV_Misc_QuestionMark")
		end
	end
	btn:SetShown(want ~= nil)
	if want then
		local n = count(want.item)
		btn.count:SetText(want.mode == "use" and n > 1 and n or "")
		btn.mode:SetText(MODE_LABEL[want.mode] or "")
		if want.mode == "wear" then btn.mode:SetTextColor(0.6, 0.85, 1) else btn.mode:SetTextColor(1, 0.82, 0.2) end
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
	-- "Equip" / "Wear" under the icon (nothing for a plain use).
	btn.mode = btn:CreateFontString(nil, "OVERLAY")
	if not btn.mode:SetFont("Fonts\\ARIALN.TTF", 11, "OUTLINE") then btn.mode:SetFontObject("GameFontNormalSmall") end
	btn.mode:SetPoint("TOP", btn, "BOTTOM", 0, -2)

	btn:SetScript("OnEnter", function(self)
		if not current then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(current.item)
		local qo = current.questId and ns.QuestSource.GetQuest(current.questId)
		local quest = qo and qo.name or "your quest"
		if current.mode == "equip" then
			GameTooltip:AddLine("Click: put it on for " .. quest .. ". The button puts your own gear back once you're done.", 1, 0.82, 0.2, true)
		elseif current.mode == "wear" then
			GameTooltip:AddLine("Click: put this back on - " .. quest .. " doesn't need the quest item any more.", 0.6, 0.85, 1, true)
		else
			GameTooltip:AddLine("Click: use it for " .. quest .. ".", 1, 0.82, 0.2, true)
		end
		GameTooltip:AddLine("Alt+drag to move.", 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	btn:Hide()
	snapshotWorn()

	local f = CreateFrame("Frame")
	for _, e in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED", "BAG_UPDATE_COOLDOWN", "UPDATE_BINDINGS",
		"PLAYER_EQUIPMENT_CHANGED", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "QUEST_LOG_UPDATE" }) do
		pcall(f.RegisterEvent, f, e)
	end
	local queued = false
	local function soon()
		if queued then return end
		queued = true
		C_Timer.After(0.3, function() queued = false IB.Refresh() end)
	end
	f:SetScript("OnEvent", function(_, event)
		if event == "BAG_UPDATE_COOLDOWN" then
			if current and current.mode == "use" then
				local getCd = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
				local start, dur = getCd(current.item)
				if start and dur then btn.cooldown:SetCooldown(start, dur) end
			end
		elseif event == "UPDATE_BINDINGS" then
			if current then hotkeyText() end
		elseif event == "PLAYER_REGEN_ENABLED" then
			if pending then IB.Refresh() end
		elseif event == "PLAYER_EQUIPMENT_CHANGED" then
			noticeEquip()
			soon()
		else
			soon()
		end
	end)
	-- You walk toward (or away from) a quest's spot without any event: look every few seconds.
	if C_Timer and C_Timer.NewTicker then
		C_Timer.NewTicker(3, function()
			if not InCombatLockdown() and ns.ready then IB.Refresh() end
		end)
	end
end
