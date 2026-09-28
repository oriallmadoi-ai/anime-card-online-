--!strict
-- A variant is the tier a copy comes in. Every card exists in all four.
--
-- TWO SEPARATE AXES, deliberately not entangled:
--   LEVEL   0..100 (boss cards to GameConfig.BossCardLevel), raised with Elder
--           Essence. Every copy starts at 0, so level 0 means "base stats, no
--           bonus" - GameConfig.MinCardLevel is the one number that decides it
--           and CardStats.levelMultiplier is the one place it is applied.
--   VARIANT the tier it was rolled into. Nothing to do with level.
--
-- rarityMultiplier is how much scarcer this variant is than the card's own
-- denominator. A 1/4 card in a x100 Gilded is effectively 1 in 400.
-- statMultiplier is how much stronger it is. Separate numbers so scarcity and
-- power tune independently.
--
-- `border` fully describes how a card of this tier is outlined. The renderer
-- reads it and draws; it has no per-variant branches of its own, so restyling a
-- tier - or adding a fifth - is an edit here and nowhere else.
--
--   base*      the dim resting outline, always present
--   bright*    the travelling highlight; omit to leave the tier unanimated
--   travel     seconds for one full rotation of the glow (lower = faster)
--   glowColours colours that circle the card. FIRST AND LAST MUST MATCH or the
--              gradient visibly jumps each time it wraps. Omit for no glow.
--   glowColour  a single colour for a STATIC glow - same falloff, no rotation.
--              Used where a tier should read as lit but not animated.
--   corner      corner radius at reference width; the renderer scales it and
--              applies it to the card, so the outline always traces the art.
--
-- `textGradient` is the same idea for the WRITING on the card, drawn by
-- TextShine. Same rule as glowColours: FIRST AND LAST COLOUR MUST MATCH, or the
-- palette visibly jumps each time it wraps. Omit to leave a tier's text flat.
--
--   colours    the palette that travels through the text
--   travel     seconds for one full pass (lower = faster)
--   rotation   gradient angle in degrees; 0 (left to right) reads best on text
--
-- NAMES vs IDS - IMPORTANT.
-- Merging copies into a higher tier is NOT implemented: there is no fuse or
-- merge code anywhere in the game today, so a variant is only ever the tier a
-- copy was rolled at.
--
-- `id` is what gets WRITTEN INTO SAVE DATA: inventory keys are "cardId|Variant",
-- so every owned copy is filed under its variant id. Renaming an id therefore
-- orphans every card a player owns of that tier and needs a DataService
-- migration (see the v3 step, which already renamed this set once).
-- `display` and `label` are pure presentation and can be changed freely. So the
-- tiers players see as Basic / Gilded / Divine / Secret are still stored under
-- their original ids, and nobody's inventory moves.

export type VariantId = "Standard" | "Gilded" | "Astral" | "Transcendent"

local VariantConfig = {}

VariantConfig.Order = { "Standard", "Gilded", "Astral", "Transcendent" }

-- Thicknesses below are authored against a card this wide; the renderer scales
-- from here, so a grid tile and a full reveal stay in proportion.
VariantConfig.BorderReferenceWidth = 180

VariantConfig.Data = {
	Standard = {
		id = "Standard", label = "B", display = "Basic",
		color = Color3.fromRGB(190, 194, 210),
		statMultiplier = 1, rarityMultiplier = 1, rank = 1,

		border = {
			baseColour = Color3.fromRGB(168, 176, 192),
			baseThickness = 2,
			baseTransparency = 0.25,
			-- A soft static grey halo: same falloff as the others, no rotation.
			glowColour = Color3.fromRGB(150, 158, 176),
			glowScale = 0.55,
			corner = 20,
		},
	},

	Gilded = {
		id = "Gilded", label = "G", display = "Gilded",
		color = Color3.fromRGB(255, 196, 60),
		statMultiplier = 4, rarityMultiplier = 100, rank = 2,

		border = {
			baseColour = Color3.fromRGB(251, 191, 36),
			baseThickness = 2.5,
			baseTransparency = 0.78,
			brightColour = Color3.fromRGB(251, 191, 36),
			brightThickness = 2.5,
			travel = 3.2,
			corner = 20,
			-- Gold: deep amber through to pale highlight and back.
			glowColours = {
				Color3.fromRGB(251, 191, 36),
				Color3.fromRGB(255, 236, 170),
				Color3.fromRGB(214, 146, 20),
				Color3.fromRGB(255, 214, 90),
				Color3.fromRGB(251, 191, 36),
			},
		},

		-- Gold reading as struck metal: amber body, one pale highlight passing
		-- through it, one darker trough behind.
		textGradient = {
			colours = {
				Color3.fromRGB(251, 191, 36),
				Color3.fromRGB(255, 240, 180),
				Color3.fromRGB(198, 132, 12),
				Color3.fromRGB(255, 214, 90),
				Color3.fromRGB(251, 191, 36),
			},
			travel = 3.2,
		},
	},

	Astral = {
		id = "Astral", label = "D", display = "Divine",
		color = Color3.fromRGB(120, 220, 255),
		statMultiplier = 16, rarityMultiplier = 10000, rank = 3,
		animated = true,

		border = {
			baseColour = Color3.fromRGB(56, 189, 248),
			baseThickness = 2.5,
			baseTransparency = 0.78,
			brightColour = Color3.fromRGB(56, 189, 248),
			brightThickness = 2.5,
			travel = 2.8,
			corner = 20,
			-- Blue: deep ocean through to pale sky.
			glowColours = {
				Color3.fromRGB(56, 189, 248),
				Color3.fromRGB(186, 240, 255),
				Color3.fromRGB(30, 110, 220),
				Color3.fromRGB(120, 210, 255),
				Color3.fromRGB(56, 189, 248),
			},
		},

		-- Divine: cyan falling into deep blue and back. The mid stop is darker
		-- than either end so the travel reads as depth rather than a flat wash.
		textGradient = {
			colours = {
				Color3.fromRGB(130, 245, 255),
				Color3.fromRGB(40, 150, 255),
				Color3.fromRGB(14, 74, 224),
				Color3.fromRGB(60, 190, 255),
				Color3.fromRGB(130, 245, 255),
			},
			travel = 2.8,
		},
	},

	Transcendent = {
		id = "Transcendent", label = "S", display = "Secret",

		-- Red, matching the red already in this tier's own border and text
		-- gradients below.
		--
		-- This used to be a cream (255, 235, 170), which was the only place in
		-- the whole tier that was not white-and-red - so anything drawing a FLAT
		-- Secret colour (a badge ring, a caption, an item tile's rim) came out
		-- pale gold and read as a second Gilded rather than as the top tier.
		-- Everything that draws Secret with a travelling gradient was already
		-- red; this brings the flat colour into line with them.
		color = Color3.fromRGB(255, 82, 82),
		statMultiplier = 64, rarityMultiplier = 1000000, rank = 4,
		animated = true,

		border = {
			baseColour = Color3.fromRGB(255, 255, 255),
			baseThickness = 3,
			baseTransparency = 0.78,
			brightColour = Color3.fromRGB(255, 255, 255),
			brightThickness = 3,
			travel = 2.4,
			corner = 20,
			-- White cut with red, so the top tier reads hotter than the others.
			glowColours = {
				Color3.fromRGB(255, 255, 255),
				Color3.fromRGB(255, 90, 90),
				Color3.fromRGB(255, 255, 255),
				Color3.fromRGB(255, 150, 150),
				Color3.fromRGB(255, 255, 255),
			},
		},

		-- Secret: white with red driven through it. Two red stops per lap rather
		-- than one, so the top tier pulses twice as often as the others travel -
		-- it should read as the most agitated thing on screen.
		textGradient = {
			colours = {
				Color3.fromRGB(255, 255, 255),
				Color3.fromRGB(255, 62, 62),
				Color3.fromRGB(255, 255, 255),
				Color3.fromRGB(214, 16, 40),
				Color3.fromRGB(255, 255, 255),
			},
			travel = 2.4,
		},
	},

	-- COSMIC - PRESENTATION ONLY. NOT A CARD TIER.
	--
	-- Elder Coins are not a card and were borrowing Secret's border, which made
	-- the game's only currency look like a card you had pulled. This is its own
	-- identity instead.
	--
	-- It is deliberately absent from BOTH `Order` and `RollOrder`, which is what
	-- keeps it unreachable: RollOrder is the entire roll draw, so no roll can
	-- produce it, and Order drives the deck screen's border filter, so it never
	-- offers players a tier they cannot own. The only way to see a Cosmic border
	-- is for something to ask for it BY NAME, which today is the Elder Coin
	-- reward tile, the Elder Coin inventory tile, Elder Essence V and the Cosmic
	-- difficulty stage.
	--
	-- statMultiplier is 1, not 64: if a bug ever did put this on a card, it
	-- should look strange rather than hand out a 64x monster.
	Cosmic = {
		id = "Cosmic", label = "C", display = "Cosmic",
		color = Color3.fromRGB(150, 235, 255),
		statMultiplier = 1, rarityMultiplier = 1, rank = 5,
		animated = true,
		presentationOnly = true,

		border = {
			baseColour = Color3.fromRGB(220, 245, 255),
			baseThickness = 3,
			baseTransparency = 0.72,
			brightColour = Color3.fromRGB(255, 255, 255),
			brightThickness = 3,
			-- The fastest travel of any tier. The top of the game should be the
			-- most alive thing on the screen.
			travel = 1.9,
			glowScale = 1.15,
			corner = 20,
			-- Deep space: void blue into cyan, through violet and magenta, back
			-- through white. First and last match so the lap does not jump.
			glowColours = {
				Color3.fromRGB(120, 235, 255),
				Color3.fromRGB(255, 255, 255),
				Color3.fromRGB(168, 120, 255),
				Color3.fromRGB(255, 120, 235),
				Color3.fromRGB(90, 170, 255),
				Color3.fromRGB(120, 235, 255),
			},
		},

		textGradient = {
			colours = {
				Color3.fromRGB(180, 245, 255),
				Color3.fromRGB(255, 255, 255),
				Color3.fromRGB(186, 150, 255),
				Color3.fromRGB(255, 160, 240),
				Color3.fromRGB(180, 245, 255),
			},
			travel = 1.9,
		},
	},
}

function VariantConfig.get(id: string)
	return VariantConfig.Data[id] or VariantConfig.Data.Standard
end

function VariantConfig.multiplier(id: string): number
	return VariantConfig.get(id).statMultiplier
end

function VariantConfig.rollChance(id: string): number
	return 1 / VariantConfig.get(id).rarityMultiplier
end

-- What the player sees on the card: base denominator x variant scarcity.
function VariantConfig.effectiveRarity(baseDenominator: number, id: string): number
	return baseDenominator * VariantConfig.get(id).rarityMultiplier
end

-- Rarest first, so a Transcendent roll is never swallowed by the Gilded check.
VariantConfig.RollOrder = { "Transcendent", "Astral", "Gilded" }

return VariantConfig
