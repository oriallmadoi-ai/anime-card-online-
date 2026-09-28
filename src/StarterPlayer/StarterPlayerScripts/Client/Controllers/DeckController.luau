--!nonstrict
-- The Deck screen.
--
-- BUILT IN CODE, DELIBERATELY. The deck band is GameConfig.AttackSlots wide and
-- the collection is however many cards you own, so both change shape with
-- data - and a layout whose shape comes from data has to be built from data.
-- StarterGui.DeckScreen is left in place but disabled, so the old artwork is
-- not lost and this is revertible.
--
-- SHAPE
--   header      icon, title, the ATTACK | SUPPORT switch, the eight presets, close
--   line-ups    two trays, attack over support, as FULL cards - what you build
--   collection  the drawer of everything you own, as compact tiles - what you
--               pick from
--
-- THE LOOK is the Backpack's: one sheet of dark lit glass with a hairline rim,
-- corner brackets and a soft stacked shadow, violet as the accent and never as
-- a fill. Attack wears a warm coral and support a cool cyan, and those two are
-- the only other colours on the chrome, so a glance tells the rows apart.
--
-- DUPLICATES. A lineup can hold the same card several times, as many times as
-- you own copies of it. E adds another copy to the next free slot every press
-- (from the card pop-out, or straight off a hovered tile), so E, E, E, E fills
-- the lineup. The server validates every request against the real inventory;
-- the client PREDICTS the result so rapid presses land in consecutive slots
-- instead of all aiming at the same one while the sync is in flight.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LeaderboardVisibility = require(ReplicatedStorage.Shared.UI.LeaderboardVisibility)

local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local CardDefinitions = require(ReplicatedStorage.Shared.Config.CardDefinitions)
local SupportDefinitions = require(ReplicatedStorage.Shared.Config.SupportDefinitions)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
local CardStats = require(ReplicatedStorage.Shared.Util.CardStats)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local CardRenderer = require(ReplicatedStorage.Shared.UI.CardRenderer)
local CardTile = require(ReplicatedStorage.Shared.UI.CardTile)
local RestrictionTip = require(ReplicatedStorage.Shared.UI.RestrictionTip)
local CardActions = require(ReplicatedStorage.Shared.UI.CardActions)
local Shine = require(ReplicatedStorage.Shared.UI.Shine)
local Sfx = require(ReplicatedStorage.Shared.UI.Sfx)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local player = Players.LocalPlayer

local DeckController = {}
DeckController.Name = "DeckController"

----------------------------------------------------------------------
-- palette (the Backpack's family)
----------------------------------------------------------------------
local WHITE        = Color3.new(1, 1, 1)
local BLACK        = Color3.new(0, 0, 0)
-- SIMPLE: one neutral family. The screen is a see-through dark veil over the
-- world, so colour is left to the cards themselves (their rarity borders).
-- Attack and support are told apart by position and label, not by paint.
local INK          = Color3.fromRGB(12, 13, 18)
local PANEL        = Color3.fromRGB(20, 22, 28)
local PANEL_2      = Color3.fromRGB(28, 30, 38)
local PANEL_TOP    = Color3.fromRGB(26, 28, 35)
local PANEL_BOTTOM = Color3.fromRGB(12, 13, 18)
local SUNK         = Color3.fromRGB(14, 15, 20)
local FIELD        = Color3.fromRGB(32, 34, 42)
local LINE         = Color3.fromRGB(70, 74, 88)
local TEXT         = Color3.fromRGB(233, 236, 242)
local MUTED        = Color3.fromRGB(150, 156, 170)
local DIM          = Color3.fromRGB(104, 110, 124)
local ACCENT       = Color3.fromRGB(214, 218, 228)
local ACCENT_HI    = Color3.fromRGB(240, 242, 248)
local PURPLE       = ACCENT
local ATTACK_C     = Color3.fromRGB(226, 230, 238)
local SUPPORT_C    = Color3.fromRGB(226, 230, 238)
-- The veil over the world while the deck is open: dark, and just see-through.
local VEIL         = Color3.fromRGB(6, 8, 13)
local VEIL_T       = 0.24
local GOOD         = Color3.fromRGB(110, 232, 160)
local BAD          = Color3.fromRGB(255, 112, 134)
local CLOSE_HOT_BG = Color3.fromRGB(78, 32, 50)

local QUART = Enum.EasingStyle.Quart
local QUAD = Enum.EasingStyle.Quad
local BACK = Enum.EasingStyle.Back

-- The HUD's own deck icon, so the window and the button that opens it match.
local DECK_ICON = "rbxassetid://107383168454655"

-- Same sweep art the HUD buttons use, so the light travelling across a deck
-- card reads as the same material as the rest of the game. Wider, fainter and
-- softer than the HUD's: on a card the size of a playing card a narrow hard
-- band reads as a scanline, so this one is nearly half the card wide and much
-- more transparent - light moving under glass rather than a stripe.
local SWEEP_IMAGE = "rbxassetid://135060446578504"
local SWEEP_WIDTH = 0.46
local SWEEP_TRANSPARENCY = 0.9
local SWEEP_LAYERS = 3

-- Deck cards are built once at this width and then scaled to fit their holder.
-- Rebuilding on every resize would throw away and re-stack the Shine strokes
-- on every card; a UIScale costs nothing and keeps proportions exact.
local CARD_REF_W = 240
local CARD_REF_H = 322
local CARD_ASPECT = CARD_REF_W / CARD_REF_H
local SLOT_GAP = 10
local TILE_W = 112

-- Line-up trays: padding round the cards, and the label column beside them.
local TRAY_PAD = 10
local RAIL_MIN, RAIL_MAX = 118, 168

-- The header, in pixels; it scales down as a whole on a narrow window.
local HEADER_H = 64
local HEADER_REF_W = 1240

-- The hover preview, in pixels. Big enough to actually read ability text at a
-- glance, which is the entire reason it exists.
local POPOUT_W = 300
local POPOUT_H = math.floor(POPOUT_W / CARD_ASPECT)

local SORTS = { "Rarity", "Level", "Name", "Copies" }

-- A tile is this many times taller than it is wide. CardTile builds to the same
-- ratio, so keeping it here lets the grid resize cells without ever distorting
-- a card: only the width is chosen, the height follows from it.
local TILE_RATIO = 1.06

-- How long a predicted slot is trusted without the server confirming it.
local PREDICT_TTL = 2.5

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
	ChromeHeight = 70,
	MinDrawerHeight = 170,
}
-- The whole screen's stacking order, in one place. With Sibling ZIndex
-- behaviour a subtree is placed by its ROOT's ZIndex, so the drawer sitting at
-- 50 beside a band at 5 puts every card in the drawer above every card in the
-- deck - which is the one thing the overlay absolutely depends on.
local Z = {
	DeckBand    = 5,
	Links       = 7,
	DrawerShade = 48,
	Drawer      = 50,
	Grid        = 52,
	Tile        = 55,
	Chrome      = 58,
	Controls    = 60,
	TileHover   = 70,
	Dropdown    = 80,
	Toast       = 85,
	Popout      = 90,
}

-- Drawer dressing: charcoal with a purple bias rather than the flat panel
-- grey, so it reads as a separate object floating in front of the deck.
local DRAWER_BG   = Color3.fromRGB(16, 18, 24)
local DRAWER_LINE = Color3.fromRGB(78, 84, 100)

local profile = nil
local state = { mode = "Attack", search = "", variant = "All", sort = "Rarity" }
-- Which slot the player armed for the next pick. nil = just browsing.
local pendingSlot = nil
-- Drawer open/closed. Read by Refresh so freshly built tiles are born at the
-- size the drawer is currently showing.
local drawerExpanded = false
-- The collection tile under the cursor, for hover + E.
local hoveredItem = nil
local hoveredTile = nil
-- Drag and drop: a press on a collection tile becomes a drag once it moves.
local drag = nil
local dragEndedAt = 0
local DRAG_THRESHOLD = 8

local ui = {}
local slotViews = {}
-- Fingerprint of the card inventory currently drawn in the collection. Deck
-- equips do not change it, so their ProfileSync can update in place.
local collectionFingerprint: string? = nil

-- PREDICTED SLOTS, keyed "attack:3". Each holds what this client has asked the
-- server to put there - a card, or `false` for "cleared" - until a sync shows
-- the server agreeing, or PREDICT_TTL passes (the server said no). Everything
-- that reads the line-up reads it through effectiveLineup, which lays these
-- over the last synced profile. Without this, four quick E presses all read
-- the same stale line-up and all four aim at slot 1.
local predicted = {}

----------------------------------------------------------------------
-- builders
----------------------------------------------------------------------

local function new(class: string, props: {[string]: any}, children: {Instance}?): any
	local inst = Instance.new(class)
	if inst:IsA("GuiObject") then inst.BorderSizePixel = 0 end
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

local function round(): UICorner
	return new("UICorner", { CornerRadius = UDim.new(1, 0) })
end

local function stroke(colour: Color3, thickness: number, transparency: number?): UIStroke
	return new("UIStroke", { Color = colour, Thickness = thickness,
		Transparency = transparency or 0, LineJoinMode = Enum.LineJoinMode.Round })
end

-- Text outlines are sized FROM THE TEXT, never a flat number: a heavy outline
-- on a small label of a thin display face thickens every stem and reads as a
-- fake bold. This keeps the outline as separation and nothing more.
local function textOutline(label: TextLabel, transparency: number?): UIStroke
	return stroke(INK, math.clamp(label.TextSize * 0.055, 1, 2.2), transparency)
end

local function tween(object, props, duration, style, direction)
	local t = TweenService:Create(object, TweenInfo.new(duration or 0.14, style or QUAD,
		direction or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function fadeEnds(peak: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, peak),
		NumberSequenceKeypoint.new(1, 1),
	})
end

-- A 1px line that fades out toward both ends.
local function hairline(parent: Instance, name: string, colour: Color3, peak: number, props)
	local line = new("Frame", { Parent = parent, Name = name, BackgroundColor3 = colour })
	for k, v in pairs(props or {}) do line[k] = v end
	new("UIGradient", { Parent = line, Transparency = fadeEnds(peak) })
	return line
end

local function diamond(parent: Instance, name: string, size: number, colour: Color3,
	transparency: number?, position: UDim2?, z: number?)
	return new("Frame", { Parent = parent, Name = name, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position or UDim2.new(), Size = UDim2.fromOffset(size, size), Rotation = 45,
		BackgroundColor3 = colour, BackgroundTransparency = transparency or 0, ZIndex = z or 3 })
end

-- An L-shaped corner accent. `anchor` picks the corner, (0,0) = top-left.
local function bracket(parent: Instance, anchor: Vector2, inset: number, arm: number,
	colour: Color3, transparency: number, z: number, thickness: number?)
	local t = thickness or 1.5
	local box = new("Frame", { Parent = parent, Name = "Bracket", BackgroundTransparency = 1,
		AnchorPoint = anchor,
		Position = UDim2.new(anchor.X, anchor.X == 0 and inset or -inset, anchor.Y, anchor.Y == 0 and inset or -inset),
		Size = UDim2.fromOffset(arm, arm), ZIndex = z })
	new("Frame", { Parent = box, Name = "H", AnchorPoint = anchor, Position = UDim2.fromScale(anchor.X, anchor.Y),
		Size = UDim2.new(1, 0, 0, t), BackgroundColor3 = colour, BackgroundTransparency = transparency, ZIndex = z })
	new("Frame", { Parent = box, Name = "V", AnchorPoint = anchor, Position = UDim2.fromScale(anchor.X, anchor.Y),
		Size = UDim2.new(0, t, 1, 0), BackgroundColor3 = colour, BackgroundTransparency = transparency, ZIndex = z })
	return box
end

local function brackets(parent: Instance, inset: number, arm: number, colour: Color3,
	transparency: number, z: number, thickness: number?)
	local list = {}
	for _, anchor in ipairs({ Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) }) do
		table.insert(list, bracket(parent, anchor, inset, arm, colour, transparency, z, thickness))
	end
	return list
end

-- The Backpack's panel as a reusable plate: stacked-stroke shadow, graphite lit
-- from above, a rim brighter along its top edge, an inner hairline and a faint
-- sheen. Returns the panel to build on.
local function glass(holder: Instance, radius: number, sheen: number?)
	local shadow = new("Frame", { Parent = holder, Name = "Shadow", BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1), ZIndex = 1 }, { corner(radius) })
	for i, spec in ipairs({ { 3, 0.8 }, { 7, 0.88 }, { 12, 0.93 }, { 18, 0.96 } }) do
		new("UIStroke", { Parent = shadow, Name = "Shade" .. i, Color = BLACK, Thickness = spec[1],
			Transparency = spec[2], LineJoinMode = Enum.LineJoinMode.Round })
	end
	-- Fully opaque: the HUD sits right behind this window, and even a few
	-- percent of see-through ghosts its stat chips into the header.
	local panel = new("Frame", { Parent = holder, Name = "Panel", BackgroundColor3 = WHITE,
		BackgroundTransparency = 0, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, {
		corner(radius),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(PANEL_TOP, PANEL_BOTTOM) }),
	})
	local rim = new("UIStroke", { Parent = panel, Name = "Rim", Color = WHITE, Thickness = 1.2, Transparency = 0.25 })
	new("UIGradient", { Parent = rim, Rotation = 90, Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, ACCENT_HI:Lerp(LINE, 0.35)),
		ColorSequenceKeypoint.new(0.45, LINE),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 30, 48)),
	}) })
	new("Frame", { Parent = panel, Name = "InnerRim", BackgroundTransparency = 1, Position = UDim2.fromOffset(1, 1),
		Size = UDim2.new(1, -2, 1, -2), ZIndex = 2 },
		{ corner(math.max(radius - 1, 0)), new("UIStroke", { Color = WHITE, Transparency = 0.95 }) })
	new("Frame", { Parent = panel, Name = "TopSheen", BackgroundColor3 = WHITE,
		Size = UDim2.new(1, 0, 0, sheen or 120), ZIndex = 2 },
		{ corner(radius), new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.955), NumberSequenceKeypoint.new(1, 1) }) }) })
	return panel
end

----------------------------------------------------------------------
-- fade (the Backpack's: walks a subtree, drives its transparencies, and
-- hands back only what nobody else touched meanwhile)
----------------------------------------------------------------------

local FADE_PROPS = {
	Frame = { "BackgroundTransparency" },
	TextLabel = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" },
	TextButton = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" },
	ImageLabel = { "BackgroundTransparency", "ImageTransparency" },
	ImageButton = { "BackgroundTransparency", "ImageTransparency" },
	UIStroke = { "Transparency" },
}

local Fade = {}
Fade.__index = Fade

function Fade.new(roots)
	return setmetatable({ roots = roots, entries = nil, conn = nil }, Fade)
end

function Fade:capture()
	local list = {}
	local function walk(object)
		local props = FADE_PROPS[object.ClassName]
		if props then
			for _, prop in ipairs(props) do
				local rest = object[prop]
				if rest < 0.999 then table.insert(list, { object, prop, rest, rest }) end
			end
		end
		for _, child in ipairs(object:GetChildren()) do walk(child) end
	end
	for _, r in ipairs(self.roots) do walk(r) end
	return list
end

function Fade:apply(a: number)
	for _, e in ipairs(self.entries) do
		local object = e[1]
		if object.Parent then
			local value = e[3] + (1 - e[3]) * a
			object[e[2]] = value
			e[4] = value
		end
	end
end

function Fade:stop(restore: boolean?)
	if self.conn then
		self.conn:Disconnect()
		self.conn = nil
	end
	if restore and self.entries then
		for _, e in ipairs(self.entries) do
			local object = e[1]
			if object.Parent and math.abs(object[e[2]] - e[4]) < 0.002 then
				object[e[2]] = e[3]
			end
		end
		self.entries = nil
	end
end

function Fade:run(from: number, to: number, duration: number)
	self:stop(true)
	self.entries = self:capture()
	local start = os.clock()
	self:apply(from)
	self.conn = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - start) / math.max(duration, 0.001), 0, 1)
		self:apply(from + (to - from) * TweenService:GetValue(t, QUAD, Enum.EasingDirection.Out))
		if t >= 1 then
			if self.conn then
				self.conn:Disconnect()
				self.conn = nil
			end
			if to <= 0 then self:stop(true) end
		end
	end)
end

----------------------------------------------------------------------
-- the line-up model
----------------------------------------------------------------------

local function accent(): Color3
	return state.mode == "Support" and SUPPORT_C or ATTACK_C
end

local function kindColour(kind: string): Color3
	return kind == "support" and SUPPORT_C or ATTACK_C
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

local function kindOf(cardId: string): string
	return isSupportId(cardId) and "support" or "attack"
end

local function activeIndex(): number
	return (profile and profile.decks and profile.decks.active) or 1
end

local function presetAt(index: number)
	if not profile or not profile.decks or type(profile.decks.presets) ~= "table" then
		return { attack = {}, support = {} }
	end
	local presets = profile.decks.presets
	return presets[index] or presets[tostring(index)] or { attack = {}, support = {} }
end

local function activePreset()
	return presetAt(activeIndex())
end

-- A stored slot is a { cardId, variant } table, or `false` for empty (the
-- server keeps line-ups dense - see DeckService.densify). Anything else, or a
-- card id that no longer exists, reads as empty.
local function realSlot(slot)
	if type(slot) == "table" and type(slot.cardId) == "string" and defOf(slot.cardId) then
		return slot
	end
	return nil
end

local function syncedSlot(kind: string, index: number, preset)
	local lineup = (preset or activePreset())[kind]
	if type(lineup) ~= "table" then return nil end
	return realSlot(lineup[index] or lineup[tostring(index)])
end

-- The line-up as the player should SEE it: the last sync, with every
-- prediction still in flight laid over the top.
local function effectiveLineup(kind: string)
	local out = {}
	local now = os.clock()
	local presetIndex = activeIndex()
	local preset = activePreset()
	for i = 1, slotCount(kind) do
		local key = kind .. ":" .. i
		local guess = predicted[key]
		if guess and (guess.expires < now or guess.preset ~= presetIndex) then
			predicted[key] = nil
			guess = nil
		end
		if guess then
			out[i] = guess.cardId and { cardId = guess.cardId, variant = guess.variant } or nil
		else
			out[i] = syncedSlot(kind, i, preset)
		end
	end
	return out
end

-- A sync has landed: every prediction it now agrees with is settled.
local function reconcilePredictions()
	local presetIndex = activeIndex()
	local preset = activePreset()
	for key, guess in pairs(predicted) do
		local kind, index = key:match("^(%a+):(%d+)$")
		local synced = kind and syncedSlot(kind, tonumber(index), preset)
		local agrees
		if guess.cardId then
			agrees = synced ~= nil and synced.cardId == guess.cardId and synced.variant == guess.variant
		else
			agrees = synced == nil
		end
		if agrees or guess.preset ~= presetIndex then
			predicted[key] = nil
		end
	end
end

local function predict(kind: string, index: number, cardId, variant)
	predicted[kind .. ":" .. index] = {
		cardId = cardId or false, variant = variant,
		expires = os.clock() + PREDICT_TTL, preset = activeIndex(),
	}
end

local function filledCount(kind: string, lineup): number
	local n = 0
	for i = 1, slotCount(kind) do
		if lineup[i] then n += 1 end
	end
	return n
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
-- Which copies are in the current line-up, and in which slots, so tiles can
-- say so. A card can now be in several slots at once.
local function equippedKeys(): {[string]: {number}}
	local out = {}
	local kind = slotType()
	local lineup = effectiveLineup(kind)
	for i = 1, slotCount(kind) do
		local slot = lineup[i]
		if slot then
			local key = CardStats.key(slot.cardId, slot.variant)
			out[key] = out[key] or {}
			table.insert(out[key], i)
		end
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

local function NSK(t: number, v: number)
	return NumberSequenceKeypoint.new(t, v)
end

-- One slot: a card-shaped frame holding BOTH an empty socket and a full card,
-- swapped by Visible. Building a CardRenderer card is expensive and players
-- flick between presets constantly, so neither is created on demand.
local function buildSlot(parent: Instance, kind: string, index: number)
	local colour = kindColour(kind)

	-- Width is set by the tray's pack() from the row's height, not by dividing
	-- the row up, so cards sit shoulder to shoulder with only SLOT_GAP between.
	local holder = new("Frame", { Parent = parent, Name = "Slot" .. index, LayoutOrder = index,
		BackgroundTransparency = 1, Size = UDim2.new(0, 100, 1, 0) })

	-- A CARD-SHAPED frame inside the holder, centred, so the socket is always
	-- the card's own shape whatever the holder happens to be.
	local frame = new("Frame", { Parent = holder, Name = "Card", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1, ZIndex = 11 },
		{ new("UIAspectRatioConstraint", { AspectRatio = CARD_ASPECT }) })
	-- The deal-in / slot-in pop. Its own UIScale, separate from the one that
	-- fits the card, so the two never fight.
	local pop = new("UIScale", { Parent = frame, Scale = 1 })

	local socket = new("Frame", { Parent = frame, Name = "Socket", Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = SUNK, BackgroundTransparency = 0.2, ZIndex = 12 }, { corner(14) })
	local socketStroke = stroke(LINE, 1.5, 0.35)
	socketStroke.Parent = socket

	-- EMPTY: a lit socket with corner brackets and a ring holding a plus.
	local empty = new("Frame", { Parent = socket, Name = "Empty", Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, ZIndex = 13 })
	new("Frame", { Parent = empty, Name = "Wash", BackgroundColor3 = colour, Size = UDim2.fromScale(1, 1),
		ZIndex = 13 }, { corner(14), new("UIGradient", { Rotation = 90,
			Transparency = NumberSequence.new({ NSK(0, 0.88), NSK(0.55, 0.97), NSK(1, 1) }) }) })
	local cornerMarks = brackets(empty, 8, 16, colour, 0.55, 14, 2)

	local ring = new("Frame", { Parent = empty, Name = "Ring", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.44), Size = UDim2.fromOffset(46, 46),
		BackgroundColor3 = colour, BackgroundTransparency = 0.9, ZIndex = 14 }, { round() })
	local ringStroke = stroke(colour, 1.5, 0.4)
	ringStroke.Parent = ring
	local ringScale = new("UIScale", { Parent = ring, Scale = 1 })
	local plus = {}
	for _, size in ipairs({ Vector2.new(16, 2), Vector2.new(2, 16) }) do
		table.insert(plus, new("Frame", { Parent = ring, Name = "Plus", AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(size.X, size.Y),
			BackgroundColor3 = colour, ZIndex = 15 }, { corner(1) }))
	end
	local slotLabel = textLabel({ Parent = empty, Name = "SlotLabel", AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(1, -12, 0, 16),
		Text = ("SLOT %d"):format(index), TextSize = 12, TextColor3 = DIM,
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 14 })

	-- FULL: the card itself.
	local cardHost = new("Frame", { Parent = frame, Name = "CardHost", Visible = false,
		Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
		ClipsDescendants = true, ZIndex = 14 }, { corner(14) })
	local card = CardRenderer.create(cardHost, CARD_REF_W, 14)
	card.root.AnchorPoint = Vector2.new(0.5, 0.5)
	card.root.Position = UDim2.fromScale(0.5, 0.5)
	local scale = new("UIScale", { Parent = card.root, Scale = 1 })

	-- The sweep. Blur is faked by STACKING a few copies at different widths and
	-- transparencies: overlapping soft bands that never share an edge composite
	-- into something with no hard boundary. It rides the HOST, so it passes over
	-- the whole card including its border.
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

	-- Hovering a full slot darkens the card and says what a click does.
	local shade = new("Frame", { Parent = frame, Name = "Shade", Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = BLACK, BackgroundTransparency = 1, ZIndex = 21 }, { corner(14) })
	local removeTag = new("Frame", { Parent = frame, Name = "RemoveTag", Visible = false,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Color3.fromRGB(46, 14, 24), BackgroundTransparency = 0.05, ZIndex = 22 },
		{ round(), stroke(BAD, 1.4, 0.15),
			new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }) })
	local removeText = textLabel({ Parent = removeTag, Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X, Text = "REMOVE", TextSize = 14, TextColor3 = BAD,
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
	textOutline(removeText).Parent = removeText

	-- The frame is already the card's aspect, so one axis is enough.
	local function refit()
		local size = frame.AbsoluteSize
		if size.X <= 0 then return end
		-- AbsoluteSize includes the pop scale and the window's open-animation
		-- scale, and the card inside inherits both anyway, so they are divided
		-- back out here or the fit would drift while either is moving.
		local outer = (ui.rootScale and ui.rootScale.Scale) or 1
		scale.Scale = (size.X / math.max(pop.Scale * outer, 0.01)) / CARD_REF_W
	end
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	task.defer(refit)

	local click = new("TextButton", { Parent = frame, Name = "Click", Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1, Text = "", ZIndex = 24 })
	Sfx.bindButton(click)

	local view = { kind = kind, index = index, holder = holder, frame = frame, pop = pop,
		socket = socket, socketStroke = socketStroke, empty = empty, cornerMarks = cornerMarks,
		ring = ring, ringStroke = ringStroke, ringScale = ringScale, plus = plus, slotLabel = slotLabel,
		sweeps = sweeps, cardHost = cardHost, card = card, click = click, shade = shade,
		removeTag = removeTag, removeText = removeText, refit = refit, renderKey = nil, armed = nil, armTween = nil }

	click.MouseEnter:Connect(function()
		if view.renderKey then
			view.removeTag.Visible = true
			tween(view.shade, { BackgroundTransparency = 0.5 }, 0.12)
		else
			tween(view.ringScale, { Scale = 1.12 }, 0.16, BACK)
			if not view.armed then view.socketStroke.Transparency = 0.05 end
		end
	end)
	click.MouseLeave:Connect(function()
		view.removeTag.Visible = false
		tween(view.shade, { BackgroundTransparency = 1 }, 0.12)
		tween(view.ringScale, { Scale = 1 }, 0.14)
		if not view.renderKey and not view.armed then view.socketStroke.Transparency = 0.35 end
	end)

	return view
end

-- The armed slot is the one the next card lands in, and it has to be findable
-- at a glance: its brackets light, its ring fills, and its outline breathes.
function DeckController:PaintArmed(view, armed: boolean)
	if view.armed == armed then return end
	view.armed = armed
	local colour = kindColour(view.kind)
	if view.armTween then
		view.armTween:Cancel()
		view.armTween = nil
	end
	view.ring.BackgroundTransparency = armed and 0.35 or 0.9
	view.ringStroke.Transparency = armed and 0 or 0.4
	for _, bar in ipairs(view.plus) do
		bar.BackgroundColor3 = armed and WHITE or colour
	end
	for _, mark in ipairs(view.cornerMarks) do
		for _, arm in ipairs(mark:GetChildren()) do
			arm.BackgroundTransparency = armed and 0 or 0.55
		end
	end
	view.slotLabel.Text = armed and "PICK A CARD" or ("SLOT %d"):format(view.index)
	view.slotLabel.TextColor3 = armed and colour or DIM
	view.socketStroke.Color = armed and colour or LINE
	view.socketStroke.Thickness = armed and 2 or 1.5
	view.socketStroke.Transparency = armed and 0 or 0.35
	if armed then
		view.armTween = TweenService:Create(view.socketStroke,
			TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Transparency = 0.65 })
		view.armTween:Play()
	end
end

-- Support N assists Attack N. Both line-ups are on screen at once, stacked,
-- and each column pair is tied by a short link in the gap between the trays -
-- lit when both halves of the pair are filled.
function DeckController:BuildLinks()
	if not ui.links then return end
	for _, c in ipairs(ui.links:GetChildren()) do c:Destroy() end
	ui.linkViews = {}
	for i = 1, math.min(slotCount("attack"), slotCount("support")) do
		local line = new("Frame", { Parent = ui.links, Name = "Link" .. i, BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.78, Size = UDim2.fromOffset(2, 10), ZIndex = Z.Links },
			{ new("UIGradient", { Rotation = 90, Color = ColorSequence.new(ATTACK_C, SUPPORT_C) }) })
		local node = diamond(ui.links, "Node" .. i, 8, WHITE, 0.55, UDim2.new(), Z.Links + 1)
		new("UIGradient", { Parent = node, Rotation = 45, Color = ColorSequence.new(ATTACK_C, SUPPORT_C) })
		ui.linkViews[i] = { line = line, node = node }
	end
end

-- Positions come from the slots' measured rectangles. The root carries a
-- UIScale (the open animation), and absolute pixels include it while the
-- offsets set here are in unscaled units - hence the division.
function DeckController:UpdateLinks()
	if not ui.linkViews or not slotViews.attack or not ui.links then return end
	local layer = ui.links
	local origin = layer.AbsolutePosition
	local s = (ui.rootScale and ui.rootScale.Scale) or 1
	if s <= 0 then return end

	-- The card's rectangle from its HOLDER, which has no pop scale on it, so a
	-- card mid-pop does not make the links jump.
	local function cardRect(view)
		local at, size = view.holder.AbsolutePosition, view.holder.AbsoluteSize
		local w, h = size.X, size.Y
		if h <= 0 or w <= 0 then return nil end
		if w / h > CARD_ASPECT then w = h * CARD_ASPECT else h = w / CARD_ASPECT end
		local cx, cy = at.X + size.X / 2, at.Y + size.Y / 2
		return cx, cy - h / 2, cy + h / 2
	end

	for i, link in ipairs(ui.linkViews) do
		local a, b = slotViews.attack[i], slotViews.support[i]
		-- Not `a and cardRect(a)`: an and/or expression keeps only the FIRST
		-- value of a call, and the rectangle is three.
		local ax, aBottom, bTop
		if a then
			local cx, _, bottom = cardRect(a)
			ax, aBottom = cx, bottom
		end
		if b then
			local _, top = cardRect(b)
			bTop = top
		end
		if ax and aBottom and bTop then
			local x = (ax - origin.X) / s
			local y1 = (aBottom - origin.Y) / s + 3
			local y2 = (bTop - origin.Y) / s - 3
			local len = math.max(0, y2 - y1)
			link.line.Position = UDim2.fromOffset(math.floor(x - 1), math.floor(y1))
			link.line.Size = UDim2.fromOffset(2, math.floor(len))
			link.node.Position = UDim2.fromOffset(math.floor(x), math.floor(y1 + len / 2))
			link.line.Visible = len > 6
			link.node.Visible = len > 6
		else
			link.line.Visible = false
			link.node.Visible = false
		end
	end
end

-- Two trays, attack over support. Each hugs its label column and its cards
-- and sits centred in the band, so the eye lands on the line-up rather than
-- on a label stranded at the far edge of an ultrawide.
function DeckController:BuildDeckBand()
	if not ui.deckRow then return end

	for _, c in ipairs(ui.deckRow:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	slotViews = { attack = {}, support = {} }
	ui.rows = {}
	ui.rails = {}
	ui.trays = {}
	ui.trayChrome = {}

	for order, kind in ipairs({ "attack", "support" }) do
		local count = slotCount(kind)
		local colour = kindColour(kind)

		local section = new("Frame", { Parent = ui.deckRow, Name = kind .. "Section", LayoutOrder = order,
			BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0.5, -7), ZIndex = Z.DeckBand })

		local tray = new("Frame", { Parent = section, Name = "Tray", AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, 600, 1, 0),
			BackgroundTransparency = 1, ZIndex = Z.DeckBand })
		ui.trays[kind] = tray

		-- Everything that is the tray's DRESSING lives in one frame, so the open
		-- animation can fade it without touching the cards.
		local chrome = new("Frame", { Parent = tray, Name = "Chrome", BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1), ZIndex = Z.DeckBand })
		ui.trayChrome[kind] = chrome
		-- No tray panel: the row sits straight on the see-through veil.

		-- THE LABEL COLUMN: what this row is, how full it is, and what it adds up to.
		local rail = new("Frame", { Parent = chrome, Name = "Rail", BackgroundTransparency = 1,
			Position = UDim2.fromOffset(18, 0), Size = UDim2.new(0, RAIL_MIN, 1, 0), ZIndex = 16 })
		local stack = new("Frame", { Parent = rail, Name = "Stack", AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 16 },
			{ new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4),
				HorizontalAlignment = Enum.HorizontalAlignment.Right }) })
		local over = textLabel({ Parent = stack, Name = "Over", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 13),
			Text = "LINE-UP", TextSize = 11, TextColor3 = DIM, Visible = false, ZIndex = 16 })
		local caption = textLabel({ Parent = stack, Name = "Caption", LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 30), Text = string.upper(kind), TextSize = 26,
			TextColor3 = TEXT, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 16 })
		local captionStroke = textOutline(caption)
		captionStroke.Parent = caption

		local pipRow = new("Frame", { Parent = stack, Name = "Pips", LayoutOrder = 4,
			Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, ZIndex = 16 },
			{ new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4),
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				SortOrder = Enum.SortOrder.LayoutOrder }) })
		local pips = {}
		for i = 1, count do
			pips[i] = new("Frame", { Parent = pipRow, Name = "Pip" .. i, LayoutOrder = i,
				Size = UDim2.fromOffset(12, 3), BackgroundColor3 = WHITE, BackgroundTransparency = 0.8, ZIndex = 16 }, { corner(2) })
		end
		local countText = textLabel({ Parent = stack, Name = "Count", LayoutOrder = 3,
			Size = UDim2.new(1, 0, 0, 16), Text = "0 / " .. count, TextSize = 13, TextColor3 = MUTED,
			TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 16 })

		local statA = textLabel({ Parent = stack, Name = "StatA", LayoutOrder = 5, Visible = false,
			Size = UDim2.new(1, 0, 0, 15), Text = "", TextSize = 12, TextColor3 = TEXT,
			RichText = true, ZIndex = 16 })
		local statB = textLabel({ Parent = stack, Name = "StatB", LayoutOrder = 6, Visible = false,
			Size = UDim2.new(1, 0, 0, 15), Text = "", TextSize = 12, TextColor3 = TEXT,
			RichText = true, ZIndex = 16 })
		ui.rails[kind] = { rail = rail, caption = caption, captionStroke = captionStroke, over = over,
			pips = pips, countText = countText, statA = statA, statB = statB }

		local row = new("Frame", { Parent = tray, Name = "Row", BackgroundTransparency = 1,
			Position = UDim2.fromOffset(18 + RAIL_MIN + 12, TRAY_PAD),
			Size = UDim2.new(0, 400, 1, -TRAY_PAD * 2), ZIndex = 10 },
			{ new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, SLOT_GAP), SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Left,
				VerticalAlignment = Enum.VerticalAlignment.Center }) })
		ui.rows[kind] = row

		for i = 1, count do
			local view = buildSlot(row, kind, i)
			slotViews[kind][i] = view
			view.click.Activated:Connect(function()
				if effectiveLineup(kind)[i] then
					self:ClearSlot(kind, i)
					return
				end
				-- Empty: arm it so the next card picked lands HERE, and put the
				-- collection on the matching tab so there is something valid to
				-- pick. Pressing the armed slot again disarms it.
				if pendingSlot and pendingSlot.slotType == kind and pendingSlot.index == i then
					pendingSlot = nil
				else
					pendingSlot = { slotType = kind, index = i }
				end
				local mode = (kind == "support") and "Support" or "Attack"
				local changed = state.mode ~= mode
				state.mode = mode
				self:RefreshSlots()
				if changed then self:Refresh() else self:RefreshEquippedMarkers() end
				CardActions.refresh()
			end)
		end

		-- Cards are as tall as the tray allows and as wide as that implies - but
		-- never so wide the tray overflows a narrow window; then width decides.
		local function pack()
			local sectionSize = section.AbsoluteSize
			local s = (ui.rootScale and ui.rootScale.Scale) or 1
			local h = sectionSize.Y / math.max(s, 0.01)
			local fullW = sectionSize.X / math.max(s, 0.01)
			if h <= 0 or fullW <= 0 then return end
			local railW = math.clamp(math.floor(h * 0.62), RAIL_MIN, RAIL_MAX)
			local cardH = h - TRAY_PAD * 2
			local w = math.floor(cardH * CARD_ASPECT)
			local room = fullW - (18 + railW + 12 + TRAY_PAD + 4)
			w = math.max(40, math.min(w, math.floor((room - (count - 1) * SLOT_GAP) / count)))
			for _, view in pairs(slotViews[kind]) do
				view.holder.Size = UDim2.new(0, w, 1, 0)
			end
			local cardsW = count * w + (count - 1) * SLOT_GAP
			rail.Size = UDim2.new(0, railW, 1, 0)
			row.Position = UDim2.fromOffset(18 + railW + 12, TRAY_PAD)
			row.Size = UDim2.new(0, cardsW, 1, -TRAY_PAD * 2)
			tray.Size = UDim2.new(0, 18 + railW + 12 + cardsW + TRAY_PAD + 4, 1, 0)
			caption.TextSize = math.clamp(math.floor(railW * 0.17), 18, 28)
			captionStroke.Thickness = math.clamp(caption.TextSize * 0.055, 1, 2.2)
			task.defer(function() self:UpdateLinks() end)
		end
		section:GetPropertyChangedSignal("AbsoluteSize"):Connect(pack)
		task.defer(pack)
	end

	self:BuildLinks()

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

-- Deals the line-up in: every card pops from slightly small, left to right,
-- attack a beat ahead of support.
function DeckController:DealIn(stagger: number)
	for _, kind in ipairs({ "attack", "support" }) do
		for i, view in ipairs(slotViews[kind] or {}) do
			view.pop.Scale = 0.86
			local delay = (i - 1) * stagger + (kind == "support" and 0.07 or 0)
			task.delay(delay, function()
				tween(view.pop, { Scale = 1 }, 0.36, BACK)
			end)
		end
	end
end

function DeckController:RefreshSlots()
	if not slotViews.attack then return end
	local lineups = {}

	for _, kind in ipairs({ "attack", "support" }) do
		local lineup = effectiveLineup(kind)
		lineups[kind] = lineup
		local colour = kindColour(kind)

		for i, view in pairs(slotViews[kind]) do
			local slot = lineup[i]
			if slot and profile then
				local owned = profile.cards and profile.cards[CardStats.key(slot.cardId, slot.variant)]
				local level = owned and owned.level or 0
				local nextRenderKey = ("%s:%s:%s"):format(slot.cardId, slot.variant, tostring(level))
				self:PaintArmed(view, false)
				if view.renderKey ~= nextRenderKey then
					local wasEmpty = view.renderKey == nil
					local variant = VariantConfig.get(slot.variant)
					CardRenderer.update(view.card, {
						cardId = slot.cardId, variant = slot.variant, level = level })
					Shine.apply(view.socket, variant.id, CARD_REF_W)
					view.renderKey = nextRenderKey
					view.refit()
					-- A card arriving in a slot pops in, so an E press has a
					-- visible landing spot even from across the screen.
					if wasEmpty and ui.screen and ui.screen.Enabled then
						view.pop.Scale = 0.84
						tween(view.pop, { Scale = 1 }, 0.34, BACK)
					end
				end
				view.cardHost.Visible = true
				view.empty.Visible = false
				view.socket.BackgroundTransparency = 1
				view.socketStroke.Transparency = 1
			else
				-- Only tear down artwork/glow when this slot actually changed to empty.
				if view.renderKey ~= nil then
					view.cardHost.Visible = false
					view.removeTag.Visible = false
					view.shade.BackgroundTransparency = 1
					view.empty.Visible = true
					view.socket.BackgroundTransparency = 0.2
					Shine.remove(view.socket)
					view.renderKey = nil
					view.armed = nil
				end
				local armed = pendingSlot ~= nil
					and pendingSlot.slotType == kind and pendingSlot.index == i
				self:PaintArmed(view, armed)
			end
		end

		-- the label column
		local rail = ui.rails and ui.rails[kind]
		if rail then
			local filled = filledCount(kind, lineup)
			for i, pip in ipairs(rail.pips) do
				pip.BackgroundTransparency = 0
				pip.BackgroundColor3 = lineup[i] and Color3.fromRGB(236, 238, 244) or Color3.fromRGB(58, 62, 74)
			end
			rail.countText.Text = ("%d / %d"):format(filled, slotCount(kind))
			local dimHex = DIM:ToHex()
			if kind == "attack" then
				-- What the row adds up to, from the same CardStats combat uses.
				local dmg, hp = 0, 0
				for i = 1, slotCount(kind) do
					local s = lineup[i]
					if s then
						local owned = profile and profile.cards
							and profile.cards[CardStats.key(s.cardId, s.variant)]
						local stats = CardStats.compute(s.cardId, s.variant, owned and owned.level or 0)
						if stats then
							dmg += stats.dmg
							hp += stats.hp
						end
					end
				end
				rail.statA.Text = ('<font color="#%s">DMG</font>  %s'):format(dimHex, Format.short(dmg))
				rail.statB.Text = ('<font color="#%s">HP</font>   %s'):format(dimHex, Format.short(hp))
			else
				rail.statA.Text = ('<font color="#%s">BACKS THE</font>'):format(dimHex)
				rail.statB.Text = ('<font color="#%s">ATTACK ABOVE</font>'):format(dimHex)
			end
		end
	end

	-- a pair is lit when both of its halves are filled
	for i, link in ipairs(ui.linkViews or {}) do
		local paired = lineups.attack[i] ~= nil and lineups.support[i] ~= nil
		link.line.BackgroundTransparency = paired and 0.1 or 0.78
		link.node.BackgroundTransparency = paired and 0 or 0.55
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
-- A tile's badge says where its copies sit: "IN 3", "IN 1·4", or a count once
-- there are too many slots to list.
local function updateEquippedBadge(root: GuiObject, slots: {number}?)
	local signature = (slots and #slots > 0) and table.concat(slots, ",") or ""
	if (root:GetAttribute("EquippedSlots") or "") == signature then return end
	root:SetAttribute("EquippedSlots", signature)
	local old = root:FindFirstChild("EquippedBadge")
	if old then old:Destroy() end
	if signature == "" then return end

	local caption
	if #slots == 1 then
		caption = "IN " .. slots[1]
	elseif #slots <= 3 then
		caption = "IN " .. table.concat(slots, "\u{00B7}")
	else
		caption = ("x%d IN DECK"):format(#slots)
	end

	local badge = new("Frame", { Name = "EquippedBadge", Parent = root,
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -22),
		Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = INK, BackgroundTransparency = 0.1, ZIndex = Z.Tile + 6 },
		{ corner(9), stroke(WHITE, 1.2, 0.45),
			new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }) })
	local badgeText = textLabel({ Parent = badge, Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X, Text = caption, TextSize = 12,
		TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = Z.Tile + 7 })
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

-- A quick lift on the tile an E press just used, so the key visibly did
-- something to THAT card.
function DeckController:PunchTile(tile: GuiObject?)
	if not tile or not tile.Parent then return end
	local lift = tile:FindFirstChild("Lift")
	if not lift then return end
	lift.Scale = 1.15
	local resting = (hoveredTile == tile) and DRAWER.HoverScale or 1
	tween(lift, { Scale = resting }, 0.3, BACK)
end

-- What the collection grid was last built for. Opening the deck used to
-- destroy and rebuild every tile (65+ CardTiles) each time - that was the lag.
local builtKey: string? = nil
local function collectionKey(): string
	return table.concat({ fingerprintInventory(profile), state.mode, state.search, state.variant, state.sort }, "#")
end

-- Builds the grid only if what it would show has changed; otherwise just
-- updates the IN-DECK badges on the tiles that are already there.
function DeckController:EnsureCollection()
	if not ui.grid or not profile then return end
	if builtKey == collectionKey() then
		self:RefreshEquippedMarkers()
	else
		self:Refresh()
	end
end

function DeckController:Refresh()
	if not ui.grid then return end
	builtKey = collectionKey()
	local savedCanvas = ui.grid.CanvasPosition
	collectionFingerprint = fingerprintInventory(profile)
	hoveredItem, hoveredTile = nil, nil

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

		-- A PRESS OPENS THE CARD. A click cannot mean both "put this in my deck"
		-- and "pour essence into it", so it means "open this", and the pop-out
		-- offers both. The hover preview is dismissed first: it is anchored to
		-- the same tile and would otherwise sit on top of the pop-out.
		tile.root.Activated:Connect(function()
			-- A drag that ends on its own tile is not a click.
			if (drag and drag.active) or os.clock() - dragEndedAt < 0.3 then return end
			self:HidePopout()
			CardActions.open(item, profile, {
				-- Read live every time rather than captured at build: equipping
				-- no longer rebuilds the grid, so a captured value would go stale
				-- the first time anything moved.
				deckState = function(chosen) return self:DeckStateFor(chosen) end,
				add = function(chosen) return self:AddCopy(chosen) end,
				remove = function(chosen) return self:RemoveCopy(chosen) end,
			}, tile.root)
		end)

		-- Hover: come forward, not jump. A UIScale rather than a size tween,
		-- because the grid layout owns every child's Size and would fight one.
		-- Scale, a brightening wash and a solid outline together read as
		-- "nearer" far better than any one of them cranked up.
		local lift = new("UIScale", { Parent = tile.root, Name = "Lift", Scale = 1 })
		local wash = new("Frame", { Parent = tile.root, Name = "HoverWash",
			Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = WHITE,
			BackgroundTransparency = 1, ZIndex = Z.Tile + 5 },
			{ corner(20) })
		local restingStroke = tile.stroke.Thickness
		local hoverInfo = TweenInfo.new(DRAWER.HoverTime,
			Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

		tile.root.MouseEnter:Connect(function()
			hoveredItem, hoveredTile = item, tile.root
			tile.root.ZIndex = Z.TileHover
			tile.stroke.Thickness = restingStroke + 1
			TweenService:Create(lift, hoverInfo, { Scale = DRAWER.HoverScale }):Play()
			TweenService:Create(wash, hoverInfo, { BackgroundTransparency = 0.88 }):Play()
			-- While the pop-out is up it IS the preview, and a much better one.
			if not CardActions.isOpen() and not (drag and drag.active) then
				self:ShowPopout(tile.root, item)
			end
		end)
		tile.root.MouseLeave:Connect(function()
			if hoveredTile == tile.root then
				hoveredItem, hoveredTile = nil, nil
			end
			tile.root.ZIndex = Z.Tile
			tile.stroke.Thickness = restingStroke
			TweenService:Create(lift, hoverInfo, { Scale = 1 }):Play()
			TweenService:Create(wash, hoverInfo, { BackgroundTransparency = 1 }):Play()
			self:HidePopout()
		end)

		-- DRAG: press here, and once the pointer travels DRAG_THRESHOLD pixels
		-- the card lifts off and can be dropped on any slot of its line-up.
		tile.root.InputBegan:Connect(function(input)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
				drag = { item = item, tile = tile.root, active = false,
					start = Vector2.new(input.Position.X, input.Position.Y) }
			end
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
-- deck actions

-- What the pop-out needs to draw its deck row for one card: how many copies of
-- it are in the line-up, how many you own, and whether another can go in.
function DeckController:DeckStateFor(item)
	local kind = kindOf(item.cardId)
	local lineup = effectiveLineup(kind)
	local n = slotCount(kind)
	local entry = profile and profile.cards and profile.cards[CardStats.key(item.cardId, item.variant)]
	local owned = entry and entry.count or 0
	local used, free = 0, 0
	for i = 1, n do
		local s = lineup[i]
		if not s then
			free += 1
		elseif s.cardId == item.cardId and s.variant == item.variant then
			used += 1
		end
	end
	local armed = pendingSlot ~= nil and pendingSlot.slotType == kind

	local canAdd, reason = true, nil
	if owned < 1 then
		canAdd, reason = false, "NOT OWNED"
	elseif armed then
		canAdd = true
	elseif free == 0 then
		canAdd, reason = false, "LINE-UP FULL"
	elseif used >= owned then
		canAdd, reason = false, owned == 1 and "ONLY 1 COPY" or ("ALL %d IN DECK"):format(owned)
	end
	return { inDeck = used, owned = owned, free = free, canAdd = canAdd, reason = reason }
end

-- Puts one more copy of `item` into its line-up: into the armed slot if one
-- is armed, otherwise the first free slot. Returns ok, reason.
--
-- The request goes to the server and the result is PREDICTED here at once, so
-- the next press - however quick - already sees this slot as taken. The
-- prediction mirrors DeckService's rules exactly, including the one case
-- where a copy moves rather than duplicates (every owned copy already placed,
-- and a slot armed for it).
function DeckController:AddCopy(item): (boolean, string?)
	if not profile then return false, "LOADING" end
	local kind = kindOf(item.cardId)
	local n = slotCount(kind)
	local info = self:DeckStateFor(item)
	if not info.canAdd then return false, info.reason end

	local lineup = effectiveLineup(kind)
	local index
	if pendingSlot and pendingSlot.slotType == kind then
		index = pendingSlot.index
		local there = lineup[index]
		if there and there.cardId == item.cardId and there.variant == item.variant then
			pendingSlot = nil
			self:RefreshSlots()
			return false, "ALREADY THERE"
		end
	else
		for i = 1, n do
			if not lineup[i] then index = i break end
		end
		if not index then return false, "LINE-UP FULL" end
	end

	if info.inDeck >= info.owned then
		for i = n, 1, -1 do
			local s = lineup[i]
			if i ~= index and s and s.cardId == item.cardId and s.variant == item.variant then
				predict(kind, i, nil)
				break
			end
		end
	end
	predict(kind, index, item.cardId, item.variant)
	Remotes.RequestSetDeck:FireServer(kind, index, item.cardId, item.variant)
	pendingSlot = nil

	self:RefreshSlots()
	self:RefreshEquippedMarkers()
	CardActions.refresh()
	return true
end

-- Takes one copy of `item` back out: the highest slot holding it, so the
-- line-up empties from the end the way E filled it.
function DeckController:RemoveCopy(item): boolean
	local kind = kindOf(item.cardId)
	local lineup = effectiveLineup(kind)
	for i = slotCount(kind), 1, -1 do
		local s = lineup[i]
		if s and s.cardId == item.cardId and s.variant == item.variant then
			self:ClearSlot(kind, i)
			return true
		end
	end
	return false
end

function DeckController:ClearSlot(kind: string, index: number)
	predict(kind, index, nil)
	Remotes.RequestSetDeck:FireServer(kind, index, nil, nil)
	pendingSlot = nil
	self:RefreshSlots()
	self:RefreshEquippedMarkers()
	CardActions.refresh()
end

-- Kept for anything still calling the old name.
function DeckController:EquipFromTile(item)
	return self:AddCopy(item)
end

-- The server owns which preset is active; this asks, and predicts the answer
-- so the switch is instant. The sync that follows confirms it.
function DeckController:SetPreset(index: number)
	if not profile or not profile.decks then return end
	if index == activeIndex() then return end
	table.clear(predicted)
	pendingSlot = nil
	profile.decks.active = index
	Remotes.RequestSetActiveDeck:FireServer(index)
	self:RefreshSlots()
	self:RefreshEquippedMarkers()
	CardActions.refresh()
	self:DealIn(0.03)
	-- The cursor is still on the chip that was just pressed.
	if ui.presetHover then
		ui.subtitle.Text = ("Preset %d  \u{00B7}  in use"):format(index)
	end
end

function DeckController:Toast(message: string, colour: Color3?)
	if not ui.toast then return end
	ui.toastToken = (ui.toastToken or 0) + 1
	local mine = ui.toastToken
	local c = colour or ACCENT_HI
	ui.toastText.Text = message
	ui.toastText.TextColor3 = c
	ui.toastDot.BackgroundColor3 = c
	ui.toastStroke.Color = c
	ui.toast.Visible = true
	ui.toastScale.Scale = 0.88
	tween(ui.toastScale, { Scale = 1 }, 0.22, BACK)
	task.delay(1.5, function()
		if mine == ui.toastToken and ui.toast then ui.toast.Visible = false end
	end)
end

-- header

local function presetFilled(index: number): number
	local preset = presetAt(index)
	local n = 0
	for _, kind in ipairs({ "attack", "support" }) do
		for i = 1, slotCount(kind) do
			if syncedSlot(kind, i, preset) then n += 1 end
		end
	end
	return n
end

function DeckController:RefreshHeader()
	if not ui.title then return end
	local index = activeIndex()
	local attack = effectiveLineup("attack")
	local support = effectiveLineup("support")
	local a, s = filledCount("attack", attack), filledCount("support", support)
	local total = slotCount("attack") + slotCount("support")

	ui.subtitleBase = ("Preset %d  \u{00B7}  %d / %d cards"):format(index, a + s, total)
	if not ui.presetHover then ui.subtitle.Text = ui.subtitleBase end

	-- the ATTACK | SUPPORT switch
	local mode = slotType()
	for kind, seg in pairs(ui.segments or {}) do
		local on = kind == mode
		local count = kind == "attack" and a or s
		seg.count.Text = ("%d/%d"):format(count, slotCount(kind))
		seg.label.TextColor3 = on and WHITE or MUTED
		seg.count.TextColor3 = on and WHITE or DIM
		seg.dot.BackgroundColor3 = on and WHITE or kindColour(kind)
	end
	if ui.modeHighlight and ui.lastMode ~= mode then
		local first = ui.lastMode == nil
		ui.lastMode = mode
		local colour = kindColour(mode)
		local goal = mode == "attack" and UDim2.new(0, 4, 0, 4) or UDim2.new(0.5, 0, 0, 4)
		if first then
			ui.modeHighlight.Position = goal
		else
			tween(ui.modeHighlight, { Position = goal }, 0.28, QUART)
		end
		ui.modeGradient.Color = ColorSequence.new(colour:Lerp(WHITE, 0.08), colour:Lerp(BLACK, 0.42))
		ui.modeStroke.Color = colour:Lerp(WHITE, 0.3)
		ui.modeGlow.Color = colour
	end

	-- the ATTACK | SUPPORT switch in the collection bar
	if ui.modeToggle then
		local t = ui.modeToggle
		local goal = mode == "attack" and UDim2.new(0, 3, 0, 3) or UDim2.new(0.5, 0, 0, 3)
		if t.lastMode == nil then
			t.pill.Position = goal
		elseif t.lastMode ~= mode then
			tween(t.pill, { Position = goal }, 0.26, QUART)
		end
		t.lastMode = mode
		for kind, label in pairs(t.segs) do
			label.TextColor3 = kind == mode and INK or MUTED
		end
	end

	-- the eight presets
	for i, chip in ipairs(ui.presetChips or {}) do
		local on = i == index
		local filled = on and (a + s) or presetFilled(i)
		chip.fill.Parent.Visible = false
		chip.number.TextColor3 = on and INK or (filled > 0 and MUTED or DIM)
		chip.gradient.Color = ColorSequence.new(WHITE, WHITE)
		chip.btn.BackgroundTransparency = on and 0.06 or 1
		chip.stroke.Transparency = 1
		chip.glow.Enabled = false
		chip.filled = filled
	end
end

-- build

function DeckController:Build(playerGui: Instance)
	local gui = new("ScreenGui", { Parent = playerGui, Name = "DeckBuilder",
		Enabled = false, ResetOnSpawn = false, IgnoreGuiInset = true,
		DisplayOrder = 20, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
	ui.screen = gui

	ui.dim = new("TextButton", { Parent = gui, Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = VEIL, BackgroundTransparency = VEIL_T,
		Text = "", AutoButtonColor = false, ZIndex = 1 })

	-- Active = true is load-bearing, not decoration. `ui.dim` behind this window
	-- is a full-screen button that closes the deck, and a plain Frame does NOT
	-- absorb clicks - so every click on the window that missed a button fell
	-- straight through to the dim and shut the whole screen.
	local root = new("Frame", { Parent = gui, Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.95, 0.94),
		BackgroundTransparency = 1, Active = true, ZIndex = 5 })
	ui.root = root
	ui.rootScale = new("UIScale", { Parent = root, Scale = 1 })

	-- THE WINDOW: the Backpack's sheet of lit glass, replacing the old thick
	-- purple shine frame. One colour of light, a hairline rim, brackets.
	-- NO WINDOW. The whole screen is the dim veil (ui.dim) with the world
	-- blurred behind it; the header, line-ups and collection sit straight on it.

	local content = new("Frame", { Parent = root, Name = "Content", BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1), ZIndex = 5 },
		{ new("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 14),
			PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18) }) })
	ui.content = content

	------------------------------------------------------------------
	-- HEADER: identity on the left, the ATTACK | SUPPORT switch in the
	-- middle, the presets and the close button on the right. Each of the
	-- three clusters scales on its own anchor on a narrow window, so they
	-- shrink toward their own edge instead of sliding into each other.
	------------------------------------------------------------------
	local header = new("Frame", { Parent = content, Name = "Header", BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, HEADER_H), ZIndex = 10 })
	ui.header = header
	ui.headerScales = {}

	local function cluster(name: string, anchor: Vector2, position: UDim2, size: UDim2)
		local f = new("Frame", { Parent = header, Name = name, AnchorPoint = anchor, Position = position,
			Size = size, BackgroundTransparency = 1, ZIndex = 10 })
		table.insert(ui.headerScales, new("UIScale", { Parent = f, Scale = 1 }))
		return f
	end

	-- identity
	local left = cluster("Identity", Vector2.new(0, 0.5), UDim2.new(0, 0, 0.5, 0), UDim2.fromOffset(380, 52))
	local badge = new("Frame", { Parent = left, Name = "IconBadge", AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(46, 46), BackgroundColor3 = WHITE,
		ZIndex = 11 }, {
		corner(13),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(ACCENT:Lerp(PANEL_TOP, 0.5),
			PANEL_BOTTOM:Lerp(ACCENT, 0.12)) }),
		stroke(ACCENT, 1, 0.45),
	})
	new("ImageLabel", { Parent = badge, Name = "Icon", BackgroundTransparency = 1, Image = DECK_ICON,
		ScaleType = Enum.ScaleType.Fit, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.78, 0.78), ZIndex = 12 })
	badge.Visible = false
	ui.title = textLabel({ Parent = left, Name = "Title", Position = UDim2.fromOffset(4, 10),
		Size = UDim2.fromOffset(90, 32), Text = "DECK", TextSize = 30, ZIndex = 11 })
	textOutline(ui.title, 0.45).Parent = ui.title
	ui.subtitle = textLabel({ Parent = left, Name = "Subtitle", Position = UDim2.fromOffset(98, 17),
		Size = UDim2.fromOffset(280, 18), Text = "", TextSize = 14, TextColor3 = MUTED, ZIndex = 11 })

	-- ATTACK | SUPPORT. The tab steers the collection below and marks which
	-- line-up a pick is for; a lit pill slides between the halves.
	local switch = cluster("ModeSwitch", Vector2.new(0.5, 0.5), UDim2.new(0.5, 0, 0.5, 0),
		UDim2.fromOffset(420, 44))
	new("Frame", { Parent = switch, Name = "Track", Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = SUNK, BackgroundTransparency = 0.15, ZIndex = 20 }, { round(), stroke(WHITE, 1, 0.9) })
	local highlight = new("Frame", { Parent = switch, Name = "Highlight", Position = UDim2.new(0, 4, 0, 4),
		Size = UDim2.new(0.5, -4, 1, -8), BackgroundColor3 = WHITE, ZIndex = 21 }, { round() })
	ui.modeHighlight = highlight
	ui.modeGradient = new("UIGradient", { Parent = highlight, Rotation = 90 })
	ui.modeStroke = stroke(ATTACK_C, 1.2, 0.1)
	ui.modeStroke.Parent = highlight
	ui.modeGlow = new("UIStroke", { Parent = highlight, Name = "Glow", Color = ATTACK_C, Thickness = 5,
		Transparency = 0.8, LineJoinMode = Enum.LineJoinMode.Round })
	hairline(highlight, "Sheen", WHITE, 0.55, { AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 1), Size = UDim2.new(0.7, 0, 0, 1), ZIndex = 22 })
	ui.segments = {}
	for order, kind in ipairs({ "attack", "support" }) do
		local seg = new("TextButton", { Parent = switch, Name = kind, Text = "", AutoButtonColor = false,
			BackgroundTransparency = 1, Position = UDim2.fromScale((order - 1) * 0.5, 0),
			Size = UDim2.fromScale(0.5, 1), ZIndex = 23 })
		local group = new("Frame", { Parent = seg, Name = "Group", AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 24),
			AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, ZIndex = 23 },
			{ new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder }) })
		local dotHolder = new("Frame", { Parent = group, Name = "DotHolder", LayoutOrder = 1,
			Size = UDim2.fromOffset(10, 10), BackgroundTransparency = 1, ZIndex = 24 })
		local dot = diamond(dotHolder, "Dot", 7, kindColour(kind), 0, UDim2.fromScale(0.5, 0.5), 24)
		local label = textLabel({ Parent = group, Name = "Label", LayoutOrder = 2,
			Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X,
			Text = string.upper(kind), TextSize = 17, TextColor3 = MUTED, ZIndex = 24 })
		textOutline(label, 0.5).Parent = label
		local chip = new("Frame", { Parent = group, Name = "CountChip", LayoutOrder = 3,
			Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = BLACK, BackgroundTransparency = 0.6, ZIndex = 24 },
			{ round(), new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }) })
		local count = textLabel({ Parent = chip, Name = "Count", Size = UDim2.fromOffset(0, 20),
			AutomaticSize = Enum.AutomaticSize.X, Text = "0/5", TextSize = 12, TextColor3 = DIM, ZIndex = 25 })
		ui.segments[kind] = { btn = seg, label = label, count = count, dot = dot }
		Sfx.bindButton(seg)
		seg.MouseEnter:Connect(function()
			if slotType() ~= kind then label.TextColor3 = TEXT end
		end)
		seg.MouseLeave:Connect(function()
			if slotType() ~= kind then label.TextColor3 = MUTED end
		end)
		seg.Activated:Connect(function()
			local mode = (kind == "support") and "Support" or "Attack"
			if state.mode == mode then return end
			state.mode = mode
			pendingSlot = nil
			self:RefreshSlots()
			self:Refresh()
		end)
	end

	switch.Visible = false

	-- presets + close
	local right = cluster("Controls", Vector2.new(1, 0.5), UDim2.new(1, 0, 0.5, 0), UDim2.fromOffset(420, 46))
	new("UIListLayout", { Parent = right, FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder })

	-- EIGHT PRESETS, all visible at once, each with a sliver showing how full
	-- it is - a switch you can read, where the old dropdown hid seven of them.
	local presetCount = GameConfig.DeckPresets
	local CHIP = 34
	local strip = new("Frame", { Parent = right, Name = "Presets", LayoutOrder = 1,
		Size = UDim2.fromOffset(presetCount * CHIP + (presetCount - 1) * 5 + 12, 46),
		BackgroundColor3 = BLACK, BackgroundTransparency = 0.55, ZIndex = 30 },
		{ round(), stroke(WHITE, 1, 0.9),
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }) })
	ui.presetChips = {}
	for i = 1, presetCount do
		local chipBtn = new("TextButton", { Parent = strip, Name = "Preset" .. i, LayoutOrder = i,
			Size = UDim2.fromOffset(CHIP, CHIP), BackgroundColor3 = WHITE, Text = "",
			AutoButtonColor = false, ZIndex = 31 }, { round() })
		local gradient = new("UIGradient", { Parent = chipBtn, Rotation = 90,
			Color = ColorSequence.new(FIELD, SUNK) })
		local chipStroke = stroke(LINE, 1, 0.2)
		chipStroke.Parent = chipBtn
		local glow = new("UIStroke", { Parent = chipBtn, Name = "Glow", Color = ACCENT, Thickness = 4,
			Transparency = 0.78, LineJoinMode = Enum.LineJoinMode.Round, Enabled = false })
		local number = textLabel({ Parent = chipBtn, Name = "Number", Position = UDim2.fromOffset(0, -2),
			Size = UDim2.fromScale(1, 1), Text = tostring(i), TextSize = 15, TextColor3 = DIM,
			TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 33 })
		local track = new("Frame", { Parent = chipBtn, Name = "Track", AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -5), Size = UDim2.fromOffset(18, 3),
			BackgroundColor3 = BLACK, BackgroundTransparency = 0.45, ZIndex = 32 }, { corner(2) })
		local fill = new("Frame", { Parent = track, Name = "Fill", Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = ACCENT_HI, ZIndex = 33 }, { corner(2) })
		local chipScale = new("UIScale", { Parent = chipBtn, Scale = 1 })
		local chip = { btn = chipBtn, gradient = gradient, stroke = chipStroke, glow = glow,
			number = number, fill = fill, filled = 0 }
		ui.presetChips[i] = chip
		Sfx.bindButton(chipBtn)
		chipBtn.MouseEnter:Connect(function()
			tween(chipScale, { Scale = 1.1 }, 0.14, BACK)
			ui.presetHover = true
			local total = slotCount("attack") + slotCount("support")
			ui.subtitle.Text = i == activeIndex()
				and ("Preset %d  \u{00B7}  in use"):format(i)
				or ("Preset %d  \u{00B7}  %d / %d cards  \u{00B7}  click to switch"):format(i, chip.filled, total)
		end)
		chipBtn.MouseLeave:Connect(function()
			tween(chipScale, { Scale = 1 }, 0.12)
			ui.presetHover = false
			ui.subtitle.Text = ui.subtitleBase or ""
		end)
		chipBtn.Activated:Connect(function()
			self:SetPreset(i)
		end)
	end

	-- close: the Backpack's square glass X
	local closeHolder = new("Frame", { Parent = right, Name = "CloseHolder", LayoutOrder = 2,
		Size = UDim2.fromOffset(46, 46), BackgroundTransparency = 1, ZIndex = 30 })
	new("Frame", { Parent = closeHolder, Name = "Back", Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = FIELD, BackgroundTransparency = 0.1, ZIndex = 31 }, { corner(13), stroke(WHITE, 1, 0.88) })
	local closeHot = new("Frame", { Parent = closeHolder, Name = "Hot", Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = CLOSE_HOT_BG, BackgroundTransparency = 1, ZIndex = 32 }, { corner(13) })
	local closeRim = stroke(BAD, 1.4, 1)
	closeRim.Parent = closeHot
	local glyph = new("Frame", { Parent = closeHolder, Name = "Glyph", BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1), ZIndex = 33 })
	for _, angle in ipairs({ -45, 45 }) do
		new("Frame", { Parent = glyph, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(18, 2.2), Rotation = angle, BackgroundColor3 = TEXT, ZIndex = 34 }, { round() })
	end
	local glyphScale = new("UIScale", { Parent = glyph, Scale = 1 })
	local close = new("TextButton", { Parent = closeHolder, Name = "Close", Text = "", AutoButtonColor = false,
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 35 })
	Sfx.bindButton(close)
	close.MouseEnter:Connect(function()
		tween(closeHot, { BackgroundTransparency = 0.15 }, 0.14)
		tween(closeRim, { Transparency = 0.15 }, 0.14)
		tween(glyphScale, { Scale = 1.12 }, 0.12)
	end)
	close.MouseLeave:Connect(function()
		tween(closeHot, { BackgroundTransparency = 1 }, 0.14)
		tween(closeRim, { Transparency = 1 }, 0.14)
		tween(glyphScale, { Scale = 1 }, 0.12)
	end)
	close.Activated:Connect(function() self:Close() end)

	-- the rule under the header, with a diamond at each end (the Backpack's)
	local rule = hairline(header, "Rule", ACCENT_HI, 0.55, { AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(1, -24, 0, 1), ZIndex = 10 })
	diamond(header, "RuleEndL", 6, ACCENT_HI, 0.45, UDim2.new(0, 4, 1, 0), 10)
	diamond(header, "RuleEndR", 6, ACCENT_HI, 0.45, UDim2.new(1, -4, 1, 0), 10)
	ui.rule = rule
	rule.BackgroundColor3 = WHITE
	for _, name in ipairs({ "RuleEndL", "RuleEndR" }) do
		local d = header:FindFirstChild(name, true)
		if d then d.Visible = false end
	end

	local function fitHeader()
		local s = (ui.rootScale and ui.rootScale.Scale) or 1
		local w = header.AbsoluteSize.X / math.max(s, 0.01)
		if w <= 0 then return end
		local k = math.clamp(w / HEADER_REF_W, 0.6, 1)
		for _, sc in ipairs(ui.headerScales) do sc.Scale = k end
	end
	header:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitHeader)
	task.defer(fitHeader)

	-- Everything below the header shares one body frame, so the band and the
	-- collection split the REMAINING height between them.
	local body = new("Frame", { Parent = content, Name = "Body", Position = UDim2.new(0, 0, 0, HEADER_H + 12),
		Size = UDim2.new(1, 0, 1, -(HEADER_H + 12)), BackgroundTransparency = 1, ZIndex = 6 })

	-- The band is sized around a COLLAPSED drawer, once, and is never touched
	-- again. Expanding the drawer does not reflow it; the drawer just passes
	-- in front. That is the whole contract here.
	ui.body = body
	local band = new("Frame", { Parent = body, Name = "Band",
		Size = UDim2.new(1, 0, 1 - DRAWER.CollapsedHeight, -12),
		BackgroundTransparency = 1, ZIndex = Z.DeckBand })
	ui.band = band

	ui.deckRow = new("Frame", { Parent = band, Name = "Lineups", BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0), ZIndex = 8 },
		{ new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center }) })
	-- The pair links live on their own layer: anything inside the line-ups
	-- frame would be picked up and placed by its list layout. Above the
	-- line-ups (9 > 8) so the tray padding cannot veil them; they only ever
	-- run through the gap between two cards, never over one.
	ui.links = new("Frame", { Parent = band, Name = "PairLinks", BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0), ZIndex = 9 })
	ui.links:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() self:UpdateLinks() end)

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
		BackgroundColor3 = DRAWER_BG, BackgroundTransparency = 0.35,
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
					ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 33, 42)),
					ColorSequenceKeypoint.new(0.35, Color3.fromRGB(20, 22, 29)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 17, 22)) }) }) })
	ui.drawer = drawer

	-- A purple seam along the top edge, fading out to either side so it reads
	-- as a lit rim rather than a drawn line. It rhymes with the DECK banner at
	-- the top of the screen without being the same object.
	new("Frame", { Parent = drawer, Name = "TopSeam", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(1, -40, 0, 2),
		BackgroundColor3 = WHITE, BackgroundTransparency = 0.75, BorderSizePixel = 0, ZIndex = Z.Chrome },
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
		Text = "^", TextSize = 16, TextColor3 = DIM, TextTransparency = 0.2,
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = Z.Chrome })

	-- header: what this is, and how much of it you are looking at
	ui.collectionTitle = textLabel({ Parent = drawer, Position = UDim2.new(0, 20, 0, 17),
		Size = UDim2.new(0.6, 0, 0, 22), Text = "COLLECTION", TextSize = 19,
		ZIndex = Z.Chrome })
	textOutline(ui.collectionTitle).Parent = ui.collectionTitle

	-- ATTACK | SUPPORT lives HERE now: it chooses what the collection shows.
	-- A white pill slides under the chosen half; no row colours.
	do
		local toggle = new("Frame", { Parent = drawer, Name = "ModeToggle", Position = UDim2.new(0, 168, 0, 11),
			Size = UDim2.fromOffset(212, 34), BackgroundColor3 = BLACK, BackgroundTransparency = 0.55,
			ZIndex = Z.Controls }, { round(), stroke(WHITE, 1, 0.9) })
		local pill = new("Frame", { Parent = toggle, Name = "Pill", Position = UDim2.new(0, 3, 0, 3),
			Size = UDim2.new(0.5, -3, 1, -6), BackgroundColor3 = WHITE, BackgroundTransparency = 0.06,
			ZIndex = Z.Controls + 1 }, { round() })
		ui.modeToggle = { pill = pill, segs = {} }
		for order, kind in ipairs({ "attack", "support" }) do
			local seg = new("TextButton", { Parent = toggle, Name = kind, Text = "", AutoButtonColor = false,
				BackgroundTransparency = 1, Position = UDim2.fromScale((order - 1) * 0.5, 0),
				Size = UDim2.fromScale(0.5, 1), ZIndex = Z.Controls + 2 })
			local label = textLabel({ Parent = seg, Size = UDim2.fromScale(1, 1), Text = string.upper(kind),
				TextSize = 14, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = Z.Controls + 3 })
			ui.modeToggle.segs[kind] = label
			Sfx.bindButton(seg)
			seg.MouseEnter:Connect(function()
				if slotType() ~= kind then label.TextColor3 = TEXT end
			end)
			seg.MouseLeave:Connect(function()
				if slotType() ~= kind then label.TextColor3 = MUTED end
			end)
			seg.Activated:Connect(function()
				local mode = (kind == "support") and "Support" or "Attack"
				if state.mode == mode then return end
				state.mode = mode
				pendingSlot = nil
				self:RefreshSlots()
				self:Refresh()
			end)
		end
	end

	ui.countLabel = textLabel({ Parent = drawer, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 20), Size = UDim2.new(0, 180, 0, 18),
		Text = "", TextSize = 13, TextColor3 = MUTED,
		TextXAlignment = Enum.TextXAlignment.Right, Visible = false, ZIndex = Z.Chrome })

	-- controls, on their own row and separated from the grid by a rule, so the
	-- top of the drawer reads as a toolbar rather than as more cards
	local bar = new("Frame", { Parent = drawer, Name = "Controls",
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 13), Size = UDim2.new(0, 552, 0, 30),
		BackgroundTransparency = 1, ZIndex = Z.Controls })

	ui.search = new("TextBox", { Parent = bar, Size = UDim2.new(0, 240, 1, 0),
		BackgroundColor3 = PANEL_2, BackgroundTransparency = 0.1, Text = "", PlaceholderText = "Search cards...",
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
		Position = UDim2.new(0, 20, 0, 56), Size = UDim2.new(1, -40, 0, 1),
		BackgroundColor3 = WHITE, BackgroundTransparency = 0.9,
		BorderSizePixel = 0, ZIndex = Z.Chrome })

	ui.gridLayout = new("UIGridLayout", {
		CellSize = UDim2.new(0, TILE_W, 0, math.floor(TILE_W * TILE_RATIO)),
		CellPadding = UDim2.new(0, DRAWER.CellGap, 0, DRAWER.CellGap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Left })

	ui.grid = new("ScrollingFrame", { Parent = drawer, Name = "Grid",
		Position = UDim2.new(0, 16, 0, DRAWER.ChromeHeight - 8),
		Size = UDim2.new(1, -32, 1, -DRAWER.ChromeHeight - 6),
		BackgroundColor3 = INK, BackgroundTransparency = 1, BorderSizePixel = 0,
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

	-- The E shortcut, taught where it is used: hover any card here and press E
	-- to drop another copy into the line-up.
	local keyHint = new("Frame", { Parent = drawer, Name = "KeyHint", AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -170, 0, 16), Size = UDim2.fromOffset(0, 22), Visible = false,
		AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, ZIndex = Z.Chrome },
		{ new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 7),
			SortOrder = Enum.SortOrder.LayoutOrder }) })
	local keycap = new("Frame", { Parent = keyHint, Name = "Key", LayoutOrder = 1,
		Size = UDim2.fromOffset(22, 22), BackgroundColor3 = FIELD, ZIndex = Z.Chrome },
		{ corner(6), stroke(DRAWER_LINE, 1, 0.1) })
	textLabel({ Parent = keycap, Size = UDim2.fromScale(1, 1), Text = "E", TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = Z.Chrome + 1 })
	textLabel({ Parent = keyHint, LayoutOrder = 2, Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X, Text = "ADD HOVERED CARD", TextSize = 12,
		TextColor3 = MUTED, ZIndex = Z.Chrome })

	-- A short confirmation under the header for hover + E: what went in, or
	-- why nothing could. On the screen itself, above the hover preview (95 >
	-- 90): the preview floats over exactly this spot whenever the cursor is on
	-- the drawer's top row, which is where E gets pressed most.
	ui.toast = new("Frame", { Parent = gui, Name = "Toast", Visible = false,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.03, 10 + HEADER_H + 16),
		Size = UDim2.fromOffset(0, 36), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Color3.fromRGB(18, 17, 30), BackgroundTransparency = 0.04, ZIndex = 95 },
		{ round(), new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 16) }),
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 9),
				SortOrder = Enum.SortOrder.LayoutOrder }) })
	ui.toastScale = new("UIScale", { Parent = ui.toast, Scale = 1 })
	ui.toastStroke = stroke(ACCENT_HI, 1.2, 0.3)
	ui.toastStroke.Parent = ui.toast
	ui.toastDot = new("Frame", { Parent = ui.toast, Name = "Dot", LayoutOrder = 1,
		Size = UDim2.fromOffset(8, 8), BackgroundColor3 = ACCENT_HI, ZIndex = Z.Toast + 1 }, { round() })
	ui.toastText = textLabel({ Parent = ui.toast, Name = "Text", LayoutOrder = 2,
		Size = UDim2.fromOffset(0, 36), AutomaticSize = Enum.AutomaticSize.X, Text = "",
		TextSize = 14, ZIndex = Z.Toast + 1 })
	textOutline(ui.toastText, 0.5).Parent = ui.toastText

	-- pop-out layer, above everything else on the screen
	ui.popout = new("Frame", { Parent = gui, Visible = false,
		BackgroundTransparency = 1, ZIndex = Z.Popout })
	ui.popoutCard = CardRenderer.create(ui.popout, CARD_REF_W, 60)
	ui.popoutCard.root.AnchorPoint = Vector2.new(0.5, 0.5)
	ui.popoutCard.root.Position = UDim2.fromScale(0.5, 0.5)
	ui.popoutScale = new("UIScale", { Parent = ui.popoutCard.root, Scale = 1 })

	-- Click-outside-to-close, but ONLY outside. The hover popout is a sibling
	-- layered above the window and is not itself active, so a click on it would
	-- still fall through to here; testing the pointer against the window's
	-- rectangle covers that and anything else added later.
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

	-- The chrome that fades up on open: header and tray dressing, never the
	-- cards (those are dealt in) or the drawer (it slides on its own).
	ui.chromeFade = Fade.new({ header, ui.trayChrome.attack, ui.trayChrome.support, ui.links })
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
	local fill = expanded and 0.04 or 0.35
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
		local dragging = drag ~= nil and drag.active
		local over = (not dragging) and contains(ui.drawer, p)

		-- Plus a forgiving band along the bottom of the deck body, so heading
		-- downwards opens the drawer before the cursor gets there. Nobody should
		-- have to land on one small card to see their collection.
		if not over and not dragging then
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
----------------------------------------------------------------------
-- drag and drop
----------------------------------------------------------------------

local function pointInside(gui: GuiObject, p: Vector2): boolean
	local at, size = gui.AbsolutePosition, gui.AbsoluteSize
	return p.X >= at.X and p.X <= at.X + size.X and p.Y >= at.Y and p.Y <= at.Y + size.Y
end

-- The slot under the dragged card: an empty one outlines and says DROP HERE,
-- a full one darkens and says REPLACE.
function DeckController:PaintDropTarget(view, on: boolean)
	if not view then return end
	if view.renderKey then
		view.removeTag.Visible = on
		if view.removeText then view.removeText.Text = on and "REPLACE" or "REMOVE" end
		tween(view.shade, { BackgroundTransparency = on and 0.45 or 1 }, 0.1)
	else
		view.socketStroke.Color = on and WHITE or LINE
		view.socketStroke.Thickness = on and 2.4 or 1.5
		view.socketStroke.Transparency = on and 0 or 0.35
		view.slotLabel.Text = on and "DROP HERE" or ("SLOT %d"):format(view.index)
		view.slotLabel.TextColor3 = on and WHITE or DIM
	end
	tween(view.pop, { Scale = on and 1.05 or 1 }, 0.14, on and BACK or QUAD)
end

-- While a card is in the air, every empty slot it could go into is outlined.
function DeckController:PaintDropZones(kind: string, on: boolean)
	for _, view in ipairs(slotViews[kind] or {}) do
		if not view.renderKey then
			view.socketStroke.Color = on and WHITE or LINE
			view.socketStroke.Transparency = on and 0.45 or 0.35
		end
	end
end

function DeckController:MoveDrag(p: Vector2)
	local d = drag
	if not d or not d.ghost then return end
	local origin = ui.screen.AbsolutePosition
	d.ghost.Position = UDim2.fromOffset(p.X - origin.X, p.Y - origin.Y)
	local target = nil
	for _, view in ipairs(slotViews[kindOf(d.item.cardId)] or {}) do
		if pointInside(view.frame, p) then target = view break end
	end
	if target ~= d.target then
		self:PaintDropTarget(d.target, false)
		d.target = target
		self:PaintDropTarget(target, true)
	end
end

function DeckController:StartDrag(p: Vector2)
	local d = drag
	if not d or d.active or not ui.screen then return end
	d.active = true
	self:HidePopout()
	pendingSlot = nil
	self:RefreshSlots()
	-- The drawer drops out of the way so every slot is in reach.
	self:SetDrawerExpanded(false)

	local w = math.max(70, d.tile.AbsoluteSize.X * 1.05)
	local ghost = new("Frame", { Parent = ui.screen, Name = "DragGhost", BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(w, w / CARD_ASPECT),
		Rotation = -6, ZIndex = Z.Popout + 2 })
	local card = CardRenderer.create(ghost, CARD_REF_W, Z.Popout + 3)
	card.root.AnchorPoint = Vector2.new(0.5, 0.5)
	card.root.Position = UDim2.fromScale(0.5, 0.5)
	new("UIScale", { Parent = card.root, Scale = w / CARD_REF_W })
	CardRenderer.update(card, { cardId = d.item.cardId, variant = d.item.variant, level = d.item.level })
	local lift = new("UIScale", { Parent = ghost, Scale = 0.85 })
	tween(lift, { Scale = 1 }, 0.16, BACK)
	d.ghost = ghost
	-- the card left behind in the collection fades back while it is away
	d.veil = new("Frame", { Parent = d.tile, Name = "DragVeil", Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = BLACK, BackgroundTransparency = 0.3, ZIndex = Z.Tile + 8 }, { corner(20) })
	self:PaintDropZones(kindOf(d.item.cardId), true)
	self:MoveDrag(p)
end

-- drop = true puts the card in the slot under it; false just cancels.
function DeckController:EndDrag(drop: boolean)
	local d = drag
	drag = nil
	if not d or not d.active then return end
	dragEndedAt = os.clock()
	if d.ghost then d.ghost:Destroy() end
	if d.veil then d.veil:Destroy() end
	local target = d.target
	self:PaintDropTarget(target, false)
	self:PaintDropZones(kindOf(d.item.cardId), false)
	if drop and target then
		pendingSlot = { slotType = target.kind, index = target.index }
		local ok, reason = self:AddCopy(d.item)
		if ok then
			local name = d.item.def and d.item.def.name or d.item.cardId
			self:Toast(("ADDED  \u{00B7}  %s"):format(string.upper(name)), TEXT)
		else
			pendingSlot = nil
			self:RefreshSlots()
			self:Toast(reason or "CANNOT ADD", BAD)
		end
	end
end

-- The world behind the deck: blurred, and the HUD put away so only the deck
-- shows through the veil.
function DeckController:SetBackdrop(on: boolean)
	local Lighting = game:GetService("Lighting")
	local blur = Lighting:FindFirstChild("DeckBlur")
	if on then
		if not blur then
			blur = Instance.new("BlurEffect")
			blur.Name = "DeckBlur"
			blur.Size = 0
			blur.Parent = Lighting
		end
		tween(blur, { Size = 12 }, 0.3)
		local hud = player:FindFirstChildOfClass("PlayerGui") and player.PlayerGui:FindFirstChild("CardClashHUD")
		if hud and hud:IsA("ScreenGui") and hud.Enabled then
			ui.hiddenHud = hud
			hud.Enabled = false
		end
	else
		if blur then blur:Destroy() end
		if ui.hiddenHud then
			ui.hiddenHud.Enabled = true
			ui.hiddenHud = nil
		end
	end
end

-- open / close

-- The Backpack's settled entrance: the dim fades up, the window grows the
-- last few percent into place, the chrome fades in, and the line-up is dealt.
-- What the open/close fades walk. NOT the whole collection: the grid can hold
-- hundreds of tiles and fading every one of them each frame is exactly the kind
-- of work that makes opening stutter. The drawer's own chrome plus the tiles
-- that can actually be on screen is all the eye ever sees.
local VISIBLE_TILES = 24
function DeckController:FadeRoots()
	local roots = { ui.header, ui.trayChrome.attack, ui.trayChrome.support, ui.links }
	for _, kind in ipairs({ "attack", "support" }) do
		for _, view in ipairs(slotViews[kind] or {}) do
			table.insert(roots, view.frame)
		end
	end
	for _, shade in ipairs(ui.drawerShades or {}) do
		table.insert(roots, shade.frame)
	end
	if ui.drawer then
		for _, child in ipairs(ui.drawer:GetChildren()) do
			if child ~= ui.grid and (child:IsA("GuiObject") or child:IsA("UIStroke")) then
				table.insert(roots, child)
			end
		end
		-- the drawer's own fill (not its children - those are listed above)
		table.insert(roots, { drawerSelf = true })
	end
	if ui.grid then
		local tiles = {}
		for _, child in ipairs(ui.grid:GetChildren()) do
			if child:IsA("GuiObject") then table.insert(tiles, child) end
		end
		table.sort(tiles, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
		for i = 1, math.min(#tiles, VISIBLE_TILES) do
			table.insert(roots, tiles[i])
		end
	end
	-- strip the marker: the drawer fill is tweened separately
	local out = {}
	for _, r in ipairs(roots) do
		if typeof(r) == "Instance" then table.insert(out, r) end
	end
	return out
end

function DeckController:PlayEntrance()
	if not ui.root then return end
	ui.closing = (ui.closing or 0) + 1

	-- The veil darkens, the world blurs (SetBackdrop), and EVERYTHING on top
	-- fades up together - header, both line-ups, the cards, the collection -
	-- while the whole screen settles from slightly small. Same timings as the
	-- Backpack: 0.26s fade, a 0.42s Quart settle, the header easing down.
	ui.dim.BackgroundTransparency = 1
	tween(ui.dim, { BackgroundTransparency = VEIL_T }, 0.3, QUAD)
	ui.rootScale.Scale = 0.94
	tween(ui.rootScale, { Scale = 1 }, 0.42, QUART)

	if ui.chromeFade then ui.chromeFade:stop(true) end
	ui.chromeFade = Fade.new(self:FadeRoots())
	ui.chromeFade:run(1, 0, 0.3)
	if ui.drawer then
		local rest = drawerExpanded and 0.04 or 0.35
		ui.drawer.BackgroundTransparency = 1
		tween(ui.drawer, { BackgroundTransparency = rest }, 0.3, QUAD)
	end

	-- small, settled movement rather than pops
	ui.header.Position = UDim2.fromOffset(0, -8)
	tween(ui.header, { Position = UDim2.fromOffset(0, 0) }, 0.34, QUART)
	if ui.drawer then
		ui.drawer.Position = UDim2.new(0.5, 0, 1, 18)
		tween(ui.drawer, { Position = UDim2.new(0.5, 0, 1, 0) }, 0.4, QUART)
	end
	for _, kind in ipairs({ "attack", "support" }) do
		for i, view in ipairs(slotViews[kind] or {}) do
			view.pop.Scale = 0.96
			task.delay((i - 1) * 0.025 + (kind == "support" and 0.05 or 0), function()
				tween(view.pop, { Scale = 1 }, 0.34, QUART)
			end)
		end
	end

	-- Once the fade has handed everything back: repaint (a sync may have landed
	-- mid-fade) and place the pair links on the settled layout.
	task.delay(0.42, function()
		if ui.screen and ui.screen.Enabled then
			self:RefreshSlots()
			self:UpdateLinks()
		end
	end)
end

function DeckController:Open()
	if not ui.screen then return end
	if ui.screen.Enabled and not ui.isClosing then return end
	ui.isClosing = false
	-- The leaderboard would peek out past the window's edge under the dim.
	LeaderboardVisibility.hide("Deck")
	-- Everything heavy happens BEFORE the screen shows: paint the line-up and make
	-- sure the collection exists. The entrance fade records every element's
	-- resting look when it starts, so it must start from the real state.
	if profile then
		self:RefreshSlots()
		self:EnsureCollection()
	end
	ui.screen.Enabled = true
	self:SetBackdrop(true)
	self:PlayEntrance()
end

function DeckController:Close()
	self:EndDrag(false)
	if not ui.screen or not ui.screen.Enabled or ui.isClosing then return end
	-- The pop-out is a separate ScreenGui layered above this one, so closing the
	-- deck has to take it down too or it is left floating over the world.
	CardActions.close()
	self:HidePopout()
	pendingSlot = nil
	hoveredItem, hoveredTile = nil, nil

	-- A quick fade out (the Backpack's 0.14s), then the screen goes away.
	ui.isClosing = true
	ui.closing = (ui.closing or 0) + 1
	local token = ui.closing
	if ui.chromeFade then ui.chromeFade:stop(true) end
	ui.chromeFade = Fade.new(self:FadeRoots())
	ui.chromeFade:run(0, 1, 0.14)
	if ui.drawer then tween(ui.drawer, { BackgroundTransparency = 1 }, 0.14, QUAD) end
	tween(ui.dim, { BackgroundTransparency = 1 }, 0.16, QUAD)
	tween(ui.rootScale, { Scale = 0.97 }, 0.16, QUAD)
	self:SetBackdrop(false)
	task.delay(0.17, function()
		if token ~= ui.closing then return end
		ui.isClosing = false
		if ui.chromeFade then ui.chromeFade:stop(true) end
		ui.chromeFade = nil
		if ui.screen then ui.screen.Enabled = false end
		LeaderboardVisibility.show("Deck")
		ui.rootScale.Scale = 1
		-- Reopening the deck should always start with the deck as the focus, so
		-- the drawer goes back down with no animation while nobody is looking.
		self:SetDrawerExpanded(false, true)
		if ui.drawer then ui.drawer.Position = UDim2.new(0.5, 0, 1, 0) end
	end)
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
		-- Predictions the server has now confirmed are dropped; the rest stay
		-- laid over this sync until it catches up or they time out.
		reconcilePredictions()
		-- The pop-out reads levels, essence counts and the line-up straight from
		-- here, so it is handed the new profile too.
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
		elseif inventoryChanged and ui.screen then
			-- Closed: build the collection in the background a moment later, so
			-- the next open has nothing heavy left to do.
			ui.prebuildToken = (ui.prebuildToken or 0) + 1
			local token = ui.prebuildToken
			task.delay(1.5, function()
				if token == ui.prebuildToken and ui.screen and not ui.screen.Enabled then
					self:EnsureCollection()
				end
			end)
		end
	end)

	ui.screen:GetPropertyChangedSignal("Enabled"):Connect(function()
		if ui.screen.Enabled then
			-- Any path that shows the screen must be able to populate it. The
			-- join-time sync can land before this controller connects, so ask
			-- for one if we still have nothing.
			if not profile then Remotes.RequestSync:FireServer() end
			self:RefreshSlots()
			self:EnsureCollection()
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not drag then return end
		local t = input.UserInputType
		if t ~= Enum.UserInputType.MouseMovement and t ~= Enum.UserInputType.Touch then return end
		local p = Vector2.new(input.Position.X, input.Position.Y)
		if not drag.active then
			if (p - drag.start).Magnitude >= DRAG_THRESHOLD then self:StartDrag(p) end
		else
			self:MoveDrag(p)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if not drag then return end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			self:EndDrag(true)
		end
	end)

	-- HOVER + E: another copy of the card under the cursor, straight into the
	-- next free slot, without opening anything. While the card pop-out is up it
	-- owns E instead (and does the same thing for its card).
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.E then return end
		if not (ui.screen and ui.screen.Enabled) then return end
		if CardActions.isOpen() then return end
		local item = hoveredItem
		if not item then return end
		local ok, reason = self:AddCopy(item)
		if ok then
			local name = item.def and item.def.name or item.cardId
			self:Toast(("ADDED  \u{00B7}  %s"):format(string.upper(name)), kindColour(kindOf(item.cardId)))
			self:PunchTile(hoveredTile)
		else
			self:Toast(reason or "CANNOT ADD", BAD)
		end
	end)
end

return DeckController
