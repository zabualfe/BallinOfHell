-- InventoryRules
-- Pure ball-ownership rules, no engine calls. Used by InventoryService and OnboardingService (server) and
-- usable by UI to list the starter choices.
--
-- Usage:
--   InventoryRules.StarterIds() -> sorted array of ball ids with Source == "Starter"
--   InventoryRules.IsStarter(ballId) -> boolean
--   InventoryRules.IsSourceAllowed(ballId, source) -> boolean
--   InventoryRules.DecideGrant(ballId, source, ownedBalls) -> ok, reason
--     reason: "Unknown" | "Owned" | "WrongSource" (nil when ok)
--   InventoryRules.CanPickStarter(ballId, hasPickedStarter) -> boolean
--
-- Source strings passed to GrantBall:
--   "Starter"      FTUE pick (OnboardingService), Starter balls only
--   "Coins"        Coin shop purchase; also accepted for Starter balls (they are sold in the shop too)
--   "Robux"        Buy-by-rarity product; same balls as "Coins"
--   "Wheel" "Daily" "Timed" "StarterPack" "RobuxLimited" "Seasonal"
--                  Exclusives: only granted with a source equal to the ball's own BallTable.Source
--   "Admin"        Admin commands only (AdminService); may grant any known ball

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BallTable = require(ReplicatedStorage.Tables.BallTable)

local InventoryRules = {}

local SHOP_SOURCES = { Coins = true, Robux = true } -- sources that may grant shop (Coins/Starter) balls
local ADMIN_SOURCE = "Admin"

local starterIds = {}
for ballId, ball in BallTable do
	if ball.Source == "Starter" then
		table.insert(starterIds, ballId)
	end
end
table.sort(starterIds, function(a, b)
	return BallTable[a].Order < BallTable[b].Order
end)

function InventoryRules.StarterIds()
	return table.clone(starterIds)
end

function InventoryRules.IsStarter(ballId)
	if type(ballId) ~= "string" then
		return false
	end
	local ball = BallTable[ballId]
	return ball ~= nil and ball.Source == "Starter"
end

function InventoryRules.IsSourceAllowed(ballId, source)
	if type(ballId) ~= "string" or type(source) ~= "string" then
		return false
	end
	local ball = BallTable[ballId]
	if not ball then
		return false
	end
	if source == ADMIN_SOURCE then
		return true
	end
	if ball.Source == "Starter" or ball.Source == "Coins" then
		return source == ball.Source or SHOP_SOURCES[source] == true
	end
	return source == ball.Source
end

function InventoryRules.DecideGrant(ballId, source, ownedBalls)
	if type(ballId) ~= "string" or BallTable[ballId] == nil then
		return false, "Unknown"
	end
	if ownedBalls and ownedBalls[ballId] ~= nil then
		return false, "Owned"
	end
	if not InventoryRules.IsSourceAllowed(ballId, source) then
		return false, "WrongSource"
	end
	return true, nil
end

function InventoryRules.CanPickStarter(ballId, hasPickedStarter)
	return hasPickedStarter ~= true and InventoryRules.IsStarter(ballId)
end

return InventoryRules
