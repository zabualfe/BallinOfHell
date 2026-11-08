local PlayerData = require(script.Parent.Parent.Parent.PlayerData)

return function(_context, player)
	if not PlayerData.IsLoaded(player) then
		return player.Name .. "'s data is not loaded."
	end
	PlayerData.Set(player, "hasPickedStarter", false)
	return "Reset onboarding for " .. player.Name .. "."
end
