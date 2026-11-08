-- AnalyticsService
-- One wrapper over Roblox AnalyticsService (GDD 12). Every engine call is pcall'd, so analytics can never
-- break gameplay. Names come from Tables/AnalyticsTable; callers pass those constants, never raw strings.
--
-- Usage:
--   AnalyticsService.Funnel(player, funnelName, stepName, qualifier?, customFields?) -> boolean
--       Fires each step once per player. Onboarding uses LogOnboardingFunnelStepEvent; the others
--       LogFunnelStepEvent. `qualifier` separates runs of one funnel (the product id for "Purchase").
--   AnalyticsService.Economy(player, flowType, amount, endingBalance, transactionType, itemSku, customFields?)
--       flowType is AnalyticsTable.Flow.Source / Sink; currency is Coins. Put the multiplier in customFields.
--   AnalyticsService.Custom(player, name, value?, customFields?)
--
-- Economy logging is NOT automatic. PlayerData.Changed only says "coins changed", not why, and GDD 12.2
-- needs a transaction type and sku for every flow. EconomyService (the one place that grants and charges
-- coins) must call Economy() itself with the reason.
--
-- Dedupe: session-only. "Once ever" onboarding steps (AnalyticsTable OnceEver) would need a saved key, and
-- DataTemplate has none that fits, so a returning player re-fires them each session. See task follow-ups.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RobloxAnalytics = game:GetService("AnalyticsService")

local AnalyticsTable = require(ReplicatedStorage.Tables.AnalyticsTable)
local FunnelDedupe = require(script.FunnelDedupe)

local AnalyticsService = {}

local seen = FunnelDedupe.new()
local joinStamps = {} -- [player] = os.time() at first use, part of the funnel session id

local function stringifyFields(fields)
	if type(fields) ~= "table" then
		return nil
	end
	local out = {}
	for key, value in fields do
		out[tostring(key)] = tostring(value)
	end
	return out
end

local function sessionId(player, qualifier)
	if not joinStamps[player] then
		joinStamps[player] = os.time()
	end
	return ("%d_%d_%s"):format(player.UserId, joinStamps[player], qualifier or "")
end

function AnalyticsService.Funnel(player, funnelName, stepName, qualifier, customFields)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or not player.Parent then
		return false
	end
	local def = FunnelDedupe.Resolve(AnalyticsTable.Funnels, funnelName)
	local stepNumber = def and FunnelDedupe.StepNumber(def, stepName)
	if not stepNumber then
		warn(("[AnalyticsService] Unknown funnel step %s / %s"):format(tostring(funnelName), tostring(stepName)))
		return false
	end
	if def.Qualified and type(qualifier) ~= "string" then
		warn(("[AnalyticsService] Funnel %s needs a qualifier"):format(funnelName))
		return false
	end
	if not seen:Claim(player, funnelName, stepName, qualifier) then
		return false
	end

	local fields = stringifyFields(customFields)
	local ok, err = pcall(function()
		if def.Type == "Onboarding" then
			RobloxAnalytics:LogOnboardingFunnelStepEvent(player, stepNumber, stepName, fields)
		else
			RobloxAnalytics:LogFunnelStepEvent(
				player,
				funnelName,
				sessionId(player, qualifier),
				stepNumber,
				stepName,
				fields
			)
		end
	end)
	if not ok then
		warn(("[AnalyticsService] Funnel %s/%s failed: %s"):format(funnelName, stepName, tostring(err)))
	end
	return ok
end

function AnalyticsService.Economy(player, flowType, amount, endingBalance, transactionType, itemSku, customFields)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end
	if flowType ~= AnalyticsTable.Flow.Source and flowType ~= AnalyticsTable.Flow.Sink then
		warn("[AnalyticsService] Economy flowType must be Source or Sink, got " .. tostring(flowType))
		return false
	end
	if
		type(amount) ~= "number"
		or amount <= 0
		or type(endingBalance) ~= "number"
		or type(transactionType) ~= "string"
	then
		warn("[AnalyticsService] Economy called with invalid arguments")
		return false
	end

	local ok, err = pcall(function()
		RobloxAnalytics:LogEconomyEvent(
			player,
			Enum.AnalyticsEconomyFlowType[flowType],
			AnalyticsTable.Currency,
			endingBalance,
			amount,
			transactionType,
			itemSku,
			stringifyFields(customFields)
		)
	end)
	if not ok then
		warn(("[AnalyticsService] Economy %s failed: %s"):format(tostring(transactionType), tostring(err)))
	end
	return ok
end

function AnalyticsService.Custom(player, name, value, customFields)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or type(name) ~= "string" then
		return false
	end
	local ok, err = pcall(function()
		RobloxAnalytics:LogCustomEvent(player, name, value, stringifyFields(customFields))
	end)
	if not ok then
		warn(("[AnalyticsService] Custom %s failed: %s"):format(name, tostring(err)))
	end
	return ok
end

Players.PlayerRemoving:Connect(function(player)
	seen:Clear(player)
	joinStamps[player] = nil
end)

return AnalyticsService
