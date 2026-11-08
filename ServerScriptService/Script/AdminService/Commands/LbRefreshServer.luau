local LeaderboardService = require(script.Parent.Parent.Parent.LeaderboardService)

return function(_context)
	local ok = LeaderboardService.Refresh()
	local boards = LeaderboardService.GetBoards()
	return ("%s: %d wins rows, %d fastest rows."):format(
		if ok then "Refreshed" else "Refresh incomplete (busy or a store call failed)",
		#boards.Wins,
		#boards.Fastest
	)
end
