-- RewardService
-- The one place that turns a Table reward into player state. Daily, timed, wheel, season, starter pack and
-- first-fall rewards all call Grant; it dispatches each part to the system that owns it.
--
-- Usage:
--   RewardService.Grant(player, rewards, source) -> granted, summary
--     rewards: one reward entry or a list, in any shape the Tables use (see Shared/RewardRules).
--     source: "Wheel" | "Daily" | "Timed" | "StarterPack" | "Season" | "FirstFall" | ... A string; it is the
--       Economy/Inventory source. Coins from "StarterPack", "Robux", "CoinPack", "Duplicate" and "Refund" are
--       NOT multiplied; every other source pays the reward-coin multiplier (2x Coins pass). Ball grants use the
--       source as-is except "Season", which InventoryService knows as "Seasonal".
--     granted: true only if every part was granted. Malformed rewards are refused whole (nothing granted, a warn).
--       Otherwise parts are granted in order and a failing part does not stop the rest (best effort, no rollback),
--       so granted = false means a PARTIAL grant: summary lists exactly what was granted. Already-owned
--       unlocks (tool, trick, trail, title) count as granted with Duplicate = true and change nothing; an owned
--       ball goes through InventoryService so EconomyService pays its duplicate coins, also Duplicate = true.
--     Coins marked Final (FinalCoins / Final = true) are already multiplied by the caller (Daily with VIP) and are
--       paid through AddCoins with no pass multiplier.
--     summary: list of { Kind, Amount, Id?, Duplicate? } for UI. Coins Amount is what was actually paid.
--
-- Dispatch: Coins -> EconomyService.Award/AddCoins, Spins -> SpinWheelService.AddSpins, BoostMinutes ->
--   EconomyService.AddBoost("coins2x"), SkipToken -> `skipTokens`, ToolCharges/ToolUnlock -> ToolService
--   (required lazily; a missing ToolService warns and that part fails), Ball -> InventoryService.GrantBall,
--   Trick -> `ownedTricks`, Trail -> `ownedTrails`, Title -> `ownedTitles`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RewardRules = require(ReplicatedStorage.Shared.RewardRules)
local TrickTable = require(ReplicatedStorage.Tables.TrickTable)

local EconomyService = require(script.Parent.EconomyService)
local InventoryService = require(script.Parent.InventoryService)
local PlayerData = require(script.Parent.PlayerData)

local RewardService = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local BOOST_ID = "coins2x" -- key in saved `boosts`
local SECONDS_PER_MINUTE = 60
local BALL_SOURCE_BY_SOURCE = { Season = "Seasonal" }

-- ── Lazy dependencies ───────────────────────────────────────────────────

local function lazyModule(name)
	local child = script.Parent:FindFirstChild(name)
	if not child then
		warn(`[RewardService] {name} is missing from ServerScriptService.Script`)
		return nil
	end
	local ok, module = pcall(require, child)
	if not ok then
		warn(`[RewardService] {name} failed to load: {tostring(module)}`)
		return nil
	end
	return module
end

-- ── Executors: each returns granted, amountOverride?, isDuplicate? ──────

local function grantFlag(player, key, id)
	local owned = PlayerData.Get(player, key)
	if type(owned) ~= "table" then
		return false
	end
	if owned[id] then
		return true, nil, true
	end
	owned[id] = true
	return PlayerData.Set(player, key, owned) == true
end

local executors = {}

function executors.Coins(player, op, source)
	if op.Final then
		return EconomyService.AddCoins(player, op.Amount, source) == true
	end
	if RewardRules.UsesMultiplier(source) then
		local paid = EconomyService.Award(player, op.Amount, source, { Kind = "Reward" })
		return paid > 0, paid
	end
	return EconomyService.AddCoins(player, op.Amount, source) == true
end

function executors.Spins(player, op, source)
	local SpinWheelService = lazyModule("SpinWheelService")
	return SpinWheelService ~= nil and SpinWheelService.AddSpins(player, op.Amount, source) == true
end

function executors.BoostMinutes(player, op)
	return EconomyService.AddBoost(player, BOOST_ID, op.Amount * SECONDS_PER_MINUTE) == true
end

function executors.SkipToken(player, op)
	return PlayerData.Set(player, "skipTokens", PlayerData.Get(player, "skipTokens") + op.Amount) == true
end

function executors.ToolCharges(player, op, source)
	local ToolService = lazyModule("ToolService")
	return ToolService ~= nil and ToolService.AddCharges(player, op.Id, op.Amount, source) ~= false
end

function executors.ToolUnlock(player, op, source)
	local owned = PlayerData.Peek(player, "ownedTools")
	if owned and owned[op.Id] then
		return true, nil, true
	end
	local ToolService = lazyModule("ToolService")
	return ToolService ~= nil and ToolService.Unlock(player, op.Id, source) ~= false
end

function executors.Ball(player, op, source)
	if InventoryService.OwnsBall(player, op.Id) then
		-- GrantBall returns false for duplicates; the DuplicateGranted signal is what pays the coins.
		InventoryService.GrantBall(player, op.Id, BALL_SOURCE_BY_SOURCE[source] or source)
		return true, nil, true
	end
	return InventoryService.GrantBall(player, op.Id, BALL_SOURCE_BY_SOURCE[source] or source) == true
end

function executors.Trick(player, op)
	if TrickTable.Tricks[op.Id] == nil then
		warn(`[RewardService] Unknown trick {op.Id}`)
		return false
	end
	return grantFlag(player, "ownedTricks", op.Id)
end

function executors.Trail(player, op)
	return grantFlag(player, "ownedTrails", op.Id)
end

function executors.Title(player, op)
	return grantFlag(player, "ownedTitles", op.Id)
end

-- ── Public ──────────────────────────────────────────────────────────────

function RewardService.Grant(player, rewards, source)
	local summary = {}
	if type(source) ~= "string" or not PlayerData.IsLoaded(player) then
		return false, summary
	end
	local ops, problems = RewardRules.Normalize(rewards)
	if #problems > 0 then
		warn(`[RewardService] Refusing malformed reward from {source}: {table.concat(problems, "; ")}`)
		return false, summary
	end

	local allGranted = true
	for _, op in ops do
		local ok, granted, amount, isDuplicate = pcall(executors[op.Kind], player, op, source)
		if ok and granted then
			table.insert(summary, {
				Kind = op.Kind,
				Amount = amount or op.Amount,
				Id = op.Id,
				Duplicate = isDuplicate or nil,
			})
		else
			allGranted = false
			local reason = if ok then "" else `: {tostring(granted)}`
			warn(`[RewardService] {op.Kind} {tostring(op.Id)} from {source} was not granted{reason}`)
		end
	end
	return allGranted, summary
end

return RewardService
