-- Products/Streak
-- Family "Offers", Restore Streak only (ProductTable.RestoreDailyStreak). CanPrompt allows it inside the 48 h window
-- after a break (DailyRewardTable.Config gap days); Effect restores the streak and is safe to retry.

local DailyRewardService = require(script.Parent.Parent.Parent.DailyRewardService)

return {
	Products = {
		RestoreDailyStreak = {
			CanPrompt = function(player)
				return DailyRewardService.CanRestore(player)
			end,
			Effect = function(player)
				return DailyRewardService.RestoreStreak(player)
			end,
		},
	},
}
