--!strict
-- VoidFailsafe  (Script, RunContext = Server)
-- Workspace.ArlongPark.MapBoundaries.VoidFailsafe
--
-- Safety net only: returns anyone who ends up under the island to
-- ArrivalPad_ArlongPark. Event driven off the catcher's Touched, no polling.

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local catcher  = script.Parent:WaitForChild("VoidCatcher")
local PAD_NAME = "ArrivalPad_ArlongPark"
local RESCUE_HEIGHT = 4
local COOLDOWN = 1.5

local recent: { [Player]: number } = {}

local function findPad(): BasePart?
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == PAD_NAME then return d end
	end
	return nil
end

local function rescue(character: Model)
	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end
	local now = os.clock()
	if recent[player] and now - recent[player] < COOLDOWN then return end
	recent[player] = now

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	local pad = findPad()
	if not pad then warn("[VoidFailsafe] no " .. PAD_NAME .. " in Workspace") return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end

	character:PivotTo(
		CFrame.new(pad.Position + Vector3.new(0, RESCUE_HEIGHT, 0))
			* (pad.CFrame - pad.CFrame.Position)
	)
	root.AssemblyLinearVelocity  = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

catcher.Touched:Connect(function(hit)
	local character = hit:FindFirstAncestorOfClass("Model")
	if character and character:FindFirstChildOfClass("Humanoid") then rescue(character) end
end)

Players.PlayerRemoving:Connect(function(player) recent[player] = nil end)

print("[VoidFailsafe] armed")
