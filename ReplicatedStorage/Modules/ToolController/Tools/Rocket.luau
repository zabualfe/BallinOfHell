-- ToolController/Tools/Rocket (client half of ToolService/Tools/Rocket)
-- Predicts the burst: horizontal velocity jumps to top speed x SpeedMultiplier along the camera's flattened forward
-- vector, then the ball is steered that way for HoldSeconds (BallController.SetMoveOverride) with the speed
-- multiplier raised (a named source in BallController's stack), so normal blending can't bleed it off. A small FOV punch sells it. The server authorises the same
-- window in the speed audit. Cancel (a rejected press) restores control, speed and FOV at once.
-- Contract: see Tools/Shield.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BallMotion = require(ReplicatedStorage.Shared.BallMotion)

local Rocket = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local FOV_PUNCH = 12 -- degrees
local FOV_IN_SECONDS = 0.1
local FOV_OUT_SECONDS = 0.4
local MIN_FLAT_LOOK = 0.05 -- below this the camera looks straight up or down
local SPEED_SOURCE = "Rocket" -- its own multiplier entry, so ending never cancels an overlapping BoostPanel boost

local active = nil -- { Finish }

local function flatForward(ball)
	local camera = workspace.CurrentCamera
	local look = camera and camera.CFrame.LookVector or Vector3.zero
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < MIN_FLAT_LOOK then
		local primary = ball.PrimaryPart
		local velocity = primary and primary.AssemblyLinearVelocity or Vector3.zero
		flat = Vector3.new(velocity.X, 0, velocity.Z)
	end
	if flat.Magnitude < MIN_FLAT_LOOK then
		return nil
	end
	return flat.Unit
end

function Rocket.CanPredict(context)
	if not context.Ball.PrimaryPart then
		return false, "NoBall"
	end
	return true, nil
end

function Rocket.Predict(context)
	local ball, def, controller = context.Ball, context.Def, context.Controller
	local primary = ball.PrimaryPart
	local direction = flatForward(ball)
	if not (primary and direction) then
		return nil
	end

	local token = {}
	active = token
	local camera = workspace.CurrentCamera
	local baseFov = camera and camera.FieldOfView or 70

	local speed = BallMotion.TargetSpeed(ball:GetAttributes(), def.SpeedMultiplier)
	local velocity = primary.AssemblyLinearVelocity
	primary.AssemblyLinearVelocity = Vector3.new(direction.X * speed, velocity.Y, direction.Z * speed)
	controller.SetMoveOverride(direction)
	controller.SetSpeedMultiplier(SPEED_SOURCE, def.SpeedMultiplier)
	if camera then
		TweenService:Create(camera, TweenInfo.new(FOV_IN_SECONDS), { FieldOfView = baseFov + FOV_PUNCH }):Play()
	end

	local function finish()
		if active ~= token then
			return
		end
		active = nil
		controller.SetMoveOverride(nil)
		controller.ClearSpeedMultiplier(SPEED_SOURCE)
		if camera then
			TweenService:Create(camera, TweenInfo.new(FOV_OUT_SECONDS), { FieldOfView = baseFov }):Play()
		end
	end
	task.delay(def.HoldSeconds, finish)
	token.Finish = finish
	return finish
end

-- The ball unbinding mid-effect must release the stack entries, or the next press captures the leftovers.
function Rocket.Destroy()
	if active and active.Finish then
		active.Finish()
	end
	active = nil
end

return Rocket
