-- ClockLow: under SecondsLeft on the round clock and not within MinSlotsFromFinish segments of the finish.
-- Polled: RoundService publishes RoundTimeLeft as a workspace attribute and ProgressService knows the checkpoint.
-- Contract: see UpsellService.

local CourseService = require(script.Parent.Parent.Parent.CourseService)
local ProgressService = require(script.Parent.Parent.Parent.ProgressService)
local Rules = require(script.Parent.Parent.UpsellRules)

local ID = "ClockLow"

return {
	Id = ID,
	Start = function() end,
	Tick = function(UpsellService, player)
		if workspace:GetAttribute("RoundState") ~= "Race" then
			return
		end
		local timeLeft = workspace:GetAttribute("RoundTimeLeft")
		local progress = ProgressService.GetState(player)
		if type(timeLeft) ~= "number" or not progress or not progress.Racing or progress.Finished then
			return
		end
		if not Rules.ClockLow(timeLeft, UpsellService.Param(ID, "SecondsLeft")) then
			return
		end
		local minSlots = UpsellService.Param(ID, "MinSlotsFromFinish")
		if Rules.NearFinish(progress.Checkpoint, CourseService.GetSegmentCount(), minSlots) then
			return
		end
		UpsellService.Offer(player, ID, { SecondsLeft = math.floor(timeLeft) })
	end,
}
