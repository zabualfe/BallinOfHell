-- ViewedTrigger
-- Shared body of the two "locked thing viewed" inline triggers (LockedItemViewed, LockedTrickViewed). The client
-- reports the view with a message; `describe(player, itemId)` validates it on the server and returns the offer
-- context { CoinPrice?, ProductKeys?, Targets? } or nil when the item is unknown, owned or not for sale.
--   Offer "Coins" is eligible when the context has a CoinPrice; "RobuxUnlock" resolves to context.ProductKeys.RobuxUnlock.
-- Inline offers have no cap and no spacing, so the message's own rate limit is what bounds them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage.Network)

local ViewedTrigger = {}

local VIEW_RATE = { Capacity = 4, RefillPerSecond = 1 } -- viewed message burst / per second
local MAX_ID_LENGTH = 64

function ViewedTrigger.new(id, messageName, describe)
	return {
		Id = id,
		Start = function(UpsellService)
			Network.OnEvent(messageName, function(player, itemId)
				if type(itemId) ~= "string" or #itemId == 0 or #itemId > MAX_ID_LENGTH then
					return
				end
				local context = describe(player, itemId)
				if context then
					UpsellService.Offer(player, id, context)
				end
			end, VIEW_RATE)
		end,
		Eligible = function(_, offerKey, context)
			if offerKey == "Coins" then
				return context.CoinPrice ~= nil
			end
			return nil
		end,
	}
end

return ViewedTrigger
