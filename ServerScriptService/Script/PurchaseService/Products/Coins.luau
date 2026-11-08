-- Products/Coins
-- First product-family plug-in; the contract it follows is documented at the top of PurchaseService/init.luau.
--   Products = { [productKey] = { Effect = fn(player, receiptInfo, target?) -> boolean, CanPrompt = fn(player, targetArg) -> boolean, target? } }
--   Effect returns true once granted, false to be retried. CanPrompt is optional; a target it returns is stored
--   server-side and handed to Effect (targeted purchases only, AGENTS.md "Networking").
--
-- Family "Currency": coin packs. Amounts come from ProductTable[key].Params.Coins.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProductTable = require(ReplicatedStorage.Tables.ProductTable)

local EconomyService = require(script.Parent.Parent.Parent.EconomyService)

local FAMILY = "Currency"

local Coins = { Products = {} }

for key, row in ProductTable do
	if row.Family == FAMILY then
		local amount = row.Params and row.Params.Coins
		if type(amount) ~= "number" or amount <= 0 then
			warn(`[PurchaseService] {key} has no positive Params.Coins`)
			continue
		end
		Coins.Products[key] = {
			Effect = function(player)
				return EconomyService.AddCoins(player, amount, "Robux", key) == true
			end,
		}
	end
end

return Coins
