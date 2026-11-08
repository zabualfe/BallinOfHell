-- TimedRewardService
-- Session playtime gifts (GDD 10.4). Playtime is counted on the server and resets every session; the client
-- never reports time. Pure maths lives in TimedRewardService/Rules (specs); rewards are paid by RewardService.Grant.
--
-- Usage:
--   TimedRewardService.Claim(player, index) -> boolean, summary?   -- false: bad index, locked, already claimed, grant failed
--   TimedRewardService.ClaimAll(player) -> boolean                 -- every remaining unlocked gift; true when none are left
--   TimedRewardService.UnlockAll(player) -> boolean                -- ignores playtime; Products/TimedUnlock calls it after payment
--   TimedRewardService.GetWaitingCount(player) -> number           -- unlocked and unclaimed this session
--   TimedRewardService.GetRemainingCount(player) -> number         -- unclaimed this session (locked or not)
--   TimedRewardService.GetSeconds(player) -> number
--
-- The once-ever ball is recorded in timedRewardsEverClaimed[ballId] after a successful grant; from then on the
-- gift pays the Table's Fallback. A gift is reserved before the grant yields and released if the grant fails;
-- a partial grant (non-empty summary) counts as claimed, with a warn, so the parts that landed are never paid twice.
-- AFK detection (TimedRewardTable.Config.AfkStopSeconds) needs a client activity signal and is not wired yet.
--
-- Player attributes: PlaytimeSeconds (integer, refreshed every PUBLISH_INTERVAL s and on unlock),
-- TimedClaimedMask (bit i-1 set when gift i is claimed this session).
--
-- Network (client -> server): ClaimTimed(index)   -- rate limited
-- Network (server -> client): TimedClaimed(index, summary)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage.Network)
local Signal = require(ReplicatedStorage.Utilities.Signal)
local TimedRewardTable = require(ReplicatedStorage.Tables.TimedRewardTable)
local RewardRules = require(ReplicatedStorage.Shared.RewardRules)

local PlayerData = require(script.Parent.PlayerData)
local RewardService = require(script.Parent.RewardService)
local Rules = require(script.Rules)

local TimedRewardService = {}
TimedRewardService.Claimed = Signal.new() -- (player, index) after a successful gift claim

-- ── Tuning ──────────────────────────────────────────────────────────────
local CLAIM_CAPACITY = 4 -- ClaimTimed burst
local CLAIM_REFILL = 1 -- ClaimTimed per second
local TICK_INTERVAL = 1 -- seconds between playtime accumulation
local PUBLISH_INTERVAL = 5 -- seconds between PlaytimeSeconds updates
local DATA_WAIT_TIMEOUT = 30 -- seconds

local gifts = TimedRewardTable.Gifts

-- ── State ───────────────────────────────────────────────────────────────
local sessions = {} -- [player] = { Seconds, Claimed = { [index] = true }, Reserved = { [index] = true }, Published }

local function publish(player, session)
	session.Published = math.floor(session.Seconds)
	player:SetAttribute("PlaytimeSeconds", session.Published)
	player:SetAttribute("TimedClaimedMask", Rules.Mask(session.Claimed, #gifts))
end

-- ── Claiming ────────────────────────────────────────────────────────────

local function grantReward(player, entry)
	return RewardService.Grant(player, entry, "Timed")
end

-- Grants one gift. `force` skips the playtime check (Unlock All) but never the claimed check.
local function claim(player, index, force)
	local session = sessions[player]
	if not session or not PlayerData.IsLoaded(player) then
		return false
	end
	local gift = type(index) == "number" and index % 1 == 0 and gifts[index] or nil
	if not gift or session.Claimed[index] or session.Reserved[index] then
		return false
	end
	if not force and not Rules.IsUnlocked(gift, session.Seconds) then
		return false
	end

	session.Reserved[index] = true
	local everClaimed = PlayerData.Get(player, "timedRewardsEverClaimed")
	local entry = Rules.BuildEntry(gift, everClaimed)
	local ok, granted, summary = pcall(grantReward, player, entry)
	if not ok then
		warn(`[TimedRewardService] Grant errored: {tostring(granted)}`)
	end
	session.Reserved[index] = nil
	if not ok then
		granted, summary = false, {}
	end
	-- A partial grant is still final: re-claiming would double-pay the parts that landed.
	if not RewardRules.IsFinalGrant(granted, summary) or sessions[player] ~= session then
		return false
	end
	if not granted then
		warn(`[TimedRewardService] Gift {index} only partly granted for {player.Name}; claim kept`)
	end

	session.Claimed[index] = true
	if
		gift.OnceEverBall ~= nil
		and everClaimed[gift.OnceEverBall] ~= true
		and Rules.GrantedBall(summary, gift.OnceEverBall)
	then
		-- Re-read: another key write may have landed while the grant yielded.
		local latest = PlayerData.Get(player, "timedRewardsEverClaimed")
		latest[gift.OnceEverBall] = true
		PlayerData.Set(player, "timedRewardsEverClaimed", latest)
	end
	publish(player, session)
	Network.FireClient(player, "TimedClaimed", index, summary)
	TimedRewardService.Claimed:Fire(player, index)
	return true, summary
end

function TimedRewardService.Claim(player, index)
	return claim(player, index, false)
end

function TimedRewardService.ClaimAll(player)
	local session = sessions[player]
	if not session then
		return false
	end
	local allDone = true
	for _, index in Rules.Remaining(gifts, session.Seconds, session.Claimed) do
		allDone = claim(player, index, false) and allDone
	end
	return allDone
end

function TimedRewardService.UnlockAll(player)
	local session = sessions[player]
	if not session or not PlayerData.IsLoaded(player) then
		return false
	end
	local allDone = true
	for index in gifts do
		if not session.Claimed[index] then
			allDone = claim(player, index, true) and allDone
		end
	end
	return allDone
end

function TimedRewardService.GetSeconds(player)
	local session = sessions[player]
	return session and session.Seconds or 0
end

function TimedRewardService.GetWaitingCount(player)
	local session = sessions[player]
	return session and Rules.WaitingCount(gifts, session.Seconds, session.Claimed) or 0
end

function TimedRewardService.GetRemainingCount(player)
	local session = sessions[player]
	if not session then
		return 0
	end
	local count = 0
	for index in gifts do
		if not session.Claimed[index] then
			count += 1
		end
	end
	return count
end

-- ── Players ─────────────────────────────────────────────────────────────

local function onPlayerAdded(player)
	if not PlayerData.WaitForLoaded(player, DATA_WAIT_TIMEOUT) or player.Parent ~= Players then
		return
	end
	local session = { Seconds = 0, Claimed = {}, Reserved = {}, Published = 0 }
	sessions[player] = session
	publish(player, session)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	sessions[player] = nil
end)

task.spawn(function()
	local last = os.clock()
	while true do
		task.wait(TICK_INTERVAL)
		local now = os.clock()
		local elapsed = now - last
		last = now
		for player, session in sessions do
			local before = Rules.WaitingCount(gifts, session.Seconds, session.Claimed)
			session.Seconds += elapsed
			local after = Rules.WaitingCount(gifts, session.Seconds, session.Claimed)
			if after ~= before or session.Seconds - session.Published >= PUBLISH_INTERVAL then
				publish(player, session)
			end
		end
	end
end)

Network.OnEvent("ClaimTimed", function(player, index)
	if type(index) ~= "number" then
		return
	end
	TimedRewardService.Claim(player, index)
end, { Capacity = CLAIM_CAPACITY, RefillPerSecond = CLAIM_REFILL })

return TimedRewardService
