-- Zyde_Forever: a small draggable bar.
-- One line: where you are, gold, bag space, the reagent bag, thrown durability or ammo, then gear durability.
-- Travel opens a second line: steps, yards swum, yards ridden, and jumps.
-- Mining, once that profession is learned, opens a line for each ore.
-- Herbalism does the same for herbs. Both can be open at once, so the bar
-- can be four lines. Counts are bags and bank. Ctrl+click a line pastes it.
-- Drag it with the left mouse button. Turn it off in /zyde.

local ADDON, ns = ...

local isSecret, safe = ns.isSecret, ns.safe
local FONT = "Fonts\\ARIALN.TTF"
local GOLD, SILVER, COPPER = "ffffd100", "ffc7c7cf", "ffeda55f"

local INV_AMMO, INV_RANGED = 0, 18
local WEAPON, PROJECTILE = 2, 6
local BOW, GUN, THROWN, CROSSBOW = 2, 3, 16, 18
local ARROW, BULLET = 2, 3
local AMMO_FOR = { [BOW] = ARROW, [CROSSBOW] = ARROW, [GUN] = BULLET }

local function plain(v)
	-- A secret must be recognised before any comparison. Comparing it throws.
	if isSecret(v) or v == nil then return nil end
	return v
end

local function on() return ns.F("infoBar") end

local function font(fs, size)
	if not fs:SetFont(FONT, size, "OUTLINE") then fs:SetFontObject("GameFontNormalSmall") end
end

---------------------------------------------------------------------------
-- The bar
---------------------------------------------------------------------------
local bar = CreateFrame("Frame", "ZydeForeverInfo", UIParent)
bar:SetHeight(22)
bar:SetFrameStrata("MEDIUM")
bar:SetClampedToScreen(true)
bar:SetMovable(true)
bar:EnableMouse(true)
bar:RegisterForDrag("LeftButton")
bar:Hide()

bar.bg = bar:CreateTexture(nil, "BACKGROUND")
bar.bg:SetAllPoints()
bar.bg:SetColorTexture(0.07, 0.07, 0.07, 0.9)
bar.edges = ns.newEdges(bar, "OVERLAY", 1)
ns.placeEdges(bar.edges, bar, -1, 1)
for _, t in ipairs(bar.edges) do t:SetColorTexture(0, 0, 0, 0.95) end

local function piece(icon, crop)
	local f = CreateFrame("Frame", nil, bar)
	f:SetHeight(22)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetSize(14, 14)
	f.icon:SetPoint("LEFT", 0, 0)
	f.icon:SetTexture(icon)
	if crop ~= false then f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
	f.text = f:CreateFontString(nil, "OVERLAY")
	font(f.text, 12)
	f.text:SetPoint("LEFT", f.icon, "RIGHT", 4, 0)
	f.text:SetTextColor(1, 0.84, 0.35)
	f:Hide()
	return f
end

local loc = piece("Interface\\Icons\\INV_Misc_Map_01")
local gold = piece("Interface\\MoneyFrame\\UI-GoldIcon", false)
local bags = piece("Interface\\Icons\\INV_Misc_Bag_08")
local reagents = piece("Interface\\Icons\\INV_Misc_Bag_10")
local ranged = piece("Interface\\Icons\\INV_ThrowingKnife_02")
local durability = piece("Interface\\Icons\\INV_Hammer_20")
local steps = piece("Interface\\Icons\\INV_Boots_08")
local swum = piece("Interface\\Icons\\Ability_Druid_AquaticForm")
local ridden = piece("Interface\\Icons\\Ability_Mount_RidingHorse")
local jumps = piece("Interface\\Icons\\Spell_Magic_FeatherFall")

-- Every ore from a vein, in the order you learn to mine them.
local ORES = {
	{ id = 2770, name = "Copper" },
	{ id = 2771, name = "Tin" },
	{ id = 2775, name = "Silver" },
	{ id = 2772, name = "Iron" },
	{ id = 2776, name = "Gold" },
	{ id = 3858, name = "Mithril" },
	{ id = 7911, name = "Truesilver" },
	{ id = 10620, name = "Thorium" },
	{ id = 11370, name = "Dark Iron" },
}
-- Herbs in the order you learn to pick them. Same list the node glow knows.
local HERB_ITEMS = {
	{ id = 2447, name = "Peacebloom" },
	{ id = 765, name = "Silverleaf" },
	{ id = 2449, name = "Earthroot" },
	{ id = 785, name = "Mageroyal" },
	{ id = 2450, name = "Briarthorn" },
	{ id = 3820, name = "Stranglekelp" },
	{ id = 2453, name = "Bruiseweed" },
	{ id = 3355, name = "Wild Steelbloom" },
	{ id = 3369, name = "Grave Moss" },
	{ id = 3356, name = "Kingsblood" },
	{ id = 3357, name = "Liferoot" },
	{ id = 3818, name = "Fadeleaf" },
	{ id = 3821, name = "Goldthorn" },
	{ id = 3358, name = "Khadgar's Whisker" },
	{ id = 3819, name = "Wintersbite" },
	{ id = 4625, name = "Firebloom" },
	{ id = 8831, name = "Purple Lotus" },
	{ id = 8836, name = "Arthas' Tears" },
	{ id = 8838, name = "Sungrass" },
	{ id = 8839, name = "Blindweed" },
	{ id = 8845, name = "Ghost Mushroom" },
	{ id = 8846, name = "Gromsblood" },
	{ id = 13464, name = "Golden Sansam" },
	{ id = 13463, name = "Dreamfoil" },
	{ id = 13465, name = "Mountain Silversage" },
	{ id = 13466, name = "Plaguebloom" },
	{ id = 13467, name = "Icecap" },
	{ id = 13468, name = "Black Lotus" },
	{ id = 19726, name = "Bloodvine" },
}
local function stackPieces(items, icon)
	local list = {}
	for _, it in ipairs(items) do
		local f = piece(icon)
		f.oreId, f.oreName = it.id, it.name
		list[#list + 1] = f
	end
	return list
end
local ores = stackPieces(ORES, "Interface\\Icons\\Trade_Mining")
local herbs = stackPieces(HERB_ITEMS, "Interface\\Icons\\Trade_Herbalism")

local ROW_H = 22
-- Row 1 is always on. Travel, Mining and Herbs each open their own row.
local rows = {
	{ loc, gold, bags, reagents, ranged, durability },
	{ steps, swum, ridden, jumps },
	ores,
	herbs,
}

local toggle = CreateFrame("Button", nil, bar)
toggle:SetSize(40, 18)
toggle:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -3, -2)
toggle:RegisterForClicks("LeftButtonUp")
toggle.bg = toggle:CreateTexture(nil, "BACKGROUND")
toggle.bg:SetAllPoints()
toggle.bg:SetColorTexture(0.16, 0.16, 0.18, 1)
toggle.edges = ns.newEdges(toggle, "OVERLAY", 1)
ns.placeEdges(toggle.edges, toggle, 0, 1)
for _, t in ipairs(toggle.edges) do t:SetColorTexture(0, 0, 0, 0.95) end
toggle.label = toggle:CreateFontString(nil, "OVERLAY")
font(toggle.label, 11)
toggle.label:SetPoint("CENTER")
toggle.label:SetTextColor(1, 0.84, 0.35)
toggle.label:SetText("Travel")
toggle:SetWidth(64)

local mineBtn = CreateFrame("Button", nil, bar)
mineBtn:SetSize(70, 18)
mineBtn:RegisterForClicks("LeftButtonUp")
mineBtn.bg = mineBtn:CreateTexture(nil, "BACKGROUND")
mineBtn.bg:SetAllPoints()
mineBtn.bg:SetColorTexture(0.16, 0.16, 0.18, 1)
mineBtn.edges = ns.newEdges(mineBtn, "OVERLAY", 1)
ns.placeEdges(mineBtn.edges, mineBtn, 0, 1)
for _, t in ipairs(mineBtn.edges) do t:SetColorTexture(0, 0, 0, 0.95) end
mineBtn.label = mineBtn:CreateFontString(nil, "OVERLAY")
font(mineBtn.label, 11)
mineBtn.label:SetPoint("CENTER")
mineBtn.label:SetTextColor(0.65, 0.65, 0.65)
mineBtn.label:SetText("Mining")
mineBtn:Hide()

local herbBtn = CreateFrame("Button", nil, bar)
herbBtn:SetSize(58, 18)
herbBtn:RegisterForClicks("LeftButtonUp")
herbBtn.bg = herbBtn:CreateTexture(nil, "BACKGROUND")
herbBtn.bg:SetAllPoints()
herbBtn.bg:SetColorTexture(0.16, 0.16, 0.18, 1)
herbBtn.edges = ns.newEdges(herbBtn, "OVERLAY", 1)
ns.placeEdges(herbBtn.edges, herbBtn, 0, 1)
for _, t in ipairs(herbBtn.edges) do t:SetColorTexture(0, 0, 0, 0.95) end
herbBtn.label = herbBtn:CreateFontString(nil, "OVERLAY")
font(herbBtn.label, 11)
herbBtn.label:SetPoint("CENTER")
herbBtn.label:SetTextColor(0.65, 0.65, 0.65)
herbBtn.label:SetText("Herbs")
herbBtn:Hide()

local function expanded()
	return ZydeForeverDB and ZydeForeverDB.infoExpanded and true or false
end

local function miningOpen()
	return ZydeForeverDB and ZydeForeverDB.infoMining and true or false
end

local function herbOpen()
	return ZydeForeverDB and ZydeForeverDB.infoHerbs and true or false
end

-- Apprentice through Artisan, same ranks the node glow uses.
local MINING_SPELLS = { 2575, 2576, 3564, 10248 }
local HERB_SPELLS = { 2366, 2368, 3570, 11993 }

local function knowsProfession(name, spells)
	for _, id in ipairs(spells) do
		if plain(safe(IsPlayerSpell, id)) or plain(safe(IsSpellKnown, id)) then return true end
	end
	if GetProfessions and GetProfessionInfo then
		local profs = { GetProfessions() }
		for i = 1, 5 do
			if profs[i] then
				local got = plain(select(1, safe(GetProfessionInfo, profs[i])))
				if got == name then return true end
			end
		end
	end
	local lines = GetNumSkillLines and plain(safe(GetNumSkillLines))
	if lines and lines > 0 and GetSkillLineInfo then
		for i = 1, lines do
			local skill, header = safe(GetSkillLineInfo, i)
			skill, header = plain(skill), plain(header)
			if skill == name and not header then return true end
		end
	end
	return false
end

local function knowsMining() return knowsProfession("Mining", MINING_SPELLS) end
local function knowsHerbalism() return knowsProfession("Herbalism", HERB_SPELLS) end

-- Which data rows are on screen, top to bottom. A profession row stays off until learned.
local function openRows()
	local list = { 1 }
	if expanded() then list[#list + 1] = 2 end
	if knowsMining() and miningOpen() then list[#list + 1] = 3 end
	if knowsHerbalism() and herbOpen() then list[#list + 1] = 4 end
	return list
end

local function place()
	bar:ClearAllPoints()
	local p = ZydeForeverDB and ZydeForeverDB.infoPos
	if type(p) == "table" and p.point then
		bar:SetPoint(p.point, UIParent, p.point, p.x or 0, p.y or 0)
	else
		bar:SetPoint("TOP", UIParent, "TOP", 0, -8)
	end
end

bar:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
	GameTooltip:AddLine("Info bar", 1, 0.84, 0.35)
	GameTooltip:AddLine("Where you are, gold, bag space, the reagent bag, ammo for a bow, gun, or throwing weapon, and gear durability.", 1, 1, 1, true)
	GameTooltip:AddLine("Travel opens steps, yards swum, yards mounted, and jumps.", 1, 1, 1, true)
	GameTooltip:AddLine("Mining, once learned, opens a count of each ore in your bags and bank.", 1, 1, 1, true)
	GameTooltip:AddLine("Herbs, once Herbalism is learned, does the same for herbs. Both can be open together.", 1, 1, 1, true)
	GameTooltip:AddLine("Ctrl+click a line to paste it into chat.", 1, 1, 1, true)
	GameTooltip:AddLine("Drag to move.", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end)
bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
bar:SetScript("OnDragStart", function(self)
	GameTooltip:Hide()
	self:StartMoving()
end)
bar:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local point, _, _, x, y = self:GetPoint()
	ZydeForeverDB = ZydeForeverDB or {}
	ZydeForeverDB.infoPos = { point = point, x = x, y = y }
end)

local function tintButton(btn, openRow)
	if openRow then btn.label:SetTextColor(1, 0.84, 0.35)
	else btn.label:SetTextColor(0.65, 0.65, 0.65) end
end

local function layout()
	local open = openRows()
	local slotOf = {}
	for slot, id in ipairs(open) do slotOf[id] = slot end
	local maxW = 120
	for i = 1, #rows do
		local slot = slotOf[i]
		local x = 6
		for _, f in ipairs(rows[i]) do
			if slot and f.on then
				local w = 14 + 4 + (f.text.GetUnboundedStringWidth and f.text:GetUnboundedStringWidth() or f.text:GetStringWidth())
				f:SetWidth(math.max(20, w))
				f:ClearAllPoints()
				f:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -((slot - 1) * ROW_H))
				f:Show()
				x = x + f:GetWidth() + 12
			else
				f:Hide()
			end
		end
		if slot then maxW = math.max(maxW, x) end
	end
	local miner, herbalist = knowsMining(), knowsHerbalism()
	mineBtn:SetShown(miner)
	herbBtn:SetShown(herbalist)
	tintButton(toggle, expanded())
	tintButton(mineBtn, miner and miningOpen())
	tintButton(herbBtn, herbalist and herbOpen())
	-- Left to right along the top: Travel, Mining, Herbs. Missing professions leave a gap closed.
	local buttons = { toggle }
	if miner then buttons[#buttons + 1] = mineBtn end
	if herbalist then buttons[#buttons + 1] = herbBtn end
	local pad = 8
	for i = #buttons, 1, -1 do
		local b = buttons[i]
		b:ClearAllPoints()
		if i == #buttons then
			b:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -4, -2)
		else
			b:SetPoint("TOPRIGHT", buttons[i + 1], "TOPLEFT", -4, 0)
		end
		pad = pad + b:GetWidth() + 4
	end
	bar:SetSize(maxW + pad, #open * ROW_H)
	if on() then bar:Show() else bar:Hide() end
end

-- Returns true when the text changed (the bar then needs laying out again).
local function show(f, text, r, g, b)
	local changed = not f.on or f.text:GetText() ~= text
	f.on = true
	if changed then f.text:SetText(text) end
	f.text:SetTextColor(r or 1, g or 0.84, b or 0.35)
	return changed
end

---------------------------------------------------------------------------
-- Location
---------------------------------------------------------------------------
local function coords()
	if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
		local map = plain(safe(C_Map.GetBestMapForUnit, "player"))
		local pos = map and safe(C_Map.GetPlayerMapPosition, map, "player")
		if pos then
			local x, y
			if pos.GetXY then x, y = safe(pos.GetXY, pos) end
			x = plain(x or pos.x)
			y = plain(y or pos.y)
			if x and y and x > 0 and y > 0 then
				return math.floor(x * 100 + 0.5), math.floor(y * 100 + 0.5)
			end
		end
	end
	if GetPlayerMapPosition then
		local x, y = safe(GetPlayerMapPosition, "player")
		x, y = plain(x), plain(y)
		if x and y and x > 0 and y > 0 then
			return math.floor(x * 100 + 0.5), math.floor(y * 100 + 0.5)
		end
	end
end

local function locationReport()
	local zone, sub = plain(GetZoneText()), plain(GetSubZoneText())
	if not zone or zone == "" then return nil end
	local where = (sub and sub ~= "" and sub ~= zone) and (zone .. ", " .. sub) or zone
	local x, y = coords()
	if x then where = ("%s (%d, %d)"):format(where, x, y) end
	return where
end

local function location()
	local where = locationReport()
	if not where then return nil end
	return "Loc: " .. where
end

---------------------------------------------------------------------------
-- Gold, bags, durability
---------------------------------------------------------------------------
local function moneyText()
	local copper = plain(GetMoney())
	if not copper then return nil end
	local g = math.floor(copper / 10000)
	local s = math.floor((copper % 10000) / 100)
	local c = copper % 100
	return ("Gold: |c%s%dg|r |c%s%ds|r |c%s%dc|r"):format(GOLD, g, SILVER, s, COPPER, c)
end

-- The reagent bag is its own slot, not one of the four normal bags.
local function reagentBagId()
	if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag then return Enum.BagIndex.ReagentBag end
	if REAGENTBAG_CONTAINER then return REAGENTBAG_CONTAINER end
	return 5
end

local function fillText(label, used, slots)
	local r, g, b = 1, 0.84, 0.35
	if used >= slots then r, g, b = 1, 0.25, 0.2
	elseif used / slots >= 0.9 then r, g, b = 1, 0.82, 0 end
	return ("%s: %d/%d"):format(label, used, slots), r, g, b
end

local function bagText()
	local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
	local numFree = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
	if not (numSlots and numFree) then return nil end
	local reagent = reagentBagId()
	local slots, free = 0, 0
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		if bag ~= reagent then
			local n, f = safe(numSlots, bag), safe(numFree, bag)
			if isSecret(n) or isSecret(f) then return nil end
			if n then slots = slots + n end
			if f then free = free + f end
		end
	end
	if slots <= 0 then return nil end
	return fillText("Bags", math.max(0, slots - free), slots)
end

local function reagentText()
	local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
	local numFree = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
	if not (numSlots and numFree) then reagents.on = false return end
	local n, f = safe(numSlots, reagentBagId()), safe(numFree, reagentBagId())
	if isSecret(n) or isSecret(f) then return nil end
	n, f = plain(n), plain(f)
	if not n or n <= 0 then reagents.on = false return end
	local slot = CharacterReagentBag0Slot
	local slotId = slot and slot.GetID and slot:GetID()
	if type(slotId) == "number" then
		local tex = plain(safe(GetInventoryItemTexture, "player", slotId))
		if tex then reagents.icon:SetTexture(tex) end
	end
	return fillText("Reagents", math.max(0, n - (f or 0)), n)
end

local function duraColor(pct)
	if pct < 0.25 then return 1, 0.25, 0.2 end
	if pct < 0.5 then return 1, 0.82, 0 end
	return 1, 0.84, 0.35
end

-- All equipped pieces that can wear out, as one percent. Hidden with nothing equipped.
local function durabilityText()
	if not GetInventoryItemDurability then durability.on = false return end
	local cur, max = 0, 0
	for slot = 1, 18 do
		local c, m = safe(GetInventoryItemDurability, slot)
		if isSecret(c) or isSecret(m) then return nil end
		c, m = plain(c), plain(m)
		if c and m and m > 0 then
			cur, max = cur + c, max + m
		end
	end
	if max <= 0 then durability.on = false return end
	local pct = cur / max
	return ("Durability: %d%%"):format(math.floor(pct * 100 + 0.5)), duraColor(pct)
end

---------------------------------------------------------------------------
-- Thrown weapon: its own durability. Bow, crossbow, gun: ammo that fits it.
---------------------------------------------------------------------------
local function itemInstant(id)
	local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	if not f then return nil end
	return safe(f, id)
end

local function weaponSubclass(id)
	local _, _, _, _, _, classID, sub = itemInstant(id)
	classID, sub = plain(classID), plain(sub)
	if classID ~= WEAPON then return nil end
	return sub
end

local function projectileKind(id)
	local _, _, _, _, _, classID, sub = itemInstant(id)
	classID, sub = plain(classID), plain(sub)
	if classID == PROJECTILE then return sub end
end

local function itemCount(id)
	local f = (C_Item and C_Item.GetItemCount) or GetItemCount
	return plain(safe(f, id))
end

-- Every arrow or bullet of the kind this weapon fires, in bags and equipped.
local function ammoAmount(kind)
	local equipped = plain(GetInventoryItemID("player", INV_AMMO))
	local n, seen = 0, false
	for _, info in ipairs(ns.Bags and ns.Bags.items() or {}) do
		if isSecret(info.itemID) or isSecret(info.stackCount) then return nil end
		if projectileKind(info.itemID) == kind then
			n = n + (tonumber(info.stackCount) or 1)
			if info.itemID == equipped then seen = true end
		end
	end
	if equipped and not seen and projectileKind(equipped) == kind then
		local c = itemCount(equipped) or plain(GetInventoryItemCount("player", INV_AMMO))
		if c and c > 0 then n = n + c end
	end
	return n
end

local function rangedText()
	local id = GetInventoryItemID("player", INV_RANGED)
	if isSecret(id) then return nil end
	if not id then ranged.on = false return end
	local sub = weaponSubclass(id)
	if sub == THROWN then
		ranged.icon:SetTexture("Interface\\Icons\\INV_ThrowingKnife_02")
		ranged.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		local cur, max = safe(GetInventoryItemDurability, INV_RANGED)
		if isSecret(cur) or isSecret(max) then return nil end
		cur, max = plain(cur), plain(max)
		if not (cur and max and max > 0) then ranged.on = false return end
		local pct = cur / max
		return ("Thrown: %d%%"):format(math.floor(pct * 100 + 0.5)), duraColor(pct)
	end
	local kind = AMMO_FOR[sub]
	if not kind then ranged.on = false return end
	if kind == ARROW then
		ranged.icon:SetTexture("Interface\\Icons\\INV_Ammo_Arrow_02")
	else
		ranged.icon:SetTexture("Interface\\Icons\\INV_Ammo_Bullet_02")
	end
	ranged.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local n = ammoAmount(kind)
	if not n then return nil end
	local label = kind == ARROW and "Arrows" or "Bullets"
	local r, g, b = 1, 0.84, 0.35
	if n < 200 then r, g, b = 1, 0.25, 0.2 elseif n < 400 then r, g, b = 1, 0.82, 0 end
	return ("%s: %d"):format(label, n), r, g, b
end

---------------------------------------------------------------------------
-- Steps, yards swum, mounted yards, and jumps, kept per character. The realm
-- name is sometimes blank on this client, which used to start a second
-- counter ("Name-" beside "Name-Realm") and look like a reset. One row per
-- character name, and any older split rows are added in the first time.
-- A step is 2 yards walked. The step count also shows that distance in miles
-- (1,760 yards). Swum yards are horizontal distance while
-- swimming. Mounted yards are the distance you ride (ground or flying mount).
-- Taxi flights are not riding. A jump is leaving the ground. Presses while you
-- are already in the air do not count.
---------------------------------------------------------------------------
local STEP_YARDS = 2
local YARDS_PER_MILE = 1760

local function milesText(yards)
	return string.format("%.1f mi", (tonumber(yards) or 0) / YARDS_PER_MILE)
end

local function blankTally()
	return { steps = 0, jumps = 0, partial = 0, mounted = 0, swum = 0 }
end

local function addTally(dst, src)
	if type(src) ~= "table" then return end
	dst.steps = dst.steps + (tonumber(src.steps) or 0)
	dst.jumps = dst.jumps + (tonumber(src.jumps) or 0)
	dst.partial = dst.partial + (tonumber(src.partial) or 0)
	dst.mounted = dst.mounted + (tonumber(src.mounted) or 0)
	dst.swum = dst.swum + (tonumber(src.swum) or 0)
end

-- Not known yet: counts land here, then move onto the character once the name is.
local pending
local active, activeName

local function playerName()
	local name = plain(UnitName("player"))
	if type(name) ~= "string" or name == "" then return nil end
	return name
end

local function tally()
	local name = playerName()
	if not name then
		pending = pending or blankTally()
		return pending
	end
	if active and activeName == name then return active end
	ZydeForeverDB = ZydeForeverDB or {}
	local ped = ZydeForeverDB.pedometer
	if type(ped) ~= "table" then
		ped = {}
		ZydeForeverDB.pedometer = ped
	end
	local t = blankTally()
	local drop = {}
	local prefix = name .. "-"
	for key, row in pairs(ped) do
		if type(key) == "string" and (key == name or key:sub(1, #prefix) == prefix) then
			addTally(t, row)
			drop[#drop + 1] = key
		end
	end
	for _, key in ipairs(drop) do ped[key] = nil end
	addTally(t, pending)
	pending = nil
	ped[name] = t
	active, activeName = t, name
	return t
end

local function commas(n)
	if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
	return tostring(n)
end

local function flag(fn, ...)
	if type(fn) ~= "function" then return false end
	local v = safe(fn, ...)
	-- Some of these return true, some return 1. A secret is "don't know", not on.
	if isSecret(v) or v == nil or v == false or v == 0 then return false end
	return true
end

local function onFoot()
	if flag(UnitOnTaxi, "player") or flag(UnitIsDeadOrGhost, "player") then return false end
	if flag(IsFlying) or flag(IsMounted) or flag(IsSwimming) then return false end
	return true
end

local function swimming()
	if flag(UnitOnTaxi, "player") or flag(UnitIsDeadOrGhost, "player") then return false end
	if flag(IsFlying) then return false end
	return flag(IsSwimming) or flag(IsSubmerged, "player")
end

-- Jumping at the surface turns IsSwimming off until you land. Remember the
-- stroke so that hop stays on the swim counter instead of becoming steps.
local swamAt = 0
local function inWater()
	if swimming() then
		swamAt = GetTime()
		return true
	end
	if flag(IsMounted) or flag(IsFlying) then return false end
	return flag(IsFalling) and (GetTime() - swamAt) < 1.5
end

local function onMount()
	if flag(UnitOnTaxi, "player") or flag(UnitIsDeadOrGhost, "player") then return false end
	return flag(IsMounted)
end

local lastX, lastY, lastInst
-- False from the moment a jump starts until we have seen the ground again.
-- leftGroundAt keeps the next sample from arming another jump before the
-- game has reported that this one left the ground.
local feetDown, leftGroundAt = true, 0

-- UnitPosition is often empty or secret on this client. Horizontal distance
-- then comes from movement speed (yards per second).
local function speedYards(dt)
	local speed = plain(safe(GetUnitSpeed, "player"))
	if not speed or speed <= 0 then return 0 end
	return speed * (dt or 0.1)
end

local function sampleMove(dt)
	if not on() then lastX, lastY = nil, nil return end
	dt = dt or 0.1
	local y, x, _, inst = safe(UnitPosition, "player")
	x, y, inst = plain(x), plain(y), plain(inst)
	local cap = math.max(20, 50 * dt)
	local dist
	if x and y and lastX and inst == lastInst then
		local dx, dy = x - lastX, y - lastY
		dist = math.sqrt(dx * dx + dy * dy)
		if dist >= cap then dist = nil end
	end
	if not dist or dist == 0 then
		local fromSpeed = speedYards(dt)
		if fromSpeed > 0 and fromSpeed < cap then dist = fromSpeed end
	end
	if dist and dist > 0 then
		local t = tally()
		if inWater() then
			t.swum = t.swum + dist
		elseif onMount() then
			t.mounted = t.mounted + dist
		elseif onFoot() and not flag(IsFlying) then
			t.partial = t.partial + dist
			local add = math.floor(t.partial / STEP_YARDS)
			if add > 0 then
				t.steps = t.steps + add
				t.partial = t.partial - add * STEP_YARDS
			end
		end
	end
	if x and y then lastX, lastY, lastInst = x, y, inst end
	if GetTime() - leftGroundAt >= 0.35
		and not flag(IsFlying) and not flag(IsSwimming) and not flag(IsFalling) then
		feetDown = true
	end
end

if hooksecurefunc and JumpOrAscendStart then
	hooksecurefunc("JumpOrAscendStart", function()
		if not on() or not feetDown then return end
		if flag(IsFlying) or flag(IsSwimming) or flag(UnitOnTaxi, "player") or flag(UnitIsDeadOrGhost, "player") then return end
		feetDown = false
		leftGroundAt = GetTime()
		local t = tally()
		if t then t.jumps = t.jumps + 1 end
	end)
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
-- Bags plus the bank. The reagent bag counts as a bag. A secret count keeps the last number.
local function itemCount(id)
	local f = (C_Item and C_Item.GetItemCount) or GetItemCount
	if not f then return nil end
	local n = safe(f, id, true, false, true)
	if n == nil then n = safe(f, id, true) end
	n = plain(n)
	if type(n) ~= "number" then return nil end
	return n
end

local function oreIcon(id)
	local icon
	if C_Item and C_Item.GetItemIconByID then icon = plain(safe(C_Item.GetItemIconByID, id)) end
	if not icon and GetItemIcon then icon = plain(safe(GetItemIcon, id)) end
	if not icon and GetItemInfo then
		local info = { safe(GetItemInfo, id) }
		icon = plain(info[10])
	end
	return icon
end

local function refreshStacks(list, showRow)
	if not showRow then
		for _, f in ipairs(list) do f.on = false end
		return false
	end
	local changed = false
	for _, f in ipairs(list) do
		local n = itemCount(f.oreId)
		if n ~= nil then
			local icon = oreIcon(f.oreId)
			if icon then f.icon:SetTexture(icon) end
			f.count = n
			local r, g, b = 1, 0.84, 0.35
			if n == 0 then r, g, b = 0.55, 0.55, 0.55 end
			if show(f, commas(n), r, g, b) then changed = true end
		end
	end
	return changed
end

local function refreshOres() return refreshStacks(ores, knowsMining() and miningOpen()) end
local function refreshHerbs() return refreshStacks(herbs, knowsHerbalism() and herbOpen()) end

-- full: also gold, bags, ammo and ore. Those only change with an event (money, bags, gear), so the
-- twice-a-second timer skips them and only redoes where you are and the travel counts.
local function update(full)
	if not on() then bar:Hide() return end
	if not bar:GetPoint() then place() end
	local changed = full or not bar:IsShown()
	local text = location()
	if text and show(loc, text) then changed = true end
	if full then
		text = moneyText()
		if text then show(gold, text, 1, 1, 1) end
		local r, g, b
		text, r, g, b = bagText()
		if text then show(bags, text, r, g, b) end
		text, r, g, b = reagentText()
		if text then show(reagents, text, r, g, b) end
		text, r, g, b = rangedText()
		if text then show(ranged, text, r, g, b) end
		text, r, g, b = durabilityText()
		if text then show(durability, text, r, g, b) end
		if refreshOres() or refreshHerbs() then changed = true end
	end
	-- the travel counts only while their line is open
	if expanded() then
		local t = tally()
		if show(steps, "Steps: " .. commas(t.steps) .. " (" .. milesText(t.steps * STEP_YARDS) .. ")") then changed = true end
		if show(swum, "Swum: " .. commas(math.floor(t.swum)) .. " yd") then changed = true end
		if show(ridden, "Mounted: " .. commas(math.floor(t.mounted)) .. " yd") then changed = true end
		if show(jumps, "Jumps: " .. commas(t.jumps)) then changed = true end
	end
	if changed then layout() end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({
	"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD",
	"ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
	"PLAYER_MONEY", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP",
	"UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED",
	"BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "PLAYERBANKSLOTS_CHANGED",
	"GET_ITEM_INFO_RECEIVED",
	"SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_TAB", "SPELLS_CHANGED",
}) do
	pcall(ev.RegisterEvent, ev, e)
end
ev:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
ev:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then place() end
	update(true)
end)

local elapsed, stepElapsed = 0, 0
bar:SetScript("OnUpdate", function(_, dt)
	stepElapsed = stepElapsed + dt
	if stepElapsed >= 0.1 then
		local waited = stepElapsed
		stepElapsed = 0
		sampleMove(waited)
	end
	elapsed = elapsed + dt
	if elapsed < 0.5 then return end
	elapsed = 0
	update(false)
end)

ns.OnFeatureChanged(function(key) if key == "infoBar" then update(true) end end)

toggle:SetScript("OnClick", function()
	ZydeForeverDB = ZydeForeverDB or {}
	ZydeForeverDB.infoExpanded = not expanded()
	update(true)
end)
toggle:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine("Travel", 1, 0.84, 0.35)
	GameTooltip:AddLine(expanded() and "Hide steps, swim, mounted, and jumps." or "Show steps, swim, mounted, and jumps.", 1, 1, 1, true)
	GameTooltip:Show()
end)
toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)

mineBtn:SetScript("OnClick", function()
	if not knowsMining() then return end
	ZydeForeverDB = ZydeForeverDB or {}
	ZydeForeverDB.infoMining = not miningOpen()
	update(true)
end)
mineBtn:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine("Mining", 1, 0.84, 0.35)
	GameTooltip:AddLine(miningOpen() and "Hide the ore counts." or "Show how many of each ore are in your bags and bank.", 1, 1, 1, true)
	GameTooltip:Show()
end)
mineBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

herbBtn:SetScript("OnClick", function()
	if not knowsHerbalism() then return end
	ZydeForeverDB = ZydeForeverDB or {}
	ZydeForeverDB.infoHerbs = not herbOpen()
	update(true)
end)
herbBtn:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine("Herbalism", 1, 0.84, 0.35)
	GameTooltip:AddLine(herbOpen() and "Hide the herb counts." or "Show how many of each herb are in your bags and bank.", 1, 1, 1, true)
	GameTooltip:Show()
end)
herbBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Ctrl+click a line: put that line's text into the chat box you are typing
-- in, or open chat with it ready to send.
local function miningReport()
	if not knowsMining() then return nil end
	local parts = {}
	for _, f in ipairs(ores) do
		local n = f.count
		if n == nil then n = itemCount(f.oreId) end
		if n then parts[#parts + 1] = f.oreName .. " " .. commas(n) end
	end
	if #parts == 0 then return nil end
	return "Ore: " .. table.concat(parts, ", ") .. "."
end

local function herbReport()
	if not knowsHerbalism() then return nil end
	local parts = {}
	for _, f in ipairs(herbs) do
		local n = f.count
		if n == nil then n = itemCount(f.oreId) end
		if n then parts[#parts + 1] = f.oreName .. " " .. commas(n) end
	end
	if #parts == 0 then return nil end
	return "Herbs: " .. table.concat(parts, ", ") .. "."
end

local function travelReport()
	local t = tally()
	if not t then return nil end
	return ("Steps: %s (%s). Swum: %s yd. Mounted: %s yd. Jumps: %s."):format(
		commas(math.floor(t.steps)),
		milesText(t.steps * STEP_YARDS),
		commas(math.floor(t.swum)),
		commas(math.floor(t.mounted)),
		commas(math.floor(t.jumps))
	)
end

local function pasteChat(text)
	if not text or text == "" then return end
	local box = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
	if box and box.IsShown and box:IsShown() and box.Insert then
		box:Insert(text)
		return
	end
	if ChatFrame_OpenChat then ChatFrame_OpenChat(text) end
end

local dragged = false
bar:HookScript("OnDragStart", function() dragged = true end)
bar:SetScript("OnMouseUp", function(self, button)
	if dragged then dragged = false return end
	if button ~= "LeftButton" or not IsControlKeyDown() then return end
	local top = self:GetTop()
	if not top then return end
	local _, cy = GetCursorPosition()
	cy = cy / self:GetEffectiveScale()
	local row = math.floor((top - cy) / ROW_H) + 1
	local which = openRows()[row]
	if which == 1 then
		pasteChat(locationReport())
	elseif which == 2 then
		pasteChat(travelReport())
	elseif which == 3 then
		pasteChat(miningReport())
	elseif which == 4 then
		pasteChat(herbReport())
	end
end)

local function stackTips(list, suffix, report)
	for _, f in ipairs(list) do
		f:EnableMouse(true)
		f:SetScript("OnEnter", function(self)
			local n = self.count
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:AddLine(self.oreName .. suffix, 1, 0.84, 0.35)
			GameTooltip:AddLine((n and commas(n) or "0") .. " in bags and bank", 1, 1, 1, true)
			GameTooltip:Show()
		end)
		f:SetScript("OnLeave", function() GameTooltip:Hide() end)
		f:SetScript("OnMouseUp", function(_, button)
			if button == "LeftButton" and IsControlKeyDown() then pasteChat(report()) end
		end)
	end
end
stackTips(ores, " Ore", miningReport)
stackTips(herbs, "", herbReport)
