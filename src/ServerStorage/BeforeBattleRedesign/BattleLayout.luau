--!strict
-- Static construction of the battle screen.
--
-- Split out of BattleController so the controller file is behaviour - drag,
-- events, animation, state - and this file is furniture. Nothing here reads
-- battle state; it returns a table of references the controller drives.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BattleTheme = require(ReplicatedStorage.Shared.UI.BattleTheme)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)

local C = BattleTheme.Colors
local new = BattleTheme.new

local BattleLayout = {}

BattleLayout.Z = {
	Backdrop = 1,
	Field    = 10,
	Location = 14,
	Card     = 24,
	Chrome   = 40,
	Hand     = 50,
	Drag     = 90,
	Modal    = 130,
}
local Z = BattleLayout.Z

-- Base sizes, authored against a 900px-tall window. applyScale() below scales
-- them to the real viewport every time it changes, so the stack grows on a
-- fullscreen client instead of sitting in a small island of a big black screen,
-- and shrinks rather than overlapping itself in a short Studio window.
local BASE = {
	-- Smaller than the field cards on purpose. The hand now lives in a tray at
	-- the right edge, where a full-size card would reach up into the enemy
	-- effects rail. Hovering a card enlarges it, so readability is not lost.
	HandCardWidth  = 128,
	FieldCardWidth = 168,
	InspectWidth   = 380,
	HandDrop       = 0,
	HandLift       = 104,
	-- The location is the centrepiece; it earns the extra height.
	LocationHeight = 178,
}
BattleLayout.DesignHeight = 900
BattleLayout.Scale = 1

BattleLayout.HandCardWidth  = BASE.HandCardWidth
BattleLayout.FieldCardWidth = BASE.FieldCardWidth
BattleLayout.InspectWidth   = BASE.InspectWidth
BattleLayout.HandDrop       = BASE.HandDrop
BattleLayout.HandLift       = BASE.HandLift
BattleLayout.LocationHeight = BASE.LocationHeight

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local p = table.clone(props)
	p.Parent = parent
	p.BackgroundTransparency = p.BackgroundTransparency or 1
	p.FontFace = Theme.font()
	p.TextColor3 = p.TextColor3 or C.Text
	p.Text = p.Text or ""
	return new("TextLabel", p)
end
BattleLayout.text = text

-- Recompute the size constants for the current viewport. Card widths are read
-- fresh every time the hand is rebuilt, so reassigning them here is enough for
-- everything transient; the pieces built once (seats, location) are resized in
-- place by BattleLayout.fit().
-- The scale is SOLVED from the vertical budget rather than guessed from a
-- design height, because the stack is height-bound and a guess is what let the
-- enemy card sit on the location and the hand fall off the bottom edge.
--
--   fixed   = round band + seat padding + gaps + margins
--   perUnit = everything that scales, expressed at k = 1
--
-- so the tallest k that still fits is (viewportY - fixed) / perUnit.
--
-- The hand is only counted for the part of it that is NOT allowed to overlap
-- the player's own seat. A hand that overlaps the near edge of the board is
-- how every physical card game looks, and refusing that overlap costs the
-- active cards about 15% of their size for nothing.
-- The hand no longer sits under the board - it is a tray on the right edge -
-- so the vertical budget does not have to reserve any room for it at all. That
-- is worth roughly 20% on every card in the centre of the screen.
local TRAY_MARGIN_X = 34    -- gap from the right edge of the screen
-- 20, not 30. A hovered card lifts and scales, and the extra 10px here is what
-- keeps the top of that card clear of the enemy effects rail above it.
local TRAY_MARGIN_Y = 20    -- gap from the bottom edge
local TRAY_SPAN_MAX = 560   -- how far left the fan may reach when expanded
-- The ENEMY tray is the same pile at the top of the same edge, pushed left far
-- enough to clear their portrait and nameplate (28 + PORTRAIT + PLATE_W + 10),
-- with a gap. Its bottom sits above the effects rail at every supported size.
local ENEMY_TRAY_X = 28 + 86 + 236 + 10 + 30
local ENEMY_TRAY_Y = 22
local SEAT_PAD   = 10
local SEAT_GAP   = 10
local ROUND_BAND = 44
local BOTTOM_PAD = 10
local FIXED = ROUND_BAND + SEAT_PAD * 2 + SEAT_GAP * 2 + BOTTOM_PAD
local PER_UNIT = BASE.FieldCardWidth * 1.45 * 2   -- both seats
                + BASE.LocationHeight             -- the location

function BattleLayout.applyScale(viewportY: number)
	local k = math.clamp((viewportY - FIXED) / PER_UNIT, 0.55, 1.30)
	BattleLayout.Scale = k
	BattleLayout.HandCardWidth  = math.floor(BASE.HandCardWidth * k + 0.5)
	BattleLayout.FieldCardWidth = math.floor(BASE.FieldCardWidth * k + 0.5)
	BattleLayout.InspectWidth   = math.floor(BASE.InspectWidth * k + 0.5)
	BattleLayout.HandDrop       = BASE.HandDrop   -- a screen-edge margin, not art
	BattleLayout.HandLift       = math.floor(BASE.HandLift * k + 0.5)
	BattleLayout.LocationHeight = math.floor(BASE.LocationHeight * k + 0.5)
	return k
end

-- ── One side's identity block ──────────────────────────────────────────
-- SQUARE portrait butted against a nameplate of matching height, so the two
-- read as one component. The previous rotated-diamond portrait floated over
-- the plate and clipped its own text.
local PORTRAIT = 86
local PLATE_W = 236

local function identity(parent: Instance, side: string)
	local isPlayer = side == "player"
	local accent = isPlayer and C.Player or C.Enemy
	local xAnchor = isPlayer and 0 or 1
	local dir = isPlayer and 1 or -1

	local holder = new("Frame", {
		Name = isPlayer and "PlayerIdentity" or "EnemyIdentity",
		Parent = parent,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(xAnchor, 0),
		-- Nudged clear of Roblox's own top-left CoreGui buttons.
		Position = UDim2.new(xAnchor, dir * 28, 0, isPlayer and 76 or 26),
		Size = UDim2.fromOffset(PORTRAIT + PLATE_W + 10, PORTRAIT),
		ZIndex = Z.Chrome,
	})

	-- portrait frame: square, outboard
	local frame = new("Frame", {
		Name = "PortraitFrame",
		Parent = holder,
		AnchorPoint = Vector2.new(xAnchor, 0.5),
		Position = UDim2.new(xAnchor, 0, 0.5, 0),
		Size = UDim2.fromOffset(PORTRAIT, PORTRAIT),
		BackgroundColor3 = C.Panel,
		BorderSizePixel = 0,
		ClipsDescendants = true,   -- crops the art to the square
		ZIndex = Z.Chrome + 4,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, 8) }),
	})
	local frameStroke = new("UIStroke", {
		Name = "RarityEdge", Parent = frame,
		Color = accent, Thickness = 3, Transparency = 0,
	})
	BattleTheme.glow(frame, accent, 1)

	local art = new("ImageLabel", {
		Name = "Art",
		Parent = frame,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ScaleType = Enum.ScaleType.Crop,
		ZIndex = Z.Chrome + 5,
	})

	-- nameplate: same height, butted against the portrait
	local plate = BattleTheme.bevel(holder, {
		Name = "Plate",
		AnchorPoint = Vector2.new(xAnchor, 0.5),
		Position = UDim2.new(xAnchor, dir * (PORTRAIT + 10), 0.5, 0),
		Size = UDim2.fromOffset(PLATE_W, PORTRAIT - 8),
		ZIndex = Z.Chrome,
	}, {
		accent = accent, cut = 18,
		cuts = isPlayer and { "br" } or { "bl" },
		backdrop = C.Void,
	})
	-- Nearly unfilled. These plates are chrome; at the bevel's default fill they
	-- competed with the cards for attention and added to the boxy feel.
	plate.BackgroundTransparency = 0.55
	BattleTheme.glow(plate, accent, 0.45)

	local name = text(plate, {
		Name = "NameLabel",
		AnchorPoint = Vector2.new(xAnchor, 0),
		Position = UDim2.new(xAnchor, dir * 16, 0, 14),
		Size = UDim2.fromOffset(PLATE_W - 34, 28),
		Text = isPlayer and "PLAYER" or "ENEMY",
		TextXAlignment = isPlayer and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right,
		TextScaled = true,
		ZIndex = Z.Chrome + 2,
	})
	new("UITextSizeConstraint", { Parent = name, MaxTextSize = 24 })
	new("UIStroke", { Parent = name, Color = Color3.new(0, 0, 0), Thickness = 2, Transparency = 0.35 })

	local power = text(plate, {
		Name = "PowerLabel",
		AnchorPoint = Vector2.new(xAnchor, 0),
		Position = UDim2.new(xAnchor, dir * 16, 0, 44),
		Size = UDim2.fromOffset(PLATE_W - 34, 18),
		Text = "0 BP",
		TextColor3 = accent,
		TextXAlignment = isPlayer and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right,
		TextScaled = true,
		ZIndex = Z.Chrome + 2,
	})
	new("UITextSizeConstraint", { Parent = power, MaxTextSize = 15 })

	return { holder = holder, plate = plate, name = name, power = power,
	         portrait = frame, portraitStroke = frameStroke, art = art, accent = accent }
end

-- ── Effects rail ────────────────────────────────────────────────────
-- A small header that is always present, and chips that only exist while the
-- side actually has effects. No tall empty box when nothing is happening.
local function effectsRail(parent: Instance, side: string)
	local isPlayer = side == "player"
	local accent = isPlayer and C.Player or C.Enemy
	local xAnchor = isPlayer and 0 or 1

	local holder = new("Frame", {
		Name = isPlayer and "PlayerEffects" or "EnemyEffects",
		Parent = parent,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(xAnchor, 0.5),
		Position = UDim2.new(xAnchor, isPlayer and 32 or -32, 0.5, -10),
		-- Wide enough to show an effect name and its latest result without hover.
		-- The list still scrolls, so the battlefield stays clean on long fights.
		Size = UDim2.fromOffset(236, 260),
		ZIndex = Z.Chrome,
	})

	-- A label with a rule under it, not a panel. The bevelled box read as one
	-- more empty container on a screen that already had too many.
	local tab = new("Frame", {
		Name = "Tab",
		Parent = holder,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(xAnchor, 0),
		Position = UDim2.new(xAnchor, 0, 0, 0),
		Size = UDim2.fromOffset(236, 24),
		ZIndex = Z.Chrome,
	})
	new("Frame", {
		Name = "Rule",
		Parent = tab,
		AnchorPoint = Vector2.new(xAnchor, 1),
		Position = UDim2.new(xAnchor, 0, 1, 2),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		ZIndex = Z.Chrome,
	}, {
		new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, isPlayer and 0 or 1),
				NumberSequenceKeypoint.new(1, isPlayer and 1 or 0),
			}),
		}),
	})

	local title = text(tab, {
		Name = "Title",
		AnchorPoint = Vector2.new(xAnchor, 0.5),
		Position = UDim2.new(xAnchor, 0, 0.5, 0),
		Size = UDim2.fromScale(0.9, 0.8),
		Text = isPlayer and "YOUR EFFECTS" or "ENEMY EFFECTS",
		TextColor3 = accent,
		TextTransparency = 0.25,
		TextXAlignment = isPlayer and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right,
		TextScaled = true,
		ZIndex = Z.Chrome + 3,
	})
	new("UITextSizeConstraint", { Parent = title, MaxTextSize = 13 })

	-- Readable compact rows: effect name, latest result, and round are visible
	-- without hovering. Full details remain available on hover/click.
	local list = new("ScrollingFrame", {
		Name = "List",
		Parent = holder,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(xAnchor, 0),
		Position = UDim2.new(xAnchor, 0, 0, 34),
		Size = UDim2.fromOffset(236, 224),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 2,
		ScrollBarImageTransparency = 0.62,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = Z.Chrome,
	}, {
		new("UIListLayout", {
			Padding = UDim.new(0, 5),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
	})

	local empty = text(holder, {
		Name = "Empty",
		AnchorPoint = Vector2.new(xAnchor, 0),
		Position = UDim2.new(xAnchor, 0, 0, 40),
		Size = UDim2.fromOffset(150, 18),
		Text = "No effects yet",
		TextColor3 = C.TextDim,
		TextTransparency = 0.48,
		TextSize = 11,
		TextXAlignment = isPlayer and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right,
		ZIndex = Z.Chrome + 1,
	})

	return { holder = holder, tab = tab, list = list, empty = empty,
	         accent = accent, isPlayer = isPlayer }
end

-- ── A card seat on the battlefield ─────────────────────────────────────
-- Seats are pinned to the field's TOP and BOTTOM edges rather than placed by
-- scale. The stack is height-bound, and a scale position silently lets the
-- cards drift into the location (and into ROUND) as the window changes shape.
local function seat(parent: Instance, side: string, _unused: number?)
	local isPlayer = side == "player"
	local accent = isPlayer and C.Player or C.Enemy
	local w = BattleLayout.FieldCardWidth

	local holder = new("Frame", {
		Name = isPlayer and "PlayerSeat" or "EnemySeat",
		Parent = parent,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, isPlayer and 1 or 0),
		Position = UDim2.new(0.5, 0, isPlayer and 1 or 0, 0),
		Size = UDim2.fromOffset(w + 16, w * 1.45 + 16),
		ZIndex = Z.Card,
	})

	-- ── The lane ──────────────────────────────────────────────────────
	-- A band of the side's colour running the full width of the screen behind
	-- the card. This is what stops a 1v1 card game from reading as two small
	-- objects marooned in a black rectangle: the width is now territory, and
	-- each side visibly owns a half of the board. It is 14x the seat's width so
	-- it always overshoots the viewport, and its gradient fades it out long
	-- before the edges so there is no hard vertical cut anywhere.
	local lane = new("Frame", {
		Name = "Lane",
		Parent = holder,
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(14, 0, 0.92, 0),
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.94,
		BorderSizePixel = 0,
		ZIndex = Z.Field,
	}, {
		new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.30, 0.72),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(0.70, 0.72),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})

	-- Hairlines along the lane's outer edges give it a defined boundary rather
	-- than letting it dissolve into a smudge.
	local laneEdges = {}
	for _, edge in ipairs({ 0, 1 }) do
		local line = new("Frame", {
			Name = "LaneEdge",
			Parent = lane,
			AnchorPoint = Vector2.new(0.5, edge),
			Position = UDim2.fromScale(0.5, edge),
			Size = UDim2.new(1, 0, 0, 2),
			BackgroundColor3 = accent,
			BackgroundTransparency = 0.84,
			BorderSizePixel = 0,
			ZIndex = Z.Field + 1,
		}, {
			new("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.5, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		})
		table.insert(laneEdges, line)
	end

	-- The socket is now GEOMETRY ONLY - never a filled panel.
	--
	-- It used to be a translucent grey rectangle with a full outline, which is
	-- what made a seated card look like it was sitting in a box rather than on
	-- the battlefield. It still exists because the drag code measures against it,
	-- but it paints nothing at all.
	local socket = new("Frame", {
		Name = "Socket",
		Parent = holder,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = Z.Card - 1,
	})
	-- The pedestal: a soft ellipse of the side's own colour directly under where
	-- the card sits. It is completely hidden while the seat is idle, appears as
	-- temporary drag feedback, and becomes a restrained grounding shadow only
	-- while a card is actually present.
	local pedestal = new("Frame", {
		Name = "Pedestal",
		Parent = holder,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(0.94, 0, 0, 22),
		BackgroundColor3 = accent,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = Z.Card - 2,
	}, {
		new("UICorner", { CornerRadius = UDim.new(1, 0) }),
		new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
	BattleTheme.glow(pedestal, accent, 0.8)
	-- BattleTheme.glow authors visible strokes immediately. Seats must paint
	-- absolutely nothing at rest, so initialise those strokes hidden rather than
	-- relying on a tween that may still be visible for its first rendered frame.
	for i = 1, 3 do
		local glow = pedestal:FindFirstChild("Glow" .. i)
		if glow and glow:IsA("UIStroke") then glow.Transparency = 1 end
	end

	-- No permanent brackets, outline or panel: the invisible socket remains only
	-- as drag geometry. A short hint appears solely while a valid card is over it.
	local hint = text(socket, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.16),
		Text = isPlayer and "RELEASE TO PLAY" or "",
		TextColor3 = C.TextDim,
		TextTransparency = 0.55,
		TextScaled = true,
		Visible = false,
		ZIndex = Z.Card,
	})
	new("UITextSizeConstraint", { Parent = hint, MaxTextSize = 12 })

	-- Idle means truly empty. During a valid drag, only a soft ellipse and a faint
	-- temporary instruction appear. With a card present, the ellipse is a small
	-- grounding shadow rather than a visible slot.
	local function setEmpty(empty: boolean, strong: boolean?)
		local validDrag = empty and strong == true
		hint.Visible = validDrag and isPlayer
		pedestal.BackgroundTransparency = validDrag and 0.84 or 1
		if validDrag then
			BattleTheme.setGlow(pedestal, 1.1)
		else
			-- No active-card pedestal and no empty-seat marker. Only a valid drag
			-- is allowed to reveal this helper.
			for i = 1, 3 do
				local glow = pedestal:FindFirstChild("Glow" .. i)
				if glow and glow:IsA("UIStroke") then glow.Transparency = 1 end
			end
		end
	end
	setEmpty(true)

	return { holder = holder, socket = socket,
	         hint = hint, accent = accent, lane = lane, laneEdges = laneEdges,
	         pedestal = pedestal, setEmpty = setEmpty }
end

-- ── Build ───────────────────────────────────────────────────────────
function BattleLayout.build(parentGui: ScreenGui)
	local R = {}

	R.root = new("Frame", {
		Name = "Board",
		Parent = parentGui,
		BackgroundColor3 = C.Void,
		-- Near-opaque on purpose. At 0.12 the world and the whole roll HUD showed
		-- straight through and the screen read as panels floating over gameplay,
		-- which is the exact thing this redesign exists to kill.
		BackgroundTransparency = 0.02,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = Z.Backdrop,
	})

	-- Vignette: a second darker pane pinned behind everything sells "arena"
	-- rather than "menu over the world".
	new("UIGradient", {
		Parent = R.root,
		Rotation = 90,
		Color = ColorSequence.new(C.Navy, C.Void),
		-- Kept shallow. A UIGradient's Transparency MULTIPLIES the frame's own
		-- BackgroundTransparency, so the old 0.35 midpoint punched a hole straight
		-- through the "near-opaque" backdrop and the world showed through the
		-- middle of the board.
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, 0.10),
			NumberSequenceKeypoint.new(1, 0),
		}),
	})

	-- ── Arena backdrop ──────────────────────────────────────────────
	-- The location's own artwork, blown up to fill the whole window and pushed
	-- almost all the way down to black. It is nearly invisible as a picture and
	-- that is the point: it gives the empty two-thirds of a widescreen window a
	-- colour and a texture belonging to the place the fight is happening in,
	-- instead of flat #000. No new art is needed - it is the image the location
	-- panel is already showing.
	R.arena = new("ImageLabel", {
		Name = "Arena",
		Parent = R.root,
		BackgroundTransparency = 1,
		-- Deliberately almost gone. At anything brighter the pagoda reads as a
		-- photograph behind the cards and competes with them for attention; this
		-- is meant to be felt as colour in the room, not seen as a picture.
		ImageTransparency = 0.90,
		ImageColor3 = Color3.fromRGB(112, 124, 205),
		Size = UDim2.fromScale(1, 1),
		ScaleType = Enum.ScaleType.Crop,
		ZIndex = Z.Backdrop + 1,
	})

	-- Darken the arena image towards the middle so the cards and the location
	-- always sit against something quiet, and towards the corners so it reads as
	-- a lit stage rather than a wallpaper.
	R.arenaScrim = new("Frame", {
		Name = "ArenaScrim",
		Parent = R.root,
		BackgroundColor3 = C.Void,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = Z.Backdrop + 2,
	}, {
		new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.05),
				NumberSequenceKeypoint.new(0.5, 0.45),
				NumberSequenceKeypoint.new(1, 0.05),
			}),
		}),
	})

	R.player = identity(R.root, "player")
	R.enemy  = identity(R.root, "enemy")

	-- Round marker: text and a hairline, no container.
	R.round = text(R.root, {
		Name = "RoundLabel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(260, 28),
		Text = "ROUND 1",
		TextColor3 = C.Gold,
		TextScaled = true,
		ZIndex = Z.Chrome,
	})
	new("UITextSizeConstraint", { Parent = R.round, MaxTextSize = 26 })
	new("UIStroke", { Parent = R.round, Color = Color3.new(0, 0, 0), Thickness = 2.5, Transparency = 0.3 })

	R.field = new("Frame", {
		Name = "Field",
		Parent = R.root,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		-- Claims almost the whole window height. Two 235-tall card blocks plus a
		-- 156 location plus gaps needs ~680px; anything less and the enemy card
		-- and the location have to overlap.
		Position = UDim2.new(0.5, 0, 0.5, 6),
		Size = UDim2.new(0, 780, 1, -118),
		ZIndex = Z.Field,
	})

	-- ── The battle lane ────────────────────────────────────────────
	-- A vertical column of light running enemy card -> location -> player card,
	-- so the three read as one connected battlefield instead of three separate
	-- panels that happen to be stacked. Its gradient runs enemy red at the top
	-- through gold at the location to player violet at the bottom.
	R.energyLane = new("Frame", {
		Name = "EnergyLane",
		Parent = R.field,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 250, 1, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.9,
		BorderSizePixel = 0,
		ZIndex = Z.Field - 1,
	}, {
		new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, C.Enemy),
				ColorSequenceKeypoint.new(0.5, C.Gold),
				ColorSequenceKeypoint.new(1, C.Player),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.45),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})

	-- The bright core, and the gradient the controller scrolls to make the lane
	-- read as flowing energy rather than a static stripe.
	local core = new("Frame", {
		Name = "Core",
		Parent = R.field,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 2, 1, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		-- Faint. At 0.55 the bottom of this line pooled into a bright blob where it
		-- met the player's pedestal glow.
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
		ZIndex = Z.Field - 1,
	})
	R.energyFlow = new("UIGradient", {
		Parent = core,
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, C.Enemy),
			ColorSequenceKeypoint.new(0.5, C.Gold),
			ColorSequenceKeypoint.new(1, C.Player),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.22, 0.5),
			NumberSequenceKeypoint.new(0.5, 0.9),
			NumberSequenceKeypoint.new(0.78, 0.5),
			NumberSequenceKeypoint.new(1, 1),
		}),
	})

	R.enemySeat  = seat(R.field, "enemy")
	R.playerSeat = seat(R.field, "player")

	-- The neutral strip the two lanes meet at, full width behind the location.
	R.midline = new("Frame", {
		Name = "Midline",
		Parent = R.field,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(14, 0, 0, 2),
		BackgroundColor3 = C.Gold,
		BackgroundTransparency = 0.62,
		BorderSizePixel = 0,
		ZIndex = Z.Field,
	}, {
		new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})

	R.playerEffects = effectsRail(R.root, "player")
	R.enemyEffects  = effectsRail(R.root, "enemy")

	-- ── The location, dead centre and dominant ───────────────────────────
	-- Artwork floats directly in the battlefield. The old bevel/backdrop/glow
	-- read as a large empty square around it, so the host is now fully invisible.
	R.location = new("Frame", {
		Name = "Location",
		Parent = R.field,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(452, BattleLayout.LocationHeight),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = Z.Location,
	})

	-- Artwork carries more of its own colour now; the text gets its own scrim
	-- below rather than the whole image being washed out to stay readable.
	R.locationArt = new("ImageLabel", {
		Name = "Art",
		Parent = R.location,
		BackgroundTransparency = 1,
		ImageTransparency = 0.08,
		Size = UDim2.fromScale(1, 1),
		ScaleType = Enum.ScaleType.Crop,
		ZIndex = Z.Location,
	})

	-- The arena backdrop is the same picture. Mirroring it here rather than in
	-- the controller means the controller keeps its single "set the location art"
	-- line and cannot forget the second one.
	R.locationArt:GetPropertyChangedSignal("Image"):Connect(function()
		R.arena.Image = R.locationArt.Image
	end)

	-- Soft fades sit on the artwork itself; they improve lettering contrast
	-- without recreating a visible frame or container around the location.
	R.locationTitleScrim = new("Frame", {
		Name = "TitleScrim",
		Parent = R.location,
		Size = UDim2.new(1, 0, 0.42, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = Z.Location + 1,
	}, {
		new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.18),
				NumberSequenceKeypoint.new(0.62, 0.48),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})

	R.locationScrim = new("Frame", {
		Name = "TextScrim",
		Parent = R.location,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 108),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = Z.Location + 1,
	}, {
		new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.45, 0.28),
				NumberSequenceKeypoint.new(1, 0.18),
			}),
		}),
	})

	R.locationName = text(R.location, {
		Name = "LocationName",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(400, 44),
		Text = "LOCATION",
		TextScaled = true,
		ZIndex = Z.Location + 3,
	})
	new("UITextSizeConstraint", { Parent = R.locationName, MaxTextSize = 36, MinTextSize = 19 })
	new("UIStroke", { Parent = R.locationName, Color = Color3.new(0, 0, 0), Thickness = 4, Transparency = 0.04 })

	R.locationDesc = text(R.location, {
		Name = "LocationDesc",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 62),
		Size = UDim2.fromOffset(404, 84),
		Text = "",
		TextColor3 = C.Text,
		TextWrapped = true,
		TextScaled = true,
		ZIndex = Z.Location + 3,
	})
	new("UITextSizeConstraint", { Parent = R.locationDesc, MaxTextSize = 20, MinTextSize = 13 })
	new("UIStroke", { Parent = R.locationDesc, Color = Color3.new(0, 0, 0),
	                  Thickness = 3, Transparency = 0.08 })

	-- "ACTIVATED" flash, hidden until the location fires
	R.locationFlash = text(R.location, {
		Name = "Activated",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 0.34),
		Text = "ACTIVATED",
		TextColor3 = C.Gold,
		TextScaled = true,
		TextTransparency = 1,
		ZIndex = Z.Location + 8,
	})
	new("UITextSizeConstraint", { Parent = R.locationFlash, MaxTextSize = 40 })
	-- Transparency 1 to match the label. A UIStroke is NOT governed by its
	-- parent's TextTransparency, so a hidden label with a visible stroke leaves
	-- a ghost outline - which is exactly what showed "ACTIVATED" through the
	-- location description on the first build.
	new("UIStroke", {
		Name = "FlashStroke", Parent = R.locationFlash,
		Color = Color3.new(0, 0, 0), Thickness = 3, Transparency = 1,
	})

	-- Victory chance: small, under the field.
	-- Sits directly above LEAVE and shares its left edge, so the two read as a
	-- pair rather than two things that happen to be in the same corner.
	R.victory = text(R.root, {
		Name = "VictoryChance",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 30, 1, -92),
		Size = UDim2.fromOffset(200, 20),
		Text = "VICTORY 50%",
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		ZIndex = Z.Chrome,
	})
	new("UITextSizeConstraint", { Parent = R.victory, MaxTextSize = 15 })

	-- ── Hand: no container, just a positioning frame ───────────────────────
	-- The hand is a collapsible TRAY anchored to the bottom-right corner.
	-- This frame is ONE CARD in size and sits exactly where the collapsed pile
	-- sits. Cards anchor to its bottom-right corner and fan out to the LEFT by
	-- taking negative X offsets, so the tray's own rect never grows and nothing
	-- needs clipping.
	R.hand = new("Frame", {
		Name = "Hand",
		Parent = R.root,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -TRAY_MARGIN_X, 1, -TRAY_MARGIN_Y),
		Size = UDim2.fromOffset(BattleLayout.HandCardWidth,
		                        BattleLayout.HandCardWidth * 1.45),
		ZIndex = Z.Hand,
	})

	-- The dock the collapsed pile rests on. A single thin lit rule, NOT a panel:
	-- a filled box behind the cards was the largest piece of empty furniture on
	-- the screen and it made the tray read as a placeholder.
	R.trayPad = new("Frame", {
		Name = "TrayDock",
		Parent = R.root,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -TRAY_MARGIN_X + 10, 1, -TRAY_MARGIN_Y + 6),
		Size = UDim2.fromOffset(BattleLayout.HandCardWidth + 20, 2),
		BackgroundColor3 = C.Player,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = Z.Hand - 2,
	}, {
		new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
	BattleTheme.glow(R.trayPad, C.Player, 0.8)

	R.trayCount = text(R.root, {
		Name = "TrayCount",
		AnchorPoint = Vector2.new(1, 1),
		-- ABOVE the pile. Under it, the top card covered it and it collided with
		-- the dock rule.
		Position = UDim2.new(1, -TRAY_MARGIN_X,
		                     1, -(TRAY_MARGIN_Y + BattleLayout.HandCardWidth * 1.45 + 8)),
		Size = UDim2.fromOffset(150, 16),
		Text = "",
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextScaled = true,
		ZIndex = Z.Hand + 60,
	})
	new("UITextSizeConstraint", { Parent = R.trayCount, MaxTextSize = 13 })

	-- The hover target that expands the tray. An explicit button, not a
	-- transparent Frame - the same reason every card carries its own Hit button.
	R.trayHit = new("TextButton", {
		Name = "TrayHit",
		Parent = R.root,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -TRAY_MARGIN_X + 20, 1, -TRAY_MARGIN_Y + 20),
		Size = UDim2.fromOffset(BattleLayout.HandCardWidth + 40,
		                        BattleLayout.HandCardWidth * 1.45 + 40),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = Z.Hand - 1,
	}) :: TextButton

	-- ── Enemy tray ─────────────────────────────────────────────────────────
	-- The same pile as the player's, mirrored to the TOP of the right edge, and
	-- face down. Cards anchor to this frame's top-right corner and fan LEFT, so
	-- like the player's tray the frame itself is one card in size and never has
	-- to grow.
	--
	-- It opens on a CLICK, not on hover. The player's tray fans under the pointer
	-- because the pointer is going there anyway to pick a card up; nobody ever
	-- reaches for the enemy's hand, so hovering it open would only be something
	-- that happens by accident while crossing the board.
	R.enemyHand = new("Frame", {
		Name = "EnemyHand",
		Parent = R.root,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -ENEMY_TRAY_X, 0, ENEMY_TRAY_Y),
		Size = UDim2.fromOffset(BattleLayout.HandCardWidth,
		                        BattleLayout.HandCardWidth * 1.45),
		ZIndex = Z.Hand,
	})

	-- Dock rule, above the pile this time: the enemy's cards hang DOWN off it.
	R.enemyTrayPad = new("Frame", {
		Name = "EnemyTrayDock",
		Parent = R.root,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -ENEMY_TRAY_X + 10, 0, ENEMY_TRAY_Y - 6),
		Size = UDim2.fromOffset(BattleLayout.HandCardWidth + 20, 2),
		BackgroundColor3 = C.Enemy,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = Z.Hand - 2,
	}, {
		new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
	BattleTheme.glow(R.enemyTrayPad, C.Enemy, 0.8)

	R.enemyTrayCount = text(R.root, {
		Name = "EnemyTrayCount",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -ENEMY_TRAY_X,
		                     0, ENEMY_TRAY_Y + BattleLayout.HandCardWidth * 1.45 + 8),
		Size = UDim2.fromOffset(150, 16),
		Text = "",
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextScaled = true,
		ZIndex = Z.Hand + 60,
	})
	new("UITextSizeConstraint", { Parent = R.enemyTrayCount, MaxTextSize = 13 })

	-- The toggle. Drawn from two rotated bars rather than set as a text glyph:
	-- a font that is missing an arrow codepoint renders a box and there is no
	-- way to detect that at runtime, which is the same reason the status badges
	-- are three letters instead of symbols.
	R.enemyToggle = new("TextButton", {
		Name = "EnemyTrayToggle",
		Parent = R.root,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(ENEMY_TRAY_X + BattleLayout.HandCardWidth + 12),
		                     0, ENEMY_TRAY_Y + BattleLayout.HandCardWidth * 1.45 * 0.5),
		Size = UDim2.fromOffset(28, 46),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		ZIndex = Z.Hand + 62,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, 8) }),
		new("UIStroke", { Color = C.Enemy, Thickness = 1, Transparency = 0.45 }),
	}) :: TextButton

	-- The chevron itself lives in its own frame so the whole mark can be rotated
	-- 180 degrees in one tween when the tray opens.
	-- Built pointing RIGHT. The controller starts it rotated 180 so a shut tray
	-- shows "<" (the direction the fan will travel), and tweens back to 0 to
	-- show ">" once it is open.
	R.enemyToggleGlyph = new("Frame", {
		Name = "Chevron",
		Parent = R.enemyToggle,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(14, 14),
		BackgroundTransparency = 1,
		ZIndex = Z.Hand + 63,
	})
	for _, spec in ipairs({ { 45, -3 }, { -45, 3 } }) do
		new("Frame", {
			Parent = R.enemyToggleGlyph,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, spec[2] * 1.5),
			Size = UDim2.fromOffset(11, 2),
			Rotation = spec[1],
			BackgroundColor3 = C.Enemy,
			BorderSizePixel = 0,
			ZIndex = Z.Hand + 63,
		}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	end

	-- Layer the dragged card sits in, so it clears the hand and the field.
	R.dragLayer = new("Frame", {
		Name = "DragLayer",
		Parent = R.root,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = Z.Drag,
	})

	-- ── Leave ───────────────────────────────────────────────────────
	R.leave = new("TextButton", {
		Name = "LeaveButton",
		Parent = R.root,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 30, 1, -30),
		Size = UDim2.fromOffset(168, 52),
		BackgroundColor3 = Color3.fromRGB(58, 12, 30),
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		ZIndex = Z.Chrome,
	}, {
		new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.fromRGB(92, 20, 48), Color3.fromRGB(40, 8, 22)),
		}),
		new("UIStroke", { Color = C.Enemy, Thickness = 2, Transparency = 0.1 }),
	})
	-- angled corners in the backdrop colour
	for _, corner in ipairs({ "tr", "bl" }) do
		local a = corner == "tr" and UDim2.fromScale(1, 0) or UDim2.fromScale(0, 1)
		new("Frame", {
			Parent = R.leave, AnchorPoint = Vector2.new(0.5, 0.5), Position = a,
			Size = UDim2.fromOffset(22, 22), Rotation = 45,
			BackgroundColor3 = C.Void, BorderSizePixel = 0, ZIndex = Z.Chrome + 3,
		}, { new("UIStroke", { Color = C.Enemy, Thickness = 1.6, Transparency = 0.2 }) })
	end
	BattleTheme.glow(R.leave, C.Enemy, 0.7)

	R.leaveLabel = text(R.leave, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.5),
		Text = "LEAVE",
		TextScaled = true,
		ZIndex = Z.Chrome + 4,
	})
	new("UITextSizeConstraint", { Parent = R.leaveLabel, MaxTextSize = 22 })

	-- ── Notice line (errors / "wait for the round") ────────────────────────
	R.notice = text(R.root, {
		Name = "Notice",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -220),
		Size = UDim2.fromOffset(560, 22),
		Text = "",
		TextColor3 = C.Gold,
		TextScaled = true,
		TextTransparency = 1,
		ZIndex = Z.Chrome,
	})
	new("UITextSizeConstraint", { Parent = R.notice, MaxTextSize = 16 })
	new("UIStroke", {
		Parent = R.notice,
		Color = Color3.new(0, 0, 0),
		Thickness = 2.5,
		Transparency = 0.16,
	})

	-- A lightweight result beat. It has no panel or box: the title, subline and
	-- two fading rules briefly replace the battlefield before the HUD returns.
	R.endOverlay = new("CanvasGroup", {
		Name = "BattleResult",
		Parent = R.root,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		GroupTransparency = 1,
		Visible = false,
		ZIndex = Z.Modal + 18,
	})
	R.endTitle = text(R.endOverlay, {
		Name = "ResultTitle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromOffset(620, 82),
		Text = "VICTORY",
		TextColor3 = C.Good,
		TextScaled = true,
		ZIndex = Z.Modal + 22,
	})
	new("UITextSizeConstraint", { Parent = R.endTitle, MaxTextSize = 68, MinTextSize = 30 })
	new("UIStroke", {
		Parent = R.endTitle,
		Color = Color3.new(0, 0, 0),
		Thickness = 5,
		Transparency = 0.02,
	})
	R.endSubtitle = text(R.endOverlay, {
		Name = "ResultSubtitle",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(420, 26),
		Text = "BATTLE COMPLETE",
		TextColor3 = C.TextDim,
		TextScaled = true,
		ZIndex = Z.Modal + 22,
	})
	new("UITextSizeConstraint", { Parent = R.endSubtitle, MaxTextSize = 17, MinTextSize = 11 })
	new("UIStroke", {
		Parent = R.endSubtitle,
		Color = Color3.new(0, 0, 0),
		Thickness = 2,
		Transparency = 0.18,
	})
	for _, side in ipairs({ -1, 1 }) do
		local rule = new("Frame", {
			Name = "ResultRule",
			Parent = R.endOverlay,
			AnchorPoint = Vector2.new(side < 0 and 1 or 0, 0.5),
			Position = UDim2.new(0.5, side * 225, 0.5, 0),
			Size = UDim2.fromOffset(160, 2),
			BackgroundColor3 = C.Good,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			ZIndex = Z.Modal + 21,
		})
		new("UIGradient", {
			Parent = rule,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, side < 0 and 1 or 0),
				NumberSequenceKeypoint.new(1, side < 0 and 0 or 1),
			}),
		})
	end

	-- Full-screen curtain used only for the first few frames of a battle. This
	-- hides layout construction and makes entering combat feel intentional.
	R.entryCurtain = new("Frame", {
		Name = "EntryCurtain",
		Parent = R.root,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Void,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = Z.Modal + 40,
	})

	-- ── Modals ──────────────────────────────────────────────────────
	-- Inspect: dim + a large card. TextButton so a click anywhere closes it.
	R.inspectDim = new("TextButton", {
		Name = "InspectDim",
		Parent = parentGui,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		ZIndex = Z.Modal,
	})

	R.inspectHolder = new("Frame", {
		Name = "InspectHolder",
		Parent = R.inspectDim,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(BattleLayout.InspectWidth, BattleLayout.InspectWidth * 1.45),
		ZIndex = Z.Modal + 2,
	}, {
		new("UIScale", { Scale = 0.8 }),
	})

	R.inspectClose = new("TextButton", {
		Name = "Close",
		Parent = R.inspectDim,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, -(BattleLayout.InspectWidth * 1.45) / 2 - 52),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = C.Panel,
		BorderSizePixel = 0,
		Text = "X",
		FontFace = Theme.font(),
		TextSize = 24,
		TextColor3 = C.Text,
		Visible = false,
		ZIndex = Z.Modal + 6,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, 10) }),
		new("UIStroke", { Color = C.Enemy, Thickness = 2, Transparency = 0.1 }),
	})

	-- Leave confirmation
	R.confirmDim = new("TextButton", {
		Name = "ConfirmDim",
		Parent = parentGui,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		ZIndex = Z.Modal + 20,
	})

	R.confirmPanel = BattleTheme.bevel(R.confirmDim, {
		Name = "ConfirmPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(400, 190),
		ZIndex = Z.Modal + 22,
	}, { accent = C.Enemy, cut = 26, cuts = { "tl", "br" }, backdrop = C.Void })
	BattleTheme.glow(R.confirmPanel, C.Enemy, 1)
	new("UIScale", { Parent = R.confirmPanel, Scale = 0.85 })

	text(R.confirmPanel, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 28),
		Size = UDim2.fromOffset(330, 40),
		Text = "LEAVE BATTLE?",
		TextScaled = true,
		ZIndex = Z.Modal + 24,
	})

	local function choice(name: string, x: number, fill: Color3, accent: Color3, labelText: string)
		local b = new("TextButton", {
			Name = name,
			Parent = R.confirmPanel,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(x, 0, 1, -26),
			Size = UDim2.fromOffset(150, 50),
			BackgroundColor3 = fill,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			ZIndex = Z.Modal + 24,
		}, {
			new("UICorner", { CornerRadius = UDim.new(0, 8) }),
			new("UIStroke", { Color = accent, Thickness = 2, Transparency = 0.1 }),
		})
		text(b, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.8, 0.5),
			Text = labelText,
			TextScaled = true,
			ZIndex = Z.Modal + 26,
		})
		return b
	end
	R.confirmYes = choice("Yes", 0.29, Color3.fromRGB(86, 18, 42), C.Enemy, "YES")
	R.confirmNo  = choice("No", 0.71, Color3.fromRGB(34, 26, 66), C.Player, "NO")

	return R
end

-- ── Fit to the viewport ─────────────────────────────────────────────
-- Resizes the pieces that are built once. The hand and the cards themselves are
-- rebuilt from BattleLayout.HandCardWidth / FieldCardWidth on every snapshot, so
-- they pick the new scale up on their own.
function BattleLayout.fit(R, viewportY: number, viewportX: number?)
	viewportX = viewportX or math.max(R.root.AbsoluteSize.X, 800)
	BattleLayout.applyScale(viewportY)

	local k = BattleLayout.Scale
	local w = BattleLayout.FieldCardWidth
	local seatH = w * 1.45 + SEAT_PAD
	local seatSize = UDim2.fromOffset(w + SEAT_PAD, seatH)
	R.enemySeat.holder.Size = seatSize
	R.playerSeat.holder.Size = seatSize

	local locH = BattleLayout.LocationHeight
	R.location.Size = UDim2.fromOffset(math.floor(500 * k + 0.5), locH)
	R.locationScrim.Size = UDim2.new(1, 0, 0, math.floor(locH * 0.69 + 0.5))
	R.locationName.Position = UDim2.new(0.5, 0, 0, math.floor(locH * 0.09 + 0.5))
	R.locationName.Size = UDim2.fromOffset(math.floor(440 * k), math.floor(locH * 0.28))
	R.locationDesc.Position = UDim2.new(0.5, 0, 0, math.floor(locH * 0.39 + 0.5))
	R.locationDesc.Size = UDim2.fromOffset(math.floor(444 * k), math.floor(locH * 0.54))

	-- Vertical placement is solved, not pinned to an edge. The field is sized to
	-- exactly its own contents and the leftover height is split evenly above and
	-- below it, so the board sits centred. With the hand moved out to the right
	-- edge nothing below the board needs reserving any more.
	local hw = BattleLayout.HandCardWidth
	local handH = math.floor(hw * 1.45 + 0.5)
	local fieldH = math.floor(seatH * 2 + locH + SEAT_GAP * 2)

	local slack = math.max(0, viewportY - (ROUND_BAND + fieldH + BOTTOM_PAD))
	local fieldTop = math.floor(ROUND_BAND + slack * 0.5)

	R.field.AnchorPoint = Vector2.new(0.5, 0)
	R.field.Position = UDim2.new(0.5, 0, 0, fieldTop)
	R.field.Size = UDim2.fromOffset(math.max(760, math.floor(w * 5)), fieldH)

	-- The tray, and the furniture pinned to it.
	R.hand.AnchorPoint = Vector2.new(1, 1)
	R.hand.Position = UDim2.new(1, -TRAY_MARGIN_X, 1, -TRAY_MARGIN_Y)
	R.hand.Size = UDim2.fromOffset(hw, handH)

	R.trayPad.Position = UDim2.new(1, -TRAY_MARGIN_X + 10, 1, -TRAY_MARGIN_Y + 6)
	R.trayPad.Size = UDim2.fromOffset(hw + 20, 2)
	R.trayHit.Position = UDim2.new(1, -TRAY_MARGIN_X + 20, 1, -TRAY_MARGIN_Y + 20)
	R.trayHit.Size = UDim2.fromOffset(hw + 40, handH + 40)
	R.trayCount.Position = UDim2.new(1, -TRAY_MARGIN_X, 1, -(TRAY_MARGIN_Y + handH + 8))

	R.enemyHand.Position = UDim2.new(1, -ENEMY_TRAY_X, 0, ENEMY_TRAY_Y)
	R.enemyHand.Size = UDim2.fromOffset(hw, handH)
	R.enemyTrayPad.Position = UDim2.new(1, -ENEMY_TRAY_X + 10, 0, ENEMY_TRAY_Y - 6)
	R.enemyTrayPad.Size = UDim2.fromOffset(hw + 20, 2)
	R.enemyTrayCount.Position = UDim2.new(1, -ENEMY_TRAY_X, 0, ENEMY_TRAY_Y + handH + 8)
	R.enemyToggle.Position = UDim2.new(1, -(ENEMY_TRAY_X + hw + 12), 0, ENEMY_TRAY_Y + handH * 0.5)

	-- How far left the expanded fan may reach. Bounded so the leftmost card can
	-- never slide over the player's own card in the centre of the board, which is
	-- the one thing the tray must never cover.
	local fieldRightEdge = viewportX / 2 + (w + SEAT_PAD) / 2
	BattleLayout.TraySpan = math.clamp(
		viewportX - TRAY_MARGIN_X - fieldRightEdge - 70,
		hw + 40, TRAY_SPAN_MAX)

	-- The enemy tray needs its OWN bound. It starts a whole nameplate further
	-- left than the player's, so reusing TraySpan let its fan reach across the
	-- board and cover the enemy's own card - the one thing each tray must
	-- never hide.
	BattleLayout.EnemyTraySpan = math.clamp(
		viewportX - ENEMY_TRAY_X - fieldRightEdge - 40,
		hw + 30, TRAY_SPAN_MAX)

	R.inspectHolder.Size =
		UDim2.fromOffset(BattleLayout.InspectWidth, BattleLayout.InspectWidth * 1.45)
	R.inspectClose.Position =
		UDim2.new(0.5, 0, 0.5, -(BattleLayout.InspectWidth * 1.45) / 2 - 52)
end

return BattleLayout

