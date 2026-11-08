local EconomyService = require(script.Parent.Parent.Parent.EconomyService)

local MAX_GRANT = 1000000000 -- coins per command, either direction

return function(_context, player, amount)
	local before = EconomyService.GetCoins(player)
	local clamped = math.clamp(amount, -MAX_GRANT, MAX_GRANT)
	if clamped == 0 then
		return ("%s has %d coins."):format(player.Name, before)
	end

	local changed
	if clamped > 0 then
		changed = EconomyService.AddCoins(player, clamped, "Admin")
	else
		-- Removing never goes below zero.
		changed = EconomyService.SpendCoins(player, math.min(-clamped, before), "Admin")
	end
	if not changed then
		return "Could not change coins for " .. player.Name .. " (not loaded, or nothing to remove)."
	end
	local after = EconomyService.GetCoins(player)
	return ("%s now has %d coins (%+d)."):format(player.Name, after, after - before)
end
