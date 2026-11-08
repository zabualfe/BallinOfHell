-- JumpPad (tag "JumpPad")
-- Sets the local ball's vertical velocity from the pad's JumpPower (ignores the Jump stat, GDD 5.4).
-- Plug-in contract: see BoostPanel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ObstacleMath = require(ReplicatedStorage.Shared.ObstacleMath)
local PhysicsTable = require(ReplicatedStorage.Tables.PhysicsTable)

local BallLink = require(script.Parent.Support.BallLink)
local Feedback = require(script.Parent.Support.Feedback)

local JumpPad = {}
JumpPad.Debounce = 0.4 -- seconds

function JumpPad.Register(instance)
	return ObstacleMath.ConfigFor("JumpPad", instance:GetAttributes(), PhysicsTable.Obstacles.JumpPad)
end

function JumpPad.Unregister() end

function JumpPad.OnTouched(_instance, state)
	BallLink.ApplyJumpPad(state.JumpPower)
	Feedback.Play("JumpPad")
end

return JumpPad
