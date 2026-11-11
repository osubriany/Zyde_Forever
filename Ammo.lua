-- Zyde_Forever: hunter ammo.
--   * Arrows / bullets left and roughly how long they last, as an extra line
--     in the XP readout (colors: yellow under 400, red under 200).
--   * A warning when you leave a town or inn low on ammo.
--   * At a vendor that sells ammo you can use: a "Fill quiver" button that
--     shows how many it will buy and the cost. Nothing is bought until you
--     click it.
-- "How long" counts only time spent out of towns and not AFK, over the last
-- 30 minutes of that, and starts over after a /reload.
--
-- /zyde ammowarn <number> - warn when leaving town with fewer shots than this

local ADDON, ns = ...

local _, playerClass = UnitClass("player")
local IS_HUNTER = playerClass == "HUNTER"

local INV_AMMO, INV_RANGED = 0, 18
local AMMO_CLASS = 6                                     -- "Projectile"
local ARROW, BULLET = 2, 3                               -- projectile subclasses
local WEAPON_AMMO = { [2] = ARROW, [18] = ARROW, [3] = BULLET } -- bow, crossbow, gun
local BAG_FAMILY = { [ARROW] = 1, [BULLET] = 2 }         -- quiver, ammo pouch
local LABEL = { [ARROW] = "Arrows", [BULLET] = "Bullets" }
local YELLOW_AT, RED_AT = 400, 200
local WARN_DEFAULT = 600
local RATE_WINDOW, MIN_WINDOW, MIN_USED = 30 * 60, 3 * 60, 20
local P = "|cff66ccffZyde_Forever|r: "

local function db() ZydeForeverDB = ZydeForeverDB or {} return ZydeForeverDB end
local function on() return IS_HUNTER and ns.F("ammo") end

local function itemInfo(x)
	local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	return f(x)
end
local function itemInstant(x)
	local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	return f(x)
end
local function itemCount(id)
	local f = (C_Item and C_Item.GetItemCount) or GetItemCount
	return tonumber(ns.safe(f, id)) or 0
end
local function num(n) return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n) end
local function money(c)
	if GetMoneyString then return GetMoneyString(c, true) end
	if GetCoinTextureString then return GetCoinTextureString(c) end
	return ("%dc"):format(c)
end

---------------------------------------------------------------------------
-- What you shoot and how much of it you have
---------------------------------------------------------------------------
-- ARROW or BULLET for the equipped ranged weapon, or nil (wand, thrown, none).
local function ammoKind()
	local id = GetInventoryItemID("player", INV_RANGED)
	if not id then return nil end
	local _, _, _, _, _, classID, subclassID = itemInstant(id)
	if classID ~= 2 then return nil end
	return WEAPON_AMMO[subclassID]
end

local function projectileKind(id)
	local _, _, _, _, _, classID, subclassID = itemInstant(id)
	if classID == AMMO_CLASS then return subclassID end
	return nil
end

-- Equipped ammo item ID and how many of it are in your bags (counted stack
-- by stack, so every stack counts whatever the game's own count says).
local function equipped()
	local id = GetInventoryItemID("player", INV_AMMO)
	if not id then return nil, 0 end
	local n = 0
	for _, info in ipairs(ns.Bags.items()) do
		if info.itemID == id then n = n + (tonumber(info.stackCount) or 1) end
	end
	return id, math.max(n, itemCount(id))
end

-- Ammo of the right kind in your bags that isn't the equipped item.
local function spareAmmo(kind, skipID)
	local total, byItem = 0, {}
	for _, info in ipairs(ns.Bags.items()) do
		local id = info.itemID
		if id ~= skipID and projectileKind(id) == kind then
			local n = tonumber(info.stackCount) or 1
			total = total + n
			byItem[id] = (byItem[id] or 0) + n
		end
	end
	return total, byItem
end

---------------------------------------------------------------------------
-- How fast you use it: shots per second of "field time" (out of towns,
-- not AFK, not flying), over the last 30 minutes of that.
---------------------------------------------------------------------------
local fieldClock, clockStart = 0, 0
local uses = {} -- { {fieldClock, shots}, ... }
local lastID, lastCount

local function prune()
	local keep = {}
	for _, u in ipairs(uses) do
		if fieldClock - u[1] <= RATE_WINDOW then keep[#keep + 1] = u end
	end
	uses = keep
end

local function rate()
	local window = math.min(RATE_WINDOW, fieldClock - clockStart)
	if window < MIN_WINDOW then return nil end
	local used = 0
	for _, u in ipairs(uses) do
		if fieldClock - u[1] <= RATE_WINDOW then used = used + u[2] end
	end
	if used < MIN_USED then return nil end
	return used / window
end

-- Called when bags change: a small drop in the equipped stack is shots fired.
-- Big drops (a stack destroyed) and anything at a merchant don't count.
local function track()
	local id, n = equipped()
	if id and id == lastID and lastCount and n < lastCount then
		local d = lastCount - n
		local atMerchant = MerchantFrame and MerchantFrame:IsShown()
		if d < 20 and not atMerchant then
			uses[#uses + 1] = { fieldClock, d }
			prune()
		end
	end
	lastID, lastCount = id, n
end

C_Timer.NewTicker(1, function()
	if not IS_HUNTER then return end
	local idle = IsResting() or (UnitIsAFK and UnitIsAFK("player")) or (UnitOnTaxi and UnitOnTaxi("player"))
		or UnitIsDeadOrGhost("player")
	if not idle then fieldClock = fieldClock + 1 end
end)

---------------------------------------------------------------------------
-- Line for the XP readout, and its tooltip
---------------------------------------------------------------------------
local Ammo = {}

-- text, r, g, b - or nil when there's nothing to show.
function Ammo.Line()
	if not on() then return nil end
	local kind = ammoKind()
	if not kind then return nil end
	local label = LABEL[kind]
	local id, n = equipped()
	if not id or n == 0 then
		local spare = spareAmmo(kind)
		if spare > 0 then return ("%s: none equipped"):format(label), 1, 0.25, 0.2 end
		return ("No %s!"):format(label:lower()), 1, 0.25, 0.2
	end
	if projectileKind(id) ~= kind then return "Wrong ammo!", 1, 0.25, 0.2 end
	-- Other arrows of the right kind count too (one total, e.g. "Arrows 822"):
	-- you can equip them when the current ones run out.
	local spare = spareAmmo(kind, id)
	local total = n + spare
	local r, g, b = 0.85, 0.85, 0.85
	if total < RED_AT then r, g, b = 1, 0.25, 0.2 elseif total < YELLOW_AT then r, g, b = 1, 0.82, 0 end
	local per = rate()
	local left = per and ns.formatTime and (" (" .. ns.formatTime(total / per) .. ")") or ""
	return ("%s %s%s"):format(label, num(total), left), r, g, b
end

function Ammo.Tooltip(tt)
	if not on() then return end
	local kind = ammoKind()
	if not kind then return end
	local id, n = equipped()
	local spare, byItem = spareAmmo(kind, id)
	tt:AddLine(LABEL[kind], 1, 0.82, 0)
	if id then
		local name = itemInfo(id) or ("item " .. id)
		tt:AddDoubleLine(name, num(n), 1, 1, 1, 1, 1, 1)
	else
		tt:AddLine("No ammo equipped", 1, 0.25, 0.2)
	end
	for otherID, c in pairs(byItem) do
		tt:AddDoubleLine((itemInfo(otherID) or ("item " .. otherID)) .. " (in bags)", num(c), 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
	end
	local per = rate()
	tt:AddDoubleLine("Shots per minute", per and ("%.1f"):format(per * 60) or "--", 1, 1, 1, 0.85, 0.85, 0.85)
	tt:AddDoubleLine("Lasts about", (per and n + spare > 0 and ns.formatTime) and ns.formatTime((n + spare) / per) or "--", 1, 1, 1, 0.85, 0.85, 0.85)
	if spare > 0 and id and n > 0 then
		tt:AddLine("When these run out, drag the other arrows onto your ammo slot", 0.6, 0.6, 0.6, true)
	end
	tt:AddLine("Time counts only while out of town and not AFK", 0.6, 0.6, 0.6)
	tt:AddLine(("Click the %s line: waypoint to the nearest %s vendor"):format(LABEL[kind], LABEL[kind]:lower():gsub("s$", "")), 0.4, 1, 0.4)
	if spare > 0 and (not id or n == 0) then
		tt:AddLine("Drag spare ammo onto your ammo slot to equip it", 1, 0.82, 0, true)
	end
end

local updatePending = false
local function updateSoon()
	if updatePending then return end
	updatePending = true
	C_Timer.After(0.3, function()
		updatePending = false
		if ns.UpdateXP then ns.UpdateXP() end
	end)
end

---------------------------------------------------------------------------
-- Leaving town low on ammo
---------------------------------------------------------------------------
local wasResting, lastWarn = nil, 0

local function warnIfLow()
	local kind = ammoKind()
	if not kind or GetTime() - lastWarn < 300 then return end
	local id, n = equipped()
	if id and projectileKind(id) ~= kind then n = 0 end
	local total = n + spareAmmo(kind, id)
	local limit = db().ammoWarn or WARN_DEFAULT
	if total >= limit then return end
	lastWarn = GetTime()
	local msg = total == 0 and ("Leaving town with no " .. LABEL[kind]:lower() .. "!")
		or ("Leaving town with only %s %s"):format(num(total), LABEL[kind]:lower())
	if RaidNotice_AddMessage and RaidWarningFrame then
		RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.3, b = 0.2 })
	end
	if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
	print(P .. msg)
end

---------------------------------------------------------------------------
-- Vendor: "Fill quiver" button
---------------------------------------------------------------------------
local function merchantItem(i)
	if GetMerchantItemInfo then
		local name, _, price, batch, numAvailable, _, isUsable, extendedCost = GetMerchantItemInfo(i)
		return name, price, batch, numAvailable, isUsable, extendedCost
	end
	local info = C_MerchantFrame and C_MerchantFrame.GetItemInfo and C_MerchantFrame.GetItemInfo(i)
	if not info then return nil end
	return info.name, info.price, info.stackCount, info.numAvailable, info.isUsable, info.hasExtendedCost
end

-- The best ammo this vendor sells that you can shoot now.
local function bestOffer(kind)
	local best
	local level = UnitLevel("player") or 1
	for i = 1, (GetMerchantNumItems() or 0) do
		local link = GetMerchantItemLink(i)
		local name, price, batch, numAvailable, isUsable, extendedCost = merchantItem(i)
		if link and name and price and price > 0 and not extendedCost and isUsable ~= false and numAvailable ~= 0 then
			local _, _, _, itemLevel, minLevel, _, _, stackSize, _, _, _, classID, subclassID = itemInfo(link)
			if classID == AMMO_CLASS and subclassID == kind and (minLevel or 0) <= level then
				local id = tonumber(link:match("item:(%d+)"))
				local o = { index = i, id = id, link = link, name = name, price = price, batch = math.max(batch or 1, 1),
					itemLevel = itemLevel or 0, stack = stackSize or 200, numAvailable = numAvailable }
				o.each = o.price / o.batch
				if not best or o.itemLevel > best.itemLevel
					or (o.itemLevel == best.itemLevel and o.each < best.each) then
					best = o
				end
			end
		end
	end
	return best
end

-- How many of item `id` fit: free quiver / pouch slots plus room left in
-- stacks of it you already have. Without a quiver, up to 2 stacks in your
-- normal bags (keeping one slot free).
local function room(kind, id, stack)
	local fam = BAG_FAMILY[kind]
	local n, hasAmmoBag, normalFree = 0, false, 0
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		local free, bagType = C_Container.GetContainerNumFreeSlots(bag)
		bagType = tonumber(bagType) or 0
		if bag > 0 and bit.band(bagType, fam) ~= 0 then
			hasAmmoBag = true
			n = n + (free or 0) * stack
		elseif bagType == 0 then
			normalFree = normalFree + (free or 0)
		end
	end
	for _, info in ipairs(ns.Bags.items()) do
		if info.itemID == id then
			n = n + math.max(0, stack - (tonumber(info.stackCount) or stack))
		end
	end
	if not hasAmmoBag then n = n + math.min(2, math.max(0, normalFree - 1)) * stack end
	return n, hasAmmoBag
end

local buy = CreateFrame("Button", "ZydeForeverAmmoBuy", UIParent, "UIPanelButtonTemplate")
buy:SetHeight(24)
buy:SetFrameStrata("HIGH")
buy:Hide()
local plan -- what a click would buy

local function planPurchase()
	plan = nil
	if not (on() and MerchantFrame and MerchantFrame:IsShown()) then return end
	local kind = ammoKind()
	if not kind then return end
	local o = bestOffer(kind)
	if not o then return end
	if Ammo.LearnVendor then Ammo.LearnVendor(kind) end -- for "nearest vendor" later
	local fits, hasAmmoBag = room(kind, o.id, o.stack)
	local batches = math.floor(fits / o.batch)
	local affordable = math.floor((GetMoney() or 0) / o.price)
	batches = math.min(batches, affordable)
	if o.numAvailable and o.numAvailable > 0 then batches = math.min(batches, o.numAvailable) end
	if batches <= 0 then return end
	o.batches, o.amount, o.cost, o.hasAmmoBag = batches, batches * o.batch, batches * o.price, hasAmmoBag
	plan = o
end

local function drawBuy()
	planPurchase()
	if not plan then buy:Hide() return end
	buy:SetText(("%s: %s %s (%s)"):format(plan.hasAmmoBag and "Fill quiver" or "Buy ammo",
		num(plan.amount), plan.name, money(plan.cost)))
	buy:SetWidth(buy:GetFontString():GetStringWidth() + 24)
	buy:ClearAllPoints()
	buy:SetPoint("TOPLEFT", MerchantFrame, "BOTTOMLEFT", 0, -4)
	buy:Show()
end

buy:SetScript("OnEnter", function(self)
	if not plan then return end
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
	GameTooltip:SetHyperlink(plan.link)
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine("Buys", num(plan.amount), 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine("Costs", money(plan.cost), 1, 1, 1, 1, 1, 1)
	if not plan.hasAmmoBag then
		GameTooltip:AddLine("No quiver or ammo pouch: buys at most 2 stacks into your bags.", 0.7, 0.7, 0.7, true)
	end
	GameTooltip:Show()
end)
buy:SetScript("OnLeave", function() GameTooltip:Hide() end)

local buying = false
buy:SetScript("OnClick", function()
	if not plan or buying then return end
	local p = plan
	buying = true
	buy:Disable()
	-- Items the vendor sells in bundles (e.g. 200 arrows) are bought one
	-- bundle per call; single items in chunks of the most allowed per call.
	local calls = {}
	if p.batch > 1 then
		for _ = 1, p.batches do calls[#calls + 1] = false end
	else
		local maxCall = (GetMerchantItemMaxStack and GetMerchantItemMaxStack(p.index)) or p.stack
		local left = p.amount
		while left > 0 do
			local n = math.min(left, maxCall)
			calls[#calls + 1] = n
			left = left - n
		end
	end
	local i = 0
	local function step()
		i = i + 1
		if i > #calls or not (MerchantFrame and MerchantFrame:IsShown())
			or GetMerchantItemLink(p.index) ~= p.link then
			buying = false
			buy:Enable()
			print(P .. ("bought %s"):format(p.link))
			C_Timer.After(0.5, drawBuy)
			return
		end
		if calls[i] then BuyMerchantItem(p.index, calls[i]) else BuyMerchantItem(p.index) end
		C_Timer.After(0.2, step)
	end
	step()
end)

---------------------------------------------------------------------------
-- Nearest ammo vendor: click the Arrows line in the XP readout (or
-- /zyde ammovendor) for a waypoint. Vendors come from Questie's database
-- (who sells the standard arrows / bullets) plus every vendor you've seen
-- selling ammo yourself, which covers Forever-only vendors.
---------------------------------------------------------------------------
local VENDOR_ITEMS = {
	[ARROW]  = { 2512, 2515, 3030, 11285, 19316 },  -- Rough, Sharp, Razor, Jagged, Ice Threaded
	[BULLET] = { 2516, 2519, 3033, 11284, 19317 },  -- Light Shot, Heavy Shot, Solid Shot, Accurate Slugs, Iron Shot
}

local function questie(name)
	if not QuestieLoader then return nil end
	local ok, m = pcall(QuestieLoader.ImportModule, QuestieLoader, name)
	return ok and m or nil
end

local function myFaction()
	local f = UnitFactionGroup("player")
	return f == "Alliance" and "A" or (f == "Horde" and "H" or nil)
end

-- Where you are: continent and world position (to compare across zones).
local function worldPos(uiMapId, x, y)
	if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
	local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, uiMapId, CreateVector2D(x, y))
	if not ok or not continent or not pos then return nil end
	return continent, pos.x, pos.y
end

local function playerWorld()
	local map = C_Map.GetBestMapForUnit("player")
	local p = map and C_Map.GetPlayerMapPosition(map, "player")
	if not p then return nil end
	return map, p.x, p.y, worldPos(map, p.x, p.y)
end

-- Remember this merchant if it sells ammo of `kind` (called at vendors).
local function learnVendor(kind)
	local guid = UnitGUID("npc")
	if not guid or ns.isSecret(guid) then return end
	local npcId = tonumber((select(6, strsplit("-", guid))))
	local map, x, y = playerWorld()
	if not (npcId and map) then return end
	local d = db()
	d.ammoVendors = d.ammoVendors or {}
	d.ammoVendors[kind .. ":" .. npcId] = { kind = kind, npc = npcId, name = UnitName("npc"), map = map, x = x, y = y }
end
Ammo.LearnVendor = learnVendor

-- { name, map, x, y (0-1), dist } of the closest vendor on your continent.
local function nearestVendor(kind)
	local _, _, _, continent, px, py = playerWorld()
	if not continent then return nil end
	local best
	local function consider(name, map, x, y)
		local c, wx, wy = worldPos(map, x, y)
		if c ~= continent then return end
		local dist = math.sqrt((wx - px) ^ 2 + (wy - py) ^ 2)
		if not best or dist < best.dist then best = { name = name, map = map, x = x, y = y, dist = dist } end
	end

	for _, v in pairs(db().ammoVendors or {}) do
		if v.kind == kind then consider(v.name or "Ammo vendor", v.map, v.x, v.y) end
	end

	local DB, ZDB = questie("QuestieDB"), questie("ZoneDB")
	if DB and ZDB and DB.QueryItemSingle then
		local faction, seen = myFaction(), {}
		for _, item in ipairs(VENDOR_ITEMS[kind] or {}) do
			local vendors = select(2, pcall(DB.QueryItemSingle, item, "vendors"))
			for _, npc in ipairs(type(vendors) == "table" and vendors or {}) do
				if not seen[npc] then
					seen[npc] = true
					local friendly = select(2, pcall(DB.QueryNPCSingle, npc, "friendlyToFaction"))
					if not friendly or friendly == "AH" or friendly == faction then
						local name = select(2, pcall(DB.QueryNPCSingle, npc, "name"))
						local spawns = select(2, pcall(DB.QueryNPCSingle, npc, "spawns"))
						for areaId, points in pairs(type(spawns) == "table" and spawns or {}) do
							local ok, map = pcall(ZDB.GetUiMapIdByAreaId, ZDB, areaId)
							if ok and map then
								for _, pt in ipairs(points) do
									if pt[1] and pt[1] > 0 then consider(name, map, pt[1] / 100, pt[2] / 100) end
								end
							end
						end
					end
				end
			end
		end
	end
	return best
end

function Ammo.WaypointToVendor()
	local kind = ammoKind() or ARROW
	local v = nearestVendor(kind)
	local what = LABEL[kind]:lower()
	if not v then
		print(P .. "no " .. what .. " vendor known on this continent" .. (questie("QuestieDB") and "" or " (Questie isn't loaded)"))
		return
	end
	local set = false
	if C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(v.map) and UiMapPoint then
		set = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(v.map, v.x, v.y))
		if set and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
			pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
		end
	end
	if TomTom and TomTom.AddWaypoint then
		pcall(TomTom.AddWaypoint, TomTom, v.map, v.x, v.y, { title = (v.name or "Ammo vendor") .. " (" .. what .. ")", from = "Zyde_Forever" })
		set = true
	end
	local mapInfo = C_Map.GetMapInfo(v.map)
	print(P .. ("nearest %s vendor: %s, %s %.1f, %.1f%s"):format(what, v.name or "?", mapInfo and mapInfo.name or "",
		v.x * 100, v.y * 100, set and " - waypoint set" or ""))
end

-- Clicking the Arrows line in the XP readout sets the waypoint; dragging,
-- hovering and right-clicking still work like on the rest of the readout.
local function hookReadout()
	local xp = _G.ZydeForeverXP
	if not (xp and xp.ammo) or xp.ammoHit then return end
	local hit = CreateFrame("Button", nil, xp)
	hit:SetPoint("TOPLEFT", xp.ammo, "TOPLEFT", -6, 2)
	hit:SetPoint("BOTTOMRIGHT", xp.ammo, "BOTTOMRIGHT", 6, -2)
	hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	hit:RegisterForDrag("LeftButton")
	local function pass(script, ...) local fn = xp:GetScript(script) if fn then fn(xp, ...) end end
	hit:SetScript("OnDragStart", function() pass("OnDragStart") end)
	hit:SetScript("OnDragStop", function() pass("OnDragStop") end)
	hit:SetScript("OnEnter", function() pass("OnEnter") end)
	hit:SetScript("OnLeave", function() pass("OnLeave") end)
	hit:SetScript("OnClick", function(_, button)
		if button == "RightButton" then pass("OnMouseUp", "RightButton") else Ammo.WaypointToVendor() end
	end)
	hit:SetShown(xp.ammo:IsShown())
	hooksecurefunc(xp.ammo, "Show", function() hit:Show() end)
	hooksecurefunc(xp.ammo, "Hide", function() hit:Hide() end)
	xp.ammoHit = hit
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, arg1)
	if event == "PLAYER_LOGIN" then
		if not IS_HUNTER then return end
		for _, e in ipairs({ "BAG_UPDATE_DELAYED", "UNIT_INVENTORY_CHANGED", "PLAYER_EQUIPMENT_CHANGED",
			"PLAYER_UPDATE_RESTING", "MERCHANT_SHOW", "MERCHANT_CLOSED", "MERCHANT_UPDATE",
			"PLAYER_MONEY", "GET_ITEM_INFO_RECEIVED" }) do
			pcall(ev.RegisterEvent, ev, e)
		end
		wasResting = IsResting()
		lastID, lastCount = equipped()
		hookReadout()
		updateSoon()
		return
	end
	if event == "PLAYER_UPDATE_RESTING" then
		local now = IsResting()
		if wasResting and not now and on() then warnIfLow() end
		wasResting = now
		return
	end
	if event == "UNIT_INVENTORY_CHANGED" and arg1 ~= "player" then return end
	if event == "MERCHANT_CLOSED" then buy:Hide() plan = nil end
	if event == "MERCHANT_SHOW" then C_Timer.After(0.2, drawBuy) return end -- frame opens after the event
	if event == "BAG_UPDATE_DELAYED" or event == "UNIT_INVENTORY_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED" then
		track()
		updateSoon()
	end
	if MerchantFrame and MerchantFrame:IsShown() and not buying and event ~= "MERCHANT_CLOSED" then
		if event ~= "GET_ITEM_INFO_RECEIVED" or not plan then drawBuy() end
	end
end)

ns.OnFeatureChanged(function(key)
	if key ~= "ammo" then return end
	updateSoon()
	if MerchantFrame and MerchantFrame:IsShown() then drawBuy() else buy:Hide() end
end)

function Ammo.SetWarn(n)
	if not n then
		print(P .. ("leaving-town ammo warning below %s shots. Use /zyde ammowarn <number> to change it (0 turns it off)")
			:format(num(db().ammoWarn or WARN_DEFAULT)))
		return
	end
	db().ammoWarn = n
	print(P .. (n > 0 and ("will warn when leaving town with fewer than %s shots"):format(num(n))
		or "leaving-town ammo warning off"))
end

ns.Ammo = Ammo
