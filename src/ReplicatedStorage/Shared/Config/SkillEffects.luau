--!strict
-- What a skill actually DOES, as a registry rather than a chain of ifs.
--
-- Adding an effect is an entry in Registry plus one line wherever that stat is
-- consumed. There is deliberately no `if skillId == "LuckBoost"` anywhere in the
-- codebase: skills name an EffectType, EffectTypes name a stat, and the stat is
-- read by the system that cares about it.
--
-- WHY THIS LIVES IN SHARED, NOT ON THE SERVER
-- The details panel has to show "current effect" and "next effect" before the
-- player buys anything. If the client computed those with its own copy of the
-- maths, the preview could drift from what the server actually grants - the
-- worst kind of bug, because it looks like the purchase was cheated. Both sides
-- call Totals() here, so the number shown is the number applied by construction.
--
-- The server remains the only thing that WRITES. Nothing here mutates a profile.

local SkillEffects = {}

-- Tiny per-rank bonuses need decimal precision or rank 1 would literally render
-- as "+0%". This keeps small gains readable while avoiding ugly 6-decimal text
-- once the cumulative bonus becomes large.
local function percentText(fraction: number): string
	local pct = fraction * 100
	local magnitude = math.abs(pct)
	if magnitude < 1 then
		return ("%.3f%%"):format(pct)
	elseif magnitude < 10 then
		return ("%.2f%%"):format(pct)
	end
	return ("%.1f%%"):format(pct)
end

-- stat     the accumulator key this effect feeds
-- combine  how multiple skills feeding the same stat merge:
--            "multiply" for multipliers, whose identity is 1
--            "add"      for flat bonuses, whose identity is 0
-- base     the identity value, i.e. the stat with no skills at all
-- label    what the details panel calls this stat
-- format   turns a value into player-facing text
SkillEffects.Registry = {
	-- Flat luck: an absolute number ADDED to the roll multiplier, not a
	-- percentage of it. Luck Boost rank 3000 is +750 luck, full stop - which is
	-- why it combines by addition and its identity is 0, not 1.
	LuckFlat = {
		stat = "luckFlat", combine = "add", base = 0,
		label = "Luck",
		format = function(v: number): string
			return ("+%.2f luck"):format(v)
		end,
	},

	LuckMultiplier = {
		stat = "luckMultiplier", combine = "multiply", base = 1,
		label = "Roll Luck",
		format = function(v) return "+" .. percentText(v - 1) .. " luck" end,
	},
	RollSpeedBonus = {
		stat = "rollSpeedReduction", combine = "add", base = 0,
		label = "Roll Speed",
		format = function(v) return "-" .. percentText(v) .. " roll cooldown" end,
	},
	CoinGain = {
		stat = "coinMultiplier", combine = "multiply", base = 1,
		label = "Elder Coins",
		format = function(v) return "+" .. percentText(v - 1) .. " coins from victories" end,
	},
	DamageMultiplier = {
		stat = "damageMultiplier", combine = "multiply", base = 1,
		label = "Card DMG",
		format = function(v) return "+" .. percentText(v - 1) .. " DMG in battle" end,
	},
	MaxHPMultiplier = {
		stat = "hpMultiplier", combine = "multiply", base = 1,
		label = "Card HP",
		format = function(v) return "+" .. percentText(v - 1) .. " HP in battle" end,
	},
	CritChanceBonus = {
		stat = "critBonus", combine = "add", base = 0,
		label = "Crit Chance",
		format = function(v) return "+" .. percentText(v) .. " crit chance" end,
	},
}

-- Every stat at its identity value: a player who has bought nothing.
--
-- Built FROM the registry rather than hand-listed, so a newly added effect type
-- cannot be forgotten here and silently total to nil.
function SkillEffects.NewTotals()
	local totals = {}
	for _, effect in pairs(SkillEffects.Registry) do
		totals[effect.stat] = effect.base
	end
	return totals
end

-- Folds a rank map - { LuckBoost = 3, SwiftHands = 1 } - into a stat table.
--
-- `definitions` is passed in rather than required at the top so this module has
-- no dependency of its own: SkillDefinitions validates itself at require time
-- and has no need to know anything about effects.
function SkillEffects.Totals(definitions, skills)
	local totals = SkillEffects.NewTotals()

	for skillId, rank in pairs(skills or {}) do
		local def = definitions.get(skillId)
		-- A rank for a skill that no longer exists, or one above the current
		-- MaxRank, is clamped or skipped rather than trusted. Both happen quite
		-- legitimately after a balance edit, and neither should grant a bonus the
		-- table no longer describes.
		if def and type(rank) == "number" and rank >= 1 then
			local effect = SkillEffects.Registry[def.EffectType]
			-- EffectValue is a FUNCTION of rank now, and the rank is clamped before
			-- the call: a save holding a rank above the current MaxRank (which a
			-- balance edit creates legitimately) must not be able to read a value off
			-- the end of the curve.
			local value = def.EffectValue(math.min(rank, def.MaxRank))
			if effect and value then
				if effect.combine == "multiply" then
					totals[effect.stat] *= value
				else
					totals[effect.stat] += value
				end
			end
		end
	end

	return totals
end

-- What ONE skill contributes at a given rank, for the panel's current/next
-- lines. Returns nil at rank 0 so the caller can print "none" rather than "+0%".
function SkillEffects.DescribeRank(def, rank: number): string?
	if not def or rank < 1 then
		return nil
	end
	local effect = SkillEffects.Registry[def.EffectType]
	local value = def.EffectValue(math.min(rank, def.MaxRank))
	if not (effect and value) then
		return nil
	end
	return effect.format(value)
end

function SkillEffects.LabelFor(effectType: string): string
	local effect = SkillEffects.Registry[effectType]
	return effect and effect.label or effectType
end

return SkillEffects
