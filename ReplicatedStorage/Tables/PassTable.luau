-- PassTable
-- The 9 game passes, keyed by a stable string key. Id = 0 is a placeholder until the real pass exists.
-- Read by GamePassService (UserOwnsGamePassAsync), the shop and the systems each perk touches.
-- ALL PRICES ARE PLACEHOLDER PROPOSALS (GDD 11.1): the Director must sign them off before publishing. Perk numbers live in their own tables.

local PassTable = {
	VIP = {
		Id = 0,
		Name = "VIP",
		Price = 349,
		Perk = "+50% daily coins, +1 free spin per day, gold chat tag, VIP lobby spot",
	},
	Coins2x = { Id = 0, Name = "2x Coins", Price = 299, Perk = "Personal x2 on race, trick and reward coins" },
	DoubleJump = { Id = 0, Name = "Double Jump", Price = 149, Perk = "Double jump (toggle in settings)" },
	Turbo = { Id = 0, Name = "Turbo", Price = 249, Perk = "MaxForce x1.10" },
	Lucky = { Id = 0, Name = "Lucky", Price = 199, Perk = "Free spin every 4 h instead of 8 h" },
	TrailsPack = {
		Id = 0,
		Name = "Trails Pack",
		Price = 99,
		Perk = "6 cosmetic trails",
		Trails = { "Ember", "Smoke", "Soul", "Bone Dust", "Gold", "Lava Drip" },
	},
	ToolBelt = { Id = 0, Name = "Tool Belt", Price = 199, Perk = "3rd tool slot" },
	UnlimitedRockets = {
		Id = 0,
		Name = "Unlimited Rockets",
		Price = 399,
		Perk = "No free-charge limit on Rocket Burst",
	},
	TrickCoins2x = { Id = 0, Name = "2x Trick Coins", Price = 149, Perk = "+1 trick coin multiplier, max x4 total" },
}

return PassTable
