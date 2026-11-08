-- ToolController/Tools/Coil (client half of ToolService/Tools/Coil)
-- Your gravity x GravityMultiplier for Duration, as a named entry in BallController's gravity stack: it multiplies with a
-- Low Gravity modifier and is floored at 0.4 x the default (GDD 6.6). Cancel or the end of the effect removes the entry.
-- Contract: see Tools/Shield.

local Coil = {}

local SOURCE = "Coil"

local active = nil -- { Finish }

function Coil.CanPredict(context)
	if not context.Ball.PrimaryPart then
		return false, "NoBall"
	end
	return true, nil
end

function Coil.Predict(context)
	local def, controller = context.Def, context.Controller
	local token = {}
	active = token
	controller.SetGravityMultiplier(SOURCE, def.GravityMultiplier)

	local function finish()
		if active ~= token then
			return
		end
		active = nil
		controller.ClearGravityMultiplier(SOURCE)
	end
	task.delay(def.Duration, finish)
	token.Finish = finish
	return finish
end

-- The ball unbinding mid-effect must release the stack entries, or the next press captures the leftovers.
function Coil.Destroy()
	if active and active.Finish then
		active.Finish()
	end
	active = nil
end

return Coil
