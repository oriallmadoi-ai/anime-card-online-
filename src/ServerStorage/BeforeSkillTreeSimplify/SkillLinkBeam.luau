--!strict
-- A connection between two nodes, drawn as three Beams sharing two attachments.
--
--   Rail   a thin solid line. Dim slate while the requirement it draws is
--          unmet, the parent's colour once it is met.
--   Glow   a wide, faint band under the rail, only on a met link - the neon
--          bleed that makes a lit path read as powered.
--   Pulse  a stream of bright rounds running parent -> child along a met link,
--          so the route through the tree visibly flows toward what it unlocks.
--
-- WHY BEAMS AND NOT THIN PARTS
-- A Beam is a camera-facing ribbon, so it keeps an even apparent thickness from
-- any zoom level, where a thin Part would visibly thin out and alias as the
-- camera pulls back. Its texture also SCROLLS for free (TextureSpeed), which is
-- the whole of the pulse effect - no per-frame script work at all.
--
-- Straight runs from parent to child: in the world there is nothing to clip
-- against, so the old 2D version's right-angled elbows are not needed.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VfxAssets = require(ReplicatedStorage.Shared.Config.VfxAssets)

local SkillLinkBeam = {}

-- A plain white 1x1 pixel: a flat ribbon whose look comes from Color and
-- Transparency alone.
local FLAT_TEXTURE = "rbxassetid://446111271"
-- A soft round dot. Wrapped along the link, every repeat is one soft-ended dash
-- with clear board between it and the next, so a scrolling link reads as a
-- string of bright pulses travelling toward the child.
local PULSE_TEXTURE = VfxAssets.Mote

local LOCKED_COLOUR = Color3.fromRGB(58, 64, 94)
local LOCKED_TRANSPARENCY = 0.3
local ACTIVE_TRANSPARENCY = 0.12

local RAIL_LOCKED = 3
local RAIL_ACTIVE = 5
local GLOW_WIDTH = 20
local GLOW_TRANSPARENCY = 0.85
local PULSE_WIDTH = 13
local PULSE_LENGTH = 90
local PULSE_SPEED = 0.9
local PULSE_WHITEN = 0.6

local function attachmentAt(parent: Instance, name: string, worldPos: Vector3): Attachment
	-- Attachments need a BasePart ancestor to have a world position, so each end
	-- gets a tiny anchored anchor part rather than being parented to the node
	-- itself - the node is scaled on hover, and that would drag the beam ends
	-- around with it.
	local anchor = Instance.new("Part")
	anchor.Name = name
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(worldPos)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Parent = parent

	local a = Instance.new("Attachment")
	a.Parent = anchor
	return a
end

local function beam(holder: Instance, name: string, a0: Attachment, a1: Attachment, width: number, texture: string): Beam
	local b = Instance.new("Beam")
	b.Name = name
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.Width0 = width
	b.Width1 = width
	-- Straight, not drooping: CurveSize defaults would bow the line.
	b.CurveSize0 = 0
	b.CurveSize1 = 0
	-- Left at the default segment count on purpose: with a single segment the
	-- texture's U coordinate collapses to one value along the whole ribbon, and
	-- a wrapped texture shows as the entire link flashing on and off instead of
	-- pulses travelling along it.
	b.LightInfluence = 0
	b.LightEmission = 1
	b.FaceCamera = true
	b.Texture = texture
	b.TextureMode = Enum.TextureMode.Wrap
	b.TextureLength = 26
	b.TextureSpeed = 0
	b.Parent = holder
	return b
end

function SkillLinkBeam.create(parent: Instance, fromPos: Vector3, toPos: Vector3, colour: Color3)
	local holder = Instance.new("Folder")
	holder.Name = "Link"
	holder.Parent = parent

	local a0 = attachmentAt(holder, "From", fromPos)
	local a1 = attachmentAt(holder, "To", toPos)

	-- Built bottom-up; beams draw in creation order when they overlap exactly.
	local glow = beam(holder, "Glow", a0, a1, GLOW_WIDTH, FLAT_TEXTURE)
	glow.Color = ColorSequence.new(colour)
	glow.Transparency = NumberSequence.new(GLOW_TRANSPARENCY)
	glow.Enabled = false

	local rail = beam(holder, "Rail", a0, a1, RAIL_LOCKED, FLAT_TEXTURE)
	rail.Color = ColorSequence.new(LOCKED_COLOUR)
	rail.Transparency = NumberSequence.new(LOCKED_TRANSPARENCY)

	local pulse = beam(holder, "Pulse", a0, a1, PULSE_WIDTH, PULSE_TEXTURE)
	pulse.Color = ColorSequence.new(colour:Lerp(Color3.new(1, 1, 1), PULSE_WHITEN))
	pulse.Transparency = NumberSequence.new(0)
	pulse.TextureLength = PULSE_LENGTH
	pulse.TextureSpeed = PULSE_SPEED
	pulse.Enabled = false

	return {
		holder = holder,
		beam = rail,
		rail = rail,
		glow = glow,
		pulse = pulse,
		colour = colour,
		active = false,
	}
end

local function paint(link)
	local active = link.active
	link.rail.Color = ColorSequence.new(active and link.colour or LOCKED_COLOUR)
	link.rail.Transparency = NumberSequence.new(active and ACTIVE_TRANSPARENCY or LOCKED_TRANSPARENCY)
	link.glow.Color = ColorSequence.new(link.colour)
	link.glow.Transparency = NumberSequence.new(GLOW_TRANSPARENCY)
	link.glow.Enabled = active
	link.pulse.Color = ColorSequence.new(link.colour:Lerp(Color3.new(1, 1, 1), PULSE_WHITEN))
	link.pulse.Transparency = NumberSequence.new(0)
	link.pulse.TextureSpeed = PULSE_SPEED
	link.pulse.Enabled = active
end

function SkillLinkBeam.setActive(link, active: boolean)
	if not link or link.active == active then
		return
	end
	link.active = active
	paint(link)

	-- Beam.Color and Beam.Transparency are sequences, and TweenService cannot
	-- interpolate a ColorSequence or NumberSequence - it silently does nothing.
	-- The colours are therefore set outright and only the WIDTH is tweened, which
	-- is a plain number and gives the change something to animate.
	local width = active and RAIL_ACTIVE or RAIL_LOCKED
	TweenService:Create(link.rail, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Width0 = width,
		Width1 = width,
	}):Play()
end

-- Energy slamming from the parent node into the child, played when a skill is
-- bought: the pulses race, the rail flares white-hot and fattens, then it all
-- eases back to whatever the link's resting state is.
function SkillLinkBeam.surge(link)
	if not link then
		return
	end
	local rail, glow, pulse = link.rail, link.glow, link.pulse
	local restingWidth = link.active and RAIL_ACTIVE or RAIL_LOCKED

	rail.Color = ColorSequence.new(Color3.new(1, 1, 1):Lerp(link.colour, 0.35))
	rail.Transparency = NumberSequence.new(0)
	rail.Width0 = restingWidth * 2.4
	rail.Width1 = restingWidth * 2.4
	glow.Enabled = true
	glow.Transparency = NumberSequence.new(0.7)
	glow.Width0 = GLOW_WIDTH * 1.8
	glow.Width1 = GLOW_WIDTH * 1.8
	pulse.Enabled = true
	pulse.Color = ColorSequence.new(Color3.new(1, 1, 1))
	pulse.TextureSpeed = PULSE_SPEED * 6

	local info = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(rail, info, { Width0 = restingWidth, Width1 = restingWidth }):Play()
	TweenService:Create(glow, info, { Width0 = GLOW_WIDTH, Width1 = GLOW_WIDTH }):Play()

	task.delay(0.8, function()
		if rail.Parent then
			paint(link)
		end
	end)
end

return SkillLinkBeam
