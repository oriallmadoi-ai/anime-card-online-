--!strict
-- Difficulty stages for the Arlong Park encounters, and the card unlocks they
-- gate. Everything about "what does fighting X on Y actually mean" is in this
-- one table.
--
-- READ BY BOTH SIDES.
-- The client uses it to draw the difficulty selector and preview the lineup; the
-- server uses it to BUILD that lineup and to decide unlocks. Sharing the table
-- is what stops the preview and the real fight from drifting apart - but it also
-- means the client can only ever DISPLAY this. BattleService re-derives the
-- lineup from here itself and never trusts a roster sent up from a client.

local EncounterModes = {}

----------------------------------------------------------------
-- STAGES
----------------------------------------------------------------

EncounterModes.Order = { "Easy", "Medium", "Hard", "Impossible", "Cosmic" }

-- statMultiplier doubles per stage and is applied to EVERY card on the enemy
-- side, boss and backup alike. Cosmic is therefore a 16x fight, which is meant
-- to be a wall rather than a step.
EncounterModes.Data = {
	Easy = {
		id = "Easy", rank = 1, display = "EASY", statMultiplier = 1,
		accent = Color3.fromRGB(104, 226, 143),
		blurb = "One enemy. Clear this to unlock its card.",
	},
	Medium = {
		id = "Medium", rank = 2, display = "MEDIUM", statMultiplier = 2,
		accent = Color3.fromRGB(245, 205, 88),
		blurb = "Double stats.",
	},
	Hard = {
		id = "Hard", rank = 3, display = "HARD", statMultiplier = 4,
		accent = Color3.fromRGB(255, 118, 96),
		blurb = "Quadruple stats.",
	},
	Impossible = {
		id = "Impossible", rank = 4, display = "IMPOSSIBLE", statMultiplier = 8,
		accent = Color3.fromRGB(202, 138, 255),
		blurb = "Eight times stats, and reinforcements.",
	},
	Cosmic = {
		id = "Cosmic", rank = 5, display = "COSMIC", statMultiplier = 16,
		accent = Color3.fromRGB(120, 232, 255),
		blurb = "Sixteen times stats. The full lineup.",
		special = true,   -- the UI gives this stage its own treatment
	},
}

----------------------------------------------------------------
-- LINEUPS
----------------------------------------------------------------

-- Extras that fight ALONGSIDE the encounter's own card, per stage. A stage not
-- listed here has no extras, so the boss fights alone at raised stats.
--
-- Sniper, Weather Girl and Duffy have no backup until Impossible on purpose:
-- their Medium and Hard are pure stat walls. The three later encounters escalate
-- by adding the enemies you already beat, so the roster doubles as a recap of
-- the route so far.
EncounterModes.Rosters = {
	Usopp = {
		Impossible = { "Franky" },
		Cosmic     = { "Franky", "Chopper" },
	},
	Nami = {
		Impossible = { "Franky" },
		Cosmic     = { "Franky", "Chopper" },
	},
	Duffy = {
		Impossible = { "Franky" },
		Cosmic     = { "Franky", "Chopper" },
	},

	-- Devil Swordsman brings the three you cleared before him instead of the
	-- Cola Cyborg / Dear Doctor pair.
	Zoro = {
		Medium     = { "Duffy" },
		Hard       = { "Duffy", "Usopp" },
		Impossible = { "Duffy", "Usopp", "Nami" },
		Cosmic     = { "Duffy", "Usopp", "Nami" },
	},

	-- Pirate Cook: the same three, plus the Swordsman at the top stage.
	Sanji = {
		Medium     = { "Duffy" },
		Hard       = { "Duffy", "Usopp" },
		Impossible = { "Duffy", "Usopp", "Nami" },
		Cosmic     = { "Duffy", "Usopp", "Nami", "Zoro" },
	},

	-- Pirate Shark fields the entire route at the top two stages. Deliberately
	-- NOT Cola Cyborg or Dear Doctor - this is the story roster only.
	Arlong = {
		Medium     = { "Usopp" },
		Hard       = { "Usopp", "Nami" },
		Impossible = { "Usopp", "Nami", "Duffy", "Zoro", "Sanji" },
		Cosmic     = { "Usopp", "Nami", "Duffy", "Zoro", "Sanji" },
	},
}

----------------------------------------------------------------
-- KAME HOUSE (same shape as Arlong Park)
----------------------------------------------------------------
-- Son Warrior and the Prideful Prince are the openers; from the Android
-- Mentor on, each fight brings the Kame House cards already beaten. Son
-- Prodigy fights ALONE until Impossible, where Son Warrior joins him.
EncounterModes.Rosters.SonWarrior = {}
EncounterModes.Rosters.PridefulPrince = {
	Impossible = { "SonWarrior" },
	Cosmic     = { "SonWarrior" },
}
EncounterModes.Rosters.AndroidMentor = {
	Hard       = { "SonWarrior" },
	Impossible = { "SonWarrior", "PridefulPrince" },
	Cosmic     = { "SonWarrior", "PridefulPrince" },
}
EncounterModes.Rosters.FutureWarrior = {
	Medium     = { "SonWarrior" },
	Hard       = { "SonWarrior", "PridefulPrince" },
	Impossible = { "SonWarrior", "PridefulPrince", "AndroidMentor" },
	Cosmic     = { "SonWarrior", "PridefulPrince", "AndroidMentor" },
}
EncounterModes.Rosters.DevouringBug = {
	Medium     = { "SonWarrior" },
	Hard       = { "SonWarrior", "PridefulPrince" },
	Impossible = { "SonWarrior", "PridefulPrince", "AndroidMentor" },
	Cosmic     = { "SonWarrior", "PridefulPrince", "AndroidMentor", "FutureWarrior" },
}
EncounterModes.Rosters.SonProdigy = {
	Impossible = { "SonWarrior" },
	Cosmic     = { "SonWarrior" },
}

-- Stage multipliers that differ for ONE encounter. Son Prodigy's top two
-- stages are twice the usual: 16x on Impossible, 32x on Cosmic.
EncounterModes.StatOverrides = {
	SonProdigy = { Impossible = 16, Cosmic = 32 },
}

-- Panel text that differs for one encounter (so the blurb never lies about
-- who shows up or how strong they are).
EncounterModes.BlurbOverrides = {
	SonWarrior = {
		Impossible = "Eight times stats.",
		Cosmic = "Sixteen times stats.",
	},
	SonProdigy = {
		Medium = "Double stats. He fights alone.",
		Hard = "Quadruple stats. He fights alone.",
		Impossible = "Sixteen times stats, and Son Warrior joins him.",
		Cosmic = "Thirty-two times stats. Son Warrior at his side.",
	},
}

-- The player side is capped at GameConfig.AttackSlots (5). The ENEMY side is
-- not: Pirate Shark on Impossible is six cards. They arrive one at a time as the
-- previous one falls, so a longer list is a longer fight rather than a wider
-- board. This cap only exists to stop a future roster edit from producing an
-- unwinnable wall by accident.
EncounterModes.MaxEnemies = 8

----------------------------------------------------------------
-- REWARDS
----------------------------------------------------------------
--
-- CALIBRATED AGAINST THE SKILL TREE, not picked out of the air.
-- The whole tree costs about 52.8M Elder Coins and a Test Battle win pays
-- 20,000, so maxing it is on the order of 2,600 wins. Clearing every encounter
-- on every stage - thirty first-time payouts, six of them Cosmic - pays roughly
-- 4M, about 7% of the tree, or 200 test battles. That is a real campaign reward
-- without turning the tree into a formality.
--
-- FIRST TIME IS ALWAYS FAR LARGER THAN REPEAT. Repeat sits near 8% of the
-- first-time figure: enough that farming the stage you are good at is worth
-- doing, nowhere near enough to beat simply progressing. Arlong on Cosmic - the
-- hardest fight in the game at 16x stats and six enemies - repeats for 64,000,
-- a bit over three test battles, which is the intended endgame farm.
EncounterModes.Rewards = {
	FirstTime = {
		Easy = 5000, Medium = 15000, Hard = 45000, Impossible = 140000, Cosmic = 400000,
	},
	Repeat = {
		Easy = 400, Medium = 1200, Hard = 3600, Impossible = 11000, Cosmic = 32000,
	},
}

-- Per-encounter weight. The route gets harder along its own order, and the boss
-- pays double. Absent = 1.0.
EncounterModes.Weights = {
	Usopp = 0.7, Nami = 0.8, Duffy = 0.9, Zoro = 1.0, Sanji = 1.3, Arlong = 2.0,
	-- Kame House is the later island, so it pays more along the same curve.
	SonWarrior = 2.2, PridefulPrince = 2.4, AndroidMentor = 2.6,
	FutureWarrior = 2.8, DevouringBug = 3.0, SonProdigy = 4.0,
}

-- Rounded to something a player can read at a glance. A payout of 43,871 tells
-- nobody anything that 43,900 does not.
local function tidy(n: number): number
	if n >= 100000 then return math.floor(n / 1000 + 0.5) * 1000 end
	if n >= 10000 then return math.floor(n / 100 + 0.5) * 100 end
	if n >= 1000 then return math.floor(n / 50 + 0.5) * 50 end
	return math.floor(n / 10 + 0.5) * 10
end

function EncounterModes.coins(encounterId: string, difficulty: string?, firstTime: boolean): number
	local table_ = firstTime and EncounterModes.Rewards.FirstTime or EncounterModes.Rewards.Repeat
	local base = table_[difficulty or "Easy"] or table_.Easy
	local weight = EncounterModes.Weights[encounterId] or 1
	return tidy(base * weight)
end

----------------------------------------------------------------
-- UNLOCKS
----------------------------------------------------------------

-- cardId -> the clear that makes it ROLLABLE.
--
-- A card absent from this table is rollable from the start, which is why Cola
-- Cyborg (Franky) and Dear Doctor (Chopper) are not listed: they are the two
-- cards a brand new player can actually pull, and therefore the deck they use to
-- win the first encounter. Locking them would make the game unstartable.
--
-- This gates ROLLING ONLY. A copy already in a player's inventory stays owned,
-- deckable and playable whatever this says - locking someone out of a card they
-- earned before this system existed would be a bug, not a feature.
EncounterModes.Unlocks = {
	Usopp  = { encounter = "Usopp",  difficulty = "Easy" },
	Nami   = { encounter = "Nami",   difficulty = "Easy" },
	Duffy  = { encounter = "Duffy",  difficulty = "Easy" },
	Zoro   = { encounter = "Zoro",   difficulty = "Easy" },
	Sanji  = { encounter = "Sanji",  difficulty = "Easy" },
	Arlong = { encounter = "Arlong", difficulty = "Easy" },

	-- The one rollable support, and the deepest reward in the route.
	WillOfD = { encounter = "Arlong", difficulty = "Impossible" },

	-- Kame House: each card is rollable once its own encounter is cleared.
	SonWarrior     = { encounter = "SonWarrior",     difficulty = "Easy" },
	PridefulPrince = { encounter = "PridefulPrince", difficulty = "Easy" },
	AndroidMentor  = { encounter = "AndroidMentor",  difficulty = "Easy" },
	FutureWarrior  = { encounter = "FutureWarrior",  difficulty = "Easy" },
	DevouringBug   = { encounter = "DevouringBug",   difficulty = "Easy" },
	SonProdigy     = { encounter = "SonProdigy",     difficulty = "Easy" },
}

----------------------------------------------------------------
-- PANEL ART
----------------------------------------------------------------

-- Authored in Blender and uploaded with this feature. All greyscale so the
-- panel can tint them per difficulty instead of needing one upload per accent.
EncounterModes.UI = {
	Grain  = "rbxassetid://75538100615853",   -- barely-there tooth on flat panels
	Glow   = "rbxassetid://100198743878664",  -- soft radial, sits behind the card
}

----------------------------------------------------------------
-- LOOKUP
----------------------------------------------------------------

function EncounterModes.get(id: string?)
	return EncounterModes.Data[id or "Easy"] or EncounterModes.Data.Easy
end

function EncounterModes.exists(id: any): boolean
	return type(id) == "string" and EncounterModes.Data[id] ~= nil
end

function EncounterModes.rank(id: string?): number
	return EncounterModes.get(id).rank
end

-- The extras only, without the encounter's own card.
function EncounterModes.extras(cardId: string, difficulty: string?): { string }
	local byCard = EncounterModes.Rosters[cardId]
	if not byCard then return {} end
	return byCard[difficulty or "Easy"] or {}
end

-- The whole enemy side, boss first. This is THE definition of who you fight;
-- both the preview and the real battle call it so they cannot disagree.
function EncounterModes.lineup(cardId: string, difficulty: string?): { string }
	local out = { cardId }
	for _, extra in ipairs(EncounterModes.extras(cardId, difficulty)) do
		if #out >= EncounterModes.MaxEnemies then break end
		table.insert(out, extra)
	end
	return out
end

-- `encounterId` is optional; pass it so an encounter's own override applies.
function EncounterModes.statMultiplier(difficulty: string?, encounterId: string?): number
	local mode = EncounterModes.get(difficulty)
	local override = encounterId and EncounterModes.StatOverrides[encounterId]
	if override and override[mode.id] then
		return override[mode.id]
	end
	return mode.statMultiplier
end

function EncounterModes.blurb(encounterId: string?, difficulty: string?): string
	local mode = EncounterModes.get(difficulty)
	local override = encounterId and EncounterModes.BlurbOverrides[encounterId]
	return (override and override[mode.id]) or mode.blurb
end

-- Stages are climbed in order: you may attempt the one after your best clear,
-- and no further. Easy is always available.
--
-- Enforced on the SERVER in BattleService:_startTest as well as drawn here; the
-- panel greying a tab out is a courtesy, not the rule.
function EncounterModes.isStageUnlocked(encounterId: string, difficulty: string?, clears: { [string]: number }?): boolean
	local rank = EncounterModes.rank(difficulty)
	if rank <= 1 then return true end
	local best = clears and clears[encounterId] or 0
	return best >= rank - 1
end

-- The stage that must be cleared before `difficulty` opens, or nil for Easy.
function EncounterModes.previousStage(difficulty: string?): string?
	local rank = EncounterModes.rank(difficulty)
	if rank <= 1 then return nil end
	return EncounterModes.Order[rank - 1]
end

-- `clears` is profile.encounters: encounterId -> highest rank cleared.
function EncounterModes.isUnlocked(cardId: string, clears: { [string]: number }?): boolean
	local req = EncounterModes.Unlocks[cardId]
	if not req then return true end
	local have = clears and clears[req.encounter] or 0
	return have >= EncounterModes.rank(req.difficulty)
end

-- What a locked card is waiting on, for the UI to explain itself.
function EncounterModes.requirement(cardId: string)
	return EncounterModes.Unlocks[cardId]
end

return EncounterModes
