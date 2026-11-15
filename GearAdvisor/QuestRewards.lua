-- QuestRewards (phase b): on quest reward choices (at the NPC, in the quest log and the map's
-- quest log), every choice that's an upgrade has its name tinted green (blue: future upgrade) and a
-- big % on its icon; the best one is tinted stronger with a solid frame round its icon.
-- Game pieces used (seen working on Forever by SimGearForever, 2026-10-20): QuestInfoRewardsFrame
-- and MapQuestInfoRewardsFrame .RewardButtons, QuestInfo_Display, GetQuestItemLink (NPC) and
-- GetQuestLogItemLink (log), button.type ("choice"/"reward") and button:GetID() as the index.
local _, zyde = ...
zyde.GA = zyde.GA or {}
local ns = zyde.GA

local QuestRewards = {}
ns.QuestRewards = QuestRewards

local marks = setmetatable({}, { __mode = "k" })   -- button -> { border, text }
local generation = 0

local function markOf(button)
	local m = marks[button]
	if m then return m end
	local anchor = button.Icon or button
	-- the name part of the choice tinted green (blue for a future upgrade); the icon stays clear
	local tint = button:CreateTexture(nil, "ARTWORK", nil, 7)
	tint:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 0, 0)
	tint:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", 0, 0)
	tint:SetPoint("RIGHT", button, "RIGHT", 0, 0)
	tint:SetColorTexture(0.1, 0.9, 0.1, 0.3)
	-- the best choice also gets a solid 2-pixel frame round its icon
	local border = CreateFrame("Frame", nil, button)
	border:SetPoint("TOPLEFT", anchor, "TOPLEFT", -2, 2)
	border:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 2, -2)
	border:SetFrameLevel(button:GetFrameLevel() + 2)
	border.lines = {}
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local l = border:CreateTexture(nil, "OVERLAY")
		l:SetColorTexture(0.1, 1, 0.1, 1)
		if side == "TOP" or side == "BOTTOM" then
			l:SetPoint(side .. "LEFT"); l:SetPoint(side .. "RIGHT"); l:SetHeight(2)
		else
			l:SetPoint("TOP" .. side); l:SetPoint("BOTTOM" .. side); l:SetWidth(2)
		end
		border.lines[#border.lines + 1] = l
	end
	function border:SetVertexColor(r, g, b)
		for _, l in ipairs(self.lines) do l:SetColorTexture(r, g, b, 1) end
	end
	border:Hide()
	-- the % in big outlined numbers on a thin dark strip along the icon's bottom
	local back = button:CreateTexture(nil, "OVERLAY", nil, 6)
	back:SetColorTexture(0, 0, 0, 0.6)
	back:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
	back:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
	back:SetHeight(14)
	local text = button:CreateFontString(nil, "OVERLAY")
	text:SetDrawLayer("OVERLAY", 7) -- above the dark strip
	text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
	text:SetPoint("BOTTOM", anchor, "BOTTOM", 0, 1)
	m = { border = border, text = text, tint = tint, back = back }
	marks[button] = m
	return m
end

local function frames()
	return { _G.QuestInfoRewardsFrame, _G.MapQuestInfoRewardsFrame }
end

local function fromLog(frame)
	if frame == _G.MapQuestInfoRewardsFrame then return true end
	return _G.QuestInfoFrame ~= nil and _G.QuestInfoFrame.questLog == true
end

local function linkFor(frame, button)
	local kind = button.type
	local index = button.GetID and button:GetID()
	if kind ~= "choice" or not index or index < 1 then return nil end
	if button.objectType ~= nil and button.objectType ~= "item" then return nil end
	local fn = fromLog(frame) and GetQuestLogItemLink or GetQuestItemLink
	return ns.safe(fn, kind, index)
end

local function clear(frame)
	for _, button in ipairs(frame and frame.RewardButtons or {}) do
		local m = marks[button]
		if m then m.border:Hide(); m.tint:Hide(); m.back:Hide(); m.text:SetText("") end
	end
end

local function update(frame, mine, tries)
	if mine ~= generation then return end
	clear(frame)
	if not (frame and frame:IsShown() and ns.db and ns.db.questMarks) then return end
	local best, bestPct, loading = nil, 0, false
	local results = {}
	for _, button in ipairs(frame.RewardButtons or {}) do
		if button:IsShown() then
			local link = linkFor(frame, button)
			if not link and button.type == "choice" and (button.objectType == nil or button.objectType == "item") then
				loading = true -- the game hasn't sent this reward's link yet: look again shortly
			end
			if link then
				local ok, r = pcall(ns.Score.compare, link)
				if ok and r then
					if r.kind == "loading" then loading = true end
					results[button] = r
					if (r.kind == "upgrade" or r.kind == "future") and r.pct > bestPct then
						best, bestPct = button, r.pct
					end
				end
			end
		end
	end
	for button, r in pairs(results) do
		if r.kind == "upgrade" or r.kind == "future" then
			local m = markOf(button)
			m.text:SetText(("+%d%%"):format(math.floor(r.pct + 0.5)))
			local cr, cg, cb = 0.1, 1, 0.1
			if r.kind ~= "upgrade" then cr, cg, cb = 0.4, 0.8, 1 end
			m.text:SetTextColor(cr, cg, cb)
			m.tint:SetColorTexture(cr, cg, cb, button == best and 0.35 or 0.18)
			m.border:SetVertexColor(cr, cg, cb)
			m.tint:Show(); m.back:Show()
			if button == best then m.border:Show() end
		end
	end
	-- Item data not in yet: try again shortly (up to ~6 seconds).
	if loading and (tries or 0) < 20 then
		C_Timer.After(0.3, function() update(frame, mine, (tries or 0) + 1) end)
	end
end

function QuestRewards.refresh()
	generation = generation + 1
	local mine = generation
	for _, frame in ipairs(frames()) do
		if frame then pcall(update, frame, mine, 0) end
	end
end

-- The first time a quest's rewards are shown the game may still be filling the page (or sending
-- item data) after it is drawn, so look again a moment later, and whenever item data arrives
-- while a reward page is open.
local later = false
local function refreshSoon()
	QuestRewards.refresh()
	if later then return end
	later = true
	C_Timer.After(0.5, function() QuestRewards.refresh() end)
	C_Timer.After(1.5, function() later = false; QuestRewards.refresh() end)
end
local function anyShown()
	for _, frame in ipairs(frames()) do
		if frame and frame:IsVisible() then return true end
	end
	return false
end

if hooksecurefunc and QuestInfo_Display then
	hooksecurefunc("QuestInfo_Display", refreshSoon)
end
local events = CreateFrame("Frame")
for _, event in ipairs({ "QUEST_DETAIL", "QUEST_COMPLETE", "GET_ITEM_INFO_RECEIVED" }) do
	pcall(events.RegisterEvent, events, event)
end
if not (hooksecurefunc and QuestInfo_Display) then pcall(events.RegisterEvent, events, "QUEST_LOG_UPDATE") end
local itemQueued = false
events:SetScript("OnEvent", function(_, event)
	if event == "GET_ITEM_INFO_RECEIVED" then
		if itemQueued or not anyShown() then return end
		itemQueued = true
		C_Timer.After(0.2, function() itemQueued = false; QuestRewards.refresh() end)
		return
	end
	C_Timer.After(0, refreshSoon)
end)
ns.onChange(function() QuestRewards.refresh() end)

-- Zygor marks its own pick with a green arrow ("Highlight recommended quest rewards"). While our
-- marks are on, that setting is turned off so there's one verdict. It comes back on only if we were
-- the ones who turned it off (ns.db.zygorRewardsOff), when you turn our marks off with /ga quest.
local function syncZygor()
	local zgv = rawget(_G, "ZGV") or rawget(_G, "ZygorGuidesViewer")
	local profile = type(zgv) == "table" and zgv.db and zgv.db.profile
	if type(profile) ~= "table" or not ns.db then return end
	if ns.db.questMarks then
		if profile.questitemselector then
			profile.questitemselector = false
			ns.db.zygorRewardsOff = true
		end
	elseif ns.db.zygorRewardsOff then
		profile.questitemselector = true
		ns.db.zygorRewardsOff = nil
	end
end

local zygorEvents = CreateFrame("Frame")
zygorEvents:RegisterEvent("PLAYER_LOGIN")
zygorEvents:SetScript("OnEvent", function() C_Timer.After(2, function() pcall(syncZygor) end) end)   -- Zygor sets up its settings late
ns.onChange(function(reason) if reason == "questMarks" then pcall(syncZygor) end end)
