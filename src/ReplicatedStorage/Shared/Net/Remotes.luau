--!strict
-- Creates and hands out the remote instances. Requiring this from either side
-- gives you the same objects, so there is no WaitForChild boilerplate scattered
-- around the codebase.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "RemoteObjects"

-- Note: in Studio's Edit mode RunService:IsServer() is FALSE and IsClient() is
-- TRUE, which is counterintuitive. Without the IsEdit() check this module hangs
-- for 20s and then errors any time it is required outside a running game.
-- IsEdit() requires plugin capability, so a LocalScript calling it throws.
-- Probe it safely: in Edit mode this resolves true, in a running game the
-- pcall simply leaves it false and IsServer() decides.
local isEdit = false
pcall(function() isEdit = RunService:IsEdit() end)
local canCreate = RunService:IsServer() or isEdit

local Remotes = {}

-- WaitForChild rather than a direct index, matching BattleRemotes,
-- BattleRemotes and SkillRemotes: a client that required this module before
-- Shared/Net had replicated would otherwise throw on the index itself.
local netFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net")

local folder
if canCreate then
	folder = netFolder:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = netFolder
	end
else
	folder = netFolder:WaitForChild(FOLDER_NAME, 30)
	assert(folder, "[Remotes] server never created the remote folder")
end

local function remote(className: string, name: string)
	if canCreate then
		local r = folder:FindFirstChild(name)
		if not r then
			r = Instance.new(className)
			r.Name = name
			r.Parent = folder
		end
		return r
	end
	-- Assert here, like the other three net modules do. Returning nil on a
	-- timeout pushed the failure to whichever line first indexed the remote,
	-- which is a long way from the actual problem.
	local found = folder:WaitForChild(name, 30)
	assert(found, "[Remotes] missing remote " .. name)
	return found
end

-- Client -> Server
Remotes.RequestRoll = remote("RemoteEvent", "RequestRoll")
Remotes.RequestSync = remote("RemoteEvent", "RequestSync")
Remotes.SetAutoRoll = remote("RemoteEvent", "SetAutoRoll")
-- No RequestFuse. There was one, with no server handler and no caller on the
-- client: an unlistened RemoteEvent sitting in ReplicatedStorage for a fuse
-- system that does not exist. It comes back when fusing does.
Remotes.RequestLevelUp = remote("RemoteEvent", "RequestLevelUp")
Remotes.RequestSetDeck = remote("RemoteEvent", "RequestSetDeck")
Remotes.RequestSetActiveDeck = remote("RemoteEvent", "RequestSetActiveDeck")
-- (sfx, music), each 0..1, from the Settings menu's volume bars. Recorded in
-- profile.settings by SettingsService; the client has already applied them.
Remotes.SetAudioSettings = remote("RemoteEvent", "SetAudioSettings")

-- Server -> Client
Remotes.RollResult = remote("RemoteEvent", "RollResult")
Remotes.ProfileSync = remote("RemoteEvent", "ProfileSync")
Remotes.Announce = remote("RemoteEvent", "Announce")

Remotes.RequestTravel = remote("RemoteFunction", "RequestTravel")
-- (code) -> { ok, status, summary }. The Store header's REDEEM A CODE box;
-- CodeService checks it against the server-only CodeConfig.
Remotes.RedeemCode = remote("RemoteFunction", "RedeemCode")

return Remotes
