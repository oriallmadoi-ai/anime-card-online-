--!strict
-- Owns the player's deck presets. The counts are GameConfig.DeckPresets
-- lineups of GameConfig.AttackSlots attack + GameConfig.SupportSlots support
-- slots - today 8 lineups of 5 and 5. They are named rather than written out
-- because this comment previously said 4 and 4 and had been wrong since the
-- slot counts changed.
--
-- A slot stores ONLY { cardId, variant }. The level is read live from the
-- inventory whenever the deck is used, so levelling a card immediately
-- strengthens the equipped copy instead of leaving a stale snapshot behind.
--
-- Everything is validated server-side against real ownership. A client that
-- could write its own deck could equip cards it never rolled, and the deck
-- feeds straight into combat.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local CardDefinitions = require(ReplicatedStorage.Shared.Config.CardDefinitions)
local SupportDefinitions = require(ReplicatedStorage.Shared.Config.SupportDefinitions)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
local CardStats = require(ReplicatedStorage.Shared.Util.CardStats)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local DeckService = {}
DeckService.Name = "DeckService"

local function slotCount(slotType: string): number
	return slotType == "attack" and GameConfig.AttackSlots or GameConfig.SupportSlots
end

-- Repairs the shape on demand: a profile that predates presets, or one whose
-- active index points at a preset that no longer exists, still works.
local function decksOf(profile)
	profile.decks = profile.decks or { active = 1, presets = {} }
	for i = 1, GameConfig.DeckPresets do
		profile.decks.presets[i] = profile.decks.presets[i] or { attack = {}, support = {} }
	end
	local active = profile.decks.active
	if typeof(active) ~= "number" or active < 1 or active > GameConfig.DeckPresets then
		profile.decks.active = 1
	end
	return profile.decks
end

function DeckService:ActivePreset(profile)
	local decks = decksOf(profile)
	return decks.presets[decks.active]
end

function DeckService:SetActive(player: Player, index: number)
	local profile = self.Services.DataService:Get(player)
	if not profile then return false, "no profile" end
	if typeof(index) ~= "number" or index % 1 ~= 0 then return false, "bad index" end
	if index < 1 or index > GameConfig.DeckPresets then return false, "preset out of range" end

	decksOf(profile).active = index
	self.Services.DataService:Sync(player)
	return true, "switched to deck " .. index
end

-- Returns ok, reason
function DeckService:Equip(player: Player, slotType: string, index: number, cardId: string?, variant: string?)
	local profile = self.Services.DataService:Get(player)
	if not profile then return false, "no profile" end

	if slotType ~= "attack" and slotType ~= "support" then return false, "bad slot type" end
	if typeof(index) ~= "number" or index % 1 ~= 0 then return false, "bad index" end
	if index < 1 or index > slotCount(slotType) then return false, "index out of range" end

	local preset = self:ActivePreset(profile)
	preset[slotType] = preset[slotType] or {}

	-- Clearing is always allowed.
	if cardId == nil then
		preset[slotType][index] = nil
		self.Services.DataService:Sync(player)
		return true, "cleared"
	end

	if typeof(cardId) ~= "string" or typeof(variant) ~= "string" then return false, "bad args" end
	if not VariantConfig.Data[variant] then return false, "unknown variant" end

	-- The card must go in the matching column: attack cards fight, supports
	-- assist from off-field, and they are not interchangeable.
	local isSupport = SupportDefinitions.get(cardId) ~= nil
	local isAttack = CardDefinitions.get(cardId) ~= nil
	if slotType == "attack" and not isAttack then return false, "that is not an attack card" end
	if slotType == "support" and not isSupport then return false, "that is not a support card" end

	-- Ownership checked against the real inventory, never trusted from the client.
	local entry = profile.cards[CardStats.key(cardId, variant)]
	if not entry or (entry.count or 0) < 1 then return false, "you do not own that copy" end

	-- The same copy cannot occupy two slots in the same lineup.
	for i, slot in pairs(preset[slotType]) do
		if i ~= index and slot and slot.cardId == cardId and slot.variant == variant then
			preset[slotType][i] = nil
		end
	end

	preset[slotType][index] = { cardId = cardId, variant = variant }
	self.Services.DataService:Sync(player)
	return true, "equipped"
end

-- Builds the active lineup in the shape CombatEngine expects, resolving levels live.
function DeckService:BuildCombatDeck(player: Player)
	local profile = self.Services.DataService:Get(player)
	if not profile then return nil end
	local preset = self:ActivePreset(profile)

	local out = { attack = {}, support = {} }
	for _, slotType in ipairs({ "attack", "support" }) do
		for i = 1, slotCount(slotType) do
			local slot = preset[slotType] and preset[slotType][i]
			if slot then
				local entry = profile.cards[CardStats.key(slot.cardId, slot.variant)]
				out[slotType][i] = {
					cardId = slot.cardId,
					variant = slot.variant,
					level = entry and entry.level or GameConfig.MinCardLevel,
				}
			end
		end
	end
	return out
end

function DeckService:IsEmpty(player: Player): boolean
	local deck = self:BuildCombatDeck(player)
	if not deck then return true end
	for _ in pairs(deck.attack) do return false end
	return true
end

function DeckService:Init()
	Remotes.RequestSetDeck.OnServerEvent:Connect(function(player, slotType, index, cardId, variant)
		local ok, reason = self:Equip(player, slotType, index, cardId, variant)
		if not ok then
			warn(("[DeckService] %s: %s"):format(player.Name, tostring(reason)))
		end
	end)

	Remotes.RequestSetActiveDeck.OnServerEvent:Connect(function(player, index)
		local ok, reason = self:SetActive(player, index)
		if not ok then
			warn(("[DeckService] %s: %s"):format(player.Name, tostring(reason)))
		end
	end)
end

return DeckService
