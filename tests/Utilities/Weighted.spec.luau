describe("Weighted", function()
	local Weighted = load("ReplicatedStorage/Utilities/Weighted")

	it("matches the weight distribution over 100k seeded picks", function()
		local random = Random.new(1234)
		local list = { { Weight = 1, Id = "a" }, { Weight = 3, Id = "b" }, { Weight = 6, Id = "c" } }
		local counts = { a = 0, b = 0, c = 0 }
		local picks = 100000
		for _ = 1, picks do
			local entry = Weighted.Pick(list, random)
			counts[entry.Id] += 1
		end
		expect(counts.a / picks):near(0.1, 0.01)
		expect(counts.b / picks):near(0.3, 0.01)
		expect(counts.c / picks):near(0.6, 0.01)
	end)

	it("returns nil for an empty list or zero total", function()
		local random = Random.new(1)
		expect(Weighted.Pick({}, random)):equal(nil)
		expect(Weighted.Pick({ { Weight = 0 }, { Weight = -2 } }, random)):equal(nil)
		expect(Weighted.PickKey({}, random)):equal(nil)
	end)

	it("never picks zero-weight entries", function()
		local random = Random.new(7)
		local list = { { Weight = 0, Id = "no" }, { Weight = 1, Id = "yes" } }
		for _ = 1, 1000 do
			expect(Weighted.Pick(list, random).Id):equal("yes")
		end
	end)

	it("picks from a map and returns key and entry", function()
		local random = Random.new(99)
		local map = { common = { Weight = 9 }, rare = { Weight = 1 } }
		local rare = 0
		for _ = 1, 20000 do
			local key, entry = Weighted.PickKey(map, random)
			expect(entry):equal(map[key])
			if key == "rare" then
				rare += 1
			end
		end
		expect(rare / 20000):near(0.1, 0.01)
	end)
end)
