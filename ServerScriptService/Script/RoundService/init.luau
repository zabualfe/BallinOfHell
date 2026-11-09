-- RoundService
-- Endless play: no intermission, loading, countdown or teardown. When the server starts, the course is built once
-- (CourseService chains it from workspace.Lobby.Start's pivot) and stays up, and the race is open for the life of
-- the server. Every player is in ball mode as soon as their data is loaded and their starter is picked: the ball
-- spawns at workspace.Lobby.Spawn and they roll out of the lobby onto the course. Finishing sends them back to the
-- lobby after FINISH_RETURN_SECONDS for another run.
--
-- Public API (kept for the systems that listen to rounds):
--   RoundService.StateChanged   Signal (stateName, roundId)   -- fires "Race" once, when the course is up
--   RoundService.GetMultiplier() -> number                     -- RoundTable.Multiplier.Start; there is no finish
--                                                                 multiplier without rounds
--   RoundService.GetState() -> stateName                       -- "Loading" until the course is built, then "Race"
--   RoundService.AddTime(seconds) -> boolean                   -- always false: there is no round clock
--
-- Workspace attributes (HUD): RoundState, RoundMultiplier, RoundId. RoundTimeLeft and StepEndsAt are never set, so
--   the HUD timer shows its empty text.
-- Network (server -> clients): PlayerFinished(name, place, multiplier, clockRate) to all on each finish.
-- Lobby spawn: workspace.Lobby.Spawn (a BasePart). Missing -> one warn and LOBBY_FALLBACK_CFRAME.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage.Network)
local Signal = require(ReplicatedStorage.Utilities.Signal)
local RoundTable = require(ReplicatedStorage.Tables.RoundTable)

local BallService = require(script.Parent.BallService)
local CourseService = require(script.Parent.CourseService)
local OnboardingService = require(script.Parent.OnboardingService)
local PlayerData = require(script.Parent.PlayerData)
local ProgressService = require(script.Parent.ProgressService)

local RoundService = {}
RoundService.StateChanged = Signal.new()

-- ── Tuning ──────────────────────────────────────────────────────────────
local RACE_STATE = "Race"
local LOADING_STATE = "Loading"
local ROUND_ID = 1 -- one endless round per server
local BUILD_RETRY_SECONDS = 5 -- wait between course build attempts
local DATA_WAIT_TIMEOUT = 60 -- seconds a joiner may take to load before we stop waiting
local CHARACTER_WAIT_TIMEOUT = 10 -- seconds to wait for a character's root part
local LOBBY_LIFT = 5 -- studs above Lobby.Spawn where the ball's centre is placed
local LOBBY_FALLBACK_CFRAME = CFrame.new(0, 20, 300)
local FINISH_RETURN_SECONDS = 5 -- after finishing, how long before the player is back in the lobby

-- ── State ───────────────────────────────────────────────────────────────
local stateName = LOADING_STATE
local isCourseReady = false
local spawning = {} -- [player] = true while a spawn is being set up
local warnedLobby = false

local function setState(name)
	stateName = name
	workspace:SetAttribute("RoundState", name)
	RoundService.StateChanged:Fire(name, ROUND_ID)
end

function RoundService.GetMultiplier()
	return RoundTable.Multiplier.Start
end

function RoundService.GetState()
	return stateName
end

function RoundService.AddTime()
	return false
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

-- Puts the player in ball mode in the lobby with a fresh run, or at their checkpoint when they already have one
-- (a character reset mid-run). false while the course is loading or the player can't have a ball yet.
local function trySpawn(player)
	if spawning[player] or not isCourseReady then
		return false
	end
	if not PlayerData.IsLoaded(player) or PlayerData.Peek(player, "hasPickedStarter") ~= true then
		return false
	end
	local character = player.Character
	if not (character and character.PrimaryPart and character.Parent) then
		return false
	end

	spawning[player] = true
	local progress = ProgressService.GetState(player)
	local cframe = nil
	if progress and progress.Checkpoint > 0 then
		cframe = CourseService.GetSpawnCFrame(progress.Checkpoint)
	else
		if not progress then
			ProgressService.NewRun(player)
		end
		cframe = getLobbyCFrame()
	end
	local spawned = cframe ~= nil and BallService.Spawn(player, cframe)
	spawning[player] = nil
	return spawned
end

local function onCharacterAdded(player)
	task.spawn(function()
		local character = waitForRoot(player)
		if not character then
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

local function startNewRun(player)
	if not player.Parent or not BallService.GetBall(player) then
		return
	end
	ProgressService.NewRun(player)
	BallService.Respawn(player, getLobbyCFrame())
end

ProgressService.Finished:Connect(function(player, place)
	Network.FireAllClients("PlayerFinished", player.Name, place, RoundService.GetMultiplier(), 1)
	task.delay(FINISH_RETURN_SECONDS, startNewRun, player)
end)

-- ── Startup ─────────────────────────────────────────────────────────────

local function buildCourse()
	while not CourseService.Build() do
		warn(`[RoundService] Course build failed; retrying in {BUILD_RETRY_SECONDS}s`)
		task.wait(BUILD_RETRY_SECONDS)
	end
	isCourseReady = true
	ProgressService.BeginRace()
	setState(RACE_STATE)
	for _, player in Players:GetPlayers() do
		task.spawn(trySpawn, player)
	end
end

workspace:SetAttribute("RoundId", ROUND_ID)
workspace:SetAttribute("RoundMultiplier", RoundService.GetMultiplier())
workspace:SetAttribute("RoundState", stateName)
task.spawn(buildCourse)

return RoundService
