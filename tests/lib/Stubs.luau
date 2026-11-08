--# selene: allow(incorrect_standard_library_use)
-- Roblox globals missing from Lune: Random, task, warn, workspace, and minimal services.
local roblox = require("@lune/roblox")
local lunetask = require("@lune/task")

local Stubs = {}

-- ── Random (splitmix32-style, deterministic per seed) ───────────────────
local Random = {}
Random.__index = Random

local MASK = 0xFFFFFFFF

function Random.new(seed)
	return setmetatable({ _state = (seed or os.time()) % (MASK + 1) }, Random)
end

function Random:_next()
	local z = (self._state + 0x9E3779B9) % (MASK + 1)
	self._state = z
	z = bit32.bxor(z, bit32.rshift(z, 16))
	z = (z * 0x85EBCA6B) % (MASK + 1)
	z = bit32.bxor(z, bit32.rshift(z, 13))
	z = (z * 0xC2B2AE35) % (MASK + 1)
	return bit32.bxor(z, bit32.rshift(z, 16))
end

function Random:NextNumber(min, max)
	local unit = self:_next() / (MASK + 1)
	if min == nil then
		return unit
	end
	return min + unit * (max - min)
end

function Random:NextInteger(min, max)
	return min + math.floor(self:_next() / (MASK + 1) * (max - min + 1))
end

-- ── Signals and services ────────────────────────────────────────────────
local function newFakeSignal()
	local signal = {}
	function signal:Connect()
		return { Connected = true, Disconnect = function() end }
	end
	signal.Once = signal.Connect
	function signal:Wait()
		error("[tests] fake signals never fire; Wait() would hang")
	end
	return signal
end

local function strictTable(name, members)
	return setmetatable(members, {
		__index = function(_, key)
			error(("[tests] fake service %s has no member %s"):format(name, tostring(key)), 2)
		end,
	})
end

local factories = {
	Players = function()
		return strictTable("Players", {
			LocalPlayer = nil,
			PlayerAdded = newFakeSignal(),
			PlayerRemoving = newFakeSignal(),
			GetPlayers = function()
				return {}
			end,
		})
	end,
	RunService = function()
		return strictTable("RunService", {
			Heartbeat = newFakeSignal(),
			Stepped = newFakeSignal(),
			RenderStepped = newFakeSignal(),
			IsServer = function()
				return true
			end,
			IsClient = function()
				return false
			end,
			IsStudio = function()
				return true
			end,
		})
	end,
	CollectionService = function()
		return strictTable("CollectionService", {
			GetTagged = function()
				return {}
			end,
			GetInstanceAddedSignal = newFakeSignal,
			GetInstanceRemovedSignal = newFakeSignal,
		})
	end,
	TweenService = function()
		return strictTable("TweenService", {})
	end,
	HttpService = function()
		local serde = require("@lune/serde")
		return strictTable("HttpService", {
			JSONEncode = function(_, value)
				return serde.encode("json", value)
			end,
			JSONDecode = function(_, text)
				return serde.decode("json", text)
			end,
		})
	end,
}

-- Fresh stub services and globals for one spec file. FakeServices maps service name -> object.
function Stubs.new()
	local services = {}
	local function getService(name)
		if services[name] == nil and factories[name] then
			services[name] = factories[name]()
		end
		return services[name]
	end

	local task = {
		spawn = lunetask.spawn,
		defer = lunetask.defer,
		delay = lunetask.delay,
		wait = function(seconds)
			return lunetask.wait(seconds)
		end,
		cancel = lunetask.cancel,
	}

	local workspace = strictTable("workspace", {
		GetServerTimeNow = function()
			return os.clock()
		end,
	})

	local env = {
		Random = Random,
		task = task,
		workspace = workspace,
		warn = function(...)
			local parts = table.pack(...)
			for i = 1, parts.n do
				parts[i] = tostring(parts[i])
			end
			print("[warn] " .. table.concat(parts, " ", 1, parts.n))
		end,
		Color3 = roblox.Color3,
		Vector2 = roblox.Vector2,
		Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Enum = roblox.Enum,
		NumberRange = roblox.NumberRange,
		NumberSequence = roblox.NumberSequence,
		-- Lune's roblox library has no ColorSequence; tables carrying the keypoints are enough for data checks.
		ColorSequence = {
			new = function(keypoints)
				return { Keypoints = keypoints }
			end,
		},
		ColorSequenceKeypoint = {
			new = function(time, value)
				return { Time = time, Value = value }
			end,
		},
		BrickColor = roblox.BrickColor,
		Instance = roblox.Instance,
	}

	return env, services, getService
end

Stubs.Random = Random

return Stubs
