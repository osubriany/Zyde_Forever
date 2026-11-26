-- Estimate: XP values and time costs. Formulas are the standard Classic ones, written here from scratch.
local ADDON, zyde = ...
-- Part of Zyde_Forever since 2026-11-14: LevelPlanner keeps its own private table (zyde.LP) so its
-- names never clash with Zyde's.
zyde.LP = zyde.LP or {}
local ns = zyde.LP

local E = {}
ns.Estimate = E

local floor = math.floor

-- Level at or below which a mob is grey (gives no XP).
local function greyLevel(L)
	if L <= 5 then return 0 end
	if L <= 39 then return L - floor(L / 10) - 5 end
	if L <= 59 then return L - floor(L / 5) - 1 end
	return L - 9
end

E.GreyLevel = greyLevel -- (also roughly where a quest goes grey: Planner's early pick-ups)

-- "Zero difference" value used to scale XP for mobs below your level.
local function zeroDiff(L)
	if L < 8 then return 5 end
	if L < 10 then return 6 end
	if L < 12 then return 7 end
	if L < 16 then return 8 end
	if L < 20 then return 9 end
	if L < 30 then return 11 end
	if L < 40 then return 12 end
	if L < 45 then return 13 end
	if L < 50 then return 14 end
	if L < 55 then return 15 end
	return 16
end

local function isElite(rank) return rank == 1 or rank == 2 or rank == 3 end

-- XP for one kill (no rested bonus). raw = skip the open-world group share (dungeons use their own).
-- atLevel: price the kill for that player level instead of yours (the planner, after a predicted level-up).
function E.MobXP(mobLevel, rank, raw, atLevel)
	local L = atLevel or ns.playerLevel()
	if L >= (GetMaxPlayerLevel and GetMaxPlayerLevel() or 60) then return 0 end
	mobLevel = mobLevel or L
	if mobLevel <= greyLevel(L) then return 0 end
	local base = L * 5 + 45
	local xp
	if mobLevel >= L then
		xp = base * (1 + 0.05 * math.min(mobLevel - L, 4))
	else
		xp = base * (1 - (L - mobLevel) / zeroDiff(L))
	end
	if isElite(rank) then xp = xp * 2 end
	if ns.IsGrouped() and not raw then xp = xp * (ns.cfg.groupMobXpShare or 0.6) end
	return math.max(0, xp)
end

-- Rested XP: kills give double until the rested pool is used up (quest XP is never rested). The
-- planner and the step list both count it with these two, so they show the same numbers.
-- The pool right now (0 when the game hides it or has none).
function E.RestedPool()
	local r = GetXPExhaustion and GetXPExhaustion()
	if r == nil or (ns.isSecret and ns.isSecret(r)) or type(r) ~= "number" then return 0 end
	return math.max(0, r)
end

-- Kills worth killXp while pool is left: the extra XP they give, and the pool left after them.
function E.RestedBonus(pool, killXp)
	pool, killXp = pool or 0, killXp or 0
	local b = killXp < pool and killXp or pool
	if b < 0 then b = 0 end
	return b, pool - b
end

-- Kill time from Config alone (what learning compares against).
function E.KillSecondsDefault(mobLevel, rank)
	local cfg = ns.cfg
	local L = ns.playerLevel()
	local t = cfg.killSeconds or 22
	if mobLevel and mobLevel > L then t = t + (mobLevel - L) * (cfg.killSecondsPerLevelAbove or 3) end
	-- lower-level mobs die faster and hit softer (less resting), down to a floor
	if mobLevel and mobLevel < L then
		t = t * math.max(cfg.killFloorShare or 0.35, 1 - (L - mobLevel) * (cfg.killShareLessPerLevelBelow or 0.07))
	end
	if isElite(rank) then
		t = t * (ns.IsGrouped() and (cfg.eliteKillFactorGrouped or 1.2) or (cfg.eliteKillFactorSolo or 3))
	end
	return t
end

-- Kill time with your learned pace: your own time for this mob if known, else the default
-- scaled by how fast you kill in general.
function E.KillSeconds(mobLevel, rank, mobName)
	local t = E.KillSecondsDefault(mobLevel, rank)
	if not ns.Learn then return t end
	t = t * ns.Learn.KillFactor()
	return ns.Learn.KillSecondsByName(mobName, t)
end

-- Seconds per unit of objective progress, learned when available.
-- ownOnly: only this objective's own pace - for item drops, whose pace depends on the drop rate (one
-- in 1 kill or one in 12), so your average over other items says nothing about this one.
function E.UnitSeconds(key, prior, ownOnly)
	if not (ns.Learn and key) then return prior end
	if ownOnly then return ns.Learn.UnitSeconds(key, prior) end
	-- the objective's own pace, falling back to your pace for that kind of objective
	local kind = key:match("^(%a+)")
	return ns.Learn.UnitSeconds(key, ns.Learn.UnitSeconds("type:" .. kind, prior))
end

-- Quest XP adjusted for level difference (same rule the game uses), for quests Questie has no XP for.
function E.EstimatedQuestXP(questLevel)
	local L = ns.playerLevel()
	if L >= (GetMaxPlayerLevel and GetMaxPlayerLevel() or 60) then return 0 end
	questLevel = math.max(1, questLevel or L)
	local xp = questLevel * (ns.cfg.unknownXpPerQuestLevel or 85)
	local mult = 2 * (questLevel - L) + 20
	if mult < 1 then mult = 1 elseif mult > 10 then mult = 10 end
	return xp * mult / 10
end

-- XP from one level to the next (Classic's table). Your current level's comes from the game
-- (UnitXPMax); this is for the levels after it, when a route plans several level-ups.
local XP_TO_NEXT = { 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900,
	14400, 16000, 17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300,
	47400, 50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700, 95800, 101000, 106300, 111800,
	117500, 123200, 129100, 135100, 141200, 147500, 153900, 160400, 167100, 173900, 180800, 187900, 195000,
	202300, 209800 }
function E.XpToNext(level)
	return XP_TO_NEXT[level]
end

function E.QuestXP(questId, questLevel)
	local xp = ns.QuestSource.QuestXP(questId)
	if xp then return xp, false end
	return E.EstimatedQuestXP(questLevel), true
end

function E.NpcLevel(npcId)
	local QS = ns.QuestSource
	local lo, hi = QS.Npc(npcId, "minLevel"), QS.Npc(npcId, "maxLevel")
	lo = lo or hi
	hi = hi or lo
	if not lo then return nil end
	return (lo + hi) / 2
end
