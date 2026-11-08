-- Products/Balls
-- Family "Balls": buy-by-rarity. The player picks a shop ball in the UI; the client sends its id as the
-- PromptProduct targetArg. CanPrompt checks it is a valid, non-exclusive, unowned ball of the product's rarity
-- and the server keeps it as the target. Effect grants exactly that ball.
-- If the ball was obtained in the meantime, the purchase pays out the ball's coin price instead (ProductTable note).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BallTable = require(ReplicatedStorage.Tables.BallTable)
local ProductTable = require(ReplicatedStorage.Tables.ProductTable)

local EconomyService = require(script.Parent.Parent.Parent.EconomyService)
local InventoryService = require(script.Parent.Parent.Parent.InventoryService)
local PlayerData = require(script.Parent.Parent.Parent.PlayerData)
local BuyRules = require(script.Parent.Parent.BuyRules)

local FAMILY = "Balls"

local Balls = { Products = {} }

for key, row in ProductTable do
	if row.Family ~= FAMILY then
		continue
	end
	local rarity = row.Params and row.Params.Rarity
	if type(rarity) ~= "string" then
		warn(`[PurchaseService] {key} has no Params.Rarity`)
		continue
	end
	Balls.Products[key] = {
		CanPrompt = function(player, ballId)
			local ok = BuyRules.BallPurchasable(ballId, rarity, PlayerData.Peek(player, "ownedBalls"))
			if not ok then
				return false
			end
			return true, ballId
		end,
		Effect = function(player, _, ballId)
			if type(ballId) ~= "string" or BallTable[ballId] == nil then
				return false
			end
			-- Owned: pay only the price. GrantBall on an owned ball would also fire DuplicateGranted and pay twice.
			if InventoryService.OwnsBall(player, ballId) then
				local price = BallTable[ballId].Price
				if type(price) ~= "number" then
					return true
				end
				return EconomyService.AddCoins(player, price, "Robux", key) == true
			end
			return InventoryService.GrantBall(player, ballId, "Robux") == true
		end,
	}
end

return Balls
