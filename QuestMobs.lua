-- Zyde_Forever: quest mobs near you (needs Questie).
-- Any enemy with a nameplate that you still need for a quest (a kill, or an
-- item it drops) counts, if it's alive and not someone else's tag:
--   1) a pulsing gold edge around its nameplate health bar
--   2) a small "Quest mobs: 3" box (drag to move; hover for which mobs)
--   3) a keybind, "Target nearest quest mob" (Keybindings > AddOns > Zyde
--      Forever), that runs /target <name> for quest mobs. Like Zygor's key
--      it works all around you and past nameplate range: the names come
--      from Questie's data for your zone (nearest known spawn wins), plus
--      any quest mob on a nameplate right now (those win over the rest).
-- The glow and the count only see mobs with a nameplate: enemy nameplates
-- must be on, and their range (about 20-40 yards) is the limit.
-- The keybind's macro can only be rebuilt out of combat (game rule): in
-- combat it keeps the names from just before the fight.
-- /zyde resetmobs - put the count box back at its default spot

local ADDON, ns = ...

local TT, DB, ZDB -- QuestieTooltips, QuestieDB, ZoneDB
local MAX_NAMES = 6 -- names in the target macro (keeps it short)
local BOX_DEFAULT = { point = "CENTER", x = 0, y = -235 }
local GOLD = { 1, 0.82, 0.2 }

local function db()
	ZydeForeverDB = ZydeForeverDB or {}
	return ZydeForeverDB
end
local function on() return TT ~= nil and ns.F("questMobs") end

local function plain(v)
	if v == nil or ns.isSecret(v) then return nil end
	return v
end

local function npcFromGUID(guid)
	guid = plain(guid)
	if type(guid) ~= "string" then return nil end
	local unitType, _, _, _, _, npcId = strsplit("-", guid)
	if (unitType ~= "Creature" and unitType ~= "Vehicle") or not npcId then return nil end
	return tonumber(npcId)
end

---------------------------------------------------------------------------
-- Is this NPC needed for an unfinished quest objective? (Questie's tooltip
-- registry has "m_<npcId>" entries for kill and drop objectives.)
-- Cached per NPC; cleared whenever your quest log changes.
---------------------------------------------------------------------------
local wanted = {} -- npcId -> true / false

local function questNeeds(npcId)
	local v = wanted[npcId]
	if v ~= nil then return v end
	v = false
	local tips = TT and TT.lookupByKey and TT.lookupByKey["m_" .. npcId]
	for _, tip in pairs(tips or {}) do
		local obj = tip.objective
		if obj then
			if obj.Update then pcall(obj.Update, obj) end
			if not obj.Completed then v = true break end
		end
	end
	wanted[npcId] = v
	return v
end

local fightCache = {} -- npcId -> true if it's an enemy to fight (see fightable)
local zoneListAt = 0     -- when the zone list was last built (see zoneCandidates)

local function forgetQuests()
	wipe(wanted)
	wipe(fightCache)
	zoneListAt = 0
end

-- An NPC worth targeting with the key: not friendly to you, and needed for
-- more than a "talk to" objective.
local myFaction = UnitFactionGroup("player")
local function fightable(npcId)
	local v = fightCache[npcId]
	if v ~= nil then return v end
	v = true
	local f = DB and DB.QueryNPCSingle and ns.safe(DB.QueryNPCSingle, npcId, "friendlyToFaction")
	if f == "AH" or (f == "A" and myFaction == "Alliance") or (f == "H" and myFaction == "Horde") then v = false end
	if v then
		local talk = (_G.Questie and _G.Questie.ICON_TYPE_TALK) or 5
		local talkOnly = true
		for _, tip in pairs(TT.lookupByKey["m_" .. npcId] or {}) do
			local obj = tip.objective
			if obj and not obj.Completed and obj.Icon ~= talk then talkOnly = false break end
		end
		if talkOnly then v = false end
	end
	fightCache[npcId] = v
	return v
end

-- The mob's name as plain text (the macro needs it). The game can hide
-- unit names from addons, so fall back to Questie's database name.
local function mobName(unit, npcId)
	local n = plain(UnitName(unit))
	if type(n) == "string" and n ~= "" then return n end
	if DB and DB.QueryNPCSingle then
		n = ns.safe(DB.QueryNPCSingle, npcId, "name")
		if type(n) == "string" and n ~= "" then return n end
	end
	return nil
end

-- Nameplate unit tokens in use right now.
local function plateUnits()
	local units = {}
	local plates = C_NamePlate and C_NamePlate.GetNamePlates and ns.safe(C_NamePlate.GetNamePlates)
	if type(plates) == "table" and #plates > 0 then
		for _, plate in ipairs(plates) do
			local token = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
			if type(token) == "string" then units[#units + 1] = token end
		end
	end
	if #units == 0 then
		for i = 1, 40 do
			if UnitExists("nameplate" .. i) then units[#units + 1] = "nameplate" .. i end
		end
	end
	return units
end

-- Why a nameplate unit is or isn't a quest mob: true, or false + reason.
-- Hidden ("secret") answers never rule a mob out; only a clear "no" does.
local function check(unit)
	local npcId = npcFromGUID(UnitGUID(unit))
	if not npcId then return false, "not an NPC (or its ID is hidden)" end
	if not questNeeds(npcId) then return false, "Questie: no unfinished objective (npc " .. npcId .. ")" end
	if plain(UnitCanAttack("player", unit)) == false then return false, "not attackable" end
	if plain(UnitIsDead(unit)) == true then return false, "dead" end
	if plain(UnitIsTapDenied(unit)) == true then return false, "someone else's tag" end
	local name = mobName(unit, npcId)
	if not name then return false, "name unknown (npc " .. npcId .. ")" end
	return true, name
end

-- Quest mobs with a nameplate right now: list of { unit, name }.
local function scan()
	local found = {}
	for _, unit in ipairs(plateUnits()) do
		local ok, name = check(unit)
		if ok then found[#found + 1] = { unit = unit, name = name } end
	end
	return found
end

---------------------------------------------------------------------------
-- Nameplate highlight: a pulsing gold edge around the health bar.
---------------------------------------------------------------------------
local glows = {} -- plate -> glow frame

local function glowFor(plate)
	local g = glows[plate]
	if g then return g end
	local uf = plate.UnitFrame
	local bar = uf and (uf.healthBar or uf.HealthBar) or plate
	g = CreateFrame("Frame", nil, plate)
	g:SetAllPoints(bar)
	g:SetFrameLevel((bar.GetFrameLevel and bar:GetFrameLevel() or plate:GetFrameLevel()) + 5)
	g.edges = ns.newEdges(g, "OVERLAY", 7)
	ns.placeEdges(g.edges, g, -2, 2) -- just outside the bar
	for _, t in ipairs(g.edges) do t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1) end
	local pulse = g:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local a = pulse:CreateAnimation("Alpha")
	a:SetFromAlpha(1)
	a:SetToAlpha(0.35)
	a:SetDuration(0.7)
	a:SetSmoothing("IN_OUT")
	g.pulse = pulse
	g:Hide()
	glows[plate] = g
	return g
end

local function updateGlows(mobs)
	local want = {}
	for _, m in ipairs(mobs) do
		local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(m.unit)
		if plate then want[plate] = true end
	end
	for plate in pairs(want) do
		local g = glowFor(plate)
		if not g:IsShown() then g:Show() g.pulse:Play() end
	end
	for plate, g in pairs(glows) do
		if not want[plate] and g:IsShown() then g.pulse:Stop() g:Hide() end
	end
end

---------------------------------------------------------------------------
-- Count box
---------------------------------------------------------------------------
local box = CreateFrame("Frame", "ZydeForeverQuestMobs", UIParent, "BackdropTemplate")
box:SetSize(110, 20)
box:SetFrameStrata("MEDIUM")
box:SetClampedToScreen(true)
box:SetMovable(true)
box:EnableMouse(true)
box:RegisterForDrag("LeftButton")
box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
box:SetBackdropColor(0.08, 0.08, 0.08, 0.85)
box:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.8)
box:Hide()

box.text = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
box.text:SetPoint("CENTER")
box.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

local function placeBox()
	local p = db().questMobsPos or BOX_DEFAULT
	box:ClearAllPoints()
	box:SetPoint(p.point, UIParent, p.point, p.x, p.y)
end

box:SetScript("OnDragStart", function(self) self:StartMoving() end)
box:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local point, _, _, x, y = self:GetPoint()
	db().questMobsPos = { point = point, x = x, y = y }
end)

local current = {} -- last scan, for the tooltip

-- { {name, count}, ... }, fewest first.
local function byName(mobs)
	local counts, list = {}, {}
	for _, m in ipairs(mobs) do
		if not counts[m.name] then
			counts[m.name] = { name = m.name, count = 0 }
			list[#list + 1] = counts[m.name]
		end
		counts[m.name].count = counts[m.name].count + 1
	end
	table.sort(list, function(a, b)
		if a.count ~= b.count then return a.count < b.count end
		return a.name < b.name
	end)
	return list
end

box:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
	GameTooltip:AddLine("Quest mobs nearby")
	local list = byName(current)
	for i = #list, 1, -1 do
		GameTooltip:AddDoubleLine(list[i].name, "x" .. list[i].count, 1, 1, 1, GOLD[1], GOLD[2], GOLD[3])
	end
	GameTooltip:AddLine(" ")
	local key = GetBindingKey("CLICK ZydeForeverQuestMobTarget:LeftButton")
	GameTooltip:AddLine(key and ("Press " .. key .. " to target one.")
		or "Set a key to target them: Keybindings > AddOns > Zyde Forever.", 0.7, 0.7, 0.7, true)
	GameTooltip:AddLine("Only mobs with a nameplate are counted. Drag to move.", 0.5, 0.5, 0.5, true)
	GameTooltip:Show()
end)
box:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function updateBox(mobs)
	if #mobs == 0 then box:Hide() return end
	box.text:SetFormattedText("Quest mobs: %d", #mobs)
	box:SetWidth(box.text:GetStringWidth() + 16)
	box:Show()
	if GameTooltip:IsOwned(box) then box:GetScript("OnEnter")(box) end
end

---------------------------------------------------------------------------
-- Target key: a hidden secure macro button (addons can't target directly).
-- /target <name> picks a nearby mob with that name. With several kinds of
-- quest mob around, each /target that finds one replaces the last (order
-- below in macroNames). Dead ones are cleared again.
---------------------------------------------------------------------------
_G["BINDING_NAME_CLICK ZydeForeverQuestMobTarget:LeftButton"] = "Target nearest quest mob"

local targetButton = CreateFrame("Button", "ZydeForeverQuestMobTarget", UIParent, "SecureActionButtonTemplate")
targetButton:SetSize(1, 1)
targetButton:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
targetButton:SetAlpha(0)
targetButton:SetAttribute("type", "macro")
targetButton:SetAttribute("macrotext", "")

-- Your zone in Questie's terms (its spawn data is keyed by area ID), the
-- map that goes with it, and where you are on that map (0-100).
local function playerZone()
	if not (ZDB and ZDB.GetAreaIdByUiMapId and C_Map and C_Map.GetBestMapForUnit) then return nil end
	local map = ns.safe(C_Map.GetBestMapForUnit, "player")
	-- Caves and city districts: step up to the zone they belong to.
	for _ = 1, 3 do
		local info = map and ns.safe(C_Map.GetMapInfo, map)
		if not info or not Enum or not Enum.UIMapType or (info.mapType or 0) <= Enum.UIMapType.Zone then break end
		if not info.parentMapID or info.parentMapID == 0 then break end
		map = info.parentMapID
	end
	if not map then return nil end
	local area = ns.safe(ZDB.GetAreaIdByUiMapId, ZDB, map)
	if not area then return nil end
	local px, py
	local pos = C_Map.GetPlayerMapPosition and ns.safe(C_Map.GetPlayerMapPosition, map, "player")
	if pos and pos.GetXY then
		local x, y = pos:GetXY()
		if type(x) == "number" and not ns.isSecret(x) and not ns.isSecret(y) then px, py = x * 100, y * 100 end
	end
	return area, px, py
end

-- Quest mobs Questie knows spawn in your zone, nearest known spawn first:
-- { {name, d}, ... }. Works without nameplates, like Zygor's key. Rebuilt
-- at most every 2 seconds.
local zoneList = {}
local function zoneCandidates()
	if GetTime() - zoneListAt < 2 then return zoneList end
	zoneListAt = GetTime()
	wipe(zoneList)
	if not (TT and TT.lookupByKey and DB and DB.QueryNPCSingle) then return zoneList end
	local area, px, py = playerZone()
	if not area then return zoneList end
	local best = {} -- name -> squared distance to its nearest spawn
	for key in pairs(TT.lookupByKey) do
		local npcId = type(key) == "string" and tonumber(key:match("^m_(%d+)$"))
		if npcId and questNeeds(npcId) and fightable(npcId) then
			local spawns = ns.safe(DB.QueryNPCSingle, npcId, "spawns")
			local points = type(spawns) == "table" and spawns[area]
			if type(points) == "table" then
				local d = 1e9 -- spawns here but distance unknown: after the known ones
				if px then
					for _, s in ipairs(points) do
						if type(s) == "table" and type(s[1]) == "number" and type(s[2]) == "number" and s[1] >= 0 then
							local dx, dy = s[1] - px, s[2] - py
							local dd = dx * dx + dy * dy
							if dd < d then d = dd end
						end
					end
				end
				local name = ns.safe(DB.QueryNPCSingle, npcId, "name")
				if type(name) == "string" and name ~= "" and (not best[name] or d < best[name]) then best[name] = d end
			end
		end
	end
	for name, d in pairs(best) do zoneList[#zoneList + 1] = { name = name, d = d } end
	table.sort(zoneList, function(a, b)
		if a.d ~= b.d then return a.d < b.d end
		return a.name < b.name
	end)
	return zoneList
end

-- Names in the order to try them, best first: the ones on nameplates
-- around you (certainly close, most numerous first), then zone quest mobs
-- by nearest known spawn.
local function macroNames(mobs)
	local plates = byName(mobs) -- most numerous last
	local seen, names = {}, {}
	for i = #plates, 1, -1 do
		if #names >= MAX_NAMES then break end
		names[#names + 1] = plates[i].name
		seen[plates[i].name] = true
	end
	for _, e in ipairs(zoneCandidates()) do
		if #names >= MAX_NAMES then break end
		if not seen[e.name] then
			names[#names + 1] = e.name
			seen[e.name] = true
		end
	end
	return names
end

-- The first live match is kept: every /target after the first only runs
-- while you have no target ([noexists]), and a corpse is cleared right
-- away ([dead]) so the search goes on. Each name is tried twice, in case
-- the first hit was the corpse of the one you just killed.
--
-- Someone else's tag: a macro can't test for that, so out of combat the
-- macro first targets specific nameplate units (nameplate3...) that this
-- addon checked are alive and not tagged by anyone else. The macro is
-- rebuilt every half second and whenever a nameplate comes or goes, so
-- those stay current. Only if none of them is there do the name lines run
-- (those can still hit a tagged mob). When combat starts the macro can't
-- be rebuilt any more, so it switches to names only (namesOnly) and a
-- stale nameplate number can't pick some other mob mid-fight.
local MAX_UNITS = 4
local function macroFor(mobs, namesOnly)
	local names = macroNames(mobs)
	if #names == 0 then return "" end
	local lines = { "/cleartarget" }
	if not namesOnly then
		for i = 1, math.min(MAX_UNITS, #mobs) do
			local u = mobs[i].unit
			lines[#lines + 1] = ("/target [@%s,exists,nodead,harm] %s"):format(u, u)
		end
	end
	for _, name in ipairs(names) do
		for _ = 1, 2 do
			lines[#lines + 1] = "/target [noexists] " .. name
			lines[#lines + 1] = "/cleartarget [dead]"
		end
	end
	return table.concat(lines, "\n")
end

local lastMacro
local function updateMacro(mobs, namesOnly)
	if InCombatLockdown() then return end
	local down = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
	targetButton:RegisterForClicks(down and "AnyDown" or "AnyUp")
	local text = on() and macroFor(mobs, namesOnly) or ""
	if text ~= lastMacro then
		targetButton:SetAttribute("macrotext", text)
		lastMacro = text
	end
end

---------------------------------------------------------------------------
-- Updates
---------------------------------------------------------------------------
local function refresh()
	local mobs = {}
	if on() and not UnitIsDeadOrGhost("player") then mobs = scan() end
	current = mobs
	updateGlows(mobs)
	updateBox(mobs)
	updateMacro(mobs)
end

local pending = false
local function refreshSoon()
	if pending then return end
	pending = true
	C_Timer.After(0.1, function() pending = false refresh() end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, unit)
	if event == "PLAYER_LOGIN" then
		if not (QuestieLoader and QuestieLoader.ImportModule) then return end
		local ok, mod = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieTooltips")
		TT = ok and mod or nil
		if not TT then return end
		local ok2, db2 = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
		DB = ok2 and db2 or nil
		local ok3, zdb = pcall(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
		ZDB = ok3 and zdb or nil
		placeBox()
		for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "QUEST_LOG_UPDATE",
			"UNIT_QUEST_LOG_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_TARGET_CHANGED" }) do
			pcall(ev.RegisterEvent, ev, e)
		end
		C_Timer.NewTicker(0.5, refresh) -- deaths, tags and progress between events
		-- Questie fills in its data some seconds after login: don't trust
		-- "not a quest mob" answers for long.
		C_Timer.NewTicker(5, forgetQuests)
		refreshSoon()
		return
	end
	if event == "PLAYER_REGEN_DISABLED" then
		-- Combat is starting: the last moment the macro can change. Names
		-- only, so a stale nameplate number can't pick another mob mid-fight.
		updateMacro(current, true)
		return
	end
	if event == "QUEST_LOG_UPDATE" or event == "UNIT_QUEST_LOG_CHANGED" then
		forgetQuests()
		-- Questie updates its own data a moment later: check again then.
		C_Timer.After(1, function() forgetQuests() refreshSoon() end)
	end
	refreshSoon()
end)

ns.OnFeatureChanged(function(key) if key == "questMobs" then refresh() end end)

-- /zyde mobsdebug: every nameplate near you and why it does or doesn't count.
local function debug()
	local p = "|cff66ccffZyde_Forever|r: "
	print(p .. "quest mobs: feature " .. (ns.F("questMobs") and "on" or ("off" .. (ns.featureBlocked("questMobs")
		and (" (" .. ns.featureBlocked("questMobs") .. ")") or ""))) .. ", Questie data " .. (TT and "found" or "NOT found"))
	forgetQuests()
	local units = plateUnits()
	if #units == 0 then print(p .. "  no nameplates near you (are enemy nameplates on?)") end
	for _, unit in ipairs(units) do
		local raw = UnitName(unit)
		local shown = ns.isSecret(raw) and "<hidden name>" or tostring(raw)
		local ok, why = check(unit)
		print(("%s  %s (%s): %s"):format(p, shown, unit, ok and ("QUEST MOB as \"" .. why .. "\"") or why))
	end
	local area, px = playerZone()
	print(p .. "zone (Questie area) " .. tostring(area) .. (px and "" or ", your map position unknown"))
	zoneListAt = 0
	local zone = zoneCandidates()
	print(p .. #zone .. " quest mob kinds spawn in this zone" .. (#zone > 0 and ", nearest first:" or ""))
	for i = 1, math.min(8, #zone) do print(p .. "    " .. zone[i].name) end
	local text = targetButton:GetAttribute("macrotext") or ""
	print(p .. "target key macro: " .. (text == "" and "(empty)" or text:gsub("\n", " | ")))
end

ns.QuestMobs = {
	Debug = debug,
	ResetPosition = function()
		db().questMobsPos = nil
		placeBox()
		print("|cff66ccffZyde_Forever|r: quest mob count back at its default spot")
	end,
}
