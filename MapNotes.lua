-- Zyde_Forever: your own named markers on the world map, kept between sessions.
--   Alt-click the map      drop a marker there and name it
--   Alt-click a marker     remove it
--   Right-click a marker   rename it
--   Hover a marker         its name
-- Saved per account (every character sees them), per map: ZydeForeverDB.mapNotes[mapID].
--
-- The markers sit on the map's canvas, so they pan with it, and are scaled back
-- down as you zoom in so they stay the same size on screen. The click is caught
-- with a hook on the map (not the map's own click handlers, which taint).

local ADDON, ns = ...

local P = "|cff66ccffZyde_Forever|r: "
local PIN_SIZE = 18

local function on() return ns.F("mapNotes") end

local function notes(mapID)
	ZydeForeverDB = ZydeForeverDB or {}
	ZydeForeverDB.mapNotes = ZydeForeverDB.mapNotes or {}
	if not mapID then return nil end
	ZydeForeverDB.mapNotes[mapID] = ZydeForeverDB.mapNotes[mapID] or {}
	return ZydeForeverDB.mapNotes[mapID]
end

---------------------------------------------------------------------------
-- Naming: a small popup with a text box
---------------------------------------------------------------------------
local refresh -- forward

StaticPopupDialogs["ZYDEFOREVER_MAP_NOTE"] = {
	text = "%s",
	button1 = ACCEPT or "OK",
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	maxLetters = 60,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
	OnShow = function(self, data)
		data = data or self.data
		local box = self.editBox or self.EditBox
		if box then
			box:SetText(data and data.label or "")
			box:HighlightText()
			box:SetFocus()
		end
	end,
	OnAccept = function(self, data)
		data = data or self.data
		if not data then return end
		local box = self.editBox or self.EditBox
		local text = box and box:GetText() or ""
		text = text:match("^%s*(.-)%s*$")
		if text == "" then text = "Marker" end
		if data.note then
			data.note.label = text -- rename
		else
			table.insert(notes(data.mapID), { x = data.x, y = data.y, label = text })
		end
		refresh()
	end,
	EditBoxOnEnterPressed = function(self)
		local popup = self:GetParent()
		local accept = popup.button1 or (popup.ButtonContainer and popup.ButtonContainer.Button1)
		if accept and accept:IsEnabled() then accept:Click() else popup:Hide() end
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

local function askName(data, title)
	StaticPopup_Show("ZYDEFOREVER_MAP_NOTE", title, nil, data)
end

---------------------------------------------------------------------------
-- The markers
---------------------------------------------------------------------------
local pins = {}       -- pool of marker frames
local shownMap, shownScale, shownW, shownH

local function canvas() return WorldMapFrame and WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child end

local function pinFrame(i)
	local p = pins[i]
	if p then return p end
	p = CreateFrame("Button", nil, canvas())
	p:SetSize(PIN_SIZE, PIN_SIZE)
	p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	p.icon = p:CreateTexture(nil, "OVERLAY")
	p.icon:SetAllPoints()
	if not (p.icon.SetAtlas and p.icon:SetAtlas("Waypoint-MapPin-Untracked")) then
		p.icon:SetTexture("Interface\\Minimap\\Tracking\\None")
		p.icon:SetVertexColor(1, 0.82, 0.2)
	end
	p.label = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	p.label:SetPoint("TOP", p, "BOTTOM", 0, -1)
	p.label:SetTextColor(1, 0.82, 0.2)
	p.label:SetShadowColor(0, 0, 0, 1)
	p.label:SetShadowOffset(1, -1)
	p:SetScript("OnClick", function(self, button)
		if not self.note then return end
		if button == "LeftButton" and IsAltKeyDown() then
			local list = notes(self.mapID)
			for k, n in ipairs(list) do
				if n == self.note then table.remove(list, k) break end
			end
			print(P .. "removed map marker \"" .. tostring(self.note.label) .. "\"")
			refresh()
		elseif button == "RightButton" then
			askName({ note = self.note }, "Rename this map marker:")
		end
	end)
	p:SetScript("OnEnter", function(self)
		if not self.note then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(self.note.label or "Marker", 1, 0.82, 0.2)
		GameTooltip:AddLine("Right-click: rename.  Alt-click: remove.", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	p:SetScript("OnLeave", function() GameTooltip:Hide() end)
	pins[i] = p
	return p
end

function refresh()
	local c = canvas()
	if not c then return end
	local mapID = WorldMapFrame:GetMapID()
	local scale = WorldMapFrame.ScrollContainer.GetCanvasScale and WorldMapFrame.ScrollContainer:GetCanvasScale() or 1
	local w, h = c:GetWidth(), c:GetHeight()
	shownMap, shownScale, shownW, shownH = mapID, scale, w, h
	local list = (on() and mapID and ZydeForeverDB and ZydeForeverDB.mapNotes and ZydeForeverDB.mapNotes[mapID]) or {}
	for i, n in ipairs(list) do
		local p = pinFrame(i)
		p.note, p.mapID = n, mapID
		-- The canvas grows as you zoom in: scale the marker back down, and
		-- give its offset in the marker's own (scaled) units.
		p:SetScale(1 / scale)
		p:SetFrameLevel(c:GetFrameLevel() + 2000)
		p:ClearAllPoints()
		p:SetPoint("CENTER", c, "TOPLEFT", n.x * w * scale, -n.y * h * scale)
		p.label:SetText(n.label or "")
		p:Show()
	end
	for i = #list + 1, #pins do
		pins[i].note = nil
		pins[i]:Hide()
	end
end

---------------------------------------------------------------------------
-- Alt-click on the map: drop a marker. Where you pressed is read when the
-- button goes down (a click on a continent map can open a zone on release).
---------------------------------------------------------------------------
local pressed, hooked

local function setup()
	if hooked or not (WorldMapFrame and WorldMapFrame.ScrollContainer) then return end
	hooked = true
	local sc = WorldMapFrame.ScrollContainer
	sc:HookScript("OnMouseDown", function(_, button)
		pressed = nil
		if button ~= "LeftButton" or not IsAltKeyDown() or not on() then return end
		local x, y = sc:GetNormalizedCursorPosition()
		if ns.isSecret(x) or ns.isSecret(y) or type(x) ~= "number" or type(y) ~= "number" then return end
		if x < 0 or x > 1 or y < 0 or y > 1 then return end
		pressed = { mapID = WorldMapFrame:GetMapID(), x = x, y = y }
	end)
	sc:HookScript("OnMouseUp", function(_, button)
		local p = pressed
		pressed = nil
		if not p or button ~= "LeftButton" or not IsAltKeyDown() then return end
		local info = C_Map.GetMapInfo and C_Map.GetMapInfo(p.mapID)
		askName(p, "Name this map marker" .. (info and info.name and (" (" .. info.name .. ")") or "") .. ":")
	end)
	-- Redraw when the map, its zoom or its size changes.
	local watcher = CreateFrame("Frame", nil, WorldMapFrame)
	watcher:SetScript("OnUpdate", function()
		local c = canvas()
		if not c then return end
		local scale = sc.GetCanvasScale and sc:GetCanvasScale() or 1
		if WorldMapFrame:GetMapID() ~= shownMap or scale ~= shownScale or c:GetWidth() ~= shownW or c:GetHeight() ~= shownH then
			refresh()
		end
	end)
	WorldMapFrame:HookScript("OnShow", refresh)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, event, name)
	if event == "PLAYER_LOGIN" or name == "Blizzard_WorldMap" then setup() end
end)

ns.OnFeatureChanged(function(key)
	if key == "mapNotes" then refresh() end
end)

-- /zyde mapnotes: how many markers you have, and how to clear one map's.
ns.MapNotesCommand = function(arg)
	local all = ZydeForeverDB and ZydeForeverDB.mapNotes or {}
	if arg == "clear" then
		local mapID = WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame:GetMapID()
		if not mapID then print(P .. "open the map you want to clear first, then /zyde mapnotes clear") return end
		local n = all[mapID] and #all[mapID] or 0
		all[mapID] = nil
		refresh()
		print(P .. ("removed %d marker%s from this map"):format(n, n == 1 and "" or "s"))
		return
	end
	local total, maps = 0, 0
	for _, list in pairs(all) do
		if #list > 0 then total, maps = total + #list, maps + 1 end
	end
	print(P .. ("%d map marker%s on %d map%s. Alt-click the map to add one, alt-click a marker to remove it, right-click to rename. /zyde mapnotes clear empties the open map.")
		:format(total, total == 1 and "" or "s", maps, maps == 1 and "" or "s"))
end
