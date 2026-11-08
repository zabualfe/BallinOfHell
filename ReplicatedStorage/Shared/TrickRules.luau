-- TrickRules
-- Pure trick maths shared by TrickController (client prediction) and TrickService (server authority), GDD 7.
-- Numbers come from Tables/TrickTable; nothing here touches the engine, so specs drive it with fake trajectories.
--
-- Eligibility (7.2)
--   TrickRules.NextAirborne(wasAirborne, groundDistance?, radius) -> boolean   -- hysteresis: grounded <= r+0.5, airborne with no hit within r+3
--   TrickRules.CanStart(context) -> ok, reason?
--       context = { RoundState, Airtime, Gliding?, Grappling?, Frozen?, GroundDrop? }  GroundDrop = studs to ground below, nil = none found
--       reason: "State" | "Frozen" | "Airtime" | "Glider" | "Grapple" | "Void"
--   TrickRules.PredictLanding(verticalVelocity, drop, gravity) -> seconds?   -- nil when drop is nil or beyond PredictMaxDrop
-- Picker (7.3)
--   TrickRules.Playable(equipped, owned) -> ids   -- equipped slots that exist and are owned (Free tricks are implicit), deduped
--   TrickRules.PlanBest(playable, options) -> { Plan, Points, Distinct, Raw }?
--       options = { Budget = seconds, Played = ids already played this airtime, Levels?, Assisted? }
--       Sequences of up to MaxTricksPerPlan, no trick twice in a row (also not right after Played), total duration <= Budget.
--       Best airtime score wins; ties go to the most different tricks, then to the earlier slot order.
-- Scoring (7.5, 7.6)
--   TrickRules.Score(entries, options?) -> { Points, Raw, Grade, Distinct, Variety, Assist, Parts }
--       entries = { { Id, Progress? } } in play order; Progress < 1 marks the trick cut by touchdown (>= 0.5 scores x0.5, below 0).
--       options = { Levels = { [id] = 1..3 }, Assisted = boolean, Void = boolean }
--       Grade: "Clean" | "Sloppy" | "Bail" (Void) | "None" (no entries). Variety counts different tricks that scored.
--   TrickRules.LandingText(grade, points) -> string   -- "CLEAN! 210", "SLOPPY! 367", "BAIL!" (<= 14 characters)
-- Coins and caps (7.5)
--   TrickRules.NewLedger() -> ledger         -- per player per round: { Carry, RoundCoins, SegmentCoins = { [segment] = n }, ... }
--   TrickRules.SegmentCap(tierName) -> number
--   TrickRules.Settle(ledger, segmentKey, points, segmentCap) -> baseCoins, flags   -- mutates the ledger
--       flags = { Trimmed, SegmentCapped, RoundCapped }; coins over a cap are dropped, the sub-coin remainder carries.
-- Server confirmation (7.9)
--   TrickRules.NewTracker() / TrickRules.Feed(tracker, sample) -> event?   -- builds airtime records from 10 Hz samples
--       sample = { Time, GroundDistance?, Radius, VerticalVelocity, Explained? (boolean or function), FreeGains? }
--       event = { Type = "Takeoff", Air } | { Type = "Land", Air }
--       Air = { StartT, EndT?, Duration?, Unexplained, FreeGains }. Takeoff/landing times are the midpoint between the
--       last sample on one side and the first on the other, so the error is unbiased (within +-0.05 s).
--   TrickRules.NoteUnexplained(ledger) -> boolean   -- counts an unexplained airtime this round; true when it earns a strike
--   TrickRules.IsVoid(air, voidTimes, confirmSeconds) -> boolean
--   TrickRules.AssistedIn(windows, startT, endT) -> boolean   -- windows = { [key] = { From, Until } }
--   TrickRules.ValidateReport(report) -> cleaned?, reason?     -- cleaned = { TrickIds, StartedAt, LandedAt }
--   TrickRules.Fit(trickIds, airSeconds) -> { Entries, Overshoot, Dropped }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TrickTable = require(ReplicatedStorage.Tables.TrickTable)

local TrickRules = {}

local EPSILON = 1e-9 -- float guard: 0.5 + 0.7 + 0.5 style sums must still fit a 1.7 s budget
local MAX_REPORT_TRICKS = 10
local MAX_REPORT_AIRTIME = 60 -- seconds, a report claiming more is nonsense
local MAX_ID_LENGTH = 32

local CONFIG = TrickTable.Config
local SCORING = TrickTable.Scoring

-- ── Eligibility ─────────────────────────────────────────────────────────

function TrickRules.NextAirborne(wasAirborne, groundDistance, radius)
	if groundDistance ~= nil and groundDistance <= radius + CONFIG.GroundRayExtra then
		return false
	end
	if groundDistance == nil then
		return true
	end
	return wasAirborne
end

function TrickRules.CanStart(context)
	if context.RoundState ~= "Race" then
		return false, "State"
	end
	if context.Frozen then
		return false, "Frozen"
	end
	if (context.Airtime or 0) < CONFIG.MinAirtime - EPSILON then
		return false, "Airtime"
	end
	if context.Gliding then
		return false, "Glider"
	end
	if context.Grappling then
		return false, "Grapple"
	end
	local drop = context.GroundDrop
	if drop == nil or drop > CONFIG.PredictMaxDrop then
		return false, "Void"
	end
	return true, nil
end

function TrickRules.PredictLanding(verticalVelocity, drop, gravity)
	if type(drop) ~= "number" or drop > CONFIG.PredictMaxDrop or gravity <= 0 then
		return nil
	end
	-- Ball already below the ground height it was measured against can't happen; clamp so sqrt stays real.
	local height = math.max(drop, 0)
	return (verticalVelocity + math.sqrt(verticalVelocity * verticalVelocity + 2 * gravity * height)) / gravity
end

-- ── Ownership ───────────────────────────────────────────────────────────

local function isOwned(trickId, owned)
	local trick = TrickTable.Tricks[trickId]
	if not trick then
		return false
	end
	return trick.Tier == "Free" or (type(owned) == "table" and owned[trickId] == true)
end

function TrickRules.IsOwned(trickId, owned)
	return type(trickId) == "string" and isOwned(trickId, owned)
end

function TrickRules.Playable(equipped, owned)
	local playable = {}
	local seen = {}
	if type(equipped) ~= "table" then
		return playable
	end
	for slot = 1, TrickTable.Loadout.Slots do
		local trickId = equipped[slot]
		if type(trickId) == "string" and not seen[trickId] and isOwned(trickId, owned) then
			seen[trickId] = true
			table.insert(playable, trickId)
		end
	end
	return playable
end

-- ── Scoring ─────────────────────────────────────────────────────────────

local function levelOf(levels, trickId)
	local level = levels and levels[trickId]
	if type(level) ~= "number" then
		return SCORING.LevelMultiplier[1]
	end
	return SCORING.LevelMultiplier[math.clamp(math.floor(level), 1, SCORING.MaxLevel)]
end

function TrickRules.ChainMultiplier(position)
	return math.min(1 + SCORING.ChainStep * (position - 1), SCORING.ChainCap)
end

function TrickRules.Score(entries, options)
	options = options or {}
	if options.Void then
		return { Points = 0, Raw = 0, Grade = "Bail", Distinct = 0, Variety = 1, Assist = 1, Parts = {} }
	end

	local seen = {}
	local scored = {}
	local distinct = 0
	local raw = 0
	local parts = {}
	local grade = "None"
	local position = 0
	for _, entry in entries do
		local trick = TrickTable.Tricks[entry.Id]
		if not trick then
			continue
		end
		position += 1
		grade = if grade == "None" then "Clean" else grade
		local fresh = if seen[entry.Id] then SCORING.RepeatMultiplier else 1
		seen[entry.Id] = true

		local landing = 1
		local progress = entry.Progress
		if type(progress) == "number" and progress < 1 then
			grade = "Sloppy"
			landing = if progress >= SCORING.SloppyMinProgress then SCORING.SloppyMultiplier else 0
		end

		local part = trick.BasePoints
			* levelOf(options.Levels, entry.Id)
			* TrickRules.ChainMultiplier(position)
			* fresh
			* landing
		table.insert(parts, part)
		raw += part
		if part > 0 and not scored[entry.Id] then
			scored[entry.Id] = true
			distinct += 1
		end
	end

	local variety = if distinct >= SCORING.VarietyMinDistinct then SCORING.VarietyMultiplier else 1
	local assist = if options.Assisted then SCORING.AssistMultiplier else 1
	local total = raw * variety * assist
	return {
		Points = math.floor(total + EPSILON),
		Raw = total,
		Grade = grade,
		Distinct = distinct,
		Variety = variety,
		Assist = assist,
		Parts = parts,
	}
end

function TrickRules.LandingText(grade, points)
	if grade == "Bail" then
		return "BAIL!"
	end
	return `{string.upper(grade)}! {points}`
end

-- ── Picker ──────────────────────────────────────────────────────────────

function TrickRules.PlanBest(playable, options)
	local budget = options.Budget
	local played = options.Played or {}
	if type(budget) ~= "number" or #playable == 0 then
		return nil
	end

	local entries = {}
	for _, trickId in played do
		table.insert(entries, { Id = trickId })
	end
	local baseCount = #entries
	local scoreOptions = { Levels = options.Levels, Assisted = options.Assisted }

	local best = nil
	local plan = {}
	local function consider()
		local result = TrickRules.Score(entries, scoreOptions)
		if
			not best
			or result.Raw > best.Raw + EPSILON
			or (math.abs(result.Raw - best.Raw) <= EPSILON and result.Distinct > best.Distinct)
		then
			best = { Plan = table.clone(plan), Points = result.Points, Distinct = result.Distinct, Raw = result.Raw }
		end
	end

	local function extend(remaining, lastId)
		if #plan >= CONFIG.MaxTricksPerPlan then
			return
		end
		for _, trickId in playable do
			local duration = TrickTable.Tricks[trickId].Duration
			if trickId ~= lastId and duration <= remaining + EPSILON then
				table.insert(plan, trickId)
				table.insert(entries, { Id = trickId })
				consider()
				extend(remaining - duration, trickId)
				table.remove(entries, baseCount + #plan)
				table.remove(plan)
			end
		end
	end
	extend(budget, played[#played])
	return best
end

-- ── Coins and caps ──────────────────────────────────────────────────────

function TrickRules.NewLedger()
	return { Carry = 0, RoundCoins = 0, SegmentCoins = {}, Points = 0, Unexplained = 0 }
end

function TrickRules.SegmentCap(tierName)
	return TrickTable.Caps.PerSegmentByTier[tierName] or 0
end

function TrickRules.Settle(ledger, segmentKey, points, segmentCap)
	local total = ledger.Carry + points
	local coins = math.floor(total / SCORING.PointsPerCoin)
	ledger.Carry = total - coins * SCORING.PointsPerCoin

	local segmentPaid = ledger.SegmentCoins[segmentKey] or 0
	local segmentRoom = math.max(0, segmentCap - segmentPaid)
	local roundRoom = math.max(0, TrickTable.Caps.PerRound - ledger.RoundCoins)
	local paid = math.min(coins, segmentRoom, roundRoom)

	ledger.SegmentCoins[segmentKey] = segmentPaid + paid
	ledger.RoundCoins += paid
	return paid,
		{
			Trimmed = paid < coins,
			SegmentCapped = segmentPaid + paid >= segmentCap,
			RoundCapped = ledger.RoundCoins >= TrickTable.Caps.PerRound,
		}
end

-- ── Server confirmation ─────────────────────────────────────────────────

function TrickRules.NewTracker()
	return { Airborne = false, Air = nil, Previous = nil }
end

function TrickRules.Feed(tracker, sample)
	local wasAirborne = tracker.Airborne
	local isAirborne = TrickRules.NextAirborne(wasAirborne, sample.GroundDistance, sample.Radius)
	local previous = tracker.Previous
	tracker.Previous = sample

	if isAirborne and not wasAirborne then
		local startT = if previous then (previous.Time + sample.Time) / 2 else sample.Time
		local air = { StartT = startT, Unexplained = false, FreeGains = sample.FreeGains or 0 }
		tracker.Airborne = true
		tracker.Air = air
		return { Type = "Takeoff", Air = air }
	end

	local air = tracker.Air
	if isAirborne and air and previous then
		-- Near the ground a bounce or a moving platform can lift the ball legitimately, so only clear air is audited.
		if previous.GroundDistance == nil and sample.GroundDistance == nil then
			local gain = sample.VerticalVelocity - previous.VerticalVelocity
			if gain > TrickTable.Server.MaxVerticalVelocityGain then
				local explained = sample.Explained
				if type(explained) == "function" then
					explained = explained()
				end
				if not explained then
					if air.FreeGains > 0 then
						air.FreeGains -= 1
					else
						air.Unexplained = true
					end
				end
			end
		end
		return nil
	end

	if wasAirborne and not isAirborne and air then
		air.EndT = if previous and previous ~= sample then (previous.Time + sample.Time) / 2 else sample.Time
		air.Duration = air.EndT - air.StartT
		tracker.Airborne = false
		tracker.Air = nil
		return { Type = "Land", Air = air }
	end
	return nil
end

-- One unexplained gain pays nothing but is not proof: a bump or moving platform the sampler can't see looks the same.
-- Repeating it within a round is what a cheat does, so only the 2nd and later ones strike (GDD 7.9).
function TrickRules.NoteUnexplained(ledger)
	ledger.Unexplained = (ledger.Unexplained or 0) + 1
	return ledger.Unexplained >= TrickTable.Server.UnexplainedStrikeAfter
end

function TrickRules.IsVoid(air, voidTimes, confirmSeconds)
	for _, time in voidTimes do
		if time >= air.StartT - EPSILON and time <= air.EndT + confirmSeconds then
			return true
		end
	end
	return false
end

function TrickRules.AssistedIn(windows, startT, endT)
	for _, window in windows do
		if window.From <= endT and window.Until >= startT then
			return true
		end
	end
	return false
end

local function isFiniteNumber(value)
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function TrickRules.ValidateReport(report)
	if type(report) ~= "table" then
		return nil, "Shape"
	end
	local ids = report.trickIds
	if type(ids) ~= "table" or not isFiniteNumber(report.startedAt) or not isFiniteNumber(report.landedAt) then
		return nil, "Shape"
	end
	local count = #ids
	if count < 1 or count > MAX_REPORT_TRICKS then
		return nil, "Shape"
	end
	local seen = 0
	for _ in ids do
		seen += 1
	end
	if seen ~= count then
		return nil, "Shape"
	end
	if report.landedAt < report.startedAt or report.landedAt - report.startedAt > MAX_REPORT_AIRTIME then
		return nil, "Shape"
	end

	local cleaned = {}
	for index = 1, count do
		local trickId = ids[index]
		if type(trickId) ~= "string" or #trickId > MAX_ID_LENGTH or not TrickTable.Tricks[trickId] then
			return nil, "Shape"
		end
		if trickId == cleaned[index - 1] then
			return nil, "Repeat"
		end
		cleaned[index] = trickId
	end
	return { TrickIds = cleaned, StartedAt = report.startedAt, LandedAt = report.landedAt }, nil
end

function TrickRules.Fit(trickIds, airSeconds)
	local available = airSeconds - CONFIG.MinAirtime
	local tolerance = TrickTable.Server.FitToleranceSeconds
	local entries = {}
	local overshoot = 0
	local dropped = 0
	local cursor = 0
	for index, trickId in trickIds do
		local duration = TrickTable.Tricks[trickId].Duration
		local finish = cursor + duration
		if finish <= available + tolerance + EPSILON then
			table.insert(entries, { Id = trickId })
		elseif cursor < available - EPSILON then
			-- Touchdown came during this trick: it is cut, and nothing after it played.
			table.insert(entries, { Id = trickId, Progress = (available - cursor) / duration })
			dropped = #trickIds - index
			break
		else
			overshoot = cursor - available
			dropped = #trickIds - index + 1
			break
		end
		cursor = finish
	end
	return { Entries = entries, Overshoot = overshoot, Dropped = dropped }
end

return TrickRules
