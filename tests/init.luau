--# selene: allow(incorrect_standard_library_use)
-- Runner: `lune run tests` from the repo root. Runs every tests/**/*.spec.luau.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local Loader = require("./lib/Loader")
local Spec = require("./lib/Spec")

local function findSpecs(dir, found)
	local entries = fs.readDir(dir)
	table.sort(entries)
	for _, entry in entries do
		local full = dir .. "/" .. entry
		if fs.isDir(full) then
			findSpecs(full, found)
		elseif entry:find("%.spec%.luau$") then
			table.insert(found, full)
		end
	end
	return found
end

local specs = findSpecs("tests", {})
local totalPassed, totalFailed = 0, 0

for _, specPath in specs do
	local load, env = Loader.new()
	local describe, it, results = Spec.new()
	env.describe, env.it, env.expect, env.load = describe, it, Spec.expect, load

	local ok, err = pcall(function()
		luau.load(fs.readFile(specPath), { debugName = specPath, environment = env })()
	end)
	if not ok then
		table.insert(results.Failed, { Name = "(spec file)", Error = tostring(err) })
	end

	totalPassed += results.Passed
	totalFailed += #results.Failed
	print(
		("%s %s: %d passed, %d failed"):format(
			if #results.Failed == 0 then "PASS" else "FAIL",
			specPath,
			results.Passed,
			#results.Failed
		)
	)
	for _, failure in results.Failed do
		print(("  - %s\n      %s"):format(failure.Name, failure.Error))
	end
end

print(("\n%d passed, %d failed across %d spec files"):format(totalPassed, totalFailed, #specs))
if totalFailed > 0 then
	process.exit(1)
end
