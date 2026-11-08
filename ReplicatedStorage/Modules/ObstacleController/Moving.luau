-- Moving (tag "Moving")
-- Ping-pongs between the start pivot and start + Offset (world studs). Period is a full there-and-back cycle in
-- seconds, Easing an Enum.EasingStyle name applied InOut. Position comes from workspace:GetServerTimeNow(), so all
-- clients agree. Plug-in contract: see BoostPanel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ObstacleMath = require(ReplicatedStorage.Shared.ObstacleMath)

local Moving = {}

function Moving.Register(instance)
	if not instance:IsA("PVInstance") then
		return nil, "must be a BasePart or Model"
	end
	local config, reason = ObstacleMath.ConfigFor("Moving", instance:GetAttributes())
	if not config then
		return nil, reason
	end
	config.BasePivot = instance:GetPivot()
	config.EasingStyle = Enum.EasingStyle[config.Easing]
	return config
end

function Moving.Unregister(instance, state)
	if instance.Parent then
		instance:PivotTo(state.BasePivot)
	end
end

function Moving.Step(_dt, active, now)
	for instance, state in active do
		local phase = ObstacleMath.Phase(now - (state.TimeLag or 0), state.Period)
		local alpha = TweenService:GetValue(ObstacleMath.PingPong(phase), state.EasingStyle, Enum.EasingDirection.InOut)
		instance:PivotTo(state.BasePivot + state.Offset * alpha)
	end
end

return Moving
