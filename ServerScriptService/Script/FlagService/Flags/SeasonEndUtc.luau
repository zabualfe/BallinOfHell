-- SeasonEndUtc (GDD 8.2): end of the active season, Unix seconds. Defaults to SeasonTable's end for
-- the default season (0 until the Director sets it).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SeasonTable = require(ReplicatedStorage.Tables.SeasonTable)
local ActiveSeasonId = require(script.Parent.ActiveSeasonId)

local season = SeasonTable.Seasons[ActiveSeasonId.Default]

local SeasonEndUtc = {
	Key = "SeasonEndUtc",
	Default = season and season.EndUtc or 0,
	Disabled = false,
	ClientVisible = true,
}

return SeasonEndUtc
