-- Countdown: balls stay frozen for the countdown, then the race opens.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoundTable = require(ReplicatedStorage.Tables.RoundTable)

local Countdown = { Name = "Countdown" }

function Countdown.Run(context)
	context.SetState("Countdown")
	context.Wait(RoundTable.Steps.Countdown, false)
	context.SetFrozen(false)
	context.BeginRace()
end

function Countdown.Skip(context)
	context.SetFrozen(false)
	context.BeginRace()
end

return Countdown
