-- ModifierStack
-- Pure "several sources each want a multiplier" bookkeeping, so one source ending never cancels another
-- (a Rocket ending must not wipe an overlapping BoostPanel boost). BallController keeps one stack for speed (the
-- largest wins, matching the server speed audit) and one for gravity (they multiply, GDD 6.6).
--
--   ModifierStack.New() -> stack
--   ModifierStack.Set(stack, source, value) -> boolean   -- value must be a finite number > 0; replaces that source's entry
--   ModifierStack.Clear(stack, source)
--   ModifierStack.Reset(stack)
--   ModifierStack.Max(stack) -> number       -- 1 when empty
--   ModifierStack.Product(stack) -> number   -- 1 when empty

local ModifierStack = {}

function ModifierStack.New()
	return {}
end

function ModifierStack.Set(stack, source, value)
	if source == nil or type(value) ~= "number" or value ~= value or value <= 0 or value == math.huge then
		return false
	end
	stack[source] = value
	return true
end

function ModifierStack.Clear(stack, source)
	stack[source] = nil
end

function ModifierStack.Reset(stack)
	table.clear(stack)
end

function ModifierStack.Max(stack)
	local best = nil
	for _, value in stack do
		if best == nil or value > best then
			best = value
		end
	end
	return best or 1
end

function ModifierStack.Product(stack)
	local product = 1
	for _, value in stack do
		product *= value
	end
	return product
end

return ModifierStack
