-- Counts on item tooltips. Bags is the backpack plus the other bags you have
-- on, including the reagent bag and the keyring, as one number. Each character's
-- bags are saved while you play them, and the bank is saved when you open
-- it, so the tooltip can list your other characters from the last time
-- they were logged in.

local _, ns = ...

local LAST = NUM_BAG_SLOTS or 4
local REAGENT = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or REAGENTBAG_CONTAINER
local KEYRING = (Enum and Enum.BagIndex and Enum.BagIndex.Keyring) or KEYRING_CONTAINER
local REAGENT_BANK = (Enum and Enum.BagIndex and (Enum.BagIndex.Reagentbank or Enum.BagIndex.ReagentBank)) or REAGENTBANK_CONTAINER

local function secret(v)
	return ns.isSecret and ns.isSecret(v) or false
end

local function numSlots(bag)
	if type(bag) ~= "number" or not (C_Container and C_Container.GetContainerNumSlots) then return 0 end
	local ok, n = pcall(C_Container.GetContainerNumSlots, bag)
	if not ok or secret(n) or type(n) ~= "number" or n < 0 then return 0 end
	return n
end

local function addBag(bag, into)
	local slots = numSlots(bag)
	if slots <= 0 or not (C_Container and C_Container.GetContainerItemInfo) then return end
	for slot = 1, slots do
		local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
		if ok and type(info) == "table" and not secret(info) then
			local id = info.itemID
			if type(id) == "number" and not secret(id) then
				local n = info.stackCount
				if secret(n) or type(n) ~= "number" or n < 1 then n = 1 end
				into[id] = (into[id] or 0) + n
			end
		end
	end
end

-- Bags other than the backpack. A reagent bag or keyring that is already
-- one of those bag numbers is not counted twice.
local function otherBags()
	local list = {}
	for bag = 1, LAST do list[#list + 1] = bag end
	local function extra(bag)
		if type(bag) ~= "number" or bag == 0 or (bag >= 1 and bag <= LAST) then return end
		for _, have in ipairs(list) do
			if have == bag then return end
		end
		list[#list + 1] = bag
	end
	extra(REAGENT)
	extra(KEYRING)
	return list
end

local function bankBags()
	local list, seen = {}, {}
	local key = type(KEYRING) == "number" and KEYRING or nil
	local main = Enum and Enum.BagIndex and Enum.BagIndex.Bank
	if type(main) ~= "number" or main == key then main = BANK_CONTAINER end
	if (type(main) ~= "number" or main == key) and key == nil then main = -1 end
	local function push(bag)
		if type(bag) ~= "number" or bag == key or bag == REAGENT or seen[bag] then return end
		if numSlots(bag) <= 0 then return end
		seen[bag] = true
		list[#list + 1] = bag
	end
	push(main)
	if type(REAGENT_BANK) == "number" then push(REAGENT_BANK) end
	local startAt = LAST + 1
	if type(REAGENT) == "number" and REAGENT >= startAt then startAt = REAGENT + 1 end
	for bag = startAt, LAST + 14 do push(bag) end
	return list
end

local wornList
local function wornSlots()
	if wornList then return wornList end
	local list, seen = {}, {}
	local function push(slot)
		if type(slot) ~= "number" or seen[slot] then return end
		seen[slot] = true
		list[#list + 1] = slot
	end
	local last = INVSLOT_LAST_EQUIPPED or 19
	for slot = 1, last do push(slot) end
	local toInv = C_Container and C_Container.ContainerIDToInventoryID
	if toInv then
		for bag = 1, LAST do
			local ok, slot = pcall(toInv, bag)
			if ok then push(slot) end
		end
		if type(REAGENT) == "number" then
			local ok, slot = pcall(toInv, REAGENT)
			if ok then push(slot) end
		end
	end
	wornList = list
	return list
end

local function character()
	local name = UnitName("player")
	if secret(name) or type(name) ~= "string" or name == "" then return end
	local realm = GetRealmName and GetRealmName()
	if secret(realm) or type(realm) ~= "string" then realm = "" end
	local _, class = UnitClass("player")
	if secret(class) or type(class) ~= "string" then class = nil end
	return name, realm, class
end

local function accounts()
	ZydeForeverDB = ZydeForeverDB or {}
	if type(ZydeForeverDB.itemCounts) ~= "table" then ZydeForeverDB.itemCounts = {} end
	return ZydeForeverDB.itemCounts
end

local function copyMap(src)
	local out = {}
	for id, n in pairs(src) do
		if type(id) == "number" and type(n) == "number" and n > 0 then out[id] = n end
	end
	return out
end

local function have(map, id)
	if type(map) ~= "table" then return 0 end
	local n = map[id]
	if secret(n) or type(n) ~= "number" then return 0 end
	return n
end

-- The bank window already remembers the last visit (bag window). Use that
-- until this character opens the bank again.
local function bankMemory(name)
	local all = ZydeForeverDB and ZydeForeverDB.bankSeen
	local row = type(all) == "table" and all[name]
	if type(row) ~= "table" or type(row.items) ~= "table" then return nil end
	local map = {}
	for _, it in ipairs(row.items) do
		if type(it) == "table" then
			local id = it.id
			if type(id) == "number" and not secret(id) then
				local n = it.n
				if secret(n) or type(n) ~= "number" or n < 1 then n = 1 end
				map[id] = (map[id] or 0) + n
			end
		end
	end
	return map
end

local liveBp, liveBags, liveWorn = {}, {}, {}
local liveDirty = true

local function ensureLive()
	if not liveDirty then return liveBp, liveBags, liveWorn end
	liveDirty = false
	liveBp, liveBags, liveWorn = {}, {}, {}
	addBag(0, liveBp)
	for _, bag in ipairs(otherBags()) do addBag(bag, liveBags) end
	if GetInventoryItemID then
		for _, slot in ipairs(wornSlots()) do
			local ok, id = pcall(GetInventoryItemID, "player", slot)
			if ok and type(id) == "number" and not secret(id) then
				liveWorn[id] = (liveWorn[id] or 0) + 1
			end
		end
	end
	return liveBp, liveBags, liveWorn
end

local function scanCarried()
	local name, realm, class = character()
	if not name then return end
	liveDirty = true
	local bp, bags, worn = ensureLive()
	local row = accounts()[name]
	if type(row) ~= "table" then
		row = {}
		accounts()[name] = row
	end
	row.name = name
	if realm ~= "" then row.realm = realm end
	if class then row.class = class end
	row.backpack = copyMap(bp)
	row.bags = copyMap(bags)
	row.worn = copyMap(worn)
	row.when = time()
end

local function bankOpen()
	return BankFrame and BankFrame.IsShown and BankFrame:IsShown() and true or false
end

local function scanBank()
	if not bankOpen() then return end
	local name, realm, class = character()
	if not name then return end
	local bags = bankBags()
	if #bags == 0 then return end
	local bank = {}
	for _, bag in ipairs(bags) do addBag(bag, bank) end
	local row = accounts()[name]
	if type(row) ~= "table" then
		row = { name = name }
		accounts()[name] = row
	end
	-- Slots still there but the items already gone: the bank is closing.
	if not next(bank) and type(row.bank) == "table" and next(row.bank) then return end
	row.name = name
	if realm ~= "" then row.realm = realm end
	if class then row.class = class end
	row.bank = copyMap(bank)
	row.bankSeen = true
	row.when = time()
end

local waitBags, waitBank
local function schedule(kind)
	if kind == "bank" then
		if waitBank then return end
		waitBank = true
		C_Timer.After(0.3, function()
			waitBank = false
			scanBank()
		end)
		return
	end
	if waitBags then return end
	waitBags = true
	liveDirty = true
	C_Timer.After(0.3, function()
		waitBags = false
		scanCarried()
	end)
end

local ready = false
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("BAG_UPDATE")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
ev:RegisterEvent("BANKFRAME_OPENED")
ev:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then ready = true end
	if not ready then return end
	if event == "BANKFRAME_OPENED" or event == "PLAYERBANKSLOTS_CHANGED" then
		schedule("bank")
	end
	schedule("bags")
end)

local function itemID(tip, data)
	if type(data) == "table" then
		local id = data.id
		if type(id) == "number" and not secret(id) then return id end
	end
	if tip and tip.GetItem then
		local ok, _, link = pcall(tip.GetItem, tip)
		if ok and type(link) == "string" and not secret(link) then
			local id = tonumber(link:match("item:(%d+)"))
			if id then return id end
		end
	end
	if type(data) == "table" and type(data.hyperlink) == "string" and not secret(data.hyperlink) then
		return tonumber(data.hyperlink:match("item:(%d+)"))
	end
end

local function already(tip)
	local name = tip.GetName and tip:GetName()
	local n = tip.NumLines and tip:NumLines()
	if secret(name) or type(name) ~= "string" or secret(n) or type(n) ~= "number" then return false end
	for i = 1, n do
		local fs = _G[name .. "TextLeft" .. i]
		local text = fs and fs.GetText and fs:GetText()
		if not secret(text) and type(text) == "string" and text:match("^Bags %d") then return true end
	end
	return false
end

local function bankFor(name, row)
	if bankOpen() and name == character() then
		local bank = {}
		for _, bag in ipairs(bankBags()) do addBag(bag, bank) end
		return bank, true
	end
	if type(row) == "table" and row.bankSeen and type(row.bank) == "table" then return row.bank, true end
	local mem = bankMemory(name)
	if mem then return mem, true end
	return nil, false
end

local function altLine(row, id)
	if type(row) ~= "table" then return end
	local who = row.name
	if secret(who) or type(who) ~= "string" or who == "" then return end
	local bp = have(row.backpack, id)
	local bags = have(row.bags, id)
	local wornN = have(row.worn, id)
	local bank, known = bankFor(who, row)
	local bankN = known and have(bank, id) or 0
	local carried = bp + bags
	if carried + wornN + bankN <= 0 then return end
	local text = who .. ": bags " .. carried
	if wornN > 0 then text = text .. ", worn " .. wornN end
	if known and bankN > 0 then text = text .. ", bank " .. bankN end
	return { name = who, text = text, total = bp + bags + wornN + bankN }
end

local function addCounts(tip, data)
	if not (ns.F and ns.F("itemCounts")) then return end
	if tip ~= GameTooltip and tip ~= ItemRefTooltip then return end
	if tip.zydeCounting then return end
	local id = itemID(tip, data)
	if not id or already(tip) then return end
	tip.zydeCounting = true
	local me = character()
	local bp, bags, worn = ensureLive()
	local text = "Bags " .. (have(bp, id) + have(bags, id))
	local wornN = have(worn, id)
	if wornN > 0 then text = text .. "    Worn " .. wornN end
	local row = me and ZydeForeverDB and ZydeForeverDB.itemCounts and ZydeForeverDB.itemCounts[me]
	local bank, known = bankFor(me, row)
	if known then text = text .. "    Bank " .. have(bank, id) end
	tip:AddLine(text, 1, 0.82, 0.2, true)
	local lines, seen = {}, {}
	local all = ZydeForeverDB and ZydeForeverDB.itemCounts
	if type(all) == "table" then
		for key, rec in pairs(all) do
			if key ~= me and type(rec) == "table" then
				seen[key] = true
				local line = altLine(rec, id)
				if line then lines[#lines + 1] = line end
			end
		end
	end
	local banks = ZydeForeverDB and ZydeForeverDB.bankSeen
	if type(banks) == "table" then
		for key, rec in pairs(banks) do
			if key ~= me and not seen[key] and type(rec) == "table" then
				local n = have(bankMemory(key), id)
				if n > 0 then
					lines[#lines + 1] = { name = key, text = key .. ": bank " .. n, total = n }
				end
			end
		end
	end
	table.sort(lines, function(a, b)
		if a.total ~= b.total then return a.total > b.total end
		return a.name < b.name
	end)
	local shown = #lines
	if shown > 12 then shown = 12 end
	for i = 1, shown do
		tip:AddLine(lines[i].text, 0.75, 0.85, 1, true)
	end
	if #lines > shown then
		tip:AddLine("+" .. (#lines - shown) .. " more characters", 0.55, 0.55, 0.55)
	end
	tip:Show()
	tip.zydeCounting = false
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		pcall(addCounts, tooltip, data)
	end)
else
	for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
		if tt and tt.HookScript then
			pcall(tt.HookScript, tt, "OnTooltipSetItem", function(self) pcall(addCounts, self) end)
		end
	end
end
