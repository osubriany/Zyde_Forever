-- Zyde_Forever: drop chance under Questie's nameplate loot bag.
-- Questie puts a small bag icon left of the nameplate of mobs that drop an
-- item you still need. Under it we add:
--   line 1: the item's drop chance (same number as Questie's tooltip)
--   line 2: which kill the next one will be since the item last dropped,
--           and the chance of at least one drop by the end of that kill:
--           P = 1 - (1 - p)^n   (p = drop chance, n = attempts so far + 1)
--           Shown once you've had at least one kill without the drop.
-- An attempt is one corpse you could loot (killed by you or your group).
-- When the item drops, its attempt counts reset.
-- Does nothing if Questie isn't loaded.

local ADDON, ns = ...

local NP, TT, DB

local function plain(v)
	if v == nil or ns.isSecret(v) then return nil end
	return v
end

-- Questie's own number style: 45% / 4.5% / 0.45% / 0.045%
local function formatRate(r)
	if r >= 10 then return ("%.0f"):format(r)
	elseif r >= 2 then return ("%.1f"):format(r)
	elseif r >= 0.01 then return ("%.2f"):format(r)
	end
	return ("%.3f"):format(r)
end

local function npcFromGUID(guid)
	guid = plain(guid)
	if type(guid) ~= "string" then return nil end
	local unitType, _, _, _, _, npcId = strsplit("-", guid)
	if (unitType ~= "Creature" and unitType ~= "Vehicle") or not npcId then return nil end
	return tonumber(npcId)
end

-- Unfinished quest items this mob drops: { [itemId] = drop % }. Remembered per
-- mob (callers only read it) until your quests change, and at least every 5 s,
-- since Questie fills in its data some seconds after login.
local dropCache = {}
local NONE = {}
local function questDrops(npcId)
	if not npcId then return NONE end
	local cached = dropCache[npcId]
	if cached then return cached end
	local out = {}
	dropCache[npcId] = out
	local tips = TT and TT.lookupByKey and TT.lookupByKey["m_" .. npcId]
	if not tips then return out end
	for _, tip in pairs(tips) do
		local obj = tip.objective
		if obj and not obj.Completed and obj.Id and obj.Type == "item" then
			local data = ns.safe(DB.GetItemDroprate, obj.Id, npcId)
			local r = type(data) == "table" and tonumber(data[1])
			if r and r > 0 and (not out[obj.Id] or r > out[obj.Id]) then out[obj.Id] = r end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Attempt counting: ZydeForeverDB.dropTries["itemId:npcId"] = attempts
---------------------------------------------------------------------------
local counted = {} -- corpse GUID -> time, so a corpse only counts once

local function tries()
	ZydeForeverDB = ZydeForeverDB or {}
	ZydeForeverDB.dropTries = ZydeForeverDB.dropTries or {}
	return ZydeForeverDB.dropTries
end

local function countAttempt(guid)
	guid = plain(guid)
	if not guid or counted[guid] then return end
	local npcId = npcFromGUID(guid)
	if not npcId then return end
	local drops = questDrops(npcId)
	if not next(drops) then return end
	counted[guid] = GetTime()
	local t = tries()
	for itemId in pairs(drops) do
		local key = itemId .. ":" .. npcId
		t[key] = (t[key] or 0) + 1
	end
end

local function itemDropped(itemId)
	local t, prefix = tries(), itemId .. ":"
	for key in pairs(t) do
		if key:sub(1, #prefix) == prefix then t[key] = nil end
	end
end

-- A mob died that you or your group tagged (its nameplate still exists).
local function checkDeath(token)
	if not (token and token:find("^nameplate")) then return end
	if plain(UnitIsDead(token)) ~= true then return end
	if plain(UnitIsTapDenied(token)) ~= false then return end -- someone else's kill
	countAttempt(UnitGUID(token))
end

-- Loot window: count each corpse, and reset when a quest item is in it.
local function onLoot()
	local n = GetNumLootItems and GetNumLootItems() or 0
	for slot = 1, n do
		if GetLootSourceInfo then
			local src = { GetLootSourceInfo(slot) }
			for i = 1, #src, 2 do countAttempt(src[i]) end
		end
	end
	if not (GetLootSourceInfo and n > 0) and UnitExists("target") then
		countAttempt(UnitGUID("target")) -- older clients: assume the target corpse
	end
	for slot = 1, n do
		local link = plain(GetLootSlotLink(slot))
		local itemId = link and tonumber(link:match("item:(%d+)"))
		if itemId then itemDropped(itemId) end
	end
end

---------------------------------------------------------------------------
-- Nameplate text
---------------------------------------------------------------------------
-- Questie's icon frame on a nameplate: a child with .Icon and .lastIcon.
local function questieIcon(plate)
	for _, child in ipairs({ plate:GetChildren() }) do
		if child.Icon and child.lastIcon and child:IsShown() then return child end
	end
end

local function rateColor(r)
	if r >= 25 then return 0.45, 1, 0.45 end   -- green: drops often
	if r >= 5 then return 1, 0.85, 0.3 end     -- yellow
	return 1, 0.5, 0.35                        -- orange: rare
end

local function newText(icon, anchor)
	local fs = icon:CreateFontString(nil, "OVERLAY")
	fs:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
	fs:SetPoint("TOP", anchor, "BOTTOM", 0, -1)
	return fs
end

local function refresh(token)
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(token)
	if not plate then return end
	local ok, icon = pcall(questieIcon, plate)
	if not ok or not icon then return end

	if not ns.F("questieDrops") then
		if icon.zydeDrop then icon.zydeDrop:Hide() icon.zydeOdds:Hide() end
		return
	end
	if not icon.zydeDrop then
		icon.zydeDrop = newText(icon, icon)
		icon.zydeOdds = newText(icon, icon.zydeDrop)
		icon.zydeOdds:SetTextColor(0.8, 0.8, 0.8)
	end

	-- The item with the best drop chance from this mob.
	local npcId = npcFromGUID(UnitGUID(token))
	local bestId, r
	for itemId, rate in pairs(questDrops(npcId)) do
		if not r or rate > r then bestId, r = itemId, rate end
	end

	if not r then
		icon.zydeDrop:Hide() -- Questie reuses icon frames: clear old numbers
		icon.zydeOdds:Hide()
		return
	end
	icon.zydeDrop:SetText(formatRate(r) .. "%")
	icon.zydeDrop:SetTextColor(rateColor(r))
	icon.zydeDrop:Show()

	-- Looking ahead to the next kill: after 1 kill with no drop it shows
	-- "2x 64%" (40% item) - the chance of a drop by the end of kill number 2.
	local n = tries()[bestId .. ":" .. npcId] or 0
	if n > 0 then
		local nextKill = n + 1
		local p = math.min(r / 100, 1)
		local chance = (1 - (1 - p) ^ nextKill) * 100
		icon.zydeOdds:SetFormattedText("%dx %d%%", nextKill, math.floor(chance + 0.5))
		icon.zydeOdds:Show()
	else
		icon.zydeOdds:Hide()
	end
end

local function refreshAll()
	for i = 1, 40 do
		local token = "nameplate" .. i
		if UnitExists(token) then refresh(token) end
	end
	-- forget corpses older than 10 minutes
	local now = GetTime()
	for guid, t in pairs(counted) do
		if now - t > 600 then counted[guid] = nil end
	end
end

-- Questie calls UpdateNameplate once per changed quest, several in a row:
-- redraw once, a moment after the last one.
local pending = false
local function refreshAllSoon()
	wipe(dropCache)
	if pending then return end
	pending = true
	C_Timer.After(0.1, function() pending = false refreshAll() end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, token)
	if event == "PLAYER_LOGIN" then
		if not (QuestieLoader and QuestieLoader.ImportModule) then return end
		NP = QuestieLoader:ImportModule("QuestieNameplate")
		TT = QuestieLoader:ImportModule("QuestieTooltips")
		DB = QuestieLoader:ImportModule("QuestieDB")
		if NP and NP.UpdateNameplate then hooksecurefunc(NP, "UpdateNameplate", refreshAllSoon) end
		for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_HEALTH", "LOOT_READY", "LOOT_OPENED",
			"QUEST_LOG_UPDATE" }) do
			pcall(f.RegisterEvent, f, e)
		end
		C_Timer.NewTicker(1, refreshAll) -- catches objective progress and reused frames
		C_Timer.NewTicker(5, function() wipe(dropCache) end)
	elseif event == "QUEST_LOG_UPDATE" then
		wipe(dropCache)
	elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
		onLoot()
		refreshAll()
	elseif event == "UNIT_HEALTH" or event == "NAME_PLATE_UNIT_REMOVED" then
		checkDeath(token)
	elseif event == "NAME_PLATE_UNIT_ADDED" and token then
		-- Let Questie add its icon first, then add our numbers under it.
		C_Timer.After(0, function() refresh(token) end)
	end
end)
