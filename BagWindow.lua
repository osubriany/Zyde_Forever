-- Zyde_Forever: all your bags in one window, sorted into sections.
--   Opens instead of the game's bags (B, the bag buttons, vendors, mail...).
--   General: Perma (never delete), Quest, Junk, Keys, Other, and Empty slots.
--   Gear: weapons, armor, bags, ammo. Consumables: food & drink, potions,
--   bandages, scrolls, other. Profession: trade goods by type, reagents, recipes.
--   Items are real bag slots: right-click uses or sells, drag moves, shift-click
--   links. Drop an item on an Empty tile to put it in that free slot.
--   Alt-click an item to put it in Perma (or take it out). Click a heading to fold it.
-- Off while Baganator is loaded. Only the view is sorted; the bags themselves
-- stay as they are (the Sort button asks the game to tidy them).
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

-- Your bags: the backpack, the four bags, and Forever's reagent (profession)
-- bag, which has its own slot and its own bag number past the four.
local LAST_BAG = NUM_BAG_SLOTS or 4
local REAGENT_BAG = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or REAGENTBAG_CONTAINER or 5
local toInv = (C_Container and C_Container.ContainerIDToInventoryID) or ContainerIDToInventoryID
local function invSlot(bag)
	if not toInv then return nil end
	local ok, slot = pcall(toInv, bag)
	return ok and type(slot) == "number" and slot or nil
end
local HAS_REAGENT = REAGENT_BAG > LAST_BAG and invSlot(REAGENT_BAG) ~= nil
local function myBags()
	local list = {}
	for bag = 0, LAST_BAG do list[#list + 1] = bag end
	if HAS_REAGENT then list[#list + 1] = REAGENT_BAG end
	return list
end
local function isMine(id)
	return type(id) == "number" and ((id >= 0 and id <= LAST_BAG) or (HAS_REAGENT and id == REAGENT_BAG))
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
local SECTIONS = { "General", "Gear", "Consumables", "Profession" }
local ORDER = {
	General = { "Empty", "Perma", "Quest", "Junk", "Keys", "Other" },
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

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local win, holders, pool, heads, labels = nil, {}, {}, {}, {}
local used, labelUsed = 0, 0
local dirty = true

local function collapsed() db().bagCollapsed = db().bagCollapsed or {} return db().bagCollapsed end
local function bagsShown() return db().bagSlotsShown and true or false end
-- Where the sections start: under the title, and under the bag row when it's out.
local function contentTop() return 34 + (bagsShown() and (S + 8) or 0) end

local function holder(bag)
	if holders[bag] then return holders[bag] end
	local h = CreateFrame("Frame", nil, win)
	h:SetID(bag)
	h:SetAllPoints()
	holders[bag] = h
	return h
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

local function paint(b)
	if b.empty then
		setNew(b, false)
		setBang(b, false)
		SetItemButtonTexture(b, b.emptyTex)
		SetItemButtonCount(b, b.emptyCount)
		SetItemButtonDesaturated(b, false)
		if SetItemButtonQuality then pcall(SetItemButtonQuality, b, nil) end
		if b.cd then b.cd:Hide() end
		b:SetAlpha(1)
		return
	end
	local info = C_Container.GetContainerItemInfo(b:GetParent():GetID(), b:GetID())
	if not info then
		setNew(b, false)
		setBang(b, false)
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
	setNew(b, isNewItem(b:GetParent():GetID(), b:GetID()), info.quality)
	setBang(b, startsQuest(b:GetParent():GetID(), b:GetID()))
	if b.cd and C_Container.GetContainerItemCooldown then
		local start, dur, enable = C_Container.GetContainerItemCooldown(b:GetParent():GetID(), b:GetID())
		if CooldownFrame_Set then pcall(CooldownFrame_Set, b.cd, start, dur, enable) end
	end
	local text = win.search and win.search:GetText() or ""
	local lit = text == "" or nameOf(info):lower():find(text:lower(), 1, true) ~= nil
	-- Hovering a bag in the bag row lights up only what's in that bag.
	if win.hoverBag then
		local inBag = false
		for _, s in ipairs(b.slots or { { bag = b:GetParent():GetID() } }) do
			if s.bag == win.hoverBag then inBag = true break end
		end
		if not inBag then lit = false end
	end
	b:SetAlpha(lit and 1 or 0.25)
end

local function itemButton(i)
	if pool[i] then return pool[i] end
	local name = "ZydeForeverBagItem" .. i
	local ok, b = pcall(CreateFrame, "ItemButton", name, holder(0), "ContainerFrameItemButtonTemplate")
	if not ok or not b then b = CreateFrame("Button", name, holder(0), "ContainerFrameItemButtonTemplate") end
	b:SetSize(S, S)
	b.cd = b.Cooldown or _G[name .. "Cooldown"]
	b:HookScript("OnClick", function(self, btn)
		if self.empty or btn ~= "LeftButton" or not IsAltKeyDown() then return end
		local info = C_Container.GetContainerItemInfo(self:GetParent():GetID(), self:GetID())
		if info and info.itemID then
			togglePerma(info.itemID)
			dirty = true
			if not InCombatLockdown() then win:Layout() end
		end
	end)
	b:HookScript("OnEnter", function(self)
		if self.empty then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(self.emptyCount .. " empty slots")
			GameTooltip:AddLine("Drop an item here to move it to a free slot.", 1, 1, 1, true)
			GameTooltip:Show()
			return
		end
		if GameTooltip:IsOwned(self) then
			GameTooltip:AddLine("Alt-click: " .. (self.perma and "take out of Perma" or "keep in Perma"), 0.6, 0.8, 1)
			GameTooltip:Show()
		end
	end)
	pool[i] = b
	return b
end

local function label(i)
	if labels[i] then return labels[i] end
	local t = win.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	t:SetJustifyH("LEFT")
	t:SetWordWrap(false)
	t:SetTextColor(0.85, 0.85, 0.85)
	labels[i] = t
	return t
end

local function head(i)
	if heads[i] then return heads[i] end
	local h = CreateFrame("Button", nil, win.content)
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
	h:SetScript("OnClick", function(self)
		if InCombatLockdown() then return end
		collapsed()[self.section] = not collapsed()[self.section] or nil
		win:Layout()
	end)
	heads[i] = h
	return h
end

-- Stacks of the same item become one tile showing the total (14 stacks of
-- bullets: one tile of 2770). The tile is the smallest stack's slot, so
-- using or dragging it takes from the stack that's nearly gone first.
-- Things that don't stack (gear) stay one tile each.
local maxStack = (C_Item and C_Item.GetItemMaxStackSizeByID) or nil
local function stacks(info)
	local n = maxStack and ns.safe(maxStack, info.itemID)
	if type(n) == "number" and not ns.isSecret(n) then return n > 1 end
	return (info.stackCount or 1) > 1
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

-- Every filled slot, sorted into section -> group -> list; plus the empty tiles.
local function gather()
	local out = {}
	for _, sec in ipairs(SECTIONS) do out[sec] = {} end
	local function add(sec, group, entry)
		out[sec][group] = out[sec][group] or {}
		table.insert(out[sec][group], entry)
	end
	for _, info in ipairs(ns.Bags.items()) do
		local sec, group = categorize(info)
		add(sec, group, { bag = info.bag, slot = info.slot, info = info, name = nameOf(info) })
	end
	-- The shared bag list stops at the four bags; read the reagent bag here.
	if HAS_REAGENT then
		for slot = 1, (C_Container.GetContainerNumSlots(REAGENT_BAG) or 0) do
			local info = C_Container.GetContainerItemInfo(REAGENT_BAG, slot)
			if info and info.itemID then
				info.bag, info.slot = REAGENT_BAG, slot
				local sec, group = categorize(info)
				add(sec, group, { bag = REAGENT_BAG, slot = slot, info = info, name = nameOf(info) })
			end
		end
	end
	-- Empty: one tile per kind of bag (normal, quiver, soul bag...), pointing at its first free slot.
	local byFamily, famOrder = {}, {}
	for _, bag in ipairs(myBags()) do
		local n = C_Container.GetContainerNumSlots(bag) or 0
		local free, fam = C_Container.GetContainerNumFreeSlots(bag)
		fam = tonumber(fam) or 0
		if bag == REAGENT_BAG then fam = 100000 end -- reagents only: its own tile, last
		if n > 0 and (free or 0) > 0 then
			local e = byFamily[fam]
			if not e then
				local tex = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
				if fam ~= 0 and C_Container.ContainerIDToInventoryID then
					tex = GetInventoryItemTexture("player", C_Container.ContainerIDToInventoryID(bag)) or tex
				end
				e = { empty = true, count = 0, tex = tex }
				byFamily[fam] = e
				famOrder[#famOrder + 1] = fam
			end
			e.count = e.count + free
			if not e.bag then
				for slot = 1, n do
					if not C_Container.GetContainerItemID(bag, slot) then e.bag, e.slot = bag, slot break end
				end
			end
		end
	end
	table.sort(famOrder)
	for _, fam in ipairs(famOrder) do
		local e = byFamily[fam]
		if e.bag then add("General", "Empty", e) end
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
	return out
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

local function layout()
	if InCombatLockdown() then dirty = true return end
	dirty = false
	local data = gather()
	used, labelUsed = 0, 0
	local headUsed = 0
	local y = 0
	for _, sec in ipairs(SECTIONS) do
		local groups = data[sec]
		local order = groupOrder(sec, groups)
		if #order > 0 then
			headUsed = headUsed + 1
			local h = head(headUsed)
			h.section = sec
			local folded = collapsed()[sec]
			local n = 0
			for _, g in ipairs(order) do n = n + #groups[g] end
			h.text:SetText(sec .. (folded and ("  |cff888888(" .. n .. ")|r") or ""))
			h.icon:SetTexture(folded and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
			h:ClearAllPoints()
			h:SetPoint("TOPLEFT", win.content, "TOPLEFT", 0, -y)
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
					local l = label(labelUsed)
					l:ClearAllPoints()
					l:SetPoint("TOPLEFT", win.content, "TOPLEFT", x, -y)
					l:SetWidth(math.max(w, S))
					l:SetText(g)
					l:Show()
					for i, e in ipairs(list) do
						used = used + 1
						local b = itemButton(used)
						b:SetParent(holder(e.bag))
						b:SetID(e.slot)
						b.empty = e.empty
						b.emptyTex, b.emptyCount = e.tex, e.count
					b.slots = e.slots
						b.perma = not e.empty and ns.IsPerma(e.info and e.info.itemID)
						local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
						b:ClearAllPoints()
						b:SetPoint("TOPLEFT", win.content, "TOPLEFT", x + col * (S + GAP), -(y + LABEL_H + row * (S + GAP)))
						b:Show()
						paint(b)
					end
					local rows = math.ceil(#list / cols)
					rowH = math.max(rowH, LABEL_H + rows * (S + GAP) - GAP)
					x = x + w + GROUP_GAP
				end
				y = y + rowH + 10
			end
		end
	end
	for i = used + 1, #pool do pool[i]:Hide() end
	for i = labelUsed + 1, #labels do labels[i]:Hide() end
	for i = headUsed + 1, #heads do heads[i]:Hide() end
	win.content:SetHeight(math.max(10, y))
	win:SetHeight(y + contentTop() + 2 + 34 + PAD)
end

local function repaint()
	for i = 1, used do paint(pool[i]) end
end

---------------------------------------------------------------------------
-- The bag row: your four bags, to swap one for a bigger one. Click or drag
-- a bag to pick it up (it has to be empty), drop a bag on a slot to put it on.
---------------------------------------------------------------------------
local EMPTY_BAG_TEX = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"

local function paintBagSlots()
	if not (win and win.bagSlots) then return end
	for _, b in ipairs(win.bagSlots) do
		local inv = invSlot(b.bag)
		local tex = inv and GetInventoryItemTexture("player", inv)
		b.icon:SetTexture(tex or EMPTY_BAG_TEX)
		local n = C_Container.GetContainerNumSlots(b.bag) or 0
		b.count:SetText(n > 0 and n or "")
	end
end

local function placeContent()
	win.content:ClearAllPoints()
	win.content:SetPoint("TOPLEFT", PAD, -contentTop())
	win.bagRow:SetShown(bagsShown())
end

local function bagSlot(bag, x)
	local b = CreateFrame("Button", nil, win.bagRow)
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
		win.hoverBag = bag
		repaint()
	end)
	b:SetScript("OnLeave", function()
		GameTooltip:Hide()
		win.hoverBag = nil
		repaint()
	end)
	return b
end

local function savePos()
	local l, b = win:GetLeft(), win:GetBottom()
	if ns.isSecret(l) or ns.isSecret(b) or not l or not b then return end
	db().bagPos = { x = win:GetRight(), y = b }
end

local function placeWin()
	win:ClearAllPoints()
	local p = db().bagPos
	if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" then
		win:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", p.x, p.y)
	else
		win:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -60, 110)
	end
end

local closeBlizzard -- forward

-- Your gold for the bottom-right corner: 14g 71s 18c with the coin icons.
local function coin(n, icon) return n .. "|TInterface\\MoneyFrame\\" .. icon .. ":12:12:2:0|t" end
local function moneyText()
	local c = ns.safe(GetMoney)
	if ns.isSecret(c) or type(c) ~= "number" then return "" end
	local g, sv, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = coin(g, "UI-GoldIcon") end
	if g > 0 or sv > 0 then parts[#parts + 1] = coin(sv, "UI-SilverIcon") end
	parts[#parts + 1] = coin(cp, "UI-CopperIcon")
	return table.concat(parts, "  ")
end

local function build()
	win = CreateFrame("Frame", "ZydeForeverBags", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	win:SetWidth(INNER_W + PAD * 2)
	win:SetHeight(200)
	win:SetFrameStrata("MEDIUM")
	win:SetToplevel(true)
	win:SetClampedToScreen(true)
	win:EnableMouse(true)
	win:SetMovable(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", function(self) self:StartMoving() end)
	win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() savePos() end)
	if win.SetBackdrop then
		win:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		win:SetBackdropColor(0.06, 0.06, 0.07, 0.95)
		win:SetBackdropBorderColor(0, 0, 0, 1)
	end
	tinsert(UISpecialFrames, "ZydeForeverBags")
	win:Hide()

	win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	win.title:SetPoint("TOPLEFT", PAD, -9)
	win.title:SetText((UnitName("player") or "") .. "'s bags")
	local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", function() win:Hide() end)

	local ok, search = pcall(CreateFrame, "EditBox", nil, win, "SearchBoxTemplate")
	if not ok or not search then search = CreateFrame("EditBox", nil, win, "InputBoxTemplate") end
	search:SetSize(150, 20)
	search:SetAutoFocus(false)
	search:SetPoint("RIGHT", close, "LEFT", -6, 0)
	search:HookScript("OnTextChanged", function() repaint() end)
	search:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
	win.search = search

	win.content = CreateFrame("Frame", nil, win)
	win.content:SetWidth(INNER_W)
	win.content:SetHeight(10)

	win.bagRow = CreateFrame("Frame", nil, win)
	win.bagRow:SetPoint("TOPLEFT", PAD, -32)
	win.bagRow:SetSize(INNER_W, S)
	win.bagSlots = {}
	for bag = 1, LAST_BAG do win.bagSlots[#win.bagSlots + 1] = bagSlot(bag, (bag - 1) * (S + GAP)) end
	-- The reagent bag, a little apart from the others.
	if HAS_REAGENT then win.bagSlots[#win.bagSlots + 1] = bagSlot(REAGENT_BAG, LAST_BAG * (S + GAP) + 10) end
	local toggle = CreateFrame("Button", nil, win)
	toggle:SetSize(22, 22)
	toggle:SetPoint("RIGHT", search, "LEFT", -10, 0)
	toggle:SetNormalTexture("Interface\\Buttons\\Button-Backpack-Up")
	toggle:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	toggle:SetScript("OnClick", function()
		if InCombatLockdown() then return end
		db().bagSlotsShown = not bagsShown()
		placeContent()
		layout()
	end)
	toggle:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(bagsShown() and "Hide your bags" or "Show your bags")
		GameTooltip:AddLine("A row of your bags (and your reagent bag), to swap one for a bigger one.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
	placeContent()
	paintBagSlots()

	win.money = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	win.money:SetPoint("BOTTOMRIGHT", -PAD, 12)
	if C_Container.SortBags then
		local sort = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
		sort:SetSize(60, 20)
		sort:SetPoint("BOTTOMLEFT", PAD, 8)
		sort:SetText("Sort")
		sort:SetScript("OnClick", function() if not InCombatLockdown() then pcall(C_Container.SortBags) end end)
		sort:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine("Tidy the bags themselves")
			GameTooltip:AddLine("This window sorts itself. Sort also moves the items in your real bags.", 1, 1, 1, true)
			GameTooltip:Show()
		end)
		sort:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	win.hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	win.hint:SetPoint("BOTTOMLEFT", PAD + (C_Container.SortBags and 68 or 0), 13)
	win.hint:SetText("Alt-click: Perma")

	win.Layout = layout
	win:SetScript("OnShow", function()
		placeWin()
		paintBagSlots()
		win.money:SetText(moneyText())
		if dirty and not InCombatLockdown() then layout() else repaint() end
	end)
	win:SetScript("OnHide", function()
		-- Closing the bags means you've seen what's new, as in the game's own bags.
		if C_NewItems and C_NewItems.ClearAll then pcall(C_NewItems.ClearAll) end
		closeBlizzard()
	end)
end

---------------------------------------------------------------------------
-- Follow the game's bags: they still open and close as always, but inside a
-- hidden frame. This window shows while any of them is open.
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
		-- Only the backpack and bags: the bank's own bags keep their windows.
		if f:IsShown() and (f == ContainerFrameCombinedBags or isMine(id)) then return true end
	end
	return false
end

local syncing = false
local function sync()
	if not win or syncing then return end
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
	if blizzOpen() and CloseAllBags then
		syncing = true
		pcall(CloseAllBags)
		syncing = false
	end
end

local installed = false
local function install()
	if installed or not on() or InCombatLockdown() then return end
	installed = true
	build()
	-- The same frames also show bank bags: each time one opens, it goes in the
	-- hidden frame for your own bags and back on screen for a bank bag.
	for _, f in ipairs(blizzFrames()) do
		if f == ContainerFrameCombinedBags then
			f:SetParent(hidden)
		else
			local function place(self)
				local id = self:GetID()
				local mine = isMine(id)
				local want = mine and hidden or UIParent
				if self:GetParent() ~= want then self:SetParent(want) end
			end
			place(f)
			hooksecurefunc(f, "Show", place)
			hooksecurefunc(f, "SetID", place)
		end
	end
	for _, fn in ipairs({ "OpenAllBags", "CloseAllBags", "ToggleAllBags", "OpenBackpack", "CloseBackpack",
		"ToggleBackpack", "ToggleBag", "OpenBag", "CloseBag" }) do
		if type(_G[fn]) == "function" then hooksecurefunc(fn, sync) end
	end
	layout()
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN",
	"PLAYER_REGEN_ENABLED", "PLAYER_MONEY", "GET_ITEM_INFO_RECEIVED", "QUEST_LOG_UPDATE", "BAG_CONTAINER_UPDATE" }) do
	pcall(ev.RegisterEvent, ev, e)
end
pcall(ev.RegisterEvent, ev, "PLAYER_ENTERING_WORLD")
local pendingLayout = false
-- For a few seconds after login or a reload the game can flag everything you
-- carry as new. Nothing is new then: clear it while the bags fill in.
local loginQuietUntil = 0
local function clearNew() if C_NewItems and C_NewItems.ClearAll then pcall(C_NewItems.ClearAll) end end
ev:SetScript("OnEvent", function(_, event, isLogin, isReload)
	if event == "PLAYER_ENTERING_WORLD" then
		if isLogin or isReload then
			loginQuietUntil = GetTime() + 5
			clearNew()
		end
		return
	end
	if event == "BAG_UPDATE_DELAYED" and GetTime() < loginQuietUntil then clearNew() end
	if event == "PLAYER_LOGIN" then install() return end
	if not win then
		if event == "PLAYER_REGEN_ENABLED" then install() end
		return
	end
	if event == "PLAYER_MONEY" then
		win.money:SetText(moneyText())
		return
	end
	if event == "BAG_CONTAINER_UPDATE" or event == "BAG_UPDATE_DELAYED" then paintBagSlots() end
	if event == "ITEM_LOCK_CHANGED" or event == "BAG_UPDATE_COOLDOWN" then
		if win:IsShown() then repaint() end
		return
	end
	if event == "GET_ITEM_INFO_RECEIVED" or event == "QUEST_LOG_UPDATE" then
		if not win:IsShown() then dirty = true return end
	end
	dirty = true
	if not win:IsShown() then return end
	if InCombatLockdown() then repaint() return end
	if pendingLayout then return end
	pendingLayout = true
	C_Timer.After(0.05, function()
		pendingLayout = false
		if win:IsShown() and dirty and not InCombatLockdown() then layout() end
	end)
end)
