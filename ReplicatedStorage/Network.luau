-- Network
-- The only client/server channel: one RemoteEvent ("Event") and one RemoteFunction ("Function") that carry a
-- string message name. Never create other remotes (AGENTS.md "Networking").
--
-- Server: OnEvent(name, fn(player, ...), options?), OnInvoke(name, fn(player, ...), options?),
--         FireClient(player, name, ...), FireAllClients(name, ...)
-- Client: OnEvent(name, fn(...)), FireServer(name, ...), Invoke(name, ...) -> reply (nil on failure)
-- options = { Capacity = n, RefillPerSecond = n } overrides the default rate limit for that message name.
-- OnEvent returns an object with Disconnect. Handlers are pcall-wrapped.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local TokenBucket = require(script.Parent.Utilities.TokenBucket)

local Network = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local MAX_NAME_LENGTH = 64 -- characters
local DEFAULT_CAPACITY = 20 -- messages in a burst
local DEFAULT_REFILL = 10 -- messages per second
local CLIENT_WAIT_TIMEOUT = 30 -- seconds to wait for the remotes
local CLIENT_QUEUE_CAP = 256 -- early messages held per client, all names combined

local EVENT_NAME = "Event"
local FUNCTION_NAME = "Function"

local isServer = RunService:IsServer()

local function isValidName(name)
	return type(name) == "string" and #name > 0 and #name <= MAX_NAME_LENGTH
end

local function runHandler(label, fn, ...)
	local ok, result = pcall(fn, ...)
	if not ok then
		warn(("[Network] Handler for %s failed: %s"):format(label, tostring(result)))
		return nil
	end
	return result
end

local function makeConnection(list, fn)
	local connection = { Connected = true }
	function connection:Disconnect()
		if not self.Connected then
			return
		end
		self.Connected = false
		local index = table.find(list, fn)
		if index then
			table.remove(list, index)
		end
	end
	return connection
end

if isServer then
	local remoteEvent = script:FindFirstChild(EVENT_NAME)
	if not remoteEvent then
		remoteEvent = Instance.new("RemoteEvent")
		remoteEvent.Name = EVENT_NAME
		remoteEvent.Parent = script
	end
	local remoteFunction = script:FindFirstChild(FUNCTION_NAME)
	if not remoteFunction then
		remoteFunction = Instance.new("RemoteFunction")
		remoteFunction.Name = FUNCTION_NAME
		remoteFunction.Parent = script
	end

	local eventHandlers = {} -- [name] = { fn, ... }
	local invokeHandlers = {} -- [name] = fn
	local limiters = {} -- [name] = TokenBucket, one bucket per player inside

	local limiterRates = {} -- [name] = { Capacity, Refill } the limiter was created with

	local function registerLimiter(name, options)
		local capacity = DEFAULT_CAPACITY
		local refill = DEFAULT_REFILL
		if type(options) == "table" then
			capacity = options.Capacity or capacity
			refill = options.RefillPerSecond or refill
		end
		local existing = limiterRates[name]
		if existing then
			-- The first registration wins; a silent mismatch would leave one handler with the wrong limit.
			if existing.Capacity ~= capacity or existing.Refill ~= refill then
				warn(
					`[Network] {name} was already registered with rate {existing.Capacity}/{existing.Refill}; ignoring {capacity}/{refill}`
				)
			end
			return
		end
		limiterRates[name] = { Capacity = capacity, Refill = refill }
		limiters[name] = TokenBucket.new(capacity, refill)
	end

	-- Every check runs before any handler, so garbage never reaches game code.
	local function admit(player, name)
		if not isValidName(name) then
			return false
		end
		-- A message from a player who just left must not recreate their bucket after PlayerRemoving cleaned it.
		if player.Parent ~= Players then
			return false
		end
		local limiter = limiters[name]
		if not limiter then
			return false
		end
		return limiter:TryTake(player)
	end

	function Network.OnEvent(name, fn, options)
		assert(isValidName(name), "[Network] Invalid message name")
		assert(type(fn) == "function", "[Network] OnEvent needs a function")
		registerLimiter(name, options)
		local list = eventHandlers[name]
		if not list then
			list = {}
			eventHandlers[name] = list
		end
		table.insert(list, fn)
		return makeConnection(list, fn)
	end

	function Network.OnInvoke(name, fn, options)
		assert(isValidName(name), "[Network] Invalid message name")
		assert(type(fn) == "function", "[Network] OnInvoke needs a function")
		if invokeHandlers[name] then
			error(("[Network] OnInvoke handler for %q is already registered"):format(name))
		end
		registerLimiter(name, options)
		invokeHandlers[name] = fn
	end

	function Network.FireClient(player, name, ...)
		assert(isValidName(name), "[Network] Invalid message name")
		remoteEvent:FireClient(player, name, ...)
	end

	function Network.FireAllClients(name, ...)
		assert(isValidName(name), "[Network] Invalid message name")
		remoteEvent:FireAllClients(name, ...)
	end

	remoteEvent.OnServerEvent:Connect(function(player, name, ...)
		if not admit(player, name) then
			return
		end
		local list = eventHandlers[name]
		if not list then
			return
		end
		-- Snapshot so a handler that disconnects mid-dispatch does not skip siblings.
		for _, fn in table.clone(list) do
			task.spawn(runHandler, name, fn, player, ...)
		end
	end)

	remoteFunction.OnServerInvoke = function(player, name, ...)
		if not admit(player, name) then
			return nil
		end
		local fn = invokeHandlers[name]
		if not fn then
			return nil
		end
		return runHandler(name, fn, player, ...)
	end

	Players.PlayerRemoving:Connect(function(player)
		for _, limiter in limiters do
			limiter:Remove(player)
		end
	end)
else
	local remoteEvent = script:WaitForChild(EVENT_NAME, CLIENT_WAIT_TIMEOUT)
	local remoteFunction = script:WaitForChild(FUNCTION_NAME, CLIENT_WAIT_TIMEOUT)
	if not remoteEvent or not remoteFunction then
		warn("[Network] Remotes not found after " .. CLIENT_WAIT_TIMEOUT .. " seconds")
	end

	local handlers = {} -- [name] = { fn, ... }
	local queue = {} -- messages that arrived before any handler, in order
	local hasWarnedCap = false

	local function dispatch(name, packed)
		for _, fn in table.clone(handlers[name]) do
			task.spawn(runHandler, name, fn, table.unpack(packed, 1, packed.n))
		end
	end

	function Network.OnEvent(name, fn)
		assert(isValidName(name), "[Network] Invalid message name")
		assert(type(fn) == "function", "[Network] OnEvent needs a function")
		local list = handlers[name]
		local isFirst = list == nil
		if isFirst then
			list = {}
			handlers[name] = list
		end
		table.insert(list, fn)

		if isFirst then
			-- Flush in arrival order; keep the rest of the queue for other names.
			local remaining = {}
			for _, message in queue do
				if message.name == name then
					dispatch(name, message.packed)
				else
					table.insert(remaining, message)
				end
			end
			queue = remaining
		end
		return makeConnection(list, fn)
	end

	function Network.FireServer(name, ...)
		if not remoteEvent or not isValidName(name) then
			return
		end
		remoteEvent:FireServer(name, ...)
	end

	function Network.Invoke(name, ...)
		if not remoteFunction or not isValidName(name) then
			return nil
		end
		local ok, result = pcall(remoteFunction.InvokeServer, remoteFunction, name, ...)
		if not ok then
			warn(("[Network] Invoke %s failed: %s"):format(name, tostring(result)))
			return nil
		end
		return result
	end

	if remoteEvent then
		remoteEvent.OnClientEvent:Connect(function(name, ...)
			if not isValidName(name) then
				return
			end
			if handlers[name] then
				dispatch(name, table.pack(...))
				return
			end
			if #queue >= CLIENT_QUEUE_CAP then
				if not hasWarnedCap then
					hasWarnedCap = true
					warn(("[Network] Early-message queue is full (%d); dropping %s"):format(CLIENT_QUEUE_CAP, name))
				end
				return
			end
			table.insert(queue, { name = name, packed = table.pack(...) })
		end)
	end
end

return Network
