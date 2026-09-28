--!strict
-- Compact card tile for grid views.
--
-- A grid shows dozens of cards at once, so a tile carries only what is needed
-- to FIND a card: artwork, variant, level, how many you own, and its rarity.
-- Ability text is deliberately absent - it is unreadable at this size and it
-- belongs on the hover preview, which renders the full card.
--
-- Layers, back to front: art, scrim, variant badge, level pill, count, rarity.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local CardDefinitions = require(ReplicatedStorage.Shared.Config.CardDefinitions)
local SupportDefinitions = require(ReplicatedStorage.Shared.Config.SupportDefinitions)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Shine = require(ReplicatedStorage.Shared.UI.Shine)
local TextShine = require(ReplicatedStorage.Shared.UI.TextShine)
local Sweep = require(ReplicatedStorage.Shared.UI.Sweep)
local ArtLoader = require(ReplicatedStorage.Shared.UI.ArtLoader)

local CardTile = {}

local INK = Color3.fromRGB(8, 8, 12)
local WHITE = Color3.new(1, 1, 1)

local function new(class, props, children)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		if k ~= "Parent" then (inst :: any)[k] = v end
	end
	for _, c in ipairs(children or {}) do c.Parent = inst end
	if props.Parent then inst.Parent = props.Parent end
	return inst
end

local function outlined(props, thickness)
	local d = { BackgroundTransparency = 1, FontFace = Theme.font(), TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Center }
	for k, v in pairs(props) do d[k] = v end
	local lbl = new("TextLabel", d)
	new("UIStroke", { Parent = lbl, Color = INK, Thickness = thickness or 2,
		LineJoinMode = Enum.LineJoinMode.Round })
	return lbl
end

function CardTile.create(parent: Instance, width: number, baseZ: number?)
	local z = baseZ or 8
	local height = math.floor(width * 1.06)

	local root = new("ImageButton", {
		Parent = parent, Size = UDim2.new(0, width, 0, height),
		BackgroundColor3 = Color3.fromRGB(14, 14, 22), AutoButtonColor = false,
		Image = "", ClipsDescendants = true, ZIndex = z,
	}, { new("UICorner", { CornerRadius = UDim.new(0, 20) }) })

	local stroke = new("UIStroke", { Parent = root, Color = Color3.fromRGB(120, 120, 150), Thickness = 2 })

	local art = new("ImageLabel", {
		Parent = root, Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
		Image = "", ScaleType = Enum.ScaleType.Crop, ZIndex = z,
	}, { new("UICorner", { CornerRadius = UDim.new(0, 20) }) })
	local noArt = new("TextLabel", {
		Parent = root, Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
		Text = "NO ART", FontFace = Theme.font(), TextSize = 11,
		TextColor3 = Color3.fromRGB(70, 70, 92), ZIndex = z,
	})

	-- Scrims: top for the badges, bottom for the rarity number.
	new("Frame", { Parent = root, Size = UDim2.new(1, 0, 0.28, 0), BackgroundColor3 = INK,
		BorderSizePixel = 0, ZIndex = z + 1 },
		{ new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }) }) })

	new("Frame", { Parent = root, AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0.3, 0),
		BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = z + 1 },
		{ new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.05) }) }) })

	-- variant badge, top-left
	local badge = new("Frame", { Parent = root, Position = UDim2.new(0, 4, 0, 4),
		Size = UDim2.new(0, 20, 0, 20), BackgroundColor3 = Color3.fromRGB(16, 16, 24),
		ZIndex = z + 2 }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	local badgeStroke = new("UIStroke", { Parent = badge, Color = WHITE, Thickness = 1.5 })
	local badgeText = new("TextLabel", { Parent = badge, Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1, Text = "S", FontFace = Theme.font(), TextSize = 11,
		TextColor3 = WHITE, ZIndex = z + 3 })

	-- level pill, next to the badge
	local levelPill = new("Frame", { Parent = root, Position = UDim2.new(0, 27, 0, 4),
		Size = UDim2.new(0, 28, 0, 20), BackgroundColor3 = Color3.fromRGB(56, 56, 70),
		BackgroundTransparency = 0.1, ZIndex = z + 2 },
		{ new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	local levelText = new("TextLabel", { Parent = levelPill, Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1, Text = "1", FontFace = Theme.font(), TextSize = 11,
		TextColor3 = WHITE, ZIndex = z + 3 })

	-- owned count, top-right
	local count = outlined({ Parent = root, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -5, 0, 5), Size = UDim2.new(0, 46, 0, 16), Text = "x1",
		TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = z + 3 }, 2)

	-- rarity denominator, bottom
	-- AutomaticSize.X so the label hugs its number rather than spanning the tile:
	-- a UIGradient maps across the label's box, and on a full-width label most of
	-- the palette would land on empty space either side of the digits.
	local rarity = outlined({ Parent = root, AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.new(0, 0, 0, 15), Text = "",
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = 11, ZIndex = z + 3 }, 1.8)

	-- The same light that crosses the HUD buttons, on the same clock. Added
	-- last so it sits over the art and the scrims; the badges and the rarity
	-- number are at z+2 and above, so the light passes BEHIND the text rather
	-- than washing it out.
	--
	-- Fainter than the HUD's 0.78: a nav column is nine buttons, a collection
	-- grid is a hundred tiles, and at button strength a hundred of them sweeping
	-- together looks like the screen is flashing.
	Sweep.attach(root, { zIndex = z + 1, transparency = 0.8, width = 0.42 })

	return { root = root, stroke = stroke, art = art, noArt = noArt, width = width,
		badge = badge, badgeStroke = badgeStroke, badgeText = badgeText,
		levelText = levelText, count = count, rarity = rarity }
end

function CardTile.update(tile, data)
	-- Supports live in their own table; a tile must render either kind or the
	-- Support tab is permanently blank.
	local def = CardDefinitions.get(data.cardId) or SupportDefinitions.get(data.cardId)
	if not def then return end
	local variant = VariantConfig.get(data.variant or "Standard")

	-- See CardRenderer: a failed first fetch never retries on its own, and a
	-- collection grid is where that was most visible - a handful of blank tiles
	-- scattered through an otherwise complete page.
	if def.art and def.art ~= "" then
		ArtLoader.set(tile.art, def.art)
		tile.noArt.Visible = false
	else
		tile.art.Image = ""
		tile.noArt.Visible = true
	end

	tile.badgeText.Text = variant.label
	tile.badgeText.TextColor3 = variant.color
	tile.badgeStroke.Color = variant.color
	tile.levelText.Text = tostring(data.level or 0)
	tile.count.Text = "x" .. Format.comma(data.count or 1)

	-- The number shown is the EFFECTIVE rarity: the card's own denominator
	-- scaled by how much scarcer its variant is.
	tile.rarity.Text = Format.comma(VariantConfig.effectiveRarity(def.baseRarity, variant.id))
	tile.rarity.TextColor3 = variant.color

	tile.stroke.Color = variant.color
	tile.stroke.Thickness = variant.rank > 1 and 3 or 2

	-- Same treatment in the grid, so a Secret is spottable at a glance among
	-- hundreds of tiles.
	Shine.apply(tile.root, variant.id, tile.width)

	-- After the flat colours above, never before: TextShine overrides TextColor3
	-- to white on the tiers that carry a travelling palette, because a gradient
	-- multiplies the colour underneath it.
	TextShine.apply(tile.rarity, variant.id)
	TextShine.apply(tile.badgeText, variant.id)
end

return CardTile
