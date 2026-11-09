-- CourseService
-- Builds the 30-segment course under workspace.Course and answers geometry questions about it.
-- The first segment always starts on the pivot of workspace.Lobby.Start (a part in the lobby), so the course runs
-- straight out of the lobby; that pivot is also the start line (checkpoint 0).
-- Segment models are authored in Studio (ServerStorage.Segments/<Tier>/<Name>, ServerStorage.CourseParts
-- holding CheckpointFlag and EndTrack); this module never creates them. Missing or empty folders
-- warn once and build nothing. A segment that breaks the authoring contract warns and is skipped.
--
-- Public API (ProgressService and RoundService use it):
--   CourseService.Build(seed?) -> boolean        -- yields until built. false if nothing could be built or a build
--                                                   is already running; true (no rebuild) if a course is already up
--   CourseService.Teardown()                     -- destroys workspace.Course and clears all state
--   CourseService.GetSegmentCount() -> number    -- 0 when not built
--   CourseService.GetCheckpoint(index) -> { CFrame, Tier, ParTime, SegmentName, Flags }?
--       Flags = { NoTools, ToolsAllowed, ToolRequired } from the segment's attributes (ToolService reads them)
--       Checkpoint n is the joint at the end of segment n; the last one is the finish. Read-only.
--   CourseService.GetSpawnCFrame(index) -> CFrame?  -- index 0 is the start line; clamps to the course length
--   CourseService.FindFallSegment(position) -> index?  -- segment the position fell from, nil if still above
--   CourseService.IsInSegment(index, position) -> boolean  -- above segment index's floor and inside its footprint
--   CourseService.GetSeed() -> number?
--   CourseService.Built                          -- Signal, fires (seed) after each successful Build
--   CourseService.IsBuilt() -> boolean
--
-- Studio-only SegmentTest: set the workspace attribute "SegmentTest" (or SEGMENT_TEST_NAME below) to a segment
-- name and Build makes a one-segment course of just that segment. Ignored outside Studio.
-- Tunables: ReplicatedStorage/Tables/CourseTable (Slots, Picker, Segment, Progress); server-only ones below.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local CourseTable = require(ReplicatedStorage.Tables.CourseTable)
local Signal = require(ReplicatedStorage.Utilities.Signal)

local CheckpointBuilder = require(script.CheckpointBuilder)
local FallZones = require(script.FallZones)
local SegmentPicker = require(script.SegmentPicker)
local SegmentValidator = require(script.SegmentValidator)

local CourseService = {}
CourseService.Built = Signal.new()

-- ── Tuning ──────────────────────────────────────────────────────────────
local LOBBY_NAME = "Lobby"
local LOBBY_START_NAME = "Start" -- workspace.Lobby.Start: its pivot is where the first segment's StartPart goes
local COURSE_ORIGIN_FALLBACK = CFrame.new(0, 100, 0) -- used (with a warning) when workspace.Lobby.Start is missing
local SPAWN_LIFT = 4 -- studs above a checkpoint or the start line where a ball is placed
local FALL_FOOTPRINT_MARGIN = 4 -- studs shaved off each side of a segment's fall footprint
local SEGMENT_TEST_NAME = "" -- Studio only: segment name to build alone; the SegmentTest attribute overrides it
local SEED_MAX = 2147483647

-- ── State ───────────────────────────────────────────────────────────────
local seedRandom = Random.new()
local warnedKeys = {}
local lastPicks -- last round's names per slot, for the avoid-repeat rule
local courseFolder
local checkpoints = {}
local fallZones = {}
local fallFloorY
local startCFrame
local courseSeed
local isBuilding = false
local generation = 0 -- bumped by Teardown so a build in flight stops

local function warnOnce(key, message)
	if warnedKeys[key] then
		return
	end
	warnedKeys[key] = true
	warn("[CourseService] " .. message)
end

-- ── Segment pool ────────────────────────────────────────────────────────
-- Returns pool (tier -> list for the picker), templates (tier -> name -> model) and the valid count.
local function gatherSegments()
	local segmentsFolder = ServerStorage:FindFirstChild("Segments")
	if not segmentsFolder then
		warnOnce("NoSegments", "ServerStorage.Segments is missing; no course will be built")
		return nil
	end

	local pool, templates, validCount = {}, {}, 0
	for tier in CourseTable.Tiers do
		pool[tier], templates[tier] = {}, {}
		local tierFolder = segmentsFolder:FindFirstChild(tier)
		if tierFolder then
			-- GetChildren order is not stable; sorting makes the same seed rebuild the same course.
			local children = tierFolder:GetChildren()
			table.sort(children, function(a, b)
				return a.Name < b.Name
			end)
			for _, model in children do
				local info, problem = SegmentValidator.Validate(model, tier)
				if not info then
					warnOnce(
						"Invalid" .. model:GetFullName(),
						("%s %s; skipping this segment"):format(model:GetFullName(), problem)
					)
				elseif templates[tier][info.Name] then
					warnOnce(
						"Duplicate" .. model:GetFullName(),
						("%s repeats the name of another %s segment; skipping it"):format(model:GetFullName(), tier)
					)
				else
					templates[tier][info.Name] = model
					table.insert(pool[tier], info)
					validCount += 1
				end
			end
		end
	end
	if validCount == 0 then
		warnOnce("EmptySegments", "ServerStorage.Segments has no valid segments; no course will be built")
		return nil
	end
	return pool, templates
end

local function getTestSegmentName()
	if not RunService:IsStudio() then
		return nil
	end
	local name = workspace:GetAttribute("SegmentTest")
	if type(name) ~= "string" or name == "" then
		name = SEGMENT_TEST_NAME
	end
	if name == "" then
		return nil
	end
	return name
end

-- Returns a list of { Tier, Name } to build plus the picked names per slot (nil in SegmentTest), or nil.
local function chooseSelection(pool, rng)
	local testName = getTestSegmentName()
	if testName then
		for tier, list in pool do
			for _, info in list do
				if info.Name == testName then
					return { { Tier = tier, Name = testName } }, nil
				end
			end
		end
		warnOnce(
			"TestMissing" .. testName,
			("SegmentTest segment %q is not a valid segment; building the normal course"):format(testName)
		)
	end

	local picks, sourceTiers, notes = SegmentPicker.Pick(pool, CourseTable.Slots, rng, lastPicks, CourseTable.Picker)
	for _, note in notes do
		warnOnce("Pick" .. note, note)
	end
	if not picks then
		return nil
	end

	local selection = {}
	for slot, name in picks do
		table.insert(selection, { Tier = sourceTiers[slot], Name = name })
	end
	return selection, picks
end

-- ── Public API ──────────────────────────────────────────────────────────
function CourseService.IsBuilt()
	return courseFolder ~= nil and not isBuilding
end

function CourseService.GetSegmentCount()
	return #checkpoints
end

function CourseService.GetSeed()
	return courseSeed
end

function CourseService.GetCheckpoint(index)
	return checkpoints[index]
end

function CourseService.GetSpawnCFrame(index)
	if not startCFrame then
		return nil
	end
	local cframe = startCFrame
	if index >= 1 and #checkpoints > 0 then
		cframe = checkpoints[math.min(math.floor(index), #checkpoints)].CFrame
	end
	return cframe + Vector3.new(0, SPAWN_LIFT, 0)
end

function CourseService.FindFallSegment(position)
	return FallZones.Find(fallZones, position, fallFloorY)
end

function CourseService.IsInSegment(index, position)
	local zone = fallZones[index]
	return zone ~= nil and FallZones.Contains(zone, position)
end

function CourseService.Teardown()
	generation += 1
	isBuilding = false
	if courseFolder then
		courseFolder:Destroy()
	end
	courseFolder = nil
	checkpoints = {}
	fallZones = {}
	fallFloorY = nil
	startCFrame = nil
	courseSeed = nil
end

local function getCourseOrigin()
	local lobby = workspace:FindFirstChild(LOBBY_NAME)
	local start = lobby and lobby:FindFirstChild(LOBBY_START_NAME)
	if start and start:IsA("PVInstance") then
		return start:GetPivot()
	end
	warnOnce(
		"NoLobbyStart",
		`workspace.{LOBBY_NAME}.{LOBBY_START_NAME} (a part or model) is missing; the course starts at the fallback origin`
	)
	return COURSE_ORIGIN_FALLBACK
end

-- Clones and joins every selected segment under folder, starting at origin. Returns checkpoints, boxes, names, or
-- nil if torn down.
local function buildSegments(selection, pool, templates, folder, myGeneration, origin)
	local partsFolder = ServerStorage:FindFirstChild("CourseParts")
	if not partsFolder then
		warnOnce("NoCourseParts", "ServerStorage.CourseParts is missing; building without Start, flags or EndTrack")
	end
	local function getPart(name)
		local part = partsFolder and partsFolder:FindFirstChild(name)
		if partsFolder and not part then
			warnOnce("NoPart" .. name, "ServerStorage.CourseParts." .. name .. " is missing; building without it")
		end
		return part
	end
	local flagTemplate, endTrackTemplate = getPart("CheckpointFlag"), getPart("EndTrack")

	local newCheckpoints, boxes, names = {}, {}, {}
	local anchorCF = origin

	for index, choice in selection do
		-- One segment per frame so the server does not hitch.
		RunService.Heartbeat:Wait()
		if myGeneration ~= generation then
			return nil
		end

		local info
		for _, candidate in pool[choice.Tier] do
			if candidate.Name == choice.Name then
				info = candidate
				break
			end
		end
		local clone, endCF = CheckpointBuilder.Place(templates[choice.Tier][choice.Name], anchorCF, folder)
		local boxCF, boxSize = clone:GetBoundingBox()
		table.insert(boxes, { CFrame = boxCF, Size = boxSize })
		table.insert(names, choice.Name)
		table.insert(newCheckpoints, CheckpointBuilder.Entry(endCF, info.Tier, info.ParTime, info.Name, info.Flags))
		CheckpointBuilder.Place(flagTemplate, endCF, folder)
		anchorCF = endCF
		if index == #selection then
			CheckpointBuilder.Place(endTrackTemplate, endCF, folder)
		end
	end
	return newCheckpoints, boxes, names
end

function CourseService.Build(seed)
	if isBuilding then
		warn("[CourseService] Build called while a build is running")
		return false
	end
	if courseFolder then
		return true
	end

	local pool, templates = gatherSegments()
	if not pool then
		return false
	end

	seed = seed or seedRandom:NextInteger(1, SEED_MAX)
	local selection, picks = chooseSelection(pool, Random.new(seed))
	if not selection then
		return false
	end

	isBuilding = true
	local myGeneration = generation
	local folder = Instance.new("Folder")
	folder.Name = "Course"
	folder.Parent = workspace

	local origin = getCourseOrigin()
	local ok, newCheckpoints, boxes, names =
		pcall(buildSegments, selection, pool, templates, folder, myGeneration, origin)
	if myGeneration ~= generation then
		-- Teardown ran mid-build and already reset the flags; just drop the partial folder.
		folder:Destroy()
		return false
	end
	if not ok or not newCheckpoints then
		warn("[CourseService] Build failed: " .. tostring(newCheckpoints))
		folder:Destroy()
		isBuilding = false
		return false
	end

	local zones = {}
	for _, box in boxes do
		table.insert(
			zones,
			FallZones.FromBox(box.CFrame, box.Size, FALL_FOOTPRINT_MARGIN, CourseTable.Segment.FallVolumePadding)
		)
	end

	courseFolder = folder
	checkpoints = newCheckpoints
	fallZones = zones
	fallFloorY = FallZones.GetFloorY(zones, CourseTable.Progress.YFloorBelowLowestSegment)
	startCFrame = origin
	courseSeed = seed
	lastPicks = picks or lastPicks
	isBuilding = false

	print(("[CourseService] Build log (GDD 13): seed %d, segments %s"):format(seed, table.concat(names, ", ")))
	CourseService.Built:Fire(seed)
	return true
end

return CourseService
