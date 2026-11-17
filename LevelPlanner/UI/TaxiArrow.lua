-- TaxiArrow: when the next step is a flight, a bouncing green arrow on the flight master's map
-- points at the flight path to pick.
-- Game facts used (this client): the classic TaxiFrame has one
-- button per node, TaxiButton<slot>, with TaxiNodeName(slot); the newer FlightMapFrame keeps its
-- nodes as pins in pinPools.FlightMap_FlightPointPinTemplate, each with taxiNodeData.name.
local ADDON, zyde = ...
zyde.LP = zyde.LP or {}
local ns = zyde.LP

local A = {}
ns.TaxiArrow = A

local ARROW = "Interface\\Buttons\\UI-MicroStream-Green" -- the game's green "look here" arrow (points down)
local marker

-- The flight path the plan says to fly to now: a flight among the first steps, before any stop
-- that isn't travel (walking to the flight master or through a zone border comes first).
function A.Destination()
	local stops = ns.plan and ns.plan.stops
	for i = 1, math.min(4, stops and #stops or 0) do
		local s = stops[i]
		if s.kind ~= "travel" then return nil end
		if s.mode == "fly" then return s.to end
		if s.mode == "hearth" then return nil end
	end
	return nil
end

local function build()
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetSize(36, 36)
	f:SetFrameStrata("DIALOG")
	f:SetFrameLevel(200)
	local arrow = f:CreateTexture(nil, "OVERLAY")
	arrow:SetAllPoints()
	if arrow:SetTexture(ARROW) == false then
		-- no such file on this client: the bags' green upgrade arrow, turned to point down
		arrow:SetAtlas("bags-greenarrow")
		arrow:SetRotation(math.pi)
	end
	-- a soft bounce, so it catches the eye
	local ag = f:CreateAnimationGroup()
	ag:SetLooping("BOUNCE")
	local move = ag:CreateAnimation("Translation")
	move:SetOffset(0, 8)
	move:SetDuration(0.45)
	move:SetSmoothing("IN_OUT")
	f.bounce = ag
	f:Hide()
	return f
end

local function pointAt(target)
	marker = marker or build()
	marker:SetParent(target:GetParent() or UIParent)
	marker:SetFrameStrata("DIALOG")
	marker:ClearAllPoints()
	marker:SetPoint("BOTTOM", target, "TOP", 0, -2)
	marker:Show()
	marker.bounce:Play()
end

function A.Hide()
	if marker then
		marker.bounce:Stop()
		marker:Hide()
	end
end

local function sameName(a, b)
	return a and b and (a == b or a:find(b, 1, true) == 1 or b:find(a, 1, true) == 1)
end

-- The button or pin for `name` on whichever flight map is open.
local function findTarget(name)
	if TaxiFrame and TaxiFrame:IsShown() and NumTaxiNodes then
		for i = 1, (NumTaxiNodes() or 0) do
			local b = _G["TaxiButton" .. i]
			if b and b:IsShown() and sameName(TaxiNodeName(i), name) and TaxiNodeGetType(i) == "REACHABLE" then
				return b
			end
		end
	end
	if FlightMapFrame and FlightMapFrame:IsShown() and FlightMapFrame.pinPools then
		local pool = FlightMapFrame.pinPools.FlightMap_FlightPointPinTemplate
		if pool then
			for pin in pool:EnumerateActive() do
				if pin.taxiNodeData and sameName(pin.taxiNodeData.name, name) then return pin end
			end
		end
	end
	return nil
end

local function update(tries)
	A.Hide()
	local name = A.Destination()
	if not name then return end
	local target = findTarget(name)
	if target then
		pointAt(target)
	elseif tries > 0 then
		-- the map fills in its buttons a moment after it opens
		C_Timer.After(0.2, function() ns.safe(update, tries - 1) end)
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("TAXIMAP_OPENED")
f:RegisterEvent("TAXIMAP_CLOSED")
f:SetScript("OnEvent", function(_, event)
	if event == "TAXIMAP_CLOSED" then A.Hide() return end
	C_Timer.After(0.1, function() ns.safe(update, 10) end)
end)
