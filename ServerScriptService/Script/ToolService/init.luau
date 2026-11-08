-- ToolService
-- Gameplay tools (GDD 6, ARCHITECTURE 6.8): ownership, charges, loadout, cooldowns and activation validation.
-- The client asks, the server decides; the client only predicts the feel of a movement tool and rolls back on a "no".
-- Saved keys (PlayerData): ownedTools { [toolId] = true }, toolCharges { [toolId] = n }, equippedTools { id|"" x3 }.
-- Runtime (not saved, per UserId for the round so rejoining can't refill): free charges used, cooldowns, uses per
-- segment, the ToolRequired temporary charge, coin refills bought. All rules are in ToolService/Rules (pure, spec'd).
--
-- Public API (other systems code against this):
--   ToolService.AddCharges(player, toolId, amount, source) -> boolean   -- stored charges, capped at ToolTable.Config.ChargeCap.
--       false when the tool is unknown, amount isn't a positive integer, data isn't loaded or the stack is already full.
--   ToolService.Unlock(player, toolId, source) -> boolean               -- permanent unlock; false if already owned
--   ToolService.Owns(player, toolId) -> boolean                         -- permanent unlock (the Unlimited Rockets pass counts for rocket)
--   ToolService.GetCharges(player, toolId) -> number                    -- stored charges
--   ToolService.GetSafePoint(player) -> CFrame?                         -- newest Shield rescue point in the player's segment
--   ToolService.GetActiveWindows(player, fromTime?, toTime?, toolIds?) -> { { ToolId, Start, End } }
--       Every accepted use is recorded as a window [Start, End] in workspace:GetServerTimeNow() time: End is Start plus the
--       tool's effect length (MovementRules.WindowSeconds: Coil Duration, Glider MaxDuration, Grapple MaxPullSeconds, Rocket
--       hold + grace, Brake StopSeconds, Time Slow Duration, Spring 1 s), cut short when the effect ends early (Glider
--       landing). Returns copies of the windows overlapping [fromTime, toTime] (default: the last 30 s up to now).
--       toolIds is an optional set, e.g. { glider = true, grapple = true, coil = true }. Windows are kept ~2 minutes.
--   ToolService.WasActive(player, toolIds, fromTime, toTime) -> boolean   -- GetActiveWindows(...) is non-empty
--       TrickService's Assist (x0.5, GDD 7.5/7.9): WasActive(player, ASSIST_TOOLS, airStart, airEnd). ToolUsed alone is not
--       enough: it carries no time span and a Coil/Glider use starts before the airtime it assists.
--   ToolService.ToolUsed        Signal (player, toolId)                 -- after a use was accepted and paid for
--   ToolService.ChargesGranted  Signal (player, toolId, amount, source)
--   ToolService.Unlocked        Signal (player, toolId, source)
--   `source` is a short string for analytics and logs ("Robux", "Coins", "Reward", "Bundle", ...).
--
-- Tool plug-ins: ToolService/Tools/<Name>.luau where Name is the ToolTable id with a capital (shield -> Shield). The
-- contract (CanActivate, Activate, optional Reset / Status / Changed) is documented at the top of Tools/Shield.
-- A tool in ToolTable without a module rejects with "Unavailable" (all 9 have one).
--
-- Network (client -> server), Network rate limits in brackets:
--   UseTool(slot, payload?)     [4/s: ToolTable.Config.UseRateLimit]  -> ToolResult(slot, ok, reason?)
--                                   slot 0 = the segment's ToolRequired pickup (Rules.TEMP_SLOT): usable without owning or
--                                   equipping that tool, spends only the temporary charge
--                                   payload is untrusted tool input handed to the tool as context.Payload (Grapple: the
--                                   anchor Instance)
--   EquipTool(slot, toolId)     [burst 4, 1/s]  toolId "" empties the slot. During a race the change waits for the next
--                                   checkpoint or respawn  -> ToolEquipResult(slot, toolId, ok, reason?, pending)
--   BuyTool(toolId, mode?)      [burst 3, 0.5/s]  mode "Unlock" | "Refill" (default: Unlock if not owned, else Refill; coins)
--                                   -> ToolBuyResult(toolId, ok, reason?, action?)
--   ToolStateRequest()          [burst 2, 0.2/s]  -> ToolRuntime
-- Network (server -> client):
--   ToolResult(slot, ok, reason)  reasons: NoTool NotRacing NoTools NotAllowed NotOwned NoCharges Cooldown SegmentCap
--       Unavailable Error, or a tool's own (TierBanned SegmentLimit NotGrounded NotAirborne BadSurface AlreadyActive NoBall
--       NoTarget OutOfRange WrongSegment)
--   ToolRuntime({ Free, Cooldowns, GlobalEnd, Temp, SegmentUses, SegmentCap, NoTools, Allowed, Racing, Status,
--       SlotCount, Pending })  every change of what the hotbar shows. Times are workspace:GetServerTimeNow().
--       Free[toolId] = free charges left this round (-1 = unlimited). Temp = { ToolId, Charges }? for this segment.
--   ShieldAbsorbed(reason)  "KillBrick" | "FallZone", for the bubble pop and bounce effect

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnalyticsTable = require(ReplicatedStorage.Tables.AnalyticsTable)
local CourseTable = require(ReplicatedStorage.Tables.CourseTable)
local Network = require(ReplicatedStorage.Network)
local Signal = require(ReplicatedStorage.Utilities.Signal)
local ToolTable = require(ReplicatedStorage.Tables.ToolTable)

local AnalyticsService = require(script.Parent.AnalyticsService)
local BallService = require(script.Parent.BallService)
local CourseService = require(script.Parent.CourseService)
local EconomyService = require(script.Parent.EconomyService)
local GamePassService = require(script.Parent.GamePassService)
local PlayerData = require(script.Parent.PlayerData)
local ProgressService = require(script.Parent.ProgressService)
local RoundService = require(script.Parent.RoundService)
local MovementRules = require(script.MovementRules)
local Rules = require(script.Rules)
local SafePoint = require(script.SafePoint)
local Windows = require(script.Windows)

local ToolService = {}
ToolService.ToolUsed = Signal.new()
ToolService.ChargesGranted = Signal.new()
ToolService.Unlocked = Signal.new()

-- ── Tuning ──────────────────────────────────────────────────────────────
local CONFIG = ToolTable.Config
local EQUIP_RATE = { Capacity = 4, RefillPerSecond = 1 }
local BUY_RATE = { Capacity = 3, RefillPerSecond = 0.5 }
local STATE_RATE = { Capacity = 2, RefillPerSecond = 0.2 }
local USE_RATE = { Capacity = CONFIG.UseRateLimit, RefillPerSecond = CONFIG.UseRateLimit }
local ROUND_RESET_STATES = { Intermission = true, Teardown = true }
local TOOL_BELT_PASS = "ToolBelt"
local WINDOW_KEEP_SECONDS = 120 -- how long ended windows stay queryable
local WINDOW_DEFAULT_LOOKBACK = 30 -- seconds, GetActiveWindows without a range

-- ── State ───────────────────────────────────────────────────────────────
local toolModules = {} -- [toolId] = plug-in module
local runtimes = {} -- [userId] = Rules runtime, lives for the round
local windows = {} -- [player] = Windows list of accepted uses
local pendingEquips = {} -- [player] = { [slot] = toolId } waiting for a checkpoint or respawn
local movementTools = {}
for _, toolId in CourseTable.Progress.MovementTools do
	movementTools[toolId] = true
end

local function getRuntime(player)
	local rt = runtimes[player.UserId]
	if not rt then
		rt = Rules.NewRuntime()
		runtimes[player.UserId] = rt
	end
	return rt
end

local function isKnown(toolId)
	return type(toolId) == "string" and ToolTable.Tools[toolId] ~= nil
end

local function now()
	return workspace:GetServerTimeNow()
end

-- ── Segment lookup ──────────────────────────────────────────────────────

-- The segment a racing player is in is the one that ends at checkpoint (Checkpoint + 1).
local function segmentOf(player)
	local state = ProgressService.GetState(player)
	if not state then
		return nil, nil, nil
	end
	local segment = math.min(state.Checkpoint + 1, math.max(CourseService.GetSegmentCount(), 1))
	return state, segment, CourseService.GetCheckpoint(segment)
end

-- ── Ownership and charges ───────────────────────────────────────────────

local function hasUnlimited(player, toolId)
	local pass = CONFIG.UnlimitedPass
	return pass ~= nil and pass.ToolId == toolId and GamePassService.Owns(player, pass.PassKey)
end

function ToolService.Owns(player, toolId)
	if not isKnown(toolId) then
		return false
	end
	local owned = PlayerData.Peek(player, "ownedTools")
	return (owned ~= nil and owned[toolId] == true) or hasUnlimited(player, toolId)
end

function ToolService.GetCharges(player, toolId)
	local charges = PlayerData.Peek(player, "toolCharges")
	local count = charges and charges[toolId]
	return if type(count) == "number" then count else 0
end

function ToolService.AddCharges(player, toolId, amount, source)
	if
		not isKnown(toolId)
		or type(amount) ~= "number"
		or amount < 1
		or amount ~= math.floor(amount)
		or not PlayerData.IsLoaded(player)
	then
		return false
	end
	local current = ToolService.GetCharges(player, toolId)
	local newValue, added = Rules.AddCharges(current, amount, CONFIG.ChargeCap)
	if added < 1 or not PlayerData.SetPath(player, "toolCharges." .. toolId, newValue) then
		return false
	end
	ToolService.ChargesGranted:Fire(player, toolId, added, source)
	ToolService.PushRuntime(player)
	return true
end

function ToolService.Unlock(player, toolId, source)
	if not isKnown(toolId) or not PlayerData.IsLoaded(player) then
		return false
	end
	local owned = PlayerData.Peek(player, "ownedTools")
	if owned and owned[toolId] == true then
		return false
	end
	if not PlayerData.SetPath(player, "ownedTools." .. toolId, true) then
		return false
	end
	ToolService.Unlocked:Fire(player, toolId, source)
	ToolService.PushRuntime(player)
	return true
end

function ToolService.GetActiveWindows(player, fromTime, toTime, toolIds)
	local list = windows[player]
	if not list then
		return {}
	end
	local upper = if type(toTime) == "number" then toTime else now()
	local lower = if type(fromTime) == "number" then fromTime else upper - WINDOW_DEFAULT_LOOKBACK
	return Windows.Query(list, lower, upper, toolIds)
end

function ToolService.WasActive(player, toolIds, fromTime, toTime)
	return #ToolService.GetActiveWindows(player, fromTime, toTime, toolIds) > 0
end

function ToolService.GetSafePoint(player)
	local _, segment = segmentOf(player)
	return segment and SafePoint.GetPoint(player, segment) or nil
end

local function refreshTemp(player)
	local _, segment, checkpoint = segmentOf(player)
	if not segment then
		return
	end
	local required = checkpoint and checkpoint.Flags and checkpoint.Flags.ToolRequired
	if required ~= nil and not isKnown(required) then
		warn(`[ToolService] Segment {checkpoint.SegmentName} has ToolRequired {required}, which is not in ToolTable`)
		required = nil
	end
	Rules.RefreshTemp(getRuntime(player), segment, required)
end

-- ── Runtime snapshot for the hotbar ─────────────────────────────────────

local function slotCountFor(player)
	return Rules.SlotCount(CONFIG, GamePassService.Owns(player, TOOL_BELT_PASS))
end

local function buildRuntime(player)
	local rt = getRuntime(player)
	local state, segment, checkpoint = segmentOf(player)
	local tierDef = checkpoint and CourseTable.Tiers[checkpoint.Tier]
	local flags = checkpoint and checkpoint.Flags or {}

	local free, cooldowns, status = {}, {}, {}
	for toolId, def in ToolTable.Tools do
		local left =
			Rules.FreeLeft(def, ToolService.Owns(player, toolId), hasUnlimited(player, toolId), rt.FreeUsed[toolId])
		free[toolId] = if left == math.huge then -1 else left
		cooldowns[toolId] = rt.CooldownEnds[toolId]
		local module = toolModules[toolId]
		if module and module.Status then
			local ok, value = pcall(module.Status, player)
			status[toolId] = if ok then value else nil
		end
	end

	local temp = nil
	if segment and rt.Temp and rt.Temp.Segment == segment and rt.Temp.Charges > 0 then
		temp = { ToolId = rt.Temp.ToolId, Charges = rt.Temp.Charges }
	end

	local allowed = nil
	local allowedSet = Rules.ParseAllowed(flags.ToolsAllowed)
	if allowedSet then
		allowed = {}
		for toolId in allowedSet do
			table.insert(allowed, toolId)
		end
	end

	return {
		Free = free,
		Cooldowns = cooldowns,
		GlobalEnd = rt.GlobalEnd,
		Temp = temp,
		SegmentUses = segment and Rules.UsesInSegment(rt, segment) or 0,
		SegmentCap = Rules.SegmentCap(tierDef) or 0,
		NoTools = flags.NoTools == true,
		Allowed = allowed,
		Racing = state ~= nil and state.Racing == true,
		Status = status,
		SlotCount = slotCountFor(player),
		Pending = pendingEquips[player] or {},
	}
end

function ToolService.PushRuntime(player)
	if player.Parent == nil or not PlayerData.IsLoaded(player) then
		return
	end
	Network.FireClient(player, "ToolRuntime", buildRuntime(player))
end

-- ── Using a tool ────────────────────────────────────────────────────────

local function deny(player, slot, toolId, reason)
	Network.FireClient(player, "ToolResult", slot, false, reason)
	AnalyticsService.Custom(player, AnalyticsTable.Events.ToolDenied, nil, { ToolId = toolId or "", Reason = reason })
end

local function handleUse(player, slot, payload)
	if type(slot) ~= "number" or slot ~= math.floor(slot) or not PlayerData.IsLoaded(player) then
		return
	end
	local rt = getRuntime(player)
	local state, segment, checkpoint = segmentOf(player)
	local toolId, isTempSlot = Rules.ResolveUse(slot, PlayerData.Peek(player, "equippedTools"), rt, segment)
	local def = ToolTable.Tools[toolId]
	local module = toolModules[toolId]
	if def and not module then
		deny(player, slot, toolId, "Unavailable")
		return
	end

	local flags = checkpoint and checkpoint.Flags or {}
	local tierDef = checkpoint and CourseTable.Tiers[checkpoint.Tier]
	local allowedSet = Rules.ParseAllowed(flags.ToolsAllowed)
	if allowedSet and flags.ToolRequired then
		allowedSet[flags.ToolRequired] = true -- the free pickup must work in its own segment
	end

	local timeNow = now()
	local ok, reason, source = Rules.Decide({
		ToolId = toolId,
		Slot = slot,
		TempSlot = isTempSlot,
		SlotCount = slotCountFor(player),
		Owned = def ~= nil and ToolService.Owns(player, toolId),
		Stored = def and ToolService.GetCharges(player, toolId) or 0,
		FreeLeft = def and Rules.FreeLeft(
			def,
			ToolService.Owns(player, toolId),
			hasUnlimited(player, toolId),
			rt.FreeUsed[toolId]
		) or 0,
		TempCharges = segment and Rules.TempCharges(rt, toolId, segment) or 0,
		Now = timeNow,
		ToolReadyAt = rt.CooldownEnds[toolId] or 0,
		GlobalReadyAt = rt.GlobalEnd,
		SegmentUses = segment and Rules.UsesInSegment(rt, segment) or 0,
		SegmentCap = Rules.SegmentCap(tierDef),
		RoundState = workspace:GetAttribute("RoundState"),
		Racing = state ~= nil and state.Racing == true and not state.Finished,
		NoTools = flags.NoTools == true,
		ToolsAllowed = allowedSet,
	})
	if not ok then
		deny(player, slot, toolId, reason)
		return
	end

	local ball = BallService.GetBall(player)
	local context = {
		ToolId = toolId,
		Def = def,
		Segment = segment,
		Tier = checkpoint and checkpoint.Tier or nil,
		TierDef = tierDef,
		Flags = flags,
		Sample = BallService.GetSample(player),
		Now = timeNow,
		Payload = payload,
		UsesThisSegment = function(id)
			return Rules.UsesInSegment(rt, segment, id)
		end,
	}
	local vetoOk, vetoed, vetoReason = pcall(module.CanActivate, player, ball, context)
	if not vetoOk then
		warn(`[ToolService] {toolId}.CanActivate failed: {tostring(vetoed)}`)
		deny(player, slot, toolId, "Error")
		return
	end
	if vetoed ~= true then
		deny(player, slot, toolId, if type(vetoReason) == "string" then vetoReason else "Denied")
		return
	end

	-- Validated: charge, then apply.
	if source == "Stored" then
		local stored = ToolService.GetCharges(player, toolId)
		if not PlayerData.SetPath(player, "toolCharges." .. toolId, stored - 1) then
			deny(player, slot, toolId, "Error")
			return
		end
	end
	Rules.Record(rt, toolId, segment, source, timeNow, def.Cooldown, CONFIG.GlobalCooldown)
	if movementTools[toolId] then
		ProgressService.MarkMovementTool(player)
	end
	local list = windows[player]
	if not list then
		list = Windows.New()
		windows[player] = list
	end
	local window =
		Windows.Add(list, toolId, timeNow, timeNow + MovementRules.WindowSeconds(toolId, def), WINDOW_KEEP_SECONDS)
	context.CloseWindow = function()
		Windows.Close(window, now())
	end
	local applied, err = pcall(module.Activate, player, ball, context)
	if not applied then
		warn(`[ToolService] {toolId}.Activate failed: {tostring(err)}`)
	end

	Network.FireClient(player, "ToolResult", slot, true, nil)
	AnalyticsService.Custom(player, AnalyticsTable.Events.ToolUsed, nil, {
		ToolId = toolId,
		Slot = slot,
		Tier = context.Tier or "",
		Source = source,
	})
	ToolService.ToolUsed:Fire(player, toolId)
	ToolService.PushRuntime(player)
end

Network.OnEvent("UseTool", handleUse, USE_RATE)

-- ── Loadout ─────────────────────────────────────────────────────────────

local function canEquip(player, slot, toolId)
	return Rules.CanEquip({
		ToolId = toolId,
		Slot = slot,
		SlotCount = slotCountFor(player),
		MaxSlots = CONFIG.SlotsWithToolBelt,
		Known = isKnown(toolId),
		Owned = ToolService.Owns(player, toolId),
		Stored = ToolService.GetCharges(player, toolId),
	})
end

local function applyEquip(player, slot, toolId)
	local equipped = PlayerData.Get(player, "equippedTools")
	local placed = Rules.PlaceInSlot(equipped, slot, toolId, CONFIG.SlotsWithToolBelt)
	return PlayerData.Set(player, "equippedTools", placed)
end

local function flushPendingEquips(player)
	local pending = pendingEquips[player]
	if not pending then
		return
	end
	pendingEquips[player] = nil
	for slot, toolId in pending do
		if canEquip(player, slot, toolId) then
			applyEquip(player, slot, toolId)
		end
	end
	ToolService.PushRuntime(player)
end

Network.OnEvent("EquipTool", function(player, slot, toolId)
	if type(slot) ~= "number" or type(toolId) ~= "string" or not PlayerData.IsLoaded(player) then
		return
	end
	local ok, reason = canEquip(player, slot, toolId)
	if not ok then
		Network.FireClient(player, "ToolEquipResult", slot, toolId, false, reason, false)
		return
	end
	local state = ProgressService.GetState(player)
	if state and state.Racing and not state.Finished then
		pendingEquips[player] = pendingEquips[player] or {}
		pendingEquips[player][slot] = toolId
		Network.FireClient(player, "ToolEquipResult", slot, toolId, true, nil, true)
		ToolService.PushRuntime(player)
		return
	end
	pendingEquips[player] = nil
	if applyEquip(player, slot, toolId) then
		Network.FireClient(player, "ToolEquipResult", slot, toolId, true, nil, false)
		ToolService.PushRuntime(player)
	end
end, EQUIP_RATE)

-- ── Coin shop ───────────────────────────────────────────────────────────

Network.OnEvent("BuyTool", function(player, toolId, mode)
	if not isKnown(toolId) or (mode ~= nil and type(mode) ~= "string") or not PlayerData.IsLoaded(player) then
		return
	end
	local def = ToolTable.Tools[toolId]
	local rt = getRuntime(player)
	local refill = CONFIG.CoinRefill
	local ok, reason, action, price = Rules.PlanBuy({
		Known = true,
		Owned = ToolService.Owns(player, toolId),
		Mode = mode,
		Coins = EconomyService.GetCoins(player),
		Price = def.Price,
		RefillPrice = refill.Coins,
		RefillsUsed = rt.RefillsUsed[toolId],
		MaxRefills = refill.MaxPerToolPerRound,
		StoredCharges = ToolService.GetCharges(player, toolId),
		ChargeCap = CONFIG.ChargeCap,
	})
	if not ok then
		Network.FireClient(player, "ToolBuyResult", toolId, false, reason, nil)
		return
	end

	local sku = (if action == "Unlock" then "Tool_" else "ToolRefill_") .. toolId
	if not EconomyService.SpendCoins(player, price, AnalyticsTable.Transaction.Shop, sku) then
		Network.FireClient(player, "ToolBuyResult", toolId, false, "NoCoins", nil)
		return
	end
	local granted
	if action == "Unlock" then
		granted = ToolService.Unlock(player, toolId, "Coins")
	else
		granted = ToolService.AddCharges(player, toolId, refill.Charges, "Coins")
		if granted then
			rt.RefillsUsed[toolId] = (rt.RefillsUsed[toolId] or 0) + 1
		end
	end
	if not granted then
		warn(`[ToolService] {player.Name} paid {price} coins for {sku} but the grant failed; refunding`)
		if not EconomyService.AddCoins(player, price, AnalyticsTable.Transaction.Shop, "Refund_" .. sku) then
			warn(`[ToolService] Refund of {price} coins to {player.Name} for {sku} failed`)
		end
	end
	Network.FireClient(player, "ToolBuyResult", toolId, granted, if granted then nil else "Error", action)
end, BUY_RATE)

Network.OnEvent("ToolStateRequest", function(player)
	ToolService.PushRuntime(player)
end, STATE_RATE)

-- ── Round and segment wiring ────────────────────────────────────────────

local function resetTools(player)
	for _, module in toolModules do
		if module.Reset then
			pcall(module.Reset, player)
		end
	end
end

local function resetRound()
	-- Runtimes are per UserId so a rejoin can't refill; players who left the server are dropped here so it can't grow forever.
	local present = {}
	for _, player in Players:GetPlayers() do
		present[player.UserId] = true
	end
	for userId, rt in runtimes do
		if present[userId] then
			Rules.ResetRound(rt)
		else
			runtimes[userId] = nil
		end
	end
	for _, player in Players:GetPlayers() do
		resetTools(player)
		SafePoint.Forget(player)
		pendingEquips[player] = nil
		windows[player] = nil
		ToolService.PushRuntime(player)
	end
end

RoundService.StateChanged:Connect(function(stateName)
	if ROUND_RESET_STATES[stateName] then
		resetRound()
	elseif stateName == "Race" then
		for _, player in Players:GetPlayers() do
			refreshTemp(player)
			ToolService.PushRuntime(player)
		end
	end
end)

-- Segment entry and every respawn give the ToolRequired pickup's charge back; loadout changes land at the same moments.
local function onSegmentStart(player)
	local _, segment = segmentOf(player)
	SafePoint.Prune(player, segment)
	refreshTemp(player)
	flushPendingEquips(player)
	ToolService.PushRuntime(player)
end

ProgressService.CheckpointReached:Connect(onSegmentStart)
ProgressService.Skipped:Connect(onSegmentStart)
ProgressService.Fell:Connect(onSegmentStart)
ProgressService.AntiCheatFlag:Connect(onSegmentStart)
BallService.BallSpawned:Connect(onSegmentStart)

GamePassService.PassChanged:Connect(function(player, passKey)
	if passKey == TOOL_BELT_PASS or (CONFIG.UnlimitedPass and passKey == CONFIG.UnlimitedPass.PassKey) then
		ToolService.PushRuntime(player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	resetTools(player)
	pendingEquips[player] = nil
	windows[player] = nil
end)

-- ── Tool plug-ins ───────────────────────────────────────────────────────

for _, child in script.Tools:GetChildren() do
	if not child:IsA("ModuleScript") then
		continue
	end
	local toolId = string.lower(child.Name)
	if not ToolTable.Tools[toolId] then
		warn(`[ToolService] Tools/{child.Name} has no entry {toolId} in ToolTable; skipped`)
		continue
	end
	local ok, module = pcall(require, child)
	if not ok then
		warn(`[ToolService] Tools/{child.Name} failed to load: {tostring(module)}`)
	elseif type(module.CanActivate) ~= "function" or type(module.Activate) ~= "function" then
		warn(`[ToolService] Tools/{child.Name} must export CanActivate and Activate`)
	else
		toolModules[toolId] = module
		if module.Changed then
			module.Changed:Connect(function(player)
				ToolService.PushRuntime(player)
			end)
		end
	end
end

return ToolService
