-- StockStore
-- The storage half of the Crown of Hell stock: every DataStore / MemoryStore call, pcall'd, behind objects that are
-- injected so specs can pass in-memory fakes with the same call shapes. All maths lives in StockRules.
--
-- Usage:
--   local store = StockStore.new({
--       DataStore = ds,            -- :GetAsync(key), :UpdateAsync(key, fn)
--       Reservations = hashMap,    -- MemoryStoreHashMap: :SetAsync(key, value, ttl), :RemoveAsync(key), :ListItemsAsync(count)
--       Key = "LimitedStock", Cap = 1000, ReservationSeconds = 300,
--   })
--   store:ReadSold() -> ok, sold?, raw?      -- DataStore failure -> false
--   store:Commit(purchaseId) -> ok, outcome? -- idempotent UpdateAsync; ok = false means "retry later"
--   store:Reserve(userId) -> boolean, reason? -- reason "SoldOut" | "StoreError"
--   store:Release(userId) -> boolean
--   store:CountReservations() -> ok, count?
-- The DataStore is written only through UpdateAsync, never SetAsync.

local StockRules = require(script.Parent.StockRules)

local StockStore = {}
StockStore.__index = StockStore

local PAGE_SIZE = 200 -- ListItemsAsync page

function StockStore.new(config)
	return setmetatable({
		_dataStore = config.DataStore,
		_reservations = config.Reservations,
		_key = config.Key,
		_cap = config.Cap,
		_ttl = config.ReservationSeconds,
	}, StockStore)
end

function StockStore:ReadSold()
	local ok, raw = pcall(self._dataStore.GetAsync, self._dataStore, self._key)
	if not ok then
		return false
	end
	return true, StockRules.Normalize(raw).sold, raw
end

function StockStore:Commit(purchaseId)
	local outcome = nil
	local ok = pcall(self._dataStore.UpdateAsync, self._dataStore, self._key, function(raw)
		-- Reset every run: UpdateAsync may retry the callback and only the last run's result is the real one.
		local newValue, result = StockRules.Commit(raw, purchaseId, self._cap)
		outcome = result
		return newValue
	end)
	if not ok or outcome == nil then
		return false
	end
	return true, outcome
end

function StockStore:CountReservations()
	local ok, count = pcall(function()
		local pages = self._reservations:ListItemsAsync(PAGE_SIZE)
		local total = 0
		while true do
			total += #pages:GetCurrentPage()
			if pages.IsFinished then
				return total
			end
			pages:AdvanceToNextPageAsync()
		end
	end)
	if not ok then
		return false
	end
	return true, count
end

function StockStore:Release(userId)
	return (pcall(self._reservations.RemoveAsync, self._reservations, tostring(userId)))
end

-- Reserve first, then count: the hold is visible to concurrent buyers before the check, so the last slot can
-- never be handed to two of them.
function StockStore:Reserve(userId)
	local soldOk, sold = self:ReadSold()
	if not soldOk then
		return false, "StoreError"
	end
	if sold >= self._cap then
		return false, "SoldOut"
	end

	local key = tostring(userId)
	local setOk = pcall(self._reservations.SetAsync, self._reservations, key, { at = os.time() }, self._ttl)
	if not setOk then
		return false, "StoreError"
	end
	local countOk, count = self:CountReservations()
	if not countOk then
		self:Release(userId)
		return false, "StoreError"
	end
	if not StockRules.CanReserve(sold, count, self._cap) then
		self:Release(userId)
		return false, "SoldOut"
	end
	return true
end

return StockStore
