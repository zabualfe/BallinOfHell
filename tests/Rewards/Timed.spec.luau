describe("TimedRewardService.Rules", function()
	local Rules = load("ServerScriptService/Script/TimedRewardService/Rules")
	local gifts = load("ReplicatedStorage/Tables/TimedRewardTable").Gifts
	local MINUTES = { 2, 5, 10, 15, 20, 30, 45, 60 }

	it("unlocks each gift exactly at its minute", function()
		for index, minute in MINUTES do
			expect(gifts[index].Minute):equal(minute)
			expect(Rules.IsUnlocked(gifts[index], minute * 60 - 1)):falsy()
			expect(Rules.IsUnlocked(gifts[index], minute * 60)):truthy()
		end
	end)

	it("validates the index, unlock and claimed state", function()
		expect(Rules.CanClaim(gifts, 1, 120, {})):truthy()
		expect(Rules.CanClaim(gifts, 2, 120, {})):falsy()
		expect(Rules.CanClaim(gifts, 1, 120, { [1] = true })):falsy()
		expect(Rules.CanClaim(gifts, 0, 9999, {})):falsy()
		expect(Rules.CanClaim(gifts, 9, 9999, {})):falsy()
		expect(Rules.CanClaim(gifts, 1.5, 9999, {})):falsy()
		expect(Rules.CanClaim(gifts, "1", 9999, {})):falsy()
		expect(Rules.CanClaim(gifts, nil, 9999, {})):falsy()
	end)

	it("lists remaining unlocked gifts and counts them", function()
		expect(Rules.Remaining(gifts, 600, { [1] = true })):equal({ 2, 3 })
		expect(Rules.WaitingCount(gifts, 3600, {})):equal(8)
		expect(Rules.WaitingCount(gifts, 3600, { [8] = true })):equal(7)
		expect(Rules.WaitingCount(gifts, 0, {})):equal(0)
	end)

	it("encodes claimed gifts as a bitmask", function()
		expect(Rules.Mask({}, 8)):equal(0)
		expect(Rules.Mask({ [1] = true, [3] = true, [8] = true }, 8)):equal(1 + 4 + 128)
	end)

	describe("BuildEntry", function()
		it("gives the exclusive ball the first time", function()
			local entry = Rules.BuildEntry(gifts[8], {})
			expect(entry.OnceEverBall):equal("hellfirekick")
			expect(entry.Minute):equal(nil)
		end)

		it("pays the Table fallback once the ball was claimed", function()
			local entry = Rules.BuildEntry(gifts[8], { hellfirekick = true })
			expect(entry.OnceEverBall):equal(nil)
			expect(entry.Coins):equal(300)
			expect(entry.Spins):equal(2)
		end)

		it("passes ordinary gifts through without the Minute field", function()
			local entry = Rules.BuildEntry(gifts[6], {})
			expect(entry.Coins):equal(100)
			expect(entry.Spins):equal(1)
			expect(entry.ToolCharges.shield):equal(2)
			expect(entry.Minute):equal(nil)
		end)
	end)

	it("Unlock All claims every remaining gift regardless of playtime", function()
		local claimed = { [1] = true, [4] = true }
		local remaining = {}
		for index in gifts do
			if not claimed[index] then
				table.insert(remaining, index)
			end
		end
		expect(#remaining):equal(6)
	end)

	describe("GrantedBall", function()
		it("finds the ball in a (possibly partial) summary", function()
			local summary = { { Kind = "Coins", Amount = 5 }, { Kind = "Ball", Amount = 1, Id = "hellfirekick" } }
			expect(Rules.GrantedBall(summary, "hellfirekick")):truthy()
			expect(Rules.GrantedBall(summary, "emberglow")):falsy()
			expect(Rules.GrantedBall({}, "hellfirekick")):falsy()
		end)
	end)
end)
