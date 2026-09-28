--!strict
-- Additive battle networking for Anime Card Online.
-- Uses the SAME ReplicatedStorage.Shared.Net.RemoteObjects folder as the
-- existing Remotes module, but does not modify or replace any existing remote.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "RemoteObjects"

local isEdit = false
pcall(function()
	isEdit = RunService:IsEdit()
end)

local canCreate = RunService:IsServer() or isEdit
local BattleRemotes = {}

local netFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net")
local folder: Folder

if canCreate then
	local existing = netFolder:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		if existing then
			existing:Destroy()
		end
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = netFolder
	end
else
	folder = netFolder:WaitForChild(FOLDER_NAME, 30) :: Folder
	assert(folder, "[BattleRemotes] server never created RemoteObjects")
end

local function remote(className: string, name: string): Instance
	if canCreate then
		local existing = folder:FindFirstChild(name)
		if existing then
			if existing.ClassName == className then
				return existing
			end
			existing:Destroy()
		end

		local created = Instance.new(className)
		created.Name = name
		created.Parent = folder
		return created
	end

	local found = folder:WaitForChild(name, 30)
	assert(found, "[BattleRemotes] missing remote " .. name)
	return found
end

-- Client -> server request/response. The server validates every action.
BattleRemotes.Action = remote("RemoteFunction", "BattleAction") :: RemoteFunction

-- Server -> client full authoritative snapshots for resync/reconciliation.
BattleRemotes.State = remote("RemoteEvent", "BattleState") :: RemoteEvent

-- Server -> client small chronological animation/gameplay events.
BattleRemotes.Event = remote("RemoteEvent", "BattleEvent") :: RemoteEvent

return BattleRemotes
