--!strict
-- The chips printed at the bottom of a card ("One Per Party", "Effect Cap",
-- "Revive Limit", "Stack Limit"). These are the rules that stop a deck of eight
-- identical broken cards from multiplying into infinity.
--
-- NOT WIRED UP YET. These are defined and nothing reads them: no card carries
-- a `limits` field and CombatEngine does not require this module, so none of
-- the five rules below is currently enforced anywhere. This header used to
-- claim the combat engine enforced all of them, which would have been a very
-- expensive thing to believe while designing a card around it.
--
-- The intent when they are implemented: enforcement belongs in the combat
-- engine, not in the passive, so a new card cannot accidentally opt out.

local Limits = {}

Limits.Data = {
	OnePerParty = {
		id = "OnePerParty",
		display = "One Per Party",
		description = "Only one copy of this card may be in a party.",
	},
	ReviveLimit = {
		id = "ReviveLimit",
		display = "Revive Limit",
		description = "This card can only revive once per battle, regardless of source.",
	},
	EffectCap = {
		id = "EffectCap",
		display = "Effect Cap",
		description = "Stat boosts from this card are capped and do not stack past the cap.",
	},
	StackLimit = {
		id = "StackLimit",
		display = "Stack Limit",
		description = "Statuses applied by this card cannot exceed their maximum stacks.",
	},
	TimeStopLimit = {
		id = "TimeStopLimit",
		display = "Time Stop",
		description = "Only one Time Stop can be active at a time across the whole battle.",
	},
}

function Limits.get(id: string)
	return Limits.Data[id]
end

return Limits
