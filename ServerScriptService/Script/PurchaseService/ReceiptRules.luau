-- ReceiptRules
-- Pure ProcessReceipt decisions and purchaseLog upkeep, no engine calls. PurchaseService feeds it facts and maps
-- the outcome to Enum.ProductPurchaseDecision.
--
-- Usage:
--   ReceiptRules.Decide(input, runEffect) -> outcome, reason, detail?
--     input = { Known, InServer, Loaded, Logged, InFlight } (booleans)
--     runEffect() -> boolean is only called when every check passes, inside a pcall.
--     outcome = "Granted" | "NotYet". Granted for a PurchaseId already logged (Roblox retried a finished receipt).
--     reason  = "UnknownProduct" | "PlayerGone" | "NotLoaded" | "Duplicate" | "InFlight" | "EffectError" |
--               "EffectDeclined" | "Granted"
--   ReceiptRules.HasPurchase(log, purchaseId) -> boolean
--   ReceiptRules.AppendLog(log, purchaseId, cap) -> new list   -- oldest dropped past cap; no-op for a known id

local ReceiptRules = {}

function ReceiptRules.Decide(input, runEffect)
	if not input.Known then
		return "NotYet", "UnknownProduct"
	end
	if not input.InServer then
		return "NotYet", "PlayerGone"
	end
	if not input.Loaded then
		return "NotYet", "NotLoaded"
	end
	if input.Logged then
		return "Granted", "Duplicate"
	end
	-- A second delivery of the same receipt while the first still yields in its Effect must not grant twice.
	if input.InFlight then
		return "NotYet", "InFlight"
	end

	local ok, result = pcall(runEffect)
	if not ok then
		return "NotYet", "EffectError", result
	end
	if result ~= true then
		return "NotYet", "EffectDeclined"
	end
	return "Granted", "Granted"
end

function ReceiptRules.HasPurchase(log, purchaseId)
	return table.find(log, purchaseId) ~= nil
end

function ReceiptRules.AppendLog(log, purchaseId, cap)
	local out = table.clone(log)
	if table.find(out, purchaseId) then
		return out
	end
	table.insert(out, purchaseId)
	while #out > cap do
		table.remove(out, 1)
	end
	return out
end

return ReceiptRules
