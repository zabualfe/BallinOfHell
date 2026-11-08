describe("RoundMath", function()
	local RoundMath = load("ServerScriptService/Script/RoundService/RoundMath")
	local RoundTable = load("ReplicatedStorage/Tables/RoundTable")

	it("raises the multiplier 0.5 per finisher and caps at 3", function()
		local rule = RoundTable.Multiplier
		expect(RoundMath.Multiplier(0, rule)):near(1, 1e-9)
		expect(RoundMath.Multiplier(2, rule)):near(2, 1e-9)
		expect(RoundMath.Multiplier(3, rule)):near(2.5, 1e-9)
		expect(RoundMath.Multiplier(4, rule)):near(3, 1e-9)
		expect(RoundMath.Multiplier(20, rule)):near(3, 1e-9)
	end)

	it("speeds the clock 0.25 per finisher and caps at 2.5", function()
		local rule = RoundTable.ClockRate
		expect(RoundMath.ClockRate(0, rule)):near(1, 1e-9)
		expect(RoundMath.ClockRate(2, rule)):near(1.5, 1e-9)
		expect(RoundMath.ClockRate(3, rule)):near(1.75, 1e-9)
		expect(RoundMath.ClockRate(6, rule)):near(2.5, 1e-9)
		expect(RoundMath.ClockRate(50, rule)):near(2.5, 1e-9)
	end)

	it("treats a negative finisher count as zero", function()
		expect(RoundMath.Multiplier(-3, RoundTable.Multiplier)):near(1, 1e-9)
	end)

	it("advances the clock by dt x rate and never below 0", function()
		expect(RoundMath.AdvanceClock(100, 2, 1.5)):near(97, 1e-9)
		expect(RoundMath.AdvanceClock(1, 2, 2.5)):equal(0)
	end)

	it("lets players join only with 60 s of clock left", function()
		local min = RoundTable.LateJoinMinClockSeconds
		expect(RoundMath.CanLateJoin(60, min)):equal(true)
		expect(RoundMath.CanLateJoin(59.9, min)):equal(false)
		expect(RoundMath.CanLateJoin(1200, min)):equal(true)
	end)
end)
