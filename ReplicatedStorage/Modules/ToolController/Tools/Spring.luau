-- ToolController/Tools/Spring (client half of ToolService/Tools/Spring)
-- Grounded only. One launch at the ball's JumpPower x JumpPowerMultiplier through BallController.ApplyJumpPad, which also
-- counts as having jumped (a Double Jump modifier still works afterwards). Cancel (a rejected press) kills the upward speed
-- if the ball is still rising. Contract: see Tools/Shield.

local Spring = {}

function Spring.CanPredict(context)
	if not context.Ball.PrimaryPart then
		return false, "NoBall"
	end
	if not context.Controller.IsGrounded() then
		return false, "NotGrounded"
	end
	return true, nil
end

function Spring.Predict(context)
	local ball, def, controller = context.Ball, context.Def, context.Controller
	local jumpPower = ball:GetAttribute("JumpPower")
	if type(jumpPower) ~= "number" then
		return nil
	end
	controller.ApplyJumpPad(jumpPower * def.JumpPowerMultiplier)

	return function()
		local primary = ball.PrimaryPart
		local velocity = primary and primary.AssemblyLinearVelocity
		if velocity and velocity.Y > 0 then
			primary.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)
		end
	end
end

return Spring
