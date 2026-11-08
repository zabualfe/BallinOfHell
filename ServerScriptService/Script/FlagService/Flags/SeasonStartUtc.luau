-- SeasonStartUtc (GDD 8.2): start of the active season, Unix seconds. Defaults to the dates of the
-- default season in SeasonTable (0 until the Director sets them).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SeasonTable = require(ReplicatedStorage.Tables.SeasonTable)
local ActiveSeasonId = require(script.Parent.ActiveSeasonId)

local season = SeasonTable.Seasons[ActiveSeasonId.Default]

local SeasonStartUtc = {
	Key = "SeasonStartUtc",
	Default = season and season.StartUtc or 0,
	Disabled = false,
	ClientVisible = true,
}

return SeasonStartUtc
