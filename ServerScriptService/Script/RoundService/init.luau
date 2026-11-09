-- RoundService
-- Drives the round as an ordered list of steps (AGENTS.md "Sequenced flow", GDD 2):
-- Intermission -> BuildCourse -> Countdown -> Race -> Results -> Teardown, forever. Each step module in Steps/
-- has Name, Run(context) and Skip(context); a Run may return "Abort" to drop the cycle (cleanup still runs).
-- START_STEP (Studio only) names the step the first cycle starts from; earlier steps are Skipped.
--
-- Public API:
--   RoundService.StateChanged   Signal (stateName, roundId)   -- Intermission | BuildCourse | Countdown | Race | Results | Teardown
--   RoundService.GetMultiplier() -> number                     -- current RoundMultiplier (coin systems read this)
--   RoundService.GetState() -> stateName
--   RoundService.AddTime(seconds) -> boolean                   -- +round clock during the Race only (ModifierService)
--
-- Workspace attributes (HUD): RoundState, RoundTimeLeft (round-clock seconds, Race only counts down), RoundMultiplier,
--   ClockRate, RoundId, StepEndsAt (workspace:GetServerTimeNow() when a timed step ends; absent while idle).
-- Network (server -> clients): PlayerFinished(name, place, multiplier, clockRate) to all on each finish;
--   RoundResults(top3, furthestCheckpoint) per player at Results, top3 = { { Name, Time } } in finish order.
--
-- Players: joiners spawn at the start line once data is loaded and the starter is picked (and on StarterPicked), but
-- only while a race is open and at least LateJoinMinClockSeconds of round clock remain; otherwise they wait in the
-- lobby. Teardown resets everyone (ProgressService.ResetAll) and respawns them in the lobby before the course goes.
-- Lobby spawn: workspace.Lobby.Spawn (a BasePart). Missing -> one warn and LOBBY_FALLBACK_CFRAME.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Network = require(ReplicatedStorage.Network)
local Signal = require(ReplicatedStorage.Utilities.Signal)
local RoundTable = require(ReplicatedStorage.Tables.RoundTable)

local BallService = require(script.Parent.BallService)
local CourseService = require(script.Parent.CourseService)
local OnboardingService = require(script.Parent.OnboardingService)
local PlayerData = require(script.Parent.PlayerData)
local ProgressService = require(script.Parent.ProgressService)
local RoundMath = require(script.RoundMath)
local StepRunner = require(script.StepRunner)

local RoundService = {}
RoundService.StateChanged = Signal.new()

-- ── Tuning ──────────────────────────────────────────────────────────────
local START_STEP = "" -- Studio only: step the first cycle starts from ("" = Intermission)
local STEP_ORDER = { "Intermission", "BuildCourse", "Countdown", "Race", "Results", "Teardown" }
local WAIT_TICK = 0.25 -- seconds between checks in timed waits
local RESTART_DELAY = 3 -- seconds before the loop restarts after an error
local DATA_WAIT_TIMEOUT = 60 -- seconds a joiner may take to load before we stop waiting
local CHARACTER_WAIT_TIMEOUT = 10 -- seconds to wait for a character's root part
local LOBBY_LIFT = 5 -- studs above Lobby.Spawn where players are placed
local LOBBY_FALLBACK_CFRAME = CFrame.new(0, 20, 300)
local RESULTS_TOP_COUNT = 3
local TEARDOWN_TICK = 0.1 -- seconds between checks while players are returned to the lobby

-- ── State ───────────────────────────────────────────────────────────────
local stateName = "Intermission"
local roundId = 0
local finishers = {} -- { { Player, Name, Time } } in finish order
local timeLeft = RoundTable.Steps.Race
local spawnOpen = false
local isFrozen = false
local spawning = {} -- [player] = true while a spawn is being set up
local warnedLobby = false
local useStartStep = true

-- ── Round values ────────────────────────────────────────────────────────

local function currentMultiplier()
	return RoundMath.Multiplier(#finishers, RoundTable.Multiplier)
end

local function currentClockRate()
	return RoundMath.ClockRate(#finishers, RoundTable.ClockRate)
end

local function publishValues()
	workspace:SetAttribute("RoundId", roundId)
	workspace:SetAttribute("RoundMultiplier", currentMultiplier())
	workspace:SetAttribute("ClockRate", currentClockRate())
	workspace:SetAttribute("RoundTimeLeft", math.floor(timeLeft * 10) / 10)
end

function RoundService.GetMultiplier()
	return currentMultiplier()
end

function RoundService.GetState()
	return stateName
end

-- Adds round-clock seconds during the Race (+2 Min product). false outside the Race or for a bad amount.
function RoundService.AddTime(seconds)
	if stateName ~= "Race" or type(seconds) ~= "number" or seconds ~= seconds or seconds <= 0 then
		return false
	end
	timeLeft += seconds
	publishValues()
	return true
end

-- ── Lobby and spawning ──────────────────────────────────────────────────

local function getLobbyCFrame()
	local lobby = workspace:FindFirstChild("Lobby")
	local spawnPart = lobby and lobby:FindFirstChild("Spawn")
	if spawnPart and spawnPart:IsA("BasePart") then
		return spawnPart.CFrame + Vector3.new(0, LOBBY_LIFT, 0)
	end
	if not warnedLobby then
		warnedLobby = true
		warn("[RoundService] workspace.Lobby.Spawn (BasePart) is missing; using the fallback lobby position")
	end
	return LOBBY_FALLBACK_CFRAME
end

local function waitForRoot(player)
	local character = player.Character
	if not character then
		return nil
	end
	if not character:WaitForChild("HumanoidRootPart", CHARACTER_WAIT_TIMEOUT) then
		return nil
	end
	if player.Character ~= character or not character.Parent then
		return nil
	end
	return character
end

local function setBallFrozen(player, frozen)
	local ball = BallService.GetBall(player)
	if not ball then
		return
	end
	for _, descendant in ball:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = frozen
		end
	end
end

local function trySpawn(player)
	if spawning[player] or not spawnOpen or ProgressService.GetState(player) then
		return false
	end
	-- Finished this round (even before leaving and rejoining): waits in the lobby.
	if ProgressService.HasFinished(player) then
		return false
	end
	if not RoundMath.CanLateJoin(timeLeft, RoundTable.LateJoinMinClockSeconds) then
		return false
	end
	if not PlayerData.IsLoaded(player) or PlayerData.Peek(player, "hasPickedStarter") ~= true then
		return false
	end
	local character = player.Character
	local cframe = CourseService.GetSpawnCFrame(0)
	if not (cframe and character and character.PrimaryPart and character.Parent) then
		return false
	end

	spawning[player] = true
	local started = ProgressService.StartPlayer(player)
	if not started then
		spawning[player] = nil
		return false
	end
	-- A rejoiner resumes at their checkpoint.
	cframe = CourseService.GetSpawnCFrame(started.Checkpoint) or cframe
	local spawned = BallService.Spawn(player, cframe)
	if spawned then
		if isFrozen then
			setBallFrozen(player, true)
		end
	else
		ProgressService.ResetPlayer(player)
	end
	spawning[player] = nil
	return spawned
end

local function returnToLobby(player)
	BallService.Despawn(player)
	ProgressService.ResetPlayer(player)
	if player.Parent then
		-- A fresh character: BallService made the old root invisible under the ball.
		local ok, err = pcall(player.LoadCharacter, player)
		if not ok then
			warn(`[RoundService] LoadCharacter failed for {player.Name}: {err}`)
		end
	end
end

local function onCharacterAdded(player)
	task.spawn(function()
		local character = waitForRoot(player)
		if not character then
			return
		end
		local progress = ProgressService.GetState(player)
		if progress then
			-- Reset or respawned mid-race: put a new ball at the last checkpoint.
			local cframe = CourseService.GetSpawnCFrame(progress.Checkpoint)
			if cframe and BallService.Spawn(player, cframe) and isFrozen then
				setBallFrozen(player, true)
			end
			return
		end
		if not trySpawn(player) then
			character:PivotTo(getLobbyCFrame())
		end
	end)
end

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(function()
		onCharacterAdded(player)
	end)
	if player.Character then
		onCharacterAdded(player)
	end
	if PlayerData.WaitForLoaded(player, DATA_WAIT_TIMEOUT) and player.Parent then
		trySpawn(player)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	spawning[player] = nil
end)

OnboardingService.StarterPicked:Connect(function(player)
	trySpawn(player)
end)

-- ── Finishes ────────────────────────────────────────────────────────────

-- ProgressService only fires Finished while the race is open and once per UserId per round, and its place is the
-- single finisher count; RoundService just records it so the two can't drift.
ProgressService.Finished:Connect(function(player, place, time)
	table.insert(finishers, { Name = player.Name, Time = time, Place = place })
	publishValues()
	Network.FireAllClients("PlayerFinished", player.Name, place, currentMultiplier(), currentClockRate())
end)

-- ── Step context ────────────────────────────────────────────────────────
-- Everything a step is allowed to do; steps hold no state of their own.
local context = { Config = RoundTable, Tick = WAIT_TICK }

function context.SetState(name)
	stateName = name
	workspace:SetAttribute("RoundState", name)
	RoundService.StateChanged:Fire(name, roundId)
end

-- Waits `seconds` of real time. With requirePlayers the timer restarts while the server is empty.
function context.Wait(seconds, requirePlayers)
	local endsAt = os.clock() + seconds
	local isIdle = nil
	while true do
		local now = os.clock()
		local empty = requirePlayers and #Players:GetPlayers() == 0
		if empty then
			endsAt = now + seconds
		elseif now >= endsAt then
			break
		end
		if empty ~= isIdle then
			isIdle = empty
			workspace:SetAttribute("StepEndsAt", if empty then nil else workspace:GetServerTimeNow() + (endsAt - now))
		end
		task.wait(WAIT_TICK)
	end
	workspace:SetAttribute("StepEndsAt", nil)
end

function context.Build()
	return CourseService.Build()
end

function context.OpenSpawning()
	spawnOpen = true
	for _, player in Players:GetPlayers() do
		task.spawn(trySpawn, player)
	end
end

function context.SetFrozen(frozen)
	isFrozen = frozen
	for _, player in Players:GetPlayers() do
		setBallFrozen(player, frozen)
	end
end

function context.BeginRace()
	ProgressService.BeginRace()
end

function context.EndRace()
	spawnOpen = false
	ProgressService.EndRace()
end

function context.HasPlayers()
	return #Players:GetPlayers() > 0
end

function context.GetTimeLeft()
	return timeLeft
end

function context.SetTimeLeft(seconds)
	timeLeft = seconds
	publishValues()
end

-- Advances the round clock by dt real seconds at the current ClockRate; returns the time left.
function context.AdvanceClock(dt)
	timeLeft = RoundMath.AdvanceClock(timeLeft, dt, currentClockRate())
	publishValues()
	return timeLeft
end

function context.PublishResults()
	local top = {}
	for index = 1, math.min(#finishers, RESULTS_TOP_COUNT) do
		table.insert(top, { Name = finishers[index].Name, Time = finishers[index].Time })
	end
	for _, player in Players:GetPlayers() do
		local progress = ProgressService.GetState(player)
		Network.FireClient(player, "RoundResults", top, progress and progress.Checkpoint or 0)
	end
end

-- Resets every player and returns them to the lobby, then removes the course (players first so nobody is standing on it).
-- Each player is returned in its own thread (LoadCharacter yields); we wait up to TeardownMax for all of them.
-- The course teardown has its own pcall so a failure earlier can't leave a stale course.
function context.Teardown()
	spawnOpen = false
	isFrozen = false
	local okReset, resetErr = pcall(ProgressService.ResetAll)
	if not okReset then
		warn("[RoundService] ProgressService.ResetAll failed: " .. tostring(resetErr))
	end

	local pending = 0
	for _, player in Players:GetPlayers() do
		pending += 1
		task.spawn(function()
			local ok, err = pcall(returnToLobby, player)
			if not ok then
				warn(`[RoundService] Returning {player.Name} to the lobby failed: {err}`)
			end
			pending -= 1
		end)
	end
	local deadline = os.clock() + RoundTable.Steps.TeardownMax
	while pending > 0 and os.clock() < deadline do
		task.wait(TEARDOWN_TICK)
	end
	if pending > 0 then
		warn(`[RoundService] {pending} player(s) still returning to the lobby after {RoundTable.Steps.TeardownMax}s`)
	end

	local okCourse, courseErr = pcall(CourseService.Teardown)
	if not okCourse then
		warn("[RoundService] CourseService.Teardown failed: " .. tostring(courseErr))
	end
end

-- ── Loop ────────────────────────────────────────────────────────────────

local steps = {}
for _, name in STEP_ORDER do
	table.insert(steps, require(script.Steps[name]))
end

local function beginCycle()
	roundId += 1
	finishers = {}
	timeLeft = RoundTable.Steps.Race
	workspace:SetAttribute("StepEndsAt", nil)
	publishValues()
end

local function runCycle()
	beginCycle()
	local startName
	if useStartStep and RunService:IsStudio() then
		startName = START_STEP
	end
	useStartStep = false
	local _, startFound = StepRunner.Plan(steps, startName)
	if not startFound then
		warn(`[RoundService] START_STEP {startName} is not a step; running from the beginning`)
	end
	local completed = StepRunner.Run(steps, startName, context)
	if not completed then
		context.Teardown()
	end
end

local function supervise()
	while true do
		local ok, err = xpcall(runCycle, debug.traceback)
		if not ok then
			warn("[RoundService] Round loop failed, restarting: " .. tostring(err))
			local cleaned, cleanErr = xpcall(context.Teardown, debug.traceback)
			if not cleaned then
				warn("[RoundService] Cleanup after failure also failed: " .. tostring(cleanErr))
			end
			task.wait(RESTART_DELAY)
		end
	end
end

task.spawn(supervise)

return RoundService
