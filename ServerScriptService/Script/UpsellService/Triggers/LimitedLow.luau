-- LimitedLow: Crown of Hell stock under Below. A server-wide toast, at most once per ToastIntervalSeconds per server,
-- never a per-player popup. LimitedBallService publishes the workspace attribute LimitedRemaining; this reads it, so
-- there is no hard dependency on that module. Contract: see UpsellService.

local FlagService = require(script.Parent.Parent.Parent.FlagService)
local Rules = require(script.Parent.Parent.UpsellRules)

local ID = "LimitedLow"
local REMAINING_ATTRIBUTE = "LimitedRemaining"

local lastToastAt = nil -- os.clock() of the last toast on this server

return {
	Id = ID,
	Start = function() end,
	ServerTick = function(UpsellService)
		if FlagService.Get("UpsellEnabled_" .. ID) ~= true then
			return
		end
		local remaining = workspace:GetAttribute(REMAINING_ATTRIBUTE)
		local now = os.clock()
		local interval = UpsellService.Param(ID, "ToastIntervalSeconds")
		if
			type(remaining) ~= "number"
			or not Rules.ToastDue(remaining, UpsellService.Param(ID, "Below"), lastToastAt, now, interval)
		then
			return
		end
		lastToastAt = now
		UpsellService.Toast(("Only %d Crown of Hell left!"):format(remaining))
	end,
}
