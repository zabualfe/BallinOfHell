-- BuildCourse: builds the course (yields), opens spawning and puts eligible players on the start line, frozen.
-- A failed build aborts the cycle (Run and Skip alike); the next Intermission is the retry delay.

local BuildCourse = { Name = "BuildCourse" }

function BuildCourse.Run(context)
	context.SetState("BuildCourse")
	if not context.Build() then
		warn("[RoundService] Course build failed; back to Intermission")
		return "Abort"
	end
	context.SetFrozen(true)
	context.OpenSpawning()
	return nil
end

function BuildCourse.Skip(context)
	if not context.Build() then
		warn("[RoundService] Course build failed; back to Intermission")
		return "Abort"
	end
	context.OpenSpawning()
	return nil
end

return BuildCourse
