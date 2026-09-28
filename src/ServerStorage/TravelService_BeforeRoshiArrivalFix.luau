--!strict
-- Moves players between locations in this place.
--
-- DELIBERATELY GENERIC. Nothing here mentions Arlong Park: a portal declares
-- where it goes with a `TravelTo` attribute, and the destination is looked up
-- by finding a part named `ArrivalPad_<destination>`. Adding an island later is
-- a builder task - place a pad, place a portal, set the attribute - with no
-- code change. The Teleport menu can call Travel() with a name too.
--
-- Runs entirely on the SERVER. ProximityPromptService fires server-side, so a
-- client cannot ask to be moved somewhere it has not earned; if travel ever
-- needs a requirement (a level, a quest, a key item) it is checked here.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")

local TravelService = {}
TravelService.Name = "TravelService"

local PAD_PREFIX = "ArrivalPad_"
local ARRIVAL_HEIGHT = 4        -- studs above the pad, so nobody spawns inside it

-- Guards against a player re-triggering mid-teleport, which would otherwise
-- fight the CFrame set and can drop a character through the floor.
local travelling: { [Player]: boolean } = {}

local function findPad(destination: string): BasePart?
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == PAD_PREFIX .. destination then
			return d
		end
	end
	return nil
end

function TravelService:Travel(player: Player, destination: string): (boolean, string)
	if travelling[player] then return false, "already travelling" end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return false, "no character" end

	local pad = findPad(destination)
	if not pad then
		warn(("[TravelService] no %s%s in Workspace"):format(PAD_PREFIX, destination))
		return false, "unknown destination"
	end

	travelling[player] = true

	-- Face the same way the pad faces, so arrival never has the player staring
	-- at a wall.
	local target = CFrame.new(pad.Position + Vector3.new(0, ARRIVAL_HEIGHT, 0))
		* (pad.CFrame - pad.CFrame.Position)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Cancel momentum, or the player keeps their pre-teleport velocity and
		-- slides off the arrival pad.
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	character:PivotTo(target)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	task.delay(0.6, function() travelling[player] = nil end)
	return true, destination
end

function TravelService:Init()
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		local holder = prompt.Parent
		local destination = holder and holder:GetAttribute("TravelTo")
		if typeof(destination) ~= "string" then return end

		local ok, reason = self:Travel(player, destination)
		if not ok then
			warn(("[TravelService] %s -> %s failed: %s")
				:format(player.Name, destination, tostring(reason)))
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		travelling[player] = nil
	end)

	print("[TravelService] online")
end

return TravelService
