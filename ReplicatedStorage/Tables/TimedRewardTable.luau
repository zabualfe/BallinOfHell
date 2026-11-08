-- TimedRewardTable
-- Session playtime gifts (GDD 10.4). Minutes count server-side playtime, reset each session; AFK past the limit stops the count.
-- Read by TimedRewardService and TimedRewardUI. Reward fields: Coins, Spins, BoostMinutes, ToolCharges, FirstTimeTrick, OnceEverBall.
-- OnceEver items are recorded in timedRewardsEverClaimed; Fallback replaces the item when already owned.

local TimedRewardTable = {
	Config = {
		AfkStopSeconds = 600,
		UnlockAllProductKey = "UnlockAllTimedGifts",
		SeasonXp = 25,
	},

	Gifts = {
		{ Minute = 2, Coins = 25 },
		{ Minute = 5, Spins = 1 },
		{ Minute = 10, Coins = 50 },
		{ Minute = 15, BoostMinutes = 10 },
		{ Minute = 20, Coins = 100 },
		{ Minute = 30, Coins = 100, Spins = 1, ToolCharges = { shield = 2 } },
		{ Minute = 45, Coins = 200, FirstTimeTrick = "skullsplit" },
		{ Minute = 60, OnceEverBall = "hellfirekick", Fallback = { Coins = 300, Spins = 2 } },
	},
}

return TimedRewardTable
