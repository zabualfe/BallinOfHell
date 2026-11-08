-- Objectives/EarnCoins
-- Sums race coins (checkpoint, finish, tricks). params.source = "Race" excludes reward coins such as gifts.

local EarnCoins = { Event = "Coins" }

local RACE_KINDS = { Race = true, Trick = true }

function EarnCoins.Increment(params, payload)
	if params.source == "Race" and not RACE_KINDS[payload.Kind] then
		return 0
	end
	return payload.Amount or 0
end

return EarnCoins
