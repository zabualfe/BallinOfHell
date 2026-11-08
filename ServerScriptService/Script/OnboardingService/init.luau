-- OnboardingService
-- FTUE starter pick (GDD 10.1). The player picks one Starter ball once; this grants it, equips it and sets
-- hasPickedStarter. It does not spawn the ball: BallService.Spawn refuses until hasPickedStarter is true, and
-- RoundService spawns on StarterPicked.
--
-- Usage:
--   OnboardingService.StarterPicked:Connect(function(player, ballId) end)
--
-- Network: PickStarter(ballId) from the client; the owner then receives StarterPicked(ballId).
-- New players hold 3 Shield charges in slot 1: DataTemplate already does this (tests/Utilities/DataTemplate.spec).
--
-- First-fall present (GDD 10.2): lives in the FirstFallPresent child, required below. Rules are in PresentRules.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage.Network)
local InventoryRules = require(ReplicatedStorage.Shared.InventoryRules)
local Signal = require(ReplicatedStorage.Utilities.Signal)
local PlayerData = require(script.Parent.PlayerData)
local InventoryService = require(script.Parent.InventoryService)

local OnboardingService = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local PICK_CAPACITY = 3 -- PickStarter burst
local PICK_REFILL = 0.5 -- PickStarter per second

OnboardingService.StarterPicked = Signal.new() -- (player, ballId)

local inFlight = {} -- [player] = true while a pick is being processed

local function pickStarter(player, ballId)
	if inFlight[player] or not PlayerData.IsLoaded(player) then
		return
	end
	if not InventoryRules.CanPickStarter(ballId, PlayerData.Peek(player, "hasPickedStarter")) then
		return
	end

	inFlight[player] = true
	-- A half-finished earlier pick may already own the ball; only grant when missing.
	local isReady = InventoryService.OwnsBall(player, ballId) or InventoryService.GrantBall(player, ballId, "Starter")
	if isReady and InventoryService.Equip(player, ballId) and PlayerData.Set(player, "hasPickedStarter", true) then
		Network.FireClient(player, "StarterPicked", ballId)
		OnboardingService.StarterPicked:Fire(player, ballId)
	end
	inFlight[player] = nil
end

Network.OnEvent("PickStarter", function(player, ballId)
	if type(ballId) ~= "string" then
		return
	end
	pickStarter(player, ballId)
end, { Capacity = PICK_CAPACITY, RefillPerSecond = PICK_REFILL })

require(script.FirstFallPresent)

return OnboardingService
