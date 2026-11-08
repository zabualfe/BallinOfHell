describe("BallAttributes", function()
	local BallAttributes = load("ServerScriptService/Script/BallService/BallAttributes")
	local BallStats = load("ReplicatedStorage/Shared/BallStats")
	local EPS = 0.0001

	local function fakeInstance()
		local written = {}
		return {
			Written = written,
			SetAttribute = function(_, key, value)
				written[key] = value
			end,
		}
	end

	it("gives the three starters measurably different attributes", function()
		local sprinter = BallAttributes.Build("sprinter")
		local grip = BallAttributes.Build("grip")
		local bouncer = BallAttributes.Build("bouncer")
		expect(sprinter.MaxForce):near(0.12, EPS)
		expect(grip.MaxForce):near(0.1056, EPS)
		expect(bouncer.MaxForce):near(0.1056, EPS)
		expect(grip.SmoothMoveRate):near(10, EPS)
		expect(sprinter.SmoothMoveRate):near(7.6, EPS)
		expect(grip.AirMoveRate):near(6, EPS)
		expect(sprinter.AirMoveRate):near(4.56, EPS)
		expect(bouncer.JumpPower):near(0.25, EPS)
		expect(sprinter.JumpPower):near(0.2275, EPS)
		expect(grip.JumpPower):near(0.2275, EPS)
	end)

	it("writes every resolved key as an attribute on the ball", function()
		local instance = fakeInstance()
		local resolved = BallAttributes.Build("sprinter")
		BallAttributes.Apply(instance, resolved)
		for key, value in resolved do
			expect(instance.Written[key]):equal(value)
		end
		expect(instance.Written.MaxForce):near(0.12, EPS)
		expect(instance.Written.DoubleJumpEnabled):equal(false)
	end)

	it("matches the GDD table for every rating through the write path", function()
		local expected = { [1] = 0.1008, [5] = 0.12, [10] = 0.144 }
		for rating, maxForce in expected do
			local instance = fakeInstance()
			BallAttributes.Apply(instance, BallStats.Resolve({ Speed = rating, Acceleration = rating, Jump = rating }))
			expect(instance.Written.MaxForce):near(maxForce, EPS)
		end
	end)

	it("multiplies MaxForce by exactly 1.10 with Turbo", function()
		for _, ballId in { "sprinter", "grip", "bouncer" } do
			local plain = BallAttributes.Build(ballId)
			local turbo = BallAttributes.Build(ballId, { Turbo = true })
			expect(turbo.MaxForce):equal(plain.MaxForce * 1.10)
		end
	end)

	it("lets the doubleJump setting switch the pass perk off but never on", function()
		expect(BallAttributes.Build("grip", { DoubleJump = true }, nil, { doubleJump = true }).DoubleJumpEnabled):equal(
			true
		)
		expect(BallAttributes.Build("grip", { DoubleJump = true }, nil, { doubleJump = false }).DoubleJumpEnabled):equal(
			false
		)
		expect(BallAttributes.Build("grip", {}, nil, { doubleJump = true }).DoubleJumpEnabled):equal(false)
		expect(BallAttributes.Build("grip", {}, { DoubleJumpForAll = true }, {}).DoubleJumpEnabled):equal(true)
	end)

	it("does not mutate the pass set it is given", function()
		local passes = { DoubleJump = true }
		BallAttributes.Build("grip", passes, nil, { doubleJump = false })
		expect(passes.DoubleJump):equal(true)
	end)

	it("reads active modifiers from boolean attributes", function()
		local attrs = { LowGravity = true, GiantBalls = false, SlowEveryone = 1 }
		local active = BallAttributes.ReadModifiers({ "LowGravity", "GiantBalls", "SlowEveryone" }, function(key)
			return attrs[key]
		end)
		expect(active):equal({ LowGravity = true })
		expect(BallAttributes.Build("sprinter", nil, active).Gravity):equal(110)
	end)

	it("errors on an unknown ball id", function()
		expect(function()
			BallAttributes.Build("nope")
		end):throws("unknown ball id")
	end)
end)
