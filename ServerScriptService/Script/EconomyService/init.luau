-- EconomyService
-- The only writer of `coins` and the owner of `boosts` countdowns (GDD 9). Every change is logged to
-- AnalyticsService.Economy with its source or sink and the ending balance.
--
-- Usage:
--   EconomyService.AddCoins(player, amount, source, sku?) -> boolean   -- final amount, NO multiplier
--   EconomyService.Award(player, baseAmount, source, opts?) -> granted  -- applies multipliers, floor, min 1; 0 on failure
--       opts = { Kind = "Race" (default) | "Reward" | "Trick", NoRoundMultiplier = boolean?,
--                RoundMultiplier = number? (override, e.g. the Finished signal's value), Sku = string? }
--       Race: round x personal (pass + boost). Reward: pass only. Trick: pass + boost + Trick Coins pass, no round.
--   EconomyService.SpendCoins(player, amount, sink, sku?) -> boolean   -- false if it can't be afforded
--   EconomyService.GetCoins(player) -> number
--   EconomyService.GetPersonalMultiplier(player, kind?) -> number
--   EconomyService.AddBoost(player, boostId, seconds) -> boolean       -- "coins2x" is capped at the 120 min bank
--   EconomyService.IsBoostActive(player, boostId) -> boolean
--   EconomyService.GetBoostSeconds(player, boostId) -> number
--       Pass keys used here: "Coins2x", "TrickCoins2x" (PassTable keys).
--
-- Wired here: ProgressService.CheckpointReached pays the tier coins (nothing for skipped checkpoints or the
-- finish), ProgressService.Finished pays 100 + place bonus with the finisher's round multiplier,
-- InventoryService.DuplicateGranted refunds the rarity value (not multiplied).
--
-- Boosts: remaining seconds live in memory while the player is here and are written to PlayerData every
-- BOOST_SAVE_INTERVAL seconds and on change. A player leaving can lose up to that interval of countdown,
-- in their favour, because PlayerData releases the profile before PlayerRemoving handlers run.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Utilities.Signal)
local AnalyticsTable = require(ReplicatedStorage.Tables.AnalyticsTable)
local BallTable = require(ReplicatedStorage.Tables.BallTable)
local EconomyTable = require(ReplicatedStorage.Tables.EconomyTable)
local CourseTable = require(ReplicatedStorage.Tables.CourseTable)
local RarityTable = require(ReplicatedStorage.Tables.RarityTable)

local AnalyticsService = require(script.Parent.AnalyticsService)
local CourseService = require(script.Parent.CourseService)
local InventoryService = require(script.Parent.InventoryService)
local PlayerData = require(script.Parent.PlayerData)
local ProgressService = require(script.Parent.ProgressService)
local GamePassService = require(script.Parent.GamePassService)
local Rules = require(script.Rules)

local EconomyService = {}
EconomyService.Awarded = Signal.new() -- (player, amount, source, kind) after Award paid coins

-- ── Tuning ──────────────────────────────────────────────────────────────
local BOOST_TICK = 1 -- seconds between countdown steps
local BOOST_SAVE_INTERVAL = 15 -- seconds between writes of the countdown to PlayerData
local COINS_BOOST_ID = "coins2x"
local COINS_PASS_KEY = "Coins2x"
local TRICK_PASS_KEY = "TrickCoins2x"
local COINS_BOOST_CAP = EconomyTable.Boost.Coins2xBankCapMinutes * 60 -- seconds

local boostStates = {} -- [player] = { Remaining = { [id] = seconds }, LastSave = os.clock() }

-- ── Coins ───────────────────────────────────────────────────────────────

local function isValidAmount(amount)
	return type(amount) == "number" and amount == amount and amount > 0 and amount < math.huge
end

local function logFlow(player, flow, amount, balance, source, sku, multiplier)
	AnalyticsService.Economy(
		player,
		flow,
		amount,
		balance,
		Rules.TransactionType(source, AnalyticsTable),
		sku or source,
		multiplier and { Multiplier = multiplier, Source = source } or { Source = source }
	)
end

function EconomyService.GetCoins(player)
	local coins = PlayerData.Peek(player, "coins")
	return type(coins) == "number" and coins or 0
end

local function addCoins(player, amount, source, sku, multiplier)
	if not isValidAmount(amount) or type(source) ~= "string" or not PlayerData.IsLoaded(player) then
		return false
	end
	amount = math.floor(amount)
	if amount < 1 then
		return false
	end
	local balance = EconomyService.GetCoins(player) + amount
	if not PlayerData.Set(player, "coins", balance) then
		return false
	end
	logFlow(player, AnalyticsTable.Flow.Source, amount, balance, source, sku, multiplier)
	return true
end

function EconomyService.AddCoins(player, amount, source, sku)
	return addCoins(player, amount, source, sku, nil)
end

function EconomyService.SpendCoins(player, amount, sink, sku)
	if not isValidAmount(amount) or type(sink) ~= "string" or not PlayerData.IsLoaded(player) then
		return false
	end
	amount = math.floor(amount)
	local current = EconomyService.GetCoins(player)
	if amount < 1 or current < amount then
		return false
	end
	local balance = current - amount
	if not PlayerData.Set(player, "coins", balance) then
		return false
	end
	logFlow(player, AnalyticsTable.Flow.Sink, amount, balance, sink, sku, nil)
	return true
end

-- ── Multipliers ─────────────────────────────────────────────────────────

local function ownsPass(player, passKey)
	return GamePassService.Owns(player, passKey) == true
end

function EconomyService.GetPersonalMultiplier(player, kind)
	return Rules.PersonalMultiplier(kind or "Race", {
		CoinsPass = ownsPass(player, COINS_PASS_KEY),
		CoinsBoost = EconomyService.IsBoostActive(player, COINS_BOOST_ID),
		TrickPass = ownsPass(player, TRICK_PASS_KEY),
	}, EconomyTable)
end

function EconomyService.Award(player, baseAmount, source, opts)
	opts = opts or {}
	local kind = opts.Kind or "Race"
	local def = Rules.KindOf(kind)
	if not def then
		warn("[EconomyService] Award with unknown kind " .. tostring(kind))
		return 0
	end

	local roundMultiplier = 1
	if def.RoundMultiplier and not opts.NoRoundMultiplier then
		roundMultiplier = opts.RoundMultiplier
		if type(roundMultiplier) ~= "number" then
			-- Read the replicated value: requiring RoundService here would close a require cycle through rewards.
			roundMultiplier = workspace:GetAttribute("RoundMultiplier") or 1
		end
	end

	local personal = EconomyService.GetPersonalMultiplier(player, kind)
	local amount = Rules.Payout(baseAmount, roundMultiplier, personal, EconomyTable.Race.MinCoins)
	if amount < 1 then
		return 0
	end
	if not addCoins(player, amount, source, opts.Sku, roundMultiplier * personal) then
		return 0
	end
	EconomyService.Awarded:Fire(player, amount, source, kind)
	return amount
end

-- ── Boosts ──────────────────────────────────────────────────────────────

local function getBoostState(player)
	local state = boostStates[player]
	if state then
		return state
	end
	local saved = PlayerData.Get(player, "boosts")
	if type(saved) ~= "table" then
		return nil
	end
	state = { Remaining = saved, LastSave = os.clock() }
	boostStates[player] = state
	return state
end

local function saveBoosts(player, state)
	state.LastSave = os.clock()
	PlayerData.Set(player, "boosts", state.Remaining)
end

function EconomyService.AddBoost(player, boostId, seconds)
	if type(boostId) ~= "string" or not isValidAmount(seconds) or not PlayerData.IsLoaded(player) then
		return false
	end
	local state = getBoostState(player)
	if not state then
		return false
	end
	local cap = boostId == COINS_BOOST_ID and COINS_BOOST_CAP or nil
	state.Remaining = Rules.AddBoost(state.Remaining, boostId, seconds, cap)
	saveBoosts(player, state)
	return true
end

function EconomyService.GetBoostSeconds(player, boostId)
	local state = getBoostState(player)
	return state and state.Remaining[boostId] or 0
end

function EconomyService.IsBoostActive(player, boostId)
	return EconomyService.GetBoostSeconds(player, boostId) > 0
end

local function tickBoosts(dt)
	for _, player in Players:GetPlayers() do
		local state = PlayerData.IsLoaded(player) and getBoostState(player)
		if state and next(state.Remaining) ~= nil then
			local expired
			state.Remaining, expired = Rules.TickBoosts(state.Remaining, dt)
			if #expired > 0 or os.clock() - state.LastSave >= BOOST_SAVE_INTERVAL then
				saveBoosts(player, state)
			end
		end
	end
end

task.spawn(function()
	local last = os.clock()
	while true do
		task.wait(BOOST_TICK)
		local now = os.clock()
		local ok, err = xpcall(tickBoosts, debug.traceback, now - last)
		last = now
		if not ok then
			warn("[EconomyService] Boost tick failed: " .. tostring(err))
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	boostStates[player] = nil
end)

-- ── Wiring ──────────────────────────────────────────────────────────────

ProgressService.CheckpointReached:Connect(function(player, index, tier)
	local state = ProgressService.GetState(player)
	local isSkipped = state ~= nil and state.Skipped[index] == true
	local isFinish = index >= CourseService.GetSegmentCount()
	local base = Rules.CheckpointBase(CourseTable.Tiers[tier], isSkipped, isFinish)
	EconomyService.Award(player, base, "Checkpoint", { Sku = tostring(tier) })
end)

ProgressService.Finished:Connect(function(player, place, _time, multiplier)
	local base = Rules.FinishBase(place, EconomyTable)
	EconomyService.Award(player, base, "Finish", { RoundMultiplier = multiplier, Sku = "Place" .. tostring(place) })
end)

InventoryService.DuplicateGranted:Connect(function(player, ballId, source)
	local amount = Rules.DuplicateCoins(BallTable[ballId], source, RarityTable, EconomyTable)
	if amount > 0 then
		EconomyService.AddCoins(player, amount, "Duplicate", ballId)
	end
end)

return EconomyService
