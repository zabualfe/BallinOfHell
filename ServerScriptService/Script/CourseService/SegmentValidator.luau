-- SegmentValidator
-- Checks one segment model against the authoring contract (GDD 5.4).
--
-- Usage:
--   SegmentValidator.Validate(model, folderTier) -> info?, problem?
--     info    -- { Name, Tier, Theme, Weight, ParTime, ToolRequired, Flags } when valid
--                Flags = { NoTools = boolean, ToolsAllowed = string?, ToolRequired = string? } (raw tool attributes for ToolService)
--     problem -- what is missing or wrong; the caller warns with model:GetFullName() and skips the segment
-- Contract: PositionParts.StartPart / EndPart (BaseParts), attributes Tier (string, matches the folder),
-- Theme (string), Weight (number, default 1, clamped to Segment.WeightMin..WeightMax), ParTime (number > 0).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CourseTable = require(ReplicatedStorage.Tables.CourseTable)

local SegmentValidator = {}

local function findPart(parent, name)
	local part = parent and parent:FindFirstChild(name)
	if part and part:IsA("BasePart") then
		return part
	end
	return nil
end

local function readString(model, name)
	local value = model:GetAttribute(name)
	return if type(value) == "string" and value ~= "" then value else nil
end

function SegmentValidator.Validate(model, folderTier)
	if not model:IsA("Model") then
		return nil, "is not a Model"
	end

	local positionParts = model:FindFirstChild("PositionParts")
	if not positionParts then
		return nil, "is missing PositionParts"
	end
	for _, partName in { "StartPart", "EndPart" } do
		if not findPart(positionParts, partName) then
			return nil, ("is missing PositionParts.%s (a BasePart)"):format(partName)
		end
	end

	local tier = model:GetAttribute("Tier")
	if type(tier) ~= "string" then
		return nil, "is missing the Tier attribute (string)"
	end
	if tier ~= folderTier then
		return nil, ("has Tier %q but sits in the %s folder"):format(tier, folderTier)
	end
	local theme = model:GetAttribute("Theme")
	if type(theme) ~= "string" then
		return nil, "is missing the Theme attribute (string)"
	end
	local parTime = model:GetAttribute("ParTime")
	if type(parTime) ~= "number" or parTime <= 0 then
		return nil, "is missing the ParTime attribute (number of seconds, above 0)"
	end

	local weight = model:GetAttribute("Weight")
	if weight ~= nil and type(weight) ~= "number" then
		return nil, "has a Weight attribute that is not a number"
	end
	local segment = CourseTable.Segment
	weight = math.clamp(weight or CourseTable.Picker.DefaultWeight, segment.WeightMin, segment.WeightMax)

	return {
		Name = model.Name,
		Tier = tier,
		Theme = theme,
		Weight = weight,
		ParTime = parTime,
		ToolRequired = model:GetAttribute("ToolRequired") ~= nil,
		Flags = {
			NoTools = model:GetAttribute("NoTools") == true,
			ToolsAllowed = readString(model, "ToolsAllowed"),
			ToolRequired = readString(model, "ToolRequired"),
		},
	}
end

return SegmentValidator
