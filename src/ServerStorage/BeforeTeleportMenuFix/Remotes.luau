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

local folder
if canCreate then
	folder = ReplicatedStorage.Shared.Net:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage.Shared.Net
	end
else
	folder = ReplicatedStorage.Shared.Net:WaitForChild(FOLDER_NAME, 30)
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
	return folder:WaitForChild(name, 30)
end

-- Client -> Server
Remotes.RequestRoll = remote("RemoteEvent", "RequestRoll")
Remotes.RequestSync = remote("RemoteEvent", "RequestSync")
Remotes.SetAutoRoll = remote("RemoteEvent", "SetAutoRoll")
Remotes.RequestFuse = remote("RemoteEvent", "RequestFuse")
Remotes.RequestLevelUp = remote("RemoteEvent", "RequestLevelUp")
Remotes.RequestSetDeck = remote("RemoteEvent", "RequestSetDeck")
Remotes.RequestSetActiveDeck = remote("RemoteEvent", "RequestSetActiveDeck")

-- Server -> Client
Remotes.RollResult = remote("RemoteEvent", "RollResult")
Remotes.ProfileSync = remote("RemoteEvent", "ProfileSync")
Remotes.Announce = remote("RemoteEvent", "Announce")

return Remotes
