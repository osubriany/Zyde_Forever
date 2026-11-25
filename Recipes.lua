-- Recipes: beside an open profession window, the recipes (patterns, plans, formulas...) for that
-- profession you haven't learned yet, where each comes from (vendor and zone, quest, drop) and,
-- with AHledger, what one costs on the auction house.
--   * The list comes from Questie's item data (QuestieDB): every "recipe" item of the profession
--     and the spell it teaches. Known ones are left out (the spell is known, or the window lists
--     a recipe of that name). Recipes only a trainer teaches are not items, so they don't show.
--   * Click a row with a vendor for a map waypoint to that vendor; Shift-click to link it in chat.
--   * The "Unlearned" button on the window shows or hides the panel (remembered).
local ADDON, ns = ...

local function on() return ns.F and ns.F("recipes") end
local function db() ZydeForeverDB = ZydeForeverDB or {} return ZydeForeverDB end
local function safe(f, ...) if not f then return nil end local ok, a, b = pcall(f, ...) if ok then return a, b end end
local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local getItemIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon

-- Recipe item subclass (item class 9) per profession, by the window's English name.
local SUBCLASS = {
	["Leatherworking"] = 1, ["Tailoring"] = 2, ["Engineering"] = 3, ["Blacksmithing"] = 4, ["Cooking"] = 5,
	["Alchemy"] = 6, ["First Aid"] = 7, ["Enchanting"] = 8, ["Fishing"] = 9, ["Jewelcrafting"] = 10,
}
local RECIPE_CLASS = 9
local P = "|cff66ccffZyde_Forever|r: "

---------------------------------------------------------------------------
-- The open profession window, its name, and the recipes it already lists
---------------------------------------------------------------------------
local function openWindow()
	if ProfessionsFrame and ProfessionsFrame:IsShown() and C_TradeSkillUI then
		local info = safe(C_TradeSkillUI.GetBaseProfessionInfo)
		return ProfessionsFrame, info and info.professionName
	end
	if TradeSkillFrame and TradeSkillFrame:IsShown() then
		return TradeSkillFrame, GetTradeSkillLine and (GetTradeSkillLine())
	end
	if CraftFrame and CraftFrame:IsShown() then
		local name = (GetCraftDisplaySkillLine and GetCraftDisplaySkillLine()) or (GetCraftName and GetCraftName())
		return CraftFrame, name
	end
	return nil
end

-- "Pattern: Red Linen Robe" -> "red linen robe" (and the same for a recipe's own name).
local function bare(name)
	name = tostring(name or ""):gsub("^[^:]+:%s*", "")
	return name:lower()
end

local function knownNames()
	local known = {}
	if ProfessionsFrame and ProfessionsFrame:IsShown() and C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
		for _, id in ipairs(safe(C_TradeSkillUI.GetAllRecipeIDs) or {}) do
			local info = safe(C_TradeSkillUI.GetRecipeInfo, id)
			if info and info.learned and info.name then known[bare(info.name)] = true end
		end
	elseif TradeSkillFrame and TradeSkillFrame:IsShown() and GetNumTradeSkills then
		for i = 1, (GetNumTradeSkills() or 0) do
			local name, kind = GetTradeSkillInfo(i)
			if name and kind ~= "header" then known[bare(name)] = true end
		end
	elseif CraftFrame and CraftFrame:IsShown() and GetNumCrafts then
		for i = 1, (GetNumCrafts() or 0) do
			local name, _, kind = GetCraftInfo(i)
			if name and kind ~= "header" then known[bare(name)] = true end
		end
	end
	return known
end

---------------------------------------------------------------------------
-- Every recipe item of a profession, from Questie's item data (built once, a little per frame)
---------------------------------------------------------------------------
local catalog = {}     -- [subclass] = list of { id, name, spell }
local building = {}    -- [subclass] = true while being built

local function IDB() return _G.LibQuestieDB and _G.LibQuestieDB.Item end

local buildError -- why the last build failed (shown in the panel), or nil

local failed = {} -- [subclass] = true after a build error (no retry until /reload)

local function buildCatalog(sub, done)
	if catalog[sub] then done() return end
	if building[sub] or failed[sub] then return end
	local Item = IDB()
	if not (Item and Item.GetAllIds) then
		-- Questie's item data isn't there (yet): say so, and try again in a moment
		buildError = "Questie's item data isn't loaded yet"
		C_Timer.After(2, done)
		return
	end
	local ids = safe(Item.GetAllIds) or {}
	building[sub] = true
	buildError = nil
	local list, i = {}, 1
	local step
	local function runStep()
		local stop = math.min(#ids, i + 1500)
		for k = i, stop do
			local id = ids[k]
			if safe(Item.class, id) == RECIPE_CLASS and safe(Item.subClass, id) == sub then
				local name = safe(Item.name, id)
				list[#list + 1] = { id = id, name = type(name) == "string" and name or ("Item " .. id),
					spell = safe(Item.teachesSpell, id) }
			end
		end
		i = stop + 1
		if i <= #ids then C_Timer.After(0, function() step() end) return end -- (step: the guarded one below)
		table.sort(list, function(a, b) return a.name < b.name end)
		catalog[sub], building[sub] = list, nil
		done()
	end
	-- Any error stops the build: never leave it marked as running (that left the panel on
	-- "Reading Questie's item data..." for good), and show what went wrong.
	step = function()
		local ok, err = pcall(runStep)
		if not ok then
			building[sub], failed[sub] = nil, true
			buildError = tostring(err)
			done()
		end
	end
	step()
end

---------------------------------------------------------------------------
-- Where a recipe comes from (one line), and a vendor's map spot for a waypoint
---------------------------------------------------------------------------
local myFaction = (UnitFactionGroup("player") == "Horde") and "H" or "A"

local function npcZone(npcId)
	local Npc = _G.LibQuestieDB and _G.LibQuestieDB.Npc
	local spawns = Npc and safe(Npc.spawns, npcId)
	for areaId, pts in pairs(type(spawns) == "table" and spawns or {}) do
		local zone = C_Map.GetAreaInfo and C_Map.GetAreaInfo(areaId)
		return zone, areaId, pts and pts[1]
	end
end

local function npcName(npcId)
	local Npc = _G.LibQuestieDB and _G.LibQuestieDB.Npc
	return Npc and safe(Npc.name, npcId) or ("NPC " .. tostring(npcId))
end

local sourceCache = {}
local function sourceOf(id)
	if sourceCache[id] then return sourceCache[id] end
	local L = _G.LibQuestieDB
	local Item, Npc, Quest = L and L.Item, L and L.Npc, L and L.Quest
	local s = { text = "|cff888888source unknown|r" }
	local vendors = safe(Item and Item.vendors, id)
	if type(vendors) == "table" and #vendors > 0 then
		-- a vendor of your faction first
		local pick
		for _, v in ipairs(vendors) do
			local f = safe(Npc and Npc.friendlyToFaction, v)
			if f == nil or f == "AH" or f == myFaction then pick = v break end
		end
		local enemyOnly = not pick
		pick = pick or vendors[1]
		local zone, areaId, pt = npcZone(pick)
		s.text = "|cff66dd66Vendor|r " .. npcName(pick) .. (zone and (" · " .. zone) or "")
			.. (#vendors > 1 and string.format(" |cff888888(+%d)|r", #vendors - 1) or "")
			.. (enemyOnly and " |cffff6666(other faction)|r" or "")
		s.vendor, s.areaId, s.pt = pick, areaId, pt
	else
		local quests = safe(Item and Item.questRewards, id)
		local drops = safe(Item and Item.npcDrops, id)
		local objects = safe(Item and Item.objectDrops, id)
		if type(quests) == "table" and #quests > 0 then
			s.text = "|cffffd100Quest|r " .. (safe(Quest and Quest.name, quests[1]) or ("#" .. quests[1]))
		elseif type(drops) == "table" and #drops > 0 then
			local zone = npcZone(drops[1])
			s.text = "|cffff9933Drop|r " .. npcName(drops[1]) .. (zone and (" · " .. zone) or "")
				.. (#drops > 1 and string.format(" |cff888888(+%d)|r", #drops - 1) or "")
		elseif type(objects) == "table" and #objects > 0 then
			s.text = "|cffff9933Found|r in a container or object"
		end
	end
	sourceCache[id] = s
	return s
end

local function money(c)
	if not c or c <= 0 then return "" end
	local g, s = math.floor(c / 10000), math.floor(c / 100) % 100
	if g > 0 then return string.format("%d|cffffd100g|r %d|cffc0c0c0s|r", g, s) end
	return string.format("%d|cffc0c0c0s|r", math.max(1, s))
end

local function ahPrice(id)
	local api = _G.AHledgerAPI
	local p = api and api.GetPrice and safe(api.GetPrice, id)
	return p and (p.minBuyout or p.median) or nil
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------
local ROW_H, W = 34, 330
local panel, rows, toggle = nil, {}, nil

local function setWaypoint(s)
	if not (s and s.areaId and s.pt) then return false end
	local ZDB = QuestieLoader and safe(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
	local map = ZDB and safe(ZDB.GetUiMapIdByAreaId, ZDB, s.areaId)
	if not (map and UiMapPoint and C_Map.SetUserWaypoint) then return false end
	local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(map, s.pt[1] / 100, s.pt[2] / 100))
	if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
	return ok
end

local function row(i)
	if rows[i] then return rows[i] end
	local r = CreateFrame("Button", nil, panel.content)
	r:SetSize(W - 30, ROW_H)
	r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
	r:RegisterForClicks("LeftButtonUp")
	r.hl = r:CreateTexture(nil, "HIGHLIGHT")
	r.hl:SetAllPoints()
	r.hl:SetColorTexture(1, 1, 1, 0.07)
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(24, 24)
	r.icon:SetPoint("LEFT", 4, 0)
	r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, 0)
	r.name:SetPoint("RIGHT", -70, 0)
	r.name:SetJustifyH("LEFT")
	r.name:SetWordWrap(false)
	r.src = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	r.src:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
	r.src:SetPoint("RIGHT", -4, 0)
	r.src:SetJustifyH("LEFT")
	r.src:SetWordWrap(false)
	r.price = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.price:SetPoint("TOPRIGHT", -4, -2)
	r.price:SetJustifyH("RIGHT")
	r:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		pcall(GameTooltip.SetItemByID, GameTooltip, self.id)
		if self.source and self.source.vendor then GameTooltip:AddLine("Click: waypoint to the vendor", 0.6, 0.8, 1) end
		GameTooltip:AddLine("Shift-click: link in chat", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	r:SetScript("OnClick", function(self)
		if IsShiftKeyDown() then
			local link = select(2, safe(getItemInfo, self.id))
			if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
			return
		end
		if setWaypoint(self.source) then print(P .. "waypoint set to " .. npcName(self.source.vendor)) end
	end)
	rows[i] = r
	return r
end

local function buildPanel()
	panel = CreateFrame("Frame", "ZydeForeverRecipes", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	panel:SetSize(W, 400)
	panel:SetFrameStrata("HIGH")
	if panel.SetBackdrop then
		panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		panel:SetBackdropColor(0.05, 0.05, 0.07, 0.94)
		panel:SetBackdropBorderColor(1, 1, 1, 0.15)
	end
	panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	panel.title:SetPoint("TOPLEFT", 10, -8)
	panel.note = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	panel.note:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -3)
	panel.note:SetPoint("RIGHT", -10, 0)
	panel.note:SetJustifyH("LEFT")
	local sf = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
	sf:SetPoint("TOPLEFT", 6, -42)
	sf:SetPoint("BOTTOMRIGHT", -26, 8)
	panel.content = CreateFrame("Frame", nil, sf)
	panel.content:SetSize(W - 30, 10)
	sf:SetScrollChild(panel.content)
	panel:Hide()
end

local function shown() return db().recipesShown ~= false end

local function refresh()
	local win, prof = openWindow()
	if toggle then toggle:SetShown(on() and win ~= nil and SUBCLASS[prof or ""] ~= nil) end
	if not (on() and win and shown()) then if panel then panel:Hide() end return end
	local sub = SUBCLASS[prof or ""]
	if not sub then if panel then panel:Hide() end return end
	if not panel then buildPanel() end
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", win, "TOPRIGHT", 2, 0)
	panel:SetHeight(math.max(300, win:GetHeight()))
	panel.title:SetText("Unlearned " .. prof .. " recipes")
	panel:Show()
	if not catalog[sub] then
		panel.note:SetText(buildError and ("|cffff6666Couldn't read Questie's item data:|r " .. buildError)
			or "Reading Questie's item data...")
		for _, r in ipairs(rows) do r:Hide() end
		buildCatalog(sub, refresh)
		return
	end
	local known = knownNames()
	local n = 0
	for _, rec in ipairs(catalog[sub]) do
		local learned = (rec.spell and IsPlayerSpell and safe(IsPlayerSpell, rec.spell)) or known[bare(rec.name)]
		if not learned then
			n = n + 1
			local r = row(n)
			r.id, r.source = rec.id, sourceOf(rec.id)
			r.icon:SetTexture((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(rec.id)) or safe(getItemIcon, rec.id) or 134939)
			local quality = getItemInfo and select(3, getItemInfo(rec.id))
			local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
			r.name:SetText((c and c.hex or "|cffffffff") .. rec.name .. "|r")
			r.src:SetText(r.source.text)
			local price = ahPrice(rec.id)
			r.price:SetText(price and money(price) or "")
			r:Show()
		end
	end
	for i = n + 1, #rows do rows[i]:Hide() end
	panel.content:SetHeight(math.max(10, n * ROW_H))
	panel.note:SetText(n > 0 and string.format("%d to learn · trainer-only recipes aren't listed%s", n,
		_G.AHledgerAPI and "" or " · AHledger adds auction prices")
		or "You know every recipe item Questie lists for this profession.")
end

-- The "Unlearned" button on the profession window.
local function buildToggle()
	toggle = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
	toggle:SetSize(90, 20)
	toggle:SetFrameStrata("HIGH")
	toggle:SetText("Unlearned")
	toggle:SetScript("OnClick", function()
		db().recipesShown = not shown()
		refresh()
	end)
	toggle:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Unlearned recipes")
		GameTooltip:AddLine("Show or hide the recipes you haven't learned yet, where to get them and their auction price.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
	toggle:Hide()
end

local function placeToggle()
	local win = openWindow()
	if not (toggle and win) then return end
	toggle:ClearAllPoints()
	toggle:SetPoint("BOTTOMRIGHT", win, "TOPRIGHT", -24, 2)
end

local queued = false
local function refreshSoon()
	if queued then return end
	queued = true
	C_Timer.After(0.2, function()
		queued = false
		placeToggle()
		pcall(refresh)
	end)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE",
	"CRAFT_SHOW", "CRAFT_CLOSE", "CRAFT_UPDATE", "NEW_RECIPE_LEARNED", "LEARNED_SPELL_IN_TAB", "PLAYER_LOGIN" }) do
	pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then buildToggle() return end
	if event == "TRADE_SKILL_CLOSE" or event == "CRAFT_CLOSE" then
		C_Timer.After(0, function() if not openWindow() then if panel then panel:Hide() end if toggle then toggle:Hide() end end end)
		return
	end
	refreshSoon()
end)

if ns.OnFeatureChanged then ns.OnFeatureChanged(function(key) if key == "recipes" then refreshSoon() end end) end
