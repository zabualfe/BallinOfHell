-- ModifierTable
-- Server-wide paid modifiers and trolls, plus troll rules (GDD 11.3). Product keys match ProductTable.
-- Read by ModifierService (sets workspace attributes, owns queue/cooldowns) and the banner UI.
-- Durations and cooldowns are seconds. MaxPerRound counts activations; StackMaxSeconds caps remaining time when re-bought while active.
-- SlowEveryone's MaxForce factor is PhysicsTable.Modifiers.SlowEveryoneMaxForce.

local ModifierTable = {
	Modifiers = {
		LowGravity = {
			Name = "Low Gravity",
			Kind = "Server",
			Gravity = 110,
			Duration = 60,
			Cooldown = 30,
			MaxPerRound = 3,
			StackMaxSeconds = 120,
		},
		DoubleJumpForAll = {
			Name = "Double Jump for All",
			Kind = "Server",
			Duration = 120,
			Cooldown = 30,
			MaxPerRound = 3,
			StackMaxSeconds = 240,
		},
		GiantBalls = {
			Name = "Giant Balls",
			Kind = "Server",
			Scale = 2,
			Duration = 60,
			Cooldown = 30,
			MaxPerRound = 3,
			StackMaxSeconds = 120,
		},
		PlusTwoMinutes = {
			Name = "+2 Min Round Time",
			Kind = "Server",
			AddClockSeconds = 120,
			Duration = 0,
			Cooldown = 60,
			MaxPerRound = 3,
			MaxRaceClockSeconds = 26 * 60, -- stops adding past this much total clock
		},
		ShrinkEveryone = {
			Name = "Shrink Everyone",
			Kind = "Troll",
			Scale = 0.5,
			Duration = 15,
			BeatsGiant = true,
		},
		SlowEveryone = {
			Name = "Slow Everyone",
			Kind = "Troll",
			Duration = 15,
		},
	},

	TrollRules = {
		ServerCooldown = 90, -- after any troll
		MaxPerRound = 4, -- trolls total
		PerPlayerIntervalSeconds = 180,
		NewPlayerImmunitySeconds = 600, -- first 10 min of first session (pending Director, GDD 14 Q4)
		BuyerImmune = true,
		FinaleImmune = true, -- players on slot 30
		CanExtend = false,
		BlockedWhileTrollActive = true,
	},

	QueuedStartDelayNextRace = 5, -- paid effect blocked by cap/cooldown is queued, never dropped
}

return ModifierTable
