return {
	Name = "segment-test",
	Description = "Studio only: rebuilds the course as just one segment. Use 'none' to go back to a normal course.",
	Group = "BallOfHell",
	Args = {
		{ Type = "string", Name = "name", Description = "Segment name, or none" },
	},
}
