-- Favorite mounts. Choose (in /zyde) ticks the ones a key may summon.
-- Tick none and the key uses every mount you know. The key is
-- "Random favorite mount" under Keybindings > Zyde Forever.
-- The click is the game's own secure button, so the summon is not blocked
-- as an addon action. The next mount is chosen ahead of the press.

local ADDON, ns = ...

local function plainString(v)
	if ns.isSecret(v) or type(v) ~= "string" or v == "" then return nil end
	return v
end
local function plainNumber(v)
	if ns.isSecret(v) or type(v) ~= "number" or v <= 0 then return nil end
	return v
end

local function spellName(id)
	if not plainNumber(id) then return nil end
	if C_Spell and C_Spell.GetSpellName then
		local n = plainString(ns.safe(C_Spell.GetSpellName, id))
		if n then return n end
	end
	if GetSpellInfo then
		local n = plainString(ns.safe(GetSpellInfo, id))
		if n then return n end
	end
end

-- The key button. The secure click itself writes the next /cast before the
-- press runs, the same way the radial key writes its spell. A step that
-- waits until after the press gets wiped by the next event, and the key
-- stays on the first mount.
local button
do
	local ok, made = pcall(CreateFrame, "Button", "ZydeForeverMountKey", UIParent, "SecureActionButtonTemplate, SecureHandlerBaseTemplate")
	button = (ok and made) or CreateFrame("Button", "ZydeForeverMountKey", UIParent, "SecureActionButtonTemplate")
end
button:SetSize(1, 1)
button:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
button:SetAlpha(0)
button:RegisterForClicks("AnyUp")
button:SetAttribute("type", "macro")
button:SetAttribute("macrotext", "")
button:SetAttribute("index", 1)
button:SetAttribute("count", 0)
_G["BINDING_NAME_CLICK ZydeForeverMountKey:LeftButton"] = "Random favorite mount"

local snippetReady = false
if SecureHandlerWrapScript then
	-- Pre body: this press summons m[index], then index moves for the next press.
	local pre = [[
		local n = tonumber(self:GetAttribute("count")) or 0
		if n < 2 then return end
		local i = tonumber(self:GetAttribute("index")) or 1
		if i < 1 or i > n then i = 1 end
		local line = self:GetAttribute("m"..i)
		if line then self:SetAttribute("macrotext", line) end
		i = i + 1
		if i > n then i = 1 end
		self:SetAttribute("index", i)
	]]
	snippetReady = pcall(SecureHandlerWrapScript, button, "OnClick", button, pre) and true or false
end

local queued = nil -- spell id currently on the button
local known = {}   -- spell id -> true, from the last list
local castNames = {} -- spell name -> true, so a cast still counts when its id differs
local dirty = true

local function charKey()
	local name = UnitName("player")
	local realm = GetRealmName and GetRealmName()
	if ns.isSecret(name) or type(name) ~= "string" or name == "" then return nil end
	if ns.isSecret(realm) or type(realm) ~= "string" then realm = "" end
	return name .. "-" .. realm
end

local function favTable()
	ZydeForeverDB = ZydeForeverDB or {}
	ZydeForeverDB.mountFav = ZydeForeverDB.mountFav or {}
	local key = charKey()
	if not key then return nil end
	local t = ZydeForeverDB.mountFav[key]
	if type(t) ~= "table" then
		t = {}
		ZydeForeverDB.mountFav[key] = t
	end
	return t
end

local function favCount(t)
	local n = 0
	if t then for _ in pairs(t) do n = n + 1 end end
	return n
end

local function addMount(list, seen, journalID, spellID, name, icon)
	if ns.isSecret(journalID) or type(journalID) ~= "number" then journalID = nil end
	if ns.isSecret(spellID) or type(spellID) ~= "number" then spellID = nil end
	local id = journalID or spellID
	if not id or seen[id] then return end
	if ns.isSecret(name) or type(name) ~= "string" or name == "" then name = spellName(spellID) end
	if not name or name == "" then return end
	local cast = spellName(spellID) or name
	if cast:find("[\n;]") then return end
	seen[id] = true
	castNames[cast] = true
	list[#list + 1] = {
		id = id,
		journalID = journalID,
		spellID = spellID,
		name = name,
		cast = cast,
		icon = (not ns.isSecret(icon)) and icon or nil,
	}
end

local function absorb(list, seen, ...)
	local name, spellID, icon
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if not ns.isSecret(v) then
			if type(v) == "string" and v ~= "" and not name then
				name = v
			elseif type(v) == "number" and v > 0 and not spellID then
				local sn = spellName(v)
				if sn then spellID = v
				elseif not icon and v > 1000 then icon = v end
			end
		end
	end
	if spellID then addMount(list, seen, nil, spellID, name, icon) end
end

-- Faction and class mounts the journal hides from this character.
-- A secret flag is left alone, since comparing it would throw.
local function allowed(hide, factionSpecific, faction)
	if not ns.isSecret(hide) and hide == true then return false end
	if ns.isSecret(factionSpecific) or factionSpecific ~= true then return true end
	local mine = UnitFactionGroup and UnitFactionGroup("player")
	if ns.isSecret(mine) or type(mine) ~= "string" then return true end
	if ns.isSecret(faction) then return true end
	if type(faction) == "string" then return faction == mine end
	if type(faction) ~= "number" then return true end
	if mine == "Horde" then return faction == 0 end
	if mine == "Alliance" then return faction == 1 end
	return true
end

-- Riding ranks, lowest first. A mount that requires a rank this character
-- has not learned is not one they are allowed to ride. Cerulean Prideclaw
-- needs Journeyman; Black Wolf and the bear only need Apprentice.
local RIDING = {
	{ name = "Apprentice Riding", spell = 33388, rank = 75 },
	{ name = "Journeyman Riding", spell = 33391, rank = 150 },
	{ name = "Expert Riding", spell = 34090, rank = 225 },
	{ name = "Artisan Riding", spell = 34091, rank = 300 },
	{ name = "Master Riding", spell = 90265, rank = 375 },
}

local function knowsSpell(id)
	local function yes(fn)
		if not fn then return false end
		local v = ns.safe(fn, id)
		if ns.isSecret(v) or v == nil or v == false then return false end
		return true
	end
	return yes(IsPlayerSpell) or yes(IsSpellKnown)
end

local function ridingRank()
	local best = 0
	for _, r in ipairs(RIDING) do
		if knowsSpell(r.spell) and r.rank > best then best = r.rank end
	end
	if GetNumSkillLines and GetSkillLineInfo then
		local n = ns.safe(GetNumSkillLines)
		if not ns.isSecret(n) and type(n) == "number" then
			for i = 1, n do
				local name, _, _, rank = ns.safe(GetSkillLineInfo, i)
				if not ns.isSecret(name) and type(name) == "string" and name:lower() == "riding"
					and not ns.isSecret(rank) and type(rank) == "number" and rank > best then
					best = rank
				end
			end
		end
	end
	return best
end

local function redRequirement(c)
	if not c or ns.isSecret(c) or type(c) ~= "table" then return false end
	if ns.isSecret(c.r) or ns.isSecret(c.g) or ns.isSecret(c.b) then return false end
	return type(c.r) == "number" and c.r > 0.95 and type(c.g) == "number" and c.g < 0.2 and type(c.b) == "number" and c.b < 0.2
end

local function textBlocks(text, have)
	if ns.isSecret(text) or type(text) ~= "string" or text == "" then return false end
	local lower = text:lower()
	for _, r in ipairs(RIDING) do
		if lower:find("requires " .. r.name:lower(), 1, true) and have > 0 and have < r.rank then
			return true
		end
	end
	local need = lower:match("requires riding %((%d+)%)")
	if need and have > 0 and have < tonumber(need) then return true end
	local lvl = lower:match("requires level (%d+)")
	if lvl then
		local mine = UnitLevel("player")
		if not ns.isSecret(mine) and type(mine) == "number" and mine < tonumber(lvl) then return true end
	end
	return false
end

local function tooltipBlocks(spellID, journalID, have)
	local function scan(data)
		if type(data) ~= "table" or type(data.lines) ~= "table" then return false end
		for _, line in ipairs(data.lines) do
			if type(line) == "table" then
				local left, right = line.leftText, line.rightText
				if textBlocks(left, have) or textBlocks(right, have) then return true end
				if (redRequirement(line.leftColor) and type(left) == "string" and not ns.isSecret(left) and left:lower():find("requires", 1, true))
					or (redRequirement(line.rightColor) and type(right) == "string" and not ns.isSecret(right) and right:lower():find("requires", 1, true)) then
					return true
				end
			end
		end
		return false
	end
	if journalID and C_TooltipInfo and C_TooltipInfo.GetMountByID then
		if scan(ns.safe(C_TooltipInfo.GetMountByID, journalID)) then return true end
	end
	if spellID and C_TooltipInfo and C_TooltipInfo.GetSpellByID then
		if scan(ns.safe(C_TooltipInfo.GetSpellByID, spellID)) then return true end
	end
	local desc
	if spellID and C_Spell and C_Spell.GetSpellDescription then
		desc = ns.safe(C_Spell.GetSpellDescription, spellID)
	elseif spellID and GetSpellDescription then
		desc = ns.safe(GetSpellDescription, spellID)
	end
	return textBlocks(desc, have)
end

-- True, false, or nil when the journal did not say.
local function usableNow(spellID, flagged)
	if not ns.isSecret(flagged) and flagged == true then return true end
	if not ns.isSecret(flagged) and flagged == false then return false end
	local fn = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell
	if not fn or not plainNumber(spellID) then return nil end
	local usable = ns.safe(fn, spellID)
	if ns.isSecret(usable) or usable == nil then return nil end
	return usable == true
end

local function dropUnrideable(list)
	local have = ridingRank()
	local now, any = {}, false
	for _, m in ipairs(list) do
		local u = usableNow(m.spellID, m.usableNow)
		now[m] = u
		if u == true then any = true end
	end
	local kept = {}
	for _, m in ipairs(list) do
		-- A red or unmet riding requirement always drops it. The journal's
		-- usable flag is only trusted when some other mount can be summoned
		-- right now, so standing in town does not empty the list.
		local blocked = tooltipBlocks(m.spellID, m.journalID, have)
		if not blocked and any and now[m] == false then blocked = true end
		if not blocked then kept[#kept + 1] = m end
	end
	return kept
end

local function collected()
	local list, seen, anyOwned = {}, {}, false
	local function consider(journalID, name, spellID, icon, isCollected, hide, factionSpecific, faction, isUsable)
		if not allowed(hide, factionSpecific, faction) then return end
		local owned = (not ns.isSecret(isCollected)) and isCollected == true
		if not owned and not ns.isSecret(isCollected) and isCollected == false then return end
		local before = #list
		if plainString(name) and (plainNumber(spellID) or ns.isSecret(spellID) or journalID) then
			addMount(list, seen, journalID, plainNumber(spellID), plainString(name) or name, icon)
		elseif plainString(name) or plainNumber(spellID) then
			addMount(list, seen, journalID, plainNumber(spellID), plainString(name), icon)
		end
		if #list > before then
			if not ns.isSecret(isUsable) and (isUsable == true or isUsable == false) then
				list[#list].usableNow = isUsable
			end
			if owned then
				list[#list].owned = true
				anyOwned = true
			end
		end
	end
	if C_MountJournal and C_MountJournal.GetMountIDs and C_MountJournal.GetMountInfoByID then
		local ids = ns.safe(C_MountJournal.GetMountIDs)
		if type(ids) == "table" then
			for _, id in ipairs(ids) do
				if not ns.isSecret(id) then
					local name, spellID, icon, _, isUsable, _, _, factionSpecific, faction, hide, isCollected = ns.safe(C_MountJournal.GetMountInfoByID, id)
					if plainString(name) or plainNumber(spellID) or ns.isSecret(spellID) then
						consider(id, name, spellID, icon, isCollected, hide, factionSpecific, faction, isUsable)
					else
						absorb(list, seen, ns.safe(C_MountJournal.GetMountInfoByID, id))
					end
				end
			end
		end
	end
	if C_MountJournal and C_MountJournal.GetNumDisplayedMounts and C_MountJournal.GetDisplayedMountInfo then
		local n = ns.safe(C_MountJournal.GetNumDisplayedMounts)
		if not ns.isSecret(n) and type(n) == "number" then
			for i = 1, n do
				local name, spellID, icon, _, isUsable, _, _, factionSpecific, faction, hide, isCollected, mountID = ns.safe(C_MountJournal.GetDisplayedMountInfo, i)
				consider(plainNumber(mountID), name, spellID, icon, isCollected, hide, factionSpecific, faction, isUsable)
			end
		end
	end
	if anyOwned then
		local kept = {}
		for _, m in ipairs(list) do
			if m.owned then kept[#kept + 1] = m end
		end
		list = kept
	end
	if #list < 2 and GetNumCompanions and GetCompanionInfo then
		local n = ns.safe(GetNumCompanions, "MOUNT") or 0
		if ns.isSecret(n) or type(n) ~= "number" then n = 0 end
		for i = 1, n do
			local _, creatureName, spellID, icon = ns.safe(GetCompanionInfo, "MOUNT", i)
			addMount(list, seen, nil, spellID, creatureName, icon)
		end
	end
	list = dropUnrideable(list)
	table.sort(list, function(a, b)
		local an, bn = a.name:lower(), b.name:lower()
		if an ~= bn then return an < bn end
		return (a.id or 0) < (b.id or 0)
	end)
	-- Two journal mounts can share one spell. /cast would summon the same
	-- creature either way, so the second one is summoned by its journal id.
	-- While mounted, the key dismounts and does not summon on that press.
	local function line(body)
		return "/dismount [mounted]\n/stopmacro [mounted]\n" .. body
	end
	local taken = {}
	for _, m in ipairs(list) do
		if taken[m.cast] and m.journalID then
			m.line = line("/run C_MountJournal.SummonByID(" .. m.journalID .. ")")
		else
			m.line = line("/cast " .. m.cast)
			taken[m.cast] = true
		end
	end
	wipe(known)
	wipe(castNames)
	for _, m in ipairs(list) do
		if m.spellID then known[m.spellID] = true end
		castNames[m.cast] = true
	end
	return list
end

local function poolFor(list)
	local fav = favTable()
	local picked = favCount(fav) > 0
	local out = {}
	for _, m in ipairs(list) do
		if not picked or fav[m.id] or (m.spellID and fav[m.spellID]) then out[#out + 1] = m end
	end
	return out
end

local function applyClick()
	if InCombatLockdown() then return end
	local down = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
	button:RegisterForClicks(down and "AnyDown" or "AnyUp")
end

-- One shuffled pass through the list. The key takes the front mount, then
-- that mount goes to the back of the line. Nothing repeats until the rest
-- have been used. Events must not reshuffle, or the same mount gets put
-- back on the key before the next press.
local deck, deckKey = {}, ""
local lastIndex = 1
local rndN = 0
local function rand(n)
	rndN = rndN + 7919
	local t = math.floor(((GetTime and GetTime()) or 0) * 1000)
	local frac = math.random()
	if type(frac) ~= "number" or frac <= 0 or frac >= 1 then frac = 0 end
	return (math.floor(t + rndN + frac * 100000) % n) + 1
end

local function poolKey(choices)
	local ids = {}
	for _, m in ipairs(choices) do ids[#ids + 1] = m.id or 0 end
	table.sort(ids)
	return table.concat(ids, ",")
end

local function shuffle(list, avoid)
	local out = {}
	for i, m in ipairs(list) do out[i] = m end
	for i = #out, 2, -1 do
		local j = rand(i)
		out[i], out[j] = out[j], out[i]
	end
	if avoid and #out > 1 and out[1].spellID == avoid then
		local j = 2
		for i = 2, #out do
			if out[i].spellID ~= avoid then j = i break end
		end
		out[1], out[j] = out[j], out[1]
	end
	return out
end

local function applyMacro()
	if InCombatLockdown() then dirty = true return end
	dirty = false
	applyClick()
	if not ns.F("mounts") then
		queued = nil
		button:SetAttribute("macrotext", "")
		return
	end
	local choices = poolFor(collected())
	if #choices == 0 then
		wipe(deck)
		deckKey = ""
		queued = nil
		button:SetAttribute("count", 0)
		button:SetAttribute("macrotext", "")
		return
	end
	local key = poolKey(choices)
	-- Same mounts as last time: leave the index where the last press left it.
	if key == deckKey and #deck > 0 then return end
	deck = shuffle(choices, nil)
	deckKey = key
	local prev = button:GetAttribute("count")
	if not plainNumber(prev) then prev = 0 end
	for i, m in ipairs(deck) do
		button:SetAttribute("m" .. i, m.line)
	end
	for i = #deck + 1, prev do
		button:SetAttribute("m" .. i, nil)
	end
	button:SetAttribute("count", #deck)
	button:SetAttribute("index", 1)
	lastIndex = 1
	local pick = deck[1]
	queued = pick.spellID
	button:SetAttribute("macrotext", pick.line)
end

-- If a summon leaves the index where Lua put it, the secure click did not
-- move it, so Lua moves it. Once a click does move the index, Lua stays
-- out, so two mounts cannot skip and land on the same one again.
local snippetMoved, advancedAt = false, 0
local function advance()
	if #deck < 2 or InCombatLockdown() then return end
	local i = button:GetAttribute("index")
	if not plainNumber(i) then i = 1 end
	if i ~= lastIndex then
		snippetMoved = true
		lastIndex = i
		return
	end
	if snippetMoved then return end
	local now = (GetTime and GetTime()) or 0
	if now - advancedAt < 0.4 then return end
	advancedAt = now
	i = i % #deck + 1
	local m = deck[i]
	if not m then return end
	button:SetAttribute("index", i)
	button:SetAttribute("macrotext", m.line)
	queued = m.spellID
	lastIndex = i
end

---------------------------------------------------------------------------
-- The list. Built once; opening it again just refills the rows.
---------------------------------------------------------------------------
local win, rows, content

local function paintNote()
	if not win then return end
	local choices = poolFor(collected())
	local names = {}
	for i, m in ipairs(choices) do
		if i > 8 then names[#names + 1] = "..." break end
		names[#names + 1] = m.name
	end
	local list = table.concat(names, ", ")
	if #choices == 0 then
		win.note:SetText("No mounts on the key yet.")
	elseif #choices == 1 then
		win.note:SetText("Only one mount on the key: " .. list)
	else
		win.note:SetText("Each press takes the next: " .. list)
	end
end

local function row(i)
	local r = rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, content)
	r:SetSize(280, 22)
	r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
	r.check:SetSize(22, 22)
	r.check:SetPoint("LEFT", 0, 0)
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(18, 18)
	r.icon:SetPoint("LEFT", r.check, "RIGHT", 2, 0)
	r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
	r.name:SetPoint("RIGHT", -4, 0)
	r.name:SetJustifyH("LEFT")
	r.name:SetWordWrap(false)
	local function toggle()
		local id = r.spellID
		local t = favTable()
		if not t or not id then return end
		if t[id] then t[id] = nil else t[id] = true end
		r.check:SetChecked(t[id] and true or false)
		paintNote()
		applyMacro()
	end
	r:SetScript("OnClick", toggle)
	r.check:SetScript("OnClick", toggle)
	rows[i] = r
	return r
end

local function fill()
	if not win or not win:IsShown() then return end
	local list = collected()
	local fav = favTable()
	local text = (win.search:GetText() or ""):lower()
	local y, shown = 0, 0
	for _, m in ipairs(list) do
		if text == "" or m.name:lower():find(text, 1, true) then
			shown = shown + 1
			local r = row(shown)
			r.spellID = m.id
			r.icon:SetTexture(m.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
			r.name:SetText(m.name)
			r.name:SetTextColor(1, 1, 1)
			r.check:SetChecked(fav and (fav[m.id] or (m.spellID and fav[m.spellID])) and true or false)
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", 0, -y)
			r:Show()
			y = y + 22
		end
	end
	for i = shown + 1, #rows do rows[i]:Hide() end
	content:SetHeight(math.max(22, y))
	if shown == 0 then
		win.empty:SetText(#list == 0 and "You have no mounts yet." or "Nothing matches.")
		win.empty:Show()
	else
		win.empty:Hide()
	end
	paintNote()
end

local function build()
	win = CreateFrame("Frame", "ZydeForeverMounts", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	win:SetSize(340, 460)
	win:SetPoint("CENTER")
	win:SetFrameStrata("FULLSCREEN_DIALOG")
	win:SetFrameLevel(400)
	win:SetClampedToScreen(true)
	win:EnableMouse(true)
	win:SetMovable(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", win.StopMovingOrSizing)
	if win.SetBackdrop then
		win:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		win:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
		win:SetBackdropBorderColor(0.69, 0.35, 1, 0.6)
	end
	tinsert(UISpecialFrames, "ZydeForeverMounts")
	win:Hide()

	win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	win.title:SetPoint("TOPLEFT", 12, -10)
	win.title:SetText("Favorite mounts")
	win.title:SetTextColor(0.69, 0.35, 1)
	local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)

	win.help = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	win.help:SetPoint("TOPLEFT", 12, -30)
	win.help:SetPoint("RIGHT", -12, 0)
	win.help:SetJustifyH("LEFT")
	win.help:SetText("Tick the ones the key may summon. The key is Random favorite mount, under Keybindings > Zyde Forever.")

	local search = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
	search:SetSize(200, 20)
	search:SetPoint("TOPLEFT", 16, -52)
	search:SetAutoFocus(false)
	search:SetScript("OnTextChanged", function() fill() end)
	search:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
	win.search = search

	local clear = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
	clear:SetSize(72, 20)
	clear:SetPoint("LEFT", search, "RIGHT", 8, 0)
	clear:SetText("Clear")
	clear:SetScript("OnClick", function()
		local t = favTable()
		if t then wipe(t) end
		fill()
		applyMacro()
	end)
	clear:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Clear")
		GameTooltip:AddLine("Untick all of them. The key then uses every mount you know.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	clear:SetScript("OnLeave", function() GameTooltip:Hide() end)

	local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 12, -78)
	scroll:SetPoint("BOTTOMRIGHT", -30, 48)
	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(280, 1)
	scroll:SetScrollChild(content)
	rows = {}

	win.empty = win:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	win.empty:SetPoint("TOP", scroll, "TOP", -8, -12)
	win.empty:Hide()

	win.note = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	win.note:SetPoint("BOTTOMLEFT", 12, 12)
	win.note:SetPoint("RIGHT", -12, 0)
	win.note:SetJustifyH("LEFT")
	win.note:SetWordWrap(true)

	win:SetScript("OnShow", fill)
end

local function toggle()
	if not win then build() end
	if win:IsShown() then
		win:Hide()
		return
	end
	-- The options window is DIALOG. This has to sit above it.
	win:SetFrameStrata("FULLSCREEN_DIALOG")
	win:SetFrameLevel(400)
	win:Show()
	win:Raise()
end

ns.Mounts = { Toggle = toggle }

ns.OnFeatureChanged(function(key)
	if key == "mounts" then applyMacro() end
end)

local wasMounted, sawMounted = false, false
local function noteMounted()
	local on = IsMounted and IsMounted()
	if ns.isSecret(on) then return end
	on = on and true or false
	if not sawMounted then
		wasMounted, sawMounted = on, true
		return
	end
	if on and not wasMounted then advance() end
	wasMounted = on
end

local ev = CreateFrame("Frame")
for _, e in ipairs({
	"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "ZONE_CHANGED_NEW_AREA",
	"CVAR_UPDATE", "COMPANION_LEARNED", "NEW_MOUNT_ADDED", "MOUNT_JOURNAL_USABILITY_CHANGED",
}) do
	pcall(ev.RegisterEvent, ev, e)
end
ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
ev:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
ev:RegisterUnitEvent("UNIT_AURA", "player")
ev:SetScript("OnEvent", function(_, event, _, _, spellID)
	if event == "UNIT_AURA" then noteMounted() return end
	if event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_FAILED" then
		advance()
		return
	end
	if event == "PLAYER_REGEN_ENABLED" then
		if dirty then applyMacro() else applyClick() end
		return
	end
	if event == "CVAR_UPDATE" or event == "MOUNT_JOURNAL_USABILITY_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" then
		if event == "CVAR_UPDATE" then applyClick() end
		return
	end
	applyMacro()
	if win and win:IsShown() and (event == "COMPANION_LEARNED" or event == "NEW_MOUNT_ADDED") then fill() end
end)
