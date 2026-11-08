-- StarterPackTable
-- The 15-minute new-player offer (GDD 10.6): window, contents and when its prompts show.
-- Read by StarterPackService, StarterPackUI and UpsellService. Price lives in ProductTable.StarterPack (Director sets).
-- Copy rule: no fake discounts ("87% OFF" is not allowed).

local StarterPackTable = {
	ProductKey = "StarterPack",
	WindowSeconds = 15 * 60, -- real wall-clock from firstJoinAt; includes offline time; never returns
	ReminderSecondsLeft = 120, -- once, only if in-game

	Contents = {
		BallId = "imp",
		ToolUnlock = "grapple",
		Coins = 2500,
		Spins = 5,
		BoostMinutes = 30,
	},
}

return StarterPackTable
