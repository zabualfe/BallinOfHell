return {
	Name = "give-coins",
	Description = "Adds coins to a player (negative removes). Clamped to a sane range.",
	Group = "BallOfHell",
	Args = {
		{ Type = "player", Name = "player", Description = "Target player" },
		{ Type = "integer", Name = "amount", Description = "Coins to add" },
	},
}
