describe("BallStats", function()
	local BallStats = load("ReplicatedStorage/Shared/BallStats")
	local PhysicsTable = load("ReplicatedStorage/Tables/PhysicsTable")

	local EPS = 0.0001
	-- GDD 3 full table: rating -> MaxForce, SmoothMoveRate, AirMoveRate, JumpPower.
	local expected = {
		[1] = { 0.1008, 6.8, 4.08, 0.2200 },
		[5] = { 0.1200, 10.0, 6.00, 0.2500 },
		[10] = { 0.1440, 14.0, 8.40, 0.2875 },
	}

	for rating, row in expected do
		it(`matches the GDD table at rating {rating}`, function()
			local r = BallStats.Resolve({ Speed = rating, Acceleration = rating, Jump = rating })
			expect(r.MaxForce):near(row[1], EPS)
			expect(r.SmoothMoveRate):near(row[2], EPS)
			expect(r.AirMoveRate):near(row[3], EPS)
			expect(r.JumpPower):near(row[4], EPS)
			expect(r.SmoothStopRate):equal(6)
			expect(r.DoubleJumpPower):near(row[4] * 1.1, EPS)
		end)
	end

	it("matches the GDD worked examples", function()
		local void = BallStats.Resolve({ Speed = 9, Acceleration = 6, Jump = 4 }, { Turbo = true })
		expect(void.MaxForce):near(0.1531, EPS)
		local bouncer = BallStats.Resolve({ Speed = 2, Acceleration = 2, Jump = 5 }, nil, { SlowEveryone = true })
		expect(bouncer.MaxForce):near(0.0739, EPS)
	end)

	it("makes Turbo exactly x1.10 MaxForce", function()
		for rating = 1, 10 do
			local stats = { Speed = rating, Acceleration = 5, Jump = 5 }
			local plain = BallStats.Resolve(stats)
			local turbo = BallStats.Resolve(stats, { Turbo = true })
			expect(turbo.MaxForce):equal(plain.MaxForce * 1.10)
		end
	end)

	it("applies modifiers: low gravity, giant, shrink, double jump", function()
		local stats = { Speed = 5, Acceleration = 5, Jump = 5 }
		expect(BallStats.Resolve(stats).Gravity):equal(196.2)
		expect(BallStats.Resolve(stats, nil, { LowGravity = true }).Gravity):equal(110)
		expect(BallStats.Resolve(stats, nil, { GiantBalls = true }).Scale):equal(2)
		expect(BallStats.Resolve(stats, nil, { GiantBalls = true, ShrinkEveryone = true }).Scale):equal(0.5)
		expect(BallStats.Resolve(stats).DoubleJumpEnabled):equal(false)
		expect(BallStats.Resolve(stats, { DoubleJump = true }).DoubleJumpEnabled):equal(true)
		expect(BallStats.Resolve(stats, nil, { DoubleJumpForAll = true }).DoubleJumpEnabled):equal(true)
	end)

	it("rejects bad ratings and unknown balls", function()
		expect(function()
			BallStats.Resolve({ Speed = 0, Acceleration = 5, Jump = 5 })
		end):throws("Speed")
		expect(function()
			BallStats.Resolve({ Speed = 5, Acceleration = 5 })
		end):throws("Jump")
		expect(function()
			BallStats.ForBall("nope")
		end):throws("unknown ball")
	end)

	it("resolves a ball from BallTable", function()
		local r = BallStats.ForBall("voidmaw", { Turbo = true })
		expect(r.MaxForce):near(0.1531, EPS)
		expect(r.SpeedRating):equal(9)
	end)

	describe("MaxAllowedSpeed", function()
		local TOP = 50 -- studs/s at the anchor MaxForce, arbitrary for the test
		local r10 = BallStats.Resolve({ Speed = 10, Acceleration = 5, Jump = 5 })
		local normalTop = TOP * 0.144 / 0.12

		it("allows 1.25x normal top speed", function()
			expect(BallStats.MaxAllowedSpeed(r10, { AnchorTopSpeed = TOP })):near(normalTop * 1.25, EPS)
		end)

		it("flags a Speed-10 ball held at 1.6x normal top speed with no boost", function()
			expect(normalTop * 1.6 > BallStats.MaxAllowedSpeed(r10, { AnchorTopSpeed = TOP })):truthy()
		end)

		it("allows 1.6x during a boost or rocket, without stacking them", function()
			local boosted = BallStats.MaxAllowedSpeed(r10, { AnchorTopSpeed = TOP, Boosting = true })
			expect(boosted):near(normalTop * 1.6 * 1.25, EPS)
			local both = BallStats.MaxAllowedSpeed(r10, { AnchorTopSpeed = TOP, Boosting = true, Rocketing = true })
			expect(both):near(boosted, EPS)
		end)

		it("allows grapple pull speed and tracks the resolved MaxForce", function()
			expect(BallStats.MaxAllowedSpeed(r10, { AnchorTopSpeed = TOP, Grappling = true })):near(80 * 1.25, EPS)
			local slow = BallStats.Resolve({ Speed = 10, Acceleration = 5, Jump = 5 }, nil, { SlowEveryone = true })
			expect(BallStats.MaxAllowedSpeed(slow, { AnchorTopSpeed = TOP })):near(
				normalTop * PhysicsTable.Modifiers.SlowEveryoneMaxForce * 1.25,
				EPS
			)
		end)

		it("requires AnchorTopSpeed", function()
			expect(function()
				BallStats.MaxAllowedSpeed(r10, {})
			end):throws("AnchorTopSpeed")
		end)
	end)
end)
