-- UpsellRules
-- Pure upsell decisions (GDD 11.4, 13), no engine calls. UpsellService feeds in the numbers and applies the result.
--
--   Rules.KindOf(trigger) -> "Popup" | "Inline" | "Toast" | "Results" | "ServerToast"
--       Only a Popup is spaced and counted against the 90 s rule. Inline never has a cap.
--   Rules.Gate(input) -> allowed, reason?
--       input = { Kind, Enabled, Cap, Shown, Now, LastPopupAt?, MinSpacing, IsFirstSession, SessionAge, QuietSeconds,
--                 QuietExempt, Countdown, NoneDuringCountdown, SegmentShown (list of trigger Types), MaxPerSegment, Type }
--       reason: "Disabled" | "Cap" | "Countdown" | "Spacing" | "Quiet" | "Segment". Checked in that order.
--   Rules.SegmentAllows(shownTypes, triggerType, maxPerSegment) -> boolean
--       At most maxPerSegment popups per segment; the fall triggers escalate (3 -> 5 -> 8 falls) so they may share one.
--   Rules.OrderOffers(offers, preferred?) -> list     -- preferred keys first (only ones the trigger offers), then the rest
--   Rules.PickOffers(ordered, isOfferable, single?) -> list   -- keeps the offerable ones; single stops at the first
--   Rules.Offerable(decided, defaultCheck) -> boolean
--       decided = a plug-in Eligible result (true/false/nil), defaultCheck = the product/pass check (true/false) or nil
--       when the key is neither. false always wins; a real product/pass check always runs after a plug-in true, so an
--       Eligible can never bypass PurchaseService.CanOffer. true only stands alone for keys with no product (Coins).
--   Rules.FallsReached(falls, threshold, segmentKey, lastKey?) -> boolean
--       True once per segment key: a new segment (or round) resets it, so the same count fires again there.
--   Rules.NearFinish(checkpoint, segmentCount, minSlots) -> boolean
--   Rules.ClockLow(timeLeft, secondsLeft) -> boolean
--   Rules.ToastDue(remaining, below, lastToastAt?, now, interval) -> boolean
--   Rules.NthLockedPremiumTier(premiumTrack, tier, nthTiers) -> boolean   -- the 1st/10th/20th/30th tier with a premium reward
--   Rules.SeasonBehind(tier, daysElapsed, secondsLeft, daysBehind, lastDays) -> boolean

local Rules = {}

local SECONDS_PER_DAY = 24 * 3600

function Rules.KindOf(trigger)
	if trigger.Inline then
		return "Inline"
	elseif trigger.ServerToast then
		return "ServerToast"
	elseif trigger.Toast then
		return "Toast"
	elseif trigger.ResultsCard then
		return "Results"
	end
	return "Popup"
end

function Rules.SegmentAllows(shownTypes, triggerType, maxPerSegment)
	if #shownTypes < maxPerSegment then
		return true
	end
	if triggerType ~= "FallsOnSegment" then
		return false
	end
	for _, shownType in shownTypes do
		if shownType ~= triggerType then
			return false
		end
	end
	return true
end

function Rules.Gate(input)
	if not input.Enabled then
		return false, "Disabled"
	end
	if input.Kind == "Inline" then
		return true
	end
	if input.Cap <= 0 or input.Shown >= input.Cap then
		return false, "Cap"
	end
	if input.Kind ~= "Popup" then
		return true
	end
	if input.Countdown and input.NoneDuringCountdown then
		return false, "Countdown"
	end
	if input.LastPopupAt ~= nil and input.Now - input.LastPopupAt < input.MinSpacing then
		return false, "Spacing"
	end
	if input.IsFirstSession and not input.QuietExempt and input.SessionAge < input.QuietSeconds then
		return false, "Quiet"
	end
	if not Rules.SegmentAllows(input.SegmentShown, input.Type, input.MaxPerSegment) then
		return false, "Segment"
	end
	return true
end

function Rules.OrderOffers(offers, preferred)
	local ordered = {}
	for _, key in preferred or {} do
		if table.find(offers, key) and not table.find(ordered, key) then
			table.insert(ordered, key)
		end
	end
	for _, key in offers do
		if not table.find(ordered, key) then
			table.insert(ordered, key)
		end
	end
	return ordered
end

function Rules.PickOffers(ordered, isOfferable, single)
	local picked = {}
	for _, key in ordered do
		if isOfferable(key) then
			table.insert(picked, key)
			if single then
				break
			end
		end
	end
	return picked
end

function Rules.Offerable(decided, defaultCheck)
	if decided == false then
		return false
	end
	if defaultCheck ~= nil then
		return defaultCheck
	end
	return decided == true
end

function Rules.FallsReached(falls, threshold, segmentKey, lastKey)
	return falls >= threshold and segmentKey ~= lastKey
end

function Rules.NearFinish(checkpoint, segmentCount, minSlots)
	return segmentCount - checkpoint <= minSlots
end

function Rules.ClockLow(timeLeft, secondsLeft)
	return timeLeft > 0 and timeLeft < secondsLeft
end

function Rules.ToastDue(remaining, below, lastToastAt, now, interval)
	if remaining == nil or remaining <= 0 or remaining >= below then
		return false
	end
	return lastToastAt == nil or now - lastToastAt >= interval
end

function Rules.NthLockedPremiumTier(premiumTrack, tier, nthTiers)
	local rewards = premiumTrack[tier]
	if rewards == nil or #rewards == 0 then
		return false
	end
	local count = 0
	for index = 1, tier do
		local entry = premiumTrack[index]
		if entry ~= nil and #entry > 0 then
			count += 1
		end
	end
	return table.find(nthTiers, count) ~= nil
end

function Rules.SeasonBehind(tier, daysElapsed, secondsLeft, daysBehind, lastDays)
	return secondsLeft > 0 and secondsLeft <= lastDays * SECONDS_PER_DAY and tier < daysElapsed - daysBehind
end

return Rules
