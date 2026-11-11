-- Zyde_Forever: a more useful member list in the Guild & Communities window.
--   * names in class colors (online members)
--   * each member's level at the right, colored like quest difficulty
--     (green = near your level, gray = far below, red = far above)
--   * hover a member for their zone
-- Offline members stay gray, as the game shows them.

local ADDON, ns = ...

local function on() return ns.F("guildRoster") end
local safe, isSecret = ns.safe, ns.isSecret
local function plain(v) if isSecret(v) then return nil end return v end

local function classColor(classID)
	if not classID then return nil end
	local info = C_CreatureInfo and C_CreatureInfo.GetClassInfo and safe(C_CreatureInfo.GetClassInfo, classID)
	local token = info and info.classFile
	local c = token and ((C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(token))
		or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]))
	return c
end

local function isOnline(info)
	local p = plain(info.presence)
	local E = Enum and Enum.ClubMemberPresence
	if E and p then return p ~= E.Offline and p ~= E.Unknown end
	return true
end

-- Dress up one row of the member list.
local function decorate(row)
	if not (row and row.GetMemberInfo or row and row.memberInfo) then return end
	local info = row.memberInfo or (row.GetMemberInfo and safe(row.GetMemberInfo, row))
	local nameFS = row.NameFrame and row.NameFrame.Name
	if not row.zydeLevel then
		row.zydeLevel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.zydeLevel:SetPoint("RIGHT", row, "RIGHT", -6, 0)
	end
	if not on() or type(info) ~= "table" then row.zydeLevel:SetText("") return end
	local online = isOnline(info)

	-- Class color on the name (online only).
	local c = online and classColor(plain(info.classID))
	if c and nameFS then nameFS:SetTextColor(c.r, c.g, c.b) end

	-- Level at the right.
	local level = plain(info.level)
	if level and level > 0 then
		local col = GetQuestDifficultyColor and GetQuestDifficultyColor(level)
		row.zydeLevel:SetText(level)
		if online and col then row.zydeLevel:SetTextColor(col.r, col.g, col.b)
		else row.zydeLevel:SetTextColor(0.5, 0.5, 0.5) end
		-- Keep the name clear of the level.
		if nameFS and nameFS.SetPoint and not row.zydeNameFit then
			row.zydeNameFit = true
			nameFS:SetPoint("RIGHT", row.zydeLevel, "LEFT", -4, 0)
		end
	else
		row.zydeLevel:SetText("")
	end

	-- Zone in the tooltip.
	if not row.zydeHooked then
		row.zydeHooked = true
		row:HookScript("OnEnter", function(self)
			if not on() then return end
			local i = self.memberInfo or (self.GetMemberInfo and safe(self.GetMemberInfo, self))
			local zone = type(i) == "table" and plain(i.zone)
			if type(zone) == "string" and zone ~= "" and GameTooltip:IsOwned(self) then
				GameTooltip:AddLine("Zone: " .. zone, 1, 0.82, 0)
				GameTooltip:Show()
			end
		end)
	end
end

local function decorateAll()
	local list = CommunitiesFrame and CommunitiesFrame.MemberList
	local box = list and list.ScrollBox
	if box and box.EnumerateFrames then
		for _, row in box:EnumerateFrames() do pcall(decorate, row) end
	end
end

local hooked = false
local function hookCommunities()
	if hooked or not CommunitiesFrame then return end
	hooked = true
	-- Rows are reused as the list scrolls and refreshes: dress each again.
	if CommunitiesMemberListEntryMixin and CommunitiesMemberListEntryMixin.SetMember then
		hooksecurefunc(CommunitiesMemberListEntryMixin, "SetMember", function(row) pcall(decorate, row) end)
	end
	local list = CommunitiesFrame.MemberList
	if list then
		for _, m in ipairs({ "Update", "RefreshListDisplay", "RefreshLayout" }) do
			if type(list[m]) == "function" then hooksecurefunc(list, m, function() C_Timer.After(0, decorateAll) end) end
		end
		if list.ScrollBox and list.ScrollBox.RegisterCallback and ScrollBoxListMixin and ScrollBoxListMixin.Event then
			pcall(list.ScrollBox.RegisterCallback, list.ScrollBox, ScrollBoxListMixin.Event.OnDataRangeChanged,
				function() C_Timer.After(0, decorateAll) end, "ZydeForeverGuild")
		end
	end
	CommunitiesFrame:HookScript("OnShow", function() C_Timer.After(0.1, decorateAll) end)
	C_Timer.After(0.1, decorateAll)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("CLUB_MEMBER_PRESENCE_UPDATED")
ev:RegisterEvent("GUILD_ROSTER_UPDATE")
ev:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" and name ~= "Blizzard_Communities" then return end
	hookCommunities()
	if CommunitiesFrame and CommunitiesFrame:IsShown() then C_Timer.After(0, decorateAll) end
end)

ns.OnFeatureChanged(function(key) if key == "guildRoster" then decorateAll() end end)
