describe("DataTemplate", function()
	local DataTemplate = load("ServerScriptService/Script/PlayerData/DataTemplate")

	it("starts new players with 3 shield charges in slot 1", function()
		expect(DataTemplate.equippedTools[1]):equal("shield")
		expect(DataTemplate.toolCharges.shield):equal(3)
	end)

	it("has every adopted key", function()
		for _, key in
			{
				"coins",
				"ownedBalls",
				"firstJoinAt",
				"sessionCount",
				"boosts",
				"settings",
				"purchaseLog",
				"stats",
				"ownedTools",
				"toolCharges",
				"equippedTools",
				"skipTokens",
				"ownedTricks",
				"equippedTricks",
				"trickLevels",
				"season",
				"seasonHistory",
				"seasonPremiumCredit",
				"challenges",
			}
		do
			expect(DataTemplate[key] ~= nil):truthy()
		end
		expect(DataTemplate.settings.showTricks):equal(true)
		expect(DataTemplate.stats.tricksLanded):equal(0)
		expect(DataTemplate.stats.bestTrickPoints):equal(0)
	end)
end)
