--!strict
-- Top-down map camera for the skill board: drag to pan, wheel or pinch to zoom.
--
-- "Almost 2D" is a NARROW FIELD OF VIEW FROM A LONG WAY BACK. Roblox has no
-- orthographic camera, so perspective is instead flattened by shrinking the FOV
-- and pushing the camera far away - the same trick a telephoto lens plays.
--
-- TWO THINGS THAT BITE HERE
-- 1. CFrame.lookAt straight down is DEGENERATE. Looking along -Y with the
--    default up vector of +Y leaves the roll undefined and the camera flips or
--    spins unpredictably. An explicit up vector is mandatory, and -Z is what
--    makes "down the board" mean "down the screen".
-- 2. Panning must be in STUDS PER PIXEL, computed from the current height and
--    FOV. A fixed sensitivity feels wrong at every zoom except the one it was
--    tuned at; this way the board tracks the cursor exactly at any zoom.

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local SkillTreeCamera = {}
SkillTreeCamera.__index = SkillTreeCamera

local FOV = 24
local ZOOM_LERP = 9      -- higher = snappier; this is a per-second rate
local PAN_LERP = 18
local WHEEL_STEP = 0.16  -- fraction of current height per wheel notch

-- Screen-up on the board is -Z, so the +Y axis of SkillDefinitions.Position
-- (which runs "down" the board) also runs down the screen.
local UP = Vector3.new(0, 0, -1)

function SkillTreeCamera.new(board)
	local self = setmetatable({}, SkillTreeCamera)

	self.board = board
	self.camera = Workspace.CurrentCamera
	self.active = false
	self.connections = {}
	self.dragging = false
	self.dragFrom = nil

	-- Focus point on the board, in world space. Height is the camera's distance
	-- straight up from it.
	self.target = Vector3.new(board.centre.X, board.centre.Y, board.centre.Z)
	self.goalTarget = self.target

	self:_computeZoomRange()
	-- Opens showing the WHOLE board. Starting part-way in meant the root and the
	-- capstone were both off screen on the first frame, which reads as the tree
	-- being broken rather than as there being more to see.
	self.height = self.maxHeight
	self.goalHeight = self.height

	return self
end

-- The zoom limits come from the tree itself, so a board that grows keeps sane
-- bounds without anyone re-tuning a constant.
function SkillTreeCamera:_computeZoomRange()
	local viewport = self.camera.ViewportSize
	local aspect = math.max(0.5, viewport.X / math.max(1, viewport.Y))
	local halfFov = math.rad(FOV) / 2

	local b = self.board.bounds

	-- Height at which the whole tree just fits, whichever axis is tighter.
	local fitForDepth = (b.depth / 2) / math.tan(halfFov)
	local fitForWidth = (b.width / 2) / (math.tan(halfFov) * aspect)

	self.maxHeight = math.max(fitForDepth, fitForWidth)
	-- Close enough that a single 60-stud node fills a good part of the screen.
	self.minHeight = 240 / math.tan(halfFov)
	self.minHeight = math.min(self.minHeight, self.maxHeight * 0.85)
end

function SkillTreeCamera:_studsPerPixel(): number
	local viewport = self.camera.ViewportSize
	return (2 * self.height * math.tan(math.rad(FOV) / 2)) / math.max(1, viewport.Y)
end

-- Keeps the focus point inside the authored area. Clamping the TARGET rather
-- than the visible rectangle means the tree is always at least partly on screen
-- at every zoom level, so the player can never lose it.
function SkillTreeCamera:_clampTarget(pos: Vector3): Vector3
	local b = self.board.bounds
	local origin = self.board.centre - Vector3.new(b.centre.X, 0, b.centre.Y)
	return Vector3.new(
		math.clamp(pos.X, origin.X + b.minX, origin.X + b.maxX),
		self.board.centre.Y,
		math.clamp(pos.Z, origin.Z + b.minY, origin.Z + b.maxY)
	)
end

function SkillTreeCamera:_apply()
	local pos = self.target + Vector3.new(0, self.height, 0)
	-- The explicit up vector is what stops a straight-down camera from rolling.
	self.camera.CFrame = CFrame.lookAt(pos, self.target, UP)
end

function SkillTreeCamera:Pan(deltaPixels: Vector2)
	local scale = self:_studsPerPixel()
	-- Dragging right moves the BOARD right, so the camera moves left.
	local moved = self.goalTarget + Vector3.new(-deltaPixels.X * scale, 0, -deltaPixels.Y * scale)
	self.goalTarget = self:_clampTarget(moved)
end

function SkillTreeCamera:Zoom(notches: number)
	-- Proportional, not additive: one notch should feel the same close in as far
	-- out, and a fixed stud step does not.
	local factor = (1 - WHEEL_STEP) ^ notches
	self.goalHeight = math.clamp(self.goalHeight * factor, self.minHeight, self.maxHeight)
end

function SkillTreeCamera:FocusOn(worldPos: Vector3)
	self.goalTarget = self:_clampTarget(Vector3.new(worldPos.X, self.board.centre.Y, worldPos.Z))
end

-- Screen point -> the node under it, by raycasting the real geometry rather than
-- doing any 2D hit-testing. The filter is an INCLUDE list of the Nodes folder,
-- so the ray cannot be stopped by the background plane or by anything else that
-- happens to be in the world.
function SkillTreeCamera:NodeAt(screenX: number, screenY: number): string?
	-- UserInputService positions are SCREEN coordinates (they include Roblox's
	-- top-bar inset). ScreenPointToRay uses the same coordinate space.
	-- ViewportPointToRay caused the physical hit test to be vertically offset,
	-- which is why clicking the label could work while clicking the circle felt
	-- unreliable.
	local ray = self.camera:ScreenPointToRay(screenX, screenY)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { self.board.nodesFolder }
	params.IgnoreWater = true

	local hit = Workspace:Raycast(ray.Origin, ray.Direction * (self.height * 2 + 500), params)
	if hit and hit.Instance then
		return hit.Instance:GetAttribute("SkillId")
	end
	return nil
end

function SkillTreeCamera:Start(callbacks)
	if self.active then
		return
	end
	self.active = true
	self.callbacks = callbacks or {}

	-- NEVER remember Scriptable as the "previous" type. If the camera is already
	-- Scriptable when the board opens - an earlier session that failed to restore,
	-- another system holding the camera, or this module run by hand in Edit mode -
	-- then saving it here means Stop() faithfully restores Scriptable and the
	-- camera stays frozen forever, with no error to point at. Custom is the only
	-- safe thing to fall back to.
	local existing = self.camera.CameraType
	self.previousType = (existing == Enum.CameraType.Scriptable)
		and Enum.CameraType.Custom
		or existing
	self.previousCFrame = self.camera.CFrame
	self.previousFov = self.camera.FieldOfView

	self.camera.CameraType = Enum.CameraType.Scriptable
	self.camera.FieldOfView = FOV
	-- FOV is set BEFORE measuring: _computeZoomRange reads the viewport aspect and
	-- assumes the board FOV, so measuring first would size the zoom range against
	-- whatever FOV the gameplay camera happened to be using.
	self:_computeZoomRange()
	self.goalHeight = math.clamp(self.goalHeight, self.minHeight, self.maxHeight)

	-- Published for diagnostics: the camera's numbers are otherwise sealed inside
	-- this closure and there is no way to see why a zoom clamped where it did.
	local marker = self.board.world:FindFirstChild("CameraTarget")
	if marker then
		marker:SetAttribute("MinHeight", self.minHeight)
		marker:SetAttribute("MaxHeight", self.maxHeight)
	end
	self.height = self.goalHeight
	self.target = self:_clampTarget(self.goalTarget)
	self.goalTarget = self.target
	self:_apply()

	local function track(connection)
		table.insert(self.connections, connection)
	end

	track(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			self.dragging = true
			self.dragMoved = 0
			self.dragFrom = Vector2.new(input.Position.X, input.Position.Y)
		end
	end))

	track(UserInputService.InputChanged:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
			self:Zoom(input.Position.Z)
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			local here = Vector2.new(input.Position.X, input.Position.Y)

			if self.dragging and self.dragFrom then
				local delta = here - self.dragFrom
				self.dragFrom = here
				self.dragMoved += delta.Magnitude
				self:Pan(delta)
			elseif input.UserInputType == Enum.UserInputType.MouseMovement
				and self.callbacks.onHover then
				self.callbacks.onHover(self:NodeAt(here.X, here.Y))
			end
		end
	end))

	track(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if not self.dragging then
			return
		end
		self.dragging = false

		-- A click is a press that did not travel. Without this threshold every pan
		-- would also select whatever node it happened to finish over.
		if (self.dragMoved or 0) <= 6 and self.callbacks.onClick then
			self.callbacks.onClick(self:NodeAt(input.Position.X, input.Position.Y))
		end
	end))

	-- Pinch zoom on touch. TouchPinch hands over a scale factor directly, which
	-- is far more reliable than tracking two raw touch points by hand.
	track(UserInputService.TouchPinch:Connect(function(_, scale, _, state)
		if state == Enum.UserInputState.Change and scale > 0 then
			self.goalHeight = math.clamp(self.goalHeight / scale, self.minHeight, self.maxHeight)
		end
	end))

	track(self.camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		self:_computeZoomRange()
	end))

	-- Everything is eased toward its goal here rather than set outright, which is
	-- what makes zoom and pan feel like a map instead of a teleport.
	track(RunService.RenderStepped:Connect(function(dt)
		local zoomAlpha = 1 - math.exp(-ZOOM_LERP * dt)
		local panAlpha = 1 - math.exp(-PAN_LERP * dt)
		self.height += (self.goalHeight - self.height) * zoomAlpha
		self.target = self.target:Lerp(self.goalTarget, panAlpha)
		self:_apply()

		if marker then
			marker:SetAttribute("Height", self.height)
			marker:SetAttribute("GoalHeight", self.goalHeight)
		end
	end))
end

function SkillTreeCamera:Stop()
	if not self.active then
		return
	end
	self.active = false
	self.dragging = false

	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	table.clear(self.connections)

	self.camera.FieldOfView = self.previousFov or 70

	-- Put the player's own view back BEFORE handing the camera over. The default
	-- camera scripts pick their angle up from wherever the camera is pointing
	-- when they regain it, so without this they inherit the board's straight-down
	-- view and the player comes back staring at the top of their own head.
	if self.previousCFrame then
		self.camera.CFrame = self.previousCFrame
	end

	-- Belt and braces: whatever was recorded, a camera left Scriptable is a
	-- soft-locked player, so the restore refuses to hand back that value.
	local restore = self.previousType or Enum.CameraType.Custom
	if restore == Enum.CameraType.Scriptable then
		restore = Enum.CameraType.Custom
	end
	self.camera.CameraType = restore
end

return SkillTreeCamera
