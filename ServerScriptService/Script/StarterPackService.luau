-- StarterPackService
-- The 15-minute new-player offer (GDD 10.6). Owns the availability window and the popups; the purchase itself
-- is PurchaseService/Products/StarterPack, which sets `starterPackBought`.
--
-- Usage:
--   StarterPackService.IsLive(player) -> boolean   -- now - firstJoinAt < window (wall-clock, offline time counts) and not bought
--
-- Player attribute: StarterPackEndsAt (server time the offer ends; absent when it is not available). Cleared the
--   moment it is bought or expires.
-- Signal: PopupDue(player, reason) with reason "Checkpoint" (first checkpoint of the session) or "Reminder"
--   (2:00 left). UpsellService owns the popup (spacing, caps, ShowUpsell); this module sends no message itself.
--   A reason keeps firing (once per TICK_SECONDS) until the consumer calls MarkShown(player, reason) after
--   UpsellService.Offer returned true, so a popup blocked by spacing or a cap is retried. A Checkpoint request
--   expires after CHECKPOINT_RETRY_SECONDS. Buying goes through PromptProduct("StarterPack").
--   StarterPackService.MarkShown(player, reason)   -- the offer was shown (or can never be); stop firing it

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Utilities.Signal)
local StarterPackRules = require(ReplicatedStorage.Shared.StarterPackRules)
local StarterPackTable = require(ReplicatedStorage.Tables.StarterPackTable)

local PlayerData = require(script.Parent.PlayerData)
local ProgressService = require(script.Parent.ProgressService)

local StarterPackService = {}
StarterPackService.PopupDue = Signal.new() -- (player, reason)

-- ── Tuning ──────────────────────────────────────────────────────────────
local TICK_SECONDS = 1 -- expiry, reminder and retry check interval
local CHECKPOINT_RETRY_SECONDS = 30 -- how long a blocked checkpoint popup keeps retrying

-- ── State ───────────────────────────────────────────────────────────────
local sessions = {} -- [player] = { ShownCheckpoint, ShownReminder, CheckpointAt? (os.clock of the first checkpoint) }

local function isLive(player)
	if not PlayerData.IsLoaded(player) then
		return false
	end
	return StarterPackRules.IsLive(
		workspace:GetServerTimeNow(),
		PlayerData.Peek(player, "firstJoinAt"),
		PlayerData.Peek(player, "starterPackBought") == true,
		StarterPackTable.WindowSeconds
	)
end

function StarterPackService.IsLive(player)
	return isLive(player)
end

local function syncAttribute(player)
	local endsAt = nil
	if isLive(player) then
		endsAt = StarterPackRules.EndsAt(PlayerData.Peek(player, "firstJoinAt"), StarterPackTable.WindowSeconds)
	end
	if player:GetAttribute("StarterPackEndsAt") ~= endsAt then
		player:SetAttribute("StarterPackEndsAt", endsAt)
	end
end

function StarterPackService.MarkShown(player, reason)
	local session = sessions[player]
	if not session then
		return
	end
	if reason == "Checkpoint" then
		session.ShownCheckpoint = true
	elseif reason == "Reminder" then
		session.ShownReminder = true
	end
end

local function tick(player, session)
	syncAttribute(player)
	if not isLive(player) then
		return
	end
	local checkpointAt = session.CheckpointAt
	if checkpointAt and not session.ShownCheckpoint and os.clock() - checkpointAt <= CHECKPOINT_RETRY_SECONDS then
		StarterPackService.PopupDue:Fire(player, "Checkpoint")
	end
	if session.ShownReminder then
		return
	end
	local due = StarterPackRules.ReminderDue(
		workspace:GetServerTimeNow(),
		PlayerData.Peek(player, "firstJoinAt"),
		StarterPackTable.WindowSeconds,
		StarterPackTable.ReminderSecondsLeft
	)
	if due then
		StarterPackService.PopupDue:Fire(player, "Reminder")
	end
end

local function onPlayerAdded(player)
	local session = { ShownCheckpoint = false, ShownReminder = false }
	sessions[player] = session
	if not PlayerData.WaitForLoaded(player, 60) or sessions[player] ~= session then
		return
	end
	PlayerData.OnUpdate(player, "starterPackBought", function()
		syncAttribute(player)
	end)
	syncAttribute(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	sessions[player] = nil
end)

ProgressService.CheckpointReached:Connect(function(player)
	local session = sessions[player]
	if not session or session.ShownCheckpoint or session.CheckpointAt then
		return
	end
	session.CheckpointAt = os.clock()
	if isLive(player) then
		StarterPackService.PopupDue:Fire(player, "Checkpoint")
	end
end)

task.spawn(function()
	while true do
		task.wait(TICK_SECONDS)
		for player, session in sessions do
			if player.Parent ~= nil then
				tick(player, session)
			end
		end
	end
end)

return StarterPackService
