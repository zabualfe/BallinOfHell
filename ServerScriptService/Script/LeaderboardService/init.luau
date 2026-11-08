-- LeaderboardService
-- Wins and fastest-time leaderboards (GDD 1 meta loop). Saved totals live in PlayerData (wins, bestTime); the
-- OrderedDataStores only feed the boards and can lag or fail without costing anyone progress.
--
-- Rules (LeaderboardRules): ProgressService.Finished place 1 = a win; any finish lowers bestTime if faster, unless
-- the run used a paid skip (ProgressService.GetState(player).Skipped is non-empty): it still counts as a win but sets
-- no record. A rejoiner restored mid-round has earlier checkpoints flagged Skipped too, so they set no record either.
-- `time` from ProgressService is os.clock() seconds since the race opened for the player, so it is already real
-- seconds and is not scaled. A rejoiner keeps the round clock, so leaving can't shorten a record.
--
-- Stores: Wins_v1 (value = wins) and FastestTime_v1 (value = integer milliseconds), suffix _Studio in Studio.
-- Fastest uses GetSortedAsync(ascending = true) instead of a negated value: the stored number stays the real
-- time, so it is readable and needs no decode trick.
-- Writes are queued per player (the latest value wins), flushed every FLUSH_INTERVAL, when the player leaves and at
-- shutdown, never past GetRequestBudgetForRequestType minus a reserve. Jobs that don't fit stay queued. A flush
-- writes its jobs in parallel and gives up waiting after FLUSH_DEADLINE so BindToClose stays inside its 30 s.
--
-- Public API:
--   LeaderboardService.Refresh() -> boolean   -- flush now and re-read both boards; false if a read failed
--   LeaderboardService.GetBoards() -> { Wins = rows, Fastest = rows }   -- rows { UserId, Name, Value }; Fastest in seconds
--
-- Network (server -> client): LeaderboardData({ Wins = { { UserId, Name, Value } }, Fastest = { ... } })
--   on join, whenever a board changes, and in reply to LeaderboardRequest. Fastest values are seconds.
-- Network (client -> server): LeaderboardRequest()   -- the UI asks for the current boards once it has loaded;
--   answered to the sender only, rate limited.
-- leaderstats is not created: the GDD does not ask for it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")

local Network = require(ReplicatedStorage.Network)

local PlayerData = require(script.Parent.PlayerData)
local ProgressService = require(script.Parent.ProgressService)
local LeaderboardRules = require(script.LeaderboardRules)

local LeaderboardService = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local STORE_SUFFIX = if RunService:IsStudio() then "_Studio" else ""
local WINS_STORE = "Wins_v1" .. STORE_SUFFIX
local FASTEST_STORE = "FastestTime_v1" .. STORE_SUFFIX
local TOP_COUNT = 50
local FLUSH_INTERVAL = 60 -- seconds
local READ_INTERVAL = 120 -- seconds
local BUDGET_RESERVE = 2 -- requests left for other systems
local WAIT_STEP = 0.1 -- seconds between checks while writes finish
local FLUSH_DEADLINE = 25 -- seconds a flush waits for its writes (BindToClose allows 30)
local REQUEST_RATE = { Capacity = 2, RefillPerSecond = 0.2 } -- LeaderboardRequest burst / per second

-- ── State ───────────────────────────────────────────────────────────────
local stores = {} -- ["Wins" | "Fastest"] = OrderedDataStore, or nil when unavailable
local pending = {} -- [userId] = { Wins?, Fastest? } latest values waiting to be written
local boards = { Wins = {}, Fastest = {} }
local nameCache = {} -- [userId] = string
local refreshing = false
local activeWrites = 0 -- SetAsync jobs in flight, across every flush

local function getStore(key, name)
	if stores[key] then
		return stores[key]
	end
	local ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, name)
	if ok then
		stores[key] = store
		return store
	end
	warn(`[LeaderboardService] {name} unavailable: {store}`)
	return nil
end

-- ── Writes ──────────────────────────────────────────────────────────────

local function queue(userId, field, value)
	pending[userId] = pending[userId] or {}
	pending[userId][field] = value
end

local function budgetFor()
	local ok, budget = pcall(
		DataStoreService.GetRequestBudgetForRequestType,
		DataStoreService,
		Enum.DataStoreRequestType.SetIncrementSortedAsync
	)
	return if ok then budget else 0
end

local function runJob(job)
	local name = if job.Store == "Wins" then WINS_STORE else FASTEST_STORE
	local store = getStore(job.Store, name)
	if not store then
		return false
	end
	local ok, err = pcall(store.SetAsync, store, tostring(job.UserId), job.Value)
	if not ok then
		warn(`[LeaderboardService] Write {job.Store}/{job.UserId} failed: {err}`)
	end
	return ok
end

-- Writes what fits in the budget. `onlyUserId` limits the flush to one leaving player. Failed or unaffordable
-- jobs are re-queued unless a newer value has replaced them.
local function flush(onlyUserId)
	local subset = {}
	for userId, entry in pending do
		if onlyUserId == nil or userId == onlyUserId then
			subset[userId] = entry
		end
	end
	local jobs = LeaderboardRules.BuildJobs(subset)
	if #jobs == 0 then
		return
	end
	for userId in subset do
		pending[userId] = nil
	end

	local taken, remaining = LeaderboardRules.TakeJobs(jobs, budgetFor(), BUDGET_RESERVE)
	local outstanding = #taken
	local deadline = os.clock() + FLUSH_DEADLINE
	local results = {}
	for _, job in taken do
		activeWrites += 1
		task.spawn(function()
			results[job] = runJob(job)
			outstanding -= 1
			activeWrites -= 1
		end)
	end
	while outstanding > 0 and os.clock() < deadline do
		task.wait(WAIT_STEP)
	end
	for _, job in taken do
		if not results[job] then
			table.insert(remaining, job)
		end
	end
	for _, job in remaining do
		local entry = pending[job.UserId]
		if not entry or entry[job.Store] == nil then
			queue(job.UserId, job.Store, job.Value)
		end
	end
end

local function recordFinish(player, place, time)
	if not PlayerData.IsLoaded(player) then
		return
	end
	local wins = PlayerData.Get(player, "wins")
	local bestTime = PlayerData.Get(player, "bestTime")
	local progress = ProgressService.GetState(player)
	local usedSkip = progress ~= nil and LeaderboardRules.UsedSkip(progress.Skipped)
	local newWins, newBest, winsChanged, bestChanged =
		LeaderboardRules.ApplyFinish(wins, bestTime, place, time, usedSkip)
	if winsChanged then
		PlayerData.Set(player, "wins", newWins)
		queue(player.UserId, "Wins", newWins)
	end
	if bestChanged then
		PlayerData.Set(player, "bestTime", newBest)
		queue(player.UserId, "Fastest", LeaderboardRules.ToMillis(newBest))
	end
end

ProgressService.Finished:Connect(function(player, place, time)
	recordFinish(player, place, time)
end)

-- ── Reads ───────────────────────────────────────────────────────────────

local function resolveName(userId)
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	if ok and type(name) == "string" then
		nameCache[userId] = name
		return name
	end
	return nil
end

local function readBoard(key, name, decode)
	local store = getStore(key, name)
	if not store then
		return nil
	end
	local ok, items = pcall(function()
		return store:GetSortedAsync(key == "Fastest", TOP_COUNT):GetCurrentPage()
	end)
	if not ok then
		warn(`[LeaderboardService] Read {name} failed: {items}`)
		return nil
	end
	local names = {}
	for _, item in items do
		local userId = tonumber(item.key)
		if userId then
			names[userId] = resolveName(userId)
		end
	end
	return LeaderboardRules.BuildRows(items, names, decode)
end

local function payload()
	return { Wins = boards.Wins, Fastest = boards.Fastest }
end

function LeaderboardService.GetBoards()
	return payload()
end

function LeaderboardService.Refresh()
	if refreshing then
		return false
	end
	refreshing = true
	local ok, wins, fastest = pcall(function()
		flush()
		return readBoard("Wins", WINS_STORE), readBoard("Fastest", FASTEST_STORE, LeaderboardRules.FromMillis)
	end)
	refreshing = false
	if not ok then
		warn(`[LeaderboardService] Refresh failed: {wins}`)
		return false
	end

	local changed = false
	if wins and not LeaderboardRules.SameRows(wins, boards.Wins) then
		boards.Wins = wins
		changed = true
	end
	if fastest and not LeaderboardRules.SameRows(fastest, boards.Fastest) then
		boards.Fastest = fastest
		changed = true
	end
	if changed then
		Network.FireAllClients("LeaderboardData", payload())
	end
	return wins ~= nil and fastest ~= nil
end

-- ── Lifecycle ───────────────────────────────────────────────────────────

local function onPlayerAdded(player)
	nameCache[player.UserId] = player.Name
	Network.FireClient(player, "LeaderboardData", payload())
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	flush(player.UserId)
end)

Network.OnEvent("LeaderboardRequest", function(player)
	Network.FireClient(player, "LeaderboardData", payload())
end, REQUEST_RATE)

game:BindToClose(function()
	local deadline = os.clock() + FLUSH_DEADLINE
	flush()
	-- Flushes started by leaving players may still be writing.
	while activeWrites > 0 and os.clock() < deadline do
		task.wait(WAIT_STEP)
	end
end)

task.spawn(function()
	local lastRead = 0
	while true do
		task.wait(FLUSH_INTERVAL)
		local ok, err = xpcall(function()
			if os.clock() - lastRead >= READ_INTERVAL - 1 then
				lastRead = os.clock()
				LeaderboardService.Refresh()
			else
				flush()
			end
		end, debug.traceback)
		if not ok then
			warn(`[LeaderboardService] Loop failed: {err}`)
		end
	end
end)

return LeaderboardService
