-- StockRules
-- Pure rules for the global Crown of Hell stock (ARCHITECTURE 6.7). No engine calls, so the whole sale
-- arithmetic is specced offline.
--
-- Stored value (DataStore key `LimitedStock`): { sold = n, log = { [purchaseId] = serial } }
--   log doubles as the idempotency record: a Roblox receipt retry finds its PurchaseId and gets the same serial
--   back. A sold-out receipt is logged with serial 0 so its retry is recognised too.
--   Growth is bounded by design: at most `cap` entries have a serial (sold never passes cap), and sold-out
--   entries stop being recorded at LOG_CAP total. Past that, the per-player purchaseLog in PurchaseService
--   still stops a normal retry, so a separate key per PurchaseId is not worth its extra writes.
--
-- Usage:
--   StockRules.Normalize(raw) -> { sold, log }      -- tolerant of nil / malformed stored values
--   StockRules.Remaining(sold, cap) -> number
--   StockRules.Commit(raw, purchaseId, cap) -> newValue?, outcome
--       Runs inside UpdateAsync (may run several times, must stay pure). newValue nil = write nothing.
--       outcome = { Status = "Sold" | "SoldOut", Serial = n?, Replayed = boolean }
--   StockRules.CanReserve(sold, reservations, cap) -> boolean
--       `reservations` counts every live hold INCLUDING the caller's, so two buyers racing for the last slot are
--       both refused rather than both admitted. A refused buyer can simply try again.
--   StockRules.RecentSales(raw, count) -> list of { PurchaseId, Serial }, newest first (admin log)

local StockRules = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
StockRules.LOG_CAP = 2000 -- total log entries (sales + sold-out receipts)

local function isCount(value)
	return type(value) == "number" and value >= 0 and value % 1 == 0
end

function StockRules.Normalize(raw)
	local sold, log = 0, {}
	if type(raw) == "table" then
		if isCount(raw.sold) then
			sold = raw.sold
		end
		if type(raw.log) == "table" then
			for purchaseId, serial in raw.log do
				if type(purchaseId) == "string" and isCount(serial) then
					log[purchaseId] = serial
				end
			end
		end
	end
	return { sold = sold, log = log }
end

function StockRules.Remaining(sold, cap)
	return math.max(0, cap - sold)
end

function StockRules.Commit(raw, purchaseId, cap)
	local value = StockRules.Normalize(raw)
	local known = value.log[purchaseId]
	if known ~= nil then
		local status = if known > 0 then "Sold" else "SoldOut"
		return nil, { Status = status, Serial = if known > 0 then known else nil, Replayed = true }
	end

	if value.sold >= cap then
		local entries = 0
		for _ in value.log do
			entries += 1
		end
		if entries >= StockRules.LOG_CAP then
			return nil, { Status = "SoldOut", Replayed = false }
		end
		value.log[purchaseId] = 0
		return value, { Status = "SoldOut", Replayed = false }
	end

	value.sold += 1
	value.log[purchaseId] = value.sold
	return value, { Status = "Sold", Serial = value.sold, Replayed = false }
end

function StockRules.CanReserve(sold, reservations, cap)
	return sold + reservations <= cap
end

function StockRules.RecentSales(raw, count)
	local sales = {}
	for purchaseId, serial in StockRules.Normalize(raw).log do
		if serial > 0 then
			table.insert(sales, { PurchaseId = purchaseId, Serial = serial })
		end
	end
	table.sort(sales, function(a, b)
		return a.Serial > b.Serial
	end)
	while #sales > count do
		table.remove(sales)
	end
	return sales
end

return StockRules
