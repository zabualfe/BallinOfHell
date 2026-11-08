-- TimeWarp
-- Pure maths for Time Slow (GDD 6.2): obstacles are animated from the shared server clock, so "slower for you only"
-- is a per-object lag subtracted from that clock on this client. While slowed, the lag grows by (1 - scale) per
-- second; afterwards it shrinks at CATCH_UP seconds per second (the object runs that much faster) until it is in
-- phase with everyone else again.
--
--   TimeWarp.StepLag(lag, dt, scale, isSlowed) -> newLag
--       isSlowed: the effect is active and the object is inside its radius. scale in (0, 1].
--   TimeWarp.CATCH_UP

local TimeWarp = {}

TimeWarp.CATCH_UP = 1 -- lag seconds recovered per second, so an object catches up at 2x speed

function TimeWarp.StepLag(lag, dt, scale, isSlowed)
	if isSlowed then
		return lag + dt * (1 - math.clamp(scale, 0, 1))
	end
	return math.max(0, lag - dt * TimeWarp.CATCH_UP)
end

return TimeWarp
