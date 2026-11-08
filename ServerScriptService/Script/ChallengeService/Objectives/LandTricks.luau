-- Objectives/LandTricks
-- Counts a landed airtime with at least 1 trick (TrickService validated it), or params.minChain tricks if set.
-- payload.Chain is the trick count; TrickService that omits it counts as a single trick.

local LandTricks = { Event = "TrickLanded" }

function LandTricks.Increment(params, payload)
	local chain = payload.Chain or 1
	if params.minChain and chain < params.minChain then
		return 0
	end
	return 1
end

return LandTricks
