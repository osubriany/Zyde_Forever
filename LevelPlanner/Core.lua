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
local _, playerClass = UnitClass("player")
function ns.AllowElite(level, rank)
	if ns.cfg.includeEliteQuests or ns.IsGrouped() then return true end
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
local runner = CreateFrame("Frame")

-- Call often inside long loops. Pauses the job until the next frame when the budget is used up.
function ns.Check()
	if coroutine.running() and debugprofilestop() - frameStart > (ns.cfg.frameBudgetMs or 4) then
		coroutine.yield()
	end
end

function ns.RunJob(name, fn, onDone)
	job = coroutine.create(fn)
	jobName, jobDone = name, onDone
	runner:Show()
end

function ns.JobRunning() return job ~= nil end

runner:Hide()
runner:SetScript("OnUpdate", function(self)
	if not job then self:Hide() return end
	if InCombatLockdown() or UnitOnTaxi("player") then return end -- no planning work during fights or flights
	local _, instanceType = IsInInstance()
	if instanceType == "party" or instanceType == "raid" then return end -- the plan waits until you leave the dungeon
	frameStart = debugprofilestop()
	local ok, result = coroutine.resume(job)
	if not ok then
		ns.print("planning error in " .. tostring(jobName) .. ": " .. tostring(result))
		if ns.StepList then ns.StepList.SetPlanning(false) end
		job = nil
		self:Hide()
		return
	end
	if coroutine.status(job) == "dead" then
		local done = jobDone
		job, jobName, jobDone = nil, nil, nil
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
	local opts = { threshold = ns.offTrail and (ns.cfg.offTrailSwitchThreshold or 0.02) or nil }
	local why = (ns.forceFresh and "fresh" or (ns.offTrail and "off the trail, 2% bar" or "10% bar")) .. (rescan and ", quests re-read" or "")
	pendingRescan, ns.forceFresh, ns.offTrail = false, false, false
	if ns.StepList then ns.StepList.SetPlanning(true) end
	ns.RunJob("plan", function()
		ns.Travel.Prepare()
		if rescan then
			ns.candidates = ns.QuestSource.ScanCandidates()
		else
			ns.QuestSource.RebuildLog(ns.candidates)
		end
		return ns.Planner.Plan(ns.candidates, previous, opts)
	end, function(plan)
		if ns.StepList then ns.StepList.SetPlanning(false) end
		local before = ns.plan
		-- (/lp debug) why the route did or didn't change: which first step won, and by how much
		if ns.debug and plan then
			local s = plan.stops and plan.stops[1]
			ns.dprint(string.format("re-planned (%s): %s; first step: %s; %d XP/min",
				why, plan.note or "new route", s and s.label or "-", math.floor((plan.rate or 0) + 0.5)))
		end
		ns.plan = plan
		ns.OnPlanReady(plan)
		ns.AnnounceChanges(before, plan)
	end)
end

function ns.RequestReplan(rescan)
	if rescan then pendingRescan = true end
	if timerQueued then return end
	timerQueued = true
	C_Timer.After(ns.cfg.replanDelay or 1, startWork)
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

function ns.OnPlanReady(plan)
	if ns.Pin then ns.safe(ns.Pin.Apply, plan) end -- (an NPC you asked for with "..." goes first)
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
			-- progress only needs a re-plan; accept / turn-in / abandon change which quests are available
			ns.RequestReplan(not (R and reason == R.QUEST_UPDATED))
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
	ns.RequestReplan(true)
end

events:SetScript("OnEvent", function(self, event, arg1)
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
	elseif event == "PLAYER_XP_UPDATE" then
		if ns.StepList and ns.plan then ns.StepList.Update(ns.plan) end -- refresh the level-up ETA
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
		ns.cfg.autoQuests = (msg == "auto on")
		ns.print("automatic accept / turn-in of planned quests " .. (ns.cfg.autoQuests and "on" or "off")
			.. " for this session (set autoQuests in Config.lua to keep it).")
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
		ns.print("/lp arrow - show or hide the built-in arrow")
		ns.print("/lp cleanup - quests in your log the plan doesn't use")
		ns.print("/lp auto on|off - automatic accept / turn-in of planned quests")
		ns.print("/lp why <quest name or ID> - why a quest is or isn't in the plan")
		ns.print("/lp learned - what LevelPlanner has learned about your pace")
		ns.print("/lp forget - clear the learned pace for this character")
		ns.print("/lp debug - show planning details in chat")
	end
end
