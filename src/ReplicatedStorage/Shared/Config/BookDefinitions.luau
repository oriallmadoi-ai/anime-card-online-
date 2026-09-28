--!strict
-- ELDER ESSENCE: the only way a card gains levels.
--
-- Consumable items held in the player's inventory. Each grants a fixed number
-- of levels, so levelling is a resource decision rather than a currency
-- treadmill - the player chooses WHICH card gets the good essence.
--
-- Essence is card-agnostic on purpose: one pool feeds every card, so a vial is
-- never dead weight.
--
-- WHY THE IDS STILL SAY "TOME".
-- These ids are SAVE KEYS - profile.books is a map of id -> count, so renaming
-- MinorTome to EssenceI would orphan every vial a player already holds and
-- need a DataService migration. `name`, `tier` and `variant` are pure
-- presentation and can change freely, which is the same split VariantConfig
-- documents for card tiers. So players see Elder Essence I..V and nobody's
-- inventory moves. EssenceV is genuinely new, so it gets a new key.
--
-- THE LADDER. Each tier simply gives more than the last:
--   I 1, II 5, III 20, IV 50, V fills the card to its own maximum.
-- V is the only one that cannot be wasted - see LevelService, which refuses
-- any essence that would overflow the cap and makes an exception for `toMax`.
-- That exception is what keeps V ahead of IV once a card is part-levelled, and
-- it is why V is the tier that matters on boss cards, which run to 120.
--
-- `variant` names a VariantConfig tier, and it is what every piece of UI reads
-- to draw this item's border. The five essences therefore wear the same five
-- frames as cards do, which is the whole point of the ladder being readable.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)

local BookDefinitions = {}

BookDefinitions.Order = {
	"MinorTome", "GreaterTome", "ArcaneTome", "AscendantTome", "EssenceV",
}

BookDefinitions.Data = {
	MinorTome = {
		id = "MinorTome", name = "Elder Essence I", tier = "I", levels = 1,
		variant = "Standard",
		description = "Grants 1 level to a single card.",
	},
	GreaterTome = {
		id = "GreaterTome", name = "Elder Essence II", tier = "II", levels = 5,
		variant = "Gilded",
		description = "Grants 5 levels to a single card.",
	},
	ArcaneTome = {
		id = "ArcaneTome", name = "Elder Essence III", tier = "III", levels = 20,
		variant = "Astral",
		description = "Grants 20 levels to a single card.",
	},
	AscendantTome = {
		id = "AscendantTome", name = "Elder Essence IV", tier = "IV", levels = 50,
		variant = "Transcendent",
		description = "Grants 50 levels to a single card.",
	},
	EssenceV = {
		id = "EssenceV", name = "Elder Essence V", tier = "V", levels = 0,
		toMax = true,
		variant = "Cosmic",
		description = "Fills a single card to its maximum level, however far it "
			.. "has already come. Never wasted.",
	},
}

-- `color` is DERIVED, never authored. Each essence already names the tier whose
-- frame it wears, so writing the colour out again beside it created a second
-- source of truth - and it had already drifted: four of the five copied the
-- tier's BORDER colour instead of the tier colour, and Essence V was a purple
-- that appears nowhere in VariantConfig's cyan Cosmic palette, so the item's
-- accent and the border drawn around it disagreed on screen. Filling it in
-- here keeps every consumer's `def.color` working while making the tier the
-- only place a colour is decided.
for _, def in pairs(BookDefinitions.Data) do
	def.color = VariantConfig.get(def.variant).color
end

function BookDefinitions.get(id: string) return BookDefinitions.Data[id] end

-- How many of this essence can be spent AT ONCE on a card at `level` without
-- overflowing `cap`, given the player holds `owned`.
--
-- The client sizes its quantity stepper from this and the server clamps to it,
-- so the two can never disagree about what is legal - the UI cannot offer a
-- number the server would refuse, and a hand-built remote call cannot smuggle
-- one past it either.
--
-- A to-max essence answers 1, however many are held: the second one would have
-- nothing left to fill.
function BookDefinitions.maxUsable(id: string, level: number, cap: number,
	owned: number): number

	local def = BookDefinitions.Data[id]
	if not def or owned < 1 or level >= cap then return 0 end
	if def.toMax then return 1 end
	if def.levels <= 0 then return 0 end
	return math.min(owned, math.floor((cap - level) / def.levels))
end

return BookDefinitions
