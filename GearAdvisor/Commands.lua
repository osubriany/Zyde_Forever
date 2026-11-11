-- Commands: /ga (or /gearadvisor). Phase a: score, summary, bags, spec, target, probe.
local _, zyde = ...
zyde.GA = zyde.GA or {}
local ns = zyde.GA

local C = ns.Config
local Score = ns.Score

local function fmt(n, places)
	if type(n) ~= "number" then return tostring(n) end
	return ("%." .. (places or 1) .. "f"):format(n)
end

-- All return values of fn(...) as one string, "-" for none, "(error)" if it failed.
local function show(fn, ...)
	if type(fn) ~= "function" then return "(no such function)" end
	local r = ns.pack(pcall(fn, ...))
	if not r[1] then return "(error)" end
	local out = {}
	for i = 2, r.n do
		local v = r[i]
		out[#out + 1] = ns.isSecret(v) and "(secret)" or tostring(v)
	end
	return #out > 0 and table.concat(out, ", ") or "-"
end

-- An item link (or "item:123" string) out of command text, or nil.
local function linkFrom(text)
	if type(text) ~= "string" then return nil end
	local link = text:match("|c[^|]*|Hitem:.-|h.-|h|r") or text:match("|Hitem:.-|h.-|h")
	if link then return link end
	local id = text:match("^%s*(%d+)%s*$") or text:match("item:(%d+)")
	if id then return "item:" .. id end
end

local function hoveredLink()
	if GameTooltip and GameTooltip:IsShown() and GameTooltip.GetItem then
		local _, link = GameTooltip:GetItem()
		if not ns.isSecret(link) then return link end
	end
end

-- One line describing a compare result.
function ns.describe(r)
	local notes = (r.notes and #r.notes > 0) and (" – " .. table.concat(r.notes, ", ")) or ""
	local vs = (r.vs and #r.vs > 0) and table.concat(r.vs, " + ")
		or ("nothing (" .. (Score.SLOT_NAMES[r.slot] or "?") .. ")")
	if r.kind == "upgrade" then
		return ("|cff00ff00Upgrade +%s%%|r over %s%s"):format(fmt(r.pct), vs, notes)
	elseif r.kind == "downgrade" then
		return ("|cffff4040Downgrade %s%%|r vs %s%s"):format(fmt(r.pct), vs, notes)
	elseif r.kind == "same" then
		return ("|cffaaaaaaAbout the same (%s%s%%)|r vs %s%s"):format(r.pct >= 0 and "+" or "", fmt(r.pct), vs, notes)
	elseif r.kind == "future" then
		return ("|cff66ccffFuture upgrade +%s%%|r over %s%s"):format(fmt(r.pct), vs, notes)
	elseif r.kind == "too early" then
		return "|cffaaaaaaCan't use yet|r" .. notes
	elseif r.kind == "equipped" then
		return "You're wearing this."
	elseif r.kind == "unusable" then
		return "|cffaaaaaaYou can't use this|r" .. notes
	elseif r.kind == "n/a" then
		return "|cffaaaaaaNot compared|r" .. notes
	elseif r.kind == "loading" then
		return "Item data still loading – try again in a moment."
	elseif r.kind == "unsupported" then
		return "Not available" .. notes
	end
	return "Not a piece of gear."
end

local function scoreItem(link)
	local r = Score.compare(link)
	local name = (r.info and r.info.link) or link
	ns.print(name .. ((r.info and r.info.itemID) and (" (item " .. r.info.itemID .. ")") or ""))
	print("  " .. ns.describe(r))
	if not r.parts then return end
	local ctx = ns.Player.context()
	for _, p in ipairs(r.parts) do
		print(("    %s %s -> %s"):format(p.label, fmt(p.amount, 2), fmt(p.value)))
	end
	if r.newHit ~= 0 or r.oldHit ~= 0 then
		print(("    Hit %s%% (old item %s%%): your hit %s%% -> %s%%, cap %s%% -> %s"):format(
			fmt(r.newHit, 2), fmt(r.oldHit, 2), fmt(r.hitBefore, 2), fmt(r.hitAfter, 2), fmt(r.hitCap), fmt(r.hitDelta)))
	end
	if r.info and r.info.speed then print("    Weapon speed " .. fmt(r.info.speed, 2)) end
	if r.setDelta and r.setDelta ~= 0 then print("    Set bonus change " .. fmt(r.setDelta)) end
	print(("  New item %s, replaced %s, change %s of kit %s (all in %s-equivalents)"):format(
		fmt(r.newLinear + Score.hitValue(r.hitBefore - r.oldHit, r.hitAfter, ctx)),
		fmt(r.oldLinear + Score.hitValue(r.hitBefore - r.oldHit, r.hitBefore, ctx)),
		fmt(r.delta), fmt(ctx.kitScore), ctx.profile.hitKind == "ranged" and "RAP" or "AP"))
end

local function summary()
	local ctx = ns.Player.context()
	if not ctx.profile then ns.print(ctx.reason) return end
	ns.print(("%s, level %d (%s)"):format(ctx.profile.label, ctx.level, ctx.profileSource))
	print(("  Hit %s%% from %s (gear %s%%), cap %s%% vs a target +%d levels (%s)"):format(
		fmt(ctx.hitHave, 2), ctx.hitSource, fmt(ctx.gearHit, 2), fmt(ctx.hitCap), ctx.targetGap, ctx.targetSetting))
	print(("  %s hit rating = 1%% (%s); %s crit rating = 1%% (%s)"):format(
		fmt(ctx.hitPer, 2), ctx.hitPerSource, fmt(ctx.critPer, 2), ctx.critPerSource))
	print("  Kit score " .. fmt(ctx.kitScore))
	for _, slot in ipairs(ns.Player.SLOTS) do
		local info = ctx.equipped[slot]
		if info then
			local _, lin, hit = Score.parts(info, slot, ctx)
			print(("    %s: %s %s%s"):format(Score.SLOT_NAMES[slot], info.link, fmt(lin),
				hit ~= 0 and (" + " .. fmt(hit, 2) .. "% hit") or ""))
		end
	end
	local keys = {}
	for k, v in pairs(ctx.weights) do if v ~= 0 then keys[#keys + 1] = k end end
	table.sort(keys)
	local w = {}
	for _, k in ipairs(keys) do w[#w + 1] = k .. " " .. fmt(ctx.weights[k], 2) end
	print("  Weights at your level: " .. table.concat(w, ", "))
	if ctx.loading then print("  Some equipped items are still loading; run it again.") end
end

local function bags()
	local list, loading = {}, 0
	local numBags = NUM_BAG_SLOTS or 4
	for bag = 0, numBags do
		local slots = ns.safe(C_Container.GetContainerNumSlots, bag) or 0
		for slot = 1, slots do
			local link = ns.safe(C_Container.GetContainerItemLink, bag, slot)
			if link and ns.Stats.isGear(link) then
				local r = Score.compare(link)
				if r.kind == "loading" then
					loading = loading + 1
				elseif r.kind == "upgrade" then
					list[#list + 1] = r
				end
			end
		end
	end
	table.sort(list, function(a, b) return a.pct > b.pct end)
	ns.print(#list == 0 and "No upgrades in your bags." or ("Upgrades in your bags (" .. #list .. "):"))
	for i = 1, math.min(#list, 15) do
		print("  " .. list[i].info.link .. ": " .. ns.describe(list[i]))
	end
	if loading > 0 then print(("  %d items still loading; run it again."):format(loading)) end
end

-- /ga loot: what loot data GearAdvisor has.
local function lootStatus()
	local s = ns.Loot.status()
	ns.print("Loot data:")
	print(("  Bundled (cMaNGOS + sightings): %d dungeons, %d bosses, %d items"):format(s.bundled.dungeons, s.bundled.bosses, s.bundled.items))
	print("  AtlasLoot: " .. tostring(s.atlas) .. (s.modules and (" (" .. table.concat(s.modules, ", ") .. ")") or ""))
	print(("  %d dungeons/raids, %d items; %d drops recorded by GearAdvisor"):format(s.dungeons, s.items, s.recorded))
	local b = ns.Loot.lastBoss()
	if b then
		print(("  Last boss kill seen: %s in %s, %d s ago"):format(tostring(b.name), tostring(b.dungeon), GetTime() - b.time))
	else
		print("  No boss kill seen this session (the recorder starts noting drops after one).")
	end
	if s.dungeons == 0 then
		print("  Install a Forever AtlasLoot (\"AtlasLoot Classic Forever\" or \"AtlasLootClassic Continued\"), or run dungeons to record drops.")
	end
end

-- /ga dungeon [name]: the upgrades a dungeon drops for you, best first. No name: list dungeons.
local function dungeonCmd(name)
	if name == "" then
		local names = {}
		for _, d in ipairs(ns.Loot.dungeons()) do
			names[#names + 1] = d.name .. (d.minLevel and (" " .. d.minLevel .. "-" .. (d.maxLevel or "?")) or "")
		end
		ns.print(#names > 0 and ("Dungeons: " .. table.concat(names, ", ")) or "No loot data yet (see /ga loot).")
		return
	end
	local list, loading, d = ns.Loot.upgradesIn(name)
	if not list then ns.print("No dungeon called '" .. name .. "'. /ga dungeon lists them.") return end
	ns.print(("%s: %d upgrades for you"):format(d.name, #list))
	for i = 1, math.min(#list, 12) do
		local e = list[i]
		local it = e.boss.items[e.result.info.itemID]
		local src = (it and (it.atlas or it.bundled)) and "" or " (seen drop)"
		print(("  %s – %s%s: %s"):format(e.result.info.link, e.boss.name, src, ns.describe(e.result)))
	end
	if loading > 0 then print(("  %d items still loading; run it again in a moment."):format(loading)) end
end

local SPEC_WORDS ={ arms = "WARRIOR_ARMS", bm = "HUNTER_BM", beastmastery = "HUNTER_BM" }

local function setSpec(arg)
	arg = (arg or ""):lower()
	if arg == "" then
		local ctx = ns.Player.context()
		ns.print("Profile: " .. tostring(ctx.profileKey) .. " (" .. tostring(ctx.profileSource or ctx.reason) .. "). Use /ga spec arms, bm or auto.")
		return
	end
	if arg == "auto" then
		ns.db.specOverride = nil
	elseif SPEC_WORDS[arg] then
		ns.db.specOverride = SPEC_WORDS[arg]
	else
		ns.print("Unknown spec '" .. arg .. "'. Use arms, bm or auto.")
		return
	end
	ns.changed("spec")
	setSpec("")
end

local function setTarget(arg)
	arg = (arg or ""):lower()
	if arg == "auto" or ns.Player.TARGETS[arg] then
		ns.db.target = arg
		ns.changed("target")
	elseif arg ~= "" then
		ns.print("Use /ga target auto, same, dungeon or raid.")
		return
	end
	local ctx = ns.Player.context()
	ns.print(("Hit cap against a target +%s levels (%s): %s%%"):format(tostring(ctx.targetGap), tostring(ctx.targetSetting), fmt(ctx.hitCap)))
end

-- /ga probe: the step-1 checks in one go. Prints to chat AND saves to GearAdvisorDB.probe, which
-- the game writes to WTF\...\SavedVariables\GearAdvisor.lua on /reload or logout.
local function probe()
	local out = {}
	local function line(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
		local s = table.concat(parts, " ")
		out[#out + 1] = s
		print("  " .. s)
	end
	ns.print("Probe (also saved for Claude to read after /reload):")
	line("T1 build:", show(GetBuildInfo))
	line("T7 class/level:", show(UnitClass, "player"), "/", show(UnitLevel, "player"))
	line("T7 GetSpecialization:", GetSpecialization and show(GetSpecialization) or "(none)")
	local tabs = ns.safe(GetNumTalentTabs) or 0
	for i = 1, tabs do line("T7 talent tab " .. i .. ":", show(GetTalentTabInfo, i)) end
	local spec, how = ns.Player.detectSpec(select(2, UnitClass("player")))
	line("T7 detected spec:", tostring(spec), "via", tostring(how))
	for _, n in ipairs({ "CR_HIT_MELEE", "CR_HIT_RANGED", "CR_HIT_SPELL", "CR_CRIT_MELEE", "CR_CRIT_RANGED",
		"CR_EXPERTISE", "CR_WEAPON_SKILL", "CR_WEAPON_SKILL_MAINHAND", "CR_WEAPON_SKILL_RANGED" }) do
		local cr = _G[n]
		if type(cr) == "number" then
			line("T4", n, "=", cr, "have", show(GetCombatRating, cr), "rating =", show(GetCombatRatingBonus, cr),
				"% ; 100 rating =", show(GetCombatRatingBonusForCombatRatingValue, cr, 100), "%")
		else
			line("T4", n, "not defined")
		end
	end
	line("T5 GetExpertise:", GetExpertise and show(GetExpertise) or "(none)")
	line("T5 names:", tostring(ITEM_MOD_EXPERTISE_RATING_SHORT), "|", tostring(ITEM_MOD_WEAPON_SKILL_RATING_SHORT))
	line("T6 weapon skill (main base, bonus, off base, bonus):", show(UnitAttackBothHands, "player"))
	line("T8 GetHitModifier:", GetHitModifier and show(GetHitModifier) or "(none)",
		"crit:", show(GetCritChance), "ranged crit:", show(GetRangedCritChance))
	line("T8 AP:", show(UnitAttackPower, "player"), "RAP:", show(UnitRangedAttackPower, "player"))
	ns.Player.invalidate()
	local ctx = ns.Player.context()
	if ctx.profile then
		line("GA hit: have", fmt(ctx.hitHave, 2), "from", ctx.hitSource, "| gear", fmt(ctx.gearHit, 2),
			"| per 1%:", fmt(ctx.hitPer, 2), ctx.hitPerSource, "| crit per 1%:", fmt(ctx.critPer, 2), ctx.critPerSource)
	end
	for _, slot in ipairs({ 16, 17, 18 }) do
		local link = ns.safe(GetInventoryItemLink, "player", slot)
		if link then
			local raw = ns.safe((C_Item and C_Item.GetItemStats) or GetItemStats, link) or {}
			local keys = {}
			for k, v in pairs(raw) do keys[#keys + 1] = tostring(k) .. "=" .. tostring(v) end
			table.sort(keys)
			local info = ns.Stats.read(link)
			line("T3 slot " .. slot .. ":", link, table.concat(keys, " "), "| speed", info and tostring(info.speed) or "?")
		end
	end
	local unknown = {}
	for k, n in pairs(ns.Stats.unknownSeen) do unknown[#unknown + 1] = k .. " x" .. n end
	table.sort(unknown)
	line("Unknown stat keys seen:", #unknown > 0 and table.concat(unknown, ", ") or "none")
	ns.db.probe = { time = date and date("%Y-%m-%d %H:%M") or "?", lines = out }
end

local function help()
	ns.print("commands:")
	print("  /ga or /ga plan – open the planner window (My Gear, Dungeons, By Slot)")
	print("  /ga minimap – show or hide the minimap button")
	print("  /ga score – score the item under your mouse (or Shift-click an item after /ga score)")
	print("  /ga summary – your profile, hit, hit cap and every equipped item's value")
	print("  /ga bags – list upgrades in your bags")
	print("  /ga loot – what loot data GearAdvisor has")
	print("  /ga dungeon [name] – upgrades a dungeon drops for you (no name: list dungeons)")
	print("  /ga spec [arms | bm | auto] – show or set the profile")
	print("  /ga target [auto | same | dungeon | raid] – which target the hit cap is for")
	print("  /ga tooltip – turn the tooltip lines on or off")
	print("  /ga quest – turn the quest reward marks on or off")
	print("  /ga arrows – turn the upgrade arrows (bags, vendor, auction house) on or off")
	print("  /ga rolls – turn the Need/Greed roll advice on or off")
	print("  /ga toast – turn the upgrade popup on or off")
	print("  /ga probe – game checks for setting up the addon (saved for Claude on /reload)")
end

local function toggle(key, label)
	ns.db[key] = not ns.db[key]
	ns.print(label .. (ns.db[key] and " on." or " off."))
	ns.changed(key)
end

SLASH_GEARADVISOR1 = "/ga"
SLASH_GEARADVISOR2 = "/gearadvisor"
SlashCmdList.GEARADVISOR = function(msg)
	msg = msg or ""
	local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
	cmd = (cmd or ""):lower()
	local ok, err = pcall(function()
		if cmd == "" or cmd == "plan" then ns.Window.toggle()
		elseif cmd == "help" then help()
		elseif cmd == "minimap" then
			ns.Window.setMinimap(ns.db.minimap == false)
			ns.print("Minimap button " .. (ns.db.minimap and "shown." or "hidden."))
		elseif cmd == "score" then
			local link = linkFrom(rest) or hoveredLink()
			if link then scoreItem(link) else summary() end
		elseif cmd == "summary" then summary()
		elseif cmd == "bags" then bags()
		elseif cmd == "spec" then setSpec(rest)
		elseif cmd == "target" then setTarget(rest)
		elseif cmd == "probe" then probe()
		elseif cmd == "tooltip" then toggle("tooltip", "Tooltip lines")
		elseif cmd == "quest" then toggle("questMarks", "Quest reward marks")
		elseif cmd == "arrows" then toggle("bagMarks", "Upgrade arrows")
		elseif cmd == "loot" then lootStatus()
		elseif cmd == "ah" then ns.Auction.report()
		elseif cmd == "dungeon" then dungeonCmd(rest)
		elseif cmd == "rolls" then toggle("rollMarks", "Loot roll advice")
		elseif cmd == "toast" then toggle("toast", "Upgrade popup")
		elseif cmd == "popup" then
			-- Test: show the popup for a Shift-clicked or hovered item, whatever its verdict.
			local link = linkFrom(rest) or hoveredLink()
			local r = link and Score.compare(link)
			if r and r.pct and r.info then ns.Toast.show(r.info.link, r)
			else ns.print("Shift-click a piece of gear after /ga popup (or hover one) to test the popup.") end
		else
			local link = linkFrom(msg)
			if link then scoreItem(link) else help() end
		end
	end)
	if not ok then ns.print("|cffff4040error:|r " .. tostring(err)) end
end
