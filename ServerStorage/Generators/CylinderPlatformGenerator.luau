-- Cylinder platform generator for Ball of Hell.
-- Round platform: diameter is the smaller of the X/Z size. TopSurface is a disc on top,
-- inset by exactly TopInset studs from the edge, however you stretch it.

local Generator = {}

Generator.Attributes = {
	TopInset = 0.1,        -- distance from each side edge of the base to the top surface
	TopThickness = 0.1,    -- thickness of the top surface
	TopProtrusion = 0.05,  -- how far the top surface sticks out above the base
	BaseColor = Color3.fromRGB(27, 42, 53),
	TopColor = Color3.fromRGB(245, 205, 48),
	Anchored = true,
	-- Texture on the top face of TopSurface (set TopTexture to "" to remove it)
	TopTexture = "rbxassetid://83313626819084",
	TopTextureColor = Color3.new(1, 1, 1),
	TopTextureTransparency = 0.7,
	TopTextureStudsPerTile = 8,
}

local function makePart(name, size, cframe, color, anchored, parent, shape)
	local p = Instance.new(shape == "Wedge" and "WedgePart" or "Part")
	if shape == "Cylinder" then p.Shape = Enum.PartType.Cylinder end
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = anchored
	p.CanCollide = true
	p.Parent = parent
	return p
end

local function addTexture(a, part, face)
	if a.TopTexture == "" then return end
	local tex = Instance.new("Texture")
	tex.Name = "Texture"
	tex.Texture = a.TopTexture
	tex.Face = face
	tex.Color3 = a.TopTextureColor
	tex.Transparency = a.TopTextureTransparency
	tex.StudsPerTileU = a.TopTextureStudsPerTile
	tex.StudsPerTileV = a.TopTextureStudsPerTile
	tex.Parent = part
end

Generator.OnGenerate = function(parameters, target)
	local a = parameters.Attributes
	local size = parameters.Size
	local inset = math.max(a.TopInset, 0)
	local thick = math.max(a.TopThickness, 0.001)
	local protrude = math.clamp(a.TopProtrusion, 0, thick)
	local diameter = math.min(size.X, size.Z)
	local upright = CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis (X) points up

	local baseH = math.max(size.Y - protrude, 0.001)
	makePart("Base",
		Vector3.new(baseH, diameter, diameter),
		CFrame.new(0, -size.Y / 2 + baseH / 2, 0) * upright,
		a.BaseColor, a.Anchored, target, "Cylinder")

	local top = makePart("TopSurface",
		Vector3.new(thick, math.max(diameter - 2 * inset, 0.001), math.max(diameter - 2 * inset, 0.001)),
		CFrame.new(0, size.Y / 2 - thick / 2, 0) * upright,
		a.TopColor, a.Anchored, target, "Cylinder")
	addTexture(a, top, Enum.NormalId.Right) -- Right face is the top after the rotation
end

return Generator
