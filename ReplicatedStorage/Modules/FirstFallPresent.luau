-- FirstFallPresent (client)
-- Shows the first-fall present (GDD 10.2) as a client-only visual. The server decides whether it appears
-- (ShowFirstFallPresent) and whether the claim counts; this module only places the authored template and reports a tap.
--
-- Authored asset: ReplicatedStorage.Assets.Present (Model or BasePart). A ProximityPrompt or ClickDetector inside it is
-- used for tapping; without one, the local ball touching any of its parts claims. Missing asset: warn once, skip.
--
-- Usage:
--   FirstFallPresent.Claimed:Connect(function() end)  -- fires once when the claim message is sent (RewardFly hook)
--   FirstFallPresent.IsShowing() -> boolean
--
-- The present is destroyed on claim, on a RoundState change (round teardown) and when the character is removed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(script.Parent.Parent.Network)
local Signal = require(script.Parent.Parent.Utilities.Signal)
local Trove = require(script.Parent.Parent.Utilities.Trove)
local BallController = require(script.Parent.BallController)

local FirstFallPresent = {}
FirstFallPresent.Claimed = Signal.new()

-- ── Tuning ──────────────────────────────────────────────────────────────
local ASSET_FOLDER = "Assets"
local ASSET_NAME = "Present"
local CLAIM_DEBOUNCE = 1 -- seconds between ClaimFirstFallGift messages

local trove = nil
local hasWarned = false
local lastClaimAt = -math.huge

local function destroyPresent()
	if trove then
		trove:Destroy()
		trove = nil
	end
end

local function claim()
	if not trove then
		return
	end
	local now = os.clock()
	if now - lastClaimAt < CLAIM_DEBOUNCE then
		return
	end
	lastClaimAt = now
	Network.FireServer("ClaimFirstFallGift")
	FirstFallPresent.Claimed:Fire()
	destroyPresent()
end

local function isOwnBall(part)
	local ball = BallController.GetBall()
	return ball ~= nil and part:IsDescendantOf(ball)
end

local function findTemplate()
	local assets = ReplicatedStorage:FindFirstChild(ASSET_FOLDER)
	local template = assets and assets:FindFirstChild(ASSET_NAME)
	if template and (template:IsA("Model") or template:IsA("BasePart")) then
		return template
	end
	if not hasWarned then
		hasWarned = true
		warn(
			`[FirstFallPresent] Missing ReplicatedStorage.{ASSET_FOLDER}.{ASSET_NAME} (Model or BasePart); no present shown`
		)
	end
	return nil
end

local function wireInput(present, newTrove)
	local hasInput = false
	for _, descendant in present:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then
			hasInput = true
			newTrove:Connect(descendant.Triggered, claim)
		elseif descendant:IsA("ClickDetector") then
			hasInput = true
			newTrove:Connect(descendant.MouseClick, claim)
		end
	end
	if hasInput then
		return
	end

	local parts = present:GetDescendants()
	table.insert(parts, present)
	for _, part in parts do
		if part:IsA("BasePart") then
			newTrove:Connect(part.Touched, function(other)
				if isOwnBall(other) then
					claim()
				end
			end)
		end
	end
end

local function show(cframe)
	if typeof(cframe) ~= "CFrame" then
		return
	end
	destroyPresent()
	local template = findTemplate()
	if not template then
		return
	end

	local present = template:Clone()
	local newTrove = Trove.new()
	newTrove:Add(present)
	trove = newTrove

	present:PivotTo(cframe)
	present.Parent = workspace
	wireInput(present, newTrove)
end

function FirstFallPresent.IsShowing()
	return trove ~= nil
end

function FirstFallPresent.CharacterRemoving()
	destroyPresent()
end

Network.OnEvent("ShowFirstFallPresent", show)

workspace:GetAttributeChangedSignal("RoundState"):Connect(destroyPresent)

return FirstFallPresent
