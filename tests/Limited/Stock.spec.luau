local StockRules = load("ServerScriptService/Script/LimitedBallService/StockRules")
local StockStore = load("ServerScriptService/Script/LimitedBallService/StockStore")

local CAP = 1000

-- ── Fakes with the real call shapes ─────────────────────────────────────

-- UpdateAsync reads a snapshot, YIELDS (so other buyers interleave), then commits only if nobody wrote in between,
-- otherwise re-runs the callback: the optimistic concurrency of the real DataStore.
local function newFakeDataStore(interleave)
	local fake = { Data = {}, Versions = {}, Waiting = {}, Writes = 0, FailNext = 0 }

	local function clone(value)
		if type(value) ~= "table" then
			return value
		end
		local copy = {}
		for key, inner in value do
			copy[key] = clone(inner)
		end
		return copy
	end

	function fake:GetAsync(key)
		if self.FailNext > 0 then
			self.FailNext -= 1
			error("DataStore request was added to queue")
		end
		return clone(self.Data[key])
	end

	function fake:UpdateAsync(key, callback)
		if self.FailNext > 0 then
			self.FailNext -= 1
			error("DataStore request was added to queue")
		end
		while true do
			local version = self.Versions[key] or 0
			local newValue = callback(clone(self.Data[key]))
			if interleave then
				table.insert(self.Waiting, coroutine.running())
				coroutine.yield()
			end
			if newValue == nil then
				return nil
			end
			if (self.Versions[key] or 0) == version then
				self.Data[key] = clone(newValue)
				self.Versions[key] = version + 1
				self.Writes += 1
				return newValue
			end
		end
	end

	-- Resume every parked UpdateAsync in a scrambled order until all have finished.
	function fake:Drain(rng)
		while #self.Waiting > 0 do
			local batch = self.Waiting
			self.Waiting = {}
			for index = #batch, 2, -1 do
				local pick = rng:NextInteger(1, index)
				batch[index], batch[pick] = batch[pick], batch[index]
			end
			for _, thread in batch do
				coroutine.resume(thread)
			end
		end
	end

	return fake
end

local function newFakeHashMap()
	local map = { Items = {}, Ttls = {} }
	function map:SetAsync(key, value, ttl)
		self.Items[key] = value
		self.Ttls[key] = ttl
	end
	function map:RemoveAsync(key)
		self.Items[key] = nil
	end
	function map:Expire(key) -- what the TTL does
		self.Items[key] = nil
	end
	function map:ListItemsAsync(count)
		local keys = {}
		for key in self.Items do
			table.insert(keys, key)
		end
		table.sort(keys)
		local index = 1
		local pages = { IsFinished = false }
		local function page()
			local out = {}
			for position = index, math.min(index + count - 1, #keys) do
				table.insert(out, { key = keys[position], value = self.Items[keys[position]] })
			end
			return out
		end
		local function finishedAfter()
			pages.IsFinished = index + count > #keys
		end
		finishedAfter()
		function pages.GetCurrentPage()
			return page()
		end
		function pages.AdvanceToNextPageAsync()
			index += count
			finishedAfter()
		end
		return pages
	end
	return map
end

local function newStore(interleave, cap)
	local dataStore = newFakeDataStore(interleave)
	local reservations = newFakeHashMap()
	local store = StockStore.new({
		DataStore = dataStore,
		Reservations = reservations,
		Key = "LimitedStock",
		Cap = cap or CAP,
		ReservationSeconds = 300,
	})
	return store, dataStore, reservations
end

-- ── Rules ───────────────────────────────────────────────────────────────

describe("StockRules", function()
	it("assigns serial = sold count and logs the PurchaseId", function()
		local value, outcome = StockRules.Commit(nil, "a", 3)
		expect(outcome.Status):equal("Sold")
		expect(outcome.Serial):equal(1)
		expect(value.sold):equal(1)
		expect(value.log.a):equal(1)
		local second = StockRules.Commit(value, "b", 3)
		expect(second.sold):equal(2)
		expect(second.log.b):equal(2)
	end)

	it("returns the same serial for a retried PurchaseId and writes nothing", function()
		local value = StockRules.Commit(nil, "a", 3)
		local newValue, outcome = StockRules.Commit(value, "a", 3)
		expect(newValue):equal(nil)
		expect(outcome.Serial):equal(1)
		expect(outcome.Replayed):equal(true)
	end)

	it("reports sold out at the cap without selling, and remembers the receipt", function()
		local value = { sold = 3, log = { a = 1, b = 2, c = 3 } }
		local newValue, outcome = StockRules.Commit(value, "d", 3)
		expect(outcome.Status):equal("SoldOut")
		expect(newValue.sold):equal(3)
		expect(newValue.log.d):equal(0)
		local again, replay = StockRules.Commit(newValue, "d", 3)
		expect(again):equal(nil)
		expect(replay.Status):equal("SoldOut")
		expect(replay.Replayed):equal(true)
	end)

	it("stops logging sold-out receipts at LOG_CAP so the key stays bounded", function()
		local log = {}
		for index = 1, StockRules.LOG_CAP do
			log["p" .. index] = 0
		end
		local newValue, outcome = StockRules.Commit({ sold = 3, log = log }, "extra", 3)
		expect(newValue):equal(nil)
		expect(outcome.Status):equal("SoldOut")
	end)

	it("tolerates malformed stored values", function()
		expect(StockRules.Normalize("junk")):equal({ sold = 0, log = {} })
		expect(StockRules.Normalize({ sold = -4, log = { a = "x", [1] = 2, ok = 5 } })):equal({
			sold = 0,
			log = { ok = 5 },
		})
	end)

	it("does reservation arithmetic including the caller's own hold", function()
		expect(StockRules.CanReserve(990, 10, 1000)):equal(true)
		expect(StockRules.CanReserve(990, 11, 1000)):equal(false)
		expect(StockRules.CanReserve(1000, 1, 1000)):equal(false)
		expect(StockRules.CanReserve(0, 1, 1000)):equal(true)
		expect(StockRules.Remaining(1200, 1000)):equal(0)
	end)

	it("lists recent sales newest first", function()
		local sales = StockRules.RecentSales({ sold = 3, log = { a = 1, b = 2, c = 3, d = 0 } }, 2)
		expect(#sales):equal(2)
		expect(sales[1].Serial):equal(3)
		expect(sales[2].PurchaseId):equal("b")
	end)
end)

-- ── Concurrency ─────────────────────────────────────────────────────────

describe("StockStore concurrent buys", function()
	it("never assigns a duplicate serial or exceeds 1000 across 1,200 interleaved buys", function()
		local store, dataStore = newStore(true)
		local outcomes = {}
		for index = 1, 1200 do
			local thread = coroutine.create(function()
				local ok, outcome = store:Commit("purchase-" .. index)
				outcomes[index] = { Ok = ok, Outcome = outcome }
			end)
			coroutine.resume(thread)
		end
		dataStore:Drain(Random.new(7))

		local serials, sold, soldOut = {}, 0, 0
		for index = 1, 1200 do
			local result = outcomes[index]
			expect(result.Ok):equal(true)
			if result.Outcome.Status == "Sold" then
				expect(serials[result.Outcome.Serial]):equal(nil)
				serials[result.Outcome.Serial] = true
				expect(result.Outcome.Serial >= 1 and result.Outcome.Serial <= CAP):equal(true)
				sold += 1
			else
				soldOut += 1
			end
		end
		expect(sold):equal(CAP)
		expect(soldOut):equal(200)
		expect(dataStore.Data.LimitedStock.sold):equal(CAP)
		for serial = 1, CAP do
			expect(serials[serial]):equal(true)
		end
	end)

	it("gives a retried PurchaseId the same serial even while others interleave", function()
		local store, dataStore = newStore(true, 50)
		local first, second = {}, {}
		for index = 1, 30 do
			coroutine.resume(coroutine.create(function()
				store:Commit("p" .. index)
			end))
		end
		coroutine.resume(coroutine.create(function()
			local _, outcome = store:Commit("retry-me")
			first.Outcome = outcome
		end))
		coroutine.resume(coroutine.create(function()
			local _, outcome = store:Commit("retry-me")
			second.Outcome = outcome
		end))
		dataStore:Drain(Random.new(3))
		expect(first.Outcome.Serial):equal(second.Outcome.Serial)
		expect(dataStore.Data.LimitedStock.sold):equal(31)
	end)

	it("returns the same serial on a sequential retry and does not sell twice", function()
		local store, dataStore = newStore(false, 10)
		local _, a = store:Commit("x")
		local _, b = store:Commit("x")
		expect(a.Serial):equal(b.Serial)
		expect(b.Replayed):equal(true)
		expect(dataStore.Data.LimitedStock.sold):equal(1)
	end)

	it("reports a store failure so the receipt is retried", function()
		local store, dataStore = newStore(false, 10)
		dataStore.FailNext = 1
		expect(store:Commit("x")):equal(false)
		local ok, outcome = store:Commit("x")
		expect(ok):equal(true)
		expect(outcome.Serial):equal(1)
	end)
end)

-- ── Reservations ────────────────────────────────────────────────────────

describe("StockStore reservations", function()
	it("reserves with the TTL and counts holds", function()
		local store, _, map = newStore(false, 5)
		expect(store:Reserve(101)):equal(true)
		expect(map.Ttls["101"]):equal(300)
		expect(select(2, store:CountReservations())):equal(1)
	end)

	it("counts reservations across several pages", function()
		local store, _, map = newStore(false, 10000)
		for userId = 1, 450 do
			map:SetAsync(tostring(userId), {}, 300)
		end
		expect(select(2, store:CountReservations())):equal(450)
	end)

	it("a re-prompt by the same player does not take a second slot", function()
		local store = newStore(false, 5)
		store:Reserve(1)
		store:Reserve(1)
		expect(select(2, store:CountReservations())):equal(1)
	end)

	it("refuses once sold plus holds would pass the cap, and releases the refused hold", function()
		local store, dataStore = newStore(false, 5)
		for index = 1, 3 do
			store:Commit("sale" .. index)
		end
		expect(dataStore.Data.LimitedStock.sold):equal(3)
		expect(store:Reserve(1)):equal(true)
		expect(store:Reserve(2)):equal(true)
		local ok, reason = store:Reserve(3)
		expect(ok):equal(false)
		expect(reason):equal("SoldOut")
		expect(select(2, store:CountReservations())):equal(2)
	end)

	it("frees a slot on release and on TTL expiry", function()
		local store, _, map = newStore(false, 2)
		expect(store:Reserve(1)):equal(true)
		expect(store:Reserve(2)):equal(true)
		expect(store:Reserve(3)):equal(false)
		store:Release(1)
		expect(store:Reserve(3)):equal(true)
		map:Expire("2")
		expect(store:Reserve(4)):equal(true)
	end)

	it("refuses when sold out even with no holds", function()
		local store = newStore(false, 2)
		store:Commit("a")
		store:Commit("b")
		local ok, reason = store:Reserve(9)
		expect(ok):equal(false)
		expect(reason):equal("SoldOut")
	end)

	it("never admits more buyers than slots when reservations race", function()
		local store = newStore(false, 10)
		local admitted = 0
		for userId = 1, 40 do
			if store:Reserve(userId) then
				admitted += 1
			end
		end
		expect(admitted):equal(10)
	end)

	it("treats a store failure as no prompt", function()
		local store, dataStore = newStore(false, 5)
		dataStore.FailNext = 1
		local ok, reason = store:Reserve(1)
		expect(ok):equal(false)
		expect(reason):equal("StoreError")
		expect(select(2, store:CountReservations())):equal(0)
	end)
end)

-- ── Sold-out consolation path ───────────────────────────────────────────

describe("sold out at receipt time", function()
	it("records the receipt as sold out without selling, and its retry stays sold out", function()
		local store, dataStore = newStore(false, 2)
		store:Commit("a")
		store:Commit("b")
		local ok, outcome = store:Commit("late")
		expect(ok):equal(true)
		expect(outcome.Status):equal("SoldOut")
		expect(dataStore.Data.LimitedStock.sold):equal(2)
		local _, retry = store:Commit("late")
		expect(retry.Status):equal("SoldOut")
		expect(retry.Replayed):equal(true)
	end)

	it("has a documented consolation in ProductTable", function()
		local ProductTable = load("ReplicatedStorage/Tables/ProductTable")
		local consolation = ProductTable.CrownOfHell.Params.Consolation
		expect(consolation.Coins):equal(25000)
		expect(consolation.TrailId):equal("AshenCrown")
	end)
end)
