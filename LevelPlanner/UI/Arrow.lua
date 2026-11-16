-- Arrow: the built-in arrow to the next stop (used when TomTom is not installed).
-- Turns smoothly, shifts from green (straight ahead) to red (behind you), shows distance and
-- time to get there, and pulses when you arrive.
local ADDON, zyde = ...
-- Part of Zyde_Forever since 2026-11-14: LevelPlanner keeps its own private table (zyde.LP) so its
-- names never clash with Zyde's.
zyde.LP = zyde.LP or {}
local ns = zyde.LP

local A = {}
ns.Arrow = A

local TEXTURE = "Interface\\AddOns\\Zyde_Forever\\LevelPlanner\\Media\\Arrow"
local TURN_SPEED = 10      -- how quickly the arrow catches up with the real direction
local TEXT_EVERY = 0.2     -- seconds between distance/time updates

local frame, tex, label, distText, pulse
local target, targetTitle
local shown = 0            -- angle currently drawn
local textElapsed = 0
local arrived = false

local function savePos()
	local point, _, rel, x, y = frame:GetPoint()
	ns.char.arrowPos = { point, rel, x, y }
end

-- Wraps an angle to -pi..pi.
local function wrap(a)
	a = a % (2 * math.pi)
	if a > math.pi then a = a - 2 * math.pi end
	return a
end

-- Green when ahead, yellow to the side, red behind.
local function headingColour(rel)
	local t = math.abs(wrap(rel)) / math.pi
	return math.min(1, t * 2), math.min(1, (1 - t) * 2), 0.25
end

local function clock(sec)
	sec = math.floor(sec + 0.5)
	local h, m, s = math.floor(sec / 3600), math.floor((sec % 3600) / 60), sec % 60
	if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
	return string.format("%d:%02d", m, s)
end

function A.Init()
	frame = CreateFrame("Frame", "LevelPlannerArrow", UIParent)
	frame:SetSize(52, 52)
	local pos = ns.char and ns.char.arrowPos
	if pos then
		frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		frame:SetPoint("TOP", UIParent, "TOP", 0, -120)
	end
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() savePos() end)
	frame:SetClampedToScreen(true)

	tex = frame:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints()
	tex:SetTexture(TEXTURE)

	distText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	distText:SetPoint("TOP", frame, "BOTTOM", 0, -2)
	label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("TOP", distText, "BOTTOM", 0, -2)
	label:SetWidth(260)
	label:SetWordWrap(false)

	-- arrival pulse
	pulse = tex:CreateAnimationGroup()
	local function scaleStep(from, to, order)
		local s = pulse:CreateAnimation("Scale")
		if s.SetScaleFrom then
			s:SetScaleFrom(from, from)
			s:SetScaleTo(to, to)
		else
			s:SetScale(to / from, to / from) -- older interface: relative scale
		end
		s:SetDuration(0.25)
		s:SetOrder(order)
	end
	scaleStep(1, 1.35, 1)
	scaleStep(1.35, 1, 2)
	pulse:SetLooping("NONE")

	frame:SetScript("OnUpdate", function(_, dt)
		A.Turn(dt)
		textElapsed = textElapsed + dt
		if textElapsed >= TEXT_EVERY then
			textElapsed = 0
			A.Refresh()
		end
	end)
	frame:Hide()
end

-- Along your walked trails (Travel/Trails.lua): the arrow aims at a point a little way along the
-- trail instead of straight at the target; looked up again every 1.5 s as you move.
local steer, steerLen, steerAt = nil, nil, 0
local function updateSteer()
	if GetTime() - steerAt < 1.5 then return end
	steerAt = GetTime()
	steer, steerLen = nil, nil
	if not (target and ns.Trails) then return end
	local here = ns.Geo.PlayerPoint()
	if here then
		local ok, s, len = pcall(ns.Trails.Steer, here, target, ns.cfg.trailAheadYards or 40)
		if ok then steer, steerLen = s, len end
	end
end

function A.SetTarget(point, title)
	target, targetTitle = point, title
	steer, steerLen, steerAt = nil, nil, 0
	arrived = false
	if not frame then return end
	-- hidden with /lp arrow, and also whenever the step list is hidden (/lp hides both)
	if target and not (ns.char and (ns.char.arrowHidden or ns.char.listHidden)) then
		label:SetText(title or "")
		frame:Show()
		A.Refresh()
	else
		frame:Hide()
	end
end

-- Every frame: ease the drawn angle toward the real direction (the short way round).
function A.Turn(dt)
	if not target or arrived then return end
	local angle = ns.Geo.VectorTo(steer or target)
	local facing = GetPlayerFacing and GetPlayerFacing()
	if not angle or not facing or ns.isSecret(facing) then return end
	local want = wrap(angle - facing)
	shown = wrap(shown + wrap(want - shown) * math.min(1, dt * TURN_SPEED))
	tex:SetRotation(shown)
	tex:SetVertexColor(headingColour(shown))
end

-- A few times a second: distance, time to get there, arrival.
function A.Refresh()
	if not target then frame:Hide() return end
	local angle, dist = ns.Geo.VectorTo(target)
	if not dist then
		tex:SetRotation(0)
		tex:SetVertexColor(0.6, 0.6, 0.6)
		tex:SetAlpha(0.4)
		distText:SetText("other continent")
		return
	end
	if dist <= (ns.cfg.arrivedYards or 15) then
		if not arrived then
			arrived = true
			tex:SetRotation(0)
			tex:SetVertexColor(0.35, 1, 0.55)
			pulse:Play()
		end
		tex:SetAlpha(0.6)
		distText:SetText("|cff59ff8chere|r")
		return
	end
	arrived = false
	updateSteer()
	if steer and steerLen then dist = steerLen end -- (the way along the trail, not the straight line)
	local facing = GetPlayerFacing and GetPlayerFacing()
	tex:SetAlpha((facing and not ns.isSecret(facing)) and 1 or 0.4)
	-- time at your current speed, or your usual speed when standing still
	local speed = GetUnitSpeed and GetUnitSpeed("player") or 0
	if ns.isSecret(speed) or not speed or speed < 1 then speed = ns.Geo.Speed() end
	distText:SetText(string.format("%d yd  |cff999999·|r  %s", math.floor(dist + 0.5), clock(dist / speed)))
end

-- Show or hide again after the step list was shown or hidden.
function A.UpdateShown()
	A.SetTarget(target, targetTitle)
end

function A.Toggle()
	ns.char.arrowHidden = not ns.char.arrowHidden
	if ns.char.arrowHidden then
		frame:Hide()
		ns.print("arrow hidden.")
	else
		ns.print("arrow shown.")
		if ns.Waypoint and ns.Waypoint.UsingTomTom() then ns.print("TomTom is installed, so its arrow is used instead.") end
		A.SetTarget(target, targetTitle)
	end
end
