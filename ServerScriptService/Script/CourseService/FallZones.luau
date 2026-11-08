-- FallZones
-- One fall zone per segment plus a global Y floor, checked by position so ProgressService can poll
-- ball positions. No Touched connections and no zone Parts.
--
-- A zone is the segment's bounding box seen from above (rotated to the box's heading, so turns work),
-- shrunk by a margin so neighbouring zones overlap less at a joint. A position is "fallen" when it is
-- inside that footprint and lower than the box bottom minus a drop depth (CourseTable.Segment.FallVolumePadding).
-- The global floor catches anything that misses every footprint.
--
-- Usage:
--   FallZones.FromBox(boxCF, boxSize, margin, depth) -> zone
--   FallZones.Find(zones, position, floorY) -> index?   -- nearest zone above the position wins; floor -> nearest footprint
--   FallZones.Contains(zone, position) -> boolean       -- inside the footprint and not yet below the zone's drop line
--   FallZones.GetFloorY(zones, belowLowest) -> number

local FallZones = {}

local EPSILON = 1e-4

local function corners(boxCF, boxSize)
	local half = boxSize / 2
	local list = {}
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				table.insert(list, boxCF * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
			end
		end
	end
	return list
end

function FallZones.FromBox(boxCF, boxSize, margin, depth)
	local center = boxCF.Position
	-- Heading only: pitch would tilt the footprint test, so flatten the look vector.
	local flatLook = Vector3.new(boxCF.LookVector.X, 0, boxCF.LookVector.Z)
	local origin = CFrame.new(center)
	if flatLook.Magnitude > EPSILON then
		origin = CFrame.lookAt(center, center + flatLook)
	end

	local inverse = origin:Inverse()
	local minX, maxX, minZ, maxZ, bottomY = math.huge, -math.huge, math.huge, -math.huge, math.huge
	for _, corner in corners(boxCF, boxSize) do
		local local_ = inverse * corner
		minX, maxX = math.min(minX, local_.X), math.max(maxX, local_.X)
		minZ, maxZ = math.min(minZ, local_.Z), math.max(maxZ, local_.Z)
		bottomY = math.min(bottomY, corner.Y)
	end

	-- Never shrink past the middle, or a thin segment would have no zone at all.
	local shrinkX = math.min(margin, (maxX - minX) / 2 - EPSILON)
	local shrinkZ = math.min(margin, (maxZ - minZ) / 2 - EPSILON)
	return {
		Origin = origin,
		MinX = minX + shrinkX,
		MaxX = maxX - shrinkX,
		MinZ = minZ + shrinkZ,
		MaxZ = maxZ - shrinkZ,
		BottomY = bottomY,
		TriggerY = bottomY - depth,
	}
end

local function inFootprint(zone, position)
	local local_ = zone.Origin:PointToObjectSpace(position)
	return local_.X >= zone.MinX and local_.X <= zone.MaxX and local_.Z >= zone.MinZ and local_.Z <= zone.MaxZ
end

function FallZones.Contains(zone, position)
	return position.Y >= zone.TriggerY and inFootprint(zone, position)
end

function FallZones.GetFloorY(zones, belowLowest)
	local lowest = math.huge
	for _, zone in zones do
		lowest = math.min(lowest, zone.BottomY)
	end
	return lowest - belowLowest
end

function FallZones.Find(zones, position, floorY)
	local bestIndex, bestTrigger
	for index, zone in zones do
		if position.Y < zone.TriggerY and inFootprint(zone, position) then
			-- The highest trigger is the segment the ball most likely left.
			if bestTrigger == nil or zone.TriggerY > bestTrigger then
				bestIndex, bestTrigger = index, zone.TriggerY
			end
		end
	end
	if bestIndex then
		return bestIndex
	end

	if floorY == nil or position.Y >= floorY or #zones == 0 then
		return nil
	end
	local nearestIndex, nearestDistance
	for index, zone in zones do
		local distance = (zone.Origin.Position - position) * Vector3.new(1, 0, 1)
		if nearestDistance == nil or distance.Magnitude < nearestDistance then
			nearestIndex, nearestDistance = index, distance.Magnitude
		end
	end
	return nearestIndex
end

return FallZones
