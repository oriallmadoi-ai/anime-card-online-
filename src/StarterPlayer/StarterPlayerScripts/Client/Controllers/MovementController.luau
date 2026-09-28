--!nonstrict
-- Sprint and dash.
--
--   Shift (hold)  sprint - faster walk, sprint animation, dust at the feet
--   Q             dash   - a burst the way you are moving (or facing), with
--                          the dash animation and a trail
-- The camera is never touched: no zoom, no screen effects.
--   Mobile        a RUN toggle button and a DASH button
--
-- Neither works while riding a mount. There is no stamina and no cooldown; a
-- dash only has to finish (DashTime) before the next one can start.
--
-- Shift lock is turned off for the game (StarterPlayer.EnableMouseLockOption)
-- because Shift is the sprint key.

local ContextActionService = game:GetService("ContextActionService")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config.MovementConfig)

local MovementController = {}
MovementController.Name = "MovementController"

local player = Players.LocalPlayer

local DOT = "rbxassetid://109042378477283" -- the soft white dot the encounters use

local character, humanoid, root, animator
local tracks = {}
local sprintHeld = false
local sprinting = false
local baseSpeed = nil
local dashing = false
local fx = {}

----------------------------------------------------------------------
-- animations
----------------------------------------------------------------------

-- The published id if there is one; in Studio, the local KeyframeSequence
-- registered on the fly so the moves can be tried before they are uploaded.
local function animationId(kind: string): string?
	local id = Config[kind .. "AnimationId"]
	if type(id) == "string" and id ~= "" then return id end
	if RunService:IsStudio() then
		local folder = ReplicatedStorage.Shared:FindFirstChild("Animations")
		local kfs = folder and folder:FindFirstChild(kind)
		if kfs then
			local ok, temp = pcall(function()
				return KeyframeSequenceProvider:RegisterKeyframeSequence(kfs)
			end)
			if ok then return temp end
		end
	end
	return nil
end

local function loadTracks()
	table.clear(tracks)
	if not animator then return end
	for _, kind in ipairs({ "Sprint", "Dash" }) do
		local id = animationId(kind)
		if id then
			local anim = Instance.new("Animation")
			anim.AnimationId = id
			local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
			if ok and track then
				track.Priority = kind == "Sprint" and Enum.AnimationPriority.Movement or Enum.AnimationPriority.Action
				track.Looped = kind == "Sprint"
				tracks[kind] = track
			end
		end
	end
end

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------

local function isMounted(): boolean
	local mounts = MovementController.Controllers and MovementController.Controllers.MountController
	if mounts and mounts.IsMounted then
		local ok, value = pcall(function() return mounts:IsMounted() end)
		return ok and value == true
	end
	return false
end


----------------------------------------------------------------------
-- effects: a trail and a dust emitter on the character, speed lines on screen
----------------------------------------------------------------------

local function buildCharacterFx()
	fx = {}
	if not root then return end
	local top = Instance.new("Attachment") top.Name = "DashTrailTop" top.Position = Vector3.new(0, 1.1, 0.4) top.Parent = root
	local bottom = Instance.new("Attachment") bottom.Name = "DashTrailBottom" bottom.Position = Vector3.new(0, -1.3, 0.4) bottom.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "DashTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.18
	trail.MinLength = 0.05
	trail.LightEmission = 0.6
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(Color3.fromRGB(235, 245, 255), Color3.fromRGB(150, 205, 255))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	trail.Enabled = false
	trail.Parent = root
	fx.trail = trail

	local feet = Instance.new("Attachment") feet.Name = "MoveDust" feet.Position = Vector3.new(0, -2.9, 0.3) feet.Parent = root
	local dust = Instance.new("ParticleEmitter")
	dust.Name = "SprintDust"
	dust.Texture = DOT
	dust.Color = ColorSequence.new(Color3.fromRGB(235, 228, 210))
	dust.LightInfluence = 1
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1.4) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(0.35, 0.6)
	dust.Speed = NumberRange.new(1.5, 3)
	dust.SpreadAngle = Vector2.new(35, 35)
	dust.EmissionDirection = Enum.NormalId.Back
	dust.Acceleration = Vector3.new(0, 2, 0)
	dust.Drag = 3
	dust.Rate = 0
	dust.Parent = feet
	fx.dust = dust
end


----------------------------------------------------------------------
-- sprint
----------------------------------------------------------------------

-- WalkSpeed is stored as a 32-bit float, so 16 * 1.65 reads back as
-- 26.3999996. Every "is it still our speed" check has to allow for that, or the
-- sprint would think someone else changed it and stack on itself.
local function sprintSpeed(): number
	return (baseSpeed or 16) * Config.SprintSpeedMultiplier
end
local function isOurSpeed(): boolean
	return humanoid ~= nil and baseSpeed ~= nil and math.abs(humanoid.WalkSpeed - sprintSpeed()) < 0.05
end

local function stopSprint()
	if not sprinting then return end
	sprinting = false
	if isOurSpeed() then
		humanoid.WalkSpeed = baseSpeed
	end
	baseSpeed = nil
end

local function update()
	if not (humanoid and root) or humanoid.Health <= 0 then return end

	local mounted = isMounted()
	local moving = humanoid.MoveDirection.Magnitude > 0.1
	local want = sprintHeld and moving and not mounted and not humanoid.Sit

	if sprinting and not isOurSpeed() then
		-- Something else changed the walk speed (a battle freeze, a mount...).
		-- Let it win: forget the sprint without restoring over it.
		sprinting = false
		baseSpeed = nil
	end

	if want and not sprinting and humanoid.WalkSpeed > 0 and humanoid.WalkSpeed <= 40 then
		sprinting = true
		baseSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = baseSpeed * Config.SprintSpeedMultiplier
	elseif not want and sprinting then
		stopSprint()
	end

	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	local track = tracks.Sprint
	if track then
		if sprinting and grounded and not dashing then
			if not track.IsPlaying then track:Play(0.2) end
			local target = (baseSpeed or 16) * Config.SprintSpeedMultiplier
			local flat = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
			track:AdjustSpeed(math.clamp(flat / math.max(target, 1), 0.7, 1.3))
		elseif track.IsPlaying then
			track:Stop(0.2)
		end
	end
	if fx.dust then
		fx.dust.Rate = (sprinting and grounded and not dashing) and 14 or 0
	end
end

----------------------------------------------------------------------
-- dash
----------------------------------------------------------------------

local function dash()
	if dashing or not (humanoid and root) or humanoid.Health <= 0 then return end
	if isMounted() or humanoid.Sit then return end

	local dir = humanoid.MoveDirection
	if dir.Magnitude < 0.1 then dir = root.CFrame.LookVector end
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.01 then return end
	dir = dir.Unit

	dashing = true
	-- Face the way the dash goes, so the pose reads as a lunge, not a slide.
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)

	local attachment = Instance.new("Attachment")
	attachment.Name = "DashDrive"
	attachment.Parent = root
	local drive = Instance.new("LinearVelocity")
	drive.Name = "DashDrive"
	drive.Attachment0 = attachment
	drive.RelativeTo = Enum.ActuatorRelativeTo.World
	drive.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	-- Nothing on Y: gravity and jumps carry on as normal mid-dash.
	drive.MaxAxesForce = Vector3.new(1e6, 0, 1e6)
	drive.VectorVelocity = dir * Config.DashSpeed
	drive.Parent = root

	if tracks.Sprint and tracks.Sprint.IsPlaying then tracks.Sprint:Stop(0.05) end
	if tracks.Dash then tracks.Dash:Play(0.05) end

	if fx.trail then fx.trail.Enabled = true end
	if fx.dust then fx.dust:Emit(10) end

	task.delay(Config.DashTime, function()
		drive:Destroy()
		attachment:Destroy()
		-- Bleed the burst off rather than stopping dead.
		if root and root.Parent then
			local v = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(v.X * 0.35, v.Y, v.Z * 0.35)
		end
		task.delay(0.12, function()
			if fx.trail then fx.trail.Enabled = false end
		end)
		dashing = false
	end)
end

----------------------------------------------------------------------
-- character + input
----------------------------------------------------------------------

local function onCharacter(char: Model)
	character = char
	humanoid = char:WaitForChild("Humanoid", 10)
	root = char:WaitForChild("HumanoidRootPart", 10)
	if not (humanoid and root) then return end
	animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 5)
	sprinting, dashing, baseSpeed = false, false, nil
	loadTracks()
	buildCharacterFx()
end

function MovementController:Init()

	ContextActionService:BindAction("Sprint", function(_, state, input)
		if input.UserInputType == Enum.UserInputType.Touch then
			-- the mobile button is a toggle
			if state == Enum.UserInputState.Begin then
				sprintHeld = not sprintHeld
				ContextActionService:SetTitle("Sprint", sprintHeld and "RUN ON" or "RUN")
			end
		else
			if state == Enum.UserInputState.Begin then
				sprintHeld = true
			elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				sprintHeld = false
			end
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL3)
	ContextActionService:SetTitle("Sprint", "RUN")
	ContextActionService:SetPosition("Sprint", UDim2.new(1, -150, 1, -150))

	ContextActionService:BindAction("Dash", function(_, state)
		if state == Enum.UserInputState.Begin then dash() end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonR1)
	ContextActionService:SetTitle("Dash", "DASH")
	ContextActionService:SetPosition("Dash", UDim2.new(1, -95, 1, -210))

	if player.Character then task.spawn(onCharacter, player.Character) end
	player.CharacterAdded:Connect(onCharacter)
	RunService.Heartbeat:Connect(update)
end

return MovementController
