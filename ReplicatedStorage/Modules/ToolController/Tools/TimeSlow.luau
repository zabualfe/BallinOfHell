-- ToolController/Tools/TimeSlow (client half of ToolService/Tools/TimeSlow)
-- Client-only by design (GDD 6.2, 15.8): for Duration, animated obstacles (Moving, Rotating, Vanishing) within Radius
-- studs of the ball run at SpeedMultiplier x on THIS client, through ObstacleController.SetTimeWarp. Everyone else, and
-- the server, see the normal clock; the server only spends the charge. Cancel or the end clears the warp and the
-- obstacles catch back up. Contract: see Tools/Shield.

local ObstacleController = require(script.Parent.Parent.Parent.ObstacleController)

local TimeSlow = {}

local active = nil -- { Token }

function TimeSlow.CanPredict(context)
	if not context.Ball.PrimaryPart then
		return false, "NoBall"
	end
	return true, nil
end

function TimeSlow.Predict(context)
	local ball, def = context.Ball, context.Def
	local token = {}
	active = token
	ObstacleController.SetTimeWarp(def.SpeedMultiplier, def.Radius, function()
		local primary = ball.PrimaryPart
		return primary and primary.Position or nil
	end)

	local function finish()
		if active ~= token then
			return
		end
		active = nil
		ObstacleController.ClearTimeWarp()
	end
	task.delay(def.Duration, finish)
	return finish
end

function TimeSlow.Destroy()
	if active then
		active = nil
		ObstacleController.ClearTimeWarp()
	end
end

return TimeSlow
