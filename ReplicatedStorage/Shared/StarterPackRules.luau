-- StarterPackRules
-- Pure Starter Pack window maths (GDD 10.6). All times are server wall-clock seconds, offline time included.
--
-- Usage:
--   StarterPackRules.IsLive(now, firstJoinAt, bought, windowSeconds) -> boolean
--       Live while now - firstJoinAt < window and not bought. Exactly at the window it is over. firstJoinAt = 0
--       means data is not ready, so never live.
--   StarterPackRules.EndsAt(firstJoinAt, windowSeconds) -> number
--   StarterPackRules.SecondsLeft(now, firstJoinAt, windowSeconds) -> number   -- clamped at 0
--   StarterPackRules.ReminderDue(now, firstJoinAt, windowSeconds, reminderSecondsLeft) -> boolean

local StarterPackRules = {}

function StarterPackRules.EndsAt(firstJoinAt, windowSeconds)
	return firstJoinAt + windowSeconds
end

function StarterPackRules.SecondsLeft(now, firstJoinAt, windowSeconds)
	return math.max(0, StarterPackRules.EndsAt(firstJoinAt, windowSeconds) - now)
end

function StarterPackRules.IsLive(now, firstJoinAt, bought, windowSeconds)
	if bought or type(firstJoinAt) ~= "number" or firstJoinAt <= 0 then
		return false
	end
	return now - firstJoinAt < windowSeconds
end

function StarterPackRules.ReminderDue(now, firstJoinAt, windowSeconds, reminderSecondsLeft)
	if firstJoinAt <= 0 then
		return false
	end
	local left = StarterPackRules.EndsAt(firstJoinAt, windowSeconds) - now
	return left > 0 and left <= reminderSecondsLeft
end

return StarterPackRules
