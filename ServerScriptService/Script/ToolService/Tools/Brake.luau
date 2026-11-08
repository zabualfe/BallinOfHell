-- Tools/Brake (server half): Brake Anchor (GDD 6.2). Horizontal velocity to 0, then SmoothStopRate x4 for StopSeconds.
-- The ball is client-owned, so the client does the stopping; slowing down can't trip the speed audit, so the server only
-- needs a ball to exist and the use is recorded as a window (ToolService.GetActiveWindows). Contract: see Tools/Shield.

local Brake = {}

function Brake.CanActivate(_, ball)
	if not ball then
		return false, "NoBall"
	end
	return true, nil
end

function Brake.Activate() end

return Brake
