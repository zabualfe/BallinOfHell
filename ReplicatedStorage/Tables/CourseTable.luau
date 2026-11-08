-- CourseTable
-- Difficulty tiers, the 30-slot tier order, segment picker rules and checkpoint/anti-cheat tuning (GDD 5).
-- Read by CourseService, SegmentPicker, ProgressService, ToolService (tool caps), TrickService (segment caps) and SegmentTest.
-- Tier lookups are by name; Slots[n] names the tier of slot n. ToolCap/ToolsAllowed absent = no cap.

local CourseTable = {
	SlotCount = 30,
	CheckpointCount = 29, -- every joint; slot 30 ends at the finish

	Tiers = {
		Beginner = {
			Order = 1,
			Themes = { "Ash Wastes" },
			ParTime = 12,
			MinPathWidth = 16,
			CheckpointCoins = 2,
			Obstacles = { "BoostPanel", "JumpPad", "KillBrick" }, -- KillBricks on edges only
		},
		Easy = {
			Order = 2,
			Themes = { "Ash Wastes", "Brimstone Caves" },
			ParTime = 15,
			MinPathWidth = 12,
			CheckpointCoins = 3,
			Obstacles = { "BoostPanel", "JumpPad", "KillBrick", "Rotating", "Moving" }, -- Rotating slow
		},
		Medium = {
			Order = 3,
			Themes = { "Brimstone Caves", "Lava Falls" },
			ParTime = 18,
			MinPathWidth = 10,
			CheckpointCoins = 4,
			Obstacles = { "BoostPanel", "JumpPad", "KillBrick", "Rotating", "Moving" }, -- KillBrick floors, faster Rotating
		},
		Hard = {
			Order = 4,
			Themes = { "Lava Falls", "Bone Yard" },
			ParTime = 22,
			MinPathWidth = 8,
			CheckpointCoins = 5,
			Obstacles = { "BoostPanel", "JumpPad", "KillBrick", "Rotating", "Moving", "Vanishing" },
			ToolCap = 3,
		},
		Insane = {
			Order = 5,
			Themes = { "Bone Yard", "Inferno Forge" },
			ParTime = 26,
			MinPathWidth = 6,
			CheckpointCoins = 7,
			Obstacles = { "BoostPanel", "JumpPad", "KillBrick", "Rotating", "Moving", "Vanishing" },
			ToolCap = 2, -- combined
		},
		Hell = {
			Order = 6,
			Themes = { "Soul Abyss" },
			ParTime = 30,
			MinPathWidth = 5,
			CheckpointCoins = 10,
			Obstacles = { "BoostPanel", "JumpPad", "KillBrick", "Rotating", "Moving", "Vanishing" },
			ToolCap = 1, -- fast timings
			BansPocketCheckpoint = true,
		},
		Finale = {
			Order = 7,
			Themes = { "Throne of Embers" },
			ParTime = 40,
			MinPathWidth = 5,
			CheckpointCoins = 0, -- pays the finish reward (EconomyTable.Finish) instead
			Obstacles = { "BoostPanel", "JumpPad", "KillBrick", "Rotating", "Moving", "Vanishing" }, -- signature set-piece
			ToolCap = 1,
			NoSkips = true,
			BansPocketCheckpoint = true,
		},
	},

	-- Tier of each slot, in order: 1-4 Beginner, 5-9 Easy, 10-15 Medium, 16-21 Hard, 22-27 Insane, 28-29 Hell, 30 Finale.
	Slots = {
		"Beginner",
		"Beginner",
		"Beginner",
		"Beginner",
		"Easy",
		"Easy",
		"Easy",
		"Easy",
		"Easy",
		"Medium",
		"Medium",
		"Medium",
		"Medium",
		"Medium",
		"Medium",
		"Hard",
		"Hard",
		"Hard",
		"Hard",
		"Hard",
		"Hard",
		"Insane",
		"Insane",
		"Insane",
		"Insane",
		"Insane",
		"Insane",
		"Hell",
		"Hell",
		"Finale",
	},

	Themes = {
		"Ash Wastes",
		"Brimstone Caves",
		"Lava Falls",
		"Bone Yard",
		"Inferno Forge",
		"Soul Abyss",
		"Throne of Embers",
	},

	Picker = {
		MaxToolRequiredPerCourse = 3,
		AllowAdjacentToolRequired = false,
		AvoidLastRoundSameSlot = true, -- soft rule
		AllowAdjacentReuse = false, -- pool fallback: reuse least-recently-used, never in adjacent slots
		DefaultWeight = 1,
		PoolSize = {
			Prototype = { Beginner = 4, Easy = 4, Medium = 3, Hard = 3, Insane = 3, Hell = 2, Finale = 1 },
			Launch = { Beginner = 6, Easy = 7, Medium = 8, Hard = 8, Insane = 8, Hell = 5, Finale = 3 },
		},
	},

	-- Authoring/validation numbers used by CourseService and SegmentTest.
	Segment = {
		WeightMin = 0.25,
		WeightMax = 3,
		ParTimeTolerance = 0.25, -- +-25% of the tier ParTime
		EndPartLevelDegrees = 2,
		FallVolumePadding = 10, -- studs added to the bounding box
		MaxNoToolsPerTier = 1,
		ToolRequiredAllowed = { "grapple", "glider", "spring" },
		LengthParFraction = 0.7, -- path length = ParTime * this * V5
		V5 = 40, -- studs/s top speed of a Speed-5 ball (tune: M1 measures it)
		TestBallStats = 1, -- SegmentTest forces 1/1/1
		FirstBeginnerSlotsWithoutMainPathKillBrick = 2,
	},

	-- ProgressService (GDD 5.7).
	Progress = {
		CheckpointRange = 20, -- studs
		MinParFraction = 0.35,
		MinParFractionWithMovementTool = 0.25,
		MovementTools = { "rocket", "grapple", "glider", "spring", "coil" },
		StrikesPerRound = 5, -- then the player returns to the last valid checkpoint (AntiCheatFlag)
		RespawnSeconds = 1.5,
		RespawnFadeSeconds = 0.3,
		YFloorBelowLowestSegment = 200, -- studs
	},
}

return CourseTable
