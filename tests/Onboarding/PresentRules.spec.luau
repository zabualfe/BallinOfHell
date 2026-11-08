describe("OnboardingService.PresentRules", function()
	local PresentRules = load("ServerScriptService/Script/OnboardingService/PresentRules")
	local EconomyTable = load("ReplicatedStorage/Tables/EconomyTable")

	local function spawnInput(overrides)
		local input = { SessionCount = 1, Claimed = false, HasPending = false }
		for key, value in overrides or {} do
			input[key] = value
		end
		return input
	end

	it("spawns on the first fall of session 1", function()
		expect(PresentRules.ShouldSpawn(spawnInput())):truthy()
	end)

	it("never spawns in session 2 or later", function()
		expect(PresentRules.ShouldSpawn(spawnInput({ SessionCount = 2 }))):falsy()
		expect(PresentRules.ShouldSpawn(spawnInput({ SessionCount = 9 }))):falsy()
	end)

	it("never spawns once claimed or while one is pending", function()
		expect(PresentRules.ShouldSpawn(spawnInput({ Claimed = true }))):falsy()
		expect(PresentRules.ShouldSpawn(spawnInput({ HasPending = true }))):falsy()
	end)

	it("claims only with a pending gift and an unset flag", function()
		expect(PresentRules.CanClaim({ HasPending = true, Claimed = false })):truthy()
		expect(PresentRules.CanClaim({ HasPending = false, Claimed = false })):falsy()
		expect(PresentRules.CanClaim({ HasPending = true, Claimed = true })):falsy()
	end)

	it("treats only a future timestamp as a live offer", function()
		expect(PresentRules.IsFuture(200, 100)):truthy()
		expect(PresentRules.IsFuture(100, 100)):falsy()
		expect(PresentRules.IsFuture(nil, 100)):falsy()
	end)

	it("pays the GDD present", function()
		expect(EconomyTable.Sources.FirstFallPresent):equal({
			Coins = 150,
			Spins = 2,
			BoostMinutes = 10,
			ToolCharges = { shield = 2 },
		})
	end)
end)
