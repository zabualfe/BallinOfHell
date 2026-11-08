-- UpsellFlags: remote switches and timing for every UpsellTable trigger (GDD 11.4: "all triggers are
-- FlagService flags"). Returns a list of definitions generated from the table, so a new trigger gets
-- flags with no extra code.
--   UpsellEnabled_<Id>        bool    false turns the trigger off
--   UpsellCap_<Id>            number  popups per session
--   UpsellParam_<Id>_<Name>   number  each numeric threshold in the trigger's Params
--   UpsellMinSecondsBetweenPopups, UpsellQuietFirstSessionSeconds: the Global spacing rules

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UpsellTable = require(ReplicatedStorage.Tables.UpsellTable)

local definitions = {
	{ Key = "UpsellMinSecondsBetweenPopups", Default = UpsellTable.Global.MinSecondsBetweenPopups },
	{ Key = "UpsellQuietFirstSessionSeconds", Default = UpsellTable.Global.QuietFirstSessionSeconds },
}

for _, trigger in UpsellTable.Triggers do
	table.insert(definitions, { Key = "UpsellEnabled_" .. trigger.Id, Default = true })
	table.insert(definitions, { Key = "UpsellCap_" .. trigger.Id, Default = trigger.CapPerSession })
	for name, value in trigger.Params or {} do
		if type(value) == "number" then
			table.insert(definitions, { Key = ("UpsellParam_%s_%s"):format(trigger.Id, name), Default = value })
		end
	end
end

return definitions
