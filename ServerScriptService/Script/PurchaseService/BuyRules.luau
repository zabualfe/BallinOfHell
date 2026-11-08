-- BuyRules
-- Pure "can this product be prompted now" rules for the core plug-ins.
--
-- Usage:
--   BuyRules.BallPurchasable(ballId, rarity, ownedBalls) -> ok, reason
--     reason: "Unknown" | "WrongRarity" | "Exclusive" | "Owned"   (shop balls only: BallTable.Source Starter/Coins)
--   BuyRules.SkipTarget(state, segmentCount, count, isNoSkip?) -> targetIndex?, reason?
--     state is ProgressService.GetState(player) (nil = not in the race). Reasons: "NotRacing" or a
--     ProgressService.Rules.CanSkip reason ("Finished" "NotAhead" "FinishLocked" "NoSkipTier").

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BallTable = require(ReplicatedStorage.Tables.BallTable)
local InventoryRules = require(ReplicatedStorage.Shared.InventoryRules)
local ProgressRules = require(script.Parent.Parent.ProgressService.Rules)

local BuyRules = {}

function BuyRules.BallPurchasable(ballId, rarity, ownedBalls)
	local ball = type(ballId) == "string" and BallTable[ballId] or nil
	if not ball then
		return false, "Unknown"
	end
	if ball.Rarity ~= rarity then
		return false, "WrongRarity"
	end
	if ball.Exclusive == true or not InventoryRules.IsSourceAllowed(ballId, "Robux") then
		return false, "Exclusive"
	end
	if ownedBalls and ownedBalls[ballId] ~= nil then
		return false, "Owned"
	end
	return true, nil
end

function BuyRules.SkipTarget(state, segmentCount, count, isNoSkip)
	if not state or not state.Racing then
		return nil, "NotRacing"
	end
	local target = state.Checkpoint + count
	local ok, reason = ProgressRules.CanSkip({
		Current = state.Checkpoint,
		Target = target,
		FinishIndex = segmentCount,
		Finished = state.Finished,
		IsNoSkip = isNoSkip,
	})
	if not ok then
		return nil, reason
	end
	return target, nil
end

return BuyRules
