-- NpcStars: a key that targets the NPC of your next step (quest giver, turn-in, trainer, vendor,
-- innkeeper or flight master) and puts the game's yellow star marker on it.
-- Marking is protected on Forever: addon code may not place a marker on its own (the game shows
-- "blocked from an action only available to the Blizzard UI"). A key press on a secure button may,
-- so this is a secure macro button: /tar <name>, then the star if a live target was found.
-- Like every secure button, its macro can only change outside combat.
local ADDON, zyde = ...
-- Part of Zyde_Forever since 2026-11-14: LevelPlanner keeps its own private table (zyde.LP) so its
-- names never clash with Zyde's.
zyde.LP = zyde.LP or {}
local ns = zyde.LP

local NS = {}
ns.NpcStars = NS

local BUTTON = "LevelPlannerTargetNPC"
_G["BINDING_NAME_CLICK " .. BUTTON .. ":LeftButton"] = "Target next step's NPC (and star it)"

local NPC_KINDS = { pickup = true, turnin = true, trainer = true, vendor = true, bind = true, flightpath = true }
local MAX_MACRO = 255

local btn
local wanted = ""       -- macro for the current plan
local pending = false   -- changed during combat; apply when it ends

-- The macro: target the next NPC step's NPC by name (each /tar only works when
-- that NPC is near, so several names are fine), then the star, only on a live target.
local function buildMacro(plan)
	local names, seen = {}, {}
	for _, s in ipairs(plan and plan.stops or {}) do
		if NPC_KINDS[s.kind] and type(s.npcIds) == "table" then
			for _, id in ipairs(s.npcIds) do
				local name = ns.QuestSource.Npc(id, "name")
				if name and not seen[name] then seen[name] = true names[#names + 1] = name end
			end
			break
		end
	end
	if #names == 0 then return "" end
	-- the star, only on a live target (Config.npcStars = false: target only)
	local tail = ns.cfg.npcStars ~= false and "/tm [exists,nodead] 1" or ""
	-- (/targetexact targets nothing on Forever, while /tar does - seen in game 2026-11-26. Each /tar
	-- line that finds its NPC replaces the target, so the least wanted name goes first and the
	-- first-listed NPC last, to win when both are near.)
	local lines = { "/cleartarget" }
	for k = #names, 1, -1 do lines[#lines + 1] = "/tar " .. names[k] end
	-- the game cuts macros at 255 characters: drop the least wanted names until it fits
	while #lines > 2 and #table.concat(lines, "\n") + 1 + #tail > MAX_MACRO do table.remove(lines, 2) end
	if tail ~= "" then lines[#lines + 1] = tail end
	return table.concat(lines, "\n")
end

local function apply()
	if not btn then return end
	if InCombatLockdown() then pending = true return end
	pending = false
	btn:SetAttribute("macrotext", wanted)
end

-- The plan changed: point the key at the next NPC step's NPC.
function NS.Update(plan)
	wanted = buildMacro(plan)
	apply()
end

function NS.Init()
	btn = CreateFrame("Button", BUTTON, UIParent, "SecureActionButtonTemplate")
	btn:SetSize(1, 1)
	btn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
	btn:SetAlpha(0)
	local down = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
	btn:RegisterForClicks(down and "AnyDown" or "AnyUp")
	btn:SetAttribute("type", "macro")
	btn:SetAttribute("macrotext", "")

	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	f:SetScript("OnEvent", function() if pending then apply() end end)
end
