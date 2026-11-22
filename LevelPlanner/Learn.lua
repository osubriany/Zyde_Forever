-- Learn (phase 5): records how fast you actually play and feeds it back into the estimates.
--   * kill pace: time between XP-giving kills ("X dies, you gain N experience"), solo and outdoors
--   * objective pace: seconds per unit of quest progress, per mob / item / object
--   * dungeon runs: minutes from entering to leaving (a short trip outside doesn't end the run)
-- Everything is stored per character in LevelPlannerCharDB.learned.
local ADDON, zyde = ...
-- Part of Zyde_Forever since 2026-11-14: LevelPlanner keeps its own private table (zyde.LP) so its
-- names never clash with Zyde's.
zyde.LP = zyde.LP or {}
local ns = zyde.LP

local L = {}
ns.Learn = L

local lastKillAt          -- GetTime() of the previous XP kill
local progress = {}       -- ["questId:index"] = {count, t}
local killPattern

local function data()
	local c = ns.char
	c.learned = c.learned or {}
	local d = c.learned
	d.units = d.units or {}        -- ["monster:123"] = {n, mean} seconds per unit of objective progress
	d.killNames = d.killNames or {} -- [mob name] = {n, mean} seconds per kill
	d.killFactor = d.killFactor or nil -- {n, mean}: real kill time / default estimate
	d.dungeons = d.dungeons or {}  -- [areaId] = {n, mean} minutes per run
	return d
end

local function add(rec, x)
	rec = rec or { n = 0, mean = 0 }
	local cap = ns.cfg.learnMaxSamples or 30
	rec.n = rec.n + 1
	rec.mean = rec.mean + (x - rec.mean) / math.min(rec.n, cap)
	return rec
end

-- Blends a default with what was learned: the default counts as learnPriorWeight samples.
local function blend(rec, prior)
	if ns.cfg.useLearned == false or not rec or rec.n == 0 then return prior end
	local k = ns.cfg.learnPriorWeight or 5
	local w = rec.n / (rec.n + k)
	return prior * (1 - w) + rec.mean * w
end

-- Seconds per unit of an objective ("monster:123", "item:456", ...), or the prior.
function L.UnitSeconds(key, prior)
	return blend(data().units[key], prior)
end

-- Multiplier on the default kill time (1 until learned).
function L.KillFactor()
	return blend(data().killFactor, 1)
end

-- Seconds per kill for a mob name, or the prior.
function L.KillSecondsByName(name, prior)
	if not name then return prior end
	return blend(data().killNames[name], prior)
end

function L.DungeonMinutes(area, prior)
	return blend(data().dungeons[area], prior)
end

local function learningAllowed()
	-- group and dungeon pace says little about solo questing pace
	if IsInGroup and IsInGroup() then return false end
	local _, t = IsInInstance()
	return t ~= "party" and t ~= "raid"
end

----------------------------------------------------------------------------------------
-- Kill pace
----------------------------------------------------------------------------------------
local function buildKillPattern()
	local fmt = COMBATLOG_XPGAIN_FIRSTPERSON or "%s dies, you gain %d experience."
	-- turn the game's own sentence into a pattern: "%s" -> name, "%d" -> number
	local p = fmt:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
	p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
	-- other variants (rested bonus, group bonus) add text at the end; match only the start
	p = p:gsub("%%%.$", "")
	killPattern = "^" .. p
end

local function onXpMessage(msg)
	if not msg or ns.isSecret(msg) then return end
	if not killPattern then buildKillPattern() end
	local name = msg:match(killPattern)
	if not name then return end
	local now = GetTime()
	local gap = lastKillAt and now - lastKillAt
	lastKillAt = now
	if not gap or gap < 2 or gap > (ns.cfg.learnMaxGapSeconds or 240) then return end
	if not learningAllowed() or UnitOnTaxi("player") then return end

	local d = data()
	d.killNames[name] = add(d.killNames[name], gap)
	-- compare with the default for a mob of the target's level, when the target is that mob
	local lvl
	if UnitName("target") == name then
		lvl = UnitLevel("target")
		if ns.isSecret(lvl) or type(lvl) ~= "number" or lvl < 1 then lvl = nil end
	end
	local prior = ns.Estimate.KillSecondsDefault(lvl or ns.playerLevel(), nil)
	if prior > 0 then d.killFactor = add(d.killFactor, gap / prior) end
end

----------------------------------------------------------------------------------------
-- Objective pace
----------------------------------------------------------------------------------------
local function objectiveKey(questId, index)
	local qo = ns.QuestSource.GetQuest(questId)
	local od = qo and qo.ObjectiveData and qo.ObjectiveData[index]
	if not od then return nil end
	if od.Type == "killcredit" then return "killcredit:" .. tostring(od.RootId) end
	if od.Type == "item" and od.Id then
		-- items dropped by mobs and items picked up from the ground take very different times,
		-- so they're learned separately ("item" vs "itempick"); Stops.lua uses the same split
		local drops = ns.QuestSource.Item(od.Id, "npcDrops")
		if not (type(drops) == "table" and #drops > 0) then return "itempick:" .. tostring(od.Id) end
	end
	if od.Id then return od.Type .. ":" .. tostring(od.Id) end
	return nil
end

local function snapshot(questId)
	local entry = ns.Q.QuestLogCache and ns.safe(ns.Q.QuestLogCache.TryGetQuest, questId)
	if not entry then return end
	for i, o in ipairs(entry.objectives or {}) do
		progress[questId .. ":" .. i] = { count = o.numFulfilled or 0, t = nil }
	end
end

-- Called from Questie's quest-update callback.
-- An objective met at named NPCs (Stops.lua individualTargets): when its count goes up, the NPC you
-- have targeted is the one you just did - noted per character, so the plan sends you to the others.
local function noteTarget(questId, index)
	local guid = UnitGUID and UnitGUID("target")
	if not guid or ns.isSecret(guid) or type(guid) ~= "string" then return end
	local kind, _, _, _, _, npc = strsplit("-", guid)
	npc = tonumber(npc)
	if not npc or (kind ~= "Creature" and kind ~= "Vehicle") then return end
	local qo = ns.QuestSource.GetQuest(questId)
	local od = qo and qo.ObjectiveData and qo.ObjectiveData[index]
	if not od then return end
	for _, id in ipairs(od.IdList or { od.Id }) do
		if id == npc then
			ns.char.objDone = ns.char.objDone or {}
			ns.char.objDone[questId] = ns.char.objDone[questId] or {}
			ns.char.objDone[questId][npc] = true
			return
		end
	end
end

function L.OnQuestUpdate(questId, index, reason)
	local R = Questie and Questie.API and Questie.API.Enums and Questie.API.Enums.QuestUpdateTriggerReason
	if R and reason == R.QUEST_ACCEPTED then
		if ns.char.objDone then ns.char.objDone[questId] = nil end -- (taken again: nobody done yet)
		snapshot(questId)
		-- an escort usually starts walking the moment you accept it (Planner escortFirst)
		-- (kept per character: GetTime counts from computer start, so it survives a /reload)
		ns.char.acceptedAt = ns.char.acceptedAt or {}
		ns.char.acceptedAt[questId] = GetTime()
		return
	end
	if R and reason ~= R.QUEST_UPDATED then return end
	if not index then return end
	local entry = ns.Q.QuestLogCache and ns.safe(ns.Q.QuestLogCache.TryGetQuest, questId)
	local o = entry and entry.objectives and entry.objectives[index]
	if not o then return end
	local k = questId .. ":" .. index
	local prev = progress[k]
	local now = GetTime()
	local count = o.numFulfilled or 0
	progress[k] = { count = count, t = now }
	if not prev or count > (prev.count or 0) then noteTarget(questId, index) end
	-- the first tick after accepting includes the walk there, so only ticks after it are timed
	if not (prev and prev.t) or count <= (prev.count or 0) then return end
	local delta = count - prev.count
	local perUnit = (now - prev.t) / delta
	if perUnit < 1 or now - prev.t > (ns.cfg.learnMaxGapSeconds or 240) then return end
	if not learningAllowed() then return end
	local key = objectiveKey(questId, index)
	if not key then return end
	local d = data()
	d.units[key] = add(d.units[key], perUnit)
	local typeKey = "type:" .. key:match("^(%a+)")
	d.units[typeKey] = add(d.units[typeKey], perUnit)
end

----------------------------------------------------------------------------------------
-- Dungeon runs
----------------------------------------------------------------------------------------
local RESUME_SECONDS = 900   -- back inside within 15 minutes = same run

local function currentDungeonArea()
	local _, t = IsInInstance()
	if t ~= "party" then return nil end
	local instanceId = select(8, GetInstanceInfo())
	local map = ns.Q.ZoneDB and ns.Q.ZoneDB.instanceIdToAreaId
	local area = map and instanceId and map[instanceId]
	if area and ns.cfg.dungeonData and ns.cfg.dungeonData[area] then return area end
	return nil
end

local function finishRun(run)
	if not run or not run.lastExit then return end
	local minutes = (run.lastExit - run.start) / 60
	if minutes >= 10 and minutes <= 240 then
		local d = data()
		d.dungeons[run.area] = add(d.dungeons[run.area], minutes)
		ns.dprint(string.format("dungeon run recorded: %.0f min", minutes))
	end
end

local function onEnteringWorld()
	local c = ns.char
	local area = currentDungeonArea()
	local run = c.dungeonRun
	if area then
		if run and run.area == area and run.lastExit and time() - run.lastExit < RESUME_SECONDS then
			run.lastExit = nil -- back in: same run
		elseif not (run and run.area == area and not run.lastExit) then
			finishRun(run)
			c.dungeonRun = { area = area, start = time() }
		end
	elseif run and not run.lastExit then
		run.lastExit = time()
	end
end

----------------------------------------------------------------------------------------
-- Summary and reset
----------------------------------------------------------------------------------------
function L.Print()
	local d = data()
	local units, names, runs = 0, 0, 0
	for _ in pairs(d.units) do units = units + 1 end
	for _ in pairs(d.killNames) do names = names + 1 end
	for _ in pairs(d.dungeons) do runs = runs + 1 end
	local kf = d.killFactor
	ns.print(string.format("learned: kill pace from %d kills (%.0f%% of the default time), %d mob types",
		kf and kf.n or 0, L.KillFactor() * 100, names))
	for _, t in ipairs({ "monster", "item", "itempick", "object", "killcredit", "event" }) do
		local r = d.units["type:" .. t]
		if r then ns.print(string.format("  %s objectives: %.0f s per unit (%d samples)",
			t == "item" and "item drop" or t == "itempick" and "item pick-up" or t, r.mean, r.n)) end
	end
	ns.print(string.format("  %d objective kinds with their own pace, %d dungeons with real run times", units, runs))
	for area, r in pairs(d.dungeons) do
		local dd = ns.cfg.dungeonData and ns.cfg.dungeonData[area]
		ns.print(string.format("  %s: %.0f min per run (%d runs)", dd and dd[1] or tostring(area), r.mean, r.n))
	end
	-- walking detour per zone (Travel/Learn.lua): real walks against straight lines
	local det = ns.db and ns.db.detour
	if det and next(det) then
		local parts = {}
		for map, r in pairs(det) do
			local info = C_Map.GetMapInfo(map)
			parts[#parts + 1] = string.format("%s x%.2f (%d walks)", info and info.name or tostring(map),
				ns.TravelLearn.Detour(map), r.n)
		end
		table.sort(parts)
		ns.print("  walking detour: " .. table.concat(parts, ", ") .. string.format("  (default x%.2f)", ns.cfg.detourFactor or 1.3))
	end
	if ns.cfg.useLearned == false then ns.print("  (useLearned is off in Config.lua, so these are not used)") end
end

function L.Forget()
	ns.char.learned = nil
	ns.char.dungeonRun = nil
	data()
end

----------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------
-- An NPC you target that Questie has no spot for: where you are now (you're close to it), kept for
-- every character (LevelPlannerDB.npcSeen[npcId] = { {uiMap, x, y}, ... }, a few spots 20+ yd apart).
local function noteNpcSpot()
	local guid = UnitGUID and UnitGUID("target")
	if not guid or ns.isSecret(guid) or type(guid) ~= "string" then return end
	local kind, _, _, _, _, npc = strsplit("-", guid)
	npc = tonumber(npc)
	if not npc or kind ~= "Creature" then return end
	local spawns = ns.QuestSource.Npc(npc, "spawns")
	if type(spawns) == "table" and next(spawns) then return end
	local p = ns.Geo.PlayerPoint()
	if not (p and p.map and p.x) then return end
	ns.db.npcSeen = ns.db.npcSeen or {}
	local list = ns.db.npcSeen[npc] or {}
	for _, s in ipairs(list) do
		local q = ns.Geo.PointOnMap(s[1], s[2], s[3])
		local d = q and ns.Geo.Distance(p, q)
		if d and d < 20 then return end
	end
	if #list >= 12 then return end
	list[#list + 1] = { p.map, math.floor(p.x * 10 + 0.5) / 10, math.floor(p.y * 10 + 0.5) / 10 }
	ns.db.npcSeen[npc] = list
	-- the first spot of an NPC a quest of yours needs: plan it there
	if #list == 1 and ns.RequestReplan then ns.RequestReplan(true) end
end

function L.Init()
	data()
	local f = CreateFrame("Frame")
	f:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
	f:RegisterEvent("PLAYER_ENTERING_WORLD")
	f:RegisterEvent("PLAYER_TARGET_CHANGED")
	f:SetScript("OnEvent", function(_, event, a1)
		if event == "CHAT_MSG_COMBAT_XP_GAIN" then
			onXpMessage(a1)
		elseif event == "PLAYER_ENTERING_WORLD" then
			onEnteringWorld()
		elseif event == "PLAYER_TARGET_CHANGED" then
			if ns.ready then ns.safe(noteNpcSpot) end
		end
	end)
	-- a run you left more than 15 minutes ago is over
	C_Timer.NewTicker(60, function()
		local run = ns.char.dungeonRun
		if run and run.lastExit and time() - run.lastExit >= RESUME_SECONDS then
			finishRun(run)
			ns.char.dungeonRun = nil
		end
	end)
end
