--!strict
-- Passives as DATA. A passive is a list of clauses: "when X happens, with Y
-- chance, run these effects".
--
-- TRIGGERS  OnEntry | OnTurnStart | OnAttack | OnAttacked | OnDamage | OnKill
--           | OnDeath
-- EFFECTS   Damage | Heal | ApplyStatus | Revive | ExtraAttack | CancelAttack
--           | GainDamage | GainMaxHP | SummonClone | RandomChoice
-- TARGETS   Self | ActiveEnemy | NextEnemy | LastHit | PairedCard | AllAllies
--           | Ally:<cardId>
--
-- A clause may also carry:
--   condition  a name from the CONDITIONS registry in CombatEngine. The clause
--              is skipped entirely when it does not hold - the chance is not
--              even rolled. Use for "only while X" abilities.
--   limit      maximum times the clause may fire in one battle.
--   chanceOnFail  added to this clause's chance each time the roll misses, so a
--              low-probability effect is guaranteed to land eventually.
--
-- A GainDamage effect permanently raises the source's DMG by a share of some
-- OTHER card's DMG, named by `from` (a target spec). It is the only effect that
-- reads a stat off a card other than the source, which is why it needs `from`
-- rather than the usual `target`.
--
-- An ApplyStatus effect may carry useSourceDmg = true, which scales the status
-- from the source's DMG STAT instead of from the damage the triggering hit
-- happened to deal. Anything whose card text says "X% of its DMG" wants this;
-- otherwise a crit silently inflates the effect past what the card claims.
--
-- Four more knobs, all optional, all shared by the effects that make sense for
-- them. They exist so an ability can be ONE clause: a clause is what rolls the
-- trigger's chance and what owns the `limit`, so splitting an ability across two
-- clauses rolls twice and lets it half-fire.
--
--   from          read a stat off a DIFFERENT card (a target spec). On Damage it
--                 re-bases the hit on that card's DMG, which is how "a share of
--                 the damage that was blocked" is expressed; on GainMaxHP it
--                 reads that card's base HP ceiling.
--   scaleBy       multiply the effect by a count. "DefeatedAllies" counts fallen
--                 party members; "AlliesNamed" counts party members whose name
--                 contains `nameContains`. A count of zero SKIPS the effect
--                 rather than applying it at zero strength.
--   namedPotency  an alternative potency used for targets whose name contains
--                 `nameContains`, so one clause can buff two grades of ally.
--   tag           what the damage number is labelled as in the log ("crit").
--
-- A RandomChoice effect picks exactly ONE of its `options` branches, weighted by
-- each branch's `weight` (default 1). Use it for "either X or Y" abilities: two
-- clauses would roll independently and could produce both effects or neither.
--
-- DESCRIPTION STYLE, and why it is worth following:
--
--   Keep descriptions SHORT. The card renderer now shrinks text to fit rather
--   than clipping it, so a long description is no longer cut off - but it does
--   get smaller, and a wall of 7px text is its own kind of unreadable. Aim for
--   roughly one hundred characters.
--
--   When a description names another CARD, or a group of cards, put the name in
--   QUOTES: 'if "Master of Both" is in your deck'. The quotes tell the player
--   that the word is a name to go looking for in their deck rather than ordinary
--   prose - which matters most for abilities that only pay out when that
--   specific card is present.

local PassiveDefinitions = {}

PassiveDefinitions.Data = {
	Geass = {
		id = "Geass", name = "Geass", alwaysFirst = true,
		clauses = {},
		description = "Always attacks first. If both fighters have Geass, normal attack order breaks the tie.",
	},
	SmokeGuard = {
		id = "SmokeGuard", name = "Smoke Guard",
		clauses = {
			{ trigger = "OnEntry", limit = 1, effects = {
				{ kind = "ApplyStatus", target = "Self", status = "DmgReduction", potency = 0.10, duration = 0 },
			} },
		},
		description = "Takes 10% less damage from attacks.",
	},
	SandDrain = {
		id = "SandDrain", name = "Sand Drain",
		clauses = {
			{ trigger = "OnAttack", effects = {
				{ kind = "Heal", target = "Self", scalesWith = "DamageDealt", potency = 0.10 },
			} },
		},
		description = "Heals for 10% of the damage its attacks deal.",
	},
	RockPunch = {
		id = "RockPunch", name = "Rock Punch",
		clauses = {
			{ trigger = "OnBeforeAttack", everyNth = 3, effects = {
				{ kind = "AttackMultiplier", multiplier = 1.30 },
			} },
		},
		description = "Every third attack deals 30% extra damage.",
	},
	HunterLightningStrike = {
		id = "HunterLightningStrike", name = "Lightning Strike",
		clauses = {
			{ trigger = "OnBeforeAttack", chance = 0.20, effects = {
				{ kind = "AttackMultiplier", multiplier = 1.40 },
			} },
		},
		description = "Each attack has a 20% chance to deal 40% extra damage.",
	},
	LuckyWeapon = {
		id = "LuckyWeapon", name = "Lucky Weapon",
		clauses = {
			{ trigger = "OnEntry", limit = 1, effects = {
				{ kind = "RandomChoice", options = {
					{ effects = { { kind = "ApplyStatus", target = "Self", status = "DmgUp", potency = 0.10, duration = 0 } } },
					{ effects = { { kind = "GainMaxHP", target = "Self", potency = 0.10 } } },
				} },
			} },
		},
		description = "On entry, randomly gains +10% DMG or +10% max HP for the battle.",
	},
	SecondLife = {
		id = "SecondLife", name = "Second Life",
		clauses = {
			{ trigger = "OnEntry", limit = 1, effects = {
				{ kind = "ApplyStatus", target = "Self", status = "DmgReduction", potency = 0.15, duration = 0 },
			} },
			{ trigger = "OnDeath", limit = 1, effects = {
				-- Revive clears the first life's statuses before the new 30% guard.
				{ kind = "Revive", target = "Self", hpPercent = 1 },
				{ kind = "ApplyStatus", target = "Self", status = "DmgReduction", potency = 0.30, duration = 0 },
			} },
		},
		description = "Takes 15% less damage. On death, revives once at full HP with 30% damage reduction.",
		restrictions = { "Revives once per battle" },
	},
	SystemHack = {
		id = "SystemHack", name = "System Hack",
		clauses = {
			{ trigger = "OnAttack", everyNth = 3, effects = {
				{ kind = "ApplyStatus", target = "ActiveEnemy", status = "SystemHack", potency = 0.20, duration = 0 },
			} },
		},
		description = "Every third attack makes the target's next attack deal 20% less damage. Does not stack.",
	},
	HandFromGod = {
		id = "HandFromGod", name = "Hand from God",
		clauses = {
			{ trigger = "OnAttackResolved", effects = { { kind = "HandFromGod" } } },
		},
		description = "Each attack marks its enemy. At 3 marks, consume them to deal 50% of that enemy's max HP as damage. Paired with Shinigami of Death: 4 marks deal 95% instead.",
	},
	AppleLover = {
		id = "AppleLover", name = "Apple Lover",
		clauses = {
			{ trigger = "OnAttacked", effects = { { kind = "AppleLover" } } },
		},
		description = "Whenever its partner is attacked, gain an apple. At 3 apples, the whole team takes 15% less damage for 3 turns. Once per match.",
		restrictions = { "Once per match for your team", "Requires 3 apples" },
	},
	Smarter = {
		id = "Smarter", name = "Smarter",
		clauses = {
			{ trigger = "OnEncounter", limit = 1, effects = { { kind = "Smarter" } } },
		},
		description = "Compare current HP with the first enemy it encounters: lower HP grants +30% DMG; higher HP grants +30% max and current HP. Equal HP grants no bonus.",
		restrictions = { "First enemy encountered only", "Equal HP grants no bonus" },
	},
	ElasticArm = {
		id = "ElasticArm", name = "Elastic Arm",
		clauses = {
			{ trigger = "OnAttack", chance = 0.50, condition = "HasNextEnemy", effects = {
				-- NextEnemy reaches past the active fighter to the one queued
				-- behind it, chipping at the enemy line before it arrives.
				{ kind = "Damage", target = "NextEnemy", potency = 0.15 },
			} },
		},
		description = "50% chance on attack to deal 15% DMG to the next enemy in line.",
	},

	-- ── attack passives ────────────────────────────────────────

	TwoSwordsStyle = {
		id = "TwoSwordsStyle", name = "Two Swords Style",
		clauses = {
			-- useSourceDmg pins the bleed to Zoro's DMG stat rather than to the
			-- size of the swing that applied it, so a crit does not quietly make
			-- the card hit harder than its own text claims.
			{ trigger = "OnAttack", chance = 0.25, effects = {
				{ kind = "ApplyStatus", target = "ActiveEnemy", status = "Bleed",
					stacks = 1, duration = 1, potency = 0.35, useSourceDmg = true },
			} },
		},
		description = "25% chance on attack to bleed the target for 35% DMG for 1 turn.",
	},

	-- The reward for clearing Pirate Shark on Impossible.
	--
	-- "the enemy has less DMG than you" is exactly StrongerThanTarget, which the
	-- engine already knows, so this needed no new condition. Freeze is the
	-- engine's stun (StatusEffects marks it skipsTurn) and a duration of 1 costs
	-- the target precisely one turn.
	--
	-- OnEntry with chance 1 means it either lands the moment the card arrives or
	-- not at all - it never gets a second look later in the fight, which is what
	-- keeps a guaranteed stun from being oppressive.
	GreaterWill = {
		id = "GreaterWill", name = "Greater Will",
		clauses = {
			{ trigger = "OnEntry", chance = 1, condition = "StrongerThanTarget", effects = {
				{ kind = "ApplyStatus", target = "ActiveEnemy", status = "Freeze",
					stacks = 1, duration = 1 },
			} },
		},
		description = "On entry: stuns the enemy for 1 turn if it has less DMG than this card.",
	},

	RainMercy = {
		id = "RainMercy", name = "Rain Mercy",
		clauses = {
			{ trigger = "OnAttack", chance = 1, effects = {
				{ kind = "Heal", target = "Self", potency = 0.05 },
			} },
		},
		description = "Heals 5% of max HP every time it attacks.",
	},

	PerfectShot = {
		id = "PerfectShot", name = "Perfect Shot",
		clauses = {
			-- Freeze is the engine's stun: StatusEffects marks it skipsTurn, and
			-- a duration of 1 costs the target exactly one turn.
			{ trigger = "OnAttack", chance = 0.10, effects = {
				{ kind = "ApplyStatus", target = "ActiveEnemy", status = "Freeze",
					stacks = 1, duration = 1 },
			} },
		},
		description = "10% chance on hit to stun the enemy for 1 turn.",
	},

	ColaOverload = {
		id = "ColaOverload", name = "Cola Overload",
		clauses = {
			{ trigger = "OnKill", chance = 0.30, effects = {
				{ kind = "Heal", target = "Self", potency = 0.5 },
			} },
		},
		description = "30% chance to heal 50% HP after defeating an enemy.",
	},

	PartingDose = {
		id = "PartingDose", name = "Parting Dose",
		clauses = {
			-- OnDeath fires after alive has already been set false, so AllAllies
			-- naturally excludes Chopper himself.
			{ trigger = "OnDeath", chance = 1, effects = {
				{ kind = "Heal", target = "AllAllies", potency = 0.15 },
			} },
		},
		description = "On death, heals every surviving ally for 15% of max HP.",
	},

	DevilsLeg = {
		id = "DevilsLeg", name = "Devil's Leg",
		clauses = {
			-- Two clauses rather than one, because "whenever it hits or is hit"
			-- is two different triggers and each rolls its own 25%.
			{ trigger = "OnAttack", chance = 0.25, effects = {
				{ kind = "ApplyStatus", target = "ActiveEnemy", status = "Burn",
					stacks = 1, duration = 1, potency = 0.25, useSourceDmg = true },
			} },
			{ trigger = "OnAttacked", chance = 0.25, effects = {
				{ kind = "ApplyStatus", target = "LastHit", status = "Burn",
					stacks = 1, duration = 1, potency = 0.25, useSourceDmg = true },
			} },
		},
		description = "25% chance to burn for 25% DMG whenever it hits or is hit.",
	},

	SliceAndDice = {
		id = "SliceAndDice", name = "Slice & Dice",
		clauses = {
			{ trigger = "OnAttack", chance = 1, condition = "StrongerThanTarget", effects = {
				{ kind = "ApplyStatus", target = "ActiveEnemy", status = "Bleed",
					stacks = 1, duration = 1, potency = 0.10, useSourceDmg = true },
			} },
		},
		description = "Bleeds the target for 10% DMG for 1 turn while it out-damages them.",
	},

	WillOfTheDragon = {
		id = "WillOfTheDragon", name = "Will of the Dragon",
		clauses = {
			-- limit = 1 is what makes this "the FIRST hit" rather than every hit;
			-- without it the card would be permanently untouchable.
			--
			-- Both effects sit in ONE clause so they cannot desync: the DMG is
			-- stolen exactly when the block happens, never on a later hit.
			-- `from = "LastHit"` resolves to the attacker, because during
			-- OnAttacked this card is the defender and the active enemy is the
			-- one swinging.
			{ trigger = "OnAttacked", chance = 1, limit = 1, effects = {
				{ kind = "CancelAttack" },
				{ kind = "GainDamage", from = "LastHit", potency = 0.10 },
			} },
		},
		description = "Blocks the first enemy hit and permanently steals 10% of that attacker's DMG.",
	},

	-- Unused since Dragon Warrior took over this slot. Left defined rather than
	-- deleted: PassiveDefinitions.get returns nil for a missing id and the card
	-- would silently render a blank ability if anything still pointed here.
	FlowerHands = {
		id = "FlowerHands", name = "Flower Hands",
		clauses = {
			-- DmgUp at potency 1.0 doubles output; duration 1 means it is gone by
			-- the end of the round.
			{ trigger = "OnEntry", chance = 0.50, effects = {
				{ kind = "ApplyStatus", target = "Self", status = "DmgUp",
					stacks = 1, duration = 1, potency = 1.0 },
			} },
			-- The heal is conditional on the buff still being up, so it only pays
			-- out on a kill made DURING the doubled turn - which is what the card
			-- promises. Without the condition it would heal on every kill for the
			-- rest of the fight.
			{ trigger = "OnKill", chance = 1, condition = "HasDmgUp", effects = {
				{ kind = "Heal", target = "Self", potency = 0.07 },
			} },
		},
		description = "On entry, 50% chance of double DMG for 1 turn. A kill during it heals 7% max HP.",
	},

	Forge = {
		id = "Forge", name = "Forge",
		clauses = {
			-- Led the party in: its death arms everyone still standing. namedPotency
			-- is what lets a single clause hand out two grades of buff at once -
			-- as two clauses each would roll its own chance and a card could end up
			-- with both buffs, or neither.
			--
			-- duration 0 means the buff lasts the whole battle; tickStatuses only
			-- counts down durations above zero.
			{ trigger = "OnDeath", chance = 1, condition = "PlayedFirst", limit = 1, effects = {
				{ kind = "ApplyStatus", target = "AllAllies", status = "DmgUp",
					stacks = 1, duration = 0, potency = 0.10,
					nameContains = "master", namedPotency = 0.20 },
			} },
			-- Came in last: it arrives carrying the weight of everyone who fell
			-- before it. scaleBy counts them at the moment it lands, and a party
			-- that has lost nobody scales to zero, so the clause grants nothing.
			{ trigger = "OnEntry", chance = 1, condition = "PlayedLast", limit = 1, effects = {
				{ kind = "GainDamage", from = "Self", potency = 0.15,
					scaleBy = "DefeatedAllies" },
			} },
		},
		description = "Played first: on death, allies gain 10% DMG, or 20% if they are a \"Master\". Played last: +15% DMG per fallen ally.",
	},

	LightningStrike = {
		id = "LightningStrike", name = "Lightning Strike",
		clauses = {
			-- limit = 1 is what makes this "the FIRST time it attacks".
			--
			-- The bonus lands as a SEPARATE follow-up hit rather than as a larger
			-- swing, because OnAttack fires after the swing has already resolved -
			-- there is no hit left to enlarge. It carries the "crit" tag so the log
			-- and the damage number read the way the card text promises.
			{ trigger = "OnAttack", chance = 1, limit = 1, effects = {
				{ kind = "Damage", target = "ActiveEnemy", potency = 0.20, tag = "crit" },
				{ kind = "ApplyStatus", target = "ActiveEnemy", status = "Freeze",
					stacks = 1, duration = 1 },
			} },
		},
		description = "First attack only: a critical for 20% extra DMG that stuns the enemy for 1 round.",
	},

	PowerWithin = {
		id = "PowerWithin", name = "Power Within",
		clauses = {
			-- scaleBy counts every card in the party whose NAME contains "master",
			-- this card included, and multiplies both gains by that count. A party
			-- with no masters scales to zero and the effects are skipped outright
			-- rather than applied at zero strength.
			{ trigger = "OnEntry", chance = 1, limit = 1, effects = {
				{ kind = "ApplyStatus", target = "Self", status = "DmgUp",
					stacks = 1, duration = 0, potency = 0.10,
					scaleBy = "AlliesNamed", nameContains = "master" },
				{ kind = "GainMaxHP", target = "Self", potency = 0.10,
					scaleBy = "AlliesNamed", nameContains = "master" },
			} },
		},
		description = "On entry, +10% DMG and max HP for every \"Master\" in your deck.",
	},

	Redirect = {
		id = "Redirect", name = "Redirect",
		clauses = {
			-- Both effects sit in ONE clause so they cannot desync: the damage is
			-- passed on exactly when the block happens, never on some later hit.
			--
			-- from = "LastHit" makes the redirected damage a share of the ATTACKER's
			-- DMG, which is what "50% of the blocked damage" means. Without it the
			-- effect would read off Moon Demon's own DMG and the number would have
			-- nothing to do with the hit that was actually stopped.
			{ trigger = "OnAttacked", chance = 0.30, limit = 3, effects = {
				{ kind = "CancelAttack" },
				{ kind = "Damage", target = "NextEnemy", from = "LastHit", potency = 0.50 },
			} },
		},
		-- The cap is NOT written here. It is read off the clause by
		-- PassiveDefinitions.restrictions and shown on the Shift panel, so the
		-- description can stay about what the ability DOES.
		description = "30% chance to block a hit and pass 50% of it to the next enemy in line.",
	},

	LastHope = {
		id = "LastHope", name = "Last Hope",
		clauses = {
			-- Gated on the condition rather than left to resolve to an empty target
			-- list, so on a deck without Master of Both the ability stays silent
			-- instead of announcing itself in the log and doing nothing.
			--
			-- Both gains read the partner's BASE stats, so fielding a Master of Both
			-- that has already been buffed does not inflate the inheritance.
			{ trigger = "OnEntry", chance = 1, condition = "HasMasterOfBoth", limit = 1, effects = {
				{ kind = "GainDamage", from = "Ally:MasterOfBoth", potency = 0.50 },
				{ kind = "GainMaxHP", target = "Self", from = "Ally:MasterOfBoth", potency = 0.50 },
			} },
		},
		description = "On entry, if \"Master of Both\" is in your deck, gain 50% of its base DMG and HP.",
	},

	WaterAndFire = {
		id = "WaterAndFire", name = "Water & Fire",
		clauses = {
			-- ONE clause, so the limit of 4 is SHARED: four activations in total, not
			-- four water blades and four fire blades. RandomChoice then picks exactly
			-- one branch per activation, which is what "50% chance to either... or..."
			-- means - it can never swing both blades on the same attack, and never
			-- neither.
			--
			-- The water blade lands as a follow-up hit for the same reason as
			-- Lightning Strike: OnAttack fires after the swing has already resolved.
			{ trigger = "OnAttack", chance = 1, limit = 4, effects = {
				{ kind = "RandomChoice", options = {
					{ effects = {
						{ kind = "Damage", target = "ActiveEnemy", potency = 0.20, tag = "crit" },
					} },
					{ effects = {
						{ kind = "ApplyStatus", target = "ActiveEnemy", status = "Freeze",
							stacks = 1, duration = 1 },
					} },
				} },
			} },
		},
		description = "Each attack: 50/50 a water blade for 20% extra DMG, or a fire blade that stuns for 1 round.",
	},

	-- ── the Son line ───────────────────────────────────────────
	-- Three cards that read each other. "Son Warrior" is the anchor: the Prince
	-- borrows his growth and the Prodigy changes shape entirely when he is in the
	-- deck, so both name him through HasAlly rather than by any shared tag.

	TheFirstOfMany = {
		id = "TheFirstOfMany", name = "The First of Many",
		clauses = {
			-- everyNth counts ATTACKS, not turns, so a double strike advances the
			-- rhythm twice and the beam lands on the beat the card promises.
			--
			-- The beam is a follow-up hit rather than a larger swing for the same
			-- reason as Lightning Strike: OnAttack fires after the swing has already
			-- resolved, so there is no hit left to enlarge.
			{ trigger = "OnAttack", chance = 1, everyNth = 2, effects = {
				{ kind = "Damage", target = "ActiveEnemy", potency = 0.50, tag = "crit" },
			} },
			-- OnDeath fires after alive is already false, so AllAllies excludes him.
			{ trigger = "OnDeath", chance = 1, effects = {
				{ kind = "ApplyStatus", target = "AllAllies", status = "DmgReduction",
					stacks = 1, duration = 2, potency = 0.15 },
			} },
		},
		description = "Every second attack fires a beam for 50% DMG. On death, allies take 15% less damage for 2 turns.",
	},

	YouAreNumberOne = {
		id = "YouAreNumberOne", name = "You Are Number One",
		clauses = {
			-- ONE clause, so the Prince and his partner are raised at the same
			-- instant and neither can land without the other.
			--
			-- The second effect needs no ally check of its own: "Ally:SonWarrior"
			-- resolves to nothing on a deck without him, and GainMaxHP over an empty
			-- target list is silently a no-op.
			{ trigger = "OnTurnStart", chance = 1, condition = "SurvivedTurns:2", limit = 1, effects = {
				{ kind = "GainMaxHP", target = "Self", potency = 0.30 },
				{ kind = "GainMaxHP", target = "Ally:SonWarrior", potency = 0.30 },
			} },
		},
		description = "After surviving 2 turns: +30% max HP, and the same to \"Son Warrior\" if he is in your deck.",
	},

	WillOfTheMachine = {
		id = "WillOfTheMachine", name = "Will of the Machine",
		clauses = {
			-- The confusion is a hit the enemy takes FROM ITS OWN DMG - `from` is what
			-- re-bases it onto the target's stat instead of the Mentor's. It is a
			-- separate hit landing after the normal swing, so it adds to the damage
			-- rather than replacing any of it: the card text is explicit that being
			-- confused does not spare you.
			{ trigger = "OnAttack", chance = 0.50, effects = {
				{ kind = "Damage", target = "ActiveEnemy", from = "ActiveEnemy", potency = 0.30 },
			} },
			-- basis "MaxHP" reads the Mentor's own ceiling, so the blast is a share of
			-- how much machine there was to detonate rather than of what it hit for.
			{ trigger = "OnDeath", chance = 1, effects = {
				{ kind = "Damage", target = "AllEnemies", basis = "MaxHP", potency = 0.15 },
			} },
		},
		description = "50% on attack: the enemy strikes itself for 30% of its own DMG. On death, explodes for 15% max HP to all enemies.",
	},

	SaveTheFuture = {
		id = "SaveTheFuture", name = "Save the Future",
		clauses = {
			-- chanceOnHit is the mirror of chanceOnFail: it moves the clause's chance
			-- every time the clause LANDS. Negative, so each volley makes the next one
			-- less likely - 75, 60, 45, 30, 15, then spent for the rest of the battle.
			--
			-- Two Damage effects in ONE clause, not two clauses: the pair is a single
			-- volley and must roll once, or one beam could fire without the other.
			{ trigger = "OnAttack", chance = 0.75, chanceOnHit = -0.15, effects = {
				{ kind = "Damage", target = "ActiveEnemy", potency = 0.35, tag = "crit" },
				{ kind = "Damage", target = "ActiveEnemy", potency = 0.35, tag = "crit" },
			} },
		},
		description = "75% chance after attacking to fire two beams for 35% DMG each. Every volley drops that chance by 15%.",
	},

	MorePower = {
		id = "MorePower", name = "More Power!!",
		clauses = {
			-- "Victim" is the only way to reach the card that just died: by the time
			-- OnKill fires it is out of the queue, so ActiveEnemy and LastHit have
			-- both moved on to whoever stepped into its place.
			--
			-- `absorbs` banks each gain so the death clause below has something to
			-- spend. Without it the bug would grow but detonate for nothing.
			{ trigger = "OnKill", chance = 1, effects = {
				{ kind = "GainDamage", from = "Victim", potency = 0.20, absorbs = true },
				{ kind = "GainMaxHP", target = "Self", from = "Victim", potency = 0.20, absorbs = true },
			} },
			-- A bug that never ate anything absorbed nothing, and basis "Absorbed"
			-- skips the effect outright rather than floor it to a 1-point hit that
			-- would read as the ability having fired.
			{ trigger = "OnDeath", chance = 1, effects = {
				{ kind = "Damage", target = "ActiveEnemy", basis = "Absorbed", potency = 1 },
			} },
		},
		description = "Absorbs 20% of the stats of every enemy it defeats. On death, detonates all of it into the active enemy.",
	},

	FinalBlast = {
		id = "FinalBlast", name = "Final Blast",
		clauses = {
			-- Charging skips exactly one turn, the same way Freeze does, but is filed
			-- under Buff so a challenge that switches off control effects cannot
			-- delete the wind-up and leave the payout waiting forever.
			{ trigger = "OnEntry", chance = 1, limit = 1, effects = {
				{ kind = "ApplyStatus", target = "Self", status = "Charging",
					stacks = 1, duration = 1 },
			} },
			-- Two mutually exclusive payouts, told apart by whether the anchor of the
			-- line is in the deck. Both gated on SurvivedTurns:2 as well, which is
			-- what makes it the SECOND turn rather than the one it spent charging.
			{ trigger = "OnTurnStart", chance = 1, limit = 1,
				conditions = { "SurvivedTurns:2", "HasAlly:SonWarrior" }, effects = {
				-- Same 200% blast; the 50% splash reaches EVERY enemy instead of
				-- only the next in line (the active one included).
				{ kind = "Damage", target = "ActiveEnemy", potency = 2.00, tag = "crit" },
				{ kind = "Damage", target = "AllEnemies", potency = 0.50 },
			} },
			{ trigger = "OnTurnStart", chance = 1, limit = 1,
				conditions = { "SurvivedTurns:2", "!HasAlly:SonWarrior" }, effects = {
				{ kind = "Damage", target = "ActiveEnemy", potency = 2.00, tag = "crit" },
				{ kind = "Damage", target = "NextEnemy", potency = 0.50 },
			} },
		},
		-- Written out by hand: the derived wording would list "Once per battle"
		-- three times over and say nothing about the charge turn, which is the part
		-- a player actually has to plan around.
		restrictions = {
			"Cannot attack on the turn it enters",
			"The blast fires once per battle",
		},
		description = "Charges for a turn, then blasts for 200% DMG and 50% to the next in line. If paired with \"Son Warrior\", the 50% hits all enemies instead.",
	},

	RunAndGun = {
		id = "RunAndGun", name = "Run & Gun",
		-- replacesBasic says the volley IS the attack, not a basic swing that
		-- happens to land several times. The presentation layer reads it to drop
		-- the attack lunge (this card never steps in to swing) and to play the
		-- burst VFX once for the whole volley instead of once per bullet.
		attackPattern = { minHits = 5, maxHits = 12, potency = 0.20, replacesBasic = true },
		clauses = {
			{ trigger = "OnFatalHit", limit = 1, effects = {
				{ kind = "RestoreHP", hpPercent = 0.30 },
			} },
		},
		restrictions = { "Survives the first fatal hit once per battle" },
		description = "Replaces each basic attack with 5-12 shots, each dealing 20% DMG. Survives the first fatal hit with 30% max HP.",
	},
	ShinigamiFreeze = {
		id = "ShinigamiFreeze", name = "Freeze",
		clauses = {
			{ trigger = "OnHealthChanged", condition = "HPAtMost:0.30", limit = 1, effects = {
				{ kind = "ApplyStatus", target = "Self", status = "FreezeReady", duration = 0 },
			} },
			{ trigger = "OnAttack", condition = "HasStatus:FreezeReady", limit = 1, effects = {
				{ kind = "RemoveStatus", target = "Self", status = "FreezeReady" },
				{ kind = "ApplyStatus", target = "ActiveEnemy", status = "Freeze", duration = 2 },
				{ kind = "ApplyStatus", target = "ActiveEnemy", status = "Frostbite", duration = 2, potency = 0.10, useSourceDmg = true },
			} },
		},
		restrictions = { "Arms once per battle at 30% HP or less", "Activates on the next unblocked attack" },
		description = "After reaching 30% HP, the next attack stuns for 2 turns and applies frostbite for 10% of this card's DMG for 2 turns.",
	},
	HungerForBattle = {
		id = "HungerForBattle", name = "Hunger for Battle",
		clauses = {
			-- oncePerAttack: a volley is ONE attack however many bullets are in it.
			-- Without this a 12-shot attack handed the card +120% DMG in one turn,
			-- which is not what "each damaging hit taken" means on the card face.
			{ trigger = "OnHitTaken", oncePerAttack = true, effects = {
				{ kind = "GainDamage", from = "Self", potency = 0.10 },
			} },
			{ trigger = "OnDeath", effects = {
				{ kind = "Damage", target = "ActiveEnemy", basis = "BaseDMG", potency = 2.50, resolveImmediately = true },
			} },
		},
		description = "Each damaging hit taken adds 10% of original DMG. On death, deals 250% of original DMG to the active enemy, excluding gained damage.",
	},
	ShinigamiDoubleStrike = {
		id = "ShinigamiDoubleStrike", name = "Double Strike",
		attackPattern = { doubleEvery = 2 },
		clauses = {
			{ trigger = "OnAttacked", chance = 0.15, limit = 3, effects = {
				{ kind = "CancelAttack" },
			} },
		},
		restrictions = { "Blocks up to 3 attacks per battle" },
		description = "Every second attack strikes twice. Has a 15% chance to block an enemy attack, up to 3 times.",
	},
	MasterManipulator = {
		id = "MasterManipulator", name = "Master Manipulator",
		clauses = {
			{ trigger = "OnAttacked", chance = 0.80, chanceOnHit = -0.15, condition = "CanDazeAttacker", effects = {
				{ kind = "ApplyStatus", target = "Attacker", status = "Daze", duration = 1 },
			} },
		},
		restrictions = { "Daze lasts one turn and is consumed by the incoming attack", "Requires a living ally of the attacker", "Can reapply to the same enemy or different enemies" },
		description = "When attacked, 80% chance to daze for this attack: each hit deals 80% to a random ally and 20% to this card. Each successful activation lowers the chance by 15 percentage points, to 0%, for this battle.",
	},
	SlashSlashSlash = {
		id = "SlashSlashSlash", name = "Slash Slash Slash",
		clauses = {
			{ trigger = "OnAttack", chance = 0.50, condition = "HasNextEnemy", effects = {
				{ kind = "Damage", target = "NextEnemy", potency = 1, resolveImmediately = true },
			} },
			{ trigger = "OnDeath", effects = {
				{ kind = "Damage", target = "ActiveAndNextEnemy", potency = 1, resolveImmediately = true },
			} },
		},
		description = "50% chance after attacking to slash the next enemy for 100% DMG. On death, slashes the active enemy and next in line for 100% DMG each.",
	},

	-- ── support passives ───────────────────────────────────────
	-- Supports never take the field, so these all reach their partner through
	-- the PairedCard target rather than acting on themselves.

	BruteForce = {
		id = "BruteForce", name = "Brute Force",
		clauses = {
			{ trigger = "OnEntry", chance = 1, effects = {
				{ kind = "ApplyStatus", target = "PairedCard", status = "DmgReduction",
					stacks = 1, duration = 0, potency = 0.25 },
			} },
		},
		description = "Its partner takes 25% less damage for the whole battle.",
	},

	Sneaky = {
		id = "Sneaky", name = "Sneaky",
		clauses = {
			-- duration 4 means four ROUNDS, ticked down by tickStatuses like any
			-- other timed status; 0 would mean the whole battle.
			{ trigger = "OnEntry", chance = 1, effects = {
				{ kind = "ApplyStatus", target = "PairedCard", status = "Dodge",
					stacks = 1, duration = 4, potency = 0.15 },
			} },
		},
		description = "Its partner has a 15% chance to dodge attacks for 4 rounds.",
	},

	SystemOverload = {
		id = "SystemOverload", name = "System Overload",
		clauses = {
			-- limit = 1 is load-bearing. OnDamage fires on EVERY hit taken, and the
			-- condition stays true for the rest of the fight once HP is low, so
			-- without it the card would gain 15% again on every single hit.
			{ trigger = "OnDamage", chance = 1, condition = "BelowHalfHP", limit = 1, effects = {
				{ kind = "ApplyStatus", target = "Self", status = "DmgUp",
					stacks = 1, duration = 0, potency = 0.15 },
				{ kind = "GainMaxHP", target = "Self", potency = 0.15 },
			} },
		},
		description = "The first time its partner drops below 50% HP, it gains 15% DMG and 15% max HP for the rest of the battle.",
	},

	JustCloneIt = {
		id = "JustCloneIt", name = "Just Clone It",
		clauses = {
			{ trigger = "OnDeath", chance = 1, limit = 1, effects = {
				{ kind = "SummonClone", statScale = 0.5 },
			} },
		},
		description = "When its partner is defeated, a copy with half stats and no ability joins the back of the party.",
	},

	Shuriken = {
		id = "Shuriken", name = "Shuriken",
		clauses = {
			-- useSourceDmg pins the bleed to the partner's DMG stat rather than to
			-- the size of the swing that applied it, so a crit cannot quietly make
			-- the card bleed for more than its text claims.
			{ trigger = "OnAttack", chance = 0.25, effects = {
				{ kind = "ApplyStatus", target = "ActiveEnemy", status = "Bleed",
					stacks = 1, duration = 1, potency = 0.25, useSourceDmg = true },
			} },
		},
		description = "25% chance on attack to bleed the target for 25% of its partner's DMG.",
	},

	Yummy = {
		id = "Yummy", name = "Yummy",
		clauses = {
			-- Scales off the hit just taken, not off max HP, so a big hit heals back
			-- proportionally more than a chip of damage does.
			{ trigger = "OnDamage", chance = 1, effects = {
				{ kind = "Heal", target = "Self", potency = 0.10, scalesWith = "DamageTaken" },
			} },
		},
		description = "Its partner heals for 10% of every hit it takes.",
	},

	Trickery = {
		id = "Trickery", name = "Trickery",
		clauses = {
			-- NextEnemy reaches past the active fighter to the one queued behind it.
			{ trigger = "OnAttack", chance = 0.20, condition = "HasNextEnemy", effects = {
				{ kind = "Damage", target = "NextEnemy", potency = 0.20 },
			} },
		},
		description = "20% chance on attack to pierce through for 20% DMG to the next enemy in line.",
	},

	DreamOn = {
		id = "DreamOn", name = "Dream On",
		clauses = {
			-- Freeze is the engine's stun: StatusEffects marks it skipsTurn, so a
			-- duration of 2 costs the target exactly two turns.
			-- Capped at 2 activations. An uncapped 2-round stun on a 60% roll could
			-- chain often enough to take a fight away from the other side entirely -
			-- the limit is what stops it, and the lower chance is what keeps the
			-- first one from feeling automatic.
			{ trigger = "OnAttack", chance = 0.25, limit = 2, effects = {
				{ kind = "ApplyStatus", target = "ActiveEnemy", status = "Freeze",
					stacks = 1, duration = 2 },
			} },
		},
		description = "25% chance on attack to stun the enemy for 2 rounds.",
	},

	KindleWard = {
		id = "KindleWard", name = "Kindle Ward",
		clauses = {
			{ trigger = "OnEntry", chance = 1, effects = {
				{ kind = "ApplyStatus", target = "PairedCard", status = "DmgUp",
					stacks = 1, duration = 0, potency = 0.1 },
			} },
		},
		description = "Its partner fights with +10% DMG for the whole battle.",
	},

	MarrowMend = {
		id = "MarrowMend", name = "Marrow Mend",
		clauses = {
			{ trigger = "OnTurnStart", chance = 0.3, effects = {
				{ kind = "Heal", target = "PairedCard", potency = 0.06 },
			} },
		},
		description = "30% chance each turn to heal its partner for 6% HP.",
	},

	GaleUrge = {
		id = "GaleUrge", name = "Gale Urge",
		clauses = {
			{ trigger = "OnEntry", chance = 1, effects = {
				{ kind = "ExtraAttack", chanceBonus = 0.2 },
			} },
		},
		description = "Gives its partner a 20% chance to strike twice.",
	},

	QuillAegis = {
		id = "QuillAegis", name = "Quill Aegis",
		clauses = {
			{ trigger = "OnEntry", chance = 1, effects = {
				{ kind = "ApplyStatus", target = "PairedCard", status = "DmgReduction",
					stacks = 1, duration = 0, potency = 0.15 },
			} },
		},
		description = "Its partner takes 15% less damage for the whole battle.",
	},

	Factory = {
		id = "Factory", name = "Factory",
		clauses = {
			-- Money is a pure COUNTER status: no effect of its own, read by the clause
			-- below through HasStacks. duration 0 means it never expires, so the count
			-- survives a long fight.
			{ trigger = "OnAttacked", chance = 0.68, effects = {
				{ kind = "ApplyStatus", target = "Self", status = "Money",
					stacks = 1, duration = 0 },
			} },
			-- Same trigger, evaluated after the clause above, so the third coin pays
			-- out on the very hit that banked it rather than on the next one.
			--
			-- limit = 1 is what "once per supported card" means: clause state is kept
			-- per CARD, and a support's clauses run on its partner, so the cap is
			-- naturally per partner rather than per support.
			{ trigger = "OnAttacked", chance = 1, condition = "HasStacks:Money:3", limit = 1, effects = {
				{ kind = "Heal", target = "Self", potency = 1 },
			} },
		},
		description = "68% chance to bank a coin whenever its partner is attacked. The third coin heals it to full.",
	},

	LanternOath = {
		id = "LanternOath", name = "Lantern Oath",
		clauses = {
			{ trigger = "OnEntry", chance = 1, effects = {
				{ kind = "ApplyStatus", target = "PairedCard", status = "CritUp",
					stacks = 1, duration = 0, potency = 0.2 },
			} },
			{ trigger = "OnKill", chance = 1, effects = {
				{ kind = "Heal", target = "PairedCard", potency = 0.12 },
			} },
		},
		description = "Partner gains +20% crit, and heals 12% HP on every kill.",
	},
}

function PassiveDefinitions.get(id: string)
	return PassiveDefinitions.Data[id]
end

----------------------------------------------------------------
-- RESTRICTIONS
----------------------------------------------------------------
--
-- The fine print of an ability: how many times it may fire, and what has to be
-- true for it to fire at all.
--
-- DERIVED from the clauses rather than written out per passive, because the two
-- used to be maintained separately and drifted: a description could claim
-- "3 times max" while the clause actually said 4, and nothing would catch it.
-- Now the cap shown to the player IS the cap the engine enforces - there is only
-- one number - which frees descriptions to be about what the ability does.
--
-- A passive may still set `restrictions = { "..." }` to override the wording
-- where the automatic phrasing reads badly.

local CONDITION_TEXT = {
	BelowHalfHP        = "Only while below half HP",
	StrongerThanTarget = "Only while out-damaging the enemy",
	HasDmgUp           = "Only while a DMG buff is active",
	PlayedFirst        = "Only if played first",
	PlayedLast         = "Only if played last",
	HasMasterOfBoth    = 'Requires "Master of Both" in your deck',
	HasNextEnemy       = "Requires another enemy behind the target",
}

-- "SonWarrior" -> "Son Warrior".
--
-- Deliberately NOT a lookup in CardDefinitions. This module requires nothing at
-- all, and every consumer of it - the renderer, the deck screen, the offline
-- balance tooling - benefits from it staying that way. The cost is that an id
-- whose display name is not simply its id spaced out would read wrong here, so
-- name a card that other cards NAME in their text after its id.
local function humanise(id: string): string
	return (id:gsub("(%l)(%u)", "%1 %2"))
end

-- Condition specs may be parameterised ("SurvivedTurns:2") and may be negated
-- with a leading "!", so the plain lookup above cannot cover them alone.
local function conditionText(spec: string): string?
	local negate = false
	if spec:sub(1, 1) == "!" then
		negate = true
		spec = spec:sub(2)
	end

	local name, arg = spec:match("^([^:]+):(.+)$")
	if not name then
		return CONDITION_TEXT[spec]
	end

	if name == "SurvivedTurns" then
		return ("Only after %s turns on the field"):format(arg)
	end

	if name == "HasAlly" then
		return negate
			and ('Only without "%s" in your deck'):format(humanise(arg))
			or ('Requires "%s" in your deck'):format(humanise(arg))
	end

	if name == "HasStatus" then
		return negate
			and ("Only while not %s"):format(string.lower(humanise(arg)))
			or ("Only while %s"):format(string.lower(humanise(arg)))
	end

	if name == "HasStacks" then
		local status, count = arg:match("^(.-):(%d+)$")
		if status then
			return ("Needs %s stacks of %s"):format(count, humanise(status))
		end
	end

	return nil
end

function PassiveDefinitions.restrictions(id): { string }
	local passive = id and PassiveDefinitions.get(id)
	if not passive then return {} end
	if passive.restrictions then return passive.restrictions end

	local out, seen = {}, {}
	local function add(line)
		if line and not seen[line] then
			seen[line] = true
			table.insert(out, line)
		end
	end

	for _, clause in ipairs(passive.clauses or {}) do
		if clause.limit then
			-- Deduped: Forge carries two once-only clauses that are mutually
			-- exclusive, and listing "Once per battle" twice reads as a bug.
			add(clause.limit == 1
				and "Once per battle"
				or ("Up to %d times per battle"):format(clause.limit))
		end
		if clause.condition then
			add(conditionText(clause.condition))
		end
		-- The AND list, for clauses whose gate is more than one fact.
		for _, spec in ipairs(clause.conditions or {}) do
			add(conditionText(spec))
		end
	end

	return out
end

function PassiveDefinitions.hasRestrictions(id): boolean
	return #PassiveDefinitions.restrictions(id) > 0
end

-- Attack replacements are opt-in; legacy cards keep their original attack path.
function PassiveDefinitions.attackPattern(passives)
	for _, id in ipairs(passives or {}) do
		local passive = PassiveDefinitions.get(id)
		if passive and passive.attackPattern then return passive.attackPattern end
	end
	return nil
end

return PassiveDefinitions



