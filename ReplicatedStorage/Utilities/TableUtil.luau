-- TableUtil
-- Pure table helpers shared by server and client PlayerData.
--
-- Usage:
--   TableUtil.DeepCopy(value) -> copy                  -- tables are copied recursively, other values returned as is
--   TableUtil.DeepEqual(a, b) -> boolean
--   TableUtil.SplitPath("a.b.c") -> { "a", "b", "c" }  -- nil for an empty or non-string path
--   TableUtil.GetPath(root, path) -> value             -- numeric segments index arrays ("daily.1.progress"), string keys win
--   TableUtil.SetPath(root, path, value) -> boolean    -- creates missing tables; false if a segment is blocked

local TableUtil = {}

function TableUtil.DeepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value do
		copy[key] = TableUtil.DeepCopy(child)
	end
	return copy
end

function TableUtil.DeepEqual(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for key, value in a do
		if not TableUtil.DeepEqual(value, b[key]) then
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

function TableUtil.SplitPath(path)
	if type(path) ~= "string" or path == "" then
		return nil
	end
	local segments = string.split(path, ".")
	for _, segment in segments do
		if segment == "" then
			return nil
		end
	end
	return segments
end

-- Path segments are always strings. A numeric one addresses an array slot when the table is an array (or has that
-- numeric key already); string-keyed maps like claimedFree["3"] keep their string key, because sparse numeric
-- keys cannot be saved.
local function resolveKey(container, segment)
	if container[segment] ~= nil then
		return segment
	end
	if not string.match(segment, "^%d+$") then
		return segment
	end
	local number = tonumber(segment)
	if container[number] ~= nil or (number >= 1 and number <= #container + 1 and #container > 0) then
		return number
	end
	return segment
end

function TableUtil.GetPath(root, path)
	local segments = TableUtil.SplitPath(path)
	if not segments then
		return nil
	end
	local current = root
	for _, segment in segments do
		if type(current) ~= "table" then
			return nil
		end
		current = current[resolveKey(current, segment)]
	end
	return current
end

function TableUtil.SetPath(root, path, value)
	local segments = TableUtil.SplitPath(path)
	if type(root) ~= "table" or not segments then
		return false
	end

	-- Walk first without mutating, so a blocked path leaves root untouched.
	local current = root
	for index = 1, #segments - 1 do
		local child = current[resolveKey(current, segments[index])]
		if child == nil then
			break
		end
		if type(child) ~= "table" then
			return false
		end
		current = child
	end

	current = root
	for index = 1, #segments - 1 do
		local key = resolveKey(current, segments[index])
		local child = current[key]
		if child == nil then
			child = {}
			current[key] = child
		end
		current = child
	end
	current[resolveKey(current, segments[#segments])] = value
	return true
end

return TableUtil
