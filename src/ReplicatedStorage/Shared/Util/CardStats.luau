--!strict
-- Single source of truth for what a copy is worth. Server and client both use
-- this, so a number in the UI can never disagree with the number in combat.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CardDefinitions = require(ReplicatedStorage.Shared.Config.CardDefinitions)
local SupportDefinitions = require(ReplicatedStorage.Shared.Config.SupportDefinitions)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local CardStats = {}

-- Levels run 0..100 and every copy starts at 0, so level 0 must mean "base
-- stats, no bonus" - hence the subtraction of GameConfig.MinCardLevel, which
-- is 0. Do not write the floor as a literal here: it is a balance number and
-- it lives in GameConfig.
--
-- `cardId` is optional and only affects the CEILING: boss cards level past 100,
-- and without it their extra levels would be clamped away here and quietly do
-- nothing. Callers that do not know the card keep the normal 100 cap, which is
-- the safe direction to be wrong in.
function CardStats.levelMultiplier(level: number, cardId: string?): number
	local cap = cardId and CardDefinitions.maxLevel(cardId) or GameConfig.MaxCardLevel
	local lv = math.clamp(level, GameConfig.MinCardLevel, cap)
	return 1 + ((lv - GameConfig.MinCardLevel) * GameConfig.StatBonusPerLevel)
end

-- Attack-card stats come from the copy's full effective rarity. This keeps
-- power monotonic across base cards and variants: if the printed denominator
-- is higher, both DMG and HP are higher. Supports still resolve to zeroes.
function CardStats.compute(cardId: string, variant: string, level: number)
	local attackDef = CardDefinitions.get(cardId)
	if attackDef then
		local effectiveRarity = VariantConfig.effectiveRarity(
			attackDef.baseRarity,
			variant
		)
		local baseDMG, baseHP
		if effectiveRarity == attackDef.baseRarity then
			-- CardDefinitions already makes the configured Basic-card order strict
			-- after rounding, so preserve those canonical base values.
			baseDMG = attackDef.baseDMG
			baseHP = attackDef.baseHP
		else
			baseDMG, baseHP = CardDefinitions.statsForRarity(effectiveRarity)
		end
		local levelMult = CardStats.levelMultiplier(level, cardId)
		return {
			dmg = math.floor(baseDMG * levelMult),
			hp = math.floor(baseHP * levelMult),
		}
	end

	local supportDef = SupportDefinitions.get(cardId)
	if supportDef then
		return { dmg = 0, hp = 0 }
	end

	return nil
end

function CardStats.definition(cardId: string)
	return CardDefinitions.get(cardId) or SupportDefinitions.get(cardId)
end

function CardStats.isSupport(cardId: string): boolean
	return SupportDefinitions.get(cardId) ~= nil
end

-- Inventory keys are "cardId|Variant". Centralised so a format change is a
-- one-line edit rather than a search across the codebase.
function CardStats.key(cardId: string, variant: string): string
	return cardId .. "|" .. variant
end

function CardStats.parseKey(key: string): (string?, string?)
	return key:match("^(.-)|(.+)$")
end

return CardStats
