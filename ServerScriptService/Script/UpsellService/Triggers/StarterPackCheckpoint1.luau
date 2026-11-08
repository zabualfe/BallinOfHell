-- StarterPackCheckpoint1: first checkpoint of the first session while the Starter Pack is live. UpsellService owns
-- the popup; StarterPackService only signals PopupDue, so it is never shown twice. Exempt from the quiet first session.
-- Contract: see UpsellService.

local PlayerData = require(script.Parent.Parent.Parent.PlayerData)
local StarterPackService = require(script.Parent.Parent.Parent.StarterPackService)

local ID = "StarterPackCheckpoint1"
local FIRST_SESSION = 1

return {
	Id = ID,
	QuietExempt = true,
	Start = function(UpsellService)
		StarterPackService.PopupDue:Connect(function(player, reason)
			if reason ~= "Checkpoint" then
				return
			end
			if PlayerData.Peek(player, "sessionCount") ~= FIRST_SESSION then
				StarterPackService.MarkShown(player, reason) -- nothing to show this session; stop retrying
				return
			end
			if UpsellService.Offer(player, ID, { Reason = reason }) then
				StarterPackService.MarkShown(player, reason)
			end
		end)
	end,
}
