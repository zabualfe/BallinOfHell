-- SpinWheelService
-- Owns `spins`, `lastFreeSpinAt` and `lastVipSpinDay`, the free-spin timer and every wheel roll (GDD 10.5).
-- The server rolls with one module Random, saves the result through RewardService, then replies.
--
-- Usage:
--   SpinWheelService.AddSpins(player, amount, source) -> boolean   -- amount a positive whole number, source a string
--   SpinWheelService.ArePaidRandomItemsRestricted(player) -> boolean
--       PolicyService result, cached at join. True until the lookup succeeds, so a failed lookup hides paid spins.
--   SpinWheelService.GetFreeSpinStatus(player) -> isReady, secondsLeft?
--
-- Free spin: ready every 8 h (4 h with the Lucky pass), never banks past one. VIP also gets +1 banked spin per UTC
-- day. A spin uses the free spin first, then a banked one.
--
-- Player attributes: NextFreeSpinAt (server time the free spin is ready; <= now means ready),
--   PaidRandomItemsRestricted (boolean; the client hides paid spin products while true).
-- Network (client -> server): SpinWheel() rate limited; GetWheelOdds() invoke -> { Slices = Odds list,
--   PaidRestricted = boolean } computed from WheelTable (see Shared/WheelRules.Odds).
-- Network (server -> client): WheelResult(sliceIndex, rewardSummary) after the result is saved;
--   WheelDenied(reason) with reason "NoSpins" | "Busy" | "Error".
-- Paid spin products are the "Wheel" family, granted by PurchaseService/Products/Spins through AddSpins.

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage.Network)
local WheelRules = require(ReplicatedStorage.Shared.WheelRules)
local Signal = require(ReplicatedStorage.Utilities.Signal)
local AnalyticsTable = require(ReplicatedStorage.Tables.AnalyticsTable)
local WheelTable = require(ReplicatedStorage.Tables.WheelTable)

local AnalyticsService = require(script.Parent.AnalyticsService)
local GamePassService = require(script.Parent.GamePassService)
local PlayerData = require(script.Parent.PlayerData)
local RewardService = require(script.Parent.RewardService)

local SpinWheelService = {}

SpinWheelService.Spun = Signal.new() -- (player, sliceIndex) after a spin is granted

-- ── Tuning ──────────────────────────────────────────────────────────────
local SPIN_RATE = { Capacity = 2, RefillPerSecond = 0.5 } -- SpinWheel burst / per second
local ODDS_RATE = { Capacity = 3, RefillPerSecond = 0.5 } -- GetWheelOdds burst / per second
local VIP_CHECK_INTERVAL = 60 -- seconds between UTC-day checks for VIP spins
local POLICY_ATTEMPTS = 3
local POLICY_RETRY_SECONDS = 3
local LUCKY_PASS = "Lucky"
local VIP_PASS = "VIP"

-- ── State ───────────────────────────────────────────────────────────────
local random = Random.new() -- one Random for every roll
local paidRestricted = {} -- [player] = boolean, true until PolicyService answers
local spinning = {} -- [player] = true while a spin is being resolved

-- ── Free spin and attributes ────────────────────────────────────────────

local function freeStatus(player)
	local interval = WheelRules.FreeInterval(WheelTable.Config, GamePassService.Owns(player, LUCKY_PASS))
	local last = PlayerData.Peek(player, "lastFreeSpinAt")
	return WheelRules.FreeStatus(workspace:GetServerTimeNow(), type(last) == "number" and last or 0, interval)
end

local function refreshNextFreeSpin(player)
	if not PlayerData.IsLoaded(player) then
		return
	end
	local _, _, nextAt = freeStatus(player)
	player:SetAttribute("NextFreeSpinAt", nextAt)
end

function SpinWheelService.GetFreeSpinStatus(player)
	if not PlayerData.IsLoaded(player) then
		return false, nil
	end
	local isReady, secondsLeft = freeStatus(player)
	return isReady, secondsLeft
end

function SpinWheelService.AddSpins(player, amount, source)
	if type(amount) ~= "number" or amount < 1 or amount ~= math.floor(amount) or type(source) ~= "string" then
		return false
	end
	if not PlayerData.IsLoaded(player) then
		return false
	end
	return PlayerData.Set(player, "spins", PlayerData.Get(player, "spins") + amount) == true
end

function SpinWheelService.ArePaidRandomItemsRestricted(player)
	return paidRestricted[player] ~= false
end

local function claimVipSpin(player)
	if not PlayerData.IsLoaded(player) or not GamePassService.Owns(player, VIP_PASS) then
		return
	end
	local day = WheelRules.DayOf(workspace:GetServerTimeNow())
	local lastDay = PlayerData.Peek(player, "lastVipSpinDay")
	if not WheelRules.VipSpinDue(day, type(lastDay) == "number" and lastDay or -1) then
		return
	end
	-- Mark the day first so a second caller cannot pay it twice; undo if the spin could not be added.
	if not PlayerData.Set(player, "lastVipSpinDay", day) then
		return
	end
	if not SpinWheelService.AddSpins(player, WheelTable.Config.VipExtraFreeSpinsPerDay, "Vip") then
		PlayerData.Set(player, "lastVipSpinDay", lastDay or -1)
	end
end

-- ── Spin ────────────────────────────────────────────────────────────────

-- Takes one spin and returns a function that gives it back, or nil when the player has none.
local function chargeSpin(player)
	local isReady = freeStatus(player)
	if isReady then
		local previous = PlayerData.Get(player, "lastFreeSpinAt")
		if not PlayerData.Set(player, "lastFreeSpinAt", workspace:GetServerTimeNow()) then
			return nil
		end
		refreshNextFreeSpin(player)
		return "Free",
			function()
				PlayerData.Set(player, "lastFreeSpinAt", previous)
				refreshNextFreeSpin(player)
			end
	end

	local banked = PlayerData.Get(player, "spins")
	if type(banked) ~= "number" or banked < 1 or not PlayerData.Set(player, "spins", banked - 1) then
		return nil
	end
	return "Banked", function()
		SpinWheelService.AddSpins(player, 1, "Refund")
	end
end

local function resolveSpin(player)
	local kind, refund = chargeSpin(player)
	if not kind then
		Network.FireClient(player, "WheelDenied", "NoSpins")
		return
	end

	local index, slice = WheelRules.Roll(WheelTable.Slices, random)
	if not slice then
		refund()
		Network.FireClient(player, "WheelDenied", "Error")
		return
	end

	local _, summary = RewardService.Grant(player, slice.Reward, "Wheel")
	if #summary == 0 then
		refund()
		Network.FireClient(player, "WheelDenied", "Error")
		return
	end

	AnalyticsService.Custom(player, AnalyticsTable.Events.WheelSpin, index, { Spin = kind })
	Network.FireClient(player, "WheelResult", index, summary)
	SpinWheelService.Spun:Fire(player, index)
end

local function spin(player)
	if spinning[player] then
		Network.FireClient(player, "WheelDenied", "Busy")
		return
	end
	if not PlayerData.IsLoaded(player) then
		return
	end
	spinning[player] = true
	local ok, err = pcall(resolveSpin, player)
	spinning[player] = nil
	if not ok then
		warn(`[SpinWheelService] Spin failed for {player.Name}: {tostring(err)}`)
	end
end

Network.OnEvent("SpinWheel", spin, SPIN_RATE)

Network.OnInvoke("GetWheelOdds", function(player)
	return {
		Slices = WheelRules.Odds(WheelTable.Slices),
		PaidRestricted = SpinWheelService.ArePaidRandomItemsRestricted(player),
	}
end, ODDS_RATE)

-- ── Players ─────────────────────────────────────────────────────────────

local function loadPolicy(player)
	for attempt = 1, POLICY_ATTEMPTS do
		local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
		if player.Parent == nil then
			return
		end
		if ok and type(info) == "table" then
			paidRestricted[player] = info.ArePaidRandomItemsRestricted == true
			player:SetAttribute("PaidRandomItemsRestricted", paidRestricted[player])
			return
		end
		if attempt < POLICY_ATTEMPTS then
			task.wait(POLICY_RETRY_SECONDS)
		end
	end
	warn(`[SpinWheelService] PolicyService lookup failed for {player.Name}; paid spins stay hidden`)
end

local function onPlayerAdded(player)
	paidRestricted[player] = true
	player:SetAttribute("PaidRandomItemsRestricted", true)
	task.spawn(loadPolicy, player)

	if PlayerData.WaitForLoaded(player, 60) and player.Parent ~= nil then
		refreshNextFreeSpin(player)
		claimVipSpin(player)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	paidRestricted[player] = nil
	spinning[player] = nil
end)

GamePassService.PassChanged:Connect(function(player, passKey)
	if passKey == LUCKY_PASS then
		refreshNextFreeSpin(player)
	elseif passKey == VIP_PASS then
		claimVipSpin(player)
	end
end)

task.spawn(function()
	while true do
		task.wait(VIP_CHECK_INTERVAL)
		for _, player in Players:GetPlayers() do
			claimVipSpin(player)
		end
	end
end)

return SpinWheelService
