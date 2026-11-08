-- EconomyService.Rules
-- Pure coin maths (GDD 9, 13). No engine calls, so every case is spec'd offline.
--
--   Rules.KindOf(kind) -> { RoundMultiplier, Boost, TrickPass }?   -- "Race" | "Reward" | "Trick"
--   Rules.PersonalMultiplier(kind, flags, economyTable) -> number
--       flags = { CoinsPass, CoinsBoost, TrickPass } booleans. Bonuses ADD (pass + boost = x3, not x4).
--   Rules.Payout(base, roundMultiplier, personalMultiplier, minCoins) -> integer
--       floor(base * round * personal), at least minCoins. A base of 0 or less pays 0 (the Finale checkpoint).
--   Rules.CheckpointBase(tierEntry, isSkipped, isFinish) -> integer   -- 0 when skipped or the finish
--   Rules.FinishBase(place, economyTable) -> integer
--   Rules.DuplicateCoins(ball, source, rarityTable, economyTable) -> integer   -- 0 = no refund
--   Rules.TransactionType(source, analyticsTable) -> string
--   Rules.TickBoosts(boosts, dt) -> remaining, expiredIds
--   Rules.AddBoost(boosts, boostId, seconds, capSeconds?) -> remaining, addedSeconds

local Rules = {}

local EPSILON = 1e-9 -- float guard so 3 * 1.1 * 3 style products never floor one coin low

-- Which multipliers each kind of grant uses. Rewards ignore the round multiplier and the boost (GDD 9.1);
-- tricks ignore the round multiplier but add the Trick Coins pass (GDD 7.5).
local KINDS = {
	Race = { RoundMultiplier = true, Boost = true, TrickPass = false },
	Reward = { RoundMultiplier = false, Boost = false, TrickPass = false },
	Trick = { RoundMultiplier = false, Boost = true, TrickPass = true },
}

local TRANSACTION_BY_SOURCE = {
	Checkpoint = "Gameplay",
	Finish = "Gameplay",
	Trick = "Gameplay",
	Duplicate = "Gameplay",
	Daily = "TimedReward",
	Timed = "TimedReward",
	Wheel = "TimedReward",
	FirstFall = "TimedReward",
	Onboarding = "Onboarding",
	CoinPack = "IAP",
	StarterPack = "IAP",
	Season = "SeasonPass",
	Refund = "Shop",
}

function Rules.KindOf(kind)
	return KINDS[kind]
end

function Rules.PersonalMultiplier(kind, flags, economyTable)
	local def = KINDS[kind]
	if not def then
		return 1
	end
	local bonus = economyTable.PersonalBonus
	local value = 1
	if flags.CoinsPass then
		value += bonus.CoinsPass
	end
	if def.Boost and flags.CoinsBoost then
		value += bonus.CoinsBoost
	end
	if def.TrickPass then
		if flags.TrickPass then
			value += bonus.TrickCoinsPass
		end
		return math.min(value, economyTable.TrickPersonalMax)
	end
	return math.min(value, economyTable.Race.PersonalMax)
end

function Rules.Payout(base, roundMultiplier, personalMultiplier, minCoins)
	if type(base) ~= "number" or base ~= base or base <= 0 then
		return 0
	end
	local amount = math.floor(base * roundMultiplier * personalMultiplier + EPSILON)
	return math.max(amount, minCoins)
end

function Rules.CheckpointBase(tierEntry, isSkipped, isFinish)
	if isSkipped or isFinish or not tierEntry then
		return 0
	end
	return tierEntry.CheckpointCoins or 0
end

function Rules.FinishBase(place, economyTable)
	local finish = economyTable.Finish
	local bonus = type(place) == "number" and finish.PlaceBonus[place] or 0
	return finish.BaseCoins + bonus
end

function Rules.DuplicateCoins(ball, source, rarityTable, economyTable)
	if not ball then
		return 0
	end
	-- The wheel exclusive pays its own flat value (GDD 9.2), whatever rarity it has.
	if ball.Source == "Wheel" and source == "Wheel" then
		return economyTable.Sources.WheelBallDuplicateCoins
	end
	local rarity = rarityTable[ball.Rarity]
	return rarity and rarity.DuplicateCoins or 0
end

function Rules.TransactionType(source, analyticsTable)
	if source == "Shop" then
		return analyticsTable.Transaction.Shop
	end
	return TRANSACTION_BY_SOURCE[source] or tostring(source)
end

-- Boost timers store remaining seconds and only run while the player is in the server (GDD 14 Q7).
function Rules.TickBoosts(boosts, dt)
	local remaining, expired = {}, {}
	for id, seconds in boosts do
		local left = seconds - dt
		if left > 0 then
			remaining[id] = left
		else
			table.insert(expired, id)
		end
	end
	table.sort(expired)
	return remaining, expired
end

function Rules.AddBoost(boosts, boostId, seconds, capSeconds)
	local remaining = table.clone(boosts)
	local current = remaining[boostId] or 0
	local total = current + seconds
	if capSeconds then
		total = math.min(total, capSeconds)
	end
	total = math.max(total, current)
	remaining[boostId] = total > 0 and total or nil
	return remaining, total - current
end

return Rules
