-- Products/TimedUnlock
-- Family "Offers", Unlock All Now only (ProductTable.UnlockAllTimedGifts). CanPrompt needs at least one gift left this
-- session; Effect claims every remaining gift and returns false (receipt retried) if any grant failed, so a retry
-- only claims what is still unclaimed.

local TimedRewardService = require(script.Parent.Parent.Parent.TimedRewardService)

return {
	Products = {
		UnlockAllTimedGifts = {
			CanPrompt = function(player)
				return TimedRewardService.GetRemainingCount(player) > 0
			end,
			Effect = function(player)
				return TimedRewardService.UnlockAll(player)
			end,
		},
	},
}
