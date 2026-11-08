-- TrickController
-- Client half of the automatic tricks (GDD 7). The player never presses anything: when the local ball has been in
-- the air long enough, this module picks the best sequence of equipped tricks that will finish before landing
-- (TrickRules.PlanBest), plays the rider animations, and after touchdown reports what it played. The server
-- (TrickService) recomputes everything and pays; the numbers shown here are a prediction.
--
-- Animations: TrickTable.Tricks[id].AnimationId. While an id is "" (not supplied yet) nothing plays and one warning is
-- logged, but the picker, scoring, popups and report run the same, so coins are unaffected.
-- settings.showTricks = false (GDD 7.7): no animation and no FOV punch; the picker, popups and report still run.
--
-- Public API:
--   TrickController.Popup       Signal (text, points, grade, info?)  -- for the future TrickPopupUI, no UI here
--       grade "Trick" (a trick started: text = its name) | "Chain" (text "x1.5") | "Mixed" ("MIXED +25%")
--           | "Clean" | "Sloppy" | "Bail" (landing: text "CLEAN! 210") | "RoundCap" (toast text)
--       info is nil for the live ones. Landings fire twice: first the prediction (info nil), then the server's answer
--       with info = { Final = true, Coins, Flags = { Trimmed, SegmentCapped, RoundCapped, RoundCapReached } }, which
--       replaces the prediction (the number can only be lower or equal).
--   TrickController.FirstTrick  Signal ()   -- the server's "first trick ever": show "Big air = auto tricks = bonus coins!"
--   TrickController.SetToolState(kind, active)   -- ToolController calls it: kind "Glider" | "Grapple" | "Coil".
--       Glider and Grapple block new tricks while active; any of the three halves the predicted score once.
--   TrickController.IsPlaying() -> boolean
--
-- Network out: TrickLanded({ trickIds, startedAt, landedAt }) once per airtime that played a trick; times are
--   workspace:GetServerTimeNow(). Network in: TrickResult, FirstTrick, and Fell / BallPivot / Skipped (they void the
--   airtime in progress: "BAIL!" and no report).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Network = require(ReplicatedStorage.Network)
local TrickRules = require(ReplicatedStorage.Shared.TrickRules)
local Signal = require(ReplicatedStorage.Utilities.Signal)
local PhysicsTable = require(ReplicatedStorage.Tables.PhysicsTable)
local TrickTable = require(ReplicatedStorage.Tables.TrickTable)

local BallController = require(script.Parent.BallController)
local CameraController = require(script.Parent.CameraController)
local PlayerData = require(script.Parent.PlayerData)

local TrickController = {}
TrickController.Popup = Signal.new()
TrickController.FirstTrick = Signal.new()

-- ── Tuning ──────────────────────────────────────────────────────────────
local CONFIG = TrickTable.Config
local BLEND_SECONDS = CONFIG.BlendSeconds -- between tricks
local LANDING_BLEND_SECONDS = CONFIG.LandingBlendSeconds -- back to the riding pose after touchdown (GDD 7.4)
local CHAIN_FOV_FROM = 3 -- the 3rd trick and up punch the FOV
local CHAIN_FOV_DEGREES = 5
local PUNCH_FOV_REFERENCE = 12 -- CameraController.Punch(1) widens by this many degrees
local BALLS_FOLDER_NAME = PhysicsTable.Ball.FolderName
local RACE_STATE = "Race"

-- ── State ───────────────────────────────────────────────────────────────
local character = nil
local animator = nil
local trackCache = {} -- [trickId] = AnimationTrack
local warnedNoAnimation = false
local activeBall = nil
local isAirborne = false
local air = nil -- { StartClock, StartServer, Played, Current, NextCheck, Assisted, Distinct } while airborne
local toolActive = { Glider = false, Grapple = false, Coil = false }

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true
rayParams.IgnoreWater = true

-- ── Helpers ─────────────────────────────────────────────────────────────

local function showTricks()
	local settings = PlayerData.Peek("settings")
	return type(settings) ~= "table" or settings.showTricks ~= false
end

local function refreshRayFilter()
	local filter = {}
	local balls = workspace:FindFirstChild(BALLS_FOLDER_NAME)
	if balls then
		table.insert(filter, balls)
	end
	if character then
		table.insert(filter, character)
	end
	rayParams.FilterDescendantsInstances = filter
end

local function getAnimator()
	if animator and animator.Parent then
		return animator
	end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	animator = humanoid and humanoid:FindFirstChildOfClass("Animator") or nil
	return animator
end

local function getTrack(trickId)
	local cached = trackCache[trickId]
	if cached then
		return cached
	end
	local animationId = TrickTable.Tricks[trickId].AnimationId
	if animationId == "" then
		if not warnedNoAnimation then
			warnedNoAnimation = true
			warn("[TrickController] TrickTable has no AnimationId yet; tricks score and pay but play no animation")
		end
		return nil
	end
	local owner = getAnimator()
	if not owner then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local ok, track = pcall(function()
		return owner:LoadAnimation(animation)
	end)
	animation:Destroy()
	if not ok then
		warn(`[TrickController] Could not load the animation for {trickId}: {track}`)
		return nil
	end
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = false
	trackCache[trickId] = track
	return track
end

local function stopCurrentTrack(fadeSeconds)
	if air and air.Track then
		air.Track:Stop(fadeSeconds)
		air.Track = nil
	end
end

local function localPlayable()
	local equipped = PlayerData.Peek("equippedTricks")
	local owned = PlayerData.Peek("ownedTricks")
	return TrickRules.Playable(equipped, owned)
end

local function isAssisted()
	return toolActive.Glider or toolActive.Grapple or toolActive.Coil
end

local function raycastDown(origin, length)
	return workspace:Raycast(origin, Vector3.new(0, -length, 0), rayParams)
end

-- ── Airtime ─────────────────────────────────────────────────────────────

local function startAir()
	air = {
		StartClock = os.clock(),
		StartServer = workspace:GetServerTimeNow(),
		Played = {},
		Current = nil,
		Track = nil, -- the animation of the newest trick, still holding its last pose
		NextCheck = 0,
		Assisted = isAssisted(),
		Distinct = {},
		DistinctCount = 0,
	}
end

-- Drops the airtime without a report (a fall, a respawn, losing the ball).
local function cancelAir(shouldBail)
	if air then
		stopCurrentTrack(LANDING_BLEND_SECONDS)
		if shouldBail and #air.Played > 0 then
			TrickController.Popup:Fire(TrickRules.LandingText("Bail", 0), 0, "Bail")
		end
	end
	air = nil
	isAirborne = false
end

local function startTrick(trickId)
	local trick = TrickTable.Tricks[trickId]
	local currentClock = os.clock()
	air.Current = { Id = trickId, StartAt = currentClock, EndAt = currentClock + trick.Duration }
	table.insert(air.Played, trickId)
	if not air.Distinct[trickId] then
		air.Distinct[trickId] = true
		air.DistinctCount += 1
	end

	local position = #air.Played
	TrickController.Popup:Fire(string.upper(trick.Name), 0, "Trick")
	if position >= 2 then
		local chain = TrickRules.ChainMultiplier(position)
		TrickController.Popup:Fire(`x{chain}`, 0, "Chain")
	end
	if air.DistinctCount == TrickTable.Scoring.VarietyMinDistinct and not air.MixedShown then
		air.MixedShown = true
		local bonus = math.round((TrickTable.Scoring.VarietyMultiplier - 1) * 100)
		TrickController.Popup:Fire(`MIXED +{bonus}%`, 0, "Mixed")
	end

	if not showTricks() then
		return
	end
	if position >= CHAIN_FOV_FROM then
		CameraController.Punch(CHAIN_FOV_DEGREES / PUNCH_FOV_REFERENCE)
	end
	local track = getTrack(trickId)
	if air.Track then
		air.Track:Stop(BLEND_SECONDS)
		air.Track = nil
	end
	if track then
		track:Play(BLEND_SECONDS)
		air.Track = track
	end
end

local function tryPick(primary, radius, clock)
	local airtime = clock - air.StartClock
	local origin = primary.Position
	local hit = raycastDown(origin, CONFIG.PredictMaxDrop + radius)
	local drop = if hit then math.max(hit.Distance - radius, 0) else nil

	local canStart = TrickRules.CanStart({
		RoundState = workspace:GetAttribute("RoundState"),
		Airtime = airtime,
		Gliding = toolActive.Glider,
		Grappling = toolActive.Grapple,
		GroundDrop = drop,
	})
	air.NextCheck = clock + CONFIG.PredictRecheckSeconds
	if not canStart then
		return
	end

	local landIn = TrickRules.PredictLanding(primary.AssemblyLinearVelocity.Y, drop, workspace.Gravity)
	if not landIn then
		return
	end
	local plan = TrickRules.PlanBest(localPlayable(), {
		Budget = landIn - CONFIG.PickMargin,
		Played = air.Played,
		Levels = PlayerData.Peek("trickLevels"),
		Assisted = air.Assisted,
	})
	if plan and plan.Plan[1] then
		startTrick(plan.Plan[1])
	end
end

local function stepAir(primary, radius)
	local clock = os.clock()
	if isAssisted() then
		air.Assisted = true
	end
	if air.Current and clock >= air.Current.EndAt then
		-- The rider holds the last pose until the next trick blends in or touchdown.
		air.Current = nil
		air.NextCheck = 0
	end
	if not air.Current and clock >= air.NextCheck then
		tryPick(primary, radius, clock)
	end
end

local function touchdown()
	local finished = air
	air = nil
	isAirborne = false
	if not finished or #finished.Played == 0 then
		return
	end

	local clock = os.clock()
	local entries = {}
	for index, trickId in finished.Played do
		entries[index] = { Id = trickId }
	end
	local current = finished.Current
	if current then
		local progress = (clock - current.StartAt) / (current.EndAt - current.StartAt)
		if progress < 1 then
			entries[#entries].Progress = math.clamp(progress, 0, 1)
		end
	end
	if finished.Track then
		finished.Track:Stop(LANDING_BLEND_SECONDS)
	end

	local result = TrickRules.Score(entries, { Levels = PlayerData.Peek("trickLevels"), Assisted = finished.Assisted })
	TrickController.Popup:Fire(TrickRules.LandingText(result.Grade, result.Points), result.Points, result.Grade)
	Network.FireServer("TrickLanded", {
		trickIds = finished.Played,
		startedAt = finished.StartServer,
		landedAt = workspace:GetServerTimeNow(),
	})
end

-- ── Frame loop ──────────────────────────────────────────────────────────

local function step()
	local ball = BallController.GetBall()
	if ball ~= activeBall then
		cancelAir(false)
		activeBall = ball
		refreshRayFilter()
	end
	local primary = ball and ball.PrimaryPart
	if not primary then
		return
	end
	-- Tricks only exist during the race; skip the per-frame raycast in the lobby and drop any airtime in progress.
	if workspace:GetAttribute("RoundState") ~= RACE_STATE then
		if isAirborne then
			cancelAir(false)
		end
		return
	end

	local radius = primary.Size.Y / 2
	local hit = raycastDown(primary.Position, radius + CONFIG.AirClearanceExtra)
	local nowAirborne = TrickRules.NextAirborne(isAirborne, hit and hit.Distance or nil, radius)
	if nowAirborne and not isAirborne then
		isAirborne = true
		startAir()
	elseif isAirborne and not nowAirborne then
		touchdown()
	end
	if isAirborne and air then
		stepAir(primary, radius)
	end
end

-- ── Public API ──────────────────────────────────────────────────────────

function TrickController.SetToolState(kind, active)
	if toolActive[kind] == nil then
		return
	end
	toolActive[kind] = active == true
	if active and air then
		air.Assisted = true
	end
end

function TrickController.IsPlaying()
	return air ~= nil and air.Current ~= nil
end

function TrickController.CharacterAdded(_, newCharacter)
	character = newCharacter
	animator = nil
	table.clear(trackCache)
	refreshRayFilter()
end

function TrickController.CharacterRemoving(_, removed)
	if removed ~= character then
		return
	end
	cancelAir(false)
	character, animator = nil, nil
	table.clear(trackCache)
end

-- ── Wiring ──────────────────────────────────────────────────────────────

BallController.Unbound:Connect(function()
	cancelAir(true)
	activeBall = nil
end)

for _, voidMessage in { "Fell", "BallPivot", "Skipped" } do
	Network.OnEvent(voidMessage, function()
		cancelAir(true)
	end)
end

Network.OnEvent("TrickResult", function(grade, points, coins, flags)
	if type(grade) ~= "string" or type(points) ~= "number" then
		return
	end
	TrickController.Popup:Fire(TrickRules.LandingText(grade, points), points, grade, {
		Final = true,
		Coins = type(coins) == "number" and coins or 0,
		Flags = type(flags) == "table" and flags or {},
	})
	if type(flags) == "table" and flags.RoundCapReached then
		TrickController.Popup:Fire("Trick coins maxed this round!", 0, "RoundCap")
	end
end)

Network.OnEvent("FirstTrick", function()
	TrickController.FirstTrick:Fire()
end)

RunService.Heartbeat:Connect(function()
	step()
end)

return TrickController
