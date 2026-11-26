-- Zyde_Forever: all your bags in one window, sorted into sections.
--   Opens instead of the game's bags (B, the bag buttons, vendors, mail...).
--   General: Perma (never delete), Quest, Junk, Keys, Other.
--   Gear: weapons, armor, bags, ammo. Consumables: food & drink, potions,
--   bandages, scrolls, other. Profession: trade goods by type, reagents, recipes.
--   Items are real bag slots: right-click uses or sells, drag moves, shift-click
--   links. The title counts free slots (reagent bag, quiver... apart, in gray).
--   Alt-click an item to put it in Perma (or take it out). Click a heading to fold it.
--   The title shows your free slots (orange at 5 or fewer, red when full).
--   Buttons: Restack (joins part stacks in the
--   real bags), Sell junk (at a vendor; junk also sells by itself there, see
--   "Sell junk at vendors" in /zyde).
--   At a banker the bank gets the same sorted window, where the game's bank
--   window was ("Game bank" brings that back, to buy slots).
--   Away from a banker, Bank (or /zyde bank) opens that window from the last
--   visit. You can look, not move things. Your bags stay open.
-- Off while Baganator is loaded.
--
-- The item buttons are the game's own bag slot buttons. Their bag is their
-- parent's ID, so each bag has a holder frame with that ID. The layout only
-- changes out of combat; in a fight the slots just repaint.

local ADDON, ns = ...

local function on() return ns.F("bagWindow") end
local function db() ZydeForeverDB = ZydeForeverDB or {} return ZydeForeverDB end

local S, GAP, COLS, PAD = 37, 4, 10, 10
local LABEL_H, HEAD_H, GROUP_GAP = 14, 22, 12
local INNER_W = COLS * (S + GAP) - GAP
local P = "|cff66ccffZyde_Forever|r: "

-- Your bags: the backpack, the four bags, Forever's reagent (profession) bag,
-- and the keyring. On this client the keyring is bag -1 (the old bank number).
-- The bank itself is the bags after yours, read while you're at a banker.
local LAST_BAG = NUM_BAG_SLOTS or 4
local REAGENT_BAG = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or REAGENTBAG_CONTAINER or 5
local KEYRING = (Enum and Enum.BagIndex and Enum.BagIndex.Keyring) or KEYRING_CONTAINER
local BANK_NAMED = Enum and Enum.BagIndex and Enum.BagIndex.Bank
local BANK_MAIN
if type(BANK_NAMED) == "number" and BANK_NAMED ~= KEYRING then
	BANK_MAIN = BANK_NAMED
elseif type(BANK_CONTAINER) == "number" and BANK_CONTAINER ~= KEYRING then
	BANK_MAIN = BANK_CONTAINER
elseif KEYRING == nil then
	BANK_MAIN = -1
end
local toInv = (C_Container and C_Container.ContainerIDToInventoryID) or ContainerIDToInventoryID
local function invSlot(bag)
	if not toInv then return nil end
	local ok, slot = pcall(toInv, bag)
	return ok and type(slot) == "number" and slot or nil
end
local HAS_REAGENT = REAGENT_BAG > LAST_BAG and invSlot(REAGENT_BAG) ~= nil
local function numSlots(bag) return ns.safe(C_Container.GetContainerNumSlots, bag) or 0 end
local function keyringId()
	if type(KEYRING) == "number" then return KEYRING end
	-- A classic keyring, when the client still has one and didn't name it.
	if BANK_MAIN ~= -2 and numSlots(-2) > 0 then return -2 end
end
local function isKeyring(id) return type(id) == "number" and id == keyringId() end
local function isEquippedBag(id)
	return type(id) == "number" and ((id >= 0 and id <= LAST_BAG) or (HAS_REAGENT and id == REAGENT_BAG))
end
local function myBags()
	local list = {}
	for bag = 0, LAST_BAG do list[#list + 1] = bag end
	if HAS_REAGENT then list[#list + 1] = REAGENT_BAG end
	local key = keyringId()
	if key and not isEquippedBag(key) and key ~= REAGENT_BAG then list[#list + 1] = key end
	return list
end
local function isMine(id) return isEquippedBag(id) or isKeyring(id) end
-- The bank, while you're at a banker: its main slots (when it has its own bag)
-- and its bags or tabs, which have the numbers after yours. The keyring is
-- never one of them. Only bags that currently have slots count.
local function bankBags()
	local list = {}
	local key = keyringId()
	if BANK_MAIN and BANK_MAIN ~= key and numSlots(BANK_MAIN) > 0 then list[#list + 1] = BANK_MAIN end
	for bag = LAST_BAG + 1, LAST_BAG + 14 do
		if bag ~= key and not (HAS_REAGENT and bag == REAGENT_BAG) and numSlots(bag) > 0 then
			list[#list + 1] = bag
		end
	end
	return list
end

---------------------------------------------------------------------------
-- Perma: things you never want to delete.
---------------------------------------------------------------------------
local DEFAULT_PERMA = {
	[6948] = true,  -- Hearthstone
	[9149] = true,  -- Philosopher's Stone
	[2901] = true,  -- Mining Pick
	[7005] = true,  -- Skinning Knife
	[5956] = true,  -- Blacksmith Hammer
	[6256] = true,  -- Fishing Pole
	[6219] = true,  -- Arclight Spanner
	[4471] = true,  -- Flint and Tinder
	[5060] = true,  -- Thieves' Tools
	[6218] = true, [6339] = true, [11130] = true, [11145] = true, [16207] = true, -- Runed rods
}
local function permaDB() db().bagPerma = db().bagPerma or {} return db().bagPerma end
function ns.IsPerma(id)
	if not id then return false end
	local v = permaDB()[id]
	if v ~= nil then return v end
	return DEFAULT_PERMA[id] or false
end
local function togglePerma(id)
	permaDB()[id] = not ns.IsPerma(id)
end

---------------------------------------------------------------------------
-- Which section and group an item goes in.
---------------------------------------------------------------------------
-- Upgrades comes first: gear that beats what you wear (the green arrow).
local SECTIONS = { "Upgrades", "General", "Gear", "Consumables", "Profession" }
local ORDER = {
	Upgrades = { "Weapons", "Armor" },
	General = { "Perma", "Quest", "Junk", "Keys", "Other" },
	Gear = { "Weapons", "Armor", "Bags", "Ammo" },
	Consumables = { "Food & drink", "Potions", "Bandages", "Scrolls", "Other" },
	Profession = {}, -- the game's trade goods types, then Reagents, Recipes
}

local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local getSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell

local function nameOf(info)
	local link = info.hyperlink
	return type(link) == "string" and link:match("%[(.-)%]") or ""
end

local function categorize(info)
	local id = info.itemID
	if ns.IsPerma(id) then return "General", "Perma" end
	local _, _, subType, equipLoc, _, classID, subID = ns.safe(getInstant, id)
	if classID == 12 then return "General", "Quest" end
	local q = C_Container.GetContainerItemQuestInfo and ns.safe(C_Container.GetContainerItemQuestInfo, info.bag, info.slot)
	if type(q) == "table" and (q.isQuestItem or q.questID) then return "General", "Quest" end
	if info.quality == 0 then return "General", "Junk" end
	if classID == 13 then return "General", "Keys" end
	if classID == 2 then return "Gear", "Weapons" end
	if classID == 4 and equipLoc and equipLoc ~= "" then return "Gear", "Armor" end
	if classID == 1 or classID == 11 then return "Gear", "Bags" end
	if classID == 6 then return "Gear", "Ammo" end
	if classID == 0 then
		local spell = ns.safe(getSpell, id)
		local s = type(spell) == "string" and not ns.isSecret(spell) and spell:lower() or ""
		local sub = type(subType) == "string" and subType:lower() or ""
		local name = nameOf(info):lower()
		if s:find("food", 1, true) or s:find("drink", 1, true) or s:find("refresh", 1, true) or sub:find("food", 1, true) then
			return "Consumables", "Food & drink"
		end
		if subID == 1 or subID == 2 or subID == 3 or sub:find("potion", 1, true) or sub:find("elixir", 1, true) or sub:find("flask", 1, true) then
			return "Consumables", "Potions"
		end
		if subID == 7 or sub:find("bandage", 1, true) or name:find("bandage", 1, true) then return "Consumables", "Bandages" end
		if sub:find("scroll", 1, true) or name:find("^scroll of") then return "Consumables", "Scrolls" end
		return "Consumables", "Other"
	end
	if classID == 9 then return "Profession", "Recipes" end
	if classID == 5 then return "Profession", "Reagents" end
	if classID == 7 then
		local g = type(subType) == "string" and subType ~= "" and subType or "Trade goods"
		return "Profession", g
	end
	return "General", "Other"
end

-- The blue "new item" glow. The slot buttons never got told, so they showed
-- it after every reload. Here: nothing is new right after login or a reload
-- (see the login clear below); something you pick up later glows until you
-- hover it or close the bags, like the game's own bags.
local NEW_ATLAS = { [2] = "bags-glow-green", [3] = "bags-glow-blue", [4] = "bags-glow-purple", [5] = "bags-glow-orange" }
local function setNew(b, isNew, quality)
	if b.BattlepayItemTexture then b.BattlepayItemTexture:Hide() end
	local tex = b.NewItemTexture
	if tex then
		if isNew then
			pcall(tex.SetAtlas, tex, NEW_ATLAS[quality] or "bags-glow-white")
			tex:Show()
		else
			tex:Hide()
		end
	end
	for _, anim in ipairs({ b.flashAnim, b.newitemglowAnim }) do
		if anim then
			if isNew then
				if not anim:IsPlaying() then anim:Play() end
			elseif anim:IsPlaying() then
				anim:Stop()
			end
		end
	end
end

local function isNewItem(bag, slot)
	if not (C_NewItems and C_NewItems.IsNewItem) then return false end
	return ns.safe(C_NewItems.IsNewItem, bag, slot) == true
end

-- A yellow ! on an item that starts a quest you haven't taken yet: click it.
-- Our own texture, so the slot button's own quest marks stay out of the way.
local QUEST_BANG = "Interface\\ContainerFrame\\UI-Icon-QuestBang"
local function setBang(b, show)
	local own = b.IconQuestTexture or _G[(b:GetName() or "") .. "IconQuestTexture"]
	if own then own:Hide() end
	if show and not b.bang then
		b.bang = b:CreateTexture(nil, "OVERLAY", nil, 6)
		b.bang:SetAllPoints()
		b.bang:SetTexture(QUEST_BANG)
	end
	if b.bang then b.bang:SetShown(show and true or false) end
end

local function startsQuest(bag, slot)
	local q = C_Container.GetContainerItemQuestInfo and ns.safe(C_Container.GetContainerItemQuestInfo, bag, slot)
	if type(q) ~= "table" then return false end
	local id = q.questID
	if not id or ns.isSecret(id) or q.isActive then return false end
	-- Done already (some starters stay in your bags): no !.
	local done = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and ns.safe(C_QuestLog.IsQuestFlaggedCompleted, id)
	return done ~= true
end

---------------------------------------------------------------------------
-- Small marks on an item: red tint (can't use it), green arrow (upgrade),
-- gold coin (junk that sells), BoE (could go on the auction house), a
-- red-orange-yellow outline and number (the scrap list's picks, bags full),
-- Open / Lock (a clam or a lockbox), and the required level on gear, in the
-- top right. What the tooltip says is read once per item in a slot and kept
-- until the bags, your level, skills or gear change.
---------------------------------------------------------------------------
local scanCache = {}
local getInfoAny = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local LOCKED_TEXT = LOCKED or "Locked"

local function scan(bag, slot, info)
	local key = bag .. ":" .. slot
	local c = scanCache[key]
	if c and c.link == info.hyperlink then return c end
	c = { link = info.hyperlink }
	local data = C_TooltipInfo and C_TooltipInfo.GetBagItem and ns.safe(C_TooltipInfo.GetBagItem, bag, slot)
	for _, line in ipairs(type(data) == "table" and data.lines or {}) do
		for _, side in ipairs({ { line.leftText, line.leftColor }, { line.rightText, line.rightColor } }) do
			local text, col = side[1], side[2]
			if type(text) == "string" and not ns.isSecret(text) then
				if text == LOCKED_TEXT then c.locked = true end
				if col and type(col.r) == "number" and not ns.isSecret(col.r)
					and col.r > 0.95 and col.g < 0.2 and col.b < 0.2 then
					c.red = true
				end
			end
		end
	end
	local name, _, _, _, reqLevel, _, _, _, equipLoc, _, sellPrice, classID, _, bindType = ns.safe(getInfoAny, info.hyperlink or info.itemID)
	if type(name) ~= "string" or ns.isSecret(name) then return c end -- not loaded yet: ask again next paint
	c.sells = not ns.isSecret(sellPrice) and type(sellPrice) == "number" and sellPrice > 0 and not info.hasNoValue
	local loc = (not ns.isSecret(equipLoc) and type(equipLoc) == "string") and equipLoc or ""
	c.boe = not ns.isSecret(bindType) and bindType == 2 and loc ~= "" -- still unbound: checked at paint
	-- Weapons and armor. A required level of 1 is every starter piece, so it stays off.
	local req = (not ns.isSecret(reqLevel) and type(reqLevel) == "number") and reqLevel or nil
	local cls = (not ns.isSecret(classID) and type(classID) == "number") and classID or nil
	if req and req > 1 and (cls == 2 or (cls == 4 and loc ~= "")) then c.req = req end
	c.upgrade = ns.BagItemUpgrade and ns.BagItemUpgrade(bag, slot, info.hyperlink) or nil
	scanCache[key] = c
	return c
end

local function markFont(fs, size)
	if not fs:SetFont("Fonts\\ARIALN.TTF", size, "OUTLINE") then fs:SetFontObject("GameFontNormalSmall") end
end

local function marks(b)
	if b.zMarks then return b.zMarks end
	local m = {}
	m.arrow = b:CreateTexture(nil, "OVERLAY", nil, 5)
	m.arrow:SetSize(14, 14)
	m.arrow:SetPoint("TOPLEFT", 1, -1)
	m.arrow:SetTexture("Interface\\Buttons\\UI-MicroStream-Green")
	m.coin = b:CreateTexture(nil, "OVERLAY", nil, 5)
	m.coin:SetSize(12, 12)
	m.coin:SetPoint("TOPLEFT", 2, -2)
	m.coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
	-- The vendor advice says "Auction it" (with AHledger): the auctioneer.
	m.ah = b:CreateTexture(nil, "OVERLAY", nil, 5)
	m.ah:SetSize(15, 15)
	m.ah:SetPoint("TOPLEFT", 1, -1)
	m.ah:SetTexture("Interface\\Minimap\\Tracking\\Auctioneer")
	m.boe = b:CreateFontString(nil, "OVERLAY")
	markFont(m.boe, 10)
	m.boe:SetPoint("BOTTOMLEFT", 2, 2)
	m.boe:SetText("BoE")
	m.boe:SetTextColor(0.4, 1, 0.5)
	m.tag = b:CreateFontString(nil, "OVERLAY")
	markFont(m.tag, 10)
	m.tag:SetPoint("TOPRIGHT", -1, -2)
	m.req = b:CreateFontString(nil, "OVERLAY")
	markFont(m.req, 9)
	m.req:SetPoint("TOPRIGHT", -1, -1)
	m.req:SetJustifyH("RIGHT")
	m.scrapNum = b:CreateFontString(nil, "OVERLAY")
	markFont(m.scrapNum, 14)
	m.scrapNum:SetPoint("TOPRIGHT", -2, -1)
	m.scrapEdges = ns.newEdges(b, "OVERLAY", 7)
	ns.placeEdges(m.scrapEdges, b, 0, 2)
	b.zMarks = m
	return m
end

local function iconOf(b)
	return b.icon or b.Icon or _G[(b:GetName() or "") .. "IconTexture"]
end

local function setMarks(b, info)
	local m = marks(b)
	local icon = iconOf(b)
	if not info then
		for _, k in ipairs({ "arrow", "coin", "ah", "boe", "tag", "scrapNum", "req" }) do m[k]:Hide() end
		for _, t in ipairs(m.scrapEdges) do t:Hide() end
		if icon then icon:SetVertexColor(1, 1, 1) end
		return
	end
	local bag, slot = b:GetParent():GetID(), b:GetID()
	local c = scan(bag, slot, info)
	-- Red: something in the tooltip says you can't use it (level, class, skill, already known).
	if icon then
		if c.red and not c.locked then icon:SetVertexColor(1, 0.3, 0.3) else icon:SetVertexColor(1, 1, 1) end
	end
	m.arrow:SetShown(c.upgrade ~= nil and not c.red)
	-- Top left, one of: upgrade arrow, auctioneer (sell it on the AH), coin
	-- (junk that sells, or the vendor advice says "Vendor it").
	local verdict = ns.Vendor and ns.Vendor.Verdict and ns.Vendor.Verdict(bag, slot)
	m.ah:SetShown(verdict == "auction" and not m.arrow:IsShown())
	m.coin:SetShown(((info.quality == 0 and c.sells) or verdict == "vendor") and not m.arrow:IsShown() and not m.ah:IsShown())
	m.boe:SetShown(c.boe and not info.isBound and true or false)
	-- The scrap list's 1-3 (any stack of a merged tile counts).
	local rank
	if ns.Scrap and ns.Scrap.Rank then
		for _, s in ipairs(b.slots or { { bag = bag, slot = slot } }) do
			local r = ns.Scrap.Rank(s.bag, s.slot)
			if r and (not rank or r < rank) then rank = r end
		end
	end
	local col = rank and ns.Scrap.COLORS and ns.Scrap.COLORS[rank]
	for _, t in ipairs(m.scrapEdges) do
		if col then t:SetColorTexture(col[1], col[2], col[3], 1) t:Show() else t:Hide() end
	end
	if col then
		m.scrapNum:SetText(rank)
		m.scrapNum:SetTextColor(col[1], col[2], col[3])
		m.scrapNum:Show()
		m.tag:Hide()
		m.req:Hide()
		return
	end
	m.scrapNum:Hide()
	-- A clam or bag of loot (right-click to open), or a lockbox still locked.
	if c.locked then
		m.tag:SetText("Lock")
		m.tag:SetTextColor(1, 0.6, 0.2)
		m.tag:Show()
	elseif info.hasLoot then
		m.tag:SetText("Open")
		m.tag:SetTextColor(0.4, 1, 0.4)
		m.tag:Show()
	else
		m.tag:Hide()
	end
	if c.req and not m.tag:IsShown() then
		local mine = UnitLevel("player")
		local low = not ns.isSecret(mine) and type(mine) == "number" and mine < c.req
		m.req:SetText(c.req)
		if low then m.req:SetTextColor(1, 0.25, 0.2) else m.req:SetTextColor(1, 1, 1) end
		m.req:Show()
	else
		m.req:Hide()
	end
end

---------------------------------------------------------------------------
-- Stacks of the same item become one tile showing the total (14 stacks of
-- bullets: one tile of 2770). The tile is the smallest stack's slot, so
-- using or dragging it takes from the stack that's nearly gone first.
-- Things that don't stack (gear) stay one tile each.
---------------------------------------------------------------------------
local maxStack = (C_Item and C_Item.GetItemMaxStackSizeByID) or nil
local function stackSize(id)
	local n = maxStack and ns.safe(maxStack, id)
	if type(n) == "number" and not ns.isSecret(n) then return n end
end
local function stacks(info)
	local n = stackSize(info.itemID)
	if n then return n > 1 end
	return (info.stackCount or 1) > 1
end

-- How many slots Restack would free: for each item, the stacks it has now
-- minus the fewest it could fit in (two stacks of 12 linen: 1 slot).
-- tally: itemID -> { stacks, total, max }, filled by gather's single pass.
local function restackSavings(tally)
	local saved = 0
	for _, e in pairs(tally) do
		saved = saved + math.max(0, e.stacks - math.ceil(e.total / e.max))
	end
	return saved
end

local function merge(list)
	local out, byID = {}, {}
	for _, e in ipairs(list) do
		local id = e.info and e.info.itemID
		local first = id and stacks(e.info) and byID[id]
		if first then
			first.slots[#first.slots + 1] = { bag = e.bag, slot = e.slot }
			local n = e.info.stackCount or 1
			if n < first.smallest then
				first.smallest, first.bag, first.slot, first.info = n, e.bag, e.slot, e.info
			end
		else
			e.slots = { { bag = e.bag, slot = e.slot } }
			e.smallest = e.info and e.info.stackCount or 1
			if id and stacks(e.info) then byID[id] = e end
			out[#out + 1] = e
		end
	end
	return out
end

-- Every filled slot of these bags, sorted into section -> group -> list;
-- plus the empty tiles. Also returns the free slots in ordinary bags.
local function gather(bags)
	local out = {}
	for _, sec in ipairs(SECTIONS) do out[sec] = {} end
	local function add(sec, group, entry)
		out[sec][group] = out[sec][group] or {}
		table.insert(out[sec][group], entry)
	end
	local tally = {}
	for _, bag in ipairs(bags) do
		for slot = 1, numSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID then
				info.bag, info.slot = bag, slot
				local sec, group = categorize(info)
				-- An upgrade you can wear now goes to the top. Same read as the
				-- green arrow, kept per item until your level, skills or gear change.
				if sec == "Gear" and (group == "Weapons" or group == "Armor") then
					local c = scan(bag, slot, info)
					if c.upgrade ~= nil and not c.red then sec = "Upgrades" end
				end
				add(sec, group, { bag = bag, slot = slot, info = info, name = nameOf(info) })
				-- (for Restack's count, in the same pass)
				local max = stackSize(info.itemID)
				if max and max > 1 then
					local t = tally[info.itemID]
					if not t then t = { stacks = 0, total = 0, max = max } tally[info.itemID] = t end
					t.stacks = t.stacks + 1
					t.total = t.total + (info.stackCount or 1)
				end
			end
		end
	end
	-- Free slots: ordinary bags for the title, and the bags that only take one
	-- kind of thing (reagent bag, quiver, ammo pouch, soul bag) counted apart.
	local ordinaryFree, extra = 0, {}
	for _, bag in ipairs(bags) do
		-- Empty key slots only hold keys. They are not free bag space.
		if not isKeyring(bag) then
			local free, fam = C_Container.GetContainerNumFreeSlots(bag)
			free, fam = tonumber(free) or 0, tonumber(fam) or 0
			local kind
			if bag == REAGENT_BAG and HAS_REAGENT then kind = "reagent"
			elseif fam == 0 then kind = nil
			elseif bit and bit.band and bit.band(fam, 3) ~= 0 then kind = "ammo"
			elseif bit and bit.band and bit.band(fam, 4) ~= 0 then kind = "soul"
			else kind = "special" end
			if kind then
				if numSlots(bag) > 0 then extra[kind] = (extra[kind] or 0) + free end
			else
				ordinaryFree = ordinaryFree + free
			end
		end
	end
	-- Same items next to each other, best quality first.
	for _, groups in pairs(out) do
		for g, list in pairs(groups) do
			if g ~= "Empty" then
				table.sort(list, function(a, b)
					local qa, qb = a.info.quality or 0, b.info.quality or 0
					if qa ~= qb then return qa > qb end
					if a.name ~= b.name then return a.name < b.name end
					if a.bag ~= b.bag then return a.bag < b.bag end
					return a.slot < b.slot
				end)
				groups[g] = merge(list)
			end
		end
	end
	return out, ordinaryFree, extra, restackSavings(tally)
end

local function groupOrder(sec, groups)
	local list, seen = {}, {}
	for _, g in ipairs(ORDER[sec]) do
		if groups[g] then list[#list + 1] = g seen[g] = true end
	end
	local rest = {}
	for g in pairs(groups) do
		if not seen[g] and g ~= "Reagents" and g ~= "Recipes" then rest[#rest + 1] = g end
	end
	table.sort(rest)
	for _, g in ipairs(rest) do list[#list + 1] = g end
	if sec == "Profession" then
		if groups.Reagents then list[#list + 1] = "Reagents" end
		if groups.Recipes then list[#list + 1] = "Recipes" end
	end
	return list
end

-- Free slots: white, orange at 5 or fewer, red when full.
local function freeColor(n)
	if n <= 0 then return 1, 0.25, 0.2 end
	if n <= 5 then return 1, 0.6, 0.15 end
	return 0.85, 0.85, 0.85
end

---------------------------------------------------------------------------
-- A window of sorted bags. Two of them: your bags, and the bank.
---------------------------------------------------------------------------
local View = {}
View.__index = View
local views = {}

local function collapsed() db().bagCollapsed = db().bagCollapsed or {} return db().bagCollapsed end

function View:Holder(bag)
	if self.holders[bag] then return self.holders[bag] end
	local h = CreateFrame("Frame", nil, self.win)
	h:SetID(bag)
	h:SetAllPoints()
	self.holders[bag] = h
	return h
end

local buttonCount = 0
function View:Button(i)
	if self.pool[i] then return self.pool[i] end
	buttonCount = buttonCount + 1
	local name = "ZydeForeverBagItem" .. buttonCount
	local parent = self:Holder(self.bags()[1] or 0)
	local ok, b = pcall(CreateFrame, "ItemButton", name, parent, "ContainerFrameItemButtonTemplate")
	if not ok or not b then b = CreateFrame("Button", name, parent, "ContainerFrameItemButtonTemplate") end
	b:SetSize(S, S)
	b.cd = b.Cooldown or _G[name .. "Cooldown"]
	b.countText = b.Count or _G[name .. "Count"]
	local view = self
	b:HookScript("OnClick", function(btn, mouse)
		if btn.empty or mouse ~= "LeftButton" or not IsAltKeyDown() then return end
		local info = C_Container.GetContainerItemInfo(btn:GetParent():GetID(), btn:GetID())
		if info and info.itemID then
			togglePerma(info.itemID)
			for _, v in pairs(views) do v.dirty = true end
			if not InCombatLockdown() then view:Layout() end
		end
	end)
	b:HookScript("OnEnter", function(btn)
		if btn.empty then
			GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
			GameTooltip:AddLine(btn.emptyCount .. " empty slots")
			GameTooltip:AddLine("Drop an item here to move it to a free slot.", 1, 1, 1, true)
			GameTooltip:Show()
			return
		end
		if GameTooltip:IsOwned(btn) then
			GameTooltip:AddLine("Alt-click: " .. (btn.perma and "take out of Perma" or "keep in Perma"), 0.6, 0.8, 1)
			GameTooltip:Show()
		end
	end)
	self.pool[i] = b
	return b
end

function View:Label(i)
	if self.labels[i] then return self.labels[i] end
	local t = self.win.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	t:SetJustifyH("LEFT")
	t:SetWordWrap(false)
	t:SetTextColor(0.85, 0.85, 0.85)
	self.labels[i] = t
	return t
end

function View:Head(i)
	if self.heads[i] then return self.heads[i] end
	local h = CreateFrame("Button", nil, self.win.content)
	h:SetSize(INNER_W, HEAD_H - 4)
	h.icon = h:CreateTexture(nil, "ARTWORK")
	h.icon:SetSize(14, 14)
	h.icon:SetPoint("LEFT", 0, 0)
	h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	h.text:SetPoint("LEFT", h.icon, "RIGHT", 4, 0)
	h.line = h:CreateTexture(nil, "ARTWORK")
	h.line:SetColorTexture(1, 0.82, 0, 0.25)
	h.line:SetHeight(1)
	h.line:SetPoint("LEFT", h.text, "RIGHT", 8, 0)
	h.line:SetPoint("RIGHT")
	local view = self
	h:SetScript("OnClick", function(btn)
		if InCombatLockdown() then return end
		collapsed()[btn.section] = not collapsed()[btn.section] or nil
		for _, v in pairs(views) do v.dirty = true end
		view:Layout()
		if ns.RefreshBankMemory then ns.RefreshBankMemory() end
	end)
	self.heads[i] = h
	return h
end

function View:Paint(b)
	if b.empty then
		setNew(b, false)
		setBang(b, false)
		setMarks(b, nil)
		SetItemButtonTexture(b, b.emptyTex)
		SetItemButtonCount(b, b.emptyCount)
		SetItemButtonDesaturated(b, false)
		if SetItemButtonQuality then pcall(SetItemButtonQuality, b, nil) end
		if b.cd then b.cd:Hide() end
		-- Running out of room: the count goes orange, then red.
		if b.countText then
			if b.emptyOrdinary then b.countText:SetTextColor(freeColor(b.emptyCount))
			else b.countText:SetTextColor(1, 1, 1) end
		end
		b:SetAlpha(1)
		return
	end
	if b.countText then b.countText:SetTextColor(1, 1, 1) end
	local bag, slot = b:GetParent():GetID(), b:GetID()
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if not info then
		setNew(b, false)
		setBang(b, false)
		setMarks(b, nil)
		SetItemButtonTexture(b, nil)
		SetItemButtonCount(b, 0)
		if SetItemButtonQuality then pcall(SetItemButtonQuality, b, nil) end
		if b.cd then b.cd:Hide() end
		return
	end
	SetItemButtonTexture(b, info.iconFileID)
	-- A merged tile counts every stack of the item, read fresh (stacks change in a fight too).
	local total = info.stackCount or 1
	if b.slots and #b.slots > 1 then
		total = 0
		for _, s in ipairs(b.slots) do
			local other = C_Container.GetContainerItemInfo(s.bag, s.slot)
			if other and other.itemID == info.itemID then total = total + (other.stackCount or 1) end
		end
	end
	SetItemButtonCount(b, total)
	SetItemButtonDesaturated(b, info.isLocked)
	if SetItemButtonQuality then pcall(SetItemButtonQuality, b, info.quality, info.hyperlink) end
	setNew(b, isNewItem(bag, slot), info.quality)
	setBang(b, startsQuest(bag, slot))
	setMarks(b, info)
	if b.cd and C_Container.GetContainerItemCooldown then
		local start, dur, enable = C_Container.GetContainerItemCooldown(bag, slot)
		if CooldownFrame_Set then pcall(CooldownFrame_Set, b.cd, start, dur, enable) end
	end
	local text = self.win.search and self.win.search:GetText() or ""
	local lit = text == "" or nameOf(info):lower():find(text:lower(), 1, true) ~= nil
	-- Hovering a bag in the bag row lights up only what's in that bag.
	if self.hoverBag then
		local inBag = false
		for _, s in ipairs(b.slots or { { bag = bag } }) do
			if s.bag == self.hoverBag then inBag = true break end
		end
		if not inBag then lit = false end
	end
	b:SetAlpha(lit and 1 or 0.25)
end

function View:Repaint()
	for i = 1, self.used do self:Paint(self.pool[i]) end
end

function View:SetTitle()
	local r, g, bl = freeColor(self.free or 0)
	local free = (self.free or 0) <= 0 and "full" or ((self.free or 0) .. " free")
	-- "30 free  ·  12 reagent": special bags after the ordinary count, in gray.
	local more = {}
	for _, kind in ipairs({ "reagent", "ammo", "soul", "special" }) do
		local n = self.extraFree and self.extraFree[kind]
		-- (a full quiver or ammo pouch is normal: only bags with room are listed)
		if n and n > 0 then more[#more + 1] = n .. " " .. kind end
	end
	local tail = #more > 0 and ("  |cff888888· " .. table.concat(more, " · ") .. "|r") or ""
	self.win.title:SetText(self.titleText .. string.format("  |cff%02x%02x%02x%s|r", r * 255, g * 255, bl * 255, free) .. tail)
end

function View:ContentTop() return 34 + (self.bagRowShown and self.bagRowShown() and (S + 8) or 0) end

function View:Layout()
	if InCombatLockdown() then self.dirty = true return end
	self.dirty = false
	local data, free, extra, saved = gather(self.bags())
	if self.omitKeys and self.omitKeys() and data.General then data.General.Keys = nil end
	self.free, self.extraFree = free, extra
	self:SetTitle()
	-- Restack only shows when it would free something: "Restack +3".
	local rb = self.win.restackBtn
	if rb then
		rb:SetText("Restack +" .. saved)
		rb:SetShown(saved > 0)
		self.win.Flow()
	end
	local used, labelUsed, headUsed = 0, 0, 0
	local y = 0
	local content = self.win.content
	for _, sec in ipairs(SECTIONS) do
		local groups = data[sec]
		local order = groupOrder(sec, groups)
		if #order > 0 then
			headUsed = headUsed + 1
			local h = self:Head(headUsed)
			h.section = sec
			local folded = collapsed()[sec]
			local n = 0
			for _, g in ipairs(order) do n = n + #groups[g] end
			h.text:SetText(sec .. (folded and ("  |cff888888(" .. n .. ")|r") or ""))
			h.icon:SetTexture(folded and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
			h:ClearAllPoints()
			h:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
			h:Show()
			y = y + HEAD_H
			if not folded then
				local x, rowH = 0, 0
				for _, g in ipairs(order) do
					local list = groups[g]
					local cols = math.min(#list, COLS)
					local w = cols * (S + GAP) - GAP
					if x > 0 and x + w > INNER_W then
						x = 0
						y = y + rowH + 6
						rowH = 0
					end
					labelUsed = labelUsed + 1
					local l = self:Label(labelUsed)
					l:ClearAllPoints()
					l:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
					l:SetWidth(math.max(w, S))
					l:SetText(g)
					l:Show()
					for i, e in ipairs(list) do
						used = used + 1
						local b = self:Button(used)
						b:SetParent(self:Holder(e.bag))
						b:SetID(e.slot)
						b.empty = e.empty
						b.emptyTex, b.emptyCount, b.emptyOrdinary = e.tex, e.count, e.ordinary
						b.slots = e.slots
						b.perma = not e.empty and ns.IsPerma(e.info and e.info.itemID)
						local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
						b:ClearAllPoints()
						b:SetPoint("TOPLEFT", content, "TOPLEFT", x + col * (S + GAP), -(y + LABEL_H + row * (S + GAP)))
						b:Show()
						self:Paint(b)
					end
					local rows = math.ceil(#list / cols)
					rowH = math.max(rowH, LABEL_H + rows * (S + GAP) - GAP)
					x = x + w + GROUP_GAP
				end
				y = y + rowH + 10
			end
		end
	end
	self.used = used
	for i = used + 1, #self.pool do self.pool[i]:Hide() end
	for i = labelUsed + 1, #self.labels do self.labels[i]:Hide() end
	for i = headUsed + 1, #self.heads do self.heads[i]:Hide() end
	content:SetHeight(math.max(10, y))
	self.win:SetHeight(y + self:ContentTop() + 2 + 34 + PAD)
end

-- Bags changed: lay out again soon (or repaint only, in a fight).
function View:Changed()
	self.dirty = true
	if not self.win:IsShown() then return end
	if InCombatLockdown() then self:Repaint() return end
	if self.pending then return end
	self.pending = true
	-- (a short wait gathers a burst of bag, quest and item-info events into one re-sort)
	C_Timer.After(0.2, function()
		self.pending = false
		if self.win:IsShown() and self.dirty and not InCombatLockdown() then self:Layout() end
	end)
end

function View:PlaceContent()
	self.win.content:ClearAllPoints()
	self.win.content:SetPoint("TOPLEFT", PAD, -self:ContentTop())
	if self.win.bagRow then self.win.bagRow:SetShown(self.bagRowShown and self.bagRowShown() or false) end
end

function View:SavePos()
	local r, b = self.win:GetRight(), self.win:GetBottom()
	if ns.isSecret(r) or ns.isSecret(b) or type(r) ~= "number" or type(b) ~= "number" then return end
	db()[self.posKey] = { x = r, y = b }
end

function View:Place()
	local w = self.win
	w:ClearAllPoints()
	local p = db()[self.posKey]
	if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" then
		w:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", p.x, p.y)
	else
		w:SetPoint(unpack(self.defaultPoint))
	end
end

-- Your gold, for the bottom-right corner: 14g 71s 18c with the coin icons.
local function coin(n, icon) return n .. "|TInterface\\MoneyFrame\\" .. icon .. ":12:12:2:0|t" end
local function moneyText(c)
	c = c or ns.safe(GetMoney)
	if ns.isSecret(c) or type(c) ~= "number" then return "" end
	local g, sv, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = coin(g, "UI-GoldIcon") end
	if g > 0 or sv > 0 then parts[#parts + 1] = coin(sv, "UI-SilverIcon") end
	parts[#parts + 1] = coin(cp, "UI-CopperIcon")
	return table.concat(parts, "  ")
end

local function smallButton(parent, text, w, tipTitle, tipText)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(w, 20)
	b:SetText(text)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(tipTitle)
		GameTooltip:AddLine(tipText, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

local function newView(o)
	local v = setmetatable(o, View)
	v.holders, v.pool, v.heads, v.labels = {}, {}, {}, {}
	v.used, v.dirty = 0, true
	local win = CreateFrame("Frame", o.frameName, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	v.win = win
	win:SetWidth(INNER_W + PAD * 2)
	win:SetHeight(200)
	win:SetFrameStrata("MEDIUM")
	win:SetToplevel(true)
	win:SetClampedToScreen(true)
	win:EnableMouse(true)
	win:SetMovable(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", function(self) self:StartMoving() end)
	win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() v:SavePos() end)
	if win.SetBackdrop then
		win:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		win:SetBackdropColor(0.06, 0.06, 0.07, 0.95)
		win:SetBackdropBorderColor(0, 0, 0, 1)
	end
	tinsert(UISpecialFrames, o.frameName)
	win:Hide()

	win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	win.title:SetPoint("TOPLEFT", PAD, -9)
	-- Fenced to the space left of the bag-row button and the search box: a
	-- longer line ("30 free · 12 reagent") cuts off there instead of running under them.
	win.title:SetWidth(INNER_W - 140 - 6 - 24 - 40)
	win.title:SetJustifyH("LEFT")
	win.title:SetWordWrap(false)
	win.close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
	win.close:SetPoint("TOPRIGHT", 2, 2)
	win.close:SetScript("OnClick", function() win:Hide() end)

	local ok, search = pcall(CreateFrame, "EditBox", nil, win, "SearchBoxTemplate")
	if not ok or not search then search = CreateFrame("EditBox", nil, win, "InputBoxTemplate") end
	search:SetSize(140, 20)
	search:SetAutoFocus(false)
	search:SetPoint("RIGHT", win.close, "LEFT", -6, 0)
	search:HookScript("OnTextChanged", function() v:Repaint() end)
	search:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
	win.search = search

	win.content = CreateFrame("Frame", nil, win)
	win.content:SetWidth(INNER_W)
	win.content:SetHeight(10)

	win.money = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	win.money:SetPoint("BOTTOMRIGHT", -PAD, 12)
	-- Bottom-left buttons, left to right; a hidden one leaves no gap.
	win.buttons = {}
	function win.Flow()
		local x = PAD
		for _, b in ipairs(win.buttons) do
			if b:IsShown() then
				b:ClearAllPoints()
				b:SetPoint("BOTTOMLEFT", x, 8)
				x = x + b:GetWidth() + 4
			end
		end
	end
	function win.AddButton(text, w, tipTitle, tipText, onClick)
		local b = smallButton(win, text, w, tipTitle, tipText)
		b:SetScript("OnClick", onClick)
		win.buttons[#win.buttons + 1] = b
		win.Flow()
		return b
	end
	views[#views + 1] = v
	return v
end

---------------------------------------------------------------------------
-- Restack: join part stacks of the same item in the real bags (two stacks of
-- 12 linen become one of 24), one move at a time, out of combat.
---------------------------------------------------------------------------
local restacking = false
local function restack(bags)
	if restacking then return end
	if InCombatLockdown() then print(P .. "can't restack during a fight") return end
	if GetCursorInfo() then print(P .. "put down what's on the cursor first") return end
	restacking = true
	local moves, tries = 0, 0
	local function finish(msg)
		restacking = false
		print(P .. msg)
	end
	local function step()
		tries = tries + 1
		if tries > 400 then finish("restack stopped (took too long)") return end
		if InCombatLockdown() then finish("restack stopped for the fight") return end
		local byID, locked = {}, false
		for _, bag in ipairs(bags) do
			for slot = 1, numSlots(bag) do
				local info = C_Container.GetContainerItemInfo(bag, slot)
				if info and info.itemID then
					if info.isLocked then locked = true end
					local max = stackSize(info.itemID)
					local n = info.stackCount or 1
					if max and max > 1 and n < max then
						byID[info.itemID] = byID[info.itemID] or {}
						table.insert(byID[info.itemID], { bag = bag, slot = slot, n = n })
					end
				end
			end
		end
		-- The last move is still settling: wait for it.
		if locked then C_Timer.After(0.15, step) return end
		for _, list in pairs(byID) do
			if #list > 1 then
				table.sort(list, function(a, b) return a.n > b.n end)
				local dst, src = list[1], list[#list]
				ClearCursor()
				C_Container.PickupContainerItem(src.bag, src.slot)
				C_Container.PickupContainerItem(dst.bag, dst.slot)
				if GetCursorInfo() then ClearCursor() end
				moves = moves + 1
				C_Timer.After(0.2, step)
				return
			end
		end
		finish(moves > 0 and ("restacked (" .. moves .. " moves)") or "nothing to restack")
	end
	step()
end

---------------------------------------------------------------------------
-- Sell junk: grey items that sell, never Perma. By itself when a vendor
-- opens (feature "sellJunk"), or with the Sell junk button.
---------------------------------------------------------------------------
local selling = false
local function sellJunk(quiet)
	if selling or InCombatLockdown() or not (MerchantFrame and MerchantFrame:IsShown()) then return end
	local queue = {}
	for _, bag in ipairs(myBags()) do
		for slot = 1, numSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID and info.quality == 0 and not info.hasNoValue and not info.isLocked
				and not ns.IsPerma(info.itemID) then
				local price = select(11, ns.safe(getInfoAny, info.hyperlink or info.itemID))
				if type(price) == "number" and not ns.isSecret(price) and price > 0 then
					queue[#queue + 1] = { bag = bag, slot = slot, id = info.itemID, value = price * (info.stackCount or 1) }
				end
			end
		end
	end
	if #queue == 0 then
		if not quiet then print(P .. "no junk to sell") end
		return
	end
	selling = true
	local i, sold, total = 0, 0, 0
	local function step()
		i = i + 1
		local q = queue[i]
		if not q or not (MerchantFrame and MerchantFrame:IsShown()) or InCombatLockdown() then
			selling = false
			if sold > 0 then print(P .. ("sold %d junk for %s"):format(sold, moneyText(total))) end
			return
		end
		local info = C_Container.GetContainerItemInfo(q.bag, q.slot)
		if info and info.itemID == q.id and not info.isLocked then
			C_Container.UseContainerItem(q.bag, q.slot)
			sold, total = sold + 1, total + q.value
		end
		C_Timer.After(0.15, step)
	end
	step()
end

---------------------------------------------------------------------------
-- Your bags
---------------------------------------------------------------------------
local bagsView, bankView

local function bagRowShown() return db().bagSlotsShown and true or false end
-- Keys start visible. The key button by the search box hides the keyring
-- and any other keys in this window.
local function keysShown()
	local v = db().bagKeysShown
	if v == nil then return true end
	return v and true or false
end
local function shownBags()
	if keysShown() then return myBags() end
	local list = {}
	for _, bag in ipairs(myBags()) do
		if not isKeyring(bag) then list[#list + 1] = bag end
	end
	return list
end

local EMPTY_BAG_TEX = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"
local function paintBagSlots()
	local win = bagsView and bagsView.win
	if not (win and win.bagSlots) then return end
	for _, b in ipairs(win.bagSlots) do
		local inv = invSlot(b.bag)
		local tex = inv and GetInventoryItemTexture("player", inv)
		b.icon:SetTexture(tex or EMPTY_BAG_TEX)
		local n = numSlots(b.bag)
		b.count:SetText(n > 0 and n or "")
	end
end

-- The bag row: your bags, to swap one for a bigger one. Click or drag a bag
-- to pick it up (it has to be empty), drop a bag on a slot to put it on.
local function bagSlot(v, bag, x)
	local b = CreateFrame("Button", nil, v.win.bagRow)
	b:SetSize(S, S)
	b:SetPoint("LEFT", x, 0)
	b:RegisterForClicks("LeftButtonUp")
	b:RegisterForDrag("LeftButton")
	b.bag = bag
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetPoint("TOPLEFT", -1, 1)
	b.bg:SetPoint("BOTTOMRIGHT", 1, -1)
	b.bg:SetColorTexture(0, 0, 0, 1)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	b.count:SetPoint("BOTTOMRIGHT", -2, 2)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.15)
	local function inv() return invSlot(bag) end
	local function put()
		if InCombatLockdown() or not inv() then return end
		if CursorHasItem() then PutItemInBag(inv()) else PickupBagFromSlot(inv()) end
	end
	b:SetScript("OnClick", put)
	b:SetScript("OnReceiveDrag", put)
	b:SetScript("OnDragStart", function()
		if not InCombatLockdown() and inv() then PickupBagFromSlot(inv()) end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		if not (inv() and GameTooltip:SetInventoryItem("player", inv())) then
			GameTooltip:AddLine("Empty bag slot")
		end
		GameTooltip:AddLine("Drop a bag here to put it on. Click or drag to take it off (it must be empty).", 0.6, 0.8, 1, true)
		GameTooltip:Show()
		v.hoverBag = bag
		v:Repaint()
	end)
	b:SetScript("OnLeave", function()
		GameTooltip:Hide()
		v.hoverBag = nil
		v:Repaint()
	end)
	return b
end

local closeBlizzard -- forward

local function buildBags()
	local v = newView({
		frameName = "ZydeForeverBags", bags = shownBags, posKey = "bagPos",
		titleText = "Bags",
		defaultPoint = { "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -60, 110 },
		bagRowShown = bagRowShown,
		omitKeys = function() return not keysShown() end,
	})
	local win = v.win
	win.bagRow = CreateFrame("Frame", nil, win)
	win.bagRow:SetPoint("TOPLEFT", PAD, -32)
	win.bagRow:SetSize(INNER_W, S)
	win.bagSlots = {}
	for bag = 1, LAST_BAG do win.bagSlots[#win.bagSlots + 1] = bagSlot(v, bag, (bag - 1) * (S + GAP)) end
	-- The reagent bag, a little apart from the others.
	if HAS_REAGENT then win.bagSlots[#win.bagSlots + 1] = bagSlot(v, REAGENT_BAG, LAST_BAG * (S + GAP) + 10) end
	local toggle = CreateFrame("Button", nil, win)
	toggle:SetSize(22, 22)
	toggle:SetPoint("RIGHT", win.search, "LEFT", -10, 0)
	toggle:SetNormalTexture("Interface\\Buttons\\Button-Backpack-Up")
	toggle:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	toggle:SetScript("OnClick", function()
		if InCombatLockdown() then return end
		db().bagSlotsShown = not bagRowShown()
		v:PlaceContent()
		v:Layout()
	end)
	toggle:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(bagRowShown() and "Hide your bags" or "Show your bags")
		GameTooltip:AddLine("A row of your bags (and your reagent bag), to swap one for a bigger one.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
	-- Room for the key button, so the title stops before it.
	win.title:SetWidth(INNER_W - 140 - 6 - 24 - 40 - 26)
	local keysBtn = CreateFrame("Button", nil, win)
	keysBtn:SetSize(22, 22)
	keysBtn:SetPoint("RIGHT", toggle, "LEFT", -2, 0)
	local keyIcon = keysBtn:CreateTexture(nil, "ARTWORK")
	keyIcon:SetAllPoints()
	keyIcon:SetTexture("Interface\\Icons\\INV_Misc_Key_03")
	keyIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	keysBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	local function paintKeys()
		local on = keysShown()
		if keyIcon.SetDesaturated then keyIcon:SetDesaturated(not on) end
		keyIcon:SetAlpha(on and 1 or 0.4)
	end
	keysBtn:SetScript("OnClick", function()
		if InCombatLockdown() then return end
		db().bagKeysShown = not keysShown()
		paintKeys()
		v.dirty = true
		v:Layout()
	end)
	keysBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(keysShown() and "Hide keys" or "Show keys")
		GameTooltip:AddLine("Takes keys out of this window.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	keysBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	paintKeys()
	v:PlaceContent()
	paintBagSlots()

	win.restackBtn = win.AddButton("Restack", 80, "Join part stacks",
		"Puts part stacks of the same item together in your real bags. The number is how many slots that frees.",
		function() restack(shownBags()) end)
	win.sellJunk = win.AddButton("Sell junk", 70, "Sell your junk",
		"Sells every gray item that's worth something (never Perma). Only at a vendor.",
		function() sellJunk(false) end)
	win.sellJunk:Hide()
	win.AddButton("Bank", 56, "Your bank",
		"Opens the bank from the last time you visited a banker. Your bags stay open. At a banker this opens the real bank.",
		function() ns.OpenBankWindow() end)

	win:SetScript("OnShow", function()
		v:Place()
		paintKeys()
		paintBagSlots()
		win.money:SetText(moneyText())
		win.sellJunk:SetShown(MerchantFrame and MerchantFrame:IsShown() or false)
		win.Flow()
		if v.dirty and not InCombatLockdown() then v:Layout() else v:Repaint() end
	end)
	win:SetScript("OnHide", function()
		-- Closing the bags means you've seen what's new, as in the game's own bags.
		if C_NewItems and C_NewItems.ClearAll then pcall(C_NewItems.ClearAll) end
		closeBlizzard()
	end)
	return v
end

-- The scrap list and the vendor advice call this when their picks change.
function ns.BagWindowRepaint()
	for _, v in pairs(views) do if v.win:IsShown() then v:Repaint() end end
end

---------------------------------------------------------------------------
-- The bank: the same window, while you're at a banker. The game's bank window
-- is shrunk out of the way (closing it would end the visit); "Game bank"
-- brings it back, for buying bank slots or bags.
---------------------------------------------------------------------------
local gameBankShown = false
local function bankFrame() return _G.BankFrame end

local function tuckGameBank(tuck)
	local f = bankFrame()
	if not f or InCombatLockdown() then return end
	if tuck then
		f:SetAlpha(0)
		f:SetScale(0.01)
	else
		f:SetAlpha(1)
		f:SetScale(1)
	end
end

local function buildBank()
	local v = newView({
		frameName = "ZydeForeverBank", bags = bankBags, posKey = "bankPos",
		titleText = "Bank",
		defaultPoint = { "TOPLEFT", UIParent, "TOPLEFT", 20, -110 },
	})
	local win = v.win
	v:PlaceContent()
	win.restackBtn = win.AddButton("Restack", 80, "Join part stacks",
		"Puts part stacks of the same item together in the bank. The number is how many slots that frees.",
		function() restack(bankBags()) end)
	win.AddButton("Game bank", 80, "The game's bank window",
		"Brings back the game's own bank window, to buy bank slots or bags. Close and reopen the bank to come back here.",
		function()
			gameBankShown = true
			tuckGameBank(false)
			win:Hide()
		end)
	win:SetScript("OnShow", function()
		v:Place()
		if v.dirty and not InCombatLockdown() then v:Layout() else v:Repaint() end
	end)
	-- Closing this window ends the bank visit, like closing the game's.
	win:SetScript("OnHide", function()
		if not gameBankShown and CloseBankFrame then pcall(CloseBankFrame) end
	end)
	return v
end

---------------------------------------------------------------------------
-- Follow the game's bags: they still open and close as always, but inside a
-- hidden frame. Your bags window shows while any of them is open.
---------------------------------------------------------------------------
local hidden = CreateFrame("Frame")
hidden:Hide()

local function blizzFrames()
	local list = {}
	if ContainerFrameCombinedBags then list[#list + 1] = ContainerFrameCombinedBags end
	for i = 1, (NUM_CONTAINER_FRAMES or 13) do
		local f = _G["ContainerFrame" .. i]
		if f then list[#list + 1] = f end
	end
	return list
end

local function blizzOpen()
	for _, f in ipairs(blizzFrames()) do
		local id = f.GetID and f:GetID()
		-- Only the backpack and bags. The keyring rides along in this window,
		-- and the bank's own bags keep their windows.
		if f:IsShown() and (f == ContainerFrameCombinedBags or isEquippedBag(id)) then return true end
	end
	return false
end

local syncing = false
local function sync()
	if not bagsView or syncing then return end
	local win = bagsView.win
	syncing = true
	if blizzOpen() then
		if not win:IsShown() then win:Show() end
	elseif win:IsShown() then
		win:Hide()
	end
	syncing = false
end

function closeBlizzard()
	if syncing then return end
	syncing = true
	if blizzOpen() and CloseAllBags then pcall(CloseAllBags) end
	local key = keyringId()
	if key and CloseBag then pcall(CloseBag, key) end
	syncing = false
end

---------------------------------------------------------------------------
-- The bank from your last visit. The game only sends bank slots while you
-- are at a banker, so this window remembers them. You can look, link, and
-- mark Perma. Moving items waits until you are at a banker.
---------------------------------------------------------------------------
local memoryWin, layoutMemory

local function charKey()
	local name = UnitName("player")
	if ns.isSecret(name) or type(name) ~= "string" or name == "" then return nil end
	return name
end

local function savedBank()
	local key = charKey()
	local all = key and db().bankSeen
	if type(all) ~= "table" then return nil end
	local row = all[key]
	return type(row) == "table" and row or nil
end

local function rememberBank(force)
	local f = bankFrame()
	if not force and not (f and f:IsShown()) then return end
	local bags = bankBags()
	if #bags == 0 then return end
	local key = charKey()
	if not key then return end
	local data, free, extra = gather(bags)
	local items = {}
	for _, sec in ipairs(SECTIONS) do
		for group, list in pairs(data[sec] or {}) do
			for _, e in ipairs(list) do
				local info = e.info
				local id = info and info.itemID
				if id and not ns.isSecret(id) and type(id) == "number" then
					local n = 0
					if e.slots and #e.slots > 1 then
						for _, s in ipairs(e.slots) do
							local other = C_Container.GetContainerItemInfo(s.bag, s.slot)
							if other and not ns.isSecret(other.itemID) and other.itemID == id then
								local sc = other.stackCount
								n = n + ((not ns.isSecret(sc) and type(sc) == "number") and sc or 1)
							end
						end
					end
					if n == 0 then
						local sc = info.stackCount
						n = (not ns.isSecret(sc) and type(sc) == "number") and sc or 1
					end
					local link, icon, name, q = info.hyperlink, info.iconFileID, e.name, info.quality
					if ns.isSecret(link) or type(link) ~= "string" then link = nil end
					if ns.isSecret(icon) then icon = nil end
					if ns.isSecret(name) or type(name) ~= "string" then name = "" end
					if ns.isSecret(q) or type(q) ~= "number" then q = 1 end
					items[#items + 1] = {
						id = id, n = n, q = q, icon = icon, link = link, name = name,
						sec = sec, group = group,
						quest = (sec == "General" and group == "Quest") or nil,
					}
				end
			end
		end
	end
	-- An empty read while the old one had items is the bank closing under
	-- us (slots still counted, items already gone), not an empty bank.
	local old = savedBank()
	if #items == 0 and old and type(old.items) == "table" and #old.items > 0 then return end
	local savedExtra = {}
	for k, v in pairs(extra or {}) do
		if type(k) == "string" and type(v) == "number" and v > 0 then savedExtra[k] = v end
	end
	db().bankSeen = db().bankSeen or {}
	db().bankSeen[key] = { free = free or 0, extra = savedExtra, items = items, at = time() }
	if ns.RefreshBankMemory then ns.RefreshBankMemory() end
end

local function buildMemory()
	local win = CreateFrame("Frame", "ZydeForeverBankMemory", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	memoryWin = win
	win:SetWidth(INNER_W + PAD * 2)
	win:SetHeight(160)
	win:SetFrameStrata("MEDIUM")
	win:SetToplevel(true)
	win:SetClampedToScreen(true)
	win:EnableMouse(true)
	win:SetMovable(true)
	win:RegisterForDrag("LeftButton")
	if win.SetBackdrop then
		win:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		win:SetBackdropColor(0.06, 0.06, 0.07, 0.95)
		win:SetBackdropBorderColor(0, 0, 0, 1)
	end
	tinsert(UISpecialFrames, "ZydeForeverBankMemory")
	win:Hide()

	local function savePos()
		local r, btm = win:GetRight(), win:GetBottom()
		if ns.isSecret(r) or ns.isSecret(btm) or type(r) ~= "number" or type(btm) ~= "number" then return end
		db().bankMemoryPos = { x = r, y = btm }
	end
	local function place()
		win:ClearAllPoints()
		local p = db().bankMemoryPos
		if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" then
			win:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", p.x, p.y)
		else
			win:SetPoint("CENTER", -220, 40)
		end
	end
	win:SetScript("OnDragStart", function(self) self:StartMoving() end)
	win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() savePos() end)

	win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	win.title:SetPoint("TOPLEFT", PAD, -9)
	win.title:SetWidth(INNER_W - 150)
	win.title:SetJustifyH("LEFT")
	win.title:SetWordWrap(false)
	win.title:SetText("Bank")
	win.close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
	win.close:SetPoint("TOPRIGHT", 2, 2)
	win.close:SetScript("OnClick", function() win:Hide() end)

	local ok, search = pcall(CreateFrame, "EditBox", nil, win, "SearchBoxTemplate")
	if not ok or not search then search = CreateFrame("EditBox", nil, win, "InputBoxTemplate") end
	search:SetSize(140, 20)
	search:SetAutoFocus(false)
	search:SetPoint("RIGHT", win.close, "LEFT", -6, 0)
	search:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
	win.search = search

	win.content = CreateFrame("Frame", nil, win)
	win.content:SetPoint("TOPLEFT", PAD, -34)
	win.content:SetWidth(INNER_W)
	win.content:SetHeight(10)
	local note = win.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	note:SetPoint("TOPLEFT", 0, -8)
	note:SetWidth(INNER_W)
	note:SetJustifyH("LEFT")
	note:SetText("Visit a banker once. This window keeps what was there.")
	note:Hide()

	local pool, heads, labels = {}, {}, {}
	local function button(i)
		local b = pool[i]
		if b then return b end
		b = CreateFrame("Button", nil, win.content, BackdropTemplateMixin and "BackdropTemplate" or nil)
		b:SetSize(S, S)
		if b.SetBackdrop then
			b:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		end
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetPoint("TOPLEFT", 1, -1)
		b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
		b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		b.count:SetPoint("BOTTOMRIGHT", -2, 2)
		b.req = b:CreateFontString(nil, "OVERLAY")
		markFont(b.req, 9)
		b.req:SetPoint("TOPRIGHT", -1, -1)
		b.req:SetJustifyH("RIGHT")
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:SetScript("OnClick", function(self, mouse)
			if IsModifiedClick("CHATLINK") and self.link then
				if ChatEdit_InsertLink then ChatEdit_InsertLink(self.link) end
				return
			end
			if mouse == "LeftButton" and IsAltKeyDown() and self.itemID then
				togglePerma(self.itemID)
				layoutMemory()
				if bagsView and bagsView.win:IsShown() and not InCombatLockdown() then
					bagsView.dirty = true
					bagsView:Layout()
				end
			end
		end)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			local link = self.link or (self.itemID and ("item:" .. self.itemID))
			if link then GameTooltip:SetHyperlink(link) end
			GameTooltip:AddLine("From your last bank visit. You can look, not move it.", 0.6, 0.8, 1, true)
			GameTooltip:AddLine("Alt-click: " .. (ns.IsPerma(self.itemID) and "take out of Perma" or "keep in Perma"), 0.6, 0.8, 1)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		pool[i] = b
		return b
	end
	local function head(i)
		local h = heads[i]
		if h then return h end
		h = CreateFrame("Button", nil, win.content)
		h:SetSize(INNER_W, HEAD_H - 4)
		h.icon = h:CreateTexture(nil, "ARTWORK")
		h.icon:SetSize(14, 14)
		h.icon:SetPoint("LEFT", 0, 0)
		h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		h.text:SetPoint("LEFT", h.icon, "RIGHT", 4, 0)
		h.line = h:CreateTexture(nil, "ARTWORK")
		h.line:SetColorTexture(1, 0.82, 0, 0.25)
		h.line:SetHeight(1)
		h.line:SetPoint("LEFT", h.text, "RIGHT", 8, 0)
		h.line:SetPoint("RIGHT")
		h:SetScript("OnClick", function(btn)
			collapsed()[btn.section] = not collapsed()[btn.section] or nil
			layoutMemory()
			if InCombatLockdown() then
				for _, v in pairs(views) do v.dirty = true end
				return
			end
			for _, v in pairs(views) do
				v.dirty = true
				if v.win:IsShown() then v:Layout() end
			end
		end)
		heads[i] = h
		return h
	end
	local function label(i)
		local t = labels[i]
		if t then return t end
		t = win.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		t:SetJustifyH("LEFT")
		t:SetWordWrap(false)
		t:SetTextColor(0.85, 0.85, 0.85)
		labels[i] = t
		return t
	end

	local function paintItem(b, it)
		b.itemID, b.link = it.id, it.link
		local icon = it.icon
		if not icon and GetItemIcon then
			icon = ns.safe(GetItemIcon, it.id)
			if ns.isSecret(icon) then icon = nil end
		end
		b.icon:SetTexture(icon)
		if it.n > 1 then b.count:SetText(it.n) b.count:Show() else b.count:Hide() end
		local qr, qg, qb = 0.4, 0.4, 0.4
		local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[it.q]
		if c and type(c.r) == "number" and not ns.isSecret(c.r) then qr, qg, qb = c.r, c.g, c.b end
		if b.SetBackdropBorderColor then b:SetBackdropBorderColor(qr, qg, qb, 1) end
		b.req:Hide()
		local name, _, _, _, req, _, _, _, equip, _, _, classID = ns.safe(getInfoAny, it.link or it.id)
		if type(name) == "string" and not ns.isSecret(name) and it.name == "" then it.name = name end
		req = (not ns.isSecret(req) and type(req) == "number") and req or nil
		equip = (not ns.isSecret(equip) and type(equip) == "string") and equip or ""
		classID = (not ns.isSecret(classID) and type(classID) == "number") and classID or nil
		if req and req > 1 and (classID == 2 or (classID == 4 and equip ~= "")) then
			local mine = UnitLevel("player")
			local low = not ns.isSecret(mine) and type(mine) == "number" and mine < req
			b.req:SetText(req)
			if low then b.req:SetTextColor(1, 0.25, 0.2) else b.req:SetTextColor(1, 1, 1) end
			b.req:Show()
		end
		local text = (search:GetText() or ""):lower()
		local show = text == "" or (it.name or ""):lower():find(text, 1, true) ~= nil
		b:SetAlpha(show and 1 or 0.25)
	end

	local laying = false
	layoutMemory = function()
		if laying or not win:IsShown() then return end
		laying = true
		local saved = savedBank()
		local r, g, bl = freeColor(saved and saved.free or 0)
		local free = saved and ((saved.free or 0) <= 0 and "full" or ((saved.free or 0) .. " free")) or ""
		local when, tail = "", ""
		if saved and type(saved.at) == "number" then
			when = "  |cff888888" .. date("%m/%d %I:%M%p", saved.at) .. "|r"
		end
		if saved and saved.extra then
			local more = {}
			for _, kind in ipairs({ "reagent", "ammo", "soul", "special" }) do
				local n = saved.extra[kind]
				if type(n) == "number" and n > 0 then more[#more + 1] = n .. " " .. kind end
			end
			if #more > 0 then tail = "  |cff888888· " .. table.concat(more, " · ") .. "|r" end
		end
		if saved then
			win.title:SetText("Bank  " .. string.format("|cff%02x%02x%02x%s|r",
				math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(bl * 255 + 0.5), free) .. tail .. when)
		else
			win.title:SetText("Bank")
		end
		for _, h in ipairs(heads) do h:Hide() end
		for _, t in ipairs(labels) do t:Hide() end
		for _, b in ipairs(pool) do b:Hide() end
		if not saved then
			note:Show()
			win.content:SetHeight(36)
			win:SetHeight(34 + 36 + PAD)
			laying = false
			return
		end
		note:Hide()
		local data = {}
		for _, sec in ipairs(SECTIONS) do data[sec] = {} end
		for _, it in ipairs(saved.items or {}) do
			local info = { itemID = it.id, hyperlink = it.link, quality = it.q }
			local okCat, sec, group = pcall(categorize, info)
			if not okCat or type(sec) ~= "string" or not data[sec] then sec, group = it.sec, it.group end
			if it.quest and not ns.IsPerma(it.id) and group ~= "Quest" then sec, group = "General", "Quest" end
			if type(sec) ~= "string" or not data[sec] then sec, group = "General", "Other" end
			group = group or "Other"
			data[sec][group] = data[sec][group] or {}
			table.insert(data[sec][group], it)
		end
		for _, groups in pairs(data) do
			for _, list in pairs(groups) do
				table.sort(list, function(a, b)
					if a.q ~= b.q then return a.q > b.q end
					return (a.name or "") < (b.name or "")
				end)
			end
		end
		local used, labelUsed, headUsed, y = 0, 0, 0, 0
		local content = win.content
		for _, sec in ipairs(SECTIONS) do
			local groups = data[sec]
			local order = groupOrder(sec, groups)
			if #order > 0 then
				headUsed = headUsed + 1
				local h = head(headUsed)
				h.section = sec
				local folded = collapsed()[sec]
				local n = 0
				for _, gname in ipairs(order) do n = n + #groups[gname] end
				h.text:SetText(sec .. (folded and ("  |cff888888(" .. n .. ")|r") or ""))
				h.icon:SetTexture(folded and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
				h:ClearAllPoints()
				h:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
				h:Show()
				y = y + HEAD_H
				if not folded then
					local x, rowH = 0, 0
					for _, gname in ipairs(order) do
						local list = groups[gname]
						local cols = math.min(#list, COLS)
						local w = cols * (S + GAP) - GAP
						if x > 0 and x + w > INNER_W then
							x = 0
							y = y + rowH + 6
							rowH = 0
						end
						labelUsed = labelUsed + 1
						local l = label(labelUsed)
						l:ClearAllPoints()
						l:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
						l:SetWidth(math.max(w, S))
						l:SetText(gname)
						l:Show()
						for i, it in ipairs(list) do
							used = used + 1
							local b = button(used)
							local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
							b:ClearAllPoints()
							b:SetPoint("TOPLEFT", content, "TOPLEFT", x + col * (S + GAP), -(y + LABEL_H + row * (S + GAP)))
							paintItem(b, it)
							b:Show()
						end
						local rows = math.ceil(#list / cols)
						rowH = math.max(rowH, LABEL_H + rows * (S + GAP) - GAP)
						x = x + w + GROUP_GAP
					end
					y = y + rowH + 10
				end
			end
		end
		content:SetHeight(math.max(10, y))
		win:SetHeight(y + 34 + PAD + 8)
		laying = false
	end

	search:HookScript("OnTextChanged", function() layoutMemory() end)
	win:SetScript("OnShow", function()
		place()
		layoutMemory()
	end)
end

function ns.RefreshBankMemory()
	if layoutMemory then layoutMemory() end
end

local installed = false
local function install()
	if installed or not on() or InCombatLockdown() then return end
	installed = true
	bagsView = buildBags()
	bankView = buildBank()
	buildMemory()
	-- The same frames also show bank bags: each time one opens, it goes in the
	-- hidden frame for your own bags and back on screen for a bank bag.
	for _, f in ipairs(blizzFrames()) do
		if f == ContainerFrameCombinedBags then
			f:SetParent(hidden)
		else
			local function place(self)
				local id = self:GetID()
				local want = isMine(id) and hidden or UIParent
				if self:GetParent() ~= want then self:SetParent(want) end
			end
			place(f)
			hooksecurefunc(f, "Show", function(self)
				place(self)
				-- The keyring button opens your bags. A bank visit can also
				-- show that frame; the bags stay as they were.
				if syncing or not isKeyring(self:GetID()) then return end
				local bank = bankFrame()
				if bank and bank:IsShown() then return end
				if bagsView and not bagsView.win:IsShown() then bagsView.win:Show() end
			end)
			hooksecurefunc(f, "SetID", place)
		end
	end
	for _, fn in ipairs({ "OpenAllBags", "CloseAllBags", "ToggleAllBags", "OpenBackpack", "CloseBackpack",
		"ToggleBackpack", "ToggleBag", "OpenBag", "CloseBag" }) do
		if type(_G[fn]) == "function" then hooksecurefunc(fn, sync) end
	end
	bagsView:Layout()
end

function ns.OpenBankWindow()
	if not on() then
		print(P .. "turn on One bag window in /zyde")
		return
	end
	if not bankView then
		if InCombatLockdown() then
			print(P .. "open your bags once out of combat first")
			return
		end
		install()
	end
	if not bankView then return end
	local live = bankFrame()
	if live and live:IsShown() then
		gameBankShown = false
		tuckGameBank(true)
		bankView.dirty = true
		bankView.win:Show()
		if not InCombatLockdown() then bankView:Layout() else bankView:Repaint() end
		return
	end
	if not memoryWin then return end
	memoryWin:SetShown(not memoryWin:IsShown())
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED",
	"BAG_UPDATE_COOLDOWN", "PLAYER_REGEN_ENABLED", "PLAYER_MONEY", "GET_ITEM_INFO_RECEIVED", "QUEST_LOG_UPDATE",
	"BAG_CONTAINER_UPDATE", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "PLAYER_EQUIPMENT_CHANGED",
	"LEARNED_SPELL_IN_TAB", "NEW_RECIPE_LEARNED", "MERCHANT_SHOW", "MERCHANT_CLOSED",
	"BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "PLAYERBANKBAGSLOTS_CHANGED" }) do
	pcall(ev.RegisterEvent, ev, e)
end
-- For a few seconds after login or a reload the game can flag everything you
-- carry as new. Nothing is new then: clear it while the bags fill in.
local loginQuietUntil = 0
local function clearNew() if C_NewItems and C_NewItems.ClearAll then pcall(C_NewItems.ClearAll) end end

local function allChanged()
	for _, v in pairs(views) do v:Changed() end
end

ev:SetScript("OnEvent", function(_, event, isLogin, isReload)
	if event == "PLAYER_ENTERING_WORLD" then
		if isLogin or isReload then
			loginQuietUntil = GetTime() + 5
			clearNew()
		end
		return
	end
	if event == "BAG_UPDATE_DELAYED" and GetTime() < loginQuietUntil then clearNew() end
	-- Junk sells by itself at a vendor, bag window or not.
	if event == "MERCHANT_SHOW" then
		if ns.F("sellJunk") then C_Timer.After(0.3, function() sellJunk(true) end) end
		if bagsView then bagsView.win.sellJunk:Show() bagsView.win.Flow() end
		return
	end
	if event == "MERCHANT_CLOSED" then
		if bagsView then bagsView.win.sellJunk:Hide() bagsView.win.Flow() end
		return
	end
	if event == "PLAYER_LOGIN" then install() return end
	if not bagsView then
		if event == "PLAYER_REGEN_ENABLED" then install() end
		return
	end
	if event == "BANKFRAME_OPENED" then
		gameBankShown = false
		tuckGameBank(true)
		bankView.dirty = true
		bankView.win:Show()
		C_Timer.After(0.25, rememberBank)
		return
	end
	if event == "BANKFRAME_CLOSED" then
		-- (no snapshot here: by now the items can already be gone, which
		-- saved an empty bank over the real one)
		gameBankShown = true -- (so hiding ours doesn't close the bank again)
		bankView.win:Hide()
		tuckGameBank(false)
		return
	end
	if event == "PLAYER_LEVEL_UP" or event == "SKILL_LINES_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED"
		or event == "LEARNED_SPELL_IN_TAB" or event == "NEW_RECIPE_LEARNED" then
		-- What you can use, and what's an upgrade, may have changed: read the tooltips again.
		wipe(scanCache)
		-- (a full sort, not just a repaint: the Upgrades section may change)
		allChanged()
		return
	end
	if event == "PLAYER_MONEY" then
		bagsView.win.money:SetText(moneyText())
		return
	end
	if event == "BAG_CONTAINER_UPDATE" or event == "BAG_UPDATE_DELAYED" then paintBagSlots() end
	if event == "ITEM_LOCK_CHANGED" or event == "BAG_UPDATE_COOLDOWN" then
		ns.BagWindowRepaint()
		return
	end
	if bankFrame() and bankFrame():IsShown() then rememberBank() end
	allChanged()
end)
