-- Zyde_Forever: flat nameplates for enemies, in the unit frames' style.
--   * a flat bar in the hostile / neutral / tapped color, thin dark outline
--   * your target's plate: its health % with one decimal, inside the bar
--   * the full name above it (smaller, so long names fit)
--   * a level badge on the left: difficulty color, "+" for elites, a silver
--     dragon for rares, a skull for bosses
--   * a cast bar under it while it casts: orange = you can interrupt, gray = you can't
--   * your own debuffs on it (Hunter's Mark, Serpent Sting, Sunder, Rend...) with time left
--   * threat (in a group): the outline turns orange / red when a mob is about
--     to / does attack you; when you're the tank, when it's attacking someone else
--   * warriors: the bar changes color below 20% health (Execute range)
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

local COLOR = {
	hostile = { 0.78, 0.29, 0.23 }, neutral = { 0.88, 0.72, 0.27 }, friendly = { 0.55, 0.76, 0.35 },
	tapped = { 0.5, 0.5, 0.5 }, execute = { 0.65, 0.35, 0.95 },
}
local EDGE = { 0, 0, 0, 0.9 }                 -- normal outline
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
-- Building one plate's frame
---------------------------------------------------------------------------
local function build(plate)
	local f = CreateFrame("Frame", nil, plate)
	f:SetSize(W, H)
	f:SetPoint("CENTER", plate, "CENTER", 0, 0)
	f:SetFrameLevel(plate:GetFrameLevel() + 5)
	f:EnableMouse(false)

	f.hp = bar(f, H)
	f.hp:SetAllPoints()
	-- Health % (your target's plate only), inside the bar on the right.
	f.pct = text(f.hp, 9)
	f.pct:SetPoint("RIGHT", f.hp, "RIGHT", -3, 0)
	f.pct:SetTextColor(1, 1, 1)

	f.name = text(f, 10)
	f.name:SetPoint("BOTTOM", f, "TOP", 0, 3)
	f.name:SetWidth(W + 60)
	f.name:SetWordWrap(false)
	f.name:SetTextColor(1, 1, 1)

	f.level = text(f, 10)
	f.level:SetPoint("RIGHT", f, "LEFT", -4, 0)
	f.dragon = f:CreateTexture(nil, "OVERLAY")
	f.dragon:SetSize(14, 14)
	f.dragon:SetPoint("RIGHT", f.level, "LEFT", 1, 0)
	f.dragon:Hide()

	-- Cast bar
	f.cast = bar(f, CAST_H)
	f.cast:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -3)
	f.cast:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -3)
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

	-- Your debuffs, above the name
	f.auras = {}
	for i = 1, AURA_MAX do
		local a = CreateFrame("Frame", nil, f)
		a:SetSize(AURA, AURA)
		a:SetPoint("BOTTOMLEFT", f, "TOPLEFT", (i - 1) * (AURA + 2), 16)
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
		a.count = text(top, 8)
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
local function reactionColor(unit)
	if UnitIsTapDenied and plain(UnitIsTapDenied(unit)) then return COLOR.tapped end
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

local function updateHealth(f)
	local unit = f.unit
	local cur, maxv = UnitHealth(unit), UnitHealthMax(unit)
	updatePct(f, cur, maxv)
	if isSecret(cur) or isSecret(maxv) then
		pcall(f.hp.SetMinMaxValues, f.hp, 0, maxv)
		pcall(f.hp.SetValue, f.hp, cur)
		local c = reactionColor(unit)
		f.hp:SetStatusBarColor(c[1], c[2], c[3])
		return
	end
	maxv = (maxv and maxv > 0) and maxv or 1
	f.hp:SetMinMaxValues(0, maxv)
	f.hp:SetValue(cur or 0)
	local c = reactionColor(unit)
	-- Warriors: Execute range.
	if IS_WARRIOR and cur and cur > 0 and cur / maxv < 0.2 and c ~= COLOR.tapped then c = COLOR.execute end
	f.hp:SetStatusBarColor(c[1], c[2], c[3])
end

local function updateName(f)
	local unit = f.unit
	if not pcall(f.name.SetText, f.name, UnitName(unit)) then f.name:SetText("") end
	local lvl = plain(UnitLevel(unit))
	local class = plain(UnitClassification(unit))
	f.dragon:Hide()
	if not lvl then f.level:SetText("") return end
	local boss = lvl < 0 or class == "worldboss"
	local txt = boss and "??" or tostring(lvl)
	if class == "elite" or class == "rareelite" then txt = txt .. "+" end
	local c = GetCreatureDifficultyColor and GetCreatureDifficultyColor(boss and 999 or lvl)
		or (GetQuestDifficultyColor and GetQuestDifficultyColor(boss and 999 or lvl))
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

local function updateAuras(f)
	local n, unit = 0, f.unit
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		for i = 1, 40 do
			if n >= AURA_MAX then break end
			local a = safe(C_UnitAuras.GetAuraDataByIndex, unit, i, "HARMFUL|PLAYER")
			if not a then break end
			n = n + 1
			local b = f.auras[n]
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
	for i = n + 1, AURA_MAX do f.auras[i]:Hide() end
end

-- You're the tank: the group's tank role, or a warrior in Defensive Stance.
local function tanking()
	local role = UnitGroupRolesAssigned and plain(UnitGroupRolesAssigned("player"))
	if role == "TANK" then return true end
	if IS_WARRIOR then return plain(GetShapeshiftForm and GetShapeshiftForm()) == 2 end
	return false
end

-- Threat (only in a group: solo, everything is on you anyway).
local function updateThreat(f)
	local unit = f.unit
	local c = EDGE
	if IsInGroup() and plain(UnitAffectingCombat(unit)) then
		local status = UnitThreatSituation and plain(UnitThreatSituation("player", unit))
		if tanking() then
			-- 3 = it's on you, safely. Anything else: it's on someone else.
			if status == 2 then c = THREAT_WARN
			elseif status ~= nil and status < 2 then c = THREAT_BAD end
		else
			if status == 3 then c = THREAT_BAD
			elseif status == 2 then c = THREAT_WARN end
		end
	end
	setEdge(f.hp, c)
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
local function hideBlizzard(plate, hide)
	local uf = plate.UnitFrame
	if not uf then return end
	uf.zydeHidden = hide
	if not uf.zydeHooked then
		uf.zydeHooked = true
		-- The game may set its own plate's alpha back: keep it invisible while ours shows.
		hooksecurefunc(uf, "SetAlpha", function(self, a)
			if self.zydeHidden and a ~= 0 and not self.zydeSetting then
				self.zydeSetting = true
				self:SetAlpha(0)
				self.zydeSetting = nil
			end
		end)
	end
	uf.zydeSetting = true
	uf:SetAlpha(hide and 0 or 1)
	uf.zydeSetting = nil
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
	if f.plate then
		hideBlizzard(f.plate, false)
		local qi = questieIcon(f.plate)
		if qi then qi:SetAlpha(1) end
	end
end

local function updateAll(f)
	updateHealth(f)
	updateName(f)
	updateCast(f)
	updateAuras(f)
	updateThreat(f)
	updateQuest(f)
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
			"GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_TARGET_CHANGED" }) do
			pcall(ev.RegisterEvent, ev, e)
		end
		for e in pairs(CAST) do pcall(ev.RegisterEvent, ev, e) end
		-- Quest counts change without an event for each kill: re-read them every 2 s.
		C_Timer.NewTicker(2, function()
			wipe(questCache)
			for _, f in pairs(skinned) do updateQuest(f) end
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
	if event == "PLAYER_TARGET_CHANGED" then
		for _, p in pairs(skinned) do updatePct(p, UnitHealth(p.unit), UnitHealthMax(p.unit)) end
		return
	end
	if event == "QUEST_LOG_UPDATE" then
		wipe(questCache)
		for _, f in pairs(skinned) do updateQuest(f) end
		return
	end
	if event == "UPDATE_SHAPESHIFT_FORM" or event == "GROUP_ROSTER_UPDATE"
		or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
		for _, f in pairs(skinned) do updateThreat(f) end
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

ns.OnFeatureChanged(function(key)
	if key ~= "plates" then return end
	if on() then skinAll() else unskinAll() end
end)
