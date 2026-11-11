-- Zyde_Forever: what in your bags is safe to sell to a vendor.
-- Every bag item gets a verdict, shown as a "Zyde:" line in its tooltip
-- (works with any bag addon):
--   Vendor it  - junk, or the auction house isn't worth it
--   Auction it - the AH pays clearly more AND it's likely to sell
--   Keep       - an exception (upgrade, on your bars, quest item, ...)
--   Check      - no auction data for a green-or-better item: look first
-- At a merchant, a panel beside the merchant window lists the "Vendor it"
-- items with a Sell button (12 at a time: all can be bought back).
-- At the auction house, a panel lists the "Auction it" items, best first,
-- with the price to post at; click one to put it in the sell slot.
-- Blizzard's bag windows: gold coin = vendor, gold-bordered auctioneer = auction.
--
-- Auction vs vendor (AHledger prices):
--   AH price  = the lower of the median and the cheapest listing (you'd have
--               to match it), minus the 5% auction house cut
--   sell odds = how many sell a day vs. how many are listed ahead of yours
--   expected  = odds x AH price - (1 - odds) x deposit lost if it doesn't sell
--   Auction only if expected beats vendor by 30% AND by enough to bother
--   (5 copper per character level), judged for all stacks of an item together.
--
-- /zyde vendor  - turn all of this on or off

local ADDON, ns = ...
local R -- ns.ItemRules, from ScrapList.lua

local AH_CUT = 0.05
local LISTING_HOURS = 48      -- plan for a 48-hour listing...
local DEPOSIT = 0.60          -- ...whose deposit is 60% of vendor price (15% per 12h), lost if unsold
local AH_MIN_RATIO = 1.3      -- auction must beat vendor by 30%...
-- ...and gain enough to bother: 5 copper per character level (50c at 10,
-- 1s at 20, 3s at 60), for all you carry of that item together.
local function minGain() return math.max(50, (UnitLevel("player") or 1) * 5) end
local UNKNOWN_ODDS = 0.4      -- sell odds when AHledger has no sales estimate
local SELL_BATCH = 12         -- the merchant's buyback holds 12

local COLORS = {
	vendor = { 0.35, 1, 0.35 },
	auction = { 1, 0.82, 0.2 },
	keep = { 0.55, 0.8, 1 },
	check = { 1, 0.55, 0.25 },
}
local LABEL = { vendor = "Vendor it", auction = "Auction it", keep = "Keep", check = "Check first" }

-- Equip location -> character slots it could replace.
local SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
	INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
	INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
	INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
	INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
	INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
	INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
local COSMETIC = { INVTYPE_BODY = true, INVTYPE_TABARD = true }

local function db()
	ZydeForeverDB = ZydeForeverDB or {}
	return ZydeForeverDB
end
local function on() return R and ns.F("vendor") end

local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local function itemLevel(link)
	local lvl = C_Item and C_Item.GetDetailedItemLevelInfo and ns.safe(C_Item.GetDetailedItemLevelInfo, link)
	if type(lvl) == "number" and not ns.isSecret(lvl) then return lvl end
	return select(4, getInfo(link)) or 0
end

---------------------------------------------------------------------------
-- Upgrades
---------------------------------------------------------------------------
-- Red lines in the item's tooltip mean you can't use it. "Requires Level N"
-- alone means you can't use it *yet*.
local LEVEL_PATTERN = ITEM_MIN_LEVEL and ("^" .. ITEM_MIN_LEVEL:gsub("%%d", "%%d+") .. "$")
-- "Requires First Aid (150)": a skill you can still raise, so also "not yet".
local SKILL_PATTERN = ITEM_MIN_SKILL and ("^" .. ITEM_MIN_SKILL:gsub("%(", "%%("):gsub("%)", "%%)")
	:gsub("%%s", ".+"):gsub("%%d", "%%d+") .. "$")

-- An item's tooltip lines, built once per bag scan (several checks below
-- read them; building a tooltip is the slow part). Wiped at each scan.
local tipCache = {} -- "bag:slot" -> tooltip data, or false
local function tooltipData(bag, slot)
	local key = bag .. ":" .. slot
	local data = tipCache[key]
	if data == nil then
		data = C_TooltipInfo and C_TooltipInfo.GetBagItem and ns.safe(C_TooltipInfo.GetBagItem, bag, slot) or false
		tipCache[key] = data
	end
	return data or nil
end

local function usability(bag, slot)
	local data = tooltipData(bag, slot)
	if not data or not data.lines then return "usable" end
	local levelOnly, other = false, false
	for _, line in ipairs(data.lines) do
		for _, side in ipairs({ { line.leftText, line.leftColor }, { line.rightText, line.rightColor } }) do
			local text, c = side[1], side[2]
			if c and type(text) == "string" and not ns.isSecret(text) and c.r and c.r > 0.95 and c.g < 0.2 and c.b < 0.2 then
				if (LEVEL_PATTERN and text:match(LEVEL_PATTERN)) or (SKILL_PATTERN and text:match(SKILL_PATTERN)) then
					levelOnly = true
				else
					other = true
				end
			end
		end
	end
	if other then return "unusable" end
	if levelOnly then return "later" end
	return "usable"
end

-- The armor type each class should wear: before level 40, and from 40 on.
-- Armor subclasses: 1 cloth, 2 leather, 3 mail, 4 plate.
local CLOTH, LEATHER, MAIL, PLATE = 1, 2, 3, 4
local ARMOR = {
	WARRIOR = { MAIL, PLATE }, PALADIN = { MAIL, PLATE },
	HUNTER = { LEATHER, MAIL }, SHAMAN = { LEATHER, MAIL },
	ROGUE = { LEATHER, LEATHER }, DRUID = { LEATHER, LEATHER },
	MAGE = { CLOTH, CLOTH }, PRIEST = { CLOTH, CLOTH }, WARLOCK = { CLOTH, CLOTH },
}
local ARMOR_NAMES = { "cloth", "leather", "mail", "plate" }

-- For body armor (not cloaks, rings, necks, trinkets, shields):
-- "wrong" (a lighter type than you should wear), "later" (the type you
-- switch to at 40, before you can wear it), or nil (fine).
local function armorFit(classID, subclassID, equipLoc)
	if classID ~= 4 or not ARMOR_NAMES[subclassID] or equipLoc == "INVTYPE_CLOAK" then return nil end
	local _, class = UnitClass("player")
	local tiers = ARMOR[class]
	if not tiers then return nil end
	local level = UnitLevel("player") or 1
	local want = level >= 40 and tiers[2] or tiers[1]
	if subclassID < want then return "wrong", ARMOR_NAMES[want] end
	if level < 40 and subclassID == tiers[2] and tiers[2] ~= tiers[1] then return "later", ARMOR_NAMES[tiers[2]] end
	return nil
end

-- "possible upgrade" / "future upgrade" reason, or nil.
local function upgradeReason(bag, slot, link, equipLoc, quality, classID, subclassID)
	local slots = SLOTS[equipLoc]
	if not slots then return nil end
	local fit, wanted = armorFit(classID, subclassID, equipLoc)
	if fit == "wrong" then return nil end -- e.g. leather for a warrior: not for you
	local use = usability(bag, slot)
	if fit == "later" then use = "later" end -- plate before 40: red now, yours later
	if use == "unusable" then return nil end
	local mine = itemLevel(link)
	local weakest = math.huge
	for _, s in ipairs(slots) do
		local eq = GetInventoryItemLink("player", s)
		local lvl = eq and itemLevel(eq) or 0
		if lvl < weakest then weakest = lvl end
	end
	if mine > weakest then
		if fit == "later" then return ("future upgrade (you wear %s from level 40)"):format(wanted) end
		return use == "later" and "future upgrade (you're not high enough level yet)" or "possible upgrade (higher item level than what you wear)"
	end
	return nil
end

---------------------------------------------------------------------------
-- Caster-only consumables (mana potions, water, wizard oils...) are no use
-- to classes without mana (warriors, rogues).
---------------------------------------------------------------------------
local function usesMana()
	local maxMana = Enum and Enum.PowerType and ns.safe(UnitPowerMax, "player", Enum.PowerType.Mana)
	if type(maxMana) == "number" and not ns.isSecret(maxMana) then return maxMana > 0 end
	local _, class = UnitClass("player")
	return class ~= "WARRIOR" and class ~= "ROGUE"
end

local function tooltipText(bag, slot)
	local data = tooltipData(bag, slot)
	local parts = {}
	for _, line in ipairs(data and data.lines or {}) do
		if type(line.leftText) == "string" and not ns.isSecret(line.leftText) then parts[#parts + 1] = line.leftText end
	end
	return table.concat(parts, "\n"):lower()
end

-- "Classes: Mage, Warlock" on the item, and your class isn't one of them.
local CLASSES_PATTERN = ITEM_CLASSES_ALLOWED and ("^" .. ITEM_CLASSES_ALLOWED:gsub("%%s", "(.+)") .. "$")
local function otherClassOnly(bag, slot)
	if not CLASSES_PATTERN then return false end
	local data = tooltipData(bag, slot)
	local myClass = UnitClass("player")
	for _, line in ipairs(data and data.lines or {}) do
		local text = line.leftText
		if type(text) == "string" and not ns.isSecret(text) then
			local list = text:match(CLASSES_PATTERN)
			if list then
				for cls in list:gmatch("[^,]+") do
					if cls:match("^%s*(.-)%s*$") == myClass then return false end
				end
				return true
			end
		end
	end
	return false
end

-- Its effect is all about mana or spells, with nothing for health.
local function casterOnly(bag, slot)
	local text = tooltipText(bag, slot)
	if text == "" or text:find("health", 1, true) then return false end
	return text:find("mana", 1, true) or text:find("spell damage", 1, true)
		or text:find("spell power", 1, true) or text:find("healing done by", 1, true) or false
end

---------------------------------------------------------------------------
-- The verdict for one bag slot
---------------------------------------------------------------------------
-- Returns a verdict table, nil (nothing to say), or "retry" (info not loaded).
local barIDs, barNames = {}, {}

-- total: how many of this item you carry across all stacks (the AH decision
-- is made for all of them together; 46 Linen Cloth, not each stack alone).
local function verdict(bag, slot, info, total)
	local id = info.itemID
	local link = info.hyperlink
	local name, _, quality, _, _, _, _, _, equipLoc, _, sellPrice, classID, subclassID = getInfo(link or id)
	if not name then return "retry" end
	local count = R.slotCount(bag, slot, info)
	total = math.max(total or count, count)
	local unit = (not info.hasNoValue and sellPrice) or 0
	local v = { link = link, itemID = id, count = count, unit = unit, vendorTotal = unit * count }
	local function keep(reason) v.kind, v.reason = "keep", reason return v end

	-- Exceptions: never suggest selling these.
	if R.NEVER[id] then return keep("a tool or item you use") end
	if barIDs[id] or barNames[name] then return keep("it's on your action bars") end
	if R.kept()[id] then return keep("you chose to keep it (/zyde scrapreset to undo)") end
	local quest = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
	if (quest and (quest.isQuestItem or quest.questID)) or classID == 12 then return keep("quest item") end
	if classID == 2 and subclassID == R.FISHING_POLE_SUBCLASS then return keep("fishing pole") end
	if unit <= 0 then return nil end -- vendors won't buy it anyway
	if info.hasLoot then return keep("it has loot inside - open it first") end
	local setInfo = C_Container.GetContainerItemEquipmentSetInfo and ns.safe(C_Container.GetContainerItemEquipmentSetInfo, bag, slot)
	if setInfo then return keep("part of an equipment set") end
	if (quality or 1) >= 4 then return keep("epic or better - your call") end
	if quality ~= 0 then
		if COSMETIC[equipLoc] then return keep("shirt or tabard (cosmetic)") end
		local up = upgradeReason(bag, slot, link, equipLoc, quality, classID, subclassID)
		if up then return keep(up) end
		-- Consumables: kept unless you can't use them (another class's item,
		-- red text in the tooltip, or caster-only and you have no mana).
		if classID == 0 then
			local useless = otherClassOnly(bag, slot) or usability(bag, slot) == "unusable"
				or (not usesMana() and casterOnly(bag, slot))
			if not useless then return keep("consumable you might use") end
		end
		if classID == 1 then return keep("a bag - check if it's bigger than yours") end
		if classID == 5 then return keep("reagent") end
		if classID == 6 or classID == 11 then return keep("ammo or quiver") end
		if classID == 9 then return keep("recipe - you or an alt may want to learn it") end
		if classID == 13 then return keep("key") end
	end

	-- Junk: always vendor.
	if quality == 0 then
		v.kind, v.reason = "vendor", "junk (gray)"
		return v
	end

	-- Soulbound: the auction house won't take it.
	if R.isBound(bag, slot) then
		v.kind, v.reason = "vendor", "soulbound, can't be auctioned, not an upgrade"
		return v
	end

	-- Auction or vendor?
	local p = AHledgerAPI and AHledgerAPI.GetPrice(id)
	if not p or not p.median or p.median <= 0 then
		if (quality or 1) <= 1 and classID ~= 7 then -- trade goods (cloth, ore...) usually have a market
			v.kind, v.reason = "vendor", "no auction market for it"
		else
			v.kind, v.reason = "check", "no auction data - look it up before selling"
		end
		return v
	end

	local price = p.median
	if p.minBuyout and p.minBuyout > 0 and p.minBuyout < price then price = p.minBuyout end
	local net = price * (1 - AH_CUT)
	local odds, demand
	if p.soldPerDay and p.soldPerDay > 0 then
		local ahead = (p.quantity or 0) / 2 + total -- roughly half the listings undercut you
		odds = math.min(0.95, p.soldPerDay * (LISTING_HOURS / 24) / math.max(1, ahead))
		demand = ("sells ~%s/day, %d listed"):format(p.soldPerDay >= 10 and ("%d"):format(p.soldPerDay)
			or ("%.1f"):format(p.soldPerDay), p.quantity or 0)
	elseif p.soldPerDay == 0 then
		odds, demand = 0.05, "hardly ever sells"
	else
		-- No sales estimate for this market: judge by how busy it is. Hundreds
		-- or thousands listed (cloth, ore) means a market that moves.
		local listed = p.quantity or 0
		odds = listed >= 1000 and 0.85 or listed >= 200 and 0.7 or listed >= 30 and 0.5 or UNKNOWN_ODDS
		demand = ("%d listed, sales unknown"):format(listed)
	end
	-- Decide for everything you carry of it; show this stack's share.
	local deposit = DEPOSIT * unit * total
	local expected = odds * net * total - (1 - odds) * deposit
	local vendorAll = unit * total
	local share = count / total
	v.total, v.expectedAll = total, expected
	v.ahNet, v.odds, v.demand, v.expected = net * count, odds, demand, expected * share
	v.postEach, v.deposit = math.floor(price), math.floor(deposit * share)

	if expected >= vendorAll * AH_MIN_RATIO and expected - vendorAll >= minGain() then
		v.kind, v.reason = "auction", demand
	else
		v.kind = "vendor"
		-- Show the numbers, so a surprising verdict explains itself.
		v.reason = ("%s (%s). All %d: AH ~%s after cut and risk (%d%% sells) vs vendor %s")
			:format(odds < 0.3 and "slow seller" or "auction pays too little more", demand, total,
				R.money(math.max(0, math.floor(expected))), math.floor(odds * 100 + 0.5), R.money(vendorAll))
	end
	return v
end

---------------------------------------------------------------------------
-- Bag scan
---------------------------------------------------------------------------
local bySlot, byLink, sellList, auctionList = {}, {}, {}, {}

local scanPending, retryPending = false, false
local waitingForInfo = false -- the last scan had items whose info wasn't loaded
local refreshMarks -- forward

local function scan()
	wipe(bySlot)
	wipe(byLink)
	wipe(sellList)
	wipe(auctionList)
	wipe(tipCache)
	waitingForInfo = false
	if not on() then return end
	barIDs, barNames = R.actionBarItems()
	local missing = false
	-- How many of each item across all stacks.
	local totals, inAuctionList = {}, {}
	for _, bag in ipairs(R.normalBags()) do
		for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID then
				local key = info.hyperlink or info.itemID
				totals[key] = (totals[key] or 0) + R.slotCount(bag, slot, info)
			end
		end
	end
	for _, bag in ipairs(R.normalBags()) do
		for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID then
				local v = verdict(bag, slot, info, totals[info.hyperlink or info.itemID])
				if v == "retry" then
					missing = true
				elseif v then
					v.bag, v.slot, v.icon = bag, slot, info.iconFileID
					bySlot[bag .. ":" .. slot] = v
					if v.link and not byLink[v.link] then byLink[v.link] = v end
					if v.kind == "vendor" then sellList[#sellList + 1] = v end
					-- One row per item at the AH: Max posts all its stacks together.
					local key = v.link or v.itemID
					if v.kind == "auction" and not inAuctionList[key] then
						inAuctionList[key] = true
						auctionList[#auctionList + 1] = v
					end
				end
			end
		end
	end
	-- Cheapest first in the sell list.
	table.sort(sellList, function(a, b) return a.vendorTotal < b.vendorTotal end)
	-- Most valuable first in the auction list.
	table.sort(auctionList, function(a, b) return a.expectedAll > b.expectedAll end)
	wipe(tipCache) -- only needed during the scan
	waitingForInfo = missing
	if missing and not retryPending then
		retryPending = true
		C_Timer.After(1, function() retryPending = false scan() refreshMarks() end)
	end
end

---------------------------------------------------------------------------
-- Tooltip line
---------------------------------------------------------------------------
local function addVerdict(tooltip, v)
	local c = COLORS[v.kind]
	local money = R.money
	local head = "Zyde: " .. LABEL[v.kind]
	if v.kind == "vendor" then
		head = head .. " - " .. money(v.vendorTotal)
	elseif v.kind == "auction" then
		head = head .. " - ~" .. money(math.floor(v.ahNet)) .. " (vendor " .. money(v.vendorTotal) .. ")"
	end
	tooltip:AddLine(head, c[1], c[2], c[3])
	if v.reason then tooltip:AddLine("   " .. v.reason, 0.7, 0.7, 0.7, true) end
	if v.kind == "auction" then
		tooltip:AddLine(("   Post at %s each, %dh. Listing costs ~%s (refunded if it sells).")
			:format(money(v.postEach), LISTING_HOURS, money(v.deposit)), 0.7, 0.7, 0.7, true)
		tooltip:AddLine(("   ~%d%% chance it sells; worth ~%s after costs and risk.")
			:format(math.floor(v.odds * 100 + 0.5), money(math.max(0, math.floor(v.expected)))), 0.7, 0.7, 0.7, true)
	end
	if v.ahNet and AHledgerAPI and AHledgerAPI.CREDIT then
		tooltip:AddLine("   " .. AHledgerAPI.CREDIT, 0.45, 0.45, 0.45)
	end
end

local function tooltipHook(tooltip)
	if not on() or tooltip ~= GameTooltip or not tooltip.GetItem then return end
	local _, link = tooltip:GetItem()
	local v = link and byLink[link]
	if v then addVerdict(tooltip, v) end
end

---------------------------------------------------------------------------
-- Blizzard's own bag windows: a gold coin on "Vendor it" items, an
-- auctioneer badge with a gold border on "Auction it" items
---------------------------------------------------------------------------
local MARK_TEX = {
	vendor = "Interface\\MoneyFrame\\UI-GoldIcon",
	auction = "Interface\\Minimap\\Tracking\\Auctioneer",
}
local marks = {}
local function markFor(button)
	local m = marks[button]
	if m then return m end
	m = CreateFrame("Frame", nil, button)
	m:SetAllPoints()
	m:SetFrameLevel(button:GetFrameLevel() + 4)
	m.icon = m:CreateTexture(nil, "OVERLAY", nil, 7)
	m.icon:SetSize(15, 15)
	m.icon:SetPoint("TOPRIGHT", -1, -1)
	m.edges = ns.newEdges(m, "OVERLAY", 6)
	ns.placeEdges(m.edges, m, 0, 2)
	for _, t in ipairs(m.edges) do t:SetColorTexture(1, 0.82, 0.2, 1) end
	marks[button] = m
	return m
end

refreshMarks = function()
	for _, m in pairs(marks) do m:Hide() end
	if not on() then return end
	pcall(R.eachBlizzardBagButton, function(button)
		local bag = button.GetBagID and button:GetBagID() or (button:GetParent() and button:GetParent():GetID())
		local v = bag and bySlot[bag .. ":" .. button:GetID()]
		if v and MARK_TEX[v.kind] then
			local m = markFor(button)
			m.icon:SetTexture(MARK_TEX[v.kind])
			for _, t in ipairs(m.edges) do t:SetShown(v.kind == "auction") end
			m:Show()
		end
	end)
end

---------------------------------------------------------------------------
-- Merchant panel
---------------------------------------------------------------------------
local panel = CreateFrame("Frame", "ZydeForeverVendor", UIParent, "BackdropTemplate")
panel:SetSize(200, 120)
panel:SetFrameStrata("HIGH")
panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
panel:SetBackdropColor(0.08, 0.08, 0.08, 0.92)
panel:SetBackdropBorderColor(0, 0, 0, 1)
panel:EnableMouse(true)
panel:Hide()

panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
panel.title:SetPoint("TOPLEFT", 8, -7)
panel.title:SetTextColor(0.35, 1, 0.35)

panel.total = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
panel.total:SetPoint("BOTTOMLEFT", 8, 10)

panel.sell = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
panel.sell:SetSize(80, 22)
panel.sell:SetPoint("BOTTOMRIGHT", -6, 5)

local ICON, PER_ROW, MAX_ICONS = 30, 6, 36
local tiles = {}

local function tile(i)
	if tiles[i] then return tiles[i] end
	local b = CreateFrame("Button", nil, panel)
	b:SetSize(ICON, ICON)
	local row, col = math.floor((i - 1) / PER_ROW), (i - 1) % PER_ROW
	b:SetPoint("TOPLEFT", 8 + col * (ICON + 3), -26 - row * (ICON + 3))
	b:RegisterForClicks("RightButtonUp")
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	b.count:SetPoint("BOTTOMRIGHT", -1, 1)
	b:SetScript("OnEnter", function(self)
		if not self.v then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetBagItem(self.v.bag, self.v.slot)
		GameTooltip:AddLine("Right-click: keep it, don't sell", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:SetScript("OnClick", function(self)
		if not self.v then return end
		R.kept()[self.v.itemID] = true
		GameTooltip:Hide()
		print("|cff66ccffZyde_Forever|r: keeping " .. (self.v.link or "item") .. " (/zyde scrapreset to undo)")
		scan() refreshMarks() panel:Refresh()
	end)
	tiles[i] = b
	return b
end

function panel:Refresh()
	if not (on() and MerchantFrame and MerchantFrame:IsShown()) then self:Hide() return end
	local n = math.min(#sellList, MAX_ICONS)
	local total = 0
	for _, v in ipairs(sellList) do total = total + v.vendorTotal end
	for i = 1, math.max(n, #tiles) do
		local b = tile(i)
		local v = sellList[i]
		if i <= n and v then
			b.v = v
			b.icon:SetTexture(v.icon)
			b.count:SetText(v.count > 1 and v.count or "")
			b:Show()
		else
			b.v = nil
			b:Hide()
		end
	end
	local rows = math.max(1, math.ceil(n / PER_ROW))
	self:SetSize(8 * 2 + PER_ROW * (ICON + 3), 26 + rows * (ICON + 3) + 34)
	self.title:SetText(#sellList == 0 and "Nothing to vendor" or ("Safe to vendor (%d)"):format(#sellList))
	self.total:SetText(#sellList > 0 and ("Total: " .. R.money(total)) or "")
	local batch = math.min(SELL_BATCH, #sellList)
	self.sell:SetText(batch > 0 and ("Sell " .. batch) or "Sell")
	self.sell:SetEnabled(batch > 0)
	self:ClearAllPoints()
	self:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 4, 0)
	self:Show()
end

-- Sells the cheapest stacks, up to 12 (all of them can be bought back),
-- re-checking each slot still holds the same item.
local selling = false
panel.sell:SetScript("OnClick", function()
	if selling or InCombatLockdown() then return end
	selling = true
	local queue = {}
	for i = 1, math.min(SELL_BATCH, #sellList) do queue[i] = sellList[i] end
	local i = 0
	local function step()
		i = i + 1
		local v = queue[i]
		if not v or not (MerchantFrame and MerchantFrame:IsShown()) then
			selling = false
			return
		end
		local info = C_Container.GetContainerItemInfo(v.bag, v.slot)
		if info and info.itemID == v.itemID and not info.isLocked then
			C_Container.UseContainerItem(v.bag, v.slot)
		end
		C_Timer.After(0.2, step)
	end
	step()
end)
panel.sell:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:AddLine("Sell the cheapest marked stacks")
	GameTooltip:AddLine("12 at a time, so every one can be bought back from the merchant.", 0.8, 0.8, 0.8, true)
	GameTooltip:Show()
end)
panel.sell:SetScript("OnLeave", function() GameTooltip:Hide() end)

---------------------------------------------------------------------------
-- Auction house panel: everything worth posting, best first.
-- Click a row to put that item in the auction house's sell slot.
---------------------------------------------------------------------------
local ROW_H, MAX_ROWS = 26, 14

local ah = CreateFrame("Frame", "ZydeForeverAuction", UIParent, "BackdropTemplate")
ah:SetSize(300, 60)
ah:SetFrameStrata("HIGH")
ah:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
ah:SetBackdropColor(0.08, 0.08, 0.08, 0.92)
ah:SetBackdropBorderColor(1, 0.82, 0.2, 0.8)
ah:EnableMouse(true)
ah:Hide()

ah.title = ah:CreateFontString(nil, "OVERLAY", "GameFontNormal")
ah.title:SetPoint("TOPLEFT", 8, -7)
ah.title:SetTextColor(1, 0.82, 0.2)
ah.hint = ah:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
ah.hint:SetPoint("BOTTOMLEFT", 8, 7)
ah.hint:SetText("Click: put in the sell slot   Right-click: keep it")

local function ahFrame()
	return (AuctionHouseFrame and AuctionHouseFrame:IsShown() and AuctionHouseFrame)
		or (AuctionFrame and AuctionFrame:IsShown() and AuctionFrame)
end

-- After the item lands in the sell slot, press the window's own Max button
-- so everything you carry is posted, not just one stack.
local function clickIfShown(button)
	if button and button.IsShown and button:IsShown() and (not button.IsEnabled or button:IsEnabled()) then
		return pcall(button.Click, button)
	end
	return false
end

local function postMax()
	-- Newer auction house: the sell frame's quantity box has a Max button.
	if AuctionHouseFrame and AuctionHouseFrame:IsShown() then
		for _, key in ipairs({ "CommoditiesSellFrame", "ItemSellFrame" }) do
			local sf = AuctionHouseFrame[key]
			if sf and sf:IsShown() then
				local qi = sf.QuantityInput
				if clickIfShown(qi and qi.MaxButton) then return end
				if sf.SetToMaxQuantity and pcall(sf.SetToMaxQuantity, sf) then return end
				if sf.GetMaxQuantity and qi and qi.SetQuantity then
					local ok, max = pcall(sf.GetMaxQuantity, sf)
					if ok and max then pcall(qi.SetQuantity, qi, max) return end
				end
			end
		end
		return
	end
	-- Older auction house: full stacks, and Max number of stacks.
	if AuctionFrame and AuctionFrame:IsShown() then
		clickIfShown(AuctionsStackSizeMaxButton)
		clickIfShown(AuctionsNumStacksMaxButton)
	end
end

local function postItem(v)
	if InCombatLockdown() then return end
	local info = C_Container.GetContainerItemInfo(v.bag, v.slot)
	if not info or info.itemID ~= v.itemID then return end
	local loc = ItemLocation and ItemLocation:CreateFromBagAndSlot(v.bag, v.slot)
	if loc and AuctionHouseFrame and AuctionHouseFrame:IsShown() and AuctionHouseFrame.SetPostItem then
		if pcall(AuctionHouseFrame.SetPostItem, AuctionHouseFrame, loc) then
			C_Timer.After(0.15, postMax)
			return
		end
	end
	ClearCursor()
	C_Container.PickupContainerItem(v.bag, v.slot)
	if AuctionFrame and AuctionFrame:IsShown() and ClickAuctionSellItemButton then
		if AuctionFrameTab3 and PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(AuctionFrame) ~= 3 then
			pcall(AuctionFrameTab3.Click, AuctionFrameTab3) -- the Auctions tab
		end
		pcall(ClickAuctionSellItemButton)
		C_Timer.After(0.15, postMax)
	end
end

local rows = {}
local function row(i)
	if rows[i] then return rows[i] end
	local r = CreateFrame("Button", nil, ah)
	r:SetSize(284, ROW_H - 2)
	r:SetPoint("TOPLEFT", 8, -26 - (i - 1) * ROW_H)
	r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	r.hl = r:CreateTexture(nil, "HIGHLIGHT")
	r.hl:SetAllPoints()
	r.hl:SetColorTexture(1, 0.82, 0.2, 0.12)
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(ROW_H - 4, ROW_H - 4)
	r.icon:SetPoint("LEFT")
	r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	r.count = r:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	r.count:SetPoint("BOTTOMRIGHT", r.icon, "BOTTOMRIGHT", 1, -1)
	r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, 0)
	r.name:SetWidth(150)
	r.name:SetJustifyH("LEFT")
	r.name:SetWordWrap(false)
	r.odds = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	r.odds:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 6, 0)
	r.price = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.price:SetPoint("RIGHT", -2, 0)
	r:SetScript("OnEnter", function(self)
		local v = self.v
		if not v then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetBagItem(v.bag, v.slot)
		-- Exact deposit from the game, when it can tell us (48 hours).
		local loc = ItemLocation and ItemLocation:CreateFromBagAndSlot(v.bag, v.slot)
		if loc and C_AuctionHouse and C_AuctionHouse.CalculateItemDeposit then
			local dep = ns.safe(C_AuctionHouse.CalculateItemDeposit, loc, 3, v.total or v.count)
			if type(dep) == "number" then
				GameTooltip:AddLine("Exact 48h listing cost: " .. R.money(dep), 1, 1, 1)
			end
		end
		GameTooltip:Show()
	end)
	r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	r:SetScript("OnClick", function(self, button)
		local v = self.v
		if not v then return end
		if button == "RightButton" then
			R.kept()[v.itemID] = true
			GameTooltip:Hide()
			print("|cff66ccffZyde_Forever|r: keeping " .. (v.link or "item") .. " (/zyde scrapreset to undo)")
			scan() refreshMarks() ah:Refresh()
		else
			postItem(v)
		end
	end)
	rows[i] = r
	return r
end

function ah:Refresh()
	local host = on() and ahFrame()
	if not host then self:Hide() return end
	local n = math.min(#auctionList, MAX_ROWS)
	local total = 0
	for _, v in ipairs(auctionList) do total = total + math.max(0, v.expectedAll) end
	for i = 1, math.max(n, #rows) do
		local r = row(i)
		local v = auctionList[i]
		if i <= n and v then
			r.v = v
			r.icon:SetTexture(v.icon)
			r.count:SetText((v.total or v.count) > 1 and (v.total or v.count) or "")
			r.name:SetText(v.link or "?")
			r.odds:SetFormattedText("%d%% sells - %s", math.floor(v.odds * 100 + 0.5), v.demand or "")
			r.price:SetText(R.money(v.postEach) .. " ea")
			r:Show()
		else
			r.v = nil
			r:Hide()
		end
	end
	self:SetHeight(26 + math.max(1, n) * ROW_H + 22)
	self.title:SetText(#auctionList == 0 and "Nothing worth auctioning"
		or ("Post on the AH (%d) - worth ~%s"):format(#auctionList, R.money(math.floor(total))))
	self:ClearAllPoints()
	self:SetPoint("TOPLEFT", host, "TOPRIGHT", 4, 0)
	self:Show()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function refreshAll()
	scan()
	refreshMarks()
	panel:Refresh()
	ah:Refresh()
end

local function refreshSoon()
	if scanPending then return end
	scanPending = true
	C_Timer.After(0.3, function() scanPending = false refreshAll() end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		R = ns.ItemRules
		if not R then return end
		for _, e in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "ACTIONBAR_SLOT_CHANGED",
			"MERCHANT_SHOW", "MERCHANT_CLOSED", "PLAYER_LEVEL_UP", "GET_ITEM_INFO_RECEIVED",
			"AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" }) do
			pcall(ev.RegisterEvent, ev, e)
		end
		if TooltipDataProcessor and Enum and Enum.TooltipDataType then
			TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, tooltipHook)
		else
			GameTooltip:HookScript("OnTooltipSetItem", tooltipHook)
		end
		for _, frame in ipairs({ ContainerFrameCombinedBags, ContainerFrame1 }) do
			if frame then frame:HookScript("OnShow", refreshSoon) end
		end
		refreshSoon()
		return
	end
	if event == "MERCHANT_CLOSED" then panel:Hide() return end
	if event == "AUCTION_HOUSE_CLOSED" then ah:Hide() return end
	-- Item info arrives in bursts at login and loading screens: only rescan
	-- when the last scan was actually waiting on some.
	if event == "GET_ITEM_INFO_RECEIVED" and not waitingForInfo then return end
	refreshSoon()
end)

ns.OnFeatureChanged(function(key) if key == "vendor" then refreshAll() end end)

ns.Vendor = {
	Toggle = function()
		ns.setFeature("vendor", not ns.featureWanted("vendor"))
		print("|cff66ccffZyde_Forever|r: vendor advice " .. (ns.F("vendor") and "on" or "off")
			.. (ns.featureBlocked("vendor") and (" (" .. ns.featureBlocked("vendor") .. ")") or ""))
	end,
}
