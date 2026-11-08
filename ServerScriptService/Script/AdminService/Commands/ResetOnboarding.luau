return {
	Name = "reset-onboarding",
	Description = "Marks the player as not having picked a starter ball, so the first-time flow runs again.",
	Group = "BallOfHell",
	Args = {
		{ Type = "player", Name = "player", Description = "Target player" },
	},
}
