--# selene: allow(incorrect_standard_library_use)
-- Filesystem-backed fake Roblox tree plus a module loader (see tests/README.md).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local Stubs = require("./Stubs")

local Loader = {}

local ROOT = process.cwd
local SERVICE_FOLDERS = {
	"ReplicatedFirst",
	"ReplicatedStorage",
	"ServerScriptService",
	"ServerStorage",
	"StarterPlayer",
}

-- ── Fake Instances ──────────────────────────────────────────────────────
local Node = {}
local data = setmetatable({}, { __mode = "k" }) -- node -> { Name, ClassName, Path, SourcePath, Parent, Children }

local function newNode(name, className, path, sourcePath, parent)
	local node = setmetatable({}, Node)
	data[node] = { Name = name, ClassName = className, Path = path, SourcePath = sourcePath, Parent = parent }
	return node
end

local function stripExtension(fileName)
	for _, suffix in { ".server.luau", ".client.luau", ".luau" } do
		if fileName:sub(-#suffix) == suffix then
			local className = if suffix == ".server.luau"
				then "Script"
				elseif suffix == ".client.luau" then "LocalScript"
				else "ModuleScript"
			return fileName:sub(1, -#suffix - 1), className
		end
	end
	return nil
end

local function findInit(dirPath)
	for _, fileName in { "init.luau", "init.server.luau", "init.client.luau" } do
		if fs.isFile(dirPath .. "/" .. fileName) then
			local _, className = stripExtension(fileName)
			return dirPath .. "/" .. fileName, className
		end
	end
	return nil
end

local function children(node)
	local info = data[node]
	if info.Children then
		return info.Children
	end
	local list = {}
	info.Children = list
	if info.Path and fs.isDir(info.Path) then
		local entries = fs.readDir(info.Path)
		table.sort(entries)
		for _, entry in entries do
			local full = info.Path .. "/" .. entry
			if fs.isDir(full) then
				local initPath, className = findInit(full)
				table.insert(list, newNode(entry, className or "Folder", full, initPath, node))
			else
				local name, className = stripExtension(entry)
				if name and not entry:find("^init%.") and not entry:find("%.spec%.luau$") then
					table.insert(list, newNode(name, className, nil, full, node))
				end
			end
		end
	end
	return list
end

local methods = {}

function methods.GetChildren(self)
	return table.clone(children(self))
end

function methods.FindFirstChild(self, name)
	for _, child in children(self) do
		if data[child].Name == name then
			return child
		end
	end
	return nil
end

function methods.WaitForChild(self, name)
	local child = methods.FindFirstChild(self, name)
	if not child then
		error(
			("[tests] WaitForChild: %s has no child %q (would hang in Roblox)"):format(methods.GetFullName(self), name)
		)
	end
	return child
end

function methods.GetDescendants(self)
	local result = {}
	for _, child in children(self) do
		table.insert(result, child)
		for _, descendant in methods.GetDescendants(child) do
			table.insert(result, descendant)
		end
	end
	return result
end

function methods.IsA(self, className)
	local own = data[self].ClassName
	return own == className
		or className == "Instance"
		or (className == "LuaSourceContainer" and (own == "ModuleScript" or own == "Script" or own == "LocalScript"))
		or (className == "BaseScript" and (own == "Script" or own == "LocalScript"))
end

function methods.GetFullName(self)
	local info = data[self]
	if not info.Parent then
		return info.Name
	end
	return methods.GetFullName(info.Parent) .. "." .. info.Name
end

function Node.__index(self, key)
	local info = data[self]
	if key == "Name" or key == "ClassName" or key == "Parent" then
		return info[key]
	end
	if methods[key] then
		return methods[key]
	end
	local child = methods.FindFirstChild(self, key)
	if child then
		return child
	end
	error(("[tests] %s is not a valid member of %s %q"):format(tostring(key), info.ClassName, info.Name), 2)
end

function Node.__newindex(_, key)
	error(("[tests] cannot assign %s on a fake Instance"):format(tostring(key)), 2)
end

function Node.__tostring(self)
	return data[self].Name
end

-- ── Loader ──────────────────────────────────────────────────────────────
-- Returns load(repoPath), plus the shared env (so specs get the same globals) and a service setter.
function Loader.new()
	local env, services, getService = Stubs.new()

	local game = { Name = "Game" }
	local serviceNodes = {}
	for _, name in SERVICE_FOLDERS do
		local path = ROOT .. "/" .. name
		serviceNodes[name] = newNode(name, name, if fs.isDir(path) then path else nil, nil, nil)
	end

	-- fs calls yield and cannot run inside the __index metamethod, so build every child list up front.
	for _, node in serviceNodes do
		methods.GetDescendants(node)
	end

	function game:GetService(name)
		return serviceNodes[name] or getService(name) or error(("[tests] no fake service %q"):format(name), 2)
	end
	function game:SetService(name, value)
		services[name] = value
	end
	env.game = game

	local cache = {}
	local requireModule

	local function run(node)
		local info = data[node]
		local sourcePath = info.SourcePath
		if not sourcePath then
			error(("[tests] %s has no source file to require"):format(methods.GetFullName(node)), 3)
		end
		if info.ClassName ~= "ModuleScript" then
			error(("[tests] cannot require a %s: %s"):format(info.ClassName, methods.GetFullName(node)), 3)
		end
		if cache[node] ~= nil then
			return cache[node].value
		end

		local moduleEnv = table.clone(env)
		moduleEnv.script = node
		moduleEnv.require = requireModule
		local chunk = luau.load(fs.readFile(sourcePath), {
			debugName = sourcePath,
			environment = moduleEnv,
		})
		local value = chunk()
		cache[node] = { value = value }
		return value
	end

	requireModule = function(node)
		if getmetatable(node) ~= Node then
			error("[tests] require expects a fake Instance (e.g. script.Parent.X)", 2)
		end
		return run(node)
	end

	-- load("ReplicatedStorage/Utilities/Weighted") -> the module's return value.
	local function load(repoPath)
		local node
		local current
		for segment in repoPath:gmatch("[^/]+") do
			if not current then
				current = serviceNodes[segment]
				if not current then
					error(("[tests] load: %q is not a service folder (%s)"):format(segment, repoPath), 2)
				end
			else
				current = methods.FindFirstChild(current, segment)
				if not current then
					error(("[tests] load: %q not found while resolving %s"):format(segment, repoPath), 2)
				end
			end
			node = current
		end
		return requireModule(node)
	end

	env.require = requireModule
	return load, env
end

return Loader
