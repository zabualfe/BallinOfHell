describe("ProgressService.Rejoin", function()
	local Rejoin = load("ServerScriptService/Script/ProgressService/Rejoin")

	it("starts fresh for an unknown player", function()
		local plan = Rejoin.Plan({}, 7)
		expect(plan.Action):equal("Fresh")
		expect(plan.Checkpoint):equal(0)
	end)

	it("restores a rejoiner at their checkpoint with every earlier index flagged", function()
		local records = {}
		Rejoin.Record(records, 7, 3)
		local plan = Rejoin.Plan(records, 7)
		expect(plan.Action):equal("Restore")
		expect(plan.Checkpoint):equal(3)
		expect(plan.Skipped):equal({ [1] = true, [2] = true, [3] = true })
	end)

	it("never moves a record backwards", function()
		local records = {}
		Rejoin.Record(records, 7, 5)
		Rejoin.Record(records, 7, 2)
		expect(Rejoin.Plan(records, 7).Checkpoint):equal(5)
	end)

	it("sends a finished player to the lobby and keeps Finished sticky", function()
		local records = {}
		Rejoin.Record(records, 7, 30, true)
		Rejoin.Record(records, 7, 30, false)
		expect(Rejoin.Plan(records, 7).Action):equal("Lobby")
	end)

	it("keeps players separate and treats checkpoint 0 as fresh", function()
		local records = {}
		Rejoin.Record(records, 1, 4)
		Rejoin.Record(records, 2, 0)
		expect(Rejoin.Plan(records, 1).Action):equal("Restore")
		expect(Rejoin.Plan(records, 2).Action):equal("Fresh")
		expect(Rejoin.Plan(records, 3).Action):equal("Fresh")
	end)
end)
