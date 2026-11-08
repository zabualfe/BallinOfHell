-- ToolService.Rules
-- Pure tool rules (GDD 6, 13). No engine calls and no clock: callers pass `now`, so specs are offline.
--
-- Runtime (per player, per round; ToolService keeps it per UserId so leaving and rejoining can't refill it):
--   Rules.NewRuntime() -> rt     { FreeUsed, CooldownEnds, GlobalEnd, Uses, Temp, RefillsUsed }
--   Rules.ResetRound(rt)         free charges, cooldowns, uses, temporary charge and coin refills all clear
--
-- Activation:
--   Rules.Decide(input) -> ok, reason, source
--       input = { ToolId, SlotCount, Slot, TempSlot?, Owned, Stored, FreeLeft, TempCharges, Now, ToolReadyAt, GlobalReadyAt,
--                 SegmentUses, SegmentCap?, RoundState, Racing, NoTools, ToolsAllowed? (set) }
--       ToolId is what sits in the pressed slot ("" or nil = empty). Checks run in this order and the first failure wins:
--       "NoTool" "NotRacing" "NoTools" "NotAllowed" "NotOwned" "NoCharges" "Cooldown" "SegmentCap".
--       TempSlot = true (the press came through Rules.TEMP_SLOT) skips the loadout range check; the tool must still have a
--       Temp charge, otherwise "NoTool".
--       On success `source` is "Temp" | "Free" | "Stored" (see PlanSpend).
--   Rules.TEMP_SLOT = 0   -- pseudo-slot for the ToolRequired pickup (GDD 6.6): usable without owning or equipping the tool
--   Rules.ResolveUse(slot, equipped, rt, segment) -> toolId, isTempSlot   -- the tool a press means ("" = nothing)
--   Rules.PlanSpend({ Temp, Free, Stored }) -> "Temp" | "Free" | "Stored" | nil
--       Order: the segment's temporary charge, then free per-round charges, then stored charges.
--   Rules.FreeLeft(def, owned, unlimited, used) -> number   -- math.huge when the pass removes the limit
--   Rules.Record(rt, toolId, segment, source, now, cooldown, globalCooldown)   -- books a spend that Decide allowed
--
-- Segments:
--   Rules.SegmentCap(tierDef) -> number?      -- nil = no cap
--   Rules.UsesInSegment(rt, segment, toolId?) -> number   -- all tools, or one tool
--   Rules.RefreshTemp(rt, segment, toolRequiredId?)   -- gives the ToolRequired pickup's 1 charge; clears any other
--   Rules.TempCharges(rt, toolId, segment) -> number
--   Rules.ParseAllowed(text?) -> set?          -- "grapple, glider" -> { grapple = true, glider = true }
--   Rules.PocketBanned(def, tierName, tierDef) -> boolean   -- Pocket Checkpoint can't be placed in Hell or Finale
--   Rules.IsSafePoint(input) -> boolean        -- Shield rescue point: { Grounded, InSegment, OnBadSurface, NearKillBrick }
--
-- Loadout and shop:
--   Rules.SlotCount(config, hasBelt) -> number
--   Rules.CanEquip(input) -> ok, reason        -- { ToolId (or ""), Slot, SlotCount, MaxSlots, Known, Owned, Stored }; reasons
--       "BadSlot" "Locked" "Unknown" "NotOwned". "" empties the slot.
--   Rules.PlaceInSlot(equipped, slot, toolId, slotCount) -> list   -- a tool lives in one slot: it moves, and the old
--       slot gets the displaced tool
--   Rules.PlanBuy(input) -> ok, reason, action, price   -- { Known, Owned, Mode?, Coins, Price, RefillPrice, RefillsUsed, MaxRefills,
--       StoredCharges?, ChargeCap? }
--       action "Unlock" | "Refill"; reasons "Unknown" "BadMode" "AlreadyOwned" "NotOwned" "RefillLimit" "NoCoins" "AtCap"
--       (a refill with the stored stack already at ChargeCap). Everything that can fail is checked here, so the caller
--       only charges a purchase it can grant; if the grant still fails it refunds and does not count the refill.
--   Rules.AddCharges(current, amount, cap) -> newValue, added

local Rules = {}

local ROUND_STATE_RACE = "Race"

Rules.TEMP_SLOT = 0

-- ── Runtime ─────────────────────────────────────────────────────────────

function Rules.NewRuntime()
	return {
		FreeUsed = {}, -- [toolId] = free charges spent this round
		CooldownEnds = {}, -- [toolId] = time
		GlobalEnd = 0,
		Uses = {}, -- [segment] = { Total = n, ByTool = { [toolId] = n } }
		Temp = nil, -- { ToolId, Segment, Charges }
		RefillsUsed = {}, -- [toolId] = coin refills bought this round
	}
end

function Rules.ResetRound(rt)
	rt.FreeUsed = {}
	rt.CooldownEnds = {}
	rt.GlobalEnd = 0
	rt.Uses = {}
	rt.Temp = nil
	rt.RefillsUsed = {}
end

-- ── Charges ─────────────────────────────────────────────────────────────

function Rules.FreeLeft(def, owned, unlimited, used)
	if not owned then
		return 0
	end
	if unlimited then
		return math.huge
	end
	return math.max((def.FreeCharges or 0) - (used or 0), 0)
end

function Rules.PlanSpend(available)
	if (available.Temp or 0) > 0 then
		return "Temp"
	end
	if (available.Free or 0) > 0 then
		return "Free"
	end
	if (available.Stored or 0) > 0 then
		return "Stored"
	end
	return nil
end

function Rules.TempCharges(rt, toolId, segment)
	local temp = rt.Temp
	if temp and temp.ToolId == toolId and temp.Segment == segment then
		return temp.Charges
	end
	return 0
end

function Rules.RefreshTemp(rt, segment, toolRequiredId)
	if type(toolRequiredId) == "string" and toolRequiredId ~= "" then
		rt.Temp = { ToolId = toolRequiredId, Segment = segment, Charges = 1 }
	else
		rt.Temp = nil
	end
end

-- ── Activation ──────────────────────────────────────────────────────────

function Rules.ResolveUse(slot, equipped, rt, segment)
	if slot == Rules.TEMP_SLOT then
		local temp = rt.Temp
		if temp and temp.Segment == segment and temp.Charges > 0 then
			return temp.ToolId, true
		end
		return "", true
	end
	local toolId = equipped and equipped[slot]
	return if type(toolId) == "string" then toolId else "", false
end

function Rules.Decide(input)
	local toolId = input.ToolId
	if type(toolId) ~= "string" or toolId == "" or type(input.Slot) ~= "number" then
		return false, "NoTool", nil
	end
	if input.TempSlot then
		if (input.TempCharges or 0) < 1 then
			return false, "NoTool", nil
		end
	elseif input.Slot < 1 or input.Slot > input.SlotCount then
		return false, "NoTool", nil
	end
	if input.RoundState ~= ROUND_STATE_RACE or not input.Racing then
		return false, "NotRacing", nil
	end
	if input.NoTools then
		return false, "NoTools", nil
	end
	if input.ToolsAllowed and not input.ToolsAllowed[toolId] then
		return false, "NotAllowed", nil
	end

	local source = Rules.PlanSpend({ Temp = input.TempCharges, Free = input.FreeLeft, Stored = input.Stored })
	if not source then
		if input.Owned or (input.Stored or 0) > 0 then
			return false, "NoCharges", nil
		end
		return false, "NotOwned", nil
	end
	if input.Now < input.ToolReadyAt or input.Now < input.GlobalReadyAt then
		return false, "Cooldown", nil
	end
	if input.SegmentCap and input.SegmentUses >= input.SegmentCap then
		return false, "SegmentCap", nil
	end
	return true, nil, source
end

function Rules.Record(rt, toolId, segment, source, now, cooldown, globalCooldown)
	if source == "Temp" and rt.Temp then
		rt.Temp.Charges = math.max(rt.Temp.Charges - 1, 0)
	elseif source == "Free" then
		rt.FreeUsed[toolId] = (rt.FreeUsed[toolId] or 0) + 1
	end
	rt.CooldownEnds[toolId] = now + (cooldown or 0)
	rt.GlobalEnd = now + (globalCooldown or 0)
	local uses = rt.Uses[segment]
	if not uses then
		uses = { Total = 0, ByTool = {} }
		rt.Uses[segment] = uses
	end
	uses.Total += 1
	uses.ByTool[toolId] = (uses.ByTool[toolId] or 0) + 1
end

-- ── Segments ────────────────────────────────────────────────────────────

function Rules.SegmentCap(tierDef)
	return tierDef and tierDef.ToolCap or nil
end

function Rules.UsesInSegment(rt, segment, toolId)
	local uses = rt.Uses[segment]
	if not uses then
		return 0
	end
	if toolId then
		return uses.ByTool[toolId] or 0
	end
	return uses.Total
end

function Rules.ParseAllowed(text)
	if type(text) ~= "string" or text == "" then
		return nil
	end
	local set = {}
	for token in string.gmatch(text, "[^,%s]+") do
		set[token] = true
	end
	return set
end

function Rules.PocketBanned(def, tierName, tierDef)
	if def.BannedTiers and table.find(def.BannedTiers, tierName) then
		return true
	end
	return tierDef ~= nil and tierDef.BansPocketCheckpoint == true
end

function Rules.IsSafePoint(input)
	return input.Grounded == true
		and input.InSegment == true
		and input.OnBadSurface ~= true
		and input.NearKillBrick ~= true
end

-- ── Loadout and shop ────────────────────────────────────────────────────

function Rules.SlotCount(config, hasBelt)
	return if hasBelt then config.SlotsWithToolBelt else config.Slots
end

function Rules.CanEquip(input)
	local slot = input.Slot
	if type(slot) ~= "number" or slot ~= math.floor(slot) or slot < 1 or slot > input.MaxSlots then
		return false, "BadSlot"
	end
	if slot > input.SlotCount then
		return false, "Locked"
	end
	if input.ToolId == "" then
		return true, nil
	end
	if not input.Known then
		return false, "Unknown"
	end
	if not input.Owned and (input.Stored or 0) < 1 then
		return false, "NotOwned"
	end
	return true, nil
end

function Rules.PlaceInSlot(equipped, slot, toolId, slotCount)
	local list = {}
	for index = 1, slotCount do
		list[index] = equipped[index] or ""
	end
	if toolId ~= "" then
		for index, current in list do
			if current == toolId and index ~= slot then
				list[index] = list[slot]
			end
		end
	end
	list[slot] = toolId
	return list
end

function Rules.PlanBuy(input)
	if not input.Known then
		return false, "Unknown", nil, nil
	end
	local mode = input.Mode
	if mode == nil then
		mode = if input.Owned then "Refill" else "Unlock"
	end
	if mode == "Unlock" then
		if input.Owned then
			return false, "AlreadyOwned", nil, nil
		end
		if input.Coins < input.Price then
			return false, "NoCoins", nil, nil
		end
		return true, nil, "Unlock", input.Price
	end
	if mode == "Refill" then
		if not input.Owned then
			return false, "NotOwned", nil, nil
		end
		if (input.RefillsUsed or 0) >= input.MaxRefills then
			return false, "RefillLimit", nil, nil
		end
		if input.Coins < input.RefillPrice then
			return false, "NoCoins", nil, nil
		end
		if input.ChargeCap and (input.StoredCharges or 0) >= input.ChargeCap then
			return false, "AtCap", nil, nil
		end
		return true, nil, "Refill", input.RefillPrice
	end
	return false, "BadMode", nil, nil
end

function Rules.AddCharges(current, amount, cap)
	local newValue = math.min(current + amount, cap)
	return newValue, newValue - current
end

return Rules
