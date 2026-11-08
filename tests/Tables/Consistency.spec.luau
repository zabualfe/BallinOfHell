describe("Tables consistency", function()
	local BallTable = load("ReplicatedStorage/Tables/BallTable")
	local RarityTable = load("ReplicatedStorage/Tables/RarityTable")
	local WheelTable = load("ReplicatedStorage/Tables/WheelTable")
	local CourseTable = load("ReplicatedStorage/Tables/CourseTable")
	local SeasonTable = load("ReplicatedStorage/Tables/SeasonTable")
	local ProductTable = load("ReplicatedStorage/Tables/ProductTable")
	local PassTable = load("ReplicatedStorage/Tables/PassTable")
	local Weighted = load("ReplicatedStorage/Utilities/Weighted")

	describe("roster", function()
		local roster = {}
		for id, ball in BallTable do
			if ball.Source ~= "Seasonal" then
				roster[id] = ball
			end
		end

		it("has 21 non-seasonal balls", function()
			local count = 0
			for _ in roster do
				count += 1
			end
			expect(count):equal(21)
		end)

		it("matches each rarity budget with every stat in 1-10", function()
			for _, ball in BallTable do -- seasonal balls follow the same rule
				local rarity = RarityTable[ball.Rarity]
				expect(rarity ~= nil):truthy()
				expect(ball.Speed + ball.Acceleration + ball.Jump == rarity.Budget):truthy()
				for _, key in { "Speed", "Acceleration", "Jump" } do
					local value = ball[key]
					expect(value >= 1 and value <= 10 and value % 1 == 0):truthy()
				end
			end
		end)

		it("never names a ball Korblox or Noob", function()
			for _, ball in BallTable do
				for _, field in { ball.Name, ball.ModelName } do
					local lower = string.lower(field)
					expect(string.find(lower, "korblox", 1, true)):equal(nil)
					expect(string.find(lower, "noob", 1, true)):equal(nil)
				end
			end
		end)

		it("sells no exclusive for Coins", function()
			for _, ball in BallTable do
				if ball.Exclusive then
					expect(ball.Price):equal(nil)
				end
			end
		end)
	end)

	describe("wheel", function()
		it("has weights summing to 100", function()
			local total = 0
			for _, slice in WheelTable.Slices do
				total += slice.Weight
			end
			expect(total):equal(100)
		end)

		it("rolls each slice within 0.5 pp over 100k seeded rolls", function()
			local random = Random.new(2024)
			local counts = {}
			local rolls = 100000
			for _ = 1, rolls do
				local slice = Weighted.Pick(WheelTable.Slices, random)
				counts[slice.Id] = (counts[slice.Id] or 0) + 1
			end
			for _, slice in WheelTable.Slices do
				local percent = (counts[slice.Id] or 0) / rolls * 100
				expect(math.abs(percent - slice.Weight) <= 0.5):truthy()
			end
		end)
	end)

	it("has 30 course slots in GDD 5.2 order", function()
		local expected = {}
		local function add(tier, count)
			for _ = 1, count do
				table.insert(expected, tier)
			end
		end
		add("Beginner", 4)
		add("Easy", 5)
		add("Medium", 6)
		add("Hard", 6)
		add("Insane", 6)
		add("Hell", 2)
		add("Finale", 1)
		expect(#CourseTable.Slots):equal(30)
		expect(CourseTable.SlotCount):equal(30)
		expect(CourseTable.Slots):equal(expected)
		for _, tier in CourseTable.Slots do
			expect(CourseTable.Tiers[tier] ~= nil):truthy()
		end
	end)

	it("has a 40 tier x 900 XP season", function()
		expect(SeasonTable.Config.Tiers):equal(40)
		expect(SeasonTable.Config.XpPerTier):equal(900)
		for _, season in SeasonTable.Seasons do
			expect(season.Tiers):equal(40)
			expect(season.XpPerTier):equal(900)
		end
	end)

	describe("product and pass references", function()
		local function check(source, key, set, label)
			if set[key] == nil then
				error(`{source} references missing {label} "{tostring(key)}"`)
			end
		end

		it("resolve to ProductTable / PassTable keys", function()
			local Tables = game:GetService("ReplicatedStorage").Tables
			local ModifierTable = load("ReplicatedStorage/Tables/ModifierTable")
			local ToolTable = load("ReplicatedStorage/Tables/ToolTable")
			local StarterPackTable = load("ReplicatedStorage/Tables/StarterPackTable")
			local DailyRewardTable = load("ReplicatedStorage/Tables/DailyRewardTable")
			local TimedRewardTable = load("ReplicatedStorage/Tables/TimedRewardTable")
			local TrickTable = load("ReplicatedStorage/Tables/TrickTable")
			local UpsellTable = load("ReplicatedStorage/Tables/UpsellTable")
			expect(Tables ~= nil):truthy()

			for id, ball in BallTable do
				if ball.ProductKey then
					check(`BallTable.{id}.ProductKey`, ball.ProductKey, ProductTable, "product")
				end
			end
			for _, key in WheelTable.Config.PaidSpinProductKeys do
				check("WheelTable.PaidSpinProductKeys", key, ProductTable, "product")
			end
			for name in ModifierTable.Modifiers do
				-- Server modifiers and trolls are sold as products of the same key.
				check(`ModifierTable.Modifiers.{name}`, name, ProductTable, "product")
			end
			check("ToolTable.Config.UnlimitedPass", ToolTable.Config.UnlimitedPass.PassKey, PassTable, "pass")
			check("StarterPackTable.ProductKey", StarterPackTable.ProductKey, ProductTable, "product")
			check(
				"DailyRewardTable.RestoreProductKey",
				DailyRewardTable.Config.RestoreProductKey,
				ProductTable,
				"product"
			)
			check(
				"TimedRewardTable.UnlockAllProductKey",
				TimedRewardTable.Config.UnlockAllProductKey,
				ProductTable,
				"product"
			)
			for id, trick in TrickTable.Tricks do
				if trick.RobuxProduct then
					check(`TrickTable.{id}.RobuxProduct`, trick.RobuxProduct, ProductTable, "product")
				end
			end
			for _, season in SeasonTable.Seasons do
				for _, key in season.Products do
					check("SeasonTable.Products", key, ProductTable, "product")
				end
			end
			for _, trigger in UpsellTable.Triggers do
				if trigger.RequiresNoPass then
					check(`UpsellTable.{trigger.Id}.RequiresNoPass`, trigger.RequiresNoPass, PassTable, "pass")
				end
				for _, offer in trigger.Offers do
					-- "Coins" and "RobuxUnlock" are inline-offer markers, not keys.
					if offer ~= "Coins" and offer ~= "RobuxUnlock" then
						if ProductTable[offer] == nil and PassTable[offer] == nil then
							error(`UpsellTable.{trigger.Id} offers missing key "{offer}"`)
						end
					end
				end
			end
		end)
	end)
end)
