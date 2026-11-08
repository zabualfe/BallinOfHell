-- HUD (client)
-- Drives the authored StarterGui.HUD from replicated state. It owns no game state and decides nothing.
-- Sources: PlayerData "coins"; workspace attributes RoundState / RoundTimeLeft / RoundMultiplier / StepEndsAt; player
-- attributes Checkpoint, SeasonXp, SeasonTier, SeasonClaimable, StarterPackEndsAt, DailyAvailable; ToolController
-- (GetSlots, StateChanged, Use); TrickController.Popup; Network ShowToast and PlayerFinished.
-- Element paths: docs/UI_ELEMENTS.md. A missing element warns once with its path and that part of the HUD is skipped.
-- Menu buttons (Shop, Inventory, Daily, Wheel, Season, Settings) are not connected here; their screens own them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Network = require(ReplicatedStorage.Network)
local NumberFormat = require(ReplicatedStorage.Utilities.NumberFormat)
local RichText = require(ReplicatedStorage.Utilities.RichText)
local TimeFormat = require(ReplicatedStorage.Utilities.TimeFormat)
local CourseTable = require(ReplicatedStorage.Tables.CourseTable)
local SeasonTable = require(ReplicatedStorage.Tables.SeasonTable)

local PlayerData = require(script.Parent.PlayerData)
local ToolController = require(script.Parent.ToolController)
local TrickController = require(script.Parent.TrickController)

local HUD = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local HUD_NAME = "HUD"
local HUD_TIMEOUT = 30 -- seconds to wait for the authored UI
local TICK_INTERVAL = 0.1 -- seconds between clock/cooldown refreshes
local BUMP_SCALE = 0.85
local PULSE_SCALE = 1.3
local POP_START_SCALE = 0.8
local POP_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local TOAST_SECONDS = 4
local MAX_TOASTS = 4
local TRICK_POPUP_SECONDS = 1.6
local NO_TIME_TEXT = "--:--"
local TEMP_SLOT = 0
local ROUND_RACE_STATE = "Race"
local STATE_TEXT = {
	Intermission = "Next round starting soon",
	BuildCourse = "Building the course...",
	Countdown = "Get ready!",
	Results = "Round over!",
	Teardown = "Round over!",
}
local GRADE_COLORS = {
	Clean = Color3.fromRGB(255, 202, 64),
	Sloppy = Color3.fromRGB(255, 110, 20),
	Bail = Color3.fromRGB(235, 40, 40),
}
local TIER_COUNT = SeasonTable.Config.Tiers
local XP_PER_TIER = SeasonTable.Config.XpPerTier
local SEGMENT_COUNT = CourseTable.SlotCount

local localPlayer = Players.LocalPlayer

-- ── Lookup helpers ──────────────────────────────────────────────────────
local function find(root, path, className)
	local node = root
	for _, name in string.split(path, ".") do
		node = node:FindFirstChild(name)
		if not node then
			break
		end
	end
	if not (node and node:IsA(className)) then
		warn(("[HUD] Expected %s at %s.%s"):format(className, root:GetFullName(), path))
		return nil
	end
	return node
end

-- A label has no UIScale of its own, so the bump effect adds one the first time it is needed.
local bumpScales = {}
local function bump(label, peak)
	if not label then
		return
	end
	local scale = label:FindFirstChildOfClass("UIScale") or bumpScales[label]
	if not scale then
		scale = Instance.new("UIScale")
		bumpScales[label] = scale
		scale.Parent = label
	end
	scale.Scale = peak or BUMP_SCALE
	TweenService:Create(scale, POP_TWEEN, { Scale = 1 }):Play()
end

local function ownAttribute(name, callback)
	localPlayer:GetAttributeChangedSignal(name):Connect(callback)
end

-- ── Setup ───────────────────────────────────────────────────────────────
local function setup(gui)
	local els = {
		coins = find(gui, "TopBar.Coins.CoinsLabel", "TextLabel"),
		timer = find(gui, "TopBar.Timer.TimerLabel", "TextLabel"),
		multiplier = find(gui, "TopBar.Multiplier.MultiplierLabel", "TextLabel"),
		multiplierScale = find(gui, "TopBar.Multiplier.UIScale", "UIScale"),
		progress = find(gui, "TopBar.Progress.ProgressLabel", "TextLabel"),
		goal = find(gui, "GoalLabel", "TextLabel"),
		season = find(gui, "SeasonXp", "Frame"),
		tier = find(gui, "SeasonXp.TierBadge.TierLabel", "TextLabel"),
		xpFill = find(gui, "SeasonXp.Bar.Fill", "Frame"),
		xpLabel = find(gui, "SeasonXp.XpLabel", "TextLabel"),
		starterPack = find(gui, "StarterPack", "TextButton"),
		starterPackTimer = find(gui, "StarterPack.TimerLabel", "TextLabel"),
		dailyBadge = find(gui, "Menu.Daily.Badge", "Frame"),
		dailyCount = find(gui, "Menu.Daily.Badge.CountLabel", "TextLabel"),
		seasonBadge = find(gui, "Menu.Season.Badge", "Frame"),
		seasonCount = find(gui, "Menu.Season.Badge.CountLabel", "TextLabel"),
		trick = find(gui, "TrickPopup", "Frame"),
		trickScale = find(gui, "TrickPopup.UIScale", "UIScale"),
		trickName = find(gui, "TrickPopup.TrickLabel", "TextLabel"),
		trickChain = find(gui, "TrickPopup.ChainLabel", "TextLabel"),
		trickResult = find(gui, "TrickPopup.ResultLabel", "TextLabel"),
		trickMax = find(gui, "TrickPopup.MaxTag", "TextLabel"),
		trickMixed = find(gui, "TrickPopup.MixedLabel", "TextLabel"),
		toasts = find(gui, "Toasts", "Frame"),
		toastTemplate = find(gui, "Templates.Toast", "Frame"),
	}

	-- ── Coins ───────────────────────────────────────────────────────────
	local function showCoins(isChange)
		if not els.coins then
			return
		end
		els.coins.Text = NumberFormat.Commas(PlayerData.Peek("coins") or 0)
		if isChange then
			bump(els.coins)
		end
	end
	PlayerData.OnUpdate("coins", function()
		showCoins(true)
	end)
	task.spawn(function()
		PlayerData.WaitForLoaded()
		showCoins(false)
	end)

	-- ── Round ───────────────────────────────────────────────────────────
	local lastMultiplier = nil
	local function showMultiplier()
		local value = workspace:GetAttribute("RoundMultiplier") or 1
		if els.multiplier then
			els.multiplier.Text = ("×%g"):format(value)
		end
		if lastMultiplier and value > lastMultiplier and els.multiplierScale then
			els.multiplierScale.Scale = PULSE_SCALE
			TweenService:Create(els.multiplierScale, POP_TWEEN, { Scale = 1 }):Play()
		end
		lastMultiplier = value
	end

	local function showProgress()
		local checkpoint = localPlayer:GetAttribute("Checkpoint") or 0
		if els.progress then
			els.progress.Text = ("%d / %d"):format(checkpoint, SEGMENT_COUNT)
		end
		if els.goal and workspace:GetAttribute("RoundState") == ROUND_RACE_STATE then
			els.goal.Text = ("Reach segment %s"):format(RichText.Bold(math.min(checkpoint + 1, SEGMENT_COUNT)))
		end
	end

	local function showRoundState()
		local state = workspace:GetAttribute("RoundState")
		if els.goal then
			if state == ROUND_RACE_STATE then
				showProgress()
			else
				els.goal.Text = STATE_TEXT[state] or ""
			end
		end
	end

	local function showTimer()
		if not els.timer then
			return
		end
		local state = workspace:GetAttribute("RoundState")
		local seconds = nil
		if state == ROUND_RACE_STATE then
			seconds = workspace:GetAttribute("RoundTimeLeft")
		else
			local endsAt = workspace:GetAttribute("StepEndsAt")
			seconds = endsAt and endsAt - workspace:GetServerTimeNow()
		end
		els.timer.Text = if seconds then TimeFormat.Clock(math.ceil(seconds), true) else NO_TIME_TEXT
	end

	workspace:GetAttributeChangedSignal("RoundMultiplier"):Connect(showMultiplier)
	workspace:GetAttributeChangedSignal("RoundState"):Connect(showRoundState)
	ownAttribute("Checkpoint", showProgress)
	showMultiplier()
	showProgress()
	showRoundState()

	-- ── Season XP ───────────────────────────────────────────────────────
	-- Hidden until the first round ends (GDD 10.1), or at once for a player who already has XP.
	local isSeasonUnlocked = false
	local function showSeason()
		local xp = localPlayer:GetAttribute("SeasonXp") or 0
		local tier = localPlayer:GetAttribute("SeasonTier") or 0
		isSeasonUnlocked = isSeasonUnlocked or xp > 0
		if els.season then
			els.season.Visible = isSeasonUnlocked
		end
		local isMaxed = tier >= TIER_COUNT
		local inTier = if isMaxed then XP_PER_TIER else xp - tier * XP_PER_TIER
		if els.tier then
			els.tier.Text = tostring(tier)
		end
		if els.xpFill then
			els.xpFill.Size =
				UDim2.new(math.clamp(inTier / XP_PER_TIER, 0, 1), 0, els.xpFill.Size.Y.Scale, els.xpFill.Size.Y.Offset)
		end
		if els.xpLabel then
			els.xpLabel.Text = if isMaxed then "MAX" else ("%d / %d"):format(inTier, XP_PER_TIER)
		end
	end
	ownAttribute("SeasonXp", showSeason)
	ownAttribute("SeasonTier", showSeason)
	Network.OnEvent("RoundResults", function()
		isSeasonUnlocked = true
		showSeason()
	end)
	showSeason()

	-- ── Badges ──────────────────────────────────────────────────────────
	local function showBadges()
		local isDailyReady = localPlayer:GetAttribute("DailyAvailable") == true
		if els.dailyBadge then
			els.dailyBadge.Visible = isDailyReady
		end
		if els.dailyCount then
			els.dailyCount.Text = "1"
		end
		local claimable = localPlayer:GetAttribute("SeasonClaimable") or 0
		if els.seasonBadge then
			els.seasonBadge.Visible = claimable > 0
		end
		if els.seasonCount then
			els.seasonCount.Text = tostring(claimable)
		end
	end
	ownAttribute("DailyAvailable", showBadges)
	ownAttribute("SeasonClaimable", showBadges)
	showBadges()

	-- ── Starter Pack ────────────────────────────────────────────────────
	local function showStarterPack()
		local endsAt = localPlayer:GetAttribute("StarterPackEndsAt")
		local remaining = endsAt and endsAt - workspace:GetServerTimeNow()
		local isLive = remaining ~= nil and remaining > 0
		if els.starterPack then
			els.starterPack.Visible = isLive
		end
		if isLive and els.starterPackTimer then
			els.starterPackTimer.Text = "⏰ " .. TimeFormat.Clock(math.ceil(remaining), true)
		end
	end
	ownAttribute("StarterPackEndsAt", showStarterPack)
	showStarterPack()

	-- ── Hotbar ──────────────────────────────────────────────────────────
	local slotUi = {}
	local isTouchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local hotbar = find(gui, "Hotbar", "Frame")
	if hotbar then
		for slot = TEMP_SLOT, 3 do
			local button = find(hotbar, "Slot" .. slot, "TextButton")
			if button then
				local ui = {
					Button = button,
					Placeholder = find(button, "Icon.Placeholder", "TextLabel"),
					Charges = find(button, "ChargesLabel", "TextLabel"),
					Cooldown = find(button, "Cooldown", "Frame"),
					CooldownLabel = find(button, "Cooldown.CooldownLabel", "TextLabel"),
					Lock = if slot == 3 then find(button, "Lock", "Frame") else nil,
					CooldownEnd = 0,
				}
				local hint = find(button, "KeyHint", "TextLabel")
				if hint then
					hint.Visible = not isTouchOnly
					hint.Text = if slot == TEMP_SLOT then "4" else tostring(slot)
				end
				button.Activated:Connect(function()
					ToolController.Use(slot)
				end)
				slotUi[slot] = ui
			end
		end
	end

	local function showSlot(slot, info)
		local ui = slotUi[slot]
		if not ui or not info then
			return
		end
		local hasTool = info.ToolId ~= ""
		if slot == TEMP_SLOT then
			ui.Button.Visible = hasTool
		end
		if ui.Placeholder then
			ui.Placeholder.Text = if hasTool then string.upper(string.sub(info.Def.Name, 1, 1)) else ""
		end
		if ui.Charges then
			local isCounted = hasTool and info.Charges ~= math.huge
			ui.Charges.Text = if isCounted then "×" .. info.Charges else ""
		end
		if ui.Lock then
			ui.Lock.Visible = info.Locked
		end
		ui.CooldownEnd = info.CooldownEnd
	end

	local function showHotbar(slots)
		for slot = 1, 3 do
			showSlot(slot, slots[slot])
		end
		showSlot(TEMP_SLOT, slots.TempSlot)
	end

	local function tickCooldowns()
		local now = workspace:GetServerTimeNow()
		for _, ui in slotUi do
			local remaining = ui.CooldownEnd - now
			local isCooling = remaining > 0
			if ui.Cooldown then
				ui.Cooldown.Visible = isCooling
			end
			if isCooling and ui.CooldownLabel then
				ui.CooldownLabel.Text = tostring(math.ceil(remaining))
			end
		end
	end

	ToolController.StateChanged:Connect(showHotbar)
	showHotbar(ToolController.GetSlots())

	-- ── Toasts ──────────────────────────────────────────────────────────
	local toastOrder = 0
	local liveToasts = {}
	local function removeToast(toast)
		local index = table.find(liveToasts, toast)
		if index then
			table.remove(liveToasts, index)
		end
		if not toast.Parent then
			return
		end
		local label = toast:FindFirstChild("TextLabel")
		if label then
			TweenService:Create(label, FADE_TWEEN, { TextTransparency = 1 }):Play()
		end
		task.delay(FADE_TWEEN.Time, function()
			toast:Destroy()
		end)
	end

	local function showToast(text)
		if not (els.toasts and els.toastTemplate) then
			return
		end
		local toast = els.toastTemplate:Clone()
		local label = toast:FindFirstChild("TextLabel")
		if not (label and label:IsA("TextLabel")) then
			warn("[HUD] Templates.Toast has no TextLabel")
			toast:Destroy()
			return
		end
		label.Text = text
		toastOrder += 1
		toast.LayoutOrder = -toastOrder
		toast.Visible = true
		toast.Parent = els.toasts
		table.insert(liveToasts, toast)
		if #liveToasts > MAX_TOASTS then
			removeToast(liveToasts[1])
		end
		local scale = toast:FindFirstChildOfClass("UIScale")
		if scale then
			scale.Scale = POP_START_SCALE
			TweenService:Create(scale, POP_TWEEN, { Scale = 1 }):Play()
		end
		task.delay(TOAST_SECONDS, removeToast, toast)
	end

	Network.OnEvent("ShowToast", function(text)
		if type(text) == "string" then
			showToast("📣 " .. text)
		end
	end)
	Network.OnEvent("PlayerFinished", function(name, _place, multiplier, clockRate)
		if type(name) ~= "string" or type(multiplier) ~= "number" or type(clockRate) ~= "number" then
			return
		end
		showToast(("🔥 %s finished! Coins ×%g, clock ×%g"):format(RichText.Bold(name), multiplier, clockRate))
	end)

	-- ── Trick popup ─────────────────────────────────────────────────────
	local popupToken = 0
	local function setVisible(element, isVisible)
		if element then
			element.Visible = isVisible
		end
	end
	local function onPopup(text, _points, grade, info)
		if grade == "RoundCap" then
			showToast("🪙 " .. text)
			return
		end
		if not els.trick then
			return
		end
		if grade == "Trick" then
			setVisible(els.trickChain, false)
			setVisible(els.trickResult, false)
			setVisible(els.trickMixed, false)
			setVisible(els.trickMax, false)
			if els.trickName then
				els.trickName.Text = text
			end
		elseif grade == "Chain" and els.trickChain then
			els.trickChain.Text = (string.gsub(text, "^x", "×"))
			els.trickChain.Visible = true
		elseif grade == "Mixed" and els.trickMixed then
			els.trickMixed.Text = text
			els.trickMixed.Visible = true
		elseif GRADE_COLORS[grade] and els.trickResult then
			els.trickResult.Text = text
			els.trickResult.TextColor3 = GRADE_COLORS[grade]
			els.trickResult.Visible = true
			setVisible(els.trickMax, info ~= nil and info.Flags ~= nil and info.Flags.SegmentCapped == true)
		else
			return
		end
		if not els.trick.Visible and els.trickScale then
			els.trickScale.Scale = POP_START_SCALE
			TweenService:Create(els.trickScale, POP_TWEEN, { Scale = 1 }):Play()
		end
		els.trick.Visible = true
		popupToken += 1
		local token = popupToken
		task.delay(TRICK_POPUP_SECONDS, function()
			if token == popupToken then
				els.trick.Visible = false
			end
		end)
	end
	TrickController.Popup:Connect(onPopup)

	-- ── Clock ───────────────────────────────────────────────────────────
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < TICK_INTERVAL then
			return
		end
		elapsed = 0
		showTimer()
		showStarterPack()
		tickCooldowns()
	end)
end

task.spawn(function()
	local gui = localPlayer:WaitForChild("PlayerGui"):WaitForChild(HUD_NAME, HUD_TIMEOUT)
	if not (gui and gui:IsA("ScreenGui")) then
		warn(("[HUD] Expected ScreenGui %s at StarterGui.%s; the HUD is unavailable"):format(HUD_NAME, HUD_NAME))
		return
	end
	setup(gui)
end)

return HUD
