-- Zyde_Forever: Rare announcer.
-- When a rare (or rare elite) mob shows up, its name flashes in the middle of
-- the screen, a line goes to chat and a sound plays. Each rare is announced
-- once, then again only after 5 minutes.
-- Rares are spotted from enemy nameplates, your target, your mouseover, and
-- the game's minimap markers for rares where the client has them.
-- Rares seen in the last 3 minutes (and not seen dead) also go to the front of
-- the "Target nearest quest mob" key (QuestMobs.lua).

local ADDON, ns = ...

local P = "|cff66ccffZyde_Forever|r: "
local ANNOUNCE_AGAIN = 300 -- seconds before the same rare is announced again
local KEEP = 180           -- seconds a seen rare stays in the target key

local function on() return ns.F("rares") end
local function plain(v) if v == nil or ns.isSecret(v) then return nil end return v end

local seen = {}      -- name -> { name, at, guid }
local announced = {} -- guid or name -> when

local function rareKind(unit)
	local c = plain(UnitClassification(unit))
	if c == "rare" then return "Rare" end
	if c == "rareelite" then return "Rare elite" end
	return nil
end

local function announce(name, kind, level)
	local text = ("%s spotted: %s%s"):format(kind, name, level and level > 0 and (" (level " .. level .. ")") or "")
	if RaidNotice_AddMessage and RaidWarningFrame then
		pcall(RaidNotice_AddMessage, RaidWarningFrame, text, ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.5, b = 0 })
	end
	print(P .. "|cffff9933" .. text .. "|r")
	pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
end

local function note(name, kind, level, guid)
	local key = guid or name
	local now = GetTime()
	local isNew = not seen[name]
	seen[name] = { name = name, at = now, guid = guid }
	if not announced[key] or now - announced[key] > ANNOUNCE_AGAIN then
		announced[key] = now
		announce(name, kind, level)
	end
	-- A new rare: let the target key know now (it also rebuilds every half second).
	if isNew and ns.QuestMobsRefresh then ns.QuestMobsRefresh() end
end

-- A unit on screen: is it a living, attackable rare?
local function check(unit)
	if not on() or not UnitExists(unit) then return end
	local kind = rareKind(unit)
	if not kind then return end
	local name = plain(UnitName(unit))
	if type(name) ~= "string" or name == "" then return end
	if plain(UnitIsDead(unit)) then seen[name] = nil return end -- killed: out of the target key
	if plain(UnitIsFriend("player", unit)) then return end
	note(name, kind, plain(UnitLevel(unit)), plain(UnitGUID(unit)))
end

-- The minimap's rare markers ("vignettes"), where the client has them.
local function checkVignettes()
	if not on() or not (C_VignetteInfo and C_VignetteInfo.GetVignettes) then return end
	for _, id in ipairs(ns.safe(C_VignetteInfo.GetVignettes) or {}) do
		local v = ns.safe(C_VignetteInfo.GetVignetteInfo, id)
		local guid = v and plain(v.objectGUID)
		local atlas = v and plain(v.atlasName)
		local name = v and plain(v.name)
		if type(guid) == "string" and guid:find("^Creature") and type(name) == "string" and name ~= ""
			and type(atlas) == "string" and (atlas:lower():find("kill") or atlas:lower():find("rare")) then
			note(name, "Rare", nil, guid)
		end
	end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
	"VIGNETTE_MINIMAP_UPDATED", "VIGNETTES_UPDATED", "UNIT_HEALTH" }) do
	pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, unit)
	if event == "NAME_PLATE_UNIT_ADDED" then check(unit)
	elseif event == "PLAYER_TARGET_CHANGED" then check("target")
	elseif event == "UPDATE_MOUSEOVER_UNIT" then check("mouseover")
	elseif event == "UNIT_HEALTH" then
		-- A rare we know of died: off the list.
		if type(unit) == "string" and unit:find("^nameplate") and next(seen) and rareKind(unit) then
			local name = plain(UnitName(unit))
			if name and seen[name] and plain(UnitIsDead(unit)) then seen[name] = nil end
		end
	else
		checkVignettes()
	end
end)

ns.Rares = {
	-- Names of rares seen lately and not seen dead, newest first (for the target key).
	names = function()
		local list, now = {}, GetTime()
		for name, s in pairs(seen) do
			if now - s.at > KEEP then seen[name] = nil else list[#list + 1] = s end
		end
		table.sort(list, function(a, b) return a.at > b.at end)
		for i, s in ipairs(list) do list[i] = s.name end
		return list
	end,
	-- Nameplate units that are living rares nobody else has tagged.
	units = function()
		local out = {}
		if not on() then return out end
		for _, unit in ipairs(ns.Plates.units()) do
			if rareKind(unit) and plain(UnitIsDead(unit)) ~= true and plain(UnitIsTapDenied(unit)) ~= true
				and plain(UnitCanAttack("player", unit)) ~= false then
				out[#out + 1] = unit
			end
		end
		return out
	end,
}
