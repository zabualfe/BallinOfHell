-- StarterPickUI (client)
-- Fills the authored StarterPickUI cards from BallTable/RarityTable and wires each Pick button to
-- Onboarding.PickStarter(id). Onboarding owns when the screen opens and closes; this module only draws it.
-- Card layout: docs/UI_ELEMENTS.md. Note card.Name is the property, so the "Name" label is FindFirstChild("Name").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BallTable = require(ReplicatedStorage.Tables.BallTable)
local RarityTable = require(ReplicatedStorage.Tables.RarityTable)

local Onboarding = require(script.Parent.Onboarding)

local StarterPickUI = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local UI_NAME = "StarterPickUI"
local UI_TIMEOUT = 30 -- seconds to wait for the authored UI
local STAT_NAMES = { "Speed", "Acceleration", "Jump" }
local STAT_MAX = 10
local POP_START_SCALE = 0.8
local POP_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PRESS_FLASH_COLOR = Color3.fromRGB(255, 202, 64)
local PRESS_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PICKED_TEXT = "..."

local function warnMissing(path)
	warn(("[StarterPickUI] Missing %s.%s"):format(UI_NAME, path))
end

local function setText(parent, childName, text)
	local label = parent:FindFirstChild(childName)
	if label and label:IsA("TextLabel") then
		label.Text = text
	else
		warnMissing(parent.Name .. "." .. childName)
	end
	return label
end

local function fillStat(card, statName, value)
	local row = card:FindFirstChild(statName)
	local track = row and row:FindFirstChild("Track")
	local fill = track and track:FindFirstChild("Fill")
	if not (fill and fill:IsA("GuiObject")) then
		warnMissing(card.Name .. "." .. statName .. ".Track.Fill")
		return
	end
	fill.Size = UDim2.new(math.clamp(value / STAT_MAX, 0, 1), 0, fill.Size.Y.Scale, fill.Size.Y.Offset)
	local valueLabel = row:FindFirstChild("Value")
	if valueLabel and valueLabel:IsA("TextLabel") then
		valueLabel.Text = tostring(value)
	end
end

local function setupCard(card)
	local ballId = card:GetAttribute("BallId") or card.Name
	local ball = BallTable[ballId]
	if not ball then
		warn(("[StarterPickUI] %s has no BallTable entry %q"):format(card:GetFullName(), tostring(ballId)))
		return
	end

	setText(card, "Name", string.upper(ball.Name))
	setText(card, "Identity", ball.Identity or "")
	local rarityLabel = setText(card, "Rarity", string.upper(ball.Rarity))
	local rarity = RarityTable[ball.Rarity]
	if rarityLabel and rarity then
		rarityLabel.TextColor3 = rarity.Color
	end
	for _, statName in STAT_NAMES do
		fillStat(card, statName, ball[statName] or 0)
	end

	local pick = card:FindFirstChild("Pick")
	if not (pick and pick:IsA("TextButton")) then
		warnMissing(card.Name .. ".Pick")
		return
	end
	local restColor = pick.BackgroundColor3
	local restText = pick.Text
	pick.Activated:Connect(function()
		if not Onboarding.PickStarter(ballId) then
			return
		end
		pick.BackgroundColor3 = PRESS_FLASH_COLOR
		pick.Text = PICKED_TEXT
		TweenService:Create(pick, PRESS_TWEEN, { BackgroundColor3 = restColor }):Play()
		task.delay(PRESS_TWEEN.Time, function()
			if pick.Parent and pick.Text == PICKED_TEXT then
				pick.Text = restText
			end
		end)
	end)
end

local function setup(screenGui)
	local cards = screenGui:FindFirstChild("Cards")
	if not (cards and cards:IsA("GuiObject")) then
		warnMissing("Cards")
		return
	end
	for _, card in cards:GetChildren() do
		if card:IsA("Frame") then
			setupCard(card)
		end
	end

	local popScale = cards:FindFirstChildOfClass("UIScale")
	local function popIn()
		if not (popScale and screenGui.Enabled) then
			return
		end
		popScale.Scale = POP_START_SCALE
		TweenService:Create(popScale, POP_TWEEN, { Scale = 1 }):Play()
	end
	screenGui:GetPropertyChangedSignal("Enabled"):Connect(popIn)
	popIn()
end

task.spawn(function()
	local found = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild(UI_NAME, UI_TIMEOUT)
	if found and found:IsA("ScreenGui") then
		setup(found)
	end
end)

return StarterPickUI
