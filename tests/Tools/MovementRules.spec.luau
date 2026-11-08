describe("ToolService.MovementRules", function()
	local MovementRules = load("ServerScriptService/Script/ToolService/MovementRules")
	local ToolTable = load("ReplicatedStorage/Tables/ToolTable")
	local tools = ToolTable.Tools

	describe("Spring", function()
		it("needs the ground", function()
			expect(MovementRules.GroundedOnly(tools.spring, true)):equal(true)
			local ok, reason = MovementRules.GroundedOnly(tools.spring, false)
			expect(ok):equal(false)
			expect(reason):equal("NotGrounded")
		end)
	end)

	describe("Glider", function()
		it("needs to be airborne", function()
			expect(MovementRules.AirborneOnly(tools.glider, false)):equal(true)
			local ok, reason = MovementRules.AirborneOnly(tools.glider, true)
			expect(ok):equal(false)
			expect(reason):equal("NotAirborne")
		end)

		it("does not restrict tools that are not flagged", function()
			expect(MovementRules.AirborneOnly(tools.brake, true)):equal(true)
			expect(MovementRules.GroundedOnly(tools.brake, false)):equal(true)
		end)
	end)

	describe("NotActive (Coil, Glider)", function()
		it("refuses while a window is open and allows once it ended", function()
			local ok, reason = MovementRules.NotActive(110, 100)
			expect(ok):equal(false)
			expect(reason):equal("AlreadyActive")
			expect(MovementRules.NotActive(110, 110)):equal(true)
			expect(MovementRules.NotActive(nil, 100)):equal(true)
		end)
	end)

	describe("Grapple", function()
		local function target(overrides)
			local base = { IsAnchor = true, Distance = 40, Reach = 60, Tolerance = 15, InSegment = true }
			for key, value in overrides or {} do
				base[key] = value
			end
			return base
		end

		it("uses the tool's Range unless the anchor overrides it", function()
			expect(MovementRules.GrappleReach(tools.grapple, nil)):equal(60)
			expect(MovementRules.GrappleReach(tools.grapple, 90)):equal(90)
			expect(MovementRules.GrappleReach(tools.grapple, "far")):equal(60)
			expect(MovementRules.GrappleReach(tools.grapple, -5)):equal(60)
		end)

		it("accepts an anchor in range inside the segment", function()
			expect(MovementRules.GrappleTarget(target())):equal(true)
		end)

		it("rejects a target that is not a tagged anchor", function()
			local ok, reason = MovementRules.GrappleTarget(target({ IsAnchor = false }))
			expect(ok):equal(false)
			expect(reason):equal("NoTarget")
		end)

		it("allows latency slack past the range but not beyond", function()
			expect(MovementRules.GrappleTarget(target({ Distance = 74 }))):equal(true)
			local ok, reason = MovementRules.GrappleTarget(target({ Distance = 76 }))
			expect(ok):equal(false)
			expect(reason):equal("OutOfRange")
		end)

		it("rejects an anchor outside the current segment", function()
			local ok, reason = MovementRules.GrappleTarget(target({ InSegment = false }))
			expect(ok):equal(false)
			expect(reason):equal("WrongSegment")
		end)
	end)

	describe("WindowSeconds", function()
		it("matches each tool's effect length", function()
			expect(MovementRules.WindowSeconds("coil", tools.coil)):equal(tools.coil.Duration)
			expect(MovementRules.WindowSeconds("glider", tools.glider)):equal(tools.glider.MaxDuration)
			expect(MovementRules.WindowSeconds("grapple", tools.grapple)):equal(tools.grapple.MaxPullSeconds)
			expect(MovementRules.WindowSeconds("rocket", tools.rocket)):near(1.1, 1e-9)
			expect(MovementRules.WindowSeconds("brake", tools.brake)):equal(tools.brake.StopSeconds)
			expect(MovementRules.WindowSeconds("timeslow", tools.timeslow)):equal(tools.timeslow.Duration)
			expect(MovementRules.WindowSeconds("spring", tools.spring) > 0):truthy()
			expect(MovementRules.WindowSeconds("shield", tools.shield)):equal(0)
		end)
	end)
end)

describe("ToolService.Windows", function()
	local Windows = load("ServerScriptService/Script/ToolService/Windows")
	local assist = { glider = true, grapple = true, coil = true }

	it("finds windows that overlap an airtime", function()
		local list = Windows.New()
		Windows.Add(list, "coil", 100, 106)
		Windows.Add(list, "rocket", 200, 201)
		expect(#Windows.Query(list, 104, 110, assist)):equal(1) -- began before the airtime, still active
		expect(#Windows.Query(list, 106, 110, assist)):equal(1) -- touching counts
		expect(#Windows.Query(list, 107, 110, assist)):equal(0)
		expect(#Windows.Query(list, 90, 99, assist)):equal(0)
		expect(#Windows.Query(list, 195, 205)):equal(1)
		expect(#Windows.Query(list, 195, 205, assist)):equal(0) -- rocket is not an assist tool
	end)

	it("returns copies", function()
		local list = Windows.New()
		Windows.Add(list, "glider", 10, 14)
		Windows.Query(list, 0, 20)[1].End = 0
		expect(list[1].End):equal(14)
	end)

	it("ends a window early but never extends it", function()
		local list = Windows.New()
		local window = Windows.Add(list, "glider", 10, 14)
		Windows.Close(window, 12)
		expect(window.End):equal(12)
		Windows.Close(window, 13)
		expect(window.End):equal(12)
		Windows.Close(window, 5)
		expect(window.End):equal(10)
		expect(#Windows.Query(list, 13, 20)):equal(0)
	end)

	it("drops windows that ended long ago", function()
		local list = Windows.New()
		Windows.Add(list, "coil", 0, 6, 120)
		Windows.Add(list, "coil", 200, 206, 120)
		expect(#list):equal(1)
	end)
end)

describe("Tool plug-in coverage", function()
	local ToolTable = load("ReplicatedStorage/Tables/ToolTable")

	it("has a server half and a client half for every tool in ToolTable", function()
		local function names(folder)
			local set = {}
			for _, child in folder:GetChildren() do
				set[string.lower(child.Name)] = true -- the loaders match on the lower-cased file name
			end
			return set
		end
		local server = names(game:GetService("ServerScriptService").Script.ToolService.Tools)
		local client = names(game:GetService("ReplicatedStorage").Modules.ToolController.Tools)
		for toolId in ToolTable.Tools do
			expect(server[toolId]):equal(true)
			expect(client[toolId]):equal(true)
		end
	end)
end)
