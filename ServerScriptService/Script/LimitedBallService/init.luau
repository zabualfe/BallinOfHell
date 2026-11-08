-- LimitedBallService
-- Crown of Hell: 1,000 ever, serial = sale order (ARCHITECTURE 6.7, GDD 10.7). A developer product, because game
-- passes can't be capped. Owns the global stock, the checkout reservations and the live counter. The Robux flow
-- itself stays in PurchaseService: Products/CrownOfHell registers CanPrompt and OnReceipt below.
--
-- Usage:
--   LimitedBallService.CanPrompt(player) -> boolean   -- not owned, a slot is free; reserves one for 5 minutes
--   LimitedBallService.OnReceipt(player, receiptInfo) -> boolean   -- the product Effect. false = Roblox retries
--   LimitedBallService.GetStock() -> { Cap, Sold, Remaining, Reservations }?   -- nil when a store call failed
--   LimitedBallService.GetLog(count) -> list of { PurchaseId, Serial }?        -- newest sales first
--
-- Stock: DataStore `LimitedStock` = { sold, log }, written only with UpdateAsync (see StockRules / StockStore).
-- Reservations: MemoryStore HashMap keyed by UserId with a TTL. Released on an abandoned prompt, on the receipt,
-- and on leaving without a bought prompt; otherwise the TTL clears them. A store failure means "no prompt" at
-- CanPrompt and "retry" at the receipt.
-- Receipt: idempotent UpdateAsync (keyed by PurchaseId) -> serial -> ball with serial -> release. Sold out at
-- receipt time (outage only) pays the consolation from ProductTable.CrownOfHell.Params.Consolation and logs it.
--
-- Live counter: workspace attribute `LimitedRemaining` (the real number, sold only), refreshed by a
-- MessagingService broadcast on every sale and by a 60 s poll. Owners get the player attribute `LimitedSerial`.
-- Studio uses separate store / topic names (suffix `_Studio`) so testing never touches live stock.
-- Network: none. The UI reads the attributes and prompts with PromptProduct("CrownOfHell").

local MarketplaceService = game:GetService("MarketplaceService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnalyticsTable = require(ReplicatedStorage.Tables.AnalyticsTable)
local BallTable = require(ReplicatedStorage.Tables.BallTable)
local ProductTable = require(ReplicatedStorage.Tables.ProductTable)

local AnalyticsService = require(script.Parent.AnalyticsService)
local InventoryService = require(script.Parent.InventoryService)
local PlayerData = require(script.Parent.PlayerData)
local RewardService = require(script.Parent.RewardService)
local StockRules = require(script.StockRules)
local StockStore = require(script.StockStore)

local LimitedBallService = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local PRODUCT_KEY = "CrownOfHell"
local DATASTORE_NAME = "LimitedBall"
local STOCK_KEY = "LimitedStock"
local RESERVATION_MAP = "LimitedReservations"
local TOPIC = "LimitedSold"
local STUDIO_SUFFIX = "_Studio"
local RESERVATION_SECONDS = 300 -- 5 minutes
local POLL_SECONDS = 60
local BALL_SOURCE = "RobuxLimited"
local CONSOLATION_SOURCE = "Robux" -- coins unmultiplied
local REMAINING_ATTRIBUTE = "LimitedRemaining"
local SERIAL_ATTRIBUTE = "LimitedSerial"

-- ── State ───────────────────────────────────────────────────────────────
local product = ProductTable[PRODUCT_KEY]
local ballId = product and product.Params and product.Params.BallId
local consolation = product and product.Params and product.Params.Consolation
local cap = ballId and BallTable[ballId] and BallTable[ballId].Stock
local awaitingReceipt = {} -- [userId] = true once the prompt was bought, until the receipt releases the hold
local knownSold = nil -- highest sold count seen (store reads and broadcasts); sold only grows
local store = nil

if type(ballId) ~= "string" or type(cap) ~= "number" or type(consolation) ~= "table" then
	warn(
		"[LimitedBallService] ProductTable.CrownOfHell / BallTable Stock are misconfigured; the limited ball is disabled"
	)
else
	local suffix = if RunService:IsStudio() then STUDIO_SUFFIX else ""
	TOPIC ..= suffix
	store = StockStore.new({
		DataStore = DataStoreService:GetDataStore(DATASTORE_NAME .. suffix),
		Reservations = MemoryStoreService:GetHashMap(RESERVATION_MAP .. suffix),
		Key = STOCK_KEY,
		Cap = cap,
		ReservationSeconds = RESERVATION_SECONDS,
	})
end

-- ── Counter ─────────────────────────────────────────────────────────────

local function noteSold(sold)
	if knownSold ~= nil and sold <= knownSold then
		return
	end
	knownSold = sold
	workspace:SetAttribute(REMAINING_ATTRIBUTE, StockRules.Remaining(sold, cap))
end

local function refreshFromStore()
	local ok, sold = store:ReadSold()
	if ok then
		noteSold(sold)
	end
end

local function syncSerial(player)
	local owned = PlayerData.Peek(player, "ownedBalls")
	local entry = owned and owned[ballId]
	local serial = entry and entry.serial or nil
	if player:GetAttribute(SERIAL_ATTRIBUTE) ~= serial then
		player:SetAttribute(SERIAL_ATTRIBUTE, serial)
	end
end

local function broadcast(sold)
	task.spawn(function()
		local ok, err = pcall(MessagingService.PublishAsync, MessagingService, TOPIC, { sold = sold })
		if not ok then
			warn(`[LimitedBallService] Broadcast failed: {tostring(err)}`)
		end
	end)
end

-- ── Prompting ───────────────────────────────────────────────────────────

function LimitedBallService.CanPrompt(player)
	if store == nil or not PlayerData.IsLoaded(player) or InventoryService.OwnsBall(player, ballId) then
		return false
	end
	local ok, reason = store:Reserve(player.UserId)
	if not ok then
		if reason == "StoreError" then
			warn(`[LimitedBallService] Could not reserve a slot for {player.Name}: store unavailable`)
		end
		return false
	end
	return true
end

-- ── Receipt ─────────────────────────────────────────────────────────────

local function grantConsolation(player, receiptInfo, why)
	-- Trail first: it is idempotent, so a retry after a failed coin grant can't pay the trail twice.
	local granted = RewardService.Grant(player, {
		{ Type = "Trail", Id = consolation.TrailId, Name = consolation.TrailName },
		{ Type = "Coins", Amount = consolation.Coins },
	}, CONSOLATION_SOURCE)
	if not granted then
		return false
	end
	warn(`[LimitedBallService] Consolation paid to {player.Name} (purchase {receiptInfo.PurchaseId}): {why}`)
	AnalyticsService.Custom(player, AnalyticsTable.Events.LimitedConsolation, consolation.Coins, { Reason = why })
	return true
end

local function finishSale(player, serial)
	syncSerial(player)
	AnalyticsService.Custom(player, AnalyticsTable.Events.LimitedSold, serial)
end

function LimitedBallService.OnReceipt(player, receiptInfo)
	if store == nil or not PlayerData.IsLoaded(player) then
		return false
	end
	local committed, outcome = store:Commit(receiptInfo.PurchaseId)
	if not committed then
		return false
	end

	local granted
	if outcome.Status == "Sold" then
		noteSold(math.max(outcome.Serial, knownSold or 0))
		if not outcome.Replayed then
			broadcast(outcome.Serial)
		end
		granted = InventoryService.GrantBall(player, ballId, BALL_SOURCE, { serial = outcome.Serial })
		if not granted then
			local owned = PlayerData.Peek(player, "ownedBalls")
			local entry = owned and owned[ballId]
			if entry == nil then
				return false
			elseif entry.serial == outcome.Serial then
				granted = true -- a retry after the grant already landed
			else
				-- Bought in two servers at once: the second serial is spent, so the buyer gets the consolation.
				granted = grantConsolation(player, receiptInfo, `already owned, serial {outcome.Serial} unused`)
			end
		end
		if granted then
			finishSale(player, outcome.Serial)
		end
	else
		granted = grantConsolation(player, receiptInfo, "sold out at receipt time")
	end

	if not granted then
		return false
	end
	awaitingReceipt[player.UserId] = nil
	store:Release(player.UserId)
	return true
end

-- ── Admin reads ─────────────────────────────────────────────────────────

function LimitedBallService.GetStock()
	if store == nil then
		return nil
	end
	local soldOk, sold = store:ReadSold()
	local countOk, reservations = store:CountReservations()
	if not soldOk or not countOk then
		return nil
	end
	return {
		Cap = cap,
		Sold = sold,
		Remaining = StockRules.Remaining(sold, cap),
		Reservations = reservations,
	}
end

function LimitedBallService.GetLog(count)
	if store == nil then
		return nil
	end
	local ok, _, raw = store:ReadSold()
	if not ok then
		return nil
	end
	return StockRules.RecentSales(raw, count)
end

-- ── Wiring ──────────────────────────────────────────────────────────────

local function setupPlayer(player)
	if not PlayerData.WaitForLoaded(player, 60) then
		return
	end
	syncSerial(player)
	PlayerData.OnUpdate(player, "ownedBalls", function()
		syncSerial(player)
	end)
end

if store ~= nil then
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, wasPurchased)
		if product.Id == 0 or productId ~= product.Id then
			return
		end
		if wasPurchased then
			awaitingReceipt[userId] = true -- the receipt releases the hold
		else
			store:Release(userId)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		if not awaitingReceipt[player.UserId] then
			store:Release(player.UserId)
		end
		awaitingReceipt[player.UserId] = nil
	end)

	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(setupPlayer, player)
	end

	task.spawn(function()
		local ok, err = pcall(MessagingService.SubscribeAsync, MessagingService, TOPIC, function(message)
			local data = message.Data
			if type(data) == "table" and type(data.sold) == "number" then
				noteSold(data.sold)
			end
		end)
		if not ok then
			warn(`[LimitedBallService] Live counter subscription failed (the 60 s poll still runs): {tostring(err)}`)
		end
	end)

	task.spawn(function()
		while true do
			refreshFromStore()
			task.wait(POLL_SECONDS)
		end
	end)
end

return LimitedBallService
