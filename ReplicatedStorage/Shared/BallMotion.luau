-- BallMotion
-- Pure movement maths for the client-owned ball (ported from the reference BallSystem:Update / Jump). No Instances,
-- no side effects; BallController feeds it velocities and ball attributes (the BallStats contract) once per frame.
--
--   BallMotion.TargetSpeed(attrs, speedMultiplier?, grounded?) -> studs/s   -- airborne: x AirTopSpeedMultiplier
--   BallMotion.DownhillMultiplier(groundNormal?, moveDirection) -> number >= 1   -- PhysicsTable.Slope; 1 if no normal
--   BallMotion.MaxDownhillMultiplier() -> number                                -- at MaxSlopeDegrees, straight down
--   BallMotion.Step(velocity, moveDirection, grounded, attrs, dt, options?) -> Vector3
--       options { SpeedMultiplier = 1, SlopeMultiplier = 1, CanControl = true, CanStop = true }
--       SlopeMultiplier (from DownhillMultiplier) scales the target speed on the ground only.
--       Moving: horizontal velocity blends toward moveDirection * target speed (SmoothMoveRate toward the ground top
--       speed on the ground; AirMoveRate toward the faster air top speed in the air). Not moving on the ground:
--       horizontal speed drops by PhysicsTable.GroundDeceleration per second until it rolls to a stop. Not moving in
--       the air: momentum is kept. Y is never touched.
--   BallMotion.NewJumpState() / UpdateJumpState(state, rawGrounded, dt) -> grounded / RequestJump(state, doubleJumpEnabled)
--       -> "Jump" | "DoubleJump" | nil
--   BallMotion.MarkLaunched(state)                  -- after a jump pad
--   BallMotion.ApplyLaunch(velocity, jumpPower) -> Vector3
--   BallMotion.ApplyJump(velocity, kind, attrs) -> Vector3     -- velocity-set jump, only Y changes
--
--   BallMotion.StopStep(velocity, stopRate, dt) -> Vector3             -- Brake: horizontal blend to zero at stopRate, any ground state
--   BallMotion.CapFallSpeed(velocity, cap) -> Vector3                  -- Glider: Y never below -cap
--   BallMotion.PullVelocity(position, target, speed, dt) -> Vector3, arrived   -- Grapple: straight at the anchor
--   BallMotion.ClampHorizontal(velocity, maxSpeed) -> Vector3          -- Grapple release keeps momentum up to top speed
--
-- Speed and jump velocity are mass independent (PhysicsTable.AnchorTopSpeed / JumpVelocityScale) so the server
-- speed audit can use the same numbers. Giant/Shrink scale does not change speed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PhysicsTable = require(ReplicatedStorage.Tables.PhysicsTable)

local BallMotion = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local MIN_DT = 1e-4 -- seconds
local MAX_DT = 0.1 -- seconds, a hitch must not slingshot the blend
local MOVE_EPSILON = 1e-3 -- input magnitude below this counts as no input
local COYOTE_SECONDS = 0.1 -- ground jump still allowed this long after leaving the ground
local ARRIVE_RADIUS = 3 -- studs from a grapple anchor that count as arrived
local JUMP_LOCKOUT_SECONDS = 0.15 -- ground check is ignored this long after a jump so it can't reset the jump state

local function blend(current, target, rate, dt)
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

function BallMotion.TargetSpeed(attrs, speedMultiplier, grounded)
	local airMultiplier = if grounded == false then PhysicsTable.AirTopSpeedMultiplier else 1
	return attrs.MaxForce
		* (PhysicsTable.AnchorTopSpeed / PhysicsTable.Anchor.MaxForce)
		* (speedMultiplier or 1)
		* airMultiplier
end

local function slopeSine(slopeDegrees)
	return math.sin(math.rad(math.clamp(slopeDegrees, 0, PhysicsTable.Slope.MaxSlopeDegrees)))
end

function BallMotion.MaxDownhillMultiplier()
	return 1 + PhysicsTable.Slope.DownhillSpeedPerSlope * slopeSine(PhysicsTable.Slope.MaxSlopeDegrees)
end

function BallMotion.DownhillMultiplier(groundNormal, moveDirection)
	if typeof(groundNormal) ~= "Vector3" then
		return 1
	end
	-- The surface normal leans toward downhill, so its flat part is the downhill direction.
	local downhill = Vector3.new(groundNormal.X, 0, groundNormal.Z)
	local flatMove = Vector3.new(moveDirection.X, 0, moveDirection.Z)
	if downhill.Magnitude < MOVE_EPSILON or flatMove.Magnitude < MOVE_EPSILON then
		return 1
	end
	local alignment = flatMove.Unit:Dot(downhill.Unit)
	if alignment <= 0 then
		return 1
	end
	local slopeDegrees = math.deg(math.acos(math.clamp(groundNormal.Unit.Y, -1, 1)))
	return 1 + PhysicsTable.Slope.DownhillSpeedPerSlope * slopeSine(slopeDegrees) * alignment
end

function BallMotion.Step(velocity, moveDirection, grounded, attrs, dt, options)
	dt = math.clamp(dt, MIN_DT, MAX_DT)
	local canControl = not options or options.CanControl ~= false
	local canStop = not options or options.CanStop ~= false

	local flat = Vector3.new(moveDirection.X, 0, moveDirection.Z)
	if flat.Magnitude > MOVE_EPSILON then
		if not canControl then
			return velocity
		end
		local speed = BallMotion.TargetSpeed(attrs, options and options.SpeedMultiplier, grounded)
		if grounded and options and options.SlopeMultiplier then
			speed *= options.SlopeMultiplier
		end
		local target = flat * speed
		if target.Magnitude > speed and speed > 0 then
			target = target.Unit * speed
		end
		local rate = if grounded then attrs.SmoothMoveRate else attrs.AirMoveRate
		return Vector3.new(blend(velocity.X, target.X, rate, dt), velocity.Y, blend(velocity.Z, target.Z, rate, dt))
	end

	if grounded and canStop then
		local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
		local speed = horizontal.Magnitude
		local slowed = math.max(speed - PhysicsTable.GroundDeceleration * dt, 0)
		if slowed <= 0 then
			return Vector3.new(0, velocity.Y, 0)
		end
		local kept = horizontal * (slowed / speed)
		return Vector3.new(kept.X, velocity.Y, kept.Z)
	end

	return velocity
end

function BallMotion.StopStep(velocity, stopRate, dt)
	local keep = math.exp(-stopRate * math.clamp(dt, MIN_DT, MAX_DT))
	return Vector3.new(velocity.X * keep, velocity.Y, velocity.Z * keep)
end

function BallMotion.CapFallSpeed(velocity, cap)
	if velocity.Y < -cap then
		return Vector3.new(velocity.X, -cap, velocity.Z)
	end
	return velocity
end

-- Arrived once the next step would reach (or is within ARRIVE_RADIUS of) the target.
function BallMotion.PullVelocity(position, target, speed, dt)
	local offset = target - position
	local distance = offset.Magnitude
	if distance <= math.max(ARRIVE_RADIUS, speed * math.clamp(dt, MIN_DT, MAX_DT)) then
		return Vector3.zero, true
	end
	return offset.Unit * speed, false
end

function BallMotion.ClampHorizontal(velocity, maxSpeed)
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	if flat.Magnitude <= maxSpeed then
		return velocity
	end
	local limited = flat.Unit * maxSpeed
	return Vector3.new(limited.X, velocity.Y, limited.Z)
end

function BallMotion.NewJumpState()
	return { AirTime = 0, Jumped = false, AirJumpUsed = false, Lockout = 0 }
end

-- Returns the effective grounded flag (false during the post-jump lockout).
function BallMotion.UpdateJumpState(state, rawGrounded, dt)
	local grounded = rawGrounded
	if state.Lockout > 0 then
		state.Lockout = math.max(0, state.Lockout - dt)
		grounded = false
	end
	if grounded then
		state.AirTime = 0
		state.Jumped = false
		state.AirJumpUsed = false
	else
		state.AirTime += dt
	end
	return grounded
end

function BallMotion.RequestJump(state, doubleJumpEnabled)
	if not state.Jumped and state.AirTime <= COYOTE_SECONDS then
		state.Jumped = true
		state.AirTime = math.huge -- no second ground jump until landing
		state.Lockout = JUMP_LOCKOUT_SECONDS
		return "Jump"
	end
	if doubleJumpEnabled and not state.AirJumpUsed then
		state.AirJumpUsed = true
		state.Jumped = true
		return "DoubleJump"
	end
	return nil
end

-- A jump pad launch counts as having jumped, so a double jump may still follow.
function BallMotion.MarkLaunched(state)
	state.Jumped = true
	state.AirTime = math.huge
	state.Lockout = JUMP_LOCKOUT_SECONDS
end

-- Vertical launch at jumpPower (a JumpPad's JumpPower, or the ball's own).
function BallMotion.ApplyLaunch(velocity, jumpPower)
	return Vector3.new(velocity.X, jumpPower * PhysicsTable.JumpVelocityScale, velocity.Z)
end

function BallMotion.ApplyJump(velocity, kind, attrs)
	return BallMotion.ApplyLaunch(velocity, if kind == "DoubleJump" then attrs.DoubleJumpPower else attrs.JumpPower)
end

return BallMotion
