-- Vanishing (tag "Vanishing")
-- Solid for OnTime seconds (fading out over the last FADE_TIME), gone for OffTime, shifted by Phase. Driven by
-- workspace:GetServerTimeNow() so all clients agree. Collision and transparency are changed locally on every BasePart
-- of the object; the originals are restored on unregister. Plug-in contract: see BoostPanel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ObstacleMath = require(ReplicatedStorage.Shared.ObstacleMath)

local Vanishing = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local FADE_TIME = 0.3 -- seconds of fade before the object goes (GDD 5.4)

local function collectParts(instance)
	local parts = {}
	if instance:IsA("BasePart") then
		table.insert(parts, instance)
	end
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

function Vanishing.Register(instance)
	if not instance:IsA("PVInstance") then
		return nil, "must be a BasePart or Model"
	end
	local config, reason = ObstacleMath.ConfigFor("Vanishing", instance:GetAttributes())
	if not config then
		return nil, reason
	end

	local parts = collectParts(instance)
	if #parts == 0 then
		return nil, "contains no BasePart"
	end
	config.Parts = parts
	config.Originals = {}
	for _, part in parts do
		config.Originals[part] = { Transparency = part.Transparency, CanCollide = part.CanCollide }
	end
	return config
end

function Vanishing.Unregister(_instance, state)
	for part, original in state.Originals do
		if part.Parent then
			part.Transparency = original.Transparency
			part.CanCollide = original.CanCollide
		end
	end
end

function Vanishing.Step(_dt, active, now)
	for _, state in active do
		local result =
			ObstacleMath.Vanishing(now - (state.TimeLag or 0), state.OnTime, state.OffTime, state.Phase, FADE_TIME)
		if result.Solid ~= state.LastSolid or result.Transparency ~= state.LastTransparency then
			state.LastSolid = result.Solid
			state.LastTransparency = result.Transparency
			for part, original in state.Originals do
				part.CanCollide = result.Solid and original.CanCollide
				part.Transparency = original.Transparency + (1 - original.Transparency) * result.Transparency
			end
		end
	end
end

return Vanishing
