--!strict
-- Shared ability rules used by both combat runtimes. Effects are executed by
-- the existing runtime so damage, status visuals and challenge rules still apply.
local CardAbilityRules = {}

function CardAbilityRules.handles(kind)
	return kind == "HandFromGod" or kind == "AppleLover" or kind == "Smarter"
end

function CardAbilityRules.expand(kind, source, target, match, context)
	if kind == "HandFromGod" then
		if not target or not target.alive or target.hp <= 0 then return {} end
		local paired = table.find(source.supportPassives or {}, "AppleLover") ~= nil
		local threshold = paired and 4 or 3
		local marks = target.statuses.DivineMark
		local count = (marks and marks.stacks or 0) + 1
		local effects = {
			{ kind = "ApplyStatus", target = "ActiveEnemy", status = "DivineMark", stacks = 1, duration = 0 },
		}
		if count >= threshold then
			table.insert(effects, { kind = "RemoveStatus", target = "ActiveEnemy", status = "DivineMark" })
			table.insert(effects, { kind = "Damage", target = "ActiveEnemy", basis = "TargetMaxHP",
				potency = paired and 0.95 or 0.50, tag = "divineMark", resolveImmediately = true })
		end
		return effects
	elseif kind == "AppleLover" then
		-- Team-scoped and owned by the match, so death/revival or a second copy
		-- of the support cannot award a second team buff in this match.
		match.appleLoverUsed = match.appleLoverUsed or {}
		if match.appleLoverUsed[source.team] then return {} end
		local apples = source.statuses.Apple
		local count = (apples and apples.stacks or 0) + 1
		local effects = {
			{ kind = "ApplyStatus", target = "Self", status = "Apple", stacks = 1, duration = 0 },
		}
		if count >= 3 then
			match.appleLoverUsed[source.team] = true
			-- AllAllies excludes the supported fighter in the existing target API.
			table.insert(effects, { kind = "ApplyStatus", target = "Self", status = "AppleGuard",
				stacks = 1, duration = 3, potency = 0.15 })
			table.insert(effects, { kind = "ApplyStatus", target = "AllAllies", status = "AppleGuard",
				stacks = 1, duration = 3, potency = 0.15 })
		end
		return effects
	elseif kind == "Smarter" then
		local ownHP, enemyHP = context.encounterHP, context.enemyEncounterHP
		if ownHP == nil or enemyHP == nil then return {} end
		if ownHP < enemyHP then
			return { { kind = "ApplyStatus", target = "Self", status = "DmgUp", stacks = 1, duration = 0, potency = 0.30 } }
		elseif ownHP > enemyHP then
			return { { kind = "GainMaxHP", target = "Self", potency = 0.30 } }
		end
	end
	return {}
end

-- Capture both HP values before either ability changes them. Waiting until both
-- fighters exist handles either play order, including Rival entering first.
function CardAbilityRules.encounter(first, second, fire)
	if not first or not second or not first.alive or not second.alive
		or first.hp <= 0 or second.hp <= 0 then return end
	local firstHP, secondHP = first.hp, second.hp
	for _, pair in ipairs({ { first, firstHP, secondHP }, { second, secondHP, firstHP } }) do
		local card = pair[1]
		if not card.firstEnemyEncountered then
			card.firstEnemyEncountered = true
			fire(card, { encounterHP = pair[2], enemyEncounterHP = pair[3] })
		end
	end
end

return CardAbilityRules