-- Zyde_Forever: Zygor's arrow target becomes an AzerothGPS route ("zygorRoute").
-- Zygor points in a straight line; AzerothGPS knows the roads, cliffs and caves.
-- Whenever Zygor's arrow moves to a new target, that target is handed to
-- AzerothGPS as a /way stop, so its map and turn-by-turn arrow show the real way.
--   * only routes Zyde made are replaced: a trip you planned in AzerothGPS
--     yourself is left alone until it's finished or cleared
--   * Zygor's own arrow is hidden while AzerothGPS has the route (/zyde gpsarrow
--     keeps it showing)
-- Nothing from AzerothGPS is copied here: it's only driven through its own
-- /way and /agps clear commands, as a player typing them would.

local ADDON, ns = ...

local PREFIX = "Zygor: "     -- route stops Zyde made are named "Zygor: <step>"
local MOVED = 0.004          -- a target this far away (map fraction, ~0.4%) counts as new
local TICK = 0.5

local function db() ZydeForeverDB = ZydeForeverDB or {} return ZydeForeverDB end
local function on() return ns.F("zygorRoute") and ns.addonOn("ZygorGuidesViewerForever") end
local function hideArrowWanted() return db().gpsShowZygorArrow ~= true end

local last = nil   -- { m, x, y, name } of the last target sent to AzerothGPS

---------------------------------------------------------------------------
-- Zygor's side
---------------------------------------------------------------------------
local function zygorTarget()
	local zgv = rawget(_G, "ZGV") or rawget(_G, "ZygorGuidesViewer")
	local p = zgv and zgv.Pointer
	local af = p and p.ArrowFrame
	local w = af and af.waypoint
	if type(w) ~= "table" then return nil end
	local m, x, y = tonumber(w.m), tonumber(w.x), tonumber(w.y)
	if not (m and x and y) or ns.isSecret(m) or ns.isSecret(x) or ns.isSecret(y) then return nil end
	if x <= 0 or x >= 1 or y <= 0 or y >= 1 then return nil end
	local title = w.GetTitle and ns.safe(w.GetTitle, w) or w.title
	if type(title) ~= "string" or ns.isSecret(title) then title = nil end
	if title then
		title = title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("[\r\n]+", " ")
		title = strtrim(title)
		if title == "" then title = nil end
	end
	return { m = m, x = x, y = y, name = PREFIX .. (title or "next step") }
end

local function arrowFrame() return rawget(_G, "ZygorGuidesViewerPointer_ArrowCtrl") end

-- Zygor's arrow fades out rather than being hidden: Zygor keeps running its
-- step checks on it, and they must keep working.
local arrowHidden = false
local function setZygorArrowHidden(hide)
	local f = arrowFrame()
	if not f then return end
	if hide and arrowHidden and f:GetAlpha() > 0 then f:SetAlpha(0) end -- (Zygor faded it back in)
	if hide == arrowHidden then return end
	arrowHidden = hide
	if hide then
		f.zydeMouse = f:IsMouseEnabled()
		f:SetAlpha(0)
		f:EnableMouse(false)
	else
		f:SetAlpha(1)
		if f.zydeMouse ~= nil then f:EnableMouse(f.zydeMouse) end
	end
end

---------------------------------------------------------------------------
-- AzerothGPS's side
---------------------------------------------------------------------------
local function gpsLoaded() return ns.addonOn("AzerothGPS") and type(rawget(_G, "AzerothGPS")) == "table" end

-- The route's stops as AzerothGPS saved them (it saves on every change), or nil
-- when they can't be read.
local function gpsStops()
	local saved = rawget(_G, "AzerothGPSDB")
	local chars = type(saved) == "table" and saved.chars
	if type(chars) ~= "table" then return nil end
	local name, surname = UnitName("player")
	if not name then return nil end
	if type(surname) == "string" and surname ~= "" then name = name .. " " .. surname end
	local rec = chars[(GetRealmName() or "?") .. "-" .. name]
	if type(rec) ~= "table" then return nil end
	return type(rec.stops) == "table" and rec.stops or {}
end

-- The route is empty or only has a stop Zyde put there.
local function routeIsOurs()
	local stops = gpsStops()
	if not stops then return true end -- can't tell: assume ours
	for _, s in ipairs(stops) do
		if type(s.name) ~= "string" or s.name:sub(1, #PREFIX) ~= PREFIX then return false end
	end
	return true
end

-- A Zyde stop is on AzerothGPS's route right now.
local function hasOurStop()
	local stops = gpsStops()
	if not stops then return last ~= nil end
	for _, s in ipairs(stops) do
		if type(s.name) == "string" and s.name:sub(1, #PREFIX) == PREFIX then return true end
	end
	return false
end

local function wayCommand()
	-- whoever owns /way: TomTom (AzerothGPS listens to it) or AzerothGPS itself
	for key, fn in pairs(SlashCmdList) do
		for i = 1, 9 do
			local cmd = rawget(_G, "SLASH_" .. key .. i)
			if not cmd then break end
			if type(cmd) == "string" and cmd:lower() == "/way" then return fn end
		end
	end
end

local function clearRoute()
	local fn = SlashCmdList and SlashCmdList.AZEROTHGPS
	if fn then pcall(fn, "clear") end
end

local function send(t)
	local way = wayCommand()
	if not way then return false end
	clearRoute()
	local ok = pcall(way, ("#%d %.2f %.2f %s"):format(t.m, t.x * 100, t.y * 100, t.name))
	return ok
end

local function same(a, b)
	return a and b and a.m == b.m and a.name == b.name
		and math.abs(a.x - b.x) < MOVED and math.abs(a.y - b.y) < MOVED
end

---------------------------------------------------------------------------
-- The loop
---------------------------------------------------------------------------
local function tick()
	if not (on() and gpsLoaded()) then
		setZygorArrowHidden(false)
		return
	end
	local t = zygorTarget()
	if t and not same(t, last) and routeIsOurs() then
		if send(t) then last = t end
	end
	-- (a short hop, under /zyde gpsmin's seconds: Zygor's own arrow leads; GPSArrow.lua decides)
	local shortHop = ns.GPSShortHop and ns.GPSShortHop()
	setZygorArrowHidden(hideArrowWanted() and t ~= nil and hasOurStop() and not shortHop)
end

local ticker
local function start()
	if ticker then return end
	ticker = C_Timer.NewTicker(TICK, function()
		local ok, err = pcall(tick)
		if not ok and ns.Debug then ns.Debug("zygorRoute: " .. tostring(err)) end
	end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function() C_Timer.After(3, start) end)

ns.OnFeatureChanged(function(key)
	if key ~= "zygorRoute" then return end
	if not ns.F("zygorRoute") then
		setZygorArrowHidden(false)
		if last and hasOurStop() and routeIsOurs() then clearRoute() end
		last = nil
	end
end)

ns.ZygorRoute = {
	-- /zyde gpsarrow: keep Zygor's own arrow showing too, or hide it again.
	ToggleZygorArrow = function()
		db().gpsShowZygorArrow = not db().gpsShowZygorArrow or nil
		print("|cff66ccffZyde_Forever|r: Zygor's arrow " ..
			(hideArrowWanted() and "hides while AzerothGPS shows the route" or "stays visible beside AzerothGPS"))
		if not hideArrowWanted() then setZygorArrowHidden(false) end
	end,
	-- /zyde gpsroute: send Zygor's target again now (e.g. after clearing the route by hand).
	Resend = function()
		last = nil
		local t = zygorTarget()
		if not t then print("|cff66ccffZyde_Forever|r: Zygor's arrow has no target right now") return end
		if not gpsLoaded() then print("|cff66ccffZyde_Forever|r: AzerothGPS isn't loaded") return end
		if send(t) then last = t end
	end,
}
