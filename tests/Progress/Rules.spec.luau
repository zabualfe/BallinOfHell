describe("ProgressService.Rules", function()
	local Rules = load("ServerScriptService/Script/ProgressService/Rules")
	local CourseTable = load("ReplicatedStorage/Tables/CourseTable")
	local progress = CourseTable.Progress

	local function input(overrides)
		local base = {
			Current = 4,
			Index = 5,
			Distance = 5,
			Elapsed = 10,
			ParTime = 20,
			Range = progress.CheckpointRange,
			MinParFraction = progress.MinParFraction,
		}
		for key, value in overrides or {} do
			base[key] = value
		end
		return base
	end

	describe("EvaluateCheckpoint", function()
		it("accepts the next checkpoint in range after the par floor", function()
			local ok, reason = Rules.EvaluateCheckpoint(input())
			expect(ok):equal(true)
			expect(reason):equal(nil)
		end)

		it("rejects an index that is not current + 1", function()
			expect(select(2, Rules.EvaluateCheckpoint(input({ Index = 6 })))):equal("WrongIndex")
			expect(select(2, Rules.EvaluateCheckpoint(input({ Index = 4 })))):equal("WrongIndex")
		end)

		it("rejects over 20 studs but accepts exactly 20", function()
			expect(select(2, Rules.EvaluateCheckpoint(input({ Distance = 20.01 })))):equal("TooFar")
			expect(Rules.EvaluateCheckpoint(input({ Distance = 20 }))):equal(true)
		end)

		it("rejects before 0.35 x ParTime but accepts exactly at it", function()
			expect(select(2, Rules.EvaluateCheckpoint(input({ Elapsed = 6.9 })))):equal("TooEarly")
			expect(Rules.EvaluateCheckpoint(input({ Elapsed = 7 }))):equal(true)
		end)

		it("reports the index problem before distance and time", function()
			local _, reason = Rules.EvaluateCheckpoint(input({ Index = 9, Distance = 99, Elapsed = 0 }))
			expect(reason):equal("WrongIndex")
		end)
	end)

	describe("MinParFraction", function()
		it("uses 0.35, or 0.25 after a movement tool", function()
			expect(Rules.MinParFraction(progress, false)):equal(0.35)
			expect(Rules.MinParFraction(progress, true)):equal(0.25)
		end)
	end)

	describe("CanSkip", function()
		local function skip(overrides)
			local base = { Current = 3, Target = 4, FinishIndex = 30, Finished = false }
			for key, value in overrides or {} do
				base[key] = value
			end
			return Rules.CanSkip(base)
		end

		it("allows moving ahead", function()
			expect(skip()):equal(true)
			expect(skip({ Target = 29 })):equal(true)
		end)

		it("never lets the finish be skipped", function()
			expect(select(2, skip({ Target = 30 }))):equal("FinishLocked")
			expect(select(2, skip({ Target = 31 }))):equal("FinishLocked")
		end)

		it("rejects standing still, going back and finished players", function()
			expect(select(2, skip({ Target = 3 }))):equal("NotAhead")
			expect(select(2, skip({ Target = 1 }))):equal("NotAhead")
			expect(select(2, skip({ Finished = true }))):equal("Finished")
		end)

		it("refuses to pass a NoSkips segment", function()
			local noSkip = function(index)
				return index == 6
			end
			expect(select(2, skip({ Target = 8, IsNoSkip = noSkip }))):equal("NoSkipTier")
			expect(skip({ Target = 5, IsNoSkip = noSkip })):equal(true)
		end)

		it("lists the skipped indices", function()
			expect(Rules.SkippedIndices(3, 6)):equal({ 4, 5, 6 })
		end)
	end)

	describe("ShouldFlag", function()
		it("flags at the strike limit", function()
			expect(Rules.ShouldFlag(4, progress.StrikesPerRound)):equal(false)
			expect(Rules.ShouldFlag(5, progress.StrikesPerRound)):equal(true)
		end)
	end)
end)
