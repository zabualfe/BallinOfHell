-- Tools/Spring (server half): Super Spring (GDD 6.2). Grounded only; the client launches the ball at JumpPower x
-- JumpPowerMultiplier. The server checks the ground itself (raycast under its latest ball sample), so a forged press in
-- mid-air is refused and costs nothing. Vertical speed isn't part of the speed audit; the use is recorded as a short
-- window so TrickService's ballistic check can explain the gain. Spring is in CourseTable.Progress.MovementTools.
-- Contract: see Tools/Shield.

local BallService = require(script.Parent.Parent.Parent.BallService)
local MovementRules = require(script.Parent.Parent.MovementRules)
local SafePoint = require(script.Parent.Parent.SafePoint)

local Spring = {}

local NO_BRICKS = {} -- the probe's KillBrick scan isn't needed for a ground check

function Spring.CanActivate(player, ball, context)
	local sample = BallService.GetSample(player)
	if not (ball and sample) then
		return false, "NoBall"
	end
	local probe = SafePoint.Probe(ball, sample.Position, context.Segment, NO_BRICKS)
	return MovementRules.GroundedOnly(context.Def, probe.Grounded)
end

function Spring.Activate() end

return Spring
