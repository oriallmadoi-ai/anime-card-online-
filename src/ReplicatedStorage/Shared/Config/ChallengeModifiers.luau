--!strict
-- Fight-wide rules attached to a stage or raid, shown in the Challenges panel.
-- These deliberately switch off whole *categories* of behaviour rather than
-- naming individual cards, so they keep working as you add hundreds of cards.

local ChallengeModifiers = {}

ChallengeModifiers.Data = {
	NoHealing = {
		id = "NoHealing",
		display = "Allies cannot heal",
		disablesCategories = { "Heal" },
	},
	NoRevive = {
		id = "NoRevive",
		display = "Allies cannot revive",
		disablesEffects = { "Revive" },
	},
	NoControl = {
		id = "NoControl",
		display = "Allies cannot freeze or stop time",
		disablesCategories = { "Control" },
	},
	BuffCeiling = {
		id = "BuffCeiling",
		display = "Ally stat boosts above 115% of base are cancelled",
		maxStatMultiplier = 1.15,
	},
	EnemyRage = {
		id = "EnemyRage",
		display = "Enemies gain 10% DMG each turn",
		enemyDmgPerTurn = 0.10,
	},
}

function ChallengeModifiers.get(id: string)
	return ChallengeModifiers.Data[id]
end

return ChallengeModifiers
