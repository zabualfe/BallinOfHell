-- ModifierService.ModifierRules
-- Pure rules for server-wide modifiers and trolls (GDD 11.3). No Instances, no clocks: callers pass `now`
-- (workspace:GetServerTimeNow() in production) and every piece of state in a plain table.
--
--   ModifierRules.Evaluate(def, trollRules, s) -> allowed, reason
--       def = ModifierTable.Modifiers[key]; trollRules = ModifierTable.TrollRules.
--       s = {
--         Now, InRace,
--         CountThisRound,            -- activations of this key this round (troll: use TrollCount instead)
--         ActiveEndsAt?, CooldownUntil?,     -- this key
--         ClockAdded, RaceClockBase,         -- PlusTwoMinutes only: seconds added so far, and the unmodified race clock
--         TrollActiveEndsAt?, TrollCooldownUntil?, TrollCount,   -- any troll
--         BuyerLastTrollAt?,         -- only passed at prompt time; nil skips the per-player interval
--       }
--       allowed = true -> reason is the mode: "Start" | "Extend" | "Instant".
--       allowed = false -> reason: NotRacing | RoundCap | Cooldown | StackFull | ClockCap | TrollActive | BuyerInterval
--   ModifierRules.ExtendedRemaining(remaining, add, cap) -> number
--   ModifierRules.IsNewPlayer(now, firstJoinAt, windowSeconds) -> boolean   -- unloaded data (0/nil) counts as new
--   ModifierRules.InFinale(checkpoint, segmentCount) -> boolean   -- checkpoint N means the player is in segment N + 1
--   ModifierRules.TrollImmunity(c) -> immune, reason?
--       c = { IsBuyer, Checkpoint, SegmentCount, Now, FirstJoinAt, Rules = TrollRules }

local ModifierRules = {}

local function isActive(endsAt, now)
	return endsAt ~= nil and endsAt > now
end

function ModifierRules.ExtendedRemaining(remaining, add, cap)
	return math.min(math.max(remaining, 0) + add, cap)
end

function ModifierRules.Evaluate(def, trollRules, s)
	if not s.InRace then
		return false, "NotRacing"
	end
	local now = s.Now

	if def.Kind == "Troll" then
		if isActive(s.TrollActiveEndsAt, now) then
			return false, "TrollActive"
		end
		if s.TrollCooldownUntil ~= nil and s.TrollCooldownUntil > now then
			return false, "Cooldown"
		end
		if s.TrollCount >= trollRules.MaxPerRound then
			return false, "RoundCap"
		end
		if s.BuyerLastTrollAt ~= nil and now - s.BuyerLastTrollAt < trollRules.PerPlayerIntervalSeconds then
			return false, "BuyerInterval"
		end
		return true, "Start"
	end

	if s.CountThisRound >= def.MaxPerRound then
		return false, "RoundCap"
	end

	if def.AddClockSeconds then
		if s.CooldownUntil ~= nil and s.CooldownUntil > now then
			return false, "Cooldown"
		end
		if s.RaceClockBase + s.ClockAdded + def.AddClockSeconds > def.MaxRaceClockSeconds then
			return false, "ClockCap"
		end
		return true, "Instant"
	end

	if isActive(s.ActiveEndsAt, now) then
		if s.ActiveEndsAt - now >= def.StackMaxSeconds then
			return false, "StackFull"
		end
		return true, "Extend"
	end
	if s.CooldownUntil ~= nil and s.CooldownUntil > now then
		return false, "Cooldown"
	end
	return true, "Start"
end

function ModifierRules.IsNewPlayer(now, firstJoinAt, windowSeconds)
	if type(firstJoinAt) ~= "number" or firstJoinAt <= 0 then
		return true
	end
	return now - firstJoinAt < windowSeconds
end

function ModifierRules.InFinale(checkpoint, segmentCount)
	if type(checkpoint) ~= "number" or segmentCount <= 0 then
		return false
	end
	return checkpoint + 1 >= segmentCount
end

function ModifierRules.TrollImmunity(c)
	if c.Rules.BuyerImmune and c.IsBuyer then
		return true, "Buyer"
	end
	if c.Rules.FinaleImmune and ModifierRules.InFinale(c.Checkpoint, c.SegmentCount) then
		return true, "Finale"
	end
	if ModifierRules.IsNewPlayer(c.Now, c.FirstJoinAt, c.Rules.NewPlayerImmunitySeconds) then
		return true, "NewPlayer"
	end
	return false
end

return ModifierRules
