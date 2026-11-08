describe("ModifierService.ModifierRules", function()
	local Rules = load("ServerScriptService/Script/ModifierService/ModifierRules")
	local ModifierTable = load("ReplicatedStorage/Tables/ModifierTable")
	local mods = ModifierTable.Modifiers
	local troll = ModifierTable.TrollRules

	local function state(overrides)
		local base = {
			Now = 1000,
			InRace = true,
			CountThisRound = 0,
			ClockAdded = 0,
			RaceClockBase = 1200,
			TrollCount = 0,
		}
		for key, value in overrides or {} do
			base[key] = value
		end
		return base
	end

	describe("server modifiers", function()
		it("starts when idle and racing", function()
			local ok, mode = Rules.Evaluate(mods.LowGravity, troll, state())
			expect(ok):truthy()
			expect(mode):equal("Start")
		end)

		it("refuses outside the race", function()
			local ok, reason = Rules.Evaluate(mods.LowGravity, troll, state({ InRace = false }))
			expect(ok):falsy()
			expect(reason):equal("NotRacing")
		end)

		it("extends while active and refuses once the stack cap is reached", function()
			local ok, mode = Rules.Evaluate(mods.LowGravity, troll, state({ ActiveEndsAt = 1050 }))
			expect(ok):truthy()
			expect(mode):equal("Extend")
			local full, reason = Rules.Evaluate(mods.LowGravity, troll, state({ ActiveEndsAt = 1120 }))
			expect(full):falsy()
			expect(reason):equal("StackFull")
		end)

		it("caps the extended remaining time", function()
			expect(Rules.ExtendedRemaining(50, 60, 120)):equal(110)
			expect(Rules.ExtendedRemaining(90, 60, 120)):equal(120)
			expect(Rules.ExtendedRemaining(-5, 60, 120)):equal(60)
		end)

		it("blocks during the cooldown after it ended and allows after", function()
			local ok, reason = Rules.Evaluate(mods.GiantBalls, troll, state({ CooldownUntil = 1010 }))
			expect(ok):falsy()
			expect(reason):equal("Cooldown")
			expect((Rules.Evaluate(mods.GiantBalls, troll, state({ CooldownUntil = 1000 })))):truthy()
		end)

		it("enforces MaxPerRound", function()
			local ok, reason = Rules.Evaluate(mods.GiantBalls, troll, state({ CountThisRound = 3 }))
			expect(ok):falsy()
			expect(reason):equal("RoundCap")
		end)

		it("+2 minutes is instant, has a cooldown and stops at the clock cap", function()
			local ok, mode = Rules.Evaluate(mods.PlusTwoMinutes, troll, state())
			expect(ok):truthy()
			expect(mode):equal("Instant")
			expect(select(2, Rules.Evaluate(mods.PlusTwoMinutes, troll, state({ CooldownUntil = 1030 })))):equal(
				"Cooldown"
			)
			expect(select(2, Rules.Evaluate(mods.PlusTwoMinutes, troll, state({ ClockAdded = 240 })))):equal("Instant")
			expect(select(2, Rules.Evaluate(mods.PlusTwoMinutes, troll, state({ ClockAdded = 360 })))):equal("ClockCap")
		end)
	end)

	describe("trolls", function()
		it("allows one when nothing blocks it", function()
			local ok, mode = Rules.Evaluate(mods.SlowEveryone, troll, state())
			expect(ok):truthy()
			expect(mode):equal("Start")
		end)

		it("blocks a second troll within the 90 s server cooldown", function()
			local ok, reason = Rules.Evaluate(mods.ShrinkEveryone, troll, state({ TrollCooldownUntil = 1000 + 89 }))
			expect(ok):falsy()
			expect(reason):equal("Cooldown")
			expect((Rules.Evaluate(mods.ShrinkEveryone, troll, state({ TrollCooldownUntil = 1000 })))):truthy()
		end)

		it("blocks while a troll is active, even the same one (no extending)", function()
			local ok, reason = Rules.Evaluate(mods.SlowEveryone, troll, state({ TrollActiveEndsAt = 1010 }))
			expect(ok):falsy()
			expect(reason):equal("TrollActive")
		end)

		it("caps trolls per round", function()
			local ok, reason = Rules.Evaluate(mods.SlowEveryone, troll, state({ TrollCount = troll.MaxPerRound }))
			expect(ok):falsy()
			expect(reason):equal("RoundCap")
		end)

		it("limits one buyer to one troll per interval at prompt time only", function()
			local ok, reason = Rules.Evaluate(mods.SlowEveryone, troll, state({ BuyerLastTrollAt = 1000 - 100 }))
			expect(ok):falsy()
			expect(reason):equal("BuyerInterval")
			expect((Rules.Evaluate(mods.SlowEveryone, troll, state({ BuyerLastTrollAt = 1000 - 181 })))):truthy()
			expect((Rules.Evaluate(mods.SlowEveryone, troll, state()))):truthy()
		end)
	end)

	describe("immunity", function()
		local function ctx(overrides)
			local base = {
				IsBuyer = false,
				Checkpoint = 3,
				SegmentCount = 30,
				Now = 10000,
				FirstJoinAt = 1000,
				Rules = troll,
			}
			for key, value in overrides or {} do
				base[key] = value
			end
			return base
		end

		it("is not granted to an ordinary player", function()
			expect((Rules.TrollImmunity(ctx()))):falsy()
		end)

		it("protects the buyer", function()
			local immune, reason = Rules.TrollImmunity(ctx({ IsBuyer = true }))
			expect(immune):truthy()
			expect(reason):equal("Buyer")
		end)

		it("protects players on slot 30 (checkpoint 29 and 30) but not slot 29", function()
			expect(select(2, Rules.TrollImmunity(ctx({ Checkpoint = 29 })))):equal("Finale")
			expect(select(2, Rules.TrollImmunity(ctx({ Checkpoint = 30 })))):equal("Finale")
			expect((Rules.TrollImmunity(ctx({ Checkpoint = 28 })))):falsy()
			expect((Rules.TrollImmunity(ctx({ Checkpoint = nil })))):falsy()
		end)

		it("protects new players for ten minutes from firstJoinAt", function()
			expect(select(2, Rules.TrollImmunity(ctx({ FirstJoinAt = 10000 - 599 })))):equal("NewPlayer")
			expect((Rules.TrollImmunity(ctx({ FirstJoinAt = 10000 - 600 })))):falsy()
		end)

		it("treats unloaded data as a new player", function()
			expect(Rules.IsNewPlayer(10000, nil, 600)):truthy()
			expect(Rules.IsNewPlayer(10000, 0, 600)):truthy()
		end)
	end)

	describe("table consistency", function()
		it("every product's ModifierId exists in ModifierTable", function()
			local ProductTable = load("ReplicatedStorage/Tables/ProductTable")
			for key, row in ProductTable do
				if row.Family == "Modifiers" then
					expect(mods[row.Params.ModifierId] ~= nil):truthy()
					expect(row.Params.ModifierId):equal(key)
				end
			end
		end)
	end)
end)
