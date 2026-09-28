--!strict
-- A connection between two nodes, drawn as a Beam.
--
-- WHY BEAMS AND NOT THIN PARTS
-- A Beam is a camera-facing ribbon, so it keeps an even apparent thickness from
-- any zoom level, where a thin Part would visibly thin out and alias as the
-- camera pulls back. It also has a scrolling TEXTURE, which is what makes the
-- energy-travel effect on unlock nearly free rather than a per-frame animation.
--
-- Note the earlier 2D version had to draw right-angled elbows because a rotated
-- GuiObject escapes ClipsDescendants and would streak outside the scrolling
-- frame. In the world there is nothing to clip against, so these are straight
-- runs from parent to child.

local TweenService = game:GetService("TweenService")

local SkillLinkBeam = {}

-- A plain white 1x1 pixel. Scrolling a flat texture is what reads as energy
-- moving along the line; the beam's own Transparency curve shapes it.
local FLOW_TEXTURE = "rbxassetid://446111271"

local LOCKED_COLOUR = Color3.fromRGB(48, 50, 70)
local LOCKED_TRANSPARENCY = 0.55
local ACTIVE_TRANSPARENCY = 0.12

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

function SkillLinkBeam.create(parent: Instance, fromPos: Vector3, toPos: Vector3, colour: Color3)
	local holder = Instance.new("Folder")
	holder.Name = "Link"
	holder.Parent = parent

	local a0 = attachmentAt(holder, "From", fromPos)
	local a1 = attachmentAt(holder, "To", toPos)

	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 5
	beam.Width1 = 5
	-- Straight, not drooping: CurveSize defaults would bow the line.
	beam.CurveSize0 = 0
	beam.CurveSize1 = 0
	beam.Color = ColorSequence.new(LOCKED_COLOUR)
	beam.Transparency = NumberSequence.new(LOCKED_TRANSPARENCY)
	beam.LightInfluence = 0
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Texture = FLOW_TEXTURE
	beam.TextureMode = Enum.TextureMode.Wrap
	beam.TextureLength = 26
	beam.TextureSpeed = 0
	beam.Parent = holder

	return {
		holder = holder,
		beam = beam,
		colour = colour,
		active = false,
	}
end

function SkillLinkBeam.setActive(link, active: boolean)
	if not link or link.active == active then
		return
	end
	link.active = active

	local beam = link.beam
	local info = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	-- Beam.Color and Beam.Transparency are sequences, and TweenService cannot
	-- interpolate a ColorSequence or NumberSequence - it silently does nothing.
	-- The colour is therefore set outright and only the WIDTH is tweened, which
	-- is a plain number and gives the change something to animate.
	beam.Color = ColorSequence.new(active and link.colour or LOCKED_COLOUR)
	beam.Transparency = NumberSequence.new(active and ACTIVE_TRANSPARENCY or LOCKED_TRANSPARENCY)
	beam.TextureSpeed = active and 0.6 or 0

	TweenService:Create(beam, info, {
		Width0 = active and 7 or 5,
		Width1 = active and 7 or 5,
	}):Play()
end

-- Energy running from the parent node into the child, played when a skill is
-- bought. Speeds the texture right up and fattens the beam, then eases back to
-- whatever its resting state is.
function SkillLinkBeam.surge(link)
	if not link then
		return
	end
	local beam = link.beam
	local restingWidth = link.active and 7 or 5

	beam.Color = ColorSequence.new(Color3.new(1, 1, 1):Lerp(link.colour, 0.35))
	beam.Transparency = NumberSequence.new(0)
	beam.TextureSpeed = 7
	beam.Width0 = restingWidth * 2.1
	beam.Width1 = restingWidth * 2.1

	TweenService:Create(
		beam,
		TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Width0 = restingWidth, Width1 = restingWidth }
	):Play()

	task.delay(0.75, function()
		if beam.Parent then
			beam.Color = ColorSequence.new(link.active and link.colour or LOCKED_COLOUR)
			beam.Transparency = NumberSequence.new(
				link.active and ACTIVE_TRANSPARENCY or LOCKED_TRANSPARENCY)
			beam.TextureSpeed = link.active and 0.6 or 0
		end
	end)
end

return SkillLinkBeam
