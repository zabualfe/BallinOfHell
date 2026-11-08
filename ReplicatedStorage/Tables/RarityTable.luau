-- RarityTable
-- One entry per rarity: stat budget, colour, Robux buy-by-rarity price and duplicate refund.
-- Read by BallStats/BallTable checks, InventoryService (duplicates), ShopService and every UI that names a rarity.
-- Colour is defined once here and used everywhere a rarity is named. Robux prices are placeholders pending Director sign-off.

local RarityTable = {
	Basic = {
		Order = 1,
		Budget = 9,
		Color = Color3.fromRGB(158, 158, 158),
		RobuxUnlock = 25,
		DuplicateCoins = 75,
	},
	Common = {
		Order = 2,
		Budget = 11,
		Color = Color3.fromRGB(76, 175, 80),
		RobuxUnlock = 49,
		DuplicateCoins = 200,
	},
	Rare = {
		Order = 3,
		Budget = 13,
		Color = Color3.fromRGB(33, 150, 243),
		RobuxUnlock = 99,
		DuplicateCoins = 600,
	},
	Epic = {
		Order = 4,
		Budget = 15,
		Color = Color3.fromRGB(156, 39, 176),
		RobuxUnlock = 199,
		DuplicateCoins = 1500,
	},
	Legendary = {
		Order = 5,
		Budget = 17,
		Color = Color3.fromRGB(255, 152, 0),
		RobuxUnlock = 399,
		DuplicateCoins = 2500,
	},
	Mythic = {
		Order = 6,
		Budget = 19,
		Color = Color3.fromRGB(244, 67, 54),
		RobuxUnlock = 799,
		DuplicateCoins = 5000,
	},
	Limited = {
		Order = 7,
		Budget = 21,
		Color = Color3.fromRGB(255, 213, 79),
		-- Shimmer for UI frames; Color is the flat fallback for RichText.
		Gradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 213, 79)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 244, 196)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 213, 79)),
		}),
		-- No buy-by-rarity and no duplicate refund: Limited has its own product.
	},
}

return RarityTable
