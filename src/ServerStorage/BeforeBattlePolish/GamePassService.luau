--!strict
-- Anime Card Online
-- Game pass ownership and the one helper the +35% Items pass needs.
--
-- OWNERSHIP is checked once on join (UserOwnsGamePassAsync) and again the
-- moment a purchase completes (PromptGamePassPurchaseFinished), and is stored
-- as a replicated player attribute - see GamePassConfig. A Studio test
-- purchase fires PromptGamePassPurchaseFinished like a real one, so the store
-- can be tested end to end in a playtest without spending anything.
--
-- WHERE THE PERKS LIVE
--   VIP luck / roll speed  SkillTreeService:Recompute folds them into the
--                          profile.upgrades values RollService already reads
--   VIP battle speed       BattleService paces its replay by the player's
--                          "BattleSpeed" attribute (the in-battle toggle)
--   2x Summon Core         SummonCoreService:Open rolls a second card
--   +35% Items             GrantCoins and GrantEncounterDrops call BoostItems

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GamePassConfig = require(ReplicatedStorage.Shared.Config.GamePassConfig)

local GamePassService = {}
GamePassService.Name = "GamePassService"

local generators: { [Player]: Random } = {}

local function rngFor(player: Player): Random
	local rng = generators[player]
	if not rng then
		rng = Random.new(os.clock() * 1e6 + player.UserId * 3 + 7)
		generators[player] = rng
	end
	return rng
end

function GamePassService:Owns(player: Player, key: string): boolean
	return GamePassConfig.owns(player, key)
end

-- Pushes pass perks into the saved profile and the client. Waits for the save
-- to load, because ownership is usually known before the profile is.
function GamePassService:_apply(player: Player)
	task.spawn(function()
		local data = self.Services.DataService
		local profile = if data.Await then data:Await(player, 30) else data:Get(player)
		if not profile or not player.Parent then return end
		local skills = self.Services.SkillTreeService
		if skills then
			pcall(function() skills:Recompute(player) end)
		end
		pcall(function() data:Sync(player) end)
	end)
end

function GamePassService:_grant(player: Player, key: string)
	if self:Owns(player, key) then return end
	player:SetAttribute(GamePassConfig.attribute(key), true)
	print(("[GamePass] %s now owns %s"):format(player.Name, key))
	self:_apply(player)
end

function GamePassService:_check(player: Player)
	local studioFresh = RunService:IsStudio() and GamePassConfig.StudioStartUnowned
	if studioFresh then
		print("[GamePass] Studio test mode: starting with no passes (GamePassConfig.StudioStartUnowned)")
	end
	for _, key in ipairs(if studioFresh then {} else GamePassConfig.Order) do
		local pass = GamePassConfig.Passes[key]
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
		end)
		if ok and owns then
			player:SetAttribute(GamePassConfig.attribute(key), true)
		elseif not ok then
			warn(("[GamePass] ownership check failed for %s / %s: %s"):format(player.Name, key, tostring(owns)))
		end
	end
	if player:GetAttribute("BattleSpeed") == nil then
		player:SetAttribute("BattleSpeed", 1)
	end
	self:_apply(player)
end

-- +35% Items. The bonus on a reward too small to take 35% of is paid as a
-- CHANCE instead: 1 item has a 35% chance of becoming 2, 10 items become 13
-- with a 50% chance of 14. Over many rewards that averages to exactly +35%,
-- and nobody is ever handed a fraction of an item.
function GamePassService:BoostItems(player: Player, amount: number): number
	local n = math.floor(tonumber(amount) or 0)
	if n <= 0 or not self:Owns(player, "MoreItems") then
		return n
	end
	local exact = n * (1 + GamePassConfig.ItemBonus)
	local whole = math.floor(exact + 1e-9)
	local fraction = exact - whole
	if fraction > 1e-9 and rngFor(player):NextNumber() < fraction then
		whole += 1
	end
	return whole
end

-- The speed the battle replay runs at for this player right now: 2 only for a
-- VIP who has switched the toggle on.
function GamePassService:BattleSpeed(player: Player): number
	if self:Owns(player, "VIP") and player:GetAttribute("BattleSpeed") == GamePassConfig.VipBattleSpeed then
		return GamePassConfig.VipBattleSpeed
	end
	return 1
end

function GamePassService:SetBattleSpeed(player: Player, speed: any)
	if not self:Owns(player, "VIP") then
		player:SetAttribute("BattleSpeed", 1)
		return false, "2x battle speed is a VIP perk"
	end
	local value = if speed == GamePassConfig.VipBattleSpeed then GamePassConfig.VipBattleSpeed else 1
	player:SetAttribute("BattleSpeed", value)
	return true, value
end

function GamePassService:Init()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		if not purchased then return end
		local pass = GamePassConfig.byId(passId)
		if pass then
			self:_grant(player, pass.key)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		generators[player] = nil
	end)
end

function GamePassService:Start()
	Players.PlayerAdded:Connect(function(player)
		self:_check(player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function() self:_check(player) end)
	end
end

return GamePassService
