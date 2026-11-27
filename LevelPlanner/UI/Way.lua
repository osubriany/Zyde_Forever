-- Way: "/way 45.2 61.8" puts your own waypoint first in the step list. LevelPlanner routes you there
-- (flights, boats, passes - like "..." > Travel), with the arrow and map pins, until you arrive.
--   /way 45.2 61.8              x y in the zone you're in (commas are fine: /way 45.2, 61.8)
--   /way Duskwood 45.2 61.8     in another zone (or #mapID, as TomTom writes it)
--   /way 45.2 61.8 Old mill     anything after the coordinates names the waypoint
--   /way clear                  remove it (or right-click its step)
-- /way is only taken when no other addon (TomTom) has it; /lp way always works.
local ADDON, zyde = ...
zyde.LP = zyde.LP or {}
local ns = zyde.LP

local Way = {}
ns.Way = Way

local USAGE = "/way x y [name], /way <zone> x y [name], or /way clear - e.g. /way 45.2, 61.8"

local function key(name)
	return (name or ""):lower():gsub("^the ", ""):gsub("[^%w]", "")
end

local function num(t)
	if not t or t:sub(1, 1) == "#" then return nil end
	return tonumber(t)
end

-- Splits what you typed into zone text, x, y and name (the raw text of each).
-- Returns nil when there are no coordinates.
function Way.Parse(text)
	local toks = {}
	for t in ((text or ""):gsub(",", " ")):gmatch("%S+") do toks[#toks + 1] = t end
	for i = 1, #toks - 1 do
		local x, y = num(toks[i]), num(toks[i + 1])
		if x and y then
			return {
				zone = table.concat(toks, " ", 1, i - 1),
				x = x, y = y, xText = toks[i], yText = toks[i + 1],
				name = table.concat(toks, " ", i + 2),
			}
		end
	end
	return nil
end

-- A zone or city by (part of) its name, or "#1429": uiMapID and its name.
function Way.FindZone(text)
	local id = text:match("^#(%d+)$")
	if id then
		local info = C_Map.GetMapInfo(tonumber(id))
		return info and tonumber(id), info and info.name
	end
	local want = key(text)
	if want == "" then return nil end
	local lists = { ns.TravelTo.Cities(), ns.TravelTo.Zones() }
	for _, list in ipairs(lists) do
		for _, z in ipairs(list) do if key(z.name) == want then return z.map, z.name end end
	end
	for _, list in ipairs(lists) do
		for _, z in ipairs(list) do if key(z.name):find(want, 1, true) then return z.map, z.name end end
	end
	return nil
end

local function isMine(dest) return dest and dest.kind == "point" end

function Way.Run(msg)
	if not ns.active then
		ns.print("the level planner is off - turn on \"Level planner\" in /zyde to use /way.")
		return
	end
	local raw = (msg or ""):match("^%s*(.-)%s*$")
	local low = raw:lower()
	if low == "clear" or low == "reset" or low == "stop" or low == "off" then
		if isMine(ns.TravelTo.Current()) then
			ns.TravelTo.Clear()
			ns.print("Waypoint: removed.")
		else
			ns.print("Waypoint: there isn't one.")
		end
		return
	end
	local w = Way.Parse(raw)
	if not w then ns.print(USAGE) return end
	if w.x < 0 or w.x > 100 or w.y < 0 or w.y > 100 then
		ns.print("Waypoint: coordinates go from 0 to 100. " .. USAGE)
		return
	end
	local map, zoneName
	if w.zone ~= "" then
		map, zoneName = Way.FindZone(w.zone)
		if not map then ns.print('Waypoint: no zone called "' .. w.zone .. '". ' .. USAGE) return end
	else
		map = C_Map.GetBestMapForUnit("player")
		if not map then ns.print("Waypoint: can't tell which zone you're in - add the zone: /way <zone> x y") return end
	end
	local name = w.name ~= "" and w.name
		or (w.xText .. ", " .. w.yText .. (zoneName and (" (" .. zoneName .. ")") or ""))
	if not ns.TravelTo.SetPoint(map, w.x, w.y, name) then
		ns.print("Waypoint: that map has no coordinates the planner can use (an instance?). " .. USAGE)
	end
end

-- /way, unless another addon has it already (checked at login, when every addon has loaded).
local function taken()
	for cmd in pairs(SlashCmdList) do
		for i = 1, 9 do
			local v = _G["SLASH_" .. cmd .. i]
			if v == nil then break end
			if type(v) == "string" and v:lower() == "/way" then return true end
		end
	end
	return false
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
	if ns.cfg and ns.cfg.wayCommand == false then return end
	if taken() then return end
	SLASH_LEVELPLANNERWAY1 = "/way"
	SlashCmdList.LEVELPLANNERWAY = Way.Run
end)
