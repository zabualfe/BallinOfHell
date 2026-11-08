-- TimedRewardService/Rules
-- Pure playtime-gift maths (GDD 10.4). No engine calls.
--
--   Rules.IsUnlocked(gift, seconds) -> boolean
--   Rules.CanClaim(gifts, index, seconds, claimed) -> boolean   -- claimed = { [index] = true } this session
--   Rules.Remaining(gifts, seconds, claimed) -> { index... }     -- unlocked, unclaimed, ascending
--   Rules.WaitingCount(gifts, seconds, claimed) -> number
--   Rules.Mask(claimed, count) -> integer                        -- bit (index - 1) set per claimed gift
--   Rules.GrantedBall(summary, ballId) -> boolean                -- the grant summary contains that ball
--   Rules.BuildEntry(gift, everClaimed) -> reward entry for RewardService.Grant

local Rules = {}

function Rules.IsUnlocked(gift, seconds)
	return seconds >= gift.Minute * 60
end

function Rules.CanClaim(gifts, index, seconds, claimed)
	local gift = type(index) == "number" and index % 1 == 0 and gifts[index] or nil
	return gift ~= nil and claimed[index] ~= true and Rules.IsUnlocked(gift, seconds)
end

function Rules.Remaining(gifts, seconds, claimed)
	local list = {}
	for index in gifts do
		if Rules.CanClaim(gifts, index, seconds, claimed) then
			table.insert(list, index)
		end
	end
	return list
end

function Rules.WaitingCount(gifts, seconds, claimed)
	return #Rules.Remaining(gifts, seconds, claimed)
end

function Rules.Mask(claimed, count)
	local mask = 0
	for index = 1, count do
		if claimed[index] then
			mask += 2 ^ (index - 1)
		end
	end
	return mask
end

function Rules.GrantedBall(summary, ballId)
	for _, item in summary do
		if item.Kind == "Ball" and item.Id == ballId then
			return true
		end
	end
	return false
end

local function copyEntry(source)
	local entry = {}
	for key, value in source do
		if key ~= "Minute" then
			entry[key] = type(value) == "table" and table.clone(value) or value
		end
	end
	return entry
end

-- The once-ever ball becomes the Table's Fallback after it has been given. The ball entry keeps its Fallback
-- so RewardService can still substitute if the ball is owned some other way.
function Rules.BuildEntry(gift, everClaimed)
	local ballId = gift.OnceEverBall
	if ballId ~= nil and everClaimed[ballId] == true then
		return copyEntry(gift.Fallback or {})
	end
	return copyEntry(gift)
end

return Rules
