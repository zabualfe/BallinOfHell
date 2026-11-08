-- SeasonTable
-- Season pass tuning and per-season reward tracks (GDD 8). Seasons.S1 = "Emberfall".
-- Read by SeasonService (XP, claims, rollover), SeasonPassUI and ChallengeService. Tier = min(Tiers, floor(xp / XpPerTier)).
-- StartUtc/EndUtc = 0 until the Director sets dates; the active season is the one named by the ActiveSeasonId flag within its dates.
-- Free[n] / Premium[n] is the list of rewards for tier n. Reward Type: Coins, Spins, BoostMinutes, ToolCharges, ToolUnlock, SkipToken, Trail, Trick, Ball, Title.
-- Challenge XP (150 daily, 500 weekly) is on ChallengeTable rows. Season track coins are never multiplied.

local SeasonTable = {
	Config = {
		LengthDays = 30,
		Tiers = 40,
		XpPerTier = 900,
		CatchUpMultiplier = 1.5, -- while tier < days elapsed since StartUtc
		BonusChestXp = 1800, -- per chest after the last tier
		BonusChestMax = 10,
		BonusChestFreeCoins = 100,
		BonusChestPremiumSpins = 1,
		HideProductsLastSeconds = 3600,
		EndingOfferLastDays = 7, -- Season Ending: 10 Tiers replaces Buy 10 Tiers
		BuyTenTiersHiddenAboveTier = 30,
		BuyTierXp = 900,
		BuyTenTiersXp = 9000,
		PremiumPlusBonusTiers = 10,
		AlreadyPremiumBonusTiers = 10, -- Premium bought twice grants this many tiers
		UnlocksHudAfterFirstResults = true,
	},

	Xp = {
		Checkpoint = 10, -- skipped segments give 0
		Finish = 100,
		TrickLanding = 5, -- Clean or Sloppy airtime with at least 1 trick
		TrickLandingMaxPerRound = 100,
		DailyRewardClaim = 100, -- see DailyRewardTable
		TimedGiftClaim = 25, -- see TimedRewardTable
	},

	Seasons = {
		S1 = {
			Name = "Emberfall",
			StartUtc = 0,
			EndUtc = 0,
			Tiers = 40,
			XpPerTier = 900,
			Products = {
				"SeasonPremiumPass",
				"SeasonPremiumPlus",
				"SeasonBuyTier",
				"SeasonBuyTenTiers",
				"SeasonEndingTenTiers",
			},
			BallIds = { "cinderhound", "moltenmonarch" },

			Free = {
				[1] = { { Type = "Coins", Amount = 100 } },
				[2] = { { Type = "Spins", Amount = 1 } },
				[3] = { { Type = "ToolCharges", ToolId = "shield", Amount = 3 } },
				[4] = { { Type = "Coins", Amount = 100 } },
				[5] = { { Type = "BoostMinutes", Amount = 15 } },
				[6] = { { Type = "Coins", Amount = 150 } },
				[7] = { { Type = "ToolCharges", ToolId = "rocket", Amount = 3 } },
				[8] = { { Type = "Spins", Amount = 1 } },
				[9] = { { Type = "Coins", Amount = 150 } },
				[10] = { { Type = "Trail", Id = "CinderWake", Name = "Cinder Wake" } },
				[11] = { { Type = "Coins", Amount = 150 } },
				[12] = { { Type = "ToolCharges", ToolId = "spring", Amount = 3 } },
				[13] = { { Type = "Spins", Amount = 1 } },
				[14] = { { Type = "Coins", Amount = 200 } },
				[15] = { { Type = "BoostMinutes", Amount = 15 } },
				[16] = { { Type = "Coins", Amount = 200 } },
				[17] = { { Type = "ToolCharges", ToolId = "shield", Amount = 3 } },
				[18] = { { Type = "Spins", Amount = 1 } },
				[19] = { { Type = "Coins", Amount = 200 } },
				[20] = { { Type = "Trick", Id = "howl" } },
				[21] = { { Type = "Coins", Amount = 200 } },
				[22] = { { Type = "ToolCharges", ToolId = "glider", Amount = 3 } },
				[23] = { { Type = "Spins", Amount = 2 } },
				[24] = { { Type = "Coins", Amount = 250 } },
				[25] = { { Type = "BoostMinutes", Amount = 15 } },
				[26] = { { Type = "Coins", Amount = 250 } },
				[27] = { { Type = "ToolCharges", ToolId = "grapple", Amount = 3 } },
				[28] = { { Type = "Spins", Amount = 2 } },
				[29] = { { Type = "Coins", Amount = 250 } },
				[30] = { { Type = "SkipToken", Amount = 1 } },
				[31] = { { Type = "Coins", Amount = 300 } },
				[32] = { { Type = "ToolCharges", ToolId = "shield", Amount = 3 } },
				[33] = { { Type = "Spins", Amount = 2 } },
				[34] = { { Type = "Coins", Amount = 300 } },
				[35] = { { Type = "BoostMinutes", Amount = 30 } },
				[36] = { { Type = "Coins", Amount = 300 } },
				[37] = { { Type = "ToolCharges", ToolId = "coil", Amount = 3 } },
				[38] = { { Type = "Spins", Amount = 3 } },
				[39] = { { Type = "Coins", Amount = 400 } },
				[40] = { { Type = "Ball", Id = "cinderhound" } },
			},

			Premium = {
				[1] = {
					{ Type = "Trail", Id = "HellfireWake", Name = "Hellfire Wake" },
					{ Type = "BoostMinutes", Amount = 30 },
				},
				[2] = { { Type = "Coins", Amount = 250 } },
				[3] = { { Type = "Spins", Amount = 2 } },
				[4] = { { Type = "ToolCharges", ToolId = "shield", Amount = 5 } },
				[5] = { { Type = "Coins", Amount = 250 } },
				[6] = { { Type = "SkipToken", Amount = 1 } },
				[7] = { { Type = "BoostMinutes", Amount = 30 } },
				[8] = { { Type = "Coins", Amount = 300 } },
				[9] = { { Type = "Spins", Amount = 2 } },
				[10] = { { Type = "Trail", Id = "SoulWake", Name = "Soul Wake" } },
				[11] = { { Type = "Coins", Amount = 300 } },
				[12] = { { Type = "ToolCharges", ToolId = "rocket", Amount = 5 } },
				[13] = { { Type = "Spins", Amount = 2 } },
				[14] = { { Type = "Coins", Amount = 350 } },
				[15] = { { Type = "Trick", Id = "throne" } },
				[16] = { { Type = "ToolCharges", ToolId = "spring", Amount = 5 } },
				[17] = { { Type = "Coins", Amount = 350 } },
				[18] = { { Type = "BoostMinutes", Amount = 30 } },
				[19] = { { Type = "Spins", Amount = 3 } },
				[20] = {
					{ Type = "Trail", Id = "GoldEmber", Name = "Gold Ember" },
					{ Type = "Title", Id = "Emberlord", Name = "Emberlord" },
				},
				[21] = { { Type = "Coins", Amount = 400 } },
				[22] = { { Type = "ToolCharges", ToolId = "pocket", Amount = 2 } },
				[23] = { { Type = "Spins", Amount = 3 } },
				[24] = { { Type = "Coins", Amount = 400 } },
				[25] = { { Type = "SkipToken", Amount = 2 } },
				[26] = { { Type = "ToolCharges", ToolId = "grapple", Amount = 5 } },
				[27] = { { Type = "Coins", Amount = 450 } },
				[28] = { { Type = "BoostMinutes", Amount = 30 } },
				[29] = { { Type = "Spins", Amount = 3 } },
				[30] = { { Type = "Trick", Id = "soulsurf" } },
				[31] = { { Type = "Coins", Amount = 500 } },
				[32] = { { Type = "ToolCharges", ToolId = "glider", Amount = 5 } },
				[33] = { { Type = "Spins", Amount = 3 } },
				[34] = { { Type = "Coins", Amount = 500 } },
				[35] = { { Type = "ToolUnlock", ToolId = "glider" } },
				[36] = { { Type = "Coins", Amount = 550 } },
				[37] = { { Type = "ToolCharges", ToolId = "shield", Amount = 5 } },
				[38] = { { Type = "Spins", Amount = 5 } },
				[39] = { { Type = "Coins", Amount = 1000 } },
				[40] = {
					{ Type = "Ball", Id = "moltenmonarch" },
					{ Type = "Trail", Id = "MonarchCrown", Name = "Monarch Crown" },
				},
			},
		},
	},
}

return SeasonTable
