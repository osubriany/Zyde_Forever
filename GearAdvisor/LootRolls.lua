-- LootRolls (phase d): a line above each Need/Greed roll window ("GearAdvisor: Upgrade +6.1% – need it")
-- and the upgrade arrow on the item icon.
-- Game facts (seen working on Forever by SimGearForever, 2026-10-20/22): GroupLootFrame1..4,
-- frame.rollID, GetLootRollItemLink(rollID); a roll that starts in combat can have a secret link.
-- Not confirmed: the icon's field name (IconFrame or Icon), so both are tried.
local _, zyde = ...
zyde.GA = zyde.GA or {}
local ns = zyde.GA

local LootRolls = {}
ns.LootRolls = LootRolls

local lines, hooked = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
local afterCombat = {}

local function enabled() return ns.db and ns.db.rollMarks end

local function lineOf(frame)
	if not lines[frame] then
		local line = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		line:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 4, 2)
		line:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -4, 2)
		line:SetJustifyH("LEFT")
		lines[frame] = line
	end
	return lines[frame]
end

local function iconOf(frame) return frame.IconFrame or frame.Icon or frame end

-- What to say on the roll, from a compare result.
local ADVICE = { upgrade = " – need it", future = " – worth keeping" }

function LootRolls.update(frame, tries)
	if lines[frame] then lines[frame]:Hide() end
	ns.Marks.hide(iconOf(frame))
	if not (enabled() and frame:IsShown()) then return end
	local rollID = frame.rollID
	if rollID == nil or ns.isSecret(rollID) then return end
	local link = GetLootRollItemLink and GetLootRollItemLink(rollID)
	if ns.isSecret(link) then
		-- Secret in combat: try again once combat ends, if this roll is still up.
		afterCombat[frame] = rollID
		return
	end
	if not link or not ns.Stats.isGear(link) then return end
	local ok, r = pcall(ns.Score.compare, link)
	if not ok or type(r) ~= "table" then return end
	if r.kind == "loading" then
		if (tries or 0) < 10 then
			C_Timer.After(0.3, function()
				if frame.rollID == rollID then LootRolls.update(frame, (tries or 0) + 1) end
			end)
		end
		return
	end
	local text, cr, cg, cb = ns.headline(r)
	if not text then return end
	local line = lineOf(frame)
	line:SetText("GearAdvisor: " .. text .. (ADVICE[r.kind] or ""))
	line:SetTextColor(cr, cg, cb)
	line:Show()
	ns.Marks.apply(iconOf(frame), link)
end

local function frames()
	local out = {}
	for i = 1, NUM_GROUP_LOOT_FRAMES or 4 do
		local f = _G["GroupLootFrame" .. i]
		if f then out[#out + 1] = f end
	end
	return out
end

local function hookFrames()
	for _, frame in ipairs(frames()) do
		if not hooked[frame] and frame.HookScript then
			hooked[frame] = true
			-- A frame later, so rollID is set before we read it.
			frame:HookScript("OnShow", function(self) C_Timer.After(0, function() LootRolls.update(self) end) end)
		end
	end
end

local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "START_LOOT_ROLL", "PLAYER_REGEN_ENABLED" }) do pcall(events.RegisterEvent, events, e) end
events:SetScript("OnEvent", function(_, event)
	hookFrames()
	if event == "START_LOOT_ROLL" then
		C_Timer.After(0.1, function()
			for _, frame in ipairs(frames()) do if frame:IsShown() then LootRolls.update(frame) end end
		end)
	elseif event == "PLAYER_REGEN_ENABLED" then
		for frame, rollID in pairs(afterCombat) do
			afterCombat[frame] = nil
			if frame.rollID == rollID then LootRolls.update(frame) end
		end
	end
end)
