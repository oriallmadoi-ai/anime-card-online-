--!strict
-- Mount networking.
--
-- Same shape as BattleRemotes and SkillRemotes: a feature-scoped module sharing
-- the ONE existing RemoteObjects folder rather than opening a second one, and
-- never touching a remote it does not own.
--
--   Action  a RemoteFunction, because equipping and summoning need an answer.
--           The client sends an action name and a mount id and gets back
--           (ok, reason). It never sends a speed, a position or an ownership
--           claim, so there is nothing to forge.
--   State   server -> client. Says which mount is now spawned for that player
--           and hands over the model, so the controller can take the wheel
--           without having to hunt for it in Workspace.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "RemoteObjects"

-- In Studio's Edit mode IsServer() is false and IsClient() is true, which is
-- backwards from what you would expect. Without the IsEdit() probe this module
-- hangs for 30s and then errors whenever it is required outside a running game.
-- IsEdit() needs plugin capability, so a LocalScript calling it throws - hence
-- the pcall, which simply leaves it false in a real game.
local isEdit = false
pcall(function()
	isEdit = RunService:IsEdit()
end)

local canCreate = RunService:IsServer() or isEdit

local MountRemotes = {}

local netFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net")
local folder: Folder

if canCreate then
	local existing = netFolder:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		if existing then existing:Destroy() end
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = netFolder
	end
else
	folder = netFolder:WaitForChild(FOLDER_NAME, 30) :: Folder
	assert(folder, "[MountRemotes] server never created RemoteObjects")
end

local function remote(className: string, name: string): Instance
	if canCreate then
		local existing = folder:FindFirstChild(name)
		if existing then
			if existing.ClassName == className then return existing end
			existing:Destroy()
		end
		local created = Instance.new(className)
		created.Name = name
		created.Parent = folder
		return created
	end
	local found = folder:WaitForChild(name, 30)
	assert(found, "[MountRemotes] missing remote " .. name)
	return found
end

MountRemotes.Action = remote("RemoteFunction", "MountAction") :: RemoteFunction
MountRemotes.State = remote("RemoteEvent", "MountState") :: RemoteEvent

return MountRemotes
