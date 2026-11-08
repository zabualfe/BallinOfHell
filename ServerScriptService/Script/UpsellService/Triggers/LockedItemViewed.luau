-- LockedItemViewed: a locked ball was viewed in the shop. Client message ShopBallViewed(ballId); inline offers
-- (Coins button, Robux unlock button), no popup. Contract: see UpsellService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopRules = require(ReplicatedStorage.Shared.ShopRules)
local BallTable = require(ReplicatedStorage.Tables.BallTable)
local ProductTable = require(ReplicatedStorage.Tables.ProductTable)

local PlayerData = require(script.Parent.Parent.Parent.PlayerData)
local ViewedTrigger = require(script.Parent.Parent.ViewedTrigger)

return ViewedTrigger.new("LockedItemViewed", "ShopBallViewed", function(player, ballId)
	local ball = BallTable[ballId]
	if not ball or not PlayerData.IsLoaded(player) or PlayerData.Peek(player, "ownedBalls")[ballId] ~= nil then
		return nil
	end
	local context = { BallId = ballId, ProductKeys = {}, Targets = { RobuxUnlock = ballId } }
	if ShopRules.IsBuyable(ball, PlayerData.Peek(player, "hasPickedStarter") == true) then
		context.CoinPrice = ball.Price
	end
	local productKey = "BallUnlock" .. tostring(ball.Rarity)
	if ProductTable[productKey] then
		context.ProductKeys.RobuxUnlock = productKey
	end
	return context
end)
