-- BallAttributes
-- Pure part of BallService's attribute write path: ball id + passes + modifiers + settings -> resolved stats,
-- and writing them onto an instance. Keys are the BallStats contract the client BallController reads.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BallStats = require(ReplicatedStorage.Shared.BallStats)

local BallAttributes = {}

-- The saved settings.doubleJump toggle turns the pass perk off; it cannot grant it.
function BallAttributes.Build(ballId, passes, modifiers, settings)
	local effective = table.clone(passes or {})
	if settings and settings.doubleJump == false then
		effective.DoubleJump = nil
	end
	return BallStats.ForBall(ballId, effective, modifiers)
end

-- keys: list of modifier keys; readAttribute: fn(key) -> value (workspace:GetAttribute in production).
function BallAttributes.ReadModifiers(keys, readAttribute)
	local active = {}
	for _, key in keys do
		if readAttribute(key) == true then
			active[key] = true
		end
	end
	return active
end

function BallAttributes.Apply(instance, resolved)
	for key, value in resolved do
		instance:SetAttribute(key, value)
	end
end

return BallAttributes
