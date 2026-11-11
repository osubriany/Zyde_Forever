-- API: the public face of GearAdvisor for other addons (LevelPlanner first).
-- Everything else in GearAdvisor is private. Results are copies; changing them changes nothing.
--
--   GearAdvisorAPI.version                    1
--   GearAdvisorAPI.Compare(link)              result table (see Score.compare), or nil
--   GearAdvisorAPI.ScoreItem(link)            pct, delta, kind   (pct = % change to your kit)
--   GearAdvisorAPI.GetProfile()               profileKey, label, level, source
--   GearAdvisorAPI.GetDungeonUpgrades(name)   list of { itemID, link, pct, kind, boss, dungeon }, loading
--   GearAdvisorAPI.GetDungeons()              list of { name, minLevel, maxLevel }
--   GearAdvisorAPI.RegisterCallback(fn)      fn(reason) after equipment, level, talents or settings change
local _, zyde = ...
zyde.GA = zyde.GA or {}
local ns = zyde.GA

local function copy(v, seen)
	if type(v) ~= "table" then return v end
	seen = seen or {}
	if seen[v] then return seen[v] end
	local t = {}
	seen[v] = t
	for k, x in pairs(v) do t[k] = copy(x, seen) end
	return t
end

GearAdvisorAPI = {
	version = 1,
	Compare = function(link)
		local ok, r = pcall(ns.Score.compare, link)
		if ok then return copy(r) end
	end,
	ScoreItem = function(link)
		local ok, r = pcall(ns.Score.compare, link)
		if ok and r then return r.pct, r.delta, r.kind end
	end,
	GetProfile = function()
		local ok, c = pcall(ns.Player.context)
		if not ok or not c then return nil end
		return c.profileKey, c.profile and c.profile.label, c.level, c.profileSource
	end,
	-- Upgrades a dungeon drops for you, best first: list of { itemID, link, pct, kind, boss, dungeon },
	-- plus how many items are still loading (ask again shortly). nil for an unknown dungeon.
	GetDungeonUpgrades = function(name)
		local ok, list, loading = pcall(ns.Loot.upgradesIn, name)
		if not ok or not list then return nil end
		local out = {}
		for _, e in ipairs(list) do
			out[#out + 1] = { itemID = e.result.info.itemID, link = e.result.info.link, pct = e.result.pct,
				kind = e.result.kind, boss = e.boss.name, dungeon = e.dungeon.name }
		end
		return out, loading
	end,
	-- Names of every dungeon with loot data.
	GetDungeons = function()
		local ok, list = pcall(ns.Loot.dungeons)
		if not ok then return {} end
		local out = {}
		for _, d in ipairs(list) do out[#out + 1] = { name = d.name, minLevel = d.minLevel, maxLevel = d.maxLevel } end
		return out
	end,
	RegisterCallback = function(fn)
		if type(fn) == "function" then ns.onChange(fn) end
	end,
}
