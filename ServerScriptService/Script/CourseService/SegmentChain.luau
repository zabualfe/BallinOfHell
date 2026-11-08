-- SegmentChain
-- Pure CFrame math for joining segments end to start. No Instances, so it is tested offline.
--
-- Usage:
--   SegmentChain.GetOffsets(pivotCF, startCF, endCF) -> startRel, endRel  -- start/end in pivot space
--   SegmentChain.Place(anchorCF, startRel, endRel) -> pivotCF, endCF      -- put a segment's start on anchorCF
-- Chaining n segments: anchor = previous endCF. Pitch and roll are kept, so segments may turn and climb.

local SegmentChain = {}

function SegmentChain.GetOffsets(pivotCF, startCF, endCF)
	local inverse = pivotCF:Inverse()
	return inverse * startCF, inverse * endCF
end

function SegmentChain.Place(anchorCF, startRel, endRel)
	local pivotCF = anchorCF * startRel:Inverse()
	return pivotCF, pivotCF * endRel
end

return SegmentChain
