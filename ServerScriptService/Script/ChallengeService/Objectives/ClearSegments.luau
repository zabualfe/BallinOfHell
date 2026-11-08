-- Objectives/ClearSegments
-- Contract (every module in Objectives/ is named after a ChallengeTable.ObjectiveTypes entry):
--   Event: the game event name ChallengeService feeds it (see SeasonService.Events for payloads)
--   Increment(params, payload) -> number     -- progress to add for one event, 0 when it does not count
--   OncePerRound: true = counts at most once per round per challenge (optional)
-- Counts an accepted checkpoint, optionally only at params.minTier or harder.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CourseTable = require(ReplicatedStorage.Tables.CourseTable)

local ClearSegments = { Event = "Checkpoint" }

function ClearSegments.Increment(params, payload)
	if params.minTier then
		local needed = CourseTable.Tiers[params.minTier]
		local actual = CourseTable.Tiers[payload.Tier]
		if not needed or not actual or actual.Order < needed.Order then
			return 0
		end
	end
	return 1
end

return ClearSegments
