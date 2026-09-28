--!strict
-- The Elder Coin as an actual object rather than a typographic glyph.
--
-- WHERE IT COMES FROM
-- Modelled and rendered in Blender: a solid of revolution with a milled edge,
-- a recessed starfield face, an inlaid ring with six studs and a faceted
-- eight-point star. Lit by a cyan key and a magenta kicker against a gradient
-- sky, so the metal has something cosmic to reflect - EEVEE renders a metal
-- with nothing to bounce as black rubber.
--
-- WHY A SPRITE SHEET AND NOT A VIEWPORTFRAME (for the small coins)
-- A ViewportFrame needs the mesh uploaded, a camera per tile and a render
-- pass per tile per frame. The coin is 46-80px on a reward tile or the skill
-- tree purse; sixteen pre-rendered frames on ONE texture look identical there,
-- cost a single ImageLabel, and animate by moving a rect offset.
--
-- WHY A WOBBLE AND NOT A SPIN (for the sprite)
-- A spinning coin goes edge-on twice per cycle and the face - the part that
-- says Elder Coin - vanishes. The frames sway instead, so the emblem stays
-- legible while the rim light travels across the metal.
--
-- HOW SMALL, AND WHY 25 FRAMES
-- +/-9 degrees of sway with a 1.6 degree nod at double frequency. Amplitude and
-- frame count do different jobs: the small amplitude is what makes it move a
-- LITTLE, the 25 frames are what make it move SMOOTHLY - per-frame rotation is
-- about 2.3 degrees rather than the 7 a 16-frame, 30-degree version stepped
-- through. At 12fps the loop is just over two seconds, which reads as breathing
-- rather than animating.
--
-- The frames are also brightness-levelled in post. Turning a mirrored face even
-- 9 degrees changes how much light it throws back, and the eye reads that as a
-- flashing pulse rather than as motion - the highlight still travels, but total
-- brightness holds flat across the loop.
--
-- THE MODEL ITSELF - ElderCoin.viewport()
-- Where the coin is a HERO rather than a glyph (the Backpack tile and its
-- inspect panel) it is the real mesh in a ViewportFrame. It is the same
-- ElderCoin.blend geometry the sheets were rendered from, brought in through
-- Import 3D, with the blend's procedural shaders baked to a SurfaceAppearance:
-- colour, metalness, roughness and an emissive mask for the stars and the
-- inlay. The template lives at ReplicatedStorage.Shared.ItemModels.ElderCoin
-- together with a ReflectionSky - six faces generated from the blend's own
-- world gradient (magenta floor, deep violet horizon, cyan/pale-blue zenith,
-- plus a cyan and a magenta kicker) - because a ViewportFrame with a Sky child
-- lights metal from it, and without one the rim reads as grey plastic.
--
-- The 3D coin turns a full revolution. Going edge-on is still the problem the
-- sway solved, so the turn is EASED to linger face-on and hurry through the
-- edge, and it carries a fixed lean toward the camera: the emblem is on screen
-- for most of the lap and the edge is a brief flash of milled metal. Because
-- the reflections come from the sky, turning the coin is also what sweeps the
-- highlight across the metal - nothing is painted on.
--
-- ONE LOOP. Sprites and viewports are driven by the same Heartbeat connection,
-- which switches itself off when the last coin of either kind is destroyed.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)

local ElderCoin = {}

-- Blender output, uploaded from the render directory. Cropped to the union of
-- every frame's silhouette - one box for the whole sequence, because cropping
-- per frame would re-centre the coin each time and turn the sway into a jitter.
ElderCoin.Hero  = "rbxassetid://139801699472283"  -- 512 still, for large tiles
ElderCoin.Sheet = "rbxassetid://115264340274971"  -- 5x5 x 200 wobble sheet

ElderCoin.Cell = 200
ElderCoin.Columns = 5
ElderCoin.Frames = 25
ElderCoin.Fps = 12

-- The Cosmic tier's own colour, used for anything tinted alongside the coin.
-- READ from VariantConfig rather than written out again: this was a copy of
-- the same RGB, and a copy is a thing that can drift. Anything that wants the
-- coin's colour should use this, so there is one value behind all of them.
ElderCoin.Accent = VariantConfig.get("Cosmic").color

-- Name of the 3D template under ReplicatedStorage.Shared.ItemModels.
ElderCoin.ModelName = "ElderCoin"

local RECT = Vector2.new(ElderCoin.Cell, ElderCoin.Cell)
local TAU = math.pi * 2

type Spin = {
	frame: ViewportFrame,
	model: Model,
	gate: GuiObject?,
	period: number,
	bob: number,
	bobPeriod: number,
	tilt: number,
	wobble: number,
	dwell: number,
	phase: number,
	light: Vector3,
	lightSwing: number,
}

local labels: { ImageLabel } = {}
local spins: { Spin } = {}
local elapsed = 0
local current = -1
local connection: RBXScriptConnection? = nil

local function offsetFor(frame: number): Vector2
	return Vector2.new((frame % ElderCoin.Columns) * ElderCoin.Cell,
		math.floor(frame / ElderCoin.Columns) * ElderCoin.Cell)
end

-- Advancing on a frame boundary rather than every render step means the
-- sheet costs 12 property writes a second per coin, not 60.
local function stepSprites()
	for i = #labels, 1, -1 do
		local label = labels[i]
		if not (label and label.Parent) then
			table.remove(labels, i)
		end
	end
	if #labels == 0 then
		current = -1
		return
	end
	local frame = math.floor(elapsed * ElderCoin.Fps) % ElderCoin.Frames
	if frame == current then return end
	current = frame
	local offset = offsetFor(frame)
	for _, label in ipairs(labels) do
		label.ImageRectOffset = offset
	end
end

-- The camera looks straight down -Y with -Z as screen-up (see viewport()), so
-- world Z is the screen's VERTICAL axis. The turn is about Z, the lean about
-- X, and "up" on screen is -Z.
local function poseFor(spin: Spin, t: number): CFrame
	local phi = (t / spin.period + spin.phase) * TAU
	-- Eased turn: d(turn)/d(phi) = 1 - 2*dwell*cos(2 phi), slowest face-on.
	local turn = phi - spin.dwell * math.sin(2 * phi)
	local bob = math.sin((t / spin.bobPeriod + spin.phase * 0.37) * TAU) * spin.bob
	local lean = math.rad(spin.tilt
		+ math.sin((t / (spin.bobPeriod * 1.7) + spin.phase) * TAU) * spin.wobble)
	return CFrame.new(0, 0, -bob) * CFrame.Angles(lean, 0, 0) * CFrame.Angles(0, 0, turn)
end

local function stepSpins()
	for i = #spins, 1, -1 do
		local spin = spins[i]
		local frame = spin.frame
		if not frame.Parent then
			table.remove(spins, i)
		elseif frame.Visible and (spin.gate == nil or (spin.gate :: GuiObject).Visible) then
			spin.model:PivotTo(poseFor(spin, elapsed))
			if spin.lightSwing > 0 then
				-- A slow swing of the key light around the view axis, so even a
				-- face-on coin never sits under a dead, fixed highlight.
				local a = math.sin((elapsed / 7.3 + spin.phase) * TAU) * spin.lightSwing
				local l = spin.light
				frame.LightDirection = Vector3.new(
					l.X * math.cos(a) - l.Z * math.sin(a), l.Y, l.X * math.sin(a) + l.Z * math.cos(a))
			end
		end
	end
end

-- One loop for every coin on screen, sprite or model, and it stops itself when
-- the last one is destroyed.
local function ensureLoop()
	if connection then return end
	connection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		stepSprites()
		stepSpins()
		if #labels == 0 and #spins == 0 then
			if connection then connection:Disconnect() end
			connection = nil
			current = -1
		end
	end)
end

-- Creates the coin under `parent`. Any ImageLabel property in `props` is
-- applied on top, so callers set their own size, position and ZIndex without
-- this module needing to know about their layout.
function ElderCoin.attach(parent: Instance, props: { [string]: any }?): ImageLabel
	local label = Instance.new("ImageLabel")
	label.Name = "ElderCoin"
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Image = ElderCoin.Sheet
	label.ImageRectSize = RECT
	label.ImageRectOffset = offsetFor(current >= 0 and current or 0)
	label.ScaleType = Enum.ScaleType.Stretch
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(1, 1)

	if props then
		for key, value in pairs(props) do
			if key ~= "Parent" then (label :: any)[key] = value end
		end
	end

	label.Parent = parent
	table.insert(labels, label)
	ensureLoop()
	return label
end

-- The still, for anywhere an animation would be noise rather than life.
function ElderCoin.still(parent: Instance, props: { [string]: any }?): ImageLabel
	local label = Instance.new("ImageLabel")
	label.Name = "ElderCoin"
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Image = ElderCoin.Hero
	label.ScaleType = Enum.ScaleType.Fit
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(1, 1)
	if props then
		for key, value in pairs(props) do
			if key ~= "Parent" then (label :: any)[key] = value end
		end
	end
	label.Parent = parent
	return label
end

-- The 3D template, or nil if it is missing from this place.
function ElderCoin.template(): Model?
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local folder = shared and shared:FindFirstChild("ItemModels")
	local model = folder and folder:FindFirstChild(ElderCoin.ModelName)
	if model and model:IsA("Model") then
		return model
	end
	return nil
end

-- The real coin in a ViewportFrame, turning. `props` are ViewportFrame
-- properties (size, position, ZIndex...), exactly like attach(). `opts`:
--   period      seconds per revolution          (default 8)
--   bob         float height in studs           (default 0.05; coin is 2 wide)
--   bobPeriod   seconds per float cycle         (default 3.4)
--   tilt        lean toward the camera, degrees (default -14)
--   wobble      extra lean sway, degrees        (default 2.5)
--   dwell       0..0.45, how long it lingers face-on (default 0.18)
--   phase       0..1 offset so two coins on screen are not in lockstep
--   fill        fraction of the frame the coin's diameter fills (default 0.8)
--   gate        a GuiObject; while it is hidden the coin is not animated
--   lightSwing  radians the key light swings around the view axis (default 0)
--   ambient / lightColor / light   ViewportFrame lighting overrides
--
-- If the template is missing the animated sprite is returned instead, so a
-- caller always gets a coin.
function ElderCoin.viewport(parent: Instance, props: { [string]: any }?, opts: { [string]: any }?): GuiObject
	local template = ElderCoin.template()
	if not template then
		warn("[ElderCoin] ItemModels.ElderCoin is missing - falling back to the sprite")
		return ElderCoin.attach(parent, props)
	end
	local o: { [string]: any } = opts or {}

	local frame = Instance.new("ViewportFrame")
	frame.Name = "ElderCoin3D"
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(1, 1)
	frame.Ambient = o.ambient or Color3.fromRGB(132, 128, 156)
	frame.LightColor = o.lightColor or Color3.fromRGB(255, 250, 255)
	local light: Vector3 = o.light or Vector3.new(0.55, -1, 0.45)
	frame.LightDirection = light
	if props then
		for key, value in pairs(props) do
			if key ~= "Parent" then (frame :: any)[key] = value end
		end
	end

	local model = template:Clone()
	local sky = model:FindFirstChild("ReflectionSky")
	if sky then
		if o.sky == false then
			sky:Destroy()
		else
			sky.Parent = frame
		end
	end
	model.Parent = frame

	-- Narrow lens, so the coin keeps its proportions rather than bulging.
	local camera = Instance.new("Camera")
	camera.FieldOfView = 20
	local diameter = (template:GetAttribute("Diameter") :: number?) or 2
	local distance = (diameter / (o.fill or 0.8)) / (2 * math.tan(math.rad(10)))
	camera.CFrame = CFrame.lookAt(Vector3.new(0, distance, 0), Vector3.zero, Vector3.new(0, 0, -1))
	camera.Parent = frame
	frame.CurrentCamera = camera

	local spin: Spin = {
		frame = frame,
		model = model,
		gate = o.gate,
		period = o.period or 8,
		bob = o.bob or 0.05,
		bobPeriod = o.bobPeriod or 3.4,
		tilt = o.tilt or -14,
		wobble = o.wobble or 2.5,
		dwell = math.clamp(o.dwell or 0.18, 0, 0.45),
		phase = o.phase or 0,
		light = light,
		lightSwing = o.lightSwing or 0,
	}
	model:PivotTo(poseFor(spin, elapsed))
	frame.Parent = parent
	table.insert(spins, spin)
	ensureLoop()
	return frame
end

return ElderCoin
