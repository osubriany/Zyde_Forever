-- Zyde_Forever: the world map in Zyde's look (option "World map look").
--   1. The frame: the gold border, the book portrait and the parchment title
--      bar are hidden; a flat dark panel with a thin black edge and a gold
--      title takes their place. Close, maximize and the side-panel buttons
--      get square dark backs with gold icons.
--   2. The bar along the top (World > continent > zone): flat dark tabs,
--      purple for the map you're on.
--   3. The quest list: a dark panel, flat headings with a thin gold line,
--      and a dark search box.
-- The map itself, its icons and pins are untouched. Only the game's art is
-- made transparent (never moved or resized), so it's safe in combat. A part
-- the client doesn't have is skipped. Turning the option off takes a reload.

local ADDON, ns = ...

local function on() return ns.F("mapSkin") end

local BG = { 0.06, 0.06, 0.07, 0.96 }
local BAR = { 0.1, 0.09, 0.12, 0.95 }
local PURPLE = { 0.69, 0.35, 1 }
local GOLD = { 1, 0.82, 0.2 }

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
-- Make every texture of a frame transparent (its fonts stay). keep: textures to leave.
local function hideArt(frame, keep)
	if not frame or not frame.GetRegions then return end
	for _, r in ipairs({ frame:GetRegions() }) do
		if r.GetObjectType and r:GetObjectType() == "Texture" and not (keep and keep[r]) and not r.zydeOwn then
			r:SetAlpha(0)
		end
	end
end

local function own(tex) tex.zydeOwn = true return tex end

-- A flat panel behind a frame's contents, with a 1px edge.
local function panel(frame, color, edge, layerLevel)
	if not frame or frame.zydePanel then return frame and frame.zydePanel end
	local bg = own(frame:CreateTexture(nil, "BACKGROUND", nil, layerLevel or -8))
	bg:SetAllPoints()
	bg:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
	frame.zydePanel = bg
	if edge then
		local e = ns.newEdges(frame, "BORDER", 7)
		ns.placeEdges(e, frame, 0, 1)
		for _, t in ipairs(e) do own(t) t:SetColorTexture(edge[1], edge[2], edge[3], edge[4] or 1) end
		frame.zydeEdges = e
	end
	return bg
end

local function goldText(frame)
	if not frame or not frame.GetRegions then return end
	for _, r in ipairs({ frame:GetRegions() }) do
		if r.GetObjectType and r:GetObjectType() == "FontString" then r:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end
	end
end

-- A square dark button with a gold icon (close, maximize, side panel).
local function skinButton(b)
	if not b or b.zydeSkinned then return end
	b.zydeSkinned = true
	for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture" }) do
		local t = b[get] and b[get](b)
		if t then
			if t.SetDesaturated then t:SetDesaturated(true) end
			t:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
		end
	end
	local hl = b.GetHighlightTexture and b:GetHighlightTexture()
	if hl then hl:SetAlpha(0.25) end
	local bg = own(b:CreateTexture(nil, "BACKGROUND", nil, -8))
	bg:SetPoint("TOPLEFT", 3, -3)
	bg:SetPoint("BOTTOMRIGHT", -3, 3)
	bg:SetColorTexture(0.05, 0.05, 0.06, 0.95)
	local e = ns.newEdges(b, "BACKGROUND", -7)
	for _, t in ipairs(e) do own(t) t:SetColorTexture(0, 0, 0, 1) end
	-- (the edge sits around the dark square, not the button's full hit area)
	e[1]:SetPoint("TOPLEFT", bg, "TOPLEFT", -1, 1) e[1]:SetPoint("TOPRIGHT", bg, "TOPRIGHT", 1, 1) e[1]:SetHeight(1)
	e[2]:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", -1, -1) e[2]:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", 1, -1) e[2]:SetHeight(1)
	e[3]:SetPoint("TOPLEFT", bg, "TOPLEFT", -1, 1) e[3]:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", -1, -1) e[3]:SetWidth(1)
	e[4]:SetPoint("TOPRIGHT", bg, "TOPRIGHT", 1, 1) e[4]:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", 1, -1) e[4]:SetWidth(1)
end

---------------------------------------------------------------------------
-- 1. The frame
---------------------------------------------------------------------------
local function skinBorder(border)
	if not border then return end
	hideArt(border)
	for _, key in ipairs({ "NineSlice", "PortraitContainer", "TitleContainer", "TopTileStreaks", "Inset", "InsetBorderTop" }) do
		local part = border[key]
		if part then hideArt(part) end
	end
	if border.portrait then border.portrait:SetAlpha(0) end
	if border.NineSlice and border.NineSlice.SetAlpha then border.NineSlice:SetAlpha(0) end
	goldText(border)
	if border.TitleContainer then goldText(border.TitleContainer) end
	if border.TitleText and border.TitleText.SetTextColor then border.TitleText:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end
	skinButton(border.CloseButton)
	local mm = border.MaximizeMinimizeFrame
	if mm then
		hideArt(mm)
		skinButton(mm.MaximizeButton)
		skinButton(mm.MinimizeButton)
	end
end

local function skinFrame()
	local f = WorldMapFrame
	if not f or f.zydeFrameSkinned then return end
	f.zydeFrameSkinned = true
	hideArt(f)
	if _G.WorldMapFrameBg then _G.WorldMapFrameBg:SetAlpha(0) end
	-- Our panel and title bar sit behind everything on the map frame.
	panel(f, BG, { 0, 0, 0, 1 })
	local title = own(f:CreateTexture(nil, "BACKGROUND", nil, -7))
	title:SetPoint("TOPLEFT", 1, -1)
	title:SetPoint("TOPRIGHT", -1, -1)
	title:SetHeight(22)
	title:SetColorTexture(1, 1, 1, 1)
	-- Top a touch lighter than the bottom: reads as a bar, not a flat block.
	if title.SetGradient and CreateColor then
		pcall(title.SetGradient, title, "VERTICAL", CreateColor(0.07, 0.065, 0.085, 0.98), CreateColor(0.14, 0.12, 0.17, 0.98))
	else
		title:SetColorTexture(BAR[1], BAR[2], BAR[3], BAR[4])
	end
	-- A faint inner edge just inside the black one.
	local inner = ns.newEdges(f, "BORDER", 5)
	ns.placeEdges(inner, f, 1, 1)
	for _, t in ipairs(inner) do own(t) t:SetColorTexture(1, 1, 1, 0.06) end
	-- The map canvas in a thin frame: black, then a faint gold line.
	local canvas = f.ScrollContainer
	if canvas then
		local edge = CreateFrame("Frame", nil, f)
		edge:SetPoint("TOPLEFT", canvas, "TOPLEFT", -2, 2)
		edge:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", 2, -2)
		edge:SetFrameLevel((canvas:GetFrameLevel() or 1) + 6)
		edge:EnableMouse(false)
		local dark = ns.newEdges(edge, "OVERLAY", 6)
		ns.placeEdges(dark, edge, 1, 1)
		for _, t in ipairs(dark) do own(t) t:SetColorTexture(0, 0, 0, 1) end
		local glow = ns.newEdges(edge, "OVERLAY", 5)
		ns.placeEdges(glow, edge, 0, 1)
		for _, t in ipairs(glow) do own(t) t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.22) end
	end
	local rule = own(f:CreateTexture(nil, "BORDER", nil, 6))
	rule:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, 0)
	rule:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, 0)
	rule:SetHeight(1)
	rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)
	skinBorder(f.BorderFrame)
	skinBorder(f.MiniBorderFrame)
	skinButton(_G.WorldMapFrameCloseButton)
	local toggle = f.SidePanelToggle
	if toggle then
		hideArt(toggle)
		skinButton(toggle.OpenButton)
		skinButton(toggle.CloseButton)
	end
end

---------------------------------------------------------------------------
-- 2. The bar along the top: a breadcrumb, not boxes. The game's tabs overlap
-- each other (their arrow art interlocks), so square backs drawn on them
-- overlapped too. Here each is plain text: gray, white on hover, and the map
-- you're on in gold with a purple underline. A small chevron sits between.
---------------------------------------------------------------------------
local function navText(b)
	return b.text or b.Text or (b.GetFontString and b:GetFontString())
end

local function paintNav(b)
	local text = navText(b)
	if not (text and text.SetTextColor) then return end
	if b.zydeCurrent then
		text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	elseif b.zydeHover then
		text:SetTextColor(1, 1, 1)
	else
		text:SetTextColor(0.62, 0.62, 0.66)
	end
	if b.zydeLine then b.zydeLine:SetShown(b.zydeCurrent and true or false) end
end

local function skinNavButton(b, current, first)
	if not b then return end
	local text = navText(b)
	if not b.zydeNav then
		b.zydeNav = true
		if text then
			local line = own(b:CreateTexture(nil, "OVERLAY", nil, 6))
			line:SetPoint("TOPLEFT", text, "BOTTOMLEFT", -1, -3)
			line:SetPoint("TOPRIGHT", text, "BOTTOMRIGHT", 1, -3)
			line:SetHeight(2)
			line:SetColorTexture(PURPLE[1], PURPLE[2], PURPLE[3], 1)
			b.zydeLine = line
			local sep = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			sep:SetPoint("RIGHT", text, "LEFT", -7, 0)
			sep:SetText(">")
			sep:SetTextColor(0.45, 0.45, 0.5)
			b.zydeSep = sep
		end
		b:HookScript("OnEnter", function(self) self.zydeHover = true paintNav(self) end)
		b:HookScript("OnLeave", function(self) self.zydeHover = false paintNav(self) end)
		if b.MenuArrowButton then
			hideArt(b.MenuArrowButton)
			local arrow = b.MenuArrowButton:GetNormalTexture()
			if arrow then
				arrow:SetAlpha(0.85)
				if arrow.SetDesaturated then arrow:SetDesaturated(true) end
				arrow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
			end
		end
	end
	-- Blizzard's tab art comes back when the bar is rebuilt: hide it again.
	hideArt(b)
	for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
		local t = b[get] and b[get](b)
		if t and not t.zydeOwn then t:SetAlpha(0) end
	end
	if b.zydeSep then b.zydeSep:SetShown(not first) end
	b.zydeCurrent = current and true or false
	paintNav(b)
end

local function skinNav()
	local nav = WorldMapFrame and WorldMapFrame.NavBar
	if not nav then return end
	if not nav.zydeNavBar then
		nav.zydeNavBar = true
		local bg = own(nav:CreateTexture(nil, "BACKGROUND", nil, -8))
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.35)
		local line = own(nav:CreateTexture(nil, "BORDER", nil, 6))
		line:SetPoint("BOTTOMLEFT")
		line:SetPoint("BOTTOMRIGHT")
		line:SetHeight(1)
		line:SetColorTexture(1, 1, 1, 0.08)
	end
	hideArt(nav)
	for _, key in ipairs({ "overlay", "InsetBorderBottomLeft", "InsetBorderBottomRight", "InsetBorderBottom", "InsetBorderLeft", "InsetBorderRight" }) do
		local part = nav[key]
		if part then
			if part.GetObjectType and part:GetObjectType() == "Texture" then part:SetAlpha(0) else hideArt(part) end
		end
	end
	local list = nav.navList or {}
	for i, b in ipairs(list) do skinNavButton(b, i == #list, i == 1) end
	if nav.homeButton and #list == 0 then skinNavButton(nav.homeButton, true, true) end
end

---------------------------------------------------------------------------
-- 3. The quest list
---------------------------------------------------------------------------
local function skinSearch(box)
	if not box or box.zydeSearch then return end
	box.zydeSearch = true
	hideArt(box)
	for _, key in ipairs({ "Left", "Middle", "Right", "Mid" }) do
		if box[key] then box[key]:SetAlpha(0) end
	end
	-- (the magnifier and the clear button keep their own art)
	if box.searchIcon then box.searchIcon:SetAlpha(0.8) end
	if box.Instructions then box.Instructions:SetTextColor(0.55, 0.55, 0.55) end
	panel(box, { 0, 0, 0, 0.6 }, { PURPLE[1], PURPLE[2], PURPLE[3], 0.5 })
	box.zydePanel:ClearAllPoints()
	box.zydePanel:SetPoint("TOPLEFT", -4, 0)
	box.zydePanel:SetPoint("BOTTOMRIGHT", 0, 0)
end

local function skinHeader(h)
	if not h or h.zydeHead then return end
	h.zydeHead = true
	hideArt(h)
	for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture" }) do
		local t = h[get] and h[get](h)
		if t then t:SetAlpha(0) end
	end
	local bg = own(h:CreateTexture(nil, "BACKGROUND", nil, -8))
	bg:SetPoint("TOPLEFT", 2, -1)
	bg:SetPoint("BOTTOMRIGHT", -2, 1)
	bg:SetColorTexture(1, 1, 1, 0.05)
	local accent = own(h:CreateTexture(nil, "BORDER", nil, 6))
	accent:SetPoint("TOPLEFT", bg, "TOPLEFT", 0, 0)
	accent:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 0, 0)
	accent:SetWidth(3)
	accent:SetColorTexture(PURPLE[1], PURPLE[2], PURPLE[3], 0.9)
	local text = h.ButtonText or h.Text
	if text and text.SetTextColor then text:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end
end

local function skinQuestHeaders()
	local scroll = _G.QuestScrollFrame
	local contents = scroll and (scroll.Contents or (scroll.ScrollBox and scroll.ScrollBox.ScrollTarget))
	if not contents or not contents.GetChildren then return end
	for _, c in ipairs({ contents:GetChildren() }) do
		-- Zone headings have ButtonText and a collapse button; quest lines don't.
		if c.ButtonText or c.CollapseButton then skinHeader(c) end
	end
end

local function skinQuestPanel()
	local qm = _G.QuestMapFrame
	if not qm then return end
	if not qm.zydeQuestPanel then
		qm.zydeQuestPanel = true
		panel(qm, { 0.05, 0.05, 0.06, 0.97 }, { 0, 0, 0, 1 })
	end
	hideArt(qm)
	for _, key in ipairs({ "Background", "BorderFrame", "VerticalSeparator", "QuestsFrame" }) do
		local part = qm[key]
		if part then
			if part.GetObjectType and part:GetObjectType() == "Texture" then part:SetAlpha(0) else hideArt(part) end
		end
	end
	local scroll = _G.QuestScrollFrame
	if scroll then
		hideArt(scroll)
		for _, key in ipairs({ "Background", "BorderFrame", "Edge" }) do
			local part = scroll[key]
			if part then
				if part.GetObjectType and part:GetObjectType() == "Texture" then part:SetAlpha(0) else hideArt(part) end
			end
		end
		skinSearch(scroll.SearchBox)
	end
	skinQuestHeaders()
end

---------------------------------------------------------------------------
local function skinAll()
	if not on() or not WorldMapFrame then return end
	skinFrame()
	skinNav()
	skinQuestPanel()
end

local hooked = false
local function hookUp()
	if hooked or not WorldMapFrame then return end
	hooked = true
	-- Each open, each new map, each rebuilt bar or quest list.
	hooksecurefunc(WorldMapFrame, "Show", function() C_Timer.After(0, skinAll) end)
	if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", function() skinNav() end) end
	for _, fn in ipairs({ "NavBar_AddButton", "NavBar_Reset" }) do
		if type(_G[fn]) == "function" then hooksecurefunc(fn, function() if on() then skinNav() end end) end
	end
	for _, fn in ipairs({ "QuestLogQuests_Update", "QuestMapFrame_UpdateAll" }) do
		if type(_G[fn]) == "function" then hooksecurefunc(fn, function() if on() then skinQuestHeaders() end end) end
	end
	for _, m in ipairs({ "Maximize", "Minimize", "SynchronizeDisplayState" }) do
		if type(WorldMapFrame[m]) == "function" then
			hooksecurefunc(WorldMapFrame, m, function() if on() then skinAll() end end)
		end
	end
	skinAll()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, event, name)
	if not on() then return end
	if event == "PLAYER_LOGIN" or name == "Blizzard_WorldMap" then hookUp() end
end)
-- Ticking it in /zyde applies it right away (turning it off takes a reload).
ns.OnFeatureChanged(function(key)
	if key == "mapSkin" and on() then hookUp() skinAll() end
end)
