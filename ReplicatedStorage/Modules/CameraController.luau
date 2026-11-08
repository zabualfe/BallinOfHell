-- CameraController
-- Camera effects for the local player. For now: a short FOV punch (boost panels, Rocket Burst, trick chains).
--
--   CameraController.Punch(strength)   strength 1 = PUNCH_FOV degrees wider, 0 < strength <= MAX_STRENGTH.
--                                      A new punch while one is active takes the larger of the two and restarts the
--                                      fall-back; the FOV returns to the value it had before the first punch.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CameraController = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local PUNCH_FOV = 12 -- degrees at strength 1
local MAX_STRENGTH = 2 -- clamp for callers
local RISE_TIME = 0.12 -- seconds to reach the peak
local FALL_TIME = 0.45 -- seconds to return
local RISE_STYLE = Enum.EasingStyle.Quad
local FALL_STYLE = Enum.EasingStyle.Quad
local FALL_DIRECTION = Enum.EasingDirection.Out
local RISE_DIRECTION = Enum.EasingDirection.Out

-- ── State ───────────────────────────────────────────────────────────────
local connection
local baseFov -- FOV before the first active punch
local appliedOffset = 0 -- degrees currently added
local fromOffset = 0
local peakOffset = 0
local elapsed = 0
local isRising = false

local function stop(camera)
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if camera and baseFov then
		camera.FieldOfView = baseFov
	end
	baseFov = nil
	appliedOffset = 0
end

local function step(dt)
	local camera = workspace.CurrentCamera
	if not camera then
		stop(nil)
		return
	end

	elapsed += dt
	if isRising then
		local alpha = TweenService:GetValue(math.min(elapsed / RISE_TIME, 1), RISE_STYLE, RISE_DIRECTION)
		appliedOffset = fromOffset + (peakOffset - fromOffset) * alpha
		if elapsed >= RISE_TIME then
			isRising = false
			elapsed = 0
		end
	else
		local alpha = TweenService:GetValue(math.min(elapsed / FALL_TIME, 1), FALL_STYLE, FALL_DIRECTION)
		appliedOffset = peakOffset * (1 - alpha)
		if elapsed >= FALL_TIME then
			stop(camera)
			return
		end
	end
	camera.FieldOfView = baseFov + appliedOffset
end

function CameraController.Punch(strength)
	if type(strength) ~= "number" or strength ~= strength or strength <= 0 then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	if not connection then
		baseFov = camera.FieldOfView
		connection = RunService.RenderStepped:Connect(step)
	end
	fromOffset = appliedOffset
	peakOffset = math.max(appliedOffset, PUNCH_FOV * math.min(strength, MAX_STRENGTH))
	elapsed = 0
	isRising = true
end

return CameraController
