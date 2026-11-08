-- ProgressService
-- Owns each racing player's course progress: checkpoint, falls, strikes, finish. Everything is decided on the
-- server from the ball's 10 Hz sample (BallService.GetSample); the client sends nothing about checkpoints.
-- RoundService starts and stops it (StartPlayer / BeginRace / EndRace / ResetAll).
--
-- Economy contract: this module grants NO coins. EconomyService (next sprint) listens to CheckpointReached and
-- Finished and pays. It must pay nothing for an index flagged in GetState(player).Skipped. CheckpointReached never
-- fires for a skipped checkpoint, so the flag is the second line of defence.
--
-- Public API:
--   ProgressService.StartPlayer(player) -> state?   -- state at checkpoint 0, or restored to the player's checkpoint
--       when they rejoin the same round (earlier indices flagged Skipped, so nothing pays twice); racing if the race
--       is open. nil when the player already finished this round (they wait in the lobby). Progress is kept per
--       UserId until ResetAll.
--   ProgressService.HasFinished(player) -> boolean  -- finished this round, even if they left and rejoined
--   ProgressService.BeginRace()                     -- opens the race: all states start racing, clocks restart
--   ProgressService.EndRace()                       -- detection stops, states are kept for the results card
--   ProgressService.IsRacing() -> boolean
--   ProgressService.ResetPlayer(player)             -- forget the player, clear attributes, reset BallService strikes
--   ProgressService.ResetAll()                      -- ResetPlayer for everyone, close the race, zero the finisher count
--                                                      and forget the per-UserId round progress (new cycle)
--   ProgressService.GetState(player) -> { Checkpoint, LastCheckpointAt, StartedAt, FallsThisSegment, Finished,
--                                         Strikes, Racing, Skipped = { [index] = true } }?   -- a copy
--   ProgressService.SkipTo(player, index, reason?) -> boolean   -- paid skip to checkpoint index. false if the
--       player isn't racing, already finished, index isn't ahead, index would reach the finish (the finish can't be
--       skipped), or a NoSkips tier lies on the way. Checkpoints passed over are flagged in Skipped and pay 0.
--   ProgressService.MarkMovementTool(player)        -- ToolService calls it when a movement tool is used; lowers
--                                                      the par-time floor for the current segment (0.25 vs 0.35)
--   ProgressService.FallInterceptors                -- list of fn(player, segmentIndex, reason) -> boolean.
--       A future Shield appends a function here. Return true to absorb the fall: the fall is then not counted, the
--       player is not moved, and falls are ignored for a short grace. The interceptor does the rescue itself.
--       Reasons: "FallZone" | "KillBrick". Interceptors are pcall'd; an erroring one counts as "not absorbed".
--
-- Signals (all fired on the server):
--   CheckpointReached (player, index, tier)   -- index 1..30; 30 is the finish
--   Fell              (player, segmentIndex, reason)
--   Finished          (player, place, time, multiplier)  -- only fires while the race is open (RoundService takes
--       its finisher count from this place); time = seconds since the race opened for the player;
--       multiplier = RoundMultiplier BEFORE this finish raised it (what this finisher's reward uses)
--   Skipped           (player, fromIndex, toIndex, reason)
--   AntiCheatFlag     (player)                -- 5 strikes in a round; the player was moved back to the checkpoint
--
-- HUD: player attributes Checkpoint (number) and Falls (falls in the current segment).
-- Network (server -> owner): CheckpointReached(index, tier), Fell(segmentIndex, reason, fallsThisSegment),
--   Finished(place, time), Skipped(fromIndex, toIndex).
-- Network (client -> server): KillBrickTouched(segmentIndex?) validated below; segmentIndex is only type-checked
--   because the server derives the segment itself.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Network = require(ReplicatedStorage.Network)
local Signal = require(ReplicatedStorage.Utilities.Signal)
local CourseTable = require(ReplicatedStorage.Tables.CourseTable)

local BallService = require(script.Parent.BallService)
local SpeedAudit = require(script.Parent.BallService.SpeedAudit)
local CourseService = require(script.Parent.CourseService)
local Rejoin = require(script.Rejoin)
local Rules = require(script.Rules)

local ProgressService = {}
ProgressService.FallInterceptors = {}
ProgressService.CheckpointReached = Signal.new()
ProgressService.Fell = Signal.new()
ProgressService.Finished = Signal.new()
ProgressService.Skipped = Signal.new()
ProgressService.AntiCheatFlag = Signal.new()

-- ── Tuning ──────────────────────────────────────────────────────────────
local SCAN_INTERVAL = 0.2 -- seconds between checkpoint and fall scans
local KILL_BRICK_TAG = "KillBrick"
local KILL_BRICK_RADIUS = 15 -- studs from the ball to a KillBrick for a client report to count (lag allowance)
local ABSORBED_GRACE = 0.5 -- seconds of fall immunity after an interceptor absorbs one
local KILL_BRICK_RATE = { Capacity = 3, RefillPerSecond = 1 }
local PROGRESS = CourseTable.Progress

-- ── State ───────────────────────────────────────────────────────────────
local states = {} -- [player] = state
local raceOpen = false
local finisherCount = 0
local raceStartedAt = 0
local roundRecords = {} -- [userId] = { Checkpoint, Finished } for this cycle; survives leave and rejoin

local function setAttributes(player, state)
	player:SetAttribute("Checkpoint", state and state.Checkpoint or nil)
	player:SetAttribute("Falls", state and state.FallsThisSegment or nil)
end

local function enterSegment(state, now)
	state.LastCheckpointAt = now
	state.FallsThisSegment = 0
	state.UsedMovementTool = false
	state.EarlyStruck = false
end

local function respawnAtCheckpoint(player, state)
	local cframe = CourseService.GetSpawnCFrame(state.Checkpoint)
	if cframe then
		BallService.Respawn(player, cframe)
	end
	state.GraceUntil = os.clock() + PROGRESS.RespawnSeconds
end

-- ── Strikes ─────────────────────────────────────────────────────────────
-- One total: BallService owns the speed-audit strikes (BallService.GetStrikes); this module only adds its own
-- early-checkpoint strikes on top (state.EarlyStrikes). The flag fires on the sum and clears both.

local function strikeTotal(player, state)
	return BallService.GetStrikes(player) + state.EarlyStrikes
end

local function checkStrikes(player, state, reason)
	if not Rules.ShouldFlag(strikeTotal(player, state), PROGRESS.StrikesPerRound) then
		return
	end
	state.EarlyStrikes = 0
	BallService.ResetStrikes(player)
	warn(`[ProgressService] AntiCheatFlag {player.Name} at checkpoint {state.Checkpoint} (last strike: {reason})`)
	respawnAtCheckpoint(player, state)
	ProgressService.AntiCheatFlag:Fire(player)
end

BallService.StrikeAdded:Connect(function(player, reason)
	local state = states[player]
	if state and state.Racing then
		checkStrikes(player, state, reason)
	end
end)

-- ── Falls ───────────────────────────────────────────────────────────────

local function handleFall(player, reason)
	local state = states[player]
	if not state or not state.Racing or state.Finished then
		return false
	end
	local now = os.clock()
	if now < state.GraceUntil then
		return false
	end

	local segmentIndex = math.min(state.Checkpoint + 1, math.max(CourseService.GetSegmentCount(), 1))
	for _, interceptor in ProgressService.FallInterceptors do
		local ok, absorbed = pcall(interceptor, player, segmentIndex, reason)
		if not ok then
			warn("[ProgressService] Fall interceptor failed: " .. tostring(absorbed))
		elseif absorbed == true then
			state.GraceUntil = now + ABSORBED_GRACE
			return false
		end
	end

	state.FallsThisSegment += 1
	setAttributes(player, state)
	respawnAtCheckpoint(player, state)
	Network.FireClient(player, "Fell", segmentIndex, reason, state.FallsThisSegment)
	ProgressService.Fell:Fire(player, segmentIndex, reason)
	return true
end

local function isNearKillBrick(position)
	for _, instance in CollectionService:GetTagged(KILL_BRICK_TAG) do
		if instance:IsDescendantOf(workspace) then
			local parts = instance:GetDescendants()
			table.insert(parts, instance)
			for _, part in parts do
				if
					part:IsA("BasePart") and SpeedAudit.IsNearBox(position, part.CFrame, part.Size, KILL_BRICK_RADIUS)
				then
					return true
				end
			end
		end
	end
	return false
end

Network.OnEvent("KillBrickTouched", function(player, segmentIndex)
	if segmentIndex ~= nil and (type(segmentIndex) ~= "number" or segmentIndex ~= segmentIndex) then
		return
	end
	local state = states[player]
	if not state or not state.Racing then
		return
	end
	local sample = BallService.GetSample(player)
	if not sample or not isNearKillBrick(sample.Position) then
		return
	end
	handleFall(player, "KillBrick")
end, KILL_BRICK_RATE)

-- ── Checkpoints and finish ──────────────────────────────────────────────

local function finish(player, state, now)
	if not raceOpen then
		return
	end
	state.Finished = true
	Rejoin.Record(roundRecords, player.UserId, state.Checkpoint, true)
	finisherCount += 1
	local time = now - state.StartedAt
	local multiplier = workspace:GetAttribute("RoundMultiplier")
	if type(multiplier) ~= "number" then
		multiplier = 1
	end
	Network.FireClient(player, "Finished", finisherCount, time)
	ProgressService.Finished:Fire(player, finisherCount, time, multiplier)
end

local function acceptCheckpoint(player, state, index, checkpoint, now)
	state.Checkpoint = index
	Rejoin.Record(roundRecords, player.UserId, index)
	enterSegment(state, now)
	setAttributes(player, state)
	Network.FireClient(player, "CheckpointReached", index, checkpoint.Tier)
	ProgressService.CheckpointReached:Fire(player, index, checkpoint.Tier)
	if index >= CourseService.GetSegmentCount() then
		finish(player, state, now)
	end
end

local function scanPlayer(player, state, now)
	if not state.Racing or state.Finished or now < state.GraceUntil then
		return
	end
	local sample = BallService.GetSample(player)
	if not sample then
		return
	end

	if CourseService.FindFallSegment(sample.Position) then
		handleFall(player, "FallZone")
		return
	end

	local index = state.Checkpoint + 1
	local checkpoint = CourseService.GetCheckpoint(index)
	if not checkpoint then
		return
	end
	local distance = (sample.Position - checkpoint.CFrame.Position).Magnitude
	if distance > PROGRESS.CheckpointRange then
		return
	end

	-- An early arrival is struck once per segment, then accepted when the par floor passes.
	local accepted, reason = Rules.EvaluateCheckpoint({
		Current = state.Checkpoint,
		Index = index,
		Distance = distance,
		Elapsed = now - state.LastCheckpointAt,
		ParTime = checkpoint.ParTime,
		Range = PROGRESS.CheckpointRange,
		MinParFraction = Rules.MinParFraction(PROGRESS, state.UsedMovementTool),
	})
	if accepted then
		acceptCheckpoint(player, state, index, checkpoint, now)
	elseif not state.EarlyStruck then
		state.EarlyStruck = true
		state.EarlyStrikes += 1
		checkStrikes(player, state, reason)
	end
end

-- One pcall per player so a single bad state can't stop everyone else's scan; warned once per player.
local function scanAll()
	local now = os.clock()
	for player, state in states do
		local ok, err = pcall(scanPlayer, player, state, now)
		if not ok and not state.WarnedScan then
			state.WarnedScan = true
			warn(`[ProgressService] Scan failed for {player.Name}: {err}`)
		end
	end
end

local scanElapsed = 0
RunService.Heartbeat:Connect(function(dt)
	scanElapsed += dt
	if scanElapsed < SCAN_INTERVAL then
		return
	end
	scanElapsed = 0
	scanAll()
end)

-- ── Skips ───────────────────────────────────────────────────────────────

local function isNoSkip(index)
	local checkpoint = CourseService.GetCheckpoint(index)
	local tier = checkpoint and CourseTable.Tiers[checkpoint.Tier]
	return tier ~= nil and tier.NoSkips == true
end

function ProgressService.SkipTo(player, index, reason)
	local state = states[player]
	if not state or not state.Racing or type(index) ~= "number" or index ~= math.floor(index) then
		return false
	end
	local allowed = Rules.CanSkip({
		Current = state.Checkpoint,
		Target = index,
		FinishIndex = CourseService.GetSegmentCount(),
		Finished = state.Finished,
		IsNoSkip = isNoSkip,
	})
	if not allowed then
		return false
	end

	local from = state.Checkpoint
	for _, skippedIndex in Rules.SkippedIndices(from, index) do
		state.Skipped[skippedIndex] = true
	end
	state.Checkpoint = index
	Rejoin.Record(roundRecords, player.UserId, index)
	enterSegment(state, os.clock())
	setAttributes(player, state)
	respawnAtCheckpoint(player, state)
	Network.FireClient(player, "Skipped", from, index)
	ProgressService.Skipped:Fire(player, from, index, type(reason) == "string" and reason or "Skip")
	return true
end

function ProgressService.MarkMovementTool(player)
	local state = states[player]
	if state then
		state.UsedMovementTool = true
	end
end

-- ── Lifecycle ───────────────────────────────────────────────────────────

function ProgressService.HasFinished(player)
	return Rejoin.Plan(roundRecords, player.UserId).Action == "Lobby"
end

function ProgressService.StartPlayer(player)
	local plan = Rejoin.Plan(roundRecords, player.UserId)
	if plan.Action == "Lobby" then
		return nil
	end
	local now = os.clock()
	local isRestore = plan.Action == "Restore"
	local state = {
		Checkpoint = plan.Checkpoint,
		LastCheckpointAt = now,
		-- A rejoiner keeps the round's clock so leaving can't shorten their finish time.
		StartedAt = if isRestore and raceOpen then raceStartedAt else now,
		FallsThisSegment = 0,
		Finished = false,
		EarlyStrikes = 0,
		Racing = raceOpen,
		Skipped = plan.Skipped,
		UsedMovementTool = false,
		EarlyStruck = false,
		GraceUntil = 0,
	}
	states[player] = state
	BallService.ResetStrikes(player)
	setAttributes(player, state)
	return state
end

function ProgressService.BeginRace()
	raceOpen = true
	finisherCount = 0
	local now = os.clock()
	raceStartedAt = now
	for _, state in states do
		state.Racing = true
		state.StartedAt = now
		state.LastCheckpointAt = now
	end
end

function ProgressService.EndRace()
	raceOpen = false
	for _, state in states do
		state.Racing = false
	end
end

function ProgressService.IsRacing()
	return raceOpen
end

function ProgressService.ResetPlayer(player)
	states[player] = nil
	setAttributes(player, nil)
	BallService.ResetStrikes(player)
end

function ProgressService.ResetAll()
	for player in states do
		ProgressService.ResetPlayer(player)
	end
	raceOpen = false
	finisherCount = 0
	roundRecords = {}
end

function ProgressService.GetState(player)
	local state = states[player]
	if not state then
		return nil
	end
	return {
		Checkpoint = state.Checkpoint,
		LastCheckpointAt = state.LastCheckpointAt,
		StartedAt = state.StartedAt,
		FallsThisSegment = state.FallsThisSegment,
		Finished = state.Finished,
		Strikes = strikeTotal(player, state),
		Racing = state.Racing,
		Skipped = table.clone(state.Skipped),
	}
end

Players.PlayerRemoving:Connect(function(player)
	states[player] = nil
end)

return ProgressService
