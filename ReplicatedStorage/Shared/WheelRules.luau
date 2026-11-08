-- WheelRules
-- Pure wheel maths, no engine calls (GDD 10.5). Used by SpinWheelService and specs; WheelUI may use Odds.
--
-- Usage:
--   WheelRules.Roll(slices, random) -> index, slice   -- one weighted pick; the caller owns the Random
--   WheelRules.Odds(slices) -> list of { Index, Weight, Percent, Rewards }   -- Rewards = RewardRules summary
--   WheelRules.FreeInterval(config, hasLucky) -> seconds
--   WheelRules.FreeStatus(now, lastFreeSpinAt, interval) -> isReady, secondsLeft, nextAt
--       Free spins never bank past one: claiming restarts the timer from the claim time, so the timer is
--       effectively paused while one waits. lastFreeSpinAt = 0 (never claimed) is ready.
--   WheelRules.DayOf(now) -> UTC day number
--   WheelRules.VipSpinDue(day, lastVipSpinDay) -> boolean   -- VIP gets one extra spin per UTC day

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Weighted = require(ReplicatedStorage.Utilities.Weighted)
local RewardRules = require(script.Parent.RewardRules)

local WheelRules = {}

local SECONDS_PER_DAY = 86400

function WheelRules.Roll(slices, random)
	local slice = Weighted.Pick(slices, random)
	if not slice then
		return nil, nil
	end
	return table.find(slices, slice), slice
end

function WheelRules.Odds(slices)
	local total = 0
	for _, slice in slices do
		total += slice.Weight
	end
	local odds = {}
	for index, slice in slices do
		local ops = RewardRules.Normalize(slice.Reward)
		table.insert(odds, {
			Index = index,
			Weight = slice.Weight,
			Percent = if total > 0 then slice.Weight / total * 100 else 0,
			Rewards = RewardRules.Summarize(ops),
		})
	end
	return odds
end

function WheelRules.FreeInterval(config, hasLucky)
	if hasLucky then
		return config.LuckyFreeSpinSeconds
	end
	return config.FreeSpinSeconds
end

function WheelRules.FreeStatus(now, lastFreeSpinAt, interval)
	if lastFreeSpinAt <= 0 then
		return true, 0, now
	end
	-- A last claim in the future (clock fix, bad data) must not lock the wheel for longer than one interval.
	local anchor = math.min(lastFreeSpinAt, now)
	local nextAt = anchor + interval
	local left = nextAt - now
	if left <= 0 then
		return true, 0, nextAt
	end
	return false, left, nextAt
end

function WheelRules.DayOf(now)
	return math.floor(now / SECONDS_PER_DAY)
end

function WheelRules.VipSpinDue(day, lastVipSpinDay)
	return day > lastVipSpinDay
end

return WheelRules
