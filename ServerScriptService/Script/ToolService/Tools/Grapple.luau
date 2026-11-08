-- Tools/Grapple (server half): Grapple Hook (GDD 6.2). The client picks the anchor (nearest in range and 30 degree cone)
-- and sends it as the UseTool payload. That instance is untrusted: it must carry the GrappleAnchor tag and still be in the
-- workspace, lie within reach of the server's own ball sample (plus latency slack), and sit inside the segment the player
-- is racing (MovementRules.GrappleTarget). Activation opens the "Grappling" speed-audit window for MaxPullSeconds plus the
-- grace (the ball keeps its pull momentum on release). Grapple is in CourseTable.Progress.MovementTools.
-- Contract: see Tools/Shield.

local CollectionService = game:GetService("CollectionService")

local BallService = require(script.Parent.Parent.Parent.BallService)
local CourseService = require(script.Parent.Parent.Parent.CourseService)
local MovementRules = require(script.Parent.Parent.MovementRules)

local Grapple = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local ANCHOR_TAG = "GrappleAnchor"
local RANGE_TOLERANCE = 15 -- studs: the 10 Hz sample is up to 0.1 s old and the client chose the target a ping ago

local function anchorPosition(anchor)
	if anchor:IsA("BasePart") then
		return anchor.Position
	elseif anchor:IsA("Model") then
		return anchor:GetPivot().Position
	end
	return nil
end

function Grapple.CanActivate(player, ball, context)
	local sample = BallService.GetSample(player)
	if not (ball and sample) then
		return false, "NoBall"
	end
	local anchor = context.Payload
	local isAnchor = typeof(anchor) == "Instance"
		and anchor:IsDescendantOf(workspace)
		and CollectionService:HasTag(anchor, ANCHOR_TAG)
	local position = isAnchor and anchorPosition(anchor) or nil
	if not position then
		return MovementRules.GrappleTarget({ IsAnchor = false })
	end
	return MovementRules.GrappleTarget({
		IsAnchor = true,
		Distance = (position - sample.Position).Magnitude,
		Reach = MovementRules.GrappleReach(context.Def, anchor:GetAttribute("Range")),
		Tolerance = RANGE_TOLERANCE,
		InSegment = CourseService.IsInSegment(context.Segment, position),
	})
end

function Grapple.Activate(player, _, context)
	local def = context.Def
	BallService.SetAuditContext(player, "Grappling", os.clock() + def.MaxPullSeconds + def.GraceSeconds)
end

return Grapple
