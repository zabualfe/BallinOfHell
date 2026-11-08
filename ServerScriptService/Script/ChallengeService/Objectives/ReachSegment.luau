-- Objectives/ReachSegment
-- Counts 1 per round once a checkpoint at or past params.slot is accepted.

local ReachSegment = { Event = "Checkpoint", OncePerRound = true }

function ReachSegment.Increment(params, payload)
	return payload.Index >= params.slot and 1 or 0
end

return ReachSegment
