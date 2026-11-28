-- Zyde_Forever: all your bags in one window, sorted into sections.
--   Opens instead of the game's bags (B, the bag buttons, vendors, mail...).
--   General: Perma (never delete), Quest, Junk, Keys, Other.
--   Gear: weapons, armor, bags, ammo. Consumables: food & drink, potions,
--   bandages, scrolls, other. Profession: trade goods by type, reagents, recipes.
--   Items are real bag slots: right-click uses or sells, and with mail or the
--   auction house open it attaches or lists the item. Drag moves, shift-click
--   links. While you drag an item, or the split-stack box is open, one empty
--   slot appears at the bottom left under a New Item header, so the drop or
--   the split has somewhere to land. The title counts free slots (reagent bag, quiver... apart, in gray).
--   Alt-click an item to put it in Perma (or take it out). Double-click a heading to fold it.
--   The title shows used/total (orange at 5 or fewer free, red and FULL when full).
--   Buttons: Restack (joins part stacks, and moves an item into the reagent
--   bag, quiver, or other special bag that takes it when that bag has room),
--   Sell junk (at a vendor; junk also sells by itself there, see
--   "Sell junk at vendors" in /zyde).
--   At a banker the bank gets the same sorted window. A right-click moves an
--   item from your bags into that bank, or from the bank back into your bags.
--   A row of bank bags lets you buy the next slot and swap bags.
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
local canEnterReagentBag
local function numSlots(bag)
	local n = ns.safe(C_Container.GetContainerNumSlots, bag)
	if ns.isSecret(n) or type(n) ~= "number" then return 0 end
	return n
end
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
	[211527] = true, -- Cozy Sleeping Bag
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

-- Bag order marks. Alt+right-click cycles them. The border is the level the
-- player picked, not quality or gear score: none, Keep, Useful, Important.
local MARKS = {
	{ name = "Keep", r = 0.72, g = 0.72, b = 0.76 },
	{ name = "Useful", r = 1, g = 0.82, b = 0.25 },
	{ name = "Important", r = 0.95, g = 0.28, b = 0.22 },
}
local function markDB() db().bagMark = db().bagMark or {} return db().bagMark end
function ns.BagMark(id)
	if not id or ns.isSecret(id) then return nil end
	local n = markDB()[id]
	if type(n) ~= "number" or n < 1 or n > #MARKS then return nil end
	return n
end
local function cycleMark(id)
	local n = ns.BagMark(id) or 0
	markDB()[id] = n >= #MARKS and nil or (n + 1)
end
local function markName(id)
	local n = ns.BagMark(id)
	return n and MARKS[n].name or "unmarked"
end
local function bagOrderOn() return ns.F and ns.F("bagOrder") end

-- Junk you marked yourself, any quality: sorted under Junk and sold at
-- vendors like grays. Marking something junk takes it out of Perma.
local function junkDB() db().bagJunk = db().bagJunk or {} return db().bagJunk end
function ns.IsMarkedJunk(id) return id ~= nil and junkDB()[id] == true end
local function setJunk(id, on)
	junkDB()[id] = on and true or nil
	if on and ns.IsPerma(id) then permaDB()[id] = false end
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
	if ns.IsMarkedJunk(id) then return "General", "Junk" end
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

-- Retail returns one table. This client also returns the three classic values
-- (isQuestItem, questID, isActive). ns.safe keeps every return.
local function questRecord(bag, slot)
	local fn = C_Container and C_Container.GetContainerItemQuestInfo
	if not fn then return nil end
	local a, b, c = ns.safe(fn, bag, slot)
	if type(a) == "table" then return a end
	if a == nil and b == nil then return nil end
	local id = b
	if type(id) ~= "number" then id = tonumber(id) end
	return { isQuestItem = a and true or false, questID = id, isActive = c and true or false }
end
local BEGINS_QUEST = ITEM_STARTS_QUEST or "This Item Begins a Quest"
local beginsCache = {}
local function textBeginsQuest(text)
	if type(text) ~= "string" or ns.isSecret(text) then return false end
	if text == BEGINS_QUEST then return true end
	return text:lower():find("begins a quest", 1, true) ~= nil
end
local function tooltipBeginsQuest(bag, slot, link)
	if type(link) ~= "string" or ns.isSecret(link) then return false end
	local cached = beginsCache[link]
	if cached ~= nil then return cached end
	local found = false
	local data = C_TooltipInfo and C_TooltipInfo.GetBagItem and ns.safe(C_TooltipInfo.GetBagItem, bag, slot)
	local lines = type(data) == "table" and data.lines
	if type(lines) == "table" then
		for _, line in ipairs(lines) do
			if textBeginsQuest(line.leftText) or textBeginsQuest(line.rightText) then
				found = true
				break
			end
		end
	end
	if not found then
		local tip = _G.ZydeForeverQuestScanTip
		if not tip then
			tip = CreateFrame("GameTooltip", "ZydeForeverQuestScanTip", nil, "GameTooltipTemplate")
			tip:SetOwner(UIParent, "ANCHOR_NONE")
		end
		tip:ClearLines()
		if pcall(tip.SetBagItem, tip, bag, slot) then
			for i = 1, tip:NumLines() or 0 do
				local fs = _G["ZydeForeverQuestScanTipTextLeft" .. i]
				if fs and textBeginsQuest(fs:GetText()) then
					found = true
					break
				end
			end
		end
	end
	beginsCache[link] = found
	return found
end
local function startsQuest(bag, slot)
	local q = questRecord(bag, slot)
	if type(q) == "table" then
		local id = q.questID
		if id and not ns.isSecret(id) and id ~= 0 and not q.isActive then
			-- Done already (some starters stay in your bags): no !.
			local done = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and ns.safe(C_QuestLog.IsQuestFlaggedCompleted, id)
			return done ~= true
		end
		if q.isActive then return false end
	end
	local info = C_Container.GetContainerItemInfo(bag, slot)
	local link = type(info) == "table" and info.hyperlink
	return tooltipBeginsQuest(bag, slot, link)
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
-- Item ids whose name was not loaded yet. The auction house fires this for
-- every listing it loads; only an id we asked about is allowed to re-sort.
local waitingIds = {}
local getInfoAny = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local LOCKED_TEXT = LOCKED or "Locked"
local STARTS_TEXT = ITEM_STARTS_QUEST or "This Item Begins a Quest"

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
				if text == STARTS_TEXT then c.starts = true end
				if col and type(col.r) == "number" and not ns.isSecret(col.r)
					and col.r > 0.95 and col.g < 0.2 and col.b < 0.2 then
					c.red = true
				end
			end
		end
	end
	local name, _, _, _, reqLevel, _, _, _, equipLoc, _, sellPrice, classID, _, bindType = ns.safe(getInfoAny, info.hyperlink or info.itemID)
	if type(name) ~= "string" or ns.isSecret(name) then
		-- Not loaded yet. Remember the id so the next info event can re-sort once.
		local id = info.itemID
		if not ns.isSecret(id) and type(id) == "number" then waitingIds[id] = true end
		return c
	end
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

-- Combined (the default) draws every stack of an item as one tile. Each slot
-- keeps that window's own slots, one tile each. Bags and the bank are
-- separate choices in /zyde, under One bag window.
local function separateSlots(which)
	local key = which == "bank" and "bankStacks" or "bagStacks"
	return ZydeForeverDB and ZydeForeverDB[key] == "slot"
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

local function merge(list, separate)
	if separate then
		for _, e in ipairs(list) do
			e.slots = { { bag = e.bag, slot = e.slot } }
			e.smallest = e.info and e.info.stackCount or 1
		end
		return list
	end
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

-- One real empty slot, for a drop or a stack split. It is only shown while an
-- item is on the cursor, or the split-stack box is open. An ordinary bag comes
-- first (anything can go there). A reagent bag, quiver, or other special bag
-- is used only when those are full. The keyring is never it.
local function isOrdinaryBag(bag, fam)
	if isKeyring(bag) then return false end
	if bag == REAGENT_BAG and HAS_REAGENT then return false end
	return (tonumber(fam) or 0) == 0
end

local function emptyTexture(bag, ordinary)
	local tex = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
	if ordinary then return tex end
	-- Empty reagent slots were the reagent bag's own icon, a green sack
	-- (GetInventoryItemTexture on the bag). They use the normal empty slot.
	if HAS_REAGENT and bag == REAGENT_BAG then return tex end
	local inv = invSlot(bag)
	if inv then return GetInventoryItemTexture("player", inv) or tex end
	return tex
end

local function plainNum(v)
	if ns.isSecret(v) then return 0 end
	if v == nil then return 0 end
	return tonumber(v) or 0
end

-- A secret item id counts as taken, so the drop slot is never a slot we cannot read.
local function slotTaken(bag, slot)
	local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
	if not ok or ns.isSecret(info) then return true end
	if info == nil then return false end
	local id = info.itemID
	if ns.isSecret(id) then return true end
	return id ~= nil
end

local function firstEmpty(bags, ordinaryOnly)
	local held
	if GetCursorInfo then
		local ok, kind, id = pcall(GetCursorInfo)
		if ok and not ns.isSecret(kind) and kind == "item" and type(id) == "number" and not ns.isSecret(id) then held = id end
	end
	local pick
	for _, bag in ipairs(bags) do
		-- The spare drop slot is never a reagent slot unless the item on the
		-- cursor is one that bag accepts. Anything else errors on the drop.
		local reagentDrop = HAS_REAGENT and bag == REAGENT_BAG and canEnterReagentBag(held) ~= true
		if not isKeyring(bag) and not reagentDrop then
			local free, fam = C_Container.GetContainerNumFreeSlots(bag)
			free, fam = plainNum(free), plainNum(fam)
			local ordinary = isOrdinaryBag(bag, fam)
			if free > 0 and numSlots(bag) > 0 and (ordinary or not ordinaryOnly) then
				for slot = 1, numSlots(bag) do
					if not slotTaken(bag, slot) then
						pick = {
							empty = true, bag = bag, slot = slot, ordinary = ordinary,
							tex = emptyTexture(bag, ordinary),
						}
						break
					end
				end
				if pick then break end
			end
		end
	end
	if not pick then return nil end
	-- The number on the slot is how many free slots of this kind are left.
	local n = 0
	for _, bag in ipairs(bags) do
		if not isKeyring(bag) then
			local free, fam = C_Container.GetContainerNumFreeSlots(bag)
			free, fam = plainNum(free), plainNum(fam)
			if isOrdinaryBag(bag, fam) == pick.ordinary then n = n + free end
		end
	end
	pick.count = n
	return pick
end

-- Every filled slot of these bags, sorted into section -> group -> list.
-- Also returns the free slots in ordinary bags, special-bag free counts, and
-- one real empty slot when any shown bag still has room.
local function gather(bags, which)
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
	local ordinaryFree, ordinarySlots, extra = 0, 0, {}
	for _, bag in ipairs(bags) do
		-- Empty key slots only hold keys. They are not free bag space.
		if not isKeyring(bag) then
			local free, fam = C_Container.GetContainerNumFreeSlots(bag)
			free, fam = plainNum(free), plainNum(fam)
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
				ordinarySlots = ordinarySlots + numSlots(bag)
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
				groups[g] = merge(list, separateSlots(which))
			end
		end
	end
	-- Ordinary room first, so a split or a new item has a slot that can take it.
	-- If those bags are full, the first free special-bag slot still shows.
	local reserve = firstEmpty(bags, true) or firstEmpty(bags, false)
	return out, ordinaryFree, extra, reserve, ordinarySlots, restackSavings(tally)
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

-- "48/60", or "60/60 FULL" when nothing is free. Older saves that never
-- recorded a size still say "12 free" or "full".
local function usageLabel(free, slots)
	free = type(free) == "number" and free or 0
	slots = type(slots) == "number" and slots or 0
	if slots > 0 then
		local used = math.max(0, slots - free)
		if used >= slots then return used .. "/" .. slots .. " FULL" end
		return used .. "/" .. slots
	end
	if free <= 0 then return "full" end
	return free .. " free"
end

---------------------------------------------------------------------------
-- A window of sorted bags. Two of them: your bags, and the bank.
---------------------------------------------------------------------------
local View = {}
View.__index = View
local views = {}

local function collapsed() db().bagCollapsed = db().bagCollapsed or {} return db().bagCollapsed end

-- A heading used to fold on any mouse-up still over it. The bar is as wide as
-- the window, so a short click, a drag that ends there, or the wheel did it.
-- Now it takes a second click, and the pointer has to stay put.
local FOLD_MOVE = 6  -- pixels. Old limit: none (0), any release folded.
local FOLD_GAP = 0.4 -- seconds between the two clicks.

local function cursorPos()
	local x, y = GetCursorPosition()
	if ns.isSecret(x) or ns.isSecret(y) or type(x) ~= "number" or type(y) ~= "number" then return nil end
	return x, y
end

local function armFold(btn)
	btn:RegisterForClicks("LeftButtonUp")
	btn:SetScript("OnMouseDown", function(self, mouse)
		if mouse ~= "LeftButton" then return end
		self.foldX, self.foldY = cursorPos()
	end)
	btn:SetScript("OnMouseWheel", function() end)
	btn:SetScript("OnClick", function(self, mouse)
		if mouse ~= "LeftButton" then return end
		local x, y = cursorPos()
		if x and self.foldX then
			local scale = self:GetEffectiveScale()
			if ns.isSecret(scale) or type(scale) ~= "number" or scale <= 0 then scale = 1 end
			local dx, dy = (x - self.foldX) / scale, (y - self.foldY) / scale
			if dx * dx + dy * dy > FOLD_MOVE * FOLD_MOVE then
				self.foldAt = nil
				return
			end
		end
		local now = GetTime()
		if ns.isSecret(now) or type(now) ~= "number" then return end
		if not self.foldAt or now - self.foldAt > FOLD_GAP then
			self.foldAt = now
			return
		end
		self.foldAt = nil
		if self.fold then self.fold(self) end
	end)
end

function View:Holder(bag)
	if self.holders[bag] then return self.holders[bag] end
	local h = CreateFrame("Frame", nil, self.win)
	h:SetID(bag)
	h:SetAllPoints()
	h:SetFrameLevel((self.win:GetFrameLevel() or 1) + 2)
	self.holders[bag] = h
	return h
end

local buttonCount = 0
-- The secure use buttons live on this layer, not on the bag window, so the
-- window itself does not become protected. They stay up during a fight: that
-- is what lets a right-click use a health pot. Mouse stays off on the layer
-- itself; only the slot-sized buttons take clicks.
local layer
local function useLayer()
	if layer then return layer end
	layer = CreateFrame("Frame", "ZydeForeverBagUseLayer", UIParent, "SecureHandlerStateTemplate")
	layer:SetAllPoints()
	-- The bag window is HIGH and toplevel, so its item buttons sit above anything
	-- else in HIGH. This layer has to be DIALOG or the use buttons are clamped
	-- under those slots and a right-click never reaches them.
	layer:SetFrameStrata("DIALOG")
	layer:EnableMouse(false)
	if layer.SetMouseClickEnabled then layer:SetMouseClickEnabled(false) end
	if layer.SetMouseMotionEnabled then layer:SetMouseMotionEnabled(false) end
	-- A visibility driver used to hide this layer for the whole fight. That
	-- took the pot buttons with it. Do not put that driver back.
	if UnregisterStateDriver then UnregisterStateDriver(layer, "visibility") end
	return layer
end

-- The auction house is open. A right-click should fill the sale form, the same
-- as a right-click in the game's own bags.
local function frameShown(f)
	if not f then return false end
	-- IsShown is only this frame's own flag. A child such as the compose page
	-- stays "shown" after its window closes. IsVisible is the window on screen.
	local probe = f.IsVisible or f.IsShown
	if type(probe) ~= "function" then return false end
	local shown = probe(f)
	if ns.isSecret(shown) or not shown then return false end
	return true
end
local function auctionHouseOpen()
	return frameShown(AuctionHouseFrame) or frameShown(AuctionFrame)
end
-- The vendor window. IsShown can stay true after it closes, the same way the
-- compose page does, so this uses the on-screen check.
local function merchantOpen()
	return frameShown(MerchantFrame)
end
-- The compose tab, and only while the mailbox window is actually open.
-- Otherwise a right-click tries to attach the item and the game says a
-- soulbound item cannot be mailed.
local function sendMailOpen()
	local compose = frameShown(SendMailFrame) or frameShown(MailFrame and MailFrame.SendMailFrame)
	if not MailFrame then return compose end
	return frameShown(MailFrame) and compose
end
-- The mailbox itself, inbox or compose. The compose tab still has its own
-- check, because only that tab attaches an item.
local function mailOpen()
	return frameShown(MailFrame)
end
-- The player trade window. Same bag-sort hold as the bank and the auction house.
local function tradeOpen()
	return frameShown(TradeFrame)
end
-- Filled in once the cursor helper exists. A right-click with the compose
-- window open attaches the item. Returns true when that click is handled.
local transferAtBank, attachToMail

local function postToAuction(b)
	local ah = AuctionHouseFrame
	if b.empty or not ah or not ah.SetPostItem or not frameShown(ah) then return false end
	local bag = b.bagID
	if type(bag) ~= "number" and b.GetParent then
		local parent = b:GetParent()
		bag = parent and parent.GetID and parent:GetID()
	end
	local slot = b.GetID and b:GetID()
	if ns.isSecret(bag) or ns.isSecret(slot) or type(bag) ~= "number" or type(slot) ~= "number" then return false end
	if not ItemLocation or not ItemLocation.CreateFromBagAndSlot then return false end
	local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
	if not loc then return false end
	local listing = ah.IsListingAuctions and ah:IsListingAuctions()
	if ns.isSecret(listing) then listing = false end
	local valid = false
	if loc.IsValid and loc:IsValid() and C_AuctionHouse and C_AuctionHouse.IsSellItemValid then
		local ok, v = pcall(C_AuctionHouse.IsSellItemValid, loc, false)
		valid = ok and v and not ns.isSecret(v) and true or false
	end
	-- On the sell tab, post even when the item cannot be listed, so the
	-- auction house can say why. On any other tab, only a sellable item.
	if not listing and not valid then return true end
	ah:SetPostItem(loc)
	return true
end

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
	-- Do not hook OnClick, and do not wrap ContainerFrameItemButton_OnClick.
	-- Either one taints the click, and the game then blocks UseContainerItem.
	-- Alt-click Perma is a cover that only shows while Alt is held, so the
	-- item button's own click is the one that uses, picks up, and drops.
	b.zydeBag = true
	-- Perma sits above the secure right-click button. That button is DIALOG, so a
	-- cover on the slot itself never sees the click.
	local alt = CreateFrame("Button", nil, useLayer())
	alt:SetSize(S, S)
	alt:SetFrameStrata("DIALOG")
	alt:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	alt:Hide()
	alt:SetScript("OnClick", function(_, mouse)
		if b.empty then return end
		local parent = b:GetParent()
		if not parent or not parent.GetID then return end
		local info = C_Container.GetContainerItemInfo(parent:GetID(), b:GetID())
		if ns.isSecret(info) or not info or ns.isSecret(info.itemID) or not info.itemID then return end
		-- Bag order: Alt+right-click sets the importance border. It does not
		-- put the item in Perma. Alt+left-click still does.
		if mouse == "RightButton" and bagOrderOn() then cycleMark(info.itemID)
		else togglePerma(info.itemID) end
		for _, v in pairs(views) do
			v.dirty = true
			if v.win:IsShown() and not InCombatLockdown() then v:Layout() end
		end
	end)
	alt:SetScript("OnEnter", function()
		local parent = b:GetParent()
		GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
		if parent and parent.GetID and GameTooltip.SetBagItem then
			GameTooltip:SetBagItem(parent:GetID(), b:GetID())
		end
		if bagOrderOn() then
			local parentId = parent and parent.GetID and parent:GetID()
			local info = parentId and C_Container.GetContainerItemInfo(parentId, b:GetID())
			local id = info and info.itemID
			GameTooltip:AddLine("Alt+right-click: " .. markName(id), 0.6, 0.8, 1)
			GameTooltip:AddLine("Alt+left-click: " .. (b.perma and "take out of Perma" or "keep in Perma"), 0.6, 0.8, 1)
		else
			GameTooltip:AddLine("Alt-click: " .. (b.perma and "take out of Perma" or "keep in Perma"), 0.6, 0.8, 1)
		end
		GameTooltip:Show()
	end)
	alt:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b.alt = alt
	-- Above the slot while the bank, mailbox, or auction house is open. A right
	-- click then moves, attaches, or lists the item. Left clicks pass through
	-- so the item can still be dragged.
	local move = CreateFrame("Button", nil, useLayer())
	move:SetSize(S, S)
	move:SetFrameStrata("DIALOG")
	move:RegisterForClicks("RightButtonUp")
	if move.SetPassThroughButtons then move:SetPassThroughButtons("LeftButton", "MiddleButton") end
	if move.SetMouseMotionEnabled then move:SetMouseMotionEnabled(false) end
	move:SetScript("OnClick", function()
		if transferAtBank(b) then return end
		if auctionHouseOpen() then postToAuction(b) return end
		attachToMail(b)
	end)
	move:Hide()
	b.move = move
	-- Right-click use cannot run from this addon button: the game blocks it as
	-- tainted. A secure button sits on the slot and uses the item itself.
	-- Left clicks pass through to this button, which still picks up and drops.
	local use = CreateFrame("Button", nil, useLayer(), "SecureActionButtonTemplate, SecureHandlerBaseTemplate")
	use:SetSize(S, S)
	-- The bag window is HIGH and toplevel, and its item buttons sit above that.
	-- A HIGH button under them never sees the click. DIALOG is above the window.
	use:SetFrameStrata("DIALOG")
	use:SetFrameLevel(100)
	use:RegisterForClicks("RightButtonDown", "RightButtonUp")
	use:EnableMouse(true)
	if use.SetMouseClickEnabled then use:SetMouseClickEnabled(true) end
	-- Motion falls through so the slot underneath still shows its tooltip.
	if use.SetMouseMotionEnabled then use:SetMouseMotionEnabled(false) end
	if use.SetPassThroughButtons then use:SetPassThroughButtons("LeftButton", "MiddleButton") end
	use:Hide()
	-- One right-click, on the release, when this button hands the click to the game's bag slot.
	-- That slot sells at a vendor, and for a bandage it lets you pick who to use it on.
	SecureHandlerWrapScript(use, "PreClick", use, [[
		if not self:GetAttribute("forward") then return end
		if down then
			self:SetAttribute("type2", nil)
			self:SetAttribute("*type2", nil)
		else
			self:SetAttribute("type2", "click")
			self:SetAttribute("*type2", "click")
		end
	]])
	use.owner = b
	b.use = use
	-- Right before a right-click uses anything: it has to be over this button's own slot, and
	-- use that slot. (A friend's right-click on a Craftsman's Writ opened another item, a
	-- journal; this catches it and says what happened.)
	use:HookScript("PreClick", function(self, button)
		if button ~= "RightButton" or InCombatLockdown() or self:GetAttribute("forward") then return end
		local owner = self.owner
		local bag = owner.bagID
		if type(bag) ~= "number" and owner:GetParent() and owner:GetParent().GetID then bag = owner:GetParent():GetID() end
		local slot = owner:GetID()
		if ns.isSecret(bag) or ns.isSecret(slot) or type(bag) ~= "number" or type(slot) ~= "number" then return end
		local where = bag .. " " .. slot
		local kind = self:GetAttribute("type2")
		local used
		if kind == "item" then used = self:GetAttribute("item2")
		elseif kind == "macro" then used = (self:GetAttribute("macrotext2") or ""):match("^/use (.+)$") end
		local quiet = self.toldAt and GetTime() - self.toldAt < 0.5 -- (down and up: one line)
		local function nameAt(spot)
			local b2, s2 = tostring(spot or ""):match("^(%-?%d+) (%d+)$")
			local link = b2 and C_Container.GetContainerItemLink(tonumber(b2), tonumber(s2))
			return (type(link) == "string" and not ns.isSecret(link)) and link or "nothing"
		end
		if not owner:IsMouseOver() then
			self:SetAttribute("type2", nil)
			self:SetAttribute("*type2", nil)
			self.itemKey = nil -- (set again on the next frame)
			self.toldAt = GetTime()
			if not quiet then print("|cff33ff99Zyde|r: skipped that right-click - it landed on the button for " .. nameAt(where)
				.. ", not the slot under your mouse. Please tell the author.") end
		elseif used and used ~= where then
			local field = kind == "item" and "item2" or "macrotext2"
			local value = kind == "item" and where or ("/use " .. where)
			self:SetAttribute(field, value)
			self:SetAttribute("*" .. field, value)
			self.toldAt = GetTime()
			if not quiet then print("|cff33ff99Zyde|r: that right-click was set for " .. nameAt(used) .. "; used " .. nameAt(where)
				.. " instead. Please tell the author.") end
		end
	end)
	local origClick = b:GetScript("OnClick")
	-- The template's own click is what the default bags run. A right-click there
	-- is UseContainerItem, which starts a quest and does not equip a necklace.
	-- Our wrapper is addon code, so UseContainerItem is blocked from it. Quest
	-- items put this original click back. Everything else keeps the wrapper so
	-- the secure button above the slot can use a health pot.
	b.origClick = origClick
	if origClick then
		local function wrapped(self, button, ...)
			local aimingNow = button == "LeftButton" and SpellCanTargetItem and SpellCanTargetItem()
			if button == "RightButton" or (aimingNow and InCombatLockdown()) then
				if button == "RightButton" and transferAtBank(self) then return end
				if button == "RightButton" and auctionHouseOpen() then postToAuction(self) return end
				if button == "RightButton" and attachToMail(self) then return end
				return
			end
			return origClick(self, button, ...)
		end
		b.wrappedClick = wrapped
		b:SetScript("OnClick", wrapped)
	end
	b:HookScript("OnEnter", function(btn)
		if btn.empty then
			GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
			if btn.realSlot then
				GameTooltip:AddLine("Empty slot")
				GameTooltip:AddLine("Drop an item here.", 1, 1, 1, true)
			else
				local n = tonumber(btn.emptyCount) or 0
				GameTooltip:AddLine(n == 1 and "Empty slot" or (n .. " empty slots"))
				GameTooltip:AddLine("Drop an item here, or split a stack into it.", 1, 1, 1, true)
				if not btn.emptyOrdinary then
					GameTooltip:AddLine("Only what this bag holds can go here.", 0.8, 0.8, 0.8, true)
				end
			end
			GameTooltip:Show()
			return
		end
		if GameTooltip:IsOwned(btn) then
			if bagOrderOn() then
				local parent = btn:GetParent()
				local info = parent and parent.GetID and C_Container.GetContainerItemInfo(parent:GetID(), btn:GetID())
				GameTooltip:AddLine("Alt+right-click: " .. markName(info and info.itemID), 0.6, 0.8, 1)
			end
			GameTooltip:AddLine("Alt-click: " .. (btn.perma and "take out of Perma" or "keep in Perma"), 0.6, 0.8, 1)
			local info = C_Container.GetContainerItemInfo(btn:GetParent():GetID(), btn:GetID())
			if info and ns.IsMarkedJunk(info.itemID) then
				GameTooltip:AddLine("Marked as junk: sold at vendors. Drag it onto the bar at the top of your bags to unmark it.", 1, 0.55, 0.3, true)
			else
				GameTooltip:AddLine("Drag it onto the Junk bar at the top of your bags to sell it at vendors.", 0.6, 0.6, 0.6, true)
			end
			GameTooltip:Show()
		end
	end)
	self.pool[i] = b
	return b
end

-- The cover sits on a slot only while Alt is held, and never while a cursor
-- item is waiting to drop. The slot's own click is left alone.
local function cursorHolding()
	if not CursorHasItem then return false end
	local ok, has = pcall(CursorHasItem)
	return ok and not ns.isSecret(has) and has
end

-- An empty attachment slot, or nil when this client has no such slot.
local function emptyMailSlot()
	local maxN = (type(ATTACHMENTS_MAX_SEND) == "number" and ATTACHMENTS_MAX_SEND) or 12
	if not GetSendMailItem then return 1 end
	for i = 1, maxN do
		local ok, name = pcall(GetSendMailItem, i)
		if not ok then return i == 1 and 1 or nil end
		if ns.isSecret(name) then name = "taken" end
		if type(name) ~= "string" or name == "" then return i end
	end
end
local function clickMailSlot(index)
	if ClickSendMailItemButton and pcall(ClickSendMailItemButton, index) and not cursorHolding() then return true end
	local named = _G["SendMailAttachment" .. (index or 1)]
	if named and named.Click and pcall(named.Click, named, "LeftButton") and not cursorHolding() then return true end
	local root = SendMailFrame
	local box = root and (root.SendMailAttachments or root.Attachments)
	if box and box.GetChildren then
		for _, child in ipairs({ box:GetChildren() }) do
			if child.Click and child.GetID and child:GetID() == index then
				if pcall(child.Click, child, "LeftButton") and not cursorHolding() then return true end
			end
		end
	end
end

-- The secure use button would use or equip this. Pick it up and drop it on
-- the compose window instead, which is what a bag right-click does there.
function attachToMail(b)
	if not sendMailOpen() then return false end
	if b.empty or cursorHolding() then return true end
	local bag = b.bagID
	if type(bag) ~= "number" and b.GetParent and b:GetParent() and b:GetParent().GetID then
		bag = b:GetParent():GetID()
	end
	local slot = b.GetID and b:GetID()
	if ns.isSecret(bag) or ns.isSecret(slot) or type(bag) ~= "number" or type(slot) ~= "number" then return true end
	C_Container.PickupContainerItem(bag, slot)
	if not cursorHolding() then
		print(P .. "that item didn't attach")
		return true
	end
	clickMailSlot(emptyMailSlot())
	if cursorHolding() and ClickSendMailItemButton then pcall(ClickSendMailItemButton) end
	if cursorHolding() then
		C_Container.PickupContainerItem(bag, slot)
		print(P .. "the mail can't take that")
	end
	return true
end
-- The drop slot is for putting something down: a dragged item, or a stack
-- you are in the middle of splitting (the split box is open, cursor still empty).
local function wantDropSlot()
	if cursorHolding() then return true end
	return StackSplitFrame and StackSplitFrame.IsShown and StackSplitFrame:IsShown() and true or false
end
local function refreshAltCovers()
	-- placeUse positions these. Releasing Alt hides them at once.
	local altDown = IsAltKeyDown()
	if ns.isSecret(altDown) then altDown = false end
	if altDown and not cursorHolding() then return end
	for _, v in pairs(views) do
		for _, b in ipairs(v.pool) do
			if b.alt then b.alt:Hide() end
		end
	end
end
local altWatch = CreateFrame("Frame")
altWatch:RegisterEvent("MODIFIER_STATE_CHANGED")
altWatch:SetScript("OnEvent", function(_, _, key)
	if key == "LALT" or key == "RALT" then refreshAltCovers() end
end)

-- The game's own bag button for this slot. A secure click on it is a normal
-- right-click: sell at a vendor, use a potion, or pick someone for a bandage.
-- At a banker that same click moves the item, because the button passes the
-- open bank. Named slots only exist for the old bag frames.
-- A bandage in this slot? (Consumable, subclass 7, or "Bandage" in its name.)
local function isBandageSlot(bag, slot)
	local info = C_Container and C_Container.GetContainerItemInfo and ns.safe(C_Container.GetContainerItemInfo, bag, slot)
	local id = type(info) == "table" and info.itemID
	if ns.isSecret(id) or type(id) ~= "number" then return false end
	local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	if getInstant then
		local _, _, _, _, _, classID, subID = ns.safe(getInstant, id)
		if not ns.isSecret(classID) and not ns.isSecret(subID) and classID == 0 and subID == 7 then return true end
	end
	local link = info.hyperlink
	if type(link) == "string" and not ns.isSecret(link) and link:lower():find("bandage", 1, true) then return true end
	return false
end

-- At a banker, a right-click moves the item. The game's own slot button does
-- that (into the bank from your bags, out of the bank from a bank slot). Our
-- use button would use or equip it instead.
local function bankVisit()
	local f = _G.BankFrame
	if not f or not f.IsShown then return false end
	local shown = f:IsShown()
	if ns.isSecret(shown) or not shown then return false end
	return true
end
local function isBankBag(bag)
	if type(bag) ~= "number" then return false end
	if BANK_MAIN and bag == BANK_MAIN then return true end
	local last = NUM_BAG_SLOTS or 4
	if bag > last and not (HAS_REAGENT and bag == REAGENT_BAG) then return true end
	return false
end
local moveBySlot = {}
local moveStale = true
local function markMoveStale() moveStale = true end
local function plainID(v)
	if v == nil or ns.isSecret(v) then return nil end
	if type(v) == "number" then return v end
	return tonumber(v)
end
local function isFrame(v)
	return type(v) == "userdata" or type(v) == "table"
end
local function buttonBagSlot(btn)
	if not isFrame(btn) or not btn.Click then return end
	-- Combined-bag buttons keep the bag on an attribute. GetBagID() falls
	-- back to the parent frame, which is the same for every slot. Buttons
	-- are userdata, so a pool loop cannot treat them as tables.
	local bag = plainID(btn.bagID)
	if bag == nil and btn.GetAttribute then bag = plainID(btn:GetAttribute("bagid")) end
	if bag == nil and btn.GetBankTabID then
		local ok, id = pcall(btn.GetBankTabID, btn)
		if ok then bag = plainID(id) end
	end
	if bag == nil and btn.GetBagID then
		local ok, id = pcall(btn.GetBagID, btn)
		if ok then bag = plainID(id) end
	end
	local slot
	if btn.GetContainerSlotID then
		local ok, id = pcall(btn.GetContainerSlotID, btn)
		if ok then slot = plainID(id) end
	end
	if slot == nil and btn.GetID then slot = plainID(btn:GetID()) end
	-- Bag 0 is the backpack. Only a missing id is rejected.
	if bag == nil or slot == nil then return end
	return bag, slot
end
local function keepMoveButton(btn)
	local bag, slot = buttonBagSlot(btn)
	if bag == nil then return end
	moveBySlot[bag] = moveBySlot[bag] or {}
	moveBySlot[bag][slot] = btn
end
local function eachPooled(iter, state, index)
	if type(iter) ~= "function" then return end
	for a, b in iter, state, index do
		if isFrame(b) then keepMoveButton(b)
		elseif isFrame(a) then keepMoveButton(a) end
	end
end
local function scanMoveFrame(frame)
	if not frame then return end
	if frame.Items then
		for _, btn in ipairs(frame.Items) do keepMoveButton(btn) end
	end
	if frame.itemButtonPool and frame.itemButtonPool.EnumerateActive then
		local ok, iter, state, index = pcall(frame.itemButtonPool.EnumerateActive, frame.itemButtonPool)
		if ok then eachPooled(iter, state, index) end
	end
	if frame.EnumerateValidItems then
		local ok, iter, state, index = pcall(frame.EnumerateValidItems, frame)
		if ok then eachPooled(iter, state, index) end
	end
	if frame.GetChildren then
		for _, child in ipairs({ frame:GetChildren() }) do
			if child.GetObjectType and child:GetObjectType() == "Button" and (child.GetBankTabID or child.GetContainerSlotID or plainID(child.bagID) ~= nil or (child.GetAttribute and plainID(child:GetAttribute("bagid")) ~= nil)) then
				keepMoveButton(child)
			end
		end
	end
end
local function rebuildMoveButtons()
	wipe(moveBySlot)
	pcall(scanMoveFrame, ContainerFrameCombinedBags)
	for i = 1, (NUM_CONTAINER_FRAMES or 13) do
		pcall(scanMoveFrame, _G["ContainerFrame" .. i])
	end
	pcall(scanMoveFrame, BankFrame and BankFrame.BankPanel)
	pcall(scanMoveFrame, _G.BankPanel)
	moveStale = false
end
local function moveButton(bag, slot)
	if moveStale then rebuildMoveButtons() end
	local row = moveBySlot[bag]
	local btn = row and row[slot]
	if btn then return btn end
	if ContainerFrameUtil_GetItemButtonAndContainer then
		local ok, found = pcall(ContainerFrameUtil_GetItemButtonAndContainer, bag, slot)
		if ok and isFrame(found) and found.Click then return found end
	end
end

-- The use spell on a quest item. Using the necklace once it is worn opens the
-- quest. UseContainerItem never gets there when the item is also gear: that
-- call equips it. Casting this spell is that same use, from the bag.
local function questUseSpell(bag, slot)
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if type(info) ~= "table" then return nil end
	local id = info.itemID
	if ns.isSecret(id) or type(id) ~= "number" or not getSpell then return nil end
	local spell = select(1, ns.safe(getSpell, id))
	if (ns.isSecret(spell) or type(spell) ~= "string" or spell == "") and type(info.hyperlink) == "string" then
		spell = select(1, ns.safe(getSpell, info.hyperlink))
	end
	if ns.isSecret(spell) or type(spell) ~= "string" or spell == "" or spell:find("[\n;]") then
		if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
		return nil
	end
	return spell
end

local function itemEquippable(id)
	if ns.isSecret(id) or type(id) ~= "number" then return false end
	local fn = (C_Item and C_Item.IsEquippableItem) or IsEquippableItem
	if not fn then return false end
	local v = ns.safe(fn, id)
	-- Some builds return 1, not true. Either one means the item can be worn.
	return v and not ns.isSecret(v) and true or false
end

-- The game's own bag button for this slot. Its right-click is UseContainerItem.
-- That opens a quest on an item that is not gear. On gear it equips instead.
local function defaultBagButton(bag, slot)
	moveStale = true
	local g = moveButton(bag, slot)
	if isFrame(g) and not g.zydeBag then
		local gb, gs = buttonBagSlot(g)
		if gb == bag and gs == slot then return g end
	end
	for i = 1, (NUM_CONTAINER_FRAMES or 13) do
		local f = _G["ContainerFrame" .. i]
		local fname = f and f.GetName and f:GetName()
		if f and fname and f.GetID and plainID(f:GetID()) == bag then
			local b = _G[fname .. "Item" .. slot]
			if isFrame(b) and b.Click and not b.zydeBag then return b end
		end
	end
end

local function muteMouse(f)
	if not f then return end
	if f.EnableMouse then f:EnableMouse(false) end
	if f.SetMouseClickEnabled then f:SetMouseClickEnabled(false) end
	if f.SetMouseMotionEnabled then f:SetMouseMotionEnabled(false) end
end
local function muteTree(f, depth)
	muteMouse(f)
	if not f or not f.GetChildren or (depth or 0) > 6 then return end
	for _, child in ipairs({ f:GetChildren() }) do muteTree(child, (depth or 0) + 1) end
end

-- Keep each secure use-button over its slot. It is not a child of the bag
-- window, so the window itself does not become protected.
local function placeUse(b, active)
	local use = b.use
	if not use or InCombatLockdown() then return end
	if not active or b.empty or not b:IsShown() or not b:IsVisible() or cursorHolding() then
		use:Hide()
		if b.alt then b.alt:Hide() end
		if b.move then b.move:Hide() end
		return
	end
	local left, top = b:GetLeft(), b:GetTop()
	if ns.isSecret(left) or ns.isSecret(top) or type(left) ~= "number" or type(top) ~= "number" then return end
	if use.lx ~= left or use.ly ~= top then
		use.lx, use.ly = left, top
		use:ClearAllPoints()
		use:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	end
	local bag = b.bagID
	if type(bag) ~= "number" and b:GetParent() and b:GetParent().GetID then bag = b:GetParent():GetID() end
	local slot = b:GetID()
	if ns.isSecret(bag) or ns.isSecret(slot) or type(bag) ~= "number" or type(slot) ~= "number" then return end
	-- Alt-click (either mouse button) marks Perma. It has to sit above this
	-- right-click button, or the right-click eats it.
	local alt = b.alt
	local altDown = IsAltKeyDown()
	if ns.isSecret(altDown) then altDown = false end
	if alt then
		if altDown and not cursorHolding() and not b.empty then
			alt:ClearAllPoints()
			alt:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
			alt:SetFrameLevel((use:GetFrameLevel() or 1) + 10)
			alt:Show()
		elseif alt:IsShown() then
			alt:Hide()
		end
	end
	-- Bank, mailbox, and auction house each take the right-click themselves.
	-- The secure button would use or equip the item instead.
	local aimingNow = SpellCanTargetItem and SpellCanTargetItem()
	local move = b.move
	local atVendor = merchantOpen()
	local handToUs = bankVisit() or auctionHouseOpen() or sendMailOpen()
	if not atVendor and handToUs and not aimingNow then
		use.itemKey = nil
		use:Hide()
		if move then
			move:ClearAllPoints()
			move:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
			move:SetFrameLevel(500)
			move:Show()
		end
		if alt and alt:IsShown() then alt:SetFrameLevel(510) end
		return
	end
	if move and move:IsShown() then move:Hide() end
	-- Right-click uses the slot itself through this secure button (food, drink, scrolls,
	-- potions; at a vendor that sells it). Only a bandage goes through the game's own slot
	-- button, so you can pick who it heals - and only when that button is on screen and is
	-- this very slot. (Every right-click went to the game's button before, found as
	-- ContainerFrame<bag+1>Item<slot>: those frames aren't tied to bags that way, and with
	-- this window they're never opened, so the click landed on a hidden, stale button and
	-- nothing was used.)
	local game
	if not atVendor and isBandageSlot(bag, slot) then
		local g = moveButton(bag, slot)
		if g and g.IsVisible and g:IsVisible() then
			local gb, gs = buttonBagSlot(g)
			if gb == bag and gs == slot then game = g end
		end
	end
	local where = bag .. " " .. slot
	-- The secure button over this slot (b.use) was the one equipping the
	-- pendant. Its right-click is type2. For a normal item that is "item",
	-- and the secure item action equips anything that can be worn before it
	-- ever uses it. Pendant of Myzrael took that path: the use spell was not
	-- what ran, and type2 stayed "item". A startsQuest item never keeps an
	-- item action. Right-click goes to the game's own bag button, whose
	-- right-click is UseContainerItem (the quest opens, the necklace stays
	-- in the bag). No game button: the click does nothing, and it does not equip.
	local wantQuest = not atVendor and not game and startsQuest(bag, slot)
	if not wantQuest and not atVendor and not game then
		-- Equippable quest items still equip if the "begins a quest" line was
		-- not loaded yet. The container marks those, and the secure item
		-- action must not get the click.
		local q = questRecord(bag, slot)
		local info = C_Container.GetContainerItemInfo(bag, slot)
		local id = type(info) == "table" and info.itemID
		if type(q) == "table" and q.isQuestItem and not q.isActive and itemEquippable(id) then
			wantQuest = true
		end
	end
	-- Default bags right-click this slot and UseContainerItem runs. That starts
	-- the quest and does not equip. The secure button over the slot was the one
	-- equipping Pendant of Myzrael (type2=item), or eating the click when it
	-- forwarded to a hidden bag button and nothing happened. Step off the slot
	-- and give the click back to the template.
	if wantQuest and b.origClick then
		if b:GetScript("OnClick") ~= b.origClick then
			b:SetScript("OnClick", b.origClick)
		end
		use.itemKey = nil
		use.clickMode = nil
		use.potClicks = nil
		use:SetAttribute("type", nil)
		use:SetAttribute("*type", nil)
		use:SetAttribute("type1", nil)
		use:SetAttribute("*type1", nil)
		use:SetAttribute("type2", nil)
		use:SetAttribute("*type2", nil)
		use:SetAttribute("item", nil)
		use:SetAttribute("*item", nil)
		use:SetAttribute("item1", nil)
		use:SetAttribute("*item1", nil)
		use:SetAttribute("item2", nil)
		use:SetAttribute("*item2", nil)
		use:SetAttribute("spell1", nil)
		use:SetAttribute("*spell1", nil)
		use:SetAttribute("spell2", nil)
		use:SetAttribute("*spell2", nil)
		if use:IsShown() then use:Hide() end
		return
	end
	if b.wrappedClick and b:GetScript("OnClick") ~= b.wrappedClick then
		b:SetScript("OnClick", b.wrappedClick)
	end
	local questSpell = wantQuest and questUseSpell(bag, slot) or nil
	local questGear = false
	if wantQuest and not questSpell then
		local info = C_Container.GetContainerItemInfo(bag, slot)
		questGear = info and itemEquippable(info.itemID) or false
	end
	local questClick = wantQuest and defaultBagButton(bag, slot) or nil
	local questBtn = (wantQuest and not questSpell and not questGear) and questClick or nil
	local quest = (questSpell or questClick or questGear) and true or false
	if wantQuest and b.SetAttribute then
		-- The slot itself is a ContainerFrameItemButton. If it still has a
		-- secure item action, a right-click that reaches it equips the gear.
		b:SetAttribute("type", nil)
		b:SetAttribute("*type", nil)
		b:SetAttribute("type2", nil)
		b:SetAttribute("*type2", nil)
		b:SetAttribute("item", nil)
		b:SetAttribute("*item", nil)
		b:SetAttribute("item2", nil)
		b:SetAttribute("*item2", nil)
	end
	local key = where .. (game and " game" or (atVendor and " vendor" or (questClick and " questclick" or (wantQuest and " quest" or " item"))))
	if use.itemKey ~= key then
		use.itemKey = key
		use:SetAttribute("type", nil)
		use:SetAttribute("*type", nil)
		use:SetAttribute("item", nil)
		use:SetAttribute("*item", nil)
		use:SetAttribute("item2", nil)
		use:SetAttribute("*item2", nil)
		use:SetAttribute("item1", nil)
		use:SetAttribute("*item1", nil)
		use:SetAttribute("spell2", nil)
		use:SetAttribute("*spell2", nil)
		use:SetAttribute("clickbutton2", nil)
		use:SetAttribute("*clickbutton2", nil)
		use:SetAttribute("macrotext2", nil)
		use:SetAttribute("*macrotext2", nil)
		-- Left click while a spell wants an item (Feed Pet, a stone, a poison).
		use:SetAttribute("item1", where)
		use:SetAttribute("*item1", where)
		if game then
			-- The game's own slot. At the auction house it lists, and a bandage
			-- lets you pick a person.
			use:SetAttribute("forward", true)
			use:SetAttribute("type2", "click")
			use:SetAttribute("*type2", "click")
			use:SetAttribute("clickbutton2", game)
			use:SetAttribute("*clickbutton2", game)
		elseif atVendor then
			use:SetAttribute("forward", nil)
			use:SetAttribute("type2", "macro")
			use:SetAttribute("*type2", "macro")
			use:SetAttribute("macrotext2", "/use " .. where)
			use:SetAttribute("*macrotext2", "/use " .. where)
		elseif questClick then
			use:SetAttribute("forward", nil)
			use:SetAttribute("type2", "click")
			use:SetAttribute("*type2", "click")
			use:SetAttribute("clickbutton2", questClick)
			use:SetAttribute("*clickbutton2", questClick)
		elseif wantQuest then
			use:SetAttribute("forward", nil)
			use:SetAttribute("type2", nil)
			use:SetAttribute("*type2", nil)
		else
			-- Right click only. A bare "type" would also fire if a left click landed here.
			use:SetAttribute("forward", nil)
			use:SetAttribute("type2", "item")
			use:SetAttribute("*type2", "item")
			use:SetAttribute("item2", where)
			use:SetAttribute("*item2", where)
		end
	end
	-- A spell waiting for an item (Feed Pet, a sharpening stone, a poison, Disenchant): the
	-- left-click on the item has to be the secure button's too. Through the slot's own click
	-- it's addon code, and the game forbids it ("was blocked calling UseContainerItem()").
	-- A quest starter's left click still casts that use when the item has one.
	-- The right click is the game bag button (type2 above), not this left click.
	local aiming = SpellCanTargetItem and SpellCanTargetItem() and true or false
	local mode = (aiming and "aim:" or (questSpell and ("spell:" .. questSpell) or (quest and "quest:" or "norm:"))) .. where
	if use.clickMode ~= mode then
		use.clickMode = mode
		use:SetAttribute("macrotext1", nil)
		use:SetAttribute("*macrotext1", nil)
		use:SetAttribute("clickbutton1", nil)
		use:SetAttribute("*clickbutton1", nil)
		use:SetAttribute("spell1", nil)
		use:SetAttribute("*spell1", nil)
		if aiming then
			use:SetAttribute("type1", "item")
			use:SetAttribute("*type1", "item")
			use:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonDown", "RightButtonUp")
			if use.SetPassThroughButtons then use:SetPassThroughButtons("MiddleButton") end
		elseif questSpell then
			use:SetAttribute("type1", "spell")
			use:SetAttribute("*type1", "spell")
			use:SetAttribute("spell1", questSpell)
			use:SetAttribute("*spell1", questSpell)
			use:RegisterForClicks("LeftButtonUp", "RightButtonDown", "RightButtonUp")
			if use.SetPassThroughButtons then use:SetPassThroughButtons("MiddleButton") end
		elseif questBtn then
			local clickName = questBtn.GetName and questBtn:GetName()
			if type(clickName) ~= "string" or clickName == "" then
				clickName = "ZydeForeverBagQuestClick"
				_G[clickName] = questBtn
			end
			use:SetAttribute("type1", "macro")
			use:SetAttribute("*type1", "macro")
			use:SetAttribute("macrotext1", "/click " .. clickName .. " RightButton")
			use:SetAttribute("*macrotext1", "/click " .. clickName .. " RightButton")
			use:RegisterForClicks("LeftButtonUp", "RightButtonDown", "RightButtonUp")
			if use.SetPassThroughButtons then use:SetPassThroughButtons("MiddleButton") end
		elseif quest then
			-- Equippable quest item, spell not loaded yet. Hold the click so it
			-- does not equip. The next refresh casts the use once the spell is known.
			use:SetAttribute("type1", nil)
			use:SetAttribute("*type1", nil)
			use:RegisterForClicks("LeftButtonUp", "RightButtonDown", "RightButtonUp")
			if use.SetPassThroughButtons then use:SetPassThroughButtons("MiddleButton") end
		else
			use:SetAttribute("type1", nil)
			use:SetAttribute("*type1", nil)
			use:RegisterForClicks("RightButtonDown", "RightButtonUp")
			if use.SetPassThroughButtons then use:SetPassThroughButtons("LeftButton", "MiddleButton") end
		end
	end
	-- A quest setup registers RightButtonUp only and stops passing Left through.
	-- On a health pot that leaves the mouse-down to the slot, and the slot
	-- swallows it, so the pot never runs. In a fight placeUse cannot fix that.
	-- Re-assert the pot click whenever this slot is not a quest starter.
	-- A quest starter never gets type2=item back: that action equips the pendant.
	if not wantQuest and not game and not atVendor and not aiming then
		if use:GetAttribute("type2") ~= "item" then
			use:SetAttribute("forward", nil)
			use:SetAttribute("type", nil)
			use:SetAttribute("*type", nil)
			use:SetAttribute("type2", "item")
			use:SetAttribute("*type2", "item")
			use:SetAttribute("spell2", nil)
			use:SetAttribute("*spell2", nil)
			use:SetAttribute("clickbutton2", nil)
			use:SetAttribute("*clickbutton2", nil)
			use:SetAttribute("item2", where)
			use:SetAttribute("*item2", where)
		end
		if use.potClicks ~= true then
			use.potClicks = true
			use:RegisterForClicks("RightButtonDown", "RightButtonUp")
			if use.SetPassThroughButtons then use:SetPassThroughButtons("LeftButton", "MiddleButton") end
		end
	else
		use.potClicks = nil
	end
	if use:GetFrameStrata() ~= "DIALOG" then use:SetFrameStrata("DIALOG") end
	local lvl = (b:GetFrameLevel() or 1) + 20
	if use:GetFrameLevel() ~= lvl then use:SetFrameLevel(lvl) end
	use:Show()
end
local function refreshUses()
	if InCombatLockdown() then return end
	local open = false
	for _, v in pairs(views) do
		if v.win and v.win:IsShown() then open = true break end
	end
	if not open then
		for _, v in pairs(views) do
			for _, b in ipairs(v.pool) do
				if b.use and b.use:IsShown() then b.use:Hide() end
				if b.move and b.move:IsShown() then b.move:Hide() end
			end
		end
		return
	end
	local bankWin = _G.ZydeForeverBank
	if bankWin and bankWin:IsShown() and _G.BankFrame then muteTree(_G.BankFrame, 0) end
	for _, v in pairs(views) do
		local n = v.used or 0
		local shown = v.win and v.win:IsShown()
		for i, b in ipairs(v.pool) do
			placeUse(b, shown and i <= n)
		end
	end
end
altWatch:SetScript("OnUpdate", function()
	refreshUses()
	-- The split box can open without the cursor changing. Show the drop slot then too.
	local split = StackSplitFrame and StackSplitFrame:IsShown() and true or false
	if split ~= altWatch.splitOpen then
		altWatch.splitOpen = split
		for _, v in pairs(views) do
			if v.SyncDropSlot then v:SyncDropSlot() end
		end
	end
end)

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
	h.fold = function(btn)
		if InCombatLockdown() then return end
		collapsed()[btn.section] = not collapsed()[btn.section] or nil
		for _, v in pairs(views) do v.dirty = true end
		view:Layout()
		if ns.RefreshBankMemory then ns.RefreshBankMemory() end
	end
	armFold(h)
	self.heads[i] = h
	return h
end

local function paintImportance(b, itemID)
	local n = bagOrderOn() and ns.BagMark(itemID)
	local m = n and MARKS[n]
	if not m then
		if b.impEdge then for _, t in ipairs(b.impEdge) do t:Hide() end end
		return
	end
	if not b.impEdge then
		b.impEdge = ns.newEdges(b, "OVERLAY", 6)
		ns.placeEdges(b.impEdge, b, 0, 2)
	end
	for _, t in ipairs(b.impEdge) do
		t:SetColorTexture(m.r, m.g, m.b, 1)
		t:Show()
	end
end

local function bagCaption(bag)
	if bag == 0 then return "Backpack" end
	if isKeyring(bag) then return "Keys" end
	if HAS_REAGENT and bag == REAGENT_BAG then return "Reagent" end
	if BANK_MAIN and bag == BANK_MAIN then return "Bank" end
	local inv = invSlot(bag)
	local name = inv and GetInventoryItemName and GetInventoryItemName("player", inv)
	if type(name) == "string" and not ns.isSecret(name) and name ~= "" then return name end
	if isBankBag(bag) then return "Bank bag" end
	return "Bag " .. tostring(bag)
end

-- "12/16": filled slots over how many the bag holds. An empty slot is unused.
local function slotCountText(bag)
	local n = numSlots(bag)
	if n <= 0 then return nil end
	local free = plainNum(C_Container.GetContainerNumFreeSlots(bag))
	return math.max(0, n - free) .. "/" .. n
end
local function bagCountLabel(bag)
	local fill = slotCountText(bag)
	if not fill then return bagCaption(bag) end
	return bagCaption(bag) .. "  " .. fill
end

function View:Paint(b)
	local parent = b:GetParent()
	local bag = parent and parent.GetID and parent:GetID()
	local slot = b:GetID()
	-- Bag 0 is the backpack. A truthiness check would skip it.
	local info
	if type(bag) == "number" and type(slot) == "number" then
		info = C_Container.GetContainerItemInfo(bag, slot)
	end
	-- A drag clears the icon, and the button can still be marked empty from
	-- the last layout. Read the slot itself so a drop shows what landed.
	if info and ns.isSecret(info) then return end
	local hasItem = info and info.itemID and not ns.isSecret(info.itemID)
	if not hasItem then
		setNew(b, false)
		setBang(b, false)
		setMarks(b, nil)
		local tex = b.emptyTex
		if b.realSlot and not tex and type(bag) == "number" then
			local _, fam = C_Container.GetContainerNumFreeSlots(bag)
			tex = emptyTexture(bag, isOrdinaryBag(bag, plainNum(fam)))
		end
		SetItemButtonTexture(b, (b.empty or b.realSlot) and tex or nil)
		SetItemButtonCount(b, b.empty and b.emptyCount or 0)
		SetItemButtonDesaturated(b, false)
		if SetItemButtonQuality then pcall(SetItemButtonQuality, b, nil) end
		if b.cd then b.cd:Hide() end
		paintImportance(b, nil)
		if b.countText then
			if b.realSlot or not b.emptyOrdinary then b.countText:SetTextColor(1, 1, 1)
			else b.countText:SetTextColor(freeColor(b.emptyCount)) end
		end
		b:SetAlpha(1)
		return
	end
	if b.countText then b.countText:SetTextColor(1, 1, 1) end
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
	paintImportance(b, info.itemID)
end

function View:Repaint()
	for i = 1, self.used do self:Paint(self.pool[i]) end
end

function View:SetTitle()
	local r, g, bl = freeColor(self.free or 0)
	local free = usageLabel(self.free or 0, self.slots or 0)
	-- "30 free  ·  12 reagent": special bags after the ordinary count, in gray.
	local more = {}
	for _, kind in ipairs({ "reagent", "ammo", "soul", "special" }) do
		local n = self.extraFree and self.extraFree[kind]
		-- (a full quiver or ammo pouch is normal: only bags with room are listed)
		if n and n > 0 then more[#more + 1] = n .. " " .. kind end
	end
	local tail = #more > 0 and ("  |cff888888· " .. table.concat(more, " · ") .. "|r") or ""
	if type(self.tabNote) == "string" and self.tabNote ~= "" then
		tail = tail .. "  |cff888888·  " .. self.tabNote .. "|r"
	end
	self.win.title:SetText(self.titleText .. string.format("  |cff%02x%02x%02x%s|r", r * 255, g * 255, bl * 255, free) .. tail)
end

function View:ContentTop()
	local row = 0
	if self.bagRowShown and self.bagRowShown() then row = (self.bagRowHeight or S) + 8 end
	return 34 + row
end

local specialMoves
function View:Layout()
	if InCombatLockdown() then self.dirty = true return end
	self.dirty = false
	local data, free, extra, reserve, slots, saved = gather(self.bags(), self.stackKey)
	if self.omitKeys and self.omitKeys() and data.General then data.General.Keys = nil end
	self.free, self.extraFree, self.slots = free, extra, slots
	self:SetTitle()
	-- "Restack +3": slots a click would free, from joining stacks and from
	-- moving an item into the special bag that takes it.
	local rb = self.win.restackBtn
	if rb then
		local n = (saved or 0) + specialMoves(self.bags())
		-- (nothing to free: no button; the ones after it close the gap)
		if n > 0 then rb:SetText("Restack +" .. n) rb:Show() else rb:Hide() end
		self.win.Flow()
	end
	local used, labelUsed, headUsed = 0, 0, 0
	local y = 0
	local content = self.win.content
	-- Bag order: each bag's own slots, empties included, no sections and no
	-- sort. A later layout reads the bags again, so a drag stays where it landed.
	local plain = bagOrderOn() and (self.stackKey == "bags" or self.stackKey == "bank")
	if plain then
		for _, bag in ipairs(self.bags()) do
			local n = numSlots(bag)
			if n > 0 then
				local _, fam = C_Container.GetContainerNumFreeSlots(bag)
				local ordinary = isOrdinaryBag(bag, tonumber(fam) or 0)
				local tex = emptyTexture(bag, ordinary)
				labelUsed = labelUsed + 1
				local l = self:Label(labelUsed)
				l:ClearAllPoints()
				l:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
				l:SetWidth(INNER_W)
				l:SetText(self.stackKey == "bags" and bagCountLabel(bag) or bagCaption(bag))
				l:Show()
				for slot = 1, n do
					used = used + 1
					local info = C_Container.GetContainerItemInfo(bag, slot)
					local filled = info and info.itemID and not ns.isSecret(info.itemID)
					local b = self:Button(used)
					b:SetParent(self:Holder(bag))
					b:SetFrameLevel((self.win:GetFrameLevel() or 1) + 4)
					b:SetID(slot)
					b.bagID = bag
					b.realSlot = true
					b.empty = not filled
					if filled then
						b.emptyTex, b.emptyCount, b.emptyOrdinary = nil, nil, nil
						b.slots = { { bag = bag, slot = slot } }
						b.perma = ns.IsPerma(info.itemID)
					else
						b.emptyTex, b.emptyCount, b.emptyOrdinary = tex, 0, ordinary
						b.slots = nil
						b.perma = false
					end
					local col, row = (slot - 1) % COLS, math.floor((slot - 1) / COLS)
					b:ClearAllPoints()
					b:SetPoint("TOPLEFT", content, "TOPLEFT", col * (S + GAP), -(y + LABEL_H + row * (S + GAP)))
					b:Show()
					self:Paint(b)
				end
				local rows = math.ceil(n / COLS)
				y = y + LABEL_H + rows * (S + GAP) - GAP + 10
			end
		end
	else
	-- Categorized bags have no per-bag heading. A short line still names the
	-- backpack and each equipped bag, with used/capacity beside it.
	if self.stackKey == "bags" then
		local x, placed = 0, false
		for _, bag in ipairs(self.bags()) do
			if numSlots(bag) > 0 and not isKeyring(bag) and (bag == 0 or isEquippedBag(bag)) then
				labelUsed = labelUsed + 1
				local l = self:Label(labelUsed)
				l:SetText(bagCountLabel(bag))
				local w = math.max(40, math.ceil(l:GetStringWidth() or 0) + 14)
				if x > 0 and x + w > INNER_W then
					x = 0
					y = y + LABEL_H
				end
				l:ClearAllPoints()
				l:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
				l:SetWidth(math.min(w, INNER_W))
				l:Show()
				x = x + w
				placed = true
			end
		end
		if placed then y = y + LABEL_H + 6 end
	end
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
						-- (a moved button keeps its old level: put it back above the window,
						-- or it draws under the window's background, faded and unclickable)
						b:SetFrameLevel((self.win:GetFrameLevel() or 1) + 4)
						b:SetID(e.slot)
						b.bagID = e.bag
						b.empty = e.empty
						b.emptyTex, b.emptyCount, b.emptyOrdinary = e.tex, e.count, e.ordinary
						b.slots = e.slots
						b.perma = not e.empty and ns.IsPerma(e.info and e.info.itemID)
						b.realSlot = false
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
	end
	-- Bottom left, only while dragging or splitting: a New Item header and one
	-- real free slot. Bag order already shows every empty slot, so it has no
	-- pinned drop slot. Kept in the pool either way so a fight can show it
	-- without laying the window out again.
	self.baseY = y
	self.reserve = plain and nil or reserve
	if reserve and not plain then
		local h = self:DropHead()
		h:ClearAllPoints()
		h:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
		used = used + 1
		local b = self:Button(used)
		b:SetParent(self:Holder(reserve.bag))
		b:SetFrameLevel((self.win:GetFrameLevel() or 1) + 4)
		b:SetID(reserve.slot)
		b.bagID = reserve.bag
		b.empty = true
		b.emptyTex, b.emptyCount, b.emptyOrdinary = reserve.tex, reserve.count, reserve.ordinary
		b.slots = nil
		b.perma = false
		b.realSlot = false
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(y + HEAD_H))
		self:Paint(b)
		self.dropButton = b
		local show = wantDropSlot()
		h:SetShown(show)
		b:SetShown(show)
		if show then y = y + HEAD_H + S end
	else
		if self.dropHead then self.dropHead:Hide() end
		self.dropButton = nil
	end
	self.used = used
	for i = used + 1, #self.pool do self.pool[i]:Hide() end
	for i = labelUsed + 1, #self.labels do self.labels[i]:Hide() end
	for i = headUsed + 1, #self.heads do self.heads[i]:Hide() end
	content:SetHeight(math.max(10, y))
	self.win:SetHeight(y + self:ContentTop() + 2 + 34 + PAD)
	refreshAltCovers()
	refreshUses()
end

-- "New Item" is not a folding section. It only labels the drop slot.
function View:DropHead()
	if self.dropHead then return self.dropHead end
	local h = CreateFrame("Frame", nil, self.win.content)
	h:SetSize(INNER_W, HEAD_H - 4)
	h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	h.text:SetPoint("LEFT", 0, 0)
	h.text:SetText("New Item")
	h.line = h:CreateTexture(nil, "ARTWORK")
	h.line:SetColorTexture(1, 0.82, 0, 0.25)
	h.line:SetHeight(1)
	h.line:SetPoint("LEFT", h.text, "RIGHT", 8, 0)
	h.line:SetPoint("RIGHT")
	h:Hide()
	self.dropHead = h
	return h
end

-- Show or hide the drop row without sorting again. Safe in a fight: the row
-- was already built, and this frame is not protected.
function View:SyncDropSlot()
	if not self.win or not self.win:IsShown() then return end
	if not self.dropButton or not self.reserve then return end
	local show = wantDropSlot()
	if self.dropHead:IsShown() == show and self.dropButton:IsShown() == show then return end
	self.dropHead:SetShown(show)
	self.dropButton:SetShown(show)
	local y = self.baseY or 0
	if show then y = y + HEAD_H + S end
	self.win.content:SetHeight(math.max(10, y))
	self.win:SetHeight(y + self:ContentTop() + 2 + 34 + PAD)
	if not InCombatLockdown() then refreshUses() end
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
		return
	end
	-- First open sits on the left of the bag window. A drag saves bankPos,
	-- and that spot is used from then on.
	local bags = self.posKey == "bankPos" and _G.ZydeForeverBags
	if bags then
		w:SetPoint("TOPRIGHT", bags, "TOPLEFT", -8, 0)
		return
	end
	w:SetPoint(unpack(self.defaultPoint))
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
	-- Above the reminder icons (which sit in HIGH), so a reminder by your
	-- character never draws on top of your bags.
	win:SetFrameStrata("HIGH")
	win:SetFrameLevel(60)
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
-- Restack. Joins part stacks (two stacks of 12 linen become one of 24), and
-- moves an item into the special bag that accepts it when that bag has a
-- free slot: a reagent in the backpack, with room in the reagent bag.
-- One move at a time, out of combat.
---------------------------------------------------------------------------
local function itemFamily(itemID)
	if ns.isSecret(itemID) or type(itemID) ~= "number" then return nil end
	local fam
	if C_Item and C_Item.GetItemFamily then fam = ns.safe(C_Item.GetItemFamily, itemID)
	elseif GetItemFamily then fam = ns.safe(GetItemFamily, itemID) end
	if ns.isSecret(fam) or type(fam) ~= "number" then return nil end
	return fam
end

local function fitsSpecial(itemFam, bagFam)
	if not itemFam or itemFam == 0 or not bagFam or bagFam == 0 then return false end
	if not bit or not bit.band then return false end
	return bit.band(itemFam, bagFam) ~= 0
end

-- The reagent bag takes an item the game has marked as a crafting reagent,
-- and only when that item also matches the bag's own family (an herb bag in
-- that slot still refuses cloth). Class 5 is wider than that mark, and item
-- family alone is wider still. Either one was enough for the bag to refuse
-- the move. nil means the item is not loaded yet, so a sort must not try it.
local function markedReagent(id)
	if not id or ns.isSecret(id) or type(id) ~= "number" then return false end
	if C_Item and C_Item.IsItemCraftingReagent then
		local ok, v = pcall(C_Item.IsItemCraftingReagent, id)
		if ok and v and not ns.isSecret(v) then return true end
	end
	local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	if not get then return nil end
	local ok, name, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, reagent = pcall(get, id)
	if not ok then return nil end
	if name == nil or ns.isSecret(name) then
		if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
		return nil
	end
	if ns.isSecret(reagent) then return nil end
	return reagent and true or false
end

function canEnterReagentBag(id)
	local marked = markedReagent(id)
	if marked == nil then return nil end
	if not marked or not HAS_REAGENT then return false end
	local _, bagFam = C_Container.GetContainerNumFreeSlots(REAGENT_BAG)
	bagFam = plainNum(bagFam)
	if bagFam == 0 then return true end
	return fitsSpecial(itemFamily(id), bagFam)
end

local function bagFamilies(bags)
	local fam = {}
	for _, bag in ipairs(bags) do
		local _, f = C_Container.GetContainerNumFreeSlots(bag)
		if ns.isSecret(f) or type(f) ~= "number" then f = 0 end
		fam[bag] = f
	end
	return fam
end

local function freeSlot(bag)
	for slot = 1, numSlots(bag) do
		if not slotTaken(bag, slot) then return slot end
	end
end

-- The bank window is ours, so a right-click cannot ask the game's bag slot to
-- move the item. Pick it up and put it down on the other side, the same move
-- Restack uses. One stack per click: the slot this tile actually is.
function transferAtBank(b)
	if not bankVisit() then return false end
	if MerchantFrame and MerchantFrame:IsShown() then return false end
	if auctionHouseOpen() then return false end
	if cursorHolding() or b.empty then return true end
	local bag = b.bagID
	if type(bag) ~= "number" and b.GetParent and b:GetParent() and b:GetParent().GetID then
		bag = b:GetParent():GetID()
	end
	local slot = b.GetID and b:GetID()
	if ns.isSecret(bag) or ns.isSecret(slot) or type(bag) ~= "number" or type(slot) ~= "number" then return true end
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if ns.isSecret(info) or type(info) ~= "table" or ns.isSecret(info.itemID) or type(info.itemID) ~= "number" then return true end
	if not ns.isSecret(info.isLocked) and info.isLocked then return true end
	local intoBank = not isBankBag(bag)
	local dests = intoBank and bankBags() or myBags()
	local id = info.itemID
	local count = info.stackCount
	if ns.isSecret(count) or type(count) ~= "number" then count = 1 end
	local max = stackSize(id) or count
	local destBag, destSlot
	if max > count then
		for _, dst in ipairs(dests) do
			if not isKeyring(dst) then
				for s = 1, numSlots(dst) do
					local other = C_Container.GetContainerItemInfo(dst, s)
					local oid = type(other) == "table" and other.itemID
					local locked = false
					if type(other) == "table" and not ns.isSecret(other.isLocked) and other.isLocked then locked = true end
					if not ns.isSecret(oid) and oid == id and not locked then
						local n = other.stackCount
						if ns.isSecret(n) or type(n) ~= "number" then n = 1 end
						if n < max then
							destBag, destSlot = dst, s
							break
						end
					end
				end
			end
			if destBag then break end
		end
	end
	if not destBag then
		local kind = itemFamily(id)
		local best = 0
		for _, dst in ipairs(dests) do
			if not isKeyring(dst) then
				local _, fam = C_Container.GetContainerNumFreeSlots(dst)
				fam = plainNum(fam)
				local rank = 0
				if not (HAS_REAGENT and dst == REAGENT_BAG and canEnterReagentBag(id) ~= true) then
					rank = (fam == 0 and 1) or (fitsSpecial(kind, fam) and 2) or 0
				end
				if rank > best then
					local s = freeSlot(dst)
					if s then destBag, destSlot, best = dst, s, rank end
				end
			end
		end
	end
	if not destBag then
		print(P .. (intoBank and "the bank is full" or "your bags are full"))
		return true
	end
	C_Container.PickupContainerItem(bag, slot)
	if not cursorHolding() then
		print(P .. "that item didn't move")
		return true
	end
	C_Container.PickupContainerItem(destBag, destSlot)
	if cursorHolding() then
		C_Container.PickupContainerItem(bag, slot)
		print(P .. "that item can't go there")
	end
	return true
end

-- How many items would move into a special bag that has room for them.
function specialMoves(bags)
	local fam = bagFamilies(bags)
	local room = {}
	for _, bag in ipairs(bags) do
		if not isKeyring(bag) and fam[bag] ~= 0 then
			local free = plainNum(C_Container.GetContainerNumFreeSlots(bag))
			if free > 0 then room[bag] = free end
		end
	end
	if not next(room) then return 0 end
	local n = 0
	for _, bag in ipairs(bags) do
		if not isKeyring(bag) then
			for slot = 1, numSlots(bag) do
				local info = C_Container.GetContainerItemInfo(bag, slot)
				local id = info and info.itemID
				if id and not ns.isSecret(id) and not fitsSpecial(itemFamily(id), fam[bag]) then
					local kind = itemFamily(id)
					for dst, left in pairs(room) do
						local reagentOk = not (HAS_REAGENT and dst == REAGENT_BAG) or canEnterReagentBag(id) == true
						if left > 0 and reagentOk and fitsSpecial(kind, fam[dst]) then
							room[dst] = left - 1
							n = n + 1
							break
						end
					end
				end
			end
		end
	end
	return n
end

-- Bag order Restack. Same category order as the sorted bag view. Only an item
-- the reagent bag will accept goes there, and only while it has room. Everything
-- else packs from the backpack forward, so empty slots are the last slots and a
-- later bag can be empty.
local function orderMove(bags, refused)
	refused = refused or {}
	local fam = bagFamilies(bags)
	local reagentBag
	if HAS_REAGENT and numSlots(REAGENT_BAG) > 0 then reagentBag = REAGENT_BAG end
	local function readItem(bag, slot)
		local info = C_Container.GetContainerItemInfo(bag, slot)
		if not info or ns.isSecret(info) or not info.itemID or ns.isSecret(info.itemID) then return nil end
		local n = info.stackCount
		if ns.isSecret(n) or type(n) ~= "number" then n = 1 end
		if info.isLocked then return "locked" end
		info.bag, info.slot = bag, slot
		local q = info.quality
		return {
			bag = bag, slot = slot, id = info.itemID, n = n, info = info,
			name = nameOf(info),
			q = (not ns.isSecret(q) and type(q) == "number") and q or 0,
		}
	end
	local function sig(id, n) return id .. ":" .. n end
	local normal, reagentSlots, items = {}, {}, {}
	for _, bag in ipairs(bags) do
		if not isKeyring(bag) then
			local isReagent = reagentBag and bag == reagentBag
			if isReagent or (fam[bag] or 0) == 0 then
				local slots = isReagent and reagentSlots or normal
				for slot = 1, numSlots(bag) do
					slots[#slots + 1] = { bag = bag, slot = slot }
					local it = readItem(bag, slot)
					if it == "locked" then return "locked" end
					if it then items[#items + 1] = it end
				end
			end
		end
	end
	local groups = {}
	for _, sec in ipairs(SECTIONS) do groups[sec] = {} end
	for _, it in ipairs(items) do
		local sec, group = categorize(it.info)
		if sec == "Gear" and (group == "Weapons" or group == "Armor") then
			local c = scan(it.bag, it.slot, it.info)
			if c and c.upgrade ~= nil and not c.red then sec = "Upgrades" end
		end
		groups[sec][group] = groups[sec][group] or {}
		table.insert(groups[sec][group], it)
	end
	local ordered = {}
	for _, sec in ipairs(SECTIONS) do
		for _, list in pairs(groups[sec]) do
			table.sort(list, function(a, b)
				if a.q ~= b.q then return a.q > b.q end
				if a.name ~= b.name then return a.name < b.name end
				if a.id ~= b.id then return a.id < b.id end
				return a.n > b.n
			end)
		end
		for _, g in ipairs(groupOrder(sec, groups[sec])) do
			for _, it in ipairs(groups[sec][g]) do ordered[#ordered + 1] = it end
		end
	end
	local reagentItems, normalItems, room = {}, {}, #reagentSlots
	for _, it in ipairs(ordered) do
		if room > 0 and canEnterReagentBag(it.id) == true and not refused[it.id] then
			room = room - 1
			reagentItems[#reagentItems + 1] = it
		else
			normalItems[#normalItems + 1] = it
		end
	end
	local dests = {}
	local function add(slots, list)
		for i, slot in ipairs(slots) do
			local it = list[i]
			dests[#dests + 1] = { bag = slot.bag, slot = slot.slot, sig = it and sig(it.id, it.n) or false }
		end
	end
	add(reagentSlots, reagentItems)
	add(normal, normalItems)
	local cur, at = {}, {}
	local function key(bag, slot) return bag .. ":" .. slot end
	for _, d in ipairs(dests) do
		local it = readItem(d.bag, d.slot)
		if it == "locked" then return "locked" end
		local s = it and sig(it.id, it.n) or false
		cur[key(d.bag, d.slot)] = s
		if s then
			at[s] = at[s] or {}
			at[s][#at[s] + 1] = { bag = d.bag, slot = d.slot }
		end
	end
	local satisfied = {}
	for _, d in ipairs(dests) do
		local k = key(d.bag, d.slot)
		if cur[k] == d.sig then satisfied[k] = true end
	end
	for _, d in ipairs(dests) do
		local k = key(d.bag, d.slot)
		if not satisfied[k] then
			if not d.sig then
				local here = cur[k]
				if here then
					for _, other in ipairs(dests) do
						local ok = key(other.bag, other.slot)
						if other.sig == here and not satisfied[ok] then
							return { d.bag, d.slot, other.bag, other.slot }
						end
					end
				end
			else
				local list = at[d.sig]
				if list then
					for _, src in ipairs(list) do
						local sk = key(src.bag, src.slot)
						if sk ~= k and not satisfied[sk] then
							return { src.bag, src.slot, d.bag, d.slot }
						end
					end
				end
			end
		end
	end
end

local restacking = false
local function restack(bags)
	if restacking then return end
	if InCombatLockdown() then print(P .. "can't restack during a fight") return end
	if GetCursorInfo() then print(P .. "put down what's on the cursor first") return end
	restacking = true
	local moves, tries, lastKey = 0, 0, nil
	local refused = {}
	local function finish(msg)
		restacking = false
		print(P .. msg)
	end
	local function step()
		tries = tries + 1
		if tries > 400 then finish("restack stopped (took too long)") return end
		if InCombatLockdown() then finish("restack stopped for the fight") return end
		local fam = bagFamilies(bags)
		local packing = false
		if bagOrderOn() then
			for _, bag in ipairs(bags) do
				if bag == 0 then packing = true break end
			end
		end
		local function rank(bag, kind, id)
			-- A part stack the reagent bag will not take must not join into it.
			if HAS_REAGENT and bag == REAGENT_BAG and canEnterReagentBag(id) ~= true then return 0 end
			if fitsSpecial(kind, fam[bag]) then return 2 end
			if (fam[bag] or 0) == 0 then return 1 end
			return 0
		end
		local function move(srcBag, srcSlot, dstBag, dstSlot)
			ClearCursor()
			C_Container.PickupContainerItem(srcBag, srcSlot)
			C_Container.PickupContainerItem(dstBag, dstSlot)
			if GetCursorInfo() then ClearCursor() end
			moves = moves + 1
			C_Timer.After(0.2, step)
		end
		local byID, locked = {}, false
		for _, bag in ipairs(bags) do
			if not isKeyring(bag) then
				for slot = 1, numSlots(bag) do
					local info = C_Container.GetContainerItemInfo(bag, slot)
					if info and info.itemID and not ns.isSecret(info.itemID) then
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
		end
		-- The last move is still settling: wait for it.
		if locked then C_Timer.After(0.15, step) return end
		for id, list in pairs(byID) do
			if #list > 1 then
				local kind = itemFamily(id) or 0
				-- The stack already in the reagent bag (or quiver) stays put.
				-- The part stack in the normal bag is the one that moves.
				table.sort(list, function(a, b)
					local ra, rb = rank(a.bag, kind, id), rank(b.bag, kind, id)
					if ra ~= rb then return ra > rb end
					return a.n > b.n
				end)
				local dst, src = list[1], list[#list]
				move(src.bag, src.slot, dst.bag, dst.slot)
				return
			end
		end
		local pack = packing
		if pack then
			local m = orderMove(bags, refused)
			if m == "locked" then C_Timer.After(0.15, step) return end
			if m then
				local k = m[1] .. ":" .. m[2] .. ">" .. m[3] .. ":" .. m[4]
				if k == lastKey then
					-- The reagent bag refused it. Leave that item out and keep packing.
					if HAS_REAGENT and m[3] == REAGENT_BAG then
						local info = C_Container.GetContainerItemInfo(m[1], m[2])
						local id = info and info.itemID
						if id and not ns.isSecret(id) then refused[id] = true end
						lastKey = nil
						C_Timer.After(0.05, step)
						return
					end
					finish("restack stopped (that item can't move)")
					return
				end
				lastKey = k
				move(m[1], m[2], m[3], m[4])
				return
			end
		else
		for _, bag in ipairs(bags) do
			if not isKeyring(bag) then
				for slot = 1, numSlots(bag) do
					local info = C_Container.GetContainerItemInfo(bag, slot)
					local id = info and info.itemID
					if id and not ns.isSecret(id) and not info.isLocked then
						local kind = itemFamily(id)
						if kind and kind ~= 0 and not fitsSpecial(kind, fam[bag]) then
							for _, dst in ipairs(bags) do
								local reagentOk = not (HAS_REAGENT and dst == REAGENT_BAG) or canEnterReagentBag(id) == true
								if not isKeyring(dst) and reagentOk and fitsSpecial(kind, fam[dst]) then
									local open = freeSlot(dst)
									if open then move(bag, slot, dst, open) return end
								end
							end
						end
					end
				end
			end
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
			if info and info.itemID and (info.quality == 0 or ns.IsMarkedJunk(info.itemID)) and not info.hasNoValue and not info.isLocked
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
local paintBankButton

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

-- Shift-click a bag in the row to leave its slots out of the window.
-- Click it again to put them back. The bag icon stays so it can be clicked.
local function bagContentsHidden(bag)
	local t = db().bagContentsHidden
	return type(t) == "table" and t[tostring(bag)] == true
end
local function toggleBagContents(bag)
	local t = db().bagContentsHidden or {}
	db().bagContentsHidden = t
	local key = tostring(bag)
	t[key] = not t[key] or nil
end
local function withoutHidden(list)
	local t = db().bagContentsHidden
	if type(t) ~= "table" then return list end
	local out, hidden = {}, false
	for _, bag in ipairs(list) do
		if t[tostring(bag)] then hidden = true else out[#out + 1] = bag end
	end
	return hidden and out or list
end
local syncBankRow

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
		local hidden = bagContentsHidden(b.bag)
		if b.icon.SetDesaturated then b.icon:SetDesaturated(hidden) end
		b.icon:SetAlpha(hidden and 0.35 or 1)
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
	local function put(self)
		local slot = invSlot(self.bag)
		if InCombatLockdown() or not slot then return end
		if CursorHasItem() then
			-- Dropping a non-reagent on the reagent bag is the error. Leave it
			-- on the cursor instead of asking the bag to take it.
			if HAS_REAGENT and self.bag == REAGENT_BAG and GetCursorInfo then
				local ok, kind, id = pcall(GetCursorInfo)
				if ok and not ns.isSecret(kind) and kind == "item" and type(id) == "number" and not ns.isSecret(id) and canEnterReagentBag(id) == false then return end
			end
			PutItemInBag(slot)
		else
			PickupBagFromSlot(slot)
		end
	end
	b:SetScript("OnClick", function(self, button)
		if button == "LeftButton" and IsShiftKeyDown() and not cursorHolding() then
			toggleBagContents(self.bag)
			v.dirty = true
			if not InCombatLockdown() then v:Layout() end
			if v.stackKey == "bank" then syncBankRow() else paintBagSlots() end
			return
		end
		put(self)
	end)
	b:SetScript("OnReceiveDrag", put)
	b:SetScript("OnDragStart", function(self)
		local slot = invSlot(self.bag)
		if not InCombatLockdown() and slot then PickupBagFromSlot(slot) end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		if type(self.tabName) == "string" and self.tabName ~= "" then
			GameTooltip:AddLine(self.tabName)
		else
			local slot = invSlot(self.bag)
			if not (slot and GameTooltip:SetInventoryItem("player", slot)) then
				GameTooltip:AddLine("Empty bag slot")
			end
			GameTooltip:AddLine("Drop a bag here to put it on. Click or drag to take it off (it must be empty).", 0.6, 0.8, 1, true)
		end
		GameTooltip:AddLine(bagContentsHidden(self.bag) and "Shift-click to show this bag." or "Shift-click to hide this bag.", 0.6, 0.8, 1)
		local n = numSlots(self.bag)
		if n > 0 then
			local free = plainNum(C_Container.GetContainerNumFreeSlots(self.bag))
			local used = math.max(0, n - free)
			GameTooltip:AddLine(used .. "/" .. n .. (used >= n and " FULL" or ""))
		end
		GameTooltip:Show()
		v.hoverBag = self.bag
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
		frameName = "ZydeForeverBags", bags = function() return withoutHidden(shownBags()) end, posKey = "bagPos", stackKey = "bags",
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
		v.hoverBag = nil -- (hiding the row under the mouse skipped its OnLeave)
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

	win.restackBtn = win.AddButton("Restack", 80, "Restack",
		"Joins part stacks of the same item, and moves an item into the bag that holds it (your reagent bag, a quiver, a soul bag) when that bag has a free slot. The number is how many slots that frees.",
		function() restack(shownBags()) end)
	win.sellJunk = win.AddButton("Sell junk", 70, "Sell your junk",
		"Sells every gray item, and everything you marked as junk, that's worth something (never Perma). Only at a vendor.",
		function() sellJunk(false) end)

	-- Junk bar: while you hold an item from your bags, a bar shows across the
	-- top of the window. Drop the item on it to mark it as junk (sorted under
	-- Junk and sold at vendors like grays); drop an item already marked to
	-- unmark it. The item goes back to its slot either way.
	local junkBar = CreateFrame("Button", nil, win)
	junkBar:SetPoint("TOPLEFT", win.content, "TOPLEFT", 0, 0)
	junkBar:SetPoint("TOPRIGHT", win.content, "TOPRIGHT", 0, 0)
	junkBar:SetHeight(34)
	junkBar:SetFrameLevel((win:GetFrameLevel() or 1) + 40)
	junkBar:RegisterForClicks("LeftButtonUp")
	junkBar:Hide()
	junkBar.bg = junkBar:CreateTexture(nil, "BACKGROUND")
	junkBar.bg:SetAllPoints()
	junkBar.edges = ns.newEdges(junkBar, "BORDER", 1)
	ns.placeEdges(junkBar.edges, junkBar, 0, 1)
	junkBar.icon = junkBar:CreateTexture(nil, "ARTWORK")
	junkBar.icon:SetSize(18, 18)
	junkBar.icon:SetPoint("LEFT", 10, 0)
	junkBar.icon:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
	junkBar.text = junkBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	junkBar.text:SetPoint("LEFT", junkBar.icon, "RIGHT", 8, 0)
	junkBar.text:SetPoint("RIGHT", -10, 0)
	junkBar.text:SetJustifyH("LEFT")
	local function heldItem()
		local kind, id, link = GetCursorInfo()
		if kind == "item" and type(id) == "number" and not ns.isSecret(id) then return id, link end
	end
	local function paintJunkBar(hover)
		local id = heldItem()
		local marked = id and ns.IsMarkedJunk(id)
		local r, g, b = 0.9, 0.35, 0.2
		if marked then r, g, b = 0.35, 0.85, 0.45 end
		junkBar.bg:SetColorTexture(r * 0.25, g * 0.25, b * 0.25, hover and 0.97 or 0.9)
		for _, t in ipairs(junkBar.edges) do t:SetColorTexture(r, g, b, hover and 1 or 0.7) end
		junkBar.text:SetText(marked and "Drop here: no longer junk" or "Drop here: mark as junk (sold at vendors)")
		junkBar.text:SetTextColor(r + 0.1, g + 0.1, b + 0.1)
	end
	local function dropped()
		local id, link = heldItem()
		if not id then return end
		local mark = not ns.IsMarkedJunk(id)
		setJunk(id, mark)
		ClearCursor() -- (the item goes back to its slot)
		print(P .. (type(link) == "string" and link or "item") .. (mark and " is marked as junk: it sells at vendors"
			or " is no longer junk"))
		junkBar:Hide()
		for _, vw in pairs(views) do vw.dirty = true end
		if not InCombatLockdown() then v:Layout() else v:Repaint() end
	end
	junkBar:SetScript("OnReceiveDrag", dropped)
	junkBar:SetScript("OnClick", dropped)
	junkBar:SetScript("OnEnter", function() paintJunkBar(true) end)
	junkBar:SetScript("OnLeave", function() paintJunkBar(false) end)
	function win.UpdateJunkBar()
		if win:IsShown() and heldItem() then
			paintJunkBar(junkBar:IsMouseOver())
			junkBar:Show()
		else
			junkBar:Hide()
		end
	end
	win.sellJunk:Hide()
	win.bankBtn = win.AddButton("Bank", 110, "Your bank",
		"Opens the bank from the last time you visited a banker. Your bags stay open. At a banker this opens the real bank. The label is how full the bank is.",
		function() ns.OpenBankWindow() end)

	win:SetScript("OnShow", function()
		v.hoverBag = nil
		v:Place()
		paintKeys()
		paintBagSlots()
		if paintBankButton then paintBankButton() end
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

-- The Stacks option changed. Lay the open windows out again so each slot
-- shows, or the stacks fold back into one tile.
function ns.BagWindowRestack()
	for _, v in pairs(views) do
		v.dirty = true
		if v.win and v.win:IsShown() and not InCombatLockdown() then v:Layout() end
	end
end

---------------------------------------------------------------------------
-- The bank: the same window, while you're at a banker. The game's bank window
-- is shrunk out of the way (closing it would end the visit). The bag row on
-- this window is your bank bags or tabs, and the button that buys the next one.
---------------------------------------------------------------------------
local gameBankShown = false
local function bankFrame() return _G.BankFrame end

local function tuckGameBank(tuck)
	local f = bankFrame()
	if not f or InCombatLockdown() then return end
	if tuck then
		-- Stay shown. The game's right-click only moves an item when this frame's
		-- bank page is still shown. Scaling it away makes that click do nothing.
		-- Mouse is off so the invisible page does not take the click itself.
		f:SetAlpha(0)
		f:SetScale(1)
		muteTree(f, 0)
	else
		f:SetAlpha(1)
		f:SetScale(1)
		if f.EnableMouse then f:EnableMouse(true) end
		if f.SetMouseClickEnabled then f:SetMouseClickEnabled(true) end
		if f.SetMouseMotionEnabled then f:SetMouseMotionEnabled(true) end
	end
end

local function activeBankType()
	if BankFrame and BankFrame.GetActiveBankType then
		local t = BankFrame:GetActiveBankType()
		if not ns.isSecret(t) and type(t) == "number" then return t end
	end
	if Enum and Enum.BankType and type(Enum.BankType.Character) == "number" then return Enum.BankType.Character end
end

-- Purchased bank bags or tabs, in the game's own order. The buy button is the
-- next one. A modern bank has tabs (C_Bank). An older one has bag slots.
-- Any bag that currently holds slots is included too, so a tab still shows
-- when the tab list itself comes back empty.
local function plainBagID(id)
	if id == nil or ns.isSecret(id) then return nil end
	if type(id) == "number" then return id end
	return tonumber(id)
end
local function addBankBag(list, seen, bag, icon, name)
	bag = plainBagID(bag)
	if not bag or seen[bag] or isKeyring(bag) or isEquippedBag(bag) then return end
	seen[bag] = true
	if ns.isSecret(icon) or (type(icon) ~= "string" and type(icon) ~= "number") then icon = nil end
	if ns.isSecret(name) or type(name) ~= "string" or name == "" then name = nil end
	list[#list + 1] = { bag = bag, icon = icon, name = name }
end
local function pullBankTabs(list, seen, data)
	if ns.isSecret(data) or type(data) ~= "table" then return end
	for _, tab in ipairs(data) do
		if type(tab) == "table" then
			addBankBag(list, seen, tab.ID or tab.id, tab.icon, tab.name)
		end
	end
end
local function bankBagContainers()
	local list, seen = {}, {}
	local panel = BankFrame and BankFrame.BankPanel
	if panel then pcall(pullBankTabs, list, seen, panel.purchasedBankTabData) end
	if C_Bank and C_Bank.FetchPurchasedBankTabData then
		local bankType = activeBankType()
		if bankType ~= nil then
			local ok, data = pcall(C_Bank.FetchPurchasedBankTabData, bankType)
			if ok then pullBankTabs(list, seen, data) end
		end
	end
	for _, bag in ipairs(bankBags()) do addBankBag(list, seen, bag) end
	if #list > 0 then return list end
	local maxn = NUM_BANKBAGSLOTS or 7
	if type(maxn) ~= "number" or maxn < 1 then maxn = 7 end
	local function bagForButton(btn, i)
		if btn and btn.GetBagID then
			local ok, id = pcall(btn.GetBagID, btn)
			if ok and type(id) == "number" and not ns.isSecret(id) then return id end
		end
		if BankButtonIDToInvSlotID then
			local ok, inv = pcall(BankButtonIDToInvSlotID, (btn and btn.GetID and btn:GetID()) or i, true)
			if ok and type(inv) == "number" and not ns.isSecret(inv) then
				local key = keyringId()
				for bag = -4, LAST_BAG + 28 do
					if bag ~= key and bag ~= BANK_MAIN and not (HAS_REAGENT and bag == REAGENT_BAG) and invSlot(bag) == inv then
						return bag
					end
				end
			end
		end
	end
	for i = 1, maxn do
		local btn = _G["BankFrameBag" .. i] or _G["BankSlotsFrameBag" .. i]
		if btn and btn:IsShown() then
			local bag = bagForButton(btn, i)
			if bag then list[#list + 1] = bag end
		end
	end
	if #list > 0 then return list end
	local purchased = 0
	if GetNumBankSlots then
		local n = GetNumBankSlots()
		if not ns.isSecret(n) then purchased = tonumber(n) or 0 end
	end
	if purchased <= 0 then return list end
	local startAt = LAST_BAG + 1
	if HAS_REAGENT and REAGENT_BAG >= startAt then startAt = REAGENT_BAG + 1 end
	local key = keyringId()
	for bag = startAt, startAt + maxn - 1 do
		if #list >= purchased then break end
		if bag ~= key and not (HAS_REAGENT and bag == REAGENT_BAG) and invSlot(bag) then
			list[#list + 1] = bag
		end
	end
	local plain = {}
	for _, bag in ipairs(list) do addBankBag(plain, {}, bag) end
	return plain
end

local function nextBankTab()
	if not (C_Bank and C_Bank.FetchNextPurchasableBankTabData) then return nil end
	local bankType = activeBankType()
	if bankType == nil then return nil end
	local ok, tab = pcall(C_Bank.FetchNextPurchasableBankTabData, bankType)
	if ok and not ns.isSecret(tab) and type(tab) == "table" then return tab end
end

local function bankSlotCost()
	local tab = nextBankTab()
	local cost = tab and tab.tabCost
	if not ns.isSecret(cost) and type(cost) == "number" and cost > 0 then return cost end
	if not GetBankSlotCost then return nil end
	local slotCost = GetBankSlotCost()
	if ns.isSecret(slotCost) or type(slotCost) ~= "number" or slotCost <= 0 then return nil end
	return slotCost
end

local function canBuyBankSlot()
	if C_Bank and C_Bank.HasMaxBankTabs then
		local bankType = activeBankType()
		if bankType ~= nil then
			local ok, full = pcall(C_Bank.HasMaxBankTabs, bankType)
			if ok and not ns.isSecret(full) then return not full end
		end
	end
	if C_Bank and C_Bank.CanPurchaseBankTab then
		local bankType = activeBankType()
		if bankType == nil then return false end
		if C_Bank.HasMaxBankTabs then
			local full = C_Bank.HasMaxBankTabs(bankType)
			if not ns.isSecret(full) and full then return false end
		end
		local ok, can = pcall(C_Bank.CanPurchaseBankTab, bankType)
		if ok then return can and not ns.isSecret(can) and true or false end
	end
	local purchase = _G.BankFramePurchaseButton
	if purchase then return purchase:IsShown() end
	local maxn = NUM_BANKBAGSLOTS or 7
	if type(maxn) ~= "number" then maxn = 7 end
	local purchased = 0
	if GetNumBankSlots then
		local n = GetNumBankSlots()
		if not ns.isSecret(n) then purchased = tonumber(n) or 0 end
	end
	return purchased < maxn and bankSlotCost() ~= nil
end

local function buyBankSlot()
	if InCombatLockdown() then return end
	if C_Bank and C_Bank.CanPurchaseBankTab and StaticPopupDialogs and StaticPopupDialogs.CONFIRM_BUY_BANK_TAB and StaticPopup_Show then
		StaticPopup_Show("CONFIRM_BUY_BANK_TAB", nil, nil, { bankType = activeBankType() })
		return
	end
	if StaticPopupDialogs and StaticPopupDialogs.CONFIRM_BUY_BANK_SLOT and StaticPopup_Show then
		StaticPopup_Show("CONFIRM_BUY_BANK_SLOT")
		return
	end
	if PurchaseSlot then PurchaseSlot() end
end

-- The bag item sitting in a bank slot. A tab's own icon is often just the
-- question mark, which is not the bag.
local function plainTex(tex)
	if tex == nil or ns.isSecret(tex) or tex == "" or tex == 0 then return nil end
	if tex == QUESTION_MARK_ICON or tex == 134400 then return nil end
	if type(tex) == "string" and tex:find("QuestionMark") then return nil end
	if type(tex) ~= "string" and type(tex) ~= "number" then return nil end
	return tex
end
local function textureFromInv(slot)
	if not slot or ns.isSecret(slot) or type(slot) ~= "number" then return nil end
	if GetInventoryItemTexture then
		local tex = plainTex(GetInventoryItemTexture("player", slot))
		if tex then return tex end
	end
	if GetInventoryItemID then
		local id = GetInventoryItemID("player", slot)
		if not ns.isSecret(id) and type(id) == "number" and id > 0 then
			local icon
			if C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(id)
			elseif GetItemIcon then icon = GetItemIcon(id) end
			return plainTex(icon)
		end
	end
end
local function bankBagTexture(bag, index)
	local tex = textureFromInv(invSlot(bag))
	if tex then return tex end
	if index and BankButtonIDToInvSlotID then
		local ok, slot = pcall(BankButtonIDToInvSlotID, index, true)
		if ok then
			tex = textureFromInv(slot)
			if tex then return tex end
		end
	end
	if index then
		local btn = _G["BankFrameBag" .. index] or _G["BankSlotsFrameBag" .. index]
		local icon = btn and (btn.icon or btn.Icon)
		if not icon and btn and btn.GetName then icon = _G[btn:GetName() .. "Icon"] end
		if icon and icon.GetTexture then
			tex = plainTex(icon:GetTexture())
			if tex then return tex end
		end
	end
end

local CHIP_W = S + 10
local CHIP_TEXT = 26
function syncBankRow()
	if not bankView or not bankView.win.bagRow then return end
	local win = bankView.win
	local ids = bankBagContainers()
	win.bagRow:SetFrameLevel((win:GetFrameLevel() or 1) + 30)
	local h = S + CHIP_TEXT
	for i, entry in ipairs(ids) do
		local bag = type(entry) == "table" and entry.bag or entry
		local b = win.bagSlots[i]
		if not b then
			b = bagSlot(bankView, bag, 0)
			win.bagSlots[i] = b
		end
		b.bag = bag
		b.tabName = type(entry) == "table" and entry.name or nil
		b:SetSize(CHIP_W, h)
		b.icon:ClearAllPoints()
		b.icon:SetPoint("TOP", 0, 0)
		b.icon:SetSize(S, S)
		if b.bg then
			b.bg:ClearAllPoints()
			b.bg:SetPoint("TOPLEFT", b.icon, "TOPLEFT", -1, 1)
			b.bg:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", 1, -1)
		end
		b.count:ClearAllPoints()
		b.count:SetPoint("TOP", b.icon, "BOTTOM", 0, -1)
		b.count:SetPoint("LEFT", 0, 0)
		b.count:SetPoint("RIGHT", 0, 0)
		b.count:SetFontObject("GameFontHighlightSmall")
		b.count:SetJustifyH("CENTER")
		b.count:SetJustifyV("TOP")
		b.count:SetWordWrap(true)
		if b.nameText then b.nameText:Hide() end
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", (i - 1) * (CHIP_W + GAP), 0)
		local icon = type(entry) == "table" and entry.icon
		b.icon:SetTexture(bankBagTexture(bag, i) or plainTex(icon) or EMPTY_BAG_TEX)
		local hidden = bagContentsHidden(bag)
		if b.icon.SetDesaturated then b.icon:SetDesaturated(hidden) end
		b.icon:SetAlpha(hidden and 0.35 or 1)
		local n = numSlots(bag)
		if n > 0 then
			local free = plainNum(C_Container.GetContainerNumFreeSlots(bag))
			local used = math.max(0, n - free)
			b.count:SetText(used >= n and (used .. "/" .. n .. "\nFULL") or (used .. "/" .. n))
			if used >= n then b.count:SetTextColor(1, 0.25, 0.2) else b.count:SetTextColor(1, 1, 1) end
		else
			b.count:SetText("")
		end
		b:Show()
	end
	for i = #ids + 1, #win.bagSlots do win.bagSlots[i]:Hide() end
	local buy = win.buySlot
	if buy then
		if canBuyBankSlot() then
			local cost = bankSlotCost()
			local tab = nextBankTab()
			local afford = tab and not ns.isSecret(tab.canAfford) and tab.canAfford
			if afford == nil then
				local money = GetMoney()
				afford = cost and not ns.isSecret(money) and type(money) == "number" and money >= cost
			end
			buy:SetSize(S, S)
			if buy.icon then buy.icon:Hide() end
			if buy.plus then
				buy.plus:Show()
				buy.plus:SetTextColor(afford and 1 or 0.45, afford and 0.82 or 0.45, afford and 0 or 0.45)
			end
			if buy.label then buy.label:Hide() end
			if buy.costText then buy.costText:Hide() end
			buy:ClearAllPoints()
			buy:SetPoint("TOPLEFT", #ids * (CHIP_W + GAP), 0)
			buy.cost = cost
			buy.modern = tab and true or false
			buy:Show()
		else
			buy:Hide()
		end
	end
	local grew = bankView.bagRowHeight ~= h
	bankView.bagRowHeight = h
	win.bagRow:SetHeight(h)
	bankView.tabNote = #ids == 1 and "1 tab" or (#ids .. " tabs")
	if win:IsShown() then bankView:SetTitle() end
	bankView:PlaceContent()
	if grew and win:IsShown() and not InCombatLockdown() and not bankView.layingRow then
		bankView.layingRow = true
		bankView:Layout()
		bankView.layingRow = false
	end
end

-- Same default as the bag row on your bags: hidden until the button is on.
-- Hidden extra bank bags leave the window. The main bank stays.
local function bankBagsShown() return db().bankSlotsShown and true or false end
local function shownBankBags()
	local list = bankBags()
	if bankBagsShown() then return list end
	local out = {}
	for _, bag in ipairs(list) do
		if BANK_MAIN and bag == BANK_MAIN then out[#out + 1] = bag end
	end
	if #out == 0 then return list end
	return out
end

local function buildBank()
	local v = newView({
		frameName = "ZydeForeverBank", bags = function() return withoutHidden(shownBankBags()) end, posKey = "bankPos", stackKey = "bank",
		titleText = "Bank",
		defaultPoint = { "TOPLEFT", UIParent, "TOPLEFT", 20, -110 },
		bagRowShown = bankBagsShown,
	})
	local win = v.win
	win.bagRow = CreateFrame("Frame", nil, win)
	win.bagRow:SetPoint("TOPLEFT", PAD, -32)
	win.bagRow:SetSize(INNER_W, S)
	win.bagSlots = {}
	win.buySlot = CreateFrame("Button", nil, win.bagRow)
	win.buySlot:SetSize(S, S)
	win.buySlot:RegisterForClicks("LeftButtonUp")
	win.buySlot.bg = win.buySlot:CreateTexture(nil, "BACKGROUND")
	win.buySlot.bg:SetPoint("TOPLEFT", -1, 1)
	win.buySlot.bg:SetPoint("BOTTOMRIGHT", 1, -1)
	win.buySlot.bg:SetColorTexture(0, 0, 0, 1)
	win.buySlot.icon = win.buySlot:CreateTexture(nil, "ARTWORK")
	win.buySlot.icon:SetAllPoints()
	win.buySlot.icon:SetTexture(EMPTY_BAG_TEX)
	win.buySlot.plus = win.buySlot:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	win.buySlot.plus:SetPoint("CENTER", 0, 0)
	win.buySlot.plus:SetText("+")
	local buyHl = win.buySlot:CreateTexture(nil, "HIGHLIGHT")
	buyHl:SetAllPoints()
	buyHl:SetColorTexture(1, 1, 1, 0.15)
	win.buySlot:SetScript("OnClick", buyBankSlot)
	win.buySlot:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(self.modern and "Buy a bank tab" or "Buy a bank bag slot")
		if self.cost then
			GameTooltip:AddLine("Costs " .. moneyText(self.cost), 1, 1, 1)
		end
		if not self.modern then
			GameTooltip:AddLine("The new slot starts empty. Drop a bag on it.", 0.6, 0.8, 1, true)
		end
		GameTooltip:Show()
	end)
	win.buySlot:SetScript("OnLeave", function() GameTooltip:Hide() end)
	win.buySlot:Hide()
	v:PlaceContent()
	local toggle = CreateFrame("Button", nil, win)
	toggle:SetSize(22, 22)
	toggle:SetPoint("RIGHT", win.search, "LEFT", -10, 0)
	toggle:SetNormalTexture(EMPTY_BAG_TEX)
	toggle:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	toggle:SetScript("OnClick", function()
		if InCombatLockdown() then return end
		db().bankSlotsShown = not bankBagsShown()
		v:PlaceContent()
		v.dirty = true
		v:Layout()
	end)
	toggle:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(bankBagsShown() and "Hide bank bags" or "Show bank bags")
		GameTooltip:AddLine("The extra bank bags. The main bank stays. Hidden bags leave this window.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
	win.title:SetWidth(INNER_W - 140 - 6 - 24 - 40 - 28)
	win.restackBtn = win.AddButton("Restack", 80, "Restack",
		"Joins part stacks of the same item, and moves an item into the bank bag that holds it when that bag has a free slot. The number is how many slots that frees.",
		function() restack(bankBags()) end)
	win:SetScript("OnShow", function()
		v:Place()
		syncBankRow()
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
	local data, free, extra, _, slots = gather(bags, "bank")
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
	db().bankSeen[key] = { free = free or 0, slots = slots or 0, extra = savedExtra, items = items, at = time() }
	if ns.RefreshBankMemory then ns.RefreshBankMemory() end
	if paintBankButton then paintBankButton() end
	if bankView and bankView.win:IsShown() then syncBankRow() end
	if ns.RefreshInfoBar then ns.RefreshInfoBar() end
end

-- Used slots and size of the bank. Live while the bank is open, otherwise the last visit.
function ns.BankUsage()
	local f = bankFrame()
	if f and f:IsShown() then
		-- (only the slot counts: gather() would sort and check every item, and this runs for
		-- the Bank button, the info bar and the bank row on every bag change)
		local free, slots = 0, 0
		for _, bag in ipairs(bankBags()) do
			local fr, fam = C_Container.GetContainerNumFreeSlots(bag)
			fr, fam = plainNum(fr), plainNum(fam)
			if isOrdinaryBag(bag, fam) then
				free = free + fr
				slots = slots + numSlots(bag)
			end
		end
		if slots > 0 then return math.max(0, slots - free), slots end
	end
	local saved = savedBank()
	if saved and type(saved.slots) == "number" and saved.slots > 0 then
		local freeN = type(saved.free) == "number" and saved.free or 0
		return math.max(0, saved.slots - freeN), saved.slots
	end
end

paintBankButton = function()
	local btn = bagsView and bagsView.win and bagsView.win.bankBtn
	if not btn then return end
	local used, slots = ns.BankUsage()
	local text = "Bank"
	if used and slots and slots > 0 then
		text = "Bank " .. usageLabel(slots - used, slots)
	end
	btn:SetText(text)
	local fs = btn.GetFontString and btn:GetFontString()
	local w = fs and fs.GetStringWidth and fs:GetStringWidth() or (#text * 6)
	if ns.isSecret(w) or type(w) ~= "number" then w = #text * 6 end
	btn:SetWidth(math.max(56, w + 24))
	if bagsView.win.Flow then bagsView.win.Flow() end
end

local function buildMemory()
	local win = CreateFrame("Frame", "ZydeForeverBankMemory", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	memoryWin = win
	win:SetWidth(INNER_W + PAD * 2)
	win:SetHeight(160)
	-- Above the reminder icons (which sit in HIGH), so a reminder by your
	-- character never draws on top of your bags.
	win:SetFrameStrata("HIGH")
	win:SetFrameLevel(60)
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
			local bags = _G.ZydeForeverBags
			if bags then
				win:SetPoint("TOPRIGHT", bags, "TOPLEFT", -8, 0)
			else
				win:SetPoint("CENTER", -220, 40)
			end
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
		h.fold = function(btn)
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
		end
		armFold(h)
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
		local free = saved and usageLabel(saved.free or 0, saved.slots or 0) or ""
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
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "BAG_UPDATE", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED",
	"BAG_UPDATE_COOLDOWN", "PLAYER_REGEN_ENABLED", "PLAYER_MONEY", "GET_ITEM_INFO_RECEIVED", "QUEST_LOG_UPDATE",
	"BAG_CONTAINER_UPDATE", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "PLAYER_EQUIPMENT_CHANGED",
	"LEARNED_SPELL_IN_TAB", "NEW_RECIPE_LEARNED", "MERCHANT_SHOW", "MERCHANT_CLOSED",
	"BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "PLAYERBANKBAGSLOTS_CHANGED", "BANK_TABS_CHANGED", "PLAYER_MONEY", "CURSOR_CHANGED",
	"AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
	"MAIL_SHOW", "MAIL_CLOSED", "TRADE_SHOW", "TRADE_CLOSED" }) do
	pcall(ev.RegisterEvent, ev, e)
end
-- For a few seconds after login or a reload the game can flag everything you
-- carry as new. Nothing is new then: clear it while the bags fill in.
local loginQuietUntil = 0
local cursorWasItem = false
local function clearNew() if C_NewItems and C_NewItems.ClearAll then pcall(C_NewItems.ClearAll) end end

local function allChanged()
	if bankView and bankView.win:IsShown() then syncBankRow() end
	if paintBankButton then paintBankButton() end
	-- Opening the bank, the auction house, the trade window, or the mailbox,
	-- and every bag event while any of them stays open, was re-sorting the
	-- bags too. That rebuild flashes the bag window. The bank still sorts.
	-- The bags sort once when the last of those windows closes.
	local f = bankFrame()
	local atBank = f and f.IsShown and f:IsShown()
	if ns.isSecret(atBank) then atBank = false end
	local holdBags = atBank or auctionHouseOpen() or tradeOpen() or mailOpen()
	for _, v in pairs(views) do
		if holdBags and v == bagsView then
			v.dirty = true
		else
			v:Changed()
		end
	end
end

-- The bags were left unsorted while one of those windows was open. Sort once
-- when the last of them closes. A window that is still open keeps the hold.
local function releaseBags()
	if not bagsView then return end
	local f = bankFrame()
	local atBank = f and f.IsShown and f:IsShown()
	if ns.isSecret(atBank) then atBank = false end
	if atBank or auctionHouseOpen() or tradeOpen() or mailOpen() then return end
	bagsView:Changed()
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
	-- Picking an item up (or putting it down) shows or hides the Junk bar.
	-- The bag update for a move inside your own bags often arrives while the
	-- item is still on the cursor, so that layout paints the slot empty and
	-- nothing asks again after the drop. When the cursor lets the item go,
	-- read the bags once more.
	if event == "CURSOR_CHANGED" then
		local holding = cursorHolding()
		local dropped = cursorWasItem and not holding
		cursorWasItem = holding
		if bagsView and bagsView.win.UpdateJunkBar then bagsView.win.UpdateJunkBar() end
		for _, v in pairs(views) do
			if v.SyncDropSlot then v:SyncDropSlot() end
		end
		if dropped then
			allChanged()
			if bagsView and bagsView.win:IsShown() and not InCombatLockdown() then
				-- pending means a full sort was queued. Do it now so the
				-- slots are not left blank. While the bank, auction house,
				-- trade window, or mailbox holds that sort, just redraw the
				-- slots in place.
				if bagsView.pending then bagsView:Layout() else bagsView:Repaint() end
			end
		end
		return
	end
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
	if event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" or event == "BANKFRAME_OPENED" or event == "BANKFRAME_CLOSED" then
		markMoveStale()
	end
	if event == "BANK_TABS_CHANGED" or event == "PLAYER_MONEY" or event == "PLAYERBANKSLOTS_CHANGED" then
		syncBankRow()
	end
	if event == "BANKFRAME_OPENED" then
		gameBankShown = false
		tuckGameBank(true)
		bankView.dirty = true
		bankView.win:Show()
		syncBankRow()
		C_Timer.After(0.25, function()
			tuckGameBank(true)
			markMoveStale()
			rememberBank()
			syncBankRow()
		end)
		return
	end
	if event == "BANKFRAME_CLOSED" then
		-- (no snapshot here: by now the items can already be gone, which
		-- saved an empty bank over the real one)
		gameBankShown = true -- (so hiding ours doesn't close the bank again)
		bankView.win:Hide()
		tuckGameBank(false)
		-- The bag window was left alone during the visit. Sort it once now,
		-- unless the auction house, trade, or mailbox is still open.
		releaseBags()
		return
	end
	if event == "AUCTION_HOUSE_CLOSED" or event == "MAIL_CLOSED" or event == "TRADE_CLOSED" then
		-- Left alone while that window was open. Sort once now, unless the
		-- bank or another of those windows is still open.
		releaseBags()
		return
	end
	if event == "PLAYER_LEVEL_UP" or event == "SKILL_LINES_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED"
		or event == "LEARNED_SPELL_IN_TAB" or event == "NEW_RECIPE_LEARNED" then
		-- What you can use, and what's an upgrade, may have changed: read the tooltips again.
		wipe(scanCache)
		wipe(beginsCache)
		-- (a full sort, not just a repaint: the Upgrades section may change)
		allChanged()
		return
	end
	if event == "GET_ITEM_INFO_RECEIVED" then
		local itemID, success = isLogin, isReload
		if ns.isSecret(itemID) or not waitingIds[itemID] then return end
		waitingIds[itemID] = nil
		if success == false then return end
		allChanged()
		return
	end
	if event == "PLAYER_MONEY" then
		bagsView.win.money:SetText(moneyText())
		if bankView and bankView.win:IsShown() then syncBankRow() end
		return
	end
	if event == "BAG_CONTAINER_UPDATE" or event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" then paintBagSlots() end
	if event == "ITEM_LOCK_CHANGED" or event == "BAG_UPDATE_COOLDOWN" then
		ns.BagWindowRepaint()
		return
	end
	if bankFrame() and bankFrame():IsShown() then rememberBank() end
	allChanged()
end)

if ns.OnFeatureChanged then
	ns.OnFeatureChanged(function(key)
		if key ~= "bagOrder" then return end
		for _, v in ipairs({ bagsView, bankView }) do
			if v then
				v.dirty = true
				if v.win:IsShown() and not InCombatLockdown() then v:Layout()
				elseif v.win:IsShown() then v:Repaint() end
			end
		end
	end)
end
