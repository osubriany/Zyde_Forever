-- StepList: the step window. One row per step: an icon, a short action, a grey detail line, and
-- XP / time in a right-hand column. The current step is highlighted, with a live progress bar for
-- its objective. A header shows the plan's totals and the level-up ETA; "Planning..." shows while
-- a new plan is being worked out; a short notice appears when the route changes.
local ADDON, zyde = ...
-- Part of Zyde_Forever since 2026-11-14: LevelPlanner keeps its own private table (zyde.LP) so its
-- names never clash with Zyde's.
zyde.LP = zyde.LP or {}
local ns = zyde.LP

local L = {}
ns.StepList = L

local WIDTH = 360
local ROW_H = 34
local MAX_ROWS = 8
local PAD = 8

-- colours
local C_NOW = { 0.35, 1, 0.55 }
local C_XP = { 1, 0.82, 0.25 }
local C_DIM = { 0.62, 0.62, 0.66 }
local C_WARN = { 1, 0.6, 0.2 }

local frame, title, status, summary, footer, toast
local rows = {}
local lastPlan

local ICON = {
	pickup = "Interface\\GossipFrame\\AvailableQuestIcon",
	turnin = "Interface\\GossipFrame\\ActiveQuestIcon",
	monster = "Interface\\Icons\\INV_Sword_04",
	killcredit = "Interface\\Icons\\INV_Sword_04",
	item = "Interface\\Icons\\INV_Misc_Bag_10",
	object = "Interface\\Icons\\INV_Misc_Gear_01",
	event = "Interface\\Icons\\INV_Misc_Map02",
	fly = "Interface\\GossipFrame\\TaxiGossipIcon",
	boat = "Interface\\Icons\\INV_Misc_Map02",
	zeppelin = "Interface\\Icons\\INV_Misc_Map02",
	tram = "Interface\\Icons\\INV_Misc_Map02",
	portal = "Interface\\Icons\\INV_Misc_Map02",
	pass = "Interface\\Icons\\INV_Misc_Map02",
	border = "Interface\\Icons\\INV_Misc_Map02",
	hearth = "Interface\\Icons\\INV_Misc_Rune_01",
	bind = "Interface\\Icons\\INV_Misc_Rune_01",
	dungeon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
	flightpath = "Interface\\Minimap\\Tracking\\FlightMaster",
	trainer = "Interface\\Minimap\\Tracking\\Class",
	vendor = "Interface\\GossipFrame\\VendorGossipIcon",
	grind = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
	default = "Interface\\Icons\\INV_Misc_QuestionMark",
}

local function savePos()
	local point, _, rel, x, y = frame:GetPoint()
	ns.char.listPos = { point, rel, x, y }
end

local function fontString(parent, template, r, g, b, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY", template)
	if r then fs:SetTextColor(r, g, b) end
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false) -- long text is cut with "..."
	return fs
end

local function makeRow(i)
	local r = CreateFrame("Frame", nil, frame)
	r:SetSize(WIDTH - PAD * 2, ROW_H)

	r.highlight = r:CreateTexture(nil, "BACKGROUND")
	r.highlight:SetAllPoints()
	r.highlight:SetColorTexture(C_NOW[1], C_NOW[2], C_NOW[3], 0.10)
	r.accent = r:CreateTexture(nil, "BORDER")
	r.accent:SetPoint("TOPLEFT")
	r.accent:SetPoint("BOTTOMLEFT")
	r.accent:SetWidth(2)
	r.accent:SetColorTexture(C_NOW[1], C_NOW[2], C_NOW[3], 0.9)

	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(20, 20)
	r.icon:SetPoint("LEFT", 6, 0)
	r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	r.xp = fontString(r, "GameFontNormalSmall", C_XP[1], C_XP[2], C_XP[3], "RIGHT")
	r.xp:SetPoint("TOPRIGHT", -4, -4)
	r.xp:SetWidth(56)
	r.time = fontString(r, "GameFontDisableSmall", C_DIM[1], C_DIM[2], C_DIM[3], "RIGHT")
	r.time:SetPoint("BOTTOMRIGHT", -4, 5)
	r.time:SetWidth(56)

	r.title = fontString(r, "GameFontHighlight")
	r.title:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 2)
	r.title:SetPoint("RIGHT", r.xp, "LEFT", -6, 0)
	r.detail = fontString(r, "GameFontDisableSmall", C_DIM[1], C_DIM[2], C_DIM[3])
	r.detail:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -3)
	r.detail:SetPoint("RIGHT", r.time, "LEFT", -6, 0)

	r.bar = CreateFrame("StatusBar", nil, r)
	r.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	r.bar:SetStatusBarColor(C_NOW[1], C_NOW[2], C_NOW[3], 0.85)
	r.bar:SetHeight(3)
	r.bar:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, -6)
	r.bar:SetPoint("RIGHT", r.time, "LEFT", -6, 0)
	r.bar.bg = r.bar:CreateTexture(nil, "BACKGROUND")
	r.bar.bg:SetAllPoints()
	r.bar.bg:SetColorTexture(1, 1, 1, 0.08)

	-- slide up into place (when a step is finished and the list moves up)
	r.slide = r:CreateAnimationGroup()
	local drop = r.slide:CreateAnimation("Translation")
	drop:SetOffset(0, -ROW_H)
	drop:SetDuration(0)
	drop:SetOrder(1)
	local rise = r.slide:CreateAnimation("Translation")
	rise:SetOffset(0, ROW_H)
	rise:SetDuration(0.28)
	rise:SetSmoothing("OUT")
	rise:SetOrder(2)
	local fadeIn = r.slide:CreateAnimation("Alpha")
	fadeIn:SetFromAlpha(0.2)
	fadeIn:SetToAlpha(1)
	fadeIn:SetDuration(0.28)
	fadeIn:SetOrder(2)
	r.slideParts = { rise, fadeIn }
	rows[i] = r
	return r
end

function L.Init()
	frame = CreateFrame("Frame", "LevelPlannerStepList", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	frame:SetSize(WIDTH, 80)
	local pos = ns.char and ns.char.listPos
	if pos then
		frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 120)
	end
	if frame.SetBackdrop then
		frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		frame:SetBackdropColor(0.05, 0.05, 0.07, 0.88)
		frame:SetBackdropBorderColor(1, 1, 1, 0.12)
	end
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() savePos() end)
	frame:SetClampedToScreen(true)

	title = fontString(frame, "GameFontNormal")
	title:SetPoint("TOPLEFT", PAD, -PAD)
	title:SetText("LevelPlanner")
	status = fontString(frame, "GameFontDisableSmall", C_DIM[1], C_DIM[2], C_DIM[3], "RIGHT")
	status:SetPoint("TOPRIGHT", -PAD, -PAD - 1)
	summary = fontString(frame, "GameFontHighlightSmall")
	summary:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	summary:SetWidth(WIDTH - PAD * 2)
	summary:SetText("Waiting for Questie...")

	footer = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	footer:SetTextColor(C_WARN[1], C_WARN[2], C_WARN[3])
	footer:SetJustifyH("LEFT")
	footer:SetWidth(WIDTH - PAD * 2)

	for i = 1, MAX_ROWS do makeRow(i):Hide() end
	for i = 1, MAX_ROWS do L.MakeDivider(i):Hide() end

	-- route-change notice
	toast = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
	toast:SetSize(WIDTH, 24)
	toast:SetPoint("BOTTOM", frame, "TOP", 0, 4)
	if toast.SetBackdrop then
		toast:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		toast:SetBackdropColor(0.08, 0.14, 0.09, 0.92)
		toast:SetBackdropBorderColor(C_NOW[1], C_NOW[2], C_NOW[3], 0.5)
	end
	toast.text = fontString(toast, "GameFontHighlightSmall", nil, nil, nil, "CENTER")
	toast.text:SetPoint("CENTER")
	toast:Hide()
	local fade = toast:CreateAnimationGroup()
	local a = fade:CreateAnimation("Alpha")
	a:SetFromAlpha(1)
	a:SetToAlpha(0)
	a:SetStartDelay(3.5)
	a:SetDuration(0.8)
	fade:SetScript("OnFinished", function() toast:Hide() end)
	toast.fade = fade

	-- every frame: progress bar eases toward its value; "Planning..." dots move
	local dots, elapsed = 0, 0
	frame:SetScript("OnUpdate", function(_, dt)
		local r = rows[1]
		if r and r.bar:IsShown() and r.bar.target then
			local v = r.bar:GetValue()
			local nv = v + (r.bar.target - v) * math.min(1, dt * 8)
			if math.abs(r.bar.target - nv) < 0.01 then nv = r.bar.target end
			r.bar:SetValue(nv)
		end
		if not L.planning then return end
		elapsed = elapsed + dt
		if elapsed < 0.4 then return end
		elapsed = 0
		dots = dots % 3 + 1
		status:SetText("Planning" .. string.rep(".", dots))
	end)

	if ns.char and ns.char.listHidden then frame:Hide() else frame:Show() end
end

function L.Toggle()
	if frame:IsShown() then
		frame:Hide()
		ns.char.listHidden = true
	else
		frame:Show()
		ns.char.listHidden = false
	end
	if ns.Arrow and ns.Arrow.UpdateShown then ns.Arrow.UpdateShown() end -- (the arrow goes with the list)
end

function L.SetPlanning(on)
	L.planning = on
	if status then status:SetText(on and "Planning..." or "") end
end

function L.Notify(text)
	if not toast then return end
	toast.fade:Stop()
	toast:SetAlpha(1)
	toast.text:SetText(text)
	toast:Show()
	toast.fade:Play()
end

----------------------------------------------------------------------------------------
-- Steps
----------------------------------------------------------------------------------------
local SAME_PLACE_YARDS = 40

local function samePlace(a, b)
	if not (a and b) then return false end
	local d = ns.Geo.Distance(a, b)
	return d and d <= SAME_PLACE_YARDS
end

-- Merges back-to-back pick-ups / turn-ins at the same place into one row.
local function groupSteps(plan)
	local steps = {}
	for _, s in ipairs(plan.stops) do
		local last = steps[#steps]
		if last and last.kind == s.kind and (s.kind == "pickup" or s.kind == "turnin") and samePlace(last.point, s.point) then
			last.n = last.n + 1
			last.xp = last.xp + (s.xp or 0)
			last.names[#last.names + 1] = s.questName
		else
			local q = s.quest
			steps[#steps + 1] = {
				kind = s.kind, mode = s.mode, point = s.point, n = 1, xp = s.xp or 0, mobXp = s.mobXp or 0,
				work = s.work or 0, label = s.label, names = { s.questName }, npcName = s.npcName,
				questId = s.questId, objIndex = s.objIndex, objType = s.objType,
				chain = q and not q.isDungeon and (q.chainValue or 0) > 0,
				grey = q and q.grey,
			}
		end
	end
	return steps
end

local function questXpFor(name, plan)
	for _, s in ipairs(plan.stops) do
		if s.kind == "turnin" and s.questName == name then return s.xp or 0 end
	end
	return 0
end

-- The objective's kind (monster/item/...) from Questie, for the icon.
local function objectiveType(step)
	if not (step.questId and step.objIndex) then return nil end
	local qo = ns.QuestSource.GetQuest(step.questId)
	local od = qo and qo.ObjectiveData and qo.ObjectiveData[step.objIndex]
	return od and od.Type
end

-- Live progress of the objective from the quest log: done, needed.
local function progressOf(step)
	if not (step.questId and step.objIndex) then return nil end
	local entry = ns.Q.QuestLogCache and ns.safe(ns.Q.QuestLogCache.TryGetQuest, step.questId)
	local o = entry and entry.objectives and entry.objectives[step.objIndex]
	if not (o and o.numRequired and o.numRequired > 0) then return nil end
	return o.numFulfilled or 0, o.numRequired
end

-- Title, detail, XP and icon for one row.
local function describe(step, plan)
	local k = step.kind
	local icon = ICON[k] or ICON.default
	local xp = ""
	local titleText, detail = step.label or "", ""

	if k == "pickup" then
		if step.n > 1 then
			titleText = string.format("Pick up %d quests", step.n)
			detail = table.concat(step.names, ", ")
		else
			titleText = step.label
			detail = "worth " .. ns.short(questXpFor(step.names[1], plan)) .. " XP at turn-in"
				.. (step.chain and " - opens follow-ups" or "")
		end
	elseif k == "turnin" then
		titleText = step.n > 1 and string.format("Turn in %d quests", step.n) or step.label
		detail = step.n > 1 and table.concat(step.names, ", ") or (step.npcName or "")
		xp = "+" .. ns.short(step.xp)
	elseif k == "objective" then
		icon = ICON[objectiveType(step) or ""] or ICON.monster
		detail = step.names[1] or ""
		if step.mobXp > 0 then xp = "+" .. ns.short(step.mobXp) end
	elseif k == "travel" then
		icon = ICON[step.mode] or ICON.pass
		local what = { fly = "Flight", boat = "Boat", zeppelin = "Zeppelin", tram = "Deeprun Tram",
			hearth = "Hearthstone", pass = "On the way", portal = "Portal", border = "On the way" }
		detail = what[step.mode] or "Travel"
	elseif k == "dungeon" then
		titleText = "Run " .. (step.names[1] or "dungeon")
		detail = step.label or ""
		if step.mobXp > 0 then xp = "+" .. ns.short(step.mobXp) end
	elseif k == "grind" then
		detail = "When quests are slower than grinding"
		if step.mobXp > 0 then xp = "+" .. ns.short(step.mobXp) end
	elseif k == "flightpath" then
		detail = "Saves travel later"
	elseif k == "trainer" then
		detail = "New spells speed up kills"
	elseif k == "vendor" then
		detail = "Bag space and repairs"
	elseif k == "bind" then
		detail = "Your next hub"
	end
	if step.grey and (k == "pickup" or k == "turnin" or k == "objective") then
		detail = detail .. "  |cff9d9d9d· grey, but quick|r"
	end
	return titleText, detail, xp, icon
end

local DIV_H = 16
local dividers = {}

-- "--- Westfall ---": a thin line with the zone name, between rows when the route changes zone.
function L.MakeDivider(i)
	local d = CreateFrame("Frame", nil, frame)
	d:SetSize(WIDTH - PAD * 2, DIV_H)
	d.text = d:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	d.text:SetPoint("CENTER")
	d.text:SetTextColor(C_XP[1], C_XP[2], C_XP[3], 0.85)
	d.left = d:CreateTexture(nil, "ARTWORK")
	d.left:SetColorTexture(1, 1, 1, 0.12)
	d.left:SetHeight(1)
	d.left:SetPoint("LEFT", 4, 0)
	d.left:SetPoint("RIGHT", d.text, "LEFT", -6, 0)
	d.right = d:CreateTexture(nil, "ARTWORK")
	d.right:SetColorTexture(1, 1, 1, 0.12)
	d.right:SetHeight(1)
	d.right:SetPoint("LEFT", d.text, "RIGHT", 6, 0)
	d.right:SetPoint("RIGHT", -4, 0)
	dividers[i] = d
	return d
end

local function zoneOf(p)
	return p and p.map
end

local function zoneName(map)
	local info = map and C_Map.GetMapInfo(map)
	return info and info.name or nil
end

local lastFirst   -- identity of the first row last time, to notice when a step is finished

function L.Update(plan)
	if not frame then return end
	local newPlan = plan ~= lastPlan
	lastPlan = plan
	for i = 1, MAX_ROWS do rows[i]:Hide() dividers[i]:Hide() end
	footer:Hide()
	if not plan or #plan.stops == 0 then
		summary:SetText("No plannable quests nearby  |cff999999(/lp debug for details)|r")
		frame:SetHeight(PAD * 2 + 36)
		return
	end

	-- header: totals, level-up ETA, warnings
	local cur, max = UnitXP("player"), UnitXPMax("player")
	local need = (not ns.isSecret(cur) and not ns.isSecret(max) and max and max > 0) and (max - cur) or nil
	-- rested XP doubles kill XP until the rested pool is used up (quest XP isn't rested)
	local rested = GetXPExhaustion and GetXPExhaustion() or 0
	if ns.isSecret(rested) or type(rested) ~= "number" then rested = 0 end
	local planMobXp = 0
	for _, st in ipairs(plan.stops) do planMobXp = planMobXp + (st.mobXp or 0) end
	local restedBonus = math.min(rested, planMobXp)
	local rate = plan.seconds > 0 and (plan.xp + restedBonus) / (plan.seconds / 60) or plan.rate or 0
	-- a ghost has the run back to the corpse to do first
	local corpseSecs = 0
	if UnitIsGhost and UnitIsGhost("player") and ns.Waypoint and ns.Waypoint.CorpsePoint then
		local corpse, here = ns.Waypoint.CorpsePoint(), ns.Geo.PlayerPoint()
		if corpse and here then corpseSecs = ns.Travel.Seconds(here, corpse) end
	end
	local parts = { "Next " .. ns.shortTime(plan.seconds), ns.short(plan.xp) .. " XP", ns.short(rate) .. " XP/min" }
	if need and rate > 0 then
		parts[#parts + 1] = string.format("|cffffd100Lvl %d in %s|r", ns.playerLevel() + 1,
			ns.shortTime(corpseSecs + need / rate * 60))
	end
	if restedBonus > 0 then parts[#parts + 1] = "|cff66ccffrested|r" end
	if corpseSecs > 0 then parts[#parts + 1] = "|cff999999+corpse run|r" end
	if ns.IsGrouped() then parts[#parts + 1] = "|cff66ccffgrouped|r" end
	if plan.bagFree and plan.bagFree < 1 then parts[#parts + 1] = "|cffff6666bags full|r" end
	if plan.logCount and plan.logCount >= 20 then parts[#parts + 1] = "|cffff6666log full|r" end
	summary:SetText(table.concat(parts, "  |cff555555·|r  "))

	-- rows, with a zone divider wherever the route enters another zone
	local steps = groupSteps(plan)
	local shown = math.min(#steps, ns.cfg.stepsShown or 6, MAX_ROWS)
	local here = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local prevZone = here
	local y = -6
	local nDiv = 0
	local gained, dinged = 0, false

	-- a finished step: the list slides up (only for a new plan whose first row changed)
	local firstId = steps[1] and ((steps[1].kind or "") .. "|" .. (steps[1].label or ""))
	local slide = newPlan and lastFirst ~= nil and firstId ~= lastFirst
	lastFirst = firstId

	for i = 1, shown do
		local s, r = steps[i], rows[i]
		local zone = zoneOf(s.point)
		if zone and zone ~= prevZone and zoneName(zone) and nDiv < MAX_ROWS then
			nDiv = nDiv + 1
			local d = dividers[nDiv]
			d.text:SetText(zoneName(zone))
			d:ClearAllPoints()
			d:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, y)
			d:Show()
			y = y - DIV_H
		end
		if zone then prevZone = zone end

		local titleText, detail, xp, icon = describe(s, plan)
		-- kills earn double while rested XP lasts
		local kills = s.mobXp or 0
		local bonus = math.min(rested, kills)
		rested = rested - bonus
		gained = gained + (s.kind == "turnin" and s.xp or 0) + kills + bonus
		if need and not dinged and gained >= need then
			dinged = true
			detail = "|cffffd100LEVEL UP|r  " .. detail
		end
		r.icon:SetTexture(icon)
		r.title:SetText(titleText)
		r.detail:SetText(detail)
		r.xp:SetText(xp)
		-- time only where it means something (not for a quick chat with an NPC)
		local timed = s.kind == "objective" or s.kind == "dungeon" or s.kind == "grind"
			or (s.kind == "travel" and s.mode ~= "pass" and s.mode ~= "border")
		r.time:SetText(timed and s.work and s.work > 0 and ns.shortTime(s.work) or "")

		local current = (i == 1)
		r.highlight:SetShown(current)
		r.accent:SetShown(current)
		r:SetAlpha(current and 1 or 0.78)
		r.title:SetTextColor(current and 1 or 0.9, current and 1 or 0.9, current and 1 or 0.9)

		-- progress bar: always on the current step; on later steps once they have some progress
		-- (kills or items that counted for them along the way)
		local done, needed = progressOf(s)
		if done and (current or done > 0) then
			r.bar:SetMinMaxValues(0, needed)
			if current then
				-- the bar eases toward the new value (see OnUpdate); a new step starts from its real value
				if slide or not r.bar.target or r.bar.questKey ~= firstId then r.bar:SetValue(done) end
				r.bar.target, r.bar.questKey = done, firstId
			else
				r.bar:SetValue(done)
				r.bar.target = nil
			end
			-- later steps' bars are a quieter gold, so the current step stands out
			if current then
				r.bar:SetStatusBarColor(C_NOW[1], C_NOW[2], C_NOW[3], 0.85)
			else
				r.bar:SetStatusBarColor(C_XP[1], C_XP[2], C_XP[3], 0.6)
			end
			r.bar:Show()
			r.time:SetText(string.format("%d/%d", done, needed))
		else
			r.bar:Hide()
			r.bar.target = nil
		end

		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, y)
		y = y - (ROW_H + 2)
		r:Show()
		if slide then
			r.slide:Stop()
			for _, part in ipairs(r.slideParts) do part:SetStartDelay((i - 1) * 0.03) end
			r.slideParts[2]:SetToAlpha(current and 1 or 0.78) -- end at the row's normal brightness
			r.slide:Play()
		end
	end
	local height = PAD + title:GetStringHeight() + 4 + summary:GetStringHeight() - y

	-- quest log nearly full: what to abandon
	if plan.cleanupDue and plan.cleanup and #plan.cleanup > 0 then
		local names = {}
		for k = 1, math.min(3, #plan.cleanup) do names[#names + 1] = plan.cleanup[k].name end
		footer:ClearAllPoints()
		footer:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, y - 4)
		footer:SetText("Log nearly full - consider abandoning: " .. table.concat(names, ", ") .. "  |cff999999/lp cleanup|r")
		footer:Show()
		height = height + footer:GetStringHeight() + 8
	end
	frame:SetHeight(height + PAD)
end

-- Quest progress changed: refresh the current row's bar without re-planning.
function L.Refresh()
	if lastPlan then L.Update(lastPlan) end
end
