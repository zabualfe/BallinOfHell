-- TargetStore
-- Server-side pending targets for purchases that act on something specific (AGENTS.md "Networking"). One entry
-- per player: the product key it was stored for and the target. A newer prompt replaces the older one.
--
-- Usage:
--   local store = TargetStore.new()
--   store:Set(player, key, target)
--   store:Get(player, key) -> target?          -- nil when missing or stored for another product
--   store:Clear(player, key?)                  -- with key: only if the entry belongs to that product
--   store:Abandon(player, key, wasPurchased) -> boolean   -- PromptProductPurchaseFinished: clears only when not bought
-- A bought prompt is left alone on purpose: the receipt may arrive after the finished event and still needs it.

local TargetStore = {}
TargetStore.__index = TargetStore

function TargetStore.new()
	return setmetatable({ _entries = setmetatable({}, { __mode = "k" }) }, TargetStore)
end

function TargetStore:Set(player, key, target)
	self._entries[player] = { Key = key, Target = target }
end

function TargetStore:Get(player, key)
	local entry = self._entries[player]
	if entry == nil or entry.Key ~= key then
		return nil
	end
	return entry.Target
end

function TargetStore:Clear(player, key)
	local entry = self._entries[player]
	if entry == nil or (key ~= nil and entry.Key ~= key) then
		return false
	end
	self._entries[player] = nil
	return true
end

function TargetStore:Abandon(player, key, wasPurchased)
	if wasPurchased then
		return false
	end
	return self:Clear(player, key)
end

return TargetStore
