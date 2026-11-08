-- KillBrick (tag "KillBrick")
-- A touch by the local ball tells the server (Network "KillBrickTouched", optional segment index). The server validates
-- it (ball near a KillBrick, not shielded) and respawns; the client never decides the outcome, it only plays feedback.
-- Plug-in contract: see BoostPanel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage.Network)
local ObstacleMath = require(ReplicatedStorage.Shared.ObstacleMath)

local Feedback = require(script.Parent.Support.Feedback)

local KillBrick = {}
KillBrick.Debounce = 1 -- seconds, per brick

-- ── Tuning ──────────────────────────────────────────────────────────────
local SEND_COOLDOWN = 1 -- seconds between reports across all bricks; the respawn takes longer than this
local SEGMENT_INDEX_ATTRIBUTE = "SegmentIndex" -- optional number on a segment model or any ancestor

local lastSent = -math.huge

local function findSegmentIndex(instance)
	local current = instance
	while current and current ~= workspace do
		local index = current:GetAttribute(SEGMENT_INDEX_ATTRIBUTE)
		if type(index) == "number" then
			return index
		end
		current = current.Parent
	end
	return nil
end

function KillBrick.Register(instance)
	return ObstacleMath.ConfigFor("KillBrick", instance:GetAttributes())
end

function KillBrick.Unregister() end

function KillBrick.OnTouched(instance)
	local now = os.clock()
	if now - lastSent < SEND_COOLDOWN then
		return
	end
	lastSent = now
	Network.FireServer("KillBrickTouched", findSegmentIndex(instance))
	Feedback.Play("KillBrick")
end

return KillBrick
