-- BallStats
-- Pure stat -> physics mapping (GDD 3) and the server speed-audit limit. No Instances, no side effects.
-- Used by BallService (writes the result as attributes on the ball model) and BallController (reads them);
-- constants come from Tables/PhysicsTable, ratings from Tables/BallTable. Nothing is rounded.
--
--   BallStats.Resolve(stats, passes, modifiers) -> resolved
--   BallStats.ForBall(ballId, passes, modifiers) -> resolved   (errors on an unknown id)
--   BallStats.MaxAllowedSpeed(resolved, context) -> number     (studs/s, horizontal)
--
-- stats      { Speed = 1-10, Acceleration = 1-10, Jump = 1-10 }; errors if missing or out of range.
-- passes     set of owned pass keys (PassTable), e.g. { Turbo = true }. Read: Turbo, DoubleJump.
-- modifiers  set of active server-wide modifier keys (ModifierTable), e.g. { LowGravity = true }.
--            Read: SlowEveryone, LowGravity, GiantBalls, ShrinkEveryone, DoubleJumpForAll.
--            Shrink beats Giant when both are active (ModifierTable BeatsGiant).
--
-- Resolved keys are the ball-model attribute names (the BallService <-> BallController contract):
--   MaxForce          force scale of the roll; reference 0.12 at rating 5. Turbo x1.10, then SlowEveryone x0.70.
--   SmoothMoveRate    1/s, ground acceleration blend rate; 10 at rating 5.
--   AirMoveRate       1/s, air acceleration blend rate; 6 at rating 5.
--   SmoothStopRate    1/s, stop blend rate; 6 for every ball.
--   JumpPower         jump impulse scale; 0.25 at rating 5.
--   DoubleJumpPower   JumpPower of the second jump (JumpPower x1.1).
--   DoubleJumpEnabled boolean; true with the DoubleJump pass or DoubleJumpForAll.
--   Gravity           studs/s^2 for this ball's controller; 196.2 default, floored at 0.4 x default.
--   Scale             ball size multiplier; 1 normal, 2 Giant Balls, 0.5 Shrink Everyone.
--   SpeedRating, AccelerationRating, JumpRating   the 1-10 inputs, for UI and debugging.
--
-- MaxAllowedSpeed context (all optional except AnchorTopSpeed):
--   AnchorTopSpeed  studs/s a ball with the anchor MaxForce (0.12) reaches on flat ground; measured in the M1 feel
--                   test. Top speed is assumed linear in MaxForce.
--   Boosting        true during a boost panel window plus its grace (caller adds PhysicsTable SpeedAudit grace).
--   Rocketing       true during Rocket Burst hold plus ToolTable rocket GraceSeconds.
--   Grappling       true while pulled by the Grapple Hook.
-- Boost and rocket do not stack: the larger multiplier wins. The result already includes the 1.25 tolerance.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tables = ReplicatedStorage.Tables
local PhysicsTable = require(Tables.PhysicsTable)
local BallTable = require(Tables.BallTable)
local ToolTable = require(Tables.ToolTable)
local ModifierTable = require(Tables.ModifierTable).Modifiers

local MIN_RATING = 1
local MAX_RATING = 10

local BallStats = {}

local function curve(spec, rating)
	return spec.Base + spec.PerRating * rating
end

local function checkRating(stats, key)
	local rating = type(stats) == "table" and stats[key]
	if type(rating) ~= "number" or rating < MIN_RATING or rating > MAX_RATING then
		error(`BallStats: {key} must be a number from {MIN_RATING} to {MAX_RATING}, got {tostring(rating)}`, 3)
	end
	return rating
end

function BallStats.Resolve(stats, passes, modifiers)
	passes = passes or {}
	modifiers = modifiers or {}

	local speed = checkRating(stats, "Speed")
	local acceleration = checkRating(stats, "Acceleration")
	local jump = checkRating(stats, "Jump")

	local anchor = PhysicsTable.Anchor
	local curves = PhysicsTable.Curves
	local accelerationMultiplier = curve(curves.Acceleration, acceleration)

	-- Order matters for float equality: stat, then Turbo, then Slow Everyone.
	local maxForce = anchor.MaxForce * curve(curves.Speed, speed)
	if passes.Turbo then
		maxForce *= PhysicsTable.Modifiers.TurboMaxForce
	end
	if modifiers.SlowEveryone then
		maxForce *= PhysicsTable.Modifiers.SlowEveryoneMaxForce
	end

	local jumpPower = anchor.JumpPower * curve(curves.Jump, jump)

	local gravity = PhysicsTable.Gravity.Default
	if modifiers.LowGravity then
		gravity = ModifierTable.LowGravity.Gravity
	end
	gravity = math.max(gravity, PhysicsTable.Gravity.Default * PhysicsTable.Gravity.MinFraction)

	local scale = 1
	if modifiers.ShrinkEveryone then
		scale = ModifierTable.ShrinkEveryone.Scale
	elseif modifiers.GiantBalls then
		scale = ModifierTable.GiantBalls.Scale
	end

	return {
		MaxForce = maxForce,
		SmoothMoveRate = anchor.SmoothMoveRate * accelerationMultiplier,
		AirMoveRate = anchor.AirMoveRate * accelerationMultiplier,
		SmoothStopRate = anchor.SmoothStopRate,
		JumpPower = jumpPower,
		DoubleJumpPower = jumpPower * PhysicsTable.DoubleJumpPowerMultiplier,
		DoubleJumpEnabled = (passes.DoubleJump or modifiers.DoubleJumpForAll) and true or false,
		Gravity = gravity,
		Scale = scale,
		SpeedRating = speed,
		AccelerationRating = acceleration,
		JumpRating = jump,
	}
end

function BallStats.ForBall(ballId, passes, modifiers)
	local ball = BallTable[ballId]
	if not ball then
		error(`BallStats: unknown ball id {tostring(ballId)}`, 2)
	end
	return BallStats.Resolve(ball, passes, modifiers)
end

function BallStats.MaxAllowedSpeed(resolved, context)
	local anchorTopSpeed = context and context.AnchorTopSpeed
	if type(anchorTopSpeed) ~= "number" or anchorTopSpeed <= 0 then
		error("BallStats.MaxAllowedSpeed: context.AnchorTopSpeed (studs/s) is required", 2)
	end

	local normal = anchorTopSpeed * resolved.MaxForce / PhysicsTable.Anchor.MaxForce
	local multiplier = 1
	if context.Boosting then
		multiplier = math.max(multiplier, PhysicsTable.Obstacles.BoostPanel.BoostSpeed)
	end
	if context.Rocketing then
		multiplier = math.max(multiplier, ToolTable.Tools.rocket.SpeedMultiplier)
	end

	local expected = normal * multiplier
	if context.Grappling then
		expected = math.max(expected, ToolTable.Tools.grapple.PullSpeed)
	end
	return expected * PhysicsTable.SpeedAudit.Tolerance
end

return BallStats
