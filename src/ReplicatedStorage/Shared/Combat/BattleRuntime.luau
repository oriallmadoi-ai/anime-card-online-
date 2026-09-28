--!strict
-- Interactive battle runtime.
--
-- IMPORTANT: this does NOT replace the existing CombatEngine. CombatEngine is
-- a one-pass deterministic auto-battle simulator. This runtime is additive and
-- exists because drag/drop battles must pause while a player chooses a card.
--
-- It deliberately reuses the game's existing sources of truth:
-- CardDefinitions, SupportDefinitions, CardStats, PassiveDefinitions,
-- StatusEffects and GameConfig. Existing ability DATA is therefore not copied.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardDefinitions = require(ReplicatedStorage.Shared.Config.CardDefinitions)
local SupportDefinitions = require(ReplicatedStorage.Shared.Config.SupportDefinitions)
local PassiveDefinitions = require(ReplicatedStorage.Shared.Config.PassiveDefinitions)
local StatusEffects = require(ReplicatedStorage.Shared.Config.StatusEffects)
local CardStats = require(ReplicatedStorage.Shared.Util.CardStats)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)

local AttackContext = require(ReplicatedStorage.Shared.Combat.AttackContext)
local CardAbilityRules = require(ReplicatedStorage.Shared.Combat.CardAbilityRules)
local TurnOrder = require(ReplicatedStorage.Shared.Combat.TurnOrder)

local BattleRuntime = {}

local function push(events, eventType: string, data)
	data = data or {}
	data.type = eventType
	table.insert(events, data)
end

local function sideOf(session, team: string)
	return team == "player" and session.player or session.enemy
end

local function enemyTeamOf(team: string): string
	return team == "player" and "enemy" or "player"
end

local function statusTotal(card, id: string, field: string): number
	local status = card.statuses[id]
	if not status then
		return 0
	end
	return (status[field] or 0) * (status.stacks or 1)
end

-- Defined up here, above the snapshot helpers, because both the combat maths and
-- the display path need it and a `local function` declared further down would
-- not be in scope for the ones above it.
local function damageMultiplier(card): number
	return 1 + statusTotal(card, "DmgUp", "potency")
end

-- The DMG number a card should SHOW on its face.
--
-- `card.dmg` is the stat the card owns, but a DmgUp buff is a MULTIPLIER applied
-- at the moment of the swing - so a card under a x2 buff was hitting for double
-- while its printed number never moved. Everything player-facing goes through
-- here.
--
-- Nothing that COMPUTES damage may use this: dealDamage applies the multiplier
-- itself, so feeding it a figure that already includes the buff would square it.
local function displayDmg(card): number
	return math.max(0, math.floor(card.dmg * damageMultiplier(card)))
end

-- Tells the client a card's numbers moved for a reason that is neither damage
-- nor healing: a buff landing or expiring, or a permanent stat steal. HP already
-- updates live off Damage and Heal events; without this the DMG figure only
-- caught up on the next full state snapshot, a whole round late.
local function pushStat(card, events)
	if not card or not events then
		return
	end
	push(events, "Stat", {
		side = card.team,
		slot = card.slot,
		dmg = displayDmg(card),
		hp = math.max(0, card.hp),
		maxHP = card.maxHP,
	})
end

local function isNegativeStatus(def): boolean
	if not def then
		return false
	end
	return def.category == "DoT" or def.category == "Debuff" or def.category == "Control"
end

local function snapshotStatus(card, id: string, state)
	local def = StatusEffects.get(id)
	return {
		id = id,
		effectType = id,
		displayName = (def and def.display) or id,
		description = (def and def.description) or "",
		category = (def and def.category) or "Effect",
		isDebuff = isNegativeStatus(def),
		stacks = state.stacks or 1,
		duration = state.duration or 0,
		initialDuration = state.initialDuration or state.duration or 0,
		potency = state.potency or 0,
		sourceDmg = state.sourceDmg or 0,
		sourceCard = state.sourceCard,
		sourceCardId = state.sourceCardId,
		sourceAbility = state.sourceAbility,
		sourceAbilityId = state.sourceAbilityId,
		sourceSide = state.sourceSide,
		appliedRound = state.appliedRound or 1,
		stacking = def and def.stacking or nil,
		maxStacks = def and def.maxStacks or nil,
		maxHP = card.maxHP,
		usesRemaining = def and def.maxUses and math.max(0, def.maxUses - (state.uses or 0)) or nil,
	}
end

local function statusList(card)
	local out = {}
	for id, state in pairs(card.statuses) do
		table.insert(out, snapshotStatus(card, id, state))
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

local function effectList(card)
	local out = statusList(card)
	for id, state in pairs(card.modifiers or {}) do
		table.insert(out, {
			id = id,
			effectType = id,
			displayName = state.displayName or id,
			description = state.description or "",
			category = state.category or "Buff",
			isDebuff = state.isDebuff == true,
			stacks = state.stacks or 1,
			duration = state.duration or 0,
			initialDuration = state.initialDuration or state.duration or 0,
			potency = state.potency or 0,
			value = state.value or 0,
			valueType = state.valueType,
			sourceCard = state.sourceCard,
			sourceCardId = state.sourceCardId,
			sourceAbility = state.sourceAbility,
			sourceAbilityId = state.sourceAbilityId,
			sourceSide = state.sourceSide,
			appliedRound = state.appliedRound or 1,
			maxHP = card.maxHP,
		})
	end
	table.sort(out, function(a, b)
		if a.isDebuff ~= b.isDebuff then
			return not a.isDebuff
		end
		return tostring(a.displayName) < tostring(b.displayName)
	end)
	return out
end

function BattleRuntime.CreateCard(team: string, slot: number, entry, supportEntry)
	local def = CardDefinitions.get(entry.cardId)
	if not def then
		return nil
	end

	local variant = entry.variant or "Standard"
	local level = entry.level or GameConfig.MinCardLevel
	local stats = CardStats.compute(entry.cardId, variant, level)
	if not stats then
		return nil
	end

	local supportPassives = {}
	local supportSnapshot = nil
	if supportEntry then
		local supportDef = SupportDefinitions.get(supportEntry.cardId)
		if supportDef then
			if supportDef.passive then
				table.insert(supportPassives, supportDef.passive)
			end
			supportSnapshot = {
				cardId = supportEntry.cardId,
				name = supportDef.name,
				passive = supportDef.passive,
				variant = supportEntry.variant or "Standard",
				level = supportEntry.level or GameConfig.MinCardLevel,
			}
		end
	end

	return {
		team = team,
		slot = slot,
		cardId = def.id,
		name = def.name,
		variant = variant,
		level = level,
		dmg = stats.dmg,
		-- The card's DMG as it entered the fight. `dmg` drifts as abilities add to
		-- it, so anything whose text says "base damage" must read this instead, or
		-- it compounds with whatever buffs happen to be up at that moment.
		baseDmg = stats.dmg,
		maxHP = stats.hp,
		-- The HP ceiling as it entered the fight, for the same reason as baseDmg:
		-- GainMaxHP moves maxHP, so an ability reading "50% of that card's HP"
		-- must read this or it compounds off whatever growth already happened.
		baseMaxHP = stats.hp,
		hp = stats.hp,
		alive = true,
		state = "hand",
		-- Set by PlayCard. 1 = the first card this side put on the field.
		playIndex = nil,
		-- Turns this card has personally taken. What SurvivedTurns reads: "on the
		-- field for N turns" has to count turns THIS card acted through, not global
		-- rounds, or a card played late inherits credit for the whole fight.
		turnsAlive = 0,
		-- Running total of stats taken off defeated enemies by `absorbs` effects.
		-- Damage with basis "Absorbed" spends it.
		absorbed = 0,
		passives = def.passive and { def.passive } or (def.passives or {}),
		supportPassives = supportPassives,
		support = supportSnapshot,
		statuses = {},
		-- UI metadata for persistent non-status modifiers. Combat calculations
		-- still use the existing scalar fields below; this table only exposes
		-- what already happened to the battle UI.
		modifiers = {},
		clauseState = {},
		extraAttackBonus = 0,
		bypassReduction = 0,
	}
end

function BattleRuntime.SnapshotCard(card)
	if not card then
		return nil
	end
	return {
		slot = card.slot,
		cardId = card.cardId,
		name = card.name,
		variant = card.variant,
		level = card.level,
		-- The EFFECTIVE figure, buffs included, because this is what the card face
		-- renders. `baseDmg` carries the unmultiplied stat for anything that needs
		-- to reason about the card rather than draw it.
		dmg = displayDmg(card),
		baseDmg = card.dmg,
		currentHP = math.max(0, card.hp),
		maxHP = card.maxHP,
		state = card.state,
		support = card.support,
		statuses = statusList(card),
		effects = effectList(card),
	}
end

-- Battle Power for one card, in the SAME terms the leaderboard and the deck
-- screen use: effective rarity after the variant multiplier. Computed here so a
-- hidden hand can still report a truthful total without naming a single card.
local function cardPower(card): number
	if not card or not card.cardId then return 0 end
	local def = CardDefinitions.get(card.cardId)
	if not (def and def.baseRarity) then return 0 end
	return VariantConfig.effectiveRarity(def.baseRarity, card.variant or "Standard")
end

-- `hidden` snapshots a side the viewer is not allowed to read.
--
-- The client used to be sent the enemy's whole hand and simply not draw it.
-- That is not hidden information - anything on the client is readable by the
-- player, so the "face down" cards were face up to anyone who looked. Hidden
-- entries carry a slot, their health and nothing else: no id, no name, no
-- stats, no statuses. There is nothing on the wire left to cheat with.
--
-- Two things the client legitimately needs are therefore computed HERE instead
-- of derived from the hand: the side's Battle Power, and which card its
-- portrait should show. The portrait has always revealed their strongest card
-- by design, so naming that one card costs nothing.
function BattleRuntime.SnapshotSide(side, hidden: boolean?)
	local hand = {}
	local defeated = {}
	local power = 0
	local best, bestPower = nil, -1

	local function consider(card)
		local p = cardPower(card)
		power += p
		if p > bestPower then best, bestPower = card, p end
	end

	for _, card in ipairs(side.cards) do
		if card.alive and card.state == "hand" then
			consider(card)
			if hidden then
				table.insert(hand, {
					slot = card.slot,
					hidden = true,
					state = card.state,
					currentHP = math.max(0, card.hp),
					maxHP = card.maxHP,
				})
			else
				table.insert(hand, BattleRuntime.SnapshotCard(card))
			end
		elseif not card.alive then
			table.insert(defeated, card.slot)
		end
	end
	if side.active then consider(side.active) end

	return {
		hand = hand,
		active = BattleRuntime.SnapshotCard(side.active),
		defeated = defeated,
		power = power,
		portrait = best and { cardId = best.cardId, variant = best.variant } or nil,
	}
end

function BattleRuntime.HasRemaining(side): boolean
	for _, card in ipairs(side.cards) do
		if card.alive then
			return true
		end
	end
	return false
end

function BattleRuntime.FindCard(side, slot: number)
	for _, card in ipairs(side.cards) do
		if card.slot == slot then
			return card
		end
	end
	return nil
end

local function activeOf(session, team: string)
	return sideOf(session, team).active
end

local function resolveTargets(session, source, spec: string)
	local ownSide = sideOf(session, source.team)
	local enemySide = sideOf(session, enemyTeamOf(source.team))

	if spec == "Self" or spec == "PairedCard" then
		return { source }
	end

	if spec == "AllAllies" then
		local out = {}
		for _, other in ipairs(ownSide.cards) do
			if other.alive and other ~= source then
				table.insert(out, other)
			end
		end
		return out
	end

	if spec == "ActiveEnemy" or spec == "LastHit" then
		return enemySide.active and { enemySide.active } or {}
	end

	if spec == "ActiveAndNextEnemy" then
		local out = enemySide.active and { enemySide.active } or {}
		for _, card in ipairs(enemySide.cards) do
			if card.alive and card.state == "hand" then table.insert(out, card); break end
		end
		return out
	end

	if spec == "NextEnemy" then
		-- In this interactive version the replacement queue is the visible hand.
		-- So "next enemy" means the first living card still waiting in that hand.
		for _, card in ipairs(enemySide.cards) do
			if card.alive and card.state == "hand" then
				return { card }
			end
		end
		return {}
	end

	if spec == "AllEnemies" then
		-- The whole opposing party still standing, the active fighter included.
		-- That is what "the enemy party" means on a card face.
		--
		-- ORDER MATTERS, because the effects run one target at a time and the
		-- replay puts a beat between each: this list is the order the player
		-- watches it happen in. Active FIRST, then the queue behind it, so a beam
		-- that hits everyone reads as a chain sweeping down the line from the card
		-- in front. Walking raw slot order started the sweep somewhere in the
		-- middle of their party for no visible reason.
		local out = {}
		if enemySide.active and enemySide.active.alive then
			table.insert(out, enemySide.active)
		end
		for _, card in ipairs(enemySide.cards) do
			if card.alive and card ~= enemySide.active then
				table.insert(out, card)
			end
		end
		return out
	end

	if spec == "Victim" then
		-- The card that just died, during the OnKill it caused. It cannot be reached
		-- any other way: by the time OnKill fires the victim is dead and no longer
		-- active, so ActiveEnemy and LastHit have both moved on. session.victim is
		-- set for exactly the length of that one trigger and cleared after.
		return session.victim and { session.victim } or {}
	end

	-- "Ally:<cardId>" names ONE specific card in the source's own party, whether
	-- it is fighting, waiting, or already defeated. Deck MEMBERSHIP is what an
	-- ability worded "if X is in your active deck" reads, so this deliberately
	-- does not filter on alive.
	local allyId = string.match(spec, "^Ally:(.+)$")
	if allyId then
		for _, other in ipairs(ownSide.cards) do
			if other ~= source and other.cardId == allyId then
				return { other }
			end
		end
		return {}
	end

	return { source }
end

-- How many times a `scaleBy` effect multiplies its potency.
--
-- Returns 1 when the effect does not scale at all, so every call site can
-- multiply unconditionally. Returns 0 when the effect scales off a count that
-- came up empty, and callers treat 0 as "do nothing" - an ability that counts
-- allies should not apply a zero-strength buff and light up the effects bar.
local function scaleCount(session, source, effect): number
	local scaleBy = effect.scaleBy
	if not scaleBy then
		return 1
	end

	local side = sideOf(session, source.team)

	if scaleBy == "DefeatedAllies" then
		local n = 0
		for _, other in ipairs(side.cards) do
			if other ~= source and not other.alive then
				n += 1
			end
		end
		return n
	end

	-- Counts by NAME, not by id, because the cards this groups together are the
	-- ones a player recognises as "the masters" from the card face. It counts the
	-- source itself when the source's own name matches, which is what "per card
	-- with 'master' in their name in your deck" says.
	if scaleBy == "AlliesNamed" then
		local needle = string.lower(effect.nameContains or "")
		if needle == "" then
			return 0
		end
		local n = 0
		for _, other in ipairs(side.cards) do
			if string.find(string.lower(other.name or ""), needle, 1, true) then
				n += 1
			end
		end
		return n
	end

	return 1
end

local function applyStatus(session, source, target, statusId: string, stacks, duration, potency, sourceDmg, sourceAbilityId, sourceAbilityName, sourceCardName, sourceCardId, events)
	local def = StatusEffects.get(statusId)
	if not def then
		return
	end

	local appliedDuration = duration
	if appliedDuration == nil then
		appliedDuration = 1
	end

	local existing = target.statuses[statusId]
	if existing and def.stacking == "Stack" then
		existing.stacks = math.min(def.maxStacks or 99, existing.stacks + (stacks or 1))
		existing.duration = math.max(existing.duration or 0, appliedDuration)
		existing.initialDuration = math.max(existing.initialDuration or 0, appliedDuration)
		existing.potency = math.max(existing.potency or 0, potency or 0)
		existing.sourceDmg = math.max(existing.sourceDmg or 0, sourceDmg or 0)
	elseif existing and def.stacking == "Unique" then
		return
	elseif existing and def.stacking == "Refresh" then
		existing.stacks = math.min(def.maxStacks or 1, stacks or 1)
		existing.duration = appliedDuration
		existing.initialDuration = appliedDuration
		existing.potency = math.max(existing.potency or 0, potency or 0)
		existing.sourceDmg = math.max(existing.sourceDmg or 0, sourceDmg or 0)
	else
		target.statuses[statusId] = {
			stacks = math.min(def.maxStacks or 99, stacks or 1),
			duration = appliedDuration,
			initialDuration = appliedDuration,
			potency = potency or 0,
			sourceDmg = sourceDmg or 0,
		}
	end

	local state = target.statuses[statusId]
	state.sourceCard = sourceCardName or (source and source.name or nil)
	state.sourceCardId = sourceCardId or (source and source.cardId or nil)
	state.sourceSide = source and source.team or nil
	state.sourceSlot = source and source.slot or nil
	state.sourceAbility = sourceAbilityName
	state.sourceAbilityId = sourceAbilityId
	state.appliedRound = session.round

	push(events, "Status", {
		side = target.team,
		slot = target.slot,
		status = statusId,
		statusName = def.display or statusId,
		effect = snapshotStatus(target, statusId, state),
		round = session.round,
	})

	-- A DmgUp landing changes what the card hits for, so the face has to follow.
	pushStat(target, events)
end

local function checkDeath(session, card, events)
	if not card or card.hp > 0 or not card.alive then
		return false
	end

	BattleRuntime.FireTrigger(session, card, "OnFatalHit", {}, events)
	if card.hp > 0 then return false end
	local side = sideOf(session, card.team)
	local wasActive = side.active == card

	card.hp = 0
	card.alive = false
	card.state = "defeated"
	if wasActive then
		side.active = nil
	end

	push(events, "Death", {
		side = card.team,
		slot = card.slot,
		cardName = card.name,
	})

	-- Existing OnDeath abilities are allowed to revive the card.
	BattleRuntime.FireTrigger(session, card, "OnDeath", {}, events)

	if card.alive then
		card.state = wasActive and "active" or "hand"
		if wasActive then
			side.active = card
		end
		return false
	end

	if wasActive then TurnOrder.recordDefeat(session, card.team) end
	return true
end

local function dealDamage(session, source, target, amount: number, tag: string, events, hit)
	if not target or not target.alive then
		return 0
	end

	local reduction = math.min(GameConfig.MaxDamageReduction, statusTotal(target, "DmgReduction", "potency")
		+ statusTotal(target, "AppleGuard", "potency"))
	reduction = math.max(0, reduction - (source and source.bypassReduction or 0))
	amount *= (1 - reduction)
	-- Preserve small percentage effects. A positive hit should never disappear
	-- just because its fractional result was below one.
	amount = amount > 0 and math.max(1, math.floor(amount)) or 0

	local shield = target.statuses.Shield
	if shield then
		local pool = (shield.potency or 0) * target.maxHP * (shield.stacks or 1)
		if pool >= amount then
			if target.maxHP > 0 and (shield.stacks or 1) > 0 then
				shield.potency -= amount / (target.maxHP * shield.stacks)
			end
			push(events, "Shield", {
				side = target.team,
				slot = target.slot,
				amount = math.floor(amount),
			})
			return 0
		end
		amount -= pool
		target.statuses.Shield = nil
	end

	amount = math.max(0, math.floor(amount))
	target.hp -= amount

	push(events, "Damage", {
		side = target.team,
		slot = target.slot,
		amount = amount,
		hp = math.max(0, target.hp),
		maxHP = target.maxHP,
		tag = tag,
		sourceSide = source and source.team or nil,
		sourceSlot = source and source.slot or nil,
		sourceName = source and source.name or nil,
		targetName = target.name,
		attackId = hit and hit.attack.id, hitIndex = hit and hit.index,
		hitCount = hit and hit.attack.hitCount, potency = hit and hit.potency,
	})

	if amount > 0 then
		BattleRuntime.FireTrigger(session, target, "OnHealthChanged", {}, events)
		BattleRuntime.FireTrigger(session, target, "OnHitTaken", { damageTaken = amount, tag = tag, hit = hit, attack = hit and hit.attack }, events)
	end
	return amount
end

function BattleRuntime.LoseHP(session, target, amount: number, tag: string, events)
	if not target or not target.alive then
		return 0
	end
	amount = math.max(0, math.floor(amount))
	target.hp -= amount
	push(events, "Damage", {
		side = target.team,
		slot = target.slot,
		amount = amount,
		hp = math.max(0, target.hp),
		maxHP = target.maxHP,
		tag = tag,
		sourceSide = "location",
		sourceName = "Location",
		targetName = target.name,
	})
	if amount > 0 then
		BattleRuntime.FireTrigger(session, target, "OnHealthChanged", {}, events)
		BattleRuntime.FireTrigger(session, target, "OnDamage", { damageTaken = amount, tag = tag }, events)
	end
	checkDeath(session, target, events)
	return amount
end

local CONDITIONS = {
	CanDazeAttacker = function(session, card, _, context)
		local attacker = context and context.attacker
		if not attacker or not attacker.alive or attacker.hp <= 0 or not card.alive or card.hp <= 0
			or context.cancelled then return false end
		return #AttackContext.livingAllies(attacker, sideOf(session, attacker.team).cards) > 0
	end,

	HPAtMost = function(_, card, arg)
		return card.maxHP > 0 and card.hp / card.maxHP <= (tonumber(arg) or 0)
	end,
	StrongerThanTarget = function(session, card)
		local enemy = activeOf(session, enemyTeamOf(card.team))
		return enemy ~= nil and card.dmg > enemy.dmg
	end,

	HasDmgUp = function(_, card)
		return statusTotal(card, "DmgUp", "potency") > 0
	end,

	-- True while the card is under half health. Pair with limit = 1 for a
	-- one-shot "desperation" ability, or it re-fires on every hit taken.
	BelowHalfHP = function(_, card)
		return card.maxHP > 0 and (card.hp / card.maxHP) < 0.5
	end,

	-- "this card was the FIRST one its side put on the field". playIndex is
	-- stamped in PlayCard and never changes, so an OnDeath clause gated on this
	-- still knows how the card arrived many rounds earlier.
	PlayedFirst = function(_, card)
		return card.playIndex == 1
	end,

	-- "this card is the LAST one its side had to play": nothing else of theirs is
	-- still waiting in hand. Defeated cards do not count as waiting, so a card
	-- brought out over the corpses of the rest of the party reads as played last.
	PlayedLast = function(session, card)
		for _, other in ipairs(sideOf(session, card.team).cards) do
			if other ~= card and other.alive and other.state == "hand" then
				return false
			end
		end
		return true
	end,

	-- "Master of Both is somewhere in this card's party", alive or not: Last Hope
	-- reads deck membership, not survival, so a fallen partner still counts.
	HasMasterOfBoth = function(session, card)
		for _, other in ipairs(sideOf(session, card.team).cards) do
			if other ~= card and other.cardId == "MasterOfBoth" then
				return true
			end
		end
		return false
	end,

	HasNextEnemy = function(session, card)
		for _, other in ipairs(sideOf(session, enemyTeamOf(card.team)).cards) do
			if other.alive and other.state == "hand" then return true end
		end
		return false
	end,

	-- ── parameterised conditions ─────────────────────────────
	-- These take the text after the colon in the clause's condition string, so one
	-- entry serves every card instead of a hardcoded predicate per ability.
	-- HasMasterOfBoth above is the old hardcoded shape, kept because saved passives
	-- still name it.

	-- "HasAlly:SonWarrior" - that card is somewhere in this card's party, alive or
	-- not. Deck MEMBERSHIP, matching how HasMasterOfBoth already reads.
	HasAlly = function(session, card, arg)
		if not arg then return false end
		for _, other in ipairs(sideOf(session, card.team).cards) do
			if other ~= card and other.cardId == arg then
				return true
			end
		end
		return false
	end,

	-- "HasStatus:Charging" - used with the ! prefix far more often than without,
	-- to gate a payout on a wind-up having finished.
	HasStatus = function(_, card, arg)
		return arg ~= nil and card.statuses[arg] ~= nil
	end,

	-- "HasStacks:Money:3" - at least N stacks of a status.
	HasStacks = function(_, card, arg)
		if not arg then return false end
		local id, n = string.match(arg, "^(.-):(%d+)$")
		if not id then return false end
		local state = card.statuses[id]
		return state ~= nil and (state.stacks or 0) >= tonumber(n)
	end,

	-- "SurvivedTurns:2" - this card has taken at least N turns of its own.
	SurvivedTurns = function(_, card, arg)
		return arg ~= nil and (card.turnsAlive or 0) >= (tonumber(arg) or 0)
	end,
}

-- Resolves a clause's `condition` string, which may be:
--   "Name"            a plain predicate
--   "Name:arg"        a parameterised one
--   "!Name" / "!N:a"  the negation of either
--
-- An UNKNOWN condition blocks the clause, negated or not. That is deliberate: a
-- typo should make an ability silently do nothing rather than fire
-- unconditionally, which is the failure mode that is hard to notice.
local function conditionHolds(session, card, spec: string?, context): boolean
	if not spec then
		return true
	end

	local negate = false
	if string.sub(spec, 1, 1) == "!" then
		negate = true
		spec = string.sub(spec, 2)
	end

	local name, arg = string.match(spec, "^([^:]+):(.+)$")
	name = name or spec

	local fn = CONDITIONS[name]
	if not fn then
		return false
	end

	local held = fn(session, card, arg, context) and true or false
	if negate then
		return not held
	end
	return held
end

-- A clause may carry `condition` (one spec) and/or `conditions` (a list). ALL of
-- them must hold. The list exists because a single string cannot express an AND,
-- and "only on its second turn AND only with that ally present" is two
-- independent facts about two different things - splitting it across two clauses
-- instead would roll the trigger's chance twice and let half the ability fire.
local function clauseGateOpen(session, card, clause, context): boolean
	if not conditionHolds(session, card, clause.condition, context) then
		return false
	end
	for _, spec in ipairs(clause.conditions or {}) do
		if not conditionHolds(session, card, spec, context) then
			return false
		end
	end
	return true
end

local function runEffect(session, source, effect, context, events)
	local kind = effect.kind
	local function effectTargets(spec)
		if context.attack and context.attack.attacker == source
			and (spec == "ActiveEnemy" or spec == "LastHit") then
			local target = context.attack.target
			return target.alive and { target } or {}
		end
		return resolveTargets(session, source, spec)
	end

	if CardAbilityRules.handles(kind) then
		for _, inner in ipairs(CardAbilityRules.expand(kind, source, effectTargets("ActiveEnemy")[1], session, context)) do
			runEffect(session, source, inner, context, events)
		end
		return
	end

	if kind == "Damage" then
		if context.attack and context.attacker and effect.from == "LastHit" then
			for _, target in ipairs(effectTargets(effect.target or "ActiveEnemy")) do
				table.insert(context.attack.reflections, { target = target, source = source,
					share = (effect.potency or 1) * scaleCount(session, source, effect), tag = effect.tag or "passive" })
			end
			return
		end

		-- By default the hit is a share of the SOURCE's own DMG. `from` re-bases it
		-- on another card instead, which is what a redirect needs: the damage passed
		-- down the line is a share of what the ATTACKER swung for, not a share of
		-- what the card doing the redirecting hits for.
		-- `basis` re-bases the hit on something OTHER than a DMG stat:
		--   "MaxHP"     the source's own HP ceiling, for a card that detonates itself
		--   "Absorbed"  everything the source has taken off things it killed
		-- Neither is scaled by DmgUp: they are not swings, so a damage buff has
		-- nothing to act on.
		local basis = source.dmg * damageMultiplier(source)
		if effect.basis == "BaseDMG" then
			basis = source.baseDmg or source.dmg
		elseif effect.basis == "MaxHP" then
			basis = source.maxHP
		elseif effect.basis == "Absorbed" then
			-- Nothing absorbed means no explosion at all, rather than a floored
			-- one-point hit that reads as the ability having fired.
			if (source.absorbed or 0) <= 0 then
				return
			end
			basis = source.absorbed
		end
		if effect.from then
			local fromCard = effectTargets(effect.from)[1]
			if not fromCard then
				return
			end
			basis = fromCard.dmg
		end

		local scale = scaleCount(session, source, effect)
		if scale <= 0 then
			return
		end

		for _, target in ipairs(effectTargets(effect.target or "ActiveEnemy")) do
			local dealt = dealDamage(
				session,
				source,
				target,
				(effect.basis == "TargetMaxHP" and target.maxHP or basis) * (effect.potency or 1) * scale,
				effect.tag or "passive",
				events
			)
			context.damageDealt = (context.damageDealt or 0) + dealt
			checkDeath(session, target, events)
		end

	elseif kind == "AttackMultiplier" then
		if context.attack then
			context.attack.damageMultiplier = (context.attack.damageMultiplier or 1) * (effect.multiplier or 1)
		end
	elseif kind == "RestoreHP" then
		source.hp = math.max(1, math.floor(source.maxHP * (effect.hpPercent or 0.30)))
		push(events, "Heal", { side = source.team, slot = source.slot, amount = source.hp,
			hp = source.hp, maxHP = source.maxHP, cardName = source.name })
	elseif kind == "RemoveStatus" then
		for _, target in ipairs(effectTargets(effect.target or "Self")) do
			target.statuses[effect.status] = nil
			push(events, "StatusEnd", { side = target.team, slot = target.slot, status = effect.status,
				statusName = (StatusEffects.get(effect.status) or {}).display or effect.status, round = session.round })
		end
	elseif kind == "Heal" then
		for _, target in ipairs(effectTargets(effect.target or "Self")) do
			if target.alive then
				local amount
				if effect.scalesWith == "DamageDealt" then
					amount = (context.damageDealt or 0) * (effect.potency or 0)
				elseif effect.scalesWith == "DamageTaken" then
					-- Set by the OnDamage trigger. Lets a card leech back a share of
					-- what just hit it, rather than a share of its own max HP.
					amount = (context.damageTaken or 0) * (effect.potency or 0)
				else
					amount = target.maxHP * (effect.potency or 0)
				end
				-- Any real percentage-based heal must restore at least 1 HP. The old
				-- floor turned Weather Girl's 5% heal into zero on low-HP cards.
				local requested = amount > 0 and math.max(1, math.floor(amount)) or 0
				local beforeHP = target.hp
				target.hp = math.min(target.maxHP, target.hp + requested)
				local healed = math.max(0, target.hp - beforeHP)
				push(events, "Heal", {
					side = target.team,
					slot = target.slot,
					amount = healed,
					hp = target.hp,
					maxHP = target.maxHP,
					cardName = target.name,
				})
			end
		end

	elseif kind == "ApplyStatus" then
		if effect.deferUntilEnemyEntry and not activeOf(session, enemyTeamOf(source.team)) then
			local enemySide = sideOf(session, enemyTeamOf(source.team))
			enemySide.pendingEntryStatuses = enemySide.pendingEntryStatuses or {}
			table.insert(enemySide.pendingEntryStatuses, { source = source, effect = effect, context = table.clone(context) })
			return
		end
		local basis = effect.useSourceDmg and source.dmg or (context.damageDealt or source.dmg)
		local scale = scaleCount(session, source, effect)
		if scale <= 0 then
			return
		end
		local targets = effectTargets(effect.target or "ActiveEnemy")
		if effect.target == "Attacker" then
			targets = context.attacker and { context.attacker } or {}
		end
		for _, target in ipairs(targets) do
			-- namedPotency lets ONE clause buff two grades of ally at different
			-- strengths ("10%, or 20% if the ally is a master"). Splitting that into
			-- two clauses would roll the trigger's chance twice and let a card get
			-- the weak buff, the strong buff, both, or neither.
			local potency = effect.potency or 0
			if effect.namedPotency and effect.nameContains
				and string.find(string.lower(target.name or ""), string.lower(effect.nameContains), 1, true) then
				potency = effect.namedPotency
			end
			applyStatus(
				session,
				source,
				target,
				effect.status,
				effect.stacks or 1,
				effect.duration ~= nil and effect.duration or 1,
				potency * scale,
				basis,
				context.sourceAbilityId,
				context.sourceAbilityName,
				context.sourceCardName,
				context.sourceCardId,
				events
			)
		end

	elseif kind == "Revive" then
		for _, target in ipairs(effectTargets(effect.target or "Self")) do
			if not target.alive then
				target.alive = true
				target.hp = math.max(1, math.floor(target.maxHP * (effect.hpPercent or 0.5)))
				target.statuses = {}
				push(events, "Revive", {
					side = target.team,
					slot = target.slot,
					hp = target.hp,
					maxHP = target.maxHP,
					cardName = target.name,
				})
			end
		end

	elseif kind == "ExtraAttack" then
		source.extraAttackBonus += (effect.chanceBonus or 1)
		source.modifiers.ExtraAttackChance = {
			displayName = "Double Strike",
			description = "Chance to make an additional attack.",
			category = "Buff",
			isDebuff = false,
			value = source.extraAttackBonus,
			valueType = "Chance",
			duration = 0,
			initialDuration = 0,
			sourceCard = context.sourceCardName or source.name,
			sourceCardId = context.sourceCardId or source.cardId,
			sourceAbility = context.sourceAbilityName,
			sourceAbilityId = context.sourceAbilityId,
			sourceSide = source.team,
			appliedRound = session.round,
		}
		push(events, "Modifier", {
			side = source.team,
			slot = source.slot,
			id = "ExtraAttackChance",
			displayName = "Double Strike",
			value = effect.chanceBonus or 1,
			valueType = "Chance",
			sourceCardName = context.sourceCardName or source.name,
		})

	elseif kind == "GainDamage" then
		-- Permanently raises this card's DMG by a share of ANOTHER card's DMG.
		-- `from` names whose stat to read, defaulting to the attacker, so during
		-- OnAttacked "LastHit" is the card that just swung.
		--
		-- Reads `from.baseDmg` rather than `from.dmg` on purpose: the card text
		-- says BASE damage, and using the live stat would let a buffed or
		-- crit-boosted attacker hand over far more than the ability promises.
		--
		-- `scaleBy` multiplies the gain by a count, for text worded "per defeated
		-- ally". A count of zero means there was nothing to scale off, and must grant
		-- nothing at all - NOT the one-point floor the math.max below would give it.
		local gainScale = scaleCount(session, source, effect)
		if gainScale <= 0 then
			return
		end
		for _, from in ipairs(effectTargets(effect.from or "LastHit")) do
			local basis = from.baseDmg or from.dmg   -- baseDmg is set at card build
			local gain = math.max(1, math.floor(basis * (effect.potency or 0) * gainScale))
			source.dmg += gain
			-- `absorbs` banks the gain so a later Damage with basis "Absorbed" can
			-- spend it.
			if effect.absorbs then
				source.absorbed = (source.absorbed or 0) + gain
			end
			source.modifiers.PermanentDamage = {
				displayName = "Permanent DMG",
				description = "Permanent damage gained from an ability.",
				category = "Buff",
				isDebuff = false,
				value = (source.modifiers.PermanentDamage and source.modifiers.PermanentDamage.value or 0) + gain,
				valueType = "Flat",
				duration = 0,
				initialDuration = 0,
				sourceCard = context.sourceCardName or source.name,
				sourceCardId = context.sourceCardId or source.cardId,
				sourceAbility = context.sourceAbilityName,
				sourceAbilityId = context.sourceAbilityId,
				sourceSide = source.team,
				appliedRound = session.round,
			}
			-- Permanent DMG gain: push the new figure to the card face at once.
			pushStat(source, events)
			push(events, "Modifier", {
				side = source.team,
				slot = source.slot,
				id = "PermanentDamage",
				displayName = "Permanent DMG",
				value = gain,
				valueType = "Flat",
				sourceCardName = context.sourceCardName or source.name,
			})
		end

	elseif kind == "GainMaxHP" then
		-- Raises the ceiling AND grants the same amount as current HP. Growing only
		-- maxHP would hand the card a bigger empty bar, which reads as a downgrade
		-- at the exact moment the ability is supposed to save it.
		--
		-- `from` reads the ceiling off a DIFFERENT card, for text worded "gain 50% of
		-- that card's HP". It reads baseMaxHP, so the gift is a share of what the
		-- other card printed rather than of whatever it has since grown to.
		local hpScale = scaleCount(session, source, effect)
		local basisCard = effect.from and effectTargets(effect.from)[1] or nil
		if hpScale <= 0 or (effect.from and not basisCard) then
			return
		end
		local hpBasis = basisCard and (basisCard.baseMaxHP or basisCard.maxHP) or nil
		for _, target in ipairs(effectTargets(effect.target or "Self")) do
			if target.alive then
				local gain = math.max(1, math.floor((hpBasis or target.maxHP) * (effect.potency or 0) * hpScale))
				target.maxHP += gain
				target.hp = math.min(target.maxHP, target.hp + gain)
				-- Banked on the SOURCE, not the target: it is the card that ate the
				-- stat that later detonates.
				if effect.absorbs then
					source.absorbed = (source.absorbed or 0) + gain
				end
				push(events, "Heal", {
					side = target.team,
					slot = target.slot,
					amount = gain,
					hp = target.hp,
					maxHP = target.maxHP,
					cardName = target.name,
				})
				pushStat(target, events)
				-- Recorded as a permanent modifier so the effect column can show a
				-- Max HP Up icon for the rest of the battle.
				target.modifiers = target.modifiers or {}
				local prevHp = target.modifiers.PermanentMaxHP
				target.modifiers.PermanentMaxHP = {
					displayName = "Max HP Up",
					description = "Permanently raised max HP for this battle.",
					category = "Buff",
					isDebuff = false,
					value = (prevHp and prevHp.value or 0) + gain,
					valueType = "Flat",
					duration = 0,
					initialDuration = 0,
					sourceCard = context.sourceCardName or source.name,
					sourceCardId = context.sourceCardId or source.cardId,
					sourceAbility = context.sourceAbilityName,
					sourceAbilityId = context.sourceAbilityId,
					sourceSide = source.team,
					appliedRound = session.round,
				}
				push(events, "Modifier", {
					side = target.team,
					slot = target.slot,
					id = "PermanentMaxHP",
					displayName = "Max HP Up",
					value = gain,
					valueType = "Flat",
					sourceCardName = context.sourceCardName or source.name,
				})
			end
		end

	elseif kind == "SummonClone" then
		-- Appends a fresh card to the owner's party. SnapshotSide walks side.cards
		-- and picks up anything alive and in hand, so the client needs no changes.
		--
		-- The clone carries NO passives on purpose: cloning a card that clones on
		-- death would otherwise spawn an endless chain of copies.
		local side = sideOf(session, source.team)
		local scale = effect.statScale or 0.5

		local maxSlot = 0
		for _, c in ipairs(side.cards) do
			if c.slot > maxSlot then maxSlot = c.slot end
		end

		local hp = math.max(1, math.floor(source.maxHP * scale))
		local dmg = math.max(1, math.floor((source.baseDmg or source.dmg) * scale))
		local clone = {
			team = source.team,
			slot = maxSlot + 1,
			cardId = source.cardId,
			name = source.name .. " (Clone)",
			variant = source.variant,
			level = source.level,
			dmg = dmg,
			baseDmg = dmg,
			maxHP = hp,
			baseMaxHP = hp,
			hp = hp,
			alive = true,
			state = "hand",
			passives = {},
			supportPassives = {},
			support = nil,
			statuses = {},
			modifiers = {},
			clauseState = {},
			extraAttackBonus = 0,
			bypassReduction = 0,
		}
		table.insert(side.cards, clone)

		push(events, "Summon", {
			side = clone.team,
			slot = clone.slot,
			cardName = clone.name,
			card = BattleRuntime.SnapshotCard(clone),
		})

	elseif kind == "RandomChoice" then
		-- Picks exactly ONE branch, so an ability worded "either X or Y" can never
		-- fire both or neither. Weights default to 1, an even split.
		--
		-- This is one effect rather than two clauses because the clause's `limit` has
		-- to be SHARED between the branches: "can activate up to 4 times" means four
		-- activations total, not four of each.
		local options = effect.options or {}
		local total = 0
		for _, option in ipairs(options) do
			total += (option.weight or 1)
		end
		if total > 0 then
			local pick = session.rng:NextNumber() * total
			local acc = 0
			for _, option in ipairs(options) do
				acc += (option.weight or 1)
				if pick <= acc then
					for _, inner in ipairs(option.effects or {}) do
						runEffect(session, source, inner, context, events)
					end
					break
				end
			end
		end

	elseif kind == "CancelAttack" then
		context.cancelled = true
	end
end

function BattleRuntime.FireTrigger(session, card, trigger: string, context, events)
	if not card then
		return context or {}
	end
	if not card.alive and trigger ~= "OnDeath" then
		return context or {}
	end

	context = context or {}

	for listIndex, passiveList in ipairs({ card.passives, card.supportPassives }) do
		local sourceCardName = card.name
		local sourceCardId = card.cardId
		if listIndex == 2 and card.support then
			sourceCardName = card.support.name or sourceCardName
			sourceCardId = card.support.cardId or sourceCardId
		end
		for _, passiveId in ipairs(passiveList) do
			local passive = PassiveDefinitions.get(passiveId)
			if passive then
				for index, clause in ipairs(passive.clauses or {}) do
					local blocked = not clauseGateOpen(session, card, clause, context)
					if clause.trigger == trigger and not blocked then
						local key = passiveId .. ":" .. tostring(index)
						local state = card.clauseState[key]
						if not state then
							state = { uses = 0, bonus = 0, ticks = 0 }
							card.clauseState[key] = state
						end
						-- `oncePerAttack` collapses a per-HIT trigger down to per-ATTACK.
						-- OnHitTaken and OnDamage fire once per damage instance, which is
						-- right for a single swing and badly wrong for a volley: a twelve
						-- bullet attack counted as twelve separate hits, so a clause that
						-- pays out a flat bonus each time paid out twelve times for one
						-- attack. Keyed on the attack's id, which is a per-battle sequence
						-- number, so two genuine attacks in the same turn still both count.
						if clause.oncePerAttack then
							local attackId = context.attack and context.attack.id
							if attackId and state.lastAttackId == attackId then
								blocked = true
							else
								state.lastAttackId = attackId
							end
						end

						-- `everyNth` counts how many times the trigger has reached this
						-- clause and only lets every Nth one through. Counted AFTER the
						-- condition gate and the limit, so a turn the clause could not have
						-- fired on does not consume a beat and shift the rhythm - "every
						-- second attack" has to stay on the attacks that actually happened.
						local onBeat = true
						if clause.everyNth and not blocked and ((not clause.limit) or state.uses < clause.limit) then
							state.ticks = (state.ticks or 0) + 1
							onBeat = (state.ticks % clause.everyNth) == 0
						end

						if onBeat and not blocked and ((not clause.limit) or state.uses < clause.limit) then
							local chance = math.clamp((clause.chance or 1) + state.bonus, 0, 1)
							-- A decayed chance that has run to zero must not roll at all:
							-- NextNumber can return exactly 0 and `0 <= 0` would let a spent
							-- ability fire once more.
							if chance > 0 and session.rng:NextNumber() <= chance then
								state.uses += 1
								-- chanceOnHit is the mirror of chanceOnFail: added to the
								-- clause's chance every time it DOES land, so a negative value
								-- is an ability that wears itself out.
								if clause.chanceOnHit then
									state.bonus = math.max(-(clause.chance or 1), state.bonus + clause.chanceOnHit)
								end
								push(events, "Passive", {
									side = card.team,
									slot = card.slot,
									passive = passiveId,
									passiveName = passive.name or passiveId,
									passiveDescription = passive.description or "",
									chance = chance, nextChance = math.clamp((clause.chance or 1) + state.bonus, 0, 1),
									cardName = card.name,
									sourceCardName = sourceCardName,
									trigger = trigger,
									round = session.round,
								})
								-- Keep using the SAME combat context so existing effects such as
								-- CancelAttack and DamageDealt keep their original behavior. We only
								-- attach temporary source metadata while this passive's effects run.
								local previousAbilityId = context.sourceAbilityId
								local previousAbilityName = context.sourceAbilityName
								local previousSourceCardName = context.sourceCardName
								local previousSourceCardId = context.sourceCardId
								context.sourceAbilityId = passiveId
								context.sourceAbilityName = passive.name or passiveId
								context.sourceCardName = sourceCardName
								context.sourceCardId = sourceCardId
								for _, effect in ipairs(clause.effects or {}) do
									runEffect(session, card, effect, context, events)
								end
								context.sourceAbilityId = previousAbilityId
								context.sourceAbilityName = previousAbilityName
								context.sourceCardName = previousSourceCardName
								context.sourceCardId = previousSourceCardId
							elseif clause.chanceOnFail then
								state.bonus += clause.chanceOnFail
							end
						end
					end
				end
			end
		end
	end

	return context
end

local function consumeDisabledTurn(card, events, round): boolean
	for statusId, state in pairs(card.statuses) do
		local def = StatusEffects.get(statusId)
		if def and def.skipsTurn and (state.duration or 0) > 0 then
			-- Control duration counts turns actually denied, not global round ends.
			-- This prevents a late-round stun from expiring before its victim acts.
			state.duration -= 1
			if state.duration <= 0 then
				card.statuses[statusId] = nil
				push(events, "StatusEnd", {
					side = card.team,
					slot = card.slot,
					status = statusId,
					statusName = def.display or statusId,
					round = round,
				})
			end
			return true
		end
	end
	return false
end

function BattleRuntime.PlayCard(session, team: string, slot: number, events)
	local side = sideOf(session, team)
	if side.active then
		return false, "an active card is already in play"
	end

	local card = BattleRuntime.FindCard(side, slot)
	if not card or not card.alive or card.state ~= "hand" then
		return false, "that card is not available"
	end

	card.state = "active"
	side.active = card

	-- Play ORDER, for abilities worded "if this card is played first / last". It
	-- is stamped once and never revised, so an OnDeath clause many rounds later
	-- still knows how this card arrived.
	side.playCount = (side.playCount or 0) + 1
	card.playIndex = side.playCount

	push(events, "Enter", {
		side = team,
		slot = card.slot,
		cardName = card.name,
		card = BattleRuntime.SnapshotCard(card),
	})

	local pending = side.pendingEntryStatuses
	side.pendingEntryStatuses = nil
	for _, item in ipairs(pending or {}) do
		if item.source.alive then runEffect(session, item.source, item.effect, item.context, events) end
	end
	BattleRuntime.FireTrigger(session, card, "OnEntry", {}, events)
	-- OnPlay is an additive interactive-battle trigger for future cards. Existing
	-- cards continue using OnEntry exactly as before.
	BattleRuntime.FireTrigger(session, card, "OnPlay", {}, events)
	checkDeath(session, card, events)
	CardAbilityRules.encounter(session.player.active, session.enemy.active, function(fighter, encounterContext)
		BattleRuntime.FireTrigger(session, fighter, "OnEncounter", encounterContext, events)
	end)
	return true, nil
end

-- Consume Daze on the incoming attack; redirected damage cannot reapply it.
local function redirectDazedAttack(session, source, events, cancelled)
	local state = source.statuses.Daze
	if not state then return nil end
	source.statuses.Daze = nil
	push(events, "StatusEnd", { side = source.team, slot = source.slot, status = "Daze", statusName = "Daze", round = session.round })
	if cancelled or (state.duration or 0) <= 0 then return nil end
	local captainSide = state.sourceSide and sideOf(session, state.sourceSide)
	local captain = captainSide and BattleRuntime.FindCard(captainSide, state.sourceSlot)
	local allies = AttackContext.livingAllies(source, sideOf(session, source.team).cards)
	if not captain or not captain.alive or #allies == 0 then return nil end
	return { { target = allies[session.rng:NextInteger(1, #allies)], share = 0.80, source = source, tag = "daze" },
		{ target = captain, share = 0.20, source = source, tag = "daze" } }
end

local function performAttack(session, source, events)
	if not source or not source.alive or source.state ~= "active" then
		return
	end

	-- Counted before OnTurnStart, so a clause gated on SurvivedTurns:1 can fire on
	-- this card's very first turn and the numbers read the way a player counts.
	-- Counted even on a turn the card is stunned out of: it was still on the field
	-- for it, which is what "has been alive for N turns" means.
	source.turnsAlive = (source.turnsAlive or 0) + 1

	BattleRuntime.FireTrigger(session, source, "OnTurnStart", {}, events)
	if not source.alive then
		return
	end

	if consumeDisabledTurn(source, events, session.round) then
		push(events, "Skip", {
			side = source.team,
			slot = source.slot,
			cardName = source.name,
		})
		return
	end

	local attacks = 1
	if source.extraAttackBonus > 0 and session.rng:NextNumber() <= source.extraAttackBonus then
		attacks = 2
	end

	for attackIndex = 1, attacks do
		if not source.alive then break end
		local target = activeOf(session, enemyTeamOf(source.team))
		if not target or not target.alive then break end
		local attack = AttackContext.new(session, source, target,
			PassiveDefinitions.attackPattern(source.passives), session.rng)
		BattleRuntime.FireTrigger(session, source, "OnBeforeAttack", { attack = attack }, events)
		-- Snapshot and consume the hack once per attack, including multi-hit volleys.
		local hack = source.statuses.SystemHack
		attack.damageMultiplier = (attack.damageMultiplier or 1) * (1 - (hack and hack.potency or 0))
		if hack then
			source.statuses.SystemHack = nil
			push(events, "StatusEnd", { side = source.team, slot = source.slot, status = "SystemHack", statusName = "System Hack", round = session.round })
		end
		push(events, "Attack", { side = source.team, slot = source.slot,
			targetSide = target.team, targetSlot = target.slot, cardName = source.name,
			targetName = target.name, extra = attackIndex > 1, attackId = attack.id, hitCount = attack.hitCount })
		local defence = BattleRuntime.FireTrigger(session, target, "OnAttacked", { attacker = source, attack = attack }, events)
		local routes = redirectDazedAttack(session, source, events, defence.cancelled)
		local dodgeChance = statusTotal(target, "Dodge", "potency")
		local dodged = not defence.cancelled and not routes and dodgeChance > 0
			and session.rng:NextNumber() <= dodgeChance
		local cancelled = defence.cancelled or dodged
		if cancelled then
			push(events, "Cancel", { side = target.team, slot = target.slot, cardName = target.name, dodged = dodged or nil })
		end
		if not routes then
			routes = cancelled and {} or { { target = target, source = source, share = 1 } }
		end
		for _, route in ipairs(attack.reflections) do table.insert(routes, route) end
		local function finishAttack()
			if attack.finished then return end
			attack.finished = true
			-- Preserve unblocked-attack semantics; redirected volleys are attacks too.
			if not cancelled and attack.hitsResolved > 0 then
				BattleRuntime.FireTrigger(session, source, "OnAttack", { damageDealt = attack.damageDealt, attack = attack }, events)
			end
			-- One resolved attack, including a block/dodge; multi-hit attacks count once.
			BattleRuntime.FireTrigger(session, source, "OnAttackResolved", { damageDealt = attack.damageDealt, attack = attack }, events)
		end
		for hitIndex = 1, attack.hitCount do
			if #routes == 0 or not source.alive or not target.alive or activeOf(session, enemyTeamOf(source.team)) ~= target then break end
			local crit = session.rng:NextNumber() <= (GameConfig.BaseCritChance + statusTotal(source, "CritUp", "potency"))
			local hit = AttackContext.hit(attack, hitIndex,
				source.dmg * damageMultiplier(source) * (attack.damageMultiplier or 1) * (crit and GameConfig.CritMultiplier or 1), crit)
			attack.hitsResolved += 1
			if attack.hitCount > 1 then
				push(events, "Hit", { side = source.team, slot = source.slot, targetSide = target.team,
					targetSlot = target.slot, attackId = attack.id, hitIndex = hitIndex, hitCount = attack.hitCount })
			end
			for _, route in ipairs(routes) do
				local victim = route.target
				if not victim.alive then continue end
				local tag = route.tag or (crit and "crit" or "basic")
				local dealt = dealDamage(session, route.source, victim, AttackContext.amount(hit, route.share), tag, events, hit)
				attack.damageDealt += dealt
				if dealt > 0 then
					BattleRuntime.FireTrigger(session, victim, "OnDamage", { damageTaken = dealt, tag = tag, attack = attack, hit = hit }, events)
				end
			end
			-- OnAttack precedes final-hit death as before. Earlier lethal hits resolve
			-- immediately (including death saves), so later bullets cannot hit a corpse.
			if hitIndex == attack.hitCount then finishAttack() end
			for _, route in ipairs(routes) do
				local victim = route.target
				local wasAlive = victim.alive
				checkDeath(session, victim, events)
				if wasAlive and not victim.alive and victim.team ~= source.team and not route.tag then
					session.victim = victim
					BattleRuntime.FireTrigger(session, source, "OnKill", { attack = attack, hit = hit }, events)
					session.victim = nil
				end
			end
			checkDeath(session, source, events)
		end
		finishAttack()
		checkDeath(session, source, events)
	end
end

local function tickStatuses(session, events)
	for _, team in ipairs({ "player", "enemy" }) do
		local side = sideOf(session, team)
		for _, card in ipairs(side.cards) do
			if card.alive then
				local ids = {}
				for statusId in pairs(card.statuses) do
					table.insert(ids, statusId)
				end
				table.sort(ids)

				for _, statusId in ipairs(ids) do
					local state = card.statuses[statusId]
					local def = state and StatusEffects.get(statusId)
					if state and def then
						if def.tick == "TurnEnd" and (state.potency or 0) > 0 and (state.sourceDmg or 0) > 0 then
							local dot = math.max(1, math.floor(state.sourceDmg * state.potency * (state.stacks or 1)))
							if dot > 0 then
								card.hp -= dot
								BattleRuntime.FireTrigger(session, card, "OnHealthChanged", {}, events)
								push(events, "Damage", {
									side = card.team,
									slot = card.slot,
									amount = dot,
									hp = math.max(0, card.hp),
									maxHP = card.maxHP,
									tag = "dot",
									status = statusId,
									sourceName = statusId,
									targetName = card.name,
								})
							end
						end

						if not def.skipsTurn and (state.duration or 0) > 0 then
							state.duration -= 1
							if state.duration <= 0 then
								card.statuses[statusId] = nil
								push(events, "StatusEnd", {
									side = card.team,
									slot = card.slot,
									status = statusId,
									statusName = def.display or statusId,
									round = session.round,
								})
								-- A DmgUp falling off drops the card's output back down,
								-- so the face has to follow it back down too.
								pushStat(card, events)
							end
						end
					end
				end

				checkDeath(session, card, events)
			end
		end
	end
end

function BattleRuntime.RunCombatRound(session, events)
	local playerActive = session.player.active
	local enemyActive = session.enemy.active
	if not playerActive or not enemyActive then
		return
	end

	-- Future passives can use this without changing the runtime.
	BattleRuntime.FireTrigger(session, playerActive, "OnRoundStart", { round = session.round }, events)
	BattleRuntime.FireTrigger(session, enemyActive, "OnRoundStart", { round = session.round }, events)

	if session.player.active ~= playerActive or session.enemy.active ~= enemyActive then return end
	local firstTeam, reason = TurnOrder.beginRound(session, playerActive, enemyActive)
	push(events, "TurnOrder", { firstTeam = firstTeam, reason = reason, round = session.round })
	local first = firstTeam == "player" and playerActive or enemyActive
	local second = firstTeam == "player" and enemyActive or playerActive
	-- Freeze the pair for this round. A replacement acts in the next round.
	performAttack(session, first, events)
	if first.alive and second.alive
		and sideOf(session, first.team).active == first
		and sideOf(session, second.team).active == second then
		performAttack(session, second, events)
	end

	-- Future abilities can use OnRoundEnd without changing BattleService.
	BattleRuntime.FireTrigger(session, session.player.active, "OnRoundEnd", { round = session.round }, events)
	BattleRuntime.FireTrigger(session, session.enemy.active, "OnRoundEnd", { round = session.round }, events)
	tickStatuses(session, events)
end

return BattleRuntime



