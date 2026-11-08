describe("TokenBucket", function()
	local TokenBucket = load("ReplicatedStorage/Utilities/TokenBucket")

	local function makeClock()
		local state = { now = 0 }
		return state, function()
			return state.now
		end
	end

	it("allows a burst up to capacity and drops the rest", function()
		local _, clock = makeClock()
		local bucket = TokenBucket.new(5, 1, clock)
		local allowed = 0
		for _ = 1, 50 do
			if bucket:TryTake("a") then
				allowed += 1
			end
		end
		expect(allowed):equal(5)
	end)

	it("refills over time and never above capacity", function()
		local state, clock = makeClock()
		local bucket = TokenBucket.new(5, 2, clock)
		for _ = 1, 5 do
			bucket:TryTake("a")
		end
		expect(bucket:TryTake("a")):falsy()
		state.now = 1 -- +2 tokens
		expect(bucket:TryTake("a")):truthy()
		expect(bucket:TryTake("a")):truthy()
		expect(bucket:TryTake("a")):falsy()
		state.now = 1000
		local allowed = 0
		for _ = 1, 20 do
			if bucket:TryTake("a") then
				allowed += 1
			end
		end
		expect(allowed):equal(5)
	end)

	it("isolates keys from each other", function()
		local _, clock = makeClock()
		local bucket = TokenBucket.new(2, 0, clock)
		expect(bucket:TryTake("a")):truthy()
		expect(bucket:TryTake("a")):truthy()
		expect(bucket:TryTake("a")):falsy()
		expect(bucket:TryTake("b")):truthy()
	end)

	it("starts a removed key with a full bucket", function()
		local _, clock = makeClock()
		local bucket = TokenBucket.new(1, 0, clock)
		expect(bucket:TryTake("a")):truthy()
		expect(bucket:TryTake("a")):falsy()
		bucket:Remove("a")
		expect(bucket:TryTake("a")):truthy()
	end)

	it("supports costs and ignores a backwards clock", function()
		local state, clock = makeClock()
		state.now = 10
		local bucket = TokenBucket.new(4, 1, clock)
		expect(bucket:TryTake("a", 3)):truthy()
		expect(bucket:TryTake("a", 2)):falsy()
		state.now = 5
		expect(bucket:TryTake("a", 2)):falsy()
	end)
end)
