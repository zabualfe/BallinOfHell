-- InventoryService
-- Owns `ownedBalls` and `equippedBall` in PlayerData. Every ball grant in the game goes through GrantBall.
--
-- Usage:
--   InventoryService.OwnsBall(player, ballId) -> boolean
--   InventoryService.GrantBall(player, ballId, source, extra?) -> boolean
--     extra = { serial = n? }. false when the id is unknown, data isn't loaded, the ball is already owned, or
--     the source isn't allowed for that ball. Allowed source strings: see Shared/InventoryRules.
--   InventoryService.Equip(player, ballId) -> boolean   -- must own it
--   InventoryService.BallGranted:Connect(function(player, ballId, source) end)
--   InventoryService.DuplicateGranted:Connect(function(player, ballId, source) end)
--     Seam for EconomyService (next sprint): it converts duplicates to coins. GrantBall returns false for them.
--
-- Network: EquipBall(ballId) from the client. Server fires nothing extra; clients read ownedBalls/equippedBall
-- from the replicated PlayerData.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage.Network)
local InventoryRules = require(ReplicatedStorage.Shared.InventoryRules)
local Signal = require(ReplicatedStorage.Utilities.Signal)
local PlayerData = require(script.Parent.PlayerData)

local InventoryService = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local EQUIP_CAPACITY = 5 -- EquipBall burst
local EQUIP_REFILL = 1 -- EquipBall per second

InventoryService.BallGranted = Signal.new() -- (player, ballId, source)
InventoryService.DuplicateGranted = Signal.new() -- (player, ballId, source)

function InventoryService.OwnsBall(player, ballId)
	if type(ballId) ~= "string" or not PlayerData.IsLoaded(player) then
		return false
	end
	local owned = PlayerData.Peek(player, "ownedBalls")
	return owned ~= nil and owned[ballId] ~= nil
end

function InventoryService.GrantBall(player, ballId, source, extra)
	if not PlayerData.IsLoaded(player) then
		return false
	end

	local owned = PlayerData.Get(player, "ownedBalls")
	local ok, reason = InventoryRules.DecideGrant(ballId, source, owned)
	if not ok then
		if reason == "Owned" then
			InventoryService.DuplicateGranted:Fire(player, ballId, source)
		elseif reason == "WrongSource" then
			warn(("[InventoryService] %s may not be granted by source %q"):format(ballId, tostring(source)))
		end
		return false
	end

	local serial = type(extra) == "table" and extra.serial or nil
	owned[ballId] = { at = workspace:GetServerTimeNow(), serial = serial }
	if not PlayerData.Set(player, "ownedBalls", owned) then
		return false
	end

	InventoryService.BallGranted:Fire(player, ballId, source)
	return true
end

function InventoryService.Equip(player, ballId)
	if not InventoryService.OwnsBall(player, ballId) then
		return false
	end
	return PlayerData.Set(player, "equippedBall", ballId)
end

Network.OnEvent("EquipBall", function(player, ballId)
	if type(ballId) ~= "string" then
		return
	end
	InventoryService.Equip(player, ballId)
end, { Capacity = EQUIP_CAPACITY, RefillPerSecond = EQUIP_REFILL })

return InventoryService
