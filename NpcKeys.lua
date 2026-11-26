-- Zyde_Forever: number keys in NPC dialogs (option "Number keys for NPC options").
-- When an NPC's dialog lists choices - gossip lines, quests to take, quests to hand in - each gets
-- a small gold number, top to bottom, and pressing 1-9 (or the number pad) picks it, exactly as
-- a click would. Other keys work as usual, and so do 1-9 when there's no choice with that number.
-- (Not in a fight: the game won't let addons catch keys then.)
--
-- How: the game's own lists say what the choices are (quest titles, gossip text). The dialog's
-- buttons that show those texts are found, numbered by where they are on screen, and a key press
-- clicks that button. A choice whose button can't be found (scrolled out of view) still gets a
-- number after the others, and is picked through the game's API.

local ADDON, ns = ...
local isSecret, safe = ns.isSecret, ns.safe
local function plain(v) if isSecret(v) then return nil end return v end
local function on() return ns.F("npcKeys") end

local GOLD = { 1, 0.82, 0.2 }
local FLAT = "Interface\\Buttons\\WHITE8X8"

local function clean(s)
	if type(s) ~= "string" then return nil end
	s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
	s = s:gsub("^%s+", ""):gsub("%s+$", "")
	return s ~= "" and s:lower() or nil
end

---------------------------------------------------------------------------
-- The choices on offer: { text, pick = function() } from the game's API
---------------------------------------------------------------------------
local function gossipChoices()
	local out = {}
	local G = C_GossipInfo
	if not G then return out end
	for _, q in ipairs(safe(G.GetAvailableQuests) or {}) do
		local id = plain(q.questID)
		out[#out + 1] = { text = plain(q.title), pick = function() if id then G.SelectAvailableQuest(id) end end }
	end
	for _, q in ipairs(safe(G.GetActiveQuests) or {}) do
		local id = plain(q.questID)
		out[#out + 1] = { text = plain(q.title), pick = function() if id then G.SelectActiveQuest(id) end end }
	end
	for _, o in ipairs(safe(G.GetOptions) or {}) do
		local id, index = plain(o.gossipOptionID), plain(o.orderIndex)
		out[#out + 1] = { text = plain(o.name), pick = function()
			if id and G.SelectOption then G.SelectOption(id)
			elseif index and G.SelectOptionByIndex then G.SelectOptionByIndex(index) end
		end }
	end
	return out
end

local function greetingChoices()
	local out = {}
	local nAvail = plain(safe(GetNumAvailableQuests)) or 0
	for i = 1, nAvail do
		out[#out + 1] = { text = plain(safe(GetAvailableTitle, i)), pick = function() SelectAvailableQuest(i) end }
	end
	local nActive = plain(safe(GetNumActiveQuests)) or 0
	for i = 1, nActive do
		out[#out + 1] = { text = plain(safe(GetActiveTitle, i)), pick = function() SelectActiveQuest(i) end }
	end
	return out
end

-- Which dialog is up: the frame to search for buttons, and its choices.
local function activeDialog()
	if GossipFrame and GossipFrame:IsShown() then return GossipFrame, gossipChoices() end
	if QuestFrame and QuestFrame:IsShown() and QuestFrameGreetingPanel and QuestFrameGreetingPanel:IsShown() then
		return QuestFrameGreetingPanel, greetingChoices()
	end
	return nil
end

---------------------------------------------------------------------------
-- The dialog's buttons for those choices, numbered by position
---------------------------------------------------------------------------
local function buttonText(b)
	local t = b.GetText and plain(b:GetText())
	if (not t or t == "") and b.GetFontString then
		local fs = b:GetFontString()
		t = fs and plain(fs:GetText())
	end
	return clean(t)
end

local function visibleButtons(frame, out)
	out = out or {}
	for _, child in ipairs({ frame:GetChildren() }) do
		if child:IsVisible() then
			if child.IsObjectType and child:IsObjectType("Button") then
				local t = buttonText(child)
				if t then out[#out + 1] = { button = child, text = t } end
			end
			visibleButtons(child, out)
		end
	end
	return out
end

local current = {} -- [n] = { button, pick }

local badges = {}
local function badge(i)
	local b = badges[i]
	if b then return b end
	b = CreateFrame("Frame", nil, UIParent)
	b:SetSize(15, 15)
	b:SetFrameStrata("DIALOG")
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.bg:SetTexture(FLAT)
	b.bg:SetVertexColor(0.06, 0.06, 0.07, 0.9)
	b.edge = b:CreateTexture(nil, "BORDER")
	b.edge:SetPoint("TOPLEFT", -1, 1)
	b.edge:SetPoint("BOTTOMRIGHT", 1, -1)
	b.edge:SetTexture(FLAT)
	b.edge:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.7)
	b.text = b:CreateFontString(nil, "OVERLAY")
	b.text:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
	b.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	b.text:SetPoint("CENTER", 1, 0)
	b.text:SetText(i)
	badges[i] = b
	return b
end

local function hideBadges()
	for _, b in pairs(badges) do b:Hide() end
end

local function refresh()
	wipe(current)
	hideBadges()
	if not on() then return end
	local frame, choices = activeDialog()
	if not frame or #choices == 0 then return end
	local buttons = visibleButtons(frame)
	local matched, used = {}, {}
	-- Exact text first, then "contains" (Questie and the game add "[12]" or "(Complete)" around
	-- titles) - so a quest called "Wolves" can't take the button of "More Wolves".
	for pass = 1, 2 do
		for _, c in ipairs(choices) do
			local want = not c.found and clean(c.text)
			if want then
				for _, b in ipairs(buttons) do
					local hit = (pass == 1 and b.text == want) or (pass == 2 and b.text:find(want, 1, true))
					if not used[b.button] and hit then
						used[b.button] = true
						local top = plain(b.button:GetTop())
						matched[#matched + 1] = { button = b.button, pick = c.pick, top = top or 0 }
						c.found = true
						break
					end
				end
			end
		end
	end
	table.sort(matched, function(a, b) return a.top > b.top end) -- top of the dialog first
	for _, m in ipairs(matched) do current[#current + 1] = m end
	for _, c in ipairs(choices) do
		if not c.found then current[#current + 1] = { pick = c.pick } end -- (scrolled out of view)
	end
	for i, m in ipairs(current) do
		if i > 9 then break end
		if m.button then
			local b = badge(i)
			b:ClearAllPoints()
			b:SetPoint("RIGHT", m.button, "LEFT", -1, 0)
			b:SetFrameLevel((m.button:GetFrameLevel() or 1) + 5)
			b:Show()
		end
	end
end

---------------------------------------------------------------------------
-- Keys
---------------------------------------------------------------------------
local catcher = CreateFrame("Frame", "ZydeForeverNpcKeys", UIParent)
catcher:Hide()

local KEY = {}
for i = 1, 9 do KEY[tostring(i)] = i KEY["NUMPAD" .. i] = i end

catcher:SetScript("OnKeyDown", function(self, key)
	local n = KEY[key]
	local entry = n and current[n]
	local plainPress = not (IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown())
	if entry and plainPress and not InCombatLockdown() then
		self:SetPropagateKeyboardInput(false)
		if entry.button and entry.button:IsVisible() then entry.button:Click()
		else pcall(entry.pick) end
		C_Timer.After(0.1, refresh)
	elseif not InCombatLockdown() then
		self:SetPropagateKeyboardInput(true)
	end
end)

local function listen()
	if InCombatLockdown() then return end
	local frame = activeDialog()
	if on() and frame and #current > 0 then
		catcher:Show()
		catcher:EnableKeyboard(true)
		catcher:SetPropagateKeyboardInput(true)
	else
		catcher:EnableKeyboard(false)
		catcher:Hide()
	end
end

local function update()
	refresh()
	listen()
end

local function soon()
	-- (the dialog lays its buttons out a moment after the event)
	C_Timer.After(0.05, update)
	C_Timer.After(0.3, update)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "GOSSIP_SHOW", "GOSSIP_CLOSED", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS",
	"QUEST_COMPLETE", "QUEST_FINISHED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
	pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		-- a fight: stop catching keys (the game won't let us pass them on in one)
		catcher:EnableKeyboard(false)
		catcher:Hide()
		return
	end
	if event == "GOSSIP_CLOSED" or event == "QUEST_FINISHED" then
		wipe(current)
		hideBadges()
		listen()
		C_Timer.After(0.1, update) -- (another dialog may follow straight away)
		return
	end
	soon()
end)

-- Scrolling a long list moves the buttons: renumber then.
local hooked = false
local function hookScroll()
	if hooked or not GossipFrame then return end
	hooked = true
	GossipFrame:HookScript("OnMouseWheel", soon)
	local box = GossipFrame.GreetingPanel and GossipFrame.GreetingPanel.ScrollBox
	if box and box.RegisterCallback and box.Event and box.Event.OnScroll then
		pcall(box.RegisterCallback, box, box.Event.OnScroll, soon, catcher)
	end
end
ev:HookScript("OnEvent", function(_, event) if event == "GOSSIP_SHOW" then hookScroll() end end)

ns.OnFeatureChanged(function(key) if key == "npcKeys" then update() end end)
