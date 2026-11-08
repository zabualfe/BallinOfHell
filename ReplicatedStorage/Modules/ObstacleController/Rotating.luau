-- Rotating (tag "Rotating")
-- Spins the object about its own pivot, Axis ("X"|"Y"|"Z", object space), Period (s per turn), Direction (1 or -1).
-- Angle comes from workspace:GetServerTimeNow(), so every client shows the same pose. Plug-in contract: see BoostPanel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ObstacleMath = require(ReplicatedStorage.Shared.ObstacleMath)

local Rotating = {}

function Rotating.Register(instance)
	if not instance:IsA("PVInstance") then
		return nil, "must be a BasePart or Model"
	end
	local config, reason = ObstacleMath.ConfigFor("Rotating", instance:GetAttributes())
	if not config then
		return nil, reason
	end
	config.BasePivot = instance:GetPivot()
	return config
end

function Rotating.Unregister(instance, state)
	if instance.Parent then
		instance:PivotTo(state.BasePivot)
	end
end

function Rotating.Step(_dt, active, now)
	for instance, state in active do
		local angle = ObstacleMath.RotationAngle(now - (state.TimeLag or 0), state.Period, state.Direction)
		instance:PivotTo(state.BasePivot * CFrame.fromAxisAngle(state.Axis, angle))
	end
end

return Rotating
