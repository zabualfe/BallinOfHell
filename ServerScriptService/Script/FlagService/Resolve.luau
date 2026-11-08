-- Resolve
-- Pure flag logic for FlagService: definition checks, remote-value resolution, retry backoff and
-- deterministic A/B bucketing. No engine calls, so it is covered by offline specs.
--
-- Flag definition contract (one per module in FlagService/Flags; a module may also return a list of them):
--   Key           string   remote-config key
--   Default       any      safe value used until config loads, on failure, or when Disabled
--   Disabled      bool?    true = ignore remote config and always use Default
--   ClientVisible bool?    true = mirrored as an attribute under ReplicatedStorage.Flags (bool/number/string only)
--   Variants      {[name]=weight}?   makes this an A/B test; Default must be a variant name
--   States        {[name]=value|fn(player)}?   what each variant means; fn is called by FlagService.GetState

local Resolve = {}

local UINT32 = 4294967296 -- 2^32

-- ── Definition checks ───────────────────────────────────────────────────

function Resolve.Validate(def)
	if type(def) ~= "table" then
		return false, "definition is not a table"
	end
	if type(def.Key) ~= "string" or def.Key == "" then
		return false, "missing Key"
	end
	if def.Default == nil then
		return false, "missing Default"
	end
	if def.Variants ~= nil then
		if type(def.Variants) ~= "table" or next(def.Variants) == nil then
			return false, "Variants must be a non-empty map of name -> weight"
		end
		for name, weight in def.Variants do
			if type(name) ~= "string" or type(weight) ~= "number" or weight < 0 then
				return false, "Variants entries must be string -> non-negative number"
			end
		end
		if def.Variants[def.Default] == nil then
			return false, "Default must name one of the Variants"
		end
	end
	return true
end

-- ── Value resolution ────────────────────────────────────────────────────

-- Remote values are accepted only when they have the same type as the Default, so a mistyped
-- remote entry can never break gameplay code.
function Resolve.Value(def, remote)
	if def.Disabled or remote == nil then
		return def.Default
	end
	if type(remote) ~= type(def.Default) then
		return def.Default
	end
	if def.Variants and def.Variants[remote] == nil then
		return def.Default
	end
	return remote
end

-- Seconds to wait before retry number `attempt` (1-based).
function Resolve.Backoff(attempt, base, cap)
	return math.min(cap, base * 2 ^ (attempt - 1))
end

-- ── A/B bucketing ───────────────────────────────────────────────────────

local function mul32(a, b)
	local low = a % 65536
	local high = (a - low) / 65536
	return ((high * b) % 65536 * 65536 + low * b) % UINT32
end

-- FNV-1a plus a murmur-style finaliser; the finaliser matters because FNV alone clusters sequential ids.
local function hash32(text)
	local hash = 2166136261
	for index = 1, #text do
		hash = mul32(bit32.bxor(hash, string.byte(text, index)), 16777619)
	end
	hash = mul32(bit32.bxor(hash, bit32.rshift(hash, 16)), 2246822507)
	hash = mul32(bit32.bxor(hash, bit32.rshift(hash, 13)), 3266489909)
	return bit32.bxor(hash, bit32.rshift(hash, 16))
end

-- Same user and test always land on the same point in [0, 1); different tests are independent.
function Resolve.Bucket(userId, testKey)
	return hash32(tostring(userId) .. ":" .. testKey) / UINT32
end

function Resolve.PickVariant(def, bucket)
	local names = {}
	local total = 0
	for name, weight in def.Variants do
		table.insert(names, name)
		total += weight
	end
	table.sort(names)
	if total <= 0 then
		return def.Default
	end

	local threshold = bucket * total
	local running = 0
	for _, name in names do
		running += def.Variants[name]
		if threshold < running then
			return name
		end
	end
	return def.Default
end

-- `remote` may force a variant (kill switch or full rollout) by naming it.
function Resolve.Variant(def, userId, remote)
	if def.Disabled or not def.Variants then
		return def.Default
	end
	if type(remote) == "string" and def.Variants[remote] ~= nil then
		return remote
	end
	return Resolve.PickVariant(def, Resolve.Bucket(userId, def.Key))
end

return Resolve
