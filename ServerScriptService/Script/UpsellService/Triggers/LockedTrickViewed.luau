-- LockedTrickViewed: a locked trick was viewed. Client message TrickViewed(trickId); inline Coins and Robux unlock
-- buttons, no popup. Contract: see UpsellService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProductTable = require(ReplicatedStorage.Tables.ProductTable)
local TrickTable = require(ReplicatedStorage.Tables.TrickTable)

local PlayerData = require(script.Parent.Parent.Parent.PlayerData)
local ViewedTrigger = require(script.Parent.Parent.ViewedTrigger)

return ViewedTrigger.new("LockedTrickViewed", "TrickViewed", function(player, trickId)
	local trick = TrickTable.Tricks[trickId]
	if not trick or trick.Tier == "Free" or not PlayerData.IsLoaded(player) then
		return nil
	end
	if PlayerData.Peek(player, "ownedTricks")[trickId] ~= nil then
		return nil
	end
	local context = { TrickId = trickId, ProductKeys = {} }
	if trick.Source == "Coins" and type(trick.Price) == "number" then
		context.CoinPrice = trick.Price
	end
	if trick.RobuxProduct and ProductTable[trick.RobuxProduct] then
		context.ProductKeys.RobuxUnlock = trick.RobuxProduct
	end
	return context
end)
