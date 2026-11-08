-- UpsellService
-- Decides when to offer what (GDD 11.4, ARCHITECTURE 7). The system decides; trigger plug-ins only detect their
-- moment and call Offer, and an A/B variant may only change the ORDER of offers (FlagService UpsellFallsThreeOrder).
-- Pure decisions live in UpsellRules (specs). Rules enforced here: flag-enabled, per-trigger session cap, at most one
-- popup per UpsellMinSecondsBetweenPopups, a quiet first session, nothing during the countdown, one per segment.
--
-- Usage (plug-ins):
--   UpsellService.Offer(player, triggerId, context?) -> boolean   -- true when ShowUpsell was sent
--   UpsellService.Param(triggerId, name) -> any      -- UpsellParam_<Id>_<Name> flag, else the UpsellTable param
--   UpsellService.Memo(player, triggerId) -> table   -- the plug-in's scratch table for this player, gone on leave
--   UpsellService.Toast(text)                        -- ShowToast to every player
--
-- Trigger plug-in contract (one module per UpsellTable trigger in Triggers/, see Triggers/FallsThree):
--   return {
--     Id = "FallsThree",                           -- the UpsellTable trigger Id
--     Start = function(UpsellService) end,         -- once at load: connect to the source, call Offer
--     Tick = function(UpsellService, player) end,  -- optional, every TICK_SECONDS per loaded player (polled sources)
--     ServerTick = function(UpsellService) end,    -- optional, every TICK_SECONDS once
--     OfferOrder = function(player) -> {keys}?,    -- optional preferred order (A/B tests)
--     Eligible = function(player, offerKey, context) -> boolean?,
--       -- optional; false vetoes that offer, nil falls through. A product or pass key is always checked too
--       -- (CanOffer / ownership), so true only stands alone for keys with no product, like "Coins"
--     QuietExempt = boolean?,                      -- skips the quiet first session (Starter Pack checkpoint)
--     Single = boolean?,                           -- offer only the first offerable key
--   }
-- Default offer check: a ProductTable key needs PurchaseService.CanOffer (real Id and CanPrompt); a PassTable key needs
-- a real Id and not owned. context.ProductKeys[offerKey] maps an alias to a product and context.Targets[offerKey]
-- is the PromptProduct target argument. Paid spins are never offered while PolicyService restricts them.
--
-- Network (server -> client):
--   ShowUpsell(triggerId, offerKeys, context)  context = plain data from the plug-in plus Inline = true for inline offers
--   ShowToast(text)                            server-wide, e.g. "Only 87 Crown of Hell left!"
-- Network (client -> server), all validated and rate limited:
--   UpsellTapped(triggerId, offerKey)   -- funnel step OfferTapped (product key); once per offer per shown popup
--   WheelOpened()                       -- WheelNoSpins   ShopBallViewed(ballId)    -- LockedItemViewed
--   TrickViewed(trickId)                -- LockedTrickViewed   ToolPressedEmpty(toolId)   -- ToolNoCharges
--   TrickPremiumWouldScore(extraFraction, extraPoints)   -- TrickPremiumPreview (client re-plan, first airtime)
-- Runtime state is per player and cleared on leave.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage.Network)
local PassTable = require(ReplicatedStorage.Tables.PassTable)
local ProductTable = require(ReplicatedStorage.Tables.ProductTable)
local UpsellTable = require(ReplicatedStorage.Tables.UpsellTable)

local AnalyticsService = require(script.Parent.AnalyticsService)
local FlagService = require(script.Parent.FlagService)
local GamePassService = require(script.Parent.GamePassService)
local PlayerData = require(script.Parent.PlayerData)
local ProgressService = require(script.Parent.ProgressService)
local PurchaseService = require(script.Parent.PurchaseService)
local SpinWheelService = require(script.Parent.SpinWheelService)
local Rules = require(script.UpsellRules)

local UpsellService = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local TICK_SECONDS = 2 -- polled triggers
local TAP_RATE = { Capacity = 4, RefillPerSecond = 1 } -- UpsellTapped burst / per second
local FUNNEL = "Purchase"

-- ── State ───────────────────────────────────────────────────────────────
local rowsById = {} -- [triggerId] = UpsellTable row
local plugins = {} -- [triggerId] = plug-in module
local states = {} -- [player] = { JoinedAt, LastPopupAt, Shown, SegmentShown, LastOffer, InlineLogged, Memos }

for _, row in UpsellTable.Triggers do
	rowsById[row.Id] = row
end

-- ── Flags ───────────────────────────────────────────────────────────────

local function flagOr(key, fallback)
	local value = FlagService.Get(key)
	if value == nil then
		return fallback
	end
	return value
end

function UpsellService.Param(triggerId, name)
	local row = rowsById[triggerId]
	local default = row and row.Params and row.Params[name]
	if type(default) ~= "number" then
		return default
	end
	return flagOr(("UpsellParam_%s_%s"):format(triggerId, name), default)
end

-- ── Per-player state ────────────────────────────────────────────────────

local function newState()
	return {
		JoinedAt = os.clock(),
		LastPopupAt = nil,
		Shown = {}, -- [triggerId] = popups this session
		SegmentShown = {}, -- [segmentKey] = { trigger Type, ... }
		LastOffer = {}, -- [triggerId] = { Keys, ProductKeys, Tapped } for the popup last sent
		InlineLogged = {}, -- ["trigger:offer:item"] = true once OfferShown was logged for an inline offer
		Memos = {},
	}
end

function UpsellService.Memo(player, triggerId)
	local state = states[player]
	if not state then
		return {}
	end
	local memo = state.Memos[triggerId]
	if not memo then
		memo = {}
		state.Memos[triggerId] = memo
	end
	return memo
end

local function currentSegmentKey(player)
	local progress = ProgressService.GetState(player)
	if not progress or not progress.Racing or progress.Finished then
		return nil
	end
	return ("%s:%d"):format(tostring(workspace:GetAttribute("RoundId")), progress.Checkpoint + 1)
end

-- ── Offers ──────────────────────────────────────────────────────────────

-- Product and pass keys always get the purchase check, even when a plug-in's Eligible said true.
local function defaultCheck(player, offerKey, context)
	local productKey = context.ProductKeys and context.ProductKeys[offerKey] or offerKey
	local target = context.Targets and context.Targets[offerKey]
	if ProductTable[productKey] then
		return PurchaseService.CanOffer(player, productKey, target)
	end
	local pass = PassTable[offerKey]
	if pass then
		return pass.Id ~= 0 and not GamePassService.Owns(player, offerKey)
	end
	return nil
end

local function isOfferable(player, plugin, offerKey, context)
	local decided = nil
	if plugin.Eligible then
		local ok, result = pcall(plugin.Eligible, player, offerKey, context)
		if ok then
			decided = result
		end
	end
	if decided == false then
		return false
	end
	return Rules.Offerable(decided, defaultCheck(player, offerKey, context))
end

local function gateInput(player, state, row, plugin, kind)
	local segmentKey = currentSegmentKey(player)
	local global = UpsellTable.Global
	return {
		Kind = kind,
		Type = row.Type,
		Enabled = flagOr("UpsellEnabled_" .. row.Id, true) == true,
		Cap = flagOr("UpsellCap_" .. row.Id, row.CapPerSession),
		Shown = state.Shown[row.Id] or 0,
		Now = os.clock(),
		LastPopupAt = state.LastPopupAt,
		MinSpacing = flagOr("UpsellMinSecondsBetweenPopups", global.MinSecondsBetweenPopups),
		IsFirstSession = PlayerData.Peek(player, "sessionCount") == 1,
		SessionAge = os.clock() - state.JoinedAt,
		QuietSeconds = flagOr("UpsellQuietFirstSessionSeconds", global.QuietFirstSessionSeconds),
		QuietExempt = plugin.QuietExempt == true,
		Countdown = workspace:GetAttribute("RoundState") == "Countdown",
		NoneDuringCountdown = global.NoneDuringCountdown,
		SegmentShown = segmentKey and state.SegmentShown[segmentKey] or {},
		MaxPerSegment = global.MaxPerSegment,
	},
		segmentKey
end

function UpsellService.Offer(player, triggerId, context)
	local row = rowsById[triggerId]
	local plugin = plugins[triggerId]
	local state = states[player]
	if not row or not plugin or not state or not PlayerData.IsLoaded(player) then
		return false
	end
	context = if type(context) == "table" then table.clone(context) else {}

	local kind = Rules.KindOf(row)
	local input, segmentKey = gateInput(player, state, row, plugin, kind)
	if not Rules.Gate(input) then
		return false
	end
	if row.RequiresPaidRandomAllowed and SpinWheelService.ArePaidRandomItemsRestricted(player) then
		return false
	end
	if row.RequiresNoPass and GamePassService.Owns(player, row.RequiresNoPass) then
		return false
	end

	local preferred = plugin.OfferOrder and plugin.OfferOrder(player) or nil
	local ordered = Rules.OrderOffers(row.Offers, preferred)
	local picked = Rules.PickOffers(ordered, function(offerKey)
		return isOfferable(player, plugin, offerKey, context)
	end, plugin.Single)
	if #picked == 0 or states[player] ~= state then
		return false
	end

	if kind == "Popup" then
		state.LastPopupAt = os.clock()
		if segmentKey then
			local shownHere = state.SegmentShown[segmentKey] or {}
			table.insert(shownHere, row.Type)
			state.SegmentShown[segmentKey] = shownHere
		end
	end
	if kind ~= "Inline" then
		state.Shown[triggerId] = (state.Shown[triggerId] or 0) + 1
	end
	state.LastOffer[triggerId] = { Keys = picked, ProductKeys = context.ProductKeys, Tapped = {} }

	context.Inline = kind == "Inline" or nil
	local itemId = context.BallId or context.TrickId or ""
	for _, offerKey in picked do
		local productKey = context.ProductKeys and context.ProductKeys[offerKey] or offerKey
		-- Re-viewing the same item must not inflate the funnel's OfferShown count.
		local loggedKey = ("%s:%s:%s"):format(triggerId, offerKey, tostring(itemId))
		if kind ~= "Inline" or not state.InlineLogged[loggedKey] then
			state.InlineLogged[loggedKey] = kind == "Inline" or nil
			AnalyticsService.Funnel(player, FUNNEL, "OfferShown", productKey, { Trigger = triggerId })
		end
	end
	Network.FireClient(player, "ShowUpsell", triggerId, picked, context)
	return true
end

function UpsellService.Toast(text)
	Network.FireAllClients("ShowToast", text)
end

Network.OnEvent("UpsellTapped", function(player, triggerId, offerKey)
	local state = states[player]
	if not state or type(triggerId) ~= "string" or type(offerKey) ~= "string" then
		return
	end
	local offered = state.LastOffer[triggerId]
	if not offered or not table.find(offered.Keys, offerKey) or offered.Tapped[offerKey] then
		return
	end
	offered.Tapped[offerKey] = true
	local productKey = offered.ProductKeys and offered.ProductKeys[offerKey] or offerKey
	AnalyticsService.Funnel(player, FUNNEL, "OfferTapped", productKey, { Trigger = triggerId })
end, TAP_RATE)

-- ── Plug-ins and ticks ──────────────────────────────────────────────────

local function safely(label, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warn(("[UpsellService] %s failed: %s"):format(label, tostring(err)))
	end
end

local function loadPlugins()
	for _, child in script.Triggers:GetChildren() do
		if not child:IsA("ModuleScript") then
			continue
		end
		local ok, plugin = pcall(require, child)
		if not ok then
			warn(("[UpsellService] Trigger %s failed to load: %s"):format(child.Name, tostring(plugin)))
		elseif type(plugin) ~= "table" or rowsById[plugin.Id] == nil or plugins[plugin.Id] ~= nil then
			warn(("[UpsellService] Trigger %s has no unique UpsellTable Id"):format(child.Name))
		else
			plugins[plugin.Id] = plugin
		end
	end
	for _, row in UpsellTable.Triggers do
		if not plugins[row.Id] then
			warn("[UpsellService] No trigger plug-in for " .. row.Id)
		end
	end
	for id, plugin in plugins do
		safely(id .. ".Start", plugin.Start, UpsellService)
	end
end

local function onPlayerAdded(player)
	states[player] = newState()
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	states[player] = nil
end)

task.spawn(function()
	while true do
		task.wait(TICK_SECONDS)
		for id, plugin in plugins do
			if plugin.ServerTick then
				safely(id .. ".ServerTick", plugin.ServerTick, UpsellService)
			end
			if not plugin.Tick then
				continue
			end
			for player in states do
				if player.Parent ~= nil and PlayerData.IsLoaded(player) then
					safely(id .. ".Tick", plugin.Tick, UpsellService, player)
				end
			end
		end
	end
end)

loadPlugins()

return UpsellService
