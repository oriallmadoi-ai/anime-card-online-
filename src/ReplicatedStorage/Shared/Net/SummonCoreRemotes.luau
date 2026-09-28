--!strict
-- Summon Core networking.
--
-- Same shape as MountRemotes / BattleRemotes / SkillRemotes: a feature-scoped
-- module sharing the ONE existing RemoteObjects folder, never touching a remote
-- it does not own.
--
--   Action  a RemoteFunction, because every request needs an answer:
--             ("upgrade", { stageId })          -> ok, { from, to, ... } | reason
--             ("open",    { stageId })          -> ok, result | reason
--             ("give",    { stageId, count })   -> ok, message   (dev only)
--             ("giveall", {})                   -> ok, message   (dev only)
--             ("clear",   {})                   -> ok, message   (dev only)
--           The client only ever names a core it wants to use. It never sends
--           a card, a luck value or a count it owns, so there is nothing to
--           forge: the server decides everything from the saved profile.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "RemoteObjects"

-- See MountRemotes: IsEdit() keeps this module from hanging when it is
-- required outside a running game, and needs a pcall on real clients.
local isEdit = false
pcall(function()
	isEdit = RunService:IsEdit()
end)

local canCreate = RunService:IsServer() or isEdit

local SummonCoreRemotes = {}

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
	assert(folder, "[SummonCoreRemotes] server never created RemoteObjects")
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
	assert(found, "[SummonCoreRemotes] missing remote " .. name)
	return found
end

SummonCoreRemotes.Action = remote("RemoteFunction", "SummonCoreAction") :: RemoteFunction

return SummonCoreRemotes
