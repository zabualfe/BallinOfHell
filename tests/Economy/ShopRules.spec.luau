describe("ShopRules", function()
	local ShopRules = load("ReplicatedStorage/Shared/ShopRules")
	local BallTable = load("ReplicatedStorage/Tables/BallTable")

	local function context(overrides)
		local base = { Owned = {}, Coins = 100000, HasPickedStarter = true }
		for key, value in overrides or {} do
			base[key] = value
		end
		return base
	end

	local coinBallId
	for id, ball in BallTable do
		if ball.Source == "Coins" then
			coinBallId = id
			break
		end
	end

	it("buys a coin ball", function()
		local ok, reason, price = ShopRules.DecideBuy(coinBallId, context(), BallTable)
		expect(ok):equal(true)
		expect(reason):equal(nil)
		expect(price):equal(BallTable[coinBallId].Price)
	end)
	it("rejects non-string and unknown ids", function()
		expect(select(2, ShopRules.DecideBuy(5, context(), BallTable))):equal("Unknown")
		expect(select(2, ShopRules.DecideBuy("nope", context(), BallTable))):equal("Unknown")
	end)
	it("rejects owned balls", function()
		local owned = { [coinBallId] = { at = 1 } }
		expect(select(2, ShopRules.DecideBuy(coinBallId, context({ Owned = owned }), BallTable))):equal("Owned")
	end)
	it("rejects when the player can't afford it", function()
		local ok, reason = ShopRules.DecideBuy(coinBallId, context({ Coins = 0 }), BallTable)
		expect(ok):equal(false)
		expect(reason):equal("NoFunds")
	end)
	it("never sells exclusives for coins", function()
		for id, ball in BallTable do
			if ball.Source ~= "Coins" and ball.Source ~= "Starter" then
				expect(select(2, ShopRules.DecideBuy(id, context(), BallTable))):equal("NotBuyable")
			end
		end
	end)
	it("sells an un-picked starter only after the pick", function()
		expect(select(1, ShopRules.DecideBuy("grip", context(), BallTable))):equal(true)
		local before = context({ HasPickedStarter = false })
		expect(select(2, ShopRules.DecideBuy("grip", before, BallTable))):equal("NotBuyable")
	end)
	it("lists every ball in order with exclusives marked unbuyable", function()
		local catalog = ShopRules.Catalog(BallTable)
		local count = 0
		for _ in BallTable do
			count += 1
		end
		expect(#catalog):equal(count)
		for index = 2, #catalog do
			expect(BallTable[catalog[index - 1].Id].Order <= BallTable[catalog[index].Id].Order):truthy()
		end
		for _, entry in catalog do
			expect(entry.Buyable):equal(
				BallTable[entry.Id].Source == "Coins" or BallTable[entry.Id].Source == "Starter"
			)
			expect(entry.Exclusive):equal(not entry.Buyable)
		end
	end)
end)
