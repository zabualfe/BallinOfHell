-- ActiveSeasonId (GDD 8.2): which SeasonTable.Seasons entry is live. Changing it in remote config
-- switches seasons without a code update. Season code reads this only through FlagService.

local ActiveSeasonId = {
	Key = "ActiveSeasonId",
	Default = "S1",
	Disabled = false,
	ClientVisible = true,
}

return ActiveSeasonId
