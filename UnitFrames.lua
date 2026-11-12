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
	local c = GetCreatureDifficultyColor and GetCreatureDifficultyColor(lvl < 0 and 999 or lvl)
		or (GetQuestDifficultyColor and GetQuestDifficultyColor(lvl < 0 and 999 or lvl))
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

local function updateName(f)
	if not f.name or not UnitExists(f.unit) then return end
	local name = plain(UnitName(f.unit)) or ""
	if f.unit == "pet" then
		f.name:SetText(name)
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
	elseif f.isGroup then
		f.name:SetText(name)
	else
		f.name:SetText(levelText(f.unit) .. name)
	end
end

local function updateRange(f)
	if not f.isGroup or unlocked then f:SetAlpha(1) return end
	local inRange, checked = UnitInRange(f.unit)
	inRange, checked = plain(inRange), plain(checked)
	f:SetAlpha((checked and inRange == false) and 0.45 or 1)
end

local function updateAll(f, snap)
	if not f.unit or not f.hp then return end
	if unlocked and not UnitExists(f.unit) then return end
	updateHealth(f, snap)
	updatePower(f, snap)
	updateName(f)
	updateRange(f)
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

local target = createUnitFrame("ZydeForeverTargetFrame", "target", LAYOUT.target)
target.watched = true
target.name = makeText(target, 13)
target.name:SetPoint("BOTTOMLEFT", target, "TOPLEFT", 1, 4)
target.name:SetPoint("BOTTOMRIGHT", target, "TOPRIGHT", -1, 4)
target.name:SetJustifyH("LEFT")
target.name:SetWordWrap(false)

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
			if ownFirst and not plain(a.isFromPlayerOrPlayerPet) then
				others[#others + 1], othersAt[#others + 1] = a, i
			elseif n < grid.max then
				n = n + 1
				showAura(grid, n, a, i, true)
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
			b:SetPoint("BOTTOMLEFT", grid.owner, "TOPLEFT", 1 + col * step, base + row * grid.rowH)
		else
			b:SetPoint("TOPLEFT", grid.owner, "BOTTOMLEFT", 1 + col * step, -(base + row * grid.rowH))
		end
	end
	return n > 0 and math.ceil(n / grid.perRow) * grid.rowH or 0
end

-- Target: debuffs under the cast bar's spot (so they don't jump when a cast
-- starts), buffs above its name.
local targetDebuffs = auraGrid(target, "target", true, 24, 8, 16, false)
local targetBuffs = auraGrid(target, "target", false, 20, 10, 20, true)
-- Player: debuffs above your frame (the pet frame sits below it), buffs above those.
local playerDebuffs = auraGrid(player, "player", true, 24, 8, 16, true)
local playerBuffs = auraGrid(player, "player", false, 20, 10, 20, true)

local function updateTargetDebuffs()
	fillGrid(targetDebuffs, CAST_H + 9)
	fillGrid(targetBuffs, 22) -- (the name sits just above the frame)
end
local function updatePlayerDebuffs()
	local used = fillGrid(playerDebuffs, 16)
	fillGrid(playerBuffs, used + 4) -- (used includes the time under the top row)
end

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
	b.count = makeText(b, 10)
	b.count:SetPoint("BOTTOMRIGHT", 3, -2)
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

for _, f in ipairs(frames) do
	f:HookScript("OnShow", function(self) updateAll(self, true) end)
	if f.watched then RegisterUnitWatch(f) end
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
	"UNIT_CLASSIFICATION_CHANGED", "PLAYER_UPDATE_RESTING", "PLAYER_LEVEL_UP",
	"UNIT_PET", "UNIT_HAPPINESS", "PET_UI_UPDATE", "UNIT_AURA", "UNIT_PET_EXPERIENCE", "UNIT_TARGET",
}) do
	pcall(ev.RegisterEvent, ev, e) -- some events don't exist on every client
end

local function dispatch(f, event)
	if unlocked and not UnitExists(f.unit) then return end
	if HEALTH[event] then
		updateHealth(f)
	elseif POWER[event] then
		updatePower(f, event == "UNIT_DISPLAYPOWER")
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
		placeAll()
		applyTot()
		buildRaid()
		hideBlizzardUnitFrames()
		for _, f in ipairs(frames) do updateAll(f, true) end
		updateRaid(true)
	elseif event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then
		buildRaid()
		hideBlizzardUnitFrames()
		for _, f in ipairs(frames) do updateAll(f, true) end
		updateRaid(true)
		updateResting()
		updatePlayerDebuffs()
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
		if unit == "pet" then updatePetAuras() updateName(pet)
		elseif unit == "target" then updateTargetDebuffs()
		elseif unit == "player" then updatePlayerDebuffs() end
	elseif event == "PLAYER_REGEN_DISABLED" then
		UF.Lock(true) -- frames can't move in combat
	elseif event == "PLAYER_REGEN_ENABLED" then
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
	end)
end

-- The target of target frame and the buff / debuff icons turn on and off right away from the /zyde window.
ns.OnFeatureChanged(function(key)
	if key == "targetTarget" then applyTot() end
	if key == "unitAuras" and not UF.disabled then updateTargetDebuffs() updatePlayerDebuffs() updatePetAuras() end
end)
