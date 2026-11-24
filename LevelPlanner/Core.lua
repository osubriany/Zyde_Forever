-- Core: shared namespace, printing, the frame-spread job runner, events and slash commands.
local ADDON, zyde = ...
-- Part of Zyde_Forever since 2026-11-14: LevelPlanner keeps its own private table (zyde.LP) so its
-- names never clash with Zyde's.
zyde.LP = zyde.LP or {}
local ns = zyde.LP

ns.cfg = LevelPlannerConfig or {}
ns.debug = false
ns.skipped = {}        -- [questId] = true: left out by /lp next until /lp reset or reload
ns.plan = nil          -- latest plan from Planner
ns.candidates = nil    -- latest candidate list from QuestSource

local PREFIX = "|cff33ff99LevelPlanner|r: "

function ns.print(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
	DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. table.concat(parts, " "))
end

function ns.dprint(...)
	if ns.debug then ns.print("|cff999999[debug]|r", ...) end
end

function ns.isSecret(v)
	return type(issecretvalue) == "function" and issecretvalue(v) or false
end

-- Calls fn safely. Returns its results, or nil if it errored (the error is shown in debug mode).
function ns.safe(fn, ...)
	if type(fn) ~= "function" then return nil end
	local res = { pcall(fn, ...) }
	if not res[1] then
		ns.dprint("error:", res[2])
		return nil
	end
	return select(2, unpack(res))
end

function ns.fmt(n)
	n = math.floor((n or 0) + 0.5)
	local s = tostring(n)
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then out = out:sub(2) end
	return out
end

-- Short numbers for the UI: 640, 4.2k, 14k.
function ns.short(n)
	n = math.floor((n or 0) + 0.5)
	if n < 1000 then return tostring(n) end
	if n < 10000 then return string.format("%.1fk", n / 1000) end
	return string.format("%dk", math.floor(n / 1000 + 0.5))
end

-- Short durations for the UI: <1m, ~5m, 1h 05m.
function ns.shortTime(sec)
	sec = sec or 0
	if sec < 60 then return "<1m" end
	local m = math.floor(sec / 60 + 0.5)
	if m < 60 then return "~" .. m .. "m" end
	return string.format("%dh %02dm", math.floor(m / 60), m % 60)
end

function ns.minutes(sec)
	sec = sec or 0
	if sec < 60 then return "<1 min" end
	return string.format("%d min", math.floor(sec / 60 + 0.5))
end

-- Grouped = marked with /lp group on, or (if allowed in Config) actually in a party.
function ns.IsGrouped()
	if ns.char and ns.char.grouped then return true end
	if ns.cfg.autoDetectGroup ~= false and IsInGroup and IsInGroup() then return true end
	return false
end

-- Elite quests and elite mobs are planned when grouped (or always, if Config says so). A hunter
-- solo (the pet tanks) also gets them when they're yellow or easier: `level` (the quest's or the
-- mob's) at most Config.hunterEliteLevelsAbove over yours. Bosses (rank 3) stay out solo.
-- Your choice overrides that (per character: /lp elites, or the step list's "..." menu):
--   "on"   - elite quests and mobs always planned, solo too
--   "off"  - never solo (still planned when grouped)
--   "auto" - the rule above (default)
local _, playerClass = UnitClass("player")
local ELITE_MODES = { auto = true, on = true, off = true }
function ns.EliteMode()
	local m = ns.char and ns.char.elites
	return ELITE_MODES[m] and m or "auto"
end

function ns.SetEliteMode(mode)
	if not ELITE_MODES[mode] then return end
	ns.char.elites = mode
	ns.print(({
		on = "elite quests: on - planned solo too.",
		off = "elite quests: off - planned only when grouped.",
		auto = "elite quests: auto - planned when grouped" .. (playerClass == "HUNTER" and ", or solo once they're yellow or easier (your pet tanks)." or "."),
	})[mode])
	ns.forceFresh = true
	if ns.RequestReplan then ns.RequestReplan(true) end
end

-- Pick-ups (per character: /lp pickup, or the step list's "..." menu):
--   "tight" - only quests that raise the route's XP per minute (default)
--   "loose" - also quick quests on the way that earn at least 40% of it (Config.looseMinShare)
local PICKUP_MODES = { tight = true, loose = true }
function ns.PickupMode()
	local m = ns.char and ns.char.pickup
	return PICKUP_MODES[m] and m or "tight"
end

function ns.SetPickupMode(mode)
	if not PICKUP_MODES[mode] then return end
	ns.char.pickup = mode
	ns.print(mode == "loose"
		and "pick-ups: loose - quick quests on the way are taken too, even when a bit slower than the route."
		or "pick-ups: tight - only quests that make the route faster.")
	ns.forceFresh = true
	ns.pickupReport = mode -- (the next plan says what loose pick-ups added)
	if ns.RequestReplan then ns.RequestReplan(true) end
end

-- Cleanup quests (the step list's "..." menu, /lp cleanup grey): abandons the grey quests in your log
-- that the plan doesn't use. Grey only gets greyer as you level, so one left out now stays out.
-- Kept: grey quests ready to turn in (free XP / a reward on the way) and class quests (the spell).
function ns.GreyCleanupList()
	local out = {}
	for _, c in ipairs(ns.plan and ns.plan.cleanup or {}) do
		if c.grey and c.id and not c.complete and not c.classQuest then out[#out + 1] = c end
	end
	return out
end

local function abandonQuest(questId)
	-- the quest log's own abandon, by its line in the log (indexes shift after each one: look it up)
	if GetNumQuestLogEntries and GetQuestLogTitle and SelectQuestLogEntry and SetAbandonQuest and AbandonQuest then
		for i = 1, (GetNumQuestLogEntries()) do
			local _, _, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
			if not isHeader and id == questId then
				SelectQuestLogEntry(i)
				SetAbandonQuest()
				AbandonQuest()
				return true
			end
		end
		return false
	end
	local QL = C_QuestLog
	if QL and QL.SetSelectedQuest and QL.SetAbandonQuest and QL.AbandonQuest then
		QL.SetSelectedQuest(questId)
		QL.SetAbandonQuest()
		QL.AbandonQuest()
		return true
	end
	return false
end

StaticPopupDialogs["LEVELPLANNER_CLEANUP_QUESTS"] = {
	text = "Abandon %d grey quest(s) the plan doesn't use?\n\n%s",
	button1 = ABANDON_QUEST_ABBREV or "Abandon",
	button2 = CANCEL or "Cancel",
	OnAccept = function(_, data)
		local done = {}
		for _, c in ipairs(data or {}) do
			if abandonQuest(c.id) then done[#done + 1] = c.name end
		end
		ns.print(#done > 0 and ("abandoned: " .. table.concat(done, ", ") .. ".") or "nothing was abandoned.")
		if ns.RequestReplan then ns.RequestReplan(true) end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function ns.ConfirmGreyCleanup()
	if not ns.plan then ns.print("no plan yet - try again in a moment.") return end
	local list = ns.GreyCleanupList()
	if #list == 0 then
		ns.print("no grey quests to clean up: every grey quest in your log is in the plan, ready to turn in, or a class quest.")
		return
	end
	local names = {}
	for _, c in ipairs(list) do names[#names + 1] = c.name end
	local popup = StaticPopup_Show("LEVELPLANNER_CLEANUP_QUESTS", #list, table.concat(names, "\n"))
	if popup then popup.data = list end
end

function ns.AllowElite(level, rank)
	local mode = ns.EliteMode()
	if mode == "on" or ns.IsGrouped() then return true end
	if mode == "off" then return false end
	if ns.cfg.includeEliteQuests then return true end
	if playerClass == "HUNTER" and ns.cfg.hunterSoloElites ~= false and rank ~= 3 and level then
		return level <= ns.playerLevel() + (ns.cfg.hunterEliteLevelsAbove or 2)
	end
	return false
end

function ns.playerLevel()
	local lvl = UnitLevel("player")
	if ns.isSecret(lvl) or type(lvl) ~= "number" or lvl < 1 then
		local QP = ns.Q and ns.Q.QuestiePlayer
		lvl = QP and ns.safe(QP.GetPlayerLevel) or 1
	end
	return lvl
end

----------------------------------------------------------------------------------------
-- Job runner: long work runs inside a coroutine and gives way when the frame budget is used.
----------------------------------------------------------------------------------------
local job, jobName, jobDone
local frameStart = 0
local frameBudget = 4 -- ms of work this frame (more while the frame rate is high, see the runner)
local runner = CreateFrame("Frame")

-- Call often inside long loops. Pauses the job until the next frame when the budget is used up.
function ns.Check()
	if coroutine.running() and debugprofilestop() - frameStart > frameBudget then
		coroutine.yield()
	end
end

local jobSeconds = 0 -- time the job has been working (paused time in fights or flights not counted)
local jobRetried = false
local jobCpu, jobStartedAt = 0, 0 -- (/lp debug: work time and wall time of the running job)

function ns.RunJob(name, fn, onDone)
	job = coroutine.create(fn)
	jobName, jobDone = name, onDone
	jobSeconds, jobCpu, jobStartedAt = 0, 0, GetTime()
	runner:Show()
end

-- Work time (ms) the running job has used so far, including this frame's.
function ns.JobCpu()
	-- (inside the job, this frame's part isn't added up yet)
	return jobCpu + (coroutine.running() and (debugprofilestop() - frameStart) or 0)
end
function ns.JobWall() return GetTime() - jobStartedAt end

function ns.JobRunning() return job ~= nil end

-- Why a job is paused right now (shown next to "Planning..."), or nil while it's working.
-- (the same checks the runner below makes before each step)
function ns.JobWaitReason()
	if not job then return nil end
	if UnitOnTaxi("player") then return "until you land" end
	if InCombatLockdown() then return "after combat" end
	local _, instanceType = IsInInstance()
	if instanceType == "party" or instanceType == "raid" then return "until you leave the dungeon" end
	return nil
end

-- A job that failed or ran too long: say so, clear "Planning...", and plan again once (a job never
-- just disappears and leaves the window waiting).
local function jobFailed(self, why, retryQuick)
	local name = jobName
	job, jobName, jobDone = nil, nil, nil
	self:Hide()
	ns.print(why)
	if ns.StepList then ns.StepList.SetPlanning(false) end
	if name == "plan" and ns.RequestReplan then
		if retryQuick then
			-- a full search that slow will be again: the quick one for the next 10 minutes
			ns.quickPlanUntil = GetTime() + 600
			ns.RequestReplan(false)
		elseif not jobRetried then
			jobRetried = true
			C_Timer.After(5, function() ns.RequestReplan(true) end)
		end
	end
end

runner:Hide()
runner:SetScript("OnUpdate", function(self, elapsed)
	if not job then self:Hide() return end
	if InCombatLockdown() or UnitOnTaxi("player") then return end -- no planning work during fights or flights
	local _, instanceType = IsInInstance()
	if instanceType == "party" or instanceType == "raid" then return end -- the plan waits until you leave the dungeon
	jobSeconds = jobSeconds + (elapsed or 0)
	local limit = ns.cfg.planTimeoutSeconds or 45
	if jobName == "plan" and jobSeconds > limit and not (ns.quickPlanUntil and GetTime() < ns.quickPlanUntil) then
		jobFailed(self, string.format("planning took over %d s - switching to the quicker search for a while", limit), true)
		return
	end
	-- a high frame rate has room to spare: use more of each frame (Config.frameBudgetFastMs) so a
	-- re-plan lands sooner; at a low one, the usual small slice (Config.frameBudgetMs)
	local base = ns.cfg.frameBudgetMs or 4
	frameBudget = (elapsed or 1) < 1 / 50 and math.max(base, ns.cfg.frameBudgetFastMs or 8) or base
	frameStart = debugprofilestop()
	local co = job
	local ok, result = coroutine.resume(co)
	jobCpu = jobCpu + (debugprofilestop() - frameStart)
	if not ok then
		local stack = debugstack and select(2, pcall(debugstack, co, 1, 4, 0))
		jobFailed(self, "planning error in " .. tostring(jobName) .. ": " .. tostring(result)
			.. (type(stack) == "string" and stack ~= "" and ("\n" .. stack) or "")
			.. (jobRetried and "" or "\n(trying again in 5 s)"))
		return
	end
	if coroutine.status(co) == "dead" then
		local done = jobDone
		job, jobName, jobDone = nil, nil, nil
		jobRetried = false
		self:Hide()
		if done then
			local okDone, err = pcall(done, result)
			if not okDone then ns.print("error: " .. tostring(err)) end
		end
	end
end)

----------------------------------------------------------------------------------------
-- Re-planning. A "rescan" looks for available quests again; a plain re-plan reuses them.
----------------------------------------------------------------------------------------
local pendingRescan, timerQueued = false, false

local function startWork()
	timerQueued = false
	if not ns.ready then return end
	if ns.JobRunning() then
		-- try again shortly; the running job finishes first
		timerQueued = true
		C_Timer.After(0.5, startWork)
		return
	end
	local rescan = pendingRescan or not ns.candidates
	local previous = (not ns.forceFresh) and ns.plan or nil
	local opts = { threshold = ns.offTrail and (ns.cfg.offTrailSwitchThreshold or 0.02) or nil,
		quick = ns.quickPlanUntil and GetTime() < ns.quickPlanUntil,
		-- (the extra searches - tight also trying loose's route - only when quests were re-read or the
		-- plan starts fresh, not on every kill; Planner search)
		thorough = rescan or ns.forceFresh or not previous }
	local why = (ns.forceFresh and "fresh" or (ns.offTrail and "off the trail, 2% bar" or "10% bar")) .. (rescan and ", quests re-read" or "")
	pendingRescan, ns.forceFresh, ns.offTrail = false, false, false
	if ns.StepList then ns.StepList.SetPlanning(true) end
	local scanMs
	ns.RunJob("plan", function()
		ns.Travel.Prepare()
		local t0 = ns.JobCpu()
		if rescan then
			ns.candidates = ns.QuestSource.ScanCandidates()
		else
			ns.QuestSource.RebuildLog(ns.candidates)
		end
		scanMs = ns.JobCpu() - t0
		return ns.Planner.Plan(ns.candidates, previous, opts)
	end, function(plan)
		if ns.StepList then ns.StepList.SetPlanning(false) end
		local before = ns.plan
		-- (/lp debug) why the route did or didn't change: which first step won, and by how much
		if ns.debug and plan then
			local s = plan.stops and plan.stops[1]
			ns.dprint(string.format("re-planned (%s): %s; first step: %s; %d XP/min",
				why, plan.note or "new route", s and s.label or "-", math.floor((plan.rate or 0) + 0.5)))
			ns.dprint(string.format("  took %.1f s: %d ms reading quests (%s), %d ms planning",
				ns.JobWall(), math.floor(scanMs or 0), rescan and "full scan" or "your log only",
				math.floor(ns.JobCpu() - (scanMs or 0))))
		end
		ns.plan = plan
		-- just switched pick-ups: what the loose rule added (or that tight takes only faster quests)
		if ns.pickupReport and plan then
			local taken = plan.looseTaken or {}
			if ns.pickupReport == "loose" then
				ns.print(#taken > 0
					and string.format("loose pick-ups added %d quest%s on the way: %s.", #taken, #taken == 1 and "" or "s",
						table.concat(taken, ", "))
					or "loose pick-ups: no extra quests on the way right now (none quick and close enough - /lp why <quest> shows the loose rule).")
			end
			ns.pickupReport = nil
		end
		ns.OnPlanReady(plan)
		ns.AnnounceChanges(before, plan)
	end)
end

-- delay: seconds to wait for more events first (default Config.replanDelay; quest progress waits less)
function ns.RequestReplan(rescan, delay)
	if rescan then pendingRescan = true end
	if timerQueued then return end
	timerQueued = true
	C_Timer.After(delay or ns.cfg.replanDelay or 1, startWork)
end

-- A step you just finished, out of the shown list right away (the new plan takes a moment):
-- accepted -> its pick-up, turned in or abandoned -> all its steps, an objective done -> that step.
function ns.DropFinished(questId, index, reason, R)
	local plan = ns.plan
	if not (plan and plan.stops and R) then return end
	local objDone = false
	if reason == R.QUEST_UPDATED and index then
		local entry = ns.Q.QuestLogCache and ns.safe(ns.Q.QuestLogCache.TryGetQuest, questId)
		local o = entry and entry.objectives and entry.objectives[index]
		objDone = o and o.finished and true or false
		if not objDone then return end
	end
	local dropped = false
	local function keep(list)
		local kept = {}
		for _, s in ipairs(list or {}) do
			local id = s.questId or (s.quest and s.quest.id)
			local drop = id == questId and (
				(reason == R.QUEST_ACCEPTED and s.kind == "pickup")
				or reason == R.QUEST_TURNED_IN or reason == R.QUEST_ABANDONED
				or (objDone and s.kind == "objective" and s.objIndex == index))
			if drop then dropped = true else kept[#kept + 1] = s end
		end
		return kept
	end
	local stops, onWay = keep(plan.stops), keep(plan.onWay) -- (and the "On the way" steps)
	if not dropped then return end
	plan.stops, plan.onWay = stops, onWay
	ns.OnPlanReady(plan)
end

----------------------------------------------------------------------------------------
-- Off the trail: you walked somewhere the plan didn't send you (or just kept moving).
----------------------------------------------------------------------------------------
local origin          -- where you were when the current plan was made
local originTargetDist -- how far the first step was from there
local planMadeAt = 0

local function rememberOrigin(plan)
	origin = ns.Geo.PlayerPoint()
	local first = plan and plan.stops and plan.stops[1]
	originTargetDist = origin and first and first.point and ns.Geo.Distance(origin, first.point)
	planMadeAt = GetTime()
end

local function busy()
	if not ns.ready or ns.JobRunning() or timerQueued then return true end
	if InCombatLockdown() or UnitOnTaxi("player") or UnitIsDeadOrGhost("player") then return true end
	local _, t = IsInInstance()
	return t == "party" or t == "raid"
end

local function checkTrail()
	if busy() or not origin or not ns.plan then return end
	local here = ns.Geo.PlayerPoint()
	local moved = here and ns.Geo.Distance(here, origin)
	if not moved then return end -- another continent: teleports are handled elsewhere
	local first = ns.plan.stops[1]
	local target = first and first.point
	local dNow = target and ns.Geo.Distance(here, target)
	local cfg = ns.cfg
	if moved >= (cfg.offTrailYards or 100) and dNow and originTargetDist then
		local inArea = dNow <= (cfg.clusterRadius or 120) * 1.5   -- moving around while killing there
		local headingThere = (originTargetDist - dNow) >= moved * 0.5
		if not inArea and not headingThere then
			ns.dprint(string.format("off the planned path (moved %d yd, not toward the next step) - re-planning", math.floor(moved)))
			ns.offTrail = true
			ns.RequestReplan(false)
			return
		end
	end
	-- walked up to a later turn-in / pick-up / extra stop (it wasn't this close when the plan was made):
	-- re-plan now so it moves to the front (Planner standingAt) instead of waiting for the refresh
	local atYards = cfg.hereTurninAtYards or 40
	for i, e in ipairs(ns.plan.route or {}) do
		if i > 1 and e.point and (e.stop.kind == "turnin" or e.stop.kind == "pickup" or e.stop.quest.isExtra) then
			local d = ns.Geo.Distance(here, e.point)
			local d0 = ns.Geo.Distance(origin, e.point)
			if d and d <= atYards and not (d0 and d0 <= atYards) then
				ns.dprint(string.format("now %d yd from step %d (%s) - re-planning", math.floor(d), i, e.stop.questName or e.stop.quest.name or "?"))
				ns.RequestReplan(false)
				return
			end
		end
	end
	if moved >= 50 and GetTime() - planMadeAt >= (cfg.refreshSeconds or 90) then
		ns.RequestReplan(false) -- re-time the route from where you are now
	end
end

local trailTicks = 0
C_Timer.NewTicker(1, function()
	trailTicks = trailTicks + 1
	if trailTicks >= (ns.cfg.offTrailCheckSeconds or 5) then
		trailTicks = 0
		checkTrail()
	end
end)

-- A short notice when the route changes, and a quiet sound when a step was finished.
function ns.AnnounceChanges(before, plan)
	if not plan then return end
	if plan.switched and ns.StepList then
		ns.StepList.Notify(string.format("New route: %+d%% XP/min", math.floor((plan.switchGain or 0) + 0.5)))
	end
	-- sound only when the game confirms the previous first step is done
	local oldFirst = before and before.keys and before.keys[1] and before.keys[1].key
	if oldFirst and ns.cfg.stepSound ~= false and ns.StepDone(oldFirst) then
		ns.safe(PlaySound, SOUNDKIT and SOUNDKIT.MAP_PING or 3175, "SFX")
	end
end

-- Is a stop (by its key) finished according to the game? p:<quest> picked up, t:<quest> turned in,
-- o:<quest>:<objective> objective complete.
function ns.StepDone(key)
	local kind, id, idx = key:match("^(%a):(%d+):?(%d*)$")
	id = tonumber(id)
	if not id then return false end
	local complete = Questie and Questie.db and Questie.db.char and Questie.db.char.complete or {}
	local entry = ns.Q.QuestLogCache and ns.safe(ns.Q.QuestLogCache.TryGetQuest, id)
	if kind == "p" then return entry ~= nil end
	if kind == "t" then return complete[id] and true or false end
	if kind == "o" then
		local o = entry and entry.objectives and entry.objectives[tonumber(idx)]
		return (o and o.finished) or (entry and entry.isComplete == 1) or false
	end
	return false
end

-- The mobs your current step needs (the first planned step with mobs, within the next few):
-- [npcId] = true, or nil. Zyde's quest-mob glow paints these green (QuestMobs.lua).
function ns.CurrentStepMobs()
	local stops = ns.plan and ns.plan.stops
	if not stops then return nil end
	local mobs
	for i = 1, math.min(#stops, 3) do
		if stops[i].mobs and next(stops[i].mobs) then mobs = stops[i].mobs break end
	end
	-- and the mobs you kill on the way (the step list's "On the way" section)
	local onWay = ns.plan.onWay
	if onWay and #onWay > 0 then
		local all = {}
		for id in pairs(mobs or {}) do all[id] = true end
		for _, s in ipairs(onWay) do
			for id in pairs(s.mobs or {}) do all[id] = true end
		end
		if next(all) then return all end
	end
	return mobs
end

function ns.OnPlanReady(plan)
	if ns.Pin then ns.safe(ns.Pin.Apply, plan) end -- (an NPC you asked for with "..." goes first)
	if ns.Shopping then ns.safe(ns.Shopping.Refresh) end -- (the auction house list, if it's open)
	if zyde.QuestMobsRefresh then ns.safe(zyde.QuestMobsRefresh) end -- (green edge on this step's mobs)
	rememberOrigin(plan)
	if ns.MapPins then ns.safe(ns.MapPins.Update, plan) end
	if ns.NpcStars then ns.safe(ns.NpcStars.Update, plan) end
	if ns.ItemButton then ns.safe(ns.ItemButton.Refresh) end
	if ns.Waypoint then ns.Waypoint.Update(plan) end
	if ns.StepList then ns.StepList.Update(plan) end
	if ns.debug and plan then
		ns.dprint(string.format("plan: %d stops, %s XP in %s (%.0f XP/min), %d candidates",
			#plan.stops, ns.fmt(plan.xp), ns.minutes(plan.seconds), plan.rate, plan.candidateCount or 0))
		if plan.note then ns.dprint(plan.note) end
		for _, d in ipairs(plan.dungeonInfo or {}) do
			ns.dprint(string.format("dungeon %s: %d quests, %.0f XP/min on its own - %s", d.name, d.quests, d.rate,
				d.ok and "considered" or "skipped (questing is faster; /lp group on to include)"))
		end
	end
end

----------------------------------------------------------------------------------------
-- Start-up and events
----------------------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")

local function onQuestieReady()
	if not ns.QuestSource.Init() then return end
	ns.ready = true
	if Questie and Questie.API and Questie.API.RegisterForQuestUpdates then
		Questie.API.RegisterForQuestUpdates(function(questId, objectiveIndex, reason)
			ns.safe(ns.Learn.OnQuestUpdate, questId, objectiveIndex, reason) -- time your objective progress
			if ns.StepList then ns.safe(ns.StepList.Refresh) end -- live progress bar
			local R = Questie.API.Enums and Questie.API.Enums.QuestUpdateTriggerReason
			-- the step you just finished leaves the list at once; the re-plan refines it a moment later
			ns.safe(ns.DropFinished, questId, objectiveIndex, reason, R)
			-- progress only needs a re-plan; accept / turn-in / abandon change which quests are available
			ns.RequestReplan(not (R and reason == R.QUEST_UPDATED), ns.cfg.replanDelayQuest or 0.3)
		end)
	end
	events:RegisterEvent("PLAYER_LEVEL_UP")
	events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("GROUP_ROSTER_UPDATE")
	events:RegisterEvent("TRAINER_SHOW")
	events:RegisterEvent("MERCHANT_CLOSED")
	events:RegisterEvent("BAG_UPDATE_DELAYED")
	events:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
	events:RegisterEvent("PLAYER_XP_UPDATE")
	events:RegisterEvent("UPDATE_EXHAUSTION")
	events:RegisterEvent("CHAT_MSG_MONSTER_YELL") -- quests offered only now and then (the giver yells)
	ns.RequestReplan(true)
end

events:SetScript("OnEvent", function(self, event, arg1, arg2)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		LevelPlannerDB = LevelPlannerDB or {}
		LevelPlannerCharDB = LevelPlannerCharDB or {}
		ns.db, ns.char = LevelPlannerDB, LevelPlannerCharDB
		ns.debug = ns.char.debug and true or false
	elseif event == "PLAYER_LOGIN" then
		-- a Zyde feature: runs only when "Level planner" is on in /zyde (it also needs Questie).
		-- Off = no windows, no events, nothing done; turning it on or off takes a /reload.
		if not (zyde.F and zyde.F("levelPlanner")) then return end
		if not (Questie and Questie.API and Questie.API.RegisterOnReady) then return end
		ns.active = true
		ns.Geo.Init()
		ns.TravelLearn.Init()
		ns.Learn.Init()
		ns.Auto.Init()
		ns.Why.Init()
		ns.ItemButton.Init()
		ns.NpcStars.Init()
		ns.ZoneLevels.Init()
		if ns.db then ns.db.trails = nil end -- walked trails were removed 2026-11-18: drop the old saved data
		if ns.StepList then ns.StepList.Init() end
		if ns.Arrow then ns.Arrow.Init() end
		if ns.Shopping then ns.Shopping.Init() end
		Questie.API.RegisterOnReady(onQuestieReady)
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- after a loading screen you are usually somewhere new (hearth, portal, boat, dungeon exit)
		ns.forceFresh = true
		ns.RequestReplan(true)
	elseif event == "PLAYER_LEVEL_UP" or event == "ZONE_CHANGED_NEW_AREA" then
		ns.RequestReplan(true)
	elseif event == "TRAINER_SHOW" then
		-- a class trainer (not a profession trainer): you're trained up for this level
		if not (IsTradeskillTrainer and IsTradeskillTrainer()) then
			ns.char.trainedLevel = ns.playerLevel()
			ns.RequestReplan(false)
		end
	elseif event == "MERCHANT_CLOSED" then
		ns.lastVendorNeed = ns.Extras.VendorNeed()
		ns.RequestReplan(false)
	elseif event == "BAG_UPDATE_DELAYED" or event == "UPDATE_INVENTORY_DURABILITY" then
		-- only when a vendor visit becomes needed (or stops being needed)
		local need = ns.Extras.VendorNeed() and true or false
		if need ~= (ns.lastVendorNeed and true or false) then
			ns.lastVendorNeed = need
			ns.RequestReplan(false)
		end
		-- you looted an item a quest needed (Stops.lua: stop.srcItem): its "get it" step is done
		local count = (C_Item and C_Item.GetItemCount) or GetItemCount
		for _, s in ipairs(ns.plan and ns.plan.stops or {}) do
			if s.srcItem and count and (count(s.srcItem) or 0) > 0 then
				ns.RequestReplan(true)
				break
			end
		end
	elseif event == "PLAYER_XP_UPDATE" or event == "UPDATE_EXHAUSTION" then
		if ns.StepList and ns.plan then ns.StepList.Update(ns.plan) end -- refresh the level-up ETA
		-- the plan counted rested XP: plan again once it runs out (kill-heavy picks lose their edge),
		-- or when it grew a lot (rested at an inn)
		local plan = ns.plan
		if plan and plan.restedPool and ns.cfg.plannerRested ~= false then
			local pool = ns.Estimate.RestedPool()
			local max = UnitXPMax("player")
			local big = (not ns.isSecret(max) and type(max) == "number" and max > 0) and max * (ns.cfg.restedReplanShare or 0.2) or 2000
			if (plan.restedPool > 0 and pool <= 0) or pool - plan.restedPool > big then
				plan.restedPool = pool -- (once per change)
				ns.dprint("rested XP " .. (pool <= 0 and "used up" or "grew") .. " - re-planning")
				ns.RequestReplan(false)
			end
		end
	elseif event == "CHAT_MSG_MONSTER_YELL" then
		-- a now-and-then quest giver (Cork Gizelton's caravan) announcing a stop: plan with it
		local text, sender = arg1, arg2
		if not ns.isSecret(text) and not ns.isSecret(sender) and ns.Stops.TimedYell(text, sender) then
			ns.dprint(tostring(sender) .. " yelled - re-planning with that quest")
			ns.RequestReplan(true)
		end
	elseif event == "GROUP_ROSTER_UPDATE" then
		-- only when "grouped" actually flips (the event also fires for roster changes inside a group)
		local g = ns.IsGrouped()
		if g ~= ns.lastGrouped then
			ns.lastGrouped = g
			ns.forceFresh = true
			ns.RequestReplan(true)
		end
	end
end)

----------------------------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------------------------
SLASH_LEVELPLANNER1 = "/lp"
SLASH_LEVELPLANNER2 = "/levelplanner"
SlashCmdList.LEVELPLANNER = function(msg)
	if not ns.active then
		local why = zyde.featureBlocked and zyde.featureBlocked("levelPlanner")
		if why then
			ns.print("the level planner " .. why .. ".")
		else
			ns.print("the level planner is off. Turn on \"Level planner\" in /zyde, then /reload.")
		end
		return
	end
	local raw = (msg or ""):match("^%s*(.-)%s*$")   -- original spelling, for quest names
	msg = raw:lower()
	if msg:match("^why") then
		if not ns.ready then
			ns.print("still starting up - Questie hasn't finished loading. Try again in a few seconds.")
			return
		end
		ns.Why.Explain(raw:gsub("^[Ww][Hh][Yy]%s*", ""))
		return
	end
	if msg == "" then
		ns.StepList.Toggle()
		if not ns.ready then ns.print("waiting for Questie to finish loading.") end
	elseif msg == "next" then
		local stop
		for _, s in ipairs(ns.plan and ns.plan.stops or {}) do
			if s.questId then stop = s break end
		end
		if not stop then ns.print("there is no quest step to skip.") return end
		-- a step that belongs to a dungeon run skips the whole run
		local q = stop.quest
		local id = q and q.isDungeon and q.id or stop.questId
		local name = q and q.isDungeon and q.name or stop.questName
		ns.skipped[id] = true
		ns.print("skipping \"" .. (name or "?") .. "\" until /lp reset. Re-planning...")
		ns.RequestReplan(true)
	elseif msg == "reset" then
		wipe(ns.skipped)
		ns.print("skipped quests cleared. Re-planning...")
		ns.RequestReplan(true)
	elseif msg == "replan" then
		ns.forceFresh = true -- a fresh plan, ignoring the switch threshold
		ns.RequestReplan(true)
		ns.print("re-planning from scratch...")
	elseif msg == "group on" or msg == "group off" or msg == "group" then
		if msg == "group" then
			ns.print("grouped: " .. (ns.IsGrouped() and "yes" or "no") .. ". Use /lp group on or /lp group off.")
			return
		end
		ns.char.grouped = (msg == "group on")
		ns.lastGrouped = ns.IsGrouped()
		ns.print(ns.char.grouped and "marked as grouped: elite quests and red quests (up to "
			.. (ns.cfg.groupMaxLevelsAbove or 6) .. " levels above you) are now planned."
			or ("group mark removed" .. (ns.IsGrouped() and " (you are still in a party, which counts as grouped)." or ".")))
		ns.forceFresh = true
		ns.RequestReplan(true)
	elseif msg == "pickup" or msg == "pickup loose" or msg == "pickup tight" then
		local mode = msg:match("^pickup (%a+)$")
		if not mode then
			ns.print("pick-ups: " .. ns.PickupMode() .. ". Use /lp pickup loose or tight.")
			return
		end
		ns.SetPickupMode(mode)
	elseif msg == "elites" or msg == "elites on" or msg == "elites off" or msg == "elites auto" then
		local mode = msg:match("^elites (%a+)$")
		if not mode then
			ns.print("elite quests: " .. ns.EliteMode() .. ". Use /lp elites on, off or auto.")
			return
		end
		ns.SetEliteMode(mode)
	elseif msg == "steps" then
		-- the whole plan in chat: when each step starts, its XP, and what the planner valued its quest at
		local plan = ns.plan
		if not plan then ns.print("no plan yet.") return end
		ns.print(string.format("plan: %d steps, %s XP in %s", #plan.stops, ns.fmt(plan.xp or 0), ns.minutes(plan.seconds or 0)))
		local seen = {}
		for i, s in ipairs(plan.stops) do
			local q = s.quest
			local extra = ""
			if q and not seen[q] and q.id then
				seen[q] = true
				extra = string.format("  |cff999999[quest %s: %s XP%s%s]|r", tostring(q.id), ns.short(q.xp or 0),
					(q.chainValue or 0) > 0 and (", +" .. ns.short(q.chainValue) .. " follow-ups") or "",
					q.xpEstimated and ", estimated" or "")
			end
			ns.print(string.format("%d. %s %s%s%s", i, ns.minutes(s.arrive or 0), s.label or s.kind or "?",
				(s.xp or 0) > 0 and (" +" .. ns.short(s.xp)) or "",
				(s.mobXp or 0) > 0 and (" (kills +" .. ns.short(s.mobXp) .. ")") or "") .. extra)
		end
	elseif msg == "debug" then
		ns.debug = not ns.debug
		ns.char.debug = ns.debug
		ns.print("debug " .. (ns.debug and "on" or "off"))
		if ns.debug then
			ns.QuestSource.PrintScanStats()
			ns.Travel.PrintInfo()
		end
	elseif msg == "arrow" then
		ns.Arrow.Toggle()
	elseif msg == "auto on" or msg == "auto off" then
		local on = (msg == "auto on")
		ns.cfg.autoQuests = on
		if zyde.setFeature then zyde.setFeature("autoQuests", on) end
		ns.print("automatic accept / turn-in of planned quests " .. (on and "on" or "off")
			.. ". The Auto complete quests checkbox in /zyde keeps this.")
	elseif msg == "cleanup grey" then
		ns.ConfirmGreyCleanup()
	elseif msg == "cleanup" then
		local list = ns.plan and ns.plan.cleanup
		if not list or #list == 0 then
			ns.print("every quest in your log is part of the plan - nothing to abandon.")
		else
			ns.print("quests in your log the plan doesn't use (worst first):")
			for _, c in ipairs(list) do ns.print("  " .. c.name .. " - " .. c.reason) end
		end
	elseif msg == "learned" then
		ns.Learn.Print()
	elseif msg == "forget" then
		ns.Learn.Forget()
		ns.print("learned kill, objective and dungeon times cleared for this character (flight times and zone crossings are kept).")
		ns.RequestReplan(true)
	else
		ns.print("commands:")
		ns.print("/lp - show or hide the step list")
		ns.print("/lp next - skip the current step's quest")
		ns.print("/lp reset - stop skipping quests")
		ns.print("/lp replan - plan again from scratch now")
		ns.print("/lp group on|off - plan elite and red quests for a group")
		ns.print("/lp steps - print the whole plan in chat (times and XP of every step)")
		ns.print("/lp elites on|off|auto - elite quests solo: always, never, or by the usual rule")
		ns.print("/lp pickup tight|loose - only quests that speed the route up, or quick ones on the way too")
		ns.print("/lp arrow - show or hide the built-in arrow")
		ns.print("/lp cleanup - quests in your log the plan doesn't use")
		ns.print("/lp cleanup grey - abandon the grey ones (asks first)")
		ns.print("/lp auto on|off - automatic accept / turn-in of planned quests")
		ns.print("/lp why <quest name or ID> - why a quest is or isn't in the plan")
		ns.print("/lp learned - what LevelPlanner has learned about your pace")
		ns.print("/lp forget - clear the learned pace for this character")
		ns.print("/lp debug - show planning details in chat")
	end
end
