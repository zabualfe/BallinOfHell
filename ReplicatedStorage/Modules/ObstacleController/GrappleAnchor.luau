-- GrappleAnchor (tag "GrappleAnchor")
-- No behaviour of its own: a registry the tool system queries for hook points. The optional Range attribute (studs)
-- overrides the tool's default reach. Plug-in contract: see BoostPanel.
--
--   GrappleAnchor.Register(instance) -> { Range = number? }
--   Query with ObstacleController.GetRegistered("GrappleAnchor") -> { [instance] = state }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ObstacleMath = require(ReplicatedStorage.Shared.ObstacleMath)

local GrappleAnchor = {}

function GrappleAnchor.Register(instance)
	return ObstacleMath.ConfigFor("GrappleAnchor", instance:GetAttributes())
end

function GrappleAnchor.Unregister() end

return GrappleAnchor
