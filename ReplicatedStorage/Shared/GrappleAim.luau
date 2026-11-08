-- GrappleAim
-- Pure target choice for the Grapple Hook (GDD 6.2): the nearest anchor within reach and inside the cone around the
-- camera's forward vector. The client calls it to pick (and to say "no target" with no charge spent); the server does not
-- trust the pick and re-validates range and segment (ToolService/MovementRules.GrappleTarget).
--
--   GrappleAim.Pick(origin, forward, candidates, defaultRange, coneDegrees) -> key?, distance?
--       candidates { { Key, Position, Range? } }  Range overrides defaultRange (a GrappleAnchor's Range attribute)
--       forward need not be unit length. coneDegrees is the half angle.

local GrappleAim = {}

function GrappleAim.Pick(origin, forward, candidates, defaultRange, coneDegrees)
	if forward.Magnitude < 1e-6 then
		return nil, nil
	end
	local look = forward.Unit
	local minDot = math.cos(math.rad(coneDegrees))
	local bestKey, bestDistance = nil, math.huge
	for _, candidate in candidates do
		local offset = candidate.Position - origin
		local distance = offset.Magnitude
		local range = candidate.Range or defaultRange
		if distance <= range and distance < bestDistance then
			if distance < 1e-6 or offset.Unit:Dot(look) >= minDot then
				bestKey, bestDistance = candidate.Key, distance
			end
		end
	end
	return bestKey, if bestKey ~= nil then bestDistance else nil
end

return GrappleAim
