describe("DailyRewardService.Rules", function()
	local Rules = load("ServerScriptService/Script/DailyRewardService/Rules")
	local DailyRewardTable = load("ReplicatedStorage/Tables/DailyRewardTable")
	local EconomyTable = load("ReplicatedStorage/Tables/EconomyTable")
	local config = DailyRewardTable.Config
	local TODAY = 20000

	it("derives UTC days from server time", function()
		expect(Rules.DayNumber(0)):equal(0)
		expect(Rules.DayNumber(86399.9)):equal(0)
		expect(Rules.DayNumber(86400)):equal(1)
		expect(Rules.DayNumber(TODAY * 86400 + 5)):equal(TODAY)
	end)

	it("lets a new player claim day 1", function()
		local status = Rules.Status(-1, 0, TODAY, config)
		expect(status.CanClaim):truthy()
		expect(status.NextDay):equal(1)
		expect(status.CanRestore):falsy()
	end)

	it("rejects a second claim on the same UTC day", function()
		expect(Rules.Status(TODAY, 3, TODAY, config).CanClaim):falsy()
	end)

	it("continues the streak on the next day", function()
		local status = Rules.Status(TODAY - 1, 3, TODAY, config)
		expect(status.CanClaim):truthy()
		expect(status.NextDay):equal(4)
		expect(status.CanRestore):falsy()
	end)

	it("wraps to day 1 after day 7", function()
		expect(Rules.Status(TODAY - 1, 7, TODAY, config).NextDay):equal(1)
	end)

	it("resets to day 1 after a miss and offers Restore inside the 48 h window", function()
		for _, gap in { 2, 3 } do
			local status = Rules.Status(TODAY - gap, 5, TODAY, config)
			expect(status.NextDay):equal(1)
			expect(status.CanRestore):truthy()
		end
	end)

	it("offers no Restore at gap 4+ and resets", function()
		local status = Rules.Status(TODAY - 4, 5, TODAY, config)
		expect(status.NextDay):equal(1)
		expect(status.CanRestore):falsy()
	end)

	it("restores to yesterday and is then idempotent", function()
		local restored = Rules.RestoredLastDay(TODAY - 2, 5, TODAY, config)
		expect(restored):equal(TODAY - 1)
		local after = Rules.Status(restored, 5, TODAY, config)
		expect(after.NextDay):equal(6)
		expect(after.CanRestore):falsy()
		expect(Rules.RestoredLastDay(restored, 5, TODAY, config)):equal(nil)
	end)

	it("does not restore outside the window", function()
		expect(Rules.RestoredLastDay(TODAY - 4, 5, TODAY, config)):equal(nil)
		expect(Rules.RestoredLastDay(TODAY - 2, 0, TODAY, config)):equal(nil)
	end)

	describe("DailyCoins", function()
		it("adds the pass and VIP bonuses (x2.5 together)", function()
			expect(Rules.DailyCoins(50, false, false, EconomyTable)):equal(50)
			expect(Rules.DailyCoins(50, true, false, EconomyTable)):equal(100)
			expect(Rules.DailyCoins(50, false, true, EconomyTable)):equal(75)
			expect(Rules.DailyCoins(50, true, true, EconomyTable)):equal(125)
			expect(Rules.DailyCoins(500, true, true, EconomyTable)):equal(1250)
		end)
	end)

	describe("BuildEntry", function()
		local day7 = DailyRewardTable.Days[7]

		it("includes the ball while it is not owned", function()
			local entry = Rules.BuildEntry(day7, false, false)
			expect(entry.FirstTimeBall):equal("emberglow")
			expect(entry.Coins):equal(500)
			expect(entry.Spins):equal(3)
			expect(entry.Day):equal(nil)
		end)

		it("drops the ball once owned (later cycles)", function()
			local entry = Rules.BuildEntry(day7, false, true)
			expect(entry.FirstTimeBall):equal(nil)
			expect(entry.Coins):equal(500)
		end)

		it("pays VIP coins as final coins and leaves the Table untouched", function()
			local entry = Rules.BuildEntry(day7, true, true, false, EconomyTable)
			expect(entry.FinalCoins):equal(750)
			expect(entry.Coins):equal(nil)
			expect(entry.VipCoins):equal(nil)
			expect(day7.Coins):equal(500)
		end)

		it("adds VIP and the 2x pass: day 1 pays 125, not 150", function()
			local entry = Rules.BuildEntry(DailyRewardTable.Days[1], true, false, true, EconomyTable)
			expect(entry.FinalCoins):equal(125)
			expect(Rules.BuildEntry(DailyRewardTable.Days[1], false, false, true, EconomyTable).Coins):equal(50)
		end)

		it("copies nested tables", function()
			local entry = Rules.BuildEntry(DailyRewardTable.Days[3], false, false)
			entry.ToolCharges.rocket = 99
			expect(DailyRewardTable.Days[3].ToolCharges.rocket):equal(3)
		end)

		it("keeps non-coin days unchanged for VIP", function()
			local entry = Rules.BuildEntry(DailyRewardTable.Days[2], true, false, true, EconomyTable)
			expect(entry.Spins):equal(1)
			expect(entry.Coins):equal(nil)
			expect(entry.FinalCoins):equal(nil)
		end)
	end)
end)
