-- PurchaseService
-- The ONLY setter of MarketplaceService.ProcessReceipt. Every developer product is granted here and nowhere
-- else, idempotently by PurchaseId (GDD 13). PromptProductPurchaseFinished is never a grant path.
--
-- Plug-in contract (one module per product family in PurchaseService/Products, see Products/Coins):
--   return {
--     Products = {
--       [productKey] = {                        -- key into ReplicatedStorage/Tables/ProductTable
--         Effect = function(player, receiptInfo, target?) -> boolean,
--           -- Grants through the owning system. true = granted, false = retry later (Roblox re-sends the receipt).
--           -- It must be safe to run once only: PurchaseService logs the PurchaseId after a true.
--           -- Targeted products read `target`; return false when it is missing.
--         CanPrompt = function(player, targetArg) -> boolean, target?,   -- optional
--           -- Gate for PromptProduct. The returned target is stored server-side for the receipt.
--       },
--     },
--   }
--   Families loaded here (Products/): Coins (Currency), Balls (buy-by-rarity), Boosts (2x Coins 30 min), Skips.
--   Left to their own tasks, which add families with PurchaseService.RegisterFamily(module): Season, Tools,
--   Tricks, Wheel, Offers (StarterPack, CrownOfHell, RestoreDailyStreak, UnlockAllTimedGifts), Modifiers
--   (server-wide and troll), RespawnHere and Gifting.
--
-- Usage:
--   PurchaseService.RegisterFamily(module) -> number   -- registers a plug-in's products; returns how many were
--       skipped (Id = 0 placeholders, unknown keys, duplicate ids). Call it at require time.
--
--   PurchaseService.CanOffer(player, productKey, targetArg?) -> boolean   -- true when PromptProduct would prompt it
--       now: a real Id, data loaded and CanPrompt passing. Read-only for UpsellService, so only call it for products
--       whose CanPrompt has no side effects (CrownOfHell reserves a stock slot, so it is never asked this way).
--
-- Receipt flow: unknown product, player gone or data not loaded -> NotProcessedYet. A PurchaseId already in
-- purchaseLog -> PurchaseGranted. Otherwise the Effect runs in a pcall; on true the id is logged (capped list),
-- stats.robuxSpent grows and the "Purchase/ReceiptGranted" funnel step fires.
--
-- Network (client -> server):
--   PromptProduct(productKey, targetArg?)   -- rate limited. The server validates the key and CanPrompt, stores
--       the target, then prompts. The client never grants anything.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage.Network)
local ProductTable = require(ReplicatedStorage.Tables.ProductTable)

local AnalyticsService = require(script.Parent.AnalyticsService)
local PlayerData = require(script.Parent.PlayerData)
local ReceiptRules = require(script.ReceiptRules)
local TargetStore = require(script.TargetStore)

local PurchaseService = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local PURCHASE_LOG_CAP = 100 -- recent PurchaseIds kept per player
local PROMPT_RATE = { Capacity = 3, RefillPerSecond = 0.5 } -- PromptProduct burst / per second
local FUNNEL = "Purchase"

-- ── State ───────────────────────────────────────────────────────────────
local productsById = {} -- [productId] = { Key, Name, Effect }
local definitionsByKey = {} -- [key] = { Id, Key, Name, Effect, CanPrompt }
local targets = TargetStore.new()
local inFlight = {} -- [purchaseId] = true while an Effect runs

-- ── Registry ────────────────────────────────────────────────────────────

local function registerFamily(module)
	local skipped = 0
	if type(module) ~= "table" or type(module.Products) ~= "table" then
		warn("[PurchaseService] RegisterFamily needs a module with a Products table")
		return 0
	end
	for key, definition in module.Products do
		local row = ProductTable[key]
		if row == nil or type(definition.Effect) ~= "function" then
			warn(`[PurchaseService] Plug-in product {tostring(key)} is not in ProductTable or has no Effect`)
			skipped += 1
		elseif definitionsByKey[key] ~= nil then
			warn(`[PurchaseService] Product {key} is registered twice`)
			skipped += 1
		else
			local entry = {
				Id = row.Id,
				Key = key,
				Name = row.Name,
				Effect = definition.Effect,
				CanPrompt = definition.CanPrompt,
			}
			definitionsByKey[key] = entry
			if row.Id == 0 then
				skipped += 1
			elseif productsById[row.Id] ~= nil then
				warn(`[PurchaseService] Product id {row.Id} is used by both {productsById[row.Id].Key} and {key}`)
				skipped += 1
			else
				productsById[row.Id] = entry
			end
		end
	end
	return skipped
end

function PurchaseService.RegisterFamily(module)
	local skipped = registerFamily(module)
	if skipped > 0 then
		warn(`[PurchaseService] {skipped} product(s) from a family were skipped (Id = 0 placeholder or invalid)`)
	end
	return skipped
end

local function loadFamilies()
	local skipped = 0
	for _, child in script.Products:GetChildren() do
		if child:IsA("ModuleScript") then
			local ok, module = pcall(require, child)
			if ok then
				skipped += registerFamily(module)
			else
				warn(`[PurchaseService] Family {child.Name} failed to load: {tostring(module)}`)
			end
		end
	end
	if skipped > 0 then
		warn(`[PurchaseService] {skipped} product(s) skipped at load (Id = 0 placeholders until the products exist)`)
	end
end

-- ── Receipts ────────────────────────────────────────────────────────────

local function robuxSpentBy(receiptInfo, key)
	local spent = receiptInfo.CurrencySpent
	if type(spent) == "number" and spent >= 0 then
		return spent
	end
	local price = ProductTable[key] and ProductTable[key].Price
	return type(price) == "number" and price or 0
end

local function recordPurchase(player, receiptInfo, key)
	-- The player can leave while an Effect yields; the grant stands, and Roblox re-sends the receipt on rejoin.
	if not PlayerData.IsLoaded(player) then
		return
	end
	local log = PlayerData.Get(player, "purchaseLog")
	if
		not PlayerData.Set(player, "purchaseLog", ReceiptRules.AppendLog(log, receiptInfo.PurchaseId, PURCHASE_LOG_CAP))
	then
		warn(`[PurchaseService] Could not log purchase {receiptInfo.PurchaseId} for {player.Name}`)
	end
	local stats = PlayerData.Get(player, "stats")
	stats.robuxSpent += robuxSpentBy(receiptInfo, key)
	PlayerData.Set(player, "stats", stats)
	AnalyticsService.Funnel(player, FUNNEL, "ReceiptGranted", key)
end

local function processReceipt(receiptInfo)
	local product = productsById[receiptInfo.ProductId]
	if product == nil then
		warn(`[PurchaseService] Unknown product id {tostring(receiptInfo.ProductId)}, will retry`)
	end

	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	local loaded = player ~= nil and PlayerData.IsLoaded(player)
	local purchaseId = receiptInfo.PurchaseId
	local outcome, reason, detail = ReceiptRules.Decide({
		Known = product ~= nil,
		InServer = player ~= nil,
		Loaded = loaded,
		Logged = loaded and ReceiptRules.HasPurchase(PlayerData.Peek(player, "purchaseLog"), purchaseId),
		InFlight = inFlight[purchaseId] == true,
	}, function()
		inFlight[purchaseId] = true
		local ok, result = pcall(function()
			return product.Effect(player, receiptInfo, targets:Get(player, product.Key))
		end)
		inFlight[purchaseId] = nil
		if not ok then
			error(result, 0)
		end
		return result
	end)

	if reason == "EffectError" then
		warn(`[PurchaseService] {product.Key} Effect errored: {tostring(detail)}`)
	elseif reason == "Granted" then
		targets:Clear(player, product.Key)
		recordPurchase(player, receiptInfo, product.Key)
	end

	if outcome == "Granted" then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

MarketplaceService.ProcessReceipt = processReceipt

-- ── Prompting ───────────────────────────────────────────────────────────

local function promptProduct(player, key, targetArg)
	if type(key) ~= "string" or not PlayerData.IsLoaded(player) then
		return
	end
	local definition = definitionsByKey[key]
	if definition == nil or definition.Id == 0 then
		return
	end

	local target = nil
	if definition.CanPrompt then
		local ok, allowed, resolved = pcall(definition.CanPrompt, player, targetArg)
		if not ok then
			warn(`[PurchaseService] {key} CanPrompt errored: {tostring(allowed)}`)
			return
		end
		if allowed ~= true then
			return
		end
		target = resolved
	end

	targets:Set(player, key, target)
	AnalyticsService.Funnel(player, FUNNEL, "PromptShown", key)
	local ok, err = pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, definition.Id)
	if not ok then
		targets:Clear(player, key)
		warn(`[PurchaseService] Prompt for {key} failed: {tostring(err)}`)
	end
end

function PurchaseService.CanOffer(player, key, targetArg)
	if type(key) ~= "string" or not PlayerData.IsLoaded(player) then
		return false
	end
	local definition = definitionsByKey[key]
	if definition == nil or definition.Id == 0 then
		return false
	end
	if definition.CanPrompt == nil then
		return true
	end
	local ok, allowed = pcall(definition.CanPrompt, player, targetArg)
	return ok and allowed == true
end

Network.OnEvent("PromptProduct", promptProduct, PROMPT_RATE)

-- Never grants. Only drops a target whose prompt was closed without buying.
MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, wasPurchased)
	local player = Players:GetPlayerByUserId(userId)
	local product = productsById[productId]
	if player and product then
		targets:Abandon(player, product.Key, wasPurchased)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	targets:Clear(player)
end)

loadFamilies()

return PurchaseService
