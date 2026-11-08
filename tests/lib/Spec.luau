-- Tiny describe/it/expect framework. Each spec file gets a fresh Collector.
local Spec = {}

local function deepEqual(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local Expectation = {}
Expectation.__index = Expectation

function Expectation:equal(expected)
	if not deepEqual(self._value, expected) then
		error(("expected %s to equal %s"):format(tostring(self._value), tostring(expected)), 2)
	end
end

function Expectation:near(expected, epsilon)
	if type(self._value) ~= "number" or math.abs(self._value - expected) > epsilon then
		error(
			("expected %s to be within %s of %s"):format(tostring(self._value), tostring(epsilon), tostring(expected)),
			2
		)
	end
end

function Expectation:truthy()
	if not self._value then
		error(("expected %s to be truthy"):format(tostring(self._value)), 2)
	end
end

function Expectation:falsy()
	if self._value then
		error(("expected %s to be falsy"):format(tostring(self._value)), 2)
	end
end

-- expect(fn):throws() or expect(fn):throws("substring")
function Expectation:throws(substring)
	local ok, err = pcall(self._value)
	if ok then
		error("expected function to throw", 2)
	end
	if substring and not tostring(err):find(substring, 1, true) then
		error(("expected error containing %q, got %q"):format(substring, tostring(err)), 2)
	end
end

function Spec.expect(value)
	return setmetatable({ _value = value }, Expectation)
end

-- Returns describe, it, and a results table filled as tests run.
function Spec.new()
	local results = { Passed = 0, Failed = {} }
	local stack = {}

	local function describe(name, fn)
		table.insert(stack, name)
		fn()
		table.remove(stack)
	end

	local function it(name, fn)
		local fullName = table.concat(stack, " > ") .. " > " .. name
		local ok, err = pcall(fn)
		if ok then
			results.Passed += 1
		else
			table.insert(results.Failed, { Name = fullName, Error = tostring(err) })
		end
	end

	return describe, it, results
end

return Spec
