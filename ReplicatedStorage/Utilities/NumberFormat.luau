-- NumberFormat
-- Shared number formatting.
--
-- Usage:
--   NumberFormat.Commas(1234567) -> "1,234,567"
--   NumberFormat.Abbreviate(1234) -> "1.2K"; 3400000 -> "3.4M"; 999 -> "999"

local NumberFormat = {}

local SUFFIXES = { "K", "M", "B", "T", "Qa", "Qi" }

function NumberFormat.Commas(value)
	local sign = if value < 0 then "-" else ""
	local whole = tostring(math.floor(math.abs(value) + 0.5))
	local formatted = whole:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return sign .. formatted
end

function NumberFormat.Abbreviate(value)
	local sign = if value < 0 then "-" else ""
	local absolute = math.abs(value)
	if absolute < 1000 then
		return sign .. tostring(math.floor(absolute))
	end

	local tier = math.min(math.floor(math.log10(absolute) / 3), #SUFFIXES)
	local scaled = absolute / 10 ^ (tier * 3)
	-- Truncate rather than round so 999,999 never reads as "1000K".
	local truncated = math.floor(scaled * 10) / 10
	if truncated >= 1000 and tier < #SUFFIXES then
		tier += 1
		truncated = 1
	end
	local text = if truncated % 1 == 0 then tostring(math.floor(truncated)) else ("%.1f"):format(truncated)
	return sign .. text .. SUFFIXES[tier]
end

return NumberFormat
