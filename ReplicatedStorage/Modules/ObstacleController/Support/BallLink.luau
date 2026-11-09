-- BallLink
-- The one seam between obstacles and the local ball. BallController owns the ball; obstacles only ask it things.
--
-- BallController API used here:
--   BallController.GetBall() -> Model?                  the local player's ball model, nil between lives
--   BallController.IsOwnBodyPart(part) -> boolean       the ball or the root part that carries it
--   BallController.SetSpeedMultiplier(source, multiplier)   BallLink owns the source "BoostPanel" and animates it for boosts (one
--                                                       envelope at a time); other sources (Rocket) overlap with it
--   BallController.ApplyJumpPad(jumpPower)              sets vertical velocity from the pad's JumpPower
--   BallController.Unbound                              Signal; BallLink resets its boost state when it fires
--
-- BallLink.Reset() drops the running boost envelope and drops its multiplier entry. It runs when the ball
-- unbinds (despawn, respawn, character removed) so a boost never outlives the ball it started on.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local BallController = require(ReplicatedStorage.Modules.BallController)
local ObstacleMath = require(ReplicatedStorage.Shared.ObstacleMath)

local BallLink = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local BOOST_TWEEN_SECONDS = 0.5 -- rise and fall time of a boost (GDD 5.4)
local BOOST_EASING = Enum.EasingStyle.Quad
local BOOST_DIRECTION = Enum.EasingDirection.Out

local BOOST_SOURCE = "BoostPanel"

local boostConnection
local currentMultiplier = 1

function BallLink.GetBall()
	return BallController.GetBall()
end

function BallLink.IsLocalBallPart(part)
	return BallController.IsOwnBodyPart(part)
end

function BallLink.Reset()
	if boostConnection then
		boostConnection:Disconnect()
		boostConnection = nil
	end
	currentMultiplier = 1
	BallController.ClearSpeedMultiplier(BOOST_SOURCE)
end

BallController.Unbound:Connect(BallLink.Reset)

local function ease(alpha)
	return TweenService:GetValue(alpha, BOOST_EASING, BOOST_DIRECTION)
end

-- A new boost replaces the running one and starts from the current multiplier, so panels chain smoothly.
function BallLink.ApplyBoost(boostSpeed, duration)
	if boostConnection then
		boostConnection:Disconnect()
	end

	local from = currentMultiplier
	local elapsed = 0
	boostConnection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		local multiplier, isDone =
			ObstacleMath.BoostMultiplier(elapsed, from, boostSpeed, duration, BOOST_TWEEN_SECONDS, ease)
		currentMultiplier = multiplier
		BallController.SetSpeedMultiplier(BOOST_SOURCE, multiplier)
		if isDone then
			boostConnection:Disconnect()
			boostConnection = nil
		end
	end)
end

function BallLink.ApplyJumpPad(jumpPower)
	BallController.ApplyJumpPad(jumpPower)
end

return BallLink
