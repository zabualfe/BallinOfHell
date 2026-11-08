return {
	Name = "limited-log",
	Description = "Lists the newest Crown of Hell sales (serial and PurchaseId).",
	Group = "BallOfHell",
	Args = {
		{ Type = "integer", Name = "count", Description = "How many sales to show (default 10)", Optional = true },
	},
}
