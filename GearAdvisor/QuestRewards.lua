-- QuestRewards (phase b): on quest reward choices (at the NPC, in the quest log and the map's
-- quest log), a gold border on the best upgrade and a small % on every choice that's an upgrade.
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
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	border:SetBlendMode("ADD")
	border:SetVertexColor(1, 0.82, 0)
	border:SetPoint("CENTER", anchor, "CENTER", 0, 0)
	local size = (anchor.GetWidth and anchor:GetWidth() or 36)
	if not size or size < 10 then size = 36 end
	border:SetSize(size * 1.8, size * 1.8)
	local text = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	text:SetPoint("TOPLEFT", anchor, "TOPLEFT", 1, -1)
	m = { border = border, text = text }
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
		if m then m.border:Hide(); m.text:SetText("") end
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
			if r.kind == "upgrade" then m.text:SetTextColor(0.1, 1, 0.1) else m.text:SetTextColor(0.4, 0.8, 1) end
			if button == best then m.border:Show() end
		end
	end
	-- Item data not in yet: try again shortly (up to ~3 seconds).
	if loading and (tries or 0) < 10 then
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

if hooksecurefunc and QuestInfo_Display then
	hooksecurefunc("QuestInfo_Display", function() QuestRewards.refresh() end)
else
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "QUEST_DETAIL", "QUEST_COMPLETE", "QUEST_LOG_UPDATE" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function() C_Timer.After(0, QuestRewards.refresh) end)
end
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
