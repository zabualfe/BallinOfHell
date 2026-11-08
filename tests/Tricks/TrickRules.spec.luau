describe("TrickRules", function()
	local TrickRules = load("ReplicatedStorage/Shared/TrickRules")
	local TrickTable = load("ReplicatedStorage/Tables/TrickTable")

	local MIN_AIRTIME = TrickTable.Config.MinAirtime
	local MARGIN = TrickTable.Config.PickMargin

	local function levelsAll(ids, level)
		local levels = {}
		for _, id in ids do
			levels[id] = level
		end
		return levels
	end

	-- GDD 7.5: window = airtime - MIN_AIRTIME, the plan must fit window - PICK_MARGIN.
	local function bestPlan(airtime, equipped, levels)
		return TrickRules.PlanBest(equipped, { Budget = airtime - MIN_AIRTIME - MARGIN, Levels = levels })
	end

	describe("worked examples (GDD 7.5)", function()
		it("1: average player on a 1.9 s jump pad scores exactly 210", function()
			local equipped = { "tuck", "horns", "spin", "hellbird" }
			local best = bestPlan(1.9, equipped, {})
			expect(best.Plan):equal({ "spin", "hellbird" })
			expect(best.Points):equal(210)
		end)

		-- GDD 7.5 prints 156.25 + 421.875 = 577.125, but the sum is 578.125. The plan and every term match the GDD, so
		-- the formula is kept and the printed total is the typo (card: GDD example 2 should read 578 / 178 carried).
		it("2: trick-heavy player on a 2.4 s drop picks the GDD plan; terms 156.25 + 421.875 give 578", function()
			local equipped = { "backflip", "doubleflip", "throne", "corkscrew" }
			local best = bestPlan(2.4, equipped, levelsAll(equipped, 2))
			expect(best.Plan):equal({ "backflip", "doubleflip" })
			expect(best.Points):equal(578)
			expect(best.Raw):near(156.25 + 421.875, 1e-9)
		end)

		it("3: the same jump cut 70% into Double Damnation scores exactly 367", function()
			local result = TrickRules.Score({
				{ Id = "backflip" },
				{ Id = "doubleflip", Progress = 0.7 },
			}, { Levels = levelsAll({ "backflip", "doubleflip" }, 2) })
			expect(result.Points):equal(367)
			expect(result.Grade):equal("Sloppy")
		end)

		it("examples 1 and 2 pay 1 and 2 base coins and carry the rest", function()
			local ledger = TrickRules.NewLedger()
			local coins = TrickRules.Settle(ledger, 1, 210, 10)
			expect(coins):equal(1)
			expect(ledger.Carry):equal(10)
			local ledger2 = TrickRules.NewLedger()
			expect(TrickRules.Settle(ledger2, 1, 578, 10)):equal(2)
			expect(ledger2.Carry):equal(178)
		end)
	end)

	describe("Score", function()
		it("chains x1, x1.5, x2, x2.5 and caps at x2.5", function()
			expect(TrickRules.ChainMultiplier(1)):equal(1)
			expect(TrickRules.ChainMultiplier(2)):equal(1.5)
			expect(TrickRules.ChainMultiplier(3)):equal(2)
			expect(TrickRules.ChainMultiplier(4)):equal(2.5)
			expect(TrickRules.ChainMultiplier(5)):equal(2.5)
		end)

		it("halves a trick repeated in the same airtime", function()
			local result = TrickRules.Score({ { Id = "tuck" }, { Id = "horns" }, { Id = "tuck" } })
			-- 50 + 50 * 1.5 + 50 * 2 * 0.5 = 175
			expect(result.Points):equal(175)
		end)

		it("adds x1.25 for three or more different tricks", function()
			local result = TrickRules.Score({ { Id = "tuck" }, { Id = "horns" }, { Id = "spin" } })
			-- (50 + 75 + 120) * 1.25 = 306.25
			expect(result.Points):equal(306)
			expect(result.Variety):equal(1.25)
			local two = TrickRules.Score({ { Id = "tuck" }, { Id = "horns" } })
			expect(two.Variety):equal(1)
		end)

		it("keeps earlier tricks at full value when the last is cut", function()
			local full = TrickRules.Score({ { Id = "tuck" }, { Id = "horns" } })
			local cut = TrickRules.Score({ { Id = "tuck" }, { Id = "horns", Progress = 0.2 } })
			expect(cut.Points):equal(50)
			expect(full.Points):equal(125)
			expect(cut.Grade):equal("Sloppy")
		end)

		it("scores a cut trick at x0.5 from exactly 50% and 0 below", function()
			expect(TrickRules.Score({ { Id = "tuck", Progress = 0.5 } }).Points):equal(25)
			expect(TrickRules.Score({ { Id = "tuck", Progress = 0.49 } }).Points):equal(0)
		end)

		it("applies the upgrade level", function()
			expect(TrickRules.Score({ { Id = "tuck" } }, { Levels = { tuck = 2 } }).Points):equal(62)
			expect(TrickRules.Score({ { Id = "tuck" } }, { Levels = { tuck = 3 } }).Points):equal(75)
			expect(TrickRules.Score({ { Id = "tuck" } }, { Levels = { tuck = 9 } }).Points):equal(75)
		end)

		it("halves once for any assist and not at all otherwise", function()
			local plain = TrickRules.Score({ { Id = "backflip" } })
			local assisted = TrickRules.Score({ { Id = "backflip" } }, { Assisted = true })
			expect(plain.Points):equal(125)
			expect(assisted.Points):equal(62)
		end)

		it("pays 0 and a Bail grade for a void airtime", function()
			local result = TrickRules.Score({ { Id = "backflip" } }, { Void = true })
			expect(result.Points):equal(0)
			expect(result.Grade):equal("Bail")
		end)

		it("formats the landing popup", function()
			expect(TrickRules.LandingText("Clean", 210)):equal("CLEAN! 210")
			expect(TrickRules.LandingText("Sloppy", 367)):equal("SLOPPY! 367")
			expect(TrickRules.LandingText("Bail", 0)):equal("BAIL!")
		end)
	end)

	describe("eligibility", function()
		local function context(overrides)
			local base = { RoundState = "Race", Airtime = 0.7, GroundDrop = 20 }
			for key, value in overrides do
				base[key] = value
			end
			if overrides.NoGround then
				base.GroundDrop = nil
			end
			return base
		end

		it("allows a long enough airtime in Race", function()
			expect(TrickRules.CanStart(context({}))):equal(true)
		end)
		it("never starts before MIN_AIRTIME", function()
			local ok, reason = TrickRules.CanStart(context({ Airtime = MIN_AIRTIME - 0.01 }))
			expect(ok):equal(false)
			expect(reason):equal("Airtime")
			expect(TrickRules.CanStart(context({ Airtime = MIN_AIRTIME }))):equal(true)
		end)
		it("never starts outside the Race state", function()
			for _, state in { "Intermission", "BuildCourse", "Countdown", "Results", "Teardown" } do
				local ok, reason = TrickRules.CanStart(context({ RoundState = state }))
				expect(ok):equal(false)
				expect(reason):equal("State")
			end
		end)
		it("never starts while gliding or grappling, or when frozen", function()
			expect(select(2, TrickRules.CanStart(context({ Gliding = true })))):equal("Glider")
			expect(select(2, TrickRules.CanStart(context({ Grappling = true })))):equal("Grapple")
			expect(select(2, TrickRules.CanStart(context({ Frozen = true })))):equal("Frozen")
		end)
		it("never starts without ground within 200 studs", function()
			expect(select(2, TrickRules.CanStart(context({ NoGround = true })))):equal("Void")
			expect(select(2, TrickRules.CanStart(context({ GroundDrop = 200.5 })))):equal("Void")
			expect(TrickRules.CanStart(context({ GroundDrop = 200 }))):equal(true)
		end)
		it("has hysteresis between the grounded and airborne distances", function()
			local radius = 2
			expect(TrickRules.NextAirborne(true, radius + 0.5, radius)):equal(false)
			expect(TrickRules.NextAirborne(false, nil, radius)):equal(true)
			expect(TrickRules.NextAirborne(true, radius + 1.5, radius)):equal(true)
			expect(TrickRules.NextAirborne(false, radius + 1.5, radius)):equal(false)
		end)
		it("predicts the landing time ballistically", function()
			-- Dropping 19.62 studs from rest at g = 196.2 takes 0.447 s.
			expect(TrickRules.PredictLanding(0, 19.62, 196.2)):near(math.sqrt(2 * 19.62 / 196.2), 1e-6)
			-- Going up at 98.1 over flat ground: 2 * v / g = 1 s.
			expect(TrickRules.PredictLanding(98.1, 0, 196.2)):near(1, 1e-6)
			expect(TrickRules.PredictLanding(0, nil, 196.2)):equal(nil)
			expect(TrickRules.PredictLanding(0, 250, 196.2)):equal(nil)
		end)
	end)

	describe("auto-picker", function()
		it("never plans a trick that ends within the margin of landing", function()
			local equipped = { "tuck", "horns", "spin", "hellbird" }
			for tLand = 0.3, 3, 0.05 do
				local best = TrickRules.PlanBest(equipped, { Budget = tLand - MARGIN })
				if best then
					local total = 0
					for _, id in best.Plan do
						total += TrickTable.Tricks[id].Duration
					end
					expect(total <= tLand - MARGIN + 1e-9):truthy()
				end
			end
		end)
		it("plans nothing when no trick fits", function()
			expect(TrickRules.PlanBest({ "tuck" }, { Budget = 0.39 })):equal(nil)
			expect(TrickRules.PlanBest({}, { Budget = 5 })):equal(nil)
		end)
		it("only uses the playable list", function()
			local best = TrickRules.PlanBest({ "tuck" }, { Budget = 3 })
			for _, id in best.Plan do
				expect(id):equal("tuck")
			end
		end)
		it("never repeats a trick back to back, including after one already played", function()
			local best = TrickRules.PlanBest({ "tuck", "horns" }, { Budget = 4 })
			for index = 2, #best.Plan do
				expect(best.Plan[index] ~= best.Plan[index - 1]):truthy()
			end
			local followUp = TrickRules.PlanBest({ "tuck", "horns" }, { Budget = 0.5, Played = { "tuck" } })
			expect(followUp.Plan):equal({ "horns" })
			expect(TrickRules.PlanBest({ "tuck" }, { Budget = 0.5, Played = { "tuck" } })):equal(nil)
		end)
		it("caps a plan at five tricks", function()
			local best = TrickRules.PlanBest({ "tuck", "horns" }, { Budget = 10 })
			expect(#best.Plan):equal(5)
		end)
		it("breaks ties toward more different tricks", function()
			-- One trick of 0.4 s only has one possible score; with two equal-score tricks the plan must still mix.
			local best = TrickRules.PlanBest({ "tuck", "horns" }, { Budget = 0.8 })
			expect(best.Distinct):equal(2)
		end)
		it("filters the loadout to owned, known and unique tricks", function()
			local playable = TrickRules.Playable({ "tuck", "hellbird", "tuck", "nope", "" }, {})
			expect(playable):equal({ "tuck" })
			expect(TrickRules.Playable({ "tuck", "hellbird", "", "" }, { hellbird = true })):equal({
				"tuck",
				"hellbird",
			})
		end)
	end)

	describe("caps and coins", function()
		it("carries remainder points between airtimes", function()
			local ledger = TrickRules.NewLedger()
			expect(TrickRules.Settle(ledger, 1, 150, 10)):equal(0)
			expect(TrickRules.Settle(ledger, 1, 150, 10)):equal(1)
			expect(ledger.Carry):equal(100)
		end)
		it("never pays past the segment cap, which is the tier's checkpoint coins", function()
			local CourseTable = load("ReplicatedStorage/Tables/CourseTable")
			for name, tier in CourseTable.Tiers do
				-- The Finale pays the finish reward instead of checkpoint coins; GDD 7.5 gives its tricks 10.
				expect(TrickRules.SegmentCap(name)):equal(if name == "Finale" then 10 else tier.CheckpointCoins)
			end
			local ledger = TrickRules.NewLedger()
			local cap = TrickRules.SegmentCap("Hard")
			expect(cap):equal(5)
			-- GDD: a Hard segment that already paid 4 only fits 1 more of the 2 earned.
			TrickRules.Settle(ledger, 3, 800, cap)
			local paid, flags = TrickRules.Settle(ledger, 3, 400, cap)
			expect(paid):equal(1)
			expect(flags.Trimmed):equal(true)
			expect(flags.SegmentCapped):equal(true)
			expect(TrickRules.Settle(ledger, 3, 4000, cap)):equal(0)
			expect(ledger.SegmentCoins[3]):equal(5)
		end)
		it("shares a segment cap between retries but not between segments", function()
			local ledger = TrickRules.NewLedger()
			expect(TrickRules.Settle(ledger, 1, 4000, 2)):equal(2)
			expect(TrickRules.Settle(ledger, 1, 4000, 2)):equal(0)
			expect(TrickRules.Settle(ledger, 2, 4000, 2)):equal(2)
		end)
		it("never pays more than 25 base coins per round", function()
			local ledger = TrickRules.NewLedger()
			local total = 0
			for segment = 1, 12 do
				local paid, flags = TrickRules.Settle(ledger, segment, 100000, 10)
				total += paid
				if total >= 25 then
					expect(flags.RoundCapped):equal(true)
				end
			end
			expect(total):equal(25)
		end)
	end)

	describe("server fit (GDD 7.9)", function()
		it("pays every reported trick that fits the airtime", function()
			local fit = TrickRules.Fit({ "spin", "hellbird" }, 1.9)
			expect(#fit.Entries):equal(2)
			expect(fit.Entries[2].Progress):equal(nil)
			expect(fit.Overshoot):equal(0)
		end)
		it("allows 0.2 s of tolerance on the last trick", function()
			-- available = 0.5 s; Cinder Spin is 0.5 s: fits. A 0.7 s trick ends 0.2 s late: still fits.
			expect(TrickRules.Fit({ "spin" }, MIN_AIRTIME + 0.5).Entries[1].Progress):equal(nil)
			expect(TrickRules.Fit({ "backflip" }, MIN_AIRTIME + 0.5).Entries[1].Progress):equal(nil)
			local late = TrickRules.Fit({ "backflip" }, MIN_AIRTIME + 0.49)
			expect(late.Entries[1].Progress):near(0.7, 1e-9)
			local cut = TrickRules.Fit({ "backflip" }, MIN_AIRTIME + 0.4)
			expect(cut.Entries[1].Progress):near(0.4 / 0.7, 1e-9)
		end)
		it("cuts the trick playing at touchdown and drops what follows", function()
			local fit = TrickRules.Fit({ "backflip", "doubleflip", "tuck" }, MIN_AIRTIME + 1.4)
			expect(#fit.Entries):equal(2)
			expect(fit.Entries[2].Progress):near((1.4 - 0.7) / 1.0, 1e-9)
			expect(fit.Dropped):equal(1)
			expect(fit.Overshoot):equal(0)
		end)
		it("reports how far past the airtime a dropped trick started", function()
			-- available 0.3: tuck (0.4) fits with tolerance, horns would start 0.1 s after touchdown.
			local fit = TrickRules.Fit({ "tuck", "horns", "spin" }, MIN_AIRTIME + 0.3)
			expect(#fit.Entries):equal(1)
			expect(fit.Overshoot):near(0.1, 1e-9)
			expect(fit.Dropped):equal(2)
		end)
		it("flags a start more than 0.5 s past the end of the airtime", function()
			-- tuck (0.4) fits a 0.5 s window with its tolerance, horns starts at 0.4 < 0.5: cut. Use a window of 0.
			local fit = TrickRules.Fit({ "tuck", "horns" }, MIN_AIRTIME - 0.7)
			expect(fit.Overshoot > TrickTable.Server.StrikeOvershootSeconds):truthy()
			expect(#fit.Entries):equal(0)
			local mild = TrickRules.Fit({ "tuck" }, MIN_AIRTIME - 0.3)
			expect(mild.Overshoot > TrickTable.Server.StrikeOvershootSeconds):equal(false)
		end)
	end)

	describe("report validation", function()
		local function report(overrides)
			local base = { trickIds = { "tuck", "horns" }, startedAt = 100, landedAt = 102 }
			for key, value in overrides do
				base[key] = value
			end
			return base
		end
		it("accepts a well-formed report", function()
			local cleaned = TrickRules.ValidateReport(report({}))
			expect(cleaned.TrickIds):equal({ "tuck", "horns" })
		end)
		it("rejects bad shapes", function()
			expect(select(2, TrickRules.ValidateReport(nil))):equal("Shape")
			expect(select(2, TrickRules.ValidateReport("x"))):equal("Shape")
			expect(select(2, TrickRules.ValidateReport(report({ trickIds = {} })))):equal("Shape")
			expect(select(2, TrickRules.ValidateReport(report({ trickIds = { "nope" } })))):equal("Shape")
			expect(select(2, TrickRules.ValidateReport(report({ trickIds = { 5 } })))):equal("Shape")
			expect(select(2, TrickRules.ValidateReport(report({ trickIds = { a = "tuck" } })))):equal("Shape")
			expect(select(2, TrickRules.ValidateReport(report({ startedAt = "1" })))):equal("Shape")
			expect(select(2, TrickRules.ValidateReport(report({ landedAt = 0 / 0 })))):equal("Shape")
			expect(select(2, TrickRules.ValidateReport(report({ landedAt = 99 })))):equal("Shape")
			expect(select(2, TrickRules.ValidateReport(report({ landedAt = 1e9 })))):equal("Shape")
			local many = {}
			for _ = 1, 11 do
				table.insert(many, "tuck")
			end
			expect(select(2, TrickRules.ValidateReport(report({ trickIds = many })))):equal("Shape")
		end)
		it("rejects the same trick twice in a row", function()
			expect(select(2, TrickRules.ValidateReport(report({ trickIds = { "tuck", "tuck" } })))):equal("Repeat")
			expect(TrickRules.ValidateReport(report({ trickIds = { "tuck", "horns", "tuck" } }))):truthy()
		end)
	end)

	describe("sampled trajectories (airtime record)", function()
		local GRAVITY = 196.2
		local RADIUS = 2

		-- Ball centre height over flat ground at y = 0 (rest height = RADIUS), sampled at 10 Hz from `offset`.
		local function jumpSamples(launchSpeed, offset, extra)
			offset = offset or 0
			local samples = {}
			local airSeconds = 2 * launchSpeed / GRAVITY
			for step = 0, math.ceil((airSeconds + 0.5) / 0.1) do
				local time = offset + step * 0.1
				local t = time - 0.05 -- launch happens between sample 0 and 1
				local height, velocity = RADIUS, 0
				if t > 0 and t < airSeconds then
					height = RADIUS + launchSpeed * t - 0.5 * GRAVITY * t * t
					velocity = launchSpeed - GRAVITY * t
				elseif t >= airSeconds then
					velocity = 0
				end
				local sample = {
					Time = time,
					Radius = RADIUS,
					VerticalVelocity = velocity,
					GroundDistance = if height <= RADIUS + 3 then math.max(height, RADIUS) else nil,
				}
				if extra then
					extra(sample, step, t)
				end
				table.insert(samples, sample)
			end
			return samples, airSeconds
		end

		local function run(samples)
			local tracker = TrickRules.NewTracker()
			local events = {}
			for _, sample in samples do
				local event = TrickRules.Feed(tracker, sample)
				if event then
					table.insert(events, event)
				end
			end
			return events
		end

		it("measures a jump pad airtime within the 0.2 s tolerance", function()
			for _, offset in { 0, 0.03, 0.07 } do
				local samples, airSeconds = jumpSamples(186, offset)
				local events = run(samples)
				expect(#events):equal(2)
				expect(events[1].Type):equal("Takeoff")
				expect(events[2].Type):equal("Land")
				expect(math.abs(events[2].Air.Duration - airSeconds) <= TrickTable.Server.FitToleranceSeconds):truthy()
				expect(events[2].Air.Unexplained):equal(false)
			end
		end)

		it("keeps an ordinary single jump under MIN_AIRTIME", function()
			-- Jump 10 style hop: ~0.45 s of air.
			local samples = jumpSamples(44)
			local events = run(samples)
			expect(events[2].Air.Duration < MIN_AIRTIME):truthy()
		end)

		it("pays a replayed jump pad trajectory exactly like the client's worked example", function()
			local samples = jumpSamples(186.4)
			local events = run(samples)
			local air = events[2].Air
			local fit = TrickRules.Fit({ "spin", "hellbird" }, air.Duration)
			local score = TrickRules.Score(fit.Entries)
			expect(score.Points):equal(210)
			expect(score.Grade):equal("Clean")
		end)

		it("flags an unexplained vertical speed gain over 15 studs/s", function()
			local samples = jumpSamples(186, 0, function(sample, step)
				if step >= 8 and sample.GroundDistance == nil then
					sample.VerticalVelocity += 40 -- a mid-air kick with no pad, spring or grapple behind it
				end
			end)
			local events = run(samples)
			-- 40 is added from step 8 on, so only the step into 8 is a gain.
			expect(events[2].Air.Unexplained):equal(true)
		end)

		it("strikes an unexplained airtime only from the second one in a round", function()
			local ledger = TrickRules.NewLedger()
			expect(TrickRules.NoteUnexplained(ledger)):equal(false)
			expect(TrickRules.NoteUnexplained(ledger)):equal(true)
			expect(TrickRules.NoteUnexplained(ledger)):equal(true)
			expect(TrickRules.NoteUnexplained(TrickRules.NewLedger())):equal(false) -- a new round starts clean
		end)

		it("accepts the same gain when an event explains it, or a free double jump covers it", function()
			local function kick(sample, step)
				if step >= 8 and sample.GroundDistance == nil then
					sample.VerticalVelocity += 40
				end
			end
			local explained = jumpSamples(186, 0, function(sample, step)
				kick(sample, step)
				sample.Explained = function()
					return true
				end
			end)
			expect(run(explained)[2].Air.Unexplained):equal(false)
			local doubleJump = jumpSamples(186, 0, function(sample, step)
				kick(sample, step)
				sample.FreeGains = 1
			end)
			expect(run(doubleJump)[2].Air.Unexplained):equal(false)
		end)

		it("does not audit gains near the ground (bounces, moving platforms)", function()
			local samples = jumpSamples(60, 0, function(sample)
				if sample.GroundDistance ~= nil then
					sample.VerticalVelocity += 40
				end
			end)
			expect(run(samples)[2].Air.Unexplained):equal(false)
		end)

		it("treats the airtime as void when a fall lands inside the confirm window", function()
			local events = run(jumpSamples(186))
			local air = events[2].Air
			local confirm = TrickTable.Config.LandConfirm
			expect(TrickRules.IsVoid(air, {}, confirm)):equal(false)
			expect(TrickRules.IsVoid(air, { air.EndT + 0.4 }, confirm)):equal(true)
			expect(TrickRules.IsVoid(air, { air.EndT + 0.6 }, confirm)):equal(false)
			expect(TrickRules.IsVoid(air, { air.StartT + 0.5 }, confirm)):equal(true)
			expect(TrickRules.IsVoid(air, { air.StartT - 0.5 }, confirm)):equal(false)
		end)

		it("matches assist windows that overlap the airtime", function()
			local windows = { Glider = { From = 5, Until = 6 } }
			expect(TrickRules.AssistedIn(windows, 4, 5.5)):equal(true)
			expect(TrickRules.AssistedIn(windows, 6.1, 7)):equal(false)
			expect(TrickRules.AssistedIn({}, 0, 100)):equal(false)
		end)
	end)
end)

describe("TrickShopRules", function()
	local TrickShopRules = load("ReplicatedStorage/Shared/TrickShopRules")
	local TrickTable = load("ReplicatedStorage/Tables/TrickTable")

	it("buys a coin trick once", function()
		local ok, _, price = TrickShopRules.DecideBuy("hellbird", { Owned = {}, Coins = 750 })
		expect(ok):equal(true)
		expect(price):equal(750)
		expect(select(2, TrickShopRules.DecideBuy("hellbird", { Owned = { hellbird = true }, Coins = 9999 }))):equal(
			"Owned"
		)
		expect(select(2, TrickShopRules.DecideBuy("hellbird", { Owned = {}, Coins = 749 }))):equal("NoFunds")
	end)
	it("refuses unknown, free and Robux tricks for coins", function()
		expect(select(2, TrickShopRules.DecideBuy(7, { Owned = {}, Coins = 1e6 }))):equal("Unknown")
		expect(select(2, TrickShopRules.DecideBuy("nope", { Owned = {}, Coins = 1e6 }))):equal("Unknown")
		expect(select(2, TrickShopRules.DecideBuy("tuck", { Owned = {}, Coins = 1e6 }))):equal("NotBuyable")
		expect(select(2, TrickShopRules.DecideBuy("throne", { Owned = {}, Coins = 1e6 }))):equal("NotBuyable")
	end)
	it("prices upgrades by tier and stops at L3", function()
		local ok, _, price, level = TrickShopRules.DecideUpgrade("tuck", { Owned = {}, Levels = {}, Coins = 300 })
		expect(ok):equal(true)
		expect(price):equal(TrickTable.Upgrades.Free.L2)
		expect(level):equal(2)
		local _, _, price3, level3 =
			TrickShopRules.DecideUpgrade("tuck", { Owned = {}, Levels = { tuck = 2 }, Coins = 900 })
		expect(price3):equal(900)
		expect(level3):equal(3)
		expect(select(2, TrickShopRules.DecideUpgrade("tuck", { Owned = {}, Levels = { tuck = 3 }, Coins = 1e6 }))):equal(
			"MaxLevel"
		)
		expect(select(2, TrickShopRules.DecideUpgrade("tuck", { Owned = {}, Levels = {}, Coins = 299 }))):equal(
			"NoFunds"
		)
		expect(select(2, TrickShopRules.DecideUpgrade("hellbird", { Owned = {}, Levels = {}, Coins = 1e6 }))):equal(
			"NotOwned"
		)
	end)
	it("validates a loadout against ownership and slot count", function()
		local owned = { hellbird = true }
		expect(TrickShopRules.DecideEquip({ "tuck", "hellbird" }, owned)):equal({ "tuck", "hellbird", "", "" })
		expect(TrickShopRules.DecideEquip({ "", "horns", "", "spin" }, owned)):equal({ "", "horns", "", "spin" })
		expect(select(2, TrickShopRules.DecideEquip({ "tuck", "tuck" }, owned))):equal("Duplicate")
		expect(select(2, TrickShopRules.DecideEquip({ "throne" }, owned))):equal("NotOwned")
		expect(select(2, TrickShopRules.DecideEquip({ "zzz" }, owned))):equal("Unknown")
		expect(select(2, TrickShopRules.DecideEquip({ "tuck", "horns", "spin", "hellbird", "tuck" }, owned))):equal(
			"Shape"
		)
		expect(select(2, TrickShopRules.DecideEquip("tuck", owned))):equal("Shape")
		expect(select(2, TrickShopRules.DecideEquip({ 5 }, owned))):equal("Shape")
	end)
end)
