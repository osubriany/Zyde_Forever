-- QuestSource: the only file that talks to Questie and QuestieDB.
-- Everything is read at run time through their interfaces; nothing is copied from them.
local ADDON, zyde = ...
-- Part of Zyde_Forever since 2026-11-14: LevelPlanner keeps its own private table (zyde.LP) so its
-- names never clash with Zyde's.
zyde.LP = zyde.LP or {}
local ns = zyde.LP

local QS = {}
ns.QuestSource = QS

local Q = {}     -- Questie modules
ns.Q = Q
local LQDB       -- LibQuestieDB
local stats = {}

local REQUIRED_CONTRACT = 4

function QS.Init()
	LQDB = _G.LibQuestieDB
	if not (LQDB and LQDB.Quest and LQDB.Npc) then
		ns.print("QuestieDB is not loaded. LevelPlanner needs it.")
		return false
	end
	if LQDB.RequireContract then
		local ok, msg = LQDB.RequireContract(REQUIRED_CONTRACT)
		if not ok then ns.print(msg or "QuestieDB version mismatch.") return false end
	end
	if not QuestieLoader then
		ns.print("Questie's loader was not found.")
		return false
	end
	for _, name in ipairs({ "QuestieDB", "ZoneDB", "QuestXP", "ActiveQuests", "QuestLogCache",
			"QuestiePlayer", "QuestieLib", "AvailableQuests" }) do
		Q[name] = ns.safe(QuestieLoader.ImportModule, QuestieLoader, name)
	end
	if not (Q.QuestieDB and Q.QuestieDB.IsDoable and Q.ActiveQuests) then
		ns.print("this Questie version is missing functions LevelPlanner needs.")
		return false
	end
	ns.Geo.Init()
	return true
end

----------------------------------------------------------------------------------------
-- Field reads (all guarded)
----------------------------------------------------------------------------------------
function QS.Quest(id, field) return ns.safe(LQDB.Quest.Get, id, field) end
function QS.Npc(id, field) return ns.safe(LQDB.Npc.Get, id, field) end
function QS.Object(id, field) return ns.safe(LQDB.Object.Get, id, field) end
function QS.Item(id, field) return ns.safe(LQDB.Item.Get, id, field) end

function QS.IsFriendly(npcId)
	local f = QS.Npc(npcId, "friendlyToFaction")
	local fn = Q.QuestieDB.IsFriendlyToPlayer
	if fn then return ns.safe(fn, f) ~= false end
	return true
end

-- Quest level and required level, with scaling quests resolved for the player.
function QS.Levels(id)
	if Q.QuestieLib and Q.QuestieLib.GetEffectiveQuestLevel then
		local lvl, req = ns.safe(Q.QuestieLib.GetEffectiveQuestLevel, id, ns.playerLevel())
		if lvl then return lvl, req or 1 end
	end
	return QS.Quest(id, "questLevel") or 1, QS.Quest(id, "requiredLevel") or 1
end

-- Quest XP for this player. Second result is true when the number is only an estimate.
function QS.QuestXP(id)
	local QX = Q.QuestXP
	local xp = QX and QX.GetQuestLogRewardXP and ns.safe(QX.GetQuestLogRewardXP, QX, id, false)
	if xp and xp > 0 then return xp, false end
	return nil, true
end

-- The quest log as Questie sees it: [questId] = entry (title, isComplete, objectives{numFulfilled, numRequired, finished}).
function QS.LogEntries()
	local out = {}
	local all = ns.safe(Q.ActiveQuests.GetAll) or {}
	local cache = Q.QuestLogCache
	for questId in pairs(all) do
		local entry = cache and cache.TryGetQuest and ns.safe(cache.TryGetQuest, questId)
		out[questId] = entry or { objectives = {} }
	end
	return out
end

-- How many quests your log can hold: the game's own number (40 on Forever; 20 on classic realms).
function QS.LogCap()
	local n = C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and ns.safe(C_QuestLog.GetMaxNumQuestsCanAccept)
	if type(n) == "number" and not ns.isSecret(n) and n > 0 then return n end
	return tonumber(MAX_QUESTLOG_QUESTS) or 20
end

function QS.LogCount()
	local cache = Q.QuestLogCache
	local n = cache and cache.GetQuestCount and ns.safe(cache.GetQuestCount)
	if n then return n end
	local c = 0
	for _ in pairs(ns.safe(Q.ActiveQuests.GetAll) or {}) do c = c + 1 end
	return c
end

-- Questie's quest object: its ObjectiveData is in the same order as the game's quest log objectives.
function QS.GetQuest(id)
	return ns.safe(Q.QuestieDB.GetQuest, id)
end

function QS.DropRate(itemId, npcId)
	-- Forever's own rate where we know it (Data/QuestFixes.lua: ns.QuestDropRates[itemId] = % or
	-- { [npcId] = % }). Questie's rates are Classic's, often a flat private-server guess (50-100%).
	local over = ns.QuestDropRates and ns.QuestDropRates[itemId]
	if type(over) == "table" then over = over[npcId] or over.all end
	if type(over) == "number" and over > 0 then return math.min(over / 100, 1) end
	local fn = Q.QuestieDB.GetItemDroprate
	local r = fn and ns.safe(fn, itemId, npcId)
	if type(r) == "table" and type(r[1]) == "number" and r[1] > 0 then
		return math.min(r[1] / 100, 1)
	end
	return nil
end

----------------------------------------------------------------------------------------
-- Candidate scan
----------------------------------------------------------------------------------------
-- why each quest was or wasn't planned, for /lp why: [questId] = reason
QS.reasons = {}
QS.ranks = {}   -- [questId] = place among nearby available quests, by rough XP per minute
local function bump(reason, id)
	stats[reason] = (stats[reason] or 0) + 1
	if id then QS.reasons[id] = reason end
end

local function isTrivial(level)
	local fn = Q.QuestieDB.IsTrivial
	if fn then return ns.safe(fn, level) == true end
	return level < ns.playerLevel() - 7
end

-- Returns { available = {quest...}, log = {quest...} } where each quest comes from Stops.BuildQuest.
-- Runs inside a job (calls ns.Check to spread work over frames).
function QS.ScanCandidates()
	wipe(stats)
	wipe(QS.reasons)
	wipe(QS.ranks)
	local cfg = ns.cfg
	local QDB = Q.QuestieDB
	local player = ns.playerLevel()
	local complete = (Questie and Questie.db and Questie.db.char and Questie.db.char.complete) or {}
	local hidden = (Questie and Questie.db and Questie.db.char and Questie.db.char.hidden) or {}
	local AQ = Q.AvailableQuests
	local notOffered = AQ and AQ.__unavailableQuestsDeterminedByTalking or {}
	local log = QS.LogEntries()

	local result = { available = {}, log = {} }
	local found = {}   -- dungeon quests by dungeon: [area] = {log = {[id] = entry}, avail = {}, blocked = {}}
	local function dungeonList(area)
		found[area] = found[area] or { log = {}, avail = {}, blocked = {} }
		return found[area]
	end

	-- quests already in the log (unfinished dungeon quests wait for their dungeon run)
	for questId, entry in pairs(log) do
		ns.Check()
		if not ns.skipped[questId] then
			local area = entry.isComplete ~= 1 and ns.Dungeons.Of(questId)
			local tooHigh = not area and QS.TooHigh(questId, entry)
			if area then
				dungeonList(area).log[questId] = entry
			elseif tooHigh then
				bump(tooHigh, questId)
			else
				local quest, why = ns.Stops.BuildQuest(questId, entry)
				if quest then result.log[#result.log + 1] = quest else bump("log: " .. (why or "unplannable"), questId) end
			end
		end
	end

	-- quests not yet picked up
	local ids = ns.safe(LQDB.Quest.GetAllIds) or {}
	local grouped = ns.IsGrouped()
	local maxAbove = grouped and (cfg.groupMaxLevelsAbove or 6) or (cfg.maxLevelsAbove or 2)
	local blocked = {}   -- in level range but waiting for a pre-quest: maybe a follow-up later in the route
	local greyIds = {}   -- grey quests not too far below you, for the quick-grey check

	-- quest kinds we don't plan (returns a reason) — shared by available quests and follow-ups
	local function excluded(id)
		if QDB.IsRepeatable and ns.safe(QDB.IsRepeatable, id) then return "repeatable" end
		if (not cfg.includeDungeonQuests) and (ns.safe(QDB.IsDungeonQuest, id) or ns.safe(QDB.IsRaidQuest, id)) then
			return "dungeon / raid"
		end
		if ns.safe(QDB.IsPvPQuest, id) then return "pvp" end
		if ns.safe(QDB.IsGroupQuest, id) and not ns.AllowElite((QS.Levels(id))) then return "elite (held back until grouped)" end
		return nil
	end

	for i = 1, #ids do
		if i % 20 == 0 then ns.Check() end
		local id = ids[i]
		if complete[id] or log[id] or ns.skipped[id] or hidden[id] or notOffered[id] then
			-- already done, in log, skipped or hidden
		else
			local lvl, req = QS.Levels(id)
			local area = ns.Dungeons.Of(id)
			-- dungeon quests are done in a group, so they get the group's level allowance
			local above = area and (cfg.groupMaxLevelsAbove or 6) or maxAbove
			if req > player then
				bump("required level too high", id)
			elseif lvl - player > above then
				bump(QS.ColourReason(lvl - player, grouped), id)
			elseif isTrivial(lvl) then
				-- grey: kept aside; quick ones near you may still be worth doing (checked below)
				if cfg.greyQuests ~= false and not area and lvl >= player - (cfg.greyMaxLevelsBelow or 8) then
					greyIds[#greyIds + 1] = id
				end
				bump("grey", id)
			elseif not ns.safe(QDB.IsDoable, id) then
				bump("not doable (pre-quest, race, class...)", id)
				if area then dungeonList(area).blocked[#dungeonList(area).blocked + 1] = id
				else blocked[#blocked + 1] = id end
			elseif area then
				local list = dungeonList(area).avail
				list[#list + 1] = id
				bump("dungeon quest", id)
			else
				local why = excluded(id)
				if why then
					bump(why, id)
				else
					local quest
					quest, why = ns.Stops.BuildQuest(id, nil)
					if quest then
						result.available[#result.available + 1] = quest
					else
						bump(why or "unplannable", id)
					end
				end
			end
		end
	end
	stats["in log, plannable"] = #result.log
	stats["available, plannable"] = #result.available

	-- keep the most promising available quests (rough XP per minute from where you stand)
	local here = ns.Geo.PlayerPoint()
	local speed = ns.Geo.Speed()
	for _, q in ipairs(result.available) do
		local first = q.stops[1]
		local reach = here and first and ns.Stops.NearestPoint(first, here)
		local travel = reach and ns.Travel.Seconds(here, reach) or (cfg.continentChangeSeconds or 900)
		q.roughRate = q.xp / math.max(60, travel + q.workSeconds)
	end
	table.sort(result.available, function(a, b) return a.roughRate > b.roughRate end)
	for i, q in ipairs(result.available) do QS.ranks[q.id] = { rank = i, of = #result.available, rate = q.roughRate } end
	local keep = cfg.maxCandidates or 60
	for i = #result.available, keep + 1, -1 do result.available[i] = nil end

	-- quick grey quests: little quest XP and none from their mobs, but worth it when they are fast
	-- and close. Kept only if their rough XP per minute is near what your plan gets anyway.
	if #greyIds > 0 and here then
		local ref = ns.plan and ns.plan.rate and ns.plan.rate > 0 and ns.plan.rate / 60
		if not ref and #result.available > 0 then
			ref = result.available[math.ceil(#result.available / 2)].roughRate -- median nearby quest
		end
		local searchYards = cfg.greySearchYards or 1500
		local greys = {}
		for _, id in ipairs(greyIds) do
			ns.Check()
			if ns.safe(QDB.IsDoable, id) and not excluded(id) then
				local starts = QS.Quest(id, "startedBy")
				local near = false
				for _, npcId in ipairs(starts and starts[1] or {}) do
					for areaId, pts in pairs(QS.Npc(npcId, "spawns") or {}) do
						local c = pts[1]
						local p = c and ns.Geo.Point(areaId, c[1], c[2])
						local d = p and ns.Geo.Distance(here, p)
						if d and d <= searchYards then near = true end
					end
				end
				if near then
					local q = ns.Stops.BuildQuest(id, nil)
					if q then
						local first = q.stops[1]
						local reach = first and ns.Stops.NearestPoint(first, here)
						local travel = reach and ns.Travel.Seconds(here, reach) or 900
						q.roughRate = q.xp / math.max(60, travel + q.workSeconds)
						q.grey = true
						if not ref or q.roughRate >= ref * (cfg.greyMinRateShare or 0.8) then
							greys[#greys + 1] = q
						else
							QS.reasons[id] = "grey (too slow)"
							QS.ranks[id] = { rate = q.roughRate }
						end
					end
				end
			end
		end
		table.sort(greys, function(a, b) return a.roughRate > b.roughRate end)
		for i, q in ipairs(greys) do
			if i > (cfg.greyCandidates or 8) then break end
			QS.reasons[q.id] = nil
			result.available[#result.available + 1] = q
		end
		stats["quick grey quests offered"] = math.min(#greys, cfg.greyCandidates or 8)
	end

	-- follow-ups: quests that open once a quest already in the route is turned in,
	-- then the quests those open in turn (up to Config.chainDepth steps)
	result.locked = {}
	local inRoute = {}
	for _, q in ipairs(result.log) do inRoute[q.id] = q end
	for _, q in ipairs(result.available) do inRoute[q.id] = q end
	if cfg.chainLookahead ~= false then
		for _ = 1, (cfg.chainDepth or 2) do
			local added = 0
			for _, id in ipairs(blocked) do
				ns.Check()
				if not inRoute[id] then
					local requires = QS.ChainRequires(id, inRoute, complete, log)
					if requires and not excluded(id) then
						local quest = ns.Stops.BuildQuest(id, nil)
						if quest then
							quest.requires = requires
							local names = {}
							for _, r in ipairs(requires) do names[#names + 1] = inRoute[r].name end
							quest.stops[1].label = quest.stops[1].label .. " (opens after " .. table.concat(names, ", ") .. ")"
							result.locked[#result.locked + 1] = quest
							inRoute[id] = quest
							added = added + 1
						end
					end
				end
			end
			if added == 0 then break end
		end
		stats["follow-ups, plannable"] = #result.locked

		-- chain value: a quest that opens later quests (not already planned) is worth part of their XP
		local unlocks = QS.UnlockIndex()
		local factor = cfg.chainValueFactor or 0.5
		local maxDepth = cfg.chainDepth or 2
		local function future(id, depth, seen)
			if depth > maxDepth then return 0 end
			local total = 0
			for _, u in ipairs(unlocks[id] or {}) do
				if not complete[u] and not inRoute[u] and not seen[u] and QS.RaceClassOk(u) then
					seen[u] = true
					local lvl, req = QS.Levels(u)
					if req <= player + 3 and not isTrivial(lvl) then
						total = total + ns.Estimate.QuestXP(u, lvl) * factor ^ depth + future(u, depth + 1, seen)
					end
				end
			end
			return total
		end
		for _, list in ipairs({ result.log, result.available, result.locked }) do
			for _, q in ipairs(list) do
				ns.Check()
				q.chainValue = future(q.id, 1, {})
				q.value = q.xp + q.chainValue
			end
		end
	end

	-- dungeons: each one as a single planned run with its quests and pre-quests
	result.dungeons = {}
	if cfg.dungeons ~= false then
		local poolIds = {}
		for _, q in ipairs(result.log) do poolIds[q.id] = true end
		for _, q in ipairs(result.available) do poolIds[q.id] = true end
		result.dungeons = ns.Dungeons.BuildAll(found, poolIds, complete, log)
		stats["dungeons, plannable"] = #result.dungeons
	end

	-- grinding camps, as filler the planner can use when quests are slow
	result.grind = cfg.grinding ~= false and ns.Extras.GrindCandidates(here) or {}
	stats["grinding camps offered"] = #result.grind
	return result
end

-- If a quest is held back only by pre-quests that are themselves candidates, returns the list of
-- those pre-quests (they must be turned in first). Otherwise nil. Deliberately strict: anything
-- else that could block the quest (profession, reputation, spell, exclusive quests) rules it out.
function QS.RaceClassOk(id)
	local QP = Q.QuestiePlayer
	local races, classes = QS.Quest(id, "requiredRaces"), QS.Quest(id, "requiredClasses")
	if races and races ~= 0 and QP and QP.HasRequiredRace and not ns.safe(QP.HasRequiredRace, races) then return false end
	if classes and classes ~= 0 and QP and QP.HasRequiredClass and not ns.safe(QP.HasRequiredClass, classes) then return false end
	return true
end

-- [quest] = quests that list it as a pre-quest. Built once per session (inside a job).
local unlockIndex
function QS.UnlockIndex()
	if unlockIndex then return unlockIndex end
	local u = {}
	local ids = ns.safe(LQDB.Quest.GetAllIds) or {}
	for i = 1, #ids do
		if i % 50 == 0 then ns.Check() end
		local id = ids[i]
		for _, field in ipairs({ "preQuestSingle", "preQuestGroup" }) do
			local pre = QS.Quest(id, field)
			if type(pre) == "table" then
				for _, p in ipairs(pre) do
					p = math.abs(p)
					u[p] = u[p] or {}
					u[p][#u[p] + 1] = id
				end
			end
		end
	end
	unlockIndex = u
	return u
end

-- Flight masters friendly to you, with a placeable position (see Places.lua). Call inside a job.
function QS.FlightMasters()
	return ns.Places.List("Flight Master")
end

function QS.ChainRequires(id, inRoute, complete, log)
	if not QS.RaceClassOk(id) then return nil end
	for _, f in ipairs({ "requiredSkill", "requiredMinRep", "requiredMaxRep", "requiredSourceItems", "requiredRanks" }) do
		if QS.Quest(id, f) then return nil end
	end
	for _, f in ipairs({ "requiredSpell", "requiredSpecialization", "parentQuest", "availableStartingWith" }) do
		local v = QS.Quest(id, f)
		if v and v ~= 0 then return nil end
	end
	for _, ex in ipairs(QS.Quest(id, "exclusiveTo") or {}) do
		if complete[ex] or log[ex] then return nil end
	end
	local nxt = QS.Quest(id, "nextQuestInChain")
	if nxt and nxt ~= 0 and (complete[nxt] or log[nxt]) then return nil end

	local single = QS.Quest(id, "preQuestSingle")
	if type(single) == "table" and #single > 0 then
		for _, p in ipairs(single) do
			if complete[p] then return nil end -- already met, so something else blocks it
		end
		for _, p in ipairs(single) do
			if inRoute[p] then return { p } end
		end
		return nil
	end
	local group = QS.Quest(id, "preQuestGroup")
	if type(group) == "table" and #group > 0 then
		local missing = {}
		for _, p in ipairs(group) do
			p = math.abs(p)
			if not complete[p] then
				if not inRoute[p] then return nil end
				missing[#missing + 1] = p
			end
		end
		if #missing > 0 then return missing end
	end
	return nil
end

-- Free slots in normal bags (special bags such as soul or herb bags don't hold quest items).
function QS.FreeBagSlots()
	local getFree = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
	if not getFree then return 99 end
	local free = 0
	for bag = 0, 4 do
		local n, bagType = getFree(bag)
		if n and (bagType == nil or bagType == 0) then free = free + n end
	end
	return free
end

-- "orange (held back until grouped)" and the like, for a quest this many levels above you.
function QS.ColourReason(above, grouped)
	local colour = above >= 5 and "red" or "orange"
	if grouped then return colour .. " (too high even for a group)" end
	return colour .. " (held back until grouped)"
end

-- A quest in your log that's too far above you to work on yet (orange or red when solo).
-- A finished one may still be turned in. Returns a reason, or nil when it's fine.
function QS.TooHigh(questId, entry)
	if entry and entry.isComplete == 1 then return nil end
	local grouped = ns.IsGrouped()
	local allowed = grouped and (ns.cfg.groupMaxLevelsAbove or 6) or (ns.cfg.maxLevelsAbove or 2)
	local lvl = QS.Levels(questId)
	local above = (lvl or 0) - ns.playerLevel()
	if above > allowed then return QS.ColourReason(above, grouped) end
	return nil
end

-- After objective progress: rebuild only the quests in the log (remaining counts changed).
function QS.RebuildLog(cands)
	if not cands then return end
	local log = QS.LogEntries()
	local fresh = {}
	-- quests that belong to a planned dungeon run stay with it until the next full scan
	local claimed = {}
	for _, d in ipairs(cands.dungeons or {}) do
		for _, q in ipairs(d.parts or {}) do claimed[q.id] = true end
	end
	for questId, entry in pairs(log) do
		ns.Check()
		if not ns.skipped[questId] and not claimed[questId] and not QS.TooHigh(questId, entry) then
			local quest = ns.Stops.BuildQuest(questId, entry)
			if quest then fresh[#fresh + 1] = quest end
		end
	end
	-- keep each quest's chain value from the last full scan
	local chain = {}
	for _, q in ipairs(cands.log or {}) do chain[q.id] = q.chainValue end
	for _, q in ipairs(fresh) do
		q.chainValue = chain[q.id]
		if q.chainValue then q.value = q.xp + q.chainValue end
	end
	cands.log = fresh
	-- a quest that moved into the log must not stay in the not-yet-picked-up lists
	for _, list in ipairs({ cands.available, cands.locked or {} }) do
		for i = #list, 1, -1 do
			if log[list[i].id] then table.remove(list, i) end
		end
	end
end

function QS.PrintScanStats()
	if not next(stats) then ns.print("no scan yet.") return end
	ns.print("last quest scan:")
	local keys = {}
	for k in pairs(stats) do keys[#keys + 1] = k end
	table.sort(keys)
	for _, k in ipairs(keys) do ns.print("  " .. k .. ": " .. stats[k]) end
end
