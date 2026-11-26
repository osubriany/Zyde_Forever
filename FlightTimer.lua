-- Zyde_Forever: flight timer (option "Flight timer").
--   * On a flight: a panel near the middle of the screen with where you're going, the time left
--     and a progress bar. Drag it to move it (/zyde flighttimer reset puts it back).
--   * On the flight map: each destination's tooltip gets its flight time.
-- Times: your own flights first (each landing is remembered, per faction), else the published
-- table in FlightTimesData.lua. A flight in neither is timed as you go ("Timing this flight")
-- and known from then on.

local ADDON, ns = ...
local isSecret = ns.isSecret
local function plain(v) if isSecret(v) then return nil end return v end
local function on() return ns.F("flightTimer") end

local FLAT = "Interface\\Buttons\\WHITE8X8"
local FONT = "Fonts\\FRIZQT__.TTF"
local GOLD = { 1, 0.82, 0.2 }
local DEFAULT_POS = { point = "CENTER", x = 0, y = 170 }

local faction = UnitFactionGroup("player") or "Neutral"

local function db()
	ZydeForeverDB = ZydeForeverDB or {}
	local d = ZydeForeverDB
	d.flightLearned = d.flightLearned or {}
	d.flightLearned[faction] = d.flightLearned[faction] or {}
	return d
end

---------------------------------------------------------------------------
-- The table: published (Classic Era with Forever's changes on top), by node ID, plus a
-- short-name index for when the game doesn't give node IDs.
---------------------------------------------------------------------------
local published, idByName
local function shortName(name)
	if type(name) ~= "string" then return nil end
	local s = (name:match("^([^,]+)") or name):gsub("^%s+", ""):gsub("%s+$", "")
	return s
end

local function build()
	if published then return end
	published, idByName = {}, {}
	local data = ns.FlightTimeData or {}
	for _, era in ipairs({ data.classic or {}, data.forever or {} }) do
		local nodes = era[faction] or {}
		for from, dests in pairs(nodes) do
			published[from] = published[from] or {}
			for to, secs in pairs(dests) do
				if to == "name" then
					published[from].name = secs
					idByName[secs] = from
				else
					published[from][to] = secs
				end
			end
		end
	end
end

local function key(from, to) return tostring(from) .. ">" .. tostring(to) end

-- Seconds for a flight, and where the number came from ("yours" / "published"), or nil.
-- from/to: node IDs when known, else short names.
local function flightTime(from, to, fromName, toName)
	build()
	local learned = db().flightLearned[faction]
	local mine = learned[key(from, to)] or (fromName and toName and learned[key(fromName, toName)])
	if mine and mine.secs then return mine.secs, "yours" end
	local f = (type(from) == "number" and published[from]) or (fromName and published[idByName[fromName] or -1])
		or (fromName and published[fromName])
	if f then
		local t = (type(to) == "number" and f[to]) or (toName and f[idByName[toName] or -1]) or (toName and f[toName])
		if t then return t, "published" end
	end
	return nil
end

local function clock(secs)
	secs = math.max(0, math.floor(secs + 0.5))
	if secs >= 3600 then return ("%d:%02d:%02d"):format(secs / 3600, (secs % 3600) / 60, secs % 60) end
	return ("%d:%02d"):format(secs / 60, secs % 60)
end

---------------------------------------------------------------------------
-- The flight map: every slot's node ID and name, and where you are (read when it opens,
-- so the choice is known after the map closes).
---------------------------------------------------------------------------
local slots, here = {}, nil -- slots[slot] = { id, name, short }; here = the same for your node

local function readMap()
	wipe(slots)
	here = nil
	local n = plain(NumTaxiNodes and NumTaxiNodes()) or 0
	for i = 1, n do
		local name = plain(TaxiNodeName(i))
		slots[i] = { name = name, short = shortName(name) }
		if plain(TaxiNodeGetType(i)) == "CURRENT" then here = slots[i] end
	end
	-- node IDs, where the game has them
	local mapID = GetTaxiMapID and plain(GetTaxiMapID())
	local all = mapID and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and ns.safe(C_TaxiMap.GetAllTaxiNodes, mapID)
	if type(all) == "table" then
		for _, node in ipairs(all) do
			local s = node.slotIndex and slots[node.slotIndex]
			if s and type(node.nodeID) == "number" then s.id = node.nodeID end
		end
	end
	build()
	for _, s in pairs(slots) do
		if not s.id and s.short then s.id = idByName[s.short] end
	end
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------
local panel = CreateFrame("Frame", "ZydeForeverFlightTimer", UIParent, "BackdropTemplate")
panel:SetSize(280, 70)
panel:SetFrameStrata("HIGH")
panel:SetClampedToScreen(true)
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
panel:SetBackdropColor(0.05, 0.05, 0.06, 0.88)
panel:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.55)
panel:Hide()

-- a soft gold line along the top
local accent = panel:CreateTexture(nil, "ARTWORK")
accent:SetTexture(FLAT)
accent:SetPoint("TOPLEFT", 1, -1)
accent:SetPoint("TOPRIGHT", -1, -1)
accent:SetHeight(2)
accent:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.8)
if CreateColor then
	pcall(accent.SetGradient, accent, "HORIZONTAL", CreateColor(GOLD[1], GOLD[2], GOLD[3], 0.15), CreateColor(GOLD[1], GOLD[2], GOLD[3], 0.9))
end

local caption = panel:CreateFontString(nil, "OVERLAY")
caption:SetFont(FONT, 9, "")
caption:SetTextColor(0.6, 0.6, 0.62)
caption:SetPoint("TOPLEFT", 12, -10)
caption:SetText("FLYING TO")

local dest = panel:CreateFontString(nil, "OVERLAY")
dest:SetFont(FONT, 14, "")
dest:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
dest:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 0, -3)
dest:SetPoint("RIGHT", panel, "RIGHT", -84, 0)
dest:SetJustifyH("LEFT")
dest:SetWordWrap(false)

local timeText = panel:CreateFontString(nil, "OVERLAY")
timeText:SetFont(FONT, 24, "")
timeText:SetTextColor(1, 1, 1)
timeText:SetPoint("RIGHT", panel, "TOPRIGHT", -12, -26)
timeText:SetJustifyH("RIGHT")

local sub = panel:CreateFontString(nil, "OVERLAY")
sub:SetFont(FONT, 9, "")
sub:SetTextColor(0.55, 0.55, 0.57)
sub:SetPoint("TOPRIGHT", timeText, "BOTTOMRIGHT", 0, -1)
sub:SetJustifyH("RIGHT")

local barBg = panel:CreateTexture(nil, "ARTWORK")
barBg:SetTexture(FLAT)
barBg:SetVertexColor(1, 1, 1, 0.08)
barBg:SetPoint("BOTTOMLEFT", 12, 11)
barBg:SetPoint("BOTTOMRIGHT", -12, 11)
barBg:SetHeight(4)

local bar = CreateFrame("StatusBar", nil, panel)
bar:SetStatusBarTexture(FLAT)
bar:SetStatusBarColor(GOLD[1], GOLD[2], GOLD[3], 0.95)
bar:SetAllPoints(barBg)
bar:SetMinMaxValues(0, 1)

local spark = bar:CreateTexture(nil, "OVERLAY")
spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
spark:SetBlendMode("ADD")
spark:SetSize(12, 16)

local fadeIn = panel:CreateAnimationGroup()
local a = fadeIn:CreateAnimation("Alpha")
a:SetFromAlpha(0)
a:SetToAlpha(1)
a:SetDuration(0.35)

local function placePanel()
	local p = db().flightTimerPos or DEFAULT_POS
	panel:ClearAllPoints()
	panel:SetPoint(p.point, UIParent, p.point, p.x, p.y)
end
panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
panel:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local point, _, _, x, y = self:GetPoint()
	db().flightTimerPos = { point = point, x = x, y = y }
end)

---------------------------------------------------------------------------
-- The flight
---------------------------------------------------------------------------
local chosen      -- { from, to, fromName, toName, secs, source, at } from TakeTaxiNode
local flight      -- the same once you're in the air, with started = GetTime()
local landedAt

local function show()
	if not flight then return end
	dest:SetText(flight.toName or "your flight path")
	placePanel()
	if not panel:IsShown() or panel:GetAlpha() < 1 then panel:SetAlpha(1) panel:Show() fadeIn:Play() end
end

local function tick()
	if not flight then return end
	local gone = GetTime() - flight.started
	if flight.secs then
		local left = flight.secs - gone
		caption:SetText("FLYING TO")
		timeText:SetText(left > 0 and clock(left) or "0:00")
		sub:SetText(left > 0 and ("of " .. clock(flight.secs)) or "landing")
		local p = math.min(1, gone / math.max(1, flight.secs))
		bar:SetValue(p)
		bar:Show()
		spark:ClearAllPoints()
		spark:SetPoint("CENTER", bar, "LEFT", bar:GetWidth() * p, 0)
		spark:SetShown(p > 0 and p < 1)
	else
		caption:SetText("FLYING TO  ·  TIMING THIS FLIGHT")
		timeText:SetText(clock(gone))
		sub:SetText("first time: learning it")
		bar:Hide()
		spark:Hide()
	end
end

local function land()
	if not flight then return end
	local took = GetTime() - flight.started
	-- Remember it: a whole flight only (not cut short), and not wildly off the published time.
	if took > 15 and flight.to then
		local ok = not flight.secs or flight.source == "yours" or math.abs(took - flight.secs) < flight.secs * 0.35
		if ok then
			local learned = db().flightLearned[faction]
			local k = key(flight.from or flight.fromName, flight.to)
			local e = learned[k] or { n = 0 }
			e.n = math.min(e.n + 1, 5)
			e.secs = e.secs and (e.secs + (took - e.secs) / e.n) or took -- (a running mean of the last few)
			e.secs = math.floor(e.secs + 0.5)
			learned[k] = e
		end
	end
	flight = nil
	landedAt = GetTime()
	caption:SetText("ARRIVED")
	timeText:SetText(clock(took))
	sub:SetText("flight time")
	bar:SetValue(1)
	spark:Hide()
	C_Timer.After(2.5, function()
		if flight then return end
		if UIFrameFadeOut then UIFrameFadeOut(panel, 0.4, panel:GetAlpha(), 0) end
		C_Timer.After(0.45, function() if not flight then panel:Hide() end end)
	end)
end

local function takeOff()
	if flight or not chosen or GetTime() - chosen.at > 15 then return end
	flight = chosen
	chosen = nil
	flight.started = GetTime()
	if on() then show() tick() end
end

-- You picked a destination.
hooksecurefunc("TakeTaxiNode", function(slot)
	if not next(slots) then readMap() end
	local s = slots[slot]
	if not s then return end
	local from = here and (here.id or here.short)
	local to = s.id or s.short
	local secs, source = flightTime(from, to, here and here.short, s.short)
	chosen = { from = from, to = to, fromName = here and here.short, toName = s.short, secs = secs, source = source, at = GetTime() }
end)

-- The flight map: add the time to each destination's tooltip.
local function tooltipFor(button)
	if not on() or not button or not GameTooltip:IsShown() then return end
	local slot = button.GetID and button:GetID()
	local s = slot and slots[slot]
	if not s or s == here or not here then return end
	local secs, source = flightTime(here.id or here.short, s.id or s.short, here.short, s.short)
	if secs then
		GameTooltip:AddLine(("Flight time: %s%s"):format(clock(secs), source == "yours" and " (your last flights)" or ""),
			GOLD[1], GOLD[2], GOLD[3])
	else
		GameTooltip:AddLine("Flight time: not known yet (timed on your first flight)", 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end
if type(TaxiNodeOnButtonEnter) == "function" then hooksecurefunc("TaxiNodeOnButtonEnter", tooltipFor) end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "TAXIMAP_OPENED", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PLAYER_ENTERING_WORLD" }) do
	pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
	if event == "TAXIMAP_OPENED" then
		readMap()
	elseif event == "PLAYER_CONTROL_LOST" then
		takeOff()
	elseif event == "PLAYER_CONTROL_GAINED" then
		if flight and not plain(UnitOnTaxi("player")) then land() end
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- (a reload mid-flight: nothing to count from, so no panel)
		if not plain(UnitOnTaxi("player")) then flight = nil panel:Hide() end
	end
end)

-- Backup for clients that don't send the control events, and the countdown itself.
local wait = 0
panel:SetScript("OnUpdate", function(_, dt)
	wait = wait + dt
	if wait < 0.2 then return end
	wait = 0
	if flight then tick() end
end)
local watcher = CreateFrame("Frame")
local wwait = 0
watcher:SetScript("OnUpdate", function(_, dt)
	wwait = wwait + dt
	if wwait < 0.25 then return end
	wwait = 0
	local onTaxi = plain(UnitOnTaxi("player"))
	if onTaxi and chosen and not flight then takeOff()
	elseif flight and onTaxi == false and GetTime() - flight.started > 3 then land() end
end)

ns.OnFeatureChanged(function(k)
	if k ~= "flightTimer" then return end
	if on() and flight then show() tick() elseif not on() then panel:Hide() end
end)

-- /zyde flighttimer: what it knows; "reset" puts the panel back in the middle.
function ns.FlightTimerCommand(arg)
	local P = "|cff66ccffZyde_Forever|r: "
	if arg == "reset" then
		db().flightTimerPos = nil
		placePanel()
		print(P .. "flight timer back in the middle of the screen")
		return
	end
	build()
	local routes, nodes = 0, 0
	for _, dests in pairs(published) do
		nodes = nodes + 1
		for k in pairs(dests) do if k ~= "name" then routes = routes + 1 end end
	end
	local mine = 0
	for _ in pairs(db().flightLearned[faction]) do mine = mine + 1 end
	print(P .. ("flight timer: %d published %s flight times from %d flight points, %d timed by you"):format(
		routes, faction, nodes, mine))
	if flight then
		print(P .. ("  flying %s -> %s: %s (%s)"):format(tostring(flight.fromName), tostring(flight.toName),
			flight.secs and clock(flight.secs) or "unknown", flight.source or "timing it"))
	end
end
