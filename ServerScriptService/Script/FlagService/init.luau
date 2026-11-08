-- FlagService
-- Remote-config feature flags and A/B tests (AGENTS.md "Experiments and feature flags"). Owns loading
-- Roblox remote config, safe defaults, per-flag change signals and the client-visible flag attributes.
--
-- Usage:
--   FlagService.Get(key) -> value                  -- Default until config loads, on failure, or if Disabled
--   FlagService.Changed(key) -> Signal             -- fires (new, old) when the resolved value changes
--   FlagService.GetVariant(player, testKey) -> variantName   -- stable per UserId, from the test's Variants weights
--   FlagService.GetState(player, testKey) -> variantName, state   -- state = States[variant], called if a function
--   FlagService.IsLoaded() -> boolean, FlagService.WaitForLoaded(timeout) -> boolean
--
-- Contract: every module in FlagService/Flags returns a flag definition or a list of them; see Resolve.luau
-- for the fields. Flags marked ClientVisible = true are mirrored as attributes on ReplicatedStorage.Flags.
-- Every flag works with no remote config at all: Get returns Default.

local ConfigService = game:GetService("ConfigService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Utilities.Signal)
local Resolve = require(script.Resolve)

local FlagService = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local RETRY_BASE_SECONDS = 2
local RETRY_CAP_SECONDS = 60
local MAX_ATTEMPTS = 10
local POLL_SECONDS = 600 -- fallback refresh when the config object has no update event
local FLAGS_FOLDER_NAME = "Flags"

local definitions = {} -- [key] = definition
local values = {} -- [key] = resolved value
local signals = {} -- [key] = Signal
local hasLoaded = false
local loadedSignal = Signal.new()
local flagsFolder -- Configuration under ReplicatedStorage, created when a flag is ClientVisible

-- ── Registry ────────────────────────────────────────────────────────────

local function isReplicable(value)
	local kind = type(value)
	return kind == "boolean" or kind == "number" or kind == "string"
end

local function publish(def, value)
	if not def.ClientVisible then
		return
	end
	if not isReplicable(value) then
		warn(("[FlagService] %s is ClientVisible but its value is not a bool, number or string"):format(def.Key))
		return
	end
	if not flagsFolder then
		flagsFolder = Instance.new("Configuration")
		flagsFolder.Name = FLAGS_FOLDER_NAME
		flagsFolder.Parent = ReplicatedStorage
	end
	flagsFolder:SetAttribute(def.Key, value)
end

local function register(def, source)
	local ok, err = Resolve.Validate(def)
	if not ok then
		warn(("[FlagService] %s: %s"):format(source, err))
		return
	end
	if definitions[def.Key] then
		warn(("[FlagService] %s: duplicate flag key %s ignored"):format(source, def.Key))
		return
	end
	definitions[def.Key] = def
	values[def.Key] = def.Default
	publish(def, def.Default)
end

local function loadDefinitions()
	local folder = script:FindFirstChild("Flags")
	if not folder then
		warn("[FlagService] Missing folder " .. script:GetFullName() .. ".Flags")
		return
	end
	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") then
			local ok, result = pcall(require, child)
			if not ok then
				warn(("[FlagService] %s failed to load: %s"):format(child.Name, tostring(result)))
			elseif type(result) == "table" and result.Key ~= nil then
				register(result, child.Name)
			elseif type(result) == "table" then
				for _, def in result do
					register(def, child.Name)
				end
			else
				warn(("[FlagService] %s must return a flag definition or a list of them"):format(child.Name))
			end
		end
	end
end

-- ── Remote config ───────────────────────────────────────────────────────

local function setValue(key, newValue)
	local oldValue = values[key]
	if oldValue == newValue then
		return
	end
	values[key] = newValue
	publish(definitions[key], newValue)
	local signal = signals[key]
	if signal then
		signal:Fire(newValue, oldValue)
	end
end

local function applyConfig(config)
	for key, def in definitions do
		local ok, remote = pcall(config.GetValue, config, key)
		setValue(key, Resolve.Value(def, ok and remote or nil))
	end
end

local function fetchConfig()
	local ok, config = pcall(function()
		return ConfigService:GetConfigAsync()
	end)
	if ok and config then
		return config
	end
	return nil, config
end

local function listenForUpdates(config)
	local hasEvent, updateSignal = pcall(function()
		return config.UpdateAvailable
	end)
	if not hasEvent or typeof(updateSignal) ~= "RBXScriptSignal" then
		task.spawn(function()
			while true do
				task.wait(POLL_SECONDS)
				local fresh = fetchConfig()
				if fresh then
					applyConfig(fresh)
				end
			end
		end)
		return
	end

	updateSignal:Connect(function()
		local refreshed = pcall(function()
			config:Refresh()
		end)
		if refreshed then
			applyConfig(config)
		end
	end)
end

local function loadRemote()
	for attempt = 1, MAX_ATTEMPTS do
		local config, err = fetchConfig()
		if config then
			applyConfig(config)
			hasLoaded = true
			loadedSignal:Fire()
			listenForUpdates(config)
			return
		end
		warn(("[FlagService] Remote config attempt %d/%d failed: %s"):format(attempt, MAX_ATTEMPTS, tostring(err)))
		task.wait(Resolve.Backoff(attempt, RETRY_BASE_SECONDS, RETRY_CAP_SECONDS))
	end
	warn("[FlagService] Remote config never loaded; running on flag defaults")
end

-- ── Public API ──────────────────────────────────────────────────────────

function FlagService.Get(key)
	local value = values[key]
	if value == nil then
		warn("[FlagService] Unknown flag " .. tostring(key))
	end
	return value
end

function FlagService.Changed(key)
	if not definitions[key] then
		warn("[FlagService] Changed requested for unknown flag " .. tostring(key))
	end
	local signal = signals[key]
	if not signal then
		signal = Signal.new()
		signals[key] = signal
	end
	return signal
end

function FlagService.GetVariant(player, testKey)
	local def = definitions[testKey]
	if not def or not def.Variants then
		warn("[FlagService] Unknown A/B test " .. tostring(testKey))
		return nil
	end
	return Resolve.Variant(def, player.UserId, values[testKey])
end

function FlagService.GetState(player, testKey)
	local variant = FlagService.GetVariant(player, testKey)
	if not variant then
		return nil, nil
	end
	local state = definitions[testKey].States and definitions[testKey].States[variant]
	if type(state) == "function" then
		local ok, result = pcall(state, player)
		if not ok then
			warn(("[FlagService] State handler for %s/%s failed: %s"):format(testKey, variant, tostring(result)))
			return variant, nil
		end
		return variant, result
	end
	return variant, state
end

function FlagService.IsLoaded()
	return hasLoaded
end

function FlagService.WaitForLoaded(timeout)
	if hasLoaded then
		return true
	end
	local waiting = coroutine.running()
	local done = false
	local connection = loadedSignal:Connect(function()
		if not done then
			done = true
			task.spawn(waiting)
		end
	end)
	task.delay(timeout or 10, function()
		if not done then
			done = true
			task.spawn(waiting)
		end
	end)
	coroutine.yield()
	connection:Disconnect()
	return hasLoaded
end

loadDefinitions()
task.spawn(loadRemote)

return FlagService
