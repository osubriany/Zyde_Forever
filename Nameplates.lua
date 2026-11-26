-- Zyde_Forever: flat nameplates for enemies, in the unit frames' style.
--   * a flat bar in the hostile / neutral / tapped color, thin dark outline; in a fight, by your
--     threat on it: green (safe / you hold it), yellow (about to pull), orange (losing it), red (on you).
--     Someone else's tag stays grey even when you have threat on it.
--   * your target's plate: a white edge, a little bigger (others a bit faded), its health % inside the bar
--   * the full name above it (smaller, so long names fit)
--   * a level badge on the left: difficulty color, "+" for elites, a silver
--     dragon for rares, a skull for bosses
--   * a cast bar under it while it casts: orange = you can interrupt, gray = you can't
--   * your own debuffs on it (Hunter's Mark, Serpent Sting, Sunder, Rend...) with time left
--   * aggro: a pulsing glow and "AGGRO" when a mob attacks you, "LOOSE" when you tank and one isn't on you (see updateThreat)
--   * bosses (dungeon and raid): a purple bar (see isBoss)
--   * warriors: the bar turns orange below 20% health (Execute range)
--   * quests (Questie): the quest icon, your count ("3/8") and the drop chance
--     together on the right, in place of Questie's own icon on the left
-- Friendly nameplates and object nameplates keep the game's look.
-- The game's own plate is only made invisible (not removed), so it keeps working underneath.
-- In dungeons and boss fights the game can hide health, threat and aura
-- details from addons: those parts then fall back to what the game will show.

local ADDON, ns = ...

local safe, isSecret = ns.safe, ns.isSecret
local function plain(v) if isSecret(v) then return nil end return v end
local function on() return ns.F("plates") end

local FLAT = "Interface\\Buttons\\WHITE8X8"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local W, H = 120, 10          -- bar size
local CAST_H = 8
local AURA, AURA_MAX = 16, 5  -- debuff icon size, how many
-- Demoralizing Shout is 45 seconds. Dungeon plates do not keep it on the game's
-- debuff row, so the cast itself puts the icon up. One row stays, so the cast
-- bar under the debuffs does not get covered.
local DEMO_SECONDS = 45
local demoSet = { [1160] = true, [6190] = true, [11554] = true, [11555] = true, [11556] = true, [25202] = true, [25203] = true, [47437] = true }
local demoOn = {} -- [mob GUID] = when your shout on it runs out (only mobs it reached, see markDemo)
local function demoLeft(f)
	local guid = f.unit and plain(UnitGUID(f.unit))
	local t = guid and demoOn[guid]
	return t and (t - GetTime()) or 0
end
local refreshAurasFor -- (updateAuras, set once it's defined below)

local COLOR = {
	hostile = { 0.78, 0.29, 0.23 }, neutral = { 0.88, 0.72, 0.27 }, friendly = { 0.55, 0.76, 0.35 },
	tapped = { 0.5, 0.5, 0.5 }, execute = { 1, 0.5, 0.1 }, boss = { 0.6, 0.25, 0.85 },
	-- in a fight, by your threat on it (UnitThreatSituation 0-3)
	threat = { [0] = { 0.25, 0.8, 0.3 }, [1] = { 0.95, 0.85, 0.2 }, [2] = { 1, 0.55, 0.1 }, [3] = { 0.85, 0.15, 0.12 } },
}
local EDGE = { 0, 0, 0, 0.9 }                 -- normal outline
local BOSS_EDGE = { 0.75, 0.35, 1, 1 }         -- a boss: purple outline, even in a fight
local SKULL = "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:12:12|t "
local THREAT_WARN = { 1, 0.6, 0.1, 1 }        -- orange
local THREAT_BAD = { 1, 0.15, 0.1, 1 }        -- red

local _, playerClass = UnitClass("player")
local IS_WARRIOR = playerClass == "WARRIOR"

local skinned = {}   -- unit token -> our frame
local frames = {}    -- plate -> our frame (kept and reused)

local function text(parent, size)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(FONT, size, "OUTLINE")
	fs:SetShadowColor(0, 0, 0, 0.6)
	fs:SetShadowOffset(1, -1)
	return fs
end

local function bar(parent, h)
	local b = CreateFrame("StatusBar", nil, parent)
	b:SetStatusBarTexture(FLAT)
	b:SetHeight(h)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.bg:SetColorTexture(0.05, 0.05, 0.05, 0.8)
	b.edges = ns.newEdges(b, "OVERLAY", 6)
	ns.placeEdges(b.edges, b, -1, 1)
	for _, t in ipairs(b.edges) do t:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], EDGE[4]) end
	return b
end

local function setEdge(b, c)
	if b.edgeColor == c then return end
	b.edgeColor = c
	for _, t in ipairs(b.edges) do t:SetColorTexture(c[1], c[2], c[3], c[4]) end
end

---------------------------------------------------------------------------
-- Combo points (rogues, druids in cat form): a row of pips on your target's
-- plate, just above the bar (the name moves up to make room). The pips fill
-- gold -> orange -> red, and glow all red once you're at the most you can hold.
-- Each pip is a tiny status bar (pip i fills when points >= i), so it still
-- works if the game ever hides the number from addons.
---------------------------------------------------------------------------
local makeCombo, updateCombo
do
	local CP = Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4
	local PIP_H, GAP, MAXPIPS = 5, 3, 7
	local FULL = { 1, 0.15, 0.1 }
	local function ramp(i, n)
		local t = n > 1 and (i - 1) / (n - 1) or 1
		return 1, 0.85 - 0.55 * t, 0.2 - 0.1 * t -- gold to orange-red
	end
	local function usesCombo()
		if playerClass == "ROGUE" then return true end
		if playerClass ~= "DRUID" then return false end
		return plain(UnitPowerType("player")) == (Enum and Enum.PowerType and Enum.PowerType.Energy or 3) -- cat form
	end

	makeCombo = function(f)
		local row = CreateFrame("Frame", nil, f)
		row:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 3)
		row:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 3)
		row:SetHeight(PIP_H)
		row.pips = {}
		for i = 1, MAXPIPS do
			local p = bar(row, PIP_H)
			p:SetMinMaxValues(i - 1, i)
			p:SetValue(0)
			p:Hide()
			row.pips[i] = p
		end
		row:Hide()
		f.combo = row
	end

	local function layout(row, n)
		if row.n == n then return end
		row.n = n
		local w = (W - GAP * (n - 1)) / n
		for i, p in ipairs(row.pips) do
			p:ClearAllPoints()
			if i <= n then
				p:SetWidth(w)
				p:SetPoint("LEFT", row, "LEFT", (i - 1) * (w + GAP), 0)
				p:SetStatusBarColor(ramp(i, n))
				p:Show()
			else
				p:Hide()
			end
		end
	end

	updateCombo = function(f)
		local row = f.combo
		if not row then return end
		local show = ns.F("comboPoints") and usesCombo() and plain(UnitIsUnit(f.unit, "target")) == true
		if show then
			local n = plain(UnitPowerMax("player", CP))
			if type(n) ~= "number" or n < 1 then n = 5 end
			layout(row, math.min(n, MAXPIPS))
			local pts = UnitPower("player", CP)
			if pts == nil and GetComboPoints then pts = GetComboPoints("player", "target") end
			local full = plain(pts) == row.n
			for i = 1, row.n do
				local p = row.pips[i]
				p:SetValue(pts or 0)
				if full then p:SetStatusBarColor(FULL[1], FULL[2], FULL[3]) else p:SetStatusBarColor(ramp(i, row.n)) end
			end
		end
		row:SetShown(show)
		f.name:ClearAllPoints()
		f.name:SetPoint("BOTTOM", f, "TOP", 0, show and (PIP_H + 6) or 3)
	end
end

---------------------------------------------------------------------------
-- Building one plate's frame
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Your debuffs through the game's aura container (clients with "secret" aura data, like Forever):
-- the addon only says which auras and where; the game fills in the icon, stacks and timer itself,
-- so it works in combat too, when addons may not read your target's auras. (Platynator does the
-- same.) Setting it up is refused in combat, so a plate built mid-fight gets it afterwards.
-- Without it: our own icons (out of combat) and the game's own debuff row (see updateAuras).
---------------------------------------------------------------------------
local USE_CONTAINER = C_Secrets and C_Secrets.HasSecretRestrictions and safe(C_Secrets.HasSecretRestrictions) and true or false

local function auraButton(b)
	b:SetSize(AURA, AURA)
	if b.EnableMouseMotion then pcall(b.EnableMouseMotion, b, false) end
	local border = b:CreateTexture(nil, "BACKGROUND", nil, -8)
	border:SetPoint("TOPLEFT", -1, 1)
	border:SetPoint("BOTTOMRIGHT", 1, -1)
	border:SetColorTexture(0, 0, 0, 1)
	local icon = b:CreateTexture(nil, "BACKGROUND", nil, -7)
	icon:SetAllPoints()
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b:SetIcon(icon)
	local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	cd:SetAllPoints()
	cd:SetFrameLevel(b:GetFrameLevel())
	cd:SetDrawEdge(false)
	cd:SetDrawBling(false)
	cd:SetReverse(true)
	if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
	b:SetDurationCooldown(cd)
	local time = text(b, 8)
	time:SetDrawLayer("OVERLAY", 6)
	time:SetPoint("BOTTOM", b, "BOTTOM", 1, 0)
	pcall(b.SetDurationText, b, time, {})
	local count = text(b, 10) -- stacks (Sunder 2-5)
	count:SetDrawLayer("OVERLAY", 7)
	count:SetPoint("TOPRIGHT", b, "TOPRIGHT", 2, 1)
	pcall(b.SetApplicationCount, b, count, {})
end

local function setupContainer(ac)
	if ac.ready then return true end
	if InCombatLockdown() then return false end
	local ok = pcall(function()
		ac:AddAuraGroup("1", "", { initializeFrame = auraButton })
		ac:SetAuraGroupLayout("1", { elementSpacing = 2, lineSpacing = 2 })
		ac:SetAuraGroupFilterString("1", "HARMFUL|PLAYER")
		ac:SetAuraGroupCandidateFilters("1", {})
		ac:SetAuraGroupMaxFrameCount("1", AURA_MAX)
		ac:SetAuraGroupEnabled("1", true)
		ac:SetFlowLayoutAnchorPoint("TOPLEFT")
		ac:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
	end)
	ac.ready = ok
	return ok
end

local function makeAuraContainer(f)
	if not USE_CONTAINER then return nil end
	local ok, ac = pcall(CreateFrame, "AuraContainer", nil, f, "CustomAuraContainerTemplate")
	if not ok or not ac then return nil end
	ac:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -7) -- right under the bar (clear of its outline)
	pcall(ac.SetEnabled, ac, false)
	setupContainer(ac)
	return ac
end

-- Point the plate's container at its unit (or off). True when the container shows the debuffs.
local function containerFor(f, unit)
	local ac = f.ac
	if not ac then return false end
	if not unit then
		pcall(ac.SetEnabled, ac, false)
		return false
	end
	if not setupContainer(ac) then return false end
	local ok = pcall(ac.SetUnit, ac, unit) and pcall(ac.SetEnabled, ac, true)
	return ok
end

local function build(plate)
	local f = CreateFrame("Frame", nil, plate)
	f:SetSize(W, H)
	f:SetPoint("CENTER", plate, "CENTER", 0, -5) -- (a little low: room between the name and the game's debuff row above it)
	f:SetFrameLevel(plate:GetFrameLevel() + 5)
	f:EnableMouse(false)

	f.hp = bar(f, H)
	f.hp:SetAllPoints()
	-- Aggro: a pulsing glow outside the bar and a word inside it (see updateThreat).
	f.aggro = CreateFrame("Frame", nil, f)
	f.aggro:SetAllPoints(f.hp)
	f.aggro:SetFrameLevel(f.hp:GetFrameLevel() + 3)
	f.aggro.edges = ns.newEdges(f.aggro, "OVERLAY", 7)
	ns.placeEdges(f.aggro.edges, f.aggro, -6, 2)
	f.aggro.tag = text(f.aggro, 8)
	f.aggro.tag:SetPoint("LEFT", f.aggro, "LEFT", 3, 0)
	f.aggro.pulse = f.aggro:CreateAnimationGroup()
	f.aggro.pulse:SetLooping("BOUNCE")
	do
		local a = f.aggro.pulse:CreateAnimation("Alpha")
		a:SetFromAlpha(1)
		a:SetToAlpha(0.35)
		a:SetDuration(0.5)
		a:SetSmoothing("IN_OUT")
	end
	f.aggro:Hide()
	-- Your target: a white edge just outside the bar (see updateTarget).
	f.sel = ns.newEdges(f.hp, "OVERLAY", 7)
	ns.placeEdges(f.sel, f.hp, -3, 2)
	for _, t in ipairs(f.sel) do t:SetColorTexture(1, 1, 1, 0.9) t:Hide() end
	-- Health % (your target's plate only), inside the bar on the right.
	f.pct = text(f.hp, 9)
	f.pct:SetPoint("RIGHT", f.hp, "RIGHT", -3, 0)
	f.pct:SetTextColor(1, 1, 1)

	f.name = text(f, 10)
	f.name:SetPoint("BOTTOM", f, "TOP", 0, 3)
	-- No fixed width. A width makes the line measure the text, and a hidden
	-- mob name cannot be measured, so the line comes out blank.
	f.name:SetWordWrap(false)
	f.name:SetTextColor(1, 1, 1)
	makeCombo(f)

	f.level = text(f, 10)
	f.level:SetPoint("RIGHT", f, "LEFT", -4, 0)
	f.dragon = f:CreateTexture(nil, "OVERLAY")
	f.dragon:SetSize(14, 14)
	f.dragon:SetPoint("RIGHT", f.level, "LEFT", 1, 0)
	f.dragon:Hide()
	-- Raid marker (skull, cross...), left of the level badge.
	f.mark = f:CreateTexture(nil, "OVERLAY")
	f.mark:SetSize(18, 18)
	f.mark:SetPoint("RIGHT", f, "LEFT", -38, 0)
	f.mark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	f.mark:Hide()

	-- Cast bar
	f.cast = bar(f, CAST_H)
	f.cast:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -(AURA + 11)) -- (below the debuff row)
	f.cast:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -(AURA + 11))
	f.cast.icon = f.cast:CreateTexture(nil, "OVERLAY")
	f.cast.icon:SetSize(CAST_H + 4, CAST_H + 4)
	f.cast.icon:SetPoint("RIGHT", f.cast, "LEFT", -2, 0)
	f.cast.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	f.cast.spell = text(f.cast, 8)
	f.cast.spell:SetPoint("LEFT", 3, 0)
	f.cast.spell:SetPoint("RIGHT", -3, 0)
	f.cast.spell:SetJustifyH("LEFT")
	f.cast.spell:SetWordWrap(false)
	f.cast:SetScript("OnUpdate", function(self)
		if not self.timed then return end
		local now = GetTime()
		if now >= self.endT then self:Hide() return end
		self:SetValue(self.channel and (self.endT - (now - self.startT)) or now)
	end)
	f.cast:Hide()

	-- Your debuffs, right under the bar (the cast bar shows below them)
	f.auras = {}
	for i = 1, AURA_MAX do
		local a = CreateFrame("Frame", nil, f)
		a:SetSize(AURA, AURA)
		a:SetPoint("TOPLEFT", f, "BOTTOMLEFT", (i - 1) * (AURA + 2), -7) -- (right under the bar, clear of its outline)
		a.border = a:CreateTexture(nil, "BACKGROUND")
		a.border:SetPoint("TOPLEFT", -1, 1)
		a.border:SetPoint("BOTTOMRIGHT", 1, -1)
		a.border:SetColorTexture(0, 0, 0, 1)
		a.icon = a:CreateTexture(nil, "ARTWORK")
		a.icon:SetAllPoints()
		a.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		a.cd = CreateFrame("Cooldown", nil, a, "CooldownFrameTemplate")
		a.cd:SetAllPoints()
		a.cd:SetDrawEdge(false)
		a.cd:SetReverse(true)
		if a.cd.SetHideCountdownNumbers then a.cd:SetHideCountdownNumbers(true) end
		local top = CreateFrame("Frame", nil, a)
		top:SetAllPoints()
		top:SetFrameLevel(a.cd:GetFrameLevel() + 2)
		a.time = text(top, 8)
		a.time:SetPoint("BOTTOM", a, "BOTTOM", 1, 0)
		a.count = text(top, 10) -- stacks (Sunder 1-5): bigger than the timer
		a.count:SetPoint("TOPRIGHT", a, "TOPRIGHT", 2, 1)
		a:SetScript("OnUpdate", function(self, elapsed)
			self.tick = (self.tick or 0) + elapsed
			if self.tick < 0.2 then return end
			self.tick = 0
			if not self.expires then self.time:SetText("") return end
			local left = self.expires - GetTime()
			if left <= 0 then self.time:SetText("")
			elseif left < 10 then self.time:SetFormattedText("%.0f", math.ceil(left)) self.time:SetTextColor(1, 0.35, 0.3)
			elseif left < 60 then self.time:SetFormattedText("%d", left) self.time:SetTextColor(1, 1, 1)
			else self.time:SetFormattedText("%dm", math.ceil(left / 60)) self.time:SetTextColor(1, 1, 1) end
		end)
		a:Hide()
		f.auras[i] = a
	end
	f.ac = makeAuraContainer(f)
	local s = CreateFrame("Frame", nil, f)
	s:SetSize(AURA, AURA)
	s:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -7)
	s:SetFrameLevel(f:GetFrameLevel() + 40)
	s.border = s:CreateTexture(nil, "BACKGROUND")
	s.border:SetPoint("TOPLEFT", -1, 1)
	s.border:SetPoint("BOTTOMRIGHT", 1, -1)
	s.border:SetColorTexture(0, 0, 0, 1)
	s.icon = s:CreateTexture(nil, "ARTWORK")
	s.icon:SetAllPoints()
	s.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	s.icon:SetTexture("Interface\\Icons\\Ability_Warrior_WarCry")
	local top = CreateFrame("Frame", nil, s)
	top:SetAllPoints()
	top:SetFrameLevel(s:GetFrameLevel() + 2)
	s.time = text(top, 8)
	s.time:SetPoint("BOTTOM", s, "BOTTOM", 1, 0)
	s:SetScript("OnUpdate", function(self, elapsed)
		self.tick = (self.tick or 0) + elapsed
		if self.tick < 0.2 then return end
		self.tick = 0
		local left = demoLeft(f)
		if left <= 0 then self:Hide() if refreshAurasFor then refreshAurasFor(f) end return end
		if left < 10 then self.time:SetFormattedText("%.0f", math.ceil(left)) self.time:SetTextColor(1, 0.35, 0.3)
		else self.time:SetFormattedText("%d", left) self.time:SetTextColor(1, 1, 1) end
	end)
	s:Hide()
	f.shout = s

	-- Quest corner: icon, count, drop chance (right of the bar)
	f.quest = CreateFrame("Frame", nil, f)
	f.quest:SetSize(1, H)
	f.quest:SetPoint("LEFT", f, "RIGHT", 4, 0)
	f.quest.icon = f.quest:CreateTexture(nil, "OVERLAY")
	f.quest.icon:SetSize(14, 14)
	f.quest.icon:SetPoint("LEFT", f.quest, "LEFT", 0, 0)
	f.quest.count = text(f.quest, 9)
	f.quest.count:SetPoint("LEFT", f.quest.icon, "RIGHT", 2, 0)
	f.quest.count:SetTextColor(1, 0.82, 0.2)
	f.quest.drop = text(f.quest, 8)
	f.quest.drop:SetPoint("TOPLEFT", f.quest.count, "BOTTOMLEFT", 0, -1)
	f.quest:Hide()

	f:Hide()
	frames[plate] = f
	plate.zydePlate = f -- (for the quest mob glow in QuestMobs.lua)
	return f
end

---------------------------------------------------------------------------
-- Updating the parts
---------------------------------------------------------------------------
-- Someone else tagged it, so you get no credit. A party tag counts as yours.
-- A mob that pays everyone on the threat list counts as yours too.
local function notMyTap(unit)
	local denied = UnitIsTapDenied and UnitIsTapDenied(unit)
	if not isSecret(denied) and denied then return true end
	local tapped = UnitIsTapped and UnitIsTapped(unit)
	if isSecret(tapped) or not tapped then return false end
	local mine = UnitIsTappedByPlayer and UnitIsTappedByPlayer(unit)
	if isSecret(mine) then return false end
	if mine then return false end
	-- In a group, "tapped, but not by you" is usually a party member's tag:
	-- UnitIsTappedByPlayer only answers for you. Tap-denied already said no,
	-- so it's the group's. (The checks below are for solo play.)
	local grouped = IsInGroup and IsInGroup()
	if not isSecret(denied) and denied == false and not isSecret(grouped) and grouped then return false end
	local everyone = UnitIsTappedByAllThreatList and UnitIsTappedByAllThreatList(unit)
	if not isSecret(everyone) and everyone then return false end
	return true
end

local function reactionColor(unit)
	if notMyTap(unit) then return COLOR.tapped end
	local r = plain(UnitReaction(unit, "player"))
	if r then
		if r <= 3 then return COLOR.hostile end
		if r == 4 then return COLOR.neutral end
		return COLOR.friendly
	end
	return COLOR.hostile
end

-- Health % with one decimal, on your target's plate only. When the game hides
-- the numbers, it can still work the percentage out for us.
local function updatePct(f, cur, maxv)
	if not plain(UnitIsUnit(f.unit, "target")) then f.pct:SetText("") return end
	if plain(UnitIsDeadOrGhost(f.unit)) then f.pct:SetText("") return end
	if not isSecret(cur) and not isSecret(maxv) then
		f.pct:SetFormattedText("%.1f%%", (maxv and maxv > 0) and (cur or 0) / maxv * 100 or 0)
		return
	end
	local pct = UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100
		and safe(UnitHealthPercent, f.unit, false, CurveConstants.ScaleTo100)
	if pct == nil or not pcall(f.pct.SetFormattedText, f.pct, "%.1f%%", pct) then f.pct:SetText("") end
end

-- Smooth bars: the bar eases toward the new health every frame (down and up),
-- like the unit frames. A new mob on the plate snaps straight to its health.
-- Hidden ("secret") numbers can't be eased by us: the game's own smoothing then.
local INTERP = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
local SPEED = 6 -- higher = faster catch-up
local easing = {}
local easer = CreateFrame("Frame")
easer:Hide()
easer:SetScript("OnUpdate", function(self, elapsed)
	local k = math.min(1, elapsed * SPEED)
	local busy = false
	for b in pairs(easing) do
		local diff = b.goal - b.cur
		if math.abs(diff) <= b.maxv * 0.002 then
			b.cur = b.goal
			easing[b] = nil
		else
			b.cur = b.cur + diff * k
			busy = true
		end
		b:SetValue(b.cur)
	end
	if not busy then self:Hide() end
end)

local function setHealthBar(b, cur, maxv, snap)
	if isSecret(cur) or isSecret(maxv) then
		easing[b], b.cur = nil, nil
		pcall(b.SetMinMaxValues, b, 0, maxv)
		if INTERP and not snap then
			if not pcall(b.SetValue, b, cur, INTERP) then pcall(b.SetValue, b, cur) end
		else
			pcall(b.SetValue, b, cur)
		end
		return
	end
	maxv = (maxv and maxv > 0) and maxv or 1
	cur = cur or 0
	b.maxv = maxv
	b:SetMinMaxValues(0, maxv)
	if snap or b.cur == nil then
		b.cur, b.goal = cur, cur
		easing[b] = nil
		b:SetValue(cur)
		return
	end
	b.goal = cur
	if b.cur ~= cur then
		easing[b] = true
		easer:Show()
	end
end

-- Bosses (dungeon and raid): purple bar. A boss is a skull-level or "world
-- boss" mob, one the game calls a boss, one in the boss frames during an
-- encounter, or one in GearAdvisor's boss list (every dungeon boss, by NPC ID
-- and name: most Classic dungeon bosses are just "elite" to the game).
local bossNpc, bossName
local function bossLists()
	if bossNpc then return end
	bossNpc, bossName = {}, {}
	local GA = ns.GA
	for _, d in ipairs(GA and GA.BossLoot and GA.BossLoot.dungeons or {}) do
		for _, b in ipairs(d.bosses or {}) do
			if b.npc then bossNpc[b.npc] = true end
			if type(b.name) == "string" then bossName[b.name:lower()] = true end
		end
	end
end

local function isBoss(unit)
	local class = plain(UnitClassification(unit))
	local lvl = plain(UnitLevel(unit))
	if class == "worldboss" or (lvl and lvl < 0) then return true end
	if UnitIsBossMob and plain(safe(UnitIsBossMob, unit)) == true then return true end
	-- The game's boss units during an encounter. In a dungeon "is it the same mob?" comes back hidden,
	-- so compare nameplates instead: the plate the game gives for boss1-5 against this mob's plate.
	local getPlate = C_NamePlate and C_NamePlate.GetNamePlateForUnit
	local mine = getPlate and safe(getPlate, unit)
	for i = 1, 5 do
		local b = "boss" .. i
		if plain(UnitExists(b)) then
			if plain(UnitIsUnit(unit, b)) then return true end
			if mine and safe(getPlate, b) == mine then return true end
		end
	end
	bossLists()
	local guid = plain(safe(UnitGUID, unit))
	if type(guid) == "string" then
		local kind, _, _, _, _, id = strsplit("-", guid)
		if (kind == "Creature" or kind == "Vehicle") and bossNpc[tonumber(id) or 0] then return true end
	end
	local name = plain(UnitName(unit))
	if type(name) == "string" and bossName[name:lower()] then
		-- (by name only inside a dungeon or raid: some boss names are common words)
		local _, kind = IsInInstance()
		if kind == "party" or kind == "raid" then return true end
	end
	return false
end

-- /zyde bossdebug: what the game tells addons about your target, for the boss check.
function ns.BossDebug()
	local u = "target"
	local P = "|cff66ccffZyde_Forever|r bossdebug: "
	if not UnitExists(u) then print(P .. "target a mob first") return end
	local function show(label, v)
		local s = isSecret(v) and "|cffff6650hidden from addons|r" or tostring(v)
		print(P .. label .. " = " .. s)
	end
	show("name", UnitName(u))
	show("GUID", safe(UnitGUID, u))
	show("level", UnitLevel(u))
	show("classification", UnitClassification(u))
	if UnitIsBossMob then show("UnitIsBossMob", safe(UnitIsBossMob, u)) end
	local getPlate = C_NamePlate and C_NamePlate.GetNamePlateForUnit
	for i = 1, 5 do
		if UnitExists("boss" .. i) then
			show("is boss" .. i, UnitIsUnit(u, "boss" .. i))
			local p = getPlate and safe(getPlate, "boss" .. i)
			show("boss" .. i .. " plate is the target's plate", p ~= nil and p == (getPlate and safe(getPlate, u)))
		else
			if i == 1 then print(P .. "no boss units right now (they appear once a boss fight starts)") end
		end
	end
	local _, kind = IsInInstance()
	show("instance", kind)
	print(P .. "counted as a boss: " .. tostring(isBoss(u)))
end

-- A mob in a fight: coloured by your threat on it. Green 0 (safe, or you hold it), yellow 1 (about
-- to pull it), orange 2 (tanking, about to lose it), red 3 (it's on you). Someone else's tag
-- stays grey no matter the threat number. nil when it isn't fighting, or the game won't say.
local function threatColor(unit)
	if not plain(UnitAffectingCombat(unit)) then return nil end
	if notMyTap(unit) then return COLOR.tapped end
	local status = UnitThreatSituation and plain(UnitThreatSituation("player", unit))
	return status and COLOR.threat[status] or nil
end

local function barColor(f, cur, maxv)
	local unit = f.unit
	local c = threatColor(unit)
	if not c then
		c = reactionColor(unit)
		if f.boss and c ~= COLOR.tapped then c = COLOR.boss end
	end
	-- Warriors: Execute range.
	if IS_WARRIOR and not isSecret(cur) and not isSecret(maxv) and cur and maxv and maxv > 0
		and cur > 0 and cur / maxv < 0.2 and c ~= COLOR.tapped then
		c = COLOR.execute
	end
	f.hp:SetStatusBarColor(c[1], c[2], c[3])
end

local function updateHealth(f, snap)
	local cur, maxv = UnitHealth(f.unit), UnitHealthMax(f.unit)
	updatePct(f, cur, maxv)
	setHealthBar(f.hp, cur, maxv, snap)
	barColor(f, cur, maxv)
end

-- The game's own plate shows raid markers, but it's invisible: show it here.
local function updateMark(f)
	if ns.applyMark then ns.applyMark(f.mark, f.unit) end
end

local function updateName(f)
	local unit = f.unit
	updateMark(f)
	-- Same as any unit frame: hand the name to the font. A hidden name still
	-- draws. Reading it, or building a new string out of it, blanks the line.
	-- Don't touch the game's own name from here. Moving or fading it makes the
	-- plate update again, and that loop hits the script limit.
	f.name:Show()
	local raw = UnitName(unit)
	if isSecret(raw) then
		-- No width. Measuring a hidden name to fit a width hits the script limit.
		local cur = f.name:GetText()
		if not isSecret(cur) then f.name:SetWidth(0) end
		f.name:SetText(raw)
	elseif f.boss and type(raw) == "string" then
		f.name:SetText(SKULL .. raw)
	else
		f.name:SetText(type(raw) == "string" and raw or "")
	end
	-- a boss: the name in purple (the bar colour shows threat in a fight)
	if f.boss then
		f.name:SetTextColor(0.85, 0.6, 1)
	else
		f.name:SetTextColor(1, 1, 1)
	end
	local lvl = plain(UnitLevel(unit))
	local class = plain(UnitClassification(unit))
	f.dragon:Hide()
	if not lvl then f.level:SetText("") return end
	local boss = lvl < 0 or class == "worldboss"
	local txt = boss and "??" or tostring(lvl)
	if class == "elite" or class == "rareelite" then txt = txt .. "+" end
	local c = ns.levelColor(boss and -1 or lvl) -- (Classic's rules, like Blizzard's frames)
	f.level:SetText(txt)
	if c then f.level:SetTextColor(c.r, c.g, c.b) else f.level:SetTextColor(1, 0.82, 0) end
	if boss then
		f.level:SetText("")
		f.dragon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
		f.dragon:SetTexCoord(0, 1, 0, 1)
		f.dragon:ClearAllPoints()
		f.dragon:SetPoint("RIGHT", f, "LEFT", -3, 0)
		f.dragon:Show()
	elseif class == "rare" or class == "rareelite" then
		if not (f.dragon.SetAtlas and f.dragon:SetAtlas("nameplates-icon-elite-silver")) then
			f.dragon:SetTexture("Interface\\Tooltips\\EliteNameplateIcon")
			f.dragon:SetDesaturated(true)
		end
		f.dragon:ClearAllPoints()
		f.dragon:SetPoint("RIGHT", f.level, "LEFT", 1, 0)
		f.dragon:Show()
	end
end

local function castInfo(unit)
	local name, _, icon, startMS, endMS, _, _, notInterruptible = safe(UnitCastingInfo, unit)
	if name then return name, icon, startMS, endMS, notInterruptible, false end
	local cname, _, cicon, cstart, cend, _, cNot = safe(UnitChannelInfo, unit)
	if cname then return cname, cicon, cstart, cend, cNot, true end
end

local function updateCast(f)
	local cb = f.cast
	if not UnitCastingInfo then cb:Hide() return end
	local name, icon, startMS, endMS, notInterruptible, channel = castInfo(f.unit)
	if not name then cb:Hide() return end
	cb.channel = channel
	if not pcall(cb.spell.SetText, cb.spell, name) then cb.spell:SetText("") end
	if not pcall(cb.icon.SetTexture, cb.icon, icon) then cb.icon:SetTexture(nil) end
	if plain(notInterruptible) then cb:SetStatusBarColor(0.55, 0.55, 0.55) else cb:SetStatusBarColor(1, 0.6, 0.15) end
	startMS, endMS = plain(startMS), plain(endMS)
	if startMS and endMS and endMS > startMS then
		cb.startT, cb.endT, cb.timed = startMS / 1000, endMS / 1000, true
		cb:SetMinMaxValues(cb.startT, cb.endT)
	else
		cb.timed = false
		local dur = (channel and UnitChannelDuration or UnitCastingDuration)
		dur = dur and safe(dur, f.unit)
		if not (dur and cb.SetTimerDuration and pcall(cb.SetTimerDuration, cb, dur)) then
			cb:SetMinMaxValues(0, 1)
			cb:SetValue(1)
		end
	end
	cb:Show()
end

-- The game's own debuff row on its plate: it can still read your debuffs in
-- combat when addons can't, so it's kept visible (where the game puts it) while the
-- rest of the game's plate is invisible. Our own icons are the fallback.
local function blizzAuraFrame(plate)
	local uf = plate.UnitFrame
	return uf and (uf.AurasFrame or uf.BuffFrame) or nil
end
ns.PlateAuraFrame = blizzAuraFrame -- (for /zyde auradebug)

-- Our own icons are used whenever the game lets addons read your debuffs (they sit a little higher
-- and show stacks); the game's row is shown only while it won't (on Forever: your target, in combat).
local function takeBlizzAuras(f)
	local c = blizzAuraFrame(f.plate)
	f.blizzAuras = (c and c.SetIgnoreParentAlpha) and c or nil
end

-- Only made visible or invisible: the game won't let addons measure or move parts of its
-- nameplates ("restricted regions"), so it stays where the game puts it, above the plate.
local function showBlizzAuras(f, show)
	local c = f.blizzAuras
	if c and f.blizzShown ~= show then
		c:SetIgnoreParentAlpha(show)
		f.blizzShown = show
	end
end

local function giveBackBlizzAuras(f)
	showBlizzAuras(f, false)
	f.blizzAuras, f.blizzShown = nil, nil
end

-- A stack count as the game will show it (the number can be hidden from addons in a fight).
local function stackText(unit, a)
	local stacks = plain(a.applications)
	if stacks then return stacks > 1 and tostring(stacks) or "" end
	local id = plain(a.auraInstanceID)
	if id and C_UnitAuras.GetAuraApplicationDisplayCount then
		local ok, s = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, id, 2, 99)
		if ok then return s end
	end
	return ""
end

local function placeAuraRow(f)
	local shift = (f.shout and f.shout:IsShown()) and (AURA + 2) or 0
	if f.ac then
		f.ac:ClearAllPoints()
		f.ac:SetPoint("TOPLEFT", f, "BOTTOMLEFT", shift, -7)
	end
	for i = 1, AURA_MAX do
		local a = f.auras[i]
		if a then a:SetPoint("TOPLEFT", f, "BOTTOMLEFT", shift + (i - 1) * (AURA + 2), -7) end
	end
end

-- The shout icon only on mobs your shout reached, and the game's own copy of the debuff is
-- left out of the plate's aura row only while ours shows (so after our 45 s, a shout still on
-- the mob - refreshed, or another warrior's - shows again).
local function updateShout(f)
	local b = f.shout
	if not b then return end
	local on = demoLeft(f) > 0
	if on then b:Show() else b:Hide() end
	if f.ac and (f.demoFiltered or false) ~= on then
		local ok = pcall(f.ac.SetAuraGroupCandidateFilters, f.ac, "1", on and { excludeSpellIDs = demoSet } or {})
		if ok then f.demoFiltered = on end
	end
	placeAuraRow(f)
end

local function updateAuras(f)
	updateShout(f)
	if f.useAC then -- (the game's container draws them, see makeAuraContainer)
		for i = 1, AURA_MAX do f.auras[i]:Hide() end
		showBlizzAuras(f, false)
		return
	end
	local n, unit = 0, f.unit
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		-- can we read them? (in a fight Forever may refuse: "Auras cannot be accessed when secret")
		local ok = pcall(C_UnitAuras.GetAuraDataByIndex, unit, 1, "HARMFUL|PLAYER")
		if not ok and f.blizzAuras then
			for i = 1, AURA_MAX do f.auras[i]:Hide() end
			showBlizzAuras(f, true)
			return
		end
		showBlizzAuras(f, false)
		for i = 1, 40 do
			if n >= AURA_MAX then break end
			local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HARMFUL|PLAYER")
			if not ok or not a then break end
			local spellId, name = plain(a.spellId), plain(a.name)
			if f.shout:IsShown() and ((spellId and demoSet[spellId]) or name == "Demoralizing Shout") then
			else
			n = n + 1
			local b = f.auras[n]
			if not pcall(b.icon.SetTexture, b.icon, a.icon) then b.icon:SetTexture(134400) end
			if not pcall(b.count.SetText, b.count, stackText(unit, a)) then b.count:SetText("") end
			local exp, dur = plain(a.expirationTime), plain(a.duration)
			if exp and dur and exp > 0 and dur > 0 then
				b.expires = exp
				b.cd:SetCooldown(exp - dur, dur)
				b.cd:Show()
			else
				b.expires = nil
				b.time:SetText("")
				local id = plain(a.auraInstanceID)
				local d = id and C_UnitAuras.GetAuraDuration and safe(C_UnitAuras.GetAuraDuration, unit, id)
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
	for i = n + 1, AURA_MAX do f.auras[i]:Hide() end
end

refreshAurasFor = updateAuras

local function spellNameOf(id)
	local name = (C_Spell and C_Spell.GetSpellName and plain(safe(C_Spell.GetSpellName, id)))
		or (GetSpellInfo and plain(safe(GetSpellInfo, id)))
	return type(name) == "string" and name or nil
end

-- Which mobs did the shout reach? Its debuff on them when the game shows it; when the game
-- hides their debuffs, an enemy within the shout's 10 yards that's fighting. Checked a moment
-- after the cast, so the debuff is on.
local function shoutReached(unit)
	if plain(UnitCanAttack("player", unit)) ~= true then return false end
	local hidden = false
	for i = 1, 40 do
		local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HARMFUL|PLAYER")
		if not ok or not a then break end
		local id, name = plain(a.spellId), plain(a.name)
		if id == nil and name == nil then hidden = true end
		if (id and demoSet[id]) or name == "Demoralizing Shout" then return true end
	end
	if not hidden then return false end
	local near = plain(safe(CheckInteractDistance, unit, 3)) -- (about 10 yards)
	if near ~= nil then return near == true or near == 1 end
	return plain(UnitAffectingCombat(unit)) == true
end

local function markDemo(spellID)
	if type(spellID) == "number" then demoSet[spellID] = true end
	C_Timer.After(0.2, function()
		local now = GetTime()
		for guid, t in pairs(demoOn) do if t <= now then demoOn[guid] = nil end end
		for unit, f in pairs(skinned) do
			local guid = plain(UnitGUID(unit))
			if guid and shoutReached(unit) then demoOn[guid] = now + DEMO_SECONDS end
			updateAuras(f)
		end
	end)
end

local demoEv = CreateFrame("Frame")
demoEv:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
demoEv:SetScript("OnEvent", function(_, _, ...)
	local hitId
	for i = 1, select("#", ...) do
		local v = plain(select(i, ...))
		if type(v) == "number" and (demoSet[v] or spellNameOf(v) == "Demoralizing Shout") then
			hitId = v
		elseif v == "Demoralizing Shout" then
			hitId = hitId or true
		end
	end
	if hitId then markDemo(type(hitId) == "number" and hitId or nil) end
end)

-- You're the tank: the group's tank role, or a warrior in Defensive Stance.
local function tanking()
	local role = UnitGroupRolesAssigned and plain(UnitGroupRolesAssigned("player"))
	if role == "TANK" then return true end
	if IS_WARRIOR then return plain(GetShapeshiftForm and GetShapeshiftForm()) == 2 end
	return false
end

-- Threat: who the mob is after, from your side.
--   Not tanking: "AGGRO" when it's attacking you (orange "AGGRO?" when it's
--   about to). In a group, or solo with a pet out (your pet should hold it).
--   Tanking (tank role, or a warrior in Defensive Stance), in a group: "LOOSE"
--   when a mob fighting your group isn't attacking you.
-- Shown as a pulsing glow around the bar and the word inside it, plus the
-- outline color.
local function fightingUs(unit)
	-- Its target is you, your pet or someone in your group.
	local t = unit .. "target"
	if not UnitExists(t) then return false end
	if plain(UnitIsUnit(t, "player")) or plain(UnitIsUnit(t, "pet")) then return true end
	return plain(UnitInParty(t)) == true or plain(UnitInRaid(t)) ~= nil
end

local function setAggro(f, text, c)
	local a = f.aggro
	if not text then
		if a:IsShown() then a.pulse:Stop() a:Hide() end
		return
	end
	for _, t in ipairs(a.edges) do t:SetColorTexture(c[1], c[2], c[3], 1) end
	a.tag:SetText(text)
	a.tag:SetTextColor(1, 1, 1)
	if not a:IsShown() then a:Show() a.pulse:Play() end
end

local function updateThreat(f)
	local unit = f.unit
	local c, text = f.boss and BOSS_EDGE or EDGE, nil
	local grouped = IsInGroup()
	if plain(UnitAffectingCombat(unit)) and (grouped or UnitExists("pet")) then
		local status = UnitThreatSituation and plain(UnitThreatSituation("player", unit))
		if tanking() and grouped then
			-- 3 = it's on you, safely. Anything else: it's on someone else.
			if status == 2 then c, text = THREAT_WARN, "LOOSE"
			elseif (status == nil or status < 2) and fightingUs(unit) then c, text = THREAT_BAD, "LOOSE" end
		elseif not tanking() then
			if status == 3 then c, text = THREAT_BAD, "AGGRO"
			elseif status == 2 then c, text = THREAT_WARN, "AGGRO?" end
		end
	end
	setEdge(f.hp, c)
	setAggro(f, text, c)
	barColor(f, UnitHealth(unit), UnitHealthMax(unit)) -- (threat changed: the bar colour too)
end

---------------------------------------------------------------------------
-- Quest corner (Questie): the quest icon, your count and the drop chance.
-- Questie's own icon on the plate is made invisible while ours shows.
---------------------------------------------------------------------------
local TT
local questCache = {} -- npcId -> { icon, count, drop } or false (cleared on quest changes, every 2 s)

local function npcFromGUID(guid)
	guid = plain(guid)
	if type(guid) ~= "string" then return nil end
	local kind, _, _, _, _, id = strsplit("-", guid)
	if (kind ~= "Creature" and kind ~= "Vehicle") or not id then return nil end
	return tonumber(id)
end

local function questFor(npcId)
	if not npcId or not TT then return nil end
	local v = questCache[npcId]
	if v ~= nil then return v or nil end
	v = false
	local tips = TT.lookupByKey and TT.lookupByKey["m_" .. npcId]
	for _, tip in pairs(tips or {}) do
		local obj = tip.objective
		if obj then
			if obj.Update then pcall(obj.Update, obj) end
			if not obj.Completed then
				local Q = _G.Questie
				local icons = Q and Q.icons or {}
				local isItem = obj.Type == "item"
				local need, have = tonumber(obj.Needed), tonumber(obj.Collected)
				v = {
					icon = isItem and (icons.loot or "Interface\\Icons\\INV_Misc_Bag_10") or (icons.slay or "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"),
					count = (need and need > 1 and have) and (have .. "/" .. need) or nil,
				}
				if ns.QuestieDrops and ns.QuestieDrops.best then
					local rate, odds = ns.QuestieDrops.best(npcId)
					if rate then v.drop, v.dropRate, v.odds = rate, rate, odds end
				end
				break
			end
		end
	end
	questCache[npcId] = v
	return v or nil
end

-- Questie's icon frame on a plate: a child with .Icon and .lastIcon.
local function questieIcon(plate)
	for _, child in ipairs({ plate:GetChildren() }) do
		if child.Icon and child.lastIcon then return child end
	end
end

local function updateQuest(f)
	local q = questFor(npcFromGUID(safe(UnitGUID, f.unit)))
	local qi = questieIcon(f.plate)
	if qi then qi:SetAlpha(q and 0 or 1) end
	if not q then f.quest:Hide() return end
	f.quest.icon:SetTexture(q.icon)
	f.quest.count:SetText(q.count or "")
	if q.drop and ns.F("questieDrops") then
		local r = q.drop
		local fmt = r >= 10 and "%.0f%%" or (r >= 2 and "%.1f%%" or "%.2f%%")
		f.quest.drop:SetFormattedText(fmt, r)
		if r >= 25 then f.quest.drop:SetTextColor(0.45, 1, 0.45)
		elseif r >= 5 then f.quest.drop:SetTextColor(1, 0.85, 0.3)
		else f.quest.drop:SetTextColor(1, 0.5, 0.35) end
		if q.odds then f.quest.drop:SetText(f.quest.drop:GetText() .. "  |cffcccccc" .. q.odds .. "|r") end
		f.quest.drop:Show()
	else
		f.quest.drop:Hide()
	end
	-- Count on the icon's line; with no count, the drop chance moves up beside the icon.
	f.quest.drop:ClearAllPoints()
	if q.count then
		f.quest.drop:SetPoint("TOPLEFT", f.quest.count, "BOTTOMLEFT", 0, -1)
	else
		f.quest.drop:SetPoint("LEFT", f.quest.icon, "RIGHT", 2, 0)
	end
	f.quest:Show()
end

---------------------------------------------------------------------------
-- Skinning plates as they come and go
---------------------------------------------------------------------------
-- The game fades these back in (on target, threat, health), and some of them
-- ignore the plate's alpha, so each one is held at 0. Alpha only: moving the
-- name is what hit the script limit. The debuff row is left alone.
local HIDE_PARTS = {
	"HealthBarsContainer", "healthBar", "HealthBar",
	"CastBarsContainer", "castBar", "CastBar",
	"PlayerLevelDiffFrame", "LevelFrame", "ClassificationFrame",
	"selectionHighlight", "aggroHighlight", "RaidTargetFrame", "name",
}

local function keepHidden(region, hide)
	if not region or not region.SetAlpha then return end
	region.zydeHidden = hide
	if not region.zydeAlphaHook and hooksecurefunc then
		region.zydeAlphaHook = true
		hooksecurefunc(region, "SetAlpha", function(self, a)
			if self.zydeHidden and a ~= 0 and not self.zydeSetting then
				self.zydeSetting = true
				self:SetAlpha(0)
				self.zydeSetting = nil
			end
		end)
	end
	if not region.zydeSetting then
		region.zydeSetting = true
		region:SetAlpha(hide and 0 or 1)
		region.zydeSetting = nil
	end
end

local function hideBlizzard(plate, hide)
	local uf = plate.UnitFrame
	if not uf then return end
	keepHidden(uf, hide)
	for i = 1, #HIDE_PARTS do
		keepHidden(uf[HIDE_PARTS[i]], hide)
	end
end

-- Enemies and neutral mobs only: not you, not friends, not objects.
local function wants(unit)
	if plain(UnitIsUnit(unit, "player")) then return false end
	if plain(UnitIsFriend("player", unit)) == true then return false end
	if UnitIsGameObject and plain(safe(UnitIsGameObject, unit)) == true then return false end
	local guid = plain(safe(UnitGUID, unit))
	if guid and guid:find("^GameObject") then return false end
	return true
end

local function unskin(unit)
	local f = skinned[unit]
	if not f then return end
	skinned[unit] = nil
	f.unit = nil
	f:Hide()
	easing[f.hp], f.hp.cur = nil, nil
	containerFor(f, nil)
	f.useAC = nil
	if f.plate then
		giveBackBlizzAuras(f)
		hideBlizzard(f.plate, false)
		local qi = questieIcon(f.plate)
		if qi then qi:SetAlpha(1) end
	end
end

-- Your target stands out: a white edge, a bit bigger, and the other plates
-- a little faded while you have a target.
local function updateTarget(f)
	local isTarget = plain(UnitIsUnit(f.unit, "target")) == true
	for _, t in ipairs(f.sel) do t:SetShown(isTarget) end
	f:SetScale((isTarget and 1.15 or 1) * (f.boss and 1.15 or 1)) -- (bosses a little bigger too)
	f:SetAlpha((isTarget or not UnitExists("target")) and 1 or 0.75)
	if isTarget then f:SetFrameLevel(f.plate:GetFrameLevel() + 20) else f:SetFrameLevel(f.plate:GetFrameLevel() + 5) end
	updateCombo(f)
end

local function updateAll(f)
	f.boss = isBoss(f.unit)
	updateHealth(f, true) -- (new mob on this plate: no easing from the last one)
	updateTarget(f)
	updateName(f)
	updateCast(f)
	updateAuras(f)
	updateThreat(f)
	updateQuest(f)
end

-- The name line on your target's plate, so the marker row can sit just above it.
function ns.TargetPlateName()
	for unit, f in pairs(skinned) do
		local ok, vis = pcall(f.IsShown, f)
		if ok and vis and f.name and plain(UnitIsUnit(unit, "target")) == true then return f.name end
	end
end

local function skin(unit)
	unskin(unit)
	if not on() then return end
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
	if not plate or (plate.IsForbidden and plate:IsForbidden()) or not wants(unit) then return end
	local f = frames[plate] or build(plate)
	-- (a plate can move to a new unit without a "removed" first)
	for u, other in pairs(skinned) do if other == f then skinned[u] = nil end end
	f.plate, f.unit = plate, unit
	skinned[unit] = f
	hideBlizzard(plate, true)
	takeBlizzAuras(f)
	f.useAC = containerFor(f, unit)
	f:Show()
	updateAll(f)
end

local function skinAll()
	for _, unit in ipairs(ns.Plates.units()) do skin(unit) end
end

local function unskinAll()
	for unit in pairs(skinned) do unskin(unit) end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- Auras change many times a frame in a fight: redraw each plate's icons once per frame.
local auraDirty, auraQueued = {}, false
local function auraFlush()
	auraQueued = false
	for unit in pairs(auraDirty) do
		local f = skinned[unit]
		if f then updateAuras(f) end
	end
	wipe(auraDirty)
end

local CAST = {
	UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_FAILED = true,
	UNIT_SPELLCAST_INTERRUPTED = true, UNIT_SPELLCAST_DELAYED = true, UNIT_SPELLCAST_CHANNEL_START = true,
	UNIT_SPELLCAST_CHANNEL_UPDATE = true, UNIT_SPELLCAST_CHANNEL_STOP = true,
	UNIT_SPELLCAST_INTERRUPTIBLE = true, UNIT_SPELLCAST_NOT_INTERRUPTIBLE = true,
}

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, unit)
	if event == "PLAYER_LOGIN" then
		if QuestieLoader and QuestieLoader.ImportModule then
			local ok, m = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieTooltips")
			if ok and type(m) == "table" then TT = m end
		end
		for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_HEALTH", "UNIT_MAXHEALTH",
			"UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION", "UNIT_FLAGS", "UNIT_CLASSIFICATION_CHANGED", "UNIT_AURA",
			"UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE", "QUEST_LOG_UPDATE", "UPDATE_SHAPESHIFT_FORM",
			"GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_TARGET_CHANGED", "RAID_TARGET_UPDATE", "INSTANCE_ENCOUNTER_ENGAGE_UNIT" }) do
			pcall(ev.RegisterEvent, ev, e)
		end
		for e in pairs(CAST) do pcall(ev.RegisterEvent, ev, e) end
		-- Quest counts change without an event for each kill: re-read them every 2 s
		-- (the saved Questie answers are dropped on the shared quest-change signal).
		ns.Plates.OnQuestChange(function() wipe(questCache) end)
		ns.Plates.Every(2, function()
			for _, f in pairs(skinned) do updateQuest(f) updateAuras(f) end
		end)
		skinAll()
		return
	end
	if event == "NAME_PLATE_UNIT_ADDED" then
		-- Let Questie add its icon first.
		skin(unit)
		C_Timer.After(0, function() local f = skinned[unit] if f then updateQuest(f) end end)
		return
	end
	if event == "NAME_PLATE_UNIT_REMOVED" then unskin(unit) return end
	if event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
		-- A boss fight started: the boss frames now name the bosses.
		for _, p in pairs(skinned) do p.boss = isBoss(p.unit) updateHealth(p) updateName(p) updateTarget(p) updateThreat(p) end
		return
	end
	if event == "RAID_TARGET_UPDATE" then
		for _, p in pairs(skinned) do updateMark(p) end
		return
	end
	if event == "PLAYER_TARGET_CHANGED" then
		for _, p in pairs(skinned) do
			updatePct(p, UnitHealth(p.unit), UnitHealthMax(p.unit))
			updateTarget(p)
		end
		return
	end
	if event == "QUEST_LOG_UPDATE" then
		wipe(questCache)
		for _, f in pairs(skinned) do updateQuest(f) end
		return
	end
	if event == "UPDATE_SHAPESHIFT_FORM" or event == "GROUP_ROSTER_UPDATE"
		or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
		for _, f in pairs(skinned) do
			updateThreat(f)
			if event == "PLAYER_REGEN_ENABLED" and f.ac and not f.useAC then
				f.useAC = containerFor(f, f.unit) -- (a plate first seen mid-fight: set up now)
			end
			if event ~= "UPDATE_SHAPESHIFT_FORM" and event ~= "GROUP_ROSTER_UPDATE" then updateAuras(f) end -- (readable or not changes)
		end
		return
	end
	local f = unit and skinned[unit]
	if not f then
		-- A friendly plate that turned hostile: skin it now.
		if (event == "UNIT_FACTION" or event == "UNIT_FLAGS") and type(unit) == "string" and unit:find("^nameplate") then skin(unit) end
		return
	end
	if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then updateHealth(f)
	elseif event == "UNIT_AURA" then
		auraDirty[unit] = true
		if not auraQueued then auraQueued = true C_Timer.After(0, auraFlush) end
	elseif CAST[event] then updateCast(f)
	elseif event == "UNIT_THREAT_SITUATION_UPDATE" or event == "UNIT_THREAT_LIST_UPDATE" then updateThreat(f)
	elseif event == "UNIT_FACTION" or event == "UNIT_FLAGS" then
		-- Turned friendly (or back): hand the plate back to the game.
		if not wants(unit) then unskin(unit) else updateHealth(f) updateThreat(f) end
	else
		updateName(f)
	end
end)

-- Combo points: redraw your target's pips when they change (or you shift in / out of cat form).
do
	local cp = CreateFrame("Frame")
	for _, e in ipairs({ "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }) do
		pcall(cp.RegisterUnitEvent, cp, e, "player")
	end
	pcall(cp.RegisterEvent, cp, "UPDATE_SHAPESHIFT_FORM")
	cp:SetScript("OnEvent", function(_, event, _, powerType)
		if (event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT")
			and not isSecret(powerType) and powerType ~= "COMBO_POINTS" then return end
		for _, f in pairs(skinned) do updateCombo(f) end
	end)
end

ns.OnFeatureChanged(function(key)
	if key == "comboPoints" then
		for _, f in pairs(skinned) do updateCombo(f) end
		return
	end
	if key ~= "plates" then return end
	if on() then skinAll() else unskinAll() end
end)
