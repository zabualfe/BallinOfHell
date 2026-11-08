-- Objectives/PlayRounds
-- Counts a round the player was racing in when Results started.

local PlayRounds = { Event = "RoundPlayed" }

function PlayRounds.Increment()
	return 1
end

return PlayRounds
