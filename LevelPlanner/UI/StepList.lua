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
-- left-edge stripe by step type
local STRIPE = {
	kill = { 0.9, 0.3, 0.3 },
	collect = { 0.4, 0.85, 0.4 },
	turnin = C_XP,
	travel = { 0.35, 0.6, 1 },
	pickup = { 0.85, 0.85, 0.85 },
	other = { 0.7, 0.45, 0.95 },
}
local CHECK = "Interface\\RAIDFRAME\\ReadyCheck-Ready"
local FADE_SECS, RISE_SECS = 0.35, 0.2 -- finished step: check + fade out, then the rows below move up

local frame, list, title, status, summary, footer, toast
local ghost -- copy of a finished step's row, faded out over the list (see L.Update)
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
	corpse = "Interface\\Icons\\Spell_Holy_Resurrection",
	default = "Interface\\Icons\\INV_Misc_QuestionMark",
}

local function savePos()
	local point, _, rel, x, y = frame:GetPoint()
	ns.char.listPos = { point, rel, x, y }
	if L.PlaceHearth then L.PlaceHearth() end -- (the hearthstone button follows the list)
end

local function fontString(parent, template, r, g, b, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY", template)
	if r then fs:SetTextColor(r, g, b) end
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false) -- long text is cut with "..."
	return fs
end

local function buildRow()
	local r = CreateFrame("Frame", nil, list)
	r:SetSize(WIDTH - PAD * 2, ROW_H)

	r.highlight = r:CreateTexture(nil, "BACKGROUND")
	r.highlight:SetAllPoints()
	r.highlight:SetColorTexture(C_NOW[1], C_NOW[2], C_NOW[3], 0.10)
	-- colour stripe on the left edge: the step's type (kill, collect, turn-in, travel, pick-up, other)
	r.stripe = r:CreateTexture(nil, "BORDER")
	r.stripe:SetPoint("TOPLEFT")
	r.stripe:SetPoint("BOTTOMLEFT")
	r.stripe:SetWidth(3)
	r.stripe:SetColorTexture(1, 1, 1, 1)

	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(20, 20)
	r.icon:SetPoint("LEFT", 6, 0)
	r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- right-hand column, the same on every row: +XP on top; "~time · »54%" (or "10/12 · »54%" on
	-- the current step) below - » = level progress after this step
	r.xp = fontString(r, "GameFontNormalSmall", C_XP[1], C_XP[2], C_XP[3], "RIGHT")
	r.xp:SetPoint("TOPRIGHT", -4, -4)
	r.xp:SetWidth(56)
	r.time = fontString(r, "GameFontDisableSmall", C_DIM[1], C_DIM[2], C_DIM[3], "RIGHT")
	r.time:SetPoint("BOTTOMRIGHT", -4, 5)
	-- (no fixed width: it fits its text, and the detail line makes room)

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

	return r
end

-- Slide up into place (when a step is finished and the list moves up): the row starts one row
-- lower - where it was before - waits while the finished step fades, then rises.
local function addSlide(r)
	r.slide = r:CreateAnimationGroup()
	local drop = r.slide:CreateAnimation("Translation")
	drop:SetOffset(0, -(ROW_H + 2))
	drop:SetDuration(0)
	drop:SetOrder(1)
	local rise = r.slide:CreateAnimation("Translation")
	rise:SetOffset(0, ROW_H + 2)
	rise:SetDuration(RISE_SECS)
	rise:SetSmoothing("OUT")
	rise:SetStartDelay(FADE_SECS)
	rise:SetOrder(2)
end

local function makeRow(i)
	local r = buildRow()
	addSlide(r)
	-- clicks: right-click a pinned NPC step to remove it; drag still moves the list
	r:EnableMouse(true)
	r:RegisterForDrag("LeftButton")
	r:SetScript("OnDragStart", function() if L.HideHearth then L.HideHearth() end frame:StartMoving() end)
	r:SetScript("OnDragStop", function() frame:StopMovingOrSizing() savePos() end)
	r:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" and self.kind == "pin" and ns.Pin then ns.Pin.Clear() end
	end)
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
	frame:SetScript("OnDragStart", function(self) if L.HideHearth then L.HideHearth() end self:StartMoving() end)
	frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() savePos() end)
	frame:SetClampedToScreen(true)

	title = fontString(frame, "GameFontNormal")
	title:SetPoint("TOPLEFT", PAD, -PAD)
	title:SetText("LevelPlanner")
	-- "...": find the nearest innkeeper, ammo vendor, class trainer or repair vendor (UI/Pin.lua)
	local more = CreateFrame("Button", nil, frame)
	more:SetSize(22, 16)
	more:SetPoint("TOPRIGHT", -PAD + 4, -PAD + 1)
	more.text = more:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	more.text:SetPoint("CENTER", 0, 3)
	more.text:SetText("...")
	more:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
	more:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.12)
	more:SetScript("OnClick", function(self) if ns.Pin then ns.Pin.ToggleMenu(self) end end)
	more:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Find an NPC")
		GameTooltip:AddLine("Innkeeper, ammo vendor, class trainer or repair: the nearest goes at the top of the steps. Right-click that step to remove it.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	more:SetScript("OnLeave", function() GameTooltip:Hide() end)
	status = fontString(frame, "GameFontDisableSmall", C_DIM[1], C_DIM[2], C_DIM[3], "RIGHT")
	status:SetPoint("TOPRIGHT", more, "TOPLEFT", -4, -2)
	summary = fontString(frame, "GameFontHighlightSmall")
	summary:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	summary:SetWidth(WIDTH - PAD * 2)
	summary:SetText("Waiting for Questie...")

	footer = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	footer:SetTextColor(C_WARN[1], C_WARN[2], C_WARN[3])
	footer:SetJustifyH("LEFT")
	footer:SetWidth(WIDTH - PAD * 2)

	-- the rows live in a clipping area under the header: while they slide up, a row waiting below
	-- the last place doesn't show outside the window
	list = CreateFrame("Frame", nil, frame)
	list:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -2)
	list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD + 2, 2)
	if list.SetClipsChildren then list:SetClipsChildren(true) end

	for i = 1, MAX_ROWS do makeRow(i):Hide() end
	for i = 1, MAX_ROWS do L.MakeDivider(i):Hide() end

	-- finished step: a copy of its row with a check mark, fading out where it was
	ghost = buildRow()
	ghost:EnableMouse(false)
	ghost:SetFrameLevel(list:GetFrameLevel() + 5)
	ghost.check = ghost:CreateTexture(nil, "OVERLAY")
	ghost.check:SetTexture(CHECK)
	ghost.check:SetSize(22, 22)
	ghost.check:SetPoint("CENTER", ghost.icon, "CENTER")
	ghost.fade = ghost:CreateAnimationGroup()
	local pop = ghost.fade:CreateAnimation("Alpha")
	pop:SetFromAlpha(1)
	pop:SetToAlpha(0)
	pop:SetStartDelay(0.1)
	pop:SetDuration(FADE_SECS - 0.1)
	ghost.fade:SetScript("OnFinished", function() ghost:Hide() end)
	ghost.fade:SetScript("OnStop", function() ghost:Hide() end)
	ghost:Hide()

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

	L.MakeHearth()
	if ns.char and ns.char.listHidden then frame:Hide() else frame:Show() end
end

-- Hearthstone step: one secure "use item" button laid over that row. Secure frames can't be moved,
-- shown or hidden in combat, so it's placed out of combat only, and hidden as combat starts
-- (PLAYER_REGEN_DISABLED still allows it). Rows themselves stay ordinary frames.
local hearthBtn, hearthRow
local placedAt -- "left,bottom,width,height" the button was last put at
local function placeHearth()
	if not hearthBtn or InCombatLockdown() then return end
	if hearthRow and hearthRow:IsVisible() and hearthRow:GetLeft() then
		-- by screen position: the game won't anchor a protected button to an ordinary frame
		local s = hearthRow:GetEffectiveScale() / UIParent:GetEffectiveScale()
		local l, b = hearthRow:GetLeft() * s, hearthRow:GetBottom() * s
		local w, h = hearthRow:GetWidth() * s, hearthRow:GetHeight() * s
		local at = string.format("%.0f,%.0f,%.0f,%.0f", l, b, w, h)
		if at == placedAt and hearthBtn:IsShown() then return end
		placedAt = at
		hearthBtn:ClearAllPoints()
		hearthBtn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
		hearthBtn:SetSize(w, h)
		hearthBtn:SetFrameLevel(hearthRow:GetFrameLevel() + 5)
		hearthBtn:Show()
	else
		placedAt = nil
		hearthBtn:Hide()
	end
end
L.PlaceHearth = function() placeHearth() end
L.HideHearth = function() if hearthBtn and not InCombatLockdown() then hearthBtn:Hide() end end

function L.MakeHearth()
	hearthBtn = CreateFrame("Button", "LevelPlannerHearthStep", UIParent, "SecureActionButtonTemplate")
	hearthBtn:SetFrameStrata(frame:GetFrameStrata())
	-- both: with "cast on key down" on, the game acts on the press, otherwise on the release (only one)
	hearthBtn:RegisterForClicks("AnyDown", "AnyUp")
	hearthBtn:SetAttribute("type", "item")
	hearthBtn:SetAttribute("item", "item:6948") -- Hearthstone
	hearthBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Click to use your hearthstone")
		GameTooltip:Show()
	end)
	hearthBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	hearthBtn:Hide()
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("PLAYER_REGEN_DISABLED")
	ev:RegisterEvent("PLAYER_REGEN_ENABLED")
	ev:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_DISABLED" then hearthBtn:Hide() placedAt = nil else placeHearth() end
	end)
	-- the row moves after it's drawn (the list resizes, rows slide in, the window is dragged):
	-- follow it a few times a second (does nothing while it stays put)
	C_Timer.NewTicker(0.25, placeHearth)
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
	placeHearth()
	if ns.MapPins and ns.MapPins.Redraw then ns.safe(ns.MapPins.Redraw) end -- (and the map pins and dotted line)
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
				icon = s.icon, pinLabel = s.pinLabel,
				questId = s.questId, objIndex = s.objIndex, objType = s.objType, buy = s.buy,
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
			hearth = "Hearthstone", pass = "On the way", portal = "Portal", border = "On the way",
			corpse = "The rest of the route starts there" }
		detail = what[step.mode] or "Travel"
		if step.mode == "hearth" then detail = "Hearthstone  |cff999999· click to use|r" end
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
	elseif k == "pin" then
		icon = step.icon or ICON.default
		detail = (step.pinLabel or "NPC") .. "  |cff999999· right-click to remove|r"
	end
	if step.grey and (k == "pickup" or k == "turnin" or k == "objective") then
		detail = detail .. "  |cff9d9d9d· grey, but quick|r"
	end
	return titleText, detail, xp, icon
end

-- The stripe colour for a step.
local function stripeOf(step)
	local k = step.kind
	if k == "turnin" then return STRIPE.turnin end
	if k == "pickup" then return STRIPE.pickup end
	if k == "travel" or k == "flightpath" then return STRIPE.travel end
	if k == "dungeon" or k == "grind" then return STRIPE.kill end
	if k == "objective" then
		if step.buy then return STRIPE.collect end
		local t = objectiveType(step)
		if t == "item" or t == "object" then return STRIPE.collect end
		if t == "event" then return STRIPE.other end
		return STRIPE.kill
	end
	return STRIPE.other
end

local DIV_H = 16
local dividers = {}

-- "--- Westfall ---": a thin line with the zone name, between rows when the route changes zone.
-- The same in gold, "--- Level 35 ---", where the plan says you'll level up.
local function styleDivider(d, level)
	local a = level and 0.6 or 0.12
	local c = level and C_XP or { 1, 1, 1 }
	d.left:SetColorTexture(c[1], c[2], c[3], a)
	d.right:SetColorTexture(c[1], c[2], c[3], a)
	d.text:SetFontObject(level and "GameFontNormalSmall" or "GameFontDisableSmall")
	d.text:SetTextColor(C_XP[1], C_XP[2], C_XP[3], level and 1 or 0.85)
end

function L.MakeDivider(i)
	local d = CreateFrame("Frame", nil, list)
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
	addSlide(d)
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
	footer:Hide()
	if not plan or #plan.stops == 0 then
		for i = 1, MAX_ROWS do rows[i]:Hide() dividers[i]:Hide() rows[i].slide:Stop() dividers[i].slide:Stop() end
		ghost.fade:Stop()
		hearthRow = nil
		placeHearth()
		summary:SetText("No plannable quests nearby  |cff999999(/lp debug for details)|r")
		frame:SetHeight(PAD * 2 + 36)
		return
	end

	-- header: totals, level-up ETA, warnings
	local cur, max = UnitXP("player"), UnitXPMax("player")
	local need = (not ns.isSecret(cur) and not ns.isSecret(max) and max and max > 0) and (max - cur) or nil
	-- rested XP doubles kill XP until the rested pool is used up (quest XP isn't rested) - the same
	-- rule the planner uses (Estimate.RestedBonus), from the live pool
	local E = ns.Estimate
	local rested = E.RestedPool()
	local planMobXp = 0
	for _, st in ipairs(plan.stops) do planMobXp = planMobXp + (st.mobXp or 0) end
	local restedBonus = E.RestedBonus(rested, planMobXp)
	local rate = plan.seconds > 0 and (plan.xp + restedBonus) / (plan.seconds / 60) or plan.rate or 0
	-- a ghost has the run back to the corpse to do first
	local corpseSecs = 0
	-- (a plan made while you're a ghost has the run as its first step already)
	if not plan.corpseRun and UnitIsGhost and UnitIsGhost("player") and ns.Waypoint and ns.Waypoint.CorpsePoint then
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
	if plan.logCount and plan.logCount >= (plan.logCap or 20) then parts[#parts + 1] = "|cffff6666log full|r" end
	summary:SetText(table.concat(parts, "  |cff555555·|r  "))

	-- rows, with a zone divider wherever the route enters another zone
	local steps = groupSteps(plan)
	local shown = math.min(#steps, ns.cfg.stepsShown or 6, MAX_ROWS)
	local here = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local prevZone = here
	local y = -6
	local nDiv = 0
	local gained, dinged = 0, false
	local hearthFound

	-- a finished step (a new plan whose first row changed): its row shows a check mark and fades
	-- out, then the rows below slide up into place. A re-plan in the middle restarts it cleanly from
	-- where things are; a re-plan that keeps the first step ends it at once (rows in their places).
	local firstId = steps[1] and ((steps[1].kind or "") .. "|" .. (steps[1].label or ""))
	local slide = newPlan and lastFirst ~= nil and firstId ~= lastFirst
	lastFirst = firstId
	if newPlan then
		for i = 1, MAX_ROWS do rows[i].slide:Stop() dividers[i].slide:Stop() end
		ghost.fade:Stop()
	end
	if slide and rows[1]:IsShown() then
		local old = rows[1]
		ghost.icon:SetTexture(old.icon:GetTexture())
		ghost.title:SetText(old.title:GetText())
		ghost.detail:SetText(old.detail:GetText())
		ghost.xp:SetText(old.xp:GetText())
		ghost.time:SetText(old.time:GetText())
		ghost.stripe:SetVertexColor(old.stripe:GetVertexColor())
		ghost.highlight:SetShown(old.highlight:IsShown())
		ghost.bar:Hide()
		ghost:ClearAllPoints()
		ghost:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, old.y or -6)
		ghost:SetAlpha(1)
		ghost:Show()
		ghost.fade:Play()
	end

	-- a divider line: the zone ahead, or a gold "Level 35" after the step that levels you up
	local function divider(text, level)
		if nDiv >= MAX_ROWS then return end
		nDiv = nDiv + 1
		local d = dividers[nDiv]
		styleDivider(d, level)
		d.text:SetText(text)
		d:ClearAllPoints()
		d:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, y)
		d:Show()
		if slide then d.slide:Play() end
		y = y - DIV_H
	end

	for i = 1, shown do
		local s, r = steps[i], rows[i]
		local zone = zoneOf(s.point)
		if zone and zone ~= prevZone and zoneName(zone) then divider(zoneName(zone), false) end
		if zone then prevZone = zone end

		local titleText, detail, xp, icon = describe(s, plan)
		-- kills earn double while rested XP lasts
		local kills = s.mobXp or 0
		local bonus
		bonus, rested = E.RestedBonus(rested, kills)
		gained = gained + (s.kind == "turnin" and s.xp or 0) + kills + bonus
		local dingHere = false
		if need and not dinged and gained >= need then dinged, dingHere = true, true end
		r.kind = s.kind
		if s.kind == "travel" and s.mode == "hearth" and not hearthFound then hearthFound = r end
		r.icon:SetTexture(icon)
		r.title:SetText(titleText)
		r.detail:SetText(detail)
		-- top line: +XP, or a dim dash when the step gives none
		r.xp:SetText((xp and xp ~= "") and xp or "|cff666666-|r")
		-- bottom line: the step's time (every step that takes any)
		r.time:SetText(s.work and s.work > 0 and ns.shortTime(s.work) or "")

		local current = (i == 1)
		r.highlight:SetShown(current)
		local c = stripeOf(s)
		r.stripe:SetVertexColor(c[1], c[2], c[3], current and 1 or 0.7)
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

		-- where you'll be after this step, as % of the level: "»64%", or "»L35 12%" past a ding
		-- (» not an arrow: the game's font has no arrow glyph and draws an empty box)
		-- (next level's size taken as this one's: close enough for a glance)
		if need and max and max > 0 then
			local total, lvl = (max - need) + gained, ns.playerLevel()
			while total >= max do total, lvl = total - max, lvl + 1 end
			local pct = math.floor(total / max * 100)
			local where = lvl > ns.playerLevel() and string.format("|cffffd100»L%d %d%%|r", lvl, pct)
				or string.format("»%d%%", pct)
			local t = r.time:GetText()
			r.time:SetText((t and t ~= "") and (t .. " · " .. where) or where)
		end

		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, y)
		r.y = y
		y = y - (ROW_H + 2)
		r:Show()
		if slide then r.slide:Play() end
		if dingHere then divider(string.format("Level %d", ns.playerLevel() + 1), true) end
	end
	for i = shown + 1, MAX_ROWS do rows[i]:Hide() rows[i].slide:Stop() end
	for i = nDiv + 1, MAX_ROWS do dividers[i]:Hide() dividers[i].slide:Stop() end
	hearthRow = hearthFound
	placeHearth()
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
