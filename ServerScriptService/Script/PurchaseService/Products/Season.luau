-- Products/Season
-- Family "Season": Premium Pass, Premium+, Buy a Tier, Buy 10 Tiers and the Season Ending offer (SeasonTable.Seasons
-- Products lists which are sold). SeasonService owns every rule: CanPrompt asks it whether the product may be offered
-- (never in the last hour of the season, never past the tier caps) and Effect applies the receipt, so the grant happens
-- in ProcessReceipt only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProductTable = require(ReplicatedStorage.Tables.ProductTable)

local SeasonService = require(script.Parent.Parent.Parent.SeasonService)

local FAMILY = "Season"

local Season = { Products = {} }

for key, row in ProductTable do
	if row.Family ~= FAMILY then
		continue
	end
	Season.Products[key] = {
		CanPrompt = function(player)
			return SeasonService.CanOfferProduct(player, key)
		end,
		Effect = function(player)
			return SeasonService.GrantProduct(player, key)
		end,
	}
end

return Season
