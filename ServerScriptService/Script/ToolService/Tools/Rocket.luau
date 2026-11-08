-- Tools/Rocket (server half): the movement tool of the first three (Common tier, GDD 6.2).
-- The client sets the ball's horizontal velocity to top speed x SpeedMultiplier along the camera for HoldSeconds.
-- The server cannot do that to a client-owned ball, so it authorises it: a "Rocketing" speed-audit window for the hold
-- plus the grace (BallService.SetAuditContext) so the speed audit doesn't strike. ProgressService.MarkMovementTool
-- (par-time floor 0.25) is called by ToolService because "rocket" is in CourseTable.Progress.MovementTools.
-- Contract: see Tools/Shield.

local BallService = require(script.Parent.Parent.Parent.BallService)

local Rocket = {}

function Rocket.CanActivate(_, ball)
	if not ball then
		return false, "NoBall"
	end
	return true, nil
end

function Rocket.Activate(player, _, context)
	local def = context.Def
	BallService.SetAuditContext(player, "Rocketing", os.clock() + def.HoldSeconds + def.GraceSeconds)
end

return Rocket
