-- Permission
-- Pure admin check, kept free of engine calls so it can be specced. AdminService gathers the inputs.

local Permission = {}

-- Returns true when the player may use the admin console.
--   isStudio     -- RunService:IsStudio()
--   isCreator    -- the game is user-owned and this is the owner, or group-owned and groupRank >= minGroupRank
--   adminUserIds -- array of UserIds
function Permission.IsAdmin(isStudio, isCreator, userId, adminUserIds)
	if isStudio or isCreator then
		return true
	end
	if type(userId) ~= "number" or type(adminUserIds) ~= "table" then
		return false
	end
	return table.find(adminUserIds, userId) ~= nil
end

-- groupRank is nil when the lookup failed, which denies.
function Permission.IsCreator(creatorType, creatorId, userId, groupRank, minGroupRank)
	if creatorType == "User" then
		return creatorId ~= 0 and creatorId == userId
	end
	if creatorType == "Group" then
		return type(groupRank) == "number" and groupRank >= minGroupRank
	end
	return false
end

return Permission
