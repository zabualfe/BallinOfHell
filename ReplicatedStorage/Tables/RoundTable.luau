-- RoundTable
-- Round step durations and the finish multiplier / clock speed-up rules (GDD 2).
-- Read by RoundService (steps), ProgressService (finish) and the HUD (timer, multiplier badge).
-- Formulas: multiplier = min(Start + PerFinisher * N, Cap); remaining -= dt * ClockRate.

local RoundTable = {
	Steps = { -- seconds
		Intermission = 20,
		BuildCourseTarget = 3, -- target only; the step ends when the course is built
		Countdown = 3,
		Race = 1200, -- round clock, not real time
		Results = 10,
		TeardownMax = 3,
	},
	LateJoinMinClockSeconds = 60, -- joining with less round clock left waits for the next round
	BuildSpinnerAfterSeconds = 1,
	IntermissionBeepsFrom = 5,

	Multiplier = { Start = 1.0, PerFinisher = 0.5, Cap = 3.0 }, -- RoundMultiplier on checkpoint and finish coins
	ClockRate = { Start = 1.0, PerFinisher = 0.25, Cap = 2.5 },
}

return RoundTable
