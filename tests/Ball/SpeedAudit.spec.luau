describe("SpeedAudit", function()
	local SpeedAudit = load("ServerScriptService/Script/BallService/SpeedAudit")
	local BallStats = load("ReplicatedStorage/Shared/BallStats")
	local PhysicsTable = load("ReplicatedStorage/Tables/PhysicsTable")

	local DT = PhysicsTable.SpeedAudit.SampleSeconds
	local sprinter = BallStats.ForBall("sprinter")
	-- The fastest legal speed: steering in the air (BallMotion's air top speed).
	local normalTop = PhysicsTable.AnchorTopSpeed
		* sprinter.MaxForce
		/ PhysicsTable.Anchor.MaxForce
		* PhysicsTable.AirTopSpeedMultiplier

	-- Fake clock: runs 10 Hz samples at a constant speed, returns the time of the first strike (or nil).
	local function run(tracker, resolved, speed, seconds, startTime)
		local now = startTime or 0
		local steps = math.floor(seconds / DT + 0.5)
		for _ = 1, steps do
			local struck = SpeedAudit.Check(tracker, resolved, speed, now)
			if struck then
				return now
			end
			now += DT
		end
		return nil
	end

	it("limits to expected top speed x1.25", function()
		local tracker = SpeedAudit.NewTracker()
		expect(SpeedAudit.Limit(tracker, sprinter, 0)):near(normalTop * 1.25, 1e-6)
	end)

	it("strikes a Speed-10 ball held at 1.6x its normal top speed for 2 s", function()
		local fast = BallStats.Resolve({ Speed = 10, Acceleration = 5, Jump = 5 })
		local top = PhysicsTable.AnchorTopSpeed * fast.MaxForce / PhysicsTable.Anchor.MaxForce
		local tracker = SpeedAudit.NewTracker()
		local struckAt = run(tracker, fast, top * 1.6, 2)
		expect(struckAt ~= nil):truthy()
		expect(struckAt <= 2):truthy()
	end)

	it("needs three over-limit samples, not two", function()
		local tracker = SpeedAudit.NewTracker()
		expect(SpeedAudit.Check(tracker, sprinter, normalTop * 2, 0)):equal(false)
		expect(SpeedAudit.Check(tracker, sprinter, normalTop * 2, 0.1)):equal(false)
		expect(SpeedAudit.Check(tracker, sprinter, normalTop * 2, 0.2)):equal(true)
	end)

	it("never strikes at or under the limit", function()
		local tracker = SpeedAudit.NewTracker()
		expect(run(tracker, sprinter, normalTop * 1.25, 10)):equal(nil)
		expect(run(tracker, sprinter, normalTop, 10, 20)):equal(nil)
	end)

	it("forgets over-limit samples older than the window", function()
		local tracker = SpeedAudit.NewTracker()
		SpeedAudit.Check(tracker, sprinter, normalTop * 2, 0)
		SpeedAudit.Check(tracker, sprinter, normalTop * 2, 1)
		expect(SpeedAudit.Check(tracker, sprinter, normalTop * 2, 2.5)):equal(false)
	end)

	it("clears the window after a strike, so a second strike needs three more samples", function()
		local tracker = SpeedAudit.NewTracker()
		local strikes = 0
		for i = 0, 8 do
			if SpeedAudit.Check(tracker, sprinter, normalTop * 2, i * DT) then
				strikes += 1
			end
		end
		expect(strikes):equal(3)
	end)

	it("allows boost speed during the boost window plus grace, then strikes again", function()
		local tracker = SpeedAudit.NewTracker()
		local boosted = normalTop * 1.6
		SpeedAudit.MarkBoostNearby(tracker, 0)
		expect(run(tracker, sprinter, boosted, 2.5)):equal(nil)
		local struckAt = run(tracker, sprinter, boosted, 1, 2.6)
		expect(struckAt ~= nil):truthy()
	end)

	it("keeps a boost window open while the ball stays near a panel", function()
		local tracker = SpeedAudit.NewTracker()
		for i = 0, 40 do
			local now = i * DT
			SpeedAudit.MarkBoostNearby(tracker, now)
			expect(SpeedAudit.Check(tracker, sprinter, normalTop * 1.6, now)):equal(false)
		end
	end)

	it("widens the allowance through SetContext and ignores unknown keys", function()
		local tracker = SpeedAudit.NewTracker()
		expect(SpeedAudit.SetContext(tracker, "Teleporting", 100)):equal(false)
		expect(SpeedAudit.SetContext(tracker, "Rocketing", 5)):equal(true)
		local rocketTool = load("ReplicatedStorage/Tables/ToolTable").Tools.rocket.SpeedMultiplier
		expect(SpeedAudit.Limit(tracker, sprinter, 1)):near(normalTop * math.max(rocketTool, 1) * 1.25, 1e-6)
		expect(SpeedAudit.Limit(tracker, sprinter, 6)):near(normalTop * 1.25, 1e-6)
	end)

	it("never shortens an open window", function()
		local tracker = SpeedAudit.NewTracker()
		SpeedAudit.SetContext(tracker, "Boosting", 10)
		SpeedAudit.SetContext(tracker, "Boosting", 2)
		expect(tracker.Until.Boosting):equal(10)
	end)

	it("detects proximity to a box including rotation and margin", function()
		local cframe = CFrame.new(100, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
		local size = Vector3.new(10, 2, 4) -- long axis along world Z after the turn
		expect(SpeedAudit.IsNearBox(Vector3.new(100, 0, 6), cframe, size, 0.1)):equal(false)
		expect(SpeedAudit.IsNearBox(Vector3.new(100, 0, 6), cframe, size, 1.5)):equal(true)
		expect(SpeedAudit.IsNearBox(Vector3.new(100, 0, 4.5), cframe, size, 0)):equal(true)
		expect(SpeedAudit.IsNearBox(Vector3.new(110, 0, 0), cframe, size, 5)):equal(false)
	end)

	describe("position delta", function()
		it("measures horizontal speed between samples and ignores gaps off the sample rate", function()
			local from = Vector3.new(0, 50, 0)
			expect(SpeedAudit.MeasuredSpeed(from, 0, Vector3.new(3, 0, 4), DT)):near(5 / DT, 1e-6)
			expect(SpeedAudit.MeasuredSpeed(from, 0, Vector3.new(3, 0, 4), DT * 10)):equal(nil)
			expect(SpeedAudit.MeasuredSpeed(from, 0, Vector3.new(3, 0, 4), 0)):equal(nil)
		end)

		it("strikes on displacement even when the reported velocity looks legal", function()
			local tracker = SpeedAudit.NewTracker()
			local measured = normalTop * 1.25 * PhysicsTable.SpeedAudit.PositionTolerance * 1.2
			expect(SpeedAudit.Check(tracker, sprinter, 0, 0, measured)):equal(false)
			expect(SpeedAudit.Check(tracker, sprinter, 0, DT, measured)):equal(false)
			expect(SpeedAudit.Check(tracker, sprinter, 0, DT * 2, measured)):equal(true)
		end)

		it("tolerates measured speed slightly over the limit", function()
			local tracker = SpeedAudit.NewTracker()
			local measured = normalTop * 1.25 * (PhysicsTable.SpeedAudit.PositionTolerance - 0.02)
			for i = 0, 20 do
				expect(SpeedAudit.Check(tracker, sprinter, 0, i * DT, measured)):equal(false)
			end
		end)

		it("counts a sample once when velocity and displacement are both over", function()
			local tracker = SpeedAudit.NewTracker()
			SpeedAudit.Check(tracker, sprinter, normalTop * 3, 0, normalTop * 3)
			expect(#tracker.Over):equal(1)
		end)
	end)

	describe("limit drop grace", function()
		local slowed = BallStats.ForBall("sprinter", {}, { SlowEveryone = true })

		it("does not strike while the allowed speed has just dropped, then resumes", function()
			local tracker = SpeedAudit.NewTracker()
			expect(SpeedAudit.Check(tracker, sprinter, normalTop, 0)):equal(false)
			local grace = PhysicsTable.SpeedAudit.LimitDropGraceSeconds
			-- Still moving at the old normal speed, now over the slowed limit.
			expect(run(tracker, slowed, normalTop, grace - DT, DT)):equal(nil)
			expect(run(tracker, slowed, normalTop, 1, grace + 0.2) ~= nil):truthy()
		end)

		it("gives no grace when the limit rises or stays", function()
			local tracker = SpeedAudit.NewTracker()
			SpeedAudit.Check(tracker, slowed, 0, 0)
			SpeedAudit.Check(tracker, sprinter, 0, DT)
			expect(run(tracker, sprinter, normalTop * 2, 1, 0.2) ~= nil):truthy()
		end)

		it("is not triggered by a boost window expiring", function()
			local tracker = SpeedAudit.NewTracker()
			SpeedAudit.MarkBoostNearby(tracker, 0)
			expect(SpeedAudit.Check(tracker, sprinter, 0, 0)):equal(false)
			expect(run(tracker, sprinter, normalTop * 2, 1, 3) ~= nil):truthy()
		end)
	end)
end)
