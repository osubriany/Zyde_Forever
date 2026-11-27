-- Zyde_Forever
-- 1) Warrior reminders: a bar of icons beside your character. Battle Shout
--    missing and Overpower ready are two of them. The urgent ones pulse.
--    Ctrl+click the bar to lay it out in a row or a column. Alt+click cycles
--    the size. Shift-drag to move it.
-- 2) Hides the main action bar art, the bag bar, the micro menu and the
--    experience bar.
-- 3) A small draggable "XP 45.2%" readout in place of the experience bar.
-- 4) One Button Fishing keybind (Keybindings > Zyde Forever).
-- 5) Flight masters open the flight map directly (hold Shift to talk instead).
-- 6) Rarity-colored borders on equipped gear in the character screen.
-- 8) Minimap tracking (e.g. Find Minerals) comes back on after you die.
-- 9) Icons over nearby objects, and an alert when one is a quest item.
-- 10) Drop chance under Questie's nameplate loot bag (QuestieDrops.lua).
-- 11) Bags full: the 3 cheapest stacks marked 1-2-3 (ScrapList.lua).
-- 12) Vendor / auction / keep advice per bag item, sell panel at merchants (VendorList.lua).
-- 13) Group finder helper: groups with room for you first, whisper the leader (LFGHelper.lua).
-- 14) A small draggable info bar, one line: location, gold, bags, and ammo.
--     Travel opens a second line: steps, swim, mounted, and jumps.
--     Mining and Herbalism, once learned, each open a count line (InfoBar.lua).
-- 15) Tank threat list: a table of mobs you have threat on, your percent,
--     and the next two people (ThreatBox.lua).
-- 16) Minimap button bag: one button on the minimap holds the other addon
--     buttons. A key opens those and the game menu at the cursor (MinimapButtons.lua).
--
-- /zyde test     - toggle preview of both icons (to see where they sit)
-- /zyde resetxp  - put the XP readout back at its default spot
-- /zyde quest <id> - is that quest flagged complete, plus its Questie name

local ADDON, ns = ...

-- The reload dialog names the addon and not the call. Say which function
-- it was, once, so the next reload is enough to find it.
do
	local told = false
	local watch = CreateFrame("Frame")
	watch:RegisterEvent("ADDON_ACTION_FORBIDDEN")
	watch:SetScript("OnEvent", function(_, _, addon, func)
		if told or addon ~= ADDON then return end
		told = true
		local name = (not ns.isSecret(func) and tostring(func)) or "?"
		local msg = "|cff66ccffZyde_Forever|r was blocked calling " .. name
		-- Outside this event. Printing here runs inside the blocked action and taints chat.
		if C_Timer and C_Timer.After then C_Timer.After(0, function() print(msg) end)
		else print(msg) end
	end)
end

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

-- The global SetCVar is a Blizzard-only action on this client and raises
-- the reload dialog. C_CVar.SetCVar is the call the other addons here use.
local function setCVar(name, value)
	if C_CVar and C_CVar.SetCVar then pcall(C_CVar.SetCVar, name, value) end
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

-- A mob's level color, by Classic's rules (what Blizzard's frames show on Forever;
-- the modern client's own GetCreatureDifficultyColor greys mobs out sooner). By
-- the mob's level against yours: red 5+ above, orange 3-4 above, yellow within 2,
-- green below that, grey at or under the "no XP" level: none until 6; then your
-- level - 5 - level/10 up to 39; your level - 1 - level/5 from 40 to 59; 51 at 60.
-- Bosses ("??", level -1) are red.  ns.levelColor(level) -> { r, g, b }
do
	local FALLBACK = {
		impossible = { r = 1, g = 0.1, b = 0.1 }, verydifficult = { r = 1, g = 0.5, b = 0.25 },
		difficult = { r = 1, g = 0.82, b = 0 }, standard = { r = 0.25, g = 0.75, b = 0.25 },
		trivial = { r = 0.5, g = 0.5, b = 0.5 },
	}
	local function color(kind)
		local t = QuestDifficultyColors and QuestDifficultyColors[kind]
		return (type(t) == "table" and t.r) and t or FALLBACK[kind]
	end
	local function grayLevel(me)
		if me <= 5 then return 0 end
		if me <= 39 then return me - 5 - math.floor(me / 10) end
		if me <= 59 then return me - 1 - math.floor(me / 5) end
		return me - 9
	end
	function ns.levelColor(level)
		local me = UnitLevel("player")
		if isSecret(me) or type(me) ~= "number" or type(level) ~= "number" then return color("difficult") end
		if level < 0 then return color("impossible") end
		local diff = level - me
		if diff >= 5 then return color("impossible") end
		if diff >= 3 then return color("verydifficult") end
		if diff >= -2 then return color("difficult") end
		if level > grayLevel(me) then return color("standard") end
		return color("trivial")
	end
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
	{ key = "reminders", short = "icons beside you", label = "Reminder icons", desc = "A bar of icons beside you. Shift-drag it to move it. Ctrl+click it to switch between a column and a row. Alt+click it to cycle the size (-60%, -30%, normal, +30%, +60%). Size is also the option under this one. Battle Shout, Thunder Clap, Demoralizing Shout, being out of melee range, Eviscerate and Seal of Righteousness pulse. Warriors: in a fight, Battle Shout, Thunder Clap, Demoralizing Shout and being out of melee range. Also Overpower / Execute / Revenge / Victory Rush ready, Shield Block flashing when ready and counting down while it recharges, wrong stance, and Sunder stacks in Defensive Stance. Hunters: no Aspect, Cheetah or Pack on in combat, Hunter's Mark missing (solo), target too far or too close to shoot, Mongoose Bite ready, Mend Pet. Shamans: weapon imbue missing or running out, Lightning Shield missing or low, Earth Shock to interrupt, a totem out of range, no Ankh. Everyone: Well-Rested low, eat when Well Fed is down, use a Camp Tent when rested XP is under 5% and Boosted Rest is off, gear needs repair, low on food or water" },
	{ key = "ammo", class = "HUNTER", short = "count, refill, warning", label = "Hunter ammo", desc = "Arrows or bullets left and how long they last (in the XP readout), a warning when you leave town low, and a Fill quiver button at ammo vendors (hunters)" },
	{ key = "autoTrack", class = "HUNTER", short = "tracking picks itself", label = "Auto tracking", desc = "Turns on the tracking for the kind of enemy most around you (Beasts, Humanoids, Undead, Demons, Elementals, Giants, Dragonkin), counting your target and quest mobs most. Switches out of combat only, at most every 10 seconds, and only when a new kind clearly leads. Leaves it alone for 2 minutes after you pick a tracking yourself, and while Find Herbs, Find Minerals or Find Treasure is on. /zyde trackdebug shows what it sees (hunters)" },
	{ key = "petCare", class = "HUNTER", short = "feed, call, Growl", label = "Hunter pet care", desc = "Keys to feed your pet the right food and to call or revive it, with reminders when it's hungry or missing, and a Growl autocast reminder: off in a group, on when solo (hunters)" },
	{ key = "markerWheel", short = "marks on the target", label = "Target markers", desc = "Hold the marker key and two rows of four icons show just under your cursor. Top: skull, X, square, moon. Bottom: triangle, diamond, circle, star. The red button removes the mark on your target. The gold ALL button removes every mark. Clicking the icon already on your target removes that mark too. Click a different icon to change it. Letting go hides the icons. World markers stay a separate key: press it to show or hide the squares, drag the title to move them, click a square, then the ground. The last square clears those." },
	{ key = "radial", short = "your spells in a ring", label = "Radial ring", desc = "Hold the Radial ring key (Keybindings > Zyde Forever) and a ring of your own spells, macros and items opens around the cursor. Move toward one and let go of the key to use it; let go in the middle to cancel. Works in combat. Set up puts things on it (or /zyde ring)" },
	{ key = "hideBars", short = "cleaner action bars", label = "Hide Blizzard bar art", desc = "Hides the action bar art and the bag bar", reload = true },
	{ key = "hideMicroMenu", short = "game menu buttons", label = "Hide micro menu", desc = "Hides the row of small game menu buttons (character, spellbook, talents, quest log, social, game menu...). Their keybinds still work", reload = true },
	{ key = "xp", short = "compact XP display", label = "XP readout", desc = "Small draggable XP % with rested XP, time to level and tooltip (replaces the XP bar)", reload = true },
	{ key = "infoBar", short = "location, gold, bags", label = "Info bar", desc = "One line you can drag: where you are, gold, bag space, bank space (used/total, FULL when full), ammo for a bow, gun, or throwing weapon, and gear durability. Travel opens a second line with steps (miles in parentheses), yards swum, yards mounted, and jumps. Mining, once learned, opens a count of each ore in your bags and bank. Herbs does the same for Herbalism. Both lines can be open at once. Those travel counts are kept for this character. Ctrl+click a line to paste it into chat" },
	{ key = "threatBox", short = "tank threat table", label = "Tank threat list", desc = "While you are set to the tank role in a party or raid: a draggable table of mobs you have threat on. Columns are the mob, your threat percent, then the two people closest behind you and their percent. Only mobs with a nameplate, bosses, and your target can be listed. Drag the title to move it" },
	{ key = "unitFrames", short = "flat health boxes", label = "Unit frames", desc = "Flat player, target, party and raid frames with buffs and debuffs, mana / rage / energy on party frames. In combat your portrait flashes red and the combat swords show. Shift-drag a frame to move it", reload = true },
	{ key = "targetTarget", short = "small frame by target", label = "Target of target", desc = "A small frame beside the target frame showing who your target is targeting (with the Zyde unit frames on). Shift-drag it to move it" },
	{ key = "unitAuras", short = "icons on your frames", label = "Unit frame buffs / debuffs", desc = "Buff and debuff icons with time left on the Zyde unit frames: the target's debuffs (yours first) and buffs, your debuffs and buffs, and your pet's" },
	{ key = "plates", short = "flat enemy nameplates", label = "Nameplates", desc = "Flat enemy nameplates in the unit frames' style: full name above, level badge (elite +, rare dragon, boss skull), cast bar (orange = interruptible), your debuffs with time left, aggro warning (AGGRO on mobs attacking you, LOOSE when you tank and a mob isn't on you), Execute-range color for warriors, and the quest icon, count and drop chance together on the right (Questie). Friendly and object nameplates keep the game's look" },
	{ key = "comboPoints", short = "pips on your target", label = "Combo points on nameplate", desc = "Rogues and druids in cat form: a row of pips above your target's nameplate, one per combo point, gold to red, all red when full (with Zyde nameplates on)" },
	{ key = "barTidy", short = "short keys, no empty slots", label = "Tidy action bars", desc = "Short keybind labels on action buttons (a-1 becomes A1, Mouse Button 4 becomes M4) and empty slots hidden - they show again while you drag a spell or item" },
	{ key = "gear", short = "borders, item levels", label = "Character screen gear", desc = "Rarity borders and item levels; a green arrow when your bags hold an upgrade for a slot (scored by GearAdvisor if loaded), empty slots quiet gray unless your bags can fill them, and your average item level in the header", reload = true },
	{ key = "fishing", short = "one-key fishing", label = "One Button Fishing", desc = "Same key casts and reels in (set the key in Keybindings)" },
	{ key = "buttonBag", short = "one button, a key for the rest", label = "Minimap button bag", desc = "Gathers the other addon buttons on the minimap onto one button. Click that button to spread them out. Drag it around the minimap to move it. Hold Buttons at cursor (Options > Keybindings > Zyde Forever) to open tradeskills, the game menu, and those buttons at the mouse" },
	{ key = "minimap", short = "zone and local time", label = "Minimap", desc = "A few looks for the minimap: Round, Gilded, or Square. Drag the map to move it. The zone name sits under it, with your local time below. Off while SexyMap is loaded", conflict = "SexyMap" },
	{ key = "mapSkin", short = "the map in Zyde's look", label = "World map look", desc = "The world map in Zyde's look: a flat dark frame with a gold title and square buttons, flat tabs along the top (purple for the map you're on), and a dark quest list with flat headings. The map, its icons and pins are unchanged. Off until you tick it", defaultOff = true, reload = true },
	{ key = "mapNotes", short = "alt-click to mark", label = "Map markers", desc = "Your own named markers on the world map, kept between sessions. Alt-click the map to drop one and name it, alt-click a marker to remove it, right-click to rename it" },
	{ key = "flightTimer", short = "time left on flights", label = "Flight timer", desc = "On a flight: a panel near the middle of the screen with where you're going, the time left and a progress bar (drag it to move it). Flight map tooltips show each flight's time. Uses the published times of about 900 Classic flights, and remembers your own" },
	{ key = "flight", short = "skip flight chat", label = "Flight master shortcut", desc = "Flight masters open the map directly (hold Shift to talk)" },
	{ key = "tracking", short = "re-enable after death", label = "Keep tracking after death", desc = "Turns Find Minerals, Find Herbs... back on after you die" },
	{ key = "questTracker", short = "ready first, by level", label = "Quest tracker", desc = "Replaces the game's quest tracker: quests ready to turn in, then this zone, then other zones folded away. The mark on each heading cycles that list: nearest, highest level, lowest level. Finished objective lines are hidden", reload = true },
	{ key = "rares", short = "flash + sound", label = "Rare announcer", desc = "When a rare or rare elite shows up (on a nameplate, as your target or mouseover, or on the minimap), its name flashes on screen, a line goes to chat and a sound plays. Each rare is announced once per 5 minutes. Rares you've just seen are also first for the \"Target nearest quest mob\" key" },
	{ key = "questAlert", short = "glow on quest objects", label = "Quest object alert", desc = "Glow, ! and ping on nearby quest objects you pick up (not the loot of mobs you kill for a quest)" },
	{ key = "questIcons", short = "icons over nodes", label = "Icons over nearby objects", desc = "The game's interact icons over herbs, ore and chests" },
	{ key = "rotation", short = "best ability glows blue", label = "Ability highlight", desc = "In a fight, the action button that does the most damage right now glows blue. It weighs each spell's damage, damage over time, cooldown and cast time against how long the fight has left, how many enemies are on you, your mana/rage/energy and combo points. Execute-type moves take over at low health even while the game hides it. Hunters get more: the pet's Attack button until it's on your target, a short head start for it, shots that save mana for the next pull as you run low, no glow while you're above your pet or your group's tank on threat (Growl off means a group tank), Multi-Shot only when every mob it could hit is safely held and no unpulled mob is in reach, Mend Pet in green, Feign Death in amber when the mob turns on you, and your big cooldowns in red when the fight is dangerous. /zyde rotationdebug shows its numbers" },
	{ key = "pullLight", short = "healer mana light", label = "Pull traffic light", desc = "When you tank a dungeon or raid: a small traffic light for your healer's mana you can drag anywhere. GO (green) at 70% or more, careful (yellow) 30-70%, STOP (red) under 30%, with a mana bar, a drink countdown, and DEAD / OFFLINE. Works in combat. /zyde light to place it, /zyde healer <name> to pick the healer" },
	{ key = "nodeGlow", short = "herbs, ore, chests", label = "Herb, ore and chest glow", desc = "A colored glow and icon on herbs (green) and ore (copper) you can gather with your professions, and on chests (gold), within 30 yards. Brighter on the one you face" },
	{ key = "guildRoster", short = "class colors, levels, zones", label = "Guild member list", desc = "In the Guild & Communities window: online members' names in class colors, each member's level at the right (colored by how near your level), and their zone when you hover them" },
	{ key = "lfg", short = "groups that fit you", label = "Group finder helper", desc = "Beside Looking For Group: groups with room for your role first, one-click whisper to the leader" },
	{ key = "bagWindow", short = "one bag, sorted for you", label = "One bag window", desc = "All your bags in one window, sorted into sections by itself: Perma (never delete: Hearthstone, Philosopher's Stone, profession tools), Quest, Junk, Keys (your keyring), gear, food and potions, profession goods, and your empty slots. Items work as in the normal bags (right-click to use or sell, drag, shift-click to link). Alt-click an item to put it in Perma or take it out. Click a heading to fold it. The Bank button shows how full the bank is (90/90 FULL when it is full), or /zyde bank opens it from the last visit and leaves your bags open. At a banker that is the real bank, with a row to buy the next bank slot and swap bank bags. Off while Baganator is loaded", conflict = "Baganator", reload = true },
	{ key = "sellJunk", short = "grays sold for you", label = "Sell junk at vendors", desc = "When you talk to a vendor, every gray item, and anything you marked as junk (drop it on the Junk bar that shows at the top of your bags while you hold an item), that's worth something is sold for you (never Perma items), and chat says how much you got. The last 12 can be bought back from the vendor" },
	{ key = "scrap", short ="what to delete", label = "Scrap list (bags full)", desc = "The 3 cheapest items to throw away when your bags are full" },
	{ key = "vendor", short = "sell or auction tips", label = "Vendor / auction advice", desc = "Vendor it / Auction it / Keep in tooltips, merchant and AH panels", needs = "AHledger" },
	{ key = "recipes", short = "what to learn, where, price", label = "Unlearned recipes", desc = "Beside a profession window: the recipes you haven't learned yet, where to get each (vendor, quest or drop) and, with AHledger, its auction price. Click one for a waypoint to its vendor. The Unlearned button on the window shows or hides it", needs = "Questie" },
	{ key = "restedWatch", short = "full rested alerts", label = "Rested XP watch", desc = "Remembers each character's rested XP and whether it logged out resting (inn or city). At login: a note when this character's rested XP is full, and which of your other characters should be full by now. /zyde rested lists them all with time until full" },
	{ key = "npcKeys", short = "press 1-9 to choose", label = "Number keys for NPC options", desc = "In an NPC's dialog, each choice (quests to take or hand in, gossip lines) gets a small gold number, top to bottom. Press 1-9 or the number pad to pick it, like a click. Other keys, and numbers with no choice, work as usual. Not in a fight" },
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
	{ name = "AHledger", title = "AHledger", used = "Needed for vendor / auction advice. Adds auction prices to the scrap list." },
	{ name = "ForeverDungeonJournal", title = "DungeonJournal", used = "Adds a Dungeon Journal button to the hold menu.", plain = true },}

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
	-- A few features start off until you tick them (defaultOff in FEATURES).
	local f = FEATURE_BY_KEY[key]
	if f and f.defaultOff then return false end
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
-- Battle Shout pulses in the bar until you put it on.
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
-- Moving the bar: Shift-drag any icon (out of combat). Ctrl+click flips between
-- a column and a row. Alt+click cycles the size. The icons only take the mouse
-- while Shift, Ctrl, or Alt is held, so they never block clicks otherwise.
-- /zyde resetreminders puts the bar back beside your character.
---------------------------------------------------------------------------
do -- own scope (200-local limit)
anchor:SetMovable(true)
anchor:SetClampedToScreen(true)

-- Saved size, as a percent off the original 44px. Older saves used small / normal / large.
local SIZE_MUL = { ["-60"] = 0.4, ["-30"] = 0.7, ["0"] = 1, ["30"] = 1.3, ["60"] = 1.6, small = 0.7, normal = 1, large = 1.3 }
local SIZE_ORDER = { "-60", "-30", "0", "30", "60" }
local SIZE_ALIAS = { small = "-30", normal = "0", large = "30" }

local function sizeKey()
	local key = ZydeForeverDB and ZydeForeverDB.reminderSize
	key = SIZE_ALIAS[key] or key
	if key and SIZE_MUL[key] then return key end
	return "0"
end

function ns.ReminderMetrics()
	local db = ZydeForeverDB
	local mul = SIZE_MUL[db and db.reminderSize] or 1
	local size = math.floor(ICON_SIZE * mul + 0.5)
	local gap = math.max(2, math.floor(SPACING * mul + 0.5))
	return size, gap, db and db.reminderLayout == "horizontal"
end

function ns.SetReminderSize(key)
	ZydeForeverDB = ZydeForeverDB or {}
	key = SIZE_ALIAS[key] or key
	if not SIZE_MUL[key] then key = "0" end
	ZydeForeverDB.reminderSize = key
	if ns.RefreshReminders then ns.RefreshReminders() end
end

function ns.CycleReminderSize()
	local cur = sizeKey()
	local i = 1
	for n, k in ipairs(SIZE_ORDER) do
		if k == cur then i = n end
	end
	ns.SetReminderSize(SIZE_ORDER[i % #SIZE_ORDER + 1])
end

function ns.ToggleReminderLayout()
	ZydeForeverDB = ZydeForeverDB or {}
	ZydeForeverDB.reminderLayout = ZydeForeverDB.reminderLayout == "horizontal" and "vertical" or "horizontal"
	if ns.RefreshReminders then ns.RefreshReminders() end
end

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
			f:SetScript("OnDragStart", function()
				if IsShiftKeyDown() and not InCombatLockdown() then anchor:StartMoving() end
			end)
			f:SetScript("OnMouseUp", function(_, button)
				if button ~= "LeftButton" or IsShiftKeyDown() or InCombatLockdown() then return end
				if IsAltKeyDown() and not IsControlKeyDown() then ns.CycleReminderSize()
				elseif IsControlKeyDown() and not IsAltKeyDown() then ns.ToggleReminderLayout() end
			end)
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
	setDraggable((IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown()) and not InCombatLockdown())
end)

ns.ResetReminderPosition = function()
	if ZydeForeverDB then ZydeForeverDB.reminderPos = nil end
	placeAnchor()
	print("|cff66ccffZyde_Forever|r: reminder icons moved back beside your character")
end
end -- reminder dragging

-- Stack the shown icons in a column or a row. Runs 10 times a second, so an
-- icon is only moved when its place, size, or direction changes. Urgent icons
-- stay in the bar and pulse (their border color is EDGE).
local EDGE = {
	shout = { 0.95, 0.72, 0.15, 1 },
	meleeRange = { 0.95, 0.15, 0.1, 1 },
	thunderClap = { 0.25, 0.55, 1, 1 },
	demoShout = { 0.72, 0.22, 0.18, 1 },
	eviscerate = { 0.85, 0.1, 0.25, 1 },
	sealRighteousness = { 1, 0.85, 0.35, 1 },
}
local function layout(states)
	local size, gap, horizontal = ns.ReminderMetrics()
	local cursor, n = 0, 0
	for _, icon in ipairs(icons) do
		local f = icon.frame
		if states[icon.key] then
			local step = size
			if horizontal and f.label then
				local text = f.label:GetText()
				if text and text ~= "" then step = math.max(size, math.ceil(f.label:GetStringWidth()) + 8) end
			end
			local along = horizontal and (cursor + (step - size) / 2) or 0
			local down = horizontal and 0 or -cursor
			if f.zydeSlot ~= n or f.zydeHoriz ~= horizontal or not f:IsShown() or f:GetWidth() ~= size or f.zydeAlong ~= along then
				f.zydeSlot, f.zydeHoriz, f.zydeAlong = n, horizontal, along
				f:SetSize(size, size)
				f:ClearAllPoints()
				if horizontal then
					f:SetPoint("TOPLEFT", anchor, "TOPLEFT", along, 0)
				else
					f:SetPoint("TOP", anchor, "TOP", 0, down)
				end
				if f.label then
					f.label:ClearAllPoints()
					if horizontal then
						f.label:SetPoint("TOP", f, "BOTTOM", 0, -2)
						f.label:SetJustifyH("CENTER")
					else
						f.label:SetPoint("LEFT", f, "RIGHT", 6, 0)
						f.label:SetJustifyH("LEFT")
					end
				end
				f:Show()
			end
			if f.prominent then
				f.pulseFast = icon.key == "meleeRange"
				local edge = EDGE[icon.key]
				if edge then f.border:SetColorTexture(edge[1], edge[2], edge[3], edge[4]) end
			end
			cursor = cursor + step + gap
			n = n + 1
		elseif f:IsShown() then
			f:Hide()
			f:SetAlpha(1)
			f:SetSize(size, size)
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
ns.RefreshReminders = update

anchor:SetScript("OnUpdate", function(_, elapsed)
	-- Urgent icons pulse every frame. The rest of the bar stays steady.
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
		setCVar("nameplateMaxDistance", db.plateDistOrig)
		db.plateDistOrig = nil
		db.questRange = 30 -- and the pickup range back to the usual 30
	end
	if db.questRange then setCVar("SoftTargetInteractRange", db.questRange) end
end

local function applyQuestIcons()
	C_Timer.After(1, applyQuestRange)
	if InCombatLockdown() then return end
	local on = questIconsOn()
	-- Objects only get a nameplate (which the glows sit on) with the interact settings on:
	-- the game's icons and the herb / ore / chest glows both need them.
	local objects = on or F("nodeGlow")
	if objects then
		if not gamepadUI() and (tonumber(GetCVar("SoftTargetInteract")) or 0) < 3 then
			setCVar("SoftTargetInteract", 3)
		end
		setCVar("SoftTargetInteractArc", 2)    -- objects all around you, not only in front
		setCVar("SoftTargetInteractRange", 30) -- yards (default 10)
		-- No nameplate popping up on friendly NPCs you face.
		setCVar("SoftTargetNameplateInteract", 0)
	end
	setCVar("SoftTargetIconGameObject", on and 1 or 0)
	setCVar("SoftTargetIconInteract", on and 1 or 0)
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

-- Herbs, ore and chests ("nodeGlow"): what kind of thing an object is, or nil.
-- First the game's own interact icon on the object's plate (its art is named for
-- the kind: "herb", "mine", "loot"), then the object's name: "... Vein" / "...
-- Deposit" is ore, a Classic herb's name is a herb, "... Chest" / "Footlocker" /
-- "Strongbox" / "Coffer" / "Trunk" is a chest. Herbs only with Herbalism, ore only
-- with Mining. Kept per object (GUID).
local nodeKind
do -- own scope (200-local limit)
	local HERBS = {}
	for _, n in ipairs({ "Peacebloom", "Silverleaf", "Earthroot", "Mageroyal", "Briarthorn", "Stranglekelp",
		"Bruiseweed", "Wild Steelbloom", "Grave Moss", "Kingsblood", "Liferoot", "Fadeleaf", "Goldthorn",
		"Khadgar's Whisker", "Wintersbite", "Firebloom", "Purple Lotus", "Arthas' Tears", "Sungrass",
		"Blindweed", "Ghost Mushroom", "Gromsblood", "Golden Sansam", "Dreamfoil", "Mountain Silversage",
		"Plaguebloom", "Icecap", "Black Lotus", "Bloodvine" }) do HERBS[n:lower()] = true end
	local CHEST_ENDS = { "chest", "footlocker", "strongbox", "coffer", "trunk" }
	local HERBALISM = { 2366, 2368, 3570, 11993 }
	local MINING = { 2575, 2576, 3564, 10248 }
	local kinds = {} -- guid -> kind or false

	local function byArt(art)
		art = plainStr(art)
		if type(art) ~= "string" then return nil end
		art = art:lower()
		if art:find("herb", 1, true) then return "herb" end
		if art:find("mine", 1, true) or art:find("mining", 1, true) then return "ore" end
		if art:find("loot", 1, true) then return "chest" end
		return nil
	end
	local function byName(name)
		if type(name) ~= "string" then return nil end
		local n = name:lower()
		if n:find("vein$") or n:find("deposit$") then return "ore" end
		if HERBS[n] then return "herb" end
		for _, e in ipairs(CHEST_ENDS) do
			if n:sub(-#e) == e then return "chest" end
		end
		return nil
	end
	local function find(unit, name)
		local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
		local uf = plate and plate.UnitFrame
		local icon = uf and uf.SoftTargetFrame and uf.SoftTargetFrame.Icon
		if icon and icon:IsShown() then
			local k = byArt(icon.GetAtlas and icon:GetAtlas()) or byArt(icon:GetTexture())
			if k then return k end
		end
		return byName(name)
	end

	function nodeKind(unit, guid, name)
		local k
		if guid and kinds[guid] ~= nil then
			k = kinds[guid] or nil
		else
			k = find(unit, name)
			if guid and (k or name) then kinds[guid] = k or false end -- (no name yet: try again)
		end
		if k == "herb" and not knownRank(HERBALISM) then return nil end
		if k == "ore" and not knownRank(MINING) then return nil end
		return k
	end
end

-- Object plates in range: list of { unit, guid, name, picked, reason, guess, kind }.
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
			local kind = not (reason and questAlertOn()) and (guid or name) and F("nodeGlow") and nodeKind(unit, guid, name) or nil
			found[#found + 1] = { unit = unit, guid = guid, name = name, reason = reason, guess = guess, kind = kind,
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

-- The marker's look: a quest object (gold glow, quest "!"), or a herb (green), ore
-- (copper) or chest (gold) with a small icon of its kind.
local MARK_LOOK = {
	quest = { 1, 0.85, 0.25, "Interface\\GossipFrame\\AvailableQuestIcon", 26 },
	herb = { 0.35, 1, 0.35, "Interface\\Icons\\INV_Misc_Flower_02", 18 },
	ore = { 1, 0.55, 0.2, "Interface\\Icons\\INV_Ore_Copper_01", 18 },
	chest = { 1, 0.8, 0.3, "Interface\\Icons\\INV_Box_02", 18 },
}
local wantedPlates, wantedLook = {}, {} -- reused by updateMarkers (no new table per scan)
local function updateMarkers(objects) -- objects nil: hide them all
	local wanted, look = wantedPlates, wantedLook
	wipe(wanted)
	wipe(look)
	local quests = questAlertOn()
	for _, o in ipairs(objects or wanted) do
		local kind = (o.reason and quests) and "quest" or o.kind
		if kind then
			local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(o.unit)
			-- (value: 1 for a sure match or the object you face, dimmer for a dungeon
			-- guess or a node a little way off)
			if plate then
				wanted[plate] = (kind == "quest" and (o.guess and 0.5 or 1)) or (o.picked and 1 or 0.7)
				look[plate] = kind
			end
		end
	end
	for plate, alpha in pairs(wanted) do
		local m = getMarker(plate)
		local kind = look[plate]
		if m.kind ~= kind then
			m.kind = kind
			local l = MARK_LOOK[kind]
			m.glow:SetVertexColor(l[1], l[2], l[3])
			m.bang:SetTexture(l[4])
			m.bang:SetSize(l[5], l[5])
			if kind == "quest" then m.bang:SetTexCoord(0, 1, 0, 1) else m.bang:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
		end
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
	local objects -- stays nil (no scan) while both the alert and node glows are off, or you're dead
	if (questAlertOn() or F("nodeGlow")) and not UnitIsDeadOrGhost("player") then
		objects = scanObjects()
		if questAlertOn() then
			for _, o in ipairs(objects) do
				if o.reason and o.name and (not best or (o.picked and not best.picked)) then best = o end
			end
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
	if key == "nodeGlow" then applyQuestIcons() checkQuestObject() end
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
-- Bind a key in Options > Keybindings > Zyde Forever.
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
		setCVar("SoftTargetInteract", 3)
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
		setCVar("SoftTargetInteract", savedSoftInteract)
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

-- The window's categories. Each one is a tab. A column is a list of { heading, entries }.
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
			{ "unitFrames", children = { "unitAuras", "targetTarget" }, choosers = { "frameStyle", "playerAuras" } },
			{ "plates", children = { "comboPoints" } }, "xp",
			{ "reminders", children = {}, choosers = { "reminderSize" } },
			{ group = "Action bars", children = { "hideBars", "hideMicroMenu", "barTidy", "rotation" } },
			{ "minimap", children = {}, choosers = { "minimapLook" } },
			"mapSkin",
			"buttonBag", "gear",
			{ "radial", children = {}, button = { label = "Set up", click = function() if ns.Radial then ns.Radial.ToggleEditor() end end } },
		} },
		{ "Hunter", { "ammo", "petCare", "autoTrack" } },
		{ "Groups", { "lfg", "guildRoster", "markerWheel", "pullLight" } },
	},
	{
		{ "Questing & leveling", {
			{ "questTracker", children = { "questFont" } },
			"autoQuests", "npcKeys", "restedWatch",
			{ group = "Objects nearby", children = { "questAlert", "nodeGlow", "questIcons" } },
			{ group = "Questie", children = { "questMobs", "questieDrops" } },
			"rares",
		} },
		{ "Bags & vendors", { "bagWindow", "sellJunk", "scrap", "vendor", "recipes" } },
		{ "Travel & gathering", { "mapNotes", "flight", "flightTimer", "tracking", "fishing" } },
	},
}

-- Short names for options shown on an indented line beside each other.
local CHILD_LABEL = {
	unitAuras = "Buffs / debuffs", targetTarget = "Target of target", comboPoints = "Combo points",
	hideBars = "Hide bar art", hideMicroMenu = "Hide micro menu", barTidy = "Tidy keys & slots",
	questAlert = "Quest glow", questIcons = "Game icons", nodeGlow = "Herb, ore, chest glow",
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
		reminderSize = {
			label = "Icon size", parent = "reminders", width = 110,
			desc = "How big the reminder icons are, compared with the original size. Alt+click the bar to cycle these. Ctrl+click switches between a column and a row. Shift-drag moves it.",
			options = function()
				return {
					{ key = "-60", label = "-60%", desc = "60% smaller than the original size." },
					{ key = "-30", label = "-30%", desc = "30% smaller than the original size." },
					{ key = "0", label = "Normal", desc = "The original size." },
					{ key = "30", label = "+30%", desc = "30% bigger than the original size." },
					{ key = "60", label = "+60%", desc = "60% bigger than the original size." },
				}
			end,
			get = function()
				local s = ZydeForeverDB and ZydeForeverDB.reminderSize
				if s == "small" then return "-30" end
				if s == "large" then return "30" end
				if s == "-60" or s == "-30" or s == "30" or s == "60" then return s end
				return "0"
			end,
			set = function(k) ns.SetReminderSize(k) end,
			changed = function() return false end,
		},
		minimapLook = {
			label = "Look", parent = "minimap", width = 120,
			desc = "Round, Gilded, or Square. The zone name and your local time stay under the map.",
			options = function() return ns.MinimapLook and ns.MinimapLook.LOOKS or {} end,
			get = function() return ns.MinimapLook and ns.MinimapLook.Get() or "round" end,
			set = function(k) if ns.MinimapLook then ns.MinimapLook.Set(k) end end,
			changed = function() return false end,
		},
		playerAuras = {
			label = "Your auras", parent = "unitFrames", width = 168,
			desc = "What is drawn above your own frame. Applies right away, while buffs / debuffs are on.",
			options = function() return ns.UnitFrames and ns.UnitFrames.AURA_MODES or {} end,
			get = function() return ns.UnitFrames and ns.UnitFrames.GetPlayerAuras() or "all" end,
			set = function(k) if ns.UnitFrames then ns.UnitFrames.SetPlayerAuras(k) end end,
			changed = function() return false end,
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

	-- Anything not placed in a category goes under an Other tab.
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
	sub:SetText("Hover an option for details.")

	local close = CreateFrame("Button", nil, o, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	local cmds = CreateFrame("Button", nil, o, "UIPanelButtonTemplate")
	cmds:SetSize(108, 22)
	cmds:SetPoint("RIGHT", close, "LEFT", -4, 0)
	cmds:SetText("Commands")
	cmds:SetScript("OnClick", function() ns.ToggleCommandList() end)

	o.rows, o.sliders, o.choosers = {}, {}, {}

	-- Category rows are built onto the open tab's page. The footer stays on the window.
	local host = o
	local span = COL_W

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
		local cb = CreateFrame("CheckButton", nil, host, "UICheckButtonTemplate")
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
		local s = CreateFrame("Slider", nil, host, "BackdropTemplate")
		s.def = def
		s.label = host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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
		s.value = host:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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
		local wide = def.width or 150
		local c = CreateFrame("Button", nil, host, "BackdropTemplate")
		c.def = def
		c.label = host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		c.label:SetPoint("TOPLEFT", x + 4, y - 6)
		c.label:SetText(def.label)
		c:SetSize(wide, 20)
		c:SetPoint("LEFT", c.label, "RIGHT", 10, 0)
		c:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		c:SetBackdropColor(0, 0, 0, 0.6)
		c:SetBackdropBorderColor(0.69, 0.35, 1, 0.5)
		c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		c.text:SetPoint("LEFT", 6, 0)
		c.text:SetPoint("RIGHT", -16, 0)
		c.text:SetJustifyH("LEFT")
		c.text:SetWordWrap(false)
		local arrow = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		arrow:SetPoint("RIGHT", -7, 0)
		arrow:SetText("v")
		c.note = host:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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
			b:SetSize(wide - 2, 20)
			b:SetPoint("TOPLEFT", 1, -1 - (i - 1) * 20)
			local hl = b:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints()
			hl:SetColorTexture(0.69, 0.35, 1, 0.3)
			b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			b.text:SetPoint("LEFT", 6, 0)
			b.text:SetPoint("RIGHT", -4, 0)
			b.text:SetJustifyH("LEFT")
			b.text:SetWordWrap(false)
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
		menu:SetSize(wide, #list * 20 + 2)
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

	-- One page per category. The tab is the section name, so the page has no second heading.
	local pages = {}
	local function paintOptTab(b, on)
		if on then
			b:SetBackdropColor(0.69, 0.35, 1, 0.45)
			b:SetBackdropBorderColor(0.69, 0.35, 1, 1)
			b.text:SetTextColor(1, 0.82, 0.2)
		else
			b:SetBackdropColor(0, 0, 0, 0.45)
			b:SetBackdropBorderColor(0.69, 0.35, 1, 0.35)
			b.text:SetTextColor(0.72, 0.72, 0.72)
		end
	end

	local cats = {}
	for _, col in ipairs(CATEGORIES) do
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
			if #entries > 0 then cats[#cats + 1] = { name = cat[1], entries = entries } end
		end
	end

	local tabGap, tabRow = 4, 0
	for i, cat in ipairs(cats) do
		local b = CreateFrame("Button", nil, o, "BackdropTemplate")
		b:SetHeight(22)
		b:SetFrameLevel((o:GetFrameLevel() or 1) + 8)
		b:RegisterForClicks("LeftButtonUp")
		b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.text:SetPoint("CENTER")
		b.text:SetText(cat.name)
		local measured = b.text:GetStringWidth() or 0
		if measured < 8 then measured = #cat.name * 7 end
		local w = math.ceil(measured + 20)
		if w < 64 then w = 64 end
		b:SetWidth(w)
		b:SetScript("OnClick", function() o:SelectTab(i) end)
		cat.tab = b
		tabRow = tabRow + w
	end
	if #cats > 1 then tabRow = tabRow + (#cats - 1) * tabGap end

	-- Options stay in the original column. The window is sized once, to the
	-- old width and the tallest tab, so switching tabs does not move anything.
	local width = math.max(24 + 2 * COL_W, tabRow + 24)
	local maxH = 8

	for _, cat in ipairs(cats) do
		local page = CreateFrame("Frame", nil, o)
		page:SetPoint("TOPLEFT", 12, -76)
		page:SetWidth(span)
		host = page
		local x, y = 0, 0
		for _, e in ipairs(cat.entries) do
			if type(e) == "string" then
				if SLIDERS[e] then sliderRow(SLIDERS[e], x, y) else checkbox(FEATURE_BY_KEY[e], x, y) end
				y = y - ROW
			elseif e.group then
				-- "Action bars:  [x] Hide bar art  [x] Tidy keys & slots"
				local name = host:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
				name:SetPoint("TOPLEFT", x + 4, y - 5)
				name:SetText(e.group)
				local lines = childLine(e.children, x + math.max(84, math.ceil(name:GetStringWidth()) + 14) - INDENT, y, nil, x + span - 16)
				y = y - ROW * math.max(1, lines)
			else
				checkbox(FEATURE_BY_KEY[e[1]], x, y)
				if e.button then
					local b = CreateFrame("Button", nil, host, "UIPanelButtonTemplate")
					b:SetSize(72, 20)
					b:SetPoint("TOPRIGHT", host, "TOPLEFT", x + span - 24, y - 2)
					b:SetText(e.button.label)
					b:SetScript("OnClick", e.button.click)
				end
				y = y - ROW
				y = y - ROW * childLine(e.children, x, y, e[1], x + span - 16)
				local chooserKeys = e.choosers or (e.chooser and { e.chooser })
				if chooserKeys then
					for _, key in ipairs(chooserKeys) do
						if CHOOSERS[key] then
							chooserRow(CHOOSERS[key], x + INDENT, y)
							y = y - ROW
						end
					end
				end
			end
		end
		local h = -y + 8
		if h < 8 then h = 8 end
		if h > maxH then maxH = h end
		page:SetHeight(h)
		page:Hide()
		pages[#pages + 1] = { name = cat.name, frame = page, height = h, tab = cat.tab }
	end
	host = o
	o:SetSize(width, 76 + maxH + 72)

	local tabX = 12
	for _, cat in ipairs(cats) do
		cat.tab:SetPoint("TOPLEFT", o, "TOPLEFT", tabX, -46)
		tabX = tabX + cat.tab:GetWidth() + tabGap
	end

	function o:SelectTab(index)
		if #pages == 0 then return end
		if index < 1 or index > #pages then index = 1 end
		for i, p in ipairs(pages) do
			local on = i == index
			p.frame:SetShown(on)
			paintOptTab(p.tab, on)
		end
		for _, c in ipairs(self.choosers) do
			if c.menu then c.menu:Hide() end
		end
		if ZydeForeverDB then ZydeForeverDB.optionsTab = pages[index].name end
	end

	-- Who else is running Zyde. Officers of Blackrock Breakfast Club can click it.
	o.users = CreateFrame("Button", nil, o)
	o.users:SetPoint("BOTTOMLEFT", 12, 46)
	o.users:SetSize(420, 18)
	o.users:SetFrameLevel(o:GetFrameLevel() + 20)
	o.users:RegisterForClicks("LeftButtonUp")
	o.usersLabel = o.users:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	o.usersLabel:SetPoint("LEFT", 2, 0)
	o.usersLabel:SetText("0 ZydeForever Users Currently Online")
	o.usersLabel:SetTextColor(1, 0.82, 0.2)
	local usersHl = o.users:CreateTexture(nil, "HIGHLIGHT")
	usersHl:SetAllPoints()
	usersHl:SetColorTexture(1, 0.82, 0.2, 0.12)
	o.users:SetScript("OnClick", function()
		if ns.ZydePresence and ns.ZydePresence.IsWatcher() then ns.ZydePresence.ToggleList() end
	end)
	o.users:SetScript("OnEnter", function(self)
		if not (ns.ZydePresence and ns.ZydePresence.IsWatcher()) then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("ZydeForever users", 1, 0.82, 0.2)
		GameTooltip:AddLine("Click for everyone who has checked in since you logged in.", 1, 1, 1)
		GameTooltip:Show()
	end)
	o.users:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
			if a.plain then
				if state == "on" then r, g, b = 1, 0.82, 0 else r, g, b = 0.6, 0.6, 0.6 end
			elseif state == "on" then r, g, b = 0.35, 1, 0.35 elseif state == "off" then r, g, b = 1, 0.6, 0.2 end
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
		-- Addons: green installed, orange disabled, red missing. Dungeon Journal is yellow or gray.
		local parts = {}
		for _, a in ipairs(ns.ADDONS) do
			local state = ns.addonState(a.name)
			local color
			if a.plain then
				color = state == "on" and "|cffffd100" or "|cff999999"
			else
				color = state == "on" and "|cff59ff59" or (state == "off" and "|cffff9933" or "|cffff4d4d")
			end
			parts[#parts + 1] = color .. a.title .. "|r"
		end
		self.addonLine:SetText("Addons:  " .. table.concat(parts, "  "))
		if ns.ZydePresence and self.usersLabel then
			self.usersLabel:SetText(ns.ZydePresence.Line())
			local watch = ns.ZydePresence.IsWatcher()
			self.users:EnableMouse(watch)
			self.usersLabel:SetTextColor(watch and 1 or 0.92, watch and 0.82 or 0.82, watch and 0.35 or 0.75)
		end
	end
	o:SetScript("OnShow", function(self) self:Refresh() end)
	local openTab = 1
	local want = ZydeForeverDB and ZydeForeverDB.optionsTab
	if type(want) == "string" then
		for i, p in ipairs(pages) do
			if p.name == want then openTab = i end
		end
	end
	o:SelectTab(openTab)
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

-- Every /zyde command. The options window and /zyde help both read this.
ns.ZydeCommands = {
	{ cmd = "/zyde", about = "Open the options window: turn features on or off." },
	{ cmd = "/zyde help", about = "Print this list in chat." },
	{ cmd = "/zyde unlock", about = "Unlock the player, target, party and raid frames so you can drag them." },
	{ cmd = "/zyde lock", about = "Lock those frames in place. Combat locks them too." },
	{ cmd = "/zyde resetframes", about = "Put the unit frames back in their default spots." },
	{ cmd = "/zyde resetxp", about = "Move the XP readout back to the top of the screen." },
	{ cmd = "/zyde resetquests", about = "Move the quest tracker back to its default spot." },
	{ cmd = "/zyde resetmobs", about = "Move the quest mob count back to its default spot." },
	{ cmd = "/zyde resetreminders", about = "Move the reminder icons back beside your character. Shift-drag the bar to move it. Ctrl+click it to switch between a column and a row. Alt+click it to cycle the size." },
	{ cmd = "/zyde errors", about = "Show the last Lua errors from any addon, even with error pop-ups turned off." },
	{ cmd = "/zyde petdebug", about = "Hunters: what the game reports about your pet's mood, buffs and food." },
	{ cmd = "/zyde rangedebug", about = "Hunters and warriors: what the game says about your target's range." },
	{ cmd = "/zyde light", about = "Show the Pull Traffic Light with your own mana, to drag it into place. Run it again to hide it." },
	{ cmd = "/zyde lightreset", about = "Put the Pull Traffic Light back in its first place." },
	{ cmd = "/zyde healer <name>", paste = "/zyde healer ", about = "The healer the Pull Traffic Light watches. No name: back to role, then a guess by class." },
	{ cmd = "/zyde sealdebug", about = "Paladins: why the Seal of Righteousness tile is or isn't showing." },
	{ cmd = "/zyde minimapdebug", about = "Where the minimap and its cluster are, and the saved spot." },
	{ cmd = "/zyde tentdebug", about = "What the tent reminder sees: nearby tents, a tent in your bags, Leatherworking, rested XP." },
	{ cmd = "/zyde trackdebug", about = "Hunters: what auto tracking sees around you and which tracking it would pick." },
	{ cmd = "/zyde flighttimer", about = "Flight timer: how many flight times it knows (add \"reset\" to put the panel back in the middle)." },
	{ cmd = "/zyde rotationdebug", about = "Ability highlight: what it sees (enemies, time left, health) and each spell's numbers." },
	{ cmd = "/zyde rotationdebug curves off|on", about = "Ability highlight (hunters): read hidden health and mana with status bars only, or through curves too (the default)." },
	{ cmd = "/zyde evisdebug", about = "Rogues: the damage numbers behind the Eviscerate tile for your target." },
	{ cmd = "/zyde mapnotes", about = "How many map markers you have. Alt-click the map to add one." },
	{ cmd = "/zyde mapnotes clear", about = "Remove every marker on the map you have open." },
	{ cmd = "/zyde auradebug", about = "List your target's debuffs as the game reports them." },
	{ cmd = "/zyde bossdebug", about = "Target a mob: what the game tells addons about it." },
	{ cmd = "/zyde mobsdebug", about = "List nearby nameplates and why each is or isn't counted as a quest mob." },
	{ cmd = "/zyde markdebug", about = "What the game says about your target's raid marker." },
	{ cmd = "/zyde ring", about = "Set up the radial ring: drag spells, macros and items onto it." },
	{ cmd = "/zyde wheeldebug", about = "Whether the marker wheel's macro lines ran." },
	{ cmd = "/zyde microdebug", about = "Where the micro menu buttons are, and what moved them." },
	{ cmd = "/zyde test", about = "Preview the Battle Shout, Overpower and quest item icons." },
	{ cmd = "/zyde questalert", about = "Turn the quest item nearby alert on or off." },
	{ cmd = "/zyde questicons", about = "Turn the icons over nearby objects on or off." },
	{ cmd = "/zyde rested", about = "Every character's rested XP, resting or not, and how long until it's full." },
	{ cmd = "/zyde bank", about = "Open the bank from your last visit. At a banker this opens the real bank. Your bags stay open." },
	{ cmd = "/zyde scrap", about = "Turn the full-bags scrap list on or off." },
	{ cmd = "/zyde scraptest", about = "Preview the scrap list now, even with bags not full." },
	{ cmd = "/zyde scrapreset", about = "Let items you chose to keep be suggested again." },
	{ cmd = "/zyde vendor", about = "Turn the vendor, auction and keep advice on or off." },
	{ cmd = "/zyde ammovendor", about = "Hunters: waypoint to the nearest arrow or bullet vendor." },
	{ cmd = "/zyde ammowarn <number>", paste = "/zyde ammowarn ", about = "Hunters: warn when leaving town with fewer shots than this. 0 turns it off." },
	{ cmd = "/zyde questrange <yards>", paste = "/zyde questrange ", about = "How far away quest objects are spotted." },
	{ cmd = "/zyde questheight <pixels>", paste = "/zyde questheight ", about = "The tallest the quest tracker gets before it scrolls. 0 goes to the bottom of the screen." },
	{ cmd = "/zyde quest <id>", paste = "/zyde quest ", about = "Whether that quest is flagged complete, and its name from Questie." },
	{ cmd = "/zyde questdebug", about = "Stand facing a quest object and run this to see why it is or isn't detected." },
}

ns.ToggleCommandList = function()
	local w = ns.commandWindow
	if w then
		w:SetShown(not w:IsShown())
		if w:IsShown() then w:Raise() end
		return
	end
	local PURPLE, GOLD = { 0.69, 0.35, 1 }, { 1, 0.82, 0.2 }
	local ROW = 46
	w = CreateFrame("Frame", "ZydeForeverCommands", UIParent, "BackdropTemplate")
	ns.commandWindow = w
	w:SetSize(540, 520)
	w:SetPoint("CENTER", 40, 0)
	w:SetFrameStrata("DIALOG")
	w:SetFrameLevel(50)
	w:SetMovable(true)
	w:EnableMouse(true)
	w:RegisterForDrag("LeftButton")
	w:SetScript("OnDragStart", w.StartMoving)
	w:SetScript("OnDragStop", w.StopMovingOrSizing)
	w:SetClampedToScreen(true)
	w:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	w:SetBackdropColor(0.07, 0.07, 0.08, 0.97)
	w:SetBackdropBorderColor(PURPLE[1], PURPLE[2], PURPLE[3], 0.9)
	tinsert(UISpecialFrames, "ZydeForeverCommands")
	local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 14, -12)
	title:SetText("Zyde commands")
	title:SetTextColor(PURPLE[1], PURPLE[2], PURPLE[3])
	local sub = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
	sub:SetText("Ctrl-click a line to put it in the chat box.")
	local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	local scroll = CreateFrame("ScrollFrame", nil, w, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 10, -48)
	scroll:SetPoint("BOTTOMRIGHT", -30, 14)
	local content = CreateFrame("Frame", nil, scroll)
	local list = ns.ZydeCommands
	local width = 480
	content:SetSize(width, #list * ROW)
	scroll:SetScrollChild(content)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local cur = self:GetVerticalScroll()
		local max = self:GetVerticalScrollRange()
		self:SetVerticalScroll(math.min(max, math.max(0, cur - delta * ROW)))
	end)
	local function putInChat(text)
		local edit = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
		if not edit and ChatFrame1EditBox then edit = ChatFrame1EditBox end
		if edit and edit.IsShown and edit:IsShown() then
			edit:SetText(text)
			edit:SetFocus()
		elseif ChatFrame_OpenChat then
			ChatFrame_OpenChat(text)
		end
	end
	for i, c in ipairs(list) do
		local b = CreateFrame("Button", nil, content)
		b:SetSize(width, ROW - 4)
		b:SetPoint("TOPLEFT", 4, -((i - 1) * ROW))
		b:RegisterForClicks("AnyUp")
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(PURPLE[1], PURPLE[2], PURPLE[3], 0.16)
		local cmd = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		cmd:SetPoint("TOPLEFT", 8, -4)
		cmd:SetText(c.cmd)
		cmd:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		local about = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		about:SetPoint("TOPLEFT", cmd, "BOTTOMLEFT", 0, -1)
		about:SetPoint("RIGHT", b, "RIGHT", -8, 0)
		about:SetJustifyH("LEFT")
		about:SetText(c.about)
		about:SetTextColor(0.82, 0.82, 0.82)
		b:SetScript("OnClick", function()
			if IsControlKeyDown() then putInChat(c.paste or c.cmd) end
		end)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(c.cmd, GOLD[1], GOLD[2], GOLD[3])
			GameTooltip:AddLine("Ctrl-click to put this in chat.", 1, 1, 1)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	w:Show()
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
	elseif msg == "rested" then
		if ns.RestedReport then ns.RestedReport() end
	elseif msg == "bank" then
		if ns.OpenBankWindow then ns.OpenBankWindow() end
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
	elseif msg == "ring" then
		if ns.Radial then ns.Radial.ToggleEditor() end
	elseif msg == "wheeldebug" and ns.MarkerWheel then
		ns.MarkerWheel.ToggleDebug()
	elseif msg == "rangedebug" then
		if ns.RangeDebug then ns.RangeDebug() else print("|cff66ccffZyde_Forever|r: the range check is for hunters and warriors") end
	elseif msg == "light" then
		if ns.PullLight then ns.PullLight.Test() end
	elseif msg == "lightreset" then
		if ns.PullLight then ns.PullLight.Reset() end
	elseif msg == "healer" or msg:match("^healer%s") then
		if ns.PullLight then ns.PullLight.SetHealer(msg:match("^healer%s+(.-)%s*$")) end
	elseif msg == "sealdebug" then
		if ns.SealDebug then ns.SealDebug() else print("|cff66ccffZyde_Forever|r: the seal tile is for paladins") end
	elseif msg == "minimapdebug" then
		if ns.MinimapDebug then ns.MinimapDebug() end
	elseif msg == "tentdebug" then
		if ns.TentDebug then ns.TentDebug() end
	elseif msg == "trackdebug" then
		if ns.TrackDebug then ns.TrackDebug() else print("|cff66ccffZyde_Forever|r: auto tracking is for hunters") end
	elseif msg == "flighttimer" or msg == "flighttimer reset" then
		if ns.FlightTimerCommand then ns.FlightTimerCommand(msg:match("reset")) end
	elseif msg == "rotationdebug" then
		if ns.RotationDebug then ns.RotationDebug() end
	elseif msg == "rotationdebug curves off" or msg == "rotationdebug curves on" then
		ZydeForeverDB.rotationCurves = (msg:match("on$") and nil) or false
		print("|cff66ccffZyde_Forever|r: ability highlight " .. (msg:match("on$") and "reads hidden health and mana through curves where it can" or "uses hidden status bars only (no curves)"))
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
		for _, c in ipairs(ns.ZydeCommands) do
			print(("  |cffffd200%s|r - %s"):format(c.cmd, c.about))
		end
		print("  Keybinds (Fishing, nearest quest mob, feed pet, call or revive pet, target markers (hold), world marker squares): Options > Keybindings > Zyde Forever")
	end
end
