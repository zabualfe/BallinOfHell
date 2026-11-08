-- Teardown: players back to the lobby first, then the course is destroyed.

local Teardown = { Name = "Teardown" }

function Teardown.Run(context)
	context.SetState("Teardown")
	context.Teardown()
end

function Teardown.Skip(context)
	context.Teardown()
end

return Teardown
