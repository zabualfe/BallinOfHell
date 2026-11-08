-- SeasonService/Rules
-- Pure season maths (GDD 8), no engine calls. SeasonService applies the results.
--
-- Usage (cfg = SeasonTable.Config, optionally merged with the season's own Tiers / XpPerTier):
--   Rules.Tier(xp, cfg) -> 0..Tiers                      Rules.MaxXp(cfg) -> XP cap including bonus chests
--   Rules.DaysElapsed(now, startUtc) -> whole days >= 0  Rules.IsCatchUp(xp, now, startUtc, cfg) -> tier < days elapsed
--   Rules.ApplyXp(xp, amount, now, startUtc, cfg) -> newXp, gained, isCatchUp
--   Rules.EffectiveEnd(endUtc, overrideUtc) -> number    Rules.IsActive(now, startUtc, endUtc, overrideUtc) -> boolean
--   Rules.IsProductLocked(now, endUtc, cfg) -> boolean   -- last HideProductsLastSeconds of the season
--   Rules.NeedsCloseOut(savedId, activeId, now, endUtc) -> boolean
--   Rules.CanClaim(state, def, track, tier, cfg) -> boolean, reason?
--   Rules.ClaimableList(state, def, cfg) -> { { Track, Tier, Rewards } } in tier order, free before premium
--   Rules.BonusChestsAvailable(state, cfg) -> number     Rules.ChestRewards(count, hasPremium, cfg) -> reward list
--   Rules.CapTierPurchase(xp, tiers, cfg) -> xp to add, never past tier Tiers
--   Rules.CanOfferProduct(key, state, now, endUtc, cfg) -> true | false, reason   -- a reason only when false
--   Rules.PurchasePlan(params, state, cfg) -> { SetPremium, Tiers, XpToAdd }
--   Rules.CreditPlan(params, premiumCredit, tierCredit, cfg) -> newPremiumCredit, newTierCredit   -- off-season receipt
--   Rules.EntryState(id, premiumCredit, tierCredit, cfg) -> fresh season table for the first join of a season
--   Rules.DidRace(furthestCheckpoint, finished) -> boolean   -- a player who raced this round (RoundPlayed, GDD 8.4)
--   Rules.RolloverPlan(state, def, cfg) -> { FinalTier, Claims, Chests, History }
-- state = the saved `season` table: { xp, claimedFree, claimedPremium, hasPremium, bonusChests }.

local Rules = {}

local SECONDS_PER_DAY = 86400
local TRACKS = { "Free", "Premium" }
local CLAIMED_KEY = { Free = "claimedFree", Premium = "claimedPremium" }
local BUY_TEN_KEY = "SeasonBuyTenTiers"
local ENDING_KEY = "SeasonEndingTenTiers"
local BUY_TIER_KEY = "SeasonBuyTier"
local RACED_MIN_CHECKPOINT = 1 -- reaching checkpoint 1 (or finishing) proves the player actually raced

function Rules.Tier(xp, cfg)
	if type(xp) ~= "number" or xp < 0 then
		return 0
	end
	return math.min(cfg.Tiers, math.floor(xp / cfg.XpPerTier))
end

function Rules.MaxXp(cfg)
	return cfg.Tiers * cfg.XpPerTier + cfg.BonusChestMax * cfg.BonusChestXp
end

function Rules.DaysElapsed(now, startUtc)
	return math.max(0, math.floor((now - startUtc) / SECONDS_PER_DAY))
end

function Rules.IsCatchUp(xp, now, startUtc, cfg)
	return Rules.Tier(xp, cfg) < Rules.DaysElapsed(now, startUtc)
end

-- The multiplier is decided from the tier BEFORE the gain, so one big grant is not half-boosted.
function Rules.ApplyXp(xp, amount, now, startUtc, cfg)
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount == math.huge then
		return xp, 0, false
	end
	local isCatchUp = Rules.IsCatchUp(xp, now, startUtc, cfg)
	local gained = math.floor(amount * (isCatchUp and cfg.CatchUpMultiplier or 1))
	local newXp = math.min(Rules.MaxXp(cfg), xp + gained)
	return newXp, newXp - xp, isCatchUp
end

function Rules.EffectiveEnd(endUtc, overrideUtc)
	local base = type(endUtc) == "number" and endUtc or 0
	local override = type(overrideUtc) == "number" and overrideUtc or 0
	return math.max(base, override)
end

function Rules.IsActive(now, startUtc, endUtc, overrideUtc)
	local effectiveEnd = Rules.EffectiveEnd(endUtc, overrideUtc)
	return effectiveEnd > 0 and now >= startUtc and now < effectiveEnd
end

function Rules.IsProductLocked(now, endUtc, cfg)
	return now >= endUtc - cfg.HideProductsLastSeconds
end

-- A saved season is closed out when another season became active, or its own end has passed.
function Rules.NeedsCloseOut(savedId, activeId, now, endUtc)
	if savedId == "" then
		return false
	end
	return savedId ~= activeId or (endUtc > 0 and now >= endUtc)
end

local function rewardsFor(def, track, tier)
	local list = def[track]
	return list and list[tier]
end

function Rules.CanClaim(state, def, track, tier, cfg)
	local claimedKey = CLAIMED_KEY[track]
	if not claimedKey then
		return false, "BadTrack"
	end
	if type(tier) ~= "number" or tier % 1 ~= 0 or tier < 1 or tier > cfg.Tiers then
		return false, "BadTier"
	end
	if not rewardsFor(def, track, tier) then
		return false, "NoReward"
	end
	if tier > Rules.Tier(state.xp, cfg) then
		return false, "NotReached"
	end
	if track == "Premium" and not state.hasPremium then
		return false, "NoPremium"
	end
	if state[claimedKey][tostring(tier)] then
		return false, "AlreadyClaimed"
	end
	return true
end

function Rules.ClaimableList(state, def, cfg)
	local out = {}
	for tier = 1, Rules.Tier(state.xp, cfg) do
		for _, track in TRACKS do
			if Rules.CanClaim(state, def, track, tier, cfg) then
				table.insert(out, { Track = track, Tier = tier, Rewards = rewardsFor(def, track, tier) })
			end
		end
	end
	return out
end

function Rules.BonusChestsAvailable(state, cfg)
	local beyond = math.max(0, state.xp - cfg.Tiers * cfg.XpPerTier)
	local earned = math.min(cfg.BonusChestMax, math.floor(beyond / cfg.BonusChestXp))
	return math.max(0, earned - state.bonusChests)
end

function Rules.ChestRewards(count, hasPremium, cfg)
	local rewards = { { Type = "Coins", Amount = cfg.BonusChestFreeCoins * count } }
	if hasPremium then
		table.insert(rewards, { Type = "Spins", Amount = cfg.BonusChestPremiumSpins * count })
	end
	return rewards
end

function Rules.CapTierPurchase(xp, tiers, cfg)
	if type(tiers) ~= "number" or tiers <= 0 then
		return 0
	end
	local ceiling = cfg.Tiers * cfg.XpPerTier
	return math.max(0, math.min(ceiling, xp + tiers * cfg.BuyTierXp) - xp)
end

-- Whether a season product may be offered or prompted right now. Never true in the last hour.
function Rules.CanOfferProduct(key, state, now, endUtc, cfg)
	if Rules.IsProductLocked(now, endUtc, cfg) then
		return false, "Locked"
	end
	local tier = Rules.Tier(state.xp, cfg)
	local isEnding = endUtc - now <= cfg.EndingOfferLastDays * SECONDS_PER_DAY
	if key == BUY_TIER_KEY then
		if tier >= cfg.Tiers then
			return false, "MaxTier"
		end
	elseif key == BUY_TEN_KEY then
		if isEnding then
			return false, "EndingOfferInstead"
		end
		if tier > cfg.BuyTenTiersHiddenAboveTier then
			return false, "TierTooHigh"
		end
	elseif key == ENDING_KEY then
		if not isEnding then
			return false, "NotEnding"
		end
		if tier > cfg.BuyTenTiersHiddenAboveTier then
			return false, "TierTooHigh"
		end
	elseif state.hasPremium then
		-- Premium Pass and Premium+: one per season.
		return false, "AlreadyPremium"
	end
	return true
end

-- What a receipt does. A second Premium turns its premium half into bonus tiers (GDD 8.7).
function Rules.PurchasePlan(params, state, cfg)
	local tiers = params.Tiers or 0
	local setPremium = false
	if params.Premium then
		if state.hasPremium then
			tiers += cfg.AlreadyPremiumBonusTiers
		else
			setPremium = true
		end
	end
	return {
		SetPremium = setPremium,
		Tiers = tiers,
		XpToAdd = Rules.CapTierPurchase(state.xp, tiers, cfg),
	}
end

-- A receipt while no season runs is stored, never lost: tiers add up, and a second Premium adds its bonus tiers instead
-- of overwriting the first (GDD 8.7). The tier credit never exceeds a full pass.
function Rules.CreditPlan(params, premiumCredit, tierCredit, cfg)
	local tiers = params.Tiers or 0
	local premium = premiumCredit == true
	if params.Premium then
		if premium then
			tiers += cfg.AlreadyPremiumBonusTiers
		else
			premium = true
		end
	end
	return premium, math.min(cfg.Tiers, math.max(0, (tierCredit or 0) + tiers))
end

function Rules.EntryState(id, premiumCredit, tierCredit, cfg)
	return {
		id = id,
		xp = Rules.CapTierPurchase(0, tierCredit or 0, cfg),
		claimedFree = {},
		claimedPremium = {},
		hasPremium = premiumCredit == true,
		bonusChests = 0,
	}
end

function Rules.DidRace(furthestCheckpoint, finished)
	return finished == true or (type(furthestCheckpoint) == "number" and furthestCheckpoint >= RACED_MIN_CHECKPOINT)
end

function Rules.RolloverPlan(state, def, cfg)
	local finalTier = Rules.Tier(state.xp, cfg)
	return {
		FinalTier = finalTier,
		Claims = def and Rules.ClaimableList(state, def, cfg) or {},
		Chests = Rules.BonusChestsAvailable(state, cfg),
		History = { tier = finalTier, hasPremium = state.hasPremium == true },
	}
end

return Rules
