-- Products/CrownOfHell
-- Family "Offers", Crown of Hell only (limited to 1,000 ever). All the stock, reservation and serial logic lives in
-- LimitedBallService; this file only plugs its CanPrompt / OnReceipt into PurchaseService.

local LimitedBallService = require(script.Parent.Parent.Parent.LimitedBallService)

return {
	Products = {
		CrownOfHell = {
			CanPrompt = function(player)
				return LimitedBallService.CanPrompt(player)
			end,
			Effect = function(player, receiptInfo)
				return LimitedBallService.OnReceipt(player, receiptInfo)
			end,
		},
	},
}
