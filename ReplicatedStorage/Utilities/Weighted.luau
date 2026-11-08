-- Weighted
-- Weighted random pick. The caller passes its own Random so results are seedable.
--
-- Usage:
--   Weighted.Pick(list, random) -> entry         -- list of { Weight = n, ... }
--   Weighted.PickKey(map, random) -> key, entry  -- map of key -> { Weight = n, ... }
-- Both return nil when empty or when the total weight is not positive. Entries with
-- non-positive weight are never picked.

local Weighted = {}

local function weightOf(entry)
	local weight = entry.Weight
	if type(weight) ~= "number" or weight <= 0 then
		return 0
	end
	return weight
end

function Weighted.Pick(list, random)
	local total = 0
	for _, entry in list do
		total += weightOf(entry)
	end
	if total <= 0 then
		return nil
	end

	local roll = random:NextNumber() * total
	local lastValid
	for _, entry in list do
		local weight = weightOf(entry)
		if weight > 0 then
			lastValid = entry
			roll -= weight
			if roll < 0 then
				return entry
			end
		end
	end
	-- Float rounding can leave a sliver of roll; fall back to the last eligible entry.
	return lastValid
end

function Weighted.PickKey(map, random)
	-- Sort keys so a seeded Random gives the same result regardless of table order.
	local keys = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)

	local list = {}
	for _, key in keys do
		table.insert(list, { Weight = weightOf(map[key]), Key = key })
	end
	local picked = Weighted.Pick(list, random)
	if not picked then
		return nil
	end
	return picked.Key, map[picked.Key]
end

return Weighted
