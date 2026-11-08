-- TrickPremiumPreview: the first airtime of the session where a premium trick would have scored at least
-- MinExtraFraction more. The client re-plans with Comet Corkscrew and reports TrickPremiumWouldScore(extraFraction,
-- extraPoints). The numbers are untrusted but only gate a capped, toast-sized offer for that same player.
-- Contract: see UpsellService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage.Network)

local PlayerData = require(script.Parent.Parent.Parent.PlayerData)

local ID = "TrickPremiumPreview"
local REPORT_RATE = { Capacity = 2, RefillPerSecond = 0.1 } -- burst / per second
local MAX_EXTRA_POINTS = 100000

return {
	Id = ID,
	Start = function(UpsellService)
		Network.OnEvent("TrickPremiumWouldScore", function(player, extraFraction, extraPoints)
			if type(extraFraction) ~= "number" or type(extraPoints) ~= "number" or extraFraction ~= extraFraction then
				return
			end
			if extraPoints < 1 or extraPoints > MAX_EXTRA_POINTS or not PlayerData.IsLoaded(player) then
				return
			end
			if extraFraction < UpsellService.Param(ID, "MinExtraFraction") then
				return
			end
			local trickId = UpsellService.Param(ID, "ReplanTrickId")
			if (PlayerData.Peek(player, "ownedTricks") or {})[trickId] ~= nil then
				return
			end
			UpsellService.Offer(player, ID, { ExtraPoints = math.floor(extraPoints), TrickId = trickId })
		end, REPORT_RATE)
	end,
}
