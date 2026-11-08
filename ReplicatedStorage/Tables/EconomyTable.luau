-- EconomyTable
-- Coin multiplier rules and base coin sources (GDD 9, 2, 10). Single currency: Coins.
-- Read by EconomyService, ProgressService, TrickService, DailyRewardService and OnboardingService.
-- Formula (code): race coins = floor(base * RoundMultiplier * Personal), minimum 1. Checkpoint coins live in CourseTable.Tiers.

local EconomyTable = {
	Race = {
		MinCoins = 1,
		PersonalMax = 3, -- 2x pass and 2x boost add (1 + 1 + 1), they do not multiply
	},

	-- Added to the base 1.0. TrickPersonal = Personal + TrickCoinsPass, max TrickPersonalMax.
	PersonalBonus = {
		CoinsPass = 1,
		CoinsBoost = 1,
		TrickCoinsPass = 1,
	},
	TrickPersonalMax = 4,

	-- Which grants the 2x Coins pass doubles. Season track coins are never multiplied.
	PassDoubles = {
		RaceCoins = true,
		TrickCoins = true,
		RewardCoins = true, -- daily, timed, wheel, first-fall present
		CoinPacks = false,
		StarterPack = false,
		Duplicates = false,
		PurchaseRefunds = false,
		SeasonTrack = false,
	},
	VipDailyCoinBonus = 0.5, -- adds to the pass: pass + VIP = x2.5 on daily coins

	Boost = {
		Coins2xBankCapMinutes = 120,
		Coins2xProductMinutes = 30, -- "2x Coins 30 min" product
		PausedWhileOffline = true, -- proposal pending Director (GDD 14 Q7): store remaining seconds
	},

	Finish = {
		BaseCoins = 100,
		PlaceBonus = { 50, 30, 20 }, -- 1st, 2nd, 3rd; must be rolled by hand
	},

	Sources = {
		FirstFallPresent = { Coins = 150, Spins = 2, BoostMinutes = 10, ToolCharges = { shield = 2 } },
		DailyReward = { MinCoins = 50, MaxCoins = 500 },
		TimedGift = { MinCoins = 25, MaxCoins = 300 },
		Wheel = { CoinSlices = { 50, 150, 400 } },
		CoinPacks = { Min = 1000, Max = 50000 },
		StarterPackCoins = 2500,
		WheelBallDuplicateCoins = 2500,
		TrickPointsPerCoin = 200,
		SeasonBonusChestCoins = 100,
		ComebackPresent = { Coins = 50, ToolCharges = { shield = 1 }, Enabled = false }, -- proposal, needs approval (GDD 10.2)
	},
	-- Duplicate refunds by rarity: RarityTable[rarity].DuplicateCoins.

	Onboarding = {
		StarterBallIds = { "sprinter", "grip", "bouncer" },
		StarterToolId = "shield",
		StarterToolCharges = 3,
	},
}

return EconomyTable
