-- BallService
-- Owns every player's ball: clones the equipped ball model, writes the BallStats attributes, welds it to the player's
-- HumanoidRootPart as a cosmetic shell, and audits the ball's speed at 10 Hz (GDD 3, 13).
-- The root part is the only physical body (the player owns it as part of their character); the ball is massless and
-- non-colliding, so its PrimaryPart reports the root's position and velocity and nothing rolls it.
-- Ball models are authored in Studio (ServerStorage.Balls/<ModelName>, a Model whose PrimaryPart is a part named
-- "Ball"). A missing model warns once and a plain sphere stands in so the game stays playable.
--
-- Public API (other systems code against this):
--   BallService.Spawn(player, cframe) -> boolean    -- cframe = where the ball's centre goes. false if data isn't
--                                                      loaded, no starter was picked, nothing is equipped or the
--                                                      player has no character. Replaces any existing ball.
--   BallService.Despawn(player)
--   BallService.Respawn(player, cframe) -> boolean  -- moves the ball and zeroes its velocity; spawns one if missing
--   BallService.GetBall(player) -> Model?
--   BallService.Refresh(player?)                    -- rebuild attributes (GamePassService calls it on a pass change)
--   BallService.SetAuditContext(player, key, untilTime) -> boolean
--       key "Boosting" | "Rocketing" | "Grappling"; untilTime in os.clock() seconds. Widens the speed allowance.
--   BallService.GetSample(player) -> { Position, Velocity, HorizontalSpeed, Time }?   -- latest 10 Hz sample, read-only
--   BallService.GetStrikes(player) -> number        BallService.ResetStrikes(player)
--   BallService.AddStrike(player, reason) -> boolean   -- other validators (TrickService) add to the same count
--   BallService.BallSpawned   Signal (player, ball)
--   BallService.StrikeAdded   Signal (player, reason, count)
--
-- Balls live in workspace.Balls (created at runtime), tagged with the owner's UserId in the "Player" attribute, and
-- stream as Persistent models so the owner always has them. Clients find their ball there rather than through a
-- remote Instance, which would arrive nil if it had not streamed in yet.
-- Network: BallSpawned() (no payload, "rescan now") and BallPivot(cframe) go to the owner; the client moves the
-- ball itself because a server CFrame write to a client-owned part is unreliable. Despawn just destroys the ball.
-- Modifiers: workspace boolean attributes named by ModifierTable.Modifiers keys (ModifierService sets them).
-- A player with the boolean player attribute TrollImmune ignores ShrinkEveryone and SlowEveryone; call Refresh(player)
-- after changing it.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Network = require(ReplicatedStorage.Network)
local Signal = require(ReplicatedStorage.Utilities.Signal)
local Trove = require(ReplicatedStorage.Utilities.Trove)
local BallTable = require(ReplicatedStorage.Tables.BallTable)
local ModifierTable = require(ReplicatedStorage.Tables.ModifierTable)
local PhysicsTable = require(ReplicatedStorage.Tables.PhysicsTable)

local GamePassService = require(script.Parent.GamePassService)
local PlayerData = require(script.Parent.PlayerData)
local BallAttributes = require(script.BallAttributes)
local SpeedAudit = require(script.SpeedAudit)

local BallService = {}
BallService.BallSpawned = Signal.new()
BallService.StrikeAdded = Signal.new()

-- ── Tuning ──────────────────────────────────────────────────────────────
local BALLS_FOLDER_NAME = PhysicsTable.Ball.FolderName
local PLACEHOLDER_SIZE = 4 -- studs, diameter of the stand-in sphere
local BOOST_CACHE_SECONDS = 5 -- how long cached boost-part boxes are trusted
local JUMP_IGNORE_TAG = "JumpIgnore"
local BOOST_TAGS = { "BoostPanel", "JumpPad" }
local TRAIL_TEMPLATE_NAME = "Trail" -- ReplicatedStorage.Assets.Trail, optional

local modifierKeys = {}
for key in ModifierTable.Modifiers do
	table.insert(modifierKeys, key)
end

local records = {} -- [player] = { Ball, Trove, BaseScale, BallId, Sample, Tracker, Strikes }
local watchers = {} -- [player] = Trove with the PlayerData listeners
local strikes = {} -- [player] = count, survives respawns
local warnedModels = {}
local boostTargets = {} -- [BasePart | Model] = true
local boostBoxes = {} -- { { CFrame, Size, Radius } } cached from boostTargets
local boostBoxesAt = -math.huge
local ballsFolder = nil

-- ── Helpers ─────────────────────────────────────────────────────────────

-- Only passes that change ball physics; the set is keyed by PassTable keys as BallStats expects.
local PHYSICS_PASSES = { "Turbo", "DoubleJump" }

local function getPasses(player)
	local passes = {}
	for _, passKey in PHYSICS_PASSES do
		if GamePassService.Owns(player, passKey) then
			passes[passKey] = true
		end
	end
	return passes
end

local function getBallsFolder()
	if ballsFolder and ballsFolder.Parent then
		return ballsFolder
	end
	ballsFolder = workspace:FindFirstChild(BALLS_FOLDER_NAME)
	if not ballsFolder then
		ballsFolder = Instance.new("Folder")
		ballsFolder.Name = BALLS_FOLDER_NAME
		ballsFolder.Parent = workspace
	end
	return ballsFolder
end

local function buildAttributes(player, ballId)
	local modifiers = BallAttributes.ReadModifiers(modifierKeys, function(key)
		return workspace:GetAttribute(key)
	end)
	-- ModifierService sets TrollImmune on buyers, Finale players and new players; they skip troll modifiers.
	if player:GetAttribute("TrollImmune") == true then
		modifiers.ShrinkEveryone = nil
		modifiers.SlowEveryone = nil
	end
	return BallAttributes.Build(ballId, getPasses(player), modifiers, PlayerData.Peek(player, "settings"))
end

local function makePlaceholder()
	local model = Instance.new("Model")
	model.Name = "PlaceholderBall"
	local part = Instance.new("Part")
	part.Name = "Ball"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * PLACEHOLDER_SIZE
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(200, 60, 40)
	part.Parent = model
	model.PrimaryPart = part
	return model
end

local function cloneBallModel(modelName)
	local template = nil
	local balls = ServerStorage:FindFirstChild("Balls")
	if balls then
		template = balls:FindFirstChild(modelName)
	end
	if template and template:IsA("Model") and template:FindFirstChild("Ball") then
		local clone = template:Clone()
		clone.PrimaryPart = clone:FindFirstChild("Ball")
		return clone
	end
	if not warnedModels[modelName] then
		warnedModels[modelName] = true
		warn(
			`[BallService] ServerStorage.Balls.{modelName} (a Model with a "Ball" part) is missing; using a placeholder sphere`
		)
	end
	return makePlaceholder()
end

local function addTrail(primary)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild(TRAIL_TEMPLATE_NAME)
	if not template then
		return
	end
	local source = template:FindFirstChild("Part") or template
	local at1 = source:FindFirstChild("AT1")
	local at2 = source:FindFirstChild("AT2")
	local trail = nil
	for _, descendant in source:GetDescendants() do
		if descendant:IsA("Trail") then
			trail = descendant
			break
		end
	end
	if not (at1 and at2 and trail) then
		return
	end
	at1 = at1:Clone()
	at2 = at2:Clone()
	trail = trail:Clone()
	at1.Parent = primary
	at2.Parent = primary
	trail.Attachment0 = at1
	trail.Attachment1 = at2
	trail.Parent = primary
end

-- The ball's centre goes on the root's centre, so the cosmetic shell surrounds the body.
local function attachToRoot(ball, root)
	root:PivotTo(ball:GetPivot())
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = ball.PrimaryPart
	weld.Part1 = root
	weld.Parent = ball.PrimaryPart
	root.Transparency = 1
end

local function destroyRecord(player)
	local record = records[player]
	if not record then
		return
	end
	records[player] = nil
	record.Trove:Destroy()
end

-- ── Attribute rebuild ───────────────────────────────────────────────────

local function rescale(record, scale)
	if record.Ball:GetAttribute("Scale") == scale then
		return
	end
	record.Ball:ScaleTo(record.BaseScale * scale)
end

local function refreshPlayer(player)
	local record = records[player]
	if not record then
		return
	end
	local ok, resolved = pcall(buildAttributes, player, record.BallId)
	if not ok then
		warn(`[BallService] Could not rebuild attributes for {player.Name}: {resolved}`)
		return
	end
	rescale(record, resolved.Scale)
	BallAttributes.Apply(record.Ball, resolved)
	record.Resolved = resolved
end

function BallService.Refresh(player)
	if player then
		refreshPlayer(player)
		return
	end
	for each in records do
		refreshPlayer(each)
	end
end

-- ── Spawning ────────────────────────────────────────────────────────────

local function watchPlayerData(player)
	if watchers[player] then
		return
	end
	local watcher = Trove.new()
	watchers[player] = watcher
	local equipListener = PlayerData.OnUpdate(player, "equippedBall", function()
		local record = records[player]
		if record then
			-- A different model is needed, so swap in place rather than only rewriting attributes.
			BallService.Spawn(player, record.Ball:GetPivot())
		end
	end)
	watcher:Add(function()
		equipListener:Disconnect()
	end)
	local settingsListener = PlayerData.OnUpdate(player, "settings", function()
		refreshPlayer(player)
	end)
	watcher:Add(function()
		settingsListener:Disconnect()
	end)
end

function BallService.Spawn(player, cframe)
	if not PlayerData.IsLoaded(player) or PlayerData.Peek(player, "hasPickedStarter") ~= true then
		return false
	end
	local ballId = PlayerData.Peek(player, "equippedBall")
	local definition = type(ballId) == "string" and BallTable[ballId]
	if not definition then
		return false
	end
	local character = player.Character
	if not (character and character.PrimaryPart and character.Parent) then
		return false
	end
	local ok, resolved = pcall(buildAttributes, player, ballId)
	if not ok then
		warn(`[BallService] Could not resolve stats for {ballId}: {resolved}`)
		return false
	end

	watchPlayerData(player)
	destroyRecord(player)

	local ball = cloneBallModel(definition.ModelName)
	local primary = ball.PrimaryPart
	local record = {
		Ball = ball,
		Trove = Trove.new(),
		BaseScale = ball:GetScale(),
		BallId = ballId,
		Resolved = resolved,
		Tracker = SpeedAudit.NewTracker(),
	}
	record.Trove:Add(ball)

	ball.Name = player.Name
	ball.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	ball:SetAttribute("Player", player.UserId)
	ball:SetAttribute("BallId", ballId)
	rescale(record, resolved.Scale)
	BallAttributes.Apply(ball, resolved)
	for _, descendant in ball:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.Massless = true
			CollectionService:AddTag(descendant, JUMP_IGNORE_TAG)
		end
	end
	addTrail(primary)
	ball:PivotTo(cframe)
	attachToRoot(ball, character.PrimaryPart)
	ball.Parent = getBallsFolder()
	records[player] = record

	-- If anything else removes the ball, drop the record so the audit stops.
	record.Trove:Connect(ball.AncestryChanged, function(_, parent)
		if not parent and records[player] == record then
			records[player] = nil
			record.Trove:Destroy()
		end
	end)

	Network.FireClient(player, "BallSpawned")
	BallService.BallSpawned:Fire(player, ball)
	return true
end

function BallService.Despawn(player)
	destroyRecord(player)
end

function BallService.Respawn(player, cframe)
	local record = records[player]
	if not (record and record.Ball.Parent and record.Ball.PrimaryPart) then
		return BallService.Spawn(player, cframe)
	end
	local ball = record.Ball
	for _, descendant in ball:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
	-- Welded to the root, so this moves the player too.
	ball:PivotTo(cframe)
	record.Sample = nil
	table.clear(record.Tracker.Over)
	Network.FireClient(player, "BallPivot", cframe)
	return true
end

function BallService.GetBall(player)
	local record = records[player]
	return record and record.Ball or nil
end

-- ── Speed audit ─────────────────────────────────────────────────────────

function BallService.SetAuditContext(player, key, untilTime)
	local record = records[player]
	if not record then
		return false
	end
	return SpeedAudit.SetContext(record.Tracker, key, untilTime)
end

function BallService.GetSample(player)
	local record = records[player]
	return record and record.Sample or nil
end

function BallService.GetStrikes(player)
	return strikes[player] or 0
end

function BallService.ResetStrikes(player)
	strikes[player] = nil
end

function BallService.AddStrike(player, reason)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or type(reason) ~= "string" then
		return false
	end
	local count = (strikes[player] or 0) + 1
	strikes[player] = count
	BallService.StrikeAdded:Fire(player, reason, count)
	return true
end

local function refreshBoostBoxes(now)
	table.clear(boostBoxes)
	for target in boostTargets do
		local boxCFrame, boxSize
		if target:IsA("Model") then
			boxCFrame, boxSize = target:GetBoundingBox()
		else
			boxCFrame, boxSize = target.CFrame, target.Size
		end
		table.insert(boostBoxes, { CFrame = boxCFrame, Size = boxSize, Radius = boxSize.Magnitude / 2 })
	end
	boostBoxesAt = now
end

local function nearBoostPart(position, margin, now)
	if now - boostBoxesAt > BOOST_CACHE_SECONDS then
		refreshBoostBoxes(now)
	end
	for _, box in boostBoxes do
		-- Cheap sphere reject before the exact box test.
		local reach = box.Radius + margin
		if
			(position - box.CFrame.Position):Dot(position - box.CFrame.Position) <= reach * reach
			and SpeedAudit.IsNearBox(position, box.CFrame, box.Size, margin)
		then
			return true
		end
	end
	return false
end

local function auditPlayer(player, record, now)
	local primary = record.Ball.PrimaryPart
	if not primary then
		return
	end
	local velocity = primary.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local position = primary.Position
	-- Respawn and Spawn clear the previous sample, so a deliberate teleport never counts as movement.
	local previous = record.Sample
	local measuredSpeed = previous and SpeedAudit.MeasuredSpeed(previous.Position, previous.Time, position, now)
	record.Sample = {
		Position = position,
		Velocity = velocity,
		HorizontalSpeed = horizontalSpeed,
		Time = now,
	}

	if nearBoostPart(position, PhysicsTable.SpeedAudit.BoostProximityStuds, now) then
		SpeedAudit.MarkBoostNearby(record.Tracker, now)
	end
	local struck = SpeedAudit.Check(record.Tracker, record.Resolved, horizontalSpeed, now, measuredSpeed)
	if struck then
		local count = (strikes[player] or 0) + 1
		strikes[player] = count
		BallService.StrikeAdded:Fire(player, "Speed", count)
	end
end

local function runAuditLoop()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < PhysicsTable.SpeedAudit.SampleSeconds then
			return
		end
		elapsed = 0
		local now = os.clock()
		for player, record in records do
			auditPlayer(player, record, now)
		end
	end)
end

-- ── Wiring ──────────────────────────────────────────────────────────────

local function registerBoostPart(target)
	if target:IsA("BasePart") or target:IsA("Model") then
		boostTargets[target] = true
		boostBoxesAt = -math.huge
	end
end

local function onPlayerAdded(player)
	player.CharacterRemoving:Connect(function()
		destroyRecord(player)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

GamePassService.PassChanged:Connect(function(player, passKey)
	if table.find(PHYSICS_PASSES, passKey) then
		BallService.Refresh(player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	destroyRecord(player)
	strikes[player] = nil
	local watcher = watchers[player]
	if watcher then
		watchers[player] = nil
		watcher:Destroy()
	end
end)

for _, tag in BOOST_TAGS do
	for _, part in CollectionService:GetTagged(tag) do
		registerBoostPart(part)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(registerBoostPart)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(part)
		-- The part may still carry the other tag.
		for _, other in BOOST_TAGS do
			if CollectionService:HasTag(part, other) then
				return
			end
		end
		boostTargets[part] = nil
		boostBoxesAt = -math.huge
	end)
end

for _, key in modifierKeys do
	workspace:GetAttributeChangedSignal(key):Connect(function()
		BallService.Refresh()
	end)
end

game:BindToClose(function()
	for player in records do
		destroyRecord(player)
	end
end)

getBallsFolder()
runAuditLoop()

return BallService
