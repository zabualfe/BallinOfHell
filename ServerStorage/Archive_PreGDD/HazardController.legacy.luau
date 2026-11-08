-- HazardController: drives every tagged hazard in Workspace.
-- Movement tags (on a Model with a PrimaryPart, or a BasePart):
--   Hazard_Swing  attrs: Period (s), Angle (deg), Phase (0-1)      swings around its local Z axis
--   Hazard_Slide  attrs: Period (s), Distance (studs), Phase (0-1) slides back and forth along local X
--   Hazard_Spin   attrs: RPM, SpinAxis ("X","Y","Z")               spins around a local axis
-- Touch tags (on BaseParts):
--   Hazard_Knockback attrs: Force   shoves whatever touches it away
--   Hazard_Kill                     resets the player (fires ServerStorage.HazardHit, kills the Humanoid)
--   BoostPanel       attrs: Speed   launches you along the panel's LookVector
-- The ball/vehicle system can listen to ServerStorage.HazardHit (player, kind, part) to reset properly.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local HazardHit = ServerStorage:FindFirstChild("HazardHit")
if not HazardHit then
	HazardHit = Instance.new("BindableEvent")
	HazardHit.Name = "HazardHit"
	HazardHit.Parent = ServerStorage
end

local movers = {} -- [instance] = {kind, base}

local function getPivot(inst)
	return inst:GetPivot()
end

local function addMover(kind)
	return function(inst)
		if not inst:IsDescendantOf(workspace) then return end
		movers[inst] = { kind = kind, base = getPivot(inst) }
	end
end

local AXES = { X = Vector3.xAxis, Y = Vector3.yAxis, Z = Vector3.zAxis }

for tag, kind in pairs({ Hazard_Swing = "swing", Hazard_Slide = "slide", Hazard_Spin = "spin" }) do
	for _, inst in CollectionService:GetTagged(tag) do addMover(kind)(inst) end
	CollectionService:GetInstanceAddedSignal(tag):Connect(addMover(kind))
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst) movers[inst] = nil end)
end

RunService.Heartbeat:Connect(function()
	local t = workspace:GetServerTimeNow()
	for inst, m in movers do
		if not inst.Parent then movers[inst] = nil; continue end
		local period = inst:GetAttribute("Period") or 3
		local phase = (inst:GetAttribute("Phase") or 0) * math.pi * 2
		local s = math.sin(t / period * math.pi * 2 + phase)
		local cf
		if m.kind == "swing" then
			cf = m.base * CFrame.Angles(0, 0, math.rad(inst:GetAttribute("Angle") or 60) * s)
		elseif m.kind == "slide" then
			cf = m.base * CFrame.new((inst:GetAttribute("Distance") or 40) / 2 * s, 0, 0)
		else
			local axis = AXES[inst:GetAttribute("SpinAxis") or "Y"] or Vector3.yAxis
			cf = m.base * CFrame.fromAxisAngle(axis, t * (inst:GetAttribute("RPM") or 10) / 60 * math.pi * 2)
		end
		inst:PivotTo(cf)
	end
end)

-- ===== touch hazards =====
local cooldown = setmetatable({}, { __mode = "k" })
local function ready(root, secs)
	local now = os.clock()
	if cooldown[root] and now - cooldown[root] < secs then return false end
	cooldown[root] = now
	return true
end

local function playerFrom(hit)
	local model = hit:FindFirstAncestorOfClass("Model")
	while model do
		local p = Players:GetPlayerFromCharacter(model)
		if p then return p end
		local owner = model:GetAttribute("OwnerUserId")
		if owner then return Players:GetPlayerByUserId(owner) end
		model = model:FindFirstAncestorOfClass("Model")
	end
	local owner = hit:GetAttribute("OwnerUserId")
	return owner and Players:GetPlayerByUserId(owner) or nil
end

local function bind(tag, fn)
	local function hook(part)
		if part:IsA("BasePart") then part.Touched:Connect(function(hit) fn(part, hit) end) end
	end
	for _, p in CollectionService:GetTagged(tag) do hook(p) end
	CollectionService:GetInstanceAddedSignal(tag):Connect(hook)
end

bind("Hazard_Knockback", function(part, hit)
	local root = hit.AssemblyRootPart
	if not root or root.Anchored or not ready(root, 0.4) then return end
	local away = (root.Position - part.Position) * Vector3.new(1, 0, 1)
	if away.Magnitude < 0.01 then away = part.CFrame.RightVector end
	local force = part:GetAttribute("Force") or 120
	root.AssemblyLinearVelocity = away.Unit * force + Vector3.yAxis * force * 0.35
	local p = playerFrom(hit)
	if p then HazardHit:Fire(p, "Knockback", part) end
end)

bind("Hazard_Kill", function(part, hit)
	local p = playerFrom(hit)
	if not p then return end
	local root = hit.AssemblyRootPart
	if root and not ready(root, 1) then return end
	HazardHit:Fire(p, "Kill", part)
	local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
	if hum then hum.Health = 0 end
end)

bind("BoostPanel", function(part, hit)
	local root = hit.AssemblyRootPart
	if not root or root.Anchored or not ready(root, 0.5) then return end
	local look = part.CFrame.LookVector
	local v = root.AssemblyLinearVelocity
	local forward = math.max(v:Dot(look), part:GetAttribute("Speed") or 220)
	root.AssemblyLinearVelocity = look * forward + Vector3.yAxis * math.max(v.Y, 0)
end)
