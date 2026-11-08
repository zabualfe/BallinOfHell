-- RoundService.StepRunner
-- Pure ordering logic for the sequenced round (AGENTS.md "Sequenced flow"). Steps before the start step are
-- Skipped (instant end state), the start step and everything after Run.
--
--   StepRunner.Plan(steps, startName?) -> { { Step, Action = "Skip" | "Run" } }, startFound
--       An empty or unknown startName runs every step (startFound = false for an unknown name).
--   StepRunner.Run(steps, startName?, context, onStep?) -> completed
--       onStep(step, action) runs before each step. A Run or Skip that returns "Abort" stops the cycle (completed = false).

local StepRunner = {}

function StepRunner.Plan(steps, startName)
	local startIndex = 1
	local startFound = true
	if startName ~= nil and startName ~= "" then
		startFound = false
		for index, step in steps do
			if step.Name == startName then
				startIndex = index
				startFound = true
				break
			end
		end
	end

	local plan = {}
	for index, step in steps do
		table.insert(plan, { Step = step, Action = index < startIndex and "Skip" or "Run" })
	end
	return plan, startFound
end

function StepRunner.Run(steps, startName, context, onStep)
	local plan = StepRunner.Plan(steps, startName)
	for _, entry in plan do
		if onStep then
			onStep(entry.Step, entry.Action)
		end
		local action = if entry.Action == "Skip" then entry.Step.Skip else entry.Step.Run
		if action(context) == "Abort" then
			return false
		end
	end
	return true
end

return StepRunner
