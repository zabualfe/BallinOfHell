-- FallsThree: 3 falls on one segment (tools allowed there). Offers Shield x5 (Tool Refill) only while the player has
-- no Shield charges, else Skip Segment. The A/B test UpsellFallsThreeOrder only picks which comes first.
-- Contract: see UpsellService.

local ToolService = require(script.Parent.Parent.Parent.ToolService)
local FlagService = require(script.Parent.Parent.Parent.FlagService)
local FallsTrigger = require(script.Parent.Parent.FallsTrigger)

local SHIELD = "shield"
local TEST = "UpsellFallsThreeOrder"

return FallsTrigger.new("FallsThree", {
	Single = true,
	Targets = { ToolRefill = SHIELD },
	OfferOrder = function(player)
		local _, order = FlagService.GetState(player, TEST)
		return order
	end,
	Eligible = function(player, offerKey)
		if offerKey ~= "ToolRefill" then
			return nil
		end
		-- nil (not true) so UpsellService still runs the CanOffer check on the refill.
		if ToolService.GetCharges(player, SHIELD) == 0 then
			return nil
		end
		return false
	end,
})
