describe("AnalyticsService funnels", function()
	local FunnelDedupe = load("ServerScriptService/Script/AnalyticsService/FunnelDedupe")
	local AnalyticsTable = load("ReplicatedStorage/Tables/AnalyticsTable")
	local Funnels = AnalyticsTable.Funnels

	it("claims a step once per player", function()
		local seen = FunnelDedupe.new()
		local player = {}
		expect(seen:Claim(player, "Onboarding", "Joined")):truthy()
		expect(seen:Claim(player, "Onboarding", "Joined")):falsy()
		expect(seen:Claim({}, "Onboarding", "Joined")):truthy()
	end)

	it("separates qualifiers and resets on Clear", function()
		local seen = FunnelDedupe.new()
		local player = {}
		expect(seen:Claim(player, "Purchase", "OfferShown", "111")):truthy()
		expect(seen:Claim(player, "Purchase", "OfferShown", "222")):truthy()
		seen:Clear(player)
		expect(seen:Claim(player, "Purchase", "OfferShown", "111")):truthy()
	end)

	it("resolves fixed and prefix funnels", function()
		expect(select(2, FunnelDedupe.Resolve(Funnels, "Round"))):equal("Round")
		expect(select(2, FunnelDedupe.Resolve(Funnels, "Season_S1"))):equal("Season")
		expect(FunnelDedupe.Resolve(Funnels, "Season_")):equal(nil)
		expect(FunnelDedupe.Resolve(Funnels, "Nope")):equal(nil)
	end)

	it("numbers steps by position", function()
		expect(FunnelDedupe.StepNumber(Funnels.Onboarding, "Joined")):equal(1)
		expect(FunnelDedupe.StepNumber(Funnels.Onboarding, "SecondSession")):equal(12)
		expect(FunnelDedupe.StepNumber(Funnels.Onboarding, "Bogus")):equal(nil)
	end)

	it("defines every GDD 12.1 step and 12.3 event", function()
		expect(#Funnels.Onboarding.Steps):equal(12)
		expect(#Funnels.Season.Steps):equal(8)
		expect(#Funnels.Purchase.Steps):equal(4)
		expect(#Funnels.Round.Steps):equal(8)
		local count = 0
		for name, value in AnalyticsTable.Events do
			expect(value):equal(name)
			count += 1
		end
		-- At least the 23 GDD §12.3 events; later systems add their own.
		expect(count >= 23):truthy()
	end)
end)
