-- AdminClient
-- Activates the Cmdr console for admins only. AdminService sets the player attribute "IsAdmin" on the server;
-- non-admins never load CmdrClient's UI, and the server's BeforeRun hook is the real gate anyway.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AdminClient = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local ATTRIBUTE_NAME = "IsAdmin"
local LOAD_TIMEOUT = 30 -- seconds to wait for the server to publish CmdrClient
local ACTIVATION_KEYS = { Enum.KeyCode.F2 }

local localPlayer = Players.LocalPlayer

local function activate()
	local cmdrFolder = ReplicatedStorage:WaitForChild("CmdrClient", LOAD_TIMEOUT)
	if not cmdrFolder then
		warn("[AdminClient] ReplicatedStorage.CmdrClient did not appear; the admin console is unavailable")
		return
	end
	local ok, CmdrClient = pcall(require, cmdrFolder)
	if not ok then
		warn("[AdminClient] CmdrClient failed to load: " .. tostring(CmdrClient))
		return
	end
	CmdrClient:SetActivationKeys(ACTIVATION_KEYS)
end

-- Non-admins never get the attribute, so this stays a single idle connection for them.
local activated = false
local function check()
	if activated or localPlayer:GetAttribute(ATTRIBUTE_NAME) ~= true then
		return
	end
	activated = true
	task.spawn(activate)
end

localPlayer:GetAttributeChangedSignal(ATTRIBUTE_NAME):Connect(check)
check()

return AdminClient
