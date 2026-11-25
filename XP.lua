-- Zyde_Forever: the XP readout (XP %, rested, time to level, ready-quest XP in the tooltip).
-- Moved out of Zyde_Forever.lua (that file was at Lua's 200-local limit).

local ADDON, ns = ...
local isSecret, safe, F = ns.isSecret, ns.safe, ns.F

---------------------------------------------------------------------------
-- Experience % (replaces the XP bar). Drag it with the left mouse button.
---------------------------------------------------------------------------
local XP_DEFAULT = { point = "TOP", x = 0, y = -40 }

local xp = CreateFrame("Frame", "ZydeForeverXP", UIParent)
xp:SetSize(70, 18)
xp:SetFrameStrata("MEDIUM")
xp:SetClampedToScreen(true)
xp:SetMovable(true)
xp:EnableMouse(true)
xp:RegisterForDrag("LeftButton")

xp.bg = xp:CreateTexture(nil, "BACKGROUND")
xp.bg:SetAllPoints()
xp.bg:SetColorTexture(0.12, 0.12, 0.12, 0.85) -- dark gray

xp.text = xp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
xp.text:SetPoint("TOP", 0, -3)
xp.text:SetTextColor(0.69, 0.35, 1.0) -- purple

xp.rested = xp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
xp.rested:SetPoint("TOP", xp.text, "BOTTOM", 0, -1)
xp.rested:SetTextColor(0.55, 0.8, 1.0) -- light blue

xp.ttl = xp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
xp.ttl:SetTextColor(0.85, 0.85, 0.85)

---------------------------------------------------------------------------
-- XP rate: gains over the last 2 hours of *play time*, saved per character
-- so it carries on after logging off (offline time doesn't count).
-- ZydeForeverDB.xpLog["Name-Realm"] = { clock, start, gains = {{c, xp}} }
---------------------------------------------------------------------------
local RATE_WINDOW = 2 * 60 * 60
local MIN_WINDOW  = 60 -- need at least a minute of data for a TTL
local sessionStart, lastXP, lastMax

local function xpLog()
	ZydeForeverDB = ZydeForeverDB or {}
	ZydeForeverDB.xpLog = ZydeForeverDB.xpLog or {}
	local key = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
	local log = ZydeForeverDB.xpLog[key]
	if not log then
		log = { clock = 0, start = 0, gains = {} }
		ZydeForeverDB.xpLog[key] = log
	end
	return log
end

-- Seconds played with the addon on this character, across sessions.
local function playClock()
	local log = xpLog()
	return log.clock + (sessionStart and (GetTime() - sessionStart) or 0)
end

local function pruneGains(log, now)
	local keep = {}
	for _, g in ipairs(log.gains) do
		if now - g[1] <= RATE_WINDOW then keep[#keep + 1] = g end
	end
	log.gains = keep
end

local function recordXP()
	local cur, max = UnitXP("player"), UnitXPMax("player")
	if isSecret(cur) or isSecret(max) or not max or max <= 0 then return end
	if lastXP then
		local gained = cur - lastXP
		if gained < 0 then gained = (lastMax - lastXP) + cur end -- levelled up
		if gained > 0 then
			local log, now = xpLog(), playClock()
			log.gains[#log.gains + 1] = { now, gained }
			pruneGains(log, now)
		end
	end
	lastXP, lastMax = cur, max
end

-- XP per second over the last 2 hours of play (or less if newer data).
local function xpRate()
	local log, now = xpLog(), playClock()
	local window = math.min(RATE_WINDOW, now - log.start)
	if window < MIN_WINDOW then return nil end
	local sum = 0
	for _, g in ipairs(log.gains) do
		if now - g[1] <= RATE_WINDOW then sum = sum + g[2] end
	end
	if sum <= 0 then return nil end
	return sum / window
end

local function formatTime(sec)
	if sec >= 100 * 3600 then return ">99h" end
	local h, m = math.floor(sec / 3600), math.floor(sec % 3600 / 60)
	if h > 0 then return ("%dh %dm"):format(h, m) end
	return ("%dm"):format(math.max(m, 1))
end

-- LevelPlanner's time to the next level while its step window is up (so the two agree), else nil.
local function plannerSeconds()
	local SL = ns.LP and ns.LP.StepList
	local secs = SL and SL.LevelUpSeconds and SL.LevelUpSeconds()
	return type(secs) == "number" and secs or nil
end

local xpClock = CreateFrame("Frame")
xpClock:RegisterEvent("PLAYER_LOGIN")
xpClock:RegisterEvent("PLAYER_LOGOUT")
xpClock:SetScript("OnEvent", function(_, event)
	local log = xpLog()
	if event == "PLAYER_LOGIN" then
		sessionStart = GetTime()
		lastXP, lastMax = UnitXP("player"), UnitXPMax("player")
		if isSecret(lastXP) or isSecret(lastMax) then lastXP, lastMax = nil, nil end
	else -- logout or /reload: bank this session's play time
		log.clock = playClock()
		sessionStart = GetTime()
		pruneGains(log, log.clock)
	end
end)

local function placeXP()
	local p = (ZydeForeverDB and ZydeForeverDB.xpPos) or XP_DEFAULT
	xp:ClearAllPoints()
	xp:SetPoint(p.point, UIParent, p.point, p.x, p.y)
end

xp:SetScript("OnDragStart", function(self) self:StartMoving() end)
xp:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local point, _, _, x, y = self:GetPoint()
	ZydeForeverDB = ZydeForeverDB or {}
	ZydeForeverDB.xpPos = { point = point, x = x, y = y }
end)

xp.ammo = xp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

-- Still levelling (XP not turned off, not max level)?
local function xpShown()
	local level = UnitLevel("player")
	local maxLevel = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion())
		or MAX_PLAYER_LEVEL or 60
	local cur, max = UnitXP("player"), UnitXPMax("player")
	if isSecret(cur) or isSecret(max) or isSecret(level) then return nil end
	if (IsXPUserDisabled and IsXPUserDisabled()) or level >= maxLevel or not max or max <= 0 then
		return false
	end
	return true, cur, max
end

local function updateXP()
	if not F("xp") then xp:Hide() return end
	local levelling, cur, max = xpShown()
	if levelling == nil then return end -- hidden values: keep what's shown
	-- Hunter ammo line (Ammo.lua), also shown at max level.
	local ammoText, ar, ag, ab
	if ns.Ammo then ammoText, ar, ag, ab = ns.Ammo.Line() end
	if not levelling and not ammoText then xp:Hide() return end

	local lines, width, below = 0, 0, nil
	if levelling then
		xp.text:SetFormattedText("XP %.1f%%", cur / max * 100)
		xp.text:Show()
		width, lines, below = xp.text:GetStringWidth(), 1, xp.text

		local rested = GetXPExhaustion and GetXPExhaustion()
		if rested and not isSecret(rested) and rested > 0 then
			xp.rested:SetFormattedText("Rested %.1f%%", rested / max * 100)
			xp.rested:Show()
			width = math.max(width, xp.rested:GetStringWidth())
			lines, below = lines + 1, xp.rested
		else
			xp.rested:Hide()
		end

		-- Time to level: LevelPlanner's while its window is up, else from the last 2 hours of play.
		local secs = plannerSeconds()
		if not secs then
			local rate = xpRate()
			secs = rate and (max - cur) / rate
		end
		xp.ttl:ClearAllPoints()
		xp.ttl:SetPoint("TOP", below, "BOTTOM", 0, -1)
		xp.ttl:SetText("TTL: " .. (secs and formatTime(secs) or "--"))
		xp.ttl:Show()
		width = math.max(width, xp.ttl:GetStringWidth())
		lines, below = lines + 1, xp.ttl
	else
		xp.text:Hide()
		xp.rested:Hide()
		xp.ttl:Hide()
	end

	if ammoText then
		xp.ammo:ClearAllPoints()
		if below then xp.ammo:SetPoint("TOP", below, "BOTTOM", 0, -1) else xp.ammo:SetPoint("TOP", 0, -3) end
		xp.ammo:SetText(ammoText)
		xp.ammo:SetTextColor(ar, ag, ab)
		xp.ammo:Show()
		width = math.max(width, xp.ammo:GetStringWidth())
		lines = lines + 1
	else
		xp.ammo:Hide()
	end

	xp:SetHeight(6 + lines * 12)
	xp:SetWidth(math.max(60, width + 14))
	xp:Show()
end
ns.UpdateXP = updateXP
ns.formatTime = formatTime
ns.xpRate = xpRate
C_Timer.NewTicker(30, updateXP) -- TTL drifts as the 2-hour window moves
-- Opening or closing LevelPlanner's window switches which time to level shows.
do
	local hook = CreateFrame("Frame")
	hook:RegisterEvent("PLAYER_LOGIN")
	hook:SetScript("OnEvent", function()
		C_Timer.After(1, function()
			local w = _G.LevelPlannerStepList
			if w and not w.zydeXPHooked then
				w.zydeXPHooked = true
				w:HookScript("OnShow", function() updateXP() end)
				w:HookScript("OnHide", function() updateXP() end)
			end
		end)
	end)
end
ns.OnFeatureChanged(function(key) if key == "xp" then updateXP() end end)

-- Right-click the XP readout: ask, then start the time-to-level data fresh.
StaticPopupDialogs["ZYDEFOREVER_RESET_TTL"] = {
	text = "Reset the time to level counter?\nYour XP rate will start over from now.",
	button1 = YES,
	button2 = NO,
	OnAccept = function()
		local log = xpLog()
		log.gains = {}
		log.start = playClock()
		updateXP()
		print("|cff66ccffZyde_Forever|r: time to level counter reset")
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}
xp:SetScript("OnMouseUp", function(_, button)
	if button == "RightButton" and xpShown() then
		GameTooltip:Hide()
		StaticPopup_Show("ZYDEFOREVER_RESET_TTL")
	end
end)

-- Mouseover: XP still needed, and the XP from quests ready to turn in.
local function num(n)
	return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

-- XP reward of quest log entry i (quest questID). Classic clients read the
-- selected log entry; modern ones take the quest ID.
local function questXP(i, questID)
	local v
	if SelectQuestLogEntry and GetQuestLogSelection then
		local old = GetQuestLogSelection()
		SelectQuestLogEntry(i)
		v = safe(GetQuestLogRewardXP)
		SelectQuestLogEntry(old or 0)
	elseif questID then
		v = safe(GetQuestLogRewardXP, questID)
	end
	if type(v) == "number" and not isSecret(v) then return v end
	return 0
end

local function isReady(questID, completeFlag)
	if completeFlag == 1 or completeFlag == true then return true end
	if questID and C_QuestLog then
		if C_QuestLog.ReadyForTurnIn and safe(C_QuestLog.ReadyForTurnIn, questID) == true then return true end
		if C_QuestLog.IsComplete and safe(C_QuestLog.IsComplete, questID) == true then return true end
	end
	return false
end

-- Returns number of quests ready to turn in and their total XP.
local function readyQuestXP()
	local count, total = 0, 0
	if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
		for i = 1, (safe(C_QuestLog.GetNumQuestLogEntries) or 0) do
			local info = safe(C_QuestLog.GetInfo, i)
			if info and not info.isHeader and info.questID and isReady(info.questID) then
				count, total = count + 1, total + questXP(i, info.questID)
			end
		end
	elseif GetNumQuestLogEntries and GetQuestLogTitle then
		for i = 1, (safe(GetNumQuestLogEntries) or 0) do
			local _, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
			if not isHeader and isReady(questID, isComplete) then
				count, total = count + 1, total + questXP(i, questID)
			end
		end
	end
	return count, total
end

local function xpTooltip(self)
	local cur, max = UnitXP("player"), UnitXPMax("player")
	if isSecret(cur) or isSecret(max) or not max or max <= 0 then return end
	local need = max - cur
	-- "1,234 (12.6%)": raw value plus its share of this level's XP
	local function val(n) return ("%s (%.1f%%)"):format(num(n), n / max * 100) end
	GameTooltip:AddLine("Experience", 0.69, 0.35, 1.0)
	GameTooltip:AddDoubleLine("Current", ("%s / %s (%.1f%%)"):format(num(cur), num(max), cur / max * 100), 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine("Needed to level", val(need), 1, 1, 1, 1, 0.82, 0)

	local rested = GetXPExhaustion and GetXPExhaustion()
	if rested and not isSecret(rested) and rested > 0 then
		GameTooltip:AddDoubleLine("Rested", val(rested), 1, 1, 1, 0.55, 0.8, 1.0)
	end
	local rate = xpRate()
	GameTooltip:AddDoubleLine("XP per hour (last 2h)", rate and val(math.floor(rate * 3600)) or "--", 1, 1, 1, 0.85, 0.85, 0.85)
	local planned = plannerSeconds()
	if planned then
		GameTooltip:AddDoubleLine("Time to level (Level Planner)", formatTime(planned), 1, 1, 1, 1, 0.82, 0)
		GameTooltip:AddDoubleLine("Time to level (last 2h)", rate and formatTime(need / rate) or "--", 1, 1, 1, 0.85, 0.85, 0.85)
	else
		GameTooltip:AddDoubleLine("Time to level", rate and formatTime(need / rate) or "--", 1, 1, 1, 0.85, 0.85, 0.85)
	end

	local count, total = readyQuestXP()
	GameTooltip:AddLine(" ")
	if count == 0 then
		GameTooltip:AddLine("No quests ready to turn in", 0.6, 0.6, 0.6)
	else
		GameTooltip:AddDoubleLine(("Quests ready (%d)"):format(count), val(total), 1, 1, 1, 0.4, 1, 0.4)
		if total >= need then
			GameTooltip:AddLine("Turning these in will level you up!", 0.4, 1, 0.4)
		elseif total > 0 then
			GameTooltip:AddDoubleLine("Still needed after", val(need - total), 0.8, 0.8, 0.8, 1, 0.82, 0)
		end
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Right-click to reset time to level", 0.6, 0.6, 0.6)
end

xp:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
	if xpShown() then xpTooltip(self) end
	if ns.Ammo and ns.Ammo.Line() then
		if GameTooltip:NumLines() > 0 then GameTooltip:AddLine(" ") end
		ns.Ammo.Tooltip(GameTooltip)
	end
	GameTooltip:Show()
end)
xp:SetScript("OnLeave", function() GameTooltip:Hide() end)

ns.PlaceXP, ns.RecordXP = placeXP, recordXP
