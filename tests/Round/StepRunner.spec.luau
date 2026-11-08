describe("StepRunner", function()
	local StepRunner = load("ServerScriptService/Script/RoundService/StepRunner")

	local function makeSteps(log, abortAt)
		local steps = {}
		for _, name in { "Intermission", "BuildCourse", "Countdown", "Race", "Results", "Teardown" } do
			table.insert(steps, {
				Name = name,
				Run = function()
					table.insert(log, "Run " .. name)
					if name == abortAt then
						return "Abort"
					end
				end,
				Skip = function()
					table.insert(log, "Skip " .. name)
				end,
			})
		end
		return steps
	end

	it("runs every step in order with no start step", function()
		local log = {}
		expect(StepRunner.Run(makeSteps(log), nil, {})):equal(true)
		expect(log):equal({
			"Run Intermission",
			"Run BuildCourse",
			"Run Countdown",
			"Run Race",
			"Run Results",
			"Run Teardown",
		})
	end)

	it("skips everything before the start step and runs the rest", function()
		local log = {}
		StepRunner.Run(makeSteps(log), "Race", {})
		expect(log):equal({
			"Skip Intermission",
			"Skip BuildCourse",
			"Skip Countdown",
			"Run Race",
			"Run Results",
			"Run Teardown",
		})
	end)

	it("treats an unknown or empty start step as a full run", function()
		local plan, found = StepRunner.Plan(makeSteps({}), "Nope")
		expect(found):equal(false)
		expect(plan[1].Action):equal("Run")
		local _, emptyFound = StepRunner.Plan(makeSteps({}), "")
		expect(emptyFound):equal(true)
	end)

	it("stops the cycle when a step returns Abort", function()
		local log = {}
		expect(StepRunner.Run(makeSteps(log, "BuildCourse"), nil, {})):equal(false)
		expect(log):equal({ "Run Intermission", "Run BuildCourse" })
	end)

	it("stops the cycle when a Skip returns Abort", function()
		local log = {}
		local steps = makeSteps(log)
		steps[1].Skip = function()
			table.insert(log, "Skip Intermission")
			return "Abort"
		end
		expect(StepRunner.Run(steps, "BuildCourse", {})):equal(false)
		expect(log):equal({ "Skip Intermission" })
	end)

	it("passes the context to each step and reports each step", function()
		local seen, reported = nil, {}
		local steps = {
			{
				Name = "A",
				Run = function(context)
					seen = context
				end,
				Skip = function() end,
			},
		}
		local context = {}
		StepRunner.Run(steps, nil, context, function(step, action)
			table.insert(reported, step.Name .. ":" .. action)
		end)
		expect(seen == context):equal(true)
		expect(reported):equal({ "A:Run" })
	end)
end)
