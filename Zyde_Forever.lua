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
-- 7) "Target Zygor Step NPC" keybind (Keybindings > AddOns > Zyde Forever).
-- 8) Minimap tracking (e.g. Find Minerals) comes back on after you die.
-- 9) Icons over nearby objects, and an alert when one is a quest item.
-- 10) Drop chance under Questie's nameplate loot bag (QuestieDrops.lua).
-- 11) Bags full: the 3 cheapest stacks marked 1-2-3 (ScrapList.lua).
-- 12) Vendor / auction / keep advice per bag item, sell panel at merchants (VendorList.lua).
-- 13) Group finder helper: groups with room for you first, whisper the leader (LFGHelper.lua).
--
-- /zyde test     - toggle preview of both icons (to see where they sit)
-- /zyde resetxp  - put the XP readout back at its default spot

local ADDON, ns = ...

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local ICON_SIZE   = 44   -- pixels
local OFFSET_X    = 130  -- right of screen centre (your character)
local OFFSET_Y    = 0    -- first icon's height relative to screen centre
local SPACING     = 6    -- gap between stacked icons
local POLL        = 0.1  -- seconds between checks

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

---------------------------------------------------------------------------
-- Features: each can be turned on or off in the /zyde window, saved in
-- ZydeForeverDB.features. A feature that needs another addon (Questie,
-- AHledger, Zygor) is off when that addon isn't loaded.
---------------------------------------------------------------------------
local FEATURES = {
	{ key = "reminders", short = "icons beside you", label = "Reminder icons", desc = "Icons to the right of your character (Shift-drag one to move them). Warriors: Battle Shout missing or running out, Overpower / Execute / Revenge / Victory Rush ready, Thunder Clap missing on your target, wrong stance, Sunder stacks when tanking. Hunters: no Aspect, Cheetah or Pack on in combat, Hunter's Mark missing (solo), target too far or too close to shoot, Mongoose Bite ready, Mend Pet. Shamans: weapon imbue missing or running out, Lightning Shield missing or low, Earth Shock to interrupt, a totem out of range, no Ankh. Everyone: Well-Rested low, gear needs repair, low on food or water" },
	{ key = "ammo", short = "count, refill, warning", label = "Hunter ammo", desc = "Arrows or bullets left and how long they last (in the XP readout), a warning when you leave town low, and a Fill quiver button at ammo vendors (hunters)" },
	{ key = "petCare", short = "feed, call, Growl", label = "Hunter pet care", desc = "Keys to feed your pet the right food and to call or revive it, with reminders when it's hungry or missing, and a Growl autocast reminder: off in a group, on when solo (hunters)" },
	{ key = "markerWheel", short = "hold key, click marker", label = "Marker wheels", desc = "Hold a key for a wheel of target markers (skull, cross, moon...) or world markers, and click one to place it" },
	{ key = "hideBars", short = "cleaner action bars", label = "Hide Blizzard bar art", desc = "Hides the action bar art, bag bar and micro menu", reload = true },
	{ key = "xp", short = "compact XP display", label = "XP readout", desc = "Small draggable XP % with rested XP, time to level and tooltip (replaces the XP bar)", reload = true },
	{ key = "unitFrames", short = "flat health boxes", label = "Unit frames", desc = "Flat player, target, party and raid frames with buffs and debuffs, mana / rage / energy on party frames. Shift-drag a frame to move it", reload = true },
	{ key = "targetTarget", short = "small frame by target", label = "Target of target", desc = "A small frame beside the target frame showing who your target is targeting (with the Zyde unit frames on). Shift-drag it to move it" },
	{ key = "unitAuras", short = "icons on your frames", label = "Unit frame buffs / debuffs", desc = "Buff and debuff icons with time left on the Zyde unit frames: the target's debuffs (yours first) and buffs, your debuffs and buffs, and your pet's" },
	{ key = "barTidy", short = "short keys, no empty slots", label = "Tidy action bars", desc = "Short keybind labels on action buttons (a-1 becomes A1, Mouse Button 4 becomes M4) and empty slots hidden - they show again while you drag a spell or item" },
	{ key = "gear", short = "borders, item levels", label = "Character screen gear", desc = "Rarity borders and item levels; a green arrow when your bags hold an upgrade for a slot (scored by GearAdvisor if loaded), empty slots quiet gray unless your bags can fill them, and your average item level in the header", reload = true },
	{ key = "fishing", short = "one-key fishing", label = "One Button Fishing", desc = "Same key casts and reels in (set the key in Keybindings)" },
	{ key = "flight", short = "skip flight chat", label = "Flight master shortcut", desc = "Flight masters open the map directly (hold Shift to talk)" },
	{ key = "tracking", short = "re-enable after death", label = "Keep tracking after death", desc = "Turns Find Minerals, Find Herbs... back on after you die" },
	{ key = "questTracker", short = "ready first, nearest first", label = "Quest tracker", desc = "Replaces the game's quest tracker: quests ready to turn in at the top, then this zone's quests nearest first, other zones folded away; finished objective lines hidden", reload = true },
	{ key = "questAlert", short = "glow on quest objects", label = "Quest object alert", desc = "Glow, ! and ping on nearby quest objects you pick up (not the loot of mobs you kill for a quest)" },
	{ key = "questIcons", short = "icons over nodes", label = "Icons over nearby objects", desc = "The game's interact icons over herbs, ore and chests" },
	{ key = "guildRoster", short = "class colors, levels, zones", label = "Guild member list", desc = "In the Guild & Communities window: online members' names in class colors, each member's level at the right (colored by how near your level), and their zone when you hover them" },
	{ key = "lfg", short = "groups that fit you", label = "Group finder helper", desc = "Beside Looking For Group: groups with room for your role first, one-click whisper to the leader" },
	{ key = "scrap", short ="what to delete", label = "Scrap list (bags full)", desc = "The 3 cheapest items to throw away when your bags are full", conflict = "LootTriage" },
	{ key = "vendor", short = "sell or auction tips", label = "Vendor / auction advice", desc = "Vendor it / Auction it / Keep in tooltips, merchant and AH panels", needs = "AHledger" },
	{ key = "questieDrops", short = "drop % on nameplates", label = "Questie drop chances", desc = "Drop % and your odds under Questie's nameplate bag", needs = "Questie" },
	{ key = "questMobs", short = "glow, count, target key", label = "Quest mobs nearby", desc = "Gold edge on quest mobs' nameplates, a count of them near you, and a key to target one", needs = "Questie" },
	{ key = "zygor", short = "target step NPC", label = "Zygor target keybind", desc = "One key targets the current Zygor step's enemy or NPC", needs = "ZygorGuidesViewerForever" },
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
	{ name = "AHledger", title = "AHledger", used = "Needed for vendor / auction advice. Adds auction prices to the scrap list." },
	{ name = "ZygorGuidesViewerForever", title = "Zygor Guides", used = "Needed for the Zygor target keybind." },
	{ name = "NodeSightSparkles", title = "NodeSight Sparkles", used = "Optional: sparkles on quest objects and nodes." },
	{ name = "LootTriage", title = "LootTriage", used = "Optional: when on, it replaces the Zyde scrap list." },
}

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
		f:EnableMouse(on)
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
local function layout(states)
	local n = 0
	for _, icon in ipairs(icons) do
		local f = icon.frame
		if states[icon.key] then
			if f.zydeSlot ~= n or not f:IsShown() then
				f.zydeSlot = n
				f:ClearAllPoints()
				f:SetPoint("TOP", anchor, "TOP", 0, -n * (ICON_SIZE + SPACING))
				f:Show()
			end
			n = n + 1
		elseif f:IsShown() then
			f:Hide()
		end
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
	elseif not isWarrior or UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then
		states.shout, states.overpower = false, false
	else
		-- Always check (keeps the remembered expiry fresh), but only show in combat.
		local missing = shoutMissing()
		-- Running out (under 10 seconds left): show it blinking so you can refresh it in time.
		local left = shoutExpires - GetTime()
		local low = not missing and shoutExpires ~= math.huge and left > 0 and left < 10
		states.shout = F("shout") and (missing or low) and UnitAffectingCombat("player") or false
		icons[1].frame:SetAlpha(low and (0.35 + 0.65 * math.abs(math.sin(GetTime() * 4))) or 1)
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
	local hidden = false
	for i = 1, 40 do
		local a = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex and safe(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
		if not a then break end
		local id, name = a.spellId, a.name
		if not isSecret(id) and isAspect[id] then return true end
		if type(name) == "string" and not isSecret(name) and name:find("^Aspect of the ") then return true end
		if isSecret(id) and isSecret(name) then hidden = true end
	end
	if hidden then return nil end
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
-- On this client, an object you can interact with gets its own nameplate
-- (the same thing NodeSight Sparkles hangs its sparkles on). We scan those
-- object plates and check each against your quests:
--   1) Questie's quest data (object ID -> unfinished objective)
--   2) objects that gave you a quest item before (learned from loot)
--   3) name matching your unfinished objectives, plurals included
-- A match puts a pulsing quest icon with the object's name in the reminder
-- column, plus a ping.                                   /zyde questalert
-- Settings: if NodeSight Sparkles is loaded it manages the interact
-- settings and we leave them alone; otherwise we set them ourselves.
--                                                         /zyde questicons
---------------------------------------------------------------------------
local function questIconsOn() return F("questIcons") end
local function questAlertOn() return F("questAlert") end

local function addonLoaded(name)
	local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	return f and safe(f, name) and true or false
end

local function nodeSightManages()
	return addonLoaded("NodeSightSparkles") or addonLoaded("NodeSight")
end

-- The gamepad UI sets softTargetInteract itself on every target change.
local function gamepadUI()
	local s = C_InputInterfaceStyle and C_InputInterfaceStyle.GetCurrentStyle and safe(C_InputInterfaceStyle.GetCurrentStyle)
	return Enum and Enum.InputDeviceInterfaceType and s == Enum.InputDeviceInterfaceType.Gamepad or false
end

-- /zyde questrange <yards>: how far away objects are picked up (game default
-- 10, NodeSight and Zyde use 30). Applied after NodeSight sets its own 30.
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
	C_Timer.After(1, applyQuestRange) -- after NodeSight's own setup
	if nodeSightManages() or InCombatLockdown() then return end
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

-- Object plates in range: list of { unit, guid, name, picked, reason }.
local verdicts = {} -- guid -> reason or false (cleared when quests change)
local function scanObjects()
	local found = {}
	for _, unit in ipairs(ns.Plates.units()) do -- shared list (Plates.lua)
		local rawGuid = safe(UnitGUID, unit)
		if rawGuid ~= nil and isGameObject(unit) then
			local guid = plainStr(rawGuid)
			local name = plainStr(safe(UnitName, unit))
			local reason
			if guid and verdicts[guid] ~= nil then
				reason = verdicts[guid] or nil
			else
				reason = questReason(guid, name)
				if guid then verdicts[guid] = reason or false end
			end
			local picked = safe(UnitIsUnit, unit, "softinteract")
			found[#found + 1] = { unit = unit, guid = guid, name = name, reason = reason,
				picked = not isSecret(picked) and picked == true }
		end
	end
	return found
end

-- Marker drawn on a quest object's nameplate (the plate sits just above the
-- object): a pulsing gold glow on the object and a bobbing quest "!" over it.
-- Parented to the plate itself, so NodeSight hiding the plate's own art
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
			if plate then wanted[plate] = true end
		end
	end
	for plate in pairs(wanted) do
		local m = getMarker(plate)
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
		.. ", NodeSight " .. (nodeSightManages() and "manages settings" or "not loaded") .. ", gamepad UI " .. tostring(gamepadUI()))
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
C_Timer.NewTicker(0.5, checkQuestObject) -- backup for plates that change without an event
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

local hideBarArt -- forward: the art, bag bar and micro menu part

local function hideBlizzardBars()
	-- Experience bar: replaced by the XP readout, so only hidden with it on.
	if F("xp") then
		stash(MainStatusTrackingBarContainer)
		stash(SecondaryStatusTrackingBarContainer)
		if not MainStatusTrackingBarContainer then stash(StatusTrackingBarManager) end
		stash(MainMenuExpBar)
		stash(ExhaustionTick)
	end
	if F("hideBars") then hideBarArt() end
end

hideBarArt = function()
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

	-- Bag bar.
	stash(BagsBar)
	stash(MainMenuBarBackpackButton)
	for i = 0, 3 do stash(_G["CharacterBag" .. i .. "Slot"]) end
	stash(CharacterReagentBag0Slot)
	stash(KeyRingButton)

	-- Micro menu.
	stash(MicroMenuContainer)
	if not MicroMenuContainer then
		stash(MicroMenu)
		stash(MicroButtonAndBagsBar)
		if MICRO_BUTTONS then
			for _, name in ipairs(MICRO_BUTTONS) do stash(_G[name]) end
		end
	end
end

---------------------------------------------------------------------------
-- Experience % (replaces the XP bar). Drag it with the left mouse button.
---------------------------------------------------------------------------
local XP_DEFAULT = { point = "TOP", x = 0, y = -40 }

local xp = CreateFrame("Frame", "ZydeForeverXP", UIParent)
xp:SetSize(70, 18)
xp:SetFrameStrata("MEDIUM")
xp:SetClampedToScreen(true)
xp:SetMovable(true)
xp:EnableMouse(true)
xp:RegisterForDrag("LeftButton")

xp.bg = xp:CreateTexture(nil, "BACKGROUND")
xp.bg:SetAllPoints()
xp.bg:SetColorTexture(0.12, 0.12, 0.12, 0.85) -- dark gray

xp.text = xp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
xp.text:SetPoint("TOP", 0, -3)
xp.text:SetTextColor(0.69, 0.35, 1.0) -- purple

xp.rested = xp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
xp.rested:SetPoint("TOP", xp.text, "BOTTOM", 0, -1)
xp.rested:SetTextColor(0.55, 0.8, 1.0) -- light blue

xp.ttl = xp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
xp.ttl:SetTextColor(0.85, 0.85, 0.85)

---------------------------------------------------------------------------
-- XP rate: gains over the last 2 hours of *play time*, saved per character
-- so it carries on after logging off (offline time doesn't count).
-- ZydeForeverDB.xpLog["Name-Realm"] = { clock, start, gains = {{c, xp}} }
---------------------------------------------------------------------------
local RATE_WINDOW = 2 * 60 * 60
local MIN_WINDOW  = 60 -- need at least a minute of data for a TTL
local sessionStart, lastXP, lastMax

local function xpLog()
	ZydeForeverDB = ZydeForeverDB or {}
	ZydeForeverDB.xpLog = ZydeForeverDB.xpLog or {}
	local key = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
	local log = ZydeForeverDB.xpLog[key]
	if not log then
		log = { clock = 0, start = 0, gains = {} }
		ZydeForeverDB.xpLog[key] = log
	end
	return log
end

-- Seconds played with the addon on this character, across sessions.
local function playClock()
	local log = xpLog()
	return log.clock + (sessionStart and (GetTime() - sessionStart) or 0)
end

local function pruneGains(log, now)
	local keep = {}
	for _, g in ipairs(log.gains) do
		if now - g[1] <= RATE_WINDOW then keep[#keep + 1] = g end
	end
	log.gains = keep
end

local function recordXP()
	local cur, max = UnitXP("player"), UnitXPMax("player")
	if isSecret(cur) or isSecret(max) or not max or max <= 0 then return end
	if lastXP then
		local gained = cur - lastXP
		if gained < 0 then gained = (lastMax - lastXP) + cur end -- levelled up
		if gained > 0 then
			local log, now = xpLog(), playClock()
			log.gains[#log.gains + 1] = { now, gained }
			pruneGains(log, now)
		end
	end
	lastXP, lastMax = cur, max
end

-- XP per second over the last 2 hours of play (or less if newer data).
local function xpRate()
	local log, now = xpLog(), playClock()
	local window = math.min(RATE_WINDOW, now - log.start)
	if window < MIN_WINDOW then return nil end
	local sum = 0
	for _, g in ipairs(log.gains) do
		if now - g[1] <= RATE_WINDOW then sum = sum + g[2] end
	end
	if sum <= 0 then return nil end
	return sum / window
end

local function formatTime(sec)
	if sec >= 100 * 3600 then return ">99h" end
	local h, m = math.floor(sec / 3600), math.floor(sec % 3600 / 60)
	if h > 0 then return ("%dh %dm"):format(h, m) end
	return ("%dm"):format(math.max(m, 1))
end

local xpClock = CreateFrame("Frame")
xpClock:RegisterEvent("PLAYER_LOGIN")
xpClock:RegisterEvent("PLAYER_LOGOUT")
xpClock:SetScript("OnEvent", function(_, event)
	local log = xpLog()
	if event == "PLAYER_LOGIN" then
		sessionStart = GetTime()
		lastXP, lastMax = UnitXP("player"), UnitXPMax("player")
		if isSecret(lastXP) or isSecret(lastMax) then lastXP, lastMax = nil, nil end
	else -- logout or /reload: bank this session's play time
		log.clock = playClock()
		sessionStart = GetTime()
		pruneGains(log, log.clock)
	end
end)

local function placeXP()
	local p = (ZydeForeverDB and ZydeForeverDB.xpPos) or XP_DEFAULT
	xp:ClearAllPoints()
	xp:SetPoint(p.point, UIParent, p.point, p.x, p.y)
end

xp:SetScript("OnDragStart", function(self) self:StartMoving() end)
xp:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local point, _, _, x, y = self:GetPoint()
	ZydeForeverDB = ZydeForeverDB or {}
	ZydeForeverDB.xpPos = { point = point, x = x, y = y }
end)

xp.ammo = xp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

-- Still levelling (XP not turned off, not max level)?
local function xpShown()
	local level = UnitLevel("player")
	local maxLevel = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion())
		or MAX_PLAYER_LEVEL or 60
	local cur, max = UnitXP("player"), UnitXPMax("player")
	if isSecret(cur) or isSecret(max) or isSecret(level) then return nil end
	if (IsXPUserDisabled and IsXPUserDisabled()) or level >= maxLevel or not max or max <= 0 then
		return false
	end
	return true, cur, max
end

local function updateXP()
	if not F("xp") then xp:Hide() return end
	local levelling, cur, max = xpShown()
	if levelling == nil then return end -- hidden values: keep what's shown
	-- Hunter ammo line (Ammo.lua), also shown at max level.
	local ammoText, ar, ag, ab
	if ns.Ammo then ammoText, ar, ag, ab = ns.Ammo.Line() end
	if not levelling and not ammoText then xp:Hide() return end

	local lines, width, below = 0, 0, nil
	if levelling then
		xp.text:SetFormattedText("XP %.1f%%", cur / max * 100)
		xp.text:Show()
		width, lines, below = xp.text:GetStringWidth(), 1, xp.text

		local rested = GetXPExhaustion and GetXPExhaustion()
		if rested and not isSecret(rested) and rested > 0 then
			xp.rested:SetFormattedText("Rested %.1f%%", rested / max * 100)
			xp.rested:Show()
			width = math.max(width, xp.rested:GetStringWidth())
			lines, below = lines + 1, xp.rested
		else
			xp.rested:Hide()
		end

		-- Time to level, from the last 2 hours of play.
		local rate = xpRate()
		xp.ttl:ClearAllPoints()
		xp.ttl:SetPoint("TOP", below, "BOTTOM", 0, -1)
		xp.ttl:SetText("TTL: " .. (rate and formatTime((max - cur) / rate) or "--"))
		xp.ttl:Show()
		width = math.max(width, xp.ttl:GetStringWidth())
		lines, below = lines + 1, xp.ttl
	else
		xp.text:Hide()
		xp.rested:Hide()
		xp.ttl:Hide()
	end

	if ammoText then
		xp.ammo:ClearAllPoints()
		if below then xp.ammo:SetPoint("TOP", below, "BOTTOM", 0, -1) else xp.ammo:SetPoint("TOP", 0, -3) end
		xp.ammo:SetText(ammoText)
		xp.ammo:SetTextColor(ar, ag, ab)
		xp.ammo:Show()
		width = math.max(width, xp.ammo:GetStringWidth())
		lines = lines + 1
	else
		xp.ammo:Hide()
	end

	xp:SetHeight(6 + lines * 12)
	xp:SetWidth(math.max(60, width + 14))
	xp:Show()
end
ns.UpdateXP = updateXP
ns.formatTime = formatTime
C_Timer.NewTicker(30, updateXP) -- TTL drifts as the 2-hour window moves
ns.OnFeatureChanged(function(key) if key == "xp" then updateXP() end end)

-- Right-click the XP readout: ask, then start the time-to-level data fresh.
StaticPopupDialogs["ZYDEFOREVER_RESET_TTL"] = {
	text = "Reset the time to level counter?\nYour XP rate will start over from now.",
	button1 = YES,
	button2 = NO,
	OnAccept = function()
		local log = xpLog()
		log.gains = {}
		log.start = playClock()
		updateXP()
		print("|cff66ccffZyde_Forever|r: time to level counter reset")
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}
xp:SetScript("OnMouseUp", function(_, button)
	if button == "RightButton" and xpShown() then
		GameTooltip:Hide()
		StaticPopup_Show("ZYDEFOREVER_RESET_TTL")
	end
end)

-- Mouseover: XP still needed, and the XP from quests ready to turn in.
local function num(n)
	return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

-- XP reward of quest log entry i (quest questID). Classic clients read the
-- selected log entry; modern ones take the quest ID.
local function questXP(i, questID)
	local v
	if SelectQuestLogEntry and GetQuestLogSelection then
		local old = GetQuestLogSelection()
		SelectQuestLogEntry(i)
		v = safe(GetQuestLogRewardXP)
		SelectQuestLogEntry(old or 0)
	elseif questID then
		v = safe(GetQuestLogRewardXP, questID)
	end
	if type(v) == "number" and not isSecret(v) then return v end
	return 0
end

local function isReady(questID, completeFlag)
	if completeFlag == 1 or completeFlag == true then return true end
	if questID and C_QuestLog then
		if C_QuestLog.ReadyForTurnIn and safe(C_QuestLog.ReadyForTurnIn, questID) == true then return true end
		if C_QuestLog.IsComplete and safe(C_QuestLog.IsComplete, questID) == true then return true end
	end
	return false
end

-- Returns number of quests ready to turn in and their total XP.
local function readyQuestXP()
	local count, total = 0, 0
	if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
		for i = 1, (safe(C_QuestLog.GetNumQuestLogEntries) or 0) do
			local info = safe(C_QuestLog.GetInfo, i)
			if info and not info.isHeader and info.questID and isReady(info.questID) then
				count, total = count + 1, total + questXP(i, info.questID)
			end
		end
	elseif GetNumQuestLogEntries and GetQuestLogTitle then
		for i = 1, (safe(GetNumQuestLogEntries) or 0) do
			local _, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
			if not isHeader and isReady(questID, isComplete) then
				count, total = count + 1, total + questXP(i, questID)
			end
		end
	end
	return count, total
end

local function xpTooltip(self)
	local cur, max = UnitXP("player"), UnitXPMax("player")
	if isSecret(cur) or isSecret(max) or not max or max <= 0 then return end
	local need = max - cur
	-- "1,234 (12.6%)": raw value plus its share of this level's XP
	local function val(n) return ("%s (%.1f%%)"):format(num(n), n / max * 100) end
	GameTooltip:AddLine("Experience", 0.69, 0.35, 1.0)
	GameTooltip:AddDoubleLine("Current", ("%s / %s (%.1f%%)"):format(num(cur), num(max), cur / max * 100), 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine("Needed to level", val(need), 1, 1, 1, 1, 0.82, 0)

	local rested = GetXPExhaustion and GetXPExhaustion()
	if rested and not isSecret(rested) and rested > 0 then
		GameTooltip:AddDoubleLine("Rested", val(rested), 1, 1, 1, 0.55, 0.8, 1.0)
	end
	local rate = xpRate()
	GameTooltip:AddDoubleLine("XP per hour (last 2h)", rate and val(math.floor(rate * 3600)) or "--", 1, 1, 1, 0.85, 0.85, 0.85)
	GameTooltip:AddDoubleLine("Time to level", rate and formatTime(need / rate) or "--", 1, 1, 1, 0.85, 0.85, 0.85)

	local count, total = readyQuestXP()
	GameTooltip:AddLine(" ")
	if count == 0 then
		GameTooltip:AddLine("No quests ready to turn in", 0.6, 0.6, 0.6)
	else
		GameTooltip:AddDoubleLine(("Quests ready (%d)"):format(count), val(total), 1, 1, 1, 0.4, 1, 0.4)
		if total >= need then
			GameTooltip:AddLine("Turning these in will level you up!", 0.4, 1, 0.4)
		elseif total > 0 then
			GameTooltip:AddDoubleLine("Still needed after", val(need - total), 0.8, 0.8, 0.8, 1, 0.82, 0)
		end
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Right-click to reset time to level", 0.6, 0.6, 0.6)
end

xp:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
	if xpShown() then xpTooltip(self) end
	if ns.Ammo and ns.Ammo.Line() then
		if GameTooltip:NumLines() > 0 then GameTooltip:AddLine(" ") end
		ns.Ammo.Tooltip(GameTooltip)
	end
	GameTooltip:Show()
end)
xp:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
-- Zygor: one keybind that targets the current step's NPC or enemy.
-- Reads the names from Zygor's action-bar buttons (talk to / click / kill)
-- and builds one macro: talk-to NPCs are tried first, then kill targets,
-- so a nearby enemy to kill always wins over the person to talk to.
-- Zygor's own raid-marker lines are dropped; we add one star marker that
-- only fires when a live target was found (avoids "You can't do that").
-- Updates out of combat only (game rule); in combat the last one stays.
---------------------------------------------------------------------------
_G["BINDING_NAME_CLICK ZydeForeverZygorTarget:LeftButton"] = "Target Zygor Step NPC"

local zygorButton = CreateFrame("Button", "ZydeForeverZygorTarget", UIParent, "SecureActionButtonTemplate")
zygorButton:SetSize(1, 1)
zygorButton:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
zygorButton:SetAlpha(0)
zygorButton:SetAttribute("type", "macro")
zygorButton:SetAttribute("macrotext", "")

-- Returns kill names, talk names (each in Zygor's button order).
local function zygorTargets()
	local candidates, seen = {}, {}
	local function add(b)
		if b and not seen[b] then seen[b] = true; candidates[#candidates + 1] = b end
	end
	for i = 1, 5 do add(_G["ZygorAB" .. i]) end
	local zgv = rawget(_G, "ZGV") or rawget(_G, "ZygorGuidesViewer")
	if zgv and zgv.ActionBar and type(zgv.ActionBar.Buttons) == "table" then
		for _, b in ipairs(zgv.ActionBar.Buttons) do add(b) end
	end

	local kills, talks, used = {}, {}, {}
	for _, b in ipairs(candidates) do
		if b.IsShown and b:IsShown() and b.GetAttribute then
			local text = b:GetAttribute("macrotext1")
			local name = type(text) == "string" and text:match("/target ([^\n]+)")
			if name then
				name = name:gsub("%s+$", "")
				if not used[name] then
					used[name] = true
					if text:find("/cleartarget [dead]", 1, true) then
						kills[#kills + 1] = name
					else
						talks[#talks + 1] = name
					end
				end
			end
		end
	end
	return kills, talks
end

local function zygorMacro()
	local kills, talks = zygorTargets()
	if #kills == 0 and #talks == 0 then return "" end
	local lines = { "/cleartarget" }
	-- Each /target only takes effect if that NPC is nearby, so the last
	-- one found wins: talk-to first, kill targets after.
	for _, name in ipairs(talks) do lines[#lines + 1] = "/target " .. name end
	for i = #kills, 1, -1 do
		lines[#lines + 1] = "/target " .. kills[i]
		lines[#lines + 1] = "/cleartarget [dead]"
	end
	-- Star marker, only when something was actually targeted (no error spam).
	local tail = "/tm [exists,nodead] 1"
	-- The game runs at most 255 characters and cuts the rest mid-word, so
	-- drop the first (least important) target lines until it fits.
	while #lines > 1 and #table.concat(lines, "\n") + 1 + #tail > 255 do
		table.remove(lines, 2)
	end
	lines[#lines + 1] = tail
	return table.concat(lines, "\n")
end

local lastZygorMacro
local function refreshZygorTarget()
	if InCombatLockdown() then return end
	local down = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
	zygorButton:RegisterForClicks(down and "AnyDown" or "AnyUp")
	local text = F("zygor") and zygorMacro() or ""
	if text ~= lastZygorMacro then
		zygorButton:SetAttribute("macrotext", text)
		lastZygorMacro = text
	end
end

if C_Timer and C_Timer.NewTicker then
	C_Timer.NewTicker(0.5, refreshZygorTarget)
end

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
-- Character screen: rarity-colored borders on equipped gear.
-- Crisp 2px colored edge, a 1px dark outline outside it, and a soft inner
-- glow fading toward the icon centre. Replaces Blizzard's own quality border.
---------------------------------------------------------------------------
local GEAR_SLOTS = {
	"Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist",
	"Hands", "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1",
	"MainHand", "SecondaryHand", "Ranged", "Ammo",
}

local BORDER_PX = 2   -- colored edge thickness (screen pixels)
local GLOW_PX   = 6   -- inner glow depth
local GLOW_A    = 0.30

local function qualityColor(q)
	if C_Item and C_Item.GetItemQualityColor then
		local r, g, b = safe(C_Item.GetItemQualityColor, q)
		if r then return r, g, b end
	end
	if GetItemQualityColor then
		local r, g, b = safe(GetItemQualityColor, q)
		if r then return r, g, b end
	end
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

local function newEdges(f, layer, sub)
	local t = {}
	for i = 1, 4 do
		t[i] = f:CreateTexture(nil, layer, nil, sub)
		t[i]:SetColorTexture(1, 1, 1, 1)
	end
	return t
end

-- Four strips forming a box: inset > 0 is inside the frame, < 0 outside.
local function placeEdges(t, f, inset, thick)
	local top, bottom, left, right = t[1], t[2], t[3], t[4]
	top:ClearAllPoints()
	top:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset)
	top:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inset, -inset)
	top:SetHeight(thick)
	bottom:ClearAllPoints()
	bottom:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inset, inset)
	bottom:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
	bottom:SetHeight(thick)
	left:ClearAllPoints()
	left:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset - thick)
	left:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inset, inset + thick)
	left:SetWidth(thick)
	right:ClearAllPoints()
	right:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inset, -inset - thick)
	right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset + thick)
	right:SetWidth(thick)
end

local function setGlow(t, r, g, b)
	if not CreateColor then
		for _, tex in ipairs(t) do tex:SetColorTexture(r, g, b, GLOW_A * 0.5) end
		return
	end
	local solid, clear = CreateColor(r, g, b, GLOW_A), CreateColor(r, g, b, 0)
	-- SetGradient(orientation, minColor, maxColor): min = bottom/left.
	t[1]:SetGradient("VERTICAL", clear, solid)   -- top: strong at the edge
	t[2]:SetGradient("VERTICAL", solid, clear)   -- bottom
	t[3]:SetGradient("HORIZONTAL", solid, clear) -- left
	t[4]:SetGradient("HORIZONTAL", clear, solid) -- right
end

local function getBorder(button)
	if button.zydeBorder then return button.zydeBorder end
	local f = CreateFrame("Frame", nil, button)
	f:SetAllPoints(button)
	f:SetFrameLevel(button:GetFrameLevel() + 3)
	f:EnableMouse(false)

	-- Snap thickness to whole screen pixels so edges stay razor sharp.
	local px = 1
	if PixelUtil and PixelUtil.GetNearestPixelSize then
		px = PixelUtil.GetNearestPixelSize(1, button:GetEffectiveScale(), 1)
	end

	f.outline = newEdges(f, "OVERLAY", 1)
	placeEdges(f.outline, f, -px, px)
	for _, tex in ipairs(f.outline) do tex:SetColorTexture(0, 0, 0, 0.9) end

	f.edge = newEdges(f, "OVERLAY", 2)
	placeEdges(f.edge, f, 0, BORDER_PX * px)

	f.glow = newEdges(f, "OVERLAY", 0)
	placeEdges(f.glow, f, BORDER_PX * px, GLOW_PX * px)

	-- Item level, bottom-centre, small with a clean outline.
	f.ilvl = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	f.ilvl:SetPoint("BOTTOM", f, "BOTTOM", 0, 3)
	local font, size = f.ilvl:GetFont()
	if font then f.ilvl:SetFont(font, (size or 11), "OUTLINE") end
	f.ilvl:SetShadowOffset(0, 0)

	-- Upgrade flag: a "!" in the top-right corner (see gearFlag below).
	f.flag = f:CreateFontString(nil, "OVERLAY")
	f.flag:SetFont(STANDARD_TEXT_FONT, 16, "THICKOUTLINE")
	f.flag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
	f.flag:SetText("!")
	f.flag:Hide()

	-- Upgrade waiting in your bags: a green arrow in the top-left corner.
	f.arrow = f:CreateTexture(nil, "OVERLAY", nil, 3)
	f.arrow:SetSize(14, 14)
	f.arrow:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
	f.arrow:SetTexture("Interface\\Buttons\\UI-MicroStream-Green")
	f.arrow:Hide()

	-- Hide Blizzard's quality border on this slot so only ours shows.
	if button.IconBorder then fade(button.IconBorder) end

	-- Add the flag's reason and any bag upgrade to the slot's tooltip.
	button:HookScript("OnEnter", function()
		if not GameTooltip:IsOwned(button) then return end
		local added = false
		if f.flagText and f.flag:IsShown() then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(f.flagText, f.flagR, f.flagG, f.flagB, true)
			added = true
		end
		if f.upgradeText and f.arrow:IsShown() then
			if not added then GameTooltip:AddLine(" ") end
			GameTooltip:AddLine(f.upgradeText, 0.35, 1, 0.35, true)
			added = true
		end
		if added then GameTooltip:Show() end
	end)

	button.zydeBorder = f
	return f
end

-- Upgrade flags: gear well behind your level, and empty slots.
-- Typical gear for your level is about item level = your level + 3 (quest
-- greens). 6-9 behind that: orange "!" (getting old). 10+ behind: red "!".
local GEAR_EXPECT_OVER_LEVEL = 3
local GEAR_AGING, GEAR_WEAK = 6, 10
-- Slots worth filling (not shirt 4, tabard 19, ammo 0).
local FLAG_EMPTY = { [1] = true, [2] = true, [3] = true, [5] = true, [6] = true, [7] = true,
	[8] = true, [9] = true, [10] = true, [11] = true, [12] = true, [13] = true, [14] = true,
	[15] = true, [16] = true, [17] = true, [18] = true }

-- Returns r, g, b, reason for a flag, or nil.
local function gearFlag(slot, lvl, twoHanded)
	local level = UnitLevel("player")
	if not level or isSecret(level) then return nil end
	if not lvl then
		if not FLAG_EMPTY[slot] then return nil end
		if slot == 17 and twoHanded then return nil end -- off hand is empty for a 2-hander
		return 1, 0.2, 0.2, "Empty slot - anything you can put here is an upgrade."
	end
	local behind = level + GEAR_EXPECT_OVER_LEVEL - lvl
	if behind >= GEAR_WEAK then
		return 1, 0.2, 0.2, ("Upgrade this: about %d item levels behind typical gear for level %d."):format(behind, level)
	elseif behind >= GEAR_AGING then
		return 1, 0.6, 0.15, ("Getting old: about %d item levels behind typical gear for level %d."):format(behind, level)
	end
	return nil
end

local function mainHandIsTwoHanded()
	local link = GetInventoryItemLink("player", 16)
	if not link or isSecret(link) then return false end
	local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local equipLoc = select(9, getInfo(link))
	return equipLoc == "INVTYPE_2HWEAPON"
end

-- Shirt, tabard and ammo: item level means nothing there.
local NO_ILVL_SLOTS = { [0] = true, [4] = true, [19] = true }

local function slotItemLevel(slot)
	local lvl
	if C_Item and C_Item.GetCurrentItemLevel and ItemLocation and ItemLocation.CreateFromEquipmentSlot then
		local loc = safe(ItemLocation.CreateFromEquipmentSlot, ItemLocation, slot)
		if loc and safe(loc.IsValid, loc) then lvl = safe(C_Item.GetCurrentItemLevel, loc) end
	end
	if not lvl then
		local link = GetInventoryItemLink("player", slot)
		if link and not isSecret(link) then
			local getLevel = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
			lvl = safe(getLevel, link)
		end
	end
	if lvl and not isSecret(lvl) then return lvl end
	return nil
end

local function showFlag(f, fr, fg, fb, reason)
	if fr then
		f.flag:SetTextColor(fr, fg, fb)
		f.flag:Show()
		f.flagText, f.flagR, f.flagG, f.flagB = reason, fr, fg, fb
	else
		f.flag:Hide()
		f.flagText = nil
	end
end

---------------------------------------------------------------------------
-- Upgrades waiting in your bags, per character slot. Scored by GearAdvisor
-- when it's loaded (its "upgrade" verdict and % gain); otherwise any item you
-- can wear now with a higher item level than what's in the slot.
---------------------------------------------------------------------------
local EQUIP_SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
	INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
	INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
	INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
	INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
	INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
	INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
local bagUpgrades = {} -- slot -> { link, pct (GearAdvisor) or gain (item levels) }

-- Red text in the item's tooltip (level, armor type, class...) = can't wear it now.
local function wearableNow(bag, slot)
	local data = C_TooltipInfo and C_TooltipInfo.GetBagItem and safe(C_TooltipInfo.GetBagItem, bag, slot)
	for _, line in ipairs(data and data.lines or {}) do
		for _, side in ipairs({ { line.leftText, line.leftColor }, { line.rightText, line.rightColor } }) do
			local text, c = side[1], side[2]
			if c and type(text) == "string" and not isSecret(text) and c.r and c.r > 0.95 and c.g < 0.2 and c.b < 0.2 then
				return false
			end
		end
	end
	return true
end

local function scanBagUpgrades()
	wipe(bagUpgrades)
	local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local getLevel = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
	local GA = GearAdvisorAPI
	local function record(slot, link, pct, gain)
		local cur = bagUpgrades[slot]
		local score = pct or gain or 0
		if not cur or score > (cur.pct or cur.gain or 0) then bagUpgrades[slot] = { link = link, pct = pct, gain = gain } end
	end
	for _, info in ipairs(ns.Bags.items()) do -- shared bag list (Bags.lua)
		local bag, bslot = info.bag, info.slot
		local link = info and info.hyperlink
		local equipLoc = link and select(9, getInfo(link))
		local slots = equipLoc and EQUIP_SLOTS[equipLoc]
		if slots then
			if GA and GA.Compare then
				local r = GA.Compare(link)
				if r and r.kind == "upgrade" and r.slot then record(r.slot, link, r.pct) end
			elseif wearableNow(bag, bslot) then
				local lvl = safe(getLevel, link)
				if type(lvl) == "number" and not isSecret(lvl) then
					for _, s in ipairs(slots) do
						local cur = slotItemLevel(s) or 0
						if lvl > cur then record(s, link, nil, lvl - cur) end
					end
				end
			end
		end
	end
end

local function upgradeLine(u)
	if u.pct then return ("Upgrade in your bags: %s (%+.0f%%)"):format(u.link, u.pct) end
	if u.gain then return ("Upgrade in your bags: %s (+%d item levels)"):format(u.link, u.gain) end
	return "Upgrade in your bags: " .. u.link
end

local function updateSlotBorder(button)
	if not button or not button.GetID then return end
	local slot = button:GetID()
	if not slot then return end
	if not F("gear") then
		if button.zydeBorder then button.zydeBorder:Hide() end
		return -- Blizzard's own border comes back after a /reload
	end
	local q = GetInventoryItemQuality("player", slot)
	if isSecret(q) then return end
	local up = bagUpgrades[slot]
	if not q then
		-- Empty slot: quiet gray, unless your bags hold something for it -
		-- then a red "!" (you can fix this right now).
		if not FLAG_EMPTY[slot] or (slot == 17 and mainHandIsTwoHanded()) then
			if button.zydeBorder then button.zydeBorder:Hide() end
			return
		end
		local f = getBorder(button)
		f.ilvl:Hide()
		f.arrow:Hide()
		if up then
			for _, tex in ipairs(f.edge) do tex:SetColorTexture(1, 0.2, 0.2, 0.6) end
			setGlow(f.glow, 1, 0.2, 0.2)
			showFlag(f, 1, 0.2, 0.2, "Empty - you have something for this slot in your bags: " .. up.link)
		else
			for _, tex in ipairs(f.edge) do tex:SetColorTexture(0.35, 0.35, 0.38, 0.5) end
			for _, tex in ipairs(f.glow) do tex:SetColorTexture(0, 0, 0, 0) end
			showFlag(f, nil)
		end
		f:Show()
		return
	end
	local f = getBorder(button)
	local r, g, b = qualityColor(q)
	for _, tex in ipairs(f.edge) do tex:SetColorTexture(r, g, b, 1) end
	setGlow(f.glow, r, g, b)
	f.arrow:SetShown(up ~= nil)
	f.upgradeText = up and upgradeLine(up) or nil

	local lvl = (not NO_ILVL_SLOTS[slot]) and slotItemLevel(slot)
	if lvl and lvl > 1 then
		f.ilvl:SetText(lvl)
		f.ilvl:SetTextColor(r, g, b)
		f.ilvl:Show()
		showFlag(f, gearFlag(slot, lvl))
	else
		f.ilvl:Hide()
		showFlag(f, nil)
	end
	f:Show()
end

-- Average item level of what you wear, in the header: "Level 17 Hunter · item level 16.8".
local function averageItemLevel()
	if GetAverageItemLevel then
		local _, equipped = safe(GetAverageItemLevel)
		if type(equipped) == "number" and not isSecret(equipped) and equipped > 0 then return equipped end
	end
	-- Our own count: the 16 slots that matter (a two-hander counts for both hands).
	local total, count = 0, 0
	for _, s in ipairs({ 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }) do
		if s ~= 18 or UnitClass and select(2, UnitClass("player")) == "HUNTER" then
			local lvl = slotItemLevel(s)
			if s == 17 and not lvl and mainHandIsTwoHanded() then lvl = slotItemLevel(16) end
			total, count = total + (lvl or 0), count + 1
		end
	end
	return count > 0 and total / count or nil
end

local ILVL_SUFFIX = "  ·  item level "
local function updateLevelText()
	if not (F("gear") and CharacterLevelText) then return end
	local text = CharacterLevelText:GetText()
	if type(text) ~= "string" or isSecret(text) then return end
	-- Take off our old number (the game doesn't always redraw the line), add the new one.
	local cut = text:find(ILVL_SUFFIX, 1, true)
	if cut then text = text:sub(1, cut - 1) end
	local avg = averageItemLevel()
	if avg then CharacterLevelText:SetText(("%s%s%.1f"):format(text, ILVL_SUFFIX, avg)) end
end
if PaperDollFrame_SetLevel then hooksecurefunc("PaperDollFrame_SetLevel", updateLevelText) end

local function updateAllGearBorders()
	if F("gear") then pcall(scanBagUpgrades) end
	for _, name in ipairs(GEAR_SLOTS) do
		updateSlotBorder(_G["Character" .. name .. "Slot"])
	end
	updateLevelText()
	-- The game's average can lag a moment behind a gear change: look again.
	C_Timer.After(0.5, updateLevelText)
end

if PaperDollItemSlotButton_Update then
	hooksecurefunc("PaperDollItemSlotButton_Update", updateSlotBorder)
end
ns.OnFeatureChanged(function(key) if key == "gear" then updateAllGearBorders() end end)

local gearEvents = CreateFrame("Frame")
gearEvents:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
gearEvents:RegisterEvent("GET_ITEM_INFO_RECEIVED")
gearEvents:RegisterEvent("PLAYER_LEVEL_UP")
gearEvents:RegisterEvent("PLAYER_LOGIN")
gearEvents:RegisterEvent("BAG_UPDATE_DELAYED")
gearEvents:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" and CharacterFrame then
		CharacterFrame:HookScript("OnShow", updateAllGearBorders)
	end
	-- Item info and bag changes only matter while the character window is open.
	if (event == "GET_ITEM_INFO_RECEIVED" or event == "BAG_UPDATE_DELAYED")
		and not (CharacterFrame and CharacterFrame:IsShown()) then return end
	-- Item info arrives in bursts (one event per item): redraw once, a moment after.
	if event == "GET_ITEM_INFO_RECEIVED" then
		if gearEvents.pending then return end
		gearEvents.pending = true
		C_Timer.After(0.2, function() gearEvents.pending = nil updateAllGearBorders() end)
		return
	end
	updateAllGearBorders()
end)

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
ns.newEdges, ns.placeEdges = newEdges, placeEdges

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
	if event == "PLAYER_LOGIN" then placeXP() end
	if event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" or event == "UPDATE_EXHAUSTION"
		or event == "PLAYER_UPDATE_RESTING" then
		if event == "PLAYER_XP_UPDATE" then recordXP() end
		-- PLAYER_LEVEL_UP fires before UnitXPMax changes; check again shortly after.
		updateXP()
		if C_Timer then C_Timer.After(0.5, updateXP) end
		return
	end
	updateXP()
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
---------------------------------------------------------------------------
local options
local ROW = 24
local HEAD = 28      -- height of a category heading
local COL_W = 420    -- width of one column of features

-- The window's categories: two columns, each a list of { heading, feature keys }.
-- A feature missing here still shows, under "Other" at the end.
local CATEGORIES = {
	{
		{ "Interface", { "unitFrames", "unitAuras", "targetTarget", "xp", "reminders", "hideBars", "barTidy", "gear" } },
		{ "Hunter", { "ammo", "petCare" } },
		{ "Groups", { "lfg", "guildRoster", "markerWheel" } },
	},
	{
		{ "Questing & leveling", { "questTracker", "questFont", "questAlert", "questIcons", "questMobs", "questieDrops", "zygor" } },
		{ "Bags & vendors", { "scrap", "vendor" } },
		{ "Travel & gathering", { "flight", "tracking", "fishing" } },
	},
}

-- Short names for "needs ..." notes (Zygor's folder name is long).
local function addonTitle(name)
	for _, a in ipairs(ns.ADDONS) do
		if a.name == name then return a.title end
	end
	return name
end

local function buildOptions()
	-- Sliders that sit in the feature lists like a feature row (by key in CATEGORIES).
	local SLIDERS = {
		questFont = {
			label = "Quest tracker text size", min = 10, max = 20,
			desc = "How big the quest tracker's text is (13 is the normal size). The tracker grows with it.",
			get = function() return ns.QuestTracker and ns.QuestTracker.GetFontSize() or 13 end,
			set = function(v) if ns.QuestTracker then ns.QuestTracker.SetFontSize(v) end end,
			enabled = function() return F("questTracker") end,
		},
	}

	-- Anything not placed in a category goes under "Other" in the second column.
	local placed, other = {}, {}
	for _, col in ipairs(CATEGORIES) do
		for _, cat in ipairs(col) do
			for _, k in ipairs(cat[2]) do placed[k] = true end
		end
	end
	for _, f in ipairs(FEATURES) do
		if not placed[f.key] then other[#other + 1] = f.key end
	end
	if #other > 0 and not CATEGORIES.otherAdded then
		CATEGORIES.otherAdded = true
		table.insert(CATEGORIES[2], { "Other", other })
	end

	-- Height: the taller column.
	local tallest = 0
	for _, col in ipairs(CATEGORIES) do
		local h = 0
		for _, cat in ipairs(col) do
			local n = 0
			for _, k in ipairs(cat[2]) do if FEATURE_BY_KEY[k] or SLIDERS[k] then n = n + 1 end end
			h = h + HEAD + n * ROW
		end
		tallest = math.max(tallest, h)
	end

	local o = CreateFrame("Frame", "ZydeForeverOptions", UIParent, "BackdropTemplate")
	o:SetSize(24 + 2 * COL_W + 250, 104 + tallest)
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
	sub:SetText("Hover a feature for details.  /zyde help for commands.")

	local close = CreateFrame("Button", nil, o, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)

	o.rows = {}
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

	local function featureRow(feat, x, y)
		local cb = CreateFrame("CheckButton", nil, o, "UICheckButtonTemplate")
		cb:SetSize(24, 24)
		cb:SetPoint("TOPLEFT", x, y)
		cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
		cb.label:SetWidth(180)
		cb.label:SetJustifyH("LEFT")
		cb.label:SetWordWrap(false)
		-- A few words on what it does beside the name; a note (needs an
		-- addon / reload to apply) takes its place when there is one.
		cb.short = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		cb.short:SetPoint("LEFT", cb.label, "RIGHT", 8, 0)
		cb.short:SetWidth(COL_W - 230)
		cb.short:SetJustifyH("LEFT")
		cb.short:SetWordWrap(false)
		cb.short:SetTextColor(0.6, 0.6, 0.65)
		cb.feat = feat
		cb:SetScript("OnClick", function(self)
			setFeature(feat.key, self:GetChecked())
			if feat.key == "xp" or feat.key == "hideBars" then pcall(hideBlizzardBars) end
			o:Refresh()
		end)
		cb:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(feat.label)
			GameTooltip:AddLine(feat.desc, 1, 1, 1, true)
			local blocked = featureBlocked(feat.key)
			if blocked then GameTooltip:AddLine("Off: " .. blocked .. ".", 1, 0.4, 0.3, true) end
			if feat.reload then GameTooltip:AddLine("Turning it off fully takes a /reload.", 0.7, 0.7, 0.7, true) end
			GameTooltip:Show()
		end)
		cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
		o.rows[#o.rows + 1] = cb
	end

	-- A slider row: name where a feature's name goes, the slider beside it.
	o.sliders = {}
	local function sliderRow(def, x, y)
		local s = CreateFrame("Slider", nil, o, "BackdropTemplate")
		s.def = def
		s.label = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		s.label:SetPoint("TOPLEFT", x + 28, y - 5)
		s.label:SetText(def.label)
		s:SetOrientation("HORIZONTAL")
		s:SetSize(150, 10)
		s:SetPoint("TOPLEFT", x + 212, y - 7)
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

	for c, col in ipairs(CATEGORIES) do
		local x, y = 12 + (c - 1) * COL_W, -46
		for _, cat in ipairs(col) do
			heading(x, y, cat[1])
			y = y - HEAD
			for _, k in ipairs(cat[2]) do
				local feat = FEATURE_BY_KEY[k]
				if feat then
					featureRow(feat, x, y)
					y = y - ROW
				elseif SLIDERS[k] then
					sliderRow(SLIDERS[k], x, y)
					y = y - ROW
				end
			end
		end
	end

	local reload = CreateFrame("Button", nil, o, "UIPanelButtonTemplate")
	reload:SetSize(110, 22)
	reload:SetPoint("BOTTOMRIGHT", -12, 12)
	reload:SetText("Reload UI")
	reload:SetScript("OnClick", function() ReloadUI() end)
	o.reloadHint = o:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	o.reloadHint:SetPoint("RIGHT", reload, "LEFT", -8, 0)
	o.reloadHint:SetText("Some changes need a reload")
	o.reloadHint:Hide()

	-- Right side: the other addons some features use, and whether you have them.
	local side = CreateFrame("Frame", nil, o, "BackdropTemplate")
	side:SetPoint("TOPLEFT", o, "TOPLEFT", 12 + 2 * COL_W, -46)
	side:SetPoint("BOTTOMRIGHT", o, "BOTTOMRIGHT", -12, 44)
	side:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
	side:SetBackdropColor(1, 1, 1, 0.04)
	local head = side:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	head:SetPoint("TOPLEFT", 10, -8)
	head:SetText("Other addons used")
	head:SetTextColor(0.69, 0.35, 1)

	o.addonRows = {}
	local y = -30
	for _, a in ipairs(ns.ADDONS) do
		local name = side:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		name:SetPoint("TOPLEFT", 10, y)
		name:SetText(a.title)
		local status = side:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		status:SetPoint("TOPRIGHT", -10, y - 1)
		local used = side:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		used:SetPoint("TOPLEFT", 10, y - 16)
		used:SetPoint("RIGHT", side, "RIGHT", -10, 0)
		used:SetJustifyH("LEFT")
		used:SetText(a.used)
		o.addonRows[#o.addonRows + 1] = { addon = a, status = status }
		y = y - 16 - math.max(14, math.ceil(#a.used / 34) * 12) - 10
	end

	o.changed = {}
	function o:Refresh()
		local needReload = false
		for _, cb in ipairs(self.rows) do
			local feat = cb.feat
			local blocked = featureBlocked(feat.key)
			cb.label:SetText(feat.label)
			if blocked then
				cb:SetChecked(false)
				cb:Disable()
				cb.label:SetTextColor(0.5, 0.5, 0.5)
				local note = feat.needs and not addonOn(feat.needs) and ("needs " .. addonTitle(feat.needs)) or blocked
				cb.short:SetText("|cffff6650" .. note .. "|r")
			else
				cb:Enable()
				cb:SetChecked(featureWanted(feat.key))
				cb.label:SetTextColor(1, 1, 1)
				local changed = feat.reload and self.startState[feat.key] ~= featureWanted(feat.key)
				cb.short:SetText(changed and "|cffffd200reload to apply|r" or (feat.short or ""))
				needReload = needReload or changed
			end
		end
		self.reloadHint:SetShown(needReload)
		for _, s in ipairs(self.sliders) do
			local v = s.def.get()
			s.loading = true
			s:SetValue(v)
			s.loading = false
			s.last = v
			s.value:SetText(v)
			local live = s.def.enabled()
			if live then s:Enable() else s:Disable() end
			s.label:SetTextColor(live and 1 or 0.5, live and 1 or 0.5, live and 1 or 0.5)
			s:SetAlpha(live and 1 or 0.5)
		end
		for _, r in ipairs(self.addonRows) do
			local state = ns.addonState(r.addon.name)
			if state == "on" then
				r.status:SetText("Installed")
				r.status:SetTextColor(0.35, 1, 0.35)
			elseif state == "off" then
				r.status:SetText("Disabled")
				r.status:SetTextColor(1, 0.6, 0.2)
			else
				r.status:SetText("Not installed")
				r.status:SetTextColor(1, 0.3, 0.3)
			end
		end
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
		print("|cff66ccffZyde_Forever|r: icons over nearby objects " .. (questIconsOn() and "on" or "off")
			.. (nodeSightManages() and " (ignored: NodeSight Sparkles manages these settings)" or ""))
	elseif msg == "zygor" then
		local text = zygorMacro()
		local keys = { GetBindingKey("CLICK ZydeForeverZygorTarget:LeftButton") }
		print("|cff66ccffZyde_Forever|r: keybind = " .. (#keys > 0 and table.concat(keys, ", ") or "none set"))
		print("|cff66ccffZyde_Forever|r: ActionButtonUseKeyDown = " .. tostring(GetCVar("ActionButtonUseKeyDown")))
		if text ~= "" then
			print("|cff66ccffZyde_Forever|r: the keybind runs:")
			for line in text:gmatch("[^\n]+") do print("   " .. line) end
		else
			print("|cff66ccffZyde_Forever|r: no Zygor target buttons on this step")
		end
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
		if ns.RangeDebug then ns.RangeDebug() else print("|cff66ccffZyde_Forever|r: the range check is for hunters") end
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
		placeXP()
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
			{ "rangedebug", "hunters: show what the game says about your target's range (Auto Shot, Wing Clip, ~10 yd)" },
			{ "auradebug", "list your target's debuffs as the game reports them (for the Sunder and Thunder Clap tiles)" },
			{ "mobsdebug", "list nearby nameplates and why each is or isn't counted as a quest mob" },
			{ "test", "preview the Battle Shout, Overpower and quest item icons" },
			{ "questalert", "turn the quest item nearby alert on or off" },
			{ "questicons", "turn the icons over nearby objects on or off" },
			{ "scrap", "turn the full-bags \"scrap first\" list on or off (off while LootTriage is enabled)" },
			{ "scraptest", "preview the scrap first list now, even with bags not full" },
			{ "scrapreset", "let items you right-clicked to keep be suggested again (scrap and vendor lists)" },
			{ "vendor", "turn the vendor / auction / keep advice in item tooltips and at merchants on or off" },
			{ "ammovendor","hunters: waypoint to the nearest arrow or bullet vendor (or click the Arrows line)" },
			{ "ammowarn <number>", "hunters: warn when leaving town with fewer arrows or bullets than this (default 600, 0 = off)" },
			{ "questrange <yards>", "how far away quest objects are spotted (default 30)" },
			{ "questheight <pixels>", "the tallest the quest tracker gets before it scrolls (0 = down to the bottom of the screen)" },
			{ "questdebug", "stand facing a quest object and run this to see why it is or isn't detected" },
			{ "zygor", "show what the Zygor target keybind will do on this step" },
		}) do
			print(("  |cffffd200/zyde %s|r - %s"):format(c[1], c[2]))
		end
		print("  Keybinds (Fishing, Zygor target, nearest quest mob, feed pet, call or revive pet, marker wheels): Options > Keybindings > AddOns > Zyde Forever")
	end
end
