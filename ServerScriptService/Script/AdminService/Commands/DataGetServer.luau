local HttpService = game:GetService("HttpService")

local PlayerData = require(script.Parent.Parent.Parent.PlayerData)

local MAX_OUTPUT_LENGTH = 2000 -- characters; keeps the console readable

return function(_context, player, key)
	if not PlayerData.IsLoaded(player) then
		return player.Name .. "'s data is not loaded."
	end
	local value = PlayerData.Get(player, key)
	if value == nil then
		return ("No data key %q."):format(key)
	end
	local ok, json = pcall(HttpService.JSONEncode, HttpService, value)
	if not ok then
		return ("Could not encode %q: %s"):format(key, tostring(json))
	end
	if #json > MAX_OUTPUT_LENGTH then
		json = json:sub(1, MAX_OUTPUT_LENGTH) .. "... (truncated)"
	end
	return key .. " = " .. json
end
