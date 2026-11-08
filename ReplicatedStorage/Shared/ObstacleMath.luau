-- ObstacleMath
-- Pure maths and attribute validation for client obstacles (GDD 5.4). No Instances, no engine calls, so it is specced.
-- Used by ObstacleController and its tag modules.
--
--   ObstacleMath.Phase(now, period, offset?) -> 0..1          position within a repeating period
--   ObstacleMath.PingPong(phase) -> 0..1..0                   0 at phase 0, 1 at phase 0.5, back to 0 at phase 1
--   ObstacleMath.RotationAngle(now, period, direction) -> radians (unbounded turns wrap at 2*pi)
--   ObstacleMath.Vanishing(now, onTime, offTime, phase, fadeTime) -> { Solid = boolean, Transparency = 0..1 }
--   ObstacleMath.BoostMultiplier(t, from, target, hold, tweenTime, ease) -> multiplier, isDone
--       Speed multiplier t seconds after a boost starts: ease from `from` up to `target` over tweenTime, hold for
--       `hold`, ease back to 1 over tweenTime. ease(alpha) -> alpha is injected (TweenService:GetValue at runtime).
--   ObstacleMath.Axis(name) -> Vector3?                       "X" | "Y" | "Z"
--   ObstacleMath.ConfigFor(kind, attributes, defaults?) -> config?, errorMessage?
--       Validates the attribute table for a tag kind. Returns the config with defaults filled in, or nil plus a
--       message naming the bad attribute. Kinds: BoostPanel, JumpPad, Rotating, Moving, Vanishing, GrappleAnchor.
--       BoostPanel BoostSpeed and Duration are clamped down to `defaults` (the PhysicsTable values the audit assumes).
--
-- All times are in seconds. `now` is workspace:GetServerTimeNow() so every client agrees on the phase.

local ObstacleMath = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local MIN_PERIOD = 0.1 -- seconds; below this the motion is a blur and the phase maths loses precision
local MAX_PERIOD = 600 -- seconds
local MAX_OFFSET = 2000 -- studs per axis
local MAX_BOOST_SPEED = 5 -- multiplier of MaxForce
local MAX_JUMP_POWER = 2 -- same scale as the PhysicsTable JumpPower anchor (0.25)
local MAX_DURATION = 30 -- seconds

local EASING_STYLES = {
	Linear = true,
	Sine = true,
	Quad = true,
	Cubic = true,
	Quart = true,
	Quint = true,
	Exponential = true,
	Circular = true,
	Back = true,
	Elastic = true,
	Bounce = true,
}

local AXES = {
	X = Vector3.xAxis,
	Y = Vector3.yAxis,
	Z = Vector3.zAxis,
}

-- ── Motion ──────────────────────────────────────────────────────────────
function ObstacleMath.Phase(now, period, offset)
	return ((now + (offset or 0)) / period) % 1
end

function ObstacleMath.PingPong(phase)
	return 1 - math.abs(2 * phase - 1)
end

function ObstacleMath.RotationAngle(now, period, direction)
	return direction * ObstacleMath.Phase(now, period) * 2 * math.pi
end

-- Solid for the whole on window, fading out over its last fadeTime seconds; gone (and not solid) while off.
function ObstacleMath.Vanishing(now, onTime, offTime, phase, fadeTime)
	local cycle = onTime + offTime
	local t = (now + phase) % cycle
	if t >= onTime then
		return { Solid = false, Transparency = 1 }
	end
	local fadeStart = onTime - math.min(fadeTime, onTime)
	if t <= fadeStart then
		return { Solid = true, Transparency = 0 }
	end
	return { Solid = true, Transparency = (t - fadeStart) / (onTime - fadeStart) }
end

function ObstacleMath.BoostMultiplier(t, from, target, hold, tweenTime, ease)
	if t < tweenTime then
		return from + (target - from) * ease(t / tweenTime), false
	end
	if t < tweenTime + hold then
		return target, false
	end
	local fallen = t - tweenTime - hold
	if fallen < tweenTime then
		return target + (1 - target) * ease(fallen / tweenTime), false
	end
	return 1, true
end

function ObstacleMath.Axis(name)
	return AXES[name]
end

-- ── Validation ──────────────────────────────────────────────────────────
local function readNumber(attributes, name, default, min, max)
	local value = attributes[name]
	if value == nil then
		return default
	end
	if type(value) ~= "number" or value ~= value or value < min or value > max then
		return nil,
			("attribute %s must be a number between %s and %s, got %s"):format(
				name,
				tostring(min),
				tostring(max),
				tostring(value)
			)
	end
	return value
end

local function readOffset(attributes)
	local value = attributes.Offset
	if value == nil then
		return nil, "attribute Offset (Vector3) is required"
	end
	if typeof(value) ~= "Vector3" then
		return nil, ("attribute Offset must be a Vector3, got %s"):format(typeof(value))
	end
	if
		value.Magnitude < 0.01
		or math.abs(value.X) > MAX_OFFSET
		or math.abs(value.Y) > MAX_OFFSET
		or math.abs(value.Z) > MAX_OFFSET
	then
		return nil, ("attribute Offset must be non-zero and within %d studs per axis"):format(MAX_OFFSET)
	end
	return value
end

local VALIDATORS = {}

function VALIDATORS.BoostPanel(attributes, defaults)
	local speed, err = readNumber(attributes, "BoostSpeed", defaults.BoostSpeed, 0.1, MAX_BOOST_SPEED)
	if not speed then
		return nil, err
	end
	local duration
	duration, err = readNumber(attributes, "Duration", defaults.Duration, 0, MAX_DURATION)
	if not duration then
		return nil, err
	end
	-- The server speed audit assumes the PhysicsTable boost; a larger authored value would read as a speed hack.
	if defaults.BoostSpeed then
		speed = math.min(speed, defaults.BoostSpeed)
	end
	if defaults.Duration then
		duration = math.min(duration, defaults.Duration)
	end
	return { BoostSpeed = speed, Duration = duration }
end

function VALIDATORS.JumpPad(attributes, defaults)
	local power, err = readNumber(attributes, "JumpPower", defaults.JumpPower, 0.01, MAX_JUMP_POWER)
	if not power then
		return nil, err
	end
	return { JumpPower = power }
end

function VALIDATORS.Rotating(attributes)
	local axisName = attributes.Axis
	if axisName == nil then
		axisName = "Y"
	end
	local axis = if type(axisName) == "string" then AXES[axisName] else nil
	if not axis then
		return nil, ('attribute Axis must be "X", "Y" or "Z", got %s'):format(tostring(axisName))
	end
	local period, err = readNumber(attributes, "Period", 4, MIN_PERIOD, MAX_PERIOD)
	if not period then
		return nil, err
	end
	local direction = attributes.Direction
	if direction == nil then
		direction = 1
	end
	if direction ~= 1 and direction ~= -1 then
		return nil, ("attribute Direction must be 1 or -1, got %s"):format(tostring(direction))
	end
	return { Axis = axis, Period = period, Direction = direction }
end

function VALIDATORS.Moving(attributes)
	local offset, err = readOffset(attributes)
	if not offset then
		return nil, err
	end
	local period
	period, err = readNumber(attributes, "Period", 3, MIN_PERIOD, MAX_PERIOD)
	if not period then
		return nil, err
	end
	local easing = attributes.Easing
	if easing == nil then
		easing = "Sine"
	end
	if type(easing) ~= "string" or not EASING_STYLES[easing] then
		return nil, ("attribute Easing must be an Enum.EasingStyle name, got %s"):format(tostring(easing))
	end
	return { Offset = offset, Period = period, Easing = easing }
end

function VALIDATORS.Vanishing(attributes)
	local onTime, err = readNumber(attributes, "OnTime", 2, 0.1, MAX_PERIOD)
	if not onTime then
		return nil, err
	end
	local offTime
	offTime, err = readNumber(attributes, "OffTime", 1.5, 0.1, MAX_PERIOD)
	if not offTime then
		return nil, err
	end
	local phase
	phase, err = readNumber(attributes, "Phase", 0, -MAX_PERIOD, MAX_PERIOD)
	if phase == nil then
		return nil, err
	end
	return { OnTime = onTime, OffTime = offTime, Phase = phase }
end

function VALIDATORS.KillBrick()
	return {}
end

function VALIDATORS.GrappleAnchor(attributes)
	local range, err = readNumber(attributes, "Range", nil, 1, 1000)
	if range == nil and attributes.Range ~= nil then
		return nil, err
	end
	return { Range = range }
end

function ObstacleMath.ConfigFor(kind, attributes, defaults)
	local validator = VALIDATORS[kind]
	if not validator then
		return nil, ("unknown obstacle kind %s"):format(tostring(kind))
	end
	return validator(attributes, defaults or {})
end

return ObstacleMath
