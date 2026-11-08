-- ModifierService
-- Owns every server-wide paid modifier and troll (GDD 11.3, ModifierTable). It sets and, always, resets the
-- workspace attributes that BallService reads, so no modifier can outlive its timer, the round or the server.
--
-- Public API:
--   ModifierService.Activate(modifierKey, buyer, opts?) -> boolean, string?
--       Grant of a paid effect. true = granted: "Started" | "Extended" | "Applied" (instant, +2 Min) | "Queued".
--       A blocked effect (cooldown, cap, troll active, not in the Race) is QUEUED, never dropped (GDD 11.3 edge case),
--       unless opts.Queue == false, which returns false, reason instead. false also for an unknown key, a bad buyer
--       or a full queue (PurchaseService then retries the receipt).
--   ModifierService.CanPrompt(modifierKey, player) -> boolean   -- prompt-time gate used by Products/Modifiers
--   ModifierService.IsActive(modifierKey) -> boolean
--   ModifierService.GetEndsAt(modifierKey) -> number?           -- workspace:GetServerTimeNow() seconds
--
-- Rules summary (details in ModifierRules): same server modifier while active extends the remaining time up to
-- StackMaxSeconds; cooldown starts when it ends; MaxPerRound counts purchases. Trolls: one at a time, never extend,
-- 90 s server-wide cooldown measured from the end of the previous troll, 4 per round, 1 per buyer per 3 min (prompt
-- time only). Different modifiers run together. Everything active ends when the Race ends; counts and cooldowns reset
-- with each new round.
--
-- Troll immunity: the buyer, players in the Finale segment and players within NewPlayerImmunitySeconds of firstJoinAt
-- (not yet loaded counts as new) get the player attribute TrollImmune = true, which BallService honours. It is set before
-- the workspace attribute and cleared after it, and re-evaluated when someone joins or reaches the Finale mid-troll.
--
-- Queue and shutdown: the queue lives only in server memory. The receipt is already granted when an effect is queued,
-- so if the server shuts down with a non-empty queue those paid effects are lost; each one is logged with warn
-- (product, buyer UserId) for support. No automatic refund: the GDD gives no coin value for a Robux product, and
-- inventing one is an economy decision for the Director.
--
-- Workspace attributes (per key in ModifierTable.Modifiers): <Key> (true while active, nil otherwise) and
--   ModifierEndsAt_<Key> (GetServerTimeNow seconds, nil when inactive) for the banner/timer UI. Late joiners read these.
-- Network (server -> all clients):
--   ModifierStarted(key, buyerName, endsAt)   -- also on an extension (new endsAt). Instant modifiers: endsAt = now.
--   ModifierEnded(key)                        -- timed modifiers only, also when the round ends them early

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage.Network)
local AnalyticsTable = require(ReplicatedStorage.Tables.AnalyticsTable)
local ModifierTable = require(ReplicatedStorage.Tables.ModifierTable)
local RoundTable = require(ReplicatedStorage.Tables.RoundTable)

local AnalyticsService = require(script.Parent.AnalyticsService)
local BallService = require(script.Parent.BallService)
local CourseService = require(script.Parent.CourseService)
local PlayerData = require(script.Parent.PlayerData)
local ProgressService = require(script.Parent.ProgressService)
local RoundService = require(script.Parent.RoundService)
local ModifierRules = require(script.ModifierRules)

local ModifierService = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local ENDS_AT_PREFIX = "ModifierEndsAt_"
local IMMUNE_ATTRIBUTE = "TrollImmune"
local QUEUE_CAP = 20 -- queued paid effects per server
local DRAIN_TICK = 1 -- seconds between queue checks while anything is queued
local FINALE_FALLBACK_SEGMENTS = 30 -- when the course is not built yet
local TROLL_RULES = ModifierTable.TrollRules

-- ── State ───────────────────────────────────────────────────────────────
local active = {} -- [key] = { EndsAt, BuyerId, BuyerName }
local generations = {} -- [key] = number; a delayed end only acts if its generation is still current
local cooldownUntil = {} -- [key] = time, server modifiers
local counts = {} -- [key] = activations this round
local trollKey = nil -- the troll currently active
local trollCooldownUntil = nil
local trollCount = 0
local clockAdded = 0
local lastTrollAt = {} -- [userId] = time of that buyer's last troll
local queue = {} -- { { Key, BuyerId, BuyerName } } in purchase order
local draining = false
local roundId = nil
local raceReadyAt = 0
local isShuttingDown = false

-- ── Helpers ─────────────────────────────────────────────────────────────

local function now()
	return workspace:GetServerTimeNow()
end

local function isRacing()
	return RoundService.GetState() == "Race"
end

local function broadcast(name, ...)
	local ok, err = pcall(Network.FireAllClients, name, ...)
	if not ok then
		warn(`[ModifierService] Could not send {name}: {err}`)
	end
end

local function segmentCount()
	local built = CourseService.GetSegmentCount()
	return if built > 0 then built else FINALE_FALLBACK_SEGMENTS
end

local function setAttributes(key, endsAt)
	workspace:SetAttribute(key, if endsAt then true else nil)
	workspace:SetAttribute(ENDS_AT_PREFIX .. key, endsAt)
end

local function buildState(key, buyerId)
	local current = active[key]
	local activeTroll = trollKey and active[trollKey]
	return {
		Now = now(),
		InRace = isRacing(),
		CountThisRound = counts[key] or 0,
		ActiveEndsAt = current and current.EndsAt,
		CooldownUntil = cooldownUntil[key],
		ClockAdded = clockAdded,
		RaceClockBase = RoundTable.Steps.Race,
		TrollActiveEndsAt = activeTroll and activeTroll.EndsAt,
		TrollCooldownUntil = trollCooldownUntil,
		TrollCount = trollCount,
		BuyerLastTrollAt = buyerId and lastTrollAt[buyerId],
	}
end

-- ── Troll immunity ──────────────────────────────────────────────────────

local function isImmune(player, buyerId)
	return (
		ModifierRules.TrollImmunity({
			IsBuyer = player.UserId == buyerId,
			Checkpoint = player:GetAttribute("Checkpoint"),
			SegmentCount = segmentCount(),
			Now = now(),
			FirstJoinAt = PlayerData.Peek(player, "firstJoinAt"),
			Rules = TROLL_RULES,
		})
	)
end

-- Returns true when the attribute changed, so the caller can refresh that ball.
local function updateImmunity(player, buyerId)
	local immune = isImmune(player, buyerId) or nil
	if player:GetAttribute(IMMUNE_ATTRIBUTE) == immune then
		return false
	end
	player:SetAttribute(IMMUNE_ATTRIBUTE, immune)
	return true
end

local function clearImmunity()
	for _, player in Players:GetPlayers() do
		player:SetAttribute(IMMUNE_ATTRIBUTE, nil)
	end
end

-- ── Ending ──────────────────────────────────────────────────────────────

-- Clears attributes first so nothing later in this function can leave a modifier switched on.
local function endModifier(key, startCooldown)
	local entry = active[key]
	if not entry then
		return
	end
	active[key] = nil
	generations[key] = (generations[key] or 0) + 1
	setAttributes(key, nil)

	local def = ModifierTable.Modifiers[key]
	if def.Kind == "Troll" then
		trollKey = nil
		clearImmunity()
		if startCooldown then
			trollCooldownUntil = now() + TROLL_RULES.ServerCooldown
		end
	elseif startCooldown then
		cooldownUntil[key] = now() + def.Cooldown
	end
	broadcast("ModifierEnded", key)
end

local function endAll()
	for key in table.clone(active) do
		endModifier(key, false)
	end
end

local function resetRound()
	table.clear(counts)
	table.clear(cooldownUntil)
	trollCount = 0
	trollCooldownUntil = nil
	clockAdded = 0
end

-- ── Starting ────────────────────────────────────────────────────────────

local function scheduleEnd(key, endsAt)
	generations[key] = (generations[key] or 0) + 1
	local generation = generations[key]
	task.delay(math.max(endsAt - now(), 0), function()
		if generations[key] ~= generation or active[key] == nil then
			return
		end
		local ok, err = pcall(endModifier, key, true)
		if not ok then
			warn(`[ModifierService] Ending {key} failed, forcing reset: {err}`)
			active[key] = nil
			setAttributes(key, nil)
			if trollKey == key then
				trollKey = nil
				clearImmunity()
			end
			broadcast("ModifierEnded", key)
		end
	end)
end

local function logActivation(entry, mode, wasQueued)
	local buyer = Players:GetPlayerByUserId(entry.BuyerId)
	if buyer then
		AnalyticsService.Custom(buyer, AnalyticsTable.Events.ModifierActivated, 1, {
			Modifier = entry.Key,
			Mode = mode,
			Queued = wasQueued,
		})
	end
end

-- The caller has already checked the rules; returns the applied mode, or nil when it could not be applied.
local function apply(entry, mode, wasQueued)
	local key = entry.Key
	local def = ModifierTable.Modifiers[key]
	local startedAt = now()

	if mode == "Instant" then
		if not RoundService.AddTime(def.AddClockSeconds) then
			return nil
		end
		clockAdded += def.AddClockSeconds
		counts[key] = (counts[key] or 0) + 1
		cooldownUntil[key] = startedAt + def.Cooldown
		broadcast("ModifierStarted", key, entry.BuyerName, startedAt)
		logActivation(entry, mode, wasQueued)
		return "Applied"
	end

	local previous = active[key]
	local remaining = if mode == "Extend" and previous then previous.EndsAt - startedAt else 0
	local duration = if def.StackMaxSeconds
		then ModifierRules.ExtendedRemaining(remaining, def.Duration, def.StackMaxSeconds)
		else def.Duration
	local endsAt = startedAt + duration

	local ok, err = pcall(function()
		active[key] = { EndsAt = endsAt, BuyerId = entry.BuyerId, BuyerName = entry.BuyerName }
		if def.Kind == "Troll" then
			trollKey = key
			lastTrollAt[entry.BuyerId] = startedAt
			for _, player in Players:GetPlayers() do
				updateImmunity(player, entry.BuyerId)
			end
		end
		setAttributes(key, endsAt)
	end)
	if not ok then
		warn(`[ModifierService] Starting {key} failed, resetting: {err}`)
		active[key] = nil
		if trollKey == key then
			trollKey = nil
			clearImmunity()
		end
		setAttributes(key, nil)
		return nil
	end

	scheduleEnd(key, endsAt)
	counts[key] = (counts[key] or 0) + 1
	if def.Kind == "Troll" then
		trollCount += 1
	end
	broadcast("ModifierStarted", key, entry.BuyerName, endsAt)
	logActivation(entry, mode, wasQueued)
	return if mode == "Extend" then "Extended" else "Started"
end

-- ── Queue ───────────────────────────────────────────────────────────────

local function drainOnce()
	if not isRacing() or now() < raceReadyAt then
		return
	end
	local index = 1
	while index <= #queue do
		local entry = queue[index]
		local def = ModifierTable.Modifiers[entry.Key]
		local allowed, mode = ModifierRules.Evaluate(def, TROLL_RULES, buildState(entry.Key, nil))
		if allowed and apply(entry, mode, true) then
			table.remove(queue, index)
		else
			index += 1
		end
	end
end

local function ensureDrain()
	if draining then
		return
	end
	draining = true
	task.spawn(function()
		while #queue > 0 and not isShuttingDown do
			task.wait(DRAIN_TICK)
			local ok, err = pcall(drainOnce)
			if not ok then
				warn(`[ModifierService] Queue check failed: {err}`)
			end
		end
		draining = false
	end)
end

-- ── Public API ──────────────────────────────────────────────────────────

function ModifierService.Activate(modifierKey, buyer, opts)
	local def = type(modifierKey) == "string" and ModifierTable.Modifiers[modifierKey]
	if not def or typeof(buyer) ~= "Instance" or not buyer:IsA("Player") or isShuttingDown then
		return false
	end
	local entry = { Key = modifierKey, BuyerId = buyer.UserId, BuyerName = buyer.DisplayName }

	local allowed, reason = ModifierRules.Evaluate(def, TROLL_RULES, buildState(modifierKey, nil))
	if allowed then
		local result = apply(entry, reason, false)
		if result then
			return true, result
		end
		reason = "NotApplied"
	end

	if opts and opts.Queue == false then
		return false, reason
	end
	if #queue >= QUEUE_CAP then
		warn(`[ModifierService] Queue is full, {modifierKey} for {buyer.Name} not accepted`)
		return false, "QueueFull"
	end
	table.insert(queue, entry)
	ensureDrain()
	return true, "Queued"
end

function ModifierService.CanPrompt(modifierKey, player)
	local def = type(modifierKey) == "string" and ModifierTable.Modifiers[modifierKey]
	if not def or typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end
	local buyerId = if def.Kind == "Troll" then player.UserId else nil
	return (ModifierRules.Evaluate(def, TROLL_RULES, buildState(modifierKey, buyerId)))
end

function ModifierService.IsActive(modifierKey)
	return active[modifierKey] ~= nil
end

function ModifierService.GetEndsAt(modifierKey)
	local entry = active[modifierKey]
	return entry and entry.EndsAt
end

-- ── Wiring ──────────────────────────────────────────────────────────────

RoundService.StateChanged:Connect(function(stateName, newRoundId)
	if newRoundId ~= roundId then
		roundId = newRoundId
		resetRound()
	end
	if stateName == "Race" then
		raceReadyAt = now() + ModifierTable.QueuedStartDelayNextRace
		if #queue > 0 then
			ensureDrain()
		end
	else
		endAll()
	end
end)

local function reevaluateImmunity(player)
	local entry = trollKey and active[trollKey]
	if entry and updateImmunity(player, entry.BuyerId) then
		BallService.Refresh(player)
	end
end

ProgressService.CheckpointReached:Connect(reevaluateImmunity)
-- A skip can land in the Finale without passing through CheckpointReached.
ProgressService.Skipped:Connect(reevaluateImmunity)

-- Until their data loads a joiner counts as new, so the real firstJoinAt must be re-checked once it is there.
local function watchDataLoaded(player)
	player:GetAttributeChangedSignal("DataLoaded"):Connect(function()
		if player:GetAttribute("DataLoaded") == true then
			reevaluateImmunity(player)
		end
	end)
end

local function onPlayerAdded(player)
	watchDataLoaded(player)
	local entry = trollKey and active[trollKey]
	if entry then
		updateImmunity(player, entry.BuyerId)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

game:BindToClose(function()
	isShuttingDown = true
	endAll()
	clearImmunity()
	for _, entry in queue do
		warn(
			`[ModifierService] Server closing with a paid {entry.Key} still queued (buyer UserId {entry.BuyerId}); lost`
		)
	end
	table.clear(queue)
end)

roundId = workspace:GetAttribute("RoundId")

return ModifierService
