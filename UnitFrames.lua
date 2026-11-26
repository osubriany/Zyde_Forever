-- Zyde_Forever: clean flat unit frames (player, target, party).
-- Flat colored health box with "62.6% | 2211" text, a thin power bar under it,
-- and smooth health/power animation in both directions.
--
-- Raid: 8 columns (one per raid group) of small boxes, shown only in a raid;
-- party frames hide while you're in a raid.
--
-- Shift-drag any frame to move it (out of combat).
-- /zyde unlock       - show and drag the frames (also the empty ones)
-- /zyde lock        - lock them again (also happens when combat starts)
-- /zyde resetframes  - back to default spots

local ADDON, ns = ...
local UF = {}
ns.UnitFrames = UF

local isSecret, safe, stash = ns.isSecret, ns.safe, ns.stash

---------------------------------------------------------------------------
-- Look
---------------------------------------------------------------------------
local FLAT = "Interface\\Buttons\\WHITE8X8"
local FONT = "Fonts\\ARIALN.TTF"

local LAYOUT = {
	player = { w = 240, h = 40, power = 6, font = 16, point = "CENTER", x = -210, y = -170 },
	target = { w = 240, h = 40, power = 6, font = 16, point = "CENTER", x = 210, y = -170 },
	-- Under the player frame, lined up with its left edge.
	pet    = { w = 150, h = 20, power = 4, font = 12, point = "CENTER", x = -255, y = -213 },
	-- Beside the target frame, top edges lined up.
	tot    = { w = 150, h = 20, power = 4, font = 12, point = "CENTER", x = 415, y = -159 },
	party  = { w = 170, h = 32, power = 9, font = 13, point = "LEFT", x = 40, y = 120, gap = 12 },
	raid   = { w = 80, h = 30, power = 3, font = 11, point = "LEFT", x = 20, y = 120, gap = 4 },
}

local C = {
	player   = { 0.55, 0.76, 0.35 },
	friendly = { 0.55, 0.76, 0.35 },
	neutral  = { 0.88, 0.72, 0.27 },
	hostile  = { 0.78, 0.29, 0.23 },
	tapped   = { 0.50, 0.50, 0.50 },
	dead     = { 0.30, 0.30, 0.30 },
	bg       = { 0.05, 0.05, 0.05, 0.75 },
}

local POWER_COLORS = {
	MANA = { 0.25, 0.50, 1.00 }, RAGE = { 0.85, 0.20, 0.20 }, ENERGY = { 1.00, 0.85, 0.25 },
	FOCUS = { 1.00, 0.55, 0.25 }, RUNIC_POWER = { 0.00, 0.82, 1.00 },
}

-- A boolean/number from the game we can safely test (secret values are not).
local function plain(v)
	if isSecret(v) then return nil end
	return v
end

local function pixel()
	if PixelUtil and PixelUtil.GetNearestPixelSize then
		return PixelUtil.GetNearestPixelSize(1, UIParent:GetEffectiveScale(), 1)
	end
	return 1
end

---------------------------------------------------------------------------
-- Smooth bars: ease toward the new value every frame (up and down).
-- If the game hands us hidden ("secret") numbers we can't do maths on, use
-- the game's own built-in smoothing instead.
---------------------------------------------------------------------------
local INTERP = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
local SPEED = 5 -- higher = faster catch-up (5: ~90% there in under half a second)

local animating = {}
local animator = CreateFrame("Frame")
animator:Hide()
animator:SetScript("OnUpdate", function(self, elapsed)
	local k = math.min(1, elapsed * SPEED)
	local busy = false
	for bar in pairs(animating) do
		local diff = bar.goal - bar.cur
		if math.abs(diff) <= bar.maxv * 0.002 then
			bar.cur = bar.goal
			animating[bar] = nil
		else
			bar.cur = bar.cur + diff * k
			busy = true
		end
		bar:SetValue(bar.cur)
	end
	if not busy then self:Hide() end
end)

local function setBar(bar, value, maxv, snap)
	if isSecret(value) or isSecret(maxv) then
		animating[bar], bar.cur = nil, nil
		pcall(bar.SetMinMaxValues, bar, 0, maxv)
		if INTERP and not snap then
			if not pcall(bar.SetValue, bar, value, INTERP) then pcall(bar.SetValue, bar, value) end
		else
			pcall(bar.SetValue, bar, value)
		end
		return
	end
	maxv = (maxv and maxv > 0) and maxv or 1
	value = value or 0
	bar.maxv = maxv
	bar:SetMinMaxValues(0, maxv)
	if snap or bar.cur == nil then
		bar.cur, bar.goal = value, value
		animating[bar] = nil
		bar:SetValue(value)
		return
	end
	bar.goal = value
	if bar.cur ~= value then
		animating[bar] = true
		animator:Show()
	end
end

---------------------------------------------------------------------------
-- Building a frame
---------------------------------------------------------------------------
local function makeBar(parent, height)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetStatusBarTexture(FLAT)
	bar:SetHeight(height)
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], C.bg[4])

	-- Very soft top sheen for a bit of depth.
	bar.sheen = bar:CreateTexture(nil, "ARTWORK", nil, 2)
	bar.sheen:SetPoint("TOPLEFT")
	bar.sheen:SetPoint("TOPRIGHT")
	bar.sheen:SetHeight(height * 0.5)
	bar.sheen:SetTexture(FLAT)
	if CreateColor and bar.sheen.SetGradient then
		bar.sheen:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.07))
	else
		bar.sheen:SetVertexColor(1, 1, 1, 0.04)
	end

	-- 1px dark outline just outside the bar.
	local px = pixel()
	local edges = ns.newEdges(bar, "OVERLAY", 6)
	ns.placeEdges(edges, bar, -px, px)
	for _, t in ipairs(edges) do t:SetColorTexture(0, 0, 0, 0.9) end
	bar.edges = edges -- (the portrait style hides these: its border is slanted)
	return bar
end

local function makeText(parent, size)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(FONT, size, "OUTLINE")
	fs:SetShadowColor(0, 0, 0, 0.5)
	fs:SetShadowOffset(1, -1)
	fs:SetTextColor(1, 1, 1)
	return fs
end

local frames = {}   -- every unit frame
local byUnit = {}   -- unit token -> frame

local function frameHeight(cfg)
	return cfg.h + (cfg.power > 0 and (cfg.power + 1) or 0)
end

-- Size, clicks and visuals; shared by the fixed frames and raid buttons.
-- Faction badge. The emblem sits in the top-left of the 64px file.
local PVP_ICON = {
	Alliance = "Interface\\TargetingFrame\\UI-PVP-Alliance",
	Horde = "Interface\\TargetingFrame\\UI-PVP-Horde",
	FFA = "Interface\\TargetingFrame\\UI-PVP-FFA",
}

local function placePvP(f)
	local b = f.pvp
	if not b then return end
	b:ClearAllPoints()
	local onRight = f.unit == "target"
	if f.portrait then
		local side = math.max(24, math.floor((f.portraitSize or 44) * 0.5))
		b:SetSize(side, side)
		b:SetPoint("CENTER", f.portrait, onRight and "TOPRIGHT" or "TOPLEFT", 0, 0)
	else
		b:SetSize(22, 22)
		b:SetPoint("CENTER", f.hp, onRight and "TOPRIGHT" or "TOPLEFT", onRight and -2 or 2, 2)
	end
	if b.time then
		b.time:SetFont(FONT, math.max(10, math.floor(b:GetWidth() * 0.4)), "OUTLINE")
	end
end

local function updatePvP(f)
	local b = f.pvp
	if not b then return end
	if not f:IsShown() or not UnitExists(f.unit) then b:Hide() return end
	local unit = f.unit
	local ffa = UnitIsPVPFreeForAll and plain(safe(UnitIsPVPFreeForAll, unit))
	local flagged = plain(safe(UnitIsPVP, unit))
	-- A hidden read must not wipe the badge you already have up.
	if unit == "player" and ffa == nil and flagged == nil and b.known then return end
	local kind
	if ffa then
		kind = "FFA"
	elseif flagged then
		local faction = plain(safe(UnitFactionGroup, unit))
		kind = (faction == "Alliance" or faction == "Horde") and faction or "FFA"
	end
	b.known = kind
	if not kind then
		b.left = nil
		if b.time then b.time:SetText("") end
		b:Hide()
		return
	end
	b.icon:SetTexture(PVP_ICON[kind])
	b.icon:SetTexCoord(0, 0.62, 0, 0.62)
	b:Show()
	if not b.time then return end
	local running = IsPVPTimerRunning and plain(safe(IsPVPTimerRunning))
	local ms = GetPVPTimer and plain(safe(GetPVPTimer))
	if running and type(ms) == "number" and ms > 0 then
		b.left = ms / 1000
	elseif b.left and (running == nil or (running and ms == nil)) then
		-- Clock hidden: the ticker already running keeps going.
	else
		b.left = nil
		b.time:SetText("")
		b.shown = nil
	end
end

local function decorate(f, cfg, visualOnly)
	f.cfg = cfg
	if not visualOnly then
		f:SetSize(cfg.w, frameHeight(cfg))
		f:SetAttribute("*type1", "target")
		f:SetAttribute("*type2", "togglemenu")
		f:RegisterForClicks("AnyUp")
	end

	f.hp = makeBar(f, cfg.h)
	f.hp:SetPoint("TOPLEFT")
	f.hp:SetPoint("TOPRIGHT")

	f.text = makeText(f.hp, cfg.font)
	f.text:SetPoint("RIGHT", f.hp, "RIGHT", -8, 0)

	-- Raid marker (skull, cross...) centered on the top edge.
	local ms = math.max(12, math.min(20, math.floor(cfg.h * 0.55)))
	f.mark = f.hp:CreateTexture(nil, "OVERLAY", nil, 7)
	f.mark:SetSize(ms, ms)
	f.mark:SetPoint("CENTER", f.hp, "TOP", 0, 0)
	f.mark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	f.mark:Hide()
	-- Group icons on the top-left corner: tank / healer, leader, master looter.
	f.groupIcons = {}
	for i = 1, 3 do
		local t = f.hp:CreateTexture(nil, "OVERLAY", nil, 7)
		t:SetSize(12, 12)
		t:SetPoint("CENTER", f.hp, "TOPLEFT", 8 + (i - 1) * 13, 0)
		t:Hide()
		f.groupIcons[i] = t
	end

	-- PvP badge on the portrait corner. Yours also counts down while the flag is dropping.
	local unit = f.unit
	if unit == "player" or unit == "target" or (type(unit) == "string" and unit:match("^party%d$")) then
		local b = CreateFrame("Frame", nil, UIParent)
		b:SetFrameStrata("MEDIUM")
		b:SetFrameLevel(90)
		b:SetSize(22, 22)
		b:EnableMouse(false)
		b:Hide()
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetAllPoints()
		if unit == "player" then
			b.time = makeText(b, 11)
			b.time:SetPoint("CENTER")
			b.time:SetTextColor(1, 0.82, 0.2)
			b:SetScript("OnUpdate", function(self, elapsed)
				if not self.left then return end
				self.left = self.left - elapsed
				if self.left <= 0 then
					self.left = nil
					self.time:SetText("")
					return
				end
				local text = string.format("%d:%02d", math.floor(self.left / 60), math.floor(self.left % 60))
				if text ~= self.shown then
					self.shown = text
					self.time:SetText(text)
				end
			end)
		end
		f.pvp = b
		placePvP(f)
		f:HookScript("OnShow", function() updatePvP(f) end)
		f:HookScript("OnHide", function() b:Hide() end)
	end

	if cfg.power > 0 then
		f.power = makeBar(f, cfg.power)
		f.power:SetPoint("TOPLEFT", f.hp, "BOTTOMLEFT", 0, -1)
		f.power:SetPoint("TOPRIGHT", f.hp, "BOTTOMRIGHT", 0, -1)
		f.power.sheen:Hide()
	end
end

local function createUnitFrame(name, unit, cfg, parent)
	local f = CreateFrame("Button", name, parent or UIParent, "SecureUnitButtonTemplate")
	f.unit = unit
	f:SetFrameStrata("LOW")
	f:SetClampedToScreen(true)
	f:SetAttribute("unit", unit)
	f:RegisterForDrag("LeftButton")
	decorate(f, cfg)

	frames[#frames + 1] = f
	byUnit[unit] = f
	return f
end

---------------------------------------------------------------------------
-- Colors and text
---------------------------------------------------------------------------
local function classColor(unit)
	local _, class = UnitClass(unit)
	class = plain(class)
	if not class then return nil end
	local c = (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class))
		or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
	if c then return c.r, c.g, c.b end
end

local function isDead(unit)
	return plain(UnitIsDeadOrGhost(unit)) or false
end

local function isOffline(unit)
	local c = plain(UnitIsConnected(unit))
	return c == false
end

local function healthColor(f)
	local unit = f.unit
	if isOffline(unit) or isDead(unit) then return unpack(C.dead) end
	if unit == "player" then
		local r, g, b = classColor(unit)
		if r then return r, g, b end
		return unpack(C.player)
	end
	if plain(UnitIsPlayer(unit)) or f.isGroup then
		local r, g, b = classColor(unit)
		if r then return r, g, b end
	end
	if UnitIsTapDenied and plain(UnitIsTapDenied(unit)) then return unpack(C.tapped) end
	local reaction = plain(UnitReaction(unit, "player"))
	if reaction then
		if reaction <= 3 then return unpack(C.hostile) end
		if reaction == 4 then return unpack(C.neutral) end
		return unpack(C.friendly)
	end
	if plain(UnitCanAttack("player", unit)) then return unpack(C.hostile) end
	return unpack(C.friendly)
end

local function setHealthText(f, cur, maxv)
	local unit, fs = f.unit, f.text
	if isOffline(unit) then fs:SetText("Offline") return end
	if isDead(unit) then
		fs:SetText(plain(UnitIsGhost(unit)) and "Ghost" or "Dead")
		return
	end
	if not isSecret(cur) and not isSecret(maxv) then
		local pct = (maxv and maxv > 0) and (cur / maxv * 100) or 0
		if f.isRaid then
			fs:SetFormattedText("%d%%", math.floor(pct + 0.5))
		elseif f.isParty or f.compact then
			fs:SetFormattedText("%d%% | %d", math.floor(pct + 0.5), cur)
		else
			fs:SetFormattedText("%.1f%% | %d", pct, cur)
		end
		return
	end
	-- Hidden values: let the game format them for us.
	local pct = UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100
		and safe(UnitHealthPercent, unit, false, CurveConstants.ScaleTo100)
	if pct ~= nil and f.isRaid and pcall(fs.SetFormattedText, fs, "%.0f%%", pct) then return end
	if pct ~= nil and pcall(fs.SetFormattedText, fs, "%.1f%% | %s", pct, cur) then return end
	if not pcall(fs.SetFormattedText, fs, "%s", cur) then fs:SetText("") end
end

local function levelText(unit)
	local lvl = plain(UnitLevel(unit))
	if not lvl then return "" end
	local txt = (lvl < 0) and "??" or tostring(lvl)
	local class = plain(UnitClassification(unit))
	if class == "elite" or class == "worldboss" or class == "rareelite" then txt = txt .. "+" end
	local c = ns.levelColor(lvl) -- (Classic's rules, like Blizzard's frames)
	if c then
		return string.format("|cff%02x%02x%02x%s|r ", c.r * 255, c.g * 255, c.b * 255, txt)
	end
	return txt .. " "
end

---------------------------------------------------------------------------
-- Updating
---------------------------------------------------------------------------
local unlocked = false

local function updateHealth(f, snap)
	local unit = f.unit
	if not UnitExists(unit) then return end
	local cur, maxv = UnitHealth(unit), UnitHealthMax(unit)
	if isDead(unit) or isOffline(unit) then cur = 0; maxv = 1 end
	setBar(f.hp, cur, maxv, snap)
	f.hp:SetStatusBarColor(healthColor(f))
	setHealthText(f, cur, maxv)
end

local function updatePower(f, snap)
	if not f.power or not UnitExists(f.unit) then return end
	local unit = f.unit
	local ptype, token = UnitPowerType(unit)
	local col = POWER_COLORS[plain(token) or ""]
	if not col and PowerBarColor then
		local pc = PowerBarColor[plain(token) or ""] or PowerBarColor[plain(ptype) or 0]
		if pc then col = { pc.r, pc.g, pc.b } end
	end
	col = col or POWER_COLORS.MANA
	f.power:SetStatusBarColor(col[1], col[2], col[3])
	local cur, maxv = UnitPower(unit), UnitPowerMax(unit)
	setBar(f.power, cur, maxv, snap)
	if f.ptext then
		-- Party: the number on the bar (mana, rage or energy).
		if plain(maxv) == 0 or isDead(unit) or isOffline(unit) then f.ptext:SetText("")
		elseif not pcall(f.ptext.SetFormattedText, f.ptext, "%s", cur) then f.ptext:SetText("") end
	end
end

-- Hunter pet happiness (Classic): name color red / yellow / green.
local HAPPINESS = { { 1, 0.3, 0.25 }, { 1, 0.85, 0.25 }, { 0.5, 1, 0.45 } }

-- Blizzard's happiness face icons: unhappy, content, happy.
local HAPPY_ICON = "Interface\\PetPaperDollFrame\\UI-PetHappiness"
local HAPPY_COORDS = { { 0.375, 0.5625, 0, 0.359375 }, { 0.1875, 0.375, 0, 0.359375 }, { 0, 0.1875, 0, 0.359375 } }
local HAPPY_LABEL = { "Unhappy", "Content", "Happy" }

-- Pet auras whose name gives the mood away, for clients where
-- GetPetHappiness is missing or hidden.
local function happinessFromAuras()
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
	for _, filter in ipairs({ "HARMFUL", "HELPFUL" }) do
		for i = 1, 40 do
			local a = safe(C_UnitAuras.GetAuraDataByIndex, "pet", i, filter)
			if not a then break end
			local name = plain(a.name)
			if type(name) == "string" then
				local n = name:lower()
				if n:find("unhappy", 1, true) then return 1 end
				if n:find("content", 1, true) then return 2 end
				if n:find("happy", 1, true) then return 3 end
			end
		end
	end
	return nil
end

-- happiness (1 unhappy, 2 content, 3 happy), damage %, loyalty rate, source
-- Forever moved the pet functions into C_PetInfo (GetPetHappiness is
-- C_PetInfo.GetPetHappiness there). Results may come as values or a table.
local function petInfoFn(name)
	return _G[name] or (C_PetInfo and C_PetInfo[name])
end
ns.PetInfoFn = petInfoFn

local function petHappiness()
	if not UnitExists("pet") then return nil end
	local fn = petInfoFn("GetPetHappiness")
	if fn then
		local ok, happy, damage, loyaltyRate = pcall(fn)
		if ok and type(happy) == "table" then
			local t = happy
			happy = t.happiness or t.happinessLevel or t.level or t[1]
			damage = t.damagePercentage or t.damagePercent or t.damage or t[2]
			loyaltyRate = t.loyaltyRate or t[3]
		end
		happy = plain(happy)
		if ok and type(happy) == "number" and happy >= 1 and happy <= 3 then
			return happy, plain(damage), plain(loyaltyRate), "game"
		end
	end
	local happy = happinessFromAuras()
	if happy then return happy, nil, nil, "aura" end
	-- Blizzard's own pet frame still has its happiness face (Forever keeps
	-- PetFrameHappiness even without GetPetHappiness): read which face it shows.
	local face = _G.PetFrameHappiness
	local tex = _G.PetFrameHappinessTexture or (face and face.texture)
	if face and tex and face:IsShown() and tex.GetTexCoord then
		local left = safe(tex.GetTexCoord, tex)
		if type(left) == "number" and not isSecret(left) then
			if left < 0.1 then return 3, nil, nil, "blizzard face"
			elseif left < 0.3 then return 2, nil, nil, "blizzard face"
			elseif left < 0.5 then return 1, nil, nil, "blizzard face" end
		end
	end
	return nil
end
ns.PetHappiness = petHappiness

-- Forever's UnitName is (first, surname). A same-realm second name on other
-- clients is a realm, so the surname is only joined when the client says so.
local function unitFullName(unit)
	local first, second = UnitName(unit)
	first = plain(first)
	if not first then return "" end
	second = plain(second)
	local regional = false
	if type(RegionalUniqueNamesEnabled) == "function" then
		local ok, on = pcall(RegionalUniqueNamesEnabled)
		regional = ok and on
	end
	if regional and second and second ~= "" then
		local consts = Constants and Constants.CharacterNameSeparatorConsts
		local sep = consts and consts.CHARACTERNAME_SURNAME_SEPARATOR
		if type(sep) ~= "string" or sep == "" then sep = " " end
		return first .. sep .. second
	end
	return first
end

-- A hidden name still draws if it is handed to the font as-is. Reading it,
-- or gluing a level onto it, turns the line blank. A fixed width is worse:
-- the line tries to measure the hidden name, and that loop hits the script limit.
-- One anchor, no width, so the line is as wide as the name and never measures it.
local function freeName(fs)
	local n = fs.GetNumPoints and fs:GetNumPoints() or 0
	if n > 1 then
		local p, rel, relPt, x, y = fs:GetPoint(1)
		fs:ClearAllPoints()
		if type(p) == "string" then fs:SetPoint(p, rel, relPt, x or 0, y or 0) end
	end
	local cur = fs.GetText and fs:GetText()
	if not isSecret(cur) then fs:SetWidth(0) end
	fs:SetWordWrap(false)
end

local function writeName(fs, unit, prefix)
	local raw = UnitName(unit)
	if isSecret(raw) then
		freeName(fs)
		fs:SetText(raw)
		return
	end
	local name = (unit == "target" or unit == "targettarget") and unitFullName(unit) or (type(raw) == "string" and raw or "")
	fs:SetText((prefix or "") .. name)
end

local function updateName(f)
	if not f.name or not UnitExists(f.unit) then return end
	if f.unit == "pet" then
		writeName(f.name, f.unit)
		local happy = petHappiness()
		local c = HAPPINESS[happy or 0]
		if c then f.name:SetTextColor(c[1], c[2], c[3]) else f.name:SetTextColor(1, 1, 1) end
		if f.happy then
			local tc = HAPPY_COORDS[happy or 0]
			if tc then
				f.happy:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
				f.happy:Show()
				if happy == 1 then f.happyPulse:Play() else f.happyPulse:Stop() f.happy:SetAlpha(1) end
			else
				f.happyPulse:Stop()
				f.happy:Hide()
			end
		end
	elseif f.unit == "targettarget" or f.isGroup then
		writeName(f.name, f.unit)
	else
		-- (with the portrait style the level sits in a badge under the portrait)
		writeName(f.name, f.unit, f.badge and "" or levelText(f.unit))
	end
end

local function updateRange(f)
	if not f.isGroup or unlocked then f:SetAlpha(1) return end
	local inRange, checked = UnitInRange(f.unit)
	inRange, checked = plain(inRange), plain(checked)
	f:SetAlpha((checked and inRange == false) and 0.45 or 1)
end

-- Raid marker: the game's sheet of 8 icons, 4 across.
local function setMarkTexture(tex, i)
	local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
	tex:SetTexCoord(col * 0.25, (col + 1) * 0.25, row * 0.25, (row + 1) * 0.25)
end
ns.setMarkTexture = setMarkTexture -- (Nameplates.lua uses it too)

-- Show unit's raid marker on texture `tex`; returns true if it has one.
-- When the game hides which marker it is from addons (a "secret" number),
-- the texture is asked to pick the icon itself (no maths needed on our side).
local function applyMark(tex, unit)
	local i = GetRaidTargetIndex and UnitExists(unit) and safe(GetRaidTargetIndex, unit) or nil
	if not isSecret(i) then
		if type(i) ~= "number" or i < 1 or i > 8 then tex:Hide() return false end
		setMarkTexture(tex, i)
		tex:Show()
		return true
	end
	if (tex.SetSpriteSheetCell and pcall(tex.SetSpriteSheetCell, tex, i, 4, 4))
		or (SetRaidTargetIconTexture and pcall(SetRaidTargetIconTexture, tex, i)) then
		tex:Show()
		return true
	end
	tex:Hide()
	return false
end
ns.applyMark = applyMark

-- /zyde markdebug: what the game says about your target's raid marker.
ns.MarkDebug = function()
	local P = "|cff66ccffZyde_Forever|r: "
	if not UnitExists("target") then print(P .. "target something first") return end
	local ok, i = pcall(GetRaidTargetIndex, "target")
	print(P .. "GetRaidTargetIndex: " .. (not ok and ("error " .. tostring(i)) or (isSecret(i) and "hidden (secret)" or tostring(i))))
	local tf = byUnit.target -- (the target frame is made further down this file)
	if not tf then print(P .. "Zyde's target frame isn't there (unit frames off?)") return end
	local shown = applyMark(tf.mark, "target")
	print(P .. "target frame marker " .. (shown and "shown" or "hidden") .. ", frame " .. (tf:IsVisible() and "visible" or "not visible"))
end

local function updateMark(f)
	if f.mark then applyMark(f.mark, f.unit) end
end

-- The master looter's unit, or nil (loot method isn't Master Loot).
local function masterLooter()
	local fn = (C_PartyInfo and C_PartyInfo.GetLootMethod) or GetLootMethod
	if not fn then return nil end
	local ok, method, partyID, raidID = pcall(fn)
	method, partyID, raidID = plain(method), plain(partyID), plain(raidID)
	local master = method == "master" or (Enum and Enum.LootMethod and method == Enum.LootMethod.Masterlooter)
	if not ok or not master then return nil end
	if IsInRaid() and raidID then return "raid" .. raidID end
	if partyID == 0 then return "player" end
	if partyID then return "party" .. partyID end
	return nil
end

-- Role icons from the game's role sheet: tank, healer (damage isn't shown).
local ROLE_COORDS = { TANK = { 0, 19 / 64, 22 / 64, 41 / 64 }, HEALER = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 } }

local function updateGroupIcons(f)
	if not f.groupIcons then return end
	local n = 0
	local function add(tex, coords)
		n = n + 1
		local t = f.groupIcons[n]
		t:SetTexture(tex)
		if coords then t:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) else t:SetTexCoord(0, 1, 0, 1) end
		t:Show()
	end
	local unit = f.unit
	if IsInGroup() and (f.isGroup or unit == "player") and UnitExists(unit) then
		local role = UnitGroupRolesAssigned and plain(UnitGroupRolesAssigned(unit))
		if ROLE_COORDS[role or ""] then add("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", ROLE_COORDS[role]) end
		if UnitIsGroupLeader and plain(UnitIsGroupLeader(unit)) then add("Interface\\GroupFrame\\UI-Group-LeaderIcon") end
		local ml = masterLooter()
		if ml and plain(UnitIsUnit(unit, ml)) then add("Interface\\GroupFrame\\UI-Group-MasterLooter") end
	end
	for i = n + 1, #f.groupIcons do f.groupIcons[i]:Hide() end
end

-- Target: a thin gold edge for elites and bosses, silver for rares.
local CLASS_EDGE = { elite = { 1, 0.82, 0.2 }, worldboss = { 1, 0.82, 0.2 }, rare = { 0.78, 0.82, 0.88 }, rareelite = { 0.78, 0.82, 0.88 } }
local function updateClassEdge(f)
	if not f.classEdge then return end
	local c = UnitExists(f.unit) and CLASS_EDGE[plain(UnitClassification(f.unit)) or ""]
	for _, t in ipairs(f.classEdge) do
		if c then t:SetColorTexture(c[1], c[2], c[3], 1) t:Show() else t:Hide() end
	end
end

local function updateAll(f, snap)
	if not f.unit or not f.hp then return end
	if unlocked and not UnitExists(f.unit) then return end
	updateHealth(f, snap)
	updatePower(f, snap)
	updateName(f)
	updateRange(f)
	updateMark(f)
	updateGroupIcons(f)
	updateClassEdge(f)
	updatePvP(f)
	if f.skinUpdate then f.skinUpdate(f) end -- (portrait, ring and level badge)
end

---------------------------------------------------------------------------
-- The frames
---------------------------------------------------------------------------
local player = createUnitFrame("ZydeForeverPlayerFrame", "player", LAYOUT.player)

-- Resting "zzz": three yellow letters, each a bit bigger and up-right of the last,
-- on the empty left side of the health bar. Shown only while rested XP can build.
local rest = CreateFrame("Frame", nil, player.hp)
rest:SetSize(40, 30)
rest:SetPoint("LEFT", player.hp, "LEFT", 8, 0)
rest:SetFrameLevel(player.hp:GetFrameLevel() + 3)
for i, z in ipairs({ { 10, 0, -7 }, { 13, 9, -1 }, { 16, 20, 6 } }) do
	local fs = makeText(rest, z[1])
	fs:SetText("z")
	fs:SetTextColor(1, 0.85, 0.1)
	fs:SetPoint("LEFT", rest, "LEFT", z[2], z[3])
end
local pulse = rest:CreateAnimationGroup()
pulse:SetLooping("BOUNCE")
local fade = pulse:CreateAnimation("Alpha")
fade:SetFromAlpha(1)
fade:SetToAlpha(0.45)
fade:SetDuration(1.6)
fade:SetSmoothing("IN_OUT")
rest:Hide()

local function atMaxLevel()
	if IsPlayerAtEffectiveMaxLevel then
		local ok, max = pcall(IsPlayerAtEffectiveMaxLevel)
		if ok and max ~= nil then return max end
	end
	local maxLevel = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion())
		or (GetMaxPlayerLevel and GetMaxPlayerLevel()) or MAX_PLAYER_LEVEL
	return maxLevel and UnitLevel("player") >= maxLevel or false
end

local function updateResting()
	local show = IsResting() and not atMaxLevel()
		and not (IsXPUserDisabled and IsXPUserDisabled())
	rest:SetShown(show)
	if show then pulse:Play() else pulse:Stop() end
end

function UF.UpdateCombat(on)
	if on == nil then
		-- A poll can turn the mark on if the combat event was missed. It does
		-- not turn it off; leaving combat is PLAYER_REGEN_ENABLED.
		local v = UnitAffectingCombat("player")
		local detected
		if isSecret(v) then detected = InCombatLockdown() and true or false
		else detected = (v and true or false) or (InCombatLockdown() and true or false) end
		if not detected then return end
		on = true
	end
	player.combatOn = on and true or false
	local overlay = player.combatOverlay
	if overlay then overlay:SetShown(player.combatOn and player:IsShown()) end
end

local target = createUnitFrame("ZydeForeverTargetFrame", "target", LAYOUT.target)
target.watched = true
target.name = makeText(target, 13)
target.name:SetPoint("BOTTOMLEFT", target, "TOPLEFT", 1, 4)
target.name:SetPoint("BOTTOMRIGHT", target, "TOPRIGHT", -1, 4)
target.name:SetJustifyH("LEFT")
target.name:SetWordWrap(false)
-- Elite / rare edge just outside the frame (see updateClassEdge).
target.classEdge = ns.newEdges(target, "OVERLAY", 7)
ns.placeEdges(target.classEdge, target, -3, 1)
for _, t in ipairs(target.classEdge) do t:Hide() end

---------------------------------------------------------------------------
-- Target cast bar: just under the target frame, only while it casts.
-- Orange = you can interrupt it, gray = you can't.
---------------------------------------------------------------------------
local CAST_H = 14
local castBar = makeBar(target, CAST_H)
castBar:SetPoint("TOPLEFT", target, "BOTTOMLEFT", 0, -4)
castBar:SetPoint("TOPRIGHT", target, "BOTTOMRIGHT", 0, -4)
castBar.icon = castBar:CreateTexture(nil, "OVERLAY")
castBar.icon:SetSize(CAST_H, CAST_H)
castBar.icon:SetPoint("RIGHT", castBar, "LEFT", -3, 0)
castBar.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
castBar.spell = makeText(castBar, 11)
castBar.spell:SetPoint("LEFT", 4, 0)
castBar.spell:SetPoint("RIGHT", -34, 0)
castBar.spell:SetJustifyH("LEFT")
castBar.spell:SetWordWrap(false)
castBar.time = makeText(castBar, 11)
castBar.time:SetPoint("RIGHT", -4, 0)
castBar:Hide()

local function castInfo()
	-- name, text, icon, startMS, endMS, isTradeSkill, castID, notInterruptible
	local name, _, icon, startMS, endMS, _, _, notInterruptible = safe(UnitCastingInfo, "target")
	if name then return name, icon, startMS, endMS, notInterruptible, false end
	local cname, _, cicon, cstart, cend, _, cNotInterruptible = safe(UnitChannelInfo, "target")
	if cname then return cname, cicon, cstart, cend, cNotInterruptible, true end
	return nil
end

local function updateCast()
	if not UnitCastingInfo then castBar:Hide() return end
	local name, icon, startMS, endMS, notInterruptible, channel = castInfo()
	if not name then castBar:Hide() return end
	castBar.channel = channel
	if not pcall(castBar.spell.SetText, castBar.spell, name) then castBar.spell:SetText("") end
	if not pcall(castBar.icon.SetTexture, castBar.icon, icon) then castBar.icon:SetTexture(nil) end
	local locked = plain(notInterruptible)
	if locked then castBar:SetStatusBarColor(0.55, 0.55, 0.55) else castBar:SetStatusBarColor(1, 0.6, 0.15) end
	startMS, endMS = plain(startMS), plain(endMS)
	if startMS and endMS and endMS > startMS then
		castBar.startT, castBar.endT = startMS / 1000, endMS / 1000
		castBar:SetMinMaxValues(castBar.startT, castBar.endT)
		castBar.timed = true
	else
		-- Times hidden from addons: let the game run the bar if it can.
		castBar.timed = false
		castBar.time:SetText("")
		local dur = (channel and UnitChannelDuration or UnitCastingDuration)
		dur = dur and safe(dur, "target")
		if not (dur and castBar.SetTimerDuration and pcall(castBar.SetTimerDuration, castBar, dur)) then
			castBar:SetMinMaxValues(0, 1)
			castBar:SetValue(1)
		end
	end
	castBar:Show()
end

castBar:SetScript("OnUpdate", function(self)
	if not self.timed then return end
	local now = GetTime()
	if now >= self.endT then self:Hide() return end
	-- Casts fill up, channels drain.
	self:SetValue(self.channel and (self.endT - (now - self.startT)) or now)
	self.time:SetFormattedText("%.1f", self.endT - now)
end)

local castEvents = CreateFrame("Frame")
for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START",
	"UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" }) do
	pcall(castEvents.RegisterUnitEvent, castEvents, e, "target")
end
castEvents:SetScript("OnEvent", updateCast)

---------------------------------------------------------------------------
-- Buffs and debuffs, like the game's own frames show them:
--   target: its debuffs under the frame (yours first), its buffs above its name
--   player: your debuffs above your frame, your buffs above those
-- Icons show time left and stacks; hover one for the game's tooltip.
---------------------------------------------------------------------------
-- Debuff type colors for the icon edge.
local DISPEL = {
	Magic = { 0.2, 0.6, 1 }, Curse = { 0.6, 0, 1 }, Disease = { 0.6, 0.4, 0 }, Poison = { 0, 0.6, 0 },
}

local function auraTime(self, elapsed)
	self.tick = (self.tick or 0) + elapsed
	if self.tick < 0.1 then return end
	self.tick = 0
	if not self.expires then self.time:SetText("") return end
	local left = self.expires - GetTime()
	if left <= 0 then self.time:SetText("")
	elseif left < 10 then self.time:SetFormattedText("%.1f", left) self.time:SetTextColor(1, 0.3, 0.25)
	elseif left < 60 then self.time:SetFormattedText("%d", left) self.time:SetTextColor(1, 1, 1)
	elseif left < 3600 then self.time:SetFormattedText("%dm", math.ceil(left / 60)) self.time:SetTextColor(1, 1, 1)
	else self.time:SetFormattedText("%dh", math.ceil(left / 3600)) self.time:SetTextColor(1, 1, 1) end
end

local function auraTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
	local fn = self.harmful and GameTooltip.SetUnitDebuffByAuraInstanceID or GameTooltip.SetUnitBuffByAuraInstanceID
	local ok = self.auraID and fn and pcall(fn, GameTooltip, self.grid.unit, self.auraID)
	if not ok and GameTooltip.SetUnitAura then
		pcall(GameTooltip.SetUnitAura, GameTooltip, self.grid.unit, self.index, self.harmful and "HARMFUL" or "HELPFUL")
	end
	GameTooltip:Show()
end

-- A grid of icons beside a frame. Big icons have the time under them; small
-- ones (buffs) have it inside, at the bottom.
--   up: grows upward from the frame's top edge, else downward from its bottom
local function auraGrid(owner, unit, harmful, size, perRow, max, up)
	local small = size < 22
	local grid = {
		owner = owner, unit = unit, harmful = harmful, size = size, perRow = perRow, max = max, up = up,
		filter = harmful and "HARMFUL" or "HELPFUL",
		rowH = size + (small and 4 or 16), -- (room for the time under big icons)
		buttons = {},
	}
	for i = 1, max do
		local b = CreateFrame("Frame", nil, owner)
		b.grid = grid
		b:SetSize(size, size)
		b.border = b:CreateTexture(nil, "BACKGROUND")
		b.border:SetPoint("TOPLEFT", -1, 1)
		b.border:SetPoint("BOTTOMRIGHT", 1, -1)
		b.border:SetColorTexture(0, 0, 0, 1)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetAllPoints()
		b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
		b.cd:SetAllPoints()
		b.cd:SetDrawEdge(false)
		b.cd:SetReverse(true)
		if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
		-- (text on a frame above the swipe, so the swipe doesn't darken it)
		local top = CreateFrame("Frame", nil, b)
		top:SetAllPoints()
		top:SetFrameLevel(b.cd:GetFrameLevel() + 2)
		b.time = makeText(top, small and 9 or 11)
		b.count = makeText(top, small and 9 or 11)
		if small then
			b.time:SetPoint("BOTTOM", b, "BOTTOM", 1, 1)
			b.count:SetPoint("TOPRIGHT", b, "TOPRIGHT", 2, 1)
		else
			b.time:SetPoint("TOP", b, "BOTTOM", 0, -1)
			b.count:SetPoint("BOTTOMRIGHT", 2, -1)
		end
		b:EnableMouse(true)
		b:SetScript("OnEnter", auraTooltip)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		b:SetScript("OnUpdate", auraTime)
		b:Hide()
		grid.buttons[i] = b
	end
	return grid
end

local function showAura(grid, n, a, index, mine)
	local b = grid.buttons[n]
	b.index, b.auraID, b.harmful = index, plain(a.auraInstanceID), grid.harmful
	if grid.harmful then
		local dc = DISPEL[plain(a.dispelName) or ""]
		if dc then b.border:SetColorTexture(dc[1], dc[2], dc[3], 1)
		elseif grid.unit == "player" then b.border:SetColorTexture(0.8, 0.1, 0.1, 1)
		else b.border:SetColorTexture(0, 0, 0, 1) end
		-- Someone else's debuff on your target: a little faded, like the game's.
		b:SetAlpha((grid.unit == "target" and not mine) and 0.7 or 1)
	end
	if not pcall(b.icon.SetTexture, b.icon, a.icon) then b.icon:SetTexture(134400) end
	local stacks = plain(a.applications)
	b.count:SetText((stacks and stacks > 1) and stacks or "")
	local exp, dur = plain(a.expirationTime), plain(a.duration)
	if exp and dur and exp > 0 and dur > 0 then
		b.expires = exp
		b.cd:SetCooldown(exp - dur, dur)
		b.cd:Show()
	else
		b.expires = nil
		b.time:SetText("")
		-- Times hidden in combat: the game can still run the swipe itself.
		local d = b.auraID and C_UnitAuras.GetAuraDuration and safe(C_UnitAuras.GetAuraDuration, grid.unit, b.auraID)
		if d and b.cd.SetCooldownFromDurationObject and pcall(b.cd.SetCooldownFromDurationObject, b.cd, d) then
			b.cd:Show()
		else
			b.cd:Hide()
		end
	end
	b:Show()
end

-- Which auras sit on your own frame. The /zyde list under unit frames sets this.
UF.AURA_MODES = {
	{ key = "all", label = "All buffs and debuffs", desc = "Every buff and every debuff on you, above your frame" },
	{ key = "debuffs", label = "All debuffs", desc = "Every debuff on you. Your buffs stay hidden" },
	{ key = "dispellable", label = "Dispellable debuffs", desc = "Only debuffs with a dispel type: magic, curse, disease, poison, and the like" },
}

function UF.GetPlayerAuras()
	local db = ZydeForeverDB
	local want = db and db.playerAuras
	for _, s in ipairs(UF.AURA_MODES) do
		if s.key == want then return want end
	end
	return "all"
end

function UF.SetPlayerAuras(key)
	ZydeForeverDB = ZydeForeverDB or {}
	ZydeForeverDB.playerAuras = key
	if UF.RefreshPlayerAuras then UF.RefreshPlayerAuras() end
end

-- A hidden (secret) dispel name counts as not dispellable.
function UF.KeepPlayerAura(grid, a)
	if grid.unit ~= "player" then return true end
	local mode = UF.GetPlayerAuras()
	if mode == "all" then return true end
	if not grid.harmful then return false end
	if mode ~= "dispellable" then return true end
	local name = plain(a.dispelName)
	if type(name) == "string" and name ~= "" and name ~= "None" then return true end
	return plain(a.isDispellable) == true
end

-- Camp Tent's hour-long "no more rest" aura. It sits on you the whole hour
-- and isn't something to watch, so it stays off the frames.
local BOOSTED_REST = 1229451
local function skipAura(a)
	local id, name = plain(a.spellId), plain(a.name)
	if id == BOOSTED_REST then return true end
	return type(name) == "string" and name:lower():find("boosted rest", 1, true) ~= nil
end

-- Fill the grid: on the target, your own debuffs come first. `base` is the
-- gap between the frame's edge and the first row. Returns the room it took.
local others, othersAt = {}, {}
local function fillGrid(grid, base)
	local n, unit = 0, grid.unit
	wipe(others)
	if UnitExists(unit) and ns.F("unitAuras") and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		local ownFirst = grid.harmful and unit == "target"
		for i = 1, 40 do
			local a = safe(C_UnitAuras.GetAuraDataByIndex, unit, i, grid.filter)
			if not a then break end
			if not skipAura(a) and UF.KeepPlayerAura(grid, a) then
				if ownFirst and not plain(a.isFromPlayerOrPlayerPet) then
					others[#others + 1], othersAt[#others + 1] = a, i
				elseif n < grid.max then
					n = n + 1
					showAura(grid, n, a, i, true)
				end
			end
		end
		for k, a in ipairs(others) do
			if n >= grid.max then break end
			n = n + 1
			showAura(grid, n, a, othersAt[k], false)
		end
	end
	wipe(others)
	for i = n + 1, grid.max do grid.buttons[i]:Hide() end
	-- Place them (the base moves when the grid below grows).
	local step = grid.size + 4
	for i = 1, n do
		local b = grid.buttons[i]
		local col, row = (i - 1) % grid.perRow, math.floor((i - 1) / grid.perRow)
		b:ClearAllPoints()
		if grid.up then
			b:SetPoint("BOTTOMLEFT", grid.owner, "TOPLEFT", (grid.x or 1) + col * step, base + row * grid.rowH)
		else
			b:SetPoint("TOPLEFT", grid.owner, "BOTTOMLEFT", (grid.x or 1) + col * step, -(base + row * grid.rowH))
		end
	end
	return n > 0 and math.ceil(n / grid.perRow) * grid.rowH or 0
end

-- Target: debuffs under the cast bar's spot (so they don't jump when a cast
-- starts), buffs above its name.
local targetDebuffs = auraGrid(target, "target", true, 24, 8, 16, false)
local targetBuffs = auraGrid(target, "target", false, 20, 10, 20, true)
-- Player: debuffs above your frame (the pet frame sits below it), buffs above those.
local playerDebuffs = auraGrid(player, "player", true, 24, 8, 40, true)
local playerBuffs = auraGrid(player, "player", false, 20, 10, 40, true)

-- In combat Forever won't let addons read the target's auras at all, but the
-- game's own target frame still draws them. So when it has aura icons, those
-- are used: moved from the (hidden) game frame onto ours and laid out like
-- our own grids (debuffs under, buffs above the name). Ours are the fallback.
local blizzTaken = {} -- the game's aura buttons we've moved onto our frame

-- The game's target aura buttons in use: buffs, debuffs. Found by what they
-- are (an icon with a cooldown swipe, under the game's target frame), since
-- Forever's buttons have no names. Ones already moved onto our frame are
-- remembered, as they're no longer under the game's frame.
local seenOrder, nextOrder = {}, 0
local function isAuraButton(b)
	return type(b.Icon) == "table" and type(b.Cooldown) == "table" and (b.auraInstanceID ~= nil or b.Count ~= nil or b.Border ~= nil)
end
local function collect(frame, depth, out, seen)
	for _, c in ipairs({ frame:GetChildren() }) do
		if not seen[c] and c ~= TargetFrame.totFrame and c ~= _G.TargetFrameToT then
			seen[c] = true
			if isAuraButton(c) then out[#out + 1] = c
			elseif depth < 3 then collect(c, depth + 1, out, seen) end
		end
	end
end
local function blizzTargetButtons()
	if not (TargetFrame and type(TargetFrame.UpdateAuras) == "function") then return nil end
	local all, seen = {}, {}
	collect(TargetFrame, 1, all, seen)
	for b in pairs(blizzTaken) do
		if not seen[b] then seen[b] = true all[#all + 1] = b end
	end
	for _, b in ipairs(all) do
		if not seenOrder[b] then nextOrder = nextOrder + 1 seenOrder[b] = nextOrder end
	end
	table.sort(all, function(a, b) return seenOrder[a] < seenOrder[b] end)
	local buffs, debuffs = {}, {}
	for _, b in ipairs(all) do
		if b:IsShown() then
			if b.Border ~= nil or b.isDebuff then debuffs[#debuffs + 1] = b else buffs[#buffs + 1] = b end
		end
	end
	return buffs, debuffs, #all
end
UF.blizzTargetButtons = blizzTargetButtons

-- Lay the game's buttons out in rows on our frame.
local function placeBlizz(list, perRow, base, up)
	local x, row, rowH = 0, 0, 0
	for i, b in ipairs(list) do
		if not blizzTaken[b] then
			blizzTaken[b] = b:GetParent() or true
			b:SetParent(target)
		end
		local w, h = b:GetWidth(), b:GetHeight()
		if i > 1 and (i - 1) % perRow == 0 then
			row = row + 1
			x = 0
		end
		rowH = math.max(rowH, h)
		b:ClearAllPoints()
		if up then
			b:SetPoint("BOTTOMLEFT", target, "TOPLEFT", 1 + x, base + row * (h + 14))
		else
			b:SetPoint("TOPLEFT", target, "BOTTOMLEFT", 1 + x, -(base + row * (h + 14)))
		end
		x = x + w + 3
	end
end

-- Give the game's buttons back to its own frame (icons turned off).
local function returnBlizz()
	for b, parent in pairs(blizzTaken) do
		if type(parent) == "table" then b:SetParent(parent) end
	end
	wipe(blizzTaken)
end

-- (Its icons are "forbidden" frames that addons can't touch, so their
-- countdown numbers can't be switched on: only the clock swipe shows.)
-- Forever's target frame has no aura buttons of its own: it has one aura
-- container (TargetFrame:GetAuraContainer()) that the game fills itself, and
-- can do so in combat. While Zyde's target frame is on, that container is
-- moved under it (where the debuffs go); it goes back when the icons are off.
local container, containerParent, returning, placing
local function gameContainer()
	if not (TargetFrame and type(TargetFrame.GetAuraContainer) == "function") then return nil end
	local ok, c = pcall(TargetFrame.GetAuraContainer, TargetFrame)
	if ok and type(c) == "table" and c.SetParent then return c end
	return nil
end
UF.gameAuraContainer = gameContainer
local function takeContainer()
	local c = gameContainer()
	if not c then return nil end
	if container ~= c then container, containerParent = c, c:GetParent() end
	if c:GetParent() ~= target then c:SetParent(target) end
	-- Only its spot: its size follows how many auras it holds, which the game
	-- keeps secret, so it isn't read or set here.
	if placing then return c end
	placing = true
	pcall(function()
		c:ClearAllPoints()
		-- Right under the frame; below the cast bar while it shows.
		c:SetPoint("TOPLEFT", target, "BOTTOMLEFT", 0, castBar:IsShown() and -(CAST_H + 9) or -4)
	end)
	placing = false
	return c
end
local function returnContainer()
	if not container or returning then return end
	returning = true
	if containerParent and container:GetParent() ~= containerParent then container:SetParent(containerParent) end
	if TargetFrame.AnchorAuraContainer then pcall(TargetFrame.AnchorAuraContainer, TargetFrame) end
	returning = false
end

local function updateTargetDebuffs()
	if returning then return end
	if UF.disabled then returnContainer() returnBlizz() return end -- (Zyde unit frames off: the game's frame keeps its icons)
	if not ns.F("unitAuras") then
		returnContainer()
		returnBlizz()
		fillGrid(targetDebuffs, CAST_H + 9)
		fillGrid(targetBuffs, 22)
		return
	end
	local c = takeContainer()
	if c then
		-- The game draws them: hide ours.
		for _, b in ipairs(targetDebuffs.buttons) do b:Hide() end
		for _, b in ipairs(targetBuffs.buttons) do b:Hide() end
		return
	end
	local buffs, debuffs = blizzTargetButtons()
	if buffs then
		-- The game's icons: hide ours.
		for _, b in ipairs(targetDebuffs.buttons) do b:Hide() end
		for _, b in ipairs(targetBuffs.buttons) do b:Hide() end
		placeBlizz(debuffs, 8, CAST_H + 9, false)
		placeBlizz(buffs, 10, 22, true)
		return
	end
	fillGrid(targetDebuffs, CAST_H + 9)
	fillGrid(targetBuffs, 22) -- (the name sits just above the frame)
end
-- After the game redraws its icons, lay them out again.
if type(_G.TargetFrame_UpdateAuras) == "function" then
	hooksecurefunc("TargetFrame_UpdateAuras", function() updateTargetDebuffs() end)
end
if TargetFrame and type(TargetFrame.UpdateAuras) == "function" then
	hooksecurefunc(TargetFrame, "UpdateAuras", function() updateTargetDebuffs() end)
end
-- The cast bar comes and goes: move the auras down for it, and back up.
castBar:HookScript("OnShow", function() if container then updateTargetDebuffs() end end)
castBar:HookScript("OnHide", function() if container then updateTargetDebuffs() end end)
-- The game re-anchors its container to its own frame: put it back under ours.
for _, m in ipairs({ "AnchorAuraContainer", "UpdateAuraContainerAnchors", "ConfigureAuraContainer" }) do
	if TargetFrame and type(TargetFrame[m]) == "function" then
		hooksecurefunc(TargetFrame, m, function() updateTargetDebuffs() end)
	end
end
local function updatePlayerDebuffs()
	local used = fillGrid(playerDebuffs, 16)
	fillGrid(playerBuffs, used + 4) -- (used includes the time under the top row)
end
function UF.RefreshPlayerAuras() updatePlayerDebuffs() end

-- Pet: a smaller box, shown only while you have a pet out.
local pet = createUnitFrame("ZydeForeverPetFrame", "pet", LAYOUT.pet)
pet.watched, pet.compact, pet.dummyName = true, true, "Pet"
pet.name = makeText(pet.hp, 11)
pet.name:SetPoint("LEFT", pet.hp, "LEFT", 6, 0)
pet.name:SetPoint("RIGHT", pet.text, "LEFT", -6, 0)
pet.name:SetJustifyH("LEFT")
pet.name:SetWordWrap(false)
pet.text:SetPoint("RIGHT", pet.hp, "RIGHT", -6, 0)
pet:SetMovable(true)

-- Hunter pet happiness face just left of the frame; it blinks when unhappy.
pet.happy = pet:CreateTexture(nil, "OVERLAY")
pet.happy:SetSize(22, 22)
pet.happy:SetPoint("RIGHT", pet, "LEFT", -3, 0)
pet.happy:SetTexture(HAPPY_ICON)
pet.happy:Hide()
pet.happyPulse = pet:CreateAnimationGroup()
pet.happyPulse:SetLooping("BOUNCE")
local hp = pet.happyPulse:CreateAnimation("Alpha")
hp:SetTarget(pet.happy)
hp:SetFromAlpha(1)
hp:SetToAlpha(0.3)
hp:SetDuration(0.6)

-- Pet XP: a thin purple bar just under the pet frame.
local function petXP()
	local fn = petInfoFn("GetPetExperience")
	if not fn then return nil end
	local ok, cur, nextXP = pcall(fn)
	if not ok then return nil end
	if type(cur) == "table" then cur, nextXP = cur.currentXP or cur.current or cur[1], cur.nextLevelXP or cur.max or cur[2] end
	cur, nextXP = plain(cur), plain(nextXP)
	if type(cur) ~= "number" or type(nextXP) ~= "number" then return nil end
	return cur, nextXP
end

pet.xp = CreateFrame("StatusBar", nil, pet)
pet.xp:SetStatusBarTexture(FLAT)
pet.xp:SetStatusBarColor(0.69, 0.35, 1.0) -- same purple as the XP readout
pet.xp:SetHeight(3)
pet.xp:SetPoint("TOPLEFT", pet, "BOTTOMLEFT", 0, -1)
pet.xp:SetPoint("TOPRIGHT", pet, "BOTTOMRIGHT", 0, -1)
pet.xp.bg = pet.xp:CreateTexture(nil, "BACKGROUND")
pet.xp.bg:SetAllPoints()
pet.xp.bg:SetColorTexture(0, 0, 0, 0.7)
pet.xp:Hide()

local lastPetLevel
local function updatePetXP()
	local cur, nextXP = petXP()
	if cur and nextXP > 0 then
		pet.xp:SetMinMaxValues(0, nextXP)
		pet.xp:SetValue(cur)
		pet.xp:Show()
	else
		pet.xp:Hide() -- same level as you: it can't level until you do
	end
	-- "Boar is now level 9" in chat when it levels.
	local lvl = UnitExists("pet") and plain(UnitLevel("pet"))
	if lvl and lastPetLevel and lvl > lastPetLevel then
		print(("|cff66ccffZyde_Forever|r: %s is now level %d"):format(plain(UnitName("pet")) or "Your pet", lvl))
	end
	lastPetLevel = lvl or nil
end

-- Hover: level, XP, and what the mood means.
pet:HookScript("OnEnter", function(self)
	if not UnitExists("pet") then return end
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
	local lvl = plain(UnitLevel("pet"))
	GameTooltip:AddLine((plain(UnitName("pet")) or "Pet") .. (lvl and ("  (level " .. lvl .. ")") or ""), 1, 1, 1)
	local cur, nextXP = petXP()
	if cur and nextXP > 0 then
		GameTooltip:AddDoubleLine("Pet XP", ("%s / %s (%.1f%%)"):format(BreakUpLargeNumbers and BreakUpLargeNumbers(cur) or cur,
			BreakUpLargeNumbers and BreakUpLargeNumbers(nextXP) or nextXP, cur / nextXP * 100), 1, 1, 1, 0.69, 0.35, 1.0)
		GameTooltip:AddDoubleLine("Needed to level", BreakUpLargeNumbers and BreakUpLargeNumbers(nextXP - cur) or (nextXP - cur),
			1, 1, 1, 1, 0.82, 0)
	elseif cur then
		GameTooltip:AddLine("Same level as you - it levels again when you do", 0.7, 0.7, 0.7, true)
	end
	local happy, damage, loyaltyRate = petHappiness()
	if not HAPPY_LABEL[happy or 0] then GameTooltip:Show() return end
	local c = HAPPINESS[happy]
	GameTooltip:AddLine(HAPPY_LABEL[happy], c[1], c[2], c[3])
	if type(damage) == "number" then
		GameTooltip:AddLine(("Deals %d%% damage"):format(math.floor(damage + 0.5)), 0.85, 0.85, 0.85)
	end
	local loyaltyFn = petInfoFn("GetPetLoyalty")
	local loyalty = loyaltyFn and plain(safe(loyaltyFn))
	if type(loyalty) == "string" and loyalty ~= "" then GameTooltip:AddLine(loyalty, 0.85, 0.85, 0.85) end
	if type(loyaltyRate) == "number" and loyaltyRate < 0 then
		GameTooltip:AddLine("Losing loyalty - it will run away if this goes on", 1, 0.3, 0.25, true)
	end
	if happy < 3 then GameTooltip:AddLine("Feed your pet to make it happier", 0.6, 0.6, 0.6) end
	GameTooltip:Show()
end)
pet:HookScript("OnLeave", function() GameTooltip:Hide() end)

-- Pet buffs and debuffs: a row of small icons under the pet frame,
-- debuffs first with a red edge. Hover one for the game's own tooltip.
local AURA_SIZE, AURA_MAX = 16, 8
local petAuras = {}

local function petAuraButton(i)
	local b = CreateFrame("Frame", nil, pet)
	b:SetSize(AURA_SIZE, AURA_SIZE)
	b:SetPoint("TOPLEFT", pet, "BOTTOMLEFT", 1 + (i - 1) * (AURA_SIZE + 3), -8) -- below the XP bar
	b.border = b:CreateTexture(nil, "BACKGROUND")
	b.border:SetPoint("TOPLEFT", -1, 1)
	b.border:SetPoint("BOTTOMRIGHT", 1, -1)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	-- a clock swipe and the seconds left, like the player and target icons
	b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cd:SetAllPoints()
	b.cd:SetDrawEdge(false)
	b.cd:SetReverse(true)
	if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
	local top = CreateFrame("Frame", nil, b) -- (text above the swipe, so it isn't darkened)
	top:SetAllPoints()
	top:SetFrameLevel(b.cd:GetFrameLevel() + 2)
	b.count = makeText(top, 9)
	b.count:SetPoint("TOPRIGHT", b, "TOPRIGHT", 2, 1)
	b.time = makeText(top, 9) -- (inside, at the bottom, like the other small aura icons)
	b.time:SetPoint("BOTTOM", b, "BOTTOM", 1, 1)
	b:SetScript("OnUpdate", auraTime)
	b:EnableMouse(true)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		local fn = self.harmful and GameTooltip.SetUnitDebuffByAuraInstanceID or GameTooltip.SetUnitBuffByAuraInstanceID
		local ok = self.auraID and fn and pcall(fn, GameTooltip, "pet", self.auraID)
		if not ok and GameTooltip.SetUnitAura then
			pcall(GameTooltip.SetUnitAura, GameTooltip, "pet", self.index, self.harmful and "HARMFUL" or "HELPFUL")
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:Hide()
	return b
end
for i = 1, AURA_MAX do petAuras[i] = petAuraButton(i) end

local function updatePetAuras()
	local n = 0
	if UnitExists("pet") and ns.F("unitAuras") and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		for _, filter in ipairs({ "HARMFUL", "HELPFUL" }) do
			for i = 1, 40 do
				if n >= AURA_MAX then break end
				local a = safe(C_UnitAuras.GetAuraDataByIndex, "pet", i, filter)
				if not a then break end
				n = n + 1
				local b = petAuras[n]
				b.harmful, b.index, b.auraID = filter == "HARMFUL", i, plain(a.auraInstanceID)
				if not pcall(b.icon.SetTexture, b.icon, a.icon) then b.icon:SetTexture(134400) end
				local stacks = plain(a.applications)
				b.count:SetText((stacks and stacks > 1) and stacks or "")
				if b.harmful then b.border:SetColorTexture(0.8, 0.1, 0.1, 1) else b.border:SetColorTexture(0, 0, 0, 1) end
				local exp, dur = plain(a.expirationTime), plain(a.duration)
				if exp and dur and exp > 0 and dur > 0 then
					b.expires = exp
					b.cd:SetCooldown(exp - dur, dur)
					b.cd:Show()
				else
					b.expires = nil
					b.time:SetText("")
					-- times hidden from addons (in combat): the game can still run the swipe itself
					local d = b.auraID and C_UnitAuras.GetAuraDuration and safe(C_UnitAuras.GetAuraDuration, "pet", b.auraID)
					if d and b.cd.SetCooldownFromDurationObject and pcall(b.cd.SetCooldownFromDurationObject, b.cd, d) then
						b.cd:Show()
					else
						b.cd:Hide()
					end
				end
				b:Show()
			end
		end
	end
	for i = n + 1, AURA_MAX do petAuras[i]:Hide() end
end
pet:HookScript("OnShow", function() updatePetAuras() updatePetXP() end)

-- Target of target: a small box beside the target frame (an option in /zyde).
-- The game sends no events for it, so it re-reads itself a few times a second.
local tot = createUnitFrame("ZydeForeverTargetTargetFrame", "targettarget", LAYOUT.tot)
tot.watched, tot.compact, tot.dummyName = true, true, "Target of target"
tot.name = makeText(tot.hp, 11)
tot.name:SetPoint("LEFT", tot.hp, "LEFT", 6, 0)
tot.name:SetPoint("RIGHT", tot.text, "LEFT", -6, 0)
tot.name:SetJustifyH("LEFT")
tot.name:SetWordWrap(false)
tot.text:SetPoint("RIGHT", tot.hp, "RIGHT", -6, 0)
tot:SetMovable(true)
tot:HookScript("OnUpdate", function(self, elapsed)
	self.tick = (self.tick or 0) + elapsed
	if self.tick < 0.2 or unlocked then return end
	self.tick = 0
	updateAll(self, false)
end)

-- On or off from the /zyde window (waits for the end of a fight: it's a secure frame).
local function applyTot()
	if UF.disabled then return end
	if InCombatLockdown() then UF.pendingTot = true return end
	UF.pendingTot = nil
	local want = ns.F("targetTarget")
	tot.off, tot.watched = not want, want
	if unlocked then return end
	if want then RegisterUnitWatch(tot) else UnregisterUnitWatch(tot) tot:Hide() end
end

local partyHolder = CreateFrame("Frame", "ZydeForeverPartyHolder", UIParent)
local pcfg = LAYOUT.party
local pheight = pcfg.h + pcfg.power + 1
partyHolder:SetSize(pcfg.w, pheight * 4 + pcfg.gap * 3)
partyHolder:SetClampedToScreen(true)
partyHolder:SetMovable(true)

local party = {}
for i = 1, 4 do
	local f = createUnitFrame("ZydeForeverParty" .. i, "party" .. i, pcfg, partyHolder)
	f.isParty, f.isGroup, f.watched = true, true, true
	f:SetPoint("TOPLEFT", partyHolder, "TOPLEFT", 0, -(i - 1) * (pheight + pcfg.gap))
	f.name = makeText(f.hp, 12)
	f.name:SetPoint("LEFT", f.hp, "LEFT", 7, 0)
	f.name:SetPoint("RIGHT", f.text, "LEFT", -6, 0)
	f.name:SetJustifyH("LEFT")
	f.name:SetWordWrap(false)
	f.ptext = makeText(f.power, 9)
	f.ptext:SetPoint("RIGHT", f.power, "RIGHT", -4, 0)
	party[i] = f
end

player:SetMovable(true)
target:SetMovable(true)

-- Blizzard's frames, which used to open the unit tooltip, are hidden.
-- These buttons only had click and drag, so hovering them did nothing.
local function showUnitTip(self)
	local unit = self.unit
	if type(unit) ~= "string" and self.GetAttribute then unit = self:GetAttribute("unit") end
	if type(unit) ~= "string" or not UnitExists(unit) then return end
	if GameTooltip_SetDefaultAnchor then
		GameTooltip_SetDefaultAnchor(GameTooltip, self)
	else
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	end
	if not pcall(GameTooltip.SetUnit, GameTooltip, unit) then GameTooltip:Hide() return end
	GameTooltip:Show()
end
local function hideUnitTip() GameTooltip:Hide() end

for _, f in ipairs(frames) do
	f:HookScript("OnShow", function(self) updateAll(self, true) end)
	if f.watched then RegisterUnitWatch(f) end
	if f.unit ~= "pet" then
		f:HookScript("OnEnter", showUnitTip)
		f:HookScript("OnLeave", hideUnitTip)
	end
end

---------------------------------------------------------------------------
-- Raid: a secure group header lays out one column per raid group (1-8),
-- five people each, and keeps it right even when the raid changes in combat.
---------------------------------------------------------------------------
local rcfg = LAYOUT.raid
local rheight = frameHeight(rcfg)

local raidHolder = CreateFrame("Frame", "ZydeForeverRaidHolder", UIParent)
raidHolder:SetSize(8 * rcfg.w + 7 * rcfg.gap, 5 * rheight + 4 * rcfg.gap)
raidHolder:SetClampedToScreen(true)
raidHolder:SetMovable(true)

local raidHeader = CreateFrame("Frame", "ZydeForeverRaidHeader", raidHolder, "SecureGroupHeaderTemplate")
raidHeader:SetPoint("TOPLEFT", raidHolder, "TOPLEFT", 0, 0)
raidHeader:SetAttribute("template", "SecureUnitButtonTemplate")
raidHeader:SetAttribute("showRaid", true)
raidHeader:SetAttribute("showParty", false)
raidHeader:SetAttribute("showPlayer", true)
raidHeader:SetAttribute("showSolo", false)
raidHeader:SetAttribute("groupBy", "GROUP")
raidHeader:SetAttribute("groupingOrder", "1,2,3,4,5,6,7,8")
raidHeader:SetAttribute("point", "TOP")
raidHeader:SetAttribute("yOffset", -rcfg.gap)
raidHeader:SetAttribute("columnAnchorPoint", "LEFT")
raidHeader:SetAttribute("columnSpacing", rcfg.gap)
raidHeader:SetAttribute("unitsPerColumn", 5)
raidHeader:SetAttribute("maxColumns", 8)
-- Size any button the header creates later (it may do so in combat).
raidHeader:SetAttribute("initialConfigFunction", string.format([[
	self:SetWidth(%d)
	self:SetHeight(%d)
	self:SetAttribute("*type1", "target")
	self:SetAttribute("*type2", "togglemenu")
]], rcfg.w, rheight))

local raidButtons = {}
local raidByUnit = {}

local function rebuildRaidMapNow()
	wipe(raidByUnit)
	for _, b in ipairs(raidButtons) do
		if b.unit and b:IsShown() then
			raidByUnit[b.unit] = b
			-- Some events name you/your group as "player"/"partyN" instead of "raidN".
			for _, alias in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
				if plain(UnitIsUnit(b.unit, alias)) then raidByUnit[alias] = b end
			end
		end
	end
end

-- A roster change makes many buttons change at once, and each asks for a
-- rebuild: do it once, on the next frame, instead of once per button.
local raidMapPending = false
local function rebuildRaidMap()
	if raidMapPending then return end
	raidMapPending = true
	C_Timer.After(0, function()
		raidMapPending = false
		rebuildRaidMapNow()
	end)
end

local function styleRaidButton(b)
	if b.zydeStyled then return end
	b.zydeStyled = true
	b.isRaid, b.isGroup = true, true
	-- In combat the size and clicks come from initialConfigFunction instead.
	decorate(b, rcfg, InCombatLockdown())
	b.text:ClearAllPoints()
	b.text:SetPoint("BOTTOMRIGHT", b.hp, "BOTTOMRIGHT", -4, 3)
	b.name = makeText(b.hp, 11)
	b.name:SetPoint("TOPLEFT", b.hp, "TOPLEFT", 4, -3)
	b.name:SetPoint("TOPRIGHT", b.hp, "TOPRIGHT", -4, -3)
	b.name:SetJustifyH("LEFT")
	b.name:SetWordWrap(false)

	b:HookScript("OnAttributeChanged", function(self, key, value)
		if key ~= "unit" then return end
		self.unit = value
		rebuildRaidMap()
		if value and self:IsShown() then updateAll(self, true) end
	end)
	b:HookScript("OnShow", function(self)
		self.unit = self:GetAttribute("unit")
		rebuildRaidMap()
		if self.unit then updateAll(self, true) end
	end)
	b:HookScript("OnHide", rebuildRaidMap)
	if not InCombatLockdown() then
		b:HookScript("OnEnter", showUnitTip)
		b:HookScript("OnLeave", hideUnitTip)
	end
	-- Shift-drag moves the whole raid (buttons are styled out of combat).
	if not InCombatLockdown() then
		b:RegisterForDrag("LeftButton")
		b:SetScript("OnDragStart", UF.startDrag)
		b:SetScript("OnDragStop", UF.stopDrag)
	end
	b.unit = b:GetAttribute("unit")
	raidButtons[#raidButtons + 1] = b
end

local function styleNewRaidButtons()
	local i = 1
	local b = raidHeader:GetAttribute("child1")
	while b do
		styleRaidButton(b)
		i = i + 1
		b = raidHeader:GetAttribute("child" .. i)
	end
	rebuildRaidMap()
end

-- Create all 40 buttons up front (out of combat) so they're styled before
-- any fight, then hand the header back its normal settings.
local function buildRaid()
	if UF.raidBuilt or InCombatLockdown() then return end
	UF.raidBuilt = true
	raidHolder:Show()
	raidHeader:Show()
	raidHeader:SetAttribute("startingIndex", -39)
	raidHeader:SetAttribute("startingIndex", 1)
	styleNewRaidButtons()
	raidHeader:SetAttribute("unitsPerColumn", 5) -- re-layout with the styled sizes
	RegisterStateDriver(raidHolder, "visibility", "[group:raid] show; hide")
	RegisterStateDriver(partyHolder, "visibility", "[group:raid] hide; show")
end

---------------------------------------------------------------------------
-- Positions
---------------------------------------------------------------------------
local movers = {
	player = { frame = player, cfg = LAYOUT.player, label = "Player" },
	target = { frame = target, cfg = LAYOUT.target, label = "Target" },
	pet    = { frame = pet, cfg = LAYOUT.pet, label = "Pet" },
	tot    = { frame = tot, cfg = LAYOUT.tot, label = "Target of target" },
	party  = { frame = partyHolder, cfg = LAYOUT.party, label = "Party" },
	raid   = { frame = raidHolder, cfg = LAYOUT.raid, label = "Raid" },
}

local function savedPos(key)
	return ZydeForeverDB and ZydeForeverDB.frames and ZydeForeverDB.frames[key]
end

local function place(key)
	local m = movers[key]
	local p = savedPos(key) or { point = m.cfg.point, rel = m.cfg.point, x = m.cfg.x, y = m.cfg.y }
	m.frame:ClearAllPoints()
	m.frame:SetPoint(p.point, UIParent, p.rel or p.point, p.x, p.y)
end

local function placeAll()
	if InCombatLockdown() then UF.pendingPlace = true return end
	UF.pendingPlace = nil
	for key in pairs(movers) do place(key) end
end

local function save(key)
	local point, _, rel, x, y = movers[key].frame:GetPoint()
	ZydeForeverDB = ZydeForeverDB or {}
	ZydeForeverDB.frames = ZydeForeverDB.frames or {}
	ZydeForeverDB.frames[key] = { point = point, rel = rel, x = x, y = y }
end

---------------------------------------------------------------------------
-- Unlock / lock
---------------------------------------------------------------------------
local stopDrag

local function moverOverlay(m)
	if m.overlay then return m.overlay end
	local o = CreateFrame("Frame", nil, m.frame)
	o:SetAllPoints()
	o:SetFrameStrata("DIALOG")
	-- The overlay itself is the drag handle.
	o:EnableMouse(true)
	o:RegisterForDrag("LeftButton")
	o:SetScript("OnDragStart", function()
		if not unlocked or InCombatLockdown() then return end
		m.frame:StartMoving()
		UF.dragging = m.frame
	end)
	o:SetScript("OnDragStop", function() stopDrag() end)
	local t = o:CreateTexture(nil, "OVERLAY")
	t:SetAllPoints()
	t:SetColorTexture(0.25, 0.55, 1.0, 0.25)
	local label = makeText(o, 12)
	label:SetPoint("CENTER")
	label:SetText(m.label .. " - drag to move")
	o:Hide()
	m.overlay = o
	return o
end

-- Shift-drag moves a frame any time out of combat; /zyde unlock without Shift.
local function startDrag(self)
	if InCombatLockdown() or not (unlocked or IsShiftKeyDown()) then return end
	local holder = (self.isParty and partyHolder) or (self.isRaid and raidHolder) or self
	holder:StartMoving()
	UF.dragging = holder
end

function stopDrag()
	local holder = UF.dragging
	if not holder then return end
	holder:StopMovingOrSizing()
	UF.dragging = nil
	for key, m in pairs(movers) do
		if m.frame == holder then save(key) end
	end
end

for _, f in ipairs(frames) do
	f:SetScript("OnDragStart", startDrag)
	f:SetScript("OnDragStop", stopDrag)
end
UF.startDrag, UF.stopDrag = startDrag, stopDrag

-- Fill an empty frame (no target / no party member) so it can be seen while moving.
local function dummy(f)
	f.hp:SetMinMaxValues(0, 1)
	f.hp:SetValue(0.7)
	f.hp.cur = nil
	f.hp:SetStatusBarColor(unpack(f.unit == "target" and C.hostile or C.friendly))
	f.text:SetText("70%")
	if f.power then f.power:SetMinMaxValues(0, 1); f.power:SetValue(0.5); f.power.cur = nil end
	if f.name then f.name:SetText(f.dummyName or (f.isParty and f.unit or "Target")) end
end

function UF.Unlock()
	if InCombatLockdown() then
		print("|cff66ccffZyde_Forever|r: can't move frames in combat")
		return
	end
	unlocked = true
	if UF.raidBuilt then
		UnregisterStateDriver(raidHolder, "visibility")
		UnregisterStateDriver(partyHolder, "visibility")
	end
	raidHolder:Show()
	partyHolder:Show()
	for _, f in ipairs(frames) do
		if not f.off then -- (target of target turned off)
			if f.watched then UnregisterUnitWatch(f) end
			f:Show()
			f:SetAlpha(1)
			if not UnitExists(f.unit) then dummy(f) end
		end
	end
	for _, m in pairs(movers) do
		if not m.frame.off then moverOverlay(m):Show() end
	end
	print("|cff66ccffZyde_Forever|r: frames unlocked - drag them, then /zyde lock (Shift-drag also moves them while locked)")
end

function UF.Lock(quiet)
	if not unlocked then return end
	unlocked = false
	stopDrag()
	for _, m in pairs(movers) do if m.overlay then m.overlay:Hide() end end
	for _, f in ipairs(frames) do
		if f.watched then RegisterUnitWatch(f) end
		updateAll(f, true)
	end
	if UF.raidBuilt then
		RegisterStateDriver(raidHolder, "visibility", "[group:raid] show; hide")
		RegisterStateDriver(partyHolder, "visibility", "[group:raid] hide; show")
	end
	if not quiet then print("|cff66ccffZyde_Forever|r: frames locked") end
end

function UF.Command(msg)
	if UF.disabled then
		print("|cff66ccffZyde_Forever|r: unit frames are turned off (/zyde to turn them on, then /reload)")
		return
	end
	if msg == "unlock" then
		UF.Unlock()
	elseif msg == "lock" then
		UF.Lock()
	elseif msg == "resetframes" then
		if InCombatLockdown() then
			print("|cff66ccffZyde_Forever|r: can't move frames in combat")
			return
		end
		if ZydeForeverDB then ZydeForeverDB.frames = nil end
		placeAll()
		print("|cff66ccffZyde_Forever|r: frames back in their default spots")
	end
end

---------------------------------------------------------------------------
-- Hide Blizzard's player, target and party frames
---------------------------------------------------------------------------
local function hideBlizzardUnitFrames()
	if InCombatLockdown() then return end
	stash(PlayerFrame)
	stash(TargetFrame)
	stash(PetFrame)
	stash(PartyFrame)
	for i = 1, 4 do stash(_G["PartyMemberFrame" .. i]) end
	stash(CompactPartyFrame)
	stash(CompactRaidFrameManager)
	stash(CompactRaidFrameContainer)
end

---------------------------------------------------------------------------
-- Frame styles: how the player, target, party, pet and target-of-target
-- frames look. Picked in /zyde (Unit frames > Style), saved as
-- ZydeForeverDB.frameStyle, and built once at login, so a change needs a /reload.
--   slant  Gilded Slant (default): round portrait in a class-colored ring,
--          level badge, slanted bar ends, glossy class gradient, name on a tab
--   bold   Gilded Bold: that same look, a little shorter, with a heavier font
--   flat   Clean Flat: the plain flat boxes, no portraits
--   hex    Hex Crest: hexagon portraits in a steel rim, bars ending in an
--          arrow point, a gold line between health and power
--   glass  Glass Glow: dark rounded cards, a glowing ring, pill-shaped bars
--   plate  Arcane Plate: square portraits with clipped corners and gold trim,
--          bars with cut corners
-- Player and party have the portrait on the left, the target on the right.
-- Pet and target of target get the bars only. Raid frames stay flat.
---------------------------------------------------------------------------
UF.STYLES = {
	{ key = "slant", label = "Gilded Slant", desc = "Round portrait in a ring of the class color, level badge, slanted bar ends with a glossy class gradient, name on a dark tab" },
	{ key = "bold", label = "Gilded Bold", desc = "Gilded Slant, a little shorter, with heavier text. Click a portrait to target that unit" },
	{ key = "flat", label = "Clean Flat", desc = "The plain flat boxes: no portraits, least screen space" },
	{ key = "hex", label = "Hex Crest", desc = "Hexagon portraits in a steel rim, bars that end in an arrow point, a thin gold line between health and power" },
	{ key = "glass", label = "Glass Glow", desc = "Dark rounded cards, a soft glow around a round portrait, pill-shaped bars" },
	{ key = "plate", label = "Arcane Plate", desc = "Square portraits with clipped corners and gold trim, chunky bars with cut corners" },
}

function UF.GetStyle()
	local db = ZydeForeverDB
	local want = db and db.frameStyle
	for _, s in ipairs(UF.STYLES) do
		if s.key == want then return want end
	end
	-- (before there was a list: the portrait option turned off meant the flat boxes)
	if db and db.features and db.features.framePortraits == false then return "flat" end
	return "slant"
end

function UF.SetStyle(key)
	ZydeForeverDB = ZydeForeverDB or {}
	ZydeForeverDB.frameStyle = key
end

do -- own scope (200-local limit)
local MEDIA = "Interface\\AddOns\\Zyde_Forever\\Media\\"
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local FRIZ = "Fonts\\FRIZQT__.TTF"
local LEAN = 24 / 256 -- how far a slant or arrow end reaches in, as a share of the width (matches the textures)
local GOLD, SILVER = { 1, 0.78, 0.25 }, { 0.80, 0.84, 0.90 }
local CLAMP = "CLAMPTOBLACKADDITIVE"

-- What each style is made of.
--   bar/back  mask over the bars (back: the target's, mirrored); whole = one
--             shape over health and power together, else one per bar
--   portrait  mask for the portrait, ring and its rim; ring = how it's colored
--   badge     level badge kind; name = where the name goes; border, shade, card
local SPEC = {
	slant = { bar = "Slant", back = "SlantBack", whole = true, portrait = ROUND, ring = "class", badge = "disc",
		name = "tab", border = "dark", shade = "shine", gap = 22 },
	bold = { bar = "Slant", back = "SlantBack", whole = true, portrait = ROUND, ring = "class", badge = "disc",
		name = "tab", border = "dark", shade = "shine", gap = 22,
		font = FRIZ, fontFlag = "THICKOUTLINE", fontAdd = 2, short = 0.8, portraitPad = 12 },
	hex = { bar = "Arrow", back = "ArrowBack", whole = true, portrait = MEDIA .. "Hex", ring = "steel", badge = "hex",
		name = "inside", border = "steel", shade = "gloss", divider = true, font = FRIZ, gap = 16 },
	glass = { bar = "Pill", back = "Pill", whole = false, portrait = ROUND, ring = "glow", badge = "chip",
		name = "inside", card = true, shade = "shine", gap = 28 },
	plate = { bar = "Cut", back = "Cut", whole = true, portrait = MEDIA .. "Octagon", ring = "gold", badge = "tag",
		name = "above", border = "gold", shade = "gloss", font = FRIZ, gap = 24 },
}

-- A two-color gradient on a plain texture. Horizontal: left, right. Vertical: bottom, top.
local function gradient(tex, orient, r1, g1, b1, a1, r2, g2, b2, a2)
	if CreateColor and tex.SetGradient then
		tex:SetGradient(orient, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
	else
		tex:SetVertexColor(r2, g2, b2, (a1 + a2) / 2)
	end
end

-- A mask made on `owner` (masks belong to a frame), shaped like `file`,
-- stretched over `area`, cutting each texture in `list`.
local function cut(owner, file, area, list)
	local m = owner:CreateMaskTexture()
	m:SetTexture(file, CLAMP, CLAMP)
	m:SetAllPoints(area)
	for _, t in ipairs(list) do t:AddMaskTexture(m) end
	return m
end

local function plainTex(owner, layer, sub)
	local t = owner:CreateTexture(nil, layer, nil, sub)
	t:SetTexture(FLAT)
	return t
end

-- Bars: the style's shape, and its shading on the filled part.
--   shine  lighter toward the right end, darker along the bottom, glossy top
--   gloss  light top, dark bottom (a rounded, metal look)
local function skinBar(bar, f, spec, file)
	for _, t in ipairs(bar.edges or {}) do t:Hide() end
	local fill = bar:GetStatusBarTexture()
	local list = { bar.bg, fill }
	if spec.shade == "shine" then
		local shine = plainTex(bar, "ARTWORK", 3)
		shine:SetPoint("TOPLEFT", fill, "TOPLEFT")
		shine:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
		gradient(shine, "HORIZONTAL", 0, 0, 0, 0.22, 1, 1, 1, 0.30)
		list[#list + 1] = shine
	end
	local low = plainTex(bar, "ARTWORK", 4)
	low:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT")
	low:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
	low:SetHeight(math.max(2, math.floor(bar:GetHeight() * (spec.shade == "gloss" and 0.5 or 0.4))))
	gradient(low, "VERTICAL", 0, 0, 0, spec.shade == "gloss" and 0.45 or 0.35, 0, 0, 0, 0)
	list[#list + 1] = low
	if bar.sheen then
		gradient(bar.sheen, "VERTICAL", 1, 1, 1, 0, 1, 1, 1, spec.shade == "gloss" and 0.32 or 0.18)
		list[#list + 1] = bar.sheen
	end
	if spec.card then bar.bg:SetColorTexture(1, 1, 1, 0.08) else bar.bg:SetColorTexture(0.07, 0.06, 0.06, 0.88) end
	cut(bar, file, spec.whole and f or bar, list)
end

-- Behind the bars (the gap between health and power shows it too).
local function skinBorder(f, spec, file)
	if spec.border == "dark" then
		local b = plainTex(f, "BACKGROUND", -8)
		b:SetPoint("TOPLEFT", f, "TOPLEFT", -3, 2)
		b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -2)
		gradient(b, "VERTICAL", 0.01, 0.01, 0.01, 0.95, 0.20, 0.18, 0.16, 0.95)
		cut(f, file, b, { b })
	elseif spec.border == "steel" then
		local b = plainTex(f, "BACKGROUND", -8)
		b:SetPoint("TOPLEFT", f, "TOPLEFT", -3, 2)
		b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -2)
		gradient(b, "VERTICAL", 0.14, 0.15, 0.17, 1, 0.83, 0.85, 0.87, 1)
		cut(f, file, b, { b })
	elseif spec.border == "gold" then
		local g = plainTex(f, "BACKGROUND", -8)
		g:SetPoint("TOPLEFT", f, "TOPLEFT", -3, 3)
		g:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -3)
		gradient(g, "VERTICAL", 0.48, 0.33, 0.06, 1, 0.95, 0.82, 0.48, 1)
		cut(f, file, g, { g })
		local d = plainTex(f, "BACKGROUND", -7)
		d:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
		d:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
		d:SetColorTexture(0.03, 0.02, 0.02, 1)
		cut(f, file, d, { d })
	end
	if spec.divider and f.power then
		local line = f:CreateTexture(nil, "ARTWORK")
		line:SetColorTexture(0.79, 0.64, 0.29, 1)
		line:SetPoint("TOPLEFT", f.hp, "BOTTOMLEFT", 0, 0)
		line:SetPoint("TOPRIGHT", f.hp, "BOTTOMRIGHT", 0, 0)
		line:SetHeight(1)
		cut(f, file, f, { line })
	end
end

-- Glass: a dark rounded card behind the frame (and its portrait).
local function addCard(f, left, right)
	local c = CreateFrame("Frame", nil, f, "BackdropTemplate")
	c:SetPoint("TOPLEFT", f, "TOPLEFT", -left, 9)
	c:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", right, -9)
	c:SetFrameLevel(math.max(0, f.hp:GetFrameLevel() - 1))
	c:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	c:SetBackdropColor(0.04, 0.04, 0.07, 0.72)
	c:SetBackdropBorderColor(1, 1, 1, 0.28)
	f.card = c
end

local function shaped(owner, shape, layer, sub)
	local t = owner:CreateTexture(nil, layer, nil, sub)
	cut(owner, shape, t, { t })
	return t
end

local function addPortrait(f, spec, onRight)
	local hp = f.hp:GetHeight()
	local extra = f.cfg.power > 0 and (f.cfg.power + 1) or 0
	local pad = spec.portraitPad or (f.isParty and 12 or 16)
	local d = hp + extra + pad
	local s = CreateFrame("Frame", nil, f)
	s:SetSize(d, d)
	s:SetPoint("CENTER", f, onRight and "RIGHT" or "LEFT", onRight and -2 or 2, 0)
	s:SetFrameLevel(f.hp:GetFrameLevel() + 6)
	if spec.ring == "glow" then
		f.glow = s:CreateTexture(nil, "BACKGROUND", nil, -8)
		f.glow:SetTexture(MEDIA .. "Glow")
		f.glow:SetPoint("CENTER")
		f.glow:SetSize(d * 1.5, d * 1.5)
		f.glow:SetBlendMode("ADD")
	end
	f.ring = shaped(s, spec.portrait, "BACKGROUND")
	f.ring:SetAllPoints()
	f.ring:SetTexture(FLAT)
	local rim = spec.ring == "glow" and 2 or 3
	local inner = shaped(s, spec.portrait, "BORDER")
	inner:SetPoint("TOPLEFT", rim, -rim)
	inner:SetPoint("BOTTOMRIGHT", -rim, rim)
	inner:SetColorTexture(0.04, 0.04, 0.04, 1)
	f.portrait = shaped(s, spec.portrait, "ARTWORK")
	f.portrait:SetPoint("TOPLEFT", rim + 1, -rim - 1)
	f.portrait:SetPoint("BOTTOMRIGHT", -rim - 1, rim + 1)

	-- The level badge.
	local small = f.isParty
	local size = small and 9 or 10
	if spec.badge == "disc" then
		local bs = (small and 18 or 21) + (spec.fontAdd or 0) * 2
		f.badgeEdge = shaped(s, ROUND, "ARTWORK", 6)
		f.badgeEdge:SetSize(bs + 2, bs + 2)
		f.badgeEdge:SetPoint("CENTER", s, "BOTTOM", 0, 4)
		f.badgeEdge:SetColorTexture(1, 1, 1, 1)
		local disc = shaped(s, ROUND, "ARTWORK", 7)
		disc:SetSize(bs, bs)
		disc:SetPoint("CENTER", f.badgeEdge, "CENTER")
		disc:SetTexture(FLAT)
		gradient(disc, "VERTICAL", 0.02, 0.02, 0.02, 1, 0.20, 0.18, 0.16, 1)
		f.badge = makeText(s, size)
		f.badge:SetPoint("CENTER", disc, "CENTER", 0, 0)
		if spec.font then f.badge:SetFont(spec.font, size + (spec.fontAdd or 0), spec.fontFlag or "OUTLINE") end
	elseif spec.badge == "hex" then
		local hb = shaped(s, MEDIA .. "Hex", "ARTWORK", 7)
		hb:SetSize(small and 22 or 26, small and 16 or 19)
		hb:SetPoint("CENTER", s, "BOTTOM", 0, 3)
		hb:SetTexture(FLAT)
		gradient(hb, "VERTICAL", 0.55, 0.40, 0.10, 1, 0.95, 0.82, 0.45, 1)
		f.badge = s:CreateFontString(nil, "OVERLAY")
		f.badge:SetFont(FRIZ, size - 1, "")
		f.badge:SetTextColor(0.1, 0.07, 0.02)
		f.badge:SetPoint("CENTER", hb, "CENTER", 0, 0)
		f.badgeDark = true
	elseif spec.badge == "chip" then
		local chip = shaped(s, MEDIA .. "Pill", "ARTWORK", 7)
		chip:SetSize(small and 22 or 26, small and 13 or 15)
		chip:SetPoint("CENTER", s, onRight and "BOTTOMLEFT" or "BOTTOMRIGHT", onRight and 4 or -4, 6)
		chip:SetColorTexture(0.05, 0.05, 0.08, 0.95)
		f.badge = makeText(s, size)
		f.badge:SetPoint("CENTER", chip, "CENTER", 0, 0)
	elseif spec.badge == "tag" then
		local tag = s:CreateTexture(nil, "ARTWORK", nil, 7)
		tag:SetColorTexture(0.03, 0.02, 0.02, 0.95)
		tag:SetSize(small and 18 or 22, small and 11 or 13)
		tag:SetPoint("BOTTOMLEFT", f.portrait, "BOTTOMLEFT", 2, 2)
		f.badge = s:CreateFontString(nil, "OVERLAY")
		f.badge:SetFont(FRIZ, size - 1, "")
		f.badge:SetTextColor(0.95, 0.82, 0.48)
		f.badge:SetPoint("CENTER", tag, "CENTER", 0, 0)
		f.badgeGold = true
	end
	f.portraitSize = d
	f.ringKind = spec.ring
	-- In combat: a red strobe over the portrait, and crossed swords on the corner.
	-- Parent is the screen, not the unit frame. The unit frame sits on a low
	-- strata, and a child there was drawing underneath the portrait button.
	if f.unit == "player" then
		local overlay = CreateFrame("Frame", nil, UIParent)
		overlay:SetFrameStrata("MEDIUM")
		overlay:SetFrameLevel(80)
		overlay:SetAllPoints(s)
		local flash = overlay:CreateTexture(nil, "ARTWORK")
		flash:SetPoint("TOPLEFT", f.portrait, "TOPLEFT")
		flash:SetPoint("BOTTOMRIGHT", f.portrait, "BOTTOMRIGHT")
		flash:SetTexture(FLAT)
		flash:SetVertexColor(1, 0, 0, 1)
		cut(overlay, spec.portrait, flash, { flash })
		overlay.flash = flash
		local sw = math.max(16, math.floor(d * 0.32))
		local icon = overlay:CreateTexture(nil, "OVERLAY")
		icon:SetSize(sw, sw)
		-- Upper-right of the face, inside the circle rather than above the bar.
		icon:SetPoint("CENTER", f.portrait, "TOPRIGHT", math.floor(-sw * 0.55), math.floor(-sw * 0.7))
		icon:SetTexture("Interface\\Icons\\Ability_DualWield")
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		overlay:SetScript("OnUpdate", function()
			local a = math.abs(math.sin(GetTime() * 6))
			flash:SetAlpha(0.05 + a * 0.28)
		end)
		overlay:Hide()
		f:HookScript("OnShow", function()
			if f.combatOn then overlay:Show() end
		end)
		f:HookScript("OnHide", function() overlay:Hide() end)
		f.combatOverlay = overlay
	end
	placePvP(f)
	-- The portrait hangs off the bar, so the bar's own click misses it.
	-- This button is a child of the unit frame and aimed with the frame's own
	-- points, which stays allowed once a fight starts.
	if not InCombatLockdown() then
		local hit = CreateFrame("Button", nil, f, "SecureUnitButtonTemplate")
		hit:SetSize(d, d)
		hit:SetPoint("CENTER", f, onRight and "RIGHT" or "LEFT", onRight and -2 or 2, 0)
		hit:SetFrameLevel(s:GetFrameLevel() + 5)
		hit:RegisterForClicks("AnyUp")
		hit:RegisterForDrag("LeftButton")
		hit:SetScript("OnDragStart", function() startDrag(f) end)
		hit:SetScript("OnDragStop", stopDrag)
		hit:SetAttribute("unit", f.unit)
		hit:SetAttribute("*type1", "target")
		hit:SetAttribute("*type2", "togglemenu")
		hit:EnableMouse(true)
		hit.unit = f.unit
		if f.unit ~= "pet" then
			hit:HookScript("OnEnter", showUnitTip)
			hit:HookScript("OnLeave", hideUnitTip)
		end
		local bg = hit:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(1, 1, 1, 0)
	end
end

-- Names. tab: on a dark slanted tab sitting on the bar's top edge.
-- inside: in the health bar, on the left. above: plain text just above the bar.
local function placeName(f, spec, file, left, width)
	local size = (f.unit == "target" and 13 or 11) + (spec.fontAdd or 0)
	-- Thick outline at the full size is wider than the tab, so long target names clip.
	if spec.fontFlag == "THICKOUTLINE" and f.unit == "target" then size = 12 end
	local face = spec.font or FONT
	local flag = spec.fontFlag or "OUTLINE"
	-- Target of target: a smaller tab, wide enough for a first and last name.
	if f.unit == "targettarget" then size, flag = 9, "OUTLINE" end
	if spec.name == "tab" then
		local tab = CreateFrame("Frame", nil, f)
		local tabH = size + (f.unit == "targettarget" and 4 or (spec.fontFlag == "THICKOUTLINE" and 8 or 5))
		local pad = f.unit == "targettarget" and 6 or 10
		tab:SetSize(width, tabH)
		tab:SetPoint("BOTTOMLEFT", f, "TOPLEFT", left, -3)
		tab:SetFrameLevel(f.hp:GetFrameLevel() + 3)
		local bg = plainTex(tab, "BACKGROUND")
		bg:SetAllPoints()
		gradient(bg, "VERTICAL", 0.02, 0.02, 0.02, 0.94, 0.22, 0.20, 0.18, 0.94)
		cut(tab, file, bg, { bg })
		f.name:SetParent(tab)
		f.name:ClearAllPoints()
		-- One side only. A right anchor gives the line a width, and a hidden
		-- name in a fixed-width line trips the script limit.
		f.name:SetPoint("LEFT", tab, "LEFT", pad, 0)
		f.name:SetFont(face, size, flag)
		f.name:SetWordWrap(false)
		f.name:SetJustifyH("LEFT")
		if f.mark then
			f.mark:ClearAllPoints()
			f.mark:SetPoint("CENTER", tab, "RIGHT", 12, -2)
		end
	elseif spec.name == "inside" then
		f.name:SetParent(f.hp)
		f.name:ClearAllPoints()
		f.name:SetPoint("LEFT", f.hp, "LEFT", left + 6, 0)
		f.name:SetFont(face, size - (spec.font and 1 or 0), flag)
		f.name:SetJustifyH("LEFT")
	else -- above
		f.name:SetParent(f)
		f.name:ClearAllPoints()
		f.name:SetPoint("BOTTOMLEFT", f, "TOPLEFT", left + 2, 4)
		f.name:SetFont(face, size - 1, flag)
		f.name:SetJustifyH("LEFT")
		if f.mark then
			f.mark:ClearAllPoints()
			f.mark:SetPoint("CENTER", f.hp, "TOPRIGHT", -24, 0)
		end
	end
end

-- Ring color: class color for players and group members, gold for elites and
-- bosses, silver for rares, otherwise the same reaction color as the bar.
-- Steel and gold rims keep their metal unless it's an elite or a rare.
local function ringColor(f)
	local unit = f.unit
	local special
	if not plain(UnitIsPlayer(unit)) and not f.isGroup then
		local cls = plain(UnitClassification(unit))
		if cls == "elite" or cls == "worldboss" then special = GOLD
		elseif cls == "rare" or cls == "rareelite" then special = SILVER end
	end
	if special then return special[1], special[2], special[3], true end
	return healthColor(f)
end

local function lift(v) return math.min(1, v * 1.15 + 0.1) end

local function skinUpdate(f)
	local unit = f.unit
	if not UnitExists(unit) then return end
	pcall(SetPortraitTexture, f.portrait, unit)
	f.portrait:SetDesaturated(isDead(unit) or isOffline(unit))
	local r, g, b, special = ringColor(f)
	local kind = f.ringKind
	if kind == "steel" and not special then
		gradient(f.ring, "VERTICAL", 0.29, 0.31, 0.34, 1, 0.90, 0.91, 0.93, 1)
	elseif kind == "gold" and not special then
		gradient(f.ring, "VERTICAL", 0.48, 0.33, 0.06, 1, 0.95, 0.82, 0.48, 1)
	elseif kind == "glow" then
		gradient(f.ring, "VERTICAL", r, g, b, 1, lift(r), lift(g), lift(b), 1)
		f.glow:SetVertexColor(r, g, b, 0.8)
		if f.card then f.card:SetBackdropBorderColor(r, g, b, special and 0.6 or 0.3) end
	else
		gradient(f.ring, "VERTICAL", r * 0.45, g * 0.45, b * 0.45, 1, lift(r), lift(g), lift(b), 1)
	end
	if f.badgeEdge then f.badgeEdge:SetVertexColor(r, g, b, 1) end
	local lvl = plain(UnitLevel(unit))
	if not lvl then
		f.badge:SetText("")
	elseif unit == "player" or f.isGroup or f.badgeDark then
		f.badge:SetText(lvl < 0 and "??" or lvl)
	else
		f.badge:SetText((levelText(unit):gsub("%s+$", ""))) -- (difficulty color, "+" for elites)
	end
end

-- Where the right end of the bars sits in, at the health text's height.
local function endInset(spec, f)
	local lean = LEAN * f.cfg.w
	local h = f.hp and f.hp:GetHeight() or f.cfg.h
	local total = h + (f.cfg.power > 0 and (f.cfg.power + 1) or 0)
	local mid = (h / 2) / math.max(1, total)
	if spec.bar == "Slant" then return lean * mid end
	if spec.bar == "Arrow" then return lean * math.abs(2 * mid - 1) end
	if spec.bar == "Pill" then return f.cfg.h * 0.3 end
	return 2
end

function UF.applySkin(style)
	local spec = SPEC[style]
	if not spec or UF.skinned then return end
	UF.skinned = style
	local list = { player, target, pet, tot }
	for i = 1, 4 do list[#list + 1] = party[i] end
	for _, f in ipairs(list) do
		local isTarget = f == target
		local file = MEDIA .. (isTarget and spec.back or spec.bar)
		local w = f.cfg.w
		-- Pet and target-of-target are already short; only the tall bars shrink.
		if spec.short and not f.shortened and not InCombatLockdown() and f.hp:GetHeight() >= 28 then
			f.shortened = true
			local h = math.max(14, math.floor(f.hp:GetHeight() * spec.short + 0.5))
			f.hp:SetHeight(h)
			if f.hp.sheen then f.hp.sheen:SetHeight(math.max(2, h * 0.5)) end
			f:SetHeight(h + (f.power and (f.power:GetHeight() + 1) or 0))
		end
		local face = spec.font or FONT
		local flag = spec.fontFlag or "OUTLINE"
		local add = spec.fontAdd or 0
		if spec.card then
			f.hp:SetFrameLevel(f:GetFrameLevel() + 3)
			if f.power then f.power:SetFrameLevel(f:GetFrameLevel() + 3) end
		end
		skinBorder(f, spec, file)
		skinBar(f.hp, f, spec, file)
		if f.power then skinBar(f.power, f, spec, file) end
		-- Keep the health number clear of the bar's right end.
		f.text:ClearAllPoints()
		f.text:SetPoint("RIGHT", f.hp, "RIGHT", -math.floor(endInset(spec, f) + 8), 0)
		f.text:SetFont(face, f.cfg.font + (spec.font and 0 or 1) + add, flag)
		if f.ptext then
			f.ptext:ClearAllPoints()
			f.ptext:SetPoint("RIGHT", f.power, "RIGHT", -math.floor((spec.bar == "Slant" and LEAN * w or 2) + 4), 0)
			f.ptext:SetFont(face, 10 + math.min(add, 1), flag)
		end
		if f.name and f ~= player and not isTarget and not f.isParty then
			f.name:SetFont(face, f.cfg.font + add, flag)
		end
		-- The pet bar is short. The heavy font fills it with the health number
		-- and the name, anchored to that number, disappears.
		if spec.fontFlag == "THICKOUTLINE" and f.compact and f.name and f.unit ~= "targettarget" then
			f.text:SetFont(face, 11, "OUTLINE")
			f.name:SetFont(face, 11, "OUTLINE")
			f.name:SetWordWrap(false)
			f.name:ClearAllPoints()
			f.name:SetPoint("LEFT", f.hp, "LEFT", 7, 0)
			f.name:SetWidth(math.floor(w * 0.58))
			f.name:SetJustifyH("LEFT")
		end
		if f == player or isTarget or f.isParty then
			addPortrait(f, spec, isTarget)
			f.skinUpdate = skinUpdate
			local r = f.portraitSize / 2
			if spec.card then
				if isTarget then addCard(f, 9, math.floor(r + 6)) else addCard(f, math.floor(r + 6), 9) end
			end
			if isTarget then
				f.text:ClearAllPoints()
				f.text:SetPoint("RIGHT", f.hp, "RIGHT", -math.floor(r + 6), 0)
				local nameW = math.floor(w * 0.72)
				if spec.fontFlag == "THICKOUTLINE" then nameW = math.floor(w - r - 6) end
				placeName(f, spec, file, spec.name == "tab" and 4 or 0, nameW)
				if f.classEdge then for _, t in ipairs(f.classEdge) do t:Hide() end end
				f.classEdge = nil -- (the ring shows elite and rare instead)
			else
				-- Role / leader icons and the resting "zzz" move clear of the portrait.
				for i, t in ipairs(f.groupIcons) do
					t:ClearAllPoints()
					t:SetPoint("CENTER", f.hp, "TOPLEFT", r + 8 + (i - 1) * 13, 0)
				end
				if f.isParty then placeName(f, spec, file, math.floor(r + 2), math.floor(w * 0.62)) end
			end
		elseif f.unit == "targettarget" and f.name and spec.name == "tab" then
			-- Same width as the bar, so the slant lines up with it instead of
			-- hanging off the ends.
			placeName(f, spec, file, 0, w)
		elseif spec.card then
			addCard(f, 7, 7)
		end
	end
	rest:ClearAllPoints()
	rest:SetPoint("LEFT", player.hp, "LEFT", math.floor(player.portraitSize / 2 + 6), 0)
	-- Your buffs and debuffs start right of your portrait instead of over it.
	local pr = math.floor(player.portraitSize / 2 + 4)
	playerBuffs.x, playerDebuffs.x = pr, pr
	-- Room for the portraits: the pet and target-of-target boxes start clear of
	-- them (unless you moved those), and the party boxes sit further apart.
	LAYOUT.pet.x = LAYOUT.pet.x + 34
	LAYOUT.tot.x = LAYOUT.tot.x + 36
	-- (secure frames: only out of combat; a reload in combat leaves the old spacing)
	if not InCombatLockdown() then
		-- Keep the portraits and names on screen: the game only keeps a frame's
		-- own box on screen, and these stick out of it (left, right and top).
		local partyR = math.floor(party[1].portraitSize / 2 + 2)
		partyHolder:SetClampRectInsets(-partyR, 0, 16, 0)
		player:SetClampRectInsets(-pr, 0, 0, 0)
		target:SetClampRectInsets(0, math.floor(target.portraitSize / 2 + 2), 18, 0)
		local gap = spec.gap
		local ph = party[1]:GetHeight()
		for i = 1, 4 do
			party[i]:ClearAllPoints()
			party[i]:SetPoint("TOPLEFT", partyHolder, "TOPLEFT", 0, -(i - 1) * (ph + gap))
		end
		partyHolder:SetHeight(ph * 4 + gap * 3)
	end
	if spec.fontFlag then
		for _, grid in ipairs({ playerBuffs, playerDebuffs }) do
			local sz = grid.size < 22 and 11 or 13
			for _, b in ipairs(grid.buttons) do
				b.time:SetFont(spec.font or FONT, sz, spec.fontFlag)
				b.count:SetFont(spec.font or FONT, sz, spec.fontFlag)
			end
		end
	end
end
end -- frame styles

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local HEALTH = { UNIT_HEALTH = true, UNIT_MAXHEALTH = true, UNIT_HEALTH_FREQUENT = true }
local POWER = { UNIT_POWER_UPDATE = true, UNIT_POWER_FREQUENT = true, UNIT_MAXPOWER = true, UNIT_DISPLAYPOWER = true }

local ev = CreateFrame("Frame")
for _, e in ipairs({
	"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "GROUP_ROSTER_UPDATE",
	"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
	"UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEALTH_FREQUENT",
	"UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
	"UNIT_CONNECTION", "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION", "UNIT_FLAGS",
	"PLAYER_FLAGS_CHANGED",
	"UNIT_CLASSIFICATION_CHANGED", "PLAYER_UPDATE_RESTING", "PLAYER_LEVEL_UP",
	"UNIT_PET", "UNIT_HAPPINESS", "PET_UI_UPDATE", "UNIT_AURA", "UNIT_PET_EXPERIENCE", "UNIT_TARGET",
	"RAID_TARGET_UPDATE", "PARTY_LEADER_CHANGED", "PARTY_LOOT_METHOD_CHANGED", "PLAYER_ROLES_ASSIGNED",
	"UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED",
}) do
	pcall(ev.RegisterEvent, ev, e) -- some events don't exist on every client
end

-- Auras change many times a frame in a group fight: redraw each unit's icons
-- at most once per frame, on the next one.
local auraDirty, auraQueued = {}, false
local function auraFlush()
	auraQueued = false
	if auraDirty.pet then updatePetAuras() updateName(pet) end
	if auraDirty.target then updateTargetDebuffs() end
	if auraDirty.player then updatePlayerDebuffs() end
	wipe(auraDirty)
end
local function auraChanged(unit)
	auraDirty[unit] = true
	if not auraQueued then
		auraQueued = true
		C_Timer.After(0, auraFlush)
	end
end

-- Frames whose health / power bars need a redraw on the next frame (see dispatch).
local pendingBars = { health = {}, power = {}, queued = false }
pendingBars.flush = function()
	local p = pendingBars
	p.queued = false
	for f in pairs(p.health) do updateHealth(f) end
	for f in pairs(p.power) do updatePower(f, false) end
	wipe(p.health)
	wipe(p.power)
end

local function dispatch(f, event)
	if unlocked and not UnitExists(f.unit) then return end
	if HEALTH[event] or (POWER[event] and event ~= "UNIT_DISPLAYPOWER") then
		-- Health and power come as two events each (normal and "frequent"), many times a frame in a
		-- fight: redraw each frame's bars at most once, on the next frame.
		local p = pendingBars
		if HEALTH[event] then p.health[f] = true else p.power[f] = true end
		if not p.queued then
			p.queued = true
			C_Timer.After(0, p.flush)
		end
	elseif POWER[event] then
		updatePower(f, true)
	else
		updateAll(f, false)
	end
end

local function updateRaid(snap)
	styleNewRaidButtons()
	for _, b in ipairs(raidButtons) do
		if b.unit and b:IsShown() then updateAll(b, snap) end
	end
end

-- Turned off in the /zyde window: hide ours, leave Blizzard's alone (until
-- turned back on and /reload).
local function disableUnitFrames()
	UF.disabled = true
	ev:UnregisterAllEvents()
	for _, f in ipairs(frames) do
		if f.watched then UnregisterUnitWatch(f) end
		f:Hide()
	end
	partyHolder:Hide()
	raidHolder:Hide()
end

ev:SetScript("OnEvent", function(_, event, unit)
	if event == "PLAYER_LOGIN" then
		if not ns.F("unitFrames") then disableUnitFrames() return end
		UF.styleAtLoad = UF.GetStyle() -- (the /zyde window asks for a reload when it changes)
		UF.applySkin(UF.styleAtLoad)
		placeAll()
		applyTot()
		buildRaid()
		hideBlizzardUnitFrames()
		for _, f in ipairs(frames) do updateAll(f, true) end
		updateRaid(true)
		UF.UpdateCombat()
	elseif event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then
		buildRaid()
		hideBlizzardUnitFrames()
		for _, f in ipairs(frames) do updateAll(f, true) end
		updateRaid(true)
		updateResting()
		updatePlayerDebuffs()
		UF.UpdateCombat()
	elseif event == "RAID_TARGET_UPDATE" or event == "PARTY_LEADER_CHANGED"
		or event == "PARTY_LOOT_METHOD_CHANGED" or event == "PLAYER_ROLES_ASSIGNED" then
		-- Markers and group icons on every frame (these name no unit).
		for _, fr in ipairs(frames) do updateMark(fr) updateGroupIcons(fr) end
		for _, b in ipairs(raidButtons) do if b.unit then updateMark(b) updateGroupIcons(b) end end
	elseif event == "PLAYER_FLAGS_CHANGED" then
		updatePvP(player)
	elseif event == "PLAYER_UPDATE_RESTING" then
		updateResting()
	elseif event == "PLAYER_LEVEL_UP" then
		C_Timer.After(0.5, updateResting)
	elseif event == "PLAYER_TARGET_CHANGED" then
		updateAll(target, true)
		updateAll(tot, true)
		updateTargetDebuffs()
		updateCast()
	elseif event == "UNIT_PET" or event == "PET_UI_UPDATE" then
		-- Pet summoned, dismissed or swapped (UNIT_PET names its owner).
		if event == "PET_UI_UPDATE" or unit == "player" then updateAll(pet, true) updatePetAuras() end
	elseif event == "UNIT_PET_EXPERIENCE" then
		updatePetXP()
	elseif event == "UNIT_AURA" then
		if unit == "pet" or unit == "target" or unit == "player" then auraChanged(unit) end
	elseif event == "PLAYER_REGEN_DISABLED" then
		UF.Lock(true) -- frames can't move in combat
		UF.UpdateCombat(true)
	elseif event == "PLAYER_REGEN_ENABLED" then
		UF.UpdateCombat(false)
		if UF.pendingPlace then placeAll() end
		if UF.pendingTot then applyTot() end
		buildRaid()
		hideBlizzardUnitFrames()
		updateRaid(true)
	elseif event == "UNIT_TARGET" then
		if unit == "target" then updateAll(tot, true) end
	elseif unit then
		local f = byUnit[unit]
		if f then dispatch(f, event) end
		local r = raidByUnit[unit]
		if r and r ~= f then dispatch(r, event) end
	end
end)

-- Party and raid range fade.
if C_Timer and C_Timer.NewTicker then
	C_Timer.NewTicker(0.5, function()
		for i = 1, 4 do
			if party[i]:IsShown() then updateRange(party[i]) end
		end
		for _, b in ipairs(raidButtons) do
			if b.unit and b:IsShown() then updateRange(b) end
		end
		-- Pet mood can change without an event on this client: re-read it.
		if pet:IsShown() and UnitExists("pet") and not unlocked then updateName(pet) updatePetXP() end
		if player.combatOverlay then UF.UpdateCombat() end
		if player.pvp and not UF.disabled then updatePvP(player) end
	end)
end

-- The target of target frame and the buff / debuff icons turn on and off right away from the /zyde window.
ns.OnFeatureChanged(function(key)
	if key == "targetTarget" then applyTot() end
	if key == "unitAuras" and not UF.disabled then updateTargetDebuffs() updatePlayerDebuffs() updatePetAuras() end
end)
