-- ToolController/Tools/Grapple (client half of ToolService/Tools/Grapple)
-- CanPredict picks the nearest registered GrappleAnchor within Range (or the anchor's own Range attribute) and the
-- ConeDegrees cone of the camera's forward vector (Shared/GrappleAim); with none the press is refused locally as
-- "NoTarget" and no charge is spent. The chosen anchor is sent as the UseTool payload; the server re-validates it.
-- Predict pulls the ball straight at the anchor at PullSpeed for up to MaxPullSeconds through a BallController velocity
-- driver, then releases: the horizontal speed is kept up to the ball's normal top speed (more would trip the speed audit
-- once its Grappling window ends). Cancel, arrival, the timeout or an unbound ball all remove the driver.
-- Contract: see Tools/Shield.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BallMotion = require(ReplicatedStorage.Shared.BallMotion)
local GrappleAim = require(ReplicatedStorage.Shared.GrappleAim)

local ObstacleController = require(script.Parent.Parent.Parent.ObstacleController)

local Grapple = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local DRIVER = "Grapple"
local ANCHOR_TAG = "GrappleAnchor"

local active = nil -- { Finish }

local function positionOf(anchor)
	if anchor:IsA("BasePart") then
		return anchor.Position
	elseif anchor:IsA("Model") then
		return anchor:GetPivot().Position
	end
	return nil
end

local function pickAnchor(ball, def)
	local primary = ball.PrimaryPart
	local camera = workspace.CurrentCamera
	if not (primary and camera) then
		return nil
	end
	local candidates = {}
	for anchor, state in ObstacleController.GetRegistered(ANCHOR_TAG) do
		local position = anchor:IsDescendantOf(workspace) and positionOf(anchor)
		if position then
			table.insert(candidates, { Key = anchor, Position = position, Range = state.Range })
		end
	end
	return (GrappleAim.Pick(primary.Position, camera.CFrame.LookVector, candidates, def.Range, def.ConeDegrees))
end

function Grapple.CanPredict(context)
	local anchor = pickAnchor(context.Ball, context.Def)
	if not anchor then
		return false, "NoTarget"
	end
	context.Payload = anchor
	return true, nil
end

function Grapple.Predict(context)
	local ball, def, controller = context.Ball, context.Def, context.Controller
	local anchor = context.Payload
	if typeof(anchor) ~= "Instance" then
		return nil
	end

	local token = {}
	active = token
	local endsAt = os.clock() + def.MaxPullSeconds

	local function finish()
		if active ~= token then
			return
		end
		active = nil
		controller.SetVelocityDriver(DRIVER, nil)
	end
	controller.SetVelocityDriver(DRIVER, function(velocity, _, _, dt, ctx)
		local primary = ball.PrimaryPart
		local target = anchor.Parent and positionOf(anchor)
		if not (primary and target) or os.clock() >= endsAt then
			finish()
			return nil
		end
		local pull, arrived = BallMotion.PullVelocity(primary.Position, target, def.PullSpeed, dt)
		if arrived then
			finish()
			return BallMotion.ClampHorizontal(velocity, BallMotion.TargetSpeed(ctx.Attrs, 1))
		end
		return pull
	end)
	token.Finish = finish
	return finish
end

-- The ball unbinding mid-effect must release the stack entries, or the next press captures the leftovers.
function Grapple.Destroy()
	if active and active.Finish then
		active.Finish()
	end
	active = nil
end

return Grapple
