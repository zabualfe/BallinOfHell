-- StreakBroken: the daily streak broke and is still restorable (DailyRewardService's DailyRestorable attribute).
-- Polled so a popup blocked by spacing or the countdown is retried until it shows or the cap is spent.
-- Contract: see UpsellService.

local ID = "StreakBroken"

return {
	Id = ID,
	Start = function() end,
	Tick = function(UpsellService, player)
		if player:GetAttribute("DailyRestorable") == true then
			UpsellService.Offer(player, ID, {})
		end
	end,
}
