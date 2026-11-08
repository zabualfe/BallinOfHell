-- GamePassService
-- Owns game pass ownership (PassTable). Passes are checked with UserOwnsGamePassAsync, never through receipts.
-- The result is cached per player at join, so every other system reads Owns() without yielding.
--
-- Usage:
--   GamePassService.Owns(player, passKey) -> boolean   -- non-yielding; false until the check finishes or if Id = 0
--   GamePassService.PassChanged:Connect(function(player, passKey, owns) end)
--       Fires after the join check for every pass the player owns, and when a prompt ends in a purchase.
--
-- Network (client -> server): PromptPass(passKey)   -- rate limited; the server validates and prompts, nothing else.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage.Network)
local PassTable = require(ReplicatedStorage.Tables.PassTable)
local Signal = require(ReplicatedStorage.Utilities.Signal)

local GamePassService = {}
GamePassService.PassChanged = Signal.new() -- (player, passKey, owns)

-- ── Tuning ──────────────────────────────────────────────────────────────
local PROMPT_RATE = { Capacity = 3, RefillPerSecond = 0.5 } -- PromptPass burst / per second
local CHECK_ATTEMPTS = 3 -- UserOwnsGamePassAsync tries per pass
local CHECK_RETRY_SECONDS = 2 -- base backoff; doubles each retry

-- ── State ───────────────────────────────────────────────────────────────
local cache = {} -- [player] = { [passKey] = boolean }
local passKeyById = {}
local warnedPlaceholders = false

for key, pass in PassTable do
	if pass.Id ~= 0 then
		passKeyById[pass.Id] = key
	end
end

local function setOwned(player, passKey, owns)
	local owned = cache[player]
	if not owned or (owned[passKey] == true) == owns then
		return
	end
	owned[passKey] = owns
	GamePassService.PassChanged:Fire(player, passKey, owns)
end

function GamePassService.Owns(player, passKey)
	local owned = cache[player]
	return owned ~= nil and owned[passKey] == true
end

local function loadPlayer(player)
	local owned = {}
	cache[player] = owned
	for key, pass in PassTable do
		if pass.Id == 0 then
			if not warnedPlaceholders then
				warnedPlaceholders = true
				warn("[GamePassService] Passes with Id = 0 are placeholders and always read as not owned")
			end
			continue
		end
		local ok, result
		for attempt = 1, CHECK_ATTEMPTS do
			ok, result = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.Id)
			if cache[player] ~= owned then
				return
			end
			if ok or attempt == CHECK_ATTEMPTS then
				break
			end
			task.wait(CHECK_RETRY_SECONDS * 2 ^ (attempt - 1))
			if cache[player] ~= owned then
				return
			end
		end
		if ok then
			setOwned(player, key, result == true)
		else
			warn(`[GamePassService] Ownership check for {key} failed: {tostring(result)}`)
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(loadPlayer, player)
end)
for _, player in Players:GetPlayers() do
	task.spawn(loadPlayer, player)
end

Players.PlayerRemoving:Connect(function(player)
	cache[player] = nil
end)

-- ── Prompting ───────────────────────────────────────────────────────────

Network.OnEvent("PromptPass", function(player, passKey)
	local pass = type(passKey) == "string" and PassTable[passKey] or nil
	if pass == nil or pass.Id == 0 or cache[player] == nil or GamePassService.Owns(player, passKey) then
		return
	end
	local ok, err = pcall(MarketplaceService.PromptGamePassPurchase, MarketplaceService, player, pass.Id)
	if not ok then
		warn(`[GamePassService] Prompt for {passKey} failed: {tostring(err)}`)
	end
end, PROMPT_RATE)

-- Passes are the one thing the finished event may update; it only fills the cache, rewards come from the pass checks.
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
	local passKey = passKeyById[passId]
	if wasPurchased and passKey and player.Parent then
		setOwned(player, passKey, true)
	end
end)

return GamePassService
