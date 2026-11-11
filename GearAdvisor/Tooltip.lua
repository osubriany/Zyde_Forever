-- Tooltip (phase b): adds GearAdvisor's verdict to every item tooltip (bags, vendor, auction
-- house, loot, links in chat). Hold Shift for the stat-by-stat breakdown.
local _, zyde = ...
zyde.GA = zyde.GA or {}
local ns = zyde.GA

local Tooltip = {}
ns.Tooltip = Tooltip

local GREY = { 0.6, 0.6, 0.6 }

local function fmt(n, places) return ("%." .. (places or 1) .. "f"):format(n) end

-- The item link a tooltip is showing, or nil.
local function linkOf(tooltip, data)
	if tooltip and tooltip.GetItem then
		local ok, _, link = pcall(tooltip.GetItem, tooltip)
		if ok and link and not ns.isSecret(link) then return link end
	end
	local link = type(data) == "table" and data.hyperlink
	if type(link) == "string" and not ns.isSecret(link) then return link end
end

-- The Shift breakdown: biggest value parts first, then hit.
local function addBreakdown(tooltip, r)
	if not r.parts then return end
	local parts = {}
	for _, p in ipairs(r.parts) do parts[#parts + 1] = p end
	table.sort(parts, function(a, b) return math.abs(a.value) > math.abs(b.value) end)
	for i = 1, math.min(#parts, 8) do
		local p = parts[i]
		tooltip:AddDoubleLine("  " .. p.label .. " " .. fmt(p.amount, 1), fmt(p.value), GREY[1], GREY[2], GREY[3], GREY[1], GREY[2], GREY[3])
	end
	if r.newHit ~= 0 or r.oldHit ~= 0 then
		tooltip:AddDoubleLine(("  Hit %s%% -> %s%% (cap %s%%)"):format(fmt(r.hitBefore), fmt(r.hitAfter), fmt(r.hitCap)),
			fmt(r.hitDelta), GREY[1], GREY[2], GREY[3], GREY[1], GREY[2], GREY[3])
	end
	if r.setDelta and r.setDelta ~= 0 then
		tooltip:AddDoubleLine("  Set bonus", fmt(r.setDelta), GREY[1], GREY[2], GREY[3], GREY[1], GREY[2], GREY[3])
	end
	tooltip:AddDoubleLine(("  New %s vs worn %s"):format(fmt(r.newLinear), fmt(r.oldLinear)), "",
		GREY[1], GREY[2], GREY[3])
end

function Tooltip.add(tooltip, data)
	if not (ns.db and ns.db.tooltip) then return end
	if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
	local link = linkOf(tooltip, data)
	if not link or not ns.Stats.isGear(link) then return end
	local ok, r = pcall(ns.Score.compare, link)
	if not ok or type(r) ~= "table" then return end
	local text, cr, cg, cb = ns.headline(r)
	if not text then return end
	local notes = (r.notes and #r.notes > 0) and table.concat(r.notes, ", ") or nil
	tooltip:AddLine(" ")
	tooltip:AddLine(text, cr, cg, cb, true)
	if notes then tooltip:AddLine(notes, GREY[1], GREY[2], GREY[3], true) end
	-- For an upgrade, what it usually costs on your auction house (AHledger, credit required).
	if (r.kind == "upgrade" or r.kind == "future") and AHledgerAPI and AHledgerAPI.GetMedian then
		local ok2, median = pcall(AHledgerAPI.GetMedian, link)
		if ok2 and type(median) == "number" and median > 0 then
			local money = (GetCoinTextureString and GetCoinTextureString(median))
				or ("%dg %ds %dc"):format(math.floor(median / 10000), math.floor(median / 100) % 100, median % 100)
			tooltip:AddLine("Usually " .. money .. " on the auction house", 0.9, 0.8, 0.5)
			tooltip:AddLine(AHledgerAPI.CREDIT or "Prices from AHledger", 0.45, 0.45, 0.45)
		end
	end
	-- Where it drops (AtlasLoot and/or our own recorded drops), for upgrades.
	if (r.kind == "upgrade" or r.kind == "future") and r.info and ns.Loot then
		local okS, sources = pcall(ns.Loot.sourcesOf, r.info.itemID)
		if okS and sources then
			local parts = {}
			for i = 1, math.min(#sources, 2) do
				parts[#parts + 1] = sources[i].boss.name .. " (" .. sources[i].dungeon.name .. ")"
			end
			tooltip:AddLine("Drops from " .. table.concat(parts, ", ") .. (#sources > 2 and ", ..." or ""), 0.8, 0.8, 0.5, true)
		end
	end
	if IsShiftKeyDown() then
		addBreakdown(tooltip, r)
	elseif r.parts then
		tooltip:AddLine("Hold Shift for details", 0.45, 0.45, 0.45)
	end
	tooltip:Show()   -- resize to fit the new lines
end

-- Hook every item tooltip: the modern way if the client has it, else the old OnTooltipSetItem.
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		pcall(Tooltip.add, tooltip, data)
	end)
else
	for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
		if tt and tt.HookScript then
			pcall(tt.HookScript, tt, "OnTooltipSetItem", function(self) pcall(Tooltip.add, self) end)
		end
	end
end

-- Pressing or releasing Shift redraws the tooltip so the breakdown appears or disappears.
local f = CreateFrame("Frame")
f:RegisterEvent("MODIFIER_STATE_CHANGED")
f:SetScript("OnEvent", function(_, _, key)
	if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
	if GameTooltip:IsShown() and GameTooltip.RefreshData then
		pcall(GameTooltip.RefreshData, GameTooltip)
	end
end)
