--!strict
-- THE SKILL TREE, as data.
--
-- COST AND EFFECT ARE FUNCTIONS OF RANK, NOT LISTS.
-- They used to be arrays with one entry per rank, which was fine at MaxRank 5
-- and impossible at MaxRank 3000 - nobody is hand-writing three thousand costs,
-- and the table would dwarf the rest of the config. A function is also the only
-- way to retune a curve without rewriting every entry.
--
--   Cost(rank)         coins to buy THAT rank (rank 1 is the first purchase)
--   EffectValue(rank)   the effect TOTAL at that rank, not an increment
--
-- FIELDS
--   Name / Description  shown on the node and in the details panel
--   Icon                asset id for the node face; empty falls back to Glyph
--   Glyph               placeholder face. ONLY use glyphs the game font has:
--                       ● ★ ▲ ■ ◆ ◉ ◎ ♦ ♣ ❀ ✿ ❖ ⚔ » are verified present;
--                       ✦ ⇉ ➤ ✹ ✺ are MISSING and render as a blank node.
--   Category            "Luck" | "Coin" | "Stat" | "Elder". Drives the node
--                       colour AND the details panel's border, so the two can
--                       never disagree.
--   Position            STUDS on the board. X right, Y down. A node at
--                       Vector2.new(500, 250) is generated exactly there and its
--                       connections and the camera bounds follow automatically.
--   MaxRank             how many times it can be bought
--   Requirements        { OtherSkillId = minimumRank }, ALL must be satisfied
--   EffectType          a key in SkillEffects.Registry

local SkillDefinitions = {}

-- Category colours. Green for luck, yellow for coins, red for stats, and Elder
-- is drawn as a travelling rainbow rather than a flat colour - the constant here
-- is only its fallback for anything that needs a single value.
local LUCK  = Color3.fromRGB(90, 235, 130)
local COIN  = Color3.fromRGB(255, 205, 70)
local STAT  = Color3.fromRGB(255, 95, 95)
local ELDER = Color3.fromRGB(200, 140, 255)

SkillDefinitions.CategoryColour = {
	Luck = LUCK,
	Coin = COIN,
	Stat = STAT,
	Elder = ELDER,
}

-- Elder is the only rainbow category. Kept as a flag rather than as a colour so
-- every renderer decides for itself how to animate it.
SkillDefinitions.RainbowCategory = "Elder"

----------------------------------------------------------------------
-- CURVE BUILDERS
----------------------------------------------------------------------

-- Cost starts at `base` and rises by `step` every `per` ranks. Stepping rather
-- than rising every rank keeps early ranks buyable in bulk while the late game
-- still bites.
local function steppedCost(base: number, step: number, per: number)
	return function(rank: number): number
		return base + math.floor((rank - 1) / per) * step
	end
end

local function fixedCost(amount: number)
	return function(): number
		return amount
	end
end

-- A FLAT total: rank x perRank. Used for luck, which is now an absolute number
-- added to the roll multiplier rather than a percentage of it.
local function flatPerRank(perRank: number)
	return function(rank: number): number
		return rank * perRank
	end
end

-- A MULTIPLIER total: 1 + rank x perRank. 1.0 is "no change", which is the
-- identity these effects combine against.
local function multiplierPerRank(perRank: number)
	return function(rank: number): number
		return 1 + rank * perRank
	end
end

local function fixedValue(amount: number)
	return function(): number
		return amount
	end
end

----------------------------------------------------------------------
-- THE TREE
----------------------------------------------------------------------

SkillDefinitions.Data = {

	-- TIER 0 - the root everything hangs off.
	Awakening = {
		Name = "Awakening",
		Description = "The first spark. Opens every path and sharpens the coins you take from a win.",
		Icon = "", Glyph = "\u{25CF}", Category = "Elder",
		Position = Vector2.new(0, 0),
		MaxRank = 1,
		Cost = fixedCost(2500),
		Requirements = {},
		EffectType = "CoinGain",
		EffectValue = fixedValue(1.10),
	},

	-- TIER 1 - the three branches split here.

	-- The headline skill. 3000 ranks at a QUARTER OF A POINT of luck each, so a
	-- fully maxed Luck Boost is +750 luck - an absolute number added to the roll
	-- multiplier, not a percentage of it.
	LuckBoost = {
		Name = "Luck Boost",
		Description = "Adds +0.25 luck per rank, straight onto your roll multiplier.",
		Icon = "", Glyph = "\u{2740}", Category = "Luck",
		Position = Vector2.new(-480, 260),
		MaxRank = 3000,
		Cost = steppedCost(250, 25, 25),
		Requirements = { Awakening = 1 },
		EffectType = "LuckFlat",
		EffectValue = flatPerRank(0.25),
	},

	SwiftHands = {
		Name = "Swift Hands",
		Description = "Shaves a tiny amount off the roll cooldown each rank. Built for long-term progression.",
		Icon = "", Glyph = "\u{00BB}", Category = "Stat",
		Position = Vector2.new(0, 260),
		MaxRank = 1500,
		Cost = steppedCost(300, 30, 20),
		Requirements = { Awakening = 1 },
		EffectType = "RollSpeedBonus",
		EffectValue = flatPerRank(0.0002),
	},

	IronBody = {
		Name = "Iron Body",
		Description = "Adds a very small amount of card HP each rank, with a very high ceiling.",
		Icon = "", Glyph = "\u{25C6}", Category = "Stat",
		Position = Vector2.new(480, 260),
		MaxRank = 2500,
		Cost = steppedCost(350, 40, 25),
		Requirements = { Awakening = 1 },
		EffectType = "MaxHPMultiplier",
		EffectValue = multiplierPerRank(0.00025),
	},

	-- TIER 2 - deeper in each branch, plus one node joining two of them.

	FortuneFlow = {
		Name = "Fortune Flow",
		Description = "Luck upon luck: another +0.10 base luck per rank.",
		Icon = "", Glyph = "\u{273F}", Category = "Luck",
		Position = Vector2.new(-720, 520),
		MaxRank = 1500,
		Cost = steppedCost(800, 80, 20),
		Requirements = { LuckBoost = 500 },
		EffectType = "LuckFlat",
		EffectValue = flatPerRank(0.10),
	},

	CoinAffinity = {
		Name = "Coin Affinity",
		Description = "Slowly increases the Elder Coins earned from every victory.",
		Icon = "", Glyph = "\u{25CE}", Category = "Coin",
		Position = Vector2.new(-240, 520),
		MaxRank = 1000,
		Cost = steppedCost(900, 90, 20),
		-- Two separate parents: where the Luck and Stat branches meet.
		Requirements = { LuckBoost = 350, SwiftHands = 200 },
		EffectType = "CoinGain",
		EffectValue = multiplierPerRank(0.0005),
	},

	RapidDraw = {
		Name = "Rapid Draw",
		Description = "A second long-term roll-speed path with tiny gains per rank.",
		Icon = "", Glyph = "\u{25B2}", Category = "Stat",
		Position = Vector2.new(240, 520),
		MaxRank = 1000,
		Cost = steppedCost(1000, 100, 20),
		Requirements = { SwiftHands = 350 },
		EffectType = "RollSpeedBonus",
		EffectValue = flatPerRank(0.0002),
	},

	Bloodlust = {
		Name = "Bloodlust",
		Description = "Adds a small permanent battle damage boost each rank.",
		Icon = "", Glyph = "\u{2694}", Category = "Stat",
		Position = Vector2.new(720, 520),
		MaxRank = 2000,
		Cost = steppedCost(1200, 120, 25),
		Requirements = { IronBody = 500 },
		EffectType = "DamageMultiplier",
		EffectValue = multiplierPerRank(0.00025),
	},

	-- TIER 3

	Windwalker = {
		Name = "Windwalker",
		Description = "A late-game roll-speed branch with small gains and a high max rank.",
		Icon = "", Glyph = "\u{2756}", Category = "Stat",
		Position = Vector2.new(0, 780),
		MaxRank = 1000,
		Cost = steppedCost(1800, 180, 20),
		Requirements = { RapidDraw = 400, CoinAffinity = 300 },
		EffectType = "RollSpeedBonus",
		EffectValue = flatPerRank(0.00015),
	},

	KeenEye = {
		Name = "Keen Eye",
		Description = "Slowly raises critical-hit chance across many ranks.",
		Icon = "", Glyph = "\u{25C9}", Category = "Stat",
		Position = Vector2.new(480, 780),
		MaxRank = 1000,
		Cost = steppedCost(2000, 200, 20),
		Requirements = { Bloodlust = 650 },
		EffectType = "CritChanceBonus",
		EffectValue = flatPerRank(0.00015),
	},

	-- TIER 4 - the capstone. Gated behind DEEP ranks in three separate branches
	-- on purpose: it should be the end of a long grind, not a node you stumble
	-- into on the way past.
	ElderAscension = {
		Name = "Elder Ascension",
		Description = "The end of every path. A brutally expensive ascension earned through deep investment in all three branches.",
		Icon = "", Glyph = "\u{2605}", Category = "Elder",
		Position = Vector2.new(0, 1040),
		MaxRank = 1,
		Cost = fixedCost(2500000),
		Requirements = { FortuneFlow = 600, Windwalker = 400, KeenEye = 500 },
		EffectType = "LuckFlat",
		EffectValue = fixedValue(250),
	},
}

----------------------------------------------------------------------
-- DERIVED
----------------------------------------------------------------------

-- Colour is derived from Category rather than authored per skill, so a node, its
-- connections and its details panel can never end up wearing different colours.
for id, def in pairs(SkillDefinitions.Data) do
	def.Id = id
	def.Colour = SkillDefinitions.CategoryColour[def.Category] or ELDER
	def.Rainbow = def.Category == SkillDefinitions.RainbowCategory
end

-- A STABLE draw order. pairs() is unordered, so without this the board's nodes
-- and connections would be built in a different sequence every session, which
-- shows up as z-fighting between overlapping links.
local order = {}
for id in pairs(SkillDefinitions.Data) do
	table.insert(order, id)
end

table.sort(order, function(a, b)
	local pa = SkillDefinitions.Data[a].Position
	local pb = SkillDefinitions.Data[b].Position
	if pa.Y ~= pb.Y then return pa.Y < pb.Y end
	if pa.X ~= pb.X then return pa.X < pb.X end
	return a < b
end)

SkillDefinitions.Order = order

----------------------------------------------------------------------
-- VALIDATION
----------------------------------------------------------------------

-- Runs once at require time and hard-errors on a malformed entry, because every
-- one of these mistakes is SILENT at runtime: a Cost that is not callable makes
-- a node unbuyable with no error, a typo'd requirement locks it forever, and a
-- bad EffectValue makes a purchased rank do nothing at all.
for id, def in pairs(SkillDefinitions.Data) do
	assert(def.MaxRank and def.MaxRank >= 1,
		("[SkillDefinitions] %s has no MaxRank"):format(id))
	assert(type(def.Cost) == "function",
		("[SkillDefinitions] %s.Cost must be a function of rank"):format(id))
	assert(type(def.EffectValue) == "function",
		("[SkillDefinitions] %s.EffectValue must be a function of rank"):format(id))
	assert(SkillDefinitions.CategoryColour[def.Category],
		("[SkillDefinitions] %s has unknown Category %s"):format(id, tostring(def.Category)))

	-- Probe both ends of the curve; a formula that errors or returns nil at rank
	-- 1 or at MaxRank would otherwise only surface when a player got there.
	for _, probe in ipairs({ 1, def.MaxRank }) do
		assert(type(def.Cost(probe)) == "number",
			("[SkillDefinitions] %s.Cost(%d) did not return a number"):format(id, probe))
		assert(type(def.EffectValue(probe)) == "number",
			("[SkillDefinitions] %s.EffectValue(%d) did not return a number"):format(id, probe))
	end

	for reqId, reqRank in pairs(def.Requirements or {}) do
		local reqDef = SkillDefinitions.Data[reqId]
		assert(reqDef,
			("[SkillDefinitions] %s requires unknown skill %s"):format(id, tostring(reqId)))
		assert(reqId ~= id, ("[SkillDefinitions] %s requires itself"):format(id))
		assert(reqRank >= 1 and reqRank <= reqDef.MaxRank,
			("[SkillDefinitions] %s requires %s rank %d, but %s caps at %d")
				:format(id, reqId, reqRank, reqId, reqDef.MaxRank))
	end
end

-- Total CURRENT-CURVE price to take a skill from nothing to a given rank.
-- Useful for balance/debug displays. Reset refunds do NOT use this anymore:
-- SkillTreeService tracks the exact coins actually paid so price rebalances
-- cannot create or delete currency for existing players.
function SkillDefinitions.totalCost(def, toRank: number): number
	local total = 0
	for rank = 1, math.min(toRank, def.MaxRank) do
		total += def.Cost(rank)
	end
	return total
end

function SkillDefinitions.get(id: string)
	return SkillDefinitions.Data[id]
end

function SkillDefinitions.exists(id: string): boolean
	return SkillDefinitions.Data[id] ~= nil
end

return SkillDefinitions
