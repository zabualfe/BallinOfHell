-- ToolNoCharges: the player pressed a tool with 0 charges. ToolService has no signal for it, so the tool client reports
-- ToolPressedEmpty(toolId) and the server re-checks the stored charges. Offers a Tool Refill for that tool.
-- Contract: see UpsellService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage.Network)
local ToolTable = require(ReplicatedStorage.Tables.ToolTable)

local ToolService = require(script.Parent.Parent.Parent.ToolService)

local ID = "ToolNoCharges"
local PRESS_RATE = { Capacity = 3, RefillPerSecond = 0.5 } -- ToolPressedEmpty burst / per second

return {
	Id = ID,
	Start = function(UpsellService)
		Network.OnEvent("ToolPressedEmpty", function(player, toolId)
			if
				type(toolId) ~= "string"
				or not ToolTable.Tools[toolId]
				or ToolService.GetCharges(player, toolId) > 0
			then
				return
			end
			UpsellService.Offer(player, ID, { ToolId = toolId, Targets = { ToolRefill = toolId } })
		end, PRESS_RATE)
	end,
}
