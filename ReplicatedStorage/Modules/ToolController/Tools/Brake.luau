-- ToolController/Tools/Brake (client half of ToolService/Tools/Brake)
-- Horizontal velocity goes to zero at once, then for StopSeconds a BallController velocity driver blends any drift toward
-- zero at SmoothStopRate x StopRateMultiplier, in the air as well, whenever the player isn't steering (steering gets the
-- normal blend). Vertical speed is untouched. Cancel (a rejected press) removes the driver. Contract: see Tools/Shield.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BallMotion = require(ReplicatedStorage.Shared.BallMotion)

local Brake = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local DRIVER = "Brake"
local INPUT_EPSILON = 1e-3 -- move direction magnitude below this is "not steering"

local active = nil -- { Token }

function Brake.CanPredict(context)
	if not context.Ball.PrimaryPart then
		return false, "NoBall"
	end
	return true, nil
end

function Brake.Predict(context)
	local def, controller = context.Def, context.Controller
	local primary = context.Ball.PrimaryPart
	if not primary then
		return nil
	end

	local token = {}
	active = token
	local endsAt = os.clock() + def.StopSeconds
	local velocity = primary.AssemblyLinearVelocity
	primary.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)

	local function finish()
		if active ~= token then
			return
		end
		active = nil
		controller.SetVelocityDriver(DRIVER, nil)
	end
	controller.SetVelocityDriver(DRIVER, function(current, moveDirection, _, dt, ctx)
		if os.clock() >= endsAt then
			finish()
			return nil
		end
		if Vector3.new(moveDirection.X, 0, moveDirection.Z).Magnitude > INPUT_EPSILON then
			return nil
		end
		return BallMotion.StopStep(current, ctx.Attrs.SmoothStopRate * def.StopRateMultiplier, dt)
	end)
	task.delay(def.StopSeconds, finish)
	return finish
end

function Brake.Destroy()
	active = nil
end

return Brake
