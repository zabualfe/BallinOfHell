-- LeaderboardRules
-- Pure rules for LeaderboardService: win and best-time updates, the millisecond encoding, write batching and row
-- building. No engine calls, so everything here is specced offline.

local LeaderboardRules = {}

-- Returns newWins, newBestTime, winsChanged, bestChanged. Only place 1 is a win; bestTime 0 means "none yet".
-- Every finisher is eligible for a best time, whatever their place, except a run that used a paid skip
-- (`usedSkip`): it still counts as a win but sets no record.
function LeaderboardRules.ApplyFinish(wins, bestTime, place, time, usedSkip)
	local newWins = wins
	local newBest = bestTime
	if place == 1 then
		newWins = wins + 1
	end
	if not usedSkip and type(time) == "number" and time == time and time > 0 and time < math.huge then
		if bestTime <= 0 or time < bestTime then
			newBest = time
		end
	end
	return newWins, newBest, newWins ~= wins, newBest ~= bestTime
end

-- True when ProgressService's Skipped map ({ [index] = true }) holds any paid skip.
function LeaderboardRules.UsedSkip(skipped)
	return type(skipped) == "table" and next(skipped) ~= nil
end

-- OrderedDataStore values must be integers. At least 1, so a valid time is never stored as 0.
function LeaderboardRules.ToMillis(seconds)
	return math.max(1, math.floor(seconds * 1000 + 0.5))
end

function LeaderboardRules.FromMillis(milliseconds)
	return milliseconds / 1000
end

-- Takes up to (budget - reserve) jobs from the front of the list. Returns taken, remaining.
function LeaderboardRules.TakeJobs(jobs, budget, reserve)
	local count = math.clamp(budget - reserve, 0, #jobs)
	local taken, remaining = {}, {}
	for index, job in jobs do
		if index <= count then
			table.insert(taken, job)
		else
			table.insert(remaining, job)
		end
	end
	return taken, remaining
end

-- Turns the pending map { [userId] = { Wins?, Fastest? } } into an ordered job list, fastest times first
-- because they are rarer and worth more. Entries keep their latest value only.
function LeaderboardRules.BuildJobs(pending)
	local userIds = {}
	for userId in pending do
		table.insert(userIds, userId)
	end
	table.sort(userIds)
	local jobs = {}
	for _, userId in userIds do
		local entry = pending[userId]
		if entry.Fastest then
			table.insert(jobs, { Store = "Fastest", UserId = userId, Value = entry.Fastest })
		end
		if entry.Wins then
			table.insert(jobs, { Store = "Wins", UserId = userId, Value = entry.Wins })
		end
	end
	return jobs
end

-- Page items from GetSortedAsync ({ key = "123", value = n }) -> rows { UserId, Name, Value }. Bad keys are
-- dropped. `names` maps userId -> name; `decode` converts the stored value (nil = as is).
function LeaderboardRules.BuildRows(items, names, decode)
	local rows = {}
	for _, item in items do
		local userId = tonumber(item.key)
		if userId and type(item.value) == "number" then
			local value = if decode then decode(item.value) else item.value
			table.insert(rows, { UserId = userId, Name = names[userId] or "Unknown", Value = value })
		end
	end
	return rows
end

function LeaderboardRules.SameRows(a, b)
	if #a ~= #b then
		return false
	end
	for index, row in a do
		local other = b[index]
		if row.UserId ~= other.UserId or row.Value ~= other.Value or row.Name ~= other.Name then
			return false
		end
	end
	return true
end

return LeaderboardRules
