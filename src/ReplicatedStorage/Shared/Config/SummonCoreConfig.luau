--!strict
-- Summon Cores: every number the Card Forge uses, in one table.
--
-- WHAT A CORE IS
-- An ITEM, not a card. Cores sit in the Backpack (profile.summonCores), are
-- upgraded one stage at a time at the Card Forge, and are consumed when opened
-- for exactly one card. The normal Roll button is untouched: this is a second,
-- separate way to roll.
--
-- THE LADDER
-- Five families, each with its own art. Basic, Gilded, Divine and Secret run
-- I-IV and Cosmic runs I-V, so there are 21 stages and Cosmic V is the top.
-- The art is shared by every level of a family; the level numeral is drawn on
-- top of it by the UI, never baked into the image.
--
-- ODDS AND GUARANTEES
-- Opening a core uses the normal distribution with multiplied luck:
--
--     effective luck = the player's luck (skill tree) x stage.luck
--
-- and the pick goes through RollService.PickOutcome: the same outcome table,
-- the same rarest-first "luck / effective rarity" rule and the same encounter
-- unlock gates as the Roll button. Outcomes below the minimum are excluded;
-- the remaining probabilities are normalized, preserving their relative odds.
-- The lucky-roll x2 does not apply and stats.totalRolls is not touched.
-- Guarantees scale with player luck and stop at the rarest unlocked outcome.
--
-- UPGRADING
-- Each step costs forge items (UPGRADE_COSTS below): Elder Core Essence for
-- Basic I -> II -> III -> IV, and an Elder Wrench for Basic IV -> Gilded I. A
-- stage with no cost listed is LOCKED - players see "Coming soon" - until its
-- cost is designed. Devs (isDev) can still push a locked stage for free while
-- DevBypassLocked is on, so the whole ladder stays testable.
--
-- WHERE THINGS COME FROM
-- EncounterDrops below: Pirate Shark (encounter "Arlong") pays a core, some
-- Elder Core Essence and, on Cosmic, an Elder Wrench on EVERY win.
--
-- SAVE DATA
-- profile.summonCores = { [stage id] = count } and
-- profile.forgeItems  = { [item id]  = count }. Stage ids ("Basic1" ..
-- "Cosmic5") and item ids ("CoreEssenceBasic", "ElderWrench", ...) are WRITTEN
-- INTO SAVES: renaming one orphans everything of that kind a player owns and
-- needs a DataService migration. Names, colours, art, costs and luck numbers
-- are presentation/balance and can change freely.

local RunService = game:GetService("RunService")

local GameConfig = require(script.Parent.GameConfig)
local CardDefinitions = require(script.Parent.CardDefinitions)
local SupportDefinitions = require(script.Parent.SupportDefinitions)
local VariantConfig = require(script.Parent.VariantConfig)
local EncounterModes = require(script.Parent.EncounterModes)

local SummonCoreConfig = {}

-- Floor = player luck x core boost x 10. Gilded I at 1,000 luck guarantees
-- 100,000 effective rarity. Both server rewards and UI read this same rule.
SummonCoreConfig.MinimumRarityPerEffectiveLuck = 10

-- Devs (owner, listed ids, Studio) may upgrade LOCKED stages for free, so the
-- ladder past Gilded I can be tested before its costs exist. Stages that HAVE a
-- cost always charge it, devs included - that is the flow players get.
SummonCoreConfig.DevBypassLocked = true

-- Server-side pacing. Opening plays a roulette that lasts several seconds, so
-- a second open request inside this window is refused rather than queued.
SummonCoreConfig.OpenCooldown = 1.5
SummonCoreConfig.UpgradeCooldown = 0.3

-- Sanity cap on a single stack, so a bad dev command cannot write a silly number
-- into a save.
SummonCoreConfig.MaxCount = 9999

-- A rare pull from a core is announced server-wide like a rare roll, but only
-- once the roulette has had time to land, so the bar never spoils it.
SummonCoreConfig.AnnounceDelay = 7.5

-- Dev tools (forge DEV buttons, chat commands). The server checks this again;
-- the client only uses it to decide whether to draw the buttons.
SummonCoreConfig.DevUserIds = {
	[148861292] = true, -- origggg
}
SummonCoreConfig.DevGiveMax = 100
SummonCoreConfig.DevQuickGive = { "Basic1", "Gilded4", "Divine3", "Secret4", "Cosmic5" }

----------------------------------------------------------------------
-- families
----------------------------------------------------------------------
-- `variant` is the card tier whose border (Shine) and text gradient
-- (TextShine) a core of this family borrows in the UI - presentation only.
-- `colour` is the family's flat UI colour. `model` recolours the 3D core that
-- floats on the forge (client-side, while a player is using it).
SummonCoreConfig.FamilyOrder = { "Basic", "Gilded", "Divine", "Secret", "Cosmic" }

SummonCoreConfig.Families = {
	Basic = {
		id = "Basic", display = "Basic", order = 1, maxLevel = 4,
		image = "rbxassetid://102747563047431",
		variant = "Standard",
		colour = Color3.fromRGB(205, 211, 224),
		model = {
			frame = Color3.fromRGB(150, 156, 168),
			trim = Color3.fromRGB(205, 210, 220),
			glow = Color3.fromRGB(235, 242, 255),
		},
	},
	Gilded = {
		id = "Gilded", display = "Gilded", order = 2, maxLevel = 4,
		image = "rbxassetid://125653399861473",
		variant = "Gilded",
		colour = Color3.fromRGB(255, 200, 70),
		model = {
			frame = Color3.fromRGB(205, 150, 35),
			trim = Color3.fromRGB(255, 205, 90),
			glow = Color3.fromRGB(255, 220, 120),
		},
	},
	Divine = {
		id = "Divine", display = "Divine", order = 3, maxLevel = 4,
		image = "rbxassetid://95835260381275",
		variant = "Astral",
		colour = Color3.fromRGB(90, 190, 255),
		model = {
			frame = Color3.fromRGB(35, 110, 225),
			trim = Color3.fromRGB(90, 180, 255),
			glow = Color3.fromRGB(140, 225, 255),
		},
	},
	Secret = {
		id = "Secret", display = "Secret", order = 4, maxLevel = 4,
		image = "rbxassetid://90979292841800",
		variant = "Transcendent",
		colour = Color3.fromRGB(255, 88, 96),
		model = {
			frame = Color3.fromRGB(190, 28, 45),
			trim = Color3.fromRGB(255, 90, 100),
			glow = Color3.fromRGB(255, 130, 140),
		},
	},
	Cosmic = {
		id = "Cosmic", display = "Cosmic", order = 5, maxLevel = 5,
		image = "rbxassetid://125315913556331",
		variant = "Cosmic",
		colour = Color3.fromRGB(196, 132, 255),
		model = {
			frame = Color3.fromRGB(110, 50, 210),
			trim = Color3.fromRGB(200, 110, 255),
			glow = Color3.fromRGB(170, 235, 255),
		},
	},
}

-- The body of the 3D core is the same dark metal for every family.
SummonCoreConfig.ModelBody = Color3.fromRGB(20, 22, 30)

----------------------------------------------------------------------
-- forge items
----------------------------------------------------------------------
-- Materials spent at the Card Forge. `active = false` items have their art
-- uploaded but nothing uses them yet (the essences for the higher families,
-- kept ready for when those upgrade costs are designed): they never drop and
-- never show in the Backpack. There is no Gilded essence art yet.
export type Item = {
	id: string,
	name: string,
	shortName: string,
	image: string,
	variant: string,
	colour: Color3,
	description: string,
	use: string,
	source: string,
	active: boolean,
	order: number,
}

SummonCoreConfig.Items = {
	CoreEssenceBasic = {
		id = "CoreEssenceBasic", name = "Elder Core Essence", shortName = "Core Essence",
		image = "rbxassetid://86556004471515", variant = "Standard",
		colour = Color3.fromRGB(214, 222, 240),
		description = "Condensed forge energy. Pour it into a Basic Summon Core at the Card Forge to raise its level.",
		use = "Basic I \u{2192} IV", source = "Pirate Shark", active = true, order = 1,
	},
	ElderWrench = {
		id = "ElderWrench", name = "Elder Wrench", shortName = "Elder Wrench",
		image = "rbxassetid://98805154705930", variant = "Cosmic",
		colour = Color3.fromRGB(226, 232, 255),
		description = "An ancient forging tool. Reforges a Basic Summon Core IV into a Gilded Summon Core I.",
		use = "Basic IV \u{2192} Gilded I", source = "Pirate Shark (Cosmic)", active = true, order = 2,
	},
	CoreEssenceDivine = {
		id = "CoreEssenceDivine", name = "Divine Core Essence", shortName = "Divine Essence",
		image = "rbxassetid://110812702844542", variant = "Astral",
		colour = Color3.fromRGB(90, 190, 255),
		description = "Not in use yet.", use = "Divine cores", source = "-", active = false, order = 3,
	},
	CoreEssenceSecret = {
		id = "CoreEssenceSecret", name = "Secret Core Essence", shortName = "Secret Essence",
		image = "rbxassetid://135107929097455", variant = "Transcendent",
		colour = Color3.fromRGB(255, 88, 96),
		description = "Not in use yet.", use = "Secret cores", source = "-", active = false, order = 4,
	},
	CoreEssenceCosmic = {
		id = "CoreEssenceCosmic", name = "Cosmic Core Essence", shortName = "Cosmic Essence",
		image = "rbxassetid://71515424226176", variant = "Cosmic",
		colour = Color3.fromRGB(196, 132, 255),
		description = "Not in use yet.", use = "Cosmic cores", source = "-", active = false, order = 5,
	},
} :: { [string]: Item }

SummonCoreConfig.ItemOrder = { "CoreEssenceBasic", "ElderWrench", "CoreEssenceDivine", "CoreEssenceSecret", "CoreEssenceCosmic" }

----------------------------------------------------------------------
-- upgrade costs
----------------------------------------------------------------------
-- What moving FROM a stage to the next costs, in forge items. A stage that is
-- not listed (and is not the top) is LOCKED until its cost is designed.
local UPGRADE_COSTS: { [string]: { [string]: number } } = {
	Basic1 = { CoreEssenceBasic = 1 },
	Basic2 = { CoreEssenceBasic = 2 },
	Basic3 = { CoreEssenceBasic = 3 },
	Basic4 = { ElderWrench = 1 },
}

----------------------------------------------------------------------
-- the 21 stages, in upgrade order
----------------------------------------------------------------------
-- luck    how many times the player's own luck this core rolls with
--         also scales this stage's minimum final rarity
local STAGES: { { any } } = {
	--  family    lvl  luck
	{ "Basic",   1, 1.5 },
	{ "Basic",   2, 2 },
	{ "Basic",   3, 3 },
	{ "Basic",   4, 4 },
	{ "Gilded",  1, 10 },
	{ "Gilded",  2, 15 },
	{ "Gilded",  3, 25 },
	{ "Gilded",  4, 40 },
	{ "Divine",  1, 150 },
	{ "Divine",  2, 250 },
	{ "Divine",  3, 400 },
	{ "Divine",  4, 650 },
	{ "Secret",  1, 3000 },
	{ "Secret",  2, 5000 },
	{ "Secret",  3, 8000 },
	{ "Secret",  4, 13000 },
	{ "Cosmic",  1, 75000 },
	{ "Cosmic",  2, 150000 },
	{ "Cosmic",  3, 300000 },
	{ "Cosmic",  4, 600000 },
	{ "Cosmic",  5, 1500000 },
}

local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }

function SummonCoreConfig.roman(n: number): string
	return ROMAN[n] or tostring(n)
end

-- 1.5 -> "1.5", 13000 -> "13,000"
function SummonCoreConfig.formatBoost(n: number): string
	if n % 1 ~= 0 then
		return (string.format("%.2f", n):gsub("0+$", ""):gsub("%.$", ""))
	end
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

export type Stage = {
	id: string,
	index: number,
	family: string,
	level: number,
	numeral: string,
	name: string,
	shortName: string,
	luck: number,
	image: string,
	variant: string,
	colour: Color3,
	isMax: boolean,
	description: string,
	upgrade: { cost: { [string]: number }?, locked: boolean, successChance: number },
}

SummonCoreConfig.Stages = {} :: { Stage }
SummonCoreConfig.ById = {} :: { [string]: Stage }

for index, row in ipairs(STAGES) do
	local familyId, level, luck = row[1], row[2], row[3]
	local family = SummonCoreConfig.Families[familyId]
	local numeral = SummonCoreConfig.roman(level)
	local id = familyId .. tostring(level)
	local isMax = index == #STAGES
	local cost = UPGRADE_COSTS[id]
	local stage: Stage = {
		id = id,
		index = index,
		family = familyId,
		level = level,
		numeral = numeral,
		name = ("%s Summon Core %s"):format(family.display, numeral),
		shortName = ("%s %s"):format(family.display, numeral),
		luck = luck,
		image = family.image,
		variant = family.variant,
		colour = family.colour,
		isMax = isMax,
		description = "",
		upgrade = { cost = cost, locked = cost == nil and not isMax, successChance = 1 },
	}
	if stage.isMax then
		stage.description = ("The top of the forge. Opens into one card, rolled with your luck x%s.")
			:format(SummonCoreConfig.formatBoost(luck))
	else
		stage.description = ("Opens into one card, rolled with your luck x%s. Upgrade it at the Card Forge for a stronger roll.")
			:format(SummonCoreConfig.formatBoost(luck))
	end
	SummonCoreConfig.Stages[index] = stage
	SummonCoreConfig.ById[stage.id] = stage
end

SummonCoreConfig.MaxIndex = #SummonCoreConfig.Stages

----------------------------------------------------------------------
-- encounter drops
----------------------------------------------------------------------
-- Paid on EVERY win of that encounter and stage, the first clear included,
-- on top of the Elder Coins. Keyed by encounter id, then difficulty.
SummonCoreConfig.EncounterDrops = {
	-- Pirate Shark.
	Arlong = {
		Easy       = { cores = { Basic1 = 1 }, items = { CoreEssenceBasic = 1 } },
		Medium     = { cores = { Basic1 = 1 }, items = { CoreEssenceBasic = 1 } },
		Hard       = { cores = { Basic1 = 1 }, items = { CoreEssenceBasic = 2 } },
		Impossible = { cores = { Basic4 = 1 }, items = { CoreEssenceBasic = 3 } },
		Cosmic     = { cores = { Basic4 = 1 }, items = { CoreEssenceBasic = 5, ElderWrench = 1 } },
	},
}

----------------------------------------------------------------------
-- lookups
----------------------------------------------------------------------

function SummonCoreConfig.get(id: string?): Stage?
	if type(id) ~= "string" then return nil end
	return SummonCoreConfig.ById[id]
end

-- Uses the same derived profile value as the regular-roll HUD and server.
function SummonCoreConfig.playerLuck(profile: any): number
	local upgrades = profile and profile.upgrades
	local luck = 1 + ((upgrades and tonumber(upgrades.luck)) or 0) * GameConfig.LuckPerLevel
	if luck ~= luck or luck == math.huge then return 1 end
	return math.max(1, luck)
end

-- A guarantee never bypasses encounter gates or promises an unavailable rarity.
-- nil clears is reserved for fully-unlocked diagnostic tools; live callers use {}.
function SummonCoreConfig.minimumRarity(stageId: string, playerLuck: number, clears: any): number
	local stage = SummonCoreConfig.get(stageId)
	if not stage then return 0 end
	local luck = tonumber(playerLuck) or 1
	if luck ~= luck or luck == math.huge then luck = 1 end
	luck = math.max(1, luck)
	local highestVariant = 1
	for _, id in ipairs(VariantConfig.Order) do
		local variant = VariantConfig.get(id)
		if not variant.presentationOnly then
			highestVariant = math.max(highestVariant, variant.rarityMultiplier)
		end
	end
	local highest = 0
	for id, def in pairs(CardDefinitions.Data) do
		if clears == nil or EncounterModes.isUnlocked(id, clears) then
			highest = math.max(highest, def.baseRarity * highestVariant)
		end
	end
	for id, def in pairs(SupportDefinitions.Data) do
		if clears == nil or EncounterModes.isUnlocked(id, clears) then
			highest = math.max(highest, def.baseRarity)
		end
	end
	return math.min(highest, math.max(1, math.floor(luck * stage.luck * SummonCoreConfig.MinimumRarityPerEffectiveLuck)))
end

function SummonCoreConfig.at(index: number): Stage?
	return SummonCoreConfig.Stages[index]
end

function SummonCoreConfig.find(familyId: string, level: number): Stage?
	return SummonCoreConfig.ById[familyId .. tostring(level)]
end

function SummonCoreConfig.nextOf(id: string): Stage?
	local stage = SummonCoreConfig.get(id)
	return stage and SummonCoreConfig.Stages[stage.index + 1] or nil
end

function SummonCoreConfig.family(id: string)
	local stage = SummonCoreConfig.get(id)
	return stage and SummonCoreConfig.Families[stage.family] or nil
end

function SummonCoreConfig.item(id: string?): Item?
	if type(id) ~= "string" then return nil end
	return SummonCoreConfig.Items[id]
end

-- How many of a stage a profile holds. Tolerates a profile saved before cores
-- existed (no summonCores table at all).
function SummonCoreConfig.count(profile: any, id: string): number
	local cores = profile and profile.summonCores
	if type(cores) ~= "table" then return 0 end
	return math.max(0, math.floor(tonumber(cores[id]) or 0))
end

-- How many of a forge item a profile holds.
function SummonCoreConfig.itemCount(profile: any, id: string): number
	local items = profile and profile.forgeItems
	if type(items) ~= "table" then return 0 end
	return math.max(0, math.floor(tonumber(items[id]) or 0))
end

-- Every stage the profile owns at least one of, lowest stage first.
function SummonCoreConfig.owned(profile: any): { { stage: Stage, count: number } }
	local list = {}
	for _, stage in ipairs(SummonCoreConfig.Stages) do
		local n = SummonCoreConfig.count(profile, stage.id)
		if n > 0 then
			table.insert(list, { stage = stage, count = n })
		end
	end
	return list
end

-- Every ACTIVE forge item the profile holds at least one of, in ItemOrder.
function SummonCoreConfig.ownedItems(profile: any): { { item: Item, count: number } }
	local list = {}
	for _, id in ipairs(SummonCoreConfig.ItemOrder) do
		local item = SummonCoreConfig.Items[id]
		local n = SummonCoreConfig.itemCount(profile, id)
		if item and item.active and n > 0 then
			table.insert(list, { item = item, count = n })
		end
	end
	return list
end

function SummonCoreConfig.total(profile: any): number
	local n = 0
	for _, entry in ipairs(SummonCoreConfig.owned(profile)) do
		n += entry.count
	end
	return n
end

-- A stage's upgrade cost as an ordered list: { { item, amount }, ... }.
-- Empty for a locked stage or the top.
function SummonCoreConfig.costList(stageId: string): { { item: Item, amount: number } }
	local stage = SummonCoreConfig.get(stageId)
	local list = {}
	local cost = stage and stage.upgrade.cost
	if not cost then return list end
	for _, id in ipairs(SummonCoreConfig.ItemOrder) do
		local amount = cost[id]
		local item = SummonCoreConfig.Items[id]
		if amount and amount > 0 and item then
			table.insert(list, { item = item, amount = amount })
		end
	end
	return list
end

-- Whether `profile` can pay a stage's upgrade cost right now.
function SummonCoreConfig.canAfford(profile: any, stageId: string): boolean
	for _, entry in ipairs(SummonCoreConfig.costList(stageId)) do
		if SummonCoreConfig.itemCount(profile, entry.item.id) < entry.amount then return false end
	end
	return true
end

-- What a win pays, as an ordered list for display and granting:
-- { { kind = "core" | "item", id, amount, name, image, variant }, ... }.
function SummonCoreConfig.dropsFor(encounterId: string?, difficulty: string?): { any }
	local list = {}
	local byEncounter = encounterId and SummonCoreConfig.EncounterDrops[encounterId]
	local spec = byEncounter and difficulty and byEncounter[difficulty]
	if not spec then return list end
	for _, stage in ipairs(SummonCoreConfig.Stages) do
		local amount = spec.cores and spec.cores[stage.id]
		if amount and amount > 0 then
			table.insert(list, { kind = "core", id = stage.id, amount = amount, name = stage.name,
				shortName = stage.shortName, image = stage.image, variant = stage.variant })
		end
	end
	for _, id in ipairs(SummonCoreConfig.ItemOrder) do
		local amount = spec.items and spec.items[id]
		local item = SummonCoreConfig.Items[id]
		if amount and amount > 0 and item then
			table.insert(list, { kind = "item", id = id, amount = amount, name = item.name,
				shortName = item.shortName, image = item.image, variant = item.variant })
		end
	end
	return list
end

-- Reads a core from loose text, for chat and debug commands. Accepts
-- "cosmic5", "Cosmic 5", "cosmic v", "c5", "gilded IV" or a plain stage number
-- "1".."21". A trailing number after the level is returned as a count:
-- "gilded 4 3" -> Gilded IV, 3.
function SummonCoreConfig.parse(text: string?): (Stage?, number?)
	if type(text) ~= "string" then return nil, nil end
	local s = string.lower(text):gsub("^%s+", ""):gsub("%s+$", "")

	local index, rest = s:match("^(%d+)%s*(%d*)$")
	if index then
		return SummonCoreConfig.Stages[tonumber(index) :: number], tonumber(rest)
	end

	local word, levelText, countText = s:match("^(%a+)%s*(%d+)%s*(%d*)$")
	local level = levelText and tonumber(levelText)
	if not word then
		local romanText
		word, romanText, countText = s:match("^(%a+)%s+([ivx]+)%s*(%d*)$")
		if word then
			for i, numeral in ipairs(ROMAN) do
				if numeral:lower() == romanText then level = i end
			end
		end
	end
	if not word or not level then return nil, nil end

	for _, familyId in ipairs(SummonCoreConfig.FamilyOrder) do
		if familyId:lower():sub(1, #word) == word then
			return SummonCoreConfig.find(familyId, level :: number), tonumber(countText)
		end
	end
	return nil, nil
end

-- Owner, listed dev, or any Studio test session. The server makes the same
-- check before honouring a dev action; the client uses it only to decide
-- whether to draw the DEV buttons.
function SummonCoreConfig.isDev(player: Player?): boolean
	if not player then return false end
	if SummonCoreConfig.DevUserIds[player.UserId] then return true end
	if game.CreatorType == Enum.CreatorType.User and game.CreatorId == player.UserId then return true end
	return RunService:IsStudio()
end

return SummonCoreConfig
