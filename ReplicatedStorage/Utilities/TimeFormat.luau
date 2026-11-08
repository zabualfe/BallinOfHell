-- TimeFormat
-- Shared duration formatting. Inputs are seconds; negatives clamp to 0.
--
-- Usage:
--   TimeFormat.Clock(75) -> "1:15"       (m:ss, or h:mm:ss from one hour)
--   TimeFormat.Clock(75, true) -> "01:15" (zero-padded mm:ss)
--   TimeFormat.Short(7500) -> "2h 5m"    ("45s", "3m 10s", "2h 5m", "1d 3h")

local TimeFormat = {}

function TimeFormat.Clock(seconds, padMinutes)
	local total = math.max(0, math.floor(seconds))
	local hours = total // 3600
	local minutes = total % 3600 // 60
	local secs = total % 60
	if hours > 0 then
		return ("%d:%02d:%02d"):format(hours, minutes, secs)
	end
	return (if padMinutes then "%02d:%02d" else "%d:%02d"):format(minutes, secs)
end

function TimeFormat.Short(seconds)
	local total = math.max(0, math.floor(seconds))
	local days = total // 86400
	local hours = total % 86400 // 3600
	local minutes = total % 3600 // 60
	local secs = total % 60
	if days > 0 then
		return ("%dd %dh"):format(days, hours)
	elseif hours > 0 then
		return ("%dh %dm"):format(hours, minutes)
	elseif minutes > 0 then
		return ("%dm %ds"):format(minutes, secs)
	end
	return ("%ds"):format(secs)
end

return TimeFormat
