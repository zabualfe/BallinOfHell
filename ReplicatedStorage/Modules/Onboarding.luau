-- Onboarding (client)
-- Thin bridge between the starter-pick UI and the server. Once data loads and hasPickedStarter is false, it
-- finds the authored ScreenGui `StarterPickUI` (StarterGui, cloned to PlayerGui) and enables it. The UI only
-- has to call Onboarding.PickStarter(ballId).
--
-- Expected authored UI (ARCHITECTURE: 3 cards with stat bars), all inside StarterPickUI:
--   Cards       Frame      -- one child Frame per starter ball, named by ball id (sprinter, grip, bouncer)
--   <card>.Name, .Identity TextLabels; .Speed/.Acceleration/.Jump bar Frames; .Pick TextButton -> PickStarter(id)
-- Server answers with StarterPicked(ballId); the UI is then disabled.
--
-- Usage:
--   Onboarding.PickStarter(ballId) -> boolean   -- false when debounced or already picked

local Players = game:GetService("Players")

local Network = require(script.Parent.Parent.Network)
local PlayerData = require(script.Parent.PlayerData)

local Onboarding = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local UI_NAME = "StarterPickUI"
local UI_TIMEOUT = 15 -- seconds to wait for the authored UI
local PICK_DEBOUNCE = 1 -- seconds between PickStarter messages

local lastPickAt = -math.huge
local hasPicked = false
local screenGui = nil

local function setUiVisible(isVisible)
	if screenGui then
		screenGui.Enabled = isVisible
	end
end

function Onboarding.PickStarter(ballId)
	if hasPicked or type(ballId) ~= "string" then
		return false
	end
	local now = os.clock()
	if now - lastPickAt < PICK_DEBOUNCE then
		return false
	end
	lastPickAt = now
	Network.FireServer("PickStarter", ballId)
	return true
end

Network.OnEvent("StarterPicked", function()
	hasPicked = true
	setUiVisible(false)
end)

task.spawn(function()
	PlayerData.WaitForLoaded()
	local alreadyPicked = PlayerData.Get("hasPickedStarter")
	if alreadyPicked then
		hasPicked = true
	end

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local found = playerGui:WaitForChild(UI_NAME, UI_TIMEOUT)
	if not found or not found:IsA("ScreenGui") then
		-- Returning players never need the UI, so a missing one is only worth a warning for new players.
		if not alreadyPicked then
			warn(
				("[Onboarding] Expected ScreenGui %s at StarterGui.%s; the starter pick cannot be shown"):format(
					UI_NAME,
					UI_NAME
				)
			)
		end
		return
	end
	screenGui = found
	-- An authored Enabled=true GUI would otherwise stay open for returning players.
	setUiVisible(not hasPicked)
end)

return Onboarding
