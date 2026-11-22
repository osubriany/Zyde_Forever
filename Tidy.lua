-- Zyde_Forever: tidier action bars.
--   Action bars ("barTidy"):
--     * short keybind labels: a-1 -> A1, c-3 -> C3, s-E -> SE, Mouse Button 4 -> M4
--     * empty slots are invisible (they come back while you drag a spell or
--       item, so you can still place things)

local ADDON, ns = ...

---------------------------------------------------------------------------
-- Action bars
---------------------------------------------------------------------------
local function barsOn() return ns.F("barTidy") end

local BAR_PREFIXES = {
	"ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
	"MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
}

local function eachButton(fn)
	for _, prefix in ipairs(BAR_PREFIXES) do
		for i = 1, 12 do
			local b = _G[prefix .. i]
			if b then fn(b) end
		end
	end
end

-- "a-1" -> "A1", "c-s-3" -> "CS3", "Mouse Button 4" -> "M4", "Num Pad 5" -> "N5".
local function shortKey(text)
	if type(text) ~= "string" or text == "" or ns.isSecret(text) then return text end
	local t = text
	t = t:gsub("[Mm]ouse [Bb]utton ?", "M"):gsub("^[Bb]utton ?", "M")
	t = t:gsub("[Mm]ouse [Ww]heel [Uu]p", "WU"):gsub("[Mm]ouse [Ww]heel [Dd]own", "WD")
	t = t:gsub("[Nn]um ?[Pp]ad ?", "N"):gsub("[Mm]iddle [Mm]ouse", "M3")
	t = t:gsub("(%a)%-", function(m) return m:upper() end) -- modifier prefixes: a- c- s-
	t = t:gsub("ALT%-", "A"):gsub("CTRL%-", "C"):gsub("SHIFT%-", "S")
	return t
end

local function fixHotkey(button)
	if not barsOn() then return end
	local hk = button.HotKey or (button.GetName and _G[(button:GetName() or "") .. "HotKey"])
	if not hk or not hk.GetText then return end
	local cur = hk:GetText()
	local short = shortKey(cur)
	if short ~= cur then hk:SetText(short) end
end

-- Empty slots: invisible unless a spell / item is being dragged (the game
-- shows its "grid" then) or you've turned the feature off.
local dragging = false
local function fixEmpty(button)
	if not barsOn() then button:SetAlpha(1) return end
	local action = button.action or (button.GetAttribute and button:GetAttribute("action"))
	local has = action and HasAction(action)
	if ns.isSecret(has) then has = true end
	button:SetAlpha((has or dragging) and 1 or 0)
end

-- Main bar dividers: the game draws a thin line between the main bar's slots. They belong to the
-- bar, not the buttons, so they stayed visible over empty (invisible) slots. Hide them like the slots.
local function mainBar() return MainActionBar or MainMenuBar end
local function setDividerAlpha(d, a)
	if not d or not d.SetAlpha then return end
	if d.IsProtected and d:IsProtected() and InCombatLockdown() then return end
	d:SetAlpha(a)
end
local function fixDividers()
	local a = (barsOn() and not dragging) and 0 or 1
	local bar = mainBar()
	if bar and bar.dividersPool and bar.dividersPool.EnumerateActive then
		for d in bar.dividersPool:EnumerateActive() do setDividerAlpha(d, a) end
	end
	for i = 1, 12 do
		local b = _G["ActionButton" .. i]
		if b then
			setDividerAlpha(b.RightDivider, a)
			setDividerAlpha(b.BottomDivider, a)
		end
		-- Forever's main bar puts each button in a MainActionBarButtonContainerN that draws the
		-- divider itself: fade the container's own textures (not the button inside it).
		local c = _G["MainActionBarButtonContainer" .. i]
		if c and c.GetRegions then
			for _, r in ipairs({ c:GetRegions() }) do setDividerAlpha(r, a) end
		end
	end
	if bar then
		for k, v in pairs(bar) do
			if type(k) == "string" and k:find("Divider") and type(v) == "table" then setDividerAlpha(v, a) end
		end
	end
end

local function updateAll()
	eachButton(function(b)
		fixHotkey(b)
		fixEmpty(b)
	end)
	fixDividers()
end

local hooked = {}
local function hookButtons()
	eachButton(function(b)
		if hooked[b] then return end
		hooked[b] = true
		-- The game rewrites the label whenever bindings or pages change: shorten it again.
		if b.UpdateHotkeys then hooksecurefunc(b, "UpdateHotkeys", fixHotkey) end
		if b.Update then hooksecurefunc(b, "Update", fixEmpty) end
	end)
	if ActionButton_UpdateHotkeys then hooksecurefunc("ActionButton_UpdateHotkeys", fixHotkey) end
	-- The game rebuilds the dividers when the bar's layout changes (Edit Mode, padding, rows).
	local bar = mainBar()
	if bar and bar.UpdateDividers and not hooked[bar] then
		hooked[bar] = true
		hooksecurefunc(bar, "UpdateDividers", fixDividers)
	end
end

local barEv = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED",
	"ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "ACTIONBAR_SHOWGRID", "ACTIONBAR_HIDEGRID",
	"PET_BAR_UPDATE", "UPDATE_SHAPESHIFT_FORM" }) do
	pcall(barEv.RegisterEvent, barEv, e)
end
barEv:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then hookButtons() end
	if event == "ACTIONBAR_SHOWGRID" then dragging = true end
	if event == "ACTIONBAR_HIDEGRID" then dragging = false end
	-- Let the game draw its own update first, then tidy it.
	C_Timer.After(0, updateAll)
end)

ns.OnFeatureChanged(function(key) if key == "barTidy" then updateAll() end end)
