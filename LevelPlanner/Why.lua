-- Why: explains why a quest is or isn't in the plan.
--   /lp why <quest name or ID>    or    Alt-click a quest in your quest log
local ADDON, zyde = ...
-- Part of Zyde_Forever since 2026-11-14: LevelPlanner keeps its own private table (zyde.LP) so its
-- names never clash with Zyde's.
zyde.LP = zyde.LP or {}
local ns = zyde.LP

local W = {}
ns.Why = W

local function say(text) ns.print(text) end

-- Quest IDs for a name (exact, as Questie spells it) or an ID.
local function resolve(input)
	local id = tonumber(input)
	if id then return { id } end
	local QDB = _G.LibQuestieDB and _G.LibQuestieDB.Quest
	if not (QDB and QDB.IdsByName) then return {} end
	local ids = ns.safe(QDB.IdsByName, input)
	if ids then return ids end
	-- the name typed in another case: each word capitalised ("Rattling The Rattlecages"), then the
	-- same with small words in lower case after the first ("Fields of Grief")
	local MINOR = { a = 1, an = 1, ["and"] = 1, at = 1, by = 1, ["for"] = 1, from = 1, ["in"] = 1, of = 1,
		on = 1, ["or"] = 1, the = 1, to = 1, with = 1 }
	local caps = input:lower():gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end)
	local first = true
	local title = input:lower():gsub("(%a)([%w']*)", function(a, b)
		local w = a .. b
		if not first and MINOR[w] then return w end
		first = false
		return a:upper() .. b
	end)
	local sentence = input:lower():gsub("^%a", string.upper)
	for _, name in ipairs({ caps, title, sentence }) do
		ids = ns.safe(QDB.IdsByName, name)
		if ids then return ids end
	end
	return {}
end

local function stepOf(id)
	for i, s in ipairs(ns.plan and ns.plan.stops or {}) do
		if s.questId == id then return i, s end
		local q = s.quest
		for _, part in ipairs(q and q.parts or {}) do
			if part.id == id then return i, s, q end
		end
	end
	return nil
end

local function dungeonFor(id)
	for _, d in ipairs(ns.candidates and ns.candidates.dungeons or {}) do
		for _, part in ipairs(d.parts or {}) do
			if part.id == id then return d end
		end
	end
	return nil
end

local function followUpFor(id)
	for _, q in ipairs(ns.candidates and ns.candidates.locked or {}) do
		if q.id == id then return q end
	end
	return nil
end

local KIND_WORDS = { pickup = "pick it up", turnin = "turn it in", objective = "work on it", dungeon = "run the dungeon" }

local UNPLANNABLE = {
	["item source unknown"] = "Questie doesn't know where its quest item comes from",
	["no location for objective"] = "Questie has no location for one of its objectives",
	["objective not in Questie's data"] = "the game lists an unfinished objective Questie has no data for - finish it yourself, then it plans the turn-in",
	["objectives unknown"] = "one of Forever's own quests, and Questie lists no objectives for it - pick it up yourself if you want it, then the game's quest log tells the planner what's left",
	["not seen on Forever"] = "Questie lists it, but no one has done it on Forever (no quest XP traced): likely a Season of Discovery leftover that isn't in the game",
	["no pickup location"] = "Questie has no location for the quest giver",
	["no turn-in location"] = "Questie has no location for the turn-in NPC",
	["started by an item"] = "it starts from an item, which can't be planned",
	["not in Questie's database"] = "Questie doesn't know this quest",
	["elite mobs (held back)"] = "it needs elite mobs - planned when grouped (/lp group on), with /lp elites on, or for a hunter solo once they are yellow",
	["elite (held back until grouped)"] = "it's an elite quest - planned when grouped (/lp group on), with /lp elites on, or for a hunter solo once it is yellow",
	["repeatable"] = "repeatable quests aren't planned",
	["pvp"] = "PvP quests aren't planned",
	["dungeon / raid"] = "dungeon and raid quests are only planned as part of a dungeon run",
	["no XP"] = "it gives no XP",
	["failed"] = "it has failed - abandon and pick it up again",
}

local function explainOne(id)
	local QS = ns.QuestSource
	local name = QS.Quest(id, "name") or ("Quest " .. id)
	local lvl, req = QS.Levels(id)
	local L = ns.playerLevel()
	say(string.format("|cffffd100%s|r (ID %d, level %d, needs %d):", name, id, lvl or 0, req or 0))

	local complete = Questie and Questie.db and Questie.db.char and Questie.db.char.complete or {}
	if complete[id] then say("  Already done.") return end
	if ns.skipped[id] then say("  You skipped it. Bring it back from \"...\" > Skipped quests (or /lp reset for all).") return end
	local dun = ns.Dungeons and ns.Dungeons.Of and ns.Dungeons.Of(id)
	if dun and ns.skipped["d:" .. dun] then
		say("  Its dungeon run is skipped. Bring it back from \"...\" > Skipped quests (or /lp reset for all).")
		return
	end

	local idx, s, dungeon = stepOf(id)
	-- a step done in passing (the step list's "On the way" section)
	for _, w in ipairs(not idx and ns.plan and ns.plan.onWay or {}) do
		if w.questId == id then
			say(string.format("  In the plan, on the way: %s - its mobs roam among the route's other quests, so you kill them in passing (the \"On the way\" section).", w.label or "?"))
			return
		end
	end
	if idx then
		if dungeon then
			say(string.format("  Planned as part of %s (step %d).", dungeon.name, idx))
		elseif s.early then
			say(string.format("  In the plan: step %d - picked up early, for later. This hour's route doesn't do it, but its giver is right by the route: taking it now costs ~%ds and saves a trip back worth ~%ds. Still worth doing at level %d (about %s h from now).",
				idx, math.floor(s.early.detour + 0.5), math.floor(s.early.saved + 0.5), s.early.future or 0, tostring(ns.cfg.earlyPickupHours or 3.5)))
		else
			say(string.format("  In the plan: step %d - %s.", idx, KIND_WORDS[s.kind] or s.kind))
			-- not first: how far its objective is from you, and what doing it now would cost
			if idx > 1 and ns.Planner.WhyNotFirst then
				local ok, lines = pcall(ns.Planner.WhyNotFirst, id)
				if ok then for _, l in ipairs(lines or {}) do say(l) end end
			end
		end
		return
	end

	local reason = QS.reasons[id]
	local inLog = QS.LogEntries()[id] ~= nil
	local planRate = ns.plan and ns.plan.rate or 0

	if reason == "dungeon quest" or (inLog and dungeonFor(id)) then
		local d = dungeonFor(id)
		if not d then
			say("  It's a dungeon quest, but that dungeon isn't at your level (or has no data in Config.dungeonData).")
			return
		end
		for _, info in ipairs(ns.plan and ns.plan.dungeonInfo or {}) do
			if info.name == d.name then
				if info.ok then
					say(string.format("  Part of a %s run (~%s XP/min on its own); the plan found questing faster this hour.",
						d.name, ns.short(info.rate)))
				else
					say(string.format("  Part of a %s run (~%s XP/min) - slower than questing (~%s XP/min). /lp group on to include it.",
						d.name, ns.short(info.rate), ns.short(planRate)))
				end
				return
			end
		end
		say("  Part of a " .. d.name .. " run, which wasn't considered this time.")
		return
	end

	if reason == "required level too high" then
		say(string.format("  You need level %d (you're %d).", req or 0, L))
	elseif reason and (reason:find("^red") or reason:find("^orange")) then
		local colour = reason:match("^(%a+)")
		local allowed = ns.cfg.maxLevelsAbove or 2
		if ns.IsGrouped() then
			say(string.format("  Level %d is %s for you (%d) - too high even for a group.", lvl or 0, colour, L))
		else
			say(string.format("  Level %d is %s for you (%d). Planned from level %d, or now with /lp group on.",
				lvl or 0, colour, L, (lvl or 0) - allowed))
		end
	elseif reason == "grey (too slow)" then
		local r = QS.ranks[id]
		say(string.format("  It's grey: reduced quest XP and its mobs give none. About %s XP/min - too slow next to the plan's ~%s.",
			ns.short((r and r.rate or 0) * 60), ns.short(planRate)))
	elseif reason == "grey" then
		say(string.format("  It's grey for you. Quick grey quests are still planned, but only ones within %d levels of you that start near you.",
			ns.cfg.greyMaxLevelsBelow or 8))
	elseif reason and reason:find("^not doable") then
		local f = followUpFor(id)
		if f then
			say("  It's a follow-up: it opens after an earlier quest, and the plan didn't fit both in this hour.")
		else
			local QDB = ns.Q.QuestieDB
			local text = QDB.IsDoableVerbose and ns.safe(QDB.IsDoableVerbose, id, false, true, false)
			say("  You can't take it yet: " .. (text or "a pre-quest, race, class or reputation requirement") .. ".")
		end
	elseif reason then
		local key = reason:gsub("^log: ", "")
		say("  LevelPlanner can't plan it: " .. (UNPLANNABLE[key] or key) .. ".")
	else
		local r = QS.ranks[id]
		if r then
			local keep = ns.cfg.maxCandidates or 60
			if r.rank > keep then
				say(string.format("  Ranked #%d of %d nearby quests by XP per minute; only the best %d are planned (Config.maxCandidates).",
					r.rank, r.of, keep))
			else
				say(string.format("  Considered, but slower than what's planned: ~%s XP/min on its own against the plan's ~%s.",
					ns.short(r.rate * 60), ns.short(planRate)))
				-- what it would really cost slotted into the route (on its own it counts the whole walk)
				local ok, lines = pcall(ns.Planner.Diagnose, id)
				if ok then for _, l in ipairs(lines or {}) do say(l) end end
			end
		elseif inLog then
			say("  It's in your log but not in this hour's plan - it's further away or slower than the planned quests.")
			-- what exactly: the rule that keeps it out, or what it would add against the route
			local ok, lines = pcall(ns.Planner.Diagnose, id)
			if not ok then say("  (couldn't check: " .. tostring(lines) .. ")")
			else for _, l in ipairs(lines or {}) do say(l) end end
		else
			say("  Not seen in the last scan: hidden in Questie, or the NPC didn't offer it when you talked to them.")
		end
	end
end

function W.Explain(input)
	input = (input or ""):match("^%s*(.-)%s*$")
	if input == "" then say("usage: /lp why <quest name or ID>  (or Alt-click a quest in your quest log)") return end
	local ids = resolve(input)
	if #ids == 0 then say("no quest called \"" .. input .. "\" found. Check the spelling, or use its ID.") return end
	for k = 1, math.min(3, #ids) do explainOne(ids[k]) end
	if #ids > 3 then say(string.format("(%d more quests share that name - use an ID)", #ids - 3)) end
end

-- Alt-click a quest in the quest log.
function W.Init()
	if not QuestLogTitleButton_OnClick then return end
	hooksecurefunc("QuestLogTitleButton_OnClick", function(self)
		if not IsAltKeyDown() then return end
		local index = self and self.GetID and self:GetID()
		if not index then return end
		local id
		if C_QuestLog and C_QuestLog.GetInfo then
			local info = C_QuestLog.GetInfo(index)
			id = info and info.questID
		end
		if not id and GetQuestLogTitle then id = select(8, GetQuestLogTitle(index)) end
		if id and not ns.isSecret(id) then W.Explain(tostring(id)) end
	end)
end
