-- Step contract (RoundService): Name, Run(context) -> "Abort"?, Skip(context) puts the world in the state the step ends in.
-- Intermission: players wait in the lobby; the timer only runs while someone is in the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoundTable = require(ReplicatedStorage.Tables.RoundTable)

local Intermission = { Name = "Intermission" }

function Intermission.Run(context)
	context.SetState("Intermission")
	context.Wait(RoundTable.Steps.Intermission, true)
end

function Intermission.Skip() end

return Intermission
