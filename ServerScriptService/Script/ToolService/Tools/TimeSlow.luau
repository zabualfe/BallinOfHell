-- Tools/TimeSlow (server half): Time Slow (GDD 6.2). Client-only by design (GDD 15.8): obstacles are animated on each
-- client, so there is nothing for the server to verify. It spends the charge, starts the cooldown and records a window;
-- the slowing itself is ToolController/Tools/TimeSlow. Contract: see Tools/Shield.

local TimeSlow = {}

function TimeSlow.CanActivate(_, ball)
	if not ball then
		return false, "NoBall"
	end
	return true, nil
end

function TimeSlow.Activate() end

return TimeSlow
