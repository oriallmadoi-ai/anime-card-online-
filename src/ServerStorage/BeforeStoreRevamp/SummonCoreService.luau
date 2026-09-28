--!strict
-- Summon Cores, server side. The only code that changes profile.summonCores
-- and profile.forgeItems.
--
-- What a player can do, all through SummonCoreRemotes.Action:
--   upgrade  one core of a stage becomes one core of the next stage, paying
--            that stage's cost in forge items (SummonCoreConfig UPGRADE_COSTS)
--   open     one core is consumed for exactly one card
--   give / giveall / giveitem / clear   dev tools - owner, listed devs, Studio
--
-- Cores and forge items also DROP: BattleService calls GrantEncounterDrops on
-- every encounter win, and SummonCoreConfig.EncounterDrops says what each
-- encounter and stage pays (today: Pirate Shark).
--
-- OPENING IS A NORMAL ROLL WITH MORE LUCK. See SummonCoreConfig for the rule.
-- The card is decided HERE, before the client plays any animation, and enters
-- the inventory through DataService:AddCard like every other card in the game.
-- The client is handed the result plus every outcome that actually had a
-- chance (p > 0) for this core and this player, so the roulette can only ever
-- show cards that could have dropped.
--
-- SEPARATE FROM THE ROLL BUTTON by design: nothing here touches
-- stats.totalRolls, the lucky-roll counter, the roll cooldown or auto roll.
-- The won card is an ordinary owned card - Deck, Battle Power and saving
-- treat it exactly like a rolled one.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SummonCoreConfig = require(ReplicatedStorage.Shared.Config.SummonCoreConfig)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
local RarityBands = require(ReplicatedStorage.Shared.Config.RarityBands)
local CardDefinitions = require(ReplicatedStorage.Shared.Config.CardDefinitions)
local SupportDefinitions = require(ReplicatedStorage.Shared.Config.SupportDefinitions)
local CardStats = require(ReplicatedStorage.Shared.Util.CardStats)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local CoreRemotes = require(ReplicatedStorage.Shared.Net.SummonCoreRemotes)

local SummonCoreService = {}
SummonCoreService.Name = "SummonCoreService"

local generators: { [Player]: Random } = {}
local lastOpen: { [Player]: number } = {}
local lastUpgrade: { [Player]: number } = {}

-- One RNG stream per player, like RollService's (which is private to it).
local function rngFor(player: Player): Random
	local rng = generators[player]
	if not rng then
		rng = Random.new(os.clock() * 1e6 + player.UserId * 7 + 13)
		generators[player] = rng
	end
	return rng
end

local function coresOf(profile): { [string]: number }
	local cores = profile.summonCores
	if type(cores) ~= "table" then
		cores = {}
		profile.summonCores = cores
	end
	return cores
end

local function countOf(profile, id: string): number
	return math.max(0, math.floor(tonumber(coresOf(profile)[id]) or 0))
end

local function setCount(profile, id: string, n: number)
	n = math.clamp(math.floor(n), 0, SummonCoreConfig.MaxCount)
	coresOf(profile)[id] = if n > 0 then n else nil
end

local function itemsOf(profile): { [string]: number }
	local items = profile.forgeItems
	if type(items) ~= "table" then
		items = {}
		profile.forgeItems = items
	end
	return items
end

local function itemCount(profile, id: string): number
	return math.max(0, math.floor(tonumber(itemsOf(profile)[id]) or 0))
end

local function setItemCount(profile, id: string, n: number)
	n = math.clamp(math.floor(n), 0, SummonCoreConfig.MaxCount)
	itemsOf(profile)[id] = if n > 0 then n else nil
end

-- Rarest copy already owned, on the same effective denominator the player
-- sees. Same rule as RollService's `best` flag (which is private to it).
local function bestOwnedRarity(profile): number
	local best = 0
	for key in pairs(profile.cards or {}) do
		local cardId, variant = CardStats.parseKey(key)
		if cardId and variant then
			local def = CardDefinitions.Data[cardId] or SupportDefinitions.Data[cardId]
			if def then
				local rarity = VariantConfig.effectiveRarity(def.baseRarity, variant)
				if rarity > best then best = rarity end
			end
		end
	end
	return best
end

local function cardName(cardId: string): string
	local def = CardDefinitions.get(cardId) or SupportDefinitions.get(cardId)
	return def and def.name or cardId
end

function SummonCoreService:IsDev(player: Player): boolean
	return SummonCoreConfig.isDev(player)
end

function SummonCoreService:Count(player: Player, stageId: string): number
	local profile = self.Services.DataService:Get(player)
	return profile and countOf(profile, stageId) or 0
end

function SummonCoreService:ItemCount(player: Player, itemId: string): number
	local profile = self.Services.DataService:Get(player)
	return profile and itemCount(profile, itemId) or 0
end

----------------------------------------------------------------------
-- dev
----------------------------------------------------------------------

function SummonCoreService:Give(player: Player, stageId: string, count: number?)
	local stage = SummonCoreConfig.get(stageId)
	if not stage then return false, "Unknown core" end
	local DataService = self.Services.DataService
	local profile = DataService:Get(player)
	if not profile then return false, "Profile not loaded" end
	local n = math.clamp(math.floor(tonumber(count) or 1), 1, SummonCoreConfig.DevGiveMax)
	setCount(profile, stage.id, countOf(profile, stage.id) + n)
	DataService:Sync(player)
	return true, ("+%d %s"):format(n, stage.name)
end

function SummonCoreService:GiveItem(player: Player, itemId: string, count: number?)
	local item = SummonCoreConfig.item(itemId)
	if not item then return false, "Unknown item" end
	local DataService = self.Services.DataService
	local profile = DataService:Get(player)
	if not profile then return false, "Profile not loaded" end
	local n = math.clamp(math.floor(tonumber(count) or 1), 1, SummonCoreConfig.DevGiveMax)
	setItemCount(profile, item.id, itemCount(profile, item.id) + n)
	DataService:Sync(player)
	return true, ("+%d %s"):format(n, item.name)
end

function SummonCoreService:GiveAll(player: Player, count: number?)
	local DataService = self.Services.DataService
	local profile = DataService:Get(player)
	if not profile then return false, "Profile not loaded" end
	local n = math.clamp(math.floor(tonumber(count) or 1), 1, SummonCoreConfig.DevGiveMax)
	for _, stage in ipairs(SummonCoreConfig.Stages) do
		setCount(profile, stage.id, countOf(profile, stage.id) + n)
	end
	DataService:Sync(player)
	return true, ("+%d of every core"):format(n)
end

function SummonCoreService:Clear(player: Player)
	local DataService = self.Services.DataService
	local profile = DataService:Get(player)
	if not profile then return false, "Profile not loaded" end
	profile.summonCores = {}
	profile.forgeItems = {}
	DataService:Sync(player)
	return true, "All Summon Cores and forge items removed"
end

----------------------------------------------------------------------
-- encounter drops
----------------------------------------------------------------------

-- Pays what SummonCoreConfig.EncounterDrops says this win is worth and returns
-- one reward tile per thing paid, in the shape the results banner
-- (RewardPopup) already draws. Called by BattleService on EVERY encounter win.
function SummonCoreService:GrantEncounterDrops(player: Player, encounterId: string?, difficulty: string?)
	local tiles = {}
	local drops = SummonCoreConfig.dropsFor(encounterId, difficulty)
	if #drops == 0 then return tiles end
	local DataService = self.Services.DataService
	local profile = DataService:Get(player)
	if not profile then return tiles end

	for _, drop in ipairs(drops) do
		local name = drop.name
		if drop.kind == "core" then
			setCount(profile, drop.id, countOf(profile, drop.id) + drop.amount)
			local stage = SummonCoreConfig.get(drop.id)
			if stage then name = ("%s Core %s"):format(stage.family, stage.numeral) end
		else
			setItemCount(profile, drop.id, itemCount(profile, drop.id) + drop.amount)
		end
		table.insert(tiles, {
			kind = drop.kind == "core" and "SummonCore" or "ForgeItem",
			id = drop.id,
			name = name,
			amount = drop.amount,
			variant = drop.variant,
			icon = drop.image,
		})
	end
	DataService:Sync(player)
	print(("[SummonCore] %s: %s %s drops granted (%d)"):format(player.Name, tostring(encounterId),
		tostring(difficulty), #tiles))
	return tiles
end

----------------------------------------------------------------------
-- upgrade
----------------------------------------------------------------------

-- Charges a cost table { [itemId] = amount } all-or-nothing: every line is
-- checked before anything is taken.
local function payCost(profile, cost: { [string]: number }?): (boolean, string?)
	if not cost then return true, nil end
	for itemId, amount in pairs(cost) do
		if itemCount(profile, itemId) < amount then
			local item = SummonCoreConfig.item(itemId)
			return false, ("Needs %d %s"):format(amount, item and item.name or itemId)
		end
	end
	for itemId, amount in pairs(cost) do
		setItemCount(profile, itemId, itemCount(profile, itemId) - amount)
	end
	return true, nil
end

function SummonCoreService:Upgrade(player: Player, stageId: string)
	local stage = SummonCoreConfig.get(stageId)
	if not stage then return false, "Unknown core" end
	local nextStage = SummonCoreConfig.nextOf(stage.id)
	if not nextStage then return false, "Already at the highest tier" end

	-- Locked stages have no cost designed yet. Players are told so; devs may
	-- push them for free (DevBypassLocked) so the ladder stays testable.
	local devFree = false
	if stage.upgrade.locked then
		if SummonCoreConfig.DevBypassLocked and self:IsDev(player) then
			devFree = true
		else
			return false, "Coming soon"
		end
	end

	local DataService = self.Services.DataService
	local profile = DataService:Get(player)
	if not profile then return false, "Profile not loaded" end
	if countOf(profile, stage.id) < 1 then return false, "You don't own that core" end

	local now = os.clock()
	if lastUpgrade[player] and now - lastUpgrade[player] < SummonCoreConfig.UpgradeCooldown then
		return false, "Too fast"
	end
	lastUpgrade[player] = now

	if not devFree then
		local paid, reason = payCost(profile, stage.upgrade.cost)
		if not paid then return false, reason end
		local chance = stage.upgrade.successChance or 1
		if chance < 1 and rngFor(player):NextNumber() > chance then
			-- A failed attempt keeps the core; only the cost is spent.
			DataService:Sync(player)
			return true, { from = stage.id, to = stage.id, failed = true,
				remaining = countOf(profile, stage.id), owned = countOf(profile, stage.id),
				items = table.clone(itemsOf(profile)) }
		end
	end

	setCount(profile, stage.id, countOf(profile, stage.id) - 1)
	setCount(profile, nextStage.id, countOf(profile, nextStage.id) + 1)
	DataService:Sync(player)

	return true, {
		from = stage.id,
		to = nextStage.id,
		failed = false,
		devFree = devFree,
		remaining = countOf(profile, stage.id),
		owned = countOf(profile, nextStage.id),
		items = table.clone(itemsOf(profile)),
	}
end

----------------------------------------------------------------------
-- open
----------------------------------------------------------------------

function SummonCoreService:Open(player: Player, stageId: string)
	local stage = SummonCoreConfig.get(stageId)
	if not stage then return false, "Unknown core" end

	local DataService = self.Services.DataService
	local RollService = self.Services.RollService
	local profile = DataService:Get(player)
	if not profile then return false, "Profile not loaded" end
	if countOf(profile, stage.id) < 1 then return false, "You don't own that core" end

	local now = os.clock()
	if lastOpen[player] and now - lastOpen[player] < SummonCoreConfig.OpenCooldown then
		return false, "Still opening"
	end
	lastOpen[player] = now

	-- THE EXISTING ROLL, with the luck multiplied. Same outcome table, same
	-- unlock gates (a missing encounters table means "nothing cleared", never
	-- "everything unlocked"), same picker.
	local playerLuck = RollService:LuckFor(profile)
	local luck = playerLuck * stage.luck
	local clears = profile.encounters or {}
	local outcome = RollService:PickOutcome(rngFor(player), luck, clears)
	if not outcome then return false, "Nothing can be summoned" end

	local previousBest = bestOwnedRarity(profile)
	local storedVariant = if CardStats.isSupport(outcome.id) then "Standard" else outcome.variant
	local wasOwned = profile.cards[CardStats.key(outcome.id, storedVariant)] ~= nil

	-- Consume, then award, with nothing that can yield in between.
	setCount(profile, stage.id, countOf(profile, stage.id) - 1)
	DataService:AddCard(player, outcome.id, outcome.variant, 1)

	-- Every outcome that could have dropped from THIS core for THIS player.
	-- The roulette draws its strip from this list and nothing else.
	local pool = {}
	for _, entry in ipairs(RollService.buildTable(luck, clears)) do
		if entry.p > 0 then
			table.insert(pool, {
				id = entry.id,
				variant = entry.variant,
				rarity = entry.effectiveRarity,
				p = entry.p,
			})
		end
	end

	DataService:Sync(player)

	-- Same announce rule as a normal roll, worded as a summon, and held back
	-- until the roulette has landed so the bar never spoils the result.
	local band = RarityBands.forDenominator(outcome.baseRarity)
	local variant = VariantConfig.get(outcome.variant)
	if band.announce or variant.rank >= 3 then
		local message = ("%s summoned %s %s from a %s!"):format(
			player.Name, variant.display, cardName(outcome.id), stage.name)
		task.delay(SummonCoreConfig.AnnounceDelay, function()
			Remotes.Announce:FireAllClients({ player = player.Name, message = message })
		end)
	end

	return true, {
		stageId = stage.id,
		cardId = outcome.id,
		variant = outcome.variant,
		rarity = outcome.baseRarity,
		effectiveRarity = outcome.effectiveRarity,
		playerLuck = playerLuck,
		luck = luck,
		best = outcome.effectiveRarity > previousBest,
		new = not wasOwned,
		remaining = countOf(profile, stage.id),
		pool = pool,
	}
end

----------------------------------------------------------------------
-- remote
----------------------------------------------------------------------

function SummonCoreService:_handle(player: Player, action: any, payload: any)
	if type(action) ~= "string" then return false, "Bad request" end
	local args = if type(payload) == "table" then payload else {}
	local stageId = if type(args.stageId) == "string" then args.stageId else ""

	if action == "upgrade" then
		return self:Upgrade(player, stageId)
	elseif action == "open" then
		return self:Open(player, stageId)
	end

	-- Everything below is a dev tool.
	if not self:IsDev(player) then return false, "Not allowed" end
	if action == "give" then
		return self:Give(player, stageId, tonumber(args.count))
	elseif action == "giveitem" then
		local itemId = if type(args.itemId) == "string" then args.itemId else ""
		return self:GiveItem(player, itemId, tonumber(args.count))
	elseif action == "giveall" then
		return self:GiveAll(player, tonumber(args.count))
	elseif action == "clear" then
		return self:Clear(player)
	end
	return false, "Unknown action"
end

-- The forge's interaction point. It is also saved in the place, but making
-- sure here means the forge keeps working if that instance is ever lost.
local function ensurePrompt()
	local lobby = workspace:WaitForChild("Lobby", 30)
	local section = lobby and lobby:WaitForChild("ForgingSection", 30)
	local forge = section and section:WaitForChild("CardForge", 30)
	if not forge then
		warn("[SummonCoreService] Card Forge not found - no forge prompt")
		return
	end
	local base = forge:WaitForChild("Forge_Base", 30)
	if not base or not base:IsA("BasePart") then return end
	local point: Instance? = base:FindFirstChild("ForgePromptPoint")
	if not point then
		local attachment = Instance.new("Attachment")
		attachment.Name = "ForgePromptPoint"
		attachment.Parent = base
		local pivot = (forge :: Model):GetPivot()
		attachment.WorldPosition = pivot.Position + pivot.LookVector * 9 + Vector3.new(0, 5, 0)
		point = attachment
	end
	if point and not point:FindFirstChildOfClass("ProximityPrompt") then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ForgePrompt"
		prompt.ActionText = "Use Forge"
		prompt.ObjectText = "Card Forge"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 14
		prompt.RequiresLineOfSight = false
		prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		prompt:SetAttribute("CardForge", true)
		prompt.Parent = point
	end
end

function SummonCoreService:Init()
	CoreRemotes.Action.OnServerInvoke = function(player: Player, action: any, payload: any)
		local ok, a, b = pcall(function()
			return self:_handle(player, action, payload)
		end)
		if not ok then
			warn("[SummonCoreService] " .. tostring(a))
			return false, "Something went wrong"
		end
		return a, b
	end

	Players.PlayerRemoving:Connect(function(player)
		generators[player] = nil
		lastOpen[player] = nil
		lastUpgrade[player] = nil
	end)
end

function SummonCoreService:Start()
	ensurePrompt()
end

return SummonCoreService
