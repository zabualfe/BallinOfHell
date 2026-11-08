return {
	Name = "data-get",
	Description = "Prints one saved data key of a player as JSON.",
	Group = "BallOfHell",
	Args = {
		{ Type = "player", Name = "player", Description = "Target player" },
		{ Type = "string", Name = "key", Description = "Saved data key, e.g. coins" },
	},
}
