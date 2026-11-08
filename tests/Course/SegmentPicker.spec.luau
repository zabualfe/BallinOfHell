describe("SegmentPicker", function()
	local SegmentPicker = load("ServerScriptService/Script/CourseService/SegmentPicker")
	local CourseTable = load("ReplicatedStorage/Tables/CourseTable")

	local function makePool(sizes, extra)
		local pool = {}
		for tier, size in sizes do
			pool[tier] = {}
			for i = 1, size do
				table.insert(pool[tier], { Name = tier .. i, Weight = 1 + (i % 3) * 0.5 })
			end
		end
		for tier, list in extra or {} do
			pool[tier] = list
		end
		return pool
	end

	local function countDuplicates(picks)
		local seen, duplicates = {}, 0
		for _, name in picks do
			if seen[name] then
				duplicates += 1
			end
			seen[name] = true
		end
		return duplicates
	end

	it("never repeats while every tier pool is big enough", function()
		local pool = makePool({
			Beginner = 6,
			Easy = 7,
			Medium = 8,
			Hard = 8,
			Insane = 8,
			Hell = 5,
			Finale = 3,
		})
		for seed = 1, 50 do
			local picks = SegmentPicker.Pick(pool, CourseTable.Slots, Random.new(seed))
			expect(#picks):equal(30)
			expect(countDuplicates(picks)):equal(0)
		end
	end)

	it("has no adjacent duplicates with the 20-segment prototype pool", function()
		local pool = makePool(CourseTable.Picker.PoolSize.Prototype)
		for seed = 1, 100 do
			local picks = SegmentPicker.Pick(pool, CourseTable.Slots, Random.new(seed))
			expect(#picks):equal(30)
			for slot = 2, 30 do
				-- Finale has one segment and one slot, so only slots 1-29 can collide.
				expect(picks[slot] ~= picks[slot - 1]):truthy()
			end
		end
	end)

	it("keeps each pick inside its slot's tier", function()
		local pool = makePool(CourseTable.Picker.PoolSize.Prototype)
		local picks, sources = SegmentPicker.Pick(pool, CourseTable.Slots, Random.new(5))
		for slot, name in picks do
			expect(sources[slot]):equal(CourseTable.Slots[slot])
			expect(name:sub(1, #sources[slot])):equal(sources[slot])
		end
	end)

	it("is deterministic for a seed and differs across seeds", function()
		local pool = makePool(CourseTable.Picker.PoolSize.Launch)
		local a = SegmentPicker.Pick(pool, CourseTable.Slots, Random.new(99))
		local b = SegmentPicker.Pick(pool, CourseTable.Slots, Random.new(99))
		local c = SegmentPicker.Pick(pool, CourseTable.Slots, Random.new(100))
		expect(a):equal(b)
		expect(table.concat(a, ",") ~= table.concat(c, ",")):truthy()
	end)

	it("avoids last round's pick per slot when it can", function()
		local pool = makePool(CourseTable.Picker.PoolSize.Launch)
		local first = SegmentPicker.Pick(pool, CourseTable.Slots, Random.new(3))
		for seed = 1, 20 do
			local second = SegmentPicker.Pick(pool, CourseTable.Slots, Random.new(seed), first)
			for slot = 1, 30 do
				expect(second[slot] ~= first[slot]):truthy()
			end
		end
	end)

	it("falls back to the nearest tier when one is empty", function()
		local pool = makePool(CourseTable.Picker.PoolSize.Prototype)
		pool.Hell = {}
		local picks, sources, notes = SegmentPicker.Pick(pool, CourseTable.Slots, Random.new(8))
		expect(#picks):equal(30)
		expect(sources[28]):equal("Insane")
		expect(sources[29]):equal("Insane")
		expect(#notes > 0):truthy()
		expect(picks[28] ~= picks[29]):truthy()
	end)

	it("returns nil with notes when every tier is empty", function()
		local picks, sources, notes = SegmentPicker.Pick({ Beginner = {} }, CourseTable.Slots, Random.new(1))
		expect(picks):equal(nil)
		expect(sources):equal(nil)
		expect(#notes > 0):truthy()
	end)

	it("allows an adjacent repeat only when a tier has a single segment", function()
		local pool = { Beginner = { { Name = "Only" } } }
		local picks, _, notes = SegmentPicker.Pick(pool, { "Beginner", "Beginner" }, Random.new(1))
		expect(picks):equal({ "Only", "Only" })
		expect(#notes > 0):truthy()
	end)

	it("caps ToolRequired segments and keeps them apart", function()
		local list = {}
		for i = 1, 12 do
			table.insert(list, { Name = "M" .. i, ToolRequired = i <= 8 })
		end
		for seed = 1, 50 do
			local picks = SegmentPicker.Pick(
				{ Medium = list },
				{ "Medium", "Medium", "Medium", "Medium", "Medium", "Medium" },
				Random.new(seed)
			)
			local tools, previousTool = 0, false
			for _, name in picks do
				local isTool = tonumber(name:sub(2)) <= 8
				if isTool then
					tools += 1
					expect(previousTool):falsy()
				end
				previousTool = isTool
			end
			expect(tools <= CourseTable.Picker.MaxToolRequiredPerCourse):truthy()
		end
	end)
end)
