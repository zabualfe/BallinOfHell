-- UpsellTable
-- When UpsellService may offer what (GDD 11.4): global spacing rules and one row per trigger.
-- Read by UpsellService and UpsellUI. Offers are ProductTable / PassTable keys. All triggers are FlagService flags for A/B tests.
-- CapPerSession 0 with Inline = true means no popup (shown inline on the item). Params are the trigger thresholds.

local UpsellTable = {
	Global = {
		MinSecondsBetweenPopups = 90,
		QuietFirstSessionSeconds = 180, -- except StarterPackCheckpoint1
		MaxPerSegment = 1,
		NoneDuringCountdown = true,
	},

	Triggers = {
		{
			Id = "FallsThree",
			Type = "FallsOnSegment",
			Params = { Falls = 3, ToolsAllowed = true },
			Offers = { "ToolRefill", "SkipSegment" },
			CapPerSession = 3,
			Note = "Tool Refill (Shield x5) if Shield charges = 0, else Skip Segment; A/B Shield-first vs Skip-first",
		},
		{
			Id = "FallsFive",
			Type = "FallsOnSegment",
			Params = { Falls = 5 },
			Offers = { "SkipSegment" },
			CapPerSession = 3,
		},
		{
			Id = "FallsEight",
			Type = "FallsOnSegment",
			Params = { Falls = 8 },
			Offers = { "SkipFiveSegments" },
			CapPerSession = 2,
		},
		{
			Id = "ClockLow",
			Type = "ClockLeft",
			Params = { SecondsLeft = 60, MinSlotsFromFinish = 3 },
			Offers = { "PlusTwoMinutes", "SkipFiveSegments" },
			CapPerSession = 1,
		},
		{
			Id = "StarterPackCheckpoint1",
			Type = "Checkpoint",
			Params = { Checkpoint = 1, FirstSessionOnly = true },
			Offers = { "StarterPack" },
			CapPerSession = 1,
		},
		{
			Id = "StarterPackReminder",
			Type = "StarterPackTimeLeft",
			Params = { SecondsLeft = 120 },
			Offers = { "StarterPack" },
			CapPerSession = 1,
		},
		{
			Id = "WheelNoSpins",
			Type = "WheelOpenedEmpty",
			Offers = { "Spins1", "Spins5", "Spins15" },
			CapPerSession = 2,
			RequiresPaidRandomAllowed = true,
		},
		{
			Id = "LockedItemViewed",
			Type = "LockedBallOrToolViewed",
			Offers = { "Coins", "RobuxUnlock" },
			CapPerSession = 0,
			Inline = true,
		},
		{ Id = "ToolNoCharges", Type = "ToolPressedEmpty", Offers = { "ToolRefill" }, CapPerSession = 2 },
		{ Id = "StreakBroken", Type = "StreakBroken", Offers = { "RestoreDailyStreak" }, CapPerSession = 1 },
		{
			Id = "GiftsWaiting",
			Type = "TimedGiftsWaiting",
			Params = { Count = 3 },
			Offers = { "UnlockAllTimedGifts" },
			CapPerSession = 1,
		},
		{
			Id = "LimitedLow",
			Type = "LimitedStock",
			Params = { Below = 100, ToastIntervalSeconds = 600 },
			Offers = { "CrownOfHell" },
			CapPerSession = 1,
			ServerToast = true,
		},
		{
			Id = "TrickPremiumPreview",
			Type = "TrickPremiumWouldScore",
			Params = { MinExtraFraction = 0.5, ReplanTrickId = "corkscrew" },
			Offers = { "TrickPack" },
			CapPerSession = 1,
			Toast = true,
		},
		{
			Id = "TrickCoinsNearCap",
			Type = "ResultsTrickCoins",
			Params = { MinCoins = 20 },
			Offers = { "TrickCoins2x" },
			CapPerSession = 1,
			RequiresNoPass = "TrickCoins2x",
			ResultsCard = true,
		},
		{
			Id = "LockedTrickViewed",
			Type = "LockedTrickViewed",
			Offers = { "Coins", "RobuxUnlock" },
			CapPerSession = 0,
			Inline = true,
		},
		{
			Id = "SeasonPremiumTier",
			Type = "SeasonLockedPremiumTier",
			Params = { NthLockedTiers = { 1, 10, 20, 30 } },
			Offers = { "SeasonPremiumPass" },
			CapPerSession = 2,
		},
		{
			Id = "SeasonEndDay",
			Type = "SeasonTimeLeft",
			Params = { SecondsLeft = 24 * 3600, MinTier = 10, RequiresNotPremium = true },
			Offers = { "SeasonPremiumPass", "SeasonEndingTenTiers" },
			CapPerSession = 1,
		},
		{
			Id = "SeasonTier40NoPremium",
			Type = "SeasonTier40",
			Offers = { "SeasonPremiumPass" },
			CapPerSession = 1,
			Preview = "moltenmonarch",
		},
		{
			Id = "SeasonBehindPace",
			Type = "SeasonBehindPace",
			Params = { DaysBehind = 5, LastDays = 7 },
			Offers = { "SeasonEndingTenTiers" },
			CapPerSession = 1,
		},
	},
}

return UpsellTable
