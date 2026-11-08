-- Wedge platform generator for Ball of Hell.
-- The base is a wedge filling the box (high end at the back, +Z). TopSurface lies on the
-- slope, inset by exactly TopInset studs from every edge of the slope, however you stretch it.

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

	makePart("Base", size, CFrame.new(), a.BaseColor, a.Anchored, target, "Wedge")

	-- Slope runs from the bottom-front edge to the top-back edge.
	local h, d = size.Y, size.Z
	local len = math.sqrt(h * h + d * d)
	local normal = Vector3.new(0, d, -h) / len -- points up and out of the slope
	local center = normal * (protrude - thick / 2)
	local cf = CFrame.fromMatrix(center, Vector3.xAxis, normal)

	local top = makePart("TopSurface",
		Vector3.new(math.max(size.X - 2 * inset, 0.001), thick, math.max(len - 2 * inset, 0.001)),
		cf, a.TopColor, a.Anchored, target)
	addTexture(a, top, Enum.NormalId.Top)
end

return Generator
