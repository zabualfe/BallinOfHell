local CourseService = require(script.Parent.Parent.Parent.CourseService)

return function(_context, seed)
	CourseService.Teardown()
	if not CourseService.Build(seed) then
		return "Course build failed; see the server output."
	end
	return ("Course rebuilt (seed %s, %d segments)."):format(
		tostring(CourseService.GetSeed()),
		CourseService.GetSegmentCount()
	)
end
