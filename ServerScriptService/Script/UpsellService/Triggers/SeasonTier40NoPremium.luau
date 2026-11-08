-- SeasonTier40NoPremium: a non-premium player reaches the last season tier. The popup previews the premium ball
-- (UpsellTable Preview) and every premium reward. Contract: see UpsellService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UpsellTable = require(ReplicatedStorage.Tables.UpsellTable)
local SeasonService = require(script.Parent.Parent.Parent.SeasonService)

local ID = "SeasonTier40NoPremium"

local preview
for _, row in UpsellTable.Triggers do
	if row.Id == ID then
		preview = row.Preview
	end
end

return {
	Id = ID,
	Start = function(UpsellService)
		SeasonService.TierReached:Connect(function(player, tier)
			local snapshot = SeasonService.GetSnapshot(player)
			if snapshot and snapshot.Active and tier >= snapshot.MaxTier and not snapshot.HasPremium then
				UpsellService.Offer(player, ID, { Tier = tier, Preview = preview })
			end
		end)
	end,
}
