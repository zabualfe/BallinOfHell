-- Tools/Pocket (server half): Pocket Checkpoint (GDD 6.2). A personal respawn flag where the ball stands.
-- Rules: not in a tier that bans it (Hell, Finale: Rules.PocketBanned), 1 per segment (def.PerSegmentLimit), the ball
-- must be grounded on a surface that isn't a KillBrick / Moving / Vanishing part, inside this segment's volume.
-- Falls in that segment respawn there (after ProgressService has already respawned at the checkpoint, since the fall
-- still counts); it is dropped at the next checkpoint, a skip, or round end. Contract: see Tools/Shield.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnalyticsTable = require(ReplicatedStorage.Tables.AnalyticsTable)
local Signal = require(ReplicatedStorage.Utilities.Signal)

local AnalyticsService = require(script.Parent.Parent.Parent.AnalyticsService)
local BallService = require(script.Parent.Parent.Parent.BallService)
local ProgressService = require(script.Parent.Parent.Parent.ProgressService)
local Rules = require(script.Parent.Parent.Rules)
local SafePoint = require(script.Parent.Parent.SafePoint)

local Pocket = {}
Pocket.Changed = Signal.new()

local flags = {} -- [player] = { Segment, CFrame }

function Pocket.CanActivate(player, ball, context)
	if Rules.PocketBanned(context.Def, context.Tier, context.TierDef) then
		return false, "TierBanned"
	end
	if context.UsesThisSegment("pocket") >= context.Def.PerSegmentLimit then
		return false, "SegmentLimit"
	end
	local sample = BallService.GetSample(player)
	if not (ball and sample) then
		return false, "NoBall"
	end
	local probe = SafePoint.Probe(ball, sample.Position, context.Segment)
	if not (probe.Grounded and probe.InSegment) then
		return false, "NotGrounded"
	end
	if probe.OnBadSurface then
		return false, "BadSurface"
	end
	return true, nil
end

function Pocket.Activate(player, _, context)
	local sample = BallService.GetSample(player)
	if not sample then
		return
	end
	flags[player] = { Segment = context.Segment, CFrame = CFrame.new(sample.Position) }
	Pocket.Changed:Fire(player)
end

function Pocket.Reset(player)
	if flags[player] ~= nil then
		flags[player] = nil
		Pocket.Changed:Fire(player)
	end
end

function Pocket.Status(player)
	local flag = flags[player]
	return flag and { Segment = flag.Segment } or nil
end

ProgressService.Fell:Connect(function(player, segmentIndex)
	local flag = flags[player]
	if flag and flag.Segment == segmentIndex then
		BallService.Respawn(player, flag.CFrame)
		AnalyticsService.Custom(player, AnalyticsTable.Events.ToolSavedFall, nil, { ToolId = "pocket" })
	end
end)

-- Checkpoint n ends segment n and a skip lands on a later checkpoint; either way the flag is behind the player.
ProgressService.CheckpointReached:Connect(function(player)
	Pocket.Reset(player)
end)
ProgressService.Skipped:Connect(function(player)
	Pocket.Reset(player)
end)

return Pocket
