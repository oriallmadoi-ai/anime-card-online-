--!nonstrict
-- Backpack presentation only. Quantities always come from the existing profile.
--
-- THE WINDOW
-- One contained panel instead of a full-screen overlay: a header (title,
-- search, item count, close), then three columns - categories, the item grid,
-- and an inspect panel for the selected item. The hierarchy reads left to
-- right, Categories -> Items -> Selected Item, and the selected item's art on
-- its pedestal is the most alive thing in the window.
--
-- WHAT DID NOT CHANGE
--   * Inventory.items() derives every entry and every quantity from the synced
--     profile (currency.elderCoins, books[id]) - nothing here stores a count.
--   * Tab filtering, the search match, and the rule that every defined essence
--     stays visible (x0 included) are the same as before.
--   * Tiles wear the same rarity border as the cards in the Deck: Shine's
--     neon falloff, drawn from each tier's VariantConfig border spec.
--   * MenuController still opens and closes the window. This module only
--     describes HOW it enters and leaves (openFrom / openTween / onOpen /
--     onClose on the record) - the open/close logic itself is untouched.
--
-- SUMMON CORES
-- A fourth tab, Cores, lists the Summon Cores the player holds (only owned
-- stages - 21 rows of x0 would bury everything else). A core in the inspect
-- panel gets an OPEN button: the server decides the card and SummonRoulette
-- plays it out. Upgrading lives at the Card Forge, not here. The forge's
-- materials (Elder Core Essence, Elder Wrench) sit in the same tab after the
-- cores, again only once held.
--
-- SIZING
-- Everything is authored in design pixels and one UIScale (the record's
-- `scale`, which MenuController also animates) fits the panel to the screen.
-- The panel's design size follows the screen's aspect within limits, and the
-- grid picks its column count from the width it is left with.
--
-- FADES
-- Roblox has no group opacity outside CanvasGroup, and a CanvasGroup the size
-- of this window can blank out entirely on low-memory clients. So fades are
-- done by walking a subtree once, remembering every transparency it rests at,
-- and driving them all from one value. A property that something else (a
-- hover tween) changed mid-fade is left alone when the fade hands back.
-- Effect layers from ItemStage are tagged NoFade and fade themselves from the
-- window's "PanelVisibility" attribute instead.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Format = require(ReplicatedStorage.Shared.Util.Format)
local ElderCoin = require(ReplicatedStorage.Shared.UI.ElderCoin)
local ElderEssence = require(ReplicatedStorage.Shared.UI.ElderEssence)
local BookDefinitions = require(ReplicatedStorage.Shared.Config.BookDefinitions)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
local MenuConfig = require(ReplicatedStorage.Shared.Config.MenuConfig)
local VfxAssets = require(ReplicatedStorage.Shared.Config.VfxAssets)
local Sweep = require(ReplicatedStorage.Shared.UI.Sweep)
local Shine = require(ReplicatedStorage.Shared.UI.Shine)
local TextShine = require(ReplicatedStorage.Shared.UI.TextShine)
local ItemStage = require(ReplicatedStorage.Shared.UI.ItemStage)
local SummonCoreConfig = require(ReplicatedStorage.Shared.Config.SummonCoreConfig)

local Inventory = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local TEXT = Color3.fromRGB(240, 242, 250)
local MUTED = Color3.fromRGB(156, 152, 182)
local DIM = Color3.fromRGB(110, 106, 138)
local INK = Color3.fromRGB(23, 26, 32)
local PANEL_TOP = Color3.fromRGB(27, 25, 40)
local PANEL_BOTTOM = Color3.fromRGB(11, 11, 17)
local RAISED = Color3.fromRGB(21, 20, 31)
local SUNK = Color3.fromRGB(13, 12, 20)
local FIELD = Color3.fromRGB(30, 28, 44)
local SLOT = Color3.fromRGB(28, 27, 40)
local SLOT_HOVER = Color3.fromRGB(40, 37, 58)
local LINE = Color3.fromRGB(66, 62, 96)
-- The Skill Tree's violet: purple is an ACCENT here, never a fill.
local ACCENT = Color3.fromRGB(150, 110, 255)
local ACCENT_HI = Color3.fromRGB(200, 176, 255)
local CLOSE_HOT = Color3.fromRGB(255, 112, 134)

local TABS = { "All", "Currency", "Essence", "Cores" }
local BACKPACK_ICON = MenuConfig.Menus.Backpack.IconImage

local QUART = Enum.EasingStyle.Quart
local QUAD = Enum.EasingStyle.Quad

----------------------------------------------------------------------
-- small builders
----------------------------------------------------------------------

local function new(className, props, children)
	local object = Instance.new(className)
	if object:IsA("GuiObject") then object.BorderSizePixel = 0 end
	for key, value in pairs(props or {}) do
		if key ~= "Parent" then object[key] = value end
	end
	for _, child in ipairs(children or {}) do child.Parent = object end
	if props and props.Parent then object.Parent = props.Parent end
	return object
end

local function corner(radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function round()
	return new("UICorner", { CornerRadius = UDim.new(1, 0) })
end

local function outline(color, transparency, thickness)
	return new("UIStroke", { Color = color, Thickness = thickness or 1, Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

local function text(parent, name, value, size, color, z)
	return new("TextLabel", { Parent = parent, Name = name, BackgroundTransparency = 1,
		Text = value, Font = Enum.Font.GothamMedium, TextSize = size, TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = z or 1 })
end

local function tween(object, properties, duration, style, direction)
	local motion = TweenService:Create(object, TweenInfo.new(duration or 0.14,
		style or QUAD, direction or Enum.EasingDirection.Out), properties)
	motion:Play()
	return motion
end

local function fadeEnds(peak)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, peak),
		NumberSequenceKeypoint.new(1, 1),
	})
end

-- A 1px line that fades out toward both ends.
local function hairline(parent, name, color, peak, props)
	local line = new("Frame", { Parent = parent, Name = name, BackgroundColor3 = color, ZIndex = 2 })
	for key, value in pairs(props or {}) do line[key] = value end
	new("UIGradient", { Parent = line, Transparency = fadeEnds(peak) })
	return line
end

local function vline(parent, name)
	local line = new("Frame", { Parent = parent, Name = name, BackgroundColor3 = WHITE, ZIndex = 2 })
	new("UIGradient", { Parent = line, Rotation = 90, Transparency = fadeEnds(0.9) })
	return line
end

local function diamond(parent, name, size, color, transparency, position, z)
	return new("Frame", { Parent = parent, Name = name, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position or UDim2.new(), Size = UDim2.fromOffset(size, size), Rotation = 45,
		BackgroundColor3 = color, BackgroundTransparency = transparency or 0, ZIndex = z or 3 })
end

local function cross(parent, length, thickness, color)
	local bars = {}
	for _, angle in ipairs({ -45, 45 }) do
		table.insert(bars, new("Frame", { Parent = parent, Name = "Cross", AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(length, thickness), Rotation = angle,
			BackgroundColor3 = color, ZIndex = (parent.ZIndex or 1) + 1 }, { round() }))
	end
	return bars
end

-- An L-shaped corner accent. `anchor` picks the corner, (0,0) = top-left.
local function bracket(parent, name, anchor, inset, arm, color, transparency, z)
	local box = new("Frame", { Parent = parent, Name = name, BackgroundTransparency = 1, AnchorPoint = anchor,
		Position = UDim2.new(anchor.X, anchor.X == 0 and inset or -inset, anchor.Y, anchor.Y == 0 and inset or -inset),
		Size = UDim2.fromOffset(arm, arm), ZIndex = z or 3 })
	new("Frame", { Parent = box, Name = "H", AnchorPoint = anchor, Position = UDim2.fromScale(anchor.X, anchor.Y),
		Size = UDim2.new(1, 0, 0, 1.5), BackgroundColor3 = color, BackgroundTransparency = transparency, ZIndex = z or 3 })
	new("Frame", { Parent = box, Name = "V", AnchorPoint = anchor, Position = UDim2.fromScale(anchor.X, anchor.Y),
		Size = UDim2.new(0, 1.5, 1, 0), BackgroundColor3 = color, BackgroundTransparency = transparency, ZIndex = z or 3 })
	return box
end

local function brackets(parent, inset, arm, color, transparency, z)
	for _, anchor in ipairs({ Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) }) do
		bracket(parent, "Bracket", anchor, inset, arm, color, transparency, z)
	end
end

----------------------------------------------------------------------
-- group fade (see FADES above)
----------------------------------------------------------------------

local FADE_PROPS = {
	Frame = { "BackgroundTransparency" },
	TextLabel = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" },
	TextButton = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" },
	TextBox = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" },
	ImageLabel = { "BackgroundTransparency", "ImageTransparency" },
	ImageButton = { "BackgroundTransparency", "ImageTransparency" },
	ViewportFrame = { "BackgroundTransparency", "ImageTransparency" },
	ScrollingFrame = { "BackgroundTransparency", "ScrollBarImageTransparency" },
	UIStroke = { "Transparency" },
}

local Fade = {}
Fade.__index = Fade

function Fade.new(root, excluded)
	return setmetatable({ root = root, excluded = excluded or {}, entries = nil, conn = nil }, Fade)
end

function Fade:capture()
	local list = {}
	local excluded = self.excluded
	local root = self.root
	local function walk(object)
		if object ~= root and (excluded[object] or object:GetAttribute("NoFade")) then return end
		local props = FADE_PROPS[object.ClassName]
		if props then
			for _, prop in ipairs(props) do
				local rest = object[prop]
				if rest < 0.999 then
					table.insert(list, { object, prop, rest, rest })
				end
			end
		end
		for _, child in ipairs(object:GetChildren()) do walk(child) end
	end
	walk(root)
	return list
end

-- a = 0 is fully at rest, a = 1 is fully transparent.
function Fade:apply(a)
	for _, e in ipairs(self.entries) do
		local object = e[1]
		if object.Parent then
			local value = e[3] + (1 - e[3]) * a
			object[e[2]] = value
			e[4] = value
		end
	end
end

function Fade:stop(restore)
	if self.conn then
		self.conn:Disconnect()
		self.conn = nil
	end
	if restore and self.entries then
		for _, e in ipairs(self.entries) do
			local object = e[1]
			-- Only hand back what nobody else has touched since we last wrote it.
			if object.Parent and math.abs(object[e[2]] - e[4]) < 0.002 then
				object[e[2]] = e[3]
			end
		end
		self.entries = nil
	end
end

function Fade:hold(a)
	self:stop(true)
	self.entries = self:capture()
	self:apply(a)
end

function Fade:play(from, to, duration, style, onStep, onDone)
	if self.conn then
		self.conn:Disconnect()
		self.conn = nil
	end
	if not self.entries then self.entries = self:capture() end
	local start = os.clock()
	self:apply(from)
	if onStep then onStep(from) end
	self.conn = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - start) / math.max(duration, 0.001), 0, 1)
		local k = TweenService:GetValue(t, style or QUAD, Enum.EasingDirection.Out)
		local a = from + (to - from) * k
		self:apply(a)
		if onStep then onStep(a) end
		if t >= 1 then
			if self.conn then
				self.conn:Disconnect()
				self.conn = nil
			end
			if to <= 0 then self:stop(true) end
			if onDone then onDone() end
		end
	end)
end

function Fade:run(from, to, duration, style, onStep, onDone)
	self:stop(true)
	self.entries = self:capture()
	self:play(from, to, duration, style, onStep, onDone)
end

----------------------------------------------------------------------
-- data
----------------------------------------------------------------------

local function quantity(profile, path)
	local value = profile
	for _, key in ipairs(path) do
		if type(value) ~= "table" then return 0 end
		value = value[key]
	end
	return math.max(0, math.floor(tonumber(value) or 0))
end

local function rarityName(variantId)
	local variant = VariantConfig.get(variantId)
	return string.upper(variant.display or variant.id or tostring(variantId))
end

-- Display descriptors, not another inventory. Essence IDs remain the saved book IDs.
function Inventory.items(profile)
	local coin = { id = "ElderCoin", name = "Elder Coin", category = "Currency", kind = "coin",
		variant = "Cosmic", detail = "Skill tree currency",
		quantity = quantity(profile, { "currency", "elderCoins" }),
		description = "The currency of the Skill Tree, paid out for every battle victory.",
		rows = { { "Type", "Currency" }, { "Used in", "Skill Tree" } },
		hint = "Open the Skill Tree to spend Elder Coins." }
	coin.art = function(parent, opts) return ItemStage.mount(parent, coin, opts) end
	local items = { coin }
	for _, id in ipairs(BookDefinitions.Order) do
		local def = BookDefinitions.get(id)
		if def then
			local effect = def.toMax and "Max level"
				or ("+%d %s"):format(def.levels, def.levels == 1 and "Level" or "Levels")
			local item = { id = id, name = def.name, category = "Essence", kind = "essence", tier = def.tier,
				variant = def.variant, quantity = quantity(profile, { "books", id }),
				detail = def.toMax and "To max level" or ("+%d %s"):format(def.levels, def.levels == 1 and "Level" or "Levels"),
				description = def.description,
				rows = { { "Type", "Essence  \u{00B7}  Tier " .. def.tier }, { "Effect", effect } },
				hint = "Open a card in your Deck to pour essence into it." }
			item.art = function(parent, opts) return ItemStage.mount(parent, item, opts) end
			table.insert(items, item)
		end
	end
	-- Summon Cores: only the stages actually held, lowest stage first.
	for _, entry in ipairs(SummonCoreConfig.owned(profile)) do
		local stage = entry.stage
		local boost = "\u{00D7}" .. SummonCoreConfig.formatBoost(stage.luck)
		local minimum = SummonCoreConfig.minimumRarity(stage.id,
			SummonCoreConfig.playerLuck(profile), profile and profile.encounters or {})
		local minimumText = SummonCoreConfig.formatBoost(minimum) .. "+"
		local item = { id = "Core_" .. stage.id, stageId = stage.id, name = stage.name, category = "Cores",
			kind = "core", typeLabel = "Summon Core", family = stage.family, level = stage.level,
			variant = stage.variant, tier = stage.numeral, quantity = entry.count,
			detail = "Minimum " .. minimumText .. " | Luck " .. boost,
			minimumRarity = minimum,
			description = ("Guaranteed %s final rarity. Includes card variants."):format(minimumText),
			rows = { { "Min. rarity", minimumText }, { "Luck Boost", boost },
				{ "Tier", ("%d of %d"):format(stage.index, SummonCoreConfig.MaxIndex) } },
			hint = "Minimum scales with your luck. Open here or upgrade at the Card Forge." }
		item.art = function(parent, opts) return ItemStage.mount(parent, item, opts) end
		table.insert(items, item)
	end
	-- Card Forge materials, after the cores they upgrade. Only what is held.
	for _, entry in ipairs(SummonCoreConfig.ownedItems(profile)) do
		local def = entry.item
		local item = { id = "ForgeItem_" .. def.id, itemId = def.id, name = def.name, category = "Cores",
			kind = "coreitem", typeLabel = "Forge Material", variant = def.variant, image = def.image,
			colour = def.colour, quantity = entry.count,
			detail = def.use,
			description = def.description,
			rows = { { "Used for", def.use }, { "Found in", def.source } },
			hint = "Spent at the Card Forge when you upgrade a Summon Core." }
		item.art = function(parent, opts) return ItemStage.mount(parent, item, opts) end
		table.insert(items, item)
	end
	return items
end

----------------------------------------------------------------------
-- item tile
----------------------------------------------------------------------

-- Kept public and backwards compatible: (parent, item, order, onHover) still
-- works; onHover is called as onHover(hovered, item, button) like the old
-- tooltip callback. onSelect(itemId), gate (the window) and width (the tile's
-- design width, which sizes its border) are new.
function Inventory.CreateInventorySlot(parent, item, order, onHover, onSelect, gate, width)
	local variant = VariantConfig.get(item.variant)
	if not width then
		local gridLayout = parent and parent:FindFirstChildOfClass("UIGridLayout")
		width = gridLayout and gridLayout.CellSize.X.Offset > 0 and gridLayout.CellSize.X.Offset or 120
	end
	local cell = new("Frame", { Parent = parent, Name = item.id, LayoutOrder = order,
		BackgroundTransparency = 1, ZIndex = 1 })
	local glow = new("ImageLabel", { Parent = cell, Name = "SelectGlow", BackgroundTransparency = 1,
		Image = VfxAssets.Glow, ImageColor3 = variant.color, ImageTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.24, 1.24), ZIndex = 1 })
	local lift = new("Frame", { Parent = cell, Name = "Lift", BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1), ZIndex = 2 })
	local appearScale = new("UIScale", { Parent = lift, Name = "AppearScale", Scale = 1 })

	-- The tile. Its thin tier-coloured outline is only a fallback now: Shine
	-- parks it and draws the border the cards in the Deck wear - the same
	-- neon falloff from the same VariantConfig spec, rotating palette and all.
	local button = new("TextButton", { Parent = lift, Name = "Slot", Text = "", AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = SLOT, BackgroundTransparency = 0.04, ZIndex = 1 },
		{ corner(12), outline(variant.color, 0.28) })
	button:SetAttribute("ItemId", item.id)
	button:SetAttribute("Category", item.category)
	local border = button:FindFirstChildOfClass("UIStroke")
	Shine.apply(button, variant.id, width)
	-- Every stroke Shine drew, with the transparency it rests at, so hover and
	-- selection can brighten the border and hand it back exactly. The tile is
	-- a TextButton, where a stroke left on Contextual outlines its (empty) text
	-- instead of the tile, so each one is pinned to the border.
	local rim = {}
	for _, child in ipairs(button:GetChildren()) do
		if child:IsA("UIStroke") and child.Enabled and child:GetAttribute("BaseThickness") then
			child.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			table.insert(rim, { stroke = child, rest = child.Transparency, base = child.Name == "BaseStroke" })
		end
	end
	local interaction = new("UIScale", { Parent = button, Name = "InteractionScale", Scale = 1 })

	-- Depth inside the tile: a lit top, a whisper of the tier's colour behind
	-- the art, and a hairline inner rim so the tile reads as a raised slot.
	new("Frame", { Parent = button, Name = "Sheen", BackgroundColor3 = WHITE, Size = UDim2.fromScale(1, 0.55), ZIndex = 1 },
		{ corner(12), new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.93), NumberSequenceKeypoint.new(1, 1) }) }) })
	local innerGlow = new("ImageLabel", { Parent = button, Name = "RarityGlow", BackgroundTransparency = 1,
		Image = VfxAssets.Glow, ImageColor3 = variant.color, ImageTransparency = 0.86,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.56),
		Size = UDim2.fromScale(1.05, 1.05), ZIndex = 1 })
	new("Frame", { Parent = button, Name = "InnerRim", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -3, 1, -3), ZIndex = 2 },
		{ corner(11), new("UIStroke", { Color = WHITE, Transparency = 0.94, Thickness = 1 }) })

	local art = new("Frame", { Parent = button, Name = "Art", BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.54),
		Size = UDim2.fromScale(0.8, 0.8), ZIndex = 3 })
	local stage = ItemStage.mount(art, item, { size = "card", gate = gate, phase = (order * 0.173) % 1 })

	local count = new("TextLabel", { Parent = button, Name = "Quantity", AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(30, 20), BackgroundColor3 = WHITE,
		BackgroundTransparency = 0, Text = "", TextColor3 = INK, TextSize = 13, Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 }, { round() })
	if item.tier then
		new("TextLabel", { Parent = button, Name = "Tier", Position = UDim2.fromOffset(6, 6),
			Size = UDim2.fromOffset(28, 20), BackgroundColor3 = SUNK, BackgroundTransparency = 0.12,
			Text = item.tier, TextColor3 = variant.color, TextSize = 12, Font = Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 },
			{ corner(6), outline(variant.color, 0.62) })
	end
	-- A small rarity bar along the foot of the tile.
	new("Frame", { Parent = button, Name = "RarityBar", AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -5), Size = UDim2.new(0.44, 0, 0, 2), BackgroundColor3 = variant.color,
		BackgroundTransparency = 0.2, ZIndex = 6 }, { round(), new("UIGradient", { Transparency = fadeEnds(0) }) })
	-- The shared light that crosses every tile on one clock (see Sweep).
	Sweep.attach(button, { tint = variant.color, transparency = 0.9, width = 0.42, zIndex = 5 })

	local marker = diamond(cell, "SelectMarker", 7, variant.color, 1, UDim2.new(0.5, 0, 1, 11), 3)

	local hovered, selected, popping, token = false, false, false, 0
	local motions = {}
	local function play(key, object, props, duration, style)
		if motions[key] then motions[key]:Cancel() end
		motions[key] = tween(object, props, duration, style)
	end
	local function resting()
		return (selected or hovered) and 1.04 or 1
	end
	local function paint(duration)
		duration = duration or 0.14
		local lit = hovered or selected
		if not popping then play("scale", interaction, { Scale = resting() }, duration) end
		play("bg", button, { BackgroundColor3 = lit and SLOT_HOVER or SLOT }, duration)
		if #rim > 0 then
			-- Brighter, wider light on hover; brighter still while selected.
			local boost = selected and 1.45 or (hovered and 1.2 or 1)
			for i, entry in ipairs(rim) do
				local goal = entry.base and entry.rest * (selected and 0.6 or (hovered and 0.8 or 1))
					or 1 - math.min(1, (1 - entry.rest) * boost)
				play("rim" .. i, entry.stroke, { Transparency = goal }, duration)
			end
		elseif border then
			play("border", border, { Transparency = lit and 0 or 0.28, Thickness = selected and 2 or (hovered and 1.4 or 1) }, duration)
		end
		play("art", art, { Position = UDim2.new(0.5, 0, 0.54, lit and -3 or 0) }, duration + 0.04)
		play("glow", glow, { ImageTransparency = selected and 0.8 or (hovered and 0.93 or 1) }, 0.22)
		play("marker", marker, { BackgroundTransparency = selected and 0.05 or 1 }, 0.2)
		play("inner", innerGlow, { ImageTransparency = lit and 0.78 or 0.86 }, 0.22)
		stage:setBoost(lit and 1 or 0)
	end
	local function hover(value)
		if hovered == value then return end
		hovered = value
		paint()
		if onHover then onHover(value, item, button) end
	end
	button.MouseEnter:Connect(function() hover(true) end)
	button.MouseLeave:Connect(function() hover(false) end)
	button.SelectionGained:Connect(function() hover(true) end)
	button.SelectionLost:Connect(function() hover(false) end)
	button.MouseButton1Down:Connect(function()
		token += 1
		popping = false
		play("scale", interaction, { Scale = 0.95 }, 0.06)
	end)
	button.Activated:Connect(function()
		token += 1
		local current = token
		popping = true
		if onSelect then onSelect(item.id) end
		play("scale", interaction, { Scale = 0.95 }, 0.05)
		task.delay(0.05, function()
			if token ~= current or not button.Parent then return end
			play("scale", interaction, { Scale = 1.075 }, 0.09)
			task.delay(0.09, function()
				if token ~= current or not button.Parent then return end
				popping = false
				play("scale", interaction, { Scale = resting() }, 0.16)
			end)
		end)
	end)

	local function update(nextItem)
		item = nextItem
		button:SetAttribute("Quantity", item.quantity)
		local value = item.quantity < 10000 and tostring(item.quantity) or Format.short(item.quantity)
		count.Text = "x" .. value
		count.Size = UDim2.fromOffset(math.max(28, 12 + #count.Text * 8), 20)
		-- A quiet badge for "none yet", so owned stacks are the ones that pop.
		count.BackgroundTransparency = item.quantity > 0 and 0 or 0.35
		count.Visible = true
	end
	update(item)

	-- Entrance / exit, driven by the window.
	local fade = Fade.new(cell)
	local appearToken = 0
	local function appear(delay)
		appearToken += 1
		local mine = appearToken
		fade:hold(1)
		stage:setVisibility(0)
		appearScale.Scale = 0.86
		lift.Position = UDim2.new(0.5, 0, 0.5, 8)
		task.delay(delay or 0, function()
			if mine ~= appearToken or not lift.Parent then return end
			tween(appearScale, { Scale = 1 }, 0.28, QUART)
			tween(lift, { Position = UDim2.fromScale(0.5, 0.5) }, 0.28, QUART)
			fade:play(1, 0, 0.2, QUAD, function(a) stage:setVisibility(1 - a) end)
		end)
	end
	local function vanish(duration)
		appearToken += 1
		fade:run(0, 1, duration or 0.12, QUAD, function(a) stage:setVisibility(1 - a) end)
	end
	local function settle()
		appearToken += 1
		fade:stop(true)
		stage:setVisibility(1)
		appearScale.Scale = 1
		lift.Position = UDim2.fromScale(0.5, 0.5)
	end
	local function setSelected(value)
		if selected == value then return end
		selected = value
		paint(0.18)
	end

	-- A new column count means a new tile width; the border rescales with it.
	local function resize(size)
		Shine.apply(button, variant.id, size)
	end

	return { cell = cell, button = button, update = update, setSelected = setSelected,
		appear = appear, vanish = vanish, settle = settle, resize = resize, stage = stage }
end

----------------------------------------------------------------------
-- window
----------------------------------------------------------------------

function Inventory.createWindow(root, getProfile, onClose)
	local holder = new("Frame", { Parent = root, Name = "BackpackWindow", Visible = false,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(1280, 700), BackgroundTransparency = 1, Active = true, ZIndex = 82 })
	local scale = new("UIScale", { Parent = holder, Name = "WindowScale", Scale = 1 })
	holder:SetAttribute("PanelVisibility", 1)
	-- Clicks on the panel's empty areas must not fall through to MenuDim,
	-- which closes every menu. A Frame's Active does not stop the GuiButton
	-- underneath from firing; a button of our own, under everything else in
	-- the window, does.
	new("TextButton", { Parent = holder, Name = "InputBlocker", Text = "", AutoButtonColor = false,
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Selectable = false, ZIndex = 0 })

	-- Soft shadow and the faintest violet bloom, as stacked strokes - each
	-- one fills from the edge outward, so near the panel they all overlap and
	-- further out only the faint wide ones remain (same trick as Shine).
	local shadow = new("Frame", { Parent = holder, Name = "Shadow", BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1), ZIndex = 1 }, { corner(18) })
	for i, spec in ipairs({ { 3, 0.8 }, { 7, 0.88 }, { 12, 0.93 }, { 18, 0.96 }, { 26, 0.978 } }) do
		new("UIStroke", { Parent = shadow, Name = "Shade" .. i, Color = BLACK, Thickness = spec[1],
			Transparency = spec[2], LineJoinMode = Enum.LineJoinMode.Round })
	end
	new("UIStroke", { Parent = shadow, Name = "Bloom", Color = ACCENT, Thickness = 5, Transparency = 0.93,
		LineJoinMode = Enum.LineJoinMode.Round })

	-- The panel: dark charcoal, lit from above, barely see-through.
	local panel = new("Frame", { Parent = holder, Name = "Panel", BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.06, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, {
		corner(18),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(PANEL_TOP, PANEL_BOTTOM) }),
	})
	local rim = new("UIStroke", { Parent = panel, Name = "Rim", Color = WHITE, Thickness = 1.2, Transparency = 0.25 })
	new("UIGradient", { Parent = rim, Rotation = 90, Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, ACCENT_HI:Lerp(LINE, 0.35)),
		ColorSequenceKeypoint.new(0.45, LINE),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(34, 32, 50)),
	}) })
	new("Frame", { Parent = panel, Name = "InnerRim", BackgroundTransparency = 1, Position = UDim2.fromOffset(1, 1),
		Size = UDim2.new(1, -2, 1, -2), ZIndex = 1 }, { corner(17), new("UIStroke", { Color = WHITE, Transparency = 0.95 }) })
	new("Frame", { Parent = panel, Name = "TopSheen", BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 0, 120), ZIndex = 1 },
		{ corner(18), new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.955), NumberSequenceKeypoint.new(1, 1) }) }) })
	hairline(panel, "TopLight", ACCENT_HI, 0.3, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0.62, 0, 0, 1) })
	brackets(panel, 10, 14, ACCENT_HI, 0.62, 3)

	------------------------------------------------------------------
	-- header
	------------------------------------------------------------------
	local header = new("Frame", { Parent = panel, Name = "Header", BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 66), ZIndex = 4 })
	local badge = new("Frame", { Parent = header, Name = "IconBadge", BackgroundColor3 = WHITE,
		Position = UDim2.fromOffset(24, 13), Size = UDim2.fromOffset(40, 40), ZIndex = 1 }, {
		corner(11),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(ACCENT:Lerp(PANEL_TOP, 0.52), PANEL_BOTTOM:Lerp(ACCENT, 0.1)) }),
		outline(ACCENT, 0.45),
	})
	new("ImageLabel", { Parent = badge, Name = "Icon", BackgroundTransparency = 1, Image = BACKPACK_ICON,
		ScaleType = Enum.ScaleType.Fit, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.76, 0.76), ZIndex = 2 })
	local title = text(header, "Title", "BACKPACK", 26, TEXT, 2)
	title.Position = UDim2.fromOffset(76, 10)
	title.Size = UDim2.fromOffset(260, 30)
	new("UIStroke", { Parent = title, Thickness = 1.4, Color = BLACK, Transparency = 0.45 })
	local sub = text(header, "SectionLabel", "INVENTORY", 12, DIM, 2)
	sub.Position = UDim2.fromOffset(77, 39)
	sub.Size = UDim2.fromOffset(200, 14)

	-- Search. Smaller than before and centred, with its own clear button.
	local searchBar = new("Frame", { Parent = header, Name = "SearchBar", BackgroundColor3 = FIELD,
		BackgroundTransparency = 0.08, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 34),
		Size = UDim2.fromOffset(340, 38), ZIndex = 2 }, { corner(10) })
	local searchStroke = outline(LINE, 0.3)
	searchStroke.Parent = searchBar
	local searchGlow = new("UIStroke", { Parent = searchBar, Name = "FocusGlow", Color = ACCENT, Thickness = 4,
		Transparency = 1, LineJoinMode = Enum.LineJoinMode.Round })
	local lens = new("Frame", { Parent = searchBar, Name = "SearchIcon", BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, -1), Size = UDim2.fromOffset(12, 12), ZIndex = 3 },
		{ round(), outline(MUTED, 0.1, 1.6) })
	new("Frame", { Parent = lens, Name = "Handle", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, 1, 1, 1),
		Size = UDim2.fromOffset(6, 2), Rotation = 45, BackgroundColor3 = MUTED, ZIndex = 3 }, { round() })
	local search = new("TextBox", { Parent = searchBar, Name = "Search", Text = "", ClearTextOnFocus = false,
		PlaceholderText = "Search items...", PlaceholderColor3 = DIM, TextColor3 = TEXT, Font = Enum.Font.GothamMedium,
		TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
		Position = UDim2.fromOffset(36, 0), Size = UDim2.new(1, -70, 1, 0), ClipsDescendants = true, ZIndex = 3 })
	local clear = new("TextButton", { Parent = searchBar, Name = "Clear", Text = "", AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = Color3.fromRGB(54, 50, 76), BackgroundTransparency = 0.15, Visible = false, ZIndex = 3 }, { round() })
	cross(clear, 9, 1.6, MUTED)
	clear.Activated:Connect(function() search.Text = "" end)
	search.Focused:Connect(function()
		tween(searchStroke, { Color = ACCENT, Transparency = 0.1 })
		tween(searchGlow, { Transparency = 0.82 })
		tween(searchBar, { BackgroundColor3 = FIELD:Lerp(ACCENT, 0.06) })
	end)
	search.FocusLost:Connect(function()
		tween(searchStroke, { Color = LINE, Transparency = 0.3 })
		tween(searchGlow, { Transparency = 1 })
		tween(searchBar, { BackgroundColor3 = FIELD })
	end)

	local close = new("TextButton", { Parent = header, Name = "Close", Text = "", AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -24, 0, 34), Size = UDim2.fromOffset(38, 38),
		BackgroundColor3 = Color3.fromRGB(34, 31, 48), BackgroundTransparency = 0.08, ZIndex = 2 }, { corner(10) })
	local closeStroke = outline(LINE, 0.3)
	closeStroke.Parent = close
	cross(close, 15, 2, TEXT)
	local closeScale = new("UIScale", { Parent = close, Name = "InteractionScale", Scale = 1 })
	local closeOver = false
	local function paintClose()
		tween(close, { BackgroundColor3 = closeOver and Color3.fromRGB(78, 32, 50) or Color3.fromRGB(34, 31, 48) })
		tween(closeStroke, { Color = closeOver and CLOSE_HOT or LINE, Transparency = closeOver and 0.1 or 0.3 })
		tween(closeScale, { Scale = closeOver and 1.06 or 1 }, 0.12)
	end
	close.MouseEnter:Connect(function() closeOver = true; paintClose() end)
	close.MouseLeave:Connect(function() closeOver = false; paintClose() end)
	close.SelectionGained:Connect(function() closeOver = true; paintClose() end)
	close.SelectionLost:Connect(function() closeOver = false; paintClose() end)
	close.MouseButton1Down:Connect(function() tween(closeScale, { Scale = 0.92 }, 0.06) end)
	close.Activated:Connect(onClose)

	local countPill = new("Frame", { Parent = header, Name = "ItemCount", AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -74, 0, 34), Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = FIELD, BackgroundTransparency = 0.2, ZIndex = 2 },
		{ round(), new("UIPadding", { PaddingLeft = UDim.new(0, 24), PaddingRight = UDim.new(0, 12) }) })
	diamond(countPill, "Tip", 5, ACCENT_HI, 0.2, UDim2.new(0, -12, 0.5, 0), 3)
	local countText = text(countPill, "Text", "0 Items", 13, MUTED, 3)
	countText.AutomaticSize = Enum.AutomaticSize.X
	countText.Size = UDim2.fromOffset(0, 26)

	hairline(panel, "HeaderDivider", ACCENT_HI, 0.62, { Position = UDim2.fromOffset(24, 66),
		Size = UDim2.new(1, -48, 0, 1) })
	diamond(panel, "DividerTipL", 5, ACCENT_HI, 0.45, UDim2.fromOffset(24, 66.5), 3)
	diamond(panel, "DividerTipR", 5, ACCENT_HI, 0.45, UDim2.new(1, -24, 0, 66.5), 3)

	------------------------------------------------------------------
	-- category sidebar
	------------------------------------------------------------------
	local sidebar = new("Frame", { Parent = panel, Name = "Sidebar", BackgroundTransparency = 1, ZIndex = 4 })
	-- The first tab lines up with the top of the first row of item tiles.
	local TAB_H, TAB_GAP, TAB_TOP = 46, 6, 38
	local tabList = new("Frame", { Parent = sidebar, Name = "Tabs", BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, TAB_TOP), Size = UDim2.new(1, 0, 0, #TABS * TAB_H + (#TABS - 1) * TAB_GAP), ZIndex = 2 },
		{ new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, TAB_GAP),
			SortOrder = Enum.SortOrder.LayoutOrder }) })
	-- One indicator that slides between tabs, rather than one per tab.
	local indicator = new("Frame", { Parent = sidebar, Name = "ActiveIndicator", BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromOffset(0, TAB_TOP + TAB_H / 2),
		Size = UDim2.fromOffset(3, 22), ZIndex = 5 })
	new("ImageLabel", { Parent = indicator, Name = "Glow", BackgroundTransparency = 1, Image = VfxAssets.Glow,
		ImageColor3 = ACCENT, ImageTransparency = 0.4, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(30, 48), ZIndex = 1 })
	new("Frame", { Parent = indicator, Name = "Bar", BackgroundColor3 = ACCENT_HI, Size = UDim2.fromScale(1, 1), ZIndex = 2 },
		{ round() })

	------------------------------------------------------------------
	-- item grid
	------------------------------------------------------------------
	local itemsCol = new("Frame", { Parent = panel, Name = "Items", BackgroundTransparency = 1, ZIndex = 4 })
	local heading = new("Frame", { Parent = itemsCol, Name = "Heading", BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 20), ZIndex = 3 },
		{ new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8),
			VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }) })
	local tipBox = new("Frame", { Parent = heading, Name = "TipBox", BackgroundTransparency = 1, LayoutOrder = 1,
		Size = UDim2.fromOffset(10, 20), ZIndex = 3 })
	diamond(tipBox, "Tip", 5, ACCENT, 0.2, UDim2.fromScale(0.5, 0.5), 3)
	local itemsLabel = text(heading, "ItemsLabel", "ITEMS", 13, TEXT, 3)
	itemsLabel.LayoutOrder = 2
	itemsLabel.AutomaticSize = Enum.AutomaticSize.X
	itemsLabel.Size = UDim2.fromOffset(0, 20)
	local shownLabel = text(heading, "Shown", "0 / 0", 13, DIM, 3)
	shownLabel.LayoutOrder = 3
	shownLabel.AutomaticSize = Enum.AutomaticSize.X
	shownLabel.Size = UDim2.fromOffset(0, 20)

	local content = new("ScrollingFrame", { Parent = itemsCol, Name = "Content", BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 1, -28), ScrollBarThickness = 3,
		ScrollBarImageColor3 = ACCENT, ScrollBarImageTransparency = 0.4,
		ScrollingDirection = Enum.ScrollingDirection.Y, ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 2 },
		-- Room around the grid for the tiles' border glow, which the scroller clips.
		{ new("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 24),
			PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }) })
	local grid = new("UIGridLayout", { Parent = content, CellSize = UDim2.fromOffset(120, 120),
		CellPadding = UDim2.fromOffset(14, 22), SortOrder = Enum.SortOrder.LayoutOrder })

	local empty = new("Frame", { Parent = itemsCol, Name = "Empty", BackgroundTransparency = 1, Visible = false,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 96), Size = UDim2.fromOffset(320, 120), ZIndex = 5 })
	local bigLens = new("Frame", { Parent = empty, Name = "Lens", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, -3, 0, 0), Size = UDim2.fromOffset(30, 30), ZIndex = 5 }, { round(), outline(DIM, 0.2, 2.5) })
	new("Frame", { Parent = bigLens, Name = "Handle", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, 3, 1, 3),
		Size = UDim2.fromOffset(13, 3), Rotation = 45, BackgroundColor3 = DIM, ZIndex = 5 }, { round() })
	local emptyTitle = text(empty, "Title", "No matching items", 17, TEXT, 5)
	emptyTitle.Position = UDim2.fromOffset(0, 46)
	emptyTitle.Size = UDim2.new(1, 0, 0, 22)
	emptyTitle.TextXAlignment = Enum.TextXAlignment.Center
	local emptyHint = text(empty, "Hint", "Try another search or category.", 13, DIM, 5)
	emptyHint.Position = UDim2.fromOffset(0, 72)
	emptyHint.Size = UDim2.new(1, 0, 0, 18)
	emptyHint.TextXAlignment = Enum.TextXAlignment.Center

	local separatorA = vline(panel, "SeparatorA")
	local separatorB = vline(panel, "SeparatorB")

	------------------------------------------------------------------
	-- inspect panel
	------------------------------------------------------------------
	local details = new("Frame", { Parent = panel, Name = "Details", BackgroundColor3 = RAISED,
		BackgroundTransparency = 0.22, ZIndex = 4 }, { corner(16) })
	new("UIStroke", { Parent = details, Color = WHITE, Transparency = 0.92, Thickness = 1 })
	local accentLine = hairline(details, "AccentLine", ACCENT, 0.25, { AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0.6, 0, 0, 1), ZIndex = 6 })

	local stage = new("Frame", { Parent = details, Name = "Stage", BackgroundColor3 = WHITE, BackgroundTransparency = 0.02,
		Position = UDim2.fromOffset(14, 14), Size = UDim2.new(1, -28, 0, 260), ClipsDescendants = true, ZIndex = 2 }, {
		corner(12),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(34, 28, 56), Color3.fromRGB(12, 11, 19)) }),
	})
	new("UIStroke", { Parent = stage, Color = WHITE, Transparency = 0.92, Thickness = 1 })
	local pedestal = ItemStage.platform(stage, { gate = holder, zIndex = 1, color = ACCENT })
	brackets(stage, 8, 12, ACCENT_HI, 0.55, 6)
	local previewSlot = new("Frame", { Parent = stage, Name = "Preview", BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromScale(0.74, 0.74), ZIndex = 4 },
		{ new("UIAspectRatioConstraint", { AspectRatio = 1 }) })
	local popScale = new("UIScale", { Parent = previewSlot, Name = "PopScale", Scale = 1 })

	local info = new("ScrollingFrame", { Parent = details, Name = "Info", BackgroundTransparency = 1,
		ScrollBarThickness = 2, ScrollBarImageColor3 = ACCENT, ScrollBarImageTransparency = 0.5,
		ScrollingDirection = Enum.ScrollingDirection.Y, AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(), ZIndex = 3 },
		{ new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
			new("UIPadding", { PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 2) }) })
	local nameLabel = text(info, "ItemName", "", 24, TEXT, 3)
	nameLabel.LayoutOrder = 1
	nameLabel.Size = UDim2.new(1, 0, 0, 30)
	nameLabel.TextScaled = true
	new("UITextSizeConstraint", { Parent = nameLabel, MaxTextSize = 24, MinTextSize = 14 })
	new("UIStroke", { Parent = nameLabel, Color = BLACK, Thickness = 1.2, Transparency = 0.5 })
	local rarityRow = new("Frame", { Parent = info, Name = "RarityRow", BackgroundTransparency = 1, LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 18), ZIndex = 3 },
		{ new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8),
			VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }) })
	local rarityLabel = text(rarityRow, "Rarity", "", 14, TEXT, 3)
	rarityLabel.LayoutOrder = 1
	rarityLabel.AutomaticSize = Enum.AutomaticSize.X
	rarityLabel.Size = UDim2.fromOffset(0, 18)
	new("Frame", { Parent = rarityRow, Name = "Dot", LayoutOrder = 2, Size = UDim2.fromOffset(4, 4),
		BackgroundColor3 = DIM, ZIndex = 3 }, { round() })
	local typeLabel = text(rarityRow, "Category", "", 13, MUTED, 3)
	typeLabel.LayoutOrder = 3
	typeLabel.AutomaticSize = Enum.AutomaticSize.X
	typeLabel.Size = UDim2.fromOffset(0, 18)
	local dividerWrap = new("Frame", { Parent = info, Name = "Divider", BackgroundTransparency = 1, LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 9), ZIndex = 3 })
	local detailDivider = new("Frame", { Parent = dividerWrap, Name = "Line", BackgroundColor3 = ACCENT,
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 1), ZIndex = 3 },
		{ new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(0.65, 0.85), NumberSequenceKeypoint.new(1, 1) }) }) })
	local descLabel = text(info, "Description", "", 14, MUTED, 3)
	descLabel.LayoutOrder = 4
	descLabel.Size = UDim2.new(1, 0, 0, 0)
	descLabel.AutomaticSize = Enum.AutomaticSize.Y
	descLabel.TextWrapped = true
	descLabel.TextYAlignment = Enum.TextYAlignment.Top
	local stats = new("Frame", { Parent = info, Name = "Stats", BackgroundColor3 = SUNK, BackgroundTransparency = 0.3,
		LayoutOrder = 5, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 3 },
		{ corner(10), new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
			PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2) }),
			new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }) })
	new("UIStroke", { Parent = stats, Color = WHITE, Transparency = 0.94 })
	local statRows = {}
	for i = 1, 4 do
		local row = new("Frame", { Parent = stats, Name = "Row" .. i, BackgroundTransparency = 1, LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, 30), ZIndex = 4 })
		local key = text(row, "Label", "", 13, MUTED, 5)
		key.Size = UDim2.new(0.42, 0, 1, 0)
		local value = text(row, "Value", "", 14, TEXT, 5)
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.fromScale(1, 0)
		value.Size = UDim2.new(0.58, 0, 1, 0)
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.TextScaled = true
		new("UITextSizeConstraint", { Parent = value, MaxTextSize = 14, MinTextSize = 10 })
		local line = new("Frame", { Parent = row, Name = "Line", BackgroundColor3 = WHITE, BackgroundTransparency = 0.93,
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1),
			Visible = i < 3, ZIndex = 5 })
		statRows[i] = { row = row, key = key, value = value, line = line }
	end

	local hint = new("Frame", { Parent = details, Name = "Hint", BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -12), Size = UDim2.new(1, -32, 0, 32), ZIndex = 3 })
	diamond(hint, "Tip", 5, ACCENT, 0.3, UDim2.fromOffset(3, 8), 4)
	local hintText = text(hint, "Text", "", 12, DIM, 4)
	hintText.Position = UDim2.fromOffset(14, 0)
	hintText.Size = UDim2.new(1, -14, 1, 0)
	hintText.TextWrapped = true
	hintText.TextYAlignment = Enum.TextYAlignment.Top

	local placeholder = new("Frame", { Parent = details, Name = "Placeholder", BackgroundTransparency = 1,
		Visible = false, ZIndex = 5 })
	diamond(placeholder, "Mark", 10, ACCENT_HI, 0.55, UDim2.new(0.5, 0, 0, 12), 6)
	local placeholderText = text(placeholder, "Text", "Select an item to view details", 14, MUTED, 6)
	placeholderText.Position = UDim2.fromOffset(0, 30)
	placeholderText.Size = UDim2.new(1, 0, 0, 40)
	placeholderText.TextWrapped = true
	placeholderText.TextXAlignment = Enum.TextXAlignment.Center
	placeholderText.TextYAlignment = Enum.TextYAlignment.Top

	------------------------------------------------------------------
	-- state
	------------------------------------------------------------------
	local record = { name = "Backpack", holder = holder, scale = scale, content = content,
		tabButtons = {}, selectedTab = "All", baseScale = 1, motion = nil, transition = 0,
		-- How MenuController should bring this window in: a short, settled
		-- scale-in rather than the overshoot the other panels use.
		openFrom = 0.97,
		openTween = TweenInfo.new(0.3, QUART, Enum.EasingDirection.Out) }
	local slots, itemsById = {}, {}
	local selectedId = nil
	local shownItem = nil
	local previewHandle = nil
	local layoutState = { sidebar = UDim2.new(), details = UDim2.new(), infoTop = 302 }

	------------------------------------------------------------------
	-- item action: OPEN (Summon Cores only)
	------------------------------------------------------------------
	-- The server decides the card; SummonRoulette plays it out full-screen
	-- over this window. Hidden for every other item, and the info column
	-- takes its room back.
	local ACTION_H = 46
	local action = new("Frame", { Parent = details, Name = "Action", BackgroundTransparency = 1, Visible = false,
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -54), Size = UDim2.new(1, -32, 0, ACTION_H), ZIndex = 4 })
	local openButton = new("TextButton", { Parent = action, Name = "OpenCore", Text = "", AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE, ZIndex = 1 }, { corner(11) })
	new("UIGradient", { Parent = openButton, Rotation = 90,
		Color = ColorSequence.new(ACCENT:Lerp(WHITE, 0.1), ACCENT:Lerp(BLACK, 0.42)) })
	local openStroke = outline(ACCENT_HI, 0.3, 1.2)
	openStroke.Parent = openButton
	local openGlow = new("UIStroke", { Parent = openButton, Name = "Glow", Color = ACCENT, Thickness = 5, Transparency = 0.86,
		LineJoinMode = Enum.LineJoinMode.Round, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	local openScale = new("UIScale", { Parent = openButton, Name = "InteractionScale", Scale = 1 })
	local openCaption = text(openButton, "Caption", "OPEN CORE", 17, WHITE, 3)
	openCaption.Font = Enum.Font.GothamBold
	openCaption.AnchorPoint = Vector2.new(0.5, 0.5)
	openCaption.Position = UDim2.fromScale(0.5, 0.5)
	openCaption.Size = UDim2.new(1, -20, 1, 0)
	openCaption.TextXAlignment = Enum.TextXAlignment.Center
	new("UIStroke", { Parent = openCaption, Color = BLACK, Thickness = 1.2, Transparency = 0.55 })
	Sweep.attach(openButton, { tint = WHITE, transparency = 0.84, width = 0.34, zIndex = 2 })

	local openOver, opening = false, false
	local function paintOpen()
		tween(openScale, { Scale = opening and 0.98 or (openOver and 1.025 or 1) }, 0.12)
		tween(openStroke, { Transparency = (openOver and not opening) and 0.05 or 0.3 }, 0.12)
		tween(openGlow, { Transparency = (openOver and not opening) and 0.72 or 0.86 }, 0.16)
		openCaption.Text = opening and "OPENING\u{2026}" or "OPEN CORE"
		openCaption.TextTransparency = opening and 0.35 or 0
	end
	openButton.MouseEnter:Connect(function() openOver = true; paintOpen() end)
	openButton.MouseLeave:Connect(function() openOver = false; paintOpen() end)
	openButton.SelectionGained:Connect(function() openOver = true; paintOpen() end)
	openButton.SelectionLost:Connect(function() openOver = false; paintOpen() end)
	openButton.MouseButton1Down:Connect(function()
		if not opening then tween(openScale, { Scale = 0.96 }, 0.06) end
	end)
	openButton.Activated:Connect(function()
		local item = shownItem
		if opening or not item or item.kind ~= "core" or (item.quantity or 0) < 1 then return end
		opening = true
		paintOpen()
		task.spawn(function()
			-- Required on first use so the Backpack never waits on the
			-- network module at startup.
			local module = ReplicatedStorage.Shared.UI:FindFirstChild("SummonRoulette")
			local loaded, Roulette = false, nil
			if module then loaded, Roulette = pcall(require, module) end
			if loaded and Roulette then
				local ran, err = pcall(Roulette.open, item.stageId)
				if not ran then warn("[Backpack] opening a core failed: " .. tostring(err)) end
			else
				warn("[Backpack] SummonRoulette unavailable: " .. tostring(Roulette))
			end
			opening = false
			if openButton.Parent then paintOpen() end
		end)
	end)

	local function sizeInfo()
		-- Cores need room for the guarantee and Open button. Keep their art
		-- slightly smaller so all four detail rows fit at ordinary screen sizes.
		local bodyH = details.Size.Y.Offset
		if bodyH > 0 then
			local stageH = if action.Visible
				then math.clamp(math.floor(bodyH * 0.30), 120, 180)
				else math.clamp(math.floor(bodyH * 0.45), 160, 280)
			stage.Size = UDim2.new(1, -28, 0, stageH)
			layoutState.infoTop = 28 + stageH
			info.Position = UDim2.fromOffset(16, layoutState.infoTop)
			placeholder.Position = UDim2.fromOffset(16, layoutState.infoTop + 18)
		end
		local reserve = action.Visible and (ACTION_H + 10) or 0
		info.Size = UDim2.new(1, -26, 1, -layoutState.infoTop - 52 - reserve)
	end

	local function setAction(item)
		local isCore = item ~= nil and item.kind == "core"
		action.Visible = isCore
		if isCore then
			local family = SummonCoreConfig.Families[item.family]
			openStroke.Color = family and family.colour:Lerp(WHITE, 0.2) or ACCENT_HI
		end
		sizeInfo()
	end

	local infoFade = Fade.new(info)
	local hintFade = Fade.new(hint)
	local previewFade = Fade.new(previewSlot)
	local panelFade = Fade.new(holder, { [content] = true, [info] = true, [hint] = true, [previewSlot] = true })

	local function fillInfo(item)
		local variant = VariantConfig.get(item.variant)
		nameLabel.Text = item.name
		rarityLabel.Text = rarityName(item.variant)
		rarityLabel.TextColor3 = variant.color
		TextShine.apply(rarityLabel, variant.id)
		typeLabel.Text = string.upper(item.typeLabel or item.category)
		detailDivider.BackgroundColor3 = variant.color
		accentLine.BackgroundColor3 = variant.color
		descLabel.Text = item.description or item.detail or ""
		local rows = { { "Owned", "x" .. Format.comma(item.quantity) } }
		for _, row in ipairs(item.rows or {}) do table.insert(rows, row) end
		for i, slot in ipairs(statRows) do
			local row = rows[i]
			slot.row.Visible = row ~= nil
			if row then
				slot.key.Text = row[1]
				slot.value.Text = row[2]
			end
			slot.line.Visible = rows[i + 1] ~= nil
		end
		statRows[1].value.TextColor3 = item.quantity > 0 and TEXT or MUTED
		hintText.Text = item.hint or ""
	end

	local function mountPreview(item, animate)
		previewFade:stop(true)
		if previewHandle then
			previewHandle:destroy()
			previewHandle = nil
		end
		if not item then return end
		local handle = ItemStage.mount(previewSlot, item, { size = "preview", gate = holder, phase = 0.37 })
		previewHandle = handle
		local variant = VariantConfig.get(item.variant)
		pedestal:setColor(variant.color, variant.id == "Cosmic" and variant.border.glowColours or nil)
		if animate then
			popScale.Scale = 0.86
			tween(popScale, { Scale = 1 }, 0.34, QUART)
			previewFade:run(1, 0, 0.24, QUAD, function(a) handle:setVisibility(1 - a) end)
		else
			popScale.Scale = 1
		end
	end

	local swapToken = 0
	local function showDetails(item, animate)
		swapToken += 1
		local mine = swapToken
		shownItem = item
		setAction(item)
		if not item then
			mountPreview(nil)
			infoFade:stop(true)
			hintFade:stop(true)
			info.Visible = false
			hint.Visible = false
			placeholder.Visible = true
			pedestal:setColor(ACCENT, nil)
			accentLine.BackgroundColor3 = ACCENT
			return
		end
		placeholder.Visible = false
		info.Visible = true
		hint.Visible = true
		mountPreview(item, animate)
		if animate then
			infoFade:run(0, 1, 0.07, QUAD, nil, function()
				if mine ~= swapToken then return end
				fillInfo(item)
				info.CanvasPosition = Vector2.zero
				infoFade:run(1, 0, 0.18, QUAD)
				hintFade:run(1, 0, 0.18, QUAD)
			end)
			hintFade:run(0, 1, 0.07, QUAD)
		else
			infoFade:stop(true)
			hintFade:stop(true)
			fillInfo(item)
		end
	end

	local function selectItem(id, animate)
		if selectedId == id then return end
		local previous = selectedId and slots[selectedId]
		selectedId = id
		if previous then previous.setSelected(false) end
		local slot = id and slots[id]
		if slot then slot.setSelected(true) end
		showDetails(id and itemsById[id] or nil, animate)
	end

	local function orderedSlots()
		local list = {}
		for _, slot in pairs(slots) do table.insert(list, slot) end
		table.sort(list, function(a, b) return a.cell.LayoutOrder < b.cell.LayoutOrder end)
		return list
	end

	local function stagger(base)
		for i, slot in ipairs(orderedSlots()) do
			slot.appear((base or 0) + (i - 1) * 0.024)
		end
	end

	local tabs = {}
	local function refresh()
		if not holder.Parent then return {} end
		local profile = getProfile()
		local query = string.lower(search.Text):match("^%s*(.-)%s*$")
		local visible, order, created = {}, 0, {}
		local totals = { All = 0, Currency = 0, Essence = 0, Cores = 0 }
		for _, item in ipairs(Inventory.items(profile)) do
			totals.All += 1
			totals[item.category] = (totals[item.category] or 0) + 1
			local haystack = string.lower(item.name .. " " .. item.detail .. " " .. item.category .. " " .. rarityName(item.variant))
			local matches = query == "" or string.find(haystack, query, 1, true) ~= nil
			-- All defined essences stay visible, including x0, as in the original Backpack.
			if matches and (record.selectedTab == "All" or record.selectedTab == item.category) then
				order += 1
				visible[item.id] = true
				itemsById[item.id] = item
				if not slots[item.id] then
					slots[item.id] = Inventory.CreateInventorySlot(content, item, order, nil,
						function(id) selectItem(id, true) end, holder, grid.CellSize.X.Offset)
					table.insert(created, slots[item.id])
					if selectedId == item.id then slots[item.id].setSelected(true) end
				else
					slots[item.id].update(item)
				end
				slots[item.id].cell.LayoutOrder = order
			end
		end
		for id, slot in pairs(slots) do
			if not visible[id] then
				slot.cell:Destroy()
				slots[id] = nil
			end
		end
		for name, tab in pairs(tabs) do tab.setCount(totals[name] or 0) end
		shownLabel.Text = ("%d / %d"):format(order, totals.All)
		countText.Text = ("%d %s"):format(totals.All, totals.All == 1 and "Item" or "Items")
		empty.Visible = order == 0
		if order == 0 and record.selectedTab == "Cores" and query == "" then
			emptyTitle.Text = "No Summon Cores yet"
			emptyHint.Text = "Every Pirate Shark win drops a Summon Core. Upgrade them at the Card Forge."
		else
			emptyTitle.Text = "No matching items"
			emptyHint.Text = "Try another search or category."
		end

		if selectedId and not visible[selectedId] then selectedId = nil end
		if not selectedId then
			local first = orderedSlots()[1]
			if first then
				selectItem(first.button:GetAttribute("ItemId"), false)
			elseif shownItem ~= nil then
				showDetails(nil, false)
			end
		elseif shownItem and itemsById[selectedId] then
			-- Luck and encounter unlocks can change while this item is selected.
			-- Refresh the guarantee as well as the count, without replaying art.
			shownItem = itemsById[selectedId]
			fillInfo(shownItem)
		end
		return created
	end

	------------------------------------------------------------------
	-- category tabs
	------------------------------------------------------------------
	local function tabIcon(name, parent)
		local box = new("Frame", { Parent = parent, Name = "Icon", BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = UDim2.fromOffset(20, 20), ZIndex = 3 })
		local parts = {}
		if name == "All" then
			for i = 0, 3 do
				table.insert(parts, new("Frame", { Parent = box, Name = "Cell", BackgroundColor3 = MUTED,
					Position = UDim2.fromOffset(2 + (i % 2) * 9, 2 + math.floor(i / 2) * 9), Size = UDim2.fromOffset(7, 7),
					ZIndex = 3 }, { corner(2) }))
			end
		elseif name == "Currency" then
			table.insert(parts, ElderCoin.still(box, { Size = UDim2.fromScale(1.1, 1.1), ZIndex = 3 }))
		elseif name == "Cores" then
			table.insert(parts, new("ImageLabel", { Parent = box, Name = "Core", BackgroundTransparency = 1,
				Image = SummonCoreConfig.Families.Cosmic.image, ScaleType = Enum.ScaleType.Fit,
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1.3, 1.3), ZIndex = 3 }))
		else
			table.insert(parts, ElderEssence.attach(box, "III", { Size = UDim2.fromScale(1.2, 1.2), ZIndex = 3 }))
		end
		return parts
	end

	local function moveIndicator(index, animate)
		local goal = UDim2.fromOffset(0, TAB_TOP + (index - 1) * (TAB_H + TAB_GAP) + TAB_H / 2)
		if animate then
			tween(indicator, { Position = goal }, 0.26, QUART)
		else
			indicator.Position = goal
		end
	end

	local function selectTab(name, animate)
		record.selectedTab = name
		for _, tab in pairs(tabs) do tab.paint(animate) end
		for i, tabName in ipairs(TABS) do
			if tabName == name then moveIndicator(i, animate) end
		end
		content.CanvasPosition = Vector2.zero
		refresh()
		if animate then stagger(0) end
	end

	for order, name in ipairs(TABS) do
		local cell = new("Frame", { Parent = tabList, Name = name .. "Cell", LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, TAB_H), BackgroundTransparency = 1, ZIndex = 2 })
		local button = new("TextButton", { Parent = cell, Name = name, Text = "", AutoButtonColor = false,
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(60, 46, 104), BackgroundTransparency = 1, ZIndex = 1 }, { corner(10) })
		new("UIGradient", { Parent = button, Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.72) }) })
		local tabStroke = new("UIStroke", { Parent = button, Color = ACCENT_HI, Transparency = 1, Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
		local interaction = new("UIScale", { Parent = button, Name = "InteractionScale", Scale = 1 })
		local inner = new("Frame", { Parent = button, Name = "Content", BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1), ZIndex = 2 })
		local icon = tabIcon(name, inner)
		local caption = text(inner, "Caption", name, 17, MUTED, 3)
		caption.AnchorPoint = Vector2.new(0, 0.5)
		caption.Position = UDim2.new(0, 44, 0.5, 0)
		caption.Size = UDim2.new(1, -96, 0, 22)
		local pill = new("Frame", { Parent = inner, Name = "Count", AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(30, 20),
			BackgroundColor3 = Color3.fromRGB(42, 39, 60), BackgroundTransparency = 0.1, ZIndex = 3 }, { round() })
		local pillText = text(pill, "Value", "0", 12, MUTED, 4)
		pillText.Size = UDim2.fromScale(1, 1)
		pillText.TextXAlignment = Enum.TextXAlignment.Center
		record.tabButtons[name] = button

		local hovered, pressToken = false, 0
		local tab = {}
		function tab.paint(animate)
			local selected = record.selectedTab == name
			local d = animate == false and 0 or 0.18
			tween(button, { BackgroundTransparency = selected and 0.12 or (hovered and 0.74 or 1) }, d)
			tween(tabStroke, { Transparency = selected and 0.84 or 1 }, d)
			tween(inner, { Position = UDim2.fromOffset(selected and 3 or 0, 0) }, d + 0.06, QUART)
			tween(interaction, { Scale = selected and 1.02 or (hovered and 1.01 or 1) }, d)
			tween(caption, { TextColor3 = selected and TEXT or (hovered and TEXT:Lerp(MUTED, 0.35) or MUTED) }, d)
			tween(pill, { BackgroundColor3 = selected and ACCENT or Color3.fromRGB(42, 39, 60),
				BackgroundTransparency = selected and 0.12 or 0.1 }, d)
			tween(pillText, { TextColor3 = selected and WHITE or MUTED }, d)
			for _, part in ipairs(icon) do
				if part:IsA("ImageLabel") then
					tween(part, { ImageTransparency = (selected or hovered) and 0 or 0.35 }, d)
				else
					tween(part, { BackgroundColor3 = selected and ACCENT_HI or MUTED }, d)
				end
			end
		end
		function tab.setCount(value)
			pillText.Text = tostring(value)
			pill.Size = UDim2.fromOffset(math.max(26, 14 + #pillText.Text * 8), 20)
		end
		tabs[name] = tab

		button.MouseEnter:Connect(function() hovered = true; tab.paint(true) end)
		button.MouseLeave:Connect(function() hovered = false; tab.paint(true) end)
		button.SelectionGained:Connect(function() hovered = true; tab.paint(true) end)
		button.SelectionLost:Connect(function() hovered = false; tab.paint(true) end)
		button.MouseButton1Down:Connect(function()
			pressToken += 1
			tween(interaction, { Scale = 0.96 }, 0.06)
		end)
		button.Activated:Connect(function()
			pressToken += 1
			local mine = pressToken
			-- The tiny compression, then the tab settles as selected.
			tween(interaction, { Scale = 0.96 }, 0.05)
			task.delay(0.05, function()
				if mine ~= pressToken then return end
				if record.selectedTab ~= name then
					selectTab(name, true)
				else
					tab.paint(true)
				end
			end)
		end)
	end

	search:GetPropertyChangedSignal("Text"):Connect(function()
		clear.Visible = search.Text ~= ""
		content.CanvasPosition = Vector2.zero
		for _, slot in ipairs(refresh()) do slot.appear(0) end
	end)

	------------------------------------------------------------------
	-- layout
	------------------------------------------------------------------
	local function layout(W, H)
		holder.Size = UDim2.fromOffset(W, H)
		local compact = W < 1120
		local SW = compact and 176 or 196
		local DW = compact and 272 or 300
		local top = 84
		local bodyH = H - top - 18

		searchBar.Size = UDim2.fromOffset(math.clamp(math.floor(W * 0.27), 230, 360), 38)

		layoutState.sidebar = UDim2.fromOffset(20, top)
		sidebar.Position = layoutState.sidebar
		sidebar.Size = UDim2.fromOffset(SW, bodyH)

		local gx = 20 + SW + 30
		local dx = W - 20 - DW
		local gw = dx - 30 - gx
		itemsCol.Position = UDim2.fromOffset(gx, top)
		itemsCol.Size = UDim2.fromOffset(gw, bodyH)
		separatorA.Position = UDim2.fromOffset(20 + SW + 15, top + 6)
		separatorA.Size = UDim2.fromOffset(1, bodyH - 12)
		separatorB.Position = UDim2.fromOffset(dx - 15, top + 6)
		separatorB.Size = UDim2.fromOffset(1, bodyH - 12)

		layoutState.details = UDim2.fromOffset(dx, top)
		details.Position = layoutState.details
		details.Size = UDim2.fromOffset(DW, bodyH)

		-- Columns come from the width that is left, never from the screen.
		local gap = 14
		local inner = gw - 28
		local columns = math.clamp(math.floor((inner + gap) / (116 + gap)), 2, 7)
		local cellSize = math.floor((inner - (columns - 1) * gap) / columns)
		grid.CellSize = UDim2.fromOffset(cellSize, cellSize)
		grid.CellPadding = UDim2.fromOffset(gap, 22)
		grid.FillDirectionMaxCells = columns
		for _, slot in pairs(slots) do slot.resize(cellSize) end

		local stageH = math.clamp(math.floor(bodyH * 0.45), 160, 280)
		stage.Size = UDim2.new(1, -28, 0, stageH)
		local infoTop = 14 + stageH + 14
		info.Position = UDim2.fromOffset(16, infoTop)
		layoutState.infoTop = infoTop
		sizeInfo()
		placeholder.Position = UDim2.fromOffset(16, infoTop + 18)
		placeholder.Size = UDim2.new(1, -32, 0, 80)
	end

	local function fit()
		local size = root.AbsoluteSize
		if size.X < 2 or size.Y < 2 then return end
		-- One scale for the whole window, from the screen; then the window's
		-- design size follows whatever room is left at that scale.
		local s = math.clamp(math.min(size.X / 1720, size.Y / 960), 0.62, 1.06)
		s = math.max(0.3, math.min(s, (size.X - 24) / 900, (size.Y - 24) / 520))
		local H = math.clamp(math.floor((size.Y - 72) / s), 520, 700)
		local W = math.clamp(math.floor((size.X - 48) / s), 900, math.min(1340, math.floor(H * 1.92)))
		if record.motion then
			record.motion:Cancel()
			record.motion = nil
		end
		record.baseScale = s
		scale.Scale = s
		layout(W, H)
	end

	------------------------------------------------------------------
	-- entrance and exit (called by MenuController)
	------------------------------------------------------------------
	local function setVisibility(a)
		holder:SetAttribute("PanelVisibility", 1 - a)
	end

	function record.onOpen()
		panelFade:run(1, 0, 0.26, QUAD, setVisibility)
		infoFade:run(1, 0, 0.3, QUAD)
		hintFade:run(1, 0, 0.3, QUAD)
		local handle = previewHandle
		previewFade:run(1, 0, 0.34, QUAD, function(a) if handle then handle:setVisibility(1 - a) end end)
		popScale.Scale = 0.92
		tween(popScale, { Scale = 1 }, 0.42, QUART)
		sidebar.Position = layoutState.sidebar - UDim2.fromOffset(16, 0)
		tween(sidebar, { Position = layoutState.sidebar }, 0.32, QUART)
		details.Position = layoutState.details + UDim2.fromOffset(12, 0)
		tween(details, { Position = layoutState.details }, 0.32, QUART)
		header.Position = UDim2.fromOffset(0, -6)
		tween(header, { Position = UDim2.fromOffset(0, 0) }, 0.3, QUART)
		stagger(0.06)
	end

	function record.onClose()
		panelFade:run(0, 1, 0.14, QUAD, setVisibility)
		infoFade:run(0, 1, 0.12, QUAD)
		hintFade:run(0, 1, 0.12, QUAD)
		local handle = previewHandle
		previewFade:run(0, 1, 0.12, QUAD, function(a) if handle then handle:setVisibility(1 - a) end end)
		for _, slot in pairs(slots) do slot.vanish(0.12) end
	end

	holder:GetPropertyChangedSignal("Visible"):Connect(function()
		if holder.Visible then return end
		-- Hidden: hand every property back so the next entrance starts clean.
		search:ReleaseFocus()
		panelFade:stop(true)
		infoFade:stop(true)
		hintFade:stop(true)
		previewFade:stop(true)
		if previewHandle then previewHandle:setVisibility(1) end
		for _, slot in pairs(slots) do slot.settle() end
		holder:SetAttribute("PanelVisibility", 1)
		sidebar.Position = layoutState.sidebar
		details.Position = layoutState.details
		header.Position = UDim2.fromOffset(0, 0)
		popScale.Scale = 1
	end)

	local resize = root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	holder.Destroying:Connect(function() resize:Disconnect() end)
	fit()
	selectTab("All", false)
	return record, refresh
end

return Inventory
