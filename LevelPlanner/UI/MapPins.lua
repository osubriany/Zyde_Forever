-- MapPins: numbered pins for the next few steps on the world map and minimap, joined by a dotted
-- trail on the world map. Uses HereBeDragons-Pins, which Questie loads (called, not copied).
local ADDON, zyde = ...
-- Part of Zyde_Forever since 2026-11-14: LevelPlanner keeps its own private table (zyde.LP) so its
-- names never clash with Zyde's.
zyde.LP = zyde.LP or {}
local ns = zyde.LP

local M = {}
ns.MapPins = M

local REF = "LevelPlanner"
local HBDP
local worldPins, miniPins, dots = {}, {}, {}
local DOT_STEP = 0.015   -- one trail dot per 1.5% of the map
local MAX_DOTS = 40       -- per leg

-- Questie's pin library: a Questie module since Questie 12.9, a LibStub library before that.
local function pins()
	if HBDP == nil then
		local m = QuestieLoader and ns.safe(QuestieLoader.ImportModule, QuestieLoader, "HBDPins")
		-- (the loader hands back an empty table for a module that does not exist)
		if not (m and m.AddWorldMapIconMap) then m = LibStub and LibStub("HereBeDragonsQuestie-Pins-2.0", true) end
		HBDP = (m and m.AddWorldMapIconMap) and m or false
	end
	return HBDP or nil
end

local PIN = "Interface\\AddOns\\Zyde_Forever\\LevelPlanner\\Media\\Pin"
local DOT = "Interface\\AddOns\\Zyde_Forever\\LevelPlanner\\Media\\Dot"
local RING_NOW = { 0.35, 1, 0.55 }   -- next step: green
local RING_LATER = { 1, 0.82, 0.25 } -- later steps: gold

-- Dark disc with a coloured ring and a white, outlined number: readable on light and dark maps.
local function numberPin(pool, i, size)
	local f = pool[i]
	if not f then
		f = CreateFrame("Frame", nil, UIParent)
		f:SetSize(size, size)
		local tex = f:CreateTexture(nil, "ARTWORK")
		tex:SetAllPoints()
		tex:SetTexture(PIN)
		f.tex = tex
		local fs = f:CreateFontString(nil, "OVERLAY")
		fs:SetFont(STANDARD_TEXT_FONT, math.floor(size * 0.55), "OUTLINE")
		fs:SetPoint("CENTER", 0, 0)
		fs:SetTextColor(1, 1, 1)
		f.text = fs
		f:EnableMouse(true)
		f:SetScript("OnEnter", function(self)
			if not self.label then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine("LevelPlanner - step " .. (self.index or "?"))
			GameTooltip:AddLine(self.label, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		f:SetScript("OnLeave", function() GameTooltip:Hide() end)
		pool[i] = f
	end
	return f
end

local function dot(i)
	local f = dots[i]
	if not f then
		f = CreateFrame("Frame", nil, UIParent)
		f:SetSize(9, 9)
		local tex = f:CreateTexture(nil, "ARTWORK")
		tex:SetAllPoints()
		tex:SetTexture(DOT)
		tex:SetVertexColor(RING_LATER[1], RING_LATER[2], RING_LATER[3])
		tex:SetAlpha(0.9)
		dots[i] = f
	end
	return f
end

function M.Clear()
	local P = pins()
	if not P then return end
	P:RemoveAllWorldMapIcons(REF)
	P:RemoveAllMinimapIcons(REF)
end

-- The next steps with a place, one per location (several turn-ins at one NPC = one pin).
local function placesOf(plan, max)
	local out = {}
	for _, s in ipairs(plan and plan.stops or {}) do
		local p = s.point
		if p and p.map and p.x and p.y then
			local last = out[#out]
			local d = last and ns.Geo.Distance(last.point, p)
			if last and d and d < 40 then
				last.label = last.label .. "\n" .. (s.label or "")
			else
				out[#out + 1] = { point = p, label = s.label or s.questName or "" }
				if #out >= max then break end
			end
		end
	end
	return out
end

function M.Update(plan)
	local P = pins()
	if not P then return end
	M.Clear()
	local cfg = ns.cfg
	if cfg.mapPins == false then return end
	local places = placesOf(plan, cfg.mapPinSteps or 5)
	local showContinent = HBD_PINS_WORLDMAP_SHOW_CONTINENT or 2

	local nDots = 0
	for i, pl in ipairs(places) do
		local p = pl.point
		local ring = (i == 1) and RING_NOW or RING_LATER
		local w = numberPin(worldPins, i, 24)
		w.index, w.label = i, pl.label
		w.text:SetText(i)
		w.tex:SetVertexColor(ring[1], ring[2], ring[3])
		ns.safe(P.AddWorldMapIconMap, P, REF, w, p.map, p.x / 100, p.y / 100, showContinent)

		if cfg.minimapPins ~= false then
			local m = numberPin(miniPins, i, i == 1 and 20 or 16)
			m.index, m.label = i, pl.label
			m.text:SetText(i)
			m.tex:SetVertexColor(ring[1], ring[2], ring[3])
			-- only the next step stays on the minimap edge when it's out of range
			ns.safe(P.AddMinimapIconMap, P, REF, m, p.map, p.x / 100, p.y / 100, true, i == 1)
		end

		-- trail to the next pin, when both are on the same map
		local nxt = places[i + 1]
		if nxt and nxt.point.map == p.map then
			local x1, y1, x2, y2 = p.x / 100, p.y / 100, nxt.point.x / 100, nxt.point.y / 100
			local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
			local count = math.min(MAX_DOTS, math.floor(len / DOT_STEP))
			-- leave a gap next to each pin so dots never cover the numbers
			for k = 2, count - 2 do
				local t = k / count
				nDots = nDots + 1
				ns.safe(P.AddWorldMapIconMap, P, REF, dot(nDots), p.map, x1 + (x2 - x1) * t, y1 + (y2 - y1) * t, showContinent)
			end
		end
	end
end
