-- PhysicsTable
-- Constants for the stat -> physics mapping (GDD 3): rating 5 equals the reference BallSystem values.
-- Read by BallStats.Resolve (shared), BallService speed audit and ModifierService. Formulas live in code:
--   multiplier(r) = Base + PerRating * r; MaxForce = Anchor.MaxForce * Speed multiplier (and so on).

local PhysicsTable = {
	Anchor = { -- values at rating 5
		MaxForce = 0.12,
		SmoothMoveRate = 10,
		AirMoveRate = 6,
		JumpPower = 0.25,
		SmoothStopRate = 6, -- same for every ball
	},
	DoubleJumpPowerMultiplier = 1.1,

	-- PLACEHOLDER: set by the M1 feel test. Horizontal studs/s of a ball at the anchor MaxForce (0.12) on flat ground.
	-- BallMotion targets MaxForce / Anchor.MaxForce * this, and BallService's speed audit scales its limit from it,
	-- so client feel and server limit can never drift apart.
	AnchorTopSpeed = 40,
	-- PLACEHOLDER (M1 feel test): vertical studs/s per point of JumpPower (0.25 at rating 5 -> 50 studs/s, ~6.4 stud hop).
	JumpVelocityScale = 200,

	Curves = {
		Speed = { Base = 0.80, PerRating = 0.04 }, -- drives MaxForce
		Acceleration = { Base = 0.60, PerRating = 0.08 }, -- drives SmoothMoveRate and AirMoveRate
		Jump = { Base = 0.85, PerRating = 0.03 }, -- drives JumpPower
	},

	-- Applied after the stat curve, in this order, all multiplying MaxForce.
	Modifiers = {
		TurboMaxForce = 1.10, -- Turbo pass
		SlowEveryoneMaxForce = 0.70, -- troll product while active
	},

	Gravity = {
		Default = 196.2,
		MinFraction = 0.4, -- floor for stacked gravity multipliers
	},

	Ball = {
		FolderName = "Balls", -- workspace container for live balls; BallService creates it at runtime
	},

	Obstacles = {
		BoostPanel = { BoostSpeed = 1.6, Duration = 2, TweenSeconds = 0.5 }, -- BoostSpeed multiplies MaxForce
		JumpPad = { JumpPower = 0.40 },
	},

	-- BallService speed audit (GDD 3).
	SpeedAudit = {
		Tolerance = 1.25, -- allowed multiple of expected top speed
		BoostGraceSeconds = 0.5,
		StrikeSamples = 3, -- over-limit samples within StrikeWindowSeconds make one strike
		StrikeWindowSeconds = 2,
		SampleSeconds = 0.1, -- the single 10 Hz audit loop
		BoostProximityStuds = 12, -- a ball this close to a BoostPanel / JumpPad part counts as boosted
		PositionTolerance = 1.1, -- measured speed between samples may exceed the limit by this multiple
		LimitDropGraceSeconds = 1.5, -- no strikes after the allowed top speed drops (SlowEveryone, pass change)
	},
}

return PhysicsTable
