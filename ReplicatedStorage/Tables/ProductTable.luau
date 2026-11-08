-- ProductTable
-- Every developer product, keyed by a stable string key. Id = 0 is a placeholder until the real Roblox product exists.
-- Read by PurchaseService (builds an Id -> product lookup at runtime), the shop/offer UIs and UpsellTable by key.
-- ALL PRICES ARE PLACEHOLDER PROPOSALS (GDD 11): the Director must sign them off before publishing.
-- Family names the PurchaseService/Products plug-in that grants it. Params are data for that plug-in.

local ProductTable = {
	-- Progress
	SkipSegment = { Id = 0, Name = "Skip Segment", Family = "Progress", Price = 19, Params = { Segments = 1 } },
	SkipFiveSegments = { Id = 0, Name = "Skip 5 Segments", Family = "Progress", Price = 59, Params = { Segments = 5 } },
	RespawnHere = { Id = 0, Name = "Respawn Here", Family = "Progress", Price = 15 },

	-- Currency
	Coins1000 = { Id = 0, Name = "1,000 Coins", Family = "Currency", Price = 49, Params = { Coins = 1000 } },
	Coins3000 = { Id = 0, Name = "3,000 Coins", Family = "Currency", Price = 129, Params = { Coins = 3000 } },
	Coins7500 = { Id = 0, Name = "7,500 Coins", Family = "Currency", Price = 279, Params = { Coins = 7500 } },
	Coins20000 = { Id = 0, Name = "20,000 Coins", Family = "Currency", Price = 649, Params = { Coins = 20000 } },
	Coins50000 = {
		Id = 0,
		Name = "50,000 Coins",
		Family = "Currency",
		Price = 1399,
		Params = { Coins = 50000, BestValue = true },
	},

	-- Wheel (hidden when paid random items are restricted)
	Spins1 = { Id = 0, Name = "1 Spin", Family = "Wheel", Price = 39, Params = { Spins = 1 } },
	Spins5 = { Id = 0, Name = "5 Spins", Family = "Wheel", Price = 169, Params = { Spins = 5 } },
	Spins15 = { Id = 0, Name = "15 Spins", Family = "Wheel", Price = 449, Params = { Spins = 15 } },

	-- Offers
	StarterPack = { Id = 0, Name = "Starter Pack", Family = "Offers", Price = 99, Params = { Gift = false } }, -- Director sets
	CrownOfHell = {
		Id = 0,
		Name = "Crown of Hell",
		Family = "Offers",
		Price = 1499,
		Params = {
			BallId = "crownofhell",
			Gift = false,
			-- Granted when the receipt arrives after the 1,000 are gone (outage only, GDD 10.7). Roblox can't refund.
			Consolation = { Coins = 25000, TrailId = "AshenCrown", TrailName = "Ashen Crown" },
		},
	}, -- Director sets
	RestoreDailyStreak = { Id = 0, Name = "Restore Streak", Family = "Offers", Price = 39 },
	UnlockAllTimedGifts = { Id = 0, Name = "Unlock All Gifts", Family = "Offers", Price = 99 },
	Coins2xThirtyMinutes = {
		Id = 0,
		Name = "2x Coins 30 min",
		Family = "Offers",
		Price = 49,
		Params = { BoostMinutes = 30 },
	},

	-- Balls: buy-by-rarity. Unlocks the coin-shop ball being viewed; owned at receipt -> its coin Price.
	BallUnlockBasic = {
		Id = 0,
		Name = "Unlock Basic Ball",
		Family = "Balls",
		Price = 25,
		Params = { Rarity = "Basic" },
	},
	BallUnlockCommon = {
		Id = 0,
		Name = "Unlock Common Ball",
		Family = "Balls",
		Price = 49,
		Params = { Rarity = "Common" },
	},
	BallUnlockRare = { Id = 0, Name = "Unlock Rare Ball", Family = "Balls", Price = 99, Params = { Rarity = "Rare" } },
	BallUnlockEpic = { Id = 0, Name = "Unlock Epic Ball", Family = "Balls", Price = 199, Params = { Rarity = "Epic" } },
	BallUnlockLegendary = {
		Id = 0,
		Name = "Unlock Legendary Ball",
		Family = "Balls",
		Price = 399,
		Params = { Rarity = "Legendary" },
	},
	BallUnlockMythic = {
		Id = 0,
		Name = "Unlock Mythic Ball",
		Family = "Balls",
		Price = 799,
		Params = { Rarity = "Mythic" },
	},

	-- Tools: unlock by tool rarity (ToolTable). Already owned in a bundle -> +10 stored charges.
	ToolUnlockCommon = {
		Id = 0,
		Name = "Unlock Common Tool",
		Family = "Tools",
		Price = 49,
		Params = { Rarity = "Common" },
	},
	ToolUnlockRare = { Id = 0, Name = "Unlock Rare Tool", Family = "Tools", Price = 99, Params = { Rarity = "Rare" } },
	ToolUnlockEpic = { Id = 0, Name = "Unlock Epic Tool", Family = "Tools", Price = 149, Params = { Rarity = "Epic" } },
	ToolUnlockLegendary = {
		Id = 0,
		Name = "Unlock Legendary Tool",
		Family = "Tools",
		Price = 249,
		Params = { Rarity = "Legendary" },
	},
	ToolRefill = { Id = 0, Name = "Tool Refill", Family = "Tools", Price = 25, Params = { Charges = 5 } }, -- viewed tool
	ToolCrate = {
		Id = 0,
		Name = "Tool Crate",
		Family = "Tools",
		Price = 99,
		Params = { Charges = 3, ExcludeTools = { "pocket" } },
	},
	SurvivalBundle = {
		Id = 0,
		Name = "Survival Bundle",
		Family = "Tools",
		Price = 199,
		Params = { Unlocks = { "shield", "glider" }, Charges = 5 },
	},
	SpeedrunnerBundle = {
		Id = 0,
		Name = "Speedrunner Bundle",
		Family = "Tools",
		Price = 199,
		Params = { Unlocks = { "rocket", "grapple" }, Charges = 5 },
	},

	-- Tricks (TrickTable[...].RobuxProduct points here). Owned at receipt -> next upgrade level.
	TrickUnlockHellbird = {
		Id = 0,
		Name = "Unlock Hellbird",
		Family = "Tricks",
		Price = 25,
		Params = { TrickId = "hellbird" },
	},
	TrickUnlockBackflip = {
		Id = 0,
		Name = "Unlock Backflip Inferno",
		Family = "Tricks",
		Price = 49,
		Params = { TrickId = "backflip" },
	},
	TrickUnlockHandstand = {
		Id = 0,
		Name = "Unlock Brimstone Handstand",
		Family = "Tricks",
		Price = 49,
		Params = { TrickId = "handstand" },
	},
	TrickPremiumThrone = { Id = 0, Name = "Throne Sit", Family = "Tricks", Price = 79, Params = { TrickId = "throne" } },
	TrickPremiumDoubleFlip = {
		Id = 0,
		Name = "Double Damnation",
		Family = "Tricks",
		Price = 99,
		Params = { TrickId = "doubleflip" },
	},
	TrickPremiumCorkscrew = {
		Id = 0,
		Name = "Comet Corkscrew",
		Family = "Tricks",
		Price = 129,
		Params = { TrickId = "corkscrew" },
	},
	TrickPack = {
		Id = 0,
		Name = "Trick Pack",
		Family = "Tricks",
		Price = 249,
		Params = { TrickIds = { "throne", "doubleflip", "corkscrew" }, Level = 2, BoostMinutes = 30 },
	},
	MaxThisTrick = { Id = 0, Name = "Max This Trick", Family = "Tricks", Price = 49, Params = { Level = 3 } }, -- viewed trick

	-- Season (granted per season; SeasonTable.Seasons[id].Products lists which keys are sold)
	SeasonPremiumPass = {
		Id = 0,
		Name = "Season Premium Pass",
		Family = "Season",
		Price = 399,
		Params = { Premium = true },
	}, -- Director sets
	SeasonPremiumPlus = {
		Id = 0,
		Name = "Season Premium+",
		Family = "Season",
		Price = 699,
		Params = { Premium = true, Tiers = 10 },
	},
	SeasonBuyTier = { Id = 0, Name = "Buy a Tier", Family = "Season", Price = 49, Params = { Tiers = 1 } },
	SeasonBuyTenTiers = { Id = 0, Name = "Buy 10 Tiers", Family = "Season", Price = 399, Params = { Tiers = 10 } },
	SeasonEndingTenTiers = {
		Id = 0,
		Name = "Season Ending: 10 Tiers",
		Family = "Season",
		Price = 299,
		Params = { Tiers = 10 },
	}, -- last 7 days

	-- Server-wide (ModifierTable holds the rules)
	LowGravity = {
		Id = 0,
		Name = "Low Gravity",
		Family = "Modifiers",
		Price = 99,
		Params = { ModifierId = "LowGravity" },
	},
	DoubleJumpForAll = {
		Id = 0,
		Name = "Double Jump for All",
		Family = "Modifiers",
		Price = 79,
		Params = { ModifierId = "DoubleJumpForAll" },
	},
	GiantBalls = {
		Id = 0,
		Name = "Giant Balls",
		Family = "Modifiers",
		Price = 49,
		Params = { ModifierId = "GiantBalls" },
	},
	PlusTwoMinutes = {
		Id = 0,
		Name = "+2 Min Round Time",
		Family = "Modifiers",
		Price = 99,
		Params = { ModifierId = "PlusTwoMinutes" },
	},
	ShrinkEveryone = {
		Id = 0,
		Name = "Shrink Everyone",
		Family = "Modifiers",
		Price = 49,
		Params = { ModifierId = "ShrinkEveryone" },
	},
	SlowEveryone = {
		Id = 0,
		Name = "Slow Everyone",
		Family = "Modifiers",
		Price = 79,
		Params = { ModifierId = "SlowEveryone" },
	},
}

-- Gifting (GDD 11.2) is not a separate product: it reuses these keys at the same price.

return ProductTable
