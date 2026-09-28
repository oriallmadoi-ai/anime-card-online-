--!strict
-- Every overworld encounter is described HERE and nowhere else.
--
-- Adding an enemy is TWO things: one entry in Data, and an anchor part in the
-- world named after its CardId. The floating card, its rarity border, ground
-- ring, label and themed VFX are all derived from this table - there is no
-- per-enemy script anywhere.
--
-- WHAT THIS TABLE DOES NOT DO.
-- `Difficulty` is PRESENTATION ONLY: it picks the label under the card and that
-- label's colour. The battle's real difficulty is whatever
-- BattleController:StartEncounter sends the server, and the server validates the
-- card id itself. Editing a Difficulty here cannot make a fight harder, and
-- cannot be used to reach an encounter the server would refuse.
--
-- Likewise `Variant` only decides which border the world card WEARS. It is not
-- written to save data and it does not touch the enemy's stats.

local EncounterDefinitions = {}

----------------------------------------------------------------
-- ASSETS
----------------------------------------------------------------

-- Textures authored for this system. All are white/greyscale so they can be
-- tinted per encounter rather than needing one upload per colour.
EncounterDefinitions.Assets = {
	Ring     = "rbxassetid://81204494272985",
	Dot      = "rbxassetid://109042378477283",
	Streak   = "rbxassetid://107003632646516",
	Aura     = "rbxassetid://106027227954060",

	-- Interim card back, used only by the Part fallback below. Once the mesh is
	-- imported its own baked texture is the back and this goes unused.
	CardBack = "rbxassetid://87924354110701",
}

-- Paste the MeshId of the imported EncounterCard.fbx here.
--
-- While this is empty the system builds the card body out of a Part instead:
-- same size, same live face, same back, but square corners and no chamfered
-- edge. Everything else behaves identically, so the game is never broken by a
-- missing mesh - it just looks less finished.
EncounterDefinitions.CardMeshId = ""

-- Set true only if the imported mesh comes in facing away from the player. The
-- FBX is authored front-to--Z, which is Roblox's Front face, so this should
-- stay false; it exists so a re-export with different axis settings is a
-- one-line fix rather than a re-import.
EncounterDefinitions.MeshFrontIsFlipped = false

----------------------------------------------------------------
-- CARD GEOMETRY
----------------------------------------------------------------

EncounterDefinitions.Card = {
	-- Height in studs. A Roblox character is ~5, so this reads as person-sized
	-- from across the plaza without dominating the skyline.
	Height = 5.0,

	-- height / width. MUST match CardRenderer, which builds a card at
	-- height = width * 1.34. If these disagree the live face is letterboxed or
	-- stretched on the mesh.
	Aspect = 1.34,

	Thickness = 0.09,

	-- Height of the card's CENTRE above its anchor. Bottom edge ends up about a
	-- stud clear of the ground, which is what makes it read as floating.
	Float = 3.6,

	-- The live face is rendered at this pixel width. 300 keeps CardRenderer's
	-- vScale() at exactly 1, so the world card's layout is pixel-identical to
	-- the deck and reveal cards rather than a shrunken variant of them.
	FaceWidth = 300,

	BossScale = 1.22,
}

----------------------------------------------------------------
-- DIFFICULTY (label only - see the header)
----------------------------------------------------------------

EncounterDefinitions.Difficulty = {
	Easy   = { text = "EASY ENCOUNTER",   color = Color3.fromRGB(104, 226, 143) },
	Medium = { text = "MEDIUM ENCOUNTER", color = Color3.fromRGB(245, 205,  88) },
	Hard   = { text = "HARD ENCOUNTER",   color = Color3.fromRGB(255, 104, 104) },
	Boss   = { text = "BOSS ENCOUNTER",   color = Color3.fromRGB(202, 138, 255) },
}

----------------------------------------------------------------
-- THEMED EFFECTS
----------------------------------------------------------------

-- Deliberately small. An idle encounter should read as calm: one or two low-rate
-- emitters and a tint, never a standing explosion. `rate` is particles per
-- second and is the number to touch first if something feels busy.
--
-- Fields per emitter:
--   texture      key into Assets
--   rate         particles/sec (keep under ~6)
--   size         {min, max} studs
--   speed        {min, max} studs/sec; negative falls, positive rises
--   life         {min, max} seconds
--   spread       degrees of cone spread
--   transparency resting transparency (particles fade in and out around it)
--   accel        Vector3 acceleration, for drift or gravity
--   drag         air resistance
--   light        LightEmission 0..1
--   rot          {min, max} degrees/sec of spin
--   dir          emission face
EncounterDefinitions.Effects = {
	-- Weather Girl: cool blue, fine falling droplets under a slow mist.
	Weather = {
		tint = Color3.fromRGB(96, 178, 255),
		glow = 0.90,
		emitters = {
			{ texture = "Dot", rate = 4.5, size = {0.06, 0.13}, speed = {-4.5, -3.0},
			  life = {1.1, 1.7}, spread = 12, transparency = 0.35, drag = 0.4,
			  light = 0.55, dir = Enum.NormalId.Top },
			{ texture = "Dot", rate = 1.6, size = {0.7, 1.25}, speed = {-0.25, 0.25},
			  life = {3.4, 5.0}, spread = 45, transparency = 0.90, drag = 1.6,
			  light = 0.25 },
		},
	},

	-- Duffy: warm rubbery energy, a couple of light wind streaks.
	Elastic = {
		tint = Color3.fromRGB(236, 96, 62),
		glow = 0.86,
		emitters = {
			{ texture = "Streak", rate = 1.8, size = {0.5, 0.95}, speed = {1.4, 2.4},
			  life = {0.8, 1.3}, spread = 22, transparency = 0.72, drag = 1.1,
			  light = 0.6, rot = {-40, 40} },
			{ texture = "Dot", rate = 2.2, size = {0.09, 0.18}, speed = {0.6, 1.5},
			  life = {1.2, 2.0}, spread = 35, transparency = 0.55, light = 0.7 },
		},
	},

	-- Devil Swordsman: green slash arcs, sparse and quick.
	Slash = {
		tint = Color3.fromRGB(86, 196, 104),
		glow = 0.88,
		emitters = {
			{ texture = "Streak", rate = 1.5, size = {0.6, 1.15}, speed = {2.2, 3.4},
			  life = {0.45, 0.75}, spread = 60, transparency = 0.60, drag = 2.0,
			  light = 0.85, rot = {-140, 140} },
			{ texture = "Dot", rate = 1.4, size = {0.06, 0.12}, speed = {0.4, 1.1},
			  life = {1.0, 1.6}, spread = 40, transparency = 0.62, light = 0.8 },
		},
	},

	-- Sniper Pirate: gold sparks, and the occasional bright glint.
	Snipe = {
		tint = Color3.fromRGB(255, 190, 84),
		glow = 0.88,
		emitters = {
			{ texture = "Dot", rate = 2.6, size = {0.05, 0.11}, speed = {0.8, 1.9},
			  life = {0.9, 1.5}, spread = 30, transparency = 0.45, light = 0.95,
			  accel = Vector3.new(0, -1.2, 0) },
			{ texture = "Streak", rate = 0.5, size = {0.8, 1.3}, speed = {0.2, 0.5},
			  life = {0.5, 0.8}, spread = 12, transparency = 0.70, light = 1.0,
			  rot = {-15, 15} },
		},
	},

	-- Pirate Cook: rising heat with embers in it.
	Heat = {
		tint = Color3.fromRGB(255, 146, 62),
		glow = 0.86,
		emitters = {
			{ texture = "Dot", rate = 3.2, size = {0.10, 0.22}, speed = {1.1, 2.1},
			  life = {1.3, 2.1}, spread = 24, transparency = 0.55, light = 0.9,
			  accel = Vector3.new(0, 1.4, 0), drag = 1.0, dir = Enum.NormalId.Top },
			{ texture = "Dot", rate = 1.2, size = {0.5, 0.9}, speed = {0.5, 1.1},
			  life = {2.0, 3.0}, spread = 40, transparency = 0.90, light = 0.35,
			  accel = Vector3.new(0, 0.8, 0), drag = 1.8 },
		},
	},

	-- Pirate Shark: the boss. Heavier water aura, droplets, deeper blue.
	Tide = {
		tint = Color3.fromRGB(64, 170, 235),
		glow = 1.00,
		emitters = {
			{ texture = "Dot", rate = 5.0, size = {0.08, 0.18}, speed = {-3.2, -1.8},
			  life = {1.4, 2.2}, spread = 26, transparency = 0.38, drag = 0.6,
			  light = 0.7, dir = Enum.NormalId.Top },
			{ texture = "Dot", rate = 2.4, size = {0.9, 1.7}, speed = {-0.2, 0.4},
			  life = {3.8, 5.4}, spread = 55, transparency = 0.88, drag = 1.7,
			  light = 0.30 },
			{ texture = "Streak", rate = 0.8, size = {0.7, 1.2}, speed = {0.9, 1.7},
			  life = {1.0, 1.6}, spread = 70, transparency = 0.80, drag = 1.4,
			  light = 0.5, rot = {-60, 60} },
		},
	},
}

----------------------------------------------------------------
-- THE ENCOUNTERS
----------------------------------------------------------------

-- CardId    which card in CardDefinitions supplies the art, name and stats.
--           Also the id handed to BattleController:StartEncounter, so it must
--           be one the server's ENCOUNTER_CARDS accepts.
-- Variant   which rarity border the world card wears. All Basic for now.
-- Effect    key into Effects above.
-- IsBoss    bigger card, bigger ring, stronger glow, BOSS chip on the label.
EncounterDefinitions.Data = {
	{ CardId = "Usopp",  Difficulty = "Easy",   Effect = "Snipe",   Variant = "Standard", Order = 1 },
	{ CardId = "Nami",   Difficulty = "Easy",   Effect = "Weather", Variant = "Standard", Order = 2 },
	{ CardId = "Duffy",  Difficulty = "Easy",   Effect = "Elastic", Variant = "Standard", Order = 3 },
	{ CardId = "Zoro",   Difficulty = "Medium", Effect = "Slash",   Variant = "Standard", Order = 4 },
	{ CardId = "Sanji",  Difficulty = "Hard",   Effect = "Heat",    Variant = "Standard", Order = 5 },
	{ CardId = "Arlong", Difficulty = "Boss",   Effect = "Tide",    Variant = "Standard", Order = 6, IsBoss = true },
}

----------------------------------------------------------------
-- LOOKUP
----------------------------------------------------------------

local byCardId: { [string]: any } = {}
for _, entry in ipairs(EncounterDefinitions.Data) do
	byCardId[entry.CardId] = entry
end

function EncounterDefinitions.get(cardId: string)
	return byCardId[cardId]
end

function EncounterDefinitions.difficulty(name: string?)
	return EncounterDefinitions.Difficulty[name or "Easy"]
		or EncounterDefinitions.Difficulty.Easy
end

function EncounterDefinitions.effect(name: string?)
	-- An unknown effect name should not blank the card out; fall back to the
	-- calmest one so a typo is visible but harmless.
	return EncounterDefinitions.Effects[name or ""]
		or EncounterDefinitions.Effects.Weather
end

function EncounterDefinitions.texture(key: string): string
	return EncounterDefinitions.Assets[key] or EncounterDefinitions.Assets.Dot
end

-- Ordered copy, so callers can iterate deterministically without depending on
-- the literal order of Data.
function EncounterDefinitions.ordered()
	local list = table.clone(EncounterDefinitions.Data)
	table.sort(list, function(a, b)
		return (a.Order or 0) < (b.Order or 0)
	end)
	return list
end

return EncounterDefinitions
