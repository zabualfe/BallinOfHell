-- CheckpointBuilder
-- Places a CheckpointFlag at every joint (including the finish) and the EndTrack, and
-- records the checkpoint data CourseService hands to ProgressService.
--
-- Usage:
--   CheckpointBuilder.Place(template, anchorCF, folder) -> instance?, endCF
--     Clones a ServerStorage.CourseParts template with its PositionParts.StartPart (or pivot) on anchorCF.
--     endCF is its PositionParts.EndPart if it has one, else anchorCF. A nil template returns nil, anchorCF.
--   CheckpointBuilder.Entry(cframe, tier, parTime, segmentName, flags?) -> checkpoint table
--     flags = the segment's tool attributes ({ NoTools, ToolsAllowed, ToolRequired }); {} when omitted

local SegmentChain = require(script.Parent.SegmentChain)

local CheckpointBuilder = {}

function CheckpointBuilder.Entry(cframe, tier, parTime, segmentName, flags)
	return { CFrame = cframe, Tier = tier, ParTime = parTime, SegmentName = segmentName, Flags = flags or {} }
end

function CheckpointBuilder.Place(template, anchorCF, folder)
	if not template then
		return nil, anchorCF
	end

	local clone = template:Clone()
	if clone:IsA("Model") then
		clone.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end

	local positionParts = clone:FindFirstChild("PositionParts")
	local startPart = positionParts and positionParts:FindFirstChild("StartPart")
	local endPart = positionParts and positionParts:FindFirstChild("EndPart")
	local pivot = clone:GetPivot()
	local startRel, endRel = SegmentChain.GetOffsets(
		pivot,
		if startPart and startPart:IsA("BasePart") then startPart.CFrame else pivot,
		if endPart and endPart:IsA("BasePart") then endPart.CFrame else pivot
	)
	local placedPivot, endCF = SegmentChain.Place(anchorCF, startRel, endRel)
	clone:PivotTo(placedPivot)
	clone.Parent = folder
	if not (endPart and endPart:IsA("BasePart")) then
		return clone, anchorCF
	end
	return clone, endCF
end

return CheckpointBuilder
