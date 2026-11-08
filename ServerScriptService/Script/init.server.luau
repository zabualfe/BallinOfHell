-- Server entry. Requires every child module in its own thread so one failure or yield
-- cannot block the others. Modules start themselves at require time (AGENTS.md "Startup").

for _, child in script:GetChildren() do
	if child:IsA("ModuleScript") then
		task.spawn(function()
			local ok, err = pcall(require, child)
			if not ok then
				warn(("[Loader] %s failed: %s"):format(child.Name, tostring(err)))
			end
		end)
	end
end
