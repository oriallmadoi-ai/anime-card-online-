--!strict
-- One skill node, as real geometry on the board.
--
-- Stacked discs, read from the board upward:
--   Halo    a wide, faint Neon disc that breathes when the node can be bought
--   Outer   a thin Neon ring just outside the rim - the node's bezel
--   Gap     a dark disc that separates the bezel from the rim
--   Rim     the bright Neon edge - this is the node's colour
--   Core    a dark disc a hair above the rim, which is what turns the rim into a
--           RING rather than a solid glowing blob
-- and three flat invisible plates carrying SurfaceGuis:
--   Face     the glyph, centred in the core
--   Tag      the name card under the node: the skill's name, its rank and a
--            thin progress bar in the category colour
--   Reticle  four corner brackets that turn slowly around the SELECTED node
--
-- WHY THE TEXT IS ON BLOCKS AND NOT ON THE CYLINDERS
-- A SurfaceGui maps onto a part's BOUNDING BOX, so on a cylinder the "top face"
-- is the square the cylinder is inscribed in, and the gui gets stretched to
-- corners that are not there. Flat invisible blocks give the gui a square to
-- live on while the visible shape stays circular.
--
-- EVERY QUERYABLE PART CARRIES A SkillId ATTRIBUTE. Picking is a raycast, and a
-- raycast returns whichever part it hit - reading the id straight off that part
-- is far more robust than walking up the hierarchy hoping to find a Model. The
-- name card is queryable too, so clicking a skill's name selects it.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Format = require(ReplicatedStorage.Shared.Util.Format)

local SkillNodePart = {}

SkillNodePart.DIAMETER = 70

local THICKNESS = 2.2
local CORE_INSET = 11
local GAP_EXTRA = 9
local OUTER_EXTRA = 16
local HALO_EXTRA = 40

local DARK = Color3.fromRGB(12, 14, 24)
local LOCKED = Color3.fromRGB(54, 60, 86)
local LOCKED_TEXT = Color3.fromRGB(116, 122, 150)
local MAXED = Color3.fromRGB(255, 214, 110)
local NAME = Color3.fromRGB(236, 238, 250)
local CARD = Color3.fromRGB(8, 10, 18)
local TRACK = Color3.fromRGB(30, 34, 52)
local RETICLE = Color3.fromRGB(226, 232, 255)
local WHITE = Color3.new(1, 1, 1)

-- The name card, in studs, and how finely its canvas is drawn. 3 pixels per
-- stud is chosen against Roblox's 100px text cap: the name is ~70px, which is
-- ~23 studs of text - large enough to read from the default zoom.
local TAG_W, TAG_H, TAG_PPS = 360, 64, 3
local RETICLE_SIZE = 150
local RETICLE_DASHES = 24

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
--
-- WHY PixelsPerStud IS DELIBERATELY LOW.
-- Roblox caps text at 100 pixels, and it caps it THREE times over: TextScaled
-- stops there, an explicit TextSize is clamped there, and UITextSizeConstraint
-- cannot lift it because MaxTextSize is itself capped at 100. So the canvas has
-- to come DOWN to meet the text instead: at 2 pixels/stud a 59-stud face is a
-- 118px canvas, and a glyph two thirds of that fills the core properly.
--
-- Model:ScaleTo divides PixelsPerStud by the scale, so offset-sized contents
-- grow and shrink with the node on hover exactly like the geometry does.
local function surface(part: Part, pixelsPerStud: number): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = part
	return gui
end

local function corner(parent: Instance, px: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px)
	c.Parent = parent
end

local function label(parent: Instance, name: string, size: number, colour: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.FontFace = Theme.font()
	l.TextSize = size
	l.TextColor3 = colour
	l.Parent = parent
	return l
end

function SkillNodePart.create(parent: Instance, def, worldPos: Vector3)
	local model = Instance.new("Model")
	model.Name = def.Id
	model.Parent = parent

	local D = SkillNodePart.DIAMETER

	local halo = disc(model, "Halo", D + HALO_EXTRA, 0.6, -0.9, worldPos)
	halo.Material = Enum.Material.Neon
	halo.Color = def.Colour
	halo.Transparency = 1

	-- The bezel: a thin lit ring separated from the rim by a dark band, which is
	-- what gives the node its instrument look rather than a flat coin.
	local outer = disc(model, "Outer", D + OUTER_EXTRA, 0.6, -0.5, worldPos)
	outer.Material = Enum.Material.Neon
	outer.Color = LOCKED
	outer.Transparency = 0.55

	local gap = disc(model, "Gap", D + GAP_EXTRA, 0.6, -0.1, worldPos)
	gap.Material = Enum.Material.SmoothPlastic
	gap.Color = DARK

	local rim = disc(model, "Rim", D, THICKNESS, 0.4, worldPos)
	rim.Material = Enum.Material.Neon
	rim.Color = LOCKED

	-- Sits ABOVE the rim, not inside it. This is what makes the rim read as a
	-- ring: the core covers the middle of the glowing disc and leaves an edge.
	local core = disc(model, "Core", D - CORE_INSET, THICKNESS, 1.3, worldPos)
	core.Material = Enum.Material.SmoothPlastic
	core.Color = DARK

	-- Must clear the TOP of the core, not merely sit above its centre. The core is
	-- centred at 1.3 and THICKNESS/2 thick, so its surface is at 2.4 - a label
	-- below that is buried inside the disc and renders nothing at all, no error.
	local face = plate(model, "Face", D - CORE_INSET, D - CORE_INSET, 3.2, worldPos)
	local faceGui = surface(face, 2)

	-- Dedicated invisible click target ABOVE the visible node, so the whole
	-- circle - bezel included - is reliably clickable.
	local hitbox = disc(model, "Hitbox", D + OUTER_EXTRA + 4, 0.28, 3.6, worldPos)
	hitbox.Transparency = 1
	hitbox.CanCollide = false
	hitbox.CanTouch = false
	hitbox.CanQuery = true

	local glyph = label(faceGui, "Glyph", 10, LOCKED_TEXT)
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)
	glyph.Size = UDim2.fromScale(0.66, 0.66)
	glyph.Text = def.Glyph or "\u{25CF}"
	glyph.TextScaled = true

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.66, 0.66)
	icon.Image = def.Icon or ""
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Visible = (def.Icon or "") ~= ""
	icon.Parent = faceGui
	glyph.Visible = not icon.Visible

	----------------------------------------------------------------
	-- NAME CARD
	----------------------------------------------------------------
	-- Hangs under the node. The card hugs its text, so a short name gets a
	-- short card; the plate it lives on is only the largest the card can be.
	local tag = plate(model, "Tag", TAG_W, TAG_H, 3.2,
		worldPos + Vector3.new(0, 0, D / 2 + OUTER_EXTRA / 2 + 6 + TAG_H / 2))
	local tagGui = surface(tag, TAG_PPS)

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.fromScale(0.5, 0)
	card.Size = UDim2.fromOffset(0, 0)
	card.AutomaticSize = Enum.AutomaticSize.XY
	card.BackgroundColor3 = CARD
	card.BackgroundTransparency = 0.16
	card.BorderSizePixel = 0
	card.Parent = tagGui
	corner(card, 34)

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = LOCKED
	cardStroke.Thickness = 3
	cardStroke.Transparency = 0.35
	cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	cardStroke.Parent = card

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 38)
	padding.PaddingRight = UDim.new(0, 38)
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 16)
	padding.Parent = card

	local stack = Instance.new("UIListLayout")
	stack.FillDirection = Enum.FillDirection.Vertical
	stack.HorizontalAlignment = Enum.HorizontalAlignment.Center
	stack.SortOrder = Enum.SortOrder.LayoutOrder
	stack.Padding = UDim.new(0, 2)
	stack.Parent = card

	local nameLabel = label(card, "Name", 70, NAME)
	nameLabel.LayoutOrder = 1
	nameLabel.Size = UDim2.fromOffset(0, 80)
	nameLabel.AutomaticSize = Enum.AutomaticSize.X
	nameLabel.Text = def.Name

	local rankRow = Instance.new("Frame")
	rankRow.Name = "RankRow"
	rankRow.LayoutOrder = 2
	rankRow.BackgroundTransparency = 1
	rankRow.Size = UDim2.fromOffset(0, 50)
	rankRow.AutomaticSize = Enum.AutomaticSize.X
	rankRow.Parent = card

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Padding = UDim.new(0, 16)
	rowLayout.Parent = rankRow

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.LayoutOrder = 1
	track.BackgroundColor3 = TRACK
	track.BorderSizePixel = 0
	track.Size = UDim2.fromOffset(180, 12)
	track.Parent = rankRow
	corner(track, 6)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = LOCKED
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Visible = false
	fill.Parent = track
	corner(fill, 5)
	-- A skill with any rank at all shows at least a sliver, so "started" never
	-- reads the same as "untouched" on a 3000-rank curve.
	local minFill = Instance.new("UISizeConstraint")
	minFill.MinSize = Vector2.new(10, 0)
	minFill.Parent = fill

	local rank = label(rankRow, "Rank", 46, LOCKED_TEXT)
	rank.LayoutOrder = 2
	rank.Size = UDim2.fromOffset(0, 50)
	rank.AutomaticSize = Enum.AutomaticSize.X
	rank.Text = ("0 / %s"):format(Format.comma(def.MaxRank))

	----------------------------------------------------------------
	-- SELECTION RETICLE
	----------------------------------------------------------------
	-- Not queryable: it overhangs the node, and must never steal a click meant
	-- for a neighbour or for the empty board.
	-- Below the name card's plate, so where the ring crosses the card the card
	-- stays on top and its text is never struck through.
	local reticle = plate(model, "Reticle", RETICLE_SIZE, RETICLE_SIZE, 2.6, worldPos)
	reticle.CanQuery = false
	local reticleGui = surface(reticle, 2)
	reticleGui.Enabled = false
	local spin = Instance.new("Frame")
	spin.Name = "Spin"
	spin.BackgroundTransparency = 1
	spin.AnchorPoint = Vector2.new(0.5, 0.5)
	spin.Position = UDim2.fromScale(0.5, 0.5)
	spin.Size = UDim2.fromScale(1, 1)
	spin.Parent = reticleGui
	-- A dashed ring just outside the halo. Every dash is the same, so turning
	-- the ring by one dash's angle and repeating is a seamless spin.
	for i = 1, RETICLE_DASHES do
		local angle = (i - 1) / RETICLE_DASHES * math.pi * 2
		local dash = Instance.new("Frame")
		dash.Name = "Dash"
		dash.BorderSizePixel = 0
		dash.BackgroundColor3 = RETICLE
		dash.BackgroundTransparency = 0.12
		dash.AnchorPoint = Vector2.new(0.5, 0.5)
		dash.Position = UDim2.fromScale(0.5 + math.cos(angle) * 0.44, 0.5 + math.sin(angle) * 0.44)
		dash.Size = UDim2.fromOffset(16, 7)
		dash.Rotation = math.deg(angle) + 90
		dash.Parent = spin
	end

	-- Picking reads this straight off whatever part the raycast returned.
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.CanQuery then
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
		outer = outer,
		rim = rim,
		core = core,
		hitbox = hitbox,
		glyph = glyph,
		icon = icon,
		rank = rank,
		nameLabel = nameLabel,
		card = card,
		cardStroke = cardStroke,
		fill = fill,
		reticleGui = reticleGui,
		spin = spin,
		spinTween = nil,
		scaleValue = scaleValue,
		worldPos = worldPos,
		state = nil,
		pulse = nil,
		hovering = false,
		selected = false,
	}
end

local QUICK = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function paintCard(node)
	local state = node.state
	local colour = node.def.Colour
	local emphasised = node.selected or node.hovering
	local stroke
	if state == "locked" then
		stroke = LOCKED
	elseif state == "maxed" then
		stroke = MAXED
	else
		stroke = colour
	end
	node.cardStroke.Color = stroke
	node.cardStroke.Transparency = emphasised and 0 or (state == "locked" and 0.45 or 0.4)
	node.cardStroke.Thickness = emphasised and 4 or 3
	node.card.BackgroundTransparency = emphasised and 0.06 or 0.16
end

-- Repaints a node for its state. Runs on every profile sync, so it must be
-- idempotent - the same state in gives the same look out, with no tween stacking
-- on the last one. The halo pulse is guarded for exactly that reason: restarting
-- a looping tween every sync turns a slow breath into a strobe.
function SkillNodePart.setState(node, state: string, currentRank: number)
	local def = node.def
	local colour = def.Colour

	node.rank.Text = ("%s / %s"):format(Format.comma(currentRank), Format.comma(def.MaxRank))
	local ratio = math.clamp(currentRank / math.max(def.MaxRank, 1), 0, 1)
	node.fill.Visible = currentRank > 0
	node.fill.Size = UDim2.fromScale(ratio, 1)

	local rimColour, textColour, coreColour, haloAlpha, outerColour, outerAlpha, fillColour

	if state == "maxed" then
		rimColour = MAXED
		textColour = MAXED
		coreColour = colour:Lerp(DARK, 0.62)
		haloAlpha = 0.6
		outerColour, outerAlpha = MAXED, 0.25
		fillColour = MAXED
	elseif state == "owned" then
		rimColour = colour
		textColour = colour:Lerp(WHITE, 0.55)
		coreColour = colour:Lerp(DARK, 0.8)
		haloAlpha = 0.8
		outerColour, outerAlpha = colour, 0.35
		fillColour = colour
	elseif state == "available" then
		rimColour = colour
		textColour = colour:Lerp(WHITE, 0.35)
		coreColour = DARK
		haloAlpha = 0.86
		outerColour, outerAlpha = colour, 0.5
		fillColour = colour
	else
		rimColour = LOCKED
		textColour = LOCKED_TEXT
		coreColour = DARK
		haloAlpha = 1
		outerColour, outerAlpha = LOCKED, 0.7
		fillColour = LOCKED
	end

	TweenService:Create(node.rim, QUICK, { Color = rimColour }):Play()
	TweenService:Create(node.core, QUICK, { Color = coreColour }):Play()
	TweenService:Create(node.glyph, QUICK, { TextColor3 = textColour }):Play()
	TweenService:Create(node.outer, QUICK, { Color = outerColour, Transparency = outerAlpha }):Play()
	node.rank.TextColor3 = state == "locked" and LOCKED_TEXT or textColour:Lerp(LOCKED_TEXT, 0.35)
	node.fill.BackgroundColor3 = fillColour
	node.nameLabel.TextColor3 = state == "locked" and LOCKED_TEXT or NAME
	node.icon.ImageColor3 = state == "locked" and LOCKED_TEXT or WHITE
	node.halo.Color = state == "maxed" and MAXED or colour

	-- Only an AVAILABLE node breathes. It is the board's one call to action, so
	-- nothing else is allowed to move and compete for the eye.
	if state == "available" then
		if not node.pulse then
			node.halo.Transparency = haloAlpha
			node.pulse = TweenService:Create(
				node.halo,
				TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Transparency = 0.45 }
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
	paintCard(node)
end

local function targetScale(node): number
	if node.hovering then return 1.12 end
	if node.selected then return 1.06 end
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
	paintCard(node)
end

function SkillNodePart.setSelected(node, selected: boolean)
	if node.selected == selected then
		return
	end
	node.selected = selected
	applyScale(node, Enum.EasingStyle.Quad)
	paintCard(node)

	-- The reticle turns by one dash and repeats: every dash is identical, so
	-- the loop never visibly restarts.
	if node.spinTween then
		node.spinTween:Cancel()
		node.spinTween = nil
	end
	node.reticleGui.Enabled = selected
	if selected then
		node.spin.Rotation = 0
		node.spin.Size = UDim2.fromScale(1.25, 1.25)
		TweenService:Create(node.spin, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = UDim2.fromScale(1, 1) }):Play()
		node.spinTween = TweenService:Create(node.spin,
			TweenInfo.new(1.2, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
			{ Rotation = 360 / RETICLE_DASHES })
		node.spinTween:Play()
	end
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
