-- TrickService
-- Server authority for the automatic tricks (GDD 7.9): the client plays animations and reports what it did, the
-- server decides what pays. All rules are pure and spec'd in Shared/TrickRules and Shared/TrickShopRules.
--
-- How a payout happens
--   1. A 10 Hz loop samples every racing player's ball (BallService.GetSample), casts the same down ray as the client
--      and feeds TrickRules.Feed, which turns the samples into airtime records { StartT, EndT, Unexplained }.
--   2. The client sends TrickLanded({ trickIds, startedAt, landedAt }) after touchdown. Times are
--      workspace:GetServerTimeNow(); they only pair the report with the server's own airtime record.
--   3. LandConfirm (0.5 s) after touchdown the report is settled: Bail if a fall, KillBrick, Shield rescue, skip,
--      respawn, anti-cheat move or the round end happened in the window (or while in a fall volume); 0 plus a strike for
--      an unexplained vertical speed gain over 15 studs/s (pays 0 for that airtime; a strike only from the 2nd one in a
--      round, see TrickRules.NoteUnexplained); otherwise only owned and equipped tricks that fit the
--      server airtime (+0.2 s) are scored from TrickTable, a strike if the overshoot is over 0.5 s, then points ->
--      coins with the segment and round caps -> EconomyService.Award(Kind = "Trick").
--
-- Public API:
--   TrickService.TrickLanded   Signal (player, points, coins, tricksLanded) -- a Clean or Sloppy airtime with >= 1 paid trick
--   TrickService.BuyTrick(player, trickId) -> boolean, reason?      -- coins, Coins-tier tricks only
--   TrickService.UpgradeTrick(player, trickId) -> boolean, reason?  -- next level for coins
--   TrickService.EquipTricks(player, list) -> boolean, reason?
--   TrickService.GrantTrick(player, trickId) -> boolean             -- free unlock for PurchaseService, SeasonService, rewards;
--       false if unknown, a Free trick, already owned or data isn't loaded
--   TrickService.GrantLevel(player, trickId, level) -> boolean      -- raises the level (never lowers); false if nothing changed
--   TrickService.MarkAssist(player, key, seconds)   -- key "Glider" | "Grapple" | "Coil": the airtime scores x0.5 once
--   TrickService.MarkLift(player, seconds)          -- a jump pad, Spring, Rocket or Grapple legitimately adds vertical speed
-- With ToolService present, assists and lifts come from its recorded use windows (ToolService.WasActive, the same
-- GetServerTimeNow time base as the airtime records), so a Glider cut short by landing is not counted for its nominal
-- length. MarkAssist and MarkLift are the fallback (fed from ToolService.ToolUsed) when ToolService can't provide windows.
--
-- Network (client -> server), rate limit in brackets:
--   TrickLanded({ trickIds = { id, ... }, startedAt, landedAt })  [burst 3, 3/s: TrickTable.Server.ReportRateLimit]
--   BuyTrick(trickId)       [burst 3, 0.5/s]   -> TrickPurchased(trickId) | TrickFailed("Buy", reason)
--   UpgradeTrick(trickId)   [burst 3, 0.5/s]   -> TrickUpgraded(trickId, level) | TrickFailed("Upgrade", reason)
--   EquipTricks(list)       [burst 5, 1/s]     -> TricksEquipped(list) | TrickFailed("Equip", reason)
-- Network (server -> owner):
--   TrickResult(grade, points, coins, flags)  grade "Clean" | "Sloppy" | "Bail"; flags = { Trimmed, SegmentCapped,
--       RoundCapped, RoundCapReached } (RoundCapReached is true once per round, for the "maxed" toast). The client
--       corrects its predicted popup with it.
--   FirstTrick()   the first paid trick ever (stats.tricksLanded was 0): "Big air = auto tricks = bonus coins!"
--
-- Saved keys: ownedTricks, equippedTricks, trickLevels, stats.tricksLanded, stats.bestTrickPoints (DataTemplate).
-- Runtime (per UserId so leaving and rejoining can't refill the caps): carried points, coins per segment and per round.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Network = require(ReplicatedStorage.Network)
local TrickRules = require(ReplicatedStorage.Shared.TrickRules)
local TrickShopRules = require(ReplicatedStorage.Shared.TrickShopRules)
local Signal = require(ReplicatedStorage.Utilities.Signal)
local AnalyticsTable = require(ReplicatedStorage.Tables.AnalyticsTable)
local PhysicsTable = require(ReplicatedStorage.Tables.PhysicsTable)
local ToolTable = require(ReplicatedStorage.Tables.ToolTable)
local TrickTable = require(ReplicatedStorage.Tables.TrickTable)

local AnalyticsService = require(script.Parent.AnalyticsService)
local BallService = require(script.Parent.BallService)
local SpeedAudit = require(script.Parent.BallService.SpeedAudit)
local CourseService = require(script.Parent.CourseService)
local EconomyService = require(script.Parent.EconomyService)
local PlayerData = require(script.Parent.PlayerData)
local ProgressService = require(script.Parent.ProgressService)
local RoundService = require(script.Parent.RoundService)

local TrickService = {}
TrickService.TrickLanded = Signal.new()

-- ── Tuning ──────────────────────────────────────────────────────────────
local SAMPLE_SECONDS = 1 / TrickTable.Server.SampleHz
local REPORT_RATE = { Capacity = 3, RefillPerSecond = TrickTable.Server.ReportRateLimit }
local BUY_RATE = { Capacity = 3, RefillPerSecond = 0.5 }
local EQUIP_RATE = { Capacity = 5, RefillPerSecond = 1 }
local MATCH_TOLERANCE = 1 -- seconds between a report's times and the server's airtime record
local REPORT_TTL = 6 -- seconds an unmatched report or airtime record is kept
local MAX_PENDING = 4 -- reports and airtime records kept per player
local MAX_VOID_TIMES = 16
local JUMP_PAD_TAG = "JumpPad"
local JUMP_PAD_MARGIN = 16 -- studs; a pad this close to the ball explains a vertical gain
local SPRING_LIFT_SECONDS = 1.5
local LIFT_GRACE_SECONDS = 0.3 -- extra window after a lift event for sampling jitter
local RACE_STATE = "Race"
local SINK = "Shop"
local TRICK_SOURCE = "Trick"
local TRICK_SKU = "Tricks"

local ASSIST_TOOL_IDS = { glider = true, grapple = true, coil = true } -- ToolService ids that halve an airtime (GDD 7.5)
local LIFT_TOOL_IDS = { spring = true, rocket = true, grapple = true } -- ids that explain a vertical gain (GDD 7.9)

local TOOL_ASSISTS = { -- tool id -> assist key and window seconds
	coil = { Key = "Coil", Seconds = ToolTable.Tools.coil.Duration },
	glider = { Key = "Glider", Seconds = ToolTable.Tools.glider.MaxDuration },
	grapple = { Key = "Grapple", Seconds = ToolTable.Tools.grapple.MaxPullSeconds },
}
local TOOL_LIFTS = { -- tool id -> seconds a vertical gain is explained
	spring = SPRING_LIFT_SECONDS,
	rocket = ToolTable.Tools.rocket.HoldSeconds + ToolTable.Tools.rocket.GraceSeconds,
	grapple = ToolTable.Tools.grapple.MaxPullSeconds,
}

-- ── State ───────────────────────────────────────────────────────────────
local states = {} -- [player] = per-player runtime state, see newState
local ledgers = {} -- [userId] = TrickRules ledger for this round
local summaries = {} -- [userId] = round summary for TrickRoundSummary
local isRaceOpen = false
local toolService = nil -- set once ToolService loads and exposes WasActive
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true
rayParams.IgnoreWater = true

local function now()
	return workspace:GetServerTimeNow()
end

local function newState()
	return {
		Tracker = TrickRules.NewTracker(),
		Airs = {}, -- finished airtime records waiting for a report or their confirm window
		Reports = {}, -- validated client reports waiting for their airtime record
		VoidTimes = {},
		Assist = {}, -- [key] = { From, Until }
		LiftUntil = 0,
		LastSampleTime = nil,
		Loadout = nil, -- snapshot taken at takeoff
		Segment = 1,
	}
end

local function newSummary(player)
	return {
		Player = player,
		Airtimes = 0,
		Clean = 0,
		Sloppy = 0,
		Bail = 0,
		Rejected = 0,
		Points = 0,
		BaseCoins = 0,
		BestPoints = 0,
		HitRoundCap = false,
		CappedSegments = {},
		Equipped = "",
		Sent = false,
	}
end

local function getLedger(player)
	local ledger = ledgers[player.UserId]
	if not ledger then
		ledger = TrickRules.NewLedger()
		ledgers[player.UserId] = ledger
		local summary = newSummary(player)
		local equipped = PlayerData.Peek(player, "equippedTricks")
		summary.Equipped = if type(equipped) == "table" then table.concat(equipped, ",") else ""
		summaries[player.UserId] = summary
	end
	summaries[player.UserId].Player = player
	return ledger, summaries[player.UserId]
end

-- ── Analytics ───────────────────────────────────────────────────────────

local function logRejected(player, reason, overshoot)
	local summary = summaries[player.UserId]
	if summary then
		summary.Rejected += 1
	end
	AnalyticsService.Custom(player, AnalyticsTable.Events.TrickRejected, overshoot or 0, { Reason = reason })
end

local function sendSummary(summary)
	if summary.Sent then
		return
	end
	summary.Sent = true
	local capped = 0
	for _ in summary.CappedSegments do
		capped += 1
	end
	if not summary.Player.Parent then
		return
	end
	AnalyticsService.Custom(summary.Player, AnalyticsTable.Events.TrickRoundSummary, summary.Points, {
		Airtimes = summary.Airtimes,
		Clean = summary.Clean,
		Sloppy = summary.Sloppy,
		Bail = summary.Bail,
		Rejected = summary.Rejected,
		BaseCoins = summary.BaseCoins,
		HitRoundCap = summary.HitRoundCap,
		CappedSegments = capped,
		BestPoints = summary.BestPoints,
		Equipped = summary.Equipped,
	})
end

-- ── Void events ─────────────────────────────────────────────────────────

local function noteVoid(player)
	local state = states[player]
	if not state then
		return
	end
	local list = state.VoidTimes
	table.insert(list, now())
	if #list > MAX_VOID_TIMES then
		table.remove(list, 1)
	end
end

-- Inserted first so a Shield that absorbs the fall later in the list still counts as a rescue (GDD 7.2).
table.insert(ProgressService.FallInterceptors, 1, function(player)
	noteVoid(player)
	return false
end)
ProgressService.Fell:Connect(noteVoid)
ProgressService.Skipped:Connect(noteVoid)
ProgressService.AntiCheatFlag:Connect(noteVoid)
BallService.BallSpawned:Connect(noteVoid)

-- ── Settling ────────────────────────────────────────────────────────────

local function segmentOf(player)
	local progress = ProgressService.GetState(player)
	local count = math.max(CourseService.GetSegmentCount(), 1)
	local index = if progress then math.min(progress.Checkpoint + 1, count) else 1
	local checkpoint = CourseService.GetCheckpoint(index)
	return index, checkpoint and checkpoint.Tier or nil
end

local function snapshotLoadout(player)
	local equipped = PlayerData.Peek(player, "equippedTricks")
	local levels = PlayerData.Peek(player, "trickLevels")
	return {
		Equipped = if type(equipped) == "table" then table.clone(equipped) else {},
		Levels = if type(levels) == "table" then table.clone(levels) else {},
	}
end

local function filterPlayable(player, trickIds, loadout)
	local owned = PlayerData.Peek(player, "ownedTricks")
	local equipped = {}
	for _, trickId in loadout.Equipped do
		equipped[trickId] = true
	end
	local kept = {}
	local reason = nil
	for _, trickId in trickIds do
		if not TrickRules.IsOwned(trickId, owned) then
			reason = "NotOwned"
		elseif not equipped[trickId] then
			reason = "NotEquipped"
		else
			table.insert(kept, trickId)
		end
	end
	return kept, reason
end

local function recordStats(player, landed, points)
	local stats = PlayerData.Peek(player, "stats")
	if type(stats) ~= "table" then
		return
	end
	if landed > 0 then
		PlayerData.SetPath(player, "stats.tricksLanded", (stats.tricksLanded or 0) + landed)
	end
	if points > (stats.bestTrickPoints or 0) then
		PlayerData.SetPath(player, "stats.bestTrickPoints", points)
	end
end

local function sendResult(player, grade, points, coins, flags)
	Network.FireClient(player, "TrickResult", grade, points, coins, flags)
end

local function settle(player, state, record, isRoundEnd)
	local air = record.Air
	local ledger, summary = getLedger(player)
	local flags = { Trimmed = false, SegmentCapped = false, RoundCapped = false, RoundCapReached = false }

	if isRoundEnd then
		noteVoid(player)
	end
	local isVoid = TrickRules.IsVoid(air, state.VoidTimes, TrickTable.Config.LandConfirm)
	summary.Airtimes += 1

	if isVoid then
		summary.Bail += 1
		sendResult(player, "Bail", 0, 0, flags)
		return
	end

	if air.Unexplained then
		logRejected(player, "Ballistic", 0)
		if TrickRules.NoteUnexplained(ledger) then
			BallService.AddStrike(player, "Trick")
		end
		sendResult(player, "Bail", 0, 0, flags)
		return
	end

	local trickIds, rejectReason = filterPlayable(player, record.Report.TrickIds, record.Loadout)
	if rejectReason then
		logRejected(player, rejectReason, 0)
	end
	if #trickIds == 0 then
		return
	end

	local fit = TrickRules.Fit(trickIds, air.Duration)
	if fit.Overshoot > TrickTable.Server.StrikeOvershootSeconds then
		logRejected(player, "DidntFit", fit.Overshoot)
		BallService.AddStrike(player, "Trick")
	elseif fit.Dropped > 0 and #fit.Entries == 0 then
		logRejected(player, "DidntFit", fit.Overshoot)
	end
	if #fit.Entries == 0 then
		return
	end

	local assisted = if toolService
		then toolService.WasActive(player, ASSIST_TOOL_IDS, air.StartT, air.EndT)
		else TrickRules.AssistedIn(state.Assist, air.StartT, air.EndT)
	local result = TrickRules.Score(fit.Entries, { Levels = record.Loadout.Levels, Assisted = assisted })
	local points = result.Points
	ledger.Points += points

	local cap = TrickRules.SegmentCap(record.Tier)
	local baseCoins, capFlags = TrickRules.Settle(ledger, record.Segment, points, cap)
	flags.Trimmed, flags.SegmentCapped, flags.RoundCapped =
		capFlags.Trimmed, capFlags.SegmentCapped, capFlags.RoundCapped
	if capFlags.RoundCapped and not summary.HitRoundCap then
		summary.HitRoundCap = true
		flags.RoundCapReached = true
	end
	if capFlags.SegmentCapped then
		summary.CappedSegments[record.Segment] = true
	end

	local coins = 0
	if baseCoins > 0 then
		coins = EconomyService.Award(player, baseCoins, TRICK_SOURCE, { Kind = "Trick", Sku = TRICK_SKU })
	end

	local stats = PlayerData.Peek(player, "stats")
	local isFirstEver = type(stats) == "table" and (stats.tricksLanded or 0) == 0 and points > 0
	local landed = 0
	for _, part in result.Parts do
		if part > 0 then
			landed += 1
		end
	end
	recordStats(player, landed, points)

	summary.Points += points
	summary.BaseCoins += baseCoins
	summary.BestPoints = math.max(summary.BestPoints, points)
	if result.Grade == "Sloppy" then
		summary.Sloppy += 1
	else
		summary.Clean += 1
	end

	sendResult(player, result.Grade, points, coins, flags)
	if points > 0 then
		TrickService.TrickLanded:Fire(player, points, coins, landed)
	end
	if isFirstEver then
		Network.FireClient(player, "FirstTrick")
		AnalyticsService.Funnel(player, "Onboarding", "FirstTrickLanded")
	end
end

-- ── Reports ─────────────────────────────────────────────────────────────

local function findMatch(state, report)
	local bestIndex, bestGap = nil, math.huge
	for index, record in state.Airs do
		if record.Report == nil then
			local landedGap = math.abs(record.Air.EndT - report.LandedAt)
			local startedGap = math.abs(record.Air.StartT - report.StartedAt)
			if landedGap <= MATCH_TOLERANCE and startedGap <= MATCH_TOLERANCE and landedGap < bestGap then
				bestIndex, bestGap = index, landedGap
			end
		end
	end
	return bestIndex
end

local function pairReports(state)
	for reportIndex = #state.Reports, 1, -1 do
		local report = state.Reports[reportIndex].Report
		local airIndex = findMatch(state, report)
		if airIndex then
			state.Airs[airIndex].Report = report
			table.remove(state.Reports, reportIndex)
		end
	end
end

local function pushLimited(list, item)
	table.insert(list, item)
	while #list > MAX_PENDING do
		table.remove(list, 1)
	end
end

local function isRacing(player)
	local progress = ProgressService.GetState(player)
	return progress ~= nil and progress.Racing and not progress.Finished
end

Network.OnEvent("TrickLanded", function(player, report)
	local state = states[player]
	if not state or not PlayerData.IsLoaded(player) or workspace:GetAttribute("RoundState") ~= RACE_STATE then
		return
	end
	local cleaned, reason = TrickRules.ValidateReport(report)
	if not cleaned then
		logRejected(player, reason, 0)
		return
	end
	pushLimited(state.Reports, { Report = cleaned, ReceivedAt = now() })
end, REPORT_RATE)

-- ── Sampling loop ───────────────────────────────────────────────────────

local function jumpPadNear(position)
	for _, instance in CollectionService:GetTagged(JUMP_PAD_TAG) do
		local parts = if instance:IsA("BasePart") then { instance } else instance:GetDescendants()
		for _, part in parts do
			if part:IsA("BasePart") and SpeedAudit.IsNearBox(position, part.CFrame, part.Size, JUMP_PAD_MARGIN) then
				return true
			end
		end
	end
	return false
end

local function groundDistance(position, radius)
	local reach = radius + TrickTable.Config.AirClearanceExtra
	local result = workspace:Raycast(position, Vector3.new(0, -reach, 0), rayParams)
	return if result then result.Distance else nil
end

local function sampleBall(player, state, ball, sample, time)
	local primary = ball.PrimaryPart
	if not primary then
		return
	end
	local radius = primary.Size.Y / 2
	local liftActive = time <= state.LiftUntil + LIFT_GRACE_SECONDS
		or (toolService ~= nil and toolService.WasActive(player, LIFT_TOOL_IDS, time - LIFT_GRACE_SECONDS, time))
	local position = sample.Position
	local event = TrickRules.Feed(state.Tracker, {
		Time = time,
		Radius = radius,
		GroundDistance = groundDistance(position, radius),
		VerticalVelocity = sample.Velocity.Y,
		Explained = function()
			return liftActive or jumpPadNear(position)
		end,
		FreeGains = if ball:GetAttribute("DoubleJumpEnabled") == true then 1 else 0,
	})
	if not event then
		return
	end

	if event.Type == "Takeoff" then
		state.Loadout = snapshotLoadout(player)
		state.Segment = segmentOf(player)
		return
	end

	local air = event.Air
	-- Anything shorter than the first trick plus tolerance can never pay, so don't keep it.
	if air.Duration < TrickTable.Config.MinAirtime - TrickTable.Server.FitToleranceSeconds then
		return
	end
	local index, tier = segmentOf(player)
	pushLimited(state.Airs, {
		Air = air,
		Loadout = state.Loadout or snapshotLoadout(player),
		Segment = state.Segment or index,
		Tier = tier or "Beginner",
		CreatedAt = time,
	})
end

local function processPending(player, state, time, isRoundEnd)
	pairReports(state)
	for index = #state.Airs, 1, -1 do
		local record = state.Airs[index]
		local confirmAt = record.Air.EndT + TrickTable.Config.LandConfirm
		if record.Report and (time >= confirmAt or isRoundEnd) then
			table.remove(state.Airs, index)
			local ok, err = pcall(settle, player, state, record, isRoundEnd)
			if not ok then
				warn(`[TrickService] Settling a trick for {player.Name} failed: {err}`)
			end
		elseif time - confirmAt > REPORT_TTL or isRoundEnd then
			table.remove(state.Airs, index)
		end
	end
	for index = #state.Reports, 1, -1 do
		if isRoundEnd or time - state.Reports[index].ReceivedAt > REPORT_TTL then
			table.remove(state.Reports, index)
			if not isRoundEnd then
				logRejected(player, "NoAirtime", 0)
			end
		end
	end
	local cutoff = time - REPORT_TTL
	while state.VoidTimes[1] and state.VoidTimes[1] < cutoff do
		table.remove(state.VoidTimes, 1)
	end
end

local function stepPlayer(player, state, time)
	local ball = BallService.GetBall(player)
	local sample = BallService.GetSample(player)
	local racing = isRacing(player) and workspace:GetAttribute("RoundState") == RACE_STATE

	if racing then
		getLedger(player)
	end
	if not racing or not ball or not sample then
		-- A cleared sample means the ball was respawned or moved; an airtime in progress can't continue.
		if state.Tracker.Airborne then
			noteVoid(player)
		end
		state.Tracker = TrickRules.NewTracker()
		state.LastSampleTime = nil
		processPending(player, state, time, false)
		return
	end

	if sample.Time ~= state.LastSampleTime then
		state.LastSampleTime = sample.Time
		if CourseService.FindFallSegment(sample.Position) then
			noteVoid(player)
		end
		sampleBall(player, state, ball, sample, time)
	end
	processPending(player, state, time, false)
end

local function refreshRayFilter()
	local balls = workspace:FindFirstChild(PhysicsTable.Ball.FolderName)
	rayParams.FilterDescendantsInstances = if balls then { balls } else {}
end

local function runLoop()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < SAMPLE_SECONDS then
			return
		end
		elapsed = 0
		refreshRayFilter()
		local time = now()
		for player, state in states do
			local ok, err = pcall(stepPlayer, player, state, time)
			if not ok and not state.Warned then
				state.Warned = true
				warn(`[TrickService] Step failed for {player.Name}: {err}`)
			end
		end
	end)
end

-- ── Round flow ──────────────────────────────────────────────────────────

local function endRace()
	local time = now()
	for player, state in states do
		state.Tracker = TrickRules.NewTracker()
		processPending(player, state, time, true)
	end
	for _, summary in summaries do
		sendSummary(summary)
	end
end

RoundService.StateChanged:Connect(function(stateName)
	if stateName == RACE_STATE then
		isRaceOpen = true
		return
	end
	if isRaceOpen then
		isRaceOpen = false
		endRace()
	end
	if stateName == "Countdown" or stateName == "BuildCourse" or stateName == "Intermission" then
		table.clear(ledgers)
		table.clear(summaries)
	end
end)

-- ── Assists and lifts (ToolService feeds these) ─────────────────────────

function TrickService.MarkAssist(player, key, seconds)
	local state = states[player]
	if not state or type(seconds) ~= "number" or seconds <= 0 then
		return false
	end
	if key ~= "Glider" and key ~= "Grapple" and key ~= "Coil" then
		return false
	end
	local time = now()
	local window = state.Assist[key]
	if window and window.Until >= time then
		window.Until = math.max(window.Until, time + seconds)
	else
		state.Assist[key] = { From = time, Until = time + seconds }
	end
	return true
end

function TrickService.MarkLift(player, seconds)
	local state = states[player]
	if not state or type(seconds) ~= "number" or seconds <= 0 then
		return false
	end
	state.LiftUntil = math.max(state.LiftUntil, now() + seconds)
	return true
end

local function onToolUsed(player, toolId)
	local assist = TOOL_ASSISTS[toolId]
	if assist then
		TrickService.MarkAssist(player, assist.Key, assist.Seconds)
	end
	local lift = TOOL_LIFTS[toolId]
	if lift then
		TrickService.MarkLift(player, lift)
	end
end

-- ── Shop, ownership and loadout ─────────────────────────────────────────

local function setOwned(player, trickId)
	local owned = PlayerData.Get(player, "ownedTricks")
	if type(owned) ~= "table" then
		return false
	end
	owned[trickId] = true
	return PlayerData.Set(player, "ownedTricks", owned)
end

local function setLevel(player, trickId, level)
	local levels = PlayerData.Get(player, "trickLevels")
	if type(levels) ~= "table" then
		return false
	end
	levels[trickId] = level
	return PlayerData.Set(player, "trickLevels", levels)
end

function TrickService.GrantTrick(player, trickId)
	local trick = type(trickId) == "string" and TrickTable.Tricks[trickId] or nil
	if not trick or trick.Tier == "Free" or not PlayerData.IsLoaded(player) then
		return false
	end
	if TrickRules.IsOwned(trickId, PlayerData.Peek(player, "ownedTricks")) then
		return false
	end
	return setOwned(player, trickId)
end

function TrickService.GrantLevel(player, trickId, level)
	if type(trickId) ~= "string" or not TrickTable.Tricks[trickId] or type(level) ~= "number" then
		return false
	end
	level = math.clamp(math.floor(level), 1, TrickTable.Scoring.MaxLevel)
	if not PlayerData.IsLoaded(player) then
		return false
	end
	local levels = PlayerData.Peek(player, "trickLevels")
	local current = type(levels) == "table" and levels[trickId] or 1
	if level <= current then
		return false
	end
	return setLevel(player, trickId, level)
end

function TrickService.BuyTrick(player, trickId)
	if not PlayerData.IsLoaded(player) then
		return false, "Failed"
	end
	local ok, reason, price = TrickShopRules.DecideBuy(trickId, {
		Owned = PlayerData.Peek(player, "ownedTricks") or {},
		Coins = EconomyService.GetCoins(player),
	})
	if not ok then
		return false, reason
	end
	if not EconomyService.SpendCoins(player, price, SINK, trickId) then
		return false, "NoFunds"
	end
	if not setOwned(player, trickId) then
		warn(`[TrickService] Grant of {trickId} failed after charging {price}; refunding`)
		EconomyService.AddCoins(player, price, "Refund", trickId)
		return false, "Failed"
	end
	AnalyticsService.Custom(
		player,
		AnalyticsTable.Events.TrickPurchased,
		price,
		{ TrickId = trickId, Currency = "Coins" }
	)
	return true, nil
end

function TrickService.UpgradeTrick(player, trickId)
	if not PlayerData.IsLoaded(player) then
		return false, "Failed"
	end
	local ok, reason, price, newLevel = TrickShopRules.DecideUpgrade(trickId, {
		Owned = PlayerData.Peek(player, "ownedTricks") or {},
		Levels = PlayerData.Peek(player, "trickLevels") or {},
		Coins = EconomyService.GetCoins(player),
	})
	if not ok then
		return false, reason
	end
	if not EconomyService.SpendCoins(player, price, SINK, `{trickId}_L{newLevel}`) then
		return false, "NoFunds"
	end
	if not setLevel(player, trickId, newLevel) then
		warn(`[TrickService] Upgrade of {trickId} failed after charging {price}; refunding`)
		EconomyService.AddCoins(player, price, "Refund", trickId)
		return false, "Failed"
	end
	AnalyticsService.Custom(
		player,
		AnalyticsTable.Events.TrickUpgraded,
		price,
		{ TrickId = trickId, Level = newLevel, Currency = "Coins" }
	)
	return true, nil
end

function TrickService.EquipTricks(player, list)
	if not PlayerData.IsLoaded(player) then
		return false, "Failed"
	end
	local slots, reason = TrickShopRules.DecideEquip(list, PlayerData.Peek(player, "ownedTricks") or {})
	if not slots then
		return false, reason
	end
	if not PlayerData.Set(player, "equippedTricks", slots) then
		return false, "Failed"
	end
	return true, nil
end

Network.OnEvent("BuyTrick", function(player, trickId)
	if type(trickId) ~= "string" then
		return
	end
	local ok, reason = TrickService.BuyTrick(player, trickId)
	if ok then
		Network.FireClient(player, "TrickPurchased", trickId)
	else
		Network.FireClient(player, "TrickFailed", "Buy", reason)
	end
end, BUY_RATE)

Network.OnEvent("UpgradeTrick", function(player, trickId)
	if type(trickId) ~= "string" then
		return
	end
	local ok, reason = TrickService.UpgradeTrick(player, trickId)
	if ok then
		local levels = PlayerData.Peek(player, "trickLevels")
		Network.FireClient(player, "TrickUpgraded", trickId, levels and levels[trickId] or 1)
	else
		Network.FireClient(player, "TrickFailed", "Upgrade", reason)
	end
end, BUY_RATE)

Network.OnEvent("EquipTricks", function(player, list)
	local ok, reason = TrickService.EquipTricks(player, list)
	if ok then
		Network.FireClient(player, "TricksEquipped", PlayerData.Get(player, "equippedTricks"))
	else
		Network.FireClient(player, "TrickFailed", "Equip", reason)
	end
end, EQUIP_RATE)

-- ── Wiring ──────────────────────────────────────────────────────────────

local function onPlayerAdded(player)
	states[player] = newState()
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	states[player] = nil
	local summary = summaries[player.UserId]
	if summary and isRaceOpen then
		sendSummary(summary)
	end
end)

task.spawn(function()
	local toolModule = script.Parent:FindFirstChild("ToolService")
	if not toolModule then
		return
	end
	local ok, ToolService = pcall(require, toolModule)
	if ok and type(ToolService) == "table" and type(ToolService.WasActive) == "function" then
		toolService = ToolService
	elseif ok and type(ToolService) == "table" and ToolService.ToolUsed then
		ToolService.ToolUsed:Connect(onToolUsed)
	else
		warn("[TrickService] ToolService could not be loaded; call MarkAssist and MarkLift from the tools instead")
	end
end)

runLoop()

return TrickService
