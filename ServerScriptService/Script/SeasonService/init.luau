-- SeasonService
-- Owns the season pass (GDD 8): XP, tiers, claims, premium, season products and rollover. The active season comes
-- ONLY from FlagService (ActiveSeasonId, SeasonStartUtc, SeasonEndUtc, SeasonEndOverrideUtc). Pure maths lives in
-- SeasonService/Rules (specs); rewards are paid by RewardService.Grant(player, rewards, "Season").
--
-- Usage (server only; no remote adds XP):
--   SeasonService.AddXp(player, source, amount) -> boolean, gained   -- catch-up x1.5 applied here; false when no
--       active season, not synced yet, or a bad amount. `amount` is the base XP from the GDD table.
--   SeasonService.GetActive() -> { Id, Def, StartUtc, EndUtc, Name }?   -- nil when no season is running
--   SeasonService.HasPremium(player) -> boolean                          -- premium of the current season
--   SeasonService.GetSnapshot(player) -> table?                          -- what GetSeasonState returns
--   SeasonService.Claim(player, track, tier) -> boolean                  -- track "Free" | "Premium"
--   SeasonService.ClaimAll(player) -> number                             -- rewards claimed (tiers and bonus chests)
--   SeasonService.ClaimBonusChests(player) -> boolean
--   SeasonService.CanOfferProduct(player, productKey) -> boolean
--   SeasonService.GrantProduct(player, productKey) -> boolean            -- Products/Season only, inside ProcessReceipt
--   SeasonService.Sync(player)                                           -- close out an old season / enter the active one
--   SeasonService.Events:Connect(function(name, player, payload) end)    -- normalized gameplay events for challenges:
--       Checkpoint {Index, Tier}   Finish {Place}   RoundPlayed {} (only for players who reached checkpoint 1 or
--       finished that round)   TrickLanded {Points, Coins, Chain?}
--       ToolUsed {ToolId}          Spin {}          Coins {Amount, Kind}   Gift {}
--   SeasonService.TierReached:Connect(function(player, tier) end)
--
-- Event sources: ProgressService, DailyRewardService.Claimed, TimedRewardService.Claimed, EconomyService.Awarded and
-- RoundService.StateChanged are required directly. ToolService.ToolUsed(player, toolId),
-- TrickService.TrickLanded(player, points, coins, chain?) and SpinWheelService.Spun(player) belong to parallel tasks,
-- so they are required lazily and connected only if present.
--
-- Rollover: a saved season.id that differs from the active id (or whose end passed) is closed out at join or live:
-- every earned, unclaimed reward (and bonus chest) is granted, seasonHistory[id] = { tier, hasPremium } is written, then
-- season resets (XP 0, nothing claimed, premium from seasonPremiumCredit). Balls, tricks and trails stay owned
-- because they are normal inventory. If a grant fails with nothing granted the close-out is retried later; progress
-- is never wiped; after MAX_CLOSE_ATTEMPTS failed passes (~30 s) a reward that still cannot be paid is skipped with a
-- warn so one bad reward cannot block entry into the new season.
-- Products bought while no season runs are stored as seasonPremiumCredit / seasonTierCredit and applied on entry.
--
-- Player attributes (HUD): SeasonXp, SeasonTier, SeasonClaimable (rewards waiting), SeasonCatchUp (boolean).
-- Workspace attributes: ActiveSeasonId ("" when none), SeasonEndsAt (server time, 0 when none).
--
-- Network (client -> server):
--   ClaimSeasonReward(track, tier)      -- rate limited
--   ClaimAllSeasonRewards()             -- rate limited
--   ClaimSeasonBonusChests()            -- rate limited
--   GetSeasonState() invoke -> snapshot: { Active, SeasonId, Name, StartUtc, EndUtc, Xp, Tier, MaxTier, XpIntoTier,
--       XpPerTier, CatchUp, HasPremium, Claimable, BonusChestsReady, Offers = { [productKey] = boolean } }
-- Network (server -> owner):
--   SeasonXpGained(source, gained, isCatchUp)   SeasonTierReached(tier)   SeasonRewardClaimed(track, tier, summary)
--   SeasonBonusChests(count, summary)   SeasonPremiumUnlocked(claimableCount)
--   SeasonClosed({ SeasonId, FinalTier, HasPremium, Rewards = summary list })   SeasonClaimDenied(reason)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage.Network)
local Signal = require(ReplicatedStorage.Utilities.Signal)
local AnalyticsTable = require(ReplicatedStorage.Tables.AnalyticsTable)
local ProductTable = require(ReplicatedStorage.Tables.ProductTable)
local SeasonTable = require(ReplicatedStorage.Tables.SeasonTable)

local AnalyticsService = require(script.Parent.AnalyticsService)
local CourseService = require(script.Parent.CourseService)
local DailyRewardService = require(script.Parent.DailyRewardService)
local EconomyService = require(script.Parent.EconomyService)
local FlagService = require(script.Parent.FlagService)
local PlayerData = require(script.Parent.PlayerData)
local ProgressService = require(script.Parent.ProgressService)
local RoundService = require(script.Parent.RoundService)
local TimedRewardService = require(script.Parent.TimedRewardService)
local Rules = require(script.Rules)

local SeasonService = {}
SeasonService.Events = Signal.new()
SeasonService.TierReached = Signal.new()

-- ── Tuning ──────────────────────────────────────────────────────────────
local CLAIM_RATE = { Capacity = 4, RefillPerSecond = 1 } -- ClaimSeasonReward burst / per second
local CLAIM_ALL_RATE = { Capacity = 2, RefillPerSecond = 0.25 }
local STATE_RATE = { Capacity = 4, RefillPerSecond = 0.5 }
local CHECK_INTERVAL = 5 -- seconds between season-change checks
local DATA_WAIT_TIMEOUT = 60 -- seconds
local FUNNEL_PREFIX = "Season_"
local FUNNEL_TIERS = { [1] = true, [5] = true, [10] = true, [20] = true, [30] = true, [40] = true }
local MAX_CLOSE_ATTEMPTS = 6 -- failed close-out passes (CHECK_INTERVAL apart) before an unpayable reward is skipped
local SOURCE = "Season" -- RewardService source for track rewards
local TRACKS = { Free = "claimedFree", Premium = "claimedPremium" }

local baseConfig = SeasonTable.Config
local xpTable = SeasonTable.Xp
local events = AnalyticsTable.Events

-- ── State ───────────────────────────────────────────────────────────────
local runtime = {} -- [player] = { Ready, Syncing, Busy, TrickXp, CloseAttempts, BestCheckpoint, Finished }
local isRaceOpen = false
local lastWorldId, lastWorldEnd = nil, nil

-- ── Season lookup ───────────────────────────────────────────────────────

local function cfgFor(def)
	local cfg = table.clone(baseConfig)
	if def then
		cfg.Tiers = def.Tiers or cfg.Tiers
		cfg.XpPerTier = def.XpPerTier or cfg.XpPerTier
	end
	return cfg
end

local function schedule()
	local startUtc = FlagService.Get("SeasonStartUtc")
	local endUtc = Rules.EffectiveEnd(FlagService.Get("SeasonEndUtc"), FlagService.Get("SeasonEndOverrideUtc"))
	return FlagService.Get("ActiveSeasonId"), type(startUtc) == "number" and startUtc or 0, endUtc
end

function SeasonService.GetActive()
	local id, startUtc, endUtc = schedule()
	local def = type(id) == "string" and SeasonTable.Seasons[id]
	if not def or not Rules.IsActive(workspace:GetServerTimeNow(), startUtc, endUtc, 0) then
		return nil
	end
	return { Id = id, Def = def, Name = def.Name, StartUtc = startUtc, EndUtc = endUtc }
end

local function getState(player)
	return PlayerData.Peek(player, "season")
end

-- The player's season, only while it is the active one and the player has been synced.
local function currentState(player)
	local rt = runtime[player]
	local active = SeasonService.GetActive()
	local state = getState(player)
	if not (rt and rt.Ready and active and state and state.id == active.Id) then
		return nil
	end
	return state, active
end

function SeasonService.HasPremium(player)
	local state = currentState(player)
	return state ~= nil and state.hasPremium == true
end

-- ── Replication ─────────────────────────────────────────────────────────

local function claimableCount(state, active)
	local cfg = cfgFor(active.Def)
	return #Rules.ClaimableList(state, active.Def, cfg) + Rules.BonusChestsAvailable(state, cfg)
end

local function refresh(player)
	local state, active = currentState(player)
	if not state then
		player:SetAttribute("SeasonXp", 0)
		player:SetAttribute("SeasonTier", 0)
		player:SetAttribute("SeasonClaimable", 0)
		player:SetAttribute("SeasonCatchUp", false)
		return
	end
	local cfg = cfgFor(active.Def)
	player:SetAttribute("SeasonXp", state.xp)
	player:SetAttribute("SeasonTier", Rules.Tier(state.xp, cfg))
	player:SetAttribute("SeasonClaimable", claimableCount(state, active))
	player:SetAttribute("SeasonCatchUp", Rules.IsCatchUp(state.xp, workspace:GetServerTimeNow(), active.StartUtc, cfg))
end

local function publishWorld()
	local active = SeasonService.GetActive()
	local id = active and active.Id or ""
	local endsAt = active and active.EndUtc or 0
	if id ~= lastWorldId then
		lastWorldId = id
		workspace:SetAttribute("ActiveSeasonId", id)
	end
	if endsAt ~= lastWorldEnd then
		lastWorldEnd = endsAt
		workspace:SetAttribute("SeasonEndsAt", endsAt)
	end
end

function SeasonService.CanOfferProduct(player, productKey)
	local state, active = currentState(player)
	if not state or not table.find(active.Def.Products or {}, productKey) then
		return false
	end
	local ok = Rules.CanOfferProduct(productKey, state, workspace:GetServerTimeNow(), active.EndUtc, cfgFor(active.Def))
	return ok == true
end

function SeasonService.GetSnapshot(player)
	local state, active = currentState(player)
	if not state then
		return PlayerData.IsLoaded(player) and { Active = false, Offers = {} } or nil
	end
	local cfg = cfgFor(active.Def)
	local tier = Rules.Tier(state.xp, cfg)
	local offers = {}
	for _, key in active.Def.Products or {} do
		offers[key] = SeasonService.CanOfferProduct(player, key)
	end
	return {
		Active = true,
		SeasonId = active.Id,
		Name = active.Name,
		StartUtc = active.StartUtc,
		EndUtc = active.EndUtc,
		Xp = state.xp,
		Tier = tier,
		MaxTier = cfg.Tiers,
		XpIntoTier = tier >= cfg.Tiers and 0 or state.xp % cfg.XpPerTier,
		XpPerTier = cfg.XpPerTier,
		CatchUp = Rules.IsCatchUp(state.xp, workspace:GetServerTimeNow(), active.StartUtc, cfg),
		HasPremium = state.hasPremium == true,
		Claimable = claimableCount(state, active),
		BonusChestsReady = Rules.BonusChestsAvailable(state, cfg),
		Offers = offers,
	}
end

-- ── Rewards ─────────────────────────────────────────────────────────────

local function grantRewards(player, rewards)
	local child = script.Parent:FindFirstChild("RewardService")
	if not child then
		warn("[SeasonService] RewardService is missing from ServerScriptService.Script")
		return false, nil
	end
	local ok, granted, summary = pcall(function()
		return require(child).Grant(player, rewards, SOURCE)
	end)
	if not ok then
		warn(`[SeasonService] Grant errored: {tostring(granted)}`)
		return false, nil
	end
	return granted == true, summary
end

-- Reserve the claim flag, grant, and release the flag only if nothing at all was granted. A partial grant keeps
-- the claim so the parts that landed are never paid twice.
local function claimReward(player, seasonId, def, cfg, track, tier)
	local state = getState(player)
	if not state or state.id ~= seasonId or not Rules.CanClaim(state, def, track, tier, cfg) then
		return false
	end
	local path = `season.{TRACKS[track]}.{tier}`
	if not PlayerData.SetPath(player, path, true) then
		return false
	end
	local granted, summary = grantRewards(player, def[track][tier])
	if not granted and (summary == nil or #summary == 0) then
		PlayerData.SetPath(player, path, nil)
		return false
	end
	if not granted then
		warn(`[SeasonService] {player.Name} got a partial {track} reward at tier {tier}`)
	end
	return true, summary
end

local function claimChests(player, seasonId, cfg)
	local state = getState(player)
	if not state or state.id ~= seasonId then
		return 0
	end
	local count = Rules.BonusChestsAvailable(state, cfg)
	if count <= 0 then
		return 0
	end
	local before = state.bonusChests
	if not PlayerData.SetPath(player, "season.bonusChests", before + count) then
		return 0
	end
	local granted, summary = grantRewards(player, Rules.ChestRewards(count, state.hasPremium == true, cfg))
	if not granted and (summary == nil or #summary == 0) then
		PlayerData.SetPath(player, "season.bonusChests", before)
		return 0
	end
	return count, summary
end

local function withLock(player, fn)
	local rt = runtime[player]
	if not rt or rt.Busy or rt.Syncing then
		return nil
	end
	rt.Busy = true
	local ok, a, b = pcall(fn)
	rt.Busy = false
	if not ok then
		warn(`[SeasonService] {tostring(a)}`)
		return nil
	end
	return a, b
end

function SeasonService.Claim(player, track, tier)
	if TRACKS[track] == nil then
		return false
	end
	return withLock(player, function()
		local state, active = currentState(player)
		if not state then
			return false
		end
		local ok, summary = claimReward(player, active.Id, active.Def, cfgFor(active.Def), track, tier)
		if not ok then
			Network.FireClient(player, "SeasonClaimDenied", "NotClaimable")
			return false
		end
		AnalyticsService.Custom(player, events.SeasonRewardClaimed, tier, {
			SeasonId = active.Id,
			Tier = tier,
			Track = track,
			Kind = active.Def[track][tier][1].Type,
		})
		Network.FireClient(player, "SeasonRewardClaimed", track, tier, summary)
		refresh(player)
		return true
	end) == true
end

function SeasonService.ClaimBonusChests(player)
	return withLock(player, function()
		local state, active = currentState(player)
		if not state then
			return false
		end
		local count, summary = claimChests(player, active.Id, cfgFor(active.Def))
		if count <= 0 then
			return false
		end
		Network.FireClient(player, "SeasonBonusChests", count, summary)
		refresh(player)
		return true
	end) == true
end

function SeasonService.ClaimAll(player)
	return withLock(player, function()
		local state, active = currentState(player)
		if not state then
			return 0
		end
		local cfg = cfgFor(active.Def)
		local claimed = 0
		for _, entry in Rules.ClaimableList(state, active.Def, cfg) do
			local ok, summary = claimReward(player, active.Id, active.Def, cfg, entry.Track, entry.Tier)
			if ok then
				claimed += 1
				AnalyticsService.Custom(player, events.SeasonRewardClaimed, entry.Tier, {
					SeasonId = active.Id,
					Tier = entry.Tier,
					Track = entry.Track,
					Kind = entry.Rewards[1].Type,
				})
				Network.FireClient(player, "SeasonRewardClaimed", entry.Track, entry.Tier, summary)
			end
		end
		local chests, chestSummary = claimChests(player, active.Id, cfg)
		if chests > 0 then
			claimed += chests
			Network.FireClient(player, "SeasonBonusChests", chests, chestSummary)
		end
		refresh(player)
		return claimed
	end) or 0
end

-- ── XP ──────────────────────────────────────────────────────────────────

local function reachTier(player, active, state, tier)
	AnalyticsService.Custom(player, events.SeasonTierReached, tier, {
		SeasonId = active.Id,
		Tier = tier,
		HasPremium = state.hasPremium == true,
		Day = Rules.DaysElapsed(workspace:GetServerTimeNow(), active.StartUtc),
	})
	if FUNNEL_TIERS[tier] then
		AnalyticsService.Funnel(player, FUNNEL_PREFIX .. active.Id, "Tier" .. tier)
	end
	Network.FireClient(player, "SeasonTierReached", tier)
	SeasonService.TierReached:Fire(player, tier)
end

-- Writes new XP and fires each newly crossed tier once. XP never goes down inside a season, so a tier is crossed once.
local function commitXp(player, active, state, newXp)
	local cfg = cfgFor(active.Def)
	local oldTier = Rules.Tier(state.xp, cfg)
	if not PlayerData.SetPath(player, "season.xp", newXp) then
		return false
	end
	local newTier = Rules.Tier(newXp, cfg)
	for tier = oldTier + 1, newTier do
		reachTier(player, active, state, tier)
	end
	refresh(player)
	return true
end

function SeasonService.AddXp(player, source, amount)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or type(source) ~= "string" then
		return false, 0
	end
	local state, active = currentState(player)
	if not state then
		return false, 0
	end
	local cfg = cfgFor(active.Def)
	local newXp, gained, isCatchUp = Rules.ApplyXp(state.xp, amount, workspace:GetServerTimeNow(), active.StartUtc, cfg)
	if gained <= 0 or not commitXp(player, active, state, newXp) then
		return false, 0
	end
	Network.FireClient(player, "SeasonXpGained", source, gained, isCatchUp)
	return true, gained
end

-- ── Products ────────────────────────────────────────────────────────────

local function fireBought(player, name, fields)
	AnalyticsService.Custom(player, name, fields.Value, fields)
end

function SeasonService.GrantProduct(player, productKey)
	local row = ProductTable[productKey]
	local rt = runtime[player]
	if not row or row.Family ~= "Season" or not rt or not PlayerData.IsLoaded(player) then
		return false
	end
	if rt.Syncing or rt.Busy then
		return false -- Roblox re-sends the receipt
	end
	local params = row.Params or {}
	local state, active = currentState(player)
	if not state then
		-- No season is running: keep the purchase as credit for the next season instead of retrying forever (GDD 8.7).
		if not (rt.Ready and SeasonService.GetActive() == nil) then
			return false
		end
		local premium, tiers = Rules.CreditPlan(
			params,
			PlayerData.Peek(player, "seasonPremiumCredit") == true,
			PlayerData.Peek(player, "seasonTierCredit") or 0,
			baseConfig
		)
		if
			tiers ~= (PlayerData.Peek(player, "seasonTierCredit") or 0)
			and not PlayerData.Set(player, "seasonTierCredit", tiers)
		then
			return false
		end
		if premium and PlayerData.Peek(player, "seasonPremiumCredit") ~= true then
			return PlayerData.Set(player, "seasonPremiumCredit", true)
		end
		return true
	end

	local cfg = cfgFor(active.Def)
	local plan = Rules.PurchasePlan(params, state, cfg)
	local tierBefore = Rules.Tier(state.xp, cfg)
	local unlocked = 0
	if plan.SetPremium then
		if not PlayerData.SetPath(player, "season.hasPremium", true) then
			return false
		end
		unlocked = #Rules.ClaimableList(getState(player), active.Def, cfg)
	end
	if plan.XpToAdd > 0 then
		commitXp(player, active, getState(player), state.xp + plan.XpToAdd)
	end

	local day = Rules.DaysElapsed(workspace:GetServerTimeNow(), active.StartUtc)
	if plan.SetPremium then
		Network.FireClient(player, "SeasonPremiumUnlocked", unlocked)
		AnalyticsService.Funnel(player, FUNNEL_PREFIX .. active.Id, "PremiumBought")
		fireBought(player, events.SeasonPremiumBought, {
			Value = unlocked,
			SeasonId = active.Id,
			Product = productKey,
			Tier = tierBefore,
			Day = day,
			Unlocked = unlocked,
		})
	end
	if plan.Tiers > 0 then
		fireBought(player, events.SeasonTiersBought, {
			Value = plan.Tiers,
			SeasonId = active.Id,
			Tiers = plan.Tiers,
			Price = row.Price,
			TierAfter = Rules.Tier(getState(player).xp, cfg),
		})
	end
	refresh(player)
	return true
end

-- ── Sync and rollover ───────────────────────────────────────────────────

local function flatten(summaries)
	local out = {}
	for _, summary in summaries do
		for _, part in summary do
			table.insert(out, part)
		end
	end
	return out
end

local function freshSeason(id, hasPremium)
	return { id = id, xp = 0, claimedFree = {}, claimedPremium = {}, hasPremium = hasPremium, bonusChests = 0 }
end

-- A failed grant keeps the old season and is retried on the next check (progress is never wiped). Once the player's
-- attempts hit MAX_CLOSE_ATTEMPTS the failing reward is skipped with a warn so the new season can start.
local function shouldRetry(rt, what, player, seasonId)
	rt.CloseAttempts += 1
	if rt.CloseAttempts < MAX_CLOSE_ATTEMPTS then
		warn(`[SeasonService] Close-out of {seasonId} for {player.Name} paused at {what}`)
		return true
	end
	warn(`[SeasonService] Close-out of {seasonId} for {player.Name} skipped {what} after {rt.CloseAttempts} attempts`)
	return false
end

-- Returns false when a grant failed so the caller keeps the old season and retries later.
local function closeOut(player, state, rt)
	local def = SeasonTable.Seasons[state.id]
	local cfg = cfgFor(def)
	local plan = Rules.RolloverPlan(state, def, cfg)
	local summaries = {}
	for _, entry in plan.Claims do
		local ok, summary = claimReward(player, state.id, def, cfg, entry.Track, entry.Tier)
		if ok then
			table.insert(summaries, summary or {})
		elseif shouldRetry(rt, `{entry.Track} tier {entry.Tier}`, player, state.id) then
			return false
		end
	end
	local chests, chestSummary = claimChests(player, state.id, cfg)
	if chests < plan.Chests and shouldRetry(rt, "the bonus chests", player, state.id) then
		return false
	end
	if chestSummary then
		table.insert(summaries, chestSummary)
	end
	if not PlayerData.IsLoaded(player) then
		return false
	end

	local history = PlayerData.Get(player, "seasonHistory")
	history[state.id] = plan.History
	PlayerData.Set(player, "seasonHistory", history)
	PlayerData.Set(player, "season", freshSeason("", false))
	rt.CloseAttempts = 0

	local rewards = flatten(summaries)
	AnalyticsService.Custom(player, events.SeasonClosed, plan.FinalTier, {
		SeasonId = state.id,
		FinalTier = plan.FinalTier,
		HasPremium = plan.History.hasPremium,
		AutoClaimed = #plan.Claims,
	})
	Network.FireClient(player, "SeasonClosed", {
		SeasonId = state.id,
		FinalTier = plan.FinalTier,
		HasPremium = plan.History.hasPremium,
		Rewards = rewards,
	})
	return true
end

-- The season (with the credit already inside it) is written first and the credit keys are cleared after, so a failure
-- between the two can only leave a credit behind, never lose one.
local function enterSeason(player, active)
	local premiumCredit = PlayerData.Peek(player, "seasonPremiumCredit") == true
	local tierCredit = PlayerData.Peek(player, "seasonTierCredit") or 0
	local entry = Rules.EntryState(active.Id, premiumCredit, tierCredit, cfgFor(active.Def))
	if not PlayerData.Set(player, "season", entry) then
		return false
	end
	if premiumCredit and not PlayerData.Set(player, "seasonPremiumCredit", false) then
		warn(`[SeasonService] Could not clear the premium credit of {player.Name} after entering {active.Id}`)
	end
	if tierCredit > 0 and not PlayerData.Set(player, "seasonTierCredit", 0) then
		warn(`[SeasonService] Could not clear the tier credit of {player.Name} after entering {active.Id}`)
	end
	return true
end

local function needsSync(player)
	local state = getState(player)
	if not state then
		return false
	end
	local id, _, endUtc = schedule()
	local active = SeasonService.GetActive()
	if active and state.id ~= active.Id then
		return true
	end
	return Rules.NeedsCloseOut(state.id, id, workspace:GetServerTimeNow(), endUtc)
end

function SeasonService.Sync(player)
	local rt = runtime[player]
	if not rt or rt.Syncing or rt.Busy or not PlayerData.IsLoaded(player) then
		return
	end
	rt.Syncing = true
	local ok, err = pcall(function()
		local id, _, endUtc = schedule()
		local state = PlayerData.Get(player, "season")
		if Rules.NeedsCloseOut(state.id, id, workspace:GetServerTimeNow(), endUtc) then
			if not closeOut(player, state, rt) then
				return
			end
			state = PlayerData.Get(player, "season")
		end
		local active = SeasonService.GetActive()
		if active and state.id ~= active.Id then
			enterSeason(player, active)
		end
		rt.Ready = true
	end)
	rt.Syncing = false
	if not ok then
		warn(`[SeasonService] Sync failed for {player.Name}: {tostring(err)}`)
	end
	-- Ready stays true only when the player's season matches (or no season runs); AddXp re-checks anyway.
	if player.Parent == Players then
		refresh(player)
	end
end

local function setupPlayer(player)
	runtime[player] = {
		Ready = false,
		Syncing = false,
		Busy = false,
		TrickXp = 0,
		CloseAttempts = 0,
		BestCheckpoint = 0,
		Finished = false,
	}
	if not PlayerData.WaitForLoaded(player, DATA_WAIT_TIMEOUT) or player.Parent ~= Players then
		return
	end
	PlayerData.OnUpdate(player, "season", function()
		refresh(player)
	end)
	SeasonService.Sync(player)
end

-- ── Event sources ───────────────────────────────────────────────────────

local function emit(name, player, payload)
	SeasonService.Events:Fire(name, player, payload)
end

local function connectLazy(moduleName, signalName, handler)
	task.spawn(function()
		local child = script.Parent:FindFirstChild(moduleName)
		if not child then
			return
		end
		local ok, module = pcall(require, child)
		if not ok then
			warn(`[SeasonService] {moduleName} failed to load: {tostring(module)}`)
			return
		end
		local signal = type(module) == "table" and module[signalName]
		if signal then
			signal:Connect(handler)
		end -- no signal yet: that source's events stay off until its task adds it
	end)
end

ProgressService.CheckpointReached:Connect(function(player, index, tier)
	local rt = runtime[player]
	if rt and isRaceOpen then
		rt.BestCheckpoint = math.max(rt.BestCheckpoint, index)
	end
	emit("Checkpoint", player, { Index = index, Tier = tier })
	-- The finish pays Finish XP instead of Checkpoint XP.
	if index < CourseService.GetSegmentCount() then
		SeasonService.AddXp(player, "Checkpoint", xpTable.Checkpoint)
	end
end)

ProgressService.Finished:Connect(function(player, place)
	local rt = runtime[player]
	if rt and isRaceOpen then
		rt.Finished = true
	end
	emit("Finish", player, { Place = place })
	SeasonService.AddXp(player, "Finish", xpTable.Finish)
end)

DailyRewardService.Claimed:Connect(function(player)
	SeasonService.AddXp(player, "DailyReward", xpTable.DailyRewardClaim)
end)

TimedRewardService.Claimed:Connect(function(player)
	emit("Gift", player, {})
	SeasonService.AddXp(player, "TimedGift", xpTable.TimedGiftClaim)
end)

EconomyService.Awarded:Connect(function(player, amount, _source, kind)
	emit("Coins", player, { Amount = amount, Kind = kind })
end)

RoundService.StateChanged:Connect(function(stateName)
	if stateName == "Race" then
		isRaceOpen = true
		for _, rt in runtime do
			rt.TrickXp = 0
			rt.BestCheckpoint = 0
			rt.Finished = false
		end
	elseif stateName == "Results" then
		isRaceOpen = false
		-- Only players who raced count (GDD 8.4); idle players must not farm the "race N rounds" challenges.
		for player, rt in runtime do
			if Rules.DidRace(rt.BestCheckpoint, rt.Finished) then
				emit("RoundPlayed", player, {})
			end
		end
	end
end)

connectLazy("ToolService", "ToolUsed", function(player, toolId)
	emit("ToolUsed", player, { ToolId = toolId })
end)

connectLazy("SpinWheelService", "Spun", function(player)
	emit("Spin", player, {})
end)

connectLazy("TrickService", "TrickLanded", function(player, points, coins, chain)
	emit("TrickLanded", player, { Points = points, Coins = coins, Chain = chain })
	local rt = runtime[player]
	if not rt then
		return
	end
	-- The per-round cap is on base XP, so catch-up cannot push a round past it.
	local room = xpTable.TrickLandingMaxPerRound - rt.TrickXp
	local base = math.min(xpTable.TrickLanding, room)
	if base > 0 and SeasonService.AddXp(player, "Trick", base) then
		rt.TrickXp += base
	end
end)

-- ── Network ─────────────────────────────────────────────────────────────

Network.OnEvent("ClaimSeasonReward", function(player, track, tier)
	if type(track) ~= "string" or type(tier) ~= "number" then
		return
	end
	SeasonService.Claim(player, track, tier)
end, CLAIM_RATE)

Network.OnEvent("ClaimAllSeasonRewards", function(player)
	SeasonService.ClaimAll(player)
end, CLAIM_ALL_RATE)

Network.OnEvent("ClaimSeasonBonusChests", function(player)
	SeasonService.ClaimBonusChests(player)
end, CLAIM_ALL_RATE)

Network.OnInvoke("GetSeasonState", function(player)
	return SeasonService.GetSnapshot(player)
end, STATE_RATE)

-- ── Wiring ──────────────────────────────────────────────────────────────

Players.PlayerAdded:Connect(function(player)
	task.spawn(setupPlayer, player)
end)
for _, player in Players:GetPlayers() do
	task.spawn(setupPlayer, player)
end

Players.PlayerRemoving:Connect(function(player)
	runtime[player] = nil
end)

-- One loop for season changes: a flag flip, the end of the season, or a close-out that failed earlier.
task.spawn(function()
	while true do
		local ok, err = pcall(function()
			publishWorld()
			for player, rt in runtime do
				if not rt.Syncing and (not rt.Ready or needsSync(player)) then
					SeasonService.Sync(player)
				end
				refresh(player)
			end
		end)
		if not ok then
			warn(`[SeasonService] Check failed: {tostring(err)}`)
		end
		task.wait(CHECK_INTERVAL)
	end
end)

return SeasonService
