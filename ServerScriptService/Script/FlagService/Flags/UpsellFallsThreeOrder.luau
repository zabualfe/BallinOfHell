-- UpsellFallsThreeOrder: the first A/B test named in the GDD (11.4). At 3 falls on a segment, offer the
-- Tool Refill (Shield x5) first or the Skip Segment first. Players are bucketed by UserId; remote config
-- can force a variant by setting this key to "ShieldFirst" or "SkipFirst".
-- UpsellService reads the offer order with FlagService.GetState(player, "UpsellFallsThreeOrder").

local UpsellFallsThreeOrder = {
	Key = "UpsellFallsThreeOrder",
	Default = "ShieldFirst",
	Disabled = false,
	Variants = { ShieldFirst = 50, SkipFirst = 50 },
	States = {
		ShieldFirst = { "ToolRefill", "SkipSegment" },
		SkipFirst = { "SkipSegment", "ToolRefill" },
	},
}

return UpsellFallsThreeOrder
