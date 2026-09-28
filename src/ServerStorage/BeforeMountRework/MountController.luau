--!strict
-- Riding a mount.
--
-- R summons the equipped mount and puts the player on it. R again gets off.
--
-- HOW IT MOVES, AND WHY NOT WITH WHEELS.
-- This is KINEMATIC, not a physics vehicle. Every frame the controller decides
-- where the bike should be and writes that CFrame, rather than applying torque
-- to wheels and hoping. Roblox wheel physics on a 12-stud model would give
-- suspension bounce, a bike that flips on its side, and a different ride on
-- every framerate - all of which read as jank rather than as speed. The trade
-- is that the tyres do not really turn, which nobody can see at 64 studs/sec.
--
-- THE RULE THAT KEEPS IT SMOOTH: physics is never left to argue with the
-- writes. The bike is one rigid welded assembly with no competing constraints,
-- its gravity is cancelled by a VectorForce so nothing accumulates downward
-- between frames, and the velocity is set to match the motion actually applied.
-- Anything that skips that turns into the jitter the old Rocket had.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local MountDefinitions = require(ReplicatedStorage.Shared.Config.MountDefinitions)
local MountRemotes = require(ReplicatedStorage.Shared.Net.MountRemotes)

local MountController = {}
MountController.Name = "MountController"

local player = Players.LocalPlayer

local ACTION = "MountToggle"
local KEY = Enum.KeyCode.R

-- Below this the bike is considered to have left the world. Matches the sort of
-- depth the game's own void failsafe uses; the point is only that it is far
-- enough down to be unambiguous, not a number anyone tunes.
local VOID_Y = -150

local character: Model? = nil
local humanoid: Humanoid? = nil

local model: Model? = nil
local root: BasePart? = nil
local seat: VehicleSeat? = nil
local def: any = nil

local driving = false
local busy = false
local speed = 0            -- studs/sec along the bike's own forward axis
local heading = 0          -- radians, world Y
local lean = 0             -- degrees, smoothed
local pitch = 0            -- radians, smoothed slope
local steerSmooth = 0      -- -1..1, the steering input after ramping
local driveConn: RBXScriptConnection? = nil

-- Emitters are collected once at summon rather than searched for every frame.
--
-- Each carries its own BaseRate attribute and the controller only supplies an
-- INTENSITY, 0 to about 1.3. That way the cola spray, the foam fizz and the
-- tyre smoke can all sit at wildly different particle counts - foam needs many
-- more than spray to read as fizz - while still answering one throttle number.
type FXEntry = { e: ParticleEmitter, base: number }
local exhaustFX: { FXEntry } = {}
local tyreFX: { FXEntry } = {}

-- Forward declaration. The drive loop calls setFX on its last line, but setFX
-- needs the emitter buckets and is defined further down next to collectFX. Left
-- undeclared here, `setFX` inside the loop compiles as a GLOBAL read, resolves
-- to nil at runtime, and throws once per frame from inside a Heartbeat - which
-- does not stop the bike moving, so the only symptom is that no particle ever
-- appears and the output fills up.
local setFX: (number, number) -> ()

local function log(fmt: string, ...)
	print(("[Mount] " .. fmt):format(...))
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * math.clamp(t, 0, 1)
end

-- KEEP THE CAMERA ON THE RIDER, NOT ON THE SEAT.
--
-- Roblox repoints Camera.CameraSubject at the seat part the instant a humanoid
-- sits down. For a car that is what you want. Here the seat is welded to the
-- bike, so the camera inherits the bike's ROTATION and spins bodily with every
-- turn - the player cannot look around any more, and a corner whips the whole
-- view round with it. Measured: through a full 360 the camera's yaw tracked the
-- bike's to a fixed 16 degrees, which is the camera being bolted to the frame.
--
-- Pointing it back at the humanoid keeps the camera FOLLOWING the bike (the
-- rider is welded to it, so the position comes along) while leaving yaw and
-- pitch where the player put them. Re-checked every frame, because the seating
-- that causes it can happen more than once.
local function holdCameraOnRider()
	local cam = Workspace.CurrentCamera
	if cam and humanoid and humanoid.Parent and cam.CameraSubject ~= humanoid then
		cam.CameraSubject = humanoid
	end
end

-- STEERING AND THROTTLE, READ FROM THREE PLACES AND COMBINED.
--
-- A VehicleSeat is supposed to publish ThrottleFloat and SteerFloat for us, and
-- on a real client it does. It is not relied on alone, because it is written by
-- Roblox's own VehicleController through the InputAction system, and anything
-- that does not feed that system - a different control scheme, an automated
-- test, a future PlayerModule change - leaves both floats stuck at zero and the
-- bike refusing to move with no error to show for it.
--
-- So: keyboard and gamepad are read directly, and the seat's floats are taken
-- as well. Whichever gives a signal wins. The seat is what covers the mobile
-- thumbstick, where there are no keys to poll.
local function readControls(s: VehicleSeat): (number, number)
	local throttle, steer = 0, 0

	if UserInputService.KeyboardEnabled then
		if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then throttle += 1 end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then throttle -= 1 end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then steer += 1 end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then steer -= 1 end
	end

	if UserInputService.GamepadEnabled and (throttle == 0 or steer == 0) then
		local ok, states = pcall(function()
			return UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)
		end)
		if ok and states then
			for _, input in ipairs(states) do
				if input.KeyCode == Enum.KeyCode.Thumbstick1 then
					local p = input.Position
					-- Deadzone: a resting stick reports small non-zero values and
					-- would creep the bike forward on its own.
					if throttle == 0 and math.abs(p.Y) > 0.15 then throttle = p.Y end
					if steer == 0 and math.abs(p.X) > 0.15 then steer = p.X end
				end
			end
		end
	end

	if throttle == 0 then throttle = s.ThrottleFloat ~= 0 and s.ThrottleFloat or s.Throttle end
	if steer == 0 then steer = s.SteerFloat ~= 0 and s.SteerFloat or s.Steer end

	return math.clamp(throttle, -1, 1), math.clamp(steer, -1, 1)
end

-- Everything the bike must not collide with or stand on: itself, and the rider
-- welded to it.
local function rayParams(): RaycastParams
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	if model then table.insert(ignore, model) end
	if character then table.insert(ignore, character) end
	local mounts = Workspace:FindFirstChild("ActiveMounts")
	if mounts then table.insert(ignore, mounts) end
	p.FilterDescendantsInstances = ignore
	p.IgnoreWater = false
	return p
end

----------------------------------------------------------------
-- THE DRIVE LOOP
----------------------------------------------------------------

local function stopDriving()
	if driveConn then
		driveConn:Disconnect()
		driveConn = nil
	end
	driving = false
	speed = 0
	lean = 0
	pitch = 0
	steerSmooth = 0
end

local function step(dt: number)
	if not (driving and model and root and seat and def) then return end
	if not model.Parent then stopDriving() return end

	local r = root :: BasePart
	local s = seat :: VehicleSeat

	-- Guard against a long hitch: a 0.5s frame would otherwise teleport the
	-- bike half a map forward in one step.
	dt = math.min(dt, 1 / 20)

	local walk = (humanoid and humanoid.WalkSpeed > 0) and humanoid.WalkSpeed or nil
	local top = MountDefinitions.topSpeed(def.id, walk)

	local throttle, steer = readControls(s)

	-- SPEED. Accelerating, braking and coasting are three different rates: a
	-- single lerp toward a target makes the bike feel like it is on a rubber
	-- band rather than like it has an engine.
	local target = throttle > 0 and top * throttle
		or throttle < 0 and top * def.ReverseMultiplier * throttle
		or 0
	local rate
	if math.abs(throttle) < 0.05 then
		rate = def.CoastDrag
	elseif (speed > 0 and throttle < 0) or (speed < 0 and throttle > 0) then
		rate = def.Braking
	else
		rate = def.Acceleration
	end
	if speed < target then
		speed = math.min(target, speed + rate * dt)
	else
		speed = math.max(target, speed - rate * dt)
	end
	if math.abs(speed) < 0.4 and math.abs(throttle) < 0.05 then speed = 0 end

	-- STEERING.
	--
	-- The raw input is a key: down or up, nothing between. Ramping it makes the
	-- bike lean into a turn over about a tenth of a second instead of snapping
	-- to full lock on one frame, which is most of what separates "responsive"
	-- from "twitchy" - and it costs nothing in how fast it actually answers.
	steerSmooth = lerp(steerSmooth, steer, (def.SteerSmoothing or 11) * dt)
	if math.abs(steerSmooth) < 0.01 then steerSmooth = 0 end

	-- Turn authority still falls off with speed so it cannot spin on the spot,
	-- but both rates are a mount's rather than a racer's: tight enough to come
	-- about inside a courtyard rather than needing the whole map.
	local speedFraction = math.clamp(math.abs(speed) / math.max(top, 1), 0, 1)
	local turnDegrees = lerp(def.TurnRate, def.TurnRateAtSpeed, speedFraction)
	local steerAuthority = math.clamp(math.abs(speed) / (def.SteerFullSpeed or 4), 0, 1)
	local direction = speed < 0 and -1 or 1
	heading -= math.rad(turnDegrees) * steerSmooth * steerAuthority * direction * dt

	-- GROUND. A raycast, not suspension. The bike is held at a fixed ride
	-- height above whatever is underneath, and tilts to match the slope.
	local params = rayParams()
	local probeFrom = r.Position + Vector3.new(0, def.RideHeight, 0)
	local ground = Workspace:Raycast(probeFrom, Vector3.new(0, -(def.GroundProbe + def.RideHeight), 0), params)

	local targetY = r.Position.Y
	local normal = Vector3.new(0, 1, 0)
	if ground then
		targetY = ground.Position.Y + def.RideHeight
		normal = ground.Normal
	else
		-- Nothing underneath: fall, but at a readable rate rather than at
		-- Roblox's 196 studs/s^2.
		targetY = r.Position.Y - 60 * dt

		-- Ride off the edge of the map and the bike would otherwise fall for
		-- ever, with the rider welded to it and no way off. Below the void line
		-- the ride ends and the character is handed back to the normal respawn.
		if r.Position.Y < VOID_Y then
			log("fell out of the world - ending the ride")
			stopDriving()
			setFX(0, 0)
			task.spawn(function() MountController:Dismount() end)
			return
		end
	end

	-- WALLS. A forward probe sized to this frame's travel, so the bike cannot
	-- tunnel through a wall between two frames at speed.
	local forward = (CFrame.Angles(0, heading, 0)).LookVector
	local travel = speed * dt
	if math.abs(travel) > 0.01 then
		local dir = travel > 0 and forward or -forward
		local probe = math.abs(travel) + 2.6
		local hit = Workspace:Raycast(r.Position + Vector3.new(0, 0.4, 0), dir * probe, params)
		if hit and hit.Normal.Y < 0.55 then
			-- A wall, not a ramp. Stop rather than bounce: a bounce at this speed
			-- reads as being shot backwards by nothing.
			speed = 0
			travel = 0
		end
	end

	-- SLOPE. Too steep to climb is a wall as far as the bike is concerned.
	local slope = math.deg(math.acos(math.clamp(normal.Y, -1, 1)))
	if slope > def.MaxClimbAngle and travel > 0 then
		travel = 0
		speed = math.max(0, speed - def.Braking * dt)
	end

	-- POSE. Heading is authoritative; the slope tilt and the cornering lean are
	-- smoothed on top so neither snaps.
	local targetPitch = 0
	if ground then
		-- Signed angle of the ground along the direction of travel.
		local alongSlope = normal:Dot(forward)
		targetPitch = math.asin(math.clamp(alongSlope, -1, 1))
	end
	pitch = lerp(pitch, targetPitch, def.PitchSmoothing * dt)
	lean = lerp(lean, -def.LeanAngle * steerSmooth * speedFraction * direction, 8 * dt)

	local position = r.Position + forward * travel
	position = Vector3.new(position.X, lerp(r.Position.Y, targetY, 14 * dt), position.Z)

	local cf = CFrame.new(position)
		* CFrame.Angles(0, heading, 0)
		* CFrame.Angles(pitch, 0, math.rad(lean))

	-- THE CFRAME IS THE ONLY THING THAT MOVES THE BIKE. Both velocities are
	-- zeroed, every frame, on purpose.
	--
	-- Setting the velocity to `forward * speed` as well seems reasonable - keep
	-- the solver's idea of the motion in step with ours - and is wrong: the
	-- solver then integrates that velocity over the frame IN ADDITION to the
	-- CFrame we just wrote, so the bike covers the distance twice and runs at
	-- double the configured top speed. Worse, the physics displacement partly
	-- overrides the CFrame, so the heading written here never takes and the bike
	-- will not steer at all. Zero velocity is what makes this body kinematic
	-- rather than half-simulated.
	r.CFrame = cf
	r.AssemblyLinearVelocity = Vector3.zero
	r.AssemblyAngularVelocity = Vector3.zero

	holdCameraOnRider()

	-- EFFECTS. The exhaust answers the THROTTLE, so the cola surges the moment
	-- the rider pulls away and drops to a lazy idle fizz when coasting. The
	-- tyres answer SPEED and STEERING, so they only kick up when there is
	-- something to kick up, and hardest mid-corner where a bike scrubs.
	local exhaustIntensity = 0.14 + math.abs(throttle) * 0.8 + speedFraction * 0.22
	local tyreIntensity = 0
	if ground then
		tyreIntensity = speedFraction * 0.85 + math.abs(steerSmooth) * speedFraction * 1.1
	end
	setFX(exhaustIntensity, math.clamp(tyreIntensity, 0, 1.5))
end

local function startDriving()
	stopDriving()
	if not (model and root) then return end
	driving = true
	heading = math.atan2(-(root :: BasePart).CFrame.LookVector.X, -(root :: BasePart).CFrame.LookVector.Z)
	speed = 0
	driveConn = RunService.Heartbeat:Connect(step)
end

----------------------------------------------------------------
-- MOUNT / DISMOUNT
----------------------------------------------------------------

local function collectFX()
	table.clear(exhaustFX)
	table.clear(tyreFX)
	if not root then return end
	for _, a in ipairs((root :: BasePart):GetChildren()) do
		if a:IsA("Attachment") then
			local bucket = nil
			if a.Name:find("^Exhaust") then
				bucket = exhaustFX
			elseif a.Name:find("^Wheel") then
				bucket = tyreFX
			end
			if bucket then
				-- Every emitter under the attachment, not just the first: an
				-- exhaust is a spray AND a foam, and finding one of them would
				-- leave the other running flat out for the whole ride.
				for _, e in ipairs(a:GetChildren()) do
					if e:IsA("ParticleEmitter") then
						local base = e:GetAttribute("BaseRate")
						table.insert(bucket, {
							e = e,
							base = (type(base) == "number" and base > 0) and base or 20,
						})
					end
				end
			end
		end
	end
end

local function applyFX(bucket: { FXEntry }, intensity: number)
	local on = intensity > 0.01
	for _, entry in ipairs(bucket) do
		entry.e.Rate = entry.base * intensity
		entry.e.Enabled = on
	end
end

function setFX(exhaustIntensity: number, tyreIntensity: number)
	applyFX(exhaustFX, exhaustIntensity)
	applyFX(tyreFX, tyreIntensity)
end

local function clearMount()
	stopDriving()
	setFX(0, 0)
	table.clear(exhaustFX)
	table.clear(tyreFX)
	model, root, seat, def = nil, nil, nil, nil
	-- The humanoid is the default subject anyway, but the seat may still be the
	-- one set if the ride ended between frames.
	holdCameraOnRider()
end

function MountController:Dismount()
	if busy then return end
	busy = true

	-- Put the rider down beside the bike before it goes, so they do not drop
	-- through the floor from wherever the seat happened to be.
	local placement: CFrame? = nil
	if model and root and def then
		local r = root :: BasePart
		local off = def.DismountOffset
		placement = r.CFrame * CFrame.new(off.X, off.Y, off.Z)
	end

	if humanoid then humanoid.Sit = false end

	local ok = pcall(function()
		return MountRemotes.Action:InvokeServer("dismiss", {})
	end)
	if not ok then log("dismiss request failed") end

	clearMount()

	if placement and character then
		task.defer(function()
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") then
				hrp.CFrame = CFrame.new((placement :: CFrame).Position)
					* CFrame.Angles(0, heading, 0)
			end
		end)
	end

	busy = false
end

function MountController:Summon()
	if busy then return end
	busy = true

	local ok, approved, reason = pcall(function()
		return MountRemotes.Action:InvokeServer("summon", {})
	end)
	busy = false

	if not ok then
		log("summon request failed")
		return
	end
	if not approved then
		log("summon refused: %s", tostring(reason))
		local ui = self.Controllers and self.Controllers.UIController
		if ui and ui.Toast then ui:Toast(tostring(reason)) end
	end
end

function MountController:Toggle()
	if model and model.Parent then
		self:Dismount()
	else
		self:Summon()
	end
end

function MountController:IsMounted(): boolean
	return model ~= nil and model.Parent ~= nil
end

----------------------------------------------------------------
-- LIFECYCLE
----------------------------------------------------------------

local function bindCharacter(char: Model)
	character = char
	humanoid = char:WaitForChild("Humanoid", 10) :: Humanoid
	clearMount()
end

function MountController:Init()
	if player.Character then bindCharacter(player.Character) end
	player.CharacterAdded:Connect(bindCharacter)
	player.CharacterRemoving:Connect(function() clearMount() end)

	MountRemotes.State.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then return end

		if payload.kind == "summoned" then
			local m = payload.model
			if typeof(m) ~= "Instance" or not m:IsA("Model") then return end
			model = m
			root = m.PrimaryPart or m:FindFirstChild("Root") :: BasePart
			seat = m:FindFirstChild("RiderSeat") :: VehicleSeat
			def = MountDefinitions.get(payload.mountId)
			collectFX()
			if not (root and seat and def) then
				log("summoned model is missing its rig")
				clearMount()
				return
			end

			-- Wait for the seat weld: driving before the rider is actually on
			-- the bike drives the bike out from under them.
			task.spawn(function()
				local deadline = os.clock() + 2
				while os.clock() < deadline do
					if humanoid and humanoid.SeatPart == seat then break end
					RunService.Heartbeat:Wait()
				end
				if model and model.Parent then startDriving() end
			end)

		elseif payload.kind == "dismissed" then
			clearMount()
		end
	end)

	-- The seat letting go for any reason the controller did not cause - death,
	-- a respawn, a teleport - ends the ride rather than leaving a ghost bike.
	RunService.Heartbeat:Connect(function()
		if driving and humanoid and seat and humanoid.SeatPart ~= seat then
			stopDriving()
			setFX(0, 0)
		end
	end)

	ContextActionService:BindAction(ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			self:Toggle()
		end
		return Enum.ContextActionResult.Pass
	end, false, KEY)
end

function MountController:Start()
	log("online - press R to summon an equipped mount")
end

return MountController
