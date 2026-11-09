describe("BallMotion", function()
	local BallMotion = load("ReplicatedStorage/Shared/BallMotion")
	local BallStats = load("ReplicatedStorage/Shared/BallStats")
	local PhysicsTable = load("ReplicatedStorage/Tables/PhysicsTable")

	local attrs = BallStats.Resolve({ Speed = 5, Acceleration = 5, Jump = 5 }, { DoubleJump = true })
	local top = BallMotion.TargetSpeed(attrs)

	it("targets MaxForce scaled by AnchorTopSpeed", function()
		expect(top):near(PhysicsTable.AnchorTopSpeed, 0.0001)
		expect(BallMotion.TargetSpeed(attrs, 1.6)):near(PhysicsTable.AnchorTopSpeed * 1.6, 0.0001)
	end)

	it("converges to top speed on the ground and never overshoots", function()
		local v = Vector3.zero
		for _ = 1, 120 do
			v = BallMotion.Step(v, Vector3.new(1, 0, 0), true, attrs, 1 / 60)
			expect(v.X <= top + 1e-6):truthy()
		end
		expect(v.X):near(top, 0.01)
		expect(v.Y):equal(0)
	end)

	it("reaches 90% of top speed in about ln10 / SmoothMoveRate", function()
		local v = Vector3.zero
		local t = 0
		while v.X < top * 0.9 do
			v = BallMotion.Step(v, Vector3.new(1, 0, 0), true, attrs, 0.01)
			t += 0.01
		end
		expect(t):near(math.log(10) / attrs.SmoothMoveRate, 0.02)
	end)

	it("has a faster top speed in the air than on the ground", function()
		local airTop = BallMotion.TargetSpeed(attrs, nil, false)
		expect(airTop):near(top * PhysicsTable.AirTopSpeedMultiplier, 0.0001)
		expect(BallMotion.TargetSpeed(attrs, nil, true)):near(top, 0.0001)
		local v = Vector3.zero
		for _ = 1, 600 do
			v = BallMotion.Step(v, Vector3.new(1, 0, 0), false, attrs, 1 / 60)
		end
		expect(v.X):near(airTop, 0.01)
	end)

	describe("slope", function()
		local function normalFor(degrees)
			-- A slope that falls toward +X.
			local r = math.rad(degrees)
			return Vector3.new(math.sin(r), math.cos(r), 0)
		end

		it("speeds up steering straight downhill by the slope", function()
			local expected = 1 + PhysicsTable.Slope.DownhillSpeedPerSlope * math.sin(math.rad(30))
			expect(BallMotion.DownhillMultiplier(normalFor(30), Vector3.new(1, 0, 0))):near(expected, 1e-6)
		end)

		it("does nothing uphill, across the slope, on flat ground or with no normal", function()
			expect(BallMotion.DownhillMultiplier(normalFor(30), Vector3.new(-1, 0, 0))):equal(1)
			expect(BallMotion.DownhillMultiplier(normalFor(30), Vector3.new(0, 0, 1))):near(1, 1e-6)
			expect(BallMotion.DownhillMultiplier(Vector3.yAxis, Vector3.new(1, 0, 0))):equal(1)
			expect(BallMotion.DownhillMultiplier(nil, Vector3.new(1, 0, 0))):equal(1)
		end)

		it("caps at MaxSlopeDegrees", function()
			local steep = BallMotion.DownhillMultiplier(normalFor(80), Vector3.new(1, 0, 0))
			expect(steep):near(BallMotion.MaxDownhillMultiplier(), 1e-6)
		end)

		it("raises the ground target speed but not the air one", function()
			local options = { SlopeMultiplier = 1.4 }
			local v = Vector3.zero
			for _ = 1, 600 do
				v = BallMotion.Step(v, Vector3.new(1, 0, 0), true, attrs, 1 / 60, options)
			end
			expect(v.X):near(top * 1.4, 0.01)
			local air = Vector3.zero
			for _ = 1, 600 do
				air = BallMotion.Step(air, Vector3.new(1, 0, 0), false, attrs, 1 / 60, options)
			end
			expect(air.X):near(BallMotion.TargetSpeed(attrs, nil, false), 0.01)
		end)
	end)

	it("rolls to a stop on the ground at GroundDeceleration instead of halting", function()
		local v = BallMotion.Step(Vector3.new(30, 4, 0), Vector3.zero, true, attrs, 0.1)
		expect(v.X):near(30 - PhysicsTable.GroundDeceleration * 0.1, 1e-6)
		expect(v.Y):equal(4)
		local diagonal = BallMotion.Step(Vector3.new(30, 0, 40), Vector3.zero, true, attrs, 0.1)
		expect(diagonal.Magnitude):near(50 - PhysicsTable.GroundDeceleration * 0.1, 1e-6)
		expect(diagonal.X / diagonal.Z):near(30 / 40, 1e-6)
	end)

	it("creeps below GroundCreep.Speed instead of stopping dead", function()
		local creep = PhysicsTable.GroundCreep
		local fast = BallMotion.Step(Vector3.new(creep.Speed + 0.5, 0, 0), Vector3.zero, true, attrs, 0.1)
		expect(fast.X):near(creep.Speed, 1e-6)
		local slow = BallMotion.Step(Vector3.new(2, 0, 0), Vector3.zero, true, attrs, 0.1)
		expect(slow.X):near(2 * math.exp(-creep.DecayRate * 0.1), 1e-6)
		expect(slow.X > 0):truthy()
	end)

	it("steers slower in the air than on the ground", function()
		local ground = BallMotion.Step(Vector3.zero, Vector3.new(0, 0, 1), true, attrs, 0.1)
		local air = BallMotion.Step(Vector3.zero, Vector3.new(0, 0, 1), false, attrs, 0.1)
		expect(air.Z < ground.Z):truthy()
		expect(air.Z > 0):truthy()
	end)

	it("clamps diagonal input to top speed", function()
		local v = Vector3.zero
		for _ = 1, 200 do
			v = BallMotion.Step(v, Vector3.new(1, 0, 1), true, attrs, 1 / 60)
		end
		expect(Vector3.new(v.X, 0, v.Z).Magnitude):near(top, 0.01)
	end)

	it("scales with analogue input", function()
		local v = Vector3.zero
		for _ = 1, 200 do
			v = BallMotion.Step(v, Vector3.new(0.5, 0, 0), true, attrs, 1 / 60)
		end
		expect(v.X):near(top * 0.5, 0.01)
	end)

	it("stops on the ground with no input and keeps airborne velocity", function()
		local v = Vector3.new(30, 0, -10)
		for _ = 1, 600 do
			v = BallMotion.Step(v, Vector3.zero, true, attrs, 1 / 60)
		end
		expect(v):equal(Vector3.zero)
		local airborne = Vector3.new(30, 5, 0)
		expect(BallMotion.Step(airborne, Vector3.zero, false, attrs, 0.1)):equal(airborne)
	end)

	it("honours CanControl and CanStop", function()
		local v = Vector3.new(10, 0, 0)
		expect(BallMotion.Step(v, Vector3.new(0, 0, 1), true, attrs, 0.1, { CanControl = false })):equal(v)
		expect(BallMotion.Step(v, Vector3.zero, true, attrs, 0.1, { CanStop = false })):equal(v)
	end)

	it("clamps a huge dt so a hitch does not slingshot", function()
		local a = BallMotion.Step(Vector3.zero, Vector3.new(1, 0, 0), true, attrs, 5)
		local b = BallMotion.Step(Vector3.zero, Vector3.new(1, 0, 0), true, attrs, 0.1)
		expect(a):equal(b)
	end)

	it("makes a Grip-like ball accelerate faster than a Sprinter-like one", function()
		local sprinter = BallStats.ForBall("sprinter")
		local grip = BallStats.ForBall("grip")
		local s = BallMotion.Step(Vector3.zero, Vector3.new(1, 0, 0), true, sprinter, 0.1)
		local g = BallMotion.Step(Vector3.zero, Vector3.new(1, 0, 0), true, grip, 0.1)
		expect(g.X / BallMotion.TargetSpeed(grip) > s.X / BallMotion.TargetSpeed(sprinter)):truthy()
		expect(BallMotion.TargetSpeed(sprinter) > BallMotion.TargetSpeed(grip)):truthy()
	end)

	describe("jumping", function()
		it("sets only vertical velocity from JumpPower, double jump is 1.1x", function()
			local v = BallMotion.ApplyJump(Vector3.new(3, -20, 4), "Jump", attrs)
			expect(v.X):equal(3)
			expect(v.Z):equal(4)
			expect(v.Y):near(attrs.JumpPower * PhysicsTable.JumpVelocityScale, 1e-6)
			local d = BallMotion.ApplyJump(Vector3.zero, "DoubleJump", attrs)
			expect(d.Y):near(v.Y * 1.1, 1e-6)
		end)

		it("jumps from the ground once, then double jumps once when enabled", function()
			local state = BallMotion.NewJumpState()
			expect(BallMotion.UpdateJumpState(state, true, 0.016)):equal(true)
			expect(BallMotion.RequestJump(state, true)):equal("Jump")
			expect(BallMotion.UpdateJumpState(state, true, 0.016)):equal(false) -- lockout hides the ground
			expect(BallMotion.RequestJump(state, true)):equal("DoubleJump")
			expect(BallMotion.RequestJump(state, true)):equal(nil)
		end)

		it("has no double jump when disabled", function()
			local state = BallMotion.NewJumpState()
			BallMotion.UpdateJumpState(state, true, 0.016)
			expect(BallMotion.RequestJump(state, false)):equal("Jump")
			expect(BallMotion.RequestJump(state, false)):equal(nil)
		end)

		it("resets on landing after the lockout", function()
			local state = BallMotion.NewJumpState()
			BallMotion.UpdateJumpState(state, true, 0.016)
			BallMotion.RequestJump(state, true)
			BallMotion.RequestJump(state, true)
			for _ = 1, 20 do
				BallMotion.UpdateJumpState(state, false, 0.016)
			end
			expect(BallMotion.UpdateJumpState(state, true, 0.016)):equal(true)
			expect(BallMotion.RequestJump(state, true)):equal("Jump")
		end)

		it("allows a late ground jump inside the coyote window only", function()
			local state = BallMotion.NewJumpState()
			BallMotion.UpdateJumpState(state, true, 0.016)
			BallMotion.UpdateJumpState(state, false, 0.05)
			expect(BallMotion.RequestJump(state, false)):equal("Jump")

			local late = BallMotion.NewJumpState()
			BallMotion.UpdateJumpState(late, true, 0.016)
			BallMotion.UpdateJumpState(late, false, 0.5)
			expect(BallMotion.RequestJump(late, false)):equal(nil)
		end)

		it("still allows a double jump after a jump pad launch", function()
			local state = BallMotion.NewJumpState()
			BallMotion.UpdateJumpState(state, true, 0.016)
			BallMotion.MarkLaunched(state)
			BallMotion.UpdateJumpState(state, false, 0.016)
			expect(BallMotion.RequestJump(state, true)):equal("DoubleJump")
		end)
	end)
end)

describe("BallMotion tool maths", function()
	local BallMotion = load("ReplicatedStorage/Shared/BallMotion")

	it("StopStep bleeds horizontal speed at the given rate, in any ground state, and keeps Y", function()
		local v = Vector3.new(40, 7, -30)
		for _ = 1, 60 do
			v = BallMotion.StopStep(v, 24, 1 / 60) -- SmoothStopRate 6 x 4 for 1 s
		end
		expect(v.X):near(40 * math.exp(-24), 1e-6)
		expect(v.Y):equal(7)
	end)

	it("CapFallSpeed only limits falling", function()
		expect(BallMotion.CapFallSpeed(Vector3.new(1, -60, 2), 18)):equal(Vector3.new(1, -18, 2))
		expect(BallMotion.CapFallSpeed(Vector3.new(1, -10, 2), 18)):equal(Vector3.new(1, -10, 2))
		expect(BallMotion.CapFallSpeed(Vector3.new(1, 30, 2), 18)):equal(Vector3.new(1, 30, 2))
	end)

	it("PullVelocity heads straight at the anchor at the pull speed and reports arrival", function()
		local v, arrived = BallMotion.PullVelocity(Vector3.zero, Vector3.new(0, 0, -100), 80, 1 / 60)
		expect(arrived):equal(false)
		expect(v.Magnitude):near(80, 1e-6)
		expect(v.Z < 0):truthy()
		local _, near = BallMotion.PullVelocity(Vector3.new(0, 0, -98), Vector3.new(0, 0, -100), 80, 1 / 60)
		expect(near):equal(true)
	end)

	it("ClampHorizontal limits the flat speed only", function()
		local v = BallMotion.ClampHorizontal(Vector3.new(80, 12, 0), 40)
		expect(v.X):near(40, 1e-6)
		expect(v.Y):equal(12)
		expect(BallMotion.ClampHorizontal(Vector3.new(10, 3, 0), 40)):equal(Vector3.new(10, 3, 0))
	end)
end)
