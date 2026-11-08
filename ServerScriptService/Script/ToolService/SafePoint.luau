-- ToolService.SafePoint
-- Engine seam for "is this ball standing somewhere safe" (GDD 6.5). Shield rescues to the newest safe point and
-- Pocket Checkpoint refuses to be placed anywhere that isn't one. The judgement is Rules.IsSafePoint; this module
-- only gathers the facts (ground raycast, tags, KillBrick distance, segment volume).
--
--   SafePoint.Probe(ball, position, segment, brickParts?) -> input for Rules.IsSafePoint
--   SafePoint.GetPoint(player, segment) -> CFrame?    -- newest safe ball position inside that segment, else nil
--   SafePoint.Forget(player)
--   SafePoint.Prune(player, segment)    -- forgets the point unless it lies in that segment
-- The server samples each racing player every ToolTable.Config.ShieldRescueSampleSeconds from BallService's 10 Hz
-- sample, so the client reports nothing (a client-sent point would be forgeable).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ToolTable = require(ReplicatedStorage.Tables.ToolTable)

local BallService = require(script.Parent.Parent.BallService)
local SpeedAudit = require(script.Parent.Parent.BallService.SpeedAudit)
local CourseService = require(script.Parent.Parent.CourseService)
local ProgressService = require(script.Parent.Parent.ProgressService)
local Rules = require(script.Parent.Rules)

local SafePoint = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local KILL_BRICK_TAG = "KillBrick"
local BAD_SURFACE_TAGS = { "KillBrick", "Moving", "Vanishing" }
local GROUND_RAY_SLACK = 1.5 -- studs below the ball's surface that still count as ground
local DEFAULT_BALL_RADIUS = 2 -- studs, when the ball has no measurable part
local CONFIG = ToolTable.Config

local points = {} -- [player] = { Segment, CFrame }

local function collectBrickParts()
	local parts = {}
	for _, instance in CollectionService:GetTagged(KILL_BRICK_TAG) do
		if instance:IsDescendantOf(workspace) then
			if instance:IsA("BasePart") then
				table.insert(parts, instance)
			end
			for _, descendant in instance:GetDescendants() do
				if descendant:IsA("BasePart") then
					table.insert(parts, descendant)
				end
			end
		end
	end
	return parts
end

local function isBadSurface(part)
	local current = part
	while current and current ~= workspace do
		for _, tag in BAD_SURFACE_TAGS do
			if CollectionService:HasTag(current, tag) then
				return true
			end
		end
		current = current.Parent
	end
	return false
end

function SafePoint.Probe(ball, position, segment, brickParts)
	local radius = DEFAULT_BALL_RADIUS
	local primary = ball and ball.PrimaryPart
	if primary then
		radius = primary.Size.Y / 2
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter = {}
	if ball then
		table.insert(filter, ball)
		local owner = Players:GetPlayerByUserId(ball:GetAttribute("Player") or 0)
		if owner and owner.Character then
			table.insert(filter, owner.Character)
		end
	end
	params.FilterDescendantsInstances = filter
	local hit = workspace:Raycast(position, Vector3.new(0, -(radius + GROUND_RAY_SLACK), 0), params)

	local nearBrick = false
	for _, part in brickParts or collectBrickParts() do
		if SpeedAudit.IsNearBox(position, part.CFrame, part.Size, CONFIG.ShieldRescueMinKillBrickDistance) then
			nearBrick = true
			break
		end
	end

	return {
		Grounded = hit ~= nil,
		InSegment = CourseService.IsInSegment(segment, position),
		OnBadSurface = hit ~= nil and isBadSurface(hit.Instance),
		NearKillBrick = nearBrick,
	}
end

function SafePoint.GetPoint(player, segment)
	local point = points[player]
	if point and point.Segment == segment then
		return point.CFrame
	end
	return nil
end

function SafePoint.Forget(player)
	points[player] = nil
end

function SafePoint.Prune(player, segment)
	local point = points[player]
	if point and point.Segment ~= segment then
		points[player] = nil
	end
end

local function sampleAll()
	local brickParts = collectBrickParts()
	for _, player in Players:GetPlayers() do
		local state = ProgressService.GetState(player)
		local sample = BallService.GetSample(player)
		if not (state and state.Racing and not state.Finished and sample) then
			continue
		end
		local segment = math.min(state.Checkpoint + 1, math.max(CourseService.GetSegmentCount(), 1))
		local probe = SafePoint.Probe(BallService.GetBall(player), sample.Position, segment, brickParts)
		if Rules.IsSafePoint(probe) then
			points[player] = { Segment = segment, CFrame = CFrame.new(sample.Position) }
		end
	end
end

local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < CONFIG.ShieldRescueSampleSeconds then
		return
	end
	elapsed = 0
	local ok, err = pcall(sampleAll)
	if not ok then
		warn("[ToolService] Safe point sampling failed: " .. tostring(err))
	end
end)

Players.PlayerRemoving:Connect(SafePoint.Forget)

return SafePoint
