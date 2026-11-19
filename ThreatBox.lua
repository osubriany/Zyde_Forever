-- Zyde_Forever: a threat list for the tank role.
-- Shown in a party or raid while your role is Tank. One line per mob you
-- have threat on:
--   mob, your %, next person, their %, second person, their %
-- Only mobs the game will tell us about: nameplates, bosses, and your target.
-- In a dungeon the percents can be hidden from addon code. They are drawn
-- one cell at a time, which is the only way those hidden numbers will show.
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
		-- A dungeon can hide the role. A healer or damage role still hides the box.
		if isSecret(role) then return true end
		if role == "TANK" then return true end
		if role == "HEALER" or role == "DAMAGER" then return false end
	end
	if GetPartyAssignment then
		local mt = safe(GetPartyAssignment, "MAINTANK", "player")
		if isSecret(mt) then return true end
		if mt then return true end
	end
	-- A walk-in dungeon often has no role set. Show the list there anyway.
	local _, inst = IsInInstance()
	if isSecret(inst) then return true end
	return inst == "party" or inst == "raid"
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
	-- Check the secret before any comparison. A dungeon hides this number.
	if isSecret(status) then return "secret" end
	if status == nil then return nil end
	return status
end

-- Scaled percent: 100 means this person has the most threat on that mob.
-- A secret number is returned as-is so the line can draw it. Comparing it throws.
local function scaledPct(unit, mob)
	if not UnitDetailedThreatSituation then return nil end
	local _, _, scaled = safe(UnitDetailedThreatSituation, unit, mob)
	if isSecret(scaled) then return scaled end
	if scaled == nil then return nil end
	return tonumber(scaled)
end

local function yes(v)
	if isSecret(v) then return false end
	return v == true
end

local function mobOk(unit)
	local exists = safe(UnitExists, unit)
	if isSecret(exists) or not exists then return false end
	if UnitIsDead and yes(safe(UnitIsDead, unit)) then return false end
	if UnitIsPlayer and yes(safe(UnitIsPlayer, unit)) then return false end
	if yes(safe(UnitIsFriend, "player", unit)) then return false end
	return true
end

local function csv(s)
	s = tostring(s or "")
	if s:find('[,"]') then return '"' .. s:gsub('"', '""') .. '"' end
	return s
end

local function pctText(n)
	if n == nil or n == "" then return "" end
	if isSecret(n) then return n end
	return tostring(math.floor(n + 0.5))
end

local function unitLabel(unit)
	local name = safe(UnitName, unit)
	if isSecret(name) then return name end
	if type(name) == "string" and name ~= "" then return name end
	return "Mob"
end

local function lineFor(unit, others)
	local name = unitLabel(unit)
	local mine = scaledPct("player", unit)
	local ranked = {}
	for _, u in ipairs(others) do
		local exists = safe(UnitExists, u)
		if not isSecret(exists) and exists then
			local p = scaledPct(u, unit)
			local keep = isSecret(p) or (type(p) == "number" and p > 0)
			if keep then ranked[#ranked + 1] = { name = unitLabel(u), pct = p } end
		end
	end
	table.sort(ranked, function(a, b)
		if isSecret(a.pct) or isSecret(b.pct) then return false end
		return a.pct > b.pct
	end)
	local first, second = ranked[1], ranked[2]
	-- Closest pull at the top: smallest gap between you and the next person.
	local gap = 999
	if type(mine) == "number" and first and type(first.pct) == "number" then gap = mine - first.pct end
	local cells = {
		isSecret(name) and name or csv(name), pctText(mine),
		first and (isSecret(first.name) and first.name or csv(first.name)) or "",
		first and pctText(first.pct) or "",
		second and (isSecret(second.name) and second.name or csv(second.name)) or "",
		second and pctText(second.pct) or "",
	}
	local r, g, b = 1, 0.92, 0.75
	if type(mine) == "number" and first and type(first.pct) == "number" then
		if first.pct > mine then r, g, b = 1, 0.35, 0.3
		elseif (mine - first.pct) < 15 then r, g, b = 1, 0.82, 0.2
		end
	end
	return cells, gap, r, g, b
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

-- One font string per cell. A dungeon hands back secret numbers, and those
-- can be drawn but cannot be joined into one line of text.
local COL = { 0, 132, 170, 214, 292, 330 }
local rowFrames = {}
local function ensureRows()
	if rowFrames[1] then return end
	for i = 1, 16 do
		local r = CreateFrame("Frame", nil, box)
		r:SetHeight(14)
		r:SetPoint("TOPLEFT", 8, -36 - (i - 1) * 14)
		r:SetPoint("TOPRIGHT", -8, -36 - (i - 1) * 14)
		r.cells = {}
		for c = 1, 6 do
			local fs = r:CreateFontString(nil, "OVERLAY")
			font(fs, 12)
			fs:SetPoint("LEFT", r, "LEFT", COL[c], 0)
			if c == 1 then fs:SetWidth(126) elseif c == 3 or c == 5 then fs:SetWidth(74) end
			fs:SetJustifyH("LEFT")
			fs:SetWordWrap(false)
			r.cells[c] = fs
		end
		r:Hide()
		rowFrames[i] = r
	end
end

local function setCell(fs, v)
	if isSecret(v) then fs:SetText(v) return end
	if v == nil or v == "" then fs:SetText("") return end
	fs:SetText(v)
end

local function refresh()
	if not on() or not isTank() then box:Hide() return end
	if not box:GetPoint() then place() end
	ensureRows()
	local others = groupUnits()
	local rows = {}
	for _, unit in ipairs(collect()) do
		local cells, gap, r, g, b = lineFor(unit, others)
		rows[#rows + 1] = { cells, gap, r, g, b }
	end
	table.sort(rows, function(a, b) return a[2] < b[2] end)
	local shown = math.min(#rows, 16)
	body:SetText(#rows == 0 and "mob,me%,next,%,next,%\n(none)" or "mob,me%,next,%,next,%")
	for i, r in ipairs(rowFrames) do
		local row = rows[i]
		if i <= shown and row then
			for c = 1, 6 do
				setCell(r.cells[c], row[1][c])
				r.cells[c]:SetTextColor(row[3], row[4], row[5])
			end
			r:Show()
		else
			r:Hide()
		end
	end
	box:SetHeight(math.max(44, 40 + (shown + (#rows == 0 and 1 or 0)) * 14))
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
