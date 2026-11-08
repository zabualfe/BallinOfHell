-- Products/Skips
-- Family "Progress", skip products only (Skip Segment, Skip 5 Segments; ProductTable Params.Segments).
-- RespawnHere belongs to its own task. CanPrompt needs a racing player who can still skip that far (never onto
-- or past the finish). Effect re-checks at receipt; if the skip is no longer possible the player gets
-- `skipTokens` instead, so a paid product never loops in retry.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CourseTable = require(ReplicatedStorage.Tables.CourseTable)
local ProductTable = require(ReplicatedStorage.Tables.ProductTable)

local CourseService = require(script.Parent.Parent.Parent.CourseService)
local PlayerData = require(script.Parent.Parent.Parent.PlayerData)
local ProgressService = require(script.Parent.Parent.Parent.ProgressService)
local BuyRules = require(script.Parent.Parent.BuyRules)

local SKIP_KEYS = { "SkipSegment", "SkipFiveSegments" }

local function isNoSkip(index)
	local checkpoint = CourseService.GetCheckpoint(index)
	local tier = checkpoint and CourseTable.Tiers[checkpoint.Tier]
	return tier ~= nil and tier.NoSkips == true
end

local function skipTarget(player, count)
	return BuyRules.SkipTarget(ProgressService.GetState(player), CourseService.GetSegmentCount(), count, isNoSkip)
end

local Skips = { Products = {} }

for _, key in SKIP_KEYS do
	local row = ProductTable[key]
	local count = row and row.Params and row.Params.Segments
	if type(count) ~= "number" or count <= 0 then
		warn(`[PurchaseService] {key} has no positive Params.Segments`)
		continue
	end
	Skips.Products[key] = {
		CanPrompt = function(player)
			return skipTarget(player, count) ~= nil
		end,
		Effect = function(player)
			local target = skipTarget(player, count)
			if target and ProgressService.SkipTo(player, target, "Purchase") then
				return true
			end
			return PlayerData.Set(player, "skipTokens", PlayerData.Get(player, "skipTokens") + count)
		end,
	}
end

return Skips
