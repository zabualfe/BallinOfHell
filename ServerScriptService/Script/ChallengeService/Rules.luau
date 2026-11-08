-- ChallengeService/Rules
-- Pure challenge maths (GDD 8.4), no engine calls. ChallengeService applies the results.
--
-- Usage:
--   Rules.DayNumber(now) -> UTC day number          Rules.WeekNumber(now) -> UTC week number (weeks start Monday 00:00)
--   Rules.SecondsToNextDay(now) / Rules.SecondsToNextWeek(now) -> seconds until the set resets
--   Rules.Seed(userId, number, salt?) -> positive integer; the same inputs always give the same seed
--   Rules.Eligible(pool, wins, conditional) -> pool where a gated row (wins < MinWins) is replaced by its ReplaceWith row
--       from the same pool, or dropped when that row is not in the pool; no row appears twice
--   Rules.Assign(pool, count, seed, wins, conditional) -> { row } picked by weight, no duplicates, deterministic
--   Rules.NewEntry(row) -> { id, progress = 0, done = false }
--   Rules.Reroll(pool, currentIds, seed, wins, conditional) -> row?   -- never one already in the set
--   Rules.RerollSeed(userId, day, rerollsUsed) -> number
--   Rules.RerollLimit(hasPremium, config) -> number
--   Rules.CanReroll(challenges, index, hasPremium, config) -> boolean, reason?
--   Rules.Advance(entry, row, increment) -> newEntry, justCompleted
-- Entries are the saved shape { id, progress, done }.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Weighted = require(ReplicatedStorage.Utilities.Weighted)

local Rules = {}

local SECONDS_PER_DAY = 86400
local DAYS_PER_WEEK = 7
local MONDAY_OFFSET_DAYS = 3 -- Unix day 0 is a Thursday; day 4 is the first Monday
local SEED_MODULUS = 2147483647
local SEED_MULTIPLIER = 48271
local REROLL_SALT = 7919

function Rules.DayNumber(now)
	return math.floor(now / SECONDS_PER_DAY)
end

function Rules.WeekNumber(now)
	return math.floor((Rules.DayNumber(now) + MONDAY_OFFSET_DAYS) / DAYS_PER_WEEK)
end

function Rules.SecondsToNextDay(now)
	return (Rules.DayNumber(now) + 1) * SECONDS_PER_DAY - now
end

function Rules.SecondsToNextWeek(now)
	local nextMondayDay = (Rules.WeekNumber(now) + 1) * DAYS_PER_WEEK - MONDAY_OFFSET_DAYS
	return nextMondayDay * SECONDS_PER_DAY - now
end

function Rules.Seed(userId, number, salt)
	local hash = math.abs(userId) % SEED_MODULUS
	hash = (hash * SEED_MULTIPLIER + math.abs(number)) % SEED_MODULUS
	hash = (hash * SEED_MULTIPLIER + (salt or 0)) % SEED_MODULUS
	return math.max(1, hash)
end

function Rules.RerollSeed(userId, day, rerollsUsed)
	return Rules.Seed(userId, day, REROLL_SALT + rerollsUsed)
end

function Rules.Eligible(pool, wins, conditional)
	local byId = {}
	for _, row in pool do
		byId[row.Id] = row
	end
	local out = {}
	local seen = {}
	for _, row in pool do
		local rule = conditional and conditional[row.Id]
		if rule and wins < rule.MinWins then
			row = rule.ReplaceWith and byId[rule.ReplaceWith] or nil
		end
		if row and not seen[row.Id] then
			seen[row.Id] = true
			table.insert(out, row)
		end
	end
	return out
end

-- Rows sorted by Id first so table order can never change the result for a seed.
local function sorted(rows)
	local copy = table.clone(rows)
	table.sort(copy, function(a, b)
		return a.Id < b.Id
	end)
	return copy
end

function Rules.Assign(pool, count, seed, wins, conditional)
	local candidates = sorted(Rules.Eligible(pool, wins, conditional))
	local random = Random.new(seed)
	local picked = {}
	for _ = 1, count do
		local row = Weighted.Pick(candidates, random)
		if not row then
			break
		end
		table.insert(picked, row)
		table.remove(candidates, table.find(candidates, row))
	end
	return picked
end

function Rules.NewEntry(row)
	return { id = row.Id, progress = 0, done = false }
end

function Rules.Reroll(pool, currentIds, seed, wins, conditional)
	local taken = {}
	for _, id in currentIds do
		taken[id] = true
	end
	local candidates = {}
	for _, row in sorted(Rules.Eligible(pool, wins, conditional)) do
		if not taken[row.Id] then
			table.insert(candidates, row)
		end
	end
	return Weighted.Pick(candidates, Random.new(seed))
end

function Rules.RerollLimit(hasPremium, config)
	return hasPremium and config.PremiumRerollsPerDay or config.FreeRerollsPerDay
end

function Rules.CanReroll(challenges, index, hasPremium, config)
	local entry = challenges.daily[index]
	if type(index) ~= "number" or index % 1 ~= 0 or not entry then
		return false, "BadIndex"
	end
	if entry.done then
		return false, "AlreadyDone"
	end
	if challenges.rerollsUsed >= Rules.RerollLimit(hasPremium, config) then
		return false, "NoRerolls"
	end
	return true
end

function Rules.Advance(entry, row, increment)
	if entry.done or type(increment) ~= "number" or increment ~= increment or increment <= 0 then
		return entry, false
	end
	local progress = math.min(row.Target, entry.progress + increment)
	local done = progress >= row.Target
	return { id = entry.id, progress = progress, done = done }, done
end

return Rules
