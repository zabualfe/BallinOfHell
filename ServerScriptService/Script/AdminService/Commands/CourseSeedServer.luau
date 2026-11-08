local CourseService = require(script.Parent.Parent.Parent.CourseService)

return function()
	local seed = CourseService.GetSeed()
	if not CourseService.IsBuilt() or seed == nil then
		return "No course is built."
	end
	return "Course seed: " .. tostring(seed)
end
