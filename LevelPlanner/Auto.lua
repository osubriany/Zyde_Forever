-- Auto: accepts and turns in the quests your plan picks up / turns in at the NPC you're talking to.
-- Only planned quests are touched. Turn-ins go first (they free log slots). A reward choice is
-- left to you. Hold the skip key (Shift by default) while opening the NPC to do it yourself.
local ADDON, zyde = ...
-- Part of Zyde_Forever since 2026-11-14: LevelPlanner keeps its own private table (zyde.LP) so its
-- names never clash with Zyde's.
zyde.LP = zyde.LP or {}
local ns = zyde.LP

local AQ = {}
ns.Auto = AQ

-- Planned pick-ups and turn-ins: [questId] = true
local function plannedSets()
	local pick, turn = {}, {}
	for _, s in ipairs(ns.plan and ns.plan.stops or {}) do
		if s.kind == "pickup" and s.questId then pick[s.questId] = true end
		if s.kind == "turnin" and s.questId then turn[s.questId] = true end
	end
	return pick, turn
end

local function enabled()
	if ns.cfg.autoQuests == false or not ns.plan then return false end
	local key = ns.cfg.autoQuestSkipKey or "SHIFT"
	if key == "SHIFT" and IsShiftKeyDown() then return false end
	if key == "CTRL" and IsControlKeyDown() then return false end
	if key == "ALT" and IsAltKeyDown() then return false end
	return true
end

local function valid(id)
	return type(id) == "number" and not ns.isSecret(id) and id > 0
end

-- Gossip window (modern style, with quest IDs).
local function onGossip()
	if not enabled() or not C_GossipInfo then return end
	local pick, turn = plannedSets()
	for _, q in ipairs(C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests() or {}) do
		if valid(q.questID) and q.isComplete and turn[q.questID] then
			C_GossipInfo.SelectActiveQuest(q.questID)
			return
		end
	end
	for _, q in ipairs(C_GossipInfo.GetAvailableQuests and C_GossipInfo.GetAvailableQuests() or {}) do
		if valid(q.questID) and pick[q.questID] then
			C_GossipInfo.SelectAvailableQuest(q.questID)
			return
		end
	end
end

-- Quest greeting window (older style, by index).
local function onGreeting()
	if not enabled() then return end
	local pick, turn = plannedSets()
	for i = 1, (GetNumActiveQuests and GetNumActiveQuests() or 0) do
		local _, isComplete = GetActiveTitle(i)
		local id = GetActiveQuestID and GetActiveQuestID(i)
		if isComplete and valid(id) and turn[id] then
			SelectActiveQuest(i)
			return
		end
	end
	for i = 1, (GetNumAvailableQuests and GetNumAvailableQuests() or 0) do
		local id = GetAvailableQuestInfo and select(5, GetAvailableQuestInfo(i))
		if valid(id) and pick[id] then
			SelectAvailableQuest(i)
			return
		end
	end
end

local function onDetail()
	if not enabled() then return end
	local id = GetQuestID and GetQuestID()
	local pick = plannedSets()
	if valid(id) and pick[id] then
		if QuestGetAutoAccept and QuestGetAutoAccept() then
			if AcknowledgeAutoAcceptQuest then AcknowledgeAutoAcceptQuest() end
		else
			AcceptQuest()
		end
	end
end

local function onProgress()
	if not enabled() then return end
	local id = GetQuestID and GetQuestID()
	local _, turn = plannedSets()
	if valid(id) and turn[id] and IsQuestCompletable() then CompleteQuest() end
end

local function onComplete()
	if not enabled() then return end
	local id = GetQuestID and GetQuestID()
	local _, turn = plannedSets()
	if not (valid(id) and turn[id]) then return end
	local choices = GetNumQuestChoices() or 0
	if choices > 1 then
		ns.print("pick your reward - LevelPlanner leaves reward choices to you.")
		return
	end
	GetQuestReward(1) -- the only reward (or none); same call Questie's own auto turn-in uses
end

function AQ.Init()
	local f = CreateFrame("Frame")
	for _, e in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE" }) do
		f:RegisterEvent(e)
	end
	f:SetScript("OnEvent", function(_, event)
		local handler = (event == "GOSSIP_SHOW" and onGossip) or (event == "QUEST_GREETING" and onGreeting)
			or (event == "QUEST_DETAIL" and onDetail) or (event == "QUEST_PROGRESS" and onProgress)
			or (event == "QUEST_COMPLETE" and onComplete)
		if handler then ns.safe(handler) end
	end)
end
