-- BallController
-- Client-owned ball movement (the server audits it, BallService). The ball is found in workspace.Balls by its
-- Player attribute (UserId), never through a remote Instance, which would arrive nil if it had not streamed in.
-- BallSpawned is only a "rescan now" nudge.
-- The player's HumanoidRootPart is the only physical body (StarterPlayer.StarterCharacter: a frictionless sphere part
-- and a Humanoid, no avatar). The ball model is cosmetic: BallService welds it to the root, massless and non-colliding,
-- so it never rolls. Once bound, every physics step a VectorForce on the root pushes its horizontal velocity toward the
-- humanoid's MoveDirection (the default control module, so keyboard, gamepad and touch all work); an AlignOrientation
-- holds it upright facing the camera. Steering downhill raises the target speed by the slope under the body
-- (BallMotion.DownhillMultiplier). Jumps set vertical velocity directly; the Humanoid's own jump is disabled.
-- BallRoll spins the cosmetic ball.
-- All numbers come from the ball's stat attributes (BallStats contract) and the maths lives in Shared/BallMotion.
--
-- Hooks for other client systems (ObstacleController, tools):
--   BallController.SetSpeedMultiplier(source, multiplier)   -- boost panel / rocket. Each source owns one entry and the
--                                                      largest applies (the server audit does the same), so one source
--                                                      ending never cancels another. The one-argument form
--                                                      SetSpeedMultiplier(multiplier) is the source "Default".
--   BallController.ClearSpeedMultiplier(source)
--   BallController.SetGravityMultiplier(source, multiplier)   -- Gravity Coil; entries multiply, floor 0.4 x default
--   BallController.ClearGravityMultiplier(source)
--   BallController.SetVelocityDriver(source, fn?)   -- tools (Glider, Grapple, Brake): fn(velocity, moveDirection, grounded,
--                                                      dt, { Attrs, SpeedMultiplier }) -> Vector3? replaces this frame's
--                                                      normal blend; nil means "normal step". Newest source asks first.
--   BallController.IsGrounded() -> boolean          -- last physics step's ground check
--   BallController.ApplyJumpPad(jumpPower)          -- vertical launch with a JumpPad's JumpPower
--   BallController.SetMoveOverride(direction?)      -- tools (Rocket): steer toward this world direction instead of the
--                                                      humanoid's MoveDirection; nil gives control back
--   BallController.GetBall() -> Model?
--   BallController.IsOwnBodyPart(part) -> boolean   -- part of the bound ball or the local root part (touch triggers)
--   BallController.Unbound   Signal ()      -- fired when the ball is released (despawn, respawn, character removed)
-- Network in: BallSpawned() and BallPivot(cframe) from BallService.
-- Authored optional asset: ReplicatedStorage.Assets.DropShadow (a Part shown under the ball while airborne).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Network = require(ReplicatedStorage.Network)
local Signal = require(ReplicatedStorage.Utilities.Signal)
local Trove = require(ReplicatedStorage.Utilities.Trove)
local BallMotion = require(ReplicatedStorage.Shared.BallMotion)
local ModifierStack = require(ReplicatedStorage.Shared.ModifierStack)
local PhysicsTable = require(ReplicatedStorage.Tables.PhysicsTable)

local BallController = {}
BallController.Unbound = Signal.new()

local localPlayer = Players.LocalPlayer

-- ── Tuning ──────────────────────────────────────────────────────────────
local WAIT_TIMEOUT = 10 -- seconds for parts of the ball and character to replicate
local GROUND_SLACK = 0.3 -- studs below the ball's surface that still count as ground
local GROUND_SKIN = 0.1 -- studs the ground probe sphere is shrunk by, so it never starts inside the floor
local SHADOW_RAY_LENGTH = 1000 -- studs
local BALLS_FOLDER_NAME = PhysicsTable.Ball.FolderName
local ALIGN_RESPONSIVENESS = 200
local MIN_FORCE_DT = 1 / 240 -- seconds, a tiny frame must not blow the force up
local JUMP_IGNORE_TAG = "JumpIgnore"

local characterTrove = nil -- one per life
local bindTrove = nil -- one per ball, child of characterTrove
local character = nil
local bindingBall = nil -- the ball a bind is in progress for or active on
local boundBall = nil
local speedStack = ModifierStack.New() -- [source] = multiplier, largest applies
local gravityStack = ModifierStack.New() -- [source] = multiplier, product applies
local velocityDrivers = {} -- list of { Source, Fn }, newest last
local reapplyGravity = nil
local isGroundedNow = false
local groundNormal = nil -- Vector3? surface normal under the body from the last ground check; nil when airborne
local moveOverride = nil -- Vector3? from a tool; replaces the humanoid's MoveDirection while set
local jumpState = BallMotion.NewJumpState()
local boundPrimary = nil
local boundRoot = nil -- the HumanoidRootPart that carries the bound ball
local warnedShadow = false

local function makeShadow()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild("DropShadow")
	if not template then
		if not warnedShadow then
			warnedShadow = true
			warn("[BallController] ReplicatedStorage.Assets.DropShadow is missing; no drop shadow")
		end
		return nil
	end
	local shadow = template:Clone()
	CollectionService:AddTag(shadow, JUMP_IGNORE_TAG)
	return shadow
end

local function bind(ball)
	if bindTrove then
		bindTrove:Destroy()
	end
	if not (character and characterTrove) then
		return
	end
	local trove = characterTrove:Extend()
	bindTrove = trove
	bindingBall = ball
	trove:Add(function()
		if bindingBall == ball then
			bindingBall = nil
		end
		BallController.Unbound:Fire()
	end)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local primary = ball.PrimaryPart or ball:WaitForChild("Ball", WAIT_TIMEOUT)
	-- Anything above can yield; a newer bind or a respawn may have replaced this one.
	if bindTrove ~= trove then
		return
	end
	local rootAttachment = root and root:FindFirstChild("RootAttachment")
	if not (humanoid and primary and primary:IsA("BasePart") and rootAttachment) then
		warn(
			'[BallController] Ball or character is missing parts (Humanoid, HumanoidRootPart.RootAttachment, ball part "Ball")'
		)
		return
	end

	boundBall, boundPrimary, boundRoot = ball, primary, root
	local attrs = ball:GetAttributes()
	jumpState = BallMotion.NewJumpState()
	ModifierStack.Reset(speedStack)
	ModifierStack.Reset(gravityStack)
	table.clear(velocityDrivers)
	isGroundedNow = false
	groundNormal = nil
	moveOverride = nil
	trove:Add(function()
		if boundBall == ball then
			boundBall, boundPrimary, boundRoot = nil, nil, nil
		end
		reapplyGravity = nil
	end)

	-- Gravity is per ball (Low Gravity); our own physics owner simulates it.
	local defaultGravity = workspace.Gravity
	local function applyGravity()
		if type(attrs.Gravity) == "number" then
			local floor = PhysicsTable.Gravity.Default * PhysicsTable.Gravity.MinFraction
			workspace.Gravity = math.max(attrs.Gravity * ModifierStack.Product(gravityStack), floor)
		end
	end
	reapplyGravity = applyGravity
	applyGravity()
	trove:Add(function()
		workspace.Gravity = defaultGravity
	end)
	trove:Connect(ball.AttributeChanged, function(name)
		attrs[name] = ball:GetAttribute(name)
		if name == "Gravity" then
			applyGravity()
		end
	end)

	-- Movement is a force on the root, not a velocity write; the root is frictionless, so this force alone moves it.
	local vectorForce = Instance.new("VectorForce")
	vectorForce.Attachment0 = rootAttachment
	vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
	vectorForce.ApplyAtCenterOfMass = true
	vectorForce.Force = Vector3.zero
	vectorForce.Parent = root
	trove:Add(vectorForce)

	-- Keeps the root upright and facing the camera, so nothing ever rolls.
	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.Attachment0 = rootAttachment
	alignOrientation.MaxTorque = math.huge
	alignOrientation.Responsiveness = ALIGN_RESPONSIVENESS
	alignOrientation.Parent = root
	trove:Add(alignOrientation)

	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	-- Ground check ignores the ball, the character, the shadow and anything tagged JumpIgnore.
	local shadow = makeShadow()
	local filter = { ball, character }
	if shadow then
		table.insert(filter, shadow)
		trove:Add(shadow)
	end
	for _, tagged in CollectionService:GetTagged(JUMP_IGNORE_TAG) do
		table.insert(filter, tagged)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	params.FilterDescendantsInstances = filter
	trove:Connect(CollectionService:GetInstanceAddedSignal(JUMP_IGNORE_TAG), function(instance)
		table.insert(filter, instance)
		params.FilterDescendantsInstances = filter
	end)

	-- A sphere cast (not a ray) so slopes still read as ground, and it reports the surface normal for the slope.
	local function probeGround()
		local result = workspace:Spherecast(
			root.Position,
			root.Size.Y / 2 - GROUND_SKIN,
			Vector3.new(0, -(GROUND_SKIN + GROUND_SLACK), 0),
			params
		)
		return result ~= nil, result and result.Normal
	end

	trove:Connect(UserInputService.JumpRequest, function()
		local kind = BallMotion.RequestJump(jumpState, attrs.DoubleJumpEnabled == true)
		if not kind then
			return
		end
		root.AssemblyLinearVelocity = BallMotion.ApplyJump(root.AssemblyLinearVelocity, kind, attrs)
	end)

	trove:Connect(RunService.PreSimulation, function(dt)
		if not attrs.MaxForce then
			return
		end
		local rawGrounded, normal = probeGround()
		local grounded = BallMotion.UpdateJumpState(jumpState, rawGrounded, dt)
		isGroundedNow = grounded
		groundNormal = if grounded then normal else nil
		local velocity = root.AssemblyLinearVelocity
		local moveDirection = moveOverride or humanoid.MoveDirection
		local speedMultiplier = ModifierStack.Max(speedStack)
		local stepped = nil
		for index = #velocityDrivers, 1, -1 do
			local ok, result = pcall(
				velocityDrivers[index].Fn,
				velocity,
				moveDirection,
				grounded,
				dt,
				{ Attrs = attrs, SpeedMultiplier = speedMultiplier }
			)
			if ok and typeof(result) == "Vector3" then
				stepped = result
				break
			end
		end
		stepped = stepped
			or BallMotion.Step(velocity, moveDirection, grounded, attrs, dt, {
				SpeedMultiplier = speedMultiplier,
				SlopeMultiplier = BallMotion.DownhillMultiplier(groundNormal, moveDirection),
			})
		-- The force that reaches this frame's stepped velocity over the coming step. A frozen (anchored) body has
		-- infinite mass, which would make the force NaN.
		local mass = root.AssemblyMass
		vectorForce.Force = if mass < math.huge
			then (stepped - velocity) * mass / math.max(dt, MIN_FORCE_DT)
			else Vector3.zero

		local camera = workspace.CurrentCamera
		if camera then
			local _, yaw = camera.CFrame:ToOrientation()
			alignOrientation.CFrame = CFrame.fromOrientation(0, yaw, 0)
		end

		if shadow then
			if grounded then
				shadow.Parent = nil
			else
				local hit = workspace:Raycast(root.Position, Vector3.new(0, -SHADOW_RAY_LENGTH, 0), params)
				if hit then
					shadow.Position = hit.Position
					shadow.Parent = workspace
				else
					shadow.Parent = nil
				end
			end
		end
	end)

	-- The server destroys the ball on despawn.
	trove:Connect(ball.AncestryChanged, function(_, parent)
		if not parent and bindTrove == trove then
			trove:Destroy()
		end
	end)
end

local function findOwnBall()
	local folder = workspace:FindFirstChild(BALLS_FOLDER_NAME)
	if not folder then
		return nil
	end
	for _, child in folder:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("Player") == localPlayer.UserId then
			return child
		end
	end
	return nil
end

local function tryBind()
	if not character then
		return
	end
	local ball = findOwnBall()
	if not ball or ball == bindingBall then
		return
	end
	task.spawn(bind, ball)
end

function BallController.SetSpeedMultiplier(source, multiplier)
	if multiplier == nil then
		source, multiplier = "Default", source
	end
	if type(multiplier) ~= "number" or multiplier == 1 or not ModifierStack.Set(speedStack, source, multiplier) then
		ModifierStack.Clear(speedStack, source)
	end
end

function BallController.ClearSpeedMultiplier(source)
	ModifierStack.Clear(speedStack, source)
end

function BallController.SetGravityMultiplier(source, multiplier)
	if type(multiplier) ~= "number" or multiplier == 1 or not ModifierStack.Set(gravityStack, source, multiplier) then
		ModifierStack.Clear(gravityStack, source)
	end
	if reapplyGravity then
		reapplyGravity()
	end
end

function BallController.ClearGravityMultiplier(source)
	ModifierStack.Clear(gravityStack, source)
	if reapplyGravity then
		reapplyGravity()
	end
end

function BallController.SetVelocityDriver(source, fn)
	for index = #velocityDrivers, 1, -1 do
		if velocityDrivers[index].Source == source then
			table.remove(velocityDrivers, index)
		end
	end
	if type(fn) == "function" then
		table.insert(velocityDrivers, { Source = source, Fn = fn })
	end
end

function BallController.IsGrounded()
	return boundRoot ~= nil and isGroundedNow
end

function BallController.IsOwnBodyPart(part)
	if not boundBall then
		return false
	end
	return part:IsDescendantOf(boundBall) or part == boundRoot
end

function BallController.SetMoveOverride(direction)
	moveOverride = if typeof(direction) == "Vector3" then direction else nil
end

function BallController.ApplyJumpPad(jumpPower)
	if not (boundRoot and type(jumpPower) == "number") then
		return
	end
	BallMotion.MarkLaunched(jumpState)
	boundRoot.AssemblyLinearVelocity = BallMotion.ApplyLaunch(boundRoot.AssemblyLinearVelocity, jumpPower)
end

function BallController.GetBall()
	return boundBall
end

function BallController.CharacterAdded(_, newCharacter)
	if characterTrove then
		characterTrove:Destroy()
	end
	character = newCharacter
	-- Jump input still fires JumpRequest (and keeps the touch jump button), but only our jump acts on it.
	local humanoid = newCharacter:FindFirstChildOfClass("Humanoid")
		or newCharacter:WaitForChild("Humanoid", WAIT_TIMEOUT)
	if humanoid and character == newCharacter then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	end
	characterTrove = Trove.new()
	bindTrove, bindingBall = nil, nil
	tryBind()
end

function BallController.CharacterRemoving(_, removed)
	if removed ~= character then
		return
	end
	if characterTrove then
		characterTrove:Destroy()
	end
	characterTrove, bindTrove, bindingBall, character = nil, nil, nil, nil
end

Network.OnEvent("BallSpawned", tryBind)

Network.OnEvent("BallPivot", function(cframe)
	local ball = boundBall
	if not ball or not boundPrimary or typeof(cframe) ~= "CFrame" then
		return
	end
	for _, descendant in ball:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
	-- The ball is welded to the root, so moving it moves the whole body.
	ball:PivotTo(cframe)
	jumpState = BallMotion.NewJumpState()
end)

task.spawn(function()
	local folder = workspace:WaitForChild(BALLS_FOLDER_NAME, WAIT_TIMEOUT)
	if not folder then
		warn(`[BallController] workspace.{BALLS_FOLDER_NAME} never appeared; the ball cannot be found`)
		return
	end
	folder.ChildAdded:Connect(function()
		tryBind()
	end)
	tryBind()
end)

return BallController
