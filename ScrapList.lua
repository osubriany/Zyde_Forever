-- Zyde_Forever: "scrap first" when your bags are full.
-- When every normal bag slot is used, a small window shows the 3 least
-- valuable stacks in your bags with big 1 / 2 / 3 badges and their value.
--   value = stack size x the higher of: vendor price, auction price
--   (auction price from AHledger, only for items you could still sell there)
-- Quest items, the Hearthstone and items with no known value are never listed.
-- The same items get a "Scrap first #N" tooltip line, and a red border with
-- the number on Blizzard's own bag buttons. Click an item in the window to
-- pick it up, then drop it outside your bags to destroy it.
--
-- Off when LootTriage is installed and enabled (it already does this).
-- /zyde scrap      - turn it on or off
-- /zyde scraptest  - show the window now, even with bags not full

local ADDON, ns = ...

local NEVER = {
	[6948] = true,  -- Hearthstone
	-- Profession tools
	[2901] = true,  -- Mining Pick
	[5956] = true,  -- Blacksmith Hammer
	[7005] = true,  -- Skinning Knife
	[6219] = true,  -- Arclight Spanner
	[10498] = true, -- Gyromatic Micro-Adjustor
	[4471] = true,  -- Flint and Tinder
	[5060] = true,  -- Thieves' Tools
	[9149] = true,  -- Philosopher's Stone
	[6218] = true, [6339] = true, [11130] = true, [11145] = true, [16207] = true, -- Runed rods
	[6256] = true, [6365] = true, [6366] = true, [6367] = true, [12225] = true,
	[19022] = true, [19970] = true, -- Fishing poles
}
local FISHING_POLE_SUBCLASS = 20 -- weapon class 2, subclass "Fishing Poles"
local BADGE_COLORS = { { 1, 0.25, 0.2 }, { 1, 0.55, 0.2 }, { 1, 0.8, 0.25 } }

local active = false   -- false while LootTriage handles this
local testing = false  -- /zyde scraptest
local ranked = {}      -- { {bag, slot, link, value, icon, count}, ... } cheapest first
local rankBySlot = {}  -- "bag:slot" -> rank

local function db()
	ZydeForeverDB = ZydeForeverDB or {}
	return ZydeForeverDB
end

local function enabled() return active and ns.F("scrap") end

local function money(c)
	if GetMoneyString then return GetMoneyString(c, true) end
	if GetCoinTextureString then return GetCoinTextureString(c) end
	return ("%dc"):format(c)
end

---------------------------------------------------------------------------
-- Bag scan and pricing
---------------------------------------------------------------------------
local function normalBags()
	local last = NUM_BAG_SLOTS or 4
	local bags = {}
	for bag = 0, last do bags[#bags + 1] = bag end
	return bags
end

local function freeSlots()
	local free = 0
	for _, bag in ipairs(normalBags()) do
		local n, bagType = C_Container.GetContainerNumFreeSlots(bag)
		if (bagType or 0) == 0 then free = free + (n or 0) end
	end
	return free
end

local function isBound(bag, slot)
	if not (C_Item and C_Item.IsBound and ItemLocation) then return false end
	local ok, loc = pcall(ItemLocation.CreateFromBagAndSlot, ItemLocation, bag, slot)
	if not ok or not loc then return false end
	local ok2, bound = pcall(C_Item.IsBound, loc)
	return ok2 and bound == true
end

local function auctionPrice(itemID)
	if not AHledgerAPI then return nil end
	return AHledgerAPI.GetMedian(itemID)
end

-- Items you've put on an action bar (directly or in a macro): you use them.
local function actionBarItems()
	local ids, names = {}, {}
	local function secret(v) return ns.isSecret(v) end
	for slot = 1, 180 do
		local kind, id = ns.safe(GetActionInfo, slot)
		if not secret(kind) and not secret(id) then
			if kind == "item" and id then
				ids[tonumber(id) or id] = true
			elseif kind == "macro" and id and GetMacroItem then
				local name, link = ns.safe(GetMacroItem, id)
				if type(name) == "string" and not secret(name) then names[name] = true end
				local mid = type(link) == "string" and not secret(link) and tonumber(link:match("item:(%d+)"))
				if mid then ids[mid] = true end
			end
		end
	end
	return ids, names
end
local barIDs, barNames = {}, {}

-- Items you chose to keep (right-click in the scrap window).
local function kept() db().scrapKeep = db().scrapKeep or {} return db().scrapKeep end

-- Value of one item from a bag slot in copper, or nil to never suggest it.
-- Returns value, needsRetry (item info not loaded yet).
local function slotValue(bag, slot, info)
	local id = info.itemID
	if not id or NEVER[id] or barIDs[id] or kept()[id] then return nil end
	local quest = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
	if quest and (quest.isQuestItem or quest.questID) then return nil end

	local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local name, _, _, _, _, _, _, _, _, _, sellPrice, classID, subclassID = getInfo(info.hyperlink or id)
	if not name then return nil, true end
	if classID == 12 then return nil end -- quest class
	if classID == 6 or classID == 11 then return nil end -- ammo, quivers and ammo pouches
	if classID == 2 and subclassID == FISHING_POLE_SUBCLASS then return nil end
	if barNames[name] then return nil end -- used in a macro on your bars

	local unit = (not info.hasNoValue and sellPrice) or 0
	local ah = not isBound(bag, slot) and auctionPrice(id)
	if ah and ah > unit then unit = ah end
	if unit <= 0 then return nil end -- no known value: could be important
	return unit -- per item; the caller multiplies by how many you have
end

-- How many are in a slot (some clients name the field differently).
local function slotCount(bag, slot, info)
	local n = tonumber(info.stackCount) or tonumber(info.count)
	if not n and GetContainerItemInfo then
		n = select(2, GetContainerItemInfo(bag, slot))
	end
	return tonumber(n) or 1
end

local retryPending = false
local refresh -- forward

local function rank()
	wipe(ranked)
	wipe(rankBySlot)
	barIDs, barNames = actionBarItems()
	-- Group every stack of the same item: 46 Linen Cloth in three stacks is
	-- valued as 46, not as each stack on its own.
	local byItem, all, missing = {}, {}, false
	for _, bag in ipairs(normalBags()) do
		-- Only ordinary bags: a quiver or ammo pouch only holds ammo, so
		-- deleting from it never frees a slot for loot.
		local _, bagType = C_Container.GetContainerNumFreeSlots(bag)
		local slots = (tonumber(bagType) or 0) == 0 and C_Container.GetContainerNumSlots(bag) or 0
		for slot = 1, (slots or 0) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID then
				local unit, retry = slotValue(bag, slot, info)
				if retry then missing = true end
				if unit then
					local key = info.hyperlink or info.itemID
					local count = slotCount(bag, slot, info)
					local e = byItem[key]
					if not e then
						e = { link = info.hyperlink, itemID = info.itemID, unit = unit, icon = info.iconFileID, count = 0, slots = {} }
						byItem[key] = e
						all[#all + 1] = e
					end
					e.count = e.count + count
					e.slots[#e.slots + 1] = { bag = bag, slot = slot, count = count }
				end
			end
		end
	end
	for _, e in ipairs(all) do
		e.value = e.unit * e.count
		-- Clicking picks up the smallest stack first.
		table.sort(e.slots, function(a, b) return a.count < b.count end)
		e.bag, e.slot = e.slots[1].bag, e.slots[1].slot
	end
	table.sort(all, function(a, b)
		if a.value ~= b.value then return a.value < b.value end
		return a.bag * 100 + a.slot < b.bag * 100 + b.slot
	end)
	for i = 1, math.min(3, #all) do
		ranked[i] = all[i]
		for _, s in ipairs(all[i].slots) do rankBySlot[s.bag .. ":" .. s.slot] = i end
	end
	-- Some item info wasn't cached yet: try again shortly.
	if missing and not retryPending then
		retryPending = true
		C_Timer.After(1, function() retryPending = false refresh() end)
	end
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local SIZE, GAP = 40, 10

local win = CreateFrame("Frame", "ZydeForeverScrap", UIParent, "BackdropTemplate")
win:SetSize(3 * SIZE + 4 * GAP, SIZE + 46)
win:SetFrameStrata("MEDIUM")
win:SetClampedToScreen(true)
win:SetMovable(true)
win:EnableMouse(true)
win:RegisterForDrag("LeftButton")
win:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
win:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
win:SetBackdropBorderColor(0, 0, 0, 1)
win:Hide()

win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
win.title:SetPoint("TOP", 0, -5)
win.title:SetTextColor(1, 0.35, 0.3)
win.title:SetText("Bags full - scrap first")

win:SetScript("OnDragStart", function(self) self:StartMoving() end)
win:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local point, _, rel, x, y = self:GetPoint()
	db().scrapPos = { point = point, rel = rel, x = x, y = y }
end)

local function placeWin()
	local p = db().scrapPos or { point = "BOTTOMRIGHT", rel = "BOTTOMRIGHT", x = -300, y = 180 }
	win:ClearAllPoints()
	win:SetPoint(p.point, UIParent, p.rel or p.point, p.x, p.y)
end

local function makeSlot(i)
	local b = CreateFrame("Button", nil, win)
	b:SetSize(SIZE, SIZE)
	b:SetPoint("TOPLEFT", GAP + (i - 1) * (SIZE + GAP), -20)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	b.border = b:CreateTexture(nil, "BACKGROUND")
	b.border:SetPoint("TOPLEFT", -2, 2)
	b.border:SetPoint("BOTTOMRIGHT", 2, -2)
	b.border:SetColorTexture(unpack(BADGE_COLORS[i]))

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	b.count:SetPoint("BOTTOMRIGHT", -2, 2)

	b.badge = b:CreateFontString(nil, "OVERLAY")
	b.badge:SetFont(STANDARD_TEXT_FONT, 20, "THICKOUTLINE")
	b.badge:SetPoint("TOPLEFT", -4, 6)
	b.badge:SetText(i)
	b.badge:SetTextColor(unpack(BADGE_COLORS[i]))

	b.value = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.value:SetPoint("TOP", b, "BOTTOM", 0, -4)
	b.value:SetWidth(SIZE + GAP)
	b.value:SetWordWrap(false)

	local pulse = b:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local a = pulse:CreateAnimation("Alpha")
	a:SetTarget(b.border)
	a:SetFromAlpha(1)
	a:SetToAlpha(0.3)
	a:SetDuration(0.8)
	a:SetSmoothing("IN_OUT")
	b:SetScript("OnShow", function() pulse:Play() end)
	b:SetScript("OnHide", function() pulse:Stop() end)

	b:SetScript("OnEnter", function(self)
		local e = ranked[i]
		if not e then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetBagItem(e.bag, e.slot)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(("You have %d in %d stack%s: %s total (%s each)"):format(e.count, #e.slots,
			#e.slots == 1 and "" or "s", money(e.value), money(e.unit)), 1, 1, 1, true)
		GameTooltip:AddLine("Click to pick it up, then drop it outside your bags to destroy it.", 0.7, 0.7, 0.7, true)
		GameTooltip:AddLine("Right-click: keep this item, never suggest it again.", 0.7, 0.7, 0.7, true)
		if AHledgerAPI and AHledgerAPI.CREDIT then GameTooltip:AddLine(AHledgerAPI.CREDIT, 0.5, 0.5, 0.5) end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:SetScript("OnClick", function(_, button)
		local e = ranked[i]
		if not e then return end
		if button == "RightButton" then
			kept()[e.itemID] = true
			GameTooltip:Hide()
			print("|cff66ccffZyde_Forever|r: " .. (e.link or "item") .. " won't be suggested again (/zyde scrapreset to undo)")
			refresh()
		elseif not InCombatLockdown() then
			C_Container.PickupContainerItem(e.bag, e.slot)
		end
	end)
	return b
end

local slots = { makeSlot(1), makeSlot(2), makeSlot(3) }

local function drawWin(show)
	if not show or #ranked == 0 then win:Hide() return end
	for i, b in ipairs(slots) do
		local e = ranked[i]
		if e then
			b.icon:SetTexture(e.icon)
			b.count:SetText(e.count > 1 and e.count or "")
			b.value:SetText(money(e.value))
			b:Show()
		else
			b:Hide()
		end
	end
	win:SetWidth(math.max(#ranked * SIZE + (#ranked + 1) * GAP, win.title:GetStringWidth() + 16))
	win:Show()
end

---------------------------------------------------------------------------
-- Blizzard's own bag windows: red border + number on the ranked items
---------------------------------------------------------------------------
local overlays = {}

local function overlayFor(button)
	local o = overlays[button]
	if o then return o end
	o = CreateFrame("Frame", nil, button)
	o:SetAllPoints()
	o:SetFrameLevel(button:GetFrameLevel() + 5)
	o.edges = ns.newEdges(o, "OVERLAY", 7)
	ns.placeEdges(o.edges, o, 0, 2)
	o.num = o:CreateFontString(nil, "OVERLAY")
	o.num:SetFont(STANDARD_TEXT_FONT, 16, "THICKOUTLINE")
	o.num:SetPoint("TOPLEFT", 1, -1)
	overlays[button] = o
	return o
end

local function eachBlizzardBagButton(fn)
	local frames = { ContainerFrameCombinedBags }
	for i = 1, (NUM_CONTAINER_FRAMES or 13) do frames[#frames + 1] = _G["ContainerFrame" .. i] end
	for _, frame in ipairs(frames) do
		if frame and frame:IsShown() then
			if frame.EnumerateValidItems then
				for _, button in frame:EnumerateValidItems() do fn(button) end
			else
				local name = frame:GetName()
				for j = 1, 36 do
					local button = name and _G[name .. "Item" .. j]
					if button then fn(button) end
				end
			end
		end
	end
end

local function markBlizzardBags(show)
	for _, o in pairs(overlays) do o:Hide() end
	if not show then return end
	pcall(eachBlizzardBagButton, function(button)
		local bag = button.GetBagID and button:GetBagID() or (button:GetParent() and button:GetParent():GetID())
		local r = bag and rankBySlot[bag .. ":" .. button:GetID()]
		if r then
			local o = overlayFor(button)
			for _, t in ipairs(o.edges) do t:SetColorTexture(unpack(BADGE_COLORS[r])) end
			o.num:SetText(r)
			o.num:SetTextColor(unpack(BADGE_COLORS[r]))
			o:Show()
		end
	end)
end

---------------------------------------------------------------------------
-- Tooltip line: "Scrap first #1"
---------------------------------------------------------------------------
local showing = false
local function tooltipLine(tooltip)
	if not showing or not tooltip.GetItem then return end
	local _, link = tooltip:GetItem()
	if not link then return end
	for i, e in ipairs(ranked) do
		if e.link == link then
			tooltip:AddLine(("Scrap first #%d  (%s)"):format(i, money(e.value)), unpack(BADGE_COLORS[i]))
			return
		end
	end
end

---------------------------------------------------------------------------
-- Updates
---------------------------------------------------------------------------
refresh = function()
	if not enabled() then
		showing = false
		win:Hide()
		markBlizzardBags(false)
		return
	end
	showing = testing or freeSlots() == 0
	if showing then rank() end
	drawWin(showing)
	markBlizzardBags(showing)
end

local pending = false
local function refreshSoon()
	if pending then return end
	pending = true
	C_Timer.After(0.2, function() pending = false refresh() end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
		active = not (loaded and loaded("LootTriage"))
		if not active then return end -- LootTriage does this already
		placeWin()
		for _, e in ipairs({ "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", "PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED" }) do
			pcall(ev.RegisterEvent, ev, e)
		end
		if TooltipDataProcessor and Enum and Enum.TooltipDataType then
			TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, tooltipLine)
		else
			GameTooltip:HookScript("OnTooltipSetItem", tooltipLine)
		end
		-- Re-mark Blizzard's bag windows whenever one opens.
		for _, frame in ipairs({ ContainerFrameCombinedBags, ContainerFrame1 }) do
			if frame then frame:HookScript("OnShow", refreshSoon) end
		end
		refreshSoon()
		return
	end
	if event == "GET_ITEM_INFO_RECEIVED" and not showing then return end
	refreshSoon()
end)

ns.OnFeatureChanged(function(key) if key == "scrap" then refresh() end end)

-- Shared with VendorList.lua (these rules apply even while LootTriage is on).
ns.ItemRules = {
	NEVER = NEVER,
	FISHING_POLE_SUBCLASS = FISHING_POLE_SUBCLASS,
	actionBarItems = actionBarItems,
	kept = kept,
	isBound = isBound,
	slotCount = slotCount,
	normalBags = normalBags,
	money = money,
	eachBlizzardBagButton = eachBlizzardBagButton,
}

ns.Scrap = {
	Toggle = function()
		if not active then
			print("|cff66ccffZyde_Forever|r: scrap list is off because LootTriage is installed and enabled (it does the same job)")
			return
		end
		ns.setFeature("scrap", not ns.featureWanted("scrap"))
		print("|cff66ccffZyde_Forever|r: scrap list " .. (ns.F("scrap") and "on" or "off"))
	end,
	ResetKeep = function()
		db().scrapKeep = nil
		print("|cff66ccffZyde_Forever|r: scrap list: items you chose to keep can be suggested again")
		refresh()
	end,
	Test = function()
		if not active then
			print("|cff66ccffZyde_Forever|r: scrap list is off because LootTriage is installed and enabled")
			return
		end
		testing = not testing
		print("|cff66ccffZyde_Forever|r: scrap list preview " .. (testing and "on" or "off"))
		refresh()
	end,
}
