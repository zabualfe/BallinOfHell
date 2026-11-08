-- Race: counts the round clock down at ClockRate. Ends at 0, or early when nobody is left in the server.

local Race = { Name = "Race" }

function Race.Run(context)
	context.SetState("Race")
	local last = os.clock()
	while context.GetTimeLeft() > 0 and context.HasPlayers() do
		task.wait(context.Tick)
		local now = os.clock()
		context.AdvanceClock(now - last)
		last = now
	end
	context.SetTimeLeft(0)
	context.EndRace()
end

function Race.Skip(context)
	context.SetTimeLeft(0)
	context.EndRace()
end

return Race
