--!strict
-- Every persistent thing that can sit on a card during a fight.
-- Passives never implement their own bookkeeping; they apply a status from
-- this registry and the combat engine handles ticking, stacking and expiry.
-- One place to fix a bug, one place to balance.
--
-- stacking:  "Stack"   - multiple applications add stacks (Brand, Bleed)
--            "Refresh" - reapplying resets duration, no stack (Freeze)
--            "Unique"  - only ever one, reapplication does nothing
-- tick:      "TurnStart" | "TurnEnd" | nil (passive modifier, never ticks)
-- category:  used by Challenge modifiers to switch whole classes off,
--            e.g. "allies cannot heal" disables everything categorised Heal.

local StatusEffects = {}

StatusEffects.Data = {
	DivineMark = {
		id = "DivineMark", display = "Divine Mark", category = "Debuff",
		stacking = "Stack", maxStacks = 4,
		description = "At 3 marks, takes 50% max HP damage; 4 marks deal 95% if the attacker is paired with Shinigami of Death. Marks are consumed.",
	},
	Apple = {
		id = "Apple", display = "Apple", category = "Buff",
		stacking = "Stack", maxStacks = 3,
		description = "Collected when the supported card is attacked. Three grant team protection once per match.",
	},
	AppleGuard = {
		id = "AppleGuard", display = "Apple Guard", category = "Mitigation",
		stacking = "Refresh", maxStacks = 1,
		description = "Takes 15% less damage for 3 turns.",
	},
	Frostbite = {
		id = "Frostbite", display = "Frostbite", category = "DoT",
		stacking = "Refresh", maxStacks = 1, tick = "TurnEnd",
		description = "Takes 10% of the applying card's DMG for two turns.",
	},
	FreezeReady = {
		id = "FreezeReady", display = "Freeze Ready", category = "Buff",
		stacking = "Unique", maxStacks = 1,
		description = "The next attack stuns and applies frostbite.",
	},
	Daze = {
		id = "Daze", display = "Daze", category = "Control",
		stacking = "Refresh", maxStacks = 1,
		description = "Lasts one turn. Redirects one attack: 80% of each hit's damage to one random living ally and 20% to the applying captain. Consumed on the attack; must be reapplied.",
	},
	Burn = {
		id = "Burn", display = "Burn", category = "DoT",
		stacking = "Stack", maxStacks = 5, tick = "TurnEnd",
		-- damage per turn = potency * source DMG, per stack
		description = "Takes damage at the end of each turn.",
	},
	Bleed = {
		id = "Bleed", display = "Bleed", category = "DoT",
		stacking = "Stack", maxStacks = 10, tick = "TurnEnd",
		description = "Takes damage at the end of each turn, scaling with the hit that applied it.",
	},
	Brand = {
		id = "Brand", display = "Brand", category = "Debuff",
		stacking = "Stack", maxStacks = 3, tick = nil,
		-- Brand is a marker other effects read: bonus damage taken per stack,
		-- and at max stacks it blocks revival.
		description = "Takes bonus damage. At max stacks, cannot revive.",
	},
	Freeze = {
		id = "Freeze", display = "Freeze", category = "Control",
		stacking = "Refresh", maxStacks = 1, tick = nil,
		skipsTurn = true,
		description = "Cannot act.",
	},
	TimeStop = {
		id = "TimeStop", display = "Time Stop", category = "Control",
		stacking = "Refresh", maxStacks = 1, tick = nil,
		skipsTurn = true, freezesEnemyTeam = true,
		description = "All enemies cannot act.",
	},
	Shield = {
		id = "Shield", display = "Shield", category = "Mitigation",
		stacking = "Stack", maxStacks = 99, tick = nil,
		absorbsDamage = true,
		description = "Absorbs damage before HP is lost.",
	},
	DmgUp = {
		id = "DmgUp", display = "DMG Up", category = "Buff",
		stacking = "Stack", maxStacks = 99, tick = nil,
		description = "Deals increased damage.",
	},
	CritUp = {
		id = "CritUp", display = "Crit Up", category = "Buff",
		stacking = "Stack", maxStacks = 20, tick = nil,
		description = "Increased critical chance.",
	},
	DmgReduction = {
		id = "DmgReduction", display = "Resist", category = "Mitigation",
		stacking = "Stack", maxStacks = 20, tick = nil,
		description = "Takes reduced damage.",
	},
	Dodge = {
		id = "Dodge", display = "Dodge", category = "Mitigation",
		stacking = "Stack", maxStacks = 20, tick = nil,
		-- Rolled once per incoming attack, BEFORE damage is calculated: a dodge
		-- avoids the hit entirely rather than reducing it, so it does not stack
		-- multiplicatively with DmgReduction the way a second resist would.
		description = "Chance to avoid an incoming attack completely.",
	},
	Chained = {
		id = "Chained", display = "Chained", category = "Control",
		stacking = "Unique", maxStacks = 1, tick = nil,
		description = "Locked in place; cannot be swapped out.",
	},

	-- A pure COUNTER. It has no effect of its own; a clause reads its stack count
	-- through the HasStacks condition and pays out at the threshold. Categorised
	-- Buff rather than invented as a new category so the existing challenge
	-- modifiers keep working without knowing about it.
	--
	-- maxStacks 3 is the payout threshold, so the counter cannot run past the
	-- point where it means anything.
	Money = {
		id = "Money", display = "Money", category = "Buff",
		stacking = "Stack", maxStacks = 3, tick = nil,
		description = "Wealth collected from being attacked.",
	},

	-- Skips a turn like Freeze, but categorised BUFF on purpose.
	--
	-- This is a card winding ITSELF up, not a stun being done to it. Filed under
	-- Control it would be switched off by any challenge that disables control
	-- effects on the player - which would not free the card, it would delete the
	-- charge and leave the payout clause waiting for a status that never lands.
	Charging = {
		id = "Charging", display = "Charging", category = "Buff",
		stacking = "Refresh", maxStacks = 1, tick = nil,
		skipsTurn = true,
		description = "Gathering power; cannot act this turn.",
	},
}

-- ── VISUAL IDENTITY ────────────────────────────────────────────────
-- Presentation only. Nothing below this line changes what a status DOES;
-- it is read by Shared.UI.StatusVfx to tint the card's aura, label the
-- corner badge and pick the burst that plays when the status lands.
--
-- Two layers, so sixteen effects do not need sixteen hand-written recipes:
--   Categories[category]  motion, sprite, burst sprite, priority
--   Visuals[id]           the colour and three-letter badge for ONE effect,
--                         and an override of any category field
-- StatusEffects.visual(id) merges the two and caches the result.
--
-- priority decides which effect owns the card's border when several are live
-- at once. A stun has to read louder than a damage buff, or the player cannot
-- tell at a glance why their card did nothing this turn.

StatusEffects.Categories = {
	Control    = { motion = "ring",    sprite = "Mote",  burst = "Rune",   priority = 50 },
	DoT        = { motion = "fall",    sprite = "Spark", burst = "Glow",   priority = 40 },
	Debuff     = { motion = "crackle", sprite = "Spark", burst = "Shock",  priority = 30 },
	Mitigation = { motion = "shell",   sprite = "Mote",  burst = "Shock",  priority = 20 },
	Buff       = { motion = "rise",    sprite = "Mote",  burst = "Streak", priority = 10 },
}

-- Categories that read as something being done TO the card rather than for it.
-- Used for the badge's tone and for which side of the log an effect colours.
local HOSTILE = { DoT = true, Control = true, Debuff = true }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Badges are three letters, not glyphs. A symbol font that is missing a
-- codepoint renders a box, and there is no way to find that out at runtime -
-- letters always draw, on every platform, at every text size.
StatusEffects.Visuals = {
	DivineMark = { colour = rgb(202, 65, 80), badge = "MRK" },
	Apple = { colour = rgb(225, 58, 62), badge = "APL" },
	AppleGuard = { colour = rgb(146, 204, 125), badge = "DEF" },
	-- DoT
	Bleed     = { colour = rgb(214,  48,  58), badge = "BLD" },
	Burn      = { colour = rgb(255, 128,  38), badge = "BRN" },
	Frostbite = { colour = rgb(128, 206, 255), badge = "FRB", burst = "Shock" },

	-- Control
	Freeze    = { colour = rgb(112, 198, 255), badge = "FRZ" },
	Chained   = { colour = rgb(168, 148, 200), badge = "CHN" },
	Daze      = { colour = rgb(255, 214,  92), badge = "DAZ" },
	TimeStop  = { colour = rgb(190, 180, 255), badge = "STP", burst = "Shaft" },

	-- Mitigation
	Shield       = { colour = rgb( 92, 196, 255), badge = "SHD" },
	DmgReduction = { colour = rgb(126, 168, 214), badge = "DEF" },
	Dodge        = { colour = rgb(120, 234, 176), badge = "DGE" },

	-- Buff
	DmgUp       = { colour = rgb(255, 168,  64), badge = "DMG" },
	CritUp      = { colour = rgb(255,  96, 120), badge = "CRT" },
	Charging    = { colour = rgb(255, 236, 110), badge = "CHG", burst = "Shaft", priority = 35 },
	FreezeReady = { colour = rgb(150, 224, 255), badge = "RDY" },
	Money       = { colour = rgb(255, 206,  88), badge = "CSH" },

	-- Debuff
	Brand = { colour = rgb(226,  88, 232), badge = "BRD" },
}

local NEUTRAL = rgb(216, 216, 234)
local visualCache: { [string]: any } = {}

-- Never returns nil for a real status id: an effect added to Data without a
-- Visuals entry still gets a usable aura off its category, so the VFX layer
-- degrades to "generic" rather than silently drawing nothing.
function StatusEffects.visual(id: string)
	if id == nil or id == "" then return nil end
	local cached = visualCache[id]
	if cached then return cached end

	local data = StatusEffects.Data[id]
	if not data then return nil end

	local cat = StatusEffects.Categories[data.category]
	local own = StatusEffects.Visuals[id] or {}

	local out = {
		id = id,
		display = data.display or id,
		category = data.category,
		colour = own.colour or NEUTRAL,
		badge = own.badge or string.upper(string.sub(id, 1, 3)),
		motion = own.motion or (cat and cat.motion) or "rise",
		sprite = own.sprite or (cat and cat.sprite) or "Mote",
		burst = own.burst or (cat and cat.burst) or "Glow",
		priority = own.priority or (cat and cat.priority) or 10,
		hostile = HOSTILE[data.category] == true,
		maxStacks = data.maxStacks or 1,
	}
	visualCache[id] = out
	return out
end

function StatusEffects.get(id: string)
	return StatusEffects.Data[id]
end

return StatusEffects



