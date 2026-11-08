-- Objectives/UseTool
-- Counts an activation ToolService accepted, optionally only for params.toolId.

local UseTool = { Event = "ToolUsed" }

function UseTool.Increment(params, payload)
	if params.toolId and payload.ToolId ~= params.toolId then
		return 0
	end
	return 1
end

return UseTool
