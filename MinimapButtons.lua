-- Zyde_Forever: one button on the minimap for the other addon buttons, and a
-- key that shows those plus the game menu at the cursor while it is held.
--
-- Click the button on the minimap to spread the gathered buttons out beside
-- it. Drag the button around the minimap to move it. Hold "Buttons at
-- cursor" (Options > Keybindings > Zyde Forever) and a panel opens at the
-- mouse: tradeskills, then the game menu, then the minimap buttons, then
-- addons. Let go and it closes.
--
-- Addon buttons are taken off the minimap and kept here. The game menu
-- buttons stay where they are; the panel clicks them, so this still works
-- when "Hide micro menu" has put that bar away.

local ADDON, ns = ...
local safe, isSecret = ns.safe, ns.isSecret
local function plain(v) if isSecret(v) then return nil end return v end

-- Wide enough that each button's own ring stays on its icon, not the next one.
local CELL, GAP, PAD = 40, 8, 12
local PURPLE = { 0.69, 0.35, 1 }
local GOLD = { 1, 0.84, 0.35 }

local function on() return ns.F("buttonBag") end

local function font(fs, size)
	if not fs:SetFont("Fonts\\FRIZQT__.TTF", size, "THICKOUTLINE") then
		fs:SetFontObject("GameFontHighlight")
	end
end

local function edgeColor(edges, r, g, b, a)
	for _, t in ipairs(edges) do t:SetColorTexture(r, g, b, a or 1) end
end

-- Forever's micro menu, in the order it sits on the bar.
local MENU_ORDER = {
	"CharacterMicroButton", "ProfessionMicroButton", "SpellbookMicroButton",
	"TalentMicroButton", "LegacyMicroButton", "QuestLogMicroButton",
	"GuildMicroButton", "LFDMicroButton", "CollectionsMicroButton",
	"StoreMicroButton", "MainMenuMicroButton",
}
local MENU_TIP = {
	CharacterMicroButton = "Character Info", ProfessionMicroButton = "Professions",
	SpellbookMicroButton = "Spellbook", TalentMicroButton = "Talents",
	LegacyMicroButton = "Legacy", QuestLogMicroButton = "Quest Log",
	GuildMicroButton = "Guild & Communities", LFDMicroButton = "Group Finder",
	CollectionsMicroButton = "Account Collections", StoreMicroButton = "Shop",
	MainMenuMicroButton = "Game Menu",
	ZydeForeverDungeonJournal = "Dungeon Journal",
}
-- What is painted on the tile. The tooltip keeps the full name above.
local MENU_SHORT = {
	CharacterMicroButton = "Character", ProfessionMicroButton = "Professions",
	SpellbookMicroButton = "Spellbook", TalentMicroButton = "Talents",
	LegacyMicroButton = "Legacy", QuestLogMicroButton = "Quests",
	GuildMicroButton = "Guild", LFDMicroButton = "Finder",
	CollectionsMicroButton = "Collections", StoreMicroButton = "Shop",
	MainMenuMicroButton = "Menu",
	ZydeForeverDungeonJournal = "Journal",
}
-- The same commands the game's own menu uses, so the tooltip can show that key.
local MENU_BIND = {
	CharacterMicroButton = { "TOGGLECHARACTER0" },
	ProfessionMicroButton = { "TOGGLEPROFESSIONBOOK", "TOGGLEPROFESSIONS" },
	SpellbookMicroButton = { "TOGGLESPELLBOOK" },
	TalentMicroButton = { "TOGGLETALENTS" },
	LegacyMicroButton = { "TOGGLELEGACYSYSTEM" },
	QuestLogMicroButton = { "TOGGLEQUESTLOG" },
	GuildMicroButton = { "TOGGLEGUILDTAB", "TOGGLESOCIAL" },
	LFDMicroButton = { "TOGGLEGROUPFINDER", "TOGGLELFGPARENT", "TOGGLELFG" },
	CollectionsMicroButton = { "TOGGLECOLLECTIONS" },
	StoreMicroButton = { "TOGGLESTORE" },
	MainMenuMicroButton = { "TOGGLEGAMEMENU" },
}

-- The real menu button is often hidden or ignores Click(). Run the same toggle
-- its hotkey runs. The first function that exists on this client wins.
local function tryCall(fn, ...)
	if type(fn) ~= "function" then return false end
	return pcall(fn, ...)
end

local function pressMenu(name)
	if name == "CharacterMicroButton" then
		return tryCall(ToggleCharacter, "PaperDollFrame")
	elseif name == "SpellbookMicroButton" then
		return tryCall(ToggleSpellBook, BOOKTYPE_SPELL or "spell")
	elseif name == "ProfessionMicroButton" then
		if tryCall(ToggleSpellBook, BOOKTYPE_PROFESSION or "professions") then return true end
		return tryCall(ToggleProfessionsBook)
	elseif name == "TalentMicroButton" or name == "PlayerSpellsMicroButton" then
		if tryCall(ToggleTalentFrame) then return true end
		local util = PlayerSpellsUtil
		return util and tryCall(util.TogglePlayerSpellsFrame) or false
	elseif name == "LegacyMicroButton" then
		if tryCall(ToggleLegacySystem) then return true end
		local frame = _G.LegacyFrame
		if frame and frame.IsShown and frame.Show and frame.Hide then
			if frame:IsShown() then frame:Hide() else frame:Show() end
			return true
		end
	elseif name == "QuestLogMicroButton" then
		return tryCall(ToggleQuestLog)
	elseif name == "SocialsMicroButton" or name == "FriendsMicroButton" then
		if tryCall(ToggleFriendsFrame, 1) then return true end
		return tryCall(ToggleChannelFrame)
	elseif name == "GuildMicroButton" then
		if tryCall(ToggleGuildFrame) then return true end
		return tryCall(ToggleFriendsFrame, 3)
	elseif name == "LFDMicroButton" or name == "LFGMicroButton" then
		if tryCall(PVEFrame_ToggleFrame) then return true end
		if tryCall(ToggleLFDParentFrame) then return true end
		return tryCall(ToggleLFGParentFrame)
	elseif name == "WorldMapMicroButton" then
		if tryCall(ToggleWorldMap) then return true end
		if WorldMapFrame and WorldMapFrame.IsShown then
			if WorldMapFrame:IsShown() then WorldMapFrame:Hide() else WorldMapFrame:Show() end
			return true
		end
	elseif name == "EJMicroButton" then
		return tryCall(ToggleEncounterJournal)
	elseif name == "CollectionsMicroButton" then
		if tryCall(ToggleCollectionsJournal) then return true end
		if tryCall(ToggleMountJournal) then return true end
		return tryCall(TogglePetJournal)
	elseif name == "MainMenuMicroButton" then
		return tryCall(ToggleGameMenu)
	elseif name == "HelpMicroButton" then
		return tryCall(ToggleHelpFrame)
	elseif name == "StoreMicroButton" then
		return tryCall(ToggleStoreUI)
	end
	return false
end

---------------------------------------------------------------------------
-- The button on the minimap, the strip that opens beside it, and the panel
-- that opens at the cursor.
---------------------------------------------------------------------------
local toggle = CreateFrame("Button", "ZydeForeverMinimapBag", Minimap)
toggle:SetSize(36, 36)
toggle:SetFrameStrata("MEDIUM")
toggle:SetFrameLevel(8)
toggle:RegisterForClicks("LeftButtonUp")
toggle:RegisterForDrag("LeftButton")
toggle:SetClampedToScreen(false)

local icon = toggle:CreateTexture(nil, "ARTWORK")
icon:SetAllPoints()
icon:SetTexture("Interface\\AddOns\\Zyde_Forever\\Media\\Minimap")
local hl = toggle:CreateTexture(nil, "HIGHLIGHT")
hl:SetAllPoints()
hl:SetTexture("Interface\\AddOns\\Zyde_Forever\\Media\\Minimap")
hl:SetBlendMode("ADD")
hl:SetAlpha(0.4)

local flyout = CreateFrame("Frame", "ZydeForeverMinimapBagFlyout", UIParent)
flyout:SetFrameStrata("HIGH")
flyout:SetClampedToScreen(true)
flyout:EnableMouse(true)
flyout:Hide()
flyout.bg = flyout:CreateTexture(nil, "BACKGROUND")
flyout.bg:SetAllPoints()
flyout.bg:SetColorTexture(0.07, 0.07, 0.08, 0.96)
flyout.edges = ns.newEdges(flyout, "OVERLAY", 1)
edgeColor(flyout.edges, PURPLE[1], PURPLE[2], PURPLE[3], 0.9)
flyout.note = flyout:CreateFontString(nil, "OVERLAY")
font(flyout.note, 12)
flyout.note:SetPoint("CENTER")
flyout.note:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
flyout.note:SetText("No addon buttons yet")
flyout.note:Hide()
flyout.head = flyout:CreateFontString(nil, "OVERLAY")
font(flyout.head, 12)
flyout.head:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
flyout.head:SetText("Other Addons")
flyout.head:Hide()
flyout.rule = flyout:CreateTexture(nil, "ARTWORK")
flyout.rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.55)
flyout.rule:Hide()

local popup = CreateFrame("Frame", "ZydeForeverButtonBagPopup", UIParent)
popup:SetFrameStrata("DIALOG")
popup:SetFrameLevel(40)
popup:SetClampedToScreen(true)
popup:EnableMouse(false)
popup:Hide()
popup.bg = popup:CreateTexture(nil, "BACKGROUND")
popup.bg:SetAllPoints()
popup.bg:Hide()
popup.edges = ns.newEdges(popup, "OVERLAY", 1)
for _, t in ipairs(popup.edges) do t:Hide() end
popup.rule = popup:CreateTexture(nil, "ARTWORK")
popup.rule:Hide()
popup.rule2 = popup:CreateTexture(nil, "ARTWORK")
popup.rule2:Hide()
-- A disc behind the rings. The mask turns the square texture into a circle.
popup.rim = popup:CreateTexture(nil, "BACKGROUND", nil, -8)
popup.rim:Hide()
popup.disc = popup:CreateTexture(nil, "BACKGROUND", nil, -7)
popup.disc:SetColorTexture(0, 0, 0, 0.35)
local function maskCircle(tex)
	if not (popup.CreateMaskTexture and tex.AddMaskTexture) then return false end
	local mask = popup:CreateMaskTexture()
	local ok = pcall(mask.SetTexture, mask, "Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	if not ok and mask.SetAtlas then ok = pcall(mask.SetAtlas, mask, "CircleMask") end
	if not ok then return false end
	mask:SetAllPoints(tex)
	return pcall(tex.AddMaskTexture, tex, mask)
end
popup.circle = maskCircle(popup.disc)
popup.rim:Hide()
tinsert(UISpecialFrames, "ZydeForeverButtonBagPopup")

-- Full-screen catcher, only while the cursor panel is open. Hidden frames
-- don't take clicks; an invisible one left up would.
local catcher = CreateFrame("Button", nil, UIParent)
catcher:SetAllPoints()
-- Below the gathered buttons. A dialog-level catcher sits on top of any
-- minimap button whose strata is locked, and the click closes the wheel
-- instead of pressing the button. Empty space still falls through to this.
catcher:SetFrameStrata("LOW")
catcher:SetFrameLevel(1)
catcher:EnableMouse(true)
catcher:RegisterForClicks("AnyDown")
catcher:Hide()

-- The key. Off the screen so the invisible button can't sit on a click.
_G["BINDING_NAME_CLICK ZydeForeverButtonBagKey:LeftButton"] = "Buttons at cursor (hold)"
local key = CreateFrame("Button", "ZydeForeverButtonBagKey", UIParent)
key:SetSize(1, 1)
key:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -20, 20)
key:RegisterForClicks("AnyDown", "AnyUp")

---------------------------------------------------------------------------
-- Addon buttons gathered off the minimap.
---------------------------------------------------------------------------
local collected = {}
local laying = false
local pending = false
local flyoutWasOpen = false

local function angle()
	local db = ZydeForeverDB
	local a = db and db.minimapBagAngle
	if type(a) ~= "number" then return 212 end
	return a
end

-- On a square map the corner sticks out past the circle the button was built for.
-- Sit just outside that corner so the icon is not covered.
local function orbitRadius(rad)
	local half = Minimap:GetWidth()
	if ns.isSecret(half) or type(half) ~= "number" then return 80 end
	half = half / 2
	if ns.MinimapLook and ns.MinimapLook.Get and ns.MinimapLook.Get() == "square" then
		if not rad then rad = math.rad(angle()) end
		local ax = math.abs(math.cos(rad))
		local ay = math.abs(math.sin(rad))
		local edge = half / math.max(ax, ay, 0.01)
		return edge + 22
	end
	return half + 6
end

local function placeToggle()
	if not Minimap or toggle.dragging then return end
	local rad = math.rad(angle())
	local r = orbitRadius(rad)
	toggle:ClearAllPoints()
	toggle:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * r, math.sin(rad) * r)
end

local function anchorFlyout()
	flyout:ClearAllPoints()
	local mx, my = Minimap and Minimap:GetCenter()
	local bx, by = toggle:GetCenter()
	if not mx or not bx then
		flyout:SetPoint("RIGHT", toggle, "LEFT", -6, 0)
		return
	end
	if bx < mx then
		flyout:SetPoint("RIGHT", toggle, "LEFT", -6, 0)
	else
		flyout:SetPoint("LEFT", toggle, "RIGHT", 6, 0)
	end
	ns.placeEdges(flyout.edges, flyout, -1, 1)
end

local function displayName(frame)
	local n = frame:GetName() or ""
	n = n:gsub("^LibDBIcon10_", "")
	n = n:gsub("[_%-]?[Mm]inimap[Bb]utton$", "")
	n = n:gsub("[_%-]?[Mm]inimap[Ii]con$", "")
	n = n:gsub("_", " ")
	if n == "" then n = "Addon" end
	return n
end

local function plainName(s)
	if type(s) ~= "string" then return "" end
	return s:lower():gsub("[^%w]", "")
end

local function texKey(tex)
	if type(tex) == "number" then return tostring(tex) end
	if type(tex) ~= "string" or tex == "" then return nil end
	return tex:lower()
end

-- Names and icons already sitting in the gathered row, so the compartment
-- list does not paint that addon a second time.
local function gatheredMarks()
	local names, icons = {}, {}
	for _, frame in ipairs(collected) do
		local n = plainName(displayName(frame))
		if n ~= "" then names[n] = true end
		local raw = frame.GetName and frame:GetName()
		if type(raw) == "string" then
			local p = plainName(raw:gsub("^LibDBIcon10_", ""))
			if p ~= "" then names[p] = true end
		end
		local icon = frame and (frame.icon or frame.Icon)
		if icon and icon.GetTexture then
			local ok, t = pcall(icon.GetTexture, icon)
			if ok then
				local key = texKey(t)
				if key then icons[key] = true end
			end
		end
		local data = frame.dataObject
		if type(data) == "table" then
			local key = texKey(data.icon)
			if key then icons[key] = true end
		end
	end
	return names, icons
end

local function uniqueButtons(list)
	local seen, out = {}, {}
	for _, frame in ipairs(list) do
		local raw = frame.GetName and frame:GetName()
		local name = (type(raw) == "string" and raw ~= "") and plainName(displayName(frame)) or ""
		if name ~= "" and seen[name] then
			laying = true
			frame:Hide()
			laying = false
		else
			if name ~= "" then seen[name] = true end
			out[#out + 1] = frame
		end
	end
	return out
end

local function sorted()
	table.sort(collected, function(a, b) return displayName(a) < displayName(b) end)
	return collected
end

-- Keep the button where we put it, the way MinimapButtonButton does. The fade
-- is separate: a lot of these buttons dim themselves when the cursor leaves.
local layoutFlyout, layoutPopup

local function lock(frame)
	if frame.zydeLocked then return end
	frame.zydeLocked = true
	local setPoint, clear = frame.SetPoint, frame.ClearAllPoints
	local setParent, hide = frame.SetParent, frame.Hide
	local setScale = frame.SetScale
	local setStrata, setLevel = frame.SetFrameStrata, frame.SetFrameLevel
	local setFixedStrata, setFixedLevel = frame.SetFixedFrameStrata, frame.SetFixedFrameLevel
	local setClamp = frame.SetClampedToScreen
	local function pass(self)
		return laying or not self.zydeOwned
	end
	frame.SetPoint = function(self, ...) if pass(self) then return setPoint(self, ...) end end
	frame.ClearAllPoints = function(self, ...) if pass(self) then return clear(self, ...) end end
	frame.SetParent = function(self, ...) if pass(self) then return setParent(self, ...) end end
	frame.Hide = function(self, ...) if pass(self) then return hide(self, ...) end end
	frame.SetScale = function(self, ...) if pass(self) then return setScale(self, ...) end end
	frame.SetFrameStrata = function(self, ...) if pass(self) then return setStrata(self, ...) end end
	frame.SetFrameLevel = function(self, ...) if pass(self) then return setLevel(self, ...) end end
	if setFixedStrata then
		frame.SetFixedFrameStrata = function(self, ...) if pass(self) then return setFixedStrata(self, ...) end end
	end
	if setFixedLevel then
		frame.SetFixedFrameLevel = function(self, ...) if pass(self) then return setFixedLevel(self, ...) end end
	end
	if setClamp then
		frame.SetClampedToScreen = function(self, ...) if pass(self) then return setClamp(self, ...) end end
	end
end

-- A mouseover fade hides the button a second after the cursor leaves. Stopping
-- that animation while it is set to keep its final alpha snaps the icon to
-- invisible and back. Flatten the fade first, so a stop lands on fully visible.
local function animsOf(group)
	if not group or not group.GetAnimations then return {} end
	local first = group:GetAnimations()
	if type(first) == "table" then return first end
	return { group:GetAnimations() }
end

local function flatten(group)
	if not group then return end
	if group.SetToFinalAlpha then group:SetToFinalAlpha(false) end
	for _, anim in ipairs(animsOf(group)) do
		if anim.SetFromAlpha then anim:SetFromAlpha(1) end
		if anim.SetToAlpha then anim:SetToAlpha(1) end
		if anim.SetDuration then anim:SetDuration(0) end
		if anim.SetStartDelay then anim:SetStartDelay(0) end
	end
end

local function rememberFade(frame, group)
	if not group or group.zydeFrozen then return end
	group.zydeFrozen = true
	local saved = frame.zydeFades
	if not saved then
		saved = {}
		frame.zydeFades = saved
	end
	local rec = {
		group = group,
		final = group.GetToFinalAlpha and group:GetToFinalAlpha(),
		anims = {},
	}
	for _, anim in ipairs(animsOf(group)) do
		rec.anims[#rec.anims + 1] = {
			anim = anim,
			from = anim.GetFromAlpha and anim:GetFromAlpha(),
			to = anim.GetToAlpha and anim:GetToAlpha(),
			dur = anim.GetDuration and anim:GetDuration(),
			delay = anim.GetStartDelay and anim:GetStartDelay(),
		}
	end
	saved[#saved + 1] = rec
	if group.Play and not group.zydePlay then
		group.zydePlay = true
		local play = group.Play
		group.Play = function(self, ...)
			if frame.zydeOwned and not laying then return end
			return play(self, ...)
		end
	end
	if group.HookScript and not group.zydeHooked then
		group.zydeHooked = true
		group:HookScript("OnPlay", function(self)
			if not frame.zydeOwned or laying or self.zydeStopping then return end
			self.zydeStopping = true
			flatten(self)
			if self.Stop then self:Stop() end
			self.zydeStopping = false
			if (frame:GetAlpha() or 1) < 0.99 then frame:SetAlpha(1) end
		end)
	end
end

local function pinAlpha(region, owner)
	if not region or not region.SetAlpha or region.zydeAlpha then return end
	region.zydeAlpha = true
	local setAlpha = region.SetAlpha
	region.SetAlpha = function(self, a, ...)
		if owner.zydeOwned and not laying and type(a) == "number" and a < 0.99 then
			if (self:GetAlpha() or 1) < 0.99 then return setAlpha(self, 1) end
			return
		end
		return setAlpha(self, a, ...)
	end
end

local function holdOpen(frame)
	local saved = frame.zydeSaved
	if frame.showOnMouseover then
		if saved then saved.showOnMouseover = true end
		frame.showOnMouseover = false
	end
	pinAlpha(frame, frame)
	pinAlpha(frame.icon, frame)
	if frame.fadeOut then rememberFade(frame, frame.fadeOut) end
	if frame.GetAnimationGroups then
		for _, group in ipairs({ frame:GetAnimationGroups() }) do
			rememberFade(frame, group)
		end
	end
	local function releaseFade(group)
		if not group or not group.Stop or group.zydeStopping then return end
		group.zydeStopping = true
		flatten(group)
		group:Stop()
		group.zydeStopping = false
	end
	releaseFade(frame.fadeOut)
	if frame.GetAnimationGroups then
		for _, group in ipairs({ frame:GetAnimationGroups() }) do
			releaseFade(group)
		end
	end
	-- Clear the flag before the button's own enter/leave reads it. That read
	-- is what starts the fade on every button, not just the one under the cursor.
	if not frame.zydeHover then
		frame.zydeHover = true
		local enter, leave = frame:GetScript("OnEnter"), frame:GetScript("OnLeave")
		frame:SetScript("OnEnter", function(self, ...)
			for i = 1, #collected do
				local other = collected[i]
				if other.zydeOwned then other.showOnMouseover = false end
			end
			if enter then return enter(self, ...) end
		end)
		frame:SetScript("OnLeave", function(self, ...)
			for i = 1, #collected do
				local other = collected[i]
				if other.zydeOwned then other.showOnMouseover = false end
			end
			if leave then leave(self, ...) end
			if self.zydeOwned and (self:GetAlpha() or 1) < 0.99 then self:SetAlpha(1) end
			-- Their leave handler turns clicks off, the way it does when the
			-- cursor leaves the minimap. The first press then does nothing.
			if self.zydeOwned then
				if self.EnableMouse then self:EnableMouse(true) end
				if self.SetMouseClickEnabled then self:SetMouseClickEnabled(true) end
			end
		end)
	end
end

local function armClicks(frame)
	if frame.Enable then frame:Enable() end
	if frame.EnableMouse then frame:EnableMouse(true) end
	if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(true) end
	if frame.SetMouseMotionEnabled then frame:SetMouseMotionEnabled(true) end
	-- Drag is why the first click after a move never opens: that press is
	-- taken as the start of a drag. Clicks work once dragging is off.
	if frame.zydeDragCleared or not frame.RegisterForDrag then return end
	if frame.GetScript and frame:GetScript("OnDragStart") then
		frame.zydeDragCleared = true
		frame:RegisterForDrag()
	end
end

local function thaw(frame)
	for _, rec in ipairs(frame.zydeFades or {}) do
		local group = rec.group
		if group and group.SetToFinalAlpha then group:SetToFinalAlpha(rec.final and true or false) end
		for _, anim in ipairs(rec.anims) do
			if anim.from and anim.anim.SetFromAlpha then anim.anim:SetFromAlpha(anim.from) end
			if anim.to and anim.anim.SetToAlpha then anim.anim:SetToAlpha(anim.to) end
			if anim.dur and anim.anim.SetDuration then anim.anim:SetDuration(anim.dur) end
			if anim.delay and anim.anim.SetStartDelay then anim.anim:SetStartDelay(anim.delay) end
		end
		if group then group.zydeFrozen = nil end
	end
	frame.zydeFades = nil
end

-- Leaving the minimap fades every mouseover button. The panel is not the minimap,
-- so that leave must not win while we are showing them.
if Minimap and Minimap.HookScript then
	Minimap:HookScript("OnLeave", function()
		if laying then return end
		for i = 1, #collected do
			local frame = collected[i]
			if frame.zydeOwned then
				frame.showOnMouseover = false
				local group = frame.fadeOut
				if group and group.IsPlaying and group:IsPlaying() and not group.zydeStopping then
					group.zydeStopping = true
					flatten(group)
					if group.Stop then group:Stop() end
					group.zydeStopping = false
				end
				if (frame:GetAlpha() or 1) < 0.99 then frame:SetAlpha(1) end
			end
		end
	end)
end

local function park(frame, parent, left, top)
	local saved = frame.zydeSaved
	lock(frame)
	laying = true
	if frame.SetFixedFrameStrata then frame:SetFixedFrameStrata(false) end
	if frame.SetFixedFrameLevel then frame:SetFixedFrameLevel(false) end
	if frame.SetClampedToScreen then frame:SetClampedToScreen(false) end
	frame:SetParent(parent)
	frame:SetScale(saved and saved.scale or 1)
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", parent, "TOPLEFT", left + CELL / 2, -(top + CELL / 2))
	frame:SetFrameStrata(parent:GetFrameStrata() or "HIGH")
	frame:SetFrameLevel((parent:GetFrameLevel() or 1) + 8)
	holdOpen(frame)
	frame:SetAlpha(1)
	armClicks(frame)
	frame:Show()
	laying = false
end

local function schedule()
	if pending or laying or not on() then return end
	pending = true
	C_Timer.After(0, function()
		pending = false
		if not on() then return end
		if popup:IsShown() then layoutPopup() else layoutFlyout() end
	end)
end

local function watch(frame)
	if frame.zydeWatched then return end
	frame.zydeWatched = true
	lock(frame)
	if not (frame.IsProtected and frame:IsProtected()) then
		local function closeWheel()
			if popup:IsShown() then
				C_Timer.After(0, function()
					if popup:IsShown() then popup:Hide() end
				end)
			end
		end
		frame:HookScript("OnClick", closeWheel)
		frame:HookScript("OnMouseUp", closeWheel)
	end
end

local function release(frame)
	local saved = frame.zydeSaved
	frame.zydeOwned = false
	if not saved then return end
	laying = true
	local parent = saved.parent
	if not parent or not parent.SetParent then parent = Minimap end
	frame:SetParent(parent)
	frame:SetScale(saved.scale or 1)
	frame:ClearAllPoints()
	if saved.points and #saved.points > 0 then
		for _, p in ipairs(saved.points) do
			-- relativeTo can be missing; a hole in the table would drop the offsets
			if p[2] then frame:SetPoint(p[1], p[2], p[3], p[4] or 0, p[5] or 0)
			else frame:SetPoint(p[1], p[4] or 0, p[5] or 0) end
		end
	elseif Minimap then
		frame:SetPoint("CENTER", Minimap, "CENTER", -80, -20)
	end
	if saved.strata then pcall(frame.SetFrameStrata, frame, saved.strata) end
	if saved.level then pcall(frame.SetFrameLevel, frame, saved.level) end
	if frame.SetFixedFrameStrata then frame:SetFixedFrameStrata(saved.fixedStrata and true or false) end
	if frame.SetFixedFrameLevel then frame:SetFixedFrameLevel(saved.fixedLevel and true or false) end
	if frame.SetClampedToScreen then frame:SetClampedToScreen(saved.clamped and true or false) end
	thaw(frame)
	if frame.zydeDragCleared and frame.RegisterForDrag then
		frame:RegisterForDrag("LeftButton")
		frame.zydeDragCleared = nil
	end
	if saved.showOnMouseover then frame.showOnMouseover = true end
	if frame.zydeRing then frame.zydeRing:Hide() end
	if saved.shown == false then frame:Hide() else frame:Show() end
	laying = false
end

local function releaseAll()
	for i = #collected, 1, -1 do
		release(collected[i])
		collected[i] = nil
	end
end

-- Blizzard chrome that lives on the minimap and should stay there.
local function blizzardName(name)
	if name:find("ZydeForever", 1, true) then return true end
	if name:find("LandingPage", 1, true) then return true end
	if name:find("QueueStatus", 1, true) then return true end
	if name:find("InstanceDifficulty", 1, true) then return true end
	if name:sub(1, 7) == "MiniMap" then return true end
	if name:sub(1, 8) == "GameTime" then return true end
	if name:sub(1, 11) == "TimeManager" then return true end
	if name:sub(1, 11) == "GarrisonLand" then return true end
	if name:sub(1, 16) == "AddonCompartment" then return true end
	-- MinimapZoomIn, MinimapBackdrop, MinimapBorder, and the rest of the
	-- map's own frames. Addon buttons are named ...MinimapButton.
	if name:sub(1, 7) == "Minimap" and not name:find("MinimapButton", 1, true) and not name:find("LibDBIcon", 1, true) then
		return true
	end
end

local function onMinimap(frame)
	local p = frame:GetParent()
	if not p then return false end
	if p == Minimap or p == MinimapCluster or p == MinimapBackdrop then return true end
	local gp = p.GetParent and p:GetParent()
	return gp == Minimap or gp == MinimapCluster
end

local function isCandidate(frame)
	if type(frame) ~= "table" or not frame.GetName or not frame.IsObjectType then return false end
	if frame.IsForbidden and frame:IsForbidden() then return false end
	if frame.IsProtected and frame:IsProtected() then return false end
	if frame.zydeOwned then return false end
	local name = frame:GetName()
	if not name or blizzardName(name) then return false end
	if not frame:IsObjectType("Button") then return false end
	if not onMinimap(frame) then return false end
	if not frame:IsShown() then return false end
	local addonNamed = name:find("LibDBIcon", 1, true) or name:find("MinimapButton", 1, true) or name:find("MinimapIcon", 1, true)
	local w, h = frame:GetWidth() or 0, frame:GetHeight() or 0
	if addonNamed then
		if w < 12 or h < 12 or w > 80 or h > 80 then return false end
	elseif w < 18 or h < 18 or w > 48 or h > 48 then
		return false
	end
	return true
end

local function grab(frame, force)
	if type(frame) ~= "table" or frame.zydeOwned then return false end
	if not force and not isCandidate(frame) then return false end
	if force then
		if not frame.IsObjectType or not frame:IsObjectType("Button") then return false end
		if frame.IsForbidden and frame:IsForbidden() then return false end
		if frame.IsProtected and frame:IsProtected() then return false end
	end
	local points = {}
	for i = 1, frame:GetNumPoints() do
		local point, rel, relPoint, x, y = frame:GetPoint(i)
		points[i] = { point, rel, relPoint or point, x or 0, y or 0 }
	end
	-- LibDBIcon locks strata and level. SetFrameStrata is then ignored, so the
	-- button stays under this panel's background: visible only as a ghost, and
	-- the panel takes the click. Probe before we wrap the methods.
	local function stuck(getter, fixer, read, write, trial)
		if not fixer then return false end
		if getter then return getter(frame) and true or false end
		local before = read(frame)
		write(frame, trial(before))
		local locked = read(frame) == before
		write(frame, before)
		return locked
	end
	frame.zydeSaved = {
		parent = frame:GetParent(),
		points = points,
		scale = frame:GetScale(),
		shown = frame:IsShown() and true or false,
		strata = frame:GetFrameStrata(),
		level = frame:GetFrameLevel(),
		w = frame:GetWidth(),
		h = frame:GetHeight(),
		clamped = frame.IsClampedToScreen and frame:IsClampedToScreen() or false,
		fixedStrata = stuck(frame.IsFixedFrameStrata, frame.SetFixedFrameStrata, frame.GetFrameStrata, frame.SetFrameStrata, function(s)
			return s == "HIGH" and "MEDIUM" or "HIGH"
		end),
		fixedLevel = stuck(frame.IsFixedFrameLevel, frame.SetFixedFrameLevel, frame.GetFrameLevel, frame.SetFrameLevel, function(n)
			return n == 1 and 2 or 1
		end),
	}
	frame.zydeOwned = true
	collected[#collected + 1] = frame
	watch(frame)
	return true
end

local function scan()
	if not on() or not Minimap then return end
	local found = false
	local function walk(root, depth)
		if not root or not root.GetChildren or depth > 2 then return end
		for _, child in ipairs({ root:GetChildren() }) do
			if grab(child) then
				found = true
			else
				local name = child.GetName and child:GetName()
				if not name or not blizzardName(name) then walk(child, depth + 1) end
			end
		end
	end
	walk(Minimap, 0)
	walk(MinimapCluster, 0)
	walk(MinimapBackdrop, 0)
	-- Addons that registered with the "9" compartment instead of leaving a button on the map.
	local lib = LibStub and LibStub("LibDBIcon-1.0", true)
	local objects = lib and lib.objects
	local reg = AddonCompartmentFrame and AddonCompartmentFrame.registeredAddons
	if type(reg) == "table" and objects then
		for _, entry in ipairs(reg) do
			local text = entry and entry.text
			local button = type(text) == "string" and objects[text]
			if button and grab(button, true) then found = true end
		end
	end
	local compartment = AddonCompartmentFrame
	if on() and compartment then
		if not compartment.zydeBagHook then
			compartment.zydeBagHook = true
			compartment:HookScript("OnShow", function(self)
				if on() then self:Hide() end
			end)
		end
		compartment:Hide()
	end
	placeToggle()
	if found then schedule() end
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------
-- Compartment entries that have no real minimap button. Same icons in the
-- pull-out and in the popup.
local compPool = {}
local function compartmentButtons()
	local reg = AddonCompartmentFrame and AddonCompartmentFrame.registeredAddons
	local list = {}
	if type(reg) ~= "table" then return list end
	local lib = LibStub and LibStub("LibDBIcon-1.0", true)
	local objects = lib and lib.objects
	local names, icons = gatheredMarks()
	local seen, seenIcon = {}, {}
	local n = 0
	for _, entry in ipairs(reg) do
		if type(entry) == "table" then
			local text = entry.text
			local key = plainName(text)
			local icon = texKey(entry.icon)
			local real = objects and type(text) == "string" and objects[text]
			local owned = real and real.zydeOwned and true or false
			if not owned and objects and key ~= "" then
				for objName, button in pairs(objects) do
					if type(button) == "table" and button.zydeOwned and (button.compartmentData == entry or plainName(objName) == key) then
						owned = true
						break
					end
				end
			end
			if not owned and key ~= "" and (names[key] or seen[key]) then owned = true end
			if not owned and icon and (icons[icon] or seenIcon[icon]) then owned = true end
			if not owned then
				if key ~= "" then seen[key] = true end
				if icon then seenIcon[icon] = true end
				n = n + 1
				local b = compPool[n]
				if not b then
					b = CreateFrame("Button", nil, UIParent)
					b:SetSize(31, 31)
					b:RegisterForClicks("AnyUp")
					b:EnableMouse(true)
					b.zydeCompartment = true
					-- The other minimap buttons show a small icon inside the frame.
					b.icon = b:CreateTexture(nil, "ARTWORK")
					b.icon:SetSize(17, 17)
					b.icon:SetPoint("CENTER")
					b:SetScript("OnClick", function(self, mouseButton)
						local item = self.entry
						local func = item and item.func
						if type(func) == "function" then
							local input = { buttonName = mouseButton or "LeftButton" }
							if not pcall(func, self, input, item) then
								pcall(func, self, mouseButton)
							end
						end
						if popup:IsShown() then popup:Hide() end
					end)
					b:SetScript("OnEnter", function(self)
						local item = self.entry
						if item and type(item.funcOnEnter) == "function" then
							pcall(item.funcOnEnter, self, item)
						end
						if GameTooltip:IsShown() then return end
						GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
						local name = item and item.text
						GameTooltip:AddLine(type(name) == "string" and name or "Addon", GOLD[1], GOLD[2], GOLD[3])
						GameTooltip:Show()
					end)
					b:SetScript("OnLeave", function(self)
						local item = self.entry
						if item and type(item.funcOnLeave) == "function" then
							pcall(item.funcOnLeave, self, item)
						end
						GameTooltip:Hide()
					end)
					compPool[n] = b
				end
				b.entry = entry
				local icon = entry.icon
				if type(icon) == "string" or type(icon) == "number" then
					b.icon:SetTexture(icon)
				else
					b.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
				end
				b.icon:ClearAllPoints()
				b.icon:SetSize(17, 17)
				b.icon:SetPoint("CENTER")
				b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				list[#list + 1] = b
			end
		end
	end
	for i = n + 1, #compPool do compPool[i]:Hide() end
	return list
end

local function placeProxy(frame, parent, left, top)
	frame:SetParent(parent)
	frame:SetScale(1)
	frame:SetSize(31, 31)
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", parent, "TOPLEFT", left + CELL / 2, -(top + CELL / 2))
	frame:SetFrameStrata(parent:GetFrameStrata() or "HIGH")
	frame:SetFrameLevel((parent:GetFrameLevel() or 1) + 8)
	frame:Show()
end

-- Same slot as the gathered buttons. The icon stays the small size set above.
local function placeAddon(frame, x, y, scale)
	frame:SetParent(popup)
	frame:SetScale(scale or 1)
	frame:SetSize(31, 31)
	frame:ClearAllPoints()
	local s = frame:GetScale()
	if not s or s == 0 then s = 1 end
	frame:SetPoint("TOPLEFT", popup, "TOPLEFT", x / s, -y / s)
	frame:SetFrameStrata(popup:GetFrameStrata() or "DIALOG")
	frame:SetFrameLevel((popup:GetFrameLevel() or 1) + 8)
	frame:Show()
end

layoutFlyout = function()
	if popup:IsShown() then return end
	local buttons = uniqueButtons(sorted())
	local addons = compartmentButtons()
	local nb, na = #buttons, #addons
	if nb == 0 and na == 0 then
		flyout.note:Show()
		flyout.head:Hide()
		flyout.rule:Hide()
		flyout:SetSize(190, 34)
	else
		flyout.note:Hide()
		local function colsOf(n)
			if n <= 0 then return 0 end
			return n < 8 and n or 8
		end
		local function gridH(n)
			local c = colsOf(n)
			if c == 0 then return 0 end
			local rows = math.ceil(n / c)
			return rows * CELL + (rows - 1) * GAP
		end
		local cols = math.max(colsOf(nb), colsOf(na))
		local width = PAD * 2 + cols * CELL + (cols - 1) * GAP
		if na > 0 then
			local hw = (flyout.head:GetStringWidth() or 0) + PAD * 2
			if hw > width then width = hw end
		end
		local function placeGrid(list, top)
			local c = colsOf(#list)
			for i, frame in ipairs(list) do
				local col = (i - 1) % c
				local row = math.floor((i - 1) / c)
				local left = PAD + col * (CELL + GAP)
				local rowTop = top + row * (CELL + GAP)
				if frame.zydeCompartment then
					placeProxy(frame, flyout, left, rowTop)
				else
					park(frame, flyout, left, rowTop)
				end
			end
		end
		local y = PAD
		if nb > 0 then
			placeGrid(buttons, y)
			y = y + gridH(nb)
		end
		if na > 0 then
			if nb > 0 then
				y = y + 8
				flyout.rule:ClearAllPoints()
				flyout.rule:SetPoint("TOPLEFT", flyout, "TOPLEFT", PAD, -y)
				flyout.rule:SetSize(math.max(8, width - PAD * 2), 2)
				flyout.rule:Show()
				y = y + 8
			else
				flyout.rule:Hide()
			end
			flyout.head:ClearAllPoints()
			flyout.head:SetPoint("TOPLEFT", flyout, "TOPLEFT", PAD, -y)
			flyout.head:Show()
			y = y + 18
			placeGrid(addons, y)
			y = y + gridH(na)
		else
			flyout.head:Hide()
			flyout.rule:Hide()
		end
		flyout:SetSize(width, y + PAD)
	end
	anchorFlyout()
	if flyout:IsShown() then icon:SetVertexColor(GOLD[1], GOLD[2], GOLD[3]) else icon:SetVertexColor(1, 1, 1) end
end

-- The real menu button's art. These use an atlas: copying only the texture
-- file shows a dark corner of the sheet, which is why the old copies were blank.
local function applyIcon(b, real)
	local icon = b.icon
	icon:ClearAllPoints()
	icon:SetPoint("TOPLEFT", 4, -4)
	icon:SetPoint("BOTTOMRIGHT", -4, 4)
	b.bg:Show()
	for _, t in ipairs(b.edges) do t:Show() end
	if b.zydeTexture then
		icon:SetTexture(b.zydeTexture)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		return
	end
	-- The character button's own art is an empty frame. The face is the portrait.
	if b.realName == "CharacterMicroButton" then
		local painted = icon.SetPortraitTexture and pcall(icon.SetPortraitTexture, icon, "player")
		if not painted and SetPortraitTexture then painted = pcall(SetPortraitTexture, icon, "player") end
		if painted then return end
		local _, class = UnitClass("player")
		if ns.isSecret(class) then class = nil end
		local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
		if coords then
			icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
			icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
			return
		end
	end
	local function atlasOf(tex)
		if not tex or not tex.GetAtlas then return nil end
		local atlas = tex:GetAtlas()
		if type(atlas) ~= "string" or atlas == "" or ns.isSecret(atlas) then return nil end
		local low = atlas:lower()
		if low:find("background", 1, true) or low:find("buttonbg", 1, true) or low:find("empty", 1, true) then return nil end
		return atlas
	end
	local function pathOf(tex)
		if not tex or not tex.GetTexture then return nil end
		local path = tex:GetTexture()
		if not path or path == 0 or path == "" or ns.isSecret(path) then return nil end
		return path, tex
	end
	local candidates = {}
	local function add(tex)
		if tex then candidates[#candidates + 1] = tex end
	end
	if real.GetNormalTexture then add(real:GetNormalTexture()) end
	add(real.Icon)
	if type(real.texture) == "table" then add(real.texture) end
	add(real.Portrait)
	if real.GetRegions then
		for _, region in ipairs({ real:GetRegions() }) do
			if region.GetObjectType and region:GetObjectType() == "Texture" then
				local name = region.GetName and region:GetName()
				local low = type(name) == "string" and name:lower() or ""
				if not (low:find("highlight", 1, true) or low:find("flash", 1, true) or low:find("glow", 1, true) or low:find("flare", 1, true)) then add(region) end
			end
		end
	end
	local atlas, path, pathTex
	for _, tex in ipairs(candidates) do
		atlas = atlasOf(tex)
		if atlas then break end
	end
	if not atlas then
		for _, tex in ipairs(candidates) do
			path, pathTex = pathOf(tex)
			if path then break end
		end
	end
	icon:ClearAllPoints()
	icon:SetPoint("TOPLEFT", 4, -4)
	icon:SetPoint("BOTTOMRIGHT", -4, 4)
	b.bg:Show()
	for _, t in ipairs(b.edges) do t:Show() end
	if atlas and icon.SetAtlas then
		-- useAtlasSize would keep a glow atlas at its own huge size.
		icon:SetAtlas(atlas, false)
	elseif path then
		icon:SetTexture(path)
		icon:SetTexCoord(0, 1, 0, 1)
		if pathTex then
			local ok, a, c, d, e, f, g, h, i = pcall(pathTex.GetTexCoord, pathTex)
			if ok and not ns.isSecret(a) then
				if i and not ns.isSecret(i) then icon:SetTexCoord(a, c, d, e, f, g, h, i)
				elseif e and not ns.isSecret(e) then icon:SetTexCoord(a, c, d, e) end
			end
		end
	else
		icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
end

local proxies = {}
local function proxyFor(name)
	local b = proxies[name]
	if b then return b end
	if not _G[name] then return nil end
	b = CreateFrame("Button", nil, popup)
	b:SetSize(CELL - 4, CELL - 4)
	b:RegisterForClicks("AnyUp")
	b:EnableMouse(true)
	b.realName = name
	b.tip = MENU_TIP[name] or name:gsub("MicroButton$", ""):gsub("(%l)(%u)", "%1 %2")
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.bg:SetColorTexture(0, 0, 0, 0.92)
	b.edges = ns.newEdges(b, "OVERLAY", 2)
	edgeColor(b.edges, 0.85, 0.68, 0.22, 1)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 4, -4)
	b.icon:SetPoint("BOTTOMRIGHT", -4, 4)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.label:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
	b.label:SetPoint("RIGHT", -4, 0)
	b.label:SetJustifyH("LEFT")
	b.label:SetWordWrap(false)
	b.label:SetTextColor(1, 0.95, 0.86)
	b.label:Hide()
	b:SetScript("OnEnter", function(self)
		edgeColor(self.edges, 1, 0.92, 0.45, 1)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local text = self.tip
		local real = _G[self.realName]
		local owned = real and real.tooltipText
		if type(owned) == "string" and owned ~= "" and not ns.isSecret(owned) then
			if owned:find("(", 1, true) then
				GameTooltip:AddLine(owned, 1, 1, 1)
				GameTooltip:Show()
				return
			end
			text = owned
		end
		local actions = MENU_BIND[self.realName]
		local key
		if actions and GetBindingKey then
			for _, action in ipairs(actions) do
				local bound = GetBindingKey(action)
				if type(bound) == "string" and bound ~= "" and not ns.isSecret(bound) then
					if MicroButtonTooltipText then
						local line = MicroButtonTooltipText(text, action)
						if type(line) == "string" and not ns.isSecret(line) then
							GameTooltip:AddLine(line, 1, 1, 1)
							GameTooltip:Show()
							return
						end
					end
					local shown = GetBindingText and GetBindingText(bound) or bound
					if type(shown) == "string" and shown ~= "" and not ns.isSecret(shown) then
						key = shown
						break
					end
				end
			end
		end
		if key then text = text .. " |cffffffff(" .. key .. ")|r" end
		GameTooltip:AddLine(text, GOLD[1], GOLD[2], GOLD[3])
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self)
		edgeColor(self.edges, 0.85, 0.68, 0.22, 1)
		GameTooltip:Hide()
	end)
	b:SetScript("OnClick", function(self)
		-- The game menu closes open windows instead of opening, and this wheel
		-- is one of those windows. Put the wheel away, then open the menu.
		if self.realName == "MainMenuMicroButton" then
			popup:Hide()
			local menu = GameMenuFrame
			if menu and menu.IsShown and menu:IsShown() then
				if HideUIPanel then pcall(HideUIPanel, menu) else menu:Hide() end
			elseif menu and ShowUIPanel then
				pcall(ShowUIPanel, menu)
			else
				tryCall(ToggleGameMenu)
			end
			return
		end
		-- The real Forever button knows its own window. The toggle list is only
		-- for when that button has been hidden with the micro menu.
		local real = _G[self.realName]
		local shown = real and real.IsShown and real:IsShown()
		if shown and real.Click and not (InCombatLockdown() and real.IsProtected and real:IsProtected()) then
			pcall(real.Click, real, "LeftButton")
		else
			if not pressMenu(self.realName) and real and real.Click
				and not (InCombatLockdown() and real.IsProtected and real:IsProtected()) then
				pcall(real.Click, real, "LeftButton")
			end
		end
		popup:Hide()
	end)
	b:Hide()
	proxies[name] = b
	return b
end

-- Forever Dungeon Journal's own launcher icon, when that addon is loaded.
local function journalIcon()
	local fdj = _G.ForeverDungeonJournal_NS
	local fromBroker = fdj and fdj._minimapDataObject and fdj._minimapDataObject.icon
	if type(fromBroker) == "string" and fromBroker ~= "" then return fromBroker end
	local btn = _G.LibDBIcon10_ForeverDungeonJournal
	local tex = btn and btn.icon and btn.icon.GetTexture and btn.icon:GetTexture()
	if tex and tex ~= 0 and tex ~= "" and not ns.isSecret(tex) then return tex end
	return "Interface\\Icons\\INV_Misc_Book_09"
end

local journalBtn
local function journalButton()
	if not (ns.addonOn and ns.addonOn("ForeverDungeonJournal")) then
		if journalBtn then journalBtn:Hide() end
		return nil
	end
	if not journalBtn then
		local b = CreateFrame("Button", nil, popup)
		b:SetSize(CELL - 4, CELL - 4)
		b:RegisterForClicks("AnyUp")
		b:EnableMouse(true)
		b.realName = "ZydeForeverDungeonJournal"
		b.tip = MENU_TIP[b.realName]
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints()
		b.bg:SetColorTexture(0, 0, 0, 0.92)
		b.edges = ns.newEdges(b, "OVERLAY", 2)
		edgeColor(b.edges, 0.85, 0.68, 0.22, 1)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetPoint("TOPLEFT", 4, -4)
		b.icon:SetPoint("BOTTOMRIGHT", -4, 4)
		b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.label:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
		b.label:SetPoint("RIGHT", -4, 0)
		b.label:SetJustifyH("LEFT")
		b.label:SetWordWrap(false)
		b.label:SetTextColor(1, 0.95, 0.86)
		b.label:Hide()
		b:SetScript("OnEnter", function(self)
			edgeColor(self.edges, 1, 0.92, 0.45, 1)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(self.tip, GOLD[1], GOLD[2], GOLD[3])
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function(self)
			edgeColor(self.edges, 0.85, 0.68, 0.22, 1)
			GameTooltip:Hide()
		end)
		b:SetScript("OnClick", function()
			local fdj = _G.ForeverDungeonJournal_NS
			if fdj and fdj.ToggleJournal then pcall(fdj.ToggleJournal) end
			if popup:IsShown() then popup:Hide() end
		end)
		b:Hide()
		journalBtn = b
	end
	journalBtn.zydeTexture = journalIcon()
	return journalBtn
end

local function menuButtons()
	-- Character, Professions, Spellbook, Talents, Legacy, Quest Log, Guild,
	-- Group Finder, Account Collections, Shop, Dungeon Journal (when that
	-- addon is loaded), Game Menu. In that order.
	local items = {}
	for _, name in ipairs(MENU_ORDER) do
		if name == "MainMenuMicroButton" then
			local journal = journalButton()
			if journal then items[#items + 1] = journal end
		end
		local b = proxyFor(name)
		if b then items[#items + 1] = b end
	end
	return items
end

local function hideProxies()
	for _, b in pairs(proxies) do b:Hide() end
	if journalBtn then journalBtn:Hide() end
end

-- x to the right of the popup's center, y up.
local function placeCenter(frame, x, y, anchor, scale)
	local saved = frame.zydeSaved
	lock(frame)
	laying = true
	if frame.SetFixedFrameStrata then frame:SetFixedFrameStrata(false) end
	if frame.SetFixedFrameLevel then frame:SetFixedFrameLevel(false) end
	if frame.SetClampedToScreen then frame:SetClampedToScreen(false) end
	frame:SetParent(popup)
	frame:SetScale(scale or (saved and saved.scale or 1))
	frame:ClearAllPoints()
	-- A scaled button measures its offset in its own pixels, so a 0.7 scale
	-- would land the row up inside the two columns. Divide to keep x and y
	-- in the panel's pixels.
	local s = frame:GetScale()
	if not s or s == 0 then s = 1 end
	if anchor == "TOPLEFT" then
		frame:SetPoint("TOPLEFT", popup, "TOPLEFT", x / s, -y / s)
	else
		frame:SetPoint("CENTER", popup, "CENTER", x / s, y / s)
	end
	frame:SetFrameStrata(popup:GetFrameStrata() or "DIALOG")
	frame:SetFrameLevel((popup:GetFrameLevel() or 1) + 8)
	holdOpen(frame)
	frame:SetAlpha(1)
	armClicks(frame)
	frame:Show()
	laying = false
end

-- Skill line ids the professions window opens by. GetProfessionInfo's own id wins
-- when it has one; these cover a name that came back without one.
local SKILL_LINE = {
	Alchemy = 171, Blacksmithing = 164, Enchanting = 333, Engineering = 202,
	Inscription = 773, Jewelcrafting = 755, Leatherworking = 165, Tailoring = 197,
	Cooking = 185, ["First Aid"] = 129, Fishing = 356, Herbalism = 182,
	Mining = 186, Skinning = 393, Archaeology = 794,
}

local function openProfession(info)
	if not info or InCombatLockdown() then return end
	-- The professions book opens a window by casting that profession's slot.
	-- Casting the spell by name, and OpenTradeSkill, both leave the window shut.
	if C_AddOns and C_AddOns.LoadAddOn then
		pcall(C_AddOns.LoadAddOn, "Blizzard_ProfessionsBook")
	elseif UIParentLoadAddOn then
		pcall(UIParentLoadAddOn, "Blizzard_ProfessionsBook")
	elseif LoadAddOn then
		pcall(LoadAddOn, "Blizzard_ProfessionsBook")
	end
	if ProfessionsBookFrame_Update then pcall(ProfessionsBookFrame_Update) end
	local offset = plain(info.spellOffset)
	local named = {
		"PrimaryProfession1SpellButtonTop", "PrimaryProfession1SpellButtonBottom",
		"PrimaryProfession2SpellButtonTop", "PrimaryProfession2SpellButtonBottom",
		"SecondaryProfession1SpellButtonLeft", "SecondaryProfession1SpellButtonRight",
		"SecondaryProfession2SpellButtonLeft", "SecondaryProfession2SpellButtonRight",
		"SecondaryProfession3SpellButtonLeft", "SecondaryProfession3SpellButtonRight",
		"SecondaryProfession4SpellButtonLeft", "SecondaryProfession4SpellButtonRight",
	}
	for i = 1, #named do
		local btn = _G[named[i]]
		if btn and btn.Click then
			local label
			if btn.SpellName and btn.SpellName.GetText then label = plain(btn.SpellName:GetText()) end
			if type(label) ~= "string" and btn.GetText then label = plain(btn:GetText()) end
			if label == info.name then
				btn:Click("LeftButton")
				return
			end
		end
	end
	local count = plain(info.numSpells)
	if type(count) ~= "number" or count < 1 then count = 1 end
	if type(offset) == "number" and CastSpell and GetSpellBookItemName then
		local books = { BOOKTYPE_PROFESSION or "professions", BOOKTYPE_SPELL or "spell" }
		local fallbackSlot, fallbackBook
		for b = 1, #books do
			for n = 1, count do
				local slot = offset + n
				local spellName = plain(safe(GetSpellBookItemName, slot, books[b]))
				if spellName == info.name then
					CastSpell(slot, books[b])
					return
				end
				if not fallbackSlot and type(spellName) == "string" then
					fallbackSlot, fallbackBook = slot, books[b]
				end
			end
		end
		CastSpell(fallbackSlot or (offset + 1), fallbackBook or books[1])
		return
	end
	local id = plain(info.skillLine)
	if type(id) ~= "number" then id = SKILL_LINE[info.name] end
	if ProfessionsFrame_LoadUI then pcall(ProfessionsFrame_LoadUI) end
	if type(id) == "number" and C_TradeSkillUI and type(C_TradeSkillUI.OpenTradeSkill) == "function" then
		C_TradeSkillUI.OpenTradeSkill(id)
	end
end

local profButtons = {}
local function profButton(i)
	local b = profButtons[i]
	if b then return b end
	-- A normal button on the wheel. A secure one hid itself on click and then
	-- stayed gone, and its spell cast never opened the profession window.
	b = CreateFrame("Button", nil, popup)
	b:SetSize(CELL - 4, CELL - 4)
	b:SetFrameLevel((popup:GetFrameLevel() or 1) + 20)
	b:RegisterForClicks("AnyUp")
	b:EnableMouse(true)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.bg:SetColorTexture(0, 0, 0, 0.92)
	b.edges = ns.newEdges(b, "OVERLAY", 2)
	edgeColor(b.edges, 0.85, 0.68, 0.22, 1)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 4, -4)
	b.icon:SetPoint("BOTTOMRIGHT", -4, 4)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.level = b:CreateFontString(nil, "OVERLAY")
	font(b.level, 10)
	b.level:SetPoint("TOP", b, "BOTTOM", 0, -2)
	b.level:SetTextColor(1, 0.95, 0.75)
	b.level:Hide()
	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.label:SetPoint("LEFT", 28, 0)
	b.label:SetPoint("RIGHT", -4, 0)
	b.label:SetJustifyH("LEFT")
	b.label:SetWordWrap(false)
	b.label:SetTextColor(1, 0.95, 0.86)
	b.label:Hide()
	b:SetScript("OnEnter", function(self)
		edgeColor(self.edges, 1, 0.92, 0.45, 1)
		local info = self.info
		if not info then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(info.name, GOLD[1], GOLD[2], GOLD[3])
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self)
		edgeColor(self.edges, 0.85, 0.68, 0.22, 1)
		GameTooltip:Hide()
	end)
	b:SetScript("OnClick", function(self)
		openProfession(self.info)
		if popup:IsShown() then popup:Hide() end
	end)
	b:Hide()
	profButtons[i] = b
	return b
end

local function hideProfButtons()
	for _, b in ipairs(profButtons) do
		b:Hide()
	end
end

local function paintProf(b, info)
	local icon = b.icon
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local tex = plain(info.texture)
	if not (tex and pcall(icon.SetTexture, icon, tex)) then
		local got = info.name and GetSpellTexture and plain(safe(GetSpellTexture, info.name))
		if not (got and pcall(icon.SetTexture, icon, got)) then
			icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		end
	end
	ns.placeEdges(b.edges, b, 0, 2)
	-- 300 is the cap. Anything short of that sits under the icon.
	if info.rank and info.rank ~= 300 then
		b.level:SetText(info.maxRank and (info.rank .. "/" .. info.maxRank) or tostring(info.rank))
		b.level:Show()
	else
		b.level:Hide()
	end
end

-- Primaries first, then cooking, first aid, fishing, archaeology.
local function learnedProfessions()
	local out, seen = {}, {}
	local function push(info)
		if type(info.name) ~= "string" or info.name == "" or seen[info.name] then return end
		if info.name == "Riding" then return end
		seen[info.name] = true
		out[#out + 1] = info
	end
	if GetProfessions and GetProfessionInfo then
		local p1, p2, arch, fish, cook, aid = GetProfessions()
		local function take(index)
			index = plain(index)
			if type(index) ~= "number" then return end
			local name, texture, rank, maxRank, numSpells, spellOffset, skillLine = safe(GetProfessionInfo, index)
			name, rank, maxRank, numSpells, spellOffset, skillLine = plain(name), plain(rank), plain(maxRank), plain(numSpells), plain(spellOffset), plain(skillLine)
			if type(name) ~= "string" then return end
			push({ name = name, texture = texture, rank = rank, maxRank = maxRank, skillLine = skillLine, spellOffset = spellOffset, numSpells = numSpells })
		end
		take(p1) take(p2) take(cook) take(aid) take(fish) take(arch)
		if #out > 0 then return out end
	end
	local lines = GetNumSkillLines and plain(safe(GetNumSkillLines))
	if not (lines and lines > 0 and GetSkillLineInfo) then return out end
	local want = false
	for i = 1, lines do
		local name, header, _, rank, _, _, maxRank = safe(GetSkillLineInfo, i)
		name, header, rank, maxRank = plain(name), plain(header), plain(rank), plain(maxRank)
		if header then
			local low = type(name) == "string" and name:lower() or ""
			want = low:find("profession", 1, true) ~= nil or low:find("secondary", 1, true) ~= nil
		elseif want and type(name) == "string" then
			push({ name = name, rank = rank, maxRank = maxRank })
		end
	end
	return out
end

-- First Aid, Cooking, Fishing, then the two primary tradeskills, then anything
-- else that was learned (archaeology, gathering).
local function orderedProfessions()
	local raw = learnedProfessions()
	local gathering = { Herbalism = true, Mining = true, Skinning = true, Archaeology = true }
	local byName = {}
	for _, info in ipairs(raw) do byName[info.name] = info end
	local out = {}
	local function take(name)
		local info = byName[name]
		if not info then return end
		out[#out + 1] = info
		byName[name] = nil
	end
	take("First Aid")
	take("Cooking")
	take("Fishing")
	for _, info in ipairs(raw) do
		if byName[info.name] and not gathering[info.name] then take(info.name) end
	end
	for _, info in ipairs(raw) do
		if byName[info.name] then take(info.name) end
	end
	return out
end

local listHeaders = {}
local function hideHeaders()
	for _, fs in ipairs(listHeaders) do fs:Hide() end
end

local function listHeader(i, text, x, y)
	local fs = listHeaders[i]
	if not fs then
		fs = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		fs:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		listHeaders[i] = fs
	end
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", popup, "TOPLEFT", x, -y)
	fs:SetText(text)
	fs:Show()
end

local listRules = { popup.rule, popup.rule2 }
local function hideRules()
	for _, tex in ipairs(listRules) do tex:Hide() end
end

local function showRule(i, x, y, span)
	local tex = listRules[i]
	if not tex then
		tex = popup:CreateTexture(nil, "ARTWORK")
		listRules[i] = tex
	end
	tex:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.55)
	tex:ClearAllPoints()
	tex:SetPoint("TOPLEFT", popup, "TOPLEFT", x, -y)
	tex:SetSize(span, 2)
	tex:Show()
end

-- One tile size: icon centered above the name.
local TILE_W, TILE_H, TILE_ICON, TILE_GAP = 116, 82, 40, 8
local LIST_ICON = math.floor(TILE_ICON * 0.6 * 1.1 + 0.5)
local LIST_W = math.floor(TILE_W * 0.6 * 1.1 + 0.5)
local LIST_LABEL = 14
local LIST_H = LIST_ICON + LIST_LABEL + 14

local function dressRow(b, listed, text)
	if b.label then
		b.label:ClearAllPoints()
		if listed then
			if b.label.SetMaxLines then b.label:SetMaxLines(1) end
			b.label:SetFontObject("GameFontHighlightSmall")
			b.label:SetText(text or "")
			b.label:SetJustifyH("CENTER")
			b.label:SetJustifyV("MIDDLE")
			b.label:SetWordWrap(false)
			local font, _, flags = b.label:GetFont()
			if type(font) == "string" then
				local size = 10
				b.label:SetFont(font, size, flags)
				while size > 8 and (b.label:GetStringWidth() or 0) > (LIST_W - 8) do
					size = size - 1
					b.label:SetFont(font, size, flags)
				end
			end
			b.label:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 3, 4)
			b.label:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 4)
			b.label:Show()
		else
			b.label:Hide()
			b.label:SetWordWrap(false)
			b.label:SetJustifyH("LEFT")
		end
	end
	if listed then
		b:SetSize(LIST_W, LIST_H)
		if b.SetClipsChildren then b:SetClipsChildren(true) end
		b.icon:ClearAllPoints()
		b.icon:SetSize(LIST_ICON, LIST_ICON)
		-- Centered in the space above the name, so a long label cannot sit on the icon.
		local above = LIST_H - LIST_LABEL
		b.icon:SetPoint("CENTER", b, "TOP", 0, -(above / 2))
		if b.level then b.level:Hide() end
	else
		b:SetSize(CELL - 4, CELL - 4)
		-- The list clips; the dial's skill level sits below the button.
		if b.SetClipsChildren then b:SetClipsChildren(false) end
		b.icon:ClearAllPoints()
		b.icon:SetPoint("TOPLEFT", 4, -4)
		b.icon:SetPoint("BOTTOMRIGHT", -4, 4)
	end
	ns.placeEdges(b.edges, b, 0, 2)
end

local function anchorPopup(point)
	local scale = UIParent:GetEffectiveScale()
	if not scale or scale == 0 then scale = 1 end
	local x, py = popup.cx, popup.cy
	if not x then
		local cx, cy = GetCursorPosition()
		x, py = cx / scale, cy / scale
	end
	popup:ClearAllPoints()
	if point == "TOPLEFT" then
		popup:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x + 14, py - 14)
	else
		popup:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, py)
	end
end

-- Tradeskills, the game menu, the minimap buttons, then Addons. A line sits
-- between bands.
local function layoutList(menu, buttons, profs, addons)
	local PAD, HEAD = 10, 20
	local COLS = 5

	local function blockH(n)
		if n <= 0 then return 0 end
		return HEAD + math.ceil(n / COLS) * (LIST_H + TILE_GAP) - TILE_GAP
	end
	local function rowSpan(n)
		if n <= 0 then return 0 end
		local c = math.min(COLS, n)
		return c * LIST_W + (c - 1) * TILE_GAP
	end

	local profH = blockH(#profs)
	local menuH = blockH(#menu)
	local width = PAD * 2 + math.max(rowSpan(#profs), rowSpan(#menu), 160)

	-- 0.7 was the old condensed size. A quarter more, in the panel's own pixels.
	local MINI = 0.7 * 1.25
	local miniSlot = 36
	for _, frame in ipairs(buttons) do
		local w = frame.GetWidth and frame:GetWidth()
		if type(w) ~= "number" or w < 8 or w > 80 then w = 31 end
		miniSlot = math.max(miniSlot, math.ceil(w * MINI) + 8)
	end
	local function measure(n)
		if n <= 0 then return 0, 0, 0 end
		local fit = math.max(1, math.floor((width - PAD * 2) / miniSlot))
		local cols, rows
		if n > fit then
			rows = 2
			cols = math.ceil(n / 2)
		else
			rows = 1
			cols = n
		end
		return cols, rows, cols * miniSlot + PAD * 2
	end
	local miniCols, miniRows, rowW = measure(#buttons)
	local addonCols, addonRows, addonW = measure(#addons)
	if rowW > width then width = rowW end
	if addonW > width then width = addonW end
	miniCols, miniRows, rowW = measure(#buttons)
	addonCols, addonRows, addonW = measure(#addons)
	local btnBlock = miniRows > 0 and (HEAD + 4 + miniRows * miniSlot) or 0
	local addonBlock = addonRows > 0 and (HEAD + 4 + addonRows * miniSlot) or 0

	local y = PAD
	local profY, menuY, miniY, addonY
	local rules, seen = {}, false
	local function split()
		y = y + 8
		rules[#rules + 1] = y
		y = y + 10
	end
	if #profs > 0 then
		profY = y
		y = y + profH
		seen = true
	end
	if #menu > 0 then
		if seen then split() end
		menuY = y
		y = y + menuH
		seen = true
	end
	if #buttons > 0 then
		if seen then split() end
		miniY = y
		y = y + btnBlock
		seen = true
	end
	if #addons > 0 then
		if seen then split() end
		addonY = y
		y = y + addonBlock
	end
	local height = y + PAD
	if height < 48 then height = 48 end
	popup:SetSize(width, height)

	popup.disc:Hide()
	popup.rim:Hide()
	popup.bg:SetColorTexture(0.06, 0.05, 0.08, 0.96)
	popup.bg:Show()
	for _, t in ipairs(popup.edges) do t:Show() end
	edgeColor(popup.edges, PURPLE[1], PURPLE[2], PURPLE[3], 0.95)
	ns.placeEdges(popup.edges, popup, 0, 1)

	local hi = 0
	local function head(text, x, y)
		hi = hi + 1
		listHeader(hi, text, x, y)
	end

	local function putTile(b, originY, i, total, level)
		local col = (i - 1) % COLS
		local row = math.floor((i - 1) / COLS)
		local inRow = math.min(COLS, total - row * COLS)
		local rowW = inRow * LIST_W + (inRow - 1) * TILE_GAP
		local contentW = width - PAD * 2
		local originX = PAD + math.floor((contentW - rowW) / 2)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", popup, "TOPLEFT", originX + col * (LIST_W + TILE_GAP), -(originY + HEAD + row * (LIST_H + TILE_GAP)))
		b:SetFrameLevel((popup:GetFrameLevel() or 1) + level)
		b:SetAlpha(1)
		if b.EnableMouse then b:EnableMouse(true) end
		if b.SetMouseClickEnabled then b:SetMouseClickEnabled(true) end
		b:Show()
	end
	if profY then
		head("Tradeskills", PAD, profY)
		for i, info in ipairs(profs) do
			local b = profButton(i)
			b.info = info
			paintProf(b, info)
			dressRow(b, true, info.name)
			putTile(b, profY, i, #profs, 20)
		end
	end
	if menuY then
		head("Menu", PAD, menuY)
		for i, b in ipairs(menu) do
			applyIcon(b, _G[b.realName])
			dressRow(b, true, MENU_SHORT[b.realName] or b.tip)
			putTile(b, menuY, i, #menu, 12)
		end
	end
	hideRules()
	local span = math.max(8, width - PAD * 2)
	for i, ry in ipairs(rules) do
		showRule(i, PAD, ry, span)
	end
	local function putIcons(list, originY, cols)
		local gridY = originY + HEAD + 2
		local contentW = width - PAD * 2
		for i, frame in ipairs(list) do
			local col = (i - 1) % cols
			local row = math.floor((i - 1) / cols)
			local inRow = math.min(cols, #list - row * cols)
			local originX = PAD + math.floor((contentW - inRow * miniSlot) / 2)
			local x = originX + col * miniSlot
			local iy = gridY + row * miniSlot
			if frame.zydeCompartment then
				placeAddon(frame, x, iy, MINI)
			else
				placeCenter(frame, x, iy, "TOPLEFT", MINI)
			end
		end
	end
	if miniY then
		head("Minimap buttons", PAD, miniY)
		putIcons(buttons, miniY, miniCols)
	end
	if addonY then
		head("Other Addons", PAD, addonY)
		putIcons(addons, addonY, addonCols)
	end
	anchorPopup("CENTER")
end

layoutPopup = function()
	local menu = menuButtons()
	local buttons = uniqueButtons(sorted())
	local addons = compartmentButtons()
	local profs = orderedProfessions()
	hideProxies()
	hideProfButtons()
	hideHeaders()
	hideRules()
	layoutList(menu, buttons, profs, addons)
end

local function showPopup()
	if not on() then return end
	scan()
	flyoutWasOpen = flyout:IsShown()
	if flyoutWasOpen then flyout:Hide() end
	local scale = UIParent:GetEffectiveScale()
	if not scale or scale == 0 then scale = 1 end
	local cx, cy = GetCursorPosition()
	popup.cx, popup.cy = cx / scale, cy / scale
	popup:Show()
	catcher:Show()
	layoutPopup()
end

popup:SetScript("OnHide", function()
	catcher:Hide()
	hideRules()
	hideHeaders()
	hideProxies()
	hideProfButtons()
	if not on() then return end
	layoutFlyout()
	if flyoutWasOpen then
		flyoutWasOpen = false
		flyout:Show()
		layoutFlyout()
	end
end)

-- Eats clicks on the empty part of the wheel so they don't land on the
-- world. The wheel itself stays up until the key is released.
catcher:SetScript("OnClick", function() end)

local function toggleFlyout()
	if flyout:IsShown() then
		flyout:Hide()
		layoutFlyout()
		return
	end
	if popup:IsShown() then popup:Hide() end
	scan()
	flyout:Show()
	layoutFlyout()
end

toggle:SetScript("OnClick", function(self)
	if self.moved then self.moved = nil return end
	if IsControlKeyDown() then
		if ns.ToggleOptions then ns.ToggleOptions() end
		return
	end
	toggleFlyout()
end)
toggle:SetScript("OnDragStart", function(self)
	self.dragging = true
	self.moved = false
	self.dragX, self.dragY = GetCursorPosition()
end)
toggle:SetScript("OnDragStop", function(self)
	self.dragging = false
end)
toggle:SetScript("OnUpdate", function(self)
	if not self.dragging or not Minimap then return end
	local cx, cy = GetCursorPosition()
	if self.dragX and (math.abs(cx - self.dragX) > 4 or math.abs(cy - self.dragY) > 4) then
		self.moved = true
	end
	local scale = Minimap:GetEffectiveScale()
	if not scale or scale == 0 then return end
	local mx, my = Minimap:GetCenter()
	if not mx then return end
	local rad = math.atan2(cy / scale - my, cx / scale - mx)
	ZydeForeverDB = ZydeForeverDB or {}
	ZydeForeverDB.minimapBagAngle = math.deg(rad)
	local r = orbitRadius(rad)
	self:ClearAllPoints()
	self:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * r, math.sin(rad) * r)
	if flyout:IsShown() then anchorFlyout() end
end)
toggle:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("Minimap buttons", GOLD[1], GOLD[2], GOLD[3])
	GameTooltip:AddLine("Click to show the addon buttons gathered here.", 1, 1, 1, true)
	GameTooltip:AddLine("Ctrl-click to open Zyde options.", 1, 1, 1, true)
	GameTooltip:AddLine("Drag around the minimap to move this.", 1, 1, 1, true)
	local n = #collected
	if n == 0 then
		GameTooltip:AddLine("None gathered yet.", 0.8, 0.8, 0.8, true)
	else
		GameTooltip:AddLine(n .. " gathered.", 0.8, 0.8, 0.8, true)
	end
	GameTooltip:AddLine("Hold Buttons at cursor, in Keybindings, to open the game menu and these at the mouse.", 0.75, 0.75, 0.75, true)
	GameTooltip:Show()
end)
toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)

local wheelHeld = false
key:SetScript("OnClick", function(_, _, down)
	if down then
		if wheelHeld or not on() then return end
		wheelHeld = true
		showPopup()
	else
		wheelHeld = false
		if popup:IsShown() then popup:Hide() end
	end
end)

ns.PlaceMinimapBag = placeToggle

local function apply()
	if on() then
		toggle:Show()
		placeToggle()
		scan()
		layoutFlyout()
	else
		if popup:IsShown() then popup:Hide() end
		flyout:Hide()
		catcher:Hide()
		releaseAll()
		if AddonCompartmentFrame and AddonCompartmentFrame.UpdateDisplay then
			AddonCompartmentFrame:UpdateDisplay()
		end
		toggle:Hide()
	end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, event)
	if event == "ADDON_LOADED" and not on() then return end
	apply()
end)
C_Timer.NewTicker(2, function()
	if on() then scan() end
end)
ns.OnFeatureChanged(function(keyName)
	if keyName == "buttonBag" then apply() end
end)
