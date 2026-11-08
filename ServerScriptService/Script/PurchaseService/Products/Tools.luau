-- Products/Tools
-- Family "Tools" (GDD 6.7): unlocks by rarity, refills, the crate and the two bundles. The plug-in contract is
-- documented at the top of PurchaseService/init.luau. Everything grants through ToolService.
--
--   ToolUnlock<Rarity>   targeted: the tool the player is viewing (CanPrompt stores its id; its rarity must match)
--   ToolRefill           targeted: +Params.Charges stored charges of the viewed tool
--   ToolCrate            +Params.Charges of every tool except Params.ExcludeTools
--   SurvivalBundle, SpeedrunnerBundle   Params.Unlocks + Params.Charges of each
-- Already owned at receipt -> the unlock converts to ToolTable.Config.UnlockedConvertsToCharges stored charges.
-- A grant that finds the stack already full still counts as granted: retrying forever helps nobody.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProductTable = require(ReplicatedStorage.Tables.ProductTable)
local ToolTable = require(ReplicatedStorage.Tables.ToolTable)

local ToolService = require(script.Parent.Parent.Parent.ToolService)

local FAMILY = "Tools"
local CONVERT_CHARGES = ToolTable.Config.UnlockedConvertsToCharges

local function unlockOrConvert(player, toolId, source)
	if ToolService.Unlock(player, toolId, source) then
		return
	end
	ToolService.AddCharges(player, toolId, CONVERT_CHARGES, source)
end

local function viewedTool(row)
	return function(_, toolId)
		local def = type(toolId) == "string" and ToolTable.Tools[toolId] or nil
		if not def then
			return false, nil
		end
		if row.Params.Rarity ~= nil and def.Rarity ~= row.Params.Rarity then
			return false, nil
		end
		return true, toolId
	end
end

local Tools = { Products = {} }

for key, row in ProductTable do
	if row.Family ~= FAMILY then
		continue
	end
	local params = row.Params or {}
	local charges = params.Charges
	local definition

	if params.Rarity ~= nil then
		definition = {
			CanPrompt = viewedTool(row),
			Effect = function(player, _, toolId)
				local def = type(toolId) == "string" and ToolTable.Tools[toolId] or nil
				if not def or def.Rarity ~= params.Rarity then
					return false
				end
				unlockOrConvert(player, toolId, "Robux")
				return true
			end,
		}
	elseif params.Unlocks ~= nil then
		definition = {
			Effect = function(player)
				for _, toolId in params.Unlocks do
					unlockOrConvert(player, toolId, "Bundle")
					ToolService.AddCharges(player, toolId, charges, "Bundle")
				end
				return true
			end,
		}
	elseif params.ExcludeTools ~= nil then
		definition = {
			Effect = function(player)
				for toolId in ToolTable.Tools do
					if not table.find(params.ExcludeTools, toolId) then
						ToolService.AddCharges(player, toolId, charges, "Robux")
					end
				end
				return true
			end,
		}
	elseif type(charges) == "number" then
		definition = {
			CanPrompt = viewedTool(row),
			Effect = function(player, _, toolId)
				if type(toolId) ~= "string" or not ToolTable.Tools[toolId] then
					return false
				end
				ToolService.AddCharges(player, toolId, charges, "Robux")
				return true
			end,
		}
	else
		warn(`[PurchaseService] Tools product {key} has no Params this family understands`)
		continue
	end
	Tools.Products[key] = definition
end

return Tools
