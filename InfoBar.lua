-- Zyde_Forever: a small draggable bar, three lines.
-- Collapsed: where you are, gold, bag space, and thrown durability or ammo.
-- Max opens the third line: steps, yards swum, yards ridden, and times you
-- press jump. Min puts that line away.
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
local dura = piece("Interface\\Icons\\INV_Chest_Chain")
local ranged = piece("Interface\\Icons\\INV_ThrowingKnife_02")
local steps = piece("Interface\\Icons\\INV_Boots_08")
local swum = piece("Interface\\Icons\\Ability_Druid_AquaticForm")
local ridden = piece("Interface\\Icons\\Ability_Mount_RidingHorse")
local jumps = piece("Interface\\Icons\\Spell_Magic_FeatherFall")

local ROW_H = 22
-- Line 1 where you are. Line 2 gold, bags, ammo. Line 3 is the travel counts,
-- hidden until Max is clicked.
local rows = {
	{ loc },
	{ gold, bags, ranged },
	{ steps, swum, ridden, jumps },
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
toggle.label:SetText("Max")

local function expanded()
	return ZydeForeverDB and ZydeForeverDB.infoExpanded and true or false
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
	GameTooltip:AddLine("Where you are, gold, bag space, and ammo for a bow, gun, or throwing weapon.", 1, 1, 1, true)
	GameTooltip:AddLine("Max opens steps, yards swum, yards mounted, and jumps. Min hides that line.", 1, 1, 1, true)
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

local function layout()
	local n = expanded() and #rows or 2
	local maxW = 120
	for i = 1, #rows do
		local x, y = 6, -((i - 1) * ROW_H)
		local showRow = i <= n
		for _, f in ipairs(rows[i]) do
			if showRow and f.on then
				local w = 14 + 4 + (f.text.GetUnboundedStringWidth and f.text:GetUnboundedStringWidth() or f.text:GetStringWidth())
				f:SetWidth(math.max(20, w))
				f:ClearAllPoints()
				f:SetPoint("TOPLEFT", bar, "TOPLEFT", x, y)
				f:Show()
				x = x + f:GetWidth() + 12
			else
				f:Hide()
			end
		end
		if showRow then maxW = math.max(maxW, x) end
	end
	bar:SetSize(maxW + 46, n * ROW_H)
	toggle.label:SetText(expanded() and "Min" or "Max")
	if on() then bar:Show() else bar:Hide() end
end

local function show(f, text, r, g, b)
	f.on = true
	f.text:SetText(text)
	f.text:SetTextColor(r or 1, g or 0.84, b or 0.35)
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

local function location()
	local zone, sub = plain(GetZoneText()), plain(GetSubZoneText())
	if not zone or zone == "" then return nil end
	local where = (sub and sub ~= "" and sub ~= zone) and (zone .. " " .. sub) or zone
	local x, y = coords()
	if x then where = ("%s (%d, %d)"):format(where, x, y) end
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

local function bagText()
	local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
	local numFree = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
	if not (numSlots and numFree) then return nil end
	local slots, free = 0, 0
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		local n, f = safe(numSlots, bag), safe(numFree, bag)
		if isSecret(n) or isSecret(f) then return nil end
		if n then slots = slots + n end
		if f then free = free + f end
	end
	if slots <= 0 then return nil end
	local used = math.max(0, slots - free)
	local r, g, b = 1, 0.84, 0.35
	if used >= slots then r, g, b = 1, 0.25, 0.2
	elseif used / slots >= 0.9 then r, g, b = 1, 0.82, 0 end
	return ("Bags: %d/%d"):format(used, slots), r, g, b
end

local SLOT = {
	[1] = "Head", [3] = "Shoulder", [5] = "Chest", [6] = "Waist", [7] = "Legs",
	[8] = "Feet", [9] = "Wrist", [10] = "Hands", [15] = "Back",
	[16] = "Main hand", [17] = "Off hand", [18] = "Ranged",
}

local function duraColor(pct)
	if pct < 0.25 then return 1, 0.25, 0.2 end
	if pct < 0.5 then return 1, 0.82, 0 end
	return 1, 0.84, 0.35
end

-- Average of everything you wear that can wear out, and the most worn piece.
local function durability()
	local sum, n, worst, worstName = 0, 0, 1, nil
	for slot, name in pairs(SLOT) do
		local cur, max = safe(GetInventoryItemDurability, slot)
		cur, max = plain(cur), plain(max)
		if cur and max and max > 0 then
			local pct = cur / max
			sum, n = sum + pct, n + 1
			if pct < worst then worst, worstName = pct, name end
		end
	end
	if n == 0 then return nil end
	local avg = sum / n
	local text = ("Durability: %d%%"):format(math.floor(avg * 100 + 0.5))
	if worstName and worst < 0.999 then
		text = ("%s (%s %d%%)"):format(text, worstName, math.floor(worst * 100 + 0.5))
	end
	return text, duraColor(avg)
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
-- Steps, yards swum, mounted yards, and jumps, kept per character so a
-- reload does not zero them. A step is about 2 yards walked. Swum yards are
-- horizontal distance while swimming. Mounted yards are the distance you ride
-- (ground or flying mount). Taxi flights are not riding. Jump counts each
-- press of the jump key.
---------------------------------------------------------------------------
local STEP_YARDS = 2

local function charKey()
	return (plain(UnitName("player")) or "?") .. "-" .. (plain(GetRealmName()) or "?")
end

local function tally()
	ZydeForeverDB = ZydeForeverDB or {}
	ZydeForeverDB.pedometer = ZydeForeverDB.pedometer or {}
	local key = charKey()
	local t = ZydeForeverDB.pedometer[key]
	if type(t) ~= "table" then
		t = { steps = 0, jumps = 0, partial = 0, mounted = 0, swum = 0 }
		ZydeForeverDB.pedometer[key] = t
	end
	t.steps, t.jumps, t.partial = t.steps or 0, t.jumps or 0, t.partial or 0
	t.mounted, t.swum = t.mounted or 0, t.swum or 0
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
end

if hooksecurefunc and JumpOrAscendStart then
	hooksecurefunc("JumpOrAscendStart", function()
		if not on() then return end
		local t = tally()
		t.jumps = t.jumps + 1
	end)
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
local function update()
	if not on() then bar:Hide() return end
	if not bar:GetPoint() then place() end
	local text = location()
	if text then show(loc, text) end
	text = moneyText()
	if text then
		gold.on = true
		gold.text:SetText(text)
		gold.text:SetTextColor(1, 1, 1)
	end
	local r, g, b
	text, r, g, b = bagText()
	if text then show(bags, text, r, g, b) end
	text, r, g, b = rangedText()
	if text then show(ranged, text, r, g, b) end
	local t = tally()
	show(steps, "Steps: " .. commas(t.steps))
	show(swum, "Swum: " .. commas(math.floor(t.swum)) .. " yd")
	show(ridden, "Mounted: " .. commas(math.floor(t.mounted)) .. " yd")
	show(jumps, "Jumps: " .. commas(t.jumps))
	layout()
end

local ev = CreateFrame("Frame")
for _, e in ipairs({
	"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD",
	"ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
	"PLAYER_MONEY", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP",
	"UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED",
	"BAG_UPDATE_DELAYED",
}) do
	pcall(ev.RegisterEvent, ev, e)
end
ev:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
ev:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then place() end
	update()
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
	update()
end)

ns.OnFeatureChanged(function(key) if key == "infoBar" then update() end end)

toggle:SetScript("OnClick", function()
	ZydeForeverDB = ZydeForeverDB or {}
	ZydeForeverDB.infoExpanded = not expanded()
	update()
end)
toggle:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(expanded() and "Min" or "Max", 1, 0.84, 0.35)
	GameTooltip:AddLine(expanded() and "Hide steps, swim, mounted, and jumps." or "Show steps, swim, mounted, and jumps.", 1, 1, 1, true)
	GameTooltip:Show()
end)
toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
