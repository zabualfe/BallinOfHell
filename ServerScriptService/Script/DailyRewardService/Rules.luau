-- DailyRewardService/Rules
-- Pure daily-streak maths (GDD 10.3). No engine calls, so every transition is covered by specs.
--
--   Rules.DayNumber(serverTime) -> UTC day number
--   Rules.Status(lastDay, streak, today, config) -> { CanClaim, NextDay, CanRestore }
--       NextDay is the calendar day (1..StreakLength) a claim today would pay.
--   Rules.RestoredLastDay(lastDay, streak, today, config) -> number?   -- new lastDailyClaimDay, nil if not restorable
--   Rules.DailyCoins(base, hasPass, isVip, economyTable) -> integer   -- base * (1 + passBonus + vipBonus); bonuses add (GDD 9.1)
--   Rules.BuildEntry(dayRow, isVip, ownsBall, hasPass, economyTable) -> reward entry for RewardService.Grant
--       A VIP entry carries FinalCoins (already multiplied, so Award must not apply the pass again).

local SECONDS_PER_DAY = 86400 -- UTC day
local EPSILON = 1e-9 -- float guard for floor, as in EconomyService/Rules

local Rules = {}

function Rules.DayNumber(serverTime)
	return math.floor(serverTime / SECONDS_PER_DAY)
end

local function clampStreak(streak, length)
	if type(streak) ~= "number" or streak < 0 then
		return 0
	end
	return math.min(math.floor(streak), length)
end

function Rules.Status(lastDay, streak, today, config)
	local length = config.StreakLength
	local current = clampStreak(streak, length)
	if lastDay < 0 then
		return { CanClaim = true, NextDay = 1, CanRestore = false }
	end

	local gap = today - lastDay
	if gap <= 0 then
		return { CanClaim = false, NextDay = current % length + 1, CanRestore = false }
	end
	if gap == 1 then
		return { CanClaim = true, NextDay = current % length + 1, CanRestore = false }
	end
	local canRestore = current > 0 and gap >= config.RestoreMinGapDays and gap <= config.RestoreMaxGapDays
	return { CanClaim = true, NextDay = 1, CanRestore = canRestore }
end

-- Restoring moves the last claim to yesterday, which is "as if no day was missed" and is idempotent:
-- once lastDay is yesterday the gap is 1 and CanRestore is false.
function Rules.RestoredLastDay(lastDay, streak, today, config)
	if not Rules.Status(lastDay, streak, today, config).CanRestore then
		return nil
	end
	return today - 1
end

function Rules.DailyCoins(base, hasPass, isVip, economyTable)
	local multiplier = 1
	if hasPass and economyTable.PassDoubles.RewardCoins then
		multiplier += economyTable.PersonalBonus.CoinsPass
	end
	if isVip then
		multiplier += economyTable.VipDailyCoinBonus
	end
	return math.floor(base * multiplier + EPSILON)
end

function Rules.BuildEntry(dayRow, isVip, ownsBall, hasPass, economyTable)
	local entry = {}
	for key, value in dayRow do
		if key == "Day" or key == "VipCoins" then
			continue
		end
		if key == "FirstTimeBall" and ownsBall then
			continue
		end
		entry[key] = type(value) == "table" and table.clone(value) or value
	end
	if isVip and dayRow.Coins then
		entry.Coins = nil
		entry.FinalCoins = Rules.DailyCoins(dayRow.Coins, hasPass == true, true, economyTable)
	end
	return entry
end

return Rules
