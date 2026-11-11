-- Zyde_Forever: a cleaner look for the game's built-in damage meter.
--   * smaller (scaled down) and see-through, with a thin black edge
--   * flat bars (keeping the game's colors) and the unit frames' narrow font
--   * fades out when it doesn't matter: visible in combat, for 5 seconds
--     after, while you're in a group, while your mouse is over it, and in
--     Edit Mode
-- We only restyle what the game draws; the numbers stay the game's own.
-- /zyde meterdebug - what we found of the meter (to fix the look if needed)

local ADDON, ns = ...

local FLAT = "Interface\\Buttons\\WHITE8X8"
local FONT = "Fonts\\ARIALN.TTF"
-- (No rescaling: a scaled window draws its text fuzzy. Size it in Edit Mode.)
local BG_ALPHA = 0.25     -- background see-through
local LINGER = 5          -- seconds it stays after combat
local FADE_SPEED = 3      -- alpha per second while fading
local P = "|cff66ccffZyde_Forever|r: "

local function on() return ns.F("meterSkin") end

---------------------------------------------------------------------------
-- Finding the meter window(s): top-level frames whose name has "DamageMeter"
---------------------------------------------------------------------------
local roots = {}

-- Top-level frames we're allowed to look at. Some of the game's own frames
-- are "forbidden": touching them throws an error (that's what broke the
-- first version), so they're skipped.
local function topFrames()
	local out = {}
	for _, child in ipairs({ UIParent:GetChildren() }) do
		local ok, forbidden = pcall(function() return child.IsForbidden and child:IsForbidden() end)
		if ok and not forbidden then out[#out + 1] = child end
	end
	return out
end

local function nameOf(f)
	local ok, n = pcall(f.GetName, f)
	return ok and type(n) == "string" and n or nil
end

local function findRoots()
	local found = {}
	for _, child in ipairs(topFrames()) do
		local name = nameOf(child)
		if name and name:find("DamageMeter") then
			found[#found + 1] = child
		end
	end
	for _, n in ipairs({ "DamageMeter", "DamageMeterFrame" }) do
		local f = _G[n]
		if type(f) == "table" and f.IsObjectType and f:IsObjectType("Frame") then
			local dup = false
			for _, x in ipairs(found) do if x == f then dup = true end end
			if not dup then found[#found + 1] = f end
		end
	end
	-- Not named like that? Look for the window whose title says "Damage Done"
	-- (or another meter mode) among the visible top-level frames.
	if #found == 0 then
		local TITLES = { "Damage Done", "Damage Taken", "Healing Done", "DPS", "HPS" }
		local function hasTitle(f, d)
			if d > 4 then return false end
			for _, r in ipairs({ f:GetRegions() }) do
				if r:IsObjectType("FontString") then
					local t = r:GetText()
					if type(t) == "string" and not ns.isSecret(t) then
						for _, want in ipairs(TITLES) do
							if t == want then return true end
						end
					end
				end
			end
			for _, c in ipairs({ f:GetChildren() }) do
				if hasTitle(c, d + 1) then return true end
			end
			return false
		end
		for _, child in ipairs(topFrames()) do
			local ok, yes = pcall(function() return child:IsShown() and child ~= ZydeForeverOptions and hasTitle(child, 0) end)
			if ok and yes then found[#found + 1] = child end
		end
	end
	roots = found
	return #found > 0
end

---------------------------------------------------------------------------
-- Restyling
---------------------------------------------------------------------------
local styled = setmetatable({}, { __mode = "k" })
local edges = {} -- meter window -> our edge/panel frame

local function edge(frame)
	if edges[frame] then return end
	-- Our own frame, not a child of the game's: adding to the game's meter
	-- window can upset its own code (and its hidden numbers).
	local e = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	e:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
	e:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)
	e:SetFrameStrata(frame:GetFrameStrata())
	e:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
	e:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
	e:SetBackdropColor(0.04, 0.04, 0.05, BG_ALPHA)
	e:SetBackdropBorderColor(0, 0, 0, 0.9)
	e:EnableMouse(false)
	edges[frame] = e
end

-- The window's own backdrop art: fade it right down (our see-through panel shows instead).
local function quietBackground(frame)
	if frame.NineSlice and frame.NineSlice.SetAlpha then frame.NineSlice:SetAlpha(0) end
	for _, key in ipairs({ "Background", "Bg", "background", "BG", "BackgroundTexture", "Backdrop", "Border", "HeaderBackground" }) do
		local t = frame[key]
		if t and t.SetAlpha and t.GetAlpha and t:GetAlpha() ~= 0 then t:SetAlpha(0) end
	end
end

-- Flat texture, keeping the game's color. Checked again on every pass
-- (no hooks into the game's own code).
local flatID
local function styleBar(bar)
	local tex = bar:GetStatusBarTexture()
	local cur = tex and tex:GetTexture()
	if cur ~= nil and (cur == FLAT or cur == flatID) then return end
	local r, g, b, a = bar:GetStatusBarColor()
	bar:SetStatusBarTexture(FLAT)
	local t = bar:GetStatusBarTexture()
	flatID = flatID or (t and t:GetTexture())
	if r then pcall(bar.SetStatusBarColor, bar, r, g, b, a) end
end

local function styleText(fs)
	if styled[fs] then return end
	styled[fs] = true
	local _, size = fs:GetFont()
	fs:SetFont(FONT, math.floor((size or 12) + 0.5), "OUTLINE") -- whole sizes stay crisp
	fs:SetShadowOffset(0, 0)
end

local function walk(frame, depth)
	if depth > 8 then return end
	if frame:IsObjectType("StatusBar") then
		styleBar(frame)
	elseif depth > 0 then
		-- The session window (and its header) carry their own panel art.
		quietBackground(frame)
	end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:IsObjectType("FontString") then styleText(region) end
	end
	for _, child in ipairs({ frame:GetChildren() }) do walk(child, depth + 1) end
end

local function restyle()
	if not on() then return end
	for _, root in ipairs(roots) do
		if not styled[root] then
			styled[root] = true
			edge(root)
		end
		quietBackground(root)
		pcall(walk, root, 0) -- rows are added as people join a fight: walk again each time
	end
end

---------------------------------------------------------------------------
-- Fading
---------------------------------------------------------------------------
local lastCombat = 0
local current = 1

local function shouldShow()
	if UnitAffectingCombat("player") then lastCombat = GetTime() return true end
	if GetTime() - lastCombat < LINGER then return true end
	if IsInGroup() then return true end
	if EditModeManagerFrame and EditModeManagerFrame:IsShown() then return true end
	for _, root in ipairs(roots) do
		if root:IsVisible() and MouseIsOver(root) then return true end
	end
	return false
end

local ticker = CreateFrame("Frame")
local elapsedSince, restyleIn = 0, 0
ticker:SetScript("OnUpdate", function(_, elapsed)
	elapsedSince = elapsedSince + elapsed
	if elapsedSince < 0.05 then return end
	local dt = elapsedSince
	elapsedSince = 0
	if #roots == 0 then
		restyleIn = restyleIn - dt
		if restyleIn > 0 then return end
		restyleIn = 5 -- still looking for the meter: try again in a few seconds
		if not findRoots() then return end
	end
	if not on() then
		if current ~= 1 then
			current = 1
			for _, root in ipairs(roots) do
				root:SetAlpha(1)
				if edges[root] then edges[root]:Hide() end
			end
		end
		return
	end
	restyleIn = restyleIn - dt
	if restyleIn <= 0 then restyleIn = 1 restyle() end
	for _, root in ipairs(roots) do -- our panel follows the meter being opened / closed
		local e = edges[root]
		if e and e:IsShown() ~= root:IsVisible() then e:SetShown(root:IsVisible()) end
	end
	local goal = shouldShow() and 1 or 0
	if current ~= goal then
		-- Pop in quickly, fade out gently.
		local step = (goal > current and FADE_SPEED * 3 or FADE_SPEED) * dt
		current = goal > current and math.min(goal, current + step) or math.max(goal, current - step)
		for _, root in ipairs(roots) do
			root:SetAlpha(current)
			if edges[root] then edges[root]:SetAlpha(current) end
		end
	end
end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		lastCombat = GetTime()
		return
	end
	if findRoots() then restyle() end -- the meter may load later as its own Blizzard addon
end)

---------------------------------------------------------------------------
-- /zyde meterdebug
---------------------------------------------------------------------------
local function debug()
	findRoots()
	if #roots == 0 then
		print(P .. "no damage meter window found (no top-level frame named ...DamageMeter...)")
		local names = {}
		for _, child in ipairs(topFrames()) do
			local n = nameOf(child)
			if n and (n:find("Meter") or n:find("Damage")) then names[#names + 1] = n end
		end
		print(P .. "frames with Meter/Damage in the name: " .. (#names > 0 and table.concat(names, ", ") or "none"))
		return
	end
	for _, root in ipairs(roots) do
		local bars, texts = 0, 0
		local function count(f, d)
			if d > 8 then return end
			if f:IsObjectType("StatusBar") then bars = bars + 1 end
			for _, r in ipairs({ f:GetRegions() }) do if r:IsObjectType("FontString") then texts = texts + 1 end end
			for _, c in ipairs({ f:GetChildren() }) do count(c, d + 1) end
		end
		pcall(count, root, 0)
		local kids = {}
		for _, c in ipairs({ root:GetChildren() }) do kids[#kids + 1] = (c:GetName() or c:GetObjectType()) end
		print(P .. ("meter: %s  shown=%s  size=%dx%d  scale=%.2f  alpha=%.2f  protected=%s  bars=%d  texts=%d  nineslice=%s"):format(
			root:GetName() or "?", tostring(root:IsShown()), root:GetWidth(), root:GetHeight(), root:GetScale(),
			root:GetAlpha(), tostring(root:IsProtected()), bars, texts, tostring(root.NineSlice ~= nil)))
		print(P .. "  children: " .. table.concat(kids, ", "))
	end

	-- The named parts of the meter and its session window (Background,
	-- Header, ScrollBox...), so the look can be aimed at the right pieces.
	local function parts(label, f)
		if not f then return end
		local out = {}
		for k, v in pairs(f) do
			if type(k) == "string" and type(v) == "table" and k ~= "zydeEdge" then
				local ok, kind = pcall(function() return v.GetObjectType and v:GetObjectType() end)
				if ok and kind then out[#out + 1] = k .. "=" .. kind end
			end
		end
		table.sort(out)
		print(P .. label .. " parts: " .. (#out > 0 and table.concat(out, ", ") or "none"))
	end
	parts("DamageMeter", _G.DamageMeter)
	local sw = _G.DamageMeterSessionWindow1
	parts("SessionWindow1", sw)
	if sw then
		-- One bar row, if we can find one.
		local function firstBarParent(f, d)
			if d > 8 then return nil end
			if f:IsObjectType("StatusBar") then return f end
			for _, c in ipairs({ f:GetChildren() }) do
				local r = firstBarParent(c, d + 1)
				if r then return r end
			end
		end
		local bar = firstBarParent(sw, 0)
		if bar then
			parts("a bar (" .. (bar:GetName() or "unnamed") .. ")", bar)
			local tex = bar:GetStatusBarTexture()
			print(P .. "  bar texture: " .. tostring(tex and tex:GetTexture()) .. "  atlas: " .. tostring(tex and tex.GetAtlas and tex:GetAtlas()))
			parts("its row", bar:GetParent())
		else
			print(P .. "no StatusBar inside SessionWindow1 (the bars are drawn another way)")
		end
	end
end

ns.Meter = {
	Debug = function()
		local ok, err = pcall(debug)
		if not ok then print(P .. "meter debug hit an error: " .. tostring(err)) end
	end,
}
