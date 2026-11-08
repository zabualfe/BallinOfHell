-- ToolController
-- Client side of the gameplay tools (GDD 6, ToolService). Owns input, the client-predicted feel of a press, rollback
-- when the server says no, and the state a hotbar UI draws. It decides nothing: charges, cooldowns and caps are the
-- server's (ToolService); what is shown here comes from the PlayerData mirror plus the server's ToolRuntime pushes.
-- No UI is built here; ToolBarUI (StarterGui, authored in Studio) listens to StateChanged and calls Use / Equip / Buy.
--
-- Public API:
--   ToolController.Use(slot)                      -- the press itself: keys 1/2/3, gamepad X/Y/RB and future mobile buttons call this.
--                                                    Slot 0 (key 4) is the segment's ToolRequired pickup (GDD 6.6): usable without owning it
--   ToolController.Equip(slot, toolId)            -- "" empties the slot; during a race it applies at the next checkpoint or respawn
--   ToolController.Buy(toolId, mode?)             -- coins: mode "Unlock" | "Refill" (default: Unlock if not owned, else Refill)
--   ToolController.GetSlots() -> { SlotState }    -- snapshot of the three slots (what StateChanged passes). The list also carries
--                                                    .TempSlot: the pickup's SlotState (ToolId "" when this segment has none)
--   ToolController.StateChanged   Signal (slots)  -- any change the hotbar shows: charges, cooldowns, loadout, segment rules
--   ToolController.Denied         Signal (slot, reason)   -- a press was blocked locally or rejected by the server
--   ToolController.EquipResult    Signal (slot, toolId, ok, reason, pending)
--   ToolController.BuyResult      Signal (toolId, ok, reason, action)
--
-- SlotState = { Slot, Locked (3rd slot without Tool Belt), ToolId ("" = empty), Def, Owned, Stored (stored charges),
--   Free (free charges left this round, math.huge = unlimited), Temp (segment pickup charge), Charges (what the button
--   shows: Temp + Free + Stored, math.huge = unlimited), CooldownEnd (GetServerTimeNow), CooldownSeconds, Ready,
--   Reason (why not: NoTool NotRacing NoTools NotAllowed NoCharges Cooldown SegmentCap), Pending (toolId waiting for a checkpoint),
--   Status (the tool's replicated state, e.g. Shield's Until) }
--
-- Plug-in tools: ToolController/Tools/<Name>.luau, same name as the server half. Contract in Tools/Shield.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Network = require(ReplicatedStorage.Network)
local Signal = require(ReplicatedStorage.Utilities.Signal)
local ToolTable = require(ReplicatedStorage.Tables.ToolTable)

local BallController = require(script.Parent.BallController)
local PlayerData = require(script.Parent.PlayerData)

local ToolController = {}
ToolController.StateChanged = Signal.new()
ToolController.Denied = Signal.new()
ToolController.EquipResult = Signal.new()
ToolController.BuyResult = Signal.new()

-- ── Tuning ──────────────────────────────────────────────────────────────
local CONFIG = ToolTable.Config
local TEMP_SLOT = 0 -- mirrors ToolService Rules.TEMP_SLOT
local SLOT_KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = TEMP_SLOT,
}
local SLOT_BUTTONS = {
	[Enum.KeyCode.ButtonX] = 1,
	[Enum.KeyCode.ButtonY] = 2,
	[Enum.KeyCode.ButtonR1] = 3,
}
local PENDING_FORGET_SECONDS = 5 -- a press the server never answered stops being rollback-able after this
local PRESS_LOCK_SECONDS = CONFIG.ClientRollbackSeconds -- same slot can't be pressed again inside the rollback window
local STATE_REQUEST_DELAY = 1 -- seconds after load before asking for the first ToolRuntime

-- ── State ───────────────────────────────────────────────────────────────
local toolModules = {} -- [toolId] = client plug-in
local runtime = nil -- latest ToolRuntime from the server
local pendingPresses = {} -- [slot] = { Cancel, At, Id }
local lockedUntil = {} -- [slot] = os.clock() deadline
local pressCounter = 0
local refreshToken = 0

local function now()
	return workspace:GetServerTimeNow()
end

local function equippedList()
	return PlayerData.Peek("equippedTools") or {}
end

-- ── Slot state ──────────────────────────────────────────────────────────

local function reasonFor(info)
	if info.ToolId == "" then
		return "NoTool"
	end
	local data = runtime
	if not data or not data.Racing or workspace:GetAttribute("RoundState") ~= "Race" then
		return "NotRacing"
	end
	if data.NoTools then
		return "NoTools"
	end
	if data.Allowed and not table.find(data.Allowed, info.ToolId) then
		if not (data.Temp and data.Temp.ToolId == info.ToolId) then
			return "NotAllowed"
		end
	end
	if info.Charges <= 0 then
		return "NoCharges"
	end
	if info.CooldownEnd > now() then
		return "Cooldown"
	end
	if data.SegmentCap > 0 and data.SegmentUses >= data.SegmentCap then
		return "SegmentCap"
	end
	return nil
end

local function buildSlot(slot)
	local data = runtime
	local isTempSlot = slot == TEMP_SLOT
	local toolId = if isTempSlot then (data and data.Temp and data.Temp.ToolId or "") else equippedList()[slot] or ""
	local def = ToolTable.Tools[toolId]
	if def == nil then
		toolId = ""
	end
	local owned = PlayerData.Peek("ownedTools") or {}
	local charges = PlayerData.Peek("toolCharges") or {}
	local slotCount = if data then data.SlotCount else CONFIG.Slots

	-- The pickup slot spends only the temporary charge, so stored and free charges don't show on it.
	local stored = if isTempSlot then 0 else charges[toolId] or 0
	local free = if isTempSlot then 0 elseif data and data.Free[toolId] ~= nil then data.Free[toolId] else 0
	if free == -1 then
		free = math.huge
	end
	local isOwned = not isTempSlot and (owned[toolId] == true or free == math.huge)
	if not isOwned then
		free = 0 -- free charges belong to owned tools
	end
	local temp = if data and data.Temp and data.Temp.ToolId == toolId then data.Temp.Charges else 0

	local cooldownEnd = 0
	if data then
		cooldownEnd = math.max(data.Cooldowns[toolId] or 0, data.GlobalEnd or 0)
	end

	local info = {
		Slot = slot,
		Locked = not isTempSlot and slot > slotCount,
		ToolId = toolId,
		Def = def,
		Owned = isOwned,
		Stored = stored,
		Free = free,
		Temp = temp,
		Charges = temp + free + stored,
		CooldownEnd = cooldownEnd,
		CooldownSeconds = def and def.Cooldown or 0,
		Pending = if isTempSlot then nil else data and data.Pending[slot],
		Status = data and data.Status[toolId] or nil,
	}
	info.Reason = if info.Locked then "NoTool" else reasonFor(info)
	info.Ready = info.Reason == nil
	return info
end

function ToolController.GetSlots()
	local slots = {}
	for slot = 1, CONFIG.SlotsWithToolBelt do
		slots[slot] = buildSlot(slot)
	end
	slots.TempSlot = buildSlot(TEMP_SLOT)
	return slots
end

-- Cooldowns end without any message, so the next change in readiness is scheduled.
local function scheduleRefresh(slots)
	refreshToken += 1
	local token = refreshToken
	local soonest = math.huge
	local current = now()
	for _, info in slots do -- includes slots.TempSlot
		if info.CooldownEnd > current then
			soonest = math.min(soonest, info.CooldownEnd - current)
		end
	end
	if soonest == math.huge then
		return
	end
	task.delay(soonest + 0.05, function()
		if token == refreshToken then
			ToolController.StateChanged:Fire(ToolController.GetSlots())
			scheduleRefresh(ToolController.GetSlots())
		end
	end)
end

local function publish()
	local slots = ToolController.GetSlots()
	ToolController.StateChanged:Fire(slots)
	scheduleRefresh(slots)
end

-- ── Pressing ────────────────────────────────────────────────────────────

local function cancelPress(slot)
	local press = pendingPresses[slot]
	pendingPresses[slot] = nil
	if press and press.Cancel then
		local ok, err = pcall(press.Cancel)
		if not ok then
			warn("[ToolController] Rollback failed: " .. tostring(err))
		end
	end
end

function ToolController.Use(slot)
	if type(slot) ~= "number" or slot < TEMP_SLOT or slot > CONFIG.SlotsWithToolBelt or slot ~= math.floor(slot) then
		return false
	end
	local clock = os.clock()
	if (lockedUntil[slot] or 0) > clock then
		return false
	end
	local info = buildSlot(slot)
	if info.Reason then
		ToolController.Denied:Fire(slot, info.Reason)
		return false
	end

	local ball = BallController.GetBall()
	local module = toolModules[info.ToolId]
	local context = { ToolId = info.ToolId, Def = info.Def, Slot = slot, Ball = ball, Controller = BallController }
	if module and module.CanPredict and ball then
		local ok, canPredict, reason = pcall(module.CanPredict, context)
		if ok and canPredict ~= true then
			ToolController.Denied:Fire(slot, if type(reason) == "string" then reason else "Denied")
			return false
		end
	end

	lockedUntil[slot] = clock + PRESS_LOCK_SECONDS
	local cancel = nil
	if module and module.Predict and ball then
		local ok, result = pcall(module.Predict, context)
		if ok then
			cancel = result
		else
			warn(`[ToolController] {info.ToolId}.Predict failed: {tostring(result)}`)
		end
	end

	pressCounter += 1
	local id = pressCounter
	pendingPresses[slot] = { Cancel = cancel, At = clock, Id = id }
	task.delay(PENDING_FORGET_SECONDS, function()
		local press = pendingPresses[slot]
		if press and press.Id == id then
			pendingPresses[slot] = nil
		end
	end)
	Network.FireServer("UseTool", slot, context.Payload)
	return true
end

function ToolController.Equip(slot, toolId)
	if type(slot) == "number" and type(toolId) == "string" then
		Network.FireServer("EquipTool", slot, toolId)
	end
end

function ToolController.Buy(toolId, mode)
	if type(toolId) == "string" and (mode == nil or type(mode) == "string") then
		Network.FireServer("BuyTool", toolId, mode)
	end
end

-- ── Server messages ─────────────────────────────────────────────────────

Network.OnEvent("ToolResult", function(slot, ok, reason)
	if type(slot) ~= "number" then
		return
	end
	if ok then
		pendingPresses[slot] = nil
		return
	end
	-- Rejected: undo the predicted effect and let the press go again.
	cancelPress(slot)
	lockedUntil[slot] = nil
	ToolController.Denied:Fire(slot, if type(reason) == "string" then reason else "Denied")
end)

Network.OnEvent("ToolRuntime", function(data)
	if type(data) ~= "table" then
		return
	end
	runtime = data
	publish()
end)

Network.OnEvent("ToolEquipResult", function(slot, toolId, ok, reason, pending)
	ToolController.EquipResult:Fire(slot, toolId, ok, reason, pending)
end)

Network.OnEvent("ToolBuyResult", function(toolId, ok, reason, action)
	ToolController.BuyResult:Fire(toolId, ok, reason, action)
end)

-- ── Input ───────────────────────────────────────────────────────────────

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	local slot = SLOT_KEYS[input.KeyCode] or SLOT_BUTTONS[input.KeyCode]
	if slot then
		ToolController.Use(slot)
	end
end)

-- ── Lifecycle ───────────────────────────────────────────────────────────

BallController.Unbound:Connect(function()
	for slot in pendingPresses do
		pendingPresses[slot] = nil
	end
	for _, module in toolModules do
		if module.Destroy then
			pcall(module.Destroy)
		end
	end
end)

for _, key in { "equippedTools", "ownedTools", "toolCharges" } do
	PlayerData.OnUpdate(key, publish)
end

for _, child in script.Tools:GetChildren() do
	if child:IsA("ModuleScript") then
		local toolId = string.lower(child.Name)
		if ToolTable.Tools[toolId] then
			local ok, module = pcall(require, child)
			if ok then
				toolModules[toolId] = module
			else
				warn(`[ToolController] Tools/{child.Name} failed to load: {tostring(module)}`)
			end
		else
			warn(`[ToolController] Tools/{child.Name} has no entry {toolId} in ToolTable`)
		end
	end
end

task.spawn(function()
	PlayerData.WaitForLoaded()
	task.wait(STATE_REQUEST_DELAY)
	Network.FireServer("ToolStateRequest")
	publish()
end)

return ToolController
