-- SpeedAudit
-- Pure rules of the BallService speed audit (GDD 3, 13). The clock is always passed in so specs can fake it.
--
--   SpeedAudit.NewTracker() -> tracker
--   SpeedAudit.SetContext(tracker, key, untilTime)       key: "Boosting" | "Rocketing" | "Grappling"
--   SpeedAudit.MarkBoostNearby(tracker, now)             boost window = BoostPanel Duration + SpeedAudit grace
--   SpeedAudit.Limit(tracker, resolved, now) -> studs/s  BallStats.MaxAllowedSpeed with the live context
--   SpeedAudit.MeasuredSpeed(prevPosition, prevTime, position, now) -> studs/s?   -- horizontal distance / dt; nil if dt is off
--   SpeedAudit.Check(tracker, resolved, horizontalSpeed, now, measuredSpeed?) -> struck, limit
--       StrikeSamples over-limit samples within StrikeWindowSeconds make one strike, then the window clears.
--       A sample is over-limit when the velocity exceeds the limit, or the measured speed (position delta) exceeds
--       it by PositionTolerance. No sample counts for LimitDropGraceSeconds after the base limit drops.
--   SpeedAudit.IsNearBox(position, boxCFrame, boxSize, margin) -> boolean

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BallStats = require(ReplicatedStorage.Shared.BallStats)
local PhysicsTable = require(ReplicatedStorage.Tables.PhysicsTable)

local SpeedAudit = {}

local CONTEXT_KEYS = { Boosting = true, Rocketing = true, Grappling = true }

function SpeedAudit.NewTracker()
	return { Over = {}, Until = {} }
end

function SpeedAudit.SetContext(tracker, key, untilTime)
	if not CONTEXT_KEYS[key] or type(untilTime) ~= "number" then
		return false
	end
	-- Never shorten a window another system already opened.
	tracker.Until[key] = math.max(tracker.Until[key] or 0, untilTime)
	return true
end

function SpeedAudit.MarkBoostNearby(tracker, now)
	local window = PhysicsTable.Obstacles.BoostPanel.Duration + PhysicsTable.SpeedAudit.BoostGraceSeconds
	SpeedAudit.SetContext(tracker, "Boosting", now + window)
end

function SpeedAudit.Limit(tracker, resolved, now)
	local context = { AnchorTopSpeed = PhysicsTable.AnchorTopSpeed }
	for key in CONTEXT_KEYS do
		local untilTime = tracker.Until[key]
		context[key] = untilTime ~= nil and now <= untilTime
	end
	return BallStats.MaxAllowedSpeed(resolved, context)
end

function SpeedAudit.MeasuredSpeed(prevPosition, prevTime, position, now)
	local dt = now - prevTime
	local config = PhysicsTable.SpeedAudit
	-- A gap far from the sample rate (a stalled server frame) says nothing about speed.
	if dt < config.SampleSeconds * 0.5 or dt > config.SampleSeconds * 3 then
		return nil
	end
	local delta = position - prevPosition
	return Vector3.new(delta.X, 0, delta.Z).Magnitude / dt
end

function SpeedAudit.Check(tracker, resolved, horizontalSpeed, now, measuredSpeed)
	local limit = SpeedAudit.Limit(tracker, resolved, now)
	local config = PhysicsTable.SpeedAudit
	local over = tracker.Over

	-- Context windows expire on their own; only a drop of the base limit gets a grace.
	local baseLimit = BallStats.MaxAllowedSpeed(resolved, { AnchorTopSpeed = PhysicsTable.AnchorTopSpeed })
	if tracker.BaseLimit and baseLimit < tracker.BaseLimit - 1e-6 then
		tracker.GraceUntil = now + config.LimitDropGraceSeconds
	end
	tracker.BaseLimit = baseLimit
	if tracker.GraceUntil and now <= tracker.GraceUntil then
		table.clear(over)
		return false, limit
	end

	-- Drop samples that left the window (oldest first, so only the head can be stale).
	while #over > 0 and over[1] < now - config.StrikeWindowSeconds do
		table.remove(over, 1)
	end

	local isOver = horizontalSpeed > limit
		or (measuredSpeed ~= nil and measuredSpeed > limit * config.PositionTolerance)
	if not isOver then
		return false, limit
	end

	table.insert(over, now)
	if #over >= config.StrikeSamples then
		table.clear(over)
		return true, limit
	end
	return false, limit
end

function SpeedAudit.IsNearBox(position, boxCFrame, boxSize, margin)
	local localPosition = boxCFrame:PointToObjectSpace(position)
	local half = boxSize / 2
	local dx = math.max(math.abs(localPosition.X) - half.X, 0)
	local dy = math.max(math.abs(localPosition.Y) - half.Y, 0)
	local dz = math.max(math.abs(localPosition.Z) - half.Z, 0)
	return dx * dx + dy * dy + dz * dz <= margin * margin
end

return SpeedAudit
