describe("PurchaseService.ReceiptRules", function()
	local ReceiptRules = load("ServerScriptService/Script/PurchaseService/ReceiptRules")

	local function facts(overrides)
		local base = { Known = true, InServer = true, Loaded = true, Logged = false, InFlight = false }
		for key, value in overrides or {} do
			base[key] = value
		end
		return base
	end

	local function counted(result)
		local calls = 0
		return function()
			calls += 1
			return result
		end, function()
			return calls
		end
	end

	it("retries unknown products without running the effect", function()
		local run, calls = counted(true)
		local outcome, reason = ReceiptRules.Decide(facts({ Known = false }), run)
		expect(outcome):equal("NotYet")
		expect(reason):equal("UnknownProduct")
		expect(calls()):equal(0)
	end)

	it("retries when the player left or data is not loaded", function()
		local run, calls = counted(true)
		expect(select(2, ReceiptRules.Decide(facts({ InServer = false }), run))):equal("PlayerGone")
		local outcome, reason = ReceiptRules.Decide(facts({ Loaded = false }), run)
		expect(outcome):equal("NotYet")
		expect(reason):equal("NotLoaded")
		expect(calls()):equal(0)
	end)

	it("grants a logged PurchaseId without running the effect again", function()
		local run, calls = counted(true)
		local outcome, reason = ReceiptRules.Decide(facts({ Logged = true }), run)
		expect(outcome):equal("Granted")
		expect(reason):equal("Duplicate")
		expect(calls()):equal(0)
	end)

	it("refuses a receipt whose effect is still running", function()
		local run, calls = counted(true)
		local outcome, reason = ReceiptRules.Decide(facts({ InFlight = true }), run)
		expect(outcome):equal("NotYet")
		expect(reason):equal("InFlight")
		expect(calls()):equal(0)
	end)

	it("grants when the effect returns true", function()
		local run, calls = counted(true)
		local outcome, reason = ReceiptRules.Decide(facts(), run)
		expect(outcome):equal("Granted")
		expect(reason):equal("Granted")
		expect(calls()):equal(1)
	end)

	it("retries when the effect returns false or anything but true", function()
		for _, result in { false, "yes", 1 } do
			local run = counted(result)
			local outcome, reason = ReceiptRules.Decide(facts(), run)
			expect(outcome):equal("NotYet")
			expect(reason):equal("EffectDeclined")
		end
	end)

	it("retries when the effect errors and reports the error", function()
		local outcome, reason, detail = ReceiptRules.Decide(facts(), function()
			error("boom", 0)
		end)
		expect(outcome):equal("NotYet")
		expect(reason):equal("EffectError")
		expect(detail):equal("boom")
	end)

	describe("purchaseLog", function()
		it("appends without mutating the input", function()
			local log = { "a" }
			local out = ReceiptRules.AppendLog(log, "b", 5)
			expect(out):equal({ "a", "b" })
			expect(log):equal({ "a" })
		end)

		it("drops the oldest past the cap", function()
			local out = { "a", "b", "c" }
			out = ReceiptRules.AppendLog(out, "d", 3)
			expect(out):equal({ "b", "c", "d" })
		end)

		it("does not duplicate a known id", function()
			expect(ReceiptRules.AppendLog({ "a", "b" }, "a", 5)):equal({ "a", "b" })
		end)

		it("finds logged ids", function()
			expect(ReceiptRules.HasPurchase({ "a" }, "a")):truthy()
			expect(ReceiptRules.HasPurchase({ "a" }, "z")):falsy()
		end)
	end)
end)
