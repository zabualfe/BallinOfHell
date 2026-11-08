-- SeasonPremiumTier: a non-premium player reaches the 1st / 10th / 20th / 30th tier that has a premium reward they
-- can't claim. SeasonService.TierReached fires per tier crossed. Contract: see UpsellService.

local SeasonService = require(script.Parent.Parent.Parent.SeasonService)
local Rules = require(script.Parent.Parent.UpsellRules)

local ID = "SeasonPremiumTier"
local NTH_TIERS_PARAM = "NthLockedTiers"

return {
	Id = ID,
	Start = function(UpsellService)
		SeasonService.TierReached:Connect(function(player, tier)
			local active = SeasonService.GetActive()
			if not active or SeasonService.HasPremium(player) then
				return
			end
			local nthTiers = UpsellService.Param(ID, NTH_TIERS_PARAM)
			if Rules.NthLockedPremiumTier(active.Def.Premium or {}, tier, nthTiers) then
				UpsellService.Offer(player, ID, { Tier = tier, SeasonId = active.Id })
			end
		end)
	end,
}
