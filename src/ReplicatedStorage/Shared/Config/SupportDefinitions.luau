--!strict
-- SUPPORT cards. A support pairs to an attack slot (Support 1 assists Attack 1),
-- never takes the field, and only modifies its partner.
--
-- Because a support never fights, baseDMG and baseHP are 0 - they exist only so
-- the shared stat and render paths do not have to special-case a missing field.
-- What a support is worth is entirely in its passive.
--
-- SUPPORTS ARE STANDARD-ONLY. They have no stats for a variant multiplier to
-- scale, so a Gilded support was identical to a Basic one apart from the border,
-- and it inflated Battle Power for nothing. DataService:AddCard now forces every
-- support to Standard, and supports are skipped by the Battle Power sum entirely.

local SupportDefinitions = {}

SupportDefinitions.Data = {
	ShinigamiOfDeath = {
		id = "ShinigamiOfDeath", name = "Shinigami of Death", baseRarity = 250,
		baseDMG = 0, baseHP = 0,
		faction = "Duskmarch", tags = { "Shinigami", "Apple" },
		passive = "AppleLover", art = "rbxassetid://78844568510520",
	},
	-- ── roster ─────────────────────────────────────────────
	-- baseRarity here is a first pass, ordered by how much each passive is worth
	-- rather than measured: Trickery and Shuriken are chip damage, Just Clone It
	-- and Dream On swing whole fights. Tune the numbers, not the abilities.

	-- THE ONLY ROLLABLE SUPPORT, and only once it has been earned.
	--
	-- Every other support here is granted, never rolled - RollService draws from
	-- CardDefinitions alone. Will of D is the exception: clearing Pirate Shark on
	-- Impossible adds it to the roll pool for that player, which is what the
	-- "UNLOCK ROLL" reward tile is announcing. See EncounterModes.Unlocks; the
	-- gate lives there, not here, so this stays pure roster data.
	WillOfD = {
		id = "WillOfD",
		name = "Will of D",
		baseRarity = 1000,
		baseDMG = 0,
		baseHP = 0,
		faction = "Voyagers",
		tags = { "Will", "Stun" },
		passive = "GreaterWill",
		art = "rbxassetid://93717441430427",
	},

	UselessClown = {
		id = "UselessClown",
		name = "Useless Clown",
		baseRarity = 90,
		baseDMG = 0,
		baseHP = 0,
		faction = "SpiritWilds",
		tags = { "Trick", "Pierce" },
		passive = "Trickery",
		art = "rbxassetid://77706909489840",
	},

	NinjaOfTheForest = {
		id = "NinjaOfTheForest",
		name = "Ninja of the Forest",
		baseRarity = 130,
		baseDMG = 0,
		baseHP = 0,
		faction = "SpiritWilds",
		tags = { "Blade", "Bleed" },
		passive = "Shuriken",
		art = "rbxassetid://116870875459125",
	},

	AngelOfTheDivine = {
		id = "AngelOfTheDivine",
		name = "Angel of the Divine",
		baseRarity = 320,
		baseDMG = 0,
		baseHP = 0,
		faction = "IronReach",
		tags = { "Divine", "Mender" },
		passive = "Yummy",
		art = "rbxassetid://91669543566526",
	},

	BushHead = {
		id = "BushHead",
		name = "Bush Head",
		baseRarity = 650,
		baseDMG = 0,
		baseHP = 0,
		faction = "SpiritWilds",
		tags = { "Stealth", "Evade" },
		passive = "Sneaky",
		art = "rbxassetid://81115286217536",
	},

	TheSystem = {
		id = "TheSystem",
		name = "The System",
		baseRarity = 1100,
		baseDMG = 0,
		baseHP = 0,
		faction = "IronReach",
		tags = { "Arcane", "Surge" },
		passive = "SystemOverload",
		art = "rbxassetid://76449157488545",
	},

	MechaOfTheFuture = {
		id = "MechaOfTheFuture",
		name = "Mecha of the Future",
		baseRarity = 5000,
		baseDMG = 0,
		baseHP = 0,
		faction = "IronReach",
		tags = { "Mecha", "Guard" },
		passive = "BruteForce",
		art = "rbxassetid://73255598418397",
	},

	HiddenNinja = {
		id = "HiddenNinja",
		name = "Hidden Ninja",
		baseRarity = 45000,
		baseDMG = 0,
		baseHP = 0,
		faction = "Duskmarch",
		tags = { "Shadow", "Echo" },
		passive = "JustCloneIt",
		art = "rbxassetid://105319912307367",
	},

	MagicWorld = {
		id = "MagicWorld",
		name = "Magic World",
		baseRarity = 120000,
		baseDMG = 0,
		baseHP = 0,
		faction = "Duskmarch",
		tags = { "Dream", "Control" },
		passive = "DreamOn",
		art = "rbxassetid://122107101465565",
	},

	WealthyScientist = {
		id = "WealthyScientist",
		name = "Wealthy Scientist",
		baseRarity = 20000,
		baseDMG = 0,
		baseHP = 0,
		faction = "IronReach",
		tags = { "Wealth", "Sustain" },
		passive = "Factory",
		art = "rbxassetid://96640489592794",
	},
}

local sorted = {}
for id in pairs(SupportDefinitions.Data) do table.insert(sorted, id) end
table.sort(sorted, function(a, b)
	local ra, rb = SupportDefinitions.Data[a].baseRarity, SupportDefinitions.Data[b].baseRarity
	if ra ~= rb then return ra > rb end
	return a < b
end)
SupportDefinitions.RarestFirst = sorted
SupportDefinitions.MostCommonId = sorted[#sorted]   -- nil while the table is empty

function SupportDefinitions.get(id: string) return SupportDefinitions.Data[id] end
function SupportDefinitions.exists(id: string): boolean return SupportDefinitions.Data[id] ~= nil end

return SupportDefinitions
