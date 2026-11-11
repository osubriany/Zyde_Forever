-- Window: the GearAdvisor planner (/ga, /ga plan or the minimap button). Three tabs:
--   My Gear   what you wear, each slot's value, and the best upgrade known for it
--   Dungeons  every dungeon with loot data; click one to see the upgrades it drops for you
--   By Slot   the best upgrades known for each slot, from your bags and from dungeons
-- Only our own frames: nothing here touches Blizzard's frames (see the taint note in Auction.lua).
local _, zyde = ...
zyde.GA = zyde.GA or {}
local ns = zyde.GA

local Window = {}
ns.Window = Window

local W, H, ROW_H = 560, 470, 22
local ROW_W = W - 56
local MAX_PER_SLOT = 3   -- upgrades listed per slot on the By Slot tab

-- Slots in character-sheet order. Rings and trinkets are one group each.
local GROUPS = {
	{ slots = { 1 }, name = "Head" }, { slots = { 2 }, name = "Neck" }, { slots = { 3 }, name = "Shoulder" },
	{ slots = { 15 }, name = "Back" }, { slots = { 5 }, name = "Chest" }, { slots = { 9 }, name = "Wrist" },
	{ slots = { 10 }, name = "Hands" }, { slots = { 6 }, name = "Waist" }, { slots = { 7 }, name = "Legs" },
	{ slots = { 8 }, name = "Feet" }, { slots = { 11, 12 }, name = "Rings" }, { slots = { 13, 14 }, name = "Trinkets" },
	{ slots = { 16 }, name = "Main hand" }, { slots = { 17 }, name = "Off hand" }, { slots = { 18 }, name = "Ranged" },
}
local GROUP_OF = {}
for i, g in ipairs(GROUPS) do for _, s in ipairs(g.slots) do GROUP_OF[s] = i end end

local frame, tab = nil, "gear"
local expanded = {}   -- dungeon name -> true when its upgrades are shown
local retries = 0

---------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------
local function idOf(link) return type(link) == "string" and tonumber(link:match("item:(%d+)")) end

local function iconOf(link)
	local id = idOf(link)
	if not id then return nil end
	return (C_Item and C_Item.GetItemIconByID and ns.safe(C_Item.GetItemIconByID, id))
		or (GetItemIcon and ns.safe(GetItemIcon, id))
end

-- Item name in its quality colour.
local function nameOf(info)
	if not info then return "?" end
	local hex
	if info.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[info.quality] then
		hex = ITEM_QUALITY_COLORS[info.quality].hex
	end
	return (hex or "|cffffffff") .. (info.name or "?") .. "|r"
end

local function pct(p) return ("%s%.1f%%"):format(p >= 0 and "+" or "", p) end

local function kindColour(kind)
	if kind == "future" then return "|cff66ccff" end
	return "|cff33ff33"
end

---------------------------------------------------------------------------------------------
-- Data: every known upgrade, by dungeon and by slot. Kept until gear, level, talents,
-- settings or bags change.
---------------------------------------------------------------------------------------------
local cache

local function collect()
	if cache then return cache end
	local c = { dungeons = {}, groups = {}, loading = 0 }
	local seen = {}   -- group -> itemID -> entry, so an item from several places is listed once
	local function add(r, source)
		local g = GROUP_OF[r.slot]
		if not g or not r.info then return end
		c.groups[g] = c.groups[g] or {}
		seen[g] = seen[g] or {}
		local e = seen[g][r.info.itemID]
		if e then
			e.sources[#e.sources + 1] = source
		else
			e = { result = r, sources = { source } }
			seen[g][r.info.itemID] = e
			table.insert(c.groups[g], e)
		end
	end

	-- Your bags.
	for _, info in ipairs(zyde.Bags.items()) do   -- Zyde's shared bag list (Bags.lua)
		local link = info.hyperlink
		if link and ns.Stats.isGear(link) then
			local ok, r = pcall(ns.Score.compare, link)
			if ok and r then
				if r.kind == "loading" then c.loading = c.loading + 1
				elseif r.kind == "upgrade" or r.kind == "future" then add(r, "in your bags") end
			end
		end
	end

	-- Dungeons.
	local ok, list = pcall(ns.Loot.dungeons)
	for _, d in ipairs(ok and list or {}) do
		local ok2, ups, loading = pcall(ns.Loot.upgradesIn, d.name)
		ups = ok2 and ups or {}
		c.loading = c.loading + ((ok2 and loading) or 0)
		c.dungeons[#c.dungeons + 1] = { d = d, ups = ups }
		for _, u in ipairs(ups) do add(u.result, u.boss.name .. " (" .. d.name .. ")") end
	end

	for _, entries in pairs(c.groups) do
		table.sort(entries, function(a, b) return a.result.pct > b.result.pct end)
	end
	if c.loading == 0 then cache = c end
	return c
end

---------------------------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------------------------
local rows, used = {}, 0

local function rowEnter(row)
	if not row.link then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	pcall(GameTooltip.SetHyperlink, GameTooltip, row.link)
	GameTooltip:Show()
end

local function rowClick(row)
	if row.link then
		if IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
			local _, full = GetItemInfo(row.link)
			ChatEdit_InsertLink(full or row.link)
			return
		elseif IsModifiedClick and IsModifiedClick("DRESSUP") and DressUpItemLink then
			DressUpItemLink(row.link)
			return
		end
	end
	if row.onClick then row.onClick() end
end

local function newRow(parent)
	local r = CreateFrame("Button", nil, parent)
	r:SetSize(ROW_W, ROW_H)
	r:RegisterForClicks("LeftButtonUp")
	local hl = r:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(r)
	hl:SetColorTexture(1, 1, 1, 0.08)
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(18, 18)
	r.left = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	r.left:SetJustifyH("LEFT")
	r.left:SetWordWrap(false)
	r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.right:SetPoint("RIGHT", -4, 0)
	r.right:SetJustifyH("RIGHT")
	r.right:SetWordWrap(false)
	r.left:SetPoint("RIGHT", r.right, "LEFT", -8, 0)
	r:SetScript("OnEnter", rowEnter)
	r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	r:SetScript("OnClick", rowClick)
	return r
end

-- spec: { left, right, link, icon (true = from link), indent, header, onClick }
local function addRow(spec)
	used = used + 1
	local r = rows[used]
	if not r then
		r = newRow(frame.content)
		rows[used] = r
	end
	r:ClearAllPoints()
	r:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -(used - 1) * ROW_H)
	local x = 4 + (spec.indent or 0)
	local tex = spec.icon and iconOf(spec.link)
	r.icon:ClearAllPoints()
	r.icon:SetPoint("LEFT", x, 0)
	if tex then
		r.icon:SetTexture(tex)
		r.icon:Show()
		x = x + 22
	else
		r.icon:Hide()
	end
	r.left:ClearAllPoints()
	r.left:SetPoint("LEFT", x, 0)
	r.left:SetPoint("RIGHT", r.right, "LEFT", -8, 0)
	r.left:SetFontObject(spec.header and "GameFontNormal" or "GameFontHighlight")
	r.left:SetText(spec.left or "")
	r.right:SetText(spec.right or "")
	r.link, r.onClick = spec.link, spec.onClick
	r:Show()
	return r
end

local function blank() addRow({}) end

---------------------------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------------------------
local function bestFor(c, g)
	local e = c.groups[g] and c.groups[g][1]
	if e then return kindColour(e.result.kind) .. "next " .. pct(e.result.pct) .. "|r" end
end

local function showGear(ctx, c)
	local target = ctx.targetSetting == "auto" and ("auto: " .. (ctx.targetGap == 3 and "raid" or "dungeon")) or ctx.targetSetting
	addRow({ header = true, left = ("%s, level %d"):format(ctx.profile.label or ctx.profileKey, ctx.level),
		right = ("hit %.1f%% of %.1f%% cap (%s)"):format(ctx.hitHave or 0, ctx.hitCap or 0, tostring(target)) })
	blank()
	local kit = math.max(ctx.kitScore or 0, 1)
	for g, group in ipairs(GROUPS) do
		for _, slot in ipairs(group.slots) do
			local info = ctx.equipped[slot]
			local label = "|cffaaaaaa" .. (ns.Score.SLOT_NAMES[slot] or group.name) .. ":|r "
			if info then
				local _, lin, hit = ns.Score.parts(info, slot, ctx)
				local hitVal = hit > 0 and ns.Score.hitValue(ctx.hitHave - hit, ctx.hitHave, ctx) or 0
				local value = lin + hitVal
				local right = ("%.0f pts (%.0f%%)"):format(value, value / kit * 100)
				local nxt = slot == group.slots[1] and bestFor(c, g)
				addRow({ left = label .. nameOf(info), right = nxt and (right .. "  " .. nxt) or right,
					link = info.link, icon = true })
			else
				local nxt = slot == group.slots[1] and bestFor(c, g)
				addRow({ left = label .. "|cff777777(empty)|r", right = nxt or "" })
			end
		end
	end
	blank()
	addRow({ left = "|cff999999pts = value to you in attack-power equivalents. \"next\" = best upgrade known (By Slot tab).|r" })
end

local function inRange(d, level)
	if not d.minLevel or not d.maxLevel then return nil end
	return level >= d.minLevel - 2 and level <= d.maxLevel
end

local function showDungeons(ctx, c)
	if #c.dungeons == 0 then
		local s = ns.Loot.status()
		addRow({ header = true, left = "No dungeon loot data yet." })
		addRow({ left = "AtlasLoot: " .. tostring(s.atlas) .. "." })
		addRow({ left = "Install AtlasLoot (Forever version) for full drop tables," })
		addRow({ left = "or kill bosses: GearAdvisor records the gear they drop." })
		return
	end
	local list = {}
	for _, e in ipairs(c.dungeons) do list[#list + 1] = e end
	local rank = function(e) local r = inRange(e.d, ctx.level); return r and 0 or (r == nil and 1 or 2) end
	table.sort(list, function(a, b)
		local ra, rb = rank(a), rank(b)
		if ra ~= rb then return ra < rb end
		if (a.d.minLevel or 0) ~= (b.d.minLevel or 0) then return (a.d.minLevel or 0) < (b.d.minLevel or 0) end
		return a.d.name < b.d.name
	end)
	addRow({ header = true, left = "Dungeons (yours to run first). Click one to list its upgrades.",
		right = c.loading > 0 and "|cffaaaaaaloading items...|r" or nil })
	for _, e in ipairs(list) do
		local d, ups = e.d, e.ups
		local open = expanded[d.name]
		local levels = d.minLevel and (" |cffaaaaaa(" .. d.minLevel .. "-" .. (d.maxLevel or "?") .. ")|r") or ""
		local col = inRange(d, ctx.level) == false and "|cff888888" or "|cffffffff"
		local best = ups[1] and (kindColour(ups[1].result.kind) .. "best " .. pct(ups[1].result.pct) .. "|r") or ""
		addRow({
			left = (open and "|cffffd100-|r " or "|cffffd100+|r ") .. col .. d.name .. "|r" .. levels,
			right = (#ups > 0 and (#ups .. (#ups == 1 and " upgrade  " or " upgrades  ")) or "|cff888888no upgrades|r") .. best,
			onClick = function() expanded[d.name] = not expanded[d.name]; Window.refresh() end,
		})
		if open then
			if #ups == 0 then addRow({ indent = 16, left = "|cff888888Nothing here beats what you wear.|r" }) end
			for _, u in ipairs(ups) do
				local r = u.result
				addRow({ indent = 16, icon = true, link = r.info.link, left = nameOf(r.info),
					right = kindColour(r.kind) .. pct(r.pct) .. "|r  |cffaaaaaa" .. u.boss.name .. "|r" })
			end
		end
	end
end

local function showSlots(ctx, c)
	addRow({ header = true, left = "Best upgrades known for each slot (bags and dungeons).",
		right = c.loading > 0 and "|cffaaaaaaloading items...|r" or nil })
	for g, group in ipairs(GROUPS) do
		local entries = c.groups[g] or {}
		local now = {}
		for _, s in ipairs(group.slots) do
			local info = ctx.equipped[s]
			now[#now + 1] = info and nameOf(info) or "|cff777777empty|r"
		end
		addRow({ header = true, left = group.name, right = "|cffaaaaaanow:|r " .. table.concat(now, ", ") })
		if #entries == 0 then
			addRow({ indent = 16, left = "|cff888888Nothing known.|r" })
		end
		for i = 1, math.min(#entries, MAX_PER_SLOT) do
			local e = entries[i]
			local r = e.result
			local src = e.sources[1] .. (#e.sources > 1 and (" +" .. (#e.sources - 1) .. " more") or "")
			local later = r.later and (" |cff66ccff(level " .. r.later .. ")|r") or ""
			addRow({ indent = 16, icon = true, link = r.info.link, left = nameOf(r.info) .. later,
				right = kindColour(r.kind) .. pct(r.pct) .. "|r  |cffaaaaaa" .. src .. "|r" })
		end
	end
end

---------------------------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------------------------
local TABS = { { key = "gear", label = "My Gear" }, { key = "dungeons", label = "Dungeons" }, { key = "slots", label = "By Slot" } }

function Window.refresh()
	if not frame or not frame:IsShown() then return end
	for _, b in ipairs(frame.tabs) do
		if b.key == tab then b:LockHighlight() else b:UnlockHighlight() end
	end
	used = 0
	local ctx = ns.Player.context()
	if not ctx.profile then
		addRow({ header = true, left = "GearAdvisor can't score gear for this character." })
		addRow({ left = tostring(ctx.reason or "") })
	else
		local c = collect()
		if tab == "gear" then showGear(ctx, c)
		elseif tab == "dungeons" then showDungeons(ctx, c)
		else showSlots(ctx, c) end
		-- Items the game hasn't sent yet: look again shortly.
		if c.loading > 0 and retries < 10 then
			retries = retries + 1
			C_Timer.After(1, Window.refresh)
		elseif c.loading == 0 then
			retries = 0
		end
	end
	for i = used + 1, #rows do rows[i]:Hide() end
	frame.content:SetHeight(math.max(used * ROW_H, 1))
end

local function make()
	if frame then return end
	local ok, made = pcall(CreateFrame, "Frame", "GearAdvisorWindow", UIParent, "BackdropTemplate")
	local f = ok and made or CreateFrame("Frame", "GearAdvisorWindow", UIParent)
	f:SetSize(W, H)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, rel, x, y = self:GetPoint()
		ns.db.windowPos = { point, rel, x, y }
	end)
	local pos = ns.db.windowPos
	if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint("CENTER") end

	if f.SetBackdrop then
		f:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		f:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
		f:SetBackdropBorderColor(0.6, 0.6, 0.6)
	else
		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(f)
		bg:SetColorTexture(0.05, 0.05, 0.05, 0.95)
	end

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 14, -12)
	title:SetText("GearAdvisor")
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	f.tabs = {}
	local prev
	for _, t in ipairs(TABS) do
		local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		b:SetSize(100, 22)
		if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 14, -38) end
		b:SetText(t.label)
		b.key = t.key
		b:SetScript("OnClick", function() tab = t.key; ns.db.windowTab = t.key; Window.refresh() end)
		f.tabs[#f.tabs + 1] = b
		prev = b
	end

	local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 12, -68)
	scroll:SetPoint("BOTTOMRIGHT", -32, 30)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(ROW_W, 1)
	scroll:SetScrollChild(content)
	f.content = content

	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("BOTTOMLEFT", 14, 11)
	hint:SetText("Hover an item for details. Shift-click links it in chat, Ctrl-click previews it.")

	f:SetScript("OnShow", function() retries = 0; Window.refresh() end)
	f:Hide()
	if UISpecialFrames then table.insert(UISpecialFrames, "GearAdvisorWindow") end   -- Esc closes it
	frame = f
	tab = ns.db.windowTab or tab
end

function Window.show(which)
	make()
	if which then tab = which end
	if frame:IsShown() then Window.refresh() else frame:Show() end
end

function Window.toggle()
	make()
	if frame:IsShown() then frame:Hide() else frame:Show() end
end

---------------------------------------------------------------------------------------------
-- Minimap button (drag it round the minimap; /ga minimap hides or shows it)
---------------------------------------------------------------------------------------------
local button

local function placeButton()
	if not button then return end
	local a = math.rad(ns.db.minimapAngle or 200)
	local r = (Minimap:GetWidth() / 2) + 10
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function makeButton()
	if button or not Minimap then return end
	local b = CreateFrame("Button", "GearAdvisorMinimapButton", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetSize(20, 20)
	bg:SetPoint("TOPLEFT", 7, -5)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetTexture("Interface\\Icons\\INV_Chest_Chain_05")
	icon:SetSize(17, 17)
	icon:SetPoint("TOPLEFT", 7, -6)
	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	b:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then Window.show("dungeons") else Window.toggle() end
	end)
	b:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local cx, cy = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			ns.db.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
			placeButton()
		end)
	end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("GearAdvisor")
		GameTooltip:AddLine("Click: your gear and upgrades", 1, 1, 1)
		GameTooltip:AddLine("Right-click: dungeon upgrades", 1, 1, 1)
		GameTooltip:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button = b
	placeButton()
end

function Window.setMinimap(on)
	ns.db.minimap = on
	if on then
		makeButton()
		if button then button:Show() end
	elseif button then
		button:Hide()
	end
end

---------------------------------------------------------------------------------------------
-- Keeping it current
---------------------------------------------------------------------------------------------
ns.onChange(function()
	cache = nil
	Window.refresh()
end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
pcall(ev.RegisterEvent, ev, "BAG_UPDATE_DELAYED")
local bagPending
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		if ns.db and ns.db.minimap ~= false then pcall(makeButton) end
	elseif event == "BAG_UPDATE_DELAYED" and not bagPending then
		bagPending = true
		C_Timer.After(0.5, function()
			bagPending = nil
			cache = nil
			if frame and frame:IsShown() then Window.refresh() end
		end)
	end
end)
