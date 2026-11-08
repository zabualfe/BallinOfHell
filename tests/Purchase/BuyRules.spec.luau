describe("PurchaseService.BuyRules", function()
	local BuyRules = load("ServerScriptService/Script/PurchaseService/BuyRules")
	local BallTable = load("ReplicatedStorage/Tables/BallTable")

	local function firstBall(predicate)
		local ids = {}
		for id, ball in BallTable do
			if predicate(ball) then
				table.insert(ids, id)
			end
		end
		table.sort(ids)
		return ids[1]
	end

	describe("BallPurchasable", function()
		local shopId = firstBall(function(ball)
			return ball.Source == "Coins" and ball.Exclusive ~= true
		end)
		local exclusiveId = firstBall(function(ball)
			return ball.Source ~= "Coins" and ball.Source ~= "Starter"
		end)

		it("accepts an unowned shop ball of the right rarity", function()
			expect(BuyRules.BallPurchasable(shopId, BallTable[shopId].Rarity, {})):truthy()
		end)

		it("rejects unknown ids, wrong rarity, owned and exclusive balls", function()
			expect(select(2, BuyRules.BallPurchasable("nope", "Rare", {}))):equal("Unknown")
			expect(select(2, BuyRules.BallPurchasable(5, "Rare", {}))):equal("Unknown")
			expect(select(2, BuyRules.BallPurchasable(shopId, "NotARarity", {}))):equal("WrongRarity")
			expect(select(2, BuyRules.BallPurchasable(shopId, BallTable[shopId].Rarity, { [shopId] = {} }))):equal(
				"Owned"
			)
			expect(select(2, BuyRules.BallPurchasable(exclusiveId, BallTable[exclusiveId].Rarity, {}))):equal(
				"Exclusive"
			)
		end)
	end)

	describe("SkipTarget", function()
		local function state(overrides)
			local base = { Racing = true, Finished = false, Checkpoint = 3 }
			for key, value in overrides or {} do
				base[key] = value
			end
			return base
		end

		it("returns current + count when racing and clear of the finish", function()
			expect(BuyRules.SkipTarget(state(), 30, 1)):equal(4)
			expect(BuyRules.SkipTarget(state(), 30, 5)):equal(8)
		end)

		it("refuses when not racing or finished", function()
			expect(select(2, BuyRules.SkipTarget(nil, 30, 1))):equal("NotRacing")
			expect(select(2, BuyRules.SkipTarget(state({ Racing = false }), 30, 1))):equal("NotRacing")
			expect(select(2, BuyRules.SkipTarget(state({ Finished = true }), 30, 1))):equal("Finished")
		end)

		it("refuses to reach or pass the finish", function()
			expect(select(2, BuyRules.SkipTarget(state({ Checkpoint = 28 }), 30, 5))):equal("FinishLocked")
			expect(select(2, BuyRules.SkipTarget(state({ Checkpoint = 29 }), 30, 1))):equal("FinishLocked")
			expect(BuyRules.SkipTarget(state({ Checkpoint = 28 }), 30, 1)):equal(29)
		end)

		it("refuses across a NoSkips tier", function()
			local isNoSkip = function(index)
				return index == 5
			end
			expect(select(2, BuyRules.SkipTarget(state(), 30, 5, isNoSkip))):equal("NoSkipTier")
			expect(BuyRules.SkipTarget(state(), 30, 1, isNoSkip)):equal(4)
		end)
	end)
end)
