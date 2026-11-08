-- DailyRewardTable
-- The 7-day streak calendar and streak rules (GDD 10.3). Days are UTC: floor(GetServerTimeNow() / 86400).
-- Read by DailyRewardService and DailyRewardUI. Reward fields: Coins, Spins, BoostMinutes, ToolCharges, FirstTimeBall; VipCoins replaces Coins for VIP.
-- Boost minutes are 2x Coins boost time. After day 7 the cycle restarts at day 1.

local DailyRewardTable = {
	Config = {
		StreakLength = 7,
		RestoreMinGapDays = 2, -- today - lastClaimDay of 2 or 3 offers Restore Streak
		RestoreMaxGapDays = 3,
		ResetGapDays = 4, -- gap of 4+ resets to day 1
		RestoreProductKey = "RestoreDailyStreak",
		SeasonXp = 100,
	},

	Days = {
		{ Day = 1, Coins = 50, VipCoins = 75 },
		{ Day = 2, Spins = 1 },
		{ Day = 3, Coins = 100, VipCoins = 150, ToolCharges = { rocket = 3 } },
		{ Day = 4, BoostMinutes = 15 },
		{ Day = 5, Coins = 200, VipCoins = 300 },
		{ Day = 6, Spins = 2, ToolCharges = { shield = 3 } },
		{ Day = 7, Coins = 500, VipCoins = 750, Spins = 3, FirstTimeBall = "emberglow" }, -- ball on the first cycle only
	},
}

return DailyRewardTable
