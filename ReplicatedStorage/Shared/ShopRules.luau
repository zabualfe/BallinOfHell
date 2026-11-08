-- ShopRules
-- Pure coin-shop rules for balls (GDD 4, 9.3), shared by ShopService (decides) and the shop UI (lists).
--
--   ShopRules.IsBuyable(ball, hasPickedStarter) -> boolean
--       Coins-source balls always; Starter balls only once a starter was picked (the un-picked ones are sold for
--       coins, GDD 9.3). Exclusives (Wheel, Daily, Seasonal, ...) never.
--   ShopRules.DecideBuy(ballId, context, ballTable) -> ok, reason, price
--       context = { Owned = { [ballId] = ... }, Coins = number, HasPickedStarter = boolean }
--       reason: "Unknown" | "NotBuyable" | "Owned" | "NoFunds" (nil when ok). Checked in that order.
--   ShopRules.Catalog(ballTable) -> ordered array of { Id, Name, Rarity, Price, Source, Buyable, Exclusive }
--       Buyable ignores the player (Source Coins/Starter with a Price); exclusives are listed with Buyable = false.

local ShopRules = {}

function ShopRules.IsBuyable(ball, hasPickedStarter)
	if type(ball) ~= "table" or type(ball.Price) ~= "number" then
		return false
	end
	if ball.Source == "Coins" then
		return true
	end
	return ball.Source == "Starter" and hasPickedStarter == true
end

function ShopRules.DecideBuy(ballId, context, ballTable)
	local ball = type(ballId) == "string" and ballTable[ballId] or nil
	if not ball then
		return false, "Unknown", nil
	end
	if not ShopRules.IsBuyable(ball, context.HasPickedStarter) then
		return false, "NotBuyable", nil
	end
	if context.Owned[ballId] ~= nil then
		return false, "Owned", nil
	end
	if context.Coins < ball.Price then
		return false, "NoFunds", ball.Price
	end
	return true, nil, ball.Price
end

function ShopRules.Catalog(ballTable)
	local entries = {}
	for id, ball in ballTable do
		table.insert(entries, {
			Id = id,
			Name = ball.Name,
			Rarity = ball.Rarity,
			Price = ball.Price,
			Source = ball.Source,
			Buyable = type(ball.Price) == "number" and (ball.Source == "Coins" or ball.Source == "Starter"),
			Exclusive = ball.Source ~= "Coins" and ball.Source ~= "Starter",
			_order = ball.Order or math.huge,
		})
	end
	table.sort(entries, function(a, b)
		if a._order ~= b._order then
			return a._order < b._order
		end
		return a.Id < b.Id
	end)
	for _, entry in entries do
		entry._order = nil
	end
	return entries
end

return ShopRules
