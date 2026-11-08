describe("ModifierStack", function()
	local ModifierStack = load("ReplicatedStorage/Shared/ModifierStack")

	it("is neutral when empty", function()
		local stack = ModifierStack.New()
		expect(ModifierStack.Max(stack)):equal(1)
		expect(ModifierStack.Product(stack)):equal(1)
	end)

	it("applies the largest speed multiplier of overlapping sources", function()
		local stack = ModifierStack.New()
		ModifierStack.Set(stack, "BoostPanel", 1.25)
		ModifierStack.Set(stack, "Rocket", 1.6)
		expect(ModifierStack.Max(stack)):equal(1.6)
	end)

	it("keeps a boost running when the rocket ends", function()
		local stack = ModifierStack.New()
		ModifierStack.Set(stack, "BoostPanel", 1.25)
		ModifierStack.Set(stack, "Rocket", 1.6)
		ModifierStack.Clear(stack, "Rocket")
		expect(ModifierStack.Max(stack)):equal(1.25)
		ModifierStack.Clear(stack, "BoostPanel")
		expect(ModifierStack.Max(stack)):equal(1)
	end)

	it("replaces a source's own entry instead of adding to it", function()
		local stack = ModifierStack.New()
		ModifierStack.Set(stack, "BoostPanel", 1.5)
		ModifierStack.Set(stack, "BoostPanel", 1.1)
		expect(ModifierStack.Max(stack)):equal(1.1)
	end)

	it("a lone slowdown is not hidden by the neutral 1", function()
		local stack = ModifierStack.New()
		ModifierStack.Set(stack, "Slow", 0.5)
		expect(ModifierStack.Max(stack)):equal(0.5)
	end)

	it("multiplies gravity sources", function()
		local stack = ModifierStack.New()
		ModifierStack.Set(stack, "LowGravity", 0.5)
		ModifierStack.Set(stack, "Coil", 0.6)
		expect(ModifierStack.Product(stack)):near(0.3, 1e-9)
	end)

	it("rejects bad values and resets", function()
		local stack = ModifierStack.New()
		expect(ModifierStack.Set(stack, "A", 0)):equal(false)
		expect(ModifierStack.Set(stack, "A", -1)):equal(false)
		expect(ModifierStack.Set(stack, "A", math.huge)):equal(false)
		expect(ModifierStack.Set(stack, "A", 0 / 0)):equal(false)
		expect(ModifierStack.Set(stack, "A", "2")):equal(false)
		expect(ModifierStack.Set(stack, nil, 2)):equal(false)
		ModifierStack.Set(stack, "B", 2)
		ModifierStack.Reset(stack)
		expect(ModifierStack.Max(stack)):equal(1)
	end)
end)

describe("TimeWarp", function()
	local TimeWarp = load("ReplicatedStorage/Shared/TimeWarp")

	it("builds lag at (1 - scale) per second while slowed", function()
		local lag = 0
		for _ = 1, 100 do
			lag = TimeWarp.StepLag(lag, 0.05, 0.5, true) -- 5 s
		end
		expect(lag):near(2.5, 1e-6)
	end)

	it("catches up afterwards and stops at zero", function()
		local lag = 2.5
		for _ = 1, 20 do
			lag = TimeWarp.StepLag(lag, 0.1, 0.5, false) -- 2 s
		end
		expect(lag):near(0.5, 1e-6)
		for _ = 1, 20 do
			lag = TimeWarp.StepLag(lag, 0.1, 0.5, false)
		end
		expect(lag):equal(0)
	end)

	it("objects outside the radius do not build lag", function()
		expect(TimeWarp.StepLag(0, 1, 0.5, false)):equal(0)
	end)
end)

describe("GrappleAim", function()
	local GrappleAim = load("ReplicatedStorage/Shared/GrappleAim")
	local origin = Vector3.new(0, 0, 0)
	local forward = Vector3.new(0, 0, -1)

	it("picks the nearest anchor in range inside the cone", function()
		local key, distance = GrappleAim.Pick(origin, forward, {
			{ Key = "far", Position = Vector3.new(0, 0, -50) },
			{ Key = "near", Position = Vector3.new(5, 0, -20) },
		}, 60, 30)
		expect(key):equal("near")
		expect(distance):near(Vector3.new(5, 0, -20).Magnitude, 1e-6)
	end)

	it("ignores anchors out of range, outside the cone or behind", function()
		expect(GrappleAim.Pick(origin, forward, { { Key = "a", Position = Vector3.new(0, 0, -61) } }, 60, 30)):equal(
			nil
		)
		expect(GrappleAim.Pick(origin, forward, { { Key = "b", Position = Vector3.new(30, 0, -20) } }, 60, 30)):equal(
			nil
		)
		expect(GrappleAim.Pick(origin, forward, { { Key = "c", Position = Vector3.new(0, 0, 20) } }, 60, 30)):equal(nil)
	end)

	it("lets an anchor's Range override the default", function()
		local candidates = { { Key = "long", Position = Vector3.new(0, 0, -80), Range = 100 } }
		expect(GrappleAim.Pick(origin, forward, candidates, 60, 30)):equal("long")
		candidates[1].Range = 10
		expect(GrappleAim.Pick(origin, forward, candidates, 60, 30)):equal(nil)
	end)

	it("returns nothing with no candidates or no look direction", function()
		expect(GrappleAim.Pick(origin, forward, {}, 60, 30)):equal(nil)
		expect(GrappleAim.Pick(origin, Vector3.zero, { { Key = "a", Position = Vector3.new(0, 0, -5) } }, 60, 30)):equal(
			nil
		)
	end)
end)
