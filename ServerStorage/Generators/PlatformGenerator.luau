-- Platform generator for Ball of Hell.
-- Stretch the ProceduralModel (Size) and the base fills the box while the
-- TopSurface stays on top, inset by exactly TopInset studs from every edge.

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

local function makePart(name, size, cframe, color, anchored, parent)
	local p = Instance.new("Part")
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

Generator.OnGenerate = function(parameters, target)
	local a = parameters.Attributes
	local size = parameters.Size
	local inset = math.max(a.TopInset, 0)
	local thick = math.max(a.TopThickness, 0.001)
	local protrude = math.clamp(a.TopProtrusion, 0, thick)

	-- Base fills the box except for the bit of the top surface that sticks out.
	local baseH = math.max(size.Y - protrude, 0.001)
	makePart("Base",
		Vector3.new(size.X, baseH, size.Z),
		CFrame.new(0, -size.Y / 2 + baseH / 2, 0),
		a.BaseColor, a.Anchored, target)

	-- Top surface: always flush with the top of the box, same inset on all four sides.
	local top = makePart("TopSurface",
		Vector3.new(math.max(size.X - 2 * inset, 0.001), thick, math.max(size.Z - 2 * inset, 0.001)),
		CFrame.new(0, size.Y / 2 - thick / 2, 0),
		a.TopColor, a.Anchored, target)

	if a.TopTexture ~= "" then
		local tex = Instance.new("Texture")
		tex.Name = "Texture"
		tex.Texture = a.TopTexture
		tex.Face = Enum.NormalId.Top
		tex.Color3 = a.TopTextureColor
		tex.Transparency = a.TopTextureTransparency
		tex.StudsPerTileU = a.TopTextureStudsPerTile
		tex.StudsPerTileV = a.TopTextureStudsPerTile
		tex.Parent = top
	end
end

return Generator
