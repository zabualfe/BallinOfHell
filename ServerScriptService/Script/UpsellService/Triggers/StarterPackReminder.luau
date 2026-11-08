-- StarterPackReminder: Starter Pack has SecondsLeft left (StarterPackService decides when and signals PopupDue).
-- Contract: see UpsellService.

local StarterPackService = require(script.Parent.Parent.Parent.StarterPackService)

local ID = "StarterPackReminder"

return {
	Id = ID,
	Start = function(UpsellService)
		StarterPackService.PopupDue:Connect(function(player, reason)
			if reason == "Reminder" and UpsellService.Offer(player, ID, { Reason = reason }) then
				StarterPackService.MarkShown(player, reason)
			end
		end)
	end,
}
