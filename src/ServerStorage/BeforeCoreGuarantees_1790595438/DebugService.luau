--!strict
-- Studio-only debug channel.
--
-- Why this exists: the Studio command bar and external tooling run in a
-- SEPARATE Luau VM from the game scripts. require() from there gives you a
-- second, empty copy of every service, and _G is not shared either. A
-- BindableFunction is instance-based, so it does cross that boundary.
--
-- Commands return STRINGS, not tables, because values sent across a
-- BindableFunction are deep-copied and functions are stripped.
--
-- This whole service refuses to initialise outside Studio, so it cannot
-- become an exploit surface in a live game.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Util.Format)
local CardStats = require(ReplicatedStorage.Shared.Util.CardStats)
local CardDefinitions = require(ReplicatedStorage.Shared.Config.CardDefinitions)
local SupportDefinitions = require(ReplicatedStorage.Shared.Config.SupportDefinitions)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local DebugService = {}
DebugService.Name = "DebugService"

local function firstPlayer(): Player?
	return Players:GetPlayers()[1]
end

local Commands = {}

function Commands.roll(self, count: number?)
	local player = firstPlayer()
	if not player then return "no player" end
	local DataService = self.Services.DataService
	local RollService = self.Services.RollService
	local profile = DataService:Get(player)
	if not profile then return "no profile" end

	local n = math.clamp(tonumber(count) or 1, 1, 100000)
	local RarityFormat = require(ReplicatedStorage.Shared.Util.RarityFormat)
	local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)

	-- "Best" means scarcest: the printed denominator scaled by how rare the
	-- variant is - which is exactly what VariantConfig.effectiveRarity computes.
	--
	-- This used to divide by `VariantConfig.get(r.variant).rollChance`, but
	-- rollChance is a FUNCTION ON THE MODULE, not a field on a variant, so the
	-- lookup was always nil and the `or 1` quietly turned the whole expression
	-- back into the base denominator. The result was that a Secret pull could
	-- never win the comparison and this command reported a Standard card as the
	-- best of a hundred thousand rolls.
	local best, bestScore = nil, -1
	for _ = 1, n do
		local r = RollService:RollOnce(player, profile)
		if r then
			local score = VariantConfig.effectiveRarity(r.rarity, r.variant)
			if score > bestScore then bestScore = score; best = r end
		end
	end
	DataService:Sync(player)
	if not best then return "rolled nothing" end
	return ("rolled %d (total %s). best: %s %s  %s"):format(
		n, Format.comma(profile.stats.totalRolls),
		best.variant, best.cardId, RarityFormat.denominator(bestScore))
end

function Commands.dump(self)
	local player = firstPlayer()
	if not player then return "no player" end
	local profile = self.Services.DataService:Get(player)
	if not profile then return "no profile" end

	local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
	local RarityFormat = require(ReplicatedStorage.Shared.Util.RarityFormat)
	local BookDefinitions = require(ReplicatedStorage.Shared.Config.BookDefinitions)

	local keys = {}
	for k in pairs(profile.cards) do table.insert(keys, k) end
	table.sort(keys)

	local lines = {
		("%s | rolls %s | schema v%s"):format(
			player.Name, Format.comma(profile.stats.totalRolls), tostring(profile.version)),
	}

	for _, key in ipairs(keys) do
		local entry = profile.cards[key]
		local cardId, variant = CardStats.parseKey(key)
		local def = CardDefinitions.get(cardId) or SupportDefinitions.get(cardId)
		if def then
			local stats = CardStats.compute(cardId, variant, entry.level)
			lines[#lines + 1] = ("  %-13s %-12s x%-4d Lv%-4d %-14s %s DMG / %s HP"):format(
				def.name, variant, entry.count, entry.level,
				RarityFormat.denominator(VariantConfig.effectiveRarity(def.baseRarity, variant)),
				Format.short(stats.dmg), Format.short(stats.hp))
		end
	end

	local books = {}
	for _, id in ipairs(BookDefinitions.Order) do
		local n = (profile.books or {})[id]
		if n and n > 0 then books[#books + 1] = ("%s x%d"):format(id, n) end
	end
	lines[#lines + 1] = "books: " .. (#books > 0 and table.concat(books, ", ") or "none")
	return table.concat(lines, "\n")
end

function Commands.grant(self, cardId: string, variant: string?, count: number?)
	local player = firstPlayer()
	if not player then return "no player" end
	if not (CardDefinitions.exists(cardId) or SupportDefinitions.exists(cardId)) then
		return "unknown card: " .. tostring(cardId)
	end
	self.Services.DataService:AddCard(player, cardId, variant or "Standard", tonumber(count) or 1)
	self.Services.DataService:Sync(player)
	return ("granted %dx %s [%s]"):format(tonumber(count) or 1, cardId, variant or "Standard")
end

-- Grants every card in both rosters, in every variant, but ONLY the ones the
-- player does not already own. AddCard increments an existing stack, so a blind
-- grant-all would inflate counts on every re-run; checking the key first makes
-- this idempotent and safe to run after adding new cards to the definitions.
--
-- It reads the rosters live, so a card added to CardDefinitions or
-- SupportDefinitions later is picked up with no change here.
function Commands.grantall(self, count: number?)
	local player = firstPlayer()
	if not player then return "no player" end
	local DataService = self.Services.DataService
	local profile = DataService:Get(player)
	if not profile then return "no profile" end

	local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
	local n = math.max(tonumber(count) or 1, 1)

	local added, existed = 0, 0
	local addedNames = {}

	for _, roster in ipairs({ CardDefinitions.Data, SupportDefinitions.Data }) do
		for cardId in pairs(roster) do
			-- Supports exist in Standard only, so granting the other three borders
			-- would just create keys AddCard immediately collapses back to Standard.
			local variants = CardStats.isSupport(cardId)
				and { "Standard" }
				or VariantConfig.Order
			for _, variant in ipairs(variants) do
				local key = CardStats.key(cardId, variant)
				if profile.cards[key] then
					existed += 1
				else
					DataService:AddCard(player, cardId, variant, n)
					added += 1
					addedNames[#addedNames + 1] = cardId .. "|" .. variant
				end
			end
		end
	end

	DataService:Sync(player)
	local saved = DataService:Save(player)

	table.sort(addedNames)
	return ("granted %d missing (x%d each), %d already owned, saved=%s\n  %s")
		:format(added, n, existed, tostring(saved),
			#addedNames > 0 and table.concat(addedNames, ", ") or "nothing was missing")
end

-- Sets an owned stack to an exact count, or removes it at 0. `grant` can only
-- ever add, so without this there is no way to undo a test grant short of wiping
-- the whole profile.
function Commands.setcount(self, cardId: string, variant: string, count: number)
	local player = firstPlayer()
	if not player then return "no player" end
	local DataService = self.Services.DataService
	local profile = DataService:Get(player)
	if not profile then return "no profile" end

	local key = CardStats.key(cardId, variant or "Standard")
	local entry = profile.cards[key]
	if not entry then return "not owned: " .. key end

	local n = math.max(0, math.floor(tonumber(count) or 0))
	if n == 0 then
		profile.cards[key] = nil
	else
		entry.count = n
	end
	DataService:Sync(player)
	local saved = DataService:Save(player)
	return ("%s -> count %d, saved=%s"):format(key, n, tostring(saved))
end

-- ── skill tree ─────────────────────────────────────────────

function Commands.coins(self, count: number?)
	local player = firstPlayer()
	if not player then return "no player" end
	local profile = self.Services.DataService:Get(player)
	if not profile then return "no profile" end

	-- Set directly rather than through GrantCoins, so a debug top-up is not
	-- inflated by the player's own CoinGain skills - you asked for N, you get N.
	profile.currency = profile.currency or {}
	profile.currency.elderCoins = math.max(0, math.floor(tonumber(count) or 0))
	self.Services.DataService:Sync(player)
	return ("Elder Coins set to %d"):format(profile.currency.elderCoins)
end

function Commands.skills(self)
	local player = firstPlayer()
	if not player then return "no player" end
	local profile = self.Services.DataService:Get(player)
	if not profile then return "no profile" end

	local SkillDefinitions = require(ReplicatedStorage.Shared.Config.SkillDefinitions)
	local SkillEffects = require(ReplicatedStorage.Shared.Config.SkillEffects)
	local Skills = self.Services.SkillTreeService

	local lines = {
		("%s | Elder Coins: %d"):format(player.Name, Skills:Coins(player)),
	}
	for _, id in ipairs(SkillDefinitions.Order) do
		local def = SkillDefinitions.get(id)
		local rank = (profile.skills or {})[id] or 0
		lines[#lines + 1] = ("  %-16s %d/%d  %s"):format(
			def.Name, rank, def.MaxRank,
			SkillEffects.DescribeRank(def, rank) or "-")
	end

	lines[#lines + 1] = "totals:"
	local totals = Skills:Totals(player)
	local keys = {}
	for k in pairs(totals) do table.insert(keys, k) end
	table.sort(keys)
	for _, k in ipairs(keys) do
		lines[#lines + 1] = ("  %-22s %.4f"):format(k, totals[k])
	end
	lines[#lines + 1] = ("derived upgrades: luck=%.4f rollSpeed=%.4f damage=%.4f"):format(
		profile.upgrades.luck or 0, profile.upgrades.rollSpeed or 0, profile.upgrades.damage or 0)
	return table.concat(lines, "\n")
end

function Commands.skill(self, skillId: string)
	local player = firstPlayer()
	if not player then return "no player" end
	local ok, reason = self.Services.SkillTreeService:Purchase(player, skillId)
	return ("%s - %s"):format(ok and "BOUGHT" or "REFUSED", tostring(reason))
end

function Commands.wipeskills(self)
	local player = firstPlayer()
	if not player then return "no player" end
	local profile = self.Services.DataService:Get(player)
	if not profile then return "no profile" end
	profile.skills = {}
	self.Services.SkillTreeService:Recompute(player)
	self.Services.DataService:Sync(player)
	return "skill ranks cleared"
end

function Commands.wipe(self)
	local player = firstPlayer()
	if not player then return "no player" end
	local profile = self.Services.DataService:Get(player)
	if not profile then return "no profile" end
	profile.cards = {}
	-- The schema field is `decks` (eight presets plus an active index). This
	-- wrote a `deck` key that nothing reads, so a wipe left every saved lineup
	-- intact and pointing at cards the player no longer owned.
	profile.decks = { active = 1, presets = {} }
	profile.deck = nil
	profile.stats.totalRolls = 0
	profile.books = {}
	self.Services.DataService:Save(player)
	self.Services.DataService:Sync(player)
	return "profile wiped and saved"
end

function Commands.save(self)
	local player = firstPlayer()
	if not player then return "no player" end
	return self.Services.DataService:Save(player) and "saved" or "SAVE FAILED"
end

function Commands.books(self, bookId: string, count: number)
	local player = firstPlayer()
	if not player then return "no player" end
	local ok = self.Services.LevelService:GrantBooks(player, bookId or "MinorTome", tonumber(count) or 1)
	return ok and ("granted %dx %s"):format(tonumber(count) or 1, bookId or "MinorTome") or "unknown book"
end

function Commands.levelup(self, cardId: string, variant: string, bookId: string)
	local ok, reason = self.Services.LevelService:UseBook(
		firstPlayer(), cardId or "Duffy", variant or "Standard", bookId or "MinorTome")
	return tostring(reason)
end

-- ── summon cores ───────────────────────────────────────────

function Commands.cores(self)
	local player = firstPlayer()
	if not player then return "no player" end
	local profile = self.Services.DataService:Get(player)
	if not profile then return "no profile" end
	local SummonCoreConfig = require(ReplicatedStorage.Shared.Config.SummonCoreConfig)
	local lines = { ("%s | luck %.2f | schema v%s"):format(
		player.Name, self.Services.RollService:LuckFor(profile), tostring(profile.version)) }
	for _, entry in ipairs(SummonCoreConfig.owned(profile)) do
		lines[#lines + 1] = ("  %-24s x%d   (luck x%s)"):format(
			entry.stage.name, entry.count, SummonCoreConfig.formatBoost(entry.stage.luck))
	end
	for _, entry in ipairs(SummonCoreConfig.ownedItems(profile)) do
		lines[#lines + 1] = ("  %-24s x%d"):format(entry.item.name, entry.count)
	end
	if #lines == 1 then lines[2] = "  no cores or forge items" end
	return table.concat(lines, "\n")
end

-- Forge items by id: "CoreEssenceBasic", "ElderWrench".
function Commands.giveitem(self, itemId: string?, count: number?)
	local player = firstPlayer()
	if not player then return "no player" end
	local _, message = self.Services.SummonCoreService:GiveItem(player, tostring(itemId or ""), tonumber(count) or 1)
	return tostring(message)
end

-- Pays one encounter win's forge drops exactly as BattleService does after a
-- win, without fighting it. Returns what the results banner would be handed.
function Commands.drops(self, encounterId: string?, difficulty: string?)
	local player = firstPlayer()
	if not player then return "no player" end
	local tiles = self.Services.SummonCoreService:GrantEncounterDrops(player,
		tostring(encounterId or "Arlong"), tostring(difficulty or "Easy"))
	local parts = {}
	for _, tile in ipairs(tiles) do
		parts[#parts + 1] = ("%s x%d [%s]"):format(tostring(tile.name), tile.amount or 0, tostring(tile.kind))
	end
	return if #parts > 0 then table.concat(parts, ", ") else "no drops"
end

-- One upgrade through the real server path (costs, locks, cooldown).
function Commands.upgradecore(self, which: string?)
	local player = firstPlayer()
	if not player then return "no player" end
	local SummonCoreConfig = require(ReplicatedStorage.Shared.Config.SummonCoreConfig)
	local stage = SummonCoreConfig.parse(tostring(which or ""))
	if not stage then return "unknown core: " .. tostring(which) end
	local ok, result = self.Services.SummonCoreService:Upgrade(player, stage.id)
	if not ok then return "refused: " .. tostring(result) end
	return ("%s -> %s%s | left %d, now own %d"):format(result.from, result.to,
		if result.devFree then " (dev, free)" else "", result.remaining or 0, result.owned or 0)
end

function Commands.givecore(self, which: string?, count: number?)
	local player = firstPlayer()
	if not player then return "no player" end
	local SummonCoreConfig = require(ReplicatedStorage.Shared.Config.SummonCoreConfig)
	local stage = SummonCoreConfig.parse(tostring(which or ""))
	if not stage then return "unknown core: " .. tostring(which) end
	local _, message = self.Services.SummonCoreService:Give(player, stage.id, tonumber(count) or 1)
	return tostring(message)
end

-- Opens N cores in simulation only: the REAL picker (RollService.PickOutcome)
-- with the core's luck, but nothing is consumed or awarded. For checking a
-- stage's odds against the table in SummonCoreConfig.
function Commands.coresim(self, which: string?, count: number?, luckOverride: number?)
	local SummonCoreConfig = require(ReplicatedStorage.Shared.Config.SummonCoreConfig)
	local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
	local RarityFormat = require(ReplicatedStorage.Shared.Util.RarityFormat)
	local stage = SummonCoreConfig.parse(tostring(which or ""))
	if not stage then return "unknown core: " .. tostring(which) end

	local player = firstPlayer()
	local profile = player and self.Services.DataService:Get(player)
	local RollService = self.Services.RollService
	local playerLuck = tonumber(luckOverride) or (profile and RollService:LuckFor(profile)) or 1
	local luck = playerLuck * stage.luck
	local clears = profile and (profile.encounters or {}) or nil
	local n = math.clamp(math.floor(tonumber(count) or 10000), 1, 1000000)

	local rng = Random.new()
	local byVariant = {}
	local rarities = table.create(n)
	local best = nil
	for i = 1, n do
		local o = RollService:PickOutcome(rng, luck, clears)
		if o then
			byVariant[o.variant] = (byVariant[o.variant] or 0) + 1
			rarities[i] = o.effectiveRarity
			if not best or o.effectiveRarity > best.effectiveRarity then best = o end
		end
	end
	table.sort(rarities)

	local lines = { ("%s x%d | player luck %.2f x %s = %s"):format(
		stage.name, n, playerLuck, SummonCoreConfig.formatBoost(stage.luck), Format.short(luck)) }
	for _, id in ipairs(VariantConfig.Order) do
		local k = byVariant[id] or 0
		lines[#lines + 1] = ("  %-8s %6.2f%%"):format(VariantConfig.get(id).display, 100 * k / n)
	end
	lines[#lines + 1] = "  median " .. RarityFormat.denominator(rarities[math.max(1, math.floor(n / 2))] or 0)
	if best then
		lines[#lines + 1] = ("  best   %s %s %s"):format(VariantConfig.get(best.variant).display, best.id,
			RarityFormat.denominator(best.effectiveRarity))
	end
	return table.concat(lines, "\n")
end

-- ── test sandbox ────────────────────────────────────────────
-- A Studio session with API access loads and SAVES the real profile. Take a
-- snapshot before testing something that grants cards or cores, and restore
-- it afterwards, so the test leaves the save exactly as it found it.
local snapshots = {}

local function deepCopy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in pairs(value) do out[k] = deepCopy(v) end
	return out
end

function Commands.snapshot(self)
	local player = firstPlayer()
	if not player then return "no player" end
	local profile = self.Services.DataService:Get(player)
	if not profile then return "no profile" end
	snapshots[player.UserId] = deepCopy(profile)
	return "snapshot taken"
end

function Commands.restore(self)
	local player = firstPlayer()
	if not player then return "no player" end
	local DataService = self.Services.DataService
	local profile = DataService:Get(player)
	local snapshot = snapshots[player.UserId]
	if not profile or not snapshot then return "nothing to restore" end
	for k in pairs(profile) do profile[k] = nil end
	for k, v in pairs(snapshot) do profile[k] = deepCopy(v) end
	DataService:Sync(player)
	return "restored, saved=" .. tostring(DataService:Save(player))
end

function Commands.help()
	return "commands: roll <n> | dump | grant <cardId> <variant> <n> | grantall <n> | setcount <cardId> <variant> <n> | books <bookId> <n> | levelup <cardId> <variant> <bookId> | coins <n> | skills | skill <skillId> | wipeskills | wipe | save | cores | givecore <core> <n> | giveitem <itemId> <n> | drops <encounterId> <difficulty> | upgradecore <core> | coresim <core> <n> [luck] | snapshot | restore"
end

function DebugService:Init()
	if not RunService:IsStudio() then return end

	local bf = ServerStorage:FindFirstChild("DebugInvoke")
	if not bf then
		bf = Instance.new("BindableFunction")
		bf.Name = "DebugInvoke"
		bf.Parent = ServerStorage
	end

	bf.OnInvoke = function(command, ...)
		local fn = Commands[tostring(command)]
		if not fn then return "unknown command: " .. tostring(command) .. "\n" .. Commands.help() end
		local ok, result = pcall(fn, self, ...)
		return ok and tostring(result) or ("error: " .. tostring(result))
	end

	print("[DebugService] ready - ServerStorage.DebugInvoke:Invoke('help')")
end

return DebugService
