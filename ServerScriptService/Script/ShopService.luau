-- ShopService
-- Coin shop for balls (GDD 4, 9.3). Validate, then charge, then grant; a failed grant refunds.
--
-- Usage:
--   ShopService.GetCatalog() -> ordered array of { Id, Name, Rarity, Price, Source, Buyable, Exclusive }
--       Exclusives are listed with Buyable = false. Starter balls are Buyable but only after a starter was picked.
--   ShopService.BuyBall(player, ballId) -> boolean, reason?
--
-- Network (client -> server): BuyBall(ballId)            rate limited, see BUY_CAPACITY
-- Network (server -> owner):  BallPurchased(ballId)
--                             PurchaseFailed(reason)     "Unknown" | "NotBuyable" | "Owned" | "NoFunds" | "Failed"

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage.Network)
local ShopRules = require(ReplicatedStorage.Shared.ShopRules)
local BallTable = require(ReplicatedStorage.Tables.BallTable)

local AnalyticsService = require(script.Parent.AnalyticsService)
local EconomyService = require(script.Parent.EconomyService)
local InventoryService = require(script.Parent.InventoryService)
local PlayerData = require(script.Parent.PlayerData)

local ShopService = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local BUY_CAPACITY = 3 -- BuyBall burst
local BUY_REFILL = 0.5 -- BuyBall per second
local SINK = "Shop"

local catalog = ShopRules.Catalog(BallTable)

function ShopService.GetCatalog()
	return table.clone(catalog)
end

function ShopService.BuyBall(player, ballId)
	if not PlayerData.IsLoaded(player) then
		return false, "Failed"
	end

	local ok, reason, price = ShopRules.DecideBuy(ballId, {
		Owned = PlayerData.Peek(player, "ownedBalls") or {},
		Coins = EconomyService.GetCoins(player),
		HasPickedStarter = PlayerData.Peek(player, "hasPickedStarter") == true,
	}, BallTable)
	if not ok then
		return false, reason
	end

	if not EconomyService.SpendCoins(player, price, SINK, ballId) then
		return false, "NoFunds"
	end
	if not InventoryService.GrantBall(player, ballId, "Coins") then
		warn(("[ShopService] Grant of %s failed after charging %d; refunding"):format(ballId, price))
		EconomyService.AddCoins(player, price, "Refund", ballId)
		return false, "Failed"
	end

	AnalyticsService.Funnel(player, "Onboarding", "FirstShopPurchase")
	return true, nil
end

Network.OnEvent("BuyBall", function(player, ballId)
	if type(ballId) ~= "string" then
		return
	end
	local bought, reason = ShopService.BuyBall(player, ballId)
	if bought then
		Network.FireClient(player, "BallPurchased", ballId)
	else
		Network.FireClient(player, "PurchaseFailed", reason)
	end
end, { Capacity = BUY_CAPACITY, RefillPerSecond = BUY_REFILL })

return ShopService
