-- Zyde_Forever
-- 1) Warrior reminders: shows an icon to the right of your character when
--    Battle Shout is NOT on you, and when Overpower is ready to use.
--    Active icons stack in a column.
-- 2) Hides the main action bar art, the bag bar, the micro menu and the
--    experience bar.
-- 3) A small draggable "XP 45.2%" readout in place of the experience bar.
-- 4) One Button Fishing keybind (Keybindings > AddOns > Zyde Forever).
-- 5) Flight masters open the flight map directly (hold Shift to talk instead).
-- 6) Rarity-colored borders on equipped gear in the character screen.
-- 8) Minimap tracking (e.g. Find Minerals) comes back on after you die.
-- 9) Icons over nearby objects, and an alert when one is a quest item.
-- 10) Drop chance under Questie's nameplate loot bag (QuestieDrops.lua).
-- 11) Bags full: the 3 cheapest stacks marked 1-2-3 (ScrapList.lua).
-- 12) Vendor / auction / keep advice per bag item, sell panel at merchants (VendorList.lua).
-- 13) Group finder helper: groups with room for you first, whisper the leader (LFGHelper.lua).
-- 14) A small draggable info bar, one line: location, gold, bags, and ammo.
--     Max opens a second line: steps, swim, mounted, and jumps
--     (InfoBar.lua).
-- 15) Tank threat list: a table of mobs you have threat on, your percent,
--     and the next two people (ThreatBox.lua).
--
-- /zyde test     - toggle preview of both icons (to see where they sit)
-- /zyde resetxp  - put the XP readout back at its default spot
-- /zyde quest <id> - is that quest flagged complete, plus its Questie name

local ADDON, ns = ...

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local ICON_SIZE   = 44   -- pixels
local OFFSET_X    = 130  -- right of screen centre (your character)
local OFFSET_Y    = 0    -- first icon's height relative to screen centre
local SPACING     = 6    -- gap between stacked icons
local POLL        = 0.2  -- seconds between checks

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function isSecret(v)
	return type(issecretvalue) == "function" and issecretvalue(v) or false
end

-- pcall's results without the ok flag (nil on error). Defined once so
-- safe() doesn't create a new function on every call.
local function passResults(ok, ...)
	if ok then return ... end
	return nil
end

local function safe(fn, ...)
	if type(fn) ~= "function" then return nil end
	return passResults(pcall(fn, ...))
end

local function knows(id)
	if IsPlayerSpell and safe(IsPlayerSpell, id) then return true end
	if IsSpellKnown and safe(IsSpellKnown, id) then return true end
	return false
end

-- Highest known rank from a list of spell IDs (lowest -> highest).
local function findRank(ids)
	for i = #ids, 1, -1 do
		if knows(ids[i]) then return ids[i] end
	end
	return nil
end

-- Known spells only change when you train, so remember the answer until
-- the game says your spells changed (rankCache is wiped then).
local rankCache = {} -- ids table -> spell ID, or false if none known
local function knownRank(ids)
	local r = rankCache[ids]
	if r == nil then
		r = findRank(ids) or false
		rankCache[ids] = r
	end
	return r or nil
end

local function spellTexture(id, fallback)
	local tex
	if C_Spell and C_Spell.GetSpellTexture then tex = safe(C_Spell.GetSpellTexture, id) end
	if not tex and GetSpellTexture then tex = safe(GetSpellTexture, id) end
	if not tex or isSecret(tex) then tex = fallback end
	return tex
end

-- Your buffs, read once and shared by every reminder tile (several tiles each
-- re-reading up to 40 buffs five times a second added up). Read again when your
-- buffs change, a fight starts or ends, or after a second at most.
--   ns.PlayerBuffs() -> { list = { aura... }, hidden = bool } or nil
-- Each aura has the game's field names (name, spellId, expirationTime, duration,
-- applications), nil where the game hides them; hidden is true when
-- any buff came back hidden or the game refused the read (Forever, in a fight).
do
	local snap, readAt, dirty = nil, 0, true
	local MAX_AGE = 1
	local function plainOf(v) if isSecret(v) then return nil end return v end
	local function read()
		if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
		local s = { list = {}, hidden = false }
		for i = 1, 40 do
			local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
			if not ok then s.hidden = true break end
			if not a then break end
			local b = { name = plainOf(a.name), spellId = plainOf(a.spellId), expirationTime = plainOf(a.expirationTime),
				duration = plainOf(a.duration), applications = plainOf(a.applications) }
			if b.name == nil and b.spellId == nil then s.hidden = true end
			s.list[#s.list + 1] = b
		end
		return s
	end
	function ns.PlayerBuffs()
		local now = GetTime()
		if dirty or now - readAt > MAX_AGE then
			snap, readAt, dirty = read(), now, false
		end
		return snap
	end
	local ev = CreateFrame("Frame")
	ev:RegisterUnitEvent("UNIT_AURA", "player")
	for _, e in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD", "ENCOUNTER_START", "ENCOUNTER_END" }) do
		pcall(ev.RegisterEvent, ev, e)
	end
	ev:SetScript("OnEvent", function() dirty = true end)
end

---------------------------------------------------------------------------
-- Features: each can be turned on or off in the /zyde window, saved in
-- ZydeForeverDB.features. A feature that needs another addon (Questie,
-- AHledger) is off when that addon isn't loaded.
---------------------------------------------------------------------------
local FEATURES = {
	{ key = "reminders", short = "icons beside you", label = "Reminder icons", desc = "Icons to the right of your character (Shift-drag one to move them). Warriors: in a fight, Battle Shout, Thunder Clap and being out of melee range pulse on your character. Also Overpower / Execute / Revenge / Victory Rush ready, wrong stance, and Sunder stacks when tanking. Hunters: no Aspect, Cheetah or Pack on in combat, Hunter's Mark missing (solo), target too far or too close to shoot, Mongoose Bite ready, Mend Pet. Shamans: weapon imbue missing or running out, Lightning Shield missing or low, Earth Shock to interrupt, a totem out of range, no Ankh. Everyone: Well-Rested low, gear needs repair, low on food or water" },
	{ key = "ammo", class = "HUNTER", short = "count, refill, warning", label = "Hunter ammo", desc = "Arrows or bullets left and how long they last (in the XP readout), a warning when you leave town low, and a Fill quiver button at ammo vendors (hunters)" },
	{ key = "petCare", class = "HUNTER", short = "feed, call, Growl", label = "Hunter pet care", desc = "Keys to feed your pet the right food and to call or revive it, with reminders when it's hungry or missing, and a Growl autocast reminder: off in a group, on when solo (hunters)" },
	{ key = "markerWheel", short = "marks on the target", label = "Target markers", desc = "Hold the marker key and two rows of four icons show just under your cursor. Top: skull, X, square, moon. Bottom: triangle, diamond, circle, star. The red button removes the mark on your target. The gold ALL button removes every mark. Clicking the icon already on your target removes that mark too. Click a different icon to change it. Letting go hides the icons. World markers stay a separate key: press it to show or hide the squares, drag the title to move them, click a square, then the ground. The last square clears those." },
	{ key = "hideBars", short = "cleaner action bars", label = "Hide Blizzard bar art", desc = "Hides the action bar art and the bag bar", reload = true },
	{ key = "hideMicroMenu", short = "game menu buttons", label = "Hide micro menu", desc = "Hides the row of small game menu buttons (character, spellbook, talents, quest log, social, game menu...). Their keybinds still work", reload = true },
	{ key = "xp", short = "compact XP display", label = "XP readout", desc = "Small draggable XP % with rested XP, time to level and tooltip (replaces the XP bar)", reload = true },
	{ key = "infoBar", short = "location, gold, bags", label = "Info bar", desc = "One line you can drag: where you are, gold, bag space, and ammo for a bow, gun, or throwing weapon. Max opens a second line with steps, yards swum, yards mounted, and jumps. Min hides that line. Those counts are kept for this character. Ctrl+click the top line to paste where you are into chat. Ctrl+click the counter line to paste the counts" },
	{ key = "threatBox", short = "tank threat table", label = "Tank threat list", desc = "While you are set to the tank role in a party or raid: a draggable table of mobs you have threat on. Columns are the mob, your threat percent, then the two people closest behind you and their percent. Only mobs with a nameplate, bosses, and your target can be listed. Drag the title to move it" },
	{ key = "unitFrames", short = "flat health boxes", label = "Unit frames", desc = "Flat player, target, party and raid frames with buffs and debuffs, mana / rage / energy on party frames. Shift-drag a frame to move it", reload = true },
	{ key = "targetTarget", short = "small frame by target", label = "Target of target", desc = "A small frame beside the target frame showing who your target is targeting (with the Zyde unit frames on). Shift-drag it to move it" },
	{ key = "unitAuras", short = "icons on your frames", label = "Unit frame buffs / debuffs", desc = "Buff and debuff icons with time left on the Zyde unit frames: the target's debuffs (yours first) and buffs, your debuffs and buffs, and your pet's" },
	{ key = "plates", short = "flat enemy nameplates", label = "Nameplates", desc = "Flat enemy nameplates in the unit frames' style: full name above, level badge (elite +, rare dragon, boss skull), cast bar (orange = interruptible), your debuffs with time left, aggro warning (AGGRO on mobs attacking you, LOOSE when you tank and a mob isn't on you), Execute-range color for warriors, and the quest icon, count and drop chance together on the right (Questie). Friendly and object nameplates keep the game's look" },
	{ key = "comboPoints", short = "pips on your target", label = "Combo points on nameplate", desc = "Rogues and druids in cat form: a row of pips above your target's nameplate, one per combo point, gold to red, all red when full (with Zyde nameplates on)" },
	{ key = "barTidy", short = "short keys, no empty slots", label = "Tidy action bars", desc = "Short keybind labels on action buttons (a-1 becomes A1, Mouse Button 4 becomes M4) and empty slots hidden - they show again while you drag a spell or item" },
	{ key = "gear", short = "borders, item levels", label = "Character screen gear", desc = "Rarity borders and item levels; a green arrow when your bags hold an upgrade for a slot (scored by GearAdvisor if loaded), empty slots quiet gray unless your bags can fill them, and your average item level in the header", reload = true },
	{ key = "fishing", short = "one-key fishing", label = "One Button Fishing", desc = "Same key casts and reels in (set the key in Keybindings)" },
	{ key = "mapNotes", short = "alt-click to mark", label = "Map markers", desc = "Your own named markers on the world map, kept between sessions. Alt-click the map to drop one and name it, alt-click a marker to remove it, right-click to rename it" },
	{ key = "flight", short = "skip flight chat", label = "Flight master shortcut", desc = "Flight masters open the map directly (hold Shift to talk)" },
	{ key = "tracking", short = "re-enable after death", label = "Keep tracking after death", desc = "Turns Find Minerals, Find Herbs... back on after you die" },
	{ key = "questTracker", short = "ready first, by level", label = "Quest tracker", desc = "Replaces the game's quest tracker: quests ready to turn in, then this zone, then other zones folded away. The mark on each heading cycles that list: nearest, highest level, lowest level. Finished objective lines are hidden", reload = true },
	{ key = "rares", short = "flash + sound", label = "Rare announcer", desc = "When a rare or rare elite shows up (on a nameplate, as your target or mouseover, or on the minimap), its name flashes on screen, a line goes to chat and a sound plays. Each rare is announced once per 5 minutes. Rares you've just seen are also first for the \"Target nearest quest mob\" key" },
	{ key = "questAlert", short = "glow on quest objects", label = "Quest object alert", desc = "Glow, ! and ping on nearby quest objects you pick up (not the loot of mobs you kill for a quest)" },
	{ key = "questIcons", short = "icons over nodes", label = "Icons over nearby objects", desc = "The game's interact icons over herbs, ore and chests" },
	{ key = "guildRoster", short = "class colors, levels, zones", label = "Guild member list", desc = "In the Guild & Communities window: online members' names in class colors, each member's level at the right (colored by how near your level), and their zone when you hover them" },
	{ key = "lfg", short = "groups that fit you", label = "Group finder helper", desc = "Beside Looking For Group: groups with room for your role first, one-click whisper to the leader" },
	{ key = "scrap", short ="what to delete", label = "Scrap list (bags full)", desc = "The 3 cheapest items to throw away when your bags are full" },
	{ key = "vendor", short = "sell or auction tips", label = "Vendor / auction advice", desc = "Vendor it / Auction it / Keep in tooltips, merchant and AH panels", needs = "AHledger" },
	{ key = "recipes", short = "what to learn, where, price", label = "Unlearned recipes", desc = "Beside a profession window: the recipes you haven't learned yet, where to get each (vendor, quest or drop) and, with AHledger, its auction price. Click one for a waypoint to its vendor. The Unlearned button on the window shows or hides it", needs = "Questie" },
	{ key = "autoQuests", short = "planned quests only", label = "Auto complete quests", desc = "While the level planner is on, it accepts and turns in the quests on its plan when you talk to the NPC. A turn-in with more than one reward waits for you to choose. Hold Shift while opening the NPC to skip it once. Uncheck this to accept and turn in quests yourself." },
	{ key = "levelPlanner", short = "best XP route, arrow", label = "Level planner", desc = "Plans the next hour of levelling for the most XP per minute from Questie's quests: a step list with the reason for each step, an arrow and map pins to the next step, the star marker on the next NPC, a quest item button, and travel by flight paths, boats and your hearthstone. Auto complete quests is its own checkbox. /lp shows the list, /lp help for more", needs = "Questie", reload = true },
	{ key = "questieDrops", short = "drop % on nameplates", label = "Questie drop chances", desc = "Drop % and your odds under Questie's nameplate bag", needs = "Questie" },
	{ key = "questMobs", short = "glow, count, target key", label = "Quest mobs nearby", desc = "Gold edge on quest mobs' nameplates, a count of them near you, and a key to target one", needs = "Questie" },
}
ns.FEATURES = FEATURES
local FEATURE_BY_KEY = {}
for _, f in ipairs(FEATURES) do FEATURE_BY_KEY[f.key] = f end

-- Is another addon loaded? Asked many times a second (feature checks), so the
-- answer is remembered: "yes" for good (an addon can't unload), "no" until the
-- next addon loads (ADDON_LOADED), since some load after Zyde or on demand.
local addonOn
do
	local known = {}
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("ADDON_LOADED")
	watcher:SetScript("OnEvent", function()
		for name, on in pairs(known) do
			if not on then known[name] = nil end
		end
	end)
	function addonOn(name)
		local v = known[name]
		if v == nil then
			local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
			v = f and safe(f, name) and true or false
			known[name] = v
		end
		return v
	end
end
ns.addonOn = addonOn

-- Other addons some features use (listed in the /zyde window).
ns.ADDONS = {
	{ name = "Questie", title = "Questie", used = "Needed for Questie drop chances and quest mobs nearby. Also helps spot quest objects." },
	{ name = "AHledger", title = "AHledger", used = "Needed for vendor / auction advice. Adds auction prices to the scrap list." },}

-- "on" (loaded), "off" (installed but disabled) or "missing".
function ns.addonState(name)
	if addonOn(name) then return "on" end
	local info = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
	if info then
		local ok, _, _, _, _, reason = pcall(info, name)
		if ok and reason ~= "MISSING" then return "off" end
	end
	return "missing"
end

-- Why a feature can't run right now ("needs Questie"), or nil.
local function featureBlocked(key)
	local f = FEATURE_BY_KEY[key]
	if not f then return nil end
	if f.needs and not addonOn(f.needs) then return "needs " .. f.needs end
	if f.conflict and addonOn(f.conflict) then return f.conflict .. " already does this" end
	return nil
end
ns.featureBlocked = featureBlocked

-- The reminder icons used to be separate toggles; now one ("reminders") covers them.
local REMINDER_KEYS = { shout = true, overpower = true, rested = true, aspect = true }

-- Was turned on by the player (saved), regardless of other addons.
local function featureWanted(key)
	if REMINDER_KEYS[key] then key = "reminders" end
	local saved = ZydeForeverDB and ZydeForeverDB.features
	if saved and saved[key] ~= nil then return saved[key] end
	-- Older toggles saved before the window existed.
	local db = ZydeForeverDB
	if db then
		if key == "questAlert" and db.questAlert == false then return false end
		if key == "questIcons" and db.questIcons == false then return false end
		if key == "scrap" and db.scrapOff then return false end
		if key == "vendor" and db.vendorOff then return false end
	end
	return true
end
ns.featureWanted = featureWanted

-- On: wanted and nothing blocks it.
-- (Same test as featureBlocked, without building its message: this runs often.)
local function F(key)
	if not featureWanted(key) then return false end
	local f = FEATURE_BY_KEY[key]
	if f and ((f.needs and not addonOn(f.needs)) or (f.conflict and addonOn(f.conflict))) then return false end
	return true
end
ns.F = F

local featureListeners = {}
-- Other parts ask to hear when a toggle changes, to update right away.
function ns.OnFeatureChanged(fn) featureListeners[#featureListeners + 1] = fn end

local function setFeature(key, on)
	ZydeForeverDB = ZydeForeverDB or {}
	ZydeForeverDB.features = ZydeForeverDB.features or {}
	ZydeForeverDB.features[key] = on and true or false
	for _, fn in ipairs(featureListeners) do pcall(fn, key, on) end
end
ns.setFeature = setFeature

---------------------------------------------------------------------------
-- Spells (Classic ranks)
---------------------------------------------------------------------------
local BATTLE_SHOUT = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 }
local OVERPOWER    = { 7384, 7887, 11584, 11585 }

---------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------
local anchor = CreateFrame("Frame", "ZydeForeverAnchor", UIParent)
anchor:SetSize(ICON_SIZE, ICON_SIZE)
anchor:SetPoint("CENTER", UIParent, "CENTER", OFFSET_X, OFFSET_Y)
anchor:SetFrameStrata("HIGH")

local function makeIcon(name, fallbackTex)
	local f = CreateFrame("Frame", name, anchor, "BackdropTemplate")
	f:SetSize(ICON_SIZE, ICON_SIZE)
	f:EnableMouse(false) -- never block clicks
	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetPoint("TOPLEFT", 1, -1)
	f.tex:SetPoint("BOTTOMRIGHT", -1, 1)
	f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	f.tex:SetTexture(fallbackTex)
	f.border = f:CreateTexture(nil, "BACKGROUND")
	f.border:SetAllPoints()
	f.border:SetColorTexture(0, 0, 0, 1)
	f.fallback = fallbackTex
	f:Hide()
	return f
end

local icons = {
	{ key = "shout", frame = makeIcon("ZydeForeverBattleShout", "Interface\\Icons\\Ability_Warrior_BattleShout") },
	{ key = "overpower", frame = makeIcon("ZydeForeverOverpower", "Interface\\Icons\\Ability_MeleeDamage") },
	{ key = "quest", frame = makeIcon("ZydeForeverQuestItem", "Interface\\GossipFrame\\AvailableQuestIcon") },
	{ key = "rested", frame = makeIcon("ZydeForeverWellRested", "Interface\\Icons\\INV_Misc_Bag_08") },
}
-- Battle Shout sits on the character, large, until you put it on.
icons[1].frame.prominent = true
-- (a font from the start: SetText runs before layout() sets the small font)
icons[1].frame.label = icons[1].frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
icons[1].frame.label:SetTextColor(1, 0.9, 0.45)

-- Other files add their own reminder icons to this column:
--   ns.AddReminder(key, frameName, texture, check)
-- check(preview) is called every 0.1s and returns show, label.
local reminders = {}
function ns.AddReminder(key, name, tex, check)
	local f = makeIcon(name, tex)
	f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.label:SetPoint("LEFT", f, "RIGHT", 6, 0)
	icons[#icons + 1] = { key = key, frame = f }
	reminders[#reminders + 1] = { key = key, frame = f, check = check }
	return f
end

---------------------------------------------------------------------------
-- Moving the column: Shift-drag any icon (out of combat). The icons only take
-- the mouse while Shift is held, so they never block clicks otherwise.
-- /zyde resetreminders puts the column back beside your character.
---------------------------------------------------------------------------
do -- own scope (200-local limit)
anchor:SetMovable(true)
anchor:SetClampedToScreen(true)

local function placeAnchor()
	anchor:ClearAllPoints()
	local p = ZydeForeverDB and ZydeForeverDB.reminderPos
	if type(p) == "table" and p.point then
		anchor:SetPoint(p.point, UIParent, p.rel or p.point, p.x or 0, p.y or 0)
	else
		anchor:SetPoint("CENTER", UIParent, "CENTER", OFFSET_X, OFFSET_Y)
	end
end

local dragReady = false
local function setDraggable(on)
	if on == dragReady then return end
	dragReady = on
	for _, icon in ipairs(icons) do
		local f = icon.frame
		if on and not f.zydeDrag then
			f.zydeDrag = true
			f:RegisterForDrag("LeftButton")
			f:SetScript("OnDragStart", function() if not InCombatLockdown() then anchor:StartMoving() end end)
			f:SetScript("OnDragStop", function()
				anchor:StopMovingOrSizing()
				local point, _, rel, x, y = anchor:GetPoint(1)
				ZydeForeverDB = ZydeForeverDB or {}
				ZydeForeverDB.reminderPos = { point = point, rel = rel, x = x, y = y }
			end)
		end
		f:EnableMouse(on and not f.prominent)
	end
end

local dragEv = CreateFrame("Frame")
dragEv:RegisterEvent("PLAYER_LOGIN")
dragEv:RegisterEvent("MODIFIER_STATE_CHANGED")
dragEv:RegisterEvent("PLAYER_REGEN_DISABLED")
dragEv:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then placeAnchor() return end
	if event == "PLAYER_REGEN_DISABLED" then anchor:StopMovingOrSizing() end
	setDraggable(IsShiftKeyDown() and not InCombatLockdown())
end)

ns.ResetReminderPosition = function()
	if ZydeForeverDB then ZydeForeverDB.reminderPos = nil end
	placeAnchor()
	print("|cff66ccffZyde_Forever|r: reminder icons moved back beside your character")
end
end -- reminder dragging

-- Stack the shown icons. Runs 10 times a second, so an icon is only moved
-- when its place in the column changes.
local BIG, BIG_GAP, BIG_Y = 38, 8, 86
local BIG_EDGE = {
	shout = { 0.95, 0.72, 0.15, 1 },
	meleeRange = { 0.95, 0.15, 0.1, 1 },
	thunderClap = { 0.25, 0.55, 1, 1 },
	eviscerate = { 0.85, 0.1, 0.25, 1 },
	sealRighteousness = { 1, 0.85, 0.35, 1 },
}
local function layout(states)
	local n, big = 0, {}
	for _, icon in ipairs(icons) do
		local f = icon.frame
		if states[icon.key] and f.prominent then
			big[#big + 1] = f
			f.pulseFast = icon.key == "meleeRange"
			local edge = BIG_EDGE[icon.key]
			if edge then f.border:SetColorTexture(edge[1], edge[2], edge[3], edge[4]) end
		elseif states[icon.key] then
			if f.zydeSlot ~= n or not f:IsShown() or f:GetWidth() ~= ICON_SIZE then
				f.zydeSlot = n
				f:SetSize(ICON_SIZE, ICON_SIZE)
				f:ClearAllPoints()
				f:SetPoint("TOP", anchor, "TOP", 0, -n * (ICON_SIZE + SPACING))
				f:Show()
			end
			n = n + 1
		elseif f:IsShown() then
			f:Hide()
			f:SetAlpha(1)
			f:SetSize(ICON_SIZE, ICON_SIZE)
		end
	end
	-- On the character, not in the side column: large, and centered as a row.
	local total = #big * BIG + math.max(0, #big - 1) * BIG_GAP
	local x = -total / 2 + BIG / 2
	for i, f in ipairs(big) do
		f:SetSize(BIG, BIG)
		f:ClearAllPoints()
		f:SetPoint("CENTER", UIParent, "CENTER", x + (i - 1) * (BIG + BIG_GAP), BIG_Y)
		if f.label then
			f.label:ClearAllPoints()
			f.label:SetPoint("TOP", f, "BOTTOM", 0, -2)
			if not f.label:SetFont("Fonts\\ARIALN.TTF", 10, "OUTLINE") then f.label:SetFontObject("GameFontNormal") end
		end
		f:Show()
	end
end

---------------------------------------------------------------------------
-- Battle Shout check
---------------------------------------------------------------------------
-- In combat the Forever client can hide aura details ("secret" values), so
-- remember when the last seen Battle Shout runs out and use that as backup.
local shoutExpires = 0
local SHOUT_DURATION = 120 -- updated from the real buff whenever we can see it

local function findShout()
	if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
		for _, id in ipairs(BATTLE_SHOUT) do
			local aura = safe(C_UnitAuras.GetPlayerAuraBySpellID, id)
			if aura then return aura end
		end
	end
	if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
		local name = (C_Spell and C_Spell.GetSpellName and safe(C_Spell.GetSpellName, 6673)) or "Battle Shout"
		local aura = safe(C_UnitAuras.GetAuraDataBySpellName, "player", name, "HELPFUL")
		if aura then return aura end
	end
	return nil
end

local function shoutMissing()
	if not knownRank(BATTLE_SHOUT) then return false end
	local aura = findShout()
	if aura then
		local exp = aura.expirationTime
		if exp and not isSecret(exp) then
			shoutExpires = (exp == 0) and math.huge or exp
		end
		local dur = aura.duration
		if dur and not isSecret(dur) and dur > 0 then SHOUT_DURATION = dur end
		return false
	end
	if InCombatLockdown() and shoutExpires > GetTime() then
		return false -- aura hidden from us in combat but should still be up
	end
	if not InCombatLockdown() then shoutExpires = 0 end
	return true
end

-- Spotting your own Battle Shout casts, so the icon clears mid-combat even
-- when the game hides the buff itself from addons.
local isShoutID = {}
for _, id in ipairs(BATTLE_SHOUT) do isShoutID[id] = true end

local function shoutCast()
	shoutExpires = GetTime() + SHOUT_DURATION
end

-- Pressing an action button that holds Battle Shout (directly or via macro).
local shoutPressedAt = 0
local function actionIsShout(slot)
	local kind, id = safe(GetActionInfo, slot)
	if isSecret(kind) or isSecret(id) then return false end
	if kind == "spell" then return isShoutID[id] or false end
	if kind == "macro" and GetMacroSpell then
		local spell = safe(GetMacroSpell, id)
		return spell and not isSecret(spell) and isShoutID[spell] or false
	end
	return false
end
if UseAction and hooksecurefunc then
	hooksecurefunc("UseAction", function(slot)
		if actionIsShout(slot) then shoutPressedAt = GetTime() end
	end)
end

local shoutEvents = CreateFrame("Frame")
shoutEvents:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
shoutEvents:SetScript("OnEvent", function(_, _, _, _, spellID)
	if not isSecret(spellID) then
		if isShoutID[spellID] then shoutCast() end
	elseif GetTime() - shoutPressedAt < 1.5 then
		-- Spell hidden from us: trust the Battle Shout button pressed just now.
		shoutCast()
	end
	if isSecret(spellID) or isShoutID[spellID] then shoutPressedAt = 0 end
end)

---------------------------------------------------------------------------
-- Overpower check
---------------------------------------------------------------------------
local GCD = 1.5

local function overpowerReady()
	local id = knownRank(OVERPOWER)
	if not id then return false end

	local usable
	if C_Spell and C_Spell.IsSpellUsable then
		usable = safe(C_Spell.IsSpellUsable, id)
	elseif IsUsableSpell then
		usable = safe(IsUsableSpell, id)
	end
	if isSecret(usable) or not usable then return false end

	-- Ignore the global cooldown, but hide while Overpower's own cooldown runs.
	local start, duration
	if C_Spell and C_Spell.GetSpellCooldown then
		local cd = safe(C_Spell.GetSpellCooldown, id)
		if type(cd) == "table" then start, duration = cd.startTime, cd.duration end
	elseif GetSpellCooldown then
		start, duration = safe(GetSpellCooldown, id)
	end
	if start and duration and not isSecret(start) and not isSecret(duration) then
		if duration > GCD and (start + duration - GetTime()) > 0 then
			return false
		end
	end
	return true
end

---------------------------------------------------------------------------
-- Update loop
---------------------------------------------------------------------------
local _, playerClass = UnitClass("player")
local isWarrior = playerClass == "WARRIOR"
local preview = false
local states = {}
local elapsedSince = 0

local function refreshTextures()
	icons[1].frame.tex:SetTexture(spellTexture(knownRank(BATTLE_SHOUT) or 6673, icons[1].frame.fallback))
	icons[2].frame.tex:SetTexture(spellTexture(knownRank(OVERPOWER) or 7384, icons[2].frame.fallback))
end

---------------------------------------------------------------------------
-- Well-Rested (Cozy Sleeping Bag) running low: 10 minutes or less left.
-- Shows the sleeping bag icon with the time left in the reminder column,
-- with a sound and chat line once each time it drops under 10 minutes.
-- Also when the buff is gone (out of combat): "Use Sleeping Bag", or how
-- long until the bag's cooldown is over. Not at max level.
---------------------------------------------------------------------------
local WELL_RESTED = 429959   -- Well-Rested aura
local SLEEPING_BAG = 211527  -- Cozy Sleeping Bag
local RESTED_WARN = 10 * 60

local restedFrame = icons[4].frame
restedFrame.label = restedFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
restedFrame.label:SetPoint("LEFT", restedFrame, "RIGHT", 6, 0)
restedFrame.label:SetTextColor(0.55, 0.8, 1.0)

local function findWellRested()
	if not (C_UnitAuras) then return nil end
	local aura = C_UnitAuras.GetPlayerAuraBySpellID and safe(C_UnitAuras.GetPlayerAuraBySpellID, WELL_RESTED)
	if aura then return aura end
	-- Stacks may carry their own spell IDs: try by name too.
	local name = C_Spell and C_Spell.GetSpellName and safe(C_Spell.GetSpellName, WELL_RESTED)
	if name and not isSecret(name) and C_UnitAuras.GetAuraDataBySpellName then
		return safe(C_UnitAuras.GetAuraDataBySpellName, "player", name, "HELPFUL")
	end
end

-- Minutes until the sleeping bag can be used again, or nil if it's ready.
local function bagCooldown()
	local getCD = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
	local start, duration = safe(getCD, SLEEPING_BAG)
	if not start or isSecret(start) or isSecret(duration) or start == 0 or duration <= 1.5 then return nil end
	local left = start + duration - GetTime()
	return left > 0 and math.ceil(left / 60) or nil
end

local function maxLevel()
	local cap = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or MAX_PLAYER_LEVEL or 60
	return UnitLevel("player") >= cap
end

-- Label for the reminder, or nil when there's nothing to remind:
--   "Well-Rested 7m"          - 10 minutes or less left
--   "Use Sleeping Bag"        - the buff is gone and the bag is ready
--   "Sleeping Bag ready in 12m" - the buff is gone, bag still cooling down
local restedWarned, restedLabel, restedChecked = nil, nil, 0
local function wellRestedReminder()
	local now = GetTime()
	if now - restedChecked < 1 then return restedLabel end
	restedChecked = now
	restedLabel = nil

	local count = C_Item and C_Item.GetItemCount and safe(C_Item.GetItemCount, SLEEPING_BAG) or safe(GetItemCount, SLEEPING_BAG)
	if not count or isSecret(count) or count < 1 then return nil end
	if maxLevel() or UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then return nil end

	local aura = findWellRested()
	local warnKey, message
	if aura then
		local exp = aura.expirationTime
		if not exp or isSecret(exp) or exp == 0 then return nil end
		local left = exp - now
		if left > RESTED_WARN then restedWarned = nil return nil end
		if left <= 0 then return nil end
		restedLabel = ("Well-Rested %dm"):format(math.ceil(left / 60))
		warnKey = "low"
		message = ("Well-Rested has %d minutes left - use your Cozy Sleeping Bag"):format(math.ceil(left / 60))
	else
		-- In combat auras can be hidden from addons: only call it missing out of combat.
		if InCombatLockdown() then return nil end
		local cd = bagCooldown()
		restedLabel = cd and ("Sleeping Bag ready in %dm"):format(cd) or "Use Sleeping Bag"
		if not cd then
			warnKey = "missing"
			message = "Well-Rested is gone - use your Cozy Sleeping Bag"
		end
	end

	if not restedFrame.iconSet then
		local tex = C_Item and C_Item.GetItemIconByID and safe(C_Item.GetItemIconByID, SLEEPING_BAG)
		if tex then restedFrame.tex:SetTexture(tex) restedFrame.iconSet = true end
	end
	-- Sound and chat line once per state (running low, then gone with the bag ready).
	if warnKey and restedWarned ~= warnKey then
		restedWarned = warnKey
		PlaySound((SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
		print("|cff66ccffZyde_Forever|r: " .. message)
	end
	return restedLabel
end

local function update()
	if preview then
		states.shout, states.overpower = true, true
		icons[1].frame.label:SetText("Shout")
	elseif not isWarrior or UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then
		states.shout, states.overpower = false, false
	else
		-- Always check (keeps the remembered expiry fresh). The icon itself
		-- only shows during a fight.
		local missing = shoutMissing()
		local left = shoutExpires - GetTime()
		local low = not missing and shoutExpires ~= math.huge and left > 0 and left < 10
		states.shout = F("shout") and (missing or low) and UnitAffectingCombat("player") or false
		if states.shout then
			icons[1].frame.label:SetText(low and ("Shout %ds"):format(math.max(1, math.ceil(left))) or "Shout")
		end
		states.overpower = F("overpower") and overpowerReady() or false
	end
	-- Well-Rested reminder: any class, any time.
	if preview then
		states.rested = true
		restedFrame.label:SetText("Well-Rested 9m")
	elseif F("rested") and wellRestedReminder() then
		states.rested = true
		restedFrame.label:SetText(restedLabel)
	else
		states.rested = false
	end
	for _, r in ipairs(reminders) do
		local ok, show, label = pcall(r.check, preview)
		states[r.key] = ok and show and true or false
		if states[r.key] then r.frame.label:SetText(label or "") end
	end
	layout(states)
end

anchor:SetScript("OnUpdate", function(_, elapsed)
	-- The big icons on your character pulse every frame. The side column does not.
	local now = GetTime()
	for _, icon in ipairs(icons) do
		local f = icon.frame
		if f.prominent and f:IsShown() then
			f:SetAlpha(0.35 + 0.65 * math.abs(math.sin(now * (f.pulseFast and 8 or 4))))
		end
	end
	elapsedSince = elapsedSince + elapsed
	if elapsedSince < POLL then return end
	elapsedSince = 0
	update()
end)

---------------------------------------------------------------------------
-- Hunter: no Aspect up -> Aspect of the Hawk tile in the reminder column.
-- Any aspect counts (Hawk, Monkey, Cheetah, Pack, Beast, Wild).
-- In combat the game can hide auras from addons, so there we trust what we
-- last saw out of combat, and any aspect you cast.
---------------------------------------------------------------------------
local ASPECT_HAWK = { 13165, 14318, 14319, 14320, 14321, 14322, 25296 }
local ASPECTS = { 13165, 14318, 14319, 14320, 14321, 14322, 25296, -- Hawk
	13163, 5118, 13159, 13161, 20043, 20190 }                      -- Monkey, Cheetah, Pack, Beast, Wild
local isAspect = {}
for _, id in ipairs(ASPECTS) do isAspect[id] = true end
local isHunter = playerClass == "HUNTER"
local aspectSeen = false -- last known: an aspect is up

-- Is an aspect on? true, false, or nil when the game hides your buffs (in
-- combat, and in dungeons even out of combat) so we can't tell.
local function aspectUp()
	if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
		for _, id in ipairs(ASPECTS) do
			if safe(C_UnitAuras.GetPlayerAuraBySpellID, id) then return true end
		end
	end
	-- By name too ("Aspect of the ..."), for ranks or IDs not listed above.
	local buffs = ns.PlayerBuffs()
	if not buffs then return nil end
	local seen = #buffs.list
	for _, b in ipairs(buffs.list) do
		if b.spellId and isAspect[b.spellId] then return true end
		if type(b.name) == "string" and b.name:find("^Aspect of the ") then return true end
	end
	if buffs.hidden then return nil end
	-- Boss fights: the game can hand back no buffs at all instead of hidden ones.
	local boss = IsEncounterInProgress and safe(IsEncounterInProgress)
	if (not isSecret(boss) and boss) or (seen == 0 and InCombatLockdown()) then return nil end
	return false
end

if isHunter then
	local aspectEvents = CreateFrame("Frame")
	aspectEvents:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	aspectEvents:SetScript("OnEvent", function(_, _, _, _, spellID)
		if not isSecret(spellID) and isAspect[spellID] then aspectSeen = true end
	end)
end

local hawkTile = ns.AddReminder("aspect", "ZydeForeverAspect", "Interface\\Icons\\Spell_Nature_RavenForm", function(previewing)
	if not isHunter then return false end
	if previewing then return true end
	if not F("aspect") or not knownRank(ASPECT_HAWK) then return false end
	if UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then return false end
	local up = aspectUp()
	if up == nil then return false end -- buffs hidden: stay quiet rather than nag wrongly
	if up then
		aspectSeen = true
	elseif InCombatLockdown() and aspectSeen then
		up = true -- (the aura list can lag a cast in combat: trust what we last saw)
	else
		aspectSeen = false
	end
	return not up -- just the icon, like the Battle Shout tile
end)
hawkTile.tex:SetTexture(spellTexture(13165, hawkTile.fallback))

---------------------------------------------------------------------------
-- Quest objects on the ground
-- On this client, an object you can interact with gets its own nameplate.
-- We scan those object plates and check each against your quests:
--   1) Questie's quest data (object ID -> unfinished objective)
--   2) objects that gave you a quest item before (learned from loot)
--   3) name matching your unfinished objectives, plurals included
-- A match puts a pulsing quest icon with the object's name in the reminder
-- column, plus a ping.                                   /zyde questalert
-- Settings: we set the interact settings ourselves.
--                                                       /zyde questicons
---------------------------------------------------------------------------
local function questIconsOn() return F("questIcons") end
local function questAlertOn() return F("questAlert") end

-- The gamepad UI sets softTargetInteract itself on every target change.
local function gamepadUI()
	local s = C_InputInterfaceStyle and C_InputInterfaceStyle.GetCurrentStyle and safe(C_InputInterfaceStyle.GetCurrentStyle)
	return Enum and Enum.InputDeviceInterfaceType and s == Enum.InputDeviceInterfaceType.Gamepad or false
end

-- /zyde questrange <yards>: how far away objects are picked up (game default
-- 10, Zyde uses 30).
local function applyQuestRange()
	local db = ZydeForeverDB
	if not db or InCombatLockdown() then return end
	-- An earlier version raised the nameplate draw distance; put yours back.
	if db.plateDistOrig ~= nil then
		pcall(SetCVar, "nameplateMaxDistance", db.plateDistOrig)
		db.plateDistOrig = nil
		db.questRange = 30 -- and the pickup range back to the usual 30
	end
	if db.questRange then pcall(SetCVar, "SoftTargetInteractRange", db.questRange) end
end

local function applyQuestIcons()
	C_Timer.After(1, applyQuestRange)
	if InCombatLockdown() then return end
	local on = questIconsOn()
	if on then
		if not gamepadUI() and (tonumber(GetCVar("SoftTargetInteract")) or 0) < 3 then
			pcall(SetCVar, "SoftTargetInteract", 3)
		end
		pcall(SetCVar, "SoftTargetInteractArc", 2)    -- objects all around you, not only in front
		pcall(SetCVar, "SoftTargetInteractRange", 30) -- yards (default 10)
	end
	pcall(SetCVar, "SoftTargetIconGameObject", on and 1 or 0)
	pcall(SetCVar, "SoftTargetIconInteract", on and 1 or 0)
	-- No nameplate popping up on friendly NPCs you face.
	pcall(SetCVar, "SoftTargetNameplateInteract", 0)
end

local questFrame = icons[3].frame
questFrame.tex:SetTexCoord(0, 1, 0, 1)
questFrame.border:SetColorTexture(0.08, 0.06, 0, 0.85)
questFrame.label = questFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
questFrame.label:SetPoint("LEFT", questFrame, "RIGHT", 6, 0)
questFrame.label:SetTextColor(1, 0.82, 0)
local questPulse = questFrame:CreateAnimationGroup()
questPulse:SetLooping("BOUNCE")
local qa = questPulse:CreateAnimation("Alpha")
qa:SetFromAlpha(1)
qa:SetToAlpha(0.5)
qa:SetDuration(0.6)
qa:SetSmoothing("IN_OUT")
questFrame:HookScript("OnShow", function() questPulse:Play() end)
questFrame:HookScript("OnHide", function() questPulse:Stop() end)

local function plainStr(v)
	if v == nil or isSecret(v) or type(v) ~= "string" or v == "" then return nil end
	return v
end

-- Unfinished objectives: their item/object names and the words in them.
local questNames, questWords, objectivesDirty = {}, {}, true
local STOPWORDS = { the = true, ["and"] = true, ["for"] = true, with = true, from = true }

local function words(text)
	local out = {}
	for w in text:lower():gmatch("[%a\128-\255]+") do
		if #w >= 3 and not STOPWORDS[w] then
			out[#out + 1] = w
			if #w > 4 and w:sub(-3) == "ies" then
				out[#out + 1] = w:sub(1, -4) .. "y"       -- berries -> berry
			elseif #w > 3 and w:sub(-1) == "s" and w:sub(-2) ~= "ss" then
				out[#out + 1] = w:sub(1, -2)              -- cattails -> cattail
			end
		end
	end
	return out
end

-- Quest items you get by killing (Questie: dropped by mobs, never picked up
-- from an object). Their loot left on the ground isn't worth an alert.
local killItems = {}
local function questieKillItem(DB, itemId)
	local okN, npcs = pcall(DB.QueryItemSingle, itemId, "npcDrops")
	local okO, objs = pcall(DB.QueryItemSingle, itemId, "objectDrops")
	if not okN or type(npcs) ~= "table" or not next(npcs) then return false end
	return not (okO and type(objs) == "table" and next(objs))
end
local function readKillItems(questIDs)
	wipe(killItems)
	if not (QuestieLoader and QuestieLoader.ImportModule) then return end
	local ok, DB = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
	if not (ok and DB and DB.GetQuest and DB.QueryItemSingle) then return end
	for _, qid in ipairs(questIDs) do
		local okQ, q = pcall(DB.GetQuest, qid)
		for _, o in ipairs(okQ and q and q.ObjectiveData or {}) do
			if o.Type == "item" and o.Id and questieKillItem(DB, o.Id) then
				local okName, name = pcall(DB.QueryItemSingle, o.Id, "name")
				if okName and type(name) == "string" then killItems[name:lower()] = true end
			end
		end
	end
end

local function readObjectives()
	objectivesDirty = false
	wipe(questNames)
	wipe(questWords)
	local questIDs = {}
	if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
		for i = 1, (safe(C_QuestLog.GetNumQuestLogEntries) or 0) do
			local info = safe(C_QuestLog.GetInfo, i)
			local qid = info and not info.isHeader and info.questID
			if type(qid) == "number" and not isSecret(qid) then questIDs[#questIDs + 1] = qid end
		end
	end
	readKillItems(questIDs)
	local function add(text, finished)
		text = plainStr(text)
		if not text or finished then return end
		local name = (text:match("^(.-):%s*%d+%s*/%s*%d+") or text:match("^%s*%d+%s*/%s*%d+%s+(.-)%s*$") or text):lower()
		if killItems[name] then return end -- (dropped by mobs: no alert for it)
		questNames[name] = true
		for _, w in ipairs(words(name)) do questWords[w] = true end
	end
	if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo and C_QuestLog.GetQuestObjectives then
		for i = 1, (safe(C_QuestLog.GetNumQuestLogEntries) or 0) do
			local info = safe(C_QuestLog.GetInfo, i)
			if info and not info.isHeader and info.questID then
				for _, o in ipairs(safe(C_QuestLog.GetQuestObjectives, info.questID) or {}) do
					if o.type == "item" or o.type == "object" or o.type == nil then add(o.text, o.finished) end
				end
			end
		end
	elseif GetNumQuestLogEntries and GetQuestLogTitle and GetNumQuestLeaderBoards then
		for i = 1, (safe(GetNumQuestLogEntries) or 0) do
			local _, _, _, isHeader = GetQuestLogTitle(i)
			if not isHeader then
				for j = 1, (safe(GetNumQuestLeaderBoards, i) or 0) do
					local text, kind, finished = GetQuestLogLeaderBoard(j, i)
					if kind == "item" or kind == "object" then add(text, finished) end
				end
			end
		end
	end
end

-- Questie knows which objects are quest objectives: its tooltip registry has
-- "o_<objectId>" entries for every unfinished one.
local function questieWantsObject(objectId)
	if not (objectId and QuestieLoader and QuestieLoader.ImportModule) then return false end
	local ok, TT = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieTooltips")
	local tips = ok and TT and TT.lookupByKey and TT.lookupByKey["o_" .. objectId]
	for _, tip in pairs(tips or {}) do
		local obj = tip.objective
		if obj then
			if obj.Update then pcall(obj.Update, obj) end
			if not obj.Completed then return true end
		end
	end
	return false
end

local function objectIdFromGUID(guid)
	guid = plainStr(guid)
	if not (guid and guid:find("^GameObject")) then return nil end
	return tonumber((select(6, strsplit("-", guid))))
end

-- Objects that gave you an item an objective asks for: ZydeForeverDB.questObjects[id] = item name.
local function learnedObjects()
	ZydeForeverDB = ZydeForeverDB or {}
	ZydeForeverDB.questObjects = ZydeForeverDB.questObjects or {}
	return ZydeForeverDB.questObjects
end

local function learnFromLoot()
	if objectivesDirty then readObjectives() end
	for slot = 1, (GetNumLootItems and GetNumLootItems() or 0) do
		local _, name = GetLootSlotInfo(slot)
		name = plainStr(name)
		if name and questNames[name:lower()] and GetLootSourceInfo then
			local id = objectIdFromGUID(GetLootSourceInfo(slot))
			if id then learnedObjects()[id] = name:lower() end
		end
	end
end

local function isGameObject(unit)
	if UnitIsGameObject then
		local v = safe(UnitIsGameObject, unit)
		if v ~= nil and not isSecret(v) then return v end
	end
	local guid = plainStr(safe(UnitGUID, unit))
	return guid and guid:find("^GameObject") and true or false
end

-- Why an object is (or isn't) a quest object. Returns reason or nil.
local function questReason(guid, name)
	if objectivesDirty then readObjectives() end
	local id = objectIdFromGUID(guid)
	if id and questieWantsObject(id) then return "Questie quest object " .. id end
	local learned = id and learnedObjects()[id]
	if learned and questNames[learned] then return "gave you \"" .. learned .. "\" before" end
	if name then
		local lname = name:lower()
		for obj in pairs(questNames) do
			if obj == lname or obj:find(lname, 1, true) or lname:find(obj, 1, true) then
				return "name matches \"" .. obj .. "\""
			end
		end
		for _, w in ipairs(words(lname)) do
			if questWords[w] then return "shares the word \"" .. w .. "\"" end
		end
	end
	return nil
end

-- Inside a dungeon the game hides objects' names and IDs from addons, so a
-- quest plant can't be told from a chest. If Questie says an unfinished
-- objective's objects spawn in this dungeon, every unreadable object here gets
-- a dimmer glow (a guess: no ping, no reminder icon). Rechecked every 3 s.
local hiddenObjectHint
do -- own scope (200-local limit)
local hintAt, hint = -math.huge, nil
local function findHint()
	local inside, kind = IsInInstance()
	if not inside or not (kind == "party" or kind == "raid") then return nil end
	if not (QuestieLoader and QuestieLoader.ImportModule) then return nil end
	local here = plainStr(safe(GetInstanceInfo))
	if not here then return nil end
	local okZ, ZDB = pcall(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
	local okD, DB = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
	local okT, TT = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieTooltips")
	if not (okZ and okD and okT and type(ZDB) == "table" and type(DB) == "table" and type(TT) == "table") then return nil end
	-- This dungeon's area IDs (Questie files spawns under them).
	local areas = {}
	local dungeons = ZDB.GetDungeons and safe(ZDB.GetDungeons, ZDB)
	for areaId, e in pairs(type(dungeons) == "table" and dungeons or {}) do
		if type(e) == "table" and e[1] == here then
			areas[areaId] = true
			for _, alt in ipairs(e[2] or {}) do areas[alt] = true end
		end
	end
	if not next(areas) then return nil end
	-- Unfinished object objectives ("o_<objectId>" in Questie's tooltip registry).
	for key, tips in pairs(TT.lookupByKey or {}) do
		local id = type(key) == "string" and tonumber(key:match("^o_(%d+)$"))
		if id and type(tips) == "table" then
			local open = false
			for _, tip in pairs(tips) do
				if type(tip) == "table" and tip.objective and not tip.objective.Completed then open = true break end
			end
			local obj = open and DB.GetObject and safe(DB.GetObject, DB, id)
			if type(obj) == "table" and type(obj.spawns) == "table" then
				for zone in pairs(obj.spawns) do
					if areas[zone] then return obj.name or "a quest object" end
				end
			end
		end
	end
	return nil
end
function hiddenObjectHint()
	if GetTime() - hintAt >= 3 then hintAt, hint = GetTime(), findHint() end
	return hint
end
end -- hidden object hint

-- Object plates in range: list of { unit, guid, name, picked, reason, guess }.
local verdicts = {} -- guid -> reason or false (cleared when quests change)
local function scanObjects()
	local found = {}
	for _, unit in ipairs(ns.Plates.units()) do -- shared list (Plates.lua)
		local rawGuid = safe(UnitGUID, unit)
		if rawGuid ~= nil and isGameObject(unit) then
			local guid = plainStr(rawGuid)
			local name = plainStr(safe(UnitName, unit))
			local reason, guess
			if not guid and not name then
				-- Hidden (in a dungeon): a guess, if a quest wants objects here.
				local hint = hiddenObjectHint()
				if hint then reason, guess = "maybe " .. hint .. " (dungeon: the game hides object names)", true end
			elseif guid and verdicts[guid] ~= nil then
				reason = verdicts[guid] or nil
			else
				reason = questReason(guid, name)
				if guid then verdicts[guid] = reason or false end
			end
			local picked = safe(UnitIsUnit, unit, "softinteract")
			found[#found + 1] = { unit = unit, guid = guid, name = name, reason = reason, guess = guess,
				picked = not isSecret(picked) and picked == true }
		end
	end
	return found
end

-- Marker drawn on a quest object's nameplate (the plate sits just above the
-- object): a pulsing gold glow on the object and a bobbing quest "!" over it.
-- Parented to the plate itself, so another addon hiding the plate's own art
-- doesn't hide it.
local markers = {} -- plate -> marker frame

local function getMarker(plate)
	local m = markers[plate]
	if m then return m end
	m = CreateFrame("Frame", nil, plate)
	m:SetSize(1, 1)
	m:SetPoint("BOTTOM", plate, "BOTTOM", 0, 0)
	m:SetFrameStrata("BACKGROUND")

	m.glow = m:CreateTexture(nil, "ARTWORK")
	m.glow:SetSize(90, 90)
	m.glow:SetPoint("CENTER", m, "CENTER", 0, -50)
	if not m.glow:SetAtlas("BonusChest-CircleGlow") then
		m.glow:SetTexture("Interface\\Cooldown\\star4")
	end
	m.glow:SetBlendMode("ADD")
	m.glow:SetVertexColor(1, 0.85, 0.25)

	m.bang = m:CreateTexture(nil, "OVERLAY")
	m.bang:SetSize(26, 26)
	m.bang:SetPoint("BOTTOM", m, "CENTER", 0, 4)
	m.bang:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")

	local pulse = m:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local a = pulse:CreateAnimation("Alpha")
	a:SetTarget(m.glow)
	a:SetFromAlpha(1)
	a:SetToAlpha(0.35)
	a:SetDuration(0.9)
	a:SetSmoothing("IN_OUT")
	local bob = pulse:CreateAnimation("Translation")
	bob:SetTarget(m.bang)
	bob:SetOffset(0, 6)
	bob:SetDuration(0.9)
	bob:SetSmoothing("IN_OUT")
	m.pulse = pulse

	markers[plate] = m
	return m
end

local wantedPlates = {} -- reused by updateMarkers (no new table per scan)
local function updateMarkers(objects) -- objects nil: hide them all
	local wanted = wantedPlates
	wipe(wanted)
	for _, o in ipairs(objects or wanted) do
		if o.reason then
			local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(o.unit)
			-- (value: 1 for a sure match, a dimmer 0.5 for a dungeon guess)
			if plate then wanted[plate] = o.guess and 0.5 or 1 end
		end
	end
	for plate, alpha in pairs(wanted) do
		local m = getMarker(plate)
		m:SetAlpha(alpha)
		if not m:IsShown() or not m.pulse:IsPlaying() then
			m:Show()
			m.pulse:Play()
		end
	end
	for plate, m in pairs(markers) do
		if not wanted[plate] and m:IsShown() then
			m.pulse:Stop()
			m:Hide()
		end
	end
end

local lastQuestGUID
local function checkQuestObject()
	local best
	local objects -- stays nil (no scan) while the alert is off or you're dead
	if questAlertOn() and not UnitIsDeadOrGhost("player") then
		objects = scanObjects()
		for _, o in ipairs(objects) do
			if o.reason and o.name and (not best or (o.picked and not best.picked)) then best = o end
		end
	end
	updateMarkers(objects)
	if best then
		questFrame.label:SetText(best.name)
		local key = best.guid or best.name
		if key ~= lastQuestGUID then
			lastQuestGUID = key
			PlaySound((SOUNDKIT and SOUNDKIT.MAP_PING) or 3175, "Master")
		end
		states.quest = true
	else
		lastQuestGUID = nil
		states.quest = preview or false
		if preview then questFrame.label:SetText("Quest item") end
	end
	layout(states)
end

-- /zyde questdebug: what the scan sees right now.
local function questDebug(p)
	for _, cvar in ipairs({ "SoftTargetInteract", "SoftTargetIconGameObject", "SoftTargetInteractArc", "SoftTargetInteractRange", "nameplateMaxDistance" }) do
		print(p .. cvar .. " = " .. tostring(GetCVar(cvar)))
	end
	print(p .. "alert " .. (questAlertOn() and "on" or "off") .. ", Questie " .. (QuestieLoader and "loaded" or "not loaded")
		.. ", gamepad UI " .. tostring(gamepadUI()))
	wipe(verdicts)
	objectivesDirty = true
	local objects = scanObjects()
	local n = 0
	for _ in pairs(questNames) do n = n + 1 end
	print(p .. n .. " unfinished item/object objectives in your log")
	if #objects == 0 then print(p .. "  no object nameplates near you") end
	for _, o in ipairs(objects) do
		print(("%s  %s%s (id %s): %s"):format(p, tostring(o.name), o.picked and " [targeted]" or "",
			tostring(objectIdFromGUID(o.guid)), o.reason or "not a quest object"))
	end
end

do -- own scope (200-local limit)
-- Nameplates come and go in bursts (a crowd, a city): check once, a moment
-- after the last event, instead of once per event.
local checkPending = false
local function checkSoon()
	if checkPending then return end
	checkPending = true
	C_Timer.After(0.1, function() checkPending = false checkQuestObject() end)
end

local questEvents = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_LOG_UPDATE", "LOOT_READY", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
	"NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_SOFT_INTERACT_CHANGED" }) do
	pcall(questEvents.RegisterEvent, questEvents, e)
end
questEvents:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
		applyQuestIcons()
	elseif event == "QUEST_LOG_UPDATE" then
		objectivesDirty = true
		wipe(verdicts)
	elseif event == "LOOT_READY" then
		learnFromLoot()
		wipe(verdicts)
	end
	checkSoon()
end)
end -- quest object events
-- Backup for plates that change without an event, on the shared nameplate driver
-- (Plates.lua loads after this file: set it up once everything has loaded).
C_Timer.After(0, function() ns.Plates.Every(1, checkQuestObject) end)
ns.OnFeatureChanged(function(key)
	if key == "questIcons" then applyQuestIcons() end
	if key == "questAlert" then checkQuestObject() end
end)

---------------------------------------------------------------------------
-- Hide Blizzard bars
---------------------------------------------------------------------------
local hidden = CreateFrame("Frame", "ZydeForeverHidden", UIParent)
hidden:Hide()

-- Move a whole frame into an always-hidden parent (bag bar, micro menu).
local function stash(frame)
	if not frame or frame:GetParent() == hidden then return end
	if frame.IsProtected and frame:IsProtected() and InCombatLockdown() then return end
	frame:SetParent(hidden)
end

-- /zyde microdebug: remember what moved the micro menu into the hidden holder (and from where),
-- so a stuck micro menu can be traced to the code that did it.
do
	for _, name in ipairs({ "MicroMenuContainer", "MicroMenu" }) do
		local f = _G[name]
		if f and f.SetParent then
			hooksecurefunc(f, "SetParent", function(self, parent)
				if parent == hidden then
					ns.microTrace = ns.microTrace or {}
					ns.microTrace[#ns.microTrace + 1] = name .. " moved into the holder at " .. date("%H:%M:%S")
						.. ":\n" .. (debugstack(2, 8, 0) or "?")
				end
			end)
		end
	end
end

-- Make decorative art invisible without touching protected visibility logic.
local function fade(region)
	if region and region.SetAlpha then
		region:SetAlpha(0)
		if not region.zydeHooked and hooksecurefunc then
			region.zydeHooked = true
			hooksecurefunc(region, "SetAlpha", function(self, a)
				if a ~= 0 then self:SetAlpha(0) end
			end)
		end
	end
end
ns.fade = fade -- (Gear.lua)

local hideBarArt -- forward: the art, bag bar and micro menu part

local function hideBlizzardBars()
	-- Experience bar: replaced by the XP readout, so only hidden with it on.
	if F("xp") then
		-- Hidden where they are, not moved: Edit Mode expects these bars to stay
		-- under the game's own bar manager (moving them broke it), and making them
		-- see-through wasn't enough (the game fades them back in). Whenever the
		-- game shows one, it's hidden again.
		for _, c in ipairs({ MainStatusTrackingBarContainer, SecondaryStatusTrackingBarContainer, StatusTrackingBarManager }) do
			if c and not (c.IsProtected and c:IsProtected()) then
				if not c.zydeKeepHidden then
					c.zydeKeepHidden = true
					hooksecurefunc(c, "Show", function(self) if F("xp") then self:Hide() end end)
					hooksecurefunc(c, "SetShown", function(self, shown) if shown and F("xp") then self:Hide() end end)
				end
				c:Hide()
			end
		end
		if not MainStatusTrackingBarContainer then stash(StatusTrackingBarManager) end
		stash(MainMenuExpBar)
		stash(ExhaustionTick)
	end
	if F("hideBars") or F("hideMicroMenu") then hideBarArt() end
	-- Safety net: with "Hide micro menu" off, the menu never stays in the hidden holder
	-- (it can be carried there along with another bar).
	local mm = MicroMenuContainer or MicroMenu
	if not F("hideMicroMenu") and mm and mm:GetParent() == hidden
		and not (mm.IsProtected and mm:IsProtected() and InCombatLockdown()) then
		mm:SetParent(UIParent)
	end
	-- and once more a moment later, in case the game re-lays out its bars after us
	if not F("hideMicroMenu") and C_Timer and not ns.microRecheck then
		ns.microRecheck = true
		C_Timer.After(2, function()
			ns.microRecheck = nil
			local m = MicroMenuContainer or MicroMenu
			if m and m:GetParent() == hidden and not InCombatLockdown() then m:SetParent(UIParent) end
		end)
	end
end

hideBarArt = function()
	-- Micro menu: its own toggle ("Hide micro menu").
	if F("hideMicroMenu") then
		stash(MicroMenuContainer)
		if not MicroMenuContainer then
			stash(MicroMenu)
			stash(MicroButtonAndBagsBar)
			if MICRO_BUTTONS then
				for _, name in ipairs(MICRO_BUTTONS) do stash(_G[name]) end
			end
		end
	end
	if not F("hideBars") then return end

	-- Main action bar art (gryphons / end caps, border, background).
	local bar = MainActionBar or MainMenuBar
	if bar then
		fade(bar.EndCaps)
		fade(bar.BorderArt)
		fade(bar.Background)
		fade(bar.ActionBarPageNumber)
	end
	-- Older-style art frames, if this client has them.
	fade(MainMenuBarArtFrameBackground)
	fade(MainMenuBarArtFrame and MainMenuBarArtFrame.LeftEndCap)
	fade(MainMenuBarArtFrame and MainMenuBarArtFrame.RightEndCap)
	fade(MainMenuBarArtFrame and MainMenuBarArtFrame.PageNumber)
	fade(MainMenuBarLeftEndCap)
	fade(MainMenuBarRightEndCap)
	for i = 0, 3 do fade(_G["MainMenuBarTexture" .. i]) end

	-- Bag bar. On clients with an Edit Mode bag bar it's hidden where it is, not moved: moving
	-- it into the hidden holder took the micro menu along (the game keeps the two together),
	-- so "Hide micro menu" off still left the menu hidden. Whenever the game shows the bag bar
	-- again it's hidden again, the same way as the XP bars above.
	if BagsBar then
		if not (BagsBar.IsProtected and BagsBar:IsProtected() and InCombatLockdown()) then
			if not BagsBar.zydeKeepHidden then
				BagsBar.zydeKeepHidden = true
				hooksecurefunc(BagsBar, "Show", function(self) if F("hideBars") then self:Hide() end end)
				hooksecurefunc(BagsBar, "SetShown", function(self, shown) if shown and F("hideBars") then self:Hide() end end)
			end
			BagsBar:Hide()
		end
	else
		-- older clients: separate bag buttons, safe to move
		stash(MainMenuBarBackpackButton)
		for i = 0, 3 do stash(_G["CharacterBag" .. i .. "Slot"]) end
		stash(CharacterReagentBag0Slot)
		stash(KeyRingButton)
	end
end

---------------------------------------------------------------------------
-- One Button Fishing
-- Bind a key in Options > Keybindings > AddOns > Zyde Forever.
-- Press 1: casts Fishing. While the line is out, the same key is
-- temporarily rebound to "Interact With Target", which reels in the bobber.
---------------------------------------------------------------------------
BINDING_HEADER_ZYDEFOREVER = "Zyde Forever"
_G["BINDING_NAME_CLICK ZydeForeverFishButton:LeftButton"] = "One Button Fishing"

do -- own scope (200-local limit)
local FISH_BINDING = "CLICK ZydeForeverFishButton:LeftButton"
local FISHING_IDS = { 7620, 7731, 7732, 18248 }

local function fishingName()
	if C_Spell and C_Spell.GetSpellName then
		local n = safe(C_Spell.GetSpellName, 7620)
		if n and not isSecret(n) then return n end
	end
	if GetSpellInfo then
		local n = safe(GetSpellInfo, 7620)
		if n then return n end
	end
	return "Fishing"
end

local fishButton = CreateFrame("Button", "ZydeForeverFishButton", UIParent, "SecureActionButtonTemplate")
fishButton:SetSize(1, 1)
fishButton:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
fishButton:SetAlpha(0)
fishButton:SetAttribute("type", "macro")
fishButton:SetAttribute("macrotext", "/cast Fishing")

local fishOwner = CreateFrame("Frame") -- owns the temporary override bindings
local fishing = false
local savedSoftInteract

local function setupFishButton()
	if InCombatLockdown() then return end
	fishButton:SetAttribute("macrotext", F("fishing") and ("/cast " .. fishingName()) or "")
	-- Fire on key down or key up to match the game's "cast on key down" option,
	-- never both (a second press would restart the cast).
	local down = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
	fishButton:RegisterForClicks(down and "AnyDown" or "AnyUp")
end

local function isFishingChannel(spellID)
	if spellID and not isSecret(spellID) then
		for _, id in ipairs(FISHING_IDS) do
			if spellID == id then return true end
		end
	end
	local name = UnitChannelInfo and UnitChannelInfo("player")
	return name ~= nil and not isSecret(name) and name == fishingName()
end

ns.OnFeatureChanged(function(key) if key == "fishing" then setupFishButton() end end)

local function startReelMode()
	if fishing or InCombatLockdown() or not F("fishing") then return end
	fishing = true
	-- Make sure the bobber can be soft-targeted so Interact can reach it.
	local cur = GetCVar and tonumber(GetCVar("SoftTargetInteract"))
	if cur and cur < 3 then
		savedSoftInteract = cur
		SetCVar("SoftTargetInteract", 3)
	end
	for _, key in ipairs({ GetBindingKey(FISH_BINDING) }) do
		SetOverrideBinding(fishOwner, true, key, "INTERACTTARGET")
	end
end

local function stopReelMode()
	if not fishing then return end
	fishing = false
	if not InCombatLockdown() then ClearOverrideBindings(fishOwner) end
	if savedSoftInteract then
		SetCVar("SoftTargetInteract", savedSoftInteract)
		savedSoftInteract = nil
	end
end

local fishEvents = CreateFrame("Frame")
fishEvents:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
fishEvents:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
fishEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
fishEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
fishEvents:RegisterEvent("PLAYER_LOGIN")
fishEvents:RegisterEvent("CVAR_UPDATE")
fishEvents:SetScript("OnEvent", function(_, event, _, _, spellID)
	if event == "UNIT_SPELLCAST_CHANNEL_START" then
		if isFishingChannel(spellID) then startReelMode() end
	elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		stopReelMode()
	elseif event == "PLAYER_REGEN_DISABLED" then
		stopReelMode() -- pulled into combat: give the key back right away
	else
		if not fishing then setupFishButton() end
		if event == "PLAYER_REGEN_ENABLED" and not fishing then ClearOverrideBindings(fishOwner) end
	end
end)
end -- fishing

---------------------------------------------------------------------------
-- Flight master: skip the "I need a ride" chat and open the flight map.
-- Skipped when the NPC also has quests for you, or if you hold Shift.
---------------------------------------------------------------------------
do -- own scope (200-local limit)
local TAXI_ICONS = {
	[132057] = true,
	["interface\\gossipframe\\taxigossipicon"] = true,
	["interface/gossipframe/taxigossipicon"] = true,
}

local function isTaxiOption(opt)
	if opt.type == "taxi" then return true end
	local icon = opt.icon
	if icon and not isSecret(icon) then
		if type(icon) == "string" then icon = icon:lower() end
		if TAXI_ICONS[icon] then return true end
	end
	return false
end

local function hasQuests()
	local g = C_GossipInfo
	if not g then return false end
	local avail = g.GetAvailableQuests and safe(g.GetAvailableQuests)
	local active = g.GetActiveQuests and safe(g.GetActiveQuests)
	return (type(avail) == "table" and #avail > 0) or (type(active) == "table" and #active > 0)
end

local taxiEvents = CreateFrame("Frame")
taxiEvents:RegisterEvent("GOSSIP_SHOW")
taxiEvents:SetScript("OnEvent", function()
	if not F("flight") or IsShiftKeyDown() or not (C_GossipInfo and C_GossipInfo.GetOptions) then return end
	if hasQuests() then return end
	local options = safe(C_GossipInfo.GetOptions)
	if type(options) ~= "table" then return end
	for _, opt in ipairs(options) do
		if isTaxiOption(opt) then
			if opt.gossipOptionID and C_GossipInfo.SelectOption then
				C_GossipInfo.SelectOption(opt.gossipOptionID)
			elseif opt.orderIndex and C_GossipInfo.SelectOptionByIndex then
				C_GossipInfo.SelectOptionByIndex(opt.orderIndex)
			end
			return
		end
	end
end)
end -- flight master

---------------------------------------------------------------------------
-- Keep tracking through death (Find Minerals, Find Herbs, ...).
-- Dying clears minimap tracking. We remember what was on while you were
-- alive and switch it back on once you're alive again. Turning tracking off
-- yourself while alive is respected.
---------------------------------------------------------------------------
do -- own scope: keeps the file under Lua's 200 top-level locals
local track = {}
if C_Minimap and C_Minimap.GetNumTrackingTypes then
	track.count, track.info, track.set = C_Minimap.GetNumTrackingTypes, C_Minimap.GetTrackingInfo, C_Minimap.SetTracking
elseif GetNumTrackingTypes then
	track.count, track.info, track.set = GetNumTrackingTypes, GetTrackingInfo, SetTracking
end

-- name, active for tracking slot i (handles table or multi-value returns).
local function trackingInfo(i)
	local a, _, active = safe(track.info, i)
	if type(a) == "table" then return a.name, a.active end
	return a, active
end

local function readTracking()
	local on = {}
	local n = track.count and safe(track.count) or 0
	for i = 1, n do
		local name, active = trackingInfo(i)
		if type(name) == "string" and active == true then on[name] = true end
	end
	return on
end

local restoringUntil = 0
local function isDeadNow() return safe(UnitIsDeadOrGhost, "player") == true end

local function saveTracking()
	if not track.count or isDeadNow() then return end
	if GetTime() < restoringUntil then
		C_Timer.After(restoringUntil - GetTime() + 0.5, saveTracking)
		return
	end
	ZydeForeverDB = ZydeForeverDB or {}
	ZydeForeverDB.tracking = readTracking()
end

local function restoreTracking()
	local want = ZydeForeverDB and ZydeForeverDB.tracking
	if not (track.set and want) or isDeadNow() then return end
	local n = safe(track.count) or 0
	for i = 1, n do
		local name, active = trackingInfo(i)
		if name and want[name] and active ~= true then safe(track.set, i, true) end
	end
end

local trackEvents = CreateFrame("Frame")
for _, e in ipairs({ "MINIMAP_UPDATE_TRACKING", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_ENTERING_WORLD" }) do
	pcall(trackEvents.RegisterEvent, trackEvents, e)
end
trackEvents:SetScript("OnEvent", function(_, event)
	if not track.count or not F("tracking") then return end
	if event == "MINIMAP_UPDATE_TRACKING" then
		-- Wait a moment: tracking is cleared right as you die, before the
		-- game reports you dead. Only save if you're still alive after.
		C_Timer.After(1.5, saveTracking)
		return
	end
	if isDeadNow() then return end -- PLAYER_ALIVE also fires on release
	restoringUntil = GetTime() + 8
	restoreTracking()
	for _, t in ipairs({ 0.5, 2, 5 }) do C_Timer.After(t, restoreTracking) end
	C_Timer.After(1, saveTracking) -- records what's on once restoring is done
end)
end -- tracking

-- Shared with UnitFrames.lua
ns.isSecret, ns.safe, ns.stash = isSecret, safe, stash

-- Keep the last few Lua errors (any addon), so /zyde errors can show their
-- text even when the game's error pop-ups are turned off. The game's own
-- error handling still runs as before.
local recentErrors = {}
do
	local previous = geterrorhandler()
	seterrorhandler(function(msg, ...)
		local text = tostring(msg)
		local last = recentErrors[#recentErrors]
		if last and last.text == text then
			last.count = last.count + 1
		else
			recentErrors[#recentErrors + 1] = { text = text, count = 1, at = date and date("%H:%M:%S") or "" }
			if #recentErrors > 10 then table.remove(recentErrors, 1) end
		end
		if previous then return previous(msg, ...) end
	end)
end
ns.RecentErrors = recentErrors
ns.knownRank, ns.spellTexture = knownRank, spellTexture

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "PLAYER_UPDATE_RESTING" }) do
	events:RegisterEvent(e)
end
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(events.RegisterEvent, events, "EDIT_MODE_LAYOUTS_UPDATED")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then ns.PlaceXP() end
	if event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" or event == "UPDATE_EXHAUSTION"
		or event == "PLAYER_UPDATE_RESTING" then
		if event == "PLAYER_XP_UPDATE" then ns.RecordXP() end
		-- PLAYER_LEVEL_UP fires before UnitXPMax changes; check again shortly after.
		ns.UpdateXP()
		if C_Timer then C_Timer.After(0.5, ns.UpdateXP) end
		return
	end
	ns.UpdateXP()
	wipe(rankCache) -- spells learned, login or zoning: look the ranks up again
	if event == "SPELLS_CHANGED" then
		refreshTextures()
	else
		hideBlizzardBars()
		refreshTextures()
	end
	update()
end)

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Options window (/zyde): turn each feature on or off. Saved per account.
-- Kept short: only what applies to you shows (class options for your class,
-- addon features only with that addon), related options sit on one indented
-- line under their parent, and each row's details are in its tooltip.
---------------------------------------------------------------------------
local options
local ROW = 24
local HEAD = 28      -- height of a category heading
local COL_W = 330    -- width of one column of features

-- The window's categories: two columns, each a list of { heading, entries }.
-- An entry is a feature key, or
--   { key, children = {...} }     a feature with options under it (they gray
--                                 out while it's off)
--   { group = "Name", children }  a name with several features on one line
-- Children are feature keys or slider keys (see SLIDERS in buildOptions).
-- chooser = "key" adds a drop-down line under a feature (see CHOOSERS there).
-- A feature missing here still shows, under "Other" at the end.
local CATEGORIES = {
	{
		{ "Interface", {
			{ "unitFrames", children = { "unitAuras", "targetTarget" }, chooser = "frameStyle" },
			{ "plates", children = { "comboPoints" } }, "xp", "reminders",
			{ group = "Action bars", children = { "hideBars", "hideMicroMenu", "barTidy" } },
			"gear",
		} },
		{ "Hunter", { "ammo", "petCare" } },
		{ "Groups", { "lfg", "guildRoster", "markerWheel" } },
	},
	{
		{ "Questing & leveling", {
			{ "questTracker", children = { "questFont" } },
			"autoQuests",
			{ group = "Quest objects", children = { "questAlert", "questIcons" } },
			{ group = "Questie", children = { "questMobs", "questieDrops" } },
			"rares",
		} },
		{ "Bags & vendors", { "scrap", "vendor", "recipes" } },
		{ "Travel & gathering", { "mapNotes", "flight", "tracking", "fishing" } },
	},
}

-- Short names for options shown on an indented line beside each other.
local CHILD_LABEL = {
	unitAuras = "Buffs / debuffs", targetTarget = "Target of target", comboPoints = "Combo points",
	hideBars = "Hide bar art", hideMicroMenu = "Hide micro menu", barTidy = "Tidy keys & slots",
	questAlert = "Glow alert", questIcons = "Icons over nodes",
	questMobs = "Quest mobs", questieDrops = "Drop chances",
}

-- Short names for "needs ..." notes (an addon's folder name can be long).
local function addonTitle(name)
	for _, a in ipairs(ns.ADDONS) do
		if a.name == name then return a.title end
	end
	return name
end

local function buildOptions()
	-- Sliders that sit in the lists like an option (by key in CATEGORIES).
	local SLIDERS = {
		questFont = {
			label = "Text size", min = 10, max = 20, parent = "questTracker",
			desc = "How big the quest tracker's text is (13 is the normal size). The tracker grows with it.",
			get = function() return ns.QuestTracker and ns.QuestTracker.GetFontSize() or 13 end,
			set = function(v) if ns.QuestTracker then ns.QuestTracker.SetFontSize(v) end end,
		},
	}

	-- Drop-downs (a feature's `chooser` in CATEGORIES).
	local CHOOSERS = {
		frameStyle = {
			label = "Style", parent = "unitFrames",
			desc = "How the player, target and party frames look. Takes a reload.",
			options = function() return ns.UnitFrames and ns.UnitFrames.STYLES or {} end,
			get = function() return ns.UnitFrames and ns.UnitFrames.GetStyle() end,
			set = function(k) if ns.UnitFrames then ns.UnitFrames.SetStyle(k) end end,
			changed = function()
				local UF = ns.UnitFrames
				return UF and UF.styleAtLoad and UF.styleAtLoad ~= UF.GetStyle() or false
			end,
		},
	}

	-- Shown here? Class options only for that class; addon features only
	-- when the addon is loaded (the rest are listed at the bottom).
	local hiddenFor = {} -- addon -> true, for the bottom note
	local function visible(key)
		if SLIDERS[key] then return true end
		local f = FEATURE_BY_KEY[key]
		if not f then return false end
		if f.class and f.class ~= playerClass then return false end
		if f.needs and not addonOn(f.needs) then hiddenFor[addonTitle(f.needs)] = true return false end
		return true
	end

	-- Anything not placed in a category goes under "Other" in the second column.
	local placed, other = {}, {}
	local function mark(e)
		if type(e) == "string" then placed[e] = true return end
		if e[1] then placed[e[1]] = true end
		for _, c in ipairs(e.children or {}) do placed[c] = true end
	end
	for _, col in ipairs(CATEGORIES) do
		for _, cat in ipairs(col) do
			for _, e in ipairs(cat[2]) do mark(e) end
		end
	end
	for _, f in ipairs(FEATURES) do
		if not placed[f.key] then other[#other + 1] = f.key end
	end
	if #other > 0 and not CATEGORIES.otherAdded then
		CATEGORIES.otherAdded = true
		table.insert(CATEGORIES[2], { "Other", other })
	end

	local o = CreateFrame("Frame", "ZydeForeverOptions", UIParent, "BackdropTemplate")
	o:SetPoint("CENTER")
	o:SetFrameStrata("DIALOG")
	o:SetMovable(true)
	o:EnableMouse(true)
	o:RegisterForDrag("LeftButton")
	o:SetScript("OnDragStart", o.StartMoving)
	o:SetScript("OnDragStop", o.StopMovingOrSizing)
	o:SetClampedToScreen(true)
	o:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	o:SetBackdropColor(0.07, 0.07, 0.08, 0.95)
	o:SetBackdropBorderColor(0.69, 0.35, 1, 0.9)
	tinsert(UISpecialFrames, "ZydeForeverOptions") -- Escape closes it

	local title = o:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 14, -12)
	title:SetText("Zyde Forever")
	title:SetTextColor(0.69, 0.35, 1)
	local sub = o:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
	sub:SetText("Hover an option for details.  /zyde help for commands.")

	local close = CreateFrame("Button", nil, o, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)

	o.rows, o.sliders, o.choosers = {}, {}, {}

	local function heading(x, y, text)
		local h = o:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		h:SetPoint("TOPLEFT", x + 4, y - 8)
		h:SetText(text)
		h:SetTextColor(0.69, 0.35, 1)
		local line = o:CreateTexture(nil, "ARTWORK")
		line:SetColorTexture(0.69, 0.35, 1, 0.35)
		line:SetHeight(1)
		line:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -3)
		line:SetWidth(COL_W - 24)
	end

	local function tooltip(owner, feat)
		GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
		GameTooltip:AddLine(feat.label)
		GameTooltip:AddLine(feat.desc, 1, 1, 1, true)
		local blocked = featureBlocked(feat.key)
		if blocked then GameTooltip:AddLine("Off: " .. blocked .. ".", 1, 0.4, 0.3, true) end
		if feat.reload then GameTooltip:AddLine("Turning it off fully takes a /reload.", 0.7, 0.7, 0.7, true) end
		GameTooltip:Show()
	end

	-- A checkbox for one feature. small: the short label, for an indented line.
	local function checkbox(feat, x, y, small, parentKey)
		local cb = CreateFrame("CheckButton", nil, o, "UICheckButtonTemplate")
		cb:SetSize(small and 20 or 24, small and 20 or 24)
		cb:SetPoint("TOPLEFT", x, small and y - 2 or y)
		cb.label = cb:CreateFontString(nil, "OVERLAY", small and "GameFontHighlightSmall" or "GameFontHighlight")
		cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
		cb.label:SetText(small and (CHILD_LABEL[feat.key] or feat.label) or feat.label)
		cb.baseLabel = cb.label:GetText()
		cb.label:SetJustifyH("LEFT")
		-- Only when there's something to say: "reload to apply", "needs Questie".
		cb.note = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		cb.note:SetPoint("LEFT", cb.label, "RIGHT", 6, 0)
		cb.feat, cb.parentKey, cb.small = feat, parentKey, small
		cb:SetScript("OnClick", function(self)
			setFeature(feat.key, self:GetChecked())
			if feat.key == "xp" or feat.key == "hideBars" or feat.key == "hideMicroMenu" then pcall(hideBlizzardBars) end
			o:Refresh()
		end)
		cb:SetScript("OnEnter", function(self) tooltip(self, feat) end)
		cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
		o.rows[#o.rows + 1] = cb
		return cb
	end

	local function sliderRow(def, x, y)
		local s = CreateFrame("Slider", nil, o, "BackdropTemplate")
		s.def = def
		s.label = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		s.label:SetPoint("TOPLEFT", x + 4, y - 6)
		s.label:SetText(def.label)
		s:SetOrientation("HORIZONTAL")
		s:SetSize(130, 10)
		s:SetPoint("LEFT", s.label, "RIGHT", 10, 0)
		s:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		s:SetBackdropColor(0, 0, 0, 0.6)
		s:SetBackdropBorderColor(0.69, 0.35, 1, 0.5)
		s:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
		local thumb = s:GetThumbTexture()
		thumb:SetSize(8, 16)
		thumb:SetVertexColor(0.69, 0.35, 1)
		s:SetMinMaxValues(def.min, def.max)
		s:SetValueStep(1)
		if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
		s.value = o:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		s.value:SetPoint("LEFT", s, "RIGHT", 8, 0)
		s:SetScript("OnValueChanged", function(self, v)
			v = math.floor(v + 0.5)
			self.value:SetText(v)
			if self.loading or v == self.last then return end
			self.last = v
			def.set(v)
		end)
		s:EnableMouseWheel(true)
		s:SetScript("OnMouseWheel", function(self, d) if self:IsEnabled() then self:SetValue(self:GetValue() + d) end end)
		s:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(def.label)
			GameTooltip:AddLine(def.desc, 1, 1, 1, true)
			GameTooltip:AddLine("Drag, or use the mouse wheel over it.", 0.7, 0.7, 0.7, true)
			GameTooltip:Show()
		end)
		s:SetScript("OnLeave", function() GameTooltip:Hide() end)
		o.sliders[#o.sliders + 1] = s
	end

	-- "Style  [ Gilded Slant  v ]": click for the list, hover a choice for what it looks like.
	local function chooserRow(def, x, y)
		local c = CreateFrame("Button", nil, o, "BackdropTemplate")
		c.def = def
		c.label = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		c.label:SetPoint("TOPLEFT", x + 4, y - 6)
		c.label:SetText(def.label)
		c:SetSize(150, 20)
		c:SetPoint("LEFT", c.label, "RIGHT", 10, 0)
		c:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		c:SetBackdropColor(0, 0, 0, 0.6)
		c:SetBackdropBorderColor(0.69, 0.35, 1, 0.5)
		c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		c.text:SetPoint("LEFT", 8, 0)
		local arrow = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		arrow:SetPoint("RIGHT", -7, 0)
		arrow:SetText("v")
		c.note = o:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		c.note:SetPoint("LEFT", c, "RIGHT", 8, 0)

		local menu = CreateFrame("Frame", nil, c, "BackdropTemplate")
		menu:SetPoint("TOPLEFT", c, "BOTTOMLEFT", 0, -2)
		menu:SetFrameLevel(o:GetFrameLevel() + 40)
		menu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		menu:SetBackdropColor(0.05, 0.05, 0.06, 0.98)
		menu:SetBackdropBorderColor(0.69, 0.35, 1, 0.8)
		menu:Hide()
		c.menu = menu
		local list = def.options()
		for i, opt in ipairs(list) do
			local b = CreateFrame("Button", nil, menu)
			b:SetSize(148, 20)
			b:SetPoint("TOPLEFT", 1, -1 - (i - 1) * 20)
			local hl = b:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints()
			hl:SetColorTexture(0.69, 0.35, 1, 0.3)
			b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			b.text:SetPoint("LEFT", 8, 0)
			b.text:SetText(opt.label)
			b:SetScript("OnClick", function()
				def.set(opt.key)
				menu:Hide()
				o:Refresh()
			end)
			b:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:AddLine(opt.label)
				GameTooltip:AddLine(opt.desc, 1, 1, 1, true)
				GameTooltip:Show()
			end)
			b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		end
		menu:SetSize(150, #list * 20 + 2)
		c:SetScript("OnClick", function() menu:SetShown(not menu:IsShown()) end)
		c:SetScript("OnHide", function() menu:Hide() end)
		c:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(def.label)
			GameTooltip:AddLine(def.desc, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		c:SetScript("OnLeave", function() GameTooltip:Hide() end)
		o.choosers[#o.choosers + 1] = c
	end

	-- One indented line of children: checkboxes side by side, or a slider. A checkbox that would run
	-- into the next column goes on a new line underneath. Returns how many lines it took (0 = none).
	local INDENT = 26
	local function childLine(children, x, y, parentKey, right)
		local start = x + INDENT
		local cx, lines = start, 0
		for _, k in ipairs(children) do
			if SLIDERS[k] then
				sliderRow(SLIDERS[k], cx, y)
				lines = math.max(lines, 1)
			elseif visible(k) then
				lines = math.max(lines, 1)
				local cb = checkbox(FEATURE_BY_KEY[k], cx, y - (lines - 1) * ROW, true, parentKey)
				local w = 24 + math.ceil(cb.label:GetStringWidth())
				if right and cx > start and cx + w > right then
					lines = lines + 1
					cx = start
					cb:ClearAllPoints()
					cb:SetPoint("TOPLEFT", cx, y - (lines - 1) * ROW - 2)
				end
				cx = cx + w + 14
			end
		end
		return lines
	end

	local function anyVisible(list)
		for _, k in ipairs(list) do if visible(k) then return true end end
		return false
	end

	-- Lay out both columns, top to bottom.
	local tallest = 0
	for c, col in ipairs(CATEGORIES) do
		local x, y = 12 + (c - 1) * COL_W, -46
		for _, cat in ipairs(col) do
			local entries = {}
			for _, e in ipairs(cat[2]) do
				if type(e) == "string" then
					if visible(e) then entries[#entries + 1] = e end
				elseif e.group then
					if anyVisible(e.children) then entries[#entries + 1] = e end
				elseif visible(e[1]) then
					entries[#entries + 1] = e
				end
			end
			if #entries > 0 then
				heading(x, y, cat[1])
				y = y - HEAD
				for _, e in ipairs(entries) do
					if type(e) == "string" then
						if SLIDERS[e] then sliderRow(SLIDERS[e], x, y) else checkbox(FEATURE_BY_KEY[e], x, y) end
						y = y - ROW
					elseif e.group then
						-- "Action bars:  [x] Hide bar art  [x] Tidy keys & slots"
						local name = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
						name:SetPoint("TOPLEFT", x + 4, y - 5)
						name:SetText(e.group)
						local lines = childLine(e.children, x + math.max(84, math.ceil(name:GetStringWidth()) + 14) - INDENT, y, nil, x + COL_W - 16)
						y = y - ROW * math.max(1, lines)
					else
						checkbox(FEATURE_BY_KEY[e[1]], x, y)
						y = y - ROW
						y = y - ROW * childLine(e.children, x, y, e[1], x + COL_W - 16)
						if e.chooser and CHOOSERS[e.chooser] then
							chooserRow(CHOOSERS[e.chooser], x + INDENT, y)
							y = y - ROW
						end
					end
				end
			end
		end
		tallest = math.max(tallest, -y)
	end

	-- Bottom: the other addons Zyde works with, and what's hidden without them.
	o.addonLine = o:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	o.addonLine:SetPoint("BOTTOMLEFT", 14, 30)
	o.addonLine:SetJustifyH("LEFT")
	o.hiddenLine = o:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	o.hiddenLine:SetPoint("BOTTOMLEFT", 14, 14)
	o.hiddenLine:SetJustifyH("LEFT")
	local missing = {}
	for name in pairs(hiddenFor) do missing[#missing + 1] = name end
	table.sort(missing)
	o.hiddenLine:SetText(#missing > 0 and ("More options appear with " .. table.concat(missing, ", ") .. ".") or "")
	local hover = CreateFrame("Frame", nil, o)
	hover:SetPoint("TOPLEFT", o.addonLine, "TOPLEFT", -2, 2)
	hover:SetPoint("BOTTOMRIGHT", o.addonLine, "BOTTOMRIGHT", 2, -2)
	hover:EnableMouse(true)
	hover:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Other addons Zyde works with")
		for _, a in ipairs(ns.ADDONS) do
			local state = ns.addonState(a.name)
			local r, g, b = 1, 0.3, 0.3
			if state == "on" then r, g, b = 0.35, 1, 0.35 elseif state == "off" then r, g, b = 1, 0.6, 0.2 end
			GameTooltip:AddDoubleLine(a.title, state == "on" and "Installed" or (state == "off" and "Disabled" or "Not installed"), 1, 1, 1, r, g, b)
			GameTooltip:AddLine(a.used, 0.7, 0.7, 0.7, true)
		end
		GameTooltip:Show()
	end)
	hover:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Reload: only when a change needs it.
	local reload = CreateFrame("Button", nil, o, "UIPanelButtonTemplate")
	reload:SetSize(110, 22)
	reload:SetPoint("BOTTOMRIGHT", -12, 12)
	reload:SetText("Reload UI")
	reload:SetScript("OnClick", function() ReloadUI() end)
	o.reload = reload
	o.reloadHint = o:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	o.reloadHint:SetPoint("RIGHT", reload, "LEFT", -8, 0)
	o.reloadHint:SetText("Some changes need a reload")

	o:SetSize(24 + 2 * COL_W, 46 + tallest + 58)

	function o:Refresh()
		local needReload = false
		for _, cb in ipairs(self.rows) do
			local feat = cb.feat
			local blocked = featureBlocked(feat.key)
			local parentOff = cb.parentKey and not featureWanted(cb.parentKey)
			local changed = feat.reload and self.startState[feat.key] ~= featureWanted(feat.key)
			needReload = needReload or changed
			if blocked then
				cb:SetChecked(false)
				cb:Disable()
				cb.label:SetTextColor(0.5, 0.5, 0.5)
				cb.note:SetText("|cffff6650" .. blocked .. "|r")
			else
				cb:SetChecked(featureWanted(feat.key))
				if parentOff then cb:Disable() else cb:Enable() end
				local v = parentOff and 0.5 or 1
				cb.label:SetTextColor(v, v, v)
				if cb.small then
					-- side by side there's no room for a note: a gold name and "*" (the bottom bar says reload)
					cb.label:SetText(changed and ("|cffffd200" .. cb.baseLabel .. "*|r") or cb.baseLabel)
					cb.note:SetText("")
				else
					cb.note:SetText(changed and "|cffffd200reload to apply|r" or "")
				end
			end
		end
		for _, s in ipairs(self.sliders) do
			local v = s.def.get()
			s.loading = true
			s:SetValue(v)
			s.loading = false
			s.last = v
			s.value:SetText(v)
			local live = not s.def.parent or F(s.def.parent)
			if live then s:Enable() else s:Disable() end
			s.label:SetTextColor(live and 1 or 0.5, live and 1 or 0.5, live and 1 or 0.5)
			s:SetAlpha(live and 1 or 0.5)
		end
		for _, c in ipairs(self.choosers) do
			local cur, label = c.def.get(), nil
			for _, opt in ipairs(c.def.options()) do if opt.key == cur then label = opt.label end end
			c.text:SetText(label or "-")
			local live = not c.def.parent or F(c.def.parent)
			if live then c:Enable() else c:Disable() c.menu:Hide() end
			local v = live and 1 or 0.5
			c.label:SetTextColor(v, v, v)
			c:SetAlpha(live and 1 or 0.5)
			local changed = c.def.changed()
			needReload = needReload or changed
			c.note:SetText(changed and "|cffffd200reload to apply|r" or "")
		end
		self.reload:SetShown(needReload)
		self.reloadHint:SetShown(needReload)
		-- Addons: green installed, orange disabled, red missing (hover for details).
		local parts = {}
		for _, a in ipairs(ns.ADDONS) do
			local state = ns.addonState(a.name)
			local color = state == "on" and "|cff59ff59" or (state == "off" and "|cffff9933" or "|cffff4d4d")
			parts[#parts + 1] = color .. a.title .. "|r"
		end
		self.addonLine:SetText("Addons:  " .. table.concat(parts, "  "))
	end
	o:SetScript("OnShow", function(self) self:Refresh() end)
	o:Hide()
	return o
end

-- What each reload-only feature was when the UI loaded.
local startState = {}
local startStateEvents = CreateFrame("Frame")
startStateEvents:RegisterEvent("PLAYER_LOGIN")
startStateEvents:SetScript("OnEvent", function()
	for _, f in ipairs(FEATURES) do startState[f.key] = featureWanted(f.key) end
end)

local function toggleOptions()
	if not options then
		options = buildOptions()
		options.startState = startState
	end
	options:SetShown(not options:IsShown())
end
ns.ToggleOptions = toggleOptions

-- Questie's name for a quest id, when its database is loaded. Nil if it has none.
local function questieQuestName(id)
	local name
	if QuestieLoader and QuestieLoader.ImportModule then
		local ok, DB = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
		if ok and DB and DB.QueryQuestSingle then
			local okN, got = pcall(DB.QueryQuestSingle, id, "name")
			if okN then name = got end
		end
	end
	if (type(name) ~= "string" or name == "") and LibQuestieDB and LibQuestieDB.Quest and LibQuestieDB.Quest.Get then
		name = safe(LibQuestieDB.Quest.Get, id, "name")
	end
	if type(name) ~= "string" or name == "" or isSecret(name) then return nil end
	return name
end

-- Same check as /script print(C_QuestLog.IsQuestFlaggedCompleted(id)).
local function printQuestFlag(id)
	local p = "|cff66ccffZyde_Forever|r: "
	local name = questieQuestName(id)
	local label = "Quest " .. id .. (name and (" (" .. name .. ")") or "") .. " complete?"
	if not (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) then
		print(p .. label .. " nil")
		return
	end
	local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, id)
	if not ok then
		print(p .. label .. " error: " .. tostring(done))
		return
	end
	-- A hidden value still prints on its own, the way the /script line does.
	if isSecret(done) then
		print(p .. label, done)
	else
		print(p .. label .. " " .. tostring(done))
	end
end

SLASH_ZYDEFOREVER1 = "/zyde"
SlashCmdList.ZYDEFOREVER = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "" or msg == "options" or msg == "config" then
		toggleOptions()
	elseif msg == "test" then
		preview = not preview
		print("|cff66ccffZyde_Forever|r: preview " .. (preview and "on" or "off"))
		checkQuestObject()
		update()
	elseif msg == "questalert" then
		setFeature("questAlert", not featureWanted("questAlert"))
		print("|cff66ccffZyde_Forever|r: quest item alert " .. (questAlertOn() and "on" or "off"))
	elseif msg == "questdebug" then
		questDebug("|cff66ccffZyde_Forever|r: ")
	elseif msg == "quest" or msg:match("^quest%s+") then
		local id = tonumber(msg:match("^quest%s+(%d+)"))
		if not id then
			print("|cff66ccffZyde_Forever|r: use /zyde quest <id>, e.g. /zyde quest 867")
		else
			printQuestFlag(id)
		end
	elseif msg:match("^questheight") then
		if ns.QuestTracker and ns.QuestTracker.SetMaxHeight then ns.QuestTracker.SetMaxHeight(tonumber(msg:match("^questheight%s+(%d+)"))) end
	elseif msg:match("^questrange") then
		local p = "|cff66ccffZyde_Forever|r: "
		local yards = tonumber(msg:match("^questrange%s+(%d+)"))
		if not yards then
			print(p .. "object pickup range is " .. tostring(GetCVar("SoftTargetInteractRange"))
				.. " yards. Use /zyde questrange <yards> to change it, e.g. /zyde questrange 60")
		elseif InCombatLockdown() then
			print(p .. "can't change that in combat, try again after")
		else
			ZydeForeverDB = ZydeForeverDB or {}
			ZydeForeverDB.questRange = yards
			applyQuestRange()
			local now = tonumber(GetCVar("SoftTargetInteractRange"))
			print(p .. "object pickup range set to " .. tostring(now) .. " yards"
				.. ((now and now < yards) and (" (the game caps it at " .. now .. ")") or ""))
		end
	elseif msg == "scrap" and ns.Scrap then
		ns.Scrap.Toggle()
	elseif msg == "scraptest" and ns.Scrap then
		ns.Scrap.Test()
	elseif msg == "scrapreset" and ns.Scrap then
		ns.Scrap.ResetKeep()
	elseif msg == "vendor" and ns.Vendor then
		ns.Vendor.Toggle()
	elseif msg == "questicons" then
		setFeature("questIcons", not featureWanted("questIcons"))
		print("|cff66ccffZyde_Forever|r: icons over nearby objects " .. (questIconsOn() and "on" or "off"))
	elseif (msg == "unlock" or msg == "lock" or msg == "resetframes") and ns.UnitFrames then
		ns.UnitFrames.Command(msg)
	elseif msg == "mobsdebug" and ns.QuestMobs then
		ns.QuestMobs.Debug()
	elseif msg == "errors" then
		local list = ns.RecentErrors
		if #list == 0 then
			print("|cff66ccffZyde_Forever|r: no Lua errors since the last /reload")
		else
			print("|cff66ccffZyde_Forever|r: last " .. #list .. " Lua errors (newest last):")
			for _, e in ipairs(list) do
				print(("  |cffff6650%s%s|r %s"):format(e.at, e.count > 1 and (" x" .. e.count) or "", e.text))
			end
		end
	elseif msg == "wheeldebug" and ns.MarkerWheel then
		ns.MarkerWheel.ToggleDebug()
	elseif msg == "rangedebug" then
		if ns.RangeDebug then ns.RangeDebug() else print("|cff66ccffZyde_Forever|r: the range check is for hunters and warriors") end
	elseif msg == "sealdebug" then
		if ns.SealDebug then ns.SealDebug() else print("|cff66ccffZyde_Forever|r: the seal tile is for paladins") end
	elseif msg == "evisdebug" then
		if ns.EvisDebug then ns.EvisDebug() else print("|cff66ccffZyde_Forever|r: the Eviscerate tile is for rogues") end
	elseif msg == "mapnotes" or msg == "mapnotes clear" then
		if ns.MapNotesCommand then ns.MapNotesCommand(msg:match("^mapnotes%s+(%S+)")) end
	elseif msg == "markdebug" then
		if ns.MarkDebug then ns.MarkDebug() end
	elseif msg == "microdebug" then
		-- where the micro menu buttons are and why they might not show: each frame, its parent
		-- chain up to UIParent, shown / visible and alpha
		local P = "|cff66ccffZyde_Forever|r: "
		print(P .. "micro menu: hideMicroMenu " .. tostring(F("hideMicroMenu")) .. ", hideBars " .. tostring(F("hideBars")))
		-- what moved it into the hidden holder this session (the code path that did it)
		for _, t in ipairs(ns.microTrace or {}) do print(P .. t) end
		if not ns.microTrace then print(P .. "nothing moved the micro menu into the holder this session") end
		print(P .. ("screen: %dx%d"):format(UIParent:GetWidth(), UIParent:GetHeight()))
		local names = { "MicroMenuContainer", "MicroMenu", "BagsBar", "MicroButtonAndBagsBar", "MainMenuBarArtFrame", "MainMenuBar",
			"MainActionBar", "CharacterMicroButton", "SpellbookMicroButton", "MainMenuMicroButton", "QuestLogMicroButton" }
		for _, n in ipairs(names) do
			local f = _G[n]
			if not f then
				print(P .. n .. ": (none)")
			else
				local chain, p, guard = {}, f.GetParent and f:GetParent(), 0
				while p and guard < 6 do
					chain[#chain + 1] = (p.GetName and p:GetName()) or "?"
					p = p.GetParent and p:GetParent()
					guard = guard + 1
				end
				local ok, alpha = pcall(f.GetEffectiveAlpha or f.GetAlpha, f)
				-- where it is on screen (left, bottom, width, height) and its layer
				local l, b, w, h
				if f.GetRect then l, b, w, h = f:GetRect() end
				local where = l and ("at %d,%d size %dx%d"):format(l, b, w, h) or "no position"
				local strata = f.GetFrameStrata and f:GetFrameStrata() or "?"
				print(P .. ("%s: shown %s, visible %s, alpha %.2f, %s, layer %s, parents %s"):format(n,
					tostring(f.IsShown and f:IsShown()), tostring(f.IsVisible and f:IsVisible()),
					ok and alpha or -1, where, strata, table.concat(chain, " < ")))
			end
		end
	elseif msg == "bossdebug" then
		if ns.BossDebug then ns.BossDebug() end
	elseif msg == "auradebug" then
		ns.AuraDebug()
	elseif msg == "petdebug" then
		if ns.PetCare then ns.PetCare.Debug()
		else print("|cff66ccffZyde_Forever|r: pet care isn't loaded - restart the game fully (a /reload doesn't load new files)") end
	elseif msg == "resetquests" and ns.QuestTracker then
		ns.QuestTracker.ResetPosition()
	elseif msg == "resetreminders" then
		ns.ResetReminderPosition()
	elseif msg == "resetmobs" and ns.QuestMobs then
		ns.QuestMobs.ResetPosition()
	elseif msg == "ammovendor" and ns.Ammo then
		ns.Ammo.WaypointToVendor()
	elseif msg:match("^ammowarn") and ns.Ammo then
		ns.Ammo.SetWarn(tonumber(msg:match("^ammowarn%s+(%d+)")))
	elseif msg == "resetxp" then
		if ZydeForeverDB then ZydeForeverDB.xpPos = nil end
		ns.PlaceXP()
		print("|cff66ccffZyde_Forever|r: XP display moved back to the top of the screen")
	else
		if msg ~= "help" then
			print("|cff66ccffZyde_Forever|r: unknown command \"" .. msg .. "\"")
		end
		print("|cff66ccffZyde_Forever|r commands:")
		for _, c in ipairs({
			{ "", "(no command) open the options window: turn features on or off" },
			{ "help", "show this list" },
			{ "unlock", "unlock the player, target, party and raid frames so you can drag them" },
			{ "lock", "lock those frames in place (also happens when combat starts)" },
			{ "resetframes", "put the unit frames back in their default spots" },
			{ "resetxp", "move the XP % readout back to the top of the screen" },
			{ "resetquests", "move the quest tracker back to its default spot" },
			{ "resetmobs", "move the quest mob count back to its default spot" },
			{ "resetreminders", "move the reminder icons back beside your character (Shift-drag one to move them)" },
			{ "errors", "show the last Lua errors (from any addon), even with error pop-ups turned off" },
			{ "petdebug", "hunters: show what the game reports about your pet's mood, buffs and food" },
			{ "rangedebug", "hunters and warriors: show what the game says about your target's range" },
			{ "sealdebug", "paladins: why the Seal of Righteousness tile is or isn't showing" },
			{ "evisdebug", "rogues: the damage numbers behind the Eviscerate tile for your target" },
			{ "mapnotes", "how many map markers you have (alt-click the map to add one); /zyde mapnotes clear empties the open map" },
			{ "auradebug", "list your target's debuffs as the game reports them (for the Sunder and Thunder Clap tiles)" },
			{ "bossdebug", "target a mob: what the game tells addons about it (for the boss nameplates)" },
			{ "mobsdebug", "list nearby nameplates and why each is or isn't counted as a quest mob" },
			{ "test", "preview the Battle Shout, Overpower and quest item icons" },
			{ "questalert", "turn the quest item nearby alert on or off" },
			{ "questicons", "turn the icons over nearby objects on or off" },
			{ "scrap", "turn the full-bags \"scrap first\" list on or off" },
			{ "scraptest", "preview the scrap first list now, even with bags not full" },
			{ "scrapreset", "let items you chose to keep be suggested again (scrap and vendor lists)" },
			{ "vendor", "turn the vendor / auction / keep advice in item tooltips and at merchants on or off" },
			{ "ammovendor","hunters: waypoint to the nearest arrow or bullet vendor (or click the Arrows line)" },
			{ "ammowarn <number>", "hunters: warn when leaving town with fewer arrows or bullets than this (default 600, 0 = off)" },
			{ "questrange <yards>", "how far away quest objects are spotted (default 30)" },
			{ "questheight <pixels>", "the tallest the quest tracker gets before it scrolls (0 = down to the bottom of the screen)" },
			{ "quest <id>", "whether that quest is flagged complete (C_QuestLog.IsQuestFlaggedCompleted), and its name from Questie" },
			{ "questdebug", "stand facing a quest object and run this to see why it is or isn't detected" },
		}) do
			print(("  |cffffd200/zyde %s|r - %s"):format(c[1], c[2]))
		end
		print("  Keybinds (Fishing, nearest quest mob, feed pet, call or revive pet, target markers (hold), world marker squares): Options > Keybindings > AddOns > Zyde Forever")
	end
end
