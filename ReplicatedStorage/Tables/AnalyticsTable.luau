-- AnalyticsTable
-- Every analytics name from GDD 12 so all callers share the same strings. AnalyticsService reads it.
-- Funnels: Steps are ordered, a step's number is its position. Type "Onboarding" uses Roblox's onboarding
-- funnel API; "Standard" uses LogFunnelStepEvent. Prefix funnels match by name prefix (Season_<id>).
-- OnceEver = step must count once per player across sessions (see AnalyticsService header for how).

local AnalyticsTable = {
	Funnels = {
		Onboarding = {
			Type = "Onboarding",
			OnceEver = true,
			Steps = {
				"Joined",
				"StarterPicked",
				"Segment1Cleared",
				"FirstFall",
				"PresentClaimed",
				"FirstToolUsed",
				"FirstTrickLanded",
				"Checkpoint5",
				"Checkpoint10",
				"FirstRoundEnded",
				"FirstShopPurchase",
				"SecondSession",
			},
		},
		Season = {
			Type = "Standard",
			Prefix = "Season_", -- funnel name is Season_<id>; once per player per season
			Steps = { "ScreenOpened", "Tier1", "Tier5", "Tier10", "Tier20", "Tier30", "Tier40", "PremiumBought" },
		},
		Purchase = {
			Type = "Standard",
			Qualified = true, -- pass the product id as the qualifier so each product has its own funnel run
			Steps = { "OfferShown", "OfferTapped", "PromptShown", "ReceiptGranted" },
		},
		Round = {
			Type = "Standard",
			Steps = {
				"RaceStarted",
				"Checkpoint5",
				"Checkpoint10",
				"Checkpoint15",
				"Checkpoint20",
				"Checkpoint25",
				"Checkpoint29",
				"Finished",
			},
		},
	},

	Currency = "Coins",

	-- Economy: flow type is "Source" or "Sink"; transaction types per GDD 12.2.
	Flow = { Source = "Source", Sink = "Sink" },
	Transaction = {
		Gameplay = "Gameplay", -- checkpoint, finish, Tricks
		SeasonPass = "SeasonPass", -- sku SeasonTier_<n>_<Free|Premium>, SeasonBonusChest
		TimedReward = "TimedReward", -- daily, timed, wheel, present
		IAP = "IAP", -- coin packs, Starter Pack
		Onboarding = "Onboarding", -- present
		Shop = "Shop", -- ball, tool, refill, trick, trick upgrade
	},

	Events = {
		SegmentFall = "SegmentFall",
		SegmentClear = "SegmentClear",
		SegmentSkip = "SegmentSkip",
		ToolUsed = "ToolUsed",
		ToolDenied = "ToolDenied",
		ToolSavedFall = "ToolSavedFall",
		WheelSpin = "WheelSpin",
		UpsellShown = "UpsellShown",
		UpsellClosed = "UpsellClosed",
		ModifierActivated = "ModifierActivated",
		AntiCheatFlag = "AntiCheatFlag",
		RoundEnd = "RoundEnd",
		TrickRoundSummary = "TrickRoundSummary",
		TrickRejected = "TrickRejected",
		TrickPurchased = "TrickPurchased",
		TrickUpgraded = "TrickUpgraded",
		SeasonTierReached = "SeasonTierReached",
		SeasonRewardClaimed = "SeasonRewardClaimed",
		SeasonPremiumBought = "SeasonPremiumBought",
		SeasonTiersBought = "SeasonTiersBought",
		ChallengeCompleted = "ChallengeCompleted",
		ChallengeRerolled = "ChallengeRerolled",
		SeasonClosed = "SeasonClosed",
		StarterPackPartialGrant = "StarterPackPartialGrant",
		LimitedSold = "LimitedSold",
		LimitedConsolation = "LimitedConsolation",
	},
}

return AnalyticsTable
