describe("SeasonService.Rules", function()
	local Rules = load("ServerScriptService/Script/SeasonService/Rules")
	local SeasonTable = load("ReplicatedStorage/Tables/SeasonTable")
	local cfg = SeasonTable.Config
	local def = SeasonTable.Seasons.S1
	local DAY = 86400
	local START = 1000000
	local END = START + 30 * DAY

	local function state(xp, extra)
		local s = { xp = xp, claimedFree = {}, claimedPremium = {}, hasPremium = false, bonusChests = 0 }
		for k, v in extra or {} do
			s[k] = v
		end
		return s
	end

	describe("tiers", function()
		it("is 40 tiers x 900 XP and caps at 40", function()
			expect(cfg.Tiers):equal(40)
			expect(cfg.XpPerTier):equal(900)
			expect(Rules.Tier(0, cfg)):equal(0)
			expect(Rules.Tier(899, cfg)):equal(0)
			expect(Rules.Tier(900, cfg)):equal(1)
			expect(Rules.Tier(35999, cfg)):equal(39)
			expect(Rules.Tier(36000, cfg)):equal(40)
			expect(Rules.Tier(99999, cfg)):equal(40)
		end)

		it("treats bad XP as tier 0", function()
			expect(Rules.Tier(-5, cfg)):equal(0)
			expect(Rules.Tier(nil, cfg)):equal(0)
		end)
	end)

	describe("catch-up", function()
		it("counts whole days since the start", function()
			expect(Rules.DaysElapsed(START + DAY - 1, START)):equal(0)
			expect(Rules.DaysElapsed(START + 5 * DAY + 10, START)):equal(5)
			expect(Rules.DaysElapsed(START - 100, START)):equal(0)
		end)

		it("applies x1.5 exactly while tier < days elapsed", function()
			local day5 = START + 5 * DAY
			expect(Rules.IsCatchUp(3 * 900, day5, START, cfg)):truthy() -- tier 3 < 5
			expect(Rules.IsCatchUp(4 * 900 + 899, day5, START, cfg)):truthy() -- tier 4 < 5
			expect(Rules.IsCatchUp(5 * 900, day5, START, cfg)):falsy() -- tier 5 == 5, on pace
			expect(Rules.IsCatchUp(6 * 900, day5, START, cfg)):falsy()
			expect(Rules.IsCatchUp(0, START + 100, START, cfg)):falsy() -- day 0
		end)

		it("multiplies the gain only while catching up", function()
			local day5 = START + 5 * DAY
			local newXp, gained, catchUp = Rules.ApplyXp(0, 10, day5, START, cfg)
			expect(gained):equal(15)
			expect(newXp):equal(15)
			expect(catchUp):truthy()
			local _, onPace = Rules.ApplyXp(5 * 900, 10, day5, START, cfg)
			expect(onPace):equal(10)
		end)

		it("floors fractional catch-up XP", function()
			local _, gained = Rules.ApplyXp(0, 5, START + 5 * DAY, START, cfg)
			expect(gained):equal(7)
		end)

		it("rejects bad amounts and caps total XP", function()
			expect(select(2, Rules.ApplyXp(0, 0, START, START, cfg))):equal(0)
			expect(select(2, Rules.ApplyXp(0, -10, START, START, cfg))):equal(0)
			expect(select(2, Rules.ApplyXp(0, 0 / 0, START, START, cfg))):equal(0)
			local newXp = Rules.ApplyXp(Rules.MaxXp(cfg) - 5, 100, START, START, cfg)
			expect(newXp):equal(Rules.MaxXp(cfg))
		end)
	end)

	describe("timing", function()
		it("is active only inside [start, end)", function()
			expect(Rules.IsActive(START - 1, START, END, 0)):falsy()
			expect(Rules.IsActive(START, START, END, 0)):truthy()
			expect(Rules.IsActive(END - 1, START, END, 0)):truthy()
			expect(Rules.IsActive(END, START, END, 0)):falsy()
		end)

		it("is inactive while the dates are unset (0/0)", function()
			expect(Rules.IsActive(50, 0, 0, 0)):falsy()
		end)

		it("lets the override extend but never shorten the end", function()
			expect(Rules.IsActive(END + 10, START, END, END + 100)):truthy()
			expect(Rules.IsActive(END + 10, START, END, END - 100)):falsy()
			expect(Rules.EffectiveEnd(END, 0)):equal(END)
		end)

		it("locks products in the last hour", function()
			expect(Rules.IsProductLocked(END - 3601, END, cfg)):falsy()
			expect(Rules.IsProductLocked(END - 3600, END, cfg)):truthy()
			expect(Rules.IsProductLocked(END - 1, END, cfg)):truthy()
		end)
	end)

	describe("claims", function()
		it("allows a reached free reward once", function()
			local s = state(3 * 900)
			expect(Rules.CanClaim(s, def, "Free", 3, cfg)):truthy()
			s.claimedFree["3"] = true
			local ok, reason = Rules.CanClaim(s, def, "Free", 3, cfg)
			expect(ok):falsy()
			expect(reason):equal("AlreadyClaimed")
		end)

		it("refuses tiers not reached", function()
			local ok, reason = Rules.CanClaim(state(2 * 900), def, "Free", 3, cfg)
			expect(ok):falsy()
			expect(reason):equal("NotReached")
		end)

		it("refuses premium without hasPremium, allows it with", function()
			local ok, reason = Rules.CanClaim(state(5 * 900), def, "Premium", 2, cfg)
			expect(ok):falsy()
			expect(reason):equal("NoPremium")
			expect(Rules.CanClaim(state(5 * 900, { hasPremium = true }), def, "Premium", 2, cfg)):truthy()
		end)

		it("keeps the free and premium claims separate", function()
			local s = state(5 * 900, { hasPremium = true })
			s.claimedFree["2"] = true
			expect(Rules.CanClaim(s, def, "Premium", 2, cfg)):truthy()
		end)

		it("rejects bad tracks and tiers", function()
			local s = state(36000, { hasPremium = true })
			expect(Rules.CanClaim(s, def, "Gold", 1, cfg)):falsy()
			expect(Rules.CanClaim(s, def, "Free", 0, cfg)):falsy()
			expect(Rules.CanClaim(s, def, "Free", 41, cfg)):falsy()
			expect(Rules.CanClaim(s, def, "Free", 1.5, cfg)):falsy()
			expect(Rules.CanClaim(s, def, "Free", "3", cfg)):falsy()
		end)

		it("buying Premium unlocks every reached premium reward at once", function()
			local s = state(7 * 900)
			expect(#Rules.ClaimableList(s, def, cfg)):equal(7)
			s.hasPremium = true
			local list = Rules.ClaimableList(s, def, cfg)
			expect(#list):equal(14)
			local premium = 0
			for _, entry in list do
				if entry.Track == "Premium" then
					premium += 1
				end
			end
			expect(premium):equal(7)
		end)

		it("lists claimable rewards in tier order, free first", function()
			local list = Rules.ClaimableList(state(2 * 900, { hasPremium = true }), def, cfg)
			expect(list[1].Tier):equal(1)
			expect(list[1].Track):equal("Free")
			expect(list[2].Track):equal("Premium")
			expect(list[3].Tier):equal(2)
		end)
	end)

	describe("bonus chests", function()
		it("start after tier 40, 1800 XP each, max 10", function()
			expect(Rules.BonusChestsAvailable(state(36000 + 1799), cfg)):equal(0)
			expect(Rules.BonusChestsAvailable(state(36000 + 1800), cfg)):equal(1)
			expect(Rules.BonusChestsAvailable(state(Rules.MaxXp(cfg) + 5000), cfg)):equal(10)
			expect(Rules.BonusChestsAvailable(state(36000 + 3600, { bonusChests = 1 }), cfg)):equal(1)
		end)

		it("pays coins, plus a spin each for premium", function()
			local free = Rules.ChestRewards(2, false, cfg)
			expect(#free):equal(1)
			expect(free[1].Amount):equal(200)
			local premium = Rules.ChestRewards(2, true, cfg)
			expect(premium[2].Type):equal("Spins")
			expect(premium[2].Amount):equal(2)
		end)
	end)

	describe("tier products", function()
		it("never push past tier 40", function()
			expect(Rules.CapTierPurchase(0, 1, cfg)):equal(900)
			expect(Rules.CapTierPurchase(0, 10, cfg)):equal(9000)
			expect(Rules.CapTierPurchase(35 * 900, 10, cfg)):equal(5 * 900)
			expect(Rules.CapTierPurchase(36000, 10, cfg)):equal(0)
			expect(Rules.CapTierPurchase(36000 + 900, 1, cfg)):equal(0)
			expect(Rules.CapTierPurchase(0, 0, cfg)):equal(0)
		end)

		it("plans Premium Pass as premium, a second one as 10 tiers", function()
			local first = Rules.PurchasePlan({ Premium = true }, state(0), cfg)
			expect(first.SetPremium):truthy()
			expect(first.XpToAdd):equal(0)
			local second = Rules.PurchasePlan({ Premium = true }, state(0, { hasPremium = true }), cfg)
			expect(second.SetPremium):falsy()
			expect(second.XpToAdd):equal(9000)
		end)

		it("plans Premium+ as premium plus 10 tiers", function()
			local plan = Rules.PurchasePlan({ Premium = true, Tiers = 10 }, state(900), cfg)
			expect(plan.SetPremium):truthy()
			expect(plan.XpToAdd):equal(9000)
		end)

		it("caps a plan near the top", function()
			local plan = Rules.PurchasePlan({ Tiers = 10 }, state(38 * 900), cfg)
			expect(plan.XpToAdd):equal(2 * 900)
		end)
	end)

	describe("product offers", function()
		local now = START + 10 * DAY
		local function offer(key, s, at)
			return (Rules.CanOfferProduct(key, s, at or now, END, cfg))
		end

		it("hides every season product in the last hour", function()
			local late = END - 1800
			for _, key in SeasonTable.Seasons.S1.Products do
				expect(offer(key, state(0), late)):falsy()
			end
			expect(offer("SeasonPremiumPass", state(0), END - 3601)):truthy()
		end)

		it("hides Buy a Tier at tier 40", function()
			expect(offer("SeasonBuyTier", state(39 * 900))):truthy()
			expect(offer("SeasonBuyTier", state(36000))):falsy()
		end)

		it("hides Buy 10 Tiers above tier 30", function()
			expect(offer("SeasonBuyTenTiers", state(30 * 900))):truthy()
			expect(offer("SeasonBuyTenTiers", state(31 * 900))):falsy()
		end)

		it("swaps Buy 10 Tiers for the ending offer in the last 7 days", function()
			local ending = END - 6 * DAY
			expect(offer("SeasonBuyTenTiers", state(0), ending)):falsy()
			expect(offer("SeasonEndingTenTiers", state(0), ending)):truthy()
			expect(offer("SeasonEndingTenTiers", state(0))):falsy()
		end)

		it("returns a reason only when the product is not offered", function()
			expect({ Rules.CanOfferProduct("SeasonPremiumPass", state(0), now, END, cfg) }):equal({ true })
			local ok, reason = Rules.CanOfferProduct("SeasonBuyTier", state(36000), now, END, cfg)
			expect(ok):equal(false)
			expect(reason):equal("MaxTier")
			local locked, lockedReason = Rules.CanOfferProduct("SeasonPremiumPass", state(0), END - 60, END, cfg)
			expect(locked):equal(false)
			expect(lockedReason):equal("Locked")
		end)

		it("offers Premium only to non-premium players", function()
			expect(offer("SeasonPremiumPass", state(0))):truthy()
			expect(offer("SeasonPremiumPass", state(0, { hasPremium = true }))):falsy()
			expect(offer("SeasonPremiumPlus", state(0, { hasPremium = true }))):falsy()
		end)
	end)

	describe("off-season credit", function()
		local pass = { Premium = true }
		local plus = { Premium = true, Tiers = 10 }

		it("stores a first Premium Pass as premium credit", function()
			local premium, tiers = Rules.CreditPlan(pass, false, 0, cfg)
			expect(premium):equal(true)
			expect(tiers):equal(0)
		end)

		it("adds a second Premium Pass as bonus tiers instead of overwriting", function()
			local premium, tiers = Rules.CreditPlan(pass, true, 0, cfg)
			expect(premium):equal(true)
			expect(tiers):equal(cfg.AlreadyPremiumBonusTiers)
			local _, again = Rules.CreditPlan(pass, premium, tiers, cfg)
			expect(again):equal(2 * cfg.AlreadyPremiumBonusTiers)
		end)

		it("stores tier products as tiers and Premium+ as both, capped at a full pass", function()
			local _, tiers = Rules.CreditPlan({ Tiers = 1 }, false, 0, cfg)
			expect(tiers):equal(1)
			local premium, plusTiers = Rules.CreditPlan(plus, false, 5, cfg)
			expect(premium):equal(true)
			expect(plusTiers):equal(15)
			local _, capped = Rules.CreditPlan({ Tiers = 10 }, false, 35, cfg)
			expect(capped):equal(cfg.Tiers)
		end)

		it("turns the credit into the first XP and premium of the new season", function()
			local entry = Rules.EntryState("S2", true, 10, cfg)
			expect(entry.id):equal("S2")
			expect(entry.hasPremium):equal(true)
			expect(Rules.Tier(entry.xp, cfg)):equal(math.floor(10 * cfg.BuyTierXp / cfg.XpPerTier))
			local empty = Rules.EntryState("S2", false, 0, cfg)
			expect(empty.xp):equal(0)
			expect(empty.hasPremium):equal(false)
		end)
	end)

	describe("did the player race", function()
		it("counts a player who reached checkpoint 1 or finished", function()
			expect(Rules.DidRace(1, false)):equal(true)
			expect(Rules.DidRace(12, false)):equal(true)
			expect(Rules.DidRace(0, true)):equal(true)
		end)

		it("does not count an idle player who never reached a checkpoint", function()
			expect(Rules.DidRace(0, false)):equal(false)
			expect(Rules.DidRace(nil, false)):equal(false)
		end)
	end)

	describe("rollover", function()
		it("closes out when another season is active or the end passed", function()
			expect(Rules.NeedsCloseOut("S1", "S2", START, END)):truthy()
			expect(Rules.NeedsCloseOut("S1", "S1", END, END)):truthy()
			expect(Rules.NeedsCloseOut("S1", "S1", END - 1, END)):falsy()
			expect(Rules.NeedsCloseOut("", "S1", END, END)):falsy()
		end)

		it("plans every earned, unclaimed reward", function()
			local s = state(5 * 900 + 100, { hasPremium = true })
			s.claimedFree["1"] = true
			s.claimedPremium["1"] = true
			local plan = Rules.RolloverPlan(s, def, cfg)
			expect(plan.FinalTier):equal(5)
			expect(#plan.Claims):equal(8) -- tiers 2..5, both tracks
			expect(plan.History):equal({ tier = 5, hasPremium = true })
		end)

		it("skips premium rewards for a free player", function()
			local plan = Rules.RolloverPlan(state(3 * 900), def, cfg)
			expect(#plan.Claims):equal(3)
			for _, entry in plan.Claims do
				expect(entry.Track):equal("Free")
			end
			expect(plan.History.hasPremium):falsy()
		end)

		it("includes unclaimed bonus chests", function()
			local plan = Rules.RolloverPlan(state(36000 + 3600), def, cfg)
			expect(plan.Chests):equal(2)
		end)

		it("plans nothing for an unknown old season but still records history", function()
			local plan = Rules.RolloverPlan(state(2000), nil, cfg)
			expect(#plan.Claims):equal(0)
			expect(plan.History.tier):equal(2)
		end)
	end)

	describe("SeasonTable", function()
		it("has a free and premium reward on every tier", function()
			for tier = 1, 40 do
				expect(def.Free[tier] ~= nil):truthy()
				expect(def.Premium[tier] ~= nil):truthy()
			end
		end)
	end)
end)
