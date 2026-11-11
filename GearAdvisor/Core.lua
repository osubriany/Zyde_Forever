-- Core: namespace, safe-call helpers, saved settings and events.
local ADDON, zyde = ...
-- Part of Zyde_Forever since 2026-11-11: GearAdvisor keeps its own private table (zyde.GA) so its
-- names never clash with Zyde's.
zyde.GA = zyde.GA or {}
local ns = zyde.GA
ns.name = ADDON

---------------------------------------------------------------------------------------------
-- Secret-value safety. On Forever some values are hidden from addons in combat ("secret");
-- doing maths on one breaks things, so every game read goes through these.
---------------------------------------------------------------------------------------------
local function isSecret(v)
	return type(issecretvalue) == "function" and issecretvalue(v) or false
end
ns.isSecret = isSecret

function ns.pack(...)
	return { n = select("#", ...), ... }
end

-- Calls fn(...) in pcall. Returns its results, or nothing if it errored or any result is secret.
function ns.safe(fn, ...)
	if type(fn) ~= "function" then return end
	local r = ns.pack(pcall(fn, ...))
	if not r[1] then return end
	for i = 2, r.n do
		if isSecret(r[i]) then return end
	end
	return unpack(r, 2, r.n)
end

function ns.print(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
	print("|cff33ff99GearAdvisor|r: " .. table.concat(parts, " "))
end

---------------------------------------------------------------------------------------------
-- Change notifications: other files (tooltip, bag arrows, LevelPlanner via the API) register
-- here to hear when equipment, level, talents or settings change.
---------------------------------------------------------------------------------------------
local listeners = {}
function ns.onChange(fn) listeners[#listeners + 1] = fn end
function ns.changed(reason)
	if ns.Player then ns.Player.invalidate() end
	for _, fn in ipairs(listeners) do pcall(fn, reason) end
end

---------------------------------------------------------------------------------------------
-- Saved settings
---------------------------------------------------------------------------------------------
local DEFAULTS = {
	specOverride = nil,   -- a profile key from Config.profiles, or nil for automatic
	target = nil,         -- nil = Config.defaultTarget
	tooltip = true,       -- upgrade lines on item tooltips (/ga tooltip)
	questMarks = true,    -- best-reward marks on quest reward choices (/ga quest)
	bagMarks = true,      -- upgrade arrows in bags, vendor and auction house (/ga arrows)
	rollMarks = true,     -- advice line on Need/Greed roll windows (/ga rolls)
	toast = true,         -- popup with an Equip button when an upgrade lands in your bags (/ga toast)
	toastPos = nil,       -- where you dragged the popup
}

-- A short headline for a compare result, plus its colour (r, g, b), or nil when there's
-- nothing worth saying. Used by tooltips, quest rewards and (later) bag and loot marks.
function ns.headline(r)
	local vs = r.vs and r.vs[1]
	local over = vs and (" over " .. vs .. (r.vs[2] and (" + " .. r.vs[2]) or "")) or " (empty slot)"
	local function pct(p) return ("%s%.1f%%"):format(p >= 0 and "+" or "", p) end
	if r.kind == "upgrade" then return "Upgrade: " .. pct(r.pct) .. over, 0.1, 1, 0.1
	elseif r.kind == "future" then return "Future upgrade: " .. pct(r.pct) .. over, 0.4, 0.8, 1
	elseif r.kind == "downgrade" then return "Downgrade: " .. pct(r.pct) .. (vs and (" vs " .. vs) or ""), 1, 0.3, 0.3
	elseif r.kind == "same" then return "About the same" .. (vs and (" as " .. vs) or ""), 0.7, 0.7, 0.7
	elseif r.kind == "too early" then return "Can't use yet", 0.6, 0.6, 0.6
	elseif r.kind == "unusable" then return "Can't use", 0.6, 0.6, 0.6
	end
end

local frame = CreateFrame("Frame")
ns.eventFrame = frame

local function safeRegister(event)
	pcall(frame.RegisterEvent, frame, event)
end

safeRegister("ADDON_LOADED")
safeRegister("PLAYER_LOGIN")
safeRegister("PLAYER_EQUIPMENT_CHANGED")
safeRegister("PLAYER_LEVEL_UP")
safeRegister("CHARACTER_POINTS_CHANGED")
safeRegister("PLAYER_TALENT_UPDATE")
safeRegister("ACTIVE_TALENT_GROUP_CHANGED")

local pendingChange
local function changeSoon(reason)
	-- Several events fire together (equip + stats); collapse them into one refresh.
	if pendingChange then return end
	pendingChange = true
	C_Timer.After(0.2, function()
		pendingChange = nil
		ns.changed(reason)
	end)
end

frame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		GearAdvisorDB = GearAdvisorDB or {}
		for k, v in pairs(DEFAULTS) do
			if GearAdvisorDB[k] == nil then GearAdvisorDB[k] = v end
		end
		ns.db = GearAdvisorDB
	elseif event == "PLAYER_LOGIN" then
		changeSoon("login")
	else
		changeSoon(event)
	end
end)
