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
function E.MobXP(mobLevel, rank, raw)
	local L = ns.playerLevel()
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
function E.UnitSeconds(key, prior)
	if not (ns.Learn and key) then return prior end
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
