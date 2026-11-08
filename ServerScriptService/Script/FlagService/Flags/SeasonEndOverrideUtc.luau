-- SeasonEndOverrideUtc (GDD 8.2): optional later end date that extends a season without a code update.
-- 0 = no override.

local SeasonEndOverrideUtc = {
	Key = "SeasonEndOverrideUtc",
	Default = 0,
	Disabled = false,
	ClientVisible = true,
}

return SeasonEndOverrideUtc
