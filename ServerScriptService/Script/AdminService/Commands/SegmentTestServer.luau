local RunService = game:GetService("RunService")

local CourseService = require(script.Parent.Parent.Parent.CourseService)

local CLEAR_WORD = "none"

return function(_context, name)
	if not RunService:IsStudio() then
		return "segment-test only works in Studio."
	end
	local isClearing = name:lower() == CLEAR_WORD
	workspace:SetAttribute("SegmentTest", if isClearing then nil else name)
	CourseService.Teardown()
	if not CourseService.Build() then
		return "Course build failed; see the server output."
	end
	if isClearing then
		return "Segment test cleared; normal course rebuilt."
	end
	return ("Built segment test %q (%d segments)."):format(name, CourseService.GetSegmentCount())
end
