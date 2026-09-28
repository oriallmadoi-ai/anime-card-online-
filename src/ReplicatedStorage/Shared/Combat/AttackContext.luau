--!strict
-- Battle-local action identity. A volley is one attack with independent damage hits.
local AttackContext = {}

function AttackContext.new(battle, attacker, target, pattern, rng)
	battle.attackSequence = (battle.attackSequence or 0) + 1
	attacker.attackActions = (attacker.attackActions or 0) + 1
	local count, potency = 1, 1
	if pattern then
		if pattern.minHits then
			count = rng:NextInteger(pattern.minHits, pattern.maxHits)
			potency = pattern.potency
		elseif pattern.doubleEvery and attacker.attackActions % pattern.doubleEvery == 0 then
			count = 2
		end
	end
	return { id = battle.attackSequence, attacker = attacker, target = target,
		hitCount = count, potency = potency, damageDealt = 0, hitsResolved = 0,
		reflections = {}, finished = false }
end

function AttackContext.hit(attack, index, modifiedDamage, crit)
	return { attack = attack, index = index, potency = attack.potency,
		rawDamage = modifiedDamage * attack.potency, crit = crit }
end

-- Split PRE-mitigation damage, never rebuild it from a card's DMG stat.
function AttackContext.amount(hit, share)
	return hit.rawDamage * share
end

function AttackContext.livingAllies(attacker, cards)
	local out = {}
	for _, card in ipairs(cards) do
		if card ~= attacker and card.alive and card.hp > 0 then table.insert(out, card) end
	end
	return out
end

return AttackContext

