-- ToolController/Tools/Glider (client half of ToolService/Tools/Glider)
-- Airborne only. For up to MaxDuration or until the ball lands, a BallController velocity driver runs the normal air
-- blend with AirMoveRate x AirMoveRateMultiplier (so it scales with the ball's own stat) and caps the fall speed at
-- FallSpeedCap. Cancel (a rejected press) or the end removes the driver. Contract: see Tools/Shield.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BallMotion = require(ReplicatedStorage.Shared.BallMotion)

local Glider = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local DRIVER = "Glider"
local MIN_FLIGHT_SECONDS = 0.2 -- grounded readings this soon after the press don't end the glide

local active = nil -- { Finish }

function Glider.CanPredict(context)
	if not context.Ball.PrimaryPart then
		return false, "NoBall"
	end
	if context.Controller.IsGrounded() then
		return false, "NotAirborne"
	end
	return true, nil
end

function Glider.Predict(context)
	local def, controller = context.Def, context.Controller
	local token = {}
	active = token
	local startedAt = os.clock()
	local endsAt = startedAt + def.MaxDuration

	local function finish()
		if active ~= token then
			return
		end
		active = nil
		controller.SetVelocityDriver(DRIVER, nil)
	end
	controller.SetVelocityDriver(DRIVER, function(velocity, moveDirection, grounded, dt, ctx)
		local clock = os.clock()
		if clock >= endsAt or (grounded and clock - startedAt >= MIN_FLIGHT_SECONDS) then
			finish()
			return nil
		end
		local attrs = table.clone(ctx.Attrs)
		attrs.AirMoveRate *= def.AirMoveRateMultiplier
		local stepped = BallMotion.Step(velocity, moveDirection, grounded, attrs, dt, {
			SpeedMultiplier = ctx.SpeedMultiplier,
		})
		return BallMotion.CapFallSpeed(stepped, def.FallSpeedCap)
	end)
	token.Finish = finish
	return finish
end

-- The ball unbinding mid-effect must release the stack entries, or the next press captures the leftovers.
function Glider.Destroy()
	if active and active.Finish then
		active.Finish()
	end
	active = nil
end

return Glider
