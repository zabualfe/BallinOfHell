-- FallsTrigger
-- Shared body of the three FallsOnSegment triggers (FallsThree / FallsFive / FallsEight). Each Triggers/ module is
-- FallsTrigger.new(id, extras) with the plug-in fields it adds (OfferOrder, Eligible, Single).
--
-- Fires on ProgressService.Fell once the segment's fall count reaches the Falls param. Shield-absorbed falls never fire
-- Fell, so they never count. The count resets with the segment, and the trigger fires once per segment per round;
-- the segment is only marked once the offer was actually shown, so a blocked offer retries on the next fall.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UpsellTable = require(ReplicatedStorage.Tables.UpsellTable)

local ProgressService = require(script.Parent.Parent.ProgressService)
local CourseService = require(script.Parent.Parent.CourseService)
local Rules = require(script.Parent.UpsellRules)

local FallsTrigger = {}

local function toolsAllowed(segmentIndex)
	local checkpoint = CourseService.GetCheckpoint(segmentIndex)
	local flags = checkpoint and checkpoint.Flags
	return not (flags and flags.NoTools)
end

function FallsTrigger.new(id, extras)
	local needsTools
	for _, row in UpsellTable.Triggers do
		if row.Id == id then
			needsTools = row.Params and row.Params.ToolsAllowed == true
		end
	end

	local plugin = {
		Id = id,
		Start = function(UpsellService)
			ProgressService.Fell:Connect(function(player, segmentIndex)
				local progress = ProgressService.GetState(player)
				if not progress then
					return
				end
				local memo = UpsellService.Memo(player, id)
				local segmentKey = ("%s:%d"):format(tostring(workspace:GetAttribute("RoundId")), segmentIndex)
				local falls = progress.FallsThisSegment
				if not Rules.FallsReached(falls, UpsellService.Param(id, "Falls"), segmentKey, memo.LastKey) then
					return
				end
				if needsTools and not toolsAllowed(segmentIndex) then
					return
				end
				if
					UpsellService.Offer(player, id, { Segment = segmentIndex, Falls = falls, Targets = extras.Targets })
				then
					memo.LastKey = segmentKey
				end
			end)
		end,
	}
	for key, value in extras do
		if key ~= "Targets" then
			plugin[key] = value
		end
	end
	return plugin
end

return FallsTrigger
