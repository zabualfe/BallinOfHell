-- WheelNoSpins: the wheel was opened with nothing to spin. The client reports WheelOpened(); the server re-checks the
-- banked spins and the free spin itself. Paid-random restriction is enforced by UpsellService (RequiresPaidRandomAllowed).
-- Contract: see UpsellService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage.Network)

local PlayerData = require(script.Parent.Parent.Parent.PlayerData)
local SpinWheelService = require(script.Parent.Parent.Parent.SpinWheelService)

local ID = "WheelNoSpins"
local OPEN_RATE = { Capacity = 2, RefillPerSecond = 0.2 } -- WheelOpened burst / per second

return {
	Id = ID,
	Start = function(UpsellService)
		Network.OnEvent("WheelOpened", function(player)
			if not PlayerData.IsLoaded(player) or (PlayerData.Peek(player, "spins") or 0) > 0 then
				return
			end
			if SpinWheelService.GetFreeSpinStatus(player) then
				return
			end
			UpsellService.Offer(player, ID, {})
		end, OPEN_RATE)
	end,
}
