describe("UpsellRules", function()
	local Rules = load("ServerScriptService/Script/UpsellService/UpsellRules")
	local UpsellTable = load("ReplicatedStorage/Tables/UpsellTable")
	local FlagResolve = load("ServerScriptService/Script/FlagService/Resolve")

	local function gateInput(overrides)
		local input = {
			Kind = "Popup",
			Type = "FallsOnSegment",
			Enabled = true,
			Cap = 3,
			Shown = 0,
			Now = 1000,
			LastPopupAt = nil,
			MinSpacing = 90,
			IsFirstSession = false,
			SessionAge = 5000,
			QuietSeconds = 180,
			QuietExempt = false,
			Countdown = false,
			NoneDuringCountdown = true,
			SegmentShown = {},
			MaxPerSegment = 1,
		}
		for key, value in overrides or {} do
			input[key] = value
		end
		return input
	end

	describe("spacing (GDD 13: 1 popup per 90 s)", function()
		it("blocks a second popup inside 90 s and allows it at 90 s", function()
			local ok, reason = Rules.Gate(gateInput({ LastPopupAt = 950 }))
			expect(ok):falsy()
			expect(reason):equal("Spacing")
			expect(Rules.Gate(gateInput({ LastPopupAt = 910 }))):truthy()
		end)

		it("follows the flag value", function()
			expect(Rules.Gate(gateInput({ LastPopupAt = 950, MinSpacing = 30 }))):truthy()
		end)

		it("does not space inline offers or results cards", function()
			expect(Rules.Gate(gateInput({ Kind = "Inline", LastPopupAt = 999, Cap = 0 }))):truthy()
			expect(Rules.Gate(gateInput({ Kind = "Results", LastPopupAt = 999 }))):truthy()
		end)

		it("never lets two popups through within 90 s across any triggers", function()
			local lastPopupAt = nil
			local shown = 0
			for second = 0, 600 do
				local ok = Rules.Gate(gateInput({ Now = second, LastPopupAt = lastPopupAt, Cap = 1000, Shown = 0 }))
				if ok then
					if lastPopupAt then
						expect(second - lastPopupAt >= 90):truthy()
					end
					lastPopupAt = second
					shown += 1
				end
			end
			expect(shown):equal(7)
		end)
	end)

	describe("session caps", function()
		it("stops at the cap", function()
			local ok, reason = Rules.Gate(gateInput({ Shown = 3 }))
			expect(ok):falsy()
			expect(reason):equal("Cap")
			expect(Rules.Gate(gateInput({ Shown = 2 }))):truthy()
		end)

		it("treats cap 0 as no popup, but inline offers still go", function()
			expect(Rules.Gate(gateInput({ Cap = 0 }))):falsy()
			expect(Rules.Gate(gateInput({ Cap = 0, Kind = "Inline" }))):truthy()
		end)

		it("honours each UpsellTable cap for every popup trigger", function()
			for _, row in UpsellTable.Triggers do
				local kind = Rules.KindOf(row)
				if kind == "Popup" then
					local input = gateInput({ Cap = row.CapPerSession, Shown = row.CapPerSession })
					expect(Rules.Gate(input)):falsy()
				end
			end
		end)
	end)

	describe("flags", function()
		it("a disabled trigger never offers, even inline", function()
			local ok, reason = Rules.Gate(gateInput({ Enabled = false }))
			expect(ok):falsy()
			expect(reason):equal("Disabled")
			expect(Rules.Gate(gateInput({ Enabled = false, Kind = "Inline" }))):falsy()
		end)
	end)

	describe("global rules", function()
		it("is silent during the countdown", function()
			local ok, reason = Rules.Gate(gateInput({ Countdown = true }))
			expect(ok):falsy()
			expect(reason):equal("Countdown")
		end)

		it("keeps the first session quiet except the exempt trigger", function()
			local quiet = gateInput({ IsFirstSession = true, SessionAge = 60 })
			local ok, reason = Rules.Gate(quiet)
			expect(ok):falsy()
			expect(reason):equal("Quiet")
			quiet.QuietExempt = true
			expect(Rules.Gate(quiet)):truthy()
			expect(Rules.Gate(gateInput({ IsFirstSession = true, SessionAge = 181 }))):truthy()
			expect(Rules.Gate(gateInput({ IsFirstSession = false, SessionAge = 5 }))):truthy()
		end)

		it("allows one popup per segment, but fall triggers may escalate on one", function()
			expect(Rules.SegmentAllows({}, "ClockLeft", 1)):truthy()
			expect(Rules.SegmentAllows({ "ClockLeft" }, "ClockLeft", 1)):falsy()
			expect(Rules.SegmentAllows({ "ClockLeft" }, "FallsOnSegment", 1)):falsy()
			expect(Rules.SegmentAllows({ "FallsOnSegment" }, "ClockLeft", 1)):falsy()
			expect(Rules.SegmentAllows({ "FallsOnSegment" }, "FallsOnSegment", 1)):truthy()
		end)
	end)

	describe("offers", function()
		it("puts the preferred order first and keeps the rest", function()
			local offers = { "ToolRefill", "SkipSegment" }
			expect(Rules.OrderOffers(offers, { "SkipSegment", "ToolRefill" })):equal({ "SkipSegment", "ToolRefill" })
			expect(Rules.OrderOffers(offers, nil)):equal(offers)
			expect(Rules.OrderOffers(offers, { "Bogus", "SkipSegment" })):equal({ "SkipSegment", "ToolRefill" })
		end)

		it("skips an offer that cannot be prompted and moves to the next", function()
			local canPrompt = { ToolRefill = false, SkipSegment = true }
			local function check(key)
				return canPrompt[key]
			end
			expect(Rules.PickOffers({ "ToolRefill", "SkipSegment" }, check, true)):equal({ "SkipSegment" })
		end)

		it("offers nothing when nothing can be prompted", function()
			expect(#Rules.PickOffers({ "ToolRefill", "SkipSegment" }, function()
				return false
			end, true)):equal(0)
		end)

		it("single mode stops at the first offerable, otherwise all offerable are kept", function()
			local function yes()
				return true
			end
			expect(Rules.PickOffers({ "Spins1", "Spins5", "Spins15" }, yes, true)):equal({ "Spins1" })
			expect(Rules.PickOffers({ "Spins1", "Spins5", "Spins15" }, yes, false)):equal({
				"Spins1",
				"Spins5",
				"Spins15",
			})
		end)
	end)

	describe("FallsThree A/B order", function()
		local FallsThreeOrder = load("ServerScriptService/Script/FlagService/Flags/UpsellFallsThreeOrder")
		local row
		for _, candidate in UpsellTable.Triggers do
			if candidate.Id == "FallsThree" then
				row = candidate
			end
		end

		it("both variants order the same two offers", function()
			expect(Rules.OrderOffers(row.Offers, FallsThreeOrder.States.ShieldFirst)):equal({
				"ToolRefill",
				"SkipSegment",
			})
			expect(Rules.OrderOffers(row.Offers, FallsThreeOrder.States.SkipFirst)):equal({
				"SkipSegment",
				"ToolRefill",
			})
		end)

		it("the variant never changes which offers exist", function()
			for _, order in FallsThreeOrder.States do
				local ordered = Rules.OrderOffers(row.Offers, order)
				expect(#ordered):equal(#row.Offers)
			end
		end)

		it("buckets a player stably", function()
			expect(FlagResolve.Variant(FallsThreeOrder, 12345, nil)):equal(
				FlagResolve.Variant(FallsThreeOrder, 12345, nil)
			)
		end)
	end)

	describe("falls threshold", function()
		it("fires at the threshold, not before", function()
			expect(Rules.FallsReached(2, 3, "r1:4", nil)):falsy()
			expect(Rules.FallsReached(3, 3, "r1:4", nil)):truthy()
		end)

		it("fires once per segment and resets on a new segment or round", function()
			expect(Rules.FallsReached(4, 3, "r1:4", "r1:4")):falsy()
			expect(Rules.FallsReached(3, 3, "r1:5", "r1:4")):truthy()
			expect(Rules.FallsReached(3, 3, "r2:4", "r1:4")):truthy()
		end)

		it("reads its thresholds from the table", function()
			local falls = {}
			for _, row in UpsellTable.Triggers do
				if row.Type == "FallsOnSegment" then
					falls[row.Id] = row.Params.Falls
				end
			end
			expect(falls):equal({ FallsThree = 3, FallsFive = 5, FallsEight = 8 })
		end)
	end)

	describe("clock and finish", function()
		it("is low under the threshold and while time remains", function()
			expect(Rules.ClockLow(59, 60)):truthy()
			expect(Rules.ClockLow(60, 60)):falsy()
			expect(Rules.ClockLow(0, 60)):falsy()
		end)

		it("is near the finish within the minimum slots", function()
			expect(Rules.NearFinish(27, 30, 3)):truthy()
			expect(Rules.NearFinish(29, 30, 3)):truthy()
			expect(Rules.NearFinish(26, 30, 3)):falsy()
		end)
	end)

	describe("limited-stock toast", function()
		it("toasts once below the threshold, then once per interval", function()
			expect(Rules.ToastDue(150, 100, nil, 0, 600)):falsy()
			expect(Rules.ToastDue(99, 100, nil, 0, 600)):truthy()
			expect(Rules.ToastDue(98, 100, 0, 300, 600)):falsy()
			expect(Rules.ToastDue(98, 100, 0, 600, 600)):truthy()
		end)

		it("stays quiet when sold out or unknown", function()
			expect(Rules.ToastDue(0, 100, nil, 0, 600)):falsy()
			expect(Rules.ToastDue(nil, 100, nil, 0, 600)):falsy()
		end)
	end)

	describe("Offerable", function()
		it("lets false veto and nil fall through to the product check", function()
			expect(Rules.Offerable(false, true)):falsy()
			expect(Rules.Offerable(nil, true)):truthy()
			expect(Rules.Offerable(nil, false)):falsy()
			expect(Rules.Offerable(nil, nil)):falsy()
		end)
		it("never lets Eligible true bypass an unbuyable product or pass", function()
			expect(Rules.Offerable(true, false)):falsy()
			expect(Rules.Offerable(true, true)):truthy()
		end)
		it("lets true stand alone for keys with no product (Coins)", function()
			expect(Rules.Offerable(true, nil)):truthy()
		end)
	end)

	describe("season", function()
		local premium = { [1] = { {} }, [2] = { {} }, [3] = {}, [4] = { {} } }

		it("counts only tiers that have a premium reward", function()
			expect(Rules.NthLockedPremiumTier(premium, 1, { 1, 10 })):truthy()
			expect(Rules.NthLockedPremiumTier(premium, 2, { 1, 10 })):falsy()
			expect(Rules.NthLockedPremiumTier(premium, 3, { 1, 2, 3 })):falsy()
			expect(Rules.NthLockedPremiumTier(premium, 4, { 3 })):truthy()
		end)

		it("is behind pace only in the last days", function()
			expect(Rules.SeasonBehind(10, 20, 3 * 86400, 5, 7)):truthy()
			expect(Rules.SeasonBehind(10, 20, 10 * 86400, 5, 7)):falsy()
			expect(Rules.SeasonBehind(15, 20, 3 * 86400, 5, 7)):falsy()
			expect(Rules.SeasonBehind(1, 20, 0, 5, 7)):falsy()
		end)
	end)
end)
