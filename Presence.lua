-- Who is running Zyde right now. Every client tells the guild which of these
-- are on when it logs in, then again every 15 minutes: unit frames (and the
-- style), reminder icons, the minimap button bag, the quest tracker, the tank
-- threat list, and the level planner. The options window counts people heard
-- in the last little while. An officer of Blackrock Breakfast Club whose name
-- contains smurf, variz, varuz, or stepdad can click that count and review
-- each person's settings.

local _, ns = ...

local PREFIX = "ZydeF"
local HELLO_EVERY = 15 * 60
-- A client that says hello every 15 minutes stays "online" if the next one is
-- a couple of minutes late.
local ONLINE_FOR = 18 * 60

local GUILD = "blackrock breakfast club"
-- The character name may be a first name plus a surname ("Stepdad Smurf").
-- Either tag is enough for the officer review.
local NAME_TAGS = { "smurf", "variz", "varuz", "stepdad" }

local seen, names, reports = {}, {}, {}
local STYLE_NAME = {
	slant = "Gilded Slant", bold = "Gilded Bold", flat = "Clean Flat",
	hex = "Hex Crest", glass = "Glass Glow", plate = "Arcane Plate",
}

local function plain(v)
	if type(issecretvalue) == "function" and issecretvalue(v) then return nil end
	if v == nil or type(v) ~= "string" or v == "" then return nil end
	return v
end

local function characterName(value)
	local name = plain(value)
	if not name then return nil end
	name = name:match("^%s*(.-)%s*$")
	if not name or name == "" then return nil end
	return (name:match("^([^%-]+)"))
end

-- Forever's UnitName is (first, surname). The guild message names you with
-- both, so a hello that only keeps the first name shows up as a second person.
local function myName()
	local first, second = UnitName("player")
	first = characterName(first)
	if not first then return nil end
	second = plain(second)
	if not second or second == "" or second:find("-", 1, true) then return first end
	local realm = ""
	if GetRealmName then
		local ok, got = pcall(GetRealmName)
		if ok then realm = plain(got) or "" end
	end
	if realm ~= "" and second:lower() == realm:lower() then return first end
	return first .. " " .. second
end

local function nameMatches()
	local name = myName()
	if not name then return false end
	local realm = ""
	if GetRealmName then
		local ok, got = pcall(GetRealmName)
		if ok then realm = plain(got) or "" end
	end
	local blob = (name .. " " .. realm):lower()
	for _, tag in ipairs(NAME_TAGS) do
		if blob:find(tag, 1, true) then return true end
	end
	return false
end

local function norm(v)
	local s = plain(v)
	if not s then return nil end
	return s:lower():gsub("%s+", " "):match("^%s*(.-)%s*$")
end

local function rankIsOfficer(rankName, rankIndex)
	if type(rankIndex) == "number" and not (type(issecretvalue) == "function" and issecretvalue(rankIndex)) and rankIndex == 0 then
		return true
	end
	local rank = norm(rankName)
	if not rank then return false end
	return rank:find("officer", 1, true) or rank:find("guild master", 1, true) or rank == "gm"
end

-- In Blackrock Breakfast Club, and an officer: the note permission, guild
-- master (rank 0), or a rank whose name says so. The client fills the roster
-- cache itself; asking for a refresh from here is a Blizzard-only action.
local function isOfficer()
	if not GetGuildInfo then return false end
	local ok, guild, rankName, rankIndex = pcall(GetGuildInfo, "player")
	if not ok then return false end
	local g = norm(guild)
	if not g or not g:find(GUILD, 1, true) then return false end
	if rankIsOfficer(rankName, rankIndex) then return true end
	local canView = (C_GuildInfo and C_GuildInfo.CanViewOfficerNote) or CanViewOfficerNote
	if canView then
		local allowed
		ok, allowed = pcall(canView)
		if ok and allowed then return true end
	end
	if GetNumGuildMembers and GetGuildRosterInfo then
		local me = myName()
		if me then
			me = me:lower()
			local n = GetNumGuildMembers()
			if type(n) == "number" then
				for i = 1, n do
					local name, rosterRank, rosterIndex = GetGuildRosterInfo(i)
					name = characterName(name)
					if name and name:lower() == me and rankIsOfficer(rosterRank, rosterIndex) then
						return true
					end
				end
			end
		end
	end
	return false
end

local function isWatcher()
	return nameMatches() and isOfficer()
end

local function line()
	local now = GetTime()
	local n = 0
	for _, when in pairs(seen) do
		if now - when <= ONLINE_FOR then n = n + 1 end
	end
	return n .. " ZydeForever Users Currently Online"
end

local listWindow

local function paint()
	local o = _G.ZydeForeverOptions
	if o and o.usersLabel and o.Refresh and o:IsShown() then
		o.usersLabel:SetText(line())
		local watch = isWatcher()
		o.users:EnableMouse(watch)
		o.usersLabel:SetTextColor(watch and 1 or 0.92, watch and 0.82 or 0.82, watch and 0.35 or 0.75)
	end
	if listWindow and listWindow:IsShown() then listWindow:Rebuild() end
end

local function yn(on)
	return on and "|cff8fd08fon|r" or "|cffd07070off|r"
end

local function snapshot()
	local function bit(key) return ns.F and ns.F(key) and "1" or "0" end
	local style = "slant"
	local UF = ns.UnitFrames
	if UF and UF.GetStyle then
		local got = UF.GetStyle()
		if type(got) == "string" and STYLE_NAME[got] then style = got end
	end
	return table.concat({
		"v1", bit("unitFrames"), style, bit("reminders"), bit("buttonBag"),
		bit("questTracker"), bit("threatBox"), bit("levelPlanner"),
	}, " ")
end

local function parseReport(message)
	message = plain(message)
	if not message then return nil end
	local frames, style, reminders, bag, tracker, threat, planner = message:match("^v1 (%d) (%a+) (%d) (%d) (%d) (%d) (%d)$")
	if not frames or not STYLE_NAME[style] then return nil end
	return {
		frames = frames == "1", style = style,
		reminders = reminders == "1", bag = bag == "1",
		tracker = tracker == "1", threat = threat == "1", planner = planner == "1",
	}
end

local function reportLines(info)
	if not info then return "No feature report yet", "" end
	local frames = "Frames " .. yn(info.frames) .. ", " .. (STYLE_NAME[info.style] or info.style)
	local first = frames .. "    Reminders " .. yn(info.reminders) .. "    Bag " .. yn(info.bag)
	local second = "Tracker " .. yn(info.tracker) .. "    Threat " .. yn(info.threat) .. "    Planner " .. yn(info.planner)
	return first, second
end

-- "Stepdad" and "Stepdad Smurf" are one person. The longer name wins.
local function samePerson(short, full)
	if not short or not full or short == full then return false end
	return full:sub(1, #short + 1):lower() == (short .. " "):lower()
end

local function dropName(name)
	seen[name] = nil
	reports[name] = nil
	for i = #names, 1, -1 do
		if names[i] == name then table.remove(names, i) end
	end
end

local function hear(name, message)
	name = characterName(name)
	if not name then return end
	for i = 1, #names do
		local other = names[i]
		if samePerson(name, other) then
			seen[other] = GetTime()
			local info = parseReport(message)
			if info then reports[other] = info end
			paint()
			return
		end
	end
	local i = 1
	while i <= #names do
		if samePerson(names[i], name) then dropName(names[i]) else i = i + 1 end
	end
	if not seen[name] then names[#names + 1] = name end
	seen[name] = GetTime()
	local info = parseReport(message)
	if info then reports[name] = info end
	paint()
end

local lastHello = 0

local function hello()
	local now = GetTime()
	if now - lastHello < 30 then return end
	if not (IsInGuild and IsInGuild()) then return end
	local msg = snapshot()
	hear(myName(), msg)
	lastHello = now
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "GUILD")
	elseif SendAddonMessage then
		pcall(SendAddonMessage, PREFIX, msg, "GUILD")
	end
end

local function registerPrefix()
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
	elseif RegisterAddonMessagePrefix then
		pcall(RegisterAddonMessagePrefix, PREFIX)
	end
end

local rows = {}
local ROW_H = 50

local function ensureList()
	if listWindow then return listWindow end
	local PURPLE, GOLD = { 0.69, 0.35, 1 }, { 1, 0.82, 0.2 }
	local w = CreateFrame("Frame", "ZydeForeverUsers", UIParent, "BackdropTemplate")
	listWindow = w
	w:SetSize(560, 480)
	w:SetPoint("CENTER", 80, 0)
	w:SetFrameStrata("DIALOG")
	w:SetFrameLevel(60)
	w:SetMovable(true)
	w:EnableMouse(true)
	w:RegisterForDrag("LeftButton")
	w:SetScript("OnDragStart", w.StartMoving)
	w:SetScript("OnDragStop", w.StopMovingOrSizing)
	w:SetClampedToScreen(true)
	w:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	w:SetBackdropColor(0.07, 0.07, 0.08, 0.97)
	w:SetBackdropBorderColor(PURPLE[1], PURPLE[2], PURPLE[3], 0.9)
	tinsert(UISpecialFrames, "ZydeForeverUsers")
	local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 14, -12)
	title:SetText("ZydeForever users")
	title:SetTextColor(PURPLE[1], PURPLE[2], PURPLE[3])
	w.sub = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	w.sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
	w.sub:SetText("Checked in since you logged in.")
	local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	local scroll = CreateFrame("ScrollFrame", nil, w, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 10, -48)
	scroll:SetPoint("BOTTOMRIGHT", -30, 14)
	w.scroll = scroll
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(500, 1)
	scroll:SetScrollChild(content)
	w.content = content
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local cur = self:GetVerticalScroll()
		local maxScroll = self:GetVerticalScrollRange()
		self:SetVerticalScroll(math.min(maxScroll, math.max(0, cur - delta * ROW_H)))
	end)

	function w:Rebuild()
		local now = GetTime()
		local list = {}
		for i = 1, #names do list[i] = names[i] end
		table.sort(list, function(a, b) return a:lower() < b:lower() end)
		local online = 0
		for _, name in ipairs(list) do
			if now - (seen[name] or 0) <= ONLINE_FOR then online = online + 1 end
		end
		self.sub:SetText(#list .. " checked in since you logged in. " .. online .. " online now.")
		for i, name in ipairs(list) do
			local row = rows[i]
			if not row then
				row = CreateFrame("Frame", nil, self.content)
				row:SetSize(500, ROW_H)
				row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
				row.name:SetPoint("TOPLEFT", 8, -2)
				row.name:SetJustifyH("LEFT")
				row.a = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				row.a:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
				row.a:SetJustifyH("LEFT")
				row.b = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				row.b:SetPoint("TOPLEFT", row.a, "BOTTOMLEFT", 0, -1)
				row.b:SetJustifyH("LEFT")
				rows[i] = row
			end
			row:SetPoint("TOPLEFT", 0, -((i - 1) * ROW_H))
			local fresh = now - (seen[name] or 0) <= ONLINE_FOR
			row.name:SetText(name)
			row.name:SetTextColor(fresh and GOLD[1] or 0.55, fresh and GOLD[2] or 0.55, fresh and GOLD[3] or 0.55)
			local first, second = reportLines(reports[name])
			row.a:SetText(first)
			row.b:SetText(second)
			row:Show()
		end
		for i = #list + 1, #rows do rows[i]:Hide() end
		self.content:SetHeight(math.max(1, #list * ROW_H + 8))
	end

	w:Hide()
	return w
end

local function toggleList()
	if not isWatcher() then return end
	local w = ensureList()
	w:SetShown(not w:IsShown())
	if w:IsShown() then
		w:Rebuild()
		w:Raise()
	end
end

ns.ZydePresence = {
	Line = line,
	IsWatcher = isWatcher,
	ToggleList = toggleList,
}

local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("CHAT_MSG_ADDON")
driver:RegisterEvent("GUILD_ROSTER_UPDATE")
driver:SetScript("OnEvent", function(_, event, prefix, message, _, sender)
	if event == "CHAT_MSG_ADDON" then
		if prefix == PREFIX then hear(sender, message) end
		return
	end
	if event == "GUILD_ROSTER_UPDATE" then
		paint()
		return
	end
	if driver.started then return end
	driver.started = true
	registerPrefix()
	hear(myName(), snapshot())
	C_Timer.After(2, hello)
end)

if C_Timer and C_Timer.NewTicker then
	C_Timer.NewTicker(HELLO_EVERY, hello)
	C_Timer.NewTicker(30, paint)
end
