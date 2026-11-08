-- Client entry. Requires every module under ReplicatedStorage.Modules in its own thread and owns
-- character lifecycle wiring: modules export CharacterAdded(self, character) and/or
-- CharacterRemoving(self, character) instead of connecting the player's signals themselves.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MODULES_TIMEOUT = 30 -- seconds

local player = Players.LocalPlayer

local modulesFolder = ReplicatedStorage:WaitForChild("Modules", MODULES_TIMEOUT)
if not modulesFolder then
	warn(("[Loader] ReplicatedStorage.Modules not found after %d seconds"):format(MODULES_TIMEOUT))
	return
end

-- Each hook runs in its own thread so a yielding module cannot delay the others.
local function runHook(name, loaded, hookName, character)
	local hook = loaded[hookName]
	if type(hook) ~= "function" then
		return
	end
	task.spawn(function()
		local ok, err = pcall(hook, loaded, character)
		if not ok then
			warn(("[Loader] %s.%s failed: %s"):format(name, hookName, tostring(err)))
		end
	end)
end

local function wireCharacter(name, loaded)
	if type(loaded) ~= "table" then
		return
	end

	if player.Character then
		runHook(name, loaded, "CharacterAdded", player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		runHook(name, loaded, "CharacterAdded", character)
	end)
	player.CharacterRemoving:Connect(function(character)
		runHook(name, loaded, "CharacterRemoving", character)
	end)
end

for _, child in modulesFolder:GetChildren() do
	if child:IsA("ModuleScript") then
		task.spawn(function()
			local ok, result = pcall(require, child)
			if not ok then
				warn(("[Loader] %s failed: %s"):format(child.Name, tostring(result)))
				return
			end
			wireCharacter(child.Name, result)
		end)
	end
end
