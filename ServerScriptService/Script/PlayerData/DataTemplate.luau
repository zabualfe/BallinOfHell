-- DataTemplate
-- Every saved key with a safe default. PlayerData reconciles missing keys from this on load, so adding a key
-- here is the migration. Renaming or removing a key needs the Director's OK (AGENTS.md "Player data").
-- Tables keyed by number cannot be stored when sparse, so id-keyed tables use string keys.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ToolTable = require(ReplicatedStorage.Tables.ToolTable)
local TrickTable = require(ReplicatedStorage.Tables.TrickTable)

local STARTER_TOOL_CHARGES = 3 -- GDD 6.4 / FTUE: new players hold 3 charges of the slot-1 default tool

local starterTools = table.clone(ToolTable.Config.DefaultEquipped)
local starterCharges = {}
local slotOneTool = starterTools[1]
if slotOneTool and ToolTable.Tools[slotOneTool] then
	starterCharges[slotOneTool] = STARTER_TOOL_CHARGES
else
	warn("[DataTemplate] ToolTable.Config.DefaultEquipped[1] is not a known tool; no starter charges granted")
end

local DataTemplate = {
	coins = 0, -- spendable currency
	wins = 0, -- finished races
	bestTime = 0, -- fastest finish in seconds, 0 = none yet
	ownedBalls = {}, -- [ballId] = { at = time, serial = n? }
	equippedBall = "", -- ballId, "" until the starter pick
	hasPickedStarter = false, -- starter ball chosen
	firstJoinAt = 0, -- server time of the first ever join, set once on load
	sessionCount = 0, -- joins so far, incremented on load
	firstFallGiftClaimed = false, -- first-fall present taken
	dailyStreak = 0, -- consecutive daily claims
	lastDailyClaimDay = -1, -- UTC day number of the last claim, -1 = never
	timedRewardsEverClaimed = {}, -- [rewardId] = true, one-off exclusives only
	spins = 0, -- unspent wheel spins
	lastFreeSpinAt = 0, -- server time of the last free spin
	lastVipSpinDay = -1, -- UTC day number of the last VIP daily spin, -1 = never
	starterPackBought = false, -- starter pack purchased
	boosts = {}, -- [boostId] = remaining seconds (timers pause offline)
	settings = {
		doubleJump = true, -- double jump enabled
		sound = true, -- sound enabled
		otherBallVfx = true, -- show other players' ball effects
		showTricks = true, -- show trick popups
	},
	purchaseLog = {}, -- recent PurchaseIds for idempotent receipts
	stats = {
		falls = 0, -- total falls
		segmentsCleared = 0, -- total segments cleared
		robuxSpent = 0, -- lifetime Robux spent
		tricksLanded = 0, -- total tricks landed
		bestTrickPoints = 0, -- best single-airtime trick score
	},

	ownedTools = {}, -- [toolId] = true, permanent unlocks
	toolCharges = starterCharges, -- [toolId] = stored charges (cap in ToolTable.Config.ChargeCap)
	equippedTools = starterTools, -- tool ids per slot, "" = empty
	skipTokens = 0, -- segment skip tokens

	ownedTrails = {}, -- [trailId] = true, cosmetic trails granted by rewards (RewardService)
	ownedTitles = {}, -- [titleId] = true, titles granted by rewards (RewardService)

	ownedTricks = {}, -- [trickId] = true, free tricks are implicit
	equippedTricks = table.clone(TrickTable.Loadout.Default), -- trick ids per slot, "" = empty
	trickLevels = {}, -- [trickId] = 1..3, missing = 1

	season = {
		id = "", -- active season id this progress belongs to
		xp = 0, -- season XP
		claimedFree = {}, -- ["tier"] = true, free track claims
		claimedPremium = {}, -- ["tier"] = true, premium track claims
		hasPremium = false, -- premium pass owned this season
		bonusChests = 0, -- bonus chests claimed after the last tier
	},
	seasonHistory = {}, -- [seasonId] = { tier = n, hasPremium = bool }
	seasonPremiumCredit = false, -- credit toward the next premium pass
	seasonTierCredit = 0, -- tiers bought while no season ran, applied as XP when the next season is entered
	challenges = {
		day = -1, -- UTC day number of the current daily set
		daily = {}, -- { { id, progress, done } } for the day
		week = -1, -- week number of the current weekly set
		weekly = {}, -- { { id, progress, done } } for the week
		rerollsUsed = 0, -- rerolls spent today
		rerollSeed = 0, -- seed of the latest daily reroll (0 = none today)
	},
}

return DataTemplate
