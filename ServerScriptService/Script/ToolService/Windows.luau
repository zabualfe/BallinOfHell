-- ToolService.Windows
-- Pure bookkeeping of "tool X was active from t0 to t1" (server time, workspace:GetServerTimeNow()). ToolService keeps one
-- list per player and exposes it as ToolService.GetActiveWindows / WasActive so TrickService can halve the points of an
-- airtime that overlapped Glider, Grapple or Coil (GDD 7.5, 7.9) and explain a Spring's vertical gain.
--
--   Windows.New() -> list
--   Windows.Add(list, toolId, startTime, endTime, keepSeconds?) -> window   -- also drops windows that ended keepSeconds ago
--   Windows.Close(window, time)                      -- ends it early (Glider landed); never extends
--   Windows.Query(list, fromTime, toTime, toolIds?) -> { { ToolId, Start, End } }   -- copies; toolIds is a set, nil = any

local Windows = {}

function Windows.New()
	return {}
end

function Windows.Add(list, toolId, startTime, endTime, keepSeconds)
	if keepSeconds then
		for index = #list, 1, -1 do
			if list[index].End < startTime - keepSeconds then
				table.remove(list, index)
			end
		end
	end
	local window = { ToolId = toolId, Start = startTime, End = math.max(startTime, endTime) }
	table.insert(list, window)
	return window
end

function Windows.Close(window, time)
	if time < window.End then
		window.End = math.max(window.Start, time)
	end
end

function Windows.Query(list, fromTime, toTime, toolIds)
	local found = {}
	for _, window in list do
		if (toolIds == nil or toolIds[window.ToolId]) and window.Start <= toTime and window.End >= fromTime then
			table.insert(found, { ToolId = window.ToolId, Start = window.Start, End = window.End })
		end
	end
	return found
end

return Windows
