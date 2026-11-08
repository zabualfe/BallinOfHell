-- ChallengeService
-- Daily and weekly challenges (GDD 8.4). Picks are deterministic per (UserId, UTC day / week) and stored in the
-- `challenges` data key, so rejoining never changes them. Progress comes from SeasonService.Events (the same server
-- events that give season XP); each objective type is a plug-in in ChallengeService/Objectives. Completing a challenge
-- awards XP at once through SeasonService.AddXp(player, "Challenge", xp). Pure maths lives in ChallengeService/Rules.
--
-- Objective plug-in contract (one module per ChallengeTable.ObjectiveTypes entry, see Objectives/ClearSegments):
--   Event: string, a SeasonService.Events name        Increment(params, payload) -> number
--   OncePerRound: boolean? -- counts at most once per round per challenge
--
-- Usage:
--   ChallengeService.GetSnapshot(player) -> table?    -- what GetChallenges returns
--   ChallengeService.Reroll(player, kind, index) -> boolean   -- kind "Daily" only
--   ChallengeService.Sync(player)                     -- assigns the current day and week if they are not set yet
--
-- Nothing is assigned or counted while no season is active (the Challenges tab is hidden then).
-- Saved: challenges = { day, daily = { { id, progress, done } }, week, weekly = { ... }, rerollsUsed, rerollSeed }.
--
-- Network (client -> server):
--   RerollChallenge(kind, index)    -- rate limited. kind is "Daily"; index 1..DailyCount
--   GetChallenges() invoke -> { Active, Daily = { { Id, Text, Type, Target, Xp, Progress, Done } }, Weekly = { ... },
--       DailyResetsIn, WeeklyResetsIn (seconds), RerollsLeft }
-- Network (server -> owner): ChallengeCompleted(scope, index, xp), ChallengeRerolled(index), ChallengeDenied(reason)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage.Network)
local AnalyticsTable = require(ReplicatedStorage.Tables.AnalyticsTable)
local ChallengeTable = require(ReplicatedStorage.Tables.ChallengeTable)

local AnalyticsService = require(script.Parent.AnalyticsService)
local PlayerData = require(script.Parent.PlayerData)
local SeasonService = require(script.Parent.SeasonService)
local Rules = require(script.Rules)

local ChallengeService = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local REROLL_RATE = { Capacity = 2, RefillPerSecond = 0.2 } -- RerollChallenge burst / per second
local QUERY_RATE = { Capacity = 4, RefillPerSecond = 0.5 }
local CHECK_INTERVAL = 30 -- seconds between day / week rollover checks
local DATA_WAIT_TIMEOUT = 60 -- seconds
local DAILY_SALT = 1
local WEEKLY_SALT = 2
local XP_SOURCE = "Challenge"

local config = ChallengeTable.Config
local events = AnalyticsTable.Events

-- ── State ───────────────────────────────────────────────────────────────
local objectives = {} -- [type] = plug-in
local objectivesByEvent = {} -- [eventName] = { plug-in, ... }
local rowsById = {} -- [challengeId] = row
local runtime = {} -- [player] = { Ready, RoundSeen = { [key] = roundId } }

for _, scope in { "Daily", "Weekly" } do
	for _, row in ChallengeTable[scope] do
		rowsById[row.Id] = row
	end
end

for _, child in script.Objectives:GetChildren() do
	if not child:IsA("ModuleScript") then
		continue
	end
	local ok, module = pcall(require, child)
	if ok and type(module) == "table" and type(module.Event) == "string" and type(module.Increment) == "function" then
		objectives[child.Name] = module
		objectivesByEvent[module.Event] = objectivesByEvent[module.Event] or {}
		table.insert(objectivesByEvent[module.Event], child.Name)
	else
		warn(`[ChallengeService] Objective {child.Name} needs Event and Increment ({tostring(module)})`)
	end
end
for _, objectiveType in ChallengeTable.ObjectiveTypes do
	if not objectives[objectiveType] then
		warn(`[ChallengeService] No Objectives/{objectiveType} module for that ChallengeTable objective type`)
	end
end

-- ── Assignment ──────────────────────────────────────────────────────────

local function entriesFor(rows)
	local out = {}
	for _, row in rows do
		table.insert(out, Rules.NewEntry(row))
	end
	return out
end

-- Fills in today's dailies and this week's weeklies when the saved day / week is stale. Returns true if data changed.
local function assign(player)
	local userId = player.UserId
	local now = workspace:GetServerTimeNow()
	local day, week = Rules.DayNumber(now), Rules.WeekNumber(now)
	local challenges = PlayerData.Get(player, "challenges")
	local wins = PlayerData.Peek(player, "wins") or 0
	local changed = false

	if challenges.day ~= day then
		local rows = Rules.Assign(
			ChallengeTable.Daily,
			config.DailyCount,
			Rules.Seed(userId, day, DAILY_SALT),
			wins,
			ChallengeTable.Conditional
		)
		challenges.day = day
		challenges.daily = entriesFor(rows)
		challenges.rerollsUsed = 0
		challenges.rerollSeed = 0
		changed = true
	end
	if challenges.week ~= week then
		local rows = Rules.Assign(
			ChallengeTable.Weekly,
			config.WeeklyCount,
			Rules.Seed(userId, week, WEEKLY_SALT),
			wins,
			ChallengeTable.Conditional
		)
		challenges.week = week
		challenges.weekly = entriesFor(rows)
		changed = true
	end
	if changed then
		PlayerData.Set(player, "challenges", challenges)
	end
	return changed
end

function ChallengeService.Sync(player)
	local rt = runtime[player]
	if not rt or not PlayerData.IsLoaded(player) or SeasonService.GetActive() == nil then
		return
	end
	assign(player)
	rt.Ready = true
end

-- ── Progress ────────────────────────────────────────────────────────────

local function complete(player, scope, index, row)
	Network.FireClient(player, "ChallengeCompleted", scope, index, row.Xp)
	AnalyticsService.Custom(player, events.ChallengeCompleted, row.Xp, {
		ChallengeId = row.Id,
		Scope = scope,
		Type = row.Type,
		Xp = row.Xp,
	})
	SeasonService.AddXp(player, XP_SOURCE, row.Xp)
end

local function applyEvent(player, rt, eventName, payload)
	-- Refresh a stale day / week first so progress never lands on yesterday's set after midnight.
	assign(player)
	local challenges = PlayerData.Peek(player, "challenges")
	local roundId = workspace:GetAttribute("RoundId")
	for _, scope in { "Daily", "Weekly" } do
		local list = challenges[string.lower(scope)]
		for index, entry in list do
			local row = rowsById[entry.id]
			local objective = row and objectives[row.Type]
			if entry.done or not objective or objective.Event ~= eventName then
				continue
			end
			local key = `{scope}{index}`
			if objective.OncePerRound and rt.RoundSeen[key] == roundId then
				continue
			end
			local increment = objective.Increment(row.Params or {}, payload)
			if type(increment) ~= "number" or increment <= 0 then
				continue
			end
			if objective.OncePerRound then
				rt.RoundSeen[key] = roundId
			end
			local updated, justDone = Rules.Advance(entry, row, increment)
			if PlayerData.SetPath(player, `challenges.{string.lower(scope)}.{index}`, updated) and justDone then
				task.spawn(complete, player, scope, index, row)
			end
		end
	end
end

SeasonService.Events:Connect(function(eventName, player, payload)
	local rt = runtime[player]
	if not rt or not objectivesByEvent[eventName] or SeasonService.GetActive() == nil then
		return
	end
	if not rt.Ready then
		ChallengeService.Sync(player)
	end
	if rt.Ready then
		applyEvent(player, rt, eventName, payload)
	end
end)

-- ── Reroll and queries ──────────────────────────────────────────────────

function ChallengeService.Reroll(player, kind, index)
	local rt = runtime[player]
	if kind ~= "Daily" or not rt or not rt.Ready or SeasonService.GetActive() == nil then
		return false
	end
	assign(player)
	local challenges = PlayerData.Get(player, "challenges")
	local ok, reason = Rules.CanReroll(challenges, index, SeasonService.HasPremium(player), config)
	if not ok then
		Network.FireClient(player, "ChallengeDenied", reason)
		return false
	end

	local currentIds = {}
	for _, entry in challenges.daily do
		table.insert(currentIds, entry.id)
	end
	local seed = Rules.RerollSeed(player.UserId, challenges.day, challenges.rerollsUsed)
	local wins = PlayerData.Peek(player, "wins") or 0
	local row = Rules.Reroll(ChallengeTable.Daily, currentIds, seed, wins, ChallengeTable.Conditional)
	if not row then
		Network.FireClient(player, "ChallengeDenied", "NoReplacement")
		return false
	end

	local oldId = challenges.daily[index].id
	challenges.daily[index] = Rules.NewEntry(row)
	challenges.rerollsUsed += 1
	challenges.rerollSeed = seed
	if not PlayerData.Set(player, "challenges", challenges) then
		return false
	end
	AnalyticsService.Custom(player, events.ChallengeRerolled, index, { From = oldId, To = row.Id, Scope = "Daily" })
	Network.FireClient(player, "ChallengeRerolled", index)
	return true
end

local function describe(entries)
	local out = {}
	for _, entry in entries do
		local row = rowsById[entry.id]
		if row then
			table.insert(out, {
				Id = row.Id,
				Text = row.Text,
				Type = row.Type,
				Target = row.Target,
				Xp = row.Xp,
				Progress = entry.progress,
				Done = entry.done,
			})
		end
	end
	return out
end

function ChallengeService.GetSnapshot(player)
	local rt = runtime[player]
	if not rt or not PlayerData.IsLoaded(player) then
		return nil
	end
	if SeasonService.GetActive() == nil then
		return { Active = false }
	end
	ChallengeService.Sync(player)
	local challenges = PlayerData.Peek(player, "challenges")
	local now = workspace:GetServerTimeNow()
	return {
		Active = true,
		Daily = describe(challenges.daily),
		Weekly = describe(challenges.weekly),
		DailyResetsIn = Rules.SecondsToNextDay(now),
		WeeklyResetsIn = Rules.SecondsToNextWeek(now),
		RerollsLeft = math.max(0, Rules.RerollLimit(SeasonService.HasPremium(player), config) - challenges.rerollsUsed),
	}
end

Network.OnEvent("RerollChallenge", function(player, kind, index)
	if type(kind) ~= "string" or type(index) ~= "number" then
		return
	end
	ChallengeService.Reroll(player, kind, index)
end, REROLL_RATE)

Network.OnInvoke("GetChallenges", function(player)
	return ChallengeService.GetSnapshot(player)
end, QUERY_RATE)

-- ── Wiring ──────────────────────────────────────────────────────────────

local function setupPlayer(player)
	runtime[player] = { Ready = false, RoundSeen = {} }
	if PlayerData.WaitForLoaded(player, DATA_WAIT_TIMEOUT) and player.Parent == Players then
		ChallengeService.Sync(player)
	end
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(setupPlayer, player)
end)
for _, player in Players:GetPlayers() do
	task.spawn(setupPlayer, player)
end

Players.PlayerRemoving:Connect(function(player)
	runtime[player] = nil
end)

-- Day and week rollovers while a player stays online.
task.spawn(function()
	while true do
		task.wait(CHECK_INTERVAL)
		for player in runtime do
			local ok, err = pcall(ChallengeService.Sync, player)
			if not ok then
				warn(`[ChallengeService] Sync failed for {player.Name}: {tostring(err)}`)
			end
		end
	end
end)

return ChallengeService
