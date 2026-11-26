-- Zyde_Forever: a radial ring of your own spells, macros and items.
--   Hold the ring key: the ring opens around the cursor. Move the mouse toward
--   a slot and let go of the key to use it. Let go near the middle to cancel.
--   Set the key in Options > Keybindings > Zyde Forever > "Radial ring (hold)".
--   /zyde ring (or the Set up button in /zyde) opens the setup window: drag a
--   spell, macro or item onto a slot, right-click a slot to empty it.
--   Each character has its own ring. The key can be the same on all of them.
--
-- Casting has to come from a secure click, so the key is a secure action
-- button. Its press opens the ring at the cursor; its release works out the
-- slot from where the mouse went (the secure code can read that) and casts it
-- on the release ("typerelease", the same thing the world marker squares use).
-- The icons and the highlight are a plain frame inside the ring, so they can
-- be drawn during a fight. The slots themselves only change out of combat.

local ADDON, ns = ...

local P = "|cff66ccffZyde_Forever|r: "
local MAX = 12
local ICON = 38
local DEAD = 22 -- let go closer than this to the middle: nothing happens
local QMARK = "Interface\\Icons\\INV_Misc_QuestionMark"

local function on() return ns.F("radial") end
-- Each character has its own ring: ZydeForeverDB.radialByChar["Name-Realm"].
-- The ring from before this was one ring for every character
-- (ZydeForeverDB.radial). It goes to the first character that knows all of its
-- spells, and is then removed, so a warrior never gets the hunter's ring.
local function charKey()
	local name = UnitName("player")
	local realm = GetRealmName and GetRealmName()
	if ns.isSecret(name) or type(name) ~= "string" or name == "" then return nil end
	if ns.isSecret(realm) or type(realm) ~= "string" then realm = "" end
	return name .. "-" .. realm
end

local function knowsSpell(id)
	if type(id) ~= "number" then return false end
	for _, f in ipairs({ IsPlayerSpell, IsSpellKnown, C_SpellBook and C_SpellBook.IsSpellKnown }) do
		if f then
			local v = ns.safe(f, id)
			if v and not ns.isSecret(v) then return true end
		end
	end
	return false
end

local fallback = { slots = {} } -- (before the character's name is known)
local function db()
	ZydeForeverDB = ZydeForeverDB or {}
	local key = charKey()
	if not key then return fallback end
	ZydeForeverDB.radialByChar = ZydeForeverDB.radialByChar or {}
	local mine = ZydeForeverDB.radialByChar[key]
	if not mine then
		mine = { slots = {} }
		ZydeForeverDB.radialByChar[key] = mine
	end
	mine.slots = mine.slots or {}
	-- Still empty: take the old shared ring if its spells are this character's.
	-- (Asked again later too, in case the spellbook wasn't loaded the first time.)
	local old = ZydeForeverDB.radial
	if #mine.slots == 0 and type(old) == "table" and type(old.slots) == "table" and #old.slots > 0 then
		local fits = true
		for _, s in ipairs(old.slots) do
			if s.kind == "spell" and not knowsSpell(s.id) then fits = false break end
		end
		if fits then
			mine.slots = old.slots
			ZydeForeverDB.radial = nil
		end
	end
	return mine
end
local function slots() return db().slots end

local function radiusFor(n) return math.max(76, math.floor(n * (ICON + 8) / (2 * math.pi) + 0.5)) end

-- Slot i of n: clockwise from the top. Returns a unit vector (x right, y up).
local function dir(i, n)
	local a = (i - 1) / n * 2 * math.pi
	return math.sin(a), math.cos(a)
end

---------------------------------------------------------------------------
-- What a slot holds: { kind = "spell", id, name } | { kind = "macro", name } | { kind = "item", id }
---------------------------------------------------------------------------
local function spellName(id)
	if C_Spell and C_Spell.GetSpellName then
		local n = ns.safe(C_Spell.GetSpellName, id)
		if type(n) == "string" then return n end
	end
	if GetSpellInfo then
		local n = ns.safe(GetSpellInfo, id)
		if type(n) == "string" then return n end
	end
end

local function iconOf(s)
	if not s then return nil end
	local tex
	if s.kind == "spell" then
		tex = (C_Spell and C_Spell.GetSpellTexture and ns.safe(C_Spell.GetSpellTexture, s.id or s.name))
			or (GetSpellTexture and ns.safe(GetSpellTexture, s.id or s.name))
	elseif s.kind == "macro" then
		local _, t = ns.safe(GetMacroInfo, s.name)
		tex = t
	elseif s.kind == "item" then
		tex = (C_Item and C_Item.GetItemIconByID and ns.safe(C_Item.GetItemIconByID, s.id))
			or (GetItemIcon and ns.safe(GetItemIcon, s.id))
	end
	if ns.isSecret(tex) then return QMARK end
	return tex or QMARK
end

local function labelOf(s)
	if not s then return "" end
	if s.kind == "spell" then return s.name or spellName(s.id) or ("Spell " .. tostring(s.id)) end
	if s.kind == "macro" then return s.name or "Macro" end
	if s.kind == "item" then
		local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
		local n = getInfo and ns.safe(getInfo, s.id)
		return type(n) == "string" and n or ("Item " .. tostring(s.id))
	end
	return ""
end

-- The secure action for a slot: button type and the value its attribute takes.
local function actionOf(s)
	if s.kind == "spell" then return "spell", s.name or spellName(s.id) or s.id end
	if s.kind == "macro" then return "macro", s.name end
	if s.kind == "item" then return "item", "item:" .. tostring(s.id) end
end

-- Whatever is on the cursor, as a slot. nil and a reason when it can't go in one.
local function slotFromCursor()
	local kind, a, b, c = GetCursorInfo()
	if not kind then return nil end
	if kind == "spell" then
		local id = type(c) == "number" and c or nil
		if not id and GetSpellBookItemInfo then
			local _, sid = ns.safe(GetSpellBookItemInfo, a, b)
			id = type(sid) == "number" and sid or nil
		end
		if not id then return nil, "couldn't read that spell" end
		return { kind = "spell", id = id, name = spellName(id) }
	elseif kind == "macro" then
		local name = ns.safe(GetMacroInfo, a)
		if type(name) ~= "string" then return nil, "couldn't read that macro" end
		return { kind = "macro", name = name }
	elseif kind == "item" then
		if type(a) ~= "number" then return nil, "couldn't read that item" end
		return { kind = "item", id = a }
	end
	return nil, "only spells, macros and items go on the ring"
end

---------------------------------------------------------------------------
-- The ring: a protected frame the key shows at the cursor, with a plain
-- frame inside it for the icons.
---------------------------------------------------------------------------
local ring = CreateFrame("Frame", "ZydeForeverRadialRing", UIParent, "SecureHandlerBaseTemplate")
ring:SetSize(2, 2)
ring:SetFrameStrata("DIALOG")
ring:SetPoint("CENTER")
ring:EnableMouse(false)
ring:Hide()

local look = CreateFrame("Frame", nil, ring)
look:SetPoint("CENTER")
look:SetSize(2 * (radiusFor(MAX) + ICON), 2 * (radiusFor(MAX) + ICON))

-- Everything round is a plain square texture cut by this circle.
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local function circle(tex, owner)
	local m = owner:CreateMaskTexture()
	m:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	m:SetAllPoints(tex)
	tex:AddMaskTexture(m)
	return m
end
local function disc(owner, layer, sub)
	local t = owner:CreateTexture(nil, layer, nil, sub)
	t:SetTexture("Interface\\Buttons\\WHITE8X8")
	circle(t, owner)
	return t
end

local function classColor()
	local _, class = UnitClass("player")
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then return c.r, c.g, c.b end
	return 0.69, 0.35, 1
end

-- The backdrop: a faint disc in your class color under the icons, a darker
-- hub in the middle (let go there to cancel).
look.track = disc(look, "BACKGROUND", 0)
look.track:SetPoint("CENTER")
look.trackEdge = disc(look, "BACKGROUND", -1)
look.trackEdge:SetPoint("CENTER")
look.hub = disc(look, "BACKGROUND", 2)
look.hub:SetPoint("CENTER")
look.hub:SetSize(DEAD * 2, DEAD * 2)
look.hubEdge = disc(look, "BACKGROUND", 1)
look.hubEdge:SetPoint("CENTER")
look.hubEdge:SetSize(DEAD * 2 + 4, DEAD * 2 + 4)

-- From the middle toward the slot you're aiming at.
if look.CreateLine then
	look.pointer = look:CreateLine(nil, "BORDER")
	look.pointer:SetThickness(3)
	look.pointer:SetColorTexture(1, 0.82, 0.25, 0.7)
	look.pointer:SetStartPoint("CENTER", look, 0, 0)
	look.pointer:SetEndPoint("CENTER", look, 0, 0)
	look.pointer:Hide()
end

look.name = look:CreateFontString(nil, "OVERLAY")
if not look.name:SetFont("Fonts\\ARIALN.TTF", 13, "OUTLINE") then look.name:SetFontObject("GameFontNormal") end
look.name:SetPoint("CENTER")
look.name:SetTextColor(1, 0.84, 0.35)
-- The name sits on a dark label under the ring, not in the middle: a long
-- name ("Mithril Head Trout") ran over the icons beside it.
look.nameBg = look:CreateTexture(nil, "BORDER")
look.nameBg:SetColorTexture(0, 0, 0, 0.75)
look.nameBg:SetPoint("TOPLEFT", look.name, "TOPLEFT", -6, 3)
look.nameBg:SetPoint("BOTTOMRIGHT", look.name, "BOTTOMRIGHT", 6, -3)
look.nameBg:Hide()

local function paintBackdrop(r)
	local cr, cg, cb = classColor()
	local size = 2 * (r + ICON * 0.8)
	look.track:SetSize(size, size)
	look.track:SetVertexColor(cr, cg, cb, 0.16)
	look.trackEdge:SetSize(size + 4, size + 4)
	look.trackEdge:SetVertexColor(cr, cg, cb, 0.35)
	look.hub:SetVertexColor(0, 0, 0, 0.75)
	look.hubEdge:SetVertexColor(cr, cg, cb, 0.5)
end

local icons = {}
local function iconFrame(i)
	if icons[i] then return icons[i] end
	local f = CreateFrame("Frame", nil, look)
	f:SetSize(ICON, ICON)
	-- Soft glow behind the slot you're aiming at.
	f.glow = f:CreateTexture(nil, "BACKGROUND", nil, -2)
	f.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	f.glow:SetBlendMode("ADD")
	f.glow:SetPoint("CENTER")
	f.glow:SetSize(ICON * 2.1, ICON * 2.1)
	f.glow:SetVertexColor(1, 0.8, 0.3)
	f.glow:Hide()
	-- Round icon on a round border.
	f.border = disc(f, "BACKGROUND", 0)
	f.border:SetPoint("TOPLEFT", -3, 3)
	f.border:SetPoint("BOTTOMRIGHT", 3, -3)
	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetAllPoints()
	f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	circle(f.tex, f)
	-- Cooldown: the clock sweep with the seconds left, drawn by the game.
	f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	f.cd:SetAllPoints()
	if f.cd.SetSwipeTexture then pcall(f.cd.SetSwipeTexture, f.cd, CIRCLE) end
	if f.cd.SetUseCircularEdge then pcall(f.cd.SetUseCircularEdge, f.cd, true) end
	if f.cd.SetHideCountdownNumbers then f.cd:SetHideCountdownNumbers(false) end
	if f.cd.SetDrawEdge then f.cd:SetDrawEdge(false) end
	icons[i] = f
	return f
end

local current = {} -- the slots the ring was last built from (compact list)

local function paintHover(pick)
	for i, f in ipairs(icons) do
		if f:IsShown() then
			local hot = i == pick
			if hot then f.border:SetVertexColor(1, 0.82, 0.2, 1) else f.border:SetVertexColor(0.12, 0.12, 0.14, 1) end
			f.glow:SetShown(hot)
			-- Bigger in place (SetScale would also push it further from the middle).
			f:SetSize(hot and ICON * 1.2 or ICON, hot and ICON * 1.2 or ICON)
			f.hot = hot
		end
	end
	local f = pick and icons[pick]
	if look.pointer then
		if f and f.vx then
			look.pointer:SetEndPoint("CENTER", look, f.vx * (f.r - ICON * 0.7), f.vy * (f.r - ICON * 0.7))
			look.pointer:Show()
		else
			look.pointer:Hide()
		end
	end
	look.hubEdge:SetVertexColor(pick and 1 or 0.6, pick and 0.82 or 0.6, pick and 0.25 or 0.6, pick and 0.9 or 0.5)
	look.name:SetText(pick and labelOf(current[pick]) or "")
	look.nameBg:SetShown(pick ~= nil)
end

---------------------------------------------------------------------------
-- Ready or not: cooldown sweep, and a tint when a spell can't be used now
-- (gray), lacks mana (blue) or the target is out of range (red). Anything
-- the game hides in a fight is left plain.
---------------------------------------------------------------------------
local function plain(v) if ns.isSecret(v) then return nil end return v end

local function spellOf(s)
	if s.kind == "spell" then return s.name or s.id end
	if s.kind == "macro" and GetMacroSpell then
		local id = plain(ns.safe(GetMacroSpell, s.name))
		if id then return id end
	end
end
local function itemOf(s)
	if s.kind == "item" then return s.id end
	if s.kind == "macro" and GetMacroItem then
		local _, link = ns.safe(GetMacroItem, s.name)
		link = plain(link)
		local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
		if id then return id end
	end
end

local function cooldownOf(s)
	local spell, item = spellOf(s), itemOf(s)
	if spell then
		if C_Spell and C_Spell.GetSpellCooldown then
			local info = ns.safe(C_Spell.GetSpellCooldown, spell)
			if type(info) == "table" then return info.startTime, info.duration end
		end
		if GetSpellCooldown then return ns.safe(GetSpellCooldown, spell) end
	elseif item then
		local f = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
		if f then return ns.safe(f, item) end
	end
end

local function stateOf(s)
	local spell, item = spellOf(s), itemOf(s)
	if spell then
		local isUsable = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell
		local usable, noMana = nil, nil
		if isUsable then usable, noMana = ns.safe(isUsable, spell) end
		usable, noMana = plain(usable), plain(noMana)
		if noMana then return "mana" end
		if usable == false then return "no" end
		if UnitExists("target") then
			local inRange = (C_Spell and C_Spell.IsSpellInRange) or IsSpellInRange
			local r = inRange and plain(ns.safe(inRange, spell, "target"))
			if r == false or r == 0 then return "range" end
		end
	elseif item then
		local isUsable = (C_Item and C_Item.IsUsableItem) or IsUsableItem
		local usable = isUsable and plain(ns.safe(isUsable, item))
		if usable == false then return "no" end
		local count = (C_Item and C_Item.GetItemCount) or GetItemCount
		local n = count and plain(ns.safe(count, item))
		if n == 0 then return "no" end
	end
	return "ok"
end

local function paintReady()
	for i, s in ipairs(current) do
		local f = icons[i]
		if f and f:IsShown() then
			local start, dur = cooldownOf(s)
			if start and dur then
				local d = plain(dur)
				-- (the global cooldown alone isn't worth a sweep)
				if d and d <= 1.6 then f.cd:Clear() else pcall(f.cd.SetCooldown, f.cd, start, dur) end
			else
				f.cd:Clear()
			end
			local st = stateOf(s)
			f.tex:SetDesaturated(st == "no")
			if st == "range" then f.tex:SetVertexColor(1, 0.35, 0.35)
			elseif st == "mana" then f.tex:SetVertexColor(0.45, 0.55, 1)
			elseif st == "no" then f.tex:SetVertexColor(0.6, 0.6, 0.6)
			else f.tex:SetVertexColor(1, 1, 1) end
		end
	end
end

-- Same pick as the secure code: the slot whose direction is closest to the mouse's.
local function pickAt(dx, dy, n)
	if dx * dx + dy * dy < DEAD * DEAD then return nil end
	local best, pick = -2, nil
	for i = 1, n do
		local vx, vy = dir(i, n)
		local d = dx * vx + dy * vy
		if d > best then best, pick = d, i end
	end
	return pick
end

---------------------------------------------------------------------------
-- Cast flash: the slot you let go on pulses out and fades where it was.
-- (The ring itself is gone by then: the secure release hides it.)
---------------------------------------------------------------------------
local flash = CreateFrame("Frame", nil, UIParent)
flash:SetFrameStrata("DIALOG")
flash:SetSize(ICON, ICON)
flash:Hide()
flash.tex = flash:CreateTexture(nil, "ARTWORK")
flash.tex:SetAllPoints()
flash.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
circle(flash.tex, flash)
flash.glow = flash:CreateTexture(nil, "OVERLAY")
flash.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
flash.glow:SetBlendMode("ADD")
flash.glow:SetPoint("CENTER")
flash.glow:SetVertexColor(1, 0.85, 0.35)
local FLASH_TIME = 0.3
flash:SetScript("OnUpdate", function(self)
	local t = (GetTime() - self.start) / FLASH_TIME
	if t >= 1 then self:Hide() return end
	local size = ICON * 1.2 * (1 + 0.6 * t)
	self:SetSize(size, size)
	self.glow:SetSize(size * 2, size * 2)
	self:SetAlpha(1 - t)
end)
local function flashAt(x, y, tex)
	flash:ClearAllPoints()
	flash:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
	flash.tex:SetTexture(tex)
	flash.start = GetTime()
	flash:SetAlpha(1)
	flash:Show()
end

---------------------------------------------------------------------------
-- While the ring is open: the icons fly out from the middle (0.12 s), the
-- slot you aim at lights up, and the ready state refreshes a few times a second.
---------------------------------------------------------------------------
local OPEN_TIME = 0.12
local readyWait = 0
look:SetScript("OnShow", function(self)
	self.lastPick = false
	self.openAt = GetTime()
	self.opening = true
	readyWait = 0
	paintReady()
end)
look:SetScript("OnHide", function(self)
	-- Let go on a slot: flash it where it was.
	local f = self.lastPick and icons[self.lastPick]
	if f and self.flashX then flashAt(self.flashX, self.flashY, f.tex:GetTexture()) end
end)
look:SetScript("OnUpdate", function(self, elapsed)
	local n = #current
	if n == 0 then return end
	if self.opening then
		local t = math.min(1, (GetTime() - (self.openAt or 0)) / OPEN_TIME)
		local ease = 1 - (1 - t) ^ 3
		for i = 1, n do
			local f = icons[i]
			if f and f.vx then
				f:ClearAllPoints()
				f:SetPoint("CENTER", look, "CENTER", f.vx * f.r * ease, f.vy * f.r * ease)
				f:SetAlpha(t)
			end
		end
		if t >= 1 then self.opening = false end
	end
	readyWait = readyWait + (elapsed or 0)
	if readyWait > 0.15 then
		readyWait = 0
		paintReady()
	end
	local cx, cy = self:GetCenter()
	local x, y = GetCursorPosition()
	if ns.isSecret(cx) or ns.isSecret(cy) or ns.isSecret(x) or ns.isSecret(y) then return end
	if type(cx) ~= "number" or type(x) ~= "number" then return end
	local scale = self:GetEffectiveScale()
	if ns.isSecret(scale) or not scale or scale == 0 then return end
	local pick = pickAt(x / scale - cx, y / scale - cy, n)
	if pick ~= self.lastPick then
		self.lastPick = pick
		paintHover(pick)
	end
	-- Where the picked slot sits, for the flash after the ring closes.
	local f = pick and icons[pick]
	if f and f.vx then
		self.flashX, self.flashY = cx + f.vx * f.r, cy + f.vy * f.r
	else
		self.flashX, self.flashY = nil, nil
	end
end)

---------------------------------------------------------------------------
-- The key. Bound as CLICK ZydeForeverRadialKey:LeftButton.
---------------------------------------------------------------------------
_G["BINDING_NAME_CLICK ZydeForeverRadialKey:LeftButton"] = "Radial ring (hold)"
local key = CreateFrame("Button", "ZydeForeverRadialKey", UIParent, "SecureActionButtonTemplate, SecureHandlerBaseTemplate")
key:SetSize(1, 1)
key:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
key:SetAlpha(0)
key:RegisterForClicks("AnyDown", "AnyUp")
-- Nothing on the press; the action runs on the release from "typerelease".
key:SetAttribute("pressAndHoldAction", true)
key:SetFrameRef("ring", ring)
key:SetFrameRef("ui", UIParent)
key:SetAttribute("on", true)
key:SetAttribute("n", 0)
key:SetAttribute("dead2", DEAD * DEAD)
-- No HookScript on this key (that taints it); the look follows the ring by itself.
SecureHandlerWrapScript(key, "OnClick", key, [[
	self:SetAttribute("type", nil)
	local ring = self:GetFrameRef("ring")
	local ui = self:GetFrameRef("ui")
	local n = self:GetAttribute("n") or 0
	if down then
		self:SetAttribute("typerelease", nil)
		self:SetAttribute("open", 0)
		if not self:GetAttribute("on") or n == 0 or not ring or not ui then return end
		local x, y = ui:GetMousePosition()
		if not x or not y then return end
		local px, py = x * ui:GetWidth(), y * ui:GetHeight()
		self:SetAttribute("px", px)
		self:SetAttribute("py", py)
		ring:ClearAllPoints()
		ring:SetPoint("CENTER", ui, "BOTTOMLEFT", px, py)
		ring:Show()
		self:SetAttribute("open", 1)
		return
	end
	if ring then ring:Hide() end
	local pick
	if self:GetAttribute("open") == 1 and ui then
		local x, y = ui:GetMousePosition()
		if x and y then
			local dx = x * ui:GetWidth() - (self:GetAttribute("px") or 0)
			local dy = y * ui:GetHeight() - (self:GetAttribute("py") or 0)
			if dx * dx + dy * dy >= (self:GetAttribute("dead2") or 0) then
				local best = -2
				for i = 1, n do
					local d = dx * (self:GetAttribute("vx" .. i) or 0) + dy * (self:GetAttribute("vy" .. i) or 0)
					if d > best then best, pick = d, i end
				end
			end
		end
	end
	self:SetAttribute("open", 0)
	self:SetAttribute("spell", nil)
	self:SetAttribute("macro", nil)
	self:SetAttribute("item", nil)
	if not pick then
		self:SetAttribute("typerelease", nil)
		return
	end
	local t = self:GetAttribute("t" .. pick)
	if t ~= "spell" and t ~= "macro" and t ~= "item" then
		self:SetAttribute("typerelease", nil)
		return
	end
	self:SetAttribute("typerelease", t)
	self:SetAttribute(t, self:GetAttribute("v" .. pick))
]])

---------------------------------------------------------------------------
-- Build the ring from the saved slots (out of combat only).
---------------------------------------------------------------------------
local pending = false
local function apply()
	if InCombatLockdown() then pending = true return end
	pending = false
	wipe(current)
	for _, s in ipairs(slots()) do
		if actionOf(s) then current[#current + 1] = s end
	end
	local n = #current
	local r = radiusFor(n)
	look.name:ClearAllPoints()
	look.name:SetPoint("TOP", look, "CENTER", 0, -(r + ICON * 0.8 + 8))
	paintBackdrop(r)
	for i = 1, MAX do
		local f = icons[i]
		if i <= n then
			f = iconFrame(i)
			local vx, vy = dir(i, n)
			-- (kept for the fly-out, the pointer and the cast flash)
			f.vx, f.vy, f.r = vx, vy, r
			f:ClearAllPoints()
			f:SetPoint("CENTER", look, "CENTER", vx * r, vy * r)
			f:SetAlpha(1)
			f.tex:SetTexture(iconOf(current[i]))
			f:Show()
			local t, v = actionOf(current[i])
			key:SetAttribute("vx" .. i, vx)
			key:SetAttribute("vy" .. i, vy)
			key:SetAttribute("t" .. i, t)
			key:SetAttribute("v" .. i, v)
		else
			if f then f:Hide() end
			key:SetAttribute("t" .. i, nil)
			key:SetAttribute("v" .. i, nil)
		end
	end
	key:SetAttribute("n", n)
	key:SetAttribute("on", on() and true or false)
	if not on() then ring:Hide() end
	paintHover(nil)
end

---------------------------------------------------------------------------
-- Setup window: the same ring, bigger, with an empty slot to drop onto.
---------------------------------------------------------------------------
local editor
local EDIT_R, EDIT_ICON = 118, 40

local function refreshEditor()
	if not (editor and editor:IsShown()) then return end
	local list = slots()
	local shown = math.min(MAX, #list + 1)
	for i = 1, MAX do
		local b = editor.slots[i]
		if i <= shown then
			local vx, vy = dir(i, shown)
			b:ClearAllPoints()
			b:SetPoint("CENTER", editor.center, "CENTER", vx * EDIT_R, vy * EDIT_R)
			local s = list[i]
			b.slot = s
			if s then
				b.tex:SetTexture(iconOf(s))
				b.tex:SetDesaturated(false)
				b.plus:Hide()
			else
				b.tex:SetTexture(nil)
				b.plus:Show()
			end
			b:Show()
		else
			b:Hide()
		end
	end
	editor.count:SetText(string.format("%d of %d slots used", #list, MAX))
	editor.combat:SetShown(InCombatLockdown())
end

local function dropOn(i)
	if InCombatLockdown() then print(P .. "the ring can't change during a fight") return end
	local s, why = slotFromCursor()
	if not s then
		if why then print(P .. why) end
		return
	end
	ClearCursor()
	local list = slots()
	if i > #list then list[#list + 1] = s else list[i] = s end
	apply()
	refreshEditor()
end

local function clearSlot(i)
	if InCombatLockdown() then print(P .. "the ring can't change during a fight") return end
	local list = slots()
	if list[i] then table.remove(list, i) end
	apply()
	refreshEditor()
end

local function buildEditor()
	local f = CreateFrame("Frame", "ZydeForeverRadialEditor", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	f:SetSize(360, 430)
	f:SetPoint("CENTER")
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	if f.SetBackdrop then
		f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		f:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
		f:SetBackdropBorderColor(0.69, 0.35, 1, 0.6)
	end
	tinsert(UISpecialFrames, "ZydeForeverRadialEditor")

	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.title:SetPoint("TOPLEFT", 12, -10)
	f.title:SetText("Radial ring  |cffaaaaaa" .. (UnitName("player") or "") .. " only|r")
	f.title:SetTextColor(0.69, 0.35, 1)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)

	f.help = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.help:SetPoint("TOPLEFT", 12, -32)
	f.help:SetPoint("RIGHT", -12, 0)
	f.help:SetJustifyH("LEFT")
	f.help:SetText("Drag a spell, macro or item onto a slot. The + slot adds one. Right-click a slot to remove it.\n"
		.. "In game: hold the key, move toward a slot, let go to use it.")

	f.center = CreateFrame("Frame", nil, f)
	f.center:SetSize(2, 2)
	f.center:SetPoint("CENTER", f, "CENTER", 0, -6)
	local hub = f:CreateTexture(nil, "ARTWORK")
	hub:SetPoint("CENTER", f.center)
	hub:SetSize(DEAD * 2, DEAD * 2)
	hub:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	hub:SetVertexColor(0, 0, 0, 0.8)

	f.slots = {}
	for i = 1, MAX do
		local b = CreateFrame("Button", nil, f)
		b:SetSize(EDIT_ICON, EDIT_ICON)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints()
		b.bg:SetColorTexture(0.12, 0.12, 0.14, 1)
		b.tex = b:CreateTexture(nil, "ARTWORK")
		b.tex:SetAllPoints()
		b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		b.plus = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		b.plus:SetPoint("CENTER")
		b.plus:SetText("+")
		b.plus:SetTextColor(0.6, 0.6, 0.6)
		b.edges = ns.newEdges(b, "OVERLAY", 2)
		ns.placeEdges(b.edges, b, 0, 1)
		for _, t in ipairs(b.edges) do t:SetColorTexture(0.69, 0.35, 1, 0.7) end
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.15)
		b:SetScript("OnReceiveDrag", function() dropOn(i) end)
		b:SetScript("OnClick", function(self, btn)
			if btn == "RightButton" then clearSlot(i) return end
			if GetCursorInfo() then dropOn(i) end
		end)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			local s = self.slot
			if not s then
				GameTooltip:AddLine("Empty slot")
				GameTooltip:AddLine("Drop a spell, macro or item here.", 1, 1, 1, true)
			elseif s.kind == "spell" and s.id then
				pcall(GameTooltip.SetSpellByID, GameTooltip, s.id)
			elseif s.kind == "item" then
				pcall(GameTooltip.SetItemByID, GameTooltip, s.id)
			else
				GameTooltip:AddLine("Macro: " .. labelOf(s))
			end
			if s then GameTooltip:AddLine("Right-click: remove. Drop something here to replace it.", 0.6, 0.8, 1, true) end
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		f.slots[i] = b
	end

	local function smallButton(text, w)
		local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		b:SetSize(w, 22)
		b:SetText(text)
		return b
	end
	local book = smallButton("Spellbook", 96)
	book:SetPoint("BOTTOMLEFT", 12, 34)
	book:SetScript("OnClick", function()
		if InCombatLockdown() then return end
		if ToggleSpellBook then pcall(ToggleSpellBook, BOOKTYPE_SPELL or "spell")
		elseif PlayerSpellsUtil and PlayerSpellsUtil.ToggleSpellBookFrame then pcall(PlayerSpellsUtil.ToggleSpellBookFrame) end
	end)
	local macros = smallButton("Macros", 80)
	macros:SetPoint("LEFT", book, "RIGHT", 6, 0)
	macros:SetScript("OnClick", function()
		if InCombatLockdown() then return end
		if ShowMacroFrame then pcall(ShowMacroFrame) end
	end)
	local bags = smallButton("Bags", 64)
	bags:SetPoint("LEFT", macros, "RIGHT", 6, 0)
	bags:SetScript("OnClick", function() if ToggleAllBags then pcall(ToggleAllBags) end end)
	local clear = smallButton("Clear all", 80)
	clear:SetPoint("BOTTOMRIGHT", -12, 34)
	clear:SetScript("OnClick", function()
		if InCombatLockdown() then return end
		wipe(slots())
		apply()
		refreshEditor()
	end)

	f.count = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.count:SetPoint("BOTTOMLEFT", 14, 14)
	f.bind = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.bind:SetPoint("BOTTOMRIGHT", -14, 14)
	f.combat = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.combat:SetPoint("TOP", f.help, "BOTTOM", 0, -6)
	f.combat:SetText("|cffff6666In a fight: changes wait until it ends|r")
	f.combat:Hide()

	f:SetScript("OnShow", function(self)
		local k = GetBindingKey and GetBindingKey("CLICK ZydeForeverRadialKey:LeftButton")
		self.bind:SetText(k and ("Key: |cffffffff" .. k .. "|r") or "|cffff6666No key yet: Keybindings > Zyde Forever|r")
		refreshEditor()
	end)
	f:RegisterEvent("PLAYER_REGEN_DISABLED")
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	f:RegisterEvent("UPDATE_BINDINGS")
	f:SetScript("OnEvent", function(self) if self:IsShown() then self:GetScript("OnShow")(self) end end)
	f:Hide()
	return f
end

local function toggleEditor()
	editor = editor or buildEditor()
	editor:SetShown(not editor:IsShown())
end

---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("SPELLS_CHANGED")
ev:RegisterEvent("UPDATE_MACROS")
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" and not pending then return end
	apply()
	refreshEditor()
end)
ns.OnFeatureChanged(function(k) if k == "radial" then apply() end end)

ns.Radial = { ToggleEditor = toggleEditor }
