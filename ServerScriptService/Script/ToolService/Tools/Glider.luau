-- Tools/Glider (server half): Glider (GDD 6.2). Airborne only; the client caps the fall speed and raises AirMoveRate
-- for up to MaxDuration or until it lands. The server checks the ball is off the ground, and ends the recorded window
-- at the first grounded sample so a later jump isn't counted as assisted. No audit context is needed (the horizontal
-- allowance is unchanged). Glider is in CourseTable.Progress.MovementTools. Contract: see Tools/Shield.

local RunService = game:GetService("RunService")

local BallService = require(script.Parent.Parent.Parent.BallService)
local MovementRules = require(script.Parent.Parent.MovementRules)
local SafePoint = require(script.Parent.Parent.SafePoint)

local Glider = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local LAND_POLL_SECONDS = 0.2
local MIN_FLIGHT_SECONDS = 0.3 -- grounded readings this soon after the press are the launch, not a landing
local NO_BRICKS = {}

local active = {} -- [player] = { Until, Start, Segment, Close }

local function probeGrounded(player, segment)
	local sample = BallService.GetSample(player)
	if not sample then
		return nil
	end
	return SafePoint.Probe(BallService.GetBall(player), sample.Position, segment, NO_BRICKS).Grounded
end

function Glider.CanActivate(player, ball, context)
	if not ball then
		return false, "NoBall"
	end
	local ok, reason = MovementRules.NotActive(active[player] and active[player].Until, workspace:GetServerTimeNow())
	if not ok then
		return false, reason
	end
	local grounded = probeGrounded(player, context.Segment)
	if grounded == nil then
		return false, "NoBall"
	end
	return MovementRules.AirborneOnly(context.Def, grounded)
end

function Glider.Activate(player, _, context)
	active[player] = {
		Until = context.Now + context.Def.MaxDuration,
		Start = context.Now,
		Segment = context.Segment,
		Close = context.CloseWindow,
	}
end

function Glider.Reset(player)
	active[player] = nil
end

-- A respawn ends the glide on the client, so the server must not keep refusing a press.
BallService.BallSpawned:Connect(Glider.Reset)

local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < LAND_POLL_SECONDS or next(active) == nil then
		return
	end
	elapsed = 0
	local timeNow = workspace:GetServerTimeNow()
	for player, flight in active do
		if timeNow >= flight.Until then
			active[player] = nil
		elseif timeNow - flight.Start >= MIN_FLIGHT_SECONDS and probeGrounded(player, flight.Segment) == true then
			active[player] = nil
			if flight.Close then
				flight.Close()
			end
		end
	end
end)

return Glider
