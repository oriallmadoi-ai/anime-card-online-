--!strict
-- Server-authoritative leaderboard summary for Anime Card Online.
--
-- SAFE DESIGN:
--   * Does NOT create or modify any DataStore.
--   * Does NOT modify RollService, Remotes, or the saved profile shape.
--   * Reads the existing DataService profile and publishes only four safe,
--     public summary values as Player Attributes.
--   * Uses the game's existing card rarity + variant rarity logic.
--
-- Battle Power = SUM of every owned card copy's EFFECTIVE rarity denominator.
-- Example: a 1-in-100 base card with a Gilded x100 rarity multiplier is worth
-- 10,000 Battle Power per owned copy.
--
-- This matches the rarity number CardRenderer already shows on the card:
-- VariantConfig.effectiveRarity(baseRarity, variant).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardStats = require(ReplicatedStorage.Shared.Util.CardStats)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)

local LeaderboardService = {}
LeaderboardService.Name = "LeaderboardService"

-- Half a second feels live without recalculating on every rendered frame.
-- The inventory stacks duplicate copies, so this loops unique card+variant
-- entries, not the player's lifetime number of rolls.
local UPDATE_INTERVAL = 0.5

local function safeCount(entry: any): number
	if type(entry) ~= "table" then return 0 end
	local count = tonumber(entry.count) or 0
	if count <= 0 then return 0 end
	return math.floor(count)
end

local function calculate(profile: any)
	local battlePower = 0
	local bestCardId = ""
	local bestVariant = "Standard"
	local bestRarity = 0
	local bestVariantRank = 0
	local bestBaseRarity = 0

	for key, entry in pairs(profile.cards or {}) do
		local count = safeCount(entry)
		if count > 0 then
			local cardId, savedVariant = CardStats.parseKey(key)
			-- Supports are deliberately excluded from Battle Power. They have no
			-- combat stats, they are Standard-only, and counting them meant a player
			-- could inflate their score with cards that never fight.
			if cardId and savedVariant and not CardStats.isSupport(cardId) then
				local def = CardStats.definition(cardId)
				if def then
					-- VariantConfig.get safely falls back to Standard if an old or
					-- invalid variant somehow appears in a save.
					local variant = VariantConfig.get(savedVariant)
					local effectiveRarity = VariantConfig.effectiveRarity(
						def.baseRarity,
						variant.id
					)

					-- Every owned copy contributes. The inventory stores copies as
					-- entry.count, so x10 of a 1-in-100 card contributes 1,000.
					battlePower += effectiveRarity * count

					-- Highest card is determined by the same effective rarity number.
					-- Ties are deterministic: prefer the higher variant rank, then
					-- the higher base rarity.
					local isBetter = effectiveRarity > bestRarity
					if effectiveRarity == bestRarity then
						if variant.rank > bestVariantRank then
							isBetter = true
						elseif variant.rank == bestVariantRank and def.baseRarity > bestBaseRarity then
							isBetter = true
						end
					end

					-- For the leaderboard thumbnail, only choose cards that actually
					-- have artwork. Cards with no art still count toward Battle Power.
					local hasArtwork = type(def.art) == "string" and def.art ~= ""

					if isBetter and hasArtwork then
						bestRarity = effectiveRarity
						bestCardId = cardId
						bestVariant = variant.id
						bestVariantRank = variant.rank
						bestBaseRarity = def.baseRarity
					end
				end
			end
		end
	end

	return {
		battlePower = battlePower,
		bestCardId = bestCardId,
		bestVariant = bestVariant,
		bestRarity = bestRarity,
	}
end

local function setAttributeIfChanged(player: Player, name: string, value: any)
	if player:GetAttribute(name) ~= value then
		player:SetAttribute(name, value)
	end
end

function LeaderboardService:Publish(player: Player)
	local DataService = self.Services and self.Services.DataService
	if not DataService then return end

	local profile = DataService:Get(player)
	if not profile then return end

	local summary = calculate(profile)
	local totalRolls = tonumber(profile.stats and profile.stats.totalRolls) or 0

	-- These Attributes replicate from server -> every client automatically.
	-- The client NEVER sends Battle Power to the server.
	setAttributeIfChanged(player, "BattlePower", summary.battlePower)
	setAttributeIfChanged(player, "TotalRolls", math.floor(math.max(0, totalRolls)))
	setAttributeIfChanged(player, "BestCardId", summary.bestCardId)
	setAttributeIfChanged(player, "BestCardVariant", summary.bestVariant)
	setAttributeIfChanged(player, "BestCardRarity", summary.bestRarity)
	setAttributeIfChanged(player, "LeaderboardReady", true)
end

function LeaderboardService:Start()
	local DataService = self.Services and self.Services.DataService
	if not DataService then
		warn("[LeaderboardService] DataService missing")
		return
	end

	local function primePlayer(player: Player)
		task.spawn(function()
			-- DataService already owns loading/session locking. We only wait for it.
			local profile = DataService:Await(player, 20)
			if profile and player.Parent then
				self:Publish(player)
			end
		end)
	end

	Players.PlayerAdded:Connect(primePlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		primePlayer(player)
	end

	-- Re-read the current authoritative profile periodically. This intentionally
	-- avoids patching RollService/DataService and also catches Studio debug grants,
	-- wipes, and any future inventory mutation that changes profile.cards.
	task.spawn(function()
		while true do
			task.wait(UPDATE_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				self:Publish(player)
			end
		end
	end)

	print("[LeaderboardService] online")
end

return LeaderboardService
