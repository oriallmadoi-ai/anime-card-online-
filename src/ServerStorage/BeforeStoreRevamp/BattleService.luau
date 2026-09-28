--!strict
-- Server-authoritative interactive Test Enemy battle service.
-- Add this to ServerScriptService.Server.Services; the existing Bootstrap will
-- discover it automatically. It does NOT save or rewrite player data.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardDefinitions = require(ReplicatedStorage.Shared.Config.CardDefinitions)
local SupportDefinitions = require(ReplicatedStorage.Shared.Config.SupportDefinitions)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
local LocationDefinitions = require(ReplicatedStorage.Shared.Config.LocationDefinitions)
local EncounterModes = require(ReplicatedStorage.Shared.Config.EncounterModes)
local MountDefinitions = require(ReplicatedStorage.Shared.Config.MountDefinitions)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local BattleRuntime = require(ReplicatedStorage.Shared.Combat.BattleRuntime)
local TurnOrder = require(ReplicatedStorage.Shared.Combat.TurnOrder)
local LocationRuntime = require(ReplicatedStorage.Shared.Combat.LocationRuntime)
local BattleRemotes = require(ReplicatedStorage.Shared.Net.BattleRemotes)

local BattleService = {}
BattleService.Name = "BattleService"

local sessions: { [Player]: any } = {}

local TEST_ENEMY = {
	Name = "Test Enemy",
	PlayDelayMin = 0.6,
	PlayDelayMax = 1.2,
	BetweenRounds = 0.55,
	EnemyLevel = 0,
	SupportChance = 0.65,

	-- Easy to tune later. All ids are REAL VariantConfig ids.
	VariantWeights = {
		{ id = "Standard", weight = 82 },
		{ id = "Gilded", weight = 13 },
		{ id = "Astral", weight = 4 },
		{ id = "Transcendent", weight = 1 },
	},
}

-- The physical Arlong Park NPC route. The server owns this whitelist so an
-- exploiter cannot ask StartEncounter to construct an arbitrary card.
local ENCOUNTER_CARDS = {
	Usopp = true,
	Nami = true,
	Duffy = true,
	Zoro = true,
	Sanji = true,
	Arlong = true,
}

local EVENT_DELAY = {
	RoundStart = 0.35,
	TurnOrder = 0.15,
	LocationActivate = 0.55,
	Attack = 0.46,
	Damage = 0.22,
	Heal = 0.20,
	Passive = 0.20,
	Status = 0.15,
	StatusEnd = 0.08,
	-- A pure number refresh on a card face. It rides along with the event that
	-- caused it, so it must not add a beat of its own to the replay.
	Stat = 0,
	Modifier = 0.08,
	Summon = 0.12,
	Shield = 0.18,
	Cancel = 0.25,
	Skip = 0.35,
	Death = 0.55,
	Revive = 0.45,
	Enter = 0.15,
}

local function pickWeightedVariant(rng: Random): string
	local total = 0
	for _, item in ipairs(TEST_ENEMY.VariantWeights) do
		total += item.weight
	end

	local roll = rng:NextNumber(0, total)
	local cursor = 0
	for _, item in ipairs(TEST_ENEMY.VariantWeights) do
		cursor += item.weight
		if roll <= cursor and VariantConfig.Data[item.id] then
			return item.id
		end
	end
	return "Standard"
end

local function shuffledCopy(list, rng: Random)
	local out = table.clone(list)
	for i = #out, 2, -1 do
		local j = rng:NextInteger(1, i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end

local function allSupportIds()
	local out = {}
	for id in pairs(SupportDefinitions.Data) do
		table.insert(out, id)
	end
	table.sort(out)
	return out
end

function BattleService:_snapshot(session)
	local location = LocationDefinitions.get(session.locationId)
	local firstTeam, initiativeReason = TurnOrder.peek(session, session.player.active, session.enemy.active)
	return {
		battleId = session.id,
		active = not session.ended,
		round = session.round,
		firstTeam = firstTeam,
		initiativeReason = initiativeReason,
		enemyName = session.enemyName or TEST_ENEMY.Name,
		location = location and {
			id = location.id,
			name = location.Name,
			description = location.Description,
			borderTheme = location.BorderTheme,
		} or nil,
		player = BattleRuntime.SnapshotSide(session.player),
		-- The enemy's bench is hidden information, so it is redacted before it
		-- is ever sent rather than hidden by the client after arrival.
		enemy = BattleRuntime.SnapshotSide(session.enemy, true),
	}
end

function BattleService:_fireState(player: Player, session)
	if sessions[player] == session and player.Parent then
		BattleRemotes.State:FireClient(player, self:_snapshot(session))
	end
end

function BattleService:_logEvent(event)
	if event.type == "RoundStart" then
		print(("[Round] Round %d started"):format(event.round))
	elseif event.type == "LocationActivate" then
		print(("[Location] %s activated"):format(event.locationName or "Location"))
	elseif event.type == "Damage" then
		if event.tag == "location" then
			print(("[Combat] %s lost %d HP from the location"):format(event.targetName or "Card", event.amount or 0))
		elseif event.sourceName then
			print(("[Combat] %s dealt %d damage to %s"):format(event.sourceName, event.amount or 0, event.targetName or "target"))
		end
	elseif event.type == "Passive" then
		print(("[Ability] %s triggered %s"):format(event.cardName or "Card", event.passiveName or event.passive or "ability"))
	elseif event.type == "Death" then
		print(("[Combat] %s defeated"):format(event.cardName or "Card"))
	end
end

function BattleService:_replayEvents(player: Player, session, events)
	for _, event in ipairs(events) do
		if sessions[player] ~= session or session.ended or not player.Parent then
			return false
		end
		self:_logEvent(event)
		BattleRemotes.Event:FireClient(player, event)
		task.wait(EVENT_DELAY[event.type] or 0.12)
	end
	return true
end

function BattleService:_buildPlayerSide(player: Player)
	local deck = self.Services.DeckService:BuildCombatDeck(player)
	if not deck then
		return nil, "your profile/deck is not ready yet"
	end

	-- Skill tree battle bonuses, read ONCE per battle rather than per card: the
	-- ranks cannot change mid-fight, and GetStat folds the whole tree each call.
	local skills = self.Services.SkillTreeService
	local dmgMultiplier = skills and skills:GetStat(player, "damageMultiplier") or 1
	local hpMultiplier = skills and skills:GetStat(player, "hpMultiplier") or 1
	local critBonus = skills and skills:GetStat(player, "critBonus") or 0

	local side = { cards = {}, active = nil }
	for slot = 1, GameConfig.AttackSlots do
		local attackEntry = deck.attack[slot]
		if attackEntry then
			local card = BattleRuntime.CreateCard("player", slot, attackEntry, deck.support[slot])
			if card then
				-- Applied AFTER CreateCard rather than inside it, so BattleRuntime stays
				-- a pure combat module with no knowledge of players or profiles - it is
				-- used by the enemy side and the offline simulator too.
				--
				-- baseDmg/baseMaxHP move with the live values on purpose: abilities that
				-- read "base damage" should see the buffed card as its own baseline,
				-- not the printed stat the skill tree just raised.
				if dmgMultiplier ~= 1 then
					card.dmg = math.max(1, math.floor(card.dmg * dmgMultiplier))
					card.baseDmg = card.dmg
				end
				if hpMultiplier ~= 1 then
					card.maxHP = math.max(1, math.floor(card.maxHP * hpMultiplier))
					card.baseMaxHP = card.maxHP
					card.hp = card.maxHP
				end
				-- Crit rides the existing CritUp status rather than a new field, because
				-- BattleRuntime already sums CritUp into every attack roll. duration 0
				-- means it never ticks down, so it lasts the whole battle.
				if critBonus > 0 then
					card.statuses.CritUp = {
						stacks = 1, duration = 0, initialDuration = 0,
						potency = critBonus, sourceDmg = 0,
					}
				end
				table.insert(side.cards, card)
			end
		end
	end

	if #side.cards == 0 then
		return nil, "your active deck has no Attack cards. Equip at least one Attack card first."
	end

	return side, nil
end

function BattleService:_buildEnemySide(rng: Random, encounterCardId: string?, difficulty: string?)
	local side = { cards = {}, active = nil }

	-- NPC encounters field a fixed, authored lineup rather than a random draw, so
	-- the card on the plaza is always the card you meet on the board.
	--
	-- THE LINEUP IS DERIVED HERE, NOT SENT UP. The client posts a difficulty NAME
	-- and nothing else; who actually shows up is read from EncounterModes on the
	-- server. The worst a tampered client can ask for is a harder fight than it
	-- displayed, and supports are never attached - an encounter is the enemy card
	-- and its stat multiplier, nothing hidden.
	if encounterCardId then
		local lineup = EncounterModes.lineup(encounterCardId, difficulty)
		local multiplier = EncounterModes.statMultiplier(difficulty)

		for slot, cardId in ipairs(lineup) do
			local card = BattleRuntime.CreateCard("enemy", slot, {
				cardId = cardId,
				variant = "Standard",
				level = 0,
			}, nil)
			if card then
				if multiplier > 1 then
					-- Same shape as the player's skill-tree multipliers below: the base
					-- fields move WITH the live ones, so an ability that reads "base
					-- damage" treats the scaled card as its own baseline instead of
					-- quietly reverting to the printed stat.
					card.dmg = math.max(1, math.floor(card.dmg * multiplier))
					card.baseDmg = card.dmg
					card.maxHP = math.max(1, math.floor(card.maxHP * multiplier))
					card.baseMaxHP = card.maxHP
					card.hp = card.maxHP
				end
				table.insert(side.cards, card)
			end
		end
		return side
	end

	local attackIds = shuffledCopy(CardDefinitions.RarestFirst, rng)
	local supportIds = shuffledCopy(allSupportIds(), rng)
	local count = math.min(GameConfig.AttackSlots, #attackIds)

	for slot = 1, count do
		local supportEntry = nil
		if #supportIds > 0 and rng:NextNumber() <= TEST_ENEMY.SupportChance then
			local supportId = supportIds[((slot - 1) % #supportIds) + 1]
			supportEntry = {
				cardId = supportId,
				variant = "Standard",
				level = TEST_ENEMY.EnemyLevel,
			}
		end

		local entry = {
			cardId = attackIds[slot],
			variant = pickWeightedVariant(rng),
			level = TEST_ENEMY.EnemyLevel,
		}

		local card = BattleRuntime.CreateCard("enemy", slot, entry, supportEntry)
		if card then
			table.insert(side.cards, card)
		end
	end

	return side
end

function BattleService:_finish(player: Player, session, playerWon: boolean, reason: string?)
	if sessions[player] ~= session or session.ended then
		return
	end
	session.ended = true

	-- Elder Coins are paid for WINNING, not per enemy defeated, so a loss pays
	-- nothing however far it got. Awarded here rather than on each Death event
	-- because this is the single place a battle is decided - both the win and the
	-- draw path pass through it, and only one of them should pay.
	local coins = 0
	if playerWon and not session.encounterId then
		local skills = self.Services.SkillTreeService
		if skills then
			coins = skills:GrantCoins(player, GameConfig.ElderCoinsPerVictory, "victory")
		end
	end

	-- Rewards travel as a LIST, not as a single number, so the results panel can
	-- render one tile per thing earned and more reward types can be added later
	-- without touching the client. `variant` names a VariantConfig tier, which is
	-- what gives the tile its border - Elder Coins are Cosmic, a tier that exists
	-- only for them and the Cosmic difficulty stage.
	local rewards = {}
	if coins > 0 then
		table.insert(rewards, {
			kind = "ElderCoins",
			name = "Elder Coin",
			amount = coins,
			-- Cosmic everywhere, so the currency looks the same however it was won.
			variant = "Cosmic",
			glyph = "\u{25C9}",
		})
	end

	-- Encounter progress, and any card this clear just made rollable.
	--
	-- The previous best is read BEFORE recording, so a player who skips straight
	-- to Impossible collects the Easy unlock and the Impossible one in the same
	-- results screen instead of silently losing the card they walked past.
	-- Re-farming a stage announces nothing, because every unlock it could grant
	-- is already at or below the old high-water mark.
	--
	-- WRAPPED IN pcall ON PURPOSE, and this is the important part.
	--
	-- Everything below is BOOKKEEPING. The line that actually ends the battle -
	-- the BattleEnd event - is further down, and the client will not close its
	-- board until it arrives. So an error thrown while working out rewards would
	-- not just lose the reward: it would abort this function, never fire
	-- BattleEnd, and leave the player staring at a finished battle they cannot
	-- exit or restart, because the client refuses a new fight while its board is
	-- still up. A soft-lock caused by a cosmetic reward tile.
	--
	-- Progress bookkeeping must never be able to hold the battle hostage.
	-- Read by the victory banner's stage chip ("FIRST CLEAR - HARD").
	local firstClear = false
	if playerWon and session.encounterId then
		local ok, err = pcall(function()
			local data = self.Services.DataService
			local rank = EncounterModes.rank(session.difficulty)
			local clears = data:GetEncounterClears(player) or {}
			local previous = clears[session.encounterId] or 0

			-- FIRST TIME is decided by whether this stage has ever been cleared,
			-- which is exactly "is this rank above the high-water mark". Reading it
			-- here, before the clear is recorded, is what stops the first win from
			-- being mistaken for a repeat.
			local firstTime = rank > previous
			firstClear = firstTime
			local payout = EncounterModes.coins(session.encounterId, session.difficulty, firstTime)
			local skills = self.Services.SkillTreeService
			local paid = skills and skills:GrantCoins(player, payout,
				firstTime and "encounter_first" or "encounter_repeat") or 0

			if paid > 0 then
				table.insert(rewards, {
					kind = "ElderCoins",
					name = "Elder Coin",
					amount = paid,
					-- Cosmic, not Secret: the currency gets its own identity rather
					-- than wearing a card tier's border.
					variant = "Cosmic",
					glyph = "\u{25C9}",
					firstTime = firstTime,
				})
			end

			-- Summon Cores and Card Forge materials, paid on EVERY win of a stage
			-- that has drops (SummonCoreConfig.EncounterDrops - Pirate Shark today),
			-- first clear included. In its own pcall so a drop problem can never
			-- cost the player the clear being recorded just below.
			local cores = self.Services.SummonCoreService
			if cores then
				local dropped, tiles = pcall(function()
					return cores:GrantEncounterDrops(player, session.encounterId, session.difficulty)
				end)
				if dropped and type(tiles) == "table" then
					for _, tile in ipairs(tiles) do
						table.insert(rewards, tile)
					end
				elseif not dropped then
					warn(("[Battle] forge drops failed for %s: %s"):format(player.Name, tostring(tiles)))
				end
			end

			if data:RecordEncounterClear(player, session.encounterId, rank) then
				for cardId, req in pairs(EncounterModes.Unlocks) do
					local need = EncounterModes.rank(req.difficulty)
					if req.encounter == session.encounterId and need > previous and need <= rank then
						local def = CardDefinitions.get(cardId) or SupportDefinitions.get(cardId)
						table.insert(rewards, {
							kind = "CardUnlock",
							name = def and def.name or cardId,
							amount = 1,
							-- Standard: an unlock announces the CARD, and a border it
							-- has not been rolled in yet would promise something the
							-- unlock does not deliver.
							variant = "Standard",
							icon = def and def.art or nil,
							unlockLabel = "UNLOCK ROLL",
						})
						print(("[Battle] %s unlocked %s for rolling"):format(player.Name, cardId))
					end
				end

				-- Mounts are earned by the same clears, through the same gate. Only
				-- stages CROSSED by this win hand anything over, which is why the
				-- grant is inside RecordEncounterClear's success branch alongside the
				-- card unlocks: beating a stage you had already beaten pays coins and
				-- nothing else.
				local mounts = self.Services.MountService
				if mounts then
					for _, mountId in ipairs(MountDefinitions.Order) do
						local req = MountDefinitions.requirement(mountId)
						local need = req and EncounterModes.rank(req.difficulty) or nil
						if req and req.encounter == session.encounterId
							and need > previous and need <= rank then
							local granted = mounts:Grant(player, mountId)
							if granted then
								local def = MountDefinitions.get(mountId)
								table.insert(rewards, {
									kind = "MountUnlock",
									name = def and def.name or mountId,
									amount = 1,
									variant = "Transcendent",
									icon = (def and def.icon ~= "") and def.icon or nil,
									glyph = "\u{25C9}",
									unlockLabel = "MOUNT UNLOCKED",
								})
								print(("[Battle] %s unlocked the %s mount"):format(player.Name, mountId))
							end
						end
					end
				end
				-- The panel reads unlock state from the replicated profile, so push
				-- it now rather than waiting for the next incidental sync.
				pcall(function() self.Services.DataService:Sync(player) end)
			end
		end)
		if not ok then
			warn(("[Battle] encounter progress failed for %s on %s/%s: %s")
				:format(player.Name, tostring(session.encounterId),
					tostring(session.difficulty), tostring(err)))
		end
	end

	BattleRemotes.Event:FireClient(player, {
		type = "BattleEnd",
		won = playerWon,
		reason = reason,
		elderCoins = coins > 0 and coins or nil,
		rewards = rewards,
		difficulty = session.encounterId and session.difficulty or nil,
		firstClear = firstClear or nil,
	})
	print(("[Battle] Battle ended for %s - %s"):format(player.Name, playerWon and "VICTORY" or "DEFEAT"))

	-- Release the slot. `ended` alone was enough for _startTest, but leaving the
	-- finished session in the table means every later "are you busy" question is
	-- answered by a fight that is already over. Clearing it makes a stale session
	-- structurally impossible rather than merely harmless.
	if sessions[player] == session then
		sessions[player] = nil
	end
end

function BattleService:_checkEnd(player: Player, session): boolean
	local playerRemaining = BattleRuntime.HasRemaining(session.player)
	local enemyRemaining = BattleRuntime.HasRemaining(session.enemy)

	if not playerRemaining and not enemyRemaining then
		self:_finish(player, session, false, "draw")
		return true
	elseif not enemyRemaining then
		self:_finish(player, session, true)
		return true
	elseif not playerRemaining then
		self:_finish(player, session, false)
		return true
	end

	return false
end

function BattleService:_scheduleEnemyPlay(player: Player, session)
	if session.enemyPlayPending or session.enemy.active or session.ended then
		return
	end
	session.enemyPlayPending = true

	task.spawn(function()
		local delayTime = session.rng:NextNumber(TEST_ENEMY.PlayDelayMin, TEST_ENEMY.PlayDelayMax)
		task.wait(delayTime)

		if sessions[player] ~= session or session.ended or session.enemy.active then
			session.enemyPlayPending = false
			return
		end

		local available = {}
		for _, card in ipairs(session.enemy.cards) do
			if card.alive and card.state == "hand" then
				table.insert(available, card)
			end
		end

		if #available == 0 then
			session.enemyPlayPending = false
			self:_checkEnd(player, session)
			return
		end

		local chosen = available[session.rng:NextInteger(1, #available)]
		local events = {}
		local ok = BattleRuntime.PlayCard(session, "enemy", chosen.slot, events)
		session.enemyPlayPending = false
		if not ok then
			return
		end

		print(("[Battle] %s played %s"):format(session.enemyName or TEST_ENEMY.Name, chosen.name))
		BattleRemotes.Event:FireClient(player, {
			type = "EnemyPlay",
			side = "enemy",
			slot = chosen.slot,
			card = BattleRuntime.SnapshotCard(chosen),
		})
		task.wait(0.38)

		-- Enter/passive events are replayed after the visual placement finishes.
		for _, event in ipairs(events) do
			if event.type ~= "Enter" then
				if sessions[player] ~= session or session.ended then
					return
				end
				self:_logEvent(event)
				BattleRemotes.Event:FireClient(player, event)
				task.wait(EVENT_DELAY[event.type] or 0.12)
			end
		end

		self:_fireState(player, session)
		self:_checkEnd(player, session)
		self:_ensureRoundLoop(player, session)
	end)
end

function BattleService:_ensureRoundLoop(player: Player, session)
	if session.roundLoopRunning or session.ended then
		return
	end
	if not session.player.active or not session.enemy.active then
		return
	end

	session.roundLoopRunning = true
	task.spawn(function()
		while sessions[player] == session and not session.ended do
			if not session.player.active or not session.enemy.active then
				break
			end

			local firstTeam, initiativeReason = TurnOrder.peek(session, session.player.active, session.enemy.active)
			local events = {
				{ type = "RoundStart", round = session.round, firstTeam = firstTeam, initiativeReason = initiativeReason },
			}

			LocationRuntime.Apply(session, "RoundStart", events)

			-- If the location did not remove an active card, normal combat continues.
			if session.player.active and session.enemy.active then
				BattleRuntime.RunCombatRound(session, events)
			end

			local replayed = self:_replayEvents(player, session, events)
			if not replayed or sessions[player] ~= session or session.ended then
				break
			end

			if self:_checkEnd(player, session) then
				break
			end

			-- The round has completed. The next actual combat exchange is the next round.
			session.round += 1
			self:_fireState(player, session)

			if not session.player.active then
				-- Player must choose the replacement manually.
				break
			end

			if not session.enemy.active then
				self:_scheduleEnemyPlay(player, session)
				break
			end

			task.wait(TEST_ENEMY.BetweenRounds)
		end

		session.roundLoopRunning = false
	end)
end

function BattleService:_startTest(player: Player, encounterCardId: string?, difficulty: string?)
	if encounterCardId then
		if not ENCOUNTER_CARDS[encounterCardId] then
			return false, "unknown Arlong Park encounter", nil
		end
		-- Stages are NOT gated behind one another on purpose: a confident player
		-- may walk straight up to Cosmic. The gate in this feature is on the reward
		-- (you must clear Easy to unlock the card), not on the attempt.
		if not EncounterModes.exists(difficulty) then
			return false, "unknown difficulty", nil
		end
	end


	local current = sessions[player]
	if current and not current.ended then
		return false, "you are already in a battle", nil
	end

	local profile = self.Services.DataService:Await(player, 10)
	if not profile then
		return false, "your save did not finish loading", nil
	end

	-- Stage order is enforced HERE, not just greyed out in the panel. The client
	-- sends a stage NAME, so without this a tampered client could post "Cosmic"
	-- on a fresh save and claim every unlock in a single fight.
	--
	-- Deliberately after the Await: reading progress from a profile that has not
	-- finished loading would report zero clears and lock a returning player out
	-- of stages they had already earned.
	if encounterCardId then
		if not EncounterModes.isStageUnlocked(encounterCardId, difficulty, profile.encounters) then
			local previous = EncounterModes.previousStage(difficulty)
			return false, ("beat %s on %s first"):format(
				CardDefinitions.get(encounterCardId).name,
				EncounterModes.get(previous).display), nil
		end
	end

	local playerSide, reason = self:_buildPlayerSide(player)
	if not playerSide then
		return false, reason, nil
	end

	local seed = math.floor(os.clock() * 1000000) % 2147483647
	local rng = Random.new(seed)
	local session = {
		id = tostring(player.UserId) .. "-" .. tostring(seed),
		rng = rng,
		round = 1,
		initiativeTeam = "player",
		locationId = "GreenPlanet",
		locationFired = {},
		player = playerSide,
		enemy = self:_buildEnemySide(rng, encounterCardId, difficulty),
		enemyName = encounterCardId and (CardDefinitions.get(encounterCardId).name) or TEST_ENEMY.Name,
		encounterId = encounterCardId,
		difficulty = encounterCardId and difficulty or nil,
		ended = false,
		roundLoopRunning = false,
		enemyPlayPending = false,
	}

	sessions[player] = session
	print(("[Battle] Battle started for %s"):format(player.Name))

	self:_scheduleEnemyPlay(player, session)
	return true, nil, self:_snapshot(session)
end

-- Additive read-only accessor. `sessions` is a file-local upvalue, so other
-- services cannot see it without this. Does not change any battle behaviour.
-- Its original caller was RocketService, which asked before letting a player
-- launch mid-fight; that system is gone, but any feature that needs to gate
-- itself on "is this player in a battle right now" should use this.
function BattleService:IsInBattle(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and not session.ended
end

function BattleService:_playPlayerCard(player: Player, slot: number)
	local session = sessions[player]
	if not session or session.ended then
		return false, "there is no active battle", nil
	end
	if session.roundLoopRunning then
		return false, "wait for the current round to finish", nil
	end
	if typeof(slot) ~= "number" or slot % 1 ~= 0 then
		return false, "invalid card slot", nil
	end

	local events = {}
	local ok, reason = BattleRuntime.PlayCard(session, "player", slot, events)
	if not ok then
		return false, reason, nil
	end

	local card = session.player.active
	print(("[Battle] Player played %s"):format(card and card.name or "card"))
	local snapshot = self:_snapshot(session)

	-- Let the client finish its drag-to-slot tween before ability VFX arrive.
	task.spawn(function()
		task.wait(0.34)
		if sessions[player] ~= session or session.ended then
			return
		end
		for _, event in ipairs(events) do
			if event.type ~= "Enter" then
				self:_logEvent(event)
				BattleRemotes.Event:FireClient(player, event)
				task.wait(EVENT_DELAY[event.type] or 0.12)
			end
		end
		self:_fireState(player, session)
		if not self:_checkEnd(player, session) then
			if not session.enemy.active then
				self:_scheduleEnemyPlay(player, session)
			end
			self:_ensureRoundLoop(player, session)
		end
	end)

	return true, nil, snapshot
end

function BattleService:_forfeit(player: Player)
	local session = sessions[player]
	if session then
		session.ended = true
		sessions[player] = nil
		print(("[Battle] %s left the test battle"):format(player.Name))
	end
	return true, nil, nil
end

function BattleService:Init()
	BattleRemotes.Action.OnServerInvoke = function(player: Player, action: string, payload)
		if action == "StartTest" then
			return self:_startTest(player)
		elseif action == "StartEncounter" then
			local cardId = typeof(payload) == "table" and payload.cardId or nil
			local difficulty = typeof(payload) == "table" and payload.difficulty or nil
			return self:_startTest(player, cardId, difficulty)
		elseif action == "PlayCard" then
			local slot = typeof(payload) == "table" and payload.slot or payload
			return self:_playPlayerCard(player, slot)
		elseif action == "Forfeit" then
			return self:_forfeit(player)
		end
		return false, "unknown battle action", nil
	end
end

function BattleService:Start()
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)
	print("[BattleService] online")
end

return BattleService
