describe("WheelRules", function()
	local WheelRules = load("ReplicatedStorage/Shared/WheelRules")
	local WheelTable = load("ReplicatedStorage/Tables/WheelTable")

	it("rolls each slice within 0.5 percentage points of its weight over 100k rolls", function()
		local random = Random.new(20261107)
		local counts = {}
		local rolls = 100000
		for _ = 1, rolls do
			local index = WheelRules.Roll(WheelTable.Slices, random)
			counts[index] = (counts[index] or 0) + 1
		end
		for index, slice in WheelTable.Slices do
			local measured = (counts[index] or 0) / rolls * 100
			expect(math.abs(measured - slice.Weight) <= 0.5):truthy()
		end
	end)

	it("has weights summing to 100 and odds that match the table", function()
		local odds = WheelRules.Odds(WheelTable.Slices)
		local total = 0
		for index, row in odds do
			total += row.Percent
			expect(row.Weight):equal(WheelTable.Slices[index].Weight)
			expect(row.Percent):near(WheelTable.Slices[index].Weight, 1e-9)
			expect(#row.Rewards > 0):truthy()
		end
		expect(total):near(100, 1e-9)
		expect(#odds):equal(8)
	end)

	it("returns nil for an empty wheel", function()
		expect(WheelRules.Roll({}, Random.new(1))):equal(nil)
	end)

	describe("free spin accrual", function()
		local config = WheelTable.Config
		local interval = WheelRules.FreeInterval(config, false)

		it("uses 8 h, or 4 h with Lucky", function()
			expect(interval):equal(8 * 3600)
			expect(WheelRules.FreeInterval(config, true)):equal(4 * 3600)
		end)

		it("is ready for a player who never spun", function()
			local ready = WheelRules.FreeStatus(1000, 0, interval)
			expect(ready):equal(true)
		end)

		it("counts down from the last claim", function()
			local ready, left, nextAt = WheelRules.FreeStatus(10000 + 3600, 10000, interval)
			expect(ready):equal(false)
			expect(left):equal(interval - 3600)
			expect(nextAt):equal(10000 + interval)
		end)

		it("is ready exactly at the interval", function()
			expect((WheelRules.FreeStatus(10000 + interval, 10000, interval))):equal(true)
			expect((WheelRules.FreeStatus(10000 + interval - 1, 10000, interval))):equal(false)
		end)

		it("does not bank: waiting longer still gives one", function()
			local ready, left = WheelRules.FreeStatus(10000 + interval * 5, 10000, interval)
			expect(ready):equal(true)
			expect(left):equal(0)
		end)

		it("Lucky shortens a running timer", function()
			local lucky = WheelRules.FreeInterval(config, true)
			expect((WheelRules.FreeStatus(10000 + lucky, 10000, lucky))):equal(true)
		end)

		it("never locks longer than one interval after a clock rewind", function()
			local ready, left = WheelRules.FreeStatus(1000, 999999, interval)
			expect(ready):equal(false)
			expect(left <= interval):truthy()
		end)

		it("gives VIP one spin per UTC day", function()
			local day = WheelRules.DayOf(86400 * 20 + 5)
			expect(day):equal(20)
			expect(WheelRules.VipSpinDue(day, -1)):equal(true)
			expect(WheelRules.VipSpinDue(day, 19)):equal(true)
			expect(WheelRules.VipSpinDue(day, 20)):equal(false)
		end)
	end)
end)
