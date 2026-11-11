-- Loot (phase e): which dungeon boss drops what. Three sources are merged:
--   0. The bundled table in Data\BossLoot.lua (ns.BossLoot, GPL-3.0-or-later like all of Zyde; see LICENSE):
--      cMaNGOS classic-db boss loot plus in-game sightings and Forever's own dungeon list, extracted
--      once from SimGear Forever's data files. Nothing here needs SimGear installed.
--   1. AtlasLoot, if you have a Forever version installed ("AtlasLoot Classic Forever" or
--      "AtlasLootClassic Continued" on CurseForge). Its tables are read in game at runtime; nothing of
--      AtlasLoot's is copied into GearAdvisor. Layout (AtlasLootClassic, also read this way by
--      SimGearForever): AtlasLoot.ItemDB.Storage[module][key] = { name, InstanceID, LevelRange,
--      items = { { name = boss, [difficulty] = { { index, itemID, ... }, ... } }, ... } }.
--   2. Our own drop recorder: gear that drops in a dungeon soon after a boss dies is noted against that
--      boss in GearAdvisorDB.drops (so the data grows as you play, and is Forever's own).
-- Public: Loot.dungeons(), Loot.sourcesOf(itemID), Loot.dungeon(name), Loot.status().
local _, zyde = ...
zyde.GA = zyde.GA or {}
local ns = zyde.GA

local Loot = {}
ns.Loot = Loot

local function clean(s)
	if type(s) ~= "string" then return nil end
	s = s:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Matching key: lower case, no leading "The", letters and digits only.
local function key(s)
	s = (clean(s) or ""):lower():gsub("^the%s+", "")
	return (s:gsub("[^%w]", ""))
end
Loot.key = key

---------------------------------------------------------------------------------------------
-- AtlasLoot reader
---------------------------------------------------------------------------------------------
local atlas = { state = "not read" }   -- { state, modules = {names}, dungeons = list }

local AddOns = C_AddOns or {}
local GetNumAddOns = AddOns.GetNumAddOns or GetNumAddOns
local GetAddOnInfo = AddOns.GetAddOnInfo or GetAddOnInfo
local LoadAddOn = AddOns.LoadAddOn or LoadAddOn
local IsAddOnLoaded = AddOns.IsAddOnLoaded or IsAddOnLoaded

-- AtlasLoot's dungeon/raid data addons, by name ("AtlasLootClassic_DungeonsAndRaids" and the like).
local function atlasModules()
	local out = {}
	for i = 1, (ns.safe(GetNumAddOns) or 0) do
		local name = ns.safe(GetAddOnInfo, i)
		if type(name) == "string" and name:find("^AtlasLoot") and (name:find("Dungeon") or name:find("Raid")) then
			out[#out + 1] = name
		end
	end
	return out
end

local function readAtlas()
	if InCombatLockdown() then return end   -- loading another addon's data mid-fight can stall a frame
	if type(_G.AtlasLoot) ~= "table" then
		-- Its core may be load-on-demand: load any AtlasLoot addon without a "_Module" suffix.
		for i = 1, (ns.safe(GetNumAddOns) or 0) do
			local name = ns.safe(GetAddOnInfo, i)
			if type(name) == "string" and name:find("^AtlasLoot") and not name:find("_") then pcall(LoadAddOn, name) end
		end
	end
	if type(_G.AtlasLoot) ~= "table" then
		atlas = { state = "not installed" }
		return
	end
	local modules = atlasModules()
	local storage = type(AtlasLoot.ItemDB) == "table" and AtlasLoot.ItemDB.Storage
	if type(storage) ~= "table" then
		atlas = { state = "installed, but its data layout isn't the one GearAdvisor knows" }
		return
	end
	local dungeons, read = {}, {}
	for _, module in ipairs(modules) do
		if not ns.safe(IsAddOnLoaded, module) then pcall(LoadAddOn, module) end
		local data = storage[module]
		if type(data) == "table" then
			read[#read + 1] = module
			for k, entry in pairs(data) do
				if type(k) == "string" and k:sub(1, 2) ~= "__" and type(entry) == "table" and type(entry.items) == "table" then
					local d = {
						name = clean(entry.name) or k,
						instanceID = type(entry.InstanceID) == "number" and entry.InstanceID or nil,
						bosses = {},
					}
					if type(entry.LevelRange) == "table" then
						d.minLevel = entry.LevelRange[1]
						d.maxLevel = entry.LevelRange[#entry.LevelRange]
					end
					for _, boss in ipairs(entry.items) do
						local bname = type(boss) == "table" and clean(boss.name)
						if bname and bname ~= "" then
							local ids, has = {}, {}
							for diff, list in pairs(boss) do
								if type(diff) == "number" and type(list) == "table" then
									for _, it in ipairs(list) do
										local id = type(it) == "table" and it[2]
										if type(id) == "number" and id > 0 and not has[id] then
											has[id] = true
											ids[#ids + 1] = id
										end
									end
								end
							end
							if #ids > 0 then d.bosses[#d.bosses + 1] = { name = bname, ids = ids } end
						end
					end
					if #d.bosses > 0 then dungeons[#dungeons + 1] = d end
				end
			end
		end
	end
	if #read == 0 then
		atlas = { state = "installed, but no dungeon data module found (" .. (#modules > 0 and table.concat(modules, ", ") or "none") .. ")" }
		return
	end
	atlas = { state = "read", modules = read, dungeons = dungeons }
end

---------------------------------------------------------------------------------------------
-- Merged view
---------------------------------------------------------------------------------------------
local merged      -- { list = dungeons sorted by name, byKey, byItem = itemID -> { {dungeon, boss}, ... } }

function Loot.invalidate() merged = nil end

local function build()
	if atlas.state == "not read" then readAtlas() end
	local byKey, list, byItem = {}, {}, {}
	local function dungeonOf(name)
		local k = key(name)
		local d = byKey[k]
		if not d then
			d = { name = clean(name) or name, bosses = {}, bossByKey = {} }
			byKey[k] = d
			list[#list + 1] = d
		end
		return d
	end
	local function bossOf(d, name)
		local k = key(name)
		local b = d.bossByKey[k]
		if not b then
			b = { name = clean(name) or name, items = {}, order = {} }
			d.bossByKey[k] = b
			d.bosses[#d.bosses + 1] = b
		end
		return b
	end
	local function addItem(d, b, id, from, count)
		local it = b.items[id]
		if not it then
			it = { id = id }
			b.items[id] = it
			b.order[#b.order + 1] = id
			byItem[id] = byItem[id] or {}
			table.insert(byItem[id], { dungeon = d, boss = b })
		end
		if from == "atlas" then it.atlas = true
		elseif from == "bundled" then
			it.bundled = true
			if count and count > 0 then it.chance = count end
		else it.seen = (it.seen or 0) + (count or 1) end
	end

	local bundled = ns.BossLoot and ns.BossLoot.dungeons
	for _, src in ipairs(bundled or {}) do
		local d = dungeonOf(src.name)
		d.minLevel, d.maxLevel, d.levelSource = src.minLevel, src.maxLevel, src.levelSource
		d.kind, d.fromBundled = src.kind, true
		for _, sb in ipairs(src.bosses or {}) do
			local b = bossOf(d, sb.name)
			b.level = b.level or sb.level
			for id, chance in pairs(sb.items or {}) do addItem(d, b, id, "bundled", chance) end
			table.sort(b.order)
		end
	end

	for _, src in ipairs(atlas.dungeons or {}) do
		local d = dungeonOf(src.name)
		-- AtlasLoot's level range beats one guessed from boss levels; Forever's own range beats both.
		if src.minLevel and (not d.minLevel or d.levelSource == "bosses") then
			d.minLevel, d.maxLevel, d.levelSource = src.minLevel, src.maxLevel, "atlas"
		end
		d.fromAtlas = true
		for _, sb in ipairs(src.bosses) do
			local b = bossOf(d, sb.name)
			for _, id in ipairs(sb.ids) do addItem(d, b, id, "atlas") end
		end
	end
	for dname, bosses in pairs(ns.db and ns.db.drops or {}) do
		local d = dungeonOf(dname)
		d.fromRecorder = true
		for bname, items in pairs(bosses) do
			local b = bossOf(d, bname)
			for id, count in pairs(items) do addItem(d, b, id, "seen", count) end
		end
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	local result = { list = list, byKey = byKey, byItem = byItem }
	-- Keep it only once AtlasLoot has been looked at (in combat it waits, so build again later).
	if atlas.state ~= "not read" then merged = result end
	return result
end

local function get() return merged or build() end

-- Every dungeon we know, sorted by name: { name, minLevel, maxLevel, bosses = { { name, items, order } } }.
function Loot.dungeons() return get().list end

-- One dungeon by (loosely matched) name, or nil.
function Loot.dungeon(name) return get().byKey[key(name)] end

-- Where an item drops: list of { dungeon, boss }, or nil.
function Loot.sourcesOf(itemID) return get().byItem[itemID] end

function Loot.status()
	local m = get()
	local n, items = #m.list, 0
	for _ in pairs(m.byItem) do items = items + 1 end
	local recorded = 0
	for _, bosses in pairs(ns.db and ns.db.drops or {}) do
		for _, list in pairs(bosses) do for _ in pairs(list) do recorded = recorded + 1 end end
	end
	local bundled = { dungeons = 0, bosses = 0, items = 0 }
	local ids = {}
	for _, d in ipairs(ns.BossLoot and ns.BossLoot.dungeons or {}) do
		bundled.dungeons = bundled.dungeons + 1
		for _, b in ipairs(d.bosses or {}) do
			bundled.bosses = bundled.bosses + 1
			for id in pairs(b.items or {}) do
				if not ids[id] then ids[id] = true; bundled.items = bundled.items + 1 end
			end
		end
	end
	return {
		atlas = atlas.state, modules = atlas.modules, dungeons = n, items = items, recorded = recorded,
		bundled = bundled,
	}
end

-- Ranked upgrades from one dungeon: list of { result, boss } (best first), how many still loading,
-- the dungeon, and extra = { early = list of { result, boss } your class can wear but not for more
-- than a few levels (no upgrade claim: shown for planning), items = how many items it has at all }.
function Loot.upgradesIn(name)
	local d = Loot.dungeon(name)
	if not d then return nil end
	local out, loading = {}, 0
	local extra = { early = {}, items = 0 }
	for _, b in ipairs(d.bosses) do
		for _, id in ipairs(b.order) do
			extra.items = extra.items + 1
			local ok, r = pcall(ns.Score.compare, "item:" .. id)
			if ok and r then
				if r.kind == "loading" then loading = loading + 1
				elseif r.kind == "upgrade" or r.kind == "future" then out[#out + 1] = { result = r, boss = b, dungeon = d }
				elseif r.kind == "too early" and r.info then extra.early[#extra.early + 1] = { result = r, boss = b, dungeon = d } end
			end
		end
	end
	table.sort(out, function(a, b) return a.result.pct > b.result.pct end)
	return out, loading, d, extra
end

---------------------------------------------------------------------------------------------
-- Drop recorder
---------------------------------------------------------------------------------------------
-- After a boss dies, gear seen dropping in the same dungeon within this many seconds is noted
-- against that boss (from your loot window, roll windows and the group's loot messages).
local WINDOW = 90
local lastBoss   -- { name, dungeon, time }

local function inDungeon()
	local name, instanceType = GetInstanceInfo()
	if instanceType == "party" or instanceType == "raid" then return name end
end

local function record(link)
	if not (lastBoss and link) or ns.isSecret(link) then return end
	if GetTime() - lastBoss.time > WINDOW then return end
	local dungeon = inDungeon()
	if dungeon ~= lastBoss.dungeon then return end
	if not ns.Stats.isGear(link) then return end
	local id = ns.safe((C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant, link)
	if not id then return end
	ns.db.drops = ns.db.drops or {}
	local bosses = ns.db.drops[dungeon] or {}
	ns.db.drops[dungeon] = bosses
	local items = bosses[lastBoss.name] or {}
	bosses[lastBoss.name] = items
	lastBoss.seen = lastBoss.seen or {}
	if lastBoss.seen[id] then return end   -- the same drop seen in the loot window and chat: count once
	lastBoss.seen[id] = true
	items[id] = (items[id] or 0) + 1
	Loot.invalidate()
end
Loot.lastBoss = function() return lastBoss end

local function linksIn(msg)
	local out = {}
	if type(msg) ~= "string" or ns.isSecret(msg) then return out end
	for link in msg:gmatch("|c[^|]*|Hitem:.-|h.-|h|r") do out[#out + 1] = link end
	return out
end

local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "ENCOUNTER_END", "BOSS_KILL", "LOOT_OPENED", "START_LOOT_ROLL", "CHAT_MSG_LOOT", "ADDON_LOADED" }) do
	pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", function(_, event, a1, a2, a3, a4, a5)
	if event == "PLAYER_LOGIN" then
		atlas = { state = "not read" }
		Loot.invalidate()
	elseif event == "ADDON_LOADED" then
		if type(a1) == "string" and a1:find("^AtlasLoot") and atlas.state ~= "read" then
			atlas = { state = "not read" }
			Loot.invalidate()
		end
	elseif event == "ENCOUNTER_END" then
		-- encounterID, encounterName, difficultyID, groupSize, success
		if a5 == 1 and not ns.isSecret(a2) then
			lastBoss = { name = clean(a2), dungeon = inDungeon(), time = GetTime() }
		end
	elseif event == "BOSS_KILL" then
		-- encounterID, encounterName (a fallback if ENCOUNTER_END didn't fire)
		if not ns.isSecret(a2) and not (lastBoss and GetTime() - lastBoss.time < 5) then
			lastBoss = { name = clean(a2), dungeon = inDungeon(), time = GetTime() }
		end
	elseif event == "LOOT_OPENED" then
		for slot = 1, (ns.safe(GetNumLootItems) or 0) do pcall(record, ns.safe(GetLootSlotLink, slot)) end
	elseif event == "START_LOOT_ROLL" then
		pcall(record, ns.safe(GetLootRollItemLink, a1))
	elseif event == "CHAT_MSG_LOOT" then
		for _, link in ipairs(linksIn(a1)) do pcall(record, link) end
	end
end)
