-- PlayerData (client)
-- Read-only mirror of the server's saved data for the local player. Never write to it; ask the server.
--
-- Usage:
--   PlayerData.Get(key) -> deep copy        PlayerData.Peek(key) -> live table, read-only
--   PlayerData.OnUpdate(key, fn(newValue, oldValue)) -> connection with Disconnect
--     Fires for the top-level key even when the server changed a nested path.
--   PlayerData.IsLoaded() -> boolean        PlayerData.WaitForLoaded() -> yields until the first snapshot
--   PlayerData.Loaded:Connect(fn)           -- fires once, when the first snapshot arrives

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage.Network)
local Signal = require(ReplicatedStorage.Utilities.Signal)
local TableUtil = require(ReplicatedStorage.Utilities.TableUtil)

local PlayerData = {}

local data = {}
local isLoaded = false
local keySignals = {} -- [key] = Signal

PlayerData.Loaded = Signal.new()

local function getSignal(key)
	local signal = keySignals[key]
	if not signal then
		signal = Signal.new()
		keySignals[key] = signal
	end
	return signal
end

function PlayerData.IsLoaded()
	return isLoaded
end

function PlayerData.WaitForLoaded()
	if not isLoaded then
		PlayerData.Loaded:Wait()
	end
end

function PlayerData.Get(key)
	return TableUtil.DeepCopy(data[key])
end

function PlayerData.Peek(key)
	return data[key]
end

function PlayerData.OnUpdate(key, fn)
	return getSignal(key):Connect(fn)
end

Network.OnEvent("DataInit", function(snapshot)
	if type(snapshot) ~= "table" then
		return
	end
	local previous = data
	data = snapshot
	if isLoaded then
		-- A repeat snapshot (late DataRequest reply) is not an update unless something changed.
		for key, value in data do
			if not TableUtil.DeepEqual(value, previous[key]) then
				getSignal(key):Fire(TableUtil.DeepCopy(value), TableUtil.DeepCopy(previous[key]))
			end
		end
		return
	end
	isLoaded = true
	PlayerData.Loaded:Fire()
end)

Network.OnEvent("DataUpdate", function(path, value)
	local segments = TableUtil.SplitPath(path)
	if not isLoaded or not segments then
		return
	end
	local key = segments[1]
	local oldValue = TableUtil.DeepCopy(data[key])
	if not TableUtil.SetPath(data, path, value) then
		return
	end
	local signal = keySignals[key]
	if signal then
		signal:Fire(TableUtil.DeepCopy(data[key]), oldValue)
	end
end)

-- The first DataInit can arrive before this client module exists, so ask for it.
Network.FireServer("DataRequest")

return PlayerData
