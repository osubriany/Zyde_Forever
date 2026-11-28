-- Auto repair. Opening a vendor that repairs fixes your gear when Auto repair
-- is on. Guild funds first pays the guild bank. Otherwise Repair all uses
-- your own gold. If the guild can't pay, your gold is left alone.

local _, ns = ...

local P = "|cff66ccffZyde_Forever|r: "
local tried

local function secret(v)
	return ns.isSecret and ns.isSecret(v) or false
end

local function plain(v)
	if secret(v) or type(v) ~= "number" then return nil end
	return v
end

local function money(copper)
	if GetCoinTextureString then
		local ok, text = pcall(GetCoinTextureString, copper)
		if ok and type(text) == "string" and not secret(text) then return text end
	end
	local g = math.floor(copper / 10000)
	local s = math.floor(copper / 100) % 100
	local c = copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = g .. "g" end
	if g > 0 or s > 0 then parts[#parts + 1] = s .. "s" end
	parts[#parts + 1] = c .. "c"
	return table.concat(parts, " ")
end

local function say(text)
	print(P .. text)
end

local function repair()
	if tried then return end
	if not (ns.F and ns.F("autoRepair")) then return end
	if MerchantFrame and MerchantFrame.IsShown and not MerchantFrame:IsShown() then return end
	if not (CanMerchantRepair and CanMerchantRepair()) then return end
	if not (GetRepairAllCost and RepairAllItems) then return end
	local cost = plain(GetRepairAllCost())
	if not cost or cost <= 0 then return end
	tried = true
	if ns.F("guildRepair") then
		local okCan, can = pcall(CanGuildBankRepair)
		if not okCan or secret(can) or not can then
			say("guild repair isn't available, so nothing was repaired")
			return
		end
		if not pcall(RepairAllItems, true) then return end
		local left = plain(GetRepairAllCost())
		if left and left > 0 then
			say("guild funds didn't cover the repair (" .. money(cost) .. ")")
		else
			say("repaired for " .. money(cost) .. " from guild funds")
		end
		return
	end
	local mine = GetMoney and plain(GetMoney())
	if mine and mine < cost then
		say("repair costs " .. money(cost) .. " and you don't have it")
		return
	end
	if not pcall(RepairAllItems) then return end
	local left = plain(GetRepairAllCost())
	if left and left > 0 then
		say("repair didn't finish (" .. money(left) .. " still due)")
	else
		say("repaired for " .. money(cost))
	end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("MERCHANT_SHOW")
ev:RegisterEvent("MERCHANT_UPDATE")
ev:RegisterEvent("MERCHANT_CLOSED")
ev:SetScript("OnEvent", function(_, event)
	if event == "MERCHANT_CLOSED" then
		tried = false
		return
	end
	-- The repair cost arrives with the vendor, a moment after the window opens.
	C_Timer.After(0.2, repair)
end)
