-- Zyde_Forever: a threat list for the tank role.
-- Shown in a party or raid while your role is Tank. One line per mob you
-- have threat on:
--   mob, your %, next person, their %, second person, their %
-- Only mobs the game will tell us about: nameplates, bosses, and your target.
-- Drag the title to move it. Turn it off in /zyde.

local ADDON, ns = ...

local isSecret, safe = ns.isSecret, ns.safe
local FONT = "Fonts\\ARIALN.TTF"

local function plain(v)
	if isSecret(v) or v == nil then return nil end
	return v
end

local function on() return ns.F("threatBox") end

local function font(fs, size)
	if not fs:SetFont(FONT, size, "OUTLINE") then fs:SetFontObject("GameFontNormalSmall") end
end

---------------------------------------------------------------------------
-- The box
---------------------------------------------------------------------------
local box = CreateFrame("Frame", "ZydeForeverThreat", UIParent)
box:SetSize(420, 44)
box:SetFrameStrata("MEDIUM")
box:SetClampedToScreen(true)
box:SetMovable(true)
box:Hide()

box.bg = box:CreateTexture(nil, "BACKGROUND")
box.bg:SetAllPoints()
box.bg:SetColorTexture(0.07, 0.07, 0.07, 0.92)
box.edges = ns.newEdges(box, "OVERLAY", 1)
ns.placeEdges(box.edges, box, -1, 1)
for _, t in ipairs(box.edges) do t:SetColorTexture(0, 0, 0, 0.95) end

local header = CreateFrame("Frame", nil, box)
header:SetPoint("TOPLEFT", 1, -1)
header:SetPoint("TOPRIGHT", -1, -1)
header:SetHeight(18)
header:EnableMouse(true)
header:RegisterForDrag("LeftButton")
header.bg = header:CreateTexture(nil, "BACKGROUND")
header.bg:SetAllPoints()
header.bg:SetColorTexture(0.14, 0.14, 0.16, 1)
header.title = header:CreateFontString(nil, "OVERLAY")
font(header.title, 12)
header.title:SetPoint("LEFT", 6, 0)
header.title:SetText("Threat")
header.title:SetTextColor(1, 0.84, 0.35)

local body = box:CreateFontString(nil, "OVERLAY")
font(body, 12)
body:SetPoint("TOPLEFT", 8, -22)
body:SetPoint("TOPRIGHT", -8, -22)
body:SetJustifyH("LEFT")
body:SetJustifyV("TOP")
body:SetTextColor(1, 0.92, 0.75)
body:SetSpacing(2)

local function place()
	box:ClearAllPoints()
	local p = ZydeForeverDB and ZydeForeverDB.threatPos
	if type(p) == "table" and p.point then
		box:SetPoint(p.point, UIParent, p.point, p.x or 0, p.y or 0)
	else
		box:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 24, -220)
	end
end

header:SetScript("OnDragStart", function()
	if InCombatLockdown() then return end
	box:StartMoving()
end)
header:SetScript("OnDragStop", function()
	box:StopMovingOrSizing()
	local point, _, _, x, y = box:GetPoint()
	ZydeForeverDB = ZydeForeverDB or {}
	ZydeForeverDB.threatPos = { point = point, x = x, y = y }
end)

---------------------------------------------------------------------------
-- Who and what to list
---------------------------------------------------------------------------
local function isTank()
	if not IsInGroup or not IsInGroup() then return false end
	if UnitGroupRolesAssigned then
		local role = safe(UnitGroupRolesAssigned, "player")
		if not isSecret(role) and role == "TANK" then return true end
	end
	if GetPartyAssignment and safe(GetPartyAssignment, "MAINTANK", "player") then return true end
	return false
end

local function groupUnits()
	local units = {}
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local u = "raid" .. i
			if not UnitIsUnit(u, "player") then units[#units + 1] = u end
		end
	else
		for i = 1, GetNumSubgroupMembers and GetNumSubgroupMembers() or (GetNumPartyMembers and GetNumPartyMembers() or 0) do
			units[#units + 1] = "party" .. i
		end
	end
	return units
end

-- nil: not on your threat table. "secret": the game hid the number.
-- A number 0-3: you are on the table (3 = it is securely on you).
local function myStatus(unit)
	if not UnitThreatSituation then return nil end
	local status = safe(UnitThreatSituation, "player", unit)
	if status == nil then return nil end
	if isSecret(status) then return "secret" end
	return status
end

-- Scaled percent: 100 means this person has the most threat on that mob.
-- Others are their threat as a percent of that leader.
local function scaledPct(unit, mob)
	if not UnitDetailedThreatSituation then return nil end
	local _, _, scaled = safe(UnitDetailedThreatSituation, unit, mob)
	if scaled == nil or isSecret(scaled) then return nil end
	return tonumber(scaled)
end

local function mobOk(unit)
	if not UnitExists(unit) then return false end
	local dead = UnitIsDead and safe(UnitIsDead, unit)
	if dead == true then return false end
	local player = UnitIsPlayer and safe(UnitIsPlayer, unit)
	if player == true then return false end
	local friend = safe(UnitIsFriend, "player", unit)
	if friend == true then return false end
	return true
end

local function csv(s)
	s = tostring(s or "")
	if s:find('[,"]') then return '"' .. s:gsub('"', '""') .. '"' end
	return s
end

local function pctText(n)
	if not n then return "" end
	return tostring(math.floor(n + 0.5))
end

local function lineFor(unit, others)
	local name = plain(UnitName(unit)) or "Mob"
	local mine = scaledPct("player", unit)
	local ranked = {}
	for _, u in ipairs(others) do
		if UnitExists(u) then
			local p = scaledPct(u, unit)
			if p and p > 0 then
				ranked[#ranked + 1] = { name = plain(UnitName(u)) or "?", pct = p }
			end
		end
	end
	table.sort(ranked, function(a, b) return a.pct > b.pct end)
	local first, second = ranked[1], ranked[2]
	-- Closest pull at the top: smallest gap between you and the next person.
	local gap = (mine and first) and (mine - first.pct) or 999
	local text = table.concat({
		csv(name), pctText(mine),
		first and csv(first.name) or "", first and pctText(first.pct) or "",
		second and csv(second.name) or "", second and pctText(second.pct) or "",
	}, ",")
	local r, g, b = 1, 0.92, 0.75
	if mine and first and first.pct > mine then r, g, b = 1, 0.35, 0.3
	elseif mine and first and (mine - first.pct) < 15 then r, g, b = 1, 0.82, 0.2
	end
	return text, gap, r, g, b
end

local function collect()
	local seen, mobs = {}, {}
	local function add(unit)
		if not unit or not mobOk(unit) then return end
		local guid = plain(UnitGUID(unit))
		if not guid or seen[guid] then return end
		if not myStatus(unit) then return end
		seen[guid] = true
		mobs[#mobs + 1] = unit
	end
	local plates = ns.Plates and ns.Plates.units()
	if plates then
		for _, u in ipairs(plates) do add(u) end
	else
		for i = 1, 40 do add("nameplate" .. i) end
	end
	add("target")
	add("focus")
	for i = 1, 5 do add("boss" .. i) end
	return mobs
end

local function refresh()
	if not on() or not isTank() then box:Hide() return end
	if not box:GetPoint() then place() end
	local others = groupUnits()
	local rows = {}
	for _, unit in ipairs(collect()) do
		local text, gap, r, g, b = lineFor(unit, others)
		rows[#rows + 1] = { text, gap, r, g, b }
	end
	table.sort(rows, function(a, b) return a[2] < b[2] end)
	local lines = { "mob,me%,next,%,next,%" }
	local color
	for i = 1, math.min(#rows, 16) do
		lines[#lines + 1] = rows[i][1]
		if i == 1 then color = { rows[i][3], rows[i][4], rows[i][5] } end
	end
	if #rows == 0 then lines[2] = "(none)" end
	if #rows > 16 then lines[#lines + 1] = ("... %d more"):format(#rows - 16) end
	body:SetText(table.concat(lines, "\n"))
	if color and #rows > 0 then body:SetTextColor(color[1], color[2], color[3]) else body:SetTextColor(1, 0.92, 0.75) end
	box:SetHeight(math.max(44, 28 + #lines * 14))
	box:Show()
end

local ev = CreateFrame("Frame")
for _, e in ipairs({
	"PLAYER_LOGIN", "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED",
	"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
	"NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
	"UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE",
	"PLAYER_TARGET_CHANGED",
}) do
	pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then place() end
	refresh()
end)

local elapsed = 0
box:SetScript("OnUpdate", function(_, dt)
	elapsed = elapsed + dt
	if elapsed < 0.4 then return end
	elapsed = 0
	refresh()
end)

ns.OnFeatureChanged(function(key) if key == "threatBox" then refresh() end end)
