-- SeasonBehindPace: in the last LastDays of the season the tier is below days elapsed minus DaysBehind. Offers Season
-- Ending 10 Tiers (SeasonService decides whether it is on sale). Polled. Contract: see UpsellService.

local SeasonService = require(script.Parent.Parent.Parent.SeasonService)
local Rules = require(script.Parent.Parent.UpsellRules)

local ID = "SeasonBehindPace"
local SECONDS_PER_DAY = 24 * 3600

return {
	Id = ID,
	Start = function() end,
	Tick = function(UpsellService, player)
		local active = SeasonService.GetActive()
		if not active then
			return
		end
		local now = workspace:GetServerTimeNow()
		-- Cheap window check first: a snapshot per player every tick is wasteful outside the last days.
		local secondsLeft = active.EndUtc - now
		if secondsLeft <= 0 or secondsLeft > UpsellService.Param(ID, "LastDays") * SECONDS_PER_DAY then
			return
		end
		local daysElapsed = math.max(0, math.floor((now - active.StartUtc) / SECONDS_PER_DAY))
		local snapshot = SeasonService.GetSnapshot(player)
		if not snapshot or not snapshot.Active then
			return
		end
		local behind = Rules.SeasonBehind(
			snapshot.Tier,
			daysElapsed,
			secondsLeft,
			UpsellService.Param(ID, "DaysBehind"),
			UpsellService.Param(ID, "LastDays")
		)
		if behind then
			UpsellService.Offer(player, ID, { Tier = snapshot.Tier, DaysElapsed = daysElapsed })
		end
	end,
}
