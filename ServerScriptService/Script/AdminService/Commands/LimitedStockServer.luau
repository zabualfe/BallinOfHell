local LimitedBallService = require(script.Parent.Parent.Parent.LimitedBallService)

return function()
	local stock = LimitedBallService.GetStock()
	if stock == nil then
		return "Stock is unavailable (store call failed or the limited ball is disabled)."
	end
	return ("Crown of Hell: %d / %d sold, %d left, %d active reservation(s)."):format(
		stock.Sold,
		stock.Cap,
		stock.Remaining,
		stock.Reservations
	)
end
