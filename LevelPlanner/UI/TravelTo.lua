-- TravelTo: the step list's "..." > Travel menu. Pick a dungeon or a zone and LevelPlanner routes you
-- there (hearthstone, flights, boats, zeppelins, passes) ahead of every other step, until you arrive
-- or right-click a travel step. Kept per character, so it survives a /reload.
--
-- Dungeon entrances: Questie's (Classic dungeons and raids, and the Forever ones it places), the
-- planner's own dungeonData entrances (Krol'dok), and EXTRA below. Entrances seen as you zone into a
-- dungeon are learned (LevelPlannerDB.travelEntrances) and win over the guessed ones.
-- Zones: every zone and city of Kalimdor and the Eastern Kingdoms, from the game's map data; you're
-- sent to the quickest way in (a zone crossing, a flight path, a dock - else the middle of the zone).
local ADDON, zyde = ...
zyde.LP = zyde.LP or {}
local ns = zyde.LP

local TT = {}
ns.TravelTo = TT

local CONTINENTS = { { map = 1414, short = "Kalimdor" }, { map = 1415, short = "E. Kingdoms" } }

-- Questie dungeon area IDs that are places you can go on Forever (not battlegrounds, cities' arenas
-- or later expansions' instances). raid = true marks raids.
local QUESTIE = {
	[2437] = {}, [718] = {}, [1581] = {}, [209] = {}, [719] = {}, [717] = {}, [721] = {}, [491] = {},
	[796] = {}, [722] = {}, [1337] = {}, [1176] = {}, [2100] = {}, [1477] = {}, [1584] = {}, [1583] = {},
	[2557] = {}, [2057] = {}, [2017] = {},
	[2717] = { raid = true }, [2677] = { raid = true }, [2159] = { raid = true }, [1977] = { raid = true },
	[3429] = { raid = true }, [3428] = { raid = true }, [3456] = { raid = true },
	-- Forever's own, placed by Questie
	[16544] = { lo = 28, hi = 35 }, [16732] = { lo = 26, hi = 33 }, [16611] = { lo = 15, hi = 22 },
	[16919] = { lo = 13, hi = 20 }, [16074] = {},
}
local RAID_LEVELS = { [2717] = 60, [2677] = 60, [2159] = 60, [1977] = 60, [3429] = 60, [3428] = 60, [3456] = 60 }

-- Forever dungeons nobody places yet: entrances from player guides (Nov 2026), APPROXIMATE.
-- map = uiMapID, x/y = 0-100. Learned entrances replace these the first time you zone in.
local EXTRA = {
	{ name = "Alcaz Prison", map = 1445, x = 75.3, y = 14.1, lo = 48, hi = 53 },          -- Alcaz Island, tower basement
	{ name = "Blackmaw Hold", map = 1447, x = 38.4, y = 32.6, lo = 55, hi = 60 },         -- the tunnel into the hold
	{ name = "The Drowned City", map = 1434, x = 21.4, y = 27.9, lo = 35, hi = 40 },      -- underwater, Sunken Hollow
	{ name = "The Shaper's Terrace", map = 1449, x = 48.4, y = 8.6, lo = 58, hi = 60 },   -- the staircase up to it
	{ name = "Manor Mistmantle", map = 1431, x = 77.0, y = 36.0 },                         -- the manor (rough guess)
}

local function key(name)
	return (name or ""):lower():gsub("^the ", ""):gsub("[^%w]", "")
end

local function learned()
	ns.db.travelEntrances = ns.db.travelEntrances or {}
	return ns.db.travelEntrances
end

----------------------------------------------------------------------------------------
-- The lists
----------------------------------------------------------------------------------------
local dungeonList, zoneList

-- { name, points = { {map, x, y}, ... }, lo, hi, raid } sorted by name.
function TT.Dungeons()
	if dungeonList then return dungeonList end
	local out, seen = {}, {}
	local function add(d)
		local k = key(d.name)
		if seen[k] then
			-- (Questie lists Dire Maul's wings apart: one entry, every entrance)
			for _, p in ipairs(d.points) do table.insert(seen[k].points, p) end
			return
		end
		seen[k] = d
		out[#out + 1] = d
	end
	local data = ns.cfg.dungeonData or {}
	local ZoneDB = ns.Q and ns.Q.ZoneDB
	local all = ZoneDB and ZoneDB.GetDungeons and ns.safe(ZoneDB.GetDungeons, ZoneDB) or {}
	for area, info in pairs(QUESTIE) do
		local entry = all[area]
		local pts = {}
		for _, loc in ipairs(entry and type(entry[4]) == "table" and entry[4] or {}) do
			local p = ns.Geo.Point(loc[1], loc[2], loc[3])
			if p then pts[#pts + 1] = { map = p.map, x = p.x, y = p.y } end
		end
		if #pts > 0 then
			local dd = data[area]
			local name = (entry and entry[1]) or (dd and dd[1]) or ("Dungeon " .. area)
			add({ name = name, points = pts, raid = info.raid, lo = info.lo or (dd and dd[2]) or RAID_LEVELS[area],
				hi = info.hi or (dd and dd[3]) })
		end
	end
	-- the planner's own (Forever dungeons Questie doesn't list)
	for area, dd in pairs(data) do
		if dd.entrance and not QUESTIE[area] then
			local p = ns.Geo.Point(dd.entrance[1], dd.entrance[2], dd.entrance[3])
			if p then add({ name = dd[1], points = { { map = p.map, x = p.x, y = p.y } }, lo = dd[2], hi = dd[3] }) end
		end
	end
	for _, e in ipairs(EXTRA) do
		add({ name = e.name, points = { { map = e.map, x = e.x, y = e.y } }, lo = e.lo, hi = e.hi, guessed = true })
	end
	table.sort(out, function(a, b) return key(a.name) < key(b.name) end)
	if ns.ready then dungeonList = out end -- (before Questie is ready only the guessed ones are known)
	return out
end

-- { name, map, cont } sorted by name: every zone and city on the two continents.
function TT.Zones()
	if zoneList then return zoneList end
	local out, seen = {}, {}
	local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
	for _, c in ipairs(CONTINENTS) do
		local kids = C_Map.GetMapChildrenInfo and ns.safe(C_Map.GetMapChildrenInfo, c.map, zoneType, false) or {}
		for _, k in ipairs(kids or {}) do
			if k.name and k.name ~= "" and not seen[k.mapID] and ns.Geo.PointOnMap(k.mapID, 50, 50) then
				seen[k.mapID] = true
				out[#out + 1] = { name = k.name, map = k.mapID, cont = c.short }
			end
		end
	end
	table.sort(out, function(a, b) return key(a.name) < key(b.name) end)
	zoneList = out
	return out
end

----------------------------------------------------------------------------------------
-- Where to go
----------------------------------------------------------------------------------------
local function current() return ns.char and ns.char.travelTo end

local function travelSeconds(a, b)
	return ns.Travel and ns.Travel.Seconds and ns.Travel.Seconds(a, b) or ns.Geo.TravelSeconds(a, b)
end

-- Is map `m` (or a map inside it) the zone?
local function inZone(zoneMap)
	local m = C_Map.GetBestMapForUnit("player")
	local guard = 0
	while m and guard < 6 do
		if m == zoneMap then return true end
		local info = C_Map.GetMapInfo(m)
		m = info and info.parentMapID
		guard = guard + 1
	end
	return false
end

-- The zone's middle, if it really is in the zone (odd-shaped zones: not always).
local function zoneMiddle(map)
	local p = ns.Geo.PointOnMap(map, 50, 50)
	if not p then return nil end
	for _, c in ipairs(CONTINENTS) do
		local x, y = ns.Geo.ZoneCoords(p, c.map)
		if x then
			local z = ns.Geo.ZoneAt(c.map, x / 100, y / 100)
			if z and z ~= map then return nil end
			return p
		end
	end
	return p
end

-- The points you could head for, each { point, label }.
local function candidates(dest)
	local out = {}
	if dest.kind == "dungeon" then
		local l = learned()[key(dest.name)]
		local pts = l and { l } or dest.points
		for _, q in ipairs(pts or {}) do
			local p = ns.Geo.PointOnMap(q.map, q.x, q.y)
			if p then out[#out + 1] = { point = p } end
		end
	else
		for _, n in ipairs(ns.Travel.NodesOn and ns.Travel.NodesOn(dest.map) or {}) do
			local p = ns.Geo.PointOnMap(n.map, n.x, n.y)
			if p then out[#out + 1] = { point = p, via = n.name } end
		end
		local mid = zoneMiddle(dest.map)
		if mid then out[#out + 1] = { point = mid } end
	end
	return out
end

local function bestTarget(dest, from)
	local best, bestT
	for _, c in ipairs(candidates(dest)) do
		local t = travelSeconds(from, c.point)
		if t and (not bestT or t < bestT) then best, bestT = c, t end
	end
	return best, bestT
end

-- The travel steps from where you stand, or nil when there is nothing to do.
local function buildSteps(dest)
	local start = ns.Geo.PlayerPoint()
	if not start then return nil end
	local target, secs = bestTarget(dest, start)
	if not target then return nil end
	local cfg = ns.cfg
	local steps, from = {}, start
	-- the hearthstone, when it's ready and gets you there clearly sooner
	local h = ns.Travel.Hearth and ns.Travel.Hearth()
	if h and h.readyIn <= 0 then
		local hs = cfg.hearthSeconds or 45
		local alt = hs + travelSeconds(h.point, target.point)
		if alt + 60 < secs then
			steps[#steps + 1] = { kind = "travel", mode = "hearth", label = "Use your hearthstone (" .. h.name .. ")",
				point = start, work = hs, mobXp = 0, xp = 0, travelTo = true }
			from, secs = h.point, alt
		end
	end
	local arrived = (cfg.arrivedYards or 15) * 2
	for _, leg in ipairs(ns.Travel.Legs(from, target.point)) do
		local dFrom = ns.Geo.Distance(leg.point, from)
		local dEnd = ns.Geo.Distance(leg.point, target.point)
		local edge = leg.mode == "pass" or leg.mode == "border"
		if not (edge and ((dFrom and dFrom <= arrived) or (dEnd and dEnd <= arrived))) then
			steps[#steps + 1] = { kind = "travel", mode = leg.mode, label = leg.label, point = leg.point,
				work = leg.seconds, mobXp = 0, xp = 0, to = leg.to, travelTo = true }
		end
	end
	local label
	if dest.kind == "dungeon" then
		label = "Go to the " .. dest.name .. " entrance"
	else
		label = "Go to " .. dest.name .. (target.via and (" (" .. target.via .. ")") or "")
	end
	steps[#steps + 1] = { kind = "goto", label = label, point = target.point, work = 0, mobXp = 0, xp = 0,
		travelTo = true, destKind = dest.kind, travelSecs = secs, guessed = dest.guessed and not learned()[key(dest.name)] }
	return steps
end

local function signature(steps)
	local t = {}
	for _, s in ipairs(steps or {}) do
		t[#t + 1] = string.format("%s:%.0f:%.0f", s.label or "", s.point and s.point.wx or 0, s.point and s.point.wy or 0)
	end
	return table.concat(t, "|")
end
local shownSig

-- Puts the travel steps at the top of the plan's steps (after a ghost's run back to the corpse).
function TT.Apply(plan)
	if not plan or not plan.stops then return end
	for i = #plan.stops, 1, -1 do
		if plan.stops[i].travelTo then table.remove(plan.stops, i) end
	end
	local dest = current()
	local steps = dest and buildSteps(dest)
	shownSig = signature(steps)
	if not steps then return end
	local at = (plan.stops[1] and plan.stops[1].mode == "corpse") and 2 or 1
	for i, s in ipairs(steps) do table.insert(plan.stops, at + i - 1, s) end
end

local function refresh()
	if not ns.OnPlanReady then return end
	if not ns.plan then
		-- (nothing planned yet - at the level cap, say: the trip alone)
		ns.plan = { stops = {}, onWay = {}, keys = {}, route = {}, xp = 0, seconds = 0, rate = 0, score = 0 }
	end
	ns.OnPlanReady(ns.plan)
end

local function arrivedAt(dest)
	if dest.kind == "zone" then return inZone(dest.map) end
	local _, t = IsInInstance()
	if t == "party" or t == "raid" then
		return key((GetInstanceInfo())) == key(dest.name)
	end
	local here = ns.Geo.PlayerPoint()
	for _, c in ipairs(candidates(dest)) do
		local d = here and ns.Geo.Distance(here, c.point)
		if d and d <= (ns.cfg.travelArrivedYards or 20) then return true end
	end
	return false
end

function TT.Set(kind, item)
	if not ns.active then ns.print("the level planner is off.") return end
	local dest = { kind = kind, name = item.name, map = item.map, points = item.points, guessed = item.guessed }
	if arrivedAt(dest) then
		ns.print("you're already " .. (kind == "zone" and "in " or "at ") .. item.name .. ".")
		return
	end
	if #candidates(dest) == 0 then
		ns.print("Travel: no known way to " .. item.name .. " from here.")
		return
	end
	ns.char.travelTo = dest
	ns.print(string.format("Travel: heading for %s%s - first in the steps until you get there (right-click a travel step to stop).",
		item.name, (item.guessed and not learned()[key(item.name)]) and " (entrance approximate)" or ""))
	refresh()
end

function TT.Clear(arrivedMsg)
	local dest = current()
	if not dest then return end
	ns.char.travelTo = nil
	if arrivedMsg then
		ns.print("Travel: you've reached " .. dest.name .. ".")
		ns.safe(PlaySound, SOUNDKIT and SOUNDKIT.MAP_PING or 3175, "SFX")
	end
	refresh()
end

function TT.Current() return current() end

-- /lp travel <name>: a dungeon or zone by (part of) its name
function TT.SetByName(text)
	local want = key(text)
	if want == "" then return false end
	local function find(list)
		for _, it in ipairs(list) do if key(it.name) == want then return it end end
		for _, it in ipairs(list) do if key(it.name):find(want, 1, true) then return it end end
	end
	local d = find(TT.Dungeons())
	if d then TT.Set("dungeon", d) return true end
	local z = find(TT.Zones())
	if z then TT.Set("zone", z) return true end
	return false
end

----------------------------------------------------------------------------------------
-- Watching the trip: arrival, and fresh steps as you go (a flight landed, a pass crossed)
----------------------------------------------------------------------------------------
local lastOutside, lastOutsideAt -- where you were just before a loading screen (dungeon entrances)
C_Timer.NewTicker(2, function()
	if not ns.active then return end
	local _, t = IsInInstance()
	if t == "none" and not (UnitOnTaxi and UnitOnTaxi("player")) then
		local p = ns.Geo.PlayerPoint()
		if p and p.map and p.x then lastOutside, lastOutsideAt = p, GetTime() end
	end
	local dest = current()
	if not dest then return end
	if arrivedAt(dest) then TT.Clear(true) return end
	if InCombatLockdown() or (UnitOnTaxi and UnitOnTaxi("player")) or t ~= "none" then return end
	if ns.JobRunning and ns.JobRunning() then return end
	local steps = buildSteps(dest)
	if signature(steps) ~= shownSig then refresh() end
end)

-- Zoning into a dungeon: remember where its entrance is (the last spot outside, a moment ago).
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function()
	if not (ns.active and ns.db) then return end
	local _, t = IsInInstance()
	if not (t == "party" or t == "raid") then return end
	local name = GetInstanceInfo()
	local o, at = lastOutside, lastOutsideAt
	if not (name and o and at and GetTime() - at <= 12) then return end
	local k = key(name)
	-- (a summon or a port would record the wrong place: only somewhere near what we knew, or new ones)
	local known
	for _, d in ipairs(TT.Dungeons()) do
		if key(d.name) == k then known = d break end
	end
	if not known then return end
	local near = false
	for _, q in ipairs(known.points) do
		local p = ns.Geo.PointOnMap(q.map, q.x, q.y)
		local d = p and ns.Geo.Distance(p, o)
		if d and d <= (known.guessed and 1500 or 300) then near = true end
	end
	if not near then return end
	learned()[k] = { map = o.map, x = o.x, y = o.y }
end)

----------------------------------------------------------------------------------------
-- The menus: "..." > Travel > Dungeons / Zones > the list
----------------------------------------------------------------------------------------
local ROW_H, ROWS, LIST_W, SIDE_W = 18, 20, 230, 150

local function panel(parent, name)
	local f = CreateFrame("Frame", name, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	if f.SetBackdrop then
		f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		f:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
		f:SetBackdropBorderColor(1, 1, 1, 0.2)
	end
	f:Hide()
	return f
end

local function rowButton(parent, w)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, ROW_H)
	b.hl = b:CreateTexture(nil, "HIGHLIGHT")
	b.hl:SetAllPoints()
	b.hl:SetColorTexture(1, 1, 1, 0.1)
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.text:SetPoint("LEFT", 8, 0)
	b.text:SetJustifyH("LEFT")
	b.right = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.right:SetPoint("RIGHT", -8, 0)
	b.right:SetJustifyH("RIGHT")
	return b
end

local side, list

local function levelColor(lo, hi)
	local L = ns.playerLevel()
	if not lo then return "|cff999999" end
	if L > (hi or lo) + 2 then return "|cff808080" end
	if L >= lo - 2 then return "|cffffd100" end
	return "|cffff6060"
end

local function showList(kind, anchor)
	if not list then
		list = panel(side, "LevelPlannerTravelList")
		list.title = list:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		list.title:SetPoint("TOPLEFT", 8, -6)
		list.rows = {}
		for i = 1, ROWS do
			local b = rowButton(list, LIST_W - 8)
			b:SetPoint("TOPLEFT", 4, -22 - (i - 1) * ROW_H)
			b:SetScript("OnClick", function(self)
				if not self.item then return end
				local menu = _G.LevelPlannerPinMenu
				if menu then menu:Hide() end
				TT.Set(list.kind, self.item)
			end)
			b:SetScript("OnEnter", function(self)
				local it = self.item
				if not it then return end
				GameTooltip:SetOwner(self, "ANCHOR_LEFT")
				GameTooltip:AddLine(it.name)
				if list.kind == "dungeon" then
					if it.lo then GameTooltip:AddLine(string.format("Level %d%s%s", it.lo, it.hi and it.hi ~= it.lo and ("-" .. it.hi) or "", it.raid and " raid" or ""), 1, 1, 1) end
					local l = learned()[key(it.name)]
					if l then
						GameTooltip:AddLine("Entrance: where you last zoned in.", 0.6, 0.8, 1, true)
					elseif it.guessed then
						GameTooltip:AddLine("Entrance approximate (player guides) - learned the first time you zone in.", 1, 0.8, 0.4, true)
					end
				else
					GameTooltip:AddLine(it.cont, 1, 1, 1)
				end
				GameTooltip:AddLine("Click: route there, ahead of every other step.", 0.6, 0.8, 1, true)
				GameTooltip:Show()
			end)
			b:SetScript("OnLeave", function() GameTooltip:Hide() end)
			list.rows[i] = b
		end
		list:SetSize(LIST_W, 22 + ROWS * ROW_H + 6)
		list:EnableMouseWheel(true)
		list:SetScript("OnMouseWheel", function(self, delta)
			local max = math.max(0, #self.items - ROWS)
			self.offset = math.min(max, math.max(0, self.offset - delta * 3))
			self.fill()
		end)
		list.fill = function()
			for i, b in ipairs(list.rows) do
				local it = list.items[list.offset + i]
				b.item = it
				if it then
					b.text:SetText(it.name)
					if list.kind == "dungeon" then
						b.right:SetText(it.lo and (levelColor(it.lo, it.hi) .. it.lo .. (it.hi and it.hi ~= it.lo and ("-" .. it.hi) or "") .. (it.raid and " R" or "") .. "|r") or "")
					else
						b.right:SetText("|cff999999" .. it.cont .. "|r")
					end
					b:Show()
				else
					b:Hide()
				end
			end
			local more = #list.items > ROWS and string.format("  |cff999999%d-%d of %d (scroll)|r", list.offset + 1,
				math.min(#list.items, list.offset + ROWS), #list.items) or ""
			list.title:SetText((list.kind == "dungeon" and "Dungeons" or "Zones") .. more)
		end
	end
	list.kind = kind
	list.items = kind == "dungeon" and TT.Dungeons() or TT.Zones()
	list.offset = 0
	list:ClearAllPoints()
	list:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -2, 6)
	list.fill()
	list:Show()
end

-- The Travel flyout, to the left of the "..." menu's Travel row.
function TT.ToggleSide(anchor)
	if side and side:IsShown() then side:Hide() return end
	if not side then
		side = panel(anchor:GetParent(), "LevelPlannerTravelMenu")
		local head = side:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		head:SetPoint("TOPLEFT", 8, -6)
		head:SetText("Travel to")
		local y = -22
		side.buttons = {}
		for _, kind in ipairs({ "dungeon", "zone" }) do
			local b = rowButton(side, SIDE_W - 8)
			b:SetPoint("TOPLEFT", 4, y)
			b.text:SetText(kind == "dungeon" and "Dungeons" or "Zones")
			b.right:SetText(">")
			b:SetScript("OnClick", function(self)
				if list and list:IsShown() and list.kind == kind then list:Hide() else showList(kind, self) end
			end)
			y = y - ROW_H
		end
		local stop = rowButton(side, SIDE_W - 8)
		stop:SetPoint("TOPLEFT", 4, y)
		stop:SetScript("OnClick", function()
			local menu = _G.LevelPlannerPinMenu
			if menu then menu:Hide() end
			TT.Clear()
		end)
		side.stop = stop
	end
	local dest = current()
	if dest then
		side.stop.text:SetText("|cffff6666Stop|r: " .. dest.name)
		side.stop:SetWidth(SIDE_W + 60 - 8)
		side.stop:Show()
		side:SetSize(SIDE_W + 60, 22 + 3 * ROW_H + 6)
	else
		side.stop:Hide()
		side:SetSize(SIDE_W, 22 + 2 * ROW_H + 6)
	end
	if list then list:Hide() end
	side:ClearAllPoints()
	side:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -6, 6)
	side:Show()
end
