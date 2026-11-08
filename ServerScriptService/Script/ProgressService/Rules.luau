-- ProgressService.Rules
-- Pure checkpoint and skip rules (GDD 5.7, 13). No engine calls, so they are spec'd offline.
--
--   Rules.EvaluateCheckpoint(input) -> accepted, reason
--       input = { Current, Index, Distance, Elapsed, ParTime, Range, MinParFraction }
--       reason is nil when accepted, else "WrongIndex" | "TooFar" | "TooEarly" (checked in that order)
--   Rules.MinParFraction(progressTable, usedMovementTool) -> number
--   Rules.CanSkip(input) -> ok, reason
--       input = { Current, Target, FinishIndex, Finished, IsNoSkip = fn(index) -> boolean? }
--       reason is nil when allowed, else "Finished" | "NotAhead" | "FinishLocked" | "NoSkipTier"
--   Rules.SkippedIndices(current, target) -> { current + 1 .. target }
--   Rules.ShouldFlag(strikes, limit) -> boolean

local Rules = {}

function Rules.EvaluateCheckpoint(input)
	if input.Index ~= input.Current + 1 then
		return false, "WrongIndex"
	end
	if input.Distance > input.Range then
		return false, "TooFar"
	end
	if input.Elapsed < input.ParTime * input.MinParFraction then
		return false, "TooEarly"
	end
	return true, nil
end

function Rules.MinParFraction(progressTable, usedMovementTool)
	if usedMovementTool then
		return progressTable.MinParFractionWithMovementTool
	end
	return progressTable.MinParFraction
end

function Rules.CanSkip(input)
	if input.Finished then
		return false, "Finished"
	end
	if input.Target <= input.Current then
		return false, "NotAhead"
	end
	-- Landing on the finish would skip the last segment, and the finish must be rolled by hand.
	if input.Target >= input.FinishIndex then
		return false, "FinishLocked"
	end
	if input.IsNoSkip then
		for index = input.Current + 1, input.Target do
			if input.IsNoSkip(index) then
				return false, "NoSkipTier"
			end
		end
	end
	return true, nil
end

function Rules.SkippedIndices(current, target)
	local list = {}
	for index = current + 1, target do
		table.insert(list, index)
	end
	return list
end

function Rules.ShouldFlag(strikes, limit)
	return strikes >= limit
end

return Rules
