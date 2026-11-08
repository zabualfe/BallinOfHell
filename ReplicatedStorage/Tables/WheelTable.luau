-- WheelTable
-- The 8 wheel slices (weights sum to 100) and free-spin timing (GDD 10.5).
-- Read by SpinWheelService (server roll with one Random) and WheelUI (odds screen, shown before any paid spin).
-- Reward Type: Coins, Spins, BoostMinutes, SkipToken, ToolCharges, Ball. Paid spins use ProductTable Spins1/Spins5/Spins15.

local WheelTable = {
	Config = {
		FreeSpinSeconds = 8 * 3600,
		LuckyFreeSpinSeconds = 4 * 3600, -- Lucky pass
		MaxBankedFreeSpins = 1, -- timer pauses while one is waiting
		VipExtraFreeSpinsPerDay = 1,
		SpinAnimationSeconds = 4,
		PaidSpinProductKeys = { "Spins1", "Spins5", "Spins15" },
	},

	Slices = {
		{ Id = 1, Weight = 30, Reward = { Type = "Coins", Amount = 50 } },
		{ Id = 2, Weight = 20, Reward = { Type = "Coins", Amount = 150 } },
		{ Id = 3, Weight = 6, Reward = { Type = "Coins", Amount = 400 } },
		{ Id = 4, Weight = 12, Reward = { Type = "Spins", Amount = 1 } },
		{ Id = 5, Weight = 10, Reward = { Type = "BoostMinutes", Amount = 15 } },
		{ Id = 6, Weight = 8, Reward = { Type = "SkipToken", Amount = 1 } },
		{ Id = 7, Weight = 12, Reward = { Type = "ToolCharges", ToolId = "shield", Amount = 3 } },
		{ Id = 8, Weight = 2, Reward = { Type = "Ball", BallId = "smokewraith", DuplicateCoins = 2500 } },
	},
}

return WheelTable
