-- Zyde_Forever: hunters' tracking picks itself (option "Auto tracking", hunters).
-- Every couple of seconds it looks at the enemies around you and turns on the tracking for the
-- kind there's most of: Track Beasts, Humanoids, Undead, Demons, Elementals, Giants or Dragonkin
-- (only the ones you know). What counts most:
--   * your target, if it's an enemy (x3)
--   * mobs your quests need (x3, from the quest mob scan)
--   * every other living enemy with a nameplate (x1)
-- Kinds you saw in the last 30 seconds still count (fading), so it doesn't flip when mobs walk
-- off screen. It only switches when the new kind clearly leads, out of combat, at most every
-- 10 seconds. It leaves things alone when:
--   * you just picked a tracking yourself (for 2 minutes)
--   * Find Herbs, Find Minerals or Find Treasure is on (your gathering comes first)
-- /zyde trackdebug shows what it sees.

local ADDON, ns = ...
local _, playerClass = UnitClass("player")
if playerClass ~= "HUNTER" then return end

local isSecret, safe = ns.isSecret, ns.safe
local function plain(v) if isSecret(v) then return nil end return v end
local function on() return ns.F("autoTrack") end

-- creature type (UnitCreatureType) -> the hunter tracking for it
local TRACK_FOR = {
	Beast = "Track Beasts", Humanoid = "Track Humanoids", Undead = "Track Undead", Demon = "Track Demons",
	Elemental = "Track Elementals", Giant = "Track Giants", Dragonkin = "Track Dragonkin",
}
local CREATURE_TRACKING = {}
for _, v in pairs(TRACK_FOR) do CREATURE_TRACKING[v] = true end
local GATHERING = { ["Find Herbs"] = true, ["Find Minerals"] = true, ["Find Treasure"] = true, ["Find Fish"] = true }

local MEMORY = 30        -- seconds a kind you saw keeps counting (fading out)
local MIN_GAP = 10       -- seconds between switches
local LEAD = 1.5         -- the new kind needs this many times the current one's count
local HANDS_OFF = 120    -- seconds after you pick a tracking yourself

local count, info, set
if C_Minimap and C_Minimap.GetNumTrackingTypes then
	count, info, set = C_Minimap.GetNumTrackingTypes, C_Minimap.GetTrackingInfo, C_Minimap.SetTracking
elseif GetNumTrackingTypes then
	count, info, set = GetNumTrackingTypes, GetTrackingInfo, SetTracking
end

-- The tracking list: { [name] = { index, active } }, and the active ones.
local function trackings()
	local list, active = {}, {}
	local n = count and plain(safe(count)) or 0
	for i = 1, n do
		local a, _, act = safe(info, i)
		local name, isOn
		if type(a) == "table" then name, isOn = plain(a.name), plain(a.active) else name, isOn = plain(a), plain(act) end
		if type(name) == "string" then
			list[name] = { index = i, active = isOn == true }
			if isOn == true then active[#active + 1] = name end
		end
	end
	return list, active
end

---------------------------------------------------------------------------
-- What's around: a fading tally of creature types
---------------------------------------------------------------------------
local seen = {} -- [mob GUID] = { kind, weight, at }

local function note(unit, weight)
	if plain(UnitExists(unit)) ~= true then return end
	if plain(UnitCanAttack("player", unit)) ~= true or plain(UnitIsDead(unit)) == true then return end
	if plain(UnitIsPlayer(unit)) == true then return end
	local kind = plain(UnitCreatureType(unit))
	local guid = plain(UnitGUID(unit))
	if not (kind and TRACK_FOR[kind] and guid) then return end
	-- (a mob keeps its highest weight while it's still around: a quest mob stays x3 after you
	-- untarget it)
	local old, now = seen[guid], GetTime()
	local w = weight
	if old and now - old.at < 5 and old.weight > w then w = old.weight end
	seen[guid] = { kind = kind, weight = w, at = now }
end

local function tally()
	local now, totals = GetTime(), {}
	for guid, s in pairs(seen) do
		local age = now - s.at
		if age > MEMORY then seen[guid] = nil
		else totals[s.kind] = (totals[s.kind] or 0) + s.weight * (1 - age / MEMORY * 0.7) end
	end
	return totals
end

local function look()
	local quest = {}
	if ns.QuestMobs and ns.QuestMobs.Current then
		for _, m in ipairs(ns.QuestMobs.Current() or {}) do if m.unit then quest[m.unit] = true end end
	end
	for _, unit in ipairs(ns.Plates and ns.Plates.units() or {}) do note(unit, quest[unit] and 3 or 1) end
	note("target", 3)
	note("mouseover", 1)
end

---------------------------------------------------------------------------
-- Switching
---------------------------------------------------------------------------
local lastSwitch, ourChangeAt, handsOffUntil = 0, 0, 0
local lastWhy = "not checked yet"

local function decide()
	look()
	local totals = tally()
	local list, active = trackings()
	for _, name in ipairs(active) do
		if GATHERING[name] then return nil, name .. " is on (gathering comes first)" end
	end
	local current
	for _, name in ipairs(active) do if CREATURE_TRACKING[name] then current = name end end
	local best, bestN, currentN = nil, 0, 0
	for kind, n in pairs(totals) do
		local tr = TRACK_FOR[kind]
		if list[tr] then
			if n > bestN then best, bestN = tr, n end
			if tr == current then currentN = n end
		end
	end
	if not best then return nil, "no enemies of a kind you can track nearby" end
	if best == current then return nil, best .. " already on" end
	if current and bestN < currentN * LEAD then
		return nil, ("%s leads (%.1f) but not clearly over %s (%.1f)"):format(best, bestN, current, currentN)
	end
	return best, ("%s: %.1f%s"):format(best, bestN, current and (" vs " .. current .. " " .. ("%.1f"):format(currentN)) or "")
end

local function tick()
	if not on() or not set then return end
	look()
	local now = GetTime()
	if InCombatLockdown() then lastWhy = "in a fight (switches after)" return end
	if now < handsOffUntil then lastWhy = ("you picked a tracking yourself: hands off for %ds"):format(handsOffUntil - now) return end
	if plain(UnitIsDeadOrGhost("player")) or plain(UnitOnTaxi("player")) then return end
	if now - lastSwitch < MIN_GAP then return end
	local want, why = decide()
	lastWhy = why
	if not want then return end
	local list = trackings()
	local entry = list[want]
	if not entry then return end
	ourChangeAt, lastSwitch = now, now
	safe(set, entry.index, true)
end

C_Timer.NewTicker(2, function() pcall(tick) end)

-- You changing tracking yourself (not us, and not dying, which clears it): hands off for a while.
local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "MINIMAP_UPDATE_TRACKING")
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")
pcall(ev.RegisterEvent, ev, "PLAYER_ALIVE")
pcall(ev.RegisterEvent, ev, "PLAYER_UNGHOST")
local loadedAt, aliveAt = GetTime(), 0
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" then lastSwitch = 0 return end
	if event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then aliveAt = GetTime() return end
	local now = GetTime()
	if now - ourChangeAt < 3 or now - loadedAt < 15 then return end -- (ours, or the game setting up)
	-- (dying clears tracking a moment before you count as dead, and "Keep tracking after death"
	-- turns it back on: neither is you choosing)
	C_Timer.After(1.5, function()
		if plain(UnitIsDeadOrGhost("player")) then return end
		if now - aliveAt < 10 then return end
		handsOffUntil = now + HANDS_OFF
	end)
end)

ns.OnFeatureChanged(function(key) if key == "autoTrack" then handsOffUntil = 0 lastSwitch = 0 end end)

-- /zyde trackdebug
function ns.TrackDebug()
	local P = "|cff66ccffZyde_Forever|r tracking: "
	look()
	local totals, parts = tally(), {}
	for kind, n in pairs(totals) do parts[#parts + 1] = ("%s %.1f"):format(kind, n) end
	table.sort(parts)
	local list, active = trackings()
	local known = {}
	for name in pairs(list) do if CREATURE_TRACKING[name] then known[#known + 1] = name end end
	table.sort(known)
	print(P .. "feature " .. (on() and "on" or "off") .. "; on now: " .. (#active > 0 and table.concat(active, ", ") or "nothing"))
	print(P .. "you know: " .. (#known > 0 and table.concat(known, ", ") or "no creature tracking"))
	print(P .. "around you: " .. (#parts > 0 and table.concat(parts, ", ") or "no enemies seen in the last 30 s"))
	local want, why = decide()
	print(P .. "would pick: " .. tostring(want or "-") .. " (" .. tostring(why) .. "); last check: " .. lastWhy)
end
