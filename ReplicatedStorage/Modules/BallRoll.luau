-- BallRoll
-- Rolls every cosmetic ball in workspace.Balls (everyone's, not just ours) in the direction its body is travelling.
-- Purely visual and client-side: BallService joins each ball to its player's root with a Weld named
-- PhysicsTable.Ball.RootWeldName, and this module rewrites that weld's C0 each frame. The ball is massless and
-- non-colliding, so the rotation never touches physics, and C0 written here never replicates.
-- No public API; it starts itself.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PhysicsTable = require(ReplicatedStorage.Tables.PhysicsTable)

local BallRoll = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local BALLS_FOLDER_NAME = PhysicsTable.Ball.FolderName
local ROOT_WELD_NAME = PhysicsTable.Ball.RootWeldName
local FOLDER_TIMEOUT = 10 -- seconds to wait for workspace.Balls
local MIN_ROLL_SPEED = 0.05 -- studs/s, below this the ball holds its current rotation
local MAX_ROLL_DISTANCE = 400 -- studs from the camera; farther balls are not worth animating

local rotations = {} -- [ball Model] = CFrame, the ball's accumulated world rotation (no position)

local function getWeld(ball)
	local primary = ball.PrimaryPart
	local weld = primary and primary:FindFirstChild(ROOT_WELD_NAME)
	if weld and weld:IsA("Weld") and weld.Part0 then
		return weld, primary
	end
	return nil
end

local function step(dt)
	local camera = workspace.CurrentCamera
	local cameraPosition = camera and camera.CFrame.Position
	for ball, rotation in rotations do
		local weld, primary = getWeld(ball)
		if not weld then
			continue
		end
		local root = weld.Part0
		if cameraPosition and (root.Position - cameraPosition).Magnitude > MAX_ROLL_DISTANCE then
			continue
		end

		local velocity = root.AssemblyLinearVelocity
		local flat = Vector3.new(velocity.X, 0, velocity.Z)
		local radius = primary.Size.Y / 2
		local speed = flat.Magnitude
		if speed > MIN_ROLL_SPEED and radius > 0 then
			-- Rolling without slipping: spin about the axis perpendicular to travel, by distance / radius.
			local axis = Vector3.yAxis:Cross(flat / speed)
			rotation = CFrame.fromAxisAngle(axis, speed * dt / radius) * rotation
			rotations[ball] = rotation
		end
		-- C0 is relative to the root, which turns with the camera; cancel that so the ball keeps its own spin.
		weld.C0 = root.CFrame.Rotation:Inverse() * rotation
	end
end

local function track(ball)
	if ball:IsA("Model") and not rotations[ball] then
		rotations[ball] = CFrame.identity
	end
end

local function untrack(ball)
	rotations[ball] = nil
end

task.spawn(function()
	local folder = workspace:WaitForChild(BALLS_FOLDER_NAME, FOLDER_TIMEOUT)
	if not folder then
		warn(`[BallRoll] workspace.{BALLS_FOLDER_NAME} never appeared; balls will not roll`)
		return
	end
	folder.ChildAdded:Connect(track)
	folder.ChildRemoved:Connect(untrack)
	for _, ball in folder:GetChildren() do
		track(ball)
	end
	RunService.Heartbeat:Connect(step)
end)

return BallRoll
