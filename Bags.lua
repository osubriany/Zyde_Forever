-- Zyde_Forever: one shared look at your bags.
-- Ammo, pet food, the food reminder, the scrap list, vendor advice, the gear
-- arrows and GearAdvisor all read your bags after every change. Instead of
-- each asking the game about every slot, they ask ns.Bags.items(): the
-- filled slots of your backpack and bags (0 to NUM_BAG_SLOTS), read once
-- after a change and shared until the next one.
--
-- Each entry is the game's C_Container.GetContainerItemInfo table (itemID,
-- stackCount, hyperlink, iconFileID, quality, isLocked...) plus .bag and .slot.
-- The list is shared: read it, don't change it.

local ADDON, ns = ...

local Bags = {}
ns.Bags = Bags

local items, dirty = {}, true

function Bags.items()
	if not dirty then return items end
	dirty = false
	wipe(items)
	local numSlots = C_Container and C_Container.GetContainerNumSlots
	local itemInfo = C_Container and C_Container.GetContainerItemInfo
	if not (numSlots and itemInfo) then return items end
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		for slot = 1, (numSlots(bag) or 0) do
			local info = itemInfo(bag, slot)
			if info and info.itemID then
				info.bag, info.slot = bag, slot
				items[#items + 1] = info
			end
		end
	end
	return items
end

-- Read again next time anyone asks. Any of these can change what's in a slot
-- (or its lock); BAG_UPDATE comes before BAG_UPDATE_DELAYED, so code that
-- runs in between never sees an old list.
function Bags.invalidate() dirty = true end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "BAG_UPDATE", "BAG_UPDATE_DELAYED", "BAG_CONTAINER_UPDATE", "ITEM_LOCK_CHANGED",
	"PLAYER_ENTERING_WORLD", "UNIT_INVENTORY_CHANGED", "PLAYERBANKSLOTS_CHANGED" }) do
	pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function() dirty = true end)
