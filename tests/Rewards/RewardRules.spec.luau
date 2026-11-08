describe("RewardRules.Normalize", function()
	local RewardRules = load("ReplicatedStorage/Shared/RewardRules")
	local BallTable = load("ReplicatedStorage/Tables/BallTable")
	local ToolTable = load("ReplicatedStorage/Tables/ToolTable")
	local TrickTable = load("ReplicatedStorage/Tables/TrickTable")
	local WheelTable = load("ReplicatedStorage/Tables/WheelTable")
	local DailyRewardTable = load("ReplicatedStorage/Tables/DailyRewardTable")
	local TimedRewardTable = load("ReplicatedStorage/Tables/TimedRewardTable")
	local StarterPackTable = load("ReplicatedStorage/Tables/StarterPackTable")
	local SeasonTable = load("ReplicatedStorage/Tables/SeasonTable")
	local EconomyTable = load("ReplicatedStorage/Tables/EconomyTable")

	local function plan(reward)
		local ops, problems = RewardRules.Normalize(reward)
		expect(problems):equal({})
		return ops
	end

	local function checkIds(ops)
		for _, op in ops do
			if op.Kind == "Ball" then
				expect(BallTable[op.Id] ~= nil):truthy()
			elseif op.Kind == "ToolCharges" or op.Kind == "ToolUnlock" then
				expect(ToolTable.Tools[op.Id] ~= nil):truthy()
			elseif op.Kind == "Trick" then
				expect(TrickTable.Tricks[op.Id] ~= nil):truthy()
			end
		end
	end

	it("reads a typed coin reward", function()
		expect(plan({ Type = "Coins", Amount = 50 })):equal({ { Kind = "Coins", Amount = 50 } })
	end)

	it("reads a flat reward in grant order, tool charges sorted", function()
		local ops =
			plan({ Coins = 100, Spins = 2, ToolCharges = { shield = 3, rocket = 1 }, FirstTimeBall = "emberglow" })
		local kinds = {}
		for _, op in ops do
			table.insert(kinds, op.Kind .. ":" .. tostring(op.Id))
		end
		expect(kinds):equal({ "Coins:nil", "Spins:nil", "ToolCharges:rocket", "ToolCharges:shield", "Ball:emberglow" })
	end)

	it("reads a list and ignores row metadata", function()
		local ops = plan({ { Day = 1, Coins = 50, VipCoins = 75 }, { Type = "SkipToken", Amount = 1 } })
		expect(#ops):equal(2)
	end)

	it("treats an empty list as nothing to do", function()
		expect(plan({})):equal({})
	end)

	it("reports malformed rewards", function()
		for _, bad in
			{
				{ Type = "Nope" },
				{ Coins = -5 },
				{ Coins = 1.5 },
				{ Gems = 3 },
				{ Type = "ToolCharges", Amount = 2 },
				7,
			}
		do
			local _, problems = RewardRules.Normalize(bad)
			expect(#problems > 0):truthy()
		end
	end)

	it("plans every Wheel slice", function()
		for _, slice in WheelTable.Slices do
			checkIds(plan(slice.Reward))
		end
	end)

	it("plans every Daily reward day", function()
		for _, day in DailyRewardTable.Days do
			checkIds(plan(day))
		end
	end)

	it("plans every Timed gift and its fallback", function()
		for _, gift in TimedRewardTable.Gifts do
			checkIds(plan(gift))
			if gift.Fallback then
				checkIds(plan(gift.Fallback))
			end
		end
	end)

	it("plans the Starter Pack contents", function()
		local ops = plan(StarterPackTable.Contents)
		checkIds(ops)
		local kinds = {}
		for _, op in ops do
			kinds[op.Kind] = op.Amount
		end
		expect(kinds.Ball):equal(1)
		expect(kinds.ToolUnlock):equal(1)
		expect(kinds.Coins):equal(2500)
		expect(kinds.Spins):equal(5)
		expect(kinds.BoostMinutes):equal(30)
	end)

	it("plans every Season track reward", function()
		for _, season in SeasonTable.Seasons do
			for _, track in { season.Free, season.Premium } do
				for _, rewards in track do
					checkIds(plan(rewards))
				end
			end
		end
	end)

	it("plans the first-fall present", function()
		checkIds(plan(EconomyTable.Sources.FirstFallPresent))
	end)

	it("round-trips an op through ToEntry", function()
		local ops = plan({ Type = "ToolCharges", ToolId = "shield", Amount = 3 })
		expect(plan(RewardRules.ToEntry(ops[1]))):equal(ops)
	end)

	it("summarizes ops for the client", function()
		local summary = RewardRules.Summarize(plan({ Type = "Ball", BallId = "smokewraith", DuplicateCoins = 2500 }))
		expect(summary):equal({ { Kind = "Ball", Amount = 1, Id = "smokewraith" } })
	end)

	it("does not multiply starter pack or purchased coins", function()
		expect(RewardRules.UsesMultiplier("StarterPack")):equal(false)
		expect(RewardRules.UsesMultiplier("Wheel")):equal(true)
	end)

	it("marks FinalCoins ops and keeps plain Coins unmarked", function()
		local final = plan({ FinalCoins = 125, Spins = 1 })
		expect(final[1].Kind):equal("Coins")
		expect(final[1].Amount):equal(125)
		expect(final[1].Final):equal(true)
		expect(final[2].Final):equal(nil)
		expect(plan({ Coins = 50 })[1].Final):equal(nil)
		expect(plan({ Type = "Coins", Amount = 9, Final = true })[1].Final):equal(true)
		expect(RewardRules.ToEntry(final[1]).Final):equal(true)
	end)

	it("treats a partial grant with a non-empty summary as final", function()
		expect(RewardRules.IsFinalGrant(true, { { Kind = "Coins", Amount = 1 } })):equal(true)
		expect(RewardRules.IsFinalGrant(false, { { Kind = "Coins", Amount = 1 } })):equal(true)
		expect(RewardRules.IsFinalGrant(false, {})):equal(false)
		expect(RewardRules.IsFinalGrant(false, nil)):equal(false)
		expect(RewardRules.IsFinalGrant(nil, nil)):equal(false)
	end)
end)
