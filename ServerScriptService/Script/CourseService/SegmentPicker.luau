-- SegmentPicker
-- Pure course picker (GDD 5.3). No Instances, no warn: problems come back as strings so the caller logs them.
--
-- Usage:
--   SegmentPicker.Pick(pool, slots, random, lastPicks?, config?) -> picks?, sourceTiers?, notes
--     pool       -- { [tierName] = { { Name = string, Weight = number?, ToolRequired = boolean? }, ... } }
--     slots      -- list of tier names, one per slot (CourseTable.Slots)
--     random     -- a Random; the same seed and inputs give the same result
--     lastPicks  -- last round's names per slot, or nil
--     config     -- CourseTable.Picker + Tiers (defaults to CourseTable)
--   picks[i] is the segment name for slot i, sourceTiers[i] the tier pool it came from (differs from
--   slots[i] only when that tier was empty). notes is a list of human-readable warnings.
--   Returns nil, nil, notes when no tier has any segment.
--
-- Rules, in order: no repeat while the tier pool lasts; once it runs out, reuse the least recently
-- used segment but never in adjacent slots; avoid last round's pick per slot; at most N ToolRequired
-- segments per course and never two in a row. The last-round and ToolRequired rules are soft: skipped if they would leave no choice.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CourseTable = require(ReplicatedStorage.Tables.CourseTable)
local Weighted = require(ReplicatedStorage.Utilities.Weighted)

local SegmentPicker = {}

local function keyOf(tier, entry)
	return tier .. "/" .. entry.Name
end

-- Nearest non-empty tier by Order; ties go to the easier tier.
local function resolveTier(tier, pool, tiers)
	local list = pool[tier]
	if list and #list > 0 then
		return tier
	end
	local wanted = tiers[tier] and tiers[tier].Order or 0
	local best, bestDistance, bestOrder
	for name, entries in pool do
		if #entries > 0 and tiers[name] then
			local order = tiers[name].Order
			local distance = math.abs(order - wanted)
			if best == nil or distance < bestDistance or (distance == bestDistance and order < bestOrder) then
				best, bestDistance, bestOrder = name, distance, order
			end
		end
	end
	return best
end

local function filter(list, keep)
	local kept = {}
	for _, entry in list do
		if keep(entry) then
			table.insert(kept, entry)
		end
	end
	return kept
end

-- Soft rule: apply the filter only if something survives.
local function softFilter(list, keep)
	local kept = filter(list, keep)
	if #kept == 0 then
		return list
	end
	return kept
end

local function withWeight(list, defaultWeight)
	local weighted = {}
	for _, entry in list do
		table.insert(weighted, { Weight = entry.Weight or defaultWeight, Entry = entry })
	end
	return weighted
end

function SegmentPicker.Pick(pool, slots, random, lastPicks, config)
	config = config or CourseTable.Picker
	local tiers = config.Tiers or CourseTable.Tiers
	local notes = {}
	local picks, sourceTiers = {}, {}
	local usedKeys = {} -- key -> true, this course
	local lastUsedSlot = {} -- key -> slot index
	local toolCount = 0
	local previousToolRequired = false

	for slot, slotTier in slots do
		local tier = resolveTier(slotTier, pool, tiers)
		if not tier then
			table.insert(notes, ("no segments in any tier (slot %d wants %s)"):format(slot, slotTier))
			return nil, nil, notes
		end
		if tier ~= slotTier then
			table.insert(notes, ("slot %d: tier %s is empty, using %s"):format(slot, slotTier, tier))
		end

		local previousName = picks[slot - 1]
		local previousTier = sourceTiers[slot - 1]
		local lastName = lastPicks and lastPicks[slot]
		local candidates = filter(pool[tier], function(entry)
			return not usedKeys[keyOf(tier, entry)]
		end)

		local chosen
		if #candidates > 0 then
			candidates = softFilter(candidates, function(entry)
				return entry.Name ~= lastName
			end)
			candidates = softFilter(candidates, function(entry)
				if not entry.ToolRequired then
					return true
				end
				if toolCount >= config.MaxToolRequiredPerCourse then
					return false
				end
				return config.AllowAdjacentToolRequired or not previousToolRequired
			end)
			local picked = Weighted.Pick(withWeight(candidates, config.DefaultWeight or 1), random)
			chosen = picked and picked.Entry
			if not chosen then
				-- All weights were non-positive: treat as equal rather than skipping the slot.
				chosen = candidates[random:NextInteger(1, #candidates)]
			end
		else
			-- Pool exhausted: least recently used, never next to itself.
			local reusable = filter(pool[tier], function(entry)
				return tier ~= previousTier or entry.Name ~= previousName
			end)
			if #reusable == 0 then
				reusable = pool[tier]
				table.insert(
					notes,
					("slot %d: tier %s has one segment, repeating %s adjacently"):format(slot, tier, reusable[1].Name)
				)
			end
			local oldest = math.huge
			for _, entry in reusable do
				oldest = math.min(oldest, lastUsedSlot[keyOf(tier, entry)] or 0)
			end
			local oldestEntries = filter(reusable, function(entry)
				return (lastUsedSlot[keyOf(tier, entry)] or 0) == oldest
			end)
			oldestEntries = softFilter(oldestEntries, function(entry)
				return entry.Name ~= lastName
			end)
			local picked = Weighted.Pick(withWeight(oldestEntries, config.DefaultWeight or 1), random)
			chosen = picked and picked.Entry or oldestEntries[random:NextInteger(1, #oldestEntries)]
		end

		picks[slot] = chosen.Name
		sourceTiers[slot] = tier
		usedKeys[keyOf(tier, chosen)] = true
		lastUsedSlot[keyOf(tier, chosen)] = slot
		previousToolRequired = chosen.ToolRequired == true
		if previousToolRequired then
			toolCount += 1
		end
	end

	return picks, sourceTiers, notes
end

return SegmentPicker
