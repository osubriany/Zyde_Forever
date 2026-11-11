-- Zyde_Forever: a helper panel beside the Looking For Group browser.
-- Reads the same search results as Blizzard's list and re-sorts them for you:
--   1) groups with an open slot for your role (DPS by default), fewest open
--      slots first (they start soonest), newest first
--   2) groups that need a different role (dimmed)
--   full or delisted groups are left out
-- Each row: leader (class colored), dungeon, members, age, what the group
-- needs, and a Whisper button that opens chat with a ready-made message to
-- the leader (you press Enter to send it).
-- Your role (Tank / Healer / DPS) is picked at the top and saved.
-- Rows in Blizzard's own list get a green edge when they have room for you.

local ADDON, ns = ...

local ROLES = { "TANK", "HEALER", "DAMAGER" }
local ROLE_LABEL = { TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" }
local ROLE_ICON = {
	TANK = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:14:14:0:0:64:64:0:19:22:41|t",
	HEALER = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:14:14:0:0:64:64:20:39:1:20|t",
	DAMAGER = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:14:14:0:0:64:64:20:39:22:41|t",
}
-- A dungeon group: 1 tank, 1 healer, 3 DPS.
local WANT = { TANK = 1, HEALER = 1, DAMAGER = 3 }
local MAX_ROWS = 10

local function db()
	ZydeForeverDB = ZydeForeverDB or {}
	return ZydeForeverDB
end
local function on() return ns.F and ns.F("lfg") end
local function myRole() return db().lfgRole or "DAMAGER" end

---------------------------------------------------------------------------
-- Reading a search result
---------------------------------------------------------------------------
local function plain(v)
	if v == nil or ns.isSecret(v) then return nil end
	return v
end

local function activityName(info)
	local id = info.activityID or (type(info.activityIDs) == "table" and info.activityIDs[1])
	if id and C_LFGList.GetActivityInfoTable then
		local a = ns.safe(C_LFGList.GetActivityInfoTable, id)
		if type(a) == "table" then return a.shortName ~= "" and a.shortName or a.fullName end
	end
	if id and C_LFGList.GetActivityInfo then
		return (ns.safe(C_LFGList.GetActivityInfo, id))
	end
	return info.name
end

-- Group summary for one result: counts per role, open slots, leader class.
local function readResult(id)
	local info = ns.safe(C_LFGList.GetSearchResultInfo, id)
	if type(info) ~= "table" then return nil end
	local members = plain(info.numMembers) or 1
	local g = { id = id, leader = plain(info.leaderName), members = members, age = plain(info.age) or 0,
		activity = activityName(info), comment = plain(info.comment), counts = { TANK = 0, HEALER = 0, DAMAGER = 0 } }

	-- Roles: count who's in the group. (The game's "remaining" numbers don't
	-- know about 1 tank / 1 healer / 3 DPS here, so they're not used.)
	local counted = false
	if C_LFGList.GetSearchResultMemberInfo then
		for i = 1, members do
			local role, class = ns.safe(C_LFGList.GetSearchResultMemberInfo, id, i)
			role = plain(role)
			if role and g.counts[role] then g.counts[role] = g.counts[role] + 1 counted = true end
			if i == 1 then g.class = plain(class) end
		end
	end
	if not counted then
		local mc = C_LFGList.GetSearchResultMemberCounts and ns.safe(C_LFGList.GetSearchResultMemberCounts, id)
		if type(mc) == "table" then
			g.counts = { TANK = mc.TANK or 0, HEALER = mc.HEALER or 0, DAMAGER = mc.DAMAGER or 0 }
		end
	end
	g.open = {}
	for _, r in ipairs(ROLES) do g.open[r] = math.max(0, WANT[r] - g.counts[r]) end
	g.free = math.max(0, 5 - members)
	-- Gone: filled up or no longer listed (Blizzard grays these out).
	g.gone = info.isDelisted and "No longer listed" or (g.free == 0 and "Full") or nil
	g.fits = not g.gone and (g.open[myRole()] or 0) > 0
	return g
end

local function sortGroups(list)
	table.sort(list, function(a, b)
		if (a.gone ~= nil) ~= (b.gone ~= nil) then return not a.gone end -- gone ones last
		if a.fits ~= b.fits then return a.fits end
		if a.free ~= b.free then return a.free < b.free end -- closest to full starts soonest
		return a.age < b.age                                  -- newest first
	end)
end

local fitByID = {}
local function collect()
	wipe(fitByID)
	local list = {}
	if not (C_LFGList and C_LFGList.GetSearchResults) then return list end
	local _, results = ns.safe(C_LFGList.GetSearchResults)
	for _, id in ipairs(type(results) == "table" and results or {}) do
		local g = readResult(id)
		if g and g.leader then
			list[#list + 1] = g
			fitByID[id] = g.fits
		end
	end
	sortGroups(list)
	return list
end

---------------------------------------------------------------------------
-- Whisper
---------------------------------------------------------------------------
local function whisperText(g)
	local classLocal = UnitClass("player") -- localized name, e.g. "Warrior"
	local where = g.activity and (" for " .. g.activity) or ""
	return ("Hi! Level %d %s (%s) - any room for me%s?"):format(UnitLevel("player"), classLocal, ROLE_LABEL[myRole()], where)
end

local function whisper(g)
	if not g.leader then return end
	local text = "/w " .. g.leader .. " " .. whisperText(g)
	if ChatFrame_OpenChat then
		ChatFrame_OpenChat(text)
	elseif ChatEdit_ActivateChat and DEFAULT_CHAT_FRAME then
		local eb = DEFAULT_CHAT_FRAME.editBox
		ChatEdit_ActivateChat(eb)
		eb:SetText(text)
	end
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local panel = CreateFrame("Frame", "ZydeForeverLFG", UIParent, "BackdropTemplate")
panel:SetSize(350, 480)
panel:SetFrameStrata("HIGH")
panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
panel:SetBackdropColor(0.07, 0.07, 0.08, 0.95)
panel:SetBackdropBorderColor(0.69, 0.35, 1, 0.9)
panel:EnableMouse(true)
panel:Hide()

panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
panel.title:SetPoint("TOPLEFT", 10, -8)
panel.title:SetTextColor(0.69, 0.35, 1)
panel.title:SetText("Groups for you")

panel.summary = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
panel.summary:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -3)

-- Role picker: three small buttons, the chosen one lit.
panel.roleButtons = {}
for i = #ROLES, 1, -1 do
	local role = ROLES[i]
	local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	b:SetSize(56, 20)
	b:SetPoint("TOPRIGHT", -8 - (#ROLES - i) * 58, -8)
	b:SetText(ROLE_LABEL[role])
	b:SetScript("OnClick", function()
		db().lfgRole = role
		panel:Refresh()
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Join as " .. ROLE_LABEL[role])
		GameTooltip:AddLine("Groups with room for this role go to the top.", 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	panel.roleButtons[role] = b
end

-- "Only groups I fit" toggle.
panel.onlyFit = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
panel.onlyFit:SetSize(20, 20)
panel.onlyFit:SetPoint("TOPLEFT", 6, -40)
panel.onlyFit.text = panel.onlyFit:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
panel.onlyFit.text:SetPoint("LEFT", panel.onlyFit, "RIGHT", 2, 0)
panel.onlyFit.text:SetText("Only show groups with room for me")
panel.onlyFit:SetScript("OnClick", function(self)
	db().lfgOnlyFit = self:GetChecked() and true or false
	panel:Refresh()
end)

local ROW_H = 40
local rows = {}
local function row(i)
	if rows[i] then return rows[i] end
	local r = CreateFrame("Frame", nil, panel, "BackdropTemplate")
	r:SetSize(334, ROW_H - 4)
	r:SetPoint("TOPLEFT", 8, -64 - (i - 1) * ROW_H)
	r:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	r:EnableMouse(true)

	r.leader = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	r.leader:SetPoint("TOPLEFT", 6, -4)
	r.leader:SetWidth(150)
	r.leader:SetJustifyH("LEFT")
	r.leader:SetWordWrap(false)
	r.info = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	r.info:SetPoint("BOTTOMLEFT", 6, 5)
	r.info:SetWidth(250)
	r.info:SetJustifyH("LEFT")
	r.info:SetWordWrap(false)
	r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	r.tag:SetPoint("TOPRIGHT", -70, -5)

	r.whisper = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
	r.whisper:SetSize(62, 20)
	r.whisper:SetPoint("RIGHT", -4, 0)
	r.whisper:SetText("Whisper")
	r.whisper:SetScript("OnClick", function() if r.g then whisper(r.g) end end)
	r.whisper:SetScript("OnEnter", function(self)
		if not r.g then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Whisper " .. r.g.leader)
		GameTooltip:AddLine(whisperText(r.g), 1, 1, 1, true)
		GameTooltip:AddLine("Opens chat with this message - press Enter to send, or edit it first.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	r.whisper:SetScript("OnLeave", function() GameTooltip:Hide() end)

	r:SetScript("OnEnter", function(self)
		local g = self.g
		if not g then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(g.leader)
		if g.activity then GameTooltip:AddLine(g.activity, 1, 1, 1) end
		GameTooltip:AddLine(("%s %d   %s %d   %s %d"):format(ROLE_ICON.TANK, g.counts.TANK,
			ROLE_ICON.HEALER, g.counts.HEALER, ROLE_ICON.DAMAGER, g.counts.DAMAGER), 1, 1, 1)
		if g.comment and g.comment ~= "" then GameTooltip:AddLine(g.comment, 0.8, 0.8, 0.8, true) end
		GameTooltip:Show()
	end)
	r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	rows[i] = r
	return r
end

local function ageText(sec)
	sec = math.floor(sec or 0)
	if sec < 60 then return "just now" end
	if sec < 3600 then return ("%dm ago"):format(sec / 60) end
	return ("%dh ago"):format(sec / 3600)
end

local function needsText(g)
	local parts = {}
	for _, r in ipairs(ROLES) do
		if (g.open[r] or 0) > 0 then parts[#parts + 1] = (g.open[r] > 1 and (g.open[r] .. " ") or "") .. ROLE_LABEL[r] end
	end
	return #parts > 0 and ("Needs " .. table.concat(parts, ", ")) or "Room for anyone"
end

-- The Blizzard window to sit beside, if open.
local HOSTS = { "LFGParentFrame", "LFGBrowseFrame", "PVEFrame", "LFGListFrame" }
local function hostFrame()
	for _, name in ipairs(HOSTS) do
		local f = _G[name]
		if f and f:IsShown() then return f end
	end
end
local function browsing()
	local b = _G.LFGBrowseFrame
	if b then return b:IsVisible() end
	local l = _G.LFGListFrame
	return l and l.SearchPanel and l.SearchPanel:IsVisible() or false
end

-- Green edge on Blizzard's own rows that have room for you.
local function tintBlizzardRows()
	local box = (_G.LFGBrowseFrame and LFGBrowseFrame.ScrollBox)
		or (_G.LFGListFrame and LFGListFrame.SearchPanel and LFGListFrame.SearchPanel.ScrollBox)
	if not (box and box.ForEachFrame) then return end
	pcall(box.ForEachFrame, box, function(entry)
		local id = entry.resultID or (entry.GetElementData and entry:GetElementData() and entry:GetElementData().resultID)
		if not entry.zydeEdge then
			entry.zydeEdge = ns.newEdges(entry, "OVERLAY", 7)
			ns.placeEdges(entry.zydeEdge, entry, 1, 2)
		end
		local fits = id and fitByID[id]
		for _, t in ipairs(entry.zydeEdge) do
			t:SetColorTexture(0.35, 1, 0.35, 0.9)
			t:SetShown(on() and fits == true)
		end
	end)
end

function panel:Refresh()
	local host = on() and browsing() and hostFrame()
	if not host then self:Hide() return end
	for role, b in pairs(self.roleButtons) do
		b:SetAlpha(role == myRole() and 1 or 0.5)
	end
	self.onlyFit:SetChecked(db().lfgOnlyFit == true)

	local all = collect()
	local fitting, open = 0, 0
	for _, g in ipairs(all) do
		if g.fits then fitting = fitting + 1 end
		if not g.gone then open = open + 1 end
	end
	local list = all
	if db().lfgOnlyFit then
		list = {}
		for _, g in ipairs(all) do if g.fits then list[#list + 1] = g end end
	end
	self.summary:SetFormattedText("%d of %d open groups have room for a %s", fitting, open, ROLE_LABEL[myRole()])

	local n = math.min(#list, MAX_ROWS)
	for i = 1, math.max(n, #rows) do
		local r = row(i)
		local g = list[i]
		if i <= n and g then
			r.g = g
			local c = g.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[g.class]
			r.leader:SetText(g.leader)
			r.leader:SetTextColor(c and c.r or 1, c and c.g or 0.82, c and c.b or 0)
			r.info:SetFormattedText("%s  -  %d/5  -  %s", g.activity or "?", g.members, ageText(g.age))
			r.whisper:SetEnabled(not g.gone)
			if g.gone then
				-- Filled or delisted: grayed out at the bottom, like Blizzard's list.
				r.tag:SetText(g.gone)
				r.tag:SetTextColor(0.5, 0.5, 0.5)
				r.leader:SetTextColor(0.5, 0.5, 0.5)
				r:SetBackdropColor(0, 0, 0, 0.3)
				r:SetBackdropBorderColor(0, 0, 0, 0.6)
				r:SetAlpha(0.35)
			elseif g.fits then
				r.tag:SetText(ROLE_LABEL[myRole()] .. " spot open")
				r.tag:SetTextColor(0.35, 1, 0.35)
				r:SetBackdropColor(0.1, 0.3, 0.1, 0.5)
				r:SetBackdropBorderColor(0.35, 1, 0.35, 0.8)
				r:SetAlpha(1)
			else
				r.tag:SetText(needsText(g))
				r.tag:SetTextColor(0.6, 0.6, 0.6)
				r:SetBackdropColor(1, 1, 1, 0.04)
				r:SetBackdropBorderColor(0, 0, 0, 0.6)
				r:SetAlpha(0.55)
			end
			r:Show()
		else
			r.g = nil
			r:Hide()
		end
	end
	self.more = self.more or self:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	self.more:SetPoint("BOTTOMLEFT", 10, 8)
	self.more:SetText(#list > MAX_ROWS and ("+%d more in the list on the left"):format(#list - MAX_ROWS)
		or (#list == 0 and "No groups yet - press the refresh button" or ""))
	self:SetHeight(64 + math.max(1, n) * ROW_H + 26)
	self:ClearAllPoints()
	-- Right of the window, past its side tabs.
	self:SetPoint("TOPLEFT", host, "TOPRIGHT", 44, 0)
	self:Show()
	tintBlizzardRows()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local pending = false
local function refreshSoon()
	if pending then return end
	pending = true
	C_Timer.After(0.2, function() pending = false panel:Refresh() end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		if not C_LFGList then return end
		for _, e in ipairs({ "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_SEARCH_RESULT_UPDATED",
			"LFG_LIST_SEARCH_FAILED", "GROUP_ROSTER_UPDATE" }) do
			pcall(ev.RegisterEvent, ev, e)
		end
		-- Show and hide with the browser.
		for _, name in ipairs({ "LFGParentFrame", "LFGBrowseFrame", "PVEFrame", "LFGListFrame" }) do
			local f = _G[name]
			if f then
				f:HookScript("OnShow", refreshSoon)
				f:HookScript("OnHide", refreshSoon)
			end
		end
		local sp = _G.LFGListFrame and LFGListFrame.SearchPanel
		if sp then sp:HookScript("OnShow", refreshSoon) sp:HookScript("OnHide", refreshSoon) end
		-- Re-tint Blizzard rows when its list scrolls or redraws.
		local box = (_G.LFGBrowseFrame and LFGBrowseFrame.ScrollBox) or (sp and sp.ScrollBox)
		if box and box.RegisterCallback and ScrollBoxListMixin and ScrollBoxListMixin.Event then
			pcall(box.RegisterCallback, box, ScrollBoxListMixin.Event.OnDataRangeChanged, tintBlizzardRows, panel)
		end
		return
	end
	refreshSoon()
end)
C_Timer.NewTicker(5, function() if panel:IsShown() then panel:Refresh() end end) -- ages and updates

ns.OnFeatureChanged(function(key) if key == "lfg" then refreshSoon() end end)
