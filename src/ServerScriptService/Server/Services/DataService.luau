--!strict
-- Owns the player profile: load, cache, save, release, replicate.
--
-- Storage is session-locked and goes through UpdateAsync, so two servers can
-- never hold the same profile and a save can never blindly overwrite newer
-- data. The backend stays isolated behind claim/commit if we later swap in
-- ProfileStore.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local CardStats = require(ReplicatedStorage.Shared.Util.CardStats)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local STORE_NAME = "PlayerProfile_v1"

local DataService = {}
DataService.Name = "DataService"

local store = DataStoreService:GetDataStore(STORE_NAME)
local profiles: { [Player]: any } = {}

-- The shape of a brand new save. Every field added later needs a migration.
local function defaultProfile()
	return {
		version = GameConfig.SaveSchemaVersion,

		-- Keyed "cardId|Border" -> { count, level }
		-- Copies stack, so a player with 400k rolls has hundreds of entries,
		-- not hundreds of thousands. This is what keeps us under the 4MB cap.
		cards = {},

		-- Eight lineups the player can swap between; `active` is the one being
		-- edited and the one combat uses.
		decks = { active = 1, presets = {} },

		stats = {
			totalRolls = 0,
			rollsSincePity = 0,
			playtime = 0,
			joinCount = 0,
		},

		currency = {
			gems = 0,
			gold = 0,
			essence = 0,       -- spent to level cards, earned from battles
			raidTokens = 0,
			-- Elder Coins: the skill tree's only currency, earned from battle wins.
			elderCoins = 0,
		},

		-- Skill tree ranks, as a flat { skillId = rank } map.
		skills = {},

		-- Exact Elder Coins actually spent on the tree. This is authoritative for
		-- RESET refunds. We intentionally store the spend total because skill costs
		-- can be rebalanced later; recomputing a refund from today's prices would
		-- either duplicate or delete coins for players who bought ranks earlier.
		skillTreeSpent = 0,

		-- DERIVED, NOT AUTHORITATIVE.
		--
		-- SkillTreeService recomputes this from `skills` on join and after every
		-- purchase. It survives only because RollService and UIController already
		-- read it, so recomputing into it means the skill tree drives roll luck and
		-- roll speed without either of those files changing at all. Never write to
		-- it from anywhere else: the next recompute would overwrite you.
		upgrades = { luck = 0, rollSpeed = 0, damage = 0 },

		-- Magic Books: bookId -> count. The only source of card levels.
		books = {},
		items = {},

		-- Arlong Park progress: encounterId -> the HIGHEST difficulty rank ever
		-- cleared (1 Easy .. 5 Cosmic). One number rather than a set of flags,
		-- because the stages are strictly ordered: clearing Cosmic implies Easy, and
		-- every unlock question is "is your best at least N".
		--
		-- This is what gates the roll pool. See EncounterModes.Unlocks.
		encounters = {},

		-- Mounts: mountId -> true for every one owned, and the id of the one the
		-- player currently has equipped (nil for none). Ownership is earned from
		-- the encounter clears above, so this is derived state that is still
		-- stored rather than recomputed - a mount must survive its unlock
		-- requirement being retuned later.
		mounts = {},
		equippedMount = nil,

		-- Summon Cores: stageId -> count ("Basic1" .. "Cosmic5", see
		-- SummonCoreConfig). Items, not cards: upgraded at the Card Forge and
		-- consumed when opened for a card. Only SummonCoreService writes here.
		summonCores = {},

		-- Card Forge materials: itemId -> count ("CoreEssenceBasic",
		-- "ElderWrench", see SummonCoreConfig.Items). Spent to upgrade Summon
		-- Cores, earned from encounter wins. Only SummonCoreService writes here.
		forgeItems = {},

		story = { world = 1, stage = 1, cleared = {} },
		-- sfxVolume / musicVolume (0..1) are written by SettingsService. Older
		-- saves simply lack them and the client reads that as full volume, so
		-- they need no migration.
		settings = { quickRoll = true, autoDelete = {}, sfxVolume = 1, musicVolume = 1 },
	}
end

-- Runs on load. Add a branch per version bump; never silently wipe.
local function migrate(data)
	-- Branches MUST run in ascending order: each one upgrades the save by a
	-- single step, and a later branch assumes the earlier ones already ran.
	if data.version == nil then data.version = 1 end

	if data.version < 2 then
		data.currency = data.currency or {}
		data.stats = data.stats or {}
		data.stats.rollsSincePity = data.stats.rollsSincePity or data.stats.rollsSinceEpic or 0
		data.stats.rollsSinceEpic = nil
		data.version = 2
	end

	if data.version < 3 then
		-- v3: borders became variants and were renamed. Inventory keys are
		-- "cardId|Variant", so every key is rewritten, not just a field.
		-- Entries whose card no longer exists are dropped rather than left as
		-- unopenable ghosts.
		local RENAME = { Basic = "Standard", Gold = "Gilded", Rainbow = "Astral", Secret = "Transcendent" }
		local RS = game:GetService("ReplicatedStorage")
		local CardDefs = require(RS.Shared.Config.CardDefinitions)
		local SupportDefs = require(RS.Shared.Config.SupportDefinitions)

		local migrated = {}
		for key, entry in pairs(data.cards or {}) do
			local cardId, variant = key:match("^(.-)|(.+)$")
			-- Either roster. Checking only CardDefinitions here would silently
			-- delete every support card a player owns.
			if cardId and (CardDefs.get(cardId) or SupportDefs.get(cardId)) then
				migrated[cardId .. "|" .. (RENAME[variant] or variant)] = entry
			end
		end
		data.cards = migrated
		data.stats.rollsSincePity = nil
		data.version = 3
	end

	if data.version < 4 then
		-- v4: levels became 1-based (there is no level 0 any more) and Magic
		-- Books replaced essence as the levelling resource. Existing copies are
		-- lifted to the new floor rather than reset.
		local RS = game:GetService("ReplicatedStorage")
		local CardDefs = require(RS.Shared.Config.CardDefinitions)
		local SupportDefs = require(RS.Shared.Config.SupportDefinitions)

		local kept = {}
		for key, entry in pairs(data.cards or {}) do
			local cardId = key:match("^(.-)|")
			-- The placeholder roster was deleted, so most old entries point at
			-- cards that no longer exist. Drop them instead of rendering blanks.
			-- Supports are checked too, or owning one is the same as owning junk.
			if cardId and (CardDefs.get(cardId) or SupportDefs.get(cardId)) then
				if (entry.level or 0) < 1 then entry.level = 1 end
				kept[key] = entry
			end
		end
		data.cards = kept
		data.books = data.books or {}
		if data.currency then data.currency.essence = nil end
		data.version = 4
	end

	if data.version < 5 then
		-- v5: a single deck became 8 named presets. The existing deck is kept
		-- as preset 1 rather than discarded, so nobody loses their lineup.
		local GameCfg = require(game:GetService("ReplicatedStorage").Shared.Config.GameConfig)
		local previous = data.deck or { attack = {}, support = {} }

		data.decks = { active = 1, presets = {} }
		for i = 1, GameCfg.DeckPresets do
			data.decks.presets[i] = { attack = {}, support = {} }
		end
		data.decks.presets[1] = {
			attack = previous.attack or {},
			support = previous.support or {},
		}
		data.deck = nil
		data.version = 5
	end

	if data.version < 6 then
		-- v6: the level floor moved from 1 to 0. Existing levels came from
		-- debug testing only, so every copy is reset to the new base rather
		-- than shifted - a card nobody levelled should read 0.
		for _, entry in pairs(data.cards or {}) do
			entry.level = 0
		end
		data.version = 6
	end

	if data.version < 7 then
		-- v7: the placeholder support roster was retired, and supports became
		-- Standard-only.
		--
		-- Both clean-ups are needed. Dropping a card from SupportDefinitions does
		-- NOT remove it from anybody's save on its own - the v4 sweep that used to
		-- do that only runs for saves older than v4 - so without this the retired
		-- supports would sit in every inventory forever as unrenderable ghosts.
		local RS7 = game:GetService("ReplicatedStorage")
		local CardDefs7 = require(RS7.Shared.Config.CardDefinitions)
		local SupportDefs7 = require(RS7.Shared.Config.SupportDefinitions)

		local kept = {}
		for key, entry in pairs(data.cards or {}) do
			local cardId = key:match("^(.-)|")
			if cardId then
				if SupportDefs7.get(cardId) then
					-- Collapse every border of a support onto Standard, MERGING counts
					-- so a player who owned Gilded + Basic keeps both copies rather
					-- than having one silently overwrite the other.
					local target = cardId .. "|Standard"
					local existing = kept[target]
					if existing then
						existing.count = (existing.count or 1) + (entry.count or 1)
						existing.level = math.max(existing.level or 0, entry.level or 0)
					else
						kept[target] = { count = entry.count or 1, level = entry.level or 0 }
					end
				elseif CardDefs7.get(cardId) then
					kept[key] = entry
				end
				-- anything in neither roster is a retired card and is dropped
			end
		end
		data.cards = kept

		-- A deck slot pointing at a retired support, or at a support border that no
		-- longer exists, would fail the ownership check forever. Repoint or clear.
		for _, preset in pairs((data.decks or {}).presets or {}) do
			for index, slot in pairs(preset.support or {}) do
				if type(slot) == "table" and slot.cardId then
					if not SupportDefs7.get(slot.cardId) then
						preset.support[index] = nil
					else
						slot.variant = "Standard"
					end
				end
			end
		end

		data.version = 7
	end

	if data.version < 8 then
		-- v8: the skill tree.
		--
		-- Elder Coins join the EXISTING currency table rather than opening a second
		-- home for currencies. That table has been in the save since v2 but nothing
		-- has ever read or written it, so it costs nothing to adopt and keeps every
		-- currency in one place.
		data.currency = data.currency or {}
		data.currency.elderCoins = data.currency.elderCoins or 0
		data.skills = data.skills or {}

		-- `upgrades` becomes a DERIVED cache of the skill ranks above, so whatever
		-- is sitting in it is reset rather than carried forward. Nothing is lost:
		-- the upgrade system it belonged to was never implemented, so every existing
		-- save has zeroes here anyway. SkillTreeService fills it in on join.
		data.upgrades = { luck = 0, rollSpeed = 0, damage = 0 }

		data.version = 8
	end


	if data.version < 9 then
		-- v9: exact skill-tree spend tracking.
		--
		-- RESET used to recompute the refund from the LIVE cost curve. That becomes
		-- unsafe the moment we rebalance costs: somebody who bought a 4-coin rank
		-- could reset after an update and receive hundreds for it. Reconstruct what
		-- v8 players actually paid using the v8 curves ONCE, then every future
		-- purchase adds its exact cost to skillTreeSpent.
		local function legacySteppedTotal(rank: number, maxRank: number, base: number, step: number, per: number): number
			local capped = math.clamp(math.floor(rank or 0), 0, maxRank)
			local total = 0
			for r = 1, capped do
				total += base + math.floor((r - 1) / per) * step
			end
			return total
		end

		local legacy = {
			Awakening      = { max = 1,    fixed = 25 },
			LuckBoost      = { max = 3000, base = 4,  step = 1, per = 25 },
			SwiftHands     = { max = 500,  base = 6,  step = 1, per = 10 },
			IronBody       = { max = 1000, base = 5,  step = 1, per = 15 },
			FortuneFlow    = { max = 750,  base = 12, step = 2, per = 8 },
			CoinAffinity   = { max = 400,  base = 10, step = 2, per = 10 },
			RapidDraw      = { max = 400,  base = 14, step = 2, per = 8 },
			Bloodlust      = { max = 1000, base = 9,  step = 2, per = 12 },
			Windwalker     = { max = 250,  base = 25, step = 5, per = 5 },
			KeenEye        = { max = 300,  base = 20, step = 4, per = 6 },
			ElderAscension = { max = 1,    fixed = 25000 },
		}

		local spent = 0
		for skillId, rawRank in pairs(data.skills or {}) do
			local curve = legacy[skillId]
			local rank = type(rawRank) == "number" and rawRank or 0
			if curve and rank > 0 then
				if curve.fixed then
					spent += math.min(math.floor(rank), curve.max) * curve.fixed
				else
					spent += legacySteppedTotal(rank, curve.max, curve.base, curve.step, curve.per)
				end
			end
		end

		local previousSpent = type(data.skillTreeSpent) == "number" and data.skillTreeSpent or spent
		data.skillTreeSpent = math.max(0, math.floor(previousSpent))
		data.version = 9
	end

	if data.version < 10 then
		-- v10: encounter difficulty stages, and the card unlocks they gate.
		--
		-- EXISTING PLAYERS ARE CREDITED WITH AN EASY CLEAR ON EVERY ENCOUNTER.
		-- Before this version every card was rollable by everybody, so anyone who
		-- has already played owns Duffy, Nami and the rest and reasonably expects to
		-- keep pulling them. Starting them at zero would silently revoke that and
		-- read as data loss rather than as a new feature. Brand new saves begin
		-- empty and earn each unlock properly; this branch only protects the people
		-- who were here first.
		--
		-- Easy specifically, not Cosmic: the card unlocks are restored, but the
		-- harder stages and the Will of D reward are still there to be earned.
		data.encounters = data.encounters or {}

		local played = (data.stats and (data.stats.totalRolls or 0) > 0)
			or next(data.cards or {}) ~= nil
		if played then
			for _, encounterId in ipairs({ "Usopp", "Nami", "Duffy", "Zoro", "Sanji", "Arlong" }) do
				data.encounters[encounterId] = math.max(data.encounters[encounterId] or 0, 1)
			end
		end

		data.version = 10
	end

	if data.version < 11 then
		-- v11: mounts. Nothing is granted retroactively - the Franky Battle Bike
		-- is earned by clearing Pirate Shark on Impossible, and anyone who has
		-- already done that is credited below from their existing clear record
		-- rather than having to beat it again.
		data.mounts = data.mounts or {}
		if (data.encounters and data.encounters.Arlong or 0) >= 4 then
			data.mounts.FrankyBattleBike = true
		end
		data.version = 11
	end

	if data.version < 12 then
		-- v12: Summon Cores. Everyone starts with none; nothing is granted.
		if type(data.summonCores) ~= "table" then data.summonCores = {} end
		data.version = 12
	end

	if data.version < 13 then
		-- v13: Card Forge materials (Elder Core Essence, Elder Wrench). Everyone
		-- starts with none; they drop from Pirate Shark wins from now on.
		if type(data.forgeItems) ~= "table" then data.forgeItems = {} end
		data.version = 13
	end

	return data
end

-- Deck line-ups are kept DENSE - exactly AttackSlots / SupportSlots entries,
-- `false` for an empty slot - because a sparse array does not survive a
-- RemoteEvent or a DataStore write (holes truncate it or turn its keys into
-- strings). DeckService keeps them that way from here on; this repairs a save
-- that was written before it did, BEFORE the first sync carries it to the
-- client. Runs on every load and is a no-op on a save that is already dense.
local function normalizeDecks(data)
	local decks = data.decks
	if type(decks) ~= "table" or type(decks.presets) ~= "table" then return end
	local function densify(list, n: number)
		local out = table.create(n, false)
		if type(list) == "table" then
			for key, slot in pairs(list) do
				local i = tonumber(key)
				if i and i % 1 == 0 and i >= 1 and i <= n and type(slot) == "table"
					and type(slot.cardId) == "string" and type(slot.variant) == "string" then
					out[i] = { cardId = slot.cardId, variant = slot.variant }
				end
			end
		end
		return out
	end
	local presets = decks.presets
	for i = 1, GameConfig.DeckPresets do
		local preset = presets[i] or presets[tostring(i)]
		presets[tostring(i)] = nil
		if type(preset) ~= "table" then preset = {} end
		preset.attack = densify(preset.attack, GameConfig.AttackSlots)
		preset.support = densify(preset.support, GameConfig.SupportSlots)
		presets[i] = preset
	end
end

-- ── storage backend ────────────────────────────────────────
--
-- Two problems with the previous GetAsync/SetAsync pair, both of which cost us
-- real deck data during development:
--
--   1. SetAsync is a blind overwrite. Any save races any other save, and the
--      last writer wins regardless of which held newer data.
--   2. Nothing stopped a second server from loading the same profile. Two
--      sessions editing one inventory is how duplication bugs happen.
--
-- Both are fixed by wrapping the profile in an envelope and going through
-- UpdateAsync, which is atomic read-modify-write:
--
--   { data = <profile>, session = { jobId, placeId, heartbeat } }
--
-- A session claims the key, refreshes its heartbeat while it holds it, and
-- releases on leave. Another server refuses to load a key whose heartbeat is
-- still fresh, and takes it over once it has gone stale - so a crashed server
-- never locks a player out permanently.

local HEARTBEAT_INTERVAL = 30

-- In a live game every server has a unique JobId, so a lock held by another
-- server genuinely belongs to someone else. Studio has no JobId, and generating
-- a fresh id per run meant each restart saw its OWN previous lock as a foreign
-- server and locked itself out for the full stale window. A fixed id lets a
-- Studio restart recognise the lock as its own and reclaim it immediately.
local IN_STUDIO = game:GetService("RunService"):IsStudio()
local sessionId = game.JobId ~= "" and game.JobId or "studio"

-- Studio runs one session at a time, so a short window keeps test restarts
-- snappy without weakening the guarantee in production.
local SESSION_STALE_AFTER = IN_STUDIO and 15 or 90

local function isOurs(session): boolean
	return session ~= nil and session.jobId == sessionId
end

local function isStale(session): boolean
	if not session then return true end
	return (os.time() - (session.heartbeat or 0)) > SESSION_STALE_AFTER
end

-- Accepts profiles written before the envelope existed.
local function unwrap(stored)
	if stored == nil then return nil, nil end
	if stored.data ~= nil or stored.session ~= nil then
		return stored.data, stored.session
	end
	return stored, nil        -- legacy: the raw profile was stored directly
end

local function claim(key: string)
	local claimed, denied = nil, false

	for attempt = 1, 5 do
		local ok, err = pcall(function()
			store:UpdateAsync(key, function(stored)
				local data, session = unwrap(stored)

				-- Someone else is live on this key; back off and retry.
				if session and not isOurs(session) and not isStale(session) then
					denied = true
					return nil        -- abort the write, leave the value alone
				end

				denied = false
				claimed = data
				return {
					data = data,
					session = { jobId = sessionId, placeId = game.PlaceId, heartbeat = os.time() },
				}
			end)
		end)

		if ok and not denied then return true, claimed end
		if ok and denied then
			warn("[DataService] " .. key .. " is locked by another session; retry " .. attempt)
		end
		if not ok then
			warn(("[DataService] claim attempt %d failed: %s"):format(attempt, tostring(err)))
		end
		task.wait(attempt * 2)
	end

	return false, nil
end

-- Writes the profile only if we still hold the session. Refusing to write
-- without the lock is the point: a server that lost the key must not stomp
-- whoever holds it now.
local function commit(key: string, data, releaseLock: boolean)
	for attempt = 1, 4 do
		local lost = false
		local ok, err = pcall(function()
			store:UpdateAsync(key, function(stored)
				local _, session = unwrap(stored)
				-- Only claim() may acquire a lock. A delayed autosave must not
				-- recreate a released lock or take over another server's save.
				-- UpdateAsync can rerun this callback after a write conflict.
				lost = not isOurs(session)
				if lost then
					return nil
				end
				return {
					data = data,
					-- "releaseLock and nil or session" always selected session.
					session = if releaseLock then nil
						else { jobId = sessionId, placeId = game.PlaceId, heartbeat = os.time() },
				}
			end)
		end)

		if ok and lost then
			warn("[DataService] session lock lost; refusing to overwrite newer data")
			return false
		end
		if ok then return true end
		warn(("[DataService] save attempt %d failed: %s"):format(attempt, tostring(err)))
		task.wait(attempt * 2)
	end
	return false
end

local function keyFor(player: Player): string
	return "u_" .. player.UserId
end

function DataService:Get(player: Player)
	return profiles[player]
end

-- Yields until the profile exists, so other services can safely call this
-- during a player's first frame without racing the load.
function DataService:Await(player: Player, timeout: number?)
	local deadline = os.clock() + (timeout or 10)
	while not profiles[player] and os.clock() < deadline do
		if not player.Parent then return nil end
		task.wait(0.1)
	end
	return profiles[player]
end

-- Push the whole profile to the client. Fine at this scale; if inventories get
-- huge we switch to sending deltas rather than the full table.
function DataService:Sync(player: Player)
	local data = profiles[player]
	if data then
		Remotes.ProfileSync:FireClient(player, data)
		self:MarkDirty(player)
	end
end

-- Central place where cards enter the inventory. Rolling, fusing, and rewards
-- all go through here so stacking logic exists exactly once.
function DataService:AddCard(player: Player, cardId: string, variant: string, count: number?)
	local data = profiles[player]
	if not data then return nil end

	-- Supports are Standard-only. Forcing it HERE rather than at each call site is
	-- what makes the rule airtight: this is the single door every card comes
	-- through - rolls, grants, rewards, fusing - so a support can never enter the
	-- inventory wearing a border it should not have.
	if CardStats.isSupport(cardId) then
		variant = "Standard"
	end

	local key = CardStats.key(cardId, variant)
	local entry = data.cards[key]
	if entry then
		entry.count += (count or 1)
	else
		entry = { count = count or 1, level = GameConfig.MinCardLevel }
		data.cards[key] = entry
	end
	return entry
end

-- ── encounter progress ─────────────────────────────────────
--
-- Records a clear and reports whether it was an IMPROVEMENT. Beating a stage
-- you have already beaten returns false, which is what stops the reward popup
-- from announcing the same unlock every time you farm an encounter.
function DataService:RecordEncounterClear(player: Player, encounterId: string, rank: number): boolean
	local data = profiles[player]
	if not data or type(encounterId) ~= "string" or type(rank) ~= "number" then
		return false
	end

	data.encounters = data.encounters or {}
	local best = data.encounters[encounterId] or 0
	if rank <= best then
		return false
	end

	-- Only the high-water mark is kept, so clearing Cosmic after Easy stores 5
	-- and every "have you beaten it at least on N" question is one comparison.
	data.encounters[encounterId] = rank
	self:MarkDirty(player)
	return true
end

function DataService:GetEncounterClears(player: Player)
	local data = profiles[player]
	return data and data.encounters or {}
end

-- Debounced save for meaningful changes.
--
-- Relying on the 120s autosave plus BindToClose is not enough: a shutdown gives
-- the save a very short window, and anything changed since the last autosave
-- can be lost. Equipping a deck or levelling a card is exactly the kind of
-- change a player will be annoyed to redo, so those mark the profile dirty and
-- a write follows a few seconds later. The delay coalesces bursts - swapping
-- four slots in a row costs one DataStore call, not four.
local dirty: { [Player]: boolean } = {}
local SAVE_DEBOUNCE = 4

function DataService:MarkDirty(player: Player)
	if dirty[player] then return end
	dirty[player] = true

	task.delay(SAVE_DEBOUNCE, function()
		dirty[player] = nil
		if player.Parent then
			self:Save(player)
		end
	end)
end

function DataService:Save(player: Player, releaseLock: boolean?)
	local data = profiles[player]
	if not data then return false end
	return commit(keyFor(player), data, releaseLock == true)
end

function DataService:_onJoin(player: Player)
	local ok, stored = claim(keyFor(player))
	if not ok then
		-- Load genuinely failed (not "no data yet"). Do NOT hand them a fresh
		-- profile, or we overwrite real progress on the next autosave.
		-- Either the datastore is unreachable or another server still holds the
		-- session. Handing out a blank profile here would overwrite real
		-- progress on the next save, so the player is asked to rejoin instead.
		player:Kick("Could not load your data. Please rejoin in a moment.")
		return
	end

	local data = stored or defaultProfile()
	data = migrate(data)
	normalizeDecks(data)
	data.stats.joinCount = (data.stats.joinCount or 0) + 1
	profiles[player] = data

	print(("[DataService] loaded %s (rolls: %d)"):format(player.Name, data.stats.totalRolls))
	self:Sync(player)
end

function DataService:_onLeave(player: Player)
	if profiles[player] then
		self:Save(player, true)      -- release the lock on the way out
		profiles[player] = nil
	end
end

function DataService:Init()
	-- A client can ask for its profile at any time. Controllers connect during
	-- startup, which can be AFTER the join-time sync has already fired, so
	-- without this a freshly joined player sees an empty inventory until their
	-- next roll.
	Remotes.RequestSync.OnServerEvent:Connect(function(player)
		self:Sync(player)
	end)


	Players.PlayerAdded:Connect(function(p) self:_onJoin(p) end)
	Players.PlayerRemoving:Connect(function(p) self:_onLeave(p) end)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(function() self:_onJoin(p) end)
	end
end

function DataService:Start()
	-- Refresh the lock while we hold it, so another server only takes over if
	-- this one genuinely died.
	task.spawn(function()
		while true do
			task.wait(HEARTBEAT_INTERVAL)
			for player in pairs(profiles) do
				task.spawn(function() self:Save(player) end)
			end
		end
	end)

	game:BindToClose(function()
		-- Shutdown gives very little time, so saves run in parallel and the
		-- lock is released as part of the same write.
		local pending = 0
		for player in pairs(profiles) do
			pending += 1
			task.spawn(function()
				self:Save(player, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 8
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
