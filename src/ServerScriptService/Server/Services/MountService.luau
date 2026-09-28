--!strict
-- Mount ownership, equipping, and the physical bike in the world.
--
-- WHAT THE CLIENT IS AND IS NOT TRUSTED WITH.
-- Ownership, equipping and spawning are decided here: the client asks and this
-- answers. Once a bike exists, its network ownership is handed to the rider so
-- the ride is smooth on their screen - which means the position of the bike is
-- client-authoritative, exactly as a player's own character already is. That is
-- the correct trade for a cosmetic traversal vehicle: the worst a tampered
-- client can do is move its own bike oddly, which it could already do with its
-- own character. Nothing about ownership, unlocks or currency goes near it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MountDefinitions = require(ReplicatedStorage.Shared.Config.MountDefinitions)
local MountRemotes = require(ReplicatedStorage.Shared.Net.MountRemotes)

local MountService = {}
MountService.Name = "MountService"

-- player -> the spawned model. One mount each, always.
local active: { [Player]: Model } = {}

local function log(fmt: string, ...)
	print(("[Mount] " .. fmt):format(...))
end

local function worldFolder(): Folder
	local f = Workspace:FindFirstChild("ActiveMounts")
	if not f then
		f = Instance.new("Folder")
		f.Name = "ActiveMounts"
		f.Parent = Workspace
	end
	return f
end

local function template(def): Model?
	local models = ReplicatedStorage.Shared:FindFirstChild("MountModels")
	local model = models and models:FindFirstChild(def.model)
	return (model and model:IsA("Model")) and model or nil
end

----------------------------------------------------------------
-- OWNERSHIP
----------------------------------------------------------------

function MountService:Owns(player: Player, mountId: string): boolean
	local profile = self.Services.DataService:Get(player)
	return profile ~= nil and (profile.mounts or {})[mountId] == true
end

-- Returns granted, alreadyOwned.
function MountService:Grant(player: Player, mountId: string): (boolean, boolean)
	if not MountDefinitions.exists(mountId) then return false, false end
	local profile = self.Services.DataService:Get(player)
	if not profile then return false, false end
	profile.mounts = profile.mounts or {}
	if profile.mounts[mountId] then return false, true end
	profile.mounts[mountId] = true
	self.Services.DataService:Sync(player)
	log("%s earned %s", player.Name, mountId)
	return true, false
end

-- Called by BattleService the moment an encounter clear is recorded. Returns the
-- list of mount ids newly earned, so the win banner can announce them.
function MountService:GrantForClear(player: Player, encounterId: string, difficulty: string?): { string }
	local earned = {}
	for _, mountId in ipairs(MountDefinitions.grantedBy(encounterId, difficulty)) do
		local granted = self:Grant(player, mountId)
		if granted then table.insert(earned, mountId) end
	end
	return earned
end

----------------------------------------------------------------
-- EQUIP
----------------------------------------------------------------

function MountService:Equip(player: Player, mountId: string?): (boolean, string)
	local profile = self.Services.DataService:Get(player)
	if not profile then return false, "your profile is not ready yet" end

	if mountId == nil then
		profile.equippedMount = nil
		self:Dismiss(player)
		self.Services.DataService:Sync(player)
		return true, "unequipped"
	end

	if not MountDefinitions.exists(mountId) then return false, "unknown mount" end
	if not self:Owns(player, mountId) then return false, "you do not own that mount" end

	-- Swapping while riding would leave the old bike in the world with a rider
	-- welded to it, so the old one is put away first.
	if profile.equippedMount ~= mountId then self:Dismiss(player) end
	profile.equippedMount = mountId
	self.Services.DataService:Sync(player)
	return true, "equipped"
end

----------------------------------------------------------------
-- SUMMON / DISMISS
----------------------------------------------------------------

function MountService:Dismiss(player: Player): boolean
	local model = active[player]
	active[player] = nil
	if not model then return false end

	-- Stand the rider up before the seat goes, or the character is destroyed
	-- along with the weld still attached to it.
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.SeatPart and humanoid.SeatPart:IsDescendantOf(model) then
		humanoid.Sit = false
	end

	if model.Parent then model:Destroy() end
	MountRemotes.State:FireClient(player, { kind = "dismissed" })
	return true
end

function MountService:Summon(player: Player): (boolean, string)
	local profile = self.Services.DataService:Get(player)
	if not profile then return false, "your profile is not ready yet" end

	local mountId = profile.equippedMount
	if not mountId then return false, "equip a mount first" end
	if not self:Owns(player, mountId) then return false, "you do not own that mount" end

	local battle = self.Services.BattleService
	if battle and battle.IsInBattle and battle:IsInBattle(player) then
		return false, "not during a battle"
	end

	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (humanoid and hrp and humanoid.Health > 0) then
		return false, "your character is not ready"
	end

	local def = MountDefinitions.get(mountId)
	local source = def and template(def)
	if not source then return false, "that mount has no model" end

	self:Dismiss(player)

	local model = source:Clone()
	model.Name = ("%s_%s"):format(player.Name, mountId)
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("MountId", mountId)

	local root = model.PrimaryPart
	if not root then model:Destroy(); return false, "that mount has no root part" end

	-- Put it down beside the player, facing the way they are, level with the
	-- ground rather than with whatever the character's pitch happens to be.
	local look = (hrp :: BasePart).CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, -1) end
	local spawnPos = (hrp :: BasePart).Position + flat.Unit * 4
	model:PivotTo(CFrame.lookAt(spawnPos, spawnPos + flat.Unit))
	model.Parent = worldFolder()

	-- The anti-gravity force is sized here rather than in the template, because
	-- assembly mass is only real once the model is in the world.
	local lift = root:FindFirstChild("AntiGravity")
	if lift and lift:IsA("VectorForce") then
		lift.Force = Vector3.new(0, root.AssemblyMass * Workspace.Gravity, 0)
	end

	local seat = model:FindFirstChild("RiderSeat")
	if seat and seat:IsA("VehicleSeat") then
		seat:Sit(humanoid)
	end

	-- Ownership to the rider: this is what makes the ride smooth on their
	-- screen, and what lets their CFrame writes replicate to everyone else.
	pcall(function() root:SetNetworkOwner(player) end)

	active[player] = model
	MountRemotes.State:FireClient(player, { kind = "summoned", mountId = mountId, model = model })
	log("%s summoned %s", player.Name, mountId)
	return true, "summoned"
end

function MountService:IsMounted(player: Player): boolean
	local model = active[player]
	return model ~= nil and model.Parent ~= nil
end

----------------------------------------------------------------
-- LIFECYCLE
----------------------------------------------------------------

function MountService:Init()
	MountRemotes.Action.OnServerInvoke = function(player: Player, action: any, payload: any)
		if type(action) ~= "string" then return false, "bad request" end

		if action == "equip" then
			local id = type(payload) == "table" and payload.mountId or nil
			if id ~= nil and type(id) ~= "string" then return false, "bad request" end
			return self:Equip(player, id)

		elseif action == "unequip" then
			return self:Equip(player, nil)

		elseif action == "summon" then
			return self:Summon(player)

		elseif action == "dismiss" then
			self:Dismiss(player)
			return true, "dismissed"
		end

		return false, "unknown action"
	end

	-- A mount must never outlive the character that was riding it: dying,
	-- respawning, teleporting between maps and leaving all end the ride.
	Players.PlayerAdded:Connect(function(player)
		player.CharacterRemoving:Connect(function() self:Dismiss(player) end)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterRemoving:Connect(function() self:Dismiss(player) end)
	end
	Players.PlayerRemoving:Connect(function(player)
		self:Dismiss(player)
		active[player] = nil
	end)
end

function MountService:Start()
	log("online - %d mount%s defined", #MountDefinitions.Order,
		#MountDefinitions.Order == 1 and "" or "s")
end

return MountService
