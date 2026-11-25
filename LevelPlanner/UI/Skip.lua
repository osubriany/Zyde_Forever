-- Skip: quests (or whole dungeon runs, or grind spots) you've told the planner to leave out.
-- Right-click a step > "Skip ...". Saved per character until you bring it back from
-- "..." > Skipped quests (or /lp reset clears them all). A skipped quest in your log stays in your log:
-- the planner just ignores it.
local ADDON, zyde = ...
zyde.LP = zyde.LP or {}
local ns = zyde.LP

local S = {}
ns.Skip = S

-- ns.skipped is the table every planner check reads: [id] = name (true from older code is fine too)
function S.Load()
	if not ns.char then return end
	ns.char.skipped = ns.char.skipped or {}
	-- (anything /lp next skipped before the saved list loaded)
	for id, v in pairs(ns.skipped or {}) do
		if ns.char.skipped[id] == nil then ns.char.skipped[id] = v end
	end
	ns.skipped = ns.char.skipped
end

local function nameOf(id, v)
	if type(v) == "string" then return v end
	local n = type(id) == "number" and ns.QuestSource and ns.QuestSource.Quest and ns.QuestSource.Quest(id, "name")
	return n or tostring(id)
end

local function replan()
	local m = _G.LevelPlannerPinMenu -- (its "Skipped quests (3)" count)
	if m and m.skipRefresh then m.skipRefresh() end
	if ns.RequestReplan then ns.RequestReplan(true) end
end

function S.Add(id, name, dungeon)
	if id == nil then return end
	ns.skipped[id] = name or true
	ns.print(string.format("skipping %s\"%s\". Bring it back from \"...\" > Skipped quests. Re-planning...",
		dungeon and "the dungeon run " or "", name or tostring(id)))
	replan()
end

function S.Remove(id)
	if ns.skipped[id] == nil then return end
	local name = nameOf(id, ns.skipped[id])
	ns.skipped[id] = nil
	ns.print(string.format("\"%s\" is back in the plan. Re-planning...", name))
	replan()
end

function S.Clear()
	if next(ns.skipped) == nil then return end
	wipe(ns.skipped)
	ns.print("skipped quests cleared. Re-planning...")
	replan()
end

-- sorted { id, name } list
function S.Items()
	local out = {}
	for id, v in pairs(ns.skipped) do out[#out + 1] = { id = id, name = nameOf(id, v) } end
	table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
	return out
end

-- What right-clicking a plan stop can skip: { id, name, dungeon } or nil
-- (real quests, dungeon runs and grind spots; not the planner's own errands like "set your hearth")
function S.TargetOf(stop)
	local q = stop.quest
	if q and q.isDungeon then return { id = q.id, name = q.name, dungeon = true } end
	if stop.kind == "dungeon" then return stop.questId and { id = stop.questId, name = stop.questName, dungeon = true } end
	if q and q.isExtra and stop.kind ~= "grind" then return nil end
	local id = (q and q.id) or stop.questId
	if id == nil then return nil end
	return { id = id, name = (q and q.name) or stop.questName or tostring(id) }
end

----------------------------------------------------------------------------------------
-- Look: the same dark panels as the "..." menu
----------------------------------------------------------------------------------------
local ROW_H = 18

local function panel(name, parent)
	local f = CreateFrame("Frame", name, parent or UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	if f.SetBackdrop then
		f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		f:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
		f:SetBackdropBorderColor(1, 1, 1, 0.2)
	end
	f:Hide()
	return f
end

local function rowButton(parent, w)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, ROW_H)
	b.hl = b:CreateTexture(nil, "HIGHLIGHT")
	b.hl:SetAllPoints()
	b.hl:SetColorTexture(1, 1, 1, 0.1)
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.text:SetPoint("LEFT", 8, 0)
	b.text:SetPoint("RIGHT", -8, 0)
	b.text:SetJustifyH("LEFT")
	b.text:SetWordWrap(false)
	return b
end

----------------------------------------------------------------------------------------
-- Right-click a step: "Skip quest: X" (one line per quest when a row merges several)
----------------------------------------------------------------------------------------
local rowMenu
function S.ShowRowMenu(anchor, targets)
	if not (targets and #targets > 0) then return end
	if not rowMenu then
		rowMenu = panel("LevelPlannerSkipMenu")
		rowMenu.head = rowMenu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		rowMenu.head:SetPoint("TOPLEFT", 8, -6)
		rowMenu.head:SetText("Leave out of the plan")
		rowMenu.rows = {}
		tinsert(UISpecialFrames, "LevelPlannerSkipMenu") -- Escape closes it
		-- closes on a click anywhere else, or 3 s after the mouse leaves it
		rowMenu:SetScript("OnUpdate", function(self, elapsed)
			if self:IsMouseOver() then self.away = 0 return end
			if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then
				self.closedAt = GetTime() -- (that click's release may be on the same step: see below)
				self:Hide()
				return
			end
			self.away = (self.away or 0) + elapsed
			if self.away > 3 then self:Hide() end
		end)
	end
	-- right-clicking the same step again closes it (the press already did; the release mustn't reopen it)
	if rowMenu.anchor == anchor and (rowMenu:IsShown() or GetTime() - (rowMenu.closedAt or -10) < 1) then
		rowMenu:Hide()
		rowMenu.closedAt = nil
		return
	end
	rowMenu.anchor = anchor
	rowMenu.away = 0
	local W = 260
	for i, t in ipairs(targets) do
		local b = rowMenu.rows[i]
		if not b then
			b = rowButton(rowMenu, W - 8)
			b:SetPoint("TOPLEFT", 4, -22 - (i - 1) * ROW_H)
			b:SetScript("OnClick", function(self)
				rowMenu:Hide()
				if self.target then S.Add(self.target.id, self.target.name, self.target.dungeon) end
			end)
			rowMenu.rows[i] = b
		end
		b.target = t
		b.text:SetText((t.dungeon and "|cffff9933Skip dungeon run|r: " or "|cffff6666Skip quest|r: ") .. t.name)
		b:Show()
	end
	for i = #targets + 1, #rowMenu.rows do rowMenu.rows[i]:Hide() rowMenu.rows[i].target = nil end
	if not rowMenu.cancel then
		rowMenu.cancel = rowButton(rowMenu, W - 8)
		rowMenu.cancel.text:SetText("|cff999999Cancel|r")
		rowMenu.cancel:SetScript("OnClick", function() rowMenu:Hide() end)
	end
	rowMenu.cancel:ClearAllPoints()
	rowMenu.cancel:SetPoint("TOPLEFT", 4, -22 - #targets * ROW_H - 2)
	rowMenu:SetSize(W, 22 + (#targets + 1) * ROW_H + 8)
	rowMenu:ClearAllPoints()
	rowMenu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 20, 2)
	rowMenu:Show()
end

----------------------------------------------------------------------------------------
-- "..." > Skipped quests: click one to bring it back
----------------------------------------------------------------------------------------
local ROWS, LIST_W = 15, 240
local list
function S.ToggleList(anchor)
	if list and list:IsShown() then list:Hide() return end
	if not list then
		list = panel("LevelPlannerSkipList", anchor:GetParent())
		list.title = list:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		list.title:SetPoint("TOPLEFT", 8, -6)
		list.empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		list.empty:SetPoint("TOPLEFT", 12, -24)
		list.empty:SetText("Nothing skipped. Right-click a step to skip it.")
		list.rows = {}
		for i = 1, ROWS do
			local b = rowButton(list, LIST_W - 8)
			b:SetPoint("TOPLEFT", 4, -22 - (i - 1) * ROW_H)
			b:SetScript("OnClick", function(self)
				if self.item then S.Remove(self.item.id) list.refresh() end
			end)
			b:SetScript("OnEnter", function(self)
				if not self.item then return end
				GameTooltip:SetOwner(self, "ANCHOR_LEFT")
				GameTooltip:AddLine(self.item.name)
				GameTooltip:AddLine("Click: put it back in the plan.", 0.6, 0.8, 1, true)
				GameTooltip:Show()
			end)
			b:SetScript("OnLeave", function() GameTooltip:Hide() end)
			list.rows[i] = b
		end
		list.clear = rowButton(list, LIST_W - 8)
		list.clear.text:SetText("|cffff6666Clear all|r")
		list.clear:SetScript("OnClick", function() S.Clear() list.refresh() end)
		list:EnableMouseWheel(true)
		list:SetScript("OnMouseWheel", function(self, delta)
			local max = math.max(0, #self.items - ROWS)
			self.offset = math.min(max, math.max(0, self.offset - delta * 3))
			self.fill()
		end)
		list.fill = function()
			local n = math.min(ROWS, #list.items)
			for i, b in ipairs(list.rows) do
				local it = list.items[list.offset + i]
				b.item = it
				if it then b.text:SetText(it.name) b:Show() else b:Hide() end
			end
			local more = #list.items > ROWS and string.format("  |cff999999%d-%d of %d (scroll)|r", list.offset + 1,
				math.min(#list.items, list.offset + ROWS), #list.items) or ""
			list.title:SetText("Skipped quests" .. more)
			list.empty:SetShown(#list.items == 0)
			local h = 22 + math.max(1, n) * ROW_H
			if #list.items > 0 then
				list.clear:ClearAllPoints()
				list.clear:SetPoint("TOPLEFT", 4, -h - 4)
				list.clear:Show()
				h = h + 4 + ROW_H
			else
				list.clear:Hide()
			end
			list:SetSize(LIST_W, h + 6)
		end
		list.refresh = function()
			list.items = S.Items()
			list.offset = math.min(list.offset or 0, math.max(0, #list.items - ROWS))
			list.fill()
		end
	end
	list.offset = 0
	list.refresh()
	list:ClearAllPoints()
	list:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -6, 6)
	list:Show()
end

function S.HideList()
	if list then list:Hide() end
end
