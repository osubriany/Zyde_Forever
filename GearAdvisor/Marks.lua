-- Marks (phase c): a small arrow on item buttons that hold an upgrade for you. Green = upgrade you
-- can wear now, blue = future upgrade (wearable within a few levels). Hold Shift to see the % instead.
-- Drawn on Blizzard's bags, the vendor window and Baganator's bags; the auction house uses the same
-- marks (Auction.lua).
-- Game facts used (seen working on Forever by SimGearForever, 2026-10-20..11-05):
--   ContainerFrameContainer.ContainerFrames / ContainerFrameCombinedBags / ContainerFrame1..13, buttons
--   via EnumerateValidItems or .Items, button:GetBagID() + :GetID(); hooking the bag frames' Update
--   broke the combined bag, so we use OnShow + BAG_UPDATE_DELAYED instead.
--   MerchantItem1..10ItemButton with GetMerchantItemLink(index), 10 per page.
--   Baganator.API.RegisterCornerWidget(label, id, onUpdate, onInit, defaultPosition).
local _, zyde = ...
zyde.GA = zyde.GA or {}
local ns = zyde.GA

local Marks = {}
ns.Marks = Marks

local ARROW_ATLAS = "bags-greenarrow"
local FALLBACK = "Interface\\RAIDFRAME\\ReadyCheck-Ready"
local COLORS = { upgrade = { 0.1, 1, 0.1 }, future = { 0.4, 0.8, 1 } }

local marks = setmetatable({}, { __mode = "k" })   -- button -> { arrow, text }

local function inCombat() return InCombatLockdown and InCombatLockdown() end

local function enabled() return ns.db and ns.db.bagMarks end

-- An arrow texture on `parent`, green or blue.
local function newArrow(parent)
	local t = parent:CreateTexture(nil, "OVERLAY", nil, 7)
	t:SetSize(16, 16)
	local ok, res = pcall(t.SetAtlas, t, ARROW_ATLAS)
	if not ok or res == false then t:SetTexture(FALLBACK) end
	return t
end

local function paint(arrow, kind)
	if kind == "future" then
		arrow:SetDesaturated(true)
		arrow:SetVertexColor(0.4, 0.8, 1)
	else
		arrow:SetDesaturated(false)
		arrow:SetVertexColor(1, 1, 1)
	end
end

local function markOf(button, anchor)
	local m = marks[button]
	if m then return m end
	local arrow = newArrow(button)
	arrow:SetPoint("TOPLEFT", anchor or button, "TOPLEFT", 1, -1)
	local text = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	text:SetPoint("TOPLEFT", anchor or button, "TOPLEFT", 2, -2)
	m = { arrow = arrow, text = text }
	marks[button] = m
	return m
end

function Marks.hide(button)
	local m = marks[button]
	if m then m.arrow:Hide(); m.text:Hide() end
end

-- The verdict worth marking for a link: "upgrade" or "future" plus the result, false for no mark,
-- nil while the item is loading.
-- Cached per link until gear, level, spec or settings change (the auction house asks 10 times a second).
local verdicts = {}
ns.onChange(function() verdicts = {} end)

function Marks.verdict(link)
	if not link or ns.isSecret(link) then return false end
	local c = verdicts[link]
	if c then return c[1], c[2] end
	if not ns.Stats.isGear(link) then return false end
	local ok, r = pcall(ns.Score.compare, link)
	if not ok or type(r) ~= "table" then return false end
	if r.kind == "loading" then return nil end   -- not cached: ask again
	local kind = (r.kind == "upgrade" or r.kind == "future") and r.kind or false
	verdicts[link] = { kind, r }
	return kind, r
end

-- Shows or hides the mark on one button for `link`. anchor: where the arrow sits (default the button).
-- opts.pctBeside: always show the % to the right of the arrow (auction house rows).
function Marks.apply(button, link, anchor, opts)
	if not enabled() then Marks.hide(button) return end
	local kind, r = Marks.verdict(link)
	if not kind then Marks.hide(button) return kind end
	local m = markOf(button, anchor)
	if opts and opts.pctBeside then
		if m.mode ~= "beside" then
			m.text:ClearAllPoints()
			m.text:SetPoint("LEFT", m.arrow, "RIGHT", 1, 0)
			m.mode = "beside"
		end
		paint(m.arrow, kind)
		m.arrow:Show()
		m.text:SetText(("+%.1f%%"):format(r.pct))
		m.text:SetTextColor(COLORS[kind][1], COLORS[kind][2], COLORS[kind][3])
		m.text:Show()
		return kind
	end
	if IsShiftKeyDown() then
		m.arrow:Hide()
		m.text:SetText(("+%d%%"):format(math.floor(r.pct + 0.5)))
		m.text:SetTextColor(COLORS[kind][1], COLORS[kind][2], COLORS[kind][3])
		m.text:Show()
	else
		m.text:Hide()
		paint(m.arrow, kind)
		m.arrow:Show()
	end
	return kind
end

---------------------------------------------------------------------------------------------
-- Blizzard bags
---------------------------------------------------------------------------------------------
local containerLink = C_Container and C_Container.GetContainerItemLink or GetContainerItemLink

local function containerFrames()
	local out, seen = {}, {}
	local function add(f) if f and not seen[f] then seen[f] = true; out[#out + 1] = f end end
	local box = _G.ContainerFrameContainer
	for _, f in ipairs(box and box.ContainerFrames or {}) do add(f) end
	add(_G.ContainerFrameCombinedBags)
	for i = 1, 13 do add(_G["ContainerFrame" .. i]) end
	return out
end

local function buttonsOf(frame)
	local out = {}
	if frame.EnumerateValidItems then
		pcall(function() for _, b in frame:EnumerateValidItems() do out[#out + 1] = b end end)
	end
	if #out == 0 and type(frame.Items) == "table" then
		for _, b in pairs(frame.Items) do if type(b) == "table" and b.GetID then out[#out + 1] = b end end
	end
	if #out == 0 then
		local name = frame.GetName and frame:GetName()
		for j = 1, 36 do
			local b = name and _G[name .. "Item" .. j]
			if b then out[#out + 1] = b end
		end
	end
	return out
end

local function bagSlot(button)
	local slot = button.GetID and button:GetID()
	local bag = button.GetBagID and button:GetBagID()
	if bag == nil and button.GetParent then
		local p = button:GetParent()
		bag = p and p.GetID and p:GetID()
	end
	return bag, slot
end

local loadingSeen = false

local function refreshBags()
	for _, frame in ipairs(containerFrames()) do
		if frame:IsShown() then
			for _, button in ipairs(buttonsOf(frame)) do
				local bag, slot = bagSlot(button)
				local link = bag and slot and ns.safe(containerLink, bag, slot)
				if link then
					if Marks.apply(button, link, button.icon or button.Icon) == nil then loadingSeen = true end
				else
					Marks.hide(button)
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------
-- Vendor window (Merchant tab only: the Buyback tab reuses the same buttons)
---------------------------------------------------------------------------------------------
local function refreshMerchant()
	local perPage = MERCHANT_ITEMS_PER_PAGE or 10
	local open = MerchantFrame and MerchantFrame:IsShown() and (MerchantFrame.selectedTab or 1) == 1
	local page = (MerchantFrame and MerchantFrame.page) or 1
	for i = 1, perPage do
		local button = _G["MerchantItem" .. i .. "ItemButton"]
		if button then
			local link = open and ns.safe(GetMerchantItemLink, (page - 1) * perPage + i)
			if link then
				if Marks.apply(button, link) == nil then loadingSeen = true end
			else
				Marks.hide(button)
			end
		end
	end
end

---------------------------------------------------------------------------------------------
-- Baganator: our arrow as a corner widget (players can move it in Baganator's Icons settings)
---------------------------------------------------------------------------------------------
local BAGANATOR_ID, BAGANATOR_LABEL = "gearadvisor", "GearAdvisor"
local baganatorTexts = setmetatable({}, { __mode = "k" })   -- arrow -> its % text
local baganatorRegistered = false

local function baganatorAPI()
	local b = _G.Baganator
	local api = type(b) == "table" and b.API
	if type(api) == "table" and type(api.RegisterCornerWidget) == "function" then return api end
end

local function baganatorInit(button)
	local arrow = newArrow(button)
	local text = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	text:SetPoint("CENTER", arrow, "CENTER", 0, 0)
	text:Hide()
	baganatorTexts[arrow] = text
	return arrow
end

local function baganatorUpdate(arrow, details)
	local text = baganatorTexts[arrow]
	if text then text:Hide() end
	if not enabled() or inCombat() then return false end
	local kind, r = Marks.verdict(details and details.itemLink)
	if kind == nil then loadingSeen = true; return nil end
	if not kind then return false end
	paint(arrow, kind)
	if IsShiftKeyDown() and text then
		arrow:SetAlpha(0)
		text:SetText(("+%d%%"):format(math.floor(r.pct + 0.5)))
		text:SetTextColor(COLORS[kind][1], COLORS[kind][2], COLORS[kind][3])
		text:Show()
	else
		arrow:SetAlpha(1)
	end
	return true
end

local function setupBaganator()
	local api = baganatorAPI()
	if not api or baganatorRegistered then return end
	baganatorRegistered = true
	pcall(api.RegisterCornerWidget, BAGANATOR_LABEL, BAGANATOR_ID, baganatorUpdate, baganatorInit,
		{ corner = "top_right", priority = 2 })
end

local function refreshBaganator()
	local api = baganatorAPI()
	if baganatorRegistered and api and api.RequestItemButtonsRefresh then pcall(api.RequestItemButtonsRefresh) end
end

---------------------------------------------------------------------------------------------
-- Refreshing
---------------------------------------------------------------------------------------------
local refreshers = {}   -- extra refreshers (Auction.lua adds one)
function Marks.addRefresher(fn) refreshers[#refreshers + 1] = fn end

local waitingForCombat = false
local retries = 0
local function run(isRetry)
	if inCombat() then waitingForCombat = true return end
	if not isRetry then retries = 0 end
	loadingSeen = false
	pcall(refreshBags)
	pcall(refreshMerchant)
	refreshBaganator()
	for _, fn in ipairs(refreshers) do pcall(fn) end
	-- Some items were still loading: look again shortly (up to 10 times, ~5 seconds).
	if loadingSeen and retries < 10 then
		retries = retries + 1
		C_Timer.After(0.5, function() run(true) end)
	end
end
function Marks.refresh() run(false) end

local queued = false
function Marks.refreshSoon()
	if queued then return end
	queued = true
	C_Timer.After(0.05, function() queued = false; Marks.refresh() end)
end

local hookedFrames = setmetatable({}, { __mode = "k" })
local function hookFrames()
	for _, frame in ipairs(containerFrames()) do
		if not hookedFrames[frame] then
			hookedFrames[frame] = true
			frame:HookScript("OnShow", function()
				Marks.refreshSoon()
				C_Timer.After(0.3, Marks.refreshSoon)   -- the combined bag fills its buttons late
			end)
		end
	end
end

local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "ADDON_LOADED", "BAG_UPDATE_DELAYED", "MERCHANT_SHOW", "MERCHANT_UPDATE",
	"MODIFIER_STATE_CHANGED", "PLAYER_REGEN_ENABLED" }) do
	pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == "Baganator" then setupBaganator() end
		return
	end
	if event == "MODIFIER_STATE_CHANGED" and arg1 ~= "LSHIFT" and arg1 ~= "RSHIFT" then return end
	if event == "PLAYER_REGEN_ENABLED" then
		if not waitingForCombat then return end
		waitingForCombat = false
	end
	if event == "PLAYER_LOGIN" then setupBaganator() end
	hookFrames()
	Marks.refreshSoon()
end)

if hooksecurefunc then
	for _, fn in ipairs({ "MerchantFrame_UpdateMerchantInfo", "OpenAllBags", "ToggleAllBags", "OpenBackpack", "ToggleBackpack", "ToggleBag" }) do
		if _G[fn] then hooksecurefunc(fn, function() hookFrames(); Marks.refreshSoon() end) end
	end
end
ns.onChange(function() Marks.refreshSoon() end)
