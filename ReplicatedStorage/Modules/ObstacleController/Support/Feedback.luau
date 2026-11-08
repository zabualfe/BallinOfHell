-- Feedback
-- Local obstacle feedback hook. Plays ReplicatedStorage.Assets.Sounds.<Name> if that template exists, else nothing
-- (sounds are authored in Studio, so a missing one is not an error). Visual feedback is CameraController.Punch.
--
--   Feedback.Play(name)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Feedback = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local CLEANUP_PADDING = 1 -- seconds added to a sound's length before it is destroyed

function Feedback.Play(name)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local sounds = assets and assets:FindFirstChild("Sounds")
	local template = sounds and sounds:FindFirstChild(name)
	if not template or not template:IsA("Sound") then
		return
	end

	local sound = template:Clone()
	sound.Parent = SoundService
	sound:Play()
	task.delay(math.max(sound.TimeLength, 0.5) + CLEANUP_PADDING, function()
		sound:Destroy()
	end)
end

return Feedback
