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
-- WHY A SPRITE SHEET AND NOT A VIEWPORTFRAME
-- A ViewportFrame would need the mesh uploaded, a camera per tile and a render
-- pass per tile per frame. The coin is 46-80px on screen; sixteen pre-rendered
-- frames on ONE texture look identical, cost a single ImageLabel, and animate
-- by moving a rect offset. Every coin in the game is driven by the one loop at
-- the bottom of this file.
--
-- WHY A WOBBLE AND NOT A SPIN
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

local RECT = Vector2.new(ElderCoin.Cell, ElderCoin.Cell)

local labels: { ImageLabel } = {}
local elapsed = 0
local current = -1
local connection: RBXScriptConnection? = nil

local function offsetFor(frame: number): Vector2
	return Vector2.new((frame % ElderCoin.Columns) * ElderCoin.Cell,
		math.floor(frame / ElderCoin.Columns) * ElderCoin.Cell)
end

-- One loop for every coin on screen, and it stops itself when the last one is
-- destroyed. Advancing on a frame boundary rather than every render step means
-- the whole thing is 14 property writes a second per coin, not 60.
local function ensureLoop()
	if connection then return end
	connection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		local frame = math.floor(elapsed * ElderCoin.Fps) % ElderCoin.Frames

		local alive = false
		for i = #labels, 1, -1 do
			local label = labels[i]
			if label and label.Parent then
				alive = true
			else
				table.remove(labels, i)
			end
		end

		if not alive then
			if connection then connection:Disconnect() end
			connection = nil
			current = -1
			return
		end

		if frame == current then return end
		current = frame
		local offset = offsetFor(frame)
		for _, label in ipairs(labels) do
			label.ImageRectOffset = offset
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

return ElderCoin
