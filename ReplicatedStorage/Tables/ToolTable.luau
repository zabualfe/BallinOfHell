-- ToolTable
-- The 9 gameplay tools (GDD 6) with effect constants, plus loadout and charge rules.
-- Read by ToolService and its Tools/ plug-ins (server), ToolController/ToolBarUI (client) and the shop.
-- Stud values are tune-until-V5-is-measured. Robux unlock price comes from ProductTable by rarity (ToolUnlock<Rarity>).
-- Cooldown 0 on pocket means "1 per segment" instead of a timer.

local ToolTable = {
	Config = {
		Slots = 2,
		SlotsWithToolBelt = 3, -- PassTable.ToolBelt
		GlobalCooldown = 2, -- seconds between any two activations
		UseRateLimit = 4, -- UseTool messages per second
		ChargeCap = 99,
		ClientRollbackSeconds = 0.3,
		DefaultEquipped = { "shield", "", "" },
		UnlockedConvertsToCharges = 10, -- owned unlock in a bundle or track becomes this many stored charges
		CoinRefill = { Coins = 100, Charges = 3, MaxPerToolPerRound = 1 }, -- owned tools only
		UnlimitedPass = { PassKey = "UnlimitedRockets", ToolId = "rocket" }, -- removes the free-charge limit only
		ShieldRescueSampleSeconds = 0.5,
		ShieldRescueMinKillBrickDistance = 3, -- studs
	},

	Tools = {
		brake = {
			Name = "Brake Anchor",
			Rarity = "Common",
			Order = 1,
			Cooldown = 8,
			FreeCharges = 3,
			Price = 300,
			StopRateMultiplier = 4,
			StopSeconds = 1.0, -- SmoothStopRate x4 after zeroing horizontal velocity
		},
		spring = {
			Name = "Super Spring",
			Rarity = "Common",
			Order = 2,
			Cooldown = 15,
			FreeCharges = 2,
			Price = 500,
			JumpPowerMultiplier = 1.6,
			GroundedOnly = true,
		},
		rocket = {
			Name = "Rocket Burst",
			Rarity = "Common",
			Order = 3,
			Cooldown = 10,
			FreeCharges = 3,
			Price = 600,
			SpeedMultiplier = 1.6,
			HoldSeconds = 0.6,
			GraceSeconds = 0.5, -- audit grace after the hold
		},
		coil = {
			Name = "Gravity Coil",
			Rarity = "Rare",
			Order = 4,
			Cooldown = 25,
			FreeCharges = 2,
			Price = 1200,
			GravityMultiplier = 0.6,
			Duration = 6,
		},
		glider = {
			Name = "Glider",
			Rarity = "Rare",
			Order = 5,
			Cooldown = 20,
			FreeCharges = 2,
			Price = 1400,
			FallSpeedCap = 18,
			AirMoveRateMultiplier = 1.5,
			MaxDuration = 4,
			AirborneOnly = true,
		},
		shield = {
			Name = "Shield Bubble",
			Rarity = "Rare",
			Order = 6,
			Cooldown = 30,
			FreeCharges = 1,
			Price = 1500,
			Duration = 20,
			InvulnerableSeconds = 0.5, -- absorbs one KillBrick touch or one fall
		},
		grapple = {
			Name = "Grapple Hook",
			Rarity = "Epic",
			Order = 7,
			Cooldown = 12,
			FreeCharges = 3,
			Price = 3500,
			Range = 60,
			ConeDegrees = 30,
			PullSpeed = 80,
			MaxPullSeconds = 1.5,
			GraceSeconds = 0.5, -- audit grace after the pull: the ball keeps its pull momentum on release
		},
		timeslow = {
			Name = "Time Slow",
			Rarity = "Epic",
			Order = 8,
			Cooldown = 40,
			FreeCharges = 1,
			Price = 4000,
			Duration = 5,
			Radius = 80,
			SpeedMultiplier = 0.5, -- client-side, for the user only
		},
		pocket = {
			Name = "Pocket Checkpoint",
			Rarity = "Legendary",
			Order = 9,
			Cooldown = 0,
			FreeCharges = 2,
			Price = 8000,
			PerSegmentLimit = 1,
			BannedTiers = { "Hell", "Finale" },
		},
	},
}

return ToolTable
