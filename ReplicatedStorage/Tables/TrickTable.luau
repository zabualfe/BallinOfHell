-- TrickTable
-- Airtime trigger config, the 12 tricks, scoring constants, caps, loadout and upgrade costs (GDD 7).
-- Read by TrickController (client picker), TrickService (server validation/grant), TricksUI and SeasonService.
-- Formulas stay in code (GDD 7.5). AnimationId "" = not yet supplied by the Animator. Robux prices: ProductTable[RobuxProduct].
-- MIN_AIRTIME is a first guess: M1 measures a Jump-10 single jump and sets it to that + 0.1 s if >= 0.6.

local TrickTable = {
	Config = {
		GroundRayExtra = 0.5, -- studs added to ball radius: hit within = grounded
		AirClearanceExtra = 3, -- studs added to ball radius: no hit within = airborne
		MinAirtime = 0.6, -- seconds (tune)
		PickMargin = 0.10, -- seconds a trick must finish before predicted landing
		PredictMaxDrop = 200, -- studs; no ground below that = void, no trick
		PredictRecheckSeconds = 0.1,
		LandConfirm = 0.5, -- seconds after touchdown before points pay
		MaxTricksPerPlan = 5,
		BlendSeconds = 0.1, -- between tricks
		LandingBlendSeconds = 0.15,
	},

	Loadout = {
		Slots = 4,
		Default = { "tuck", "horns", "spin", "" },
	},

	Tricks = {
		tuck = {
			Name = "Ember Tuck",
			Tier = "Free",
			Rarity = "Basic",
			Duration = 0.4,
			BasePoints = 50,
			Source = "Starter",
			AnimationId = "",
			Order = 1,
		},
		horns = {
			Name = "Horn Salute",
			Tier = "Free",
			Rarity = "Basic",
			Duration = 0.4,
			BasePoints = 50,
			Source = "Starter",
			AnimationId = "",
			Order = 2,
		},
		spin = {
			Name = "Cinder Spin",
			Tier = "Free",
			Rarity = "Basic",
			Duration = 0.5,
			BasePoints = 60,
			Source = "Starter",
			AnimationId = "",
			Order = 3,
		},
		hellbird = {
			Name = "Hellbird",
			Tier = "Coins",
			Rarity = "Rare",
			Duration = 0.6,
			BasePoints = 100,
			Source = "Coins",
			Price = 750,
			RobuxProduct = "TrickUnlockHellbird",
			AnimationId = "",
			Order = 4,
		},
		backflip = {
			Name = "Backflip Inferno",
			Tier = "Coins",
			Rarity = "Rare",
			Duration = 0.7,
			BasePoints = 125,
			Source = "Coins",
			Price = 1500,
			RobuxProduct = "TrickUnlockBackflip",
			AnimationId = "",
			Order = 5,
		},
		handstand = {
			Name = "Brimstone Handstand",
			Tier = "Coins",
			Rarity = "Rare",
			Duration = 0.7,
			BasePoints = 125,
			Source = "Coins",
			Price = 2500,
			RobuxProduct = "TrickUnlockHandstand",
			AnimationId = "",
			Order = 6,
		},
		skullsplit = {
			Name = "Skull Split",
			Tier = "Reward",
			Rarity = "Epic",
			Duration = 0.6,
			BasePoints = 110,
			Source = "Timed",
			AnimationId = "",
			Order = 7, -- 45-min timed gift, once ever
		},
		throne = {
			Name = "Throne Sit",
			Tier = "Premium",
			Rarity = "Legendary",
			Duration = 0.8,
			BasePoints = 175,
			Source = "Robux",
			RobuxProduct = "TrickPremiumThrone",
			AnimationId = "",
			Order = 8, -- also Season 1 premium tier 15
		},
		doubleflip = {
			Name = "Double Damnation",
			Tier = "Premium",
			Rarity = "Legendary",
			Duration = 1.0,
			BasePoints = 225,
			Source = "Robux",
			RobuxProduct = "TrickPremiumDoubleFlip",
			AnimationId = "",
			Order = 9,
		},
		corkscrew = {
			Name = "Comet Corkscrew",
			Tier = "Premium",
			Rarity = "Legendary",
			Duration = 1.2,
			BasePoints = 275,
			Source = "Robux",
			RobuxProduct = "TrickPremiumCorkscrew",
			AnimationId = "",
			Order = 10,
		},
		howl = {
			Name = "Hellhound Howl",
			Tier = "Seasonal",
			Duration = 0.6,
			BasePoints = 110,
			Source = "Seasonal",
			SeasonId = "S1",
			AnimationId = "",
			Order = 11, -- Season 1 free tier 20
		},
		soulsurf = {
			Name = "Soul Surf",
			Tier = "Seasonal",
			Duration = 1.0,
			BasePoints = 230,
			Source = "Seasonal",
			SeasonId = "S1",
			AnimationId = "",
			Order = 12, -- Season 1 premium tier 30
		},
	},

	Scoring = {
		LevelMultiplier = { 1.00, 1.25, 1.50 }, -- L1, L2, L3
		MaxLevel = 3,
		ChainStep = 0.5, -- Chain_i = min(1 + ChainStep * (i - 1), ChainCap)
		ChainCap = 2.5,
		RepeatMultiplier = 0.5, -- same trick again in one airtime
		VarietyMinDistinct = 3,
		VarietyMultiplier = 1.25,
		AssistMultiplier = 0.5, -- Glider, Grapple or Gravity Coil; applies once
		SloppyMinProgress = 0.5, -- cut trick at or above: SloppyMultiplier; below: 0
		SloppyMultiplier = 0.5,
		PointsPerCoin = 200,
	},

	Caps = { -- base trick coins, before personal multipliers
		PerRound = 25,
		PerSegmentByTier = { Beginner = 2, Easy = 3, Medium = 4, Hard = 5, Insane = 7, Hell = 10, Finale = 10 },
	},

	Server = {
		SampleHz = 10,
		FitToleranceSeconds = 0.2,
		StrikeOvershootSeconds = 0.5,
		MaxVerticalVelocityGain = 15, -- studs/s between samples without an explaining event
		UnexplainedStrikeAfter = 2, -- unexplained airtimes in one round before the first strike (the 1st only pays 0)
		ReportRateLimit = 3, -- ReportTricks per second
	},

	-- Upgrade cost in coins per trick Tier.
	Upgrades = {
		Free = { L2 = 300, L3 = 900 },
		Coins = { L2 = 600, L3 = 1800 },
		Reward = { L2 = 1000, L3 = 3000 },
		Premium = { L2 = 1000, L3 = 3000 },
		Seasonal = { L2 = 1000, L3 = 3000 },
		AlreadyL3Refund = 1000, -- coins when a track/pack reward hits an L3 trick
	},
}

return TrickTable
