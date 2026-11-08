-- Results: the race is over; everyone gets the results card.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoundTable = require(ReplicatedStorage.Tables.RoundTable)

local Results = { Name = "Results" }

function Results.Run(context)
	context.SetState("Results")
	context.PublishResults()
	context.Wait(RoundTable.Steps.Results, false)
end

function Results.Skip() end

return Results
