-- RoundService.RoundMath
-- Pure round maths (GDD 2): the finish multiplier, the clock speed-up and the late-join rule.
--
--   RoundMath.Multiplier(finishers, rule) -> number    -- rule = RoundTable.Multiplier
--   RoundMath.ClockRate(finishers, rule) -> number     -- rule = RoundTable.ClockRate
--   RoundMath.AdvanceClock(timeLeft, dt, rate) -> number   -- never below 0; times are round-clock seconds
--   RoundMath.CanLateJoin(timeLeft, minSeconds) -> boolean

local RoundMath = {}

local function scaled(finishers, rule)
	return math.min(rule.Start + rule.PerFinisher * math.max(finishers, 0), rule.Cap)
end

function RoundMath.Multiplier(finishers, rule)
	return scaled(finishers, rule)
end

function RoundMath.ClockRate(finishers, rule)
	return scaled(finishers, rule)
end

function RoundMath.AdvanceClock(timeLeft, dt, rate)
	return math.max(timeLeft - dt * rate, 0)
end

function RoundMath.CanLateJoin(timeLeft, minSeconds)
	return timeLeft >= minSeconds
end

return RoundMath
