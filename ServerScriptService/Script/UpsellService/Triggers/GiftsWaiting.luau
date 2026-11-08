-- GiftsWaiting: Count or more timed gifts are unlocked and unclaimed. Polled from TimedRewardService.GetWaitingCount.
-- Contract: see UpsellService.

local TimedRewardService = require(script.Parent.Parent.Parent.TimedRewardService)

local ID = "GiftsWaiting"

return {
	Id = ID,
	Start = function() end,
	Tick = function(UpsellService, player)
		local waiting = TimedRewardService.GetWaitingCount(player)
		if waiting >= UpsellService.Param(ID, "Count") then
			UpsellService.Offer(player, ID, { Waiting = waiting })
		end
	end,
}
