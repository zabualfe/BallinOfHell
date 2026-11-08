-- TokenBucket
-- Pure per-key rate limiter with an injectable clock, so it can be tested offline.
-- Each key (a player, say) gets its own bucket that starts full and refills continuously.
--
-- Usage:
--   local limiter = TokenBucket.new(capacity, refillPerSecond, clock?)  -- clock defaults to os.clock
--   limiter:TryTake(key, cost?) -> boolean   -- false when the bucket is empty (drop the message)
--   limiter:Remove(key)                      -- call when the key leaves, so buckets do not leak

local TokenBucket = {}
TokenBucket.__index = TokenBucket

function TokenBucket.new(capacity, refillPerSecond, clock)
	assert(type(capacity) == "number" and capacity > 0, "TokenBucket capacity must be a positive number")
	assert(type(refillPerSecond) == "number" and refillPerSecond >= 0, "TokenBucket refill must be >= 0")
	return setmetatable({
		_capacity = capacity,
		_refill = refillPerSecond,
		_clock = clock or os.clock,
		_buckets = {},
	}, TokenBucket)
end

function TokenBucket:TryTake(key, cost)
	cost = cost or 1
	local now = self._clock()
	local bucket = self._buckets[key]
	if not bucket then
		bucket = { tokens = self._capacity, last = now }
		self._buckets[key] = bucket
	end

	-- Clamp elapsed so a clock that steps backwards cannot drain the bucket.
	local elapsed = math.max(0, now - bucket.last)
	bucket.tokens = math.min(self._capacity, bucket.tokens + elapsed * self._refill)
	bucket.last = now

	if bucket.tokens < cost then
		return false
	end
	bucket.tokens -= cost
	return true
end

function TokenBucket:Remove(key)
	self._buckets[key] = nil
end

return TokenBucket
