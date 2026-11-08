-- DailyRewardService
-- The 7-day UTC streak calendar (GDD 10.3). The server decides everything: the client only asks to claim.
-- Pure maths lives in DailyRewardService/Rules (specs); rewards are paid by RewardService.Grant.
--
-- Usage:
--   DailyRewardService.Claim(player) -> boolean, summary?   -- false: already claimed today, not loaded, grant failed
--   DailyRewardService.GetStatus(player) -> { CanClaim, NextDay, CanRestore }?   -- nil until data is loaded
--   DailyRewardService.CanRestore(player) -> boolean         -- inside the 48 h window after a break
--   DailyRewardService.RestoreStreak(player) -> boolean      -- idempotent; Products/Streak calls it after payment
--
-- Saved: dailyStreak (day of the last claim, 1..7), lastDailyClaimDay (UTC day number). Neither is reset
-- until the next claim, so the broken streak is still known during the Restore window and no extra key is
-- needed. Restoring moves lastDailyClaimDay to yesterday.
-- Day 7 pays Ember Glow only while it is not owned (the ball has no other source, so that is the first cycle).
-- VIP coins are computed as base x (1 + passBonus + vipBonus) (GDD 9.1: bonuses add, pass + VIP = x2.5) and
-- granted as FinalCoins, so Award does not apply the 2x Coins pass a second time.
-- The streak and claim day are written BEFORE the grant (a second claim sees them) and rolled back only when the
-- grant paid nothing. A partial grant is final: re-claiming would double-pay the parts that landed.
--
-- Player attributes (HUD badge): DailyAvailable (bool), DailyDay (the day a claim now pays, 1..7),
-- DailyRestorable (bool, Restore Streak offer). Refreshed on load, on claim and when the UTC day rolls over.
--
-- Network (client -> server): ClaimDaily()   -- rate limited
-- Network (server -> client): DailyClaimed(day, summary)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage.Network)
local Signal = require(ReplicatedStorage.Utilities.Signal)
local DailyRewardTable = require(ReplicatedStorage.Tables.DailyRewardTable)
local EconomyTable = require(ReplicatedStorage.Tables.EconomyTable)
local RewardRules = require(ReplicatedStorage.Shared.RewardRules)

local GamePassService = require(script.Parent.GamePassService)
local PlayerData = require(script.Parent.PlayerData)
local RewardService = require(script.Parent.RewardService)
local Rules = require(script.Rules)

local DailyRewardService = {}
DailyRewardService.Claimed = Signal.new() -- (player) after a successful claim

-- ── Tuning ──────────────────────────────────────────────────────────────
local CLAIM_CAPACITY = 2 -- ClaimDaily burst
local CLAIM_REFILL = 0.2 -- ClaimDaily per second
local DATA_WAIT_TIMEOUT = 30 -- seconds
local REFRESH_INTERVAL = 30 -- seconds between UTC rollover checks
local VIP_PASS = "VIP"
local COINS_PASS = "Coins2x"

local config = DailyRewardTable.Config

-- ── State ───────────────────────────────────────────────────────────────
local inFlight = {} -- [player] = true while a claim is being granted

-- ── Status ──────────────────────────────────────────────────────────────

local function today()
	return Rules.DayNumber(workspace:GetServerTimeNow())
end

function DailyRewardService.GetStatus(player)
	if not PlayerData.IsLoaded(player) then
		return nil
	end
	return Rules.Status(
		PlayerData.Peek(player, "lastDailyClaimDay"),
		PlayerData.Peek(player, "dailyStreak"),
		today(),
		config
	)
end

function DailyRewardService.CanRestore(player)
	local status = DailyRewardService.GetStatus(player)
	return status ~= nil and status.CanRestore
end

local function refreshAttributes(player)
	local status = DailyRewardService.GetStatus(player)
	if not status then
		return
	end
	player:SetAttribute("DailyAvailable", status.CanClaim)
	player:SetAttribute("DailyDay", status.NextDay)
	player:SetAttribute("DailyRestorable", status.CanRestore)
end

-- ── Claim ───────────────────────────────────────────────────────────────

local function grantReward(player, entry)
	return RewardService.Grant(player, entry, "Daily")
end

local function writeClaim(player, streak, claimDay)
	return PlayerData.Set(player, "dailyStreak", streak) and PlayerData.Set(player, "lastDailyClaimDay", claimDay)
end

function DailyRewardService.Claim(player)
	if inFlight[player] or not PlayerData.IsLoaded(player) then
		return false
	end
	local status = DailyRewardService.GetStatus(player)
	if not status or not status.CanClaim then
		return false
	end

	local dayRow = DailyRewardTable.Days[status.NextDay]
	if not dayRow then
		return false
	end

	inFlight[player] = true
	local entry = Rules.BuildEntry(
		dayRow,
		GamePassService.Owns(player, VIP_PASS),
		dayRow.FirstTimeBall ~= nil and PlayerData.Peek(player, "ownedBalls")[dayRow.FirstTimeBall] ~= nil,
		GamePassService.Owns(player, COINS_PASS),
		EconomyTable
	)
	local previousStreak = PlayerData.Peek(player, "dailyStreak")
	local previousDay = PlayerData.Peek(player, "lastDailyClaimDay")
	if not writeClaim(player, status.NextDay, today()) then
		writeClaim(player, previousStreak, previousDay)
		inFlight[player] = nil
		return false
	end

	local ok, granted, summary = pcall(grantReward, player, entry)
	if not ok then
		warn(`[DailyRewardService] Grant errored: {tostring(granted)}`)
		granted, summary = false, {}
	end
	inFlight[player] = nil
	if not RewardRules.IsFinalGrant(granted, summary) then
		writeClaim(player, previousStreak, previousDay)
		return false
	end
	if not granted then
		warn(`[DailyRewardService] Day {status.NextDay} only partly granted for {player.Name}; claim kept`)
	end

	refreshAttributes(player)
	Network.FireClient(player, "DailyClaimed", status.NextDay, summary)
	return true, summary
end

function DailyRewardService.RestoreStreak(player)
	if not PlayerData.IsLoaded(player) then
		return false
	end
	local lastDay = PlayerData.Peek(player, "lastDailyClaimDay")
	local streak = PlayerData.Peek(player, "dailyStreak")
	local current = today()
	-- Already restored (gap is 1) or already claimed: nothing left to do, which keeps a retried receipt safe.
	if lastDay >= current - 1 then
		return true
	end
	local restoredDay = Rules.RestoredLastDay(lastDay, streak, current, config)
	if restoredDay == nil then
		-- Past the window or no streak left: true so a paid receipt is not retried forever.
		warn(`[DailyRewardService] {player.Name} bought Restore Streak but nothing could be restored`)
		return true
	end
	if not PlayerData.Set(player, "lastDailyClaimDay", restoredDay) then
		return false
	end
	refreshAttributes(player)
	return true
end

-- ── Players ─────────────────────────────────────────────────────────────

local function onPlayerAdded(player)
	if PlayerData.WaitForLoaded(player, DATA_WAIT_TIMEOUT) and player.Parent == Players then
		refreshAttributes(player)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	inFlight[player] = nil
end)

task.spawn(function()
	while true do
		task.wait(REFRESH_INTERVAL)
		for _, player in Players:GetPlayers() do
			refreshAttributes(player)
		end
	end
end)

Network.OnEvent("ClaimDaily", function(player)
	DailyRewardService.Claim(player)
end, { Capacity = CLAIM_CAPACITY, RefillPerSecond = CLAIM_REFILL })

return DailyRewardService
