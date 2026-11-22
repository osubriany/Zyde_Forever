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

---------------------------------------------------------------------------
-- One driver for the repeating nameplate checks (quest mobs, drop chances, quest
-- objects, Zyde's plates). They used to run on four separate timers, all at the
-- same moments, even with no nameplates around. Now:
--   Plates.Every(seconds, fn) runs fn about every `seconds`, the jobs spread
--   across the second, and skips it while no nameplates are in view (after one
--   last run, so a job can clear what it showed).
---------------------------------------------------------------------------
local jobs = {}
function Plates.Every(seconds, fn)
	jobs[#jobs + 1] = { every = seconds, fn = fn, nextAt = GetTime() + 0.25 * #jobs, wasEmpty = false }
end
local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function()
	local now = GetTime()
	for _, j in ipairs(jobs) do
		if now >= j.nextAt then
			j.nextAt = now + j.every
			local empty = #Plates.units() == 0
			if not (empty and j.wasEmpty) then
				local ok, err = pcall(j.fn)
				if not ok then geterrorhandler()(err) end -- (reported as usual, the other jobs still run)
			end
			j.wasEmpty = empty
		end
	end
end)

---------------------------------------------------------------------------
-- Quest data changed: each part keeps Questie answers per mob (is it a quest mob,
-- your count, drop chances) and forgets them on this one signal instead of on its
-- own timer. Sent when your quest log changes, again a second later (Questie
-- updates its data after the game does), when Questie redraws its nameplate
-- icons, and every few seconds as a backstop (Questie fills in its data some
-- seconds after login; kill counts don't always come with an event).
--   Plates.OnQuestChange(fn)
---------------------------------------------------------------------------
local questListeners = {}
function Plates.OnQuestChange(fn) questListeners[#questListeners + 1] = fn end
local function questChanged()
	for _, fn in ipairs(questListeners) do pcall(fn) end
end
local soon = false
local function questChangedSoon()
	if soon then return end
	soon = true
	C_Timer.After(0.1, function() soon = false questChanged() end)
end
local BACKSTOP = 3

local qev = CreateFrame("Frame")
qev:RegisterEvent("PLAYER_LOGIN")
qev:SetScript("OnEvent", function(_, event, unit)
	if event == "PLAYER_LOGIN" then
		for _, e in ipairs({ "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED" }) do pcall(qev.RegisterEvent, qev, e) end
		if QuestieLoader and QuestieLoader.ImportModule then
			local ok, np = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieNameplate")
			if ok and type(np) == "table" and np.UpdateNameplate then hooksecurefunc(np, "UpdateNameplate", questChangedSoon) end
		end
		C_Timer.NewTicker(BACKSTOP, questChanged)
		return
	end
	if event == "UNIT_QUEST_LOG_CHANGED" and unit ~= "player" then return end
	questChangedSoon()
	C_Timer.After(1, questChangedSoon)
end)
