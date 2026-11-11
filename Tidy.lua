-- Zyde_Forever: small tidy-ups.
--   Action bars ("barTidy"):
--     * short keybind labels: a-1 -> A1, c-3 -> C3, s-E -> SE, Mouse Button 4 -> M4
--     * empty slots are invisible (they come back while you drag a spell or
--       item, so you can still place things)
--   Chat ("repChat"):
--     * the burst of "Reputation with X increased by 50." lines from one
--       turn-in becomes one line: "Reputation: +50 Booty Bay, Gadgetzan; +100 Ratchet"

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

local function updateAll()
	eachButton(function(b)
		fixHotkey(b)
		fixEmpty(b)
	end)
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

---------------------------------------------------------------------------
-- Reputation lines in chat
---------------------------------------------------------------------------
local function repOn() return ns.F("repChat") end

-- "Reputation with %s increased by %d." -> a pattern that captures both.
local function toPattern(fmt)
	if type(fmt) ~= "string" then return nil end
	-- Mark the %s / %d slots, escape everything else, then put captures in.
	local p = fmt:gsub("%%%d?%$?s", "\1"):gsub("%%%d?%$?d", "\2")
	p = p:gsub("([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1")
	p = p:gsub("\1", "(.+)"):gsub("\2", "(%%d+)")
	return "^" .. p .. "$"
end
local UP = toPattern(FACTION_STANDING_INCREASED or "Reputation with %s increased by %d.")
local DOWN = toPattern(FACTION_STANDING_DECREASED or "Reputation with %s decreased by %d.")

-- Lines collected per chat window, printed together a moment later.
local batches = {}

local function flush(frame)
	local b = batches[frame]
	batches[frame] = nil
	if not b or #b.order == 0 then return end
	-- Group factions by amount: "+50 A, B; +100 C"
	local byAmount, amounts = {}, {}
	for _, e in ipairs(b.order) do
		if not byAmount[e.amount] then byAmount[e.amount] = {} amounts[#amounts + 1] = e.amount end
		table.insert(byAmount[e.amount], e.faction)
	end
	local parts = {}
	for _, a in ipairs(amounts) do
		parts[#parts + 1] = ("%s%d %s"):format(a > 0 and "+" or "", a, table.concat(byAmount[a], ", "))
	end
	local info = ChatTypeInfo and ChatTypeInfo.COMBAT_FACTION_CHANGE or { r = 0.5, g = 0.5, b = 1 }
	frame:AddMessage("Reputation: " .. table.concat(parts, "; "), info.r, info.g, info.b)
end

local function repFilter(frame, _, msg)
	if not repOn() or type(msg) ~= "string" or ns.isSecret(msg) then return false end
	local faction, amount = msg:match(UP or "^$")
	local sign = 1
	if not faction then
		faction, amount = msg:match(DOWN or "^$")
		sign = -1
	end
	amount = tonumber(amount)
	if not (faction and amount) then return false end -- some other wording: leave it alone
	local b = batches[frame]
	if not b then
		b = { order = {} }
		batches[frame] = b
		C_Timer.After(0.4, function() flush(frame) end)
	end
	b.order[#b.order + 1] = { faction = faction, amount = sign * amount }
	return true -- hide the single line; the combined one follows
end

local addFilter = ChatFrame_AddMessageEventFilter
	or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
if addFilter then addFilter("CHAT_MSG_COMBAT_FACTION_CHANGE", repFilter) end

ns.OnFeatureChanged(function(key) if key == "barTidy" then updateAll() end end)
