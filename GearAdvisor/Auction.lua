-- Auction: upgrade arrows and % on auction house rows, and the "Upgrades panel" beside the window.
-- Forever's client may show either auction window, so both are handled (AHledger hooks both too):
--   classic: AuctionFrame, BrowseButton1..8 (icon BrowseButton<i>Item), AuctionFrameBrowse_Update,
--            GetAuctionItemLink("list", offset + i).
--   modern:  AuctionHouseFrame.BrowseResultsFrame.ItemList.ScrollBox rows with rowData.itemKey (the one
--            Forever uses, seen 2026-11-11). Only the item ID is known there, so random-suffix items
--            ("of the Monkey") score without their roll.
--
-- TAINT RULE (learned the hard way, 2026-11-11): never hand Blizzard's auction frames a function of
-- ours to call (ScrollBox:RegisterCallback, ItemList:SetDataProvider) and never call their list
-- methods (DirtyScrollFrame). Blizzard's code calling ours taints the rest of what it's doing, and the
-- Search button then gets blocked. We only READ (rows, C_AuctionHouse.GetBrowseResults), draw our own
-- frames, and use hooksecurefunc / HookScript, which are safe.
local _, zyde = ...
zyde.GA = zyde.GA or {}
local ns = zyde.GA

local Auction = {}
ns.Auction = Auction

local function enabled() return ns.db and ns.db.bagMarks end

local function itemName(id)
	local name = ns.safe(C_Item and C_Item.GetItemNameByID or nil, id)
	if not name then name = ns.safe((C_Item and C_Item.GetItemInfo) or GetItemInfo, id) end
	return name
end

-- "1g 23s", "23s", "4c": only the parts that aren't zero, in coin colours.
local function money(copper)
	if type(copper) ~= "number" then return "" end
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = "|cffffd700" .. g .. "g|r" end
	if s > 0 then parts[#parts + 1] = "|cffc7c7cf" .. s .. "s|r" end
	if c > 0 or #parts == 0 then parts[#parts + 1] = "|cffeda55f" .. c .. "c|r" end
	return table.concat(parts, " ")
end

-- The item's name in its quality colour, once its data has loaded.
local function coloredName(id)
	local name, _, quality = ns.safe((C_Item and C_Item.GetItemInfo) or GetItemInfo, id)
	if not name then return nil end
	local color = ITEM_QUALITY_COLORS and quality and ITEM_QUALITY_COLORS[quality]
	return color and color.hex and (color.hex .. name .. "|r") or name
end

---------------------------------------------------------------------------------------------
-- Classic auction window
---------------------------------------------------------------------------------------------
local function refreshClassic()
	if not (AuctionFrame and AuctionFrame:IsShown()) then return end
	local offset = (BrowseScrollFrame and FauxScrollFrame_GetOffset and FauxScrollFrame_GetOffset(BrowseScrollFrame)) or 0
	for i = 1, (NUM_BROWSE_TO_DISPLAY or 8) do
		local button = _G["BrowseButton" .. i]
		local icon = _G["BrowseButton" .. i .. "Item"] or button
		if icon then
			local link = enabled() and button and button:IsShown() and ns.safe(GetAuctionItemLink, "list", offset + i)
			if link then ns.Marks.apply(icon, link) else ns.Marks.hide(icon) end
		end
	end
end

---------------------------------------------------------------------------------------------
-- Modern auction window: marks on the rows, and a gold glow on the row you picked in the panel
---------------------------------------------------------------------------------------------
local selectedID   -- item picked in the panel, glowing in Blizzard's list

local function modernScrollBox()
	local browse = AuctionHouseFrame and AuctionHouseFrame.BrowseResultsFrame
	local list = browse and browse.ItemList
	return list and list.ScrollBox
end

-- Our own layer on each row (above the row's cells): arrow, % and the glow. No mouse input.
local holders = setmetatable({}, { __mode = "k" })
local function holderOf(row)
	local h = holders[row]
	if not h then
		h = CreateFrame("Frame", nil, row)
		h:SetAllPoints(row)
		h:SetFrameLevel(row:GetFrameLevel() + 10)
		local glow = h:CreateTexture(nil, "BACKGROUND")
		glow:SetAllPoints(h)
		glow:SetColorTexture(1, 0.82, 0, 0.18)
		glow:Hide()
		h.glow = glow
		holders[row] = h
	end
	return h
end

-- Rows are recycled as the list scrolls, so every pass re-reads each row's item.
local function refreshModern()
	if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return end
	local box = modernScrollBox()
	if not (box and box.ForEachFrame) then return end
	box:ForEachFrame(function(row)
		local key = row.rowData and row.rowData.itemKey
		local id = key and key.itemID
		local holder = holderOf(row)
		if ns.isSecret(id) then id = nil end
		if id and enabled() then
			-- Always show the % beside the arrow (requested 2026-11-11).
			ns.Marks.apply(holder, "item:" .. id, nil, { pctBeside = true })
		else
			ns.Marks.hide(holder)
		end
		holder.glow:SetShown(id ~= nil and id == selectedID)
	end)
end

---------------------------------------------------------------------------------------------
-- The Upgrades panel: our own list, beside the auction window, of the upgrades in the current
-- search results, best first. Blizzard's list is left exactly as it is. Clicking an entry puts its
-- name in the search box (press Search to see its listings) and makes its row glow gold.
---------------------------------------------------------------------------------------------
local panel
local ROW_H, ROW_W = 26, 264   -- panel 300 wide, the same as Zyde_Forever's auction panel above it

local function setStatus(text) if panel then panel.status:SetText(text) end end

local function rowOf(i)
	local r = panel.rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, panel.content)
	r:SetSize(ROW_W, ROW_H)
	r:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, -(i - 1) * ROW_H)
	r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(20, 20)
	r.icon:SetPoint("LEFT", 2, 0)
	r.pct = r:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	r.pct:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
	r.pct:SetWidth(44)
	r.pct:SetJustifyH("LEFT")
	r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.name:SetPoint("TOPLEFT", r.pct, "TOPRIGHT", 2, 6)
	r.name:SetPoint("RIGHT", r, "RIGHT", -2, 0)
	r.name:SetJustifyH("LEFT")
	r.name:SetWordWrap(false)
	r.price = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.price:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -1)
	r.price:SetJustifyH("LEFT")
	r:SetScript("OnEnter", function(self)
		if not self.id then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink("item:" .. self.id)
		GameTooltip:Show()
	end)
	r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	r:SetScript("OnClick", function(self) Auction.pick(self.id) end)
	panel.rows[i] = r
	return r
end

-- Puts the item's name in Blizzard's search box (you press Search) and makes its row glow.
function Auction.pick(id)
	if not id then return end
	selectedID = id
	local name = itemName(id)
	local bar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
	local sb = bar and bar.SearchBox
	if name and sb and sb.SetText then
		sb:SetText(name)
		setStatus("|cffffd100Press Search|r to see listings for " .. name .. ".")
	end
	pcall(refreshModern)
end

-- The panel shows by itself whenever the current search results hold at least one upgrade for you,
-- and hides when they hold none (user's choice, 2026-11-11: no on/off box).
local retries = 0
function Auction.refreshPanel(isRetry)
	if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
		if panel then panel:Hide() end
		return
	end
	if not isRetry then retries = 0 end
	local results = C_AuctionHouse and ns.safe(C_AuctionHouse.GetBrowseResults)
	local list, loading, total = {}, 0, 0
	if type(results) == "table" then
		total = #results
		for _, res in ipairs(results) do
			local id = res.itemKey and res.itemKey.itemID
			if id and not ns.isSecret(id) then
				local kind, r = ns.Marks.verdict("item:" .. id)
				if kind == nil then
					loading = loading + 1
				elseif kind then
					list[#list + 1] = { id = id, kind = kind, r = r, price = res.minPrice }
				end
			end
		end
	end
	table.sort(list, function(a, b) return a.r.pct > b.r.pct end)
	-- Items still loading may turn out to be upgrades: look again shortly.
	if loading > 0 and retries < 10 then
		retries = retries + 1
		C_Timer.After(0.5, function() Auction.refreshPanel(true) end)
	end
	if #list == 0 then
		if panel then panel:Hide() end
		return
	end
	if not panel then Auction.makePanel() end
	if not panel then return end
	if not panel:IsShown() then panel.place(); panel:Show() end
	for i, e in ipairs(list) do
		local row = rowOf(i)
		row.id = e.id
		row.icon:SetTexture(ns.safe(C_Item and C_Item.GetItemIconByID or GetItemIcon, e.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
		row.pct:SetText(("+%.1f%%"):format(e.r.pct))
		if e.kind == "future" then row.pct:SetTextColor(0.4, 0.8, 1) else row.pct:SetTextColor(0.1, 1, 0.1) end
		row.name:SetText(coloredName(e.id) or itemName(e.id) or ("item " .. e.id))
		row.price:SetText(money(e.price))
		row:Show()
	end
	for i = #list + 1, #panel.rows do panel.rows[i]:Hide(); panel.rows[i].id = nil end
	panel.content:SetHeight(math.max(1, #list * ROW_H))

	local more = C_AuctionHouse and C_AuctionHouse.HasFullBrowseResults and not ns.safe(C_AuctionHouse.HasFullBrowseResults)
	setStatus(("%d upgrade%s in %d results%s%s"):format(#list, #list == 1 and "" or "s", total,
		loading > 0 and (" (" .. loading .. " still loading)") or "",
		more and ".\nScroll Blizzard's list to load more results." or "."))
end

local function makePanel()
	if panel or not AuctionHouseFrame then return end
	local ok, made = pcall(CreateFrame, "Frame", "GearAdvisorAuctionPanel", UIParent, "BackdropTemplate")
	local p = ok and made or CreateFrame("Frame", "GearAdvisorAuctionPanel", UIParent)
	p:SetWidth(ROW_W + 36)
	p:SetFrameStrata(AuctionHouseFrame:GetFrameStrata())
	-- Under Zyde_Forever's auction panel (ZydeForeverAuction, top right of the window, its height
	-- changes with its contents) when that's showing; else at the window's top right.
	local function place()
		p:ClearAllPoints()
		local zyde = _G.ZydeForeverAuction
		local zb, ab = zyde and zyde:GetBottom(), AuctionHouseFrame:GetBottom()
		local top
		if zyde and zyde:IsShown() and zb and ab and zb - ab < 150 then
			-- Zyde's panel is nearly as tall as the window: sit beside it instead of under it.
			p:SetPoint("TOPLEFT", zyde, "TOPRIGHT", 4, 0)
			top = zyde:GetTop()
		elseif zyde and zyde:IsShown() then
			p:SetPoint("TOPLEFT", zyde, "BOTTOMLEFT", 0, -4)
			top = zb and (zb - 4)
		else
			p:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, 0)
			top = AuctionHouseFrame:GetTop()
		end
		-- Down to the bottom of the auction window.
		p:SetHeight((top and ab) and math.max(120, top - ab) or 400)
	end
	place()
	p.place = place
	local zyde = _G.ZydeForeverAuction
	if zyde then
		zyde:HookScript("OnShow", place)
		zyde:HookScript("OnHide", place)
		zyde:HookScript("OnSizeChanged", place)
	end
	if not p.SetBackdrop then
		-- No backdrop template on this client: a plain dark background instead.
		local bg = p:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(p)
		bg:SetColorTexture(0.05, 0.05, 0.05, 0.95)
	end
	if p.SetBackdrop then
		p:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		p:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
		p:SetBackdropBorderColor(0.6, 0.6, 0.6)
	end
	p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	p.title:SetPoint("TOPLEFT", 12, -10)
	p.title:SetText("GearAdvisor: upgrades here")
	p.status = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	p.status:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -4)
	p.status:SetPoint("RIGHT", -12, 0)
	p.status:SetJustifyH("LEFT")
	local scroll = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 10, -58)
	scroll:SetPoint("BOTTOMRIGHT", -30, 28)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(ROW_W, 1)
	scroll:SetScrollChild(content)
	p.content, p.rows = content, {}
	p.hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	p.hint:SetPoint("BOTTOMLEFT", 12, 10)
	p.hint:SetPoint("RIGHT", -12, 0)
	p.hint:SetJustifyH("LEFT")
	p.hint:SetText("Click an item to search for it.")
	p:Hide()
	AuctionHouseFrame:HookScript("OnHide", function() p:Hide() end)
	panel = p
end
Auction.makePanel = makePanel

---------------------------------------------------------------------------------------------
-- Hooks: both windows load on demand, so hook when they appear.
---------------------------------------------------------------------------------------------
local ticker
local function startTicker()
	if ticker or not C_Timer.NewTicker then return end
	ticker = C_Timer.NewTicker(0.1, function()
		if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
			ticker:Cancel()
			ticker = nil
			return
		end
		pcall(refreshModern)
	end)
end

local hooked = {}
local function hook()
	if not hooked.classic and AuctionFrameBrowse_Update then
		hooked.classic = true
		hooksecurefunc("AuctionFrameBrowse_Update", function() pcall(refreshClassic) end)
	end
	if not hooked.modern and AuctionHouseFrame then
		hooked.modern = true
		AuctionHouseFrame:HookScript("OnShow", function()
			startTicker()
			-- A moment later, so Zyde's panel has shown (or not) and sized itself first.
			C_Timer.After(0.1, function() pcall(Auction.refreshPanel) end)
		end)
		AuctionHouseFrame:HookScript("OnHide", function() if panel then panel:Hide() end end)
		if AuctionHouseFrame:IsShown() then startTicker() end
	end
end

-- /ga ah: what the auction house parts look like, for a bug report.
function Auction.report()
	ns.print("Auction house:")
	print("  AuctionHouseFrame " .. tostring(AuctionHouseFrame ~= nil) .. ", classic AuctionFrame " .. tostring(AuctionFrame ~= nil))
	print("  panel: " .. (panel and ("made, shown " .. tostring(panel:IsVisible())) or "not made") .. "; rows list found " .. tostring(modernScrollBox() ~= nil))
	local results = C_AuctionHouse and ns.safe(C_AuctionHouse.GetBrowseResults)
	print("  GetBrowseResults: " .. (type(results) == "table" and (#results .. " results") or "not available"))
end

ns.Marks.addRefresher(function()
	pcall(refreshClassic)
	pcall(refreshModern)
end)

-- New results, and gear/level/spec changes, refresh the panel (our own event frame: taint-safe).
local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "ADDON_LOADED", "AUCTION_HOUSE_SHOW",
	"AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" }) do
	pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", function(_, event)
	pcall(hook)
	if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
		C_Timer.After(0.1, function() pcall(Auction.refreshPanel) end)
	end
end)
ns.onChange(function() C_Timer.After(0.1, function() pcall(Auction.refreshPanel) end) end)
