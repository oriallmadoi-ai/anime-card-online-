--!strict
-- Server-authoritative rolling.
--
-- IMPORTANT DESIGN RULE:
-- Every rollable card + variant pair is its own outcome in ONE distribution.
--
-- Examples:
--   Pirate Sniper Basic   = base 2 x 1       = 1 in 2
--   Pirate Sniper Gilded  = base 2 x 100     = 1 in 200
--   Pirate Sniper Divine  = base 2 x 10,000  = 1 in 20,000
--   Pirate Sniper Secret  = base 2 x 1,000,000 = 1 in 2,000,000
--
-- This fixes the old two-step system where the card roll used player luck but
-- the variant roll did not. In that system a high-luck player could regularly
-- hit a 1-in-17,000 Basic card while Gilded / Divine still rolled at their raw
-- 1/100 and 1/10,000 variant chances. That made the printed effective rarity
-- disagree with the player's actual roll distribution.
--
-- Locked cards are removed from the outcome pool until their encounter unlock
-- requirement is met. Attack cards can roll Basic/Gilded/Divine/Secret.
-- Supports remain Standard-only, matching DataService and SupportDefinitions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local CardDefinitions = require(ReplicatedStorage.Shared.Config.CardDefinitions)
local SupportDefinitions = require(ReplicatedStorage.Shared.Config.SupportDefinitions)
local EncounterModes = require(ReplicatedStorage.Shared.Config.EncounterModes)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
local RarityBands = require(ReplicatedStorage.Shared.Config.RarityBands)
local CardStats = require(ReplicatedStorage.Shared.Util.CardStats)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local RollService = {}
RollService.Name = "RollService"

local lastRoll: { [Player]: number } = {}
local generators: { [Player]: Random } = {}
local tableCache: { [string]: any } = {}
local autoRolling: { [Player]: boolean } = {}

-- The unlock ids in a fixed order so unlock state can be part of the table key.
local UNLOCK_IDS: { string } = {}
for id in pairs(EncounterModes.Unlocks) do
	table.insert(UNLOCK_IDS, id)
end
table.sort(UNLOCK_IDS)

local function rngFor(player: Player): Random
	local rng = generators[player]
	if not rng then
		-- One RNG stream per player.
		rng = Random.new(os.clock() * 1e6 + player.UserId)
		generators[player] = rng
	end
	return rng
end

-- nil clears is used by offline/debug odds tooling and means FULLY UNLOCKED.
-- A real live profile always passes profile.encounters (an actual table), so a
-- new player with no clears still has the intended encounter gates.
local function isUnlockedForRoll(cardId: string, clears): boolean
	if clears == nil then
		return true
	end
	return EncounterModes.isUnlocked(cardId, clears)
end

-- Stable unlock-state cache key.
local function unlockKey(clears): string
	if clears == nil then
		return "ALL"
	end

	local parts = table.create(#UNLOCK_IDS)
	for i, id in ipairs(UNLOCK_IDS) do
		parts[i] = EncounterModes.isUnlocked(id, clears) and "1" or "0"
	end
	return table.concat(parts)
end

-- Base card/support pool the player is currently allowed to roll.
local function basePoolFor(clears)
	local pool = {}

	for _, cardId in ipairs(CardDefinitions.RarestFirst) do
		if isUnlockedForRoll(cardId, clears) then
			local def = CardDefinitions.Data[cardId]
			if def then
				table.insert(pool, {
					id = cardId,
					baseRarity = def.baseRarity,
					isSupport = false,
				})
			end
		end
	end

	-- Supports roll like everything else.
	--
	-- This loop used to walk UNLOCK_IDS, which meant only a support NAMED in
	-- EncounterModes.Unlocks could ever appear - exactly one of the ten (Will
	-- of D). The other nine were defined, arted, priced at rarities from 1/90
	-- to 1/120,000, and unobtainable by rolling.
	--
	-- RarestFirst, not pairs(Data): the outcome pool is CACHED by unlock state,
	-- so it has to be built in a stable order or the same cache key could be
	-- filled from two differently ordered tables. RarestFirst is sorted by
	-- rarity with an id tiebreak, so it is deterministic.
	--
	-- The gate is unchanged: isUnlockedForRoll returns true for any id absent
	-- from Unlocks, so the nine ungated supports are available immediately and
	-- Will of D stays behind Arlong on Impossible. Supports remain
	-- Standard-only downstream in outcomePoolFor.
	for _, id in ipairs(SupportDefinitions.RarestFirst) do
		local def = SupportDefinitions.get(id)
		if def and isUnlockedForRoll(id, clears) then
			table.insert(pool, {
				id = id,
				baseRarity = def.baseRarity,
				isSupport = true,
			})
		end
	end

	return pool
end

-- Build every actual outcome that can happen on one roll.
--
-- Attack cards: Standard / Gilded / Astral(displayed Divine) /
-- Transcendent(displayed Secret).
-- Supports: Standard only.
local function outcomePoolFor(clears)
	local outcomes = {}

	for _, item in ipairs(basePoolFor(clears)) do
		if item.isSupport then
			table.insert(outcomes, {
				id = item.id,
				variant = "Standard",
				baseRarity = item.baseRarity,
				effectiveRarity = item.baseRarity,
				variantRank = VariantConfig.get("Standard").rank,
			})
		else
			for _, variantId in ipairs(VariantConfig.Order) do
				local variant = VariantConfig.get(variantId)

				-- Presentation-only variants (for example Cosmic) must never enter rolls.
				if not variant.presentationOnly then
					table.insert(outcomes, {
						id = item.id,
						variant = variantId,
						baseRarity = item.baseRarity,
						effectiveRarity = VariantConfig.effectiveRarity(item.baseRarity, variantId),
						variantRank = variant.rank,
					})
				end
			end
		end
	end

	-- Rarest first. This is the same safe ordering principle the old card-only
	-- table used, but now it applies to the REAL outcome denominator shown to the
	-- player, including the variant multiplier.
	table.sort(outcomes, function(a, b)
		if a.effectiveRarity ~= b.effectiveRarity then
			return a.effectiveRarity > b.effectiveRarity
		end
		if a.variantRank ~= b.variantRank then
			return a.variantRank > b.variantRank
		end
		if a.id ~= b.id then
			return a.id < b.id
		end
		return a.variant < b.variant
	end)

	return outcomes
end

-- Builds one cumulative table containing EVERY rollable card+variant outcome.
--
-- Luck scales the exact effective denominator that is printed on the card.
-- That means 2x luck doubles the chance of a 1-in-10,000 Gilded outcome just as
-- it doubles the chance of a 1-in-10,000 Basic outcome.
local function buildTable(luck: number, clears, minimumRarity: number?)
	luck = math.max(0, tonumber(luck) or 1)

	local minimum = math.max(0, tonumber(minimumRarity) or 0)
	local key = tostring(luck) .. "#" .. unlockKey(clears)
	if minimum > 0 then key ..= "#min:" .. tostring(minimum) end
	local cached = tableCache[key]
	if cached then
		return cached
	end

	-- Condition the existing distribution on the guarantee, rather than
	-- rerolling or assigning the leftover probability to the weakest card.
	-- No minimum means the ordinary roll table remains exactly unchanged.
	if minimum > 0 then
		local base = buildTable(luck, clears)
		local total = 0
		for _, entry in ipairs(base) do
			if entry.effectiveRarity >= minimum and entry.p > 0 then total += entry.p end
		end
		local filtered = {}
		if total > 0 then
			local acc = 0
			for _, entry in ipairs(base) do
				if entry.effectiveRarity >= minimum and entry.p > 0 then
					local copy = table.clone(entry)
					copy.p = entry.p / total
					acc += copy.p
					copy.upTo = acc
					table.insert(filtered, copy)
				end
			end
			filtered[#filtered].upTo = 1
		end
		tableCache[key] = filtered
		return filtered
	end

	local pool = outcomePoolFor(clears)
	local entries = {}
	local remaining = 1.0

	-- If the roster is somehow empty, return an empty table instead of erroring.
	if #pool == 0 then
		tableCache[key] = entries
		return entries
	end

	-- Rarest-first sequential odds.
	-- The final (most common) unlocked outcome absorbs the remaining probability,
	-- guaranteeing that one roll always produces one valid result.
	local lastIndex = #pool
	for index, outcome in ipairs(pool) do
		local probability

		if index == lastIndex then
			probability = remaining
			remaining = 0
		else
			local chance = math.clamp(luck / outcome.effectiveRarity, 0, 1)
			probability = remaining * chance
			remaining -= probability
		end

		entries[#entries + 1] = {
			id = outcome.id,
			variant = outcome.variant,
			baseRarity = outcome.baseRarity,
			effectiveRarity = outcome.effectiveRarity,
			p = probability,
		}
	end

	local cumulative = {}
	local acc = 0
	for _, entry in ipairs(entries) do
		acc += entry.p
		cumulative[#cumulative + 1] = {
			id = entry.id,
			variant = entry.variant,
			baseRarity = entry.baseRarity,
			effectiveRarity = entry.effectiveRarity,
			p = entry.p,
			upTo = acc,
		}
	end

	-- Avoid a microscopic floating-point gap at the very end.
	if #cumulative > 0 then
		cumulative[#cumulative].upTo = 1
	end

	tableCache[key] = cumulative
	return cumulative
end

-- Kept public because the existing debug/offline tooling already expects it.
RollService.buildTable = buildTable

function RollService:LuckFor(profile): number
	return 1 + (profile.upgrades.luck or 0) * GameConfig.LuckPerLevel
end

function RollService:GetCooldown(profile): number
	local reduction = (profile.upgrades.rollSpeed or 0) * GameConfig.RollSpeedPerLevel
	return math.max(GameConfig.MinRollCooldown, GameConfig.BaseRollCooldown * (1 - reduction))
end

-- Pick one COMPLETE outcome: card + variant.
function RollService:PickOutcome(rng: Random, luck: number, clears, minimumRarity: number?)
	local dist = buildTable(luck, clears, minimumRarity)
	if #dist == 0 then
		return nil
	end

	local roll = rng:NextNumber()
	for _, entry in ipairs(dist) do
		if roll <= entry.upTo then
			return entry
		end
	end

	return dist[#dist]
end

-- Compatibility helpers. Nothing in the current game needs these separately,
-- but keeping them prevents Studio/debug tooling from breaking if it calls them.
function RollService:PickCard(rng: Random, luck: number, clears): string
	local outcome = self:PickOutcome(rng, luck, clears)
	return outcome and outcome.id or CardDefinitions.MostCommonId
end

function RollService:PickVariant(rng: Random, variantLuck: number): string
	local luck = math.max(0, tonumber(variantLuck) or 1)
	for _, id in ipairs(VariantConfig.RollOrder) do
		local variant = VariantConfig.Data[id]
		if variant then
			local chance = math.clamp(luck / variant.rarityMultiplier, 0, 1)
			if rng:NextNumber() < chance then
				return id
			end
		end
	end
	return "Standard"
end

-- How many rolls until the next lucky roll, 1..LuckyRollEvery.
function RollService:RollsUntilLucky(profile): number
	local every = GameConfig.LuckyRollEvery
	return every - (profile.stats.totalRolls % every)
end

-- Rarest copy already owned, using the same effective denominator the player sees.
local function bestOwnedRarity(profile): number
	local best = 0

	for key in pairs(profile.cards) do
		local cardId, variant = CardStats.parseKey(key)
		if cardId and variant then
			local def = CardDefinitions.Data[cardId] or SupportDefinitions.Data[cardId]
			if def then
				local rarity = VariantConfig.effectiveRarity(def.baseRarity, variant)
				if rarity > best then
					best = rarity
				end
			end
		end
	end

	return best
end

function RollService:RollOnce(player: Player, profile)
	local rng = rngFor(player)
	local previousBest = bestOwnedRarity(profile)

	-- The roll about to happen is totalRolls + 1.
	local isLucky = ((profile.stats.totalRolls + 1) % GameConfig.LuckyRollEvery) == 0

	-- ONE luck value drives the entire outcome table, including variants.
	local luck = self:LuckFor(profile)
	if isLucky then
		luck *= GameConfig.LuckyRollMultiplier
	end

	local outcome = self:PickOutcome(rng, luck, profile.encounters)
	if not outcome then
		return nil
	end

	local cardId = outcome.id
	local variant = outcome.variant
	local baseRarity = outcome.baseRarity

	profile.stats.totalRolls += 1
	self.Services.DataService:AddCard(player, cardId, variant, 1)

	return {
		cardId = cardId,
		variant = variant,
		rarity = baseRarity,
		effectiveRarity = outcome.effectiveRarity,
		lucky = isLucky,
		untilLucky = self:RollsUntilLucky(profile),
		best = outcome.effectiveRarity > previousBest,
	}
end

function RollService:HandleRollRequest(player: Player)
	local DataService = self.Services.DataService
	local profile = DataService:Get(player)
	if not profile then
		return
	end

	-- Server-authoritative rate limit.
	local now = os.clock()
	local cooldown = self:GetCooldown(profile)
	if lastRoll[player] and (now - lastRoll[player]) < (cooldown * 0.9) then
		return
	end
	lastRoll[player] = now

	local result = self:RollOnce(player, profile)
	if not result then
		return
	end

	Remotes.RollResult:FireClient(player, result)

	local band = RarityBands.forDenominator(result.rarity)
	local variant = VariantConfig.get(result.variant)
	if band.announce or variant.rank >= 3 then
		-- Announced by the server so a modified client cannot fake a pull.
		Remotes.Announce:FireAllClients({
			player = player.Name,
			cardId = result.cardId,
			variant = result.variant,
			rarity = result.rarity,
		})
	end

	DataService:Sync(player)
end

function RollService:StartAutoLoop()
	task.spawn(function()
		while true do
			task.wait(0.1)

			for player, on in pairs(autoRolling) do
				if on and player.Parent then
					local profile = self.Services.DataService:Get(player)
					if profile then
						local last = lastRoll[player] or 0
						if os.clock() - last >= self:GetCooldown(profile) then
							self:HandleRollRequest(player)
						end
					end
				end
			end
		end
	end)
end

function RollService:Init()
	Remotes.RequestRoll.OnServerEvent:Connect(function(player)
		local ok, err = pcall(function()
			self:HandleRollRequest(player)
		end)
		if not ok then
			warn("[RollService] " .. tostring(err))
		end
	end)

	Remotes.SetAutoRoll.OnServerEvent:Connect(function(player, enabled)
		autoRolling[player] = (enabled == true) or nil
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastRoll[player] = nil
		generators[player] = nil
		autoRolling[player] = nil
	end)

	self:StartAutoLoop()
end

return RollService
