--!strict

--[[
	CARD DEFINITIONS

	IMPORTANT STAT RULE:

	Every Attack card's BASE HP and BASE DMG come ONLY from its baseRarity.

	Higher denominator = rarer card = stronger card.

	Example:
	1/15 Dear Doctor
	1/25 Pirate Cook

	Pirate Cook MUST have more HP AND more DMG than Dear Doctor.

	Characters no longer get custom dmgShare values that can cause
	a lower-rarity card to have more HP than a higher-rarity card.

	Variants contribute their rarity multiplier to the card's effective
	denominator. CardStats runs that full denominator through this same curve,
	so a copy with a higher displayed rarity is always stronger regardless of
	which base card and variant produced it.
]]

-- GameConfig is a leaf config with no requires of its own, so pulling it in
-- here cannot create a cycle. It is needed for the level ceiling only.
local GameConfig = require(script.Parent.GameConfig)

local CardDefinitions = {}

----------------------------------------------------------------
-- RARITY-BASED STAT SYSTEM
----------------------------------------------------------------

-- The most common Attack card is currently 1/2.
local MIN_RARITY = 2

-- Starting stats for the most common rarity.
local BASE_DMG = 3
local BASE_HP = 16

-- Controls how quickly stats grow as cards become rarer.
--
-- Higher number = rare cards become much stronger.
-- Lower number = flatter balance.
--
-- 0.42 keeps the current game roughly in the same power range
-- while removing the old stat inconsistencies.
local STAT_EXPONENT = 0.42

----------------------------------------------------------------
-- CALCULATE RAW STATS FROM RARITY
----------------------------------------------------------------

local function statsForRarity(baseRarity: number): (number, number)

	local rarityScale =
		(baseRarity / MIN_RARITY) ^ STAT_EXPONENT

	local dmg =
		math.max(
			1,
			math.round(BASE_DMG * rarityScale)
		)

	local hp =
		math.max(
			1,
			math.round(BASE_HP * rarityScale)
		)

	return dmg, hp
end

-- Shared with CardStats so variants are evaluated from their full effective
-- denominator instead of an unrelated stat multiplier.
CardDefinitions.statsForRarity = statsForRarity

----------------------------------------------------------------
-- CARD DATA
----------------------------------------------------------------

CardDefinitions.Data = {
	SmokeMarine = {
		id = "SmokeMarine", name = "Smoke Marine", baseRarity = 400,
		faction = "Voyagers", tags = { "Marine", "Smoke" },
		passive = "SmokeGuard", art = "rbxassetid://138936516719337",
	},
	AlligatorPirate = {
		id = "AlligatorPirate", name = "Alligator Pirate", baseRarity = 500,
		faction = "Voyagers", tags = { "Pirate", "Sand" },
		passive = "SandDrain", art = "rbxassetid://82821534254625",
	},
	HunterFreecss = {
		id = "HunterFreecss", name = "Hunter Freecss", baseRarity = 300,
		faction = "SpiritWilds", tags = { "Hunter" },
		passive = "RockPunch", art = "rbxassetid://85401455998618",
	},
	HunterZoldyck = {
		id = "HunterZoldyck", name = "Hunter Zoldyck", baseRarity = 300,
		faction = "SpiritWilds", tags = { "Hunter", "Lightning" },
		passive = "HunterLightningStrike", art = "",
		-- Portrait upload pending: Roblox returned account moderation (403).
	},
	ArsenalMaster = {
		id = "ArsenalMaster", name = "Arsenal Master", baseRarity = 300,
		faction = "SpiritWilds", tags = { "Hunter", "Weapon", "Master" },
		passive = "LuckyWeapon", art = "",
		-- Portrait upload pending: Roblox returned account moderation (403).
	},
	CyberBandit = {
		id = "CyberBandit", name = "Cyber Bandit", baseRarity = 1000,
		faction = "IronReach", tags = { "Cyborg", "Bulwark" },
		passive = "SecondLife", art = "",
		-- Portrait upload pending: Roblox returned account moderation (403).
	},
	CyberGhost = {
		id = "CyberGhost", name = "Cyber Ghost", baseRarity = 900,
		faction = "IronReach", tags = { "Cyborg", "Hacker" },
		passive = "SystemHack", art = "",
		-- Portrait upload pending: Roblox returned account moderation (403).
	},
	TheMassiah = {
		id = "TheMassiah", name = "The Massiah", baseRarity = 1000,
		faction = "Duskmarch", tags = { "Divine", "Mark" },
		passive = "HandFromGod", art = "rbxassetid://105997473642766",
	},
	RivalOfTheGod = {
		id = "RivalOfTheGod", name = "Rival of the God", baseRarity = 400,
		faction = "Duskmarch", tags = { "Tactician" },
		passive = "Smarter", art = "rbxassetid://107687667664462",
	},

	------------------------------------------------------------
	-- COMMON
	------------------------------------------------------------

	Usopp = {
		id = "Usopp",
		name = "Pirate Sniper",

		baseRarity = 2,

		faction = "Voyagers",

		tags = {
			"Sniper",
			"Trickster",
		},

		passive = "PerfectShot",

		art = "rbxassetid://127806938672058",
	},

	Nami = {
		id = "Nami",
		name = "Weather Girl",

		baseRarity = 3,

		faction = "Voyagers",

		tags = {
			"Weather",
			"Sustain",
		},

		passive = "RainMercy",

		art = "rbxassetid://112705830070867",
	},

	Duffy = {
		id = "Duffy",
		name = "Duffy",

		baseRarity = 4,

		faction = "SpiritWilds",

		tags = {
			"Rubber",
		},

		passive = "ElasticArm",

		art = "rbxassetid://86321017642356",
	},

	Zoro = {
		id = "Zoro",
		name = "Devil Swordsman",

		baseRarity = 5,

		faction = "Voyagers",

		tags = {
			"Blade",
			"Bleed",
		},

		passive = "TwoSwordsStyle",

		art = "rbxassetid://100627062247474",
	},

	------------------------------------------------------------
	-- UNCOMMON
	------------------------------------------------------------

	Franky = {
		id = "Franky",
		name = "Cola Cyborg",

		baseRarity = 10,

		faction = "Voyagers",

		tags = {
			"Cyborg",
			"Bruiser",
		},

		passive = "ColaOverload",

		art = "rbxassetid://106391252937677",
	},

	Chopper = {
		id = "Chopper",
		name = "Dear Doctor",

		baseRarity = 15,

		faction = "Voyagers",

		tags = {
			"Doctor",
			"Support",
		},

		passive = "PartingDose",

		art = "rbxassetid://71410153941533",
	},

	Sanji = {
		id = "Sanji",
		name = "Pirate Cook",

		baseRarity = 25,

		faction = "Voyagers",

		tags = {
			"Flame",
			"Burn",
		},

		passive = "DevilsLeg",

		art = "rbxassetid://88731221312517",
	},

	------------------------------------------------------------
	-- RARE
	------------------------------------------------------------

	Arlong = {
		id = "Arlong",
		name = "Pirate Shark",

		baseRarity = 50,

		-- BOSS. Levels past the normal 100 ceiling, which is why Elder Essence V
		-- still has somewhere to go on this card after IV has topped out a normal
		-- one. Any card can join by adding this line; nothing else needs editing.
		maxLevel = 120,

		faction = "Tidebound",

		tags = {
			"Fishman",
			"Bleed",
		},

		passive = "SliceAndDice",

		art = "rbxassetid://98836414183238",
	},

	------------------------------------------------------------
	-- VERY RARE
	------------------------------------------------------------

	-- IMPORTANT:
	-- Keep the id as "Robin".
	-- Your save data uses the ID.
	-- Only the displayed name was changed.
	Robin = {
		id = "Robin",
		name = "Dragon Warrior",

		baseRarity = 100,

		faction = "Voyagers",

		tags = {
			"Dragon",
			"Bulwark",
		},

		passive = "WillOfTheDragon",

		art = "rbxassetid://76512085014783",
	},

	------------------------------------------------------------
	-- MASTERS & DEMONS
	--
	-- Every card below is rarer than the whole roster above it, so the stat
	-- curve places all six over Dragon Warrior. That is the rule working, not
	-- a mistake: rarity IS the stat line.
	--
	-- Two of these read each other by NAME at runtime. Forge and Power Within
	-- both count party members whose name contains "master", so renaming any of
	-- these four quietly changes what those abilities are worth.
	------------------------------------------------------------

	HumanlyDemon = {
		id = "HumanlyDemon",
		name = "Humanly Demon",

		baseRarity = 750,

		faction = "Demons",

		tags = {
			"Demon",
			"Inheritor",
		},

		passive = "LastHope",

		art = "rbxassetid://101901645129707",
	},

	LightningMaster = {
		id = "LightningMaster",
		name = "Lightning Master",

		baseRarity = 950,

		faction = "Masters",

		tags = {
			"Master",
			"Lightning",
			"Stun",
		},

		passive = "LightningStrike",

		art = "rbxassetid://78168313489266",
	},

	-- LastHope looks this card up by the id "MasterOfBoth". Changing the id
	-- breaks that link silently - the condition would simply stop matching.
	MasterOfBoth = {
		id = "MasterOfBoth",
		name = "Master of Both",

		baseRarity = 1000,

		faction = "Masters",

		tags = {
			"Master",
			"Water",
			"Flame",
		},

		passive = "WaterAndFire",

		art = "rbxassetid://75616173445342",
	},

	MoonDemon = {
		id = "MoonDemon",
		name = "Moon Demon",

		baseRarity = 3000,

		faction = "Demons",

		tags = {
			"Demon",
			"Moon",
			"Bulwark",
		},

		passive = "Redirect",

		art = "rbxassetid://102035509051724",
	},

	FlameMaster = {
		id = "FlameMaster",
		name = "Flame Master",

		baseRarity = 5000,

		faction = "Masters",

		tags = {
			"Master",
			"Flame",
		},

		passive = "PowerWithin",

		art = "rbxassetid://106925049719467",
	},

	WeaponMaster = {
		id = "WeaponMaster",
		name = "Weapon Master",

		baseRarity = 7000,

		faction = "Masters",

		tags = {
			"Master",
			"Weapon",
			"Commander",
		},

		passive = "Forge",

		art = "rbxassetid://97996597225855",
	},

	------------------------------------------------------------
	-- THE SON LINE & THE MACHINES
	--
	-- The rarest band in the game: every card here out-scales Weapon Master,
	-- because rarity IS the stat line and these are printed above it.
	--
	-- "Son Warrior" is READ BY NAME at runtime. The Prideful Prince raises him
	-- alongside itself and Son Prodigy changes its whole payout when he is in
	-- the deck, and both reach him through his ID - so renaming the id breaks
	-- two other cards, while renaming only the display name is safe.
	------------------------------------------------------------

	SonWarrior = {
		id = "SonWarrior",
		name = "Son Warrior",

		baseRarity = 15000,

		faction = "Ascendants",

		tags = {
			"Son",
			"Beam",
			"Vanguard",
		},

		passive = "TheFirstOfMany",

		art = "rbxassetid://95501165116730",
	},

	PridefulPrince = {
		id = "PridefulPrince",
		name = "The Prideful Prince",

		baseRarity = 17000,

		faction = "Ascendants",

		tags = {
			"Prince",
			"Pride",
			"Growth",
		},

		passive = "YouAreNumberOne",

		art = "rbxassetid://101470172589738",
	},

	AndroidMentor = {
		id = "AndroidMentor",
		name = "Android Mentor",

		baseRarity = 24000,

		faction = "IronReach",

		tags = {
			"Machine",
			"Confusion",
			"Volatile",
		},

		passive = "WillOfTheMachine",

		art = "rbxassetid://80093721693906",
	},

	FutureWarrior = {
		id = "FutureWarrior",
		name = "Future Warrior",

		baseRarity = 30000,

		faction = "Ascendants",

		tags = {
			"Son",
			"Beam",
			"Timeline",
		},

		passive = "SaveTheFuture",

		art = "rbxassetid://92263520255774",
	},

	DevouringBug = {
		id = "DevouringBug",
		name = "Devouring Bug",

		baseRarity = 36000,

		faction = "IronReach",

		tags = {
			"Bio",
			"Absorb",
			"Volatile",
		},

		passive = "MorePower",

		art = "rbxassetid://125361061501568",
	},

	SonProdigy = {
		id = "SonProdigy",
		name = "Son Prodigy",

		baseRarity = 50000,

		faction = "Ascendants",

		tags = {
			"Son",
			"Prodigy",
			"Finisher",
		},

		passive = "FinalBlast",

		art = "rbxassetid://80578074143430",
	},
	-- Shinigami roster. Stats and variants use the existing rarity curve.
	NumberOne = {
		id = "NumberOne", name = "Number One", baseRarity = 70000,
		faction = "SpiritWilds", tags = { "Shinigami" },
		passive = "RunAndGun", art = "rbxassetid://128915555897578",
	},
	IceShinigami = {
		id = "IceShinigami", name = "Ice Shinigami", baseRarity = 45000,
		faction = "SpiritWilds", tags = { "Shinigami" },
		passive = "ShinigamiFreeze", art = "rbxassetid://74863485732337",
	},
	EyepatchShinigami = {
		id = "EyepatchShinigami", name = "Eyepatch Shinigami", baseRarity = 60000,
		faction = "SpiritWilds", tags = { "Shinigami" },
		passive = "HungerForBattle", art = "rbxassetid://121669360651044",
	},
	OtherwordlyShinigami = {
		id = "OtherwordlyShinigami", name = "Otherwordly Shinigami", baseRarity = 85000,
		faction = "SpiritWilds", tags = { "Shinigami" },
		passive = "ShinigamiDoubleStrike", art = "rbxassetid://75171474988075",
	},
	CaptainOfBoth = {
		id = "CaptainOfBoth", name = "Captain of Both", baseRarity = 100000,
		faction = "SpiritWilds", tags = { "Shinigami" },
		passive = "MasterManipulator", art = "rbxassetid://105974994018572",
	},
	GrimGhost = {
		id = "GrimGhost", name = "Grim Ghost", baseRarity = 55000,
		faction = "SpiritWilds", tags = { "Shinigami" },
		passive = "SlashSlashSlash", art = "rbxassetid://93756284305819",
	},
}

----------------------------------------------------------------
-- SORT CARDS FROM MOST COMMON -> RAREST
----------------------------------------------------------------

local commonToRare = {}

for id in pairs(CardDefinitions.Data) do
	table.insert(commonToRare, id)
end

table.sort(commonToRare, function(a, b)

	local rarityA =
		CardDefinitions.Data[a].baseRarity

	local rarityB =
		CardDefinitions.Data[b].baseRarity

	if rarityA ~= rarityB then
		return rarityA < rarityB
	end

	return a < b
end)

----------------------------------------------------------------
-- ASSIGN STATS
----------------------------------------------------------------

-- These variables make the rarity hierarchy STRICT.
--
-- Even if two nearby rarity values round to the same stat,
-- the rarer card will always receive at least +1.

local previousDMG = 0
local previousHP = 0
local previousRarity = -1

for _, id in ipairs(commonToRare) do

	local def =
		CardDefinitions.Data[id]

	local dmg, hp =
		statsForRarity(def.baseRarity)

	------------------------------------------------------------
	-- Guarantee rarer cards are stronger
	------------------------------------------------------------

	if def.baseRarity > previousRarity then

		if previousDMG > 0 then
			dmg =
				math.max(
					dmg,
					previousDMG + 1
				)
		end

		if previousHP > 0 then
			hp =
				math.max(
					hp,
					previousHP + 1
				)
		end
	end

	def.baseDMG = dmg
	def.baseHP = hp

	previousDMG = dmg
	previousHP = hp
	previousRarity = def.baseRarity
end

----------------------------------------------------------------
-- RAREST-FIRST LIST
----------------------------------------------------------------

local rarestFirst = {}

for index = #commonToRare, 1, -1 do
	table.insert(
		rarestFirst,
		commonToRare[index]
	)
end

CardDefinitions.RarestFirst =
	rarestFirst

CardDefinitions.MostCommonId =
	commonToRare[1]

----------------------------------------------------------------
-- PUBLIC FUNCTIONS
----------------------------------------------------------------

function CardDefinitions.get(id: string)

	return CardDefinitions.Data[id]
end

function CardDefinitions.exists(id: string): boolean

	return CardDefinitions.Data[id] ~= nil
end

-- How far this card can be levelled. Everything answers 100 unless it opted
-- into a higher ceiling, so callers never need to know which cards are bosses -
-- they just ask, and the stat curve, the level gate and the UI all agree
-- because they are all reading this one function.
function CardDefinitions.maxLevel(id: string): number
	local def = CardDefinitions.Data[id]
	local ceiling = GameConfig.BossCardLevel or GameConfig.MaxCardLevel
	if def and def.maxLevel then
		return math.min(def.maxLevel, ceiling)
	end
	return GameConfig.MaxCardLevel
end

return CardDefinitions
