-- FunnelDedupe
-- Pure funnel rules for AnalyticsService: resolve a funnel name to its definition, find a step's number,
-- and remember which (player, funnel, step, qualifier) combinations were already sent this session.
--
-- Usage:
--   local def, funnelKey = FunnelDedupe.Resolve(AnalyticsTable.Funnels, "Season_S1")
--   FunnelDedupe.StepNumber(def, "Tier5") -> 2 | nil
--   local seen = FunnelDedupe.new()
--   seen:Claim(player, "Onboarding", "Joined") -> true the first time, false afterwards
--   seen:Clear(player)

local FunnelDedupe = {}
FunnelDedupe.__index = FunnelDedupe

function FunnelDedupe.Resolve(funnels, name)
	if type(name) ~= "string" then
		return nil
	end
	if funnels[name] and not funnels[name].Prefix then
		return funnels[name], name
	end
	for key, def in funnels do
		local prefix = def.Prefix
		if prefix and #name > #prefix and string.sub(name, 1, #prefix) == prefix then
			return def, key
		end
	end
	return nil
end

function FunnelDedupe.StepNumber(def, stepName)
	return table.find(def.Steps, stepName)
end

function FunnelDedupe.new()
	return setmetatable({ _seen = {} }, FunnelDedupe)
end

function FunnelDedupe:Claim(player, funnelName, stepName, qualifier)
	local perPlayer = self._seen[player]
	if not perPlayer then
		perPlayer = {}
		self._seen[player] = perPlayer
	end
	local key = funnelName .. "|" .. stepName .. "|" .. (qualifier or "")
	if perPlayer[key] then
		return false
	end
	perPlayer[key] = true
	return true
end

function FunnelDedupe:Clear(player)
	self._seen[player] = nil
end

return FunnelDedupe
