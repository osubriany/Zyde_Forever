-- Zyde_Forever: a threat table for the tank role.
-- Shown in a party or raid while your role is Tank. One row per mob you
-- have threat on:
--   Mob | You | Next | % | 2nd | %
-- Only mobs the game will tell us about: nameplates, bosses, and your target.
-- In a dungeon the percents can be hidden from addon code. Each cell is its
-- own text, which is the only way those hidden numbers will show.
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

-- A secret must never be the left side of "or" or "and". Callers pass the
-- result straight to SetText.
local function shown(v)
	if v == nil then return "" end
	return v
end

---------------------------------------------------------------------------
-- The box. Columns are measured once so the header and the rows share them.
---------------------------------------------------------------------------
local PAD, GAP, INSET = 8, 10, 3
local TITLE_H, HEAD_H, ROW_H = 20, 18, 18
local COLS = {
	{ label = "Mob",  w = 156, align = "LEFT" },
	{ label = "You",  w = 40,  align = "RIGHT" },
	{ label = "Next", w = 96,  align = "LEFT" },
	{ label = "%",    w = 36,  align = "RIGHT" },
	{ label = "2nd",  w = 96,  align = "LEFT" },
	{ label = "%",    w = 36,  align = "RIGHT" },
}
local RULE_AT = { 2, 3, 5 }

local x = PAD
for i, col in ipairs(COLS) do
	col.x = x
	if col.align == "RIGHT" then
		col.tx, col.tw = x, col.w - INSET
	else
		col.tx, col.tw = x + INSET, col.w - INSET * 2
	end
	x = x + col.w
	if i < #COLS then x = x + GAP end
end
local BOX_W = x + PAD + 2

local box = CreateFrame("Frame", "ZydeForeverThreat", UIParent)
box:SetSize(BOX_W, TITLE_H + HEAD_H + ROW_H + 8)
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
header:SetHeight(TITLE_H - 1)
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

local colHead = CreateFrame("Frame", nil, box)
colHead:SetPoint("TOPLEFT", 1, -TITLE_H)
colHead:SetPoint("TOPRIGHT", -1, -TITLE_H)
colHead:SetHeight(HEAD_H)
colHead.bg = colHead:CreateTexture(nil, "BACKGROUND")
colHead.bg:SetAllPoints()
colHead.bg:SetColorTexture(0.11, 0.11, 0.13, 1)
colHead.rule = colHead:CreateTexture(nil, "BORDER")
colHead.rule:SetPoint("BOTTOMLEFT", 0, 0)
colHead.rule:SetPoint("BOTTOMRIGHT", 0, 0)
colHead.rule:SetHeight(1)
colHead.rule:SetColorTexture(1, 1, 1, 0.16)
for _, col in ipairs(COLS) do
	local fs = colHead:CreateFontString(nil, "OVERLAY")
	font(fs, 11)
	fs:SetPoint("LEFT", colHead, "LEFT", col.tx, 0)
	fs:SetWidth(col.tw)
	fs:SetJustifyH(col.align)
	fs:SetJustifyV("MIDDLE")
	fs:SetWordWrap(false)
	fs:SetText(col.label)
	fs:SetTextColor(0.78, 0.72, 0.55)
end
for _, colIndex in ipairs(RULE_AT) do
	local line = colHead:CreateTexture(nil, "BORDER")
	line:SetWidth(1)
	line:SetPoint("TOP", colHead, "TOPLEFT", COLS[colIndex].x - (GAP / 2), 0)
	line:SetPoint("BOTTOM", colHead, "BOTTOMLEFT", COLS[colIndex].x - (GAP / 2), 0)
	line:SetColorTexture(1, 1, 1, 0.1)
end

local function place()
	box:ClearAllPoints()
	local p = ZydeForeverDB and ZydeForeverDB.threatPos
	if type(p) == "table" and type(p.point) == "string" and type(p.x) == "number" and type(p.y) == "number" then
		box:SetPoint(p.point, UIParent, p.point, p.x, p.y)
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
	if type(point) ~= "string" or type(x) ~= "number" or type(y) ~= "number" then return end
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

-- Detailed percents come back for target, focus and boss. The same mob's
-- nameplate token often returns a situation and no numbers at all.
local function tokensFor(unit)
	local list = {}
	local function add(token)
		if token == unit then list[#list + 1] = token return end
		local exists = safe(UnitExists, token)
		if isSecret(exists) or not exists then return end
		local same = safe(UnitIsUnit, unit, token)
		if isSecret(same) or same ~= true then return end
		list[#list + 1] = token
	end
	add("target")
	add("focus")
	for i = 1, 5 do add("boss" .. i) end
	if unit ~= "target" and unit ~= "focus" and not (type(unit) == "string" and unit:match("^boss%d$")) then
		list[#list + 1] = unit
	end
	return list
end

-- nil: not on the threat table. "secret": the game hid the number.
-- A number 0-3: on the table (3 = it is securely on this person).
local function threatStatus(unit, mob)
	if not UnitThreatSituation then return nil end
	for _, token in ipairs(tokensFor(mob)) do
		local status = safe(UnitThreatSituation, unit, token)
		if isSecret(status) then return "secret" end
		if status ~= nil then return status end
	end
	return nil
end

local function myStatus(unit)
	return threatStatus("player", unit)
end

-- One token's answer. The second return is false when this token said nothing,
-- so the caller can try target after a nameplate.
-- A secret number is returned as-is. Comparing it throws.
local function readPct(unit, mob)
	if not UnitDetailedThreatSituation then return nil, false end
	local tanking, status, scaled, raw = safe(UnitDetailedThreatSituation, unit, mob)
	if isSecret(scaled) then return scaled, true end
	if type(scaled) == "number" then return scaled, true end
	if isSecret(raw) then return raw, true end
	if type(raw) == "number" then return raw, true end
	if isSecret(tanking) or isSecret(status) then return nil, true end
	-- While you hold the mob the percent is often left out. It means 100.
	if tanking == true or status == 2 or status == 3 then return 100, true end
	if status ~= nil then return nil, true end
	return nil, false
end

local function scaledPct(unit, mob)
	for _, token in ipairs(tokensFor(mob)) do
		local pct, ok = readPct(unit, token)
		if ok then return pct end
	end
	return nil
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

-- Whole numbers only. A raw percent is often 8.4615..., and a hidden one
-- cannot be rounded with math. RoundToNearestString accepts both.
local function pctCell(n)
	if n == nil then return "" end
	if C_StringUtil and C_StringUtil.RoundToNearestString then
		local s = safe(C_StringUtil.RoundToNearestString, n)
		if isSecret(s) or type(s) == "string" or type(s) == "number" then return s end
	end
	if isSecret(n) then return n end
	if type(n) ~= "number" then return "" end
	return tostring(math.floor(n + 0.5))
end

local function unitLabel(unit, fallback)
	local name = safe(UnitName, unit)
	if isSecret(name) then return name end
	if type(name) == "string" and name ~= "" then return name end
	return fallback
end

local function sameUnit(a, b)
	if a == b then return true end
	local same = safe(UnitIsUnit, a, b)
	if isSecret(same) then return false end
	return same and true or false
end

-- Closest pull at the top: smallest gap between you and the next person.
-- Someone ahead of you sorts as a negative gap, so they stay at the top.
local function lineFor(unit, others)
	local name = unitLabel(unit, "Mob")
	local status = myStatus(unit)
	local mine = scaledPct("player", unit)
	-- Nameplate situation can say you have the mob while the percent is blank.
	if not isSecret(mine) and type(mine) ~= "number" and (status == 2 or status == 3) then mine = 100 end
	local ranked = {}
	for _, u in ipairs(others) do
		local exists = safe(UnitExists, u)
		if not isSecret(exists) and exists then
			local p = scaledPct(u, unit)
			local listed = threatStatus(u, unit) ~= nil or isSecret(p) or type(p) == "number"
			if listed then ranked[#ranked + 1] = { name = unitLabel(u, ""), pct = p } end
		end
	end
	-- Known percents first (highest first), then hidden ones, then people with no
	-- percent at all; ties keep their order. Every pair gets a firm answer: saying
	-- "equal" to some pairs and not others made table.sort throw "invalid order function".
	local function kind(p)
		if isSecret(p) then return 1 end
		if type(p) == "number" then return 0 end
		return 2
	end
	for i, e in ipairs(ranked) do e.i, e.k = i, kind(e.pct) end
	table.sort(ranked, function(a, b)
		if a.k ~= b.k then return a.k < b.k end
		if a.k == 0 and a.pct ~= b.pct then return a.pct > b.pct end
		return a.i < b.i
	end)
	local first, second = ranked[1], ranked[2]
	local mineN, firstN
	if not isSecret(mine) and type(mine) == "number" then mineN = math.floor(mine + 0.5) end
	if first and not isSecret(first.pct) and type(first.pct) == "number" then firstN = math.floor(first.pct + 0.5) end
	local gap = 999
	if mineN and firstN then gap = mineN - firstN end
	local cells = {
		shown(name),
		pctCell(mine),
		"",
		"",
		"",
		"",
	}
	if first then
		cells[3] = shown(first.name)
		cells[4] = pctCell(first.pct)
	end
	if second then
		cells[5] = shown(second.name)
		cells[6] = pctCell(second.pct)
	end
	-- Warm by default. Yellow when the next person is within 15. Red when
	-- they are already ahead, or the mob is not on you and the percent is hidden.
	local r, g, b = 1, 0.92, 0.75
	if mineN and firstN then
		if firstN > mineN then r, g, b = 1, 0.45, 0.38
		elseif (mineN - firstN) < 15 then r, g, b = 1, 0.82, 0.2
		end
	elseif status == 2 or status == 1 then
		r, g, b = 1, 0.82, 0.2
	elseif status == 0 then
		r, g, b = 1, 0.45, 0.38
	end
	return cells, gap, r, g, b
end

local function collect()
	local seen, mobs, platesSeen = {}, {}, {}
	local function add(unit)
		if not unit or not mobOk(unit) then return end
		local guid = plain(safe(UnitGUID, unit))
		if guid and seen[guid] then return end
		-- In a dungeon the GUID and UnitIsUnit can both be hidden. The nameplate
		-- frame still tells: your target with a plate already listed is the same mob.
		local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and safe(C_NamePlate.GetNamePlateForUnit, unit)
		if isSecret(plate) or type(plate) ~= "table" then plate = nil end
		if plate and platesSeen[plate] then return end
		for _, u in ipairs(mobs) do
			if sameUnit(u, unit) then return end
		end
		if not myStatus(unit) then return end
		if guid then seen[guid] = true end
		if plate then platesSeen[plate] = true end
		mobs[#mobs + 1] = unit
	end
	local plates = ns.Plates and safe(ns.Plates.units)
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
local rowFrames = {}
local function ensureRows()
	if rowFrames[1] then return end
	for i = 1, 16 do
		local r = CreateFrame("Frame", nil, box)
		r:SetHeight(ROW_H)
		r:SetPoint("TOPLEFT", 1, -(TITLE_H + HEAD_H + (i - 1) * ROW_H))
		r:SetPoint("TOPRIGHT", -1, -(TITLE_H + HEAD_H + (i - 1) * ROW_H))
		r.bg = r:CreateTexture(nil, "BACKGROUND")
		r.bg:SetAllPoints()
		r.cells = {}
		for c, col in ipairs(COLS) do
			local fs = r:CreateFontString(nil, "OVERLAY")
			font(fs, 12)
			fs:SetPoint("LEFT", r, "LEFT", col.tx, 0)
			fs:SetWidth(col.tw)
			fs:SetJustifyH(col.align)
			fs:SetJustifyV("MIDDLE")
			fs:SetWordWrap(false)
			r.cells[c] = fs
		end
		r.rules = {}
		for n, colIndex in ipairs(RULE_AT) do
			local line = r:CreateTexture(nil, "BORDER")
			line:SetWidth(1)
			line:SetPoint("TOP", r, "TOPLEFT", COLS[colIndex].x - (GAP / 2), 0)
			line:SetPoint("BOTTOM", r, "BOTTOMLEFT", COLS[colIndex].x - (GAP / 2), 0)
			line:SetColorTexture(1, 1, 1, 0.1)
			r.rules[n] = line
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

local function paintRow(r, cells, cr, cg, cb, stripe)
	r.bg:SetColorTexture(1, 1, 1, stripe)
	for c = 1, 6 do
		setCell(r.cells[c], cells[c])
		r.cells[c]:SetTextColor(cr, cg, cb)
	end
	r:Show()
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
	local count = #rows
	local shown = math.min(count, 16)
	if shown == 0 then
		paintRow(rowFrames[1], { "No mobs on you", "", "", "", "", "" }, 0.55, 0.52, 0.45, 0)
		shown = 1
		for i = 2, #rowFrames do rowFrames[i]:Hide() end
	else
		for i, r in ipairs(rowFrames) do
			local row = rows[i]
			if i <= shown and row then
				paintRow(r, row[1], row[3], row[4], row[5], (i % 2 == 0) and 0.045 or 0.02)
			else
				r:Hide()
			end
		end
	end
	box:SetHeight(TITLE_H + HEAD_H + shown * ROW_H + 4)
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
