-- ObstacleController
-- Client tag registry for course obstacles (GDD 5.4, AGENTS.md "Tagged behaviour"). Each CollectionService tag is
-- handled by the child ModuleScript of the same name: BoostPanel, JumpPad, KillBrick, Rotating, Moving, Vanishing,
-- GrappleAnchor. Configuration comes from attributes on the tagged object; nothing is cloned into objects.
--
-- Plug-in contract (full text in BoostPanel.luau):
--   Register(instance) -> state?, reason?    setup, may yield; nil + reason = misconfigured, warned and disabled
--   Unregister(instance, state)              undo world changes
--   Step(dt, active, now)                    optional, animated kinds; active = { [instance] = state }, near the camera
--   OnTouched(instance, state, ball)         optional, local ball touches only
--   Debounce                                 optional seconds between OnTouched calls per object
-- Helper modules live in the Support folder (only ModuleScripts directly under this one are tag kinds).
--
-- Rules:
--   * Only instances inside workspace are tracked; with StreamingEnabled they register on stream-in and unregister on
--     stream-out (the removed signal fires for both, and for destroy). Each object owns a Trove.
--   * ONE Heartbeat connection drives every animated kind. Every SCAN_INTERVAL it refreshes which registered objects
--     are within ACTIVE_RANGE of the camera; Step then runs each frame for those only.
--   * Time is workspace:GetServerTimeNow(), so all clients show the same phase.
--
-- Public API:
--   ObstacleController.GetRegistered(tag) -> { [instance] = state }   live table, read-only (e.g. GrappleAnchor)
--   ObstacleController.Registered   Signal, fires (tag, instance) after an object finishes registering
--   ObstacleController.SetTimeWarp(scale, radius, getPosition)   -- Time Slow: animated obstacles within radius studs of
--       getPosition() run at scale x speed on THIS client only (each state gets a TimeLag that Step subtracts from `now`).
--       After ClearTimeWarp they catch up to the shared clock (Shared/TimeWarp).
--   ObstacleController.ClearTimeWarp()

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Signal = require(ReplicatedStorage.Utilities.Signal)
local Trove = require(ReplicatedStorage.Utilities.Trove)
local TimeWarp = require(ReplicatedStorage.Shared.TimeWarp)

local BallLink = require(script.Support.BallLink)

local ObstacleController = {}
ObstacleController.Registered = Signal.new()

-- ── Tuning ──────────────────────────────────────────────────────────────
local SCAN_INTERVAL = 0.25 -- seconds between active-set refreshes
local ACTIVE_RANGE = 450 -- studs from the camera within which animated objects step
local DEFAULT_DEBOUNCE = 0.25 -- seconds between touch callbacks per object
local STREAM_SETTLE = 0.2 -- seconds for the rest of a streaming Model to arrive after its first part

-- ── State ───────────────────────────────────────────────────────────────
local kinds = {} -- [tag] = module
local records = {} -- [tag] = { [instance] = record }
local states = {} -- [tag] = { [instance] = state } (only successfully registered objects)
local active = {} -- [tag] = { [instance] = state } (animated kinds, near the camera)
local stepKinds = {} -- list of tags that export Step
local scanAccumulator = 0
local warp = nil -- { Scale, Radius, GetPosition } while Time Slow is active
local hasLag = false -- some state still has a TimeLag to recover

local function touchParts(instance)
	local parts = {}
	if instance:IsA("BasePart") then
		table.insert(parts, instance)
	end
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

-- With StreamingEnabled a tagged Model can arrive before its parts, so an empty Model is not yet a misconfiguration.
-- Returns false if the object left the workspace before any part arrived.
local function waitForParts(instance)
	if #touchParts(instance) > 0 then
		return true
	end
	local thread = coroutine.running()
	local connections = {}
	local function finish(result)
		for _, connection in connections do
			connection:Disconnect()
		end
		task.spawn(thread, result)
	end
	table.insert(
		connections,
		instance.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("BasePart") then
				finish(true)
			end
		end)
	)
	table.insert(
		connections,
		instance.AncestryChanged:Connect(function()
			if not instance:IsDescendantOf(workspace) then
				finish(false)
			end
		end)
	)
	local arrived = coroutine.yield()
	if arrived then
		task.wait(STREAM_SETTLE)
	end
	return arrived
end

local function disable(tag, instance, reason)
	warn(("[ObstacleController] %s is tagged %q but %s"):format(instance:GetFullName(), tag, reason))
end

local function hookTouches(tag, instance, record)
	local kind = kinds[tag]
	local parts = touchParts(instance)
	if #parts == 0 then
		return false
	end
	local debounce = kind.Debounce or DEFAULT_DEBOUNCE
	local lastTouch = -math.huge
	for _, part in parts do
		record.Trove:Connect(part.Touched, function(hit)
			local now = os.clock()
			if now - lastTouch < debounce or not BallLink.IsLocalBallPart(hit) then
				return
			end
			lastTouch = now
			local ball = BallLink.GetBall()
			if ball and record.State then
				kind.OnTouched(instance, record.State, ball)
			end
		end)
	end
	return true
end

local function unregister(tag, instance)
	local record = records[tag][instance]
	if not record then
		return
	end
	records[tag][instance] = nil
	states[tag][instance] = nil
	if active[tag] then
		active[tag][instance] = nil
	end
	record.Trove:Destroy()
	if record.State then
		local ok, err = pcall(kinds[tag].Unregister, instance, record.State)
		if not ok then
			warn(
				("[ObstacleController] %s Unregister failed for %s: %s"):format(
					tag,
					instance:GetFullName(),
					tostring(err)
				)
			)
		end
	end
end

local function register(tag, instance)
	if records[tag][instance] or not instance:IsDescendantOf(workspace) then
		return
	end
	local kind = kinds[tag]
	local record = { Trove = Trove.new() }
	records[tag][instance] = record

	task.spawn(function()
		local hasParts = waitForParts(instance)
		if records[tag][instance] ~= record then
			return
		end
		if not hasParts then
			unregister(tag, instance)
			return
		end

		local ok, state, reason = pcall(kind.Register, instance)
		-- Register may have yielded: the object can be gone, or replaced by a newer record.
		if records[tag][instance] ~= record then
			if ok and state then
				pcall(kind.Unregister, instance, state)
			end
			return
		end
		if not ok then
			disable(tag, instance, ("Register failed: %s"):format(tostring(state)))
			unregister(tag, instance)
			return
		end
		if not state then
			disable(tag, instance, reason or "is misconfigured")
			unregister(tag, instance)
			return
		end

		record.State = state
		if kind.OnTouched and not hookTouches(tag, instance, record) then
			disable(tag, instance, "contains no BasePart to touch")
			unregister(tag, instance)
			return
		end
		states[tag][instance] = state
		ObstacleController.Registered:Fire(tag, instance)
	end)
end

-- ── Animation loop ──────────────────────────────────────────────────────
local function refreshActive()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local origin = camera.CFrame.Position
	for _, tag in stepKinds do
		local set = active[tag]
		table.clear(set)
		for instance, state in states[tag] do
			if
				instance:IsDescendantOf(workspace)
				and (instance:GetPivot().Position - origin).Magnitude <= ACTIVE_RANGE
			then
				set[instance] = state
			end
		end
	end
end

local function updateLags(dt)
	local center = if warp then warp.GetPosition() else nil
	hasLag = false
	for _, tag in stepKinds do
		for instance, state in states[tag] do
			local lag = state.TimeLag or 0
			if lag == 0 and not warp then
				continue
			end
			local isSlowed = center ~= nil
				and instance:IsDescendantOf(workspace)
				and (instance:GetPivot().Position - center).Magnitude <= warp.Radius
			lag = TimeWarp.StepLag(lag, dt, if warp then warp.Scale else 1, isSlowed)
			state.TimeLag = lag
			if lag > 0 then
				hasLag = true
			end
		end
	end
end

function ObstacleController.SetTimeWarp(scale, radius, getPosition)
	if type(scale) == "number" and type(radius) == "number" and type(getPosition) == "function" then
		warp = { Scale = scale, Radius = radius, GetPosition = getPosition }
	end
end

function ObstacleController.ClearTimeWarp()
	warp = nil
end

local function onHeartbeat(dt)
	if warp or hasLag then
		local ok, err = pcall(updateLags, dt)
		if not ok then
			warn("[ObstacleController] Time warp failed: " .. tostring(err))
			warp = nil
		end
	end
	scanAccumulator += dt
	if scanAccumulator >= SCAN_INTERVAL then
		scanAccumulator = 0
		refreshActive()
	end
	local now = workspace:GetServerTimeNow()
	for _, tag in stepKinds do
		local set = active[tag]
		if next(set) ~= nil then
			local ok, err = xpcall(kinds[tag].Step, debug.traceback, dt, set, now)
			if not ok then
				warn(("[ObstacleController] %s Step failed: %s"):format(tag, tostring(err)))
			end
		end
	end
end

function ObstacleController.GetRegistered(tag)
	return states[tag] or {}
end

-- ── Startup ─────────────────────────────────────────────────────────────
for _, child in script:GetChildren() do
	if child:IsA("ModuleScript") then
		local ok, result = pcall(require, child)
		if ok then
			kinds[child.Name] = result
		else
			warn(("[ObstacleController] %s failed to load: %s"):format(child.Name, tostring(result)))
		end
	end
end

for tag, kind in kinds do
	records[tag] = {}
	states[tag] = {}
	if kind.Step then
		active[tag] = {}
		table.insert(stepKinds, tag)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance)
		register(tag, instance)
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance)
		unregister(tag, instance)
	end)
	for _, instance in CollectionService:GetTagged(tag) do
		register(tag, instance)
	end
end

if #stepKinds > 0 then
	RunService.Heartbeat:Connect(onHeartbeat)
end

return ObstacleController
