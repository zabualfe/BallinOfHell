describe("ChallengeService.Rules", function()
	local Rules = load("ServerScriptService/Script/ChallengeService/Rules")
	local ChallengeTable = load("ReplicatedStorage/Tables/ChallengeTable")
	local config = ChallengeTable.Config
	local DAY = 86400

	local function ids(rows)
		local out = {}
		for _, row in rows do
			table.insert(out, row.Id)
		end
		return out
	end

	describe("day and week numbers", function()
		it("changes the day at 00:00 UTC", function()
			expect(Rules.DayNumber(DAY - 1)):equal(0)
			expect(Rules.DayNumber(DAY)):equal(1)
		end)

		it("starts weeks on Monday 00:00 UTC", function()
			local monday = 4 * DAY -- 1970-01-05
			expect(Rules.WeekNumber(monday - 1)):equal(0) -- Sunday
			expect(Rules.WeekNumber(monday)):equal(1)
			expect(Rules.WeekNumber(monday + 6 * DAY + 86399)):equal(1)
			expect(Rules.WeekNumber(monday + 7 * DAY)):equal(2)
		end)

		it("counts seconds to the next reset", function()
			expect(Rules.SecondsToNextDay(DAY + 100)):equal(DAY - 100)
			expect(Rules.SecondsToNextWeek(4 * DAY + 10)):equal(7 * DAY - 10)
		end)
	end)

	describe("assignment", function()
		local seed = Rules.Seed(1234, 20000, 1)

		it("picks 3 distinct dailies and 5 distinct weeklies", function()
			local daily = Rules.Assign(ChallengeTable.Daily, config.DailyCount, seed, 0, ChallengeTable.Conditional)
			local weekly = Rules.Assign(ChallengeTable.Weekly, config.WeeklyCount, seed, 0, ChallengeTable.Conditional)
			expect(#daily):equal(3)
			expect(#weekly):equal(5)
			local seen = {}
			for _, row in daily do
				expect(seen[row.Id]):equal(nil)
				seen[row.Id] = true
			end
		end)

		it("is deterministic for the same (UserId, day), so rejoining changes nothing", function()
			local a = Rules.Assign(ChallengeTable.Daily, 3, Rules.Seed(99, 20000, 1), 0, nil)
			local b = Rules.Assign(ChallengeTable.Daily, 3, Rules.Seed(99, 20000, 1), 0, nil)
			expect(ids(a)):equal(ids(b))
		end)

		it("does not depend on pool order", function()
			local reversed = {}
			for i = #ChallengeTable.Daily, 1, -1 do
				table.insert(reversed, ChallengeTable.Daily[i])
			end
			local a = Rules.Assign(ChallengeTable.Daily, 3, seed, 0, nil)
			local b = Rules.Assign(reversed, 3, seed, 0, nil)
			expect(ids(a)):equal(ids(b))
		end)

		it("varies across users and days", function()
			local sets = {}
			for user = 1, 12 do
				sets[table.concat(ids(Rules.Assign(ChallengeTable.Daily, 3, Rules.Seed(user, 20000, 1), 0, nil)), ",")] =
					true
			end
			local count = 0
			for _ in sets do
				count += 1
			end
			expect(count > 1):truthy()
			expect(Rules.Seed(1, 20000, 1) ~= Rules.Seed(1, 20001, 1)):truthy()
			expect(Rules.Seed(1, 20000, 1) ~= Rules.Seed(2, 20000, 1)):truthy()
		end)

		it("never offers w_finish1 before the first win", function()
			for user = 1, 60 do
				local rows =
					Rules.Assign(ChallengeTable.Weekly, 5, Rules.Seed(user, 2900, 2), 0, ChallengeTable.Conditional)
				expect(#rows):equal(5)
				for _, row in rows do
					expect(row.Id ~= "w_finish1"):truthy()
				end
			end
		end)

		it("substitutes ReplaceWith for a gated row and never lists a row twice", function()
			local conditional = { w_finish1 = { MinWins = 1, ReplaceWith = "w_play10" } }
			local pool = {
				{ Id = "w_finish1", Weight = 1 },
				{ Id = "w_play10", Weight = 1 },
				{ Id = "w_other", Weight = 1 },
			}
			expect(ids(Rules.Eligible(pool, 0, conditional))):equal({ "w_play10", "w_other" })
			expect(ids(Rules.Eligible(pool, 1, conditional))):equal({ "w_finish1", "w_play10", "w_other" })

			local noReplacement = { { Id = "w_finish1", Weight = 1 }, { Id = "w_other", Weight = 1 } }
			expect(ids(Rules.Eligible(noReplacement, 0, conditional))):equal({ "w_other" })
		end)

		it("can offer w_finish1 after a win", function()
			local found = false
			for user = 1, 60 do
				for _, row in
					Rules.Assign(ChallengeTable.Weekly, 5, Rules.Seed(user, 2900, 2), 1, ChallengeTable.Conditional)
				do
					found = found or row.Id == "w_finish1"
				end
			end
			expect(found):truthy()
		end)

		it("builds fresh entries", function()
			expect(Rules.NewEntry(ChallengeTable.Daily[1])):equal({ id = "d_clear15", progress = 0, done = false })
		end)
	end)

	describe("rerolls", function()
		local function challenges(used, done)
			return {
				daily = {
					{ id = "d_clear15", progress = 0, done = done or false },
					{ id = "d_tools3", progress = 0, done = false },
					{ id = "d_spin1", progress = 0, done = false },
				},
				rerollsUsed = used,
			}
		end

		it("allows 1 free reroll a day and 2 with Premium", function()
			expect(Rules.RerollLimit(false, config)):equal(1)
			expect(Rules.RerollLimit(true, config)):equal(2)
			expect(Rules.CanReroll(challenges(0), 1, false, config)):truthy()
			expect(Rules.CanReroll(challenges(1), 1, false, config)):falsy()
			expect(Rules.CanReroll(challenges(1), 1, true, config)):truthy()
			expect(Rules.CanReroll(challenges(2), 1, true, config)):falsy()
		end)

		it("refuses bad or finished slots", function()
			expect(select(2, Rules.CanReroll(challenges(0), 4, false, config))):equal("BadIndex")
			expect(select(2, Rules.CanReroll(challenges(0), 1.5, false, config))):equal("BadIndex")
			expect(select(2, Rules.CanReroll(challenges(0, true), 1, false, config))):equal("AlreadyDone")
		end)

		it("is deterministic from the stored seed and never repeats a held challenge", function()
			local held = { "d_clear15", "d_tools3", "d_spin1" }
			local seed = Rules.RerollSeed(77, 20000, 0)
			local a = Rules.Reroll(ChallengeTable.Daily, held, seed, 0, nil)
			local b = Rules.Reroll(ChallengeTable.Daily, held, seed, 0, nil)
			expect(a.Id):equal(b.Id)
			expect(table.find(held, a.Id)):equal(nil)
			expect(Rules.RerollSeed(77, 20000, 1) ~= seed):truthy()
		end)

		it("returns nil when nothing is left to swap in", function()
			local all = ids(ChallengeTable.Daily)
			expect(Rules.Reroll(ChallengeTable.Daily, all, 5, 0, nil)):equal(nil)
		end)
	end)

	describe("progress", function()
		local row = { Target = 3 }

		it("advances, caps at the target and completes once", function()
			local entry = { id = "x", progress = 0, done = false }
			local one, done1 = Rules.Advance(entry, row, 1)
			expect(one.progress):equal(1)
			expect(done1):falsy()
			local full, done2 = Rules.Advance(one, row, 10)
			expect(full.progress):equal(3)
			expect(full.done):truthy()
			expect(done2):truthy()
			local _, done3 = Rules.Advance(full, row, 1)
			expect(done3):falsy()
		end)

		it("ignores zero, negative and NaN increments", function()
			local entry = { id = "x", progress = 1, done = false }
			expect(select(1, Rules.Advance(entry, row, 0)).progress):equal(1)
			expect(select(1, Rules.Advance(entry, row, -2)).progress):equal(1)
			expect(select(1, Rules.Advance(entry, row, 0 / 0)).progress):equal(1)
		end)
	end)

	describe("objective plug-ins", function()
		local function objective(name)
			return load("ServerScriptService/Script/ChallengeService/Objectives/" .. name)
		end

		it("has a module with Event and Increment for every objective type", function()
			for _, name in ChallengeTable.ObjectiveTypes do
				local module = objective(name)
				expect(type(module.Event)):equal("string")
				expect(type(module.Increment)):equal("function")
			end
		end)

		it("only uses known types in the pools", function()
			local known = {}
			for _, name in ChallengeTable.ObjectiveTypes do
				known[name] = true
			end
			for _, scope in { "Daily", "Weekly" } do
				for _, row in ChallengeTable[scope] do
					expect(known[row.Type]):truthy()
				end
			end
		end)

		it("ClearSegments honours minTier by course order", function()
			local clear = objective("ClearSegments")
			expect(clear.Increment({}, { Tier = "Beginner" })):equal(1)
			expect(clear.Increment({ minTier = "Medium" }, { Tier = "Easy" })):equal(0)
			expect(clear.Increment({ minTier = "Medium" }, { Tier = "Medium" })):equal(1)
			expect(clear.Increment({ minTier = "Medium" }, { Tier = "Hard" })):equal(1)
		end)

		it("ReachSegment counts once a slot is reached, once per round", function()
			local reach = objective("ReachSegment")
			expect(reach.OncePerRound):truthy()
			expect(reach.Increment({ slot = 20 }, { Index = 19 })):equal(0)
			expect(reach.Increment({ slot = 20 }, { Index = 21 })):equal(1)
		end)

		it("LandTricks honours minChain", function()
			local land = objective("LandTricks")
			expect(land.Increment({}, { Points = 10 })):equal(1)
			expect(land.Increment({ minChain = 3 }, { Chain = 2 })):equal(0)
			expect(land.Increment({ minChain = 3 }, { Chain = 3 })):equal(1)
		end)

		it("TrickPoints sums points", function()
			expect(objective("TrickPoints").Increment({}, { Points = 120 })):equal(120)
		end)

		it("UseTool filters by toolId", function()
			local use = objective("UseTool")
			expect(use.Increment({}, { ToolId = "rocket" })):equal(1)
			expect(use.Increment({ toolId = "shield" }, { ToolId = "rocket" })):equal(0)
		end)

		it("EarnCoins counts race and trick coins, not reward coins", function()
			local earn = objective("EarnCoins")
			expect(earn.Increment({ source = "Race" }, { Amount = 7, Kind = "Race" })):equal(7)
			expect(earn.Increment({ source = "Race" }, { Amount = 4, Kind = "Trick" })):equal(4)
			expect(earn.Increment({ source = "Race" }, { Amount = 50, Kind = "Reward" })):equal(0)
		end)
	end)
end)
