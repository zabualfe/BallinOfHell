-- SeasonEndDay: SecondsLeft (24 h) left in the season, not premium, tier at least MinTier. Premium Pass, plus Season
-- Ending 10 Tiers while SeasonService still offers it (it hides above tier 40). Polled from the season snapshot.
-- Contract: see UpsellService.

local SeasonService = require(script.Parent.Parent.Parent.SeasonService)

local ID = "SeasonEndDay"

return {
	Id = ID,
	Start = function() end,
	Tick = function(UpsellService, player)
		local active = SeasonService.GetActive()
		if not active or SeasonService.HasPremium(player) then
			return
		end
		local secondsLeft = active.EndUtc - workspace:GetServerTimeNow()
		if secondsLeft <= 0 or secondsLeft > UpsellService.Param(ID, "SecondsLeft") then
			return
		end
		local snapshot = SeasonService.GetSnapshot(player)
		if snapshot and snapshot.Active and snapshot.Tier >= UpsellService.Param(ID, "MinTier") then
			UpsellService.Offer(player, ID, { Tier = snapshot.Tier, SecondsLeft = math.floor(secondsLeft) })
		end
	end,
}
