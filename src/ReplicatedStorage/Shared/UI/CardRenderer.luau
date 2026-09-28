--!strict
-- THE card visual. One builder, used by the reveal, the backpack, the deck
-- screen and anything later. If a card looks wrong it is wrong in exactly one
-- place.
--
-- IMPORTANT:
-- This version ONLY fixes the square/pointy artwork edges.
-- It KEEPS your original:
--   • main UIStroke
--   • rarity border colour
--   • border thickness logic
--   • Shine module
--   • Shine.apply(...) effect
--   • text layout
--   • stats
--   • pills
--
-- Nothing from your border/shine system is removed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local CardDefinitions = require(ReplicatedStorage.Shared.Config.CardDefinitions)
local SupportDefinitions = require(ReplicatedStorage.Shared.Config.SupportDefinitions)
local PassiveDefinitions = require(ReplicatedStorage.Shared.Config.PassiveDefinitions)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
local CardStats = require(ReplicatedStorage.Shared.Util.CardStats)
local RarityFormat = require(ReplicatedStorage.Shared.Util.RarityFormat)
local Format = require(ReplicatedStorage.Shared.Util.Format)

-- KEEP YOUR SHINE EFFECT.
local Shine = require(ReplicatedStorage.Shared.UI.Shine)
local TextShine = require(ReplicatedStorage.Shared.UI.TextShine)
local Sweep = require(ReplicatedStorage.Shared.UI.Sweep)
local ArtLoader = require(ReplicatedStorage.Shared.UI.ArtLoader)

local CardRenderer = {}

local WHITE = Color3.new(1, 1, 1)
local INK   = Color3.fromRGB(8, 8, 12)

local CARD_RADIUS = 12

local function new(class, props, children)
	local inst = Instance.new(class)

	for k, v in pairs(props) do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end

	for _, c in ipairs(children or {}) do
		c.Parent = inst
	end

	if props.Parent then
		inst.Parent = props.Parent
	end

	return inst
end

-- Outlined text, the way the reference cards read over busy artwork.
local function outlined(props, thickness: number?)
	local d = {
		BackgroundTransparency = 1,
		FontFace = Theme.font(),
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		RichText = false,
	}

	for k, v in pairs(props) do
		d[k] = v
	end

	local lbl = new("TextLabel", d)

	new("UIStroke", {
		Parent = lbl,
		Color = INK,
		Thickness = thickness or 2,
		LineJoinMode = Enum.LineJoinMode.Round,
	})

	return lbl
end

-- The card's vertical furniture was authored in fixed pixels against a 240px
-- wide card (the deck's reference size). Those pixels do not shrink with the
-- card, so on a narrow card the bottom-anchored block - ability name, ability
-- text, DMG/HP - climbs up the face until it collides with the name and the
-- rarity denominator. The top block needs 74px and the bottom block 114px; a
-- 130px-wide card is only 174px tall, so they overlap by 14px.
--
-- vScale() is the correction. It is CLAMPED AT 1, so every existing caller
-- (deck 240, reveal 250, battle inspect 380) is pixel-for-pixel unchanged and
-- only cards narrower than the reference are affected.
local REF_H = math.floor(240 * 1.34)

local function vScale(height: number): number
	return math.clamp(height / REF_H, 0.55, 1)
end

local function vs(value: number, scale: number): number
	return math.floor(value * scale + 0.5)
end

local function pill(parent, x, w, zIndex, s)
	s = s or 1
	return new("Frame", {
		Parent = parent,
		Position = UDim2.new(0, x, 0, vs(8, s)),
		Size = UDim2.new(0, w, 0, vs(20, s)),
		BackgroundColor3 = Color3.fromRGB(18, 18, 26),
		BackgroundTransparency = 0.15,
		ZIndex = zIndex,
	}, {
		new("UICorner", {
			CornerRadius = UDim.new(1, 0),
		}),
		new("UIStroke", {
			Color = Color3.fromRGB(90, 90, 115),
			Thickness = 1,
		}),
	})
end

-- Creates an empty card. Call update() to fill it.
function CardRenderer.create(parent: Instance, width: number, baseZ: number?)
	local z = baseZ or 4
	local height = math.floor(width * 1.34)
	local s = vScale(height)
	local pillText = math.max(8, math.floor(11 * s))

	----------------------------------------------------------------
	-- ROOT
	----------------------------------------------------------------

	local root = new("Frame", {
		Parent = parent,
		Size = UDim2.new(0, width, 0, height),

		BackgroundColor3 = Color3.fromRGB(16, 16, 24),
		BorderSizePixel = 0,

		ClipsDescendants = true,
		ZIndex = z,
	}, {
		new("UICorner", {
			CornerRadius = UDim.new(0, CARD_RADIUS),
		}),
	})

	----------------------------------------------------------------
	-- YOUR ORIGINAL MAIN BORDER — KEPT
	----------------------------------------------------------------

	local stroke = new("UIStroke", {
		Parent = root,

		Color = Color3.fromRGB(120, 120, 150),

		Thickness = 4,

		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,

		-- Keep it inside where Roblox supports this property.
		BorderStrokePosition = Enum.BorderStrokePosition.Inner,

		LineJoinMode = Enum.LineJoinMode.Round,

		ZIndex = z + 20,
	})

	----------------------------------------------------------------
	-- 1 ART
	----------------------------------------------------------------

	-- FIX:
	-- Keep the image full-size, but round THE IMAGE ITSELF.
	-- This prevents the square corners of the source PNG from sticking
	-- through your rounded border.
	--
	-- No inset. No border removal. No shine removal.
	local art = new("ImageLabel", {
		Parent = root,

		Position = UDim2.new(0, 0, 0, 0),
		Size = UDim2.new(1, 0, 1, 0),

		BackgroundColor3 = Color3.fromRGB(20, 20, 30),
		BorderSizePixel = 0,

		Image = "",
		ScaleType = Enum.ScaleType.Crop,

		ZIndex = z,
	}, {
		new("UICorner", {
			-- Slightly smaller than the card radius so the border covers it cleanly.
			CornerRadius = UDim.new(0, CARD_RADIUS - 2),
		}),
	})

	local artPlaceholder = new("TextLabel", {
		Parent = root,

		Size = UDim2.new(1, 0, 1, 0),

		BackgroundTransparency = 1,

		Text = "NO ART",

		FontFace = Theme.font(),
		TextSize = 13,

		TextColor3 = Color3.fromRGB(70, 70, 92),

		ZIndex = z,
	}, {
		new("UICorner", {
			CornerRadius = UDim.new(0, CARD_RADIUS - 2),
		}),
	})

	----------------------------------------------------------------
	-- 2 TOP SCRIM
	----------------------------------------------------------------

	-- Also round the scrim so its square top corners cannot cover the border.
	new("Frame", {
		Parent = root,

		Size = UDim2.new(1, 0, 0.30, 0),

		BackgroundColor3 = INK,
		BorderSizePixel = 0,

		ZIndex = z + 1,
	}, {
		new("UICorner", {
			CornerRadius = UDim.new(0, CARD_RADIUS - 2),
		}),

		new("UIGradient", {
			Rotation = 90,

			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.15),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})

	----------------------------------------------------------------
	-- 3 BOTTOM SCRIM
	----------------------------------------------------------------

	-- Same thing at the bottom.
	new("Frame", {
		Parent = root,

		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),

		Size = UDim2.new(1, 0, 0.54, 0),

		BackgroundColor3 = INK,
		BorderSizePixel = 0,

		ZIndex = z + 1,
	}, {
		new("UICorner", {
			CornerRadius = UDim.new(0, CARD_RADIUS - 2),
		}),

		new("UIGradient", {
			Rotation = 90,

			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.45, 0.15),
				NumberSequenceKeypoint.new(1, 0.02),
			}),
		}),
	})

	----------------------------------------------------------------
	-- 4 RARITY PILL
	----------------------------------------------------------------

	local rarityPill = pill(root, 8, 62, z + 2, s)

	local rarityText = new("TextLabel", {
		Parent = rarityPill,

		Size = UDim2.new(1, 0, 1, 0),

		BackgroundTransparency = 1,

		Text = "Basic",

		FontFace = Theme.font(),
		TextSize = pillText,

		TextColor3 = WHITE,

		ZIndex = z + 3,
	})

	----------------------------------------------------------------
	-- 5 LEVEL PILL
	----------------------------------------------------------------

	local levelPill = pill(root, 74, 26, z + 2, s)

	local levelText = new("TextLabel", {
		Parent = levelPill,

		Size = UDim2.new(1, 0, 1, 0),

		BackgroundTransparency = 1,

		Text = "0",

		FontFace = Theme.font(),
		TextSize = pillText,

		TextColor3 = WHITE,

		ZIndex = z + 3,
	})

	----------------------------------------------------------------
	-- 6 NAME
	----------------------------------------------------------------

	local name = outlined({
		Parent = root,

		Position = UDim2.new(0, 10, 0, vs(32, s)),
		Size = UDim2.new(1, -20, 0, vs(30, s)),

		Text = "-",

		-- On a shrunk card the name is anchored to the TOP of its box, so the box
		-- shrinking cannot push the glyphs down onto the rarity line. Cards at the
		-- reference size keep centred alignment and are untouched.
		TextYAlignment = (s < 0.99) and Enum.TextYAlignment.Top
		                             or Enum.TextYAlignment.Center,

		TextSize = math.floor(width * 0.115),

		-- Shrink to fit rather than run off the edge.
		--
		-- The card root clips its descendants, so a name wider than the card was
		-- silently cut mid-word: "Mecha of the Future" lost its last letters at
		-- EVERY card size, and "Angel of the Divine" and "Ninja of the Forest"
		-- lost theirs on the smaller ones. Same treatment the ability name below
		-- already gets, and for the same reason.
		TextScaled = true,

		ZIndex = z + 3,
	}, 2.5)

	-- TextScaled ignores TextSize completely and grows text until it fills the
	-- box, so without this cap every SHORT name would balloon to the full line
	-- height. The maximum is the size the card was authored at, which means every
	-- name that already fitted is pixel-for-pixel unchanged and only the three
	-- that overflowed are touched.
	new("UITextSizeConstraint", {
		Parent = name,
		MaxTextSize = math.floor(width * 0.115),
		MinTextSize = 8,
	})

	----------------------------------------------------------------
	-- RARITY DENOMINATOR
	----------------------------------------------------------------

	-- AutomaticSize.X so the label hugs its number instead of spanning the card.
	-- A UIGradient maps across the label's BOX, not across the glyphs, so on a
	-- full-width label most of the variant palette would land on empty space and
	-- the digits would only ever show one washed-out slice of it. Same reason
	-- CardTile sizes its rarity label this way.
	local denom = new("TextLabel", {
		Parent = root,

		-- The extra (1 - s) term buys a few pixels of clearance from the name on a
		-- small card, where the name's outline stroke would otherwise touch these
		-- digits. It is exactly zero at s = 1, so the reference card is unchanged.
		Position = UDim2.new(0, 11, 0, vs(60, s) + math.floor((1 - s) * 12)),
		Size = UDim2.new(0, 0, 0, vs(14, s)),
		AutomaticSize = Enum.AutomaticSize.X,

		BackgroundTransparency = 1,

		Text = "",

		FontFace = Theme.font(),
		TextSize = 11,

		TextColor3 = Color3.fromRGB(215, 215, 235),

		TextXAlignment = Enum.TextXAlignment.Left,

		ZIndex = z + 3,
	})

	new("UIStroke", {
		Parent = denom,
		Color = INK,
		Thickness = 1.5,
	})

	----------------------------------------------------------------
	-- 7 ABILITY NAME
	----------------------------------------------------------------

	local abilityName = outlined({
		Parent = root,

		AnchorPoint = Vector2.new(0, 1),

		Position = UDim2.new(0, 10, 1, -vs(92, s)),
		Size = UDim2.new(1, -20, 0, vs(22, s)),

		Text = "-",

		TextSize = math.floor(width * 0.092),

		-- Shrink to fit instead of running off the edge. The card root clips its
		-- descendants, so a long ability name used to be silently cut in half.
		TextScaled = true,

		ZIndex = z + 3,
	}, 2)

	-- TextScaled ignores TextSize completely and grows text until it fills the
	-- box, so a SHORT name would balloon to the full 22px without this. The cap is
	-- the size we actually authored above: short names look exactly as before, and
	-- only names that would not otherwise fit are scaled down.
	new("UITextSizeConstraint", {
		Parent = abilityName,
		MaxTextSize = math.floor(width * 0.092),
		MinTextSize = 7,
	})

	----------------------------------------------------------------
	-- 8 ABILITY DESCRIPTION
	----------------------------------------------------------------

	local abilityDesc = new("TextLabel", {
		Parent = root,

		AnchorPoint = Vector2.new(0, 1),

		Position = UDim2.new(0, 10, 1, -vs(32, s)),
		Size = UDim2.new(1, -20, 0, vs(58, s)),

		BackgroundTransparency = 1,

		Text = "",

		FontFace = Theme.font(),

		TextSize = math.max(
			12,
			math.floor(width * 0.068)
		),

		TextColor3 = Color3.fromRGB(232, 232, 245),

		TextWrapped = true,

		-- Same reason as the ability name: this box is a fixed 58px tall and the
		-- card clips, so any description longer than about four lines simply
		-- disappeared off the bottom. Wrapped + scaled means the text always fits.
		TextScaled = true,

		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Bottom,

		ZIndex = z + 3,
	})

	-- Caps the scale at the authored size so a one-line ability does not blow up
	-- to fill the whole box. The floor is lower than the ability name's because
	-- this text has several lines to lose and staying READABLE matters less than
	-- staying COMPLETE - a truncated ability is worse than a small one.
	new("UITextSizeConstraint", {
		Parent = abilityDesc,
		MaxTextSize = math.max(12, math.floor(width * 0.068)),
		MinTextSize = 6,
	})

	new("UIStroke", {
		Parent = abilityDesc,
		Color = INK,
		Thickness = 1.5,
	})

	----------------------------------------------------------------
	-- 9 DMG
	----------------------------------------------------------------

	local dmg = outlined({
		Parent = root,

		AnchorPoint = Vector2.new(0, 1),

		Position = UDim2.new(0, 10, 1, -vs(6, s)),

		Size = UDim2.new(0.5, -12, 0, vs(22, s)),

		Text = "DMG 0",

		TextSize = math.floor(width * 0.078),

		TextColor3 = Color3.fromRGB(255, 82, 82),

		ZIndex = z + 3,
	}, 2.5)

	----------------------------------------------------------------
	-- 10 HP
	----------------------------------------------------------------

	local hp = outlined({
		Parent = root,

		AnchorPoint = Vector2.new(1, 1),

		Position = UDim2.new(1, -10, 1, -vs(6, s)),

		Size = UDim2.new(0.5, -12, 0, vs(22, s)),

		Text = "HP 0",

		TextSize = math.floor(width * 0.078),

		TextColor3 = Color3.fromRGB(96, 235, 128),

		TextXAlignment = Enum.TextXAlignment.Right,

		ZIndex = z + 3,
	}, 2.5)

	----------------------------------------------------------------
	-- SWEEP
	----------------------------------------------------------------
	-- The travelling highlight, on the same clock as the HUD buttons and the
	-- grid tiles. z + 1 puts it over the artwork but under the pills, the name
	-- and the ability text, which all sit at z + 2 and above - light crossing a
	-- card should pass behind what you are reading, not over it.
	--
	-- Three stacked layers here, one on a grid tile: a full card is large enough
	-- that a single hard-edged band looks like a rectangle sliding past, and
	-- stacking copies at increasing width is how the edge gets softened without
	-- a blur effect.
	--
	-- Callers that overlap cards strip this again with Sweep.remove: stacked
	-- highlights composite into a band across the pile instead of lighting one
	-- card. The battle board does exactly that.
	Sweep.attach(root, { zIndex = z + 1, transparency = 0.84, width = 0.4, layers = 3 })

	----------------------------------------------------------------
	-- RETURN
	----------------------------------------------------------------

	return {
		root = root,

		stroke = stroke,

		art = art,
		artPlaceholder = artPlaceholder,

		rarityPill = rarityPill,
		rarityText = rarityText,

		levelPill = levelPill,
		levelText = levelText,

		name = name,
		denom = denom,

		abilityName = abilityName,
		abilityDesc = abilityDesc,

		dmg = dmg,
		hp = hp,

		width = width,
		height = height,
	}
end

----------------------------------------------------------------
-- UPDATE CARD
----------------------------------------------------------------

-- data = { cardId, variant, level }
function CardRenderer.update(card, data)
	-- Either table: a support has to render as a full card in a deck slot.
	local def = CardDefinitions.get(data.cardId)
		or SupportDefinitions.get(data.cardId)

	if not def then
		return
	end

	local variant =
		VariantConfig.get(
			data.variant or "Standard"
		)

	local level =
		data.level or 0

	local stats =
		CardStats.compute(
			data.cardId,
			variant.id,
			level
		)

	local passive =
		def.passive
		and PassiveDefinitions.get(
			def.passive
		)

	----------------------------------------------------------------
	-- ART
	----------------------------------------------------------------

	-- Through ArtLoader, not a bare .Image assignment: a card whose artwork
	-- loses the cold-cache race would otherwise keep an empty face for the rest
	-- of the session, because Roblox never retries a failed image fetch.
	if def.art and def.art ~= "" then
		ArtLoader.set(card.art, def.art)
		card.artPlaceholder.Visible = false
	else
		card.art.Image = ""
		card.artPlaceholder.Visible = true
	end

	----------------------------------------------------------------
	-- RARITY / LEVEL
	----------------------------------------------------------------

	card.rarityText.Text =
		variant.display

	card.rarityText.TextColor3 =
		variant.color

	-- Must follow the line above: a gradient multiplies the TextColor3 beneath
	-- it, so TextShine forces white on the tiers that carry one and leaves the
	-- flat tier colour alone on the ones that do not.
	TextShine.apply(
		card.rarityText,
		variant.id
	)

	local rarityStroke =
		card.rarityPill:FindFirstChildOfClass(
			"UIStroke"
		)

	if rarityStroke then
		rarityStroke.Color =
			variant.color
	end

	card.levelText.Text =
		tostring(level)

	----------------------------------------------------------------
	-- NAME / RARITY NUMBER
	----------------------------------------------------------------

	card.name.Text =
		def.name

	card.denom.Text =
		RarityFormat.denominator(
			VariantConfig.effectiveRarity(
				def.baseRarity,
				variant.id
			)
		)

	-- The denominator wears THE TIER'S colour - the same colour as the border,
	-- the tier pill and the grid tile - so a tier looks like itself everywhere.
	--
	-- It was previously band-tinted for rank 1 only, on the premise that "a
	-- Standard border is band-tinted too". It is not: Shine draws every border
	-- from VariantConfig's border.baseColour and never reads RarityBands at all.
	-- So Basic cards were the one tier whose denominator changed colour from
	-- card to card - grey on Usopp, green on Robin, blue on Moon Demon, purple
	-- on Son Prodigy - inside an outline that was grey every time, and the same
	-- card's tile in the collection grid (CardTile, which always used the tier
	-- colour) disagreed with its own full card.
	card.denom.TextColor3 = variant.color

	-- Must follow the line above: a gradient multiplies the TextColor3 beneath
	-- it, so TextShine forces white on the tiers that carry one and leaves the
	-- flat colour alone on the ones that do not. This is what gives a Secret its
	-- travelling fade, matching the deck tiles.
	TextShine.apply(
		card.denom,
		variant.id
	)

	----------------------------------------------------------------
	-- PASSIVE
	----------------------------------------------------------------

	card.abilityName.Text =
		passive
		and passive.name
		or ""

	card.abilityDesc.Text =
		passive
		and passive.description
		or ""

	----------------------------------------------------------------
	-- STATS
	----------------------------------------------------------------

	-- LIVE stats win over the computed base ones.
	--
	-- CardStats.compute only knows cardId/variant/level, so it always returns the
	-- card as it left the collection screen. In battle a card's DMG moves - Will
	-- of the Dragon steals some, DmgUp multiplies it - and the battle snapshot
	-- carries the real figure. Without this the card sat at its base number all
	-- fight while hitting for something else entirely.
	--
	-- Callers outside battle simply omit these and get the base values as before.
	local shownDMG = data.dmg or stats.dmg
	local shownHP = data.maxHP or stats.hp

	card.dmg.Text =
		"DMG "
		.. Format.short(
			shownDMG
		)

	card.hp.Text =
		"HP "
		.. Format.short(
			shownHP
		)

	----------------------------------------------------------------
	-- YOUR ORIGINAL BORDER LOGIC — KEPT
	----------------------------------------------------------------

	-- The card outline, the denominator and the tier pill all read the same
	-- value, so the frame and the writing inside it can never disagree.
	card.stroke.Color = variant.color

	card.stroke.Thickness =
		variant.rank > 1
		and 4
		or 3

	----------------------------------------------------------------
	-- YOUR ORIGINAL SHINE EFFECT — KEPT
	----------------------------------------------------------------

	Shine.apply(
		card.root,
		variant.id,
		card.width
	)
end

return CardRenderer