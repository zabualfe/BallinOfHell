-- AdminService
-- Owns the Cmdr admin console (vendored at ServerStorage/Cmdr). Registers Cmdr's default commands plus ours
-- from AdminService/Commands, gates every command behind one BeforeRun hook, and sets the player attribute
-- "IsAdmin" that the client loader (ReplicatedStorage/Modules/AdminClient) reads before activating the console.
--
-- Who is an admin (rules in AdminService/Permission, specced offline): Studio sessions, the game creator
-- (the owner, or a group member at or above GROUP_OWNER_MIN_RANK), and UserIds in ADMIN_USER_IDS.
-- Status is resolved once on join, because a BeforeRun hook must not yield; unresolved means denied.
--
-- Public API:
--   AdminService.IsAdmin(player) -> boolean
--
-- Adding a command: drop a pair of ModuleScripts in AdminService/Commands.
--   MyCommand.luau        -- definition: { Name, Aliases?, Description, Group = "BallOfHell", Args = { { Type, Name,
--                            Description, Optional? } } }. Types: player, integer, number, string, boolean.
--   MyCommandServer.luau  -- `return function(context, ...args) -> string` run on the server; the returned string
--                            is printed in the console. Call other systems only through their public APIs.
-- The Server file must be named <Command file name>Server. Nothing else needs registering. Permissions apply
-- automatically through the hook; never check them inside a command.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Cmdr = require(ServerStorage:WaitForChild("Cmdr"))
local Permission = require(script.Permission)

local AdminService = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local ADMIN_USER_IDS = {} -- UserIds allowed on live servers besides the creator
local GROUP_OWNER_MIN_RANK = 254 -- group rank that counts as the creator for group-owned games
local DENIED_MESSAGE = "You do not have permission to run this command."
local ATTRIBUTE_NAME = "IsAdmin"

-- ── State ───────────────────────────────────────────────────────────────
local adminPlayers = {} -- [player] = true once resolved as admin

local function lookupGroupRank(player)
	if game.CreatorType ~= Enum.CreatorType.Group then
		return nil
	end
	local ok, rank = pcall(player.GetRankInGroup, player, game.CreatorId)
	if not ok then
		warn(("[AdminService] Group rank lookup failed for %s: %s"):format(player.Name, tostring(rank)))
		return nil
	end
	return rank
end

local function resolveAdmin(player)
	local isCreator = Permission.IsCreator(
		if game.CreatorType == Enum.CreatorType.Group then "Group" else "User",
		game.CreatorId,
		player.UserId,
		lookupGroupRank(player),
		GROUP_OWNER_MIN_RANK
	)
	return Permission.IsAdmin(RunService:IsStudio(), isCreator, player.UserId, ADMIN_USER_IDS)
end

function AdminService.IsAdmin(player)
	return adminPlayers[player] == true
end

local function onPlayerAdded(player)
	if not resolveAdmin(player) or player.Parent == nil then
		return
	end
	adminPlayers[player] = true
	player:SetAttribute(ATTRIBUTE_NAME, true)
end

Cmdr.Registry:RegisterDefaultCommands()
Cmdr.Registry:RegisterCommandsIn(script.Commands)
Cmdr.Registry:RegisterHook("BeforeRun", function(context)
	if not adminPlayers[context.Executor] then
		return DENIED_MESSAGE
	end
	return nil
end)

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	adminPlayers[player] = nil
end)

return AdminService
