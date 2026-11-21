-- Stops: turns one quest into stops — pick up, one per objective (an area, not a point), turn in.
local ADDON, zyde = ...
-- Part of Zyde_Forever since 2026-11-14: LevelPlanner keeps its own private table (zyde.LP) so its
-- names never clash with Zyde's.
zyde.LP = zyde.LP or {}
local ns = zyde.LP

local S = {}
ns.Stops = S

local MAX_POINTS = 150   -- spawn points looked at per objective (more are sampled)
local fixStop            -- (below) an objective stop from Data/QuestFixes.lua

----------------------------------------------------------------------------------------
-- Points and areas
----------------------------------------------------------------------------------------

-- All placeable points from a Questie spawn list {[areaId] = {{x,y},...}}.
local function pointsFromSpawns(spawns, out)
	out = out or {}
	if type(spawns) ~= "table" then return out end
	for areaId, list in pairs(spawns) do
		if type(list) == "table" then
			for _, c in ipairs(list) do
				local p = ns.Geo.Point(areaId, c[1], c[2])
				if p then out[#out + 1] = p end
			end
		end
	end
	return out
end

local function npcPoints(npcIds, friendlyOnly, out)
	out = out or {}
	for _, id in ipairs(npcIds or {}) do
		if (not friendlyOnly) or ns.QuestSource.IsFriendly(id) then
			pointsFromSpawns(ns.QuestSource.Npc(id, "spawns"), out)
		end
	end
	return out
end

local function objectPoints(objectIds, out)
	out = out or {}
	for _, id in ipairs(objectIds or {}) do
		pointsFromSpawns(ns.QuestSource.Object(id, "spawns"), out)
	end
	return out
end

-- Groups spawn points into up to N areas. Each area is its densest spawn point, with how many
-- spawns lie within the cluster radius.
local function clusterAreas(points)
	local cfg = ns.cfg
	local radius = cfg.clusterRadius or 120
	local r2 = radius * radius
	local pts = points
	if #pts > MAX_POINTS then
		pts = {}
		local step = #points / MAX_POINTS
		for i = 1, MAX_POINTS do pts[i] = points[math.floor((i - 1) * step) + 1] end
	end
	local used, areas = {}, {}
	for _ = 1, (cfg.maxAreasPerObjective or 3) do
		local best, bestCount = nil, 0
		for i, a in ipairs(pts) do
			if not used[i] then
				local n = 0
				for j, b in ipairs(pts) do
					if not used[j] and a.inst == b.inst then
						local dx, dy = a.wx - b.wx, a.wy - b.wy
						if dx * dx + dy * dy <= r2 then n = n + 1 end
					end
				end
				if n > bestCount then best, bestCount = i, n end
			end
		end
		if not best then break end
		local centre = pts[best]
		for j, b in ipairs(pts) do
			if not used[j] and centre.inst == b.inst then
				local dx, dy = centre.wx - b.wx, centre.wy - b.wy
				if dx * dx + dy * dy <= r2 then used[j] = true end
			end
		end
		local area = {}
		for k, v in pairs(centre) do area[k] = v end
		area.count = bestCount
		areas[#areas + 1] = area
	end
	return areas
end

function S.NearestPoint(stop, from)
	local best, bestD
	for _, p in ipairs(stop.points) do
		local d = ns.Geo.Distance(from, p)
		if d and (not bestD or d < bestD) then best, bestD = p, d end
	end
	return best or stop.points[1]
end

----------------------------------------------------------------------------------------
-- Counts from quest text ("Kill 10 Kobold Vermin")
----------------------------------------------------------------------------------------
local function escape(s) return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end

local function countFromText(texts, name, default)
	if type(texts) ~= "table" or not name or name == "" then return default end
	local candidates = { name, name:match("^(%S+)") }
	for _, t in ipairs(texts) do
		if type(t) == "string" then
			for _, n in ipairs(candidates) do
				local num = t:match("(%d+)%s+" .. escape(n))
				if num then
					num = tonumber(num)
					if num and num > 0 and num <= 100 then return num end
				end
			end
		end
	end
	return default
end

----------------------------------------------------------------------------------------
-- Objectives
----------------------------------------------------------------------------------------

-- Seconds one gold is worth when buying: the time it takes to earn it at your level
-- (cfg.goldPerHourByLevel, straight lines between the listed levels), unless set outright.
function S.SecondsPerGold()
	local cfg = ns.cfg
	if type(cfg.buySecondsPerGold) == "number" then return cfg.buySecondsPerGold end
	local tbl = cfg.goldPerHourByLevel or { [10] = 0.5, [20] = 1.5, [30] = 3, [40] = 6, [50] = 10, [60] = 18 }
	local L = ns.playerLevel()
	local lo, hi
	for lvl in pairs(tbl) do
		if lvl <= L and (not lo or lvl > lo) then lo = lvl end
		if lvl >= L and (not hi or lvl < hi) then hi = lvl end
	end
	lo, hi = lo or hi, hi or lo
	local gph = tbl[lo]
	if hi ~= lo then gph = tbl[lo] + (tbl[hi] - tbl[lo]) * (L - lo) / (hi - lo) end
	return 3600 / math.max(gph or 1, 0.1)
end

-- A quest item nobody drops: buy it. From a vendor Questie knows sells it, else at the auction house
-- when AHledger has seen it listed (lowest buyout, else median) and it costs at most cfg.ahBuyMaxGold.
-- The gold counts as time (S.SecondsPerGold: how long you'd take to earn it), so the planner weaves
-- it in only when the detour and the price are worth it. Returns a finished stop, or nil.
local function buyStop(quest, itemId, itemName, need)
	local QS, cfg = ns.QuestSource, ns.cfg
	local function make(points, label, seconds)
		if #points == 0 then return nil end
		if #points > 12 then -- (keep a spread of places; the planner picks the nearest)
			local few, step = {}, #points / 12
			for i = 1, 12 do few[i] = points[math.floor((i - 1) * step) + 1] end
			points = few
		end
		return { kind = "objective", questId = quest.id, questName = quest.name, mobXp = 0, buy = true,
			points = points, work = seconds, label = label, need = need }
	end
	if cfg.buyQuestItems == false then return nil end
	-- 1) a vendor
	local vendors = QS.Item(itemId, "vendors")
	if type(vendors) == "table" and #vendors > 0 then
		local s = make(npcPoints(vendors, true), string.format("Buy %d %s from %s", need, itemName,
			QS.Npc(vendors[1], "name") or "a vendor"), cfg.buySeconds or 30)
		-- (bought for you when you open the vendor, UI/Shopping.lua)
		if s then s.buyItem, s.buyName, s.buyCount, s.buyVendor = itemId, itemName, need, true return s end
	end
	-- 2) the auction house
	if cfg.ahBuy == false then return nil end
	local api = _G.AHledgerAPI
	local p = api and api.GetPrice and ns.safe(api.GetPrice, itemId)
	local each = p and (p.minBuyout or p.median)
	if type(each) ~= "number" or each <= 0 then return nil end
	local total = each * need
	if total > (cfg.ahBuyMaxGold or 5) * 10000 then return nil end
	local places = ns.Places and ns.Places.List("Auctioneer") or {}
	local pts = {}
	for _, pl in ipairs(places) do pts[#pts + 1] = pl.point end
	local gold = total / 10000
	local s = make(pts, string.format("Buy %d %s at the auction house (~%s)", need, itemName,
		gold >= 1 and string.format("%.1fg", gold) or string.format("%ds", math.max(1, math.floor(total / 100)))),
		(cfg.ahBuySeconds or 60) + gold * S.SecondsPerGold())
	-- (for the shopping list at the auction house, UI/Shopping.lua)
	if s then s.buyItem, s.buyName, s.buyCount, s.buyEach, s.buyAH = itemId, itemName, need, each, true end
	return s
end

-- An item you could farm, but that a vendor sells or the auction house lists: buy it instead when
-- that's quicker. Buying gives no kill XP, so the farm's time is counted net of the XP its kills earn
-- (at your plan's XP per second): kills that pay as well as questing cost nothing extra.
-- farmWork: the farm stop's seconds (with its overhead); mobXp: its kill XP. Returns a buy stop, or nil.
local function buyInstead(quest, itemId, itemName, need, farmWork, mobXp)
	local cfg = ns.cfg
	if cfg.buyInsteadOfFarming == false then return nil end
	local buy = buyStop(quest, itemId, itemName, need)
	if not buy then return nil end
	local rate = ns.plan and ns.plan.rate and ns.plan.rate > 0 and ns.plan.rate / 60 -- XP per second
	local farmCost = farmWork - ((rate and mobXp and mobXp > 0) and (mobXp / rate) or 0)
	farmCost = math.max(farmCost, farmWork * 0.25)
	if buy.work < farmCost then
		buy.label = buy.label .. "  |cff999999(quicker than farming)|r"
		return buy
	end
	return nil
end

-- Builds one objective stop. `remaining` is how many are still needed (nil = unknown, use text/defaults).
-- Returns stop, or nil plus a reason when the objective can't be planned.
local function objectiveStop(quest, od, remaining)
	local QS, E, cfg = ns.QuestSource, ns.Estimate, ns.cfg
	local stop = { kind = "objective", questId = quest.id, questName = quest.name, work = 0, mobXp = 0 }
	local points

	if od.Type == "monster" or od.Type == "killcredit" then
		local ids = od.Type == "monster" and { od.Id } or (od.IdList or {})
		local name = od.Text or QS.Npc(ids[1] or 0, "name") or "mobs"
		local need = remaining or countFromText(quest.texts, QS.Npc(ids[1] or 0, "name") or name, cfg.defaultKillCount or 8)
		local lvl = E.NpcLevel(ids[1] or 0)
		local rank = QS.Npc(ids[1] or 0, "rank")
		if (rank == 1 or rank == 2 or rank == 3) and not ns.AllowElite(lvl, rank) then return nil, "elite mobs (held back)" end
		points = npcPoints(ids, false)
		local mobName = QS.Npc(ids[1] or 0, "name")
		stop.mobs = {}
		for _, id in ipairs(ids) do stop.mobs[id] = true end
		local key = od.Type == "monster" and ("monster:" .. tostring(od.Id)) or ("killcredit:" .. tostring(od.RootId))
		stop.work = need * E.UnitSeconds(key, E.KillSeconds(lvl, rank, mobName))
		stop.mobXp = need * E.MobXP(lvl, rank)
		stop.mobLevel, stop.mobRank = lvl, rank -- (the planner re-prices the kills after a level-up)
		stop.label = string.format("Kill %d %s", need, mobName or name)
		stop.need = need

	elseif od.Type == "object" then
		local name = od.Text or QS.Object(od.Id, "name") or "objects"
		local need = remaining or countFromText(quest.texts, QS.Object(od.Id, "name") or name, cfg.defaultObjectCount or 4)
		points = objectPoints({ od.Id })
		stop.work = need * E.UnitSeconds("object:" .. tostring(od.Id), cfg.objectSeconds or 12)
		stop.label = string.format("Use %d %s", need, name)
		stop.need = need

	elseif od.Type == "item" then
		if quest.sourceItemId and od.Id == quest.sourceItemId then return "skip" end -- given at pickup
		local itemName = QS.Item(od.Id, "name") or od.Text or "items"
		local need = remaining or countFromText(quest.texts, itemName, cfg.defaultItemCount or 6)
		local npcs = QS.Item(od.Id, "npcDrops")
		local objs = QS.Item(od.Id, "objectDrops")
		if type(npcs) == "table" and #npcs > 0 then
			-- hostile droppers only; average their drop rate. Rares and elites (rank > 0) are left
			-- out when normal mobs drop it too: you farm the normal mobs, and a rare's low drop rate
			-- (Satyr Horns: rares ~5-11% next to ~42%) would make the quest look far slower than it is.
			local hostile, normal, rateSum, rateN, normSum, normN = {}, {}, 0, 0, 0, 0
			for _, npcId in ipairs(npcs) do
				if not QS.IsFriendly(npcId) or QS.Npc(npcId, "friendlyToFaction") == nil then
					hostile[#hostile + 1] = npcId
					local r = QS.DropRate(od.Id, npcId)
					local rk = QS.Npc(npcId, "rank")
					local isNormal = not (rk == 1 or rk == 2 or rk == 3 or rk == 4)
					if isNormal then normal[#normal + 1] = npcId end
					if r then
						rateSum, rateN = rateSum + r, rateN + 1
						if isNormal then normSum, normN = normSum + r, normN + 1 end
					end
				end
			end
			if #normal > 0 then hostile = normal end
			if normN > 0 then rateSum, rateN = normSum, normN end
			if #hostile == 0 then hostile = npcs end
			local rate = rateN > 0 and (rateSum / rateN) or (cfg.defaultDropRate or 0.5)
			rate = math.max(rate, 0.05)
			local kills = math.ceil(need / rate)
			local lvl = E.NpcLevel(hostile[1])
			local rank = QS.Npc(hostile[1], "rank")
			if (rank == 1 or rank == 2 or rank == 3) and not ns.AllowElite(lvl, rank) then return nil, "elite mobs (held back)" end
			points = npcPoints(hostile, false)
			stop.mobs = {}
			for _, id in ipairs(hostile) do stop.mobs[id] = true end
			-- default: kills needed x kill time; learned: your real seconds per item
			local perItem = kills * E.KillSeconds(lvl, rank, QS.Npc(hostile[1], "name")) / need
			stop.work = need * E.UnitSeconds("item:" .. tostring(od.Id), perItem)
			stop.mobXp = kills * E.MobXP(lvl, rank)
			stop.mobLevel, stop.mobRank = lvl, rank -- (the planner re-prices the kills after a level-up)
			stop.label = string.format("Collect %d %s (~%d kills)", need, itemName, kills)
			-- sold or listed for less than the farm costs you? buy it
			local bought = buyInstead(quest, od.Id, itemName, need,
				stop.work + (cfg.objectiveOverheadSeconds or 45), stop.mobXp)
			if bought then return bought end
		elseif type(objs) == "table" and #objs > 0 then
			points = objectPoints(objs)
			-- picked up from the ground: learned apart from mob drops (see Learn.lua)
			stop.work = need * E.UnitSeconds("itempick:" .. tostring(od.Id), cfg.objectSeconds or 12)
			stop.label = string.format("Collect %d %s", need, itemName)
			local bought = buyInstead(quest, od.Id, itemName, need,
				stop.work + (cfg.objectiveOverheadSeconds or 45), 0)
			if bought then return bought end
		else
			-- Questie doesn't know where it comes from: Data/QuestFixes.lua may ([quest].items[itemId])
			local fix = ns.QuestFixes and ns.QuestFixes[quest.id]
			local fo = fix and fix.items and fix.items[od.Id]
			if fo and fo.kind == "have" then return "skip" end -- handed to you with the quest
			if fo then return fixStop(quest, fo, "i" .. od.Id, remaining) end
			-- nobody drops it: buy it (a vendor, else the auction house)
			-- (how many: the log, else the quest text; "Bring a Moonsteel Broadsword" means 1, not the
			-- drop default)
			local bought = buyStop(quest, od.Id, itemName, remaining or countFromText(quest.texts, itemName, 1))
			if bought then return bought end
			return nil, "item source unknown"
		end
		stop.need = need

	elseif od.Type == "event" then
		points = pointsFromSpawns(od.Coordinates)
		stop.work = cfg.eventSeconds or 20
		stop.label = od.Text or "Reach the area"
		if quest.escort then
			stop.escort = true
			stop.label = "Escort: " .. (od.Text or quest.name) .. " (stay with them)"
		end

	else
		return nil, "objective type " .. tostring(od.Type)
	end

	if not points or #points == 0 then return nil, "no location for objective" end
	stop.points = clusterAreas(points)
	stop.work = stop.work + (cfg.objectiveOverheadSeconds or 45)
	return stop
end

-- One objective from Data/QuestFixes.lua (filled in by hand where Questie has none).
-- fo: { kind = "kill" | "loot" | "spot", name, count, ids, spawns }. index: its place in the entry.
fixStop = function(quest, fo, index, remaining)
	local QS, E, cfg = ns.QuestSource, ns.Estimate, ns.cfg
	local stop = { kind = "objective", questId = quest.id, questName = quest.name, work = 0, mobXp = 0, fixed = true }
	local points = pointsFromSpawns(fo.spawns)
	local key = "fix:" .. quest.id .. ":" .. index -- (learned seconds per unit, apart from Questie's objectives)
	if fo.kind == "kill" or fo.kind == "loot" then
		local ids = fo.ids or {}
		local lvl = E.NpcLevel(ids[1] or 0) or quest.level or ns.playerLevel()
		local rank = QS.Npc(ids[1] or 0, "rank")
		if (rank == 1 or rank == 2 or rank == 3) and not ns.AllowElite(lvl, rank) then return nil, "elite mobs (held back)" end
		stop.mobs = {}
		for _, id in ipairs(ids) do stop.mobs[id] = true end
		if fo.kind == "kill" then
			local need = remaining or fo.count or countFromText(quest.texts, fo.name, cfg.defaultKillCount or 8)
			stop.work = need * E.UnitSeconds(key, E.KillSeconds(lvl, rank, fo.name))
			stop.mobXp = need * E.MobXP(lvl, rank)
			stop.mobLevel, stop.mobRank = lvl, rank -- (the planner re-prices the kills after a level-up)
			stop.label = string.format("Kill %d %s", need, fo.name or "mobs")
			stop.need = need
		else
			-- a quest item from these mobs: drop rate unknown, so the usual default
			local need = remaining or fo.count or cfg.defaultItemCount or 6
			local kills = math.ceil(need / math.max(cfg.defaultDropRate or 0.5, 0.05))
			stop.work = need * E.UnitSeconds(key, kills * E.KillSeconds(lvl, rank, fo.name) / need)
			stop.mobXp = kills * E.MobXP(lvl, rank)
			stop.mobLevel, stop.mobRank = lvl, rank -- (the planner re-prices the kills after a level-up)
			stop.label = string.format("Collect %d from %s (~%d kills)", need, fo.name or "mobs", kills)
			stop.need = need
		end
	elseif fo.kind == "spot" then
		stop.work = fo.seconds or cfg.eventSeconds or 20
		stop.label = fo.name or "Go to the spot"
		-- a fee (gold) to pay there: counts as the time it takes you to earn it
		if fo.cost and fo.cost > 0 then
			stop.work = stop.work + fo.cost * S.SecondsPerGold()
			stop.label = string.format("%s (%sg fee)", stop.label, tostring(fo.cost))
		end
	elseif fo.kind == "objects" then
		-- click / loot things lying around (herbs, crates)
		local need = remaining or fo.count or countFromText(quest.texts, fo.name, cfg.defaultObjectCount or 4)
		stop.work = need * E.UnitSeconds(key, cfg.objectSeconds or 12)
		stop.label = string.format("Collect %d %s", need, fo.name or "objects")
		stop.need = need
	else
		return nil, "objective type " .. tostring(fo.kind)
	end
	if #points == 0 then return nil, "no location for objective" end
	stop.points = clusterAreas(points)
	stop.work = stop.work + (cfg.objectiveOverheadSeconds or 45)
	return stop
end

----------------------------------------------------------------------------------------
-- Whole quest
----------------------------------------------------------------------------------------

-- An escort quest: an "event" objective (bring someone somewhere) on a quest the database marks as
-- one the whole party gets when it starts (questFlags 2, set on escorts), or whose text says escort.
function S.IsEscort(qo)
	local hasEvent = false
	for _, od in ipairs(qo.ObjectiveData or {}) do
		if od.Type == "event" then hasEvent = true break end
	end
	if not hasEvent then return false end
	local flags = tonumber(qo.questFlags) or 0
	if flags % 4 >= 2 then return true end
	local texts = type(qo.objectivesText) == "table" and table.concat(qo.objectivesText, " ") or tostring(qo.objectivesText or "")
	return texts:lower():find("escort") ~= nil
end

-- logEntry: Questie's quest log entry when the quest is already picked up, else nil.
-- Returns quest {id, name, level, xp, stops, workSeconds} or nil plus a reason.
-- opts.dungeon: the objectives happen inside a dungeon, so only pick-up and turn-in stops are made.
function S.BuildQuest(questId, logEntry, opts)
	local QS, cfg = ns.QuestSource, ns.cfg
	local qo = QS.GetQuest(questId)
	if not qo then return nil, "not in Questie's database" end
	if logEntry and logEntry.isComplete == -1 then return nil, "failed" end

	local level = qo.level or QS.Levels(questId)
	local quest = {
		id = questId,
		name = qo.name or ("Quest " .. questId),
		level = level,
		texts = qo.objectivesText,
		sourceItemId = qo.sourceItemId,
		inLog = logEntry ~= nil,
		stops = {},
	}
	quest.escort = S.IsEscort(qo)
	quest.questXp, quest.xpEstimated = ns.Estimate.QuestXP(questId, level)
	-- grey for you: reduced quest XP, and its mobs give none (Estimate.MobXP already returns 0)
	local QDB = ns.Q.QuestieDB
	quest.grey = QDB and QDB.IsTrivial and ns.safe(QDB.IsTrivial, level) == true or false

	-- where Questie is missing something, a hand-filled entry (Data/QuestFixes.lua) may have it
	local fix = ns.QuestFixes and ns.QuestFixes[questId]

	-- Never seen on Forever, and nothing to do: Questie's quest XP for IDs past Classic's (10000+) comes
	-- only from Forever players' traces, so no XP there means no one has done it here yet. With no
	-- objectives either it's most likely a Season of Discovery leftover (e.g. 81570, a twin of "Jarl
	-- Needs a Blade" with no prerequisite and no objectives) that would be planned as pick up -> hand
	-- in. Untraced quests WITH objectives stay: many are real race/class versions few people have done.
	-- Kept too: ones in your log, with a hand-filled entry, or confirmed live (ns.LiveQuests).
	if not logEntry and quest.xpEstimated and questId >= (cfg.classicQuestIdMax or 10000) and not fix
		and #(qo.ObjectiveData or {}) == 0 and not (ns.LiveQuests and ns.LiveQuests[questId]) then
		return nil, "not seen on Forever"
	end

	-- pick up
	if not logEntry then
		local starts = qo.startedBy or {}
		local pts = npcPoints(starts[1], true)
		objectPoints(starts[2], pts)
		local fixStart = #pts == 0 and fix and fix.start
		if fixStart and fixStart.spawns then pointsFromSpawns(fixStart.spawns, pts) end
		-- Started by an item that's another quest's REWARD (Forlorn Necklace from Not on Squealing Terms):
		-- the item comes when you hand that quest in, so this one starts right there, after it. Already
		-- handed in: the item is in your bags, start it where you are. From fix.start.afterQuest, or
		-- Questie's item data (questRewards).
		local afterLabel
		if #pts == 0 then
			local after = fixStart and fixStart.afterQuest
			if not after then
				for _, item in ipairs(starts[3] or {}) do
					local rq = QS.Item(item, "questRewards")
					if type(rq) == "table" and rq[1] then after = rq[1] break end
				end
			end
			if after then
				local done = Questie and Questie.db and Questie.db.char and Questie.db.char.complete or {}
				local afterName = QS.Quest(after, "name") or ("quest " .. after)
				if done[after] then
					local here = ns.Geo.PlayerPoint()
					if here then pts[1] = here end
					afterLabel = string.format("Start %s (the item from %s, in your bags)", quest.name, afterName)
				else
					local fin = QS.Quest(after, "finishedBy") or {}
					npcPoints(fin[1], true, pts)
					objectPoints(fin[2], pts)
					quest.requires = quest.requires or {}
					quest.requires[#quest.requires + 1] = after
					afterLabel = string.format("Start %s (with the reward from %s)", quest.name, afterName)
				end
			end
		end
		if #pts == 0 then
			return nil, (starts[3] and #starts[3] > 0) and "started by an item" or "no pickup location"
		end
		if #pts > 5 then pts = clusterAreas(pts) end
		local pickup = {
			kind = "pickup", questId = questId, questName = quest.name, points = pts, npcIds = starts[1],
			work = cfg.npcTalkSeconds or 10, mobXp = 0, label = "Pick up " .. quest.name,
		}
		if fixStart and fixStart.drop then
			-- the quest starts from an item these mobs drop: a few kills, then right-click the item
			local E = ns.Estimate
			local ids = fixStart.ids or {}
			local lvl = E.NpcLevel(ids[1] or 0) or level or ns.playerLevel()
			local kills = fixStart.kills or 4
			pickup.work = kills * E.KillSeconds(lvl, QS.Npc(ids[1] or 0, "rank"), fixStart.name) + pickup.work
			pickup.mobXp = kills * E.MobXP(lvl, QS.Npc(ids[1] or 0, "rank"))
			pickup.mobLevel, pickup.mobRank = lvl, QS.Npc(ids[1] or 0, "rank")
			pickup.mobs = {}
			for _, id in ipairs(ids) do pickup.mobs[id] = true end
			pickup.label = string.format("Loot the starter for %s from %s", quest.name, fixStart.name or "mobs")
		end
		if afterLabel then pickup.label, pickup.npcIds = afterLabel, nil end
		quest.stops[#quest.stops + 1] = pickup
	end

	-- objectives
	local complete = logEntry and logEntry.isComplete == 1
	local bagHold = qo.sourceItemId and 1 or 0   -- bag slots this quest's items use until turn-in
	local logObj = logEntry and logEntry.objectives or {}
	for _, od in ipairs(qo.ObjectiveData or {}) do
		if od.Type == "item" and od.Id ~= qo.sourceItemId then bagHold = bagHold + 1 end
	end
	quest.bagHold = bagHold
	if not complete and not (opts and opts.dungeon) then
		-- The game says an objective isn't done, but Questie's data doesn't list it (common on Forever's
		-- own quests): there's no telling where to go, and planning only the turn-in would send you to
		-- hand in an unfinished quest. Leave it out until Questie knows it, or you've finished it.
		local data = qo.ObjectiveData or {}
		local fixObjs = fix and fix.objectives
		-- (replace = true: the entry's steps stand in for Questie's, e.g. one item that takes 4 steps)
		if fixObjs and #fixObjs > 0 and (#data == 0 or fix.replace) then
			-- Questie lists none, but Data/QuestFixes.lua has them. When the game's quest log lists the
			-- same number of objectives they're matched one to one (a finished one is skipped);
			-- otherwise every one is planned until the game says the quest is done.
			local matched = #logObj == #fixObjs
			for i, fo in ipairs(fixObjs) do
				local lo = matched and logObj[i] or nil
				if not (lo and lo.finished) then
					local remaining
					if lo and lo.numRequired then
						remaining = math.max(1, (lo.numRequired or 1) - (lo.numFulfilled or 0))
					end
					local stop, why = fixStop(quest, fo, i, remaining)
					if not stop then return nil, why end
					if lo then stop.objIndex = i end
					quest.stops[#quest.stops + 1] = stop
				end
			end
			data = {} -- (nothing more from Questie)
			logObj = {}
		end
		-- Not picked up yet, one of Forever's own quests, and Questie lists no objectives: its data for
		-- these is often missing them, so "pick up, then hand straight in" can't be trusted. Once it's in
		-- your log the game says what's left (the check below), and it's planned from there.
		-- (A Data/QuestFixes.lua entry means someone checked the quest: no objectives there means none.)
		if not logEntry and #data == 0 and questId >= (cfg.customQuestIdFrom or 90000) and not fix then
			return nil, "objectives unknown"
		end
		for i, lo in ipairs(logObj) do
			if not lo.finished and not data[i] then return nil, "objective not in Questie's data" end
		end
		for i, od in ipairs(data) do
			local lo = logObj[i]
			if not (lo and lo.finished) then
				local remaining
				if lo and lo.numRequired then
					remaining = math.max(1, (lo.numRequired or 1) - (lo.numFulfilled or 0))
				end
				local stop, why = objectiveStop(quest, od, remaining)
				if stop == "skip" then
					-- nothing to do for this objective
				elseif not stop then
					return nil, why
				else
					stop.objIndex = i
					-- a new stack of quest items needs a free bag slot
					if od.Type == "item" and not (lo and (lo.numFulfilled or 0) > 0) then stop.bagDelta = 1 end
					quest.stops[#quest.stops + 1] = stop
				end
			end
		end
	end

	-- turn in
	local fin = qo.finishedBy or {}
	local tpts = npcPoints(fin[1], true)
	objectPoints(fin[2], tpts)
	local fixFinish = #tpts == 0 and fix and fix.finish
	if fixFinish then pointsFromSpawns(fixFinish.spawns, tpts) end
	if #tpts == 0 then return nil, "no turn-in location" end
	if #tpts > 5 then tpts = clusterAreas(tpts) end
	quest.stops[#quest.stops + 1] = {
		kind = "turnin", questId = questId, questName = quest.name, points = tpts, npcIds = fin[1],
		work = cfg.npcTalkSeconds or 10, mobXp = 0, xp = quest.questXp,
		npcName = (fin[1] and fin[1][1] and QS.Npc(fin[1][1], "name")) or (fixFinish and fixFinish.name) or nil,
		label = "Turn in " .. quest.name,
	}

	-- identity, order and what each stop does to the quest log and bags
	local mobXp, work = 0, 0
	for order, s in ipairs(quest.stops) do
		s.quest, s.order = quest, order
		if s.kind == "pickup" then
			s.key = "p:" .. questId
			s.logDelta = 1
			s.bagDelta = qo.sourceItemId and 1 or 0
		elseif s.kind == "turnin" then
			s.key = "t:" .. questId
			s.logDelta = -1
			s.bagDelta = -bagHold
		else
			s.key = "o:" .. questId .. ":" .. tostring(s.objIndex)
			s.logDelta = 0
			s.bagDelta = s.bagDelta or 0
		end
		mobXp = mobXp + (s.mobXp or 0)
		work = work + (s.work or 0)
	end
	quest.mobXp = mobXp
	quest.workSeconds = work
	quest.xp = quest.questXp * (cfg.questXpWeight or 1) + mobXp * (cfg.mobXpWeight or 1)
	if quest.xp <= 0 then return nil, "no XP" end
	return quest
end
