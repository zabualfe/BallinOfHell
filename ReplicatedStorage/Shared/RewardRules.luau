-- RewardRules
-- Pure reward-shape logic, no engine calls. RewardService executes the plan; WheelUI and others use Summarize.
--
-- Usage:
--   RewardRules.Normalize(rewards) -> ops, problems
--     rewards = one reward entry or a list of them. Every shape the Tables use is understood:
--       typed  { Type = "Coins"|"Spins"|"BoostMinutes"|"SkipToken", Amount = n }
--              Coins may carry Final = true: the amount is already multiplied, so no pass multiplier is applied.
--              { Type = "ToolCharges", ToolId|Id = s, Amount = n }   { Type = "ToolUnlock", ToolId|Id = s }
--              { Type = "Ball", BallId|Id = s }   { Type = "Trick"|"Trail"|"Title", Id = s, Name? = s }
--       flat   { Coins, FinalCoins (= Coins with Final), Spins, BoostMinutes, SkipTokens, ToolCharges = { [toolId] = n }, ToolUnlock = toolId,
--                BallId, FirstTimeBall, OnceEverBall, FirstTimeTrick }   (Daily, Timed, Starter Pack, first-fall)
--     Row metadata (Day, Minute, Name, VipCoins, Fallback, DuplicateCoins, Weight) is ignored: the owning
--     service picks VipCoins/Fallback and Economy pays ball duplicates. Any other field is a problem.
--     ops = ordered list of { Kind, Amount, Id?, Name?, Final? }. problems = list of strings, empty when valid.
--   RewardRules.Summarize(ops) -> list of { Kind, Amount, Id? }   -- client-friendly
--   RewardRules.ToEntry(op) -> typed entry that Normalize accepts back
--   RewardRules.IsOwnership(kind) -> boolean   -- granting twice is harmless (unlocks), unlike coins/spins/boosts
--   RewardRules.IsFinalGrant(granted, summary) -> boolean   -- true when a claim must be marked: fully granted, or partial
--     with a non-empty summary (re-granting would double-pay the parts that landed). Only an empty grant is retryable.
--   RewardRules.UsesMultiplier(source) -> boolean   -- whether coins from this source take the 2x Coins pass

local RewardRules = {}

local AMOUNT_KINDS = { Coins = true, Spins = true, BoostMinutes = true, SkipToken = true }
local OWNERSHIP_KINDS = { Ball = true, ToolUnlock = true, Trick = true, Trail = true, Title = true }
local ID_KINDS = { Trick = true, Trail = true, Title = true }
local NO_MULTIPLIER_SOURCES =
	{ StarterPack = true, Robux = true, CoinPack = true, Duplicate = true, Refund = true, Season = true }

-- Row metadata that is not a grant.
local IGNORED_FIELDS = {
	Day = true,
	Minute = true,
	Name = true,
	VipCoins = true,
	Fallback = true,
	DuplicateCoins = true,
	Weight = true,
}

-- Flat field -> op kind, in grant order.
local FLAT_AMOUNT_FIELDS = {
	{ "Coins", "Coins" },
	{ "FinalCoins", "Coins" },
	{ "Spins", "Spins" },
	{ "BoostMinutes", "BoostMinutes" },
	{ "SkipTokens", "SkipToken" },
}
local FLAT_ID_FIELDS = {
	{ "ToolUnlock", "ToolUnlock" },
	{ "BallId", "Ball" },
	{ "FirstTimeBall", "Ball" },
	{ "OnceEverBall", "Ball" },
	{ "FirstTimeTrick", "Trick" },
}
local FLAT_KNOWN = { ToolCharges = true }
for _, pair in FLAT_AMOUNT_FIELDS do
	FLAT_KNOWN[pair[1]] = true
end
for _, pair in FLAT_ID_FIELDS do
	FLAT_KNOWN[pair[1]] = true
end

local function isPositive(value)
	return type(value) == "number" and value == value and value > 0 and value < math.huge
end

local function isWhole(value)
	return isPositive(value) and value == math.floor(value)
end

local function isId(value)
	return type(value) == "string" and value ~= ""
end

local function addOp(ops, problems, kind, amount, id, name)
	if kind == "BoostMinutes" then
		if not isPositive(amount) then
			table.insert(problems, "BoostMinutes needs a positive Amount")
			return
		end
	elseif not isWhole(amount) then
		table.insert(problems, `{kind} needs a positive whole Amount`)
		return
	end
	table.insert(ops, { Kind = kind, Amount = amount, Id = id, Name = name })
end

local function normalizeTyped(entry, ops, problems)
	local kind = entry.Type
	if AMOUNT_KINDS[kind] then
		addOp(ops, problems, kind, entry.Amount)
		if kind == "Coins" and entry.Final == true and #ops > 0 and ops[#ops].Kind == "Coins" then
			ops[#ops].Final = true
		end
	elseif kind == "ToolCharges" then
		local toolId = entry.ToolId or entry.Id
		if not isId(toolId) then
			table.insert(problems, "ToolCharges needs a ToolId")
			return
		end
		addOp(ops, problems, kind, entry.Amount, toolId)
	elseif kind == "ToolUnlock" or kind == "Ball" or ID_KINDS[kind] then
		local id = entry.ToolId or entry.BallId or entry.Id
		if not isId(id) then
			table.insert(problems, `{kind} needs an id`)
			return
		end
		table.insert(ops, { Kind = kind, Amount = 1, Id = id, Name = entry.Name })
	else
		table.insert(problems, `unknown reward Type {tostring(kind)}`)
	end
end

local function normalizeFlat(entry, ops, problems)
	for key in entry do
		if not FLAT_KNOWN[key] and not IGNORED_FIELDS[key] then
			table.insert(problems, `unrecognised reward field {tostring(key)}`)
		end
	end
	for _, pair in FLAT_AMOUNT_FIELDS do
		local value = entry[pair[1]]
		if value ~= nil then
			addOp(ops, problems, pair[2], value)
			if pair[1] == "FinalCoins" and #ops > 0 and ops[#ops].Kind == "Coins" then
				ops[#ops].Final = true
			end
		end
	end
	local charges = entry.ToolCharges
	if charges ~= nil then
		if type(charges) ~= "table" then
			table.insert(problems, "ToolCharges must be a { [toolId] = amount } map")
		else
			local toolIds = {}
			for toolId in charges do
				table.insert(toolIds, tostring(toolId))
			end
			table.sort(toolIds)
			for _, toolId in toolIds do
				addOp(ops, problems, "ToolCharges", charges[toolId], toolId)
			end
		end
	end
	for _, pair in FLAT_ID_FIELDS do
		local value = entry[pair[1]]
		if value ~= nil then
			if isId(value) then
				table.insert(ops, { Kind = pair[2], Amount = 1, Id = value })
			else
				table.insert(problems, `{pair[1]} must be an id string`)
			end
		end
	end
end

local function isList(value)
	return value[1] ~= nil or next(value) == nil
end

local function normalizeEntry(entry, ops, problems)
	if type(entry) ~= "table" then
		table.insert(problems, "reward entry is not a table")
	elseif entry.Type ~= nil then
		normalizeTyped(entry, ops, problems)
	else
		normalizeFlat(entry, ops, problems)
	end
end

function RewardRules.Normalize(rewards)
	local ops, problems = {}, {}
	if type(rewards) ~= "table" then
		table.insert(problems, "rewards is not a table")
	elseif isList(rewards) then
		for _, entry in rewards do
			normalizeEntry(entry, ops, problems)
		end
	else
		normalizeEntry(rewards, ops, problems)
	end
	return ops, problems
end

function RewardRules.Summarize(ops)
	local summary = {}
	for _, op in ops do
		table.insert(summary, { Kind = op.Kind, Amount = op.Amount, Id = op.Id })
	end
	return summary
end

function RewardRules.ToEntry(op)
	return { Type = op.Kind, Amount = op.Amount, Id = op.Id, Name = op.Name, Final = op.Final }
end

function RewardRules.IsOwnership(kind)
	return OWNERSHIP_KINDS[kind] == true
end

function RewardRules.IsFinalGrant(granted, summary)
	return granted == true or (type(summary) == "table" and #summary > 0)
end

function RewardRules.UsesMultiplier(source)
	return NO_MULTIPLIER_SOURCES[source] ~= true
end

return RewardRules
