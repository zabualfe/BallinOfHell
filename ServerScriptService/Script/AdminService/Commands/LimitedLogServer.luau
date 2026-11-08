local LimitedBallService = require(script.Parent.Parent.Parent.LimitedBallService)

local DEFAULT_COUNT = 10
local MAX_COUNT = 50 -- keeps the console readable

return function(_context, count)
	count = math.clamp(count or DEFAULT_COUNT, 1, MAX_COUNT)
	local sales = LimitedBallService.GetLog(count)
	if sales == nil then
		return "Sale log is unavailable (store call failed or the limited ball is disabled)."
	end
	if #sales == 0 then
		return "No sales yet."
	end
	local lines = {}
	for _, sale in sales do
		table.insert(lines, ("#%d  %s"):format(sale.Serial, sale.PurchaseId))
	end
	return table.concat(lines, "\n")
end
