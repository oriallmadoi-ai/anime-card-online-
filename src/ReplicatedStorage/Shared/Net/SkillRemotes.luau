--!strict
-- Skill tree networking.
--
-- Follows the same shape as BattleRemotes: a feature-scoped
-- module that shares the ONE existing RemoteObjects folder rather than creating
-- a second one, and never touches remotes it does not own.
--
-- Only two remotes are needed, and deliberately so:
--   Action  a RemoteFunction, because a purchase needs an answer. The client
--           sends a skill id and gets back (ok, reason) - nothing else. It never
--           sends a cost, a rank or an effect, so there is nothing to forge.
--   Result  a RemoteEvent for server-pushed feedback the client did not ask for,
--           such as coins arriving from a battle win.
--
-- The profile itself still replicates through the existing Remotes.ProfileSync;
-- skills and coins live in the profile, so they arrive with it and no separate
-- state channel exists to drift out of sync.

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

local SkillRemotes = {}

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
	assert(folder, "[SkillRemotes] server never created RemoteObjects")
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
	assert(found, "[SkillRemotes] missing remote " .. name)
	return found
end

-- Client -> server. Payload is a skill id and nothing more.
SkillRemotes.Action = remote("RemoteFunction", "SkillAction") :: RemoteFunction

-- Server -> client. Unsolicited feedback: coins earned, purchase confirmations.
SkillRemotes.Result = remote("RemoteEvent", "SkillResult") :: RemoteEvent

return SkillRemotes
