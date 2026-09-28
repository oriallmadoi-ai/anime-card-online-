--!strict
-- One skill node, as real geometry on the board.
--
-- Four stacked cylinders plus a flat label plate:
--   Halo   a wide, faint Neon disc that pulses when the node can be bought
--   Rim    the bright Neon edge - this is the node's colour
--   Core   a dark disc a hair above the rim, which is what turns the rim into a
--          RING rather than a solid glowing blob
--   Face   an invisible block carrying the SurfaceGui (glyph + rank)
--   Plate  a second invisible block below it carrying the skill's name
--
-- WHY THE TEXT IS ON BLOCKS AND NOT ON THE CYLINDERS
-- A SurfaceGui maps onto a part's BOUNDING BOX, so on a cylinder the "top face"
-- is the square the cylinder is inscribed in, and the gui gets stretched to
-- corners that are not there. Flat invisible blocks give the gui a square to
-- live on while the visible shape stays circular.
--
-- EVERY PART CARRIES A SkillId ATTRIBUTE. Picking is a raycast, and a raycast
-- returns whichever part it hit - reading the id straight off that part is far
-- more robust than walking up the hierarchy hoping to find a Model.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)

local SkillNodePart = {}

SkillNodePart.DIAMETER = 60

local THICKNESS = 2.2
local CORE_INSET = 9
local HALO_EXTRA = 26

local DARK = Color3.fromRGB(14, 15, 24)
local LOCKED = Color3.fromRGB(58, 60, 82)
local LOCKED_TEXT = Color3.fromRGB(120, 124, 150)
local MAXED = Color3.fromRGB(255, 214, 110)

-- A cylinder's circular faces sit on its LOCAL X axis, so a disc lying flat on
-- the board needs a 90 degree roll about Z. Size.X is then the disc's thickness
-- and Size.Y/Z are its diameter.
local FLAT = CFrame.Angles(0, 0, math.rad(90))

local function disc(parent: Instance, name: string, diameter: number, thickness: number, y: number, worldPos: Vector3)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(thickness, diameter, diameter)
	p.CFrame = CFrame.new(worldPos + Vector3.new(0, y, 0)) * FLAT
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = true
	p.CastShadow = false
	p.Parent = parent
	return p
end

-- A SurfaceGui on the TOP face takes its "up" from the part's local +X, not from
-- -Z as you would expect - so on an unrotated plate every label reads sideways.
-- Rolling the plate a quarter turn about Y points that axis along world -Z,
-- which is the direction the camera treats as up.
local LABEL_FACING = CFrame.Angles(0, math.rad(-90), 0)

local function plate(parent: Instance, name: string, sizeX: number, sizeZ: number, y: number, worldPos: Vector3)
	local p = Instance.new("Part")
	p.Name = name
	-- Swapped, because the quarter turn below exchanges the plate's X and Z.
	p.Size = Vector3.new(sizeZ, 0.2, sizeX)
	p.CFrame = CFrame.new(worldPos + Vector3.new(0, y, 0)) * LABEL_FACING
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Parent = parent
	return p
end

-- LightInfluence 0 on every SurfaceGui is load-bearing. The board sits in the
-- live world, under whatever sun, ambient and per-location lighting the game is
-- running - without this the tree's colours would drift with the time of day.
-- WHY PixelsPerStud IS DELIBERATELY LOW.
--
-- Roblox caps text at 100 pixels, and it caps it THREE times over: TextScaled
-- stops there, an explicit TextSize is clamped there, and UITextSizeConstraint
-- cannot lift it because MaxTextSize is itself capped at 100. No property
-- anywhere draws text larger than 100px.
--
-- So the canvas has to come DOWN to meet the text instead. At 20 pixels/stud a
-- 51-stud node face is a 1020px canvas and the largest possible glyph covers a
-- tenth of it - which is exactly why these faces first rendered as specks. At
-- 5 pixels/stud the face is ~255px and 100px text fills it properly.

local function surface(part: Part): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 5
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Parent = part
	return gui
end

function SkillNodePart.create(parent: Instance, def, worldPos: Vector3)
	local model = Instance.new("Model")
	model.Name = def.Id
	model.Parent = parent

	local D = SkillNodePart.DIAMETER

	local halo = disc(model, "Halo", D + HALO_EXTRA, 0.6, -0.4, worldPos)
	halo.Material = Enum.Material.Neon
	halo.Color = def.Colour
	halo.Transparency = 1

	local rim = disc(model, "Rim", D, THICKNESS, 0, worldPos)
	rim.Material = Enum.Material.Neon
	rim.Color = LOCKED

	-- Sits ABOVE the rim, not inside it. This is what makes the rim read as a
	-- ring: the core covers the middle of the glowing disc and leaves an edge.
	local core = disc(model, "Core", D - CORE_INSET, THICKNESS, 0.9, worldPos)
	core.Material = Enum.Material.SmoothPlastic
	core.Color = DARK

	-- Must clear the TOP of the core, not merely sit above its centre. The core is
	-- centred at 0.9 and THICKNESS/2 thick, so its surface is at 2.0 - a label at
	-- 1.6 is buried inside the disc and renders nothing at all, with no error.
	local face = plate(model, "Face", D - CORE_INSET, D - CORE_INSET, 2.8, worldPos)
	local faceGui = surface(face)

	-- Dedicated invisible click target ABOVE the visible node. The old picker
	-- relied on whichever decorative part happened to be hit first, which made
	-- the name plate feel easier to click than the actual circle. This disc makes
	-- the whole skill button reliably clickable while remaining real 3D geometry.
	local hitbox = disc(model, "Hitbox", D + 8, 0.28, 3.25, worldPos)
	hitbox.Transparency = 1
	hitbox.CanCollide = false
	hitbox.CanTouch = false
	hitbox.CanQuery = true

	local glyph = Instance.new("TextLabel")
	glyph.BackgroundTransparency = 1
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.42)
	glyph.Size = UDim2.fromScale(0.62, 0.5)
	glyph.Text = def.Glyph or "\u{25CF}"
	glyph.FontFace = Theme.font()
	glyph.TextScaled = true
	glyph.TextColor3 = LOCKED_TEXT
	glyph.Parent = faceGui

	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.42)
	icon.Size = UDim2.fromScale(0.62, 0.5)
	icon.Image = def.Icon or ""
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Visible = (def.Icon or "") ~= ""
	icon.Parent = faceGui
	glyph.Visible = not icon.Visible

	local rank = Instance.new("TextLabel")
	rank.BackgroundTransparency = 1
	rank.AnchorPoint = Vector2.new(0.5, 1)
	rank.Position = UDim2.fromScale(0.5, 0.98)
	rank.Size = UDim2.fromScale(0.8, 0.22)
	rank.Text = ("0/%d"):format(def.MaxRank)
	rank.FontFace = Theme.font()
	rank.TextScaled = true
	rank.TextColor3 = LOCKED_TEXT
	rank.Parent = faceGui

	-- The name sits on its own plate BELOW the disc, so a long name is never
	-- squeezed into the circle.
	local namePlate = plate(model, "NamePlate", D * 2.1, 26, 2.8,
		worldPos + Vector3.new(0, 0, D * 0.72))
	local nameGui = surface(namePlate)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.fromScale(1, 1)
	nameLabel.Text = def.Name
	nameLabel.FontFace = Theme.font()
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.fromRGB(228, 230, 245)
	nameLabel.Parent = nameGui

	local nameStroke = Instance.new("UIStroke")
	nameStroke.Color = Color3.new(0, 0, 0)
	nameStroke.Thickness = 3
	nameStroke.Parent = nameLabel

	-- Picking reads this straight off whatever part the raycast returned.
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p:SetAttribute("SkillId", def.Id)
		end
	end

	model.PrimaryPart = rim

	-- Model:ScaleTo is the only clean way to grow the WHOLE node (geometry and
	-- its SurfaceGui contents together), but it is a method, not a property, so
	-- TweenService cannot touch it. Tweening a NumberValue and applying it on
	-- change is the standard way round that.
	local scaleValue = Instance.new("NumberValue")
	scaleValue.Value = 1
	scaleValue.Parent = model
	scaleValue.Changed:Connect(function(v)
		if model.Parent then
			model:ScaleTo(math.max(0.01, v))
		end
	end)

	return {
		id = def.Id,
		def = def,
		model = model,
		halo = halo,
		rim = rim,
		core = core,
		hitbox = hitbox,
		glyph = glyph,
		icon = icon,
		rank = rank,
		nameLabel = nameLabel,
		scaleValue = scaleValue,
		worldPos = worldPos,
		state = nil,
		pulse = nil,
		hovering = false,
		selected = false,
	}
end

local QUICK = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Repaints a node for its state. Runs on every profile sync, so it must be
-- idempotent - the same state in gives the same look out, with no tween stacking
-- on the last one. The halo pulse is guarded for exactly that reason: restarting
-- a looping tween every sync turns a slow breath into a strobe.
function SkillNodePart.setState(node, state: string, currentRank: number)
	local def = node.def
	local colour = def.Colour

	node.rank.Text = ("%d/%d"):format(currentRank, def.MaxRank)

	local rimColour, textColour, coreColour, haloAlpha

	if state == "maxed" then
		rimColour = MAXED
		textColour = MAXED
		coreColour = colour:Lerp(DARK, 0.62)
		haloAlpha = 0.55
	elseif state == "owned" then
		rimColour = colour
		textColour = colour:Lerp(Color3.new(1, 1, 1), 0.6)
		coreColour = colour:Lerp(DARK, 0.78)
		haloAlpha = 0.78
	elseif state == "available" then
		rimColour = colour
		textColour = colour:Lerp(Color3.new(1, 1, 1), 0.4)
		coreColour = DARK
		haloAlpha = 0.86
	else
		rimColour = LOCKED
		textColour = LOCKED_TEXT
		coreColour = DARK
		haloAlpha = 1
	end

	TweenService:Create(node.rim, QUICK, { Color = rimColour }):Play()
	TweenService:Create(node.core, QUICK, { Color = coreColour }):Play()
	TweenService:Create(node.glyph, QUICK, { TextColor3 = textColour }):Play()
	node.rank.TextColor3 = textColour
	node.nameLabel.TextColor3 = state == "locked"
		and LOCKED_TEXT
		or Color3.fromRGB(228, 230, 245)
	node.icon.ImageColor3 = state == "locked" and Color3.fromRGB(120, 124, 150) or Color3.new(1, 1, 1)
	node.halo.Color = state == "maxed" and MAXED or colour

	-- Only an AVAILABLE node breathes. It is the board's one call to action, so
	-- nothing else is allowed to move and compete for the eye.
	if state == "available" then
		if not node.pulse then
			node.halo.Transparency = haloAlpha
			node.pulse = TweenService:Create(
				node.halo,
				TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Transparency = 0.42 }
			)
			node.pulse:Play()
		end
	else
		if node.pulse then
			node.pulse:Cancel()
			node.pulse = nil
		end
		TweenService:Create(node.halo, QUICK, { Transparency = haloAlpha }):Play()
	end

	node.state = state
end

local function targetScale(node): number
	if node.hovering then return 1.14 end
	if node.selected then return 1.07 end
	return 1
end

local function applyScale(node, style)
	TweenService:Create(
		node.scaleValue,
		TweenInfo.new(0.16, style, Enum.EasingDirection.Out),
		{ Value = targetScale(node) }
	):Play()
end

function SkillNodePart.setHover(node, hovering: boolean)
	if node.hovering == hovering then
		return
	end
	node.hovering = hovering
	applyScale(node, hovering and Enum.EasingStyle.Back or Enum.EasingStyle.Quad)
end

function SkillNodePart.setSelected(node, selected: boolean)
	if node.selected == selected then
		return
	end
	node.selected = selected
	applyScale(node, Enum.EasingStyle.Quad)
end

-- Fired on a successful purchase: a hard punch that settles back, plus a halo
-- flash, so the click has a physical result even when only the rank text moved.
function SkillNodePart.punch(node)
	node.scaleValue.Value = targetScale(node) * 1.3
	TweenService:Create(
		node.scaleValue,
		TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
		{ Value = targetScale(node) }
	):Play()

	local resting = node.halo.Transparency
	node.halo.Transparency = 0.05
	TweenService:Create(
		node.halo,
		TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Transparency = resting }
	):Play()
end

return SkillNodePart
