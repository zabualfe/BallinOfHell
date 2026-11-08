-- ProgressService.Rejoin
-- Pure per-round progress ledger keyed by UserId, so leaving and rejoining mid-round can't reset a player
-- (which would pay checkpoints and raise the multiplier twice). No engine calls, so it is spec'd offline.
--
--   Rejoin.Record(records, userId, checkpoint, finished?) -> record   -- keeps the highest checkpoint; Finished sticks
--   Rejoin.Plan(records, userId) -> { Action, Checkpoint, Skipped }
--       Action = "Fresh"   no usable record: start at checkpoint 0
--              | "Restore" resume at Checkpoint; Skipped flags 1..Checkpoint (already paid, never pay or fire again)
--              | "Lobby"   already finished this round: wait in the lobby

local Rules = require(script.Parent.Rules)

local Rejoin = {}

function Rejoin.Record(records, userId, checkpoint, finished)
	local record = records[userId]
	if not record then
		record = { Checkpoint = 0, Finished = false }
		records[userId] = record
	end
	record.Checkpoint = math.max(record.Checkpoint, checkpoint)
	if finished then
		record.Finished = true
	end
	return record
end

function Rejoin.Plan(records, userId)
	local record = records[userId]
	if not record then
		return { Action = "Fresh", Checkpoint = 0, Skipped = {} }
	end
	if record.Finished then
		return { Action = "Lobby", Checkpoint = record.Checkpoint, Skipped = {} }
	end
	if record.Checkpoint <= 0 then
		return { Action = "Fresh", Checkpoint = 0, Skipped = {} }
	end
	local skipped = {}
	for _, index in Rules.SkippedIndices(0, record.Checkpoint) do
		skipped[index] = true
	end
	return { Action = "Restore", Checkpoint = record.Checkpoint, Skipped = skipped }
end

return Rejoin
