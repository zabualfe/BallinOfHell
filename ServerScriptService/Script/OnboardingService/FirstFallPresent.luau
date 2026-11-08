-- FirstFallPresent
-- Server half of the first-fall present (GDD 10.2), a child of OnboardingService. The first Fell of session 1
-- records a pending gift at the checkpoint and tells the owner to show it; ClaimFirstFallGift grants it once ever.
--
-- Network: ShowFirstFallPresent(cframe) to the owner; ClaimFirstFallGift() from the owner;
--   then FirstFallGiftClaimed(summary) and, if a Starter Pack offer is live (player attribute StarterPackEndsAt in
--   the future), ShowStarterPackHint().
-- Shield-absorbed falls never fire Fell, so they never trigger it. The pending gift is runtime only: it is dropped
-- on leave and whenever RoundState changes, because the client present is torn down with the round.
-- The grant uses source "FirstFall".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage.Network)
local EconomyTable = require(ReplicatedStorage.Tables.EconomyTable)
local RewardRules = require(ReplicatedStorage.Shared.RewardRules)
local AnalyticsService = require(script.Parent.Parent.AnalyticsService)
local PlayerData = require(script.Parent.Parent.PlayerData)
local ProgressService = require(script.Parent.Parent.ProgressService)
local CourseService = require(script.Parent.Parent.CourseService)
local PresentRules = require(script.Parent.PresentRules)
local RewardService = require(script.Parent.Parent.RewardService)

local FirstFallPresent = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local SOURCE = "FirstFall"
local CLAIM_RATE = { Capacity = 2, RefillPerSecond = 0.5 }

local pending = {} -- [player] = CFrame where the present was shown
local claiming = {} -- [player] = true while a claim is being granted

local function logStep(player, step)
	AnalyticsService.Funnel(player, "Onboarding", step)
end

local function onFell(player)
	if not PlayerData.IsLoaded(player) then
		return
	end
	local shouldSpawn = PresentRules.ShouldSpawn({
		SessionCount = PlayerData.Peek(player, "sessionCount"),
		Claimed = PlayerData.Peek(player, "firstFallGiftClaimed"),
		HasPending = pending[player] ~= nil,
	})
	if not shouldSpawn then
		return
	end
	local state = ProgressService.GetState(player)
	local cframe = state and CourseService.GetSpawnCFrame(state.Checkpoint)
	if not cframe then
		return
	end
	pending[player] = cframe
	logStep(player, "FirstFall")
	Network.FireClient(player, "ShowFirstFallPresent", cframe)
end

local function claim(player)
	local canClaim = PresentRules.CanClaim({
		HasPending = pending[player] ~= nil and not claiming[player],
		Claimed = PlayerData.Peek(player, "firstFallGiftClaimed") == true,
	})
	if not canClaim then
		return false
	end
	claiming[player] = true
	local granted, summary = RewardService.Grant(player, EconomyTable.Sources.FirstFallPresent, SOURCE)
	claiming[player] = nil
	-- A partial grant is still final: re-granting would double-pay the parts that landed.
	if not RewardRules.IsFinalGrant(granted, summary) then
		return false
	end
	if not granted then
		warn(`[FirstFallPresent] First-fall gift only partly granted for {player.Name}; claim kept`)
	end
	if not PlayerData.Set(player, "firstFallGiftClaimed", true) then
		warn(`[FirstFallPresent] Could not save the claim flag for {player.Name}`)
	end
	pending[player] = nil
	logStep(player, "PresentClaimed")
	Network.FireClient(player, "FirstFallGiftClaimed", summary)

	local endsAt = player:GetAttribute("StarterPackEndsAt")
	if PresentRules.IsFuture(endsAt, workspace:GetServerTimeNow()) then
		Network.FireClient(player, "ShowStarterPackHint")
	end
	return true
end

ProgressService.Fell:Connect(onFell)

Network.OnEvent("ClaimFirstFallGift", function(player)
	claim(player)
end, CLAIM_RATE)

workspace:GetAttributeChangedSignal("RoundState"):Connect(function()
	table.clear(pending)
end)

Players.PlayerRemoving:Connect(function(player)
	pending[player] = nil
	claiming[player] = nil
end)

return FirstFallPresent
