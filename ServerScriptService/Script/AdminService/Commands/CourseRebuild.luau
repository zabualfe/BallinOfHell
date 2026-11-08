return {
	Name = "course-rebuild",
	Description = "Tears the course down and builds it again, optionally with a given seed.",
	Group = "BallOfHell",
	Args = {
		{ Type = "integer", Name = "seed", Description = "Seed to build with", Optional = true },
	},
}
