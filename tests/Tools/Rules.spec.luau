describe("ToolService.Rules", function()
	local Rules = load("ServerScriptService/Script/ToolService/Rules")
	local ToolTable = load("ReplicatedStorage/Tables/ToolTable")
	local CourseTable = load("ReplicatedStorage/Tables/CourseTable")
	local config = ToolTable.Config

	local function input(overrides)
		local base = {
			ToolId = "shield",
			Slot = 1,
			SlotCount = 2,
			Owned = false,
			Stored = 3,
			FreeLeft = 0,
			TempCharges = 0,
			Now = 100,
			ToolReadyAt = 0,
			GlobalReadyAt = 0,
			SegmentUses = 0,
			SegmentCap = nil,
			RoundState = "Race",
			Racing = true,
			NoTools = false,
			ToolsAllowed = nil,
		}
		for key, value in overrides or {} do
			base[key] = value
		end
		return base
	end

	describe("Decide: every rejection in GDD 13", function()
		it("accepts a normal press and says which charge pays", function()
			local ok, reason, source = Rules.Decide(input())
			expect(ok):equal(true)
			expect(reason):equal(nil)
			expect(source):equal("Stored")
		end)

		it("rejects an empty or out-of-range slot", function()
			expect(select(2, Rules.Decide(input({ ToolId = "" })))):equal("NoTool")
			expect(select(2, Rules.Decide(input({ Slot = 3 })))):equal("NoTool")
			expect(select(2, Rules.Decide(input({ Slot = 0 })))):equal("NoTool")
		end)

		it("rejects during the countdown and every other non-race state", function()
			for _, state in { "Countdown", "Intermission", "BuildCourse", "Results", "Teardown" } do
				expect(select(2, Rules.Decide(input({ RoundState = state })))):equal("NotRacing")
			end
			expect(select(2, Rules.Decide(input({ Racing = false })))):equal("NotRacing")
		end)

		it("rejects in a NoTools segment", function()
			expect(select(2, Rules.Decide(input({ NoTools = true })))):equal("NoTools")
		end)

		it("rejects a tool the ToolsAllowed whitelist leaves out", function()
			local allowed = Rules.ParseAllowed("grapple, glider")
			expect(select(2, Rules.Decide(input({ ToolsAllowed = allowed })))):equal("NotAllowed")
			expect(Rules.Decide(input({ ToolId = "grapple", ToolsAllowed = allowed }))):equal(true)
		end)

		it("rejects without ownership or charges", function()
			expect(select(2, Rules.Decide(input({ Stored = 0 })))):equal("NotOwned")
		end)

		it("rejects an owned tool that has run out of charges", function()
			expect(select(2, Rules.Decide(input({ Owned = true, Stored = 0, FreeLeft = 0 })))):equal("NoCharges")
		end)

		it("rejects on the tool's cooldown and on the global cooldown", function()
			expect(select(2, Rules.Decide(input({ ToolReadyAt = 101 })))):equal("Cooldown")
			expect(select(2, Rules.Decide(input({ GlobalReadyAt = 100.5 })))):equal("Cooldown")
			expect(Rules.Decide(input({ ToolReadyAt = 100, GlobalReadyAt = 100 }))):equal(true)
		end)

		it("rejects over the per-segment cap and accepts below it", function()
			expect(select(2, Rules.Decide(input({ SegmentCap = 2, SegmentUses = 2 })))):equal("SegmentCap")
			expect(Rules.Decide(input({ SegmentCap = 2, SegmentUses = 1 }))):equal(true)
		end)

		it("reports the first failing check in a fixed order", function()
			local everythingWrong = input({
				RoundState = "Countdown",
				NoTools = true,
				Stored = 0,
				ToolReadyAt = 999,
				SegmentCap = 1,
				SegmentUses = 1,
			})
			expect(select(2, Rules.Decide(everythingWrong))):equal("NotRacing")
			everythingWrong.RoundState = "Race"
			expect(select(2, Rules.Decide(everythingWrong))):equal("NoTools")
			everythingWrong.NoTools = false
			expect(select(2, Rules.Decide(everythingWrong))):equal("NotOwned")
			everythingWrong.Stored = 1
			expect(select(2, Rules.Decide(everythingWrong))):equal("Cooldown")
			everythingWrong.ToolReadyAt = 0
			expect(select(2, Rules.Decide(everythingWrong))):equal("SegmentCap")
		end)
	end)

	describe("ToolRequired pickup slot (GDD 6.6)", function()
		local function runtimeWithTemp(toolId, segment, charges)
			local rt = Rules.NewRuntime()
			Rules.RefreshTemp(rt, segment, toolId)
			rt.Temp.Charges = charges
			return rt
		end

		it("resolves the pseudo-slot to the segment's temp tool", function()
			local rt = runtimeWithTemp("grapple", 7, 1)
			local toolId, isTemp = Rules.ResolveUse(Rules.TEMP_SLOT, { "shield", "", "" }, rt, 7)
			expect(toolId):equal("grapple")
			expect(isTemp):equal(true)
		end)
		it("resolves to nothing for another segment or a spent charge", function()
			expect(Rules.ResolveUse(Rules.TEMP_SLOT, {}, runtimeWithTemp("grapple", 7, 1), 8)):equal("")
			expect(Rules.ResolveUse(Rules.TEMP_SLOT, {}, runtimeWithTemp("grapple", 7, 0), 7)):equal("")
			expect(Rules.ResolveUse(Rules.TEMP_SLOT, {}, Rules.NewRuntime(), 7)):equal("")
		end)
		it("resolves a normal slot from the loadout", function()
			local toolId, isTemp = Rules.ResolveUse(2, { "shield", "rocket", "" }, Rules.NewRuntime(), 1)
			expect(toolId):equal("rocket")
			expect(isTemp):equal(false)
			expect(Rules.ResolveUse(3, { "shield" }, Rules.NewRuntime(), 1)):equal("")
		end)
		it("lets someone who owns nothing use the pickup, and spends only the temp charge", function()
			local ok, reason, source = Rules.Decide(input({
				ToolId = "grapple",
				Slot = Rules.TEMP_SLOT,
				TempSlot = true,
				TempCharges = 1,
				Stored = 0,
				Owned = false,
			}))
			expect(ok):equal(true)
			expect(reason):equal(nil)
			expect(source):equal("Temp")
		end)
		it("refuses the pseudo-slot without a temp charge, and slot 0 on its own", function()
			expect(select(2, Rules.Decide(input({ Slot = 0, TempSlot = true, TempCharges = 0 })))):equal("NoTool")
			expect(select(2, Rules.Decide(input({ Slot = 0 })))):equal("NoTool")
		end)
		it("still applies the race, cooldown and cap checks to the pickup", function()
			local pickup = { ToolId = "grapple", Slot = 0, TempSlot = true, TempCharges = 1, Stored = 0 }
			expect(select(
				2,
				Rules.Decide(input({
					RoundState = "Countdown",
					ToolId = "grapple",
					Slot = 0,
					TempSlot = true,
					TempCharges = 1,
					Stored = 0,
				}))
			)):equal("NotRacing")
			pickup.ToolReadyAt = 101
			expect(select(2, Rules.Decide(input(pickup)))):equal("Cooldown")
		end)
	end)

	describe("caps per tier (GDD 6.6)", function()
		it("matches the guardrail table", function()
			local expected = { Beginner = nil, Easy = nil, Medium = nil, Hard = 3, Insane = 2, Hell = 1, Finale = 1 }
			for tier in CourseTable.Tiers do
				expect(Rules.SegmentCap(CourseTable.Tiers[tier])):equal(expected[tier])
			end
		end)
	end)

	describe("charge spending order", function()
		it("spends the temporary charge, then free, then stored", function()
			expect(Rules.PlanSpend({ Temp = 1, Free = 2, Stored = 5 })):equal("Temp")
			expect(Rules.PlanSpend({ Temp = 0, Free = 2, Stored = 5 })):equal("Free")
			expect(Rules.PlanSpend({ Temp = 0, Free = 0, Stored = 5 })):equal("Stored")
			expect(Rules.PlanSpend({ Temp = 0, Free = 0, Stored = 0 })):equal(nil)
		end)

		it("uses free charges before stored ones across a sequence of presses", function()
			local rt = Rules.NewRuntime()
			local def = ToolTable.Tools.brake -- 3 free per round
			local stored = 2
			local sources = {}
			for press = 1, 6 do
				local left = Rules.FreeLeft(def, true, false, rt.FreeUsed.brake)
				local source = Rules.PlanSpend({ Free = left, Stored = stored })
				table.insert(sources, source or "none")
				if source == "Stored" then
					stored -= 1
				end
				if source then
					Rules.Record(rt, "brake", 1, source, press * 100, def.Cooldown, config.GlobalCooldown)
				end
			end
			expect(sources):equal({ "Free", "Free", "Free", "Stored", "Stored", "none" })
		end)

		it("gives free charges only to owned tools and lifts the limit with the pass", function()
			local def = ToolTable.Tools.rocket
			expect(Rules.FreeLeft(def, false, false, 0)):equal(0)
			expect(Rules.FreeLeft(def, true, false, 0)):equal(def.FreeCharges)
			expect(Rules.FreeLeft(def, true, false, 99)):equal(0)
			expect(Rules.FreeLeft(def, true, true, 99)):equal(math.huge)
		end)
	end)

	describe("Record and the per-round reset", function()
		it("starts the cooldowns and counts the use in its segment", function()
			local rt = Rules.NewRuntime()
			Rules.Record(rt, "spring", 7, "Free", 50, 15, 2)
			expect(rt.CooldownEnds.spring):equal(65)
			expect(rt.GlobalEnd):equal(52)
			expect(Rules.UsesInSegment(rt, 7)):equal(1)
			expect(Rules.UsesInSegment(rt, 7, "spring")):equal(1)
			expect(Rules.UsesInSegment(rt, 7, "rocket")):equal(0)
			expect(Rules.UsesInSegment(rt, 8)):equal(0)
		end)

		it("restores free charges, cooldowns, uses and refills every round", function()
			local rt = Rules.NewRuntime()
			Rules.Record(rt, "brake", 1, "Free", 10, 8, 2)
			rt.RefillsUsed.brake = 1
			Rules.RefreshTemp(rt, 1, "grapple")
			Rules.ResetRound(rt)
			expect(Rules.FreeLeft(ToolTable.Tools.brake, true, false, rt.FreeUsed.brake)):equal(3)
			expect(rt.CooldownEnds.brake):equal(nil)
			expect(rt.GlobalEnd):equal(0)
			expect(Rules.UsesInSegment(rt, 1)):equal(0)
			expect(rt.RefillsUsed.brake):equal(nil)
			expect(Rules.TempCharges(rt, "grapple", 1)):equal(0)
		end)
	end)

	describe("ToolRequired temporary charge", function()
		it("gives 1 charge at the segment's start", function()
			local rt = Rules.NewRuntime()
			Rules.RefreshTemp(rt, 13, "grapple")
			expect(Rules.TempCharges(rt, "grapple", 13)):equal(1)
			expect(Rules.TempCharges(rt, "glider", 13)):equal(0)
		end)

		it("is spent by a use and refilled by a respawn in the same segment", function()
			local rt = Rules.NewRuntime()
			Rules.RefreshTemp(rt, 13, "grapple")
			Rules.Record(rt, "grapple", 13, "Temp", 10, 12, 2)
			expect(Rules.TempCharges(rt, "grapple", 13)):equal(0)
			Rules.RefreshTemp(rt, 13, "grapple") -- respawn
			expect(Rules.TempCharges(rt, "grapple", 13)):equal(1)
		end)

		it("is lost when the player leaves the segment", function()
			local rt = Rules.NewRuntime()
			Rules.RefreshTemp(rt, 13, "grapple")
			expect(Rules.TempCharges(rt, "grapple", 14)):equal(0)
			Rules.RefreshTemp(rt, 14, nil)
			expect(Rules.TempCharges(rt, "grapple", 13)):equal(0)
		end)

		it("lets an unowned, uncharged player use the pickup", function()
			local rt = Rules.NewRuntime()
			Rules.RefreshTemp(rt, 13, "grapple")
			local ok, _, source = Rules.Decide(input({
				ToolId = "grapple",
				Stored = 0,
				TempCharges = Rules.TempCharges(rt, "grapple", 13),
			}))
			expect(ok):equal(true)
			expect(source):equal("Temp")
		end)
	end)

	describe("Pocket Checkpoint tier rule", function()
		local pocket = ToolTable.Tools.pocket
		it("is banned in Hell and Finale", function()
			expect(Rules.PocketBanned(pocket, "Hell", CourseTable.Tiers.Hell)):equal(true)
			expect(Rules.PocketBanned(pocket, "Finale", CourseTable.Tiers.Finale)):equal(true)
		end)
		it("is allowed in every other tier", function()
			for _, tier in { "Beginner", "Easy", "Medium", "Hard", "Insane" } do
				expect(Rules.PocketBanned(pocket, tier, CourseTable.Tiers[tier])):equal(false)
			end
		end)
		it("is banned by the tier flag even if the tool list forgot the tier", function()
			expect(Rules.PocketBanned({}, "Hell", { BansPocketCheckpoint = true })):equal(true)
		end)
	end)

	describe("IsSafePoint (Shield rescue)", function()
		local safe = { Grounded = true, InSegment = true, OnBadSurface = false, NearKillBrick = false }
		it("needs ground, the segment, a stable surface and distance from KillBricks", function()
			expect(Rules.IsSafePoint(safe)):equal(true)
			expect(Rules.IsSafePoint({ Grounded = false, InSegment = true })):equal(false)
			expect(Rules.IsSafePoint({ Grounded = true, InSegment = false })):equal(false)
			expect(Rules.IsSafePoint({ Grounded = true, InSegment = true, OnBadSurface = true })):equal(false)
			expect(Rules.IsSafePoint({ Grounded = true, InSegment = true, NearKillBrick = true })):equal(false)
		end)
	end)

	describe("loadout", function()
		local function equip(overrides)
			local base = {
				ToolId = "rocket",
				Slot = 1,
				SlotCount = 2,
				MaxSlots = 3,
				Known = true,
				Owned = true,
				Stored = 0,
			}
			for key, value in overrides do
				base[key] = value
			end
			return Rules.CanEquip(base)
		end

		it("sizes the loadout by the Tool Belt", function()
			expect(Rules.SlotCount(config, false)):equal(2)
			expect(Rules.SlotCount(config, true)):equal(3)
		end)
		it("equips an owned tool or one with a stored charge", function()
			expect(equip({})):equal(true)
			expect(equip({ Owned = false, Stored = 1 })):equal(true)
		end)
		it("refuses an unowned tool with no charges, unknown tools and bad slots", function()
			expect(select(2, equip({ Owned = false }))):equal("NotOwned")
			expect(select(2, equip({ Known = false }))):equal("Unknown")
			expect(select(2, equip({ Slot = 4 }))):equal("BadSlot")
			expect(select(2, equip({ Slot = 1.5 }))):equal("BadSlot")
		end)
		it("keeps slot 3 locked without the Tool Belt", function()
			expect(select(2, equip({ Slot = 3 }))):equal("Locked")
			expect(equip({ Slot = 3, SlotCount = 3 })):equal(true)
		end)
		it("lets any slot be emptied", function()
			expect(equip({ ToolId = "", Owned = false })):equal(true)
		end)
		it("moves a tool that is already equipped instead of duplicating it", function()
			expect(Rules.PlaceInSlot({ "shield", "rocket", "" }, 1, "rocket", 3)):equal({ "rocket", "shield", "" })
			expect(Rules.PlaceInSlot({ "shield", "", "" }, 2, "rocket", 3)):equal({ "shield", "rocket", "" })
			expect(Rules.PlaceInSlot({ "shield", "rocket", "" }, 2, "", 3)):equal({ "shield", "", "" })
		end)
	end)

	describe("coin shop", function()
		local function plan(overrides)
			local base = {
				Known = true,
				Owned = false,
				Coins = 1000,
				Price = 500,
				RefillPrice = config.CoinRefill.Coins,
				RefillsUsed = 0,
				MaxRefills = config.CoinRefill.MaxPerToolPerRound,
			}
			for key, value in overrides or {} do
				base[key] = value
			end
			return Rules.PlanBuy(base)
		end

		it("unlocks an unowned tool at its coin price", function()
			local ok, _, action, price = plan()
			expect(ok):equal(true)
			expect(action):equal("Unlock")
			expect(price):equal(500)
		end)
		it("refills an owned tool for 100 coins, once per round", function()
			local ok, _, action, price = plan({ Owned = true })
			expect(ok):equal(true)
			expect(action):equal("Refill")
			expect(price):equal(100)
			expect(select(2, plan({ Owned = true, RefillsUsed = 1 }))):equal("RefillLimit")
		end)
		it("rejects what the player can't afford, already owns or can't refill", function()
			expect(select(2, plan({ Coins = 499 }))):equal("NoCoins")
			expect(select(2, plan({ Owned = true, Coins = 99 }))):equal("NoCoins")
			expect(select(2, plan({ Owned = true, Mode = "Unlock" }))):equal("AlreadyOwned")
			expect(select(2, plan({ Mode = "Refill" }))):equal("NotOwned")
			expect(select(2, plan({ Known = false }))):equal("Unknown")
			expect(select(2, plan({ Mode = "Gift" }))):equal("BadMode")
		end)
		it("refuses a refill the stored stack can't take, before anything is charged", function()
			expect(select(2, plan({ Owned = true, StoredCharges = config.ChargeCap, ChargeCap = config.ChargeCap }))):equal(
				"AtCap"
			)
			expect(plan({ Owned = true, StoredCharges = config.ChargeCap - 1, ChargeCap = config.ChargeCap })):equal(
				true
			)
			expect(plan({ StoredCharges = config.ChargeCap, ChargeCap = config.ChargeCap })):equal(true) -- an unlock isn't a refill
		end)
		it("caps stored charges", function()
			local value, added = Rules.AddCharges(98, 3, config.ChargeCap)
			expect(value):equal(99)
			expect(added):equal(1)
			expect(select(2, Rules.AddCharges(99, 3, config.ChargeCap))):equal(0)
		end)
	end)

	describe("ParseAllowed", function()
		it("reads a comma list and ignores blanks", function()
			expect(Rules.ParseAllowed("grapple, glider")):equal({ grapple = true, glider = true })
			expect(Rules.ParseAllowed("")):equal(nil)
			expect(Rules.ParseAllowed(nil)):equal(nil)
		end)
	end)
end)
