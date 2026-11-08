-- Products/StarterPack
-- Family "Offers", the Starter Pack only (CrownOfHell, RestoreDailyStreak and UnlockAllTimedGifts belong to
-- their own tasks). Contents come from StarterPackTable.Contents and are granted through RewardService.
--
-- CanPrompt: only while the offer is live. Effect does NOT re-check the window: the Robux is already spent.
-- Retry safety (Roblox re-sends a receipt when Effect returns false): unlocks go first and are skipped when
-- already owned, so a retry never pays duplicate-ball coins. Only then is `starterPackBought` set and the
-- consumables (coins, spins, boost) granted, once. If a retry finds the flag already set, the consumables were
-- granted (or attempted) before, so only the unlocks are rechecked and nothing is paid twice.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnalyticsTable = require(ReplicatedStorage.Tables.AnalyticsTable)
local RewardRules = require(ReplicatedStorage.Shared.RewardRules)
local StarterPackTable = require(ReplicatedStorage.Tables.StarterPackTable)

local AnalyticsService = require(script.Parent.Parent.Parent.AnalyticsService)
local InventoryService = require(script.Parent.Parent.Parent.InventoryService)
local PlayerData = require(script.Parent.Parent.Parent.PlayerData)
local RewardService = require(script.Parent.Parent.Parent.RewardService)
local StarterPackService = require(script.Parent.Parent.Parent.StarterPackService)

local SOURCE = "StarterPack"

local ops, problems = RewardRules.Normalize(StarterPackTable.Contents)
if #problems > 0 then
	warn(`[PurchaseService] StarterPackTable.Contents is invalid: {table.concat(problems, "; ")}`)
end

local function splitContents(player)
	local unlocks, consumables = {}, {}
	for _, op in ops do
		if not RewardRules.IsOwnership(op.Kind) then
			table.insert(consumables, RewardRules.ToEntry(op))
		elseif not (op.Kind == "Ball" and InventoryService.OwnsBall(player, op.Id)) then
			table.insert(unlocks, RewardRules.ToEntry(op))
		end
	end
	return unlocks, consumables
end

local StarterPack = { Products = {} }

StarterPack.Products[StarterPackTable.ProductKey] = {
	CanPrompt = function(player)
		return StarterPackService.IsLive(player)
	end,
	Effect = function(player)
		if #problems > 0 or not PlayerData.IsLoaded(player) then
			return false
		end
		local unlocks, consumables = splitContents(player)
		if not RewardService.Grant(player, unlocks, SOURCE) then
			return false
		end
		if PlayerData.Peek(player, "starterPackBought") == true then
			warn(`[PurchaseService] Starter Pack already marked bought for {player.Name}; consumables not paid again`)
			return true
		end
		if not PlayerData.Set(player, "starterPackBought", true) then
			return false
		end
		local granted, summary = RewardService.Grant(player, consumables, SOURCE)
		if not granted then
			warn(`[PurchaseService] Starter Pack consumables only partly granted for {player.Name}`)
			AnalyticsService.Custom(player, AnalyticsTable.Events.StarterPackPartialGrant, #summary, {
				Expected = #consumables,
			})
		end
		return true
	end,
}

return StarterPack
