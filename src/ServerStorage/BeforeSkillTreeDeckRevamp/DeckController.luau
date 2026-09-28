--!strict
-- The Deck screen.
--
-- BUILT IN CODE, DELIBERATELY. The previous version bound to a hand-authored
-- panel in StarterGui, which was the right call while the layout was a fixed
-- picture with holes punched in it. It is not right any more: the deck band is
-- GameConfig.AttackSlots wide and the collection is however many cards you own,
-- so both change shape with data. A layout whose shape comes from data has to
-- be built from data.
--
-- StarterGui.DeckScreen is left in place but disabled, so the artwork is not
-- lost and this is revertible.
--
-- SHAPE
--   header      close / deck preset / slot count
--   tabs        ATTACK | SUPPORT
--   deck band   your lineup, as FULL cards - the thing you are building
--   collection  everything you own, as compact tiles - the thing you pick from
--
-- The two card representations are deliberately different. A full card is for
-- READING; a tile is for FINDING. Making one do both jobs is what made the old
-- screen feel like everything was competing for attention at once.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local CardDefinitions = require(ReplicatedStorage.Shared.Config.CardDefinitions)
local SupportDefinitions = require(ReplicatedStorage.Shared.Config.SupportDefinitions)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
local CardStats = require(ReplicatedStorage.Shared.Util.CardStats)
local CardRenderer = require(ReplicatedStorage.Shared.UI.CardRenderer)
local CardTile = require(ReplicatedStorage.Shared.UI.CardTile)
local RestrictionTip = require(ReplicatedStorage.Shared.UI.RestrictionTip)
local CardActions = require(ReplicatedStorage.Shared.UI.CardActions)
local PanelHeader = require(ReplicatedStorage.Shared.UI.PanelHeader)
local Shine = require(ReplicatedStorage.Shared.UI.Shine)
local Sfx = require(ReplicatedStorage.Shared.UI.Sfx)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local player = Players.LocalPlayer

local DeckController = {}
DeckController.Name = "DeckController"

-- palette
local INK       = Color3.fromRGB(9, 10, 16)
local PANEL     = Color3.fromRGB(19, 21, 33)
local PANEL_2   = Color3.fromRGB(27, 30, 46)
local LINE      = Color3.fromRGB(56, 60, 90)
local TEXT      = Color3.fromRGB(236, 238, 248)
local MUTED     = Color3.fromRGB(146, 152, 178)
local ATTACK_C  = Color3.fromRGB(255, 96, 72)
local SUPPORT_C = Color3.fromRGB(90, 210, 255)
local PURPLE    = Color3.fromRGB(178, 112, 255)

-- Same sweep art the HUD buttons use, so the light travelling across a deck
-- card reads as the same material as the rest of the game.
local SWEEP_IMAGE = "rbxassetid://135060446578504"
-- Panel dressing.
local BACKDROP_IMAGE = "rbxassetid://94268331444793"
-- Wider, fainter and softer than the HUD's. A button sweep is a quick glint on
-- a small target; on a card the size of a playing card the same narrow hard
-- band looks like a scanline, so this one is nearly half the card wide and much
-- more transparent - it reads as light moving under glass rather than a stripe.
local SWEEP_WIDTH = 0.46
local SWEEP_TRANSPARENCY = 0.9
local SWEEP_LAYERS = 3

-- Deck cards are built once at this width and then scaled to fit their holder.
-- Rebuilding on every resize would throw away and re-stack thirteen Shine
-- strokes per card; a UIScale costs nothing and keeps proportions exact.
local CARD_REF_W = 240
local CARD_REF_H = 322
local CARD_ASPECT = CARD_REF_W / CARD_REF_H
local SLOT_GAP = 8
local TILE_W = 112
local TILE_H = math.floor(TILE_W * 1.06) + 22

-- The hover preview, in pixels. Big enough to actually read ability text at a
-- glance, which is the entire reason it exists.
local POPOUT_W = 300
local POPOUT_H = math.floor(POPOUT_W / CARD_ASPECT)

local SORTS = { "Rarity", "Level", "Name", "Copies" }

-- A tile is this many times taller than it is wide. CardTile builds to the same
-- ratio, so keeping it here lets the grid resize cells without ever distorting
-- a card: only the width is chosen, the height follows from it.
local TILE_RATIO = 1.06

--=========================================================================--
-- COLLECTION DRAWER
--
-- EVERY number that shapes the drawer lives in this one table. Heights are
-- fractions of the BODY frame (everything below the tabs) rather than pixels,
-- so the drawer holds its proportions on a laptop and an ultrawide alike.
--=========================================================================--
local DRAWER = {
	-- Resting height. This is also the only height the DECK BAND is ever sized
	-- around: the band is built once to fill what is left above a collapsed
	-- drawer and then never moves again, no matter what the drawer does.
	CollapsedHeight = 0.28,
	-- Height when open. The band is NOT shrunk to make room - the drawer simply
	-- covers it. Deck is the workspace; the drawer is pulled out over the top.
	ExpandedHeight  = 0.62,

	-- The slice along the bottom of the body that arms the drawer. Deliberately
	-- deeper than the collapsed drawer itself, so moving the cursor downwards
	-- opens it slightly BEFORE arriving - the drawer anticipates rather than
	-- waits, which is what makes it feel like it was already coming.
	ActivationZone = 0.30,

	OpenTime  = 0.30,
	CloseTime = 0.34,
	-- Out on the way open (fast start, soft landing - it arrives eagerly),
	-- InOut on the way closed (it leaves politely rather than dropping).
	OpenStyle      = Enum.EasingStyle.Quint,
	OpenDirection  = Enum.EasingDirection.Out,
	CloseStyle     = Enum.EasingStyle.Quad,
	CloseDirection = Enum.EasingDirection.InOut,

	-- Anti-flicker. The cursor has to MEAN it before anything moves, and it
	-- gets a moment of doubt on the way out. Without these two numbers, a
	-- cursor crossing the activation edge produces open/close/open/close.
	OpenDelay  = 0.08,
	CloseGrace = 0.16,

	-- The grid derives its cell width from these: the drawer measures itself,
	-- divides by the column count and clamps. Cards grow on a bigger monitor
	-- without ever becoming absurd, and never stretch - only the width is
	-- chosen, the height comes from TILE_RATIO.
	ExpandedColumns  = 7,
	CollapsedColumns = 10,
	MinCell = 92,
	MaxCell = 150,
	CellGap = 12,
	GridPad = 14,

	HoverScale = 1.06,
	HoverTime  = 0.12,

	-- The drawer's chrome - handle, title, toolbar, rule - costs this many
	-- pixels no matter how short the window is, so a percentage alone can leave
	-- the grid with negative height on a small screen. This is the floor the
	-- drawer refuses to go below; on any normal display the percentage is
	-- larger and this never applies.
	ChromeHeight = 100,
	MinDrawerHeight = 190,
}

-- The whole screen's stacking order, in one place. With Sibling ZIndex
-- behaviour a subtree is placed by its ROOT's ZIndex, so the drawer sitting at
-- 50 beside a band at 5 puts every card in the drawer above every card in the
-- deck - which is the one thing the overlay absolutely depends on.
local Z = {
	DeckBand    = 5,
	DrawerShade = 48,
	Drawer      = 50,
	Grid        = 52,
	Tile        = 55,
	Chrome      = 58,
	Controls    = 60,
	TileHover   = 70,
	Dropdown    = 80,
	Popout      = 90,
}

-- Drawer dressing: charcoal with a purple bias rather than the flat panel
-- grey, so it reads as a separate object floating in front of the deck.
local DRAWER_BG   = Color3.fromRGB(16, 13, 26)
local DRAWER_LINE = Color3.fromRGB(96, 76, 148)

local profile = nil
local state = { mode = "Attack", search = "", variant = "All", sort = "Rarity" }
-- Which slot the player armed for the next pick. nil = just browsing.
local pendingSlot = nil
-- Drawer open/closed. Read by Refresh so freshly built tiles are born at the
-- size the drawer is currently showing.
local drawerExpanded = false

local ui = {}
local slotViews = {}
-- Fingerprint of the card inventory currently drawn in the collection. Deck
-- equips do not change it, so their ProfileSync can update in place.
local collectionFingerprint: string? = nil

local function new(class: string, props: {[string]: any}, children: {Instance}?): any
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		if k ~= "Parent" then (inst :: any)[k] = v end
	end
	for _, c in ipairs(children or {}) do c.Parent = inst end
	if props.Parent then inst.Parent = props.Parent end
	return inst
end

local function corner(radius: number): UICorner
	return new("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function stroke(colour: Color3, thickness: number, transparency: number?): UIStroke
	return new("UIStroke", { Color = colour, Thickness = thickness,
		Transparency = transparency or 0, LineJoinMode = Enum.LineJoinMode.Round })
end

-- Text outlines are sized FROM THE TEXT, never a flat number.
--
-- The game font is AccanthisADFStd, a thin display face. A 2.5px outline on a
-- 13px label of it thickens every stem and fills the counters, and the result
-- reads as a bold weight - which is exactly what picking a custom face was
-- meant to avoid. Theme.Weight is deliberately Regular for the same reason.
-- This keeps the outline as separation from the background and nothing more.
local function textOutline(label: TextLabel, transparency: number?): UIStroke
	return stroke(INK, math.clamp(label.TextSize * 0.055, 1, 2.2), transparency)
end

-- The travelling outline used for the layout itself, as opposed to the ones on
-- cards. Same rule as every other palette here: first and last colour must
-- match or the gradient jumps on each wrap.
local function frameSpec(colour: Color3, strength: number)
	local pale = colour:Lerp(Color3.new(1, 1, 1), 0.55)
	local deep = colour:Lerp(Color3.new(0, 0, 0), 0.4)
	return {
		baseColour = colour,
		baseThickness = 2,
		baseTransparency = 0.4,
		glowColours = { colour, pale, deep, pale, colour },
		glowScale = strength,
		travel = 3.4,
	}
end

local function accent(): Color3
	return state.mode == "Support" and SUPPORT_C or ATTACK_C
end

local function slotType(): string
	return state.mode == "Support" and "support" or "attack"
end

local function slotCount(kind: string): number
	return kind == "attack" and GameConfig.AttackSlots or GameConfig.SupportSlots
end

local function defOf(cardId: string)
	return CardDefinitions.get(cardId) or SupportDefinitions.get(cardId)
end

local function isSupportId(cardId: string): boolean
	return SupportDefinitions.get(cardId) ~= nil
end

local function activePreset()
	if not profile or not profile.decks then return { attack = {}, support = {} } end
	local index = profile.decks.active or 1
	return profile.decks.presets[index] or { attack = {}, support = {} }
end

-- collection filtering

local function ownedList()
	if not profile then return {} end
	local list = {}
	for key, entry in pairs(profile.cards) do
		local cardId, variantId = CardStats.parseKey(key)
		local def = cardId and defOf(cardId)
		if def and variantId then
			list[#list + 1] = {
				cardId = cardId, variant = variantId, level = entry.level or 0,
				count = entry.count or 1, def = def,
			}
		end
	end
	return list
end

local function passesFilters(item): boolean
	if isSupportId(item.cardId) ~= (state.mode == "Support") then return false end
	if state.variant ~= "All" and item.variant ~= state.variant then return false end
	if state.search ~= "" then
		if not item.def.name:lower():find(state.search:lower(), 1, true) then return false end
	end
	return true
end

local function sortList(list)
	local by = state.sort
	table.sort(list, function(a, b)
		if by == "Name" then
			if a.def.name ~= b.def.name then return a.def.name < b.def.name end
		elseif by == "Level" then
			if a.level ~= b.level then return a.level > b.level end
		elseif by == "Copies" then
			if a.count ~= b.count then return a.count > b.count end
		end
		-- Rarity is the default AND the tiebreak for every other sort, so two
		-- cards that match on the chosen key still come out in a stable,
		-- meaningful order rather than whatever pairs() happened to produce.
		local ra = VariantConfig.effectiveRarity(a.def.baseRarity, a.variant)
		local rb = VariantConfig.effectiveRarity(b.def.baseRarity, b.variant)
		if ra ~= rb then return ra > rb end
		return a.def.name < b.def.name
	end)
end

-- Which copies are already in the current lineup, so tiles can say so.
local function equippedKeys(): {[string]: number}
	local out = {}
	local deck = activePreset()[slotType()] or {}
	for i = 1, slotCount(slotType()) do
		local slot = deck[i]
		if slot then out[CardStats.key(slot.cardId, slot.variant)] = i end
	end
	return out
end

-- small widgets

local function textLabel(props, children): TextLabel
	local d = { BackgroundTransparency = 1, FontFace = Theme.font(),
		TextColor3 = TEXT, TextXAlignment = Enum.TextXAlignment.Left }
	for k, v in pairs(props) do d[k] = v end
	return new("TextLabel", d, children)
end

-- Every interactive surface gets the same treatment: a lifted fill, a real
-- outline, and an ink stroke on its own text. Without the text stroke the
-- letters sit flat on the button and the whole control reads as a coloured
-- rectangle rather than something pressable.
local function styleButton(btn: GuiButton, label: TextLabel?, tint: Color3?)
	-- The resting colour lives in an ATTRIBUTE, not a closure. The tab buttons
	-- get recoloured by RefreshHeader every time the mode changes, and a captured
	-- local would mean the next MouseLeave snapped them back to whatever they
	-- were built as - so an inactive tab would look active as soon as you
	-- brushed past it.
	btn:SetAttribute("BaseColour", tint or PANEL_2)
	btn.BackgroundColor3 = tint or PANEL_2
	btn.AutoButtonColor = false

	local function base(): Color3
		return btn:GetAttribute("BaseColour") or PANEL_2
	end

	local outline = btn:FindFirstChildOfClass("UIStroke")
		or stroke((tint or LINE):Lerp(Color3.new(1, 1, 1), 0.25), 2, 0.15)
	outline.Thickness = 2
	outline.Parent = btn

	if label and not label:FindFirstChildOfClass("UIStroke") then
		local s = textOutline(label)
		s.Parent = label
	end

	-- Hover lifts the outline rather than the fill: brightening the fill on a
	-- dark panel washes the label out.
	local rest = 0.15
	btn.MouseEnter:Connect(function()
		rest = outline.Transparency
		outline.Transparency = 0
		btn.BackgroundColor3 = base():Lerp(Color3.new(1, 1, 1), 0.09)
	end)
	btn.MouseLeave:Connect(function()
		outline.Transparency = rest
		btn.BackgroundColor3 = base()
	end)
	Sfx.bindButton(btn)
end

-- A pill button carrying a dropdown list. Returns the button and a setter for
-- its caption, so callers never reach into the children.
-- `zBase` is the button's own ZIndex; the list opens 20 above it so it can
-- never be swallowed by whatever it opens over.
local function dropdown(parent: Instance, width: number, options: {string},
	captionFor: (string) -> string, onPick: (string) -> (), zBase: number?)

	local zb = zBase or 30

	local btn = new("TextButton", { Parent = parent, Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = PANEL_2, AutoButtonColor = false, Text = "",
		ZIndex = zb }, { corner(10) })

	local caption = textLabel({ Parent = btn, Position = UDim2.new(0, 10, 0, 0),
		Size = UDim2.new(1, -26, 1, 0), Text = "", TextSize = 13, ZIndex = zb + 1 })
	textLabel({ Parent = btn, AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0, 12, 0, 12),
		Text = "v", TextSize = 11, TextColor3 = MUTED, ZIndex = zb + 1 })
	styleButton(btn, caption)

	-- Opens downward at a high ZIndex so the collection scroller underneath can
	-- never swallow it.
	local list = new("Frame", { Parent = parent, Visible = false,
		Position = UDim2.new(0, 0, 1, 4), Size = UDim2.new(1, 0, 0, #options * 26 + 8),
		BackgroundColor3 = PANEL_2, ZIndex = zb + 20 },
		{ corner(10), stroke(LINE, 1.5),
			new("UIListLayout", { Padding = UDim.new(0, 2),
				SortOrder = Enum.SortOrder.LayoutOrder }),
			new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
				PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }) })

	for i, opt in ipairs(options) do
		local row = new("TextButton", { Parent = list, LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, 24), BackgroundColor3 = PANEL,
			BackgroundTransparency = 0.35, AutoButtonColor = false,
			Text = captionFor(opt), FontFace = Theme.font(), TextSize = 12,
			TextColor3 = TEXT, ZIndex = zb + 21 }, { corner(7), stroke(INK, 2) })
		Sfx.bindButton(row)
		row.MouseEnter:Connect(function() row.BackgroundTransparency = 0 end)
		row.MouseLeave:Connect(function() row.BackgroundTransparency = 0.35 end)
		row.Activated:Connect(function()
			list.Visible = false
			onPick(opt)
		end)
	end

	Sfx.bindButton(btn)
	btn.Activated:Connect(function() list.Visible = not list.Visible end)

	return btn, function(text: string) caption.Text = text end, list
end

-- drawer geometry

-- The cell width for a given state, measured from the grid rather than assumed.
-- Columns are a TARGET, not a promise: the clamp wins, so a very wide panel
-- simply fits more columns of a sensible size instead of six enormous ones.
local function cellWidthFor(expanded: boolean): number
	if not ui.grid then return DRAWER.MinCell end
	local available = ui.grid.AbsoluteSize.X
	if available <= 0 then return DRAWER.MinCell end
	local columns = expanded and DRAWER.ExpandedColumns or DRAWER.CollapsedColumns
	local usable = available - DRAWER.GridPad * 2 - 8 - DRAWER.CellGap * (columns - 1)
	return math.clamp(math.floor(usable / columns), DRAWER.MinCell, DRAWER.MaxCell)
end

local function drawerTweenInfo(expanded: boolean): TweenInfo
	return expanded
		and TweenInfo.new(DRAWER.OpenTime, DRAWER.OpenStyle, DRAWER.OpenDirection)
		or TweenInfo.new(DRAWER.CloseTime, DRAWER.CloseStyle, DRAWER.CloseDirection)
end

-- Cells are TWEENED, not snapped, so the cards grow with the drawer instead of
-- popping to their new size the instant it starts moving.
local function applyCells(expanded: boolean, animate: boolean)
	if not ui.gridLayout then return end
	local w = cellWidthFor(expanded)
	local target = UDim2.new(0, w, 0, math.floor(w * TILE_RATIO))
	if animate then
		TweenService:Create(ui.gridLayout, drawerTweenInfo(expanded),
			{ CellSize = target }):Play()
	else
		ui.gridLayout.CellSize = target
	end
end

-- deck band

-- One slot: a framed holder holding BOTH an empty socket and a full card,
-- swapped by Visible. Building a CardRenderer card is expensive and players
-- flick between tabs constantly, so neither is created on demand.
local function buildSlot(parent: Instance, index: number, count: number)
	-- Width is set by packRow from the row's height, not by dividing the row up.
	-- Dividing gave each card a holder far wider than the card itself, so five
	-- cards sat marooned in five wide boxes with big gaps between them.
	local holder = new("Frame", { Parent = parent, LayoutOrder = index,
		BackgroundTransparency = 1, Size = UDim2.new(0, 100, 1, 0) })

	-- A CARD-SHAPED frame inside the holder. Without this the socket takes the
	-- holder's shape, which is whatever the row division happens to be, and the
	-- card ends up floating small inside a wide empty box.
	local frame = new("Frame", { Parent = holder, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1, ZIndex = 11 },
		{ new("UIAspectRatioConstraint", { AspectRatio = CARD_REF_W / CARD_REF_H }) })

	local socket = new("Frame", { Parent = frame, Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = INK, BackgroundTransparency = 0.25, ZIndex = 12 },
		{ corner(14), stroke(LINE, 2, 0.35) })

	local empty = new("Frame", { Parent = socket, Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1, ZIndex = 13 })
	textLabel({ Parent = empty, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.44), Size = UDim2.new(1, 0, 0, 40),
		Text = "+", FontFace = Theme.font(), TextSize = 32, TextColor3 = LINE,
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 13 })
	textLabel({ Parent = empty, AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(1, 0, 0, 16),
		Text = "SLOT " .. index, TextSize = 11, TextColor3 = LINE,
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 13 })

	local cardHost = new("Frame", { Parent = frame, Visible = false,
		Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
		ClipsDescendants = true, ZIndex = 14 }, { corner(14) })
	local card = CardRenderer.create(cardHost, CARD_REF_W, 14)
	card.root.AnchorPoint = Vector2.new(0.5, 0.5)
	card.root.Position = UDim2.fromScale(0.5, 0.5)
	local scale = new("UIScale", { Parent = card.root, Scale = 1 })

	-- The sweep. Blur is faked by STACKING a few copies at different widths and
	-- transparencies: Roblox has no blur for 2D UI, but overlapping soft bands
	-- that do not share an edge composite into something with no hard boundary,
	-- which is what the eye reads as a blurred highlight.
	--
	-- It rides the HOST, not the card, so it passes over the whole card including
	-- its border rather than being clipped to the artwork inside.
	local sweeps = {}
	for i = 1, SWEEP_LAYERS do
		local spread = 1 + (i - 1) * 0.55
		sweeps[i] = new("ImageLabel", {
			Parent = cardHost, Name = "Sweep" .. i, BackgroundTransparency = 1,
			Image = SWEEP_IMAGE,
			ImageTransparency = math.min(0.985, SWEEP_TRANSPARENCY + (i - 1) * 0.03),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(-0.6, 0, 0.5, 0),
			Size = UDim2.new(SWEEP_WIDTH * spread, 0, 1.25, 0),
			ScaleType = Enum.ScaleType.Stretch, ZIndex = 19,
		})
	end

	-- The frame is already the card's aspect, so one axis is enough.
	local function refit()
		local size = frame.AbsoluteSize
		if size.X <= 0 then return end
		scale.Scale = size.X / CARD_REF_W
	end
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	task.defer(refit)

	local click = new("TextButton", { Parent = frame, Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1, Text = "", ZIndex = 20 })
	Sfx.bindButton(click)

	local hint = textLabel({ Parent = frame, Visible = false,
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(1, 0, 0, 18), Text = "REMOVE", TextSize = 14,
		TextColor3 = ATTACK_C, TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 21 })
	textOutline(hint).Parent = hint

	click.MouseEnter:Connect(function() hint.Visible = cardHost.Visible end)
	click.MouseLeave:Connect(function() hint.Visible = false end)

	return { holder = holder, socket = socket, empty = empty, sweeps = sweeps,
		cardHost = cardHost, card = card, click = click, hint = hint, refit = refit,
		renderKey = nil }
end

-- Both line-ups are on screen at once, stacked: attack on top, support beneath.
-- Tabbing between them meant you could never see the pairing, and Support N
-- assists Attack N - that relationship is the whole point of the column, so it
-- has to be visible in one glance.
function DeckController:BuildDeckBand()
	if not ui.deckRow then return end

	for _, c in ipairs(ui.deckRow:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	slotViews = { attack = {}, support = {} }
	ui.rows = {}

	for order, kind in ipairs({ "attack", "support" }) do
		local count = slotCount(kind)
		local colour = (kind == "support") and SUPPORT_C or ATTACK_C

		local section = new("Frame", { Parent = ui.deckRow, LayoutOrder = order,
			BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0.5, -6) })

		-- THE LABEL GETS ITS OWN COLUMN.
		--
		-- It used to be drawn on top of a row that spanned the full width and
		-- centred its cards inside it, so the moment a line-up was wide enough the
		-- first card simply sat on the words. Reserving a gutter and starting the
		-- row AFTER it means the two can never collide, at any window width or
		-- slot count - the overlap is designed out rather than tuned away.
		local rail = new("Frame", { Parent = section, Name = kind .. "Rail",
			BackgroundTransparency = 1, Size = UDim2.new(0, 160, 1, 0), ZIndex = 16 })

		-- A bar in the row's colour. The two line-ups are then told apart by
		-- something you can see without reading, which matters on a screen where
		-- the eye is mostly on the cards.
		new("Frame", { Parent = rail, Name = "Accent", AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(0, 4, 0.5, 0),
			BackgroundColor3 = colour, BorderSizePixel = 0, ZIndex = 16 },
			{ corner(2) })

		-- Two lines rather than one. ATTACK is the word being scanned for and
		-- keeps the size; LINE-UP is context and steps back. Stacked, the pair
		-- fits a far narrower gutter than one long 26px string ever could, which
		-- is what buys the cards their space back.
		local caption = textLabel({ Parent = rail, Name = kind .. "Caption",
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 0.5, 2),
			Size = UDim2.new(1, -22, 0, 30), Text = string.upper(kind),
			TextSize = 26, TextColor3 = colour, ZIndex = 16 })
		local captionStroke = textOutline(caption)
		captionStroke.Parent = caption

		local sub = textLabel({ Parent = rail, Name = kind .. "Sub",
			Position = UDim2.new(0, 16, 0.5, 4), Size = UDim2.new(1, -22, 0, 16),
			Text = "LINE-UP", TextSize = 13, TextColor3 = MUTED, ZIndex = 16 })
		textOutline(sub, 0.3).Parent = sub

		local row = new("Frame", { Parent = section, BackgroundTransparency = 1,
			Position = UDim2.new(0, 160, 0, 0), Size = UDim2.new(1, -160, 1, 0) },
			{ new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, SLOT_GAP), SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center }) })
		ui.rows[kind] = row

		-- The gutter is a PROPORTION of the band with pixel limits, not a fixed
		-- number, so it stays readable on a laptop and does not swallow a third of
		-- an ultrawide. Text scales with the column it lives in for the same
		-- reason - a label that outgrows its own gutter is the bug we just fixed.
		local function fitRail()
			local width = section.AbsoluteSize.X
			if width <= 0 then return end
			local gutter = math.clamp(math.floor(width * 0.15), 104, 200)

			rail.Size = UDim2.new(0, gutter, 1, 0)
			row.Position = UDim2.new(0, gutter, 0, 0)
			row.Size = UDim2.new(1, -gutter, 1, 0)

			caption.TextSize = math.clamp(math.floor(gutter * 0.18), 15, 30)
			sub.TextSize = math.clamp(math.floor(gutter * 0.09), 10, 15)
			-- textOutline sized the stroke from the ORIGINAL TextSize, so it has to
			-- be resized here too or the outline thickens relative to the letters as
			-- the label shrinks - which is exactly what reads as fake bold.
			captionStroke.Thickness = math.clamp(caption.TextSize * 0.055, 1, 2.2)
		end
		section:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitRail)
		task.defer(fitRail)

		for i = 1, count do
			local view = buildSlot(row, i, count)
			slotViews[kind][i] = view
			view.click.Activated:Connect(function()
				local deck = activePreset()[kind] or {}
				if deck[i] then
					Remotes.RequestSetDeck:FireServer(kind, i, nil, nil)
					pendingSlot = nil
				else
					-- Empty: arm it so the next card clicked lands here, and put
					-- the collection on the matching tab so there is something
					-- valid to click.
					pendingSlot = { slotType = kind, index = i }
					state.mode = (kind == "support") and "Support" or "Attack"
					self:RefreshSlots()
					self:Refresh()
				end
			end)
		end

		-- Cards are as tall as the row allows and as wide as that height implies,
		-- so they sit shoulder to shoulder with only SLOT_GAP between them.
		local function packRow()
			local h = row.AbsoluteSize.Y
			if h <= 0 then return end
			local w = math.floor(h * CARD_ASPECT)
			for _, view in pairs(slotViews[kind]) do
				view.holder.Size = UDim2.new(0, w, 1, 0)
			end
		end
		row:GetPropertyChangedSignal("AbsoluteSize"):Connect(packRow)
		task.defer(packRow)
	end

	-- One tween drives every sweep on the screen, so all ten cards catch the
	-- light together instead of each running its own clock.
	for _, kind in ipairs({ "attack", "support" }) do
		for _, view in pairs(slotViews[kind]) do
			for i, sweep in ipairs(view.sweeps) do
				TweenService:Create(sweep,
					TweenInfo.new(2.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut,
						-1, false, 3.4 + i * 0.05),
					{ Position = UDim2.new(1.6, 0, 0.5, 0) }):Play()
			end
		end
	end
end

function DeckController:RefreshSlots()
	if not slotViews.attack then return end

	for _, kind in ipairs({ "attack", "support" }) do
		-- Both rows stay visible now; the tab only steers the collection below.
		local deck = activePreset()[kind] or {}

		for i, view in pairs(slotViews[kind]) do
			local slot = deck[i]
			-- A slot can outlive its card: retiring an id from CardDefinitions leaves
			-- it sitting in every saved deck that used it. Without this check the
			-- renderer bails on the missing definition but the holder is still shown,
			-- so the slot displays a blank card you cannot click away. Treating it as
			-- empty is both truthful and recoverable - the player just fills it again.
			if slot and not defOf(slot.cardId) then slot = nil end
			if slot and profile then
				local owned = profile.cards[CardStats.key(slot.cardId, slot.variant)]
				local level = owned and owned.level or 0
				local nextRenderKey = ("%s:%s:%s"):format(slot.cardId, slot.variant, tostring(level))
				if view.renderKey ~= nextRenderKey then
					local variant = VariantConfig.get(slot.variant)
					CardRenderer.update(view.card, {
						cardId = slot.cardId, variant = slot.variant, level = level })
					Shine.apply(view.socket, variant.id, CARD_REF_W)
					view.renderKey = nextRenderKey
					view.refit()
				end
				view.cardHost.Visible = true
				view.empty.Visible = false
				view.socket.BackgroundTransparency = 1
			else
				-- Only tear down artwork/glow when this slot actually changed to empty.
				if view.renderKey ~= nil then
					view.cardHost.Visible = false
					view.hint.Visible = false
					view.empty.Visible = true
					view.socket.BackgroundTransparency = 0.25
					Shine.remove(view.socket)
					view.renderKey = nil
				end

				-- Only the armed slot lights up, so "where does my next click
				-- go" is answerable at a glance.
				local armed = pendingSlot
					and pendingSlot.slotType == kind and pendingSlot.index == i
				local rowColour = (kind == "support") and SUPPORT_C or ATTACK_C
				local s = view.socket:FindFirstChildOfClass("UIStroke")
				if s then
					s.Color = armed and rowColour or LINE
					s.Thickness = armed and 3 or 2
					s.Transparency = armed and 0 or 0.35
				end
			end
		end
	end

	self:RefreshHeader()
end

-- collection

local function fingerprintInventory(data): string
	local parts = {}
	for key, entry in pairs((data and data.cards) or {}) do
		parts[#parts + 1] = ("%s:%s:%s"):format(
			tostring(key), tostring(entry.count or 0), tostring(entry.level or 0))
	end
	table.sort(parts)
	return table.concat(parts, "|")
end

local function updateEquippedBadge(root: GuiObject, slotIndex: number?)
	if root:GetAttribute("EquippedSlot") == slotIndex then return end
	root:SetAttribute("EquippedSlot", slotIndex)
	local old = root:FindFirstChild("EquippedBadge")
	if old then old:Destroy() end
	if not slotIndex then return end

	local badge = new("Frame", { Name = "EquippedBadge", Parent = root,
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -22),
		Size = UDim2.new(0, 52, 0, 17), BackgroundColor3 = accent(),
		BackgroundTransparency = 0.05, ZIndex = Z.Tile + 6 },
		{ corner(8), stroke(Color3.new(1, 1, 1), 1.5, 0.45) })
	local badgeText = textLabel({ Parent = badge, Size = UDim2.new(1, 0, 1, 0),
		Text = "IN " .. slotIndex, TextSize = 12,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = Z.Tile + 7 })
	textOutline(badgeText).Parent = badgeText
end

function DeckController:RefreshEquippedMarkers()
	if not ui.grid then return end
	local equipped = equippedKeys()
	for _, child in ipairs(ui.grid:GetChildren()) do
		if child:IsA("GuiObject") then
			local key = child:GetAttribute("CardKey")
			if key then updateEquippedBadge(child, equipped[key]) end
		end
	end
end

function DeckController:Refresh()
	if not ui.grid then return end
	local savedCanvas = ui.grid.CanvasPosition
	collectionFingerprint = fingerprintInventory(profile)

	for _, c in ipairs(ui.grid:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end

	local list = {}
	for _, item in ipairs(ownedList()) do
		if passesFilters(item) then list[#list + 1] = item end
	end
	sortList(list)

	local equipped = equippedKeys()

	-- Tiles are BORN at the size the drawer is currently showing, so their
	-- artwork and shine are scaled against a sensible reference. The grid layout
	-- resizes them from here on; only a rebuild reads this again.
	local cellW = cellWidthFor(drawerExpanded)

	for i, item in ipairs(list) do
		local tile = CardTile.create(ui.grid, cellW, Z.Tile)
		tile.root.LayoutOrder = i
		CardTile.update(tile, item)
		Sfx.bindButton(tile.root)

		local tileKey = CardStats.key(item.cardId, item.variant)
		tile.root:SetAttribute("CardKey", tileKey)
		updateEquippedBadge(tile.root, equipped[tileKey])

		-- A PRESS OPENS THE CARD; it no longer equips on the spot.
	--
		-- Equipping used to be the only thing you could do with a card, so one
		-- click meaning "equip" was unambiguous. Elder Essence ended that: a press
		-- could now reasonably mean "put this in my deck" or "pour essence into
		-- it", and a click cannot mean two things. So it means "open this", and the
		-- window offers both.
		--
		-- The hover pop-out is dismissed first: it is anchored to the tile and
		-- would otherwise hang over the window that just opened on top of it.
		tile.root.Activated:Connect(function()
			-- The hover preview is dismissed first: it is anchored to the same tile
			-- and would otherwise sit on top of the pop-out that just opened there.
			self:HidePopout()
			CardActions.open(item, profile, {
				-- Read the live marker rather than a value captured when the tile was
				-- built: equipping no longer rebuilds the grid, so a closure holding
				-- the old equipped state would go stale the first time anything moved.
				equippedIndex = function() return equippedKeys()[tileKey] end,
				equip = function(chosen) self:EquipFromTile(chosen) end,
				unequip = function(chosen, slotIndex)
					local kind = isSupportId(chosen.cardId) and "support" or "attack"
					Remotes.RequestSetDeck:FireServer(kind, slotIndex, nil, nil)
					pendingSlot = nil
				end,
			-- The tile is the anchor: the pop-out parks beside the card you
			-- pressed rather than in the middle of the screen.
			}, tile.root)
		end)

		-- Hover: come forward, not jump. A UIScale rather than a size tween,
		-- because the grid layout owns every child's Size and would fight one.
		-- The lift is three small things at once - scale, a brightening wash, and
		-- a solid outline - which together read as "nearer" far better than any
		-- one of them cranked up far enough to be noticed on its own.
		local lift = new("UIScale", { Parent = tile.root, Scale = 1 })
		local wash = new("Frame", { Parent = tile.root, Name = "HoverWash",
			Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = Z.Tile + 5 },
			{ corner(20) })
		local restingStroke = tile.stroke.Thickness
		local hoverInfo = TweenInfo.new(DRAWER.HoverTime,
			Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

		tile.root.MouseEnter:Connect(function()
			tile.root.ZIndex = Z.TileHover
			tile.stroke.Thickness = restingStroke + 1
			TweenService:Create(lift, hoverInfo, { Scale = DRAWER.HoverScale }):Play()
			TweenService:Create(wash, hoverInfo, { BackgroundTransparency = 0.88 }):Play()
			-- While the pop-out is up it IS the preview, and a much better one.
			-- Letting hover throw a second floating card over it would just be two
			-- copies of the same card fighting for the same space.
			if not CardActions.isOpen() then
				self:ShowPopout(tile.root, item)
			end
		end)
		tile.root.MouseLeave:Connect(function()
			tile.root.ZIndex = Z.Tile
			tile.stroke.Thickness = restingStroke
			TweenService:Create(lift, hoverInfo, { Scale = 1 }):Play()
			TweenService:Create(wash, hoverInfo, { BackgroundTransparency = 1 }):Play()
			self:HidePopout()
		end)
	end

	if #list == 0 then
		textLabel({ Parent = ui.grid, Size = UDim2.new(0, 320, 0, 40),
			Text = (state.mode == "Support")
				and "No support cards yet - go roll some."
				or "Nothing matches that.",
			TextSize = 15, TextColor3 = MUTED,
			TextXAlignment = Enum.TextXAlignment.Center })
	end

	if ui.countLabel then
		ui.countLabel.Text = ("%d SHOWN"):format(#list)
	end

	-- AutomaticCanvasSize settles after layout. Restore the exact reading
	-- position on the following frame and clamp only if filtering shortened it.
	task.defer(function()
		RunService.Heartbeat:Wait()
		if not ui.grid or not ui.grid.Parent then return end
		local maxY = math.max(0, ui.grid.AbsoluteCanvasSize.Y - ui.grid.AbsoluteWindowSize.Y)
		ui.grid.CanvasPosition = Vector2.new(savedCanvas.X, math.clamp(savedCanvas.Y, 0, maxY))
	end)
end

-- hover pop-out

-- The full card, floating above the hovered tile. A tile is deliberately too
-- small to read ability text on, so this is how you find out what a card
-- actually does before committing it to a slot.
--
-- ONE card instance, repainted and repositioned - not one per tile. A grid of
-- two hundred tiles would otherwise mean two hundred CardRenderer builds.
function DeckController:ShowPopout(tile: GuiObject, item)
	if not ui.popout then return end

	CardRenderer.update(ui.popoutCard, {
		cardId = item.cardId, variant = item.variant, level = item.level })

	local w, h = POPOUT_W, POPOUT_H
	local centre = tile.AbsolutePosition + tile.AbsoluteSize / 2
	local view = ui.screen.AbsoluteSize

	-- Prefer above the tile; flip below when there is no room, and keep it on
	-- screen horizontally. A preview that opens half off the edge is worse than
	-- no preview.
	local y = centre.Y - tile.AbsoluteSize.Y / 2 - 8 - h
	if y < 6 then y = centre.Y + tile.AbsoluteSize.Y / 2 + 8 end
	y = math.clamp(y, 6, math.max(6, view.Y - h - 6))
	local x = math.clamp(centre.X - w / 2, 6, math.max(6, view.X - w - 6))

	ui.popout.Position = UDim2.fromOffset(x, y)
	ui.popout.Size = UDim2.fromOffset(w, h)
	ui.popout.Visible = true

	ui.popoutScale.Scale = 0.82
	TweenService:Create(ui.popoutScale,
		TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = w / CARD_REF_W }):Play()

	-- Anchored to the POP-OUT rather than the tile: the fine print belongs beside
	-- the card you are reading, not beside the thumbnail you happen to be over.
	RestrictionTip.setTarget(item.cardId, ui.popout)
end

function DeckController:HidePopout()
	if ui.popout then ui.popout.Visible = false end
	RestrictionTip.clear()
end

-- Clicking a tile fills the armed slot, or the first free one if none is armed.
-- One click works for a new player; arming a slot first works for anyone who
-- cares exactly where the card lands.
function DeckController:EquipFromTile(item)
	local kind = isSupportId(item.cardId) and "support" or "attack"
	local index = nil

	if pendingSlot and pendingSlot.slotType == kind then
		index = pendingSlot.index
	else
		local deck = activePreset()[kind] or {}
		for i = 1, slotCount(kind) do
			if not deck[i] then index = i break end
		end
		index = index or 1
	end

	Remotes.RequestSetDeck:FireServer(kind, index, item.cardId, item.variant)
	pendingSlot = nil
end

-- header

function DeckController:RefreshHeader()
	if not ui.title then return end
	local index = (profile and profile.decks and profile.decks.active) or 1
	ui.title.Text = "DECK " .. tostring(index)
	if ui.setDeckCaption then ui.setDeckCaption("Deck " .. tostring(index)) end

	local deck = activePreset()
	for _, kind in ipairs({ "attack", "support" }) do
		local filled = 0
		for i = 1, slotCount(kind) do
			-- Counted the same way RefreshSlots draws them: a slot holding a card id
			-- that no longer exists shows as empty, so it must not be counted as
			-- full. Otherwise the tab reads 4/5 above a band with one card in it.
			local entry = (deck[kind] or {})[i]
			if entry and defOf(entry.cardId) then filled += 1 end
		end
		local tab = ui.tabs and ui.tabs[kind]
		if tab then
			tab.count.Text = ("%d/%d"):format(filled, slotCount(kind))
			local on = (kind == slotType())
			local colour = (kind == "support") and SUPPORT_C or ATTACK_C
			local resting = on and colour:Lerp(INK, 0.55) or PANEL_2
			tab.btn:SetAttribute("BaseColour", resting)
			tab.btn.BackgroundColor3 = resting
			tab.label.TextColor3 = on and colour or MUTED
			tab.count.TextColor3 = on and TEXT or MUTED
			local s = tab.btn:FindFirstChildOfClass("UIStroke")
			if s then
				s.Color = on and colour or LINE
				s.Transparency = on and 0 or 0.35
			end
		end
	end

	-- The purple frame belongs to the SCREEN, not to a tab, so it is painted
	-- once at build time rather than repainted per mode. Nothing about which tab
	-- you are on should make the whole panel change colour.
end

-- build

function DeckController:Build(playerGui: Instance)
	local gui = new("ScreenGui", { Parent = playerGui, Name = "DeckBuilder",
		Enabled = false, ResetOnSpawn = false, IgnoreGuiInset = true,
		DisplayOrder = 20, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
	ui.screen = gui

	ui.dim = new("TextButton", { Parent = gui, Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35,
		Text = "", AutoButtonColor = false, ZIndex = 1 })

	-- Active = true is load-bearing, not decoration.
	--
	-- `ui.dim` behind this panel is a full-screen TextButton that closes the deck,
	-- and a plain Frame does NOT absorb clicks - so every click on the panel that
	-- did not land on a button fell straight through to the dim and shut the whole
	-- screen. Marking the root active makes it swallow those clicks; the dim still
	-- closes the deck when you click genuinely outside the panel.
	local root = new("Frame", { Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.95, 0.94),
		BackgroundColor3 = PANEL, Active = true, ZIndex = 5 },
		{ corner(20),
			new("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12),
				PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }) })

	-- One purple frame around the whole screen. Passing the panel's own width as
	-- the reference makes Shine scale the stroke stack up to something readable
	-- at this size instead of card-sized hairlines.
	Shine.applySpec(root, frameSpec(PURPLE, 0.72), 420, "deckframe")

	-- Backdrop texture. Sized to bleed past the root's own padding so it reaches
	-- the panel's real edges, and faded down the screen by a gradient rather than
	-- left at one flat transparency - a uniform overlay reads as wallpaper laid
	-- on top, whereas a fade reads as part of the panel.
	new("ImageLabel", { Parent = root, Name = "Backdrop",
		BackgroundTransparency = 1, Image = BACKDROP_IMAGE,
		ImageTransparency = 0.82, ScaleType = Enum.ScaleType.Crop,
		Position = UDim2.new(0, -14, 0, -12), Size = UDim2.new(1, 28, 1, 24),
		ZIndex = 5 },
		{ corner(20),
			new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.55, 0.35),
				NumberSequenceKeypoint.new(1, 0.8) }) }) })

	-- header
	-- Above the body rather than tied with it, so the deck-preset list it opens
	-- is never half-swallowed by the band underneath.
	local header = new("Frame", { Parent = root, BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 54), ZIndex = 10 })

	-- The title header, from the shared component. See PanelHeader for why the
	-- old diamond-and-hairline ribbon read as unfinished.
	local headerPlate = PanelHeader.create({
		Parent = header,
		Name = "HeaderPlate",
		Position = UDim2.new(0, -4, 0, 2),
		Size = UDim2.fromOffset(430, 48),
		accent = PURPLE,
		shade = PURPLE:Lerp(INK, 0.34),
		text = "DECK 1",
		textSize = 26,
		height = 48,
		zIndex = 10,
	}).plate

	-- Exit moved to the RIGHT of the header, and it is an X rather than a back
	-- arrow: a "<" pointing left while pinned to the right edge reads as "go back
	-- one page", which is not what it does. This matches the close button every
	-- other menu window uses. The deck switcher below is shifted left to clear it.
	local back = new("TextButton", { Parent = header, Size = UDim2.fromOffset(52, 42),
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 5),
		BackgroundColor3 = Color3.fromRGB(242, 76, 68), AutoButtonColor = false, Text = "X",
		FontFace = Theme.font(), TextSize = 19, TextColor3 = TEXT, ZIndex = 31 },
		{ corner(999), stroke(Color3.new(1, 1, 1), 2, 0.08) })
	styleButton(back, nil, Color3.fromRGB(242, 76, 68))
	back.Activated:Connect(function() self:Close() end)

	-- PanelHeader already built and positioned the title inside the plate;
	-- RefreshHeader only needs the handle to rewrite it per deck.
	ui.title = headerPlate.Title

	local presetNames = {}
	for i = 1, GameConfig.DeckPresets do presetNames[i] = tostring(i) end
	-- Shifted left by the exit button's width plus a gap, so the two never overlap.
	local switcherHolder = new("Frame", { Parent = header, BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -52, 0, 0),
		Size = UDim2.new(0, 120, 1, 0), ZIndex = 30 })
	local _, setDeckCaption = dropdown(switcherHolder, 120, presetNames,
		function(v) return "Deck " .. v end,
		function(v)
			-- The server owns which preset is active; we only ask. It answers
			-- with a ProfileSync, which repaints everything.
			Remotes.RequestSetActiveDeck:FireServer(tonumber(v))
			pendingSlot = nil
		end)
	ui.setDeckCaption = setDeckCaption

	-- tabs
	local tabBar = new("Frame", { Parent = root, BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 60), Size = UDim2.new(1, 0, 0, 36), ZIndex = 6 },
		{ new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder }) })

	ui.tabs = {}
	for order, kind in ipairs({ "attack", "support" }) do
		local btn = new("TextButton", { Parent = tabBar, LayoutOrder = order,
			Size = UDim2.new(0, 220, 1, 0), BackgroundColor3 = PANEL_2,
			AutoButtonColor = false, Text = "", ZIndex = 7 }, { corner(10) })
		local label = textLabel({ Parent = btn, Position = UDim2.new(0, 14, 0, 0),
			Size = UDim2.new(1, -74, 1, 0), Text = string.upper(kind),
			FontFace = Theme.font(), TextSize = 15, ZIndex = 8 })
		local count = textLabel({ Parent = btn, AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.new(0, 54, 1, 0),
			Text = "0/5", TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 8 })
		textOutline(count).Parent = count
		styleButton(btn, label, (kind == "support") and SUPPORT_C:Lerp(INK, 0.62)
			or ATTACK_C:Lerp(INK, 0.62))
		btn.Activated:Connect(function()
			state.mode = (kind == "support") and "Support" or "Attack"
			pendingSlot = nil
			self:RefreshSlots()
			self:Refresh()
		end)
		ui.tabs[kind] = { btn = btn, label = label, count = count }
	end

	-- Everything below the tabs shares one body frame, so the band and the
	-- collection split the REMAINING height between them. Giving each a fraction
	-- of the whole panel instead makes them collide as soon as the window is
	-- short, because the fixed 92px header does not shrink with it.
	local body = new("Frame", { Parent = root, Position = UDim2.new(0, 0, 0, 104),
		Size = UDim2.new(1, 0, 1, -104), BackgroundTransparency = 1, ZIndex = 6 })

	-- The band is sized around a COLLAPSED drawer, once, and is never touched
	-- again. Expanding the drawer does not reflow it, shrink it or push it up;
	-- the drawer just passes in front. That is the whole contract here.
	ui.body = body
	local band = new("Frame", { Parent = body,
		Size = UDim2.new(1, 0, 1 - DRAWER.CollapsedHeight, -10),
		BackgroundColor3 = INK, BackgroundTransparency = 0.35, ZIndex = Z.DeckBand },
		{ corner(16) })

	-- The glow rides its own transparent frame rather than the band, so it can
	-- never disturb the band's fill or corner.
	ui.bandGlow = nil

	ui.deckRow = new("Frame", { Parent = band, BackgroundTransparency = 1,
		Position = UDim2.new(0, 14, 0, 10), Size = UDim2.new(1, -28, 1, -20), ZIndex = 8 },
		{ new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center }) })

	--=====================================================================--
	-- COLLECTION DRAWER
	--
	-- A SIBLING of the band, not a neighbour sharing the space with it.
	-- Anchored to the bottom of the body and grown upward by tweening its own
	-- height, so "slide up" and "get bigger" are the same single animation and
	-- the deck underneath is never consulted.
	--=====================================================================--

	-- Roblox has no drop shadow for 2D UI, and a child can never draw behind
	-- its own parent's fill - so the shadow is three SIBLING plates behind the
	-- drawer, each a little larger and a little fainter. Overlapping soft edges
	-- that never coincide composite into something with no hard boundary, which
	-- is what the eye accepts as a shadow.
	ui.drawerShades = {}
	for _, pad in ipairs({ 6, 14, 24 }) do
		local plate = new("Frame", { Parent = body, Name = "DrawerShade" .. pad,
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, pad),
			Size = UDim2.new(1, pad * 2, DRAWER.CollapsedHeight, pad),
			BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0,
			BackgroundTransparency = 0.80 + pad * 0.006, ZIndex = Z.DrawerShade },
			{ corner(24), new("UISizeConstraint", {
				MinSize = Vector2.new(0, DRAWER.MinDrawerHeight + pad) }) })
		table.insert(ui.drawerShades, { frame = plate, pad = pad })
	end

	local drawer = new("Frame", { Parent = body, Name = "CollectionDrawer",
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, 0, DRAWER.CollapsedHeight, 0),
		BackgroundColor3 = DRAWER_BG, BackgroundTransparency = 0.08,
		ZIndex = Z.Drawer },
		{ corner(18), stroke(DRAWER_LINE, 1.6, 0.25),
			-- Percentages alone are not safe on a short window: 28% of a 340px
			-- body is less than the chrome costs, and the grid ends up with a
			-- negative height. This is the floor, and nothing else.
			new("UISizeConstraint", {
				MinSize = Vector2.new(0, DRAWER.MinDrawerHeight) }),
			-- Barely a gradient - a couple of shades lighter along the top edge.
			-- Enough that the drawer has a lit side and a shadowed one, which is
			-- what stops a large dark rectangle reading as a hole in the screen.
			new("UIGradient", { Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 25, 46)),
					ColorSequenceKeypoint.new(0.35, Color3.fromRGB(19, 16, 30)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(13, 11, 21)) }) }) })
	ui.drawer = drawer

	-- A purple seam along the top edge, fading out to either side so it reads
	-- as a lit rim rather than a drawn line. It rhymes with the DECK banner at
	-- the top of the screen without being the same object.
	new("Frame", { Parent = drawer, Name = "TopSeam", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(1, -40, 0, 2),
		BackgroundColor3 = PURPLE, BorderSizePixel = 0, ZIndex = Z.Chrome },
		{ corner(2), new("UIGradient", { Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.15),
			NumberSequenceKeypoint.new(1, 1) }) }) })

	-- The handle. Purely a cue that this panel moves - it is never the only way
	-- to open the drawer, so it stays quiet: two hairlines and a caret that
	-- turns over when the drawer is out.
	local handle = new("Frame", { Parent = drawer, Name = "Handle",
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 5),
		Size = UDim2.new(0, 150, 0, 14), BackgroundTransparency = 1, ZIndex = Z.Chrome })
	for _, side in ipairs({ -1, 1 }) do
		new("Frame", { Parent = handle, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, side * 40, 0.5, 0), Size = UDim2.new(0, 46, 0, 2),
			BackgroundColor3 = DRAWER_LINE, BackgroundTransparency = 0.45,
			BorderSizePixel = 0, ZIndex = Z.Chrome }, { corner(2) })
	end
	ui.handleCaret = textLabel({ Parent = handle, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 22, 0, 16),
		Text = "^", TextSize = 16, TextColor3 = PURPLE, TextTransparency = 0.2,
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = Z.Chrome })

	-- header: what this is, and how much of it you are looking at
	ui.collectionTitle = textLabel({ Parent = drawer, Position = UDim2.new(0, 20, 0, 17),
		Size = UDim2.new(0.6, 0, 0, 22), Text = "CARD COLLECTION", TextSize = 19,
		ZIndex = Z.Chrome })
	textOutline(ui.collectionTitle).Parent = ui.collectionTitle

	ui.countLabel = textLabel({ Parent = drawer, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 20), Size = UDim2.new(0, 180, 0, 18),
		Text = "", TextSize = 13, TextColor3 = MUTED,
		TextXAlignment = Enum.TextXAlignment.Right, ZIndex = Z.Chrome })

	-- controls, on their own row and separated from the grid by a rule, so the
	-- top of the drawer reads as a toolbar rather than as more cards
	local bar = new("Frame", { Parent = drawer, Name = "Controls",
		Position = UDim2.new(0, 20, 0, 46), Size = UDim2.new(1, -40, 0, 30),
		BackgroundTransparency = 1, ZIndex = Z.Controls })

	ui.search = new("TextBox", { Parent = bar, Size = UDim2.new(0, 240, 1, 0),
		BackgroundColor3 = PANEL_2, Text = "", PlaceholderText = "Search cards...",
		PlaceholderColor3 = MUTED, FontFace = Theme.font(), TextSize = 13,
		TextColor3 = TEXT, TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false, ZIndex = Z.Controls },
		{ corner(10), stroke(LINE, 1.5),
			new("UIPadding", { PaddingLeft = UDim.new(0, 10) }) })

	-- Filter lists that are open count as "still in the drawer" even when the
	-- cursor has wandered off it, so picking a sort never closes the thing you
	-- were sorting.
	ui.dropdownLists = {}

	local sortHolder = new("Frame", { Parent = bar, BackgroundTransparency = 1,
		Position = UDim2.new(0, 250, 0, 0), Size = UDim2.new(0, 132, 1, 0),
		ZIndex = Z.Controls })
	local _, setSortCaption, sortList = dropdown(sortHolder, 132, SORTS,
		function(v) return v end,
		function(v)
			state.sort = v
			ui.setSortCaption("Sort: " .. v)
			self:Refresh()
		end, Z.Dropdown)
	ui.setSortCaption = setSortCaption
	setSortCaption("Sort: Rarity")
	table.insert(ui.dropdownLists, sortList)

	-- "All" plus every tier, labelled by DISPLAY name, so a rename in
	-- VariantConfig reaches this list for free while the value stays the id.
	local variantOptions = { "All" }
	for _, id in ipairs(VariantConfig.Order) do
		variantOptions[#variantOptions + 1] = id
	end
	local variantHolder = new("Frame", { Parent = bar, BackgroundTransparency = 1,
		Position = UDim2.new(0, 392, 0, 0), Size = UDim2.new(0, 150, 1, 0),
		ZIndex = Z.Controls })
	local _, setVariantCaption, variantList = dropdown(variantHolder, 150, variantOptions,
		function(v)
			local def = VariantConfig.Data[v]
			return def and def.display or v
		end,
		function(v)
			state.variant = v
			local def = VariantConfig.Data[v]
			ui.setVariantCaption("Border: " .. (def and def.display or v))
			self:Refresh()
		end, Z.Dropdown)
	ui.setVariantCaption = setVariantCaption
	setVariantCaption("Border: All")
	table.insert(ui.dropdownLists, variantList)

	-- The rule under the toolbar. Everything above it is controls, everything
	-- below it is cards - which is the separation the drawer was missing.
	new("Frame", { Parent = drawer, Name = "Divider",
		Position = UDim2.new(0, 20, 0, 84), Size = UDim2.new(1, -40, 0, 1),
		BackgroundColor3 = DRAWER_LINE, BackgroundTransparency = 0.5,
		BorderSizePixel = 0, ZIndex = Z.Chrome })

	ui.gridLayout = new("UIGridLayout", {
		CellSize = UDim2.new(0, TILE_W, 0, math.floor(TILE_W * TILE_RATIO)),
		CellPadding = UDim2.new(0, DRAWER.CellGap, 0, DRAWER.CellGap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Left })

	ui.grid = new("ScrollingFrame", { Parent = drawer, Name = "Grid",
		Position = UDim2.new(0, 16, 0, DRAWER.ChromeHeight - 8),
		Size = UDim2.new(1, -32, 1, -DRAWER.ChromeHeight - 6),
		BackgroundColor3 = INK, BackgroundTransparency = 0.72, BorderSizePixel = 0,
		ScrollBarThickness = 6, ScrollBarImageColor3 = DRAWER_LINE,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ClipsDescendants = true, ZIndex = Z.Grid },
		{ corner(14), ui.gridLayout,
			new("UIPadding", {
				PaddingTop = UDim.new(0, DRAWER.GridPad),
				PaddingBottom = UDim.new(0, DRAWER.GridPad),
				PaddingLeft = UDim.new(0, DRAWER.GridPad),
				PaddingRight = UDim.new(0, DRAWER.GridPad) }) })

	-- Cells are chosen from the grid's MEASURED width, so this has to wait
	-- until it has one - and be redone whenever the window changes shape.
	ui.grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		applyCells(drawerExpanded, false)
	end)
	task.defer(function() applyCells(drawerExpanded, false) end)

	ui.search:GetPropertyChangedSignal("Text"):Connect(function()
		state.search = ui.search.Text
		self:Refresh()
	end)

	-- pop-out layer, above everything else on the screen
	ui.popout = new("Frame", { Parent = gui, Visible = false,
		BackgroundTransparency = 1, ZIndex = Z.Popout })
	ui.popoutCard = CardRenderer.create(ui.popout, CARD_REF_W, 60)
	ui.popoutCard.root.AnchorPoint = Vector2.new(0.5, 0.5)
	ui.popoutCard.root.Position = UDim2.fromScale(0.5, 0.5)
	ui.popoutScale = new("UIScale", { Parent = ui.popoutCard.root, Scale = 1 })

	-- Click-outside-to-close, but ONLY outside.
	--
	-- root.Active already stops clicks on the panel reaching this button, but the
	-- hover popout is a sibling layered above the panel and is not itself active,
	-- so a click on it would still fall through to here. Testing the pointer
	-- against the panel's rectangle covers that and anything else added later:
	-- if the click was over the panel, it was never meant to close anything.
	ui.dim.Activated:Connect(function(inputObject)
		if inputObject and root.AbsoluteSize.X > 0 then
			local p = Vector2.new(inputObject.Position.X, inputObject.Position.Y)
			local topLeft = root.AbsolutePosition
			local bottomRight = topLeft + root.AbsoluteSize
			if p.X >= topLeft.X and p.X <= bottomRight.X
				and p.Y >= topLeft.Y and p.Y <= bottomRight.Y then
				return
			end
		end
		self:Close()
	end)

	self:BuildDeckBand()
	self:WatchDrawerHover()
end

--=========================================================================--
-- DRAWER STATE
--=========================================================================--

-- One animation drives everything: the drawer's height, its shadow plates, its
-- fill, the caret and the grid's cell size all ride the same TweenInfo, so they
-- arrive together instead of finishing at three different moments.
function DeckController:SetDrawerExpanded(expanded: boolean, instant: boolean?)
	if not ui.drawer then return end
	if drawerExpanded == expanded and not instant then return end
	drawerExpanded = expanded

	local height = expanded and DRAWER.ExpandedHeight or DRAWER.CollapsedHeight
	-- Opaque once it is out. Even two percent of transparency is enough for the
	-- SUPPORT LINE-UP caption underneath to ghost through in its bright cyan,
	-- and a foreground panel you can read the background through stops being a
	-- foreground panel. Collapsed it can afford to sit back a little.
	local fill = expanded and 0 or 0.08
	local info = drawerTweenInfo(expanded)

	if instant then
		ui.drawer.Size = UDim2.new(1, 0, height, 0)
		ui.drawer.BackgroundTransparency = fill
		for _, shade in ipairs(ui.drawerShades or {}) do
			shade.frame.Size = UDim2.new(1, shade.pad * 2, height, shade.pad)
		end
		if ui.handleCaret then ui.handleCaret.Rotation = expanded and 180 or 0 end
		applyCells(expanded, false)
		return
	end

	TweenService:Create(ui.drawer, info,
		{ Size = UDim2.new(1, 0, height, 0), BackgroundTransparency = fill }):Play()
	for _, shade in ipairs(ui.drawerShades or {}) do
		TweenService:Create(shade.frame, info,
			{ Size = UDim2.new(1, shade.pad * 2, height, shade.pad) }):Play()
	end
	if ui.handleCaret then
		TweenService:Create(ui.handleCaret, info,
			{ Rotation = expanded and 180 or 0 }):Play()
	end
	applyCells(expanded, true)
end

-- Hover detection.
--
-- Deliberately NOT MouseEnter/MouseLeave on the drawer. The drawer is full of
-- buttons - every tile, the search box, both filter pills - and moving onto a
-- child button fires MouseLeave on the parent, so an enter/leave pair would
-- read "left the collection" every single time the cursor crossed from one card
-- to the next. That is the flicker. Testing the cursor against the drawer's
-- RECTANGLE has no such notion of children: anything drawn inside the drawer is
-- inside the drawer, which is exactly what a player means by it.
function DeckController:WatchDrawerHover()
	local body = ui.body
	if not body or not ui.drawer then return end

	-- GetMouseLocation and AbsolutePosition DO NOT share an origin, and getting
	-- this wrong is a silent bug rather than an error: the drawer would arm
	-- from a band 36-58 pixels away from where the player can see it, and it
	-- would look like the hover detection was merely unreliable.
	--
	-- GetMouseLocation is measured from the very top of the SCREEN. A GuiObject
	-- reports AbsolutePosition from below the top bar. So the cursor has to come
	-- down by the inset before it can be tested against any rectangle. (The x/y
	-- that GuiObject.MouseMoved hands you are in GetMouseLocation's space too,
	-- not AbsolutePosition's - they are not a shortcut around this.)
	local inset = GuiService:GetGuiInset()
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(function()
		inset = GuiService:GetGuiInset()
	end)

	local function contains(gui: GuiObject, p: Vector2): boolean
		local at, size = gui.AbsolutePosition, gui.AbsoluteSize
		return p.X >= at.X and p.X <= at.X + size.X
			and p.Y >= at.Y and p.Y <= at.Y + size.Y
	end

	local function dropdownOpen(): boolean
		for _, list in ipairs(ui.dropdownLists or {}) do
			if list.Visible then return true end
		end
		return false
	end

	local inside = false
	local changedAt = os.clock()

	RunService.RenderStepped:Connect(function()
		if not ui.screen or not ui.screen.Enabled then return end

		local p = UserInputService:GetMouseLocation() - inset

		-- Anywhere on the drawer keeps it out. The cards, the search box and the
		-- filters are all part of the collection, so moving between them is
		-- never a leave.
		local over = contains(ui.drawer, p)

		-- Plus a forgiving band along the bottom of the deck body, so heading
		-- downwards opens the drawer before the cursor gets there. Nobody should
		-- have to land on one small card to see their collection.
		if not over then
			local at, size = body.AbsolutePosition, body.AbsoluteSize
			local zoneTop = at.Y + size.Y * (1 - DRAWER.ActivationZone)
			over = p.X >= at.X and p.X <= at.X + size.X
				and p.Y >= zoneTop and p.Y <= at.Y + size.Y
		end

		-- An open filter list or a search box being typed into counts as being
		-- in the drawer wherever the cursor has drifted to.
		if not over and (dropdownOpen() or (ui.search and ui.search:IsFocused())) then
			over = true
		end

		if over ~= inside then
			inside = over
			changedAt = os.clock()
		end

		local held = os.clock() - changedAt
		if inside and not drawerExpanded and held >= DRAWER.OpenDelay then
			self:SetDrawerExpanded(true)
		elseif not inside and drawerExpanded and held >= DRAWER.CloseGrace then
			self:SetDrawerExpanded(false)
		end
	end)
end

-- open / close

function DeckController:Open()
	if ui.screen then ui.screen.Enabled = true end
end

function DeckController:Close()
	if ui.screen then ui.screen.Enabled = false end
	-- The window is a separate ScreenGui layered above this one, so closing the
	-- deck has to take it down too or it is left floating over the world.
	CardActions.close()
	self:HidePopout()
	pendingSlot = nil
	-- Reopening the deck should always start with the deck as the focus, so the
	-- drawer goes back down with no animation while nobody is looking.
	self:SetDrawerExpanded(false, true)
end

-- wiring

function DeckController:Init()
	local playerGui = player:WaitForChild("PlayerGui")

	-- The authored screen is kept, not deleted: the artwork is still there if we
	-- want it back, and destroying a player's UI to replace it is the kind of
	-- change that is painful to undo.
	local legacy = playerGui:WaitForChild("DeckScreen", 10)
	if legacy then legacy.Enabled = false end

	self:Build(playerGui)

	Remotes.ProfileSync.OnClientEvent:Connect(function(data)
		local nextFingerprint = fingerprintInventory(data)
		local inventoryChanged = collectionFingerprint ~= nextFingerprint
		profile = data
		-- The action window reads levels and essence counts straight from the
		-- profile, so it has to be handed the new one - a level-up is exactly the
		-- case where it is open and its numbers just changed underneath it.
		CardActions.setProfile(data)
		if ui.screen and ui.screen.Enabled then
			self:RefreshSlots()
			if inventoryChanged then
				self:Refresh()
			else
				-- Equipping changes only the deck. Keep every collection tile alive,
				-- update its small marker, and leave CanvasPosition untouched.
				self:RefreshEquippedMarkers()
			end
		end
	end)

	ui.screen:GetPropertyChangedSignal("Enabled"):Connect(function()
		if ui.screen.Enabled then
			-- Any path that shows the screen must be able to populate it. The
			-- join-time sync can land before this controller connects, so ask
			-- for one if we still have nothing.
			if not profile then Remotes.RequestSync:FireServer() end
			self:RefreshSlots()
			self:Refresh()
		end
	end)
end

return DeckController
