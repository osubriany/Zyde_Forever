-- Shopping: when the auction house is open, a small list beside it of the quest items your plan
-- buys there (Stops.lua buy steps): how many, how many you already have, and about what they cost.
-- Shift-click a row to put the item in the auction house search (the game's own shift-click).
local ADDON, zyde = ...
zyde.LP = zyde.LP or {}
local ns = zyde.LP

local Shop = {}
ns.Shopping = Shop

local ROW_H, W = 22, 250
local panel, rows = nil, {}
local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local getItemIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local getItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount

local function ahFrame()
	if AuctionHouseFrame and AuctionHouseFrame:IsShown() then return AuctionHouseFrame end
	if AuctionFrame and AuctionFrame:IsShown() then return AuctionFrame end
	return nil
end

local function money(c)
	if not c or c <= 0 then return "" end
	local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
	if g > 0 then return string.format("%d|cffffd100g|r %d|cffc0c0c0s|r", g, s) end
	if s > 0 then return string.format("%d|cffc0c0c0s|r", s) end
	return string.format("%d|cffeda55fc|r", cp)
end

-- What the plan buys at the auction house, one line per item: { id, name, need, each }.
local function wanted()
	local out, byId = {}, {}
	for _, s in ipairs(ns.plan and ns.plan.stops or {}) do
		if s.buyAH and s.buyItem then
			local w = byId[s.buyItem]
			if not w then
				w = { id = s.buyItem, name = s.buyName or ("Item " .. s.buyItem), need = 0, each = s.buyEach,
					quest = s.questName }
				byId[s.buyItem] = w
				out[#out + 1] = w
			end
			w.need = w.need + (s.buyCount or 1)
		end
	end
	return out
end

local function row(i)
	if rows[i] then return rows[i] end
	local r = CreateFrame("Button", nil, panel)
	r:SetSize(W - 16, ROW_H)
	r:SetPoint("TOPLEFT", 8, -28 - (i - 1) * ROW_H)
	r:RegisterForClicks("LeftButtonUp")
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(18, 18)
	r.icon:SetPoint("LEFT")
	r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0)
	r.name:SetPoint("RIGHT", -60, 0)
	r.name:SetJustifyH("LEFT")
	r.name:SetWordWrap(false)
	r.price = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.price:SetPoint("RIGHT")
	r:SetScript("OnEnter", function(self)
		if not self.id then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(self.id)
		GameTooltip:AddLine("For: " .. (self.quest or "your plan"), 0.6, 0.8, 1)
		GameTooltip:AddLine("Shift-click to search for it", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	r:SetScript("OnClick", function(self)
		-- the game's own shift-click: with the auction house open it fills in the search
		if self.link and IsModifiedClick and HandleModifiedItemClick then HandleModifiedItemClick(self.link) end
	end)
	rows[i] = r
	return r
end

local function build()
	panel = CreateFrame("Frame", "LevelPlannerShopping", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	panel:SetSize(W, 60)
	panel:SetFrameStrata("HIGH")
	if panel.SetBackdrop then
		panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		panel:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
		panel:SetBackdropBorderColor(1, 1, 1, 0.2)
	end
	panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	panel.title:SetPoint("TOPLEFT", 8, -8)
	panel.title:SetText("LevelPlanner shopping list")
	panel:Hide()
end

function Shop.Refresh()
	local ah = ahFrame()
	if not ah or not ns.active or ns.cfg.shoppingList == false then
		if panel then panel:Hide() end
		return
	end
	local list = wanted()
	if #list == 0 then if panel then panel:Hide() end return end
	if not panel then build() end
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", ah, "TOPRIGHT", 4, 0)
	for i, w in ipairs(list) do
		local r = row(i)
		local have = getItemCount and getItemCount(w.id) or 0
		local _, link, quality
		if getItemInfo then _, link, quality = getItemInfo(w.id) end
		r.id, r.link, r.quest = w.id, link, w.quest
		r.icon:SetTexture((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(w.id)) or (getItemIcon and getItemIcon(w.id)) or 134400)
		local done = have >= w.need
		local c = done and "|cff59ff8c" or ((quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] and ITEM_QUALITY_COLORS[quality].hex) or "|cffffffff")
		r.name:SetText(string.format("%s%s|r  |cff999999%d/%d|r", c, w.name, math.min(have, w.need), w.need))
		r.price:SetText(done and "|cff59ff8cgot it|r" or ("~" .. money((w.each or 0) * (w.need - have))))
		r:Show()
	end
	for i = #list + 1, #rows do rows[i]:Hide() end
	panel:SetHeight(36 + #list * ROW_H)
	panel:Show()
end

---------------------------------------------------------------------------
-- Auto-buy: open a vendor that sells something your plan buys from a vendor, and it's bought —
-- only what's still missing, only planned items, never more than ahBuyMaxGold in all, and not
-- while you hold the skip key (the same one auto turn-in uses).
---------------------------------------------------------------------------
local function skipHeld()
	local key = ns.cfg.autoQuestSkipKey or "SHIFT"
	return (key == "SHIFT" and IsShiftKeyDown()) or (key == "CTRL" and IsControlKeyDown())
		or (key == "ALT" and IsAltKeyDown())
end

function Shop.AutoBuy()
	if not ns.active or ns.cfg.autoBuy == false or skipHeld() then return end
	if not (GetMerchantNumItems and BuyMerchantItem) then return end
	-- what the plan buys from vendors: [itemId] = { name, need }
	local want, any = {}, false
	for _, s in ipairs(ns.plan and ns.plan.stops or {}) do
		if s.buyVendor and s.buyItem then
			local w = want[s.buyItem] or { name = s.buyName, need = 0 }
			w.need = w.need + (s.buyCount or 1)
			want[s.buyItem], any = w, true
		end
	end
	if not any then return end
	local budget = math.min((ns.cfg.ahBuyMaxGold or 5) * 10000, GetMoney and GetMoney() or 0)
	local spent, bought = 0, {}
	for i = 1, (GetMerchantNumItems() or 0) do
		local link = GetMerchantItemLink(i)
		local id = link and tonumber(link:match("item:(%d+)"))
		local w = id and want[id]
		if w then
			local _, _, price, perBuy, available = GetMerchantItemInfo(i)
			perBuy = (perBuy and perBuy > 0) and perBuy or 1
			local missing = w.need - ((getItemCount and getItemCount(id)) or 0)
			if missing > 0 and price and price > 0 then
				local buys = math.ceil(missing / perBuy)
				if available and available >= 0 then buys = math.min(buys, available) end
				buys = math.min(buys, math.floor((budget - spent) / price))
				if buys > 0 then
					-- one call per purchase for items sold in stacks; one call for the rest
					if perBuy > 1 then
						for _ = 1, buys do BuyMerchantItem(i, 1) end
					else
						BuyMerchantItem(i, buys)
					end
					spent = spent + buys * price
					bought[#bought + 1] = string.format("%d %s", buys * perBuy, w.name or link)
				end
			end
		end
	end
	if #bought > 0 then
		ns.print(string.format("bought %s for your plan (%s). Hold %s at a vendor to skip.",
			table.concat(bought, ", "), money(spent), (ns.cfg.autoQuestSkipKey or "SHIFT"):lower()))
	end
end

function Shop.Init()
	local f = CreateFrame("Frame")
	for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "BAG_UPDATE_DELAYED", "MERCHANT_SHOW" }) do
		pcall(f.RegisterEvent, f, e)
	end
	f:SetScript("OnEvent", function(_, event)
		if event == "MERCHANT_SHOW" then
			-- (a moment later: the vendor's list fills in after the window opens)
			C_Timer.After(0.3, function() ns.safe(Shop.AutoBuy) end)
			return
		end
		if event == "AUCTION_HOUSE_CLOSED" then
			if panel then panel:Hide() end
		else
			-- (a moment later: the auction house window has to be shown first)
			C_Timer.After(0.1, function() ns.safe(Shop.Refresh) end)
		end
	end)
end
