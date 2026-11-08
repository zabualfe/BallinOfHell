-- PlayerData
-- The only module that touches ProfileStore. Loads a profile on join, reconciles it against DataTemplate,
-- replicates it to the owning client only, and releases it on leave and on server close.
--
-- Usage:
--   PlayerData.Get(player, key) -> deep copy       PlayerData.Peek(player, key) -> live table, read-only
--   PlayerData.Set(player, key, value) -> boolean  PlayerData.SetPath(player, "a.b", value) -> boolean
--   PlayerData.OnUpdate(player, key, fn(newValue, oldValue, path)) -> { Disconnect }
--     Set passes whole-key values with path = key; SetPath passes the leaf values with the full path.
--   PlayerData.IsLoaded(player) -> boolean         PlayerData.WaitForLoaded(player, timeout) -> boolean
--   PlayerData.Changed:Connect(function(player, key, value) end)  -- value is the live key table, read-only
-- Everything returns nil/false until loaded; wait for the DataLoaded player attribute first.
--
-- Network: DataInit(snapshot) and DataUpdate(path, value) go to the owner; the client sends DataRequest
-- once it is ready, because it may miss the first DataInit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage.Network)
local ProfileStore = require(ReplicatedStorage.Utilities.ProfileStore)
local Signal = require(ReplicatedStorage.Utilities.Signal)
local TableUtil = require(ReplicatedStorage.Utilities.TableUtil)
local DataTemplate = require(script.DataTemplate)

local PlayerData = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local STORE_NAME = "PlayerData_v1"
local KICK_MESSAGE = "Your data could not be loaded safely. Please rejoin in a minute."
local SESSION_END_MESSAGE = "Your data was opened on another server. Please rejoin."
local REQUEST_CAPACITY = 3 -- DataRequest burst
local REQUEST_REFILL = 0.2 -- DataRequest per second

local store = ProfileStore.New(STORE_NAME, DataTemplate)

local entries = {} -- [player] = { Profile, Data, Listeners = { [key] = { fn, ... } } }
local loadedSignal = Signal.new() -- (player, ok)

PlayerData.Changed = Signal.new()

local function getEntry(player)
	local entry = entries[player]
	if entry and entry.Data then
		return entry
	end
	return nil
end

local function notify(player, entry, key, path, newValue, oldValue)
	local list = entry.Listeners[key]
	if list then
		for _, fn in table.clone(list) do
			task.spawn(fn, newValue, oldValue, path)
		end
	end
	PlayerData.Changed:Fire(player, key, entry.Data[key])
end

function PlayerData.IsLoaded(player)
	return getEntry(player) ~= nil and player:GetAttribute("DataLoaded") == true
end

function PlayerData.WaitForLoaded(player, timeout)
	if PlayerData.IsLoaded(player) then
		return true
	end
	if player.Parent ~= Players then
		return false
	end
	local thread = coroutine.running()
	local done = false
	local connection
	local function finish(ok)
		if done then
			return
		end
		done = true
		connection:Disconnect()
		task.spawn(thread, ok)
	end
	connection = loadedSignal:Connect(function(who, ok)
		if who == player then
			finish(ok)
		end
	end)
	task.delay(timeout or 30, finish, false)
	return coroutine.yield()
end

function PlayerData.Get(player, key)
	local entry = getEntry(player)
	if not entry then
		return nil
	end
	return TableUtil.DeepCopy(entry.Data[key])
end

function PlayerData.Peek(player, key)
	local entry = getEntry(player)
	if not entry then
		return nil
	end
	return entry.Data[key]
end

-- A whole key must keep the type of its template default; nil would silently delete saved data.
local function hasTemplateType(key, value)
	if type(value) == type(DataTemplate[key]) then
		return true
	end
	warn(`[PlayerData] Rejected {key}: expected {type(DataTemplate[key])}, got {type(value)}`)
	return false
end

function PlayerData.Set(player, key, value)
	local entry = getEntry(player)
	if not entry or type(key) ~= "string" or DataTemplate[key] == nil then
		return false
	end
	if not hasTemplateType(key, value) then
		return false
	end
	local oldValue = entry.Data[key]
	-- Copy so the caller mutating its table later cannot change saved data behind our back.
	entry.Data[key] = TableUtil.DeepCopy(value)
	Network.FireClient(player, "DataUpdate", key, value)
	notify(player, entry, key, key, entry.Data[key], oldValue)
	return true
end

function PlayerData.SetPath(player, path, value)
	local entry = getEntry(player)
	local segments = TableUtil.SplitPath(path)
	if not entry or not segments or DataTemplate[segments[1]] == nil then
		return false
	end
	if #segments == 1 and not hasTemplateType(segments[1], value) then
		return false
	end
	local oldValue = TableUtil.DeepCopy(TableUtil.GetPath(entry.Data, path))
	local copy = TableUtil.DeepCopy(value)
	if not TableUtil.SetPath(entry.Data, path, copy) then
		return false
	end
	Network.FireClient(player, "DataUpdate", path, value)
	notify(player, entry, segments[1], path, copy, oldValue)
	return true
end

function PlayerData.OnUpdate(player, key, fn)
	local entry = entries[player]
	if not entry then
		return { Disconnect = function() end }
	end
	local list = entry.Listeners[key]
	if not list then
		list = {}
		entry.Listeners[key] = list
	end
	table.insert(list, fn)
	local connected = true
	return {
		Disconnect = function()
			if not connected then
				return
			end
			connected = false
			local index = table.find(list, fn)
			if index then
				table.remove(list, index)
			end
		end,
	}
end

local function release(player)
	local entry = entries[player]
	if not entry then
		return
	end
	entries[player] = nil
	entry.Data = nil
	if entry.Profile then
		entry.Profile:EndSession()
	end
	loadedSignal:Fire(player, false)
end

local function sendSnapshot(player)
	local entry = getEntry(player)
	if entry then
		Network.FireClient(player, "DataInit", entry.Data)
	end
end

local function setupPlayer(player)
	local entry = { Listeners = {} }
	entries[player] = entry

	local profile = store:StartSessionAsync(tostring(player.UserId), {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if not profile then
		entries[player] = nil
		if player.Parent == Players then
			player:Kick(KICK_MESSAGE)
		end
		loadedSignal:Fire(player, false)
		return
	end

	-- The player may have left, or been released, while the load yielded.
	if player.Parent ~= Players or entries[player] ~= entry then
		profile:EndSession()
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	profile.OnSessionEnd:Connect(function()
		if entries[player] == entry then
			entries[player] = nil
			entry.Data = nil
			player:SetAttribute("DataLoaded", nil)
			loadedSignal:Fire(player, false)
			if player.Parent == Players then
				player:Kick(SESSION_END_MESSAGE)
			end
		end
	end)

	local data = profile.Data
	data.sessionCount += 1
	if data.firstJoinAt == 0 then
		data.firstJoinAt = workspace:GetServerTimeNow()
	end

	entry.Profile = profile
	entry.Data = data
	player:SetAttribute("DataLoaded", true)
	sendSnapshot(player)
	loadedSignal:Fire(player, true)
end

Network.OnEvent("DataRequest", function(player)
	sendSnapshot(player)
end, { Capacity = REQUEST_CAPACITY, RefillPerSecond = REQUEST_REFILL })

Players.PlayerAdded:Connect(function(player)
	task.spawn(setupPlayer, player)
end)
for _, player in Players:GetPlayers() do
	task.spawn(setupPlayer, player)
end

Players.PlayerRemoving:Connect(release)

game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		release(player)
	end
end)

return PlayerData
