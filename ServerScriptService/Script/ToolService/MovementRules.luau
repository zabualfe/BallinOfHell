-- ToolService.MovementRules
-- Pure per-tool activation rules for the movement and utility tools (GDD 6.2, 6.6): Spring, Glider, Coil, Grapple and the
-- length of each tool's "active window". No engine calls; the tool modules gather the facts (ground ray, anchor tag,
-- distance, segment) and ask these functions to judge them, so every rule has a spec.
--
--   MovementRules.GroundedOnly(def, grounded) -> ok, reason?      Spring: "NotGrounded"
--   MovementRules.AirborneOnly(def, grounded) -> ok, reason?      Glider: "NotAirborne"
--   MovementRules.NotActive(activeUntil?, now) -> ok, reason?     Coil, Glider: "AlreadyActive" while a window is still open
--   MovementRules.GrappleReach(def, anchorRange?) -> studs        the anchor's Range attribute overrides the tool's reach
--   MovementRules.GrappleTarget(input) -> ok, reason?
--       input = { IsAnchor (tagged GrappleAnchor, still in the workspace), Distance (server ball sample to the anchor),
--                 Reach, Tolerance (latency slack), InSegment }
--       reasons "NoTarget" (not an anchor), "OutOfRange", "WrongSegment". The 30 degree cone is camera-based and so is
--       checked on the client only; the server bounds what a forged target could do with range and segment.
--   MovementRules.WindowSeconds(toolId, def) -> seconds           how long a use counts as "active" (ToolService windows)

local MovementRules = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local SPRING_EVENT_SECONDS = 1 -- how long a Spring use explains an upward speed gain to TrickService

function MovementRules.GroundedOnly(def, grounded)
	if def.GroundedOnly and not grounded then
		return false, "NotGrounded"
	end
	return true, nil
end

function MovementRules.AirborneOnly(def, grounded)
	if def.AirborneOnly and grounded then
		return false, "NotAirborne"
	end
	return true, nil
end

function MovementRules.NotActive(activeUntil, now)
	if activeUntil ~= nil and now < activeUntil then
		return false, "AlreadyActive"
	end
	return true, nil
end

function MovementRules.GrappleReach(def, anchorRange)
	if type(anchorRange) == "number" and anchorRange > 0 then
		return anchorRange
	end
	return def.Range
end

function MovementRules.GrappleTarget(input)
	if not input.IsAnchor then
		return false, "NoTarget"
	end
	if input.Distance > input.Reach + input.Tolerance then
		return false, "OutOfRange"
	end
	if not input.InSegment then
		return false, "WrongSegment"
	end
	return true, nil
end

function MovementRules.WindowSeconds(toolId, def)
	if toolId == "coil" or toolId == "timeslow" then
		return def.Duration
	elseif toolId == "glider" then
		return def.MaxDuration
	elseif toolId == "grapple" then
		return def.MaxPullSeconds
	elseif toolId == "rocket" then
		return def.HoldSeconds + def.GraceSeconds
	elseif toolId == "brake" then
		return def.StopSeconds
	elseif toolId == "spring" then
		return SPRING_EVENT_SECONDS
	end
	return 0
end

return MovementRules
