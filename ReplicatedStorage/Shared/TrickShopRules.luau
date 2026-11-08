-- TrickShopRules
-- Pure rules for buying, upgrading and equipping tricks (GDD 7.8, 7.10), shared by TrickService (decides) and the
-- future TricksUI (lists). Free tricks are owned by everyone; only Coins-tier tricks are sold for coins here, the
-- Robux tricks are granted by PurchaseService and the Reward and Seasonal ones by their own systems.
--
--   TrickShopRules.DecideBuy(trickId, context) -> ok, reason, price
--       context = { Owned = { [id] = true }, Coins = number }
--       reason: "Unknown" | "NotBuyable" | "Owned" | "NoFunds" (nil when ok). Checked in that order.
--   TrickShopRules.DecideUpgrade(trickId, context) -> ok, reason, price, newLevel
--       context = { Owned, Levels = { [id] = 1..3 }, Coins }
--       reason: "Unknown" | "NotOwned" | "MaxLevel" | "NoFunds"
--   TrickShopRules.DecideEquip(list, owned) -> slots?, reason?
--       list = array of up to Loadout.Slots ids ("" = empty slot). Returns the list padded with "" to full length.
--       reason: "Shape" | "Unknown" | "NotOwned" | "Duplicate"

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TrickRules = require(ReplicatedStorage.Shared.TrickRules)
local TrickTable = require(ReplicatedStorage.Tables.TrickTable)

local TrickShopRules = {}

local function levelOf(levels, trickId)
	local level = type(levels) == "table" and levels[trickId]
	if type(level) ~= "number" then
		return 1
	end
	return math.clamp(math.floor(level), 1, TrickTable.Scoring.MaxLevel)
end

function TrickShopRules.DecideBuy(trickId, context)
	local trick = type(trickId) == "string" and TrickTable.Tricks[trickId] or nil
	if not trick then
		return false, "Unknown", nil
	end
	if trick.Source ~= "Coins" or type(trick.Price) ~= "number" then
		return false, "NotBuyable", nil
	end
	if TrickRules.IsOwned(trickId, context.Owned) then
		return false, "Owned", nil
	end
	if context.Coins < trick.Price then
		return false, "NoFunds", trick.Price
	end
	return true, nil, trick.Price
end

function TrickShopRules.DecideUpgrade(trickId, context)
	local trick = type(trickId) == "string" and TrickTable.Tricks[trickId] or nil
	if not trick then
		return false, "Unknown", nil, nil
	end
	if not TrickRules.IsOwned(trickId, context.Owned) then
		return false, "NotOwned", nil, nil
	end
	local level = levelOf(context.Levels, trickId)
	if level >= TrickTable.Scoring.MaxLevel then
		return false, "MaxLevel", nil, nil
	end
	local newLevel = level + 1
	local price = TrickTable.Upgrades[trick.Tier]["L" .. newLevel]
	if context.Coins < price then
		return false, "NoFunds", price, newLevel
	end
	return true, nil, price, newLevel
end

function TrickShopRules.DecideEquip(list, owned)
	local slots = TrickTable.Loadout.Slots
	if type(list) ~= "table" then
		return nil, "Shape"
	end
	local count = #list
	if count > slots then
		return nil, "Shape"
	end
	local entries = 0
	for _ in list do
		entries += 1
	end
	if entries ~= count then
		return nil, "Shape"
	end

	local result = {}
	local seen = {}
	for slot = 1, slots do
		local trickId = list[slot]
		if trickId == nil or trickId == "" then
			result[slot] = ""
			continue
		end
		if type(trickId) ~= "string" then
			return nil, "Shape"
		end
		if not TrickTable.Tricks[trickId] then
			return nil, "Unknown"
		end
		if not TrickRules.IsOwned(trickId, owned) then
			return nil, "NotOwned"
		end
		if seen[trickId] then
			return nil, "Duplicate"
		end
		seen[trickId] = true
		result[slot] = trickId
	end
	return result, nil
end

return TrickShopRules
