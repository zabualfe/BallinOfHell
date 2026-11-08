-- Products/Spins
-- Family "Wheel": paid spin packs (ProductTable Params.Spins). Paid spins are paid random items, so CanPrompt
-- refuses while PolicyService restricts them (or has not answered). The receipt still grants: the Robux was
-- already spent, so a policy change between prompt and receipt must not eat the purchase.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProductTable = require(ReplicatedStorage.Tables.ProductTable)

local SpinWheelService = require(script.Parent.Parent.Parent.SpinWheelService)

local FAMILY = "Wheel"

local Spins = { Products = {} }

for key, row in ProductTable do
	if row.Family ~= FAMILY then
		continue
	end
	local count = row.Params and row.Params.Spins
	if type(count) ~= "number" or count <= 0 then
		warn(`[PurchaseService] {key} has no positive Params.Spins`)
		continue
	end
	Spins.Products[key] = {
		CanPrompt = function(player)
			return not SpinWheelService.ArePaidRandomItemsRestricted(player)
		end,
		Effect = function(player)
			return SpinWheelService.AddSpins(player, count, "Robux") == true
		end,
	}
end

return Spins
