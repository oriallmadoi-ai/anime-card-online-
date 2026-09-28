-- Owner-only test commands. This script is intentionally isolated from the
-- normal roll/progression code: commands mutate or preview through public
-- service APIs and never change the live roll algorithm.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local DataService = require(script.Parent.Server.Services.DataService)
local RollService = require(script.Parent.Server.Services.RollService)
local CardDefinitions = require(ReplicatedStorage.Shared.Config.CardDefinitions)
local SupportDefinitions = require(ReplicatedStorage.Shared.Config.SupportDefinitions)
local CardStats = require(ReplicatedStorage.Shared.Util.CardStats)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SummonCoreConfig = require(ReplicatedStorage.Shared.Config.SummonCoreConfig)

-- Required on first use rather than at load, so this script never races the
-- server Bootstrap that initialises the service.
local function coreService()
	return require(script.Parent.Server.Services.SummonCoreService)
end

local ADMIN_USER_IDS = {
	[148861292] = true, -- origggg
}

-- Keyed by UserId, NOT by the Player instance.
--
-- /reset wipes the live profile and DataService will happily autosave that wipe,
-- so the snapshot is the only copy of the old progress. Keying it on the Player
-- meant a rejoin - or a disconnect right after a reset - threw the snapshot away
-- and made the wipe permanent. UserId keeps it alive for the life of the server.
local snapshots = {}

local function isAdmin(player)
	return ADMIN_USER_IDS[player.UserId] == true or (game.CreatorType == Enum.CreatorType.User and game.CreatorId == player.UserId)
end

local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, child in pairs(value) do
		result[key] = copy(child)
	end
	return result
end

local function restore(target, source)
	for key in pairs(target) do target[key] = nil end
	for key, value in pairs(source) do target[key] = copy(value) end
end

local function profileFor(player)
	return DataService:Await(player, 15)
end

local function announce(player, text)
	print(("[AdminCommand] %s: %s"):format(player.Name, text))
	player:SetAttribute("AdminCommandStatus", text)

	-- `message` is shown verbatim by UIController:Announce. This used to pass the
	-- status text as `cardId`, which the announce bar then wrapped in its own
	-- sentence and rendered as "ADMIN rolled Basic OK: previewed ...".
	Remotes.Announce:FireClient(player, {
		player = "ADMIN",
		message = text,
	})
end

local function resetProfile(player)
	local profile = profileFor(player)
	if not profile then return false, "profile is not loaded" end
	if not snapshots[player.UserId] then snapshots[player.UserId] = copy(profile) end

	-- Keep the profile object owned by DataService; clear and refill it so every
	-- existing service continues to reference the same authoritative table.
	local fresh = {
		version = profile.version,
		cards = {},
		decks = { active = 1, presets = {} },
		stats = { totalRolls = 0, rollsSincePity = 0, playtime = 0, joinCount = 0 },
		currency = { gems = 0, gold = 0, essence = 0, raidTokens = 0, elderCoins = 0 },
		skills = {},
		skillTreeSpent = 0,
		upgrades = { luck = 0, rollSpeed = 0, damage = 0 },
		books = {},
		items = {},
		encounters = {},
		summonCores = {},
		forgeItems = {},
		story = { world = 1, stage = 1, cleared = {} },
		settings = { quickRoll = true, autoDelete = {} },
	}
	restore(profile, fresh)
	DataService:Sync(player)
	return true, "progress reset"
end

local function gainBack(player)
	local profile = profileFor(player)
	local snapshot = snapshots[player.UserId]
	if not profile or not snapshot then return false, "no pre-reset snapshot exists" end
	restore(profile, snapshot)
	DataService:Sync(player)

	-- Write it through immediately. A restore that only lives in memory can be
	-- undone by a crash before the next autosave, which is the one failure mode
	-- this command exists to protect against.
	local saved = DataService:Save(player)
	return true, saved and "previous progress restored" or "restored in memory, SAVE FAILED"
end

local function findHighestOwned(profile)
	local bestId, bestVariant, bestRarity = nil, nil, -1
	for key in pairs(profile.cards or {}) do
		local cardId, variant = CardStats.parseKey(key)
		if cardId and variant then
			local def = CardDefinitions.Data[cardId] or SupportDefinitions.Data[cardId]
			if def then
				local effective = VariantConfig.effectiveRarity(def.baseRarity, variant)
				if effective > bestRarity then
					bestId, bestVariant, bestRarity = cardId, variant, effective
				end
			end
		end
	end
	return bestId, bestVariant, bestRarity
end

local function previewPull(player, index)
	-- A reveal preview does NOT need a profile.
	--
	-- It used to bail with "profile is not loaded", which made these commands
	-- useless in exactly the situation you most want them: a Studio session where
	-- DataStores are unreachable, so no profile ever loads. The profile is only
	-- consulted for two cosmetic details - the lucky counter and, for /pull5, the
	-- rarest card owned - and both have sane fallbacks.
	local profile = DataService:Get(player)

	-- ONE COMMAND PER REVEAL TIER. The variant rank is what picks the tier, so a
	-- single low card in each of the four borders walks the whole ladder:
	--   /pull1 Standard    -> quick      /pull3 Astral       -> major
	--   /pull2 Gilded      -> normal     /pull4 Transcendent -> cinematic
	-- /pull5 is the fifth tier: the full-screen personal-record sequence.
	local cardId, variant
	if index == 1 then
		cardId, variant = "Usopp", "Standard"
	elseif index == 2 then
		cardId, variant = "Usopp", "Gilded"
	elseif index == 3 then
		cardId, variant = "Usopp", "Astral"
	elseif index == 4 then
		cardId, variant = "Usopp", "Transcendent"
	else
		if profile then
			cardId, variant = findHighestOwned(profile)
		end
		if not cardId then
			cardId, variant = "Usopp", "Transcendent"
		end
	end

	local def = CardDefinitions.Data[cardId] or SupportDefinitions.Data[cardId]
	if not def then return false, "preview card is missing" end

	-- This is a reveal-only preview. It intentionally does not call AddCard,
	-- increment rolls, or alter the player's inventory/progression.
	local rarity = def.baseRarity
	local untilLucky = profile and RollService:RollsUntilLucky(profile) or 0

	-- `best` is what promotes a reveal to the full-screen record sequence, so it
	-- belongs to /pull5 ALONE. Sending it on every preview meant /pull3 and
	-- /pull4 both played the legend sequence instead of the major and cinematic
	-- tiers they are supposed to demonstrate - three of the five commands showed
	-- the same animation.
	--
	-- `preview` tells the reveal to ignore quick-roll. Without it /pull1 is
	-- silent whenever quick roll is on, because a quick-tier pull under quick
	-- roll is deliberately skipped - which looks exactly like a broken command.
	Remotes.RollResult:FireClient(player, {
		cardId = cardId,
		variant = variant,
		rarity = rarity,
		lucky = false,
		untilLucky = untilLucky,
		best = index == 5,
		preview = true,
	})
	return true, ("previewed %s %s"):format(VariantConfig.get(variant).display, def.name)
end

-- Summon Core test commands:
--   /givecore cosmic5        one Cosmic Summon Core V
--   /givecore gilded 4 3     three Gilded Summon Core IV
--   /givecore 21             stage number 1..21 works too
--   /allcores                one of every stage
--   /clearcores              remove every core and forge item
--   /giveessence [count]     Elder Core Essence (default 1)
--   /givewrench [count]      Elder Wrench (default 1)
local function giveCore(player, args)
	local stage, count = SummonCoreConfig.parse(args)
	if not stage then
		return false, "usage: /givecore <family><level> [count], e.g. /givecore cosmic5"
	end
	return coreService():Give(player, stage.id, count or 1)
end

local function runCommand(player, raw)
	if not isAdmin(player) then return end
	local command = string.lower((raw:match("^%s*(/%S+)") or ""))
	local args = raw:match("^%s*/%S+%s*(.-)%s*$") or ""
	local ok, message

	if command == "/reset" then
		ok, message = resetProfile(player)
	elseif command == "/gainback" then
		ok, message = gainBack(player)
	elseif command == "/givecore" then
		ok, message = giveCore(player, args)
	elseif command == "/allcores" then
		ok, message = coreService():GiveAll(player, tonumber(args) or 1)
	elseif command == "/clearcores" then
		ok, message = coreService():Clear(player)
	elseif command == "/giveessence" then
		ok, message = coreService():GiveItem(player, "CoreEssenceBasic", tonumber(args) or 1)
	elseif command == "/givewrench" then
		ok, message = coreService():GiveItem(player, "ElderWrench", tonumber(args) or 1)
	else
		local number = tonumber(command:match("^/pull([1-5])$"))
		if number then
			ok, message = previewPull(player, number)
		end
	end

	if ok ~= nil then announce(player, (ok and "OK: " or "ERROR: ") .. message) end
end

local function registerTextCommands()
	local folder = TextChatService:FindFirstChild("TextChatCommands")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "TextChatCommands"
		folder.Parent = TextChatService
	end
	local aliases = { "/reset", "/gainback", "/pull1", "/pull2", "/pull3", "/pull4", "/pull5",
		"/givecore", "/allcores", "/clearcores", "/giveessence", "/givewrench" }
	for _, alias in ipairs(aliases) do
		local command = folder:FindFirstChild("Admin_" .. alias:sub(2))
		if not command then
			command = Instance.new("TextChatCommand")
			command.Name = "Admin_" .. alias:sub(2)
			command.Parent = folder
		end
		command.PrimaryAlias = alias
		command.Triggered:Connect(function(textSource, unfilteredText)
			local player = Players:GetPlayerByUserId(textSource.UserId)
			if player then
				local ok, err = pcall(runCommand, player, unfilteredText or alias)
				if not ok then warn("[AdminCommand] " .. tostring(err)) end
			end
		end)
	end
end

local function setup(player)
	-- LEGACY CHAT ONLY.
	--
	-- Under TextChatService both this and the TextChatCommand fire for the same
	-- message, so every command ran TWICE - two reveals stacked on one /pull,
	-- and two lines in the log for one command. TextChatCommand is the correct
	-- path when it is available; Chatted is only the fallback for a place still
	-- on the legacy chat.
	if TextChatService.ChatVersion == Enum.ChatVersion.LegacyChatService then
		player.Chatted:Connect(function(message)
			local ok, err = pcall(runCommand, player, message)
			if not ok then warn("[AdminCommand] " .. tostring(err)) end
		end)
	end

	task.spawn(function()
		local profile = profileFor(player)
		if profile and not snapshots[player.UserId] then
			snapshots[player.UserId] = copy(profile)
		end
	end)
end

Players.PlayerAdded:Connect(setup)

-- Deliberately NOT clearing the snapshot on leave: see the note by `snapshots`.
-- Dropping it here is what made a reset-then-disconnect unrecoverable.

for _, player in ipairs(Players:GetPlayers()) do setup(player) end
registerTextCommands()

print("[AdminCommandService] owner-only chat commands online")
