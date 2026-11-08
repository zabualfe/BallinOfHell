-- BoostPanel (tag "BoostPanel")
-- Contract every tag module in this folder follows (ObstacleController dispatches by module name == tag name):
--   Register(instance) -> state?, reason?   Per-object setup, may yield (it runs in task.spawn). Return a state table, or
--                                           nil plus a reason when the object is misconfigured; the controller then
--                                           warns with the full path and disables just that object.
--   Unregister(instance, state)             Undo anything Register changed in the world. Connections made by the
--                                           controller (touch hooks) are cleaned by its Trove, not here.
--   Step(dt, active, now)                   Optional. Called every frame for animated kinds. `active` maps instance ->
--                                           state for streamed-in objects near the camera only; `now` is
--                                           workspace:GetServerTimeNow().
--   OnTouched(instance, state, ball)        Optional. Fires for a touch by the LOCAL ball only (the controller filters).
--   Debounce                                Optional number: seconds between OnTouched calls per object (default 0.25).
-- Config comes from attributes, validated by ReplicatedStorage.Shared.ObstacleMath.ConfigFor. Per-object state lives in
-- the state table; modules never read script.Parent.
--
-- Boost: BallLink eases the ball's speed multiplier up, holds it for Duration, eases it back, punches the FOV, plays the sound.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraController = require(ReplicatedStorage.Modules.CameraController)
local ObstacleMath = require(ReplicatedStorage.Shared.ObstacleMath)
local PhysicsTable = require(ReplicatedStorage.Tables.PhysicsTable)

local BallLink = require(script.Parent.Support.BallLink)
local Feedback = require(script.Parent.Support.Feedback)

local BoostPanel = {}
BoostPanel.Debounce = 0.5 -- seconds

function BoostPanel.Register(instance)
	return ObstacleMath.ConfigFor("BoostPanel", instance:GetAttributes(), PhysicsTable.Obstacles.BoostPanel)
end

function BoostPanel.Unregister() end

function BoostPanel.OnTouched(_instance, state)
	BallLink.ApplyBoost(state.BoostSpeed, state.Duration)
	CameraController.Punch(1)
	Feedback.Play("BoostPanel")
end

return BoostPanel
