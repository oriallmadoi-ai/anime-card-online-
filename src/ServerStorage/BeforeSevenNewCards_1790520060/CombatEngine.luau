--!strict
-- Deterministic turn-based auto-battle. QUEUE model: one fighter active per
-- side, the next steps forward when the active one falls.
--
-- ARCHITECTURE
-- The whole battle is simulated on the server in one pass, producing a log of
-- events plus a result. The client replays that log. Three consequences:
--   1. Cheating is impossible - the client animates an already-decided fight.
--   2. Battle speed (1x/2x/8x) and "hide battle" are free: play the log faster,
--      or not at all. Nothing can desync because nothing is simulated twice.
--   3. Balance is testable at thousands of battles per second, offline.
--
-- Determinism needs the RNG consumed in a fixed order, so never iterate
-- combatants with pairs() during a fight - always ipairs over an ordered array.
--
-- SUPPORTS are paired by slot: Support 1 assists Attack 1. A support never
-- takes the field and cannot be targeted; its clauses fire on its partner's
-- triggers, which is why they are simply appended to that card's passive list.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CardDefinitions = require(ReplicatedStorage.Shared.Config.CardDefinitions)
local SupportDefinitions = require(ReplicatedStorage.Shared.Config.SupportDefinitions)
local EnemyDefinitions = require(ReplicatedStorage.Shared.Config.EnemyDefinitions)
local PassiveDefinitions = require(ReplicatedStorage.Shared.Config.PassiveDefinitions)
local StatusEffects = require(ReplicatedStorage.Shared.Config.StatusEffects)
local ChallengeModifiers = require(ReplicatedStorage.Shared.Config.ChallengeModifiers)
local CardStats = require(ReplicatedStorage.Shared.Util.CardStats)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local AttackContext = require(ReplicatedStorage.Shared.Combat.AttackContext)
local CardAbilityRules = require(ReplicatedStorage.Shared.Combat.CardAbilityRules)

local CombatEngine = {}

-- ── construction ───────────────────────────────────────────

local function newCombatant(def, level, variant, team, slot, stats, supportPassives)
	return {
		defId = def.id, name = def.name, team = team, slot = slot,
		variant = variant, level = level, tags = def.tags or {},
		passives = def.passive and { def.passive } or (def.passives or {}),
		supportPassives = supportPassives or {},

		maxHP = stats.hp, hp = stats.hp, dmg = stats.dmg,
		-- DMG as it entered the fight. `dmg` drifts as abilities add to it, so
		-- anything whose text says "base damage" reads this instead. baseMaxHP is
		-- the same idea for the HP ceiling, which GainMaxHP moves.
		baseDmg = stats.dmg, baseMaxHP = stats.hp,
		alive = true, entered = false,
		-- Stamped by ensureEntered. 1 = the first of its side to take the field.
		playIndex = nil,
		-- Turns this card has personally taken, counted at the top of its own turn.
		-- What SurvivedTurns reads: "has been on the field for N turns" has to mean
		-- turns THIS card acted through, not global rounds, or a card brought out
		-- late would inherit credit for the whole fight.
		turnsAlive = 0,
		-- Running total of stats taken off defeated enemies by `absorbs` effects.
		-- Damage with basis "Absorbed" spends it.
		absorbed = 0,
		statuses = {}, clauseState = {},
		extraAttackBonus = 0, bypassReduction = 0,
	}
end

-- ── status helpers ─────────────────────────────────────────

local function statusTotal(c, id: string, field: string): number
	local s = c.statuses[id]
	if not s then return 0 end
	return (s[field] or 0) * (s.stacks or 1)
end

local function applyStatus(ctx, target, statusId, stacks, duration, potency, sourceDmg)
	local def = StatusEffects.get(statusId)
	if not def then return end
	if ctx.disabledCategories[def.category] and target.team == "player" then return end

	local existing = target.statuses[statusId]
	if existing and def.stacking == "Stack" then
		existing.stacks = math.min(def.maxStacks or 99, existing.stacks + (stacks or 1))
		existing.duration = math.max(existing.duration, duration or existing.duration)
		existing.potency = math.max(existing.potency or 0, potency or 0)
		existing.sourceDmg = math.max(existing.sourceDmg or 0, sourceDmg or 0)
	elseif existing and def.stacking == "Unique" then
		return
	else
		target.statuses[statusId] = {
			stacks = math.min(def.maxStacks or 99, stacks or 1),
			duration = duration or 1, potency = potency or 0, sourceDmg = sourceDmg or 0,
		}
	end
	ctx.log[#ctx.log + 1] = { t = "status", team = target.team, slot = target.slot, status = statusId }
end

local function consumeDisabledTurn(c): boolean
	for statusId, s in pairs(c.statuses) do
		local def = StatusEffects.get(statusId)
		if def and def.skipsTurn and (s.duration or 0) > 0 then
			s.duration -= 1
			if s.duration <= 0 then c.statuses[statusId] = nil end
			return true
		end
	end
	return false
end

-- ── queue ──────────────────────────────────────────────────

local function activeOf(ctx, team)
	for _, c in ipairs(ctx.queue[team]) do
		if c.alive then return c end
	end
	return nil
end

local function teamAlive(ctx, team): boolean
	return activeOf(ctx, team) ~= nil
end

-- ── damage ─────────────────────────────────────────────────

local function damageMultiplier(ctx, c): number
	local mult = 1 + statusTotal(c, "DmgUp", "potency")
	if ctx.maxStatMultiplier and c.team == "player" then
		mult = math.min(mult, ctx.maxStatMultiplier)
	end
	return mult
end

local fireTrigger
local checkDeath

local function dealDamage(ctx, source, target, amount, tag, hit)
	if not target or not target.alive then return 0 end

	local reduction = math.min(GameConfig.MaxDamageReduction, statusTotal(target, "DmgReduction", "potency")
		+ statusTotal(target, "AppleGuard", "potency"))
	reduction = math.max(0, reduction - (source and source.bypassReduction or 0))
	amount *= (1 - reduction)
	-- Keep low-stat percentage attacks meaningful instead of flooring them to 0.
	amount = amount > 0 and math.max(1, math.floor(amount)) or 0

	local shield = target.statuses.Shield
	if shield then
		local pool = shield.potency * target.maxHP * shield.stacks
		if pool >= amount then
			shield.potency -= amount / (target.maxHP * shield.stacks)
			ctx.log[#ctx.log + 1] = { t = "shield", team = target.team, slot = target.slot, amount = math.floor(amount) }
			return 0
		end
		amount -= pool
		target.statuses.Shield = nil
	end

	amount = amount > 0 and math.max(1, math.floor(amount)) or 0
	target.hp -= amount
	ctx.log[#ctx.log + 1] = {
		t = "damage", team = target.team, slot = target.slot,
		srcTeam = source and source.team, srcSlot = source and source.slot,
		amount = amount, tag = tag, hp = math.max(0, target.hp),
		attackId = hit and hit.attack.id, hitIndex = hit and hit.index,
		hitCount = hit and hit.attack.hitCount, potency = hit and hit.potency,
	}
	if amount > 0 then
		fireTrigger(ctx, target, "OnHealthChanged", {})
		fireTrigger(ctx, target, "OnHitTaken", { damageTaken = amount, tag = tag, hit = hit, attack = hit and hit.attack })
	end
	return amount
end

-- ── effects ────────────────────────────────────────────────

local function resolveTargets(ctx, source, spec)
	local enemyTeam = source.team == "player" and "enemy" or "player"
	if spec == "Self" or spec == "PairedCard" then return { source } end
	if spec == "AllAllies" then
		-- Everyone still standing on the source's own side, source excluded. On
		-- an OnDeath clause the source's alive flag is already false by the time
		-- this runs, so "living" is honest without a special case.
		local out = {}
		for _, other in ipairs(ctx.queue[source.team]) do
			if other.alive and other ~= source then out[#out + 1] = other end
		end
		return out
	end
	if spec == "ActiveEnemy" or spec == "LastHit" then
		local a = activeOf(ctx, enemyTeam)
		return a and { a } or {}
	end
	if spec == "ActiveAndNextEnemy" then
		local out = {}
		for _, c in ipairs(ctx.queue[enemyTeam]) do
			if c.alive then table.insert(out, c); if #out == 2 then break end end
		end
		return out
	end
	if spec == "NextEnemy" then
		-- The second living enemy in the queue: the one waiting behind whoever
		-- is currently fighting. Empty if nobody is queued up.
		local seen = 0
		for _, c in ipairs(ctx.queue[enemyTeam]) do
			if c.alive then
				seen += 1
				if seen == 2 then return { c } end
			end
		end
		return {}
	end
	if spec == "AllEnemies" then
		-- The whole opposing party still standing, active fighter included. This is
		-- what "the enemy party" means on a card face.
		--
		-- Active first, then the queue behind it, mirroring BattleRuntime: the
		-- order this list comes back in is the order an AoE resolves in, and the
		-- interactive runtime paces a beat between each target so the player sees
		-- it sweep down the line.
		local out = {}
		local active = activeOf(ctx, enemyTeam)
		if active and active.alive then out[#out + 1] = active end
		for _, c in ipairs(ctx.queue[enemyTeam]) do
			if c.alive and c ~= active then out[#out + 1] = c end
		end
		return out
	end
	if spec == "Victim" then
		-- The card that just died, during the OnKill it caused.
		--
		-- It cannot be reached any other way: by the time OnKill fires the victim is
		-- already dead, so ActiveEnemy and LastHit have both moved on to whoever
		-- stepped into its place. ctx.victim is set for exactly the length of that
		-- one trigger and cleared straight after.
		return ctx.victim and { ctx.victim } or {}
	end
	-- "Ally:<defId>" names ONE specific card in the source's own queue, whether it
	-- is fighting, waiting, or already defeated. Deck MEMBERSHIP is what an
	-- ability worded "if X is in your active deck" reads, so no alive filter.
	local allyId = string.match(spec, "^Ally:(.+)$")
	if allyId then
		for _, other in ipairs(ctx.queue[source.team]) do
			if other ~= source and other.defId == allyId then return { other } end
		end
		return {}
	end
	return { source }
end

-- How many times a `scaleBy` effect multiplies its potency. Mirror of the
-- BattleRuntime helper.
--
-- 1 when the effect does not scale, so callers can multiply unconditionally.
-- 0 when it scales off a count that came up empty, and every caller treats 0 as
-- "do nothing" rather than applying a zero-strength buff.
local function scaleCount(ctx, source, effect): number
	local scaleBy = effect.scaleBy
	if not scaleBy then return 1 end

	local queue = ctx.queue[source.team] or {}

	if scaleBy == "DefeatedAllies" then
		local n = 0
		for _, other in ipairs(queue) do
			if other ~= source and not other.alive then n += 1 end
		end
		return n
	end

	-- Counts by NAME rather than id: the group this gathers is the one a player
	-- recognises off the card face. Counts the source itself when its own name
	-- matches, which is what "per card with 'master' in their name" says.
	if scaleBy == "AlliesNamed" then
		local needle = string.lower(effect.nameContains or "")
		if needle == "" then return 0 end
		local n = 0
		for _, other in ipairs(queue) do
			if string.find(string.lower(other.name or ""), needle, 1, true) then n += 1 end
		end
		return n
	end

	return 1
end

local function runEffect(ctx, source, effect, context)
	local kind = effect.kind
	local function effectTargets(spec)
		if context.attack and context.attack.attacker == source
			and (spec == "ActiveEnemy" or spec == "LastHit") then
			local target = context.attack.target
			return target.alive and { target } or {}
		end
		return resolveTargets(ctx, source, spec)
	end

	if ctx.disabledEffects[kind] and source.team == "player" then return end
	if CardAbilityRules.handles(kind) then
		for _, inner in ipairs(CardAbilityRules.expand(kind, source, effectTargets("ActiveEnemy")[1], ctx, context)) do
			runEffect(ctx, source, inner, context)
		end
		return
	end

	if kind == "Damage" then
		if context.attack and context.attacker and effect.from == "LastHit" then
			for _, target in ipairs(effectTargets(effect.target or "ActiveEnemy")) do
				table.insert(context.attack.reflections, { target = target, source = source,
					share = (effect.potency or 1) * scaleCount(ctx, source, effect), tag = effect.tag or "passive" })
			end
			return
		end

		-- `from` re-bases the hit on ANOTHER card's DMG. A redirect needs it: what
		-- gets passed down the line is a share of what the ATTACKER swung for, not a
		-- share of what the redirecting card hits for.
		--
		-- `basis` instead re-bases it on something OTHER than a DMG stat:
		--   "MaxHP"     the source's own HP ceiling, for a card that detonates itself
		--   "Absorbed"  everything the source has taken off things it killed
		-- Neither is scaled by DmgUp: they are not swings, so a damage buff has
		-- nothing to act on.
		local basis = source.dmg * damageMultiplier(ctx, source)
		if effect.basis == "BaseDMG" then
			basis = source.baseDmg or source.dmg
		elseif effect.basis == "MaxHP" then
			basis = source.maxHP
		elseif effect.basis == "Absorbed" then
			-- Nothing absorbed means no explosion at all, rather than a floored
			-- one-point hit that reads as the ability having fired.
			if (source.absorbed or 0) <= 0 then return end
			basis = source.absorbed
		end
		if effect.from then
			local fromCard = effectTargets(effect.from)[1]
			if not fromCard then return end
			basis = fromCard.dmg
		end
		local scale = scaleCount(ctx, source, effect)
		if scale <= 0 then return end
		for _, t in ipairs(effectTargets(effect.target or "ActiveEnemy")) do
			local dealt = dealDamage(ctx, source, t,
				(effect.basis == "TargetMaxHP" and t.maxHP or basis) * (effect.potency or 1) * scale, effect.tag or "passive")
			context.damageDealt = (context.damageDealt or 0) + dealt
			if effect.resolveImmediately then checkDeath(ctx, t) end
		end

	elseif kind == "RestoreHP" then
		source.hp = math.max(1, math.floor(source.maxHP * (effect.hpPercent or 0.30)))
		ctx.log[#ctx.log + 1] = { t = "heal", team = source.team, slot = source.slot, amount = source.hp }
	elseif kind == "RemoveStatus" then
		for _, t in ipairs(effectTargets(effect.target or "Self")) do t.statuses[effect.status] = nil end
	elseif kind == "Heal" then
		for _, t in ipairs(effectTargets(effect.target or "Self")) do
			local amount
			if effect.scalesWith == "DamageDealt" then
				amount = (context.damageDealt or 0) * (effect.potency or 0)
			elseif effect.scalesWith == "DamageTaken" then
				-- Set by the OnDamage trigger: leech back a share of the hit just
				-- taken, rather than a share of max HP.
				amount = (context.damageTaken or 0) * (effect.potency or 0)
			else
				amount = t.maxHP * (effect.potency or 0)
			end
			local requested = amount > 0 and math.max(1, math.floor(amount)) or 0
			local beforeHP = t.hp
			t.hp = math.min(t.maxHP, t.hp + requested)
			local healed = math.max(0, t.hp - beforeHP)
			ctx.log[#ctx.log + 1] = { t = "heal", team = t.team, slot = t.slot, amount = healed }
		end

	elseif kind == "ApplyStatus" then
		-- What the status scales from. By default it is the hit that applied it,
		-- which is right for "bleeds for a share of the wound". A card whose text
		-- promises a share of its own DMG sets useSourceDmg, because otherwise a
		-- crit would make the effect larger than the card says it is.
		local basis = effect.useSourceDmg and source.dmg or (context.damageDealt or source.dmg)
		local scale = scaleCount(ctx, source, effect)
		if scale <= 0 then return end
		local targets = effectTargets(effect.target or "ActiveEnemy")
		if effect.target == "Attacker" then
			targets = context.attacker and { context.attacker } or {}
		end
		for _, t in ipairs(targets) do
			-- namedPotency lets ONE clause buff two grades of ally at different
			-- strengths ("10%, or 20% if the ally is a master"). Two clauses would roll
			-- the trigger's chance twice and could grant both buffs, or neither.
			local potency = effect.potency or 0
			if effect.namedPotency and effect.nameContains
				and string.find(string.lower(t.name or ""), string.lower(effect.nameContains), 1, true) then
				potency = effect.namedPotency
			end
			applyStatus(ctx, t, effect.status, effect.stacks or 1, effect.duration or 1,
				potency * scale, basis)
			if effect.status == "Daze" and t.statuses.Daze then t.statuses.Daze.source = source end
		end

	elseif kind == "Revive" then
		for _, t in ipairs(effectTargets(effect.target or "Self")) do
			t.alive = true
			t.hp = math.floor(t.maxHP * (effect.hpPercent or 0.5))
			t.statuses = {}
			ctx.log[#ctx.log + 1] = { t = "revive", team = t.team, slot = t.slot, hp = t.hp }
		end

	elseif kind == "ExtraAttack" then
		source.extraAttackBonus += (effect.chanceBonus or 1)

	elseif kind == "GainMaxHP" then
		-- Mirror of the BattleRuntime effect. Grants the gain as current HP too, or
		-- the card just receives a bigger empty bar.
		--
		-- `from` reads the ceiling off a DIFFERENT card ("gain 50% of that card's
		-- HP"), and reads its baseMaxHP so the gift is a share of what that card
		-- printed rather than of whatever it has since grown to.
		local hpScale = scaleCount(ctx, source, effect)
		local basisCard = effect.from and effectTargets(effect.from)[1] or nil
		if hpScale <= 0 or (effect.from and not basisCard) then return end
		local hpBasis = basisCard and (basisCard.baseMaxHP or basisCard.maxHP) or nil
		for _, t in ipairs(effectTargets(effect.target or "Self")) do
			if t.alive then
				local gain = math.max(1, math.floor((hpBasis or t.maxHP) * (effect.potency or 0) * hpScale))
				t.maxHP += gain
				t.hp = math.min(t.maxHP, t.hp + gain)
				-- `absorbs` banks the gain so a later Damage with basis "Absorbed"
				-- can spend it. Banked on the SOURCE, not the target: it is the
				-- card that ate the stat that later detonates.
				if effect.absorbs then source.absorbed = (source.absorbed or 0) + gain end
				ctx.log[#ctx.log + 1] = { t = "heal", team = t.team, slot = t.slot, amount = gain }
			end
		end

	elseif kind == "SummonClone" then
		-- Mirror of the BattleRuntime effect. The clone carries NO passives, or a
		-- card that clones on death would spawn copies forever.
		local queue = ctx.queue[source.team]
		if queue then
			local scale = effect.statScale or 0.5
			local maxSlot = 0
			for _, c in ipairs(queue) do
				if (c.slot or 0) > maxSlot then maxSlot = c.slot end
			end
			local hp = math.max(1, math.floor(source.maxHP * scale))
			local dmg = math.max(1, math.floor((source.baseDmg or source.dmg) * scale))
			table.insert(queue, {
				defId = source.defId,
				name = source.name .. " (Clone)",
				team = source.team,
				slot = maxSlot + 1,
				variant = source.variant,
				level = source.level,
				tags = {},
				passives = {},
				supportPassives = {},
				maxHP = hp, hp = hp, dmg = dmg, baseDmg = dmg, baseMaxHP = hp,
				alive = true, entered = false,
				statuses = {}, clauseState = {},
				extraAttackBonus = 0, bypassReduction = 0,
			})
		end

	elseif kind == "GainDamage" then
		-- Mirror of the BattleRuntime effect, so a passive behaves the same in the
		-- simulated engine as it does in an interactive battle.
		-- `scaleBy` multiplies the gain by a count ("per defeated ally"). Zero means
		-- nothing to scale off, and must grant nothing at all rather than the
		-- one-point floor the math.max below would otherwise hand out.
		local gainScale = scaleCount(ctx, source, effect)
		if gainScale <= 0 then return end
		for _, from in ipairs(effectTargets(effect.from or "LastHit")) do
			local basis = from.baseDmg or from.dmg
			local gain = math.max(1, math.floor(basis * (effect.potency or 0) * gainScale))
			source.dmg += gain
			if effect.absorbs then source.absorbed = (source.absorbed or 0) + gain end
			ctx.log[#ctx.log + 1] = {
				t = "gainDamage", team = source.team, slot = source.slot, amount = gain,
			}
		end

	elseif kind == "RandomChoice" then
		-- Picks exactly ONE branch, so "either X or Y" can never fire both or
		-- neither. One effect rather than two clauses because the clause's `limit`
		-- must be SHARED: "up to 4 times" means four activations, not four of each.
		local options = effect.options or {}
		local total = 0
		for _, option in ipairs(options) do total += (option.weight or 1) end
		if total > 0 then
			local pick = ctx.rng:NextNumber() * total
			local acc = 0
			for _, option in ipairs(options) do
				acc += (option.weight or 1)
				if pick <= acc then
					for _, inner in ipairs(option.effects or {}) do
						runEffect(ctx, source, inner, context)
					end
					break
				end
			end
		end

	elseif kind == "CancelAttack" then
		context.cancelled = true
	end
end

-- Clause conditions.
--
-- A clause with no condition always rolls. One with a condition is skipped
-- outright when it does not hold - the chance is not even rolled, so a
-- conditional clause never burns its `limit` or accumulates `chanceOnFail` on a
-- turn where it could not have applied.
--
-- Kept as a NAMED REGISTRY rather than functions written into the passive data,
-- because PassiveDefinitions has to stay pure data: readable at a glance,
-- diffable, and safe to serialise. A condition is a rule the engine knows, not
-- code a card carries.
local CONDITIONS = {
	CanDazeAttacker = function(ctx, c, _, context)
		local attacker = context and context.attacker
		if not attacker or not attacker.alive or attacker.hp <= 0 or not c.alive or c.hp <= 0
			or context.cancelled then return false end
		if (ctx.disabledEffects.ApplyStatus and c.team == "player")
			or (ctx.disabledCategories.Control and attacker.team == "player") then return false end
		return #AttackContext.livingAllies(attacker, ctx.queue[attacker.team]) > 0
	end,

	HPAtMost = function(_, c, arg)
		return c.maxHP > 0 and c.hp / c.maxHP <= (tonumber(arg) or 0)
	end,
	-- "while the card is under half health". Pair with limit = 1 for a one-shot
	-- desperation ability, or it re-fires on every hit taken.
	BelowHalfHP = function(_, c)
		return c.maxHP > 0 and (c.hp / c.maxHP) < 0.5
	end,

	-- "while this card has more DMG than the card it is facing"
	StrongerThanTarget = function(ctx, c)
		local enemy = activeOf(ctx, c.team == "player" and "enemy" or "player")
		return enemy ~= nil and c.dmg > enemy.dmg
	end,

	-- "while a damage buff is up" - lets a reward clause fire only during the
	-- window some earlier clause opened, instead of for the rest of the fight.
	HasDmgUp = function(_, c)
		return statusTotal(c, "DmgUp", "potency") > 0
	end,

	-- "this card was the FIRST one its side put on the field". Stamped once in
	-- ensureEntered and never revised, so an OnDeath clause gated on it still
	-- knows how the card arrived many turns earlier.
	PlayedFirst = function(_, c)
		return c.playIndex == 1
	end,

	-- "this card is the LAST one its side had to play": nobody else of theirs is
	-- still waiting to enter. Defeated cards do not count as waiting.
	PlayedLast = function(ctx, c)
		for _, other in ipairs(ctx.queue[c.team]) do
			if other ~= c and other.alive and not other.entered then return false end
		end
		return true
	end,

	-- "Master of Both is somewhere in this card's party", alive or not: Last Hope
	-- reads deck membership, not survival, so a fallen partner still counts.
	HasMasterOfBoth = function(ctx, c)
		for _, other in ipairs(ctx.queue[c.team]) do
			if other ~= c and other.defId == "MasterOfBoth" then return true end
		end
		return false
	end,

	HasNextEnemy = function(ctx, c)
		local enemyTeam = c.team == "player" and "enemy" or "player"
		local seenActive = false
		for _, other in ipairs(ctx.queue[enemyTeam]) do
			if other.alive then
				if seenActive then return true end
				seenActive = true
			end
		end
		return false
	end,

	-- ── parameterised conditions ───────────────────────────
	-- These take the text after the colon in the clause's condition string, so one
	-- entry serves every card instead of a hardcoded predicate per ability.
	-- HasMasterOfBoth above is the old hardcoded shape, kept because saved passives
	-- still name it.

	-- "HasAlly:SonWarrior" - that card is somewhere in this card's party, alive or
	-- not. Deck MEMBERSHIP, matching how HasMasterOfBoth already reads.
	HasAlly = function(ctx, c, arg)
		if not arg then return false end
		for _, other in ipairs(ctx.queue[c.team]) do
			if other ~= c and other.defId == arg then return true end
		end
		return false
	end,

	-- "HasStatus:Charging" - used with the ! prefix far more often than without,
	-- to gate a payout on a wind-up having finished.
	HasStatus = function(_, c, arg)
		return arg ~= nil and c.statuses[arg] ~= nil
	end,

	-- "HasStacks:Money:3" - at least N stacks of a status.
	HasStacks = function(_, c, arg)
		if not arg then return false end
		local id, n = string.match(arg, "^(.-):(%d+)$")
		if not id then return false end
		local s = c.statuses[id]
		return s ~= nil and (s.stacks or 0) >= tonumber(n)
	end,

	-- "SurvivedTurns:2" - this card has taken at least N turns of its own.
	SurvivedTurns = function(_, c, arg)
		return arg ~= nil and (c.turnsAlive or 0) >= (tonumber(arg) or 0)
	end,
}

-- Resolves a clause's `condition` string, which may be:
--   "Name"            a plain predicate
--   "Name:arg"        a parameterised one
--   "!Name" / "!N:a"  the negation of either
--
-- An UNKNOWN condition blocks the clause, negated or not. That is deliberate:
-- a typo should make an ability silently do nothing rather than fire
-- unconditionally, which is the failure mode that is hard to notice.
local function conditionHolds(ctx, c, spec, context): boolean
	if not spec then return true end

	local negate = false
	if string.sub(spec, 1, 1) == "!" then
		negate = true
		spec = string.sub(spec, 2)
	end

	local name, arg = string.match(spec, "^([^:]+):(.+)$")
	name = name or spec

	local fn = CONDITIONS[name]
	if not fn then return false end

	local held = fn(ctx, c, arg, context) and true or false
	if negate then return not held end
	return held
end

-- A clause may carry `condition` (one spec) and/or `conditions` (a list). ALL of
-- them must hold. The list exists because a single string cannot express an AND,
-- and "only on its second turn AND only with that ally present" is two
-- independent facts about two different things - splitting it across two clauses
-- instead would roll the trigger's chance twice and let half the ability fire.
local function clauseGateOpen(ctx, c, clause, context): boolean
	if not conditionHolds(ctx, c, clause.condition, context) then return false end
	for _, spec in ipairs(clause.conditions or {}) do
		if not conditionHolds(ctx, c, spec, context) then return false end
	end
	return true
end

fireTrigger = function(ctx, c, trigger, context)
	if not c then return context or {} end
	if not c.alive and trigger ~= "OnDeath" then return context or {} end
	context = context or {}

	-- The card's own passives, then whatever its paired support contributes.
	for _, list in ipairs({ c.passives, c.supportPassives }) do
		for _, passiveId in ipairs(list) do
			local passive = PassiveDefinitions.get(passiveId)
			if passive then
				for i, clause in ipairs(passive.clauses or {}) do
					local blocked = not clauseGateOpen(ctx, c, clause, context)
					if clause.trigger == trigger and not blocked then
						local key = passiveId .. ":" .. i
						local state = c.clauseState[key]
						if not state then state = { uses = 0, bonus = 0, ticks = 0 }; c.clauseState[key] = state end

						-- `oncePerAttack` collapses a per-HIT trigger down to per-ATTACK.
						-- Mirrors BattleRuntime exactly: this simulator drives the victory
						-- chance the player is shown, so a rule it does not know about makes
						-- the prediction disagree with the fight.
						if clause.oncePerAttack then
							local attackId = context.attack and context.attack.id
							if attackId and state.lastAttackId == attackId then
								blocked = true
							else
								state.lastAttackId = attackId
							end
						end

						if not blocked and ((not clause.limit) or (state.uses < clause.limit)) then
							-- `everyNth` counts how many times the trigger has reached
							-- this clause and only lets every Nth one through. Counted
							-- AFTER the condition gate and the limit, so a turn the clause
							-- could not have fired on does not consume a beat and shift the
							-- rhythm - "every second attack" has to stay on the attacks that
							-- actually happened.
							local onBeat = true
							if clause.everyNth then
								state.ticks = (state.ticks or 0) + 1
								onBeat = (state.ticks % clause.everyNth) == 0
							end

							if onBeat then
								local chance = math.clamp((clause.chance or 1) + state.bonus, 0, 1)
								-- A decayed chance that has run to zero must not roll at all:
								-- NextNumber can return exactly 0 and `0 <= 0` would let a
								-- spent ability fire once more.
								if chance > 0 and ctx.rng:NextNumber() <= chance then
									state.uses += 1
									-- chanceOnHit is the mirror of chanceOnFail: added to the
									-- clause's chance every time it DOES land, so a negative
									-- value is an ability that wears itself out.
									if clause.chanceOnHit then state.bonus = math.max(-(clause.chance or 1), state.bonus + clause.chanceOnHit) end
									ctx.log[#ctx.log + 1] = { t = "passive", team = c.team, slot = c.slot, passive = passiveId, trigger = trigger,
										chance = chance, nextChance = math.clamp((clause.chance or 1) + state.bonus, 0, 1) }
									for _, effect in ipairs(clause.effects or {}) do
										runEffect(ctx, c, effect, context)
									end
								elseif clause.chanceOnFail then
									state.bonus += clause.chanceOnFail
								end
							end
						end
					end
				end
			end
		end
	end
	return context
end

-- ── death / entry ──────────────────────────────────────────

local ensureEntered
local resolveEntries

checkDeath = function(ctx, c)
	if not c or c.hp > 0 or not c.alive then return end
	fireTrigger(ctx, c, "OnFatalHit", {})
	if c.hp > 0 then return end
	c.hp = 0
	c.alive = false
	ctx.log[#ctx.log + 1] = { t = "death", team = c.team, slot = c.slot }
	fireTrigger(ctx, c, "OnDeath", {})   -- may revive; alive flips back if so
	if not c.alive then
		-- Whoever steps into the gap enters immediately.
		resolveEntries(ctx)
	end
end

-- Both sides' active fighters must have entered before anything else happens.
-- Safe against recursion because `entered` is set before the trigger fires.
function resolveEntries(ctx)
	for _, team in ipairs({ "player", "enemy" }) do
		ensureEntered(ctx, activeOf(ctx, team))
	end
	CardAbilityRules.encounter(activeOf(ctx, "player"), activeOf(ctx, "enemy"), function(fighter, encounterContext)
		fireTrigger(ctx, fighter, "OnEncounter", encounterContext)
	end)
end

-- Fires OnEntry the first time a card becomes active, which is what makes the
-- queue meaningful: entry abilities land as each fighter steps forward.
function ensureEntered(ctx, c)
	if c and c.alive and not c.entered then
		c.entered = true
		-- Entry order is this engine's equivalent of "played first / played last":
		-- there is no player choosing, so the queue order IS the play order.
		ctx.playCount[c.team] += 1
		c.playIndex = ctx.playCount[c.team]
		ctx.log[#ctx.log + 1] = { t = "enter", team = c.team, slot = c.slot, name = c.name }
		fireTrigger(ctx, c, "OnEntry", {})
	end
end

-- ── turn ───────────────────────────────────────────────────

local function redirectDazedAttack(ctx, c, cancelled)
	local state = c.statuses.Daze
	if not state then return nil end
	c.statuses.Daze = nil
	if cancelled or (state.duration or 0) <= 0 then return nil end
	local captain = state.source
	local allies = AttackContext.livingAllies(c, ctx.queue[c.team])
	if not captain or not captain.alive or #allies == 0 then return nil end
	return { { target = allies[ctx.rng:NextInteger(1, #allies)], share = 0.80, source = c, tag = "daze" },
		{ target = captain, share = 0.20, source = c, tag = "daze" } }
end

local function takeTurn(ctx, c)
	if not c or not c.alive then return end

	-- Entry resolves here rather than at the top of the round. A fighter that
	-- steps forward mid-turn (because the one in front of it just died) would
	-- otherwise attack before its entry ability fired, landing every "upon
	-- entry" effect a full turn late.
	ensureEntered(ctx, c)
	if not c.alive then return end

	-- Counted before OnTurnStart, so a clause gated on SurvivedTurns:1 can fire on
	-- this card's very first turn and the numbers read the way a player counts.
	c.turnsAlive = (c.turnsAlive or 0) + 1

	fireTrigger(ctx, c, "OnTurnStart", {})
	if consumeDisabledTurn(c) then
		ctx.log[#ctx.log + 1] = { t = "skip", team = c.team, slot = c.slot }
		return
	end

	local attacks = 1
	if c.extraAttackBonus > 0 and ctx.rng:NextNumber() <= c.extraAttackBonus then attacks = 2 end

	for attackIndex = 1, attacks do
		if not c.alive then break end
		local target = activeOf(ctx, c.team == "player" and "enemy" or "player")
		if not target or not target.alive then break end
		local attack = AttackContext.new(ctx, c, target,
			PassiveDefinitions.attackPattern(c.passives), ctx.rng)
		ctx.log[#ctx.log + 1] = { t = "attack", team = c.team, slot = c.slot, attackId = attack.id, hitCount = attack.hitCount }
		local defence = fireTrigger(ctx, target, "OnAttacked", { attacker = c, attack = attack })
		local routes = redirectDazedAttack(ctx, c, defence.cancelled)
		local dodgeChance = statusTotal(target, "Dodge", "potency")
		local dodged = not defence.cancelled and not routes and dodgeChance > 0
			and ctx.rng:NextNumber() <= dodgeChance
		local cancelled = defence.cancelled or dodged
		if cancelled then
			ctx.log[#ctx.log + 1] = { t = "cancel", team = target.team, slot = target.slot, dodged = dodged or nil }
		end
		if not routes then
			routes = cancelled and {} or { { target = target, source = c, share = 1 } }
		end
		for _, route in ipairs(attack.reflections) do table.insert(routes, route) end
		local function finishAttack()
			if attack.finished then return end
			attack.finished = true
			-- Preserve unblocked-attack semantics; redirected volleys are attacks too.
			if not cancelled and attack.hitsResolved > 0 then
				fireTrigger(ctx, c, "OnAttack", { damageDealt = attack.damageDealt, attack = attack })
			end
			-- One resolved attack, including a block/dodge; multi-hit attacks count once.
			fireTrigger(ctx, c, "OnAttackResolved", { damageDealt = attack.damageDealt, attack = attack })
		end
		for hitIndex = 1, attack.hitCount do
			if #routes == 0 or not c.alive or not target.alive or activeOf(ctx, c.team == "player" and "enemy" or "player") ~= target then break end
			local crit = ctx.rng:NextNumber() <= (GameConfig.BaseCritChance + statusTotal(c, "CritUp", "potency"))
			local hit = AttackContext.hit(attack, hitIndex,
				c.dmg * damageMultiplier(ctx, c) * (crit and GameConfig.CritMultiplier or 1), crit)
			attack.hitsResolved += 1
			for _, route in ipairs(routes) do
				local victim = route.target
				if not victim.alive then continue end
				local tag = route.tag or (crit and "crit" or "basic")
				local dealt = dealDamage(ctx, route.source, victim, AttackContext.amount(hit, route.share), tag, hit)
				attack.damageDealt += dealt
				if dealt > 0 then
					fireTrigger(ctx, victim, "OnDamage", { damageTaken = dealt, tag = tag, attack = attack, hit = hit })
				end
			end
			-- OnAttack precedes final-hit death as before. Earlier lethal hits resolve
			-- immediately (including death saves), so later bullets cannot hit a corpse.
			if hitIndex == attack.hitCount then finishAttack() end
			for _, route in ipairs(routes) do
				local victim = route.target
				local wasAlive = victim.alive
				checkDeath(ctx, victim)
				if wasAlive and not victim.alive and victim.team ~= c.team and not route.tag then
					ctx.victim = victim
					fireTrigger(ctx, c, "OnKill", { attack = attack, hit = hit })
					ctx.victim = nil
				end
			end
			checkDeath(ctx, c)
		end
		finishAttack()
		checkDeath(ctx, c)
	end
end

local function tickStatuses(ctx)
	for _, team in ipairs({ "player", "enemy" }) do
		for _, c in ipairs(ctx.queue[team]) do
			if c.alive then
				for statusId, s in pairs(c.statuses) do
					local def = StatusEffects.get(statusId)
					if def and def.tick == "TurnEnd" and s.potency > 0 and s.sourceDmg > 0 then
						local dot = math.max(1, math.floor(s.sourceDmg * s.potency * s.stacks))
						if dot > 0 then
							c.hp -= dot
							fireTrigger(ctx, c, "OnHealthChanged", {})
							ctx.log[#ctx.log + 1] = { t = "dot", team = c.team, slot = c.slot, status = statusId, amount = dot }
						end
					end
					if not def.skipsTurn and s.duration > 0 then
						s.duration -= 1
						if s.duration <= 0 then c.statuses[statusId] = nil end
					end
				end
				checkDeath(ctx, c)
			end
		end
	end
end

-- ── entry point ────────────────────────────────────────────

-- deck = { attack = {{cardId, variant, level}, ...}, support = {{cardId, variant, level}, ...} }
-- waves = { { {id = enemyId, level = n}, ... }, ... }
function CombatEngine.simulate(deck, waves, challengeIds, seed)
	local ctx = {
		rng = Random.new(seed or os.clock() * 1e6),
		log = {},
		queue = { player = {}, enemy = {} },
		-- How many of each side have taken the field, so PlayedFirst / PlayedLast
		-- have something to read. Reset for the enemy at the top of every wave.
		playCount = { player = 0, enemy = 0 },
		disabledCategories = {}, disabledEffects = {}, maxStatMultiplier = nil,
	}

	for _, id in ipairs(challengeIds or {}) do
		local mod = ChallengeModifiers.get(id)
		if mod then
			for _, cat in ipairs(mod.disablesCategories or {}) do ctx.disabledCategories[cat] = true end
			for _, eff in ipairs(mod.disablesEffects or {}) do ctx.disabledEffects[eff] = true end
			if mod.maxStatMultiplier then ctx.maxStatMultiplier = mod.maxStatMultiplier end
			ctx.log[#ctx.log + 1] = { t = "challenge", id = id }
		end
	end

	-- Build the player queue, attaching each slot's paired support.
	for slot = 1, GameConfig.AttackSlots do
		local entry = (deck.attack or {})[slot]
		if entry then
			local def = CardDefinitions.get(entry.cardId)
			if def then
				local supportPassives = {}
				local sEntry = (deck.support or {})[slot]
				if sEntry then
					local sDef = SupportDefinitions.get(sEntry.cardId)
					if sDef and sDef.passive then table.insert(supportPassives, sDef.passive) end
				end
				local stats = CardStats.compute(entry.cardId, entry.variant or "Standard", entry.level or 0)
				ctx.queue.player[#ctx.queue.player + 1] =
					newCombatant(def, entry.level or 0, entry.variant or "Standard", "player", slot, stats, supportPassives)
			end
		end
	end

	local result = { won = false, turns = 0, wavesCleared = 0 }

	for waveIndex, wave in ipairs(waves) do
		ctx.queue.enemy = {}
		ctx.playCount.enemy = 0
		for slot, spec in ipairs(wave) do
			local def = EnemyDefinitions.get(spec.id)
			if def then
				local mult = CardStats.levelMultiplier(spec.level or 1)
				ctx.queue.enemy[#ctx.queue.enemy + 1] = newCombatant(
					def, spec.level or 1, nil, "enemy", slot,
					{ dmg = math.floor(def.baseDMG * mult), hp = math.floor(def.baseHP * mult) })
			end
		end
		ctx.log[#ctx.log + 1] = { t = "wave", index = waveIndex }

		local turn = 0
		while turn < GameConfig.MaxBattleTurns do
			turn += 1
			result.turns += 1
			ctx.log[#ctx.log + 1] = { t = "turn", n = turn }

			-- Only the two active fighters act. Whoever steps forward this
			-- turn gets their entry ability first.
			resolveEntries(ctx)
			takeTurn(ctx, activeOf(ctx, "player"))
			takeTurn(ctx, activeOf(ctx, "enemy"))
			tickStatuses(ctx)

			if not teamAlive(ctx, "enemy") then
				result.wavesCleared += 1
				break
			end
			if not teamAlive(ctx, "player") then
				ctx.log[#ctx.log + 1] = { t = "end", won = false }
				result.log = ctx.log
				return result
			end
		end

		if teamAlive(ctx, "enemy") then
			ctx.log[#ctx.log + 1] = { t = "end", won = false, reason = "timeout" }
			result.log = ctx.log
			return result
		end
	end

	result.won = true
	ctx.log[#ctx.log + 1] = { t = "end", won = true }
	result.log = ctx.log
	return result
end

return CombatEngine



