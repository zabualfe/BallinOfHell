-- ToolController/Tools/Shield (client half of ToolService/Tools/Shield)
--
-- CLIENT PLUG-IN CONTRACT (every module in ToolController/Tools; same file name as the server half)
--   Tool.CanPredict(context) -> ok, reason?   optional. Local pre-check; false cancels the press with no network
--                                             message and no charge (e.g. Grapple with no anchor: "NoTarget").
--   Tool.Predict(context) -> cancel?          optional. Starts the effect at once, for feel. Return a function that undoes
--                                             it; ToolController calls it if the server answers ToolResult false, so a
--                                             rejected press leaves nothing behind. The server stays the authority.
--   Tool.Destroy()                            optional. Called when the ball is unbound (respawn, leaving).
--   context = { ToolId, Def (ToolTable row), Slot, Ball (Model), Controller (BallController) }
--   CanPredict may set context.Payload (e.g. Grapple's chosen anchor); it is sent as UseTool's second argument and the
--   server treats it as untrusted. Predict receives the same context.
-- Modules may also listen to their own server messages at require time (below). One module serves every use.
--
-- Shield Bubble predicts nothing: whether it absorbs is decided by the server. The pop effect comes from the server's
-- ShieldAbsorbed(reason). A KillBrick touch bounces the ball back off the brick; a fall is a server teleport (BallPivot).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage.Network)

local BallController = require(script.Parent.Parent.Parent.BallController)

local Shield = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local BOUNCE_BACK_FACTOR = 0.6 -- of the horizontal speed, reversed
local BOUNCE_UP_SPEED = 30 -- studs/s

local function bounce()
	local ball = BallController.GetBall()
	local primary = ball and ball.PrimaryPart
	if not primary then
		return
	end
	local velocity = primary.AssemblyLinearVelocity
	local back = Vector3.new(-velocity.X, 0, -velocity.Z) * BOUNCE_BACK_FACTOR
	primary.AssemblyLinearVelocity = back + Vector3.new(0, BOUNCE_UP_SPEED, 0)
end

Network.OnEvent("ShieldAbsorbed", function(reason)
	if reason == "KillBrick" then
		bounce()
	end
end)

return Shield
