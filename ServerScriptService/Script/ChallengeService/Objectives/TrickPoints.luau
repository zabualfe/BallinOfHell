-- Objectives/TrickPoints
-- Sums the trick points the server granted for a landing.

local TrickPoints = { Event = "TrickLanded" }

function TrickPoints.Increment(_params, payload)
	return payload.Points or 0
end

return TrickPoints
