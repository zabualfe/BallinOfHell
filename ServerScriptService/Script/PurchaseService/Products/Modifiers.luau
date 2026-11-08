-- Products/Modifiers
-- Family "Modifiers" (GDD 11.2/11.3): server-wide products and the two trolls. Params.ModifierId names the
-- ModifierTable entry. CanPrompt refuses at prompt time while the cooldown, cap, stack limit or a troll blocks the
-- purchase (trolls also check the buyer's 1-per-3-min limit). Effect hands the receipt to ModifierService, which
-- applies it or queues it when a race condition blocks it; either way the effect counts as granted.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProductTable = require(ReplicatedStorage.Tables.ProductTable)

local ModifierService = require(script.Parent.Parent.Parent.ModifierService)

local FAMILY = "Modifiers"

local Modifiers = { Products = {} }

for key, row in ProductTable do
	if row.Family ~= FAMILY then
		continue
	end
	local modifierId = row.Params and row.Params.ModifierId
	if type(modifierId) ~= "string" then
		warn(`[PurchaseService] {key} has no Params.ModifierId`)
		continue
	end
	Modifiers.Products[key] = {
		CanPrompt = function(player)
			return ModifierService.CanPrompt(modifierId, player)
		end,
		Effect = function(player)
			return ModifierService.Activate(modifierId, player) == true
		end,
	}
end

return Modifiers
