describe("ObstacleMath", function()
	local ObstacleMath = load("ReplicatedStorage/Shared/ObstacleMath")

	it("wraps the phase and applies an offset", function()
		expect(ObstacleMath.Phase(0, 4)):near(0, 1e-9)
		expect(ObstacleMath.Phase(1, 4)):near(0.25, 1e-9)
		expect(ObstacleMath.Phase(5, 4)):near(0.25, 1e-9)
		expect(ObstacleMath.Phase(1, 4, 1)):near(0.5, 1e-9)
		expect(ObstacleMath.Phase(-1, 4)):near(0.75, 1e-9)
	end)

	it("ping-pongs 0 -> 1 -> 0", function()
		expect(ObstacleMath.PingPong(0)):near(0, 1e-9)
		expect(ObstacleMath.PingPong(0.25)):near(0.5, 1e-9)
		expect(ObstacleMath.PingPong(0.5)):near(1, 1e-9)
		expect(ObstacleMath.PingPong(0.75)):near(0.5, 1e-9)
		expect(ObstacleMath.PingPong(1)):near(0, 1e-9)
	end)

	it("rotates a full turn per period, either way", function()
		expect(ObstacleMath.RotationAngle(1, 4, 1)):near(math.pi / 2, 1e-9)
		expect(ObstacleMath.RotationAngle(1, 4, -1)):near(-math.pi / 2, 1e-9)
		expect(ObstacleMath.RotationAngle(4, 4, 1)):near(0, 1e-9)
	end)

	it("vanishes on schedule with a fade before it goes", function()
		-- on 2s, off 1.5s, fade 0.3s
		expect(ObstacleMath.Vanishing(0, 2, 1.5, 0, 0.3).Solid):equal(true)
		expect(ObstacleMath.Vanishing(0, 2, 1.5, 0, 0.3).Transparency):equal(0)
		expect(ObstacleMath.Vanishing(1.85, 2, 1.5, 0, 0.3).Transparency):near(0.5, 1e-9)
		expect(ObstacleMath.Vanishing(1.85, 2, 1.5, 0, 0.3).Solid):equal(true)
		local off = ObstacleMath.Vanishing(2.5, 2, 1.5, 0, 0.3)
		expect(off.Solid):equal(false)
		expect(off.Transparency):equal(1)
		expect(ObstacleMath.Vanishing(3.5, 2, 1.5, 0, 0.3).Solid):equal(true) -- next cycle
		expect(ObstacleMath.Vanishing(0, 2, 1.5, 2, 0.3).Solid):equal(false) -- phase shifts the cycle
	end)

	it("shapes a boost: rise, hold, fall, done", function()
		local function linear(alpha)
			return alpha
		end
		local function at(t, from)
			return ObstacleMath.BoostMultiplier(t, from or 1, 1.6, 2, 0.5, linear)
		end
		expect((at(0))):near(1, 1e-9)
		expect((at(0.25))):near(1.3, 1e-9)
		expect((at(1))):near(1.6, 1e-9)
		expect((at(2.5))):near(1.6, 1e-9)
		expect((at(2.75))):near(1.3, 1e-9)
		local multiplier, isDone = at(3)
		expect(multiplier):equal(1)
		expect(isDone):equal(true)
		expect((at(0, 1.4))):near(1.4, 1e-9) -- retriggered mid-boost starts from the current value
	end)

	it("resolves axes", function()
		expect(ObstacleMath.Axis("Y")):equal(Vector3.yAxis)
		expect(ObstacleMath.Axis("W")):equal(nil)
	end)

	describe("ConfigFor", function()
		it("fills defaults", function()
			expect(ObstacleMath.ConfigFor("Rotating", {}).Period):equal(4)
			expect(ObstacleMath.ConfigFor("Rotating", {}).Direction):equal(1)
			expect(ObstacleMath.ConfigFor("Vanishing", {}).OffTime):equal(1.5)
			expect(ObstacleMath.ConfigFor("JumpPad", {}, { JumpPower = 0.4 }).JumpPower):equal(0.4)
			expect(ObstacleMath.ConfigFor("BoostPanel", {}, { BoostSpeed = 1.6, Duration = 2 }).BoostSpeed):equal(1.6)
			expect(ObstacleMath.ConfigFor("Moving", { Offset = Vector3.new(0, 0, 20) }).Easing):equal("Sine")
		end)

		it("accepts attribute overrides", function()
			expect(
				ObstacleMath.ConfigFor(
					"BoostPanel",
					{ BoostSpeed = 1.2, Duration = 1 },
					{ BoostSpeed = 1.6, Duration = 2 }
				).BoostSpeed
			):equal(1.2)
			expect(ObstacleMath.ConfigFor("Rotating", { Axis = "X", Direction = -1, Period = 1 }).Direction):equal(-1)
		end)

		it("clamps boost panel attributes to the audited defaults", function()
			local config = ObstacleMath.ConfigFor(
				"BoostPanel",
				{ BoostSpeed = 3, Duration = 10 },
				{ BoostSpeed = 1.6, Duration = 2 }
			)
			expect(config.BoostSpeed):equal(1.6)
			expect(config.Duration):equal(2)
			expect(ObstacleMath.ConfigFor("BoostPanel", { Duration = 1 }, { BoostSpeed = 1.6, Duration = 2 }).Duration):equal(
				1
			)
		end)

		it("rejects bad values with a message naming the attribute", function()
			local _, err = ObstacleMath.ConfigFor("Rotating", { Axis = "Q" })
			expect(string.find(err, "Axis", 1, true) ~= nil):truthy()
			_, err = ObstacleMath.ConfigFor("Rotating", { Period = 0 })
			expect(string.find(err, "Period", 1, true) ~= nil):truthy()
			_, err = ObstacleMath.ConfigFor("Rotating", { Direction = 2 })
			expect(string.find(err, "Direction", 1, true) ~= nil):truthy()
			_, err = ObstacleMath.ConfigFor("Moving", {})
			expect(string.find(err, "Offset", 1, true) ~= nil):truthy()
			_, err = ObstacleMath.ConfigFor("Moving", { Offset = Vector3.new(1, 0, 0), Easing = "Wobble" })
			expect(string.find(err, "Easing", 1, true) ~= nil):truthy()
			_, err = ObstacleMath.ConfigFor("JumpPad", { JumpPower = "high" }, { JumpPower = 0.4 })
			expect(string.find(err, "JumpPower", 1, true) ~= nil):truthy()
			_, err = ObstacleMath.ConfigFor("Vanishing", { OnTime = -1 })
			expect(string.find(err, "OnTime", 1, true) ~= nil):truthy()
			_, err = ObstacleMath.ConfigFor("GrappleAnchor", { Range = 0 })
			expect(string.find(err, "Range", 1, true) ~= nil):truthy()
		end)

		it("rejects NaN and unknown kinds", function()
			expect(ObstacleMath.ConfigFor("Rotating", { Period = 0 / 0 })):equal(nil)
			expect(ObstacleMath.ConfigFor("Nope", {})):equal(nil)
		end)

		it("allows an anchor and a kill brick with no attributes", function()
			expect(ObstacleMath.ConfigFor("GrappleAnchor", {}).Range):equal(nil)
			expect(ObstacleMath.ConfigFor("KillBrick", {})):truthy()
		end)
	end)
end)
