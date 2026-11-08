-- Tools/Coil (server half): Gravity Coil (GDD 6.2). The client multiplies its own gravity by GravityMultiplier for
-- Duration (BallController's gravity stack, floored at 0.4 x default). Lower gravity gives no speed, so the audit needs
-- no context; the server keeps the active window so a second Coil can't overlap and TrickService can halve the points of
-- an airtime that used it. Coil is in CourseTable.Progress.MovementTools. Contract: see Tools/Shield.

local BallService = require(script.Parent.Parent.Parent.BallService)
local MovementRules = require(script.Parent.Parent.MovementRules)

local Coil = {}

local activeUntil = {} -- [player] = server time

function Coil.CanActivate(player, ball)
	if not ball then
		return false, "NoBall"
	end
	return MovementRules.NotActive(activeUntil[player], workspace:GetServerTimeNow())
end

function Coil.Activate(player, _, context)
	activeUntil[player] = context.Now + context.Def.Duration
end

function Coil.Reset(player)
	activeUntil[player] = nil
end
-- A respawn ends the effect on the client, so the server must not keep refusing a press.
BallService.BallSpawned:Connect(Coil.Reset)

return Coil
