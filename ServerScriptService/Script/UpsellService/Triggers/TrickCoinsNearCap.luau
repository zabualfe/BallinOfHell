-- TrickCoinsNearCap: Results screen with MinCoins or more trick coins earned this round and no 2x Trick Coins pass.
-- Trick coins are summed from TrickService.TrickLanded during the race (its payout after multipliers and caps).
-- A Results card, not a popup. Contract: see UpsellService.

local Players = game:GetService("Players")

local RoundService = require(script.Parent.Parent.Parent.RoundService)
local TrickService = require(script.Parent.Parent.Parent.TrickService)

local ID = "TrickCoinsNearCap"

local earned = {} -- [player] = trick coins this round

return {
	Id = ID,
	Start = function(UpsellService)
		TrickService.TrickLanded:Connect(function(player, _, coins)
			if type(coins) == "number" then
				earned[player] = (earned[player] or 0) + coins
			end
		end)
		Players.PlayerRemoving:Connect(function(player)
			earned[player] = nil
		end)
		RoundService.StateChanged:Connect(function(stateName)
			if stateName == "Race" then
				table.clear(earned)
			elseif stateName == "Results" then
				for player, coins in earned do
					if player.Parent ~= nil and coins >= UpsellService.Param(ID, "MinCoins") then
						UpsellService.Offer(player, ID, { Coins = coins })
					end
				end
			end
		end)
	end,
}
