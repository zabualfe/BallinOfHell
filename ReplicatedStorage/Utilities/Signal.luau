-- Signal
-- Minimal custom event. Handlers run in their own thread, so a yielding or erroring handler
-- cannot block the firer or other handlers.
--
-- Usage:
--   local signal = Signal.new()
--   local connection = signal:Connect(fn)  -- connection:Disconnect()
--   signal:Once(fn)
--   signal:Wait() -> ...                   -- yields until the next Fire
--   signal:Fire(...)
--   signal:DisconnectAll()

local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false
	local signal = self._signal
	local index = table.find(signal._handlers, self)
	if index then
		table.remove(signal._handlers, index)
	end
end

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local connection = setmetatable({ Connected = true, _signal = self, _fn = fn }, Connection)
	table.insert(self._handlers, connection)
	return connection
end

function Signal:Once(fn)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

function Signal:Wait()
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:Fire(...)
	-- Snapshot so handlers that disconnect during the fire do not skip siblings.
	for _, connection in table.clone(self._handlers) do
		if connection.Connected then
			task.spawn(connection._fn, ...)
		end
	end
end

function Signal:DisconnectAll()
	for _, connection in self._handlers do
		connection.Connected = false
	end
	table.clear(self._handlers)
end

Signal.Destroy = Signal.DisconnectAll

return Signal
