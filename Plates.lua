-- Zyde_Forever: one shared list of the nameplates near you.
-- The quest object alert, quest mobs nearby and Questie drop chances all walk
-- the nameplates several times a second. Instead of each checking all 40
-- nameplate slots itself, they ask ns.Plates.units(): the slots in use,
-- rebuilt only when a nameplate came or went, and otherwise when it's older
-- than 0.4 s (object nameplates can change without an event, and the half-
-- second checks must still see a fresh list).
-- The returned list is shared: read it, don't change it.

local ADDON, ns = ...

local Plates = {}
ns.Plates = Plates

local TOKENS = {}
for i = 1, 40 do TOKENS[i] = "nameplate" .. i end

local MAX_AGE = 0.4
local units, builtAt, dirty = {}, -math.huge, true

function Plates.units()
	local now = GetTime()
	if not dirty and now - builtAt < MAX_AGE then return units end
	dirty, builtAt = false, now
	wipe(units)
	for i = 1, 40 do
		local token = TOKENS[i]
		-- Any GUID (even a hidden one) means the slot is in use.
		if ns.safe(UnitGUID, token) ~= nil then units[#units + 1] = token end
	end
	return units
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_ENTERING_WORLD" }) do
	pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function() dirty = true end)
