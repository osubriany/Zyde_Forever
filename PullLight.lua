-- Zyde_Forever: Pull Traffic Light.
-- For the tank in a dungeon or raid: a small traffic light for the healer's mana.
--   GO (green)       the healer has 70% mana or more
--   careful (yellow) 30% to 70%
--   STOP (red)       below 30%
-- With the healer's name on top, a mana bar with marks at 30% and 70% and the percent,
-- a drink icon with a countdown while the healer drinks, and DEAD / OFFLINE.
--
-- The healer: the name you set with /zyde healer <name>, if they're in the group; else
-- whoever has the healer role; else, when nobody in the group has set a role, a guess by class (priest,
-- druid, shaman, paladin). You're the tank with the tank role, or (no role set) as a
-- warrior in Defensive Stance, a druid in bear form or a paladin with Righteous Fury.
--
-- In a fight Forever hides other players' mana from addons. The game will still draw
-- a status bar from the hidden numbers, so every part here is drawn that way: the mana
-- bar is one, and each lamp and word sits in a clipping frame tied to an invisible
-- bar the game fills from the healer's mana (see gate()). The percent is the game's
-- own text of its hidden percentage. Nothing here compares the hidden numbers.
--
-- Drag it with the left mouse button (out of combat). /zyde light shows it with your
-- own mana to place it anywhere; /zyde lightreset puts it back.

local ADDON, ns = ...

local safe, isSecret = ns.safe, ns.isSecret
local function plain(v) if isSecret(v) then return nil end return v end
local function on() return ns.F("pullLight") end

local FLAT = "Interface\\Buttons\\WHITE8X8"
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- (a white disc)
local GLOW = "Interface\\AddOns\\Zyde_Forever\\Media\\Glow"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local GO, STOP = 0.70, 0.30 -- thresholds (share of max mana)
local K = 200 -- gate bars are this many times wider than what they gate (a 0.5% switch-over)
local DEFAULT_POS = { point = "CENTER", x = -320, y = 60 }

local W = 84                   -- light width
local LAMP, GAP, PAD = 44, 8, 8
local HOUSING_W = LAMP + 2 * PAD
local HOUSING_H = 3 * LAMP + 2 * GAP + 2 * PAD
local TITLE_H, WORD_H, BAR_H = 20, 24, 13

local LAMPS = { -- top to bottom
	{ key = "stop", word = "STOP", dim = { 0.22, 0.03, 0.03 }, lit = { 1, 0.15, 0.1 } },
	{ key = "careful", word = "careful", dim = { 0.25, 0.2, 0.03 }, lit = { 1, 0.85, 0.2 } },
	{ key = "go", word = "GO", dim = { 0.03, 0.18, 0.05 }, lit = { 0.25, 1, 0.3 } },
}

---------------------------------------------------------------------------
-- The frame
---------------------------------------------------------------------------
local f = CreateFrame("Frame", "ZydeForeverPullLight", UIParent, "BackdropTemplate")
f:SetSize(W, TITLE_H + HOUSING_H + WORD_H + BAR_H + 20)
f:SetFrameStrata("MEDIUM")
f:SetClampedToScreen(true)
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetBackdrop({ bgFile = FLAT, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 } })
f:SetBackdropColor(0.1, 0.12, 0.15, 0.92)
f:SetBackdropBorderColor(0.45, 0.45, 0.5, 1)
f:Hide()

local function circle(parent, layer, sub, size, r, g, b, a)
	local t = parent:CreateTexture(nil, layer, nil, sub)
	t:SetTexture(ROUND)
	t:SetSize(size, size)
	t:SetVertexColor(r, g, b, a or 1)
	return t
end

-- Healer's name on a dark plate.
local plate = f:CreateTexture(nil, "ARTWORK")
plate:SetColorTexture(0.03, 0.03, 0.04, 0.9)
plate:SetPoint("TOPLEFT", 6, -6)
plate:SetPoint("TOPRIGHT", -6, -6)
plate:SetHeight(TITLE_H - 4)
local nameText = f:CreateFontString(nil, "OVERLAY")
nameText:SetFont(FONT, 10, "OUTLINE")
nameText:SetPoint("CENTER", plate, "CENTER", 0, 0)
nameText:SetWidth(W - 14)
nameText:SetWordWrap(false)

-- The housing with three lamps.
local housing = CreateFrame("Frame", nil, f, "BackdropTemplate")
housing:SetSize(HOUSING_W, HOUSING_H)
housing:SetPoint("TOP", f, "TOP", 0, -(TITLE_H + 6))
housing:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
housing:SetBackdropColor(0.02, 0.02, 0.025, 1)
housing:SetBackdropBorderColor(0, 0, 0, 1)

-- Under the lamps: the word, then the mana bar.
local wordArea = CreateFrame("Frame", nil, f)
wordArea:SetSize(W - 8, WORD_H)
wordArea:SetPoint("TOP", housing, "BOTTOM", 0, -3)
local stateWord = wordArea:CreateFontString(nil, "OVERLAY") -- DEAD / OFFLINE / no mana
stateWord:SetFont(FONT, 15, "OUTLINE")
stateWord:SetPoint("CENTER")
stateWord:SetTextColor(0.6, 0.6, 0.6)

local manaBar = CreateFrame("StatusBar", nil, f)
manaBar:SetSize(W - 14, BAR_H)
manaBar:SetPoint("TOP", wordArea, "BOTTOM", 0, -2)
manaBar:SetStatusBarTexture(FLAT)
manaBar:SetStatusBarColor(0.1, 0.25, 0.95)
manaBar:SetMinMaxValues(0, 1)
manaBar:SetValue(0)
do
	local bg = manaBar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.02, 0.02, 0.08, 1)
	local edge = manaBar:CreateTexture(nil, "BACKGROUND", nil, -1)
	edge:SetPoint("TOPLEFT", -1, 1)
	edge:SetPoint("BOTTOMRIGHT", 1, -1)
	edge:SetColorTexture(0, 0, 0, 1)
	-- Marks at the thresholds.
	for _, m in ipairs({ { STOP, 1, 0.85, 0.2 }, { GO, 0.3, 1, 0.35 } }) do
		local t = manaBar:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(m[2], m[3], m[4], 1)
		t:SetSize(2, BAR_H)
		t:SetPoint("LEFT", manaBar, "LEFT", (W - 14) * m[1] - 1, 0)
	end
end
local pctText = manaBar:CreateFontString(nil, "OVERLAY")
pctText:SetFont(FONT, 9, "OUTLINE")
pctText:SetPoint("CENTER")

---------------------------------------------------------------------------
-- Gates: show what's inside only while the healer's mana is above (or below) a
-- share of their max. An invisible status bar K times wider than the area runs from
-- `share` of its width left of the area; the game fills it from the hidden mana, so
-- its fill edge sits at the area's left edge exactly at `share`, and passes the area's
-- right edge 1/K later. The clipping frame is the filled part (above) or the empty
-- part (below), so the area is fully shown or fully cut away. Never a negative size.
---------------------------------------------------------------------------
local gateBars = {}
local function gate(area, share, above, parent)
	local w, h = area:GetWidth(), area:GetHeight()
	local bar = CreateFrame("StatusBar", nil, area)
	bar:SetSize(w * K, h)
	bar:SetPoint("LEFT", area, "LEFT", -share * w * K, 0)
	bar:SetStatusBarTexture(FLAT)
	bar:SetStatusBarColor(0, 0, 0, 0) -- (never drawn: only its fill's edge is used)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	gateBars[#gateBars + 1] = bar
	local fill = bar:GetStatusBarTexture()
	local clip = CreateFrame("Frame", nil, parent or area)
	clip:SetClipsChildren(true)
	if above then
		clip:SetPoint("TOPLEFT", bar, "TOPLEFT")
		clip:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
	else
		clip:SetPoint("TOPLEFT", fill, "TOPRIGHT")
		clip:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
	end
	return clip
end

-- What to draw for lamp i (1 stop, 2 careful, 3 go), inside its gate(s): a frame
-- covering `area`. Stop: below 30%. Careful: above 30% and below 70%. Go: above 70%.
local function gated(i, area)
	local outer
	if i == 1 then outer = gate(area, STOP, false)
	elseif i == 3 then outer = gate(area, GO, true)
	else outer = gate(area, GO, false, gate(area, STOP, true)) end
	local content = CreateFrame("Frame", nil, outer)
	content:SetAllPoints(area)
	return content
end

local gateRoot = CreateFrame("Frame", nil, f) -- (hidden while dead / offline: everything gated goes)
gateRoot:SetAllPoints()

local lampLit = {}
for i, l in ipairs(LAMPS) do
	local area = CreateFrame("Frame", nil, housing)
	area:SetSize(LAMP, LAMP)
	area:SetPoint("TOP", housing, "TOP", 0, -(PAD + (i - 1) * (LAMP + GAP)))
	-- Always there: a gold ring and the dark lamp.
	local ring = circle(area, "BACKGROUND", 1, LAMP + 6, 0.7, 0.55, 0.2)
	ring:SetPoint("CENTER")
	local ringIn = circle(area, "BACKGROUND", 2, LAMP + 2, 0.15, 0.1, 0.03)
	ringIn:SetPoint("CENTER")
	local dim = circle(area, "BORDER", 0, LAMP - 2, l.dim[1], l.dim[2], l.dim[3])
	dim:SetPoint("CENTER")
	local shine = circle(area, "ARTWORK", 3, LAMP * 0.45, 1, 1, 1, 0.12)
	shine:SetPoint("TOP", area, "TOP", 0, -5)
	-- Lit (gated): a glow around it and the bright lamp.
	local gateArea = CreateFrame("Frame", nil, gateRoot)
	gateArea:SetSize(LAMP + 28, LAMP + 28) -- (room for the glow)
	gateArea:SetPoint("CENTER", area, "CENTER")
	local lit = gated(i, gateArea)
	lit:SetFrameLevel(area:GetFrameLevel() + 2)
	local glow = lit:CreateTexture(nil, "BACKGROUND")
	glow:SetTexture(GLOW)
	glow:SetBlendMode("ADD")
	glow:SetSize(LAMP + 28, LAMP + 28)
	glow:SetPoint("CENTER", area, "CENTER")
	glow:SetVertexColor(l.lit[1], l.lit[2], l.lit[3], 0.9)
	local bright = circle(lit, "ARTWORK", 0, LAMP - 2, l.lit[1], l.lit[2], l.lit[3])
	bright:SetPoint("CENTER", area, "CENTER")
	local hl = circle(lit, "ARTWORK", 2, LAMP * 0.45, 1, 1, 1, 0.45)
	hl:SetPoint("TOP", area, "TOP", 0, -5)
	lampLit[i] = lit

	-- The word for this lamp, gated the same way.
	local wordGate = CreateFrame("Frame", nil, gateRoot)
	wordGate:SetSize(W - 8, WORD_H) -- (a set size: gate() needs it before the frame is placed)
	wordGate:SetPoint("CENTER", wordArea, "CENTER")
	local wc = gated(i, wordGate)
	local word = wc:CreateFontString(nil, "OVERLAY")
	word:SetFont(FONT, i == 2 and 17 or 16, "OUTLINE")
	word:SetPoint("CENTER", wordArea, "CENTER")
	word:SetText(l.word)
	word:SetTextColor(l.lit[1], l.lit[2], l.lit[3])
end

-- Drinking: the drink's icon on the housing, bobbing, with the seconds left.
local drink = CreateFrame("Frame", nil, f)
drink:SetSize(22, 22)
drink:SetPoint("TOPRIGHT", housing, "TOPRIGHT", 12, 10)
drink:SetFrameLevel(housing:GetFrameLevel() + 10)
drink.icon = drink:CreateTexture(nil, "ARTWORK")
drink.icon:SetAllPoints()
drink.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
drink.border = drink:CreateTexture(nil, "BACKGROUND")
drink.border:SetPoint("TOPLEFT", -1, 1)
drink.border:SetPoint("BOTTOMRIGHT", 1, -1)
drink.border:SetColorTexture(0.3, 0.6, 1, 1)
drink.time = drink:CreateFontString(nil, "OVERLAY")
drink.time:SetFont(FONT, 10, "OUTLINE")
drink.time:SetPoint("TOP", drink, "BOTTOM", 0, -1)
drink.time:SetTextColor(0.6, 0.85, 1)
drink.anim = drink:CreateAnimationGroup()
drink.anim:SetLooping("BOUNCE")
do
	local up = drink.anim:CreateAnimation("Translation")
	up:SetOffset(0, 4)
	up:SetDuration(0.6)
	up:SetSmoothing("IN_OUT")
end
drink:Hide()

---------------------------------------------------------------------------
-- Who: the tank (you) and the healer
---------------------------------------------------------------------------
local GUESS_ORDER = { PRIEST = 1, DRUID = 2, SHAMAN = 3, PALADIN = 4 }
local healerUnit, healerHow
local testing = false

local function groupUnits()
	local units = {}
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local u = "raid" .. i
			if not plain(UnitIsUnit(u, "player")) then units[#units + 1] = u end
		end
	else
		for i = 1, (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0) do units[#units + 1] = "party" .. i end
	end
	return units
end

local function roleOf(unit)
	local r = UnitGroupRolesAssigned and plain(safe(UnitGroupRolesAssigned, unit))
	if r == "NONE" or r == "" then return nil end
	return r
end

local function findHealer()
	local units = groupUnits()
	local typed = ZydeForeverDB and ZydeForeverDB.lightHealer
	if typed then
		for _, u in ipairs(units) do
			local n = plain(UnitName(u))
			if type(n) == "string" and n:lower() == typed then return u, "the name you set (/zyde healer)" end
		end
	end
	for _, u in ipairs(units) do
		if roleOf(u) == "HEALER" then return u, "healer role" end
	end
	-- Nobody has set a role: guess by class.
	for _, u in ipairs(units) do if roleOf(u) then return nil end end
	local best, bestRank
	for _, u in ipairs(units) do
		local _, class = UnitClass(u)
		local rank = GUESS_ORDER[plain(class) or ""]
		if rank and (not bestRank or rank < bestRank) then best, bestRank = u, rank end
	end
	if best then return best, "a guess by class (no roles set)" end
	return nil
end

local function iAmTank()
	local r = roleOf("player")
	if r == "TANK" then return true end
	if r == "HEALER" or r == "DAMAGER" then return false end
	local _, class = UnitClass("player")
	local form = plain(GetShapeshiftForm and GetShapeshiftForm())
	if class == "WARRIOR" then return form == 2 end
	if class == "DRUID" then
		local id = plain(GetShapeshiftFormID and GetShapeshiftFormID())
		return id == 5 or id == 8 -- (bear, dire bear)
	end
	if class == "PALADIN" then
		local buffs = ns.PlayerBuffs and ns.PlayerBuffs()
		for _, a in ipairs(buffs and buffs.list or {}) do
			if a.name == "Righteous Fury" then return true end
		end
	end
	return false
end

local function inDungeon()
	local inside, kind = IsInInstance()
	return plain(inside) and (kind == "party" or kind == "raid")
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local DRINKS = { ["Drink"] = true, ["Food & Drink"] = true, ["Refreshment"] = true, ["Enriched Manna Biscuit"] = true }

local function updateDrink(u)
	local found
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		for i = 1, 40 do
			local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, u, i, "HELPFUL")
			if not ok or not a then break end
			local n = plain(a.name)
			if n and (DRINKS[n] or n:find("Drink")) then found = a break end
		end
	end
	if not found then
		if drink:IsShown() then drink.anim:Stop() drink:Hide() end
		return
	end
	drink.icon:SetTexture(plain(found.icon) or "Interface\\Icons\\INV_Drink_07")
	local exp = plain(found.expirationTime)
	local left = exp and exp > 0 and (exp - GetTime()) or nil
	drink.time:SetText(left and ("%ds"):format(math.max(0, math.ceil(left))) or "")
	if not drink:IsShown() then drink:Show() drink.anim:Play() end
end

local function update()
	local u = healerUnit
	if not u then return end
	local name = plain(UnitName(u))
	local _, class = UnitClass(u)
	local cc = class and plain(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	nameText:SetText(name or "Healer")
	if cc then nameText:SetTextColor(cc.r, cc.g, cc.b) else nameText:SetTextColor(1, 1, 1) end

	local offline = plain(UnitIsConnected(u)) == false
	local dead = not offline and plain(UnitIsDeadOrGhost(u)) == true
	local maxv = UnitPowerMax(u, MANA)
	local noMana = plain(maxv) == 0
	if offline or dead or noMana then
		gateRoot:Hide()
		stateWord:SetText(offline and "OFFLINE" or dead and "DEAD" or "no mana")
		stateWord:Show()
		manaBar:SetMinMaxValues(0, 1)
		manaBar:SetValue(0)
		pctText:SetText("")
		drink:Hide()
		return
	end
	stateWord:Hide()
	gateRoot:Show()
	local cur = UnitPower(u, MANA)
	for _, b in ipairs(gateBars) do
		pcall(b.SetMinMaxValues, b, 0, maxv)
		pcall(b.SetValue, b, cur)
	end
	pcall(manaBar.SetMinMaxValues, manaBar, 0, maxv)
	pcall(manaBar.SetValue, manaBar, cur)
	-- The percent: worked out here when the numbers show, else the game's own text.
	local c, m = plain(cur), plain(maxv)
	if c and m and m > 0 then
		pctText:SetFormattedText("%d%%", math.floor(c / m * 100 + 0.5))
	else
		local p = UnitPowerPercent and CurveConstants and CurveConstants.ScaleTo100
			and safe(UnitPowerPercent, u, MANA, false, CurveConstants.ScaleTo100)
		if p == nil or not pcall(pctText.SetFormattedText, pctText, "%.0f%%", p) then pctText:SetText("") end
	end
	updateDrink(u)
end

-- Show or hide, and pick the healer again (group, roles, forms and zones change).
local function refresh()
	local u, how
	if testing then
		u, how = "player", "test: your own mana (/zyde light to hide)"
	elseif on() and IsInGroup() and inDungeon() and iAmTank() then
		u, how = findHealer()
	end
	healerUnit, healerHow = u, how
	if u then
		if not f:IsShown() then f:Show() end
		update()
	elseif f:IsShown() then
		f:Hide()
	end
end

local tick = 0
f:SetScript("OnUpdate", function(_, elapsed)
	tick = tick + elapsed
	if tick < 0.1 then return end
	tick = 0
	update()
end)

---------------------------------------------------------------------------
-- Moving, tooltip, commands
---------------------------------------------------------------------------
local function place()
	local p = (ZydeForeverDB and ZydeForeverDB.lightPos) or DEFAULT_POS
	f:ClearAllPoints()
	f:SetPoint(p.point, UIParent, p.point, p.x, p.y)
end
f:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
f:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local point, _, _, x, y = self:GetPoint()
	ZydeForeverDB = ZydeForeverDB or {}
	ZydeForeverDB.lightPos = { point = point, x = x, y = y }
end)
f:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine("Pull Traffic Light")
	GameTooltip:AddLine(("Healer: %s"):format(plain(healerUnit and UnitName(healerUnit)) or "?"), 1, 1, 1)
	GameTooltip:AddLine(("Found by: %s"):format(healerHow or "?"), 0.8, 0.8, 0.8)
	GameTooltip:AddLine(("GO %d%%+ · careful %d-%d%% · STOP under %d%%"):format(GO * 100, STOP * 100, GO * 100, STOP * 100), 0.8, 0.8, 0.8)
	GameTooltip:AddLine("Drag to move. /zyde healer <name> picks the healer.", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end)
f:SetScript("OnLeave", function() GameTooltip:Hide() end)

ns.PullLight = {
	-- /zyde light: show it with your own mana, to place it (again to hide).
	Test = function()
		testing = not testing
		refresh()
		print("|cff66ccffZyde_Forever|r: Pull Traffic Light " .. (testing and "shown with your own mana: drag it where you want it, /zyde light again to hide" or "back to normal"))
	end,
	-- /zyde healer <name>: the healer to watch when nobody has the healer role (no name: clear).
	SetHealer = function(name)
		ZydeForeverDB = ZydeForeverDB or {}
		ZydeForeverDB.lightHealer = (name and name ~= "") and name:lower() or nil
		refresh()
		print("|cff66ccffZyde_Forever|r: " .. (ZydeForeverDB.lightHealer and ("healer set to " .. name) or "healer name cleared (role, then a guess by class)"))
	end,
	Reset = function()
		if ZydeForeverDB then ZydeForeverDB.lightPos = nil end
		place()
		print("|cff66ccffZyde_Forever|r: Pull Traffic Light moved back")
	end,
}

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		place()
		for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PLAYER_ENTERING_WORLD",
			"ZONE_CHANGED_NEW_AREA", "UPDATE_SHAPESHIFT_FORM", "UNIT_CONNECTION" }) do
			pcall(ev.RegisterEvent, ev, e)
		end
		C_Timer.NewTicker(2, refresh) -- (buffs like Righteous Fury, roles shown late)
	end
	refresh()
end)
ns.OnFeatureChanged(function(key) if key == "pullLight" then refresh() end end)
