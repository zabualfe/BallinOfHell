-- Tools/Shield (server half)
--
-- PLUG-IN CONTRACT (every module in ToolService/Tools; the file name is the ToolTable id with a capital: shield -> Shield)
--   Tool.CanActivate(player, ball, context) -> ok, reason?
--       Tool-specific veto, run after ToolService's own checks and before any charge is spent. `reason` is sent to the
--       client in ToolResult. Must not change state.
--   Tool.Activate(player, ball, context)
--       Runs after the charge is spent and the cooldown started; it cannot fail. Apply or authorise the effect here
--       (shield state, pocket position, a BallService audit context). MarkMovementTool is ToolService's job
--       (CourseTable.Progress.MovementTools), not the tool's.
--   Tool.Reset(player)                optional. Round end, leaving, or a new round: drop this player's state.
--   Tool.Status(player) -> table?     optional. Small replicated state for the tool button (sent in ToolRuntime.Status).
--   Tool.Changed                      optional Signal (player). Fire it when Status changes so ToolService re-sends.
--   context = { ToolId, Def (ToolTable.Tools[id]), Segment (1..30), Tier, TierDef, Flags, Sample, Now (server time),
--               Payload (untrusted second argument of UseTool, e.g. Grapple's anchor; validate before use),
--               CloseWindow() (ends this use's ToolService active window early, e.g. Glider landed),
--               UsesThisSegment(toolId) -> number }
-- Modules hold per-player state in a table keyed by player; granting, validation and prices stay in ToolService.
--
-- Shield Bubble: absorbs exactly one KillBrick touch or one fall (GDD 6.2, 6.5). It registers a
-- ProgressService.FallInterceptors function, so an absorbed fall is never counted (no Fell signal, no upsell).
-- KillBrick: ProgressService already grants the 0.5 s invulnerable grace after an absorb and the client bounces.
-- FallZone: the ball goes to the newest safe ground point (SafePoint), else the segment's checkpoint, with zero velocity.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnalyticsTable = require(ReplicatedStorage.Tables.AnalyticsTable)
local Network = require(ReplicatedStorage.Network)
local Signal = require(ReplicatedStorage.Utilities.Signal)
local ToolTable = require(ReplicatedStorage.Tables.ToolTable)

local AnalyticsService = require(script.Parent.Parent.Parent.AnalyticsService)
local BallService = require(script.Parent.Parent.Parent.BallService)
local CourseService = require(script.Parent.Parent.Parent.CourseService)
local ProgressService = require(script.Parent.Parent.Parent.ProgressService)
local SafePoint = require(script.Parent.Parent.SafePoint)

local Shield = {}
Shield.Changed = Signal.new()

local DEF = ToolTable.Tools.shield
local TOOL_ID = "shield"

local active = {} -- [player] = server time the bubble pops

local function isActive(player)
	local untilTime = active[player]
	return untilTime ~= nil and workspace:GetServerTimeNow() < untilTime
end

local function consume(player)
	active[player] = nil
	Shield.Changed:Fire(player)
end

function Shield.CanActivate(player)
	if isActive(player) then
		return false, "AlreadyActive"
	end
	return true, nil
end

function Shield.Activate(player)
	active[player] = workspace:GetServerTimeNow() + DEF.Duration
	Shield.Changed:Fire(player)
end

function Shield.Reset(player)
	if active[player] ~= nil then
		active[player] = nil
		Shield.Changed:Fire(player)
	end
end

function Shield.Status(player)
	if isActive(player) then
		return { Until = active[player] }
	end
	return nil
end

local function rescue(player, segmentIndex)
	local cframe = SafePoint.GetPoint(player, segmentIndex)
	if not cframe then
		-- No valid point yet: the checkpoint at the segment's start (the fall still doesn't count).
		local state = ProgressService.GetState(player)
		cframe = CourseService.GetSpawnCFrame(state and state.Checkpoint or 0)
	end
	if cframe then
		BallService.Respawn(player, cframe)
	end
end

table.insert(ProgressService.FallInterceptors, function(player, segmentIndex, reason)
	if not isActive(player) then
		return false
	end
	consume(player)
	if reason == "FallZone" then
		rescue(player, segmentIndex)
	end
	Network.FireClient(player, "ShieldAbsorbed", reason)
	local checkpoint = CourseService.GetCheckpoint(segmentIndex)
	AnalyticsService.Custom(player, AnalyticsTable.Events.ToolSavedFall, nil, {
		ToolId = TOOL_ID,
		Tier = checkpoint and checkpoint.Tier or "",
		Reason = reason,
	})
	return true
end)

return Shield
