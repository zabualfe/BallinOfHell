-- Products/Boosts
-- Family "Offers", boost products only: 2x Coins for BoostMinutes (ProductTable Params). The remaining Offers
-- (StarterPack, CrownOfHell, RestoreDailyStreak, UnlockAllTimedGifts) belong to their own tasks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyTable = require(ReplicatedStorage.Tables.EconomyTable)
local ProductTable = require(ReplicatedStorage.Tables.ProductTable)

local EconomyService = require(script.Parent.Parent.Parent.EconomyService)

local BOOST_ID = "coins2x" -- key in saved `boosts`
local BANK_CAP_SECONDS = EconomyTable.Boost.Coins2xBankCapMinutes * 60
local BOOST_KEYS = { "Coins2xThirtyMinutes" }

local Boosts = { Products = {} }

for _, key in BOOST_KEYS do
	local row = ProductTable[key]
	local minutes = row and row.Params and row.Params.BoostMinutes
	if type(minutes) ~= "number" or minutes <= 0 then
		warn(`[PurchaseService] {key} has no positive Params.BoostMinutes`)
		continue
	end
	Boosts.Products[key] = {
		-- Refuse before the prompt: a purchase past the bank cap would be paid for and then lost.
		CanPrompt = function(player)
			return EconomyService.GetBoostSeconds(player, BOOST_ID) < BANK_CAP_SECONDS
		end,
		Effect = function(player)
			return EconomyService.AddBoost(player, BOOST_ID, minutes * 60) == true
		end,
	}
end

return Boosts
